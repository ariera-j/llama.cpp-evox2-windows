#requires -Version 5.1

Set-StrictMode -Version Latest

function Set-Evox2Utf8Console {
    [CmdletBinding()]
    param()

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $script:OutputEncoding = $utf8NoBom
}

function ConvertTo-Evox2SafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [ValidateRange(8, 200)]
        [int]$MaxLength = 80
    )

    $safe = $Value.Trim()
    $safe = $safe -replace '[<>:"/\\|?*\x00-\x1F]', '-'
    $safe = $safe -replace '\s+', '-'
    $safe = $safe -replace '-{2,}', '-'
    $safe = $safe.Trim('-', '.', ' ')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'unknown'
    }

    if ($safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).TrimEnd('-', '.', ' ')
    }

    return $safe
}

function Invoke-Evox2NativeCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory = ''
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $command) {
            throw "Executable not found: $FilePath"
        }
        $FilePath = $command.Source
    } else {
        $FilePath = (Resolve-Path -LiteralPath $FilePath).Path
    }

    $savedLocation = $null
    $lines = New-Object System.Collections.Generic.List[string]
    $oldPreference = $ErrorActionPreference
    $exitCode = -1

    try {
        if ($WorkingDirectory) {
            $savedLocation = (Get-Location).Path
            Set-Location -LiteralPath $WorkingDirectory
        }

        # Windows PowerShell may wrap native stderr as ErrorRecord objects even
        # when the native program is only printing normal diagnostic output.
        $ErrorActionPreference = 'Continue'

        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $lines.Add($_.ToString())
        }

        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
        if ($savedLocation) {
            Set-Location -LiteralPath $savedLocation
        }
    }

    [PSCustomObject]@{
        FilePath  = $FilePath
        Arguments = @($ArgumentList)
        ExitCode  = $exitCode
        Lines     = @($lines)
        Text      = ($lines -join [Environment]::NewLine)
    }
}

