#include "common.h"
#include "llama-cpp.h"
#include "../src/llama-ext.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool condition, const std::string & message) {
    if (!condition) { throw std::runtime_error(message); }
}

static void set_env(const char * name, const char * value) {
#ifdef _WIN32
    require(_putenv_s(name, value ? value : "") == 0, "Cannot change test environment");
#else
    require((value ? setenv(name, value, 1) : unsetenv(name)) == 0, "Cannot change test environment");
#endif
}

struct env_guard {
    std::string name, old;
    bool present;
    explicit env_guard(const char * key) : name(key), present(std::getenv(key) != nullptr) {
        if (present) { old = std::getenv(key); }
    }
    ~env_guard() {
#ifdef _WIN32
        _putenv_s(name.c_str(), present ? old.c_str() : "");
#else
        if (present) { setenv(name.c_str(), old.c_str(), 1); } else { unsetenv(name.c_str()); }
#endif
    }
};

struct log_capture {
    std::mutex mutex;
    std::string text;
    log_capture() { llama_log_set(callback, this); }
    ~log_capture() { llama_log_set(nullptr, nullptr); }
    static void callback(ggml_log_level, const char * message, void * data) {
        auto & self = *static_cast<log_capture *>(data);
        std::lock_guard<std::mutex> lock(self.mutex);
        self.text += message;
        std::fputs(message, stderr);
    }
    void clear() { std::lock_guard<std::mutex> lock(mutex); text.clear(); }
    std::string get() { std::lock_guard<std::mutex> lock(mutex); return text; }
};

struct backend_guard {
    backend_guard() { ggml_backend_load_all(); llama_backend_init(); }
    ~backend_guard() { llama_backend_free(); }
};

struct output {
    std::vector<float> logits, hidden;
};

static bool compare(const std::vector<float> & reference, const std::vector<float> & actual,
                    const std::string & name) {
    require(!reference.empty() && reference.size() == actual.size(), name + ": missing/unequal output");
    double squared_error = 0, energy = 0;
    float max_abs = 0;
    for (size_t i = 0; i < reference.size(); ++i) {
        require(std::isfinite(reference[i]) && std::isfinite(actual[i]), name + ": non-finite output");
        const double delta = double(reference[i]) - actual[i];
        squared_error += delta * delta;
        energy += double(reference[i]) * reference[i];
        max_abs = std::max(max_abs, float(std::fabs(delta)));
    }
    // Same NMSE criterion as test-save-load-state. A zero reference has no
    // normalizing energy, so require exact zeros instead of dividing by zero.
    const double nmse = energy ? squared_error / energy : (squared_error ? INFINITY : 0.0);
    std::printf("QSA no-op invalidation: %s nmse=%.9g max_abs=%.9g\n", name.c_str(), nmse, double(max_abs));
    return nmse <= 1e-5;
}

static bool compare(const output & reference, const output & actual, const std::string & name) {
    const bool logits = compare(reference.logits, actual.logits, name + "/logits");
    const bool hidden = compare(reference.hidden, actual.hidden, name + "/hidden");
    return logits && hidden;
}

struct comparison_report {
    std::vector<std::string> failed;
    void check(const output & reference, const output & actual, const std::string & name) {
        if (!compare(reference, actual, name)) { failed.push_back(name); }
    }
    void require_ok() const {
        for (const auto & name : failed) {
            std::fprintf(stderr, "QSA no-op invalidation: numerical failure: %s\n", name.c_str());
        }
        require(failed.empty(), std::to_string(failed.size()) + " numerical comparisons exceed NMSE 1e-5");
    }
};

static output capture_output(llama_context * ctx) {
    llama_synchronize(ctx);
    const auto * model = llama_get_model(ctx);
    const int n_vocab = llama_vocab_n_tokens(llama_model_get_vocab(model));
    const int n_hidden = llama_model_n_embd_out(model);
    const auto * logits = llama_get_logits_ith(ctx, -1);
    const auto * hidden = llama_get_embeddings_nextn_ith(ctx, -1);
    require(logits && hidden && n_vocab > 0 && n_hidden > 0, "Missing MTP logits/nextn output");
    return {{logits, logits + n_vocab}, {hidden, hidden + n_hidden}};
}


