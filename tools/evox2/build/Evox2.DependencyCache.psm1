#requires -Version 5.1

Set-StrictMode -Version Latest

function ConvertTo-Evox2CMakePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return ([IO.Path]::GetFullPath($Path) -replace '\\', '/')
}

function Get-Evox2CMakeStringValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Variable
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $text = [IO.File]::ReadAllText($Path)
    $pattern = 'set\s*\(\s*' + [regex]::Escape($Variable) + '\s+"([^"]+)"'
    $match = [regex]::Match(
        $text,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function Resolve-Evox2DependencyCacheRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [AllowEmptyString()]
        [string]$RequestedRoot = '',

        [bool]$Explicit = $false
    )

    $RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
    $candidate = $null
    $createIfMissing = $false

    if ($Explicit) {
        if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
            return $null
        }

        $candidate = $RequestedRoot
        $createIfMissing = $true
    } elseif (-not [string]::IsNullOrWhiteSpace($env:EVOX2_DEPS_ROOT)) {
        $candidate = $env:EVOX2_DEPS_ROOT
        $createIfMissing = $true
    } else {
        $parent = Split-Path -Parent $RepoRoot
        $sibling = Join-Path $parent 'evox2-deps'

        if (Test-Path -LiteralPath $sibling -PathType Container) {
            $candidate = $sibling
        } else {
            return $null
        }
    }

    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    $candidate = [IO.Path]::GetFullPath($candidate)

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        throw "Dependency cache root is a file: $candidate"
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        if (-not $createIfMissing) {
            return $null
        }

        New-Item -ItemType Directory -Path $candidate -Force | Out-Null
    }

    return $candidate
}

function Test-Evox2BoringSslCheckout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedVersion
    )

    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'CMakeLists.txt') -PathType Leaf)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir '.git'))) {
        return $false
    }

    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $git) {
        $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if (-not $git) {
        return $false
    }

    $head = @(& $git.Source -C $SourceDir rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $head.Count -eq 0) {
        return $false
    }

    $tagRef = "$ExpectedVersion^{commit}"
    $expected = @(& $git.Source -C $SourceDir rev-parse $tagRef 2>$null)
    if ($LASTEXITCODE -ne 0 -or $expected.Count -eq 0) {
        return $false
    }

    if ($head[0].Trim() -ne $expected[0].Trim()) {
        return $false
    }

    $dirty = @(& $git.Source -C $SourceDir status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($dirty.Count -eq 0)
}

function Test-Evox2OpenMpLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    return (
        (Test-Path -LiteralPath (Join-Path $Root 'lib\libomp.lib') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root 'bin\libomp.dll') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Root 'include\omp.h') -PathType Leaf)
    )
}

function Copy-Evox2DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-Evox2DependencyVersions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $boringSslVersion = Get-Evox2CMakeStringValue `
        -Path (Join-Path $RepoRoot 'vendor\cpp-httplib\CMakeLists.txt') `
        -Variable 'BORINGSSL_VERSION'

    $openMpVersion = Get-Evox2CMakeStringValue `
        -Path (Join-Path $RepoRoot 'ggml\src\CMakeLists.txt') `
        -Variable 'GGML_OPENMP_LLVM_VERSION'

    return [PSCustomObject]@{
        BoringSsl = $boringSslVersion
        OpenMp     = $openMpVersion
    }
}

