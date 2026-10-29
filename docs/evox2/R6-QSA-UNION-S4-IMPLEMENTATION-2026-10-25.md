# r6 S4 / VULKAN-002 — QSA grouped-union upstream audit, isolated port and Windows validation

- **Date:** 2026-10-25 JST
- **Experimental branch:** `r6/vulkan-qsa-union-20261025`, forked from passing S3 `r6/mtp-compat-20261025` (`db27fcbaefa35e411bc9979f9fe0f6bdbae9bcab`).
- **Base upstream:** fixed llama.cpp b11870 / `74bca3950054eed1795f525cb9cf06bfe796492d`. No upstream refresh in S4.
- **Status (updated 2026-10-26): S4 PASS, candidate for S7.** Windows Vulkan build b11895, 4k fallback, 64k real-QSA activation, and the fixed 12/12 long-context OFF/ON runs completed successfully. **Default remains OFF** until combined S7 evaluation. Keep earlier S3 binaries untouched.
- **Scope:** f16 K/V QSA prefill, Vulkan only. No ROCm source modifications, q8_0-KV expansion, union-stats CSV, RGP, MTP DENSE/NOOP, Stage-B, or 256k.

### First Windows build feedback and compile fix (2026-10-25)

The first S4 Windows Clang 20.1.8/Ninja build stopped while compiling `ggml-vulkan.cpp` (build step 464/1114), before runtime testing. The two diagnostics at lines 8359 and 8387 were both caused by one local variable declared `const vk_pipeline sparse_compact`: upstream `ggml_pipeline_request_descriptor_sets()` and `ggml_vk_dispatch_pipeline()` require a mutable `vk_pipeline &`, so the const-qualified shared-pointer variable cannot bind to either. **Removed `const` from that local `vk_pipeline` variable only**; pipeline selection and contents are unchanged. This is a compile-compatibility correction, **not** a measured optimization. The subsequent Windows build and all S4 runtime gates passed; see section 4.

## 1. Upstream source audit before port

The r5 VULKAN-002 donor cannot be replayed unchanged. The r5 graph placed an explicit per-query selection-ID list into `FLASH_ATTN_EXT` source slot 5; r5's union shader read that list directly. On b11870 the Qwen4Exp graph passes **only the final selection mask** and sets `n_kv_max` in flash-attention op parameter 4. r6 does **not** expose those selected IDs through FA `src[5]`.

Two b11870 selection paths exist:

| Qwen4Exp selection implementation | Source evidence | S4 handling |
| --- | --- | --- |
| Fused `TOP_K_MASK` | `src/models/qwen4exp.cpp` fused branch / `src/llama-graph.cpp` | Reconstruct finite selected positions from the mask on GPU; do not modify the fused graph. |
| Unfused `GET_ROWS` → `SET_ROWS` → `VIEW` → **`CONT`** | `src/models/qwen4exp.cpp` unfused branch. S0 Vulkan reported fused top-k mask unavailable/disabled. | Reconstruct positions from the final contiguous mask; do not revive the old r5 graph or its `src[5]` ABI. |

The current Vulkan backend already provides `flash_attn_sparse_compact.comp`, which converts each finite-mask row into an ascending array of bounded positions (`n_kv_max`, then `-1` padding). That is an appropriate shared input for r5's bitmap union/gather, **without altering Qwen4Exp's pool bookkeeping or mask semantics**. Its shader is reused; S4 adds no model graph rewrites. The compact pass can nevertheless be expensive because it scans the mask over the full KV length.

Importantly, the upstream `use_sparse` branch in `ggml_vk_flash_attn()` normally requires `gqa_ratio > 1` (or scalar `N == 1`), so its sparse decode optimization does **not** simply supersede the 64-query grouped-union prefill mechanism. It is also not proof of a speedup: b11870 Vulkan has improved dramatically elsewhere.

### Why r5 throughput is not an adoption argument on its own

| Matched historical input | r5 QSA union OFF → ON PP (tok/s) | r6 b11870-derived already-measured PP (tok/s) | Consequence |
| --- | --- | --- | --- |
| IQ3 PLE16, 64k | **270.26 → 339.48** (+25.61%) | S2 64k **343.56** (MTP OFF) | r6 without union already matches/exceeds the older r5 union ON level. |
| IQ3 PLE16, 128k | **179.34 → 307.15** (+71.27%) | Clean S0 original 128k **268.60** (different PLE format); S1 PLE16 result in stage record | Historical improvement does not predict r6 adoption. |

