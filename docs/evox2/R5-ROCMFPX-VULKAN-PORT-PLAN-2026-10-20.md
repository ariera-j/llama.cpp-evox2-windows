# r5 ROCmFPx / ROCmFP4 Vulkan port plan — 2026-10-20

## Status

**STAGE 5A PASS AT 32K WITH ROCmFP4 MTP SIDECAR. NEXT: STAGE 5B 64K MTP OFF/ON MATCHED GATE.**

Stage 1 / COMMON-003A implementation commit: `85ab8d797f176c322f77647e27ebea3ee5d29931` (`ggml: add ROCmFPx core format support`).

Stage 2 / VULKAN-001A implementation commit: `202f498877d03aa2c31b7d455b64c5452a4545b8` (`vulkan: add ROCmFPx correctness kernels`).

Handoffs:

- [COMMON-003A core implementation and observed Stage-1 runtime](R5-COMMON003A-ROCMFPX-CORE-IMPLEMENTATION-2026-10-20.md)
- [VULKAN-001A correctness implementation and Windows gates](R5-VULKAN001A-ROCMFPX-CORRECTNESS-IMPLEMENTATION-2026-10-20.md)

This branch is intentionally based on the minimal r5 split-PLE checkpoint so ROCmFPx can be attributed independently from the later MTP/QSA/Vulkan experiments.

## Branch and fixed base

| Item | Identity |
|---|---|
| Investigation branch | `investigation/r5-rocmfpx-vulkan-20261020` |
| Fixed base | `b45025848b97fc8fd3efa7333305567bc897f61f` |
| Base content | r5 upstream refresh + minimal COMMON-001 split PLE16 support |
| Initial failing build | b11521 / `b45025848` |
| Target backend for this port | Windows Vulkan on Evo-X2 / Radeon 8060S |
| ROCm/HIP backend | explicitly out of initial scope |

Target target-model artifact:

`Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf`

Target MTP artifact, after the target model is stable:

`Qwen3.8-Flash-Next-MTP-ROCmFP4-FAST.gguf`

The current b11521 failure is before model/PLE/MTP graph construction:

```text
tensor 'output_hc_down.weight' has invalid ggml type 101. should be in [0, 43)
```

Type 101 is `GGML_TYPE_Q4_0_ROCMFP4_FAST`. The immediate blocker is therefore missing ROCmFPx GGML type support, not COMMON-001.

For load-debug runs use `-fit off` initially so the fit probe does not duplicate the same loader error.

## Donor hierarchy

Use the donors in this order.

### 1. Current agentionai/llama.cpp main — primary structural donor

Pinned during this review at:

`dc255f2a4b6e4211b555b0c05260b2523281f314`

Reason:

- it remains the current maintained ROCmFPx implementation;
- it has already been rebased/merged onto much newer upstream structures than the original August port;
- it therefore gives the best examples for adapting type registration and Vulkan dispatch to r5.

Do **not** merge the fork wholesale. It contains many unrelated Strix, trellis, MTP, scheduler and Vulkan changes.

### 2. r2/legacy — behavior and provenance reference

The following original feature commits remain useful as bounded implementation units:

- `8610c8b36284dbed5f02aa9a429251ecbfa9510d` — ROCmFPx type/core + CPU + base Vulkan support.
- `e282dfd6dfbaaaadc293bf2cb5d11108088400a2` — Vulkan q8_1 integer-dot MMVQ/MMQ.
- `f0a2bd6b34e83b4282d62b085e2d21ef2d241864` — ROCmFPx batch 3–8 mat-vec correction.

The standalone ROCmFP4 implementation files and the two basic Vulkan dequant shaders are unchanged between r2 and current agentionai at the reviewed heads. This makes r2 a trustworthy behavioral reference even though the original Laurent repository is gone.

### 3. MTP compatibility donor — only after target-model validation

Current agentionai commit:

`93a24e52cc12687213c0432af41c7fe2ab1a0eda`

It accepts both current upstream `blk.<il>.nextn.hc_head_*` names and the older `output_hc_*` layout used by older MTP-only sidecars. Do not port this pre-emptively into COMMON-003/VULKAN-001.

## Scope decisions

### In scope

ROCmFPx GGML tensor IDs required by the donor format family:

```text
100 Q4_0_ROCMFP4
101 Q4_0_ROCMFP4_FAST
102 Q6_0_ROCMFPX
103 Q8_0_ROCMFPX
104 Q3_0_ROCMFPX
107 Q2_0_ROCMFPX
```

