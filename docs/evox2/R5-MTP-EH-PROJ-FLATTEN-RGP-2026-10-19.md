# r5 MTP `eh_proj` flatten — 2026-10-19 RGP and diagnostic timing reference

**Status: Windows Vulkan b11659-c192befce flatten-ON RGP event-tree capture completed; numeric Draft K/V equivalence NOT YET CHECKED. Documentation-only sync onto canonical r5 stable; no source port.**

Canonical detailed implementation/10/16 ABBA and the complete 10/19 RGP notes remain in the [experiment report](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-eh-proj-flatten-20261016/docs/evox2/R5-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-16.md) on `investigation/r5-mtp-eh-proj-flatten-20261016`. Do not mistake this stable-document snapshot for a stable source patch.

## Fixed conditions, profiling overhead observations

Unsloth Qwen3.8-Flash-Next PLE16 UD-IQ3_XXS Target, self-contained Q8_0 Draft; **61,789-token 64k prompt**, f16 K/V, `-b 2048 -ub 1024`, MTP ON, Stage-B Draft K/V-only ON, flatten ON, Vulkan QSA union ON/minKV32768. Binary **b11659-c192befce**, SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, verified runtime digest `0b8087e7c2a1ac99a6223c576dc5d6f9c19b77d2e61f3ac63bebd298333b56f8`. Both Oct 19 child runs: 0 exit, 295/430 accepted, 512 output, start/end **P-MODE Performance**, ADLX Performance-like. Their command, arguments, model, Draft, input, build and environment metadata match exactly; both have GPU markers, Vulkan dispatch trace and MTP CPU phase trace enabled.

| Condition | PP (tok/s) | Prompt time (s) | TG (tok/s) | PP-rate delta vs untraced |
| --- | ---: | ---: | ---: | ---: |
| 2026-10-16 same-binary **normal ABBA flatten-ON mean** | **349.390** | **176.847565** | see experiment ABBA table | control |
| 2026-10-19 **traces+markers ON / no RGP capture** | **330.50** | **186.955460** | **28.48** | **-5.41%** |
| 2026-10-19 **same traces+markers ON / RGP capture** | **312.20** | **197.911840** | **28.37** | **-10.64%** |

- Trace-only vs ordinary ABBA: **+10.108s prompt / -5.41% tok/s**.
- Trace+RGP vs ordinary ABBA: **+21.064s prompt / -10.64% tok/s**.
- Trace+RGP vs trace-only: **+10.956s prompt / -5.54% tok/s**.
- Native trace-only ZIP: `20261019-194034-647-cli-vulkan-b11659-ctx65536-024dd180ad0f.zip`, SHA256 `a080a377a386cd6f9c85b8a36cf6c2227688bb0495a4f38db8343faaf1ecaabf`; GPU high-load avg 109.333 W.
- Native trace+RGP ZIP: `20261019-195315-755-cli-vulkan-b11659-ctx65536-024dd180ad0f.zip`, SHA256 `0130198b570c4ec431eb09bbc1484d570830196d3af2feef39e4a62d2584fdb3`; GPU high-load avg 110.719 W.

These are **observed diagnostic/session penalties**, not randomized, isolated profiler overhead estimates. "Trace-only" means no actual RDP Auto capture: role markers and dispatch/phase logs were **still ON**. The baseline ABBA was three days earlier. Do not use profiling PP as a new performance baseline or infer exact fractions caused by logs, SQTT, power, cache or other system state.

## GPU event findings at approximately 51–53k KV

Both stderr traces record the identical Draft graph windows:

```text
role=draft [215195,215215) 20 dispatch, 32 graph nodes
role=draft [215215,215235) 20 dispatch, 32 graph nodes
```

Radeon Developer Panel Dispatch range **Start=215180, Count=64, SQTT High**. The user supplied **five consecutive Event timing screenshots** spanning both Draft graphs; there is no supplied raw `.rgp` export. Screenshot-derived measurements:

