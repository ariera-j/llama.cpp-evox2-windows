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
    [int]$IntervalSeconds = 2
)

$ErrorActionPreference = 'Stop'

function ConvertTo-GiB {
    param([double]$Bytes)
    [math]::Round($Bytes / 1GB, 3)
}

function Get-SampleSum {
    param(
        [array]$Samples,
        [string]$PathPattern
    )

    $sum = (
        $Samples |
        Where-Object {
            $_.Path -like $PathPattern -and $_.CookedValue -ge 0
        } |
        Measure-Object -Property CookedValue -Sum
    ).Sum

    if ($null -eq $sum) {
        return 0.0
    }

    return [double]$sum
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
            $_.CookedValue -ge 0 -and
            $_.CookedValue -le $MaximumCookedValue
        }
    )

    $sum = (
        $valid |
        Measure-Object -Property CookedValue -Sum
    ).Sum

    if ($null -eq $sum) {
        $sum = 0.0
    }

    return [PSCustomObject]@{
        Sum           = [double]$sum
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

$previousTimestamp = $null
$sampleIndex = 0
$warnedCounterFallback = $false
$warnedInvalidGpuEngineCounter = $false

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

    $os = Get-CimInstance Win32_OperatingSystem

    $processCounterPaths = @(
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Local Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Dedicated Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Shared Usage",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Total Committed",
        "\GPU Process Memory(pid_${TargetProcessId}_*)\Non Local Usage",
        "\GPU Engine(pid_${TargetProcessId}_*)\Utilization Percentage"
    )

    $gpuProcessCountersAvailable = $false

    try {
        $samples = (
            Get-Counter -Counter @($StaticCounterPaths + $processCounterPaths) -ErrorAction Stop
        ).CounterSamples
        $gpuProcessCountersAvailable = $true
    } catch {
        # A very common shutdown race is:
        #   1) Get-Process succeeds at the top of the loop,
        #   2) llama-cli exits while Get-Counter is collecting,
        #   3) the PID-scoped GPU counter instances disappear first.
        #
        # That is a normal end-of-run condition, not a monitoring failure.
        $targetStillRunning = Get-Process -Id $TargetProcessId -ErrorAction SilentlyContinue
        if ($null -eq $targetStillRunning) {
            break
        }

        try {
            $samples = (
                Get-Counter -Counter $StaticCounterPaths -ErrorAction Stop
            ).CounterSamples

            if (-not $warnedCounterFallback) {
                Write-Warning 'GPU process counters were unavailable while the target process was still running; continuing with adapter/system counters only.'
                $warnedCounterFallback = $true
            }
        } catch {
            Write-Warning "Counter collection failed: $($_.Exception.Message)"
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }
    }

    $cpuPercent = Get-SampleSum $samples '*\processor(_total)\% processor time'

    $diskPercent = Get-SampleSum $samples '*\physicaldisk(_total)\% disk time'
    $diskReadBytesPerSec = Get-SampleSum $samples '*\physicaldisk(_total)\disk read bytes/sec'
    $diskWriteBytesPerSec = Get-SampleSum $samples '*\physicaldisk(_total)\disk write bytes/sec'

    $committedPercent = Get-SampleSum $samples '*\memory\% committed bytes in use'
    $committedBytes = Get-SampleSum $samples '*\memory\committed bytes'
    $commitLimitBytes = Get-SampleSum $samples '*\memory\commit limit'
    $pagesInputPerSec = Get-SampleSum $samples '*\memory\pages input/sec'
    $pageReadsPerSec = Get-SampleSum $samples '*\memory\page reads/sec'
    $pageFaultsPerSec = Get-SampleSum $samples '*\memory\page faults/sec'

    $adapterLocalBytes = Get-SampleSum $samples '*\gpu local adapter memory(*)\local usage'
    $adapterDedicatedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\dedicated usage'
    $adapterSharedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\shared usage'
    $adapterCommittedBytes = Get-SampleSum $samples '*\gpu adapter memory(*)\total committed'

    $gpuLocalBytes = 0.0
    $gpuDedicatedBytes = 0.0
    $gpuSharedBytes = 0.0
    $gpuCommittedBytes = 0.0
    $gpuNonLocalBytes = 0.0
    $gpuEnginePercent = 0.0

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
        $gpuEngineMatchedCount = $gpuEngineSummary.MatchedCount
        $gpuEngineRejectedCount = $gpuEngineSummary.RejectedCount

        if ($gpuEngineRejectedCount -gt 0 -and -not $warnedInvalidGpuEngineCounter) {
            Write-Warning (
                'Discarded {0} invalid GPU engine utilization counter value(s) outside 0..100.5%. ' +
                'The multi-engine utilization sum itself is allowed to exceed 100%.' -f
                $gpuEngineRejectedCount
            )
            $warnedInvalidGpuEngineCounter = $true
        }
    } else {
        $gpuEngineMatchedCount = 0
        $gpuEngineRejectedCount = 0
    }

    $timestamp = Get-Date
    $actualIntervalSeconds = if ($previousTimestamp) {
        [math]::Round(($timestamp - $previousTimestamp).TotalSeconds, 3)
    } else {
        0
    }
    $previousTimestamp = $timestamp
    $sampleIndex++

    $usedRamGiB = [math]::Round(
        ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB,
        3
    )
    $freeRamGiB = [math]::Round($os.FreePhysicalMemory / 1MB, 3)
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
        CommittedPercent              = [math]::Round($committedPercent, 1)
        Committed_GiB                 = ConvertTo-GiB $committedBytes
        CommitLimit_GiB               = ConvertTo-GiB $commitLimitBytes

        PagesInput_PerSec             = [math]::Round($pagesInputPerSec, 1)
        PageReads_PerSec              = [math]::Round($pageReadsPerSec, 1)
        PageFaults_PerSec             = [math]::Round($pageFaultsPerSec, 1)

        TargetWS_GiB                  = ConvertTo-GiB $target.WorkingSet64
        TargetPrivate_GiB             = ConvertTo-GiB $target.PrivateMemorySize64
        TargetVirtual_GiB             = ConvertTo-GiB $target.VirtualMemorySize64

        TargetGPULocal_GiB            = ConvertTo-GiB $gpuLocalBytes
        TargetGPUDedicated_GiB        = ConvertTo-GiB $gpuDedicatedBytes
        TargetGPUShared_GiB           = ConvertTo-GiB $gpuSharedBytes
        TargetGPUTotalCommitted_GiB   = ConvertTo-GiB $gpuCommittedBytes
        TargetGPUNonLocal_GiB         = ConvertTo-GiB $gpuNonLocalBytes
        TargetGPUEngineSum_Percent    = [math]::Round($gpuEnginePercent, 1)
        GpuEngineCounterInstances     = $gpuEngineMatchedCount
        GpuEngineRejectedValues       = $gpuEngineRejectedCount

        AdapterLocal_GiB              = ConvertTo-GiB $adapterLocalBytes
        AdapterDedicated_GiB          = ConvertTo-GiB $adapterDedicatedBytes
        AdapterShared_GiB             = ConvertTo-GiB $adapterSharedBytes
        AdapterTotalCommitted_GiB     = ConvertTo-GiB $adapterCommittedBytes

        CPU_Percent                   = [math]::Round($cpuPercent, 1)
        Disk_Percent                  = [math]::Round($diskPercent, 1)
        DiskRead_MiBps                = [math]::Round($diskReadBytesPerSec / 1MB, 2)
        DiskWrite_MiBps               = [math]::Round($diskWriteBytesPerSec / 1MB, 2)
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
