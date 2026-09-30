# Evo-X2 r3 optimization roadmap

Snapshot: 2026-09-30 (pre-COMMON-004 implementation)

This document records the current execution order for the r3 optimization work.
Patch IDs remain stable even when implementation priority changes.

## Current base and policy

The r3 source baseline remains:

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

The base is intentionally kept fixed while the current optimization sequence is
measured. r3 does not automatically rebase to every new upstream commit.

New upstream changes are evaluated as isolated A/B candidates when practical.
A full upstream refresh is reconsidered only at explicit checkpoints.

## Completed foundation

The following work is already part of the current r3 branch:

- clean upstream-first b11247 Vulkan and ROCm baselines
- COMMON-001 PLE16 loader support, validated through 256k on Vulkan and ROCm
- benchmark wrappers for real-input `llama-cli` and synthetic `llama-bench`
- benchmark matrix runner with environment-variable A/B support
- Vulkan and ROCm build wrappers with build manifests
- shared BoringSSL and LLVM OpenMP dependency caching for fresh build directories

The long-context decrease that remains after COMMON-001 is treated as an
optimization problem, not as a PLE16 correctness issue.

## Completed diagnostic gate: r2 versus r3 decode profile

Before implementing COMMON-004, a 64k Vulkan profile was run on the same PLE16
model and the same 61,789-token input with MTP disabled and
`GGML_VK_PERF_LOGGER=1`.

The steady single-token decode graph averaged:

| Build | QSA union | Steady GPU graph time |
|---|---|---:|
| r2 | OFF | 44.18 ms/token |
| r2 | ON | 44.31 ms/token |
| r3 + COMMON-001 | n/a | 59.13 ms/token |

The grouped-union switch changes r2 prefill substantially but does not explain
its TG advantage: the steady decode difference between union OFF and ON is only
about 0.3%.

Compared with r2 union OFF, the r3 steady decode graph is about 14.95 ms/token
slower. Three QSA-summary operations explain about 14.15 ms/token of that gap:

- `CONT`: +11.38 ms/token
- full-block indexer RMS norm: +2.18 ms/token
- QSA-related RoPE work: +0.59 ms/token

Together they account for about 94.6% of the measured steady GPU-time gap.
The r2 graph performs the expensive full refill on the first decode step, then
keeps the pooled summaries incrementally; the r3 graph rebuilds the summaries on
every decode step.

All three profiled runs reported `graphs reused = 127`. The r3 Flash Attention
portion was actually faster than r2 in this profile, which further isolates the
missing pooled-summary reuse as the primary first target.

This diagnostic result strengthens, rather than changes, the decision to make
COMMON-004 the next implementation patch.

## Current execution order

### 1. COMMON-004 - incremental pooled-key cache

This is the next implementation target.

The QSA indexer currently has an O(context depth) component because pooled block
summary keys are reconstructed from the raw indexer cache during every decode
step. The reference pooled-key implementation keeps one persistent summary row
per complete position block and updates only newly completed or invalidated
blocks.

Primary references:

- LaurentZuijdwijk/llama.cpp commit
  `d8ec9e66329c1340e6fc74eee9d66ea5eebdb7c4`
  (`qwen4exp: incremental pooled-key cache for the QSA indexer`)
- Laurent follow-up
  `c659bd6d0c515e4f33f432139c71f3dfc19551de`
  (`qwen4exp: bound the pooled-cache dirty tables against speculative drafts`)
- upstream draft PR `ggml-org/llama.cpp#28699`
  (`qwen4exp: incremental pooled-key cache for the QSA indexer`)

The upstream PR remains the preferred structural reference because it contains
later state/rollback and per-buffer allocation work. The Laurent implementation
remains important for the Evo-X2 decode-sized ubatch gate and for historical
Windows/Vulkan behavior.

Planned r3 scope:

- persistent f32 pooled-summary rows for QSA layers
- per-buffer-type/device allocation following the newer upstream design
- incremental dirty-block pool / norm / RoPE / `set_rows` updates
- recurrent-layer exclusion matching the indexer cache layer filter
- sequence/state invalidation and watermark maintenance
- speculative dirty-table bounding equivalent to Laurent `c659bd6`
- safe dirty-table sizing for M-RoPE / repeated-position inputs
- pooled cache enabled only for a single-sequence memory configuration initially
- explicit fallback to the existing full-recompute path for unsupported cases
- `LLAMA_QSA_NO_POOLED_CACHE=1` as the same-binary A/B kill switch
- retain `LLAMA_QSA_POOLED_MAX_TOKENS` with default 32 and `0` meaning no limit

The r3 port should make the kill switch disable both pooled graph use and pooled
buffer allocation so same-binary memory comparisons are meaningful. This is an
intentional r3 behavior difference from reference implementations that allocate
the cache even when the graph path is disabled.

