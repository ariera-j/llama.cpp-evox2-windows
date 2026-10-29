# Windows benchmark background-activity evidence (post-tag tooling, 2026-10-29)

**Status: code staged on main, Windows execution not yet re-validated.** The r6 b11908 executable and immutable public source tag are unchanged.

The EVO-X2 benchmark wrappers `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1` now record two **lightweight, no-extra-process** snapshots automatically for each non-dry-run measurement:

- `conditions.json: BackgroundActivityAtStart`: observed process names, PIDs, per-process cumulative CPU seconds at the beginning.
- `result.json: BackgroundActivityAtStart / BackgroundActivityAtFinish / BackgroundActivitySummary`: processes observed at the boundaries and CPU-time increments between them.
- `summary.csv`: `BackgroundNoisePossible`, semicolon-joined `BackgroundBusyNames`, and `BackgroundCpuPercent` (CPU-time share across the machine's logical processors).
- If potentially busy processes were seen, the wrapper emits a **warning only**. Results are **never automatically discarded** or assigned a different status.

Recognized process executables are from **Microsoft Defender** (`MsMpEng`, `NisSrv`, `MpCmdRun`), **Windows Update and maintenance** (`TiWorker`, `TrustedInstaller`, `MoUsoCoreWorker`, `UsoClient`, `wuauclt`, `WaaSMedicAgent`, `WindowsUpdateBox`, `dismhost`, `SetupHost`, `CompatTelRunner`) and **Windows Search indexing** (`SearchIndexer`, `SearchProtocolHost`, `SearchFilterHost`). The list intentionally does **not** equate idle Defender services or any generic `svchost.exe` with active background interference.

When the existing **`-ResourceMonitor` switch** is used, `Monitor-LlamaProcess.ps1` additionally samples process presence and CPU-time deltas at `-ResourceIntervalSeconds` (default 2s) and writes these columns to **`resources.csv`**:

`BackgroundProbeStatus`, `BackgroundObservedNames`, `BackgroundActiveNames`, `BackgroundBusyNames`, `BackgroundCpuDeltaSeconds`, `BackgroundCpuPercentOfSystem`, `BackgroundNoisePossible`.

A process is **possibly interfering**, not proven causal, if one named process consumes at least **0.5% of total logical-machine CPU time** within an observation interval. The start/end summary is averaged over the whole run, so short bursts are easier to see in `resources.csv`. Existing total system CPU, paging and disk throughput columns remain useful to correlate apparent interference.

## 2026-10-29 Windows retest finding and fix

In a real VS2022 Native Tools PowerShell test, `Get-Process` listed `MsMpEng`, `NisSrv`, `SearchIndexer`, and `SearchProtocolHost`, but `CpuKnownCount=0` for the 3.096-second observation. The original comparator returned `PossibleNoise=False`, which was **not justified** because **none of the process CPU counters was readable**.

The corrected snapshot tries `Win32_PerfRawData_PerfProc_Process` when `Get-Process.CPU` is null, using the cumulative raw CPU counter (100-nanosecond units) converted to seconds. It does not attempt service changes, kernel tracing, process termination, or heavy file scanning. The comparator records `CpuCoverage`, `CpuKnownCount`, `CpuComparedCount` and three-state `PossibleNoise`:

- `True`: at least one named background process crossed the configured 0.5% of all-core CPU-time threshold.
- `False`: CPU evidence was complete for the observed candidates, and none crossed the threshold; or no candidate processes were observed at either boundary (short-lived activity can still be missed).
- **`$null` / blank CSV field**: unknown; counters inaccessible or incomplete. `Status=CpuUnavailable` (none) or `Status=PartialCoverage` (some) makes this explicit. This must **never** be interpreted as a quiet benchmark run.

`Get-Evox2BackgroundActivitySnapshot` now includes `CpuSource` (`GetProcess` or `PerfProcRaw100ns`) and `CpuProbeError` for diagnostics. `summary.csv` also includes `BackgroundProbeStatus`, `BackgroundCpuCoverage`, `BackgroundCpuKnownCount` in addition to the earlier fields. `resources.csv` includes per-sample coverage fields; its first sample is intentionally `FirstSample` because a delta needs two observations. If CPU data remain unavailable, the wrapper **warns but does not change the inference run status**.

To validate the zero-counter and busy/quiet interpretation without a model, run [Test-BackgroundActivityClassification.ps1](tests/Test-BackgroundActivityClassification.ps1) in Windows PowerShell 5.1. A Windows retest of the actual PerfProc fallback is still needed; protected processes can remain unreadable even with this fallback.

## Quick checks without inference

From a Windows PowerShell 5.1 x64 session at repo root:

```powershell
Import-Module .\tools\evox2\benchmark\Evox2.Benchmark.psm1 -Force
$a = Get-Evox2BackgroundActivitySnapshot
Start-Sleep -Seconds 3
$b = Get-Evox2BackgroundActivitySnapshot
Compare-Evox2BackgroundActivitySnapshots -Before $a -After $b | Format-List
$a.Processes | Select-Object Name, Pid, CpuSource, CpuSeconds | Format-Table
$b.Processes | Select-Object Name, Pid, CpuSource, CpuSeconds | Format-Table
```

For a real measurement, add `-ResourceMonitor` to the **same command** you already use for `Measure-LlamaCli.ps1` or `Measure-LlamaBench.ps1` (or via the existing matrix plan). You will then see the extra `resources.csv` columns alongside the existing ADLX and P-MODE evidence. No changes to model, inference environment variables or Windows services are needed.

## Caveats

- A running `MsMpEng.exe` with negligible CPU is **not** proof of a scan; Windows Defender may use other worker processes or kernel I/O. Updates can run inside shared `svchost.exe` processes and **may be missed**.
- A process that starts and exits between two observations can be missed, especially in short runs. Access to CPU counters may be restricted; null counter fields mean **unknown**, not zero.
- Per-process disk attribution is **not implemented**. Correlate with existing system disk MB/s and paging columns; do not infer that a named process caused all disk traffic.
- Monitoring itself has some measurement overhead. For tight A/B benchmarks keep the monitoring configuration identical across variants, and compare recorded P-MODE/ADLX conditions as before.
- The `BackgroundNoisePossible` flag is a conservative *hint*, not a benchmark failure and not a guarantee the system was quiet when it is false.

This tooling is intentionally post-tag and limited to measurement / build scripts. Validate its PowerShell behavior on the actual Windows host before relying on automatic noise annotations.
