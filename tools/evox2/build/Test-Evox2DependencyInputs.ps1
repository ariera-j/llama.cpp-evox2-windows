<#
Prerequisites for HIP-2C-1A audit exception tests:
- Local repository object store must contain commits:
  - f5e6915c28f10330885fcb9243a93ae98d3115ab (pinned b12651 audit baseline)
  - f19d5c75f68ae25bbd5a95b223e67d816c97e2fc (reviewed HIP-2 implementation)
- No network access or external downloads are performed; objects are borrowed read-only via alternates.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'Evox2.DependencyCache.psm1') -Force -PassThru
$sourceRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$repo = Join-Path ([IO.Path]::GetTempPath()) ('evox2-audit-' + [Guid]::NewGuid().ToString('N'))
$hipRepo = Join-Path ([IO.Path]::GetTempPath()) ('evox2-audit-hip-' + [Guid]::NewGuid().ToString('N'))

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory)][string]$TargetRepo,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $output = & git -C $TargetRepo @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed ($LASTEXITCODE): $($Arguments -join ' ')" }
    return $output
}

function Set-FixtureFile {
    param(
        [Parameter(Mandatory)][string]$TargetRepo,
        [Parameter(Mandatory)][string]$Relative,
        [Parameter(Mandatory)][string]$Content
    )
    $path = Join-Path $TargetRepo $Relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $Content + "`n")
}

function Assert-Audit {
    param(
        [string[]]$Expected = @(),
        [string]$TargetRepo = $repo,
        [string]$Base = $baseline
    )
    $failure = $null
    try {
        & $module { param($root, $baseCommit) Assert-Evox2DependencyInputs $root $baseCommit } $TargetRepo $Base
    } catch {
        $failure = $_.Exception.Message
    }
    if ($Expected.Count -eq 0) {
        if ($failure) { throw "Unexpected audit rejection: $failure" }
        return
    }
    foreach ($pattern in $Expected) {
        if ($failure -notlike "*$pattern*") { throw "Expected '$pattern' in audit rejection. Actual: $failure" }
    }
}

