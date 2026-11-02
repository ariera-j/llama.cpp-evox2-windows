# COMMON-005 r6 ROCm selected-K/V gather prototype — 2026-11-02

**Status: SOURCE IMPLEMENTED ON RESEARCH BRANCH; NOT BUILT OR TESTED ON WINDOWS.** This is not an accepted performance improvement and is not a production/default profile. CPU-bound RGP B follow-up is recorded in [the RGP log](R6-COMMON005-RGP-2026-11-02.md).

## Scope and source changes

- On this research branch, `Evox2.Benchmark.psm1` includes `QWEN4EXP_` in `Get-Evox2RelevantEnvironment`. This is required: otherwise Gather ON/OFF can share a condition fingerprint even when the matrix variant differs. Check `conditions.json` now includes `QWEN4EXP_QSA_GATHER=0/1` as applicable.
- Branch `research/rocm-qsa-gather-20261030`, derived from r6-based `main`; no upstream update, public tag or published stable b11908 build changed.
- `src/models/qwen4exp.cpp` and `src/models/models.h`: opt-in `QWEN4EXP_QSA_GATHER=1` **only**, with default OFF (unset, `0`, or any other value => OFF).
- Narrow graph eligibility: `cparams.flash_attn`, one token, exactly one sequence, `n_kv / 4 >= n_sel`, `n_kv <= 2^24`, valid single-stream original KQ mask, F16 K/V and contiguous full-head-per-cell cache layout.
- First time a compact graph is **built**, opt-in mode emits one flushed stderr record `qwen4exp_common005_v1 graph_built=compact n_kv=... n_sel=...`. Verify this exists in `output.log`/`stderr.log` for the 32k ON gate; its absence means Gather eligibility was not demonstrated. This graph-build cue is **not proof of GPU dispatch/execution** and is never emitted in OFF mode.
- The active branch of `build_qsa_sel` directly computes selected cells from `pool_idxs[top_k]` plus `tail_idxs` and a per-cell validity mask, without constructing `n_kv`-wide `TOP_K_MASK` or the existing full `SET_ROWS` scatter graph. Non-Gather branch remains untouched.
- The selected pool score is valid only when nonnegative/finite, reflecting `lightning_indexer` rectified score; `-inf` invisible pools are masked. Tail sentinel `n_kv` is masked. Invalid entries use **safe source index 0** (never `n_kv`) when passed to `ggml_get_rows`, with additive F16 bias `-65504`. For valid rows bias is 0. The `n_kv <= 2^24` gate ensures integer indices are exactly representable through the F32 graph intermediate. This numerical masking choice is **still subject to native correctness validation**, including cases with invalid pools/tails.
- `build_attn_qsa`: after normal K/V cache writes, view each F16 cache cell as a row containing every KV head, gather selected rows through `ggml_get_rows`, reshape compact K/V and run ordinary `build_attn_mha(..., n_kv_max=0)`. It casts F32 gathered tensors to F16 within the existing attention helper. A second sparse-mask compaction is not requested. Preserve the existing post-attention value unrotation.
- With `QWEN4EXP_QSA_GATHER=0`, **full old code path** still uses `build_qsa_sel`'s fused or unfused full-KV mask; graph eligibility checks are short-circuited. MTP ON was not tested or optimized: do not enable `QWEN4EXP_QSA_GATHER=1` in the server's MTP-enabled operating profile until verified. The gate itself does not inspect a global MTP enable flag; it is limited to one-token single-sequence graphs.

### Unresolved risks to test

1. New compact attention K/V width `n_sel = kpool*n_top_pool + (kpool-1)` includes the tail; this differs from r3's old fixed-width `top_k`. Confirm flash-kernel handling of non-multiple-of-256 widths (e.g. 2,051), F16 mask and actual cache strides on Windows gfx1151 before long runs.
2. `ggml_get_rows` of the F16 KV cell view returns F32 in this ggml version. The attention helper casts it to F16; this creates additional GPU work and could outweigh benefits at short context. Native build and RGP can confirm actual dispatch.
3. Unordered Top-K pools change the summation order relative to full-KV scan, so byte-identical outputs are not required; nevertheless, reference answers, output token counts, absence of NaNs and stability must match. ROCm output determinism is imperfect even at fixed seed.
4. Graph caching, first decoder steps, padded/invisible blocks and later memory growth require testing. The full-KV fallback is unchanged when ineligible. **If initial 32k Gather ON crashes/asserts or fails correctness, stop rather than running 64k+**.

