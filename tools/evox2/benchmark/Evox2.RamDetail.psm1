#requires -Version 5.1
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Evox2.Benchmark.psm1')

function Write-RamEvent {
    param($Detail, [string]$Kind, [hashtable]$Data = @{})
    $stamp = [Diagnostics.Stopwatch]::GetTimestamp()
    $record = [ordered]@{
        RunId = $Detail.RunId
        Event = $Kind
        TimestampUtc = [datetime]::UtcNow.ToString('o')
        StopwatchTicks = $stamp
        StopwatchFrequency = [Diagnostics.Stopwatch]::Frequency
        ElapsedMs = [math]::Round(($stamp - $Detail.StartTick) * 1000.0 / [Diagnostics.Stopwatch]::Frequency, 3)
        Data = $Data
    }
    $Detail.Events.WriteLine(($record | ConvertTo-Json -Compress -Depth 5))
    if ($Kind -ne 'LogMarkerReceived') { $Detail.Events.Flush() }
}

function New-Evox2RamDetail {
    param([string]$RunDirectory, [string]$RunId, [hashtable]$Settings, [string]$StdOutPath, [string]$StdErrPath)
    [pscustomobject]@{
        RunId = $RunId; Directory = $RunDirectory; Settings = $Settings
        StartTick = [Diagnostics.Stopwatch]::GetTimestamp()
        LaunchTicks = $null; LaunchUtc = $null; ExitUtc = $null; ExitTicks = $null; OsExitUtc = $null; TargetStartUtc = $null
        MarkerPhases = @{}
        Process = $null; Ready = $false; Error = $null; MarkerError = $null; Events = $null
        EventPath = Join-Path $RunDirectory 'ram-events.jsonl'
        MonitorPath = Join-Path $RunDirectory 'ram-monitor.json'
        CsvPath = Join-Path $RunDirectory 'ram-detail.csv'
        StderrPath = Join-Path $RunDirectory 'ram-monitor.stderr.log'
        Tails = @(
            @{ Name = 'stdout'; Path = $StdOutPath; Offset = 0L; Line = 0; Pending = ''; DroppingLine = $false }
            @{ Name = 'stderr'; Path = $StdErrPath; Offset = 0L; Line = 0; Pending = ''; DroppingLine = $false }
        )
    }
}

function Start-Evox2RamDetail {
    param($Detail)
    $Detail.Events = [IO.StreamWriter]::new($Detail.EventPath, $false, [Text.UTF8Encoding]::new($false))
    Write-RamEvent $Detail 'MonitorLaunchRequested'
    $argsList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned',
        '-File', (Join-Path $PSScriptRoot 'Monitor-Evox2RamDetail.ps1'),
        '-RunDirectory', $Detail.Directory, '-RunId', $Detail.RunId, '-ParentId', "$PID",
        '-IntervalMs', "$($Detail.Settings.IntervalMs)", '-PostSeconds', "$($Detail.Settings.PostSeconds)",
        '-TimeoutSeconds', "$($Detail.Settings.TimeoutSeconds)"
    )
    $launch = @{
        FilePath = Join-Path $PSHOME 'powershell.exe'
        ArgumentList = ($argsList | ForEach-Object { ConvertTo-Evox2WindowsArgument -Value $_ }) -join ' '
        RedirectStandardError = $Detail.StderrPath
        NoNewWindow = $true
        PassThru = $true
        ErrorAction = 'Stop'
    }
    $Detail.Process = Start-Process @launch
    $null = $Detail.Process.Handle
}

function Wait-Evox2RamDetailReady {
    param($Detail)
    $readyFile = Join-Path $Detail.Directory 'ram-ready'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (!$Detail.Process.HasExited -and $clock.Elapsed.TotalSeconds -lt $Detail.Settings.ReadyTimeoutSeconds) {
        if ([IO.File]::Exists($readyFile)) {
            Write-RamEvent $Detail 'MonitorReadyObserved'
            $Detail.Ready = $true
            return
        }
        Start-Sleep -Milliseconds 25
    }
    throw 'RAM monitor did not produce a valid pre-launch sample before the readiness deadline.'
}

function Wait-Evox2RamBaseline {
    param($Detail)
    if (!$Detail.Ready) { return }
    if ($Detail.Settings.PreSeconds -gt 0) {
        $null = $Detail.Process.WaitForExit(1000 * $Detail.Settings.PreSeconds)
    }
    if ($Detail.Process.HasExited) {
        $Detail.Ready = $false
        throw 'RAM monitor ended during the pre-launch observation.'
    }
}

