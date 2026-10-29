#requires -Version 5.1

Set-StrictMode -Version Latest

function Import-Evox2LocalConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$Required
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        if ($Required) {
            throw "Local configuration file not found: $fullPath"
        }
        return @{}
    }

    $config = Import-PowerShellDataFile -LiteralPath $fullPath
    if ($null -eq $config) {
        return @{}
    }

    return $config
}

function Get-Evox2RelevantEnvironment {
    [CmdletBinding()]
    param()

    $result = [ordered]@{}
    $pattern = '^(GGML_|LLAMA_|HIP_|ROCM_|HSA_|ROCBLAS_|VULKAN_|AMD_)'

    foreach ($item in @(Get-ChildItem Env: | Where-Object { $_.Name -match $pattern } | Sort-Object Name)) {
        $result[$item.Name] = $item.Value
    }

    return $result
}

function ConvertTo-Evox2WindowsArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')

    $backslashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
            continue
        }

        if ($ch -eq '"') {
            if ($backslashes -gt 0) {
                [void]$builder.Append(('\' * ($backslashes * 2)))
                $backslashes = 0
            }
            [void]$builder.Append('\"')
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }

        [void]$builder.Append($ch)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-Evox2CommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string[]]$Arguments = @()
    )

    $parts = @(
        ConvertTo-Evox2WindowsArgument -Value $Executable
    )

    foreach ($argument in $Arguments) {
        $parts += ConvertTo-Evox2WindowsArgument -Value ([string]$argument)
    }

    return ($parts -join ' ')
}

function ConvertTo-Evox2InvariantString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    if ($Value -is [System.IFormattable]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }

    return [string]$Value
}

function Get-Evox2ConfigEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Builds', 'Models', 'Inputs')]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not $Config.ContainsKey($Section)) {
        throw "Configuration section '$Section' is missing."
    }

    $sectionValue = $Config[$Section]
    if (-not ($sectionValue -is [System.Collections.IDictionary])) {
        throw "Configuration section '$Section' is not a dictionary."
    }

    if (-not $sectionValue.Contains($Key)) {
        throw "Configuration key '$Section.$Key' was not found."
    }

    return $sectionValue[$Key]
}

function Get-Evox2BuildLabel {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$ExecutableMetadata
    )

    if ($null -ne $ExecutableMetadata -and $null -ne $ExecutableMetadata.BuildNumber) {
        return "b$($ExecutableMetadata.BuildNumber)"
    }

    return 'build-unknown'
}

function New-Evox2RunDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogRoot,

        [Parameter(Mandatory = $true)]
        [string]$Tool,

        [Parameter(Mandatory = $true)]
        [string]$Backend,

        [Parameter(Mandatory = $true)]
        [string]$BuildLabel,

        [Parameter(Mandatory = $true)]
        [int]$Context,

        [Parameter(Mandatory = $true)]
        [string]$ConditionId
    )

    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

    $safeTool = $Tool.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    $safeBackend = $Backend.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    $safeBuild = $BuildLabel.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'

    $name = "$stamp-$safeTool-$safeBackend-$safeBuild-ctx$Context-$ConditionId"
    $path = Join-Path $LogRoot $name

    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return [IO.Path]::GetFullPath($path)
}

function Write-Evox2CombinedLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$HeaderLines = @(),

        [Parameter(Mandatory = $true)]
        [string]$StdErrPath,

        [Parameter(Mandatory = $true)]
        [string]$StdOutPath
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $builder = New-Object System.Text.StringBuilder

    foreach ($line in $HeaderLines) {
        [void]$builder.AppendLine($line)
    }

    [void]$builder.AppendLine()
    [void]$builder.AppendLine('================ STDERR ================')
    if (Test-Path -LiteralPath $StdErrPath -PathType Leaf) {
        [void]$builder.Append([IO.File]::ReadAllText($StdErrPath, $utf8NoBom))
    }

    [void]$builder.AppendLine()
    [void]$builder.AppendLine('================ STDOUT ================')
    if (Test-Path -LiteralPath $StdOutPath -PathType Leaf) {
        [void]$builder.Append([IO.File]::ReadAllText($StdOutPath, $utf8NoBom))
    }

    [IO.File]::WriteAllText([IO.Path]::GetFullPath($Path), $builder.ToString(), $utf8NoBom)
}