Historical data: [r5 actual-model validation](R5-VULKAN002-VALIDATION-2026-10-09.md), [r6 clean baseline](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md), [r6 S2 FP4+IQ3 64k](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md). The S0 original-format and S2 PLE16 runs are not treated as exact same-binary A/B.

## 2. Bounded code changes

| File | Implementation |
| --- | --- |
| `ggml-vulkan.cpp` | `GGML_VK_QSA_UNION=1` opt-in, `GGML_VK_QSA_UNION_MIN_KV` default 32768, runtime activation/fallback logs; GPU compaction → group union → f16 gather → FA with dynamic rounded KV count. |
| `ggml-vulkan-types.h` | Two optional Vulkan pipelines and one-time diagnostic flags. |
| `vulkan-shaders-gen.cpp` | Register `qsa_union.comp`, `qsa_gather.comp`. |
| `qsa_union.comp` | Bitmap union for ≤64 queries; 4096-word bitmap processed in high-KV windows (no truncation of >131072 indices); unique-position count padded to ≥256 and 256 multiples. |
| `qsa_gather.comp` | Gather the selected K/V once per union KV position and remap the original per-query f16 mask. Dead padded KV positions receive negative infinity mask. |
| `flash_attn_base.glsl` | Restore an optional **bit-32** dynamic-KV variant in FA shader; binding 7 supplies count, **not sparse-index rows**. Bit-16 sparse path remains unchanged. |

Input checks are deliberately narrow: explicit `n_kv_max`/sparse QSA hint; source mask op `TOP_K_MASK` or `CONT`; **f16 K/V**, f32 Q/output, no sinks, zero bias/softcap; compatible dimensions/strides and device descriptor and shared-memory limits; query tokens 2–4096, KV 32768–262144 by default. Unsupported shapes return to upstream FA, **before any S4 GPU write**. If the environment variable is absent or `0`, the standard b11870 code path is unchanged.

The compactor's `n_kv_max` bound is part of upstream's QSA contract. If future upstream models violate it (finite entries exceed `n_kv_max`), their FA hint must be corrected rather than silently enabling union. The pipeline must not be considered safe on arbitrary masks/models just because a short prompt completes.

Donor provenance: [r5 VULKAN-002 implementation](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md) and the MIT-licensed `LynxPDA/llama.cpp` grouped-union shader recorded there. In r6 the compaction and graph-interface adaptation are new. No r5 statistics buffer code is imported.

## 3. Windows isolated build and fixed tests

The local worktree is `C:\llama-build\llama.cpp-evox2-windows-r6`. After fetching this S4 branch, use a **new** Vulkan build directory; preserve S3 b11889 and its exact `S3Vulkan` key:

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git switch r6/vulkan-qsa-union-20261025
git pull --ff-only
git status

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-qsa-union `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

Build log/JSON gate: source identity verified/clean, `llama-cli --version`, Vulkan0 / Radeon 8060S, `ggml-vulkan.dll`, shader compilation without errors, no unexpected model CPU offload. Since S4 touches only Vulkan, **do not rebuild ROCm** for this gate. Do not run the broad Windows `FLASH_ATTN_EXT` backend test or `-RunBackendTest`.

Add this under `Builds` of the **ignored** `tools/evox2/benchmark/configs/local.psd1` (retain other keys):

```powershell
S4Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-qsa-union\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

### Gate 4a — short fallback / real-QSA activation, before repeated timings

1. IQ3 PLE16, `-BuildKey S4Vulkan`, MTP OFF, context 4096, a 32-token allocation-only/short generation with `GGML_VK_QSA_UNION=1`. **Expected:** model load and output, with **no** `qsa-union active` (KV below 32768). There may be a threshold fallback diagnostic. Test with the **same GGUF and CLI parameters** at `GGML_VK_QSA_UNION=0` if output unexpected.
2. **64k IQ3 PLE16 one ON smoke** using the standard 64k real document, fixed f16 KV, n-predict lowered to 16–32 for this smoke only. **Required stderr:** `QSA grouped-union = on`, `qsa-union active (r6), source=mask-compact` (works with both fused and unfused selection masks), groups/capacity/scratch nonzero, no shader/pipeline errors. Real output and GPU offload must be normal.
3. **64k IQ3 one OFF smoke** with the same file and generation length to confirm normal b11870 path. Log should show `QSA grouped-union = off` and no activation. A crash, unexpected fallback at 64k, or malformed result is a **STOP**, not permission to proceed to ABBA.

CLI invocation example for fallback (the measurement wrapper provides ADLX/P-MODE and artifact identity; it accepts the normal `-BuildKey` and `-ModelKey`):

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_MIN_KV = '32768'
& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S4Vulkan `
    -ModelKey UnslothPle16 -Context 4096 -AllocationOnly `
    -Temperature 0 -GenerationTokens 32 -NoThrowOnFailure
