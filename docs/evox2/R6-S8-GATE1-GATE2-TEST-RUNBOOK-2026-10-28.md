# R6 S8 combined: Gate 1 -> Gate 2 Windows test runbook (2026-10-28)

This runbook follows `R6-S8-COMBINED-INTEGRATION-PLAN-2026-10-28.md` for source `b82243bf0` / build `b11908`. Run in Windows PowerShell from `C:\llama-build\llama.cpp-evox2-windows-r6`, branch `r6/combined-20261028`. The user's Vulkan and ROCm build manifests were both `BuildIdentity=Verified`; ROCm uses TheRock SDK 10.0 and the known-good Visual Studio 2022/MSVC 14.44 environment. `llama-tokenize` was subsequently built on both backends.

**Run one gate at a time. Stop on any unexpected exit, output mismatch, GPU reset or P-MODE anomaly.** Do not run `Build-ROCm.ps1 -RunBackendTest` or an unfiltered backend test on Windows gfx1151; the broad `FLASH_ATTN_EXT` suite has a watchdog history. The S2 numerical test below targets **Vulkan only**.

## 0. Source and local configuration

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git branch --show-current
git rev-parse --short HEAD

# Inspect; add both build entries inside the existing Builds table if missing.
notepad .\tools\evox2\benchmark\configs\local.psd1
```

Expected entries (preserve all earlier mappings and existing Models/Inputs):

```powershell
CombinedVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-combined\bin\Release'
    ExpectedBackend = 'Vulkan'
}
CombinedROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-r6-combined\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

These are entries **inside** `Builds`, not a complete replacement for `local.psd1`. Confirm that `Models.UnslothPle16` and `Models.UnslothMtp` point to the existing IQ3 PLE16 main and Q8_0 MTP GGUFs.

## 1. Build the four missing native test executables

The standard `Build-Vulkan.ps1` and `Build-ROCm.ps1` targets do not include these four binaries. Even though `llama-tokenize` was separately built, re-run the respective build wrapper with `-BuildOnly` so `evox2-build.json` records the new test executable hashes. Keep the **same** source and build directory.

In the existing Vulkan-capable PowerShell:

```powershell
$nativeTargets = @('test-mtp-indexer-policy', 'test-mtp-dense-indexer',
                   'test-qsa-noop-policy', 'test-qsa-noop-invalidation',
                   'llama-tokenize')
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildOnly -BuildDir .\build-vulkan-r6-combined -Parallel 4 `
    -ExtraTargets $nativeTargets
```

For ROCm, use the **Visual Studio 2022 Developer PowerShell + TheRock virtual environment** already confirmed to select MSVC 14.44 (not VS18/MSVC 14.51):

```powershell
$nativeTargets = @('test-mtp-indexer-policy', 'test-mtp-dense-indexer',
                   'test-qsa-noop-policy', 'test-qsa-noop-invalidation',
                   'llama-tokenize')
& .\tools\evox2\build\Build-ROCm.ps1 `
    -BuildOnly -BuildDir .\build-rocm-r6-combined -Parallel 4 `
    -ExpectedRocmSdkVersion '10.0.0' -AmdGpuTarget gfx1151 `
    -ExtraTargets $nativeTargets
```

Confirm `BuildIdentity.Status = Verified`, the `llama-cli` version is still `b11908-b82243bf0`, and the ROCm `RuntimePolicy.Verification` is still `DllAndRuntimeDataHashesVerified`. For both builds, check all four `test-*.exe` now exist. Do not treat mere build success as a native test pass.

## 2. Gate 1A: bounded Vulkan ROCmFPx numerical gate (150 cases)

Run on **Vulkan0**, not ROCm0. The suite uses the ggml backend test's filtering options; inspect the actual number of executed tests rather than accepting skipped tests as passes.

```powershell
$exe = '.\build-vulkan-r6-combined\bin\Release\test-backend-ops.exe'
$types = 'type_a=(q4_0_rocmfp4|q4_0_rocmfp4_fast|q3_0_rocmfpx|q6_0_rocmfpx|q8_0_rocmfpx)'
try {
    foreach ($mode in @('normal', 'force-mmvq')) {
        if ($mode -eq 'force-mmvq') {
            $env:GGML_VK_FORCE_MMVQ = '1'
        } else {
            Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
        }
        foreach ($test in @(
            @{ Op = 'MUL_MAT';    Pattern = $types },
            @{ Op = 'MUL_MAT_ID'; Pattern = "$types.*skip=0" },
            @{ Op = 'MUL_MAT_ID'; Pattern = "$types.*skip=1" }
        )) {
            & $exe test -b Vulkan0 -o $test.Op -p $test.Pattern
            if ($LASTEXITCODE -ne 0) {
                throw "Numerical gate failed: $mode / $($test.Op) / $($test.Pattern)"
            }
        }
    }
} finally {
    Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
}
```

