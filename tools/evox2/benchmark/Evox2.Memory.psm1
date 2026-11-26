#requires -Version 5.1

if (-not ('Evox2ResourceMemory' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Evox2ResourceMemory {
    [StructLayout(LayoutKind.Sequential)]
    public struct PerformanceInfo {
        public uint Size;
        public UIntPtr CommitTotal, CommitLimit, CommitPeak;
        public UIntPtr PhysicalTotal, PhysicalAvailable, SystemCache;
        public UIntPtr KernelTotal, KernelPaged, KernelNonpaged, PageSize;
        public uint HandleCount, ProcessCount, ThreadCount;
    }

    [DllImport("psapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetPerformanceInfo(ref PerformanceInfo info, uint size);
}
"@
}

function Get-Evox2SystemMemory {
    $info = New-Object 'Evox2ResourceMemory+PerformanceInfo'
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    if (![Evox2ResourceMemory]::GetPerformanceInfo([ref]$info, $info.Size)) {
        throw "GetPerformanceInfo Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }
    $pageSize = $info.PageSize.ToUInt64()
    $total = $info.PhysicalTotal.ToUInt64() * $pageSize
    $available = $info.PhysicalAvailable.ToUInt64() * $pageSize
    $commit = $info.CommitTotal.ToUInt64() * $pageSize
    $limit = $info.CommitLimit.ToUInt64() * $pageSize
    [pscustomobject]@{
        Total = $total
        Available = $available
        Used = $total - $available
        Commit = $commit
        CommitLimit = $limit
        CommitPercent = $(if ($limit -gt 0) { 100.0 * $commit / $limit } else { $null })
        CommitPeak = $info.CommitPeak.ToUInt64() * $pageSize
        Cache = $info.SystemCache.ToUInt64() * $pageSize
    }
}

function Get-Evox2ProcessMemory {
    param([Diagnostics.Process]$Process)
    $values = @{}
    $issue = $null
    try {
        $Process.Refresh()
        foreach ($property in 'WorkingSet64', 'PrivateMemorySize64', 'VirtualMemorySize64') {
            try {
                $value = $Process.$property
                if ($null -ne $value -and $value -ge 0) { $values[$property] = $value }
            } catch {
                if (!$issue) { $issue = $_.Exception.Message }
            }
        }
    } catch { $issue = $_.Exception.Message }
    [pscustomobject]@{ Values = $values; Error = $issue }
}

Export-ModuleMember -Function 'Get-Evox2SystemMemory', 'Get-Evox2ProcessMemory'
