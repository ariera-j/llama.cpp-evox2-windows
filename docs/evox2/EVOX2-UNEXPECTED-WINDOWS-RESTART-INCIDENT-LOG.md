# EVO-X2: unexplained Windows restarts during LLM benchmarking

**Last updated:** 2026-10-22 JST  
**Host:** GMKtec EVO-X2 / Ryzen AI Max+ 395 / Windows 11 / UMA VRAM ordinarily configured at 96 GB

This is the **single ongoing incident ledger** for sudden *OS-level* restarts, resets or apparent hard power-cycle events during llama.cpp or local LLM **performance testing**. Preserve exact measured facts and provenance; do not treat an unexplained reset as an established model, driver, power-supply, firmware or application bug.

## Incident register (confirmed)

| ID | Date/time (JST) | Workload | Impact / evidence | Recheck | Cause |
| --- | --- | --- | --- | --- | --- |
| RST-20260917 | **2026-09-17 ~19:07** | Unsloth PLE16, Vulkan, long-context/96 GB UMA evaluation | Inference cut off; Kernel-Power 41, BugcheckCode=0, no contemporary BugCheck 1001/normal-shutdown 1074, dump not found | **Four subsequent same-condition runs completed** | Unknown |
| RST-20261006 | **2026-10-06 ~00:54:42–00:54:52** | Qwen3.5-2B, llama.cpp b11372/r4 Vulkan; 1M YaRN×4 prefill | At ~694,272/943,645 prompt tokens the machine abruptly restarted; Kernel-Power 41, BugcheckCode=0, reboot confirmed | **Same 1M test rerun completed** | Unknown |
| RST-20261022-PM | **2026-10-22 ~17:46** | Qwen3.8-Flash-Next Unsloth UD-IQ3_XXS PLE16 + Unsloth Q8_0 MTP, 128k, Vulkan `b11588` | 128k ABBA's third run (seventh overall) stopped mid-prefill; Kernel-Power 41, BugcheckCode=0; EventLog 6008; remaining fourth run not started | **128k ABBA four-run recheck underway at the time of writing** | Unknown |

**Provenance:** September and October 6 details were recovered from project conversation records and uploaded event/resource-log analyses; October 22 evening details come from the current project conversation, the run ZIP and System event CSV/XML inspection described below. Raw conversation attachments are **not** automatically versioned in this repository.

**Evidence standard:** Rows above document observed unexpected OS restart and the associated run. No event above has a confirmed low-level root cause. `Kernel-Power 41` itself only reports an unclean prior termination.

## RST-20260917 — 2026-09-17 evening

- **Approximate run window:** start **19:03:51**; last resource-log sample **19:07:00.920**; `Kernel-Power 41` **19:07:10** (boot/event timestamp, not necessarily exact fault moment).
- **Workload:** Windows/Vulkan, Unsloth PLE16-converted Qwen3.8-Flash-Next, 96 GB UMA setting, while investigating long-context performance. r2-era optimization work; the exact run parameters/build SHA associated with this *particular failed process* have not been independently reverified.
- **Observable symptom:** RDP returned to the Windows login screen and the active llama.cpp process was gone.
- **Event findings:** `BugcheckCode=0`, `PowerButtonTimestamp=0`, `WHEABootErrorCount=0`. Contemporary BugCheck 1001, planned User32 1074 and a fresh MiniDump/MEMORY.DMP were not found.
- **Last measured memory:** system commit **94.55 / 127.65 GiB**, free RAM **22.67 GiB**, GPU adapter local **83.50 GiB**; not an obvious memory-exhaustion snapshot. No directly incriminating heat or power anomaly was established.
- **Windows Update:** Defender security-intelligence update KB2267602 succeeded around **18:51:21–18:51:26**; a planned reboot or update-caused restart was **not** established.
- **Recheck:** user reported **four same-condition successful repeats**, with no recurrence during those reruns.
- **Decision:** record as an isolated unexplained OS reset under measurement load, not proof of a reproducible llama.cpp/driver defect.
- **Source:** project chat on 2026-09-17; previously analyzed `原因推測 Windowsクラッシュ.md` and corresponding resource/event reports (private attachments, not versioned here).

