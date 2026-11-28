#!/usr/bin/env python3
"""HIP-2E-4 serial GPU validation supervisor (ThinkPad controller side).

Executes pre-suite audit and runs each of the 14 pinned HIP-2E test cases
one by one over independent SSH invocations with strict 60s execution deadline,
PID/StartTime tracking, inter-case resource/event recovery checks, incremental
summary persistence, and strict log collection verification.
"""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

SSH_HOST = "evox2-runner@192.168.240.38"
SSH_KEY = "/home/antigravity/.ssh/id_ed25519_evox2"
SSH_OPTIONS: List[str] = [
    "-F", "/dev/null",
    "-o", "BatchMode=yes",
    "-o", "ControlMaster=no",
    "-o", "ControlPath=none",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "ForwardAgent=no",
    "-i", SSH_KEY,
]

PLACEMENT_CASE = "S-HC-PIN-REJECT"

CASES: List[str] = [
    "1", "1-NC", "2", "2-C",
    "5", "6",
    "7", "8", "9", "9-Z",
    "S-HC-CPU", "S-HC-PIN-COPY", "S-ID-PIN-COPY", PLACEMENT_CASE,
]
SCHED_CASES = {"S-HC-CPU", "S-HC-PIN-COPY", "S-ID-PIN-COPY"}

EXPECTED_REF_SHA256: Dict[str, str] = {
    "1": "d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a",
    "1-NC": "d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a",
    "2": "637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f",
    "2-C": "637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f",
    "5": "0978449fc6f46e694dcffa7841034c6a4d85da13766c20b55e37446f32597cbd",
    "6": "f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1",
    "7": "d3ab1c4678f9604738fc286adbe9ee181a9e0bd56f6a55e4fa8616f28d933c1e",
    "8": "3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb",
    "9": "9203115b655f0305deaad40823cf2920d8e33e3c2d6ef9ad9d45001ff9146414",
    "9-Z": "738c079dff6c9b77a0891ac42db1cabcab933a672b14aed8ecfcf94c0e77bb40",
    "S-HC-CPU": "f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1",
    "S-HC-PIN-COPY": "f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1",
    "S-ID-PIN-COPY": "3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb",
}

SCHED_EXPECTED: Dict[str, Dict[str, Any]] = {
    "S-HC-CPU": {
        "backend": "ROCm0", "weight": "ROCm0", "activation": "CPU->ROCm0",
        "dst": "ROCm0", "ids": "-", "split_copy": 1, "stage_h2d": 0,
        "id_copy": 0, "observed_span": 0, "observed_pitch": 0,
        "stage_d2h": 0, "host_reads": 0, "span": 0, "pitch": 0, "ops": 1, "sgemms": 1,
    },
    "S-HC-PIN-COPY": {
        "backend": "ROCm0", "weight": "ROCm0", "activation": "ROCm_Host->ROCm0",
        "dst": "ROCm0", "ids": "-", "split_copy": 1, "stage_h2d": 0,
        "id_copy": 0, "observed_span": 0, "observed_pitch": 0,
        "stage_d2h": 0, "host_reads": 0, "span": 0, "pitch": 0, "ops": 1, "sgemms": 1,
    },
    "S-ID-PIN-COPY": {
        "backend": "ROCm0", "weight": "ROCm0", "activation": "ROCm0->ROCm0",
        "dst": "ROCm0", "ids": "ROCm0", "split_copy": 0, "stage_h2d": 0,
        "id_copy": 1, "observed_span": 4104, "observed_pitch": 2048,
        "stage_d2h": 0, "host_reads": 0, "span": 0, "pitch": 0, "ops": 1, "sgemms": 2,
    },
}

SCHED_EXPECTED[PLACEMENT_CASE] = {
    "backend": "CPU", "weight": "ROCm0", "activation": "ROCm_Host", "dst": "ROCm_Host",
    "hip_buft": 0, "hip_op": 0, "cpu_buft": 1, "cpu_op": 1, "alloc": 1,
    "split_copy": 0, "id_copy": 0, "observed_span": 0, "observed_pitch": 0,
    "compute": 0, "ops": 0, "sgemms": 0, "stage_h2d": 0, "stage_d2h": 0,
    "host_reads": 0, "span": 0, "pitch": 0,
}

PINNED = {
    "main_sha": "d0bf0911c135594e19038488613f9211a1dd5a3e",
    "branch": "codex/b12651-rocmfp4-hip2e4-20261129",
    "source_commit": "",
    "worktree": r"C:\llama-build\automation\w64",
    "binary_dir": "",
    "manifest_sha256": "",
    "hip_dll_sha256": "",
    "ggml_dll_sha256": "",
    "base_dll_sha256": "",
    "cpu_dll_sha256": "",
    "cli_sha256": "",
    "libomp_sha256": "4a20c1e5c115c29771a12324513eb109badac72180f79481527ad79d996ffb33",
    "old_catalog_sha256": "0f5c1cf6b166d57f6c8ed16bc85c3ef6d8a88f10837c09d55655dfd577c6feea",
    "new_catalog_sha256": "5d5a2e08ae7eed50a6d6cb52013a4ce0e92c6c51cfa94088690039cb990258a6",
    "remote_log_root": r"C:\llama-build\_logs\codex",
}

EXPECTED_HASH_MAP = {
    "manifest": PINNED["manifest_sha256"],
    "hip_dll": PINNED["hip_dll_sha256"],
    "ggml_dll": PINNED["ggml_dll_sha256"],
    "base_dll": PINNED["base_dll_sha256"],
    "cpu_dll": PINNED["cpu_dll_sha256"],
    "cli_exe": PINNED["cli_sha256"],
}

MIN_PHYS_AVAIL_GIB = 16.0
MAX_DELTA_GIB = 4.0
CASE_TIMEOUT_SEC = 60.0
SSH_TIMEOUT_SEC = 120
COMPETING_PROC_REGEX = r"^(llama|llama-cli|llama-server|llama-bench|test-backend-ops|cmake|ninja|clang|clang\+\+|cl|msbuild|python)$"

_PS_STDIN_BOOTSTRAP = base64.b64encode(
    "$ErrorActionPreference='Stop';$b=[Console]::In.ReadLine();$c=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b));& ([scriptblock]::Create($c))".encode("utf-16le")
).decode("ascii")


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


SshRunner = Callable[[str, str, int], CommandResult]
ScpRunner = Callable[[str, Path, int], CommandResult]


def validate_case_id(case_id: str) -> str:
    if case_id not in CASES:
        raise ValueError(f"Unsupported or invalid case ID: {case_id!r}")
    return case_id


