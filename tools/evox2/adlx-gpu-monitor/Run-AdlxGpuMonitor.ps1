[CmdletBinding()]
param(
    [int]$DurationSeconds = 30,
    [int]$IntervalMs = 2000,
    [int]$GpuIndex = 0,
    [string]$Output,
    [switch]$ListGpus
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $scriptRoot 'build\bin\evox2-adlx-gpu-monitor.exe'

if (-not (Test-Path -LiteralPath $exe)) {
    throw "Monitor executable was not found. Build it first with .\Build-AdlxGpuMonitor.ps1`nExpected: $exe"
}

if ($ListGpus) {
    & $exe --list-gpus
    if ($LASTEXITCODE -ne 0) {
        throw "GPU listing failed with exit code $LASTEXITCODE"
    }
    exit 0
}

if ($DurationSeconds -lt 0) {
    throw 'DurationSeconds must be >= 0.'
}
if ($IntervalMs -lt 100) {
    throw 'IntervalMs must be >= 100.'
}
if ($GpuIndex -lt 0) {
    throw 'GpuIndex must be >= 0.'
}

if (-not $Output) {
    $logDir = Join-Path $scriptRoot 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Output = Join-Path $logDir "adlx-gpu-metrics-$stamp.csv"
}

$args = @(
    '--duration', $DurationSeconds.ToString(),
    '--interval-ms', $IntervalMs.ToString(),
    '--gpu-index', $GpuIndex.ToString(),
    '--output', $Output
)

Write-Host 'Running ADLX GPU monitor...'
Write-Host "  executable : $exe"
Write-Host "  output     : $Output"
Write-Host "  duration   : $DurationSeconds s"
Write-Host "  interval   : $IntervalMs ms"
Write-Host "  gpu index  : $GpuIndex"
Write-Host ''

& $exe @args
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "ADLX GPU monitor failed with exit code $exitCode"
}

Write-Host ''
Write-Host "Saved: $Output"

if (Test-Path -LiteralPath $Output) {
    Write-Host ''
    Write-Host 'First rows:'
    Get-Content -LiteralPath $Output -TotalCount 5
}
