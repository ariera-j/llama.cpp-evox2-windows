# r3 downstream patch registry

## Purpose

r3 applies downstream changes in small units on top of one exact upstream baseline.

This file is the human-readable patch registry. It should answer:

- what the patch changes
- why it exists
- which backend it affects
- whether it is currently applied
- how it is validated
- what performance effect was measured

Patch IDs are stable documentation identifiers. They do not need to match Git commit hashes.

## Base

```text
BASE-000
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
status: validated
```

Validation is recorded in [BASELINE.md](BASELINE.md).

## Registry

| ID | Scope | Status | Purpose |
|---|---|---|---|
| COMMON-001 | common | validated | PLE16 model loading support |
| COMMON-002 | common | planned | Unsloth MTP compatibility, after main-QSA work |
| COMMON-003 | common | evaluate | ROCmFPx format/core support only if still required by target models |
| COMMON-004 | common | validated | incremental pooled-key cache for the QSA indexer |
| COMMON-005 | common | next | gather selected QSA K/V for long-context single-token decode |
| COMMON-006 | common | evaluate | move QSA selection closer to the block domain to avoid full cell-score expansion |
| VULKAN-001 | Vulkan | evaluate | ROCmFPx Vulkan kernels only if still required |
| VULKAN-002 | Vulkan | evaluate | QSA grouped-union / sparse-FA PP optimization after COMMON decode work |
| ROCM-001 | ROCm | none yet | reserved for a demonstrated ROCm-specific requirement |

`planned` means the feature is expected to be ported or evaluated after its
prerequisites are complete.

`evaluate` means the feature existed or was relevant in earlier work, but r3 will first verify whether current upstream still needs it.

`next` means it is the current implementation target.

Current execution order is tracked separately in [ROADMAP.md](ROADMAP.md).
Patch IDs remain stable and are not renumbered when priorities change.

## COMMON-001 - PLE16 loader

Status:

```text
validated
```

Base:

```text
upstream build: b11247
upstream commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

Goal:

Support the PLE16 layout used by the converted Unsloth Qwen3.8-Flash-Next model while preserving support for the original joined PLE layout.

Source/history:

```text
LaurentZuijdwijk/llama.cpp
bf9e0a2ace3b86f77950e5516f351110baa37f5d
qwen4exp: store the n-gram table one tensor per head
```

The historical conversion uses:

```text
gguf-py/gguf/scripts/gguf_split_ple_heads.py
```

The conversion splits the combined PLE n-gram table into per-head tensors without dequantizing or requantizing the model weights. The converter remains external and is not vendored into this repository.

Changed files:

```text
src/llama-arch.h
src/llama-arch.cpp
src/models/models.h
src/models/qwen4exp.cpp
```

Behavior:

- the original joined `per_layer_token_embd.weight` layout remains supported
- the loader auto-detects the split `ple_ngram_embd.N.weight` layout
- when the joined tensor is absent, all 16 split PLE head tensors are required
- split-head row indices are converted to each head's local vocabulary range before `get_rows`
- the per-head results are concatenated back to the layout expected by the qwen4exp graph

Runtime controls:

```text
none
```

Correctness validation:

- original joined model allocation/load: Vulkan OK, ROCm OK
- PLE16 model allocation/load: Vulkan OK, ROCm OK
- 64k real-input inference: Vulkan OK, ROCm OK
- 128k real-input inference with PLE16: Vulkan OK, ROCm OK
- 256k real-input inference with PLE16: Vulkan OK, ROCm OK
- no extreme long-context slowdown, allocation failure, or crash was observed through 256k

Benchmark workload:

- Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS
- PLE16 conversion for split-layout runs
- MTP off
- f16 K/V cache
- batch 2048, ubatch 1024
- 4 CPU threads
- all model layers offloaded where supported
- Flash Attention enabled
- 1024-token generation budget
- temperature 0.2, top_p 0.8

Measured results:

| Backend | Model | Context | PP (tok/s) | TG (tok/s) |
|---|---|---:|---:|---:|
| Vulkan | original joined | 64k | 266.23 | 16.96 |
| Vulkan | PLE16 | 64k | 267.90 | 17.20 |
| ROCm | original joined | 64k | 357.84 | 14.55 |
| ROCm | PLE16 | 64k | 357.93 | 14.86 |
| Vulkan | PLE16 | 128k | 159.56 | 12.00 |
| ROCm | PLE16 | 128k | 259.41 | 9.91 |
| Vulkan | PLE16 | 256k | 103.75 | 7.30 |
| ROCm | PLE16 | 256k | 167.35 | 5.74 |

Interpretation:

- at 64k, PLE16 has only a small performance effect relative to the original joined model
- the primary purpose of COMMON-001 is reliable loading and execution of the split PLE layout, especially at long context
- PLE16 completed the 128k and 256k validation runs on both Vulkan and ROCm without the extreme slowdown or crash behavior that motivated the split layout
- long-context PP/TG still decreases with context depth; this is treated as a separate performance-optimization topic rather than a COMMON-001 correctness issue

Known limitations:

- the PLE16 conversion utility is external to this patch
- COMMON-001 does not include MTP compatibility, MTP-QSA, grouped-union QSA, or ROCmFPx support
- ROCm and Vulkan place the model buffers differently; this patch does not attempt to normalize backend-specific placement

Upstream interaction:

The patch is intentionally limited to qwen4exp PLE tensor naming, loading, and graph assembly so that later upstream changes can be compared or dropped independently.

## COMMON-004 - incremental pooled-key cache

Status:

```text
validated
```

Goal:

Reduce the long-context decode cost of the qwen4exp QSA indexer by caching
complete block summary keys instead of rebuilding pooled/normed/roped summaries
from the full raw indexer cache on every decode step.

Primary references:

```text
LaurentZuijdwijk/llama.cpp
d8ec9e66329c1340e6fc74eee9d66ea5eebdb7c4
qwen4exp: incremental pooled-key cache for the QSA indexer

