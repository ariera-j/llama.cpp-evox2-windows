# Gemma 4 31B: v1.0.0 vs #31323 Vulkan PP FA RGP capture (2026-11-21)

## GPU timestamps resolve PP improvement to Global Attention FA (2026-11-21, ~19:47–20:00 JST)

**The source-level cause is now isolated to the Global Attention FA node family (not an individual CM1 optimization subfeature).** User ran the existing `GGML_VK_PERF_LOGGER=1` and `GGML_VK_PERF_LOGGER_FREQUENCY=1` in **both original v1.0.0 diagnostic b12366 and #31323+#32415 diagnostic b12369** with identical model/input/flags. Both `Status=OK`, `ExitCode=0`, 29,379-token Japanese paper, `-c32768 -b2048 -ub512` F16 KV, Radeon8060S UMA64GB, P-MODE Performance. No RGP capture or gate pause. The two logs contain 60 `Vulkan Timings:` graph blocks each; **exclude the first two Q2 blocks**, leaving 58 PP blocks, with 50 SWA and 10 Global FA entries per graph.

| Sum of 58 PP graph GPU node times | Original b12366 | #31323 port b12369 | Change |
| --- | ---: | ---: | ---: |
| Global FA `HSK512` (10 nodes/graph) | **378.076 s** | **88.715 s** | **-289.362 s, 4.26x faster** |
| SWA FA `HSK256` (50 nodes/graph) | 6.646 s | 13.036 s | +6.390 s, 1.96x slower |
| Other GPU nodes, incl. GEMM | 71.374 s | 70.697 s | -0.677 s, essentially unchanged |
| **Total node timing sums** | **456.096 s** | **172.448 s** | **-283.648 s** |

These timestamp sums decompose almost exactly the *previous uninstrumented* same-input PP wall-time delta: **456.595 s -> 171.975 s (saves 284.620s)**. Exact G48 (Q512 / graph-KVMAX24576): SWA `FA_KV1536` mean per node **2.266 ms -> 4.356 ms** (~1.92x slower), while Global `FA_KV24576` mean per node **1086.730 ms -> 268.563 ms** (**4.05x faster**). This agrees in direction with the earlier RGP SWA dispatch difference **2017.884µs -> 4293.574µs**. In the old GPU node total, Global FA contributed **82.9%**; in the port, **51.4%**.

**Caveats:** Timestamp logging changes GPU submission and synchronization, so the *instrumented PP wall rates* 63.95 and 157.95 tok/s are **not comparable to uninstrumented clean throughput**. The 58-node GPU sums are derived from printed per-op `N x avg_us = sum_us` and the per-graph `Total time` (rounded), not full shader RGP pipeline counter results. **Global FA runtime reduction is empirically established, but the per-shader reason (Br16 vs Br32, Q-in-regs, wave occupancy) remains to be proven**. Windows proprietary AMD driver forbids new flipped FA via #32415. No source changes needed for the GPU timestamp method.

Archives privately retained:
- Original `20261121-195235-883-cli-vulkan-b12366-ctx32768-82eb7837459e.zip` SHA256 `2f4a0451a8869560461084744b8fc6babdb34528888bbb2a21208e0f0343566f`.
- Port `20261121-194719-044-cli-vulkan-b12369-ctx32768-bbdc9feb73db.zip` SHA256 `aa1e857206152a5ea132b23b316c5724e1952217e397f795fc1c342523c0fab4`.

[Full calculation, provenance and KV-dependent Global FA time table (private experiment repository)](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-vulkan-perf-logger-global-vs-swa-fa-32k.md).

## Paired G48 #31323 capture: short-KV SWA CM1 regresses despite faster overall PP (2026-11-21 ~19:32 JST)

**#31323 diagnostic capture PASS:** `20261121-193009-279-cli-vulkan-b12369-ctx32768-f469ccd61ea7.zip` (raw ZIP private; SHA256 `1a095bcd951863b0ddeb362cf06cccb6518961c85bcf465d6737ba05cb059671`). Ported diagnostic build **b12369**, executable source commit `471738b83`, `Status=OK / ExitCode 0`, 29,379 Japanese paper prompt tokens, identical Gemma4 31B QAT/Q4_0, F16 KV, b2048 ub512, UMA64GB, Performance P-MODE. Stop at `EVOX2_PP_G48_Q512_KVMAX24576_FA60` (`2:17.499078`), **`RESUMED`** (`2:28.292122`) after **10.793 s**, no TIMEOUT/TDR. Whole-PP 160.00 tok/s **includes the pause** and is not a clean performance measurement (nominal adjusted rate ~170.0 tok/s, for sanity only). RGP file in screenshot `llama-cli-20261121-193238668.rgp`.

Paired screenshot values at **identical first SWA-class FA** `EVOX2_FA_I0_Q512_KV1536_HSK256 FLASH_ATTN_EXT node_30`, **same labeled CM1 pipeline and workgroup dispatch** `flash_attn_f32_f16_aligned_cm1` / `vkCmdDispatch(32,32,1)`:

