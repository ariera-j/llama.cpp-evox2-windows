# r5 COMMON-001 Windows validation (2026-10-09)

## Decision

**ACCEPTED for the requested r5 COMMON-001 compatibility gate:** b11521 Windows builds on both Vulkan and ROCm loaded and ran Original joined-PLE and split PLE16 Unsloth GGUFs, and the 64k full-document PP/TG comparison found no material regression. PLE16-specific GPU/offload behavior was reproduced (backend-dependent). **No further COMMON-001-only measurement is requested now.** Record the small Vulkan TG difference as unresolved rather than promoting a performance optimization claim.

Source change: [`b45025848b97fc8fd3efa7333305567bc897f61f`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/b45025848b97fc8fd3efa7333305567bc897f61f), four native source files only. VULKAN-002 is not in this binary. Prior [implementation details](R5-COMMON001-IMPLEMENTATION-2026-10-09.md); preserved [clean baseline](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md); [r4 COMMON-001](R4-COMMON001-VALIDATION-2026-10-03.md) and [r4 VULKAN-002](R4-VULKAN002-VALIDATION-2026-10-04.md) are historical comparisons.

## Data and identity

- AllocationOnly/short inference: user-supplied preceding archive, **Vulkan Original, Vulkan PLE16, ROCm Original, ROCm PLE16 all 4/4 OK, exit 0**, prompt "Reply with the word OK.", generated "OK". Does not establish benchmark speed.
- Full-document archive (retained locally, not committed): `20261009-162422-245-qwen38-r5-common001.zip`, containing `matrix-plan.json`, `matrix-result.json`, `matrix-results.csv` and four child results and resource logs.
- All four long runs: **Status OK / ExitCode 0**, **RuntimeArtifactStatus Verified**, **b11521**, embedded `b45025848`, build manifest/source commit `b45025848b97fc8fd3efa7333305567bc897f61f`, Windows 11 26H2 on Evo-X2 Radeon 8060S, UMA label 96GB.
- Vulkan executable SHA256: `3eb770f43555399b4fb467fe1991ebe8b2acd75a751da25f8733f637c7687ab9`; runtime digest `3010eec7d5f9f95e0dec8057f9520e45e746676b9dcf03aa249e643b7ee88635`.
- ROCm executable SHA256: `90cb1b05cfb83b7c66cdfbe43d479d4b382b25ddae01d6aa50c4f9bb2179616f`; runtime digest `db802028bde5aae255ff84c216242ebf7bd4e8da15321cd8fcffce5dd5470215`.
- `GitDirty=True` in all children is explained *exclusively* by untracked local `tools/evox2/benchmark/configs/qwen38-r5-common001-local.psd1`; Git `StatusPorcelain` lists no tracked source changes. The checked build manifest says source stable during build and embedded commit matches.
- Context 65536, actual 61789 prompt tokens, **same input SHA256 for all four**: `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`.
- Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS GGUF, Original first joined-layout shard versus pre-existing split PLE16 conversion; MTP OFF; K/V f16; batch 2048; ubatch 1024; threads 4, threads-batch 4; all GPU layers (49/49); `-ncmoe 0`, FA auto, cache-ram 0, ctx-checkpoints 0t, temperature 0.2, top-p 0.8, reasoning off, resource monitor ON. Uses the copied r5 clean plan with per-model/build-key selection.
- **One run per backend/model combination, sequential Original then PLE16; generation stopped at EOS with different output counts.** This is a functional/performance sanity gate, not randomized or interleaved repeated A/B. Model file hashes were not computed in these children.

## 64k full-document results

| Backend | Layout | PP tok/s | TG tok/s | Output tokens | Prompt eval ms | Generation eval ms |
|---|---|---:|---:|---:|---:|---:|
| Vulkan | Original joined | **269.30** | **25.42** | 638 | 229439.62 | 25058.77 |
| Vulkan | PLE16 split | **270.65** | **25.90** | 609 | 228298.41 | 23471.89 |
| ROCm | Original joined | **389.78** | **21.18** | 529 | 158521.66 | 24929.07 |
| ROCm | PLE16 split | **389.01** | **21.15** | 510 | 158836.33 | 24068.18 |

