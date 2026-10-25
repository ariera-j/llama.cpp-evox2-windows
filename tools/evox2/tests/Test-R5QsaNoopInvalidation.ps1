#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LocalConfig = '',
    [string]$BuildKey = 'R5MtpNoopVulkan',
    [string]$ModelKey = 'UnslothPle16',
    [ValidateRange(0, 9999)][int]$GpuLayers = 999,
    [switch]$SourceOnly,
    [switch]$RunModelTests
)
$ErrorActionPreference = 'Stop'
if ($SourceOnly -and $RunModelTests) { throw 'SourceOnly cannot run the model gate.' }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$benchmark = Join-Path $repo 'tools\evox2\benchmark'
Import-Module (Join-Path $repo 'tools\evox2\lib\Evox2.Common.psm1') -Force
Import-Module (Join-Path $benchmark 'Evox2.Benchmark.psm1') -Force
$reportDirectory = Join-Path $repo ('evox2-logs\tests\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-qsa-noop-invalidation')
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$report = [ordered]@{
    SchemaVersion = 1; StartedAt = (Get-Date).ToString('o'); Status = 'Incomplete'
    SourceChecks = 'NotRun'; PolicyTest = 'NotRun'; ModelTest = 'NotRun'
    ReportDirectory = $reportDirectory; NativeRuns = @()
}

