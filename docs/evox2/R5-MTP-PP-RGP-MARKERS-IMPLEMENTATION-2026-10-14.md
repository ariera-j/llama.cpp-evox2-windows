# r5 MTP PP Vulkan RGP markers — experiment implementation (2026-10-14)

**Status:** SOURCE COMMITTED; source-contract static checks pass; **Windows Vulkan compilation, native smoke and RGP marker visibility are NOT YET VERIFIED**. This document covers only `investigation/r5-mtp-pp-trace-20261013`. Do not treat this code as part of stable `r5/upstream-refresh-20261009`; do not overwrite the validated b11569 executable used in prior 64k/128k PP traces or the DENSE/NOOP branches.

## Proven donor: the previous llama-bench study

The implementation deliberately reuses the **already GPU-validated design**, rather than inventing an unrelated profiler:

- Original donor: `investigation/r5-vulkan-off-fa-dispatch-20261010` and [archived historical RGP evidence](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/r5/upstream-refresh-20261009/docs/evox2/R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md).
- **Previously confirmed:** Vulkan upstream `VK_EXT_debug_utils` regions are visible in RGP. A one-shot diagnostic `GGML_VK_FA_RGP_MARKERS=1` wrapped the exact FA dispatch with `EVOX2_FA_MAIN shader=... KV=... N=... Br=... Bc=... n_kv_max=... q=...` labels. RGP confirmed `flash_attn_f32_f16_aligned_cm1` at KV=49152 and differentiable main/mask stages. The prior diagnostic was specific to QSA union OFF llama-bench inputs, **not** an MTP on/off GPU timing measurement.
- **Important previous lesson:** automatically capture `Dispatch timer` sampled repeated common graph prefixes and did not reliably include FA; **Dispatch range**, with controlled start-dispatch offset, captured a known `EVOX2_FA_*` marker and KV. The historical `start=180000` value was calibrated for a *different QSA OFF benchmark binary and corpus*; it is **not a calibrated MTP PP setting**.
- Current 64k **MTP ON/OFF** RGP snapshots at KV~51–53k captured the same 13 dominant PSO hashes and near-identical summed GPU time ~300.46ms each, despite native PP +13.74s ON. The objective is to capture the **MTP-related graph portions** instead of another unknown common-path window.

## New opt-in and source changes

New Vulkan environment variable **`GGML_VK_MTP_PP_RGP_MARKERS=1`**, enabled **only when exactly `1`**. When omitted, `0`, empty or another value, the instrumentation branch is disabled. This is deliberately **separate from donor `GGML_VK_FA_RGP_MARKERS`**, which has NOT been merged wholesale. No edits to shaders, sampled token outputs, QSA policies, FA algorithm, KV cache, GGUF metadata, MoE math or speculative scheduling.

Changed experimental source:

- `ggml/src/ggml-vulkan/ggml-vulkan-types.h`: per-backend `mtp_rgp_graph_role` string, default `unknown`, and a constructor for an explicit Vulkan debug region.
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: auto-request `VK_EXT_debug_utils` when the flag is enabled and the instance extension is supported (the pre-existing `GGML_VK_DEBUG_MARKERS` also continues to work). At initialization log `ggml_vulkan: MTP PP RGP markers enabled (VK_EXT_debug_utils, EVOX2_MTP_*)` or explicit missing-extension warning.
- Source-level **graph role heuristic**: search the compiled Vulkan cgraph for `mtp_eh_proj` or `mtp_hnorm` nodes -> `role=draft`; otherwise `hc_init` -> `role=target`; absent/partial graph -> **`role=unknown`**. This is a read-only source-name **hint**, NOT a verified inference-context ID: graph partitioning/fusion might omit sentinel nodes. Never infer correctness from a guessed role alone. A queue debug region `EVOX2_MTP_GRAPH role=...` records the hint.
- Per-dispatch subregions `EVOX2_MTP_<stage> role=... shader=<actual_pipeline> KV=... N=... Br=... Bc=... n_kv_max=... q=<tensor_name>` wrap **QSA_UNION**, **QSA_GATHER**, **QSA_MAIN**, **MASK_OPT**, **SPARSE**, **MAIN**, **MAIN_SPLIT** and **SPLIT_REDUCE**. All use the **exact original Vulkan compute dispatch** with unchanged push constants/descriptors/workgroup size. QSA preprocess stages have `Br=Bc=0`, `n_kv_max=0` because those FA tuning fields do not apply; QSA_MAIN reports its selected FA Br/Bc. `KV` is the K tensor length for the operation; not the input length and not necessarily unique attended positions.
- `EVOX2_MTP_MATMUL role=... op=MUL_MAT_ID|MUL_MAT tensor=<node>` wraps only these graph-node compute paths, to expose heavy MoE/FFN candidates even if their shaders are shared between ON and OFF. It closes **before** the original graph-op label and potential command buffer submit.
- Debug regions insert Vulkan marker commands and allocate formatting strings **only when enabled**. No extra FA kernel, GPU copy/readback or `vkQueueWaitIdle`/forced host GPU sync has been added by the new wrapper. Performance still incurs profiling overhead, so marker-enabled wall PP/TG must NOT be used as a production-speed or ABBA baseline.

