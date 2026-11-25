#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Plan,

    [string]$LocalConfig = '',

    [ValidateSet('all', 'cli', 'bench')]
    [string]$Tool = 'all',

    [string[]]$OnlyJob = @(),
    [string[]]$OnlyCase = @(),
    [string[]]$OnlyVariant = @(),
    [string[]]$OnlyBuild = @(),

    [ValidateRange(1, 1000)]
    [int]$MaxRuns = 100,

    [ValidateRange(-1, 3600)]
    [int]$CooldownSeconds = -1,

    [switch]$StopOnError,
    [switch]$ResourceMonitor,
    [switch]$NoResourceMonitor,

    [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'

$benchmarkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $benchmarkDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'
$benchmarkModule = Join-Path $benchmarkDir 'Evox2.Benchmark.psm1'
$measureCli = Join-Path $benchmarkDir 'Measure-LlamaCli.ps1'
$measureBench = Join-Path $benchmarkDir 'Measure-LlamaBench.ps1'

Import-Module $commonModule -Force
Import-Module $benchmarkModule -Force
Import-Module (Join-Path $benchmarkDir 'Evox2.MatrixComparison.psm1') -Force
Set-Evox2Utf8Console

function Copy-Evox2Hashtable {
    param(
        [hashtable]$Source
    )

    $copy = @{}
    if ($null -eq $Source) {
        return $copy
    }

    foreach ($key in $Source.Keys) {
        $copy[$key] = $Source[$key]
    }

    return $copy
}

function Merge-Evox2Hashtable {
    param(
        [hashtable[]]$Tables
    )

    $merged = @{}

    foreach ($table in $Tables) {
        if ($null -eq $table) {
            continue
        }

        foreach ($key in $table.Keys) {
            $merged[$key] = $table[$key]
        }
    }

    return $merged
}

function Assert-Evox2Environment {
    param(
        [hashtable]$Environment,
        [string]$Context
    )

    foreach ($key in $Environment.Keys) {
        $name = [string]$key

        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name '$name' in $Context."
        }

        $value = $Environment[$key]
        if ($null -ne $value -and
            -not ($value -is [string]) -and
            -not ($value -is [ValueType])) {
            throw (
                "Environment variable '$name' in $Context must be a scalar " +
                'value or $null.'
            )
        }
    }
}

function ConvertTo-Evox2EnvironmentSummary {
    param(
        [hashtable]$Environment
    )

    if ($null -eq $Environment -or $Environment.Count -eq 0) {
        return ''
    }

    $parts = @()
    foreach ($key in @($Environment.Keys | Sort-Object)) {
        $value = $Environment[$key]
        if ($null -eq $value) {
            $parts += "$key=<unset>"
        } else {
            $parts += "$key=$value"
        }
    }

    return ($parts -join ';')
}

function Get-Evox2OptionalHashtable {
    param(
        [hashtable]$Parent,
        [string]$Key
    )

    if ($null -eq $Parent -or -not $Parent.ContainsKey($Key)) {
        return @{}
    }

    $value = $Parent[$Key]
    if ($null -eq $value) {
        return @{}
    }

    if (-not ($value -is [hashtable])) {
        throw "'$Key' must be a hashtable."
    }

    return $value
}

function Get-Evox2OptionalArray {
    param(
        [hashtable]$Parent,
        [string]$Key
    )

    if ($null -eq $Parent -or -not $Parent.ContainsKey($Key)) {
        return @()
    }

    $value = $Parent[$Key]
    if ($null -eq $value) {
        return @()
    }

    return @($value)
}

function Test-Evox2NameFilter {
    param(
        [string]$Value,
        [string[]]$Filter
    )

    if ($Filter.Count -eq 0) {
        return $true
    }

    foreach ($item in $Filter) {
        if ($Value -like $item) {
            return $true
        }
    }

    return $false
}

function Get-Evox2MatrixWorkloadLabel {
    param(
        [string]$ToolName,
        [hashtable]$Parameters
    )

    if ($ToolName -eq 'cli') {
        $context = if ($Parameters.ContainsKey('Context')) {
            [string]$Parameters.Context
        } else {
            'default'
        }

        $inputLabel = if ($Parameters.ContainsKey('AllocationOnly') -and
                     [bool]$Parameters.AllocationOnly) {
            'allocation'
        } elseif ($Parameters.ContainsKey('InputKey')) {
            [string]$Parameters.InputKey
        } elseif ($Parameters.ContainsKey('InputFile')) {
            Split-Path -Leaf ([string]$Parameters.InputFile)
        } else {
            'input?'
        }

        $mtp = if ($Parameters.ContainsKey('Mtp') -and [bool]$Parameters.Mtp) {
            'mtp'
        } else {
            'nomtp'
        }

        return "ctx=$context input=$inputLabel $mtp"
    }

    $p = if ($Parameters.ContainsKey('PromptTokens')) {
        (@($Parameters.PromptTokens) -join ',')
    } else {
        '512'
    }

    $n = if ($Parameters.ContainsKey('GenerationTokens')) {
        (@($Parameters.GenerationTokens) -join ',')
    } else {
        '128'
    }

    $d = if ($Parameters.ContainsKey('Depths')) {
        (@($Parameters.Depths) -join ',')
    } else {
        '0'
    }

    $r = if ($Parameters.ContainsKey('Repetitions')) {
        [string]$Parameters.Repetitions
    } else {
        '3'
    }

    return "p=$p n=$n d=$d r=$r"
}

function Get-Evox2ScriptParameterNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    if ($null -ne $parseErrors -and $parseErrors.Count -gt 0) {
        $details = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "Failed to parse benchmark script parameter block: $Path :: $details"
    }

    if ($null -eq $ast.ParamBlock) {
        throw "Benchmark script has no param block: $Path"
    }

    return @(
        $ast.ParamBlock.Parameters |
            ForEach-Object { $_.Name.VariablePath.UserPath } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )
}

function Assert-Evox2KnownParameters {
    param(
        [string]$ToolName,
        [hashtable]$Parameters,
        [string[]]$ValidParameterNames
    )

    $reserved = @(
        'LocalConfig',
        'BuildKey',
        'ModelKey',
        'LlamaCli',
        'LlamaBench',
        'ModelFile',
        'DryRun',
        'NoThrowOnFailure'
    )

    foreach ($key in $Parameters.Keys) {
        if ($reserved -contains [string]$key) {
            throw "Matrix plans must not set reserved parameter '$key'."
        }

        if ($ValidParameterNames -notcontains [string]$key) {
            throw "Unknown $ToolName parameter '$key' in matrix plan."
        }
    }
}

