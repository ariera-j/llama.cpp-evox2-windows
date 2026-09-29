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

        $input = if ($Parameters.ContainsKey('AllocationOnly') -and
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

        return "ctx=$context input=$input $mtp"
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

            BenchTest         = $null
            PromptTokens      = $ChildRow.PromptTokens
            GenerationTokens  = $ChildRow.GeneratedTokens
            Depth             = $null
            AvgTokensPerSec   = $null
            StdDevTokensPerSec = $null
            RepetitionSamples = $null

            ResourceSamples   = $ChildRow.ResourceSamples
            ChildRunDirectory = $ChildRow.RunDirectory
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

        Context           = $null
        InputFile         = $null
        MTP               = $false
        PP                = $null
        TG                = $null
        DraftAcceptance   = $null

        BenchTest         = $ChildRow.Test
        PromptTokens      = $ChildRow.PromptTokens
        GenerationTokens  = $ChildRow.GenerationTokens
        Depth             = $ChildRow.Depth
        AvgTokensPerSec   = $ChildRow.AvgTokensPerSec
        StdDevTokensPerSec = $ChildRow.StdDevTokensPerSec
        RepetitionSamples = $ChildRow.RepetitionSamples

        ResourceSamples   = $ChildRow.ResourceSamples
        ChildRunDirectory = $ChildRow.RunDirectory
    }
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

$Jobs = Get-Evox2OptionalArray -Parent $PlanData -Key 'Jobs'
if ($Jobs.Count -eq 0) {
    throw 'Matrix plan contains no Jobs.'
}

$cliCommand = Get-Command -Name $measureCli
$benchCommand = Get-Command -Name $measureBench
$validCliParameters = @($cliCommand.Parameters.Keys)
$validBenchParameters = @($benchCommand.Parameters.Keys)

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
                    }

                    $planKeyData = [ordered]@{
                        Tool       = $toolName
                        BuildKey   = $buildKey
                        ModelKey   = $modelKey
                        Parameters = $effectiveParameters
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

                    $matrixIndex++
                    $matrixRunId = 'M{0:D3}' -f $matrixIndex

                    $expanded += [PSCustomObject]@{
                        MatrixRunId = $matrixRunId
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
                        Parameters  = $effectiveParameters
                    }
                }
            }
        }
    }
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

Write-Host ''
Write-Host '================ Expanded benchmark matrix ================'
Write-Host "Plan             : $PlanName"
Write-Host "Selected tool    : $Tool"
Write-Host "Runs             : $($expanded.Count)"
Write-Host "CooldownSeconds  : $effectiveCooldown"
Write-Host "ContinueOnError  : $ContinueOnError"
Write-Host ''

$expanded |
    Select-Object MatrixRunId, Tool, Job, Case, Variant, BuildKey, ModelKey, Workload |
    Format-Table -AutoSize |
    Out-Host

Write-Host '==========================================================='
Write-Host ''

if ($PlanOnly) {
    Write-Host 'PlanOnly: no benchmark processes were started.'
    return
}

$LogRoot = Join-Path $RepoRoot 'evox2-logs'
if ($Local.ContainsKey('LogRoot') -and
    -not [string]::IsNullOrWhiteSpace([string]$Local.LogRoot)) {
    $LogRoot = [string]$Local.LogRoot
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
        Parameters  = $item.Parameters
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
    }

    Runs = $expandedForJson
}

Write-Evox2Json -InputObject $planRecord -Path $planJsonPath -Depth 32

$runRecords = @()
$resultRows = @()
$stoppedEarly = $false

Write-Host "Matrix batch directory: $batchDir"
Write-Host ''

for ($i = 0; $i -lt $expanded.Count; $i++) {
    $planRun = $expanded[$i]
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

    try {
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

            foreach ($childRow in $childRows) {
                $resultRows += ConvertTo-Evox2MatrixResultRow `
                    -PlanRun $planRun `
                    -ChildRow $childRow
            }
        }
    } catch {
        $errorText = $_.Exception.ToString()
        $matrixStatus = 'EXCEPTION'
        Write-Warning (
            "Matrix run $($planRun.MatrixRunId) failed with an exception: " +
            $_.Exception.Message
        )
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

    if ($matrixStatus -ne 'OK' -and -not $ContinueOnError) {
        Write-Warning 'Stopping matrix because ContinueOnError is false.'
        $stoppedEarly = $true
        break
    }

    $isLastPlannedRun = ($i -ge ($expanded.Count - 1))
    if (-not $isLastPlannedRun -and $effectiveCooldown -gt 0) {
        Write-Host "Cooling down for $effectiveCooldown seconds..."
        Start-Sleep -Seconds $effectiveCooldown
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