def safe_case_name(case_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", case_id)


def expected_log_stem(run_id: str, case_id: str) -> str:
    return f"{PINNED['remote_log_root']}\\{run_id}-{safe_case_name(case_id)}"


def build_remote_ssh_command() -> str:
    return f"powershell -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -EncodedCommand {_PS_STDIN_BOOTSTRAP}"


def default_ssh_runner(ps_script: str, remote_cmd: str, timeout_sec: int = SSH_TIMEOUT_SEC) -> CommandResult:
    cmd = ["ssh", *SSH_OPTIONS, SSH_HOST, remote_cmd]
    payload = base64.b64encode(ps_script.encode("utf-8")) + b"\n"
    proc = subprocess.run(cmd, input=payload, capture_output=True, timeout=timeout_sec)
    return CommandResult(
        proc.returncode,
        proc.stdout.decode("utf-8", errors="replace"),
        proc.stderr.decode("utf-8", errors="replace"),
    )


def default_scp_runner(remote_glob: str, local_dir: Path, timeout_sec: int = SSH_TIMEOUT_SEC) -> CommandResult:
    local_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["scp", *SSH_OPTIONS, f"{SSH_HOST}:{remote_glob}", str(local_dir)]
    proc = subprocess.run(cmd, capture_output=True, timeout=timeout_sec)
    return CommandResult(
        proc.returncode,
        proc.stdout.decode("utf-8", errors="replace"),
        proc.stderr.decode("utf-8", errors="replace"),
    )


def _require_finite_number(val: Any, name: str, non_negative: bool = False) -> float:
    if isinstance(val, bool) or not isinstance(val, (int, float)):
        raise ValueError(f"{name} must be a finite number, got {val!r}")
    f = float(val)
    if not math.isfinite(f):
        raise ValueError(f"{name} is not finite: {val!r}")
    if non_negative and f < 0.0:
        raise ValueError(f"{name} must be >= 0, got {f}")
    return f


def _require_int(val: Any, name: str, min_val: Optional[int] = None) -> int:
    if isinstance(val, bool) or not isinstance(val, int):
        raise ValueError(f"{name} must be an integer, got {val!r}")
    if min_val is not None and val < min_val:
        raise ValueError(f"{name} must be >= {min_val}, got {val}")
    return val


def _require_nonempty_str(val: Any, name: str) -> str:
    if not isinstance(val, str) or not val.strip():
        raise ValueError(f"{name} must be a non-empty string, got {val!r}")
    return val


def _require_bool(val: Any, name: str) -> bool:
    if not isinstance(val, bool):
        raise ValueError(f"{name} must be a bool, got {val!r}")
    return val


def build_pre_audit_ps() -> str:
    ref_checks = "\n".join(
        f"if ($refText -notmatch '(?m)^PASS {re.escape(cid)} reference SHA256 {sha}\\r?$') {{ throw 'Reference SHA256 mismatch for {cid}' }}"
        for cid, sha in EXPECTED_REF_SHA256.items()
        if cid not in SCHED_CASES
    )
    sched_ref_checks = "\n".join(
        f"$sOut = (& $py -I -B tools/evox2/hip2a/fixtures.py reference --case {cid}) -join \"`n\"; "
        f"if ($LASTEXITCODE -ne 0 -or $sOut -notmatch '(?m)^PASS {re.escape(cid)} reference SHA256 {EXPECTED_REF_SHA256[cid]}\\r?$') {{ throw 'Scheduler reference check failed for {cid}' }}"
        for cid in sorted(SCHED_CASES)
    )
    return rf"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$w64 = '{PINNED["worktree"]}'
$bin = '{PINNED["binary_dir"]}'
$build = Split-Path -Parent (Split-Path -Parent $bin)
Set-Location -LiteralPath $w64

$head = (& git.exe rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {{ throw 'git rev-parse HEAD failed' }}
$st = @(& git.exe status --porcelain)
if ($LASTEXITCODE -ne 0) {{ throw 'git status failed' }}
$remoteMain = ((& git.exe ls-remote origin refs/heads/main) -split '\s+')[0]
if ($LASTEXITCODE -ne 0) {{ throw 'git ls-remote main failed' }}
$remoteBranch = ((& git.exe ls-remote origin refs/heads/{PINNED["branch"]}) -split '\s+')[0]
if ($LASTEXITCODE -ne 0) {{ throw 'git ls-remote branch failed' }}
if ($head -cne '{PINNED["source_commit"]}' -or $remoteBranch -cne '{PINNED["source_commit"]}' -or $remoteMain -cne '{PINNED["main_sha"]}' -or $st.Count -ne 0) {{
    throw "Git/SHA or clean check failed: head=$head branch=$remoteBranch main=$remoteMain dirty=$($st.Count)"
}}

$hashes = [ordered]@{{
    manifest = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'evox2-build.json')).Hash
    hip_dll  = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'ggml-hip.dll')).Hash
    ggml_dll = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'ggml.dll')).Hash
    base_dll = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'ggml-base.dll')).Hash
    cpu_dll  = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'ggml-cpu.dll')).Hash
    cli_exe  = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'llama-cli.exe')).Hash
}}
if ($hashes.manifest -ne '{PINNED["manifest_sha256"]}' -or
    $hashes.hip_dll -ne '{PINNED["hip_dll_sha256"]}' -or
    $hashes.ggml_dll -ne '{PINNED["ggml_dll_sha256"]}' -or
    $hashes.base_dll -ne '{PINNED["base_dll_sha256"]}' -or
    $hashes.cpu_dll -ne '{PINNED["cpu_dll_sha256"]}' -or
    $hashes.cli_exe -ne '{PINNED["cli_sha256"]}') {{
    throw "Artifact SHA-256 mismatch: $($hashes | ConvertTo-Json -Compress)"
}}

$cache = Get-Content -LiteralPath (Join-Path $build 'CMakeCache.txt')
if ($cache -notcontains 'GGML_HIP_ROCMFP4_TEST:BOOL=ON' -or $cache -notcontains 'GGML_BACKEND_DL:BOOL=ON') {{
    throw 'Missing required CMakeCache flags'
}}

Import-Module .\tools\evox2\lib\Evox2.Common.psm1
$manifest = Get-Content -LiteralPath (Join-Path $bin 'evox2-build.json') -Raw | ConvertFrom-Json
$rt = Test-Evox2RuntimeArtifacts -Executable (Join-Path $bin 'llama-cli.exe') -Manifest $manifest
if ($rt.Status -ne 'Verified' -or $rt.Scope -ne 'RuntimeDependenciesV1') {{
    throw "Runtime verification failed: $($rt.Issues -join ', ')"
}}