| RGP event | Original-v1 G48 (b12366) | Port b12369 G48 | Observation |
| --- | ---: | ---: | --- |
| **CM1 GPU dispatch only** | **2017.884 µs** | **4293.574 µs** | port **2.128x longer** (single captures) |
| `EVOX2_FA_I0` whole labeled group | 2305.651 µs | 4580.051 µs | port ~1.99x longer |
| FFN gate Q4 matmul shown | ~4356.6 µs | ~4347.7 µs | nearly unchanged |
| FFN up Q4 matmul shown | ~4531.6 µs | ~4498.1 µs | nearly unchanged |

**Do not generalize one SWA CM1 event to all FA kernels.** `KVMAX24576` is the **graph maximum**, but **captured FA KV=1536** (SWA, 50/60 FA nodes). This profile does **not show** any `HSK512` long-KV Global Attention FA (10/60 FA nodes). Clean paired whole-PP speed was independently **64.34 → 170.83 tok/s**, so the likely substantial speedup must arise in other work not captured by this first SWA FA (Global Attention is the leading candidate, not yet measured).

Source interpretation: #31323 extends existing CM1 shader (`flash_attn_cm1.comp`) to support **32-Q-row tiles on UMA RDNA3/4 where shared memory permits**, with a fallback to the 16-row tile and **`q_in_regs`** register-resident query caching in AMD PP. New flipped FA is **disabled on AMD proprietary Windows driver** by #32415 and is not the observed labeled pipeline. Same RGP dispatch geometry is consistent with a common 16-row Br for this HSK256 shape (not a proof: verify specialization parameters). The reason that the 1536-KV path slows down could be register pressure/occupancy, query caching or other new shader costs; **not yet isolated by source analysis**.

**Recommended next:** measure the actual `HSK512`, FA-KV~24576 Global Attention node to resolve the contradictory whole-PP vs first SWA findings. Avoid blindly raising RDP capture count to hundreds given the earlier AMD driver timeout. The built-in **`GGML_VK_PERF_LOGGER=1`** Vulkan timestamp feature logs per GGML node and includes FA `q(...)`, `k(...)`, `v(...)`, `m(...)` shapes. This can survey all SWA and Global FA nodes without extended RGP capture, although it changes synchronization and must **not** be used as an uninstrumented throughput comparison. Code source: `ggml-vulkan.cpp` initializes `GGML_VK_PERF_LOGGER` and emits `Vulkan Timings:` blocks via `vk_perf_logger::print_timings`. Do a small timing smoke first before using the full 32k context. Subsequently use targeted RGP for specific long-KV GPU dispatch timing if needed.

[Full paired RGP report, screenshots interpreted (private experiment repository)](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-vs-fa31323-rgp-g48-swa-16dispatch.md).

## First stable deep-PP RGP baseline captured at KV24576 (2026-11-21 ~19:16 JST)

**Original v1.0.0 diagnostic b12366 PASS:** one manual RGP 16-dispatch trace at graph `EVOX2_PP_G48_Q512_KVMAX24576_FA60`. This confirms that late-context pause/release and **actual RGP capture** can be completed without a driver timeout using the now-validated matching-prefix procedure.

Run archive (locally kept): `20261121-191115-138-cli-vulkan-b12366-ctx32768-15228ae6a84b.zip` / SHA256 `0389dc6e165602d64257a3d9ee36085493fa10dc72a9a6009d57e9c450d2155f`. `Status=OK / ExitCode 0`, 29,379 prompt tokens; `PAUSED` at log time `5:24.426.677` and **`RESUMED`** at `5:33.590.012` (**9.163 s pause**), no `TIMEOUT`. End-of-run PP 63.10 tok/s includes the pause and is not a clean performance value. RGP 2.7.0.32 screenshot title `llama-cli-20261121-191649965.rgp` (binary not provided).

In Event timing the recorded early FA event reads:

```text
EVOX2_PP_G48_Q512_KVMAX24576_FA60 submit 0
  EVOX2_FA_I0_Q512_KV1536_HSK256 FLASH_ATTN_EXT node_30
    flash_attn_f32_f16_aligned_cm1 (32,32,1)
      vkCmdDispatch(32,32,1)  2017.884 us
EVOX2_PP_G48_Q512_KVMAX24576_FA60 submit 1
  ... quantized FFN matmul ...
```

**Important: the captured FA is SWA / head dimension 256 with its own KV1536, NOT global attention with KV24576.** The graph's KVMAX24576 aggregates FA nodes and must not be taken as the captured dispatch's KV. Consequently this trace alone cannot explain the observed 2.66x whole-PP speedup; first compare the same early SWA FA with the **ported #31323 diagnostic** at KV24576, then target actual `HSK512` / long-KV global-attention FA for a causal mechanism study. The visible `EVOX2_FA_I0` has the same Q512/KV1536/HSK256 shape as the prior early-G4 screenshot; observed single-shader times fluctuate, so do not infer context-depth speedups from these two independent dispatches.

