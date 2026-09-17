#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$LlamaCli,
    [Parameter(Mandatory = $true)][string]$ModelFile,
    [Parameter(Mandatory = $true)][string]$InputFile,
    [ValidateSet('Unsloth', 'Agention')][string]$ModelKind = 'Unsloth',
    [ValidateSet('ABBA', 'OFF', 'ON', 'ThresholdABBA')][string]$Sequence = 'ABBA',
    [ValidateSet(65536, 131072, 262144)][int]$Context = 65536,
    [string]$LogDirectory = (Join-Path (Get-Location).Path 'evox2-r2-bench'),
    [ValidateRange(1, 262144)][int]$MinKv = 32768,
    [ValidateRange(1, 262144)][int]$CompareMinKv = 16384
)

$ErrorActionPreference = 'Stop'
if ($Sequence -eq 'ThresholdABBA' -and $MinKv -eq $CompareMinKv) {
    throw 'ThresholdABBA requires different -MinKv and -CompareMinKv values.'
}
$LlamaCli = (Resolve-Path -LiteralPath $LlamaCli).Path
$ModelFile = (Resolve-Path -LiteralPath $ModelFile).Path
$InputFile = (Resolve-Path -LiteralPath $InputFile).Path
$LogDirectory = [IO.Path]::GetFullPath((Join-Path $LogDirectory (Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$Names = @('GGML_VK_QSA_UNION', 'GGML_VK_QSA_UNION_MIN_KV', 'GGML_VK_QSA_UNION_STATS',
    'GGML_VK_QSA_GATHER_GROUPS', 'GGML_VK_PERF_LOGGER', 'GGML_VK_PERF_LOGGER_FREQUENCY',
    'GGML_VK_FUSE_UNARY_MUL')
$Saved = @{}
foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process') }
$Modes = @(switch ($Sequence) {
    'ABBA' { '0', '1', '1', '0' }
    'OFF' { '0' }
    'ON' { '1' }
    'ThresholdABBA' { '1', '1', '1', '1' }
})
$RunMinKv = if ($Sequence -eq 'ThresholdABBA') {
    @($MinKv, $CompareMinKv, $CompareMinKv, $MinKv)
} else {
    @($MinKv) * $Modes.Count
}
$Metadata = [ordered]@{
    Candidate = 'evox2-r2'; BaseCommit = 'ee245db63d4bd08f590aa5a4d756c5913e56ffdd'
    MeasurementScriptVersion = '20260917-r2-stable'
    LlamaCli = $LlamaCli; CliSha256 = (Get-FileHash -LiteralPath $LlamaCli -Algorithm SHA256).Hash
    ModelFile = $ModelFile; ModelBytes = (Get-Item -LiteralPath $ModelFile).Length
    InputFile = $InputFile; InputSha256 = (Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash
    Sequence = $Sequence; Context = $Context; Kv = 'f16'; UBatch = 1024; MTP = $false
    RunUnionModes = $Modes; RunMinKv = @($RunMinKv)
}
$GpuDll = Join-Path (Split-Path -Parent $LlamaCli) 'ggml-vulkan.dll'
if (Test-Path -LiteralPath $GpuDll) { $Metadata.VulkanDllSha256 = (Get-FileHash -LiteralPath $GpuDll -Algorithm SHA256).Hash }
$Metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LogDirectory 'conditions.json') -Encoding UTF8
try {
    foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $null, 'Process') }
    $Run = 0
    foreach ($Mode in $Modes) {
        ++$Run
        $CurrentMinKv = $RunMinKv[$Run - 1]
        [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION', $Mode, 'Process')
        [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION_MIN_KV', "$CurrentMinKv", 'Process')
        [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION_STATS', '1', 'Process')
        $Label = if ($Mode -eq '1') { 'ON' } else { 'OFF' }
        $FolderLabel = if ($Sequence -eq 'ThresholdABBA' -or $MinKv -ne 32768) { "$Label-kv$CurrentMinKv" } else { $Label }
        $RunDirectory = Join-Path $LogDirectory ("{0:D2}-{1}" -f $Run, $FolderLabel)
        Write-Host "Run $Run / $($Modes.Count): union $Label, min_kv=$CurrentMinKv"
        & (Join-Path $PSScriptRoot 'Measure-Qwen38-Ple16.ps1') -LlamaCli $LlamaCli -ModelFile $ModelFile `
            -InputFile $InputFile -ModelKind $ModelKind -Context $Context -KvType f16 -UBatch 1024 `
            -UmaVramLabel 96GB -LogDir $RunDirectory
        $Csv = Get-ChildItem -LiteralPath $RunDirectory -Filter '*.csv' | Select-Object -First 1
        if (-not $Csv) { throw "No result CSV in $RunDirectory" }
        $Result = Import-Csv -LiteralPath $Csv.FullName
        $Log = Get-Content -LiteralPath $Result.LogFile -Raw
        $Active = $Log -match 'qsa-union active'
        $ThresholdMatch = [regex]::Match($Log, 'qsa-union active[^\r\n]*\bmin_kv=(\d+)\b')
        $LoggedMinKv = if ($ThresholdMatch.Success) { [int]$ThresholdMatch.Groups[1].Value } else { $null }
        $Result | Add-Member -NotePropertyName UnionRequested -NotePropertyValue $Label
        $Result | Add-Member -NotePropertyName UnionActive -NotePropertyValue $Active
        $Result | Add-Member -NotePropertyName UnionMinKvRequested -NotePropertyValue $CurrentMinKv
        $Result | Add-Member -NotePropertyName UnionMinKvLogged -NotePropertyValue $LoggedMinKv
        if ($Mode -eq '1' -and -not $Active) { throw 'ON finished without using the new path. Send the logs before continuing.' }
        if ($Mode -eq '1' -and $LoggedMinKv -ne $CurrentMinKv) {
            throw "Requested min_kv=$CurrentMinKv, but the active path logged '$LoggedMinKv'. Send the logs before continuing."
        }
        if ($Mode -eq '0' -and $Active) { throw 'OFF unexpectedly used the new path. Send the logs before continuing.' }
        $Result | Export-Csv -LiteralPath (Join-Path $LogDirectory 'comparison.csv') -NoTypeInformation -Encoding UTF8 -Append
    }
} finally {
    foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], 'Process') }
}
Write-Host "Comparison complete: $LogDirectory"