Implement:

- GGUF/GGML type registration and size/block traits;
- row-data validation;
- scalar/generic CPU fallback and CPU op eligibility;
- model ftype naming/recognition needed for clean loading/reporting;
- Vulkan dequant/get_rows/mul_mat/mul_mat_id/copy support required by existing ROCmFPx GGUFs;
- q8_1 integer-dot decode/prefill paths after the correctness baseline;
- the proven batch 3–8 correction before MTP performance evaluation.

### Deferred

Do not include in the first Vulkan compatibility series:

- ROCm/HIP kernels and ROCmFP4 HIP-specific tuning;
- ROCm FlashAttention support;
- `llama-quantize` recipes/presets unless required by a build dependency;
- GGUF conversion tooling and Python quantizer support;
- current agentionai trellis/PTQ types;
- unrelated Vulkan optimizations from agentionai;
- MTP host/scheduler optimizations;
- QSA union / VULKAN-002;
- r5 MTP PP experimental branches.

Quantization/conversion support can be added later as a separately justified utility patch. The immediate objective is inference from already-produced GGUFs.

## Implementation sequence

## Stage 0 — pre-port inventory and invariants

No behavior change.

1. Freeze the base at `b45025848`.
2. Record donor SHAs above.
3. Keep COMMON-001 source untouched except where a compile-time enum/count dependency forces otherwise.
4. Once COMMON-003 can parse the GGUF, inventory all tensor type IDs in:
   - target ROCmFP4-FAST v2-ple16 GGUF;
   - MTP ROCmFP4-FAST sidecar.
5. Confirm that no target tensor type outside 100/101/102/103/104/107 is required.
6. Preserve a loader log from the base showing the current type-101 failure.

Gate: documentation only; no inference source changes.

## Stage 1 — COMMON-003A: core ROCmFPx format and loader support

Goal: make the GGML core understand the format family independently of Vulkan.

### Add format implementation

Primary donor: current agentionai main, checked against r2.

Add the minimum standalone sources:

```text
ggml/rocmfp4/rocmfp4.c
ggml/rocmfp4/rocmfp4.h
ggml/rocmfpx/rocmfpx.c
ggml/rocmfpx/rocmfpx.h
```

Do not add the HIP `.cu/.cuh` sources in this stage. They are not needed by CPU/Vulkan and should not imply ROCm backend support.

Do not add standalone ROCmFP2 reference/test files unless a real dependency is found while compiling; the promoted `rocmfpx.c/.h` own the runtime format path.

### Core integration files

Expected integration points:

```text
ggml/include/ggml.h
ggml/src/CMakeLists.txt
ggml/src/ggml.c
ggml/src/ggml-quants.c
ggml/src/ggml-cpu/ggml-cpu.c
ggml/src/ggml-cpu/ops.cpp
include/llama.h
src/llama-model-loader.cpp
```

Required behavior:

- reserve the historical high type IDs exactly; do not renumber the GGUF format;
- raise `GGML_TYPE_COUNT` sufficiently to index type 107 while preserving holes;
- register block size, type size, dequant reference functions and quantized flag;
- add row validation;
- add CPU vec-dot/from-float traits and operation eligibility for safe fallback;
- recognize/report the ROCmFPx model ftypes instead of printing an avoidable unknown ftype.

### What not to carry from agentionai

Do not copy unrelated newer custom ftypes/types above the ROCmFPx range. r5 should remain upstream-shaped except for this family.

Do not bring x86 micro-optimizations initially. The generic CPU fallback is a correctness path, not the target performance backend.

### Stage 1 gates

1. Clean Vulkan configure/build must compile the core additions even before VULKAN-001 is added.
2. Existing non-ROCmFPx test suite must not regress.
3. The former GGUF parser error `invalid ggml type 101` must disappear.
4. A verbose `-fit off` load should advance to the expected next boundary (most likely Vulkan unsupported-type/pipeline selection) rather than fail in GGUF parsing.
5. Record the actual target/draft tensor-type inventory.

Commit boundary: **COMMON-003A only**.

## Stage 2 — VULKAN-001A: correctness-first Vulkan execution path

Goal: execute the target model correctly before importing the integer-dot performance path.

Historical donor: the Vulkan portion of `8610c8b...`, adapted from current agentionai main to r5 APIs.

