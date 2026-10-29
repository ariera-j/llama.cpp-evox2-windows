# r5 MTP-NOOP + ROCmFPx integration check — 2026-10-21

## Purpose

This branch is an integration rehearsal, not the weekend integrated release.

Base:

```text
investigation/r5-mtp-noop-20261012
80dd44ed90e8e199786c8c436bbb9a084bde4aa5
```

Integration-check branch:

```text
integration-check/r5-noop-rocmfpx-20261021
```

Goal: determine whether the already-validated ROCmFP4/ROCmFPx implementation can coexist structurally with the r5 VULKAN-002 + MTP-DENSE + MTP-NOOP line before the later latest-upstream integration.

This branch deliberately does **not** import Stage-B / EH-proj flatten yet.

## Important integration finding

The isolated ROCmFPx validation branch was based on a line that did not contain the current VULKAN-002 grouped-union implementation.

Therefore copying final files wholesale from
`investigation/r5-rocmfpx-vulkan-20261020`
would silently remove existing r5 VULKAN-002 source, including the selected-row API and grouped-union Vulkan path.

The final integration-check branch does **not** use whole-file replacement for overlapping source. Instead, the validated ROCmFPx commits were replayed hunk-by-hunk onto the NOOP base. All ROCmFPx hunks used here applied without conflict.

This is also the recommended rule for the future newest-upstream integration: semantic/hunk-level port, not wholesale file replacement.

## Ported logical units

### ROCmFPx core

Source validation commit:

`85ab8d797f176c322f77647e27ebea3ee5d29931`

Integration-check commit:

`454af536c9084e7f4d4048bfb52915fe8450883a`

Includes:

- historical GGML ROCmFPx type IDs;
- ROCmFP4 / ROCmFP4-FAST / FP2 / FP3 / FP6 / FP8 core layouts;
- quantize/dequantize and validation;
- CPU fallback;
- model ftype/load registration.

The NOOP base's existing `ggml_flash_attn_ext_set_selected_rows` API is preserved.

### ROCmFPx Vulkan correctness

Source validation commit:

`202f498877d03aa2c31b7d455b64c5452a4545b8`

Integration-check commit:

`01d4d843efb4fa3fc12cdcea0a57cd8c853dcb13`

All 21 `ggml-vulkan.cpp` hunks and the shader hunks apply cleanly on top of the NOOP/VULKAN-002 source.

### ROCmFPx Vulkan integer-dot

Source validation commit:

`8205db29206c71feb86ee5322069cdc31e48c061`

Integration-check commit:

`842aaabab366732763f96fce8c852121646a16b4`

All seven modified files apply without conflict.

Preserves the validated q8_1 MMVQ/MMQ paths, MUL_MAT_ID registration, ROCmFP4 K_PER_ITER=32 handling and the FP3/FP6 batch-width correction.

### Focused backend coverage

Source validation commit:

`fe36a4d3fcfc6d96952f65386c2ac4b1579d3d51`

Integration-check commit:

`b78266377bb87e81ac71f0ec71f4aee334f185ad`

Carries the focused Vulkan ROCmFPx MUL_MAT / MUL_MAT_ID widths 1,3,4,5,6,7,8 tests. The isolated source previously passed 140/140 under default and forced-MMVQ dispatch.

### Agention old-HC MTP compatibility

Source validation commit:

`9fa9970b19c1c4aba87934686c9b74f3b2f32ecf`

Integration-check commit:

`a8640e560959b33976c5c6697885bd474742f9ff`

All three hunks apply cleanly to the NOOP branch's `qwen4exp.cpp`.

The existing NOOP/DENSE ratio-zero guard remains present:

```cpp
hparams.dsv4_compress_ratios[il] > 0
```

The separate ROCmFPx validation commit
`a09d40719f6d0af159216357708f376ff51170ea`
is therefore **not** replayed because the NOOP base already contains the equivalent dense-MTP k-pool guard.

## Static coexistence checks

