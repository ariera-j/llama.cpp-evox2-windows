#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$LocalConfig = '',

    [string]$BuildKey = '',
    [string]$LlamaBench = '',

    [string]$ModelKey = '',
    [string]$ModelFile = '',

    [string]$InputKey = '',
    [string]$InputFile = '',

    [ValidateSet('head-tail', 'head')]
    [string]$PromptSlice = 'head-tail',

    [ValidateRange(0, 4194304)]
    [int]$Context = 0,

    [ValidateRange(0, 4194304)]
    [int[]]$PromptTokens = @(512),

    [ValidateRange(0, 4194304)]
    [int[]]$GenerationTokens = @(128),

    [ValidateRange(0, 4194304)]
    [int[]]$Depths = @(0),

    [ValidateRange(1, 100)]
    [int]$Repetitions = 3,

    [ValidateRange(0, 3600)]
    [int]$DelaySeconds = 0,

    [ValidateNotNullOrEmpty()]
    [string]$KvType = 'f16',

    [ValidateRange(1, 65536)]
    [int]$UBatch = 1024,

    [ValidateRange(1, 65536)]
    [int]$Batch = 2048,

    [ValidateRange(1, 512)]
    [int]$Threads = 4,

    [ValidateRange(-1, 9999)]
    [int]$GpuLayers = 999,

    [ValidateRange(0, 9999)]
    [int]$CpuMoe = 0,

    [ValidateSet('on', 'off', 'auto')]
    [string]$FlashAttn = 'on',

    [switch]$NoWarmup,

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
# from Start-Process -PassThru even after the child has exited. Retain the
# process handle and use GetExitCodeProcess as a fallback, matching the
# llama-cli wrapper.
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
$inputEntry = $null

if (-not [string]::IsNullOrWhiteSpace($BuildKey)) {
    $buildEntry = Get-Evox2ConfigEntry -Config $Config -Section Builds -Key $BuildKey

    if ([string]::IsNullOrWhiteSpace($LlamaBench)) {
        if (-not $buildEntry.ContainsKey('BinDir')) {
            throw "Build '$BuildKey' does not define BinDir."
        }
        $LlamaBench = Join-Path $buildEntry.BinDir 'llama-bench.exe'
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedBackend) -and
        $buildEntry.ContainsKey('ExpectedBackend')) {
        $ExpectedBackend = [string]$buildEntry.ExpectedBackend
    }
}

if ([string]::IsNullOrWhiteSpace($LlamaBench)) {
    throw 'Specify -LlamaBench or -BuildKey.'
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

if (-not [string]::IsNullOrWhiteSpace($InputKey)) {
    $inputEntry = Get-Evox2ConfigEntry -Config $Config -Section Inputs -Key $InputKey
    if ([string]::IsNullOrWhiteSpace($InputFile)) {
        $InputFile = [string]$inputEntry
    }
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

if (-not (Test-Path -LiteralPath $LlamaBench -PathType Leaf)) {
    throw "Required file not found: $LlamaBench"
}
if (-not (Test-Path -LiteralPath $ModelFile -PathType Leaf)) {
    throw "Required file not found: $ModelFile"
}
if (-not [string]::IsNullOrWhiteSpace($InputFile) -and
    -not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
    throw "Required file not found: $InputFile"
}

$LlamaBench = (Resolve-Path -LiteralPath $LlamaBench).Path
$ModelFile = (Resolve-Path -LiteralPath $ModelFile).Path
if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
    $InputFile = (Resolve-Path -LiteralPath $InputFile).Path
}

$PromptTokens = @($PromptTokens | Sort-Object -Unique)
$GenerationTokens = @($GenerationTokens | Sort-Object -Unique)
$Depths = @($Depths | Sort-Object -Unique)

if ($PromptTokens.Count -eq 0) {
    throw '-PromptTokens must contain at least one value.'
}
if ($GenerationTokens.Count -eq 0) {
    throw '-GenerationTokens must contain at least one value.'
}
if ($Depths.Count -eq 0) {
    throw '-Depths must contain at least one value.'
}

$hasPromptWork = @($PromptTokens | Where-Object { $_ -gt 0 }).Count -gt 0
$hasGenerationWork = @($GenerationTokens | Where-Object { $_ -gt 0 }).Count -gt 0

if (-not $hasPromptWork -and -not $hasGenerationWork) {
    throw 'At least one prompt-processing or generation workload must be non-zero.'
}

Write-Host 'Detecting llama-bench executable, backend, Git, and system metadata...'
$Identity = Get-Evox2LlamaIdentity `
    -Executable $LlamaBench `
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
if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
    $InputIdentity = Get-Evox2FileIdentity -Path $InputFile -Sha256
}

