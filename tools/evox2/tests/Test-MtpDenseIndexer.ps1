#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LocalConfig = '',
    [string]$BuildKey = 'R4QsaUnionVulkan',
    [string]$ModelKey = 'UnslothPle16',
    [string]$DraftModelKey = 'UnslothMtp',
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
$reportDirectory = Join-Path $repo ('evox2-logs\tests\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-mtp-dense-indexer')
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
        $failure = @($tail | Where-Object { $_ -match '^MTP (dense indexer|indexer policy): FAIL:' })
        $detail = if ($failure.Count) { $failure[-1] } else { 'No completed gate marker; inspect the native logs.' }
        throw "$Name failed (exit=$exitCode): $detail Logs are retained in $reportDirectory"
    }
    Get-Content -LiteralPath $stdout | ForEach-Object { Write-Host $_ }
}

try {
    $parsePaths = @(
        $PSCommandPath, (Join-Path $benchmark 'Evox2.Benchmark.psm1'),
        (Join-Path $benchmark 'Measure-LlamaCli.ps1'),
        (Join-Path $repo 'tools\evox2\build\Build-Vulkan.ps1'),
        (Join-Path $repo 'tools\evox2\build\Build-ROCm.ps1'),
        (Join-Path $repo 'tools\evox2\build\Evox2.Build.psm1')
    )
    $plans = @(Get-ChildItem -LiteralPath (Join-Path $benchmark 'configs') -Filter 'qwen38-r4-*.psd1' -File)
    $parsePaths += @($plans | ForEach-Object { $_.FullName })
    foreach ($path in $parsePaths) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Assert-Check (-not $errors.Count) "$path : $($errors.Message -join '; ')"
    }
    foreach ($file in $plans) {
        $plan = Import-PowerShellDataFile -LiteralPath $file.FullName
        Assert-Check ($plan.Defaults.Environment.ContainsKey('LLAMA_MTP_SKIP_DENSE_INDEXER') -and
            $null -eq $plan.Defaults.Environment.LLAMA_MTP_SKIP_DENSE_INDEXER) "$($file.Name): inherited candidate is not cleared."
    }
    $expectedPlans = @{
        'check' = @('control-mtp-off', 'A-normal', 'B-normal', 'A-wall', 'B-wall')
        'wall' = @('A-wall', 'B-wall')
        'abba' = @('A1', 'B1', 'B2', 'A2')
    }
    foreach ($kind in $expectedPlans.Keys) {
        $path = Join-Path $benchmark "configs\qwen38-r4-mtp-dense-indexer-$kind.psd1"
        $plan = Import-PowerShellDataFile -LiteralPath $path
        Assert-Check ($plan.Jobs.Count -eq 1 -and $plan.Jobs[0].Cases.Count -eq 1) "${kind}: unexpected job/case expansion."
        $job = $plan.Jobs[0]
        $labels = @($job.Variants | ForEach-Object { $_.Name })
        Assert-Check (($labels -join ',') -eq ($expectedPlans[$kind] -join ',')) "${kind}: wrong variant order/count."
        $expectedContext = if ($kind -eq 'check') { 32768 } else { 262144 }
        Assert-Check ($job.Cases[0].Parameters.Context -eq $expectedContext) "${kind}: wrong context."
        Assert-Check ($plan.Defaults.CliParameters.PromptCacheMiB -eq 0 -and
            ($plan.Defaults.CliParameters.ExtraArgs -join ' ') -match '--ctx-checkpoints 0t') "${kind}: state reuse must be disabled."
        foreach ($variant in $job.Variants) {
            $isControl = $variant.Name -eq 'control-mtp-off'
            $candidate = if ($variant.Name.StartsWith('A')) { '0' } else { '1' }
            $diag = if ($variant.Name.EndsWith('-wall')) { 'wall' } else { 'off' }
            Assert-Check ($variant.Environment.LLAMA_MTP_SKIP_DENSE_INDEXER -eq $candidate -and
                $variant.Environment.LLAMA_MTP_DIAG -eq $diag) "$kind/$($variant.Name): wrong candidate/diagnostic setting."
            if (-not $isControl) {
                Assert-Check ($variant.Parameters.Mtp -eq $true -and $variant.Parameters.DraftMax -eq 2 -and
                    $variant.Parameters.DraftPMin -eq 0) "$kind/$($variant.Name): both candidate arms must keep MTP ON."
            } else {
                Assert-Check (-not $plan.Defaults.CliParameters.Mtp -and -not $variant.Parameters.ContainsKey('Mtp')) 'MTP OFF control changed.'
            }
            if ($kind -eq 'abba') {
                Assert-Check ($variant.Environment.EVOX2_ABBA_RUN -eq $variant.Name) 'ABBA repetition identity missing.'
            }
        }
    }
    $a = 'create_memory: MTP dense indexer: requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled'
    $b = 'create_memory: MTP dense indexer: requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block'
    $refused = 'create_memory: MTP dense indexer: requested=1 eligible=0 omitted=0 layer=48 ratio=4 reason=compressed'
    foreach ($fixture in @(
        @{ Text = $a; Setting = '0'; Mtp = $true; Status = 'Verified' },
        @{ Text = $b; Setting = '1'; Mtp = $true; Status = 'Verified' },
        @{ Text = ''; Setting = '1'; Mtp = $true; Status = 'Missing' },
        @{ Text = $a; Setting = '1'; Mtp = $true; Status = 'Mismatch' },
        @{ Text = $refused; Setting = '1'; Mtp = $true; Status = 'NotApplied' },
        @{ Text = ($b + "`nMTP dense indexer: broken"); Setting = '1'; Mtp = $true; Status = 'Malformed' },
        @{ Text = ''; Setting = '1'; Mtp = $false; Status = 'MtpDisabled' },
        @{ Text = ''; Setting = ''; Mtp = $true; Status = 'NotRequested' }
    )) {
        $evidence = @(Get-Evox2MtpDenseIndexerEvidence -Text $fixture.Text -Setting $fixture.Setting -Mtp $fixture.Mtp)
        Assert-Check ($evidence.Count -eq 1 -and $evidence[0].Status -eq $fixture.Status) 'Candidate evidence classification/pipeline fixture failed.'
    }
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
        Invoke-NativeGate -Executable (Join-Path $binDir 'test-mtp-indexer-policy.exe') -Arguments @() `
            -Name 'policy' -PassMarker 'MTP indexer policy: PASS'
        $report.PolicyTest = 'Passed'
        if ($RunModelTests) {
            $report.ModelTest = 'Running'
            $main = Get-Evox2ConfigEntry -Config $config -Section Models -Key $ModelKey
            $draft = Get-Evox2ConfigEntry -Config $config -Section Models -Key $DraftModelKey
            $mainPath = if ([IO.Path]::IsPathRooted($main.Path)) { $main.Path } else { Join-Path $repo $main.Path }
            $draftPath = if ([IO.Path]::IsPathRooted($draft.Path)) { $draft.Path } else { Join-Path $repo $draft.Path }
            $mainPath = (Resolve-Path -LiteralPath $mainPath).ProviderPath
            $draftPath = (Resolve-Path -LiteralPath $draftPath).ProviderPath
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
                $env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'; $env:GGML_VK_GET_ROWS_128X4 = '0'; $env:GGML_VK_QSA_UNION = '1'
                Invoke-NativeGate -Executable (Join-Path $binDir 'test-mtp-dense-indexer.exe') `
                    -Arguments @('-m', $mainPath, '-md', $draftPath, '-ngl', "$GpuLayers") `
                    -Name 'model' -PassMarker 'MTP dense indexer: PASS ('
            } finally {
                foreach ($name in $savedEnvironment.Keys) {
                    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
                }
            }
            $report.ModelTest = 'Passed'; $report.Status = 'Complete'
            Write-Host 'Dense MTP indexer policy and model/state/rollback gates passed.'
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
