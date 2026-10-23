#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [string]$SourceForkRoot = '',
    [string]$ConverterScript = '',
    [string]$Python = 'python',

    [string]$LogRoot = '',
    [string]$SidecarPath = '',

    [switch]$HashModels,
    [switch]$VerboseConverter,
    [switch]$SkipVerify,
    [switch]$VerifyBytes,
    [switch]$PreflightOnly,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
Import-Module $commonModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

if ($VerifyBytes -and $SkipVerify) {
    throw 'Do not use -VerifyBytes together with -SkipVerify.'
}

$InputFile = (Resolve-Path -LiteralPath $InputFile).Path
$OutputFile = [IO.Path]::GetFullPath($OutputFile)

$PartialOutput = $OutputFile + '.partial.gguf'
foreach ($candidate in @($OutputFile, $PartialOutput)) {
    if (Test-Path -LiteralPath $candidate) {
        throw "Output already exists (nothing overwritten): $candidate"
    }
}
if ($InputFile -eq $OutputFile -or $InputFile -eq $PartialOutput) {
    throw 'Output path must differ from input path.'
}

if ([string]::IsNullOrWhiteSpace($ConverterScript)) {
    if ([string]::IsNullOrWhiteSpace($SourceForkRoot)) {
        $SourceForkRoot = $RepoRoot
    }
    $SourceForkRoot = [IO.Path]::GetFullPath($SourceForkRoot)
    $ConverterScript = Join-Path $scriptDir 'gguf_split_ple_heads.py'
} else {
    $ConverterScript = (Resolve-Path -LiteralPath $ConverterScript).Path

    if ([string]::IsNullOrWhiteSpace($SourceForkRoot)) {
        $probe = Split-Path -Parent $ConverterScript
        for ($i = 0; $i -lt 3; $i++) {
            $probe = Split-Path -Parent $probe
        }
        $SourceForkRoot = $probe
    } else {
        $SourceForkRoot = [IO.Path]::GetFullPath($SourceForkRoot)
    }
}

if (-not (Test-Path -LiteralPath $ConverterScript -PathType Leaf)) {
    throw "External converter script not found: $ConverterScript"
}

$pythonCommand = Get-Command -Name $Python -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$Python = $pythonCommand.Source

$InputShards = @()
$inputItem = Get-Item -LiteralPath $InputFile
$match = [regex]::Match(
    $inputItem.Name,
    '^(.*)-(\d{5})-of-(\d{5})\.gguf$',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase
)

if ($match.Success) {
    $stem = $match.Groups[1].Value
    $total = [int]$match.Groups[3].Value
    if ([int]$match.Groups[2].Value -ne 1) {
        throw 'Pass shard 00001, not a later shard.'
    }

    for ($i = 1; $i -le $total; $i++) {
        $name = '{0}-{1:D5}-of-{2:D5}.gguf' -f $stem, $i, $total
        $path = Join-Path $inputItem.Directory.FullName $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing input shard: $path"
        }
        $InputShards += (Resolve-Path -LiteralPath $path).Path
    }
} else {
    $InputShards = @($InputFile)
}

# Check sufficient free space before producing a very large single GGUF.
$InputBytes = [long]0
foreach ($shard in $InputShards) {
    $InputBytes += (Get-Item -LiteralPath $shard).Length
}
$outputDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($OutputFile))
if ($outputDrive.AvailableFreeSpace -lt ($InputBytes + 1GB)) {
    throw ('Insufficient output disk space: available {0:N2} GiB, need at least {1:N2} GiB.' -f
        ($outputDrive.AvailableFreeSpace / 1GB), (($InputBytes + 1GB) / 1GB))
}

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $RepoRoot 'evox2-logs\model-conversion'
}
$LogRoot = [IO.Path]::GetFullPath($LogRoot)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runDir = Join-Path $LogRoot "$timestamp-ple-layout"
$stdoutPath = Join-Path $runDir 'converter.stdout.log'
$stderrPath = Join-Path $runDir 'converter.stderr.log'
$verifyPath = Join-Path $runDir 'ple-layout.json'
$provenancePath = Join-Path $runDir 'conversion.json'

