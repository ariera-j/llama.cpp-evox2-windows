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
    decision d;
    d.requested = setting && std::strcmp(setting, "1") == 0;
    if (!qwen4exp) return d;
    if (!target) { d.reason = "not_target"; return d; }
    if (!indexer) { d.reason = "indexer_absent"; return d; }
    if (!by_order || pool != 4) { d.reason = "unsupported_pool"; return d; }
    if (sequences != 1 || streams != 1 || swa) { d.reason = "unsupported_cache"; return d; }
    d.eligible = true;
    d.enabled = d.requested;
    d.reason = d.enabled ? "target_single_sequence" : "disabled";
    return d;
}
inline bool inspect(const decision & d, int32_t sequence, bool shared, bool diagnostics) {
    return d.eligible && sequence == 0 && !shared && (d.enabled || diagnostics);
}
inline bool suppress(const decision & d, bool inspected, size_t before, size_t after) {
    return d.enabled && inspected && before == after;
}
} // namespace llama_qsa_noop