| Captured GPU event | Draft 1 flatten ON | Draft 2 flatten ON |
| --- | ---: | ---: |
| `EVOX2_MTP_GRAPH role=draft` inclusive | **9.238ms** | **9.370ms** |
| `MUL_MAT node_10` inclusive | 4.679ms | 4.752ms |
| `quantize_q8_1_x4` | 0.634ms | 0.705ms |
| `matmul_q8_0_q8_1_1` main GEMM | **4.043ms** | **4.046ms** |
| Main GEMM dispatch | **(40,64,1)** | **(40,64,1)** |
| Draft FA | **no `FLASH_ATTN_EXT` visible in complete sampled Draft graph** | likewise |

The RGP calls the key matmul **`node_10`**, not explicitly `mtp_eh_proj`; its place, source geometry and dispatch are strongly consistent with `mtp_eh_proj` flattened GEMM, but keep the naming limitation explicit. The original source estimate `(20,32,1)` was a conditional 128x128 tile model, not a guarantee; actual Vulkan shader is `matmul_q8_0_q8_1_1 (40,64,1)`. Stage-B Draft FA remains absent and explicit K/V write (`mtp_draft_cache_write_v`) appears in both sampled graphs.

Historical **different-binary** b11618 Stage-B/flatten-OFF RGP: Draft 1/2 **61.662/63.846ms**, main GEMM **56.510/58.643ms**, old `(80,1,1024)`. Relative to those older local observations: Draft inclusive GPU event ~**85.02/85.32%** shorter and main GEMM ~**92.85/93.10%** shorter. This is **not** a same-binary GPU A/B, but its order of magnitude agrees with the same-binary untraced flatten B-vs-A 64k PP gain **+1.386%, 2.451s** and 128k **+1.397%, 5.444s**. Never sum nested inclusive graph/matmul/kernel times or scale one local SQTT slice to all prompts.

## Next gates

1. Optional **same-binary A-flat-off RGP** at the same KV depth, with new dispatch ordinal calibration, to verify attribution beyond this cross-binary reference; old b11618 captures are useful only as context. Retain same b11659 executable.
2. **Required before integration: numerical Draft K/V correctness** for Stage-B OFF vs ON and Stage-B ON flatten OFF vs ON, including seq/position/state continuity and float tolerance, prompt catch-up, speculative continuation/acceptance/reject/rollback. Matching sampled output and acceptance are encouraging **but insufficient** to claim cache-value equivalence.
3. Separate selected-upstream integration candidate after these correctness gates. See [2026-10-19 research and integration plan](R5-RESEARCH-AND-INTEGRATION-PLAN-2026-10-19.md). Do not merge current branch, rerun performance ABBA with RGP enabled, or advance the r5 pin merely because this measurement was recorded.

## 2026-10-19 20:10 — A-flat-off trace and B occupancy follow-up

A source-control run `LLAMA_MTP_EH_PROJ_FLATTEN=0` completed normally on the **same b11659 Vulkan binary**, SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, identical input/model/trace flags. A trace-only: **PP326.56 tok/s / 189.213430s, TG28.61 tok/s**, Draft 295/430, P-MODE Performance→Performance, ADLX high-load avg 110.591W. Archive: `20261019-201026-929-cli-vulkan-b11659-ctx65536-30acd689bd50.zip`; SHA256 `f5cc9e8c4ca2909fa03fbaa76a96112458d9903c48048633f21f0f34d3d28749`.

**Key control discovery:** A and B have the **same** `role=draft` half-open Vulkan dispatch intervals near 51k KV: `[215195,215215)` and `[215215,215235)`, **20 dispatches per graph**. A graphs have **30 nodes**, B graphs **32 nodes** (extra reshape/view nodes). **Correction:** flatten did **not** reduce the number of dispatches in this same-binary A/B; it changes the key GEMM geometry and shader latency. Since A's ordinals were measured, reuse **RDP Auto capture Start=215180, Count=64, SQTT High** for the exact A GPU comparison, then verify both Draft events are present. The diagnostic trace-only B PP 330.50 vs A 326.56 is **+1.21%**, a non-repeated single-pair observation; the untraced ABBA +1.386% remains authoritative.

