#requires -Version 5.1

Set-StrictMode -Version Latest

function Get-Evox2ToolIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string[]]$VersionArguments = @('--version')
    )

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $command) {
        return [PSCustomObject]@{
            Name     = $Name
            Path     = $null
            ExitCode = $null
            Text     = $null
        }
    }

    $capture = Invoke-Evox2NativeCapture `
        -FilePath $command.Source `
        -ArgumentList $VersionArguments

    return [PSCustomObject]@{
        Name     = $Name
        Path     = $command.Source
        ExitCode = $capture.ExitCode
        Text     = $capture.Text
    }
}

function ConvertTo-Evox2CaptureRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Capture,

        [ValidateRange(1, 500)]
        [int]$TailLines = 80
    )

    if ($null -eq $Capture) {
        return $null
    }

    $lines = @($Capture.Lines)
    if ($lines.Count -gt $TailLines) {
        $lines = @($lines | Select-Object -Last $TailLines)
    }

    return [ordered]@{
        FilePath  = $Capture.FilePath
        Arguments = @($Capture.Arguments)
        ExitCode  = $Capture.ExitCode
        Tail      = @($lines)
    }
}

function Save-Evox2CaptureLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Capture,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $header = @(
        "CapturedAt: $((Get-Date).ToString('o'))",
        "Executable: $($Capture.FilePath)",
        "Arguments: $($Capture.Arguments -join ' ')",
        "ExitCode: $($Capture.ExitCode)",
        ''
    )
    $text = (@($header) + @($Capture.Lines)) -join [Environment]::NewLine
    [IO.File]::WriteAllText($fullPath, $text + [Environment]::NewLine, $utf8NoBom)
    return $fullPath
}

function Get-Evox2BuildArtifactIdentities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BinDir
    )

    $names = @(
        'llama-cli.exe',
        'llama-server.exe',
        'llama-bench.exe',
        'test-backend-ops.exe',
        'test-mtp-indexer-policy.exe',
        'test-mtp-dense-indexer.exe',
        'test-qsa-noop-policy.exe',
        'test-qsa-noop-invalidation.exe',
        'ggml.dll',
        'llama.dll',
        'ggml-base.dll',
        'ggml-cpu.dll',
        'ggml-vulkan.dll',
        'ggml-hip.dll'
    )

    $names += @('llama-cli.dll', 'llama-server.dll', 'llama-common.dll')
    $names += @(Get-ChildItem -LiteralPath $BinDir -Filter 'ggml-cpu*.dll' -File |
        ForEach-Object { $_.Name })
    $names = @($names | Sort-Object -Unique)

    $result = @()

    foreach ($name in $names) {
        $path = Join-Path $BinDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $result += Get-Evox2FileIdentity -Path $path -Sha256
        }
    }

    return @($result)
}

