# r6 S3 MTP compatibility — native gate and minimal port (2026-10-25)

## Status and fixed scope

- **S3 branch:** `r6/mtp-compat-20261025`, created from passing S2 `r6/rocmfpx-vulkan-20261025` / remote `739af71c117f463236bf33d1624a9438f945ccf2`.
- **Status: compatibility fixes built; 4k DraftMax=2/7 and 32k MTP ON PASSED for both matching drafts on b11889; 64k and ROCm IQ3 check pending.** S2 b11882 / `70545f998` is preserved as the historical upstream-native failed baseline.
- **Models:** Unsloth UD-IQ3_XXS PLE16 **with Unsloth Q8_0 MTP**; Agention ROCmFP4 FAST PLE16 **with matching Agention ROCmFP4 FAST MTP**. Never mix the two drafts when drawing model-pair conclusions.
- **Purpose:** confirm loading, model/draft GPU placement, real speculative acceptance and coherent output. Do **not** mix this with S4 QSA union, S5 DENSE/NOOP, S6 Stage-B/flatten, MMVQ forcing, new HIP ROCmFP4 kernels, or 256k.

## Source audit before native execution

Source `src/models/qwen4exp.cpp` at the S2 b11870-derived base still contains two previously identified compatibility-sensitive paths:

1. **Ratio-zero dense MTP:** `graph_mtp` builds `inp_kpool` when `mctx_hyb->get_idx() && hparams.indexer_kpool > 0`, without testing `hparams.dsv4_compress_ratios[il] > 0`. r5's COMMON-002 minimal compatibility fix added that guard after an Unsloth Q8_0 draft failed in the unmodified path with `GGML_ASSERT(buffer)`. A source-level similarity predicts risk, **not a verified r6 runtime failure**. Do not preemptively apply the unrelated `LLAMA_MTP_SKIP_DENSE_INDEXER` optimization.
2. **Legacy Agention draft layout:** the loader asks for `blk.<il>.nextn.hc_head_{norm,down,up}`, while an older Agention MTP GGUF used `output_hc_{norm,down,up}` for the final mixer. The r5 isolated donor proved a bounded old-name fallback. A newer draft may already use the current names; **inspect the error and actual GGUF layout before deciding that fallback is necessary**.

The user's actual 4k native logs now confirm **both anticipated independent failures**; see the evidence below. Neither issue demonstrates an S2 quantization regression nor justifies enabling S5 performance patches.

## Native 4k runtime gate — FAILED, S3 compatibility-only port required

User archive: `20261025-202024-892-cli-vulkan-b11882-ctx4096-e77de269b276.zip` (two nested runs, each `-Mtp -DraftMax 2 -AllocationOnly --ignore-eos`; same unmodified S2 Vulkan b11882 build). Both main models load with **49/49 GPU offload**; they fail specifically after loading or while loading the *matching draft*.

| Run | Main + matching draft | Actual error / point of failure | Decision |
| --- | --- | --- | --- |
| `20261025-201916-874-cli-vulkan-b11882-ctx4096-35c4e23054c8` | Unsloth IQ3 PLE16 + Unsloth Q8_0 MTP | Draft **50/50 GPU offload**, both contexts reserve graphs (127/133 nodes); `ggml/src/ggml-backend.cpp:345: GGML_ASSERT(buffer) failed` immediately after `draft-mtp` setup. Windows exit `3221226505` (`0xC0000409`); no generated tokens. | Same signature as r5 COMMON-002 ratio-zero dense MTP. Apply *MTP-graph-only* k-pool guard and retest. Exact stack trace was not recorded. |
| `20261025-202024-892-cli-vulkan-b11882-ctx4096-e77de269b276` | Agention ROCmFP4 FAST PLE16 + matching ROCmFP4 FAST MTP | Draft GGUF (34 tensors) parses, then `check_tensor_dims: tensor 'blk.48.nextn.hc_head_norm.weight' not found`; error exit 1. Does not reach draft GPU allocation/graph. | Old-`output_hc_*` GGUF name compatibility. Reuse the existing legacy tensors only if the whole modern `nextn.hc_head_*` trio is absent. |

