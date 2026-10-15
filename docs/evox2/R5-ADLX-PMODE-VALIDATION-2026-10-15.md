# r5 ADLX / display / power / P-MODE validation — 2026-10-15

## Scope

This report records the 2026-10-15 environment-instrumentation work performed on:

- branch: `investigation/r5-adlx-gpu-monitor-20261015`
- pre-report branch head: `697c3ac87be94d661ea304fd5563ed88921bf6a0`
- target runtime: Windows 11 on GMKtec Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S
- benchmark binary: llama.cpp b11560, executable commit `f8d24494f`
- model: `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`
- 64k real-input benchmark: `pp 61777`, context 65536, batch 2048, ubatch 1024, threads 4, GPU layers 999, CPU MoE 0, KV f16/f16, FA auto
- input SHA-256: `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`

The goal was not to optimize inference itself. The goal was to make future performance comparisons explainable after the fact by recording GPU telemetry, display/session state, power state and P-MODE.

## Tooling added and validated

The investigation branch now contains:

- `tools/evox2/adlx-gpu-monitor/`: native ADLX GPU telemetry helper
- automatic benchmark-side ADLX launch for `Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1`
- `gpu-metrics.csv`, ADLX stdout/stderr and sample counts per run
- target-PID lifetime tracking so the monitor exits cleanly when llama exits
- fail-open behavior: ADLX failure does not abort the benchmark
- start display snapshot in `conditions.json`
- finish display snapshot in `result.json`
- PnP-based display detection that works over RDP

Relevant implementation commits on this branch before this report:

- `a2ebfe8190317125ef29b6fb69e0078ab6d33c3f` — stop ADLX monitor with target process
- `8f0fc4b69963e2844f5b9770bbfbffd0ead52c58` — automatic ADLX benchmark logging
- `095b5f65c6ba38d005bd508fda32a68230f30656` — automatic ADLX logging documentation
- `e355f601c82f53997c73bcfa53daaf75bc93102c` — surface ADLX telemetry status
- `7a057f35d3856ea01158a2c8185b3aee0f0df86a` — retain ADLX exit code and final display state
- `697c3ac87be94d661ea304fd5563ed88921bf6a0` — format rejected GPU counter warning

## Display-state validation

The first WMI monitor probe was not reliable under RDP, so display detection was changed to present PnP monitors plus parent-device classification.

Observed states:

- RDP only / physical display switched away:
  - present monitors: 1
  - physical candidates: 0
  - remote-like monitors: 1
  - remote parent: `SWD\\RemoteDisplayEnum\\RdpIdd_IndirectDisplay...`
- physical display selected for Evo-X2 while RDP remained connected:
  - present monitors: 2
  - physical candidates: 1
  - remote-like monitors: 1
  - physical monitor: `Generic Monitor (27M2N3500N)`
  - physical parent: Radeon PCI device
- switching the external display selector away from Evo-X2 returned the PnP snapshot to physical=0 / remote=1.

Conclusion: the PnP probe reflects the actual current display routing rather than stale historical monitor records.

## ADLX automatic logging validation

### llama-cli

A same-condition 64k MTP OFF/ON run with automatic ADLX enabled reproduced the fast state:

| mode | PP tok/s | TG tok/s |
|---|---:|---:|
| MTP OFF | 356.13 | 26.13 |
| MTP ON | 329.01 | 29.31 |

ADLX logging completed normally and did not visibly perturb the result.

### llama-bench

Automatic ADLX logging was also validated with llama-bench:

- benchmark status OK
- benchmark exit code 0
- ADLX requested/started: true/true
- ADLX exit code: 0
- 106 ADLX samples in the first validation run
- all ADLX result codes were 0
- expected supported metrics were populated
- hotspot / total-board-power remained blank because the device/API does not expose them
- target PID exit was detected and the logger stopped cleanly
- start and finish display state both showed RDP-only for that run

This validated the common integration path for both llama-cli and llama-bench.

## ADLX overhead ABBA

Raw archive:

- `20261015-143840-494-bench-vulkan-b11560-ctx65536-05124e04061a.zip`

The four runs used the same ConditionId `05124e04061a`, executable/build identity, input SHA, pp token count and RDP-only display state.

Sequence:

