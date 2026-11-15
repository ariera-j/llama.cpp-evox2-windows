#requires -Version 5.1
[CmdletBinding()]
param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$paths = @(
    'tools\evox2\build\Evox2.Build.psm1', 'tools\evox2\build\Build-Vulkan.ps1',
    'tools\evox2\build\Build-ROCm.ps1', 'tools\evox2\lib\Evox2.Common.psm1',
    'tools\evox2\benchmark\Measure-LlamaCli.ps1', 'tools\evox2\benchmark\Summarize-MtpDiagnostics.ps1',
    'tools\evox2\benchmark\Repair-MtpDiagnostics.ps1',
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

    # The native parser prints a progress line. It must not become a matrix row.
    $fixture = Join-Path $temp 'diagnostic-run'
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $begin = 'mtp_diag v=1 kind=begin id=server-test parent=none mode=wall domain=server event=target_evaluation ctx=0x1 role=target phase=generation thread=1 t0_us=10 t1_us=0 elapsed_us=0 rc=0 complete=0'
    $end = 'mtp_diag v=1 kind=end id=server-test parent=none mode=wall domain=server event=target_evaluation ctx=0x1 role=target phase=generation thread=1 t0_us=10 t1_us=20 elapsed_us=10 rc=0 complete=1'
    [IO.File]::WriteAllText((Join-Path $fixture 'stderr.log'), "$begin`n$end`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'result.json'), '{"GenerationEvalMilliseconds":1.0}')
    $summaryOutput = @(& (Join-Path $repo 'tools\evox2\benchmark\Summarize-MtpDiagnostics.ps1') `
        -RunDirectory $fixture -Python $Python)
    if ($summaryOutput.Count -ne 0) { throw 'Diagnostic summary polluted the success pipeline.' }
    $report = Get-Content -LiteralPath (Join-Path $fixture 'mtp-diagnostics.json') -Raw | ConvertFrom-Json
    if ($report.Status -ne 'Complete' -or
        -not (Test-Path -LiteralPath (Join-Path $fixture 'mtp-diagnostics.csv'))) {
        throw 'Diagnostic summary sidecar test failed.'
    }

    # Reproduce a shell location that differs from Python's inherited process
    # directory. Both wrappers must resolve relative paths in PowerShell.
    $matrixFixture = Join-Path $temp 'diagnostic-matrix'
    $processFixture = Join-Path $temp 'process-directory'
    New-Item -ItemType Directory -Path $matrixFixture, $processFixture | Out-Null
    $child = [PSCustomObject]@{
        RunId = 'run1'; Status = 'DIAGNOSTIC_INCOMPLETE'; DiagnosticStatus = 'Incomplete'
        DiagnosticError = 'fixture'; ExitCode = 0; RunException = $null
        GenerationEvalMilliseconds = 1.0; GenerationTokensPerSecond = 19.69
    }
    $child | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'result.json') -Encoding UTF8
    [PSCustomObject]@{ RunId = 'run1'; Status = 'DIAGNOSTIC_INCOMPLETE'; TG = 19.69 } |
        Export-Csv -LiteralPath (Join-Path $fixture 'summary.csv') -NoTypeInformation -Encoding UTF8
    $run = [PSCustomObject]@{
        MatrixRunId = 'M001'; ChildRunId = 'run1'; ChildRunDirectory = $fixture
        MatrixStatus = 'DIAGNOSTIC_INCOMPLETE'
    }
    $row = [PSCustomObject]@{ MatrixRunId = 'M001'; ChildStatus = 'DIAGNOSTIC_INCOMPLETE'; TG = 19.69 }
    [PSCustomObject]@{
        Runs = @($run); Results = @($row); RunCountPlanned = 1; RunCountFinished = 1
        Complete = $false; StoppedEarly = $true; StatusCounts = @{ OK = 0; NonOK = 1 }
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $matrixFixture 'matrix-result.json') -Encoding UTF8
    $run | Export-Csv -LiteralPath (Join-Path $matrixFixture 'matrix-runs.csv') -NoTypeInformation -Encoding UTF8
    $row | Export-Csv -LiteralPath (Join-Path $matrixFixture 'matrix-results.csv') -NoTypeInformation -Encoding UTF8
    $savedProcessDirectory = [Environment]::CurrentDirectory
    Push-Location $temp
    try {
        [Environment]::CurrentDirectory = $processFixture
        $relativeSummaryOutput = @(& (Join-Path $repo 'tools\evox2\benchmark\Summarize-MtpDiagnostics.ps1') `
            -RunDirectory '.\diagnostic-run' -Python $Python)
        if ($relativeSummaryOutput.Count -ne 0) { throw 'Relative summary polluted the success pipeline.' }
        $relativeRepairOutput = @(& (Join-Path $repo 'tools\evox2\benchmark\Repair-MtpDiagnostics.ps1') `
            -MatrixDirectory '.\diagnostic-matrix' -Python $Python)
        if ($relativeRepairOutput.Count -ne 0) { throw 'Relative repair polluted the success pipeline.' }
        $repaired = Get-Content -LiteralPath (Join-Path $matrixFixture 'matrix-result.json') -Raw | ConvertFrom-Json
        $repairedChild = Get-Content -LiteralPath (Join-Path $fixture 'result.json') -Raw | ConvertFrom-Json
        if (-not $repaired.Complete -or $repaired.StatusCounts.OK -ne 1 -or
            $repairedChild.Status -ne 'OK' -or $repairedChild.GenerationTokensPerSecond -ne 19.69) {
            throw 'Relative diagnostic recovery failed or changed performance metrics.'
        }
    } finally {
        [Environment]::CurrentDirectory = $savedProcessDirectory
        Pop-Location
    }
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Push-Location $repo
try {
    & $Python -m unittest discover -s tools/evox2/tests -p test_mtp_diagnostics.py -v
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic parser tests failed.' }
} finally { Pop-Location }
Write-Host 'PowerShell parsing, artifact verification, relative paths, summary pipeline and diagnostic parser checks passed.'
