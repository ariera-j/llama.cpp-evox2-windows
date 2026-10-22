# EVO-X2: unexplained Windows restarts during LLM benchmarking

**Last updated:** 2026-10-22 JST (22:50 RDP-only completion follow-up)  
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

- **Prior power-on / uptime (user recollection, not yet corroborated by boot metadata):** the EVO-X2 was powered off around **2026-10-20 daytime**, powered on **2026-10-20 evening**, and apparently left on continuously until the unexpected restart on **2026-10-22 ~17:46**. Exact power-on time and whether any intermediate OS restart occurred are **unverified**. This suggests roughly two days of wall-clock operation, **not** a proven exact continuous uptime. The user intended a separate, *deliberate* Windows restart on the night of 2026-10-22 to test whether low 128k/32k prefill VRAM clock would recover; that later restart must not be counted as another incident.
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

## 2026-10-22 evening: subsequent PP/VRAM-clock and power-cycle investigation

This is a **follow-up to RST-20261022-PM, not a fourth unexpected reset**. Data below are matched 32k Vulkan `b11588 / 1c3167fb6` tests: Agention ROCmFP4 PLE16 target + matching MTP draft, MTP ON, ~29,557 input tokens, 512 generated, temperature 0, QSA union/DENSE/NOOP enabled. Exit codes were 0; draft acceptance was 70.686%; P-MODE consistently Performance. Comparison input/output/model build hashes matched according to the run logs.

| Local run time | Prior action/session | PP tok/s | TG tok/s | Mean PP VRAM clock | Notes |
| --- | --- | ---: | ---: | ---: | --- |
| ~16:50 | Prior long-running Windows session, RDP | 398.65 | 36.60 | ~970 MHz | Reference fast state |
| ~20:32 | After ~17:46 unexpected OS restart, RDP | 376.88 | 35.95 | ~884 MHz | PP clock decayed over prefill |
| ~20:53 | **Normal Windows Restart-Computer**, RDP | 380.02 | 35.93 | ~895 MHz | Boot time 20:49:56; no substantive recovery |
| ~21:06 | **Normal shutdown → power on**, RDP | 376.23 | 36.14 | ~876 MHz | Still not recovered |
| ~21:48 | **AC cord removed, power button long-held while unplugged, then power and physical display connected**, local Console session | **393.12** | **36.47** | **~937 MHz** | Partial recovery; still ~1.4% below reference |

The latest run is recorded as `20261022-214850-765-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip`, `ExecutableCommit=1c3167fb6`, `OutputFingerprintSha256=21d9ce4059...`, `PModeAtStart/Finish=Performance`, `DisplayEnvironmentAtFinish.SessionName=Console`, one physical display `E2K60V2`, and ADLX `remote_session=0`. Its high-utilization prefill section (35 samples, usage >=95%) averaged **937.31 MHz VRAM**, **2864.86 MHz GPU core**, **112.63 W GPU**, **68.94°C GPU temperature**, **99.03% GPU utilization**. VRAM-clock progression across the prefill was approximately **968 → 939 → 915 MHz** in consecutive thirds; generation-phase VRAM returned near 1000 MHz.

**Interpretation:** The combination of AC removal/button hold **and** a physical-display/Console-session change coincided with a ~4.49% PP recovery relative to the preceding normal-shutdown run. Normal Restart-Computer and normal shutdown→power-on had not restored the prior rate. This is a strong **lead for power-control reset state or display/session-related GPU behavior**, but the two interventions were performed together and **cannot be causally separated**. It does *not* prove that an EC reset occurred, that a firmware protection state triggered the original OS reset, or that the VRAM-clock change is a direct causal mechanism rather than a correlated control variable.

Recommended low-cost next isolation: with AC and physical display **unchanged**, enter **RDP and repeat one identical 32k run**. Compare against the Console run; then, optionally, repeat under RDP with the physical display disconnected. Record `DisplayEnvironmentAtFinish` and ADLX `remote_session` for each. Do not change BIOS, P-MODE or driver during this isolation. User attempted to enter BIOS via Esc but Windows booted normally; **no BIOS information was obtained** during this step.

**128k rerun status:** The complete 128k ABBA recheck on 2026-10-22 evening finished four of four. ROCmFP4 mean PP **276.78**, Unsloth mean PP **276.52** tok/s; both substantially lower than the first two runs before the reboot. High-load VRAM clocks also differed between sessions. Do not treat the original 128k PP inversion as a stable target-model property.

