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
