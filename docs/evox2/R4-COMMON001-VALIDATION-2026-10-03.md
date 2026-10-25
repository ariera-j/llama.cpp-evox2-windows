# r4 COMMON-001 validation

Validation date: 2026-10-03 JST.

## Result

COMMON-001 is **validated through 256k on both Vulkan and ROCm** for the
Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS PLE16 model with MTP disabled.

Implementation commit:

```text
a60a57879a9ffb4d51acd45d4de7e80d721548f9
qwen4exp: restore split PLE n-gram tensor support
```

Pinned upstream base:

```text
bed0a856606ee4a24a164066f73d2379447033f5
```

The port preserves the upstream joined-PLE path and adds the split per-head PLE
layout used by the converted PLE16 model. No COMMON-004, COMMON-005, grouped
union, or MTP-QSA implementation is included in this patch.

## Measurement conditions

Common conditions:

```text
UMA VRAM: 96 GB
MTP: off
K/V cache: f16
-ngl 999
-ncmoe 0
-t 4
-tb 4
-b 2048
-ub 1024
-fa auto
-fit off
--cache-ram 0
--ctx-checkpoints 0t
--reasoning off
generation budget: 1024 tokens
temperature: 0.2
top_p: 0.8
```

The Vulkan validation runs fix the diagnostic MoE policy to:

```text
GGML_VK_MOE_LEGACY_TILE_SELECTION=1
```

Profiler and experimental QSA/MTP overrides are cleared for the normal
throughput runs.

Benchmark plans:

```text
tools/evox2/benchmark/configs/qwen38-r4-common001-64k.psd1
tools/evox2/benchmark/configs/qwen38-r4-common001-longctx.psd1
```

## Build and smoke validation

Before the long-context measurements:

- Vulkan and ROCm were rebuilt after the COMMON-001 source commit.
- Original joined-PLE loading remained functional.
- PLE16 split-PLE loading succeeded on both backends.
- AllocationOnly / short inference succeeded on both backends.
- ROCm FLASH_ATTN_EXT backend validation completed 3986/3986 tests successfully.

The split-PLE buffer placement remains backend-dependent:

- Vulkan places the split PLE tensors on the GPU; the model GPU buffer rises to
  roughly 77.7 GiB and the large ~27.5 GiB CPU-side PLE table is absent.
- ROCm retains roughly 27.5 GiB of PLE model data on the CPU and roughly
  50.2 GiB on ROCm0.

This matches the backend-placement difference already observed on r3 and is not
newly introduced by the r4 port.

## 64k matched-layout gate

The first performance gate compares Original joined PLE and PLE16 with the same
post-port binaries. Vulkan uses the legacy MoE tile policy above.

| Backend | Model | Context | PP tok/s | TG tok/s |
|---|---|---:|---:|---:|
| Vulkan | Original joined | 64k | 267.51 | 24.53 |
| Vulkan | PLE16 | 64k | 268.79 | 25.46 |
| ROCm | Original joined | 64k | 370.32 | 21.17 |
| ROCm | PLE16 | 64k | 370.37 | 21.16 |

Interpretation:

- Original loading/performance does not show a material post-port regression.
- ROCm Original and PLE16 are effectively identical at 64k.
- Vulkan PLE16 is not slower than Original in this single matched pair. The TG
  difference is not treated as a proven PLE16 speedup because generation lengths
  and run-to-run variance are not controlled tightly enough for that claim.

The Vulkan pre-port Original 64k legacy-MoE reference was approximately
268.99 PP / 24.57 TG, so the post-port Original result is within about -0.6% PP
and -0.2% TG of that reference.

## 128k and 256k PLE16 validation

After the 64k gate passed, only PLE16 was carried forward for the long-context
validation because the joined Original path had already passed the clean r4
baseline through 256k and showed no material 64k regression after the port.

| Backend | Context | PP tok/s | TG tok/s | Result |
|---|---:|---:|---:|---|
| Vulkan | 128k | 178.99 | 23.24 | OK |
| ROCm | 128k | 279.80 | 17.13 | OK |
| Vulkan | 256k | 132.99 | 19.56 | OK |
| ROCm | 256k | 185.90 | 12.41 | OK |

