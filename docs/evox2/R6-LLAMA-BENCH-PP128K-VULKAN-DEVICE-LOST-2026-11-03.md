# r6 llama-bench 128k: Vulkan IQ4 GPU device-lost incident (2026-11-03)

**Status: STOP; investigate Windows GPU TDR/device loss before restarting GPU benchmarks.** Not a source regression verdict, not a complete 12-case performance sweep. No patches, rebuilds, driver changes or BIOS/UMA configuration changes have been made in this documentation step.

Branch: `feature/r6-llama-bench-real-prompt-20261103`. Source logs: user ZIP `evox2-r6-pp128k-matrix-20261103(2).zip`, and screenshot of AMD Software Bug Report Tool saying the system experienced a driver timeout. Raw ZIP/screenshot are not checked into Git. The original 12-case plan and pilot are in [128k cross-check plan](R6-LLAMA-BENCH-REAL-INPUT-CROSSCHECK-AND-ROCM-PLAN-2026-11-03.md).

## Exact incident signature

- Cases 01–07 completed with native exit 0 / valid PP JSON and monitor data. Case 08 `Vulkan-IQ4-Japanese` failed; cases 09–12 never ran. This is **7/12 complete**, **1/12 failed**, **4/12 not attempted**.
- Case 08: `20261103-170119-...-bench-vulkan-b12032-ctx131072` (run ID in ZIP conditions/result), source `c4ddd239b`, Vulkan b12032 EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`. Original Unsloth IQ4_XS Ple16 GGUF 93682576992 bytes, same `nlp-survey-ch3-d31-b1.txt` (SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`), first 126253 of 255169 raw tokens. `-c 131072 -p 126253 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16`, warmup enabled. Vulkan QSA UNION=1, MIN_KV=32768, QSA stats OFF. QSA active logged.
- stderr sequence: `benchmark 1/1: warmup prompt run`, then `qsa-union fallback: query count, selection size or KV threshold`, then `qsa-union active (r6), source=mask-compact`, then **`benchmark 1/1: prompt run 1/1`**, then **`vkGetDeviceFaultInfoEXT (counts) failed: -4`** and **`device lost on Vulkan0`**. This means warmup advanced into the timed run before failure; it does **not** establish which GPU kernel caused the fault.
- Native process exit code **3221226505 = 0xC0000409**, Windows fail-fast. This is **not proof of a stack buffer overrun**; Windows/Microsoft documentation explains that fail-fast is used for multiple scenarios. The primary GPU evidence is Vulkan device loss combined with the AMD timeout UI and ADLX sudden resource reset. `vkGetDeviceFaultInfoEXT` returning `-4` is `VK_ERROR_DEVICE_LOST`; this query did not yield an actionable GPU fault record.
- `llama-bench.json` is only `[\n` (incomplete); `NativeRowCount=0`, `Status=FAILED`, `ExitCodeSource=GetExitCodeProcess`, parse exception due to truncated JSON. No valid PP timing can be derived for case 08.
- P-MODE `PModeAtStart=Performance`, `PModeAtFinish=Unknown` due to P-MODE WMI access error 5 and scheduled-task fallback 5-second timeout after the GPU crash. **Do not mark `PModeChanged=false` or assume a P-MODE switch.** This is a failure to query at finish.
- `DurationSeconds=746.38` total, including model load and warmup, but no completed timed-PP sample.

## ADLX timing and memory-pressure clue

Case 08 ADLX recorded 373 samples (2-second intervals) from **17:01:20.064 to 17:13:44.076 JST**. GPU-memory usage reported by ADLX rose to **97130 MiB** (~94.85 GiB), versus **85683 MiB** peak in the immediately preceding case 07 Vulkan IQ3 Japanese. Delta: **11447 MiB**. With the user's manually configured **96-GiB UMA** reference, 97130 MiB is ~98.8% of 98304 MiB (1174 MiB nominal gap); **this is a heuristic comparison, not a verified allocatable-memory limit**. The Vulkan device reports its own VRAM values and Windows UMA/residency/allocation mechanisms can differ.

Actual ADLX checkpoint rows (not interpolated):

| Time JST | ADLX GPU memory MiB | GPU clock MHz | VRAM clock MHz | GPU power W | Usage % |
|---|---:|---:|---:|---:|---:|
| 17:13:20.071 | 97130 | 2863 | 800 | 105 | 100 |
| 17:13:22.067 | 97130 | 2875 | 692 | 76 | 100 |
| 17:13:24.079 | 97130 | 2897 | 544 | 42 | 100 |
| 17:13:26.077 | 97130 | 2899 | 513 | 37 | 100 |
| 17:13:34.075 | 97128 | 2900 | 926 | 60 | 100 |
| 17:13:36.078 | 88428 | 2900 | 617 | 46 | 100 |
| 17:13:38.070 | 609 | 2900 | 605 | 45 | 100 |
| 17:13:44.076 | 609 | 2900 | 459 | 39 | 100 |

The ADLX usage field remained 100% even after memory reclamation; **do not interpret post-reset usage/clock values as an accurate picture of healthy GPU compute**. GPU temperature max in failed run = 84 °C; no clear thermal runaway. Power/VRAM clocks collapsed at the end, coinciding with loss/recovery, and are not evidence for an independent P-MODE change.

One plausible hypothesis is Vulkan IQ4 128k memory/resource pressure. Others are Vulkan QSA active-path kernel or driver behavior and WDDM timeout/scheduling under sustained long-context work. The case 08 log does **not** isolate the faulting kernel, and case 07 had the same QSA activation but successfully completed. The AMD Software dialog says driver timeout occurred, which is consistent with WDDM TDR, but **the exact Windows fault type 0x141/0x117/4101 is unknown without Event Viewer/WER records**. Do not change TdrDelay or infer a driver bug alone from this single occurrence.

## Valid prior results in interrupted archive

Native throughput `-p 126253`, context131072, warmup ON, `-r 1` each. First six ROCm b12038, Gather=0, and case07 Vulkan b12032, UNION=1.

| Case | Backend | Model | Input | PP tok/s | Status |
|---|---|---|---|---:|---|
| 01 | ROCm | IQ4 | Japanese | 290.899345 | OK |
| 02 | ROCm | IQ3 | Japanese | 299.151698 | OK |
| 03 | ROCm | IQ3 | Random | 313.880965 | OK |
| 04 | ROCm | IQ4 | Random | 308.615225 | OK |
| 05 | ROCm | IQ4 | Code | 291.982779 | OK |
| 06 | ROCm | IQ3 | Code | 299.941061 | OK |
| 07 | Vulkan | IQ3 | Japanese | 306.831891 | OK |
| 08 | Vulkan | IQ4 | Japanese | N/A | DEVICE LOST |
| 09–12 | Vulkan | IQ3/IQ4 | Random/Code | N/A | NOT RUN |

Within these ROCm cases, IQ3 exceeds IQ4 by +2.84% Japanese, +1.71% Random, +2.73% Code. **Only one timed sample each**, so neither causal attribution nor a validated stable difference. These preliminary results differ in direction from an earlier ROCm quality-task CLI incidental PP IQ4 advantage; workloads and measurement methods differ. Preserve seven runs and their per-run monitor artifacts, no automatic rerun.

## Safety and diagnostic actions

