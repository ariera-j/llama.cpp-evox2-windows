# Evo-X2 optimization roadmap

Snapshot: 2026-10-03 (r3 frozen; r4 COMMON-001 validated through 256k; cached-pool follow-up / VULKAN-002 next)

This document records the current execution order for the Evo-X2 optimization
work. Patch IDs remain stable even when implementation priority changes.

## Current checkpoint and policy

The validated r3 source baseline remains:

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

The r3 branch is frozen at:

```text
r3/upstream-first
0a93fcbb8e5bcf51b331275c4f4b142d822168d6
```

The r4 branch was created directly from the pinned upstream commit:

```text
r4/upstream-refresh-20261002
bed0a856606ee4a24a164066f73d2379447033f5
```

Fork housekeeping is committed at `39f35efdfa135b36d0181a393178cc53719e5363`.
The clean refreshed-upstream baseline remains preserved as the comparison point.
COMMON-001 has now been adapted to r4 and committed as:

```text
a60a57879a9ffb4d51acd45d4de7e80d721548f9
qwen4exp: restore split PLE n-gram tensor support
```

The joined Original model and split PLE16 model both load after the port.
Vulkan/ROCm AllocationOnly and short inference pass, the matched 64k
Original/PLE16 gate passes, and PLE16 completes 128k/256k on both backends.
See [R4-COMMON001-VALIDATION-2026-10-03.md](R4-COMMON001-VALIDATION-2026-10-03.md).
Do not move the upstream base silently or rewrite r3 onto it. Re-apply only
downstream deltas justified by measurements.

### Active order after COMMON-001 validation (2026-10-03)

This order supersedes the older refresh sequence below. The clean six-run
baseline, scoped 64k PP regression diagnosis, GET_ROWS tensor breakdown, and
COMMON-001 compatibility port are complete.

1. **Completed:** capture tensor-level Vulkan GET_ROWS with Original 64k,
   before COMMON-001, fixing MoE legacy selection to 1. Windows run is OK:
   GET_ROWS 2.487 ms/token, including cached pool gather 1.662 ms (66.82%).
   Preserve b11377 / acf7fea2b and its logs as the pre-port reference.
2. **Completed:** COMMON-001 adapted port. Split PLE16 compatibility is restored
   while preserving the joined Original path. 64k matched-layout comparison and
   PLE16 128k/256k validation pass on Vulkan and ROCm. The implementation commit
   is `a60a57879a9ffb4d51acd45d4de7e80d721548f9`.
3. **Decision gate:** inspect whether the cached-pool gather cost can be reduced
   with a small, well-scoped change. Do not restore COMMON-004 wholesale. If the
   fix requires a broad cache/layout rewrite, keep the measured reference and
   move on rather than obscuring attribution.
   Source inspection is complete at `43feb226...`: direct view replacement is
   constrained by variable cell ids, padding, graph reshapes, and backend copies.
   A scoped Vulkan GET_ROWS `128 x 4` workgroup candidate is now implemented behind
   `GGML_VK_GET_ROWS_128X4=1`, default OFF. CPU-side source-derived checks pass;
   Windows shader/backend correctness and 64k profile/normal A/B are pending.
   Test only this candidate before deciding whether to advance to VULKAN-002;
   do not broaden it into a cache/layout or gather/matmul-fusion rewrite.
   See [R4-GET-ROWS-128X4-AB-2026-10-03.md](R4-GET-ROWS-128X4-AB-2026-10-03.md).
4. **VULKAN-002:** adapt the missing grouped-union PP path if the small TG gate
   above does not justify an earlier patch. The current per-row sparse FA does
   not cover the observed 1024/349-query PP. Use 128k/256k as the primary value
   test because r4 TG is already near the historical r2 range while long-context
   PP still trails the grouped-union reference materially.
5. **COMMON-005:** profile ROCm single-token decode and adapt compact selected K/V
   gathering if confirmed. It remains complementary to VULKAN-002 and can move
   earlier if ROCm decode becomes the immediate priority.
6. Resume MTP and other candidates after these decisions and validations.

COMMON-001 is treated as a compatibility/layout patch, not a throughput
optimization. ROCm clean Original and COMMON-001 PLE16 are effectively neutral
across 64k/128k/256k. Vulkan COMMON-001 runs use legacy MoE tile selection, so
the clean-to-COMMON-001 PP gain is not attributed to PLE16; the 64k delta closely
matches the previously measured same-binary MoE A/B result.

