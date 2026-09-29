#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BuildDir = '',

    [ValidateSet('Release', 'Debug', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',

    [ValidateRange(1, 64)]
    [int]$Parallel = 4,

    [string]$LlvmBin = '',
    [string]$VulkanSdk = '',

    [switch]$ConfigureOnly,
    [switch]$BuildOnly,
    [switch]$ManifestOnly,

    [switch]$SkipSmoke,

    [string[]]$ExtraCMakeArgs = @()
)

$ErrorActionPreference = 'Stop'

if (($ConfigureOnly -and $BuildOnly) -or
    ($ManifestOnly -and ($ConfigureOnly -or $BuildOnly))) {
    throw 'Use only one of -ConfigureOnly, -BuildOnly, or -ManifestOnly.'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
$buildModule = Join-Path $scriptDir 'Evox2.Build.psm1'

Import-Module $commonModule -Force
Import-Module $buildModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot 'build-vulkan-r3'
}
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
$BinDir = Join-Path $BuildDir "bin\$Configuration"

$cmake = (Get-Command cmake -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source

$savedPath = $env:PATH
$savedVulkanSdk = $env:VULKAN_SDK

try {
    if (-not [string]::IsNullOrWhiteSpace($VulkanSdk)) {
        $env:VULKAN_SDK = [IO.Path]::GetFullPath($VulkanSdk)
    } elseif (-not [string]::IsNullOrWhiteSpace($env:VULKAN_SDK)) {
        $VulkanSdk = $env:VULKAN_SDK
    }

    if (-not [string]::IsNullOrWhiteSpace($LlvmBin)) {
        $LlvmBin = [IO.Path]::GetFullPath($LlvmBin)
        $env:PATH = "$LlvmBin;$env:PATH"
    } else {
        $clangCommand = Get-Command clang.exe -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($clangCommand) {
            $LlvmBin = Split-Path -Parent $clangCommand.Source
        }
    }

    if (-not $ManifestOnly -and -not $BuildOnly) {
        if ([string]::IsNullOrWhiteSpace($env:VULKAN_SDK)) {
            throw 'VULKAN_SDK is not set. Pass -VulkanSdk or configure the shell first.'
        }
    }

    $toolchainFile = Join-Path $RepoRoot 'cmake\x64-windows-llvm.cmake'

    $configureArgs = @(
        '-S', $RepoRoot,
        '-B', $BuildDir,
        '-G', 'Ninja Multi-Config',
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
        '-DGGML_VULKAN=ON',
        '-DGGML_NATIVE=OFF',
        '-DGGML_BACKEND_DL=ON',
        '-DGGML_CPU_ALL_VARIANTS=ON',
        '-DGGML_OPENMP=ON',
        '-DGGML_OPENMP_FETCH=ON',
        '-DLLAMA_BUILD_BORINGSSL=ON',
        '-DLLAMA_BUILD_EXAMPLES=OFF',
        '-DLLAMA_BUILD_TESTS=ON',
        '-DLLAMA_BUILD_TOOLS=ON',
        '-DLLAMA_BUILD_SERVER=ON',
        '-DLLAMA_BUILD_UI=OFF',
        '-DGGML_RPC=ON'
    )
    if ($ExtraCMakeArgs.Count -gt 0) {
        $configureArgs += $ExtraCMakeArgs
    }

    $targets = @(
        'llama-cli',
        'llama-server',
        'llama-bench',
        'test-backend-ops'
    )

    $configureRecord = [ordered]@{
        Executed  = $false
        Generator = 'Ninja Multi-Config'
        Arguments = @($configureArgs)
        ExtraArgs = @($ExtraCMakeArgs)
    }

    $buildRecord = [ordered]@{
        Executed  = $false
        Parallel  = $Parallel
        Targets   = @($targets)
    }

    if (-not $ManifestOnly -and -not $BuildOnly) {
        Write-Host 'Configuring Vulkan build...'
        & $cmake @configureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "CMake configure failed with exit code $LASTEXITCODE."
        }
        $configureRecord.Executed = $true
    }

    if (-not $ManifestOnly -and -not $ConfigureOnly) {
        Write-Host 'Building Vulkan targets...'
        $buildArgs = @(
            '--build', $BuildDir,
            '--config', $Configuration,
            '--parallel', "$Parallel",
            '--target'
        ) + $targets

        & $cmake @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "CMake build failed with exit code $LASTEXITCODE."
        }
        $buildRecord.Executed = $true
        $buildRecord.Arguments = @($buildArgs)
    }

    if ($ConfigureOnly) {
        Write-Host "Configure-only complete: $BuildDir"
        return
    }

    $llamaCli = Join-Path $BinDir 'llama-cli.exe'
    if (-not (Test-Path -LiteralPath $llamaCli -PathType Leaf)) {
        throw "llama-cli.exe not found after build: $llamaCli"
    }

    $versionCapture = $null
    $deviceCapture = $null

    if (-not $SkipSmoke) {
        Write-Host 'Running Vulkan smoke checks...'
        $versionCapture = Invoke-Evox2NativeCapture `
            -FilePath $llamaCli `
            -ArgumentList @('--version')

        $deviceCapture = Invoke-Evox2NativeCapture `
            -FilePath $llamaCli `
            -ArgumentList @('--list-devices')
    }

    $toolchain = [ordered]@{
        CMake = Get-Evox2ToolIdentity -Name 'cmake'
        Ninja = Get-Evox2ToolIdentity -Name 'ninja'
        Clang = Get-Evox2ToolIdentity -Name 'clang'
        ClangXX = Get-Evox2ToolIdentity -Name 'clang++'
        CL = Get-Evox2ToolIdentity -Name 'cl' -VersionArguments @('/Bv')
        LlvmBin = $LlvmBin
        VulkanSdk = $env:VULKAN_SDK
    }

    $validation = [ordered]@{
        SmokeSkipped = [bool]$SkipSmoke
        Version = ConvertTo-Evox2CaptureRecord -Capture $versionCapture
        ListDevices = ConvertTo-Evox2CaptureRecord -Capture $deviceCapture
    }

    $manifestPath = Write-Evox2BuildManifest `
        -RepoRoot $RepoRoot `
        -Backend 'Vulkan' `
        -BuildDir $BuildDir `
        -BinDir $BinDir `
        -Configuration $Configuration `
        -GeneratedBy 'tools/evox2/build/Build-Vulkan.ps1' `
        -Configure $configureRecord `
        -Build $buildRecord `
        -Toolchain $toolchain `
        -BackendSettings ([ordered]@{
            Vulkan = $true
            Native = $false
            BackendDl = $true
            CpuAllVariants = $true
        }) `
        -Runtime ([ordered]@{
            VulkanSdk = $env:VULKAN_SDK
        }) `
        -Validation $validation

    Write-Host ''
    Write-Host 'Vulkan build manifest written:'
    Write-Host $manifestPath

    if (-not $SkipSmoke) {
        if ($versionCapture.ExitCode -ne 0) {
            throw "llama-cli --version failed with exit code $($versionCapture.ExitCode)."
        }
        if ($deviceCapture.ExitCode -ne 0) {
            throw "llama-cli --list-devices failed with exit code $($deviceCapture.ExitCode)."
        }
    }
} finally {
    $env:PATH = $savedPath
    if ($null -eq $savedVulkanSdk) {
        Remove-Item Env:VULKAN_SDK -ErrorAction SilentlyContinue
    } else {
        $env:VULKAN_SDK = $savedVulkanSdk
    }
}
