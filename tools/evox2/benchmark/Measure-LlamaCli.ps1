#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LocalConfig = '',

    [string]$BuildKey = '',
    [string]$LlamaCli = '',

    [string]$ModelKey = '',
    [string]$ModelFile = '',

    [string]$InputKey = '',
    [string]$InputFile = '',

    [switch]$AllocationOnly,

    [ValidateRange(256, 4194304)]
    [int]$Context = 65536,

    [ValidateNotNullOrEmpty()]
    [string]$KvType = 'f16',

    [ValidateRange(1, 65536)]
    [int]$UBatch = 1024,

    [ValidateRange(1, 65536)]
    [int]$Batch = 2048,

    [ValidateRange(1, 512)]
    [int]$Threads = 4,

    [ValidateRange(0, 9999)]
    [int]$GpuLayers = 999,

    [ValidateRange(0, 9999)]
    [int]$CpuMoe = 0,

    [ValidateNotNullOrEmpty()]
    [string]$FlashAttn = '1',

    [ValidateRange(0, 10)]
    [int]$Verbosity = 4,

    [ValidateRange(1, 65536)]
    [int]$GenerationTokens = 1024,

    [ValidateRange(0, 1048576)]
    [int]$PromptCacheMiB = 0,

    [ValidateRange(0.0, 10.0)]
    [double]$Temperature = 0.2,

    [ValidateRange(0.0, 1.0)]
    [double]$TopP = 0.8,

    [ValidateNotNullOrEmpty()]
    [string]$Reasoning = 'off',

    [ValidateNotNullOrEmpty()]
    [string]$Fit = 'off',

    [switch]$NoJinja,
    [switch]$NoSingleTurn,

    [switch]$Mtp,

    [string]$DraftModelKey = '',
    [string]$DraftModel = '',

    [ValidateRange(1, 64)]
    [int]$DraftMax = 2,

    [ValidateRange(0.0, 1.0)]
    [double]$DraftPMin = 0.0,

    [string]$UmaLabel = '',
    [string]$ExpectedBackend = '',

    [switch]$HashModel,

    [switch]$ResourceMonitor,

    [ValidateRange(1, 60)]
    [int]$ResourceIntervalSeconds = 2,

    [ValidateRange(5, 300)]
    [int]$ProgressIntervalSeconds = 15,

    [string[]]$ExtraArgs = @(),

    [switch]$DryRun,
    [switch]$NoThrowOnFailure
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 can occasionally expose a blank Process.ExitCode
# from Start-Process -PassThru even after the child has exited. Keep the
# native process handle and use GetExitCodeProcess as a fallback.
if (-not ('Evox2NativeProcess' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Evox2NativeProcess {
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetExitCodeProcess(
        IntPtr hProcess,
        out uint lpExitCode
    );
}
'@
}

$benchmarkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $benchmarkDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
$benchmarkModule = Join-Path $benchmarkDir 'Evox2.Benchmark.psm1'

Import-Module $commonModule -Force
Import-Module $benchmarkModule -Force
Set-Evox2Utf8Console

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($LocalConfig)) {
    $LocalConfig = Join-Path $benchmarkDir 'configs\local.psd1'
}

$Config = Import-Evox2LocalConfig -Path $LocalConfig
$buildEntry = $null
$modelEntry = $null
$draftEntry = $null

if (-not [string]::IsNullOrWhiteSpace($BuildKey)) {
    $buildEntry = Get-Evox2ConfigEntry -Config $Config -Section Builds -Key $BuildKey

    if ([string]::IsNullOrWhiteSpace($LlamaCli)) {
        if (-not $buildEntry.ContainsKey('BinDir')) {
            throw "Build '$BuildKey' does not define BinDir."
        }
        $LlamaCli = Join-Path $buildEntry.BinDir 'llama-cli.exe'
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedBackend) -and
        $buildEntry.ContainsKey('ExpectedBackend')) {
        $ExpectedBackend = [string]$buildEntry.ExpectedBackend
    }
}