New measurement support:

- `tools/evox2/benchmark/configs/qwen38-r5-mtp-pp-rgp-64k.psd1` is independent of the prior trace-only plans. It has `vulkan-short` and `vulkan-64k` jobs with `on-detail`/`off-detail` variants, `GGML_VK_MTP_PP_RGP_MARKERS=1`, `GGML_VK_QSA_UNION=1` threshold32768, existing `LLAMA_MTP_PP_TRACE=detail`, f16 KV, ub1024/b2048 and the existing 64k input. The dedicated build key **`R5MtpRgpVulkan`** must be defined in the ignored `local.psd1`. The plan unsets `GGML_VK_DEBUG_MARKERS`, donor RGP flags, `GGML_VK_PERF_LOGGER`, concurrent logger and other unrelated profiling switches.
- `tools/evox2/tests/test_mtp_rgp_markers.py` checks source-gating, intended label paths, graph role heuristic and absence of a newly inserted sync in the marker wrapper. This is **static source testing**, not a C++ build or GPU validation; marker role correctness and RGP debug-region visibility require a real native test.
- Existing `tools/evox2/benchmark/Evox2.Benchmark.psm1` already records all `GGML_*` environment variables in conditions; no wrapper patch needed. The new PSD1's effective environment is therefore traceable in normal run logs.

## Evo-X2 Windows source/build gate (NOT YET PASSED)

Use the existing PP experiment worktree, or switch only after ensuring any local edits are committed. Keep b11569's `build-vulkan-mtp-pp-trace` directory unchanged.

```powershell
git fetch origin
git switch investigation/r5-mtp-pp-trace-20261013
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_rgp_markers.py' -v
python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_pp_trace.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-mtp-pp-rgp `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

$bin = '.\build-vulkan-mtp-pp-rgp\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\llama-cli.exe" --list-devices
```

In ignored `tools/evox2/benchmark/configs/local.psd1` `Builds` add/edit this **distinct entry**; adapt only the local path:

```powershell
R5MtpRgpVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-mtp-pp-rgp\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

Check actual `BinDir` and executable SHA/manifest in the runner output; `GitCommit` is the checkout HEAD and must not be confused with an older compiled executable. Do NOT point this key at validated b11569 or b11560.

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-pp-rgp-64k.psd1'

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# One small MTP ON native smoke, before any more long RGP capture
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan $plan -OnlyJob vulkan-short -OnlyVariant on-detail -StopOnError
```

Gate: process `Status=OK`/`ExitCode=0`; **new** verified runtime digest/build SHA and Vulkan backend; stderr contains `ggml_vulkan: MTP PP RGP markers enabled`; no unexpected Vulkan initialization warnings. The CPU phase trace still needs to show target and draft events; model output need not be byte-identical to an older build before correctness is independently checked. If compilation, runtime, logits or graph roles fail, **stop before 64k** and submit the build stderr.

## Native 64k and RGP gate (only after short smoke)

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-pp-rgp-64k.psd1 `
  -OnlyJob vulkan-64k -OnlyVariant on-detail -StopOnError