function ConvertTo-Evox2MatrixResultRow {
    param(
        [pscustomobject]$PlanRun,
        [object]$ChildRow
    )

    if ($PlanRun.Tool -eq 'cli') {
        return [PSCustomObject]@{
            MatrixRunId       = $PlanRun.MatrixRunId
            PlanRunKey        = $PlanRun.PlanRunKey
            Tool              = $PlanRun.Tool
            Job               = $PlanRun.Job
            Case              = $PlanRun.Case
            Variant           = $PlanRun.Variant
            BuildKey          = $PlanRun.BuildKey
            ModelKey          = $PlanRun.ModelKey

            ChildRunId        = $ChildRow.RunId
            ChildConditionId  = $ChildRow.ConditionId
            ChildStatus       = $ChildRow.Status
            Backend           = $ChildRow.Backend
            Build             = $ChildRow.Build
            ModelAlias        = $ChildRow.ModelAlias

            Context           = $ChildRow.ContextRequested
            InputFile         = $ChildRow.InputFile
            MTP               = $ChildRow.MTP
            PP                = $ChildRow.PP
            TG                = $ChildRow.TG
            DraftAcceptance   = $ChildRow.DraftAcceptance
            DenseIndexerEvidence = $ChildRow.DenseIndexerEvidence
            DenseIndexerOmitted  = $ChildRow.DenseIndexerOmitted
            QsaNoopEvidence      = $ChildRow.QsaNoopEvidence
            QsaNoopEnabled       = $ChildRow.QsaNoopEnabled

            BenchTest         = $null
            PromptTokens      = $ChildRow.PromptTokens
            GenerationTokens  = $ChildRow.GeneratedTokens
            OutputFingerprintSha256 = $ChildRow.OutputFingerprintSha256
            OutputFingerprintBytes  = $ChildRow.OutputFingerprintBytes
            OutputFingerprintStatus = $ChildRow.OutputFingerprintStatus
            Depth             = $null
            AvgTokensPerSec   = $null
            StdDevTokensPerSec = $null
            RepetitionSamples = $null

            ResourceSamples   = $ChildRow.ResourceSamples
            AdlxSamples       = $ChildRow.AdlxSamples
            PModeStart        = $ChildRow.PModeStart
            PModeFinish       = $ChildRow.PModeFinish
            PModeChanged      = $ChildRow.PModeChanged
            AdlxHighLoadPowerW = $ChildRow.AdlxHighLoadPowerW
            AdlxPowerClass    = $ChildRow.AdlxPowerClass
            PModeWarningCount = $ChildRow.PModeWarningCount
            ChildRunDirectory = $ChildRow.RunDirectory
            ResourceMonitorStatus = $ChildRow.ResourceMonitorStatus
            AdlxMonitorStatus = $ChildRow.AdlxMonitorStatus
            RamDetailStatus = $ChildRow.RamDetailStatus
            RamDetailIncreaseMiB = $ChildRow.RamDetailIncreaseMiB
            RamDetailSystemRecovery = $ChildRow.RamDetailSystemRecovery
            PlannedOrder = $PlanRun.PlannedOrder; ComparisonGroup = $PlanRun.ComparisonGroup
            BaseConfiguration = $PlanRun.BaseConfiguration; Configuration = $PlanRun.Configuration
            Round = $PlanRun.Round; RoundPosition = $PlanRun.RoundPosition
            ActualContext = $ChildRow.ActualContext; InputSha256 = $ChildRow.InputSha256; PromptSlice = $ChildRow.PromptSlice
            NativeSeconds = $null
            PromptSeconds = $(if ($null -ne $ChildRow.PromptMilliseconds) { $ChildRow.PromptMilliseconds / 1000 } else { $null })
            GenerationSeconds = $(if ($null -ne $ChildRow.GenerationMilliseconds) { $ChildRow.GenerationMilliseconds / 1000 } else { $null })
        }
    }

    return [PSCustomObject]@{
        MatrixRunId       = $PlanRun.MatrixRunId
        PlanRunKey        = $PlanRun.PlanRunKey
        Tool              = $PlanRun.Tool
        Job               = $PlanRun.Job
        Case              = $PlanRun.Case
        Variant           = $PlanRun.Variant
        BuildKey          = $PlanRun.BuildKey
        ModelKey          = $PlanRun.ModelKey

        ChildRunId        = $ChildRow.RunId
        ChildConditionId  = $ChildRow.ConditionId
        ChildStatus       = $ChildRow.Status
        Backend           = $ChildRow.BackendDetected
        Build             = $ChildRow.Build
        ModelAlias        = $ChildRow.ModelAlias

        Context           = $ChildRow.Context
        InputFile         = $ChildRow.InputFile
        MTP               = $false
        PP                = $null
        TG                = $null
        DraftAcceptance   = $null
        DenseIndexerEvidence = $null
        DenseIndexerOmitted  = $null
        QsaNoopEvidence      = $null
        QsaNoopEnabled       = $null

        BenchTest         = $ChildRow.Test
        PromptTokens      = $ChildRow.PromptTokens
        GenerationTokens  = $ChildRow.GenerationTokens
        OutputFingerprintSha256 = $null
        OutputFingerprintBytes  = $null
        OutputFingerprintStatus = $null
        Depth             = $ChildRow.Depth
        AvgTokensPerSec   = $ChildRow.AvgTokensPerSec
        StdDevTokensPerSec = $ChildRow.StdDevTokensPerSec
        RepetitionSamples = $ChildRow.RepetitionSamples

        ResourceSamples   = $ChildRow.ResourceSamples
        AdlxSamples       = $ChildRow.AdlxSamples
        PModeStart        = $ChildRow.PModeStart
        PModeFinish       = $ChildRow.PModeFinish
        PModeChanged      = $ChildRow.PModeChanged
        AdlxHighLoadPowerW = $ChildRow.AdlxHighLoadPowerW
        AdlxPowerClass    = $ChildRow.AdlxPowerClass
        PModeWarningCount = $ChildRow.PModeWarningCount
        ChildRunDirectory = $ChildRow.RunDirectory
        ResourceMonitorStatus = $ChildRow.ResourceMonitorStatus
        AdlxMonitorStatus = $ChildRow.AdlxMonitorStatus
        RamDetailStatus = $ChildRow.RamDetailStatus
        RamDetailIncreaseMiB = $ChildRow.RamDetailIncreaseMiB
        RamDetailSystemRecovery = $ChildRow.RamDetailSystemRecovery
        PlannedOrder = $PlanRun.PlannedOrder; ComparisonGroup = $PlanRun.ComparisonGroup
        BaseConfiguration = $PlanRun.BaseConfiguration; Configuration = $PlanRun.Configuration
        Round = $PlanRun.Round; RoundPosition = $PlanRun.RoundPosition
        ActualContext = $ChildRow.Context; InputSha256 = $ChildRow.InputSha256; PromptSlice = $ChildRow.PromptSlice
        NativeSeconds = $(if ($null -ne $ChildRow.AvgNanoseconds) { $ChildRow.AvgNanoseconds / 1e9 } else { $null })
        PromptSeconds = $null; GenerationSeconds = $null
    }
}

