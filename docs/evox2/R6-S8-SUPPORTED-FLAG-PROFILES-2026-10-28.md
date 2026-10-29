# R6 S8 supported flag profiles / G8-6 decision sheet - 2026-10-28

**Status: G8-6 RUNTIME PASS / FLAG DECISION FROZEN (2026-10-28 JST).** The [G8-6 measured closure](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md#g8-6-windows-measured-closure---2026-10-28-jst) and [S8 combined results](R6-S8-COMBINED-RESULTS-2026-10-28.md) cover the verified b11908 Vulkan/ROCm artifacts, Jinja, MTP-OFF/ON, the one 64k real document and the three user confirmations. Raw G8-6 ZIP SHA256: `6d143104949649cf89b3ffa6fa11b4a848eab61a0d2aaf9829871712b0395f38`. **All five source defaults remain OFF.** S7-A/B numerical Draft K/V parity and ROCm MTP-ON *server* evidence remain DEFER; do not interpret this as global default-ON approval.

## Flag and backend decision inventory (frozen S8 scope)

`PASS opt-in` means *only the tested model/backend/KV/graph conditions*, with explicit per-process flags. `DEFER` means unproven for supported use, not a finding of failure. `DISABLE` means do not enable in that backend profile. `upstream-covered` applies to unchanged upstream functionality, not these five independent S8 speed flags.

| Backend / model | Feature (environment key) | Existing evidence | S8 decision / restriction |
| --- | --- | --- | --- |
| Vulkan / Unsloth IQ3 PLE16 | S4 QSA union (`GGML_VK_QSA_UNION`) | f16 KV, G8-3/G8-5 and G8-6 real64 server `qsa-union active` | **PASS opt-in** for tested f16 KV / `MIN_KV=32768`; stock OFF remains supported |
| Vulkan / Unsloth IQ3 PLE16 | S5 DENSE (`LLAMA_MTP_SKIP_DENSE_INDEXER`) | Native state/rollback, MTP, long-input; G8-6 server all-ON MTP acceptance | **PASS opt-in** for eligible ratio-zero Draft on tested Qwen3.8 model; independent/default OFF |
| Vulkan / Unsloth IQ3 PLE16 | S6 NOOP (`LLAMA_QSA_SKIP_NOOP_INVALIDATION`) | Native 524/524, target NOOP, G8-5 and G8-6 server functional | **PASS opt-in** for eligible Qwen4Exp Target path; independent/default OFF |
| Vulkan / Unsloth IQ3 PLE16 | S7-A Stage-B (`LLAMA_MTP_DRAFT_PREFILL_KV_CROP`) | G8-4 output continuation 14/14 across cohorts; G8-5 256k stable | **DEFER** for supported preset: numerical Draft K/V state parity not proven; lab opt-in only |
| Vulkan / Unsloth IQ3 PLE16 | S7-B flatten (`LLAMA_MTP_EH_PROJ_FLATTEN`) | G8-4 output/acceptance parity; isolated incremental PP small and possible Defender confounder | **DEFER** for supported preset; requires Stage-B and separate K/V parity; lab opt-in only |
| Vulkan / Agention ROCmFP4 FAST PLE16 | S4/S5/S6 | Vulkan FP4 4k/64k/128k combined evidence; no G8-6 FP4 `llama-server` case | **DEFER** server profile, CLI-only opt-in evidence; **not** ROCm HIP FP4 kernel support |
| Vulkan / Agention ROCmFP4 FAST PLE16 | S7-A / S7-B | G8-4 output parity only, 64k single ordered C/A/B, no K/V snapshot | **DEFER** supported preset; lab opt-in only |
| ROCm / Unsloth IQ3 PLE16 | S4 Vulkan QSA union | Only a Vulkan implementation | **DISABLE**; unset/0 |
| ROCm / Unsloth IQ3 PLE16 | S5 DENSE and S6 NOOP | ROCm native/short and G8-3 real-input CLI; G8-6 MTP-OFF server functional PASS | **PASS opt-in (CLI MTP-ON, tested Qwen3.8 only)**; ROCm **MTP-OFF server PASS** separately. **ROCm MTP-ON server DEFER**, not exercised in G8-6 |
| ROCm / Unsloth IQ3 PLE16 | S7-A / S7-B | No independent ROCm Stage-B/flatten gate or Draft K/V parity | **DEFER**; leave OFF |
| ROCm / ROCmFP4 HIP model or other unseen quant | S2/Vulkan quant handling and S4-S7 | Not validated as HIP FP4 kernels or supported ROCmFP4 server profile | **DEFER**; do not infer from Vulkan loading |
| Gemma4, IQ4, huihui IQ4XS / other S9 models | S4-S7 | S8 Qwen3.8 evidence does not transfer to other model layouts | **DEFER** to S9; use known b10919 Gemma4 fallback |

The compatibility fixes S1 PLE16, S2 Vulkan ROCmFPx and S3 MTP format support are *required source paths*, not five automatically enabled speed knobs; upstream S0 behavior remains the stock MTP-OFF baseline. A running all-ON CLI test is **not** equivalent to a supported default-ON server deployment.

## Minimal, process-local switch profiles

All five flags default OFF in source. In each fresh PowerShell server terminal, set only the intended flags and make all other S8 flags `0`. Diagnostic flags remain unset. Never use `setx`, permanent registry/user environment settings, or a shared auto-start profile.

| Profile | S4 union | S5 DENSE | S6 NOOP | S7-A Stage-B | S7-B flatten | Scope |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `stock-off` | 0 | 0 | 0 | 0 | 0 | Same b11908, MTP OFF, no Draft args; normal compatibility path |
| `vk-iq3-conservative-candidate` | 1 | 1 | 1 | 0 | 0 | Vulkan IQ3 PLE16, f16 K/V, eligible MTP; supported *flag opt-in scope* from S8 tests, not separately asserted as a G8-6 server performance result |
| `vk-iq3-all-on-lab` | 1 | 1 | 1 | 1 | 1 | Vulkan IQ3 + Unsloth MTP DraftMax=2; G8-4/G8-5 and G8-6 functional PASS, but S7 numerical parity DEFER; **lab only** |
| `rocm-iq3-opt-in-candidate` | 0 | 1 | 1 | 0 | 0 | ROCm IQ3 PLE16 MTP-ON **CLI opt-in** from G8-3; do not claim ROCm MTP-ON `llama-server` approval |

For Vulkan S4 ON, additionally set `GGML_VK_QSA_UNION_MIN_KV=32768` and require log evidence of active-path eligibility in a sufficiently long f16-KV input. S7-B flatten has **no independent effect** unless Stage-B is ON. The G8-6 runbook's `vk-mtp` all-ON case is a *runtime probe*, not permission to promote all five into a stable preset.

## Frozen decisions and later revision triggers

1. Provenance, actual server and tokenizer hashes, observed per-case results, 64k usage/truncation and ZIP SHA are archived in the [combined results](R6-S8-COMBINED-RESULTS-2026-10-28.md). No further G8-6 run is required for the tested scope.
2. S7-A/B remain **DEFER** for generally supported presets without numerical Draft K/V evidence irrespective of output hashes. ROCm MTP-ON server and all S9 models remain **DEFER** pending separate targeted evidence.
3. Keep old verified b11903/b11906/S4/S5/S6/S0 and b10919 Gemma4 executable folders as rollback. Never overwrite the known-good bins or mark a new binary verified solely because documentation Git HEAD has moved.
4. The verified S8 b11908 Vulkan/ROCm artifacts are **eligible candidates for S9 model testing**, not a production-wide distribution release. S9 deployment/adoption is a separate gate.
