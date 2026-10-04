#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RunDirectory, [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$parser = Join-Path $PSScriptRoot 'mtp_diagnostics.py'
# Keep the parser's progress message off the success pipeline. Measurement
# scripts return structured rows to Invoke-BenchmarkMatrix through that stream.
& $Python $parser ([IO.Path]::GetFullPath($RunDirectory)) | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Diagnostic report is incomplete. Raw log and partial report are preserved in $RunDirectory"
}
