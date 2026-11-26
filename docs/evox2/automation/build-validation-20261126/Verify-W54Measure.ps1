#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Worktree = 'C:\llama-build\automation\w54',
    [string]$Automation = 'C:\llama-build\automation',
    [string]$ResultDirectory = 'C:\llama-build\_logs\codex\w54-20261126'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$output = @('matrix-plan.log','matrix-plan.stderr.log','measurement-compatibility.json')
foreach ($key in 'NewVulkan','NewROCm','Diagnostic') {
    $output += @("$key-Cli-DryRun.log","$key-Bench-DryRun.log")
}
foreach ($name in $output) {
    if (Test-Path -LiteralPath (Join-Path $ResultDirectory $name)) { throw "Use a new result directory: $name already exists." }
}
$null = [IO.Directory]::CreateDirectory($ResultDirectory)
$bench = Join-Path $Worktree 'tools\evox2\benchmark'
Import-Module (Join-Path $Worktree 'tools\evox2\lib\Evox2.Common.psm1')
$paths = [ordered]@{
    NewVulkan = 'w54\build-vk'; NewROCm = 'w54\build-rm'
    Work52Vulkan = 'llama.cpp-evox2-windows\build-w5v'; Work52ROCm = 'llama.cpp-evox2-windows\build-w5r'
    Stage2 = 'llama.cpp-evox2-windows\build-s2v'; C1ROCm = 'llama.cpp-evox2-windows\build-c1r'
    Diagnostic = 'w43diag\build-ld'
}
$verification = @()
$measure = @()
foreach ($key in $paths.Keys) {
    $bin = Join-Path (Join-Path $Automation $paths[$key]) 'bin\Release'
    $scope = if ($key -match '^New') { 'RuntimeDependenciesV1' } else { 'LegacyArtifacts' }
    foreach ($leaf in 'llama-cli.exe','llama-bench.exe') {
        $exe = Join-Path $bin $leaf
        $m = Read-Evox2BuildManifest $exe
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $r = Test-Evox2RuntimeArtifacts $exe $m
        $clock.Stop()
        if ($r.Status -ne 'Verified' -or $r.Scope -ne $scope -or $m.BuildIdentity.Status -ne 'Verified') {
            throw "Manifest regression for $key : $leaf $($r.Issues)"
        }
        $verification += [pscustomobject]@{Build=$key;Executable=$leaf;Scope=$scope;Seconds=$clock.Elapsed.TotalSeconds;Digest=$r.Digest}
    }
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('evox2-w54-plan-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
try {
    $model = Join-Path $fixture 'placeholder.gguf'
    [IO.File]::WriteAllText($model, 'Verification-only placeholder. This is not model data.')
    $local = Join-Path $fixture 'local.psd1'
    $plan = Join-Path $fixture 'plan.psd1'
    $builds = @{}
    foreach ($key in 'NewVulkan','NewROCm','Diagnostic') {
        $bin = Join-Path (Join-Path $Automation $paths[$key]) 'bin\Release'
        $backend = if ($key -eq 'NewROCm') { 'ROCm' } else { 'Vulkan' }
        $builds[$key] = "$key = @{ BinDir = '$bin'; ExpectedBackend = '$backend' }"
    }
    [IO.File]::WriteAllText($local, "@{ LogRoot = '$fixture'; Builds = @{ $($builds.Values -join '; ') }; Models = @{ Placeholder = @{ Path = '$model' } } }")
    [IO.File]::WriteAllText($plan, @'
@{
    SchemaVersion = 1
    Jobs = @(
        @{ Name = 'cli'; Tool = 'cli'; BuildKeys = @('NewVulkan','NewROCm','Diagnostic'); ModelKeys = @('Placeholder'); Parameters = @{ AllocationOnly = $true } },
        @{ Name = 'bench'; Tool = 'bench'; BuildKeys = @('NewVulkan','NewROCm','Diagnostic'); ModelKeys = @('Placeholder') }
    )
}
'@)
    $planLog = Join-Path $ResultDirectory 'matrix-plan.log'
    $script = Join-Path $bench 'Invoke-BenchmarkMatrix.ps1'
    $launch = @{
        FilePath = "$PSHOME\powershell.exe"; PassThru = $true; NoNewWindow = $true
        ArgumentList = @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File', ('"{0}"' -f $script),
            '-Plan', ('"{0}"' -f $plan), '-LocalConfig', ('"{0}"' -f $local), '-MaxRuns', '6', '-PlanOnly')
        RedirectStandardOutput = $planLog
        RedirectStandardError = Join-Path $ResultDirectory 'matrix-plan.stderr.log'
    }
    $process = Start-Process @launch
    $null = $process.Handle
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "PlanOnly exit code: $($process.ExitCode)" }
    $expanded = Get-Content -LiteralPath $planLog -Raw
    if ((Test-Path -LiteralPath (Join-Path $fixture 'matrix')) -or $expanded -notmatch 'M006' -or
        $expanded -notmatch 'PlanOnly: no benchmark processes were started') {
        throw 'PlanOnly output differs from the expected six cells and non-execution status.'
    }
    foreach ($key in 'NewVulkan','NewROCm','Diagnostic') {
        foreach ($tool in 'Cli','Bench') {
            $opts = @{LocalConfig=$local;BuildKey=$key;ModelKey='Placeholder';DryRun=$true;NoAdlxMonitor=$true;NoPModeProbe=$true}
            if ($tool -eq 'Cli') { $opts.AllocationOnly = $true }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            & (Join-Path $bench "Measure-Llama$tool.ps1") @opts *> (Join-Path $ResultDirectory "$key-$tool-DryRun.log")
            $clock.Stop()
            $measure += [pscustomobject]@{Build=$key;Tool=$tool;Seconds=$clock.Elapsed.TotalSeconds}
            $measure[-1] | ConvertTo-Json -Compress
        }
    }
} finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
[pscustomobject]@{Runtime=$verification;DryRun=$measure;PlanOnly=$true} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ResultDirectory 'measurement-compatibility.json') -Encoding UTF8
