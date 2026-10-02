# Evo-X2 optimization roadmap

Snapshot: 2026-10-02 (r3 COMMON-005 checkpoint complete; upstream refresh next)

This document records the current execution order for the Evo-X2 optimization
work. Patch IDs remain stable even when implementation priority changes.

## Current checkpoint and policy

The validated r3 source baseline remains:

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

The r3 branch is now treated as a frozen comparison checkpoint after the
COMMON-001/004/005 work and its validation documents are committed.

The next phase is a separate upstream-refresh branch. Do not rewrite r3 onto the
new base. Establish a clean refreshed baseline first, then re-apply only the
remaining downstream deltas that measurements justify.

Latest upstream master observed during the 2026-10-02 review:

```text
a868c3e3c56657f7e8a6231190dbbe90e7dd86c0
```

This SHA is an observation point, not yet the permanent refresh base. Pin the
exact upstream SHA when the refresh branch is created and record it before
benchmarking.

## Completed r3 foundation

The r3 checkpoint includes:

- clean upstream-first b11247 Vulkan and ROCm baselines
- COMMON-001 PLE16 loader support, validated through 256k on Vulkan and ROCm
- COMMON-004 incremental pooled-key cache, validated through 256k on Vulkan and ROCm
- COMMON-005 gather-based QSA decode, validated through 256k on Vulkan and ROCm
- benchmark wrappers for real-input `llama-cli` and synthetic `llama-bench`
- benchmark matrix runner with environment-variable A/B support
- Vulkan and ROCm build wrappers with build manifests
- shared dependency caching for fresh build directories

## Completed diagnostic gate: r2 versus r3 decode profile

The 64k Vulkan profile that preceded COMMON-004 isolated repeated QSA pooled-
summary reconstruction as the dominant r3 decode regression.

Steady single-token decode GPU graph time:

| Build | QSA union | Steady GPU graph |
|---|---|---:|
| r2 | OFF | 44.18 ms/token |
| r2 | ON | 44.31 ms/token |
| r3 + COMMON-001 | n/a | 59.13 ms/token |

The extra r3 cost was concentrated in full pooled-summary `CONT`, RMS norm, and
RoPE work. This motivated COMMON-004.

## Completed: COMMON-004 pooled-key cache

Implementation commit:

```text
6559dd272fd0d5f553823e8851c78b9edc2a5016
qwen4exp: cache pooled QSA keys across decode steps
```

Key TG results with the pooled cache enabled:

| Backend | 64k | 128k | 256k |
|---|---:|---:|---:|
| Vulkan | 25.95 | 24.00 | 21.03 |
| ROCm | 20.62 | 16.44 | 11.60 |

COMMON-004 removed a large long-context decode cost on both backends. Vulkan
retained relatively little TG depth loss; ROCm still showed substantial
64k -> 256k degradation.

## Completed diagnostic gate: ROCm residual scaling after COMMON-004

Radeon GPU Profiler at 128k and 256k showed two context-linear paths:

| Kernel | 128k | 256k | Change |
|---|---:|---:|---:|
| `flash_attn_tile<256,256,1,4,false>` | ~1.452 ms | ~2.939 ms | ~2.02x |
| `k_get_rows_float` | ~0.451 ms | ~0.907 ms | ~2.01x |
| `mul_mat_vec_q<type14>` | ~2.835 ms | ~2.836 ms | flat |

Source tracing matched them to:

1. full-context K/V Flash Attention on HIP, despite a sparse `n_kv_max` hint
2. block-score-to-full-cell expansion before qwen4exp top-k

This diagnostic gate selected COMMON-005 as the next r3 patch and retained the
score-expansion rewrite as the original COMMON-006 idea.

## Completed: COMMON-005 gather-based QSA decode

Implementation commit:

```text
d03c91b6342b099457de3508c5d67533a9a5f0ee
qwen4exp: gather selected QSA KV rows for decode
```

COMMON-005 gathers selected K/V and matching KQ-mask rows during eligible
single-token decode and runs ordinary Flash Attention on compact tensors. The
existing path remains available through:

```text
QWEN4EXP_QSA_GATHER=0
QWEN4EXP_QSA_GATHER=1
```

### ROCm result

| Context | Gather OFF TG | Gather ON TG | Gain |
|---|---:|---:|---:|
| 64k | 20.55 | 22.60 | +10.0% |
| 128k | 16.425 | 20.41 | +24.3% |
| 256k | 11.68 | 17.37 | +48.7% |

