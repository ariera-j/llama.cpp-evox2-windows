[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'Evox2.DependencyCache.psm1') -Force -PassThru
$repo = Join-Path ([IO.Path]::GetTempPath()) ('evox2-audit-' + [Guid]::NewGuid().ToString('N'))

function Invoke-FixtureGit {
    & git -C $repo @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git command failed: $args" }
}

function Set-FixtureFile {
    param([string]$Relative, [string]$Content)
    $path = Join-Path $repo $Relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $Content + "`n")
}

function Assert-Audit {
    param([string[]]$Expected = @())
    $failure = $null
    try {
        & $module { param($root, $base) Assert-Evox2DependencyInputs $root $base } $repo $baseline
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
try {
    Invoke-FixtureGit init --quiet
    Set-FixtureFile '.gitignore' '/cmake/FindExample.cmake'
    Set-FixtureFile 'CMakeLists.txt' 'include(cmake/dependency.cmake)'
    Set-FixtureFile 'cmake/dependency.cmake' 'set(DEP_URL "https://example.invalid/original")'
    Set-FixtureFile 'src/example.cpp' 'int example = 0;'
    Set-FixtureFile 'ui/apps/chat/package-lock.json' '{}'
    Invoke-FixtureGit add -- .
    Invoke-FixtureGit -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit --quiet -m baseline
    $baseline = Invoke-FixtureGit rev-parse HEAD
    Assert-Audit

    Set-FixtureFile 'src/example.cpp' 'int example = 1;'
    Set-FixtureFile 'ggml/src/shaders/new.comp' '// shader source'
    Set-FixtureFile 'tools/evox2/adlx-gpu-monitor/CMakeLists.txt' '# standalone project'
    Assert-Audit

    Set-FixtureFile 'cmake/dependency.cmake' 'set(DEP_URL "https://example.invalid/changed")'
    Set-FixtureFile 'ggml/src/new/CMakeLists.txt' 'include(FetchContent)'
    Set-FixtureFile 'ggml/src/host-toolchain.cmake.in' '# template'
    Set-FixtureFile 'cmake/FindExample.cmake' '# ignored module'
    Set-FixtureFile '.gitmodules' '# new submodule declaration'
    Remove-Item -LiteralPath (Join-Path $repo 'ui/apps/chat/package-lock.json')
    Assert-Audit @(
        'cmake/dependency.cmake: CMake configuration',
        'ggml/src/new/CMakeLists.txt: CMake configuration',
        'ggml/src/host-toolchain.cmake.in: CMake configuration',
        'cmake/FindExample.cmake: ignored local module',
        '.gitmodules: package or submodule',
        'ui/apps/chat/package-lock.json: package or submodule'
    )

    Invoke-FixtureGit add -- ggml/src/new/CMakeLists.txt
    Assert-Audit @('ggml/src/new/CMakeLists.txt: CMake configuration')
    Write-Host 'Dependency audit tests passed.'
} finally {
    Remove-Item -LiteralPath $repo -Recurse -Force
}
