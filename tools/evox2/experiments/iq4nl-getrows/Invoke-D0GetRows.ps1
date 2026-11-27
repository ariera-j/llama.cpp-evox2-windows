#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('\A[0-9a-f]{40}\z')][string]$ExpectedHead,
    [Parameter(Mandatory)][ValidateSet('RocmSupport','CpuSupport','RocmNumerical')][string]$Case,
    [switch]$RunApproved
)
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
if ($root -ine 'C:\llama-build\automation\w55') { throw 'This experiment is pinned to w55.' }
$head = $ExpectedHead
$sha = 'e199e5f4319731071199d84f4f2e571fcaa7d413'
$bin = Join-Path $root 'build-rh\bin\Release'
$exe = Join-Path $bin 'test-backend-ops.exe'
$module = Join-Path $PSScriptRoot 'D0GetRows.Supervisor.psm1'
$memoryModule = Join-Path $root 'tools\evox2\benchmark\Evox2.Memory.psm1'
Import-Module $module
$caseModule = Join-Path $PSScriptRoot 'D0GetRows.Cases.psm1'
Import-Module $caseModule
$plan = Get-D0GetRowsPlan -Case $Case
$nativeArgs = $plan.NativeArguments
Import-Module $memoryModule
Import-Module (Join-Path $root 'tools\evox2\lib\Evox2.Common.psm1')
$log = Join-Path 'C:\llama-build\_logs\codex' ('d0-4d-getrows-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $log | Out-Null
Write-Host "Logs: $log"
function Save-Record($name, $value) {
    Write-D0Record (Join-Path $log $name) $value
}
$resourceFunctions = {
    function Get-GpuSnapshot {
        $paths = '\GPU Adapter Memory(*)\Dedicated Usage', '\GPU Adapter Memory(*)\Shared Usage', '\GPU Engine(*)\Utilization Percentage'
        foreach ($path in $paths) {
            $samples = @((Get-Counter -Counter $path -ErrorAction Stop).CounterSamples | Where-Object { $_.Status -in 0,1 -and $_.CookedValue -ge 0 -and ![double]::IsInfinity($_.CookedValue) })
            if (!$samples.Count) { throw "No valid samples for $path" }
            [pscustomobject]@{ Counter=$path; Count=$samples.Count; Sum=($samples | Measure-Object CookedValue -Sum).Sum
                Samples=@($samples | Select-Object InstanceName, Timestamp, CookedValue, Status) }
        }
    }
    function Read-EventRange([string]$channel, [long]$old, [long]$new) {
        if ($new -lt $old) { throw "Event cursor rolled back: $channel" }
        $readError = @()
        $entries = @(Get-WinEvent -LogName $channel -FilterXPath "*[System[EventRecordID > $old and EventRecordID <= $new]]" -ErrorAction SilentlyContinue -ErrorVariable readError)
        if ($readError.Count -gt 1 -or ($readError.Count -eq 1 -and $readError[0].FullyQualifiedErrorId -notlike 'NoMatchingEventsFound,*')) { throw "Event query failed: $channel" }
        if ($new -gt $old -and (!$entries.Count -or $entries.Count -ne ($new - $old))) { throw "Event records unavailable within the cursor interval: $channel" }
        $entries
    }
    function Test-MajorEvent($entry) {
        $provider = $entry.ProviderName
        return ($entry.Level -in 1,2 -or $provider -match 'WHEA|BugCheck|Resource-Exhaustion|^Display$|amdkmd|amdwdd|DxgKrnl|Application Hang|Application Error' -or
            ($provider -match 'Kernel-Power' -and $entry.Id -eq 41) -or
            ($provider -eq 'Application Popup' -and $entry.Id -eq 26 -and $entry.Message -match 'virtual memory|仮想メモリ不足') -or
            ($provider -match 'Windows Error Reporting' -and $entry.Message -match 'LiveKernelEvent|BlueScreen|AppHang|APPCRASH|test-backend-ops'))
    }
}
. $resourceFunctions
$competing = 'test-backend-ops','llama-cli','llama-bench','llama-server','cmake','ninja','clang','clang++','clang-cl','cl','taskmgr','evox2-adlx-gpu-monitor'
function Get-HostSnapshot {
    $mode = Get-Evox2PModeMetadata
    $memory = Get-Evox2SystemMemory
    $gpu = @(Get-GpuSnapshot)
    $boot = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12} -MaxEvents 1
    $bootTime = ([xml]$boot.ToXml()).Event.EventData.Data | Where-Object Name -eq 'StartTime' | Select-Object -ExpandProperty '#text'
    if (!$bootTime -or !$memory.CommitLimit) { throw 'Missing boot time or commit limit' }
    $cursors = [ordered]@{}
    foreach ($channel in 'System','Application') {
        $latest = Get-WinEvent -LogName $channel -MaxEvents 1
        if (!$latest.RecordId) { throw "No cursor for $channel" }
        $cursors[$channel] = [long]$latest.RecordId
        $null = Read-EventRange $channel $latest.RecordId $latest.RecordId
    }
    [pscustomobject]@{ Time=[DateTimeOffset]::Now.ToString('o'); Memory=$memory; GPU=$gpu; BootTime=$bootTime; BootRecordId=$boot.RecordId; EventCursors=$cursors
        PMode=($mode | Select-Object ProbeSucceeded,Transport,MethodId,Mode,CapturedAt,Error)
        Processes=@(Get-Process -Name $competing -ErrorAction SilentlyContinue | Select-Object Name,Id) }
}
function Assert-Snapshot($snapshot) {
    if (!$snapshot.PMode.ProbeSucceeded -or $snapshot.PMode.Mode -ne 'Performance' -or $snapshot.Memory.Available -lt 16GB -or $snapshot.Processes.Count) {
        throw "Snapshot gate failed at $($snapshot.Time)."
    }
    if ([Math]::Abs(([DateTimeOffset]$snapshot.Time - [DateTimeOffset]$snapshot.PMode.CapturedAt).TotalSeconds) -gt 30) {
        throw 'P-MODE snapshot is stale'
    }
}