1. **Do not invoke `& $s -Stage Remaining` now.** Matrix runner skips the 7 `OK` cases but will retry failed case 08, potentially inducing another GPU hang. No blind retry, no long benchmark, no full `FLASH_ATTN_EXT` test, no TdrDelay/TdrLevel registry change.
2. While Windows is responsive, capture System/Application event records centered on **2026-11-03 17:13 JST** (suggest 17:08–17:20). Look for Display 4101, Windows Error Reporting 1001, application crash 1000, LiveKernelEvent 141/117, AMD display driver/WHEA records. Record whether a relevant `C:\Windows\LiveKernelReports\WATCHDOG` or WER report exists; initially save **metadata only** and do not upload large crash dumps.
3. Read-only collection script supplied as separate user attachment: `Collect-Evox2-GpuTimeout-20261103.ps1`, packaged in `Collect-Evox2-GpuTimeout-20261103.zip`. It exports a privacy-reviewable ZIP of nearby events, driver version and crash-report metadata; it does not execute GPU workloads.
4. Preserve screen/grab and raw matrix ZIP. After collection, close bug report dialog, save work and perform a normal Windows reboot once. Confirm desktop/RDP and GPU reporting are healthy before any GPU test.
5. Review OS event signatures and resource headroom first, then design **one controlled, reduced-risk test** if evidence supports it. For example, a much shorter Vulkan IQ4 workload (smaller context) followed by separate QSA ON/OFF only if needed; do not repeat full 126253-token Vulkan IQ4 until cause/risk has been assessed.
6. No changes to existing frozen binaries, GPU driver, BIOS, UMA setting, source, or public release while incident is under investigation.

**Key difference from a normal bench error:** this incident involved a reported AMD display driver timeout, Vulkan device loss, abrupt VRAM release and P-MODE probe failure. The first seven cases remain valid; the missing five are *not* a reason to restart the matrix immediately.

## Windows Event / WER follow-up — collected 2026-11-03 18:17 JST

**Evidence upgrade: current incident is a confirmed Windows LiveKernelEvent 141 (VIDEO_ENGINE_TIMEOUT_DETECTED), with a matching new WATCHDOG live dump and subsequent `dwm.exe` APPCRASH in AMD graphics module.** This moves the diagnosis beyond a generic Vulkan process crash, but does **not** prove whether Vulkan kernel, driver scheduling, memory pressure, or resource residency initiated the timeout.

Source archive `evox2-gpu-timeout-20261103.zip` (about 5.6KB) from read-only `Collect-Evox2-GpuTimeout-20261103.ps1`; event interval **2026-11-03 17:08–17:20 JST**, collection 18:17:30 JST. ZIP contents: `application-events.csv`, `graphics-adapter.csv`, `live-kernel-dump-file-list.csv`, `system-events.txt`, `readme.txt`. No .dmp bytes uploaded. Original Windows event messages retained in the user ZIP, not copied into repo.

| Event timestamp JST | Provider / event | Details |
|---|---|---|
| **17:13:27** | Live dump file metadata | `C:\Windows\LiveKernelReports\WATCHDOG\WATCHDOG-20261103-1713.dmp`; 480988 bytes, creation/write 17:13:27 |
| **17:13:29.908** | Application Error ID 1000 | `llama-bench.exe` fault, module `ucrtbase.dll`, exception **0xC0000409**, offset `0xA527E` |
| **17:13:30.973**, **17:13:31.907** | Windows Error Reporting ID 1001 | `Event Name: LiveKernelEvent`, **P1:141**, points to **same new 20261103 WATCHDOG live dump** |
| **17:13:33.023** | Windows Error Reporting ID 1001 | `Event Name: BEX64`, `llama-bench.exe`, `ucrtbase.dll`, `P8:c0000409`, `P9:0000000000000007`; same process crash as 17:13:29, not a second independent PP failure |
| **17:13:53.724** | Application Error ID 1000 | `dwm.exe` fault, module **`amdxx64.dll`**, version **32.0.31041.1004**, exception **0xC0000005** (access violation), offset `0xD0C82` |
| **17:13:57.876** | Windows Error Reporting ID 1001 | `Event Name: APPCRASH` with `dwm.exe` / `amdxx64.dll` and same 0xC0000005; WER report for the prior DWM fault |

Microsoft's documentation identifies `0x141` as **VIDEO_ENGINE_TIMEOUT_DETECTED**, indicating a display/GPU processing engine failed to respond in time; a *live dump* code, not proof of a machine-wide BSOD. See `https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x141---video-engine-timeout-detected`. `0xC0000409` is a Windows fail-fast termination category; do not diagnose buffer overrun purely from its legacy label. `0xC0000005` signifies invalid memory access in the DWM/AMD module; without a DWM crash dump cannot establish root cause or direction of causality.

**Important historical WER caveat:** Although `application-events.csv` has 27 selected rows, many ID 1001 records at **17:13:31** re-list *pre-existing* WATCHDOG dumps dated October 22, October 10, September and August/July 2026, plus older BlueScreen reports. They are **not separate new GPU hangs at 17:13 on November 3**. Only the WER entries pointing to **WATCHDOG-20261103-1713.dmp** establish the new 0x141 incident, and they refer to the same dump. Therefore do not count 19 `LiveKernelEvent` WER rows as 19 new faults.

The `system-events.txt` reports no selected System event (raw System queries=1, selected=0); **absence of Display 4101 in the selected window does not override LiveKernelEvent 141**. The collection also reports Access Denied when reading `C:\ProgramData\Microsoft\Windows\WER\ReportArchive` and `ReportQueue`; `0` matched report folders is **not** proof there are no WER reports. New 480988-byte WATCHDOG live dump exists, but **not parsed**.

`graphics-adapter.csv` reports `AMD Radeon(TM) 8060S Graphics` driver **32.0.31041.1004**, date shown as 2026-08-17; also lists Microsoft Remote Display Adapter, consistent with RDP session. This is driver identity only, not a recommendation to change drivers.

### Updated decision

1. **Halt** matrix `-Stage Remaining`: it would retry failed `08-Vulkan-IQ4-Japanese`, risking another display-driver hang. Preserve all 7 good 128k PP results; keep case08 FAILED and cases09–12 NOT RUN.
2. If the system is still running from the incident, save work and preserve the specific 480988-byte `WATCHDOG-20261103-1713.dmp` in a private local location if deeper analysis is desired. It is a live dump and may contain sensitive machine information. Optional inspect with WinDbg `!analyze -v` rather than blindly retrying the full workload.
3. Perform one **normal OS reboot** after capturing incident information. Verify adapter, P-MODE, desktop/RDP and GPU memory reporting afterward. Do not change `TdrDelay/TdrLevel`, BIOS, UMA, or drivers solely based on this occurrence.
4. Decide a bounded low-risk investigation only after reviewing root-cause evidence. At present, 128k IQ4 Vulkan memory reported peak 97130 MiB (~94.85 GiB) and the desktop compositor also crashed; capacity pressure and QSA active-path/driver scheduling all remain plausible. If more testing is pursued, avoid a full 128k IQ4 warmup + timed retry as the first post-reboot action.
5. No source edits or patches, no kernel attribution, no assertion of thermal cause, no claim of hardware defect. Incident priority is Windows graphics-stack recovery and isolation before finishing matrix.

## WinDbg WATCHDOG dump analysis 2026-11-03