$vs = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\2022\BuildTools'
$vsDev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$vars = cmd.exe /d /c "`"$vsDev`" -arch=x64 -host_arch=x64 -no_logo >nul && set"
if ($LASTEXITCODE -ne 0) {{ throw 'VsDevCmd failed' }}
foreach ($line in $vars) {{
    if ($line -match '^([^=]+)=(.*)$') {{ [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }}
}}
$hipExp = & dumpbin.exe /nologo /exports (Join-Path $bin 'ggml-hip.dll')
if ($LASTEXITCODE -ne 0) {{ throw 'dumpbin ggml-hip.dll failed' }}
if (@($hipExp | Select-String '\bevox2_hip2a_case\b').Count -ne 1 -or @($hipExp | Select-String '\bevox2_hip2e_sched_case\b').Count -ne 1) {{
    throw 'Unexpected ggml-hip.dll export count'
}}
$ggmlExp = & dumpbin.exe /nologo /exports (Join-Path $bin 'ggml.dll')
if ($LASTEXITCODE -ne 0 -or @($ggmlExp | Select-String '\bggml_backend_load\b').Count -lt 1) {{ throw 'Missing ggml_backend_load' }}
$cpuExp = & dumpbin.exe /nologo /exports (Join-Path $bin 'ggml-cpu.dll')
if ($LASTEXITCODE -ne 0 -or @($cpuExp | Select-String '\bggml_backend_init\b').Count -lt 1) {{ throw 'Missing ggml_backend_init' }}

$libomp = Join-Path $env:SystemRoot 'System32\libomp140.x86_64.dll'
if (!(Test-Path -LiteralPath $libomp -PathType Leaf)) {{ throw 'Missing System32 libomp140.x86_64.dll' }}
$libompHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $libomp).Hash.ToLowerInvariant()
$libompManifest = $manifest.RuntimeDependencies.External | Where-Object {{ $_.Name -ieq 'libomp140.x86_64.dll' }} | Select-Object -First 1
if (-not $libompManifest -or $libompManifest.Sha256.ToLowerInvariant() -ne $libompHash -or $libompHash -ne '{PINNED["libomp_sha256"]}') {{
    throw "libomp140.x86_64.dll hash mismatch: $libompHash"
}}

$pmode = Get-Evox2PModeMetadata
if (!$pmode.ProbeSucceeded -or $pmode.Mode -ne 'Performance') {{
    throw "P-MODE check failed: ProbeSucceeded=$($pmode.ProbeSucceeded) Mode=$($pmode.Mode) Error=$($pmode.Error)"
}}
$bootUtc = (Get-WinEvent -FilterHashtable @{{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12}} -MaxEvents 1).TimeCreated.ToUniversalTime().ToString('o')
$sysId = [int64](Get-WinEvent -LogName System -MaxEvents 1).RecordId
$appId = [int64](Get-WinEvent -LogName Application -MaxEvents 1).RecordId

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public struct PI2E {{
    public uint cb;
    public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable, SystemCache, KernelTotal, KernelPaged, KernelNonpaged, PageSize;
    public uint HandleCount, ProcessCount, ThreadCount;
}}
public static class Mem2E {{
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool GetPerformanceInfo(out PI2E p, uint s);
}}
'@
$pi = New-Object PI2E
if (-not [Mem2E]::GetPerformanceInfo([ref]$pi, [Runtime.InteropServices.Marshal]::SizeOf($pi))) {{
    throw 'GetPerformanceInfo failed'
}}
$ps = [double]$pi.PageSize.ToUInt64()
$physAvail = [math]::Round($pi.PhysicalAvailable.ToUInt64()*$ps/1GB, 3)
$commitGiB = [math]::Round($pi.CommitTotal.ToUInt64()*$ps/1GB, 3)
$commitLim = [math]::Round($pi.CommitLimit.ToUInt64()*$ps/1GB, 3)
if ($physAvail -lt {MIN_PHYS_AVAIL_GIB}) {{ throw "PhysAvailGiB < 16: $physAvail" }}
if ($commitGiB -gt $commitLim) {{ throw "CommitGiB ($commitGiB) > CommitLimitGiB ($commitLim)" }}

$dedSamples = @((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples)
$shrSamples = @((Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop).CounterSamples)
if ($dedSamples.Count -eq 0 -or $shrSamples.Count -eq 0) {{ throw 'WDDM CounterSamples empty' }}
foreach ($s in ($dedSamples + $shrSamples)) {{
    if ($s.Status -ne 0 -or [double]::IsNaN($s.CookedValue) -or [double]::IsInfinity($s.CookedValue) -or $s.CookedValue -lt 0) {{
        throw "Invalid WDDM counter sample: Status=$($s.Status) Value=$($s.CookedValue)"
    }}
}}
$ded = ($dedSamples | Measure-Object -Property CookedValue -Sum).Sum / 1GB
$shr = ($shrSamples | Measure-Object -Property CookedValue -Sum).Sum / 1GB

$competing = @(Get-Process | Where-Object {{ $_.ProcessName -match '{COMPETING_PROC_REGEX}' }})
if ($competing.Count -gt 0) {{ throw "Competing processes present: $($competing.ProcessName -join ',')" }}

$py = 'C:\Python314\python.exe'
$caseRows = @(Get-Content tools/evox2/hip2a/cases.inc | Where-Object {{ $_.StartsWith('CASE(') }})
$catalogBytes = [Text.Encoding]::UTF8.GetBytes(($caseRows -join "`n"))
$catalogHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($catalogBytes)).Replace('-','')
if ($catalogHash -ne '{PINNED["new_catalog_sha256"]}') {{ throw 'Catalog SHA256 mismatch' }}
$enumOut = @(& $py -I -B tools/evox2/hip2a/fixtures.py enumerate)
if ($LASTEXITCODE -ne 0 -or $enumOut.Count -ne 14) {{ throw 'Python enumerate failed' }}
$refText = (& $py -I -B tools/evox2/hip2a/fixtures.py reference) -join "`n"
if ($LASTEXITCODE -ne 0) {{ throw 'Python reference (10) failed' }}
{ref_checks}
{sched_ref_checks}

