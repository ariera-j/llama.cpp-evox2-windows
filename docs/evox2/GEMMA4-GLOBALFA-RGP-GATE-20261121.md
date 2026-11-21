# Gemma 4 31B — Target Global FA Vulkan RGP without a long dispatch capture (2026-11-21)

## Why a new gate is necessary

At PP graph `EVOX2_PP_G48_Q512_KVMAX24576_FA60`, prior successful Radeon Developer Panel **16-dispatch** profiles only reached the **first SWA FA** `FA_I0_Q512_KV1536_HSK256`. The actual Global Attention nodes have `HSK=512` and `FA-KV=24576` at G48. `GGML_VK_PERF_LOGGER` (58 PP graphs) measured the Global FA mean per layer at **1,086.73ms old vs 268.56ms ported (~4.05x faster)**, while SWA became slower. We want a matched **single Global FA RGP dispatch** for each build, without capturing hundreds of preceding operations.

## Two isolated source branches

- Original v1 source + **Global FA RGP diagnostic**: `investigation/gemma4-v1-globalfa-rgp-20261121`, based on `investigation/gemma4-v1-pp-rgp-20261121`.
- #31323+#32415 port + **same Global FA RGP diagnostic**: `investigation/gemma4-fa31323-globalfa-rgp-20261121`, based on `investigation/gemma4-fa31323-pp-rgp-20261121`.

Only `ggml/src/ggml-vulkan/ggml-vulkan.cpp` changes in addition to this runbook. The **validated original and ported 32k PP benchmark binaries and previous diagnostic branch sources are unchanged**. There are no shader source changes in these new branches relative to their own parents.

**Not yet compiled/tested on the EVO-X2:** mid-graph segmentation may have interactions with Vulkan command buffers, transfer dependencies and RDP. Do not assume a valid RGP capture or inference completion until both are proven. If any TDR or device lost occurs, stop and inspect logs; do not modify system TDR settings as a first workaround.

## New feature: pause before the first matching Global FA inside G48

Set in the **same PowerShell process** that starts `Measure-LlamaCli.ps1`:

```powershell
$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
$env:EVOX2_VK_PP_RGP_TARGET_GLOBAL_FA = '1'
$env:EVOX2_VK_PP_RGP_PAUSE_KV = '24576'
$env:EVOX2_VK_PP_RGP_PAUSE_GRAPH = '48'
$env:EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS = '120000'
$env:EVOX2_VK_PP_RGP_PAUSE_PREFIX = 'C:\llama-build\rgp-pp\old-global-g48'
Remove-Item Env:GGML_VK_PERF_LOGGER -ErrorAction SilentlyContinue
Remove-Item Env:GGML_VK_PERF_LOGGER_FREQUENCY -ErrorAction SilentlyContinue
Remove-Item Env:GGML_VK_FORCE_FA_FLIP -ErrorAction SilentlyContinue
```

**IMPORTANT:** `GGML_VK_PERF_LOGGER` must be removed (not set to `0`): the mid-graph gate changes submission boundaries and must not coexist with GPU timestamp query recording. The code defensively disables the Global gate when the built-in Vulkan performance logger is active.

The existing PP graph label is still `G48` and is still propagated to new command buffers. With `TARGET_GLOBAL_FA=1`, the **old graph-start pause is disabled**. Within the selected PP graph, the code scans each FA node in graph execution order for the first matching **`q->ne[0]=512`**, `q->ne[1]>=64`, **`k->ne[1]>=24576`**. Before that node is recorded it submits the outstanding earlier command buffer (when present), calls `ggml_vk_synchronize`, waits for GPU idle, writes the matching `<prefix>.ready`, and pauses until `<prefix>.go` is created (or the 120s timeout). This forces RDP's next few dispatches to start near the **actual Global FA** rather than the beginning of SWA Layer 0. It **changes command-buffer grouping**, not the attention math; do not use instrumented PP wall time as production throughput.

The ready/log marker will explicitly say, for example (FA ordinal illustrative):