**Updated conclusion:** a `VIDEO_ENGINE_TIMEOUT_DETECTED (0x141)` live dump with AMD kernel display module `amdkmdag.sys` bucketing and Windows GPU scheduler engine-reset stack. **This establishes GPU-engine non-response / TDR recovery, not the initiating Vulkan shader, an AMD software defect, or an allocation failure.**

Evidence: user-provided WinDbg `.symfix; .reload; !analyze -v` transcript from `WATCHDOG-20261103-1713.dmp`. Only textual analysis supplied; actual .dmp is not in Git or this chat.

Key extracted fields:

```text
VIDEO_ENGINE_TIMEOUT_DETECTED (141)
Arg1 = ffff808f9d4513d0  (internal TDR recovery context pointer)
Arg2 = fffff8034b3a0fb0  (pointer into responsible display driver module)
Arg3 = 0000000000000000  (secondary driver-specific bucketing)
Arg4 = ffff808fb1c5a080  (internal context-dependent data)
Failure.Bucket = LKD_0x141_IMAGE_amdkmdag.sys
Failure.Exception.IP.Module = amdkmdag
Failure.Exception.IP.Offset = 0x1d0fb0
SYMBOL_NAME = amdkmdag+1d0fb0
IMAGE_NAME = amdkmdag.sys
PROCESS_NAME = System
DUMP_FILE_ATTRIBUTES = 0x18 / Kernel Generated Triage Dump / Live Generated Dump
```

Decisive stack excerpt:

```text
dxgkrnl!TdrCollectDbgInfoStage1+0xe6a
dxgmms2!VidSchiResetHwEngine+0x222
dxgmms2!VidSchiResetEngines+0xcb
dxgmms2!VidSchiCheckHwProgress+0x316
dxgmms2!VidSchiWaitForSchedulerEvents+0x1b1
dxgmms2!VidSchiScheduleCommandToRun+0x32e
dxgmms2!VidSchiWorkerThread+0xdc
```

Interpretation:

- Microsoft's official bug check documentation identifies `0x141` as a **GPU/video engine timeout live dump**, not an actual whole-system BSOD; `Arg2` is a pointer into the responsible driver for diagnostics. See https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x141---video-engine-timeout-detected and https://learn.microsoft.com/en-us/windows-hardware/drivers/display/timeout-detection-and-recovery .
- Kernel stack shown is the **Windows TDR detection/reset/collection path**. It does **not** show the instruction sequence or queue submission of the original shader workload. `PROCESS_NAME=System` refers to the kernel diagnostic/scheduler thread, not the user process's origin.
- `amdkmdag+0x1d0fb0` is the driver-owner/bucketing address, not independently demonstrated to be the faulty code location. Do not conclude driver source bug/hardware damage from the bucket.
- WinDbg warning `Unable to load image amdkmdag.sys, Win32 error 0n2` and `Unable to verify timestamp` indicates missing/unavailable image for symbol validation; **not evidence that the installed driver is corrupt**.
- Mini-dump limitations: `Mini Kernel Dump does not contain unloaded driver list`, unavailable `dxgkrnl!_TDR_RECOVERY_CONTEXT` type symbol, and no readable precise faulting GPU shader. Secondary tag TDR data might be present: optional WinDbg `.enumtag` (Microsoft docs), and `lmvm amdkmdag` for driver module metadata. Their output may be insufficient to identify a shader or allocation failure.
- Reconcile with previously analyzed 17:13:27 WATCHDOG file, 17:13:29 `llama-bench.exe` fail-fast `0xC0000409`, 17:13:53 `dwm.exe` AMD user-mode module `amdxx64.dll` crash. These are related in time, but a causal sequence at kernel/device level is not proven. The observed peak ADLX ~97130 MiB (~94.85GiB) in the 96 GiB configured UMA remains a **capacity-pressure hypothesis**, not an OOM diagnosis.

**Action:** Keep interrupted 128k 12-case run at 7 OK / 1 failed / 4 not attempted; **do not re-run `-Stage Remaining`** since it retries the failed IQ4 Vulkan Japanese case. If not already done, preserve dump/OS metadata and restart Windows normally before more GPU work. Check GPU device, P-MODE, RDP/physical display, VRAM clock, memory reporting. Do not alter TDR registry, BIOS, driver or source as a first response.

If user wants to finish the experimental comparison, first design a **separate, explicitly scoped** post-recovery plan: retain valid ROCm six and Vulkan IQ3 Japanese one; consider safer Vulkan IQ3 random/code under isolation only after health checks, and evaluate a reduced-size / lower-risk Vulkan IQ4 diagnostic separately rather than repeating the failed 126253-token warmup+timed full PP. This does **not** certify any new matrix results.

At this point WinDbg largely confirms the *failure class* and responsible driver module; hardware-vs-memory-vs-kernel root cause remains undetermined.

## WinDbg secondary tags and loaded module (follow-up) — 2026-11-03

**User reports normal Windows reboot has completed.** This is a user-confirmed reboot, not independent certification that P-MODE/driver/VRAM clocks have recovered under load. No benchmark was performed during this diagnostic step.

Input: `貼り付けたテキスト（1）(20261103-093608).txt` with WinDbg `.enumtag` and `lmvm amdkmdag`, approximately 944151 bytes / 13690 lines. Full raw tag hexdump remains an external local attachment, **not** reproduced in repository.

### .enumtag

- Two secondary data tags: `{270A33FD-3DA6-460D-BA893C1BAE21E39B} - 0x3567c bytes` and `{8BE1C8F0-B5BD-48FE-BCB7BBD165DEB285} - 0x10 bytes`. The first is the TDR-related secondary tag identified in Microsoft's 0x141 documentation (which writes the formatted GUID `{270A33FD-3DA6-460D-BA89-3C1BAE21E39B}`). The `0x3567c` is ~217.6 KiB.
- Readable hex/ASCII content includes `vTDR` and `llama-bench.ex` (WinDbg ASCII view; trailing extension terminator is not fully shown on that line). This corroborates association of the timeout context with the running `llama-bench.exe` workload, though it **does not** itself identify the failing Vulkan compute shader or establish the executable as the sole initiating cause.
- Additional labels visible in the raw hex/ASCII include `WaveChunk`, `HwExecUnitCp` and `GlobalMmr`. These are undissected driver/GPU state records, **not** actionable kernel identifiers without AMD-specific decoder/documentation. Do not derive GPU scheduler event chronology from the arbitrary raw tag bytes.
- Second 0x10-byte secondary tag is present but no further diagnostic identification is supported.
- Microsoft: https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/bug-check-0x141---video-engine-timeout-detected and https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-enumtag--enumerate-secondary-callback-data- .

### lmvm amdkmdag

```text
fffff803`4b1d0000 fffff803`502f6000  amdkmdag T (no symbols)
Loaded symbol image file: amdkmdag.sys
Image path: amdkmdag.sys
ImageSize: 05126000
Timestamp: Tue Jun 24 05:14:56 1975 (0A4C8340)
CheckSum: 0508CC9B
Mapping Form: Loaded
```

The module identity agrees with `!analyze -v`, but AMD function names are unavailable (`no symbols`). The 1975 PE header timestamp is **not reliable evidence of the installed driver's actual build date**: reproducible PE builds may set timestamp fields from content hashes (Microsoft PE format: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format). We have **not independently verified** whether this particular AMD binary has an `IMAGE_DEBUG_TYPE_REPRO` record; do not assert it does. The separately captured adapter/WER driver module version `32.0.31041.1004` remains a better version anchor. No proof of corrupt module, outdated driver, or debugger failure beyond unavailable symbols.

