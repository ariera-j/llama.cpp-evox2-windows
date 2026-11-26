#requires -Version 5.1
param($repo, $backend, $name, $mode, $vulkanBin, $vulkanClangVersion, $cpuVariants, $offline, $worktree, $sourceCommit, $stateStem)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:VSLANG = '1033'
$env:GIT_OPTIONAL_LOCKS = '0'
$env:GIT_TERMINAL_PROMPT = '0'
$env:PYTHONDONTWRITEBYTECODE = '1'
Set-Location -LiteralPath $repo
Import-Module (Join-Path $PSScriptRoot 'Evox2.BuildState.psm1')
if ($stateStem -notmatch '\AC:\\llama-build\\_logs\\codex\\build-(Vulkan|ROCm)-(Build|Preflight|Configure)-[a-f0-9]{32}\z') {
    throw 'Invalid build state path.'
}
$workerRecord = [ordered]@{
    ExecutionId = [IO.Path]::GetFileName($stateStem)
    Process = Get-Evox2ProcessIdentity (Get-Process -Id $PID)
    Phase = $null; UpdatedUtc = $null; CheckoutStart = $null; CheckoutEnd = $null; Tools = @()
}
function Set-WorkerPhase([string]$Phase) {
    $workerRecord.Phase = $Phase
    $workerRecord.UpdatedUtc = [datetime]::UtcNow.ToString('o')
    Write-Evox2BuildRecord "$stateStem.worker.json" $workerRecord
}
Set-WorkerPhase 'ValidateLocation'


function Read-Native($exe, [string[]]$arguments) {
    $output = @(& $exe @arguments)
    if ($LASTEXITCODE -ne 0) { throw "$exe exited $LASTEXITCODE" }
    $output
}

function Assert-Directory($path) {
    $item = Get-Item -LiteralPath $path -Force
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular directory: $path"
    }
}