$ModelAlias = $null
if ($null -ne $modelEntry -and $modelEntry.ContainsKey('Alias')) {
    $ModelAlias = [string]$modelEntry.Alias
}

$LlamaArguments = @(
    '-m', $ModelFile,
    '-p', ($PromptTokens -join ','),
    '-n', ($GenerationTokens -join ','),
    '-d', ($Depths -join ','),
    '-r', "$Repetitions",
    '--delay', "$DelaySeconds",
    '-b', "$Batch",
    '-ub', "$UBatch",
    '-ctk', $KvType,
    '-ctv', $KvType,
    '-t', "$Threads",
    '-ngl', "$GpuLayers",
    '-ncmoe', "$CpuMoe",
    '-fa', $FlashAttn,
    '-o', 'json'
)

if ($Context -gt 0) {
    $LlamaArguments += @('-c', "$Context")
}

if ($InputIdentity) {
    $LlamaArguments += @(
        '-f', $InputFile,
        '--prompt-slice', $PromptSlice
    )
}

if ($NoWarmup) {
    $LlamaArguments += '--no-warmup'
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
    Tool = 'llama-bench'

    Executable = [ordered]@{
        Sha256      = $Identity.Executable.Sha256
        BuildNumber = $Identity.Executable.BuildNumber
        Commit      = $Identity.Executable.Commit
        Compiler    = $Identity.Executable.Compiler
    }

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
            Path        = $InputIdentity.Path
            LengthBytes = $InputIdentity.LengthBytes
            Sha256      = $InputIdentity.Sha256
            Slice       = $PromptSlice
        }
    } else {
        [ordered]@{
            Mode = 'random-tokens'
        }
    }

    Benchmark = [ordered]@{
        PromptTokens     = @($PromptTokens)
        Context          = $Context
        PromptSlice      = if ($InputIdentity) { $PromptSlice } else { $null }
        GenerationTokens = @($GenerationTokens)
        Depths           = @($Depths)
        Repetitions      = $Repetitions
        DelaySeconds     = $DelaySeconds
        KvType           = $KvType
        UBatch           = $UBatch
        Batch            = $Batch
        Threads          = $Threads
        GpuLayers        = $GpuLayers
        CpuMoe           = $CpuMoe
        FlashAttn        = $FlashAttn
        NoWarmup         = [bool]$NoWarmup
        ExtraArgs        = @($ExtraArgs)
    }

    ManualConditions = [ordered]@{
        UmaLabel = $UmaLabel
    }

    Environment = $RelevantEnvironment
}

$ConditionId = Get-Evox2ConditionId -Condition $ConditionFingerprint
$BuildLabel = Get-Evox2BuildLabel -ExecutableMetadata $Identity.Executable
$CommandLine = ConvertTo-Evox2CommandLine `
    -Executable $LlamaBench `
    -Arguments $LlamaArguments

$maxPrompt = ($PromptTokens | Measure-Object -Maximum).Maximum
$maxDepth = ($Depths | Measure-Object -Maximum).Maximum
$ContextHint = if ($Context -gt 0) {
    $Context
} else {
    [Math]::Max([int]$maxPrompt, [int]$maxDepth)
}
if ($ContextHint -lt 1) {
    $ContextHint = 1
}

