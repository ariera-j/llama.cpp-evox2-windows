#pragma once

#include "ggml.h"

#if defined(GGML_USE_HIP)

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace evox2_dense_gemm_trace {

struct settings {
    bool enabled;
    int layer;
    int64_t n;
    int limit;
};

static inline int read_int(const char * name, int fallback, int minimum, int maximum) {
    const char * value = std::getenv(name);
    if (!value || !value[0]) {
        return fallback;
    }
    char * end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    return end == value || *end != '\0' || parsed < minimum || parsed > maximum ? fallback : (int) parsed;
}

static inline const settings & get_settings() {
    static const settings cfg = []() {
        const char * enabled = std::getenv("GGML_HIP_GEMM_TRACE");
        return settings {
            enabled && std::strcmp(enabled, "1") == 0,
            read_int("GGML_HIP_GEMM_TRACE_LAYER", -1, 0, 4095),
            read_int("GGML_HIP_GEMM_TRACE_N", -1, 1, 1048576),
            read_int("GGML_HIP_GEMM_TRACE_LIMIT", 2048, 1, 100000)
        };
    }();
    return cfg;
}

static inline int get_layer(const char * name) {
    if (!name) {
        return -1;
    }
    const char * p = std::strstr(name, "blk.");
    if (!p) {
        return -1;
    }
    p += 4;
    if (*p < '0' || *p > '9') {
        return -1;
    }
    int layer = 0;
    while (*p >= '0' && *p <= '9') {
        layer = layer * 10 + (*p - '0');
        if (layer > 4095) {
            return -1;
        }
        ++p;
    }
    return *p == '.' || *p == '\0' ? layer : -1;
}

static inline void safe_name(const char * input, char * output, size_t capacity) {
    if (!input || !input[0]) {
        output[0] = '-';
        output[1] = '\0';
        return;
    }
    size_t i = 0;
    while (i + 1 < capacity && input[i]) {
        const unsigned char c = (unsigned char) input[i];
        output[i] = c <= 32 || c >= 127 || c == '=' ? '_' : (char) c;
        ++i;
    }
    output[i] = '\0';
}

static inline void record(const ggml_tensor * weight, const ggml_tensor * activation, const ggml_tensor * dst,
                          int device, const char * path, const char * compute_type = "-") {
    const settings & cfg = get_settings();
    if (!cfg.enabled || !weight || !activation || !dst || dst->op != GGML_OP_MUL_MAT) {
        return;
    }
    int layer = get_layer(weight->name);
    if (layer < 0) {
        layer = get_layer(dst->name);
    }
    if (layer < 0) {
        layer = get_layer(activation->name);
    }
    if ((cfg.layer >= 0 && layer != cfg.layer) || (cfg.n > 0 && activation->ne[1] != cfg.n)) {
        return;
    }

    static std::atomic<int> count{0};
    const int seq = count.fetch_add(1, std::memory_order_relaxed);
    if (seq >= cfg.limit) {
        if (seq == cfg.limit) {
            std::fprintf(stderr, "evox2_dense_gemm_v1 truncated_after=%d\n", cfg.limit);
        }
        return;
    }

    char weight_name[GGML_MAX_NAME + 1];
    char activation_name[GGML_MAX_NAME + 1];
    char dst_name[GGML_MAX_NAME + 1];
    safe_name(weight->name, weight_name, sizeof(weight_name));
    safe_name(activation->name, activation_name, sizeof(activation_name));
    safe_name(dst->name, dst_name, sizeof(dst_name));

    std::fprintf(stderr,
        "evox2_dense_gemm_v1 seq=%d device=%d layer=%d path=%s weight_type=%s activation_type=%s dst_type=%s compute_type=%s "
        "K=%lld M=%lld N=%lld w2=%lld w3=%lld a2=%lld a3=%lld weight=%s activation=%s dst=%s\n",
        seq + 1, device, layer, path, ggml_type_name(weight->type), ggml_type_name(activation->type),
        ggml_type_name(dst->type), compute_type, (long long) weight->ne[0], (long long) weight->ne[1],
        (long long) activation->ne[1], (long long) weight->ne[2], (long long) weight->ne[3],
        (long long) activation->ne[2], (long long) activation->ne[3], weight_name, activation_name, dst_name);
}

} // namespace evox2_dense_gemm_trace

#else

namespace evox2_dense_gemm_trace {
static inline void record(const ggml_tensor *, const ggml_tensor *, const ggml_tensor *, int, const char *,
                          const char * = "-") {}
}

#endif // defined(GGML_USE_HIP)