function Get-MatrixChildDetails {
    param([string]$Directory)

    if (!$Directory) { return }
    $path = Join-Path $Directory 'result.json'
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $result = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $nativeLoad = $null
    $gpuFailure = $false
    $contextSeconds = $null
    $warmupSeconds = $null
    if ($result.Files.StdErr -and (Test-Path -LiteralPath $result.Files.StdErr -PathType Leaf)) {
        foreach ($line in (Get-Content -LiteralPath $result.Files.StdErr)) {
            if ($line -match 'VK_ERROR_DEVICE_LOST|HIP_ERROR_LAUNCH_FAILURE|hipErrorLaunchFailure|out of memory|GGML_ASSERT.*failed') {
                $gpuFailure = $true
            }
            if ($null -eq $nativeLoad -and $line -match 'load time\s*=\s*([0-9.]+)\s*ms') {
                $nativeLoad = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) / 1000
            }
        }
    }
    if ($result.PhaseTracePath -and (Test-Path -LiteralPath $result.PhaseTracePath -PathType Leaf)) {
        $launch = $null
        foreach ($line in (Get-Content -LiteralPath $result.PhaseTracePath -Encoding UTF8)) {
            $event = $line | ConvertFrom-Json
            if ($event.Event -eq 'TargetLaunchRequested') { $launch = $event; continue }
            if (!$launch -or $event.Event -ne 'LogMarkerReceived') { continue }
            $duration = ([long]$event.StopwatchTicks - [long]$launch.StopwatchTicks) / [double]$event.StopwatchFrequency
            if ($null -eq $contextSeconds -and $event.Data.Phase -eq 'ContextInitialization') { $contextSeconds = $duration }
            if ($null -eq $warmupSeconds -and $event.Data.Phase -eq 'WarmupReported') { $warmupSeconds = $duration }
        }
    }
    [pscustomobject]@{
        Lifecycle = $result.TargetLifecycle; ResidualPids = @($result.TargetLifecycle.ResidualPids | Where-Object { $_ })
        ProcessSeconds = $result.TargetLifecycle.ProcessSeconds; WrapperSeconds = $result.DurationSeconds
        ModelLoadReportedSeconds = $nativeLoad; ContextMarkerFromLaunchSeconds = $contextSeconds
        WarmupMarkerFromLaunchSeconds = $warmupSeconds; GpuFailure = $gpuFailure
        PModeStart = $result.PModeAtStart.Mode; PModeFinish = $result.PModeAtFinish.Mode
        RamPeakUsedMiB = $result.RamDetail.PeakUsedMiB; RamPeakUtc = $result.RamDetail.PeakUtc
        RamMinimumAvailableBytes = $result.RamDetail.RunningMetrics.AvailableRAMBytes.Minimum
        GpuRecovery = $result.RamDetail.GpuRecovery.Status
    }
}

function Get-MatrixGateCheck {
    param([hashtable]$Policy, $Baseline, [string]$Phase)
    $check = [ordered]@{
        Phase=$Phase; TimestampUtc=[datetime]::UtcNow.ToString('o')
        AvailableGiB=$null; CommitGiB=$null; DedicatedGpuGiB=$null
        PMode=$null; ProcessIds=@(); Issue=$null
    }
    try {
        $memory = Get-Evox2SystemMemory
        $check.AvailableGiB = $memory.Available / 1GB
        $check.CommitGiB = $memory.Commit / 1GB
        $check.ProcessIds = @(Get-Process -Name 'llama-bench','llama-cli','llama-server','evox2-adlx-gpu-monitor','ninja','cmake','test-backend-ops' -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.ProcessName):$($_.Id)" })
        if ($check.ProcessIds.Count) { throw "Competing or residual process: $($check.ProcessIds -join ', ')." }
        if ($Policy.ContainsKey('MinimumAvailableGiB') -and $check.AvailableGiB -lt $Policy.MinimumAvailableGiB) {
            throw 'Available physical memory fell below the plan safety threshold.'
        }
        if ($Baseline -and $Policy.ContainsKey('MaxCommitGrowthGiB') -and
            $check.CommitGiB -gt $Baseline.CommitGiB + $Policy.MaxCommitGrowthGiB) {
            throw 'System commit did not return within the plan tolerance.'
        }
        if ($Policy.ContainsKey('MaxGpuGrowthGiB')) {
            $gpu = Get-Counter -Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop
            $values = @($gpu.CounterSamples | Where-Object { $_.Status -in 0,1 -and $_.CookedValue -ge 0 })
            if (!$values.Count) { throw 'No valid adapter dedicated memory sample at the safety gate.' }
            $check.DedicatedGpuGiB = ($values | Measure-Object CookedValue -Sum).Sum / 1GB
            if ($Baseline -and $check.DedicatedGpuGiB -gt $Baseline.DedicatedGpuGiB + $Policy.MaxGpuGrowthGiB) {
                throw 'Adapter dedicated memory did not return within the plan tolerance.'
            }
        }
        if ($Policy.PMode -and $Phase.StartsWith('before')) {
            $pMode = Get-Evox2PModeMetadata
            $check.PMode = $pMode.Mode
            if (!$pMode.ProbeSucceeded -or $pMode.Mode -ne $Policy.PMode) { throw "Required P-MODE '$($Policy.PMode)' could not be verified." }
        }
    } catch { $check.Issue = $_.Exception.Message }
    [pscustomobject]$check
}

if ($ResourceMonitor -and $NoResourceMonitor) {
    throw 'Do not specify -ResourceMonitor and -NoResourceMonitor together.'
}

$RepoRoot = Get-Evox2RepoRoot -StartPath $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($LocalConfig)) {
    $LocalConfig = Join-Path $benchmarkDir 'configs\local.psd1'
}
if (-not (Test-Path -LiteralPath $LocalConfig -PathType Leaf)) {
    throw "Local config not found: $LocalConfig"
}
$LocalConfig = (Resolve-Path -LiteralPath $LocalConfig).Path
$Local = Import-Evox2LocalConfig -Path $LocalConfig

if (-not (Test-Path -LiteralPath $Plan -PathType Leaf)) {
    throw "Matrix plan not found: $Plan"
}
$Plan = (Resolve-Path -LiteralPath $Plan).Path

$PlanData = Import-PowerShellDataFile -LiteralPath $Plan
if (-not ($PlanData -is [hashtable])) {
    throw 'Matrix plan must evaluate to a hashtable.'
}

