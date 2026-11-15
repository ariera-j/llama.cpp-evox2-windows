#pragma once

#if defined(GGML_USE_HIP)

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace evox2_moe_trace {

inline bool enabled() {
    static const bool on = [] {
        const char * env = std::getenv("GGML_HIP_MOE_TRACE");
        return env != nullptr && std::strcmp(env, "1") == 0;
    }();
    return on;
}

inline long layer_of(const char * name) {
    const char * begin = std::strstr(name, "blk.");
    if (!begin || begin[4] < '0' || begin[4] > '9') {
        return -1;
    }
    char * end = nullptr;
    const long layer = std::strtol(begin + 4, &end, 10);
    return end && *end == '.' ? layer : -1;
}

inline const char * role_of(const char * name) {
    if (std::strstr(name, "ffn_gate_up_exps")) return "gate_up";
    if (std::strstr(name, "ffn_gate_exps")) return "gate";
    if (std::strstr(name, "ffn_up_exps")) return "up";
    if (std::strstr(name, "ffn_down_exps")) return "down";
    return "other";
}

inline void record(
        const ggml_tensor * weight, const ggml_tensor * activation, const ggml_tensor * ids,
        const ggml_tensor * dst, int device, const char * path, int tile_j, bool edge_fallback, ggml_prec prec) {
    if (!enabled() || ids == nullptr) return;

    static const long filter_layer = [] {
        const char * env = std::getenv("GGML_HIP_MOE_TRACE_LAYER");
        return env && *env ? std::strtol(env, nullptr, 10) : -1L;
    }();
    static const long long filter_tokens = [] {
        const char * env = std::getenv("GGML_HIP_MOE_TRACE_N");
        return env && *env ? std::strtoll(env, nullptr, 10) : -1LL;
    }();
    static const unsigned limit = [] {
        const char * env = std::getenv("GGML_HIP_MOE_TRACE_LIMIT");
        const long value = env && *env ? std::strtol(env, nullptr, 10) : 2048L;
        return value >= 1 && value <= 8192 ? (unsigned) value : 2048u;
    }();

    const long layer = layer_of(weight->name);
    const long long n = (long long) activation->ne[2];
    if ((filter_layer >= 0 && layer != filter_layer) || (filter_tokens >= 0 && n != filter_tokens)) return;

    static std::atomic<unsigned> matched { 0 };
    const unsigned seq = matched.fetch_add(1, std::memory_order_relaxed) + 1;
    if (seq > limit) {
        if (seq == limit + 1) {
            std::fprintf(stderr, "evox2_moe_dispatch_v1 truncated_after=%u\n", limit);
        }
        return;
    }

    std::fprintf(stderr,
            "evox2_moe_dispatch_v1 seq=%u layer=%ld role=%s path=%s N=%lld device=%d"
            " weight_type=%s K=%lld M=%lld n_experts=%lld n_used=%lld"
            " J=%d edge_fallback=%d prec=%d dedup_bcast=%d weight=%s activation=%s dst=%s\n",
            seq, layer, role_of(weight->name), path, n, device, ggml_type_name(weight->type),
            (long long) weight->ne[0], (long long) weight->ne[1], (long long) weight->ne[2],
            (long long) ids->ne[0], tile_j, edge_fallback ? 1 : 0, (int) prec,
            activation->ne[1] == 1 && ids->ne[0] > 1 ? 1 : 0,
            weight->name, activation->name, dst->name);
}
} // namespace evox2_moe_trace
#endif // GGML_USE_HIP
