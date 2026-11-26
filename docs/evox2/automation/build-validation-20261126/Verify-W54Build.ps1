#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Vulkan','ROCm')][string]$Backend,
    [string]$Worktree = 'C:\llama-build\automation\w54',
    [string]$FixedClone = 'C:\llama-build\automation\llama.cpp-evox2-windows',
    [string]$LogRoot = 'C:\llama-build\_logs\codex\w54-20261126',
    [string]$SourceCommit = '20f48bfe162d8d886b9f5fea7ad6d7df91eb3266'
)

$ErrorActionPreference = 'Stop'
$dir = if ($Backend -eq 'Vulkan') { 'build-vk' } else { 'build-rm' }
$ref = if ($Backend -eq 'Vulkan') { 'build-w5v' } else { 'build-w5r' }
$build = Join-Path $Worktree $dir
$bin = Join-Path $build 'bin\Release'
$cli = Join-Path $bin 'llama-cli.exe'
$caseRecord = Get-Content -LiteralPath (Join-Path $LogRoot "$Backend-run.json") -Raw | ConvertFrom-Json
$stem = $caseRecord.Stem
$tools = Join-Path $Worktree 'tools\evox2'
Import-Module (Join-Path $tools 'lib\Evox2.Common.psm1')
$depsModule = Import-Module (Join-Path $tools 'lib\Evox2.RuntimeDependencies.psm1') -PassThru
Import-Module (Join-Path $tools 'automation\Evox2.BuildState.psm1')
$state = Read-Evox2BuildState $stem
if ($state.Status -ne 'Succeeded' -or $state.Result.ExitCode -ne 0 -or
    $state.Snapshot.ExecutionId -ne $state.Result.ExecutionId -or $state.Worker.ExecutionId -ne $state.Result.ExecutionId -or
    $state.Snapshot.Conditions.BuildDirectory -ne $build -or !$state.Snapshot.Conditions.Offline -or
    $state.LiveProcesses.Count -or $state.Worker.CheckoutStart.SourceCommit -ne $SourceCommit -or
    $state.Worker.CheckoutEnd.SourceCommit -ne $SourceCommit -or !$state.Worker.CheckoutEnd.Clean) {
    throw 'State, result, or checkout provenance verification failed.'
}
$logFiles = @(foreach ($suffix in 'stdout.log','stderr.log','result.json','state.json','worker.json','progress.jsonl') {
    Get-Item -LiteralPath "$stem.$suffix"
})
$secret = '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|Authorization:\s*Bearer\s+\S+|https?://[^/\s]+:[^/\s]+@)'
if (Select-String -LiteralPath $logFiles.FullName -Pattern $secret -List) { throw 'A log may contain credential material.' }
$stdout = Get-Content -LiteralPath "$stem.stdout.log" -Raw
foreach ($phase in 'Configure: .* -ConfigureOnly','Build: .* -BuildOnly','Refreshing build metadata',"Verified $Backend") {
    if ($stdout -notmatch $phase) { throw "Missing successful wrapper phase: $phase" }
}
$warning = [bool](Select-String -LiteralPath "$stem.stderr.log","$stem.stdout.log" -Pattern 'Git index not found in git repository' -List)
$progress = @(Get-Content -LiteralPath "$stem.progress.jsonl" | ForEach-Object { ConvertFrom-Json $_ })
$jobs = @($progress | ForEach-Object { $_.Processes } | Where-Object { $_ -and $_.Id -and $_.StartedUtc })
$compilers = @($jobs | Where-Object CompilerCommand)
$ninja = @($progress | Where-Object Ninja)
$intervals = @(for ($i = 1; $i -lt $progress.Count; $i++) { $progress[$i].ElapsedSeconds - $progress[($i - 1)].ElapsedSeconds })
if (!$ninja.Count -or !$jobs.Count -or !$compilers.Count -or 'Build' -notin $progress.Phase) { throw 'Missing actual build progress or process evidence.' }

function Read-Cache([string]$Directory) {
    $index = @{}
    foreach ($line in Get-Content -LiteralPath (Join-Path $Directory 'CMakeCache.txt')) {
        if ($line -match '^([^:#/][^:]*):[^=]+=(.*)$') { $index[$Matches[1]] = $Matches[2] }
    }
    return $index
}
$cache = Read-Cache $build
$prior = Read-Cache (Join-Path $FixedClone $ref)
$keys = @('CMAKE_GENERATOR','CMAKE_MAKE_PROGRAM','GGML_HIP','GGML_VULKAN','GGML_CPU_ALL_VARIANTS',
    'GGML_NATIVE','GGML_BACKEND_DL','GGML_RPC','GGML_OPENMP','GGML_OPENMP_FETCH','LLAMA_BUILD_BORINGSSL',
    'BORINGSSL_VERSION','FETCHCONTENT_SOURCE_DIR_BORINGSSL','FETCHCONTENT_FULLY_DISCONNECTED','LLAMA_BUILD_UI','LLAMA_USE_PREBUILT_UI')
