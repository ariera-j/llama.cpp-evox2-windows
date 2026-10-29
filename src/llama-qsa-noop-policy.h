#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace llama_qsa_noop {

struct decision {
    bool requested = false;
    bool eligible = false;
    bool enabled = false;
    const char * reason = "other_arch";
};

inline decision decide(const char * setting, bool qwen4exp, bool target, bool indexer,
                       bool by_order, uint32_t pool, uint32_t sequences,
                       uint32_t streams, bool swa) {
    decision result;
    result.requested = setting && std::strcmp(setting, "1") == 0;
    if (!qwen4exp) {
        return result;
    }
    if (!target) {
        result.reason = "not_target";
        return result;
    }
    if (!indexer) {
        result.reason = "indexer_absent";
        return result;
    }
    if (!by_order || pool != 4) {
        result.reason = "unsupported_pool";
        return result;
    }
    if (sequences != 1 || streams != 1 || swa) {
        result.reason = "unsupported_cache";
        return result;
    }
    result.eligible = true;
    result.enabled = result.requested;
    result.reason = result.enabled ? "target_single_sequence" : "disabled";
    return result;
}

inline bool inspect(const decision & result, int32_t sequence, bool shared, bool diagnostics) {
    return result.eligible && sequence == 0 && !shared && (result.enabled || diagnostics);
}

inline bool suppress(const decision & result, bool inspected, size_t before, size_t after) {
    return result.enabled && inspected && before == after;
}

} // namespace llama_qsa_noop