if ([string]::IsNullOrWhiteSpace($LlamaCli)) {
    throw 'Specify -LlamaCli or -BuildKey.'
}

if (-not [string]::IsNullOrWhiteSpace($ModelKey)) {
    $modelEntry = Get-Evox2ConfigEntry -Config $Config -Section Models -Key $ModelKey

    if ([string]::IsNullOrWhiteSpace($ModelFile)) {
        if (-not $modelEntry.ContainsKey('Path')) {
            throw "Model '$ModelKey' does not define Path."
        }
        $ModelFile = [string]$modelEntry.Path
    }
}

if ([string]::IsNullOrWhiteSpace($ModelFile)) {
    throw 'Specify -ModelFile or -ModelKey.'
}

if ($AllocationOnly) {
    if (-not [string]::IsNullOrWhiteSpace($InputFile) -or
        -not [string]::IsNullOrWhiteSpace($InputKey)) {
        throw 'Do not specify -InputFile or -InputKey together with -AllocationOnly.'
    }
} else {
    if (-not [string]::IsNullOrWhiteSpace($InputKey)) {
        $resolvedInput = Get-Evox2ConfigEntry -Config $Config -Section Inputs -Key $InputKey
        if ([string]::IsNullOrWhiteSpace($InputFile)) {
            $InputFile = [string]$resolvedInput
        }
    }

    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        throw 'Specify -InputFile or -InputKey, or use -AllocationOnly.'
    }
}

if ($Mtp) {
    if (-not [string]::IsNullOrWhiteSpace($DraftModelKey)) {
        $draftEntry = Get-Evox2ConfigEntry -Config $Config -Section Models -Key $DraftModelKey

        if ([string]::IsNullOrWhiteSpace($DraftModel)) {
            if (-not $draftEntry.ContainsKey('Path')) {
                throw "Draft model '$DraftModelKey' does not define Path."
            }
            $DraftModel = [string]$draftEntry.Path
        }
    }

    if ([string]::IsNullOrWhiteSpace($DraftModel)) {
        throw 'MTP requires -DraftModel or -DraftModelKey.'
    }
} elseif (-not [string]::IsNullOrWhiteSpace($DraftModel) -or
          -not [string]::IsNullOrWhiteSpace($DraftModelKey)) {
    throw 'Draft model was supplied but -Mtp was not specified.'
}

if ([string]::IsNullOrWhiteSpace($UmaLabel) -and
    $Config.ContainsKey('UmaLabel')) {
    $UmaLabel = [string]$Config.UmaLabel
}
if ([string]::IsNullOrWhiteSpace($UmaLabel)) {
    $UmaLabel = 'unspecified'
}

$LogRoot = Join-Path $RepoRoot 'evox2-logs'
if ($Config.ContainsKey('LogRoot') -and
    -not [string]::IsNullOrWhiteSpace([string]$Config.LogRoot)) {
    $LogRoot = [string]$Config.LogRoot
}

$RequiredFiles = @($LlamaCli, $ModelFile)
if (-not $AllocationOnly) {
    $RequiredFiles += $InputFile
}
if ($Mtp) {
    $RequiredFiles += $DraftModel
}

foreach ($path in $RequiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file not found: $path"
    }
}

$LlamaCli = (Resolve-Path -LiteralPath $LlamaCli).Path
$ModelFile = (Resolve-Path -LiteralPath $ModelFile).Path
if (-not $AllocationOnly) {
    $InputFile = (Resolve-Path -LiteralPath $InputFile).Path
}
if ($Mtp) {
    $DraftModel = (Resolve-Path -LiteralPath $DraftModel).Path
}

Write-Host 'Detecting executable, backend, Git, and system metadata...'
$Identity = Get-Evox2LlamaIdentity `
    -Executable $LlamaCli `
    -RepoRoot $RepoRoot

$DetectedBackend = [string]$Identity.Device.BackendDetected
if ([string]::IsNullOrWhiteSpace($DetectedBackend)) {
    $DetectedBackend = 'Unknown'
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedBackend) -and
    $DetectedBackend -ne $ExpectedBackend) {
    throw "Backend expectation mismatch: expected '$ExpectedBackend', detected '$DetectedBackend'."
}