if ([string]::IsNullOrWhiteSpace($SidecarPath)) {
    $SidecarPath = $OutputFile + '.evox2-conversion.json'
}
$SidecarPath = [IO.Path]::GetFullPath($SidecarPath)

$converterArgs = @(
    $ConverterScript,
    $InputFile,
    $PartialOutput
)
if ($VerboseConverter) {
    $converterArgs += '--verbose'
}

$sourceGit = $null
try {
    $sourceGit = Get-Evox2GitMetadata -RepoRoot $SourceForkRoot
} catch {}

$converterIdentity = Get-Evox2FileIdentity `
    -Path $ConverterScript `
    -Sha256

$inputIdentities = @()
foreach ($path in $InputShards) {
    $inputIdentities += Get-Evox2FileIdentity `
        -Path $path `
        -Sha256:$HashModels
}

$preview = [PSCustomObject]@{
    Tool = 'r5 downstream PLE converter (adapted from LaurentZuijdwijk)'
    SourceRepository = 'https://github.com/ariera-j/llama.cpp-evox2-windows'
    OriginalSource = 'https://github.com/LaurentZuijdwijk/llama.cpp'
    SourceForkRoot = $SourceForkRoot
    ConverterScript = $ConverterScript
    ConverterSha256 = $converterIdentity.Sha256
    SourceCommit = if ($sourceGit) { $sourceGit.Commit } else { $null }
    Input = $InputFile
    InputShardCount = $InputShards.Count
    Output = $OutputFile
    PartialOutput = $PartialOutput
    InputBytes = $InputBytes
    AvailableOutputBytes = $outputDrive.AvailableFreeSpace
    Verify = (-not $SkipVerify)
    VerifyBytes = [bool]$VerifyBytes
    HashModels = [bool]$HashModels
}

Write-Host ''
Write-Host '================ Planned PLE conversion ================'
$preview | Format-List | Out-Host
Write-Host ''
Write-Host 'Derived converter: LaurentZuijdwijk/llama.cpp (MIT), adapted for r5.'
Write-Host 'Original input is retained; output remains partial until verified.'
Write-Host '========================================================'
Write-Host ''

if ($DryRun) {
    return $preview
}

if ($PreflightOnly) {
    Write-Host 'Running GGUF layout preflight (no output created)...'
    & $Python $ConverterScript $InputFile $PartialOutput --check-only
    if ($LASTEXITCODE -ne 0) {
        throw "PLE preflight failed: exit code $LASTEXITCODE."
    }
    Write-Host 'Preflight passed; no output created.'
    return $preview
}

& $Python $ConverterScript $InputFile $PartialOutput --check-only
if ($LASTEXITCODE -ne 0) {
    throw "PLE preflight failed: exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputFile) | Out-Null

$started = Get-Date

Write-Host "Conversion log directory: $runDir"
Write-Host 'Starting external converter...'

$argumentLine = (
    $converterArgs |
    ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') {
            '"' + ($value -replace '"', '\"') + '"'
        } else {
            $value
        }
    }
) -join ' '