Expected 35 MUL_MAT + 35 MUL_MAT_ID skip=0 + 5 MUL_MAT_ID skip=1 per mode = **150/150** across two modes. Stop and preserve logs if the test case selection or counts have changed. Run no unfiltered `test-backend-ops` on ROCm.

## 3. Gate 1B: native policy, model/state and rollback

These PowerShell harnesses write timestamped report directories under `evox2-logs/tests`, containing `result.json`, `policy.stdout.log`, and `model.stdout.log` / `.stderr.log`.

Run **Vulkan first**:

```powershell
& .\tools\evox2\tests\Test-MtpDenseIndexer.ps1 `
    -BuildKey CombinedVulkan -ModelKey UnslothPle16 `
    -DraftModelKey UnslothMtp -RunModelTests

& .\tools\evox2\tests\Test-R6MtpNoop.ps1 `
    -BuildKey CombinedVulkan -ModelKey UnslothPle16 -RunModelTests
```

Then **ROCm**, using the same source with the separate `CombinedROCm` build key:

```powershell
& .\tools\evox2\tests\Test-MtpDenseIndexer.ps1 `
    -BuildKey CombinedROCm -ModelKey UnslothPle16 `
    -DraftModelKey UnslothMtp -RunModelTests

& .\tools\evox2\tests\Test-R6MtpNoop.ps1 `
    -BuildKey CombinedROCm -ModelKey UnslothPle16 -RunModelTests
```

Gate requires exit 0 and `result.json: Status=Complete, SourceChecks=Passed, PolicyTest=Passed, ModelTest=Passed`. Confirm `MTP dense indexer: PASS (...)`, `QSA no-op invalidation: PASS (...)`, expected rollback/state-restore tests, and the known NOOP 524/524 comparisons with `nmse=0 max_abs=0` (or investigate any documented difference). Deliberate invalid-state-restore negative probes may emit stderr; judge by the harness final assertions and exit status, not by stderr presence alone. No long-context benchmarking before this gate passes.

## 4. Gate 2, first 4k smoke only (after Gate 1 PASS)

The existing S8 PSD1 plan is authoritative. Check the plan syntax and build keys first:

```powershell
Get-ChildItem .\tools\evox2\benchmark\configs\qwen38-r6-s8-*.psd1 | ForEach-Object {
    $plan = Import-PowerShellDataFile -LiteralPath $_.FullName
    '{0}: schema={1}, jobs={2}' -f $_.Name, $plan.SchemaVersion, @($plan.Jobs).Count
}
$smoke = '.\tools\evox2\benchmark\configs\qwen38-r6-s8-smoke.psd1'
$runner = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
& $runner -Plan $smoke -OnlyJob s8-iq3-vulkan-smoke -OnlyCase 4k -PlanOnly
```

After verifying the planned binary, model, variant list and environment settings, run just that one job:

```powershell
& $runner -Plan $smoke -OnlyJob s8-iq3-vulkan-smoke -OnlyCase 4k -StopOnError
```

**Stop and inspect** its output before running FP4 or ROCm:

- All cases ended `Status=OK`, `ExitCode=0`, with no model-loading or allocation failures.
- Target and Draft were fully GPU-offloaded; MTP acceptance is positive in MTP-ON variants.
- Output is coherent, and expected default-OFF vs opt-in behavior is evidenced by logs (do not assume active flags solely because they were set).
- No unexpected rollback, invalid CUDA/HIP/graphics device state, driver reset or low-power/P-MODE condition.

After reviewing that report, the next individually gated jobs are:

```powershell
& $runner -Plan $smoke -OnlyJob s8-fp4-vulkan-smoke -OnlyCase 4k -PlanOnly
& $runner -Plan $smoke -OnlyJob s8-fp4-vulkan-smoke -OnlyCase 4k -StopOnError

& $runner -Plan $smoke -OnlyJob s8-iq3-rocm-smoke -OnlyCase 4k -PlanOnly
& $runner -Plan $smoke -OnlyJob s8-iq3-rocm-smoke -OnlyCase 4k -StopOnError
```

Do not launch all smoke variants, 16k/32k, 64k/128k ABBA, ROCm Stage-B/flatten or 256k in one unattended batch. Once the 4k results are reviewed, choose the remaining G8-2 jobs and only then proceed to G8-3.

## Handoff files

1. Fresh `evox2-build.json` for Vulkan and ROCm (after native-target build).
2. Text output from all six Vulkan focused numerical invocations (expected 150/150).
3. The four native harness report directories as ZIP or `result.json` plus `policy/model` logs.
4. First Vulkan IQ3 4k smoke ZIP. Review this before other 4k smoke jobs.

No code changes or environment-default changes are required by this runbook. Git commit/push is separate and requires explicit user request.