if (-not $PlanData.ContainsKey('SchemaVersion') -or
    [int]$PlanData.SchemaVersion -ne 1) {
    throw 'Matrix plan SchemaVersion must be 1.'
}

$PlanName = if ($PlanData.ContainsKey('Name') -and
               -not [string]::IsNullOrWhiteSpace([string]$PlanData.Name)) {
    [string]$PlanData.Name
} else {
    [IO.Path]::GetFileNameWithoutExtension($Plan)
}

$Settings = Get-Evox2OptionalHashtable -Parent $PlanData -Key 'Settings'
$SafetyGate = Get-Evox2OptionalHashtable -Parent $Settings -Key 'SafetyGate'
if ($SafetyGate.Count -gt 0) { Import-Module (Join-Path $benchmarkDir 'Evox2.Memory.psm1') }
$Defaults = Get-Evox2OptionalHashtable -Parent $PlanData -Key 'Defaults'

$ContinueOnError = $true
if ($Settings.ContainsKey('ContinueOnError')) {
    $ContinueOnError = [bool]$Settings.ContinueOnError
}
if ($StopOnError) {
    $ContinueOnError = $false
}

$effectiveCooldown = 10
if ($Settings.ContainsKey('CooldownSeconds')) {
    $effectiveCooldown = [int]$Settings.CooldownSeconds
}
if ($CooldownSeconds -ge 0) {
    $effectiveCooldown = $CooldownSeconds
}
if ($effectiveCooldown -lt 0 -or $effectiveCooldown -gt 3600) {
    throw 'Effective CooldownSeconds must be between 0 and 3600.'
}

$DefaultCliParameters = Get-Evox2OptionalHashtable `
    -Parent $Defaults `
    -Key 'CliParameters'

$DefaultBenchParameters = Get-Evox2OptionalHashtable `
    -Parent $Defaults `
    -Key 'BenchParameters'

$DefaultEnvironment = Get-Evox2OptionalHashtable `
    -Parent $Defaults `
    -Key 'Environment'
Assert-Evox2Environment `
    -Environment $DefaultEnvironment `
    -Context 'Defaults.Environment'

$Jobs = Get-Evox2OptionalArray -Parent $PlanData -Key 'Jobs'
if ($Jobs.Count -eq 0) {
    throw 'Matrix plan contains no Jobs.'
}

# Do not use Get-Command ExternalScriptInfo.Parameters here. On Windows
# PowerShell 5.1 it can expose an incomplete parameter dictionary for scripts
# addressed by path (observed missing ExtraArgs and GpuLayers). Parse the
# script AST directly so matrix validation follows the actual param blocks.
$validCliParameters = @(Get-Evox2ScriptParameterNames -Path $measureCli)
$validBenchParameters = @(Get-Evox2ScriptParameterNames -Path $measureBench)

$expanded = @()
$seenPlanKeys = @{}
$matrixIndex = 0

