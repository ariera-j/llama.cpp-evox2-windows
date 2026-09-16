#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LlamaRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$InputModel,
    [string]$OutputModel = '',
    [string]$Python = '',
    [switch]$VerifyBytes
)

$ErrorActionPreference = 'Stop'
if (-not $Python) { $Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe' }
if (-not $OutputModel) {
    $OutputModel = Join-Path (Split-Path -Parent $InputModel) 'Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf'
}
$Converter = Join-Path $LlamaRoot 'gguf-py\gguf\scripts\gguf_split_ple_heads.py'
$Verifier = Join-Path $PSScriptRoot 'verify-ple16.py'
foreach ($FilePath in @($InputModel, $Converter, $Verifier)) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "File not found: $FilePath" }
}
$null = Get-Command -Name $Python -CommandType Application -ErrorAction Stop
$InputModel = (Resolve-Path -LiteralPath $InputModel).Path
$LlamaRoot = (Resolve-Path -LiteralPath $LlamaRoot).Path
$OutputModel = [System.IO.Path]::GetFullPath($OutputModel)
$PartialOutput = $OutputModel + '.partial.gguf'
foreach ($FilePath in @($OutputModel, $PartialOutput)) {
    if (Test-Path -LiteralPath $FilePath) { throw "Output already exists: $FilePath" }
}
$OutputDirectory = Split-Path -Parent $OutputModel
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw "Output directory not found: $OutputDirectory" }

$ShardFiles = @($InputModel)
$ShardMatch = [regex]::Match([System.IO.Path]::GetFileName($InputModel), '^(.*)-(\d{5})-of-(\d{5})\.gguf$')
if ($ShardMatch.Success) {
    if ([int]$ShardMatch.Groups[2].Value -ne 1) { throw 'Pass the first shard (00001).' }
    $ShardFiles = @(1..([int]$ShardMatch.Groups[3].Value) | ForEach-Object {
        Join-Path (Split-Path -Parent $InputModel) ('{0}-{1:00000}-of-{2:00000}.gguf' -f $ShardMatch.Groups[1].Value, $_, [int]$ShardMatch.Groups[3].Value)
    })
}
$InputBytes = [long]0
foreach ($FilePath in $ShardFiles) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Missing shard: $FilePath" }
    $InputBytes += (Get-Item -LiteralPath $FilePath).Length
}
$OutputDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($OutputModel))
if ($OutputDrive.AvailableFreeSpace -lt ($InputBytes + 1GB)) { throw 'The output drive needs space for another complete model plus 1 GiB.' }

& $Python -c 'import sys; sys.path.insert(0, sys.argv[1]); import gguf' (Join-Path $LlamaRoot 'gguf-py')
if ($LASTEXITCODE -ne 0) { throw 'Python dependencies are missing. Follow docs/evox2/README-ja.md.' }

Write-Host "Converter: $Converter"
Write-Host "Input    : $InputModel"
Write-Host "Output   : $OutputModel"
Write-Host ('Input size: {0:N2} GiB. The original files are retained.' -f ($InputBytes / 1GB))
& $Python $Converter $InputModel $PartialOutput
if ($LASTEXITCODE -ne 0) { throw "Conversion failed. Incomplete output, if present: $PartialOutput" }

$VerifyArguments = @($Verifier, '--llama-root', $LlamaRoot, '--input', $InputModel, '--output', $PartialOutput)
if ($VerifyBytes) { $VerifyArguments += '--verify-bytes' }
& $Python @VerifyArguments
if ($LASTEXITCODE -ne 0) { throw "Verification failed. Output remains at: $PartialOutput" }
Move-Item -LiteralPath $PartialOutput -Destination $OutputModel -ErrorAction Stop
Write-Host "Ready: $OutputModel"
