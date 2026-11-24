#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$builder = Join-Path $PSScriptRoot 'Build-Vulkan.ps1'
$repo = & git -C $PSScriptRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw 'Fixture requires a Git checkout.' }
$commit = & git -C $repo rev-parse --short HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the fixture source.' }
$root = Join-Path (Split-Path -Parent $repo) ('vk-manifest-test-' + [Guid]::NewGuid().ToString('N'))

# One small executable simulates CMake and provides the CLI metadata fixture.
$fixtureSource = @'
using System;
using System.IO;
using System.Linq;

public static class VulkanManifestFixture
{
    public static int Main(string[] args)
    {
        string name = Path.GetFileNameWithoutExtension(typeof(VulkanManifestFixture).Assembly.Location);
        if (name.Equals("llama-cli", StringComparison.OrdinalIgnoreCase))
        {
            if (args[0] == "--version")
                Console.WriteLine("version: 1.0.0-dev (build 1, commit SOURCE_COMMIT)");
            else if (args[0] == "--list-devices")
                Console.WriteLine("Available devices:\n  Vulkan0: AMD Radeon(TM) 8060S Graphics (1024 MiB, 1024 MiB free)");
            else return 2;
            return 0;
        }

        if (args[0] == "--version")
        {
            Console.WriteLine("cmake version 3.31.6-msvc6");
            return 0;
        }

        if (args[0] == "--build")
        {
            File.WriteAllText(Path.Combine(args[1], "fixture-built"), "");
            return 0;
        }

        int buildIndex = Array.IndexOf(args, "-B");
        if (buildIndex < 0) return 2;
        string buildDir = args[buildIndex + 1];
        File.WriteAllText(Path.Combine(buildDir, "fixture-configured"), "");
        string request = args.LastOrDefault(a => a.StartsWith("-DGGML_CPU_ALL_VARIANTS:BOOL=", StringComparison.Ordinal));
        if (request != null)
        {
            string source = args[Array.IndexOf(args, "-S") + 1];
            string value = request.Substring(request.IndexOf('=') + 1);
            File.WriteAllLines(Path.Combine(buildDir, "CMakeCache.txt"), new [] {
                "CMAKE_HOME_DIRECTORY:INTERNAL=" + source,
                "GGML_VULKAN:BOOL=ON",
                "GGML_CPU_ALL_VARIANTS:BOOL=" + value
            });
        }
        return 0;
    }
}
'@

function New-Fixture {
    param([string]$Name, [string[]]$Entries = @())

    $dir = Join-Path $root $Name
    $bin = Join-Path $dir 'bin\Release'
    [IO.Directory]::CreateDirectory($bin) | Out-Null
    Copy-Item -LiteralPath $script:cmake -Destination (Join-Path $bin 'llama-cli.exe')
    [IO.File]::WriteAllLines((Join-Path $dir 'CMakeCache.txt'),
        @("CMAKE_HOME_DIRECTORY:INTERNAL=$repo", 'GGML_VULKAN:BOOL=ON') + $Entries)
    return $dir
}

function Assert-FixtureManifest {
    param([string]$Dir, [bool]$Variants, [bool]$Built)

    $bin = Join-Path $Dir 'bin\Release'
    $manifest = Get-Content -LiteralPath (Join-Path $bin 'evox2-build.json') -Raw | ConvertFrom-Json
    $value = $manifest.BackendSettings.CpuAllVariants
    if ($value -isnot [bool] -or $value -ne $Variants -or $manifest.Build.Executed -ne $Built) {
        throw "Unexpected backend settings or build state in $Dir."
    }
    $identity = if ($Built) { 'Verified' } else { 'Unverified' }
    if ($manifest.BuildIdentity.Status -ne $identity -or
        !$manifest.Source.Commit.StartsWith($commit) -or
        $manifest.ExecutableIdentity.Sha256 -ne (Get-FileHash (Join-Path $bin 'llama-cli.exe')).Hash -or
        $manifest.DeviceIdentity.Devices.Id -notcontains 'Vulkan0') {
        throw "Unexpected manifest provenance fields in $Dir."
    }
}