$Preview = [PSCustomObject]@{
    Tool              = 'llama-bench'
    BackendDetected   = $DetectedBackend
    Build             = $BuildLabel
    ExecutableCommit  = $Identity.Executable.Commit
    Compiler          = $Identity.Executable.Compiler
    Model             = $ModelIdentity.Name
    ModelAlias        = $ModelAlias
    Input             = if ($InputIdentity) { $InputIdentity.Name } else { 'random-tokens' }
    PromptSlice       = if ($InputIdentity) { $PromptSlice } else { $null }
    Context           = $Context
    PromptTokens      = ($PromptTokens -join ',')
    GenerationTokens  = ($GenerationTokens -join ',')
    Depths            = ($Depths -join ',')
    Repetitions       = $Repetitions
    KvType            = $KvType
    UBatch            = $UBatch
    MTP               = $false
    UmaLabel          = $UmaLabel
    ResourceMonitor   = [bool]$ResourceMonitor
    ConditionId       = $ConditionId
    GitCommit         = $Identity.Git.Commit
    GitDirty          = $Identity.Git.Dirty
    LogRoot           = $LogRoot
}

Write-Host ''
Write-Host '================ Planned llama-bench run ================'
$Preview | Format-List | Out-Host
Write-Host 'Command:'
Write-Host $CommandLine
Write-Host '========================================================='
Write-Host ''

if ($DryRun) {
    return $Preview
}

$RunDirectory = New-Evox2RunDirectory `
    -LogRoot $LogRoot `
    -Tool 'bench' `
    -Backend $DetectedBackend `
    -BuildLabel $BuildLabel `
    -Context $ContextHint `
    -ConditionId $ConditionId

$RunId = Split-Path -Leaf $RunDirectory
$ConditionsPath = Join-Path $RunDirectory 'conditions.json'
$ResultPath = Join-Path $RunDirectory 'result.json'
$SummaryPath = Join-Path $RunDirectory 'summary.csv'
$NativeJsonPath = Join-Path $RunDirectory 'llama-bench.json'
$StdErrPath = Join-Path $RunDirectory 'stderr.log'
$OutputPath = Join-Path $RunDirectory 'output.log'
$ResourcePath = Join-Path $RunDirectory 'resources.csv'
$MonitorStdOutPath = Join-Path $RunDirectory 'resource-monitor.stdout.log'
$MonitorStdErrPath = Join-Path $RunDirectory 'resource-monitor.stderr.log'

# Keep optional QSA union diagnostics with the other benchmark artifacts.
# The child inherits this environment; the caller's environment is restored in finally.
$QsaStatsFile = $null
$AutoQsaStatsFile = $false
if ($env:GGML_VK_QSA_UNION_STATS -eq '1') {
    if ([string]::IsNullOrWhiteSpace($env:GGML_VK_QSA_UNION_STATS_FILE)) {
        $QsaStatsFile = Join-Path $RunDirectory 'qsa-union-stats.csv'
        $env:GGML_VK_QSA_UNION_STATS_FILE = $QsaStatsFile
        $AutoQsaStatsFile = $true
    } else {
        $QsaStatsFile = $env:GGML_VK_QSA_UNION_STATS_FILE
    }
}

# Place opt-in FA dispatch diagnostics beside the normal result artifacts.
# The native backend writes once when its context is freed, after all PP passes.
$FaDispatchDiagFile = $null
$AutoFaDispatchDiagFile = $false
if ($env:GGML_VK_FA_DISPATCH_DIAG -eq '1') {
    if ([string]::IsNullOrWhiteSpace($env:GGML_VK_FA_DISPATCH_DIAG_FILE)) {
        $FaDispatchDiagFile = Join-Path $RunDirectory 'fa-dispatch-diag.csv'
        $env:GGML_VK_FA_DISPATCH_DIAG_FILE = $FaDispatchDiagFile
        $AutoFaDispatchDiagFile = $true
    } else {
        $FaDispatchDiagFile = $env:GGML_VK_FA_DISPATCH_DIAG_FILE
    }
}

