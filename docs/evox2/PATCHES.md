# Evo-X2 downstream patch registry

## Current r4 status

The r4 base is pinned at `bed0a856606ee4a24a164066f73d2379447033f5` on
`r4/upstream-refresh-20261002`. A diagnostic Vulkan MoE tile-selection switch is
now prepared; its default preserves the upstream selection. COMMON-001 split-PLE16
compatibility is validated through 256k; the historical COMMON-004/005 optimization
ports remain deferred. Windows profile A/B and both 939/939 MUL_MAT_ID
test runs pass. Legacy selection reduces PP MoE GPU time by 25.22% and total
PP GPU time by 8.82%. Normal 64k ABBA also passes: PP mean 248.475 -> 268.985
tok/s (+8.25%, 18.959 s less prompt time). TG mean is 25.195 -> 24.565 (-2.50%);
two short generations per mode do not establish TG equivalence or regression.
The scoped PP diagnosis is complete; keep the opt-in switch. Tensor-level
GET_ROWS diagnostics passed on Windows: steady GPU 40.671 ms/token, including
2.487 ms GET_ROWS across 124 calls. Cached pooled-key gathering contributes
1.662 ms (66.82% of GET_ROWS); incremental raw-key gathering is only 0.030 ms.
This isolates a residual cache-read cost, not missing incremental caching.
The pre-port reference is preserved. COMMON-001 was committed at `a60a57879...`
and the subsequent small GET_ROWS 128x4 candidate at `109e238b...` was profiled
on Windows. Steady cached gather is 1.658893 -> 1.671003 ms/token and GPU total
40.688344 -> 40.716906 ms/token (OFF -> ON), with both runs OK. No useful gain
was observed: keep default OFF, skip normal ABBA and long-context expansion for
this candidate, and advance to VULKAN-002. Dedicated value-test logs were not
included in that profile archive; no numerical pass is asserted.
See [R4-GET-ROWS-128X4-AB-2026-10-03.md](R4-GET-ROWS-128X4-AB-2026-10-03.md).
See [R4-GET-ROWS-PROFILE-2026-10-03.md](R4-GET-ROWS-PROFILE-2026-10-03.md).
See [R4-MOE-TILE-AB-2026-10-03.md](R4-MOE-TILE-AB-2026-10-03.md).
Clean 64k/128k/256k runs now pass on both backends.
COMMON-006 remains an upstream-validation gate. The registry and measurements below
are the historical r3 checkpoint frozen at
`0a93fcbb8e5bcf51b331275c4f4b142d822168d6`, not r4 validation.