### Revised decision after WinDbg supplemental data

This completes the practical **failure-class** and owner-tag diagnosis from the current small triage dump: Windows GPU engine timeout `0x141`, AMD kernel display module `amdkmdag`, TDR content referencing `llama-bench.ex`. **Root cause is still not isolated** between near-UMA-capacity GPU memory/residency pressure (~97130 MiB ADLX), Vulkan QSA UNION long-context active path, WDDM scheduling/driver behavior, and an interaction among them.

Since the OS has been rebooted, next perform **read-only/lightweight system health probes** (Device Manager/adapter recognition, P-MODE Performance, current clock/VRAM reporting, basic GUI/RDP reliability) without any 128k stress. If normal and user wishes to continue, run a separate **bounded, staged** diagnostic starting with a lower-context Vulkan IQ4 trial or lower-risk IQ3 pending cases; do not relaunch `-Stage Remaining` because it automatically retries the failed 08 `Vulkan-IQ4-Japanese` case. Keep first seven 128k PP numbers and mark remaining four as not attempted. Repeating full 128k IQ4 under identical conditions is deferred.

No changes to C++ sources, binary, driver, BIOS/UMA, or TDR registry.

## Post-reboot Windows and Vulkan device listing — 2026-11-03

User confirms **Windows was rebooted** after the 17:13 GPU TDR. A subsequent PowerShell read-only probe shows the graphics driver and Vulkan device can be discovered again:

```text
Get-CimInstance Win32_VideoController:
Microsoft Remote Display Adapter | 10.0.26100.9818 | OK
AMD Radeon(TM) 8060S Graphics    | 32.0.31041.1004 | OK

llama-bench.exe --list-devices (Vulkan b12032):
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = AMD Radeon(TM) 8060S Graphics (AMD proprietary driver)
load_backend: loaded Vulkan backend ...ggml-vulkan.dll
Available devices:
Vulkan0: AMD Radeon(TM) 8060S Graphics (114507 MiB, 108782 MiB free)
```

**Result: PASS for Windows adapter status and Vulkan backend/device discovery only.** The driver version is unchanged from the captured incident. Windows reports a Remote Display Adapter in addition to AMD GPU, consistent with the user's RDP workflow. The reported Vulkan total/free memory is the backend/driver-reported budget, **not** direct proof of the configured 96GiB UMA size, nor of full IQ4 128k allocation headroom.

**Not verified by these two commands:** P-MODE and live memory clocks after reboot, real GPU compute, long-duration device stability, or safety of 128k IQ4. Continue to hold `-Stage Remaining` because it retries the full-length IQ4 failure. If proceeding with a bounded diagnostic, start with **one** low-context, short Vulkan model-run after ensuring the display works and other GPU workloads are stopped. Set QSA UNION OFF and no warmup. Inspect ADLX/P-MODE and WER before any repeat. Only after that consider a larger but still bounded 32k IQ4 PP. The default QSA union threshold 32768 means a 32k input may not activate the feature, so a 32k OFF/ON nominal comparison is **not** a valid proof of QSA kernel effects; compare QSA only where logs positively show activation, and defer that heavier test for now.

No benchmark was executed in this post-reboot check. No source/driver/BIOS/UMA/TDR configuration changes.

## Post-reboot Vulkan IQ4 real-model smoke (32k context) — 2026-11-03

**PASS for short Vulkan IQ4 load and 256-token PP after reboot.** The user's ZIP `20261103-184435-722-bench-vulkan-b12032-ctx32768-5c7652f9e27f.zip` contains the complete `conditions.json`, `result.json`, `llama-bench.json`, stderr, ADLX and summary. Raw archive is not committed.