function Get-Evox2RepoRoot {
    [CmdletBinding()]
    param(
        [string]$StartPath = $PSScriptRoot
    )

    $candidate = [IO.Path]::GetFullPath($StartPath)
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -Parent $candidate
    }

    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($git) {
        $probe = Invoke-Evox2NativeCapture -FilePath $git.Source `
            -ArgumentList @('-C', $candidate, 'rev-parse', '--show-toplevel')
        if ($probe.ExitCode -eq 0 -and $probe.Lines.Count -gt 0) {
            return [IO.Path]::GetFullPath($probe.Lines[-1].Trim())
        }
    }

    $current = Get-Item -LiteralPath $candidate
    while ($current) {
        if (Test-Path -LiteralPath (Join-Path $current.FullName '.git')) {
            return $current.FullName
        }
        $current = $current.Parent
    }

    throw "Could not locate the repository root from: $StartPath"
}

function Get-Evox2GitMetadata {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = ''
    )

    if (-not $RepoRoot) {
        $RepoRoot = Get-Evox2RepoRoot
    }
    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

    $git = (Get-Command git -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source

    function Invoke-GitText {
        param([string[]]$Arguments)
        $result = Invoke-Evox2NativeCapture -FilePath $git `
            -ArgumentList (@('-C', $RepoRoot) + $Arguments)
        if ($result.ExitCode -ne 0) {
            throw "git command failed: git $($Arguments -join ' ')"
        }
        return $result.Text.Trim()
    }

    $commit = Invoke-GitText @('rev-parse', 'HEAD')
    $shortCommit = Invoke-GitText @('rev-parse', '--short=10', 'HEAD')
    $branch = Invoke-GitText @('branch', '--show-current')
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = '(detached)'
    }

    $status = Invoke-GitText @('status', '--porcelain=v1', '--untracked-files=all')
    $dirty = -not [string]::IsNullOrWhiteSpace($status)

    $dirtyFingerprint = $null
    if ($dirty) {
        $unstaged = Invoke-GitText @('diff', '--binary', '--no-ext-diff')
        $staged = Invoke-GitText @('diff', '--cached', '--binary', '--no-ext-diff')
        $fingerprintText = @(
            'STATUS'
            $status
            'UNSTAGED'
            $unstaged
            'STAGED'
            $staged
        ) -join "`n"

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($fingerprintText)
            $dirtyFingerprint = (
                $sha.ComputeHash($bytes) |
                ForEach-Object { $_.ToString('x2') }
            ) -join ''
        } finally {
            $sha.Dispose()
        }
    }

    $remoteUrl = $null
    $remote = Invoke-Evox2NativeCapture -FilePath $git `
        -ArgumentList @('-C', $RepoRoot, 'config', '--get', 'remote.origin.url')
    if ($remote.ExitCode -eq 0) {
        $remoteUrl = $remote.Text.Trim()
    }

    [PSCustomObject]@{
        RepoRoot         = $RepoRoot
        Commit           = $commit
        ShortCommit      = $shortCommit
        Branch           = $branch
        Dirty            = $dirty
        DirtyFingerprint = $dirtyFingerprint
        RemoteOrigin     = $remoteUrl
        StatusPorcelain  = if ($dirty) { @($status -split "`r?`n") } else { @() }
    }
}

function Get-Evox2FileIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$Sha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    $hash = $null

    if ($Sha256) {
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    [PSCustomObject]@{
        Path             = $item.FullName
        Name             = $item.Name
        LengthBytes      = [long]$item.Length
        LastWriteTimeUtc = $item.LastWriteTimeUtc.ToString('o')
        Sha256           = $hash
    }
}

function Get-Evox2ExecutableMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [switch]$SkipHash
    )

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Executable not found: $Executable"
    }

    $Executable = (Resolve-Path -LiteralPath $Executable).Path
    $exeDir = Split-Path -Parent $Executable
    $identity = Get-Evox2FileIdentity -Path $Executable -Sha256:(-not $SkipHash)

    $version = Invoke-Evox2NativeCapture -FilePath $Executable `
        -ArgumentList @('--version') `
        -WorkingDirectory $exeDir

    $text = $version.Text
    $buildNumber = $null
    $commit = $null
    $compiler = $null
    $versionString = $null

    $match = [regex]::Match(
        $text,
        '(?im)^\s*version:\s*(.+?)\s+\(build\s+(\d+),\s*commit\s+([0-9a-f]+)\)'
    )
    if ($match.Success) {
        $versionString = $match.Groups[1].Value.Trim()
        $buildNumber = [int]$match.Groups[2].Value
        $commit = $match.Groups[3].Value
    }

    if ($null -eq $buildNumber) {
        $match = [regex]::Match($text, '(?im)\bbuild\s+(\d+)\s+\(([0-9a-f]+)\)')
        if ($match.Success) {
            $buildNumber = [int]$match.Groups[1].Value
            $commit = $match.Groups[2].Value
        }
    }

    if ($null -eq $buildNumber) {
        $match = [regex]::Match($text, '(?im)\bb(\d+)-([0-9a-f]{7,40})\b')
        if ($match.Success) {
            $buildNumber = [int]$match.Groups[1].Value
            $commit = $match.Groups[2].Value
        }
    }

    $compilerMatch = [regex]::Match(
        $text,
        '(?im)\bbuilt with\s+(.+?)(?:\s+for\s+.+)?\s*$'
    )
    if ($compilerMatch.Success) {
        $compiler = $compilerMatch.Groups[1].Value.Trim()
    }

    [PSCustomObject]@{
        Path            = $Executable
        Name            = [IO.Path]::GetFileName($Executable)
        Directory       = $exeDir
        Sha256          = $identity.Sha256
        LengthBytes     = $identity.LengthBytes
        Version         = $versionString
        BuildNumber     = $buildNumber
        Commit          = $commit
        Compiler        = $compiler
        VersionExitCode = $version.ExitCode
        VersionText     = $text
    }
}

function Get-Evox2DeviceMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        throw "Executable not found: $Executable"
    }

    $Executable = (Resolve-Path -LiteralPath $Executable).Path
    $exeDir = Split-Path -Parent $Executable
    $result = Invoke-Evox2NativeCapture -FilePath $Executable `
        -ArgumentList @('--list-devices') `
        -WorkingDirectory $exeDir

    $devices = New-Object System.Collections.Generic.List[object]

    foreach ($line in $result.Lines) {
        $m = [regex]::Match(
            $line,
            '^\s*([A-Za-z][A-Za-z0-9_-]*\d+)\s*:\s*(.+?)(?:\s+\((\d+)\s+MiB,\s*(\d+)\s+MiB free\))?\s*$'
        )

        if (-not $m.Success) {
            continue
        }

        $deviceId = $m.Groups[1].Value
        $deviceName = $m.Groups[2].Value.Trim()
        $totalMiB = $null
        $freeMiB = $null

        if ($m.Groups[3].Success) {
            $totalMiB = [int64]$m.Groups[3].Value
            $freeMiB = [int64]$m.Groups[4].Value
        }

        $backend = switch -Regex ($deviceId) {
            '^Vulkan' { 'Vulkan'; break }
            '^ROCm'   { 'ROCm'; break }
            '^CUDA'   { 'CUDA'; break }
            '^Metal'  { 'Metal'; break }
            '^SYCL'   { 'SYCL'; break }
            '^CPU'    { 'CPU'; break }
            default   { 'Unknown' }
        }

        $devices.Add([PSCustomObject]@{
            Id       = $deviceId
            Backend  = $backend
            Name     = $deviceName
            TotalMiB = $totalMiB
            FreeMiB  = $freeMiB
            RawLine  = $line.Trim()
        })
    }

    $gpuBackends = @(
        $devices |
        Where-Object { $_.Backend -notin @('CPU', 'Unknown') } |
        Select-Object -ExpandProperty Backend -Unique
    )

    $backendDetected = if ($gpuBackends.Count -eq 1) {
        $gpuBackends[0]
    } elseif ($gpuBackends.Count -gt 1) {
        'Mixed'
    } else {
        'Unknown'
    }

    [PSCustomObject]@{
        BackendDetected = $backendDetected
        # PowerShell 5.1 can throw "Argument types do not match" when
        # array-subexpression syntax is applied directly to List[object].
        # ToArray() avoids that Windows PowerShell compatibility bug.
        Devices          = $devices.ToArray()
        ExitCode         = $result.ExitCode
        RawText          = $result.Text
    }
}

function Get-Evox2SystemMetadata {
    [CmdletBinding()]
    param()

    $os = $null
    $computer = $null
    $cpu = $null
    $video = @()

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    } catch {}

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    } catch {}

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop |
            Select-Object -First 1
    } catch {}

    try {
        $video = @(
            Get-CimInstance Win32_VideoController -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    Name          = $_.Name
                    DriverVersion = $_.DriverVersion
                    DriverDate    = [string]$_.DriverDate
                    AdapterRAM    = $_.AdapterRAM
                    PNPDeviceID   = $_.PNPDeviceID
                }
            }
        )
    } catch {}

    [PSCustomObject]@{
        ComputerName       = $env:COMPUTERNAME
        UserName           = $env:USERNAME
        OsCaption          = if ($os) { $os.Caption } else { $null }
        OsVersion          = if ($os) { $os.Version } else { $null }
        OsBuildNumber      = if ($os) { $os.BuildNumber } else { $null }
        TotalPhysicalBytes = if ($computer) { [int64]$computer.TotalPhysicalMemory } else { $null }
        CpuName            = if ($cpu) { $cpu.Name } else { $null }
        CpuLogicalCount    = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { $null }
        VideoControllers   = $video
        PowerShellVersion  = $PSVersionTable.PSVersion.ToString()
        CapturedAt         = (Get-Date).ToString('o')
    }
}

function Read-Evox2BuildManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )

    $Executable = (Resolve-Path -LiteralPath $Executable).Path
    $manifestPath = Join-Path (Split-Path -Parent $Executable) 'evox2-build.json'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    } catch {
        throw "Invalid build manifest: $manifestPath`n$($_.Exception.Message)"
    }
}

