# R6/S8 combined integration candidate: result and S9 handoff - 2026-10-28

> **New downstream measured evidence (2026-10-29 JST):** [Consolidated S0→S9 PP/TG inventory, G8-3 six raw ZIP hashes and the 21-run gap-fill plus standalone ROCm all-five CLI smoke](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md). The downstream speed results support the user's next **ROCm long-context PP+TG profiling priority**. This **does not reopen S8 gates or change the frozen S8 supported flags**: ROCm all-five ON was a **single CLI stability test only**, not numerical Draft K/V parity or router-mode PASS, and ROCm release defaults remain unpromoted.


> **S9 measured downstream update (2026-10-29 JST):** [Qwen original IQ4 and huihui measured G9-0/1/2/3 results](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md) are recorded: 4/4 short, 3/3 real 64k/selected 128k and **4/4 bounded MH-128K A/B execution/score checks**, with **original IQ4 A/B both 12/12, huihui A 12/12, huihui B 11/12**. Original IQ4 B follow-up is now complete; proceed to independent Gemma4 G9-4 preflight. G9-5 and public release are not approved. This does not change the S8 flag freeze or reopen the integration gates.

> **S9 handoff procedure prepared (2026-10-28; not yet run):** [S9 Windows final-model gates](R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md) and two filtered model smoke/long-input plans. This is a downstream testing handoff; the S8 b11908 evidence and flag freeze documented below are unchanged.

## Status and evidence boundary