### Source change limited to two demonstrated compatibility failures

`src/models/qwen4exp.cpp` only:

1. `graph_mtp`: extend the existing `mctx_hyb->get_idx() && hparams.indexer_kpool > 0` condition with `hparams.dsv4_compress_ratios[il] > 0`. The nonzero-ratio QSA path remains unchanged; no `LLAMA_MTP_SKIP_DENSE_INDEXER` optimization is imported.
2. In the **MTP block loader only**, probe all three `blk.<il>.nextn.hc_head_*` tensors as optional, preserving their priority. If all are absent, reuse the already loaded `output_hc_{norm,down,up}` tensors (the source already probed those via `hc_head_*` using `trunk_flags` and `TENSOR_NOT_REQUIRED` for MTP-only GGUFs). If only some new names are present, or neither complete trio exists, report a load error. Reusing avoids allocating/registering the same legacy tensor twice. No GGUF renaming or generalized tensor-name rewrite.

**At the original source-implementation checkpoint the runtime result was still unknown.** The subsequent b11889 smoke results are recorded below. The Unsloth assertion cause is inferred from the source plus r5's successful controlled fix; no fresh r6 stack trace was collected.

## Patched S3 Vulkan build and 4k DraftMax=2 — PASS (2026-10-25 JST)

User build manifest: `(vulkan-mtp)evox2-build.json`; user smoke archive: `20261025-204912-737-cli-vulkan-b11889-ctx4096-f5d7224f74d4.zip` (contains both matching target+draft runs). These two smokes use the same patched executable; no comparison of GGUF-based PP/TG is attempted at this short length.

| Identity / result | Value |
| --- | --- |
| Source and branch | `r6/mtp-compat-20261025` / GitHub commit **`befbc45388ed9eee211c94becafaa4963fc3eb5a`**; build manifest source clean, `BuildIdentity.Status=Verified` |
| Vulkan binary | **b11889** / embedded `befbc4538`, Clang 20.1.8, `llama-cli.exe` SHA256 **`42ebf2a69d3c7b2239b9f9e57673760da88ef65367bc5581aadfa4aaae9e6aac`** |
| Build path | `build-vulkan-r6-mtp-compat/bin/Release`, separate from retained S2 b11882 |
| Device | AMD Radeon(TM) 8060S Graphics, Vulkan0; `llama-cli --version` and `--list-devices` exit 0 |
| Test flags | ctx4096, **DraftMax=2**, DraftPMin=0, f16 main/draft K/V, `--temp 0 --ignore-eos`, allocation-only short prompt, 32 generated tokens |
| Power telemetry | Both runs: IP3-WMI P-MODE **Performance=1** at start and finish; ADLX data collected, but no high-load samples, so workload power classification is **not** available/required at 4k |

| Actual run | Pair | GPU offload (main/draft) | Exit / generation | Speculative acceptance |
| --- | --- | --- | --- | --- |
| `20261025-204558-172-cli-vulkan-b11889-ctx4096-797150290a44` | Unsloth IQ3 PLE16 + matching Q8_0 MTP | **49/49 + 50/50** | `OK`, exit0, 32 tokens; prints `OK. I am ready to assist you…` | **12 accepted / 36 generated draft tokens = 33.33%**, mean length 1.67 |
| `20261025-204912-737-cli-vulkan-b11889-ctx4096-f5d7224f74d4` | Agention ROCmFP4 FAST PLE16 + matching ROCmFP4 FAST MTP | **49/49 + 50/50** | `OK`, exit0, 32 tokens; prints `OK.`, `</think>`, repeated `OK.` under `--ignore-eos` | **17 accepted / 28 generated draft tokens = 60.71%**, mean length 2.21 |