function Start-Evox2AdlxGpuMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$StdOutPath,

        [Parameter(Mandatory = $true)]
        [string]$StdErrPath,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$TargetProcessId,

        [ValidateRange(100, 60000)]
        [int]$IntervalMs = 2000,

        [ValidateRange(0, 64)]
        [int]$GpuIndex = 0
    )

    $fullExecutable = [IO.Path]::GetFullPath($Executable)
    if (-not (Test-Path -LiteralPath $fullExecutable -PathType Leaf)) {
        throw "ADLX GPU monitor executable not found: $fullExecutable"
    }

    $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
    $outputDir = Split-Path -Parent $fullOutputPath
    if ($outputDir) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $arguments = @(
        '--duration', '0',
        '--interval-ms', "$IntervalMs",
        '--gpu-index', "$GpuIndex",
        '--target-pid', "$TargetProcessId",
        '--output', $fullOutputPath
    )

    $argumentLine = (
        $arguments |
        ForEach-Object { ConvertTo-Evox2WindowsArgument -Value ([string]$_) }
    ) -join ' '

    return Start-Process `
        -FilePath $fullExecutable `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $fullExecutable) `
        -RedirectStandardOutput $StdOutPath `
        -RedirectStandardError $StdErrPath `
        -NoNewWindow `
        -PassThru
}