function Write-Evox2Json {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [ValidateRange(3, 64)]
        [int]$Depth = 16
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = $InputObject | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($fullPath, $json + [Environment]::NewLine, $utf8NoBom)
}

function ConvertTo-Evox2CanonicalObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($InputObject.Keys | Sort-Object { [string]$_ })) {
            $ordered[[string]$key] = ConvertTo-Evox2CanonicalObject -InputObject $InputObject[$key]
        }
        return $ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $values = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $values.Add((ConvertTo-Evox2CanonicalObject -InputObject $item))
        }
        # Windows PowerShell 5.1 can throw "Argument types do not match"
        # when @() is applied directly to List[object]. Materialize a real
        # object[] instead.
        return $values.ToArray()
    }

    $ordered = [ordered]@{}
    foreach ($property in @($InputObject.PSObject.Properties | Sort-Object Name)) {
        $ordered[$property.Name] = ConvertTo-Evox2CanonicalObject -InputObject $property.Value
    }
    return $ordered
}

function Get-Evox2ConditionId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Condition,

        [ValidateRange(6, 64)]
        [int]$Length = 12
    )

    $canonical = ConvertTo-Evox2CanonicalObject -InputObject $Condition
    $json = $canonical | ConvertTo-Json -Depth 32 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()

    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $hash = (
            $sha.ComputeHash($bytes) |
            ForEach-Object { $_.ToString('x2') }
        ) -join ''
    } finally {
        $sha.Dispose()
    }

    return $hash.Substring(0, $Length)
}