LaurentZuijdwijk/llama.cpp
c659bd6d0c515e4f33f432139c71f3dfc19551de
qwen4exp: bound the pooled-cache dirty tables against speculative drafts

ggml-org/llama.cpp
PR #28699
qwen4exp: incremental pooled-key cache for the QSA indexer
```

The upstream PR is the preferred structural reference for the r3 port because
it includes later state/rollback and per-buffer allocation handling. The
Laurent version remains useful for Evo-X2/Vulkan behavior, the decode-sized
ubatch gate, and later speculative-safety fixes.

### Pre-implementation evidence

A 64k Vulkan diagnostic profile used the same PLE16 model, the same 61,789-token
input, MTP off, f16 K/V, batch 2048, ubatch 1024, and
`GGML_VK_PERF_LOGGER=1`.

| Build | QSA union | PP (tok/s, profiler on) | TG (tok/s, profiler on) | Steady GPU graph |
|---|---|---:|---:|---:|
| r2 | OFF | 221.44 | 7.78 | 44.18 ms/token |
| r2 | ON | 263.28 | 7.77 | 44.31 ms/token |
| r3 + COMMON-001 | n/a | 259.73 | 6.62 | 59.13 ms/token |

The profiler adds substantial wall-clock overhead, so its PP/TG values are not
used as absolute performance numbers. The GPU timestamp comparison is used to
locate the decode gap.

Relative to r2 union OFF, r3 adds about 14.95 ms/token of steady GPU graph time.
The following QSA-summary differences account for about 14.15 ms/token, or
94.6% of that gap:

- `CONT`: +11.38 ms/token
- full-block RMS norm: +2.18 ms/token
- QSA-related RoPE: +0.59 ms/token

The r2 graph performs the expensive full pooled-summary refill on the first
decode step and then stops rebuilding the full block set. r3 continues the
full-context work on every decode step. All profiled runs reported
`graphs reused = 127`.

The grouped-union switch is therefore not the explanation for the r2 TG
advantage and remains a separate PP optimization.

### Implemented r3 behavior

- one persistent f32 summary row per complete position block per QSA layer
- pooled buffers allocated with the QSA indexer K storage on the appropriate
  buffer type/device
- only newly completed or invalidated blocks are pooled, normalized, RoPE'd,
  and written with `set_rows`
- QSA layers only; recurrent layers are excluded using the same layer filter as
  the indexer cache
- full state loads invalidate pooled trust and refill lazily
- sequence edits clamp or reset pooled validity as required
- speculative dirty writes are bounded so a build-time dirty-table estimate
  cannot overflow at fill time
- dirty-table sizing remains safe for M-RoPE / repeated-position inputs
- pooled-cache support is limited to a single-sequence memory configuration;
  unsupported multi-sequence/server cases use the full recompute path

### Runtime controls

```text
LLAMA_QSA_NO_POOLED_CACHE=1
```

Disables the pooled path for same-binary A/B and also skips pooled-buffer
allocation so memory A/B is meaningful.

```text
LLAMA_QSA_POOLED_MAX_TOKENS=32
```

Default 32; `0` means no ubatch-size limit. The default keeps the incremental
path focused on decode-sized ubatches and preserves the reference first-decode
refill behavior.

### Explicitly outside COMMON-004

Do not combine this patch with:

- multi-sequence pooled row windows or `--parallel > 1` pooled caching
- COMMON-005 gather-based QSA decode
- Laurent `44041e78650c9f8aca2642842302dc8139907ded` reverse-scan `get_prev_tokens`
- grouped-union / Vulkan sparse-FA changes
- Unsloth MTP compatibility
- MTP-QSA
- ROCmFPx format or kernel work

### Initial validation plan

1. build Vulkan and ROCm from the same COMMON-004 source revision
2. allocation/load and short-generation smoke tests
3. MTP off
4. same-binary cache ON/OFF comparison
5. Vulkan 64k first to confirm the diagnosed cost disappears
6. Vulkan 128k and 256k for the primary TG-depth decision
7. ROCm 128k, then fill 64k/256k cells if the signal is useful
8. record PP, TG, memory, first-decode refill cost, and graph reuse
9. use interleaved/ABBA ordering for close results

Use the validated PLE16 model for long-context runs.

Primary metric:

```text
TG versus context depth
```

At 64k, recovering most of the historical r2/r3 decode gap is a useful
implementation check. The final accept/reject decision depends on correctness
and the 128k/256k depth slope, not on a single 64k threshold.

### Vulkan validation results

COMMON-004 was validated on Vulkan with the Unsloth Qwen3.8-Flash-Next
PLE16 model, MTP disabled, using same-binary pooled-cache ON/OFF comparisons.

| Context | Pooled cache | PP (tok/s) | TG (tok/s) |
|---|---|---:|---:|
| 64k | OFF | 269.18 | 17.13 |
| 64k | ON | 262.89 | 25.95 |
| 128k | OFF | 159.39 | 11.91 |
| 128k | ON | 156.47 | 24.00 |
| 256k | OFF | 102.77 | 7.27 |
| 256k | ON | 98.63 | 21.03 |

64k and 128k values are ABBA averages. The 256k result uses one OFF
and one ON run because of the substantially longer runtime.

TG improvement from the pooled cache was:

- 64k: +51.5%
- 128k: +101.6%
- 256k: +189.3%

TG from 64k to 256k decreased by about 19.0% with the pooled cache,
compared with about 57.6% with the cache disabled.

This strongly supports the pre-implementation profiling result that repeated
full pooled-summary reconstruction was the dominant long-context decode
regression.

PP is consistently lower with the pooled cache enabled on Vulkan:

- 64k: -2.3%
- 128k: -1.8%
- 256k: -4.0% (single-run comparison)

This trend was not reproduced on ROCm and remains a Vulkan-specific follow-up.

A scheduler/compute-buffer warning was also observed on pooled-cache ON runs:

```text
Vulkan0 compute buffer size of 4004.7852 MiB,
does not match expectation of 4362.8672 MiB
```

The warning appeared on successful runs and was not accompanied by a crash,
incorrect output, or benchmark failure. The same warning was not observed in
the ROCm validation runs.

### ROCm validation results

COMMON-004 was also validated on ROCm from the same source revision used for
the Vulkan validation:

```text
commit: 6559dd272fd0d5f553823e8851c78b9edc2a5016
ROCm SDK: 10.0.0
compiler: AMD Clang 23.0.0
target: gfx1151
```

The ROCm build passed the FLASH_ATTN_EXT backend test with 3982/3982 tests
passing before the long-context measurements.

The same PLE16 model and long-context workload were used with MTP disabled.
Each context depth used one cache-OFF run followed by one cache-ON run.

| Context | Pooled cache | PP (tok/s) | TG (tok/s) |
|---|---|---:|---:|
| 64k | OFF | 348.90 | 14.82 |
| 64k | ON | 356.55 | 20.62 |
| 128k | OFF | 262.67 | 9.89 |
| 128k | ON | 261.67 | 16.44 |
| 256k | OFF | 167.07 | 5.52 |
| 256k | ON | 166.18 | 11.60 |

TG improvement from the pooled cache was:

- 64k: +39.1%
- 128k: +66.2%
- 256k: +110.1%

The pooled cache therefore provides a substantial decode improvement on ROCm
as well as Vulkan.

However, the remaining TG depth scaling differs between the backends.

From 64k to 256k:

- ROCm cache OFF: 14.82 -> 5.52 tok/s, about -62.8%
- ROCm cache ON: 20.62 -> 11.60 tok/s, about -43.7%
- Vulkan cache OFF: 17.13 -> 7.27 tok/s, about -57.6%
- Vulkan cache ON: 25.95 -> 21.03 tok/s, about -19.0%

COMMON-004 removes a large context-dependent decode cost on ROCm, but a
substantial long-context slope remains after pooled-summary caching. Collect
ROCm profiling data before deciding which remaining QSA optimization should be
implemented next.

PP behavior on ROCm does not reproduce the consistent Vulkan regression:

- 64k: +2.2%
- 128k: -0.4%
- 256k: -0.5%

With only one OFF/ON pair per ROCm depth, these values should not be treated as
precise performance gains or regressions. They are sufficient to show that the
systematic Vulkan PP decrease was not reproduced on ROCm.

The pooled-cache allocation behaved as expected:

- 64k: +96 MiB context memory
- 128k: +192 MiB context memory
- 256k: +384 MiB context memory

ROCm compute-buffer sizes were unchanged between cache OFF and ON at each
context depth.

The Vulkan pooled-cache compute-buffer expectation warning was not observed in
any of the six ROCm long-context runs.

### Follow-up checks

- Vulkan shows a repeatable PP decrease with pooled caching enabled; ROCm did
  not reproduce the same systematic trend.
- Vulkan pooled-cache ON runs produced a compute-buffer expectation warning;
  the warning was not observed in the ROCm validation runs.
- Treat the Vulkan PP regression and compute-buffer warning as a likely
  backend-specific follow-up until profiling shows otherwise.
- ROCm residual profiling and source tracing are complete. At 128k -> 256k,
  `flash_attn_tile` increased from about 1.452 to 2.939 ms and
  `k_get_rows_float` from about 0.451 to 0.907 ms, while the main mat-vec time
  stayed essentially flat. The two increases account for almost the entire
  measured +23.68 ms/token latency delta.
- Source tracing identifies `k_get_rows_float` as the block-score to full-cell
  expansion in `build_qsa_top_k()`, and shows that QSA still passes full K/V to
  Flash Attention after selection. HIP does not currently use the sparse-FA
  `n_kv_max` hint, so the ROCm attention path continues to scale with full
  context depth.
- COMMON-005 is therefore selected as the next implementation target.
- COMMON-004 itself is considered validated on both Vulkan and ROCm; the items
  above are follow-up optimization/debugging work rather than blockers.

Detailed RGP and source-trace notes are recorded in
[ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md](ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md).

## COMMON-005 - gather-based QSA decode

Status:

```text
next
```

Goal:

Reduce the remaining long-context QSA attention cost after COMMON-004 by
running decode attention on the K/V rows selected by the indexer instead of
turning the selection back into a mask over the full KV cache.

Primary references:

```text
ggml-org/llama.cpp
PR #28213
qwen4exp : gather-based sparse attention for QSA decode

