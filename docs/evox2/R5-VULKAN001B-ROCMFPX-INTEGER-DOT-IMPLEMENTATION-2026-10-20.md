# r5 VULKAN-001B ROCmFPx integer-dot implementation — 2026-10-20

## Status

**SOURCE IMPLEMENTED. WINDOWS BUILD/RUNTIME VALIDATION PENDING.**

| Item | Identity |
|---|---|
| Branch | `investigation/r5-rocmfpx-vulkan-20261020` |
| VULKAN-001A validated baseline | `3a8be43e2849bf8f5e72afcec2ca52f322ce07a0` |
| VULKAN-001B source | `8205db29206c71feb86ee5322069cdc31e48c061` |
| Commit title | `vulkan: add ROCmFPx integer-dot paths` |
| integer-dot donor | AgentionAI `e282dfd6dfbaaaadc293bf2cb5d11108088400a2` |
| batch 3-8 donor | AgentionAI `f0a2bd6b34e83b4282d62b085e2d21ef2d241864` |

VULKAN-001B is layered directly on the validated 001A correctness baseline. No MTP/QSA experiment is mixed into this commit.

## Implemented paths

### q8_1 MMQ

Enabled for:

- `Q4_0_ROCMFP4`
- `Q4_0_ROCMFP4_FAST`

The activation side is q8_1 and the packed FP4 codebook values are decoded to int8 for integer dot products. The dual-scale non-FAST format keeps separate accumulators for the lower and upper 16 weights; FAST uses one scale.

Normal MUL_MAT and both MUL_MAT_ID registrations are included.

### q8_1 MMVQ

Enabled for:

- `Q4_0_ROCMFP4`
- `Q4_0_ROCMFP4_FAST`
- `Q8_0_ROCMFPX`

The normal and MUL_MAT_ID matvec pipelines are registered and selected by the existing q8_1 dispatch path.

### Batch 3-8 correction

The donor fix is included in the same source commit because speculative verification commonly uses batches 3-8.

ROCmFP4/FAST MMVQ now uses:

```text
K_PER_ITER = 32
```

so one invocation consumes a complete 32-weight block and decodes the UE4M3 scale only once per block.

FP3 and FP6 stay on the float path, but their `dequantize4` implementations are optimized:

- FP3 gathers four 3-bit codes from the aligned 12-bit window without the third-byte branch and shares one half-block scale;
- FP6 gathers four 6-bit codes from exactly three bytes and shares one half-block scale.

This matters for mixed ROCmFPx GGUFs even when the principal expert weights are ROCmFP4.

## Files changed

```text
ggml/src/ggml-vulkan/ggml-vulkan.cpp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vecq.comp
ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vecq_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mmq_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mmq_shmem_types.glsl
ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp
```

Current-r5 adaptations were necessary in `ggml-vulkan.cpp` and the shader generator because upstream has refactored the old donor's explicit pipeline layout. The port follows the current r5 registration structure rather than replaying the old patch mechanically.

## Deliberately not included

- FP3/FP6 integer-dot MMVQ;
- ROCmFPx HIP kernels;
- MTP old-HC tensor-name fallback;
- MTP optimization branches;
- QSA changes;
- unrelated current-AgentionAI Qwen/indexer changes.

## Static validation completed

The pushed source was re-read from GitHub and checked for:

- q8_1 MMQ shader generation for ROCmFP4 and FAST;
- q8_1 MMVQ shader generation for ROCmFP4, FAST and FP8;
- normal/ID q8_1 Vulkan pipeline registration;
- q8_1 dispatch acceptance for the three MMVQ types;
- ROCmFP4/FAST integer-MMQ shared-memory accounting;
- `K_PER_ITER=32` and full eight-dword B-cache load for ROCmFP4 MMVQ;
- whole-block four-way ROCmFP4 dot accumulation;
- FP3 shared-scale/aligned-window dequant4;
- FP6 three-byte dequant4.

No Windows build is claimed yet.

## Windows build

Use a fresh build directory:

```powershell
git fetch origin
git switch investigation/r5-rocmfpx-vulkan-20261020
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-rocmfpx-stage3\ `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

A shader-generation/compiler failure is a VULKAN-001B source failure and should be fixed before runtime testing.

## Runtime gates

Use the same target model and inputs as VULKAN-001A.

### Gate A — normal 4k smoke

```powershell
$exe = '.\build-vulkan-rocmfpx-stage3\bin\release\llama-cli.exe'
$model = 'C:\llama\models\agentionai\Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf'

& $exe `
    -m $model `
    -fit off `
    -ngl 999 `
    -ncmoe 0 `
    -c 4096 `
    -n 32 `
    -t 4 `
    -b 512 `
    -ub 512 `
    -p 'Say hello in one short sentence.' `
    --temp 0 `
    --reasoning off `
    -lv 4
```

Pass criteria: full-GPU model placement remains unchanged, graph splits remain low, output is coherent, no q8_1 shader/pipeline error.

### Gate B — force MMVQ smoke

The existing Vulkan backend supports `GGML_VK_FORCE_MMVQ`. Use it for one short run to prove the newly added q8_1 matvec path is executable rather than merely compiled.

```powershell
$env:GGML_VK_FORCE_MMVQ = '1'

& $exe `
    -m $model `
    -fit off `
    -ngl 999 `
    -ncmoe 0 `
    -c 4096 `
    -n 32 `
    -t 4 `
    -b 512 `
    -ub 512 `
    -p 'Say hello in one short sentence.' `
    --temp 0 `
    --reasoning off `
    -lv 4

Remove-Item Env:GGML_VK_FORCE_MMVQ
```

A coherent clean exit is sufficient. Do not use this forced run as a performance number.

### Gate C — 32k/64k comparison

Repeat the exact 001A real inputs:

- 32k: `nlp-survey-ch3-d3-b1.txt`
- 64k: `nlp-survey-ch3-d7-b1.txt`

Baseline:

| Context | Prompt tokens | VULKAN-001A PP | VULKAN-001A TG |
|---|---:|---:|---:|
| 32k | 29,557 | 410.33 tok/s | 27.06 tok/s |
| 64k | 61,789 | 277.55 tok/s | 25.99 tok/s |

Keep the same `-b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0` and sampling settings.

The user's current-AgentionAI 32k/64k runs are the external reference. Compare them separately from 001A -> 001B so unrelated fork differences do not get attributed to the integer-dot port.

## Interpretation

The expected benefit is more likely in decode and especially speculative verification batch 3-8 than in large prefill. The original donor reports MMQ as roughly neutral on Radeon 8060S because coopmat can already win there.

Therefore:

- no PP increase is not a failure;
- modest single-token TG change is not a failure;
- the important future gate is MTP/speculative batch 3-8 after base-model correctness is confirmed;
- a regression in ordinary 32k/64k correctness or model placement is a failure.

After VULKAN-001B passes, proceed to the MTP sidecar compatibility gate and add the old `output_hc_*` fallback only if the sidecar actually requires it.