**Gate decision:** **PASS for 4k DraftMax=2 only.** Both previously failing model/draft pairs now load, execute MTP and accept draft tokens on the same clean b11889 binary. The repeated `OK` / post-`</think>` continuation in the FP4 run is not treated as quality evidence: `--ignore-eos` forces generation beyond the natural response. Short-prompt acceptance percentages are not long-context performance estimates. The earlier ratio-zero failure still has no independently collected stack trace; runtime success after the narrowly scoped fix is the practical causality check. The S3 stage itself is **not yet PASS**.

**Historical next step, now completed:** repeat both 4k allocation-only smoke runs using `-BuildKey S3Vulkan -DraftMax 7` (other flags and pairs unchanged). The results follow below. **Do not add S4/S5/S6 performance patches or 256k runs yet.**

## Patched S3 Vulkan 4k DraftMax=7 — PASS (2026-10-25 JST)

User archive: `20261025-205954-487-cli-vulkan-b11889-ctx4096-ffdf8db7e2c0.zip` (two target/draft runs). Executable identity unchanged from the previous 4k gate: **b11889** / `befbc4538`, SHA256 `42ebf2a69d3c7b2239b9f9e57673760da88ef65367bc5581aadfa4aaae9e6aac`; both use `--spec-draft-n-max 7`, ctx4096, fixed prompt, `--ignore-eos`, f16 draft KV, 32 output tokens.

| Run | Model and matching draft | Exit and GPU placement | Draft statistics | Power / output |
| --- | --- | --- | --- | --- |
| `20261025-205851-925-cli-vulkan-b11889-ctx4096-c0e18e4737bf` | Unsloth IQ3 PLE16 + Q8_0 MTP | `Status=OK`, exit0; main **49/49**, draft **50/50** GPU | **15 accepted / 95 generated = 15.79%**, mean accepted length **1.94**, 16 draft batches | Start/finish P-MODE Performance. Output begins `OK. I am ready to assist…`; continued beyond natural answer because EOS was ignored |
| `20261025-205954-487-cli-vulkan-b11889-ctx4096-ffdf8db7e2c0` | Agention ROCmFP4 FAST PLE16 + matching FP4 MTP | `Status=OK`, exit0; main **49/49**, draft **50/50** GPU | **20 accepted / 71 generated = 28.17%**, mean accepted length **2.82**, 11 draft batches | Start/finish P-MODE Performance. `OK.`, `</think>`, repeated `OK.` under ignored EOS |

Both have **nonzero acceptance with seven-position draft width** and terminate normally without a load/graph assertion; the per-position acceptance arrays each contain seven positions. P-MODE never changed; ADLX had zero high-load samples, so the 4k power class is inconclusive but not a stop. Lower acceptance *percentage* compared with DraftMax2 is unsurprising because more candidate positions are proposed; this tiny forced-generation workload is **not** a speed or quality comparison. No independent bitwise hidden-state/rollback equivalence test has been claimed here.

**Gate decision:** **4k MTP compatibility/width smoke PASS for both target+draft pairs.** The subsequent **32k MTP ON ×2** result is recorded below. S3 overall still awaits **64k MTP ON ×2** and a separately planned ROCm IQ3 compatibility check. Performance patches S4–S6 remain untouched.

## Patched S3 Vulkan 32k real-document MTP ON — PASS (2026-10-25 JST)

User matrix archive: `20261025-211444-407-qwen38-r6-s3-mtp-native.zip`. `matrix-result.json` states `Complete=true`, `RunCountPlanned=2`, `RunCountFinished=2`, `OK=2`, `NonOK=0`, no early stop. `-OnlyCase 32k -OnlyVariant on` correctly produced one Unsloth IQ3 and one Agention ROCmFP4 run on **S3Vulkan**. Both use exactly **29,557 input tokens**, **256 generated tokens**, ctx32768, `DraftMax=2`, f16 draft KV, the same source and binary **b11889 / befbc4538** (`llama-cli.exe` SHA256 `42ebf2a69d3c7b2239b9f9e57673760da88ef65367bc5581aadfa4aaae9e6aac`).

