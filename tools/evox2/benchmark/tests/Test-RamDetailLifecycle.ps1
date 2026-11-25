#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$benchmark = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('evox2-ram-lifecycle-' + [guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($work)
$fixtureModule = Join-Path $work 'Evox2.RamDetail.psm1'
$exe = Join-Path $PSHOME 'powershell.exe'
$processes = @()
$originalMode = $env:EVOX2_TEST_RAM_MODE
Remove-Item Env:EVOX2_TEST_RAM_MODE -ErrorAction SilentlyContinue
function Assert-True($Condition,[string]$Message) { if (!$Condition) { throw $Message } }
try {
    foreach ($file in 'Evox2.RamDetail.psm1','Evox2.Benchmark.psm1','Monitor-Evox2RamDetail.ps1') {
        Copy-Item -LiteralPath (Join-Path $benchmark $file) -Destination $work
    }
    $shim = @'
$script:calls = 0
function Get-Evox2SystemMemory {
    $script:calls++
    if ($env:EVOX2_TEST_RAM_MODE -eq 'denied' -or $script:calls -in 1,2,7) { throw 'synthetic native acquisition error' }
    [pscustomobject]@{ Total=1GB; Available=512MB; Used=512MB; Commit=768MB; CommitLimit=2GB; CommitPercent=37.5; Cache=128MB; CommitPeak=1GB }
}
function Get-Evox2ProcessMemory {
    [pscustomobject]@{ Values=@{ WorkingSet64=16MB; PrivateMemorySize64=20MB; VirtualMemorySize64=256MB }; Error=$null }
}
Export-ModuleMember -Function Get-Evox2SystemMemory,Get-Evox2ProcessMemory
'@
    [IO.File]::WriteAllText((Join-Path $work 'Evox2.Memory.psm1'), $shim, [Text.UTF8Encoding]::new($true))
    Import-Module $fixtureModule -Force
    function New-TestDetail([string]$Name, [int]$Timeout, [int]$ReadyTimeout) {
        $dir = Join-Path $work $Name
        [void][IO.Directory]::CreateDirectory($dir)
        $setting = @{ IntervalMs=100; PreSeconds=0; PostSeconds=1; TimeoutSeconds=$Timeout; ReadyTimeoutSeconds=$ReadyTimeout
            RecoveryToleranceMiB=8; PeakThresholdMiB=1 }
        New-Evox2RamDetail $dir $Name $setting (Join-Path $dir 'stdout.log') (Join-Path $dir 'stderr.log')
    }

    $detail = New-TestDetail 'recover-and-abort' 10 6
    $processes += $detail
    Start-Evox2RamDetail $detail
    Wait-Evox2RamDetailReady $detail
    Write-Evox2RamLaunch $detail
    # Simulate a target launch exception: no PID was created.
    Stop-Evox2RamDetail $detail $null
    $rows = @(Import-Csv -LiteralPath $detail.CsvPath)
    $result = Get-Evox2RamDetailResult $detail (Join-Path $work 'none')
    Assert-True ($rows[0].NativeStatus -eq 'Unavailable' -and $rows[0].UsedRAMBytes -eq '' -and
        $rows[-1].UsedRAMBytes -eq [string]512MB) 'Initial native failure was not preserved or did not recover'
    Assert-True ($result.Status -eq 'Partial' -and $result.Monitor.StopReason -eq 'StoppedByLauncher' -and
        $result.SystemRecovery -eq 'Unobserved' -and $detail.Process.HasExited) 'Launch abort not contained'

    $env:EVOX2_TEST_RAM_MODE = 'denied'
    $detail = New-TestDetail 'ready-timeout' 15 2
    $processes += $detail
    Start-Evox2RamDetail $detail
    $failed = $false
    try { Wait-Evox2RamDetailReady $detail } catch { $failed = $_.Exception.Message -like '*readiness deadline*' }
    Stop-Evox2RamDetail $detail $null
    $result = Get-Evox2RamDetailResult $detail (Join-Path $work 'none')
    Assert-True ($failed -and $detail.Process.HasExited -and $result.Status -eq 'Unavailable' -and
        $result.NativeMissing -gt 0 -and $null -eq $result.PeakUsedMiB) 'Readiness timeout was not fail-open and bounded'
    Remove-Item Env:EVOX2_TEST_RAM_MODE

    $detail = New-TestDetail 'sampling-timeout' 2 6
    $processes += $detail
    Start-Evox2RamDetail $detail
    Wait-Evox2RamDetailReady $detail
    Assert-True ($detail.Process.WaitForExit(6000)) 'Hard sampler timeout was ignored'
    Stop-Evox2RamDetail $detail $null
    $result = Get-Evox2RamDetailResult $detail (Join-Path $work 'none')
    Assert-True ($result.Status -eq 'Partial' -and $result.Monitor.StopReason -eq 'Timeout') 'Timed out sampler was misclassified'

    $detail = New-TestDetail 'bad-attach' 20 6
    $processes += $detail
    Start-Evox2RamDetail $detail
    Wait-Evox2RamDetailReady $detail
    $target = Start-Process -FilePath $exe -ArgumentList '-NoProfile -Command "Start-Sleep -Milliseconds 2500"' -NoNewWindow -PassThru
    try {
        $null = $target.Handle
        Write-Evox2RamLaunch $detail
        # A recycled or unidentifiable PID must never be attached.
        $path = Join-Path $detail.Directory 'ram-attach.json'
        [IO.File]::WriteAllText("$path.tmp", (@{ Id=$target.Id; Name='fixture'; StartUtc=''; StartUtcTicks=1 } | ConvertTo-Json -Compress))
        [IO.File]::Move("$path.tmp", $path)
        Assert-True ($target.WaitForExit(8000)) 'Short fixture target failed to stop'
    } finally {
        if (!$target.HasExited) { $target.Kill(); $null=$target.WaitForExit(2000) }
        Stop-Evox2RamDetail $detail $target
    }
    $result = Get-Evox2RamDetailResult $detail (Join-Path $work 'none')
    Assert-True ($result.Status -eq 'Partial' -and $result.Monitor.AttachError -and $null -eq $result.Monitor.AttachedUtc -and
        $result.PostNativeSamples -gt 0 -and $result.RunningMetrics.WorkingSetBytes.ValidCount -eq 0) 'Wrong PID was attached or post observation was lost'
    Assert-True ($detail.Process.HasExited) 'RAM monitor still running after PID failure'
    $detail = New-TestDetail 'parent-exit' 20 6
    $launcher = Join-Path $work 'parent-launcher.ps1'
    $launchCode = @'
param($Module, $Directory)
$ErrorActionPreference = 'Stop'
Import-Module $Module -Force
$settings = @{ IntervalMs=100; PreSeconds=0; PostSeconds=1; TimeoutSeconds=20; ReadyTimeoutSeconds=6
    RecoveryToleranceMiB=8; PeakThresholdMiB=1 }
$detail = New-Evox2RamDetail $Directory 'parent-exit' $settings (Join-Path $Directory 'stdout.log') (Join-Path $Directory 'stderr.log')
Start-Evox2RamDetail $detail
Wait-Evox2RamDetailReady $detail
'@
    [IO.File]::WriteAllText($launcher, $launchCode, [Text.UTF8Encoding]::new($true))
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "{0}" -Module "{1}" -Directory "{2}"' -f $launcher,$fixtureModule,$detail.Directory
    $abruptParent = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -PassThru
    try {
        Assert-True ($abruptParent.WaitForExit(8000)) 'Unexpected launcher hang'
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $state = $null
        while (!$state -and $timer.Elapsed.TotalSeconds -lt 6) {
            if (Test-Path -LiteralPath $detail.MonitorPath) {
                try { $state = Get-Content -LiteralPath $detail.MonitorPath -Raw | ConvertFrom-Json } catch {}
            }
            if (!$state) { Start-Sleep -Milliseconds 100 }
        }
        Assert-True ($state -and $state.StopReason -eq 'ParentExited') 'Sampler did not detect launcher exit'
        $remaining = Get-Process -Id $state.MonitorPid -ErrorAction SilentlyContinue
        Assert-True (!$remaining -or $remaining.WaitForExit(2000)) 'Sampler remained after launcher exit'
    } finally {
        if (!$abruptParent.HasExited) { $abruptParent.Kill(); $null = $abruptParent.WaitForExit(2000) }
    }
    Write-Output 'PASS missing native samples and recovery, launch abort, readiness timeout, sampling timeout, parent exit, PID identity and bounded cleanup'
} finally {
    if ($null -eq $originalMode) { Remove-Item Env:EVOX2_TEST_RAM_MODE -ErrorAction SilentlyContinue }
    else { $env:EVOX2_TEST_RAM_MODE = $originalMode }
    foreach ($detail in $processes) {
        if ($detail.Process -and !$detail.Process.HasExited) { Stop-Evox2RamDetail $detail $null }
    }
    Remove-Item -LiteralPath $work -Recurse
}
