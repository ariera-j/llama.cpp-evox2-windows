#include "common.h"
#include "llama-cpp.h"
#include "../src/llama-ext.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
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

static void compare(const std::vector<float> & reference, const std::vector<float> & actual,
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
    std::printf("MTP dense indexer: %s nmse=%.9g max_abs=%.9g\n", name.c_str(), nmse, double(max_abs));
    require(nmse <= 1e-5, name + ": NMSE exceeds state-test threshold");
}

static void compare(const output & reference, const output & actual, const std::string & name) {
    compare(reference.logits, actual.logits, name + "/logits");
    compare(reference.hidden, actual.hidden, name + "/hidden");
}

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

struct trace {
    llama_tokens tokens;
    std::vector<std::vector<float>> hidden;
};

static trace make_trace(llama_context * target) {
    const std::string prompt = "Please explain how a careful implementation checks cache state, "
        "replays rejected draft tokens, and validates a deterministic sequence of predictions.";
    trace result;
    result.tokens = common_tokenize(target, prompt, true, true);
    require(result.tokens.size() >= 12, "Test prompt needs at least twelve target tokens");
    result.tokens.resize(12);
    common_batch batch(target);
    for (size_t i = 0; i < result.tokens.size(); ++i) { batch.add(result.tokens[i], i, 0, true); }
    require(llama_process(target, LLAMA_PROCESS_TYPE_DECODE, batch.get()) == 0, "Target trace decode failed");
    llama_synchronize(target);
    const int width = llama_model_n_embd_out(llama_get_model(target));
    result.hidden.assign(result.tokens.size(), std::vector<float>(width, 0.0f));
    // Same pairing as draft-mtp catch-up: the initial carry is zero, subsequent
    // tokens consume the preceding target row. Keep copies across draft evals.
    for (size_t i = 1; i < result.tokens.size(); ++i) {
        const float * row = llama_get_embeddings_nextn_ith(target, i - 1);
        require(row != nullptr, "Missing target hidden trace row");
        std::copy(row, row + width, result.hidden[i].begin());
    }
    return result;
}

static void check_positions(llama_context * ctx, llama_pos expected, const std::string & stage) {
    const auto memory = llama_get_memory(ctx);
    const auto min = llama_memory_seq_pos_min(memory, 0);
    const auto max = llama_memory_seq_pos_max(memory, 0);
    // These public APIs report the intersection of attention and recurrent
    // ranges, not attention alone. With n_seq_max=1 and n_rs_seq=0, even the
    // empty MTP recurrent cache tracks one cell at the latest position. Thus
    // hybrid min=max=latest; attention history is checked by replay outputs.
    require(min == expected && max == expected,
            stage + ": hybrid sequence positions min=" + std::to_string(min) +
            " max=" + std::to_string(max) + " expected=" + std::to_string(expected));
}

static output decode(llama_context * ctx, const trace & input, int first, int count,
                     const std::string & stage) {
    require(first >= 0 && count > 0 && size_t(first + count) <= input.tokens.size(), "Invalid trace slice");
    common_batch batch(ctx);
    for (int i = first; i < first + count; ++i) {
        const int slot = batch.add(input.tokens[i], i, 0, true);
        require(batch.set_embd(slot, {input.hidden[i].data(), 1, input.hidden[i].size()}), "Cannot pair MTP input");
    }
    require(llama_process(ctx, LLAMA_PROCESS_TYPE_DECODE, batch.get()) == 0, stage + ": MTP decode failed");
    check_positions(ctx, first + count - 1, stage);
    return capture_output(ctx);
}

static void clear(llama_context * ctx) {
    llama_synchronize(ctx);
    llama_memory_clear(llama_get_memory(ctx), true);
}

static std::vector<uint8_t> save(llama_context * ctx, llama_state_seq_flags flags) {
    llama_synchronize(ctx);
    const size_t size = llama_state_seq_get_size_ext(ctx, 0, flags);
    require(size != 0, "Empty saved state");
    std::vector<uint8_t> state(size);
    require(llama_state_seq_get_data_ext(ctx, state.data(), size, 0, flags) == size, "Incomplete state write");
    return state;
}