| Run / model | PP tok/s | TG tok/s | MTP acceptance | PP+TG time | GPU placement, power and output |
| --- | ---: | ---: | --- | ---: | --- |
| `20261025-211449-060-cli-vulkan-b11889-ctx32768-7f7ca8b46b8d` Unsloth IQ3 PLE16 + Unsloth Q8_0 MTP | **386.12** | **33.49** | **145/220 = 65.91%**, mean length 2.32 | **84.165 s** | `Status=OK`/exit0, GPU target **49/49**, draft **50/50**, P-MODE Performance at both ends, ADLX high-load **119.486 W**, classification agrees. Output is a coherent Japanese technical summary truncated by 256-token limit. |
| `20261025-211719-366-cli-vulkan-b11889-ctx32768-a4bf32fe85e2` Agention ROCmFP4 FAST PLE16 + matching FP4 MTP | **396.92** | **38.05** | **149/212 = 70.28%**, mean length 2.41 | **81.169 s** | `Status=OK`/exit0, GPU target **49/49**, draft **50/50**, P-MODE Performance at both ends, ADLX high-load **120.229 W**, classification agrees. Output is likewise a coherent Japanese technical summary truncated by 256-token limit. |

Both report **zero graph reallocations** and no visible model-load/runtime assertions, unexpected CPU model fallback or text corruption. Power telemetry has 35 high-load samples per run and confirms the previously observed low-clock/P-MODE problem is **not** present in these measurements. A host-side model/utility buffer is normal and is not misidentified as CPU layer offload.

**Gate decision:** **32k MTP ON PASS for both matching pairs.** The 32k acceptance percentages are meaningfully measured on long input but are **not** a head-to-head model-quality ranking. Neither pair has a matched 32k MTP OFF measurement in this gate, so the displayed TG and PP values do **not** measure an MTP speedup. No extra A/B, 256k, or optimization investigation is authorized by this PASS.

**Next fixed step:** `-OnlyCase 64k -OnlyVariant on -PlanOnly`, confirm exactly `s3-iq3-ple16` and `s3-rocmfp4-fast-ple16` (both `S3Vulkan`), then execute that **two-run ON-only** matrix. Record output, PP/TG, acceptance, GPU placement, P-MODE/ADLX and memory headroom; pause for review before a separate S3 ROCm IQ3 build/check or S4 work.

### Original Windows rebuild and 4k smoke procedure — completed

From the r6 worktree, after fetching the S3 branch, build **new** `build-vulkan-r6-mtp-compat`. Leave `build-vulkan-r6-rocmfpx` (b11882) unchanged:

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git pull --ff-only
git status

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-mtp-compat `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

Add `Builds.S3Vulkan` to ignored `tools/evox2/benchmark/configs/local.psd1`:

```powershell
S3Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-mtp-compat\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

The two 4k DraftMax=2 and two DraftMax=7 repeats have **all passed** on b11889; see the recorded results above. Continue with the remaining fixed **32k → 64k** plan. The matrix in `qwen38-r6-s3-mtp-native.psd1` selects `S3Vulkan` for both models; its historical name is retained to avoid changing paths midway through S3.

## First gate: reuse b11882, 4k MTP smoke

Historical upstream-native gate instructions (**executed and FAILED**). For post-fix reruns, use `S3Vulkan` as specified above, not the `S2Vulkan` keys in these historical commands. In ignored `tools/evox2/benchmark/configs/local.psd1`, retain `S2Vulkan`, `UnslothPle16`, `UnslothMtp`, and `AgentionRocmFp4FastPle16`. Add the following entry under `Models` if absent (replace the placeholder with the **existing locally downloaded** matching draft path):

```powershell
AgentionRocmFp4FastMtp = @{
    Path  = 'C:\path\to\Qwen3.8-Flash-Next-MTP-ROCmFP4-FAST.gguf'
    Alias = 'agention-rocmfp4-fast-mtp'
}
```

