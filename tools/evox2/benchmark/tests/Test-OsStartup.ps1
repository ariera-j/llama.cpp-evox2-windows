#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Evox2.OsStartup.psm1'
$startupModule = Import-Module $modulePath -Force -PassThru
$actual = Get-Evox2OsStartup
if ($actual.UptimeSource -ne 'GetTickCount64' -or $actual.UptimeSeconds -le 0 -or
    [math]::Abs($actual.UptimeHours * 3600 - $actual.UptimeSeconds) -gt 0.003) {
    throw 'Native elapsed uptime or hour conversion failed.'
}
if ($actual.ShutdownEventStatus -ne 'OK' -and
    ($null -ne $actual.PreviousOsDowntimeSeconds -or $null -ne $actual.BootAfterUnexpectedShutdown)) {
    throw 'Unavailable events must not produce confirmed shutdown history.'
}
& $startupModule {
    function script:Get-CimInstance { throw 'Simulated CIM denial' }
    function script:Get-WinEvent { throw 'Simulated event denial' }
    function script:Get-ItemPropertyValue { throw 'Simulated registry denial' }
    $missing = Get-Evox2OsStartup
    if ($null -ne $missing.LastBootUpTimeUtc -or $null -ne $missing.PreviousOsDowntimeSeconds -or
        $null -ne $missing.FastStartupEnabled -or $missing.UptimeSeconds -le 0) {
        throw 'A denied source replaced a missing field or discarded native uptime.'
    }
}
Remove-Module $startupModule
$actual | ConvertTo-Json -Compress
'OS startup checks passed.'
