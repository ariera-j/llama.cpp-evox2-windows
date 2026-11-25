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

Import-Module (Join-Path $PSScriptRoot 'Evox2.Memory.psm1')

function ConvertTo-RoundedMetric {
    param($Value, [double]$Divisor = 1, [int]$Digits = 1)

    if ($null -ne $Value) { [math]::Round($Value / $Divisor, $Digits) }
}

function Read-CounterBatch {
    param([string[]]$Paths)

    $issues = @()
    $terminatingIssue = $null
    $samples = @(try {
        Get-Counter -Counter $Paths -ErrorAction SilentlyContinue -ErrorVariable +issues |
            ForEach-Object { $_.CounterSamples }
    } catch {
        $terminatingIssue = $_.Exception.Message
    })
    [pscustomobject]@{
        Samples = $samples
        Error = $(if ($terminatingIssue) { $terminatingIssue } elseif ($issues.Count) { $issues[0].Exception.Message } else { $null })
    }
}

function Test-TargetExited {
    param([Diagnostics.Process]$Process)

    try { return $Process.HasExited } catch {
        return ($null -eq (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue))
    }
}

function Get-CounterMetricSet {
    param([array]$Samples, [string[]]$Paths)

    $values = @{}
    $rejected = @{}
    $matchedPaths = @{}
    foreach ($sample in $Samples) {
        if ($null -eq $sample) { continue }
        foreach ($path in $Paths) {
            if ($sample.Path -notlike "*$path") { continue }
            $matchedPaths[$path]++
            $value = $sample.CookedValue
            # PDH_CSTATUS_VALID_DATA (0) and PDH_CSTATUS_NEW_DATA (1).
            $status = $sample.PSObject.Properties['Status']
            if ($null -eq $value -or $null -eq $status -or $status.Value -notin 0, 1 -or
                [double]::IsNaN($value) -or [double]::IsInfinity($value) -or
                $value -lt 0 -or ($path -eq $gpuEnginePath -and $value -gt 100.5)) {
                $rejected[$path]++
            } else {
                $values[$path] += [double]$value
            }
            break
        }
    }
    [pscustomobject]@{
        Values = $values
        Rejected = $rejected
        Matches = $matchedPaths
        Status = $(if ($values.Count -eq 0) { 'Unavailable' }
            elseif ($values.Count -ne $Paths.Count -or $rejected.Count -gt 0) { 'Partial' }
            else { 'Complete' })
    }
}

