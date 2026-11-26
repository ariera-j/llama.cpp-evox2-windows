#requires -Version 5.1
Set-StrictMode -Version Latest

function Get-Evox2OsStartup {
    [CmdletBinding()]
    param()

    $snapshot = [ordered]@{
        CapturedAtUtc = $null
        LastBootUpTimeUtc = $null
        LastBootUpTimeSource = $null
        CimStatus = 'Unavailable'
        UptimeSeconds = $null
        UptimeHours = $null
        UptimeSource = $null
        UptimeErrorId = $null
        ShutdownEventStatus = 'NotChecked'
        PreviousShutdownMode = $null
        PreviousNormalShutdownUtc = $null
        PreviousOsDowntimeSeconds = $null
        BootAfterUnexpectedShutdown = $null
        FastStartupEnabled = $null
        FastStartupStatus = 'Unavailable'
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property LastBootUpTime -OperationTimeoutSec 3 -ErrorAction Stop
        if ($null -ne $os.LastBootUpTime) {
            $snapshot.LastBootUpTimeUtc = $os.LastBootUpTime.ToUniversalTime().ToString('o')
            $snapshot.LastBootUpTimeSource = 'Win32_OperatingSystem.LastBootUpTime'
            $snapshot.CimStatus = 'OK'
        }
    } catch { $snapshot.CimStatus = $_.FullyQualifiedErrorId }

    try {
        $null = Get-WinEvent -LogName System -MaxEvents 1 -ErrorAction Stop
        $boots = @(Get-WinEvent -FilterHashtable @{
            LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12
        } -MaxEvents 2 -ErrorAction Stop)
        $latest = $boots[0]
        $bootXml = [xml]$latest.ToXml()
        $start = $bootXml.Event.EventData.Data | Where-Object Name -eq 'StartTime' | Select-Object -First 1
        if (!$snapshot.LastBootUpTimeUtc -and $start) {
            $snapshot.LastBootUpTimeUtc = ([DateTimeOffset]::Parse($start.'#text')).UtcDateTime.ToString('o')
            $snapshot.LastBootUpTimeSource = 'Kernel-General/12.StartTime'
        }
        $snapshot.ShutdownEventStatus = 'OK'
        # Use record order so a current-boot event cannot be confused with a prior-boot event.
        $startupFilter = "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=41 and EventRecordID >= $($latest.RecordId)]]"
        $unexpected = @(Get-Evox2StartupEvent -FilterXPath $startupFilter)
        if ($unexpected.Count) {
            $snapshot.BootAfterUnexpectedShutdown = $true
        } elseif ($boots.Count -eq 2) {
            $previousFilter = "EventRecordID > $($boots[1].RecordId) and EventRecordID < $($latest.RecordId)"
            $shutdown = Get-Evox2StartupEvent -FilterXPath "*[System[Provider[@Name='Microsoft-Windows-Kernel-General'] and EventID=13 and $previousFilter]]"
            if ($shutdown) {
                $shutdownXml = [xml]$shutdown.ToXml()
                $stop = $shutdownXml.Event.EventData.Data | Where-Object Name -eq 'StopTime' | Select-Object -First 1
                if ($stop -and $snapshot.LastBootUpTimeUtc) {
                    $stopped = [DateTimeOffset]::Parse($stop.'#text')
                    $gap = ([DateTimeOffset]::Parse($snapshot.LastBootUpTimeUtc) - $stopped).TotalSeconds
                    if ($gap -ge 0) {
                        $snapshot.BootAfterUnexpectedShutdown = $false
                        $snapshot.PreviousNormalShutdownUtc = $stopped.UtcDateTime.ToString('o')
                        $snapshot.PreviousOsDowntimeSeconds = [math]::Round($gap, 3)
                        $request = Get-Evox2StartupEvent -FilterXPath "*[System[Provider[@Name='User32'] and EventID=1074 and $previousFilter and EventRecordID < $($shutdown.RecordId)]]"
                        if ($request -and ($shutdown.TimeCreated - $request.TimeCreated).TotalMinutes -le 5) {
                            $requestXml = [xml]$request.ToXml()
                            $mode = $requestXml.Event.EventData.Data | Where-Object Name -eq 'param5' | Select-Object -First 1
                            if ($mode) { $snapshot.PreviousShutdownMode = $mode.'#text' }
                        }
                    }
                }
            }
        }
    } catch { $snapshot.ShutdownEventStatus = $_.FullyQualifiedErrorId }

    try {
        $fast = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction Stop
        if ($fast -in @(0, 1)) {
            $snapshot.FastStartupEnabled = ($fast -eq 1)
            $snapshot.FastStartupStatus = 'OK'
        }
    } catch { $snapshot.FastStartupStatus = $_.FullyQualifiedErrorId }

    try {
        if (-not ('Evox2.BenchmarkNativeUptime' -as [type])) {
            Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace Evox2 {
    public static class BenchmarkNativeUptime {
        [DllImport("kernel32.dll")]
        public static extern ulong GetTickCount64();
    }
}
'@ -ErrorAction Stop
        }
        $milliseconds = [Evox2.BenchmarkNativeUptime]::GetTickCount64()
        $snapshot.UptimeSeconds = $milliseconds / 1000.0
        $snapshot.UptimeHours = [math]::Round($milliseconds / 3600000.0, 6)
        $snapshot.UptimeSource = 'GetTickCount64'
    } catch { $snapshot.UptimeErrorId = $_.FullyQualifiedErrorId }
    $snapshot.CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
    [pscustomobject]$snapshot
}

function Get-Evox2StartupEvent {
    param([string]$FilterXPath)
    try {
        Get-WinEvent -LogName System -FilterXPath $FilterXPath -MaxEvents 1 -ErrorAction Stop
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*') { throw }
    }
}

Export-ModuleMember -Function Get-Evox2OsStartup
