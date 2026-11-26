#requires -Version 5.1
Set-StrictMode -Version 3

function Write-D0Record {
    param([string]$Path, $Value)
    $temporary = "$Path.tmp"
    $json = ConvertTo-Json -InputObject $Value -Depth 12
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($true))
    if ([IO.File]::Exists($Path)) {
        [IO.File]::Replace($temporary, $Path, [NullString]::Value)
    } else {
        [IO.File]::Move($temporary, $Path)
    }
}

function Get-D0Error {
    param([Management.Automation.ErrorRecord]$Record)
    [ordered]@{
        Message = $Record.Exception.Message
        Id = $Record.FullyQualifiedErrorId
        Line = $Record.InvocationInfo.ScriptLineNumber
        Stack = $Record.ScriptStackTrace
    }
}

function Get-D0Identity {
    param([Diagnostics.Process]$Process, [string]$Executable)
    $start = $Process.StartTime.ToUniversalTime()
    [ordered]@{ Id = $Process.Id; StartUtc = $start.ToString('o'); StartTicks = $start.Ticks; Executable = $Executable }
}

function Test-D0ProcessIdentity {
    param($Identity)
    $live = Get-Process -Id $Identity.Id -ErrorAction SilentlyContinue
    if (!$live) { return $false }
    try {
        if ($live.HasExited) { return $false }
        $startTime = $live.StartTime
        if ($live.HasExited) { return $false }
        if ($null -eq $startTime) { throw "Start time unavailable for PID $($Identity.Id)" }
        if ($startTime.ToUniversalTime().Ticks -ne $Identity.StartTicks) { return $false }
        $image = $live.Path
        if ($live.HasExited) { return $false }
        if (!$image -or $image -ine $Identity.Executable) { throw "Image path mismatch or unavailable for PID $($Identity.Id)" }
        return $true
    } finally { $live.Dispose() }
}

function Stop-D0Child {
    param([Diagnostics.Process]$Process, $Identity)
    if ($Process.WaitForExit(0)) { return }
    if (!$Identity -or $Process.Id -ne $Identity.Id -or !$Identity.StartTicks -or !(Test-D0ProcessIdentity $Identity)) {
        if ($Process.WaitForExit(0)) { return }
        throw 'Owner identity could not be verified for stop.'
    }
    try { $Process.Kill() }
    catch { if (!$Process.WaitForExit(0)) { throw } }
}

