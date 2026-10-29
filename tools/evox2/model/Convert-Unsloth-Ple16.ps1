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
    [switch]$FinalizePartial,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Identical Win32 fallback to the validated benchmark launcher: PowerShell 5.1
# can return $null for Process.ExitCode after Start-Process -PassThru.
if (-not ('Evox2NativeProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Evox2NativeProcess {
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);
}
'@
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
Import-Module $commonModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

if ($VerifyBytes -and $SkipVerify) {
    throw 'Do not use -VerifyBytes together with -SkipVerify.'
}
if ($FinalizePartial -and $PreflightOnly) {
    throw 'Use -FinalizePartial or -PreflightOnly, not both.'
}
if ($FinalizePartial -and $SkipVerify) {
    throw 'Cannot finalize an existing partial GGUF without verification.'
}

$InputFile = (Resolve-Path -LiteralPath $InputFile).Path
$OutputFile = [IO.Path]::GetFullPath($OutputFile)

$PartialOutput = $OutputFile + '.partial.gguf'
if (Test-Path -LiteralPath $OutputFile) {
    throw "Output already exists (nothing overwritten): $OutputFile"
}
if ($FinalizePartial) {
    if (-not (Test-Path -LiteralPath $PartialOutput -PathType Leaf)) {
        throw "No partial GGUF to verify: $PartialOutput"
    }
} elseif (Test-Path -LiteralPath $PartialOutput) {
    throw "Partial GGUF already exists. Use -FinalizePartial to verify/recover it, or inspect it manually: $PartialOutput"
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
if (-not $FinalizePartial -and -not $PreflightOnly -and -not $DryRun -and
    $outputDrive.AvailableFreeSpace -lt ($InputBytes + 1GB)) {
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
    $PartialOutput,
    '--expect-operation',
    'split'
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
    FinalizePartial = [bool]$FinalizePartial
    HashModels = [bool]$HashModels
}

Write-Host ''
Write-Host '================ Planned PLE conversion ================'
$preview | Format-List | Out-Host
Write-Host ''
Write-Host 'Derived converter: LaurentZuijdwijk/llama.cpp (MIT), adapted for r5.'
Write-Host 'Original input is retained; output remains partial until verified.'
if ($FinalizePartial) {
    Write-Host 'RECOVERY: no conversion will run; existing partial GGUF must pass verification.'
}
Write-Host '========================================================'
Write-Host ''

if ($DryRun) {
    return $preview
}

if ($PreflightOnly) {
    Write-Host 'Running GGUF layout preflight (no output created)...'
    & $Python $ConverterScript $InputFile $PartialOutput --check-only --expect-operation split
    if ($LASTEXITCODE -ne 0) {
        throw "PLE preflight failed: exit code $LASTEXITCODE."
    }
    Write-Host 'Preflight passed; no output created.'
    return $preview
}

# A previous complete conversion can be recovered without rewriting ~87 GiB.
if (-not $FinalizePartial) {
    & $Python $ConverterScript $InputFile $PartialOutput --check-only --expect-operation split
    if ($LASTEXITCODE -ne 0) {
        throw "PLE preflight failed: exit code $LASTEXITCODE."
    }
}

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputFile) | Out-Null

$started = Get-Date
$exitCode = $null
$exitCodeSource = if ($FinalizePartial) { 'unavailable-from-original-run' } else { 'not-collected' }
$recoveredPartial = [bool]$FinalizePartial

if (-not $FinalizePartial) {
    Write-Host "Conversion log directory: $runDir"
    Write-Host 'Starting PLE converter...'

    $argumentLine = (
        $converterArgs |
        ForEach-Object {
            $value = [string]$_
            if ($value -match '[\\s"]') {
                '"' + ($value -replace '"', '\\"') + '"'
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

    # Retain the native handle BEFORE the process exits, as with Measure-LlamaCli.ps1.
    $processHandle = $process.Handle
    $nextHeartbeat = (Get-Date).AddSeconds(30)
    while (-not $process.HasExited) {
        Start-Sleep -Seconds 1
        $process.Refresh()
        if ((Get-Date) -ge $nextHeartbeat) {
            $elapsed = (Get-Date) - $started
            Write-Host (
                'Converting... PID {0}, elapsed {1:N1} min' -f
                $process.Id, $elapsed.TotalMinutes
            )
            $nextHeartbeat = (Get-Date).AddSeconds(30)
        }
    }
    $process.WaitForExit()
    $process.Refresh()
    try {
        $managedCode = $process.ExitCode
        if ($null -ne $managedCode -and "$managedCode" -ne '') {
            $exitCode = [uint32]$managedCode
            $exitCodeSource = 'Process.ExitCode'
        }
    } catch {}
    if ($null -eq $exitCode -and $processHandle -ne [IntPtr]::Zero) {
        [uint32]$nativeCode = 0
        $nativeOk = [Evox2NativeProcess]::GetExitCodeProcess($processHandle, [ref]$nativeCode)
        if ($nativeOk) {
            $exitCode = $nativeCode
            $exitCodeSource = 'GetExitCodeProcess'
        }
    }
    if ($null -eq $exitCode -or $exitCode -ne 0) {
        Write-Host 'Last converter stderr lines:'
        if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Tail 80 | ForEach-Object { Write-Host $_ }
        }
        throw "Converter failed or exit status unavailable: $exitCode (source: $exitCodeSource). Check partial GGUF; recover with -FinalizePartial only after inspecting logs."
    }
} else {
    Write-Host "Recovering existing partial GGUF: $PartialOutput"
    Write-Host 'Conversion will NOT run. Rechecking existing output before renaming.'
}

if (-not (Test-Path -LiteralPath $PartialOutput -PathType Leaf)) {
    throw "Expected partial output GGUF not found: $PartialOutput"
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
            $PartialOutput,
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
    $verifyRecord['PayloadVerification'] = [ordered]@{
        ExitCode = $payloadCheck.ExitCode
        Output = $payloadCheck.Text
        VerifyBytes = [bool]$VerifyBytes
    }
    if ($payloadCheck.ExitCode -ne 0) {
        throw "PLE payload verification failed: exit code $($payloadCheck.ExitCode)."
    }
}

# Rename only after both conversion and enabled verification succeed.
# The original source and the verified partial are on the same output drive
# when the user follows the documented layout; this rename avoids a second copy.
Move-Item -LiteralPath $PartialOutput -Destination $OutputFile -ErrorAction Stop
$finished = Get-Date

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
        ExitCodeSource = $exitCodeSource
        RecoveredExistingPartial = $recoveredPartial
        Note = if ($recoveredPartial) {
            'The original conversion exited earlier without a readable exit status; this invocation performed verification and finalization only.'
        } else { $null }
    }

    Verification = $verifyRecord

    Logs = [ordered]@{
        RunDirectory = $runDir
        Stdout = if ($recoveredPartial) { $null } else { $stdoutPath }
        Stderr = if ($recoveredPartial) { $null } else { $stderrPath }
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
if ($recoveredPartial) {
    Write-Host 'PLE recovery verified and finalized successfully.'
} else {
    Write-Host 'PLE conversion completed.'
}
Write-Host "Output     : $OutputFile"
Write-Host "Provenance : $SidecarPath"
Write-Host "Run log    : $runDir"