Expected shader/backend files include:

```text
ggml/src/ggml-vulkan/ggml-vulkan.cpp
ggml/src/ggml-vulkan/vulkan-shaders/types.glsl
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs_cm2.glsl
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfp4.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfp4_fast.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp3.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp6.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp8.comp
ggml/src/ggml-vulkan/vulkan-shaders/mul_mm_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/copy_to_quant.comp
ggml/src/ggml-vulkan/vulkan-shaders/copy_from_quant.comp
ggml/src/ggml-vulkan/vulkan-shaders/copy_quant_same.comp
ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp
```

Exact file count is allowed to shrink if current r5 already has a generic mechanism that makes a donor hunk unnecessary. Do not mechanically replay the August patch.

Required Vulkan capabilities for the target model:

- type recognition in backend capability checks;
- dequant to f16/f32 where used;
- GET_ROWS for quantized tensors;
- dense MUL_MAT;
- MoE MUL_MAT_ID;
- same-type/copy paths needed by graph execution;
- no CPU fallback for expert weights during the normal all-layer-offloaded run.

### Stage 2 gates

Use a fresh build directory, e.g. `build-vulkan-rocmfpx-stage2a`.

Run with `-fit off` first.

1. 4k smoke load/generation with `-ngl 999 -ncmoe 0`. The Stage-1 hybrid baseline left 41765.72 MiB in the CPU model buffer; VULKAN-001A should instead place the ROCmFPx weights on Vulkan and move toward the current-AgentionAI reference of about 88645.69 MiB Vulkan model / 497.31 MiB Vulkan_Host.
2. Verify coherent output and clean exit. Exact performance parity with current AgentionAI is not expected because q8_1 MMVQ/MMQ and unrelated Qwen/indexer changes are intentionally absent.
3. Check logs for unexpected CPU model placement/fallback. Graph split count should fall materially from the Stage-1 hybrid path; exact parity with the AgentionAI graph is not required.
4. Repeat at 32k, MTP OFF, fixed sampling.
5. Repeat with 64k real input after 32k is clean.
6. Preserve PP/TG as diagnostics; do **not** make the Stage-3 performance decision from the 4k smoke test.
7. Compare generated text against r2/current-agentionai where practical. Exact byte equality is not required unless sampling is deterministic and the compared graph path is numerically equivalent.

Commit boundary: **VULKAN-001A correctness baseline**.

If this stage cannot run without the q8_1 path because current r5 backend routing assumes it, move the minimum required integer-dot plumbing into Stage 2 but keep the performance-specific optimization in Stage 3.

## Stage 3 — VULKAN-001B: q8_1 MMVQ/MMQ and batch 3–8 performance path

Goal: recover the ROCmFP4-FAST path that matters for normal decode, prefill and speculative verification.

Historical donors:

- `e282dfd6...`
- `f0a2bd6...`

Primary current-API donor: current agentionai main.

Expected additional integration points:

```text
ggml/src/ggml-vulkan/ggml-vulkan.cpp
ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vecq.comp
ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vecq_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mmq_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mmq_shmem_types.glsl
ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs.glsl
```

Key behavior:

- q8_1 activation path for ROCmFP4 and ROCmFP4_FAST;
- correct separate accumulator handling for dual-scale type 100;
- single-scale fast path for type 101;
- Q8_0_ROCMFPX support where the donor uses the same integer path;
- whole-block `K_PER_ITER=32` treatment for ROCmFP4/FAST;
- retain the fp3/fp6 four-value dequant correction from `f0a2bd6...` because mixed-type GGUFs can hit those tensors;
- preserve current r5 generic Vulkan heuristics unless the ROCmFPx-specific donor requires an explicit branch.

### Stage 3 gates

1. Focused `test-backend-ops` correctness for ROCmFPx MUL_MAT and MUL_MAT_ID shapes.
2. Force/observe both the ordinary and integer-dot paths where the test harness permits.
3. Short model output must remain coherent.
4. 64k real-input comparison against Stage 2:
   - PP;
   - TG;
   - no new CPU fallback;
   - no output corruption.
5. Exercise a small multi-column/batched shape before enabling MTP. The 3–8 column range is a mandatory gate because the historical bug was concentrated there.
6. Optional RGP only if runtime routing is ambiguous; do not profile before basic correctness.

Commit boundary: **VULKAN-001B optimized inference**.