## RST-20261006 — 2026-10-06 ~00:54 JST

- **Workload:** Qwen3.5-2B long-context generation, llama.cpp **b11372/r4**, **Vulkan**, **n_ctx=1,048,576**, **YaRN ×4**, **KV q8_0/q8_0**; source prompt **943,645 tokens**. The model's exact target GGUF quantization is not confirmed in the retrieved history.
- **Run:** started approximately **00:22:23**, interrupted around **00:54:42–00:54:44** in prefill. Last normal progress: **694,272 cached/prompt tokens (~73.6%)**, contemporary rolling PP about **358.18 tok/s**.
- **OS evidence:** previous restart inferred from RDP login screen and ended process; `LastBootUpTime` approximately **00:54:49**; `Kernel-Power 41` around **00:54:52**, `EventLog 6008`, no planned restart `1074`, `BugcheckCode=0`, no newly identified dump. Timestamp precision varies by source/event.
- **Telemetry near end:** RAM usage/free approximately **6.62 / 31.65 GiB** as reported by the run's monitor, commit **23.47 / 127.65 GiB**, llama-cli private bytes **14.70 GiB**, GPU committed **~11.62 GiB**. These figures are from the recovered chat report; do not extrapolate them to 9/17 or 10/22.
- **Caveat:** a pinned-memory warning had appeared but was also observed in a previously successful 1M workload; no established causal link.
- **Recheck:** another attempt under the same 1M condition finished **943,645 prompt tokens, ExitCode=0, truncated=0**. This supports intermittency and **does not identify the initiating subsystem**.
- **Source:** project Qwen3.5-2B 1M experiment chat, 2026-10-06, and uploaded resource/event analyses.

## RST-20261022-PM — 2026-10-22 ~17:46 JST

- **Machine/test:** Vulkan `b11588`, integration-check binary `build-vulkan-r5-noop-rocmfpx`; 128k Qwen3.8-Flash-Next, **Unsloth UD-IQ3_XXS PLE16 target + Q8_0 draft**, MTP ON `DraftMax=2`; r5 QSA union, MTP-DENSE and MTP-NOOP enabled; input around **126,253 tokens**.
- **ABBA schedule:** 64k completed all four runs; 128k order **ROCmFP4, Unsloth, Unsloth, ROCmFP4**. 128k first two runs completed (PP **293.59** ROCmFP4 and **306.42** Unsloth tok/s); the **third 128k run was Unsloth**, the **seventh matrix run overall**; fourth was never started. The observed PP inversion is a separate benchmark-repeatability question, **not evidence of a reset cause**.
- **Interrupted run:** began about **17:40:33**; last monitoring record **17:46:07**. Prefill **94,208 tokens (~75%)**, rolling PP about **327.03 tok/s**, generation not yet reached; no normal llama-cli exit.
- **Last telemetry (not guaranteed to capture the triggering event):** GPU temperature **84 °C**, core clock **2,869 MHz**, power **114 W**, utilization **99%**, GPU local allocation **88.48 GiB**, system commit **79.4%**. Over the incomplete run the GPU temperature peaked **89 °C**, power **123 W**, allocation **88.48 GiB**, free RAM bottomed **22.71 GiB**; a prior *successful* ROCmFP4 128k run allocated up to **98.91 GiB** GPU local. No convincing immediate thermal or exhaustion anomaly was observed in the 2-second sample history.
- **Events:** `Kernel-Power 41` recorded about **17:46:17**, `EventLog 6008` about **17:46:24**; no BugCheck 1001 or planned-restart User32 1074 in the filtered CSV. `6008` reported a different previous-shutdown time (17:42:21) inconsistent with resource samples continuing to 17:46; do **not** use this reported timestamp as the fault moment.
- **Event 41 XML values manually checked by user:**

  ```text
  BugcheckCode=0
  BugcheckParameter1..4=0x0
  SleepInProgress=0
  PowerButtonTimestamp=0
  BootAppStatus=0
  ConnectedStandbyInProgress=false
  BugcheckInfoFromEFI=false
  LongPowerButtonPressDetected=false
  WHEABootErrorCount=0
  ```

  This **does not** exclude GPU driver, Windows kernel, low-level firmware, voltage/power or transient hardware failure. No contemporaneous MiniDump result was furnished for this evening incident; record dump status as **unverified**, not 'none'.