function Write-Evox2RamLaunch {
    param($Detail)
    if ($Detail.Events) {
        $Detail.LaunchTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        $Detail.LaunchUtc = [datetime]::UtcNow.ToString('o')
        Write-RamEvent $Detail 'TargetLaunchRequested'
    }
}

function Connect-Evox2RamTarget {
    param($Detail, [Diagnostics.Process]$Target)
    if (!$Detail.Events) { return }
    $ticket = @{ Id = $Target.Id; Name = $null; StartUtc = $null; StartUtcTicks = $null }
    try {
        $start = $Target.StartTime.ToUniversalTime()
        $ticket.StartUtc = $start.ToString('o')
        $ticket.StartUtcTicks = $start.Ticks
        $ticket.Name = $Target.ProcessName
    } catch {}
    $Detail.TargetStartUtc = $ticket.StartUtc
    Write-RamEvent $Detail 'TargetPidObserved' $ticket
    if ($Detail.Ready -and !$Detail.Process.HasExited) {
        $path = Join-Path $Detail.Directory 'ram-attach.json'
        [IO.File]::WriteAllText("$path.tmp", ($ticket | ConvertTo-Json -Compress))
        [IO.File]::Move("$path.tmp", $path)
    }
}

$phasePatterns = [ordered]@{
    BackendInitialization = '^(load_backend:|ggml_vulkan:|ggml_cuda_init:|ggml_hip_init:|(?:llama_model_load_from_file_impl|llama_prepare_model_devices):\s*using device)'
    GgufMetadataReported = '^(llama_model_loader:\s*loaded meta data|llama_model_loader:\s*Dumping metadata)'
    TensorLoadOrPlacement = '^(load_tensors:\s*(loading model tensors|offload|offloaded|.+model buffer size)|llama_model_load:\s*loading model tensors)'
    ContextInitialization = '^(llama_init_from_model:\s*|llama_context:\s*(constructing|n_seq_max))'
    KvOrComputeBuffers = '^(llama_kv_cache(?:_unified)?:\s*.+KV buffer size|llama_context:\s*.+compute buffer size|sched_reserve:\s*.+compute buffer size)'
    GraphReserve = '^(sched_reserve:\s*|llama_context:\s*(graph nodes|graph splits|reserving))'
    WarmupReported = '^(?:[^:]+:\s*)?warming up the model|(?:^|\s)warming up the model with an empty run|^llama-bench:\s*.*warmup'
    PromptRunReported = '^llama-bench: benchmark \d+/\d+: prompt run'
    GenerationRunReported = '^llama-bench: benchmark \d+/\d+: generation run'
    PromptEvalReported = '(?:^|:)\s*prompt eval time\s*='
    TokenEvalReported = '(?:^|:)\s*eval time\s*='
}

