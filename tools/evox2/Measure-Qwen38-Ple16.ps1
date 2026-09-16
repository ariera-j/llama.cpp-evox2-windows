#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Unsloth', 'Agention')][string]$ModelKind = 'Unsloth',
    [ValidateSet(65536, 131072, 262144)][int]$Context = 65536,
    [ValidateSet('f16', 'q8_0')][string]$KvType = 'f16',
    [ValidateSet(128, 256, 512, 1024)][int]$UBatch = 1024,
    [switch]$Mtp,
    [string]$DraftModel = '',
    [ValidateRange(1, 8)][int]$DraftMax = 2,
    [string]$InputFile = '',
    [switch]$AllocationOnly,
    [switch]$DryRun,
    [string]$UmaVramLabel = '96GB',
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$LlamaCli,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ModelFile,
    [string]$LogDir = (Join-Path (Get-Location).Path 'evox2-logs'),
    [ValidateRange(0, 8192)][int]$PromptCacheMiB = 0
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $Utf8NoBom
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }

if ($AllocationOnly -and $InputFile) { throw 'Use either -AllocationOnly or -InputFile.' }
if (-not $AllocationOnly -and -not $InputFile) {
    throw 'Pass -InputFile, or use -AllocationOnly for a short-prompt allocation check.'
}
if ($Mtp -and -not $DraftModel) { throw 'MTP requires -DraftModel with the path to a compatible MTP head GGUF.' }
if ($UmaVramLabel -notmatch '^[A-Za-z0-9_-]+$') { throw 'Use letters, digits, underscores or hyphens for -UmaVramLabel.' }

$RequiredFiles = @($LlamaCli, $ModelFile)
if ($Mtp) { $RequiredFiles += $DraftModel }
if (-not $AllocationOnly) { $RequiredFiles += $InputFile }
foreach ($FilePath in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "File not found: $FilePath" }
}
$LlamaCli = (Resolve-Path -LiteralPath $LlamaCli).Path
$ModelFile = (Resolve-Path -LiteralPath $ModelFile).Path
if ($Mtp) { $DraftModel = (Resolve-Path -LiteralPath $DraftModel).Path }
if ($InputFile) { $InputFile = (Resolve-Path -LiteralPath $InputFile).Path }

$LlamaArguments = @('-m', $ModelFile, '-c', "$Context", '-ngl', '999', '-ncmoe', '0',
    '-t', '4', '-b', '2048', '-ub', "$UBatch", '-fa', '1', '-lv', '4',
    '-ctk', $KvType, '-ctv', $KvType, '-fit', 'off', '--cache-ram', "$PromptCacheMiB",
    '--temp', '0.2', '--top-p', '0.8', '--jinja', '--single-turn', '--reasoning', 'off')