function Invoke-D0SupervisedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$NativeArguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][ValidateRange(100,60000)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory)][scriptblock]$MonitorAction,
        [scriptblock]$BeforeStart = {}
    )
    $ErrorActionPreference = 'Stop'
    $modulePath = $PSCommandPath
    $childPath = Join-Path $LogDirectory 'child.json'
    $statusPath = Join-Path $LogDirectory 'status.json'
    $readyPath = Join-Path $LogDirectory 'monitor-ready.json'
    $errorPath = Join-Path $LogDirectory 'monitor-error.json'
    $stopPath = Join-Path $LogDirectory 'monitor.stop'
    $status = [ordered]@{
        Attempted = $false; Started = $false; Child = $null; ChildStartUtc = $null; ChildExitUtc = $null
        ExitCode = $null; ChildElapsedMilliseconds = $null; SupervisorElapsedMilliseconds = $null
        TimeoutMilliseconds = $TimeoutMilliseconds; StopReason = $null; ChildEnded = $null
        Monitor = $null; MonitorEnded = $null; MonitorError = $null
        StdoutSaved = $false; StderrSaved = $false; Error = $null; StopError = $null
        MetadataErrors = @(); CleanupErrors = @()
    }
    $proc = $null
    $job = $null
    $clock = $null
    $outFile = $null
    $errFile = $null
    $outCopy = $null
    $errCopy = $null
    Write-D0Record $statusPath $status
    try {
        $job = Start-Job -ArgumentList $modulePath,$LogDirectory,$MonitorAction.ToString() -ScriptBlock {
            param($module, $dir, $action)
            $ErrorActionPreference = 'Stop'
            try {
                Import-Module $module
                $worker = Get-Process -Id $PID
                try { Write-D0Record (Join-Path $dir 'monitor-ready.json') (Get-D0Identity $worker $worker.Path) }
                finally { $worker.Dispose() }
                & ([scriptblock]::Create($action)) $dir
            } catch {
                Write-D0Record (Join-Path $dir 'monitor-error.json') (Get-D0Error $_)
            }
        }
        $readyWait = [Diagnostics.Stopwatch]::StartNew()
        while (!(Test-Path -LiteralPath $readyPath)) {
            if ($readyWait.ElapsedMilliseconds -ge 10000 -or $job.State -in 'Completed','Failed','Stopped') { throw 'Monitor did not become ready.' }
            Start-Sleep -Milliseconds 25
        }
        $status.Monitor = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
        & $BeforeStart
        if ($job.State -ne 'Running' -or (Test-Path -LiteralPath $errorPath)) { throw 'Monitor is unavailable.' }

        # A one-byte buffer lets the monitor read short diagnostics before the child exits.
        $outFile = [IO.FileStream]::new((Join-Path $LogDirectory 'stdout.log'), 'CreateNew', 'Write', 'Read', 1, $true)
        $errFile = [IO.FileStream]::new((Join-Path $LogDirectory 'stderr.log'), 'CreateNew', 'Write', 'Read', 1, $true)
        $startInfo = [Diagnostics.ProcessStartInfo]::new($Executable, $NativeArguments)
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $status.Attempted = $true
        Write-D0Record $statusPath $status
        $clock = [Diagnostics.Stopwatch]::StartNew()
        # Process.Start retains the handle returned by process creation.
        $proc = [Diagnostics.Process]::Start($startInfo)
        $status.Started = $true
        $outCopy = $proc.StandardOutput.BaseStream.CopyToAsync($outFile)
        $errCopy = $proc.StandardError.BaseStream.CopyToAsync($errFile)
        $status.Child = [ordered]@{ Id = $proc.Id; StartUtc = $null; StartTicks = $null; Executable = $Executable }
        try {
            $status.Child = Get-D0Identity $proc $Executable
            $status.ChildStartUtc = $status.Child.StartUtc
        } catch { $status.MetadataErrors += Get-D0Error $_ }
        Write-D0Record $childPath $status.Child

        while (!$proc.WaitForExit(0)) {
            $remaining = $TimeoutMilliseconds - $clock.ElapsedMilliseconds
            if ($remaining -le 0) {
                $status.StopReason = 'Timeout'
                Stop-D0Child $proc $status.Child
                break
            }
            if ((Test-Path -LiteralPath $errorPath) -or $job.State -ne 'Running') {
                if ($proc.WaitForExit(0)) { break }
                $status.StopReason = 'MonitorError'
                Stop-D0Child $proc $status.Child
                break
            }
            $null = $proc.WaitForExit([int][Math]::Min(200, $remaining))
        }
    } catch {
        $status.Error = Get-D0Error $_
        if ($proc) {
            try { Stop-D0Child $proc $status.Child }
            catch { $status.StopError = Get-D0Error $_ }
        }
    } finally {
        if ($proc) {
            try {
                $status.ChildEnded = $proc.WaitForExit(3000)
                $status.SupervisorElapsedMilliseconds = $clock.Elapsed.TotalMilliseconds
                if ($status.ChildEnded) {
                    try {
                        $code = $proc.ExitCode
                        if ($null -eq $code) { throw 'Child exit code is unavailable.' }
                        $status.ExitCode = $code
                    } catch { $status.MetadataErrors += Get-D0Error $_ }
                    try {
                        $exitTime = $proc.ExitTime
                        if ($null -eq $exitTime) { throw 'Child exit timestamp is unavailable.' }
                        $status.ChildExitUtc = $exitTime.ToUniversalTime().ToString('o')
                        if ($status.ChildStartUtc) {
                            $status.ChildElapsedMilliseconds = ([DateTimeOffset]$status.ChildExitUtc - [DateTimeOffset]$status.ChildStartUtc).TotalMilliseconds
                        }
                    } catch { $status.MetadataErrors += Get-D0Error $_ }
                }
            } catch { $status.MetadataErrors += Get-D0Error $_ }
        }

        foreach ($stream in @(
            @{ File = $outFile; Copy = $outCopy; Key = 'StdoutSaved' },
            @{ File = $errFile; Copy = $errCopy; Key = 'StderrSaved' }
        )) {
            try {
                if ($stream.Copy -and $stream.Copy.Wait(5000)) {
                    $stream.File.Flush()
                    $status[$stream.Key] = $true
                }
            } catch { $status.CleanupErrors += Get-D0Error $_ }
            finally { if ($stream.File) { $stream.File.Dispose() } }
        }
        if ($proc) { $proc.Dispose() }
        try { Write-D0Record $statusPath $status }
        catch { $status.CleanupErrors += Get-D0Error $_ }

        if ($job) {
            try {
                [IO.File]::WriteAllText($stopPath, 'stop')
                $null = Wait-Job -Job $job -Timeout 8
                if (!$status.Monitor -and (Test-Path -LiteralPath $readyPath)) {
                    $status.Monitor = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
                }
                if ($job.State -notin 'Completed','Failed','Stopped') {
                    if (!$status.Monitor) { throw 'Monitor identity unavailable for forced cleanup.' }
                    if (Test-D0ProcessIdentity $status.Monitor) {
                        $worker = Get-Process -Id $status.Monitor.Id
                        try {
                            if ($worker.StartTime.ToUniversalTime().Ticks -ne $status.Monitor.StartTicks -or $worker.Path -ine $status.Monitor.Executable) {
                                throw 'Monitor identity changed before forced cleanup.'
                            }
                            $worker.Kill()
                            $null = $worker.WaitForExit(3000)
                        } finally { $worker.Dispose() }
                    }
                    $null = Wait-Job -Job $job -Timeout 3
                    throw 'Monitor exceeded its cleanup deadline.'
                }
            } catch { $status.CleanupErrors += Get-D0Error $_ }
            if ($job.State -in 'Completed','Failed','Stopped') {
                try {
                    if ($job.State -ne 'Completed') {
                        $status.CleanupErrors += "Monitor job ended in state $($job.State)."
                    }
                    Remove-Job -Job $job
                } catch { $status.CleanupErrors += Get-D0Error $_ }
            }
            if ($status.Monitor) {
                try {
                    $endWait = [Diagnostics.Stopwatch]::StartNew()
                    while ((Test-D0ProcessIdentity $status.Monitor) -and $endWait.ElapsedMilliseconds -lt 3000) {
                        Start-Sleep -Milliseconds 50
                    }
                    $status.MonitorEnded = !(Test-D0ProcessIdentity $status.Monitor)
                } catch { $status.CleanupErrors += Get-D0Error $_ }
            }
            if (Test-Path -LiteralPath $errorPath) { $status.MonitorError = Get-Content -LiteralPath $errorPath -Raw | ConvertFrom-Json }
        }
        Write-D0Record $statusPath $status
    }
    [pscustomobject]$status
}

Export-ModuleMember -Function Invoke-D0SupervisedProcess,Write-D0Record,Get-D0Error,Get-D0Identity,Test-D0ProcessIdentity
