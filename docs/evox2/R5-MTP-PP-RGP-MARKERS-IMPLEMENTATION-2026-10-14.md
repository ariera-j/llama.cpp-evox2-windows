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
