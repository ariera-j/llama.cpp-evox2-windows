# Gate 1 implemented: r6 Vulkan FA RGP marker-only port (2026-11-05)

**Status (2026-11-05):** Gate 1 source patch + static source-contract tests + short-only benchmark plan committed. User confirmed **Python static tests PASS**. First Windows build stopped with a constructor-arity error in `ggml_vk_debug_label`; **FIX1 changes only that call to r6's existing five-argument overload**. Native Windows re-build, model inference and RGP visibility remain **NOT PASSED**.

**Branch** `investigation/r6-pp-fa-mask-rgp-20261105`. Originated from source feature commit `6a092fd2e60789d6ff7001cbe8e342fccff323ac`.

## Changes

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: ported r5 **marker-only** design into r6 without old r5 QSA/FA source. Exact `GGML_VK_FA_RGP_MARKERS=1` enables `VK_EXT_debug_utils` (when available) and wraps Vulkan FA **MASK_OPT, SPARSE, MAIN_SPLIT, SPLIT_REDUCE, MAIN** dispatches in `EVOX2_FA_...` regions. User-event labels report true shader pipeline name, `KV` K tensor length, `N` FA query dimension, `Br`, `Bc`, `n_kv_max`, `q` tensor name.
- Only the normal `ggml_vk_flash_attn` path is annotated. r6 QSA UNION is unchanged and must be **OFF** during the investigation. Intel Xe dual-stage FA has no custom wrapper in G1 (the EVO-X2 is AMD).
- **FIX1: r6 constructor compatibility:** use `ggml_vk_debug_label region(subctx, label, groups[0], groups[1], groups[2]);`. r6 does not have r5's two-argument `(vk_context&, std::string)` constructor. Its existing overload appends the **passed dispatch group tuple** as `(x,y,z)` to the label; preserve this in RGP screenshot/export when matching. The tuple is the dispatch helper's input group arguments and is not a substitute for verifying actual GPU dispatch dimensions.
- No additional shader, GPU memory copy/readback, QSA data mutation, FA math change, queue wait or forced GPU synchronization. The wrapper's disabled branch invokes exactly the former `ggml_vk_dispatch_pipeline` with the same arguments.
- `tools/evox2/tests/test_r6_fa_rgp_markers.py`: static source/plan opt-in/dispatch/absence-of-sync contract. **No claim of native correctness from static assertions**.
- `tools/evox2/benchmark/configs/qwen38-r6-pp-fa-rgp-gate1-20261105.psd1`: one **1024-token / ctx2048 / head-sliced literary prompt** job with markers OFF and ON variants. No 64k job, reducing risk of accidental full GPU profiling before smoke verification. Requires a new local BuildKey `R6PpFaRgpVulkan`.

## Windows: prepare a separate checkout

If not already prepared, from the existing r6 worktree:

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git worktree add -b investigation/r6-pp-fa-mask-rgp-20261105 `
    C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag `
    origin/investigation/r6-pp-fa-mask-rgp-20261105
cd C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag
git status --short
git log -1 --oneline
```

If the branch is **already** local, use `git worktree add C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag investigation/r6-pp-fa-mask-rgp-20261105`; never force switch/delete worktrees.

## Run static tests and isolated build

```powershell
python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_rgp_markers.py' -v

# Confirm pinned CMake binary first. Build-Vulkan.ps1 expects
# 3.31.6-msvc6 by default, not arbitrary PATH cmake.
.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-ppdiag-rgp `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4

$bin = '.\build-vulkan-ppdiag-rgp\bin\Release'
& "$bin\llama-bench.exe" --version
& "$bin\llama-bench.exe" --list-devices
Get-FileHash "$bin\llama-bench.exe" -Algorithm SHA256
```

If pinned CMake mismatch: use `-CMakeExe <path to 3.31.6-msvc6>` or deliberately reproduce and label a different validated version. Do not overwrite prior r6 b12032/b12038 build folders.

## Add ONE ignored local.psd1 build entry

In the new worktree's `tools/evox2/benchmark/configs/local.psd1`, which is intentionally untracked, define the existing `Models.UnslothPle16` and add a fresh key under `Builds`:

```powershell
R6PpFaRgpVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-vulkan-ppdiag-rgp\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

Copy or recreate the local model path and `LogRoot` settings from the validated r6 local configuration without committing them. **Do not** point the diagnostic key at the original b12032 executable. The short test uses the known existing literary corpus path; adjust in the plan ONLY if its path differs locally, then record actual source SHA `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`.

## Execute G1: PlanOnly → markers OFF → markers ON

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-pp-fa-rgp-gate1-20261105.psd1'

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant markers-off-control -StopOnError

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant markers-on -StopOnError
```

Run only after new build's identity is verified. For ON, stderr must contain:

```text
ggml_vulkan: FA RGP markers enabled (VK_EXT_debug_utils, label prefix EVOX2_FA_)
```

If instead warning says extension unavailable, **stop** rather than continuing to a long RGP. Both OFF and ON runs must exit 0 and use Vulkan (not CPU fallback). The OFF diagnostic should have no `EVOX2_FA_` startup message.

## RGP visibility check: one small short-workload capture

- Attach Radeon Developer Panel/RGP to the **new `llama-bench.exe`**, Vulkan API. In ON mode, choose auto **Dispatch range** with a **small** capture count (initially 256), SQTT **High**, instruction tracing/hardware counters OFF. Absolute start at a small ordinal (r5 512 was an initialization sample) is **calibration only**; verify an FA event appears before drawing conclusions. If no marker, capture could be outside FA; do not treat it as failed source until the correct GPU dispatch range is identified.
- In RGP **Events → Event timing**, select **Group by user events** and search `EVOX2_FA_` and `FLASH_ATTN_EXT`. Require a real FA `MASK_OPT` and `MAIN` marker, `KV=...`, `N=1024`, actual `q=` and shader pipeline names; if snapshot at initial QSA layer is not reached in that short 256-dispatch window, reposition the window using observed label/dispatch metadata rather than timer guess.
- Capture can finish faster than delayed RGP auto acquisition on 1024-token workload; if this happens, **do not declare marker failure**. First inspect the run's log and RDP capture mode, then use a small deterministic capture/setup or a 4k short diagnostic-only workload after a reviewed plan revision.

Gate 1 native PASS requires: static tests pass, unique diagnostic build compiles, OFF and ON short runs Status OK/exit 0 with correct identities, ON initialization log and at least one RGP label truly visible, no TDR/OOM, ADLX+Windows resource data. **Source implementation alone is not enough.**

## Limits / next patch

- **No mask metadata snapshots or heatmaps in Gate 1.** These are Gate 2 and should be a separate commit, after RGP source verification.
- No ROCm/HIP source changes in Gate 1. HIP layer ↔ kernel correlation and ROCm captures are a later gate.
- Marker-enabled rates are diagnostic and should not enter the `evox2-llm-experiments` throughput baseline table.


## FIX1 — incremental build after constructor mismatch

The first Windows clang-cl build failed at `ggml-vulkan.cpp` because the initial Gate 1 wrapper invoked `ggml_vk_debug_label region(subctx, label)`, but r6 only offers a five-argument command-buffer pipeline-name constructor. This was not discovered by pure string-contract static tests, which previously omitted constructor compatibility.

After `git pull --ff-only` on the diagnostic worktree, rerun the updated static test then **reuse the existing diagnostic build directory** (no need to delete the CMake cache or rebuild the validated baseline):

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag
git pull --ff-only
python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_rgp_markers.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-ppdiag-rgp `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4 `
    -BuildOnly
