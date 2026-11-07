# Compare experts chosen per token in paired llama-bench stderr.log captures.
# The instrumented graph callback forces synchronizations. Do not compare PP time.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CodeStderr,
    [Parameter(Mandatory = $true)][string]$LiteratureStderr,
    [string]$OutCsv = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pattern = [regex]'evox2_moe_topk_hist_v1 ubatch=(?<ubatch>\d+) layer=(?<layer>\d+) tokens=(?<tokens>\d+) k=(?<k>\d+) experts=(?<experts>\d+) assignments=(?<assignments>\d+) active=(?<active>\d+) max=(?<max>\d+) active_tiles32=(?<tiles>\d+) bad_ids=(?<bad>\d+) counts=(?<counts>.*)$'
function Read-Hist([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing stderr.log: $Path" }
    $rows = @()
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $Path).Path)) {
        $m = $script:pattern.Match($line)
        if (-not $m.Success) { continue }
        $nExperts = [int]$m.Groups['experts'].Value
        $hist = New-Object 'long[]' $nExperts
        foreach ($entry in $m.Groups['counts'].Value.Split(',')) {
            if ([string]::IsNullOrEmpty($entry)) { continue }
            if ($entry -notmatch '^(\d+):(\d+)$') { throw "Bad expert frequency: $entry" }
            $expert = [int]$Matches[1]
            if ($expert -ge $nExperts) { throw "Bad expert id: $expert" }
            $hist[$expert] = [long]$Matches[2]
        }
        $sum = [long]0; $tiles = [long]0
        foreach ($n in $hist) { $sum += $n; $tiles += [long][math]::Ceiling($n/32.0) }
        if ($sum -ne [long]$m.Groups['assignments'].Value -or $tiles -ne [long]$m.Groups['tiles'].Value) {
            throw "Count/tile checksum failed in $Path"
        }
        $rows += [pscustomobject]@{
            UBatch = [int]$m.Groups['ubatch'].Value
            Layer = [int]$m.Groups['layer'].Value
            Tokens = [int]$m.Groups['tokens'].Value
            K = [int]$m.Groups['k'].Value
            NExperts = $nExperts
            Sum = $sum
            Active = [int]$m.Groups['active'].Value
            Tiles32 = $tiles
            BadIds = [int]$m.Groups['bad'].Value
            Counts = $hist
        }
    }
    if ($rows.Count -eq 0) { throw "No top-k histogram records: $Path" }
    return $rows
}
$code = @(Read-Hist $CodeStderr)
$lit = @(Read-Hist $LiteratureStderr)
$litMap = @{}
foreach ($l in $lit) {
    $key = "$($l.UBatch)/$($l.Layer)"
    if ($litMap.ContainsKey($key)) { throw "Duplicate literature record: $key" }
    $litMap[$key] = $l
}
$details = @(
    foreach ($c in $code) {
        $key = "$($c.UBatch)/$($c.Layer)"
        if (-not $litMap.ContainsKey($key)) { throw "No corresponding literature record: $key" }
        $l = $litMap[$key]
        if ($c.K -ne $l.K -or $c.Tokens -ne $l.Tokens -or $c.NExperts -ne $l.NExperts -or
            $c.BadIds -ne 0 -or $l.BadIds -ne 0) { throw "Shape or ID error: $key" }
        $distance = [long]0; $overlap = [long]0
        for ($i = 0; $i -lt $c.NExperts; $i++) {
            $a = $c.Counts[$i]; $b = $l.Counts[$i]
            $distance += [math]::Abs($a - $b)
            $overlap += [math]::Min($a, $b)
            [pscustomobject]@{
                UBatch = $c.UBatch; Layer = $c.Layer; Expert = $i
                CodeCount = $a; LiteratureCount = $b; CodeMinusLiterature = $a - $b
            }
        }
        Write-Host ("UBatch={0}, layer={1}, experts={2}, k={3}, assignments={4}; active(code/lit)={5}/{6}; active J32 tiles(code/lit)={7}/{8}; diff={9}; histogram L1={10}; intersection={11}" -f
             $c.UBatch, $c.Layer, $c.NExperts, $c.K, $c.Sum,
             $c.Active, $l.Active, $c.Tiles32, $l.Tiles32,
             ($c.Tiles32 - $l.Tiles32), $distance, $overlap)
    }
)
if (-not [string]::IsNullOrWhiteSpace($OutCsv)) {
    $details | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Wrote $($details.Count) rows: $OutCsv"
}
Write-Warning 'Histogram counts and predicted J32 live tile counts are routing facts, not GPU timings or proven causes of PP differences.'