```text
EVOX2_PP_G48_Q512_KVMAX24576_FA60_GLOBAL_FA_I5_Q512_KV24576_HSK512 node=...
evox2 global FA rgp: PAUSED ...
evox2 global FA rgp: RESUMED ...
```

`FA_I` is the zero-based **Flash Attention node ordinal in the graph**, **not necessarily the model's physical layer index**. The actual value is determined at runtime; do not assume I5.

## Build both branches without changing validated executables

Use an existing checkout from this repository and `git worktree add --detach` so branch creation does not collide with preexisting local branch names:

```powershell
$repo = 'C:\llama-build\llama.cpp-evox2-v1-fa31323'
git -C $repo fetch origin
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }

$cases = @(
    @{ Branch='investigation/gemma4-v1-globalfa-rgp-20261121'; Root='C:\llama-build\llama.cpp-evox2-v1-globalfa-rgp'; ConfigSource='C:\llama-build\llama.cpp-evox2-v1-pp-rgp\tools\evox2\benchmark\configs\local.psd1' },
    @{ Branch='investigation/gemma4-fa31323-globalfa-rgp-20261121'; Root='C:\llama-build\llama.cpp-evox2-fa31323-globalfa-rgp'; ConfigSource='C:\llama-build\llama.cpp-evox2-fa31323-pp-rgp\tools\evox2\benchmark\configs\local.psd1' }
)
foreach ($case in $cases) {
    git -C $repo worktree add --detach $case.Root "origin/$($case.Branch)"
    if ($LASTEXITCODE -ne 0) { throw "worktree failed: $($case.Branch)" }
    Copy-Item -LiteralPath $case.ConfigSource -Destination (Join-Path $case.Root 'tools\evox2\benchmark\configs\local.psd1')
    & (Join-Path $case.Root 'tools\evox2\build\Build-Vulkan.ps1') `
        -BuildDir (Join-Path $case.Root 'build-vulkan-globalfa-rgp') `
        -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
        -LlvmBin 'C:\Program Files\LLVM\bin' `
        -Parallel 4
    if (-not $?) { throw "Vulkan build failed: $($case.Branch)" }
}
```

The inherited Build-Vulkan.ps1 disables downloading the incompatible prebuilt UI assets. These runs do **not** need the ADLX monitor exe when `-NoAdlxMonitor` is specified.

## Mandatory first smoke: Global FA gate without RGP

Because this new feature **splits a Vulkan command buffer partway through the PP graph**, first verify correctness in the **original v1** build **without requesting a capture**. Use the PowerShell A and B commands below, but leave RDP idle (no Capture profile). Once `.ready` reports `G48...GLOBAL_FA_I...Q512_KV24576_HSK512`, press Enter in the helper; confirm `evox2 global FA rgp: RESUMED`, all subsequent PP graphs through G58, and `Status=OK / ExitCode 0`. `TIMEOUT`, device lost, missing Global FA label, or unexpected output are failures; do **not** attempt RGP until resolved. The PP wall rate includes both a pause and altered submission grouping and is not a benchmark. The smoke avoids conflating a new command-buffer bug with an RGP/driver capture issue.

If the no-capture smoke passes, repeat the original v1 run with a **new unique prefix** and a small RGP capture (4 dispatches), then repeat on the port. Do not reuse `.ready/.go` names from earlier runs.

## RGP capture — run original first, then ported

Keep Radeon Developer Panel open and connected **before** starting the app; under Connection enable **Disable client timeout**. Under Capture > Profiling set **Capture mode=Dispatch**, **Render op count=4** as the first trial (increase cautiously to 6 or 8 only if FA is not included), **Auto capture=None**, counters OFF, instruction tracing OFF, Delay capture OFF. A Global FA kernel may take **~1 second** on old-v1 even without profiler overhead, so avoid large captures and watch for TDR.

Run PowerShell A, original branch example:

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-v1-globalfa-rgp'
$prefix = 'C:\llama-build\rgp-pp\old-global-g48'
New-Item -ItemType Directory -Force -Path (Split-Path $prefix) | Out-Null
Remove-Item "$prefix.ready","$prefix.go" -ErrorAction SilentlyContinue

$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
$env:EVOX2_VK_PP_RGP_TARGET_GLOBAL_FA = '1'
$env:EVOX2_VK_PP_RGP_PAUSE_PREFIX = $prefix
$env:EVOX2_VK_PP_RGP_PAUSE_GRAPH = '48'
$env:EVOX2_VK_PP_RGP_PAUSE_KV = '24576'
$env:EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS = '120000'
Remove-Item Env:GGML_VK_PERF_LOGGER,Env:GGML_VK_PERF_LOGGER_FREQUENCY,Env:GGML_VK_FORCE_FA_FLIP -ErrorAction SilentlyContinue

& "$root\tools\evox2\benchmark\Measure-LlamaCli.ps1" `
    -LocalConfig "$root\tools\evox2\benchmark\configs\local.psd1" `
    -LlamaCli "$root\build-vulkan-globalfa-rgp\bin\Release\llama-cli.exe" `
    -ExpectedBackend Vulkan -ModelKey Gemma4_31B -InputKey '32k' `
    -Context 32768 -GenerationTokens 1 -Threads 4 -Batch 2048 -UBatch 512 `
    -GpuLayers 999 -CpuMoe 0 -FlashAttn auto -KvType f16 `
    -Fit on -PromptCacheMiB 0 -Reasoning off -Temperature 0.2 -TopP 0.8 `
    -UmaLabel 64GB -NoAdlxMonitor `
    -ExtraArgs @('-tb','4','--ctx-checkpoints','0t','--seed','1234')
```