function Get-Evox2AdlxPModeConsistency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [AllowNull()]
        [object]$PModeAtStart,

        [AllowNull()]
        [object]$PModeAtFinish,

        [ValidateRange(1, 100)]
        [double]$GpuUsageThreshold = 95,

        [ValidateRange(1, 1000)]
        [int]$MinimumHighLoadSamples = 5
    )

    $result = [ordered]@{
        Evaluated              = $false
        CsvPath                = $CsvPath
        GpuUsageThresholdPct   = $GpuUsageThreshold
        MinimumHighLoadSamples = $MinimumHighLoadSamples
        ClassifierVersion      = 1
        QuietMaxW              = 65.0
        BalancedMinW           = 75.0
        BalancedMaxW           = 95.0
        PerformanceMinW        = 105.0
        HighLoadSampleCount    = 0
        AverageGpuPowerW       = $null
        PowerClass             = 'Unavailable'
        AuthoritativeMode      = $null
        PModeChanged           = $null
        Consistent             = $null
        Warning                = $false
        WarningCode            = $null
        Reason                 = $null
    }

    $startOk = (
        $null -ne $PModeAtStart -and
        $PModeAtStart.PSObject.Properties['ProbeSucceeded'] -and
        [bool]$PModeAtStart.ProbeSucceeded
    )
    $finishOk = (
        $null -ne $PModeAtFinish -and
        $PModeAtFinish.PSObject.Properties['ProbeSucceeded'] -and
        [bool]$PModeAtFinish.ProbeSucceeded
    )

    if ($startOk -and $finishOk) {
        $result.PModeChanged = ([string]$PModeAtStart.Mode -ne [string]$PModeAtFinish.Mode)
        if (-not $result.PModeChanged) {
            $result.AuthoritativeMode = [string]$PModeAtStart.Mode
        }
    }

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        $result.Reason = 'ADLX CSV is not available.'
        return [PSCustomObject]$result
    }

    $powers = New-Object System.Collections.Generic.List[double]
    try {
        foreach ($row in @(Import-Csv -LiteralPath $CsvPath)) {
            if ($null -eq $row) {
                continue
            }

            $adlxResult = $null
            $usage = $null
            $power = $null

            try { $adlxResult = [int]$row.adlx_result } catch { continue }
            if ($adlxResult -ne 0) {
                continue
            }

            try {
                $usage = ConvertFrom-Evox2InvariantDouble -Value ([string]$row.gpu_usage_pct)
                $power = ConvertFrom-Evox2InvariantDouble -Value ([string]$row.gpu_power_w)
            } catch {
                continue
            }

            if ($null -eq $usage -or $null -eq $power) {
                continue
            }
            if ($usage -lt $GpuUsageThreshold) {
                continue
            }

            [void]$powers.Add([double]$power)
        }
    } catch {
        $result.Reason = "Failed to read ADLX CSV: $($_.Exception.Message)"
        return [PSCustomObject]$result
    }

    $result.HighLoadSampleCount = $powers.Count
    if ($powers.Count -lt $MinimumHighLoadSamples) {
        $result.PowerClass = 'InsufficientSamples'
        $result.Reason = "Only $($powers.Count) high-load power sample(s) were available."
        return [PSCustomObject]$result
    }

    $average = ($powers.ToArray() | Measure-Object -Average).Average
    $result.AverageGpuPowerW = [math]::Round([double]$average, 3)
    $result.Evaluated = $true

    if ($average -le 65.0) {
        $result.PowerClass = 'Quiet-like'
    } elseif ($average -ge 75.0 -and $average -le 95.0) {
        $result.PowerClass = 'Balanced-like'
    } elseif ($average -ge 105.0) {
        $result.PowerClass = 'Performance-like'
    } else {
        $result.PowerClass = 'Ambiguous'
    }

    if ($result.PModeChanged) {
        $result.Reason = 'P-MODE changed between start and finish; power consistency was not classified against a single authoritative mode.'
        return [PSCustomObject]$result
    }

    if ([string]::IsNullOrWhiteSpace([string]$result.AuthoritativeMode)) {
        $result.Reason = 'No stable authoritative start/finish P-MODE was available.'
        return [PSCustomObject]$result
    }

    if ($result.PowerClass -eq 'Ambiguous') {
        $result.Reason = 'Average high-load GPU power fell in an intentionally ambiguous band.'
        return [PSCustomObject]$result
    }

    $expectedClass = switch ($result.AuthoritativeMode) {
        'Quiet'       { 'Quiet-like'; break }
        'Balanced'    { 'Balanced-like'; break }
        'Performance' { 'Performance-like'; break }
        default       { $null }
    }

    if ([string]::IsNullOrWhiteSpace([string]$expectedClass)) {
        $result.Reason = "Unsupported authoritative P-MODE: $($result.AuthoritativeMode)"
        return [PSCustomObject]$result
    }

    $result.Consistent = ($result.PowerClass -eq $expectedClass)
    if (-not $result.Consistent) {
        $result.Warning = $true
        $result.WarningCode = 'PMODE_ADLX_POWER_MISMATCH'
        $result.Reason = (
            'Authoritative P-MODE is {0}, but high-load ADLX power is {1} ({2:N1} W average across {3} sample(s)).' -f
            $result.AuthoritativeMode,
            $result.PowerClass,
            $average,
            $powers.Count
        )
    } else {
        $result.Reason = (
            'Authoritative P-MODE and high-load ADLX power classification agree ({0}, {1:N1} W).' -f
            $result.PowerClass,
            $average
        )
    }

    return [PSCustomObject]$result
}

