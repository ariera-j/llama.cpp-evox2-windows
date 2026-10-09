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

Export-ModuleMember -Function @(
    'Resolve-Evox2DependencyCacheRoot',
    'Initialize-Evox2DependencyCache',
    'Save-Evox2DependencyCacheFromBuild'
)