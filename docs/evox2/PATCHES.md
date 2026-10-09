# Evo-X2 downstream patch registry

## Current r5 status (2026-10-09)

The initial r5 inference source matches pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. r4 downstream inference patches, including COMMON-001, VULKAN-002, the dense MTP guard and the two TG candidates, are not ported by this bootstrap. Re-evaluate upstream support and current performance before classifying or porting a delta.

Documentation, build/measurement utilities and historical test fixtures are imported. Their presence does not mean the corresponding native patch or CMake test target is implemented in r5. The real-prompt bench and union-statistics investigation branches remain separate.

See [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md) for pending gates and [ROADMAP.md](ROADMAP.md) for the current order.

## Preserved r4 status (2026-10-09)

The full source/validation checkpoint and investigation-branch references are in
[R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md).

| Item | Current status |
|---|---|
| MoE legacy tile selection | Implemented and measured; opt-in, default OFF. |
| COMMON-001 | Split PLE16 support implemented; Vulkan/ROCm validation through 256k. |
| VULKAN-002 | Grouped-union implemented; Vulkan PP/TG validation through 256k; default OFF. |
| COMMON-002 | Historical compatibility port not applied wholesale. Uses upstream-native MTP plus the minimal dense-sidecar pool-input guard; includes diagnostics and the two TG candidates below. |
| Dense MTP indexer omission | Implemented, default OFF; Vulkan 256k normal ABBA validated. |
| Target no-op QSA invalidation suppression | Implemented, default OFF; Vulkan 256k normal ABBA validated with indexer omission enabled. |
| MTP PP overhead / ROCm PP scaling | Unresolved. ROCm long-context MTP equivalence and focused confirmation gates remain open. |
| COMMON-003 / VULKAN-001 | ROCmFPx support not implemented in r4. |
| COMMON-004 / COMMON-005 / COMMON-006 | No automatic historical port; old ROCm selected-KV decode remains deferred; COMMON-006 is an upstream-validation gate. |
| Real-prompt bench / union statistics | Implemented on separate investigation branches, not integrated into r4; statistics-OFF performance validation remains pending. |

Next work moves to a clean, separately pinned **r5 upstream-refresh validation**.
Reclassify and selectively re-port only still-needed deltas after measuring the
new baseline. See [ROADMAP.md](ROADMAP.md) for the current priority order.

## Historical r4 implementation progression (2026-10-03 to 2026-10-05)

The narrative below preserves the original progression. Statements about the
next candidate or investigation reflect those dates; use the checkpoint above
for the current state.

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
is now implemented, default OFF. The 14:50 Windows Vulkan native gate is
Complete after test position/partition corrections: policy, cache/state/
rollback and all eight A/B output pairs pass. Allocation/short real CLI now
passes 8/8 runs; MTP ON output/acceptance match and draft indexer work disappears
only in B. The 256k wall pair also passes: TG 14.76 -> 19.95 (+35.16%),
generation time -9.00755 s, matching response bytes/acceptance, no draft layout
in B and 5.499980 s target layout remaining. PP is effectively unchanged.
Normal 256k ABBA also passes 4/4: TG mean 15.220 -> 20.185 (+32.62%),
identical response/acceptance and effectively unchanged PP. Versus the earlier
normal MTP OFF reference TG19.76, the advantage is only +2.15%; PP overhead
still makes fresh-prompt total latency worse. Target source review is complete:
no-op invalidation (3.09 s of 5.50 s) is the first bounded proposal, with 128k
confirmation before expansion. Default OFF.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md).
See [short validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md)
and [implementation and commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).
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
| COMMON-002 | Native MTP loading, dense-sidecar graph guard, opt-in attribution diagnostics and guarded dense-indexer omission implemented | Earlier overnight 28/28 and short gates pass; wall reports recovered. New omission candidate passes Windows Vulkan native policy/model/state/rollback and A/B gates, then 8/8 allocation/short CLI runs and 256k wall A/B (draft layout removed) and normal ABBA (TG +32.62%, output/acceptance match); target source review complete (3.09 s no-op / 2.41 s suffix rebuilds), target no-op candidate implemented and Windows native gate Complete, then 8/8 allocation/short CLI runs pass with matched output/acceptance and target full rebuilds 57->33; 256k wall also passes 2/2 with matched output/ordered acceptance, target rebuilds 217->95, layout 5.53->2.44 s, wall TG +13.78% and PP unchanged; normal ABBA now passes 4/4 (TG mean 20.205->22.830, +12.99%, output/acceptance match); ROCm native gates and 8/8 allocation/short CLI now pass (matched output/acceptance, rebuilds58->36); ROCm256k normal collection3/3 OK (OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84), but A/B output/acceptance differ so long equivalence and isolated no-op benefit remain unresolved; B fresh-prompt evaluation+88.318s versus OFF; MTP OFF CLI/bench64k/256k collected (11 new runs OK, reused ROCm256k OFF); TG tool gaps within2.40%, ROCm PP agrees closely, Vulkan256k bench PP−19.40% versus CLI; next investigation decision including ROCm equivalence and PP workload/scaling gaps; 128k confirmation retained, default OFF |
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
Windows Vulkan build, native rollback and same-setting restore now pass in the
14:50 report, with identical A/B logits/hidden on eight output pairs. All three
allocation smokes and five short CLI gates also pass; draft indexer/layout/pool
events are absent only in B. Candidate 256k wall A/B passes with TG
14.76 -> 19.95 tok/s and generation time 34.61605 -> 25.60850 s.
Output bytes and ordered acceptance history match. Draft layout 9.767278 s
is removed; target layout remains 5.499980 s. PP gains only 0.13%, so MTP PP
overhead remains open. Normal 256k ABBA now passes with the same binary:
TG mean 15.220 -> 20.185 (+32.62%), generation time -8.247875 s, matched
output/acceptance and effectively unchanged PP. Earlier normal OFF is
TG19.76/PP265.02, so B's TG advantage is small and fresh-prompt latency still
loses. Retain the opt-in for subsequent Vulkan MTP tests; investigate retained
target layout separately and confirm 128k before wider expansion.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md) and
[implementation and Windows commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).

