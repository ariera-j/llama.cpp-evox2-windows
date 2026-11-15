# Evo-X2 P-MODE probe

This helper records the current GMKtec Evo-X2 / Sixunited AXB35 P-MODE without changing it.

The authoritative read uses the ACPI-WMI block:

- GUID: `99D89064-8D50-42BB-BEA9-155B2E5D0FCD`
- instance: `ACPI\PNP0C14\IP3POWERSWITCH_0`
- method ID: `2` (read-only current-mode query)

Verified mapping on the target Evo-X2:

- `0` = Balanced
- `1` = Performance
- `2` = Quiet

Normal user processes cannot open this WMI execute block on the target machine. The benchmark wrappers therefore support a one-time highest-privilege scheduled-task setup.

## One-time setup

Open Windows PowerShell as Administrator in the repository and run:

```powershell
.\tools\evox2\pmode\Install-Evox2PModeProbeTask.ps1
```

The installer registers `\Evox2\PModeProbe` for the current user. It has no trigger and runs only when a benchmark requests a fresh state. The task writes:

```text
%ProgramData%\Evox2\PMode\state.json
```

The benchmark remains a normal, non-elevated process.

## Manual read

Elevated PowerShell can read directly:

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
Get-Evox2PModeMetadata -DirectOnly | Format-List
```

Normal PowerShell can use the registered task fallback:

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
Get-Evox2PModeMetadata | Format-List
```

This code never calls WMI method ID 1 and never changes the hardware mode.

## Benchmark behavior

`Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1` probe P-MODE immediately before and after the measured child process. The expected mode is Performance. Probe failures, non-Performance modes, start/finish changes, and confident ADLX power/P-MODE contradictions are warnings only and do not abort a run.

Use `-NoPModeProbe` only for an explicit control run or while setting up the helper.

## Removal

Run elevated:

```powershell
.\tools\evox2\pmode\Uninstall-Evox2PModeProbeTask.ps1
```
