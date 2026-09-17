#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LlvmBin = 'C:\LLVM\20.1.8\bin',
    [string]$VulkanSdk = $env:VULKAN_SDK,
    [string]$CMakeExecutable = 'cmake',
    [string]$NinjaExecutable = 'ninja',
    [string]$BuildDirectory = '',
    [string]$DependencyCacheDirectory = 'C:\llama-build\evox2-deps',
    [ValidateRange(1, 32)][int]$Parallel = 4,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$SourceDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $SourceDirectory 'build-llvm20-r2' }
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
$DependencyCacheDirectory = [IO.Path]::GetFullPath($DependencyCacheDirectory)
if (-not $VulkanSdk) { $VulkanSdk = 'C:\VulkanSDK\1.4.357.0' }

$RequiredSourceFiles = @(
    'ggml\src\ggml-vulkan\vulkan-shaders\qsa_gather.comp',
    'tools\evox2\Measure-Qwen38-Ple16.ps1',
    'tools\ui\src\lib\components\app\chat\ChatAttachments\ChatAttachmentsPreview\ChatAttachmentsPreviewCurrentItem\ChatAttachmentsPreviewCurrentItemVideo.svelte'
)
foreach ($RelativePath in $RequiredSourceFiles) {
    $RequiredPath = Join-Path $SourceDirectory $RelativePath
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Source file is missing: $RequiredPath. Re-extract the ZIP to a short path such as C:\e2r2; do not continue with a partially extracted tree."
    }
}
$PathProbe = Join-Path $BuildDirectory 'ggml\src\ggml-vulkan\vulkan-shaders-gen-prefix\src\vulkan-shaders-gen-build\CMakeFiles\CMakeScratch\TryCompile-12345678\CMakeFiles\cmTC_12345.dir\Debug\testCCompiler.c.obj'
if ($PathProbe.Length -gt 235) {
    throw "The build path is too long ($($PathProbe.Length) characters in a compiler probe). Re-extract the source to C:\e2r2 or use -BuildDirectory C:\b\e2r2."
}

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Program" }
}

foreach ($File in @((Join-Path $LlvmBin 'clang.exe'), (Join-Path $LlvmBin 'clang++.exe'),
                    (Join-Path $VulkanSdk 'Bin\glslc.exe'))) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "Required file not found: $File. Set -LlvmBin or -VulkanSdk." }
}
if (-not $env:VCToolsInstallDir -or -not $env:WindowsSdkDir) {
    throw 'Open x64 Native Tools Command Prompt for VS, run powershell -NoProfile, then run this script. The VS linker and Windows SDK environment are required.'
}
$Cache = Join-Path $BuildDirectory 'CMakeCache.txt'
if (Test-Path -LiteralPath $Cache) {
    $HomeLine = Get-Content -LiteralPath $Cache | Where-Object { $_ -like 'CMAKE_HOME_DIRECTORY:INTERNAL=*' } | Select-Object -First 1
    $CachedSource = if ($HomeLine) { $HomeLine.Substring($HomeLine.IndexOf('=') + 1) } else { '' }
    if (-not $CachedSource -or [IO.Path]::GetFullPath($CachedSource) -ne $SourceDirectory) {
        throw 'This build directory belongs to another source tree. Choose a new -BuildDirectory.'
    }
}

