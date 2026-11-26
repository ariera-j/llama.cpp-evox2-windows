#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot,
    [ValidateSet('off','normal','detail250','detail100','combined250','adlx250')][string[]]$OnlyCase = @(),
    [switch]$PulseFixture
)

$ErrorActionPreference = 'Stop'
if ($PulseFixture) {
    function Invoke-MemoryPulse([string]$Name, [int]$DurationMs) {
        $length = 32MB
        $mem = [Runtime.InteropServices.Marshal]::AllocHGlobal($length)
        try {
            for ($offset = 0; $offset -lt $length; $offset += [Environment]::SystemPageSize) {
                [Runtime.InteropServices.Marshal]::WriteByte($mem, $offset, [byte]51)
            }
            [Console]::WriteLine("PULSE $Name START $([Diagnostics.Stopwatch]::GetTimestamp())")
            [Threading.Thread]::Sleep($DurationMs)
            [Console]::WriteLine("PULSE $Name END $([Diagnostics.Stopwatch]::GetTimestamp())")
        } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($mem) }
    }
    [Console]::WriteLine('load_backend: synthetic startup')
    Start-Sleep -Milliseconds 300
    [Console]::Error.WriteLine('llama_model_loader: loaded meta data synthetic')
    Start-Sleep -Milliseconds 2300
    [Console]::WriteLine("QUIET END $([Diagnostics.Stopwatch]::GetTimestamp())")
    for ($j=1; $j -le 6; $j++) {
        Invoke-MemoryPulse "short-$j" 130
        Start-Sleep -Milliseconds (299 + 37 * $j)
    }
    [Console]::Error.WriteLine('llama_context: constructing synthetic')
    Start-Sleep -Seconds 9
    Invoke-MemoryPulse 'long' 2600
    [Console]::Error.WriteLine('fixture: prompt eval time = 1 ms')
    Start-Sleep -Milliseconds 800
    [Console]::Error.WriteLine('fixture: eval time = 1 ms')
    Start-Sleep -Seconds 5
    return
}

if (!$OutputRoot) { throw 'Specify a new -OutputRoot directory.' }
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot already exists.' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
$benchmark = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $benchmark 'Evox2.Benchmark.psm1')
Import-Module (Join-Path $benchmark 'Evox2.RamDetail.psm1')
$exe = Join-Path $PSHOME 'powershell.exe'
$adlxPath = 'C:\llama-build\adlx-gpu-monitor\build\bin\evox2-adlx-gpu-monitor.exe'

