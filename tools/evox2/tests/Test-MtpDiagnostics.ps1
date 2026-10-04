#requires -Version 5.1
[CmdletBinding()]
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$paths = @(
    'tools\evox2\build\Evox2.Build.psm1', 'tools\evox2\build\Build-Vulkan.ps1',
    'tools\evox2\build\Build-ROCm.ps1', 'tools\evox2\lib\Evox2.Common.psm1',
    'tools\evox2\benchmark\Measure-LlamaCli.ps1', 'tools\evox2\benchmark\Summarize-MtpDiagnostics.ps1',
    'tools\evox2\benchmark\configs\qwen38-r4-mtp-check.psd1',
    'tools\evox2\benchmark\configs\qwen38-r4-mtp-diagnostics.psd1',
    'tools\evox2\benchmark\configs\qwen38-r4-mtp-diagnostics-sync.psd1'
)
foreach ($relative in $paths) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $relative), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$relative : $($errors.Message -join '; ')" }
}
Import-Module (Join-Path $repo 'tools\evox2\lib\Evox2.Common.psm1') -Force
$temp = Join-Path ([IO.Path]::GetTempPath()) ('evox2-artifacts-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $names = @('llama-cli.exe', 'llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-vulkan.dll')
    foreach ($name in $names) { [IO.File]::WriteAllText((Join-Path $temp $name), 'fixture-' + $name) }
    $exe = Join-Path $temp 'llama-cli.exe'
    $manifest = [PSCustomObject]@{ Artifacts = @($names | ForEach-Object {
        Get-Evox2FileIdentity -Path (Join-Path $temp $_) -Sha256
    }) }
    $valid = Test-Evox2RuntimeArtifacts -Executable $exe -Manifest $manifest
    if ($valid.Status -ne 'Verified' -or -not $valid.Digest) { throw 'Matching identity test failed.' }
    [IO.File]::WriteAllText((Join-Path $temp 'ggml-vulkan.dll'), 'substituted')
    if ((Test-Evox2RuntimeArtifacts -Executable $exe -Manifest $manifest).Status -ne 'Mismatch') {
        throw 'DLL substitution test failed.'
    }
    if ((Test-Evox2RuntimeArtifacts -Executable $exe -Manifest $null).Status -ne 'MissingManifest') {
        throw 'Missing legacy manifest test failed.'
    }
    Remove-Item -LiteralPath (Join-Path $temp 'ggml-vulkan.dll')
    if ((Test-Evox2RuntimeArtifacts -Executable $exe -Manifest $manifest).Status -ne 'Mismatch') {
        throw 'Missing DLL test failed.'
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Push-Location $repo
try {
    & $Python -m unittest discover -s tools/evox2/tests -p test_mtp_diagnostics.py -v
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic parser tests failed.' }
} finally { Pop-Location }
Write-Host 'PowerShell parsing, artifact verification and diagnostic parser checks passed.'
