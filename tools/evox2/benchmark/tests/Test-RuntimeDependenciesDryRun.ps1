#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$benchmark = Split-Path -Parent $PSScriptRoot
$tools = Split-Path -Parent $benchmark
Import-Module (Join-Path $tools 'lib\Evox2.RuntimeDependencies.psm1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('evox2-dryruntime-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $root 'bin'
$null = [IO.Directory]::CreateDirectory($bin)
$priorCalls = $env:EVOX2_FIXTURE_RUNTIME_CALLS
try {
    $cli = Join-Path $bin 'llama-cli.exe'
    $bench = Join-Path $bin 'llama-bench.exe'
    $env:EVOX2_FIXTURE_RUNTIME_CALLS = Join-Path $root 'calls.txt'
    $code = @'
using System;
using System.IO;
public static class Evox2RuntimeDryRunFixture {
    public static int Main(string[] args) {
        if (args.Length != 1) return 91;
        File.AppendAllText(Environment.GetEnvironmentVariable("EVOX2_FIXTURE_RUNTIME_CALLS"), args[0] + "\n");
        switch (args[0]) {
            case "--version":
                Console.WriteLine("version: 1.0.0 (build 53, commit abc12345)");
                return 0;
            case "--list-devices":
                Console.WriteLine("Available devices:\n  Vulkan0: AMD Radeon(TM) 8060S Graphics (1024 MiB, 1024 MiB free)");
                return 0;
            case "--help":
                Console.WriteLine("  -c, --ctx-size N");
                return 0;
            default: return 92;
        }
    }
}
'@
    Add-Type -TypeDefinition $code -OutputAssembly $cli -OutputType ConsoleApplication
    Copy-Item -LiteralPath $cli -Destination $bench
    $cache = Join-Path $root 'CMakeCache.txt'
    'GGML_BACKEND_DL:BOOL=OFF' | Set-Content -LiteralPath $cache -Encoding UTF8
    $extension = Get-Evox2RuntimeDependencies -BinDir $bin -BuildDir $root -Backend Vulkan -Runtime @{} -Built $true
    $files = @($extension.Files)
    $manifest = [ordered]@{ SchemaVersion = 1; Backend = 'Vulkan'; Source = @{ Commit = 'abc12345' }; Artifacts = $files }
    $manifestPath = Join-Path $bin 'evox2-build.json'
    $model = Join-Path $root 'dummy.gguf'
    [IO.File]::WriteAllText($model, 'This file is never loaded by the fixture.')
    $local = Join-Path $root 'local.psd1'
    $plan = Join-Path $root 'plan.psd1'
    [IO.File]::WriteAllText($local, "@{ LogRoot = '$root'; Builds = @{ B = @{ BinDir = '$bin'; ExpectedBackend = 'Vulkan' } }; Models = @{ M = @{ Path = '$model' } } }")
    [IO.File]::WriteAllText($plan, @'
@{
    SchemaVersion = 1
    Jobs = @(
        @{ Name = 'cli'; Tool = 'cli'; BuildKeys = @('B'); ModelKeys = @('M'); Parameters = @{ AllocationOnly = $true } },
        @{ Name = 'bench'; Tool = 'bench'; BuildKeys = @('B'); ModelKeys = @('M') }
    )
}
'@)

    foreach ($format in 'Legacy','Extended') {
        if ($format -eq 'Extended') { $manifest.RuntimeDependencies = $extension }
        $manifest | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        $before = if (Test-Path -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS) {
            (Get-Item -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS).Length
        } else { 0 }
        $matrix = @{ Plan = $plan; LocalConfig = $local; MaxRuns = 2; PlanOnly = $true }
        & (Join-Path $benchmark 'Invoke-BenchmarkMatrix.ps1') @matrix | Out-Null
        if ((Test-Path -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS) -and
            (Get-Item -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS).Length -ne $before) {
            throw 'PlanOnly launched a fixture executable.'
        }
        $argsForMeasure = @{ LocalConfig = $local; BuildKey = 'B'; ModelKey = 'M'; DryRun = $true; NoPModeProbe = $true; NoAdlxMonitor = $true }
        & (Join-Path $benchmark 'Measure-LlamaCli.ps1') @argsForMeasure -AllocationOnly | Out-Null
        & (Join-Path $benchmark 'Measure-LlamaBench.ps1') @argsForMeasure -Context 4096 | Out-Null
        $after = (Get-Item -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS).Length
        if ($after -le $before) { throw "DryRun skipped metadata discovery for $format." }
    }
    $calls = @(Get-Content -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS)
    if (@($calls | Where-Object { $_ -notin '--help','--version','--list-devices' }).Count -or $calls -notcontains '--help') {
        throw 'Unexpected fixture invocation.'
    }
    $extFile = $extension.Files | Where-Object Name -eq 'llama-bench.exe'
    $extFile.Sha256 = '0' * 64
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $before = (Get-Item -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS).Length
    try {
        & (Join-Path $benchmark 'Measure-LlamaBench.ps1') @argsForMeasure -Context 4096 | Out-Null
        throw 'Expected bench metadata validation to stop.'
    } catch {
        if ($_.Exception.Message -notmatch 'Runtime artifact hash mismatch') { throw }
    }
    if ((Get-Item -LiteralPath $env:EVOX2_FIXTURE_RUNTIME_CALLS).Length -ne $before) {
        throw 'Invalid bench manifest did not stop before --help.'
    }
} finally {
    $env:EVOX2_FIXTURE_RUNTIME_CALLS = $priorCalls
    Remove-Item -LiteralPath $root -Recurse -Force
}
'Legacy and extended Measure DryRun and Matrix PlanOnly passed.'