if ($Backend -eq 'Vulkan') { $keys += @('Vulkan_INCLUDE_DIR','Vulkan_LIBRARY','Vulkan_GLSLC_EXECUTABLE') }
else { $keys += @('AMDGPU_TARGETS','CMAKE_C_COMPILER','CMAKE_CXX_COMPILER','CMAKE_HIP_COMPILER') }
$settings = @(foreach ($key in $keys) {
    if (!$cache.ContainsKey($key) -or !$prior.ContainsKey($key) -or $cache[$key] -cne $prior[$key]) {
        throw "Work 5-2 cache discrepancy $key : $($prior[$key]) to $($cache[$key])"
    }
    [pscustomobject]@{Name=$key;Value=$cache[$key]}
})
if ($cache['CMAKE_HOME_DIRECTORY'] -ine $Worktree.Replace('\','/')) { throw 'Unexpected CMake source root.' }
$manifestPath = Join-Path $bin 'evox2-build.json'
$m = Read-Evox2BuildManifest $cli
$ext = $m.RuntimeDependencies
$parallel = if ($Backend -eq 'ROCm') {
    $m.Build.Parallel -eq 4 -and @($m.Build.Steps | Where-Object { $_.Arguments -notcontains '4' }).Count -eq 0
} else { $m.Build.Arguments -contains '4' }
if ($m.BuildIdentity.Status -ne 'Verified' -or $m.Source.Commit -ne $SourceCommit -or $m.Source.Dirty -or
    !$SourceCommit.StartsWith($m.ExecutableIdentity.Commit) -or $m.Configuration -ne 'Release' -or
    $m.Validation.Version.ExitCode -ne 0 -or $m.Validation.ListDevices.ExitCode -ne 0 -or
    ($m.Validation.ListDevices.Tail -join ' ') -notmatch "$($Backend)0: AMD Radeon.*8060S" -or
    $ext.Version -ne 1 -or $ext.Provenance -ne 'BuildCompleted' -or !$m.Configure.MetadataRefresh.Executed -or
    !$parallel) { throw 'Release identity, smoke, parallelism, or schema mismatch.' }
$gpu = if ($Backend -eq 'Vulkan') { 'ggml-vulkan.dll' } else { 'ggml-hip.dll' }
$required = @('ggml-cpu.dll',$gpu)
if ($Backend -eq 'Vulkan') {
    $required += 'libomp.dll'
    $cacheOmp = 'C:\llama-build\automation\_deps\openmp\llvm-openmp-22.1.8-x64\bin\libomp.dll'
    if (($ext.Files | Where-Object Name -eq 'libomp.dll').Sha256 -ne (Get-FileHash -LiteralPath $cacheOmp).Hash) {
        throw 'Bundled Vulkan libomp does not match the approved cache.'
    }
}
foreach ($name in $required) {
    if ($ext.ConfigurationRequired -notcontains $name) { throw "Missing configured runtime $name" }
}
if ($ext.ConfigurationRequired -contains 'ggml-rpc.dll' -or $ext.Files.Name -notcontains 'ggml-rpc.dll') {
    throw 'RPC plugin classification differs from the configuration.'
}
$cliRequired = ($ext.Executables | Where-Object Name -eq 'llama-cli.exe').Required
$benchRequired = ($ext.Executables | Where-Object Name -eq 'llama-bench.exe').Required
foreach ($name in 'llama-cli-impl.dll','llama-server-impl.dll','mtmd.dll') {
    if ($cliRequired -notcontains $name -or $benchRequired -contains $name) { throw "Unexpected executable dependency: $name" }
}
if ($benchRequired -notcontains 'llama-bench-impl.dll' -or $cliRequired -contains 'llama-bench-impl.dll') { throw 'Incorrect benchmark dependency closure.' }

$measurements = @(foreach ($name in 'llama-cli.exe','llama-bench.exe','llama-server.exe') {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $check = Test-Evox2RuntimeArtifacts (Join-Path $bin $name) $m
    $clock.Stop()
    if ($check.Status -ne 'Verified' -or $check.Scope -ne 'RuntimeDependenciesV1' -or $check.Provenance -ne 'BuildCompleted') {
        throw "Runtime check failed for $name : $($check.Issues)"
    }
    [pscustomobject]@{Executable=$name;DurationSeconds=$clock.Elapsed.TotalSeconds;Digest=$check.Digest}
})
$trees = @(foreach ($tree in $ext.DataTrees) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $digest = & $depsModule { param($path) Get-RuntimeTreeDigest $path } (Join-Path $bin $tree.Name)
    $clock.Stop()
    if ($digest -ne $tree.Sha256) { throw "Runtime tree mismatch: $($tree.Name)" }
    [pscustomobject]@{Name=$tree.Name;Sha256=$digest;Seconds=$clock.Elapsed.TotalSeconds}
})
if ($Backend -eq 'ROCm') {
    if ($m.Runtime.RuntimePolicy.Verification -ne 'DllAndRuntimeDataHashesVerified' -or $m.Runtime.RuntimeDlls.Count -ne 8 -or $trees.Count -ne 2) {
        throw 'TheRock legacy runtime evidence missing.'
    }
    foreach ($tree in $m.Runtime.RuntimeDataTrees) {
        $sourceDigest = & $depsModule { param($path) Get-RuntimeTreeDigest $path } $tree.Source.Path
        if ($sourceDigest -ne $tree.Destination.DigestSha256 -or $sourceDigest -ne $tree.Source.DigestSha256) {
            throw "TheRock source data changed: $($tree.Name)"
        }
    }
    foreach ($dll in $m.Runtime.RuntimeDlls) {
        if ((Get-FileHash -LiteralPath $dll.Source.Path).Hash -ne $dll.Destination.Sha256 -or
            ($ext.Files | Where-Object Name -eq $dll.Name).Sha256 -ne $dll.Destination.Sha256) { throw "TheRock DLL mismatch: $($dll.Name)" }
    }
}
$observed = Get-Evox2RuntimeDependencies -BinDir $bin -BuildDir $build -Backend $Backend -Runtime $m.Runtime -Built $false
foreach ($field in 'Files','Executables','ConfigurationRequired','CpuVariants','DataTrees') {
    $new = ConvertTo-Evox2CanonicalObject -InputObject $observed[$field] | ConvertTo-Json -Depth 15 -Compress
    $saved = ConvertTo-Evox2CanonicalObject -InputObject $ext.$field | ConvertTo-Json -Depth 15 -Compress
    if ($new -cne $saved) { throw "Retained PE or runtime evidence differs: $field" }
}
$hashes = @(foreach ($file in Get-ChildItem -LiteralPath $bin -File | Where-Object Extension -in '.dll','.exe','.json' | Sort-Object Name) {
    $sha = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $expected = @($m.Artifacts | Where-Object Name -eq $file.Name)
    if ($expected.Count -and $expected[0].Sha256 -ne $sha) { throw "Legacy artifact hash differs: $($file.Name)" }
    [pscustomobject]@{Backend=$Backend;Name=$file.Name;Sha256=$sha}
})
[pscustomobject]@{
    Backend=$Backend; Source=$SourceCommit; Embedded=$m.ExecutableIdentity.Commit; BuildIdentity=$m.BuildIdentity.Status
    Version=$m.Validation.Version.Tail; Devices=$m.Validation.ListDevices.Tail
    CliSha256=$m.ExecutableIdentity.Sha256; ManifestSha256=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant()
    Cache=$settings; Runtime=$measurements; RuntimeTrees=$trees; RuntimeFiles=$ext.Files.Count; External=$ext.External
    Artifacts=$hashes; GitIndexWarning=$warning
    Log=[pscustomobject]@{
        Stem=$stem; Seconds=$state.Result.ElapsedSeconds; Exit=$state.Result.ExitCode; Start=$state.Snapshot.StartedUtc; End=$state.Snapshot.UpdatedUtc
        Samples=$progress.Count; Phases=@($progress.Phase | Sort-Object -Unique); Interval=$intervals | Measure-Object -Minimum -Maximum -Average
        LastNinja=$state.Snapshot.Ninja; Compilers=$compilers.Count; SampleCompiler=$compilers[0].CompilerCommand
        CompilerPeakWorkingSet=($compilers | Measure-Object -Property WorkingSetBytes -Maximum).Maximum
        CompilerMaxSampleCpu=($compilers | Measure-Object -Property CpuSeconds -Maximum).Maximum
        WorkerPid=$state.Worker.Process.Id; WorkerStart=$state.Worker.Process.StartedUtc; SupervisorPid=$state.Snapshot.SupervisorProcess.Id
        LogBytes=@($logFiles | ForEach-Object { [pscustomobject]@{File=$_.Extension;Name=$_.Name;Length=$_.Length} })
    }
}