**Next** use the optimized RGP diagnostic at `EVOX2_VK_PP_RGP_PAUSE_KV=24576`, prefix `C:\llama-build\rgp-pp\ported-kv24576-16` **identical in both PowerShell windows**, RDP 16 dispatch with Disable client timeout ON and counters/instruction tracing OFF. Verify `RESUMED` and executable commit before attempting to compare captures. No new C++ implementation is required for this same-FA capture.

[Detailed original-v1 private RGP notes](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-pp-rgp-kv24576-16-dispatch-success.md).

## Manual resume + RGP 16-dispatch capture PASS (2026-11-21, ~18:06–18:14 JST)

The original v1.0.0 diagnostic b12366 (`51bb379eb`) was re-run at `EVOX2_PP_G4_Q512_KVMAX2048_FA60` with the correctly matched fresh prefix `C:\llama-build\rgp-pp\original-kv2048-16-retry` in both shells. **stderr confirms `PAUSED` at 0:11.677398 and `RESUMED` at 0:27.357863**, with no `TIMEOUT` line (gate duration **15.680 seconds**). RDP's manual **16-dispatch** capture completed promptly; user RGP 2.7.0.32 screenshot shows command-buffer marker `EVOX2_PP_G4_Q512_KVMAX2048_FA60 submit 0` and nested `EVOX2_FA_I0_Q512_KV1536_HSK256 FLASH_ATTN_EXT node_30`. **Inference also completed `Status=OK`, ExitCode=0**, all 29,379 input tokens and final G58 marker.

Run ZIP `20261121-180602-392-cli-vulkan-b12366-ctx32768-15228ae6a84b.zip` (private; SHA256 `d8ce3e2f2e9efcb154ef201764d8a350aa745407df3e630c2d980a3d1a3c5e6b`). PromptEvalMilliseconds=471570.47, 62.30 tok/s, including 15.68-second pause — **not** a normal benchmark result. The screenshot does not expose the nested shader-dispatch timestamp; the FA label's displayed group duration cannot be treated as a precise individual dispatch. A proper A/B FA timing requires matching actual `FA_KV`, `Q`, `HSK`, FA ordinal and shader pipeline in the two traces, **not merely graph maximum KVMAX**.

**This validates the full profiling workflow** on original-v1: debug labels → GPU drain → matching .ready → RDP manually armed → matching .go → `RESUMED` → .rgp captured → successful inference. It also confirms the prior 600s timeout was caused by the wrong .go prefix, not an inherent deadlock in the capture gate.

### Next matched late-PP capture

