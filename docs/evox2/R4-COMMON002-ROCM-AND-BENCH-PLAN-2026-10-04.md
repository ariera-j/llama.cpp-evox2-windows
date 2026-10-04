# r4 COMMON-002: ROCm validation and CLI/bench comparison

User-directed order after Vulkan normal ABBA: ROCm build/measurement, then
CLI/llama-bench comparison, then choose the next optimization investigation.
Do not start suffix reuse or MTP PP changes before reviewing these results.
Source default stays OFF and upstream remains pinned. The plan adds benchmark
configurations only; no inference/runtime implementation changes.

## 1. Build ROCm and validate native behavior

Use the previously working TheRock venv/SDK setup. Build scripts already include
the dense-indexer and target-no-op policy/model tests and llama-bench. Reuse
`build-rocm-r4`; verify `local.psd1` BuildKey `R4ROCm` points to its Release bin
with ExpectedBackend=ROCm. Preserve the verified Vulkan build for later bench.

```powershell
git pull --ff-only
# Activate the same TheRock venv used for the earlier successful ROCm build.
& .\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir build-rocm-r4 -Parallel 4
& .\tools\evox2\tests\Test-MtpDenseIndexer.ps1 `
    -BuildKey R4ROCm -RunModelTests
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 `
    -BuildKey R4ROCm -RunModelTests
```

Both test reports must be Complete, with source/build/runtime evidence and
numeric/state/rollback checks passing. A SourceOnly or policy-only report is
not a ROCm model gate. Vulkan success does not imply ROCm numeric success.
The native scripts temporarily set Vulkan-only controls, which have no HIP
implementation effect; the ROCm benchmark plans clear those controls.

## 2. Allocation and short CLI gate

Three allocation smokes mirror the validated Vulkan gate. They clear all plan
controls and restore the caller environment after execution:

```powershell
$plan = Import-PowerShellDataFile `
    .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-rocm-check.psd1
$names = @($plan.Defaults.Environment.Keys)
$saved = @{}
foreach ($name in $names) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $env:LLAMA_MTP_DIAG = 'off'
    $env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
    $smoke = @{
        BuildKey = 'R4ROCm'; ModelKey = 'UnslothPle16'
        Context = 32768; GenerationTokens = 32
        KvType = 'f16'; Batch = 2048; UBatch = 1024; Threads = 4
        GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
        Temperature = 0.0; TopP = 0.8; Reasoning = 'off'; Fit = 'off'
        PromptCacheMiB = 0; Verbosity = 4
        ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
    }
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke -AllocationOnly
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
        -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
        -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-rocm-check.psd1
```

Short matrix has exactly five runs: OFF/target1 control, A-normal0, B-normal1,
A-wall0, B-wall1. All MTP ON arms retain dense omission1 and DraftMax2/PMin0.
Check8/8 statuses and Verified ROCm/runtime/target/draft evidence, A/B output,
aggregate acceptance and wall trim history, suppression versus actual removals,
and preserved dirty state before running the long plan. Unknown phase events
remain unknown; do not reinterpret them as missing scopes or generation work.

## 3. Focused ROCm 256k normal comparison

After the preceding gate passes:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-rocm-256k.psd1
```

Exactly three serial diagnostic-OFF runs at context262144 /input256k /n512:

| Arm | MTP | Dense draft omission | Target no-op suppression | Purpose |
| --- | --- | ---: | ---: | --- |
| control-mtp-off | OFF | 1 (no draft) | 1 | Fresh same-binary OFF reference and later bench control |
| A-normal | ON | 1 | 0 | Isolate target no-op cost with dense omission retained |
| B-normal | ON | 1 | 1 | Current combined candidate |

This is an exploratory pair plus OFF control, not a ROCm ABBA or an isolated
dense-omission experiment. Compare A/B output and acceptance within ROCm;
cross-backend outputs need not be identical. Check PP/TG and reported total
evaluation, not loading-inclusive wall-clock duration. Compare current results
with historical ROCm separately; do not attribute every cross-build change
to the target switch. Add repetitions or wall attribution only if the normal
result leaves a concrete uncertainty. No automatic all-context overnight matrix.

## 4. Staged CLI/bench comparison

The pinned implementation `tools/llama-bench/llama-bench.cpp` has no draft-model,
MTP verification or sampling path. `test_prompt` evaluates random token IDs;
`test_gen` decodes one random token at a time and synchronizes every step.
Use **MTP OFF CLI** for the direct comparison. MTP ON remains a separate
application measurement; bench cannot measure the speculative trim benefit.