if (-not ('Evox2TestProcessIo' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Evox2TestProcessIo {
    [StructLayout(LayoutKind.Sequential)]
    public struct Counters {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetProcessIoCounters(IntPtr process, out Counters counters);
}
'@
}

function Measure-MonitorProcess($Process, $Usage) {
    if (!$Process) { return }
    try {
        $Process.Refresh()
        $Usage.CpuMs = [math]::Round($Process.TotalProcessorTime.TotalMilliseconds, 1)
        $peak = [math]::Max($Process.PeakWorkingSet64, $Process.WorkingSet64) / 1MB
        if ($peak -gt 0) { $Usage.PeakWorkingSetMiB = [math]::Round([math]::Max($peak, [double]$Usage.PeakWorkingSetMiB), 2) }
    } catch {}
    try {
        $io = New-Object 'Evox2TestProcessIo+Counters'
        if ([Evox2TestProcessIo]::GetProcessIoCounters($Process.Handle, [ref]$io)) {
            $Usage.ReadBytes = $io.ReadTransferCount
            $Usage.WriteBytes = $io.WriteTransferCount
        }
    } catch {}
}

function Format-Arguments([string[]]$Parts) {
    ($Parts | ForEach-Object { ConvertTo-Evox2WindowsArgument -Value $_ }) -join ' '
}

$study = foreach ($case in @(
    @{ Name='off'; Normal=$false; Interval=0 },
    @{ Name='normal'; Normal=$true; Interval=0 },
    @{ Name='detail250'; Normal=$false; Interval=250 },
    @{ Name='detail100'; Normal=$false; Interval=100 },
    @{ Name='combined250'; Normal=$true; Interval=250 },
    @{ Name='adlx250'; Normal=$false; Interval=250 }
)) {
    if ($OnlyCase.Count -gt 0 -and $case.Name -notin $OnlyCase) { continue }
    $prefix = $case.Name
    $caseDir = Join-Path $OutputRoot $prefix
    [void][IO.Directory]::CreateDirectory($caseDir)
    $stdout = Join-Path $caseDir 'stdout.log'
    $stderr = Join-Path $caseDir 'stderr.log'
    $resources = Join-Path $caseDir 'resources.csv'
    $gpuCsv = Join-Path $caseDir 'gpu-metrics.csv'
    $detail = $null
    $normal = $null
    $gpu = $null
    $child = $null
    $detailUsage = @{ CpuMs=$null; PeakWorkingSetMiB=$null; ReadBytes=$null; WriteBytes=$null }
    $normalUsage = $detailUsage.Clone()
    try {
        if ($case.Interval) {
            $settings = @{ IntervalMs=$case.Interval; PreSeconds=3; PostSeconds=5; ReadyTimeoutSeconds=10
                TimeoutSeconds=45; PeakThresholdMiB=16; RecoveryToleranceMiB=64 }
            $detail = New-Evox2RamDetail $caseDir $prefix $settings $stdout $stderr
            Start-Evox2RamDetail $detail
            Wait-Evox2RamDetailReady $detail
            if ($prefix -eq 'adlx250' -and (Test-Path -LiteralPath $adlxPath)) {
                $gpu = Start-Evox2AdlxGpuMonitor -Executable $adlxPath -OutputPath $gpuCsv -TargetProcessId $detail.Process.Id `
                    -StdOutPath (Join-Path $caseDir 'adlx.stdout.log') -StdErrPath (Join-Path $caseDir 'adlx.stderr.log')
            }
            Wait-Evox2RamBaseline $detail
            Write-Evox2RamLaunch $detail
        }
        $child = Start-Process -FilePath $exe -ArgumentList (Format-Arguments @(
                '-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',$PSCommandPath,'-PulseFixture'
            )) -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $null = $child.Handle
        if ($detail) { Connect-Evox2RamTarget $detail $child }
        if ($case.Normal) {
            $normal = Start-Process -FilePath $exe -ArgumentList (Format-Arguments @(
                    '-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $benchmark 'Monitor-LlamaProcess.ps1'),
                    '-TargetProcessId',"$($child.Id)",'-LogPath',$resources,'-RunId',$prefix
                )) -NoNewWindow -PassThru -RedirectStandardError (Join-Path $caseDir 'normal.stderr.log')
            $null = $normal.Handle
        }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (!$child.WaitForExit(200)) {
            if ($watch.Elapsed.TotalSeconds -gt 32) { throw "Fixture exceeded its time limit: $prefix" }
            if ($detail) {
                Read-Evox2RamMarkers $detail
                Measure-MonitorProcess $detail.Process $detailUsage
            }
            if ($normal) { Measure-MonitorProcess $normal $normalUsage }
        }
        if ($child.ExitCode -ne 0) { throw "Fixture exited $($child.ExitCode): $prefix" }
    } finally {
        if ($child -and !$child.HasExited) { $child.Kill(); $null = $child.WaitForExit(2000) }
        if ($detail) { Stop-Evox2RamDetail $detail $child }
        foreach ($process in $normal,$gpu) {
            if ($process -and !$process.WaitForExit(10000)) {
                $process.Kill(); $null = $process.WaitForExit(2000)
                throw "Monitor did not exit gracefully: $prefix"
            }
        }
    }
    if ($detail) { Measure-MonitorProcess $detail.Process $detailUsage }
    if ($normal) { Measure-MonitorProcess $normal $normalUsage }
    $detailResult = $null
    if ($detail) {
        $detailResult = Get-Evox2RamDetailResult $detail $gpuCsv
        $detailResult | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $caseDir 'detail-result.json') -Encoding UTF8
        if ($detailResult.Status -ne 'Complete' -or $detailResult.MarkerPhases.TokenEvalReported -ne 'ReceiptObserved') {
            throw "Detailed sampling or line receipt did not complete: $prefix"
        }
        $rows = @(Import-Csv -LiteralPath $detail.CsvPath)
        $outside = @($rows | Where-Object { $_.Phase -in 'Pre','Post' })
        if (@($outside | Where-Object { $_.WorkingSetBytes -ne '' -or $_.TargetPID -ne '' }).Count) {
            throw 'PID fields must be missing outside the process lifetime.'
        }
        $events = @(Get-Content -LiteralPath $detail.EventPath | ForEach-Object { $_ | ConvertFrom-Json })
        $markerEvents = @($events | Where-Object Event -eq 'LogMarkerReceived')
        $required = @('BackendInitialization','GgufMetadataReported','ContextInitialization','PromptEvalReported','TokenEvalReported')
        if (($markerEvents.Data.Phase -join ',') -ne ($required -join ',')) { throw 'Unexpected marker order' }
        if (($markerEvents[-1].StopwatchTicks - $markerEvents[0].StopwatchTicks) -lt 3 * [Diagnostics.Stopwatch]::Frequency) { throw 'Markers did not preserve phase timing' }
    }
    $pulses = @{}
    $quietEnd = $null
    foreach ($line in (Get-Content -LiteralPath $stdout)) {
        if ($line -match '^QUIET END (\d+)$') { $quietEnd = [long]$Matches[1] }
        if ($line -match '^PULSE (\S+) (START|END) (\d+)$') {
            if (!$pulses.ContainsKey($Matches[1])) { $pulses[$Matches[1]] = @{} }
            $pulses[$Matches[1]][$Matches[2]] = [long]$Matches[3]
        }
    }
    if ($pulses.Count -ne 7 -or !$quietEnd) { throw 'Fixture pulse markers are incomplete.' }
    $firstPulse = $quietEnd
    $samples = @{}
    if ($normal) {
        $samples['Normal'] = @(Import-Csv -LiteralPath $resources | Where-Object TargetWS_GiB | ForEach-Object {
            [pscustomobject]@{
                Tick = [long]$_.ProcessMemoryStopwatchTicks
                Utc = [datetime]::Parse($_.ProcessMemoryTimestampUtc).ToUniversalTime()
                MiB = [double]$_.TargetWS_GiB * 1024
            }
        })
    }
    if ($detail) {
        $samples['Detail'] = @($rows | Where-Object WorkingSetBytes | ForEach-Object {
            [pscustomobject]@{ Tick=[long]$_.StopwatchTicks; Utc=[datetime]::Parse($_.TimestampUtc).ToUniversalTime(); MiB=[double]$_.WorkingSetBytes / 1MB }
        })
    }
    $capture = @{}
    foreach ($kind in $samples.Keys) {
        $baseline = $samples[$kind] | Where-Object { $_.Tick -lt $firstPulse } | Select-Object -Last 1
        if (!$baseline) { throw "No PID baseline for $prefix/$kind" }
        $observed = foreach ($name in @($pulses.Keys | Sort-Object)) {
            $pulse = $pulses[$name]
            $within = @($samples[$kind] | Where-Object {
                $_.MiB -ge $baseline.MiB + 16 -and $_.Tick -ge $pulse.START -and $_.Tick -lt $pulse.END
            })
            [pscustomobject]@{
                Pulse=$name; Hits=$within.Count
                DurationMs=[math]::Round(($pulse.END - $pulse.START) * 1000.0 / [Diagnostics.Stopwatch]::Frequency,2)
            }
        }
        $capture[$kind] = @($observed)
    }
    $normalQuality = if ($normal) { Get-Evox2MonitoringQuality -Kind Resource -CsvPath $resources -Requested $true -Started $true -IntervalSeconds 2 }
    [pscustomobject]@{
        Case=$prefix; Normal=$normalUsage; Detail=$detailUsage; Capture=$capture
        NormalSamples=$(if($normalQuality){$normalQuality.SampleCount}else{$null})
        NormalInterval=$(if($normalQuality){$normalQuality.SampleIntervalSeconds}else{$null})
        DetailInterval=$(if($detailResult){$detailResult.IntervalMs}else{$null})
        DetailSamples=$(if($detailResult){$detailResult.Samples}else{$null})
        NativeMissing=$(if($detailResult){$detailResult.NativeMissing}else{$null})
        SystemRecovery=$(if($detailResult){$detailResult.SystemRecovery}else{$null})
        GpuRecovery=$(if($detailResult){$detailResult.GpuRecovery}else{$null})
        Residual=@(@($child,$normal,$gpu,$(if($detail){$detail.Process})) | Where-Object {$_ -and !$_.HasExited} | ForEach-Object Id)
    }
    Write-Host "Completed: $prefix"
}
$study | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputRoot 'study.json') -Encoding UTF8
$study | ConvertTo-Json -Depth 12 -Compress
