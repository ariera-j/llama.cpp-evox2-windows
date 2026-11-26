#requires -Version 5.1

function Get-Evox2MatrixRoundSchedule {
    param([hashtable]$Comparison, [string[]]$Configurations, [string]$Job)

    if ($Configurations.Count -lt 2 -or @($Configurations | Select-Object -Unique).Count -ne $Configurations.Count) {
        throw "Comparison in '$Job' needs at least two uniquely named configurations."
    }
    if ([string]::IsNullOrWhiteSpace($Comparison.Group) -or $Comparison.Base -notin $Configurations) {
        throw "Comparison in '$Job' requires Group and a known Base."
    }
    foreach ($reference in @($Comparison.References | Where-Object { $_ })) {
        if ($reference -notin $Configurations) { throw "Unknown reference '$reference' in '$Job'." }
    }
    $count = if ($Comparison.ContainsKey('Runs')) { [int]$Comparison.Runs } else { 1 }
    if ($count -lt 1 -or $count -gt 1000) { throw "Comparison.Runs must be between 1 and 1000 in '$Job'." }
    $mode = if ($Comparison.Order) { [string]$Comparison.Order } else { 'Rotate' }
    if ($mode -notin 'ABAB','ABBA','Rotate','Explicit') { throw "Unknown comparison order '$mode'." }
    if ($mode -in 'ABAB','ABBA' -and $Configurations.Count -ne 2) { throw "$mode requires two configurations." }
    if ($mode -eq 'Explicit' -and @($Comparison.Rounds).Count -ne $count) {
        throw "Comparison.Rounds must have one order per independent run in '$Job'."
    }
    $baseFirst = @($Comparison.Base) + @($Configurations | Where-Object { $_ -ne $Comparison.Base })
    for ($index = 0; $index -lt $count; $index++) {
        $order = switch ($mode) {
            'Explicit' {
                $round = $Comparison.Rounds[$index]
                if ($round -isnot [hashtable]) { throw 'Each Comparison.Rounds item requires an Order array.' }
                $round.Order
            }
            'ABBA' {
                if ($index % 2 -eq 0) { $baseFirst } else { $baseFirst[1], $baseFirst[0] }
            }
            'ABAB' { $baseFirst }
            'Rotate' {
                for ($position = 0; $position -lt $baseFirst.Count; $position++) {
                    $baseFirst[($index + $position) % $baseFirst.Count]
                }
            }
        }
        $order = @($order)
        if ($order.Count -ne $Configurations.Count -or
            @($order | Select-Object -Unique).Count -ne $Configurations.Count -or
            @($order | Where-Object { $_ -notin $Configurations }).Count -gt 0) {
            throw "Comparison round $($index + 1) in '$Job' must list each configuration once."
        }
        [pscustomobject]@{ Round = $index + 1; Order = $order }
    }
}

function Get-MatrixNumericValue {
    param($Value)
    [double]$number = 0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -and
        ![double]::IsNaN($number) -and ![double]::IsInfinity($number) -and $number -gt 0) { $number }
}

function Get-MatrixMeasurements {
    param($Row)
    if ($Row.Tool -eq 'bench') {
        if (!$Row.BenchTest -or $Row.BenchTest -eq 'unknown') { return }
        $metric = if ([int]$Row.PromptTokens -eq 0) { 'TG' }
            elseif ([int]$Row.GenerationTokens -eq 0) { 'PP' } else { 'PG' }
        $entries = @{ $metric = $Row.AvgTokensPerSec }
    } else {
        $entries = [ordered]@{ PP = $Row.PP; TG = $Row.TG }
    }
    $shape = [ordered]@{
        Prompt = $Row.PromptTokens; Generation = $Row.GenerationTokens; Depth = $Row.Depth
        Context = $Row.Context; ActualContext = $Row.ActualContext; InputSha256 = $Row.InputSha256
        InputFile = $Row.InputFile; PromptSlice = $Row.PromptSlice; Mtp = $Row.MTP
        Test = $Row.BenchTest; Repetitions = $Row.RepetitionSamples
    }
    foreach ($metric in $entries.Keys) {
        $usableShape = ($null -ne $shape.Prompt -and $null -ne $shape.Generation)
        $value = Get-MatrixNumericValue $entries[$metric]
        [pscustomobject]@{
            Metric = $metric; Shape = ($shape | ConvertTo-Json -Compress)
            Value = $(if ($usableShape) { $value } else { $null })
            NativeSeconds = $(if ($Row.Tool -eq 'bench') { $Row.NativeSeconds } elseif ($metric -eq 'PP') { $Row.PromptSeconds } else { $Row.GenerationSeconds })
            PMode = $Row.PModeStart; PModeChanged = $Row.PModeChanged
        }
    }
}

function Get-MatrixObservation {
    param($Run, $Record, [object[]]$Measurements, [string]$Metric, [string]$Shape)
    $matching = @($Measurements | Where-Object { $_.Metric -eq $Metric -and $_.Shape -ceq $Shape })
    $status = if (!$Run) { 'Filtered' }
        elseif (!$Record) { 'NotRun' }
        elseif ($Record.MatrixStatus -ne 'OK') { 'Failed' }
        elseif ($matching.Count -gt 1) { 'AmbiguousWorkload' }
        elseif ($matching.Count -eq 1 -and $matching[0].PModeChanged -eq $true) { 'PModeChanged' }
        elseif ($matching.Count -eq 1 -and $null -ne $matching[0].Value) { 'Valid' }
        elseif (@($Measurements | Where-Object Metric -eq $Metric).Count -gt 0 -and $matching.Count -eq 0) { 'WorkloadMismatch' }
        else { 'Missing' }
    [pscustomobject]@{
        Status = $status
        Value = $(if ($status -eq 'Valid') { $matching[0].Value } else { $null })
        PMode = $(if ($matching.Count -eq 1) { $matching[0].PMode } else { $null })
        NativeSeconds = $(if ($matching.Count -eq 1) { $matching[0].NativeSeconds } else { $null })
    }
}

