# r5 VULKAN-001B ROCmFPx integer-dot implementation and validation — 2026-10-21

## Status

**COMPLETE.**

VULKAN-001B is the Stage-3 ROCmFPx Vulkan performance/correctness layer on top of the validated VULKAN-001A correctness baseline.

Implementation commit:

```text
8205db29206c71feb86ee5322069cdc31e48c061
vulkan: add ROCmFPx integer-dot paths
```

Focused correctness-test commit:

```text
fe36a4d3fcfc6d96952f65386c2ac4b1579d3d51
tests: add ROCmFPx Vulkan batch-width coverage
```

Target model:

```text
Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf
```

Target backend:

```text
Windows Vulkan
GMKtec Evo-X2 / Radeon 8060S
```

MTP remains OFF in this stage.

## Donors

Historical behavior donors:

- `e282dfd6dfbaaaadc293bf2cb5d11108088400a2` — q8_1 integer-dot MMVQ/MMQ
- `f0a2bd6b34e83b4282d62b085e2d21ef2d241864` — ROCmFPx batch-3-8 correction

Current AgentionAI main was used only as the current-API structural reference. No wholesale fork merge was performed.

## Implemented scope

VULKAN-001B adds or completes:

- q8_1 integer-dot MMQ for Q4_0_ROCMFP4 and Q4_0_ROCMFP4_FAST;
- q8_1 MMVQ for Q4_0_ROCMFP4, Q4_0_ROCMFP4_FAST and Q8_0_ROCMFPX;
- `MUL_MAT_ID` registration for the same integer-dot paths;
- whole-block `K_PER_ITER = 32` handling for ROCmFP4/FAST;
- integer-MMQ shared-memory sizing;
- FP3/FP6 four-value dequant path used by the historical batch-3-8 correction.

FP3 and FP6 intentionally remain on the float mat-vec path.

Q2_0_ROCMFPX is not part of this Vulkan stage. COMMON-003A provides the format/core CPU path, but the historical Vulkan donor does not implement Q2.

## Model-runtime validation

Build:

```text
b11531-db0b11516
```

All runs use full model GPU offload, MTP OFF, and completed with coherent output.

| Context | Dispatch | PP | TG | Result |
|---|---|---:|---:|---|
| 32k | normal | 412.22 tok/s | 27.19 tok/s | pass |
| 32k | force MMVQ | 419.32 tok/s | 27.42 tok/s | pass |
| 64k | normal | 277.21 tok/s | 26.07 tok/s | pass |
| 64k | force MMVQ | 277.02 tok/s | 26.41 tok/s | pass |

Model placement remains approximately:

```text
Vulkan0 model buffer 88645.69 MiB
Vulkan_Host          497.31 MiB
CPU model buffer     absent
graph splits         2
```

### Stage-2 comparison

Stage-2 VULKAN-001A reference:

| Context | PP | TG |
|---|---:|---:|
| 32k | 410.33 | 27.06 |
| 64k | 277.55 | 25.99 |

Stage-3 normal dispatch versus Stage 2:

- 32k PP: +0.46%
- 32k TG: +0.48%
- 64k PP: -0.12%
- 64k TG: +0.31%

Forced MMVQ versus Stage 2:

- 32k PP: +2.19%
- 32k TG: +1.33%
- 64k PP: -0.19%
- 64k TG: +1.62%

The forced-MMVQ path is therefore useful as a validation knob but is **not** selected as the default dispatch policy: it provides no 64k PP gain.

## Focused numerical correctness gate

The Stage-3 test-only patch adds dedicated coverage for:

```text
Q4_0_ROCMFP4
Q4_0_ROCMFP4_FAST
Q3_0_ROCMFPX
Q6_0_ROCMFPX
Q8_0_ROCMFPX
```

For both `MUL_MAT` and `MUL_MAT_ID`:

```text
n = 1, 3, 4, 5, 6, 7, 8
m = 64
k = 256
```

For `MUL_MAT_ID`:

```text
n_mats = 4
n_used = 4
```

Using `n_used == n_mats` makes every token route to every expert, so the batch-width coverage is deterministic and does not depend on random expert selection.

Results:

| Test | Normal dispatch | GGML_VK_FORCE_MMVQ=1 |
|---|---:|---:|
| MUL_MAT | 35/35 | 35/35 |
| MUL_MAT_ID | 35/35 | 35/35 |
| Total | 70/70 | 70/70 |

**Overall: 140/140 passed, 0 failures.**

This explicitly validates the historical n=3-8 failure window under both normal and forced integer-dot routing before MTP is introduced.

The PowerShell log prefix may contain a `NativeCommandError` wrapper because backend-loader messages are emitted on stderr. The actual executable completed normally and reported all test suites/backends OK; this is not a test failure.

## AgentionAI comparison

Current AgentionAI reference:

| Context | PP | TG |
|---|---:|---:|
| 32k | 421.13 | 27.75 |
| 64k | 279.61 | 26.74 |

Stage-3 forced MMVQ is within roughly 0.4-0.9% PP and 1.2% TG of that fork.

Do not use the remaining gap as a ROCmFPx-port completion criterion. The current AgentionAI graph has unrelated Qwen/indexer/cache differences, including a different indexer KV layout and pooled indexer cache, so exact performance parity is not an isolated ROCmFPx comparison.

## Decision

VULKAN-001B is complete.

Keep:

- normal r5 Vulkan dispatch as the default;
- `GGML_VK_FORCE_MMVQ=1` only as a diagnostic/validation control;
- the focused ROCmFPx tests as a regression gate.

Next:

1. Stage 4, target model, MTP OFF.
2. Run 128k long-context compatibility because Stage-3 64k is already clean.
3. Run 256k only if 128k is stable and the extra cost is justified.
4. Only after Stage 4, attempt the MTP sidecar and determine whether old `output_hc_*` compatibility is actually needed.