```

`-BuildOnly` still performs the script's environment and toolchain validation, including the CMake version pin. If the original build explicitly used `-CMakeExe`/`-ExpectedCMakeVersion`, pass the **same** arguments again. Do not clear or reconfigure the build directory unnecessarily. If compilation fails at another point, stop and send the first compiler error (rather than the final PowerShell throw).

**Gate condition remains unchanged**: new executable identity, short OFF/ON native smoke, actual RGP user-event visibility; no 64k profiling yet.


## Gate 1 Windows short smoke (2026-11-05 23:42–23:45 JST)

**Observed results from user-uploaded ZIP: Native inference OFF/ON smoke PASS, RGP event-tree visibility still PENDING.** Initial attempt without the ADLX monitor executable was rerun; only the two monitored reruns below are accepted as the completed Gate 1 short-smoke evidence.

Archive: \`20261105-234205-965-bench-vulkan-b12094-ctx2048-e5f7b74db89b.zip\` (outside Git), SHA-256 \`242a806c06417e189a9c180b5b9555abbeba949379e2da81326d04c3602b679f\`.

| Evidence | Markers OFF | Markers ON |
|---|---|---|
| Run ID | \`20261105-234205-965-bench-vulkan-b12094-ctx2048-e5f7b74db89b\` | \`20261105-234459-522-bench-vulkan-b12094-ctx2048-c2518537e3ba\` |
| Effective flag \`GGML_VK_FA_RGP_MARKERS\` | Unset | Literal \`1\` |
| Backend / build | Vulkan b12094 / \`0847585f2\` | Same |
| \`Status\`, \`ExitCode\` | OK / 0 | OK / 0 |
| PP prompt, ctx, physical UBatch | 1024, 2048, 1024 | Same |
| Measured PP (single run) | **530.712141 tok/s**, 1.929483 s | **532.608126 tok/s**, 1.922617 s |
| ADLX | Started, 24 samples, exit0, no monitor error | Started, 26 samples, exit0, no error |
| Windows resource monitor | 23 samples | 26 samples |
| P-MODE start → finish | Performance → Performance, no change/warning | Same |
| GPU memory (ADLX peak) | 80,821 MiB | 80,828 MiB |
| Windows physical free RAM minimum | 23.013 GiB | 22.953 GiB |
| Named-process background probe | Observed, possible noise false | Same |
| RGP FA enabled stderr line | Absent | **Present** |

Common executable SHA-256 \`d8f6a022fbf1b1ada3e56ac1dfb0c28cfa8a76b4eb5f4d7236e6b67aae062fb5\`; source commit \`0847585f24fae354359b19df239350fcf14e3bf7\`; source clean at build; same IQ3 PLE16 file identity (model hash not calculated for this large file). Source input SHA-256 \`8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143\` (literature), \`--prompt-slice head\`; QSA UNION OFF, f16 KV, no MTP, no warmup, batch2048.

Marker ON \`stderr.log\` and \`DeviceIdentity.RawText\` confirm \`ggml_vulkan: FA RGP markers enabled (VK_EXT_debug_utils, label prefix EVOX2_FA_)\`. This demonstrates successful **Vulkan debug-utils extension enabling and host marker path initialization**, but **does not prove any individual GPU FA region appeared in an RGP capture**: no \`.rgp\`, label-tree screenshot or dispatch matching is in the ZIP.

The monitor reports \`RDP-Tcp#0\`, \`remote_session=1\`, with no detected physical monitor candidate; record and hold this state constant for the next capture, or connect a physical display and deliberately restart controlled captures. The \`AdlxPModeConsistency.HighLoadSampleCount=0\` in each short run, so the ADLX high-load power classifier cannot independently validate clock/power behavior; the WMI P-MODE probe still reports Performance at start/finish.

**Decision:** pass native 1024 PP and monitoring; proceed to **Gate 1 final check: a small Radeon Developer Panel Vulkan RGP capture with a visible \`EVOX2_FA_\` label, actual \`KV\`, \`N\`, query tensor and shader**, using marker ON, QSA UNION OFF, and a pre-armed capture because 1024 PP lasts only ~1.9 s. Do NOT start mask heatmap Gate 2 nor claim full Gate 1 PASS until the actual RGP event-tree label is inspected. The +0.36% OFF→ON PP difference is r=1 smoke noise and must not be treated as a speed gain.


## Gate 1 RGP first generated file: capture successful, FA label not observed (2026-11-05 23:59 JST)

User reported that initial RDP \`Dispatch start index=512, count=256\` generated no file. A repeat with **start=1, count=256** generated a valid file, but in the RGP GUI the user did not find an \`EVOX2_FA_\` marker.

- Capture filename: \`llama-bench-20261105-235912976.rgp\`, **73,717,512 bytes** (~70.3 MiB), SHA-256 \`8428825fde1f195619aee16c6d3d1a11f22e5d9eb24a2645b7472516a71b5607\`. Raw file retained outside Git.
- Parsed AMD RDF container header/index (85 chunk records). It contains 2 \`SqttData\` chunks, 62 \`CodeObject\` chunks, \`TraceConfig\`, and \`TraceProcessInfo\`. This verifies structural presence of GPU trace data, **not** complete event decoding or label visibility.
- Exact RDF \`TraceConfig.controller\`: \`{"name":"renderop","config":{"enabled":true,"renderOpMode":"dispatch","numPrepRenderOps":0,"captureRenderOpCount":256,"captureMode":"absolute","preparationStartRenderOp":1}}\`.
- SQTT \`TraceConfig\`: enabled, \`memoryLimitInMb=128\`, no instruction tokens, SPM disabled.
- \`TraceProcessInfo\` confirms \`C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-vulkan-ppdiag-rgp\bin\Release\llama-bench.exe\`, not a different executable.
- Absence of \`EVOX2_FA_\` in the user's **first 256-dispatch** GUI search does not prove that the marker code fails, because the selected capture window may end before FA. No GPU-event tree screenshot or decoded dispatch inventory was included, so no definitive attribution of those first 256 dispatches is possible.
- The earlier start=512/count=256 attempt would need a sufficient number of dispatches to complete its window; no generated file alone **does not establish** that fewer than 512 occurred.

**Next focused step:** retain the 1024-token marker-ON workload and all capture options except set \`Dispatch start index=257, Dispatch count=128\`. If no capture, probe start=129/count=128; if a capture exists but no FA, inspect event names, then adjust based on observed dispatch range, not elapsed time. Stop blind capture attempts if no range contains FA; investigate event-tree grouping/debug marker visibility and whether the FA call path used the expected instrumented backend. Gate 1 RGP label visibility remains **PENDING**, not PASS.
