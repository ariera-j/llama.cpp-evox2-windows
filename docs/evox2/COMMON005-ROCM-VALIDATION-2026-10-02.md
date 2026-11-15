# COMMON-005 ROCm validation - 2026-10-02

## Purpose

Record the first implementation/validation results for COMMON-005, the qwen4exp
gather-based QSA decode path derived from the design around upstream PR #28213.

COMMON-005 gathers the QSA-selected K/V rows and the matching existing KQ-mask
rows during long-context single-token decode, then runs ordinary Flash
Attention on the compact tensors. The existing full-K/V path remains available
through the runtime A/B switch.

This document covers ROCm only. Vulkan validation remains a separate gate
because Vulkan already has a backend sparse-Flash-Attention path.

## Implementation under test

```text
commit: d03c91b6342b099457de3508c5d67533a9a5f0ee
build:  b11264
backend: ROCm/HIP
target: gfx1151
compiler: AMD Clang 23.0.0
ROCm SDK: 10.0.0
```

Runtime controls:

```text
QWEN4EXP_QSA_GATHER=0   # COMMON-005 OFF
QWEN4EXP_QSA_GATHER=1   # COMMON-005 ON
```

COMMON-004 remained enabled for every measurement:

```text
LLAMA_QSA_NO_POOLED_CACHE=<unset>
LLAMA_QSA_POOLED_MAX_TOKENS=32
```

The ROCm build passed the FLASH_ATTN_EXT backend test with 3982/3982 tests
passing. An allocation-only smoke test also completed successfully with the
PLE16 model.

## Benchmark workload

- GMKtec Evo-X2 / Radeon 8060S
- UMA setting: 96 GB
- Qwen3.8-Flash-Next PLE16-converted Unsloth UD-IQ3_XXS
- MTP disabled
- f16 K/V
- batch 2048
- ubatch 1024
- 4 CPU threads / 4 batch threads
- all supported model layers offloaded
- Flash Attention auto
- generation budget 1024
- temperature 0.2
- top_p 0.8
- prompt cache disabled
- context checkpoints disabled

64k used one OFF -> ON pair as an initial gate. 128k and 256k used ABBA order:

```text
A1 gather ON
B1 gather OFF
B2 gather OFF
A2 gather ON
```

All 10 runs completed successfully.

## Benchmark results

### Raw TG values

```text
64k
OFF 20.55 tok/s
ON  22.60 tok/s

128k
ON  20.35 tok/s
OFF 16.43 tok/s
OFF 16.42 tok/s
ON  20.47 tok/s

256k
ON  17.37 tok/s
OFF 11.68 tok/s
OFF 11.68 tok/s
ON  17.37 tok/s
```

### Aggregated results

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG gain |
|---|---:|---:|---:|---:|---:|
| 64k | 359.37 | 357.27 | 20.55 | 22.60 | +10.0% |
| 128k | 262.44 | 262.50 | 16.425 | 20.41 | +24.3% |
| 256k | 167.58 | 167.99 | 11.68 | 17.37 | +48.7% |

128k and 256k values are ABBA averages. 64k is one OFF/ON pair.

PP is essentially unchanged at 128k and 256k. The 64k difference is below 1%
and is treated as normal run-to-run variation unless future Vulkan/ROCm data
shows otherwise.

### Decode latency and depth scaling

Converted to milliseconds per generated token:

| Context | Gather OFF | Gather ON |
|---|---:|---:|
| 64k | 48.66 ms/token | 44.25 ms/token |
| 128k | 60.88 ms/token | 49.00 ms/token |
| 256k | 85.62 ms/token | 57.57 ms/token |

The primary depth comparison is 128k -> 256k:

```text
COMMON-005 OFF:
60.88 -> 85.62 ms/token
+24.73 ms/token

COMMON-005 ON:
49.00 -> 57.57 ms/token
+8.57 ms/token
```

COMMON-005 therefore removes about 65.3% of the additional 128k -> 256k decode
latency observed on the fallback path.

TG depth loss over the same range changes from about -28.9% OFF to about -14.9%
ON.

The fallback values also reproduce the previous COMMON-004 ROCm baseline closely
(20.62 / 16.44 / 11.60 tok/s at 64k / 128k / 256k), which is a useful check that
the new source change did not materially alter the disabled path.

## RGP capture conditions

Radeon GPU Profiler used steady-decode dispatch-timer captures with 4096
dispatches.

```text
128k capture time:  530000 ms
256k capture time: 1560000 ms
```

COMMON-005 and COMMON-004 were enabled in both profiling runs.

## RGP: 128k after COMMON-005

The expensive-event distribution changed substantially from the pre-COMMON-005
profile.

The top repeated `k_get_rows_float` events were approximately:

```text
448.251 us
448.248 us
447.987 us
447.983 us
447.917 us
447.916 us
447.860 us
447.803 us
447.695 us
447.571 us
```

Mean of these representative events:

```text
~447.92 us
```