Same-binary PLE16 vs Original:

| Backend | PP delta | TG delta | Assessment |
|---|---:|---:|---|
| Vulkan | +0.50% | **+1.89%** | No regression; TG is a repeated *observation*, not proof of a layout speedup |
| ROCm | -0.20% | -0.14% | Effectively neutral |

The **r5 clean Original-only** reference (a different b11517 binary, earlier same OS session) was Vulkan PP/TG **269.24 / 25.31** and ROCm **390.73 / 21.18**. The post-port Original run remains close: Vulkan PP +0.02%, ROCm PP -0.24%. This supports no material Original regression from COMMON-001; it is not a controlled replicated source-only A/B.

## GPU/CPU model buffer placement

From the child `stderr.log` model-buffer messages (MiB, excluding Vulkan_Host/ROCm_Host 497.31 MiB and excluding KV/compute buffers):

| Backend | Layout | Device model MiB | CPU model MiB |
|---|---|---:|---:|
| Vulkan | Original | 50191.11 | 27465.95 |
| Vulkan | PLE16 | **77657.05** | not reported (split heads GPU-resident) |
| ROCm | Original | 50191.17 | 27465.95 |
| ROCm | PLE16 | 50191.17 | 27465.94 |

All four `stderr.log` files report **49/49 layers offloaded to GPU**. This reproduces the backend-dependent placement seen in r4, **not** a new backend optimization. There are no fatal load, allocation, or inference errors in the four logs. Do not interpret a missing CPU model-buffer line as zero total system RAM consumption; it reports only model-buffer allocation by that name.

## Vulkan TG difference: recorded, not promoted

- In this r5 64k pair, PLE16 TG is 25.90 vs Original 25.42 tok/s (**+1.89%**), while PP differs only +0.50%.
- Comparable historical r4 observations: r4 COMMON-001 64k Original 24.53 vs PLE16 25.46 tok/s; r4 VULKAN-002 **union OFF** 64k normal ABBA means Original 24.72 vs PLE16 25.30. ROCm matched-model observations were neutral.
- Each r5 model was run once, in sequential rather than interleaved order; 638 vs 609 Vulkan generated tokens differ, and neither seed nor fixed output length was imposed. Initial/steady generation timings, host memory placement and paging behavior may contribute, **but the cause is not established**.
- **Decision: defer new ABBA/repeats.** If a later experiment needs causal attribution, run same-binary Original/PLE16 ABBA with fixed seed, fixed output tokens and ignore-EOS, and separate warm-up from steady decode. VULKAN-002's later ABBA is a *different*, QSA-OFF/ON effect test; do not mix the two variables.

## Next work (user decision, 2026-10-09)

1. Mark the r5 COMMON-001 **allocation + short inference + 64k comparison** as complete; do not require a separate COMMON-001 128k/256k sweep.
2. **Reorganize repository branches next, as a separate operation**: preserve legacy r2 (currently `main` at `23c316fb5af67da74e614af4a7453fba9ae46189`) with an unambiguous r2 branch; expose frozen r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8` as new default `main`; retain both r4 frozen and r5 active refs. Check GitHub default-branch behavior, permalink/document impact, and local clones before migration.
3. **Then VULKAN-002 source/port review and PLE16 64k→128k→256k QSA union OFF/ON A/B**, with constant executable/model/input and unchanged upstream MoE tile selection.
4. r2 specialized-fork PLE extras are [deferred](R2-PLE-LEGACY-SOURCE-REVIEW-2026-10-09.md); revisit only on a relevant source-fork change or new requirement.

No inference-source changes or branch renames were made by this validation record.
