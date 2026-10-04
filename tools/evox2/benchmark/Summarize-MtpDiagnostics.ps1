#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RunDirectory, [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$parser = Join-Path $PSScriptRoot 'mtp_diagnostics.py'
& $Python $parser ([IO.Path]::GetFullPath($RunDirectory))
if ($LASTEXITCODE -ne 0) {
    throw "Diagnostic report is incomplete. Raw log and partial report are preserved in $RunDirectory"
}