### Follow-up: RDP session with physical display still attached (2026-10-22 21:57)

The next matched 32k ROCmFP4+MTP run was started through **RDP** while leaving the physical `E2K60V2` display plugged in, **without** a further power cycle. Artifact: `20261022-215727-143-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip`.

- Build `b11588 / 1c3167fb6`; 29,557 prompt tokens; 512 generated; temp=0; OutputFingerprintSha256 `21d9ce4059613c9ee2920b3d035d5a55dd5bc85c76d9e8d59808489c88432e3b`, same as earlier matched runs; MTP acceptance `70.686%`.
- **PP 397.31 tok/s, TG 36.52 tok/s**, exit 0, P-MODE Performance throughout, no monitoring warnings.
- ADLX `remote_session=1` confirms RDP for the monitoring process; both RDP indirect and physically attached `E2K60V2` displays are enumerated. Caution: `DisplayEnvironmentAtFinish.SessionName` reported `Console` despite the ADLX remote-session flag; these probes do not necessarily describe the same process/session and should not be conflated.
- Prefill high-utilization section (35 2-second samples, 21:58:18–21:59:26, GPU usage 97–100%): mean GPU VRAM clock **957.49 MHz**, GPU core **2858.31 MHz**, GPU power **114.69 W**, temperature **70.60°C**, usage **99.0%**. VRAM clock across three prefill segments averaged **969.7 → 953.8 → 948.3 MHz**.
- Compared with preceding local-Console 21:48 run (PP 393.12, TG 36.47, mean PP VRAM ~937 MHz), RDP run is **+1.07% PP**. Compared with ~16:50 fast baseline (PP 398.65), it is **-0.34% PP**. Compared with the low-clock ~21:06 normal-power-cycle run (PP 376.23), it is **+5.60% PP**.
- **Inference:** near-baseline prefill speed is retained through RDP while a physical monitor remains attached. Therefore **RDP alone is unlikely to explain the ~5% degradation**. The difference between 21:48 and 21:57 is one run each and **does not prove warm-up**; GPU/load state and noise can also affect it. The AC-unplug/button-hold and physical-monitor attachment occurred simultaneously before 21:48, so these two interventions remain confounded.
- **Next isolating check (optional):** with AC unchanged, continue RDP then disconnect only the physical monitor (or change display switching) and rerun the same 32k model/MTP case; retain ADLX/display metadata. This is more diagnostic than another restart or BIOS modification, but avoid interrupting any ongoing workload.

## HNG-20261022-PM — apparent whole-system hang during display-detached RDP benchmark (time not yet established)

### Follow-up: raw partial inference and Windows events (22:06–22:44 JST)

Artifacts received in conversation:
- `20261022-220636-149-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip` — incomplete per-run folder, contains `conditions.json`, `stderr.log`, `resources.csv`, `gpu-metrics.csv`; **no result/summary/normal-exit record**.
- `貼り付けたテキスト（1）(20261022-134824).txt` — copied `Get-WinEvent` System/Application output after manual recovery. Repeated WER records refer to historical crashes and are **not new dump timestamps**.

**Run identity:** started `2026-10-22T22:06:36.985+09:00`, llama.cpp `b11588 (1c3167fb6)`, executable SHA-256 `a816c4e8bf68e923d662f2e470f06b892bd9d8c6c2b0305cc2d26ad597f0c1d5`, Vulkan ROCmFP4-FAST v2 PLE16 + Agention ROCmFP4 MTP, `n_ctx=32768`, prompt `29557`, `-n 512`, temp=0, `GGML_VK_QSA_UNION=1`, r5 DENSE/NOOP, `PModeAtStart=Performance`. Physical monitor **absent**, PnP probe saw **one RDP-indirect monitor only** (`PresentPhysicalCandidateCount=0`); ADLX `remote_session=1`.