Run **DraftMax=2** first. `--ignore-eos` is deliberately used only for this short compatibility gate so the 32-token reply exercises speculation beyond the immediate `OK`/EOS response; **do not interpret forced post-EOS text as a quality test**. `-NoThrowOnFailure` preserves an unsuccessful run's diagnostic logs.

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"

& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan `
    -ModelKey UnslothPle16 -Mtp -DraftModelKey UnslothMtp `
    -DraftMax 2 -DraftPMin 0 -Context 4096 -AllocationOnly `
    -Temperature 0 -ExtraArgs @('--ignore-eos') -NoThrowOnFailure

& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan `
    -ModelKey AgentionRocmFp4FastPle16 -Mtp -DraftModelKey AgentionRocmFp4FastMtp `
    -DraftMax 2 -DraftPMin 0 -Context 4096 -AllocationOnly `
    -Temperature 0 -ExtraArgs @('--ignore-eos') -NoThrowOnFailure
```

**Stop and send both logs before further runs** if either model load fails, the native draft crashes, CPU model placement is unexpected, or draft acceptance stays zero despite a substantive forced 32-token generation. Save `stderr.log`, `result.json`, `conditions.json`, `stdout.normalized.log`, and preferably the zipped `evox2-logs` runs. Look specifically for `blk.48.nextn.hc_head_* not found`, `GGML_ASSERT(buffer)`, GPU offload layers/draft layers, `DraftAcceptance`, accepted/proposed counts, and model/draft identity. Avoid additional rebuilds or unrelated environment toggles when localizing failure.

Only **after both DraftMax=2 smokes succeed**, repeat the same two 4k short commands with `-DraftMax 7`, to exercise an eight-token speculative verification width. Report the actual accepted/proposed distribution and memory; `DraftMax=7` is not a speed-tuning choice here.

## Second gate: fixed 32k, then 64k

Use [`qwen38-r6-s3-mtp-native.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s3-mtp-native.psd1); required ignored local config keys also include `Inputs.32k` and `Inputs.64k`. The stage plan has ON/OFF variants on the **same executable** so a compatibility fix can later be checked without comparing unrelated binaries. Start with **MTP ON only**, one run per target pair; do not execute the full 4-run ON/OFF matrix by accident.

```powershell
$plan = "$bench\configs\qwen38-r6-s3-mtp-native.psd1"
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 32k -OnlyVariant on -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 32k -OnlyVariant on

# Only when both 32k target+draft runs have passed:
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k -OnlyVariant on -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k -OnlyVariant on
```

The 32k gate has now passed; **stop after 64k** to inspect acceptance and output before advancing the stage. The `off` variant is reserved for an explicitly needed same-binary regression/control pair, not an automatic speed-optimization A/B. **Compatibility source code was added after the native failure.** The matrix `BuildKeys` are now `S3Vulkan`, leaving native S2 baseline intact. Test the IQ3 path on ROCm when the source becomes final (new independent S3 ROCm build); FP4 on HIP remains outside S3.

## PASS/STOP and handoff

- **PASS criteria:** both matching draft pairs load; no silent/large CPU model fallback; output is coherent under ordinary sampling; acceptance/proposed > 0 at 4k and 32k; controlled DraftMax=7 short test completes with safe width/rollback; 32k/64k MTP ON runs are stable; Performance P-MODE/ADLX checks are coherent.
- **STOP:** load error, assertion, output corruption, unexpectedly high CPU model placement, repeated device/system failure or acceptance remaining zero. Diagnose one issue at a time; use the old HC fallback or ratio0 guard only for demonstrated incompatibility.
- **Post-compatibility:** mark S3 PASS only after native+patched (if needed) result verification and a clean source/build identity. Then proceed to S4 VULKAN-002 QSA union without changing the agreed patch order. `llama-tokenize` is still an S8 final-build target, not a reason to expand S3.
