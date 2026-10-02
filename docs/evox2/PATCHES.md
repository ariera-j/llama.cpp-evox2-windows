# r3 downstream patch registry

## Purpose

r3 applies downstream changes in small units on top of one exact upstream baseline.

This file is the human-readable patch registry for the validated r3 checkpoint. It should answer:

- what the patch changes
- why it exists
- which backend it affects
- whether it is currently applied
- how it is validated
- what performance effect was measured
- whether a newer upstream implementation changes the need to carry the patch forward

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

The r3 branch remains the fixed comparison point while a separate upstream-refresh
branch is evaluated. A patch marked `validated` below means validated on this r3 base;
it does not mean the patch should automatically be re-applied to the refresh branch.

## Registry

| ID | Scope | Status | Purpose |
|---|---|---|---|
| COMMON-001 | common | validated | PLE16 model loading support; re-evaluate need on refreshed upstream |
| COMMON-002 | common | evaluate | validate refreshed upstream MTP against the existing Unsloth draft model before porting compatibility code |
| COMMON-003 | common | evaluate | ROCmFPx format/core support only if still required by target models |
| COMMON-004 | common | validated | incremental pooled-key cache for the QSA indexer; compare with refreshed upstream k-pool implementation |
| COMMON-005 | common | validated | gather selected QSA K/V for long-context single-token decode; likely ROCm re-evaluation candidate after refresh |
| COMMON-006 | common | evaluate | intended block-domain QSA selection now exists upstream; validate instead of implementing on b11247 |
| VULKAN-001 | Vulkan | evaluate | ROCmFPx Vulkan kernels only if still required |
| VULKAN-002 | Vulkan | evaluate | QSA grouped-union / sparse-FA PP optimization after refreshed-upstream baseline |
| ROCM-001 | ROCm | none yet | reserved for a demonstrated ROCm-specific requirement |

`evaluate` means the feature existed or was relevant in earlier work, but the next
step is to verify what the refreshed upstream already provides before carrying a
downstream implementation forward.

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

The r3 patch is intentionally limited to qwen4exp PLE tensor naming, loading, and
graph assembly. On the refresh branch, first test the refreshed upstream with the
original joined Unsloth model. Only re-port COMMON-001 if the joined path still has
the stability/resource problem or if the PLE16 model remains operationally necessary.

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
- full-block indexer RMS norm: +2.18 ms/token
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

### Validation results

COMMON-004 is validated on both Vulkan and ROCm with the PLE16 model and MTP
disabled.

| Backend | Context | Pooled cache | PP (tok/s) | TG (tok/s) |
|---|---:|---|---:|---:|
| Vulkan | 64k | OFF | 269.18 | 17.13 |
| Vulkan | 64k | ON | 262.89 | 25.95 |
| Vulkan | 128k | OFF | 159.39 | 11.91 |
| Vulkan | 128k | ON | 156.47 | 24.00 |
| Vulkan | 256k | OFF | 102.77 | 7.27 |
| Vulkan | 256k | ON | 98.63 | 21.03 |
| ROCm | 64k | OFF | 348.90 | 14.82 |
| ROCm | 64k | ON | 356.55 | 20.62 |
| ROCm | 128k | OFF | 262.67 | 9.89 |
| ROCm | 128k | ON | 261.67 | 16.44 |
| ROCm | 256k | OFF | 167.07 | 5.52 |
| ROCm | 256k | ON | 166.18 | 11.60 |

TG improvement with pooled caching enabled:

- Vulkan: +51.5% at 64k, +101.6% at 128k, +189.3% at 256k
- ROCm: +39.1% at 64k, +66.2% at 128k, +110.1% at 256k

The pooled-cache allocation grows as expected with context depth. ROCm compute
buffers are unchanged by cache ON/OFF. Vulkan retains the previously observed
compute-buffer expectation warning on successful pooled-cache runs.

ROCm residual profiling after COMMON-004 identified two remaining O(n_kv)
decode costs: full-context Flash Attention and block-score-to-full-cell
expansion. That profiling motivated COMMON-005 and the original COMMON-006
design. The refresh branch should compare this r3 implementation with the newer
upstream k-pool path rather than blindly re-applying COMMON-004.

Detailed RGP and source-trace notes are recorded in
[ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md](ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md).

## COMMON-005 - gather-based QSA decode

Status:

```text
validated
```

Implementation commit:

```text
d03c91b6342b099457de3508c5d67533a9a5f0ee
qwen4exp: gather selected QSA KV rows for decode
```

Goal:

Reduce the remaining long-context QSA attention cost after COMMON-004 by
running decode attention on selected compact K/V rows instead of feeding the
full KV cache to Flash Attention.

Primary references:

```text
ggml-org/llama.cpp
PR #28213
qwen4exp : gather-based sparse attention for QSA decode

current upstream MiniMax-M3 decode path
selected K/V/mask gather before Flash Attention
```

Implemented behavior:

- qwen4exp single-token decode only
- gathers selected K rows, V rows, and existing KQ-mask rows after top-k
- runs ordinary Flash Attention on physically compact K/V tensors
- prompt/batched/speculative paths retain the existing fallback
- short contexts retain the existing fallback through the `n_kv >= 4*width` gate
- fallback keeps the existing `n_kv_max` sparse-FA hint
- COMMON-004 pooled-key handling and `build_qsa_top_k()` are unchanged

Runtime control:

```text
QWEN4EXP_QSA_GATHER=0   # force fallback
QWEN4EXP_QSA_GATHER=1   # enable gather path where eligible
```

The current source treats unset/empty as enabled. Vulkan A/B results show that
this is not necessarily the fastest choice at every context depth, so retain
the runtime control while backend/context policy remains under evaluation.

### ROCm validation

ROCm build/backend tests, allocation-only smoke, and all 10 real-input A/B runs
passed.

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG gain |
|---|---:|---:|---:|---:|---:|
| 64k | 359.37 | 357.27 | 20.55 | 22.60 | +10.0% |
| 128k | 262.44 | 262.50 | 16.425 | 20.41 | +24.3% |
| 256k | 167.58 | 167.99 | 11.68 | 17.37 | +48.7% |

128k and 256k are ABBA averages; 64k is one OFF/ON pair. PP is effectively
unchanged.

128k -> 256k added decode latency falls from about +24.73 ms/token with Gather
OFF to +8.57 ms/token with Gather ON, removing about 65% of the residual depth
slope.

RGP confirms the intended mechanism:

```text
pre-COMMON-005 Flash Attention
128k ~= 1.452 ms
256k ~= 2.939 ms

COMMON-005 compact Flash Attention
128k ~= 41.93 us
256k ~= 42.00 us
```

The full-context Flash Attention scaling is therefore removed on the profiled
ROCm path.

The remaining repeated `k_get_rows_float` still scales approximately 2x:

```text
128k ~= 447.92 us
256k ~= 907.13 us
```

This was the post-COMMON-005 evidence for the original COMMON-006 proposal.

### Vulkan validation

Vulkan FLASH_ATTN_EXT backend tests passed 5297/5297, allocation-only smoke
passed, and all real-input A/B runs completed.

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG change |
|---|---:|---:|---:|---:|---:|
| 64k | 261.98 | 262.44 | 25.95 | 25.42 | -2.0% |
| 128k | 156.275 | 156.16 | 24.61 | 24.12 | -2.0% |
| 256k | 98.065 | 97.975 | 21.135 | 21.69 | +2.6% |

64k is one OFF/ON pair. 128k and 256k are ABBA averages.

Vulkan already has backend sparse Flash Attention support, so COMMON-005 is not
a universal speedup there. The existing fallback is slightly faster at 64k and
128k, while model-side gather is slightly faster at 256k. Both ABBA pairs show
the same direction at each depth, but the effect is only a few percent and does
not justify a precise automatic crossover threshold from the current data.

The known Vulkan compute-buffer expectation warning occurs on both Gather OFF
and Gather ON runs and is not treated as a COMMON-005 regression.

### Final interpretation

COMMON-005 is validated because correctness/build/runtime gates pass on both
backends and the intended ROCm bottleneck is removed. Performance policy remains
backend-dependent:

- ROCm: gather is strongly beneficial and increasingly valuable with context depth
- Vulkan: gather and the existing sparse-FA fallback are close; fallback wins
  slightly at 64k/128k and gather wins slightly at 256k

The refreshed upstream must be measured before deciding whether COMMON-005 is
still required. Current upstream CUDA code explicitly excludes HIP from sparse
Flash Attention, so ROCm remains the highest-value place to look for a residual
need for this downstream compact-K/V path.

Detailed final results are recorded in
[COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md).

## COMMON-006 - block-domain QSA selection upstream evaluation

Status:

```text
evaluate
```