128k -> 256k added decode latency falls from about +24.73 to +8.57 ms/token.

RGP directly confirms that compact Flash Attention no longer scales with full
context depth:

```text
128k ~= 41.93 us
256k ~= 42.00 us
```

The remaining repeated `k_get_rows_float` still scales from about 447.92 us at
128k to 907.13 us at 256k.

### Vulkan result

Vulkan already has backend sparse Flash Attention, so the model-side gather path
is a much closer tradeoff:

| Context | Gather OFF TG | Gather ON TG | Change |
|---|---:|---:|---:|
| 64k | 25.95 | 25.42 | -2.0% |
| 128k | 24.61 | 24.12 | -2.0% |
| 256k | 21.135 | 21.69 | +2.6% |

64k is one OFF/ON pair. 128k and 256k are ABBA averages. PP is effectively
unchanged.

Interpretation:

- ROCm: Gather ON is strongly beneficial and grows more valuable with context
- Vulkan: existing sparse-FA is slightly faster at 64k/128k, Gather ON slightly
  faster at 256k
- keep the r3 runtime A/B control as part of the reference checkpoint

Detailed final validation is recorded in
[COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md).

## Why the plan changes here

The 2026-10-02 upstream review crossed the refresh threshold that the previous
roadmap had intentionally deferred.

### COMMON-006 direction is now upstream

Upstream PR #29751 (`llama: fix qwen4exp`, merge commit
`66e0c17ee1741fef493312e17fe60a5d2cf5f7d5`) reworked the qwen4exp QSA/k-pool
path. Current upstream qwen4exp now selects top pools/blocks before expanding
them to cell indices:

```text
pool/block score
  -> pool-domain top-k
  -> expand selected pools to cell indices
  -> append retained tail indices
```

This is materially the same direction as the planned COMMON-006. Building a
second b11247 implementation immediately before refreshing upstream would add
maintenance and validation work without a clean long-term target.

Therefore COMMON-006 changes from `next implementation` to `upstream evaluation`.

### MTP support also moved upstream

Upstream PR #29761 (`Qwen4Exp: add MTP`) merged on 2026-10-01 and adds qwen4exp
MTP conversion/tensor support plus the draft-model load-path fix.

COMMON-002 should therefore start by testing the existing Unsloth MTP sidecar on
the refreshed upstream. Only a remaining compatibility delta should be ported.

### Relevant post-b11247 Vulkan work is already merged

The refresh also brings several changes that were previously independent
candidate ports, including:

- #28501: 512-expert Vulkan row-id hoisting, measured as a Qwen3.8 prefill gain
- #29182: MoE-aware Vulkan `mul_mat_id` tile selection
- #29520: qwen4exp HC post-gate Vulkan fusion
- #29599: PLE row prefetch; Windows behavior still needs real Evo-X2 validation

This makes a clean refreshed baseline more informative than cherry-picking the
same changes individually onto b11247.

### COMMON-005 may still matter on ROCm

Do not assume the refresh supersedes COMMON-005.

Current upstream CUDA sparse Flash Attention code explicitly excludes HIP, so
ROCm can still retain a full-context attention cost even with the newer model
QSA/k-pool selection path. The r3 COMMON-005 result remains the reference for
this question.

## Current execution order

### 1. Freeze r3 at this documentation checkpoint

After this roadmap/registry update is committed:

- keep `r3/upstream-first` as the validated b11247 reference
- do not rebase it onto current upstream
- use the committed COMMON-004/005 measurements and validation documents as the
  comparison baseline for all refresh work

### 2. Create a separate upstream-refresh branch

Recommended branch name:

```text
r4/upstream-refresh-20261002
```

At branch creation:

1. fetch current `ggml-org/llama.cpp` master
2. pin the exact upstream commit used for the branch
3. record that SHA before adding downstream patches
4. keep r3 available as the comparison branch

Do not carry COMMON-001/004/005 into the initial refreshed source tree.

### 3. Establish clean refreshed-upstream load/build baselines

Build Vulkan and ROCm from the pinned refresh source before optimization work.

First model-loading checks:

1. try the original joined Unsloth Qwen3.8-Flash-Next model
2. verify allocation/load on Vulkan and ROCm
3. test whether the upstream PLE changes remove the practical reason COMMON-001
   was needed
4. only re-port PLE16 support if the joined path remains problematic or the
   split model is still required operationally