current upstream MiniMax-M3 decode path
selected K/V/mask gather before Flash Attention
```

Profiling and source evidence:

- RGP 128k -> 256k shows `flash_attn_tile` growing about 2.02x
  (1.452 -> 2.939 ms per observed full-attention layer)
- `k_get_rows_float` grows about 2.01x (0.451 -> 0.907 ms)
- with 12 full-attention layers per token, the two increases explain about
  23.31 ms/token versus the measured 23.68 ms/token latency increase
- `build_qsa_top_k()` expands block scores back to full cell granularity before
  top-k; this is the likely source of the profiled `k_get_rows_float`
- `build_attn_qsa()` constructs a sparse full-length mask but obtains K/V from
  the full KV cache and passes those full tensors to `build_attn_mha()`
- the graph sets `n_kv_max` to the QSA selection width (2051 for top_k=2048,
  ratio=4), but the current HIP sparse-FA implementation is disabled and the
  ROCm path still scans the full K/V length
- Vulkan already has a sparse mask compaction path, and MiniMax-M3 provides a
  model-layer selected-K/V gather precedent

Basic implementation policy:

- begin with qwen4exp single-token decode
- gather selected K/V and the required mask rows into compact tensors after
  top-k selection
- run ordinary Flash Attention on the compact tensors so the first prototype
  does not depend on adding HIP sparse-FA backend support
- leave prompt/batched QSA behavior unchanged initially
- retain a short-context gate so gather overhead does not become a regression
- provide a runtime A/B switch
- validate selected-row/mask correctness before performance acceptance
- use 128k and 256k ABBA measurements as the main depth-scaling decision points

Detailed tensor shapes, row-index construction, fallback conditions, and the
runtime-control name are intentionally deferred to the COMMON-005 design step.

This patch remains separate from COMMON-004 and from COMMON-006 so attribution
stays clean.

## COMMON-006 - block-domain QSA selection candidate

Status:

```text
evaluate
```

Goal:

Remove the remaining O(n_kv) score-expansion work in `build_qsa_top_k()` after
COMMON-005 has addressed full-context attention.

Current qwen4exp selection flow:

```text
block score
  -> expand score to every KV cell through cell_blk
  -> cell-level top-k