The prepared `qwen38-r4-cli-bench-comparison.psd1` has Vulkan and ROCm jobs,
first64k and later256k. Same PLE16 model/backend build per pairing, f16,
b2048/ub1024, threads4, ngl999, CPU MoE0 and FA auto. The CLI uses t4/tb4,
512 generated tokens and the prior real inputs. Both candidates are explicitly1,
diagnostics OFF; no draft is loaded. Vulkan tile/union settings match the CLI
measurements; ROCm clears those Vulkan controls.

| Case | CLI allocated context | Expected CLI prompt tokens | Bench PP | Bench TG |
| --- | ---: | ---: | --- | --- |
| 64k | 65536 | 61789 | p61789, n0, d0, repetitions2 | p0, n512, d61789, repetitions3 |
| 256k | 262144 | 255181 | p255181, n0, d0, repetitions2 | p0, n512, d255181, repetitions3 |

The token counts come from existing CLI results, including the current256k
ABBA. Verify fresh OFF counts before bench; adjust the prepared counts if
actual tokenization differs. Do not substitute65536/262144 for processed
token counts. `-p P -n512 -d0` would be independent PP and empty-depth TG,
so it is deliberately not used as a long-context TG comparison.

Before bench, check its current executable/DLL hashes against the build manifest:

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
$local = Import-PowerShellDataFile .\tools\evox2\benchmark\configs\local.psd1
foreach ($key in @('R4QsaUnionVulkan', 'R4ROCm')) {
    $bench = Join-Path $local.Builds[$key].BinDir 'llama-bench.exe'
    $manifest = Read-Evox2BuildManifest -Executable $bench
    $runtime = Test-Evox2RuntimeArtifacts -Executable $bench -Manifest $manifest
    if ($null -eq $manifest -or $manifest.BuildIdentity.Status -ne 'Verified' -or
        $runtime.Status -ne 'Verified') { throw "$key bench build/runtime identity is not Verified." }
    Write-Host "$key bench runtime: $($runtime.Digest)"
}
```

Collect fresh64k CLI controls first (two runs), then bench after confirming
counts/conditions (four invocations, two result rows per backend: PP and TG):

```powershell
$comparison = '.\tools\evox2\benchmark\configs\qwen38-r4-cli-bench-comparison.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $comparison -Tool cli -OnlyCase 64k
# Review CLI token counts and status before the bench command.
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $comparison -Tool bench -OnlyCase 64k
```

Review64k first. For256k, reuse the focused ROCm OFF result from step3 if the
same runtime/settings/input are retained; collect only the missing Vulkan OFF
control, then the four bench invocations:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $comparison -Tool cli -OnlyCase 256k -OnlyBuild R4QsaUnionVulkan
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $comparison -Tool bench -OnlyCase 256k
```

Interpretation limits from the pinned source:

- Bench requested context is p+n+d, then subject to runtime padding; there is
  no independent CLI-style `-c` option. PP and TG requested sizes therefore
  differ from the CLI allocation. Record actual context and buffer sizes;
  do not add dummy depth to PP merely to match allocation, which would change
  the fresh-prefix workload. The wrapper's directory ContextHint excludes n
  and is not the authoritative allocated context.
- Random versus real-text token IDs can alter MoE expert routing and runtime
  cost. Bench excludes application sampling/tokenization/server trim behavior.
  Its wall timer and CLI reported evaluation timer also have different boundaries.
- Standard warmup remains ON. PP warmup runs the full prompt, then two measured
  repetitions; this is three full prefills, not a tiny32-token warmup.
  TG initially fills depth outside the timed section; later repetitions try
  restoring serialized depth state, falling back to prefill if incompatible.
  These warmup/state costs affect elapsed duration and cache history even when
  excluded from the printed TG metric.
- Bench timing differences alone cannot identify a faulty backend or explain
  MTP PP overhead. Report the size and direction of gaps within each backend,
  dispersion and known workload differences before selecting a source investigation.

## 5. Decision after measurements

Only after ROCm and bench review, choose among MTP PP attribution, residual
target suffix rebuilds, ROCm long-context PP scaling, or focused128k validation.
Reuse existing diagnostics for the chosen question; avoid restarting every
profile/context. COMMON-005 decode remains deferred and defaults stay OFF.
This does not promise CLI/bench numeric equality or mark ROCm model/performance
validation complete before the Windows results arrive.

See [Vulkan normal ABBA results](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md).
