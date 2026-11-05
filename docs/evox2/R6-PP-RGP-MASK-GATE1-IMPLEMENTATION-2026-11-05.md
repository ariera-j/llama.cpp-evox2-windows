# Gate 1 implemented: r6 Vulkan FA RGP marker-only port (2026-11-05)

**Status:** GitHub source patch + static source-contract tests + **short-only** benchmark plan committed. **Windows native build NOT RUN; Python tests NOT RUN in a Windows worktree; model inference and RGP capture NOT RUN.** G1 is **implementation complete / validation pending**, not a GPU PASS.

**Branch** `investigation/r6-pp-fa-mask-rgp-20261105`. Originated from source feature commit `6a092fd2e60789d6ff7001cbe8e342fccff323ac`.

## Changes

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: ported r5 **marker-only** design into r6 without old r5 QSA/FA source. Exact `GGML_VK_FA_RGP_MARKERS=1` enables `VK_EXT_debug_utils` (when available) and wraps Vulkan FA **MASK_OPT, SPARSE, MAIN_SPLIT, SPLIT_REDUCE, MAIN** dispatches in `EVOX2_FA_...` regions. User-event labels report true shader pipeline name, `KV` K tensor length, `N` FA query dimension, `Br`, `Bc`, `n_kv_max`, `q` tensor name.
- Only the normal `ggml_vk_flash_attn` path is annotated. r6 QSA UNION is unchanged and must be **OFF** during the investigation. Intel Xe dual-stage FA has no custom wrapper in G1 (the EVO-X2 is AMD).
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