Original r3 goal:

Remove the remaining O(n_kv) score-expansion work in `build_qsa_top_k()` after
COMMON-005 removed the full-context ROCm attention cost.

The b11247/r3 flow was:

```text
block score
  -> expand score to every KV cell through cell_blk
  -> cell-level top-k
```

The intended downstream direction was:

```text
block-domain selection
  -> expand only selected blocks to cell indices
```

Post-COMMON-005 RGP showed the repeated block-to-cell `k_get_rows_float` at
about 0.448 ms at 128k and 0.907 ms at 256k. With 12 full-attention groups per
token, its nominal increase accounts for roughly 64% of the measured
COMMON-005 ON 128k -> 256k ROCm latency increase.

### Upstream checkpoint decision

Do not implement COMMON-006 on the frozen b11247 base.

Upstream PR #29751 (`llama: fix qwen4exp`, merge commit
`66e0c17ee1741fef493312e17fe60a5d2cf5f7d5`) replaced the qwen4exp QSA/k-pool
path. In the current upstream source observed on 2026-10-02, qwen4exp now:

- computes `n_top_pool = min(n_pool, indexer_top_k / kpool)`
- applies `ggml_top_k()` directly to the pool/block score
- expands only the selected pool indices to cell indices
- appends the retained tail indices separately

That is materially the same optimization direction COMMON-006 was meant to
explore. Implementing an independent b11247 version now would create a second
lineage immediately before an upstream refresh.

### Refresh-branch validation

Treat COMMON-006 as an upstream validation item, not a downstream patch, until
measurements say otherwise:

- establish clean Vulkan and ROCm baselines on the pinned refresh commit
- compare 64k/128k/256k PP and TG against the r3 COMMON-005 checkpoint
- verify the old full-cell score-expansion `k_get_rows_float` slope is gone or
  materially reduced
- verify tail/causal/visibility behavior with real model output
- only create a new downstream delta if the refreshed upstream leaves a measured
  bottleneck or correctness gap on Evo-X2

The historical semantic requirements remain useful as review checks:

- `indexer_top_k` budget behavior
- tail-block handling
- causal/visibility masking
- tie and ordering behavior

## COMMON-002 - Unsloth MTP compatibility

Status:

```text
evaluate
```

Goal:

Load and run the existing Unsloth Qwen3.8-Flash-Next MTP draft model on the
refreshed upstream, adding only the compatibility delta that is still missing.

Upstream PR #29761 (`Qwen4Exp: add MTP`) merged on 2026-10-01. It adds qwen4exp
MTP conversion/tensor support and fixes the draft-model load path, so the old
r3 plan to port MTP support first is no longer the correct starting point.

Refresh-branch validation plan:

- test the existing Unsloth Q8_0 MTP sidecar without downstream MTP patches
- confirm draft model allocation and short-context generation
- confirm recurrent rollback behavior and no state-replay regression
- report draft acceptance statistics
- compare MTP on/off at short and long context
- separately measure long-context PP overhead
- port only the minimum compatibility change if the existing sidecar still fails

Do not combine this item with MTP-QSA work. Revisit MTP-QSA only if ordinary MTP
loses enough long-context benefit to justify its additional graph/cache complexity.

## COMMON-003 - ROCmFPx format/core support

Status:

```text
evaluate
```

Earlier work used ROCmFP4-FAST model variants from AgentionAI.

Before porting format/core changes, verify exactly what the pinned refresh
upstream already supports and what the target model still requires.

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

The 64k r2/r3 pre-implementation profile confirms that grouped-union changes PP but
is essentially neutral for steady decode TG.

Before porting:

1. establish the clean refreshed-upstream Vulkan baseline
2. measure the refreshed qwen4exp QSA/k-pool path at 128k and 256k
3. account for already-merged post-b11247 Vulkan changes before attributing a PP gap
4. determine whether the refreshed sparse-FA/QSA path already replaces enough of
   the historical grouped-union benefit
5. compare against the historical grouped-union implementation only if a material
   PP gap remains
6. port only the required delta
7. validate correctness before benchmarking the final candidate

## MTP-QSA prototype

The earlier MTP-QSA prototype remains outside the initial refresh stack.

It should only be reconsidered after:

- the refreshed main-model QSA path is validated
- COMMON-005 is re-evaluated on ROCm
- COMMON-006 upstream behavior is measured
- COMMON-002 upstream MTP compatibility is stable
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
