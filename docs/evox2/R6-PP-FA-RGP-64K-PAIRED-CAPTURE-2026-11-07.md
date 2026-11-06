# r6 Vulkan QSA FA: paired 64k RGP capture plan / RDP values (2026-11-07)

**Status: config/runbook created; no new C++ changes, build or RGP capture performed here.** Reuse the already tested marker-capable **b12133 / da51a88c2** Vulkan build (or a verifiably equivalent later build). Work on `investigation/r6-pp-fa-mask-rgp-20261105`; do not change r6 stable/production branches.

## Objective, scope and already-verified evidence

Compare the **same** physical FA kernel invocation for C/C++ source and Japanese literature:
- Model Qwen3.8 Flash Next Unsloth IQ3_XXS PLE16, Radeon 8060S, UMA96GB, P-MODE Performance.
- 61,777 head tokens, ctx65,536, batch2048/UBatch1024, F16 KV, n_gen0, n_depth0, one repetition, no warmup, QSA UNION OFF, gather OFF, MTP OFF.
- Target **KV49152 / N1024 / q=Qcur-19**, pipeline and Br/Bc as *read from the actual RGP marker*.
- Previous score/top-k observations at layer19 Query48640–48703: code 93.933% of selected pools in Key>=40960, literature54.578%; literature more broadly distributed. Existing 2-bit mask Q tiles32–35 have 767 active Key tiles in code and1,912 in literature (ratio2.49). These are **hypotheses about FA skip work**, not observed timing ratios.
- RGP marker is for the whole **1024-Query physical FA**, *not* a timed 64-Query region. Exact match by KV/N/q and pipeline; if RGP does not show those IDs, classify as exploratory, not an aligned comparison.

Sources: [existing FA RGP dispatch wrapper](../../ggml/src/ggml-vulkan/ggml-vulkan.cpp) (`EVOX2_FA_MASK_OPT`, `EVOX2_FA_MAIN`, sometimes `EVOX2_FA_SPARSE`, `MAIN_SPLIT`, `SPLIT_REDUCE`) and [Gate1 4k RGP trace](R6-PP-RGP-GATE1-4K-CAPTURE-RUNBOOK-2026-11-06.md).

## New files

- Benchmark: `tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-64k-paired-20261107.psd1`
- RDP reference settings: `tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-rdp-settings-20261107.json`

The JSON is **documentation/machine-readable settings reference; Radeon Developer Panel does not automatically import this JSON**. The benchmark plan is ready for `Invoke-BenchmarkMatrix.ps1`.

## 1. RDP GUI settings (exploratory first attempt)

Set RDP **before launching the benchmark**, choose the Vulkan `llama-bench.exe` that loads the b12133 diagnostic Vulkan DLL. Only profile one application/run at a time.

| RDP / RGP setting | Initial value |
|---|---|
| Profiling target | Vulkan / `llama-bench.exe` (build-vulkan-ppdiag-rgp/bin/Release) |
| Capture mode | **Dispatch** (not Frame or Draw) |
| Render op / dispatch count | **256** |
| Auto capture mode | **Dispatch timer** (exploratory, not calibrated) |
| Timer dispatch count | **256** |
| Initial timer for **code** | **175,000 ms** (provisional) |
| Initial timer for **literature** | **185,000 ms** (provisional) |
| Additional Delay capture | **OFF / 0 ms** |
| SQTT Buffer Size | **High** |
| Collect counters | **OFF** |
| Enable instruction tracing | **OFF** |
| Enable shader instrumentation | **OFF** |
| Device clocks | Keep the same setting across both runs; log actual clock/power; RGP may change clock mode at capture |
| Output | Distinct per-corpus `.rgp` files + RDP collection log. Preserve exact filename and SHA-256 |

**Crucial calibration warning:** 175/185 s are only first-search estimates based on the previous whole-process duration (~208.5 s code /229.1 s literature), model-loading latency and a rough position in 61,777-token PP. They are **not measurements of the KV49152 event timestamp**. RDP's timer origin/driver attach timing and nonuniform PP rate can shift the capture. Changing the timer until the **RGP label** says `KV=49152 / N=1024 / q=Qcur-19` is expected. Do not infer successful alignment from timestamps alone.

AMD GPUOpen documents both `Dispatch timer` and `Dispatch range` auto capture, as well as high SQTT and optional trace/counters: https://gpuopen.com/manuals/rdp_manual/features/ .

**Alternative if Dispatch timer is not exposed or does not work:** Auto capture mode `None` / Capture mode `Dispatch` / count256 / manual button or hotkey, timed near the expected position; the same *RGP-label validation* applies. Do not transplant r5 or 4k CPU dispatch ordinal into RDP `Dispatch start index`.

**After obtaining an anchored sample** optionally switch to **Auto capture mode: Dispatch range**, start=<CALIBRATED ACTUAL RDP INDEX> / count256; set start per run only after inspecting RDP/RGP. RDP GPU RenderOp numbering and source CPU `vkCmdDispatch` count are *not guaranteed equal*. A known fixed numeric start is **not yet available** for this r6 b12133 64k plan.