Instructions: [R4-GET-ROWS-PROFILE-2026-10-03.md](R4-GET-ROWS-PROFILE-2026-10-03.md).
COMMON-001 result: [R4-COMMON001-VALIDATION-2026-10-03.md](R4-COMMON001-VALIDATION-2026-10-03.md).
Source evidence and historical decisions:
[R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md).

### First r4 Vulkan profile (64k)

The next PP diagnostic is implemented as an opt-in MoE tile-selection switch,
with one binary for current/legacy A/B and separate profile/normal matrix jobs.
Default selection remains upstream. Windows A/B profiles now show PP MoE GPU
time 63.933 -> 47.807 s (legacy), with FA unchanged and steady TG essentially
unchanged. Both modes pass 939/939 MUL_MAT_ID tests. Normal ABBA now confirms
PP 248.475 -> 268.985 tok/s (+8.25%) with all four runs OK. This completes the
64k PP diagnosis for the tested model/device/shapes. TG averages -2.50% with
short, differing generations; do not claim no TG impact. Keep legacy opt-in.
The subsequent tensor-level TG GET_ROWS profile and COMMON-001 validation are
now complete; use the active order above for the next decision.
See [R4-MOE-TILE-AB-2026-10-03.md](R4-MOE-TILE-AB-2026-10-03.md).

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

### r2 grouped-union remains the long-context PP reference

r3 intentionally does **not** include the r2 QSA grouped-union optimization.
This is by design: r3 is an attribution-focused upstream-first checkpoint, not
a claim that every r2 performance optimization has already been superseded.

Keep the validated r2 grouped-union results as the long-context Vulkan PP
reference when evaluating the refreshed upstream:

| Context | r2 QSA union PP |
|---|---:|
| 64k | ~275 tok/s |
| 128k | 222.77 tok/s |
| 256k | 177.01 tok/s |

The r4 COMMON-001 PLE16 validation with legacy MoE selection measures 268.79,
178.99, and 132.99 tok/s at 64k/128k/256k respectively. The 64k gap is small,
but the long-context gap remains material, which keeps VULKAN-002 relevant.
Do not add grouped-union to r3 merely to make the checkpoint faster; preserving
the clean attribution of COMMON-001/004/005 is more valuable at this stage.

The 2026-10-02 observation `a868c3e3c56657f7e8a6231190dbbe90e7dd86c0`
was a candidate only. The base was pinned on 2026-10-03 JST at `bed0a856...`
after fetching upstream and verifying the raw source identity. #29824 is
included; #29825 was open and excluded at pin time.

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

The numbered refresh sequence below records the original refresh plan. The
**Active order after COMMON-001 validation** above supersedes it for current
execution.

### 1. Freeze r3 at this documentation checkpoint (complete)

The frozen checkpoint is `0a93fcbb8e5bcf51b331275c4f4b142d822168d6`:

- keep `r3/upstream-first` as the validated b11247 reference
- do not rebase it onto current upstream
- use the committed COMMON-004/005 measurements and validation documents as the
  comparison baseline for all refresh work

### 2. Create a separate upstream-refresh branch (complete)

Created branch:

```text
r4/upstream-refresh-20261002
```

Completed at branch creation:

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

- #29824: qwen4exp mask-construction optimization; merged and included in the
  pinned r4 base (`4e2713c1620f1fadb2c3afcc0a8f01500d68ac17`)
- #29825: qwen4exp indexer score-memory reduction; open and not included at
  pin time (2026-10-03 JST)

The base is now fixed. Later upstream merges are separate A/B candidates;
recheck their status when evaluating them rather than silently moving the base.

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

The refresh branch now has the clean baseline and COMMON-001 validation recorded.
Before re-porting the remaining historical optimization stack, keep the following
checkpoint items explicit:

1. exact upstream base SHA
2. successful Vulkan and ROCm builds
3. relevant backend tests / allocation-only smoke
4. joined Original and split PLE16 load results
5. 64k/128k/256k PP/TG baseline where practical
6. direct comparison against the r3 COMMON-004/005 checkpoint
7. written decisions for COMMON-004, COMMON-005, COMMON-006, and VULKAN-002

That checkpoint becomes the basis for later MTP, grouped-union, and ROCmFPx work.