function Assert-Check([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-NativeGate([string]$Executable, [string[]]$Arguments, [string]$Name, [string]$PassMarker) {
    $runtime = Test-Evox2RuntimeArtifacts -Executable $Executable -Manifest $manifest
    Assert-Check ($runtime.Status -eq 'Verified') "$Name executable/DLL identity is not Verified. Rebuild and refresh the manifest."
    $stdout = Join-Path $reportDirectory ($Name + '.stdout.log')
    $stderr = Join-Path $reportDirectory ($Name + '.stderr.log')
    Write-Host "Running $Name; logs: $reportDirectory"
    $startArgs = @{
        FilePath = $Executable; WorkingDirectory = (Split-Path -Parent $Executable)
        RedirectStandardOutput = $stdout; RedirectStandardError = $stderr
        NoNewWindow = $true; PassThru = $true
    }
    if ($Arguments.Count) {
        $startArgs.ArgumentList = (@($Arguments | ForEach-Object {
            ConvertTo-Evox2WindowsArgument -Value $_
        }) -join ' ')
    }
    $process = Start-Process @startArgs
    try {
        [void]$process.Handle # retain a native process handle before waiting
        $process.WaitForExit(); $process.Refresh()
        $exitCode = $process.ExitCode
    } finally { $process.Dispose() }
    $text = [IO.File]::ReadAllText($stdout)
    $report.NativeRuns += [PSCustomObject]@{
        Name = $Name; ExitCode = $exitCode; StdOut = $stdout; StdErr = $stderr
        Executable = $Executable; RuntimeArtifactDigest = $runtime.Digest
        Arguments = @($Arguments)
    }
    if ($null -eq $exitCode -or $exitCode -ne 0 -or -not $text.Contains($PassMarker)) {
        $tail = @(Get-Content -LiteralPath $stderr -Tail 30)
        $tail | ForEach-Object { Write-Host $_ }
        $failure = @($tail | Where-Object { $_ -match '^QSA no-op (invalidation|policy): FAIL:' })
        $detail = if ($failure.Count) { $failure[-1] } else { 'No completed gate marker; inspect the native logs.' }
        throw "$Name failed (exit=$exitCode): $detail Logs are retained in $reportDirectory"
    }
    Get-Content -LiteralPath $stdout | ForEach-Object { Write-Host $_ }
}

try {
    $parsePaths = @(
        $PSCommandPath, (Join-Path $benchmark 'Evox2.Benchmark.psm1'),
        (Join-Path $benchmark 'Measure-LlamaCli.ps1'),
        (Join-Path $benchmark 'Invoke-BenchmarkMatrix.ps1'),
        (Join-Path $repo 'tools\evox2\build\Build-Vulkan.ps1'),
        (Join-Path $repo 'tools\evox2\build\Build-ROCm.ps1'),
        (Join-Path $repo 'tools\evox2\build\Evox2.Build.psm1')
    )
    $plans = @(Get-ChildItem -LiteralPath (Join-Path $benchmark 'configs') -Filter 'qwen38-r5-mtp-noop-*.psd1' -File)
    Assert-Check ($plans.Count -eq 4) 'Expected r5 Vulkan/ROCm short and ABBA plan files not found.'
    $parsePaths += @($plans | ForEach-Object { $_.FullName })
    foreach ($path in $parsePaths) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Assert-Check (-not $errors.Count) "$path : $($errors.Message -join '; ')"
    }
    $expectedVariants = @{
        'check' = @('A-normal', 'B-normal', 'A-proof', 'B-proof')
        'rocm-check' = @('A-normal', 'B-normal', 'A-proof', 'B-proof')
        'abba' = @('A1', 'B1', 'B2', 'A2')
        'rocm-abba' = @('A1', 'B1', 'B2', 'A2')
    }
    foreach ($kind in @('check', 'rocm-check', 'abba', 'rocm-abba')) {
        $path = Join-Path $benchmark "configs\qwen38-r5-mtp-noop-$kind.psd1"
        $plan = Import-PowerShellDataFile -LiteralPath $path
        Assert-Check ($plan.Defaults.Environment.ContainsKey('LLAMA_QSA_SKIP_NOOP_INVALIDATION') -and
            $null -eq $plan.Defaults.Environment.LLAMA_QSA_SKIP_NOOP_INVALIDATION -and
            $null -eq $plan.Defaults.Environment.LLAMA_QSA_NOOP_TRACE) "$kind inherited candidate/trace is not cleared."
        $expectedJobs = if ($kind -in @('check', 'rocm-check')) { 1 } else { 3 }
        Assert-Check ($plan.Jobs.Count -eq $expectedJobs) "$kind unexpected job count."
        foreach ($job in $plan.Jobs) {
            Assert-Check ($job.Cases.Count -eq 1) "$kind must have exactly one case per job."
            $context = [int]$job.Cases[0].Parameters.Context
            $expectedContext = if ($kind -in @('check', 'rocm-check')) { 32768 }
                elseif ($job.Name -match '128k$') { 131072 }
                elseif ($job.Name -match '64k$') { 65536 }
                elseif ($job.Name -match '256k$') { 262144 }
                else { throw "Unexpected job $($job.Name)" }
            Assert-Check ($context -eq $expectedContext) "$kind/$($job.Name) wrong context."
            $expectedBuild = if ($kind -in @('rocm-abba', 'rocm-check')) { 'R5MtpNoopROCm' } else { 'R5MtpNoopVulkan' }
            Assert-Check ($job.BuildKeys.Count -eq 1 -and $job.BuildKeys[0] -eq $expectedBuild) "$kind/$($job.Name) wrong build."
            # A plan must never silently target the other backend or inherit its
            # launch-only flags. These checks run even in -SourceOnly mode.
            if ($kind -in @('rocm-abba', 'rocm-check')) {
                Assert-Check ($job.Environment.ContainsKey('GGML_VK_QSA_UNION') -and
                    $null -eq $job.Environment.GGML_VK_QSA_UNION -and
                    $job.Environment.ContainsKey('GGML_VK_QSA_UNION_MIN_KV') -and
                    $null -eq $job.Environment.GGML_VK_QSA_UNION_MIN_KV) "$kind/$($job.Name) Vulkan-specific overrides must be unset."
            } else {
                Assert-Check ($job.Environment.GGML_VK_QSA_UNION -eq '1' -and
                    $job.Environment.GGML_VK_QSA_UNION_MIN_KV -eq '32768') "$kind/$($job.Name) Vulkan QSA union overrides changed."
            }
            $labels = @($job.Variants | ForEach-Object { $_.Name })
            Assert-Check (($labels -join ',') -eq ($expectedVariants[$kind] -join ',')) "$kind/$($job.Name) invalid variant order."
            Assert-Check ($plan.Defaults.CliParameters.PromptCacheMiB -eq 0 -and
                ($plan.Defaults.CliParameters.ExtraArgs -join ' ') -match '--ctx-checkpoints 0t') "${kind}: cache/checkpoint defaults changed."
            foreach ($variant in $job.Variants) {
                $candidate = if ($variant.Name.StartsWith('A')) { '0' } else { '1' }
                $trace = if ($variant.Name.EndsWith('-proof')) { '1' } else { '0' }
                Assert-Check ($variant.Environment.LLAMA_MTP_SKIP_DENSE_INDEXER -eq '1' -and
                    $variant.Environment.LLAMA_QSA_SKIP_NOOP_INVALIDATION -eq $candidate -and
                    $variant.Environment.LLAMA_QSA_NOOP_TRACE -eq $trace -and
                    $variant.Environment.LLAMA_MTP_DIAG -eq 'off') "$kind/$($variant.Name) toggle/dense/trace mismatch."
                Assert-Check ($variant.Parameters.Mtp -eq $true -and $variant.Parameters.DraftMax -eq 2 -and
                    $variant.Parameters.DraftPMin -eq 0) "$kind/$($variant.Name) must preserve MTP ON/DraftMax2."
                if ($kind -notin @('check', 'rocm-check')) {
                    Assert-Check ($variant.Environment.EVOX2_ABBA_RUN -eq $variant.Name) "$kind ABBA identity missing."
                }
            }
        }
    }
    $a = 'llama_memory_hybrid_idx: QSA no-op invalidation: requested=0 eligible=1 enabled=0 target=1 kpool=4 streams=1 seq_max=1 reason=disabled'
    $b = 'llama_memory_hybrid_idx: QSA no-op invalidation: requested=1 eligible=1 enabled=1 target=1 kpool=4 streams=1 seq_max=1 reason=target_single_sequence'
    $draft = 'llama_memory_hybrid_idx: QSA no-op invalidation: requested=1 eligible=0 enabled=0 target=0 kpool=4 streams=0 seq_max=1 reason=not_target'
    $refused = 'llama_memory_hybrid_idx: QSA no-op invalidation: requested=1 eligible=0 enabled=0 target=1 kpool=4 streams=1 seq_max=2 reason=unsupported_cache'
    foreach ($fixture in @(
        @{ Text = $a; Setting = '0'; Status = 'Verified' },
        @{ Text = $b; Setting = '1'; Status = 'Verified' },
        @{ Text = ($b + "`n" + $draft); Setting = '1'; Status = 'Verified' },
        @{ Text = $draft; Setting = '1'; Status = 'Missing' },
        @{ Text = ''; Setting = '1'; Status = 'Missing' },
        @{ Text = $a; Setting = '1'; Status = 'Mismatch' },
        @{ Text = $b; Setting = '0'; Status = 'Mismatch' },
        @{ Text = $refused; Setting = '1'; Status = 'NotApplied' },
        @{ Text = ($b + "`nQSA no-op invalidation: broken"); Setting = '1'; Status = 'Malformed' },
        @{ Text = ($b + "`n" + $b); Setting = '1'; Status = 'Malformed' },
        @{ Text = $b.Replace('streams=1', 'streams=2'); Setting = '1'; Status = 'Mismatch' },
        @{ Text = $b.Replace('reason=target_single_sequence', 'reason=disabled'); Setting = '1'; Status = 'Mismatch' },
        @{ Text = ''; Setting = ''; Status = 'NotRequested' }
    )) {
        $evidence = @(Get-Evox2QsaNoopInvalidationEvidence -Text $fixture.Text -Setting $fixture.Setting)
        Assert-Check ($evidence.Count -eq 1 -and $evidence[0].Status -eq $fixture.Status) 'Target evidence classification/pipeline fixture failed.'
    }
    # MTP OFF still has the DEFAULT target context: the parser deliberately has no Mtp parameter.
    Assert-Check ((Get-Evox2QsaNoopInvalidationEvidence -Text $b -Setting '1').Enabled) 'MTP OFF target eligibility must remain visible.'
    $report.SourceChecks = 'Passed'
    if ($SourceOnly) {
        $report.Status = 'SourceChecksPassed'
        Write-Host 'Source checks passed. Native policy/model gates NOT RUN; rebuild before proceeding.'
    } else {
        if ([string]::IsNullOrWhiteSpace($LocalConfig)) { $LocalConfig = Join-Path $benchmark 'configs\local.psd1' }
        $resolvedConfig = (Resolve-Path -LiteralPath $LocalConfig -ErrorAction Stop).ProviderPath
        $config = Import-Evox2LocalConfig -Path $resolvedConfig -Required
        $build = Get-Evox2ConfigEntry -Config $config -Section Builds -Key $BuildKey
        $binDir = if ([IO.Path]::IsPathRooted($build.BinDir)) { $build.BinDir } else { Join-Path $repo $build.BinDir }
        $binDir = (Resolve-Path -LiteralPath $binDir).ProviderPath
        $cli = Join-Path $binDir 'llama-cli.exe'
        $manifest = Read-Evox2BuildManifest -Executable $cli
        Assert-Check ($null -ne $manifest -and $manifest.BuildIdentity.Status -eq 'Verified') 'Build manifest/source identity is not Verified.'
        $report.BuildIdentity = $manifest.BuildIdentity
        $report.PolicyTest = 'Running'
        Invoke-NativeGate -Executable (Join-Path $binDir 'test-qsa-noop-policy.exe') -Arguments @() `
            -Name 'policy' -PassMarker 'QSA no-op policy: PASS'
        $report.PolicyTest = 'Passed'
        if ($RunModelTests) {
            $report.ModelTest = 'Running'
            $main = Get-Evox2ConfigEntry -Config $config -Section Models -Key $ModelKey
            $mainPath = if ([IO.Path]::IsPathRooted($main.Path)) { $main.Path } else { Join-Path $repo $main.Path }
            $mainPath = (Resolve-Path -LiteralPath $mainPath).ProviderPath
            $savedEnvironment = @{}
            $clear = @(Get-ChildItem Env: | Where-Object {
                $_.Name -match '^(LLAMA_MTP_|LLAMA_QSA_|QWEN4EXP_QSA_|GGML_VK_)' -or $_.Name -eq 'LLAMA_GRAPH_REUSE_DISABLE'
            } | ForEach-Object { $_.Name })
            $names = @($clear + @('GGML_VK_MOE_LEGACY_TILE_SELECTION', 'GGML_VK_GET_ROWS_128X4', 'GGML_VK_QSA_UNION') | Sort-Object -Unique)
            foreach ($name in $names) {
                $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                [Environment]::SetEnvironmentVariable($name, $null, 'Process')
            }
            try {
                $env:GGML_VK_QSA_UNION = '1'; $env:GGML_VK_QSA_UNION_MIN_KV = '32768'
                Invoke-NativeGate -Executable (Join-Path $binDir 'test-qsa-noop-invalidation.exe') `
                    -Arguments @('-m', $mainPath, '-ngl', "$GpuLayers") `
                    -Name 'model' -PassMarker 'QSA no-op invalidation: PASS ('
            } finally {
                foreach ($name in $savedEnvironment.Keys) {
                    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
                }
            }
            $report.ModelTest = 'Passed'; $report.Status = 'Complete'
            Write-Host 'Target QSA no-op policy and model/state/rollback gates passed.'
        } else {
            $report.Status = 'PolicyPassedModelNotRun'
            Write-Host 'Policy gate passed; model/state/rollback gate NOT RUN. Use -RunModelTests before long measurements.'
        }
    }
} catch {
    if ($report.PolicyTest -eq 'Running') { $report.PolicyTest = 'Failed' }
    if ($report.ModelTest -eq 'Running') { $report.ModelTest = 'Failed' }
    $report.Status = 'Failed'; $report.Error = $_.Exception.Message
    throw
} finally {
    $report.FinishedAt = (Get-Date).ToString('o')
    Write-Evox2Json -InputObject $report -Path (Join-Path $reportDirectory 'result.json') -Depth 24
    Write-Host "Gate report: $(Join-Path $reportDirectory 'result.json')"
}
