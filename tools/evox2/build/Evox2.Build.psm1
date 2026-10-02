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
        'ggml.dll',
        'llama.dll',
        'ggml-base.dll',
        'ggml-cpu.dll',
        'ggml-vulkan.dll',
        'ggml-hip.dll'
    )

    $result = @()

    foreach ($name in $names) {
        $path = Join-Path $BinDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $result += Get-Evox2FileIdentity -Path $path -Sha256
        }
    }

    return @($result)
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
        [object]$Validation
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

    $manifest = [ordered]@{
        SchemaVersion = 1
        GeneratedAt   = (Get-Date).ToString('o')
        GeneratedBy   = $GeneratedBy

        Backend       = $Backend
        Configuration = $Configuration
        BuildDirectory = $BuildDir
        BinaryDirectory = $BinDir

        Source = $git

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
    return $manifestPath
}

Export-ModuleMember -Function @(
    'Get-Evox2ToolIdentity',
    'ConvertTo-Evox2CaptureRecord',
    'Get-Evox2BuildArtifactIdentities',
    'Write-Evox2BuildManifest'
)