At this point COMMON-003 + VULKAN-001 is the candidate ROCmFP4 implementation for the future integrated build.

## Stage 4 — target-model long-context compatibility gate

Still MTP OFF.

Use the same target model and input/config used by the r5 project baseline.

Sequence:

1. 64k normal run.
2. 128k only after 64k passes.
3. 256k only if the target remains stable and the time cost is justified for integration confidence.

For this compatibility branch the purpose is stability and gross-regression detection, not re-optimizing QSA.

Keep QSA union/VULKAN-002 absent so ROCmFPx attribution remains clean.

Record:

- executable SHA/build ID;
- Vulkan driver/device;
- model filename/hash if already available in the existing harness;
- PP/TG;
- peak/steady memory observations;
- unexpected warnings/fallbacks;
- response sanity.

## Stage 5 — MTP sidecar compatibility

Only start after Stage 4 has at least a clean 64k target-model result.

First attempt the existing MTP sidecar **without any MTP compatibility code**.

Use:

- target ROCmFP4 model;
- ROCmFP4 MTP sidecar;
- `--spec-type draft-mtp`;
- short context first;
- conservative draft depth matching prior known-good r2 usage.

Possible next failure:

r5 currently expects the upstream `blk.<il>.nextn.hc_head_*` MTP tensor names. Older AgentionAI MTP-only files can instead rely on `output_hc_{norm,down,up}`.

Only if the actual sidecar fails for this reason, port the current agentionai/r2 fallback:

- nextn HC head tensors optional;
- old output HC head tensors optional for MTP-only load;
- require one complete set;
- graph uses nextn head when present, otherwise old output head.

Keep this as a distinct compatibility commit, not part of ROCmFPx.

### MTP gates

1. Draft model load.
2. 32k short generation.
3. Nonzero sensible acceptance.
4. Output coherence.
5. Target/draft GPU placement.
6. 64k MTP ON/OFF.
7. Exercise verify width 3–8 so Stage 3 is tested in its intended workload.

Do not import later r5 MTP PP/TG optimizations into this branch.

## Stage 6 — integration into the later r5 optimized line

After this branch is validated, do not merge the entire investigation history blindly.

Prepare clean logical commits:

1. COMMON-003 core ROCmFPx.
2. VULKAN-001A/B ROCmFPx Vulkan.
3. MTP old-HC compatibility only if required.
4. Documentation/tests.

Then apply/cherry-pick those commits onto the selected MTP-optimized integration base.

This separates:

```text
ROCmFPx correctness
  -> ROCmFPx Vulkan performance
  -> MTP sidecar compatibility
  -> interaction with r5 MTP/QSA optimizations
```

If a regression appears only after applying to the MTP-optimized line, treat it as an interaction regression rather than reopening the core ROCmFPx implementation.

## Stop / rollback criteria

Stop a stage and diagnose before proceeding if any of the following occurs:

- a type ID is renumbered relative to the existing GGUF;
- target model requires an unplanned custom type outside the recorded family;
- Vulkan silently places major ROCmFPx expert tensors on CPU;
- short generation is incoherent while r2/current agentionai is coherent under comparable settings;
- backend tests show numeric failures;
- Stage 3 improves one-token decode but badly regresses batch 3–8;
- MTP acceptance becomes zero/implausible after a target-only build is known good.

Do not work around a failure by importing a large unrelated agentionai source block.

## Expected difficulty after source review

| Area | Estimate | Main risk |
|---|---:|---|
| Core type/loader support | low–moderate | sparse high type IDs and current CPU trait structure |
| Base Vulkan execution | moderate | adapting pipeline/shader registration to current r5 Vulkan |
| MMVQ/MMQ optimized path | moderate | current shader generator/pipeline APIs |
| Batch 3–8 correction | low after MMVQ/MMQ | ensuring the historical fix remains applicable |
| MTP old-head compatibility | low–moderate if needed | distinguishing old vs upstream tensor layouts |
| ROCm/HIP parity | high, deferred | large independent Strix-specific kernel/tuning surface |

Overall recommendation: proceed. The Vulkan-only port is bounded enough to be a practical prerequisite for the weekend integrated build, provided the stage/commit boundaries above are kept.


## Stage 2 validation checkpoint — 2026-10-20

Build `b11528-f4bd9adac` passed the VULKAN-001A correctness gates on Evo-X2.

