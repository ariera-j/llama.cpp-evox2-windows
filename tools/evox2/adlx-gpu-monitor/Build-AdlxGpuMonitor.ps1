[CmdletBinding()]
param(
    [string]$AdlxRoot,
    [string]$BuildDir,
    [string]$CMakePath,
    [switch]$NoFetch,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$expectedTag = 'v2.0'
$expectedCommit = '1ca2dd42f1df8cbd045489b7a20013a07692a446'
$adlxRepo = 'https://github.com/GPUOpen-LibrariesAndSDKs/ADLX.git'

function Resolve-CMake {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "CMake was not found at -CMakePath '$ExplicitPath'."
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe')
    }

    if (${env:ProgramFiles(x86)}) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $installations = @(
                & $vswhere `
                    -products * `
                    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                    -property installationPath
            )

            foreach ($installation in $installations) {
                if ($installation) {
                    $candidates += (
                        Join-Path $installation `
                            'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
                    )
                }
            }
        }

        $candidates += (
            Join-Path ${env:ProgramFiles(x86)} `
                'Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        )
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @'
cmake.exe was not found.

Install CMake, add it to PATH, or pass -CMakePath explicitly.
For Visual Studio Build Tools, a typical path is:
  C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe
'@
}

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

$requiredHeader = Join-Path $AdlxRoot 'SDK\Include\IPerformanceMonitoring.h'

if (-not (Test-Path -LiteralPath $requiredHeader)) {
    if ($NoFetch) {
        throw "ADLX SDK was not found at '$AdlxRoot' and -NoFetch was specified."
    }

    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw 'git.exe was not found in PATH. Install Git or pass -AdlxRoot pointing to an ADLX v2.0 checkout.'
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
    & git.exe clone --branch $expectedTag --depth 1 $adlxRepo $AdlxRoot
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $requiredHeader)) {
    throw "ADLX SDK is missing required header: $requiredHeader"
}

$gitDir = Join-Path $AdlxRoot '.git'
if (Test-Path -LiteralPath $gitDir) {
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        throw 'git.exe was not found in PATH, so the ADLX SDK commit cannot be verified.'
    }

    $actualCommit = (& git.exe -C $AdlxRoot rev-parse HEAD).Trim()
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

$cmake = Resolve-CMake -ExplicitPath $CMakePath
Write-Host "CMake: $cmake"

Write-Host 'Configuring...'
& $cmake `
    -S $scriptRoot `
    -B $BuildDir `
    -G 'Visual Studio 17 2022' `
    -A x64 `
    "-DADLX_ROOT=$AdlxRoot"

if ($LASTEXITCODE -ne 0) {
    throw "CMake configure failed with exit code $LASTEXITCODE"
}

Write-Host 'Building Release...'
& $cmake --build $BuildDir --config Release --parallel 4

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