Remove-Item Env:\GGML_VK_QSA_UNION -ErrorAction SilentlyContinue
Remove-Item Env:\GGML_VK_QSA_UNION_MIN_KV -ErrorAction SilentlyContinue
```

For 64k smoke, the matrix plan below has no separate short variant; use `Measure-LlamaCli.ps1` with `-InputKey 64k -Context 65536 -GenerationTokens 32 -Mtp:$false` plus the same temporary env. Verify smoke result before running the full matrix.

### Gate 4b — actual-model ABBA, no exploratory matrix growth

Plan: [`qwen38-r6-s4-qsa-union.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s4-qsa-union.psd1). All variants use **identical new S4Vulkan binary**, same prompt/ctx/sampler/f16 cache/MTP OFF. Explicit `GGML_VK_QSA_UNION=0/1` determines A/B. No stats recording and no new optimization flags.

| Ordered batch | Model | Context | Pattern | Runs |
| --- | --- | --- | --- | ---: |
| 1 | IQ3 PLE16 | 64k | A1 OFF → B1 ON → B2 ON → A2 OFF | 4 |
| 2 | IQ3 PLE16 | 128k | A1 OFF → B1 ON → B2 ON → A2 OFF | 4 |
| 3 | ROCmFP4 FAST PLE16 (Vulkan) | 64k | A1 OFF → B1 ON | 2 |
| 4 | ROCmFP4 FAST PLE16 (Vulkan) | 128k | A1 OFF → B1 ON | 2 |

Each batch is run independently and its logs examined before the next. Use `-PlanOnly` first; `-OnlyJob` limits the model, `-OnlyCase` limits context, and `-MaxRuns` prevents accidentally expanding the entire 12-run plan before the first gate:

```powershell
$plan = "$bench\configs\qwen38-r6-s4-qsa-union.psd1"
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local `
    -OnlyJob s4-iq3-ple16 -OnlyCase 64k -MaxRuns 4 -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local `
    -OnlyJob s4-iq3-ple16 -OnlyCase 64k -MaxRuns 4
```

After **64k PASS**, repeat those two commands with `-OnlyCase 128k`. After IQ3 ABBA both pass, use `-OnlyJob s4-rocmfp4-fast-ple16 -OnlyCase 64k -MaxRuns 2` and then 128k. Do **not** run the full matrix without filters initially.

### PASS / DEFER / STOP

- **PASS (candidate for S7):** real QSA union activation and 4k fallback confirmed, output coherent, no CPU model-layer fallback/device errors, 64/128k matched A/B shows repeatable *useful total performance*. Keep OFF default even after PASS until S7 decision.
- **DEFER (default OFF):** ≤3% differences or overlapping ABBA noise. At most **one additional IQ3 ABBA set** on the disputed context, per fixed r6 rule; no ad hoc tuning. FP4 single-pair result is directional only.
- **REJECT/STOP:** correctness regression, shape fallback on intended QSA, unexpectedly high GPU memory/driver failure or material 128k slowdown. The extra full-KV mask scan may erase old r5 benefits now that b11870 is faster; do not assume VULKAN-002 remains profitable.
- **No 256k:** S0 baseline already captured it. Follow the S1–S6 restriction. Subsequent work stays S5 MTP-DENSE-001 → MTP-NOOP-001, then S6, unless this predefined gate fails.

The above is the reproducible original gate procedure. Actual results and the adoption decision follow.

## 4. S4 Windows build and complete measurement results (2026-10-25/26 JST)

**Build gate: PASS.** `(vulkan-qsa-union)evox2-build.json` records Vulkan b11895, clean and verified source at `7748be523b0a17211ff172a1265e7d3c2d8b04f5`, Windows Clang 20.1.8, Vulkan0 Radeon 8060S, and successful compilation of `ggml-vulkan.dll`. `llama-cli.exe` SHA-256 is `5aa3cafa03c1f2b150b257d531e4e61336a110e1df3e4ff1949cdf3cab158828`. All measurements below used this same executable, f16 K/V, MTP OFF, and `GGML_VK_QSA_UNION=0/1`; the FP4 entries describe **ROCmFP4 model quantization on the Vulkan backend**, not HIP execution.

### Gate 4a: fallback, activation, and OFF comparison