### Capture must show these RGP labels

- Prefer **both** `EVOX2_FA_MASK_OPT ... KV=49152 N=1024 ... q=Qcur-19` and `EVOX2_FA_MAIN ... KV=49152 N=1024 ... q=Qcur-19` from the **same invocation** (or clearly same batch/layer when split stages).
- Record stage, shader, RGP GPU duration (µs), physical KV/N/Br/Bc, group sizes, kernel specialization, split-K flag if any, SQTT validity, GPU clock, capture index/timer and RGP filename.
- First capture that lands at a *different KV/layer* is **calibration only**, not one half of a final comparison. Change timer or calibrated dispatch range and retry with a fresh capture file. Capture metadata and RGP screenshot are useful even if the benchmark succeeded but the target was missed.

## 2. Native plan execution — one corpus per process

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git pull --ff-only
git branch --show-current

$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-pp-fa-rgp-64k-paired-20261107.psd1'
& '.\build-vulkan-ppdiag-rgp\bin\Release\llama-bench.exe' --version
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
```

Check **two** variants with no Indexer or FA-mask diagnostic. Important effective environment: `GGML_VK_FA_RGP_MARKERS='1'` only; `GGML_VK_FA_DISPATCH_TRACE`, `GGML_VK_FA_MASK_DIAG`, `GGML_VK_INDEXER_DIAG`, `GGML_VK_PERF_LOGGER` all **unset**. Plan freezes model/key and input source paths from earlier passing 64k experiments. `R6PpFaRgpVulkan` must resolve to the existing checked Vulkan b12133 binary. Do not rebuild for this plan.

Prepare RDP Capture *before* launch, then one process:
```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant rgp-code-64k -StopOnError
```

Inspect the `.rgp` and stderr for `ggml_vulkan: FA RGP markers enabled`. **Only after finding the desired actual KV/N/q and validating the profile**, configure the second (literature) timer/range, and run:
```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant rgp-literature-64k -StopOnError
```

Native artifacts are stored by `Invoke-BenchmarkMatrix.ps1` as separate run ZIPs. Keep `.rgp` raw files outside Git. Use distinct filenames (e.g. `rgp-code-64k-kv49152-*.rgp` and `rgp-literature-64k-kv49152-*.rgp`) and record original RDP name too.

## 3. How to read RGP — stage timings / alignment

RGP → Events → **Event timing**, enable user-event grouping/filtering and search `EVOX2_FA_`. Match **literal** `KV=49152`, `N=1024`, `q=Qcur-19`, same Br/Bc/pipeline between corpora. The existing debug marker wrapper encloses the actual `vkCmdDispatch` without buffer readback or additional compute. For each corpus record:

| Identity | Code | Literature |
|---|---|---|
| .rgp filename and SHA | fill from profile | fill |
| Exact marker `KV/N/q` | require 49152/1024/Qcur-19 | require 49152/1024/Qcur-19 |
| `MASK_OPT` duration (µs) | measured | measured |
| `MAIN` duration (µs) | measured | measured |
| `SPARSE`, `MAIN_SPLIT`, `SPLIT_REDUCE` if present | measured separately | measured separately |
| Shader specialization, Br/Bc, workgroup shape | same or record mismatch | same or record mismatch |
| RGP GPU occupancy/idle / clocks | observed | observed |

**Do not sum inclusive nested user markers with nested shader events.** Compare like-for-like GPU shader event durations, with units and evidence. The 64-Query mask count 767 vs1912 is a **spatial sample**, while RGP duration applies to 1024 Query; do not divide those quantities as if identical sample windows. RGP profiling affects clocks/timing; do not compare captured PP tok/s against old clean baseline as isolated FA effects.

## 4. Retry / stop policy

- If target was missed, first report **the actual nearest labeled KV/N/q** and RDP capture timer/start/count. Then change **only the capture position**, not model/QSA/kernel conditions.
- If capture is truncated, increase SQTT to High (already default here), decrease dispatch count to128 or64 after calibrating start. Do **not** add Indexer or F16 readback in the profiled run.
- Stop for Vulkan DeviceLost, Win TDR/0x141, OOM/paging, driver reset, major clock/P-MODE drift, missing debug_utils (no `FA RGP markers enabled`), or untrusted process identity. Retain benchmark ZIP + RDP log/screenshot and first `.rgp`; do not silently average unmatched runs.

## 5. Evidence to return

For **each** corpus: benchmark ZIP, `.rgp` file (or if too large, RGP event-timing screenshots showing both stage labels and duration, plus RDP capture status log), actual timer/dispatch start and count, build identity and P-MODE observations. Initial code capture alone is enough to verify calibration before literature.

Reference: AMD RDP [Profiling & capture settings](https://gpuopen.com/manuals/rdp_manual/features/) and [compute-only Vulkan RGP](https://gpuopen.com/learn/radeon_gpu_profiler_2-4_support_rx9000_series_pure-compute_applications/).