foreach ($rawJob in $Jobs) {
    if (-not ($rawJob -is [hashtable])) {
        throw 'Each Jobs entry must be a hashtable.'
    }

    $job = [hashtable]$rawJob

    $enabled = $true
    if ($job.ContainsKey('Enabled')) {
        $enabled = [bool]$job.Enabled
    }
    if (-not $enabled) {
        continue
    }

    if (-not $job.ContainsKey('Name') -or
        [string]::IsNullOrWhiteSpace([string]$job.Name)) {
        throw 'Every enabled job requires a non-empty Name.'
    }
    $jobName = [string]$job.Name

    if (-not (Test-Evox2NameFilter -Value $jobName -Filter $OnlyJob)) {
        continue
    }

    if (-not $job.ContainsKey('Tool')) {
        throw "Job '$jobName' requires Tool = 'cli' or 'bench'."
    }

    $toolName = ([string]$job.Tool).ToLowerInvariant()
    if ($toolName -notin @('cli', 'bench')) {
        throw "Job '$jobName' has unsupported Tool '$($job.Tool)'."
    }
    if ($Tool -ne 'all' -and $Tool -ne $toolName) {
        continue
    }

    $buildKeys = Get-Evox2OptionalArray -Parent $job -Key 'BuildKeys'
    $modelKeys = Get-Evox2OptionalArray -Parent $job -Key 'ModelKeys'
    if ($buildKeys.Count -eq 0) {
        throw "Job '$jobName' has no BuildKeys."
    }
    if ($modelKeys.Count -eq 0) {
        throw "Job '$jobName' has no ModelKeys."
    }

    $jobParameters = Get-Evox2OptionalHashtable -Parent $job -Key 'Parameters'
    $jobEnvironment = Get-Evox2OptionalHashtable -Parent $job -Key 'Environment'
    Assert-Evox2Environment `
        -Environment $jobEnvironment `
        -Context "job '$jobName' Environment"

    $cases = Get-Evox2OptionalArray -Parent $job -Key 'Cases'
    if ($cases.Count -eq 0) {
        $cases = @(
            @{
                Name = 'default'
                Parameters = @{}
            }
        )
    }

    $variants = Get-Evox2OptionalArray -Parent $job -Key 'Variants'
    if ($variants.Count -eq 0) {
        $variants = @(
            @{
                Name = 'default'
                Parameters = @{}
            }
        )
    }

    $comparison = Get-Evox2OptionalHashtable -Parent $job -Key 'Comparison'
    $jobComparisonRows = @()
    $schedule = @()
    if ($comparison.Count -gt 0) {
        $names = @(foreach ($key in $buildKeys) {
            foreach ($item in $variants) {
                if ($item -isnot [hashtable]) { throw 'Each comparison variant requires a hashtable.' }
                $name = if ($item.Name) { [string]$item.Name } else { 'default' }
                if ($buildKeys.Count -gt 1) { "$key/$name" } else { $name }
            }
        })
        $schedule = @(Get-Evox2MatrixRoundSchedule $comparison $names $jobName)
    }
    foreach ($rawCase in $cases) {
        if (-not ($rawCase -is [hashtable])) {
            throw "Job '$jobName' contains a Case that is not a hashtable."
        }
        $case = [hashtable]$rawCase

        $caseName = if ($case.ContainsKey('Name') -and
                       -not [string]::IsNullOrWhiteSpace([string]$case.Name)) {
            [string]$case.Name
        } else {
            'default'
        }

        if (-not (Test-Evox2NameFilter -Value $caseName -Filter $OnlyCase)) {
            continue
        }

        $caseParameters = Get-Evox2OptionalHashtable -Parent $case -Key 'Parameters'
        $caseEnvironment = Get-Evox2OptionalHashtable -Parent $case -Key 'Environment'
        Assert-Evox2Environment `
            -Environment $caseEnvironment `
            -Context "case '$jobName/$caseName' Environment"

        foreach ($buildKeyValue in $buildKeys) {
            $buildKey = [string]$buildKeyValue

            if (-not (Test-Evox2NameFilter -Value $buildKey -Filter $OnlyBuild)) {
                continue
            }

            [void](Get-Evox2ConfigEntry -Config $Local -Section Builds -Key $buildKey)

            foreach ($modelKeyValue in $modelKeys) {
                $modelKey = [string]$modelKeyValue
                [void](Get-Evox2ConfigEntry -Config $Local -Section Models -Key $modelKey)

                foreach ($rawVariant in $variants) {
                    if (-not ($rawVariant -is [hashtable])) {
                        throw "Job '$jobName' contains a Variant that is not a hashtable."
                    }
                    $variant = [hashtable]$rawVariant

                    $variantName = if ($variant.ContainsKey('Name') -and
                                      -not [string]::IsNullOrWhiteSpace([string]$variant.Name)) {
                        [string]$variant.Name
                    } else {
                        'default'
                    }

                    if (-not (Test-Evox2NameFilter -Value $variantName -Filter $OnlyVariant)) {
                        continue
                    }

                    $variantParameters = Get-Evox2OptionalHashtable `
                        -Parent $variant `
                        -Key 'Parameters'

                    $variantEnvironment = Get-Evox2OptionalHashtable `
                        -Parent $variant `
                        -Key 'Environment'
                    Assert-Evox2Environment `
                        -Environment $variantEnvironment `
                        -Context "variant '$jobName/$caseName/$variantName' Environment"

                    $effectiveEnvironment = Merge-Evox2Hashtable -Tables @(
                        $DefaultEnvironment,
                        $jobEnvironment,
                        $caseEnvironment,
                        $variantEnvironment
                    )

                    $baseDefaults = if ($toolName -eq 'cli') {
                        $DefaultCliParameters
                    } else {
                        $DefaultBenchParameters
                    }

                    $effectiveParameters = Merge-Evox2Hashtable -Tables @(
                        $baseDefaults,
                        $jobParameters,
                        $caseParameters,
                        $variantParameters
                    )

                    if ($ResourceMonitor) {
                        $effectiveParameters['ResourceMonitor'] = $true
                    } elseif ($NoResourceMonitor) {
                        $effectiveParameters['ResourceMonitor'] = $false
                    }

                    if ($toolName -eq 'cli') {
                        Assert-Evox2KnownParameters `
                            -ToolName 'llama-cli' `
                            -Parameters $effectiveParameters `
                            -ValidParameterNames $validCliParameters

                        $allocationOnly = (
                            $effectiveParameters.ContainsKey('AllocationOnly') -and
                            [bool]$effectiveParameters.AllocationOnly
                        )

                        if (-not $allocationOnly) {
                            $hasInputKey = (
                                $effectiveParameters.ContainsKey('InputKey') -and
                                -not [string]::IsNullOrWhiteSpace(
                                    [string]$effectiveParameters.InputKey
                                )
                            )
                            $hasInputFile = (
                                $effectiveParameters.ContainsKey('InputFile') -and
                                -not [string]::IsNullOrWhiteSpace(
                                    [string]$effectiveParameters.InputFile
                                )
                            )

                            if (-not $hasInputKey -and -not $hasInputFile) {
                                throw "CLI run '$jobName/$caseName/$variantName' requires InputKey/InputFile or AllocationOnly."
                            }

                            if ($hasInputKey) {
                                [void](Get-Evox2ConfigEntry `
                                    -Config $Local `
                                    -Section Inputs `
                                    -Key ([string]$effectiveParameters.InputKey))
                            }
                        }

                        $mtp = (
                            $effectiveParameters.ContainsKey('Mtp') -and
                            [bool]$effectiveParameters.Mtp
                        )

                        if ($mtp) {
                            $hasDraftKey = (
                                $effectiveParameters.ContainsKey('DraftModelKey') -and
                                -not [string]::IsNullOrWhiteSpace(
                                    [string]$effectiveParameters.DraftModelKey
                                )
                            )
                            $hasDraftPath = (
                                $effectiveParameters.ContainsKey('DraftModel') -and
                                -not [string]::IsNullOrWhiteSpace(
                                    [string]$effectiveParameters.DraftModel
                                )
                            )

                            if (-not $hasDraftKey -and -not $hasDraftPath) {
                                throw "MTP run '$jobName/$caseName/$variantName' requires DraftModelKey or DraftModel."
                            }

                            if ($hasDraftKey) {
                                [void](Get-Evox2ConfigEntry `
                                    -Config $Local `
                                    -Section Models `
                                    -Key ([string]$effectiveParameters.DraftModelKey))
                            }
                        }
                    } else {
                        Assert-Evox2KnownParameters `
                            -ToolName 'llama-bench' `
                            -Parameters $effectiveParameters `
                            -ValidParameterNames $validBenchParameters

                        if ($effectiveParameters.ContainsKey('InputKey') -and
                            -not [string]::IsNullOrWhiteSpace([string]$effectiveParameters.InputKey)) {
                            [void](Get-Evox2ConfigEntry `
                                -Config $Local `
                                -Section Inputs `
                                -Key ([string]$effectiveParameters.InputKey))
                        }
                    }

                    $planKeyData = [ordered]@{
                        Tool        = $toolName
                        BuildKey    = $buildKey
                        ModelKey    = $modelKey
                        Parameters  = $effectiveParameters
                        Environment = $effectiveEnvironment
                    }
                    $planRunKey = Get-Evox2ConditionId `
                        -Condition $planKeyData `
                        -Length 12

                    if ($seenPlanKeys.ContainsKey($planRunKey)) {
                        throw (
                            "Duplicate expanded matrix run detected: " +
                            "'$jobName/$caseName/$variantName' duplicates " +
                            "'$($seenPlanKeys[$planRunKey])'."
                        )
                    }

                    $displayName = "$jobName/$caseName/$buildKey/$modelKey/$variantName"
                    $seenPlanKeys[$planRunKey] = $displayName

                    $template = [PSCustomObject]@{
                        MatrixRunId = $null
                        PlanRunKey  = $planRunKey
                        Tool        = $toolName
                        Job         = $jobName
                        Case        = $caseName
                        Variant     = $variantName
                        BuildKey    = $buildKey
                        ModelKey    = $modelKey
                        Workload    = Get-Evox2MatrixWorkloadLabel `
                            -ToolName $toolName `
                            -Parameters $effectiveParameters
                        EnvironmentSummary = ConvertTo-Evox2EnvironmentSummary `
                            -Environment $effectiveEnvironment
                        Parameters  = $effectiveParameters
                        Environment = $effectiveEnvironment
                        ComparisonGroup = $null; BaseConfiguration = $null; Configuration = $null
                        References = @(); Round = $null; RoundPosition = $null; PlannedOrder = $null
                    }
                    if ($comparison.Count -gt 0) {
                        $template.ComparisonGroup = [string]$comparison.Group
                        $template.BaseConfiguration = [string]$comparison.Base
                        $template.Configuration = if ($buildKeys.Count -gt 1) { "$buildKey/$variantName" } else { $variantName }
                        $template.References = @($comparison.References | Where-Object { $_ })
                        $jobComparisonRows += $template
                    } else { $expanded += $template }
                }
            }
        }
    }
    if ($comparison.Count -gt 0) {
        foreach ($group in ($jobComparisonRows | Group-Object Case, ModelKey)) {
            $byConfig = @{}
            foreach ($template in $group.Group) {
                if ($byConfig.ContainsKey($template.Configuration)) { throw "Duplicate comparison configuration: $($template.Configuration)" }
                $byConfig[$template.Configuration] = $template
            }
            foreach ($round in $schedule) {
                for ($j = 0; $j -lt $round.Order.Count; $j++) {
                    $configuration = $round.Order[$j]
                    if (!$byConfig.ContainsKey($configuration)) { continue }
                    $entry = $byConfig[$configuration].PSObject.Copy()
                    $entry.Round = $round.Round
                    $entry.RoundPosition = $j + 1
                    $expanded += $entry
                    if ($expanded.Count -gt $MaxRuns) { throw "Matrix exceeds MaxRuns=$MaxRuns." }
                }
            }
        }
    }
}

foreach ($item in $expanded) {
    $matrixIndex++
    $item.MatrixRunId = 'M{0:D3}' -f $matrixIndex
    $item.PlannedOrder = $matrixIndex
}

if ($expanded.Count -eq 0) {
    throw 'The selected matrix expands to zero runs.'
}

if ($expanded.Count -gt $MaxRuns) {
    throw (
        "Matrix expands to $($expanded.Count) runs, exceeding MaxRuns=$MaxRuns. " +
        'Narrow the filters or explicitly raise -MaxRuns.'
    )
}

$LogRoot = Join-Path $RepoRoot 'evox2-logs'
if ($Local.ContainsKey('LogRoot') -and
    -not [string]::IsNullOrWhiteSpace([string]$Local.LogRoot)) {
    $LogRoot = [string]$Local.LogRoot
}

Write-Host ''
Write-Host '================ Expanded benchmark matrix ================'
Write-Host "Plan             : $PlanName"
Write-Host "Selected tool    : $Tool"
Write-Host "Runs             : $($expanded.Count)"
Write-Host "CooldownSeconds  : $effectiveCooldown"
Write-Host "ContinueOnError  : $ContinueOnError"
Write-Host "LogRoot          : $LogRoot"
Write-Host ''

$hasComparison = @($expanded | Where-Object ComparisonGroup).Count -gt 0
if ($hasComparison) {
    foreach ($item in $expanded) {
        Write-Host ("{0} {1} group={2} round={3} slot={4} configuration={5} base={6} {7}/{8}/{9}/{10}/{11} {12}" -f
            $item.PlannedOrder, $item.MatrixRunId, $item.ComparisonGroup, $item.Round, $item.RoundPosition,
            $item.Configuration, $item.BaseConfiguration, $item.Job, $item.Case, $item.BuildKey,
            $item.ModelKey, $item.Variant, $item.Workload)
    }
} else {
    $expanded | Select-Object MatrixRunId, Tool, Job, Case, Variant, BuildKey, ModelKey, Workload, EnvironmentSummary |
        Format-Table -AutoSize | Out-Host
}

Write-Host '==========================================================='
Write-Host ''

if ($PlanOnly) {
    Write-Host 'PlanOnly: no benchmark processes were started.'
    return
}

$matrixRoot = Join-Path $LogRoot 'matrix'
New-Item -ItemType Directory -Force -Path $matrixRoot | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$safePlanName = ConvertTo-Evox2SafeName -Value $PlanName -MaxLength 60
$batchId = "$stamp-$safePlanName"
$batchDir = Join-Path $matrixRoot $batchId
New-Item -ItemType Directory -Force -Path $batchDir | Out-Null

$planJsonPath = Join-Path $batchDir 'matrix-plan.json'
$runsCsvPath = Join-Path $batchDir 'matrix-runs.csv'
$resultsCsvPath = Join-Path $batchDir 'matrix-results.csv'
$resultJsonPath = Join-Path $batchDir 'matrix-result.json'

$planIdentity = Get-Evox2FileIdentity -Path $Plan -Sha256
$localIdentity = Get-Evox2FileIdentity -Path $LocalConfig -Sha256
$gitIdentity = $null
try {
    $gitIdentity = Get-Evox2GitMetadata -RepoRoot $RepoRoot
} catch {}

$expandedForJson = @()
foreach ($item in $expanded) {
    $expandedForJson += [ordered]@{
        MatrixRunId = $item.MatrixRunId
        PlanRunKey  = $item.PlanRunKey
        Tool        = $item.Tool
        Job         = $item.Job
        Case        = $item.Case
        Variant     = $item.Variant
        BuildKey    = $item.BuildKey
        ModelKey    = $item.ModelKey
        Workload    = $item.Workload
        EnvironmentSummary = $item.EnvironmentSummary
        Parameters  = $item.Parameters
        Environment = $item.Environment
        PlannedOrder = $item.PlannedOrder; ComparisonGroup = $item.ComparisonGroup
        BaseConfiguration = $item.BaseConfiguration; Configuration = $item.Configuration
        Round = $item.Round; RoundPosition = $item.RoundPosition
    }
}

$batchStarted = Get-Date

$planRecord = [ordered]@{
    SchemaVersion = 1
    BatchId       = $batchId
    PlanName      = $PlanName
    StartedAt     = $batchStarted.ToString('o')

    PlanIdentity = $planIdentity
    LocalConfigIdentity = [ordered]@{
        Path             = $localIdentity.Path
        LengthBytes      = $localIdentity.LengthBytes
        LastWriteTimeUtc = $localIdentity.LastWriteTimeUtc
        Sha256           = $localIdentity.Sha256
    }

    GitIdentity = $gitIdentity

    Selection = [ordered]@{
        Tool        = $Tool
        OnlyJob     = @($OnlyJob)
        OnlyCase    = @($OnlyCase)
        OnlyVariant = @($OnlyVariant)
        OnlyBuild   = @($OnlyBuild)
    }

    RunnerSettings = [ordered]@{
        CooldownSeconds = $effectiveCooldown
        ContinueOnError = $ContinueOnError
        ForceResourceMonitorOn  = [bool]$ResourceMonitor
        ForceResourceMonitorOff = [bool]$NoResourceMonitor
        MaxRuns = $MaxRuns
        SafetyGate = $SafetyGate
    }

    Runs = $expandedForJson
}

Write-Evox2Json -InputObject $planRecord -Path $planJsonPath -Depth 32

$runRecords = @()
$resultRows = @()
$stoppedEarly = $false
$gateChecks = @()
$gateBaseline = $null

Write-Host "Matrix batch directory: $batchDir"
Write-Host ''

for ($i = 0; $i -lt $expanded.Count; $i++) {
    $planRun = $expanded[$i]
    if ($SafetyGate.Count -gt 0) {
        $check = Get-MatrixGateCheck $SafetyGate $gateBaseline "before $($planRun.MatrixRunId)"
        if (!$gateBaseline) { $gateBaseline = $check }
        $gateChecks += $check
        Write-Evox2Json -InputObject @($gateChecks) -Path (Join-Path $batchDir 'matrix-safety-checks.json')
        if ($check.Issue) { Write-Warning $check.Issue; $stoppedEarly = $true; break }
    }
    $runStart = Get-Date

    Write-Host ''
    Write-Host '============================================================'
    Write-Host (
        'MATRIX START {0}/{1}: {2}  {3}/{4}/{5}' -f
        ($i + 1),
        $expanded.Count,
        $planRun.MatrixRunId,
        $planRun.Job,
        $planRun.Case,
        $planRun.Variant
    )
    Write-Host "Tool      : $($planRun.Tool)"
    Write-Host "BuildKey  : $($planRun.BuildKey)"
    Write-Host "ModelKey  : $($planRun.ModelKey)"
    Write-Host "Workload  : $($planRun.Workload)"
    if (-not [string]::IsNullOrWhiteSpace($planRun.EnvironmentSummary)) {
        Write-Host "Environment: $($planRun.EnvironmentSummary)"
    }
    Write-Host '============================================================'
    Write-Host ''

    $invokeParams = Copy-Evox2Hashtable -Source $planRun.Parameters
    $invokeParams['LocalConfig'] = $LocalConfig
    $invokeParams['BuildKey'] = $planRun.BuildKey
    $invokeParams['ModelKey'] = $planRun.ModelKey
    $invokeParams['NoThrowOnFailure'] = $true

    $childRows = @()
    $matrixStatus = 'EXCEPTION'
    $errorText = $null
    $childRunId = $null
    $childConditionId = $null
    $childRunDirectory = $null

    $extra = $null
    $savedRunEnvironment = @{}
    try {
        foreach ($name in $planRun.Environment.Keys) {
            $existing = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            $savedRunEnvironment[$name] = [ordered]@{
                Exists = ($null -ne $existing)
                Value = if ($null -ne $existing) { $existing.Value } else { $null }
            }

            $newValue = $planRun.Environment[$name]
            if ($null -eq $newValue) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            } else {
                Set-Item -LiteralPath "Env:$name" -Value ([string]$newValue)
            }
        }

        if ($planRun.Tool -eq 'cli') {
            $childRows = @(& $measureCli @invokeParams)
        } else {
            $childRows = @(& $measureBench @invokeParams)
        }

        if ($childRows.Count -eq 0) {
            $matrixStatus = 'NO_RESULT'
        } else {
            $nonOk = @(
                $childRows |
                Where-Object {
                    $null -ne $_.Status -and [string]$_.Status -ne 'OK'
                }
            )

            if ($nonOk.Count -gt 0) {
                $matrixStatus = [string]$nonOk[0].Status
            } else {
                $matrixStatus = 'OK'
            }

            $childRunId = $childRows[0].RunId
            $childConditionId = $childRows[0].ConditionId
            $childRunDirectory = $childRows[0].RunDirectory

            if ($hasComparison -or $SafetyGate.Count -gt 0) {
                $extra = Get-MatrixChildDetails $childRunDirectory
            }
            foreach ($childRow in $childRows) {
                $row = ConvertTo-Evox2MatrixResultRow -PlanRun $planRun -ChildRow $childRow
                $resultRows += $row
            }
        }
    } catch {
        $errorText = $_.Exception.ToString()
        $matrixStatus = 'EXCEPTION'
        Write-Warning (
            "Matrix run $($planRun.MatrixRunId) failed with an exception: " +
            $_.Exception.Message
        )
    } finally {
        foreach ($name in $savedRunEnvironment.Keys) {
            $saved = $savedRunEnvironment[$name]
            if ($saved.Exists) {
                Set-Item -LiteralPath "Env:$name" -Value $saved.Value
            } else {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            }
        }
    }

    if ($SafetyGate.Count -gt 0 -and $matrixStatus -eq 'OK') {
        if (!$extra -or !$extra.Lifecycle -or $extra.ResidualPids.Count -gt 0 -or
            $extra.GpuFailure -or ($SafetyGate.PMode -and ($extra.PModeStart -ne $SafetyGate.PMode -or $extra.PModeFinish -ne $SafetyGate.PMode))) {
            $matrixStatus = 'SAFETY_STOP'
            $errorText = 'Missing lifecycle evidence, residual process, GPU error or P-MODE mismatch. Inspect child result and stderr.'
        }
    }
    $runEnd = Get-Date

    $runRecords += [PSCustomObject]@{
        MatrixRunId      = $planRun.MatrixRunId
        PlanRunKey       = $planRun.PlanRunKey
        MatrixStatus     = $matrixStatus
        Tool             = $planRun.Tool
        Job              = $planRun.Job
        Case             = $planRun.Case
        Variant          = $planRun.Variant
        BuildKey         = $planRun.BuildKey
        ModelKey         = $planRun.ModelKey
        Workload         = $planRun.Workload
        Environment      = $planRun.EnvironmentSummary
        StartTime        = $runStart.ToString('o')
        EndTime          = $runEnd.ToString('o')
        DurationMinutes  = [math]::Round(
            ($runEnd - $runStart).TotalMinutes,
            3
        )
        ChildRunId       = $childRunId
        ChildConditionId = $childConditionId
        ChildRunDirectory = $childRunDirectory
        Error            = $errorText
        ResourceMonitorStatus = $(if ($childRows.Count) { $childRows[0].ResourceMonitorStatus } else { $null })
        AdlxMonitorStatus     = $(if ($childRows.Count) { $childRows[0].AdlxMonitorStatus } else { $null })
        ResourceSamples      = $(if ($childRows.Count) { $childRows[0].ResourceSamples } else { $null })
        AdlxSamples          = $(if ($childRows.Count) { $childRows[0].AdlxSamples } else { $null })
        RamDetailStatus       = $(if ($childRows.Count) { $childRows[0].RamDetailStatus } else { $null })
        RamDetailIncreaseMiB  = $(if ($childRows.Count) { $childRows[0].RamDetailIncreaseMiB } else { $null })
        RamDetailSystemRecovery = $(if ($childRows.Count) { $childRows[0].RamDetailSystemRecovery } else { $null })
        PlannedOrder = $planRun.PlannedOrder; ActualOrder = $runRecords.Count + 1
        ComparisonGroup = $planRun.ComparisonGroup; BaseConfiguration = $planRun.BaseConfiguration
        Configuration = $planRun.Configuration; Round = $planRun.Round; RoundPosition = $planRun.RoundPosition
        ProcessSeconds = $extra.ProcessSeconds; WrapperSeconds = $extra.WrapperSeconds
        ModelLoadReportedSeconds = $extra.ModelLoadReportedSeconds
        ContextMarkerFromLaunchSeconds = $extra.ContextMarkerFromLaunchSeconds
        WarmupMarkerFromLaunchSeconds = $extra.WarmupMarkerFromLaunchSeconds
        RamPeakUsedMiB = $extra.RamPeakUsedMiB; RamPeakUtc = $extra.RamPeakUtc
        RamMinimumAvailableBytes = $extra.RamMinimumAvailableBytes; GpuRecovery = $extra.GpuRecovery
    }

    $runRecords | Export-Csv `
        -LiteralPath $runsCsvPath `
        -NoTypeInformation `
        -Encoding UTF8

    if ($resultRows.Count -gt 0) {
        $resultRows | Export-Csv `
            -LiteralPath $resultsCsvPath `
            -NoTypeInformation `
            -Encoding UTF8
    }

    $partialResult = [ordered]@{
        SchemaVersion = 1
        BatchId       = $batchId
        PlanName      = $PlanName
        StartedAt     = $batchStarted.ToString('o')
        LastUpdatedAt = (Get-Date).ToString('o')
        Complete      = $false
        StoppedEarly  = $false
        RunCountPlanned = $expanded.Count
        RunCountFinished = $runRecords.Count
        Runs          = @($runRecords)
        Results       = @($resultRows)
    }
    Write-Evox2Json -InputObject $partialResult -Path $resultJsonPath -Depth 32

    Write-Host ''
    Write-Host (
        'MATRIX END {0}: {1} ({2:N2} min)' -f
        $planRun.MatrixRunId,
        $matrixStatus,
        ($runEnd - $runStart).TotalMinutes
    )

    if ($matrixStatus -eq 'SAFETY_STOP' -or ($matrixStatus -ne 'OK' -and -not $ContinueOnError)) {
        Write-Warning 'Stopping matrix because ContinueOnError is false.'
        $stoppedEarly = $true
        break
    }

    $isLastPlannedRun = ($i -ge ($expanded.Count - 1))
    if ((-not $isLastPlannedRun -or $SafetyGate.Count -gt 0) -and $effectiveCooldown -gt 0) {
        Write-Host "Cooling down for $effectiveCooldown seconds..."
        Start-Sleep -Seconds $effectiveCooldown
    }
    if ($SafetyGate.Count -gt 0) {
        $check = Get-MatrixGateCheck $SafetyGate $gateBaseline "after $($planRun.MatrixRunId)"
        $gateChecks += $check
        Write-Evox2Json -InputObject @($gateChecks) -Path (Join-Path $batchDir 'matrix-safety-checks.json')
        if ($check.Issue) { Write-Warning $check.Issue; $stoppedEarly = $true; break }
    }
}

