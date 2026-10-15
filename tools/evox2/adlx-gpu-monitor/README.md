# Evo-X2 ADLX GPU monitor (investigation)

This folder contains a small Windows-only ADLX performance-metrics logger for the GMKtec Evo-X2 / Radeon 8060S investigation.

Its first purpose is deliberately narrow:

1. verify that AMD ADLX performance metrics can be read while the machine is accessed through Windows Remote Desktop (RDP);
2. write those metrics to a simple timestamped CSV at roughly the same cadence used for the existing benchmark resource logs;
3. keep the experiment isolated from the existing benchmark PowerShell scripts until RDP behavior and monitoring overhead are understood.

This tool is **not integrated into `Measure-LlamaCli.ps1` or `Monitor-LlamaProcess.ps1` yet**. If the RDP test succeeds, the intended next step is to integrate it as an optional, fail-open sidecar monitor and then move the validated implementation into the r5 main branch.

## Why ADLX

AMD Software: Adrenalin Edition can display GPU clock, temperature, power, usage, and memory clock on the Evo-X2. Its CSV logging also works with a directly connected display, but in the current investigation the Adrenalin logging UI does not start recording during an RDP session.

ADLX provides the underlying AMD performance-monitoring API without depending on the Adrenalin metrics UI.

The implementation uses AMD's public ADLX API and follows the structure of AMD's official `PerfGPUMetrics` sample. The ADLX SDK itself is **not vendored into this repository**.

Pinned SDK for this experiment:

- AMD ADLX SDK v2.0
- release: 2026-09-20
- tag: `v2.0`
- commit: `1ca2dd42f1df8cbd045489b7a20013a07692a446`
- upstream: https://github.com/GPUOpen-LibrariesAndSDKs/ADLX
- documentation: https://gpuopen.com/adlx/

The AMD display driver supplies the ADLX runtime DLL. The SDK checkout is only needed to compile this test program.

## Files

- `src/adlx_gpu_monitor.cpp` - ADLX metric probe/logger.
- `CMakeLists.txt` - standalone CMake target. It compiles AMD's ADLX helper sources from an external SDK checkout.
- `Build-AdlxGpuMonitor.ps1` - downloads the pinned ADLX v2.0 SDK when necessary and builds the logger.
- `Run-AdlxGpuMonitor.ps1` - convenience wrapper for the RDP test.
- `.gitignore` - ignores the downloaded SDK, local build output, and test CSVs.

## Requirements

Target environment is Windows 11 x64 with an ADLX-compatible AMD display driver.

Build requirements:

- Git
- CMake
- Visual Studio 2022 Build Tools with C++ desktop tools
- AMD display driver / Adrenalin installation

The build script uses the `Visual Studio 17 2022` CMake generator. It first looks for `cmake.exe` in PATH and then checks the standalone CMake location and Visual Studio Build Tools' bundled CMake via `vswhere.exe`. Therefore an x64 Native Tools prompt should not normally be required.

If CMake is installed in another location, pass it explicitly:

```powershell
.\Build-AdlxGpuMonitor.ps1 -CMakePath 'C:\path\to\cmake.exe'
```

## 1. Switch to the investigation branch

From the repository root:

```powershell
git fetch origin
git switch --track origin/investigation/r5-adlx-gpu-monitor-20261015
```

If the branch already exists locally:

```powershell
git switch investigation/r5-adlx-gpu-monitor-20261015
git pull --ff-only
```

Then:

```powershell
cd .\tools\evox2\adlx-gpu-monitor
```

## 2. Build

The simplest build is:

```powershell
.\Build-AdlxGpuMonitor.ps1
```

On first use the script clones ADLX v2.0 into:

```text
tools\evox2\adlx-gpu-monitor\_deps\ADLX-v2.0
```

and verifies that the checkout is the pinned v2.0 commit.

The executable is written to:

```text
tools\evox2\adlx-gpu-monitor\build\bin\evox2-adlx-gpu-monitor.exe
```

To use an existing ADLX v2.0 checkout instead:

```powershell
.\Build-AdlxGpuMonitor.ps1 -AdlxRoot C:\path\to\ADLX -NoFetch
```

To force a clean CMake build:

```powershell
.\Build-AdlxGpuMonitor.ps1 -Clean
```

## 3. First RDP test

Keep the Evo-X2 in the same RDP session in which you normally run the llama.cpp benchmarks.

First list the GPUs that ADLX can see:

```powershell
.\Run-AdlxGpuMonitor.ps1 -ListGpus
```

Expected on the Evo-X2 is at least one AMD GPU, normally Radeon 8060S.

Then run a 30-second test at a 2-second interval:

```powershell
.\Run-AdlxGpuMonitor.ps1 -DurationSeconds 30 -IntervalMs 2000
```

The wrapper saves a CSV under:

```text
tools\evox2\adlx-gpu-monitor\logs\
```

A 30-second / 2-second run samples immediately and then at 2-second targets through about 30 seconds, so approximately 16 data rows are expected.

The executable also prints:

- ADLX runtime version;
- GPUs visible to ADLX;
- which metrics the selected GPU reports as supported;
- the Windows session ID;
- whether `GetSystemMetrics(SM_REMOTESESSION)` reports the process as being in a remote session.

Under a normal RDP session, `remote=yes` / CSV `remote_session=1` is expected. The important result, however, is whether ADLX returns real GPU metrics; session detection itself is only diagnostic metadata.

## 4. CSV fields

The CSV currently contains:

- `timestamp_local`
- `elapsed_ms`
- `adlx_timestamp_ms`
- `windows_session_id`
- `remote_session`
- `gpu_index`
- `gpu_name`
- `gpu_usage_pct`
- `gpu_clock_mhz`
- `gpu_vram_clock_mhz`
- `gpu_temp_c`
- `gpu_hotspot_c`
- `gpu_power_w`
- `gpu_vram_mb`
- `total_board_power_w`
- `adlx_result`

Unsupported metrics are left blank instead of failing the run.

The fields most important for comparison with the directly connected Adrenalin `Hardware.*.CSV` are:

| Adrenalin | ADLX logger |
|---|---|
| GPU UTIL | `gpu_usage_pct` |
| GPU SCLK | `gpu_clock_mhz` |
| GPU MCLK | `gpu_vram_clock_mhz` |
| GPU TEMP | `gpu_temp_c` |
| GPU PWR | `gpu_power_w` |

The two programs do not sample at exactly the same instant, so small instantaneous differences are expected.

## 5. Success criteria for the RDP probe

For the first test, consider the approach viable if all of the following are true:

- `--list-gpus` sees the Radeon 8060S under RDP;
- the 30-second run exits with code 0;
- the CSV receives roughly 16 samples;
- `adlx_result` is successful for each sample;
- GPU clock, temperature, power, usage, and VRAM clock are populated when ADLX reports them as supported;
- values change plausibly when GPU load changes.

If it fails, preserve both the console output and any CSV that was created. The startup diagnostics distinguish several useful failure modes: ADLX initialization failure, no GPU visible in the RDP session, performance-monitoring service failure, unsupported metrics, and per-sample `GetCurrentGPUMetrics` failures.

## 6. Optional longer test

After the 30-second probe works:

```powershell
.\Run-AdlxGpuMonitor.ps1 -DurationSeconds 300 -IntervalMs 2000
```

To run until Ctrl+C:

```powershell
.\build\bin\evox2-adlx-gpu-monitor.exe --duration 0 --interval-ms 2000 --output .\logs\manual.csv
```

To follow a specific Windows process and stop when it exits:

```powershell
.\build\bin\evox2-adlx-gpu-monitor.exe --duration 0 --interval-ms 2000 --target-pid 12345 --output .\logs\pid-test.csv
```

Ctrl+C is handled as a graceful stop request and the CSV is flushed after every sample.

## Benchmark integration

The investigation branch now integrates the ADLX logger with both `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1`.

Default behavior:

- ADLX monitoring is requested automatically for every measurement;
- samples are written to `gpu-metrics.csv` beside `resources.csv`;
- the default interval is 2000 ms and GPU index is 0;
- the monitor receives the llama process PID through `--target-pid` and exits cleanly after that process ends;
- ADLX stdout/stderr are saved as `adlx-monitor.stdout.log` and `adlx-monitor.stderr.log`;
- monitor executable identity, SHA-256, interval, GPU index, and availability are recorded in `conditions.json`;
- actual start status, exit code, error text, and sample count are recorded in `result.json`;
- ADLX failures are fail-open and do not abort the llama.cpp benchmark.

To disable ADLX telemetry for an overhead/control run:

```powershell
.\Measure-LlamaCli.ps1 ... -NoAdlxMonitor
.\Measure-LlamaBench.ps1 ... -NoAdlxMonitor
```

Optional overrides:

```powershell
-AdlxIntervalMs 2000
-AdlxGpuIndex 0
-AdlxMonitorExe 'C:\path\to\evox2-adlx-gpu-monitor.exe'
```

The C++ monitor must be rebuilt after pulling the integration because benchmark mode uses the new `--target-pid` option.

The remaining validation before moving this integration to the r5 main branch is to confirm one normal llama-cli run and one normal llama-bench run produce valid GPU CSVs, then measure benchmark overhead with ADLX monitoring ON/OFF. The current implementation still uses `GetCurrentGPUMetrics()` per sample; tracking/history APIs remain a possible later optimization if the overhead test shows a measurable effect.


## Validation notes

Validated on GMKtec Evo-X2 / Radeon 8060S under a normal, non-elevated Windows RDP session on 2026-10-15.

- ADLX runtime version reported by the installed driver: 1.5
- GPU enumeration works over RDP
- GPU usage, core clock, VRAM clock, GPU temperature, GPU power, and GPU VRAM metrics are reported over RDP
- GPU hotspot temperature and total board power are reported unsupported on this system
- Administrator elevation was not required for this validation
- The initial probe had an evaluation-order bug in expressions like `supported_result(IsSupported...(&value), value)`. The probe now performs the ADLX call first, stores the result, and evaluates the support flag afterward.
