# Gate HIP-TRACE-1 — ROCm/HIP 64k FA host metadata instrumentation (2026-11-07)

**State: b12148 Windows gfx1151 build and 1024-token trace-ON smoke PASS (2026-11-07). 64k KV49152 matching and trace-OFF A/B still pending.** New source remains default-OFF and does **not** change the Flash Attention mathematical algorithm, kernel launch dimensions, K/V tensors, memory copies or GPU synchronization.

Branch `investigation/r6-rocm-pp-fa-trace-20261107` branched from `investigation/r6-pp-fa-mask-rgp-20261105`. All old b11908 / b12013 / b12038 binaries and the Vulkan benchmark worktree are preserved.

## 1. What was implemented

- File: `ggml/src/ggml-cuda/fattn.cu` inside `#if defined(GGML_USE_HIP)` only, immediately before the selected FA backend path dispatch.
- Off by default. Set `GGML_HIP_FA_TRACE=1` to log a line per **host-side GGML_OP_FLASH_ATTN_EXT invocation**, not one per low-level HIP GPU dispatch.
- Optional `GGML_HIP_FA_TRACE_KV=49152` and `GGML_HIP_FA_TRACE_LAYER=19`. An unset filter allows all. **Select KV first without a layer filter** to discover exact graph names and any layers whose Q name lacks a predictable `Qcur-<layer>`.
- Each line has `fa_id` (monotonic host FA call count, across all KV/layers), `matched` (filtered sequence), `host_us` (monotonic CPU timestamp relative to first *logged match*, not absolute wall clock), device, `KV=K->ne[1]`, `N=Q->ne[1]`, `layer` derived from `Qcur-N` in Q tensor name or `-1` if absent, selected FA backend path `mma_f16/tile/vec`, `suffix_scan_candidate` derived from the same MMA condition, `kv_max_hint` and head and sequence dimensions, raw Q/dst names. All logged fields are host metadata.
- Limit **256 matching events**, truncation explicitly reported (no giant log); all calls continue unmodified after the logging limit.
- No extra `hipEvent*`/device synchronization, no readback, no benchmark model/input modifications. The `ggml_cuda_flash_attn_ext` code performs the same existing best-kernel selection once and then follows the same dispatch switch.
- **Important**: this *does not* produce an RGP Event ID nor capture a GPU timestamp, and HIP does not support Vulkan's RGP user debug markers. In CUDA/HIP graph-captured execution, one host graph-build call need not correspond to one GPU replay. Exact GPU event attribution requires its own calibration Gate. Never claim HIP Event423==Qcur19 based on `fa_id` alone.

### Example `stderr.log` record (illustrative, not an observed run)

```text
evox2_hip_fa_trace_v1 fa_id=... matched=... host_us=... device=0 KV=49152 N=1024 layer=19 kernel=mma_f16 suffix_scan_candidate=1 kv_max_hint=... q_heads=... k_heads=... seq=... q_name="Qcur-19 (view) (permuted)" dst_name="..."
```

## 2. Build (isolated output; Windows user performs the build)

Source root is the **diagnostic worktree**:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git status --short
git fetch origin
git switch -c investigation/r6-rocm-pp-fa-trace-20261107 --track origin/investigation/r6-rocm-pp-fa-trace-20261107
# If the local branch already exists, switch to it instead. Preserve any local changes.
git status --short

