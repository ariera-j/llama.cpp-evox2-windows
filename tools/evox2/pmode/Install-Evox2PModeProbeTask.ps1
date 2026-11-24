#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
if (![Environment]::Is64BitProcess) { throw 'Use elevated 64-bit Windows PowerShell.' }

$root = 'C:\Program Files\Evox2\PModeProbe'
$probe = Join-Path $root 'pmode\Read-Evox2PMode.ps1'
$module = Join-Path $root 'lib\Evox2.Common.psm1'
$state = 'C:\ProgramData\Evox2\PMode\state.json'
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

foreach ($path in 'C:\Program Files', 'C:\Program Files\Evox2', $root,
    "$root\pmode", "$root\lib", 'C:\ProgramData\Evox2', 'C:\ProgramData\Evox2\PMode') {
    $item = Get-Item -LiteralPath $path -Force
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular directory: $path"
    }
}
foreach ($path in $probe, $module, $exe) {
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular file: $path"
    }
}

if (!$PSCmdlet.ShouldProcess('\Evox2\PModeProbe', 'Create a new read-only P-MODE task after reviewing the protected files and ACLs')) {
    return
}

$service = New-Object -ComObject Schedule.Service
$service.Connect()
try {
    $folder = $service.GetFolder('\Evox2')
} catch {
    if ($_.Exception.HResult -notin -2147024894, -2147024893) { throw }
    $folder = $service.GetFolder('\').CreateFolder('Evox2')
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$definition = $service.NewTask(0)
$definition.RegistrationInfo.Description = 'Read-only EVO-X2 P-MODE probe.'
$definition.Principal.UserId = $identity
$definition.Principal.LogonType = 3 # Interactive token
$definition.Principal.RunLevel = 1 # Highest
$definition.Settings.DisallowStartIfOnBatteries = $false
$definition.Settings.StopIfGoingOnBatteries = $false
$definition.Settings.ExecutionTimeLimit = 'PT1M'
$definition.Settings.MultipleInstances = 2 # IgnoreNew

$action = $definition.Actions.Create(0) # Exec
$action.Path = $exe
$action.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -OutputPath "{1}"' -f $probe, $state

# TASK_CREATE refuses registration when the task already exists.
$null = $folder.RegisterTaskDefinition('PModeProbe', $definition, 2, $identity, $null, 3, $null)
Write-Output "Created \Evox2\PModeProbe for $identity. Verify the definition and delegate task-specific access separately."