```

Candidate direction:

```text
block-domain selection
  -> expand only selected blocks to cell indices
```

The RGP source trace makes this worth evaluating because the likely
block-to-cell `k_get_rows_float` grows from about 0.451 ms at 128k to about
0.907 ms at 256k.

Do not combine this with COMMON-005. The design must preserve the qwen4exp
reference semantics around:

- `indexer_top_k + compress_ratio - 1`
- the tail block
- causal/visibility masking
- tie and ordering behavior

Treat COMMON-006 as a separate correctness-first A/B only after the COMMON-005
path is stable enough to provide a fixed baseline.

## COMMON-002 - Unsloth MTP compatibility

Status:

```text
planned
```

Goal:

Load and run the Unsloth MTP draft model used in the earlier Evo-X2 tests.

The r2 work required compatibility handling beyond the clean upstream baseline. r3 should port only the minimum compatibility change needed by the current upstream source.

COMMON-002 is deliberately scheduled after COMMON-004 and the first main-QSA
optimization pass so MTP measurements are not confounded by a moving target.

Validation plan:

- draft model allocation succeeds
- short-context generation succeeds
- MTP acceptance statistics are reported
- compare MTP on/off at short and long context
- test whether long-context MTP benefit shrinks as draft dense-attention cost grows
- separately measure long-context PP overhead

Do not combine this patch with MTP-QSA work.

If ordinary MTP loses most or all of its long-context benefit, that becomes an
explicit trigger to reconsider the frozen MTP-QSA prototype later.

## COMMON-003 - ROCmFPx format/core support

Status:

```text
evaluate
```

Earlier work used ROCmFP4-FAST model variants from AgentionAI.

Before porting format/core changes, verify exactly what current upstream b11247 already supports and what the target model still requires.

Only missing functionality should be carried forward.

## VULKAN-001 - ROCmFPx Vulkan kernels

Status:

```text
evaluate
```

Port only if the target ROCmFPx model requires downstream Vulkan kernel support after COMMON-003 evaluation.

Keep format/core support and Vulkan kernel support as separate reviewable changes where practical.

## VULKAN-002 - QSA grouped-union / sparse-FA PP optimization

Status:

```text
evaluate
```

Earlier r2 measurements showed a large long-context prefill benefit from a grouped-union QSA path.

The 64k r2/r3 pre-implementation profile confirms that grouped-union is a PP
optimization: r2 union ON/OFF changed profiled PP from 221.44 to 263.28 tok/s,
while steady decode GPU time remained 44.18 versus 44.31 ms/token.

r3 must not assume the old patch is still optimal because the new base already contains newer upstream Vulkan/QSA changes.

Before porting:

1. complete COMMON-004
2. implement/evaluate COMMON-005
3. evaluate COMMON-006 only if its residual score-expansion cost remains worth targeting
4. complete the selected small post-b11247 Vulkan A/B tests
5. determine whether the upstream Vulkan sparse-FA work around `#28105` can be
   enabled or adapted for qwen4exp