$ModelIdentity = Get-Evox2FileIdentity -Path $ModelFile -Sha256:$HashModel
$InputIdentity = $null
if (-not $AllocationOnly) {
    $InputIdentity = Get-Evox2FileIdentity -Path $InputFile -Sha256
}

$DraftIdentity = $null
if ($Mtp) {
    $DraftIdentity = Get-Evox2FileIdentity -Path $DraftModel
}

$ModelAlias = $null
if ($null -ne $modelEntry -and $modelEntry.ContainsKey('Alias')) {
    $ModelAlias = [string]$modelEntry.Alias
}

$DraftAlias = $null
if ($null -ne $draftEntry -and $draftEntry.ContainsKey('Alias')) {
    $DraftAlias = [string]$draftEntry.Alias
}

$Culture = [Globalization.CultureInfo]::InvariantCulture

$LlamaArguments = @(
    '-m', $ModelFile,
    '-c', "$Context",
    '-ngl', "$GpuLayers",
    '-ncmoe', "$CpuMoe",
    '-t', "$Threads",
    '-b', "$Batch",
    '-ub', "$UBatch",
    '-fa', $FlashAttn,
    '-lv', "$Verbosity",
    '-ctk', $KvType,
    '-ctv', $KvType,
    '-fit', $Fit,
    '--cache-ram', "$PromptCacheMiB",
    '--temp', $Temperature.ToString('0.################', $Culture),
    '--top-p', $TopP.ToString('0.################', $Culture),
    '--reasoning', $Reasoning
)

if (-not $NoJinja) {
    $LlamaArguments += '--jinja'
}
if (-not $NoSingleTurn) {
    $LlamaArguments += '--single-turn'
}

if ($Mtp) {
    $LlamaArguments += @(
        '-md', $DraftModel,
        '--spec-type', 'draft-mtp',
        '--n-gpu-layers-draft', "$GpuLayers",
        '--spec-draft-n-max', "$DraftMax",
        '--spec-draft-p-min', $DraftPMin.ToString('0.################', $Culture),
        '--cache-type-k-draft', $KvType,
        '--cache-type-v-draft', $KvType
    )
} else {
    $LlamaArguments += @('--spec-type', 'none')
}

$Workload = if ($AllocationOnly) {
    'allocation-short-prompt'
} else {
    'input-file'
}

if ($AllocationOnly) {
    $LlamaArguments += @(
        '-n', '32',
        '-p', 'Reply with the word OK.'
    )
} else {
    $LlamaArguments += @(
        '-n', "$GenerationTokens",
        '-f', $InputFile
    )
}

if ($ExtraArgs.Count -gt 0) {
    $LlamaArguments += $ExtraArgs
}

$RelevantEnvironment = Get-Evox2RelevantEnvironment

$primaryDevice = @(
    $Identity.Device.Devices |
    Where-Object { $_.Backend -eq $DetectedBackend } |
    Select-Object -First 1
)
$primaryDeviceObject = if ($primaryDevice.Count -gt 0) { $primaryDevice[0] } else { $null }

