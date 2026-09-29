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
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
Import-Module $commonModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

$InputFile = (Resolve-Path -LiteralPath $InputFile).Path
$OutputFile = [IO.Path]::GetFullPath($OutputFile)

if (Test-Path -LiteralPath $OutputFile) {
    throw "Output already exists: $OutputFile"
}

if ([string]::IsNullOrWhiteSpace($ConverterScript)) {
    if ([string]::IsNullOrWhiteSpace($SourceForkRoot)) {
        throw 'Pass -SourceForkRoot or -ConverterScript for the external LaurentZuijdwijk converter.'
    }

    $SourceForkRoot = [IO.Path]::GetFullPath($SourceForkRoot)
    $ConverterScript = Join-Path `
        $SourceForkRoot `
        'gguf-py\gguf\scripts\gguf_split_ple_heads.py'
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
    $OutputFile
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
    Tool = 'external PLE layout converter'
    SourceRepository = 'https://github.com/LaurentZuijdwijk/llama.cpp'
    SourceForkRoot = $SourceForkRoot
    ConverterScript = $ConverterScript
    ConverterSha256 = $converterIdentity.Sha256
    SourceCommit = if ($sourceGit) { $sourceGit.Commit } else { $null }
    Input = $InputFile
    InputShardCount = $InputShards.Count
    Output = $OutputFile
    Verify = (-not $SkipVerify)
    HashModels = [bool]$HashModels
}

Write-Host ''
Write-Host '================ Planned PLE conversion ================'
$preview | Format-List | Out-Host
Write-Host ''
Write-Host 'Important: gguf_split_ple_heads.py is an external tool.'
Write-Host 'It is not authored or vendored by this repository.'
Write-Host 'Source: https://github.com/LaurentZuijdwijk/llama.cpp'
Write-Host '========================================================'
Write-Host ''

if ($DryRun) {
    return $preview
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
}

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
        ToolRole = 'external converter invoked by a local wrapper'
        SourceRepository = 'https://github.com/LaurentZuijdwijk/llama.cpp'
        SourceScript = 'gguf-py/gguf/scripts/gguf_split_ple_heads.py'
        SourceLicense = 'MIT'
        Note = (
            'The Python conversion algorithm is external. ' +
            'This repository only records and invokes it.'
        )
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
