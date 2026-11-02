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