$monitorBody = @'
$memoryModule = 'C:\llama-build\automation\w55\tools\evox2\benchmark\Evox2.Memory.psm1'
Import-Module $memoryModule
Import-Module $caseModule
$plan = Get-D0GetRowsPlan -Case $caseName
$stop = Join-Path $dir 'monitor.stop'
$child = Join-Path $dir 'child.json'
while (!(Test-Path -LiteralPath $child)) {
    if (Test-Path -LiteralPath $stop) { return }
    Start-Sleep -Milliseconds 25
}
$identity = Get-Content -LiteralPath $child -Raw | ConvertFrom-Json
$before = Get-Content -LiteralPath (Join-Path $dir 'before.json') -Raw | ConvertFrom-Json
$counter = 0
while (!(Test-Path -LiteralPath $stop) -and (Test-D0ProcessIdentity $identity)) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $sampleStart = [DateTimeOffset]::Now.ToString('o')
    $memory = Get-Evox2SystemMemory
    $p = Get-Process -Id $identity.Id -ErrorAction SilentlyContinue
    $processMemory = $null
    if ($p) {
        try { $processMemory = Get-Evox2ProcessMemory $p } finally { $p.Dispose() }
    }
    $gpu = @(Get-GpuSnapshot)
    $stillRunning = Test-D0ProcessIdentity $identity
    $counter++
    Write-D0Record (Join-Path $dir ('sample-{0:D3}.json' -f $counter)) ([ordered]@{
        Start=$sampleStart; End=[DateTimeOffset]::Now.ToString('o'); ChildStillRunning=$stillRunning
        Memory=$memory; GPU=$gpu; Process=$processMemory
    })
    if (!$stillRunning) { return }
    if ($memory.Available -lt 16GB -or $memory.Commit -gt $before.Memory.Commit + 4GB -or $gpu[0].Sum -gt $before.GPU[0].Sum + 4GB) {
        throw 'Live resource threshold breached.'
    }
    foreach ($channel in 'System','Application') {
        $recent = (Get-WinEvent -LogName $channel -MaxEvents 1).RecordId
        if (@(Read-EventRange $channel $before.EventCursors.$channel $recent | Where-Object { Test-MajorEvent $_ }).Count) {
            throw "New potentially major event: $channel"
        }
    }
    $out = @(Get-Content -LiteralPath (Join-Path $dir 'stdout.log'))
    $err = Get-Content -LiteralPath (Join-Path $dir 'stderr.log') -Raw
    if (Test-D0GetRowsFailureLog $plan $out $err) {
        throw 'Failure signature in the child logs.'
    }
    $delay = [Math]::Max(0, 2000 - $timer.ElapsedMilliseconds)
    if ($delay) { Start-Sleep -Milliseconds $delay }
}
'@
$monitorCode = @'
param($dir)
'@ + [Environment]::NewLine + $resourceFunctions.ToString() + [Environment]::NewLine +
    '$caseModule = ' + "'" + $caseModule + "'" + [Environment]::NewLine +
    '$caseName = ' + "'" + $Case + "'" + [Environment]::NewLine + $monitorBody