## Windows build and validation sequence

```powershell
git fetch origin
git switch research/rocm-qsa-gather-20261030
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_rocm_common005_gather.py' -v

# TheRock ROCm 10.0 shell. Separate build location; NEVER -RunBackendTest.
.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-common005 `
  -Parallel 4
```

In ignored `tools/evox2/benchmark/configs/local.psd1` add a **new** entry in `Builds` and leave `CombinedROCm` and `R6RocmQsaRgp` untouched:

```powershell
R6RocmCommon005 = @{
    BinDir          = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-common005\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Adjust the directory to match the actual clone. Ensure the runtime artifact digest is Verified and records TheRock 10.0; build only when that SDK is active. Ensure model alias `UnslothPle16` and Inputs.`32k`/.`64k`/.`128k`/.`256k` are mapped locally, context fits and P-MODE Performance / UMA 96 GiB hold.

Plan: `tools/evox2/benchmark/configs/qwen38-r6-rocm-common005-gather-20261102.psd1`. This contains **three jobs**; do not run the entire matrix by accident. First `-PlanOnly` and verify cases, build and variants. Example:

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-common005-gather-20261102.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# 4k: Gather is ineligible. ON/OFF should behave like the old source.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob common005-fallback-smoke -StopOnError

# 32k: the first real-input activation gate, 64 output tokens.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob common005-activation-32k -StopOnError

# Only if both gates PASS, start with ONE 64k ABBA group.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob common005-long-abba -OnlyCase 64k -StopOnError
```

After reviewing 64k logs and answer correctness, conduct 128k and then 256k in **separate commands**, with identical ABBA OFF/ON/ON/OFF. The measurement plan keeps MTP OFF, fixed temp/seed/input, f16 K/V, resource monitor OFF (ADLX remains), RGP/SSE cues OFF and 60s cooldown. A binary built once from this exact commit must be used for both sides; do not compare the new ON with frozen b11908 as a controlled A/B. For acceptance use PP, TG, full eval time, output agreement, error logs, GPU clocks/P-MODE, and runtime DLL provenance.

**Safety:** no full `FLASH_ATTN_EXT` suite and no `Build-ROCm.ps1 -RunBackendTest` on gfx1151 Windows. No performance or stability result is claimed by this source commit.

## First native gate results — 2026-11-02, b12013

User-supplied artifacts: `(rocm-common005)evox2-build.json`, `20261102-212540-714-cli-rocm-b12013-ctx4096-3308053a6d6f.zip` (contains four complete run folders: 4k OFF, 4k ON, 32k OFF, 32k ON). These user-provided files are not added to Git.

- **Build: PASS**: `b12013 / f29592d6a`, branch `research/rocm-qsa-gather-20261030`, clean source, Clang 23, `gfx1151`. TheRock SDK 10.0.0 and HIP/BLAS DLLs+rocBLAS/hipBLASLt runtime data verified. `BuildIdentity=Verified`, `RuntimePolicy=TheRockUnified`, smoke version and device query OK. Broad backend test deliberately not requested. All four runs `RuntimeArtifactStatus=Verified`, same runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`; same CLI hash `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628`. All Performance P-MODE start/end; no P-MODE changes. Note the shell's inherited `HIP_PATH=C:\Program Files\AMD\ROCm\7.2\` appears in condition logs despite staged TheRock runtime; this is **not evidence** of mixed loaded DLLs given Verified artifact provenance, but retain for future runtime audits.
- **4k fallback: PASS** (163 prompt + 64 generated tokens, MTP OFF). OFF `20261102-212325-035`: PP **38.10**, TG **27.17**; ON `20261102-212540-714`: PP **199.69**, TG **27.37** tok/s. Normalized outputs and fingerprints are **identical** (`0b963884ea555ae070b56094d692516017c3537d22f2974032345e02d6fee43e`). Neither emitted the `graph_built=compact` cue, as expected. The PP difference is enormous for a short first-run workload and **cannot be attributed to Gather** (both paths ineligible); avoid treating it as a speed measurement, investigate only if reproducible in warmed matched runs.
- **32k activation: PASS (preliminary)** (29,557 prompt + 64 generated, MTP OFF). OFF `20261102-212706-619`: PP **489.42**, TG **24.41**; ON `20261102-213013-628`: PP **488.50**, TG **25.31** tok/s. Relative changes **PP -0.19% / TG +3.69%** single-run; not repeat-validated. ON emitted exactly one `qwen4exp_common005_v1 graph_built=compact n_kv=32768 n_sel=2051` cue, and OFF none. The cue establishes graph construction, not an RGP proof of GPU dispatch. Input and generated token counts match.
- **32k output caveat**: output fingerprints differ (`d6ec190d... ` OFF vs `7fd49955... ` ON), normalized text changes mainly `基づき` vs `応じて` and subsequent 64-token truncation boundary; no evident gibberish, assert or non-finite output in inspected logs. Prior ROCm same-seed output reproducibility is imperfect; **do not claim exact-output equality or mathematical proof of correctness**. The 4k output was byte-identical. Native logs contain the ordinary info-level `context does not support partial sequence removal` message, not an identified COMMON-005 error.
- **Outcome**: 4k+32k smoke and activation gates **PASS as an initial screening**, with one 32k run per condition. The implementation is still a prototype and **not approved for default ON**; source `f29592d6a` is the measured executable. **Proceed with only the 64k OFF/ON/ON/OFF ABBA job next**, analyze its correctness, PP/TG, runtime and activation before scheduling 128k or 256k. RGP/SSE console watching should remain OFF for ordinary performance runs. Keep the b11908 published binary untouched.

## 64k ABBA gate — 2026-11-02 (PASS; next 128k)

User upload `20261102-215353-365-cli-rocm-b12013-ctx65536-4514ac8e6f9d.zip` contains **four independent run folders in correct OFF/ON/ON/OFF order**. Actual input 61,789 tokens (`Inputs.64k`), 512 generated tokens in each, MTP OFF, F16 K/V, context 65,536. Same `b12013 / f29592d6a` patched CLI SHA256 `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628`; all `RuntimeArtifactStatus=Verified`, runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`.

| Order / ID | Gather | PP tok/s | TG tok/s | PP eval ms | TG eval ms | Total eval ms | ConditionId |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| A1 `20261102-213858-892` | OFF | 404.41 | 21.77 | 152,786.64 | 23,474.01 | 176,260.65 | `4514ac8e6f9d` |
| B1 `20261102-214401-900` | ON | 403.35 | 24.52 | 153,191.05 | 20,843.32 | 174,034.38 | `1ad01ba561dc` |
| B2 `20261102-214858-610` | ON | 403.01 | 24.60 | 153,320.11 | 20,774.67 | 174,094.79 | `1ad01ba561dc` |
| A2 `20261102-215353-365` | OFF | 402.91 | 21.83 | 153,356.48 | 23,404.54 | 176,761.02 | `4514ac8e6f9d` |
| OFF mean | OFF | **403.66** | **21.80** | **153,071.56** | **23,439.28** | **176,510.84** | |
| ON mean | ON | **403.18** | **24.56** | **153,255.58** | **20,809.00** | **174,064.59** | |

- **TG +12.66%** `(24.56 / 21.80) - 1`; per-token generation time declines ~45.87 → ~40.72 ms. For 512 generated tokens, TG eval is **2,630.28 ms shorter**; prompt eval is **184.02 ms longer**, so measured total PP+TG eval improves **~2,446.25 ms**. PP speed changes **−0.12%**, within the small variability of these runs.
- **Both independent ON runs are faster than both OFF runs**, with a narrow within-side spread (ON 24.52–24.60; OFF 21.77–21.83). This is stronger evidence than the prior single 32k +3.69% result, though no confidence interval or broad quality claim is implied. r3's historical 64k +10% ROCm Gather result is directionally consistent; do not cross-compare absolute speeds.
- Both ON stderr logs show one `qwen4exp_common005_v1 graph_built=compact n_kv=65536 n_sel=2051`; both OFF logs do not. This demonstrates appropriate graph-path eligibility and matches the separate A/B environment fingerprints. It is a host graph-build marker, not a GPU event.
- **Validity:** 4/4 `Status=OK`, exit 0; no encountered GGML assertion/fatal exception/abort. All runs remain Performance P-MODE start/end; `AdlxPModeConsistency.Consistent=True`, ~119.96–120.08 W high-load power (all Performance-like). Resource monitor OFF, ADLX monitoring ON. Start/end named-process background samples: A1 `PartialCoverage/PossibleNoise=null`; B1/B2/A2 `Observed/PossibleNoise=false`. Treat these as bounded observations, not proof of no external activity.
- **Output:** all four outputs are coherent Japanese summaries of the same technical document and retain the main topics (lexical-network, co-occurrence/PMI, surrounding-context approaches and evaluation document classification); 512 generated tokens completed. The four SHA256 output fingerprints are **all different**, including both OFF runs and both ON runs. Thus exact-text matching cannot be demanded from this known nondeterministic ROCm setting. No obvious severe semantic breakdown in inspected outputs; this is a smoke-level qualitative check, **not an exact-logit or full factual equivalence proof**.
- **Gate decision:** **PASS** 64k speed/stability/activation screen. Next run **only 128k** with the same frozen b12013 binary and existing matrix plan `-OnlyJob common005-long-abba -OnlyCase 128k -StopOnError`; review before 256k. No change to default OFF or public b11908. Defer capture-local CPU-bound RGP B investigation unless TG gain fails to track GPU gain at longer contexts.

## 128k ABBA gate — 2026-11-02 (PASS; next 256k)

User-supplied ZIP `20261102-223233-977-cli-rocm-b12013-ctx131072-479c75226db1.zip`, SHA256 `f9df2162caad7614b7dc53d8dc284d0abc4b1e1df87aedd7ca6ca120521f8`, includes **four complete independent run folders** in OFF/ON/ON/OFF order. Model Qwen3.8 Flash Next Unsloth IQ3 PLE16, MTP OFF, context 131072, **126,253 prompt tokens**, exactly 512 generated tokens each, f16 KV, `-b 2048 -ub 1024`. Same b12013/`f29592d6a` binary SHA256 `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628` in all four, `RuntimeArtifactStatus=Verified`, runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`.

| ABBA / RunId | Gather | PP tok/s | TG tok/s | PP eval ms | TG eval ms | Total eval ms | ConditionId |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| A1 `20261102-220402-423` | OFF | 300.86 | 17.53 | 419,643.31 | 29,142.98 | 448,786.29 | `479c75226db1` |
| B1 `20261102-221339-688` | ON | 300.50 | 22.67 | 420,146.92 | 22,541.10 | 442,688.02 | `595af4b84b4f` |
| B2 `20261102-222309-329` | ON | 300.42 | 22.76 | 420,251.85 | 22,453.27 | 442,705.12 | `595af4b84b4f` |
| A2 `20261102-223233-977` | OFF | 296.88 | 17.72 | 425,266.40 | 28,838.26 | 454,104.66 | `479c75226db1` |
| **OFF mean** | | **298.87** | **17.625** | **422,454.855** | **28,990.620** | **451,445.475** | |
| **ON mean** | | **300.46** | **22.715** | **420,199.385** | **22,497.185** | **442,696.570** | |

- **TG +28.88%** (22.715 / 17.625 - 1). TG evaluation time shorter by **6,493.44 ms per 512 output tokens**, about **−22.40%** duration. 64k previous ABBA improvement was **+12.66%**; the context-dependent gain has increased as expected. The historical r3 128k result was +24.3% on different settings; do not directly compare absolute speeds.
- **PP apparent +0.53%**, but the second OFF PP 296.88 is noticeably slower than A1 300.86, while ON measurements agree closely (300.50 and 300.42). Do **not** attribute PP drift or +2,255.47 ms nominal PP improvement to the optimization. Mean PP+TG evaluation time differs by **8,748.91 ms**, but this includes drift/noise in PP.
- Both ON stderr logs have exactly one `qwen4exp_common005_v1 graph_built=compact n_kv=131072 n_sel=2051` line, none in OFF. `n_sel` stays 2051 at 64k/128k while full KV length doubles. This is a host graph-build cue, not a GPU dispatch proof.
- All **4/4 Status=OK, ExitCode=0**, no `GGML_ASSERT`, abort, or fatal error in captured stderr. All have `PModeAtStart=Performance` and `PModeAtFinish=Performance`, `AdlxPModeConsistency.Consistent=true`; ADLX high-load power W **119.276 / 119.407 / 119.338 / 119.042**. `ResourceMonitorEnabled=false`; start/end named-process background status `Observed`, `PossibleNoise=false`, no busy names (cannot exclude transient activity).
- Output fingerprints differ across **all four runs, including both OFF runs**. Manual inspection of the 512-token Japanese summaries found all four coherent, with shared central topics (polarity lexicons, lexical networks, PMI/co-occurrence, contextual bootstrapping, document classification and limitations); no obvious corruption, but **not a mathematical equivalence / exact-logit proof**. Normalized output may end mid-sentence because output is capped at 512 tokens.
- **Gate: PASS** for 128k speed, basic validity and operational stability. Proceed to **only 256k ABBA** using the exact same patched b12013 binary and research plan, with `-OnlyJob common005-long-abba -OnlyCase 256k -StopOnError`; inspect results before changing any defaults or deciding release suitability. Preserve frozen b11908. No repeat RGP necessary yet. Deferred capture-B CPU-bound queue gap remains a separate investigation if unprofiled TG gains unexpectedly flatten.


## 256k ABBA gate — 2026-11-03 (PASS, final long-context gate)

User ZIP `20261103-000255-742-cli-rocm-b12013-ctx262144-e98d3c9afac4.zip` (SHA256 `e4eee9b8062fdf671a5240d3b286e1e83d5d2cbd5bbd3cabe85ffe903e876e86`) contains **four successful, independent OFF/ON/ON/OFF runs** of the 256k real input. Same `b12013 / f29592d6a` patched binary (`4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628`), same runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`; all `RuntimeArtifactStatus=Verified`. Context 262,144, actual prompt **255,181 tokens**, generated **512** each; MTP OFF, F16 K/V, ROCm/TheRock 10, batch 2048 / ubatch 1024, same model and seed. Local timestamps span 2026-11-02 22:51 to 2026-11-03 00:26 JST.

| Order / RunId | Gather | PP tok/s | TG tok/s | PP eval ms | TG eval ms | PP+TG eval ms | Condition ID |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| A1 `20261102-225102-548` | OFF | 198.95 | 12.65 | 1,282,635.56 | 40,393.59 | 1,323,029.15 | `e98d3c9afac4` |
| B1 `20261102-231512-434` | ON | 198.85 | 19.74 | 1,283,314.16 | 25,891.10 | 1,309,205.26 | `3c3ef5186fd6` |
| B2 `20261102-233912-583` | ON | 199.01 | 19.78 | 1,282,260.01 | 25,832.29 | 1,308,092.31 | `3c3ef5186fd6` |
| A2 `20261103-000255-742` | OFF | 197.90 | 12.68 | 1,289,468.62 | 40,287.63 | 1,329,756.25 | `e98d3c9afac4` |
| **OFF mean** | OFF | **198.425** | **12.665** | **1,286,052.09** | **40,340.61** | **1,326,392.70** | |
| **ON mean** | ON | **198.930** | **19.760** | **1,282,787.085** | **25,861.695** | **1,308,648.785** | |

- **TG +56.02%** for Gather ON vs OFF; 512-token TG evaluation time falls by **14,478.915 ms** (**−35.89% latency**). All ON runs 19.74–19.78 vs all OFF 12.65–12.68; highly separated, stable direction. Total PP+TG eval time appears **17,743.915 ms shorter**, but this contains PP measurement drift, so **14.48s TG saving is the more trustworthy causal estimate**. The end-to-end process wall-time mean differs by 22.36s, but includes startup/teardown/cooldown variations and is not a controlled inference-only metric.
- **PP variance**: A1 OFF 198.95 vs A2 OFF 197.90 (**−0.528%**) while ON is 198.85/199.01 (spread **0.080%**). The lower last OFF drives the OFF mean down to 198.425, causing the apparent **+0.255% ON PP** in the ABBA means. **Do not report this as a Gather PP improvement**. Previously frozen b11908 256k three-run PP mean was **198.96**, versus patched ON mean **198.93** (−0.015%, source/binary differ so not controlled), and patched A1 OFF **198.95**. As Gather is decode-only, no PP performance change is predicted. The A2 OFF PP eval is 6.83s longer than A1, <0.6% of its ~21.4-minute prompt eval; within observed real-world run-to-run drift but not a statistically proven random error.
- **GPU monitor context**: per-run ADLX CSV averages GPU clock (whole capture, including startup/teardown) **A1 2845.25, B1 2838.51, B2 2843.20, A2 2833.60 MHz**, matching the direction of A2's slightly slower PP; GPU load whole-run averages 96.45/96.02/96.38/95.91%; VRAM clock 981.68/981.58/981.23/980.84 MHz. Do **not** claim a causal clock explanation without PP-only interval/clock alignment, as these averages cover the whole run. High-load GPU power **117.673 / 117.705 / 117.731 / 117.833 W**, all Performance-like. All P-MODE start/finish Performance, `PModeChanged=False`, `AdlxPModeConsistency.Consistent=True`.
- **Background monitoring**: `ResourceMonitorEnabled=False` for all runs; ADLX remained on. Boundary named-process probe: A1/B1/A2 status `Observed`, `PossibleNoise=False`; B2 `PartialCoverage`, `PossibleNoise=null` (unknown, **not a clean bill**). No monitored `BusyNames`. Short-lived OS/background activity cannot be excluded.
- **Gather activation**: both ON stderr logs have exactly one `qwen4exp_common005_v1 graph_built=compact n_kv=262144 n_sel=2051`; no OFF cue. Proven graph construction, **not GPU-kernel trace**. The selection width remains 2051 from 32k through 256k. No model-side parse/crash/fatal/NaN indications in inspected logs.
- **Output**: normalized result fingerprints differ across all four outputs, including OFF/OFF (known ROCm non-determinism). Manual content inspection: coherent Japanese summaries of the input's evaluation-expression lexicon construction (lexical networks, PMI/co-occurrence, contextual methods) and polarity/document classification, with no obvious semantic collapse. The prompt source is not fully reviewed; treat this as **smoke-level qualitative correctness only**, not exact-logit parity or factual certification.

### Combined r6 COMMON-005 results (same model; no changes to public defaults)

| Context | OFF TG tok/s | ON TG tok/s | TG change | Scope |
| --- | ---: | ---: | ---: | --- |
| 32k | 24.41 | 25.31 | **+3.69%** | single run / condition |
| 64k | 21.80 | 24.56 | **+12.66%** | ABBA mean |
| 128k | 17.625 | 22.715 | **+28.88%** | ABBA mean |
| 256k | 12.665 | 19.760 | **+56.02%** | ABBA mean |

**Decision:** 256k speed/activation/basic-output/stability gate **PASS**. The b12013 research prototype delivers context-dependent TG gains while preserving PP within observed variability, and at 256k its ~19.76 TG exceeds the **historical, differently configured** contemporary MTP-ON 14.80–15.04 TG; do not call that a controlled MTP-ON/OFF A/B. Keep `QWEN4EXP_QSA_GATHER` **default OFF** until further targeted output correctness and adoption review. No third 256k repeat required now. Optional narrow postpatch RGP comparison if identifying residual GPU bottlenecks or explaining the deferred CPU-bound capture B becomes important; no broad HIP FA suite and no upstream upgrade. Main and published b11908 are unchanged.

## RGP capture start cue (added 2026-11-03; no binary rebuild)

The benchmark's `Measure-LlamaCli.ps1` now prints **one host-side onset line** when `LLAMA_EVOX2_RGP_SSE_TRACE=1` and the saved `stderr.log` receives `evox2_rgp_sse_v1 event=first_text_delta`:

```text
TG START (first SSE text, host +7.0 min): capture RGP now. PID 17760
```

The script reads **only the final 8 KiB of stderr at most once per second**, exclusively under the opt-in RGP flag, using read/write file sharing, then **stops reading altogether after the first cue**. Standard unprofiled benchmarks do not probe stderr. Existing periodic `Running... PID ..., elapsed ... min` lines remain. Reading a bounded tail is **not the same as streaming the entire stderr log live**. The cue is delivered no more than ~1s after host receipt under normal circumstances; it is **not a GPU timestamp**. If it does not appear (file permissions, buffering, or unexpected log format), the ordinary run remains unaffected; manual log checks remain possible.

Use the single-run plan `qwen38-r6-rocm-common005-rgp-on-128k-20261103.psd1`, existing `R6RocmCommon005` b12013 binary, `-PlanOnly` then one normal invocation. `git pull --ff-only` fetches the PowerShell-only update; **no ROCm rebuild**. RGP 1024 dispatch relative capture should occur during steady TG after this cue. Do not open a full real-time `Get-Content -Wait` view unless troubleshooting. Do not infer the 29% unprofiled TG gain from profiled CLI stopwatch time. Submit .rgp, profiler overview/events and result ZIP for A/B comparison with previous 128k Gather OFF.

## Post-patch 128k RGP validation — 2026-11-03

**Result: GPU-side compact Attention confirmed; GPU idle gap still exists in one of two captures.** Source unchanged; b12013 `f29592d6a`; normal controlled ABBA remains the performance benchmark. User supplied 2 RGP captures in **one** 128k Gather ON diagnostic run and screenshots. User artifacts (not checked into Git):

| File | Bytes | SHA256 |
| --- | ---: | --- |
| `llama-cli-20261103-005325955.rgp` (A, GPU bound) | 43,395,393 | `d6457e77630994cc752bda7082bc8bf37421522cf4b530c602cbcf9e710460d2` |
| `llama-cli-20261103-005331682.rgp` (B, CPU bound) | 45,530,201 | `7258e96d31fd87fbb431e9d4795978a8e95d2d2e3e469fce9f1fa56fd20a5078` |
| `20261103-004526-851-cli-rocm-b12013-ctx131072-6877c8a1dc30.zip` | 47,219 | `15eb5e99604aac2ef9e781d9a3aebb9a29c192debb091a894a88a1e6e3380926` |

Both `.rgp` binaries have `AMD_RDF` (v3) container header; GPU event durations below are **read from user RGP GUI screenshots**, not full machine-parsed dispatch listings. Do not present per-event times as kernel-total statistics.

### Controlled-length Attention before and after Gather (single events)

| Kernel / observation | 128k prepatch, Gather OFF, 2026-11-02 | 128k postpatch, Gather ON, 2026-11-03 |
| --- | ---: | ---: |
| `flash_attn_tile<256,256,1,4,false>` (full-KV) | **1,490.759 us**, original RGP A | no longer the selected QSA path |
| `flash_attn_tile<256,256,2,1,false>` (compact-KV) | not in prior selected QSA event | **40.714 us** in A event 565; **40.682 us** in B event 917 |
| Attention runtime reduction per sampled event | | **~97.27%**, **~36.6x shorter** than prepatch sampled full-KV event; different launch template and workload length |
| Existing `k_get_rows_float<half,float>` before indexer | **405.008 us** in prepatch A | **407.568 us** in postpatch A event 499; **403.423 us** in B event 851 |
| `lightning_indexer_kernel_vec` | ~124.728 us prepatch A | **121.704 us** A event 503, **132.925 us** B event 855 |
| Extra `k_get_rows_float<half,float>` near compact-KV creation | not present as compact KV read | **~36.210 and 36.126 us** A events 553/557; **~35.562 and 35.123 us** B events 905/909 |
| Copy/convert `cpy_scalar` near compact KV read | not in old masked FA path | **~58.405 and 56.847 us** A events 555/559; **~58.253 and 56.735 us** B events 907/911; inspect precise backend node mapping before attributing all time solely to K/V cast |
| Other representative compute | `mul_mat_vec_q<type14>` ~2.846 ms in earlier prepatch B | **2,849.442 us** B event 1017; same general scale, not improved by QSA Gather |

The existing ~0.4 ms pooled key `get_rows` remains unchanged. New compact K/V `get_rows` calls and conversion/copy events cost tens of microseconds each and are **newly prominent** after FA is shortened; these can be investigated if another optimization pass is warranted. Do not add every sampled event 12x and call it end-to-end proven savings; the captures cover only 1,024 dispatches and kernels have different mixes. Also, the postpatch FA template has different launch dimensions and occupancy; **no instruction-level optimization has been demonstrated**.

### Profile summary and CPU-bound gap

| Metric | Prepatch RGP A | Prepatch RGP B | Postpatch RGP A | Postpatch RGP B |
| --- | ---: | ---: | ---: | ---: |
| Profile duration | 18,966.790 us | 30,863.455 us | **14,397.195 us** | **22,400.565 us** |
| GPU idle reported | **2.22%** | **15.34%** | **2.38%** | **14.29%** |
| RGP local classification | GPU bound | CPU bound | **GPU bound** | **CPU bound** |

Postpatch B shows a conspicuous interval with no Compute queue 0 work while brief Compute queue 1 / Copy queue activity persists. **This is not necessarily a full-GPU idle interval**. The appearance and capture-specific RGP classification are comparable to the **prepatch** B case; **not evidence of a Gather-specific queue regression**. Percentages are valid **only over their respective capture windows**, not the full TG run. A 1,024-dispatch capture may contain a different kernel mix after source changes; do **not** treat profile duration 18.97→14.40 ms as directly comparable speedup.

**Next-step status for CPU bound:** remain deferred / investigate separately if required using host-submit/GPU queue correlation; this RGP set does **not** establish its cause. Do not launch additional GPU-profiling runs solely to reproduce it now.

### Run ZIP confirmation

- b12013 / commit `f29592d6a`, `Status=OK, ExitCode=0`; 126,253 prompt tokens, 512 generated, F16 KV, MTP OFF, `RuntimeArtifactStatus=Verified`, 128k.
- PP **300.63 tok/s**, TG **21.98 tok/s** under RGP diagnostics; normal **unprofiled** 128k ABBA ON mean is **22.715 tok/s**. The difference does not isolate profiling overhead because runs differ. Avoid using this one diagnostic TG number as the official gain.
- `qwen4exp_common005_v1 graph_built=compact n_kv=131072 n_sel=2051` present exactly once. Opt-in host SSE cue `first_text_delta elapsed_ms=420309`, `stream_end elapsed_ms=443571`, `text_deltas=510`; SSE deltas are not generated tokens or GPU timestamps. Run stayed Performance P-MODE, ADLX Performance-like **119.254 W** under high GPU load, `PModeChanged=False`.
- **Decision:** RGP verification **PASS** for intended shorter QSA FA kernel and preservation of pre-indexer cost. Experimental opt-in remains **default OFF** until targeted quality/numerical-parity review. 256k ABBA +56.02% TG still stands. Investigate backend conversion/gather overhead only if pursuing further speed; queue idle investigation is distinct and deferred. No new compile/branch merge/default flip in this documentation step.
