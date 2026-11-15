# Q6_K Dense BLAS vs MMQ shape experiment (gfx1151)

## Status

Implemented on `investigation/v1-strata-dense-gemm-20261115`. **Not yet built or GPU-verified with ROCm.** The default dispatch and the existing Dense diagnostic remain unchanged unless the experiment variable is set.

## Switch and safety scope

`GGML_HIP_Q6K_DENSE_ROUTE` is read once per process:

| Value | Result |
| --- | --- |
| Unset, `auto`, `0`, anything else | Original dispatch |
| `blas` | Force existing `ggml_cuda_mul_mat_cublas` |
| `mmq` | Force existing `ggml_cuda_mul_mat_q` if shared memory is at least 48 KiB |

The override is HIP-only, gfx1151 only, GGML_TYPE_Q6_K weights + F32 activations/output only, contiguous unbatched tensors (no views), and **exactly** two weight shapes at N=256,512,1024:

- Attention Q: `K=2560, M=12288`
- Attention Output: `K=6144, M=2560`

All other operations, including MoE, use unmodified dispatch. At N=256 original dispatch usually chooses MMQ; for N=512/1024 it normally chooses BLAS. The override **does not** force an entire backend or change the matrix arithmetic. BLAS uses the existing quantized-weight conversion + F16 GEMM path, MMQ uses Q6_K native quantized MMQ and Q8_1 activations. Their numerical results need not be bit-identical.

## Build

Keep the prior clean v1 and MoE builds intact. Update the branch in the existing working tree, then rebuild the separate GEMM directory:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_v1_strata_q6k_dense_route.py' -v
if ($LASTEXITCODE -ne 0) { throw "Static test failed" }

.\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-strata-gemm `
    -AmdGpuTarget gfx1151 `
    -Parallel 4 `
    -DependencyCacheRoot 'C:\llama-build\evox2-deps' `
    -ExtraTargets @('test-backend-ops')
```

## Validation, then direct operator timing

The new `Q6K_DENSE_ROUTE` test cases reuse the existing `test_mul_mat` graph and its CPU reference check, with a **weights buffer** and 2 shapes x 3 N values. Each test has its own `m`, `n`, `k` parameters, so `-p` filters the cases.

**First, one N=256 shape with BLAS forced, then MMQ forced.** Test mode can be CPU-expensive for larger N; leave the N=512/1024 correctness tests until the initial case passes.

```powershell
$exe = '.\build-rocm-strata-gemm\bin\Release\test-backend-ops.exe'
try {
    foreach ($route in @('blas', 'mmq')) {
        $env:GGML_HIP_Q6K_DENSE_ROUTE = $route
        & $exe test -b ROCm0 -o Q6K_DENSE_ROUTE -p 'm=12288,n=256,k=2560'
        if ($LASTEXITCODE -ne 0) { throw "Correctness failed: $route" }
    }
}
finally {
    Remove-Item Env:\GGML_HIP_Q6K_DENSE_ROUTE -ErrorAction SilentlyContinue
}
```

**Then isolated per-operator perf**. The existing backend perf test warms up once and reports average per `GGML_OP_MUL_MAT` elapsed wall time in microseconds; it includes runtime conversion, temporary buffers and backend dispatch, not only the GPU kernel. It is *not* a GPU-event-only timing. Use several passes with reversed order before drawing a conclusion.

```powershell
$exe = '.\build-rocm-strata-gemm\bin\Release\test-backend-ops.exe'
$shapes = @(
    @{ m=12288; k=2560 },
    @{ m=2560; k=6144 }
)
try {
    foreach ($route in @('blas','mmq','mmq','blas')) {
        $env:GGML_HIP_Q6K_DENSE_ROUTE = $route
        foreach ($shape in $shapes) {
            foreach ($n in @(256,512,1024)) {
                $case = "m=$($shape.m),n=$n,k=$($shape.k)"
                Write-Host "route=$route case=$case"
                & $exe perf -b ROCm0 -o Q6K_DENSE_ROUTE -p $case
                if ($LASTEXITCODE -ne 0) { throw "Perf failed: $route $case" }
            }
        }
    }
}
finally {
    Remove-Item Env:\GGML_HIP_Q6K_DENSE_ROUTE -ErrorAction SilentlyContinue
}
```

If there are no matching cases, check `-o Q6K_DENSE_ROUTE` and the `-p m=...,n=...,k=...` match. Do not compare trace-enabled run times.

### Optional route evidence

For one quick dispatch check, set `GGML_HIP_GEMM_TRACE=1` **without** `GGML_HIP_GEMM_TRACE_LAYER` or `GGML_HIP_GEMM_TRACE_N` filters (test tensors are named `a` and `b`, not `blk.N.`). Select one `Q6K_DENSE_ROUTE` case and confirm `path=blas` vs `path=mmq` in stderr. Disable the trace for timings. The experiment is not proven to have run merely by setting the environment variable.

## Decision gate

1. Verify `test-backend-ops test` for both forced routes; save the NMSE results and stop if any route fails.
2. Verify the selected route by trace at least once.
3. Compare the per-op perf distributions by shape and N. Beware one-time quantization/setup, thermal and clock variation.
4. If no stable MMQ benefit, stop; **do not** expand the forced override to other tensors or make it the default.
5. Only if a useful shape-dependent difference is repeatable, validate the real model output and run PP tests with diagnostics OFF.

Rollback: unset `GGML_HIP_Q6K_DENSE_ROUTE` before launching a new process. Existing diagnostic and MoE branches remain separate.