| Context | Prompt tokens | PP | TG | Model placement | Graph splits | Result |
|---|---:|---:|---:|---|---:|---|
| 32k | 29,557 | 410.33 tok/s | 27.06 tok/s | Vulkan 88,645.69 MiB + Host 497.31 MiB | 2 | pass |
| 64k | 61,789 | 277.55 tok/s | 25.99 tok/s | Vulkan 88,645.69 MiB + Host 497.31 MiB | 2 | pass |

Both runs produced coherent summaries and completed normally. The Stage-1 ~41.8 GiB CPU model buffer did not return.

Decision: close Stage 2 and proceed to VULKAN-001B.


## Stage 3 implementation checkpoint — 2026-10-20

VULKAN-001B source commit:

```text
8205db29206c71feb86ee5322069cdc31e48c061
vulkan: add ROCmFPx integer-dot paths
```

Primary donor commits:

- `e282dfd6dfbaaaadc293bf2cb5d11108088400a2`: ROCmFPx q8_1 integer-dot MMVQ/MMQ
- `f0a2bd6b34e83b4282d62b085e2d21ef2d241864`: batch 3-8 correction

Ported scope:

- MMQ q8_1: Q4_0_ROCMFP4 and Q4_0_ROCMFP4_FAST;
- MMVQ q8_1: Q4_0_ROCMFP4, Q4_0_ROCMFP4_FAST and Q8_0_ROCMFPX;
- ROCmFP4/FAST MMVQ K_PER_ITER = 32;
- FP3/FP6 float-path dequantize4 optimization for batch 3-8;
- normal and MUL_MAT_ID q8_1 dispatch/pipeline registration;
- integer-MMQ shared-memory sizing.

FP3/FP6 remain on the float matvec path by design. See [R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-21.md](R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-21.md).


## Stage 3 validation checkpoint — 2026-10-21

Build `b11531-db0b11516` passed the VULKAN-001B model-runtime and focused numerical-correctness gates on Evo-X2.

Model runtime, MTP OFF:

| Context | Dispatch | PP | TG | Result |
|---|---|---:|---:|---|
| 32k | normal | 412.22 tok/s | 27.19 tok/s | pass |
| 32k | `GGML_VK_FORCE_MMVQ=1` | 419.32 tok/s | 27.42 tok/s | pass |
| 64k | normal | 277.21 tok/s | 26.07 tok/s | pass |
| 64k | `GGML_VK_FORCE_MMVQ=1` | 277.02 tok/s | 26.41 tok/s | pass |

All four runs retained full GPU model placement and graph splits = 2 and produced coherent output. Relative to Stage 2, normal-dispatch performance is effectively flat in PP (+0.46% at 32k, -0.12% at 64k) with a small TG increase (+0.48% / +0.31%). Forced MMVQ improves 32k PP by 2.19% and TG by 1.33%, but does not improve 64k PP; therefore forced MMVQ is **not** promoted as the default dispatch policy.

The focused correctness test commit is:

```text
fe36a4d3fcfc6d96952f65386c2ac4b1579d3d51
tests: add ROCmFPx Vulkan batch-width coverage
```

The test gate covers these five Vulkan-supported ROCmFPx formats:

- Q4_0_ROCMFP4
- Q4_0_ROCMFP4_FAST
- Q3_0_ROCMFPX
- Q6_0_ROCMFPX
- Q8_0_ROCMFPX

For both `MUL_MAT` and `MUL_MAT_ID`, widths `n = 1, 3, 4, 5, 6, 7, 8` were compared against the CPU reference under both normal dispatch and `GGML_VK_FORCE_MMVQ=1`.

| Test | Normal | Force MMVQ |
|---|---:|---:|
| MUL_MAT | 35/35 pass | 35/35 pass |
| MUL_MAT_ID | 35/35 pass | 35/35 pass |
| Total | 70/70 pass | 70/70 pass |

Overall: **140/140 pass, 0 failures**. This explicitly closes the historical batch-3-8 correctness gate before MTP.

Current AgentionAI remains about 1% faster in the long-context comparison, but it also uses a materially different Qwen/indexer/cache graph, so that residual is not treated as evidence of an incomplete ROCmFPx port.

Decision: **close Stage 3**. Preserve normal r5 Vulkan dispatch and proceed to Stage 4 with the target model, MTP OFF, starting at 128k because 64k has already passed on the Stage-3 build.


## Stage 4 validation checkpoint — 2026-10-21

