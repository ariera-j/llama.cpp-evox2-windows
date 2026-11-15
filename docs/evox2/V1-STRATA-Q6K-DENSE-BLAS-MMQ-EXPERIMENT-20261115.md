# Q6_K Dense BLAS vs MMQ shape experiment (gfx1151)

## Status

Implemented, built, and GPU-tested on `investigation/v1-strata-dense-gemm-20261115` (Windows ROCm, Radeon 8060S/gfx1151). The performance-case registration was added in commit `76be555297bd3883c574bb4c918adef5229ad75c` (build b12367). Results and decision follow below. The default dispatch and the existing Dense diagnostic remain unchanged unless the experiment variable is set.

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


## Measured results and conclusion (2026-11-15)

### Scope and provenance

- GPU: Radeon 8060S, gfx1151, wave32; ROCm 10.0.0 (TheRock), Windows.
- Test binary: separate \`build-rocm-strata-gemm/bin/Release/test-backend-ops.exe\`; test-case additions in b12367 (commit \`76be555297bd3883c574bb4c918adef5229ad75c\`).
- Two repeated results per route, obtained in \`blas,mmq,mmq,blas\` order for each N. Per-operation \`test-backend-ops perf\` wall-time averages (microseconds per run). Trace was **OFF** for performance runs. Measurement includes backend dispatch, relevant conversion and scratch work; it is **not** an isolated GPU GEMM kernel timestamp.
- A previous invocation printed only \`Backend ROCm0: OK\` because \`Q6K_DENSE_ROUTE\` was registered in \`make_test_cases_eval()\` but *not* \`make_test_cases_perf()\`. The missing cases were then added to the perf suite; the silent zero-case run is **not** a timing result. In Windows PowerShell 5.1, capturing native stderr with \`2>&1\` under \`$ErrorActionPreference = 'Stop'\` can raise \`NativeCommandError\` for normal ROCm initialization messages. Subsequent runs captured stdout without stderr redirection.

### Direct operator benchmarks

Values in the two timing columns are averages of the two listed measurements (us/run). \`BLAS/MMQ\` is the relative throughput of BLAS vs MMQ: greater than 1 means BLAS is faster; less than 1 means MMQ is faster.

| Projection | Weight K x M | N | BLAS us/run (2 samples) | MMQ us/run (2 samples) | BLAS / MMQ throughput | Faster route |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Attention Q | 2560 x 12288 | 256 | 1076.53 (1077.27, 1075.78) | 1079.41 (1082.17, 1076.65) | 1.003x | Similar |
| Attention Q | 2560 x 12288 | 512 | 1501.72 (1503.98, 1499.46) | 2220.61 (2232.77, 2208.44) | 1.479x | BLAS |
| Attention Q | 2560 x 12288 | 1024 | 2581.34 (2582.31, 2580.37) | 4122.41 (4125.36, 4119.45) | 1.597x | BLAS |
| Attention Output | 6144 x 2560 | 256 | 1196.68 (1276.89, 1116.47) | 508.00 (508.19, 507.81) | 0.424x | MMQ (2.36x vs BLAS) |
| Attention Output | 6144 x 2560 | 512 | 1832.11 (1837.27, 1826.95) | 1100.88 (1098.30, 1103.45) | 0.601x | MMQ (1.66x vs BLAS) |
| Attention Output | 6144 x 2560 | 1024 | 2405.51 (2402.69, 2408.32) | 2709.23 (2703.53, 2714.92) | 1.126x | BLAS |

- This is shape-dependent, not a global BLAS/MMQ winner. In particular N=512 favors BLAS for Attention Q but MMQ for Attention Output.
- BLAS on Attention Output at N=256 varied more between samples; the gap vs MMQ is still large. No confidence intervals or independent clock/thermal-controlled replicates were collected.
- The benchmark repeats a graph operation and reports an average; it does not measure the full model's PP improvement. Do not multiply the per-op gain by layers without real-model evidence.

### Correctness

\`test-backend-ops test -b ROCm0 -o Q6K_DENSE_ROUTE -p ...\` passed the CPU-reference tolerance check for **both** forced \`blas\` and \`mmq\` routes for:

1. Attention Q, \`m=12288,n=256,k=2560\`: 1/1 for BLAS, 1/1 for MMQ. The trace also confirmed \`path=blas\` vs \`path=mmq\`.
2. Attention Output, \`m=2560,n=512,k=6144\`: 1/1 for BLAS, 1/1 for MMQ.

The remaining tested perf shapes were **not** separately validated by CPU-reference correctness tests. Correctness passes do not establish bitwise equality between BLAS and MMQ, or long-context generation quality.

### Real-model 64k dispatch check

- Evidence archive: \`20261115-214427-534-cli-rocm-b12367-ctx65536-52695434fb19.zip\`.
- Run: b12367, source commit \`76be555297bd3883c574bb4c918adef5229ad75c\`, old Unsloth original 3-shard Qwen3.8 Flash Next \`UD-IQ3_XXS\` model, \`code-64k.txt\` input SHA256 \`c41624eb232ffc1ab43a8ac066b0c96ee910ccee7a129b0d957fae0329225599\`.
- Settings: \`-c 65536\`, \`-b 2048\`, \`-ub 1024\`, KV F16, MTP OFF, 61,795 prompt tokens, 768 generated tokens, reported UMA 64GB, Performance P-MODE stable. No \`GGML_HIP_Q6K_DENSE_ROUTE\` override. Tracing enabled with \`GGML_HIP_GEMM_TRACE=1\`, \`GGML_HIP_GEMM_TRACE_LAYER=19\`, limit 2048.
- Run result OK, PP 411.42 tok/s, TG 22.30 tok/s; **not a comparable clean PP speed** because tracing/logging was enabled.
- \`summarize-dense-gemm.py --layer 19 --strict\` reported **1,253 selected of 1,253 lines; truncated=False**.
- For each of \`blk.19.attn_q.weight\` and \`blk.19.attn_output.weight\`: \`N=1024\` -> **60 BLAS dispatch records**, \`N=351\` -> **1 BLAS record**, and \`N=1/2/4\` -> **11/2/1 MMVQ records**. Neither tensor had any \`N=512\` or \`N=256\` dispatch record. The same N profile appears for the other layer-19 Dense projection weights in the trace.
- The large operator-level advantage of MMQ for Attention Output at N=512 **does not apply directly to this 64k/ubatch-1024 run**, where N=512 never occurred for that projection. The common N=1024 path favors BLAS for both Attention Q and Attention Output. N=351 was not part of the forced-route test scope.

### Decision

**Stop the forced existing BLAS-vs-MMQ route experiment for now; leave the default dispatch unchanged.** No real-model PP gain has been demonstrated. The useful result is a reproducible shape-dependent crossover at N=512, but that N was not reached under the observed 64k/ubatch-1024 workload. Do not globally force MMQ: it severely regresses Attention Q at N=512/1024. A different ubatch (such as 512) could alter the real N distribution; investigate that separately *only if* the intended production workload uses it.

Follow-up research: compare the **actual** llama.cpp Q6_K BLAS path (dequantize/convert + F16 GEMM, including its rocBLAS/hipBLASLt dispatch) against Strata's known/observable GEMM route, paying attention to weight format, shader/kernel implementation, scratch buffers, effective N, GPU target and backend versions. This experiment alone does **not** show that Strata's advantage comes from GEMM.