$audit = [ordered]@{{
    Head = $head; RemoteMain = $remoteMain; RemoteBranch = $remoteBranch; Clean = $true
    Hashes = $hashes; LibompSystem32 = $libompHash
    PMode = $pmode.Mode; BootUtc = $bootUtc; SysId = $sysId; AppId = $appId
    PhysAvailGiB = $physAvail; CommitGiB = $commitGiB; CommitLimitGiB = $commitLim
    DedicatedGiB = [math]::Round($ded, 3); SharedGiB = [math]::Round($shr, 3)
}}
Write-Output ("AUDIT_JSON=" + ($audit | ConvertTo-Json -Compress))
"""


def build_case_ps(
    case_id: str,
    run_id: str,
    prev_sys_id: int,
    prev_app_id: int,
    suite_baseline: Dict[str, Any],
) -> str:
    validate_case_id(case_id)
    if not re.fullmatch(r"hip2e4-[A-Za-z0-9_-]+", run_id):
        raise ValueError(f"Invalid run_id: {run_id!r}")
    stem = expected_log_stem(run_id, case_id)
    base_commit = float(suite_baseline["CommitGiB"])
    base_ded = float(suite_baseline["DedicatedGiB"])
    base_boot = str(suite_baseline["BootUtc"])

    return rf"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$caseId = '{case_id}'
$w64 = '{PINNED["worktree"]}'
$dll = '{PINNED["binary_dir"]}\ggml-hip.dll'
$py = 'C:\Python314\python.exe'
$stem = '{stem}'
$prevSys = [int64]{int(prev_sys_id)}
$prevApp = [int64]{int(prev_app_id)}
$suiteCommit = [double]{base_commit}
$suiteDed = [double]{base_ded}
$suiteBoot = '{base_boot}'
Set-Location -LiteralPath $w64
Import-Module .\tools\evox2\lib\Evox2.Common.psm1

# Prevent overwriting existing remote logs for this run_id/case
$existingLogs = @(Get-ChildItem -LiteralPath (Split-Path -Parent $stem) -Filter ([IO.Path]::GetFileName($stem) + '.*') -ErrorAction SilentlyContinue)
if ($existingLogs.Count -gt 0) {{
    throw "Remote log files already exist for $stem"
}}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public struct PI2E {{
    public uint cb;
    public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable, SystemCache, KernelTotal, KernelPaged, KernelNonpaged, PageSize;
    public uint HandleCount, ProcessCount, ThreadCount;
}}
public static class Mem2E {{
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool GetPerformanceInfo(out PI2E p, uint s);
}}
'@

function Get-MemSnapshot {{
    $pi = New-Object PI2E
    if (-not [Mem2E]::GetPerformanceInfo([ref]$pi, [Runtime.InteropServices.Marshal]::SizeOf($pi))) {{
        throw 'GetPerformanceInfo failed'
    }}
    $ps = [double]$pi.PageSize.ToUInt64()
    [ordered]@{{
        PhysAvailGiB = [math]::Round($pi.PhysicalAvailable.ToUInt64()*$ps/1GB, 3)
        CommitGiB    = [math]::Round($pi.CommitTotal.ToUInt64()*$ps/1GB, 3)
        CommitLimGiB = [math]::Round($pi.CommitLimit.ToUInt64()*$ps/1GB, 3)
    }}
}}

function Get-WddmSnapshot {{
    $dedSamples = @((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples)
    $shrSamples = @((Get-Counter '\GPU Adapter Memory(*)\Shared Usage' -ErrorAction Stop).CounterSamples)
    if ($dedSamples.Count -eq 0 -or $shrSamples.Count -eq 0) {{ throw 'WDDM CounterSamples empty' }}
    foreach ($s in ($dedSamples + $shrSamples)) {{
        if ($s.Status -ne 0 -or [double]::IsNaN($s.CookedValue) -or [double]::IsInfinity($s.CookedValue) -or $s.CookedValue -lt 0) {{
            throw "Invalid WDDM counter sample: Status=$($s.Status) Value=$($s.CookedValue)"
        }}
    }}
    $ded = ($dedSamples | Measure-Object -Property CookedValue -Sum).Sum / 1GB
    $shr = ($shrSamples | Measure-Object -Property CookedValue -Sum).Sum / 1GB
    [ordered]@{{ DedicatedGiB = [math]::Round($ded, 3); SharedGiB = [math]::Round($shr, 3) }}
}}

function Get-NewCriticalEvents([int64]$sysAfter, [int64]$appAfter) {{
    $sysErr = @()
    try {{
        $sysErr = @(Get-WinEvent -FilterHashtable @{{ LogName='System'; Level=1,2,3 }} -ErrorAction Stop | Where-Object {{ $_.RecordId -gt $sysAfter -and $_.ProviderName -match 'Display|amd|WHEA|Kernel-Power|BugCheck|DxgKrnl' }} | Select-Object RecordId,ProviderName,Id,Message)
    }} catch [Exception] {{
        if ($_.Exception.Message -notmatch 'NoMatchingEventsFound|指定された選択基準に一致するイベント') {{ throw }}
    }}
    $appErr = @()
    try {{
        $appErr = @(Get-WinEvent -FilterHashtable @{{ LogName='Application'; Level=1,2 }} -ErrorAction Stop | Where-Object {{ $_.RecordId -gt $appAfter -and $_.ProviderName -match 'Application Error|Windows Error Reporting|amd|HIP' }} | Select-Object RecordId,ProviderName,Id,Message)
    }} catch [Exception] {{
        if ($_.Exception.Message -notmatch 'NoMatchingEventsFound|指定された選択基準に一致するイベント') {{ throw }}
    }}
    return @{{ Sys = $sysErr; App = $appErr }}
}}

$preMem = Get-MemSnapshot
$preWddm = Get-WddmSnapshot
$prePModeObj = Get-Evox2PModeMetadata
if (!$prePModeObj.ProbeSucceeded -or $prePModeObj.Mode -ne 'Performance') {{
    throw "Pre-case P-MODE invalid: $($prePModeObj.Mode) $($prePModeObj.Error)"
}}
$preSys = [int64](Get-WinEvent -LogName System -MaxEvents 1).RecordId
$preApp = [int64](Get-WinEvent -LogName Application -MaxEvents 1).RecordId
if ($preSys -lt $prevSys -or $preApp -lt $prevApp) {{
    throw "Event log cursor regressed before case: Sys=$preSys<$prevSys App=$preApp<$prevApp"
}}
$preBoot = (Get-WinEvent -FilterHashtable @{{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12}} -MaxEvents 1).TimeCreated.ToUniversalTime().ToString('o')
if ($preBoot -cne $suiteBoot) {{ throw "Pre-case OS boot time changed: $preBoot != $suiteBoot" }}
if ($preMem.PhysAvailGiB -lt {MIN_PHYS_AVAIL_GIB}) {{ throw "Pre-case PhysAvailGiB < 16: $($preMem.PhysAvailGiB)" }}
if ($preMem.CommitGiB -gt $preMem.CommitLimGiB) {{ throw "Pre-case Commit exceeds Limit" }}
if (($preMem.CommitGiB - $suiteCommit) -gt {MAX_DELTA_GIB}) {{ throw "Pre-case suite Commit delta exceeded 4 GiB" }}
if (($preWddm.DedicatedGiB - $suiteDed) -gt {MAX_DELTA_GIB}) {{ throw "Pre-case suite Dedicated delta exceeded 4 GiB" }}

$gapEvents = Get-NewCriticalEvents $prevSys $prevApp
if ($gapEvents.Sys.Count -gt 0 -or $gapEvents.App.Count -gt 0) {{
    throw "Inter-case critical events detected: Sys=$($gapEvents.Sys.Count) App=$($gapEvents.App.Count)"
}}
$competing = @(Get-Process | Where-Object {{ $_.ProcessName -match '{COMPETING_PROC_REGEX}' }})
if ($competing.Count -gt 0) {{ throw "Pre-case competing processes present: $($competing.ProcessName -join ',')" }}

$legacy = '(?i)[\\/]ROCm[\\/]7\.2(?:[\\/]|$)'
$env:Path = ($env:Path -split ';' | Where-Object {{ $_.Trim('"') -notmatch $legacy }}) -join ';'
Get-ChildItem Env: | Where-Object {{ $_.Name -match '^(HIP|ROCM|HSA|LLVM|CMAKE)' -and $_.Value -match $legacy }} | ForEach-Object {{ Remove-Item -LiteralPath "Env:$($_.Name)" }}
if (($env:Path -split ';' | Where-Object {{ $_.Trim('"') -match $legacy }}).Count -gt 0) {{ throw 'Failed to strip ROCm 7.2 from PATH' }}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $py
$psi.Arguments = "-I -B tools/evox2/hip2a/fixtures.py gpu --case $caseId --dll `"$dll`""
$psi.WorkingDirectory = $w64
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$proc = $null
$childPid = $null
$procStartUtc = $null
$samples = @()
$sampleErrors = @()
$timedOut = $false
$unconfirmed = $false
$monitorError = $null
$stdout = ''
$stderr = ''
$exitCode = -1
$startUtc = [datetime]::UtcNow.ToString('o')
$execSw = $null

try {{
    $proc = [System.Diagnostics.Process]::Start($psi)
    $execSw = [Diagnostics.Stopwatch]::StartNew()
    $childPid = $proc.Id
    $procStartUtc = $proc.StartTime.ToUniversalTime().ToString('o')
    $initState = [ordered]@{{
        CaseId = $caseId; Status = 'Running'; Pid = $childPid; ProcessStartUtc = $procStartUtc
        StartedUtc = $startUtc; Command = "$py $($psi.Arguments)"; LogStem = $stem
    }}
    ($initState | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath "$stem.state.json" -Encoding UTF8

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    while (-not $proc.WaitForExit(2000)) {{
        try {{
            $m = Get-MemSnapshot
            $ws = $null; $pm = $null
            if (-not $proc.HasExited) {{
                $proc.Refresh()
                $ws = [math]::Round($proc.WorkingSet64/1MB,1)
                $pm = [math]::Round($proc.PrivateMemorySize64/1MB,1)
            }}
            $samples += [ordered]@{{ ElapsedSec = [math]::Round($execSw.Elapsed.TotalSeconds,2); PhysAvailGiB = $m.PhysAvailGiB; CommitGiB = $m.CommitGiB; ProcWsMiB = $ws; ProcPrivMiB = $pm }}
        }} catch {{
            $sampleErrors += $_.Exception.Message
            throw "During-execution monitoring failed: $($_.Exception.Message)"
        }}
        if ($execSw.Elapsed.TotalSeconds -ge {CASE_TIMEOUT_SEC}) {{
            $timedOut = $true
            try {{
                if (-not $proc.HasExited) {{
                    $proc.Kill()
                    if (-not $proc.WaitForExit(5000)) {{ $unconfirmed = $true }}
                }}
            }} catch {{
                $unconfirmed = $true
            }}
            break
        }}
    }}
    $execSw.Stop()
    if (-not $timedOut -and $execSw.Elapsed.TotalSeconds -ge {CASE_TIMEOUT_SEC}) {{
        $timedOut = $true
    }}
    if (-not $outTask.Wait(5000)) {{ $unconfirmed = $true }} else {{ $stdout = $outTask.GetAwaiter().GetResult() }}
    if (-not $errTask.Wait(5000)) {{ $unconfirmed = $true }} else {{ $stderr = $errTask.GetAwaiter().GetResult() }}
    if (-not $timedOut -and $proc.HasExited) {{ $exitCode = $proc.ExitCode }}
}} catch {{
    $monitorError = $_.Exception.Message
    $unconfirmed = $true
    if ($proc -ne $null) {{
        try {{
            if (-not $proc.HasExited) {{
                $proc.Kill()
                if (-not $proc.WaitForExit(5000)) {{ $unconfirmed = $true }}
            }}
        }} catch {{
            $unconfirmed = $true
        }}
    }}
}} finally {{
    if ($execSw -ne $null -and $execSw.IsRunning) {{ $execSw.Stop() }}
    if ($proc -ne $null) {{
        try {{
            if (-not $proc.HasExited) {{
                $proc.Kill()
                if (-not $proc.WaitForExit(5000)) {{ $unconfirmed = $true }}
            }}
        }} catch {{
            $unconfirmed = $true
        }}
        $proc.Dispose()
    }}
}}
$endUtc = [datetime]::UtcNow.ToString('o')
$execSec = if ($execSw -ne $null) {{ [math]::Round($execSw.Elapsed.TotalSeconds, 3) }} else {{ 0.0 }}

[IO.File]::WriteAllText("$stem.stdout.log", $stdout, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText("$stem.stderr.log", $stderr, [Text.UTF8Encoding]::new($false))

$postMem = Get-MemSnapshot
$postWddm = Get-WddmSnapshot
$postPModeObj = Get-Evox2PModeMetadata
if (!$postPModeObj.ProbeSucceeded) {{ throw "Post-case P-MODE probe failed: $($postPModeObj.Error)" }}
$postSys = [int64](Get-WinEvent -LogName System -MaxEvents 1).RecordId
$postApp = [int64](Get-WinEvent -LogName Application -MaxEvents 1).RecordId
if ($postSys -lt $preSys -or $postApp -lt $preApp) {{
    throw "Event log cursor regressed during case: Sys=$postSys<$preSys App=$postApp<$preApp"
}}
$postBoot = (Get-WinEvent -FilterHashtable @{{LogName='System'; ProviderName='Microsoft-Windows-Kernel-General'; Id=12}} -MaxEvents 1).TimeCreated.ToUniversalTime().ToString('o')

$postEvents = Get-NewCriticalEvents $preSys $preApp
$residual = @()
if ($childPid) {{
    $residual = @(Get-Process -Id $childPid -ErrorAction SilentlyContinue | Where-Object {{ $_.StartTime.ToUniversalTime().ToString('o') -eq $procStartUtc }})
}}
if ($residual.Count -gt 0) {{ $unconfirmed = $true }}

$commitDelta = [math]::Round($postMem.CommitGiB - $preMem.CommitGiB, 3)
$dedDelta = [math]::Round($postWddm.DedicatedGiB - $preWddm.DedicatedGiB, 3)

$finalState = [ordered]@{{
    CaseId = $caseId
    Status = if ($unconfirmed) {{ 'Unconfirmed' }} elseif (-not $timedOut -and $exitCode -eq 0) {{ 'Completed' }} else {{ 'Failed' }}
    Pid = $childPid; ProcessStartUtc = $procStartUtc; StartedUtc = $startUtc; EndedUtc = $endUtc
    ElapsedSeconds = $execSec; TimedOut = $timedOut; Unconfirmed = $unconfirmed; ExitCode = $exitCode
    MonitorError = $monitorError; LogStem = $stem
}}
($finalState | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath "$stem.state.json" -Encoding UTF8

$peakNote = if ($sampleErrors.Count -gt 0) {{ 'sample_error' }} elseif ($samples.Count -eq 0) {{ 'unmeasured (duration < 2s)' }} else {{ 'measured at 2s intervals' }}

$report = [ordered]@{{
    CaseId = $caseId; Pid = $childPid; ProcessStartUtc = $procStartUtc
    StartUtc = $startUtc; EndUtc = $endUtc; ElapsedSeconds = $execSec
    TimedOut = $timedOut; Unconfirmed = $unconfirmed; ExitCode = $exitCode; MonitorError = $monitorError
    Command = "$py $($psi.Arguments)"
    Pre = [ordered]@{{ Mem = $preMem; Wddm = $preWddm; PMode = $prePModeObj.Mode; BootUtc = $preBoot; SysId = $preSys; AppId = $preApp }}
    DuringSamples = $samples; DuringSampleErrors = $sampleErrors; DuringPeakNote = $peakNote
    Post = [ordered]@{{ Mem = $postMem; Wddm = $postWddm; PMode = $postPModeObj.Mode; BootUtc = $postBoot; SysId = $postSys; AppId = $postApp; CommitDeltaGiB = $commitDelta; DedicatedDeltaGiB = $dedDelta; ResidualCount = $residual.Count; SysErrors = $postEvents.Sys; AppErrors = $postEvents.App }}
    Stdout = $stdout; Stderr = $stderr; LogStem = $stem
}}
($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath "$stem.report.json" -Encoding UTF8
Write-Output ("REPORT_JSON=" + ($report | ConvertTo-Json -Depth 6 -Compress))
"""