The standard Evo-X2 matrix runner was used with the same real-input long-context conditions for the r5 Stage-3 Vulkan build and the current AgentionAI dedicated Vulkan fork.

Important qualification: this ROCmFPx investigation branch still had the pre-2026-10-15 measurement scripts, so P-MODE start/finish and ADLX GPU clock/temperature/power telemetry were **not recorded**. The runs are valid as compatibility/stability evidence, but the cross-build performance comparison is provisional until the updated telemetry tooling is used.

All four runs completed with status OK and coherent output.

| Context | Build | Prompt tokens | PP | TG | Result |
|---|---|---:|---:|---:|---|
| 128k | r5 Stage-3 b11531-db0b11516 | 126,253 | 181.83 tok/s | 23.38 tok/s | pass |
| 128k | current AgentionAI dedicated fork | 126,253 | 166.91 tok/s | 23.05 tok/s | pass |
| 256k | r5 Stage-3 b11531-db0b11516 | 255,181 | 126.79 tok/s | 18.63 tok/s | pass |
| 256k | current AgentionAI dedicated fork | 255,181 | 91.03 tok/s | 19.18 tok/s | pass |

Provisional Stage-3 versus AgentionAI differences:

- 128k PP: +8.94%
- 128k TG: +1.43%
- 256k PP: +39.28%
- 256k TG: -2.87%

The 256k PP gap is accompanied by a materially different memory/cache layout:

| Context | Build | Indexer KV | Pooled indexer cache | Vulkan compute buffer |
|---|---|---:|---:|---:|
| 128k | r5 Stage-3 | 768 MiB | none reported | 1,148.91 MiB |
| 128k | AgentionAI | 384 MiB | 192.01 MiB | 2,824.68 MiB |
| 256k | r5 Stage-3 | 1,536 MiB | none reported | 2,005.28 MiB |
| 256k | AgentionAI | 768 MiB | 384.01 MiB | 4,373.93 MiB |

At 256k the resource monitor observed approximately 99.9 GiB peak target GPU committed for Stage-3 versus 102.7 GiB for AgentionAI, with about 5.1 GiB versus 7.8 GiB peak target shared GPU memory. This is consistent with the AgentionAI graph using substantially more long-context working memory and crossing further into shared memory, but no causal performance attribution is made without matched P-MODE/ADLX telemetry and profiling.

Decision:

- Stage 4 compatibility/stability gate: **PASS through 256k**.
- Stage-3 ROCmFPx port remains stable at long context with full GPU model placement.
- Cross-build performance ranking: **provisional** because P-MODE/ADLX telemetry is absent from these runs.
- Before Stage 5, sync the benchmark telemetry tooling from the r5 line and use the external ADLX monitor path from local configuration; do not re-add the ADLX source/build tree to Git.


## Telemetry restore checkpoint — 2026-10-21

The ROCmFPx branch benchmark tooling was synchronized with the validated r5 P-MODE/ADLX measurement path before starting Stage 5.

A 4k target-only allocation smoke on build `b11531-db0b11516` confirmed:

- run status: `OK`;
- P-MODE start: `Performance`;
- P-MODE finish: `Performance`;
- P-MODE changed: `False`;
- ADLX monitor requested/started successfully;
- ADLX exit code: 0;
- ADLX samples: 21;
- `gpu-metrics.csv` contains GPU usage, core clock, VRAM clock, temperature, power and VRAM usage;
- no P-MODE warnings.

The P-MODE/ADLX high-load consistency classifier reports `InsufficientSamples` for this smoke because it is an allocation/short-prompt run and produced no >=95% GPU-usage samples. This is expected and is not a telemetry failure.

The external ADLX executable remains outside Git management and is selected through `local.psd1` using `AdlxMonitorExe`.

### Deferred performance follow-up

The previous Stage-4 128k/256k cross-build speed results remain useful as compatibility observations but are provisional performance data because those runs predated telemetry restoration.

Do **not** block Stage 5 on repeating them. Keep these as later investigation candidates:

1. repeat the 256k Stage-3 vs AgentionAI matched comparison with P-MODE/ADLX enabled;
2. capture RGP at 256k, where the dedicated fork showed a much larger PP slowdown and substantially larger compute/shared-memory usage.

These are performance-attribution tasks, not requirements for proving the ROCmFP4/ROCmFPx upstream port correct.

## Stage 5A execution checkpoint — 2026-10-21

Prepared:

`tools/evox2/benchmark/configs/qwen38-rocmfpx-stage5-mtp-gate.psd1`

The gate deliberately uses the existing ROCmFP4 MTP sidecar **without any old-HC compatibility patch first**.

Run sequence:

1. 4k allocation smoke with MTP ON, draft max = 2;
2. only if the 4k load succeeds, 32k real-input generation with MTP ON.

The matrix stops on the first failure. If the 4k run fails specifically because the sidecar uses the older `output_hc_{norm,down,up}` naming instead of current upstream `blk.<il>.nextn.hc_head_*`, then and only then port the bounded compatibility fallback from AgentionAI commit `93a24e52cc12687213c0432af41c7fe2ab1a0eda`.

Stage 5A acceptance criteria:

- target and draft both load;
- no major target/draft CPU fallback;
- 32k completes normally;
- output remains coherent;
- draft acceptance is nonzero and plausible;
- no ROCmFPx batch-width/numerical failure is observed.

After Stage 5A passes, prepare the Stage 5B 64k MTP OFF/ON matched gate. Do not import later r5 MTP PP/TG optimization patches into this compatibility branch.


## Stage 5A first load result — 2026-10-21

The first 4k MTP allocation smoke used the unmodified Stage-3 build `b11531-db0b11516` with:

- target: `Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf`;
- draft: `Qwen3.8-Flash-Next-MTP-ROCmFP4-FAST.gguf`;
- MTP enabled, draft max = 2;
- P-MODE/ADLX telemetry enabled and working.

The target model loaded successfully. The draft GGUF also passed ROCmFPx parsing and reported:

- GGUF V3;
- file type `Q4_0_ROCMFP4_FAST`;
- 34 tensors total;
- 19 tensors of type `q4_0_rocmfp4_fast`.

The load then failed exactly at the expected MTP layout boundary:

```text
llama_model_load: error loading model:
check_tensor_dims: tensor 'blk.48.nextn.hc_head_norm.weight' not found
```

This is not a ROCmFPx format/Vulkan failure. The draft sidecar is an older AgentionAI MTP-only layout that stores the final hyper-connection mixer under `output_hc_{norm,down,up}`, while the current upstream qwen4exp loader expects `blk.<il>.nextn.hc_head_*`.

### Stage 5A compatibility implementation

Implemented in:

```text
9fa9970b19c1c4aba87934686c9b74f3b2f32ecf
qwen4exp: support old MTP HC head layout
```

The current r5 base already contains:

- `LLM_TENSOR_NEXTN_HC_HEAD_{NORM,DOWN,UP}`;
- tensor-name mappings;
- tensor infos;
- `llama_layer_nextn::hc_head_*` fields.

Therefore the compatibility patch is intentionally limited to `src/models/qwen4exp.cpp`:

1. current `blk.<il>.nextn.hc_head_*` tensors become optional at MTP load;
2. require either a complete current nextn set or a complete old `output_hc_*` set;
3. reject a partial current set explicitly;
4. graph construction prefers the current nextn set and falls back to `model.hc_head_*` only when the current set is absent.

No ROCmFPx GGML/Vulkan code is changed by this patch.

This is adapted from AgentionAI compatibility commit:

`93a24e52cc12687213c0432af41c7fe2ab1a0eda`

but only the runtime qwen4exp compatibility logic is needed on this r5 base; converter/tensor-enum additions from that historical commit are already present upstream.

### Re-test

Use a separate Stage-5 build so the validated Stage-3 binary remains intact.

The Stage-5 plan now expects build key:

`R5RocmFpxStage5Vulkan`

and retains the sequence:

1. 4k allocation smoke, MTP ON;
2. stop on error;
3. 32k real-input MTP run only after the 4k gate passes.

Acceptance remains target/draft load, GPU placement, coherent output and nonzero/plausible draft acceptance. Performance is not a gate here.


## Stage 5A second smoke result — 2026-10-21

Build `b11558-05b288018` included the old-HC compatibility path and progressed materially further than the first Stage-5 smoke.

Observed sequence:

1. target ROCmFP4-FAST model loaded;
2. draft ROCmFP4-FAST sidecar loaded;
3. old `output_hc_*` fallback successfully bypassed the previous
   `blk.48.nextn.hc_head_norm.weight not found` failure;