All four runs completed with Status OK / ExitCode 0. No load failure, extreme
slowdown, or crash was observed through 256k.

## Comparison with r4 clean upstream

The primary r4 clean baseline used the Original joined-PLE model and the
upstream-default Vulkan MoE tile policy. Therefore the Vulkan delta below is
**not** attributed to COMMON-001 alone. ROCm does not have that Vulkan-only
policy difference and is the cleaner compatibility/performance comparison.

| Backend | Context | r4 clean PP/TG | COMMON-001 PLE16 PP/TG |
|---|---:|---:|---:|
| Vulkan | 64k | 248.38 / 24.61 | 268.79 / 25.46 |
| Vulkan | 128k | 168.09 / 22.81 | 178.99 / 23.24 |
| Vulkan | 256k | 126.76 / 19.26 | 132.99 / 19.56 |
| ROCm | 64k | 369.72 / 20.98 | 370.37 / 21.16 |
| ROCm | 128k | 275.00 / 17.13 | 279.80 / 17.13 |
| ROCm | 256k | 185.95 / 12.23 | 185.90 / 12.41 |

ROCm is effectively performance-neutral across the full range. Its 64k -> 256k
scaling is also almost unchanged by the split layout.

For Vulkan, the 64k PP increase from 248.38 to 268.79 (+8.2%) closely matches
the previously measured same-binary MoE tile A/B result of roughly +8.25% for
legacy selection. The COMMON-001 64k Original/PLE16 matched pair differs by only
about +0.5% PP. The larger Vulkan baseline delta is therefore treated primarily
as the MoE tile-policy difference, not as a COMMON-001 performance gain.

## Comparison with r3 COMMON-001

Historical r3 COMMON-001 PLE16 results:

| Backend | Context | r3 PP | r3 TG | r4 PP | r4 TG |
|---|---:|---:|---:|---:|---:|
| Vulkan | 64k | 267.90 | 17.20 | 268.79 | 25.46 |
| Vulkan | 128k | 159.56 | 12.00 | 178.99 | 23.24 |
| Vulkan | 256k | 103.75 | 7.30 | 132.99 | 19.56 |
| ROCm | 64k | 357.93 | 14.86 | 370.37 | 21.16 |
| ROCm | 128k | 259.41 | 9.91 | 279.80 | 17.13 |
| ROCm | 256k | 167.35 | 5.74 | 185.90 | 12.41 |

The r4 upstream QSA/k-pool path removes most of the severe TG depth loss seen
immediately after r3 COMMON-001. This is a refreshed-upstream improvement, not a
claim that COMMON-001 itself accelerates decode.

## Comparison with the r2 frozen Vulkan reference

The r2 frozen grouped-union path remains the Vulkan long-context PP reference:

| Context | r2 grouped-union PP | r4 COMMON-001 PP | r2 grouped-union TG | r4 COMMON-001 TG |
|---|---:|---:|---:|---:|
| 64k | 274.67 | 268.79 | 23.55 | 25.46 |
| 128k | 222.77 | 178.99 | ~21.65 | 23.24 |
| 256k | 177.01 | 132.99 | 18.84 | 19.56 |

TG is now at or above the old r2 range, while Vulkan PP still trails r2 more as
context depth increases. This strengthens the case for evaluating VULKAN-002 as
a long-context prefill optimization after the small cached-pool-gather follow-up
is bounded.

## Decision

COMMON-001 is complete for the current r4 checkpoint:

- split PLE16 compatibility restored
- joined Original path preserved
- Vulkan and ROCm short smoke passed
- 64k Original/PLE16 matched comparison passed
- PLE16 128k and 256k passed on both backends
- no material performance regression attributable to the compatibility port

The remaining performance topics are separate from COMMON-001. The next decision
is whether the measured Vulkan cached-pool gather cost can be reduced with a
small, well-scoped change. If that requires a broad cache/layout rewrite, keep
the diagnostic reference and proceed to VULKAN-002. COMMON-005 remains the
ROCm-oriented long-context decode candidate after the Vulkan PP work or if
profiling priority changes.