function Write-MonitorWarningOnce {
    param([string]$Key, [string]$Message)

    if (!$warned.ContainsKey($Key)) {
        $warned[$Key] = $true
        Write-Warning $Message
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

    '\Memory\% Committed Bytes In Use',
    '\Memory\Committed Bytes',
    '\Memory\Commit Limit',
    '\Memory\Pages Input/sec',
    '\Memory\Page Reads/sec',
    '\Memory\Page Faults/sec',

    '\GPU Local Adapter Memory(*)\Local Usage',
    '\GPU Adapter Memory(*)\Dedicated Usage',
    '\GPU Adapter Memory(*)\Shared Usage',
    '\GPU Adapter Memory(*)\Total Committed'
)

$processCounterPaths = @(
    "\GPU Process Memory(pid_${TargetProcessId}_*)\Local Usage",
    "\GPU Process Memory(pid_${TargetProcessId}_*)\Dedicated Usage",
    "\GPU Process Memory(pid_${TargetProcessId}_*)\Shared Usage",
    "\GPU Process Memory(pid_${TargetProcessId}_*)\Total Committed",
    "\GPU Process Memory(pid_${TargetProcessId}_*)\Non Local Usage",
    "\GPU Engine(pid_${TargetProcessId}_*)\Utilization Percentage"
)
$gpuEnginePath = $processCounterPaths[-1]
$allPaths = $StaticCounterPaths + $processCounterPaths

$target = Get-Process -Id $TargetProcessId -ErrorAction SilentlyContinue -ErrorVariable targetErrors
if ($null -eq $target) {
    if ($targetErrors.Count -gt 0 -and $targetErrors[0].CategoryInfo.Category -ne 'ObjectNotFound') {
        throw $targetErrors[0]
    }
    return
}

$processName = $target.ProcessName
$processPath = $null
$processStart = $null
try { $processPath = $target.Path } catch {}
try { $processStart = $target.StartTime.ToString('o') } catch {}

$previousTimestamp = $null
$sampleIndex = 0
$warned = @{}
$previousBackgroundSnapshot = $null
$backgroundSampleCount = 0
$nextBackgroundSampleAt = (Get-Date).AddSeconds($BackgroundIntervalSeconds)

while (-not (Test-TargetExited $target)) {
    $loopStart = Get-Date
    $sampleClock = [Diagnostics.Stopwatch]::StartNew()
    $native = $null
    $nativeError = $null
    $nativeMemoryUtc = [datetime]::UtcNow
    $nativeMemoryTick = [Diagnostics.Stopwatch]::GetTimestamp()
    try { $native = Get-Evox2SystemMemory } catch { $nativeError = $_.Exception.Message }
    $processMemoryUtc = [datetime]::UtcNow
    $processMemoryTick = [Diagnostics.Stopwatch]::GetTimestamp()
    $memory = Get-Evox2ProcessMemory $target
    $processValues = $memory.Values
    $processError = $memory.Error

    $batch = Read-CounterBatch $allPaths
    if (Test-TargetExited $target) { break }
    $system = Get-CounterMetricSet $batch.Samples $StaticCounterPaths
    $gpu = Get-CounterMetricSet $batch.Samples $processCounterPaths
    $counterError = $batch.Error
    if ($system.Status -eq 'Unavailable' -and $batch.Error) {
        # At most one fallback. Preserve partial PDH results from either call.
        $fallback = Read-CounterBatch $StaticCounterPaths
        if (Test-TargetExited $target) { break }
        $system = Get-CounterMetricSet $fallback.Samples $StaticCounterPaths
        if ($fallback.Error -and $fallback.Error -ne $counterError) {
            $counterError = "$counterError | static fallback: $($fallback.Error)"
        }
    }
    $sys = $system.Values
    $pidGpu = $gpu.Values
    $nativeStatus = if ($native) { 'Complete' } else { 'Unavailable' }
    $processStatus = switch ($processValues.Count) {
        3 { 'Complete' }
        0 { 'Unavailable' }
        default { 'Partial' }
    }
    if ($nativeError) { Write-MonitorWarningOnce NativeMemory $nativeError }
    if ($processError) { Write-MonitorWarningOnce ProcessMemory $processError }
    if ($counterError) { Write-MonitorWarningOnce PerfMon $counterError }
    if ($system.Rejected.Count -gt 0 -or $gpu.Rejected.Count -gt 0) {
        Write-MonitorWarningOnce InvalidCounter 'Invalid PerfMon counter values were omitted. See the rejected-value counts.'
    }

    # The resource-counter timestamp is taken BEFORE optional slow WMI
    # collection so it describes the CPU/GPU/disk counter observation, not
    # the completion of the separate named-process activity snapshot.
    $timestamp = Get-Date
    $actualIntervalSeconds = if ($previousTimestamp) {
        [math]::Round(($timestamp - $previousTimestamp).TotalSeconds, 3)
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
    $backgroundError = $null
    $collectionMilliseconds = [math]::Round($sampleClock.Elapsed.TotalMilliseconds, 0)

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
            $backgroundError = if ($backgroundNow.Error) { $backgroundNow.Error } else { $backgroundNow.CpuProbeError }
            if ($backgroundError) { Write-MonitorWarningOnce Background $backgroundError }
            $previousBackgroundSnapshot = $backgroundNow
            $backgroundSampleCount++
        } catch {
            $backgroundError = $_.Exception.Message
            Write-MonitorWarningOnce Background $backgroundError
        } finally {
            $backgroundStopwatch.Stop()
            $backgroundCollectionMilliseconds = [math]::Round($backgroundStopwatch.Elapsed.TotalMilliseconds, 1)
            $nextBackgroundSampleAt = (Get-Date).AddSeconds($BackgroundIntervalSeconds)
        }
    }

    [pscustomobject][ordered]@{
        Timestamp                     = $timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff')
        RunId                         = $RunId
        SampleIndex                   = $sampleIndex
        SampleIntervalSecondsActual   = $actualIntervalSeconds
        CounterCollectionMilliseconds = $collectionMilliseconds

        TargetPID                     = $TargetProcessId
        TargetProcessName             = $processName
        TargetProcessPath             = $processPath
        TargetProcessStart            = $processStart
        GpuProcessCountersAvailable   = ($gpu.Status -ne 'Unavailable')

        UsedRAM_GiB                   = ConvertTo-RoundedMetric $native.Used 1GB 3
        FreeRAM_GiB                   = ConvertTo-RoundedMetric $native.Available 1GB 3
        CommittedPercent              = ConvertTo-RoundedMetric $native.CommitPercent
        Committed_GiB                 = ConvertTo-RoundedMetric $native.Commit 1GB 3
        CommitLimit_GiB               = ConvertTo-RoundedMetric $native.CommitLimit 1GB 3

        PagesInput_PerSec             = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[7]]
        PageReads_PerSec              = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[8]]
        PageFaults_PerSec             = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[9]]

        TargetWS_GiB                  = ConvertTo-RoundedMetric $processValues.WorkingSet64 1GB 3
        TargetPrivate_GiB             = ConvertTo-RoundedMetric $processValues.PrivateMemorySize64 1GB 3
        TargetVirtual_GiB             = ConvertTo-RoundedMetric $processValues.VirtualMemorySize64 1GB 3

        TargetGPULocal_GiB            = ConvertTo-RoundedMetric $pidGpu[$processCounterPaths[0]] 1GB 3
        TargetGPUDedicated_GiB        = ConvertTo-RoundedMetric $pidGpu[$processCounterPaths[1]] 1GB 3
        TargetGPUShared_GiB           = ConvertTo-RoundedMetric $pidGpu[$processCounterPaths[2]] 1GB 3
        TargetGPUTotalCommitted_GiB   = ConvertTo-RoundedMetric $pidGpu[$processCounterPaths[3]] 1GB 3
        TargetGPUNonLocal_GiB         = ConvertTo-RoundedMetric $pidGpu[$processCounterPaths[4]] 1GB 3
        TargetGPUEngineSum_Percent    = ConvertTo-RoundedMetric $pidGpu[$gpuEnginePath]
        GpuEngineCounterInstances     = [int]$gpu.Matches[$gpuEnginePath]
        GpuEngineRejectedValues       = [int]$gpu.Rejected[$gpuEnginePath]

        AdapterLocal_GiB              = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[10]] 1GB 3
        AdapterDedicated_GiB          = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[11]] 1GB 3
        AdapterShared_GiB             = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[12]] 1GB 3
        AdapterTotalCommitted_GiB     = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[13]] 1GB 3

        CPU_Percent                   = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[0]]
        Disk_Percent                  = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[1]]
        DiskRead_MiBps                = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[2]] 1MB 2
        DiskWrite_MiBps               = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[3]] 1MB 2

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

        ResourceSchemaVersion         = 2
        TimestampUtc                  = $timestamp.ToUniversalTime().ToString('o')
        PhysicalTotal_GiB             = ConvertTo-RoundedMetric $native.Total 1GB 3
        SystemCache_GiB               = ConvertTo-RoundedMetric $native.Cache 1GB 3
        CommitPeakSinceBoot_GiB       = ConvertTo-RoundedMetric $native.CommitPeak 1GB 3
        PerfMonCommittedPercent       = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[4]]
        PerfMonCommitted_GiB          = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[5]] 1GB 3
        PerfMonCommitLimit_GiB        = ConvertTo-RoundedMetric $sys[$StaticCounterPaths[6]] 1GB 3
        NativeMemoryStatus            = $nativeStatus
        ProcessMemoryStatus           = $processStatus
        PerfMonSystemStatus           = $system.Status
        PerfMonPidGpuStatus           = $gpu.Status
        PerfMonRejectedValues         = [int]((@($system.Rejected.Values) + @($gpu.Rejected.Values) | Measure-Object -Sum).Sum)
        NativeMemoryError             = $nativeError
        ProcessMemoryError            = $processError
        PerfMonError                  = $counterError
        BackgroundProbeError          = $backgroundError
        NativeMemoryTimestampUtc      = $nativeMemoryUtc.ToString('o')
        NativeMemoryStopwatchTicks    = $nativeMemoryTick
        ProcessMemoryTimestampUtc     = $processMemoryUtc.ToString('o')
        ProcessMemoryStopwatchTicks   = $processMemoryTick
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