function Get-Evox2MatrixComparison {
    param([object[]]$Planned, [object[]]$RunRecords, [object[]]$ResultRows)

    $plannedComparison = @($Planned | Where-Object ComparisonGroup)
    $recordIndex = @{}
    foreach ($record in $RunRecords) { $recordIndex[$record.MatrixRunId] = $record }
    $measurements = @{}
    foreach ($row in $ResultRows) { $measurements[$row.MatrixRunId] = @($measurements[$row.MatrixRunId]) + @(Get-MatrixMeasurements $row) }
    $perRound = [Collections.Generic.List[object]]::new()
    $summary = [Collections.Generic.List[object]]::new()
    foreach ($group in ($plannedComparison | Group-Object Job, Case, ModelKey)) {
        $plans = @($group.Group)
        $exemplar = $plans[0]
        $configurations = @($plans.Configuration | Select-Object -Unique)
        $references = @($exemplar.BaseConfiguration) + @($exemplar.References | Where-Object { $_ })
        $references = @($references | Select-Object -Unique)
        $index = @{}
        foreach ($run in $plans) { $index["$($run.Round)|$($run.Configuration)"] = $run }
        $series = @(foreach ($run in $plans) { $measurements[$run.MatrixRunId] }) |
            Where-Object { $_ } | Select-Object Metric, Shape -Unique
        foreach ($item in $series) {
            foreach ($configuration in $configurations) {
                $observations = [Collections.Generic.List[object]]::new()
                foreach ($round in ($plans.Round | Sort-Object -Unique)) {
                    $run = $index["$round|$configuration"]
                    $record = if ($run) { $recordIndex[$run.MatrixRunId] }
                    $samples = if ($run) { $measurements[$run.MatrixRunId] }
                    $observed = Get-MatrixObservation $run $record $samples $item.Metric $item.Shape
                    $observations.Add($observed)
                    foreach ($reference in $references) {
                        $refRun = $index["$round|$reference"]
                        $refRecord = if ($refRun) { $recordIndex[$refRun.MatrixRunId] }
                        $refSamples = if ($refRun) { $measurements[$refRun.MatrixRunId] }
                        $baseline = Get-MatrixObservation $refRun $refRecord $refSamples $item.Metric $item.Shape
                        $pairStatus = if ($configuration -eq $reference) { 'Reference' }
                            elseif ($observed.Status -ne 'Valid') { $observed.Status }
                            elseif ($baseline.Status -ne 'Valid') { "Reference$($baseline.Status)" }
                            elseif ($observed.PMode -and $baseline.PMode -and $observed.PMode -ne $baseline.PMode) { 'PModeMismatch' }
                            else { 'Comparable' }
                        $perRound.Add([pscustomobject][ordered]@{
                            Group=$exemplar.ComparisonGroup; Job=$exemplar.Job; Case=$exemplar.Case; ModelKey=$exemplar.ModelKey
                            Round=$round; Configuration=$configuration; Reference=$reference; Base=$exemplar.BaseConfiguration
                            Metric=$item.Metric; Workload=$item.Shape; RunId=$record.MatrixRunId; ReferenceRunId=$refRecord.MatrixRunId
                            Value=$observed.Value; ReferenceValue=$baseline.Value; Status=$pairStatus
                            DeltaPct=$(if ($pairStatus -eq 'Comparable') { 100.0 * ($observed.Value / $baseline.Value - 1) } else { $null })
                            NativeSeconds=$observed.NativeSeconds; ResourceStatus=$record.ResourceMonitorStatus
                            AdlxStatus=$record.AdlxMonitorStatus; RamDetailStatus=$record.RamDetailStatus
                            RamIncreaseMiB=$record.RamDetailIncreaseMiB; MemoryRecovery=$record.RamDetailSystemRecovery
                            ProcessSeconds=$record.ProcessSeconds; WrapperSeconds=$record.WrapperSeconds
                            ModelLoadReportedSeconds=$record.ModelLoadReportedSeconds; ContextMarkerFromLaunchSeconds=$record.ContextMarkerFromLaunchSeconds
                        })
                    }
                }
                $valid = @($observations | Where-Object Status -eq 'Valid' | ForEach-Object Value | Sort-Object)
                $median = $null; $min = $null; $max = $null; $average = $null
                if ($valid.Count) {
                    $mid = [int][math]::Floor($valid.Count / 2)
                    $median = if ($valid.Count % 2) { $valid[$mid] } else { ($valid[$mid - 1] + $valid[$mid]) / 2 }
                    $average = ($valid | Measure-Object -Average).Average
                    $min = $valid[0]; $max = $valid[-1]
                }
                $failed = @($observations | Where-Object Status -eq 'Failed').Count
                $summary.Add([pscustomobject][ordered]@{
                    Group=$exemplar.ComparisonGroup; Job=$exemplar.Job; Case=$exemplar.Case; ModelKey=$exemplar.ModelKey
                    Configuration=$configuration; Metric=$item.Metric; Workload=$item.Shape; Valid=$valid.Count; Failed=$failed
                    Missing=$observations.Count - $valid.Count - $failed; Average=$average; Median=$median; Minimum=$min; Maximum=$max
                })
            }
        }
    }
    [pscustomobject]@{ Rounds=$perRound.ToArray(); Summary=$summary.ToArray() }
}

Export-ModuleMember -Function 'Get-Evox2MatrixRoundSchedule','Get-Evox2MatrixComparison'
