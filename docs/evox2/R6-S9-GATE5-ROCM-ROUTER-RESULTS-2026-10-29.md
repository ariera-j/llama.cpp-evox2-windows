# R6 G9-5 ROCm router + Open WebUI MTP-ON smoke — 2026-10-29

> **Decision: bounded PASS.** Post-tag validation on the **unchanged b11908 ROCm Windows binary** (source commit `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`, built with Clang 23.0.0). This does not change the public source tag, Vulkan Preview ZIP, or inference code.

## Evidence and reproducibility

User-provided Windows server logs (not uploaded to Git because they contain local paths):

| Evidence | Size | SHA256 | Scope |
| --- | ---: | --- | --- |
| `llama-r6-rocm-router-test.log` | 84,063 bytes | `16392eb9b0b39d5bcb83a8eab11831e69015c4c98496f26c3b1b36e0d98c26ea` | First 4k-context attempt |
| `llama-r6-rocm-router-test(1).log` | 248,545 bytes | `8b8cee06ccb3662f9231b53328b750dc53af59a510c0aca0a1b972b074bdf535` | Retest with 16k-context |

Test host: EVO-X2 / AMD Radeon 8060S, Windows 11, `ROCm0`, TheRock HIP runtime. The server read **11 presets** from the user's original `models.ini`, listened on **127.0.0.1:8082**, and used `--models-max 1 --models-autoload --parallel 1 --device ROCm0 --ctx-size 16384 -b 2048 -ub 1024 --flash-attn auto --reasoning off --cache-ram 0 -fit off --load-mode auto`. All five experimental speed flags were OFF; the models' individual INI entries supplied the Target+Draft model paths, GPU layer settings, and MTP draft sizes. Open WebUI was the client.

## 16k retest — serial model switching

| Sequence | Router model ID | Child port | Completed inference requests | MTP draft | Child termination |
| ---: | --- | ---: | ---: | --- | --- |
| 1 | Qwen3.8 Flash Next Unsloth IQ3 PLE16 | 63365 | **8** | `draft-mtp n_max=2` | Status **0** before Gemma31B load |
| 2 | `gemma-qat` (Gemma4 31B QAT) | 52213 | **4** | `draft-mtp n_max=4` | Status **0** before Gemma26B load |
| 3 | `gemma-qat-26b-a4b` (Gemma4 26B A4B) | 54450 | **4** | `draft-mtp n_max=4` | Status **0** at router shutdown |
| **Total** | **3 exercised presets / 11 registered** | | **16 completed** | Draft acceptance timings present for all 16 | **3 normal exits** |

The 16 completed requests each have `truncated = 0` and MTP acceptance/timing records. The log confirms **ROCm0 initialization and GPU model/Draft offload**, not CPU-only or Vulkan fallback. The router's old child exits with status 0 **before** the next child spawns; `--models-max 1` serial model control therefore worked in this test.

One additional Qwen request failed **at input validation**, not during GPU inference: `request (23190 tokens) exceeds the available context size (16384 tokens)`. The user enabled Web search for that request, which increased the input substantially. A subsequent short request still completed successfully. **16 successful generations + one rejected oversized request**, not 17 fully successful generations.

First 4k-context attempt: the small requests at **280, 272, 267 tokens** completed successfully with Draft MTP, but **6394, 6202 and 6197-token** requests exceeded a `4096`-token context and were rejected. Based on the user's Open WebUI observation, small jobs are consistent with automatic chat title generation; the request text is **not** logged, so this attribution is *probable, not confirmed*. A system prompt alone cannot be established as the cause of the ~6k tokens.

At 16k, Qwen successfully handled prompt sizes including **6202, 6555, 14819 and 14884 tokens**; the 23190-token Web-search request was larger than the 16384 limit. For a later functional Web-search test, `--ctx-size 32768` may allow that particular request, but the result is **not tested** and search snippets can still overflow.

## Gate decision / caveats

- **ROCm b11908 MTP-ON server + Open WebUI router: scoped PASS** for short-use serial switch and 16/16 accepted requests on **three models**. No HIP GPU reset, crash, or child termination error in the uploaded retest log.
- This is a **runtime acceptance test**. No long soak, concurrent models, strict GPU/UMA memory-return measurement, image grounding correctness, complete preset coverage, Web-search large-context success, or numeric Draft K/V parity was performed.
- The user used loopback-only binding; parent server warnings explicitly indicate no API key / permissive CORS and warn against exposure of router mode. Do not extrapolate to LAN/public deployment.
- The b11908 inference source and public tag `evox2-integrated-2026-10-29` remain frozen. The Vulkan-only public pre-release does **not** include ROCm binaries.
- **r6 public candidate validation can be marked CLOSED for its explicitly bounded S8/S9 acceptance scope.** Deferred research items remain DEFER (particularly S7 numeric Draft K/V parity, long-duration stability, multimodal precision, and ROCm 128k/256k PP/TG optimization). This closure is not a statement of fully supported production quality.

Related: [Vulkan router G9-5](R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md), [S9 validation runbook](R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md), [S8/S9 support flags](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md).
