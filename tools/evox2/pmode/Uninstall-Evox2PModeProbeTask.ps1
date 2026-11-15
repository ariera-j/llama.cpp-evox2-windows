#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TaskName = 'PModeProbe',
    [string]$TaskPath = '\Evox2\',
    [switch]$KeepStateFile
)

$ErrorActionPreference = 'Stop'

try {
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction Stop
    Write-Host "Removed scheduled task: $TaskPath$TaskName"
} catch {
    Write-Warning "Scheduled task was not removed: $($_.Exception.Message)"
}

if (-not $KeepStateFile) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $toolsRoot = Split-Path -Parent $scriptDir
    $commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
    Import-Module $commonModule -Force

    $statePath = Get-Evox2PModeStatePath
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        Remove-Item -LiteralPath $statePath -Force
        Write-Host "Removed state file: $statePath"
    }
}