| Item | Observed |
| --- | --- |
| Run ID | `20261103-184435-722-bench-vulkan-b12032-ctx32768-5c7652f9e27f` |
| Started → finished | 18:44:37 → 18:45:20 JST; elapsed 43.633 s including load |
| Model | Original Unsloth `Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf` 93682576992 bytes |
| Binary | Vulkan b12032 `c4ddd239b`, SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |
| Input | `nlp-survey-ch3-d31-b1.txt`, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`; `head` |
| Context/prompt | `-c 32768 -p 256 -n 0 -d 0 -r 1 -b 256 -ub 256 --no-warmup -fa auto -ctk/ctv f16 -ngl 999 -ncmoe 0 -t 4` |
| QSA | `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0` (feature requested OFF). No active-UNION line in stderr. |
| Native JSON | `n_prompt=256`, `avg_ns=658279700`, `avg_ts=388.892442`, samples=1 |
| Wrapper | `Status=OK`, `ExitCode=0`, no Run/Parse exception |
| ADLX | Exit0, 19 samples at 2 s, remote_session=1; max VRAM `90648 MiB` = 88.52 GiB; max GPU clock `2900 MHz`, max VRAM clock `1000 MHz`, peak temperature `57 C`, peak power `76 W`, GPU busy max `45%` |
| P-MODE | `Performance` start/end, `PModeChanged=false`; no high-load (>95%) samples for ADLX power-class consistency |
| External noise | Named-process coverage complete; PossibleNoise false |
| TDR / reset | None observed during this short run |

**Interpretation:** After a normal OS restart the AMD GPU and Vulkan path appear usable for an IQ4 model load and actual, short PP compute. Short smoke and `--list-devices` do not certify full 128k stability. 256-token PP cannot be used for absolute speed comparison against the interrupted 126253-token job; QSA OFF, context, and batch/ubatch also differ.

**Capacity clue:** failed 128k Vulkan IQ4 recorded `97130 MiB` ADLX VRAM, vs `90648 MiB` here: peak difference `6482 MiB`. These are peaks in *distinct runs*, not directly decomposable into KV or scratch allocation. 90648 MiB is already a substantial reservation for an apparent 96GiB manually configured UMA, so do not assume ample Vulkan IQ4 128k headroom. Within the short-run sample, GPU usage never reached 95%, so it does not establish sustained power or memory residency robustness.

**Recommended next step:** If more fault isolation is worthwhile, proceed to **a single bounded ~8k-token real-text PP run** of Vulkan IQ4 with **explicit QSA OFF** (`-c 32768 -p 8192 -n 0 -r 1 --no-warmup -b 2048 -ub 1024 -ngl 999 -ncmoe 0 -fa auto -ctk/ctv f16`) and monitor ADLX, event history, GPU/VRAM clocks, P-MODE. Require completion, no new TDR, stable memory. Then only if healthy consider a separate ~30k-token 32k context trial, still QSA OFF. Never automatically restart the 12-case matrix because it will retry the failed full-length case08. More repetitions/ON-OFF tests are deferred until safety and root-cause criteria are satisfied. A QSA flag toggled at 256 or 8k does not by itself exercise the long-context active UNION kernel, so passing or failing one case cannot identify that feature as the cause.

## Post-reboot Vulkan IQ4 8192-token sustained-PP probe — 2026-11-03

**PASS: 8192 actual Japanese-source tokens on Vulkan IQ4 at 32768 explicit context, QSA UNION OFF and no warmup.** Source user ZIP `20261103-185048-704-bench-vulkan-b12032-ctx32768-de2d71ea1d3b.zip`; raw archive not stored in repo.

- Run: `20261103-185048-704-bench-vulkan-b12032-ctx32768-de2d71ea1d3b`. Start 18:50:49 JST, finish 18:51:42 JST, `DurationSeconds=52.446`, including ~37 seconds of model load/preparation before timed PP.
- Binary Vulkan b12032 `c4ddd239b`, SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` matched previous verified Vulkan build. Same original Unsloth IQ4_XS PLE16 GGUF `93682576992` filesystem bytes (full GGUF SHA not calculated). Same Japanese ANLP `nlp-survey-ch3-d31-b1.txt`, input SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, slice head.
- Native argv: `-p 8192 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -ctk f16 -ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto -c 32768 -f ... --prompt-slice head --no-warmup`; `Environment.GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, Gather OFF. ROCm7.2 HIP_PATH in Windows shell has no material role for the **Vulkan-only** process.
- Native JSON: `n_prompt=8192`, `avg_ns=15539463500` => **527.173927 tokens/s**, one repetition, no sample stddev. `NativeRowCount=1`, `Status=OK`, exit0, `RunException=null`, `ParseException=null`; stderr no GPU fault, no `qsa-union active` line.
- ADLX: **26 samples** at 2-second intervals over the process. Samples at >=95% usage: **6**, mean GPU clock **2862.83MHz**, mean VRAM clock **999.5MHz**, mean GPU power **119.667W**, `PowerClass=Performance-like` and `Consistent=true`. Max GPU temp **66C**. Max ADLX GPU memory **93156 MiB (~90.97 GiB)**. Sampled memory reached `90654 MiB` during loading, rose at PP start to `93144 MiB`, then rose gradually to `93156 MiB` by end. No conspicuous power/VRAM-clock collapse or driver reset in this run. ADLX exit0, samples26, remote_session=1.
- P-MODE Performance at start and finish, `PModeChanged=false`, no P-mode warnings; named background process probe `Observed`, `Complete`, `PossibleNoise=false` (sampling coverage caveat).
- Relative to failed 128k Vulkan IQ4 ADLX high watermark `97130 MiB`, observed 8k maximum is **3974 MiB lower**. Relative to an arithmetic 96GiB=98304MiB UMA setting, 8k leaves **5148 MiB**, but allocated/resident/available memory limits are NOT equivalent and may change dynamically. Do not call either delta a proven free budget.
- **Decision:** post-reboot IQ4 compute now demonstrated beyond 256-token smoke. This supports a bounded ~30k-token run in the **same 32k context with QSA UNION OFF**, still no warmup and single repetition, subject to GPU desktop stability and avoiding parallel GPU work. This probes longer sustained load while limiting context and feature activation, without pretending it isolates the original 128k TDR trigger. Watch ADLX/high-load, WER, clocks, VRAM. Stop upon any new TDR/UI freeze. Do NOT invoke original `-Stage Remaining` (auto-retries failed 08) and do NOT test full 128k IQ4 yet.

## Post-reboot Vulkan IQ4 30000-token PP (32k context) — 2026-11-03

**PASS: extended sustained real-text 30000-token PP, Vulkan IQ4 PLE16, `-c 32768`, QSA UNION OFF, no warmup.** This establishes stable observed behavior under a ~70-second timed PP and >1-minute high GPU utilization in the tested 32k context. It **does not** certify the 128k failure path or all memory residency conditions.

User ZIP: `20261103-185642-516-bench-vulkan-b12032-ctx32768-cb387aa6f067.zip`, containing valid conditions/result/native JSON, stderr, ADLX, summary, output. No raw ZIP is committed.

| Field | Observed value |
|---|---|
| Run ID | `20261103-185642-516-bench-vulkan-b12032-ctx32768-cb387aa6f067` |
| Start/finish JST | `2026-11-03T18:56:43.363+09:00` to `18:58:31.832+09:00` |
| Total run wall time | 108.469 sec including model load/preparation |
| Backend/build | Vulkan0, b12032 `c4ddd239b`, same verified executable SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |
| Model | Original Unsloth IQ4_XS Ple16, `93682576992` GGUF filesystem bytes, model SHA not independently calculated |
| Input | `nlp-survey-ch3-d31-b1.txt`, source SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` |
| Workload | `-c 32768 -p 30000 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16 --prompt-slice head` |
| Environment | `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, `QWEN4EXP_QSA_GATHER=0`. No active QSA diagnostics. |
| Native PP result | `n_prompt=30000`, `avg_ns=70053151300` = **428.246259 tok/s**; one sample |
| Status | `OK`, exit0, one native JSON row, no run/parse errors |
| P-MODE | Performance start and finish, no changes/warnings |
| ADLX | Exit0, 54 samples at 2-sec cadence, 34 >=95% GPU use, high-load mean clock **2839.82 MHz**, VRAM clock **999.91 MHz**, power **119.647 W** (Performance-like), peak GPU temperature **75 C**, peak ADLX GPU memory **93203 MiB** (~91.02 GiB). RDP session present. |
| Named-process noise | Observed, CPU coverage Complete, PossibleNoise false; transient background activity cannot be excluded |

Memory time series: GPU-memory usage first rises to ~90648 MiB on model load, ~90653 MiB while preparing, then ~93120 MiB when PP starts (18:57:19) and climbs gradually to 93203 MiB by run end. The earlier same-`-c 32768` **8192-token** short PP reached 93156 MiB (difference **47 MiB**) and initial **256-token** smoke reached 90648 MiB; short-only smoke can miss PP workspace/residency and cannot be compared as a controlled memory experiment. Failed 128k IQ4 recorded **97130 MiB** ADLX peak (difference **3927 MiB** vs this 30k run). The ~96GiB manually set UMA target and these ADLX reported usage numbers are **not** proof of allocatable headroom or exact per-context KV size. Do not claim OOM as cause.

The high-load stretch has GPU usage ~99–100%, VRAM clock near 1000MHz, GPU power 115–122W, peak temp75C, and no observed device-loss/driver timeout. GPU clock gradually decreased from ~2860 to ~2780MHz by the last sample with sustained high power; this alone is not the previous pathological VRAM-clock failure or evidence of thermal shutdown.

**Decision / next diagnostic:** 32k IQ4 QSA-OFF sustained GPU compute is functioning after reboot. To distinguish context-size/memory pressure from the QSA-ON long-context kernel, do **not** rerun failed 128k IQ4 or original `-Stage Remaining`. If proceeding, start a separate **64k-context IQ4 QSA-OFF** *short prompt* smoke first (model/context allocation), followed only if healthy by one **~60k-token** real-input PP at `-c 65536` with QSA OFF and no warmup. Keep exact original model and Japanese source, same binary, threads, full-PP batch2048/ubatch1024/f16, performance P-MODE, ADLX. Clearly separate the short smoke from timed long PP results and stop on any WER/TDR/GPU display anomaly. QSA-on activation/failure requires additional controlled evidence; toggling UNION at short inputs cannot exercise the relevant kernel. Avoid UMA/BIOs/driver/TDR registry changes during isolation.

## Post-reboot Vulkan IQ4 64k-context 256-token smoke — 2026-11-03

**PASS for context 65536 model allocation and 256-token actual PP with QSA UNION OFF and no warmup.** User ZIP: `20261103-190336-143-bench-vulkan-b12032-ctx65536-15fc5261257f.zip` (original artifact kept outside Git; contents include conditions, result, native JSON, stderr, ADLX metrics, output, summary).

| Attribute | Verified value |
|---|---|
| Run ID | `20261103-190336-143-bench-vulkan-b12032-ctx65536-15fc5261257f` |
| Time | 2026-11-03 19:03:36–19:04:20 JST, wrapper duration 43.023 sec |
| Build | Vulkan b12032 `c4ddd239b`, EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |
| Model | Same original Unsloth IQ4_XS PLE16, file length 93682576992 bytes, model hash not recalculated |
| Input | Same `nlp-survey-ch3-d31-b1.txt`, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, head |
| Native arguments | `-c 65536 -p 256 -n 0 -d 0 -r 1 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16 --no-warmup -f ... --prompt-slice head` |
| QSA | `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, Gather OFF; no active QSA log |
| Result | `Status=OK`, `ExitCode=0`, native `n_prompt=256`, 1 sample, `avg_ns=657130600`, **389.572484 tok/s** |
| P-MODE | Performance at start and finish, `PModeChanged=false` |
| ADLX | 19 samples, exit 0; `gpu_vram_mb` max **93002 MiB** (~90.82 GiB); GPU temp max 38 C; GPU use max **21%**; GPU clock up to 2900 MHz; VRAM clock max 1000 MHz, but no sustained high-load samples; driver timeout not seen |
| Background | No named-process interference flagged by wrapper; no inference of workload stability at high sustained load |

