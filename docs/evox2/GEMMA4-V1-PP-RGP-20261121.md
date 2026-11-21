# Gemma 4 31B: v1.0.0 vs #31323 Vulkan PP FA RGP capture (2026-11-21)

## Purpose and isolation

Two **separate diagnostic branches**, preserving the production benchmark binaries:

- Original v1.0.0 core + EVO-X2 docs/tools: `investigation/gemma4-v1-pp-rgp-20261121`, based on `baseline/v1.0.0-docs-tools-only-20261115` (original engine build b12363).
- v1.0.0 plus upstream Vulkan FA #31323 and AMD Windows guard #32415: `investigation/gemma4-fa31323-pp-rgp-20261121`, based on `investigation/gemma4-v1-fa31323-20261121`.

The diagnostic adds **no shader, tensor or numerical changes**. It modifies only `ggml/src/ggml-vulkan/ggml-vulkan.cpp` and adds this guide and a UTF-8-with-BOM PowerShell resume helper. With the environment feature switch unset, the inference/capture path remains unchanged. Use **new build directories**: do not overwrite the verified 64.34 vs 170.83 tok/s binaries.

## Diagnostic environment and markers

Enable before starting llama-cli:

```powershell
$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
```

The feature enables Vulkan `VK_EXT_debug_utils` when available and prefixes the **command-buffer** submit label (not only the queue label). Example (values illustrative, actual values written by the executable):

```text
EVOX2_PP_G48_Q512_KVMAX24576_FA60 submit 0
  EVOX2_FA_I23_Q512_KV24576_HSK256 FLASH_ATTN_EXT node_...
    flash_attn_..._cm1 (..,..,..)
      vkCmdDispatch(...)
```

- `G`: sequential **Vulkan PP graphs with FA Q≥64** recorded within this process; starts at 1. This is **not** an RDP dispatch index.
- `Q`: max `q->ne[1]` across PP FA graph nodes.
- `KVMAX`: max `k->ne[1]` across PP FA graph nodes. **This is not guaranteed to equal total consumed prompt tokens**; both RGP files must be matched using actual Q/KV and per-FA shape, not graph ordinal alone.
- `FA`: number of PP flash-attention nodes with Q≥64 in the graph.
- `I`: zero-based **FA ordinal within this Vulkan graph**; not an asserted physical Gemma layer ID. Match it alongside Q/KV/head dimension, especially when fusions or graph structure change.
- `HSK`: `q->ne[0]` (query-head dimension); Gemma 4 31B uses 256 for SWA and 512 for global attention in this workload; **confirm which values actually appear in the profile**.
- The nested shader label is the selected Vulkan pipeline, whose identity should also be confirmed via RGP Events/Overview. The AMD Windows guard #32415 keeps the flipped FA shader disabled on proprietary drivers by default.
- The diagnostic logs a `evox2 pp rgp: EVOX2_PP_G...` line for every such PP graph and `PAUSED` / `RESUMED` for the chosen graph. Do not treat those host print timestamps as GPU shader durations.

## Easier RGP capture at the same PP position: pause gate

Instead of repeatedly guessing dispatch timer/dispatch count, **arm manual dispatch capture while llama-cli is paused just before the target PP graph's first submission**, then release the gate. The gate waits for earlier GPU work to finish (`device.waitIdle()`) before writing `<prefix>.ready`.

Additional environment variables:

| Variable | Example | Behavior |
| --- | --- | --- |
| `EVOX2_VK_PP_RGP_PAUSE_PREFIX` | `C:\llama-build\rgp-pp\original` | writes `original.ready`, waits for `original.go`; directory must already exist |
| `EVOX2_VK_PP_RGP_PAUSE_KV` | `24576` | pause once at the first PP FA graph with `KVMAX >= 24576` |
| `EVOX2_VK_PP_RGP_PAUSE_GRAPH` | `0` | optional: use exact `G` instead of KV threshold; positive graph number **takes precedence** |
| `EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS` | `300000` | wait timeout, 5min default; timeout **continues the run** and logs TIMEOUT |

The gate is opt-in: it requires markers enabled, a nonempty pause prefix, and a positive KV threshold or graph ID. It fires only once per process, and removes any stale `.go` file before generating `.ready`. Disable other background inference loads. The pause and debug labels are **profiling only**: do not compare total PP duration or TG speed from these runs with non-diagnostic benchmark numbers.

Example original-v1 setup in PowerShell window A (adjust worktree and the model/input keys in local.psd1):

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-v1-pp-rgp'
$prefix = 'C:\llama-build\rgp-pp\original'
New-Item -ItemType Directory -Force -Path (Split-Path $prefix) | Out-Null
Remove-Item "$prefix.ready", "$prefix.go" -ErrorAction SilentlyContinue