```

In RDP: Vulkan/llama-cli; SQTT **High**, instruction tracing and hardware counters **OFF**. Prefer **Auto capture → Dispatch range**, initially **start dispatch index ~512, count 256** as a visibility/calibration trial, then inspect **RGP → Events → Event timing** and filter `EVOX2_MTP_`. If labels are visible, read the **actual `KV=`** and `role=` before increasing the dispatch start index to late prefill; don't blindly reuse the previous `180000` llama-bench range or interpret RGP's short snapshot percentage as whole PP cost. The first range may capture only target initialization. Once a draft label with correct graph role and late KV is found, acquire an OFF control at comparable KV if needed, staying on the *same new executable*.

Prior known-good MTP draft Q8_0 SHA256: `cd87e5d1a4dadaeed63e35929f3b2f28d13e081b4cd32e00f2835095ec09351e` (**old revision**); do not substitute Hugging Face's October updated weights during this profiling study.

### Expected labels in the RGP event tree

```text
EVOX2_MTP_GRAPH role=target
  ... EVOX2_MTP_QSA_MAIN role=target shader=<...> KV=<...> ...
  ... EVOX2_MTP_MATMUL role=target op=MUL_MAT_ID tensor=<...>
EVOX2_MTP_GRAPH role=draft
  ... EVOX2_MTP_MAIN role=draft shader=flash_attn_<...> KV=<...> q=<...>
  ... EVOX2_MTP_MATMUL role=draft op=MUL_MAT ... 