static void restore(llama_context * ctx, const std::vector<uint8_t> & state, llama_state_seq_flags flags) {
    llama_synchronize(ctx);
    const size_t read = llama_state_seq_set_data_ext(ctx, state.data(), state.size(), 0, flags);
    if (read != state.size()) {
        clear(ctx);
        throw std::runtime_error("Incomplete state read; context cleared");
    }
}

struct checks {
    std::vector<output> outputs;
    size_t full_size = 0, partial_size = 0;
};

static checks exercise(llama_context * ctx, const trace & input, const std::string & arm) {
    checks result;
    clear(ctx);
    result.outputs.push_back(decode(ctx, input, 0, 6, arm + "/prefix"));
    result.full_size = save(ctx, LLAMA_STATE_SEQ_FLAGS_NONE).size();
    result.partial_size = save(ctx, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY).size();
    result.outputs.push_back(decode(ctx, input, 6, 1, arm + "/append")); // append-only
    const auto max_before = llama_memory_seq_pos_max(llama_get_memory(ctx), 0);
    require(llama_memory_seq_rm(llama_get_memory(ctx), 0, max_before + 1, -1), "No-op suffix removal refused");
    check_positions(ctx, max_before, arm + "/no-op-remove");
    result.outputs.push_back(decode(ctx, input, 7, 1, arm + "/no-op-append"));

    for (int accepted = 0; accepted <= 2; ++accepted) {
        clear(ctx);
        const auto stage = arm + "/accept-" + std::to_string(accepted);
        decode(ctx, input, 0, 8, stage + "/speculate"); // prefix of six, plus two speculative rows
        require(llama_memory_seq_rm(llama_get_memory(ctx), 0, 6 + accepted, -1), "Speculative suffix removal refused");
        check_positions(ctx, 5 + accepted, stage + "/trim");
        const auto after_trim = decode(ctx, input, 6 + accepted, 1, stage + "/replay");
        clear(ctx);
        const auto reference = decode(ctx, input, 0, 7 + accepted, stage + "/reference");
        compare(reference, after_trim, stage);
        result.outputs.push_back(after_trim);
    }

    for (auto flags : {LLAMA_STATE_SEQ_FLAGS_NONE, LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY}) {
        clear(ctx);
        const auto stage = arm + (flags ? "/partial-restore" : "/full-restore");
        decode(ctx, input, 0, 6, stage + "/prefix");
        const auto state = save(ctx, flags);
        const auto expected = decode(ctx, input, 6, 1, stage + "/expected");
        decode(ctx, input, 7, 1, stage + "/extra");
        restore(ctx, state, flags);
        // PARTIAL_ONLY restores recurrent state, not attention/indexer cells.
        // This is the same restore-then-trim order used by speculative rollback.
        if (flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) {
            require(llama_memory_seq_rm(llama_get_memory(ctx), 0, 6, -1), "Restored suffix removal refused");
        }
        check_positions(ctx, 5, stage + "/restored");
        const auto actual = decode(ctx, input, 6, 1, stage + "/continue");
        compare(expected, actual, stage);
        result.outputs.push_back(actual);
    }
    return result;
}

static llama_context_ptr draft_context(llama_model * model, llama_context_params params,
                                       const char * setting, log_capture & log) {
    env_guard restore_env("LLAMA_MTP_SKIP_DENSE_INDEXER");
    set_env("LLAMA_MTP_SKIP_DENSE_INDEXER", setting);
    log.clear();
    params.ctx_type = LLAMA_CONTEXT_TYPE_MTP;
    llama_context_ptr ctx(llama_init_from_model(model, params));
    require(ctx != nullptr, "Cannot initialize draft context");
    const std::string marker = std::string("MTP dense indexer: requested=") + setting +
        " eligible=1 omitted=" + setting + " ";
    require(log.get().find(marker) != std::string::npos, "Missing eligible/effective candidate startup evidence");
    llama_set_embeddings_nextn(ctx.get(), true, true);
    return ctx;
}