Target layout source investigation is complete at the current source baseline:
full acceptance still calls trim, and no-op indexer removals unconditionally
stale the layout. B-wall target cost splits into 122 no-op-associated rebuilds /
3.092231 s and 95 real suffix rebuilds / 2.407742 s. A separate default-off
no-op invalidation candidate is now implemented and retains recurrent/indexer/
attention removal calls and pending stale markers. Actual suffix reuse follows separately;
CPU layout dirtiness must not clear required pooled-key invalidation.
No runtime change is included in this review. The
[target no-op implementation plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md)
is approved and delivered: separate default-off switch, actual membership-count
check, existing dirty-state preservation, numeric target QSA tests and short/
wall/normal A/B with draft omission1 fixed. Local policy, C++ syntax, PowerShell
source and diagnostic checks pass. The19:12 Windows Vulkan native gate is now
Complete after the accessor correction: all524 vector comparisons match exactly,
with67 actual no-op suppressions and33 preserved pending stale markers. The
allocation/short CLI gate now also passes8/8 with Verified startup/runtime
evidence, matched A/B response bodies and acceptance,25 no-op suppressions
and all33 real-removal stale marks preserved. Target full rebuilds fall57->33.
Short normal TG34.81->34.86 does not establish a speedup. The256k wall gate
now also passes2/2 with matching output and ordered218-round acceptance
history:123 no-op suppressions, all95 real-removal stale marks retained,
full rebuilds217->95 and layout5.529702->2.436146 s. Wall TG19.96->22.71
(+13.78%) while PP230.12->229.92 is effectively unchanged. Diagnostic-OFF
normal ABBA now also passes4/4 with matched output/aggregate acceptance:
mean TG20.205->22.830 (+12.99%), mean PP229.940->229.565 (-0.16%). Keep source
default OFF. Residual suffix rebuilds retain2.436146 s but further TG/PP
implementation is parked: the user requests ROCm build/measurement, then
CLI/bench comparison, then the next optimization decision. New focused ROCm
short/256k and staged CLI/bench plans are prepared; local source/PlanOnly checks
pass. Windows ROCm native gates now both pass and all8 allocation/short runs
are OK with Verified runtime and matched A/B output/acceptance. The short
wall confirms23 no-op suppressions and36 real-removal stale marks retained
(full rebuilds58->36). B-normal PP48.16 is an unexplained outlier, retained
for follow-up. ROCm256k normal collection now finishes3/3 OK with the same
Verified runtime: OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84.
The short PP collapse is absent here, but A/B response/acceptance differ
(289/441 versus286/448), leaving long equivalence and isolated speedup open.
B evaluation remains88.318s slower than OFF. MTP OFF CLI/bench64k/256k is now
collected:11 new runs OK, eight bench rows/20 timed repetitions, plus the reused
ROCm256k OFF reference. TG gaps within2.40%; ROCm PP agrees closely, while
Vulkan256k bench PP216.09 is19.40% below CLI268.10. ROCm PP roughly halves
between depths in both tools without MTP. Native uint64 time-SD overflow is
identified; mean speed and throughput SD verify against samples. Bench does
not settle speculative correctness. Choose the next source investigation
separately. No inference code changed or rebuild needed.
See [CLI/bench data](R4-COMMON002-CLI-BENCH-COMPARISON-2026-10-05.md).
See [ROCm256k review](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md).
See [ROCm native/short validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md).
See [normal ABBA validation](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md) and
[ROCm/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).
See [256k wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md).
See [allocation and short CLI validation](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md).
See [implementation and Windows commands](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md) and
[target source review](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md).

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