Explicitly outside COMMON-004:

- multi-sequence pooled-row windows / `--parallel > 1` support
- COMMON-005 decode gather
- Laurent `44041e78650c9f8aca2642842302dc8139907ded` reverse-scan optimization
- grouped-union / Vulkan sparse-FA changes
- Unsloth MTP compatibility
- MTP-QSA
- ROCmFPx work

Initial validation should keep MTP off and use the same binary for cache-on and
cache-off measurements.

Recommended validation order:

1. Vulkan and ROCm build / allocation / short-generation smoke
2. Vulkan 64k cache ON/OFF without PERF_LOGGER
3. Vulkan 128k cache ON/OFF
4. Vulkan 256k cache ON/OFF
5. ROCm 128k cache ON/OFF
6. fill Vulkan/ROCm 64k and ROCm 256k cells as useful
7. repeat close results in interleaved/ABBA order

Use the PLE16 model for the long-context runs because that layout is already
validated through 256k on both backends.

The primary metric is TG as a function of context depth. PP, memory use, first-
decode refill cost, and graph reuse must also be recorded. At 64k, recovering
most of the historical r2/r3 TG gap is a useful diagnostic target, but the
accept/reject decision is based primarily on depth scaling and correctness.

### 2. Evaluate selected post-b11247 upstream changes

Do not replace the whole upstream base for these tests. Prefer isolated
cherry-pick A/B work when the changes apply cleanly.

Highest-value candidates currently identified:

```text
94a0ae3e7298127b74d5b31370e83a1b4f143070
vulkan: MOE aware mat_mul_id tile selection (#29182)
```

This is relevant to Qwen3.8-Flash-Next because it is a large MoE model and the
change selects Vulkan `MUL_MAT_ID` tiles from per-expert row counts rather than
the total token count.

Keep this test separate from COMMON-004. If it shows a positive signal, repeat
with multiple ubatch sizes (at least 1024/2048/4096 where practical) because the
per-expert row shape changes with ubatch size. Test more than one target
quantization/model family before treating it as a general Evo-X2 default.

```text
5c200e0c8dfdbfa388f5d8f79ef7195dd4eb801e
vulkan: Tune GDN kernel, fix Intel performance (#29476)
```

The published motivation is Intel, so gfx1151 benefit must be measured rather
than assumed.

Lower-priority backend candidate:

```text
748d4225b9016b17ce4bcfa69fdc2c39f473a965
ggml-cuda: HIP: optimize packed byte subtraction (#29478)
```

Only keep an upstream candidate in r3 if it produces a useful measured result
or fixes a relevant correctness issue.

### 3. COMMON-005 - gather-based QSA decode

Add a common/model-layer candidate after COMMON-004 rather than treating all
remaining TG loss as a Vulkan-only problem.

The current qwen4exp decode path selects a top-k set but then converts that set
back into a mask over the full KV cache and calls attention over the full
context. Upstream PR `#28213` demonstrates an alternative single-token decode
path that gathers only the selected K/V rows and runs ordinary dense attention
on the compact set.

Why this is high priority after COMMON-004:

- it targets another O(context depth) decode cost
- it is model/common work rather than a Vulkan-only kernel change
- it can potentially help both Vulkan and ROCm
- it complements, rather than overlaps, pooled-summary caching

Do not implement COMMON-005 inside COMMON-004. First validate COMMON-004 and
profile whether Flash Attention / full-KV masking still scales materially with
context depth.

When evaluated, prefer a gate that avoids the gather path at short contexts
where the gather overhead exceeds the saved attention work. Preserve a runtime
A/B switch and validate retrieval/correctness before accepting it.

### 4. VULKAN-002 - QSA grouped-union / sparse-FA re-evaluation

The historical r2 grouped-union path remains a high-value PP candidate.

The 64k pre-implementation profile reconfirmed that grouped-union changes PP but
is essentially neutral for steady decode TG, so it remains complementary to the
COMMON decode work above.

Before re-porting the historical implementation:

1. finish COMMON-004
2. profile/evaluate COMMON-005
3. finish the selected small upstream Vulkan A/B tests
4. check whether the upstream Vulkan sparse-FA path (including the work around
   `#28105`) can be enabled or adapted for qwen4exp instead of reviving a larger
   historical downstream implementation
5. compare that option with the historical grouped-union implementation
6. port only the delta that is still needed
7. validate correctness before long-context benchmarking

128k and 256k remain the primary PP depths for deciding whether the port is
worth keeping.

### 5. Investigate remaining main-QSA decode scaling

After COMMON-004 and the COMMON-005 decision, profile the remaining depth-
dependent QSA costs before adding another large patch.

Current investigation order:

1. remaining attention / gather cost
2. block-score expansion and full-length mask construction/upload
3. top-k over the cell-level expanded scores
4. block score computation itself

This ordering supersedes the earlier assumption that top-k/select should be the
first remaining target. On the current gfx1151 Vulkan path the radix-style top-k
cost appears relatively small compared with the full-context work around it.

A later design may move selection closer to the block domain so the score does
not need to be expanded to every cell before top-k. That would require explicit
correctness checks for ties and tail blocks.

Halogen remains useful as architecture/performance evidence, not as code to port
blindly from a Linux-only closed engine.

### 6. COMMON-002 - Unsloth MTP compatibility

MTP remains important, but it is intentionally scheduled after the main-model
QSA costs above are better understood.

The first r3 MTP port should remain minimal:

- load the Unsloth MTP draft model
- confirm draft residual-stream inputs match the reference behavior
- confirm recurrent rollback is actually used
- measure acceptance statistics
- compare MTP on/off at short and long context
- keep MTP-QSA out of this patch

Before or during this work, evaluate relevant post-b11247 speculative-decoding
correctness fixes such as:

```text
d280808f5d82fcc3142b53f94ea5f594250cd765
common: stop accepting draft tokens at EOG (#29638)
```

Draft depth should be measured rather than assumed. Depth 2 is the first default
candidate; depth 3 remains a coding-oriented comparison point.

Revisit MTP-QSA only if ordinary MTP loses most or all of its benefit at long
context because the draft path is dominated by full-context attention.

### 7. COMMON-003 and VULKAN-001 - ROCmFPx

ROCmFPx work is deferred until the main Unsloth/QSA path above is understood.

For the AgentionAI ROCmFP4-FAST model:

1. identify exactly what current upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

### 8. MTP-QSA prototype

MTP-QSA remains outside the initial r3 patch stack.

The earlier Evo-X2 prototype established technical feasibility but did not show
a PP benefit at 128k and added substantial memory use. Revisit it only after:

- COMMON-004 is validated
- COMMON-005 is decided or the remaining full-context attention cost is known
- main-QSA long-context TG costs are reduced or characterized
- COMMON-002 is stable
- ordinary MTP on/off measurements are complete
- long-context MTP benefit has collapsed enough to justify draft-QSA complexity,
  or another new performance case justifies it

## Items already supplied by the upstream base

These were important investigation targets before r3 was rebased, but they are
not new downstream implementation tasks on b11247:

- qwen4exp recurrent-state rollback support from upstream #28123
- graph-reuse/shared-QSA-input work already present before b11247
- qwen4exp HC operations and Vulkan support from upstream #28901/#28988

They should still be verified when the relevant workload is exercised, but r3
should not re-port them as downstream features.

## Independent follow-up candidates

Keep these separate from COMMON-004 so attribution stays clean:

- Laurent `44041e78650c9f8aca2642842302dc8139907ded`: reverse-scan
  `get_prev_tokens` instead of walking the full cache; re-evaluate after
  COMMON-004 if a meaningful depth-dependent CPU/cache scan remains
- q8_0 K/V cache as an operational A/B while attention still reads the full KV
  cache; treat quality/memory effects separately from source patches

## Lower-priority candidates retained for later A/B

Keep these as candidates, not current implementation work:

- `GGML_VK_SHMEM_PAD` Windows driver-specific sweep
- `GGML_VK_DENSE_WAVE32`
- Strix Halo/RDNA3 matvec tuning where gfx1151 results conflict
- MMID row-list prepass for 512-expert MoE prefill
- later grouped-union scan/FA overlap and indexer-pipeline work
- per-row index Flash Attention prefill
- MoE router quantization
- ROCm/HIP micro-optimizations that are independent of QSA
- persistent prompt-cache and PLE residency/mmap experiments as operational
  topics rather than core r3 source patches

## Current upstream-refresh decision

Do not perform a full upstream replacement now.

Reasons:

- the b11247 r3 baseline is validated on both Vulkan and ROCm
- COMMON-001 and the tooling commits are already cleanly layered on that base
- the highest-priority pooled-key cache is still an unmerged upstream draft PR
- the most interesting post-b11247 Vulkan changes can be measured independently
- moving the base now would make COMMON-004 attribution less clear

Reconsider a new upstream base when one or more of these become true:

1. upstream #28699 is merged or superseded by an equivalent implementation
2. COMMON-004, COMMON-005 evaluation, and the selected small upstream A/B tests
   are complete enough to establish a new checkpoint
3. qwen4exp/MTP correctness fixes accumulate enough to outweigh base stability
4. porting COMMON-004 to b11247 proves materially harder than using a newer base

When the base is refreshed, create a separate branch and establish a new clean
Vulkan/ROCm baseline before reapplying downstream patches.