static output decode(llama_context * ctx, int first, int count) {
    common_batch batch(ctx);
    const int vocab = llama_vocab_n_tokens(llama_model_get_vocab(llama_get_model(ctx)));
    for (int i=first; i<first+count; ++i) batch.add(3 + i % (vocab-3), i, 0, true);
    require(llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch.get()) == 0, "Target decode failed");
    return capture_output(ctx);
}
static void clear(llama_context * ctx) { llama_memory_clear(llama_get_memory(ctx), true); }
static std::vector<uint8_t> save(llama_context * ctx, llama_state_seq_flags flags) {
    llama_synchronize(ctx);
    std::vector<uint8_t> s(llama_state_seq_get_size_ext(ctx,0,flags));
    require(!s.empty() && llama_state_seq_get_data_ext(ctx,s.data(),s.size(),0,flags)==s.size(), "Incomplete state write");
    return s;
}
static void restore(llama_context * ctx, const std::vector<uint8_t> & s, llama_state_seq_flags flags) {
    const auto n=llama_state_seq_set_data_ext(ctx,s.data(),s.size(),0,flags);
    if(n!=s.size()) { clear(ctx); throw std::runtime_error("Incomplete restore; cleared"); }
}
static bool remove(llama_context * ctx,int p0,int p1) { return llama_memory_seq_rm(llama_get_memory(ctx),0,p0,p1); }

