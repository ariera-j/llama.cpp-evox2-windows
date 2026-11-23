#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Mandatory)][ValidateSet('Vulkan', 'ROCm')][string]$Backend,
    [Parameter(Mandatory)][ValidatePattern('\Abuild-[A-Za-z0-9][A-Za-z0-9_-]*\z')][string]$BuildDir,
    [Parameter(ParameterSetName = 'Preflight')][switch]$PreflightOnly,
    [Parameter(ParameterSetName = 'Configure')][switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$mode = $PSCmdlet.ParameterSetName
$logRoot = 'C:\llama-build\_logs\codex'
$stem = Join-Path $logRoot ("build-$Backend-$mode-" + [guid]::NewGuid().ToString('N'))
$result = [ordered]@{
    Command = @($PSCommandPath, '-Backend', $Backend, '-BuildDir', $BuildDir)
    Stdout = "$stem.stdout.log"
    Stderr = "$stem.stderr.log"
    ExitCode = 1
    ElapsedSeconds = $null
}
if ($mode -ne 'Build') { $result.Command += "-$($mode)Only" }
if (!(Test-Path -LiteralPath $logRoot -PathType Container)) { throw "Missing log directory: $logRoot" }

$worker = {
    param($repo, $backend, $name, $mode)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $env:VSLANG = '1033'
    $env:GIT_OPTIONAL_LOCKS = '0'
    $env:PYTHONDONTWRITEBYTECODE = '1'
    if ($repo -ine 'C:\llama-build\automation\llama.cpp-evox2-windows') { throw 'Use the EVO-X2 Codex clone.' }
    Set-Location -LiteralPath $repo

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

    $parent = Split-Path -Parent $repo
    $cache = Join-Path $parent '_deps'
    foreach ($path in 'C:\llama-build', $parent, $repo, $cache, "$cache\fetchcontent") { Assert-Directory $path }
    $destination = Join-Path $repo $name
    if (Test-Path -LiteralPath $destination) { throw "Build directory already exists: $destination" }
    $head = Read-Native git @('rev-parse', 'HEAD')
    if ($mode -ne 'Preflight' -and @(Read-Native git @('status', '--porcelain')).Count) { throw 'Worktree is not clean.' }

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
        $clang = 'C:\Program Files\LLVM\bin'
        $clangVersion = '^clang version 20\.1\.8(?:\s|$)'
        $params.CMakeExe = $cmake
        $params.LlvmBin = $clang
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

    $module = Import-Module .\tools\evox2\build\Evox2.DependencyCache.psm1 -PassThru
    & $module {
        param($repo, $cache, $backend)
        $versions = Get-Evox2DependencyVersions -RepoRoot $repo
        if (!$versions.BoringSsl) { throw 'BoringSSL version is missing from source.' }
        $source = Join-Path $cache "fetchcontent\boringssl-$($versions.BoringSsl)-src"
        foreach ($path in $source, "$source\.git") {
            $item = Get-Item -LiteralPath $path -Force
            if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Invalid private BoringSSL checkout: $path"
            }
        }
        if ((Test-Path -LiteralPath "$source\.git\objects\info\alternates") -or
            !(Test-Evox2BoringSslCheckout -SourceDir $source -ExpectedVersion $versions.BoringSsl)) {
            throw "Invalid private BoringSSL checkout: $source"
        }
        "Cached BoringSSL: $source"
        if ($backend -eq 'Vulkan') {
            if (!$versions.OpenMp) { throw 'OpenMP version is missing from source.' }
            $runtime = Join-Path $cache "openmp\llvm-openmp-$($versions.OpenMp)-x64"
            foreach ($path in "$cache\openmp", $runtime) {
                if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Unexpected cache reparse point: $path"
                }
            }
            if (!(Test-Evox2OpenMpLayout -Root $runtime) -or !(Test-Path -LiteralPath "$runtime\LICENSE.TXT" -PathType Leaf)) {
                throw "Incomplete private OpenMP cache: $runtime"
            }
            "Cached OpenMP: $runtime"
        }
    } $repo $cache $backend

    if ($mode -eq 'Preflight') {
        if ($backend -eq 'Vulkan') { & $wrapper @params -PreflightOnly }
        "Preflight passed for $backend"
        return
    }

    $null = New-Item -ItemType Directory -Path $destination
    $options = @('-DLLAMA_BUILD_UI=OFF', '-DLLAMA_USE_PREBUILT_UI=OFF', '-DFETCHCONTENT_FULLY_DISCONNECTED=ON')
    "Configure: $wrapper | $($params | ConvertTo-Json -Compress) | -ConfigureOnly $($options -join ' ')"
    & $wrapper @params -ExtraCMakeArgs $options -ConfigureOnly
    $configured = Get-Content -LiteralPath "$destination\CMakeCache.txt"
    foreach ($flag in 'LLAMA_BUILD_UI:BOOL=OFF', 'LLAMA_USE_PREBUILT_UI:BOOL=OFF', 'FETCHCONTENT_FULLY_DISCONNECTED:BOOL=ON') {
        if ($configured -notcontains $flag) { throw "Unexpected cache: $flag" }
    }
    if ($mode -eq 'Configure') { return }

    "Build: $wrapper | $($params | ConvertTo-Json -Compress) | -BuildOnly"
    & $wrapper @params -BuildOnly
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
}

# All phases run in one child PowerShell, with separate native output streams.
$quoted = @($repo, $Backend, $BuildDir, $mode) | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
$payload = "try { & {" + $worker.ToString() + "} " + ($quoted -join ' ') +
    '; exit 0 } catch { [Console]::Error.WriteLine($_.ToString()); exit 1 }'
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
$timer = [Diagnostics.Stopwatch]::StartNew()
try {
    $process = Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-EncodedCommand', $encoded
    ) -NoNewWindow -RedirectStandardOutput $result.Stdout -RedirectStandardError $result.Stderr -PassThru
    $null = $process.Handle
    $process.WaitForExit()
    if ($null -ne $process.ExitCode) { $result.ExitCode = $process.ExitCode }
    if ($result.ExitCode -ne 0) { throw "Codex build failed. See $($result.Stderr) and $($result.Stdout)" }
} finally {
    $timer.Stop()
    $result.ElapsedSeconds = $timer.Elapsed.TotalSeconds
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$stem.result.json" -Encoding UTF8
    Write-Host "Result: $stem.result.json"
}
