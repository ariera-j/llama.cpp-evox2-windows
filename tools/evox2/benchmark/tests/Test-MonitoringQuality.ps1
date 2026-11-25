#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$benchDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $benchDir 'Evox2.Benchmark.psm1') -Force

function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('evox2-monitor-test-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($work)
$sleeper = $null
try {
    $exe = Join-Path $PSHOME 'powershell.exe'
    $sleeper = Start-Process -FilePath $exe -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"' -PassThru
    $state = @{ Iteration = 0; Calls = 0 }
    function Get-Counter {
        [CmdletBinding()]
        param([string[]]$Counter)

        $state.Calls++
        $combined = $Counter[-1] -like '*Utilization Percentage'
        if ($combined) { $state.Iteration++ }
        switch ($state.Iteration) {
            2 { if ($combined) { throw 'simulated PID failure' } }
            3 { throw 'simulated PerfMon denial' }
            6 {
                $sleeper.Kill()
                $sleeper.WaitForExit()
                throw 'simulated PID removal during collection'
            }
        }

        $samples = foreach ($path in $Counter) {
            if ($state.Iteration -eq 4 -and $path -like '*Disk Write*') { continue }
            $value = if ($path -like '*Bytes/sec') { 0 } else { 123.0 }
            $status = 1
            if ($path -like '*Utilization Percentage') {
                $value = if ($state.Iteration -eq 4) { 1.8e14 } else { 65 }
                if ($state.Iteration -ne 4) {
                    [pscustomobject]@{ Path = ('\\fixture' + $path.Replace('*', 'other')); CookedValue = 60; Status = 0 }
                }
            } elseif ($state.Iteration -eq 4 -and $path -like '*Page Faults*') {
                $status = 2147485656
            } elseif ($state.Iteration -eq 4 -and $path -like '*Pages Input*') {
                $value = [double]::NaN
            }
            [pscustomobject]@{ Path = ('\\fixture' + $path.Replace('*', 'fixture')); CookedValue = $value; Status = $status }
        }
        [pscustomobject]@{ CounterSamples = @($samples) }
        if ($state.Iteration -eq 4) { Write-Error 'simulated nonterminating partial read' }
    }

    $csv = Join-Path $work 'resources.csv'
    $warnings = @(& (Join-Path $benchDir 'Monitor-LlamaProcess.ps1') -TargetProcessId $sleeper.Id -LogPath $csv -IntervalSeconds 1 3>&1)
    $rows = @(Import-Csv -LiteralPath $csv)
    Assert-True ($rows.Count -eq 5 -and $state.Calls -eq 8) 'Unexpected row or fallback count'
    Assert-True ($rows[0].TargetGPUEngineSum_Percent -eq '125' -and $rows[0].DiskWrite_MiBps -eq '0') 'Valid GPU sum or real zero lost'
    Assert-True ($rows[0].PerfMonSystemStatus -eq 'Complete' -and $rows[0].PerfMonPidGpuStatus -eq 'Complete') 'Full counters not recorded'
    Assert-True ($rows[1].PerfMonSystemStatus -eq 'Complete' -and $rows[1].PerfMonPidGpuStatus -eq 'Unavailable') 'PID-only fallback lost system counters'
    Assert-True ($rows[1].TargetGPULocal_GiB -eq '' -and $rows[1].GpuProcessCountersAvailable -eq 'False') 'Missing GPU counters became zero'
    Assert-True ($rows[2].PerfMonSystemStatus -eq 'Unavailable' -and $rows[2].CPU_Percent -eq '') 'Full failure filled CPU'
    Assert-True ($rows[2].UsedRAM_GiB -ne '' -and $rows[2].Committed_GiB -ne '' -and $rows[2].TargetPrivate_GiB -ne '') 'Full failure lost independent memory'
    Assert-True ($rows[3].CPU_Percent -ne '' -and $rows[3].DiskWrite_MiBps -eq '' -and $rows[3].PagesInput_PerSec -eq '') 'Nonterminating partial failure lost or invented a sample'
    Assert-True ($rows[3].TargetGPUEngineSum_Percent -eq '' -and $rows[3].PageFaults_PerSec -eq '' -and $rows[3].PerfMonRejectedValues -eq '3') 'Invalid values counted as valid'
    Assert-True ($rows[4].PerfMonSystemStatus -eq 'Complete' -and $rows[4].PerfMonPidGpuStatus -eq 'Complete') 'Did not recover'
    Assert-True ($warnings.Count -eq 2 -and (($warnings -join ' ') -notmatch 'PID removal')) 'Repeated warning or target exit treated as a failure'
    Assert-True ($sleeper.HasExited) 'Fixture target still running'

    $quality = Get-Evox2MonitoringQuality -Kind Resource -CsvPath $csv -Requested $true -Started $true -IntervalSeconds 1
    Assert-True ($quality.Status -eq 'Partial' -and $quality.Metrics.UsedRAM_GiB.ValidCount -eq 5) 'Wrong resource quality'
    Assert-True ($quality.Metrics.DiskWrite_MiBps.ValidCount -eq 3 -and $quality.Metrics.DiskWrite_MiBps.Average -eq 0) 'Mixed zeros and missing values averaged incorrectly'
    Assert-True ($quality.SampleIntervalSeconds.ObservedCount -eq 4 -and $quality.Sources.PerfMonSystemStatus.Unavailable -eq 1) 'Wrong cadence or per-source counts'
    Assert-True ($quality.Metrics.TargetGPUEngineSum_Percent.Average -eq 125) 'Missing values affected GPU average'

    $legacyPath = Join-Path $work 'legacy.csv'
    'CPU_Percent,SampleIntervalSecondsActual', '0,0', ',2' | Set-Content -LiteralPath $legacyPath -Encoding UTF8
    $legacy = Get-Evox2MonitoringQuality -Kind Resource -CsvPath $legacyPath -Requested $true -Started $true
    Assert-True ($legacy.Status -eq 'LegacyUnqualified' -and $legacy.Metrics.CPU_Percent.ValidCount -eq 1) 'Legacy zero reinterpreted'
    Assert-True ($legacy.Metrics.TargetWS_GiB.ValidCount -eq 0 -and $null -eq $legacy.Metrics.TargetWS_GiB.Average) 'Missing metric has an average'
    $emptyPath = Join-Path $work 'no-csv'
    $empty = Get-Evox2MonitoringQuality -Kind Resource -CsvPath $emptyPath -Requested $true -Started $true
    Assert-True ($empty.Status -eq 'Unavailable' -and $empty.SampleCount -eq 0) 'No data incorrectly marked available'

    $gpuPath = Join-Path $work 'adlx.csv'
    $gpuSupport = Join-Path $work 'adlx.stdout.log'
    @('elapsed_ms,adlx_result,gpu_usage_pct,gpu_power_w,gpu_temp_c,gpu_hotspot_c',
      '0,0,0,20,-2,', '2000,0,0,,5,', '4000,3,99,200,15,', '6000,,80,100,10,') |
        Set-Content -LiteralPath $gpuPath -Encoding UTF8
    '  hotspot=0 result=0' | Set-Content -LiteralPath $gpuSupport -Encoding UTF8
    $adlx = Get-Evox2MonitoringQuality -Kind ADLX -CsvPath $gpuPath -Requested $true -Started $true -StdOutPath $gpuSupport
    Assert-True ($adlx.Status -eq 'Partial' -and $adlx.Metrics.gpu_usage_pct.ValidCount -eq 2 -and $adlx.Metrics.gpu_power_w.Average -eq 20) 'ADLX result code/filter handling failed'
    Assert-True ($adlx.Metrics.gpu_temp_c.Minimum -eq -2 -and $adlx.AdlxZeroOnlyMetrics -contains 'gpu_usage_pct' -and !$adlx.AdlxSupport.gpu_hotspot_c.Supported) 'Absent support or reported constant zero misclassified'
    $serialized = $adlx | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    Assert-True ($null -eq $serialized.Metrics.gpu_hotspot_c.Average -and $serialized.Metrics.gpu_usage_pct.Average -eq 0) 'Null/zero did not survive JSON'
    Write-Output 'PASS monitor fallback, invalid samples, recovery and exit race; quality, legacy CSV and ADLX'
} finally {
    if ($sleeper -and !$sleeper.HasExited) { $sleeper.Kill(); $sleeper.WaitForExit() }
    Remove-Item -LiteralPath $work -Recurse
}