# FA mask-tile histogram: native Vulkan backend emits the one-shot snapshot
# after GPU synchronization; place the CSV in the unique run directory.
$FaMaskDiagFile = $null
$AutoFaMaskDiagFile = $false
if ($env:GGML_VK_FA_MASK_DIAG -eq '1') {
    if ([string]::IsNullOrWhiteSpace($env:GGML_VK_FA_MASK_DIAG_FILE)) {
        $FaMaskDiagFile = Join-Path $RunDirectory 'fa-mask-tile-diag.csv'
        $env:GGML_VK_FA_MASK_DIAG_FILE = $FaMaskDiagFile
        $AutoFaMaskDiagFile = $true
    } else {
        $FaMaskDiagFile = $env:GGML_VK_FA_MASK_DIAG_FILE
    }
}

$Started = Get-Date

$Conditions = [ordered]@{
    SchemaVersion = 1
    RunId          = $RunId
    ConditionId    = $ConditionId
    StartedAt      = $Started.ToString('o')
    Tool           = 'llama-bench'
    Command        = $CommandLine
    Arguments      = @($LlamaArguments)

    LookupKeys = [ordered]@{
        BuildKey = $BuildKey
        ModelKey = $ModelKey
        InputKey = $InputKey
    }

    HumanAliases = [ordered]@{
        Model = $ModelAlias
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
    BuildManifest      = $Identity.BuildManifest
    GitIdentity        = $Identity.Git
    SystemIdentity     = $Identity.System

    ModelIdentity      = $ModelIdentity
    InputIdentity      = $InputIdentity
    EffectiveCondition = $ConditionFingerprint
    Environment        = $RelevantEnvironment
    QsaUnionStatsFile  = $QsaStatsFile
    FaDispatchDiagFile = $FaDispatchDiagFile
    FaMaskDiagFile     = $FaMaskDiagFile

    Notes = @(
        'llama-bench measurements exclude tokenization and sampling time.',
        'When an input file is specified, prompt-processing uses tokenized file content instead of random token IDs.',
        'PromptSlice=head-tail keeps ceil(N/2) tokens from the head and floor(N/2) tokens from the tail.',
        'Prompt-processing (-p) and generation (-n) are separate tests unless llama-bench -pg is used.',
        'Depth (-d) pre-fills the KV cache before each benchmark test.',
        'This Phase 3 wrapper does not benchmark MTP/speculative decoding.'
    )
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
    Write-Host 'Starting llama-bench...'

    $process = Start-Process `
        -FilePath $LlamaBench `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $LlamaBench) `
        -RedirectStandardOutput $NativeJsonPath `
        -RedirectStandardError $StdErrPath `
        -NoNewWindow `
        -PassThru

    Write-Host "llama-bench PID: $($process.Id)"

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
                'Running llama-bench... PID {0}, elapsed {1:N1} min' -f
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
    } catch {}

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
    if ($AutoQsaStatsFile) {
        Remove-Item Env:GGML_VK_QSA_UNION_STATS_FILE -ErrorAction SilentlyContinue
    }
    if ($AutoFaDispatchDiagFile) {
        Remove-Item Env:GGML_VK_FA_DISPATCH_DIAG_FILE -ErrorAction SilentlyContinue
    }
    if ($AutoFaMaskDiagFile) {
        Remove-Item Env:GGML_VK_FA_MASK_DIAG_FILE -ErrorAction SilentlyContinue
    }
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
    'Evo-X2 llama-bench measurement',
    "RUN_ID: $RunId",
    "CONDITION_ID: $ConditionId",
    "START: $($Started.ToString('o'))",
    "FINISH: $($Finished.ToString('o'))",
    "BACKEND_DETECTED: $DetectedBackend",
    "LLAMA_BUILD: $BuildLabel",
    "EXECUTABLE_COMMIT: $($Identity.Executable.Commit)",
    "UMA_LABEL: $UmaLabel (manual label; not auto-detected)",
    "MODELFILE: $ModelFile",
    "INPUT: $(if ($InputIdentity) { $InputFile } else { 'random-tokens' })",
    "PROMPT_SLICE: $(if ($InputIdentity) { $PromptSlice } else { '' })",
    "CONTEXT: $Context",
    "PROMPT_TOKENS: $($PromptTokens -join ',')",
    "GENERATION_TOKENS: $($GenerationTokens -join ',')",
    "DEPTHS: $($Depths -join ',')",
    "REPETITIONS: $Repetitions",
    "COMMAND: $CommandLine"
)