$ConditionFingerprint = [ordered]@{
    SchemaVersion = 1
    Tool = 'llama-cli'

    Executable = [ordered]@{
        Sha256      = $Identity.Executable.Sha256
        BuildNumber = $Identity.Executable.BuildNumber
        Commit      = $Identity.Executable.Commit
        Compiler    = $Identity.Executable.Compiler
    }

    RuntimeArtifactDigest = $Identity.RuntimeArtifacts.Digest

    Backend = $DetectedBackend

    Device = if ($primaryDeviceObject) {
        [ordered]@{
            Id       = $primaryDeviceObject.Id
            Name     = $primaryDeviceObject.Name
            TotalMiB = $primaryDeviceObject.TotalMiB
        }
    } else {
        $null
    }

    Model = [ordered]@{
        Path             = $ModelIdentity.Path
        LengthBytes      = $ModelIdentity.LengthBytes
        LastWriteTimeUtc = $ModelIdentity.LastWriteTimeUtc
        Sha256           = $ModelIdentity.Sha256
    }

    Input = if ($InputIdentity) {
        [ordered]@{
            Sha256      = $InputIdentity.Sha256
            LengthBytes = $InputIdentity.LengthBytes
        }
    } else {
        [ordered]@{
            AllocationOnly = $true
        }
    }

    Inference = [ordered]@{
        Context            = $Context
        KvType             = $KvType
        UBatch             = $UBatch
        Batch              = $Batch
        Threads            = $Threads
        GpuLayers          = $GpuLayers
        CpuMoe             = $CpuMoe
        FlashAttn          = $FlashAttn
        Verbosity          = $Verbosity
        GenerationTokens   = if ($AllocationOnly) { 32 } else { $GenerationTokens }
        PromptCacheMiB     = $PromptCacheMiB
        Temperature        = $Temperature
        TopP               = $TopP
        Reasoning          = $Reasoning
        Fit                = $Fit
        Jinja              = -not $NoJinja
        SingleTurn         = -not $NoSingleTurn
        Mtp                = [bool]$Mtp
        DraftMax           = if ($Mtp) { $DraftMax } else { $null }
        DraftPMin          = if ($Mtp) { $DraftPMin } else { $null }
        ExtraArgs          = @($ExtraArgs)
    }

    DraftModel = if ($DraftIdentity) {
        [ordered]@{
            Path             = $DraftIdentity.Path
            LengthBytes      = $DraftIdentity.LengthBytes
            LastWriteTimeUtc = $DraftIdentity.LastWriteTimeUtc
        }
    } else {
        $null
    }

    ManualConditions = [ordered]@{
        UmaLabel = $UmaLabel
    }

    Environment = $RelevantEnvironment
}

$ConditionId = Get-Evox2ConditionId -Condition $ConditionFingerprint
$BuildLabel = Get-Evox2BuildLabel -ExecutableMetadata $Identity.Executable
$CommandLine = ConvertTo-Evox2CommandLine `
    -Executable $LlamaCli `
    -Arguments $LlamaArguments

$Preview = [PSCustomObject]@{
    Tool              = 'llama-cli'
    BackendDetected   = $DetectedBackend
    Build             = $BuildLabel
    ExecutableCommit  = $Identity.Executable.Commit
    Compiler          = $Identity.Executable.Compiler
    Model             = $ModelIdentity.Name
    ModelAlias        = $ModelAlias
    Input             = if ($InputIdentity) { $InputIdentity.Name } else { $null }
    Context           = $Context
    KvType            = $KvType
    UBatch            = $UBatch
    MTP               = [bool]$Mtp
    UmaLabel          = $UmaLabel
    ResourceMonitor   = [bool]$ResourceMonitor
    ConditionId       = $ConditionId
    GitCommit         = $Identity.Git.Commit
    GitDirty          = $Identity.Git.Dirty
    LogRoot           = $LogRoot
}

Write-Host ''
Write-Host '================ Planned run ================'
$Preview | Format-List | Out-Host
Write-Host 'Command:'
Write-Host $CommandLine
Write-Host '============================================='
Write-Host ''

if ($DryRun) {
    return $Preview
}

$RunDirectory = New-Evox2RunDirectory `
    -LogRoot $LogRoot `
    -Tool 'cli' `
    -Backend $DetectedBackend `
    -BuildLabel $BuildLabel `
    -Context $Context `
    -ConditionId $ConditionId

$RunId = Split-Path -Leaf $RunDirectory
$ConditionsPath = Join-Path $RunDirectory 'conditions.json'
$ResultPath = Join-Path $RunDirectory 'result.json'
$SummaryPath = Join-Path $RunDirectory 'summary.csv'
$StdOutPath = Join-Path $RunDirectory 'stdout.log'
$StdErrPath = Join-Path $RunDirectory 'stderr.log'
$OutputPath = Join-Path $RunDirectory 'output.log'
$ResourcePath = Join-Path $RunDirectory 'resources.csv'
$MonitorStdOutPath = Join-Path $RunDirectory 'resource-monitor.stdout.log'
$MonitorStdErrPath = Join-Path $RunDirectory 'resource-monitor.stderr.log'

