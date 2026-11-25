#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][int]$ParentId,
    [ValidateRange(100, 1000)][int]$IntervalMs = 250,
    [ValidateRange(0, 120)][int]$PostSeconds = 5,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = 'Stop'
$clock = [Diagnostics.Stopwatch]::StartNew()
$frequency = [Diagnostics.Stopwatch]::Frequency
$state = [ordered]@{
    RunId = $RunId; MonitorPid = $PID; IntervalMs = $IntervalMs; StopwatchFrequency = $frequency
    StartedUtc = [datetime]::UtcNow.ToString('o'); ReadyUtc = $null; AttachedUtc = $null
    TargetId = $null; TargetStartUtc = $null; TargetExitObservedUtc = $null; AttachError = $null
    FinishedUtc = $null; StopReason = 'Error'; Error = $null
    TotalSamples = 0; NativeFailures = 0; ProcessFailures = 0
    SystemSource = 'GetPerformanceInfo'; ProcessSource = 'System.Diagnostics.Process'; MemoryUnit = 'bytes'
}
$writer = $null
$target = $null
$parent = $null
$utf8 = [Text.UTF8Encoding]::new($false)
$csv = Join-Path $RunDirectory 'ram-detail.csv'
$ready = Join-Path $RunDirectory 'ram-ready'
$attach = Join-Path $RunDirectory 'ram-attach.json'
$stop = Join-Path $RunDirectory 'ram-stop'
$exitSignal = Join-Path $RunDirectory 'ram-exited'
$status = Join-Path $RunDirectory 'ram-monitor.json'
$lastTick = $null
$lastPhase = $null
$nextFlush = 0
$targetName = $null
$epoch = 'Pre'
$postDeadline = $null

function ConvertTo-CsvLine {
    param([object[]]$Values)
    ($Values | ForEach-Object {
        if ($null -eq $_) { '""' }
        elseif ($_ -is [IFormattable]) { '"' + $_.ToString($null, [Globalization.CultureInfo]::InvariantCulture).Replace('"','""') + '"' }
        else { '"' + ([string]$_).Replace('"','""') + '"' }
    }) -join ','
}

try {
    Import-Module (Join-Path $PSScriptRoot 'Evox2.Memory.psm1')
    $parent = [Diagnostics.Process]::GetProcessById($ParentId)
    $null = $parent.Handle
    $writer = [IO.StreamWriter]::new($csv, $false, $utf8, 16384)
    $writer.WriteLine('RunId,TimestampUtc,StopwatchTicks,ElapsedMs,IntervalMsActual,Phase,NativeStatus,ProcessStatus,TargetPID,TargetName,TargetStartUtc,PhysicalTotalBytes,UsedRAMBytes,AvailableRAMBytes,CommitTotalBytes,CommitLimitBytes,CommitPercent,SystemCacheBytes,CommitPeakSinceBootBytes,WorkingSetBytes,PrivateBytes,VirtualBytes,NativeError,ProcessError')
    while ($true) {
        $elapsed = $clock.ElapsedMilliseconds
        if ($parent.HasExited) { $state.StopReason = 'ParentExited'; break }
        if ([IO.File]::Exists($stop)) { $state.StopReason = 'StoppedByLauncher'; break }
        if ($elapsed -ge (1000L * $TimeoutSeconds)) { $state.StopReason = 'Timeout'; break }

        if ($epoch -eq 'Pre' -and [IO.File]::Exists($attach)) {
            $ticket = [IO.File]::ReadAllText($attach) | ConvertFrom-Json
            $state.TargetId = $ticket.Id
            $state.TargetStartUtc = [string]$ticket.StartUtc
            $targetName = $ticket.Name
            try {
                $target = [Diagnostics.Process]::GetProcessById([int]$ticket.Id)
                $null = $target.Handle
                if ($target.StartTime.ToUniversalTime().Ticks -ne [long]$ticket.StartUtcTicks) {
                    throw 'Target PID does not match the launch start time.'
                }
            } catch {
                $state.AttachError = $_.Exception.Message
                if ($target) { $target.Dispose(); $target = $null }
            }
            if ($target) {
                $state.AttachedUtc = [datetime]::UtcNow.ToString('o')
                $epoch = 'Running'
            } else { $epoch = 'AwaitingTargetExit' }
        }

        if (($epoch -eq 'Running' -and $target.HasExited) -or
            ($epoch -in 'Pre','AwaitingTargetExit' -and [IO.File]::Exists($exitSignal))) {
            $state.TargetExitObservedUtc = [datetime]::UtcNow.ToString('o')
            $epoch = 'Post'
            $postDeadline = $elapsed + (1000L * $PostSeconds)
        }
        if ($epoch -eq 'Post' -and $elapsed -gt $postDeadline -and $lastPhase -eq 'Post') {
            $state.StopReason = 'PostWindowComplete'
            break
        }

        $now = [datetime]::UtcNow
        $tick = [Diagnostics.Stopwatch]::GetTimestamp()
        $gap = if ($null -ne $lastTick) { [math]::Round(($tick - $lastTick) * 1000.0 / $frequency, 3) }
        $lastTick = $tick
        $native = $null
        $nativeError = $null
        try { $native = Get-Evox2SystemMemory } catch {
            $nativeError = $_.Exception.Message
            $state.NativeFailures++
        }
        $process = @{}
        $processError = $null
        $processStatus = 'NotApplicable'
        $observedId = $null
        if ($epoch -eq 'AwaitingTargetExit') { $processStatus = 'Unavailable' }
        if ($epoch -eq 'Running') {
            $detail = Get-Evox2ProcessMemory $target
            $observedId = $state.TargetId
            $process = $detail.Values
            $processError = $detail.Error
            $processStatus = switch ($process.Count) {
                3 { 'Complete' }
                0 { 'Unavailable' }
                default { 'Partial' }
            }
            if ($processStatus -ne 'Complete') { $state.ProcessFailures++ }
        }
        $statusName = if ($native) { 'Complete' } else { 'Unavailable' }
        $writer.WriteLine((ConvertTo-CsvLine @(
            $RunId, $now.ToString('o'), $tick, $elapsed, $gap, $epoch, $statusName, $processStatus,
            $observedId, $(if ($observedId) { $targetName } else { $null }),
            $(if ($observedId) { $state.TargetStartUtc } else { $null }),
            $native.Total, $native.Used, $native.Available, $native.Commit, $native.CommitLimit,
            $native.CommitPercent, $native.Cache, $native.CommitPeak,
            $process.WorkingSet64, $process.PrivateMemorySize64, $process.VirtualMemorySize64,
            $nativeError, $processError
        )))
        $state.TotalSamples++
        $lastPhase = $epoch
        if ($elapsed -ge $nextFlush) {
            $writer.Flush()
            $nextFlush = $elapsed + 1000
        }
        if ($native -and !$state.ReadyUtc) {
            $writer.Flush()
            $state.ReadyUtc = $now.ToString('o')
            [IO.File]::WriteAllText($ready, $state.ReadyUtc, $utf8)
        }
        $delay = $IntervalMs - ($clock.ElapsedMilliseconds - $elapsed)
        if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
    }
} catch {
    $state.Error = $_.Exception.Message
    throw
} finally {
    if ($writer) { $writer.Dispose() }
    if ($target) { $target.Dispose() }
    if ($parent) { $parent.Dispose() }
    $state.FinishedUtc = [datetime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText($status, ($state | ConvertTo-Json -Depth 4), $utf8)
}
