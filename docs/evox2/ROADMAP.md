# Evo-X2 r3 optimization roadmap

Snapshot: 2026-10-02 (COMMON-005 validated on ROCm and Vulkan; COMMON-006 next)

This document records the current execution order for the r3 optimization work.
Patch IDs remain stable even when implementation priority changes.

## Current base and policy

The r3 source baseline remains:

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

The base remains fixed while the current optimization sequence is measured.
New upstream changes are evaluated as isolated A/B candidates when practical.
A full upstream refresh is reconsidered only at explicit checkpoints.

## Completed foundation

The current r3 branch now includes:

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

This diagnostic gate selected COMMON-005 as the next patch and retained the
score-expansion rewrite as COMMON-006.

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
- keep the runtime A/B control; do not infer a precise Vulkan crossover threshold
  from only three depths

Detailed final validation is recorded in
[COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md).

## Current execution order

### 1. COMMON-006 - block-domain QSA selection - next

COMMON-006 is now the active common/model optimization target.

Current qwen4exp selection flow:

```text
block score
  -> expand score to every KV cell through cell_blk
  -> cell-level top-k
```

Candidate direction:

```text
block-domain selection
  -> expand only selected blocks/cells
```

Why it is next:

- COMMON-005 removed full-context ROCm Flash Attention scaling
- the remaining repeated `k_get_rows_float` still scales ~2x from 128k to 256k
- its nominal per-token increase accounts for roughly 64% of the measured
  COMMON-005 ON 128k -> 256k ROCm latency increase

The main risk is semantic. The design must preserve:

- `indexer_top_k + compress_ratio - 1`
- tail-block behavior
- causal/visibility masking
- tie and ordering behavior

Keep COMMON-006 as a separate correctness-first A/B against the fixed
COMMON-005 baseline.

### 2. Evaluate selected post-b11247 upstream changes

Do not replace the whole upstream base for these tests. Prefer isolated A/B work.

Highest-value Vulkan candidate currently retained:

```text
94a0ae3e7298127b74d5b31370e83a1b4f143070
vulkan: MOE aware mat_mul_id tile selection (#29182)
```

Also retained for targeted evaluation:

```text
5c200e0c8dfdbfa388f5d8f79ef7195dd4eb801e
vulkan: Tune GDN kernel, fix Intel performance (#29476)

748d4225b9016b17ce4bcfa69fdc2c39f473a965
ggml-cuda: HIP: optimize packed byte subtraction (#29478)
```

Only keep a candidate if it produces a useful measured result or fixes a
relevant correctness issue.

### 3. VULKAN-002 - grouped-union / sparse-FA PP re-evaluation

Historical r2 grouped-union remains a high-value PP candidate. The previous
profile reconfirmed that it changes PP substantially but is essentially neutral
for steady decode TG.

Before re-porting:

1. keep COMMON-004 and COMMON-005 fixed
2. evaluate COMMON-006
3. finish selected small upstream Vulkan A/B tests
4. check whether newer upstream Vulkan sparse-FA work can be adapted instead of
   reviving a larger historical downstream implementation
5. compare against the historical grouped-union implementation
6. port only the required delta
7. validate correctness before benchmarking

128k and 256k remain the primary PP depths.

### 4. COMMON-002 - Unsloth MTP compatibility

MTP remains important, but it stays after the current main-model QSA pass.

The first r3 MTP port should remain minimal:

- load the Unsloth MTP draft model
- confirm draft residual-stream inputs match reference behavior
- confirm recurrent rollback is used
- measure acceptance statistics
- compare MTP on/off at short and long context
- keep MTP-QSA out of the compatibility patch

Relevant post-b11247 speculative-decoding correctness fixes should be evaluated
independently when this work resumes.

Revisit MTP-QSA only if ordinary MTP loses enough long-context benefit to justify
its additional graph/cache complexity.

### 5. COMMON-003 and VULKAN-001 - ROCmFPx

For the AgentionAI ROCmFP4-FAST model:

1. identify what current upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

## Independent follow-up candidates

Keep these separate from COMMON-006 so attribution stays clean:

- Laurent reverse-scan `get_prev_tokens` optimization if a meaningful
  depth-dependent CPU/cache scan remains
- q8_0 K/V cache as an operational A/B
- `GGML_VK_SHMEM_PAD` Windows driver-specific sweep
- `GGML_VK_DENSE_WAVE32`
- Strix Halo/RDNA matvec tuning
- MMID row-list prepass for large-expert MoE prefill
- later grouped-union scan/FA overlap and indexer-pipeline work
- per-row index Flash Attention prefill
- persistent prompt-cache and PLE residency/mmap experiments

## Current upstream-refresh decision

Do not perform a full upstream replacement yet.

Reasons:

- the b11247 r3 baseline is validated on Vulkan and ROCm
- COMMON-001, COMMON-004, and COMMON-005 are now measured against that fixed base
- selected post-b11247 changes can still be tested independently
- moving the base now would make COMMON-006 attribution less clear

Reconsider a new upstream base when one or more of these become true:

1. upstream equivalents of COMMON-004/005 are merged or supersede the downstream patches
2. COMMON-006 and selected small upstream A/B tests establish a new checkpoint
3. qwen4exp/MTP correctness fixes accumulate enough to outweigh base stability
4. a newer upstream base materially simplifies the remaining QSA work

When refreshing the base, create a separate branch and establish new clean
Vulkan/ROCm baselines before reapplying downstream patches.