if ($Mtp) {
    $LlamaArguments += @('-md', $DraftModel, '--spec-type', 'draft-mtp',
        '--n-gpu-layers-draft', '999', '--spec-draft-n-max', "$DraftMax", '--spec-draft-p-min', '0',
        '--cache-type-k-draft', $KvType, '--cache-type-v-draft', $KvType)
} else {
    $LlamaArguments += @('--spec-type', 'none')
}
if ($AllocationOnly) {
    $LlamaArguments += @('-n', '32', '-p', 'Reply with the word OK.')
} else {
    $LlamaArguments += @('-n', '1024', '-f', $InputFile)
}
$Workload = if ($AllocationOnly) { 'allocation-short-prompt' } else { 'input-file' }
$MtpLabel = if ($Mtp) { 'mtp' } else { 'nomtp' }
$CommandText = ($LlamaCli | ConvertTo-Json -Compress) + ' ' + (($LlamaArguments | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ' ')
Write-Host "Workload: $Workload; UMA label: $UmaVramLabel; model: $ModelKind"
Write-Host 'Arguments below are JSON-escaped for display; execution uses an argument array.'
Write-Host $CommandText
if ($DryRun) { return }

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$Stem = "$Stamp-$UmaVramLabel-$ModelKind-ple16-ctx-$Context-$KvType-ub-$UBatch-$MtpLabel-$Workload"
$LogFile = Join-Path $LogDir ($Stem + '.log')
$SummaryFile = Join-Path $LogDir ($Stem + '.csv')
$Started = Get-Date
$Header = @(
    "START: $($Started.ToString('o'))", 'BACKEND: Vulkan (expected; check device lines)',
    "UMA_LABEL: $UmaVramLabel (manual label, not a BIOS measurement)",
    "MODEL: $ModelKind", "MODELFILE: $ModelFile", "CTX_REQUESTED: $Context",
    "KV_REQUESTED: $KvType", "UBATCH: $UBatch", "MTP: $([bool]$Mtp)",
    "DRAFT: $DraftModel", "WORKLOAD: $Workload", "INPUT: $InputFile",
    "PROMPT_CACHE_MIB: $PromptCacheMiB", 'COMMAND_DISPLAY_FORMAT: JSON-escaped arguments',
    "COMMAND: $CommandText"
)
$Header += @(Get-ChildItem Env: | Where-Object { $_.Name -like 'GGML_VK_*' } | Sort-Object Name | ForEach-Object { "ENV: $($_.Name)=$($_.Value)" })
$Writer = New-Object System.IO.StreamWriter($LogFile, $false, $Utf8NoBom)
$Writer.AutoFlush = $true
$Writer.WriteLine(($Header -join [Environment]::NewLine))
$ExitCode = -1
$LocationPushed = $false
try {
    Push-Location (Split-Path -Parent $LlamaCli)
    $LocationPushed = $true
    # Windows PowerShell wraps native stderr in ErrorRecord even for normal logs.
    $ErrorActionPreference = 'Continue'
    & $LlamaCli @LlamaArguments 2>&1 | ForEach-Object {
        $Line = $_.ToString()
        [Console]::WriteLine($Line)
        $Writer.WriteLine($Line)
    }
    $ExitCode = $LASTEXITCODE
} catch {
    $Writer.WriteLine("RUN_EXCEPTION: $($_.Exception.Message)")
} finally {
    $ErrorActionPreference = 'Stop'
    if ($LocationPushed) { Pop-Location }
    $Writer.Dispose()
}
$Finished = Get-Date
$LogText = [System.IO.File]::ReadAllText($LogFile, $Utf8NoBom)
$Culture = [System.Globalization.CultureInfo]::InvariantCulture
function Last-Number {
    param([string]$Pattern, [int]$Group = 1)
    $Found = [regex]::Matches($LogText, $Pattern)
    if ($Found.Count -eq 0) { return $null }
    return [double]::Parse($Found[$Found.Count - 1].Groups[$Group].Value, $Culture)
}
$PromptPattern = 'prompt eval time\s*=\s*[\d.]+ ms /\s*(\d+) tokens\s*\([^\r\n]*?([\d.]+) tokens per second\)'
$GenerationPattern = '(?m)^[^\r\n]*?(?<!prompt )\beval time\s*=\s*[\d.]+ ms /\s*(\d+) tokens\s*\([^\r\n]*?([\d.]+) tokens per second\)'
$PromptTokens = Last-Number $PromptPattern 1
$ActualContext = Last-Number 'llama_context:\s+n_ctx\s*=\s*(\d+)'
$EnoughInput = if ($AllocationOnly -or $null -eq $PromptTokens) { $false } else { $PromptTokens -ge ($Context * 0.8) }
$Status = if ($ExitCode -ne 0) { 'FAILED' } elseif ($ActualContext -ne $Context) { 'CHECK_CONTEXT' } else { 'OK' }
$Summary = [PSCustomObject]@{
    Started = $Started.ToString('o'); Finished = $Finished.ToString('o')
    Status = $Status; ExitCode = $ExitCode; DurationMinutes = [Math]::Round(($Finished - $Started).TotalMinutes, 2)
    UmaLabel = $UmaVramLabel; Model = $ModelKind; ModelFile = $ModelFile; LlamaCli = $LlamaCli
    Workload = $Workload; RequestedContext = $Context; ActualContext = $ActualContext
    KvType = $KvType; UBatch = $UBatch; MTP = [bool]$Mtp; DraftModel = $DraftModel
    PromptCacheMiB = $PromptCacheMiB; PromptTokens = $PromptTokens; InputAtLeast80Percent = $EnoughInput
    PP = (Last-Number $PromptPattern 2); TG = (Last-Number $GenerationPattern 2)
    GeneratedTokens = (Last-Number $GenerationPattern 1)
    CpuMappedMiB = (Last-Number 'CPU_Mapped model buffer size\s*=\s*([\d.]+) MiB')
    InputFile = $InputFile; LogFile = $LogFile
}
$Summary | Export-Csv -LiteralPath $SummaryFile -NoTypeInformation -Encoding UTF8
$Summary | Format-List
if (-not $AllocationOnly -and -not $EnoughInput) { Write-Warning 'Input did not fill 80% of the requested context. Treat this as a shorter-input result.' }
if ($ModelKind -eq 'Unsloth' -and $Summary.CpuMappedMiB -gt 20000) { Write-Warning 'The large CPU-mapped table is still present. Check the selected model and offload log.' }
Write-Host "Log: $LogFile"
Write-Host "CSV: $SummaryFile"
if ($Status -ne 'OK') { throw "Run did not complete as requested: $Status (exit $ExitCode)" }