This is essentially unchanged from the pre-COMMON-005 128k value of about
0.451 ms, as expected: COMMON-005 intentionally does not modify the
block-score-to-full-cell expansion in `build_qsa_top_k()`.

The Flash Attention kernel changed from the old full-context variant:

```text
flash_attn_tile<256,256,1,4,false>
~1.45 ms at 128k before COMMON-005
```

to the compact-K/V variant:

```text
flash_attn_tile<256,256,2,1,false>
```

Twelve visible 128k tile samples ranged from about 41.24 to 42.90 us, with a
representative mean of about 41.93 us. `flash_attn_combine_results<256>` was
only a few microseconds per invocation.

The tile kernel is therefore roughly 34x shorter than the old 128k full-context
tile kernel. This is direct profiler evidence that COMMON-005 is actually
feeding a compact attention problem to the HIP backend rather than merely
changing the mask representation.

The repeated full-attention-group cadence changed from roughly +586 dispatches
before COMMON-005 to roughly +590 after COMMON-005, consistent with the added
K/V/mask gather work while preserving the same higher-level 12-group decode
structure.

The most expensive 5% of events accounted for about 70% of the selected frame,
versus about 78% in the pre-COMMON-005 128k profile. This percentage is only a
supporting observation because RGP selection/zoom affects the distribution.

## RGP: 256k after COMMON-005

The 256k expensive-event list is now dominated by `k_get_rows_float`, not Flash
Attention.

The main repeated `k_get_rows_float` events visible in the expensive-event list
were approximately:

```text
910.397 us
909.739 us
907.212 us
906.644 us
906.221 us
906.022 us
903.686 us
```

Representative mean:

```text
~907.13 us
```

A separate visible `k_get_rows_float` occurrence was about 520.99 us; it is not
included in the repeated main-path average above because its duration/role is
clearly different from the seven ~0.9 ms events.

Comparing the repeated main path:

```text
128k: ~447.92 us
256k: ~907.13 us
ratio: ~2.03x
```

This reproduces the expected O(n_kv) scaling of the block-score-to-full-cell
expansion after COMMON-005.

With 12 full-attention groups per token, the representative increase contributes
approximately:

```text
(907.13 - 447.92) us * 12 ~= 5.51 ms/token
```

The measured COMMON-005 ON latency increase from 128k to 256k is about
8.57 ms/token, so this single remaining `get_rows` path can account for roughly
64% of the residual depth slope by nominal summed event time.

The 256k `Most expensive events` view no longer shows Flash Attention among the
dominant events. The supplied 256k screenshots did not include an
`Event timing` view filtered to `flash_attn`, so this document does not assign an
exact 256k Flash Attention duration. The absence of the old multi-millisecond FA
kernel from the expensive-event list is nevertheless consistent with the
benchmark improvement and the direct 128k compact-FA measurement.

The repeated major-event cadence remains about +590 dispatches at 256k, matching
the 128k COMMON-005 graph structure.

The most expensive 5% of events accounted for about 72% of the selected 256k
frame, and the selected region about 86% of profile GPU time. Again, these
percentages are supporting observations rather than strict cross-capture
metrics.

## Interpretation

The benchmark and profiler evidence agree with the intended COMMON-005 mechanism:

```text
Before COMMON-005 on ROCm
selected top-k indices
  -> full-length sparse mask
  -> full K/V
  -> HIP dense/full-context Flash Attention

COMMON-005 ON
selected top-k indices
  -> gather selected K
  -> gather selected V
  -> gather matching existing mask rows
  -> compact K/V/mask
  -> ordinary Flash Attention over the compact set
```

The old full-context Flash Attention cost is no longer the dominant 128k/256k
ROCm decode cost. The remaining depth-dependent path is now much more visibly
concentrated in the full cell-score expansion before top-k.

## COMMON-006 implication

COMMON-005 intentionally leaves this flow unchanged:

```text
block score
  -> expand to every KV cell via cell_blk
  -> cell-level top-k
```

RGP now shows that this remaining `k_get_rows_float` scales from about 0.448 ms
at 128k to about 0.907 ms at 256k. This is strong post-COMMON-005 evidence for
the existing COMMON-006 candidate:

```text
block-domain selection
  -> expand only selected blocks/cells
```

COMMON-006 should remain a separate correctness-first patch so its benefit can
be measured against a fixed COMMON-005 baseline.

## Current decision

ROCm performance/correctness gate:

```text
PASS
```

Reasons:

- build and FLASH_ATTN_EXT backend tests pass
- allocation-only smoke passes
- all 10 real-input matrix runs pass
- fallback path reproduces the previous baseline
- PP is effectively unchanged
- TG improves increasingly with context depth
- 128k -> 256k added decode latency drops by about 65%
- RGP directly shows compact Flash Attention at 128k
- RGP leaves the expected O(n_kv) score-expansion path visible for COMMON-006

COMMON-005 should not yet be marked fully validated across the project until the
Vulkan A/B is complete. Vulkan is the next validation gate because its fallback
path already uses backend sparse Flash Attention and may have a different
performance crossover from ROCm.
