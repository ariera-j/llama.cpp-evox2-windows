# IQ2_S routed Gate/Up/SwiGLU fusion on gfx1151 (PoC, 2026-11-15)

## Status and scope

**Implemented on** `investigation/v1-strata-moe-fusion-20261115`; **not yet compiled or GPU-tested** after this change. The previous Phase 0 build b12366 and 64K MoE trace were successful, but they **do not validate the new fused code**. This branch remains based on upstream v1.0.0, with the user's own r6 historical docs/tools.

- GPU: exact AMD gfx1151, HIP/ROCm. Default OFF; opt-in with `GGML_HIP_MOE_IQ2S_FUSION=1`. Other values (including `0`) preserve previous code.
- Operation: routed `MUL_MAT_ID`, matching separate IQ2_S Gate and Up weights, GGML_GLU_OP_SWIGLU, broadcast activation (ne[1]==1), shared Expert IDs. Existing graph matching also rejects mismatched strides/precision, view/padding hazards, unsuitable batch sizes and cases where MMQ is not selected.
- Kernel: the existing MMQ Gate/Up fusion path (previously NVIDIA only) with a new IQ2_S dual-weight loader. In each 16-row WMMA256 tile, 8 Up rows interleave with their 8 Gate rows. The AMD WMMA256 J-major accumulator stores corresponding rows in registers `l` and `l+4` of each lane, enabling the existing fused GLU writeback. Source activation conversion (F32 to Q8_1), Expert index compacting and the MMQ kernel are shared within the fused call.
- The IQ4_NL Down projection remains unchanged. No Strata source code was copied. No new GGML operator, public API, or GPU synchronization was introduced.

## Relevant source files

- `ggml/src/ggml-cuda/ggml-cuda.cu`: opt-in exact gfx1151 gate in the existing fused MMQ graph matcher, plus common header.
- `ggml/src/ggml-cuda/mmq.cuh`: compile-time IQ2_S fusion support for HIP, WMMA256 fusion availability, dual-weight IQ2_S MMA/writeback specialization.
- `ggml/src/ggml-cuda/mmq-load-tiles.cuh`: `ggml_cuda_mmq_load_tiles_iq2_s<..., has_fusion>`, using the existing `ggml_cuda_mmq_x_row` row interleaving helper. The ordinary path uses `has_fusion=false`.
- `ggml/src/ggml-cuda/mmq.cu`: host-side trace reports `path=mmq_iq2s_fused` for a fused launch, rather than `path=mmq`.
- `tests/test-backend-ops.cpp`: `MOE_GATE_UP_DOWN` graph checks small 8/2 and realistic 512/10 Expert selection, each with 32 and 128 tokens. Gate/Up are IQ2_S, Down IQ4_NL, tested against the CPU reference.
- `tools/evox2/tests/test_v1_strata_moe_probe.py`: source guards and WMMA256 C-tile register pairing check.

## Runbook: source, build and focused tests

Use the **same** working directory, and keep `build-rocm-strata-v1` unchanged.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git status --short
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_v1_strata_moe_probe.py' -v
if ($LASTEXITCODE -ne 0) { throw 'Static test failure' }

.\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-strata-moe `
    -AmdGpuTarget gfx1151 `
    -Parallel 4 `
    -DependencyCacheRoot 'C:\llama-build\evox2-deps' `
    -ExtraTargets @('test-backend-ops')
```

Do not use `-RunBackendTest`. If the build fails, capture the full compiler error before testing. Never test a partially updated runtime (build script must report verified artifacts).

Compare isolated processes with the feature OFF and ON (the flag is read once per process):

```powershell
$exe = '.\build-rocm-strata-moe\bin\Release\test-backend-ops.exe'

Remove-Item Env:\GGML_HIP_MOE_IQ2S_FUSION -ErrorAction SilentlyContinue
& $exe test -b ROCm0 -o MOE_GATE_UP_DOWN
if ($LASTEXITCODE -ne 0) { throw 'OFF test failed' }