int main(int argc, char ** argv) {
    try {
        std::string main_path, draft_path;
        int gpu_layers = 999;
        for (int i = 1; i < argc; ++i) {
            const std::string key = argv[i];
            require(i + 1 < argc, "Usage: test-mtp-dense-indexer -m MAIN -md DRAFT [-ngl N]");
            if (key == "-m") { main_path = argv[++i]; }
            else if (key == "-md") { draft_path = argv[++i]; }
            else if (key == "-ngl") { gpu_layers = std::stoi(argv[++i]); }
            else { throw std::runtime_error("Unknown argument: " + key); }
        }
        require(!main_path.empty() && !draft_path.empty(), "Explicit main/draft model paths are required; no model test was run");
        env_guard diagnostic_env("LLAMA_MTP_DIAG");
        env_guard candidate_env("LLAMA_MTP_SKIP_DENSE_INDEXER");
        set_env("LLAMA_MTP_DIAG", "off");
        backend_guard backends;
        log_capture log;
        auto mp = llama_model_default_params();
        mp.n_gpu_layers = gpu_layers;
        mp.load_mtp = false;
        llama_model_ptr main_model(llama_model_load_from_file(main_path.c_str(), mp));
        mp.load_mtp = true;
        llama_model_ptr draft_model(llama_model_load_from_file(draft_path.c_str(), mp));
        require(main_model && draft_model, "Cannot load test models");
        for (auto * model : {main_model.get(), draft_model.get()}) {
            char arch[64]{};
            require(llama_model_meta_val_str(model, "general.architecture", arch, sizeof(arch)) > 0 &&
                    std::strcmp(arch, "qwen4exp") == 0, "This model-dependent gate requires QWEN4EXP");
        }
        require(llama_model_n_embd_out(main_model.get()) == llama_model_n_embd_out(draft_model.get()) &&
                llama_vocab_n_tokens(llama_model_get_vocab(main_model.get())) ==
                llama_vocab_n_tokens(llama_model_get_vocab(draft_model.get())), "Target/draft widths or vocabularies differ");
        auto cp = llama_context_default_params();
        cp.n_ctx = 1024; cp.n_batch = 32; cp.n_ubatch = 32;
        cp.n_seq_max = 1; cp.n_rs_seq = 0;
        cp.n_threads = 4; cp.n_threads_batch = 4;
        cp.type_k = GGML_TYPE_F16; cp.type_v = GGML_TYPE_F16;
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
        set_env("LLAMA_MTP_SKIP_DENSE_INDEXER", "1");
        log.clear();
        llama_context_ptr target(llama_init_from_model(main_model.get(), cp));
        require(target != nullptr, "Cannot initialize target context");
        require(log.get().find("creating indexer KV cache") != std::string::npos,
                "Target QSA indexer disappeared with candidate requested");
        llama_set_embeddings_nextn(target.get(), true, false);
        const auto input = make_trace(target.get());
        auto a = draft_context(draft_model.get(), cp, "0", log);
        auto b = draft_context(draft_model.get(), cp, "1", log);
        const auto results_a = exercise(a.get(), input, "A");
        const auto results_b = exercise(b.get(), input, "B");
        require(results_a.outputs.size() == results_b.outputs.size(), "Unequal check counts");
        for (size_t i = 0; i < results_a.outputs.size(); ++i) {
            compare(results_a.outputs[i], results_b.outputs[i], "A/B-" + std::to_string(i));
        }
        require(results_a.full_size > results_b.full_size, "No actual draft indexer state was omitted");
        require(results_a.partial_size == results_b.partial_size, "PARTIAL_ONLY checkpoint format changed");
        std::printf("MTP dense indexer: full_state_bytes A=%zu B=%zu partial_state_bytes=%zu\n",
                    results_a.full_size, results_b.full_size, results_a.partial_size);
        std::puts("MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)");
        return 0;
    } catch (const std::exception & error) {
        std::fprintf(stderr, "MTP dense indexer: FAIL: %s\n", error.what());
        return 1;
    }
}