$process = Start-Process `
    -FilePath $Python `
    -ArgumentList $argumentLine `
    -WorkingDirectory $SourceForkRoot `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -NoNewWindow `
    -PassThru

$nextHeartbeat = (Get-Date).AddSeconds(30)
while (-not $process.HasExited) {
    Start-Sleep -Seconds 1
    $process.Refresh()

    if ((Get-Date) -ge $nextHeartbeat) {
        $elapsed = (Get-Date) - $started
        Write-Host (
            'Converting... PID {0}, elapsed {1:N1} min' -f
            $process.Id,
            $elapsed.TotalMinutes
        )
        $nextHeartbeat = (Get-Date).AddSeconds(30)
    }
}

$process.WaitForExit()
$process.Refresh()
$exitCode = $process.ExitCode
$finished = Get-Date

if ($exitCode -ne 0) {
    Write-Host 'Last converter stderr lines:'
    if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Tail 80 | ForEach-Object {
            Write-Host $_
        }
    }
    throw "External PLE converter failed with exit code $exitCode."
}

if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
    throw "Converter returned success but output is missing: $OutputFile"
}

$verifyRecord = $null
if (-not $SkipVerify) {
    $verifyScript = Join-Path $scriptDir 'verify-ple-layout.py'
    $ggufPy = Join-Path $SourceForkRoot 'gguf-py'

    if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
        throw "Verifier not found: $verifyScript"
    }
    if (-not (Test-Path -LiteralPath $ggufPy -PathType Container)) {
        throw "gguf-py directory not found in external source tree: $ggufPy"
    }

    Write-Host 'Verifying converted per-head PLE layout...'
    $verifyCapture = Invoke-Evox2NativeCapture `
        -FilePath $Python `
        -ArgumentList @(
            $verifyScript,
            $OutputFile,
            '--gguf-py', $ggufPy,
            '--expect', 'split',
            '--json', $verifyPath
        )

    $verifyRecord = [ordered]@{
        ExitCode = $verifyCapture.ExitCode
        Output = $verifyCapture.Text
        JsonPath = $verifyPath
    }

    if ($verifyCapture.ExitCode -ne 0) {
        throw "PLE layout verification failed with exit code $($verifyCapture.ExitCode)."
    }

    # Also check every tensor name/type/shape and preserved metadata.
    # -VerifyBytes additionally SHA-256 checks each tensor payload (slow).
    $payloadVerifier = Join-Path $scriptDir 'verify-ple16.py'
    $payloadArgs = @(
        $payloadVerifier, '--llama-root', $SourceForkRoot,
        '--input', $InputFile, '--output', $PartialOutput
    )
    if ($VerifyBytes) { $payloadArgs += '--verify-bytes' }
    $payloadCheck = Invoke-Evox2NativeCapture `
        -FilePath $Python `
        -ArgumentList $payloadArgs
    $verifyRecord.PayloadVerification = [ordered]@{
        ExitCode = $payloadCheck.ExitCode
        Output = $payloadCheck.Text
        VerifyBytes = [bool]$VerifyBytes
    }
    if ($payloadCheck.ExitCode -ne 0) {
        throw "PLE payload verification failed: exit code $($payloadCheck.ExitCode)."
    }
}

# Rename only after both conversion and enabled verification succeed.
Move-Item -LiteralPath $PartialOutput -Destination $OutputFile -ErrorAction Stop

$outputIdentity = Get-Evox2FileIdentity `
    -Path $OutputFile `
    -Sha256:$HashModels

$provenance = [ordered]@{
    SchemaVersion = 1
    StartedAt = $started.ToString('o')
    FinishedAt = $finished.ToString('o')
    DurationMinutes = [math]::Round(
        ($finished - $started).TotalMinutes,
        3
    )

    Operation = 'qwen4exp PLE joined-to-per-head layout conversion'

    Attribution = [ordered]@{
        AuthoredByThisRepository = $false
        ToolRole = 'in-repository adaptation of MIT-licensed external converter'
        SourceRepository = 'https://github.com/LaurentZuijdwijk/llama.cpp'
        SourceScript = 'gguf-py/gguf/scripts/gguf_split_ple_heads.py'
        ArchivedIn = 'r2/legacy'
        AdaptedScript = 'tools/evox2/model/gguf_split_ple_heads.py'
        SourceLicense = 'MIT'
        Note = 'Derived from LaurentZuijdwijk converter with r5 GGUF API compatibility adjustments.'
    }

    ExternalSourceCheckout = $sourceGit
    ConverterScriptIdentity = $converterIdentity
    PythonExecutable = $Python

    InputFiles = @($inputIdentities)
    OutputFile = $outputIdentity

    HashModels = [bool]$HashModels

    Command = [ordered]@{
        FilePath = $Python
        Arguments = @($converterArgs)
        WorkingDirectory = $SourceForkRoot
        ExitCode = $exitCode
    }

    Verification = $verifyRecord

    Logs = [ordered]@{
        RunDirectory = $runDir
        Stdout = $stdoutPath
        Stderr = $stderrPath
        VerificationJson = if (Test-Path -LiteralPath $verifyPath) {
            $verifyPath
        } else {
            $null
        }
    }
}

Write-Evox2Json -InputObject $provenance -Path $provenancePath -Depth 32
Write-Evox2Json -InputObject $provenance -Path $SidecarPath -Depth 32

Write-Host ''
Write-Host 'PLE conversion completed.'
Write-Host "Output     : $OutputFile"
Write-Host "Provenance : $SidecarPath"
Write-Host "Run log    : $runDir"