function Initialize-Evox2DependencyCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$BuildDir,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Vulkan', 'ROCm')]
        [string]$Backend,

        [AllowNull()]
        [string]$CacheRoot,

        [string[]]$ExtraCMakeArgs = @(),

        [bool]$PrepareBuildDir = $true
    )

    $versions = Get-Evox2DependencyVersions -RepoRoot $RepoRoot

    $record = [ordered]@{
        Root      = $CacheRoot
        BoringSSL = [ordered]@{
            ExpectedVersion = $versions.BoringSsl
            Source          = $null
            Reused          = $false
            UserOverride    = $false
            Reason          = $null
        }
        OpenMP = if ($Backend -eq 'Vulkan') {
            [ordered]@{
                ExpectedVersion = $versions.OpenMp
                Source          = $null
                BuildSeed       = $null
                Reused          = $false
                Seeded          = $false
                LicensePresent  = $false
                Reason          = $null
            }
        } else {
            $null
        }
        Captured = $null
    }

    $configureArgs = @()

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        $record.BoringSSL.Reason = 'dependency cache disabled or not found'
        if ($null -ne $record.OpenMP) {
            $record.OpenMP.Reason = 'dependency cache disabled or not found'
        }

        return [PSCustomObject]@{
            ConfigureArgs = @()
            Record        = $record
        }
    }

    Write-Host "Dependency cache: $CacheRoot"

    $hasBoringSslOverride = @(
        $ExtraCMakeArgs | Where-Object {
            $_ -match '^-DFETCHCONTENT_SOURCE_DIR_BORINGSSL(?::[^=]+)?='
        }
    ).Count -gt 0

    if ($hasBoringSslOverride) {
        $record.BoringSSL.UserOverride = $true
        $record.BoringSSL.Reason = 'user supplied FETCHCONTENT_SOURCE_DIR_BORINGSSL'
    } elseif ([string]::IsNullOrWhiteSpace($versions.BoringSsl)) {
        $record.BoringSSL.Reason = 'BORINGSSL_VERSION could not be read from source'
    } else {
        $versioned = Join-Path `
            (Join-Path $CacheRoot 'fetchcontent') `
            "boringssl-$($versions.BoringSsl)-src"
        $legacy = Join-Path (Join-Path $CacheRoot 'fetchcontent') 'boringssl-src'

        foreach ($candidate in @($versioned, $legacy)) {
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
                continue
            }

            if (Test-Evox2BoringSslCheckout `
                    -SourceDir $candidate `
                    -ExpectedVersion $versions.BoringSsl) {
                $record.BoringSSL.Source = [IO.Path]::GetFullPath($candidate)
                $record.BoringSSL.Reused = $true
                $configureArgs += (
                    '-DFETCHCONTENT_SOURCE_DIR_BORINGSSL=' +
                    (ConvertTo-Evox2CMakePath -Path $candidate)
                )

                Write-Host "Using cached BoringSSL source: $candidate"
                break
            }

            Write-Warning (
                "Ignoring cached BoringSSL source because it is not a clean checkout " +
                "of $($versions.BoringSsl): $candidate"
            )
        }

        if (-not $record.BoringSSL.Reused) {
            $record.BoringSSL.Reason = (
                'matching cached source not found; CMake may download it once and ' +
                'the wrapper will cache it after configure'
            )
        }
    }

    if ($Backend -eq 'Vulkan') {
        if ([string]::IsNullOrWhiteSpace($versions.OpenMp)) {
            $record.OpenMP.Reason = 'GGML_OPENMP_LLVM_VERSION could not be read from source'
        } else {
            $openMpName = "llvm-openmp-$($versions.OpenMp)-x64"
            $openMpSource = Join-Path (Join-Path $CacheRoot 'openmp') $openMpName
            $openMpDestination = Join-Path (Join-Path $BuildDir '_deps') $openMpName

            $record.OpenMP.Source = [IO.Path]::GetFullPath($openMpSource)
            $record.OpenMP.BuildSeed = [IO.Path]::GetFullPath($openMpDestination)

            if (Test-Evox2OpenMpLayout -Root $openMpSource) {
                $record.OpenMP.Reused = $true
                $record.OpenMP.LicensePresent = (
                    Test-Path -LiteralPath (Join-Path $openMpSource 'LICENSE.TXT') -PathType Leaf
                )

                if ($PrepareBuildDir) {
                    if (-not (Test-Evox2OpenMpLayout -Root $openMpDestination)) {
                        Copy-Evox2DirectoryContents `
                            -Source $openMpSource `
                            -Destination $openMpDestination

                        if (-not (Test-Evox2OpenMpLayout -Root $openMpDestination)) {
                            throw "Failed to seed LLVM OpenMP cache into: $openMpDestination"
                        }

                        $record.OpenMP.Seeded = $true
                        Write-Host "Seeded cached LLVM OpenMP: $openMpDestination"
                    } else {
                        Write-Host "Using existing build-local LLVM OpenMP cache: $openMpDestination"
                    }
                }

                if (-not $record.OpenMP.LicensePresent) {
                    Write-Warning (
                        "Cached LLVM OpenMP runtime has no LICENSE.TXT. " +
                        "CMake may still make a small network request for the license file."
                    )
                }
            } else {
                $record.OpenMP.Reason = (
                    'matching cached runtime not found; CMake may download it once and ' +
                    'the wrapper will cache it after configure'
                )
            }
        }
    }

    return [PSCustomObject]@{
        ConfigureArgs = @($configureArgs)
        Record        = $record
    }
}