def parse_json_marker(text: str, marker: str) -> Dict[str, Any]:
    for line in text.splitlines():
        if line.startswith(marker):
            return json.loads(line[len(marker):])
    raise ValueError(f"Missing {marker} in remote output")


def validate_pre_audit_json(audit: Dict[str, Any]) -> Dict[str, Any]:
    required = {
        "Head", "RemoteMain", "RemoteBranch", "Clean", "Hashes", "LibompSystem32",
        "PMode", "BootUtc", "SysId", "AppId", "PhysAvailGiB", "CommitGiB",
        "CommitLimitGiB", "DedicatedGiB", "SharedGiB",
    }
    missing = sorted(required - set(audit.keys()))
    if missing:
        raise ValueError(f"Pre-audit missing required fields: {missing}")

    if audit["Head"] != PINNED["source_commit"] or audit["RemoteBranch"] != PINNED["source_commit"]:
        raise ValueError(f"Pre-audit source commit mismatch: {audit['Head']} / {audit['RemoteBranch']}")
    if audit["RemoteMain"] != PINNED["main_sha"]:
        raise ValueError(f"Pre-audit main SHA mismatch: {audit['RemoteMain']}")
    if _require_bool(audit["Clean"], "Clean") is not True:
        raise ValueError("Pre-audit repository is not clean")
    if audit["PMode"] != "Performance":
        raise ValueError(f"Pre-audit PMode != Performance: {audit['PMode']!r}")
    _require_nonempty_str(audit["BootUtc"], "BootUtc")

    libomp = _require_nonempty_str(audit["LibompSystem32"], "LibompSystem32").lower()
    if libomp != PINNED["libomp_sha256"]:
        raise ValueError(f"Pre-audit LibompSystem32 hash mismatch: {libomp}")

    hashes = audit["Hashes"]
    if not isinstance(hashes, dict):
        raise ValueError("Pre-audit Hashes must be a dict")
    for hkey, expected_h in EXPECTED_HASH_MAP.items():
        actual_h = hashes.get(hkey)
        if not isinstance(actual_h, str) or actual_h.upper() != expected_h:
            raise ValueError(f"Pre-audit Hashes.{hkey} mismatch: {actual_h!r} != {expected_h!r}")

    _require_int(audit["SysId"], "SysId", min_val=0)
    _require_int(audit["AppId"], "AppId", min_val=0)

    phys = _require_finite_number(audit["PhysAvailGiB"], "PhysAvailGiB", non_negative=True)
    if phys < MIN_PHYS_AVAIL_GIB:
        raise ValueError(f"Pre-audit PhysAvailGiB < {MIN_PHYS_AVAIL_GIB}: {phys}")
    commit = _require_finite_number(audit["CommitGiB"], "CommitGiB", non_negative=True)
    clim = _require_finite_number(audit["CommitLimitGiB"], "CommitLimitGiB", non_negative=True)
    if clim <= 0 or commit > clim:
        raise ValueError(f"Invalid pre-audit Commit/Limit: {commit}/{clim}")
    _require_finite_number(audit["DedicatedGiB"], "DedicatedGiB", non_negative=True)
    _require_finite_number(audit["SharedGiB"], "SharedGiB", non_negative=True)
    return audit


