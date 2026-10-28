# R6 S8 supported flag profiles / G8-6 decision sheet - 2026-10-28

**Status: PROVISIONAL / G8-6 NOT RUN.** Existing G8-0 through G8-5 tests are recorded, but **server/Jinja/real-document usability and the final S8 supported-profile freeze remain pending**. Do not turn provisional recommendations into defaults. Use the [G8-6 runbook](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md), then replace the `PENDING` column using actual G8-6 evidence and reference its ZIP SHA256.

## Flag and backend decision inventory (pre-freeze)

`PASS opt-in` means *only the tested model/backend/KV/graph conditions*, with explicit per-process flags. `DEFER` means unproven for supported use, not a finding of failure. `DISABLE` means do not enable in that backend profile. `upstream-covered` applies to unchanged upstream functionality, not these five independent S8 speed flags.

| Backend / model | Feature (environment key) | Existing evidence | Provisional G8-6 decision / prerequisite |
| --- | --- | --- | --- |
| Vulkan / Unsloth IQ3 PLE16 | S4 QSA union (`GGML_VK_QSA_UNION`) | f16 KV and union active in real long input; same-binary G8-3, G8-5 PASS | **PENDING** G8-6 server; candidate `PASS opt-in` for f16 KV, `MIN_KV=32768` |
| Vulkan / Unsloth IQ3 PLE16 | S5 DENSE (`LLAMA_MTP_SKIP_DENSE_INDEXER`) | Native state/rollback, MTP functional, long-input PASS | **PENDING** G8-6; candidate `PASS opt-in` for eligible ratio-zero Draft |
| Vulkan / Unsloth IQ3 PLE16 | S6 NOOP (`LLAMA_QSA_SKIP_NOOP_INVALIDATION`) | Native 524/524, target NOOP, G8-5 PASS | **PENDING** G8-6; candidate `PASS opt-in` for eligible Target invalidation |
| Vulkan / Unsloth IQ3 PLE16 | S7-A Stage-B (`LLAMA_MTP_DRAFT_PREFILL_KV_CROP`) | G8-4 output continuation 14/14 across cohorts; G8-5 256k stable | **DEFER** for supported preset: numerical Draft K/V state parity not proven; lab opt-in only |
| Vulkan / Unsloth IQ3 PLE16 | S7-B flatten (`LLAMA_MTP_EH_PROJ_FLATTEN`) | G8-4 output/acceptance parity; isolated incremental PP small and possible Defender confounder | **DEFER** for supported preset; requires Stage-B and separate K/V parity; lab opt-in only |
| Vulkan / Agention ROCmFP4 FAST PLE16 | S4/S5/S6 | Vulkan FP4 4k/64k/128k combined evidence; no G8-6 FP4 `llama-server` case | **DEFER** server profile, CLI-only opt-in evidence; **not** ROCm HIP FP4 kernel support |
| Vulkan / Agention ROCmFP4 FAST PLE16 | S7-A / S7-B | G8-4 output parity only, 64k single ordered C/A/B, no K/V snapshot | **DEFER** supported preset; lab opt-in only |
| ROCm / Unsloth IQ3 PLE16 | S4 Vulkan QSA union | Only a Vulkan implementation | **DISABLE**; unset/0 |
| ROCm / Unsloth IQ3 PLE16 | S5 DENSE and S6 NOOP | ROCm native/short and G8-3 real-input evidence | CLI candidate `PASS opt-in` for DENSE+NOOP only; **ROCm server PENDING** G8-6 MTP-OFF smoke (does not prove ROCm MTP-ON server) |
| ROCm / Unsloth IQ3 PLE16 | S7-A / S7-B | No independent ROCm Stage-B/flatten gate or Draft K/V parity | **DEFER**; leave OFF |
| ROCm / ROCmFP4 HIP model or other unseen quant | S2/Vulkan quant handling and S4-S7 | Not validated as HIP FP4 kernels or supported ROCmFP4 server profile | **DEFER**; do not infer from Vulkan loading |
| Gemma4, IQ4, huihui IQ4XS / other S9 models | S4-S7 | S8 Qwen3.8 evidence does not transfer to other model layouts | **DEFER** to S9; use known b10919 Gemma4 fallback |

The compatibility fixes S1 PLE16, S2 Vulkan ROCmFPx and S3 MTP format support are *required source paths*, not five automatically enabled speed knobs; upstream S0 behavior remains the stock MTP-OFF baseline. A running all-ON CLI test is **not** equivalent to a supported default-ON server deployment.

## Minimal, process-local switch profiles

All five flags default OFF in source. In each fresh PowerShell server terminal, set only the intended flags and make all other S8 flags `0`. Diagnostic flags remain unset. Never use `setx`, permanent registry/user environment settings, or a shared auto-start profile.

| Profile | S4 union | S5 DENSE | S6 NOOP | S7-A Stage-B | S7-B flatten | Scope |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `stock-off` | 0 | 0 | 0 | 0 | 0 | Same b11908, MTP OFF, no Draft args; normal compatibility path |
| `vk-iq3-conservative-candidate` | 1 | 1 | 1 | 0 | 0 | Vulkan IQ3 PLE16, f16 K/V, optional MTP; **G8-6/API validation still required** |
| `vk-iq3-all-on-lab` | 1 | 1 | 1 | 1 | 1 | Vulkan IQ3 + Unsloth MTP DraftMax=2, **experimental** G8-4/G8-5 reproduction and G8-6 test; parity DEFER |
| `rocm-iq3-opt-in-candidate` | 0 | 1 | 1 | 0 | 0 | ROCm IQ3 PLE16 with MTP; G8-3 CLI evidence, not a general ROCm server approval |

For Vulkan S4 ON, additionally set `GGML_VK_QSA_UNION_MIN_KV=32768` and require log evidence of active-path eligibility in a sufficiently long f16-KV input. S7-B flatten has **no independent effect** unless Stage-B is ON. The G8-6 runbook's `vk-mtp` all-ON case is a *runtime probe*, not permission to promote all five into a stable preset.

## Closing this sheet after evidence review

1. Record actual Vulkan+ROCm `llama-server` version and SHA, active backend, Jinja response, MTP-OFF behavior, multi-turn, real 64k token usage/truncation, tokenizer IDs/counts and G8-6 ZIP SHA.
2. Replace each relevant `PENDING` with `PASS opt-in`, `DEFER` or `DISABLE`, with tested model, quant, backend and restrictions. Keep S7-A/B **DEFER** without numerical Draft K/V evidence irrespective of output hashes. Keep S9 models **DEFER** pending their own gates.
3. Keep old verified b11903/b11906/S4/S5/S6/S0 and b10919 Gemma4 executable folders as rollback. Never overwrite the known-good bins or mark a new binary verified solely because documentation Git HEAD has moved.
4. Add finalized S8 result manifest (`R6-S8-COMBINED-RESULTS`), source/binary/DLL hashes and known limitations before designating S8 as the S9 candidate. No S9 deployment/adoption decision is made here.
