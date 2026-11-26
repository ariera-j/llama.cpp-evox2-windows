#requires -Version 5.1

function Write-Evox2BuildRecord {
    param([string]$Path, [object]$Record)
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, ($Record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temp, $Path) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Read-Evox2BuildRecord([string]$Path) {
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try { return ConvertFrom-Json ($reader.ReadToEnd()) -ErrorAction Stop }
        finally { $reader.Dispose() }
    } catch { return $null }
}

function Get-Evox2ProcessIdentity([Diagnostics.Process]$Process) {
    try {
        [pscustomobject]@{
            Id = $Process.Id
            Name = $Process.ProcessName
            StartedUtc = $Process.StartTime.ToUniversalTime().ToString('o')
        }
    } catch { return $null }
}

function Test-Evox2ProcessIdentity($Identity) {
    if (!$Identity -or !$Identity.StartedUtc -or $Identity.Id -isnot [int] -or $Identity.Id -le 0) { return $false }
    $instance = Get-Process -Id $Identity.Id -ErrorAction SilentlyContinue
    if (!$instance) { return $false }
    return (Get-Evox2ProcessIdentity $instance).StartedUtc -ceq $Identity.StartedUtc
}

function Initialize-Evox2ProcessSnapshot {
    if ('Evox2BuildProcessSnapshot' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class Evox2BuildProcessSnapshot
{
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(uint access, bool inherit, int pid);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationProcess(IntPtr handle, int informationClass, IntPtr buffer, int size, out int needed);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ProcessEntry
    {
        public uint Size, Usage, Id;
        public IntPtr DefaultHeap;
        public uint ModuleId, Threads, ParentId;
        public int BasePriority;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", EntryPoint = "Process32FirstW")]
    static extern bool Process32First(IntPtr handle, ref ProcessEntry entry);
    [DllImport("kernel32.dll", EntryPoint = "Process32NextW")]
    static extern bool Process32Next(IntPtr handle, ref ProcessEntry entry);

    public static Dictionary<int, int> Parents()
    {
        IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
        if (snapshot == new IntPtr(-1)) throw new System.ComponentModel.Win32Exception();
        try
        {
            var parents = new Dictionary<int, int>();
            var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf(typeof(ProcessEntry)) };
            if (Process32First(snapshot, ref entry))
            {
                do { parents[(int)entry.Id] = (int)entry.ParentId; }
                while (Process32Next(snapshot, ref entry));
            }
            return parents;
        }
        finally { CloseHandle(snapshot); }
    }

    public static string ReadCommandLine(int pid)
    {
        IntPtr handle = OpenProcess(0x1000, false, pid);
        if (handle == IntPtr.Zero) return null;
        try
        {
            int needed;
            NtQueryInformationProcess(handle, 60, IntPtr.Zero, 0, out needed);
            if (needed <= 0 || needed > 65536) return null;
            IntPtr buffer = Marshal.AllocHGlobal(needed);
            try
            {
                int status = NtQueryInformationProcess(handle, 60, buffer, needed, out needed);
                if (status != 0) return null;
                ushort length = unchecked((ushort)Marshal.ReadInt16(buffer));
                IntPtr text = Marshal.ReadIntPtr(buffer, IntPtr.Size);
                return Marshal.PtrToStringUni(text, length / sizeof(char));
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        finally { CloseHandle(handle); }
    }
}
'@
}

function Get-Evox2BuildProcesses($Root) {
    if (!(Test-Evox2ProcessIdentity $Root)) { return }
    $parents = [Evox2BuildProcessSnapshot]::Parents()
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue($Root)
    $seen = @{}
    while ($queue.Count) {
        $identity = $queue.Dequeue()
        if ($seen.ContainsKey($identity.Id) -or !(Test-Evox2ProcessIdentity $identity)) { continue }
        $seen[$identity.Id] = $true
        $process = Get-Process -Id $identity.Id -ErrorAction SilentlyContinue
        if (!$process) { continue }
        $command = $null
        if ($identity.Name -match '^(clang(?:\+\+|-cl|-\d+)?|cl|glslc|hipcc)$') {
            $line = [Evox2BuildProcessSnapshot]::ReadCommandLine($identity.Id)
            # Persist only compiler, source/target names and selected architecture/optimization switches.
            $source = @([regex]::Matches([string]$line, '(?i)(?:^|[\\/\s"])([a-z0-9_.+-]+\.(?:c|cc|cxx|cpp|cu|comp|obj|rsp))(?=\s|"|$)') |
                ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique -First 4)
            $arch = @([regex]::Matches([string]$line, '(?i)(?:--offload-arch=gfx[0-9a-f]+|-march=[a-z0-9_-]+|-O[0-3s]|/O[12dx])(?=\s|$)') |
                ForEach-Object { $_.Value } | Select-Object -Unique -First 4)
            if ($line) { $command = (@($identity.Name) + $arch + $source) -join ' ' }
        }
        if (!(Test-Evox2ProcessIdentity $identity)) { continue }
        [pscustomobject]@{
            Id = $identity.Id; ParentId = $(if ($parents.ContainsKey($identity.Id)) { $parents[$identity.Id] })
            Name = $identity.Name; StartedUtc = $identity.StartedUtc
            CpuSeconds = $process.CPU; WorkingSetBytes = $process.WorkingSet64; CompilerCommand = $command
        }
        foreach ($id in $parents.Keys) {
            if ($parents[$id] -ne $identity.Id -or $seen.ContainsKey($id)) { continue }
            $child = Get-Process -Id $id -ErrorAction SilentlyContinue
            if (!$child) { continue }
            $childIdentity = Get-Evox2ProcessIdentity $child
            if ($childIdentity -and [datetime]$childIdentity.StartedUtc -ge [datetime]$identity.StartedUtc) {
                $queue.Enqueue($childIdentity)
            }
        }
    }
}

function Get-Evox2NinjaProgress {
    param([string]$Path)
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        try {
            $end = $stream.Length
            $start = [Math]::Max(0, $end - 32768)
            $stream.Position = $start
            $buffer = New-Object byte[] ([int]($end - $start))
            $count = $stream.Read($buffer, 0, $buffer.Length)
        } finally { $stream.Dispose() }
    } catch { return }
    $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
    $rows = @($text.TrimStart([char]0xFEFF) -split '\r\n|\r|\n')
    for ($i = $rows.Count - 1; $i -ge [int]($start -gt 0); $i--) {
        if ($rows[$i] -notmatch '^\[(?<done>\d{1,9})/(?<total>\d{1,9})\]\s*(?<message>.*)$') { continue }
        $completed = [int]$Matches.done
        $total = [int]$Matches.total
        $target = [regex]::Match($Matches.message, '(?i)([a-z0-9_.+-]+\.(?:c|cc|cpp|cu|comp|obj|dll|exe|lib|rsp))\s*$').Groups[1].Value
        return [pscustomobject]@{ Completed = $completed; Total = $total; Target = $target }
    }
}

function Read-Evox2BuildState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Stem)
    $snapshot = Read-Evox2BuildRecord "$Stem.state.json"
    $result = Read-Evox2BuildRecord "$Stem.result.json"
    $worker = Read-Evox2BuildRecord "$Stem.worker.json"
    $status = 'Unconfirmed'
    $id = [IO.Path]::GetFileName($Stem)
    if ($result -and $result.ExecutionId -ceq $id -and $result.ExitCode -is [int] -and $result.Outcome -cin @('Succeeded','Failed')) {
        $status = if ($result.ExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
    } elseif (($snapshot.ExecutionId -ceq $id -and (Test-Evox2ProcessIdentity $snapshot.WorkerProcess)) -or
        ($worker.ExecutionId -ceq $id -and (Test-Evox2ProcessIdentity $worker.Process))) {
        $status = 'Running'
    }
    $live = @(foreach ($identity in $snapshot.Processes) {
        if ($snapshot.ExecutionId -ceq $id -and (Test-Evox2ProcessIdentity $identity)) { $identity }
    })
    [pscustomobject]@{ Status = $status; Snapshot = $snapshot; Worker = $worker; Result = $result; LiveProcesses = $live }
}

function Invoke-Evox2TrackedBuildProcess {
    [CmdletBinding()]
    param(
        [string]$Program, [string[]]$Arguments, [string]$Stem,
        [System.Collections.IDictionary]$Result, [object]$Conditions,
        [ValidateRange(100,30000)][int]$IntervalMilliseconds = 5000
    )

    $ErrorActionPreference = 'Stop'
    $id = [IO.Path]::GetFileName($Stem)
    $Result.ExecutionId = $id
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $supervisor = Get-Evox2ProcessIdentity (Get-Process -Id $PID)
    $snapshot = [ordered]@{
        Version = 1; ExecutionId = $id; Status = 'Starting'; StartedUtc = [datetime]::UtcNow.ToString('o')
        UpdatedUtc = $null; ElapsedSeconds = 0; SupervisorProcess = $supervisor; WorkerProcess = $null
        Conditions = $Conditions; Worker = $null; Processes = @(); Ninja = $null
        Stdout = $Result.Stdout; Stderr = $Result.Stderr; ExitCode = $null; TelemetryError = $null
    }
    Write-Evox2BuildRecord "$Stem.state.json" $snapshot
    $process = $null
    $observedExit = $false
    try {
        Initialize-Evox2ProcessSnapshot
        $launch = @{
            FilePath = $Program; ArgumentList = $Arguments; NoNewWindow = $true; PassThru = $true
            RedirectStandardOutput = $Result.Stdout; RedirectStandardError = $Result.Stderr
        }
        $process = Start-Process @launch
        $null = $process.Handle
        $snapshot.WorkerProcess = Get-Evox2ProcessIdentity $process
        $snapshot.Status = 'Running'
        try { Write-Evox2BuildRecord "$Stem.state.json" $snapshot }
        catch { $snapshot.TelemetryError = $_.Exception.GetType().Name }
        while (!$process.WaitForExit($IntervalMilliseconds)) {
            try {
                $snapshot.UpdatedUtc = [datetime]::UtcNow.ToString('o')
                $snapshot.ElapsedSeconds = $clock.Elapsed.TotalSeconds
                $snapshot.Worker = Read-Evox2BuildRecord "$Stem.worker.json"
                $snapshot.Processes = @(Get-Evox2BuildProcesses $snapshot.WorkerProcess)
                $ninja = Get-Evox2NinjaProgress $Result.Stdout
                if ($ninja) { $snapshot.Ninja = $ninja }
                Write-Evox2BuildRecord "$Stem.state.json" $snapshot
                $progress = [ordered]@{
                    UpdatedUtc = $snapshot.UpdatedUtc; ElapsedSeconds = $snapshot.ElapsedSeconds
                    Phase = $snapshot.Worker.Phase; Ninja = $snapshot.Ninja; Processes = $snapshot.Processes
                }
                $line = $progress | ConvertTo-Json -Depth 6 -Compress
                [IO.File]::AppendAllText("$Stem.progress.jsonl", $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
            } catch {
                $snapshot.TelemetryError = $_.Exception.GetType().Name
            }
        }
        $process.WaitForExit()
        if ($null -eq $process.ExitCode) { throw 'The child process exit code is unavailable.' }
        $Result.ExitCode = $process.ExitCode
        $observedExit = $true
    } finally {
        $Result.ElapsedSeconds = $clock.Elapsed.TotalSeconds
        $snapshot.UpdatedUtc = [datetime]::UtcNow.ToString('o')
        $snapshot.ElapsedSeconds = $Result.ElapsedSeconds
        $worker = Read-Evox2BuildRecord "$Stem.worker.json"
        if ($worker) { $snapshot.Worker = $worker }
        $ninja = Get-Evox2NinjaProgress $Result.Stdout
        if ($ninja) { $snapshot.Ninja = $ninja }
        if ($observedExit) {
            $snapshot.ExitCode = $Result.ExitCode
            $snapshot.Status = if ($Result.ExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
        } elseif ($process) {
            $snapshot.Status = 'Unconfirmed'
        } else {
            $snapshot.Status = 'Failed'
        }
        $Result.Outcome = $snapshot.Status
        Write-Evox2BuildRecord "$Stem.result.json" $Result
        Write-Evox2BuildRecord "$Stem.state.json" $snapshot
    }
}

Export-ModuleMember -Function Write-Evox2BuildRecord, Get-Evox2ProcessIdentity, Test-Evox2ProcessIdentity, Get-Evox2NinjaProgress, Read-Evox2BuildState, Invoke-Evox2TrackedBuildProcess
