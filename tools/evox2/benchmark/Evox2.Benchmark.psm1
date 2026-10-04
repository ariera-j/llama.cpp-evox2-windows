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
    'Get-Evox2MtpDenseIndexerEvidence',
    'ConvertFrom-Evox2LlamaCliResult',
    'ConvertFrom-Evox2LlamaBenchJson',
    'Get-Evox2LlamaBenchTestLabel'
)
