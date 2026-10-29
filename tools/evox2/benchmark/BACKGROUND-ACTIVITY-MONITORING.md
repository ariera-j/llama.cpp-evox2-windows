# Windows benchmark background-activity evidence (post-tag tooling, 2026-10-29)

**Status: code staged on main, Windows execution not yet re-validated.** The r6 b11908 executable and immutable public source tag are unchanged.

The EVO-X2 benchmark wrappers `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1` now record two **lightweight, no-extra-process** snapshots automatically for each non-dry-run measurement:

- `conditions.json: BackgroundActivityAtStart`: observed process names, PIDs, per-process cumulative CPU seconds at the beginning.
- `result.json: BackgroundActivityAtStart / BackgroundActivityAtFinish / BackgroundActivitySummary`: processes observed at the boundaries and CPU-time increments between them.
- `summary.csv`: `BackgroundNoisePossible`, semicolon-joined `BackgroundBusyNames`, and `BackgroundCpuPercent` (CPU-time share across the machine's logical processors).
- If potentially busy processes were seen, the wrapper emits a **warning only**. Results are **never automatically discarded** or assigned a different status.

Recognized process executables are from **Microsoft Defender** (`MsMpEng`, `NisSrv`, `MpCmdRun`), **Windows Update and maintenance** (`TiWorker`, `TrustedInstaller`, `MoUsoCoreWorker`, `UsoClient`, `wuauclt`, `WaaSMedicAgent`, `WindowsUpdateBox`, `dismhost`, `SetupHost`, `CompatTelRunner`) and **Windows Search indexing** (`SearchIndexer`, `SearchProtocolHost`, `SearchFilterHost`). The list intentionally does **not** equate idle Defender services or any generic `svchost.exe` with active background interference.

## 2026-10-29 monitoring cadence reduction (post-tag)

The Windows smoke check measured **9.468 s elapsed for a nominal 3 s sleep** across two background snapshots, suggesting the protected-process CPU counter fallback may be expensive. The original monitor called that snapshot **on every resource row**, potentially perturbing PP/TG. The revised design separates the two frequencies:

| Probe | Default | Trigger |
| --- | --- | --- |
| Existing GPU/system CPU, paging, RAM and disk resource counters | **2 s** (unchanged) | `-ResourceMonitor -ResourceIntervalSeconds 2` |
| Defender / Windows servicing / Search named-process CPU snapshot (including the PerfProc CIM fallback when needed) | **15 s** (new default) | `-BackgroundIntervalSeconds 15` |
| Before/after named-process snapshots | Once at run start and once after inference | Always captured by `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1`, even without `-ResourceMonitor` |

**Cadence semantics:** the resource-monitor subprocess delays its *first* heavy named-process snapshot until at least 15 seconds after the monitor starts. Further snapshots are scheduled 15 seconds **after the previous probe completes**, not every N resource rows, so an unexpectedly slow CIM call does not cause repeated catch-up probes. A short inference can therefore have **zero** in-run named-process samples; its start/end summary still exists. In-run CPU deltas require **two** samples (normally at about 15 s and 30+ s of resource-monitor time).

When a heavy snapshot is taken, `resources.csv` includes only that row's named-process status and CPU deltas. Other rows have **`BackgroundSampleTaken=False`, `BackgroundProbeStatus=NotSampled` and blank CPU activity fields**; these rows are *not* evidence that the system was quiet. The first snapshot records `BackgroundCpuCoverage=FirstSample` and no delta. Additional fields:

- `BackgroundIntervalSeconds`: configured minimum delay, default 15.
- `BackgroundSampleCount`, `BackgroundSampleTaken`, `BackgroundSampleTimestampUtc`: distinguish real snapshots from skipped rows.
- `BackgroundSampleIntervalSecondsActual`: measured time between the last two snapshot timestamps.
- `BackgroundCollectionMilliseconds`: wall-clock duration of **this expensive named-process probe**; blank when skipped.
- Existing `SampleIntervalSecondsActual` and `CounterCollectionMilliseconds` still describe the **overall** resource loop, which may exceed 2 s on rows where an expensive probe is performed.
- `BackgroundCpuCoverage`, `BackgroundCpuComparedCount`, `BackgroundCpuKnownCount`, `BackgroundObservedNames`, `BackgroundActiveNames`, `BackgroundBusyNames`, `BackgroundCpuDeltaSeconds`, `BackgroundCpuPercentOfSystem`, `BackgroundNoisePossible` remain present but only carry evidence when a snapshot or valid delta exists.

Example with the existing CLI/bench wrappers:

```powershell
# Add these parameters to an existing Measure-LlamaCli.ps1 or
# Measure-LlamaBench.ps1 invocation; no model flags need to change.
-ResourceMonitor -ResourceIntervalSeconds 2 -BackgroundIntervalSeconds 15
```

The same interval is passed automatically to `Monitor-LlamaProcess.ps1`, and `conditions.json.ResourceMonitor.BackgroundIntervalSeconds` and the wrapper's preview record it for reproducibility. The ordinary resource `Timestamp` is captured **before** the potentially slow background probe, so timestamped CPU/GPU/disk counters continue to refer to when those counters were collected, rather than the end of the WMI request. To reduce overhead further for a strict A/B experiment, use a larger interval (e.g. 30 or 60 seconds) **consistently in both test arms**, or omit `-ResourceMonitor` (start/end snapshots still run outside inference). This is sampling rather than asynchronous tracing: **a heavy probe can still delay a particular 2-second row**. Use `BackgroundCollectionMilliseconds` and `SampleIntervalSecondsActual` to quantify it, rather than assuming monitoring has no cost.

To validate a produced `resources.csv` without running another inference, execute:

```powershell
.\tools\evox2\benchmark\tests\Test-ResourceMonitorCadence.ps1 `
    -CsvPath 'C:\path\to\a\completed\run\resources.csv'
```

The verifier checks skipped rows, sampling time fields and minimum spacing, and reports the largest actual resource-row gap and the most expensive background probe. **Windows live-runtime execution of the new monitor remains pending**; the script changes have only been inspected statically in this update.

A process is **possibly interfering**, not proven causal, if one named process consumes at least **0.5% of total logical-machine CPU time** within an observation interval. Because periodic snapshots are now sparser, short spikes and short-lived processes are **more likely to be missed** than with 2-second sampling. Existing system CPU, paging and disk throughput counters remain useful for correlation.


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