**Progress and last samples:** `stderr.log` last records at about **22:07:27** include `prompt processing, n_tokens=4096, progress=0.14`, rolling **659.03 tok/s** for the early 4k (NOT a full-context PP result), followed by a `cached n_tokens=4096` line. Last ADLX sample timestamp **22:07:27.259**: usage **99%**, GPU core **2804 MHz**, VRAM clock **1000 MHz**, GPU temperature **64 °C**, GPU power **126 W**, ADLX VRAM used **95729 MB**. Latest valid `resources.csv` sample **22:07:26.555**: system commit **83.0% of 127.647 GiB**, physical RAM free **22.44 GiB**, target GPU local **94.148 GiB**, GPU shared **1.286 GiB**, adapter local **94.772 GiB**. Previous successful 32k runs had comparable GPU model/KV allocations, so these numbers **do not establish OOM**; they do show a substantial GPU-memory footprint at failure. `resources.csv` ends with an incomplete/NUL-filled row; monitor tail and inference log were not closed normally. No obvious preceding GPU thermal or VRAM-clock-downshift symptom was sampled. There is **no measured full PP/TG for this interrupted run**.

**Manual recovery:** Windows `Kernel-Power 41` logged at **22:39:47** and `EventLog 6008` at **22:39:54** after the forced restart. Event 6008's reported *previous shutdown* time **21:47:22** is incompatible with 22:07 monitoring data and **must not be used as a reliable hang timestamp**. Actual hang onset is bracketed near the final 22:07 samples, not exactly timestamped by the later boot events. User checked current `LiveKernelReports` and `Minidump` and found **no new dump**.

**Important WER interpretation:** `Application / Windows Error Reporting 1001` entries at about **22:40:02–22:44:01** reference existing **`WATCHDOG-20261022-0244.dmp`** (LiveKernelEvent 141) and **`WATCHDOG-20261010-1011.dmp`** (also 141), plus older September/August dumps. These timestamps are WER reporting/requeue times; the `*.dmp` names identify **older original incidents**. This copied event output provides **no fresh 22:07 LiveKernelEvent 141 or new dump attributable to this hang**. An **October 10 historical GPU WATCHDOG 141 report is now evidenced**, but whether a corresponding independent *OS spontaneous reboot* occurred then remains unconfirmed; do not reclassify the separate 2026-10-06 reboot. `crashpad_log` for `setup.exe/EdgeInstallerError` at 22:44 is unrelated without further evidence.

**Status / safe policy:** Unknown root cause. Display detachment shortly before workload is temporal association only. Inference also used ~95 GiB-class local GPU memory with high GPU utilization, so avoid asserting a pure display-path cause. A same-condition retest from RDP without a physical monitor was planned by the user after recovery, but **its outcome is pending**. Because the prior full-machine hang required manual recovery, do **not** repeatedly hot-unplug/replug displays under inference load. If an identical 32k/no-display workload hangs again, stop the stress test and investigate before extended 128k/256k runs.

**Classification: suspected system-wide hang requiring manual restart; NOT an observed spontaneous restart and NOT part of the three confirmed unexplained reboot events above.**

- **Time:** 2026-10-22 JST, **after the 21:57 successful matched RDP run**. Exact hang and manual reboot timestamps are **not yet confirmed**; do not infer them from this entry.
- **Workload/environment:** subsequent 32k matched ROCmFP4 + MTP Vulkan benchmark (`build-vulkan-r5-noop-rocmfpx`, same workflow as earlier matched cases), controlled through RDP, **physical monitor deliberately detached** to isolate display-connection effects. The particular interrupted run's full conditions, PID, token progress and binary hash have **not yet been independently retrieved**.
- **Symptom:** during inference/benchmarking, RDP connection failed; SSH and ping were also unreachable. Reconnecting a physical display produced no visible response. **Power-button indicator remained lit.** User intended to restart via physical power button. Windows **did not visibly auto-reboot** before that action.
- **Dump check after recovery:** user checked `C:\\Windows\\LiveKernelReports` and `C:\\Windows\\Minidump`; **no new DMP/Minidump** was found. This does **not** rule out a GPU hang, driver failure or unrecorded OS stall; it establishes only that these searched locations contained no captured dump.
- **Windows System/Application events / WER Reliability Monitor:** **pending inspection**. In particular, check whether WER logged `LiveKernelEvent 141/117` even without a dump; check Kernel-Power 41/EventLog 6008 after manual power-off separately from the initiating failure. Such 41/6008 events would be *consequences of the manual recovery* and cannot by themselves identify the root cause.
- **Comparison:** symptom resembles 2026-10-22 02:44 ROCm `FLASH_ATTN_EXT` backend-test GPU/display hang (RDP/display unresponsive), **but no evidence currently establishes the same low-level trigger**; this time the active workload was **Vulkan** and there is **no DMP**.
- **Confounding:** physical monitor disconnection occurred just before the incident, but that timing does **not establish causation**. Do not actively reproduce by repeatedly disconnecting the monitor under GPU load; prioritize preserving hardware stability and collecting event evidence.
- **Disposition:** pending event logs, no causal claim. Count separately as a fourth **incident** only when including hangs; keep the **unexplained spontaneous reboot count at three**.

