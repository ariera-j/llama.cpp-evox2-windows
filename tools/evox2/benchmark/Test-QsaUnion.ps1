#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BinDir,

    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$Backend = 'Vulkan0',

    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$BinDir = [IO.Path]::GetFullPath($BinDir)
$exe = Join-Path $BinDir 'test-backend-ops.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Missing backend test binary: $exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $OutputDir = Join-Path $repoRoot "evox2-logs\$stamp-qsa-union-tests"
}
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
[void](New-Item -ItemType Directory -Path $OutputDir -Force)
$utf8 = New-Object System.Text.UTF8Encoding($false)

# 18 dense-reference cases, including unsupported-input fallbacks.
$filter = 'qsa_union=1'
$arguments = '-b "{0}" -o FLASH_ATTN_EXT -p "{1}"' -f $Backend, $filter
$environmentNames = @(
    'GGML_VK_QSA_UNION',
    'GGML_VK_QSA_UNION_MIN_KV',
    'GGML_VK_FA_SPARSE_DISABLE',
    'GGML_VK_DISABLE_F16',
    'GGML_VK_DISABLE_COOPMAT',
    'GGML_VK_DISABLE_COOPMAT2',
    'GGML_VK_PERF_LOGGER',
    'GGML_VK_PERF_LOGGER_FREQUENCY',
    'GGML_VK_PERF_LOGGER_CONCURRENT'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$results = @()
try {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($mode in @('0', '1')) {
        $label = if ($mode -eq '1') { 'on' } else { 'off' }
        [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION', $mode, 'Process')
        Write-Host "QSA grouped-union correctness: $label / $Backend"

        # Read both streams asynchronously: native stderr is ordinary log output,
        # and must not trigger PowerShell 5.1 NativeCommandError handling.
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $exe
        $info.Arguments = $arguments
        $info.WorkingDirectory = $BinDir
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $info
        try {
            [void]$process.Start()
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            $exitCode = $process.ExitCode
        } finally {
            $process.Dispose()
        }
        [IO.File]::WriteAllText((Join-Path $OutputDir "$label.stdout.log"), $stdout, $utf8)
        [IO.File]::WriteAllText((Join-Path $OutputDir "$label.stderr.log"), $stderr, $utf8)
        $allOutput = $stdout + "`n" + $stderr
        $ranAllTests = $allOutput -match '(?m)^\s*18/18 tests passed\s*$'
        $skippedSeen = $allOutput -match '(?i)not supported'
        $switchSeen = $allOutput.Contains("QSA grouped-union = $label")
        $activeSeen = $allOutput.Contains("qsa-union active (r5)")
        $fallbackSeen = $allOutput.Contains("qsa-union fallback:")
        $passed = $exitCode -eq 0 -and $ranAllTests -and $switchSeen -and -not $skippedSeen -and
            ($mode -eq '0' -or ($activeSeen -and $fallbackSeen))
        $results += [ordered]@{
            Mode = $label
            ExitCode = $exitCode
            ExpectedTests = 18
            AllTestsRanAndPassed = $ranAllTests
            SwitchSeen = $switchSeen
            SkippedSeen = $skippedSeen
            ActiveSeen = $activeSeen
            FallbackSeen = $fallbackSeen
            Passed = $passed
        }
        $summary = [ordered]@{
            Executable = $exe
            ExecutableSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
            Backend = $Backend
            Arguments = $arguments
            Results = @($results)
        }
        [IO.File]::WriteAllText((Join-Path $OutputDir 'results.json'),
            ($summary | ConvertTo-Json -Depth 6), $utf8)
        if (-not $passed) {
            throw "QSA grouped-union $label failed, was skipped, or used another binary/backend. Logs: $OutputDir"
        }
        Write-Host '18/18 tests passed.'
    }
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
Write-Host "Correctness OFF/ON passed. Logs: $OutputDir"
