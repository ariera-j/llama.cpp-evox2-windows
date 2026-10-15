[CmdletBinding()]
param(
    [string]$AdlxRoot,
    [string]$BuildDir,
    [switch]$NoFetch,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$expectedTag = 'v2.0'
$expectedCommit = '1ca2dd42f1df8cbd045489b7a20013a07692a446'
$adlxRepo = 'https://github.com/GPUOpen-LibrariesAndSDKs/ADLX.git'

if (-not $BuildDir) {
    $BuildDir = Join-Path $scriptRoot 'build'
}

$usingDefaultAdlxRoot = -not $AdlxRoot
if (-not $AdlxRoot) {
    $AdlxRoot = Join-Path $scriptRoot '_deps\ADLX-v2.0'
}

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) {
    Write-Host "Removing build directory: $BuildDir"
    Remove-Item -LiteralPath $BuildDir -Recurse -Force
}

$requiredHeader = Join-Path $AdlxRoot 'SDK\Include\IPerformanceMonitoring3.h'

if (-not (Test-Path -LiteralPath $requiredHeader)) {
    if ($NoFetch) {
        throw "ADLX SDK was not found at '$AdlxRoot' and -NoFetch was specified."
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git was not found in PATH. Install Git or pass -AdlxRoot pointing to an ADLX v2.0 checkout.'
    }

    $parent = Split-Path -Parent $AdlxRoot
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    if (Test-Path -LiteralPath $AdlxRoot) {
        $items = @(Get-ChildItem -LiteralPath $AdlxRoot -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            throw "ADLX destination exists but is not a usable SDK checkout: $AdlxRoot"
        }
    }

    Write-Host "Cloning AMD ADLX $expectedTag..."
    & git clone --branch $expectedTag --depth 1 $adlxRepo $AdlxRoot
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $requiredHeader)) {
    throw "ADLX SDK is missing required header: $requiredHeader"
}

$gitDir = Join-Path $AdlxRoot '.git'
if (Test-Path -LiteralPath $gitDir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git was not found in PATH, so the ADLX SDK commit cannot be verified.'
    }

    $actualCommit = (& git -C $AdlxRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to read ADLX checkout commit.'
    }

    if ($usingDefaultAdlxRoot -and $actualCommit -ne $expectedCommit) {
        throw "Default ADLX checkout is not the pinned v2.0 commit. Expected $expectedCommit, got $actualCommit."
    }

    if ($actualCommit -ne $expectedCommit) {
        Write-Warning "Custom ADLX checkout is not the pinned v2.0 commit. Expected $expectedCommit, got $actualCommit."
    } else {
        Write-Host "ADLX commit: $actualCommit (v2.0)"
    }
} else {
    Write-Warning 'ADLX root is not a Git checkout; version/commit cannot be verified.'
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'cmake was not found in PATH.'
}

Write-Host 'Configuring...'
& cmake -S $scriptRoot -B $BuildDir -G 'Visual Studio 17 2022' -A x64 "-DADLX_ROOT=$AdlxRoot"
if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed with exit code $LASTEXITCODE"
}

Write-Host 'Building Release...'
& cmake --build $BuildDir --config Release --parallel 4
if ($LASTEXITCODE -ne 0) {
    throw "CMake build failed with exit code $LASTEXITCODE"
}

$exe = Join-Path $BuildDir 'bin\evox2-adlx-gpu-monitor.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    throw "Build completed but executable was not found: $exe"
}

Write-Host ''
Write-Host 'Build completed:'
Write-Host "  $exe"
Write-Host ''
Write-Host 'Next:'
Write-Host '  .\Run-AdlxGpuMonitor.ps1 -ListGpus'
Write-Host '  .\Run-AdlxGpuMonitor.ps1 -DurationSeconds 30 -IntervalMs 2000'
