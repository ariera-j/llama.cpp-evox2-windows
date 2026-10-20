# r5 VULKAN-001A ROCmFPx correctness implementation — 2026-10-20

## Status

**SOURCE IMPLEMENTED. WINDOWS BUILD/RUNTIME VALIDATION PENDING.**

| Item | Identity |
|---|---|
| Branch | `investigation/r5-rocmfpx-vulkan-20261020` |
| Fixed base | `b45025848b97fc8fd3efa7333305567bc897f61f` |
| COMMON-003A | `85ab8d797f176c322f77647e27ebea3ee5d29931` |
| VULKAN-001A source | `202f498877d03aa2c31b7d455b64c5452a4545b8` |
| Commit title | `vulkan: add ROCmFPx correctness kernels` |
| Primary historical donor | AgentionAI `8610c8b36284dbed5f02aa9a429251ecbfa9510d` |
| Current API reference | AgentionAI `dc255f2a4b6e4211b555b0c05260b2523281f314` |
| VULKAN-001B q8_1/MMQ/MMVQ | deliberately not included |

The implementation is a correctness-first Vulkan port. It is intended to remove the large Stage-1 CPU fallback before importing the later integer-dot performance path.

## Pre-port runtime boundary

The COMMON-003A Windows build b11526 could parse and run the target model, but with `-ngl 999 -ncmoe 0` the model placement was hybrid:

```text
CPU model buffer size     = 41765.72 MiB
Vulkan0 model buffer size = 46879.97 MiB
Vulkan_Host model buffer  =   497.31 MiB
```

The same target model on current AgentionAI used:

```text
Vulkan0 model buffer size = 88645.69 MiB
Vulkan_Host model buffer  =   497.31 MiB
```

The target GGUF contains the following ROCmFPx Vulkan-relevant tensors:

```text
q4_0_rocmfp4_fast: 50 tensors   # type 101
q3_0_rocmfpx:      16 tensors   # type 104
```

The full family is registered so other compatible ROCmFPx GGUFs do not require another backend-format patch.

## Source scope

VULKAN-001A changes 15 Vulkan/common files.

Added shaders:

```text
ggml/src/ggml-vulkan/vulkan-shaders/copy_quant_same.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfp4.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfp4_fast.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp3.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp6.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_rocmfpx_fp8.comp
```

Integrated files:

```text
ggml/src/ggml-common.h
ggml/src/ggml-vulkan/ggml-vulkan.cpp
ggml/src/ggml-vulkan/vulkan-shaders/copy_from_quant.comp
ggml/src/ggml-vulkan/vulkan-shaders/copy_to_quant.comp
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/dequant_funcs_cm2.glsl
ggml/src/ggml-vulkan/vulkan-shaders/mul_mm_funcs.glsl
ggml/src/ggml-vulkan/vulkan-shaders/types.glsl
ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp
```

Implemented Vulkan capabilities:

- ROCmFP4/FAST and FP3/FP6/FP8 ROCmFPx shader data layouts and UE4M3/codebook decode;
- dequant pipelines;
- GET_ROWS and f32 GET_ROWS;
- ordinary f16/f32 MUL_MAT and MUL_MAT_ID paths;
- f32-to-quant, quant-to-f32, same-quant and SET_ROWS copy paths;
- backend capability/dispatch recognition;
- shared-memory accounting required by the LUT-style matmul paths.

Q2_0_ROCMFPX remains a core/CPU format from COMMON-003A but is not part of the original Vulkan donor and is not required by the current target GGUF.

## Adaptation to current r5

The August donor used many explicit per-type mul_mm registrations. Current r5 has already refactored these paths into generic type-list expansion.

VULKAN-001A therefore does **not** replay those old registrations mechanically. Instead the five Vulkan ROCmFPx types are added to `FOR_EACH_LUT_TYPE_NONFP4`, so the current r5 scalar/coopmat pipeline machinery expands the normal f16/f32 MUL_MAT and MUL_MAT_ID variants.

The shader generator similarly classifies ROCmFPx as LUT-style per-type shaders. This keeps the port aligned with current r5 APIs while preserving the donor decode behavior.

## Explicit Stage-3 boundary

VULKAN-001A intentionally does not generate or dispatch ROCmFPx q8_1 integer-dot kernels.

The generator contains an explicit guard:

```cpp
if (btype == "q8_1" && is_rocmfpx_quant(tname)) {
    continue;
}
```

Therefore the following remain VULKAN-001B work:

- q8_1 activation MMVQ;
- integer-dot MMQ/MUL_MAT_ID;
- ROCmFP4/FAST whole-block integer decode;
- the historical batch 3–8 fix from `f0a2bd6...`.

This boundary is deliberate: 001A should first prove correct full-GPU placement and coherent output.

## Static checks completed before commit

- all five original Vulkan donor types are present in current r5 pipeline registration;
- shader generation includes ROCmFP4, FAST, FP3, FP6 and FP8;
- dequant/GET_ROWS/copy pipeline registrations are present;
- backend MUL_MAT/MUL_MAT_ID and GET_ROWS capability switches accept ROCmFPx;
- no ROCmFPx `GGML_TYPE_Q8_1` registration was introduced into `ggml-vulkan.cpp`;
- the generator explicitly suppresses ROCmFPx q8_1 shader arrays;
- source commit was re-read from GitHub after push.

No Windows build is claimed yet.

## Windows validation

Use a fresh build directory:

```powershell
git fetch origin
git switch investigation/r5-rocmfpx-vulkan-20261020
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-rocmfpx-stage2a\ `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

### Gate A — 4k all-GPU smoke

```powershell
$exe = '.\build-vulkan-rocmfpx-stage2a\bin\llama-cli.exe'
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

Primary pass criteria:

1. build/shader generation succeeds;
2. no ROCmFPx unsupported-type error;
3. the ~41765.72 MiB Stage-1 CPU model buffer disappears or is reduced to only explainable non-model host allocation;
4. Vulkan model allocation moves toward the current-AgentionAI reference of ~88645.69 MiB;
5. short output is coherent and exits cleanly;
6. graph splitting is materially reduced from the Stage-1 hybrid path.

Do not require exact graph or speed parity with current AgentionAI. That fork also contains unrelated Qwen/indexer changes and the later ROCmFPx integer-dot path.

### Gate B — 32k and 64k

If Gate A passes:

1. repeat MTP OFF at 32k;
2. verify model placement remains all/mostly Vulkan;
3. run the established 64k real input;
4. record PP/TG, response sanity and memory placement.

Performance is diagnostic at this stage. VULKAN-001B is the performance port.

## CPU-only reference limitation

Both COMMON-003A and current AgentionAI reproduce the same Windows CPU-only termination with `-ngl 0 --no-warmup`:

```text
$LASTEXITCODE = -1073740791
```

The exit occurs after threadpool initialization. This is not treated as a VULKAN-001A blocker because it is reproducible in the maintained donor fork and the project target is Evo-X2 Vulkan execution.

## Next decision

- build failure: fix VULKAN-001A source/shader adaptation before runtime testing;
- 4k coherent but major CPU model buffer remains: inspect backend capability/routing before Stage 3;
- 4k full-GPU placement succeeds: advance to 32k/64k correctness, then VULKAN-001B;
- only after VULKAN-001A/B target-model stability should the MTP ROCmFP4 sidecar compatibility gate begin.
