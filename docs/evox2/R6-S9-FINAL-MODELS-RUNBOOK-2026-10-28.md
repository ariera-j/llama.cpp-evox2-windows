# R6 S9 final-model Windows validation runbook - 2026-10-28

## Status, authority and boundaries

**Status update (2026-10-29 JST): G9-0, G9-1, G9-2 and bounded G9-3 completed PASS, including the original IQ4 MH-B 12/12 follow-up; G9-4/G9-5 PENDING.** The measured **eleven** CLI ZIPs, model identities, actual input hashes/token counts, conversion verification limits, four MH A/B per-question results, telemetry and archive SHA256 are in the [S9 Qwen IQ4/huihui results](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md). The execution instructions below remain the original prepared procedure; do not interpret later testing as authorizing a Gemma4 replacement, MTP or all-flags-ON profile.

**Original preparation scope:** Begin only after the [S8 G8-6 runtime PASS and flag decision freeze](R6-S8-COMBINED-RESULTS-2026-10-28.md). This S9 gate determines **model-specific load, text quality, long-context performance and rollback eligibility**, not whether the S8 source optimization gates should be reopened. The [r6 S0-S9 integration plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md), [r5 model-quality baseline](R5-MODEL-QUALITY-AND-POST-INTEGRATION-HANDOFF-2026-10-25.md) and [per-Gemma fallback gate](R5-RESEARCH-AND-INTEGRATION-PLAN-2026-10-19.md#post-integration-gemma-4-vulkan-replacement-gate--2026-10-20) define the intended scope.

Use **Windows Evo-X2, UMA 96GB, P-MODE Performance**, branch `r6/combined-20261028`, one GPU inference at a time. Preserve the exact **b11908 Vulkan `CombinedVulkan`** binary and separately verified ROCm build from S8 (no recompile to match docs-only Git HEAD). Retain b10919 Gemma4 operational binaries **separately**, plus b11903/b11906/S4/S5/S6/S0 controls. **Do not overwrite** model files or known-good executable/DLL folders; do not refresh upstream, add new patches or run the unsafe broad ROCm `FLASH_ATTN_EXT` suite.

| Gate | Model/backend | Ordered tests | Required decision |
| --- | --- | --- | --- |
| G9-0 | **Unsloth original UD-IQ4_XS PLE16** / Vulkan b11908 | 4k short -> 16k short | Load, correct GGUF/PLE16, full GPU placement, coherent output, memory |
| G9-1 | **huihui abliterated UD-IQ4_XS PLE16** / Vulkan b11908 | 4k short -> 16k short | Same, **independent** from original IQ4; preserve prior b11521 128k evidence |
| G9-2 | Both Qwen IQ4 variants, separately | One **real 64k** per model -> **selected real 128k** only if safe | No truncation, exact input SHA/actual prompt tokens, PP/TG/total/memory/ADLX |
| G9-3 | Selected Qwen IQ3/FP4/IQ4/huihui, if applicable | **Frozen MH-128K quality regression**, begin small with seed `20261026` | Compare per-question correctness to **b11592** references; no 16-run automatic rerun |
| G9-4 | **Gemma4 31B IT QAT q4_0**, separately **26B A4B IT QAT UD-Q4_K_XL** / Vulkan | Existing **b10919** baseline -> b11908 4k -> 16k -> selected 32k real; longer only after review | Per-model compatibility, template, output, PP/TG and **rollback/replacement decision** |
| G9-5 | Server/vision where used, then release decision | Bounded Jinja/multi-turn; matching `mmproj` + image only if part of real use | Mark PASS/DEFER/DISABLE by exact model/backend; distribution is a separate authorization |

**All five S8 speed switches OFF** for the initial S9 tests. MTP OFF (no Draft model) for IQ4, huihui and Gemma4. The S8 `PASS opt-in` verdict for IQ3 PLE16 is **not transferable to a different quant, abliterated weights, Gemma4 or server/backend**. Do not enable Stage-B/flatten merely because the G8-5 all-ON IQ3 lab run passed; numerical Draft K/V parity stays DEFER.

## 0. Preflight and private model map

`tools/evox2/benchmark/configs/local.psd1` is ignored by Git. Keep existing mappings (`CombinedVulkan`, `CombinedROCm`, `UnslothPle16`, etc.); **add** the missing model keys and the saved b10919 path in the appropriate tables, without replacing the rest of the file:

```powershell
# Add inside Builds, if absent:
GemmaB10919Vulkan = @{
    BinDir = 'C:\path\to\saved-b10919-vulkan\bin'
    ExpectedBackend = 'Vulkan'
}

# Add inside Models (exact local GGUF file; no guessed quant or shard):
UnslothIQ4XSPle16 = @{
    Path = 'C:\path\to\Unsloth-UD-IQ4_XS-ple16.gguf'
    Alias = 'unsloth-iq4xs-ple16'
}
HuihuiIQ4XSPle16 = @{
    Path = 'C:\path\to\huihui-UD-IQ4_XS-ple16.gguf'
    Alias = 'huihui-iq4xs-ple16'
}
Gemma4_31B = @{
    Path = 'C:\path\to\Gemma4-31B-IT-QAT-q4_0.gguf'
    Alias = 'gemma4-31b-qat-q4_0'
}
Gemma4_26B = @{
    Path = 'C:\path\to\Gemma4-26B-A4B-IT-QAT-UD-Q4_K_XL.gguf'
    Alias = 'gemma4-26b-a4b-qat-ud-q4-k-xl'
}
```

These are **placeholder names**, not claims about the user's actual filename or availability. The [r5 quality report](R5-MODEL-QUALITY-AND-POST-INTEGRATION-HANDOFF-2026-10-25.md) already records both IQ4 variants' MH-128K results on an older binary, and [huihui's verified PLE16 conversion](R5-HUIHUI-IQ4XS-PLE16-VALIDATION-2026-10-24.md) does not need repeating. For original Unsloth IQ4, resolve the actual current PLE16 GGUF and any conversion sidecar; if no verified converted file exists, **stop that model** and review the existing conversion workflow before running it. Never infer exact bytes from the huihui model.

For Qwen real inputs, retain the already frozen fixtures:

| `Inputs` key | Existing raw file SHA256 | Historical raw tokenizer count (IQ3, not mandatory for IQ4) |
| --- | --- | ---: |
| `'64k'` | `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` | 61,789 |
| `'128k'` | `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` | 126,253 |

**Preflight in Windows PowerShell** (run from `C:\llama-build\llama.cpp-evox2-windows-r6`):

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
git status --short --branch
if (@(git status --porcelain).Count -ne 0) { throw 'Dirty worktree: inspect, do not reset.' }
git pull --ff-only origin r6/combined-20261028
if ($LASTEXITCODE -ne 0) { throw 'Could not fast-forward; inspect before continuing.' }

$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$vkBin = [string]$local.Builds.CombinedVulkan.BinDir
$vkCli = Join-Path $vkBin 'llama-cli.exe'
$expected = 'bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a'
if ((Get-FileHash -LiteralPath $vkCli -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Wrong Vulkan binary: require the exact S8 G8-5/G8-6 fixed b11908 build.'
}
$manifest = Get-Content -LiteralPath (Join-Path $vkBin 'evox2-build.json') -Raw | ConvertFrom-Json
if ($manifest.BuildIdentity.Status -ne 'Verified' -or $manifest.Backend -notmatch 'Vulkan') {
    throw 'CombinedVulkan build manifest/backend is not Verified.'
}
& $vkCli --version
& $vkCli --list-devices

# Only needed before the matching long-input case; do not load or print the text.
$expectedInputHashes = @{
    '64k'  = '2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751'
    '128k' = '182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466'
}
foreach ($key in @('64k', '128k')) {
    $inputPath = [string]$local.Inputs[$key]
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) { throw "Missing fixture: $key" }
    if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedInputHashes[$key]) {
        throw "Fixture hash changed: $key; stop and investigate."
    }
}

$ram = Get-CimInstance Win32_OperatingSystem
$freeGiB = [math]::Round($ram.FreePhysicalMemory / 1MB, 2)
Write-Host "Physical RAM free: $freeGiB GiB; confirm Performance P-MODE/ADLX"
if ($freeGiB -lt 12) { throw 'Low free physical RAM; defer model loading.' }
```

The preflight *does not* validate the user's actual four GGUF paths: check the intended model **one at a time** with `Test-Path`, the verified conversion manifest (where relevant), GGUF metadata and `Get-FileHash -Algorithm SHA256` (hash a large 80+ GiB GGUF **once**, not before every case). Preserve full filename, size, quant and model SHA in results; do not publish the private model directory. For Gemma, also record matching b10919 `llama-cli`/DLL SHA and `--version` in its own untouched folder.

## 1. G9-0/G9-1: Qwen IQ4 and huihui smoke (no MTP)

The [bounded S9 Qwen matrix](../../tools/evox2/benchmark/configs/qwen38-r6-s9-final-models.psd1) contains **two separate jobs**, each with 4k/16k/64k/128k cases, but **never** run the whole matrix. Use the same S8 `Invoke-BenchmarkMatrix.ps1`; `$job` below is **one** of `s9-unsloth-iq4xs-vulkan` or `s9-huihui-iq4xs-vulkan`. Start with original Unsloth IQ4, inspect the ZIP, then proceed to huihui **separately**.

```powershell
$runner = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$qwenPlan = '.\tools\evox2\benchmark\configs\qwen38-r6-s9-final-models.psd1'
$job = 's9-unsloth-iq4xs-vulkan'  # later: s9-huihui-iq4xs-vulkan

& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 4k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# STOP: confirm one 4096 context, correct GGUF, CombinedVulkan, MTP OFF, five flags OFF.
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 4k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

**Review the result before the next case:** `Status=OK`, `ExitCode=0`, 64 generated tokens unless earlier EOS, coherent text, GPU model layers (expect full placement where memory permits), no unexpected CPU PLE/offload, no `truncated`, reasonable RAM/VRAM/P-MODE/ADLX. If an EOS ends generation early, inspect it rather than calling it a crash. A parse error, unverified GGUF conversion, model CPU placement, OOM, driver reset or unreliable P-MODE stops that model. No automatic retry.

Then run **16k allocation plus short generation** after 4k PASS:

```powershell
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 16k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# Review PlanOnly and current resource headroom; only then:
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 16k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

The 4k and 16k cases use the same **short** `mtp-short.txt` fixture and test allocation/load + elementary decoding. **They are not 4k/16k filled-input performance claims.** Historical huihui b11521 tests reached 128k, but this does not guarantee identical memory behavior on b11908.

## 2. G9-2: selected real-paper 64k -> 128k

After *that exact model's* 4k/16k PASS, run **one real 64k paper** with `-n 256`, `-fit on`, `-ub 512`, f16 KV, no Draft, all S8 speed switches OFF. The 128k case is **one selected follow-up** only after 64k quality/stability/resource inspection, not an automatic pair of runs.

```powershell
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 64k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# Verify exact input SHA in preflight and output <= context; then:
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 64k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

Check actual `PromptTokens`, no context rollover/truncation, nonempty coherent output, GPU model placement, memory and telemetry. Qwen IQ4 token counts **may differ from IQ3's historical 61,789** despite identical input bytes. Do not silently shorten the paper to make the run pass; do not call `-c 65536` proof of 64k input occupancy. If 64k PASS and free physical RAM/paging/ADLX support a longer case, run:

```powershell
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 128k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# Confirm exactly one row, 131072 context, real 128k fixture, and acceptable memory.
& $runner -Plan $qwenPlan -OnlyJob $job -OnlyCase 128k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

At high UMA commitment, monitor host free RAM, GPU dedicated/shared usage, VRAM clock, temperatures and power. If free RAM approaches 8 GiB with sustained paging or the GPU resets/hangs, stop safely, classify **DEFER** and inspect first; do not repeat 128k just to get a throughput number. Record PP, TG **and total wall time** for the same model/fixture, and make comparisons to older b11521/b11592 only with the recorded differences in build, sampler, input and KV made explicit. No 256k IQ4 run is scheduled here.

## 3. G9-3: frozen quality regression, not a new dataset

**Measured closure:** The original IQ4 **A 12/12 and B 12/12**, huihui **A 12/12**, and huihui **B 11/12** results were independently scored and archived. Huihui B's wrong item was **Q01**, while Q08 was correct in both b11908 huihui orders; original IQ4 B answered both correctly. See the [G9-3 measured result and ZIP/scorer hashes](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md#3-g9-3-frozen-mh-128k-quality-regression). The three minimal plans are [A selectable pair](../../tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-a-minimal.psd1), [huihui B only](../../tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-huihui-only.psd1), and [original IQ4 B only](../../tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-iq4-only.psd1). **No further MH-128K run is scheduled before Gemma4.**

Use the **existing** [evox2-llm-experiments search/retrieval scripts and MH-128K dataset](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval). The local execution steps and oracle belong to that repository, not duplicated in this source repo. Its [r5 handoff](R5-MODEL-QUALITY-AND-POST-INTEGRATION-HANDOFF-2026-10-25.md) records **seed 20261026** as the most informative known near-miss seed: original IQ4 **12/12 A and B**, huihui **11/12 A and B**, IQ3 **11/12 A/B**, FP4 **12/12 A/B** (local controls separate). Previous full study = 4 Qwen models x 2 seeds x A/B = **16** runs; **do not repeat all 16 by default**.

1. Use the **identical frozen source data / prompt / oracle / answer mapping** and same chosen Qwen GGUF hashes as the r5 baseline. Record current b11908 Vulkan SHA, `MTP OFF`, all speed switches OFF, f16 KV, context 131072, sampler/seed, prompt byte SHA and **actual token count per tokenizer**. Do **not** substitute this runbook's short `mtp-short.txt` or paper input for the MH dataset.
2. Start with a **bounded 20261026 A** smoke for original IQ4 and huihui **one model at a time**, and compare to the recorded per-question expected answer, not just global score. Include IQ3/FP4 controls only when diagnosing shared-backend versus model-specific changes.
3. If a known near-miss, model-specific discrepancy or parse failure appears, review source/args/quant/KV/template first, then execute **B** or one targeted repeat to distinguish run variability. Do not infer that a score difference proves an internal routing mechanism or a causal quantization effect.
4. Preserve raw outputs, independent oracle results, task-score per question, Q13/Q14 controls, model/build SHA, P-MODE/ADLX and any termination/truncation reasons. **No new synthetic MH-Hard questions in this S9 acceptance gate.**

This quality gate is separate from the 64/128k throughput rows above. An output can finish with `truncated=0` while still violating instruction format or answering a cross-document relation incorrectly (G8-6 real64 ended at the 128-token cap and said six rather than three items). Quality requires its own evidence.

## 4. G9-4: Gemma4 31B and 26B independent b10919 rollback gate

**Do not treat Gemma4 as Qwen4Exp, and do not apply the S4-S7 flags or MTP sidecars.** The two Gemma variants are different architectures/quant families and must be tested **one model at a time**, against **that same model's existing upstream b10919 working executable**. Model keys in ignored `local.psd1` are `Gemma4_31B` (31B IT QAT q4_0) and `Gemma4_26B` (26B A4B IT QAT UD-Q4_K_XL). Before any comparison, freeze exact GGUF and projector (if used) identities and the original b10919 launch parameters, version, SHA and DLLs.

**First**: confirm or obtain the existing **b10919 4k text/Jinja baseline** under the user's known-good settings and its last working model file. If older logs already contain a fully identified matching baseline, **reuse them**. If b10919 `llama-cli.exe --help` lacks any modern b11908 flag, do **not** pass it blindly; preserve b10919's working command, and explicitly mark unmatched settings as non-comparable for speed. No b10919 install or replacement is performed here.

**Second**: use the [b11908-only Gemma smoke matrix](../../tools/evox2/benchmark/configs/gemma4-r6-s9-vulkan-smoke.psd1) for each model's **4k**, then **16k**, with S8 flags OFF. `$job` is either `s9-gemma4-31b-vulkan` or `s9-gemma4-26b-vulkan`:

```powershell
$gemmaPlan = '.\tools\evox2\benchmark\configs\gemma4-r6-s9-vulkan-smoke.psd1'
$job = 's9-gemma4-31b-vulkan'  # later and independently: s9-gemma4-26b-vulkan

& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 4k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# Verify one row, model identity, flags and GPU headroom; then:
& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 4k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError

# Only AFTER reviewing 4k logs:
& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 16k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 16k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

Confirm actual Gemma metadata, correct chat-template/Jinja behavior, coherent Japanese and English text, safe GPU offload, no NaNs/garbage/unsupported quant or reset. The two short cases do **not** exercise long-context prefill; compare selected prompt+decode values to b10919 only if the model, template, sampling, KV, FA, GPU placement and prompt bytes genuinely match.

**Third (selective):** only after the relevant 16k PASS and memory review, use the **real 32k** fixture (`Inputs.'32k'`) with at most one b11908 32k case for that model:

```powershell
& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 32k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -PlanOnly
# Verify actual paper fixture, full model GPU placement, and RAM/VRAM safety.
& $runner -Plan $gemmaPlan -OnlyJob $job -OnlyCase 32k `
    -OnlyVariant s9-stock-nomtp -MaxRuns 1 -StopOnError
```

No unconditional 64/128k Gemma run. As a warning, the previous Gemma4 **31B** b11592 128k MH test reported ~**17 PP / 5.66 TG tok/s** and roughly **114 minutes per run** with an unconfirmed Vulkan attention bottleneck. That is not the b10919/b11908 matched baseline and does not justify a new FA patch within S9. Advance to a user's genuinely used longer context **only after** the relevant 32k and text/API checks PASS, under an explicitly bounded follow-up plan. If Gemma4 31B passes but 26B fails (or vice versa), **keep b10919 for the failing model**; do not force a common replacement decision.

## 5. Optional chat/vision and final per-model decision

- If the user actually uses a Gemma4 model via `llama-server`, run one local-only `--host 127.0.0.1 --parallel 1 --jinja` short chat and one two-turn follow-up on each candidate and its b10919 control **with the relevant version's supported flags**. Prefer the existing known-good b10919 launch profile; do not expose a WAN endpoint. Compare template/functionality, not output SHA across versions.
- If the model use case includes images, separately verify the **matching** `mmproj`/image fixture with each specific model version; a text-only PASS does not imply vision support. Do not invent projector paths or include third-party image bytes in the benchmark ZIP.
- For **each** of `UnslothIQ4XSPle16`, `HuihuiIQ4XSPle16`, `Gemma4_31B`, `Gemma4_26B`, record exactly one verdict: **PASS candidate / DEFER / DISABLE** for its tested backend, GGUF hash, context, generation mode and binary. Never silently infer MTP ON, ROCm FP4 kernel support, 256k quality or model-general S8 flag support.
- Retain a model-specific **rollback map** to b10919 Gemma4 and prior Qwen/FP4 builds. A successful S9 model test authorizes *consideration* for an updated user-selected launch profile, not automatic replacement, deletion or public release.

### Evidence to send

After **each gate boundary**, send only that filtered matrix batch ZIP (with `matrix-plan.json`, `matrix-results.csv`, child `conditions.json`, `result.json`, stdout/stderr, resource/ADLX/P-MODE telemetry), or a small matched b10919/b11908 pair plus model fingerprints. Include the existing raw ZIP SHA256 in the review. Do **not** commit `.gguf`, local config, huge logs, private documents or full datasets to Git.

**Stop rule:** wrong build/model SHA, unexpected full CPU PLE spill/GPU fallback, NaNs, OOM/reset, high paging/free-RAM collapse, P-MODE disagreement, bad response, truncated real-paper input, missing source provenance or meaningful quality regression => **STOP / DEFER** for that case and send the existing logs for review. No batch retries, broad ROCm stress tests or opportunistic code tuning. Start S9 with **one Qwen IQ4 4k** PlanOnly/short run, review, then advance; there is no need to run Gemma4 or 128k on the first S9 session.
