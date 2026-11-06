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

## 2026-11-07 first 64k RGP calibration pair — GPU capture obtained, FA target NOT YET confirmed

Native marker-only runs completed normally on the correctly configured b12133/da51a88c2 Vulkan binary:

| Corpus | Native run ID | Native Exit | RGP file | Initial RDP Dispatch timer |
|---|---|---|---|---|
| Code | `20261107-012232-772-bench-vulkan-b12133-ctx65536-283633fc79f0` | OK / 0 | `llama-bench-20261107-012538502.rgp` | 175,000 ms (planned) |
| Literature | `20261107-013603-436-bench-vulkan-b12133-ctx65536-1e4b472c638e` | OK / 0 | `llama-bench-20261107-013915236.rgp` | 185,000 ms (planned) |

- Native `conditions.json.Environment` and `stderr.log` positively confirm `GGML_VK_FA_RGP_MARKERS=1`, the `ggml_vulkan: FA RGP markers enabled (VK_EXT_debug_utils, label prefix EVOX2_FA_)` line, correct Vulkan backend, QSA UNION0, gather0, prompt61777, ctx65536, N1024 nominal and unchanged b12133 build. Code sample native `384.331 tok/s` and literature `356.762 tok/s` are marker-only/RDP-influenced; don't use them for a clean timing attribution.
- Four user screenshots show **valid RGP event-tree and wavefront-occupancy captures**, with grouped `GET_ROWS node_1`, `CONCAT node_4`, and MoE `ffn_moe_gate-2/ffn_moe_up-2` among the most expensive captured events. In the shown event area no `EVOX2_FA_` marker appears; user reports none found. **Do not conclude global FA absence:** a 256-dispatch window can sample the beginning of one graph while missing its later `Qcur-19` FA dispatch.
- The actual RGP filenames are around +184.777s after the code run's START and +190.359s after literature START, but filenames represent profile creation, not a verified `KV49152` moment; the screenshot doesn't establish physical KV. These are **exploratory calibration traces**, not a matched FA timing pair.
- Evidence digests: code ZIP `5ebe07e10f30a1da2e89fe854511a7d0fa02cc90be076d2f4a247f7aaf2e990a`; code RGP `e864b6aa334b556d88b880e3653505e323a8cb01dd9f8e0018f5f996bc8cc5c4`; literature ZIP `cea963af09ef6eeafdff789630c55b546464dde92371f784c58000ee5e8b5ee7`; literature RGP `5121e305be038db7f1e9123e7b86811b09635a4e2ddb76759d881cee7dbcc658`.

**Cheap check before rerunning:** in the existing RGP *Event timing* view, clear all filters and search the exact literal `EVOX2_FA_` (without `EVO-X2` hyphen) using **Filter event tree**. Verify both `EVOX2_FA_MASK_OPT` and `EVOX2_FA_MAIN` absent in the complete captured event hierarchy, not merely the first on-screen `submit 0` rows.

**One-step code-only probe if the marker is absent:** keep dispatch count256, SQTT High, counters/tracing OFF, all benchmark plan parameters unchanged, and move RDP `Dispatch timer / Capture time` to **176,000 ms** from175,000 ms. This **+1000ms is only an exploratory heuristic**, intended to move from visibly early MoE layers toward later `Qcur-19` within or near the same 1024-token physical batch; it does not guarantee the same KV, or even the same batch. Inspect the **nearest actual `EVOX2_FA_ ... KV=... N=... q=...`** event and report. Only after this code-side calibration choose a literature timer value. If the next sample still shows early graph and no FA, inspect RDP timer behavior and consider a different dispatch range/capture trigger; do not blindly repeat entire code/literature 64k pairs.

**No C++ source change or Vulkan rebuild is indicated by this evidence.** If a future RGP capture has an `EVOX2_FA_` label but not KV49152/Qcur-19, that is valuable stage calibration but must not be recorded as exact-alignment PASS.

## 2026-11-07 02:00 JST — 177,000 ms / 512-dispatch code capture: FA marker successfully found, KV still too late

**Verified user screenshots and native ZIP; this is a useful timing calibration, NOT the aligned KV49152 comparison.**

- Code native ZIP: `20261107-015701-891-bench-vulkan-b12133-ctx65536-283633fc79f0.zip`; SHA256 `58b9ade148077e2acc452842ff3a0781a6a3337c1396131d52c600d9af95c69a`.
- GPU profile: `llama-bench-20261107-020006687.rgp`; SHA256 `b327c99d1a9959b059fb1211928bde3392ecae12039a656afd19ce56f8c4958e`, bytes `187157672` (~178.5 MiB). The original RGP binary is retained outside Git; labels and times below are directly read from screenshots.
- RDP GUI settings in screenshot: **Dispatch timer Capture time=177000 ms, Dispatch count=512, SQTT High**, instruction trace and counters OFF. User reports a 176000 ms exploratory trace without FA label; 512 instead of 256 changes capture coverage.
- Graph user-event tree positively shows `EVOX2_FA_MASK_OPT ... KV=53248 N=1024 Br=16 Bc=64 n_kv_max=2051 q=Qcur-3` and `EVOX2_FA_MAIN shader=flash_attn_f32_f16_aligned_cm1` in `submit 3` / `FLASH_ATTN_EXT node_624`.
- Actual RGP GPU timings (from screenshot): `fa_mask_opt` **5126.844 µs** (~5.127 ms); `flash_attn_f32_f16_aligned_cm1` **78277.633 µs** (~78.278 ms); enclosing `FLASH_ATTN_EXT` **83405.076 µs** (~83.405 ms). Inclusive user-event intervals are **not independently additive**; do not treat these as target KV49152 or literature timings.
- Native output: **Status OK, ExitCode0**, model and b12133/da51a88c2 correct, P-MODE Performance unchanged, no logged GPU TDR/OOM; PP `383.030548 tok/s` marker/RDP-on not clean speed baseline. Native START `2026-11-07T01:57:02.7573227+09:00`, FINISH `02:00:35.2280862+09:00`, profile filename `02:00:06.687` ~184s after run start; profile save timestamp is **not** exact dispatch execution time.
- Target still `KV49152 / N1024 / Qcur-19`. Measured KV gap = `53248-49152=4096` tokens, and Qcur-3 layer is earlier than desired Qcur-19 within the GPU graph. Need **earlier time for target KV** and potentially **later point within the matching layer's graph**.

**Proposed next code-only calibration:** RDP Dispatch timer **166000 ms**, count **512**, SQTT High, counters/tracing OFF, same existing marker-only benchmark variant `rgp-code-64k`, no C++ changes/rebuild. This is a **rough estimate**: 4096 tokens / 383.03 tok/s overall average ≈10.7s, implying ~166.3s from the prior 177s timer; late-stage instantaneous PP and RDP timer origin can differ, so **do not label 166000 ms as verified to be KV49152**. Observe `EVOX2_FA_* KV/N/q`: if KV <49152 move capture time later, if KV >49152 move earlier. If KV49152 but q is `Qcur-3` or another earlier layer, move the capture start slightly later within the *same* KV graph, retaining 512 dispatches. Beware that the presence/absence of FA also depends on count256 vs512 and capture graph boundary, not timer only. Avoid changing model or enabling score/mask readback.

**Capture priority:** first one exact `EVOX2_FA_MASK_OPT KV49152 N1024 Qcur-19` and its matching `EVOX2_FA_MAIN` for code. Only then choose literature capture timer; the two corpora need matching **labels**, not matching timer numbers. Stop/inspect on SQTT truncation, GPU reset, DeviceLost or unexplained build/env drift.