static void check_diagnostics(const std::string & text) {
    bool suppressed = false, pending = false, real_edit = false;
    std::istringstream lines(text);
    for (std::string line; std::getline(lines, line);) {
        if (line.find("mtp_diag ") == std::string::npos) { continue; }
        std::map<std::string, std::string> fields;
        std::istringstream words(line);
        for (std::string word; words >> word;) {
            const auto eq = word.find('=');
            if (eq != std::string::npos) { fields[word.substr(0, eq)] = word.substr(eq + 1); }
        }
        if (fields["kind"] != "end" || fields["event"] != "seq_rm" || !fields.count("idx_cells_before")) { continue; }
        const auto before = std::stoll(fields.at("idx_cells_before"));
        const auto after = std::stoll(fields.at("idx_cells_after"));
        if (fields.at("noop_suppressed") == "1") {
            require(before == after && fields.at("noop_observed") == "1" && fields.at("stale_marked") == "0",
                    "Suppressed removal changed membership or marked stale");
            require(fields.at("stale_before") == fields.at("stale_after"), "Suppressed removal lost pending stale");
            suppressed |= before > 0;
            if (fields.at("pending_stale_preserved") == "1") {
                require(std::stoll(fields.at("stale_before")) != std::numeric_limits<llama_pos>::max(), "False pending-stale evidence");
                pending = true;
            }
        } else if (before > after) {
            require(fields.at("stale_marked") == "1", "Real removal did not mark stale");
            real_edit = true;
        }
    }
    require(suppressed && pending && real_edit, "Missing real target suppression/pending-stale/real-edit evidence");
    require(text.find("event=layout") != std::string::npos, "Actual QSA layout path absent");
}
int main(int argc,char **argv) {
    try {
        std::string main_path; int ngl=999;
        for(int i=1;i<argc;++i) {
            require(i+1<argc,"Usage: test-qsa-noop-invalidation -m MAIN [-ngl N]");
            const std::string key=argv[i++];
            if(key=="-m") main_path=argv[i]; else if(key=="-ngl") ngl=std::stoi(argv[i]); else throw std::runtime_error("Unknown option");
        }
        require(!main_path.empty(),"Missing main model");
        env_guard e1("LLAMA_QSA_SKIP_NOOP_INVALIDATION"),e2("LLAMA_MTP_DIAG"),e3("LLAMA_MTP_SKIP_DENSE_INDEXER");
        set_env("LLAMA_MTP_DIAG","wall");set_env("LLAMA_MTP_SKIP_DENSE_INDEXER","1");
        backend_guard backend; log_capture log;
        auto mp=llama_model_default_params();mp.n_gpu_layers=ngl;mp.load_mtp=false;
        llama_model_ptr model(llama_model_load_from_file(main_path.c_str(),mp));require(bool(model),"Cannot load target model");
        auto cp=llama_context_default_params();cp.n_ctx=1024;cp.n_batch=64;cp.n_ubatch=32;
        cp.n_seq_max=1;cp.n_rs_seq=2;cp.n_threads=4;cp.n_threads_batch=4;
        cp.type_k=cp.type_v=GGML_TYPE_F16;cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_AUTO;
        comparison_report comparisons;
        for(unsigned seqs : {1u,2u}) {
            cp.n_seq_max=seqs;
            cp.kv_unified=seqs==2; // one stream with genuinely shared prefix cells
            set_env("LLAMA_QSA_SKIP_NOOP_INVALIDATION","0");log.clear();
            llama_context_ptr a(llama_init_from_model(model.get(),cp));require(bool(a),"Cannot initialize A");
            require(log.get().find("enabled=0 target=1 kpool=4")!=std::string::npos,"A target/pool decision absent");
            set_env("LLAMA_QSA_SKIP_NOOP_INVALIDATION","1");log.clear();
            llama_context_ptr b(llama_init_from_model(model.get(),cp));require(bool(b),"Cannot initialize B");
            require(log.get().find(seqs==1 ? "eligible=1 enabled=1 target=1 kpool=4" : "eligible=0 enabled=0 target=1 kpool=4")!=std::string::npos,"B eligibility mismatch");
            llama_set_embeddings_nextn(a.get(),true,false);llama_set_embeddings_nextn(b.get(),true,false);
            for(int base=32;base<36;++base) {
                for(int accepted=0;accepted<=2;++accepted) {
                    const auto stage = "seqs-" + std::to_string(seqs) + "/prefix-" + std::to_string(base) + "/accept-" + std::to_string(accepted);
                    std::printf("QSA no-op invalidation: running %s\n", stage.c_str()); std::fflush(stdout);
                    clear(a.get());clear(b.get());
                    comparisons.check(decode(a.get(),0,base),decode(b.get(),0,base),stage + "/prefix");
                    comparisons.check(decode(a.get(),base,3),decode(b.get(),base,3),stage + "/verify3");
                    const int keep=base+1+accepted;
                    const bool ar = remove(a.get(),keep,-1), br = remove(b.get(),keep,-1);
                    require(ar && br,"Supported suffix removal refused");
                    require(remove(a.get(),base+4,-1)==remove(b.get(),base+4,-1),"Pending-stale no-op differs");
                    comparisons.check(decode(a.get(),keep,1),decode(b.get(),keep,1),stage + "/continuation");
                    for(auto flags : {LLAMA_STATE_SEQ_FLAGS_NONE,LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY}) {
                        const auto state_stage = stage + (flags ? "/partial" : "/full");
                        auto sa=save(a.get(),flags),sb=save(b.get(),flags);require(sa.size()==sb.size(),"State size changed");
                        comparisons.check(decode(a.get(),keep+1,1),decode(b.get(),keep+1,1),state_stage + "/before-restore");
                        restore(a.get(),sa,flags);restore(b.get(),sb,flags);
                        require(remove(a.get(),keep+4,-1)==remove(b.get(),keep+4,-1),"Restored no-op differs");
                        require(remove(a.get(),keep+1,-1)==remove(b.get(),keep+1,-1),"Restored trim differs");
                        comparisons.check(decode(a.get(),keep+1,1),decode(b.get(),keep+1,1),state_stage + "/restored-continuation");
                        require(remove(a.get(),keep+1,-1)==remove(b.get(),keep+1,-1),"Reset suffix differs");
                    }
                }
                for(auto range : {std::pair<int,int>{100,101},{100,100},{101,100},{0,1},{4,5}}) {
                    const auto stage = "seqs-" + std::to_string(seqs) + "/prefix-" + std::to_string(base) + "/range-" + std::to_string(range.first) + "-" + std::to_string(range.second);
                    clear(a.get());clear(b.get());
                    comparisons.check(decode(a.get(),0,base),decode(b.get(),0,base),stage + "/prefix");
                    const bool ar=remove(a.get(),range.first,range.second),br=remove(b.get(),range.first,range.second);
                    require(ar==br,"Range/refusal return differs");
                    if(ar) comparisons.check(decode(a.get(),base,1),decode(b.get(),base,1),stage + "/continuation");
                }
            }
            if(seqs==1) {
                check_diagnostics(log.get());
            } else {
                // Real shared-prefix/copy/keep fallback, with the feature ineligible.
                clear(a.get());clear(b.get());decode(a.get(),0,32);decode(b.get(),0,32);
                for(auto *ctx : {a.get(),b.get()}) {
                    llama_memory_seq_cp(llama_get_memory(ctx),0,1,0,-1);
                }
                comparisons.check(decode(a.get(),32,1),decode(b.get(),32,1),"shared-prefix-fallback");
                require(remove(a.get(),100,-1)==remove(b.get(),100,-1),"Shared no-op return differs");
                for(auto *ctx : {a.get(),b.get()}) llama_memory_seq_keep(llama_get_memory(ctx),0);
                comparisons.check(decode(a.get(),33,1),decode(b.get(),33,1),"sharing-keep-fallback");
            }
            // Failed restore is followed by the same defensive clear used by the gate.
            auto sa=save(a.get(),LLAMA_STATE_SEQ_FLAGS_NONE),sb=save(b.get(),LLAMA_STATE_SEQ_FLAGS_NONE);
            require(sa.size()==sb.size(),"Final state size differs");
            sa.resize(1);sb.resize(1);
            const auto ar=llama_state_seq_set_data_ext(a.get(),sa.data(),sa.size(),0,LLAMA_STATE_SEQ_FLAGS_NONE);
            const auto br=llama_state_seq_set_data_ext(b.get(),sb.data(),sb.size(),0,LLAMA_STATE_SEQ_FLAGS_NONE);
            require(ar==br && ar!=sa.size(),"Malformed restore was accepted");clear(a.get());clear(b.get());
            comparisons.check(decode(a.get(),0,32),decode(b.get(),0,32),"after-failed-restore-clear");

            // Nonzero positions/gaps, repeated no-ops, then a real edit.
            clear(a.get());clear(b.get());
            require(remove(a.get(),0,0)==remove(b.get(),0,0),"Empty-sequence removal differs");
            comparisons.check(decode(a.get(),10,17),decode(b.get(),10,17),"offset-prefix");
            comparisons.check(decode(a.get(),30,3),decode(b.get(),30,3),"gapped-append");
            for(int repeat=0;repeat<2;++repeat) {
                require(remove(a.get(),33,-1) && remove(b.get(),33,-1),"Repeated no-op refused");
            }
            require(remove(a.get(),32,-1) && remove(b.get(),32,-1),"Post-no-op real edit refused");
            comparisons.check(decode(a.get(),32,1),decode(b.get(),32,1),"no-op-then-edit");
            // Drop all and reuse physical slots through the production allocator.
            require(remove(a.get(),0,-1) && remove(b.get(),0,-1),"Sequence drop refused");
            comparisons.check(decode(a.get(),0,32),decode(b.get(),0,32),"drop-and-slot-reuse");
            const bool shift_a = llama_memory_can_shift(llama_get_memory(a.get()));
            const bool shift_b = llama_memory_can_shift(llama_get_memory(b.get()));
            require(shift_a == shift_b, "Position-shift capability differs");
            if (shift_a) {
                for(auto *ctx : {a.get(),b.get()}) {
                    llama_memory_seq_add(llama_get_memory(ctx),0,0,-1,4);
                }
                comparisons.check(decode(a.get(),36,1),decode(b.get(),36,1),"position-shift");
                for(auto *ctx : {a.get(),b.get()}) {
                    llama_memory_seq_div(llama_get_memory(ctx),0,0,-1,2);
                }
                comparisons.check(decode(a.get(),19,1),decode(b.get(),19,1),"position-division");
            } else {
                std::puts("QSA no-op invalidation: position shift/division unsupported by both arms; capability unchanged");
            }
        }

        // No rollback snapshots: both contexts must preserve recurrent refusal,
        // including the untouched future cache and continuation.
        cp.n_seq_max=1;cp.n_rs_seq=0;cp.kv_unified=false;
        set_env("LLAMA_QSA_SKIP_NOOP_INVALIDATION","0");
        llama_context_ptr a(llama_init_from_model(model.get(),cp));require(bool(a),"Cannot initialize refusal A");
        set_env("LLAMA_QSA_SKIP_NOOP_INVALIDATION","1");
        llama_context_ptr b(llama_init_from_model(model.get(),cp));require(bool(b),"Cannot initialize refusal B");
        for(auto *ctx : {a.get(),b.get()}) llama_set_embeddings_nextn(ctx,true,false);
        comparisons.check(decode(a.get(),0,32),decode(b.get(),0,32),"refusal-prefix");
        require(!remove(a.get(),31,-1) && !remove(b.get(),31,-1),"Expected recurrent refusal changed");
        comparisons.check(decode(a.get(),32,1),decode(b.get(),32,1),"after-refused-edit");
        comparisons.require_ok();
        std::puts("QSA no-op invalidation: PASS (target numeric, pools, rollback, state and fallback)");return 0;
    } catch(const std::exception &e) { std::fprintf(stderr,"QSA no-op invalidation: FAIL: %s\n",e.what());return 1; }
}