- **Run artifacts in conversation:** `20261022-170625-072-qwen38-r5-noop-rocmfpx-mtp-64k128k-abba.zip`, `windows-restart-20261022.csv`, plus XML field output pasted in chat.
- **Recheck plan:** rerun **128k ABBA all four runs** for clean paired PP/TG comparisons. User had started this recheck when the incident ledger was requested. The actual result must be filled in when available.

## Events excluded from the unexplained-reboot count

- **2026-10-22 ~02:44 — ROCm FLASH_ATTN_EXT backend-test failure:** A broad backend test reached an unsupported DKQ=64/logit-softcap HIP kernel and invoked a `NO_DEVICE_CODE` trap; Windows reported **LiveKernelEvent 141**, `WATCHDOG-20261022-0244.dmp`, display/RDP became unusable and manual reboot followed. **Separate, comparatively well-correlated backend-test issue, not the unexplained benchmark restart above.** The exact kernel→OS failure chain remains unproven without dump analysis. See [R5-ROCM-QSA-REPEATABILITY-2026-10-22.md](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md#build-script-side-findings-during-this-investigation). **Do not routinely run the full FLASH_ATTN_EXT test sweep** on this configuration pending support-check fix.
- Earlier WATCHDOG/dump incidents or llama.cpp asserts/process-only failures are not counted here unless evidence ties them to a corresponding OS-level restart.
- **2026-10-10:** user recalled this as a possible earlier date, but a separate unexplained reboot on that date **was not supported by the retrieved conversation/repository evidence**. The documented October incident is **2026-10-06**. Keep 10/10 as unverified, not as a fourth confirmed event.

## Cross-incident observations / limits

1. All three verified unexplained restarts occurred during long or high-load local LLM **benchmark/inference** runs, but workloads/models/builds differ and there is **no established common root cause**.
2. `BugcheckCode=0`, lack of a dump, and absence of 1074 distinguish these incidents from a *documented normal reboot or recorded BSOD*; they **do not prove** the absence of GPU/driver/firmware/hardware faults.
3. At the last collected samples, none displayed an obvious system commit exhaustion or unequivocal thermal spike. This is only a telemetry observation, **not** a hardware health clearance.
4. At least the September and October 6 incidents did not reproduce on immediate retry. A successful subsequent run does not invalidate the prior abnormal reset.
5. Do not compare measured PP/TG or infer performance regressions from interrupted runs. Archive partial logs separately and remeasure complete matched pairs.

## Minimal record to append after any future event

- ID, Japan-local date/time and time source (last resource sample, reboot uptime, event timestamp).
- Exact binary/build SHA, backend, model+draft GGUFs, flags and environment, context/input tokens, test name and run number.
- Prompt progress at failure; whether the OS really rebooted versus only display/RDP or process crash.
- `Kernel-Power 41` XML `BugcheckCode`, `WHEABootErrorCount`, `PowerButtonTimestamp`; Event 6008/1074/1001; Windows Error Reporting/LiveKernelEvent and dump path if present.
- Last/peak telemetry: GPU clock, temperature, power, usage, local/shared allocation; RAM available and system commit; P-MODE state.
- Outcome of **same-condition** repeat and final classification: unexplained / diagnosed / pending.
- Source paths to run ZIP, CSV, Windows event exports and any GitHub diagnostics; avoid treating a user-supplied log as repository-versioned unless committed.

**Current policy (2026-10-22):** no deeper root-cause investigation unless the incident recurs frequently or develops a reliably reproducible trigger. Continue paired benchmarks with explicit notes about invalidated runs.