function Read-Evox2RamMarkers {
    param($Detail, [switch]$Final)
    if (!$Detail.Events -or $Detail.MarkerError) { return }
    try {
        $buffer = New-Object byte[] 65536
        foreach ($tail in $Detail.Tails) {
            if (![IO.File]::Exists($tail.Path)) { continue }
            $stream = [IO.File]::Open($tail.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try {
                $stream.Position = $tail.Offset
                $limit = if ($Final) { 16 } else { 1 }
                for ($chunk = 0; $chunk -lt $limit; $chunk++) {
                    $length = $stream.Read($buffer, 0, $buffer.Length)
                    $tail.Offset = $stream.Position
                    if ($length -eq 0) { break }
                    $parts = ($tail.Pending + [Text.Encoding]::ASCII.GetString($buffer, 0, $length)).Split([char]10)
                    $tail.Pending = $parts[-1]
                    for ($lineIndex = 0; $lineIndex -lt $parts.Count - 1; $lineIndex++) {
                        $tail.Line++
                        if (!$tail.DroppingLine) {
                            $line = $parts[$lineIndex] -replace '^(?:\d+\.\d+\.\d+\.\d+\s+[A-Z]\s+)', ''
                            foreach ($phase in $phasePatterns.Keys) {
                                if ($line -match $phasePatterns[$phase]) {
                                    $Detail.MarkerPhases[$phase] = $true
                                    Write-RamEvent $Detail 'LogMarkerReceived' @{ Stream = $tail.Name; Line = $tail.Line; Phase = $phase }
                                    break
                                }
                            }
                        }
                        $tail.DroppingLine = $false
                    }
                    if ($tail.Pending.Length -gt 8192) {
                        $tail.Pending = ''
                        $tail.DroppingLine = $true
                    }
                }
                if ($Final -and $tail.Offset -lt $stream.Length) {
                    Write-RamEvent $Detail 'LogTailLimit' @{ Stream = $tail.Name; UnreadBytes = $stream.Length - $tail.Offset }
                }
            } finally { $stream.Dispose() }
        }
        $Detail.Events.Flush()
    } catch { $Detail.MarkerError = $_.Exception.Message }
}

function Stop-Evox2RamDetail {
    param($Detail, [Diagnostics.Process]$Target)
    try {
        $targetExited = ($null -ne $Target -and $Target.HasExited)
        if ($targetExited) {
            $Detail.ExitTicks = [Diagnostics.Stopwatch]::GetTimestamp()
            $Detail.ExitUtc = [datetime]::UtcNow.ToString('o')
            try { $Detail.OsExitUtc = $Target.ExitTime.ToUniversalTime().ToString('o') } catch {}
            if ($Detail.Events) { Write-RamEvent $Detail 'TargetExitObserved' @{ Id = $Target.Id; OsExitUtc = $Detail.OsExitUtc } }
            if ($Detail.Process -and !$Detail.Process.HasExited) {
                [IO.File]::WriteAllText((Join-Path $Detail.Directory 'ram-exited'), '')
            }
        }
        Read-Evox2RamMarkers $Detail -Final
        if ($Detail.Process -and !$Detail.Process.HasExited) {
            if (!$targetExited -or !$Detail.Ready) {
                [IO.File]::WriteAllText((Join-Path $Detail.Directory 'ram-stop'), '')
                $null = $Detail.Process.WaitForExit(2000)
            } else {
                $null = $Detail.Process.WaitForExit(($Detail.Settings.PostSeconds + 3) * 1000)
            }
        }
    } catch {
        if (!$Detail.Error) { $Detail.Error = $_.Exception.Message }
    } finally {
        if ($Detail.Process -and !$Detail.Process.HasExited) {
            try {
                $Detail.Process.Kill()
                $null = $Detail.Process.WaitForExit(2000)
                if (!$Detail.Error) { $Detail.Error = 'RAM monitor exceeded its stop deadline.' }
            } catch {
                if (!$Detail.Error) { $Detail.Error = $_.Exception.Message }
            }
        }
        if ($Detail.Events) {
            try { Write-RamEvent $Detail 'MonitorStopObserved' }
            catch { if (!$Detail.MarkerError) { $Detail.MarkerError = $_.Exception.Message } }
            finally {
                try { $Detail.Events.Dispose() }
                catch { if (!$Detail.MarkerError) { $Detail.MarkerError = $_.Exception.Message } }
                $Detail.Events = $null
            }
        }
    }
}

function Get-RamSummaryStats {
    param([object[]]$Rows, [string]$Column)
    $values = @(foreach ($row in $Rows) {
        [double]$value = 0
        if ([double]::TryParse($row.$Column, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and
            $value -ge 0 -and ![double]::IsInfinity($value)) { $value }
    })
    $stats = $values | Measure-Object -Minimum -Maximum -Average
    [ordered]@{
        ValidCount = $values.Count
        MissingCount = $Rows.Count - $values.Count
        Minimum = $(if ($values.Count) { $stats.Minimum } else { $null })
        Maximum = $(if ($values.Count) { $stats.Maximum } else { $null })
        Average = $(if ($values.Count) { $stats.Average } else { $null })
    }
}

function Get-RamGpuRecovery {
    param([string]$Path, [string]$LaunchUtc, [string]$ExitUtc, [double]$ToleranceMb)
    $before = $null
    $after = $null
    $postCount = 0
    $postMin = $null
    $postMax = $null
    $duringMax = $null
    if ($LaunchUtc -and $ExitUtc -and [IO.File]::Exists($Path)) {
        foreach ($row in (Import-Csv -LiteralPath $Path)) {
            [datetime]$local = [datetime]::MinValue
            [double]$vram = 0
            if ($row.adlx_result -notin '0','1','2' -or
                ![datetime]::TryParseExact($row.timestamp_local, "yyyy-MM-dd'T'HH:mm:ss.fff",
                    [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$local) -or
                [TimeZoneInfo]::Local.IsAmbiguousTime($local) -or [TimeZoneInfo]::Local.IsInvalidTime($local) -or
                ![double]::TryParse($row.gpu_vram_mb, [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$vram) -or $vram -lt 0 -or
                [double]::IsNaN($vram) -or [double]::IsInfinity($vram)) { continue }
            $utc = $local.ToUniversalTime().ToString('o')
            if ($utc -lt $LaunchUtc) { $before = $vram }
            elseif ($utc -ge $ExitUtc) {
                $after = $vram
                $postCount++
                $postMin = if ($null -eq $postMin) { $vram } else { [math]::Min($postMin, $vram) }
                $postMax = if ($null -eq $postMax) { $vram } else { [math]::Max($postMax, $vram) }
            } else {
                $duringMax = if ($null -eq $duringMax) { $vram } else { [math]::Max($duringMax, $vram) }
            }
        }
    }
    [ordered]@{
        Status = $(if ($null -ne $before -and $null -ne $after) {
            if ($after -le $before + $ToleranceMb) { 'WithinTolerance' } else { 'AboveTolerance' }
        } else { 'Unobserved' })
        BaselineMb = $before; RunningMaximumMb = $duringMax; PostFinalMb = $after
        PostMinimumMb = $postMin; PostMaximumMb = $postMax; PostValidSamples = $postCount
        ToleranceMb = $ToleranceMb
    }
}

function Get-Evox2RamDetailResult {
    param($Detail, [string]$GpuCsvPath)
    $state = $null
    $rows = @()
    if ([IO.File]::Exists($Detail.MonitorPath)) { $state = Get-Content -LiteralPath $Detail.MonitorPath -Raw | ConvertFrom-Json }
    if ([IO.File]::Exists($Detail.CsvPath)) { $rows = @(Import-Csv -LiteralPath $Detail.CsvPath) }
    $baseline = $null
    $peak = $null
    $post = @()
    $nativeValid = @($rows | Where-Object NativeStatus -eq 'Complete')
    $running = @($rows | Where-Object {
        $Detail.LaunchTicks -and [long]$_.StopwatchTicks -ge $Detail.LaunchTicks -and
        $_.Phase -ne 'Post' -and (!$Detail.ExitTicks -or [long]$_.StopwatchTicks -lt $Detail.ExitTicks)
    })
    if ($Detail.LaunchTicks) {
        $baseline = $nativeValid | Where-Object { [long]$_.StopwatchTicks -lt $Detail.LaunchTicks } | Select-Object -Last 1
        $peak = $running | Where-Object NativeStatus -eq 'Complete' | Sort-Object {[long]$_.UsedRAMBytes} -Descending | Select-Object -First 1
        $post = @($nativeValid | Where-Object Phase -eq 'Post')
    }
    $lastPost = $post | Select-Object -Last 1
    $threshold = $null
    $aboveMs = 0.0
    $longestMs = 0.0
    $spanMs = 0.0
    $lastAboveTick = $null
    $aboveSamples = 0
    if ($baseline) {
        $threshold = [long]$baseline.UsedRAMBytes + $Detail.Settings.PeakThresholdMiB * 1MB
        foreach ($row in $running) {
            if ($row.NativeStatus -ne 'Complete' -or [long]$row.UsedRAMBytes -lt $threshold) {
                $lastAboveTick = $null
                $spanMs = 0
                continue
            }
            $aboveSamples++
            $tick = [long]$row.StopwatchTicks
            $gap = if ($null -ne $lastAboveTick) { ($tick - $lastAboveTick) * 1000.0 / [Diagnostics.Stopwatch]::Frequency }
            if ($null -ne $gap -and $gap -le 2 * $Detail.Settings.IntervalMs) {
                $aboveMs += $gap
                $spanMs += $gap
                $longestMs = [math]::Max($longestMs, $spanMs)
            } else { $spanMs = 0 }
            $lastAboveTick = $tick
        }
    }
    $metrics = [ordered]@{}
    foreach ($column in 'UsedRAMBytes','AvailableRAMBytes','CommitTotalBytes','SystemCacheBytes') {
        $metrics[$column] = Get-RamSummaryStats $running $column
    }
    $pidRows = @($rows | Where-Object { $_.Phase -in 'Running', 'AwaitingTargetExit' })
    foreach ($column in 'WorkingSetBytes','PrivateBytes','VirtualBytes') {
        $metrics[$column] = Get-RamSummaryStats $pidRows $column
    }
    $systemRecovery = 'Unobserved'
    if ($baseline -and $lastPost -and $Detail.ExitUtc) {
        $tolerance = $Detail.Settings.RecoveryToleranceMiB * 1MB
        $systemRecovery = if ([long]$lastPost.UsedRAMBytes -le [long]$baseline.UsedRAMBytes + $tolerance -and
            [long]$lastPost.CommitTotalBytes -le [long]$baseline.CommitTotalBytes + $tolerance) {
            'WithinTolerance'
        } else { 'AboveTolerance' }
    }
    $stopReason = if ($state) { $state.StopReason }
    $quality = if (!$Detail.Ready -or !$nativeValid.Count) { 'Unavailable' }
        elseif ($stopReason -ne 'PostWindowComplete' -or !$baseline -or !$peak -or !$post.Count -or
            !$state.AttachedUtc -or $state.ProcessFailures -gt 0 -or $state.NativeFailures -gt 0 -or $Detail.Error -or $Detail.MarkerError) { 'Partial' }
        else { 'Complete' }

    $markers = [ordered]@{}
    foreach ($name in $phasePatterns.Keys) {
        $markers[$name] = if ($Detail.MarkerPhases.ContainsKey($name)) { 'ReceiptObserved' } else { 'Unobserved' }
    }
    [ordered]@{
        SchemaVersion = 1; Requested = $true; Status = $quality; Ready = $Detail.Ready; Settings = $Detail.Settings
        Error = $Detail.Error; MarkerError = $Detail.MarkerError; MarkerPhases = $markers; Monitor = $state
        TargetLaunchUtc = $Detail.LaunchUtc; TargetStartUtc = $Detail.TargetStartUtc
        TargetExitObservedUtc = $Detail.ExitUtc; TargetOsExitUtc = $Detail.OsExitUtc
        Samples = $rows.Count; NativeMissing = $rows.Count - $nativeValid.Count
        IntervalMs = Get-RamSummaryStats @($rows | Select-Object -Skip 1) 'IntervalMsActual'
        BeforePidAttachRunningSamples = @($running | Where-Object Phase -eq 'Pre').Count
        RunningMetrics = $metrics; Baseline = $baseline; PostFinal = $lastPost; PostNativeSamples = $post.Count
        PeakUtc = $(if ($peak) { $peak.TimestampUtc } else { $null })
        PeakUsedMiB = $(if ($peak) { [math]::Round([long]$peak.UsedRAMBytes / 1MB, 3) } else { $null })
        IncreaseMiB = $(if ($peak -and $baseline) { [math]::Round(([long]$peak.UsedRAMBytes - [long]$baseline.UsedRAMBytes) / 1MB, 3) } else { $null })
        AboveThreshold = [ordered]@{
            ThresholdBytes = $threshold
            Samples = $(if ($baseline) { $aboveSamples } else { $null })
            ObservedSpanMs = $(if ($baseline) { [math]::Round($aboveMs, 3) } else { $null })
            LongestObservedSpanMs = $(if ($baseline) { [math]::Round($longestMs, 3) } else { $null })
            MaximumAdjacentGapMs = 2 * $Detail.Settings.IntervalMs
        }
        SystemRecovery = $systemRecovery
        GpuRecovery = Get-RamGpuRecovery $GpuCsvPath $Detail.LaunchUtc $Detail.ExitUtc $Detail.Settings.RecoveryToleranceMiB
        Files = @{
            Csv = $Detail.CsvPath; Events = $Detail.EventPath; Monitor = $Detail.MonitorPath
            MonitorStderr = $Detail.StderrPath
            Adlx = $(if ([IO.File]::Exists($GpuCsvPath)) { $GpuCsvPath } else { $null })
        }
    }
}

Export-ModuleMember -Function 'New-Evox2RamDetail','Start-Evox2RamDetail','Wait-Evox2RamDetailReady','Wait-Evox2RamBaseline',
    'Write-Evox2RamLaunch','Connect-Evox2RamTarget','Read-Evox2RamMarkers','Stop-Evox2RamDetail','Get-Evox2RamDetailResult'
