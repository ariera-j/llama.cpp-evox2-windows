#pragma once
#include "../ggml/src/ggml-mtp-diag.h"
#include "llama-impl.h"
inline void llama_mtp_diag_emit(const char * line) { LLAMA_LOG_INFO("%s", line); }
