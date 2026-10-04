#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$MatrixDirectory, [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$parser = Join-Path $PSScriptRoot 'mtp_diagnostics.py'
# Reparse existing logs, restore diagnostic-only failures and matrix/CSV status.
# No executable, model, sampling or inference process is launched.
& $Python $parser ([IO.Path]::GetFullPath($MatrixDirectory)) --repair-matrix | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Diagnostic recovery failed. Original logs are retained; inspect the new sidecars.'
}