Write-Evox2CombinedLog `
    -Path $OutputPath `
    -HeaderLines $HeaderLines `
    -StdErrPath $StdErrPath `
    -StdOutPath $NativeJsonPath

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$NativeJson = ''
$NativeRows = @()
$parseException = $null

if (Test-Path -LiteralPath $NativeJsonPath -PathType Leaf) {
    $NativeJson = [IO.File]::ReadAllText($NativeJsonPath, $Utf8NoBom)

    if (-not [string]::IsNullOrWhiteSpace($NativeJson)) {
        try {
            $NativeRows = @(
                ConvertFrom-Evox2LlamaBenchJson -Json $NativeJson
            )
        } catch {
            $parseException = $_.Exception.ToString()
        }
    }
}

$Status = if ($null -ne $runException) {
    'FAILED_EXCEPTION'
} elseif ($null -eq $ExitCode) {
    'CHECK_EXITCODE'
} elseif ($ExitCode -ne 0) {
    'FAILED'
} elseif ($null -ne $parseException) {
    'CHECK_OUTPUT'
} elseif ($NativeRows.Count -eq 0) {
    'CHECK_OUTPUT'
} else {
    'OK'
}

$resourceSampleCount = 0
if (Test-Path -LiteralPath $ResourcePath -PathType Leaf) {
    try {
        $resourceSampleCount = @(Import-Csv -LiteralPath $ResourcePath).Count
    } catch {}
}

$SummaryRows = @()

foreach ($row in $NativeRows) {
    $sampleCount = 0
    if ($null -ne $row.samples_ts) {
        $sampleCount = @($row.samples_ts).Count
    }

    $SummaryRows += [PSCustomObject]@{
        RunId             = $RunId
        ConditionId       = $ConditionId
        Status            = $Status
        ExitCode          = $ExitCode
        ExitCodeSource    = $ExitCodeSource

        BackendDetected   = $DetectedBackend
        BenchBackends     = $row.backends
        Build             = $BuildLabel
        BuildNumber       = $row.build_number
        BenchBuildCommit  = $row.build_commit
        ExecutableCommit  = $Identity.Executable.Commit
        GitCommit         = $Identity.Git.Commit
        GitDirty          = $Identity.Git.Dirty

        UmaLabel          = $UmaLabel
        ModelFile         = $ModelFile
        ModelAlias        = $ModelAlias
        InputFile         = if ($InputIdentity) { $InputFile } else { $null }
        InputSha256       = if ($InputIdentity) { $InputIdentity.Sha256 } else { $null }
        PromptSlice       = if ($InputIdentity) { $PromptSlice } else { $null }
        Context           = $Context
        ModelType         = $row.model_type
        ModelSizeBytes    = $row.model_size
        ModelParams       = $row.model_n_params

        Test              = Get-Evox2LlamaBenchTestLabel -Row $row
        PromptTokens      = $row.n_prompt
        GenerationTokens  = $row.n_gen
        Depth             = $row.n_depth

        Batch             = $row.n_batch
        UBatch            = $row.n_ubatch
        Threads           = $row.n_threads
        KvTypeK           = $row.type_k
        KvTypeV           = $row.type_v
        GpuLayers         = $row.n_gpu_layers
        CpuMoe            = $row.n_cpu_moe
        FlashAttn         = $row.flash_attn

        AvgTokensPerSec   = $row.avg_ts
        StdDevTokensPerSec = $row.stddev_ts
        AvgNanoseconds    = $row.avg_ns
        StdDevNanoseconds = $row.stddev_ns
        RepetitionSamples = $sampleCount

        ResourceSamples   = $resourceSampleCount
        RunDirectory      = $RunDirectory
    }
}