Use the **same 16-dispatch** settings (RDP's `Disable client timeout` ON; counters and instruction tracing OFF) at KVMAX **24576** on the original-v1 diagnostic first and then on #31323/#32415 diagnostic:

- Original: unique prefix `C:\llama-build\rgp-pp\original-kv24576-16`
- Port: unique prefix `C:\llama-build\rgp-pp\ported-kv24576-16`
- In each run, set `EVOX2_VK_PP_RGP_PAUSE_PREFIX`, `EVOX2_VK_PP_RGP_PAUSE_KV=24576`, and `EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS=120000`; confirm the helper uses **the exact same prefix**, then arm RDP capture, immediately press Enter, and verify `RESUMED` rather than `TIMEOUT`.
- Use one profiling engine at a time and keep the same model/input, F16 KV, 512-token ubatch, driver and RDP settings. Use different diagnostic executables/build manifests as appropriate. Retain both .rgp files; initial screenshots of Event timing with same `FA_I/Q/FA_KV/HSK` are sufficient for a first comparison. If a single 16-dispatch profile fails to include useful FA, raise to 32 or 64 only after the short capture proves stable.

[Complete private validation report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-pp-rgp-manual-resume-16-dispatch-success.md).

## Pause-gate mismatch identified from screenshots (2026-11-21, ~17:32 JST)

The user shared a screenshot of `C:\llama-build\rgp-pp` **after** the 16-dispatch RGP test:

| Filename | File modification time | Role |
| --- | --- | --- |
| `original-gate-only.ready` | 17:19 | stale .ready from preceding pause-only test |
| `original-gate-only.go` | **17:32** | .go written for preceding prefix during new test |
| `original-kv2048-16.ready` | **17:32** | .ready of the **actual new RGP test** |
| `original-kv2048-16.go` | **ABSENT** | correct release signal never written |

The user's narrative confirms they pressed Enter in a PowerShell resume window, while RDP showed **Status: Capturing**, a pending 16-dispatch request. These filenames and times provide strong evidence that PowerShell② used the **old `-Prefix ...\original-gate-only`**, creating a `.go` that the **current** `original-kv2048-16` pause gate could not see. Previous run logs indeed recorded **`TIMEOUT` after 600,000ms**, not `RESUMED`. As a result the RDP request could not collect dispatches until the program auto-resumed at timeout; capture then completed. An RDP screenshot showing a ~5-minute wait is approximate; runtime log establishes the gate waited **600 seconds**.

This **explains the manual resume mismatch directly**, without needing any further driver or profiling hypothesis. It does not fully explain the *separate earlier* AMD GPU timeout from the longer capture. Note 16-dispatch capture + `Disable client timeout ON` both differ from the earlier failed RGP run; their individual effects remain unproven.

### Safeguard added to `Resume-VulkanPpRgp.ps1`

Both diagnostic branches now make PowerShell② **fail closed before creating .go** when:

- The selected `.ready` is older than `-MaxReadyAgeSeconds` (default **300 seconds**, configurable for unusual long setups);
- Another **newer** `*.ready` exists in the same directory, suggesting the selected prefix belongs to an old test.

The script prints the selected full `.ready` and expected full `.go`, validates before showing the RDP instructions, then validates **again after Enter**. UTF-8 with BOM retained. **No C++ changes or rebuild needed; pull the branch in the worktree**. Future test: use **one fresh unique prefix variable** for both the llama-cli environment and the resume script.

Example:

```powershell
# PowerShell 1: before Measure-LlamaCli.ps1
$prefix = 'C:\llama-build\rgp-pp\original-kv2048-16-retry'
Remove-Item "$prefix.ready", "$prefix.go" -ErrorAction SilentlyContinue
$env:EVOX2_VK_PP_RGP_PAUSE_PREFIX = $prefix
$env:EVOX2_VK_PP_RGP_PAUSE_KV = '2048'
$env:EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS = '120000'

# PowerShell 2 (use exact same prefix)
$root = 'C:\llama-build\llama.cpp-evox2-v1-pp-rgp'
& "$root\tools\evox2\benchmark\Resume-VulkanPpRgp.ps1" -Prefix 'C:\llama-build\rgp-pp\original-kv2048-16-retry'
```

In PowerShell②: `<prefix>.ready` appears, RDP Capture profile is armed, then Enter is pressed immediately, and stderr should show `RESUMED` rather than `TIMEOUT`. No .rgp is expected before allowing dispatches to proceed. A single correct 16-dispatch/early-KV retry is enough to validate the handshake, then capture paired deep KV24576 old/ported diagnostic builds.


## First successful 16-dispatch RGP: manual release was TIMEOUT, not .go (2026-11-21)

**Confirmed RGP capture and marker visibility on original v1.0.0** in Radeon GPU Profiler v2.7.0.32. User's screenshots show `EVOX2_PP_G4_Q512_KVMAX2048_FA60 submit 0` / `submit 1` and nested `EVOX2_FA_I0_Q512_KV1536_HSK256 FLASH_ATTN_EXT node_30` -> `flash_attn_f32_f16_aligned_cm1` / `vkCmdDispatch(32,32,1)` **2181.694 µs**. This is ONE old-v1 SWA-class FA GPU dispatch, not a whole PP graph or an A/B comparison. RDP 3.5.0.18 screenshot shows **Disable client timeout ON**; user reports capturing **16 dispatches** rather than the previous larger count. These two changes were simultaneous, so the earlier GPU timeout's cause is still not uniquely attributed.

User archive `20261121-173218-451-cli-vulkan-b12366-ctx32768-15228ae6a84b.zip` (local only, SHA256 `38cde0a99cbb5261486fa02a3c8f907bd3c8bbcbc3a407c9b9ad14efb2fa89bc`) has **`Status=OK`, ExitCode 0**, same Gemma 4 model, 29,379 paper tokens, original-v1 diagnostic b12366. However, `stderr.log` recorded `PAUSED` at G4 at **0:11.590**, then **`TIMEOUT` at 10:11.600** (600 seconds), and **no `RESUMED`**. `PP=27.78 tok/s` includes the entire 10-minute pause and **must not be compared with baseline performance**. Screenshot RGP filename `llama-cli-20261121-174233951.rgp` (~17:42:33) is just after the ~17:42:31 automatic gate release, consistent with the profiler **capturing only when the timeout released GPU dispatches**.

### Immediate procedural correction (no new C++ build)

The original helper text was ambiguous: **clicking Capture profile ARMS the capture; it does not mean the profile is complete.** The app is stalled until a `.go` file is created. Once the RDP capture request is armed, **immediately switch to the helper's PowerShell window and press Enter — do not wait for an .rgp file or completed capture before pressing Enter**. Then check llama-cli stderr for **`RESUMED`** within a second or two. If it shows `TIMEOUT`, manual gate release was NOT verified.

For the next KV2048 / 16-dispatch trial, use a fresh prefix and set `EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS=120000` instead of 600000, to avoid an unnecessary 10-minute stall if `.go` is not observed. Keep **Disable client timeout ON**, Collect counters OFF and instruction tracing OFF. The PowerShell helper was updated in both diagnostic branches to emphasize immediate release and print `Go-file written` rather than claiming process resume.

Once an RGP capture and `RESUMED` occur in the **same** run, continue to KV24576 with the same small 16-dispatch capture, first on old-v1 then on the #31323 diagnostic build. Inspect corresponding **Q, FA-KV, HSK, FA ordinal, shader name**, and per-dispatch GPU durations. No renewed 32k performance benchmarking is needed.

[Complete private capture analysis and log timeline](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-pp-rgp-16-dispatch-capture-and-auto-timeout.md).

## Pause-only + open RDP smoke PASSED (2026-11-21 17:22 JST)

**The pause gate is independently validated with Radeon Developer Panel open but NO RGP capture.** Original v1 diagnostic b12366, unchanged executable (`51bb379eb`, SHA256 `7d73d9940da98a280acf795a119ae931c1f69c031b9bf63296c99327061c83eb`), processed the same 29,379-token paper **OK / ExitCode 0**. Log archive (kept privately): `20261121-171342-857-cli-vulkan-b12366-ctx32768-15228ae6a84b.zip`, SHA256 `e7d4e274f2535e8768a23097f4444487e45a012f5bef43986dd3a90b5847ae58`.

At `EVOX2_PP_G48_Q512_KVMAX24576_FA60`, the pause log occurred 5:24.145 and the resume 5:35.965, **11.820 s** apart. The run continued through G49...G58 and completed PP with **467.363s / 62.86 tok/s**. The preceding marker-only no-pause run took **454.654s / 64.62 tok/s**, only ~12.71s faster; nearly all elapsed PP time difference corresponds to intentional pausing. Thus marker code and pause/release are **not sufficient** to reproduce the prior TDR when RDP is merely open. A live RGP capture or an intermittent driver issue is the remaining likely difference, not a confirmed root cause.

**Next:** original-v1 branch only, very short manual RGP capture at **KV2048**, **16 dispatches**, *Collect counters*, *Enable instruction tracing*, *Delay capture* all OFF, **Auto capture=None**, **Disable client timeout ON** in RDP Connections. Configure RDP *before launching* the test application. Arm `Capture profile` while stopped, release promptly using the helper, and check the .rgp file and visible `EVOX2_PP_` command-buffer marker. Expand to 32 or 64 dispatches only if necessary and stable. Then use KV24576, followed by the #31323 diagnostic branch.

[Private test data, timings and three-way isolation table](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-pp-rgp-pause-only-smoke.md).

## Markers-only smoke after restart PASSED (2026-11-21 17:04 JST)

The user rebooted EVO-X2 and ran the **original v1.0.0 PP diagnostic binary** (b12366, commit `51bb379eb`) on the same 29,379-token Japanese paper with `EVOX2_VK_PP_RGP_MARKERS=1` and `GGML_VK_DEBUG_MARKERS=1`, but **no pause and no Radeon Developer Panel capture**. Raw archive: `20261121-165633-701-cli-vulkan-b12366-ctx32768-15228ae6a84b.zip` (private, SHA256 `abce179bbeb61f79146a6342d3f0019bc6ac41aa67cc39e6cdc9dfe95e7e09d6`).

- **Result: `Status=OK`, ExitCode 0**, full 29,379-token prompt, 1 generated token, `PP=64.62 tok/s`, `PP time=454.654 s`. Historical original-v1 Vulkan PP 64.34 tok/s (previous paired A/B). 1-token output means TG speed is **not measured**.
- `stderr.log` shows `EVOX2_PP_G1` through `G58`, including `G48_Q512_KVMAX24576_FA60` and final `G58_Q195_KVMAX29440_FA60`, with no `PAUSED`/`RESUMED` and no driver error. Thus **the marker path itself can complete this whole workload**.
- Build identity and backend verified; same paper input hash, F16 KV, ubatch512, UMA64GB, Performance P-MODE. No ADLX or OS samples requested. `conditions.json` currently retains `GGML_VK_DEBUG_MARKERS=1` but not the custom `EVOX2_` switch; the logger proves the custom switch was active.
- **Next critical test:** enable the pause gate at **KVMAX24576** but do **not** run any RGP capture. Resume promptly using the helper from another PowerShell window and check for full completion. This exactly isolates the gate itself from the earlier G48/capture/TDR incident. **If stable, only then try RGP with 16 dispatches at KV2048** and RDP's `Disable client timeout` enabled. Do not repeat 512-dispatch long capture first.

[Detailed private aggregate analysis](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-pp-rgp-markers-only-smoke.md).

## First EVO-X2 capture trial: AMD driver timeout after pause/resume (2026-11-21)

**Status: capture path NOT yet validated; do not repeat the same long capture automatically.** The first run used the **original v1.0.0 diagnostic branch**, not the #31323 optimized branch. Log: `20261121-144034-630-cli-vulkan-b12366-ctx32768-15228ae6a84b`, executable commit `51bb379eb`, clean source. The helper displayed `EVOX2_PP_G48_Q512_KVMAX24576_FA60`; stderr confirmed `PAUSED` at ~5:29, `RESUMED` ~5:59 (29s later), and a 24576-token progress checkpoint. Then the llama-cli process exited ~22s later with decimal **3221226505 = 0xC0000409**; AMD Bug Report Tool reported **GPU driver timeout**. The benchmark was `FAILED` with no final PP/TG; do NOT treat as a throughput result. The resume helper exited normally because it only writes the `.go` file, not because llama-cli succeeded. RGP trace creation / dispatch count / counters settings were not supplied and remain unverified.

`0xC0000409` is Windows *Fail Fast*, whose particular cause cannot be determined without an exception subcode/dump. AMD's timeout dialog strongly suggests a GPU TDR, but it is **not proved** whether the trigger was a long RGP capture, stale/disconnected RDP capture target after the 29s CPU-only pause, `vkDeviceWaitIdle` at the pause gate, or the diagnostic shader/driver interaction. There is no justification to blame the #31323 optimization (the failing build was original v1.0.0).

### Conservative isolation order

1. **Markers only, no pause, no RDP capture:** keep `EVOX2_VK_PP_RGP_MARKERS=1` and `GGML_VK_DEBUG_MARKERS=1`, but remove `EVOX2_VK_PP_RGP_PAUSE_PREFIX`, `EVOX2_VK_PP_RGP_PAUSE_KV`, `EVOX2_VK_PP_RGP_PAUSE_GRAPH`; run short or 32k and confirm it completes. If this fails, investigate instrumentation independent of RDP.
2. **Pause/release without capture:** set prefix, `PAUSE_KV=2048`, resume with helper while RDP capture remains inactive, verify success. This isolates the `device.waitIdle()` + file gate from GPU profiling.
3. **Small manual profile:** with RDP connected **before launching** llama-cli, enable **Disable client timeout**; set Profiling capture mode Dispatch, `Auto capture mode=None`, **Render op count 16** (optionally 32 after successful smoke), Delay capture OFF, Collect counters OFF, Enable instruction tracing OFF. Pause at `KVMAX>=2048`, arm `Capture profile` while paused, release with the helper. Verify a valid trace and labels.
4. Only after step 3 is stable, repeat the **small** capture at `KVMAX>=24576`. Increase dispatch count only if necessary, in small steps (16→32→64), never assume 512 dispatches are harmless at deep context.

If another driver timeout appears, **stop repeated captures** and inspect Windows System/Application event logs (Display 4101, WER 1000/1001, driver LiveKernelEvent 141) and the RDP output log. Keep the system's default TDR settings; do **not** increase `TdrDelay` as a first-line workaround. Preserve any existing RGP or RGD artifacts. AMD docs: [RDP initial setup and Disable client timeout](https://gpuopen.com/manuals/rdp_manual/initial_setup/), [Profiling capture settings](https://gpuopen.com/manuals/rdp_manual/features/), [RGD/TDR explanation](https://gpuopen.com/manuals/rgd_manual/help_manual/).

## Purpose and isolation

Two **separate diagnostic branches**, preserving the production benchmark binaries:

- Original v1.0.0 core + EVO-X2 docs/tools: `investigation/gemma4-v1-pp-rgp-20261121`, based on `baseline/v1.0.0-docs-tools-only-20261115` (original engine build b12363).
- v1.0.0 plus upstream Vulkan FA #31323 and AMD Windows guard #32415: `investigation/gemma4-fa31323-pp-rgp-20261121`, based on `investigation/gemma4-v1-fa31323-20261121`.

The diagnostic adds **no shader, tensor or numerical changes**. It modifies only `ggml/src/ggml-vulkan/ggml-vulkan.cpp` and adds this guide and a UTF-8-with-BOM PowerShell resume helper. With the environment feature switch unset, the inference/capture path remains unchanged. Use **new build directories**: do not overwrite the verified 64.34 vs 170.83 tok/s binaries.

## Diagnostic environment and markers

Enable before starting llama-cli:

```powershell
$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
```

The feature enables Vulkan `VK_EXT_debug_utils` when available and prefixes the **command-buffer** submit label (not only the queue label). Example (values illustrative, actual values written by the executable):

```text
EVOX2_PP_G48_Q512_KVMAX24576_FA60 submit 0
  EVOX2_FA_I23_Q512_KV24576_HSK256 FLASH_ATTN_EXT node_...
    flash_attn_..._cm1 (..,..,..)
      vkCmdDispatch(...)
```

- `G`: sequential **Vulkan PP graphs with FA Q≥64** recorded within this process; starts at 1. This is **not** an RDP dispatch index.
- `Q`: max `q->ne[1]` across PP FA graph nodes.
- `KVMAX`: max `k->ne[1]` across PP FA graph nodes. **This is not guaranteed to equal total consumed prompt tokens**; both RGP files must be matched using actual Q/KV and per-FA shape, not graph ordinal alone.
- `FA`: number of PP flash-attention nodes with Q≥64 in the graph.
- `I`: zero-based **FA ordinal within this Vulkan graph**; not an asserted physical Gemma layer ID. Match it alongside Q/KV/head dimension, especially when fusions or graph structure change.
- `HSK`: `q->ne[0]` (query-head dimension); Gemma 4 31B uses 256 for SWA and 512 for global attention in this workload; **confirm which values actually appear in the profile**.
- The nested shader label is the selected Vulkan pipeline, whose identity should also be confirmed via RGP Events/Overview. The AMD Windows guard #32415 keeps the flipped FA shader disabled on proprietary drivers by default.
- The diagnostic logs a `evox2 pp rgp: EVOX2_PP_G...` line for every such PP graph and `PAUSED` / `RESUMED` for the chosen graph. Do not treat those host print timestamps as GPU shader durations.

## Easier RGP capture at the same PP position: pause gate

Instead of repeatedly guessing dispatch timer/dispatch count, **arm manual dispatch capture while llama-cli is paused just before the target PP graph's first submission**, then release the gate. The gate waits for earlier GPU work to finish (`device.waitIdle()`) before writing `<prefix>.ready`.

Additional environment variables:

| Variable | Example | Behavior |
| --- | --- | --- |
| `EVOX2_VK_PP_RGP_PAUSE_PREFIX` | `C:\llama-build\rgp-pp\original` | writes `original.ready`, waits for `original.go`; directory must already exist |
| `EVOX2_VK_PP_RGP_PAUSE_KV` | `24576` | pause once at the first PP FA graph with `KVMAX >= 24576` |
| `EVOX2_VK_PP_RGP_PAUSE_GRAPH` | `0` | optional: use exact `G` instead of KV threshold; positive graph number **takes precedence** |
| `EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS` | `300000` | wait timeout, 5min default; timeout **continues the run** and logs TIMEOUT |

The gate is opt-in: it requires markers enabled, a nonempty pause prefix, and a positive KV threshold or graph ID. It fires only once per process, and removes any stale `.go` file before generating `.ready`. Disable other background inference loads. The pause and debug labels are **profiling only**: do not compare total PP duration or TG speed from these runs with non-diagnostic benchmark numbers.

Example original-v1 setup in PowerShell window A (adjust worktree and the model/input keys in local.psd1):

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-v1-pp-rgp'
$prefix = 'C:\llama-build\rgp-pp\original'
New-Item -ItemType Directory -Force -Path (Split-Path $prefix) | Out-Null
Remove-Item "$prefix.ready", "$prefix.go" -ErrorAction SilentlyContinue

$env:EVOX2_VK_PP_RGP_MARKERS = '1'
$env:GGML_VK_DEBUG_MARKERS = '1'
$env:EVOX2_VK_PP_RGP_PAUSE_PREFIX = $prefix
$env:EVOX2_VK_PP_RGP_PAUSE_KV = '24576'
Remove-Item Env:EVOX2_VK_PP_RGP_PAUSE_GRAPH -ErrorAction SilentlyContinue
$env:EVOX2_VK_PP_RGP_PAUSE_TIMEOUT_MS = '600000'
Remove-Item Env:GGML_VK_FORCE_FA_FLIP -ErrorAction SilentlyContinue

& "$root\tools\evox2\benchmark\Measure-LlamaCli.ps1" `
    -LocalConfig "$root\tools\evox2\benchmark\configs\local.psd1" `
    -LlamaCli "$root\build-vulkan-pp-rgp\bin\Release\llama-cli.exe" `
    -ExpectedBackend Vulkan -ModelKey Gemma4_31B -InputKey '32k' `
    -Context 32768 -GenerationTokens 1 -Threads 4 -Batch 2048 -UBatch 512 `
    -GpuLayers 999 -CpuMoe 0 -FlashAttn auto -KvType f16 `
    -Fit on -PromptCacheMiB 0 -Reasoning off -Temperature 0.2 -TopP 0.8 `
    -UmaLabel 64GB -NoAdlxMonitor `
    -ExtraArgs @('-tb','4','--ctx-checkpoints','0t','--seed','1234')
```

In **PowerShell window B**, enter before starting or while window A is running:

```powershell
& 'C:\llama-build\llama.cpp-evox2-v1-pp-rgp\tools\evox2\benchmark\Resume-VulkanPpRgp.ps1' `
    -Prefix 'C:\llama-build\rgp-pp\original'
```

Window B detects `.ready`, shows the exact `G/Q/KVMAX/FA`, then asks you to click **Capture profile** in Radeon Developer Panel with **Dispatch** capture mode (try 16 dispatches first; cautiously increase to 32 or 64 only if stable and needed). Once RDP is armed, press Enter in window B. `.go` releases the graph. Keep `Auto capture mode=None` for this gate-driven workflow; do **not** additionally specify Dispatch timer or Dispatch range.

Repeat for the #31323 branch with a **different prefix** (`...\ported`) and new build directory (`build-vulkan-pp-rgp`). Prefer matching by KVMAX, FA ordinal/head dimension and shader labels, not a fixed dispatch number.

**Preflight:** Test once with a small positive KV threshold (e.g. 2048) to verify `.ready` + `.go` + visible RGP labels; then do the late ~24k or ~28k target. If the reported `KVMAX` does not increase as assumed, use `EVOX2_VK_PP_RGP_PAUSE_GRAPH` after inspecting stderr and match actual FA shapes.

## Capture caveats

- The AMD RDP Profiling UI documents **manual Dispatch capture** and **auto Dispatch range / Dispatch timer**. **Marker-driven start/end is documented for RRA raytracing, not RGP profiling**; the PP labels alone do not automatically trigger an RGP capture.
- New RDP 3.5+ includes `RadeonDeveloperPanelCLI` with `--rgp-auto-capture dispatch:start:count`, but that still uses dispatch numbers and may not be available on the user's installed version. The pause gate is independent of this version.
- A queued RGP manual capture must be armed before the `.go` release. Different RDP/driver versions may arm capture differently; verify with a short test instead of assuming an exact automatic trigger.
- Prefer first captures **without Collect counters**, enough to inspect Events > Event timing, selected FA shader name, per-dispatch duration and wave occupancy. Collect counters only on a later targeted profile if supported. Do not confuse group-level total GPU duration with per-shader time.
- Profiled old-v1 and #31323 branches will have separate commit hashes; their baseline source differs intentionally. The only added common functional code should be the **identical** PP diagnostic implementation, and the optimized branch retains #31323 and Windows #32415.
- Neither branch is validated on the EVO-X2 Windows compiler/RGP yet; report any build errors before treating the marker labels as confirmed. Do not add instrumentation to the verified benchmark branches.

## References

- [Prior verified Vulkan TG marker approach](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/gemma4-31b-v1-rocm-20261116/docs/evox2/GEMMA4-V1-VULKAN-TG-RGP-2026-11-16.md): queue-only labels were not visible in RGP; command-buffer submit labels were.
- [AMD RDP Profiling capture modes](https://gpuopen.com/manuals/rdp_manual/features/)
- [AMD RDP CLI arguments](https://gpuopen.com/manuals/rdp_manual/radeon_developer_panel_cli/)

## Build fix: newer Hugging Face UI assets rejected by the old v1.0.0 asset validator (2026-11-21)

An EVO-X2 RGP diagnostic build stopped at `[1020/1061] Provisioning UI assets`, **not** during Vulkan C++ compilation. `ggml-org/llama-ui` had no `b12369` matching UI release, so `scripts/ui-assets.cmake` fell back to `latest`; the downloaded UI uses modern `_app/immutable/*` files, whereas this older v1.0.0 script requires `bundle*.js`, `bundle*.css` and `workbox*.js`. This is unrelated to FA/PP markers.

The two dedicated RGP branches now add `-DLLAMA_USE_PREBUILT_UI=OFF` to `tools/evox2/build/Build-Vulkan.ps1` **alongside the existing `-DLLAMA_BUILD_UI=OFF`**. (The latter alone does not prevent the downloaded-asset path.) These branches need no server Web UI for llama-cli RGP captures. Production benchmark branches are unchanged.

If the failed build has already downloaded incompatible UI assets, delete **only** that build directory's `tools\ui\dist` and optional UI stamp. After `git pull --ff-only` in the corresponding diagnostic worktree, re-run the same Build-Vulkan.ps1 to reuse all other compiled objects. Example for the optimized diagnostic branch:

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-fa31323-pp-rgp'
$build = Join-Path $root 'build-vulkan-pp-rgp'
Remove-Item -LiteralPath (Join-Path $build 'tools\ui\dist') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $build 'tools\ui\.ui-stamp') -Force -ErrorAction SilentlyContinue

git -C $root pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'git pull failed' }
& (Join-Path $root 'tools\evox2\build\Build-Vulkan.ps1') -BuildDir $build `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

If you have not pulled the updated branch yet, an equally safe workaround is passing `-ExtraCMakeArgs @('-DLLAMA_USE_PREBUILT_UI=OFF')` to the existing build script, after clearing stale UI dist.

A successful UI-less build will generate an empty built-in Web UI table for llama-server; no effect on the Vulkan kernel implementation. Windows marker build and capture are still unverified until the next executable smoke/RGP trace.