[IO.Directory]::CreateDirectory($repo) | Out-Null
[IO.Directory]::CreateDirectory($hipRepo) | Out-Null
try {
    $null = Invoke-FixtureGit $repo @('init', '--quiet')
    Set-FixtureFile $repo '.gitignore' '/cmake/FindExample.cmake'
    Set-FixtureFile $repo 'CMakeLists.txt' 'include(cmake/dependency.cmake)'
    Set-FixtureFile $repo 'cmake/dependency.cmake' 'set(DEP_URL "https://example.invalid/original")'
    Set-FixtureFile $repo 'src/example.cpp' 'int example = 0;'
    Set-FixtureFile $repo 'ui/apps/chat/package-lock.json' '{}'
    $null = Invoke-FixtureGit $repo @('add', '--', '.')
    $null = Invoke-FixtureGit $repo @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'baseline')
    $baseline = (Invoke-FixtureGit $repo @('rev-parse', 'HEAD')).Trim()
    Assert-Audit

    Set-FixtureFile $repo 'src/example.cpp' 'int example = 1;'
    Set-FixtureFile $repo 'ggml/src/shaders/new.comp' '// shader source'
    Set-FixtureFile $repo 'tools/evox2/adlx-gpu-monitor/CMakeLists.txt' '# standalone project'
    Assert-Audit

    Set-FixtureFile $repo 'cmake/dependency.cmake' 'set(DEP_URL "https://example.invalid/changed")'
    Set-FixtureFile $repo 'ggml/src/new/CMakeLists.txt' 'include(FetchContent)'
    Set-FixtureFile $repo 'ggml/src/host-toolchain.cmake.in' '# template'
    Set-FixtureFile $repo 'cmake/FindExample.cmake' '# ignored module'
    Set-FixtureFile $repo '.gitmodules' '# new submodule declaration'
    Remove-Item -LiteralPath (Join-Path $repo 'ui/apps/chat/package-lock.json')
    Assert-Audit @(
        'cmake/dependency.cmake: CMake configuration',
        'ggml/src/new/CMakeLists.txt: CMake configuration',
        'ggml/src/host-toolchain.cmake.in: CMake configuration',
        'cmake/FindExample.cmake: ignored local module',
        '.gitmodules: package or submodule',
        'ui/apps/chat/package-lock.json: package or submodule'
    )

    $null = Invoke-FixtureGit $repo @('add', '--', 'ggml/src/new/CMakeLists.txt')
    Assert-Audit @('ggml/src/new/CMakeLists.txt: CMake configuration')

    # HIP-2C-1A exception tests using local Git objects in an isolated temporary repository
    $auditBaseline = 'f5e6915c28f10330885fcb9243a93ae98d3115ab'
    $reviewedHipCommit = 'f19d5c75f68ae25bbd5a95b223e67d816c97e2fc'
    $null = Invoke-FixtureGit $sourceRepo @('rev-parse', '--verify', "$auditBaseline^{commit}")
    $null = Invoke-FixtureGit $sourceRepo @('rev-parse', '--verify', "$reviewedHipCommit^{commit}")
    $objectsDir = (Invoke-FixtureGit $sourceRepo @('rev-parse', '--path-format=absolute', '--git-path', 'objects')).Trim()

    $null = Invoke-FixtureGit $hipRepo @('init', '--quiet')
    $alternatesPath = Join-Path $hipRepo '.git\objects\info\alternates'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $alternatesPath)) | Out-Null
    [IO.File]::WriteAllText($alternatesPath, $objectsDir + "`n", [Text.UTF8Encoding]::new($false))

    # Limit checkout to the files under test so temp paths stay well under MAX_PATH
    $null = Invoke-FixtureGit $hipRepo @('sparse-checkout', 'init', '--no-cone')
    $null = Invoke-FixtureGit $hipRepo @('sparse-checkout', 'set', '/CMakeLists.txt', '/ggml/src/ggml-hip/CMakeLists.txt')
    $null = Invoke-FixtureGit $hipRepo @('checkout', '--quiet', '--force', $auditBaseline)
    $null = Invoke-FixtureGit $hipRepo @('checkout', '--quiet', $reviewedHipCommit, '--', 'ggml/src/ggml-hip/CMakeLists.txt')
    $null = Invoke-FixtureGit $hipRepo @('reset', '--quiet', $auditBaseline, '--', 'ggml/src/ggml-hip/CMakeLists.txt')

    $actualBlob = (Invoke-FixtureGit $hipRepo @('hash-object', '--path=ggml/src/ggml-hip/CMakeLists.txt', '--', 'ggml/src/ggml-hip/CMakeLists.txt')).Trim()
    if ($actualBlob -cne 'b683a1d32fd8cf8e3bf15a788b16b1f2c083bd76') {
        throw "Unexpected reviewed HIP CMake blob: $actualBlob"
    }

    # Production 2-argument call allows the exact reviewed HIP-2 blob under the pinned audit baseline
    Assert-Audit -TargetRepo $hipRepo -Base $auditBaseline

    # Coexisting unreviewed CMake change must be rejected
    $rootCmake = Join-Path $hipRepo 'CMakeLists.txt'
    $origRootCmake = [IO.File]::ReadAllText($rootCmake)
    [IO.File]::WriteAllText($rootCmake, $origRootCmake + "`n# unreviewed change`n")
    Assert-Audit @('CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $auditBaseline
    [IO.File]::WriteAllText($rootCmake, $origRootCmake)
    Assert-Audit -TargetRepo $hipRepo -Base $auditBaseline

    # Different audit baseline SHA must NOT apply the exception
    $null = Invoke-FixtureGit $hipRepo @('checkout', '--quiet', '-b', 'other-baseline')
    $null = Invoke-FixtureGit $hipRepo @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--allow-empty', '-m', 'other-baseline')
    $otherBaseline = (Invoke-FixtureGit $hipRepo @('rev-parse', 'HEAD')).Trim()
    Assert-Audit @('ggml/src/ggml-hip/CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $otherBaseline

    # Adding even 1 line to ggml/src/ggml-hip/CMakeLists.txt must be rejected
    $hipCmakePath = Join-Path $hipRepo 'ggml/src/ggml-hip/CMakeLists.txt'
    [IO.File]::AppendAllText($hipCmakePath, "# extra line`n")
    Assert-Audit @('ggml/src/ggml-hip/CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $auditBaseline

    # Untracked ggml/src/ggml-hip/CMakeLists.txt with the exact reviewed blob must be rejected
    # even when the pinned audit baseline SHA is specified
    $null = Invoke-FixtureGit $hipRepo @('checkout', '--quiet', $reviewedHipCommit, '--', 'ggml/src/ggml-hip/CMakeLists.txt')
    $null = Invoke-FixtureGit $hipRepo @('rm', '--cached', '--quiet', 'ggml/src/ggml-hip/CMakeLists.txt')
    Assert-Audit @('ggml/src/ggml-hip/CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $auditBaseline
    $null = Invoke-FixtureGit $hipRepo @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'untracked-hip')
    $untrackedHipBase = (Invoke-FixtureGit $hipRepo @('rev-parse', 'HEAD')).Trim()
    Assert-Audit @('ggml/src/ggml-hip/CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $untrackedHipBase

    # Deleting ggml/src/ggml-hip/CMakeLists.txt must be rejected
    Remove-Item -LiteralPath $hipCmakePath
    Assert-Audit @('ggml/src/ggml-hip/CMakeLists.txt: CMake configuration') -TargetRepo $hipRepo -Base $auditBaseline

    Write-Host 'Dependency audit tests passed.'
} finally {
    Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $hipRepo -Recurse -Force -ErrorAction SilentlyContinue
}
if ((Test-Path -LiteralPath $repo) -or (Test-Path -LiteralPath $hipRepo)) {
    throw 'Temporary test repository was not cleaned up.'
}