def _validate_mem_block(mem: Any, prefix: str) -> Tuple[float, float, float]:
    if not isinstance(mem, dict):
        raise ValueError(f"{prefix}.Mem must be an object")
    phys = _require_finite_number(mem.get("PhysAvailGiB"), f"{prefix}.Mem.PhysAvailGiB", non_negative=True)
    commit = _require_finite_number(mem.get("CommitGiB"), f"{prefix}.Mem.CommitGiB", non_negative=True)
    lim_key = "CommitLimGiB" if "CommitLimGiB" in mem else "CommitLimitGiB"
    clim = _require_finite_number(mem.get(lim_key), f"{prefix}.Mem.{lim_key}", non_negative=True)
    if clim <= 0 or commit > clim:
        raise ValueError(f"{prefix}.Mem Commit exceeds Limit: {commit}/{clim}")
    return phys, commit, clim


def _validate_wddm_block(wddm: Any, prefix: str) -> Tuple[float, float]:
    if not isinstance(wddm, dict):
        raise ValueError(f"{prefix}.Wddm must be an object")
    ded = _require_finite_number(wddm.get("DedicatedGiB"), f"{prefix}.Wddm.DedicatedGiB", non_negative=True)
    shr = _require_finite_number(wddm.get("SharedGiB"), f"{prefix}.Wddm.SharedGiB", non_negative=True)
    return ded, shr


def parse_and_verify_sched_route(case_id: str, stderr: str) -> Dict[str, Any]:
    exp = SCHED_EXPECTED[case_id]
    lines = [line for line in stderr.splitlines() if line.startswith(case_id + " ")]
    if len(lines) != 1:
        raise ValueError(f"missing scheduler route diagnostic or duplicate for {case_id}")
    fields = lines[0].split()[1:]
    parsed = {}
    for field in fields:
        key, sep, value = field.partition("=")
        if not sep or key in parsed or key not in exp or value != str(exp[key]):
            raise ValueError(f"scheduler route mismatch: {field}")
        parsed[key] = int(value) if isinstance(exp[key], int) else value
    if parsed != exp:
        raise ValueError(f"scheduler route mismatch: incomplete fields for {case_id}")
    return parsed