& C:\TheRock\build\.venv\Scripts\Activate.ps1
.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-pp-fa-trace-r6 -Parallel 4 -AmdGpuTarget gfx1151
$bin = '.\build-rocm-pp-fa-trace-r6\bin\Release\llama-bench.exe'
& $bin --version
& $bin --help
Get-FileHash $bin -Algorithm SHA256
```

Do not use the unsafe broad `-RunBackendTest` suite on Windows HIP gfx1151. Check b/source revision, expected backend, device gfx1151, and TheRock runtime from `--version`, `--list-devices`, build manifest and stderr. The new build *may* have version b12133 or later based on this source branch; do not label it b12038. The new version includes subsequent source changes and thus is **not source-identical** to the baseline b12038 used for prior HIP RGP samples.

In the **Git-ignored** `tools/evox2/benchmark/configs/local.psd1`, append to the existing `Builds` hashtable:

```powershell
R6RocmFaTrace = @{
    BinDir          = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-pp-fa-trace-r6\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

## 3. Minimal tests — smoke then 64k host trace

Plan: [qwen38-r6-rocm-hip-fa-host-trace-64k-20261107.psd1](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-hip-fa-host-trace-64k-20261107.psd1)

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-hip-fa-host-trace-64k-20261107.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# First very small run: confirm e.g. fa_id=... KV=1024 N=1024 and correct Qcur name.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant hip-trace-smoke-code -StopOnError

# After smoke and RGP/PP safety checks, one run each, separately:
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant hip-trace-code-64k -StopOnError
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant hip-trace-literature-64k -StopOnError
```

Use exactly the same `llama.cpp` input SHA `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` and novel SHA `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`, model `UnslothPle16` IQ3 PLE16, no-warmup, 61777 head, ctx65536, UBatch1024, F16 KV, MTP OFF, Gather OFF, P-MODE Performance. **Do not run both 64k experiments at once**. The RDP panel is not needed for this first metadata Gate.

After the run ends, inspect the saved `stderr.log` only; live `Get-Content -Wait` is unnecessary. Filter:

```powershell
Select-String -Path '<run_dir>\stderr.log' -Pattern 'evox2_hip_fa_trace_v1' |
    Select-Object -First 80
```

**Acceptance:**
1. Stable b/source/backend and no TDR/OOM/exception; HIP device detected.
2. Smoke prints at least one FA trace when enabled; no trace when `GGML_HIP_FA_TRACE` unset.
3. At 64k at least one `KV=49152 N=1024 layer=19 kernel=mma_f16` line per corpus; **layer23** if present. If this is absent, inspect the full Q names/KV metadata before changing the code; do not silently call RGP Event423 layer19.
4. Data records grouped from the same original inputs and versions; code/lit layer19/23 matched by `KV/N/layer` not by host sequence count.
5. This validates host-side *graph op metadata only*, not GPU timing or RGP event mapping.

Compare the two saved stderr files:

```powershell
.\tools\evox2\benchmark\Compare-HipFaTrace.ps1 `
    -CodeStderr 'C:\PATH\CODE-RUN\stderr.log' `
    -LiteratureStderr 'C:\PATH\LITERATURE-RUN\stderr.log' `
    -OutCsv '.\hip-fa-kv49152-code-literature.csv'
```

## 4. Where the code input may spend more PP time

The earlier b12038 RGP-on full prompt calculation is about **167.49 seconds (code)** versus **164.43 seconds (novel)**, ~**3.06 s longer for code**. Yet the one **unmatched-KV/layer** HIP Event423 in code was **98.000ms**, literature **98.447ms**, a **0.447ms longer FA for the novel**. This is not contradictory: full PP totals include **all layers/UBatches**, GDN, Lightning Indexer/top-k, GET_ROWS, MoE expert MM/FFN, CONCATS, quantized GEMMs and CPU launch/graph overhead; the chosen FA event is one small component. Other FA calls might also have different timings.

**Do not attribute the 3.06s to a specific kernel from these two trace screenshots.** For a bounded actual bottleneck comparison:
- Reopen the saved pair `llama-bench-20261107-131042215.rgp` (code) and `llama-bench-20261107-132609191.rgp` (literature).
- In each RGP **Overview → Most expensive events**, collect top ~15 dispatches including GPU Duration, full shader name, Event ID, and grouped context. Also retain **Event timing** screenshots around `Event423` and prominent MoE/Indexer/GET_ROWS dispatches; same HIP 181200/512 profiles already exist. This is a **sample window**, not full-run attribution.
- Compare durations of like-for-like **kernel families** and event order; distinguish `MUL_MAT_ID` expert kernels, `GET_ROWS`, `CONCAT`, Indexer, GDN, and FA. Determine whether any non-FA kernel in code is consistently slower. A single top-dispatch screenshot cannot establish aggregate full-run PP contributions.
- If necessary, create an independent **per-UBatch GPU category timing** design rather than interpret host `host_us` gaps as GPU kernel durations. The current FA source instrumentation is deliberately **not** an invasive all-op timer.

## 5. Subsequent HIP event↔layer correlation Gate (not implemented here)

HIP RGP Event ID is unrelated to `fa_id`. Matching source tensor names and identical query shape alone prove **a host op exists** but not that Event423 represents it. Determine whether the sequence of RGP `flash_attn_ext_f16` events within the 512-dispatch window and the trace order, plus a stable PP UBatch anchor, uniquely identify target Qcur19; if not, investigate a **separate** opt-in layer-targeted GPU timing or dispatch-ordinal probe with an explicit instrumentation overhead/correctness gate.

A minimal first milestone is **KV/layer metadata and correspondence between model graph calls**, not "ROCm exact RGP matching PASS". A new GPU synchro or broad backend test is **not authorized by this Gate**.

## 2026-11-07 14:14 JST — Windows ROCm b12148 HIP-TRACE smoke PASS

**First real device validation complete** on Radeon 8060S gfx1151; this confirms source compiles and `GGML_HIP_FA_TRACE=1` actually produces expected per-layer metadata. **64k KV49152 pair and standalone default-OFF A/B have NOT yet been tested.**

- Build provenance `(rocm)evox2-build(1).json` (41,752B), SHA256 `843eca9119875572080d2d4b6ccb25c105e8990d04756eca0ad49fdc6e6d0996`. Branch `investigation/r6-rocm-pp-fa-trace-20261107`, source commit **`5066464c3ddc4264a8fa34141581b74846b49d88`**, `BuildIdentity.Status=Verified`, Windows clang23, TheRock ROCm10.0.0, `AMDGPU_TARGETS=gfx1151`. New build dir `build-rocm-pp-fa-trace-r6`. Runtimes including `amdhip64_7.dll`, rocBLAS, hipBLASLt and `gfx1151` data staged from unified TheRock tree with hash verification.
- Executable `llama-bench.exe` **b12148/`5066464c3`**, sha256 `9f8c90e99cc0f9c08f0851647fdbff5c0252d1835ffea61d2703c859bab52521`; `ggml-hip.dll` sha256 `8c8751f8055f4f18212a414ebed77bbca27823eed5018f6cfccc3de2e9a08138`. ROCm device detected 110456MiB. Version/device probe ExitCode0.
- Build manifest `Dirty=true` is caused by **four unrelated untracked legacy Vulkan mask config PSD1 files**, not a modified tracked source file; built-source identity reports Verified. Preserve those local untracked files rather than deleting them casually.
- Smoke `20261107-141333-584-bench-rocm-b12148-ctx2048-396815d87e05.zip` (25,253B), SHA256 `c02fe1d3fea5480646f6ffeb1e7523bbe3dd40050b72bedc6164f8c8dea6e5ab`; `Status=OK`, `ExitCode=0`, `NativeRowCount=1`, ctx2048, prompt head1024, physical UBatch1024, batch2048, no warmup, generation0, KVf16, input code SHA `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`, Gather OFF, P-MODE Performance unchanged.
- stderr confirms `evox2_hip_fa_trace_v1 enabled=1 filter_kv=-1 filter_layer=-1 note=host_FA_submission_not_RGP_dispatch_id max_matched=256`: the **smoke intentionally disables the 49152 filter**. **12/12 FA calls recorded**, `fa_id=1..12`, `matched=1..12`; layers **Qcur-3,7,11,15,19,23,27,31,35,39,43,47**, each with `KV=1024 N=1024 kernel=mma_f16 suffix_scan_candidate=1 kv_max_hint=1283 q_heads=24 k_heads=2 seq=1`. Example layer19 `fa_id=5`, layer23 `fa_id=6`. Host-relative `host_us` reaches `58908` at layer47; **not** GPU duration; actual timed PP `avg_ns=2576185200` (~2.576s, 397.487 tok/s) is diagnostic-on and not benchmark-comparable.
- No program errors, no indicated HIP trap/TDR, backend correctly loaded from the diagnostic build directory. ADLX had only zero qualifying high-load power samples (short smoke), so **power-mode ADLX consistency not evaluated**, but authoritative IP3 P-MODE remained Performance.
- `conditions.json.Environment.GGML_HIP_FA_TRACE=1`; KV filter unset; correct. The trace output showed real newline-separated entries, quoted Q names and numeric metadata; no parser-blocking issue evident.
- `HIP_PATH` inherited an existing 7.2 path in the process environment, but build manifest confirms **staged ROCm10.0** for this isolated binary. Keep manifest/hashes and validate actual backend path for 64k rather than inferring the runtime from this environment variable alone.

**Next:** Run **only** `hip-trace-code-64k` first; verify actual `KV=49152 N=1024 layer=19/23`, same model/Gather0, no trace truncation/failures; then execute `hip-trace-literature-64k`. Compare stderr files using `Compare-HipFaTrace.ps1` and confirm identity matches. This does not by itself prove that the old HIP RGP Event423 was exactly layer19; event correlation remains a distinct Gate. The ~3s full-PP opposite-to-FA observation should be investigated through existing RGP **Most expensive events** screen(s), not by interpreting host timestamps as GPU times.

## 2026-11-07 14:24 JST — 64k code KV49152 trace PASS

- Original native ZIP: `20261107-142123-521-bench-rocm-b12148-ctx65536-65f6dbd15ee9.zip`, **SHA256 `f1fc2000eeead177ce467d95eb13f6e4079478f2b824408f3733f2ae6593ade8`**, bytes **30,828**. Contains one code-input run, source build **b12148/`5066464c3`**, same isolated `ggml-hip.dll`, correct code input SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`.
- Result `Status=OK, ExitCode=0, NativeRowCount=1`, ROCm/Radeon 8060S gfx1151, ctx65536, head 61777, UBatch1024, Batch2048, F16 KV, no generation, `NoWarmup=true`, gather0/MTP flags0; P-MODE `Performance→Performance`, `PModeChanged=false`, ADLX high-load power **120.147W** `Consistent=true`; no diag truncation/error in `stderr.log`.
- `stderr.log` startup: `evox2_hip_fa_trace_v1 enabled=1 filter_kv=49152 filter_layer=-1 note=host_FA_submission_not_RGP_dispatch_id max_matched=256`.
- Exactly **12/12** host FA records for `KV=49152` `N=1024`, all `kernel=mma_f16 suffix_scan_candidate=1 kv_max_hint=2051 q_heads=24 k_heads=2 seq=1`. `fa_id=565..576` corresponding to **`Qcur-3,7,11,15,19,23,27,31,35,39,43,47`** in order. **`Qcur-19 = fa_id569, matched5, host_us4199, dst_name=node_2741`; `Qcur-23 = fa_id570, matched6, host_us5054, dst_name=node_3277`**. Host timestamps 0..10028us describe nonblocking host submission only, **NOT** 10ms of GPU FA work.
- Native `avg_ns=153003932200` = **153.0039322s**, `avg_ts=403.760865 tok/s` (single profile/trace-on run). This is **not** directly comparable with older RGP-active `368.839 tok/s` because binaries/diagnostics differ, nor does it establish a code-vs-literature speed difference without the next matching run.
- **Conclusion:** new default-OFF diagnostic is validated for identifying the 12 FA graph nodes at the target `KV49152/Qcur-19/23` in code. It does **not** validate that older RGP Event423 was `Qcur-19`; host id and RGP GPU Event id are different numbering systems, and code/literature identity matching only becomes possible when the literature host trace is recorded.

**Next: run only `hip-trace-literature-64k` in the same b12148 diagnostic build**, then compare both `stderr.log` records with `Compare-HipFaTrace.ps1`. No new RGP, GPU kernel instrumentation, or rebuild needed at this stage. Optional existing b12038 HIP RGP **Most expensive events** screenshots remain the least-expensive way to investigate why unprofiled full PP slightly favors literature.

## 2026-11-07 14:35 JST — 64k code/literature KV49152 host trace pair PASS

**Gate HIP-TRACE-1 completed for the 64k code/literature host metadata pair.** Each original archive has exactly 12 `evox2_hip_fa_trace_v1` records at KV49152, N1024 for layers 3,7,11,15,19,23,27,31,35,39,43,47. All matched records show `kernel=mma_f16`, `suffix_scan_candidate=1`, `kv_max_hint=2051`, `q_heads=24`, `k_heads=2`, `seq=1`; q_name/dst_name and filtered index and fa_id coincide one-for-one. This establishes **host-side FA op identity and path equality at the target KV**, not HIP RGP GPU Event423↔Qcur19 binding and not mask equality.

| Raw ZIP provenance | Code | Literature |
|---|---|---|
| ZIP | `20261107-142123-521-bench-rocm-b12148-ctx65536-65f6dbd15ee9.zip` | `20261107-143156-059-bench-rocm-b12148-ctx65536-41a0d4bb3911.zip` |
| ZIP SHA256 | `f1fc2000eeead177ce467d95eb13f6e4079478f2b824408f3733f2ae6593ade8` | `20b2dedccb537a336b2afa9267df82d12eabc37350b5a2523c955f67ddbba8c2` |
| Archive bytes | 30828 | 31034 |
| Input SHA256 | `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` | `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143` |
| Native PP time | **153.0039322s** | **150.7452838s** |
| Native PP speed | 403.760865 tok/s | 409.810499 tok/s |
| Result | OK / ExitCode0 | OK / ExitCode0 |
| P-MODE | Performance→Performance | Performance→Performance |
| ADLX high-load mean | 120.147 W | 120.055 W |
| RGP active? | **No** | **No** |

- Both use same **b12148 / `5066464c3`**, ROCm/gfx1151 runtime, same GGUF model, prompt61777/head, ctx65536, batch2048, ubatch1024, threads4, K/V f16, generation0, NoWarmup, all-GPU offload, MTP OFF, Gather OFF and identical environment diagnostics `GGML_HIP_FA_TRACE=1`, `GGML_HIP_FA_TRACE_KV=49152`. No trace truncation, no P-MODE warnings/recorded resets; no background high-load interference flagged.
- Host FA call IDs from **565..576** in both corpora, `fa_id=569 / matched=5 / q_name=Qcur-19 (view) (permuted) / dst=node_2741`, and `fa_id=570 / matched=6 / Qcur-23 / dst=node_3277`. All remaining layer IDs and node names also agree.
- Relative `host_us` at Qcur-19: code `4199`, literature `5314`; Qcur-23 code `5054`, literature `6198`. These numbers measure the **CPU-side submission/logging timeline within a single observed host graph**, not the HIP kernel duration or FA cost, and must **not** be interpreted as literature's FA being slower by ~1.1ms.
- **Literature PP was 6.049634 tok/s or +1.4983% faster**, finishing **2.2586484s sooner** than code in these one-run each diagnostic-ON b12148 results. This reproduces the prior ROCm direction but is not a repeated-distribution statistical test and does not prove whether FA/GDN/MoE/Indexer/other kernels account for the difference.
- For comparison the separate **b12038 HIP RGP same-index** snapshots had one FA MAIN **98.000337ms code / 98.447049ms literature** (literature 0.447ms slower), but **exact KV and layer are not verified for those snapshots and build/source differ**. A single FA event need not predict whole-PP duration.

**Conclusion:** At KV49152 the FA invocation structure and backend selection are identical, despite content-dependent sparse mask differences observed in the Vulkan investigation. The longstanding opposite-direction PP throughput is *not explained by any different FA kernel choice / n_kv_max hint at this exact point*. This does not exclude content-dependent FA timing elsewhere or different effective per-tile work.

**Next discriminating work (no need to re-run 64k host trace):** compare existing b12038 HIP RGP **Overview → Most expensive events** for code `llama-bench-20261107-131042215.rgp` and literature `llama-bench-20261107-132609191.rgp` (top 15–20 kernel durations, same Dispatch range 181200/count512, optionally total time by kernel family). If a non-FA kernel dominates consistently in code, plan a narrower repeated profiling or per-UBatch category timing study. It is a sampled window, not a complete PP attribution. For *strict* RGP KV49152/Qcur-19 equivalence, a separate HIP host-to-GPU launch correlation Gate remains **not implemented**; do not label old Event423 as layer19 just because the new host trace includes that layer.

**Status note:** The initial **default-OFF vs ON performance-neutrality A/B** is still untested. The safe claim is "trace-ON code/literature structural match PASS," not "all diagnostics validated for zero overhead."

## 2026-11-07 — MMQ source-only follow-up (no new source patch)

- [ROCm/MMQ dense-vs-MoE source audit](R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md), based on the **exact b12038/d321e7ff3** source used by the historical HIP RGP profiles (MMQ/CUDA source blob SHA identical to this investigation branch).
- Both `GGML_OP_MUL_MAT` and `GGML_OP_MUL_MAT_ID` can call the same `mul_mat_q<type,J,fallback,prec>` kernel. The GPU name by itself does not establish expert routing.
- The observed RGP types 20=IQ4_NL / 22=IQ2_S, J32, fallback false, Q8 activation precision; five repeated triplets contain two IQ2_S plus one IQ4_NL event each. A routed-MoE FFN interpretation is consistent with model graph source but requires a verified event-to-op mapping.
- In the MMQ **ids-present** path, `mm_ids_helper` creates per-expert `expert_bounds`, and MMQ skips tiles when `jt*J >= expert_bounds[e+1]-expert_bounds[e]`. For J32, differences in assignment histogram can alter the count of effective tiles (approximately `sum_e ceil(m_e/32)`). This is a testable causal *mechanism*, **not evidence that the measured data used more expert tiles in code**.
- In the matched 512-dispatch HIP capture, the 15 visible `mul_mat_q` events sum 76.349ms code vs 73.035ms literature, while FA Main Event423 is 98.000ms vs 98.447ms. The 5th MMQ triplet reverses direction, and the capture is not a full PP attribution.
- Next first step **without running GPU experiments**: existing RGP Event timing around IDs 91/97/105 and 465/471/479, especially HIP dispatch grid (x,y,z) and neighboring `mm_ids_helper`/activation-quantize events. If insufficient, propose a separate **default-OFF host-only GGML_HIP_MMQ_TRACE** diagnostic with `ids != nullptr`, weight/dst names, shape, selected J, and graph op. Do not claim HIP RGP Event ID↔host ID equivalence. No MMQ C++ code changes have been made for this follow-up.