$env:GGML_HIP_MOE_IQ2S_FUSION = '1'
& $exe test -b ROCm0 -o MOE_GATE_UP_DOWN
if ($LASTEXITCODE -ne 0) { throw 'ON test failed' }

Remove-Item Env:\GGML_HIP_MOE_IQ2S_FUSION -ErrorAction SilentlyContinue
```

**Caution**: Previous backend tests passing with the feature OFF are no substitute for the ON test. If the feature ON test fails, times out, or resets the GPU, do not run the full model with it. Preserve stderr and revert to OFF. The numeric test tolerance is NMSE 5e-3; a passing test does not establish bit-identical results.

## Model-only dispatch validation gate

Only after both focused tests succeed, use the old 3-shard UnslothOriginal GGUF and frozen 64k code input with `Measure-LlamaCli.ps1`, `BuildKey=V1StrataMoe`, context 65536, batch 2048, ubatch 1024, f16 KV, UMA64GB, MTP OFF, 8 generated tokens. Run in a **fresh PowerShell process** if uncertain about earlier environment.

```powershell
$env:GGML_HIP_MOE_IQ2S_FUSION = '1'
$env:GGML_HIP_MOE_TRACE = '1'
$env:GGML_HIP_MOE_TRACE_LAYER = '19'
$env:GGML_HIP_MOE_TRACE_N = '1024'
$env:GGML_HIP_MOE_TRACE_LIMIT = '512'
```

Use the previously successful full `Measure-LlamaCli.ps1` command, with `-BuildKey V1StrataMoe`. The expected full-ubatch trace on Layer 19 is **one** `role=up path=mmq_iq2s_fused weight_type=iq2_s` call and **one** `role=down path=mmq weight_type=iq4_nl` call per ubatch. If it is still Gate+Up+Down separately, fusion was not chosen; inspect graph fusion checks rather than assuming it ran.

```powershell
python .\tools\evox2\benchmark\summarize-moe-dispatch.py 'C:\path\to\stderr.log' --layer 19 --n 1024 --strict
Remove-Item Env:\GGML_HIP_MOE_IQ2S_FUSION,Env:\GGML_HIP_MOE_TRACE,Env:\GGML_HIP_MOE_TRACE_LAYER,Env:\GGML_HIP_MOE_TRACE_N,Env:\GGML_HIP_MOE_TRACE_LIMIT -ErrorAction SilentlyContinue
```

The expected *counts* depend on the exact frozen prompt and physical ubatches; the earlier 64k trial had 60 full 1024-token chunks. Do not interpret diagnostic-on PP throughput as benchmark performance.

**Final speed/quality gate**: only after confirming the fused route in a real model, compare two **trace OFF** 64k runs with feature OFF vs ON, including text output and hashes, then extend to 128k and MH-Hard if justified. Keep `build-rocm-strata-v1` as an independent clean upstream reference.

## Risk and rollback

- The critical layout invariant is **AMD WMMA256**, not WMMA128/CDNA. The host gate tests exact gfx1151. The IQ2_S dual-loader uses the existing `ggml_cuda_mmq_x_row` interleaving; this must be verified by actual ROCm results.
- Only SwiGLU (no clamp, biases, or per-Expert scales) is enabled. Unmatched graphs, small MMVQ cases, non-broadcast input, wrong GPU or disabled flag must preserve the original behavior.
- Reverting `GGML_HIP_MOE_IQ2S_FUSION` to `0` (or removing it) before process launch switches back without rebuilding.
- No PP improvement has been established by this patch; a PoC that is correct but slower should not be left enabled.

Previous Phase 0 notes: [V1-STRATA-MOE-PHASE0-RUNBOOK-20261115.md](V1-STRATA-MOE-PHASE0-RUNBOOK-20261115.md).
