#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($rows.Count -eq 0) { throw 'Resource CSV has no rows.' }
$required = @(
    'SampleIntervalSecondsActual',
    'BackgroundIntervalSeconds',
    'BackgroundSampleTaken',
    'BackgroundSampleTimestampUtc',
    'BackgroundCollectionMilliseconds',
    'BackgroundProbeStatus'
)
foreach ($name in $required) {
    if (-not ($rows[0].PSObject.Properties.Name -contains $name)) {
        throw "Resource CSV missing expected field: $name"
    }
}

$backgroundRows = @($rows | Where-Object { $_.BackgroundSampleTaken -eq 'True' })
$nonBackgroundRows = @($rows | Where-Object { $_.BackgroundSampleTaken -ne 'True' })
foreach ($row in $nonBackgroundRows) {
    if (-not [string]::IsNullOrWhiteSpace($row.BackgroundCollectionMilliseconds)) {
        throw 'BackgroundCollectionMilliseconds was nonblank on a skipped row.'
    }
    if ($row.BackgroundProbeStatus -ne 'NotSampled') {
        throw "A skipped row must report NotSampled, got: $($row.BackgroundProbeStatus)"
    }
}

$period = [int]$rows[0].BackgroundIntervalSeconds
$previous = $null
foreach ($row in $backgroundRows) {
    if ([string]::IsNullOrWhiteSpace($row.BackgroundCollectionMilliseconds)) {
        throw 'A sampled row is missing BackgroundCollectionMilliseconds.'
    }
    $observed = [datetimeoffset]::Parse(
        $row.BackgroundSampleTimestampUtc,
        [Globalization.CultureInfo]::InvariantCulture
    )
    if ($null -ne $previous) {
        $gap = ($observed - $previous).TotalSeconds
        if ($gap -lt ($period - 0.1)) {
            throw "Background samples too close: $([math]::Round($gap, 3))s, configured $period s"
        }
    }
    $previous = $observed
}

$gaps = @($rows | ForEach-Object {
    [double]::Parse($_.SampleIntervalSecondsActual, [Globalization.CultureInfo]::InvariantCulture)
})
$maxGap = ($gaps | Measure-Object -Maximum).Maximum
$maxBackgroundCost = if ($backgroundRows.Count -gt 0) {
    $costs = @($backgroundRows | ForEach-Object {
        [double]::Parse($_.BackgroundCollectionMilliseconds, [Globalization.CultureInfo]::InvariantCulture)
    })
    ($costs | Measure-Object -Maximum).Maximum
} else {
    $null
}

[pscustomobject]@{
    Status                         = 'PASS'
    ResourceRows                   = $rows.Count
    BackgroundSampleRows           = $backgroundRows.Count
    SkippedBackgroundRows          = $nonBackgroundRows.Count
    BackgroundIntervalSeconds      = $period
    LargestResourceRowGapSeconds   = $maxGap
    LargestBackgroundProbeMs       = $maxBackgroundCost
    Note                           = 'Short runs may have zero in-run background samples; start/end snapshots are captured by the measure wrapper.'
} | Format-List
