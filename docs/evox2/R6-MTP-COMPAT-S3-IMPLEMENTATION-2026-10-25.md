# r6 S3 MTP compatibility — native gate and minimal port (2026-10-25)

## Status and fixed scope

- **S3 branch:** `r6/mtp-compat-20261025`, created from passing S2 `r6/rocmfpx-vulkan-20261025` / remote `739af71c117f463236bf33d1624a9438f945ccf2`.
- **Status: native MTP gate prepared; runtime tests pending.** No MTP source patch has been applied. The S2 b11882 / `70545f998` Vulkan executable can be reused unchanged for the first compatibility smoke. No new Windows build is needed *before* this native gate.
- **Models:** Unsloth UD-IQ3_XXS PLE16 **with Unsloth Q8_0 MTP**; Agention ROCmFP4 FAST PLE16 **with matching Agention ROCmFP4 FAST MTP**. Never mix the two drafts when drawing model-pair conclusions.
- **Purpose:** confirm loading, model/draft GPU placement, real speculative acceptance and coherent output. Do **not** mix this with S4 QSA union, S5 DENSE/NOOP, S6 Stage-B/flatten, MMVQ forcing, new HIP ROCmFP4 kernels, or 256k.

## Source audit before native execution

Source `src/models/qwen4exp.cpp` at the S2 b11870-derived base still contains two previously identified compatibility-sensitive paths:

1. **Ratio-zero dense MTP:** `graph_mtp` builds `inp_kpool` when `mctx_hyb->get_idx() && hparams.indexer_kpool > 0`, without testing `hparams.dsv4_compress_ratios[il] > 0`. r5's COMMON-002 minimal compatibility fix added that guard after an Unsloth Q8_0 draft failed in the unmodified path with `GGML_ASSERT(buffer)`. A source-level similarity predicts risk, **not a verified r6 runtime failure**. Do not preemptively apply the unrelated `LLAMA_MTP_SKIP_DENSE_INDEXER` optimization.
2. **Legacy Agention draft layout:** the loader asks for `blk.<il>.nextn.hc_head_{norm,down,up}`, while an older Agention MTP GGUF used `output_hc_{norm,down,up}` for the final mixer. The r5 isolated donor proved a bounded old-name fallback. A newer draft may already use the current names; **inspect the error and actual GGUF layout before deciding that fallback is necessary**.

Keep both variants in the investigation log: **native/upstream succeeds** (omit compatibility patch) or **specific native failure reproduced** (port only the minimal corresponding fix on this S3 branch and rebuild). Never claim failure or success before the user's runtime logs arrive.

## First gate: reuse b11882, 4k MTP smoke

Run in `C:\llama-build\llama.cpp-evox2-windows-r6` after fetching/switching to the S3 branch. The S2 Vulkan build directory must remain unchanged. In ignored `tools/evox2/benchmark/configs/local.psd1`, retain `S2Vulkan`, `UnslothPle16`, `UnslothMtp`, and `AgentionRocmFp4FastPle16`. Add the following entry under `Models` if absent (replace the placeholder with the **existing locally downloaded** matching draft path):

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

Stop after 32k to inspect acceptance and output before 64k. The `off` variant is reserved for an explicitly needed same-binary regression/control pair, not an automatic speed-optimization A/B. **If compatibility source code is added**, build a new `S3Vulkan` target in a separate output directory; copy/update this plan's `BuildKeys` to `S3Vulkan` for post-fix verification, leaving native S2 baseline intact. Re-run smoke, then the 32k/64k gates. Test the IQ3 path on ROCm when the source becomes final (new independent S3 ROCm build); FP4 on HIP remains outside S3.

## PASS/STOP and handoff

- **PASS criteria:** both matching draft pairs load; no silent/large CPU model fallback; output is coherent under ordinary sampling; acceptance/proposed > 0 at 4k and 32k; controlled DraftMax=7 short test completes with safe width/rollback; 32k/64k MTP ON runs are stable; Performance P-MODE/ADLX checks are coherent.
- **STOP:** load error, assertion, output corruption, unexpectedly high CPU model placement, repeated device/system failure or acceptance remaining zero. Diagnose one issue at a time; use the old HC fallback or ratio0 guard only for demonstrated incompatibility.
- **Post-compatibility:** mark S3 PASS only after native+patched (if needed) result verification and a clean source/build identity. Then proceed to S4 VULKAN-002 QSA union without changing the agreed patch order. `llama-tokenize` is still an S8 final-build target, not a reason to expand S3.
