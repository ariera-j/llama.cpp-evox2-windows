#pragma once
#include "../ggml/src/ggml-mtp-diag.h"
#include "llama.h"
#include "log.h"

inline void common_mtp_diag_emit(const char * line) { LOG_INF("%s", line); }

inline void common_mtp_diag_wait(llama_context * ctx, const char * role, const char * event, const char * phase = nullptr) {
    if (!mtp_diag::synchronized()) { return; }
    mtp_diag::scope timing("common", event, ctx, role, common_mtp_diag_emit, phase);
    llama_synchronize(ctx);
}

inline void common_mtp_diag_register(llama_context * ctx, const char * role) {
    if (!mtp_diag::enabled() || !ctx) { return; }
    mtp_diag::scope timing("common", "context", ctx, role, common_mtp_diag_emit, "setup");
    timing.pointer("mem", llama_get_memory(ctx));
}
