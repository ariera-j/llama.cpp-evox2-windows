#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$TargetProcessId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath,

    [string]$RunId = '',

    [ValidateRange(1, 60)]
    [int]$IntervalSeconds = 2,

    # Expensive per-process CPU fallback (PerfProc CIM) is decoupled
    # from the high-frequency GPU/memory/disk resource samples.
    [ValidateRange(10, 300)]
    [int]$BackgroundIntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'

# Reuse the same lightweight process classification as the start/end snapshots.
Import-Module (Join-Path $PSScriptRoot 'Evox2.Benchmark.psm1') -Force

# Read physical memory and system commit page counts without WMI.
if (-not ('Evox2ResourceMemory' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Evox2ResourceMemory {
    [StructLayout(LayoutKind.Sequential)]
    public struct PerformanceInfo {
        public uint Size;
        public UIntPtr CommitTotal, CommitLimit, CommitPeak;
        public UIntPtr PhysicalTotal, PhysicalAvailable, SystemCache;
        public UIntPtr KernelTotal, KernelPaged, KernelNonpaged, PageSize;
        public uint HandleCount, ProcessCount, ThreadCount;
    }

    [DllImport("psapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetPerformanceInfo(ref PerformanceInfo info, uint size);
}
"@
}

function Get-MemorySnapshot {
    $info = New-Object 'Evox2ResourceMemory+PerformanceInfo'
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    if (![Evox2ResourceMemory]::GetPerformanceInfo([ref]$info, $info.Size)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "GetPerformanceInfo failed (Win32 error $errorCode)."
    }

    $pageSize = $info.PageSize.ToUInt64()
    $available = $info.PhysicalAvailable.ToUInt64() * $pageSize
    [pscustomobject]@{
        UsedPhysicalBytes = $info.PhysicalTotal.ToUInt64() * $pageSize - $available
        FreePhysicalBytes = $available
        CommittedBytes = $info.CommitTotal.ToUInt64() * $pageSize
        CommitLimitBytes = $info.CommitLimit.ToUInt64() * $pageSize
    }
}

function Format-Sample($Value, $Divisor = 1, $Digits = 1) {
    if ($null -ne $Value) { [math]::Round($Value / $Divisor, $Digits) }
}

function Get-AvailableCounterSamples {
    param([string[]]$Paths)

    try {
        (Get-Counter -Counter $Paths -ErrorAction Stop).CounterSamples
        return
    } catch {
        # An unavailable path must not discard other counters in the batch.
    }

    foreach ($path in $Paths) {
        try {
            (Get-Counter -Counter $path -ErrorAction Stop).CounterSamples
        } catch {
            if ($warnedCounterPaths.Add($path)) {
                Write-Warning "Counter unavailable: $path ($($_.FullyQualifiedErrorId)). $($_.Exception.Message)"
            }
        }
    }
}

function Get-SampleSum {
    param(
        [array]$Samples,
        [string]$PathPattern
    )

    $sum = (
        $Samples |
        Where-Object {
            $_.Path -like $PathPattern -and $_.Status -in 0, 1 -and
            $_.CookedValue -ge 0 -and ![double]::IsInfinity($_.CookedValue)
        } |
        Measure-Object -Property CookedValue -Sum
    ).Sum

    if ($null -ne $sum) { return [double]$sum }
}

function Get-GpuEngineCounterSummary {
    param(
        [array]$Samples,
        [string]$PathPattern,
        [double]$MaximumCookedValue = 100.5
    )

    $matched = @(
        $Samples |
        Where-Object {
            $_.Path -like $PathPattern
        }
    )

    $valid = @(
        $matched |
        Where-Object {
            $_.Status -in 0, 1 -and $_.CookedValue -ge 0 -and
            $_.CookedValue -le $MaximumCookedValue
        }
    )

    $sum = (
        $valid |
        Measure-Object -Property CookedValue -Sum
    ).Sum

    return [PSCustomObject]@{
        Sum           = $sum
        MatchedCount  = [int]$matched.Count
        RejectedCount = [int]($matched.Count - $valid.Count)
    }
}

$fullLogPath = [IO.Path]::GetFullPath($LogPath)
$logDir = Split-Path -Parent $fullLogPath
if ($logDir) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$StaticCounterPaths = @(
    '\Processor(_Total)\% Processor Time',

    '\PhysicalDisk(_Total)\% Disk Time',
    '\PhysicalDisk(_Total)\Disk Read Bytes/sec',
    '\PhysicalDisk(_Total)\Disk Write Bytes/sec',

    '\Memory\Pages Input/sec',
    '\Memory\Page Reads/sec',
    '\Memory\Page Faults/sec',

    '\GPU Local Adapter Memory(*)\Local Usage',
    '\GPU Adapter Memory(*)\Dedicated Usage',
    '\GPU Adapter Memory(*)\Shared Usage',
    '\GPU Adapter Memory(*)\Total Committed'
)

$previousTimestamp = $null
$sampleIndex = 0
$warnedCounterPaths = [Collections.Generic.HashSet[string]]::new()
$warnedInvalidGpuEngineCounter = $false
$previousBackgroundSnapshot = $null
$backgroundSampleCount = 0
$nextBackgroundSampleAt = (Get-Date).AddSeconds($BackgroundIntervalSeconds)

while ($true) {
    $loopStart = Get-Date

    try {
        $target = Get-Process -Id $TargetProcessId -ErrorAction Stop
    } catch {
        break
    }

    $processName = $target.ProcessName
    $processPath = $null
    $processStart = $null

    try { $processPath = $target.Path } catch {}
    try { $processStart = $target.StartTime.ToString('o') } catch {}

    $memory = Get-MemorySnapshot

    $processCounterPaths = @(
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Local Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Dedicated Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Shared Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Total Committed",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Non Local Usage",
        "\GPU Engine(pid_${TargetProcessId}_*)\Utilization Percentage"
    )

    $staticSamples = @(Get-AvailableCounterSamples -Paths $StaticCounterPaths)
    $processSamples = @(Get-AvailableCounterSamples -Paths $processCounterPaths)
    $samples = $staticSamples + $processSamples
    $gpuProcessCountersAvailable = @(
        $processSamples | Where-Object {
            $_.Status -in 0, 1 -and $_.CookedValue -ge 0 -and ![double]::IsInfinity($_.CookedValue)
        }
    ).Count -gt 0

    $cpuPercent = Get-SampleSum $samples '*\processor(_total)\% processor time'

    $diskPercent = Get-SampleSum $samples '*\physicaldisk(_total)\% disk time'
    $diskReadBytesPerSec = Get-SampleSum $samples '*\physicaldisk(_total)\disk read bytes/sec'
    $diskWriteBytesPerSec = Get-SampleSum $samples '*\physicaldisk(_total)\disk write bytes/sec'

    $committedBytes = $memory.CommittedBytes
    $commitLimitBytes = $memory.CommitLimitBytes
    $committedPercent = if ($commitLimitBytes -gt 0) { 100 * $committedBytes / $commitLimitBytes }

    $pagesInputPerSec = Get-SampleSum $samples '*\memory\pages input/sec'
    $pageReadsPerSec = Get-SampleSum $samples '*\memory\page reads/sec'
    $pageFaultsPerSec = Get-SampleSum $samples '*\memory\page faults/sec'

    $adapterLocalBytes = Get-SampleSum $samples '*\gpu local adapter memory(*)\local usage'
    $adapterDedicatedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\dedicated usage'
    $adapterSharedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\shared usage'
    $adapterCommittedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\total committed'

    $gpuLocalBytes = $null
    $gpuDedicatedBytes = $null
    $gpuSharedBytes = $null
    $gpuCommittedBytes = $null
    $gpuNonLocalBytes = $null
    $gpuEnginePercent = $null

    if ($gpuProcessCountersAvailable) {
        $gpuLocalBytes = Get-SampleSum $samples "*\gpu process memory(pid_${TargetProcessId}_*)\local usage"
        $gpuDedicatedBytes = Get-SampleSum $samples "*\gpu process memory(pid_${TargetProcessId}_*)\dedicated usage"
        $gpuSharedBytes = Get-SampleSum $samples "*\gpu process memory(pid_${TargetProcessId}_*)\shared usage"
        $gpuCommittedBytes = Get-SampleSum $samples "*\gpu process memory(pid_${TargetProcessId}_*)\total committed"
        $gpuNonLocalBytes = Get-SampleSum $samples "*\gpu process memory(pid_${TargetProcessId}_*)\non local usage"
        # Each individual GPU Engine utilization counter is a percentage and
        # should be in the 0..100 range. The sum may legitimately exceed 100
        # because several engines can be active at the same time.
        #
        # Windows occasionally emits a corrupted CookedValue for one engine
        # instance (for example ~1.8e14%). Reject only the invalid individual
        # values, not the multi-engine sum.
        $gpuEngineSummary = Get-GpuEngineCounterSummary `
            -Samples $samples `
            -PathPattern "*\gpu engine(pid_${TargetProcessId}_*)\utilization percentage" `
            -MaximumCookedValue 100.5

        $gpuEnginePercent = $gpuEngineSummary.Sum
        $gpuEngineMatchedCount = if ($gpuEngineSummary.MatchedCount -gt 0) { $gpuEngineSummary.MatchedCount }
        $gpuEngineRejectedCount = if ($gpuEngineSummary.MatchedCount -gt 0) { $gpuEngineSummary.RejectedCount }

        if ($gpuEngineRejectedCount -gt 0 -and -not $warnedInvalidGpuEngineCounter) {
            Write-Warning (
                (
                    'Discarded {0} invalid GPU engine utilization counter value(s) outside 0..100.5%. ' +
                    'The multi-engine utilization sum itself is allowed to exceed 100%.'
                ) -f $gpuEngineRejectedCount
            )
            $warnedInvalidGpuEngineCounter = $true
        }
    } else {
        $gpuEngineMatchedCount = $null
        $gpuEngineRejectedCount = $null
    }

    # The resource-counter timestamp is taken BEFORE optional slow WMI
    # collection so it describes the CPU/GPU/disk counter observation, not
    # the completion of the separate named-process activity snapshot.
    $timestamp = Get-Date
    $actualIntervalSeconds = if ($previousTimestamp) {
        [math]::Round(($timestamp - $previousTimestamp).TotalSeconds, 3)
    } else {
        0
    }
    $previousTimestamp = $timestamp
    $sampleIndex++

    # The optional named-process CPU fallback may take several seconds on
    # protected Windows processes (PerfProc CIM). Do NOT invoke it on each
    # 2-second resource sample. Defer the first probe until the configured
    # interval and schedule subsequent probes relative to their COMPLETION,
    # preventing back-to-back probes when acquisition takes longer.
    #
    # Start/end snapshots in Measure-LlamaCli / Measure-LlamaBench remain
    # outside inference execution, including on runs shorter than this period.
    $backgroundSampleTaken = $false
    $backgroundNow = $null
    $backgroundDelta = $null
    $backgroundCollectionMilliseconds = $null
    $backgroundSampleIntervalSecondsActual = $null

    if ((Get-Date) -ge $nextBackgroundSampleAt) {
        $backgroundSampleTaken = $true
        $backgroundStopwatch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $backgroundNow = Get-Evox2BackgroundActivitySnapshot
            if ($null -ne $previousBackgroundSnapshot) {
                $backgroundDelta = Compare-Evox2BackgroundActivitySnapshots `
                    -Before $previousBackgroundSnapshot -After $backgroundNow
                $backgroundSampleIntervalSecondsActual = $backgroundDelta.DurationSeconds
            }
            $previousBackgroundSnapshot = $backgroundNow
            $backgroundSampleCount++
        } catch {
            Write-Warning "Background activity probe failed: $($_.Exception.Message)"
        } finally {
            $backgroundStopwatch.Stop()
            $backgroundCollectionMilliseconds = [math]::Round($backgroundStopwatch.Elapsed.TotalMilliseconds, 1)
            $nextBackgroundSampleAt = (Get-Date).AddSeconds($BackgroundIntervalSeconds)
        }
    }

    $usedRamGiB = Format-Sample $memory.UsedPhysicalBytes 1GB 3
    $freeRamGiB = Format-Sample $memory.FreePhysicalBytes 1GB 3

    $collectionMilliseconds = [math]::Round(((Get-Date) - $loopStart).TotalMilliseconds, 0)

    [pscustomobject]@{
        Timestamp                     = $timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff')
        RunId                         = $RunId
        SampleIndex                   = $sampleIndex
        SampleIntervalSecondsActual   = $actualIntervalSeconds
        CounterCollectionMilliseconds = $collectionMilliseconds

        TargetPID                     = $TargetProcessId
        TargetProcessName             = $processName
        TargetProcessPath             = $processPath
        TargetProcessStart            = $processStart
        GpuProcessCountersAvailable   = $gpuProcessCountersAvailable

        UsedRAM_GiB                   = $usedRamGiB
        FreeRAM_GiB                   = $freeRamGiB
        CommittedPercent              = Format-Sample $committedPercent
        Committed_GiB                 = Format-Sample $committedBytes 1GB 3
        CommitLimit_GiB               = Format-Sample $commitLimitBytes 1GB 3

        PagesInput_PerSec             = Format-Sample $pagesInputPerSec
        PageReads_PerSec              = Format-Sample $pageReadsPerSec
        PageFaults_PerSec             = Format-Sample $pageFaultsPerSec

        TargetWS_GiB                  = Format-Sample $target.WorkingSet64 1GB 3
        TargetPrivate_GiB             = Format-Sample $target.PrivateMemorySize64 1GB 3
        TargetVirtual_GiB             = Format-Sample $target.VirtualMemorySize64 1GB 3

        TargetGPULocal_GiB            = Format-Sample $gpuLocalBytes 1GB 3
        TargetGPUDedicated_GiB        = Format-Sample $gpuDedicatedBytes 1GB 3
        TargetGPUShared_GiB           = Format-Sample $gpuSharedBytes 1GB 3
        TargetGPUTotalCommitted_GiB   = Format-Sample $gpuCommittedBytes 1GB 3
        TargetGPUNonLocal_GiB         = Format-Sample $gpuNonLocalBytes 1GB 3
        TargetGPUEngineSum_Percent    = Format-Sample $gpuEnginePercent
        GpuEngineCounterInstances     = $gpuEngineMatchedCount
        GpuEngineRejectedValues       = $gpuEngineRejectedCount

        AdapterLocal_GiB              = Format-Sample $adapterLocalBytes 1GB 3
        AdapterDedicated_GiB          = Format-Sample $adapterDedicatedBytes 1GB 3
        AdapterShared_GiB             = Format-Sample $adapterSharedBytes 1GB 3
        AdapterTotalCommitted_GiB     = Format-Sample $adapterCommittedBytes 1GB 3

        CPU_Percent                   = Format-Sample $cpuPercent
        Disk_Percent                  = Format-Sample $diskPercent
        DiskRead_MiBps                = Format-Sample $diskReadBytesPerSec 1MB 2
        DiskWrite_MiBps               = Format-Sample $diskWriteBytesPerSec 1MB 2

        BackgroundIntervalSeconds     = $BackgroundIntervalSeconds
        BackgroundSampleTaken         = $backgroundSampleTaken
        BackgroundSampleCount         = $backgroundSampleCount
        BackgroundSampleTimestampUtc  = if ($backgroundNow) { $backgroundNow.TimestampUtc } else { '' }
        BackgroundSampleIntervalSecondsActual = $backgroundSampleIntervalSecondsActual
        BackgroundCollectionMilliseconds = $backgroundCollectionMilliseconds
        BackgroundProbeStatus         = if ($backgroundNow) { $backgroundNow.Status } elseif ($backgroundSampleTaken) { 'ProbeError' } else { 'NotSampled' }
        BackgroundCpuCoverage         = if ($backgroundDelta) { $backgroundDelta.CpuCoverage } elseif ($backgroundNow) { 'FirstSample' } else { 'NotSampled' }
        BackgroundCpuComparedCount    = if ($backgroundDelta) { $backgroundDelta.CpuComparedCount } else { $null }
        BackgroundCpuKnownCount       = if ($backgroundDelta) { $backgroundDelta.CpuKnownCount } else { $null }
        BackgroundObservedNames       = if ($backgroundNow) { (@($backgroundNow.Processes | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ';') } else { '' }
        BackgroundActiveNames         = if ($backgroundDelta) { ($backgroundDelta.ActiveNames -join ';') } else { '' }
        BackgroundBusyNames           = if ($backgroundDelta) { ($backgroundDelta.BusyNames -join ';') } else { '' }
        BackgroundCpuDeltaSeconds     = if ($backgroundDelta) { $backgroundDelta.CpuDeltaSeconds } else { $null }
        BackgroundCpuPercentOfSystem  = if ($backgroundDelta) { $backgroundDelta.CpuPercentOfSystem } else { $null }
        BackgroundNoisePossible       = if ($backgroundDelta) { $backgroundDelta.PossibleNoise } else { $null }
    } | Export-Csv -LiteralPath $fullLogPath -Append -NoTypeInformation -Encoding UTF8

    $elapsedMilliseconds = ((Get-Date) - $loopStart).TotalMilliseconds
    $sleepMilliseconds = [math]::Max(
        0,
        ($IntervalSeconds * 1000) - $elapsedMilliseconds
    )

    if ($sleepMilliseconds -gt 0) {
        Start-Sleep -Milliseconds ([int]$sleepMilliseconds)
    }
}

if ($sampleIndex -eq 0) {
    throw "Resource monitor collected no samples for PID $TargetProcessId."
}