```

**These are examples, not observed outputs.** A real trace may show `role=unknown` because graph partitioning removed the sentinel; in that case use the query tensor name, graph-op ancestry and CLI CPU event times, and repair the role heuristic *after* observing evidence. Do not mislabel `EVOX2_MTP_MAIN` as draft solely because the graph was MTP ON: the target's **dense FA fallback** also has `MAIN` dispatches. RGP GPU time is distinct from the CPU-side `hidden_get_us` sync wait; the markers do not measure pinned-host mapping/copy in isolation.

## Stop gates and change control

1. Static tests → new Clang/Vulkan build → short smoke → RGP one small range → calibrate KV and graph role.
2. If the first RGP shows only shared target compute or labels are missing, **do not ask for another blind 64k timer RGP**. Inspect stdout/stderr and debug region support; use a different deterministic dispatch range after calibration.
3. Only when identifying draft dense FA versus target QSA/MoE kernels compare GPU event times (same KV), then decide whether KV-only draft prefill, output graph rewiring, or host handoff merits a correctness-gated experiment.
4. Do not merge this diagnostic source into stable r5. Stable docs should point to this file and display the **UNBUILT/UNVERIFIED** status until Evo-X2 results arrive.


## Native Evo-X2 validation: Python PASS, b11577 Windows Vulkan build PASS, short ON PASS — 2026-10-14 01:23 JST

The user reports both `test_mtp_rgp_markers.py` and prior `test_mtp_pp_trace.py` PASS and a successful dedicated Clang/Vulkan build. Native **short ON** archive `20261014-012312-361-cli-vulkan-b11577-ctx32768-b44bb4d65d5d.zip` SHA256 `6271d4ef1498f90937c752dc183700f2befb30aea4ed0d8e3c31424669025c72` was inspected independently (9 ZIP members; `conditions.json`, `result.json`, `stderr.log`, `output.log`, resource/summary artifacts).

| Gate | Native evidence |
| --- | --- |
| Dedicated code/build | **b11577**, compiled Git commit **`34ebb693308e651fe60cd8242209264c5d4cf57d`**, clean build and clean checkout, Clang 20.1.8, Vulkan, 96GB UMA label |
| Runtime artifacts | **Verified**, executable SHA256 `6d141c6b2e627e89c380922573f1b62a08ea48fbdb362f9e0ce31860a73ebe34`, overall runtime digest `be63fa5cc09edb444e437598541faa276aa34afc3e08214b43dc7bf655fb9933`. **Different** from b11569 validated prior PP binary |
| Enabled parameters | `GGML_VK_MTP_PP_RGP_MARKERS=1`; `GGML_VK_QSA_UNION=1` / threshold `32768`; `LLAMA_MTP_PP_TRACE=detail`; other inherited performance logger / unrelated profiling flags absent |
| Vulkan extension evidence | Real `stderr.log` includes `ggml_vulkan: MTP PP RGP markers enabled (VK_EXT_debug_utils, EVOX2_MTP_*)`. This verifies initialization/extension activation, **NOT YET RGP capture visibility or role-hint accuracy** |
| Inference | `Status=OK`, `ExitCode=0`; short 163 input / 32 generated, context 32768, batch2048/ub1024; MTP accepted 17/27 (**62.963%**), consistent with earlier b11569 short condition |
| Phase trace | Four `mtp_pp_trace_v1` bins (target/draft × prompt/generation), each has complete detail rows (1 + 14 per role). Each role-phase bin's row/token counts and **all timing fields** matched exactly. Both target and draft prompt have 163 tokens |
| Performance caution | PP1654.78ms (98.50 tok/s), TG1992.10ms (15.56 tok/s) are **short, new-build, debug-region-enabled** measurements; do not compare to prior b11569/ABBA rates or infer regression |

**Result:** Source-test/build/native-short gate **PASS**; we may proceed to 64k RGP **visibility and KV calibration only**. Do **not** claim that RGP has yet shown `EVOX2_MTP_GRAPH role=draft` or that all MTP-added GPU operator time is measured.

**Next native RGP gate:** run existing `qwen38-r5-mtp-pp-rgp-64k.psd1` **`vulkan-64k / on-detail`**, using the same b11577 executable, original Q8_0 draft and 61,789-token input; in RDP choose Vulkan / Auto capture → **Dispatch range**, first **start dispatch=512, count=256** as an early marker-visibility check, SQTT High, instruction tracing/counters OFF. In RGP → Events → **Event timing**, search `EVOX2_MTP_`, inspect graph role (including `unknown`) and true `KV=`. First capture need not target KV~50k; it **calibrates** deterministic dispatch positioning for this new binary (historical r5 llama-bench offsets cannot be copied blindly). Only after a first labelled capture choose a later range for draft-specific work. Capture-overhead changes PP rates; keep b11569 unprofiled comparisons separate.


## First RGP visibility gate PASSED: ON 64k / dispatch range 512–767 — 2026-10-14 01:32–01:36 JST

**New evidence:** user native CLI ZIP `20261014-013203-264-cli-vulkan-b11577-ctx65536-91e77c66f839.zip` SHA256 **`5daea5d62d8c72dd592c186d664652aaf7190e2fac247bfce9f1de11cbcb23e6`** (9 files); user native RGP `llama-cli-20261014-013243516.rgp` SHA256 **`095b118ff3808132946835a9295cde66c89fa6e17b1707fdea941bbb00f31e9c`**, **3,916,169 bytes**, plus RGP Events → Event timing screenshot with `Group by user events` and filter `EVOX2_MTP`. Raw user artifacts retained outside Git; do not commit large GPU traces.

### Identity/correctness/phase trace

- User runtime **b11577 / compiled `34ebb693308e651fe60cd8242209264c5d4cf57d`**, same executable SHA `6d141c6b2e627e89c380922573f1b62a08ea48fbdb362f9e0ce31860a73ebe34` and runtime artifact digest `be63fa5cc09edb444e437598541faa276aa34afc3e08214b43dc7bf655fb9933` as passed short smoke; `RuntimeArtifactStatus=Verified`; checkout same source, clean; Vulkan Radeon8060S / Clang20.1.8, original target PLE16 and **old self-contained Q8_0 draft**.
- CLI wall start **`2026-10-14T01:32:03.2657788+09:00`**, finish 01:36:12.1038483, process 248.838s, `Status=OK/ExitCode=0`. 61,789 prompt / 512 generated tokens; PP **186.43927s / 331.42 tok/s**, TG **17.93738s / 28.49 tok/s**, MTP acceptance **295/430=68.605%**. Marker-enabled rates are **diagnostic only**, never a regular OFF/ON speed baseline.
- Effective env has `GGML_VK_MTP_PP_RGP_MARKERS=1`, `GGML_VK_QSA_UNION=1` and `GGML_VK_QSA_UNION_MIN_KV=32768`, `LLAMA_MTP_PP_TRACE=detail`, without Vulkan PERF_LOGGER. Native stderr includes the expected `ggml_vulkan: MTP PP RGP markers enabled (VK_EXT_debug_utils, EVOX2_MTP_*)`. PP source trace 31 target and 31 draft prompt calls, covering the complete 61,789 tokens, with bin/detail correspondence; `qsa-union active` later at high KV is logged, but **not** observed in the *early* RGP capture.

### Exact capture location / visible shader labels

- RDF trace config parsed from `.rgp`: `controller=renderop`, `renderOpMode=dispatch`, **`captureMode=absolute`**, `preparationStartRenderOp=512`, **`captureRenderOpCount=256`**, SQTT enabled, counters/instruction tokens off. The RGP image verifies that named Vulkan debug regions are actually visible to the tool: **RGP LABEL VISIBILITY GATE PASSED**.
- User screenshot hierarchy, near `submit 7`: `MUL_MAT ffn_shexp-4 → EVOX2_MTP_MATMUL role=target op=MUL_MAT tensor=ffn_shexp-4 → quantize_q8_1_x4 → mul_mat_vec_q8_0_q8_1_f32`. Other `role=target` labels: `MUL_MAT node_875`, `MUL_MAT hc_gate-5`, `MUL_MAT node_890`, `MUL_MAT node_923`, `MUL_MAT node_929`. This **directly validates** that the new annotation attaches to real GPU compute events and the target inference graph in the early startup sample. The screenshot does **not** show a `role=draft` graph region, draft dense FA, `EVOX2_MTP_MAIN` or `EVOX2_MTP_QSA_MAIN`; absence from this limited view does not mean they do not exist in the whole trace or PP.
- Filename timestamp `01:32:43.516` is **+40.250s** relative to CLI start (assuming name is acquisition timestamp). Native stderr records target compute reservation around **+39.876s**, draft-side model tensor buffer creation beginning **+40.758s**, and steady speculative model/context setup completes around **+43.125s**. Thus this first low dispatch index appears to catch **model setup / target scheduler preflight compute**, *not* the desired 40–55k prompt KV (which arrives minutes later). Corroborated by only `role=target` matmul nodes in screenshot. **Do not attach a 51k KV value to this capture.**
- **Caution:** the RDF does not contain a convenient searchable literal `EVOX2_MTP` in its raw bytes; labels are RGP-processed Vulkan events (the supplied Event timing screenshot is positive visibility evidence), not necessarily plain UTF-8 strings in `.rgp`.

### Next experiment, no new build

**Do not rebuild:** use the same compiled b11577, same `qwen38-r5-mtp-pp-rgp-64k.psd1` `vulkan-64k` / `on-detail`. In RDP use **Auto capture → Dispatch range**, **start 50,000, count 256**, Vulkan, SQTT High, hardware counters OFF. This is a **calibration estimate only** based on the previous llama-bench success (`start=50000` produced FA KV~14k under different code/corpus); the extra MTP graph can change the global dispatch-index scale. In RGP → Events → Event timing → `Group by user events`, search `EVOX2_MTP_` and check any `EVOX2_MTP_MAIN`, `EVOX2_MTP_QSA_MAIN`, `EVOX2_MTP_MATMUL role=draft`, etc., with **actual displayed `KV=`**. If only target is seen, record it and choose subsequent dispatch start with that anchor; do not blindly call it draft or KV~50k. Only then choose a late-range MTP ON and optional matched OFF.

The prior successful unoptimized b11569 binary and all original RGP ON/OFF snapshots remain independent controls.