In PowerShell B, with the **exact same prefix**:

```powershell
& 'C:\llama-build\llama.cpp-evox2-v1-globalfa-rgp\tools\evox2\benchmark\Resume-VulkanPpRgp.ps1' `
    -Prefix 'C:\llama-build\rgp-pp\old-global-g48'
```

When `.ready` appears, confirm the **`GLOBAL_FA_I..._Q512_KV24576_HSK512`** text rather than just `G48`. Then click RDP **Capture profile** to *arm* 4 dispatches and **immediately press Enter** in PowerShell B to create `.go`; do **not** wait for the profile to finish before resuming. Require a **`RESUMED` line**, not `TIMEOUT`, and a valid `.rgp` trace; verify `Status=OK`.

For ported repeat, switch to:
- Root `C:\llama-build\llama.cpp-evox2-fa31323-globalfa-rgp`
- Same `G48`, same `KV24576`, same `-ub 512` and `-ctk/-ctv f16`
- **Unique matching prefix** `C:\llama-build\rgp-pp\ported-global-g48`
- Its **own newly built** `build-vulkan-globalfa-rgp\bin\Release\llama-cli.exe` and local.psd1
- Same RDP settings.

Compare **Global FA** `FA_I`, Q512, actual KV24576, HSK512, the shader pipeline name, `vkCmdDispatch` dimensions and **GPU dispatch duration**. A 4-dispatch trace may contain two K/V copy kernels, a mask kernel and the single FA; if capture ends before FA, raise to 6 or 8 only on a stable run.

**Caution:** New mid-graph synchronization may perturb GPU scheduling, shape and kernel timings compared with uninstrumented runs. Use the earlier clean 32k benchmarks (64.34 vs 170.83 tok/s) for end-to-end performance, and use these traces for focused old-vs-port Global FA behavior.

## Source/docs references

- Existing 2026-11-21 [RGP pause/resume runbook](GEMMA4-V1-PP-RGP-20261121.md).
- [Timestamp Global-vs-SWA GPU analysis](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-vulkan-perf-logger-global-vs-swa-fa-32k.md).
- [RDP Manual: profiling Dispatch capture](https://gpuopen.com/manuals/rdp_manual/features/).