$comparisonFiles = $null
if ($hasComparison) {
    $comparisonResult = Get-Evox2MatrixComparison $expanded $runRecords $resultRows
    $comparisonFiles = [ordered]@{ Rounds = $null; Summary = $null }
    if ($comparisonResult.Rounds.Count) {
        $comparisonFiles.Rounds = Join-Path $batchDir 'matrix-comparison-rounds.csv'
        $comparisonResult.Rounds | Export-Csv -LiteralPath $comparisonFiles.Rounds -Encoding UTF8 -NoTypeInformation
        $comparisonFiles.Summary = Join-Path $batchDir 'matrix-comparison-summary.csv'
        $comparisonResult.Summary | Export-Csv -LiteralPath $comparisonFiles.Summary -Encoding UTF8 -NoTypeInformation
    }
}
$batchFinished = Get-Date

$finalResult = [ordered]@{
    SchemaVersion = 1
    BatchId       = $batchId
    PlanName      = $PlanName
    StartedAt     = $batchStarted.ToString('o')
    FinishedAt    = $batchFinished.ToString('o')
    DurationMinutes = [math]::Round(
        ($batchFinished - $batchStarted).TotalMinutes,
        3
    )
    Complete      = (-not $stoppedEarly -and
                     $runRecords.Count -eq $expanded.Count)
    StoppedEarly  = $stoppedEarly
    RunCountPlanned = $expanded.Count
    RunCountFinished = $runRecords.Count

    StatusCounts = [ordered]@{
        OK = @($runRecords | Where-Object { $_.MatrixStatus -eq 'OK' }).Count
        NonOK = @($runRecords | Where-Object { $_.MatrixStatus -ne 'OK' }).Count
    }

    Files = [ordered]@{
        Plan    = $planJsonPath
        Runs    = $runsCsvPath
        Results = if (Test-Path -LiteralPath $resultsCsvPath) {
            $resultsCsvPath
        } else {
            $null
        }
    }

    ComparisonFiles = $comparisonFiles
    SafetyChecks = @($gateChecks)
    Runs    = @($runRecords)
    Results = @($resultRows)
}