$Started = Get-Date

$Conditions = [ordered]@{
    SchemaVersion = 1
    RunId          = $RunId
    ConditionId    = $ConditionId
    StartedAt      = $Started.ToString('o')
    Tool           = 'llama-cli'
    Workload       = $Workload
    Command        = $CommandLine
    Arguments      = @($LlamaArguments)

    LookupKeys = [ordered]@{
        BuildKey      = $BuildKey
        ModelKey      = $ModelKey
        InputKey      = $InputKey
        DraftModelKey = $DraftModelKey
    }

    HumanAliases = [ordered]@{
        Model = $ModelAlias
        Draft = $DraftAlias
    }

    ManualConditions = [ordered]@{
        UmaLabel = $UmaLabel
    }

    ResourceMonitor = [ordered]@{
        Enabled         = [bool]$ResourceMonitor
        IntervalSeconds = if ($ResourceMonitor) { $ResourceIntervalSeconds } else { $null }
    }

    ExecutableIdentity = $Identity.Executable
    DeviceIdentity     = $Identity.Device
    RuntimeArtifacts   = $Identity.RuntimeArtifacts
    BuildManifest      = $Identity.BuildManifest
    GitIdentity        = $Identity.Git
    SystemIdentity     = $Identity.System

    ModelIdentity      = $ModelIdentity
    DraftModelIdentity = $DraftIdentity
    InputIdentity      = $InputIdentity

    EffectiveCondition = $ConditionFingerprint
    Environment        = $RelevantEnvironment
}

Write-Evox2Json -InputObject $Conditions -Path $ConditionsPath -Depth 24

$argumentLine = (
    $LlamaArguments |
    ForEach-Object { ConvertTo-Evox2WindowsArgument -Value ([string]$_) }
) -join ' '

$process = $null
$processHandle = [IntPtr]::Zero
$monitorProcess = $null
$ExitCode = $null
$ExitCodeSource = 'unavailable'
$runException = $null

