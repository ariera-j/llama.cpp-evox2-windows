# r5 COMMON-003A ROCmFPx core implementation — 2026-10-20

## Status

**SOURCE IMPLEMENTED. WINDOWS BUILD AND TARGET-MODEL VALIDATION PENDING.**

| Item | Identity |
|---|---|
| Branch | `investigation/r5-rocmfpx-vulkan-20261020` |
| Fixed base | `b45025848b97fc8fd3efa7333305567bc897f61f` |
| COMMON-003A source commit | `85ab8d797f176c322f77647e27ebea3ee5d29931` |
| Commit title | `ggml: add ROCmFPx core format support` |
| Target model | `Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf` |
| Vulkan kernels | **not implemented yet**; Stage 2 / VULKAN-001A |
| ROCm/HIP kernels | out of scope |

The pre-port b11521 failure was:

```text
tensor 'output_hc_down.weight' has invalid ggml type 101. should be in [0, 43)
```

COMMON-003A raises the GGML type domain to include the published ROCmFPx high IDs and implements the common/CPU substrate required to parse and safely fall back on these tensors.

## Implemented tensor IDs

```text
100 GGML_TYPE_Q4_0_ROCMFP4
101 GGML_TYPE_Q4_0_ROCMFP4_FAST
102 GGML_TYPE_Q6_0_ROCMFPX
103 GGML_TYPE_Q8_0_ROCMFPX
104 GGML_TYPE_Q3_0_ROCMFPX
107 GGML_TYPE_Q2_0_ROCMFPX
GGML_TYPE_COUNT = 108
```

The sparse/high numbering is deliberate. It preserves the tensor IDs serialized in existing AgentionAI/r2 GGUF files.

## Added format sources

```text
ggml/rocmfp4/rocmfp4.c
ggml/rocmfp4/rocmfp4.h
ggml/rocmfpx/rocmfpx.c
ggml/rocmfpx/rocmfpx.h
```

The ROCmFP4 source/header and ROCmFPx header were verified byte-identical between the retained r2 source and current AgentionAI during the port review. The ROCmFPx C implementation uses the current AgentionAI version; its public runtime layout/API remains compatible with the retained r2 header, while including later reference-quantizer corrections.

No HIP/CUDA sources are added.

## Modified common/CPU integration

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

### Core GGML traits

Each ROCmFPx type now has:

- block size;
- type size;
- quantized flag;
- reference dequantization;
- reference from-float function;
- row-data validation.

The generic `ggml_quantize_chunk()` dispatch is also wired to the format implementations. This is core format completeness; it does **not** add llama-quantize recipes/presets or converter tooling.

### CPU fallback

The CPU backend includes:

- ROCmFP4/FAST vec-dot against Q8_0;
- scalar FP2/FP3/FP6/FP8 vec-dot against Q8_0;
- from-float traits;
- quantized-op eligibility in the same seven generic CPU switch groups that current AgentionAI enables.

This is primarily a correctness/fallback substrate. No CPU SIMD optimization was ported.

### Model file type reporting

The published ROCmFP4 recipe IDs are recognized in `llama_ftype`, including FAST/STRIX variants, plus Q3/Q6/Q8/Q2 ROCmFPx file types. The loader can also infer a ROCmFPx ftype from the dominant tensor type.

The target FAST model should therefore report a meaningful ROCmFP4 file type instead of `unknown, may not work`.

## Deliberately not implemented

COMMON-003A contains **no**:

- Vulkan ROCmFPx shader or pipeline;
- ROCm/HIP kernel;
- ROCmFPx KV-cache CLI selection;
- `llama-quantize` ROCmFPx recipe policy;
- Python converter/gguf-py additions;
- current AgentionAI PTQ/trellis types;
- MTP old-HC tensor-name compatibility;
- VULKAN-002/QSA-union or later r5 MTP optimization.

That separation is intentional so a target-model failure can still be attributed to common format support versus the later Vulkan port.

## Static review

The implementation was compared against both the retained r2 behavior and current AgentionAI integration.

Static checks performed before commit:

- type 101 is registered and `GGML_TYPE_COUNT` covers type 107;
- all six format types have core type traits;
- all six have row validation;
- all six have CPU type traits;
- the seven current r5 generic quantized CPU-op switch groups include the ROCmFPx family;
- model-loader ftype names and guessed-type mappings are present;
- CMake includes only the four standalone C/H format files, not HIP sources.

An attempted local Linux CPU build could not be run because the execution container cannot resolve external GitHub hosts. Windows build validation therefore remains a real gate, not an inferred pass.

## Windows validation sequence

Use a fresh build directory. From the r5 repository checkout:

```powershell
git fetch origin
git switch investigation/r5-rocmfpx-vulkan-20261020
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-rocmfpx-stage1\ `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

First gate: the clean build must succeed without any Vulkan ROCmFPx implementation. COMMON-003A is common/CPU code and should compile into the Vulkan build.

### Gate A — CPU-only target-model load / minimal execution

Use the new executable and disable the fit probe so the old failure is not printed twice.

```powershell
$exe = '.\build-vulkan-rocmfpx-stage1\bin\llama-cli.exe'
$model = 'C:\llama\models\agentionai\Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf'

& $exe `
    -m $model `
    -fit off `
    -ngl 0 `
    -c 4096 `
    -n 1 `
    -t 4 `
    -b 512 `
    -ub 512 `
    -p 'Say hello in one short sentence.' `
    --temp 0
```

Pass criteria:

1. there is no `invalid ggml type 101` error;
2. metadata/tensor enumeration completes;
3. the model can allocate on CPU;
4. one-token compute does not fail in a missing ROCmFPx CPU trait/op.

The purpose is correctness only; CPU speed is irrelevant.

If a later tensor type fails, retain the exact ID/name. It will update the format inventory before Stage 2.

### Gate B — Vulkan boundary probe

Then probe the same model with GPU offload:

```powershell
& $exe `
    -m $model `
    -fit off `
    -ngl 999 `
    -c 4096 `
    -n 1 `
    -t 4 `
    -b 512 `
    -ub 512 `
    -p 'Say hello in one short sentence.' `
    --temp 0
```

At this stage a Vulkan unsupported-type/pipeline error or CPU fallback is acceptable and useful: VULKAN-001A has not been implemented.

The important Stage-1 observation is that the loader has crossed the former type-101 boundary. Preserve enough of the log to identify:

- all reported ROCmFPx tensor type counts;
- the reported file type;
- first Vulkan-specific failure/fallback, if any.

Do not run 64k yet if Gate B is clearly blocked by the missing Vulkan implementation.

## Decision after validation

- **Build fails:** fix COMMON-003A before starting Vulkan.
- **CPU Gate A fails:** treat as missing common/CPU substrate; do not start Vulkan.
- **Gate A passes and Gate B stops at Vulkan support:** COMMON-003A is complete; proceed to VULKAN-001A.
- **Gate B unexpectedly runs by CPU fallback:** still proceed to VULKAN-001A; confirm that ROCmFPx weights are actually offloaded rather than judging speed from a hybrid path.

The next source implementation after these gates is Stage 2 / VULKAN-001A correctness-first Vulkan dequant/GET_ROWS/MUL_MAT/MUL_MAT_ID support.