function Save-Evox2DependencyCacheFromBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$BuildDir,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Vulkan', 'ROCm')]
        [string]$Backend,

        [AllowNull()]
        [string]$CacheRoot
    )

    $captured = [ordered]@{
        BoringSSL = $false
        OpenMP     = $false
    }

    if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
        return $captured
    }

    $versions = Get-Evox2DependencyVersions -RepoRoot $RepoRoot

    if (-not [string]::IsNullOrWhiteSpace($versions.BoringSsl)) {
        $fetchRoot = Join-Path $CacheRoot 'fetchcontent'
        $versioned = Join-Path $fetchRoot "boringssl-$($versions.BoringSsl)-src"
        $legacy = Join-Path $fetchRoot 'boringssl-src'

        $alreadyCached = $false
        foreach ($candidate in @($versioned, $legacy)) {
            if ((Test-Path -LiteralPath $candidate -PathType Container) -and
                (Test-Evox2BoringSslCheckout `
                    -SourceDir $candidate `
                    -ExpectedVersion $versions.BoringSsl)) {
                $alreadyCached = $true
                break
            }
        }

        if (-not $alreadyCached) {
            $buildSource = Join-Path (Join-Path $BuildDir '_deps') 'boringssl-src'

            if ((Test-Path -LiteralPath $buildSource -PathType Container) -and
                (Test-Evox2BoringSslCheckout `
                    -SourceDir $buildSource `
                    -ExpectedVersion $versions.BoringSsl)) {
                if (-not (Test-Path -LiteralPath $versioned)) {
                    New-Item -ItemType Directory -Path $fetchRoot -Force | Out-Null
                    Copy-Evox2DirectoryContents `
                        -Source $buildSource `
                        -Destination $versioned

                    if (Test-Evox2BoringSslCheckout `
                            -SourceDir $versioned `
                            -ExpectedVersion $versions.BoringSsl) {
                        $captured.BoringSSL = $true
                        Write-Host "Cached BoringSSL source: $versioned"
                    } else {
                        Write-Warning "Copied BoringSSL cache failed validation: $versioned"
                    }
                } else {
                    Write-Warning (
                        "BoringSSL cache target exists but is not a valid " +
                        "$($versions.BoringSsl) checkout: $versioned"
                    )
                }
            }
        }
    }

    if ($Backend -eq 'Vulkan' -and
        -not [string]::IsNullOrWhiteSpace($versions.OpenMp)) {
        $openMpName = "llvm-openmp-$($versions.OpenMp)-x64"
        $cacheTarget = Join-Path (Join-Path $CacheRoot 'openmp') $openMpName

        if (-not (Test-Evox2OpenMpLayout -Root $cacheTarget)) {
            $buildSource = Join-Path (Join-Path $BuildDir '_deps') $openMpName

            if (Test-Evox2OpenMpLayout -Root $buildSource) {
                Copy-Evox2DirectoryContents `
                    -Source $buildSource `
                    -Destination $cacheTarget

                if (Test-Evox2OpenMpLayout -Root $cacheTarget) {
                    $captured.OpenMP = $true
                    Write-Host "Cached LLVM OpenMP runtime: $cacheTarget"
                } else {
                    Write-Warning "Copied LLVM OpenMP cache failed validation: $cacheTarget"
                }
            }
        }
    }

    return $captured
}

