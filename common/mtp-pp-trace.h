// Evo-X2 experiment only: opt-in MTP prompt wall-time accounting.
// Never introduce extra GPU synchronization. This header is intentionally
// private to common/speculative.cpp and tools/server/server-context.cpp.
#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace mtp_pp_trace {

inline int mode() {
    // 0 = disabled, 1 = aggregate bins, 2 = bins + delayed per-ubatch records
    static const int value = []() {
        const char * env = std::getenv("LLAMA_MTP_PP_TRACE");
        if (!env || !*env || std::strcmp(env, "off") == 0 || std::strcmp(env, "0") == 0) {
            return 0;
        }
        if (std::strcmp(env, "detail") == 0) {
            return 2;
        }
        return std::strcmp(env, "bins") == 0 || std::strcmp(env, "1") == 0 ? 1 : 0;
    }();
    return value;
}

inline int64_t now_us() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

inline int depth_bin(int64_t end_pos) {
    const int64_t kv = end_pos + 1;
    if (kv <= 32768)  return 0;
    if (kv <= 65536)  return 1;
    if (kv <= 131072) return 2;
    if (kv <= 262144) return 3;
    return 4;
}

inline const char * bin_name(int b) {
    static const char * names[] = { "0-32768", "32769-65536", "65537-131072", "131073-262144", "262145+" };
    return names[b];
}

inline const char * phase_name(int phase) {
    return phase == 1 ? "prompt" : phase == 2 ? "mixed" : "generation";
}

struct sample {
    const char * role = "";  // "target" for server, "draft" for common/speculative
    int phase = 0;           // 1 prompt, 0 generation, 2 mixed (never silently assume batch size == phase)
    int64_t end_pos = 0;    // sequence token position, not allocated KV capacity
    int32_t n_tokens = 0;
    int64_t total_us = 0;
    int64_t target_us = 0;      // wall around server queued target decode
    int64_t target_sync_us = 0; // subset of target_us, do not add to parent
    int64_t spec_us = 0;        // wall around server speculative process
    int64_t hidden_get_us = 0;  // synchronizing target NextN getter; not pure transfer
    int64_t prepare_us = 0;     // draft input batch preparation
    int64_t draft_us = 0;       // draft llama_process call, not necessarily completed GPU time
    int64_t verify_copy_us = 0; // includes repeated _ith getter/sync and memcpy
};

struct bucket {
    uint64_t calls = 0;
    uint64_t tokens = 0;
    int64_t total = 0;
    int64_t target = 0;
    int64_t sync = 0;
    int64_t spec = 0;
    int64_t hidden = 0;
    int64_t prepare = 0;
    int64_t draft = 0;
    int64_t verify = 0;
};

class recorder {
public:
    explicit recorder(const char * role) : role_(role) {}

    void add(const sample & s) {
        if (!mode()) {
            return;
        }
        const int phase = s.phase >= 0 && s.phase <= 2 ? s.phase : 2;
        auto & b = bins_[phase * 5 + depth_bin(s.end_pos)];
        b.calls++;
        b.tokens  += static_cast<uint64_t>(s.n_tokens);
        b.total   += s.total_us;
        b.target  += s.target_us;
        b.sync    += s.target_sync_us;
        b.spec    += s.spec_us;
        b.hidden  += s.hidden_get_us;
        b.prepare += s.prepare_us;
        b.draft   += s.draft_us;
        b.verify  += s.verify_copy_us;
        if (mode() == 2) {
            rows_.push_back(s);
        }
    }

    ~recorder() {
        if (!mode()) {
            return;
        }
        for (int phase = 0; phase < 3; ++phase) {
            for (int depth = 0; depth < 5; ++depth) {
                const auto & b = bins_[phase * 5 + depth];
                if (!b.calls) {
                    continue;
                }
                std::fprintf(stderr,
                    "mtp_pp_trace_v1 type=bin role=%s phase=%s kv_bin=%s calls=%llu tokens=%llu"
                    " total_us=%lld target_us=%lld target_sync_us=%lld spec_us=%lld"
                    " hidden_get_us=%lld prepare_us=%lld draft_us=%lld verify_copy_us=%lld\n",
                    role_, phase_name(phase), bin_name(depth),
                    (unsigned long long) b.calls, (unsigned long long) b.tokens,
                    (long long) b.total, (long long) b.target, (long long) b.sync, (long long) b.spec,
                    (long long) b.hidden, (long long) b.prepare, (long long) b.draft, (long long) b.verify);
            }
        }
        for (const auto & s : rows_) {
            std::fprintf(stderr,
                "mtp_pp_trace_v1 type=row role=%s phase=%s end_pos=%lld n_tokens=%d"
                " total_us=%lld target_us=%lld target_sync_us=%lld spec_us=%lld"
                " hidden_get_us=%lld prepare_us=%lld draft_us=%lld verify_copy_us=%lld\n",
                role_, phase_name(s.phase), (long long) s.end_pos, (int) s.n_tokens,
                (long long) s.total_us, (long long) s.target_us, (long long) s.target_sync_us,
                (long long) s.spec_us, (long long) s.hidden_get_us, (long long) s.prepare_us,
                (long long) s.draft_us, (long long) s.verify_copy_us);
        }
        std::fflush(stderr);
    }

private:
    const char * role_;
    std::array<bucket, 15> bins_{};
    std::vector<sample> rows_;
};

} // namespace mtp_pp_trace
