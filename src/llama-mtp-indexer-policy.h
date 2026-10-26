#pragma once

// Internal, allocation-time policy. No environment reads or cache mutation here.
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace llama_mtp_indexer {

struct decision {
    bool requested = false;
    bool eligible  = false;
    bool enabled   = false;
    int64_t layer  = -1;
    int64_t ratio  = -1;
    const char * reason = "other_arch";
};

inline decision decide(const char * setting, bool qwen4exp, bool mtp, bool has_indexer,
                       uint32_t n_layer_all, uint32_t n_layer_nextn,
                       const uint32_t * ratios, size_t n_ratios) {
    decision out;
    out.requested = setting != nullptr && std::strcmp(setting, "1") == 0;
    if (!qwen4exp) {
        return out;
    }
    if (!mtp) {
        out.reason = "not_mtp";
        return out;
    }
    if (n_layer_nextn != 1) {
        out.reason = "unsupported_block_count";
        return out;
    }
    // n_layer() is n_layer_all - n_layer_nextn in the pinned graph. Validate
    // subtraction and both bounds before inspecting any compression ratio.
    if (n_layer_all < n_layer_nextn || ratios == nullptr) {
        out.reason = "invalid_layer";
        return out;
    }
    const uint32_t il = n_layer_all - n_layer_nextn;
    if (il >= n_layer_all || il >= n_ratios) {
        out.reason = "invalid_layer";
        return out;
    }
    out.layer = il;
    out.ratio = ratios[il];
    if (!has_indexer) {
        out.reason = "indexer_absent";
        return out;
    }
    if (out.ratio != 0) {
        out.reason = "compressed";
        return out;
    }
    out.eligible = true;
    out.enabled  = out.requested;
    out.reason   = out.enabled ? "dense_single_block" : "disabled";
    return out;
}

} // namespace llama_mtp_indexer
