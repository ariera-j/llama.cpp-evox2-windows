# R6 S9 G9-5 router / Open WebUI — measured 2026-10-29

**Verdict: PASS in a bounded 3-model Vulkan server test.** Post-release-tag runtime test of the existing b11908 binary (source SHA `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`). This is not a rebuild or a retag.

## Evidence / launch scope

User log `llama-r6-router-test.log`: 655,340 bytes, 9,654 lines, SHA256 `c2e361cc1ccfa1238f906be2a8453d398347c7abe269bdd6b576d1b7d0930522`. The original log is not committed because it contains local file paths.

On Windows 11 / EVO-X2 / Radeon 8060S, Vulkan server b11908 started as router on localhost port 8081. The existing `models.ini` registered 11 presets, with `--models-max 1 --models-autoload --parallel 1 --flash-attn auto --cache-ram 0 -b 2048 -ub 2048 -fit off --load-mode auto`. Optional speed flags were all OFF; all three model loads logged `QSA grouped-union = off`. User switched models using Open WebUI.

## Verified switch sequence

| Model | Child port | Complete responses | MTP Draft | Exit status |
| --- | ---: | ---: | --- | --- |
| Gemma4 31B QAT / `gemma-qat` | 53588 | 17 | ON, n_max=4 | 0 when switching to 26B |
| Gemma4 26B A4B / `gemma-qat-26b-a4b` | 53653 | 9 | ON, n_max=4 | 0 when switching to Qwen |
| Qwen3.8 FN IQ3 PLE16 | 53695 | 9 | ON, n_max=2 | 0 at shutdown |
| **Total** | | **35** | | **normal exits** |

All 35 completed requests recorded `truncated = 0` and PP/TG/Draft acceptance timing. The first model child exited with status 0 before the next child spawned, and likewise for the second switch. The router stopped the Qwen child normally. No error-level logs or OOM/crash were detected.

## Warnings and limits

- Qwen image requests: **24** `non-consecutive token position` warnings across two multimodal requests. Images decoded and generation continued; **image interpretation correctness is not validated**.
- Other warnings included model token corrections, cache-idle-slot disabled with `--cache-ram 0`, and backend notices.
- Router bound to localhost; its log warns that API key is absent and CORS is permissive. Do not expose unchanged settings on untrusted networks.
- Serial model management is validated, but full GPU/UMA memory release was not measured. No switch back to a previously unloaded model is demonstrated by this log.
- Built-in llama.cpp WebUI not tested (build disabled it); ROCm MTP-ON server, all model presets, sustained operation, and multimodal accuracy remain out of scope.

Decision: **G9-5 scoped PASS for Vulkan router + Open WebUI, three models, MTP ON, 35/35 completed responses**. Keep existing known-good installation for rollback; do not change the immutable source tag.
