#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Evox2.BuildState.psm1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('evox2-state-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($root)
try {
    $fixture = @'
[Console]::WriteLine('[1/3] Building first.cpp.obj')
[Console]::Error.WriteLine('fixture stderr')
[Console]::Out.Flush()
$exe = Join-Path $PSHOME 'powershell.exe'
$child = Start-Process -FilePath $exe -ArgumentList '-NoProfile','-NonInteractive','-Command','Start-Sleep -Milliseconds 1900' -NoNewWindow -PassThru
$child.WaitForExit()
[Console]::Write(('[2/3] Building second.cpp.obj' + [char]13 + '[3/3] Linking fixture.exe'))
exit EXIT_CODE
'@
    foreach ($code in 0, 7) {
        $stem = Join-Path $root "test-$code"
        $result = [ordered]@{ ExitCode = 1; Stdout = "$stem.stdout.log"; Stderr = "$stem.stderr.log"; ElapsedSeconds = $null }
        $payload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixture.Replace('EXIT_CODE', [string]$code)))
        $options = @{
            Program = "$PSHOME\powershell.exe"
            Arguments = @('-NoProfile','-NonInteractive','-EncodedCommand',$payload)
            Stem = $stem; Result = $result; Conditions = @{ Mode = 'Fixture' }; IntervalMilliseconds = 250
        }
        Invoke-Evox2TrackedBuildProcess @options
        $run = Read-Evox2BuildState $stem
        $expected = if ($code -eq 0) { 'Succeeded' } else { 'Failed' }
        if ($run.Status -ne $expected -or $run.Result.ExitCode -ne $code -or
            $run.Snapshot.Ninja.Completed -ne 3 -or $run.Snapshot.Ninja.Target -ne 'fixture.exe' -or
            $result.ElapsedSeconds -lt 1.9 -or (Get-Content -LiteralPath $result.Stderr -Raw) -notmatch 'fixture stderr') {
            throw "Unexpected completed fixture state for exit $code"
        }
        $events = @(Get-Content -LiteralPath "$stem.progress.jsonl" | ForEach-Object { ConvertFrom-Json $_ })
        $worker = $run.Snapshot.WorkerProcess
        $children = @($events | ForEach-Object { $_.Processes } | Where-Object { $_.ParentId -eq $worker.Id })
        if (!$children.Count -or !($events | Where-Object { $_.Ninja.Completed -eq 1 }) -or
            (Test-Evox2ProcessIdentity $worker) -or ($children | Where-Object { Test-Evox2ProcessIdentity $_ })) {
            throw 'Progress, child process, or process termination evidence missing.'
        }
    }

    $stem = Join-Path $root 'missing-result'
    $current = Get-Evox2ProcessIdentity (Get-Process -Id $PID)
    $stale = [pscustomobject]@{ Id = $current.Id; StartedUtc = ([datetime]$current.StartedUtc).AddSeconds(-10).ToUniversalTime().ToString('o') }
    Write-Evox2BuildRecord "$stem.state.json" @{ ExecutionId = 'missing-result'; Status = 'Succeeded'; WorkerProcess = $stale }
    if ((Read-Evox2BuildState $stem).Status -ne 'Unconfirmed' -or (Test-Evox2ProcessIdentity $stale)) { throw 'Unconfirmed or stale PID was accepted.' }
    [IO.File]::WriteAllText("$stem.state.json", '{invalid')
    Write-Evox2BuildRecord "$stem.worker.json" @{ ExecutionId = 'missing-result'; Phase = 'Build'; Process = $current }
    if ((Read-Evox2BuildState $stem).Status -ne 'Running') { throw 'Valid worker did not recover missing state.' }
    [IO.File]::WriteAllText("$stem.result.json", '{invalid')
    if ((Read-Evox2BuildState $stem).Status -ne 'Running') { throw 'Invalid result changed the verified process state.' }
    [IO.File]::Delete("$stem.worker.json")
    if ((Read-Evox2BuildState $stem).Status -ne 'Unconfirmed') { throw 'Corrupted records were treated as a finished run.' }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
'Build state tests passed.'