if ($SummaryRows.Count -eq 0) {
    $SummaryRows = @(
        [PSCustomObject]@{
            RunId             = $RunId
            ConditionId       = $ConditionId
            Status            = $Status
            ExitCode          = $ExitCode
            ExitCodeSource    = $ExitCodeSource
            BackendDetected   = $DetectedBackend
            BenchBackends     = $null
            Build             = $BuildLabel
            BuildNumber       = $Identity.Executable.BuildNumber
            BenchBuildCommit  = $null
            ExecutableCommit  = $Identity.Executable.Commit
            GitCommit         = $Identity.Git.Commit
            GitDirty          = $Identity.Git.Dirty
            UmaLabel          = $UmaLabel
            ModelFile         = $ModelFile
            ModelAlias        = $ModelAlias
            InputFile         = if ($InputIdentity) { $InputFile } else { $null }
            InputSha256       = if ($InputIdentity) { $InputIdentity.Sha256 } else { $null }
            PromptSlice       = if ($InputIdentity) { $PromptSlice } else { $null }
            Context           = $Context
            ModelType         = $null
            ModelSizeBytes    = $ModelIdentity.LengthBytes
            ModelParams       = $null
            Test              = $null
            PromptTokens      = $null
            GenerationTokens  = $null
            Depth             = $null
            Batch             = $Batch
            UBatch            = $UBatch
            Threads           = $Threads
            KvTypeK           = $KvType
            KvTypeV           = $KvType
            GpuLayers         = $GpuLayers
            CpuMoe            = $CpuMoe
            FlashAttn         = $FlashAttn
            AvgTokensPerSec   = $null
            StdDevTokensPerSec = $null
            AvgNanoseconds    = $null
            StdDevNanoseconds = $null
            RepetitionSamples = 0
            ResourceSamples   = $resourceSampleCount
            RunDirectory      = $RunDirectory
        }
    )
}

$Result = [ordered]@{
    SchemaVersion = 1
    RunId          = $RunId
    ConditionId    = $ConditionId

    Status         = $Status
    ExitCode       = $ExitCode
    ExitCodeSource = $ExitCodeSource
    RunException   = $runException
    ParseException = $parseException

    StartedAt      = $Started.ToString('o')
    FinishedAt     = $Finished.ToString('o')
    DurationSeconds = [math]::Round(($Finished - $Started).TotalSeconds, 3)

    BackendDetected  = $DetectedBackend
    BuildNumber      = $Identity.Executable.BuildNumber
    ExecutableCommit = $Identity.Executable.Commit
    ExecutableSha256 = $Identity.Executable.Sha256
    Compiler         = $Identity.Executable.Compiler

    ManualUmaLabel   = $UmaLabel

    Requested = [ordered]@{
        PromptTokens     = @($PromptTokens)
        Context          = $Context
        InputFile        = if ($InputIdentity) { $InputFile } else { $null }
        InputSha256      = if ($InputIdentity) { $InputIdentity.Sha256 } else { $null }
        PromptSlice      = if ($InputIdentity) { $PromptSlice } else { $null }
        GenerationTokens = @($GenerationTokens)
        Depths           = @($Depths)
        Repetitions      = $Repetitions
        DelaySeconds     = $DelaySeconds
        Batch            = $Batch
        UBatch           = $UBatch
        Threads          = $Threads
        KvType           = $KvType
        GpuLayers        = $GpuLayers
        CpuMoe           = $CpuMoe
        FlashAttn        = $FlashAttn
        NoWarmup         = [bool]$NoWarmup
    }

    NativeRowCount = $NativeRows.Count
    NativeRows     = @($NativeRows)

    ResourceMonitorEnabled = [bool]$ResourceMonitor
    ResourceSampleCount    = $resourceSampleCount

    Files = [ordered]@{
        Conditions = $ConditionsPath
        Result     = $ResultPath
        Summary    = $SummaryPath
        NativeJson = $NativeJsonPath
        Output     = $OutputPath
        StdErr     = $StdErrPath
        Resources  = if (Test-Path -LiteralPath $ResourcePath) { $ResourcePath } else { $null }
        QsaUnionStats = if ($QsaStatsFile -and (Test-Path -LiteralPath $QsaStatsFile)) { $QsaStatsFile } else { $null }
        FaDispatchDiag = if ($FaDispatchDiagFile -and (Test-Path -LiteralPath $FaDispatchDiagFile)) { $FaDispatchDiagFile } else { $null }
        FaMaskDiag = if ($FaMaskDiagFile -and (Test-Path -LiteralPath $FaMaskDiagFile)) { $FaMaskDiagFile } else { $null }
    }
}

