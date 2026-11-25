#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$benchmark = Split-Path -Parent $PSScriptRoot
$common = Join-Path (Split-Path -Parent $benchmark) 'lib\Evox2.Common.psm1'
Import-Module (Join-Path $benchmark 'Evox2.Benchmark.psm1') -Force

function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('evox2-matrix-quality-' + [guid]::NewGuid())
$fixtureTools = Join-Path $fixture 'tools\evox2'
$fixtureBench = Join-Path $fixtureTools 'benchmark'
$fixtureLib = Join-Path $fixtureTools 'lib'
[void][IO.Directory]::CreateDirectory($fixtureBench)
[void][IO.Directory]::CreateDirectory($fixtureLib)
[void][IO.Directory]::CreateDirectory((Join-Path $fixture '.git'))
try {
    $encoding = [Text.UTF8Encoding]::new($true)
    Copy-Item -LiteralPath $common -Destination $fixtureLib
    Copy-Item -LiteralPath (Join-Path $benchmark 'Evox2.Benchmark.psm1'),(Join-Path $benchmark 'Invoke-BenchmarkMatrix.ps1') -Destination $fixtureBench

    $ResourcePath = Join-Path $fixture 'resources.csv'
    $GpuMetricsPath = Join-Path $fixture 'gpu-metrics.csv'
    'ResourceSchemaVersion,UsedRAM_GiB,CPU_Percent,PerfMonSystemStatus', '2,4,,Unavailable', '2,5,0,Partial' |
        Set-Content -LiteralPath $ResourcePath -Encoding UTF8
    'elapsed_ms,adlx_result,gpu_usage_pct', '0,3,' | Set-Content -LiteralPath $GpuMetricsPath -Encoding UTF8
    $ResourceMonitor = $true
    $monitorProcess = [pscustomobject]@{}
    $monitorExitCode = 0
    $monitorError = $null
    $MonitorStdOutPath = $MonitorStdErrPath = Join-Path $fixture 'absent'
    $AdlxStdOutPath = $AdlxStdErrPath = $MonitorStdOutPath
    $ResourceIntervalSeconds = 2
    $AdlxIntervalMs = 2000
    $AdlxMonitorRequested = $adlxMonitorStarted = $true
    $adlxMonitorExitCode = 0
    $adlxMonitorStartError = $null

    foreach ($name in 'Measure-LlamaBench.ps1', 'Measure-LlamaCli.ps1') {
        $path = Join-Path $benchmark $name
        $tokens = $null; $problems = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$problems)
        Assert-True ($problems.Count -eq 0) "Invalid AST: $name"
        # Execute the actual wrapper's post-run assignments and JSON record
        # against synthetic monitor output. Do not invoke a native workload.
        foreach ($variable in 'ResourceQuality', 'AdlxQuality', 'resourceSampleCount', 'adlxSampleCount') {
            $assignment = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq ('$' + $variable)
            }, $false)
            Assert-True ($null -ne $assignment) "Missing wrapper assignment: $variable in $name"
            . ([scriptblock]::Create($assignment.Extent.Text))
        }
        $tables = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.HashtableAst] -and
                $node.KeyValuePairs.Item1.Value -contains 'MonitoringQuality'
        }, $true))
        Assert-True ($tables.Count -eq 1) "Missing JSON record in $name"
        $record = $tables[0].KeyValuePairs | Where-Object { $_.Item1.Value -eq 'MonitoringQuality' }
        $details = & ([scriptblock]::Create($record.Item2.Extent.Text)) | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        Assert-True ($details.Resource.Status -eq 'Partial' -and $details.ADLX.Status -eq 'Unavailable') "Wrong wrapper quality in $name"
        Assert-True ($details.Resource.Metrics.CPU_Percent.ValidCount -eq 1 -and $details.Resource.Metrics.CPU_Percent.Average -eq 0 -and $null -eq $details.ADLX.Metrics.gpu_usage_pct.Average) 'JSON did not preserve missing values and observed zero'

        $tables = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.HashtableAst] -and
                $node.KeyValuePairs.Item1.Value -contains 'ResourceMonitorStatus'
        }, $true))
        Assert-True ($tables.Count -eq $(if ($name -like '*Bench*') { 2 } else { 1 })) "Missing summary fields in $name"
        # Use the actual parameter contract plus a synthetic successful
        # child row, fed by fields evaluated from the real summary mapping.
        $row = [ordered]@{ Status = 'OK'; RunId = 'fixture'; RunDirectory = 'fixture' }
        foreach ($pair in $tables[0].KeyValuePairs) {
            if ($pair.Item1.Value -in 'ResourceMonitorStatus', 'AdlxMonitorStatus', 'ResourceSamples', 'AdlxSamples') {
                $row[$pair.Item1.Value] = & ([scriptblock]::Create($pair.Item2.Extent.Text))
            }
        }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($row | ConvertTo-Json -Compress)))
        $body = "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json"
        [IO.File]::WriteAllText((Join-Path $fixtureBench $name), ($ast.ParamBlock.Extent.Text + [Environment]::NewLine + $body), $encoding)
    }
    $local = Join-Path $fixture 'local.psd1'
    $plan = Join-Path $fixture 'plan.psd1'
    [IO.File]::WriteAllText($local, "@{ LogRoot = '$fixture'; Builds = @{ B = @{} }; Models = @{ M = @{} } }", $encoding)
    [IO.File]::WriteAllText($plan, @'
@{
    SchemaVersion = 1
    Jobs = @(
        @{ Name = 'bench'; Tool = 'bench'; BuildKeys = @('B'); ModelKeys = @('M') },
        @{ Name = 'cli'; Tool = 'cli'; BuildKeys = @('B'); ModelKeys = @('M'); Parameters = @{ AllocationOnly = $true } }
    )
}
'@, $encoding)
    & (Join-Path $fixtureBench 'Invoke-BenchmarkMatrix.ps1') -Plan $plan -LocalConfig $local -MaxRuns 2 -CooldownSeconds 0 -ResourceMonitor
    $batch = Get-ChildItem -LiteralPath (Join-Path $fixture 'matrix') -Directory | Select-Object -First 1
    $runs = @(Import-Csv -LiteralPath (Join-Path $batch.FullName 'matrix-runs.csv'))
    $results = @(Import-Csv -LiteralPath (Join-Path $batch.FullName 'matrix-results.csv'))
    $json = Get-Content -LiteralPath (Join-Path $batch.FullName 'matrix-result.json') -Raw | ConvertFrom-Json
    Assert-True ($runs.Count -eq 2 -and $results.Count -eq 2 -and $json.StatusCounts.OK -eq 2) 'Quality affected workload success'
    foreach ($item in @($runs) + @($results) + @($json.Runs) + @($json.Results)) {
        Assert-True ($item.ResourceMonitorStatus -eq 'Partial' -and $item.AdlxMonitorStatus -eq 'Unavailable' -and $item.ResourceSamples -eq 2 -and $item.AdlxSamples -eq 1) 'Missing Matrix quality rollup'
    }
    Write-Output 'PASS Measure quality assignments, JSON and CSV fields; Matrix quality rollup and status independence'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse
}