try {
    Write-Host "Run directory: $RunDirectory"
    Write-Host "Starting llama-cli..."

    $process = Start-Process `
        -FilePath $LlamaCli `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $LlamaCli) `
        -RedirectStandardOutput $StdOutPath `
        -RedirectStandardError $StdErrPath `
        -NoNewWindow `
        -PassThru

    Write-Host "llama-cli PID: $($process.Id)"

    # Force .NET to open and retain a process handle while the child is alive.
    # This gives us a reliable native fallback for the exit code later.
    $processHandle = $process.Handle

    if ($ResourceMonitor) {
        $monitorScript = Join-Path $benchmarkDir 'Monitor-LlamaProcess.ps1'
        $powerShellExe = (Get-Process -Id $PID).Path

        $monitorArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $monitorScript,
            '-TargetProcessId', "$($process.Id)",
            '-LogPath', $ResourcePath,
            '-RunId', $RunId,
            '-IntervalSeconds', "$ResourceIntervalSeconds"
        )

        $monitorArgumentLine = (
            $monitorArgs |
            ForEach-Object { ConvertTo-Evox2WindowsArgument -Value ([string]$_) }
        ) -join ' '

        $monitorProcess = Start-Process `
            -FilePath $powerShellExe `
            -ArgumentList $monitorArgumentLine `
            -WorkingDirectory $benchmarkDir `
            -RedirectStandardOutput $MonitorStdOutPath `
            -RedirectStandardError $MonitorStdErrPath `
            -NoNewWindow `
            -PassThru

        Write-Host "Resource monitor PID: $($monitorProcess.Id)"
    }

    $nextProgress = (Get-Date).AddSeconds($ProgressIntervalSeconds)

    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()

        if ((Get-Date) -ge $nextProgress) {
            $elapsed = (Get-Date) - $Started
            Write-Host (
                'Running... PID {0}, elapsed {1:N1} min' -f
                $process.Id,
                $elapsed.TotalMinutes
            )
            $nextProgress = (Get-Date).AddSeconds($ProgressIntervalSeconds)
        }
    }

    $process.WaitForExit()
    $process.Refresh()

    try {
        $managedExitCode = $process.ExitCode
        if ($null -ne $managedExitCode -and "$managedExitCode" -ne '') {
            $ExitCode = [uint32]$managedExitCode
            $ExitCodeSource = 'System.Diagnostics.Process.ExitCode'
        }
    } catch {
        # Fall through to the native Win32 fallback below.
    }

    if ($null -eq $ExitCode -and $processHandle -ne [IntPtr]::Zero) {
        [uint32]$nativeExitCode = 0
        $nativeOk = [Evox2NativeProcess]::GetExitCodeProcess(
            $processHandle,
            [ref]$nativeExitCode
        )

        if ($nativeOk) {
            $ExitCode = $nativeExitCode
            $ExitCodeSource = 'GetExitCodeProcess'
        }
    }

    if ($null -eq $ExitCode) {
        Write-Warning 'The child process exited, but its exit code could not be retrieved.'
    }
} catch {
    $runException = $_.Exception.ToString()
    Write-Warning "Run exception: $($_.Exception.Message)"
} finally {
    if ($null -ne $monitorProcess) {
        try {
            if (-not $monitorProcess.HasExited) {
                if (-not $monitorProcess.WaitForExit(10000)) {
                    Stop-Process -Id $monitorProcess.Id -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {}
    }
}

$Finished = Get-Date

$HeaderLines = @(
    'Evo-X2 llama-cli measurement',
    "RUN_ID: $RunId",
    "CONDITION_ID: $ConditionId",
    "START: $($Started.ToString('o'))",
    "FINISH: $($Finished.ToString('o'))",
    "BACKEND_DETECTED: $DetectedBackend",
    "LLAMA_BUILD: $BuildLabel",
    "EXECUTABLE_COMMIT: $($Identity.Executable.Commit)",
    "UMA_LABEL: $UmaLabel (manual label; not auto-detected)",
    "MODELFILE: $ModelFile",
    "INPUT: $(if ($InputIdentity) { $InputFile } else { '' })",
    "MTP: $([bool]$Mtp)",
    "DRAFT: $DraftModel",
    "COMMAND: $CommandLine"
)

Write-Evox2CombinedLog `
    -Path $OutputPath `
    -HeaderLines $HeaderLines `
    -StdErrPath $StdErrPath `
    -StdOutPath $StdOutPath

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$CombinedText = [IO.File]::ReadAllText($OutputPath, $Utf8NoBom)
$Parsed = ConvertFrom-Evox2LlamaCliResult -Text $CombinedText
$DenseIndexerEvidence = Get-Evox2MtpDenseIndexerEvidence -Text $CombinedText `
    -Setting $env:LLAMA_MTP_SKIP_DENSE_INDEXER -Mtp ([bool]$Mtp)
