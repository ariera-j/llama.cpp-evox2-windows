#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Evox2.MatrixComparison.psm1') -Force
function Assert-True($condition, [string]$message) { if (!$condition) { throw $message } }
function Sequence([string]$mode, [string[]]$names) {
    $config = @{ Group='test'; Base='A'; Runs=3; Order=$mode }
    @(Get-Evox2MatrixRoundSchedule $config $names 'test' | ForEach-Object { $_.Order -join '' }) -join ','
}
Assert-True ((Sequence 'ABAB' @('A','B')) -eq 'AB,AB,AB') 'ABAB'
Assert-True ((Sequence 'ABBA' @('A','B')) -eq 'AB,BA,AB') 'ABBA'
Assert-True ((Sequence 'Rotate' @('A','B','C')) -eq 'ABC,BCA,CAB') 'Rotate'
$bad = $false
try {
    $null = Get-Evox2MatrixRoundSchedule @{Group='x';Base='A';Runs=1;Order='Explicit';Rounds=@(@{Order=@('A','A')})} @('A','B') 'x'
} catch { $bad = $true }
Assert-True $bad 'Explicit duplicate must be rejected'

$plans = @()
$records = @()
$measurements = @()
foreach ($round in 1..3) {
    foreach ($name in 'A','B') {
        if ($round -eq 3 -and $name -eq 'A') { continue }
        $id = "$round$name"
        $plans += [pscustomobject]@{ MatrixRunId=$id; Job='j'; Case='c'; ModelKey='m'; Round=$round; Configuration=$name; BaseConfiguration='A'; ComparisonGroup='x' }
        $success = !($round -eq 2 -and $name -eq 'A')
        $records += [pscustomobject]@{ MatrixRunId=$id; MatrixStatus=$(if($success){'OK'}else{'EXCEPTION'}) }
        if (!$success) { continue }
        $value = if ($name -eq 'A') { 100 } else { 105 }
        $measurements += [pscustomobject]@{ MatrixRunId=$id; Tool='bench'; BenchTest='pp 8192'; PromptTokens=8192; GenerationTokens=0; AvgTokensPerSec=$value }
        $measurements += [pscustomobject]@{ MatrixRunId=$id; Tool='bench'; BenchTest='tg 256'; PromptTokens=0; GenerationTokens=256; AvgTokensPerSec=$null }
    }
}
$result = Get-Evox2MatrixComparison $plans $records $measurements
$r1 = $result.Rounds | Where-Object { $_.Round -eq 1 -and $_.Configuration -eq 'B' -and $_.Metric -eq 'PP' }
Assert-True ($r1.Status -eq 'Comparable' -and [math]::Abs($r1.DeltaPct - 5) -lt 0.00001) 'Expected 5% paired PP'
Assert-True (@($result.Rounds | Where-Object { $_.Status -in 'ReferenceFailed','ReferenceFiltered' -and $null -eq $_.DeltaPct }).Count -eq 2) 'Missing reference imputed'
$tg = $result.Summary | Where-Object { $_.Metric -eq 'TG' -and $_.Configuration -eq 'B' }
Assert-True ($tg.Valid -eq 0 -and $tg.Missing -eq 3 -and $null -eq $tg.Median) 'Missing metric fabricated'

# CLI outputs of different lengths must stay in separate workload strata.
$cli = @(
    [pscustomobject]@{ MatrixRunId='1A';Tool='cli';PromptTokens=50;GenerationTokens=20;PP=200;TG=40 },
    [pscustomobject]@{ MatrixRunId='1B';Tool='cli';PromptTokens=50;GenerationTokens=21;PP=200;TG=41 }
)
$r = Get-Evox2MatrixComparison @($plans | Where-Object Round -eq 1) $records $cli
Assert-True (@($r.Rounds | Where-Object Status -eq 'Comparable').Count -eq 0) 'Unequal generated lengths were paired'
'PASS ABAB, ABBA, rotation, explicit duplicate, paired PP/TG, failed and missing references, CLI token mismatch'