function Get-Evox2PModeWarnings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$PModeAtStart,

        [AllowNull()]
        [object]$PModeAtFinish,

        [AllowNull()]
        [object]$AdlxConsistency,

        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$ExpectedMode = 'Performance'
    )

    $warnings = New-Object System.Collections.Generic.List[string]

    if ($null -ne $PModeAtStart -and $null -ne $PModeAtFinish -and
        [string]$PModeAtStart.Source -eq 'Disabled' -and
        [string]$PModeAtFinish.Source -eq 'Disabled') {
        return $warnings.ToArray()
    }

    if ($null -eq $PModeAtStart -or -not [bool]$PModeAtStart.ProbeSucceeded) {
        $detail = if ($null -ne $PModeAtStart) { [string]$PModeAtStart.Error } else { 'no start probe object' }
        [void]$warnings.Add("P-MODE start probe failed; state is Unknown. $detail")
    } elseif ([string]$PModeAtStart.Mode -ne $ExpectedMode) {
        [void]$warnings.Add("P-MODE at start is $($PModeAtStart.Mode); expected $ExpectedMode for performance comparisons.")
    }

    if ($null -eq $PModeAtFinish -or -not [bool]$PModeAtFinish.ProbeSucceeded) {
        $detail = if ($null -ne $PModeAtFinish) { [string]$PModeAtFinish.Error } else { 'no finish probe object' }
        [void]$warnings.Add("P-MODE finish probe failed; state is Unknown. $detail")
    } elseif ([string]$PModeAtFinish.Mode -ne $ExpectedMode) {
        [void]$warnings.Add("P-MODE at finish is $($PModeAtFinish.Mode); expected $ExpectedMode for performance comparisons.")
    }

    if ($null -ne $PModeAtStart -and $null -ne $PModeAtFinish -and
        [bool]$PModeAtStart.ProbeSucceeded -and [bool]$PModeAtFinish.ProbeSucceeded -and
        [string]$PModeAtStart.Mode -ne [string]$PModeAtFinish.Mode) {
        [void]$warnings.Add("P-MODE changed during the run: $($PModeAtStart.Mode) -> $($PModeAtFinish.Mode).")
    }

    if ($null -ne $AdlxConsistency -and
        $AdlxConsistency.PSObject.Properties['Warning'] -and
        [bool]$AdlxConsistency.Warning) {
        [void]$warnings.Add([string]$AdlxConsistency.Reason)
    }

    return $warnings.ToArray()
}

function Get-Evox2LastRegexMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[$matches.Count - 1]
}

function ConvertFrom-Evox2InvariantDouble {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [double]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-Evox2InvariantInt64 {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [int64]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-Evox2MtpDenseIndexerEvidence {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [AllowNull()][string]$Setting, [bool]$Mtp)
    $pattern = '(?m)MTP dense indexer: requested=([01]) eligible=([01]) omitted=([01]) layer=(-?\d+) ratio=(-?\d+) reason=([a-z_]+)\r?$'
    $records = @([regex]::Matches($Text, $pattern) | ForEach-Object {
        [PSCustomObject]@{
            Requested = $_.Groups[1].Value -eq '1'; Eligible = $_.Groups[2].Value -eq '1'
            Omitted = $_.Groups[3].Value -eq '1'; Layer = [int64]$_.Groups[4].Value
            Ratio = [int64]$_.Groups[5].Value; Reason = $_.Groups[6].Value
        }
    })
    $status = if (-not $Mtp) { 'MtpDisabled' } elseif ($Setting -notin @('0', '1')) { 'NotRequested' }
        elseif (-not $records.Count) { 'Missing' }
        elseif ([regex]::Matches($Text, 'MTP dense indexer:').Count -ne $records.Count) { 'Malformed' }
        else { 'Verified' }
    if ($status -eq 'Verified') {
        foreach ($record in $records) {
            if ($record.Requested -ne ($Setting -eq '1')) { $status = 'Mismatch'; break }
            if ($Setting -eq '1' -and (-not $record.Eligible -or -not $record.Omitted -or
                $record.Layer -lt 0 -or $record.Ratio -ne 0 -or $record.Reason -ne 'dense_single_block')) {
                $status = 'NotApplied'; break
            }
            if ($Setting -eq '0' -and $record.Omitted) { $status = 'Mismatch'; break }
        }
    }
    return [PSCustomObject]@{
        Setting = $Setting; Status = $status; Decisions = @($records)
        Omitted = if ($status -eq 'Verified') { $records[-1].Omitted } else { $null }
    }
}


function Get-Evox2QsaNoopInvalidationEvidence {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text, [AllowNull()][string]$Setting)
    $pattern = '(?m)QSA no-op invalidation: requested=([01]) eligible=([01]) enabled=([01]) target=([01]) kpool=(\d+) streams=(\d+) seq_max=(\d+) reason=([a-z_]+)\r?$'
    $records = @([regex]::Matches($Text, $pattern) | ForEach-Object {
        [PSCustomObject]@{
            Requested = $_.Groups[1].Value -eq '1'; Eligible = $_.Groups[2].Value -eq '1'
            Enabled = $_.Groups[3].Value -eq '1'; Target = $_.Groups[4].Value -eq '1'
            KPool = [int64]$_.Groups[5].Value; Streams = [int64]$_.Groups[6].Value
            SeqMax = [int64]$_.Groups[7].Value; Reason = $_.Groups[8].Value
        }
    })
    $targets = @($records | Where-Object { $_.Target })
    $status = if ($Setting -notin @('0', '1')) { 'NotRequested' }
        elseif ([regex]::Matches($Text, 'QSA no-op invalidation:').Count -ne $records.Count) { 'Malformed' }
        elseif ($targets.Count -gt 1) { 'Malformed' }
        elseif ($targets.Count -eq 0) { 'Missing' }
        else { 'Verified' }
    if ($status -eq 'Verified') {
        $target = $targets[0]
        if ($target.Requested -ne ($Setting -eq '1') -or
            ($target.Enabled -and (-not $target.Eligible -or -not $target.Requested)) -or
            ($target.Eligible -and ($target.KPool -ne 4 -or $target.Streams -ne 1 -or $target.SeqMax -ne 1)) -or
            ($Setting -eq '0' -and $target.Enabled)) { $status = 'Mismatch' }
        elseif ($Setting -eq '1' -and (-not $target.Eligible -or -not $target.Enabled)) { $status = 'NotApplied' }
        elseif (($target.Enabled -and $target.Reason -ne 'target_single_sequence') -or
            ($target.Eligible -and -not $target.Enabled -and $target.Reason -ne 'disabled')) { $status = 'Mismatch' }
    }
    return [PSCustomObject]@{
        Setting = $Setting; Status = $status; Decisions = @($records)
        Enabled = if ($status -eq 'Verified') { $targets[0].Enabled } else { $null }
    }
}