function Invoke-Evox2DependencyCommand {
    param([string]$Exe, [string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe exited $LASTEXITCODE while preparing the dependency cache."
    }
}

function Assert-Evox2CacheItem {
    param([string]$Path, [bool]$Directory)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -ne $Directory -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected cache item type or reparse point: $Path"
    }
}

function Assert-Evox2CacheHashes {
    param([string]$Root, [System.Collections.IDictionary]$Hashes)
    foreach ($relative in $Hashes.Keys) {
        $path = Join-Path $Root $relative
        Assert-Evox2CacheItem $path $false
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $Hashes[$relative]) {
            throw "SHA-256 mismatch: $path"
        }
    }
}

function Save-Evox2VerifiedDownload {
    param([string]$Url, [string]$Path, [string]$Sha256)
    Invoke-Evox2DependencyCommand curl.exe @('--fail', '--location', '--silent', '--show-error',
        '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '20',
        '--max-time', '600', '--output', $Path, $Url)
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Sha256) {
        throw "SHA-256 mismatch: $Url"
    }
}

function Publish-Evox2Dependency {
    param([string]$Destination, [scriptblock]$Validate, [scriptblock]$Acquire, [bool]$AllowDownload)
    $parent = Split-Path -Parent $Destination
    if (Test-Path -LiteralPath $parent) {
        Assert-Evox2CacheItem $parent $true
    }
    if (Test-Path -LiteralPath $Destination) {
        & $Validate $Destination
        Write-Host "Verified cached dependency: $Destination"
        return
    }
    if (!$AllowDownload) { throw "Required dependency is missing in offline or preflight mode: $Destination" }

    [IO.Directory]::CreateDirectory($parent) | Out-Null
    Assert-Evox2CacheItem $parent $true
    $lockPath = "$Destination.lock"
    $lock = $null
    $deadline = [Diagnostics.Stopwatch]::StartNew()
    while (!$lock) {
        if (Test-Path -LiteralPath $lockPath) { Assert-Evox2CacheItem $lockPath $false }
        try {
            $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch [IO.IOException] {
            $code = $_.Exception.HResult -band 65535
            if ($code -notin 32, 33 -or $deadline.Elapsed.TotalMinutes -ge 12) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    try {
        if (Test-Path -LiteralPath $Destination) {
            & $Validate $Destination
            Write-Host "Verified dependency published by another process: $Destination"
            return
        }
        $stage = Join-Path $parent ('.stage-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        try {
            $entry = Join-Path $stage 'entry'
            & $Acquire $stage $entry
            & $Validate $entry
            [IO.Directory]::Move($entry, $Destination)
            Write-Host "Published verified dependency: $Destination"
        } finally {
            Remove-Item -LiteralPath $stage -Recurse -Force
        }
    } finally {
        $lock.Dispose()
    }
}

function Assert-Evox2DependencyInputs {
    param([string]$RepoRoot, [string]$AuditedCommit)

    # CMake entry points, nested projects, modules and templates can all
    # introduce a fetch or override an acquisition setting in another file.
    $cmakeInputs = @(
        ':(icase,glob)**/CMakeLists.txt',
        ':(icase,glob)**/*.cmake',
        ':(icase,glob)**/*.cmake.in',
        # ADLX is built separately and is not reachable from llama.cpp CMake.
        ':(exclude,icase,literal)tools/evox2/adlx-gpu-monitor/CMakeLists.txt'
    )
    # ui-assets.cmake can run npm ci, including local package dependencies.
    # Git submodules can introduce another source repository.
    $packageInputs = @(
        ':(icase,glob)ui/**/package.json',
        ':(icase,glob)ui/**/package-lock.json',
        ':(icase,glob)ui/**/npm-shrinkwrap.json',
        ':(icase,glob)ui/**/.npmrc',
        ':(icase,literal).gitmodules'
    )

    # The root and ggml projects search these module directories before using
    # CMake's bundled modules. An ignored file there can shadow a bundled one.
    $ignoredModules = @(
        ':(icase,glob)cmake/**/*.cmake',
        ':(icase,glob)ggml/cmake/**/*.cmake',
        ':(icase,literal)ui/apps/chat/.npmrc'
    )
    $gitArgs = @('-C', $RepoRoot, '-c', 'core.quotePath=false')
    # This reviewed ggml-base source-list addition enables the ROCmFPx codecs.
    # Any other change to the file still requires a dependency review.
    $rocmfpxBuildPath = 'ggml/src/CMakeLists.txt'
    $rocmfpxBuildBlob = 'cfdb9a0ac0fe698592cf448657fc81bf7d247cdc'
    $reviewedRocmFpxBuild = $false
    if (Test-Path -LiteralPath (Join-Path $RepoRoot $rocmfpxBuildPath) -PathType Leaf) {
        $blob = Invoke-Evox2DependencyCommand git ($gitArgs + @(
            'hash-object', "--path=$rocmfpxBuildPath", '--', $rocmfpxBuildPath
        ))
        $reviewedRocmFpxBuild = $blob -ceq $rocmfpxBuildBlob
    }

    $issues = @(foreach ($inputGroup in @(
        @{ Paths = $cmakeInputs; Reason = 'CMake configuration can change dependency acquisition' },
        @{ Paths = $packageInputs; Reason = 'package or submodule configuration can change dependency sources' }
    )) {
        $tracked = Invoke-Evox2DependencyCommand git ($gitArgs + @(
            'diff', '--name-only', '--no-ext-diff', '--no-renames', '--ignore-submodules=none', $AuditedCommit, '--'
        ) + $inputGroup.Paths)
        if ($reviewedRocmFpxBuild -and $AuditedCommit -ceq 'f5e6915c28f10330885fcb9243a93ae98d3115ab') {
            $tracked = @($tracked | Where-Object { $_ -cne $rocmfpxBuildPath })
        }
        $untracked = Invoke-Evox2DependencyCommand git ($gitArgs + @(
            'ls-files', '--others', '--exclude-standard', '--'
        ) + $inputGroup.Paths)
        foreach ($path in @($tracked) + @($untracked) | Sort-Object -Unique) {
            if ($path) { "${path}: $($inputGroup.Reason)" }
        }
    })

    $issues += @(Invoke-Evox2DependencyCommand git ($gitArgs + @(
        'ls-files', '--others', '--ignored', '--exclude-standard', '--'
    ) + $ignoredModules) | ForEach-Object {
        "${_}: ignored local module or npm configuration can override dependency acquisition"
    })

    if ($issues) {
        throw ("Dependency inputs differ from reviewed baseline $AuditedCommit. Review these files before building:`n" +
            ($issues -join "`n"))
    }
}

function Initialize-Evox2CodexDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$CacheRoot,
        [Parameter(Mandatory)][ValidateSet('Vulkan', 'ROCm')][string]$Backend,
        [switch]$AllowDownload
    )

    $versions = Get-Evox2DependencyVersions $RepoRoot
    $auditedCommit = if ($versions.BoringSsl -eq '0.20261020.0') {
        '2bce03311306c3d0367349e85db4420455ab283a'
    } else {
        'f5e6915c28f10330885fcb9243a93ae98d3115ab'
    }
    Assert-Evox2DependencyInputs -RepoRoot $RepoRoot -AuditedCommit $auditedCommit

    $sslCmake = Join-Path $RepoRoot 'vendor\cpp-httplib\CMakeLists.txt'
    $sslUrl = Get-Evox2CMakeStringValue $sslCmake 'BORINGSSL_GIT'
    if ($sslUrl -cne 'https://boringssl.googlesource.com/boringssl') {
        throw 'Unreviewed BoringSSL source.'
    }
    $downloadEnabled = $AllowDownload.IsPresent
    switch ($versions.BoringSsl) {
        '0.20261105.0' {
            $sslCommit = '3dc4b63808921e914a3fb1fa61869abc3938781b'
            $expectedOmpVersion = '22.1.8'
        }
        '0.20261020.0' {
            # Preserve the previous main wrapper's cache-only policy.
            $sslCommit = 'd3bf4795ad5b79d646cddf2fec687da5b9b502db'
            $expectedOmpVersion = '20.1.8'
            $downloadEnabled = $false
        }
        default { throw 'Unreviewed BoringSSL version.' }
    }
    $sslPath = Join-Path $CacheRoot "fetchcontent\boringssl-$($versions.BoringSsl)-src"
    $sslValidate = {
        param($path)
        Assert-Evox2CacheItem $path $true
        Assert-Evox2CacheItem (Join-Path $path '.git') $true
        if (Test-Path -LiteralPath (Join-Path $path '.git\objects\info\alternates')) {
            throw "BoringSSL checkout uses borrowed objects: $path"
        }
        if (!(Test-Evox2BoringSslCheckout -SourceDir $path -ExpectedVersion $versions.BoringSsl)) {
            throw "BoringSSL checkout is incomplete, dirty, or does not match its tag: $path"
        }
        $origin = Invoke-Evox2DependencyCommand git @('-C', $path, 'config', '--local', '--get', 'remote.origin.url')
        $head = Invoke-Evox2DependencyCommand git @('-C', $path, 'rev-parse', 'HEAD')
        if ($origin -cne $sslUrl -or $head -ne $sslCommit) {
            throw "BoringSSL origin or pinned SHA mismatch: $path"
        }
        Write-Host "Verified BoringSSL $($versions.BoringSsl) $head from $origin"
    }
    $sslAcquire = {
        param($stage, $entry)
        Invoke-Evox2DependencyCommand git @('init', '--quiet', $entry)
        Invoke-Evox2DependencyCommand git @('-C', $entry, 'remote', 'add', 'origin', $sslUrl)
        $tag = "refs/tags/$($versions.BoringSsl)"
        Invoke-Evox2DependencyCommand git @('-C', $entry, '-c', 'credential.helper=', '-c', 'http.lowSpeedLimit=1024',
            '-c', 'http.lowSpeedTime=60', 'fetch', '--quiet', '--no-tags', '--depth', '1', 'origin', "${tag}:${tag}")
        Invoke-Evox2DependencyCommand git @('-C', $entry, '-c', 'core.longpaths=true', 'checkout', '--detach', '--quiet', $sslCommit)
    }

    Assert-Evox2CacheItem (Split-Path -Parent $CacheRoot) $true
    if (Test-Path -LiteralPath $CacheRoot) { Assert-Evox2CacheItem $CacheRoot $true }
    if ($Backend -eq 'Vulkan') {
        $ompCmake = Join-Path $RepoRoot 'ggml\src\CMakeLists.txt'
        # The reviewed x64 branch provides the first installer SHA.
        $installerSha = Get-Evox2CMakeStringValue $ompCmake 'GGML_OPENMP_INSTALLER_SHA256'
        $licenseSha = Get-Evox2CMakeStringValue $ompCmake 'GGML_OPENMP_LICENSE_SHA256'
        $ompVersion = $versions.OpenMp
        if ($ompVersion -ne $expectedOmpVersion -or $installerSha -notmatch '^[0-9a-f]{64}$' -or $licenseSha -notmatch '^[0-9a-f]{64}$') {
            throw 'Unreviewed LLVM OpenMP version or missing upstream hashes.'
        }
        $ompPath = Join-Path $CacheRoot "openmp\llvm-openmp-$ompVersion-x64"
        $ompHashes = [ordered]@{
            'LICENSE.TXT' = $licenseSha
            'bin\libomp.dll' = '1e4222f195d84e7355109d778e751dfe3c085e42c947f7fe3d7853181329dd40'
            'include\omp.h' = 'cb9ab6f531f893ed38634f071417459d147607e1cd2adae0e382dff5e98f18fd'
            'lib\libomp.lib' = '3f8f26586db975f83db95dac80ef1a264e9c2b65dcb2ddb2d1a9318d2e01940d'
        }
        if ($ompVersion -eq '20.1.8') {
            $ompHashes['bin\libomp.dll'] = 'a12116ba72d1d6820407cf30be23da04ce79d6bb8a71a5ee71759c5a1faa6f1c'
            $ompHashes['include\omp.h'] = '098fc2aa433072427dc68d8c289ca14fc871142e615e0064614419bb9bc15905'
            $ompHashes['lib\libomp.lib'] = '7fc644ff5c7ff8cc5ab69c1301371a1fb6f3c7a6bef25b82155c609527de956c'
        }
        $ompValidate = {
            param($path)
            foreach ($directory in $path, "$path\bin", "$path\include", "$path\lib") {
                Assert-Evox2CacheItem $directory $true
            }
            Assert-Evox2CacheHashes $path $ompHashes
        }
        $ompAcquire = {
            param($stage, $entry)
            $installer = Join-Path $stage 'llvm.exe'
            $extract = Join-Path $stage 'extract'
            [IO.Directory]::CreateDirectory($entry) | Out-Null
            Save-Evox2VerifiedDownload "https://github.com/llvm/llvm-project/releases/download/llvmorg-$ompVersion/LLVM-$ompVersion-win64.exe" $installer $installerSha
            Save-Evox2VerifiedDownload "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-$ompVersion/openmp/LICENSE.TXT" (Join-Path $entry 'LICENSE.TXT') $licenseSha
            $sevenZip = Get-Command 7z.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            $exe = if ($sevenZip) { $sevenZip.Source } else { Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
            Invoke-Evox2DependencyCommand $exe @('e', '-y', "-o$extract", $installer, '-r', 'libomp.lib', 'libomp.dll', 'omp.h')
            foreach ($relative in $ompHashes.Keys | Where-Object { $_ -ne 'LICENSE.TXT' }) {
                $destination = Join-Path $entry $relative
                [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
                Copy-Item -LiteralPath (Join-Path $extract (Split-Path -Leaf $relative)) -Destination $destination
            }
        }
        # Inspect existing OpenMP before any BoringSSL acquisition.
        if (Test-Path -LiteralPath (Split-Path -Parent $ompPath)) {
            Assert-Evox2CacheItem (Split-Path -Parent $ompPath) $true
        }
        if (Test-Path -LiteralPath $ompPath) { & $ompValidate $ompPath }
    }

    Publish-Evox2Dependency $sslPath $sslValidate $sslAcquire $downloadEnabled
    if ($Backend -eq 'Vulkan') {
        Publish-Evox2Dependency $ompPath $ompValidate $ompAcquire $downloadEnabled
    }
}

Export-ModuleMember -Function @(
    'Initialize-Evox2CodexDependencies',
    'Resolve-Evox2DependencyCacheRoot',
    'Initialize-Evox2DependencyCache',
    'Save-Evox2DependencyCacheFromBuild'
)