Write-Evox2Json -InputObject $Result -Path $ResultPath -Depth 32
$SummaryRows | Export-Csv -LiteralPath $SummaryPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host '================ llama-bench result ================'
$SummaryRows |
    Format-Table Test, AvgTokensPerSec, StdDevTokensPerSec, BenchBackends, RepetitionSamples -AutoSize |
    Out-Host

Write-Host "Status          : $Status"
Write-Host "ExitCode        : $ExitCode"
Write-Host "ExitCodeSource  : $ExitCodeSource"
Write-Host "ResourceSamples : $resourceSampleCount"
Write-Host "RunDirectory    : $RunDirectory"
Write-Host "conditions.json : $ConditionsPath"
Write-Host "result.json     : $ResultPath"
Write-Host "summary.csv     : $SummaryPath"
Write-Host "llama-bench.json: $NativeJsonPath"
Write-Host "output.log      : $OutputPath"
if ($QsaStatsFile) {
    Write-Host "QSA union stats : $QsaStatsFile"
}
if ($FaDispatchDiagFile) {
    Write-Host "FA dispatch diag: $FaDispatchDiagFile"
    if (-not (Test-Path -LiteralPath $FaDispatchDiagFile -PathType Leaf)) {
        Write-Warning 'FA dispatch diagnostics were requested, but no CSV was found. Check stderr.log.'
    }
}
if ($FaMaskDiagFile) {
    Write-Host "FA mask tiles   : $FaMaskDiagFile"
    if (-not (Test-Path -LiteralPath $FaMaskDiagFile -PathType Leaf)) {
        Write-Warning 'FA mask tile diagnostics were requested but no CSV was found. Check stderr.log for snapshot status.'
    }
}
if ($ResourceMonitor) {
    Write-Host "resources.csv   : $ResourcePath"
}
Write-Host '===================================================='
Write-Host ''

if ($ResourceMonitor -and $resourceSampleCount -eq 0) {
    Write-Warning 'Resource monitoring was requested, but resources.csv contains no samples.'
}

if ($Status -ne 'OK') {
    if (Test-Path -LiteralPath $StdErrPath -PathType Leaf) {
        Write-Host 'Last stderr lines:'
        Get-Content -LiteralPath $StdErrPath -Tail 60 | ForEach-Object {
            Write-Host $_
        }
    }

    if (-not $NoThrowOnFailure) {
        $exitDisplay = if ($null -eq $ExitCode) { 'unavailable' } else { "$ExitCode" }
        throw "llama-bench run did not complete as requested: $Status (exit $exitDisplay, source $ExitCodeSource)"
    }
}

return $SummaryRows
