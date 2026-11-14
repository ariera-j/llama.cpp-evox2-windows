# r6 ROCm/HIP GPU operator timing (experimental, 2026-11-15)

**Status: committed as an opt-in experimental diagnostic; Windows ROCm build and runtime measurement NOT YET VALIDATED.** This branch is **r6/rocm-pp-timing-20261115**, forked from **r6/combined-20261028**. It must not be used as a production performance baseline.

## Purpose

Compare Qwen3.8 Flash Next **old Unsloth UD-IQ3_XXS original 3-shard** Japanese-paper long-context PP on **EVO-X2 8060S Windows HIP**, for which existing **Strata engine 0.1.59** built-in \`STRATA_PREFILL_TIMING=1\` reported:

| Strata group | 64K paper | 128K paper |
|---|---:|---:|
| QSA total | 7.606 s | 19.184 s |
| MoE/routing | 14.717 s | 30.301 s |
| GDN | 10.087 s | 20.575 s |
| HC | 9.069 s | 18.224 s |
| GPU total | 41.853 s | 89.090 s |

The original llama.cpp upstream/r6 128K PP was around 420 seconds vs Strata around 90 seconds. Those absolute times use different engines and timer schemes. Existing llama.cpp RGP traces show FA-heavy individual regions but are **not entire-prefill per-category totals**. This branch is a first step toward accumulating those timings, not proof that FA alone explains the gap.

## Code and activation

Only **\`ggml/src/ggml-cuda/ggml-cuda.cu\`** is modified. No model code, weights, kernel math, quantization, planner, r6 optimization defaults, or upstream main is changed. The backend file is shared by ggml's CUDA and HIP builds; this experiment targets the installed **Windows ROCm/HIP** backend.

\`GGML_EVOX2_PP_TIMING=1\` (exact string "1") enables the per-GGML-execution GPU-event timer. It is OFF if the variable is absent, "0", or another value. The timer is inside the native GPU graph execution loop, after ggml backend dispatch and before/after participating op launches. It records device events on the **active compute stream**, synchronizes at the end of each graph for measurement, and releases all created GPU events before returning. It deliberately disables CUDA graph capture **when timing is enabled**, because cudaEventRecord is not safe to treat as a normal graph capture in the current prototype. This *changes execution scheduling and adds major overhead*; **never use timing-ON PP tok/s as ordinary performance data**. Timing-OFF uses the unmodified logic except for the constant runtime check.

To enable in the current PowerShell process for an **independent, diagnostic build**, not a production binary:

~~~powershell
$env:GGML_EVOX2_PP_TIMING = '1'
# Run the separately built ROCm llama-cli on a SHORT smoke input first,
# keeping the exact old-IQ3 model and original benchmark flags.
# After a smoke/build check, run the frozen Japanese paper 64K and/or 128K.
Remove-Item Env:\GGML_EVOX2_PP_TIMING -ErrorAction SilentlyContinue
~~~

Do not use \`setx\` to set the variable globally. Verify the env removal before an ordinary benchmark. Build with the existing pinned r6 ROCm build toolchain into a **new, dedicated build directory**; do not overwrite \`build-rocm-common005\`, historical \`build-rocm\`, or clean upstream. The instrumented source has **not** been compiled on the real EVO-X2; smoke-test and regression-check results are presently unknown. Preserve old main model, UMA64 GB, and baseline inference flags.

## Format of diagnostic output

One \`evox2 pp timing:\` line is emitted **per GGML CUDA/HIP backend graph invocation** in the program's diagnostic stderr. The label includes "pp" because the goal is prefill, but the current code is at **backend level** and may emit lines during decode or other graph calls. Distinguish PP graph invocations (time order and prompt evaluation boundaries) before aggregating. Example of **field layout only**, not real measurements:

~~~text
evox2 pp timing: nodes=... gpu_total_ms=...
  fa_ms=... fa_n=...
  qsa_select_ms=... qsa_select_n=...
  moe_id_ms=... moe_id_n=...
  gdn_core_ms=... gdn_core_n=...
  hc_fused_ms=... hc_fused_n=... concurrent=...
~~~

The actual line is a single line with all these fields. The parser must sum appropriately selected **PP calls**, not include the later TG calls, and retain call counts and total prompt tokens.

| Logged category | GGML op names included | Important exclusions |
|---|---|---|
| \`fa_ms\` | \`GGML_OP_FLASH_ATTN_EXT\` | Non-FA attention Q/K/V projections, masks, cache edits, generic matmuls |
| \`qsa_select_ms\` | \`LIGHTNING_INDEXER\`, \`TOP_K_MASK\`, \`TOP_K\`, \`ARGSORT\` | Indexer projection GEMMs, RoPE, other graph work |
| \`moe_id_ms\` | \`MUL_MAT_ID\` | Shared-expert generic matmuls, routing, gating, and fused ops not rooted at \`MUL_MAT_ID\` |
| \`gdn_core_ms\` | \`SSM_CONV\`, \`SSM_SCAN\`, \`GATED_DELTA_NET\` | Related normalization/projection/generic matmuls |
| \`hc_fused_ms\` | \`DSV4_HC_PRE\`, \`DSV4_HC_POST\`, \`DSV4_HC_COMB\` | HC GEMMs and fused sequences with a generic unclassified root |

**DO NOT compare these directly with Strata's QSA/MoE/GDN/HC categories**, which include additional operations. They are **GPU-event operator subtotals**, not a disjoint 100% breakdown. \`gpu_total_ms\` is the event interval on the primary stream, potentially excluding concurrently running streams that are not joined within its bounds; category sums may overlap on different streams. Each marked operator interval may include host-launch stalls and queue waits. GPU-event creation/recording and per-graph synchronization incur much more diagnostic overhead than the ordinary path (especially under Windows WDDM); this may change relative category shares, not just total time.

The classification is currently based on the GGML op at the **first node of a fused operation**; fused GPU work rooted at other op types (e.g. certain HC fused sequences beginning with \`SCALE\`) may fall in the unclassified remainder. The \`concurrent=1\` flag signals the graph has concurrent streams; do not derive exclusive wall fractions from the simple category subtotals in that case.

## Minimal validation sequence and interpretation

1. **Build check (short smoke)**: ensure ROCm/HIP compilation succeeds, \`GGML_EVOX2_PP_TIMING\` is correctly recognized and no CUDA/HIP event errors are raised; run a tiny prompt with variable absent, then variable \`1\` and verify reported fields are finite, non-negative, and \`fa_n\` or other counted ops is positive.
2. **64K paper MTP OFF**: same old-original GGUF and frozen Japanese-paper 64K source as Strata, \`-ub 1024\`, context65536, same model/full-GPU placement; capture **both native PP printout and per-graph \`evox2 pp timing\` lines**, plus GPU/PDH paging; separate the prompt graph calls from TG calls before summing. Do not infer missing-op time by subtracting category sum from total when \`concurrent=1\`.
3. **128K paper only if 64K data is sane**: input SHA / actual prompt tokens and no cache reuse must match, then examine how \`fa_ms\` and \`qsa_select_ms\` grow compared with Strata's full-stage growth. A large FA subtotal motivates sampling a representative llama RGP section and refining the op classification; a large unclassified remainder motivates a second iteration, not a forced attribution.
4. **Later refinement**: separate model-layer projection/GDN/HC/Router generic matmuls using graph node names plus fused-root metadata, or use more precise GPU/event probes per stream. Keep future improvements on this same experimental branch until tested.

For the underlying Strata observations and research plan, see [evox2-llm-experiments (PP investigation)](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/PP_ROOT_CAUSE_INVESTIGATION_PLAN_20261114.md) and [128K Strata breakdown](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/runs/2026-11-15-strata-128k-prefill-breakdown-and-llama-rocm-profiling-plan.md).

**Scope rule:** experimental local fork only; never merge into \`main\` automatically. The source change was AI-assisted and requires human review, ROCm compilation, short smoke, and CPU/GPU resource logging before interpreting profiling data.