### 22:50 RDP-only retest after manual recovery — completed, PP low again

The user's next unchanged **32k ROCmFP4 PLE16 target + matching MTP** test, with **physical monitor disconnected since the manual reboot** and **RDP active**, finished successfully. Source archive: `20261022-225007-431-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip`.

- Started **22:50:08**, finished **22:52:29 JST**; ExitCode **0**, `Status=OK`. `b11588 / 1c3167fb6`, runtime verified, model/input/target/draft and benchmark flags unchanged; prompt **29,557 tokens**, generated **512**.
- **PP 376.15 tok/s; TG 36.32 tok/s**; draft acceptance **70.686%**, accepted **299/423**. Output fingerprint `21d9ce4059613c9ee2920b3d035d5a55dd5bc85c76d9e8d59808489c88432e3b` matches the earlier comparable 21:57 run.
- `DisplayEnvironmentAtFinish.PresentPhysicalCandidateCount=0`; one **RDP indirect monitor only**, `SessionName=RDP-Tcp#0`; ADLX `remote_session=1`. P-MODE **Performance** at start and finish, no state change, ADLX finished cleanly (**70** samples), resource monitor **69** samples.
- Prefill sampling: high GPU utilization >=97%, excluding TG, **36** ADLX observations. VRAM **~875 MHz**, GPU core **~2,870 MHz**, GPU power **~108.3 W**, temperature **~67°C** average (max **73°C** among sampled prefill points); VRAM clock by chronological thirds ~**920 → 864 → 841 MHz**. In generation, VRAM clock returned toward ~1000 MHz.
- **Comparison to 21:57 RDP WITH physical monitor:** PP **397.31 → 376.15 tok/s** (**-5.32%**); TG **36.52 → 36.32** (**-0.55%**); PP VRAM clock **~958 → ~875 MHz** (**-8.7%**); GPU core **~2,858 → ~2,870 MHz**; PP GPU power **~114.7 → ~108.3 W**. P-MODE, output and acceptance were stable.
- **Comparison to 21:06 RDP without physical monitor** (before AC disconnect): PP **376.23 vs 376.15 tok/s**, nearly identical, and prefilling VRAM ~**877 vs 875 MHz**.

**Interpretation limit:** This is a strong *association* between headless/RDP-only display topology and a lower sustained VRAM clock/PP rate on this specific session/build. However a **system-wide hang and manual reboot** also intervened between the monitored-connected 21:57 and monitor-disconnected 22:50 runs; the physical monitor was unplugged shortly before the preceding failed run. Do **not** claim an isolated randomized display-connect causal result, or that monitor hot-unplugging caused the hang. Normal completion of the next run argues against inevitable headless-mode failure, but does not establish stability over many repetitions.

**Operational choice:** avoid further hot unplug/replug during GPU workloads. If stable high-speed benchmarking is the priority, consider using a fixed physical monitor connection and labeling display topology in all result sets; defer further A/B isolation and BIOS/firmware changes until the system is stable. Always record ADLX high-load VRAM clocks alongside PP/TG.

### 23:23 AC-unplug + power-button hold + ten-minute rest, **no physical display**: PP remained slow

To isolate the AC/power-button intervention from monitor attachment, the user **shut down, unplugged AC, held the power button, left the machine without power for about ten minutes, then powered on with no physical display connected**. A matched 32k ROCmFP4+MTP run was completed through RDP: `20261022-232334-057-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip`.