Also run the relevant backend tests and allocation-only smoke before long runs.

### 4. Measure refreshed QSA baseline at 64k / 128k / 256k

Use MTP off first so the main-model QSA path is isolated.

Primary comparison:

```text
new upstream, no downstream QSA patches
vs
r3 COMMON-004 + COMMON-005 validated checkpoint
```

Record PP and TG for Vulkan and ROCm at 64k, 128k, and 256k using the existing
matrix/wrapper tooling.

Questions to answer:

- does upstream pool-domain selection remove the old COMMON-006
  `k_get_rows_float` depth slope?
- how does the new upstream pooled-key/k-pool path compare with COMMON-004?
- is ROCm TG still materially behind the r3 COMMON-005 result at 128k/256k?
- does Vulkan PP improve enough that historical grouped-union work becomes less
  valuable?

### 5. Re-evaluate COMMON-005 on ROCm only if the refreshed baseline needs it

If ROCm long-context TG still scales badly:

1. profile 128k and 256k on the clean refreshed build
2. confirm whether Flash Attention still sees the full KV depth
3. if so, port the minimum COMMON-005 compact selected-K/V path onto the new QSA
   structure
4. A/B against the clean refreshed build

Do not port COMMON-005 first and diagnose later.

For Vulkan, keep COMMON-005 out initially. Its r3 benefit was only a few percent
and changed sign with context depth.

### 6. Treat COMMON-006 as an upstream-validation gate

Do not write a downstream COMMON-006 unless measurement shows a remaining gap.

Validation points:

- pool-domain top-k is actually exercised by the real model
- selected pool expansion and tail indices preserve expected output behavior
- the old full-cell score expansion is gone or materially reduced
- 128k -> 256k ROCm residual latency slope is re-accounted after the refresh

If a new bottleneck remains, define a new downstream delta from the refreshed
source rather than reviving the b11247 design verbatim.

### 7. Re-evaluate COMMON-002 MTP on refreshed upstream

Start without old r2/r3 compatibility patches.

- load the existing Unsloth MTP draft model
- confirm draft residual-stream inputs and recurrent rollback behavior
- measure acceptance statistics
- compare MTP on/off at short and long context
- measure long-context PP overhead
- add only the compatibility change that is still demonstrably required

Keep MTP-QSA outside this compatibility step.

### 8. Reconsider VULKAN-002 grouped-union only after refreshed PP data

Historical grouped-union remains a useful reference, but the decision gate moves
after the new upstream baseline because several Vulkan/QSA changes have already
landed.

Use 128k and 256k as the primary PP decision points. If refreshed upstream has
already recovered most of the historical PP gap, do not re-port the larger r2
implementation.

### 9. COMMON-003 / VULKAN-001 ROCmFPx

For the AgentionAI ROCmFP4-FAST model:

1. identify what the pinned refreshed upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

## Upstream items to watch during the refresh

Do not mix unmerged work into the first clean baseline, but keep these visible:

- #29824: qwen4exp mask-construction optimization
- #29825: qwen4exp indexer score-memory reduction

If either merges before the refresh SHA is pinned, document whether it is in the
chosen base. If it merges after the base is pinned, evaluate it separately rather
than silently moving the base.

## Independent follow-up candidates

After the refreshed main path is understood:

- Laurent reverse-scan `get_prev_tokens` optimization if a meaningful
  depth-dependent CPU/cache scan remains
- q8_0 K/V cache as an operational A/B
- `GGML_VK_SHMEM_PAD` Windows driver-specific sweep
- `GGML_VK_DENSE_WAVE32`
- Strix Halo/RDNA matvec tuning
- MMID row-list prepass if refreshed MoE prefill still warrants it
- grouped-union scan/FA overlap and indexer-pipeline work only if profiling points there
- per-row index Flash Attention prefill
- persistent prompt-cache and PLE residency/mmap experiments

## Refresh acceptance checkpoint

Do not start re-porting the remaining historical patch stack until the refresh
branch has all of the following recorded:

1. exact upstream base SHA
2. successful Vulkan and ROCm builds
3. relevant backend tests / allocation-only smoke
4. model load result for the joined Unsloth model
5. 64k/128k/256k PP/TG baseline where practical
6. direct comparison against the r3 COMMON-004/005 checkpoint
7. a written decision for COMMON-001, COMMON-004, COMMON-005, and COMMON-006

That checkpoint becomes the new basis for later MTP, grouped-union, and ROCmFPx
work.
