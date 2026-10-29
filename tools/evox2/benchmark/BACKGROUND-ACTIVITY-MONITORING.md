# Windows benchmark background-activity evidence (post-tag tooling, 2026-10-29)

**Status: Windows live-run functional validation PASS (bounded), 2026-10-29.** The 2-second resource / 15-second background cadence and successful llama-bench execution are verified. One 4.89-second heavy probe delayed a resource row; no claim of zero measurement overhead. The immutable b11908 executable and public source tag are unchanged.

The EVO-X2 benchmark wrappers `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1` now record two **lightweight, no-extra-process** snapshots automatically for each non-dry-run measurement:

- `conditions.json: BackgroundActivityAtStart`: observed process names, PIDs, per-process cumulative CPU seconds at the beginning.
- `result.json: BackgroundActivityAtStart / BackgroundActivityAtFinish / BackgroundActivitySummary`: processes observed at the boundaries and CPU-time increments between them.
- `summary.csv`: `BackgroundNoisePossible`, semicolon-joined `BackgroundBusyNames`, and `BackgroundCpuPercent` (CPU-time share across the machine's logical processors).
- If potentially busy processes were seen, the wrapper emits a **warning only**. Results are **never automatically discarded** or assigned a different status.

Recognized process executables are from **Microsoft Defender** (`MsMpEng`, `NisSrv`, `MpCmdRun`), **Windows Update and maintenance** (`TiWorker`, `TrustedInstaller`, `MoUsoCoreWorker`, `UsoClient`, `wuauclt`, `WaaSMedicAgent`, `WindowsUpdateBox`, `dismhost`, `SetupHost`, `CompatTelRunner`) and **Windows Search indexing** (`SearchIndexer`, `SearchProtocolHost`, `SearchFilterHost`). The list intentionally does **not** equate idle Defender services or any generic `svchost.exe` with active background interference.

> **b11908 CLI-compatibility note:** The initial 2026-10-29 monitor smoke benchmark failed **before any PP/TG work** because the older wrapper passed unsupported `llama-bench -c 4096`. This does **not** demonstrate a monitoring fault or throughput regression. The corrected test omits `-Context` and uses native per-test automatic context. See [b11908 llama-bench argument compatibility](LLAMA-BENCH-B11908-ARGUMENT-COMPATIBILITY.md) before repeating this smoke test.

## 2026-10-29 Windows live-run validation — bounded PASS

- Original user-supplied run ZIP: `20261029-234938-110-bench-vulkan-b11908-ctx1024-8f87d4db6047.zip`, **SHA256 `ab870e682b9fdd84379ae6e8084a2de07aa24541bbfde298543518c525c1fd10`**, 24,711 bytes. Evidence inspected from `conditions.json`, `result.json`, `llama-bench.json`, `resources.csv`, `summary.csv`, `stderr.log` and monitor logs; raw ZIP not committed (user-local model paths).
- Environment: Windows 11 / EVO-X2 Radeon 8060S, Vulkan **b11908** (`b82243bf0`), Unsloth Qwen3.8 Flash Next UD-IQ3_XXS PLE16, **random tokens**. `-p 512 -n 1024 -d 0 -r 4` with `ContextMode=PerTestAuto`. `-ResourceMonitor -ResourceIntervalSeconds 2 -BackgroundIntervalSeconds 15 -NoAdlxMonitor`. No forced `-c`; this was the successful retry after the earlier argument incompatibility.
- **Benchmark completed normally:** `Status=OK`, exit code **0**, 2 native test rows, duration **196.1 s**. PP 512 = **550.178 tokens/s ±1.835**; TG 1024 = **29.423 tokens/s ±0.056** (native means ± standard deviations, 4 repetitions each). These are smoke measurements, **not** a controlled overhead A/B comparison. P-MODE **Performance** at both boundaries.
- **Cadence regression validator PASS:** 95 resource rows, **11 actual background probes**, 84 skipped; expected 15-second minimum. Median resource-row interval **2.008 s**. Consecutive background probe timestamps were generally **16.06–16.13 s** apart, with one interval **20.037 s** after an expensive probe. First probe was deferred.
- **Probe overhead observable:** background probe duration median **85.5 ms**, maximum **4,887.6 ms** at sample **64** (23:51:48 local). That resource row's total collection took **5,963 ms**; the following resource interval reached **5.970 s** at sample **65**. Resource sampling then returned to approximately 2 s. This demonstrates that rare slow CIM activity still perturbs monitoring cadence; minimizing probe frequency **does not eliminate** its potential effect on inference.
- **Process coverage complete:** `MsMpEng`, `NisSrv`, `SearchIndexer` present and comparable at start/end; `CpuKnownCount=3`, `CpuCoverage=Complete`, aggregate **4.672 CPU seconds**, **0.074% of total logical CPU time** over the run, `PossibleNoise=False` under the configured 0.5%-per-process threshold. Ten in-run comparisons also returned False; the first in-run probe has no earlier snapshot and therefore has no comparison.
- **Browser launch during run (user-reported):** System used RAM rose from roughly **7.25 GiB to over 8 GiB around 23:51:40**; some later total CPU utilization samples exceeded **20%**. The monitor does **not** attribute browser process CPU, and the user did not provide a precise browser-launch timestamp. Correlation is plausible but browser causality and any effect on PP/TG cannot be established. GPU model load also drives large initial disk reads; do not attribute those reads to the browser.
- Resource-monitor stdout/stderr logs are empty (no monitor errors). This **closes the post-tag monitoring functional verification** only. Repeat with and without the resource monitor under matched model/P-MODE/driver conditions if attributing benchmark throughput overhead, and consider `-BackgroundIntervalSeconds 30` or `60` for high-precision long-context A/B work.

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

The verifier checks skipped rows, sampling time fields and minimum spacing, and reports the largest actual resource-row gap and the most expensive background probe. **Historical note (before the live run above):** this statement described the code-only status before successful Windows revalidation.

A process is **possibly interfering**, not proven causal, if one named process consumes at least **0.5% of total logical-machine CPU time** within an observation interval. Because periodic snapshots are now sparser, short spikes and short-lived processes are **more likely to be missed** than with 2-second sampling. Existing system CPU, paging and disk throughput counters remain useful for correlation.


## 2026-10-29 Windows retest finding and fix

In a real VS2022 Native Tools PowerShell test, `Get-Process` listed `MsMpEng`, `NisSrv`, `SearchIndexer`, and `SearchProtocolHost`, but `CpuKnownCount=0` for the 3.096-second observation. The original comparator returned `PossibleNoise=False`, which was **not justified** because **none of the process CPU counters was readable**.

The corrected snapshot tries `Win32_PerfRawData_PerfProc_Process` when `Get-Process.CPU` is null, using the cumulative raw CPU counter (100-nanosecond units) converted to seconds. It does not attempt service changes, kernel tracing, process termination, or heavy file scanning. The comparator records `CpuCoverage`, `CpuKnownCount`, `CpuComparedCount` and three-state `PossibleNoise`:

- `True`: at least one named background process crossed the configured 0.5% of all-core CPU-time threshold.
- `False`: CPU evidence was complete for the observed candidates, and none crossed the threshold; or no candidate processes were observed at either boundary (short-lived activity can still be missed).
- **`$null` / blank CSV field**: unknown; counters inaccessible or incomplete. `Status=CpuUnavailable` (none) or `Status=PartialCoverage` (some) makes this explicit. This must **never** be interpreted as a quiet benchmark run.

`Get-Evox2BackgroundActivitySnapshot` now includes `CpuSource` (`GetProcess` or `PerfProcRaw100ns`) and `CpuProbeError` for diagnostics. `summary.csv` also includes `BackgroundProbeStatus`, `BackgroundCpuCoverage`, `BackgroundCpuKnownCount` in addition to the earlier fields. `resources.csv` includes per-sample coverage fields; its first sample is intentionally `FirstSample` because a delta needs two observations. If CPU data remain unavailable, the wrapper **warns but does not change the inference run status**.

To validate the zero-counter and busy/quiet interpretation without a model, run [Test-BackgroundActivityClassification.ps1](tests/Test-BackgroundActivityClassification.ps1) in Windows PowerShell 5.1. **Live test update:** PerfProc fallback succeeded for all three protected/indexer process readings in this run. Other Windows configurations can still yield unreadable counters, correctly marked unknown.

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