Verified on the integration-check branch:

| Existing / added feature | Static result |
| --- | --- |
| VULKAN-002 grouped-union control `GGML_VK_QSA_UNION` | preserved |
| selected-row FA API | preserved |
| MTP-DENSE control `LLAMA_MTP_SKIP_DENSE_INDEXER` | preserved |
| MTP-NOOP control `LLAMA_QSA_SKIP_NOOP_INVALIDATION` | preserved |
| dense-MTP ratio-zero k-pool guard | preserved |
| ROCmFP4 / ROCmFPx GGML types | present |
| ROCmFPx Vulkan dispatch | present |
| old `output_hc_*` MTP fallback | present |
| ROCmFPx focused backend tests | present |

Compared with `investigation/r5-mtp-noop-20261012`, the branch is five source commits ahead before this documentation commit. The changed-file set is restricted to the expected ROCmFPx core/Vulkan/test files plus `src/models/qwen4exp.cpp`; existing DENSE/NOOP implementation files are not replaced.

## Windows validation gate

This branch has passed source-level integration review only. It still needs a native Windows build/run before the coexistence check is accepted.

Recommended bounded gate:

1. clean Vulkan build;
2. run focused ROCmFPx backend tests, first default dispatch and then `GGML_VK_FORCE_MMVQ=1`;
3. target-only Agention ROCmFP4 allocation/short inference;
4. target + ROCmFP4 MTP short inference, DraftMax=2;
5. enable the existing DENSE + NOOP controls used by their validated branch and repeat the short MTP run;
6. optionally one 64k run only if the short combined gate is clean.

This is an integration/correctness rehearsal. Do not spend time on 128k/256k performance or RGP here.

## Weekend integration implication

Current evidence says the following source families are structurally compatible on the pinned r5 lineage:

- VULKAN-002;
- MTP-DENSE;
- MTP-NOOP;
- ROCmFP4/ROCmFPx core;
- ROCmFPx Vulkan correctness + integer-dot paths;
- Agention old-HC MTP sidecar compatibility.

For the weekend newest-upstream build, repeat the same semantic-port approach because upstream Qwen4Exp, k-pool, speculative decoding and Vulkan code have moved materially since the r5 pin.

Stage-B and EH-proj flatten remain a separate interaction gate and are not proven combined by this branch.


## Windows backend validation — 2026-10-21

Build directory:

`build-vulkan-r5-noop-rocmfpx`

Focused ROCmFPx Vulkan backend tests were repeated on the integrated NOOP/VULKAN-002 branch.

Observed Vulkan device:

```text
AMD Radeon(TM) 8060S Graphics
int dot: 1
matrix cores: KHR_coopmat
```

The backend reports `QSA grouped-union = off` for these backend-op tests, which is expected because the grouped-union feature is an opt-in model-level path and is not part of these focused matrix-operation tests.

Results:

| Gate | Normal dispatch | GGML_VK_FORCE_MMVQ=1 |
| --- | ---: | ---: |
| MUL_MAT | 35/35 | 35/35 |
| MUL_MAT_ID | 35/35 | 35/35 |
| Total | 70/70 | 70/70 |

Overall: **140/140 PASS, zero failures**.

Covered ROCmFPx Vulkan types:

- `q4_0_rocmfp4`
- `q4_0_rocmfp4_fast`
- `q3_0_rocmfpx`
- `q6_0_rocmfpx`
- `q8_0_rocmfpx`

For each type, widths `n = 1, 3, 4, 5, 6, 7, 8` passed for both `MUL_MAT` and `MUL_MAT_ID`.

This confirms that the validated ROCmFPx correctness and integer-dot paths remain numerically healthy after being replayed onto the r5 VULKAN-002 + MTP-DENSE + MTP-NOOP branch.

### Remaining integration gates

Backend coexistence is now validated. The remaining bounded checks are model-level:

1. run the existing NOOP native policy/model-state gate on this integrated build using the Agention ROCmFP4 target model;
2. run one short real target+ROCmFP4-MTP inference with DENSE=1 and NOOP=1;
3. grouped-union should be enabled in the model-level gate so the retained VULKAN-002 path is exercised in a real Qwen3.8 graph;
4. no 128k/256k performance run is required for this rehearsal.

If those model-level gates pass, mark the NOOP + ROCmFPx integration rehearsal complete and leave Stage-B / EH-proj flatten as the next independent interaction check.


## Native NOOP + all-on model validation — 2026-10-21

### Native QSA NOOP gate

`Test-QsaNoopInvalidation.ps1` completed with:

```text
Status       = Complete
SourceChecks = Passed
PolicyTest   = Passed
ModelTest    = Passed
```

Both native executables exited 0 with verified runtime/build identity.

The model/state/rollback gate used the Agention ROCmFP4 target GGUF and reported:

```text
QSA no-op invalidation: PASS (target numeric, pools, rollback, state and fallback)
```

The detailed numeric checks reported zero NMSE / zero max-absolute error across the tested target logits/hidden-state restore and trim cases.

### All-on real model smoke

Run:

```text
build      : b11588-1c3167fb6
context    : 32768
prompt     : 163 tokens
target     : Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf
draft      : Qwen3.8-Flash-Next-MTP-ROCmFP4-FAST.gguf
DraftMax   : 2
```

Enabled together:

```text
GGML_VK_QSA_UNION=1
GGML_VK_QSA_UNION_MIN_KV=1
LLAMA_MTP_SKIP_DENSE_INDEXER=1
LLAMA_QSA_SKIP_NOOP_INVALIDATION=1
```

Result:

| Item | Result |
| --- | ---: |
| Status | OK / exit 0 |
| Target file type | Q4_0_ROCMFP4_FAST |
| Target GPU layers | 49/49 |
| Draft GPU layers | 50/50 |
| Prompt tokens | 163 |
| PP | 97.57 tok/s |
| Generated tokens | 128 |
| TG | 25.05 tok/s |
| Draft generated | 114 |
| Draft accepted | 69 |
| Draft acceptance | 60.526% |
| Mean accepted length | 2.21 |
| Dense indexer evidence | Verified / omitted |
| NOOP invalidation evidence | Verified / enabled |
| Output | coherent |

The short run is a correctness stress only; PP/TG are not performance numbers.

### Grouped-union path proof

The Vulkan backend first reports:

```text
ggml_vulkan: QSA grouped-union = on (group=64, min_kv=1)
```

and during the target prefill actually enters the optimized path:

```text
ggml_vulkan: qsa-union active (r5), group=64, bitmap=16KiB,
path=1, Br=16, Bc=64, f32acc=1, groups=1, capacity=256,
min_kv=1, scratch=558096 bytes
```

Later generation emits:

```text
ggml_vulkan: qsa-union fallback: query count or KV threshold
```

This later fallback is expected for decode / single-query shapes; it does not negate the earlier active-prefill proof.

Therefore this single run conclusively exercised:

- ROCmFP4/ROCmFPx target Vulkan kernels;
- ROCmFP4 MTP draft model and old-HC fallback;
- MTP-DENSE indexer omission;
- MTP-NOOP target invalidation suppression;
- VULKAN-002 grouped-union target prefill;
- normal decode fallback after the grouped-union prefill path.

### Integration-rehearsal decision

**PASS — COMPLETE.**

The pinned-r5 source families are proven to coexist both structurally and at runtime:

- VULKAN-002;
- MTP-DENSE;
- MTP-NOOP;
- ROCmFP4 / ROCmFPx core;
- ROCmFPx Vulkan correctness and integer-dot;
- old-layout Agention ROCmFP4 MTP compatibility.

No additional long-context run is required for this rehearsal.

The next independent interaction question is Stage-B + EH-proj flatten. The weekend integrated build should still start from the newest selected upstream and replay these features semantically rather than copying whole files from this branch.
