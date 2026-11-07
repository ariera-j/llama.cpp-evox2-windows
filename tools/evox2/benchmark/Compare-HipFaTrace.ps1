# PowerShell 5.1 and 7: compare host-side FA metadata records.
# This is NOT GPU timing and CANNOT map fa_id to an RGP Event ID.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CodeStderr,
    [Parameter(Mandatory = $true)][string]$LiteratureStderr,
    [string]$OutCsv = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# All fields before the human-readable Q tensor name are machine-parsable.
$re = [regex]'evox2_hip_fa_trace_v1 fa_id=(?<faid>\d+) matched=(?<match>\d+) host_us=(?<host>\d+) device=(?<device>\d+) KV=(?<kv>\d+) N=(?<n>\d+) layer=(?<layer>-?\d+) kernel=(?<kernel>\S+) suffix_scan_candidate=(?<scan>[01]) kv_max_hint=(?<hint>\d+) q_heads=(?<qheads>\d+) k_heads=(?<kheads>\d+) seq=(?<seq>\d+) q_name="(?<qname>[^"]*)"'

function Get-TraceRows([string]$Path, [string]$Corpus) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "stderr.log does not exist: $Path"
    }

    $count = 0
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $Path).Path)) {
        $m = $script:re.Match($line)
        if (-not $m.Success) {
            continue
        }
        $count++
        [pscustomobject]@{
            Corpus     = $Corpus
            FaId       = [long]$m.Groups['faid'].Value
            Matched    = [long]$m.Groups['match'].Value
            HostUs     = [long]$m.Groups['host'].Value
            KV         = [long]$m.Groups['kv'].Value
            N          = [long]$m.Groups['n'].Value
            Layer      = [long]$m.Groups['layer'].Value
            Kernel     = $m.Groups['kernel'].Value
            SuffixScan = [int]$m.Groups['scan'].Value
            KvMaxHint  = [long]$m.Groups['hint'].Value
            QHeads     = [long]$m.Groups['qheads'].Value
            KHeads     = [long]$m.Groups['kheads'].Value
            Sequence   = [long]$m.Groups['seq'].Value
            QName      = $m.Groups['qname'].Value
        }
    }
    if ($count -eq 0) {
        throw "No hip FA trace rows in $Corpus stderr.log. Check binary, GGML_HIP_FA_TRACE, KV filter."
    }
}

$code = @(Get-TraceRows -Path $CodeStderr -Corpus 'code' | Sort-Object FaId)
$lit  = @(Get-TraceRows -Path $LiteratureStderr -Corpus 'literature' | Sort-Object FaId)

# One row per (KV, N, layer) is expected in the nominal 49152/1024 snapshot,
# but keep an occurrence index rather than silently overwriting duplicates.
function Index-ByIdentity([object[]]$Rows) {
    $seen = @{}
    foreach ($r in $Rows) {
        $key = "$($r.KV)/$($r.N)/$($r.Layer)"
        if (-not $seen.ContainsKey($key)) { $seen[$key] = 0 }
        $seen[$key]++
        Add-Member -InputObject $r -NotePropertyName Occurrence -NotePropertyValue $seen[$key]
        Add-Member -InputObject $r -NotePropertyName Identity -NotePropertyValue "$key/$($r.Occurrence)"
    }
    return $Rows
}

$code = @(Index-ByIdentity -Rows $code)
$lit  = @(Index-ByIdentity -Rows $lit)

$litByIdentity = @{}
foreach ($r in $lit) { $litByIdentity[$r.Identity] = $r }

$results = @(
    foreach ($c in $code) {
        $l = if ($litByIdentity.ContainsKey($c.Identity)) { $litByIdentity[$c.Identity] } else { $null }
        [pscustomobject]@{
            KV                 = $c.KV
            N                  = $c.N
            Layer              = $c.Layer
            Occurrence         = $c.Occurrence
            CodeFaId           = $c.FaId
            LiteratureFaId     = if ($null -ne $l) { $l.FaId } else { $null }
            CodeKernel         = $c.Kernel
            LiteratureKernel   = if ($null -ne $l) { $l.Kernel } else { '' }
            SameKernel         = $null -ne $l -and $c.Kernel -eq $l.Kernel
            CodeSuffixScan     = $c.SuffixScan
            LiteratureSuffixScan = if ($null -ne $l) { $l.SuffixScan } else { $null }
            CodeKvMaxHint      = $c.KvMaxHint
            LiteratureKvMaxHint = if ($null -ne $l) { $l.KvMaxHint } else { $null }
            CodeHostUs         = $c.HostUs
            LiteratureHostUs   = if ($null -ne $l) { $l.HostUs } else { $null }
            QNamesMatchLayer   = $c.Layer -ge 0 -and $null -ne $l -and $l.Layer -eq $c.Layer
            RgpEventMatched    = $false
        }
    }
)

Write-Host "Code FA records: $($code.Count); literature records: $($lit.Count); identity pairs: $( @($results | Where-Object { $null -ne $_.LiteratureFaId }).Count )"
$results | Format-Table KV, N, Layer, CodeFaId, LiteratureFaId, SameKernel, CodeSuffixScan, LiteratureSuffixScan -AutoSize

if (-not [string]::IsNullOrWhiteSpace($OutCsv)) {
    $results | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "CSV written: $OutCsv"
}
Write-Warning 'HostUs/FaId are not GPU durations or HIP RGP dispatch indices. Do NOT use them to prove exact RGP KV/layer mapping.'
