# COMMON-005 validation - 2026-10-02

## Purpose

Record the completed Vulkan and ROCm validation of COMMON-005, the qwen4exp
gather-based QSA decode path derived from the design around upstream PR #28213.

COMMON-005 gathers the QSA-selected K/V rows and matching KQ-mask rows during
long-context single-token decode, then runs ordinary Flash Attention on the
compact tensors. The existing full-K/V path remains available through the
runtime A/B switch.

Implementation commit:

```text
d03c91b6342b099457de3508c5d67533a9a5f0ee
qwen4exp: gather selected QSA KV rows for decode
```

Runtime control:

```text
QWEN4EXP_QSA_GATHER=0   # COMMON-005 OFF
QWEN4EXP_QSA_GATHER=1   # COMMON-005 ON
```

COMMON-004 remained enabled during COMMON-005 A/B validation.

## Workload

- GMKtec Evo-X2 / Radeon 8060S / 96 GB UMA
- Qwen3.8-Flash-Next PLE16-converted Unsloth UD-IQ3_XXS
- MTP disabled
- f16 K/V
- batch 2048, ubatch 1024
- 4 CPU threads / 4 batch threads
- full supported GPU offload
- Flash Attention enabled/auto
- generation budget 1024
- temperature 0.2, top_p 0.8
- prompt cache disabled
- context checkpoints disabled

64k used one OFF/ON pair. 128k and 256k used ABBA order:

```text
A1 gather ON
B1 gather OFF
B2 gather OFF
A2 gather ON
```

## ROCm validation

Build/smoke gate:

- ROCm/HIP target gfx1151
- AMD Clang 23.0.0
- FLASH_ATTN_EXT: 3982/3982 tests passed
- allocation-only smoke passed
- all 10 real-input benchmark runs passed

### ROCm benchmark results

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG gain |
|---|---:|---:|---:|---:|---:|
| 64k | 359.37 | 357.27 | 20.55 | 22.60 | +10.0% |
| 128k | 262.44 | 262.50 | 16.425 | 20.41 | +24.3% |
| 256k | 167.58 | 167.99 | 11.68 | 17.37 | +48.7% |

128k and 256k are ABBA averages. PP is effectively unchanged.

Decode latency:

| Context | Gather OFF | Gather ON |
|---|---:|---:|
| 64k | 48.66 ms/token | 44.25 ms/token |
| 128k | 60.88 ms/token | 49.00 ms/token |
| 256k | 85.62 ms/token | 57.57 ms/token |

From 128k to 256k, added decode latency falls from about +24.73 ms/token OFF
to +8.57 ms/token ON. COMMON-005 therefore removes about 65% of the residual
ROCm depth-dependent latency over this interval.

### ROCm RGP confirmation

Before COMMON-005, the repeated full-context Flash Attention tile scaled almost
exactly with context length:

```text
128k: flash_attn_tile<256,256,1,4,false> ~= 1.452 ms
256k: flash_attn_tile<256,256,1,4,false> ~= 2.939 ms
```

After COMMON-005, the compact-K/V path selects:

```text
flash_attn_tile<256,256,2,1,false>
```

Representative tile duration is effectively independent of context:

```text
128k: ~= 41.93 us
256k: ~= 42.00 us
```

The old O(n_kv) Flash Attention scaling is therefore removed in the profiled
ROCm path.

The remaining repeated `k_get_rows_float` path still scales with full context:

```text
128k: ~= 447.92 us
256k: ~= 907.13 us
ratio: ~= 2.03x
```

This matches the block-score-to-full-cell expansion that COMMON-005 deliberately
leaves unchanged in `build_qsa_top_k()`.

Using 12 full-attention groups per token, the increase in this repeated get-rows
path contributes nominally about +5.51 ms/token, roughly 64% of the measured
COMMON-005 ON 128k -> 256k latency increase.

Detailed pre/post ROCm profiling is retained in:

- `ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md`
- `COMMON005-ROCM-VALIDATION-2026-10-02.md`

## Vulkan validation

Vulkan requires a separate interpretation because the fallback path already has
backend sparse Flash Attention support.

Build/smoke gate:

- Vulkan0: AMD Radeon 8060S
- Clang 20.1.8 build
- FLASH_ATTN_EXT: 5297/5297 tests passed
- allocation-only smoke passed
- all 64k/128k/256k real-input runs passed

The same known Vulkan compute-buffer expectation warning was observed on both
Gather OFF and Gather ON runs. It was not introduced by COMMON-005 and did not
prevent successful completion.

### Vulkan benchmark results

Raw ABBA TG values:

```text
128k
ON  23.97
OFF 24.68
OFF 24.54
ON  24.27

256k
ON  21.74
OFF 21.12
OFF 21.15
ON  21.64
```

Aggregated results:

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG change |
|---|---:|---:|---:|---:|---:|
| 64k | 261.98 | 262.44 | 25.95 | 25.42 | -2.0% |
| 128k | 156.275 | 156.16 | 24.61 | 24.12 | -2.0% |
| 256k | 98.065 | 97.975 | 21.135 | 21.69 | +2.6% |

64k is one OFF/ON pair. 128k and 256k are ABBA averages.

PP is effectively unchanged at all three depths.

The Vulkan result is backend-dependent rather than a universal gain:

- 64k: existing Vulkan sparse-FA fallback is about 2% faster
- 128k: existing Vulkan sparse-FA fallback is about 2% faster
- 256k: model-side gather is about 2.6% faster

Both runs within each ABBA side follow the same direction at 128k and 256k, so
the crossover is probably real, but the effect size is small. Do not infer a
precise automatic crossover threshold from only these three depths.

## Final decision

COMMON-005 status:

```text
validated
```

Reasons:

- builds and backend tests pass on both ROCm and Vulkan
- allocation-only model smoke passes on both backends
- all long-context A/B runs complete successfully
- disabled/fallback paths reproduce the expected prior behavior
- PP remains effectively unchanged
- ROCm receives large, increasing TG gains with context length
- RGP directly confirms that ROCm full-context Flash Attention scaling is removed
- Vulkan correctness is preserved and performance remains within a few percent
  of its existing backend sparse-FA path, with a small 256k gain

The source currently keeps the runtime A/B control because the best path is
backend/context dependent. The current source default remains gather enabled
when `QWEN4EXP_QSA_GATHER` is unset; this should not be interpreted as proof that
gather is the optimal Vulkan choice at every context depth.

## Next target: COMMON-006

Post-COMMON-005 ROCm profiling makes COMMON-006 the next common/model candidate.

Current selection flow:

```text
block score
  -> expand to every KV cell through cell_blk
  -> cell-level top-k
```

Candidate direction:

```text
block-domain selection
  -> expand only selected blocks/cells
```

The design must preserve qwen4exp reference behavior around:

- `indexer_top_k + compress_ratio - 1`
- tail-block handling
- causal/visibility masking
- tie/ordering semantics

Keep COMMON-006 as a separate correctness-first A/B so the residual score-
expansion benefit can be attributed independently of COMMON-005.