$QsaNoopEvidence = Get-Evox2QsaNoopInvalidationEvidence -Text $CombinedText `
    -Setting $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION

$EnoughInput = $false
if (-not $AllocationOnly -and $null -ne $Parsed.PromptTokens) {
    $EnoughInput = $Parsed.PromptTokens -ge ($Context * 0.8)
}

$Status = if ($null -ne $runException) {
    'FAILED_EXCEPTION'
} elseif ($null -eq $ExitCode) {
    'CHECK_EXITCODE'
} elseif ($ExitCode -ne 0) {
    'FAILED'
} elseif ($null -eq $Parsed.ActualContext) {
    'CHECK_CONTEXT'
} elseif ([int64]$Parsed.ActualContext -ne [int64]$Context) {
    'CHECK_CONTEXT'
} elseif (-not $AllocationOnly -and $null -eq $Parsed.PromptTokensPerSecond) {
    'CHECK_TIMING'
} else {
    'OK'
}

$resourceSampleCount = 0
if ($Status -eq 'OK' -and $Mtp -and $env:LLAMA_MTP_SKIP_DENSE_INDEXER -in @('0', '1') -and
    $DenseIndexerEvidence.Status -ne 'Verified') {
    $Status = 'CANDIDATE_EVIDENCE_' + $DenseIndexerEvidence.Status.ToUpperInvariant()
}
if ($Status -eq 'OK' -and $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION -in @('0', '1') -and
    $QsaNoopEvidence.Status -ne 'Verified') {
    $Status = 'QSA_NOOP_EVIDENCE_' + $QsaNoopEvidence.Status.ToUpperInvariant()
}
if (Test-Path -LiteralPath $ResourcePath -PathType Leaf) {
    try {
        $resourceSampleCount = @(Import-Csv -LiteralPath $ResourcePath).Count
    } catch {}
}

$Result = [ordered]@{
    SchemaVersion = 1
    RunId          = $RunId
    ConditionId    = $ConditionId

    Status         = $Status
    ExitCode       = $ExitCode
    ExitCodeSource = $ExitCodeSource
    RunException   = $runException

    StartedAt      = $Started.ToString('o')
    FinishedAt     = $Finished.ToString('o')
    DurationSeconds = [math]::Round(($Finished - $Started).TotalSeconds, 3)

    BackendDetected = $DetectedBackend
    BuildNumber     = $Identity.Executable.BuildNumber
    ExecutableCommit = $Identity.Executable.Commit
    RuntimeArtifactStatus = $Identity.RuntimeArtifacts.Status
    RuntimeArtifactDigest = $Identity.RuntimeArtifacts.Digest
    ExecutableSha256 = $Identity.Executable.Sha256
    Compiler         = $Identity.Executable.Compiler

    ManualUmaLabel = $UmaLabel

    Workload         = $Workload
    RequestedContext = $Context
    ActualContext    = $Parsed.ActualContext
    KvType           = $KvType
    Batch            = $Batch
    UBatch           = $UBatch
    Threads          = $Threads
    Mtp              = [bool]$Mtp

    PromptTokens               = $Parsed.PromptTokens
    TaskPromptTokens           = $Parsed.TaskPromptTokens
    PromptEvalMilliseconds     = $Parsed.PromptEvalMilliseconds
    PromptTokensPerSecond      = $Parsed.PromptTokensPerSecond

    GeneratedTokens            = $Parsed.GeneratedTokens
    GenerationEvalMilliseconds = $Parsed.GenerationEvalMilliseconds
    GenerationTokensPerSecond  = $Parsed.GenerationTokensPerSecond

    TotalMilliseconds          = $Parsed.TotalMilliseconds
    TotalTokens                = $Parsed.TotalTokens

    DraftAcceptance            = $Parsed.DraftAcceptance
    DraftAccepted              = $Parsed.DraftAccepted
    DraftGenerated             = $Parsed.DraftGenerated
    MtpDenseIndexerEvidence     = $DenseIndexerEvidence
    QsaNoopInvalidationEvidence = $QsaNoopEvidence

    ModelArchitecture          = $Parsed.ModelArchitecture
    ModelFileType              = $Parsed.ModelFileType
    ModelFileSizeGiB           = $Parsed.ModelFileSizeGiB
    CpuMappedMiB               = $Parsed.CpuMappedMiB

    InputAtLeast80Percent       = $EnoughInput

    ResourceMonitorEnabled      = [bool]$ResourceMonitor
    ResourceSampleCount         = $resourceSampleCount

    Files = [ordered]@{
        Conditions = $ConditionsPath
        Result     = $ResultPath
        Summary    = $SummaryPath
        Output     = $OutputPath
        StdOut     = $StdOutPath
        StdErr     = $StdErrPath
        Resources  = if (Test-Path -LiteralPath $ResourcePath) { $ResourcePath } else { $null }
    }

    MemoryBreakdownLines = $Parsed.MemoryBreakdownLines
    BufferLines          = $Parsed.BufferLines
}

Write-Evox2Json -InputObject $Result -Path $ResultPath -Depth 24

$Summary = [PSCustomObject]@{
    RunId               = $RunId
    ConditionId         = $ConditionId
    Status              = $Status
    ExitCode            = $ExitCode
    ExitCodeSource      = $ExitCodeSource
    Backend             = $DetectedBackend
    Build               = $BuildLabel
    ExecutableCommit    = $Identity.Executable.Commit
    GitCommit           = $Identity.Git.Commit
    GitDirty            = $Identity.Git.Dirty
    UmaLabel            = $UmaLabel
    ModelFile           = $ModelFile
    ModelAlias          = $ModelAlias
    InputFile           = if ($InputIdentity) { $InputFile } else { '' }
    ContextRequested    = $Context
    ContextActual       = $Parsed.ActualContext
    PromptTokens        = $Parsed.PromptTokens
    PP                  = $Parsed.PromptTokensPerSecond
    GeneratedTokens     = $Parsed.GeneratedTokens
    TG                  = $Parsed.GenerationTokensPerSecond
    MTP                 = [bool]$Mtp
    DraftAcceptance     = $Parsed.DraftAcceptance
    DenseIndexerEvidence = $DenseIndexerEvidence.Status
    DenseIndexerOmitted  = $DenseIndexerEvidence.Omitted
    QsaNoopEvidence     = $QsaNoopEvidence.Status
    QsaNoopEnabled      = $QsaNoopEvidence.Enabled
    ResourceSamples     = $resourceSampleCount
    DurationMinutes     = [math]::Round(($Finished - $Started).TotalMinutes, 3)
    RunDirectory        = $RunDirectory
}

if ($env:LLAMA_MTP_DIAG -in @('wall', 'sync')) {
    try {
        & (Join-Path $PSScriptRoot 'Summarize-MtpDiagnostics.ps1') -RunDirectory $RunDirectory
        $Result.DiagnosticStatus = 'Complete'
    } catch {
        $Result.DiagnosticStatus = 'Incomplete'
        $Result.DiagnosticError = $_.Exception.Message
        if ($Status -eq 'OK') {
            $Status = 'DIAGNOSTIC_INCOMPLETE'
            $Result.Status = $Status
            $Summary.Status = $Status
        }
        Write-Warning $_.Exception.Message
    }
    $Result.Files.MtpDiagnostics = Join-Path $RunDirectory 'mtp-diagnostics.json'
    Write-Evox2Json -InputObject $Result -Path $ResultPath -Depth 24
}

$Summary | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '================ Result ================'
$Summary | Format-List | Out-Host
Write-Host "conditions.json : $ConditionsPath"
Write-Host "result.json     : $ResultPath"
Write-Host "summary.csv     : $SummaryPath"
Write-Host "output.log      : $OutputPath"
if ($ResourceMonitor) {
    Write-Host "resources.csv   : $ResourcePath"
}
Write-Host '========================================'
Write-Host ''

if (Test-Path -LiteralPath $StdOutPath -PathType Leaf) {
    $stdoutText = [IO.File]::ReadAllText($StdOutPath, $Utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
        Write-Host '================ Model stdout ================'
        [Console]::WriteLine($stdoutText)
        Write-Host '================================================'
    }
}

if (-not $AllocationOnly -and -not $EnoughInput) {
    Write-Warning 'Input did not fill 80% of the requested context. Treat this as a shorter-input result.'
}

if ($Status -ne 'OK') {
    if (Test-Path -LiteralPath $StdErrPath -PathType Leaf) {
        Write-Host 'Last stderr lines:'
        Get-Content -LiteralPath $StdErrPath -Tail 40 | ForEach-Object {
            Write-Host $_
        }
    }

    if (-not $NoThrowOnFailure) {
        $exitDisplay = if ($null -eq $ExitCode) { 'unavailable' } else { "$ExitCode" }
        throw "Run did not complete as requested: $Status (exit $exitDisplay, source $ExitCodeSource)"
    }
}

return $Summary
