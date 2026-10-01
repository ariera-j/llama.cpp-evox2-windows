# Evo-X2 r3 optimization roadmap

Snapshot: 2026-10-01 (post-COMMON-004 validation)

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
- COMMON-004 incremental pooled-key cache, validated through 256k on Vulkan and ROCm
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

This diagnostic result motivated COMMON-004 and was confirmed by the later
long-context cache ON/OFF validation.

## Current execution order

### 1. COMMON-004 - incremental pooled-key cache - completed

COMMON-004 is implemented and validated on both Vulkan and ROCm.

Implementation commit:

```text
6559dd272fd0d5f553823e8851c78b9edc2a5016
qwen4exp: cache pooled QSA keys across decode steps
```

The patch keeps persistent pooled QSA indexer summary keys and updates only
newly completed or invalidated blocks during decode.

Same-binary cache ON/OFF validation was completed through 256k with the PLE16
Qwen3.8-Flash-Next model and MTP disabled.

Key results:

| Backend | Context | TG OFF | TG ON |
|---|---:|---:|---:|
| Vulkan | 64k | 17.13 | 25.95 |
| Vulkan | 128k | 11.91 | 24.00 |
| Vulkan | 256k | 7.27 | 21.03 |
| ROCm | 64k | 14.82 | 20.62 |
| ROCm | 128k | 9.89 | 16.44 |
| ROCm | 256k | 5.52 | 11.60 |

COMMON-004 clearly removes a major long-context decode cost on both backends.

The remaining behavior is backend-dependent:

- Vulkan retains relatively little TG depth loss after the cache is enabled.
- ROCm still shows substantial TG degradation from 64k to 256k.
- Vulkan shows a small repeatable PP regression with the cache enabled.
- ROCm did not reproduce that PP trend.
- the Vulkan compute-buffer expectation warning was not observed on ROCm.

Detailed validation and follow-up notes are recorded in [PATCHES.md](PATCHES.md).

### 2. Profile remaining ROCm long-context decode scaling

Before selecting the next optimization patch, collect ROCm profiling data with
COMMON-004 enabled.

The purpose of this step is diagnostic rather than another implementation.

ROCm TG with pooled caching enabled still decreases substantially with context
depth:

```text
64k   20.62 tok/s
128k  16.44 tok/s
256k  11.60 tok/s
```

Do not assume that COMMON-005, a backend-specific change, or another QSA
optimization is the next patch until the residual ROCm cost is measured.

Use the profile to determine which part of the remaining decode graph scales
with context depth, then choose the next implementation target from the
evidence.

### 3. Evaluate selected post-b11247 upstream changes

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

### 4. COMMON-005 - gather-based QSA decode

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

Do not implement COMMON-005 until the ROCm residual profile above identifies
the remaining depth-dependent cost strongly enough to justify this path.

When evaluated, prefer a gate that avoids the gather path at short contexts
where the gather overhead exceeds the saved attention work. Preserve a runtime
A/B switch and validate retrieval/correctness before accepting it.

### 5. VULKAN-002 - QSA grouped-union / sparse-FA re-evaluation

The historical r2 grouped-union path remains a high-value PP candidate.

The 64k pre-implementation profile reconfirmed that grouped-union changes PP but
is essentially neutral for steady decode TG, so it remains complementary to the
COMMON decode work above.

Before re-porting the historical implementation:

1. keep the validated COMMON-004 baseline fixed
2. collect and interpret the ROCm residual profile
3. profile/evaluate COMMON-005 if the residual evidence supports it
4. finish the selected small upstream Vulkan A/B tests
5. check whether the upstream Vulkan sparse-FA path (including the work around
   `#28105`) can be enabled or adapted for qwen4exp instead of reviving a larger
   historical downstream implementation
6. compare that option with the historical grouped-union implementation
7. port only the delta that is still needed
8. validate correctness before long-context benchmarking

128k and 256k remain the primary PP depths for deciding whether the port is
worth keeping.

### 6. Investigate remaining main-QSA decode scaling

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

### 7. COMMON-002 - Unsloth MTP compatibility

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

### 8. COMMON-003 and VULKAN-001 - ROCmFPx

ROCmFPx work is deferred until the main Unsloth/QSA path above is understood.

For the AgentionAI ROCmFP4-FAST model:

1. identify exactly what current upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

### 9. MTP-QSA prototype

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
- COMMON-001, COMMON-004, and the tooling commits are cleanly layered on that base
- COMMON-004 is validated downstream while the equivalent upstream work remains
  unmerged
- the most interesting post-b11247 Vulkan changes can still be measured independently
- moving the base now would make the next residual-profile and optimization
  attribution less clear

Reconsider a new upstream base when one or more of these become true:

1. upstream #28699 is merged or superseded by an equivalent implementation
2. COMMON-005 evaluation and the selected small upstream A/B tests are complete
   enough to establish a new checkpoint
3. qwen4exp/MTP correctness fixes accumulate enough to outweigh base stability
4. a newer upstream base materially simplifies the remaining QSA work or
   supersedes downstream patches without losing validated behavior

When the base is refreshed, create a separate branch and establish a new clean
Vulkan/ROCm baseline before reapplying downstream patches.