- Run **23:23:35–23:25:53 JST**, `Status=OK`, ExitCode 0. Same `b11588 / 1c3167fb6` executable and conditions, **29,557 prompt/512 generation tokens**, MTP acceptance **70.686%** (299/423), identical output fingerprint **`21d9ce4059613c9ee2920b3d035d5a55dd5bc85c76d9e8d59808489c88432e3b`**.
- PP **377.11 tok/s**, TG **36.07 tok/s**; low-speed state sustained vs 22:50 headless PP **376.15** and 21:57 physically connected PP **397.31**.
- ADLX PP high-utilization interval (~**37** samples): mean VRAM clock **877.38 MHz**, core **2873.19 MHz**, GPU power **107.89 W**, GPU temperature **65.73°C**, usage **99.27%**. VRAM clock by three chronological thirds **931 → 868 → 836 MHz**. `AdlxMonitorExitCode=0` and resource-monitor results present.
- `PModeAtStart/Finish=Performance` and unchanged. `DisplayEnvironmentAtFinish`: RDP only; one remote-like monitor, **zero physical candidates**; ADLX `remote_session=1`.
- **Finding:** AC removal, long power-button hold, ten minutes unplugged, and headless reboot were **insufficient to restore the high PP/VRAM-clock state**. This does *not* prove no EC reset occurred or prove a protection state exists. A comparable pre-17:46 high-speed run had also been headless, so **headless state alone cannot fully explain all observations**.
- **Next planned isolating intervention:** normal shutdown, **leave AC plugged in**, attach physical display **while powered off**, boot, then run the *same* 32k Vulkan benchmark. Avoid hot-plugging displays while under GPU load after the recent whole-system hang. Do not change BIOS, driver or P-MODE during comparison.

### 23:34 reconnect physical display while shut down, local login, then RDP: PP recovered

**Intervention:** after the still-slow 23:23 headless run, the user **shut Windows down normally without unplugging AC**, **attached the physical monitor while powered off**, powered on, **logged in once locally using that display**, then connected through **RDP** and executed the same benchmark. Matched full-run archive: `20261022-233435-245-cli-vulkan-b11588-ctx32768-587a0dcffad5.zip`.

- **Result:** 23:34:36–23:36:51 JST, status OK, ExitCode 0; PP **393.98 tok/s**, TG **36.50 tok/s**, MTP acceptance **70.686%** (299/423), identical output SHA-256 fingerprint `21d9ce4059613c9ee2920b3d035d5a55dd5bc85c76d9e8d59808489c88432e3b`, prompt **29,557 tokens** and generation **512 tokens**. Runtime same `b11588/1c3167fb6`, executable SHA-256 `a816c4e8bf68e923d662f2e470f06b892bd9d8c6c2b0305cc2d26ad597f0c1d5`.
- **P-MODE:** Performance at start and finish. `DisplayEnvironmentAtFinish` enumerated both an RDP indirect display and physical **E2K60V2** (`PresentPhysicalCandidateCount=1`), though `SessionName=Console` despite ADLX `remote_session=1`; these probes target different processes and should not override the user's RDP description.
- **High-GPU-utilization prefill window:** approximately **35** ADLX samples, mean VRAM clock **~942 MHz**, GPU core **~2861 MHz**, GPU power **~114 W**, temperature **~71°C**. VRAM clock across thirds approximately **962 → 941 → 925 MHz**. Sampling window approximated from run start/finish, prompt/gen durations and excluding post-run time.
- **Matched change from prior 23:23 headless after AC-button-10min experiment:** PP **377.11 → 393.98 tok/s (+4.47%)**; TG **36.07 → 36.50**; PP VRAM **~877 → ~942 MHz**; high-load power **~108 → ~114 W**. The earlier 21:57 display-attached RDP run had **397.31 tok/s** and **~958 MHz** VRAM, so the current recovery is close but not identical.
- **Key qualifier:** The user observed **pre-17:46 high PP while headless**, so physical monitor *presence* is not necessary in every machine state. This is repeated evidence of an association between *monitor attachment / boot and local login sequence* and return to higher PP and VRAM-clock behavior under current conditions; **do not claim proven hardware protection lock/reset, EC reset, or monitor-only causality**. Boot state, user console login and display detection were changed together.
- **Next planned discrimination:** gracefully shut down, **leave AC connected**, detach the physical monitor **while off**, boot headless and repeat one 32k RDP run. No connection changes under GPU load; monitor placement on floor is unsafe for permanent unattended operation, so consider stable cable/monitor arrangement if fixed attachment is ultimately required. Note this protocol still confounds monitor detachment with reboot.

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