$monitor = [scriptblock]::Create($monitorCode)

Push-Location $root
try {
    $actualHead = git rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actualHead -ne $head) { throw 'Unexpected HEAD' }
    $tracking = git rev-parse '@{upstream}'
    if ($LASTEXITCODE -ne 0 -or $tracking -ne $head -or (git branch --show-current) -ne 'experiment/hip-iq4nl-ple160') { throw 'Unexpected branch or tracking SHA' }
    $dirty = @(git status --porcelain=v1)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count) { throw 'Dirty worktree' }
    $diff = @(git diff --name-status $sha HEAD)
    $allowed = @(
        "A`tdocs/evox2/B12651-D0-4D-2A-HIP-IQ4NL-GETROWS-20261127.md",
        "A`ttools/evox2/experiments/iq4nl-getrows/D0GetRows.Cases.psm1",
        "M`ttools/evox2/experiments/iq4nl-getrows/Invoke-D0GetRows.ps1",
        "A`ttools/evox2/experiments/iq4nl-getrows/Test-D0GetRowsCases.ps1"
    )
    if ($LASTEXITCODE -ne 0 -or $diff.Count -ne $allowed.Count -or @(Compare-Object $allowed $diff -CaseSensitive).Count) {
        throw 'Unexpected change since the binary was built.'
    }
    $overrides = @('GGML_BACKEND_PATH','HIP_VISIBLE_DEVICES','HIP_DEVICE_ORDINAL','ROCR_VISIBLE_DEVICES','CUDA_VISIBLE_DEVICES','GPU_DEVICE_ORDINAL','HSA_OVERRIDE_GFX_VERSION' | Where-Object { [Environment]::GetEnvironmentVariable($_) })
    if ($overrides.Count) { throw "Unexpected environment overrides: $($overrides -join ', ')" }
    if (@(Get-Process -Name $competing -ErrorAction SilentlyContinue).Count) { throw 'Competing process' }

    $exeInfo = Get-Item -LiteralPath $exe
    $exeHash = (Get-FileHash -LiteralPath $exe).Hash
    if ($exeInfo.FullName -ine $exe -or $exeInfo.Attributes -band [IO.FileAttributes]::ReparsePoint -or $exeInfo.Length -ne 2500096 -or $exeHash -ne '993c6f4b16c52d82d246f48c4e67eb5c751d703379ccdd39c8f34cc512e003f3') { throw 'EXE verification failed' }
    $manifestPath = Join-Path $bin 'evox2-build.json'
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath).Hash
    if ($manifestHash -ne '8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116') { throw 'Manifest hash mismatch' }
    $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $testArtifact = @($m.Artifacts | Where-Object Name -eq $exeInfo.Name)
    if ($m.Source.Commit -ne $sha -or $m.BuildSource.Commit -ne $sha -or $m.BuildIdentity.Status -ne 'Verified' -or $m.Backend -ne 'ROCm' -or
        $m.BackendSettings.AmdGpuTarget -ne 'gfx1151' -or $testArtifact.Count -ne 1 -or $testArtifact[0].Sha256 -ne $exeHash -or $m.Validation.BackendTestRequested) { throw 'Manifest identity mismatch' }
    $cli = Join-Path $bin 'llama-cli.exe'
    if ($m.ExecutableIdentity.Sha256 -ne '538a12f93ed12ab2a639640d87aeb78582acca4d9d9c086fe5d6f9220f7c01de' -or (Get-FileHash -LiteralPath $cli).Hash -ne $m.ExecutableIdentity.Sha256) { throw 'CLI hash mismatch' }
    $verified = Test-Evox2RuntimeArtifacts -Executable $cli -Manifest $m
    if ($verified.Status -ne 'Verified' -or $verified.Scope -ne 'RuntimeDependenciesV1') { throw 'Runtime manifest verification failed' }
    $hip = @($m.Artifacts | Where-Object Name -eq 'ggml-hip.dll')
    if ($hip.Count -ne 1 -or $hip[0].Sha256 -ne '2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f' -or (Get-FileHash -LiteralPath (Join-Path $bin 'ggml-hip.dll')).Hash -ne $hip[0].Sha256) { throw 'HIP backend hash mismatch' }
    if ($m.Runtime.RuntimePolicy.Verification -ne 'DllAndRuntimeDataHashesVerified' -or $m.Runtime.RuntimePolicy.ObservedSdkVersion -ne '10.0.0' -or
        @($m.Runtime.RuntimeDlls).Count -ne 8 -or @($m.Runtime.RuntimeDataTrees).Count -ne 2 -or
        !(Test-Path -LiteralPath (Join-Path $m.Toolchain.RocmPath '..\rocm_sdk_device_gfx1151-10.0.0.dist-info') -PathType Container)) { throw 'TheRock runtime or SDK mismatch' }
    foreach ($dll in $m.Runtime.RuntimeDlls) {
        if ((Get-FileHash -LiteralPath $dll.Source.Path).Hash -ne $dll.Source.Sha256 -or $dll.Source.Sha256 -ne $dll.Destination.Sha256 -or (Get-FileHash -LiteralPath $dll.Destination.Path).Hash -ne $dll.Destination.Sha256) { throw "Runtime DLL mismatch: $($dll.Name)" }
    }
    foreach ($tree in $m.Runtime.RuntimeDataTrees) {
        if ($tree.Target -ne 'gfx1151' -or $tree.Source.DigestSha256 -ne $tree.Destination.DigestSha256 -or !(Test-Path -LiteralPath $tree.TargetDataPath -PathType Container)) { throw "Runtime data tree mismatch: $($tree.Name)" }
    }
    $adapter = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' | ForEach-Object {
        $key = Join-Path $_.PSPath '0000'
        if (Test-Path $key) { Get-ItemProperty -LiteralPath $key }
    } | Where-Object { $_.PSObject.Properties['DriverDesc'] -and $_.DriverDesc -like '*8060S*' })
    $driver = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'AMD Software*' })
    if ($adapter.Count -ne 1 -or $adapter[0].DriverVersion -ne '32.0.32029.2010' -or $adapter[0].'HardwareInformation.qwMemorySize' -ne 96GB -or $driver.Count -ne 1 -or $driver[0].DisplayVersion -ne '26.11.2') { throw 'Unexpected driver or UMA' }

    Save-Record 'provenance.json' ([ordered]@{
        TestCase=$Case; ChildExecutable=$exe; Arguments=$nativeArgs; ExeHash=$exeHash; ExeSize=$exeInfo.Length
        ManifestHash=$manifestHash; HipHash=$hip[0].Sha256; BuildSha=$sha; Head=$actualHead; Tracking=$tracking
        Diff=$diff; Overrides=$overrides; RuntimeStatus=$verified.Status; RuntimeScope=$verified.Scope
        Driver=$driver[0].DisplayVersion; SDK=$m.Runtime.RuntimePolicy.ObservedSdkVersion; UmaGiB=96
        Windows=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object CurrentBuild,UBR)
    })
    if (!$RunApproved) {
        $snapshot = Get-HostSnapshot
        Save-Record 'before.json' $snapshot
        Assert-Snapshot $snapshot
        Write-Host 'Preflight passed. Launch requires -RunApproved after individual approval.'
        return
    }

    $devices = Invoke-Evox2NativeCapture -FilePath $cli -ArgumentList @('--list-devices') -WorkingDirectory $bin
    Save-Record 'devices.json' $devices
    if ($devices.ExitCode -ne 0 -or @($devices.Lines -match '^\s+ROCm0: AMD Radeon.*8060S').Count -ne 1) {
        throw 'ROCm0 device verification failed.'
    }
    $run = @{
        Executable=$exe; NativeArguments=$nativeArgs; WorkingDirectory=$bin; LogDirectory=$log
        TimeoutMilliseconds=60000; MonitorAction=$monitor
        BeforeStart={
            $snapshot = Get-HostSnapshot
            Save-Record 'before.json' $snapshot
            Assert-Snapshot $snapshot
        }
    }
    $result = $null
    $supervisorError = $null
    try { $result = Invoke-D0SupervisedProcess @run }
    catch { $supervisorError = Get-D0Error $_ }
    $audit = [ordered]@{
        TestCase=$Case; Passed=$false; ExpectedOutput=$false; SamplesWhileChildAlive=0; NoActiveSamplesReason=$null; MajorEventCandidates=@(); Error=$supervisorError
    }
    try {
        $before = Get-Content -LiteralPath (Join-Path $log 'before.json') -Raw | ConvertFrom-Json
        $after = Get-HostSnapshot
        Save-Record 'after.json' $after
        $delta = @(foreach ($channel in 'System','Application') {
            $rows = @(Read-EventRange $channel $before.EventCursors.$channel $after.EventCursors[$channel])
            $events = @($rows | Select-Object RecordId,TimeCreated,ProviderName,Id,Level,Message,@{Name='MajorCandidate';Expression={Test-MajorEvent $_}})
            [pscustomobject]@{ Channel=$channel; Before=$before.EventCursors.$channel; After=$after.EventCursors[$channel]; Events=$events }
        })
        Save-Record 'event-delta.json' $delta
        $audit.MajorEventCandidates = @($delta | ForEach-Object Events | Where-Object MajorCandidate)
        Assert-Snapshot $after
        if ($after.BootTime -ne $before.BootTime -or $after.BootRecordId -ne $before.BootRecordId -or
            $after.Memory.Commit -gt $before.Memory.Commit + 4GB -or $after.GPU[0].Sum -gt $before.GPU[0].Sum + 4GB) {
            throw 'Post-run recovery gate failed.'
        }

        $samples = @(Get-ChildItem -LiteralPath $log -Filter 'sample-*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
        if ($result -and $result.ChildExitUtc) {
            $audit.SamplesWhileChildAlive = @($samples | Where-Object { $_.ChildStillRunning -and [DateTimeOffset]$_.End -le [DateTimeOffset]$result.ChildExitUtc }).Count
        }
        if (!$audit.SamplesWhileChildAlive) {
            $audit.NoActiveSamplesReason = if ($result -and $result.ChildExitUtc) {
                'No complete sample was captured while the child was alive.'
            } else { 'Child exit time is unavailable for sample alignment.' }
        }

        $out = @(Get-Content -LiteralPath (Join-Path $log 'stdout.log'))
        $err = Get-Content -LiteralPath (Join-Path $log 'stderr.log') -Raw
        $audit.ExpectedOutput = Test-D0GetRowsOutput $plan $out $err $bin
        $audit.Passed = ($audit.ExpectedOutput -and !$audit.MajorEventCandidates.Count -and $result -and $result.Started -and
            $result.ChildEnded -and $result.MonitorEnded -and $null -ne $result.ExitCode -and $result.ExitCode -eq 0 -and
            $null -ne $result.ChildElapsedMilliseconds -and $result.ChildElapsedMilliseconds -ge 0 -and
            $result.ChildElapsedMilliseconds -le 60000 -and !$result.StopReason -and !$result.Error -and
            !$result.StopError -and !$result.MonitorError -and !@($result.MetadataErrors).Count -and !@($result.CleanupErrors).Count -and
            $result.StdoutSaved -and $result.StderrSaved)
    } catch { $audit.Error = Get-D0Error $_ }
    Save-Record 'audit.json' $audit
    if (!$audit.Passed) { throw "D0 GET_ROWS acceptance criteria were not met. See $log." }
    Write-Host "Passed: $log"
} catch {
    Save-Record 'entry-error.json' (Get-D0Error $_)
    throw
} finally { Pop-Location }
