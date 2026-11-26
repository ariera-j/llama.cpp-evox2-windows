#requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'D0GetRows.Supervisor.psm1') -Force
$dummy = Join-Path $env:SystemRoot 'System32\cmd.exe'
$root = Join-Path 'C:\llama-build\_logs\codex' ('d0-2c-dummy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
Write-Host "Dummy logs: $root"

$fast = 'echo dummy-stdout & echo dummy-stderr 1>&2'
$goodMonitor = {
    param($dir)
    while (!(Test-Path -LiteralPath (Join-Path $dir 'monitor.stop'))) { Start-Sleep -Milliseconds 25 }
}
$badMonitor = {
    param($dir)
    while (!(Test-Path -LiteralPath (Join-Path $dir 'child.json'))) {
        if (Test-Path -LiteralPath (Join-Path $dir 'monitor.stop')) { return }
        Start-Sleep -Milliseconds 25
    }
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Item -LiteralPath (Join-Path $dir 'stderr.log')).Length -eq 0 -and $wait.ElapsedMilliseconds -lt 3000) {
        Start-Sleep -Milliseconds 25
    }
    if ((Get-Item -LiteralPath (Join-Path $dir 'stderr.log')).Length -eq 0) { throw 'Dummy stderr was not visible while the child was running.' }
    throw 'Intentional dummy monitor exception'
}
$sleepExe = Join-Path $PSHOME 'powershell.exe'
function Get-SleepArguments([int]$Seconds) {
    $code = "[Console]::WriteLine('dummy-stdout'); [Console]::Error.WriteLine('dummy-stderr'); Start-Sleep -Seconds $Seconds; exit 0"
    '-NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
}
$cases = @(
    @{ Name='fast-zero'; Program=$dummy; Native="/d /c $fast & exit 0"; Limit=4000; Expected=0; Stop=$null; Monitor=$goodMonitor },
    @{ Name='fast-nonzero'; Program=$dummy; Native="/d /c $fast & exit 7"; Limit=4000; Expected=7; Stop=$null; Monitor=$goodMonitor },
    @{ Name='delayed-zero'; Program=$sleepExe; Native=(Get-SleepArguments 3); Limit=8000; Expected=0; Stop=$null; Monitor=$goodMonitor },
    @{ Name='timeout'; Program=$sleepExe; Native=(Get-SleepArguments 20); Limit=2000; Expected=$null; Stop='Timeout'; Monitor=$goodMonitor },
    @{ Name='monitor-error'; Program=$sleepExe; Native=(Get-SleepArguments 20); Limit=8000; Expected=$null; Stop='MonitorError'; Monitor=$badMonitor }
)
$results = foreach ($case in $cases) {
    $dir = Join-Path $root $case.Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $params = @{
        Executable=$case.Program; NativeArguments=$case.Native; WorkingDirectory=$dir
        LogDirectory=$dir; TimeoutMilliseconds=$case.Limit; MonitorAction=$case.Monitor
        BeforeStart={ Write-D0Record (Join-Path $dir 'fixture-ready.json') @{ Case=$case.Name } }
    }
    $r = Invoke-D0SupervisedProcess @params
    $outOk = (Get-Content -LiteralPath (Join-Path $dir 'stdout.log') -Raw -ErrorAction SilentlyContinue) -match 'dummy-stdout'
    $errOk = (Get-Content -LiteralPath (Join-Path $dir 'stderr.log') -Raw -ErrorAction SilentlyContinue) -match 'dummy-stderr'
    $childAbsent = $r.Child -and !(Test-D0ProcessIdentity $r.Child)
    $codeOk = if ($null -eq $case.Expected) { $null -ne $r.ExitCode -and $r.ExitCode -ne 0 } else { $null -ne $r.ExitCode -and $r.ExitCode -eq $case.Expected }
    $monitorOk = if ($case.Stop -eq 'MonitorError') {
        $r.MonitorError -and $r.MonitorError.Message -eq 'Intentional dummy monitor exception'
    } else { !$r.MonitorError }
    $timeOk = $null -ne $r.ChildElapsedMilliseconds -and $r.ChildElapsedMilliseconds -ge 0 -and $null -ne $r.SupervisorElapsedMilliseconds
    if ($case.Name -eq 'delayed-zero') { $timeOk = $timeOk -and $r.ChildElapsedMilliseconds -ge 3000 }
    if ($case.Name -eq 'timeout') { $timeOk = $timeOk -and $r.SupervisorElapsedMilliseconds -ge $case.Limit -and $r.SupervisorElapsedMilliseconds -lt 8000 }
    [pscustomobject]@{
        Case=$case.Name; ExpectedExit=$case.Expected; ExitCode=$r.ExitCode; ExpectedStop=$case.Stop; StopReason=$r.StopReason
        ChildElapsedMilliseconds=$r.ChildElapsedMilliseconds; SupervisorElapsedMilliseconds=$r.SupervisorElapsedMilliseconds
        ChildStartUtc=$r.ChildStartUtc; ChildExitUtc=$r.ChildExitUtc; Stdout=$outOk; Stderr=$errOk
        ChildAbsent=$childAbsent; MonitorEnded=$r.MonitorEnded; Evidence=$dir
        Passed=((Test-Path -LiteralPath (Join-Path $dir 'fixture-ready.json')) -and $r.Started -and $r.ChildEnded -and $childAbsent -and $r.MonitorEnded -and !$r.Error -and !$r.StopError -and
            !@($r.MetadataErrors).Count -and !@($r.CleanupErrors).Count -and $r.StdoutSaved -and $r.StderrSaved -and $outOk -and $errOk -and
            $codeOk -and $timeOk -and $monitorOk -and $r.StopReason -eq $case.Stop)
    }
}
Write-D0Record (Join-Path $root 'dummy-summary.json') @($results)
$results | Format-Table Case,ExitCode,ChildElapsedMilliseconds,SupervisorElapsedMilliseconds,StopReason,ChildAbsent,MonitorEnded,Passed
if (@($results | Where-Object { !$_.Passed }).Count) { throw "Dummy verification failed. See $root" }