Memory comparison using ADLX per-run peaks (not identical usage windows): 32k 256-token IQ4 smoke **90648 MiB**; this 64k 256-token smoke **93002 MiB** (delta **+2354 MiB** at fixed 256-token prompt); 32k 30000-token PP **93203 MiB**; failed 128k IQ4 **97130 MiB**. During 64k smoke, sampled memory rose from ~90653 MiB on model load to 93002 MiB at start of actual PP, consistent with context-size-associated reservation changes but not direct proof of the exact KV byte contribution. The 64k PP workspace/residency and performance at 60k input have **not** been measured. ADLX GPU memory usage vs configured 96 GiB UMA should not be treated as allocatable headroom.

**Decision:** reboots, backend discovery, 32k 256-token, 32k 8k-PP, 32k 30k-PP, and this 64k 256-token model/PP smoke have succeeded. Since 64k short-smoke memory already reaches **93002 MiB** and 128k timed QSA-ON previously TDR'd at **97130 MiB**, conservatively gate the next long-context run with **one 64k-context 8192-token QSA-OFF real-PP check**, using actual PP batch2048/ubatch1024 and no warmup, before the originally proposed ~60000-token 64k PP. This smaller intermediate test probes PP scratch/residency and high GPU load at 64k context. Examine ADLX max/memory stability and TDR before authorizing any 60k PP. Do not automatically rerun the interrupted 12-case matrix, where case08 auto-retries failed full 128k Vulkan IQ4. No changes to driver, source, BIOS, UMA or TDR registry.

## Post-reboot Vulkan IQ4 64k-context 8192-token PP — 2026-11-03

**PASS: native 8192-token Japanese-document PP at explicit 65536 context with Vulkan IQ4 PLE16, QSA UNION OFF, no warmup.** Source ZIP `20261103-190852-549-bench-vulkan-b12032-ctx65536-1e220eff4716.zip` (user-side artifact; not committed). Valid full conditions/result/native JSON and ADLX telemetry.

| Field | Observed |
| --- | --- |
| Run ID | `20261103-190852-549-bench-vulkan-b12032-ctx65536-1e220eff4716` |
| Start/finish (JST) | 2026-11-03 19:08:53.404 – 19:09:46.079 |
| Total wrapper duration | 52.675 seconds including model load, actual timed PP 15.5355915 seconds |
| Binary | Vulkan0, b12032 `c4ddd239b`, EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |
| Model | Same original Unsloth IQ4_XS PLE16, filesystem size 93682576992 bytes; full model SHA not computed in this run |
| Input | Same Japanese ANLP `nlp-survey-ch3-d31-b1.txt`, input SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, `--prompt-slice head` |
| Arguments | `-c 65536 -p 8192 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16` |
| Environment | `GGML_VK_QSA_UNION=0`; `GGML_VK_QSA_UNION_STATS=0`; `QWEN4EXP_QSA_GATHER=0`; no `qsa-union active` stderr. |
| Native PP | One native row: `n_prompt=8192`, `avg_ns=15535591500`, **527.305317 tok/s**; no repetition-derived stddev |
| Result / exceptions | `Status=OK`, exit0, `RunException=null`, `ParseException=null`, stderr has no GPU fault or device lost |
| ADLX | Exit0, **26 samples**, GPU usage >=95% on **6 samples**; high-load mean GPU clock **2857.667 MHz**, VRAM clock **999.167 MHz**, GPU power **119.333 W**, classified Performance-like/consistent; max GPU temperature **63C**, peak ADLX GPU memory **94311 MiB (~92.10 GiB)** |
| P-MODE | Performance both at start and finish, `PModeChanged=false`, no warnings |
| Background | Monitored named processes, CPU coverage complete, `PossibleNoise=false`; cannot rule out all transient interference |

ADLX chronological observations: GPU-memory usage `90654 MiB` steady from ~19:09:01 through ~19:09:27 during model setup; at 19:09:29 it rose to `94299 MiB`, and during high GPU utilization reached `94311 MiB` by 19:09:43. No continued steep growth in the short 8k PP or collapse of power/VRAM clock. Context65536 short smoke peak was `93002 MiB` (this run **+1309 MiB**), 32k-context 8k PP peak was `93156 MiB` (this run **+1155 MiB**), and failed 128k IQ4 peak `97130 MiB` (this run **-2819 MiB**). Compare peaks with caution: each job has its own allocations, and ADLX reported usage is **not** exact allocatable free memory within manually configured UMA.

**Decision:** 64k-context QSA-OFF IQ4 demonstrated a valid short full-batch PP under high GPU load. If continuing isolation, one bounded `-c 65536 -p 60000` real-input, QSA UNION OFF, no warmup, batch2048/ubatch1024 and the same model/file/binary is now justified **provided GPU desktop/P-MODE remain normal and no other GPU inference job is running**. The test increases sustained GPU load at fixed context to check for temporal/longer-prompt instability while keeping QSA disabled. It remains a risk, especially with ~94 GiB already reported; watch GPU/video and stop on a new TDR. This neither proves nor disproves whether QSA UNION or memory pressure initiated the prior 128k TDR. **Do not re-run `-Stage Remaining`**; it retries failed 128k Vulkan IQ4 case08. Do not alter BIOS/UMA, driver or TDR registry during isolation.

## Post-reboot Vulkan IQ4 64k-context 60000-token PP — 2026-11-03

**PASS: full sustained 60,000-token real-document PP, original Unsloth IQ4_XS Ple16, Vulkan b12032, explicit context 65,536, QSA UNION OFF, no warmup.** User archive: `20261103-191514-805-bench-vulkan-b12032-ctx65536-32a9841dae75.zip`. Raw ZIP retained user-side, not stored in GitHub.