function Assert-FixtureFailure {
    param([string]$Dir, [string]$Pattern, [hashtable]$Options)

    $message = $null
    try { & $builder @fixtureArgs -BuildDir $Dir @Options | Out-Null }
    catch { $message = $_.Exception.Message }
    if ($message -notmatch $Pattern -or
        (Test-Path -LiteralPath (Join-Path $Dir 'bin\Release\evox2-build.json')) -or
        (Test-Path -LiteralPath (Join-Path $Dir 'fixture-built'))) {
        throw "Expected rejection before build and manifest generation in $Dir. Actual: $message"
    }
}

[IO.Directory]::CreateDirectory($root) | Out-Null
try {
    $cmake = Join-Path $root 'cmake.exe'
    Add-Type -TypeDefinition ($fixtureSource.Replace('SOURCE_COMMIT', $commit)) -OutputAssembly $cmake -OutputType ConsoleApplication
    Copy-Item -LiteralPath $cmake -Destination (Join-Path $root '7z.exe')
    $fixtureArgs = @{ CMakeExe = $cmake; VulkanSdk = $root; SevenZipBin = $root; DependencyCacheRoot = (Join-Path $root 'deps') }

    foreach ($variant in 'ON', 'OFF') {
        $entry = "GGML_CPU_ALL_VARIANTS:BOOL=$variant"
        $enabled = $variant -eq 'ON'

        $normal = New-Fixture "normal-$variant"
        & $builder @fixtureArgs -BuildDir $normal -CpuAllVariants $variant | Out-Null
        Assert-FixtureManifest $normal $enabled $true

        $buildOnly = New-Fixture "build-$variant" $entry
        & $builder @fixtureArgs -BuildDir $buildOnly -BuildOnly | Out-Null
        Assert-FixtureManifest $buildOnly $enabled $true

        $manifestOnly = New-Fixture "manifest-$variant" $entry
        & $builder @fixtureArgs -BuildDir $manifestOnly -ManifestOnly | Out-Null
        Assert-FixtureManifest $manifestOnly $enabled $false
        if (Test-Path -LiteralPath (Join-Path $manifestOnly 'fixture-configured')) {
            throw 'ManifestOnly invoked configure.'
        }
    }

    Assert-FixtureFailure (New-Fixture 'missing') 'found 0' @{ ManifestOnly = $true }
    Assert-FixtureFailure (New-Fixture 'wrong-key' 'ggml_cpu_all_variants:BOOL=ON') 'found 0' @{ ManifestOnly = $true }
    Assert-FixtureFailure (New-Fixture 'bad' 'GGML_CPU_ALL_VARIANTS:BOOL=MAYBE') 'Invalid.*MAYBE' @{ ManifestOnly = $true }
    Assert-FixtureFailure (New-Fixture 'duplicate' @('GGML_CPU_ALL_VARIANTS:BOOL=ON', 'GGML_CPU_ALL_VARIANTS:BOOL=OFF')) 'found 2' @{ ManifestOnly = $true }
    Assert-FixtureFailure (New-Fixture 'manifest-mismatch' 'GGML_CPU_ALL_VARIANTS:BOOL=OFF') 'requested ON, CMake cache reports OFF' @{ ManifestOnly = $true; CpuAllVariants = 'ON' }
    Assert-FixtureFailure (New-Fixture 'build-mismatch' 'GGML_CPU_ALL_VARIANTS:BOOL=ON') 'requested OFF, CMake cache reports ON' @{ BuildOnly = $true; CpuAllVariants = 'OFF' }
    Assert-FixtureFailure (New-Fixture 'configure-mismatch') 'requested OFF, CMake cache reports ON' @{ CpuAllVariants = 'OFF'; ExtraCMakeArgs = @('-DGGML_CPU_ALL_VARIANTS:BOOL=ON') }
    Write-Host 'Vulkan manifest tests passed (six manifest cases and seven rejection cases).'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
