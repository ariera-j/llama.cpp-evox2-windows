# v1.0.0 gfx1151 Dense GEMM dispatch probe (2026-11-15)

## Purpose

Identify the actual backend route for each **ordinary Dense GGML_OP_MUL_MAT** in the old Unsloth Qwen3.8 Flash Next UD-IQ3_XXS model on Windows ROCm/gfx1151. This is a **host-only diagnostic**, not a GEMM optimization or a timing profiler. It is isolated from the MoE investigation branch and leaves the old `build-rocm-strata-v1` and `build-rocm-strata-moe` directories unchanged.

- Source baseline: `investigation/strata-pp-v1.0.0-20261115` at commit `934a6574780035863ffa1903d3449f3505ac1f93`.
- Branch: `investigation/v1-strata-dense-gemm-20261115`.
- Working tree: `C:\llama-build\llama.cpp-evox2-v1-strata-pp` (same physical directory).
- Build directory: `build-rocm-strata-gemm` (separate).
- Target operation: Dense `MUL_MAT`, not `MUL_MAT_ID`/MoE. For fused graph paths that bypass ordinary `ggml_cuda_mul_mat()`, this probe is intentionally not exhaustive; use a later graph-level trace if needed.

## Design

`GGML_HIP_GEMM_TRACE=1` enables the diagnostic for newly started processes. Unset or `0` does not emit records. The following optional environment variables are read once per process:

| Variable | Meaning | Default |
| --- | --- | --- |
| `GGML_HIP_GEMM_TRACE_LAYER` | filter `blk.N.` tensor names by layer | all layers |
| `GGML_HIP_GEMM_TRACE_N` | filter `src1->ne[1]` matrix columns / physical microbatch | all N |
| `GGML_HIP_GEMM_TRACE_LIMIT` | maximum matching lines, 1 to 100000 | 2048 |

The header is HIP-only, no HIP/CUDA kernel launch, device sync, or readback. Logging to stderr can still affect PP throughput; **do not compare trace-ON performance**.

At each existing dispatch branch in `ggml_cuda_mul_mat()`, record the selected `path`: `fwht`, `mmvf`, `mmvf_transposed`, `mmf`, `mmvq`, `mmq_few`, `mmq`, `fp8` or `blas`. The `blas` record is emitted from `ggml_cuda_mul_mat_cublas()` **after** choosing the data/compute-type override (e.g., `GGML_CUDA_CUBLAS_COMPUTE_TYPE`); it is not a claim that a particular hipBLASLt solution was used.

Each `evox2_dense_gemm_v1` line has `seq`, `device`, `layer`, `path`, `weight_type`, `activation_type`, `dst_type`, `compute_type`, `K`, `M`, `N`, batch dimensions `w2/w3/a2/a3`, tensor names `weight/activation/dst`. `K/M/N` are `src0.ne[0]` / `src0.ne[1]` / `src1.ne[1]`; values describe the logical operation, not the inner BLAS tile. `compute_type=-` on non-BLAS paths. The BLAS `compute_type` is the selected input datatype for the template (`f16`, `bf16`, or `f32`), not necessarily the accumulator or temporary-output precision.

Layer IDs are extracted from `blk.N.` in weight, output, then activation names. If the name has no such prefix, `layer=-1`; a layer filter drops it. The trace uses names rather than buffer contents or GPU readback.

## First verification

**No GPU build or real-model validation has been performed on this new source.** Start with a local source test, then build, then one 64k code dispatch run.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git status --short
git fetch origin
git switch --track -c investigation/v1-strata-dense-gemm-20261115 origin/investigation/v1-strata-dense-gemm-20261115

python -m unittest discover -s .\tools\evox2\tests -p 'test_v1_strata_dense_gemm_trace.py' -v

.\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-strata-gemm `
    -AmdGpuTarget gfx1151 `
    -Parallel 4 `
    -DependencyCacheRoot 'C:\llama-build\evox2-deps'
```

Add the following to the `Builds` map in the **untracked** `tools/evox2/local.psd1`, following its existing entries:

```powershell
V1StrataGemm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-v1-strata-pp\build-rocm-strata-gemm\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Then run a **single 64k code diagnostic run**, same original 3-shard GGUF, frozen code input, context 65536, batch 2048, ubatch 1024, KV=f16, MTP OFF, generation 8. Reuse the previously successful `Measure-LlamaCli.ps1` command with `-BuildKey V1StrataGemm`. Set the variables before that run:

```powershell
$env:GGML_HIP_GEMM_TRACE = '1'
$env:GGML_HIP_GEMM_TRACE_LAYER = '19'
$env:GGML_HIP_GEMM_TRACE_N = '1024'
$env:GGML_HIP_GEMM_TRACE_LIMIT = '2048'
```

Review stderr, and summarize:

```powershell
python .\tools\evox2\benchmark\summarize-dense-gemm.py 'C:\path\to\stderr.log' --layer 19 --n 1024 --strict
```

Exit and clear all four variables:

```powershell
Remove-Item Env:\GGML_HIP_GEMM_TRACE, Env:\GGML_HIP_GEMM_TRACE_LAYER, Env:\GGML_HIP_GEMM_TRACE_N, Env:\GGML_HIP_GEMM_TRACE_LIMIT -ErrorAction SilentlyContinue
```

The `Measure-LlamaCli.ps1` scripts already capture all `GGML_*` environment variables into run conditions. Do not interpret counts as GPU duration. If no matching lines appear, first inspect the full stderr and look for unfiltered layers/N and graph-fused routes before concluding that Dense GEMMs did not run.

## What to decide from the output

1. Map each weight name and quant type to `K/M/N` and selected path. Confirm whether `Q6_K` goes to BLAS and `Q8_0` to MMQ for these shapes.
2. Count group calls per path/shape and determine if those paths correspond to the major PP work, **without** interpreting frequency as elapsed GPU time.
3. If an important Dense projection is in BLAS, isolate that exact shape for a standalone MMQ vs BLAS or Strata-style WMMA experiment. Validate output before performance tuning.
4. Keep MoE fusion at its completed status (64k small speedup, 128k small speedup, matching output), and do not merge the branches until independent gains are established.
