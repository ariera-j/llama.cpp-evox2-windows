#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Vulkan', 'ROCm')][string]$Backend,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('\Abuild-[A-Za-z0-9][A-Za-z0-9_-]*\z')][string]$BuildDir,
    [Parameter(Mandatory)][ValidatePattern('\Abuild-[A-Za-z0-9][A-Za-z0-9_-]*\z')][string]$ReferenceDir,
    [Parameter(Mandatory)][ValidatePattern('\A[0-9a-f]{40}\z')][string]$BuildCommit,
    [Parameter(Mandatory)][string]$WrapperResult
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath

function Read-CMakeCache([string]$Directory) {
    $entries = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $Directory 'CMakeCache.txt')) {
        if ($line -match '^([^:#/][^:]*):[^=]+=(.*)$') {
            $entries[$Matches[1]] = $Matches[2]
        }
    }
    return $entries
}

function Get-RuntimeTreeDigest([string]$Directory) {
    $root = (Resolve-Path -LiteralPath $Directory).ProviderPath.TrimEnd('\')
    $rows = foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse | Sort-Object FullName) {
        $name = $file.FullName.Substring($root.Length).TrimStart('\')
        $hash = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        '{0}|{1}|{2}' -f $name, $file.Length, $hash
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join [char]10))
        return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

$cache = Read-CMakeCache (Join-Path $RepoRoot $BuildDir)
$reference = Read-CMakeCache (Join-Path $RepoRoot $ReferenceDir)
$keys = @(
    'CMAKE_GENERATOR', 'CMAKE_MAKE_PROGRAM', 'GGML_HIP', 'GGML_VULKAN',
    'GGML_BACKEND_DL', 'GGML_NATIVE', 'GGML_CPU_ALL_VARIANTS', 'GGML_OPENMP',
    'GGML_OPENMP_FETCH', 'GGML_RPC', 'FETCHCONTENT_FULLY_DISCONNECTED',
    'FETCHCONTENT_SOURCE_DIR_BORINGSSL', 'BORINGSSL_VERSION', 'LLAMA_BUILD_BORINGSSL',
    'LLAMA_BUILD_EXAMPLES', 'LLAMA_BUILD_TESTS', 'LLAMA_BUILD_TOOLS',
    'LLAMA_BUILD_SERVER', 'LLAMA_BUILD_UI', 'LLAMA_USE_PREBUILT_UI'
)
if ($Backend -eq 'Vulkan') {
    $keys += @('Vulkan_INCLUDE_DIR', 'Vulkan_LIBRARY', 'Vulkan_GLSLC_EXECUTABLE')
} else {
    $keys += @('AMDGPU_TARGETS', 'CMAKE_C_COMPILER', 'CMAKE_CXX_COMPILER', 'CMAKE_HIP_COMPILER')
}
$settings = foreach ($key in $keys) {
    if (!$cache.ContainsKey($key) -or !$reference.ContainsKey($key) -or $cache[$key] -cne $reference[$key]) {
        throw "CMake cache discrepancy for $key ($($reference[$key]) to $($cache[$key]))."
    }
    [pscustomobject]@{ Name = $key; Value = $cache[$key] }
}

$outer = Get-Content -LiteralPath $WrapperResult -Raw | ConvertFrom-Json
if ($outer.ExitCode -ne 0 -or $outer.Command -notcontains '-Offline' -or
    $outer.Command -notcontains $BuildDir -or $outer.Command -notcontains $Backend) {
    throw 'Expected a successful offline wrapper invocation for this output.'
}

$bin = Join-Path $RepoRoot "$BuildDir\bin\Release"
$manifestPath = Join-Path $bin 'evox2-build.json'
$cli = Join-Path $bin 'llama-cli.exe'
Import-Module (Join-Path $RepoRoot 'tools\evox2\lib\Evox2.Common.psm1')
$manifest = Read-Evox2BuildManifest -Executable $cli
if ($manifest.SchemaVersion -ne 1 -or $manifest.Backend -ne $Backend -or $manifest.Configuration -ne 'Release' -or
    !$manifest.Build.Executed -or !$manifest.Configure.MetadataRefresh.Executed -or
    $manifest.BuildIdentity.Status -ne 'Verified' -or $manifest.Source.Commit -ne $BuildCommit -or $manifest.Source.Dirty) {
    throw 'Build manifest provenance is invalid.'
}
if ($manifest.Validation.Version.ExitCode -ne 0 -or $manifest.Validation.ListDevices.ExitCode -ne 0 -or
    ($manifest.Validation.ListDevices.Tail -join ' ') -notmatch "$($Backend)0: AMD Radeon.*8060S") {
    throw 'Recorded CLI smoke failed.'
}

$artifacts = @(Get-ChildItem -LiteralPath $bin -File | Where-Object Extension -in '.dll', '.exe' |
    Sort-Object Name | ForEach-Object { Get-Evox2FileIdentity -Path $_.FullName -Sha256 })
$byName = @{}
foreach ($artifact in $artifacts) { $byName[$artifact.Name] = $artifact.Sha256 }
foreach ($item in $manifest.Artifacts) {
    if ($byName[$item.Name] -ne $item.Sha256) { throw "Manifest hash mismatch: $($item.Name)" }
}
$bench = Test-Evox2RuntimeArtifacts -Executable (Join-Path $bin 'llama-bench.exe') -Manifest $manifest
if ($bench.Status -ne 'Verified') { throw 'Standard bench artifact checks failed.' }

if ($Backend -eq 'Vulkan') {
    if ($manifest.BackendSettings.CpuAllVariants -ne $false) { throw 'Incorrect Vulkan CPU variant in manifest.' }
    $cacheRoot = Join-Path (Split-Path -Parent $RepoRoot) '_deps'
    $omp = Join-Path $cacheRoot 'openmp\llvm-openmp-22.1.8-x64\bin\libomp.dll'
    if ($byName['libomp.dll'] -ne (Get-FileHash -LiteralPath $omp).Hash) {
        throw 'Vulkan libomp differs from the validated cache.'
    }
} else {
    $runtime = $manifest.Runtime
    if ($runtime.RuntimePolicy.Verification -ne 'DllAndRuntimeDataHashesVerified' -or
        $runtime.RuntimeDlls.Count -ne 8 -or $runtime.RuntimeDataTrees.Count -ne 2) {
        throw 'ROCm runtime staging is incomplete.'
    }
    foreach ($dll in $runtime.RuntimeDlls) {
        if ((Get-FileHash -LiteralPath $dll.Source.Path).Hash -ne $dll.Source.Sha256 -or
            $byName[$dll.Name] -ne $dll.Source.Sha256 -or $dll.Source.Sha256 -ne $dll.Destination.Sha256) {
            throw "ROCm runtime DLL mismatch: $($dll.Name)"
        }
    }
    foreach ($tree in $runtime.RuntimeDataTrees) {
        $destination = Join-Path $bin $tree.Name
        if ($tree.Target -ne 'gfx1151' -or !(Test-Path -LiteralPath (Join-Path $destination 'library\gfx1151') -PathType Container) -or
            (Get-RuntimeTreeDigest $destination) -ne $tree.Destination.DigestSha256 -or
            (Get-RuntimeTreeDigest $tree.Source.Path) -ne $tree.Source.DigestSha256 -or
            $tree.Source.DigestSha256 -ne $tree.Destination.DigestSha256) {
            throw "ROCm runtime data tree mismatch: $($tree.Name)"
        }
    }
}

$identity = Get-Evox2LlamaIdentity -Executable $cli -SkipSystem
if (!$identity.Executable.Commit -or !$BuildCommit.StartsWith($identity.Executable.Commit) -or
    $identity.RuntimeArtifacts.Status -ne 'Verified' -or $identity.Executable.Sha256 -ne $manifest.ExecutableIdentity.Sha256) {
    throw 'Standard CLI identity check failed.'
}

[pscustomobject]@{
    Backend = $Backend
    Build = $BuildDir
    Wrapper = $outer
    Source = $manifest.Source.Commit
    Embedded = $identity.Executable.Commit
    Version = $manifest.Validation.Version
    Device = $manifest.Validation.ListDevices
    Identity = $manifest.BuildIdentity
    ManifestSha256 = (Get-FileHash -LiteralPath $manifestPath).Hash
    CliSha256 = $identity.Executable.Sha256
    RuntimeArtifactDigest = $identity.RuntimeArtifacts.Digest
    BenchArtifactDigest = $bench.Digest
    Reference = $ReferenceDir
    Settings = $settings
    Artifacts = $artifacts
    ManifestNames = @($manifest.Artifacts | ForEach-Object Name)
    Runtime = $manifest.Runtime
    Toolchain = $manifest.Toolchain
}
