# r5 MTP PP Vulkan RGP — locate Draft by measured dispatch ordinals (2026-10-14)

**STATUS: b11587 Windows Vulkan build and native short role/dispatch gate PASS; 64k interval calibration and RGP index cross-check pending.** This change is an *experimental tracing aid* on `investigation/r5-mtp-pp-trace-20261013` only. No production performance optimization; do not replace the known-good b11569/b11577 binaries.

## Why another arbitrary Dispatch range is low-value

The previously labelled Vulkan b11577 64k MTP-ON RGP captures show:

| RDP Auto capture: start/count | RGP time relative to CLI launch | Estimated current input / KV | RGP visible proof |
| --- | --- | --- | --- |
| **512 / 256** | ~+40.25 s | Model initialization / graph reserve | `EVOX2_MTP_MATMUL role=target`, user event hierarchy works |
| **50,000 / 256** | ~+73.55 s | **12,288–14,336** input tokens, below QSA minKV | Target `FLASH_ATTN_EXT` / `flash_attn_f32_f16_aligned_cm1`; target MoE |
| **180,000 / 256** | **+181.721 s** | **40,960–43,008** input tokens, QSA enabled | Target `indexer_k_raw-43`, QSA indexer + matmul shaders; user searched **`role=draft` and `role=unknown` with no matches** |

The third capture is from ZIP `20261014-020121-195-cli-vulkan-b11577-ctx65536-91e77c66f839.zip` SHA256 **`0a14946c067f8b88e9e46331e06709cb260c30b0a995a7981faa58a74bf330b7`** (raw log), RGP `llama-cli-20261014-020422918.rgp` SHA256 **`f651c3c3b42dcbec6a38728f90913aca9c11c3227a1a146e927ceb0db1b8366c`**, **225,147,740 bytes**, and screenshots. Verified **same b11577** executable SHA256 `6d141c6b2e627e89c380922573f1b62a08ea48fbdb362f9e0ce31860a73ebe34`; CLI `Status=OK/ExitCode=0`, 61,789 PP tokens, PP **202.73442s (304.78 tok/s)**, 512 generated and TG **17.61017s (29.02 tok/s)**, draft accepted 295/430, `qsa-union active` reported from GPU path. **Native stderr independently records 31 draft process rows**, including draft call wall sum 4.00095s for the KV bin 32769–65536. Thus draft processing was scheduled, but the 256-dispatch RGP slice did **not** sample an identified draft event.

RGP filename time `2026-10-14T02:04:22.918+09` minus run start `02:01:21.1969024+09` = **181.7211s**. Native stderr progress `2.54.783.727` (174.784s, 40,960 tokens) and `3.01.908.645` (181.909s, 43,008 tokens) bracket the capture. The integer suffix `indexer_k_raw-43` is consistent with this stage. **RGP filename chronology is a host clock correlation, not an embedded device token counter**.

**Interpretation:** Capturing a few hundred dispatches inside a multi-layer target graph is likely too narrow to hit the later short draft graph. The absence of `role=draft` or `role=unknown` in these captured windows is *not* evidence of no draft GPU work; conversely, the code's current tensor-name role heuristic has **not yet been positively validated** for a real draft graph. A deterministic CPU-side range log addresses both possibilities.

## New source: CPU-side ordinal counter at actual Vulkan dispatch

New env flag **`GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1`**, exact literal `1` only. Changes:

- `ggml/src/ggml-vulkan/ggml-vulkan-common.h`: use a process-local/ggml-vulkan-DLL-wide atomic uint64 counter incremented **exactly once immediately before each backend `vkCmdDispatch`** issued through the existing `ggml_vk_dispatch_pipeline` wrapper. Counter is zero-based ordinal. With this flag unset there is no atomic counter increment or additional log.
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: at entry of `ggml_backend_vk_graph_compute`, snapshot the counter; at successful return print the half-open **`[dispatch_begin, dispatch_end)`** range, `dispatch_count`, the **existing graph-role heuristic** (target, draft or unknown), `n_nodes`, `first_node`, and `last_node`. Example, **illustrative, not observed**:

```text
evox2_mtp_vk_graph_v1 role=target dispatch_begin=... dispatch_end=... dispatch_count=... n_nodes=... first_node=... last_node=...
evox2_mtp_vk_graph_v1 role=draft dispatch_begin=... dispatch_end=... dispatch_count=... n_nodes=... first_node=... last_node=...
```

- No new shader, GPU readback, force-sync, compute dependency or speculative algorithm change. **Atomic increments + per-graph stderr do add CPU overhead**, so any ON/OFF PP data with this flag are *diagnostic*, not throughput benchmarks.
- **Limits:** this counter covers `ggml_vk_dispatch_pipeline` calls and uses host **recording order**; it may not exactly equal Radeon Developer Panel's process-wide *renderop* index if Vulkan dispatches occur outside this wrapper, command submission/queue order differs or RDP counts a different set of operations. Graph role names are heuristic and may be `unknown` for scheduler-split graphs. A **single RGP calibration check** at a computed draft ordinal is required, rather than assuming equality.
- New dedicated plan `tools/evox2/benchmark/configs/qwen38-r5-mtp-pp-rgp-dispatch-64k.psd1`: opt-in counters **and** existing GPU markers enabled, 64k and short, ON/OFF, while keeping Vulkan PERF_LOGGER unset. New dedicated `BuildKey=R5MtpRgpDispatchVulkan` avoids accidentally using the old b11577 executable. Existing plans/binaries unchanged.
- `tools/evox2/tests/test_mtp_rgp_dispatch_trace.py` adds four static source-contract tests. These cannot substitute for a native Windows build and a measured run.