Import-Module .\tools\evox2\automation\Evox2.BuildLocation.psm1
$location = Resolve-Evox2BuildLocation -Repository $repo -BuildName $name -Worktree:($worktree -eq 'True') `
    -SourceCommit $sourceCommit -Preflight:($mode -eq 'Preflight') -Offline:($offline -eq 'True')
$cache = $location.Cache
$destination = $location.Destination
$head = $location.SourceCommit
$workerRecord.CheckoutStart = $location
"Checkout start: $($location | ConvertTo-Json -Compress)"
"Source path: $repo ($($location.SourcePathLength) characters); build path: $destination ($($location.BuildPathLength) characters)"
if ($location.LinkedWorktree -and $destination.Length -gt 'C:\llama-build\automation\llama.cpp-evox2-windows\build-w5v'.Length) {
    Write-Warning 'Output root exceeds the successful work 5-2 Vulkan path length. Generated MSVC shader-test paths can be longer.'
}
$scriptHashes = Get-FileHash -LiteralPath ".\tools\evox2\automation\Invoke-CodexBuild.ps1", ".\tools\evox2\build\Build-$backend.ps1"
$workerRecord.Tools = @($scriptHashes | Select-Object Path,Hash)
$scriptHashes | ForEach-Object { "Tool SHA-256: $($_.Hash) $($_.Path)" }
try {
    Set-WorkerPhase 'ValidateToolchain'
    $vs = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\2022\BuildTools'
    $env:EVOX2_CODEX_VSDEV = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    $variables = Read-Native cmd.exe @('/d', '/c', 'call "%EVOX2_CODEX_VSDEV%" -arch=x64 -host_arch=x64 -no_logo && set')
    foreach ($line in $variables) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
    if ($env:VisualStudioVersion -ne '17.0' -or $env:VSCMD_ARG_HOST_ARCH -ne 'x64' -or $env:VSCMD_ARG_TGT_ARCH -ne 'x64') {
        throw 'Expected VS2022 x64 Native Tools.'
    }
    $cmakeBase = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake'
    $cmake = "$cmakeBase\CMake\bin\cmake.exe"
    $pins = @{ 'cmake.exe' = @($cmake, 'cmake version 3.31.6-msvc6'); 'ninja.exe' = @("$cmakeBase\Ninja\ninja.exe", '1.12.1') }
    $params = @{ BuildDir = $destination; DependencyCacheRoot = $cache; Parallel = 4 }
    $wrapper = Join-Path $repo "tools\evox2\build\Build-$backend.ps1"

    if ($backend -eq 'ROCm') {
        $venv = 'C:\TheRock\build\.venv'
        & "$venv\Scripts\Activate.ps1"
        $legacy = '(?i)[\\/]ROCm[\\/]7\.2(?:[\\/]|$)'
        $env:Path = ($env:Path -split ';' | Where-Object { $_.Trim('"') -notmatch $legacy }) -join ';'
        Get-ChildItem Env: | Where-Object {
            $_.Name -match '^(HIP|ROCM|HSA|LLVM|CMAKE)' -and $_.Value -match $legacy
        } | ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }
        $sdk = (Get-Command rocm-sdk.exe -CommandType Application | Select-Object -First 1).Source
        if ($sdk -ine "$venv\Scripts\rocm-sdk.exe" -or (Read-Native $sdk @('version')) -ne '10.0.0') {
            throw 'Expected TheRock rocm-sdk 10.0.0.'
        }
        $root = (Read-Native $sdk @('path', '--root')).Trim()
        if ($root -ine "$venv\Lib\site-packages\_rocm_sdk_devel") { throw "Unexpected TheRock root: $root" }
        $env:HIP_PATH = $root
        $env:ROCM_PATH = $root
        $clang = "$root\lib\llvm\bin"
        $clangVersion = '^AMD clang version 23\.0\.0(?:git)?(?:\s|$)'
        $params.ExpectedRocmSdkVersion = '10.0.0'
        $params.AmdGpuTarget = 'gfx1151'
        $params.RocmPath = $root
        $params.RocmBin = (Read-Native $sdk @('path', '--bin')).Trim()
        $params.RocmCmakePath = (Read-Native $sdk @('path', '--cmake')).Trim()
        foreach ($path in $params.RocmBin, $params.RocmCmakePath) {
            if (!$path.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) {
                throw "Unexpected TheRock SDK path: $path"
            }
            Assert-Directory $path
        }
        "TheRock 10.0.0, gfx1151: $root"
    } else {
        $clang = $vulkanBin
        $clangVersion = '^clang version ' + [regex]::Escape($vulkanClangVersion) + '(?:\s|$)'
        $params.CMakeExe = $cmake
        $params.LlvmBin = $clang
        $params.CpuAllVariants = $cpuVariants
        $params.VulkanSdk = 'C:\VulkanSDK\1.4.357.0'
        foreach ($file in 'Include\vulkan\vulkan.h', 'Lib\vulkan-1.lib', 'Bin\glslc.exe') {
            if (!(Test-Path -LiteralPath (Join-Path $params.VulkanSdk $file) -PathType Leaf)) {
                throw "Vulkan SDK file missing: $file"
            }
        }
        if (!(Get-Command 7z.exe -ErrorAction SilentlyContinue) -and
            !(Test-Path -LiteralPath "$env:ProgramFiles\7-Zip\7z.exe" -PathType Leaf)) { throw '7-Zip is missing.' }
    }
    foreach ($tool in $pins.GetEnumerator()) {
        $exe = (Get-Command $tool.Key -CommandType Application | Select-Object -First 1).Source
        $version = @(Read-Native $exe @('--version'))[0]
        if ($exe -ine $tool.Value[0] -or $version -ne $tool.Value[1]) { throw "Unexpected tool: $exe ($version)" }
        "$exe : $version"
    }
    foreach ($compiler in 'clang.exe', 'clang++.exe') {
        $exe = Join-Path $clang $compiler
        $version = @(Read-Native $exe @('--version'))[0]
        if ($version -notmatch $clangVersion) { throw "Unexpected compiler: $exe ($version)" }
        "$exe : $version"
    }
    $cl = (Get-Command cl.exe -CommandType Application | Select-Object -First 1).Source
    if (!$cl.StartsWith("$vs\", [StringComparison]::OrdinalIgnoreCase) -or $cl -notmatch '\\Hostx64\\x64\\cl\.exe$') {
        throw "Unexpected MSVC compiler: $cl"
    }
    $msvcVersion = (Get-Item -LiteralPath $cl).VersionInfo.ProductVersion
    if ($msvcVersion -notmatch '^14\.44\.') { throw "Unexpected MSVC version: $msvcVersion" }
    "$cl : $msvcVersion"

    Import-Module .\tools\evox2\build\Evox2.DependencyCache.psm1
    $allowDownload = $mode -ne 'Preflight' -and $offline -eq 'False'
    Set-WorkerPhase 'VerifyDependencies'
    Initialize-Evox2CodexDependencies -RepoRoot $repo -CacheRoot $cache -Backend $backend -AllowDownload:$allowDownload

    if ($mode -eq 'Preflight') {
        Set-WorkerPhase 'Preflight'
        if ($backend -eq 'Vulkan') { & $wrapper @params -PreflightOnly }
        "Preflight passed for $backend"
        return
    }

    Set-WorkerPhase 'Configure'
    $null = New-Item -ItemType Directory -Path $destination
    $options = @('-DLLAMA_BUILD_UI=OFF', '-DLLAMA_USE_PREBUILT_UI=OFF', '-DFETCHCONTENT_FULLY_DISCONNECTED=ON')
    "Configure: $wrapper | $($params | ConvertTo-Json -Compress) | -ConfigureOnly $($options -join ' ')"
    & $wrapper @params -ExtraCMakeArgs $options -ConfigureOnly
    Set-WorkerPhase 'VerifyCache'
    $configured = Get-Content -LiteralPath "$destination\CMakeCache.txt"
    foreach ($flag in 'LLAMA_BUILD_UI:BOOL=OFF', 'LLAMA_USE_PREBUILT_UI:BOOL=OFF', 'FETCHCONTENT_FULLY_DISCONNECTED:BOOL=ON') {
        if ($configured -notcontains $flag) { throw "Unexpected cache: $flag" }
    }
    if ($backend -eq 'Vulkan') {
        foreach ($flag in "GGML_CPU_ALL_VARIANTS:BOOL=$cpuVariants", 'GGML_NATIVE:BOOL=OFF', 'GGML_BACKEND_DL:BOOL=ON') {
            if ($configured -notcontains $flag) { throw "Unexpected cache: $flag" }
        }
        $targets = Read-Native $pins['ninja.exe'][0] @('-C', $destination, '-f', 'build-Release.ninja', '-t', 'targets', 'all')
        $hasSapphireRapids = [bool]($targets -match 'ggml-cpu-sapphirerapids')
        if ($cpuVariants -eq 'OFF' -and $hasSapphireRapids) { throw 'Unexpected Sapphire Rapids target.' }
        "Verified Vulkan CPU variants: $cpuVariants, Sapphire Rapids target present: $hasSapphireRapids"
    } else {
        if (-not ($configured -match '^AMDGPU_TARGETS:[^=]+=gfx1151$')) { throw 'Unexpected AMDGPU_TARGETS cache value.' }
        if ($configured -notcontains 'GGML_HIP:BOOL=ON') { throw 'Unexpected GGML_HIP cache value.' }
    }
    if ($mode -eq 'Configure') { return }

    Set-WorkerPhase 'Build'
    "Build: $wrapper | $($params | ConvertTo-Json -Compress) | -BuildOnly"
    & $wrapper @params -BuildOnly
    Set-WorkerPhase 'VerifyArtifacts'
    $bin = Join-Path $destination 'bin\Release'
    $exe = Join-Path $bin 'llama-cli.exe'
    $manifest = Get-Content -LiteralPath "$bin\evox2-build.json" -Raw | ConvertFrom-Json
    if ($manifest.BuildIdentity.Status -ne 'Verified' -or $manifest.Source.Commit -ne $head -or
        $manifest.Backend -ne $backend -or (Get-FileHash -LiteralPath $exe).Hash -ne $manifest.ExecutableIdentity.Sha256) {
        throw 'Build manifest, source or executable hash mismatch.'
    }
    $device = if ($backend -eq 'Vulkan') { 'Vulkan0' } else { 'ROCm0' }
    if ($manifest.Validation.SmokeSkipped -ne $false -or $manifest.Validation.Version.ExitCode -ne 0 -or
        $manifest.Validation.ListDevices.ExitCode -ne 0 -or
        ($manifest.Validation.ListDevices.Tail -join ' ') -notmatch "$($device): AMD Radeon.*8060S") {
        throw "CLI smoke failed or Radeon 8060S was not found as $device."
    }
    if ($backend -eq 'ROCm' -and $manifest.Runtime.RuntimePolicy.Verification -ne 'DllAndRuntimeDataHashesVerified') {
        throw 'TheRock runtime staging was not verified.'
    }
    "Verified $backend, $device, $head, SHA-256 $($manifest.ExecutableIdentity.Sha256)"
} finally {
    $end = Get-Evox2BuildCheckout $repo
    $workerRecord.CheckoutEnd = $end
    Set-WorkerPhase $workerRecord.Phase
    "Checkout end: $($end | ConvertTo-Json -Compress)"
    if ($end.SourceCommit -ne $head -or (($location.LinkedWorktree -or $mode -ne 'Preflight') -and !$end.Clean)) {
        throw 'Checkout SHA or clean state changed during the wrapper invocation.'
    }
}
