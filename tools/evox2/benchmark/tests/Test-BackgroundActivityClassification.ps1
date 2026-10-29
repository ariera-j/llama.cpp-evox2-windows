#requires -Version 5.1
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\Evox2.Benchmark.psm1') -Force

function New-TestSnapshot {
    param(
        [Parameter(Mandatory = $true)][datetime]$When,
        [AllowNull()][object]$CpuSeconds,
        [switch]$NoProcesses
    )

    $processes = if ($NoProcesses) {
        @()
    } else {
        @([pscustomobject]@{
            Name       = 'MsMpEng'
            Pid        = 41001
            StartedUtc = '2026-10-20T00:00:00.0000000Z'
            CpuSeconds = $CpuSeconds
        })
    }

    return [pscustomobject]@{
        TimestampUtc = $When.ToUniversalTime().ToString('o')
        Status       = 'Observed'
        Processes    = @($processes)
    }
}

function Assert-Evox2 {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$t0 = [datetime]::UtcNow.AddSeconds(-4)
$t1 = $t0.AddSeconds(3)

# Regression case: a process list exists but every CPU counter is unreadable.
$a = New-TestSnapshot -When $t0 -CpuSeconds $null
$b = New-TestSnapshot -When $t1 -CpuSeconds $null
$x = Compare-Evox2BackgroundActivitySnapshots -Before $a -After $b
Assert-Evox2 ($x.Status -eq 'CpuUnavailable') 'Unreadable CPU => CpuUnavailable'
Assert-Evox2 ($x.CpuKnownCount -eq 0) 'Unreadable CPU => zero known counters'
Assert-Evox2 ($null -eq $x.PossibleNoise) 'Unreadable CPU => unknown, never False'
Write-Host 'PASS unreadable CPU counters => CpuUnavailable / PossibleNoise=null'

# Valid readings with no CPU time increase are an observed quiet interval.
$a = New-TestSnapshot -When $t0 -CpuSeconds 12.0
$b = New-TestSnapshot -When $t1 -CpuSeconds 12.0
$x = Compare-Evox2BackgroundActivitySnapshots -Before $a -After $b
Assert-Evox2 ($x.Status -eq 'Observed') 'Known zero delta => Observed'
Assert-Evox2 ($x.CpuKnownCount -eq 1) 'Known zero delta => one CPU counter'
Assert-Evox2 ($x.PossibleNoise -eq $false) 'Known zero delta => False'
Write-Host 'PASS known zero-CPU interval => Observed / PossibleNoise=False'

# A synthetic workload far above the all-core threshold must be flagged.
$busyDelta = [math]::Max(1.0, [Environment]::ProcessorCount * 0.2)
$a = New-TestSnapshot -When $t0 -CpuSeconds 12.0
$b = New-TestSnapshot -When $t1 -CpuSeconds (12.0 + $busyDelta)
$x = Compare-Evox2BackgroundActivitySnapshots -Before $a -After $b
Assert-Evox2 ($x.Status -eq 'Observed') 'Known busy delta => Observed'
Assert-Evox2 ($x.PossibleNoise -eq $true) 'Known busy delta => True'
Assert-Evox2 ($x.BusyNames -contains 'MsMpEng') 'BusyNames includes target process'
Write-Host 'PASS synthetic CPU workload => PossibleNoise=True'

# Both observation boundaries without any relevant processes are not
# equivalent to a probe failure.
$a = New-TestSnapshot -When $t0 -NoProcesses
$b = New-TestSnapshot -When $t1 -NoProcesses
$x = Compare-Evox2BackgroundActivitySnapshots -Before $a -After $b
Assert-Evox2 ($x.Status -eq 'NoCandidates') 'No process => NoCandidates'
Assert-Evox2 ($x.PossibleNoise -eq $false) 'No observed process => False'
Write-Host 'PASS no observed candidates => NoCandidates'

Write-Host 'ALL SYNTHETIC BACKGROUND-ACTIVITY REGRESSIONS PASS'