Write-Evox2Json -InputObject $finalResult -Path $resultJsonPath -Depth 32

Write-Host ''
Write-Host '================ Matrix complete ================'
Write-Host "BatchId          : $batchId"
Write-Host "Plan             : $PlanName"
Write-Host "Finished runs    : $($runRecords.Count) / $($expanded.Count)"
Write-Host "OK               : $($finalResult.StatusCounts.OK)"
Write-Host "Non-OK           : $($finalResult.StatusCounts.NonOK)"
Write-Host "StoppedEarly     : $stoppedEarly"
Write-Host "Batch directory  : $batchDir"
Write-Host "matrix-plan.json : $planJsonPath"
Write-Host "matrix-runs.csv  : $runsCsvPath"
if (Test-Path -LiteralPath $resultsCsvPath) {
    Write-Host "matrix-results.csv: $resultsCsvPath"
}
Write-Host "matrix-result.json: $resultJsonPath"
Write-Host '================================================='
Write-Host ''

$runRecords |
    Format-Table MatrixRunId, MatrixStatus, Tool, Job, Case, Variant, BuildKey, DurationMinutes -AutoSize |
    Out-Host

if ($finalResult.StatusCounts.NonOK -gt 0) {
    Write-Warning (
        "$($finalResult.StatusCounts.NonOK) matrix run(s) did not finish with status OK."
    )
}