| Artifact | Gate | Result |
| --- | --- | --- |
| `20261025-233148-478-cli-vulkan-b11895-ctx4096-df781994ecd4.zip` | IQ3 4k ON | **PASS:** model 49/49 layers on GPU, normal `OK` output; `qsa-union fallback` is expected under the 32768-KV threshold. |
| `20261025-233659-315-cli-vulkan-b11895-ctx65536-d58132dc5bb7.zip` | IQ3 64k ON | **PASS:** 61,789-token input; `qsa-union active (r6), source=mask-compact`, `group=64`, `Br=16`, `Bc=64`, `groups=16`, `capacity=32768`, `min_kv=32768`, `scratch=81801472 bytes`. |
| `20261025-234453-012-cli-vulkan-b11895-ctx65536-a564b5d8b720.zip` | IQ3 64k OFF | **PASS:** no union activation, normal upstream path, 49/49 layers GPU. |

The 64k ON and OFF smokes both exited normally, generated 32 tokens, and yielded the **same output SHA-256** `ea93621ee9301d0c3f3ca527e65ed77aa60f5b355869e96f3bc5133a6ab88055`. They are correctness/activation checks, not the speed-adoption runs. All three smokes recorded Performance P-MODE and ADLX metadata.

### Gate 4b: fixed same-binary 64/128k A/B (12/12 PASS)

The IQ3 runs are ordered ABBA (two observations per OFF/ON), while the ROCmFP4 FAST PLE16 runs are the fixed single OFF/ON pairs. PP and TG are in tokens/s. Arithmetic means are reported for IQ3; ROCmFP4 values are single observations, so do not infer run-to-run variance from them.

| Model / context | OFF PP | ON PP | PP change | OFF TG | ON TG | TG change | Run status |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| IQ3 PLE16 / 64k | 344.80 | 364.41 | **+5.69%** | 26.58 | 26.50 | -0.30% | 4/4 PASS |
| IQ3 PLE16 / 128k | 270.61 | 330.22 | **+22.03%** | 24.305 | 24.310 | +0.02% | 4/4 PASS |
| ROCmFP4 FAST PLE16 / 64k | 351.86 | 373.40 | **+6.12%** | 26.35 | 26.35 | 0.00% | 2/2 PASS |
| ROCmFP4 FAST PLE16 / 128k | 275.22 | 335.97 | **+22.07%** | 24.14 | 24.19 | +0.21% | 2/2 PASS |

Source artifacts, in the same order:

1. `20261025-235814-554-qwen38-r6-s4-qsa-union.zip` (IQ3 64k ABBA; 61,789 input tokens).
2. `20261026-003758-077-qwen38-r6-s4-qsa-union.zip` (IQ3 128k ABBA; 126,253 input tokens).
3. `20261026-011810-855-qwen38-r6-s4-qsa-union.zip` (ROCmFP4 64k A/B; 61,789 input tokens).
4. `20261026-013005-955-qwen38-r6-s4-qsa-union.zip` (ROCmFP4 128k A/B; 126,253 input tokens).

All 12 runs finished `Status=OK`, exit code 0, with all 49 model layers offloaded to Vulkan and Performance P-MODE / ADLX collection consistent. Both IQ3 ON contexts and FP4 ON contexts showed actual union activation; no GPU pipeline/driver errors, anomalous low-memory-clock mode, or broken Japanese output were observed. The 128k IQ3 B1 stopped at EOS after 448 tokens versus 512 on its peers; IQ3 64k A1 stopped at 453 versus 512; FP4 64k A1 stopped at 501 versus 512. The PP results are comparable because PP input is unchanged, but raw total runtime depends on generated-token count. Normalizing IQ3 128k to 512 output tokens gives approximately **487.6 s OFF vs 403.3 s ON**, or **84.2 s / 17.3%** shorter PP+TG. The FP4 128k pair each generated 512 tokens: **479.91 s OFF vs 396.91 s ON**, **83.0 s / 17.3%** faster overall.

### S4 decision and continuation

- **PASS / retain as opt-in S7 candidate:** strong, consistent 128k PP acceleration (~22%) and smaller but positive 64k PP acceleration (~6%) in both quantizations, with TG effectively unchanged. These results belong to the b11895 Vulkan S4 binary and should not be added to historical r5 gains.
- **Do not change default:** `GGML_VK_QSA_UNION=0` or unset remains the known-good default; combined S7 determines whether to enable in normal operation. No 256k, stats pipeline, or RGP expansion was needed to make the S4 decision.
- **Next as planned: S5 MTP-DENSE-001**, after auditing the current b11870 `llama_model::create_memory()` path for already-upstream behavior; then MTP-NOOP-001 independently. The S4 measurements used MTP OFF and do not establish combined MTP+union behavior.