| Property | Verified run data |
| --- | --- |
| Run ID | `20261103-191514-805-bench-vulkan-b12032-ctx65536-32a9841dae75` |
| Start → finish | 2026-11-03 19:15:15.678 → 19:18:42.159 JST, total **206.482 s** |
| Backend | `Vulkan0`, b12032 `c4ddd239b`, EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |
| Model | `Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf`, original Unsloth, filesystem 93682576992 bytes. Model full SHA not computed |
| Input | Same `nlp-survey-ch3-d31-b1.txt`, 1261235 bytes, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, `head` slice |
| Native command | `-c 65536 -p 60000 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -ctk/ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto -f ... --prompt-slice head` |
| QSA flags | `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, `QWEN4EXP_QSA_GATHER=0`. No QSA active message or Vulkan errors in stderr |
| Native PP | One JSON row, `n_prompt=60000`, `avg_ns=168865992700`, **355.311327 tok/s**, `stddev_ts=0` due to only 1 sample; no confidence interval |
| Wrapper | `Status=OK`, `ExitCode=0`, `RunException=null`, `ParseException=null` |
| P-MODE | Performance at start and finish, `PModeChanged=false`, `PModeWarnings=[]` |
| ADLX | 103 samples/2 s, exit0, high GPU usage >=95% for **83 samples**; high-load mean GPU clock **2827.012 MHz**, VRAM clock **999.940 MHz**, power **119.554 W**; peak GPU temperature **81 C**; peak ADLX GPU memory **94424 MiB (~92.21 GiB)**; consistent Performance-like power |
| Display | Active RDP session `RDP-Tcp#0`, remote-like display; no GPU timeout observed |
| Background | `Status=PartialCoverage`, `PossibleNoise=null`, CPU coverage Partial. **Do not claim background interference fully ruled out.** Named processes `MsMpEng` and `NisSrv` active, busy threshold not exceeded among observed names; individual short-lived Windows processes may not be captured |

ADLX memory chronology:
- ~19:15:24, model-load residency `90655 MiB`;
- ~19:15:52, `92705 MiB`;
- ~19:15:54, `94300 MiB` as active PP starts;
- 19:16:24, `94359 MiB`;
- 19:18:00, `94423 MiB`;
- 19:18:40, `94424 MiB`, GPU 100%, VRAM clock 1000MHz, power120W.
At high load GPU clock mean ~2827MHz, peak temp81C, no evident sustained VRAM-clock collapse or device loss.

Memory comparison: at **same 64k context** the earlier 8192-token QSA-OFF real PP peaked `94311 MiB` and this 60000-token PP `94424 MiB` (**+113 MiB**); the earlier short 256-token context smoke peaked `93002 MiB`. Previous failed **128k QSA-ON** IQ4 run peaked `97130 MiB` (**+2706 MiB** vs this run), but this is a peak comparison across different contexts, warmup, activation paths and loads, **not exact proven allocatable headroom or OOM evidence**.

**Interpretation:** 64k-context IQ4 Vulkan **QSA-OFF** sustained PP now confirmed for 60k tokens, including continuous heavy GPU load (~2.8 minutes). This makes an elementary "Vulkan IQ4 cannot run long PP at all" explanation unlikely. It does not rule out context-dependent resource pressure at 128k or QSA-enabled device-driver interactions.