6. compare that route with the historical grouped-union implementation
7. port only the required delta
8. validate correctness before benchmarking
9. use 128k and 256k as the primary PP decision points

Historical r2 results remain strong evidence that the idea is worth
re-evaluating, but they are not r3 baseline values.

## MTP-QSA prototype

The earlier MTP-QSA prototype is intentionally outside the initial r3 patch stack.

It should only be reconsidered after:

- COMMON-004 is validated
- COMMON-005 is decided or remaining full-context attention cost is characterized
- COMMON-002 is stable
- normal MTP on/off measurements are complete
- long-context MTP loses enough benefit to justify draft-QSA complexity, or a
  separate new performance case justifies the added graph/cache complexity

## Patch documentation template

Add a section for every patch that reaches implementation status.

Recommended fields:

```text
ID:
scope:
status:
base commit:
purpose:
source/history:
changed files:
build requirements:
runtime controls:
correctness validation:
benchmark workload:
benchmark result:
known limitations:
upstream interaction:
```

## Commit discipline

A patch should not be marked `validated` merely because it compiles.

For this project, validation normally means:

1. targeted build succeeds
2. relevant backend test succeeds
3. target model loads
4. target workload completes
5. result is compared to the immediately preceding baseline
6. logs are retained outside Git when they are too large or machine-specific