| run | ADLX | PP tok/s | ADLX samples |
|---|---|---:|---:|
| A1 | ON | 357.734690 | 105 |
| B1 | OFF | 356.157140 | 0 |
| B2 | OFF | 356.082454 | 0 |
| A2 | ON | 356.769839 | 105 |

Averages:

- ADLX ON: **357.252265 tok/s**
- ADLX OFF: **356.119797 tok/s**
- ON minus OFF: **+1.132468 tok/s**
- relative difference: **+0.318%**

Conclusion: with the current 2000 ms sampling interval there is no evidence that ADLX reduces 64k prompt-processing performance. The observed difference is inside the preselected ±0.5% negligible-overhead band and is in the opposite direction from an overhead hypothesis.

ADLX therefore remains enabled by default; `-NoAdlxMonitor` is retained for explicit controls.

## Windows power-state snapshot

A read-only power snapshot was taken in Performance, Quiet and Balanced P-MODE states. The captured Windows-side data were identical between P-MODEs, including:

- `powercfg /getactivescheme`
- `powercfg /qh`
- `HKLM\\SYSTEM\\CurrentControlSet\\Control\\Power`
- `AmdPPM` registry state
- CPU metadata
- relevant PnP devices and services

The active Windows power scheme remained:

```text
8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)
```

Current AC timeout state:

- display-off timeout: 0 seconds / disabled
- sleep timeout: 0 seconds / disabled
- hibernate timeout: 0 seconds / disabled
- fast startup: disabled by current system policy

Available sleep-state report still lists S0 Low Power Idle and hibernation as platform capabilities. The observation above means the AC automatic timers are disabled; it does not mean the platform capabilities have been removed.

Conclusion: Evo-X2 P-MODE is not represented by the active Windows `powercfg` scheme on this machine.

## P-MODE performance effect

Raw archive:

- `20261015-153132-433-bench-vulkan-b11560-ctx65536-05124e04061a.zip`

The user changed only the physical Evo-X2 P-MODE control between runs. Sequence:

```text
Performance -> Quiet -> Balanced -> Performance
```

Results:

| P-MODE | PP tok/s | vs first Performance | high-load GPU clock* | high-load GPU power* |
|---|---:|---:|---:|---:|
| Performance #1 | 357.263699 | baseline | 2878.9 MHz | 114.0 W |
| Quiet | 298.213165 | -16.53% | 2151.4 MHz | 53.5 W |
| Balanced | 339.164725 | -5.07% | 2621.7 MHz | 84.8 W |
| Performance #2 | 356.978330 | -0.08% | 2872.2 MHz | 115.3 W |

\* High-load averages use ADLX samples with GPU usage >= 95%.

The two Performance runs reproduced within about 0.08%, while Quiet and Balanced formed clearly separate clock/power/performance states.

### Relation to the earlier unexplained slow state

The previously observed b11560 64k MTP-OFF slow-state result was approximately 339 tok/s. The explicit Balanced run above is 339.164725 tok/s and has a distinct ~2.62 GHz / ~85 W high-load signature.

This is strong evidence that the earlier slow state **may have been Balanced P-MODE**, especially because the machine was explicitly re-selected to Performance on the morning of 2026-10-15 before fast ~357 tok/s measurements resumed.

It is not retroactive proof: P-MODE was not logged in the older run, so historical attribution remains a hypothesis.

## Direct P-MODE read via ACPI WMI

The machine exposes:

```text
ACPI\\PNP0C14\\IP3POWERSWITCH
ACPI\\PNP0C14\\IP3WMIEVENT
```

The method GUID:

```text
99D89064-8D50-42BB-BEA9-155B2E5D0FCD
```

can be opened with `WmiOpenBlock` under an elevated PowerShell process.

Reading method ID 2 on instance:

```text
ACPI\\PNP0C14\\IP3POWERSWITCH_0
```

returned, as verified while observing the physical OSD:

| raw UInt32 | physical mode |
|---:|---|
| 0 | Balanced |
| 1 | Performance |
| 2 | Quiet |

Example Performance read:

```text
WmiOpenBlockResult : 0
WmiExecuteResult   : 0
OutputSize         : 4
OutputHex          : 01 00 00 00
RawUInt32          : 1
```

Normal, non-elevated PowerShell receives `WmiOpenBlockResult = 5` (access denied), so method 2 is not directly usable from the normal benchmark process without an elevated helper.