**Proposed controlled next discrimination (not executed yet):** If user wishes to continue after a no-anomaly status check, run exactly **one** 64k-context / 60000-token / same model and same Japanese input **QSA UNION ON**, with `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `GGML_VK_QSA_UNION_STATS=0`, and keep **no warmup**, same batch2048/ubatch1024, f16 KV, native executable. Compare precisely against this QSA-OFF 355.311327tok/s run **only if logs actually show `qsa-union active`**; otherwise ON merely requested, not activated. Any TDR or device loss is a reason to stop, preserve dump and not retry. GPU memory already ~94424 MiB in OFF path, and QSA activation may change buffers; this has a real driver-timeout risk. Do not jump to 128k IQ4 or resume original `-Stage Remaining`; that script retries case08. Reassess after the QSA ON run, before considering 128k context-only smoke with QSA OFF.

No changes made to C++ patches, driver, BIOS/UMA or WDDM TDR registry.

## Post-reboot Vulkan IQ4 64k/60k QSA-ON paired with QSA-OFF — 2026-11-03

**PASS: actual QSA UNION active and no TDR on 60,000-token full real-text PP in 64k context. But important ADLX clock-state transition makes the ~+0.8% PP comparison provisional and confounded.**

User ZIP `20261103-192525-644-bench-vulkan-b12032-ctx65536-384a52ae061f.zip`; raw ZIP is not committed. Matched comparison is immediately prior **QSA-OFF** 64k/60k run `20261103-191514-805-bench-vulkan-b12032-ctx65536-32a9841dae75.zip` (see preceding section). Same Windows session, same model/input hash/binary, ctx65536/p60000/b2048/ub1024/f16 KV, no warmup, single native repetition. Only intended independent variable: QSA UNION flag, with MIN_KV=32768 on ON; environmental drift may remain.

| Metric | QSA OFF | QSA ON |
| --- | ---: | ---: |
| Native PP throughput tok/s | **355.311327** | **358.089891** |
| Native prompt `avg_ns` | 168865992700 | **167555693600** |
| PP elapsed s | 168.866 | **167.556** |
| Claimed speed delta (unreplicated) | baseline | **+0.7820%** |
| ADLX max VRAM MiB | 94424 | **94578** |
| High GPU-use samples >=95% | 83/103 | **82/103** |
| High GPU-use mean clock MHz | 2827.012 | **2847.780** |
| High GPU-use mean VRAM clock MHz | **999.940** | **904.134** |
| High GPU-use mean power W | 119.554 | **111.476** |
| Max observed GPU temp C | 81 | **78** |
| P-MODE | Performance start/end | Performance start/end |
| Native status | OK / exit0 | **OK / exit0** |

ON run details:
- Run ID `20261103-192525-644-bench-vulkan-b12032-ctx65536-384a52ae061f`; 2026-11-03 19:25:26.502–19:28:57.542 JST; total wrapper duration **211.040 seconds** including model load.
- Native b12032 `c4ddd239b`; binary SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, original Unsloth IQ4_XS Ple16 GGUF 93682576992 bytes (full GGUF hash not recomputed); same Japanese ANLP `nlp-survey-ch3-d31-b1.txt` source SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`. `-c 65536 -p 60000 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16 -t 4`. `Status=OK`, exit0, 1 native JSON row, no run/parse errors, ADLX exit0 and 103 samples.
- Environment: `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `GGML_VK_QSA_UNION_STATS=0`, `QWEN4EXP_QSA_GATHER=0`. Stderr contains both `qsa-union fallback: query count, selection size or KV threshold` and **`qsa-union active (r6), source=mask-compact, group=64, path=1, Br=16, Bc=64, groups=16, capacity=32768, min_kv=32768, scratch=81801472 bytes`**. Thus actual activation is confirmed for some work, but this single line does not tell the exact activation timestamp or fraction of kernels using UNION.
- P-MODE was `Performance` both ends with `PModeChanged=false`. ADLX performance classification is consistent (`HighLoadSampleCount=82`, `AverageGpuPowerW=111.476 W`, `PowerClass=Performance-like`). GPU clock mean at high load ~2848MHz, VRAM clock mean ~904MHz, peak 78C, peak memory 94578MiB. RDP session. Background check `PartialCoverage`, `PossibleNoise=null`: **do not infer a quiet system**.
- **Crucial intra-run state change** around **19:27:23 JST**: at 19:27:21 GPU 100%, GPU clock2806MHz, VRAM1000MHz, power120W, VRAM94365MiB, temp78C; at 19:27:23 GPU99%, GPU clock2832MHz, VRAM900MHz, power110W, VRAM94482MiB, temp73C; at 19:27:25 GPU100%, GPU clock2861MHz, VRAM834MHz, power106W, VRAM94482MiB, temp72C. Thereafter through ~19:28:53, GPU still ~99–100%, VRAM clock typically ~793–868 MHz and power ~101–108W with GPU core clock ~2850–2870MHz; no reset. Within ON high-load samples, 46/82 have VRAM clock <=900MHz; early high-load mean before 19:27:27 is ~992.9MHz VRAM / 119.1W, late high-load mean from 19:27:27 onward ~827.5MHz VRAM / 104.9W. The OFF paired run had high-load mean 999.94MHz VRAM with no comparable sustained drop.
- The transition occurs during the timed long PP, approximately a minute-plus after it began. **Do not equate the transition timestamp to exact `min_kv=32768` QSA activation**: QSA active stderr has no timestamp and the token-position evolution is not independently measured. It is a correlation to investigate, **not proof that QSA caused the clock change**. GPU time vs tokens is non-linear.
- ON max VRAM usage `94578 MiB` vs OFF `94424 MiB`: +154MiB. The ON activation line reports 81801472 bytes of QSA scratch, but this is not a direct one-to-one explanation of ADLX total or delta, which includes other allocations/residency and samples. The earlier failed 128k QSA ON reached `97130 MiB`. Thus 64k QSA ON success alone does not clear the 128k problem, and QSA ON is **not generally broken**.
- Compared speed +0.782% is a single unreplicated observation with different observed VRAM clock regimes; **not evidence of a stable QSA speedup**. No controlled confidence interval or clock-normalized performance estimate.

**Recommended gating:** Do NOT automatically relaunch 12-case `-Stage Remaining` (will reattempt 128k IQ4). After this success, the most informative next dimension is **context/memory** with QSA forced OFF, rather than blindly increasing PP length with QSA ON. If user accepts bounded risk, begin with **`-c 131072 -p 256` QSA-OFF/no-warmup smoke** and ADLX: this tests 128k context allocation while avoiding QSA long-context active path and sustained compute. This deliberately does not yet test full 126253 tokens. Require stable P-MODE/desktop/monitor and no other GPU job; stop if a new driver timeout occurs. Then reconsider 8k PP at 128k context vs more precise measurement of QSA-ON VRAM clock state. Original full 128k case remains deferred. No code, driver, BIOS/UMA or TDR registry changes made.

## Post-reboot Vulkan IQ4 128k-context 256-token smoke — 2026-11-03

**PASS for a *short* 256-token model-load/PP smoke at the formerly failing full `-c 131072`, with QSA UNION explicitly disabled and no warmup. Not a pass for 128k sustained PP.**

User ZIP `20261103-193555-852-bench-vulkan-b12032-ctx131072-20f1c22e11fa.zip`, contains conditions/result/native JSON/stderr/ADLX. Raw archive is not stored in the repository.

| Item | Verified observation |
| --- | --- |
| Run | `20261103-193555-852-bench-vulkan-b12032-ctx131072-20f1c22e11fa` |
| Start/finish JST | 2026-11-03 19:35:56.6926739 → 19:36:35.1528258; wall **38.46 sec** |
| Model | Original Unsloth IQ4_XS PLE16 (GGUF file 93682576992 bytes, wrapper metadata); native `model_size=93671551580` |
| Executable | Vulkan b12032 `c4ddd239b`, SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, Clang20.1.8 |
| Input | Same `nlp-survey-ch3-d31-b1.txt`, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, slice=head |
| Native command | `-c 131072 -p 256 -n 0 -d 0 -r 1 --delay 0 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --no-warmup` |
| QSA | `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_MIN_KV=32768` (inert while OFF), `GGML_VK_QSA_UNION_STATS=0`, `QWEN4EXP_QSA_GATHER=0`. No `qsa-union active` log. |
| Native PP | `n_prompt=256`, one repetition, `avg_ns=646646300`, `avg_ts=395.888757 tokens/s`, stddev=0 because 1 sample |
| Result | `Status=OK`, exit 0, 1 native row, no run/parse exception, no Vulkan stderr fault |
| ADLX | Exit0, **19** samples at 2-sec cadence; max **94932 MiB GPU memory (~92.71 GiB)**; max GPU utilization **21%** (0 samples >=95%); no performance-class inference possible. GPU clock ~2900MHz and VRAM clock 1000MHz during tail of load, GPU temp up to **38 C**; power around55W during allocation/prep |
| P-MODE | Performance start and finish; `PModeChanged=false`, no PModeWarnings |
| Background / RDP | Named-process CPU coverage Complete, PossibleNoise=false, 0.013% sampled; RDP session, remote-like monitor; no native device loss |

ADLX memory chronology: initial 479MiB at 19:35:57 → 28735 MiB at 19:35:59 → 59230 MiB at 19:36:01 → 89950 MiB at 19:36:03 → **90659 MiB from ~19:36:05 through 19:36:31**, then **94932 MiB at final 19:36:33 sample**. Thus an important late memory-residency/scratch transition is sampled, but *only one sample* at the maximum, and no heavy PP phase. The output does **not** prove that the whole 128k long-context working set is resident/stable.

Comparators, with caution because independent runs:
- 32k/256 smoke peak `90648 MiB`
- 64k/256 smoke peak `93002 MiB`
- 128k/256 smoke peak `94932 MiB` (**+1930 MiB** over 64k/256)
- 64k/60000 PP QSA-OFF peak `94424 MiB`
- 64k/60000 PP QSA-ON peak `94578 MiB`
- Earlier **failed** 128k/126253 PP QSA-ON peak `97130 MiB` (**+2198 MiB** vs current 128k smoke).

Do not infer precise physical 96GiB UMA free capacity from `98304 - 94932`: the driver, Windows budget, GPU mapping and ADLX memory accounting do not directly convert to available headroom. Short 128k PP performance (~396tok/s) is **not comparable** with long PP throughput.

**Interpretation:** After reboot, device works at c131072 with 256 real tokens under QSA-OFF. The prior GPU engine TDR must be tied to an additional condition beyond merely choosing `-c 131072` and loading the full model: e.g. increased PP batch/workspace/residency, deeper context processing, QSA ON, or an intermittent driver/scheduler/memory pressure condition. Success of *a single* short smoke cannot rule out intermittent faults at allocation alone.

**Next bounded diagnostic (proposal only):** Prefer **`-c 131072 -p 2048 -b 2048 -ub 1024 -r 1 --no-warmup` QSA UNION OFF** with same model and document, not a jump to 8k or 126253 tokens. This exercises full measurement batch/ubatch memory patterns while limiting length, temperature and duration. Watch ADLX memory jump (and potential ~96GiB pressure), P-MODE, WER, and desktop; stop at first fault. This test is still risky: max memory 94932 MiB in the short smoke, and a different PP batch size may allocate more. Do not make unsafe claims that 2048-token run is guaranteed stable. Only evaluate any larger 128k PP if this staged test passes. Keep original 12-case run interrupted (7 PASS, 1 TDR, four not attempted), and do NOT relaunch `-Stage Remaining`, which retries failed Vulkan IQ4 128k case08.

No changes to C++ patches, driver, BIOS/UMA, TDR registry or memory allocation policy.
