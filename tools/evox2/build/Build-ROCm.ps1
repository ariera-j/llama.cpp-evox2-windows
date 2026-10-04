#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BuildDir = '',

    [ValidateSet('Release', 'Debug', 'RelWithDebInfo', 'MinSizeRel')]
    [string]$Configuration = 'Release',

    [ValidateRange(1, 64)]
    [int]$Parallel = 4,

    [string]$RocmPath = '',
    [string]$RocmBin = '',
    [string]$RocmCmakePath = '',
    [string]$DependencyCacheRoot = '',

    [string]$AmdGpuTarget = 'gfx1151',

    [switch]$ConfigureOnly,
    [switch]$BuildOnly,
    [switch]$ManifestOnly,

    [switch]$SkipRuntimeDllCopy,
    [switch]$SkipSmoke,
    [switch]$RunBackendTest,

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
$dependencyCacheModule = Join-Path $scriptDir 'Evox2.DependencyCache.psm1'

Import-Module $commonModule -Force
Import-Module $buildModule -Force
Import-Module $dependencyCacheModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

$dependencyCacheRootExplicit = $PSBoundParameters.ContainsKey('DependencyCacheRoot')
$DependencyCacheRoot = Resolve-Evox2DependencyCacheRoot `
    -RepoRoot $RepoRoot `
    -RequestedRoot $DependencyCacheRoot `
    -Explicit:$dependencyCacheRootExplicit

function Resolve-Evox2RepoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot 'build-rocm-r4'
}
$BuildDir = Resolve-Evox2RepoPath -Path $BuildDir
$BinDir = Join-Path $BuildDir "bin\$Configuration"

$cmake = (Get-Command cmake -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source

function Get-RocmSdkPath {
    param([string]$Kind)

    $rocmSdk = Get-Command rocm-sdk -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $rocmSdk) {
        return $null
    }

    $capture = Invoke-Evox2NativeCapture `
        -FilePath $rocmSdk.Source `
        -ArgumentList @('path', "--$Kind")

    if ($capture.ExitCode -ne 0) {
        return $null
    }

    return $capture.Text.Trim()
}

if ([string]::IsNullOrWhiteSpace($RocmPath)) {
    $RocmPath = Get-RocmSdkPath -Kind 'root'
}
if ([string]::IsNullOrWhiteSpace($RocmBin)) {
    $RocmBin = Get-RocmSdkPath -Kind 'bin'
}
if ([string]::IsNullOrWhiteSpace($RocmCmakePath)) {
    $RocmCmakePath = Get-RocmSdkPath -Kind 'cmake'
}

if (-not [string]::IsNullOrWhiteSpace($RocmPath)) {
    $RocmPath = [IO.Path]::GetFullPath($RocmPath)
}
if (-not [string]::IsNullOrWhiteSpace($RocmBin)) {
    $RocmBin = [IO.Path]::GetFullPath($RocmBin)
}
if (-not [string]::IsNullOrWhiteSpace($RocmCmakePath)) {
    $RocmCmakePath = [IO.Path]::GetFullPath($RocmCmakePath)
}

if (-not $ManifestOnly -and
    -not $BuildOnly -and
    [string]::IsNullOrWhiteSpace($RocmPath)) {
    throw 'ROCm SDK root could not be resolved. Activate the TheRock venv or pass -RocmPath.'
}

$environmentNames = @(
    'HIP_PATH',
    'ROCM_PATH',
    'CMAKE_PREFIX_PATH',
    'HIP_DEVICE_LIB_PATH',
    'HIP_PLATFORM',
    'LLVM_PATH',
    'PATH'
)

$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $savedEnvironment[$name] = [ordered]@{
        Exists = ($null -ne $item)
        Value = if ($null -ne $item) { $item.Value } else { $null }
    }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($RocmPath)) {
        $rocmLlvmBin = Join-Path $RocmPath 'lib\llvm\bin'

        $env:HIP_PATH = $RocmPath
        $env:ROCM_PATH = $RocmPath
        if (-not [string]::IsNullOrWhiteSpace($RocmCmakePath)) {
            $env:CMAKE_PREFIX_PATH = $RocmCmakePath
        }
        $env:HIP_DEVICE_LIB_PATH = Join-Path $RocmPath 'lib\llvm\amdgcn\bitcode'
        $env:HIP_PLATFORM = 'amd'
        $env:LLVM_PATH = Join-Path $RocmPath 'lib\llvm'

        $pathPieces = @($rocmLlvmBin)
        if (-not [string]::IsNullOrWhiteSpace($RocmBin)) {
            $pathPieces += $RocmBin
        }
        $env:PATH = (($pathPieces -join ';') + ';' + $env:PATH)
    } else {
        $rocmLlvmBin = $null
    }

    $dependencyCache = Initialize-Evox2DependencyCache `
        -RepoRoot $RepoRoot `
        -BuildDir $BuildDir `
        -Backend 'ROCm' `
        -CacheRoot $DependencyCacheRoot `
        -ExtraCMakeArgs $ExtraCMakeArgs `
        -PrepareBuildDir:(-not $ManifestOnly -and -not $BuildOnly)

    $configureArgs = @(
        '-S', $RepoRoot,
        '-B', $BuildDir,
        '-G', 'Ninja Multi-Config'
    )

    if (-not [string]::IsNullOrWhiteSpace($RocmPath)) {
        $configureArgs += @(
            "-DCMAKE_PREFIX_PATH=$RocmPath",
            '-DGGML_BACKEND_DL=ON',
            '-DGGML_NATIVE=OFF',
            '-DGGML_HIP=ON',
            "-DCMAKE_C_COMPILER=$RocmPath\lib\llvm\bin\clang.exe",
            "-DCMAKE_CXX_COMPILER=$RocmPath\lib\llvm\bin\clang++.exe",
            '-DCMAKE_C_FLAGS=-Wno-error=incompatible-pointer-types',
            "-DCMAKE_HIP_COMPILER=$RocmPath\lib\llvm\bin\clang.exe",
            "-DHIP_PATH=$RocmPath",
            "-DAMDGPU_TARGETS=$AmdGpuTarget"
        )
    } else {
        # Manifest-only mode can inspect an already-built tree even if the
        # TheRock environment is not currently active.
        $configureArgs += @(
            '-DGGML_BACKEND_DL=ON',
            '-DGGML_NATIVE=OFF',
            '-DGGML_HIP=ON',
            "-DAMDGPU_TARGETS=$AmdGpuTarget"
        )
    }

    $configureArgs += @(
        '-DLLAMA_BUILD_BORINGSSL=ON',
        '-DLLAMA_BUILD_EXAMPLES=OFF',
        '-DLLAMA_BUILD_TESTS=ON',
        '-DLLAMA_BUILD_TOOLS=ON',
        '-DLLAMA_BUILD_SERVER=ON',
        '-DLLAMA_BUILD_UI=OFF',
        '-DGGML_RPC=ON'
    )

    if ($dependencyCache.ConfigureArgs.Count -gt 0) {
        $configureArgs += @($dependencyCache.ConfigureArgs)
    }

    if ($ExtraCMakeArgs.Count -gt 0) {
        $configureArgs += $ExtraCMakeArgs
    }

    $userTargets = @(
        'llama-cli',
        'llama-server',
        'llama-bench',
        'test-backend-ops',
        'test-mtp-indexer-policy',
        'test-mtp-dense-indexer'
    )

    $configureRecord = [ordered]@{
        Executed  = $false
        Generator = 'Ninja Multi-Config'
        Arguments = @($configureArgs)
        ExtraArgs = @($ExtraCMakeArgs)
    }

    $buildRecord = [ordered]@{
        Executed       = $false
        Parallel       = $Parallel
        BackendTarget  = 'ggml-hip'
        UserTargets    = @($userTargets)
        Steps          = @()
    }

    $buildSource = if (-not $ManifestOnly) { Get-Evox2GitMetadata -RepoRoot $RepoRoot } else { $null }
    if ($BuildOnly) {
        $configureRecord.MetadataRefresh = Invoke-Evox2BuildMetadataRefresh `
            -CMake $cmake -RepoRoot $RepoRoot -BuildDir $BuildDir -Backend 'ROCm'
    }

    if (-not $ManifestOnly -and -not $BuildOnly) {
        Write-Host 'Configuring ROCm build...'
        & $cmake @configureArgs
        if ($LASTEXITCODE -ne 0) {
            throw "CMake configure failed with exit code $LASTEXITCODE."
        }
        $configureRecord.Executed = $true
        $dependencyCache.Record.Captured = Save-Evox2DependencyCacheFromBuild `
            -RepoRoot $RepoRoot `
            -BuildDir $BuildDir `
            -Backend 'ROCm' `
            -CacheRoot $DependencyCacheRoot
    }

    if (-not $ManifestOnly -and -not $ConfigureOnly) {
        Write-Host 'Building ggml-hip first...'
        $hipBuildArgs = @(
            '--build', $BuildDir,
            '--config', $Configuration,
            '--parallel', "$Parallel",
            '--target', 'ggml-hip'
        )
        & $cmake @hipBuildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "ggml-hip build failed with exit code $LASTEXITCODE."
        }

        Write-Host 'Building user-facing ROCm targets...'
        $toolBuildArgs = @(
            '--build', $BuildDir,
            '--config', $Configuration,
            '--parallel', "$Parallel",
            '--target'
        ) + $userTargets

        & $cmake @toolBuildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "ROCm tool build failed with exit code $LASTEXITCODE."
        }

        $buildRecord.Executed = $true
        $buildRecord.Steps = @(
            [ordered]@{
                Name = 'ggml-hip'
                Arguments = @($hipBuildArgs)
            },
            [ordered]@{
                Name = 'tools'
                Arguments = @($toolBuildArgs)
            }
        )
    }

    if ($ConfigureOnly) {
        Write-Host "Configure-only complete: $BuildDir"
        return
    }

    $llamaCli = Join-Path $BinDir 'llama-cli.exe'
    if (-not (Test-Path -LiteralPath $llamaCli -PathType Leaf)) {
        throw "llama-cli.exe not found after build: $llamaCli"
    }

    $runtimeDllRecords = @()
    $runtimeDllNames = @(
        'amdhip64_7.dll',
        'rocm_kpack.dll',
        'amd_comgr.dll'
    )

    if (-not $ManifestOnly -and
        -not $SkipRuntimeDllCopy -and
        -not [string]::IsNullOrWhiteSpace($RocmBin)) {
        Write-Host 'Copying ROCm runtime DLLs beside the executables...'

        foreach ($name in $runtimeDllNames) {
            $source = Join-Path $RocmBin $name
            $destination = Join-Path $BinDir $name

            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
                throw "Required ROCm runtime DLL not found: $source"
            }

            Copy-Item -LiteralPath $source -Destination $destination -Force

            $runtimeDllRecords += [ordered]@{
                Name = $name
                Source = Get-Evox2FileIdentity -Path $source -Sha256
                Destination = Get-Evox2FileIdentity -Path $destination -Sha256
            }
        }
    } else {
        foreach ($name in $runtimeDllNames) {
            $destination = Join-Path $BinDir $name
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                $runtimeDllRecords += [ordered]@{
                    Name = $name
                    Source = $null
                    Destination = Get-Evox2FileIdentity -Path $destination -Sha256
                }
            }
        }
    }

    $versionCapture = $null
    $deviceCapture = $null

    if (-not $SkipSmoke) {
        Write-Host 'Running ROCm smoke checks...'
        $versionCapture = Invoke-Evox2NativeCapture `
            -FilePath $llamaCli `
            -ArgumentList @('--version')

        $deviceCapture = Invoke-Evox2NativeCapture `
            -FilePath $llamaCli `
            -ArgumentList @('--list-devices')
    }

    $backendTestCapture = $null
    $backendTestLogPath = $null
    if ($RunBackendTest) {
        $backendTest = Join-Path $BinDir 'test-backend-ops.exe'
        if (-not (Test-Path -LiteralPath $backendTest -PathType Leaf)) {
            throw "test-backend-ops.exe not found: $backendTest"
        }

        Write-Host 'Running ROCm FLASH_ATTN_EXT backend test...'
        $backendTestCapture = Invoke-Evox2NativeCapture `
            -FilePath $backendTest `
            -ArgumentList @('test', '-b', 'ROCm0', '-o', 'FLASH_ATTN_EXT')

        # The failing case can occur far before the final summary. Preserve
        # the complete native output as well as the compact manifest tail.
        $backendTestLogPath = Save-Evox2CaptureLog `
            -Capture $backendTestCapture `
            -Path (Join-Path $BinDir ('evox2-backend-test-rocm-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
        Write-Host "Backend test log: $backendTestLogPath"

        if ($backendTestCapture.ExitCode -ne 0) {
            $backendTestCapture.Lines |
                Where-Object { $_ -match 'ERR|FAIL|NaN|mismatch|failed|error|tests passed|backends passed' } |
                ForEach-Object { Write-Host $_ }
        }
    }

    $toolchain = [ordered]@{
        CMake = Get-Evox2ToolIdentity -Name 'cmake'
        Ninja = Get-Evox2ToolIdentity -Name 'ninja'
        Clang = Get-Evox2ToolIdentity -Name 'clang'
        ClangXX = Get-Evox2ToolIdentity -Name 'clang++'
        CL = Get-Evox2ToolIdentity -Name 'cl' -VersionArguments @('/Bv')
        RocmSdk = Get-Evox2ToolIdentity -Name 'rocm-sdk' -VersionArguments @('version')
        RocmPath = $RocmPath
        RocmBin = $RocmBin
        RocmCmakePath = $RocmCmakePath
        RocmLlvmBin = $rocmLlvmBin
        VCToolsInstallDir = $env:VCToolsInstallDir
    }

    $runtime = [ordered]@{
        DependencyCache = $dependencyCache.Record
        RuntimeDllCopySkipped = [bool]$SkipRuntimeDllCopy
        RuntimeDlls = @($runtimeDllRecords)
        Environment = [ordered]@{
            HIP_PATH = $env:HIP_PATH
            ROCM_PATH = $env:ROCM_PATH
            CMAKE_PREFIX_PATH = $env:CMAKE_PREFIX_PATH
            HIP_DEVICE_LIB_PATH = $env:HIP_DEVICE_LIB_PATH
            HIP_PLATFORM = $env:HIP_PLATFORM
            LLVM_PATH = $env:LLVM_PATH
        }
    }

    $validation = [ordered]@{
        SmokeSkipped = [bool]$SkipSmoke
        Version = ConvertTo-Evox2CaptureRecord -Capture $versionCapture
        ListDevices = ConvertTo-Evox2CaptureRecord -Capture $deviceCapture
        BackendTestRequested = [bool]$RunBackendTest
        BackendTestLogPath = $backendTestLogPath
        BackendTest = ConvertTo-Evox2CaptureRecord `
            -Capture $backendTestCapture `
            -TailLines 80
    }

    $manifestPath = Write-Evox2BuildManifest `
        -RepoRoot $RepoRoot `
        -Backend 'ROCm' `
        -BuildDir $BuildDir `
        -BinDir $BinDir `
        -Configuration $Configuration `
        -GeneratedBy 'tools/evox2/build/Build-ROCm.ps1' `
        -BuildSource $buildSource `
        -Configure $configureRecord `
        -Build $buildRecord `
        -Toolchain $toolchain `
        -BackendSettings ([ordered]@{
            Hip = $true
            Native = $false
            BackendDl = $true
            AmdGpuTarget = $AmdGpuTarget
        }) `
        -Runtime $runtime `
        -Validation $validation

    Write-Host ''
    Write-Host 'ROCm build manifest written:'
    Write-Host $manifestPath

    if (-not $SkipSmoke) {
        if ($versionCapture.ExitCode -ne 0) {
            throw "llama-cli --version failed with exit code $($versionCapture.ExitCode)."
        }
        if ($deviceCapture.ExitCode -ne 0) {
            throw "llama-cli --list-devices failed with exit code $($deviceCapture.ExitCode)."
        }
    }

    if ($RunBackendTest -and $backendTestCapture.ExitCode -ne 0) {
        throw "test-backend-ops failed with exit code $($backendTestCapture.ExitCode). Full log: $backendTestLogPath"
    }
} finally {
    foreach ($name in $environmentNames) {
        $saved = $savedEnvironment[$name]
        if ($saved.Exists) {
            Set-Item -LiteralPath "Env:$name" -Value $saved.Value
        } else {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}