**Additional B RGP Pipeline state screenshot**: `matmul_q8_0_q8_1_1 (40,64,1)` runs wave32, 128 threads/workgroup, VGPR 185 used/192 allocated, SGPR 45 used/128 allocated, LDS 20,480B/group, no spill, theoretical occupancy **6/16 wavefronts/SIMD, LDS-limited**. Historical unflattened b11618 kernel occupancy 3/16 is a different-binary reference, not a proof that occupancy is the primary cause.

**Target→Draft compute-idle interval**: B Wavefront occupancy screenshot shows approximately 40–45ms with no visible compute wavefronts between late Target and Draft work. The source in `common_speculative_impl_draft_mtp::process()` calls `llama_get_embeddings_nextn(ctx_tgt)`, prepares an embedding batch on the host, then calls `llama_process(ctx_dft,...)`; host synchronization, target hidden-state readback, copy or submit latency are candidate contributors. The GPU Compute timeline **cannot show CPU work or uniquely attribute a DMA transfer**. At prompt `end_pos=51199`, A CPU phase trace had `hidden_get_us=3309910, draft_us=94569, prepare_us=19, verify_copy_us=22434`; B trace-only had `hidden_get_us=3242438, draft_us=42064, prepare_us=18, verify_copy_us=22595`. `hidden_get_us` **includes waiting for previously queued Target GPU compute**, so it is not 3.3s of CPU-only processing and cannot be equated with the local RGP idle gap. A host/GPU timestamp correlation would be needed to distinguish CPU, sync, memcpy or GPU queue idleness. Do not branch into that optimization before the current A RGP and Draft K/V numerical correctness gate.

## 2026-10-19 20:22 — same-binary A-flat-off RGP closes flatten GPU attribution

**Evidence:** Seven uploaded RGP Event timing / Pipeline state / Wavefront occupancy screenshots plus native diagnostic ZIP `20261019-202229-773-cli-vulkan-b11659-ctx65536-30acd689bd50.zip`, SHA256 `cd19ed5c54d3c6540efd33a570695e801ede2043a36a651d727cca3ec6a5bd1e`. The raw `.rgp` file was not uploaded, so source is screenshot-derived events rather than an exported machine-readable GPU trace. All A/B RGP captures were made using the *same b11659-c192befce*, exe SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, runtime artifact digest `0b8087e7c2a1ac99a6223c576dc5d6f9c19b77d2e61f3ac63bebd298333b56f8`; same model/input/MTP Stage B ON/64k (61,789 actual tokens)/f16 KV/QSA union minKV32768/ubatch1024, same debug/trace flags, effective flatten OFF on A vs ON on B. Both user-supplied RGP event trees sample the same two zero-output 1024-token Draft graphs around 51–53k prompt/KV. Graph dispatch intervals are identical `[215195,215215)` and `[215215,215235)` (20 each; A 30 graph nodes, B 32 reshape-related nodes). User RDP settings Start215180/Count64/SQTT High.

### Direct controlled GPU measurements (microseconds)

| Event from Event timing | A OFF Draft 1 | B ON Draft 1 | A OFF Draft 2 | B ON Draft 2 |
| --- | ---: | ---: | ---: | ---: |
| `EVOX2_MTP_GRAPH role=draft` inclusive | **61,014.624** | **9,237.963** | **63,890.600** | **9,369.707** |
| `MUL_MAT mtp_eh_proj-48` / B `MUL_MAT node_10` parent inclusive | **56,507.117** | **4,678.655** | **59,145.802** | **4,751.532** |
| `quantize_q8_1_x4` | 640.590 | 634.449 | 656.664 | 705.248 |
| main Q8 matmul dispatch | **55,865.803** | **4,042.842** | **58,487.483** | **4,045.548** |
| main dispatch | `matmul_q8_0_q8_1_0 (80,1,1024)` | `matmul_q8_0_q8_1_1 (40,64,1)` | `(80,1,1024)` | `(40,64,1)` |

