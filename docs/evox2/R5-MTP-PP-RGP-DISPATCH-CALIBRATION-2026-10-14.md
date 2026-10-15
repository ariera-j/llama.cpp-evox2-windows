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


## 64k ON native dispatch-ordinal calibration PASS — 2026-10-14 09:47–09:51 JST

**Evidence:** ZIP \`20261014-094739-371-cli-vulkan-b11587-ctx65536-dee8a8f1085d.zip\` SHA256 **\`53e20c2590433b6fcc3d6c4de3a57ba31fb779aa1e98bbc7e8743b40af3aeb62\`** (10 entries including parent dir). \`result.json\`: **Status OK**, **ExitCode=0**; verified binary **b11587 / compiled commit \`1453c9063\`**, executable SHA256 \`90f2540f0e2af5d15ad58364a58a582a079bc27afc3084c0326595819b569318\`, Verified runtime digest \`e9356ae6ef7fb0853cdf0e09bb6df4cc26a04c9c3e0b2e7b5da5913b9dbe8619\`; prompt 61,789 tokens; PP **186.48492s / 331.34 tok/s**; generated512, TG18.40475s / 27.76 tok/s; MTP draft acceptance **295/430 = 68.605%**, original pre-Oct-5 MTP Q8_0. \`GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1\`, GPU user-event markers, detail PP trace, Vulkan QSA union ON minKV32768.

**Important file-format detail:** In this run, **\`stderr.log\` is 0 bytes**; \`output.log\` (297,809 bytes) contains the composite console output and the **entire \`evox2_mtp_vk_graph_v1\` stream** (986 records). The empty raw stderr does **not** invalidate the trace; do not parse the wrong member. \`stdout.log\` contains only unrelated monitor output.

**Validation: all 986 records contiguous and arithmetically consistent.** Every \`dispatch_end − dispatch_begin = dispatch_count\`; every record begins at the previous record's \`dispatch_end\`; 0 initial, **1,153,078** final exclusive ordinal. Role counts: **278 target**, **708 draft**, no \`unknown\`. The first target/draft pair is initialization/reservation (**[0,3767)** Target and **[3767,3846)** Draft). Exactly **122 prompt-graph records** then **862 generation-graph records**:

| Region | Target graphs / vkCmdDispatch | Draft graphs / vkCmdDispatch | Full exclusive range |
| --- | ---: | ---: | --- |
| Setup/preflight | 1 / 3,767 | 1 / 79 | [0, 3,846) |
| **Prompt prefill 61,789 tokens** | **61 / 260,330** | **61 / 4,028** | **[3,846, 268,204)** |
| Generation of 512 tokens | 216 / 842,899 | 646 / 41,975 | [268,204, 1,153,078) |
| **All** | **278 / 1,106,996** | **708 / 46,082** | [0, 1,153,078) |

Prompt graph structure: first **30 × 2048-token caller batches** each have two Target + two Draft Vulkan backend graphs (ubatch1024); final **349-token** batch has one Target + one Draft. Every depth bin of \`mtp_pp_trace_v1\` cross-checks its row count, prompt tokens and timer sums; **31 prompt Target / 31 prompt Draft batch-level trace rows**. **Draft only 4,028 / 264,358 = 1.524% of prompt dispatch *count***, not 1.524% of GPU time; long FA kernels can be expensive individually. The extreme sampling asymmetry explains why several unrelated 256-dispatch RGP slices landed in common Target paths.

### Source-derived target / draft VK dispatch windows near late prompt

These are directly aligned to the \`slot ... cached n_tokens\` and \`prompt processing\` markers in \`output.log\`; **half-open** \`[begin,end)\` intervals with global host-recorded Vulkan dispatch ordinals.

| Prompt tokens processed | Target interval | **Draft interval** | Notes |
| ---: | --- | --- | --- |
| 40,960 | [161,999,171,123) | **[171,123,171,255)** | 2 ×66 Draft |
| 43,008 | [171,255,180,379) | **[180,379,180,511)** | 2 ×66 Draft |
| 49,152 | [199,023,208,147) | **[208,147,208,279)** | 2 ×66 Draft |
| **51,200** | **[208,279,217,403)** | **[217,403,217,535)** | **best first targeted RGP gate** |
| 53,248 | [217,535,226,659) | **[226,659,226,791)** | 2 ×66 Draft |
| 55,296 | [226,791,235,915) | **[235,915,236,047)** | 2 ×66 Draft |
| 61,440 | [254,559,263,683) | **[263,683,263,815)** | 2 ×66 Draft |
| 61,789 (last partial) | [263,815,268,136) | **[268,136,268,204)** | 1×68 Draft; not a regular full batch |

**Cross-check with the prior b11577 RGP captures:** RDP range start **50,000** samples source ordinal inside the **10,241–12,288-token Target** graph; prior RGP at start50k was captured around 12–14k KV. Range start **180,000** samples **Target** in the **40,961–43,008-token** batch and **does not reach** its Draft until ordinal180,379, outside the 256 count; prior RGP showed Target indexer \`-43\` and \`role=draft\` search was empty. This is direct, mutually consistent ordinal positioning across b11577 RGP and b11587 CPU logs, **strong evidence** that RDP and backend ordinals are nearly aligned for these workloads, but **does not prove zero offset in the next capture**.

### Recommended next GPU capture — no rebuild

**b11587 already compiled and verified.** Use existing \`qwen38-r5-mtp-pp-rgp-dispatch-64k.psd1\` \`vulkan-64k / on-detail\` unchanged and keep **both** diagnostic flags enabled to retain role/ordinal ground truth. RDP: API Vulkan, Auto capture → **Dispatch range**, **start=217,300**, **count=512** (slightly larger than previous 256 as an offset safety margin), SQTT buffer High, instruction tracing OFF, hardware counters OFF, \`GGML_VK_PERF_LOGGER\` unset. The requested capture range **[217,300,217,812)** should straddle ~**103 Target dispatch**, **132 Draft dispatch [217,403,217,535)**, and ~277 following Target dispatch **IF** RDP absolute renderop indices align with logger's ordinal in the new native run. Count512 will increase native RGP size vs 256 but reduces the risk of missing the short two-Draft interval. If 512 exceeds device capture budget, use **start=217,350 / count=256** (predicted 53 Target +132 Draft +71 Target) but this has much less tolerance for index drift.

Within RGP **Events → Event timing**, \`Group by user events\`, filter \`role=draft\` and expand \`EVOX2_MTP_MAIN role=draft\` to read **shader name / KV= / N= / Br / Bc** and GPU event durations; retain corresponding \`role=target\` in same slice. If role and FA markers fail despite \`[217403,217535)\` positioning, analyze whether RDP's ordinal differs from CPU recording order or whether GPU queue labels and graph-dispatch markers are mismatched. Do not claim successful draft GPU attribution until seen in actual RGP.

**Reproducible off-Git CSV artifacts:** \`r5_mtp_pp_64k_b11587_dispatch_graphs.csv\` (986 graph records) and \`r5_mtp_pp_64k_b11587_prompt_draft_ranges.csv\` (31 prompt batches) generated from original \`output.log\` and made available in the conversation; not committed to this repository. No source changes made based on these measurements.


## First confirmed RGP draft graph and dense FA — 2026-10-14 10:56–11:07 JST

**DRAFT GPU CAPTURE GATE PASSED — positive RGP screenshot evidence.** User ran a follow-up **b11587, 64k, MTP ON** at recommended **Dispatch range start=217,300, count=512**. The native source-run ZIP is `20261014-105604-956-cli-vulkan-b11587-ctx65536-dee8a8f1085d.zip`; native RGP `llama-cli-20261014-105935745.rgp`; two RGP Events → Event timing/Wavefront occupancy screenshots are attached to the ChatGPT conversation. **Artifact bytes/individual summary counters were not independently parsed in this documentation update**; the recorded observations below are directly visible in the two screenshots. Do not claim a verified runtime hash or PP timing for this particular repeat until the ZIP can be inspected.

**Unambiguous visible evidence:**

1. The RGP user-event tree, with event-name filter `role=dra`, shows **`EVOX2_MTP_GRAPH role=draft`** as a GPU graph interval, with a visible duration **`232,580.056 µs`** (~232.58 ms) for the selected region. The Wavefront occupancy screenshot shows **two complete successive draft graph intervals** and a partial following one; they were missed by the earlier blind 256-dispatch captures. **This fully validates the GPU-visible Draft graph role heuristic, not merely a CLI-side guess.**
2. Under the Draft graph, nested `MUL_MAT mtp_eh_proj-48 → EVOX2_MTP_MATMUL role=draft op=MUL_MAT tensor=mtp_eh_proj-48` is visible. The *inclusive* RGP marker duration is **`57,138.203 µs`** (~57.14 ms), whose nested `matmul_q8_0_q8_1` dispatch is **`56,497.154 µs`** (~56.50 ms). These two durations are nested, **not additive**. The screenshot also shows `quantize_q8_1_x4` before the matrix multiplication and norm/repeat/concat stages before projection.
3. The Wavefront occupancy/Event timeline explicitly shows `FLASH_ATTN_EXT node_42 → EVOX2_MTP_MAIN role=draft shader=flash_attn_f32_f16_aligned_cm1`, with dispatch grid displayed approximately `(64,24,1)`. This is **positive direct evidence of Draft-side dense Flash Attention actually executing on Vulkan**. The full `KV=..., N=..., Br=..., Bc=...` annotation and **the kernel's exact GPU duration are truncated/not shown** in the screenshot; do not invent them.
4. Earlier [b11587 unprofiled 64k dispatch log](#64k-on-native-dispatch-ordinal-calibration-pass--2026-10-14-09470951-jst) measured Draft **[217,403,217,535)** around 51,200 prompt tokens. The chosen next capture range **[217,300,217,812)** was designed to include that interval; the actual draft screenshot **confirms the targeting strategy works**. Without inspecting this new run's ZIP/label `KV=`, say **expected ~51k KV from prior calibration**, not "exact current-run KV verified." The RGP figure shows a draft graph around 232.58 ms, but this is an inclusive **RGP event-region interval**, not pure FA kernel time, not CPU `llama_process` time, and not an OFF→ON incremental PP cost.

**Interpretation / research priority:** Previous focus on dense draft FA alone was premature. The screenshot directly exposes **Draft `mtp_eh_proj` Q8_0 matmul of ~56.5ms** in the same graph, so its relative contribution to the full 232.6ms region must be compared with *the actual draft FA dispatch duration* before choosing KV-only prefill vs projection-oriented optimization. There can also be queue gaps, copies and graph-level synchronization; do not sum nested markers. The RGP trace **does not by itself isolate the Target's NextN/MoE incremental cost** because an MTP-OFF final-layer matched control is still needed.

**Immediate next action (no further blind 64k rerun):** In **this existing RGP**, expand `EVOX2_MTP_MAIN role=draft`, capture the **complete label including `KV=` and `N=`** and the nested `flash_attn_f32_f16_aligned_cm1` dispatch **Duration** for both consecutive Draft intervals. If visible, also inspect the Draft `MUL_MAT_ID`/FFN and NextN-related events. Then parse/compare the new native ZIP and .rgp programmatically or manually before calculating per-stage proportion. Do **not** yet claim all ~13–38sec PP penalties originate in Draft FA, or attempt a correctness-impacting KV-only change.

**No source change** from the successful b11587 diagnostic is needed now. After the stage durations are recovered, decide whether an RGP OFF comparison at the same KV is warranted.


## Draft FA GPU timing positively verified at exact KV=50,176 and 51,200 — 2026-10-14

**EVIDENCE GATE PASSED:** The user supplied a third Events → Event timing screenshot from **the same existing b11587, 64k MTP-ON, Dispatch range 217300/count512 RGP**. The screenshot shows the expanded native Vulkan pipeline and duration, including the complete `EVOX2_MTP_MAIN` marker. No additional benchmark or source modification was needed.

The screenshot's RGP event tree is **filtered to `FLASH_ATTN_EXT node_42`**, so the topmost displayed, filtered parent duration is **not the entire Draft compute graph**.

| Native RGP field | Draft microbatch at KV=50,176 | Draft microbatch at KV=51,200 |
| --- | ---: | ---: |
| GPU user-event role | `EVOX2_MTP_GRAPH role=draft` | `EVOX2_MTP_GRAPH role=draft` |
| `N` queries | **1,024** | **1,024** |
| `Br` / `Bc` | 16 / 64 | 16 / 64 |
| `n_kv_max` | 0 | 0 |
| Query tensor | `Qcur-48 (view) (permuted)` | same |
| Mask prepass shader | `fa_mask_opt` | `fa_mask_opt` |
| Mask prepass vkCmdDispatch grid | `(49,64,1)` | `(50,64,1)` |
| Mask prepass GPU duration | **1,094.154 µs** | **1,159.200 µs** |
| FA main shader | **`flash_attn_f32_f16_aligned_cm1`** | **same** |
| FA main vkCmdDispatch grid | `(64,24,1)` | `(64,24,1)` |
| **FA main GPU dispatch time** | **139,917.873 µs (139.918 ms)** | **139,159.326 µs (139.159 ms)** |
| Filtered enclosing FLASH_ATTN_EXT region | **141,012.698 µs** | **140,319.252 µs** |

The **two 1,024-token Draft FA microbatches** have summed FA-main GPU event durations **279.077199 ms**, summed mask preprocessing **2.253354 ms**, and summed enclosing **FA-filtered** region durations **281.331950 ms**. FA main is ~**99.2% of these FA-filtered intervals**, not of the complete Draft graph. This directly measures **GPU dispatch duration**, unlike prior CPU `draft_us` intervals. Both measured KV lengths are read from the actual RGP label rather than inferred from timestamps.

These are **two local observations at ~50–51k KV**, not an extrapolation to the entire 64k or 128k prompt; the small decrease in duration as KV increases by 1,024 is within potential GPU variance and does not imply a negative scaling slope.

An earlier **unfiltered** screenshot of *this same RGP capture* showed an inclusive **232.580 ms** Draft graph interval with nested `mtp_eh_proj-48` **57.138 ms** (underlying `matmul_q8_0_q8_1` dispatch **56.497 ms**). If the first FA-filtered event matches that same graph, the rough within-graph shares are **FA ~60.6%**, **projection ~24.6%**, **other ~14.8%**. **Treat these as preliminary, not a rigorously additive operator decomposition**, since the two screenshots are differently filtered and marker nesting/queue bubbles and exact event matching have not been exhaustively verified. Never add the inclusive Draft total to its nested FA or projection time.

**Research interpretation:** Draft dense FA is now **positively demonstrated** to be a costly GPU kernel during 64k prefill (~140ms per 1,024-token Draft microbatch at ~51k KV), alongside substantial Draft projection Q8_0 GEMM. This supports studying Draft prefill query/KV dependencies and potential correctness-gated KV-only design, **but not implementing KV-only yet**. Earlier 128k CPU trace also exposed about **+15.975s** Target+NextN wait-envelope difference vs OFF, separate from the ~20.023s Draft `llama_process` call envelope. The entire 64k/128k PP slowdown cannot be assigned exclusively to Draft FA from this one RGP slice.

**Next diagnostic step:** No further RGP calibration needed to prove draft FA. Optionally show **one unfiltered expanded Draft graph** with all operators and durations in the same event tree if reliable stage percentages are required. Otherwise prioritize source-only correctness/dependency review of draft prefill, then a targeted isolated optimization plan with explicit output/acceptance verification. Keep DENSE/NOOP TG patches and stable b11569 inference code untouched.