function Invoke-Evox2BuildMetadataRefresh {
    [CmdletBinding()]
    param([string]$CMake, [string]$RepoRoot, [string]$BuildDir,
          [ValidateSet('Vulkan', 'ROCm')][string]$Backend)

    $cachePath = Join-Path $BuildDir 'CMakeCache.txt'
    if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
        throw 'BuildOnly requires an existing CMake cache; run a full configure first.'
    }
    $cache = Get-Content -LiteralPath $cachePath -Raw
    $homeMatch = [regex]::Match($cache, '(?m)^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)\r?$')
    if (-not $homeMatch.Success -or
        -not [string]::Equals([IO.Path]::GetFullPath($homeMatch.Groups[1].Value.Trim()),
            [IO.Path]::GetFullPath($RepoRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CMake cache belongs to another source directory.'
    }
    $backendFlag = if ($Backend -eq 'Vulkan') { 'GGML_VULKAN' } else { 'GGML_HIP' }
    if ($cache -notmatch "(?m)^${backendFlag}:BOOL=(ON|1|TRUE)\r?`$") {
        throw "CMake cache does not enable $backendFlag."
    }
    $arguments = @('-S', $RepoRoot, '-B', $BuildDir)
    Write-Host 'Refreshing build metadata using the existing CMake configuration...'
    & $CMake @arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Metadata refresh failed: $LASTEXITCODE" }
    return [ordered]@{ Executed = $true; Arguments = $arguments; CachePreserved = $true }
}

function Write-Evox2BuildManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Vulkan', 'ROCm')]
        [string]$Backend,

        [Parameter(Mandatory = $true)]
        [string]$BuildDir,

        [Parameter(Mandatory = $true)]
        [string]$BinDir,

        [Parameter(Mandatory = $true)]
        [string]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$GeneratedBy,

        [Parameter(Mandatory = $true)]
        [object]$Configure,

        [Parameter(Mandatory = $true)]
        [object]$Build,

        [Parameter(Mandatory = $true)]
        [object]$Toolchain,

        [Parameter(Mandatory = $true)]
        [object]$BackendSettings,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Runtime,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Validation,

        [AllowNull()]
        [object]$BuildSource
    )

    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
    $BuildDir = [IO.Path]::GetFullPath($BuildDir)
    $BinDir = [IO.Path]::GetFullPath($BinDir)

    if (-not (Test-Path -LiteralPath $BinDir -PathType Container)) {
        throw "Binary directory not found: $BinDir"
    }

    $llamaCli = Join-Path $BinDir 'llama-cli.exe'
    if (-not (Test-Path -LiteralPath $llamaCli -PathType Leaf)) {
        throw "llama-cli.exe not found: $llamaCli"
    }

    $git = Get-Evox2GitMetadata -RepoRoot $RepoRoot
    $exe = Get-Evox2ExecutableMetadata -Executable $llamaCli
    $devices = $null
    try {
        $devices = Get-Evox2DeviceMetadata -Executable $llamaCli
    } catch {}

    $artifacts = Get-Evox2BuildArtifactIdentities -BinDir $BinDir
    $manifestPath = Join-Path $BinDir 'evox2-build.json'

    $identityStatus = 'Unverified'
    $identityReason = 'No real build executed by this invocation.'
    if ($Build.Executed) {
        $sourceStable = $null -ne $BuildSource -and
            $BuildSource.Commit -eq $git.Commit -and
            $BuildSource.DirtyFingerprint -eq $git.DirtyFingerprint
        $versionMatches = -not [string]::IsNullOrWhiteSpace($exe.Commit) -and
            $git.Commit.StartsWith($exe.Commit, [StringComparison]::OrdinalIgnoreCase)
        if ($sourceStable -and $versionMatches) {
            $identityStatus = 'Verified'
            $identityReason = 'Source stable during build; embedded commit matches.'
        } else {
            $identityStatus = 'Mismatch'
            $identityReason = 'Source changed during build or embedded commit does not match build source.'
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($exe.Commit) -and
        -not $git.Commit.StartsWith($exe.Commit, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning 'ManifestOnly: embedded commit differs from current checkout; no rebuild was performed.'
    }

    $manifest = [ordered]@{
        SchemaVersion = 1
        GeneratedAt   = (Get-Date).ToString('o')
        GeneratedBy   = $GeneratedBy

        Backend       = $Backend
        Configuration = $Configuration
        BuildDirectory = $BuildDir
        BinaryDirectory = $BinDir

        Source = $git
        BuildSource = $BuildSource
        BuildIdentity = [ordered]@{ Status = $identityStatus; Reason = $identityReason }

        ExecutableIdentity = $exe
        DeviceIdentity     = $devices

        Configure       = $Configure
        Build           = $Build
        Toolchain       = $Toolchain
        BackendSettings = $BackendSettings
        Runtime         = $Runtime
        Validation      = $Validation

        Artifacts = @($artifacts)
    }

    Write-Evox2Json -InputObject $manifest -Path $manifestPath -Depth 32
    if ($identityStatus -eq 'Mismatch') {
        throw "$identityReason Manifest preserved at $manifestPath"
    }
    return $manifestPath
}

Export-ModuleMember -Function @(
    'Get-Evox2ToolIdentity',
    'ConvertTo-Evox2CaptureRecord',
    'Save-Evox2CaptureLog',
    'Get-Evox2BuildArtifactIdentities',
    'Invoke-Evox2BuildMetadataRefresh',
    'Write-Evox2BuildManifest'
)
