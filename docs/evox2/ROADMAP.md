# Evo-X2 r3 optimization roadmap

Snapshot: 2026-09-30

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

## Current execution order

### 1. COMMON-004 - incremental pooled-key cache

This is the next implementation target.

The QSA indexer currently has an O(context depth) component because pooled block
summary keys are repeatedly reconstructed from the raw indexer cache during
decode. The reference pooled-key implementation keeps one persistent summary row
per complete position block and updates only newly completed blocks.

Primary references:

- LaurentZuijdwijk/llama.cpp commit
  `d8ec9e66329c1340e6fc74eee9d66ea5eebdb7c4`
  (`qwen4exp: incremental pooled-key cache for the QSA indexer`)
- upstream draft PR `ggml-org/llama.cpp#28699`
  (`qwen4exp: incremental pooled-key cache for the QSA indexer`)

The upstream PR is the preferred design reference because it includes later
state/rollback handling and per-buffer allocation changes. The Laurent commit
remains useful for Evo-X2/Vulkan measurements and for the decode-sized ubatch
gate.

Reference runtime controls include:

```text
LLAMA_QSA_NO_POOLED_CACHE=1
```

The Laurent implementation also has:

```text
LLAMA_QSA_POOLED_MAX_TOKENS
default: 32
0: no limit
```

Whether r3 retains the second control should be decided during the port rather
than assumed in advance.

Initial validation should keep MTP off and use the same binary for cache-on and
cache-off measurements.

Recommended first measurements:

1. Vulkan 128k cache ON/OFF
2. Vulkan 256k cache ON/OFF
3. ROCm 128k cache ON/OFF
4. fill 64k and ROCm 256k after a clear signal is established

Use the PLE16 model for the long-context runs because that is the validated r3
layout through 256k.

The main metric is TG as a function of context depth. PP should be recorded, but
a PP improvement is not the primary purpose of this patch.

Use interleaved/ABBA ordering for close results and retain thermal/resource logs.

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

### 3. VULKAN-002 - QSA grouped-union

The historical r2 grouped-union path remains a high-value PP candidate.

Earlier r2 measurements showed progressively larger PP gains at deeper context,
while TG was largely unchanged. That makes it complementary to COMMON-004:
pooled-key caching targets long-context decode/TG, while grouped-union targets
prefill/PP.

Before porting the historical implementation:

1. finish COMMON-004
2. finish the selected small upstream Vulkan A/B tests
3. compare the historical grouped-union implementation with the then-current
   qwen4exp/Vulkan graph
4. port only the delta that is still needed
5. validate correctness before long-context benchmarking

128k and 256k are the primary PP depths for deciding whether the port is worth
keeping.

### 4. Investigate remaining main-QSA decode scaling

If TG still falls strongly with depth after COMMON-004, profile the remaining
QSA path before adding another large patch.

Priority areas:

- block score computation
- top-k / block selection
- sparse gather
- Flash Attention
- scan/selection serialization at one-token decode shapes

Halogen 0.12 measurements and the later grouped-union/indexer work suggest that
block selection/scoring can become a major depth-dependent cost even after
pooled summaries are cached.

This stage is profiling/design work, not a blind port of a Linux-only engine.

### 5. COMMON-002 - Unsloth MTP compatibility

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

### 6. COMMON-003 and VULKAN-001 - ROCmFPx

ROCmFPx work is deferred until the main Unsloth/QSA path above is understood.

For the AgentionAI ROCmFP4-FAST model:

1. identify exactly what current upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

### 7. MTP-QSA prototype

MTP-QSA remains outside the initial r3 patch stack.

The earlier Evo-X2 prototype established technical feasibility but did not show
a PP benefit at 128k and added substantial memory use. Revisit it only after:

- COMMON-004 is validated
- main-QSA long-context TG costs are reduced or characterized
- COMMON-002 is stable
- ordinary MTP on/off measurements are complete
- a new performance case justifies the extra graph/cache complexity

## Items already supplied by the upstream base

These were important investigation targets before r3 was rebased, but they are
not new downstream implementation tasks on b11247:

- qwen4exp recurrent-state rollback support from upstream #28123
- graph-reuse/shared-QSA-input work already present before b11247
- qwen4exp HC operations and Vulkan support from upstream #28901/#28988

They should still be verified when the relevant workload is exercised, but r3
should not re-port them as downstream features.

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
2. COMMON-004 and the selected small upstream A/B tests are complete
3. qwen4exp/MTP correctness fixes accumulate enough to outweigh base stability
4. porting COMMON-004 to b11247 proves materially harder than using a newer base

When the base is refreshed, create a separate branch and establish a new clean
Vulkan/ROCm baseline before reapplying downstream patches.