function ConvertFrom-Evox2LlamaCliResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $prompt = Get-Evox2LastRegexMatch -Text $Text -Pattern (
        'prompt eval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens' +
        '\s*\([^\r\n]*?([\d.]+)\s*tokens per second\)'
    )

    $generation = Get-Evox2LastRegexMatch -Text $Text -Pattern (
        '(?m)^[^\r\n]*?(?<!prompt )\beval time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens' +
        '\s*\([^\r\n]*?([\d.]+)\s*tokens per second\)'
    )

    $total = Get-Evox2LastRegexMatch -Text $Text -Pattern (
        'total time\s*=\s*([\d.]+)\s*ms\s*/\s*(\d+)\s*tokens'
    )

    $actualContextMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern 'llama_context:\s+n_ctx\s*=\s*(\d+)'

    $taskTokensMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern 'task\.n_tokens\s*=\s*(\d+)'

    $summaryMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern '\[\s*Prompt:\s*([\d.]+)\s*t/s\s*\|\s*Generation:\s*([\d.]+)\s*t/s\s*\]'

    $cpuMappedMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern 'CPU_Mapped model buffer size\s*=\s*([\d.]+)\s*MiB'

    $acceptanceMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern 'draft acceptance\s*=\s*([\d.]+)\s*\(\s*(\d+)\s+accepted\s*/\s*(\d+)\s+generated\)'

    $modelArchMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern '(?m)print_info:\s+arch\s*=\s*(\S+)'

    $fileTypeMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern '(?m)print_info:\s+file type\s*=\s*(.+?)\s*$'

    $fileSizeMatch = Get-Evox2LastRegexMatch -Text $Text `
        -Pattern '(?m)print_info:\s+file size\s*=\s*([\d.]+)\s+GiB'

    $memoryLines = @(
        $Text -split "`r?`n" |
        Where-Object {
            $_ -match 'common_memory_breakdown_print:' -or
            $_ -match '\|\s*memory breakdown \[MiB\]'
        }
    )

    $bufferLines = @(
        $Text -split "`r?`n" |
        Where-Object {
            $_ -match '\b(?:model|KV|compute) buffer size\s*='
        }
    )

    [PSCustomObject]@{
        ActualContext = if ($actualContextMatch) {
            ConvertFrom-Evox2InvariantInt64 $actualContextMatch.Groups[1].Value
        } else { $null }

        TaskPromptTokens = if ($taskTokensMatch) {
            ConvertFrom-Evox2InvariantInt64 $taskTokensMatch.Groups[1].Value
        } else { $null }

        PromptEvalMilliseconds = if ($prompt) {
            ConvertFrom-Evox2InvariantDouble $prompt.Groups[1].Value
        } else { $null }

        PromptTokens = if ($prompt) {
            ConvertFrom-Evox2InvariantInt64 $prompt.Groups[2].Value
        } else { $null }

        PromptTokensPerSecond = if ($prompt) {
            ConvertFrom-Evox2InvariantDouble $prompt.Groups[3].Value
        } else { $null }

        GenerationEvalMilliseconds = if ($generation) {
            ConvertFrom-Evox2InvariantDouble $generation.Groups[1].Value
        } else { $null }

        GeneratedTokens = if ($generation) {
            ConvertFrom-Evox2InvariantInt64 $generation.Groups[2].Value
        } else { $null }

        GenerationTokensPerSecond = if ($generation) {
            ConvertFrom-Evox2InvariantDouble $generation.Groups[3].Value
        } else { $null }

        TotalMilliseconds = if ($total) {
            ConvertFrom-Evox2InvariantDouble $total.Groups[1].Value
        } else { $null }

        TotalTokens = if ($total) {
            ConvertFrom-Evox2InvariantInt64 $total.Groups[2].Value
        } else { $null }

        SummaryPromptTokensPerSecond = if ($summaryMatch) {
            ConvertFrom-Evox2InvariantDouble $summaryMatch.Groups[1].Value
        } else { $null }

        SummaryGenerationTokensPerSecond = if ($summaryMatch) {
            ConvertFrom-Evox2InvariantDouble $summaryMatch.Groups[2].Value
        } else { $null }

        CpuMappedMiB = if ($cpuMappedMatch) {
            ConvertFrom-Evox2InvariantDouble $cpuMappedMatch.Groups[1].Value
        } else { $null }

        DraftAcceptance = if ($acceptanceMatch) {
            ConvertFrom-Evox2InvariantDouble $acceptanceMatch.Groups[1].Value
        } else { $null }

        DraftAccepted = if ($acceptanceMatch) {
            ConvertFrom-Evox2InvariantInt64 $acceptanceMatch.Groups[2].Value
        } else { $null }

        DraftGenerated = if ($acceptanceMatch) {
            ConvertFrom-Evox2InvariantInt64 $acceptanceMatch.Groups[3].Value
        } else { $null }

        ModelArchitecture = if ($modelArchMatch) {
            $modelArchMatch.Groups[1].Value.Trim()
        } else { $null }

        ModelFileType = if ($fileTypeMatch) {
            $fileTypeMatch.Groups[1].Value.Trim()
        } else { $null }

        ModelFileSizeGiB = if ($fileSizeMatch) {
            ConvertFrom-Evox2InvariantDouble $fileSizeMatch.Groups[1].Value
        } else { $null }

        MemoryBreakdownLines = $memoryLines
        BufferLines          = $bufferLines
    }
}


function ConvertFrom-Evox2LlamaBenchJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'llama-bench JSON output is empty.'
    }

    try {
        $parsed = $Json | ConvertFrom-Json
    } catch {
        throw "Failed to parse llama-bench JSON output: $($_.Exception.Message)"
    }

    if ($null -eq $parsed) {
        return @()
    }

    if ($parsed -is [System.Array]) {
        return $parsed
    }

    return @($parsed)
}

function Get-Evox2LlamaBenchTestLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row
    )

    $nPrompt = if ($null -ne $Row.n_prompt) { [int64]$Row.n_prompt } else { 0 }
    $nGen = if ($null -ne $Row.n_gen) { [int64]$Row.n_gen } else { 0 }
    $nDepth = if ($null -ne $Row.n_depth) { [int64]$Row.n_depth } else { 0 }

    if ($nPrompt -gt 0 -and $nGen -gt 0) {
        $label = "pg $nPrompt,$nGen"
    } elseif ($nPrompt -gt 0) {
        $label = "pp $nPrompt"
    } elseif ($nGen -gt 0) {
        $label = "tg $nGen"
    } else {
        $label = 'unknown'
    }

    if ($nDepth -gt 0) {
        $label += " @ d$nDepth"
    }

    return $label
}


# Lightweight context for benchmark contamination analysis. This records
# *observed* Windows update/Defender/indexer processes, not service health,
# and never starts/stops/changes Windows services or Defender.
function Get-Evox2BackgroundActivitySnapshot {
    [CmdletBinding()]
    param()

    $candidates = @(
        'MsMpEng', 'NisSrv', 'MpCmdRun',                    # Defender
        'TiWorker', 'TrustedInstaller', 'MoUsoCoreWorker',  # Windows servicing/update
        'UsoClient', 'wuauclt', 'WaaSMedicAgent', 'WindowsUpdateBox',
        'SearchIndexer', 'SearchProtocolHost', 'SearchFilterHost',
        'CompatTelRunner', 'dismhost', 'SetupHost'
    )

    $now = Get-Date
    $items = @()
    $probeError = $null

    try {
        $processes = @(Get-Process -ErrorAction Stop |
            Where-Object { $_.ProcessName -in $candidates })
        foreach ($proc in $processes) {
            $cpuSeconds = $null
            $startTime = $null
            try {
                if ($null -ne $proc.CPU) {
                    $cpuSeconds = [math]::Round([double]$proc.CPU, 3)
                }
            } catch {}
            try { $startTime = $proc.StartTime.ToUniversalTime().ToString('o') } catch {}

            $category = switch -Regex ($proc.ProcessName) {
                '^(MsMpEng|NisSrv|MpCmdRun)$' { 'Defender'; break }
                '^(SearchIndexer|SearchProtocolHost|SearchFilterHost)$' { 'Indexer'; break }
                default { 'WindowsMaintenance' }
            }

            $items += [PSCustomObject]@{
                Name         = [string]$proc.ProcessName
                Pid          = [int]$proc.Id
                StartedUtc   = $startTime
                CpuSeconds   = $cpuSeconds
                Category     = $category
            }
        }
    } catch {
        $probeError = $_.Exception.Message
    }

    return [PSCustomObject]@{
        TimestampUtc = $now.ToUniversalTime().ToString('o')
        Status       = if ($probeError) { 'ProbeError' } else { 'Observed' }
        Error        = $probeError
        Processes    = @($items)
    }
}

function Compare-Evox2BackgroundActivitySnapshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Before,
        [Parameter(Mandatory = $true)][object]$After
    )

    $t0 = [datetime]::Parse([string]$Before.TimestampUtc).ToUniversalTime()
    $t1 = [datetime]::Parse([string]$After.TimestampUtc).ToUniversalTime()
    $duration = [math]::Max(0.001, ($t1 - $t0).TotalSeconds)
    $byKey = @{}
    foreach ($p in @($Before.Processes)) {
        if ($null -ne $p) {
            $byKey["$($p.Pid):$($p.StartedUtc)"] = $p
        }
    }
    $active = @()
    $cpuTotal = 0.0
    $cpuKnownCount = 0
    foreach ($p in @($After.Processes)) {
        if ($null -eq $p) { continue }
        $key = "$($p.Pid):$($p.StartedUtc)"
        if ($byKey.ContainsKey($key)) {
            $prior = $byKey[$key]
            if ($null -ne $p.CpuSeconds -and $null -ne $prior.CpuSeconds) {
                $delta = [math]::Max(0.0, [double]$p.CpuSeconds - [double]$prior.CpuSeconds)
                $cpuTotal += $delta
                $cpuKnownCount++
                if ($delta -gt 0) {
                    $active += [PSCustomObject]@{
                        Name = $p.Name; Pid = $p.Pid; CpuDeltaSeconds = [math]::Round($delta, 3)
                    }
                }
            }
        } else {
            # A new or restarted process may have done work; do not subtract
            # its lifetime CPU counter from zero without confirming start time.
            $started = $null
            try { $started = [datetime]::Parse([string]$p.StartedUtc).ToUniversalTime() } catch {}
            if ($null -ne $started -and $started -ge $t0 -and $null -ne $p.CpuSeconds) {
                $delta = [math]::Max(0.0, [double]$p.CpuSeconds)
                $cpuTotal += $delta
                $cpuKnownCount++
                if ($delta -gt 0) {
                    $active += [PSCustomObject]@{
                        Name = $p.Name; Pid = $p.Pid; CpuDeltaSeconds = [math]::Round($delta, 3)
                    }
                }
            }
        }
    }

    $machineCpuPercent = 100.0 * $cpuTotal / ($duration * [math]::Max(1, [Environment]::ProcessorCount))
    $busy = @($active | Where-Object { $_.CpuDeltaSeconds -gt 0 } |
        Group-Object -Property Name | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; CpuDeltaSeconds =
                [math]::Round(($_.Group | Measure-Object CpuDeltaSeconds -Sum).Sum, 3) }
        } | Where-Object {
            # An aggregate 0.5% of total CPU is a possible measurement disturbance,
            # not conclusive attribution of benchmark speed changes.
            (100.0 * $_.CpuDeltaSeconds / ($duration * [math]::Max(1, [Environment]::ProcessorCount))) -ge 0.5
        } | Select-Object -ExpandProperty Name)

    $names = @($After.Processes | ForEach-Object { $_.Name } | Sort-Object -Unique)

    return [PSCustomObject]@{
        Status             = if ($Before.Status -ne 'Observed' -or $After.Status -ne 'Observed') { 'Partial' } else { 'Observed' }
        DurationSeconds    = [math]::Round($duration, 3)
        ProcessNames       = $names
        ActiveNames        = @($active | ForEach-Object { $_.Name } | Sort-Object -Unique)
        BusyNames          = $busy
        CpuKnownCount      = $cpuKnownCount
        CpuDeltaSeconds    = [math]::Round($cpuTotal, 3)
        CpuPercentOfSystem = [math]::Round($machineCpuPercent, 3)
        PossibleNoise      = $busy.Count -gt 0
        Caveat             = 'Only named processes observed at sample boundaries; short-lived processes may be missed. CPU time is not disk I/O or service-level attribution; no automatic exclusion.'
    }
}

Export-ModuleMember -Function @(
    'Import-Evox2LocalConfig',
    'Get-Evox2RelevantEnvironment',
    'ConvertTo-Evox2WindowsArgument',
    'ConvertTo-Evox2CommandLine',
    'ConvertTo-Evox2InvariantString',
    'Get-Evox2ConfigEntry',
    'Get-Evox2BuildLabel',
    'New-Evox2RunDirectory',
    'Write-Evox2CombinedLog',
    'Start-Evox2AdlxGpuMonitor',
    'Get-Evox2AdlxPModeConsistency',
    'Get-Evox2PModeWarnings',
    'Get-Evox2MtpDenseIndexerEvidence',
    'Get-Evox2QsaNoopInvalidationEvidence',
    'ConvertFrom-Evox2LlamaCliResult',
    'ConvertFrom-Evox2LlamaBenchJson',
    'Get-Evox2LlamaBenchTestLabel',
    'Get-Evox2BackgroundActivitySnapshot',
    'Compare-Evox2BackgroundActivitySnapshots'
)