**S8 candidate integration gates G8-0 through G8-6 closed for their explicitly tested cases.** The [G8-6 runtime result](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md#g8-6-windows-measured-closure---2026-10-28-jst) and the user's three confirmations permit **S9 final-model testing**, but do **not** approve general distribution, all-flags-ON defaults, numerical Draft K/V parity, ROCm MTP-ON server or unseen model/quant paths. Follow the frozen [flag decision sheet](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md).

This document is a compact index of independently preserved gate results, **not** a new cross-build speed comparison or reanalysis of missing raw matrix archives. All raw ZIPs, GGUFs, private input text and machine-local `local.psd1` stay outside the repository. The exact measured executable source is `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f` / **b11908**, even though docs-only GitHub commits have advanced the branch tip.

| Gate | Measured/verified scope | S8 disposition / evidence source |
| --- | --- | --- |
| G8-0/1 | Cumulative S1-S7-B sources, separately verified b11908 Vulkan and TheRock 10.0 ROCm builds; native S5/S6 regression and Vulkan targeted S2 numerical checks | **PASS in preceding gate review**; build/native reproduction [runbook](R6-S8-GATE1-GATE2-TEST-RUNBOOK-2026-10-28.md) |
| G8-2 | Combined-binary MTP-OFF/ON, IQ3/FP4 Vulkan and IQ3 ROCm short cases; DraftMax=7 bounded smoke | **PASS in preceding gate review**; see [G8-1/2 runbook](R6-S8-GATE1-GATE2-TEST-RUNBOOK-2026-10-28.md) and [S8 plan](R6-S8-COMBINED-INTEGRATION-PLAN-2026-10-28.md) |
| G8-3 | Same-binary real 64/128k ABBA/A-B, Vulkan IQ3/FP4 and ROCm IQ3 with only eligible flags | **PASS in preceding gate review**, no additive optimization percentages inferred; [S8 plan](R6-S8-COMBINED-INTEGRATION-PLAN-2026-10-28.md) defines the fixed conditions. Detailed gate-3 aggregate ZIP SHA is not repeated in this checkpoint |
| G8-4 | Final b11908 Vulkan IQ3/FP4 C/A/B/D 4k and C/A/B 64k; **14/14 output-level PASS** | [Measured Stage-B/flatten result](R6-S8-GATE4-STAGEB-FLATTEN-RUNBOOK-2026-10-28.md#g8-4-windows-measured-closure---2026-10-28-jst). Numerical Draft K/V parity **DEFER**; possible Defender interference to FP4 M002 speed |
| G8-5 | One IQ3 Vulkan 256k MTP-ON/all-ON stability run, 255,181 input + 512 output, PP 301.30/TG 25.08, 298/425 Draft | [Single-run PASS](R6-S8-GATE5-SELECTIVE-STABILITY-RUNBOOK-2026-10-28.md#windows-measured-result-and-g8-5-closure---2026-10-28-jst). ZIP SHA256 `0ae127d6c600056c13b42d0fea746205648bf3a83f83e96e70651338ad626831`; **not** a 256k speed A/B |
| G8-6 | Vulkan/ROCm distinct server, EN/JA tokenizer equivalence, Vulkan stock+MTP Jinja multi-turn, real64, ROCm stock | [Measured runtime PASS](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md#g8-6-windows-measured-closure---2026-10-28-jst). ZIP SHA256 `6d143104949649cf89b3ffa6fa11b4a848eab61a0d2aaf9829871712b0395f38` |

## Verified Windows binary and backend identity (G8-6 ZIP)

| Artifact | Vulkan fixed b11908 SHA256 | ROCm b11908 SHA256 |
| --- | --- | --- |
| `llama-cli.exe` | `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a` | `1bbd4a5102b6181d8de92faf2d42e49f96ba2ad4b04b7c7f9e6aafc168d322b1` |
| `llama-server.exe` | `89b575891366cd5d697686c84ef78ff09127088a6330d86b64da73f6b73d3615` | `9187ebec46825efc88a98644581ee6b856f30472b6a99671f95b237459ec9c82` |
| `llama-tokenize.exe` | `a85e803bf30c1385ddb35ed24dda8f4a732608050c59c2cad24a2d876cc9cea8` | `0333a9c90825729866241510b9a2970f6bdbe733331a83c63eeb0c6953c56581` |
| GPU backend DLL | `ggml-vulkan.dll`: `c5c00dab8ec29b2becccd33cccee64b3221ce243a7ff7909ce8d3f73e9078d54` | `ggml-hip.dll`: `cb0c107b52d8a20a86a5b57b7db7b1cf64047be48302811cf593d3506e9a40ce` |

- Both `evox2-build.json`: `BuildIdentity.Status=Verified`, same source `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`, no dirty source at build; Vulkan Clang 20.1.8, `build-vulkan-r6-combined-fixed`; ROCm AMD Clang 23.0.0/MSVC 14.44, `build-rocm-r6-combined` and `RuntimePolicy.Verification=DllAndRuntimeDataHashesVerified` / `gfx1151`.
- Both separate directory hash inventories in the raw ZIP cover the other DLLs and tools. `llama-bench.exe` is included in build verification; its detailed SHA can be recovered from the raw inventory and is not restated here. Do not mix backend binaries/DLLs or switch an already verified b11908 manifest to a docs-only source HEAD.
- Main/G8-5 CLI GPU placement was 49/49, MTP Draft 50/50. G8-6 server logs do not independently re-report full layer counts; they demonstrate accepted MTP, actual Vulkan union and successful HTTP requests, while distinct manifests and user confirmation establish the intended backend execution.

## G8-6 runtime numeric checkpoint

| Request | Actual prompt / completion | Result and caveat |
| --- | --- | --- |
| Vulkan MTP OFF `vk-stock` | 37 / 39 | `/health=ok`, no Draft, `truncated=0` |
| Vulkan MTP ON turn1 | 37 / 39 | Draft accepted **20/38**, `truncated=0` |
| Vulkan MTP ON turn2 | 109 / 83 (`cached_tokens=76`) | Draft accepted **49/66**, coherent Jinja assistant-history carry-over, `truncated=0` |
| Vulkan MTP ON existing 64k paper | **61,842 / 128** (`total=61,970`) | PP **358.29**, TG **33.55 tok/s**, **76/100** Draft, QSA union active, `truncated=0`; 128-token output cap caused `finish_reason=length`, not context truncation |
| ROCm MTP OFF `rocm-stock` | 37 / 39 | `/health=ok`, `truncated=0`; archived `21:07` API folder is misnamed `vk-stock`, user confirmed ROCm identity |

The long real-input fixture was the known SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`. Output was meaningfully related to source content but stopped at the 128-token cap and referred to six instead of the requested three summary items. **Do not call this semantic-quality PASS**. G8-6 P-MODE Performance/no OOM-reset-scan and unchanged test flags/commands were explicitly confirmed by the user, but a separate ADLX/P-MODE per-sample CSV was not in the 19-entry ZIP.

## Frozen S8 presets and known exclusions

| Backend/model | Supported S8 result | What remains OFF / DEFER |
| --- | --- | --- |
| Vulkan Qwen3.8 Unsloth IQ3 PLE16 f16 K/V | **S4 union + S5 DENSE + S6 NOOP: PASS opt-in** for tested eligible paths, `GGML_VK_QSA_UNION_MIN_KV=32768`. MTP-OFF stock PASS. All-ON S7 lab profile demonstrated functional stability/usable server | Source defaults OFF. **S7-A/B DEFER** for general supported preset pending numerical Draft K/V parity; all-ON not a default |
| Vulkan Agention ROCmFP4 FAST PLE16 | S8 CLI/Vulkan combined numerical and performance evidence only; no G8-6 FP4 server test | FP4 Vulkan is not ROCm HIP FP4 kernel support. No production/server flag promotion without targeted evidence |
| ROCm Qwen3.8 Unsloth IQ3 PLE16 | **S5 DENSE + S6 NOOP: PASS opt-in for MTP-ON CLI scope**. MTP-OFF short server PASS, TheRock 10.0 verified | S4 Vulkan union **DISABLE**; ROCm S7-A/B **DEFER**; ROCm MTP-ON **server DEFER** |
| Unsloth IQ4 / huihui IQ4XS / Gemma4 | **S9 pending**, not approved by S8 IQ3 results | Treat all S8 optional speed flags as OFF when first testing each unvalidated model; retain b10919 Gemma4 fallback |

**Handoff:** execute [the S9 final-model plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md#3-モデルと計測タイミングを固定) only after selecting exact model files/quant/fixtures and safe binary profiles. Unsloth IQ4/huihui 4/16k then selected 64/128k, Gemma4 31B/26B separately against b10919; record quality as distinct from throughput and loading. Keep original b11903, b11906, S4/S5/S6, S0, and b10919 builds unmodified; no new source patches or upstream rebase in the S9 acceptance path.
