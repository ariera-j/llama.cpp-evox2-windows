# v1.0.0 / gfx1151 MoE fusion investigation: Phase 0 runbook (2026-11-15)

**Branch**: `investigation/v1-strata-moe-fusion-20261115`, fork of `investigation/strata-pp-v1.0.0-20261115`. The original model is the old three-shard Qwen3.8 Flash Next UD-IQ3_XXS GGUF, not PLE16. **UMA is 64 GB.** No kernel fusion or precision algorithm changes have been made yet.

## What is in this branch

- **Host-only, default-OFF ROCm MoE dispatcher trace**. Enable with `GGML_HIP_MOE_TRACE=1`, narrow to a layer with `GGML_HIP_MOE_TRACE_LAYER=19`, and optionally to the full physical ubatch with `GGML_HIP_MOE_TRACE_N=1024`. Optional `GGML_HIP_MOE_TRACE_LIMIT` defaults to 2048 and accepts 1-8192. The `evox2_moe_dispatch_v1` rows include expert role/name, weight quant type, n_used, matrix K and M, physical ubatch token count N, path (mmq/mmvq/mmvf/mmf/host_fallback), MMQ J, and quantization/fallback flags. `J=0` and `prec=-1`/undefined values on non-MMQ calls mean **not applicable**, not missing work. A message `truncated_after=...` indicates incomplete coverage.
- No device sync, GPU readback, GPU marker, new kernels, or extra graph nodes in the diagnostic. Host stderr I/O **can perturb throughput**; never treat trace-ON PP as clean performance data.
- A small **whole-graph CPU-vs-backend correctness test** (`MOE_GATE_UP_DOWN`) builds separate IQ2_S Gate and Up `MUL_MAT_ID` calls, SwiGLU and IQ4_NL Down `MUL_MAT_ID`. Two microbatch sizes: 32 and 128 tokens. This is a reference for a later feature-flagged gfx1151 fusion implementation; it is **not** a benchmark of the unimplemented fusion.
- `tools/evox2/benchmark/summarize-moe-dispatch.py` reads saved stderr logs and summarizes actual routes by layer, role, format, N and MMQ J.
- `tools/evox2/tests/test_v1_strata_moe_probe.py` validates source contracts and the parser. These are static tests and **not** a substitute for Windows ROCm build or GPU results.

## Working directory / build isolation

Stay in the existing local repository. **Do not clone or create a separate worktree**:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git status --short
git fetch origin
git switch --track -c investigation/v1-strata-moe-fusion-20261115 origin/investigation/v1-strata-moe-fusion-20261115
git log -1 --format='%h %s'
```

This retains the user's ignored `tools/evox2/benchmark/configs/local.psd1`, any locally copied ADLX exe, and the old `build-rocm-strata-v1` baseline binary. The new build stays in **`build-rocm-strata-moe`** (already covered by `.gitignore` `/build*`).

```powershell
python -m unittest discover -s .\tools\evox2\tests -p 'test_v1_strata_moe_probe.py' -v

.\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-strata-moe `
    -AmdGpuTarget gfx1151 `
    -Parallel 4 `
    -DependencyCacheRoot 'C:\llama-build\evox2-deps' `
    -ExtraTargets @('test-backend-ops')

$bin = '.\build-rocm-strata-moe\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\test-backend-ops.exe" test -b ROCm0 -o MOE_GATE_UP_DOWN
```

Never use `-RunBackendTest` for the build command: earlier ROCm Flash Attention backend tests caused GPU hangs. The focused `MOE_GATE_UP_DOWN` test is a separate deliberate GPU test, not an all-ops suite. Start with the Python static tests, then build, then the focused test. If the test exits nonzero or triggers a GPU reset, stop and preserve logs.

The baseline build at `build-rocm-strata-v1` must remain untouched. Both builds use the same **working tree**, so `git switch` changes source for future compiles; it does not replace existing binaries. Do not run two builds targeting one directory simultaneously.

## Model trace: one short, filtered run

In the ignored `local.psd1`, add a new entry **inside the existing `Builds` table** (retain all existing keys):

```powershell
V1StrataMoe = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-v1-strata-pp\build-rocm-strata-moe\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Use exactly the **same frozen code64k input** that produced the clean v1.0.0 baseline, with `UnslothOriginal`. Before starting `Measure-LlamaCli.ps1`, set the diagnostic environment in that PowerShell session:

```powershell
$env:GGML_HIP_MOE_TRACE = '1'
$env:GGML_HIP_MOE_TRACE_LAYER = '19'
$env:GGML_HIP_MOE_TRACE_N = '1024'
$env:GGML_HIP_MOE_TRACE_LIMIT = '512'
```

Repeat the successful prior `Measure-LlamaCli.ps1` command, changing **only** `-BuildKey V1StrataMoe`, `-GenerationTokens 8` (for a short correctness smoke) and `-UmaLabel 64GB`. Keep `-Context 65536 -Batch 2048 -UBatch 1024 -KvType f16 -ModelKey UnslothOriginal`, `-Reasoning off`, MTP OFF, and the *same input path*. For a focused dispatch test do not evaluate its recorded PP as a speed number.

After the run:

```powershell
# Set this path to the extracted stderr.log from the completed run.
$log = 'C:\path\to\stderr.log'
python .\tools\evox2\benchmark\summarize-moe-dispatch.py $log --layer 19 --n 1024 --require-role gate --require-role up --require-role down --strict
Remove-Item Env:\GGML_HIP_MOE_TRACE,Env:\GGML_HIP_MOE_TRACE_LAYER,Env:\GGML_HIP_MOE_TRACE_N,Env:\GGML_HIP_MOE_TRACE_LIMIT -ErrorAction SilentlyContinue
```

If the selected GGUF combines gate/up into one tensor, use `--require-role gate_up` instead and record that observation. Print the log's actual tensor names and format; do not assume the entire three-shard GGUF uses IQ3_XXS for routed experts. Historical r6 layer 19 used IQ2_S Gate/Up and IQ4_NL Down, but **the current clean v1 dispatch remains to be verified**. For a new layer, adjust the layer filter rather than guessing weight formats.

## Gate criteria before enabling any fusion

1. `MOE_GATE_UP_DOWN` CPU-reference vs ROCm tests PASS at the two microbatch sizes, with no TDR/reset.
2. Log proves which dtype, physical N and MMQ J the targeted layer actually uses. It may select MMVQ or another path at small N.
3. Freeze a source SHA, model file hash/size, prompt SHA and exact flags. Store the baseline output; do **not** compare trace-ON PP speed with trace-OFF PP speed.
4. Only then implement an independent **default-OFF** `IQ2_S` Gate/Up/SwiGLU fast path for gfx1151. Keep Down untouched at first. Use the same CPU-reference test and a matched feature OFF/ON 64K run. Quantized fused arithmetic may differ from nonfused MMQ at rounding level.
5. When practical, extend the test to a realistic routed-token distribution, duplicate-expert IDs, partial tiles, and non-broadcast input modes. All changes must fail closed to the standard code path for unsupported types/shapes and other GPUs.

**No experimental source/kernel from r6 has been copied**. The earlier r6 MMQ diagnostic was consulted for naming and a successful Windows host-only tracing precedent, but this branch is clean v1.0.0 plus the standalone diagnostic and test.

Relevant history: [r6 MMQ host trace study](R6-ROCM-PP64K-IQ3-IQ4-MMQ-CLI-TRACE-2026-11-10.md); [Strata vs r6 source audit](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/STRATA_V0213_VS_LLAMA_R6_PP_SOURCE_COMPARISON_20261115.md).