$SavedPath = $env:PATH
$SavedSdk = $env:VULKAN_SDK
$TranscriptStarted = $false
try {
    $ExtraPath = @($LlvmBin, (Join-Path $VulkanSdk 'Bin'))
    if (Test-Path -LiteralPath 'C:\Program Files\7-Zip\7z.exe') { $ExtraPath += 'C:\Program Files\7-Zip' }
    $env:PATH = ($ExtraPath -join ';') + ';' + $SavedPath
    $env:VULKAN_SDK = $VulkanSdk
    $CMake = (Get-Command $CMakeExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $Ninja = (Get-Command $NinjaExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    Get-Command 7z -CommandType Application -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $BuildDirectory -Force | Out-Null
    $OpenMpCache = Join-Path $DependencyCacheDirectory 'openmp'
    $FetchContentCache = Join-Path $DependencyCacheDirectory 'fetchcontent'
    New-Item -ItemType Directory -Path $OpenMpCache, $FetchContentCache -Force | Out-Null
    $OpenMpRoot = Join-Path $OpenMpCache 'llvm-openmp-20.1.8-x64'
    $OpenMpReady = (Test-Path -LiteralPath (Join-Path $OpenMpRoot 'lib\libomp.lib')) -and (Test-Path -LiteralPath (Join-Path $OpenMpRoot 'bin\libomp.dll')) -and (Test-Path -LiteralPath (Join-Path $OpenMpRoot 'include\omp.h'))
    $BoringSslSource = Join-Path $FetchContentCache 'boringssl-src'
    if ($OpenMpReady) { Write-Host "Reusing LLVM OpenMP cache: $OpenMpRoot" }
    else { Write-Host "LLVM OpenMP is not cached yet; the first configure will download it to: $OpenMpRoot" }
    if (Test-Path -LiteralPath (Join-Path $BoringSslSource 'CMakeLists.txt')) {
        Write-Host "Reusing BoringSSL source cache: $BoringSslSource"
    } else {
        Write-Host "BoringSSL is not cached yet; the first configure will fetch it to: $BoringSslSource"
    }
    $LogPath = Join-Path $BuildDirectory ('evox2-r2-build-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    Start-Transcript -Path $LogPath | Out-Null
    $TranscriptStarted = $true
    Invoke-Checked (Join-Path $LlvmBin 'clang.exe') @('--version')
    Invoke-Checked (Join-Path $VulkanSdk 'Bin\glslc.exe') @('--version')
    $Configure = @('-S', $SourceDirectory, '-B', $BuildDirectory, '-G', 'Ninja Multi-Config',
        ('-DCMAKE_MAKE_PROGRAM=' + $Ninja),
        ('-DCMAKE_TOOLCHAIN_FILE=' + (Join-Path $SourceDirectory 'cmake\x64-windows-llvm.cmake')),
        '-DGGML_VULKAN=ON', '-DGGML_NATIVE=OFF', '-DGGML_BACKEND_DL=ON',
        '-DGGML_CPU_ALL_VARIANTS=ON', '-DGGML_OPENMP=ON', '-DGGML_OPENMP_FETCH=ON',
        ('-DGGML_OPENMP_CACHE_DIR:PATH=' + $OpenMpCache),
        ('-DFETCHCONTENT_BASE_DIR:PATH=' + $FetchContentCache),
        '-DFETCHCONTENT_UPDATES_DISCONNECTED=ON',
        '-DLLAMA_BUILD_BORINGSSL=ON', '-DLLAMA_BUILD_EXAMPLES=OFF', '-DLLAMA_BUILD_TESTS=ON',
        '-DLLAMA_BUILD_TOOLS=ON', '-DLLAMA_BUILD_SERVER=ON', '-DLLAMA_BUILD_UI=OFF', '-DGGML_RPC=ON',
        '-DLLAMA_BUILD_COMMIT=ee245db-evox2-r2')
    if (Test-Path -LiteralPath (Join-Path $BoringSslSource 'CMakeLists.txt')) {
        $Configure += ('-DFETCHCONTENT_SOURCE_DIR_BORINGSSL:PATH=' + $BoringSslSource)
    }
    Invoke-Checked $CMake $Configure
    if (-not $ConfigureOnly) {
        Invoke-Checked $CMake @('--build', $BuildDirectory, '--config', 'Release', '--parallel', "$Parallel",
            '--target', 'llama-cli', 'llama-server', 'llama-bench', 'test-backend-ops')
        $BinaryDirectory = Join-Path $BuildDirectory 'bin\Release'
        foreach ($Name in @('llama-cli', 'llama-server', 'llama-bench', 'test-backend-ops')) {
            if (-not (Test-Path -LiteralPath (Join-Path $BinaryDirectory ($Name + '.exe')))) { throw "Missing binary: $Name" }
        }
        Invoke-Checked (Join-Path $BinaryDirectory 'llama-cli.exe') @('--version')
        Write-Host "Candidate binaries: $BinaryDirectory"
        Write-Host 'Run Test-Qsa-Union.ps1 before model benchmarks. Keep the DLLs beside the executables.'
    }
} finally {
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    $env:PATH = $SavedPath
    $env:VULKAN_SDK = $SavedSdk
}