VULKAN-002 `5814fbe99...` now passes the Windows build, 18/18 GPU OFF/ON tests,
64k profile/normal ABBA and PLE16 128k/256k ABBA. Normal PP gains reach +65.2% /
+100.6%, with TG effectively unchanged. Keep the default OFF; validated target
runs explicitly enable union. COMMON-002 dense MTP now completes all 28 overnight
Vulkan/ROCm runs through 256k. Investigate its long-context TG regression first,
then MTP PP overhead and ROCm PP scaling; COMMON-005's historical decode port
remains deferred. See
[R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md)
for implemented opt-in diagnostics and build identity checks; the rebuilt Vulkan
allocation/short diagnostic gate now passes.
The wall collection now completes all three inference runs and identifies a
15.015 s CPU layout cost at 256k MTP ON. The user has recovered all three reports
with the script-only startup-capability-probe classification fix; no GPU rerun.
Source review confirms that the ratio-zero MTP graph omits pool inputs while
memory still maintains an indexer. A default-off dense-draft indexer omission
is now implemented, default OFF; its Windows correctness/performance gates
remain pending. See [implementation and commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).
Both diagnostic
wrappers now resolve relative paths against PowerShell's location, and the
updated Windows path/pipeline/recovery fixture passes. The concrete candidate
plan adds eligibility, same-setting state/rollback and focused A/B gates. See
[R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
[R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md) and
[R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md).
See [R4-COMMON002-SHORT-VALIDATION-2026-10-04.md](R4-COMMON002-SHORT-VALIDATION-2026-10-04.md);
[R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md) and
[R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).

See [BASELINE.md](BASELINE.md) for the current r4 gates.

## Provisional r4 decisions through 256k (updated 2026-10-04)

These decisions apply to the pinned r4 source, not moving upstream master.
Historical r3 `validated` statuses below remain unchanged.

| ID | Upstream coverage in r4 | Provisional action |
|---|---|---|
| COMMON-001 | Joined-PLE upstream path plus adapted split PLE16 support | Completed; Original/PLE16 load and 64k gates, PLE16 128k/256k validated on both backends |
| COMMON-004 | Persistent pooled keys and incremental dirty/new-pool updates exist | Do not port the old cache; scoped Vulkan cached-gather 128x4 gate closed without promotion |
| COMMON-002 | Native MTP loading, dense-sidecar graph guard, opt-in attribution diagnostics and guarded dense-indexer omission implemented | Earlier overnight 28/28 and short gates pass; wall reports recovered. New omission candidate passes local policy/syntax/diagnostic checks; Windows native model/state/rollback and focused performance gates pending, default OFF |
| COMMON-005 | qwen4exp passes full K/V plus a selection mask; HIP sparse-FA dispatch is disabled | Deferred: mainly ROCm decode; retain its validated r3 evidence and revisit when ROCm is needed |
| VULKAN-002 | Adapted grouped-union PP added without replacing upstream sparse decode | Validated opt-in on Evo-X2 through 256k; keep default OFF and preserve the measured baseline |

The following historical regression gate led to the completed MoE diagnosis
above. The new user-directed order (GET_ROWS reference, COMMON-001, then TG/QSA
work) supersedes the earlier priority discussion below.

Before the optimization ports, investigate the Vulkan r3-to-r4 slowdown:
64k original-model PP is down 6.3%; TG versus the initial COMMON-004 ON
checkpoint is down 5.2% at 64k, 5.0% at 128k, and 8.4% at 256k. Neither r3 nor r4 has
VULKAN-002, so its absence does not explain this regression signal.
COMMON-004 is functionally covered but performance parity remains unverified.
A matched rerun/profile gate now precedes implementation priority 1.

Priority favors long-context wall-clock time: 128k Vulkan prompt evaluation
is 751 s versus 20 s of generation. COMMON-005 remains the strongest decode
candidate, and may move first if its residual bottleneck is confirmed and the
Vulkan port needs substantial investigation. COMMON-001 moves first if the
joined-layout comparison is needed or PLE16 is required. The 256k clean run passed.
At 256k, ROCm TG is 12.23 versus r3 Gather OFF 11.68 / ON 17.37;
Vulkan PP is 126.76 versus the r2 grouped-union reference 177.01.
These cross-version/layout gaps support continued investigation, not gain forecasts.
See [R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md)
for source evidence, comparison limits, and implementation gates.

### First r4 Vulkan profile (64k)

The first logger run completed with 61 prefill and 127 decode timing blocks.
Prefill FA accounts for 43.0% of measured GPU operator time (62.5% at the last
full ubatch). The current Vulkan sparse dispatch excludes the observed 1024/349
query prefill batches. Steady decode averages 40.60 ms of GPU operator timings;
pool norm shapes support incremental updates rather than full-pool recomputation.
See [R4-VULKAN-PROFILE-64K-2026-10-03.md](R4-VULKAN-PROFILE-64K-2026-10-03.md).

The matched COMMON-004 + Original profile is now available. GPU operator time
increases from 233.203 to 251.893 s for PP and 39.022 to 40.597 ms/token for
steady TG. PP MoE matmul accounts for +16.634 s; FA changes by only +0.735 s.
First isolate upstream `94a0ae3e7` (MoE tile selection) with a targeted A/B.
TG GET_ROWS + QSA fused/top-k timing increases by 1.022 ms/token; obtain tensor
names/shapes before assigning this to pooled-key gathering. Keep the incremental
cache and pool-domain selection; neither wholesale COMMON-004 restoration nor
VULKAN-002 explains the measured regression yet. Confirm fixes with the logger off.
See [R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md](R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md).

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

Historical clean r3 validation is recorded in [R3-BASELINE.md](R3-BASELINE.md).

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

Current r4 priority (2026-10-04): deferred while Vulkan/COMMON-002 MTP is
prioritized. The validated status and implementation below describe r3.

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

Current priority (2026-10-04): active after validated VULKAN-002; COMMON-005's
historical ROCm decode port is deferred. Pinned-source inspection is complete: native sidecar
loading, HC-wide hidden transfer, MTP-layer QSA and bounded recurrent rollback
are present. The dense sidecar's unused QSA-input assertion is fixed by the
layer-ratio guard. Rebuilt Vulkan allocation and 32k OFF/ON generation pass;
TG improves in the first pair but total latency increases for 128 generated
tokens. The overnight matrix now passes 28/28 runs through 256k. TG OFF -> ON
at 256k is Vulkan 19.76 -> 15.245 and ROCm 12.405 -> 10.955 tok/s. Vulkan
128k/256k acceptance stays near 67%, so acceptance alone does not explain the
loss. Dense draft/catch-up work, CPU pool-layout rebuilding after sequence edits,
unused dense-draft indexer bookkeeping and small-query verification dispatch
need separate timing. Exhaustive output/rollback equivalence remains unproven.
Investigate TG first, then MTP PP overhead, then ROCm long-context PP scaling.
See [R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md)
for all results and focused diagnostic gates, and
[R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md)
for the initial source review, compatibility fix and matrix plan.

Diagnostics, artifact identity and the focused wall collection are complete.
The bounded optimization is implemented; design:
[R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
based on the
[layout source review](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md).
The default-off opt-in omits allocation only for the supported single
ratio-zero MTP block and retains hybrid, attention and recurrent handling.
Next validate the Windows build, rollback and same-setting restore before
focused 256k wall A/B and unprofiled ABBA. See
[implementation and Windows commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).

Refresh-branch validation plan:

- test the existing Unsloth Q8_0 MTP sidecar without downstream MTP patches
- confirm draft model allocation and short-context generation
- confirm recurrent rollback behavior and no state-replay regression
- report draft acceptance statistics
- compare MTP on/off at short and long context
- separately measure long-context PP overhead
- port only the minimum compatibility change if the existing sidecar still fails

Keep historical downstream MTP-QSA changes outside this compatibility gate.
Ordinary upstream MTP already uses QSA when its pool/compression metadata is
present; any additional prototype must demonstrate a missing delta and value.

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

r4 status:

```text
validated opt-in on Evo-X2 through 256k; default OFF
```

Implementation `5814fbe99e9249e8ac2c4c2e9b977c05735b0912` adapts the r2
64-query grouped-union/gather path to current FA, with final remapped cell-id
metadata, device-local counts and dynamic flag 32 separate from sparse bit 16.
It preserves the current selector/cache and one-query sparse/decode fallback.

Windows build and 18/18 GPU tests pass OFF/ON. Profile and normal 64k gates pass,
and PLE16 normal ABBA at 128k/256k yields PP 178.97 -> 295.68 and
132.96 -> 266.75 tok/s (+65.2%/+100.6%), with effectively neutral TG.
The recorded earlier ROCm PP is 279.80/185.90, so Vulkan now leads this tested
long-context workload. Source defaults stay OFF; broader device/model/default
promotion and ordinary MTP validation remain separate.

The two Vulkan-specific switches in the tested baseline are legacy MoE tile
selection=1 (already used at COMMON-001) and union=1. GET_ROWS 128x4 remains 0.
These switches do not provide ROCm acceleration. COMMON-001 is a common layout
compatibility patch; optional FA metadata does not replace ROCm's algorithm.

- Results and comparison limits:
  [R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).
- Implementation and original execution gates:
  [R4-VULKAN002-IMPLEMENTATION-2026-10-03.md](R4-VULKAN002-IMPLEMENTATION-2026-10-03.md).
- Historical donor/source review:
  [R4-VULKAN002-PORT-REVIEW-2026-10-03.md](R4-VULKAN002-PORT-REVIEW-2026-10-03.md).

## MTP-QSA prototype

The historical downstream MTP-QSA prototype remains outside the refresh stack.
Pinned upstream's ordinary MTP graph already builds its own QSA/indexer path.
The old assumption that draft QSA must first be added no longer applies.

Reconsider a prototype only after COMMON-002 sidecar compatibility, actual QSA
activation and normal MTP OFF/ON/long-context overhead are measured. Identify a
concrete gap relative to the pinned implementation and validate only that delta.
Deferred ROCm COMMON-005 work is not a prerequisite for ordinary Vulkan MTP.

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
