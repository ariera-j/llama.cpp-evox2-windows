#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TaskName = 'PModeProbe',
    [string]$TaskPath = '\Evox2\',
    [string]$StatePath = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
$probeScript = Join-Path $scriptDir 'Read-Evox2PMode.ps1'

Import-Module $commonModule -Force

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Get-Evox2PModeStatePath
}
$StatePath = [IO.Path]::GetFullPath($StatePath)

$stateDir = Split-Path -Parent $StatePath
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Windows PowerShell not found: $windowsPowerShell"
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$argument = @(
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $probeScript),
    '-OutputPath', ('"{0}"' -f $StatePath)
) -join ' '

$action = New-ScheduledTaskAction -Execute $windowsPowerShell -Argument $argument
$principal = New-ScheduledTaskPrincipal -UserId $currentIdentity -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Principal $principal -Settings $settings -Description 'Read-only GMKtec Evo-X2 P-MODE probe for benchmark metadata.' -Force | Out-Null

Write-Host "Registered scheduled task: $TaskPath$TaskName"
Write-Host "State file: $StatePath"
Write-Host "User: $currentIdentity"

$before = $null
if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    $before = (Get-Item -LiteralPath $StatePath).LastWriteTimeUtc
}

Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath

$deadline = (Get-Date).AddSeconds(8)
$updated = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 100
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        continue
    }

    $item = Get-Item -LiteralPath $StatePath
    if ($null -eq $before -or $item.LastWriteTimeUtc -gt $before) {
        $updated = $true
        break
    }
}

if (-not $updated) {
    throw "The task was registered, but no fresh P-MODE state appeared within 8 seconds."
}

$state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$state | Format-List | Out-Host

if (-not [bool]$state.ProbeSucceeded) {
    throw "The scheduled task ran, but the P-MODE probe failed: $($state.Error)"
}

Write-Host ''
Write-Host 'P-MODE scheduled probe is ready for normal benchmark runs.'