def evaluate_case_result(
    case_id: str,
    ssh_res: CommandResult,
    suite_baseline: Dict[str, Any],
    run_id: Optional[str] = None,
) -> Dict[str, Any]:
    validate_case_id(case_id)
    if ssh_res.returncode != 0:
        return {
            "case_id": case_id,
            "status": "FAIL",
            "reason": f"SSH exited with code {ssh_res.returncode}: {ssh_res.stderr.strip()}",
            "ssh_exit": ssh_res.returncode,
            "unconfirmed": True,
        }
    try:
        rep = parse_json_marker(ssh_res.stdout, "REPORT_JSON=")
    except Exception as exc:
        return {
            "case_id": case_id,
            "status": "FAIL",
            "reason": f"Audit/report JSON parse failure: {exc}",
            "ssh_exit": ssh_res.returncode,
            "unconfirmed": True,
        }

    required_keys = {
        "CaseId", "Pid", "ProcessStartUtc", "StartUtc", "EndUtc",
        "ElapsedSeconds", "TimedOut", "Unconfirmed", "ExitCode", "MonitorError",
        "Pre", "DuringSamples", "DuringSampleErrors", "DuringPeakNote", "Post",
        "Stdout", "Stderr", "LogStem",
    }
    missing = sorted(required_keys - set(rep.keys()))
    if missing:
        return {
            "case_id": case_id,
            "status": "FAIL",
            "reason": f"Report missing required fields: {missing}",
            "unconfirmed": True,
        }

    reasons: List[str] = []
    try:
        if rep["CaseId"] != case_id:
            reasons.append(f"CaseId mismatch: expected {case_id!r}, got {rep['CaseId']!r}")
        pid = _require_int(rep["Pid"], "Pid", min_val=1)
        proc_start = _require_nonempty_str(rep["ProcessStartUtc"], "ProcessStartUtc")
        _require_nonempty_str(rep["StartUtc"], "StartUtc")
        _require_nonempty_str(rep["EndUtc"], "EndUtc")
        elapsed = _require_finite_number(rep["ElapsedSeconds"], "ElapsedSeconds", non_negative=True)
        timed_out = _require_bool(rep["TimedOut"], "TimedOut")
        unconfirmed = _require_bool(rep["Unconfirmed"], "Unconfirmed")
        exit_code = _require_int(rep["ExitCode"], "ExitCode")

        if not isinstance(rep["DuringSamples"], list):
            raise ValueError("DuringSamples must be a list")
        if not isinstance(rep["DuringSampleErrors"], list):
            raise ValueError("DuringSampleErrors must be a list")
        if rep["DuringSampleErrors"]:
            reasons.append(f"during sample error: {rep['DuringSampleErrors']}")
        if rep["MonitorError"] is not None and rep["MonitorError"] != "":
            reasons.append(f"monitor error: {rep['MonitorError']}")
        _require_nonempty_str(rep["DuringPeakNote"], "DuringPeakNote")

        log_stem = _require_nonempty_str(rep["LogStem"], "LogStem")
        if run_id is not None:
            exp_stem = expected_log_stem(run_id, case_id)
            if log_stem != exp_stem:
                reasons.append(f"LogStem mismatch: expected {exp_stem!r}, got {log_stem!r}")

        if not isinstance(rep["Stdout"], str) or not isinstance(rep["Stderr"], str):
            raise ValueError("Stdout/Stderr must be strings")

        if not isinstance(rep["Pre"], dict) or not isinstance(rep["Post"], dict):
            raise ValueError("Pre/Post must be objects")

        pre = rep["Pre"]
        pre_required = {"Mem", "Wddm", "PMode", "BootUtc", "SysId", "AppId"}
        pre_missing = sorted(pre_required - set(pre.keys()))
        if pre_missing:
            raise ValueError(f"Pre missing required fields: {pre_missing}")

        pre_phys, pre_commit, _ = _validate_mem_block(pre["Mem"], "Pre")
        pre_ded, _ = _validate_wddm_block(pre["Wddm"], "Pre")
        pre_sys_id = _require_int(pre["SysId"], "Pre.SysId", min_val=0)
        pre_app_id = _require_int(pre["AppId"], "Pre.AppId", min_val=0)
        _require_nonempty_str(pre["BootUtc"], "Pre.BootUtc")

        if pre_phys < MIN_PHYS_AVAIL_GIB:
            reasons.append(f"Pre PhysAvailGiB < {MIN_PHYS_AVAIL_GIB}: {pre_phys}")
        if pre["PMode"] != "Performance":
            reasons.append(f"Pre P-MODE != Performance: {pre['PMode']}")
        if pre["BootUtc"] != suite_baseline["BootUtc"]:
            reasons.append(f"Pre OS boot time mismatch: {pre['BootUtc']} != {suite_baseline['BootUtc']}")
        if (pre_commit - float(suite_baseline["CommitGiB"])) > MAX_DELTA_GIB:
            reasons.append(f"Pre suite Commit delta > {MAX_DELTA_GIB}: {pre_commit}")
        if (pre_ded - float(suite_baseline["DedicatedGiB"])) > MAX_DELTA_GIB:
            reasons.append(f"Pre suite Dedicated delta > {MAX_DELTA_GIB}: {pre_ded}")
        if pre_sys_id < int(suite_baseline["SysId"]) or pre_app_id < int(suite_baseline["AppId"]):
            reasons.append(f"Pre event cursor regressed vs baseline: Sys={pre_sys_id}, App={pre_app_id}")

        post = rep["Post"]
        post_required = {"Mem", "Wddm", "PMode", "BootUtc", "SysId", "AppId", "CommitDeltaGiB", "DedicatedDeltaGiB", "ResidualCount", "SysErrors", "AppErrors"}
        post_missing = sorted(post_required - set(post.keys()))
        if post_missing:
            raise ValueError(f"Post missing required fields: {post_missing}")

        phys, commit, _ = _validate_mem_block(post["Mem"], "Post")
        ded, _ = _validate_wddm_block(post["Wddm"], "Post")
        commit_delta = _require_finite_number(post["CommitDeltaGiB"], "Post.CommitDeltaGiB")
        ded_delta = _require_finite_number(post["DedicatedDeltaGiB"], "Post.DedicatedDeltaGiB")
        residual_count = _require_int(post["ResidualCount"], "Post.ResidualCount", min_val=0)
        post_sys_id = _require_int(post["SysId"], "Post.SysId", min_val=0)
        post_app_id = _require_int(post["AppId"], "Post.AppId", min_val=0)
        _require_nonempty_str(post["BootUtc"], "Post.BootUtc")
        if not isinstance(post["SysErrors"], list) or not isinstance(post["AppErrors"], list):
            raise ValueError("Post.SysErrors and Post.AppErrors must be lists")

        if post_sys_id < pre_sys_id or post_app_id < pre_app_id:
            reasons.append(f"Post event cursor regressed vs Pre: Sys {pre_sys_id}->{post_sys_id}, App {pre_app_id}->{post_app_id}")

        recomp_commit_delta = round(commit - pre_commit, 3)
        recomp_ded_delta = round(ded - pre_ded, 3)
        if abs(commit_delta - recomp_commit_delta) > 0.002:
            reasons.append(f"CommitDeltaGiB mismatch: reported {commit_delta}, recomputed {recomp_commit_delta}")
        if abs(ded_delta - recomp_ded_delta) > 0.002:
            reasons.append(f"DedicatedDeltaGiB mismatch: reported {ded_delta}, recomputed {recomp_ded_delta}")

        if timed_out:
            reasons.append("timeout (>60s)")
        if elapsed >= CASE_TIMEOUT_SEC:
            reasons.append(f"elapsed seconds >= {CASE_TIMEOUT_SEC}: {elapsed}")
        if unconfirmed:
            reasons.append("process stop or output unconfirmed")
        if exit_code != 0:
            reasons.append(f"process exit code {exit_code}")

        stdout = rep["Stdout"]
        stderr = rep["Stderr"]
        if case_id == PLACEMENT_CASE:
            if [line for line in stdout.splitlines() if line.startswith("PASS ")] != [
                f"PASS {case_id} allocation-only"
            ] or "reference SHA256" in stdout + stderr:
                reasons.append("invalid allocation-only PASS")
        else:
            expected_sha = EXPECTED_REF_SHA256[case_id]
            pass_pattern = rf"(?m)^PASS {re.escape(case_id)} reference SHA256 {expected_sha}\r?$"
            if not re.search(pass_pattern, stdout):
                reasons.append(f"missing or mismatched PASS SHA256 line for {case_id}")
        if re.search(r"(?i)\b(skip|skipped|fallback)\b", stdout + "\n" + stderr):
            reasons.append("detected skip or CPU fallback marker in output")

        diag: Optional[Dict[str, float]] = None
        sched_route: Optional[Dict[str, Any]] = None
        if case_id in SCHED_CASES:
            m_diag = re.search(r"(?m)^max relative error (\S+) max condition (\S+)\r?$", stdout)
            if not m_diag:
                reasons.append("missing scheduler error diagnostic line")
            else:
                rel_err = _require_finite_number(float(m_diag.group(1)), "max relative error", non_negative=True)
                cond = _require_finite_number(float(m_diag.group(2)), "max condition", non_negative=True)
                diag = {"max_relative_error": rel_err, "max_condition": cond}
        if case_id in SCHED_EXPECTED:
            try:
                sched_route = parse_and_verify_sched_route(case_id, stderr)
            except Exception as exc:
                reasons.append(str(exc))

        if phys < MIN_PHYS_AVAIL_GIB:
            reasons.append(f"post PhysAvailGiB < {MIN_PHYS_AVAIL_GIB}: {phys}")
        if commit_delta > MAX_DELTA_GIB:
            reasons.append(f"step CommitDeltaGiB > {MAX_DELTA_GIB}: {commit_delta}")
        if ded_delta > MAX_DELTA_GIB:
            reasons.append(f"step DedicatedDeltaGiB > {MAX_DELTA_GIB}: {ded_delta}")
        if (commit - float(suite_baseline["CommitGiB"])) > MAX_DELTA_GIB:
            reasons.append(f"suite Commit delta > {MAX_DELTA_GIB}: {commit} vs {suite_baseline['CommitGiB']}")
        if (ded - float(suite_baseline["DedicatedGiB"])) > MAX_DELTA_GIB:
            reasons.append(f"suite Dedicated delta > {MAX_DELTA_GIB}: {ded} vs {suite_baseline['DedicatedGiB']}")
        if post["PMode"] != "Performance":
            reasons.append(f"post P-MODE != Performance: {post['PMode']}")
        if post["BootUtc"] != suite_baseline["BootUtc"]:
            reasons.append(f"OS boot time changed: {post['BootUtc']} != {suite_baseline['BootUtc']}")
        if residual_count != 0:
            reasons.append(f"residual process count: {residual_count}")
        if post["SysErrors"]:
            reasons.append(f"new System error events: {len(post['SysErrors'])}")
        if post["AppErrors"]:
            reasons.append(f"new Application error events: {len(post['AppErrors'])}")

    except Exception as exc:
        return {
            "case_id": case_id,
            "status": "FAIL",
            "reason": f"Invalid report schema/values: {exc}",
            "unconfirmed": True,
        }

    status = "PASS" if not reasons else "FAIL"
    return {
        "case_id": case_id,
        "status": status,
        "reason": "OK" if status == "PASS" else "; ".join(reasons),
        "pid": pid,
        "process_start_utc": proc_start,
        "elapsed_seconds": elapsed,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "unconfirmed": unconfirmed,
        "during_samples_count": len(rep["DuringSamples"]),
        "during_peak_note": rep["DuringPeakNote"],
        "expected_ref_sha256": EXPECTED_REF_SHA256.get(case_id),
        "scheduler_diagnostics": diag,
        "scheduler_route": sched_route,
        "post_mem": post["Mem"],
        "post_wddm": post["Wddm"],
        "post_sys_id": post_sys_id,
        "post_app_id": post_app_id,
        "log_stem": log_stem,
    }