4. draft model offloaded 50/50 layers to Vulkan;
5. draft context allocated attention KV and indexer KV;
6. draft graph scheduler reserve completed;
7. speculative implementation `draft-mtp` was registered;
8. a subsequent reserve completed;
9. process aborted at:
   ```text
   ggml/src/ggml-backend.cpp:345: GGML_ASSERT(buffer) failed
   ```

The assertion is `ggml_backend_buffer_get_type(nullptr)`, not a GGUF/tensor-type parser failure.

This matches the previously isolated r5 dense-MTP compatibility defect from commit `f8d24494`: the MTP layer has `dsv4_compress_ratios[il] == 0` (dense attention), but the graph registers a k-pool input solely because the indexer cache and global k-pool feature exist. The dense MTP graph never consumes that input, so no backend buffer is assigned and the input setter later reaches a null buffer.

### Stage 5A dense-MTP compatibility implementation

Implemented in:

```text
a09d40719f6d0af159216357708f376ff51170ea
qwen4exp: skip k-pool input for dense MTP
```

Change scope is one MTP-graph condition in `src/models/qwen4exp.cpp`:

```cpp
if (mctx_hyb->get_idx() &&
    hparams.indexer_kpool > 0 &&
    hparams.dsv4_compress_ratios[il] > 0) {
    ...
    inp_kpool = build_inp_kpool(mctx_hyb);
}
```

Positive-ratio MTP/QSA behavior is unchanged. Target/trunk QSA is unchanged. Draft indexer KV allocation may still appear; this patch only avoids registering the unused k-pool graph input for the ratio-zero dense MTP block.

This is a compatibility fix already validated independently on the r5 line and is not a ROCmFPx performance optimization.

Rebuild the dedicated Stage-5 Vulkan directory and repeat the same matrix. The expected causality gate is disappearance of the `ggml-backend.cpp:345` assertion and successful token generation/draft acceptance at 4k before the automatic 32k run.


## Stage 5A validation result — 2026-10-21

Dedicated Stage-5 Vulkan build:

```text
b11561-bddcbf2f1
```

includes both compatibility fixes required by the existing AgentionAI ROCmFP4 MTP sidecar:

1. `9fa9970b1` — old `output_hc_*` final-mixer fallback;
2. `a09d40719` — skip unused k-pool graph input for ratio-zero dense MTP.

The 4k gate passed and the matrix proceeded to the 32k real-input run.

32k result:

| Item | Result |
|---|---:|
| Status | OK / exit 0 |
| Context | 32,768 |
| Prompt tokens | 29,557 |
| PP | 384.28 tok/s |
| Generated tokens | 626 |
| TG | 36.42 tok/s |
| Draft generated | 528 |
| Draft accepted | 361 |
| Draft acceptance | **68.371%** |
| Mean accepted length | 2.37 |
| Target GPU layers | 49/49 |
| Draft GPU layers | 50/50 |
| P-MODE start/finish | Performance / Performance |
| P-MODE changed | false |
| ADLX high-load power | 119.829 W |
| ADLX power class | Performance-like |
| P-MODE/ADLX consistency | true |

Speculative statistics:

```text
draft-mtp: #calls(b,g,a) = 1 264 264
#gen drafts = 264
#acc drafts = 210
#gen tokens = 528
#acc tokens = 361
#mean acc len = 2.37
#acc rate/pos = (0.795, 0.572)
```

The generated Japanese summary is coherent and relevant to the input document. There are no ROCmFPx type, Vulkan pipeline, HC-layout or null-buffer failures.

Decision: **Stage 5A PASS**.

This is the key integration result: the upstream-based r5 branch can now run the existing ROCmFP4-FAST target GGUF together with the existing ROCmFP4-FAST MTP sidecar through real 32k generation.

### Stage 5B

Prepared:

`tools/evox2/benchmark/configs/qwen38-rocmfpx-stage5b-mtp-64k.psd1`

It runs one matched 64k pair on the same Stage-5 build:

1. MTP OFF;
2. MTP ON with the same sidecar, `DraftMax=2`, `DraftPMin=0`.

Stage 5B remains a compatibility gate. Record completion, coherent output, draft acceptance, GPU placement and telemetry. PP/TG are diagnostic only.

After 64k passes, use a small bounded DraftMax expansion test to exercise wider speculative verification in a real MTP graph. The Stage-3 backend tests have already validated ROCmFPx MUL_MAT/MUL_MAT_ID widths 3-8 numerically, so this final real-workload check need not be a long-context performance run.
