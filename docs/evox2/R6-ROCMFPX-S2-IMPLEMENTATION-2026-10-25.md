# r6 S2 ROCmFPx port: COMMON-003A / VULKAN-001A / VULKAN-001B

## Scope and state

- **Base:** `r6/common001-ple16-20261025` at `39920946753e14b0e9bc43eba00e186441370ba3` (S1 PASS), with ggml-org/llama.cpp b11870 as its original upstream.
- **Working branch:** `r6/rocmfpx-vulkan-20261025` (separate from S1 and r6 clean).
- **State:** port implemented, source consistency checks passed; **Windows Vulkan build, GPU shader compilation, numerical tests and real-model measurements are pending**. Do not mark S2 PASS before the Evo-X2 gates below.
- **Donor:** `investigation/r5-rocmfpx-vulkan-20261020`. Reused tested commits `85ab8d79` (core), `202f4988` (correctness shaders), `8205db29` (integer dot), `fe36a4d3` (tests).
- **Unchanged roadmap:** S2 then S3, without opportunistic performance changes. ROCmFP4-specific HIP kernels and forcing MMVQ for normal use are **not** included.

| Part | r6 implementation | Notes |
| --- | --- | --- |
| COMMON-003A | GGML types 100, 101, 102, 103, 104, 107; corresponding file types, dequant/quant helpers, loader, CPU fallback | Preserve serialized GGUF IDs. `Q2_0_ROCMFPX` has **no Vulkan shader**, by historical design. |
| VULKAN-001A | 5 Vulkan-supported formats; dequantization, copy, MUL_MAT, MUL_MAT_ID | Covers ROCmFP4, FAST, FP3, FP6, FP8. |
| VULKAN-001B | `q8_1` MMVQ for ROCmFP4/FAST/FP8 and MMQ for ROCmFP4/FAST | FP3/FP6 keep float matvec paths. Default dispatch is unchanged. |
| Test gate | Five types, MUL_MAT and MUL_MAT_ID, widths 1/3/4/5/6/7/8 | Historical 140 cases across normal/forced MMVQ, plus 10 cases for skipped expert IDs (`-1`). |

### b11870-specific adjustment

`mul_mmq.comp` now invokes `block_a_to_shmem(buf_ib, ib, iqs, is_in_bounds)` with **four arguments**; the validated r5 ROCmFP4 donor used three. The port adapts ROCmFP4 and FAST to four arguments, avoids source reads for out-of-range blocks, and zero-initializes both integer-weight halves and the scale. This matters for partial K tiles and prevents a compile error on the new upstream.

The existing upstream `MUL_MAT_ID` test fixture also supports `skip=true` (`-1` expert IDs). Add five targeted ROCmFPx skipped-ID cases at width 4 to catch this edge case without changing the historical 140-case gate. Check both dispatch modes.

## Preliminary local verification

- Cherry-picked four source/test units against S1 without merge conflicts; inspected the resulting upstream dispatch, shader generator, and scope.
- `git diff --check` passed for code commits.
- Local GCC syntax checks passed for `rocmfp4.c`, `rocmfpx.c`, `ggml-quants.c`, `ggml-cpu.c`, and G++ syntax check passed for `ggml-cpu/ops.cpp`.
- This Linux workspace **does not contain the Windows Vulkan SDK, `glslc`, or CMake**. Actual shader compilation and end-to-end execution must be performed on Evo-X2. No performance or GPU correctness claim is made from syntax checks.

## User-side build and validation sequence (Windows / Evo-X2)

**1. Preserve S1 baseline, fetch and check out the S2 branch.** Run in the existing r6 worktree; keep the S0 and S1 build directories untouched.

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git switch -c r6/rocmfpx-vulkan-20261025 --track origin/r6/rocmfpx-vulkan-20261025
git status

.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-r6-rocmfpx -Parallel 4
```

- First inspect the build JSON: branch/commit/build identity, Vulkan backend and compiler, and that new shader compilation succeeded.
- **Do not** start unfiltered `test-backend-ops` or the ROCm `FLASH_ATTN_EXT` suite. The earlier Windows watch-dog incidents make those unsuitable for this gate.

**2. Focused numerical gate.** The following test paths preserve the r5 140-case gate and independently test the five skipped-expert cases under both dispatch modes. The `type_a` regex selects only the new formats. If the upstream test runner's filter semantics differ from expected, inspect the printed case count before treating a test as passed.

```powershell
$bin = '.\build-vulkan-r6-rocmfpx\bin\Release'
$exe = "$bin\test-backend-ops.exe"
$types = 'type_a=(q4_0_rocmfp4|q4_0_rocmfp4_fast|q3_0_rocmfpx|q6_0_rocmfpx|q8_0_rocmfpx)'

try {
    foreach ($mode in @('normal', 'force-mmvq')) {
        if ($mode -eq 'force-mmvq') {
            $env:GGML_VK_FORCE_MMVQ = '1'
        } else {
            Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
        }
        & $exe test -b Vulkan0 -o MUL_MAT -p $types
        & $exe test -b Vulkan0 -o MUL_MAT_ID -p "$types.*skip=0"
        & $exe test -b Vulkan0 -o MUL_MAT_ID -p "$types.*skip=1"
    }
} finally {
    Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
}
```

Expected focused cases: 35 MUL_MAT + 35 ordinary MUL_MAT_ID + 5 skipped-ID MUL_MAT_ID per mode; **150/150** over both modes. Keep stdout/stderr and all failures. `ggml` support/skipped messages are not numerical passes; verify tests actually executed and numerical comparison passed.

**3. Actual model smoke.** Update `tools/evox2/benchmark/configs/local.psd1` (ignored by Git) with:

```powershell
# Append inside Builds:
S2Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-rocmfpx\bin\Release'
    ExpectedBackend = 'Vulkan'
}
# Append inside Models (actual first GGUF shard or model path):
AgentionRocmFp4FastPle16 = @{
    Path = 'C:\path\to\Qwen3.8-Flash-Next-ROCmFP4-FAST-ple16.gguf'
    Alias = 'agention-rocmfp4-fast-ple16'
}
```

The local `UnslothPle16` and `Inputs.64k` / `Inputs.128k` entries remain the same as S1. Check the ROCmFP4 FAST model's own GGUF header/type IDs and keep the GGUF input checksum in logs.

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"
$plan = "$bench\configs\qwen38-r6-rocmfpx.psd1"

# Short smoke: do not proceed unless generation and GPU placement are correct.
& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan -ModelKey AgentionRocmFp4FastPle16 -AllocationOnly -Context 4096
& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan -ModelKey AgentionRocmFp4FastPle16 -AllocationOnly -Context 16384

# Only after numerical tests and smoke have passed.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k

# Only after 64k succeeds. No new 256k repetitions in S2.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k
```

`-AllocationOnly` in this measurement tool is the established short smoke mode. Verify it actually performs generation, not merely allocation. Check all-layer Vulkan placement versus the earlier ~41.8 GiB CPU buffer seen before VULKAN-001A, P-MODE and ADLX metadata, graph splits, coherent output, and unexpected CPU fallback. The 64k IQ3 PLE16 run is the S2-binary regression control, not proof of ROCmFP4-vs-IQ3 quality parity.

**STOP conditions:** compilation errors; failure/skipping in the 150-case numerical gate; model type 101 load failure; inappropriate CPU model placement; output corruption; abnormal power mode; repeated crashes. Record diagnostics in S2 before discussing S3. Keep ROCmFP4 MTP and the remaining r6 patch list for their planned later stages.