def write_summary(summary_path: Path, summary: Dict[str, Any]) -> None:
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def collect_logs(
    run_id: str,
    dest_dir: Path,
    expected_cases: Sequence[str],
    case_results: Sequence[Dict[str, Any]],
    scp_runner: ScpRunner = default_scp_runner,
) -> Dict[str, Any]:
    if dest_dir.exists() and any(dest_dir.iterdir()):
        raise RuntimeError(f"Log destination already exists and is non-empty: {dest_dir}")
    remote_glob = f"{PINNED['remote_log_root'].replace(chr(92), '/')}/{run_id}-*"
    res = scp_runner(remote_glob, dest_dir, SSH_TIMEOUT_SEC)
    if res.returncode != 0:
        raise RuntimeError(f"scp log collection failed ({res.returncode}): {res.stderr}")

    expected_files: List[str] = []
    by_case = {c["case_id"]: c for c in case_results}
    for cid in expected_cases:
        safe = safe_case_name(cid)
        prefix = f"{run_id}-{safe}"
        for ext in ("stdout.log", "stderr.log", "report.json", "state.json"):
            expected_files.append(f"{prefix}.{ext}")
            fpath = dest_dir / f"{prefix}.{ext}"
            if not fpath.is_file():
                raise RuntimeError(f"Missing collected log file: {fpath.name}")

        stdout_text = (dest_dir / f"{prefix}.stdout.log").read_bytes().decode("utf-8")
        stderr_text = (dest_dir / f"{prefix}.stderr.log").read_bytes().decode("utf-8")
        rep_data = json.loads((dest_dir / f"{prefix}.report.json").read_text(encoding="utf-8-sig"))
        st_data = json.loads((dest_dir / f"{prefix}.state.json").read_text(encoding="utf-8-sig"))
        c_rec = by_case[cid]
        exp_stem = expected_log_stem(run_id, cid)

        if (rep_data.get("CaseId") != cid or st_data.get("CaseId") != cid or
                rep_data.get("Pid") != c_rec.get("pid") or st_data.get("Pid") != c_rec.get("pid") or
                rep_data.get("ProcessStartUtc") != c_rec.get("process_start_utc") or
                st_data.get("ProcessStartUtc") != c_rec.get("process_start_utc") or
                rep_data.get("ExitCode") != 0 or st_data.get("ExitCode") != 0 or
                rep_data.get("TimedOut") is not False or st_data.get("TimedOut") is not False or
                rep_data.get("Unconfirmed") is not False or st_data.get("Unconfirmed") is not False or
                st_data.get("Status") != "Completed" or
                rep_data.get("LogStem") != exp_stem or st_data.get("LogStem") != exp_stem):
            raise RuntimeError(f"Collected log metadata mismatch for case {cid}")

        if rep_data.get("Stdout") != stdout_text or rep_data.get("Stderr") != stderr_text:
            raise RuntimeError(f"Collected stdout/stderr content differs from report.json for case {cid}")

    actual_files = sorted(p.name for p in dest_dir.iterdir() if p.is_file() and p.name != "SHA256SUMS")
    if actual_files != sorted(expected_files):
        raise RuntimeError(f"Unexpected file set in {dest_dir}: expected {len(expected_files)}, got {len(actual_files)}")

    lines = []
    for fname in actual_files:
        h = hashlib.sha256((dest_dir / fname).read_bytes()).hexdigest()
        lines.append(f"{h}  {fname}")
    (dest_dir / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"collected_count": len(actual_files), "sha256sums_path": str(dest_dir / "SHA256SUMS")}


def run_suite(
    output_dir: Path,
    cases: Sequence[str] = CASES,
    run_id: Optional[str] = None,
    ssh_runner: SshRunner = default_ssh_runner,
    scp_runner: ScpRunner = default_scp_runner,
    collect_on_pass: bool = True,
    pre_audit_only: bool = False,
) -> Dict[str, Any]:
    if not (re.fullmatch(r"[0-9a-f]{40}", PINNED["source_commit"]) and PINNED["binary_dir"]
            and all(re.fullmatch(r"[0-9A-F]{64}", h) for h in EXPECTED_HASH_MAP.values())):
        raise ValueError("HIP-2E-4 build pins are incomplete")
    validated_cases = [validate_case_id(c) for c in cases]
    if run_id is None:
        run_id = "hip2e4-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    if not re.fullmatch(r"hip2e4-[A-Za-z0-9_-]+", run_id):
        raise ValueError(f"Invalid run_id: {run_id!r}")

    summary_path = output_dir / f"{run_id}-summary.json"
    logs_dir = output_dir / f"{run_id}-logs"
    if summary_path.exists() or logs_dir.exists():
        raise FileExistsError(f"Run output already exists for run_id={run_id}; refuse to overwrite")

    summary: Dict[str, Any] = {
        "run_id": run_id,
        "pre_audit_only": pre_audit_only,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "pinned": PINNED,
        "pre_audit": None,
        "cases": [{"case_id": c, "status": "NOT RUN"} for c in validated_cases],
        "gpu_cases_passed": False,
        "overall_status": "RUNNING",
        "stop_reason": None,
        "collected_logs": None,
    }
    write_summary(summary_path, summary)

    remote_cmd = build_remote_ssh_command()

    try:
        pre_res = ssh_runner(build_pre_audit_ps(), remote_cmd, SSH_TIMEOUT_SEC)
    except Exception as exc:
        summary["overall_status"] = "FAIL"
        summary["stop_reason"] = f"Pre-suite audit exception ({type(exc).__name__}): {exc}"
        summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
        write_summary(summary_path, summary)
        return summary

    if pre_res.returncode != 0:
        summary["overall_status"] = "FAIL"
        summary["stop_reason"] = f"Pre-suite audit failed (SSH/PS exit {pre_res.returncode}): {pre_res.stderr.strip()}"
        summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
        write_summary(summary_path, summary)
        return summary

    try:
        baseline = validate_pre_audit_json(parse_json_marker(pre_res.stdout, "AUDIT_JSON="))
    except Exception as exc:
        summary["overall_status"] = "FAIL"
        summary["stop_reason"] = f"Pre-suite audit validation failed: {exc}"
        summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
        write_summary(summary_path, summary)
        return summary

    summary["pre_audit"] = baseline
    write_summary(summary_path, summary)

    if pre_audit_only:
        summary["overall_status"] = "PASS"
        summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
        write_summary(summary_path, summary)
        return summary

    prev_sys_id = int(baseline["SysId"])
    prev_app_id = int(baseline["AppId"])
    all_passed = True

    for idx, case_id in enumerate(validated_cases):
        try:
            case_ps = build_case_ps(case_id, run_id, prev_sys_id, prev_app_id, baseline)
            case_res = ssh_runner(case_ps, remote_cmd, SSH_TIMEOUT_SEC)
            evaluated = evaluate_case_result(case_id, case_res, baseline, run_id=run_id)
        except Exception as exc:
            evaluated = {
                "case_id": case_id,
                "status": "FAIL",
                "reason": f"Controller SSH/supervision exception ({type(exc).__name__}): {exc}; remote process state Unconfirmed",
                "unconfirmed": True,
            }

        summary["cases"][idx] = evaluated
        if evaluated["status"] != "PASS":
            all_passed = False
            summary["overall_status"] = "FAIL"
            summary["stop_reason"] = f"Stopped at case {case_id}: {evaluated['reason']}"
            summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
            write_summary(summary_path, summary)
            return summary

        prev_sys_id = int(evaluated["post_sys_id"])
        prev_app_id = int(evaluated["post_app_id"])
        write_summary(summary_path, summary)

    if all_passed:
        summary["gpu_cases_passed"] = True
        if collect_on_pass:
            try:
                summary["collected_logs"] = collect_logs(
                    run_id, logs_dir, validated_cases, summary["cases"], scp_runner=scp_runner
                )
            except Exception as exc:
                summary["overall_status"] = "FAIL"
                summary["stop_reason"] = f"GPU cases passed but log collection failed: {exc}"
                summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
                write_summary(summary_path, summary)
                return summary
        summary["overall_status"] = "PASS"

    summary["ended_utc"] = datetime.now(timezone.utc).isoformat()
    write_summary(summary_path, summary)
    return summary


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="HIP-2E-4 serial GPU validation supervisor")
    parser.add_argument("--output-dir", type=Path, required=True, help="Controller output directory")
    parser.add_argument("--run-id", default=None, help="Explicit run identifier")
    parser.add_argument("--pre-audit-only", action="store_true", help="Run only pre-suite audit without launching GPU cases")
    args = parser.parse_args(argv)
    summary = run_suite(
        args.output_dir,
        run_id=args.run_id,
        collect_on_pass=True,
        pre_audit_only=args.pre_audit_only,
    )
    print(f"OVERALL={summary['overall_status']} RUN_ID={summary['run_id']}")
    return 0 if summary["overall_status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