Each A graph has an explicitly named `MUL_MAT mtp_eh_proj-48`. In B that source projection is reshaped into `MUL_MAT node_10`; the same surrounding graph sequence, quantize node and flattened shape support identifying it as the corresponding projection. Main Q8 kernel reductions **92.763% / 93.083%** (13.82x / 14.46x faster); entire Draft graph reductions **84.859% / 85.335%** (6.61x / 6.82x faster). Per Draft graph **51.777ms / 54.521ms** less inclusive GPU time; main Q8 reduction **51.823ms / 54.442ms**, accounting for almost the full graph reduction. Rest-of-graph envelope (`Draft inclusive - main Q8`) stays approximately **5.149/5.403ms A vs 5.195/5.324ms B**; this difference is descriptive and does not establish an exact exclusive operator-time decomposition.

**Kernel Pipeline state**, same-binary: A wave32, VGPR **256/256**, SGPR **48/128**, LDS **10240B**, no spill, theoretical occupancy **3/16 (LDS-limited)**; B wave32, VGPR **185 used/192 allocated**, SGPR **45/128**, LDS **20480B**, no spill, theoretical occupancy **6/16 (LDS-limited)**. Dispatch group size also changes (A 32 threads/workgroup, B 128). Occupancy correlates with much better tile shape and GEMM performance but is not by itself proven causal.

Both sampled Stage-B Draft graphs retain cache-write events and **no FLASH_ATTN_EXT** appears in the inspected whole trees; these observations do **not** certify numerical Draft K/V equality or ensure generation-time Draft graphs omit attention.

### Native A capture result and instrumentation reference

A capture 20:22 status OK, exit0, MTP accepted **295/430**, generated512, P-MODE Performance→Performance, ADLX high-load average **111.354W / Performance-like**, PP **309.14 tok/s** / prompt **199.876480s**, TG **28.38 tok/s**. A trace-only 20:10 (identical source/args/env, no RGP capture): PP **326.56 tok/s / 189.213430s**. Compared to its same-arm trace-only run, A captured PP rate was **-5.33%** and prompt time **+10.663s (+5.64%)**. Compared with 10/16 normal ABBA A mean **344.615 tok/s**, A trace+RGP is **-10.29%**; cross-day, nonrandomized descriptive only. Similar B trace-only **330.50** vs trace+RGP **312.20** (-5.54%); normal B ABBA mean **349.390**. Profiling runs are *not* new performance baselines and changes cannot be causally attributed exclusively to RGP given possible between-run variation.

### Closure and next action

**Mechanism/RGP gate PASSED for the tested Windows Vulkan 64k Stage-B zero-output Draft path:** shape flattening moved narrow batched `eh_proj` Q8 GEMM into large unbatched Vulkan GEMM, saving ~52–54ms of GPU time per observed 1024-token Draft graph while retaining the FA-bypassed cache-write path. The independent *normal*, marker-free same-binary ABBA still establishes whole-prompt PP gain **+1.386% at 64k / +1.397% at 128k**; do not confuse RGP-local 6.7x Draft speed with whole-inference PP speed.

**Stop GPU profiling for now. Next required gate before integration: numerical K/V correctness and continuation/rollback** across (C) Stage-B OFF, (A) Stage-B ON/flatten OFF, (B) Stage-B ON/flatten ON. Existing text/acceptance identity is insufficient. This report is *not* a declaration that any experimental source is integrated into pinned r5.