function Test-Evox2RuntimeArtifacts {
    [CmdletBinding()]
    param([string]$Executable, [AllowNull()][object]$Manifest)

    if ($null -eq $Manifest) {
        return [PSCustomObject]@{ Status = 'MissingManifest'; Digest = $null; Artifacts = @(); Issues = @() }
    }
    $binDir = Split-Path -Parent $Executable
    $requiredNames = @([IO.Path]::GetFileName($Executable))
    $dllNames = @('llama.dll', 'ggml.dll', 'ggml-base.dll', 'ggml-vulkan.dll', 'ggml-hip.dll', 'llama-cli.dll', 'llama-server.dll', 'llama-common.dll')
    $dllNames += @(Get-ChildItem -LiteralPath $binDir -Filter 'ggml-cpu*.dll' -File | ForEach-Object { $_.Name })
    $requiredNames += @($dllNames | Where-Object { Test-Path -LiteralPath (Join-Path $binDir $_) -PathType Leaf })
    # Include any additional bounded ggml/llama runtime DLLs already recorded by the manifest.
    $recorded = if ($Manifest.PSObject.Properties['Artifacts']) { @($Manifest.Artifacts) } else { @() }
    $requiredNames += @($recorded | Where-Object { $_.Name -match '^(ggml|llama).*\.dll$' } |
        ForEach-Object { $_.Name })
    $artifacts = @(); $issues = @(); $mismatch = $false
    foreach ($name in @($requiredNames | Sort-Object -Unique)) {
        if ([IO.Path]::GetFileName($name) -ne $name) { throw 'Invalid runtime artifact name in manifest.' }
        $file = Join-Path $binDir $name
        $expected = @($recorded | Where-Object { $_.Name -eq $name })
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            $issues += "Missing runtime artifact: $name"; $mismatch = $true; continue
        }
        $actual = Get-Evox2FileIdentity -Path $file -Sha256
        $artifacts += $actual
        if ($expected.Count -ne 1 -or [string]::IsNullOrWhiteSpace($expected[0].Sha256)) {
            $issues += "Unrecorded runtime artifact: $name"; continue
        }
        if ($actual.Sha256 -ne $expected[0].Sha256) {
            $issues += "Runtime artifact hash mismatch: $name"; $mismatch = $true
        }
    }
    $digest = $null
    $status = if ($mismatch) { 'Mismatch' } elseif ($issues.Count) { 'Unverified' } else { 'Verified' }
    if ($status -eq 'Verified') {
        $text = (@($artifacts | Sort-Object Name | ForEach-Object { "$($_.Name.ToLowerInvariant())=$($_.Sha256)" }) -join "`n")
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $digest = ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)) |
                ForEach-Object { $_.ToString('x2') }) -join ''
        } finally { $sha.Dispose() }
    }
    return [PSCustomObject]@{ Status = $status; Digest = $digest; Artifacts = @($artifacts); Issues = @($issues) }
}

function Get-Evox2LlamaIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string]$RepoRoot = '',

        [switch]$SkipExecutableHash,

        [switch]$SkipSystem
    )

    $Executable = (Resolve-Path -LiteralPath $Executable).Path

    $manifest = Read-Evox2BuildManifest -Executable $Executable
    $exe = Get-Evox2ExecutableMetadata -Executable $Executable `
        -SkipHash:$SkipExecutableHash
    $runtimeArtifacts = Test-Evox2RuntimeArtifacts -Executable $Executable -Manifest $manifest
    if ($runtimeArtifacts.Status -eq 'Mismatch') {
        throw ($runtimeArtifacts.Issues -join '; ')
    }
    $device = Get-Evox2DeviceMetadata -Executable $Executable

    $git = $null
    if ($RepoRoot) {
        try {
            $git = Get-Evox2GitMetadata -RepoRoot $RepoRoot
        } catch {}
    }

    $system = $null
    if (-not $SkipSystem) {
        $system = Get-Evox2SystemMetadata
    }

    [PSCustomObject]@{
        Executable    = $exe
        Device        = $device
        BuildManifest = $manifest
        RuntimeArtifacts = $runtimeArtifacts
        Git           = $git
        System        = $system
    }
}

Export-ModuleMember -Function @(
    'Set-Evox2Utf8Console',
    'ConvertTo-Evox2SafeName',
    'Invoke-Evox2NativeCapture',
    'Get-Evox2RepoRoot',
    'Get-Evox2GitMetadata',
    'Get-Evox2FileIdentity',
    'Get-Evox2ExecutableMetadata',
    'Get-Evox2DeviceMetadata',
    'Get-Evox2SystemMetadata',
    'Read-Evox2BuildManifest',
    'Write-Evox2Json',
    'ConvertTo-Evox2CanonicalObject',
    'Get-Evox2ConditionId',
    'Test-Evox2RuntimeArtifacts',
    'Get-Evox2LlamaIdentity'
)