$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
$env:EVOX2_VK_PP_RGP_PAUSE_PREFIX = $prefix
$env:EVOX2_VK_PP_RGP_PAUSE_KV = '24576'
Remove-Item Env:EVOX2_VK_PP_RGP_PAUSE_GRAPH -ErrorAction SilentlyContinue
$env:EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS = '600000'
Remove-Item Env:GGML_VK_FORCE_FA_FLIP -ErrorAction SilentlyContinue

& "$root\tools\evox2\benchmark\Measure-LlamaCli.ps1" `
    -LocalConfig "$root\tools\evox2\benchmark\configs\local.psd1" `
    -LlamaCli "$root\build-vulkan-pp-rgp\bin\Release\llama-cli.exe" `
    -ExpectedBackend Vulkan -ModelKey Gemma4_31B -InputKey 32k `
    -Context 32768 -GenerationTokens 1 -Threads 4 -Batch 2048 -UBatch 512 `
    -GpuLayers 999 -CpuMoe 0 -FlashAttn auto -KvType f16 `
    -Fit on -PromptCacheMiB 0 -Reasoning off -Temperature 0.2 -TopP 0.8 `
    -UmaLabel 64GB -NoAdlxMonitor `
    -ExtraArgs @('-tb','4','--ctx-checkpoints','0t','--seed','1234')
```

In **PowerShell window B**, enter before starting or while window A is running:

```powershell
& 'C:\llama-build\llama.cpp-evox2-v1-pp-rgp\tools\evox2\benchmark\Resume-VulkanPpRgp.ps1' `
    -Prefix 'C:\llama-build\rgp-pp\original'
```

Window B detects `.ready`, shows the exact `G/Q/KVMAX/FA`, then asks you to click **Capture profile** in Radeon Developer Panel with **Dispatch** capture mode (try 512 dispatches initially; increase if the trace lacks the desired FA). Once RDP is armed, press Enter in window B. `.go` releases the graph. Keep `Auto capture mode=None` for this gate-driven workflow; do **not** additionally specify Dispatch timer or Dispatch range.

Repeat for the #31323 branch with a **different prefix** (`...\ported`) and new build directory (`build-vulkan-pp-rgp`). Prefer matching by KVMAX, FA ordinal/head dimension and shader labels, not a fixed dispatch number.

**Preflight:** Test once with a small positive KV threshold (e.g. 2048) to verify `.ready` + `.go` + visible RGP labels; then do the late ~24k or ~28k target. If the reported `KVMAX` does not increase as assumed, use `EVOX2_VK_PP_RGP_PAUSE_GRAPH` after inspecting stderr and match actual FA shapes.

## Capture caveats

- The AMD RDP Profiling UI documents **manual Dispatch capture** and **auto Dispatch range / Dispatch timer**. **Marker-driven start/end is documented for RRA raytracing, not RGP profiling**; the PP labels alone do not automatically trigger an RGP capture.
- New RDP 3.5+ includes `RadeonDeveloperPanelCLI` with `--rgp-auto-capture dispatch:start:count`, but that still uses dispatch numbers and may not be available on the user's installed version. The pause gate is independent of this version.
- A queued RGP manual capture must be armed before the `.go` release. Different RDP/driver versions may arm capture differently; verify with a short test instead of assuming an exact automatic trigger.
- Prefer first captures **without Collect counters**, enough to inspect Events > Event timing, selected FA shader name, per-dispatch duration and wave occupancy. Collect counters only on a later targeted profile if supported. Do not confuse group-level total GPU duration with per-shader time.
- Profiled old-v1 and #31323 branches will have separate commit hashes; their baseline source differs intentionally. The only added common functional code should be the **identical** PP diagnostic implementation, and the optimized branch retains #31323 and Windows #32415.
- Neither branch is validated on the EVO-X2 Windows compiler/RGP yet; report any build errors before treating the marker labels as confirmed. Do not add instrumentation to the verified benchmark branches.

## References

- [Prior verified Vulkan TG marker approach](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/gemma4-31b-v1-rocm-20261116/docs/evox2/GEMMA4-V1-VULKAN-TG-RGP-2026-11-16.md): queue-only labels were not visible in RGP; command-buffer submit labels were.
- [AMD RDP Profiling capture modes](https://gpuopen.com/manuals/rdp_manual/features/)
- [AMD RDP CLI arguments](https://gpuopen.com/manuals/rdp_manual/radeon_developer_panel_cli/)
