#requires -Version 5.1
[CmdletBinding()]
param([string]$ReferenceClone = '')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Evox2.Common.psm1')
Import-Module (Join-Path $PSScriptRoot '..\lib\Evox2.RuntimeDependencies.psm1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('evox2-runtime-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
$cli = Join-Path $root 'llama-cli.exe'
$bench = Join-Path $root 'llama-bench.exe'
function Assert-Status($Executable, $Manifest, $Status, $Issue = '', $Scope = 'RuntimeDependenciesV1') {
    $result = Test-Evox2RuntimeArtifacts $Executable $Manifest
    if ($result.Status -ne $Status -or $result.Scope -ne $Scope -or
        ($Issue -and ($result.Issues -join ' ') -notmatch $Issue)) {
        throw "Expected $Status ($Issue) for $Executable, received $($result.Status): $($result.Issues)"
    }
}
try {
    $imports = @{
        'llama-cli.exe' = @('llama-cli-impl.dll')
        'llama-bench.exe' = @('llama-bench-impl.dll')
        'llama-cli-impl.dll' = @('llama.dll')
        'llama-bench-impl.dll' = @('llama.dll')
        'llama.dll' = @()
        'ggml-vulkan.dll' = @('libomp.dll')
        'ggml-rpc.dll' = @()
        'libomp.dll' = @()
    }
    $files = @(foreach ($name in $imports.Keys) {
        $file = Join-Path $root $name
        [IO.File]::WriteAllText($file, $name)
        [pscustomobject]@{
            Name = $name
            Sha256 = (Get-FileHash -LiteralPath $file).Hash
            Kind = if ($name -eq 'libomp.dll') { 'BundledRuntime' } else { 'Product' }
            BundledImports = $imports[$name]
            ExternalImports = @()
        }
    })
    ($files | Where-Object Name -eq 'llama.dll').ExternalImports = @('MSVCP140.dll')
    $ext = [pscustomobject]@{
        Version = 1; Provenance = 'BuildCompleted'; Backend = 'Vulkan'; Inspection = 'PEImportsAndConfiguredBackends'
        Files = $files
        ConfigurationRequired = @('ggml-vulkan.dll')
        CpuVariants = @()
        External = @([pscustomobject]@{ Name = 'MSVCP140.dll'; Evidence = 'SystemDirectoryCandidate'; ObservedPath = 'C:\Windows\System32\MSVCP140.dll'; Sha256 = ('0' * 64) })
        DataTrees = @()
        Executables = @(
            [pscustomobject]@{ Name = 'llama-cli.exe'; Required = @('llama-cli.exe','llama-cli-impl.dll','llama.dll','ggml-vulkan.dll','libomp.dll') },
            [pscustomobject]@{ Name = 'llama-bench.exe'; Required = @('llama-bench.exe','llama-bench-impl.dll','llama.dll','ggml-vulkan.dll','libomp.dll') }
        )
    }
    $legacy = [pscustomobject]@{ Backend = 'Vulkan'; Artifacts = @($files | Where-Object Name -ne 'ggml-rpc.dll') }
    Assert-Status $cli $legacy 'Verified' '' 'LegacyArtifacts'
    $manifest = [pscustomobject]@{ Backend = 'Vulkan'; RuntimeDependencies = $ext }
    Assert-Status $cli $manifest 'Verified'
    Assert-Status $bench $manifest 'Verified'
    Move-Item -LiteralPath (Join-Path $root 'ggml-rpc.dll') -Destination (Join-Path $root 'rpc.saved')
    Assert-Status $cli $manifest 'Verified'
    Move-Item -LiteralPath (Join-Path $root 'llama-bench-impl.dll') -Destination (Join-Path $root 'bench.saved')
    Assert-Status $cli $manifest 'Verified'
    Assert-Status $bench $manifest 'Mismatch' 'Missing required'
    [IO.File]::WriteAllText((Join-Path $root 'libomp.dll'), 'changed')
    Assert-Status $cli $manifest 'Mismatch' 'hash mismatch'
    [IO.File]::WriteAllText((Join-Path $root 'libomp.dll'), 'libomp.dll')
    Move-Item -LiteralPath (Join-Path $root 'ggml-vulkan.dll') -Destination (Join-Path $root 'vulkan.saved')
    Assert-Status $cli $manifest 'Mismatch' 'Missing required'
    Move-Item -LiteralPath (Join-Path $root 'vulkan.saved') -Destination (Join-Path $root 'ggml-vulkan.dll')
    $ext.Provenance = 'Observed'
    Assert-Status $cli $manifest 'Unverified'
    $ext.Provenance = 'BuildCompleted'
    $ext.Files = $files + @($files[0])
    Assert-Status $cli $manifest 'Mismatch' 'duplicated'
    $ext.Files = $files
    $name = $files[0].Name
    $files[0].Name = '..\outside.dll'
    Assert-Status $cli $manifest 'Mismatch' 'Invalid runtime dependency name'
    $files[0].Name = $name
    $saved = $ext.Executables
    $ext.Executables = @()
    Assert-Status $cli $manifest 'Mismatch' 'Missing dependency entry'
    $ext.Executables = $saved
    $manifest.RuntimeDependencies = $null
    Assert-Status $cli $manifest 'Mismatch' 'Invalid runtime dependency header'
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $root 'evox2-build.json') -Encoding UTF8
    try {
        Get-Evox2LlamaIdentity -Executable $cli -SkipSystem | Out-Null
        throw 'Expected pre-execution manifest rejection.'
    } catch {
        if ($_.Exception.Message -notmatch 'Invalid runtime dependency header') { throw }
    }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}

if ($ReferenceClone) {
    foreach ($sample in @(@('Vulkan','build-w5v'),@('ROCm','build-w5r'))) {
        $build = Join-Path $ReferenceClone $sample[1]
        $bin = Join-Path $build 'bin\Release'
        $manifestPath = Join-Path $bin 'evox2-build.json'
        $initial = (Get-FileHash -LiteralPath $manifestPath).Hash
        $cli = Join-Path $bin 'llama-cli.exe'
        $existing = Read-Evox2BuildManifest $cli
        Assert-Status $cli $existing 'Verified' '' 'LegacyArtifacts'
        $ext = Get-Evox2RuntimeDependencies -BinDir $bin -BuildDir $build -Backend $sample[0] -Runtime $existing.Runtime -Built $false
        $existing | Add-Member NoteProperty RuntimeDependencies $ext
        $observed = ConvertFrom-Json ($existing | ConvertTo-Json -Depth 32)
        foreach ($name in 'llama-cli.exe','llama-bench.exe','llama-server.exe') {
            Assert-Status (Join-Path $bin $name) $observed 'Unverified'
        }
        if ($sample[0] -eq 'ROCm' -and ($ext.DataTrees.Count -ne 2 -or $ext.ConfigurationRequired -notcontains 'amdhip64_7.dll')) {
            throw 'Missing ROCm SDK runtime dependencies.'
        }
        if ((Get-FileHash -LiteralPath $manifestPath).Hash -ne $initial) { throw 'Reference manifest changed.' }
    }
}
'Runtime dependency tests passed.'