## Windows validation and next run

```powershell
git fetch origin
git switch investigation/r5-mtp-pp-trace-20261013
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_rgp_dispatch_trace.py' -v
python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_rgp_markers.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-mtp-pp-dispatch `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

Add a **distinct** key in ignored `tools/evox2/benchmark/configs/local.psd1` under `Builds`; adapt the absolute path to actual checkout:

```powershell
R5MtpRgpDispatchVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-mtp-pp-dispatch\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

First run the short ON case with **RDP Auto capture disabled**:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-pp-rgp-dispatch-64k.psd1 `
  -OnlyJob vulkan-short -OnlyVariant on-detail -StopOnError
```

**Short gate:** exit0/runtime Verified, `ggml_vulkan: MTP PP RGP markers enabled`, and `evox2_mtp_vk_graph_v1 role=...` lines with valid increasing half-open dispatch ranges. Check whether a real **`role=draft`** record exists. If not, inspect `first_node`/`last_node` for MTP sidecar shape and repair role heuristic **before full 64k**; don't claim marker-proven role yet.

Only if the short gate is good, perform **one 64k ON run (RDP capture still disabled)**:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-pp-rgp-dispatch-64k.psd1 `
  -OnlyJob vulkan-64k -OnlyVariant on-detail -StopOnError
```

Read `stderr.log` and locate `role=draft` ranges **late in PP** (after enough target KV accumulation). A follow-up RDP trace should use start near the **middle of a selected draft interval** rather than broad guesses such as 250k/300k. Keep count≈256, capture SQTT High. Check whether RGP labels `role=draft` and `KV=` appear, and calibrate any offset between our host count and RDP's global renderop index.

**STOP conditions:** Python/static tests fail; Windows compile fails; no native `evox2_mtp_vk_graph_v1` lines; ordinal values regress or overlap in an unexpected way; all graphs classify target/unknown even when draft processing is known. Do not request additional RGP/64k work before debugging those failures.

**Tracking:** stable r5 `PATCHES.md` and `ROADMAP.md` should mark this as **experimental source committed / not built**, and retain b11569 uninstrumented measurements, b11577 marker-RGP captures and the TG-side DENSE/NOOP branches separately.

## Native Windows short-smoke gate PASSED — 2026-10-14 09:29 JST

Source archive: `20261014-092950-687-cli-vulkan-b11587-ctx32768-8c8b4d29d258.zip`, SHA256 `14e2b351d286d9d55fe9a413dd7cc1676da428cf2af93355629d41f16ecdf96c` (9 files). The ZIP contains actual `conditions.json`, `result.json` and raw `stderr.log`, not just the user's reported outcome.

- Executable **b11587**, compiled Git SHA **`1453c90634f99c1a3d392e566cc265cbab6d36c8`**, branch `investigation/r5-mtp-pp-trace-20261013`, **clean**; compiler Clang 20.1.8 / Vulkan; executable SHA256 **`90f2540f0e2af5d15ad58364a58a582a079bc27afc3084c0326595819b569318`**; runtime digest **`e9356ae6ef7fb0853cdf0e09bb6df4cc26a04c9c3e0b2e7b5da5913b9dbe8619`**, **Verified**.
- Environment includes `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1`, `GGML_VK_MTP_PP_RGP_MARKERS=1`, `LLAMA_MTP_PP_TRACE=detail`, QSA union=1 and minKV32768; **Vulkan PERF_LOGGER not set**.
- CLI `Status=OK`, exit0; short input 163 tokens, generated 32; MTP accepted **17/27 = 62.96%**. Prompt 1675.89ms (**97.26 tok/s**); TG 2019.39ms (**15.35 tok/s**). Marked/counted timings are diagnostic only, not throughput benchmark results.
- **Graph logger emitted 60 records, with role=target 16 graphs and role=draft 44 graphs, role=unknown 0**. First prompt graph `target [0,3767)` (3767 dispatches), immediately followed by `draft [3767,3846)` (79 dispatches, `n_nodes=132 first_node=norm-48 last_node=top_k_rows`). Every logged `dispatch_count = dispatch_end − dispatch_begin`, and **all 60 intervals abut exactly, without gaps or overlap**, covering `[0,64653)`.
- Cumulative logged dispatch counts: **target 61,775**, **draft 2,878**, total **64,653**. The majority is generation work on this short test, so do **not** use this ordinal as the late-KV 64k location. Actual prompt has one target and one draft graph; generation has the remaining 15 target and 43 draft graph records.
- Existing `mtp_pp_trace_v1`: one prompt row and 14 generation rows **per role**, four bins overall; all per-bin row counts, token totals and timer sums match raw detail records. The diagnostic therefore remains internally self-consistent.
- **Critical outcome: the role heuristic DID positively identify the real draft graph.** No source changes are needed before 64k. The previous target-only RGP screenshots represent limited dispatch-range samples; there is no evidence from them that the draft does not execute on GPU.

**Next measured gate:** Using the **same compiled b11587 binary** and dedicated `R5MtpRgpDispatchVulkan` build-key plan, run one `vulkan-64k / on-detail` **with Radeon Developer Panel Auto capture disabled**. In the resulting stderr find consecutive `role=target` and `role=draft` records during **PP** near ~40–55k KV and report their actual `[dispatch_begin,dispatch_end)` ordinal ranges. Then choose a **single targeted 256-dispatch RGP capture** starting just before one such draft interval (since a single draft may contribute fewer than 256 dispatches), and calibrate the offset between our recording-order ordinal and RDP absolute dispatch index; do not treat their numbering as guaranteed identical. No new binary is necessary for the 64k counter-only run.