The physical P-MODE button was also tested after switching the external display selector away from Evo-X2. An elevated re-read changed from Performance raw 1 to Quiet raw 2. Therefore the button is functional even when the physical display is not routed to Evo-X2.

## Normal-user P-MODE event tracking

Normal-user PowerShell can subscribe to:

```sql
SELECT * FROM IP3_WMIEvent
```

in `root\\WMI`.

Observed event payload:

```text
InstanceName = ACPI\\PNP0C14\\IP3WMIEVENT_0
EventDetail  = 8-byte UInt8 array
```

Three consecutive physical P-MODE presses produced:

| EventDetail hex | resulting mode |
|---|---|
| `01 13 81 00 00 00 00 00` | Performance |
| `01 11 81 00 00 00 00 00` | Quiet |
| `01 12 81 00 00 00 00 00` | Balanced |

Therefore:

- `EventDetail[1] == 0x11` -> Quiet
- `EventDetail[1] == 0x12` -> Balanced
- `EventDetail[1] == 0x13` -> Performance

The OEM OSD binary also contains the corresponding 17/18/19 branches and a 20/Super branch. Super mode was not exercised on this Evo-X2 and must not be treated as validated here.

`IP3_WMIEvent` is transient. `Get-CimInstance -ClassName IP3_WMIEvent` returns no retained current instance even when elevated; a watcher only receives new events as they occur.

## ImagesShow OEM utility analysis

Installed application:

- product: `ImagesShow version 2.4`
- install path: `C:\\Program Files\\ImagesShow\\`
- OSD process: `OsdShowV2.4.exe`
- service: `ImagesShowService`
- service executable: `WindowsService.exe`
- service account: `LocalSystem`
- service start mode: automatic

Validated file identities:

- `OsdShowV2.4.exe` SHA-256: `D6843CC35056A1CB363D163A23E08B79D355190882D7848446B3A7FC80600155`
- `WindowsService.exe` SHA-256: `1F70F5CD66A7E6494998EBD2A4F80B3D30ADC36B58A6BC5933DA7324039CFD59`
- both files have valid Shanghai Sixunited Intelligent Technology Co., Ltd. signatures

Static inspection shows:

- the OSD is a Python 3.8 / PyQt5 application packaged with PyInstaller
- it subscribes to `root\\WMI` `IP3_WMIEvent`
- its P-MODE event branches match the experimentally observed 17/18/19 mapping
- `WindowsService.exe` contains user-session launch APIs such as `WTSGetActiveConsoleSessionId` / `CreateProcessAsUser` and appears to be primarily an OSD launcher rather than the ACPI P-MODE implementation itself
- the package contains optional Windows power-plan handling, but on this Evo-X2 the active `powercfg` scheme did not change with P-MODE

The hardware/ACPI event path is therefore independent of merely having an OSD window visible.

### Service-stop expectation

Based on the architecture above, stopping `ImagesShowService` is expected to stop automatic OSD launch/relaunch, **not to disable the physical P-MODE button or the firmware/ACPI mode transition itself**.

This exact service-stopped condition has not yet been experimentally validated and should remain labeled as an expectation until tested.

Also note that stopping only the service may leave an already-running `OsdShowV2.4.exe` process alive. A clean validation would stop the service, terminate existing OSD processes, press P-MODE, then verify the resulting mode with elevated WMI method 2 and/or a direct normal-user `IP3_WMIEvent` watcher.

For benchmark reproducibility, keeping ImagesShow running is currently safer than disabling it: the OSD provides immediate visible feedback if the hardware P-MODE button is pressed accidentally, while the button itself is not expected to be disabled by stopping the service.

## Measurement policy after this investigation

Until automatic P-MODE state logging is added:

1. keep P-MODE fixed at **Performance** for performance comparisons;
2. do not change P-MODE during a benchmark matrix;
3. keep ADLX enabled at 2000 ms unless explicitly testing monitor overhead;
4. preserve start/finish display metadata;
5. treat ~339 tok/s b11560 64k results as potentially Balanced-state contamination unless the run has independent P-MODE evidence;
6. do not rewrite older results as definitively Balanced without direct evidence.

Future logging should distinguish:

- a direct elevated method-2 reading of current mode;
- a normal-user event-derived last mode;
- any manually supplied label;
- any ADLX clock/power inference.

Direct observations and inferred mode must not be conflated.
