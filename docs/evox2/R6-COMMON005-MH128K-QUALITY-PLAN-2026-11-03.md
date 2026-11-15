# r6 COMMON-005 — ROCm MH-128K quality parity runbook (2026-11-03)

**Purpose:** Compare opt-in Gather OFF vs ON for the **same** Unsloth IQ3 PLE16 and **original Unsloth UD-IQ4_XS PLE16** weights, using historical MH-128K two-hop A/B question orders. Evaluate correctness, **not** PP/TG speed. Quality is *not yet certified*. No source flag defaults or release tags change.

> **2026-11-03 scope correction:** the initial plan used Agention ROCmFP4 FAST v2, but that format's availability in the current b12013 ROCm binary is **not confirmed**. This runbook and plan now target **original Unsloth UD-IQ4_XS PLE16**, which was previously 12/12 on both MH question orders for both historical seeds under Vulkan. This change is about test feasibility and clean comparisons; it does **not** establish that the current ROCm binary lacks FP4 support.

## Historical baseline: not a ROCm comparison

The canonical experiment kit and previous observations live in [evox2-llm-experiments: MH-128K](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval/mh-128k) and [2026-10-25 experiment summary](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/search-retrieval/EXPERIMENTS-2026-10-25.md). The historical b11592 fixed-input comparison was **Vulkan**, NOT ROCm:

| Model | Seed 20261025 A/B | Seed 20261026 A/B |
| --- | --- | --- |
| Unsloth IQ3 PLE16 | 12/12, 11/12 | 11/12, 11/12 |
| Original Unsloth UD-IQ4_XS PLE16 | 12/12, 12/12 | 12/12, 12/12 |

No matched **ROCm** MH-128K baseline is present in the reviewed repositories. The new ROCm **Gather OFF** arm establishes that baseline. Do not attribute Vulkan-vs-ROCm response differences to Gather. A/B = question-order ascending/descending, NOT OFF/ON. These are the **same** 12 underlying questions plus local controls Q13 (two-hop) and Q14 (direct); A/B are not independent data samples.

For each seed: `2 models × 2 question orders × 2 Gather settings = 8 runs`. Both frozen seeds = 16 runs. Run seed 20261025 first, review before seed 20261026. All conditions use verified b12013 / binary-source `f29592d6a` as already built (new main docs commits do not require rebuild), ROCm/TheRock 10.0, `-c 131072`, `-n 512`, MTP OFF, F16 KV, `-b 2048 -ub 512`, `-t 4 -tb 4 -ngl 999 -ncmoe 0 -fa auto`, `--temp 0 --top-p 0.8 --top-k 20 --min-p 0.05 --seed 1234 --reasoning off`, and `--ctx-checkpoints 0t`. The matrix preserves the historical MH generation/sampling conditions where available. `ResourceMonitor = false` for low-overhead diagnostics, ADLX/P-MODE checks remain active (unlike the original Vulkan quality plan's resource monitor ON). **Not a controlled PP/TG comparison with the old Vulkan runs.**

## 1. Recover and validate frozen historical production inputs

The *original* full prompts and manifests are **not committed** to GitHub, only the deterministic generator and reduced smoke fixtures. Do NOT use `tests/example-data`, arbitrary recreated prompts, or `--no-tokenize` manifests for claims comparing against 2026-10-25 Vulkan results.

Use the original Windows archives of **six source artifacts (three per seed)**: `mh128k_s20261025_{A,B}.prompt.txt`, `mh128k_s20261025.manifest.json` and corresponding `20261026` files. Manifest files hold the matching expected SHA256 of the A/B inputs. The original calibration used 1,136 records for seed 20261025 and 1,137 for seed 20261026, but **record counts alone do not prove identity**; compare SHA256. If the archives are missing, regenerate separately with the original generator/version, all five original GGUF tokenizer paths, and verify manifest/input hashes against the historic run if available; otherwise label it a **new dataset** and do not quote the historic scores as matched baselines.

PowerShell example (edit the paths):

```powershell
$exp = 'C:\llama-build\evox2-llm-experiments'
$mh = Join-Path $exp 'benchmarks\search-retrieval\mh-128k'
$data = 'C:\Users\ai\Desktop\mh128k-data'
$manifest1 = Join-Path $data 'mh128k_s20261025.manifest.json'
$manifest2 = Join-Path $data 'mh128k_s20261026.manifest.json'

python (Join-Path $mh 'tools\validate_mh128k.py') --manifest $manifest1
python (Join-Path $mh 'tools\validate_mh128k.py') --manifest $manifest2
```

**Both must be `VALID`; SHA mismatch, wrong content, missing originals, or `truncated=1` means STOP** until inputs are corrected. When available, check `token_count_verified=true`, original model tokenizer counts and original GGUF SHA.

## 2. Local benchmark configuration (ignored local.psd1)

Use main `llama.cpp-evox2-windows` with `tools/evox2/benchmark/configs/local.psd1`, adding the following **without overwriting existing entries**.

In `Builds`:

```powershell
R6RocmCommon005 = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-common005\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

(Keep the existing verified b12013 build directory and manifest; if the entry already exists, don't duplicate it.) **Original IQ4 in ROCm is not established by earlier Vulkan tests.** The 2026-10-29 r6 S9 Vulkan record lists the original IQ4 PLE16 as 93,682,576,992 bytes (~87.25 GiB), SHA256 `BA65BD1E3631DA5FC99764686C05D68DB45FEAF22A36C2C5F824F9255DAC614A`, and about 93.339 GiB GPU committed during a 128k Vulkan run. Given the EVO-X2 96 GiB UMA, the ROCm backend's allocations may differ; **successful 32k alone does not guarantee 128k will fit**. Use the exact original GGUF, do not substitute Huihui and do not treat an out-of-memory condition as a Gather correctness regression.

In `Models`, verify the existing `UnslothPle16` and `Qwen38Iq4XsPle16` are the **same frozen historical model weights** used in the 2026-10-25 study. If your local keys differ, add aliases for these exact names with `Path` pointing to the **original Unsloth IQ4, not Huihui abliterated IQ4**, and the historical IQ3 GGUF. Verify model paths / hashes; **do not silently substitute another quantization or model derivative**.

In `Inputs`:

```powershell
MH128K_S20261025_A = 'C:\Users\ai\Desktop\mh128k-data\mh128k_s20261025_A.prompt.txt'
MH128K_S20261025_B = 'C:\Users\ai\Desktop\mh128k-data\mh128k_s20261025_B.prompt.txt'
MH128K_S20261026_A = 'C:\Users\ai\Desktop\mh128k-data\mh128k_s20261026_A.prompt.txt'
MH128K_S20261026_B = 'C:\Users\ai\Desktop\mh128k-data\mh128k_s20261026_B.prompt.txt'
```

Adjust all paths to the actual archived files. Plan checks for all four keys during expansion, even when selecting one seed; **register both seeds before PlanOnly**. Verify `Import-PowerShellDataFile` loads, model and input files exist, binary backend is ROCm, P-MODE Performance, UMA allocation adequate, no RGP or real-time log streaming.

## 3. Execute in gates

Plan: `tools/evox2/benchmark/configs/qwen38-r6-common005-mh128k-quality-20261103.psd1`. This is a NEW research/quality plan; never overwrite the historical Vulkan MH plan.

```powershell
git switch main
git pull --ff-only
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-common005-mh128k-quality-20261103.psd1'
$matrix = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
& $matrix -Plan $plan -PlanOnly

# 0) Required original-IQ4 ROCm Gather activation smoke, 32k, 64 generated
& $matrix -Plan $plan -OnlyJob mh-iq4-gather-preflight -StopOnError

# 1) Confirm all OFF and ON results are usable, then FIRST seed only:
& $matrix -Plan $plan -OnlyCase seed20261025 -StopOnError

# 2) ONLY after reviewing seed20261025 quality, optional second original seed:
& $matrix -Plan $plan -OnlyCase seed20261026 -StopOnError
```

The 32k preflight is **2 runs**, original IQ4 Gather OFF/ON; require `Status=OK, ExitCode=0`, plausible answer, and the ON-only stderr cue `qwen4exp_common005_v1 graph_built=compact n_kv=32768 n_sel=2051`. If original IQ4 does not load, cannot allocate ROCm memory, fails, asserts, or produces invalid output, STOP; don't assume IQ3's eligibility proves IQ4.

For every seed, the **eight** 128k tasks are IQ3-A OFF→ON; IQ3-B ON→OFF; IQ4-A OFF→ON; IQ4-B ON→OFF (counterbalances the arm order without confusing A/B question order). The batch runner uses independent processes, no prompt cache, cooldown 45s. Each ON 128k run should produce `graph_built=compact n_kv=131072 n_sel=2051`. If the plan produces anything other than 8 runs for `-OnlyCase seed20261025`, do NOT run it; review the PlanOnly summary.

During the first two quality runs, check all 14 answer lines and `GeneratedTokens`. If `-n 512` truncates the 14 answers, do **not** score partial output; revise the plan to raise the cap **identically for all arms/models/seeds**, and rerun affected cohort. More output tokens may change historical comparability; record the change. **Do not use `--ignore-eos` for this task**.

## 4. Score each leaf run directory or per-run ZIP, not a multi-run matrix ZIP

Use the same original **MH-128K** validator/scorer from `ariera-j/evox2-llm-experiments`:

```powershell
# Example (replace with actual 'Run directory:' leaf paths or single-run ZIPs):
python (Join-Path $mh 'tools\score_mh128k.py') `
  --manifest $manifest1 `
  --run 'C:\path\to\IQ3-A-OFF-run-folder' `
  --run 'C:\path\to\IQ3-A-ON-run-folder' `
  --out (Join-Path $data 'common005-seed20261025-scores.csv') `
  --json-out (Join-Path $data 'common005-seed20261025-details.json')
```

Repeat `--run` for all 8 leaf runs of seed20261025. Run the other seed separately with `$manifest2`. The original scorer rejects an input that doesn't match the selected manifest SHA and reads result/conditions, normalized stdout, stderr and GPU metrics. A **matrix ZIP containing multiple run folders must be extracted** and each leaf scored individually; feeding the whole matrix ZIP to this scorer can cause duplicate-file errors.

Record for every model×seed×question order×Gather arm:
- `strict_final_correct /12`, E/M/H correct (/4 each), Q13/Q14 local controls, 14-line format compliance, wrong-question binding/role/near-link classifications.
- `Status=OK`, exit0, `RuntimeArtifactStatus=Verified`, input SHA matching the manifest, `truncated=0`, prompt tokens less than 131072, no runtime OOM/fatal events.
- Exact model GGUF hash, b12013 executable SHA and loaded runtime digest, `QWEN4EXP_QSA_GATHER` from `conditions.json`, ON-only compact-graph cue, P-MODE Performance start/end and ADLX GPU/VRAM clocks. **Run hash/output SHA alone is not a correctness criterion.**

**Assessment:** primary paired comparison is **ON vs OFF for the same model, seed and question order**. Prior Vulkan b11592 results are context, not the matched ROCm control. A/B are correlated question permutations; seeds differ in content and provide stronger robustness checks. ROCm QSA top-k has known fixed-seed nondeterminism. If one ON arm misses a question, inspect the exact wrong Q/value and compare OFF, then repeat the same matched OFF/ON arm before attributing the change to Gather. A single equal score is a bounded regression smoke pass, **not mathematical numeric equivalence**. No automatic default-ON promotion, no merge/release change.

## Final artifacts

Keep original input manifests/hashes, per-run ZIPs or leaf run dirs, scorer CSV/JSON, sample wrong-Q explanations, conditions.json and telemetry. Initial request to share back: 32k original IQ4 2-run log + seed20261025 first 8-run matrix ZIP and scorer results. After a gate review decide whether to run seed20261026 or any targeted repeat. Preserve [main COMMON-005 implementation record](R6-COMMON005-IMPLEMENTATION-2026-11-02.md), published b11908 checkpoint and separate deferred CPU-bound RGP investigation.

## 2026-11-03 — original IQ4 ROCm 32k Gather activation preflight (PASS; small TG regression not attributed)

User-supplied matrix ZIP `20261103-014250-967-cli-rocm-b12013-ctx32768-60ad2994a9a5.zip` SHA256 `ea4f0a265161f64734e7acf61f94e2da0cb4aac3a48985e0ab216a39e4f46566` contained **two independent runs**, original Unsloth IQ4_XS PLE16 (not Huihui), 29,557 real prompt tokens, 64 generated, context 32,768, MTP OFF, F16 KV, `-b 2048 -ub 512`. `Status=OK`, exit=0, `truncated=0` for both.

| Run | `QWEN4EXP_QSA_GATHER` | PP tok/s | TG tok/s | PP eval ms | TG eval ms | Run ID |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| OFF | 0 | **468.75** | **22.95** | **63,054.46** | **2,745.52** | `20261103-014000-011-cli-rocm-b12013-ctx32768-abc088cc6251` |
| ON | 1 | **468.08** | **22.30** | **63,144.75** | **2,825.16** | `20261103-014250-967-cli-rocm-b12013-ctx32768-60ad2994a9a5` |

- Gather ON is **−2.83% TG** (22.30 vs 22.95 tok/s) and **−0.14% PP** for one 64-token run per arm; generation evaluation +79.64 ms, prompt evaluation +90.29 ms. **Do not claim statistical significance, a stable model-specific crossover, or a confirmed regression.** At only 32k, extra compact K/V gather+convert dispatches may offset the smaller Full-KV Attention savings, and normal run variation is another viable explanation; this was not a matched repeated speed ABBA.
- **Gather activation PASS:** ON stderr contains `qwen4exp_common005_v1 graph_built=compact n_kv=32768 n_sel=2051`; OFF doesn't. Same verified `b12013 / f29592d6a` executable SHA256 `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628` and runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`. Both original IQ4 model paths/binary size **93,682,576,992 bytes**, `qwen4exp`, `IQ4_XS`, 49/49 layers offloaded; local GGUF SHA not recomputed in this ZIP.
- **Output:** normalized outputs **byte-identical** (1,810 bytes; SHA256 `8d65bde7d33a5a52557186e47137eadd0108351a50e6a8a5428b83252e885818`), despite different raw stdout SHA. This passes this 64-token smoke comparison only; it is **not** the MH search correctness test.
- **Telemetry:** both Performance P-MODE start/end, `PModeChanged=false`, high-GPU-load average clock **~2,874 / 2,876 MHz**, high-load VRAM clock **1,000 MHz** both, high-load GPU power **121.194 / 121.367 W** (Performance-like), 54 ADLX samples each; named-process background `Observed, PossibleNoise=false` but short bursts cannot be excluded. Neither shows a clear P-MODE/clock anomaly. `ResourceMonitorEnabled=false`.
- **Memory:** ROCm managed allocation projection is **62,509 MiB** at 32k (ROCm model 61,222 MiB; context ~1,072 MiB; compute 215 MiB) with **~46,195 MiB free reported by the backend at end**; model also uses CPU and ROCm_Host buffers. Unlike the former Vulkan 128k 93.3 GiB GPU-committed measurement, these ROCm figures make a 128k attempt plausible, but **a successful 32k load never proves the larger context will allocate or fit**. Preserve Performance P-MODE, 96GB UMA setup, and stop on OOM rather than substituting a different model/config.
- **Gate decision:** 32k original IQ4 Gather OFF/ON activation, stability, and limited output comparison **PASS**, despite a small TG decrease in these single runs. Proceed to frozen 128k MH-128K **seed20261025** quality screening (`-OnlyCase seed20261025`) after input/manifest VALID and PlanOnly verification (expect 8 runs). **Do not infer Gather's 128k IQ4 throughput from this 32k short check**. No extra 32k speed ABBA needed to answer the current quality question. If 128k fails OOM, label capacity issue and continue IQ3 only. If 128k has a consistent *paired* quality regression, inspect per-question failures/repeats before considering default-on.

## 2026-11-03 — MH-128K seed 20261025: IQ3/IQ4 ROCm OFF/ON quality (8/8 PASS)

User-supplied archive: `20261103-024913-692-cli-rocm-b12013-ctx131072-e89eccbd8209.zip`, SHA256 `0cf3b82be548d9afa51848dc46d83fd8f79da83571e93c864000c876975640c1`. This **multi-run ZIP includes exactly eight complete leaf run folders**; scored summary for each was supplied in chat, and logs/response rows were independently inspected from the ZIP. This is the FIRST matched ROCm MH-128K seed-20261025 quality screen, **not** a repeat of the 2026-10-25 Vulkan experiment.

Every run used **the same 111,166 prompt tokens**, 239 generated answer tokens, original frozen A/B inputs, context 131072, MTP OFF, F16 KV, `-b 2048 -ub 512`, `--temp 0 --top-k 20 --min-p 0.05 --seed 1234`, the verified `b12013 / f29592d6a` patched source, CLI SHA256 `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628`, TheRock ROCm runtime digest `df577616ae33fcec7984f6ae17441070955c08882d1d91f83c86f57864257684`. Original `UnslothPle16` and original `Qwen38Iq4XsPle16` (not abliterated Huihui) were loaded. Both question-order inputs are reproducibly distinct: A SHA256 `8605a7b23cca9334e93aa36313b7c12655e66c821bd9db1ad817445172444b80`, B `fdbb72bb065010e3ca4aa8b12d4ee047a0fd4033a78bf61b73f829e77b257aed`. The scorer accepted these as frozen seed-20261025 inputs (per user-supplied scoring output).

| Order / run ID prefix | Model | Q order | Gather | Main score | PP tok/s | TG tok/s | Q03 |
| --- | --- | --- | --- | --- | ---: | ---: | --- |
| 1 `015158-880` | IQ3 XXS | A | OFF | **11/12** | 288.14 | 18.61 | `VAL-94632CB08D88` (source decoy) |
| 2 `020031-182` | IQ3 XXS | A | ON | **12/12** | 288.39 | 23.25 | correct `VAL-A283F4B92A37` |
| 3 `020854-333` | IQ3 XXS | B | ON | **11/12** | 287.44 | 23.33 | same source decoy |
| 4 `021723-748` | IQ3 XXS | B | OFF | **11/12** | 285.27 | 18.64 | same source decoy |
| 5 `022552-661` | original IQ4 XS | A | OFF | **12/12** | 314.26 | 17.62 | correct |
| 6 `023342-906` | original IQ4 XS | A | ON | **12/12** | 314.30 | 21.74 | correct |
| 7 `024128-130` | original IQ4 XS | B | ON | **12/12** | 313.91 | 21.72 | correct |
| 8 `024913-692` | original IQ4 XS | B | OFF | **12/12** | 314.13 | 17.61 | correct |

**Quality findings:**
- IQ3, seed 20261025: **Gather OFF 22/24**, **ON 23/24** across A/B. Only **Q03** ever failed; all three failures return precisely `VAL-94632CB08D88`, classified `source_decoy_compatible`. One ON result (A) corrected this to the gold `VAL-A283F4B92A37`. No evidence of an ON regression; **do not call the one improvement causally proven**, due to known ROCm fixed-seed output variation and only one run per cell.
- Original IQ4: **Gather OFF 24/24**, **ON 24/24** across A/B. All four IQ4 normalized output SHA256 values are **byte-identical** (`e9f0575b797ac50db8d4a675588de679214103ceebee59cf4935d1c447fa1f79`). For IQ3, all three Q03-miss runs have the same full normalized-output fingerprint (`7d4eaaa7d54ca01e0274...`); IQ3 A ON differs and is correct. This gives unusually clean bounded parity evidence for the IQ4 cohort but **is not numerical/logit equivalence**.
- **All eight**: Q13 local 2-hop and Q14 direct correct, output format correct with **14/14 Q lines**; answer generation complete in 239 tokens, **not exhausted at `-n 512`**; `truncated=0`, `Status=OK`, exit 0, `RuntimeArtifactStatus=Verified`, P-MODE Performance start/end, `PModeChanged=False`, power category Performance-like and no named-process `PossibleNoise` indication. Both question-order variants have correct `InputIdentity` in `conditions.json`. Each ON run emitted `qwen4exp_common005_v1 graph_built=compact n_kv=131072 n_sel=2051`, none in OFF. All 49/49 model layers are offloaded in both quantizations.

**Throughput side observations (NOT the main purpose of these answer-quality runs):**

| Model | Mean OFF PP | Mean ON PP | Mean OFF TG | Mean ON TG | Gather ON TG gain |
| --- | ---: | ---: | ---: | ---: | ---: |
| IQ3 XXS | 286.71 | 287.92 | 18.625 | 23.290 | **+25.05%** |
| original IQ4 XS | **314.20** | **314.11** | 17.615 | 21.730 | **+23.36%** |

- Original IQ4's **PP is consistently faster than IQ3's** despite larger GGUF: matched OFF means ~**+9.59%** IQ4 (314.20 vs 286.71 tok/s), or ~33.9 s less processing time for the common 111,166 input. IQ3 generates faster on this workload. Do not assume smaller file -> faster PP on HIP.
- Source logs show materially different per-tensor quantization makeup: IQ3 has `q6_K:250`, `iq2_s:94`, `q8_0:248` tensors, whereas original IQ4 has `q8_0:502`, `iq3_s:94`, `q6_K:1`; both also have `f32:557`, `bf16:24`. Hypothesis: **different HIP quantized matrix-multiplication/dequantization kernels and batching efficiency**, possibly with allocation/transfer/cache differences. **No kernel-level causal attribution** has been profiled on this A/B and no per-quant speed claim is justified without RGP or a controlled type/operation microbench.
- IQ3 ROCm0 model buffer ~**50,191 MiB** versus IQ4 ~**61,222 MiB**; CPU model buffers both ~**27,466 MiB**, GPU KV and compute buffer footprints same (3072+768 MiB and 337 MiB). GPU-clock averages under high load IQ3 ~**2894 MHz**, IQ4 ~**2889 MHz**, while VRAM clock varies around **933–938 MHz** IQ3 and **962–965 MHz** IQ4. These *full-run high-load averages* do not establish cause of PP differences, and alone do not explain the ~9.6% gain. No obvious P-MODE/CPU background drift confound observed.
- Gather changes **decode**, not long PP. Small apparent PP ON/OFF differences are measurement drift; in particular IQ3 A/B OFF PP differs 288.14 vs 285.27 while both Gather OFF. This eight-run screen is **not** a randomized/repeated speed ABBA; existing 64k/128k/256k IQ3 ABBA is the primary speed evidence.
- Historical b11592 Vulkan seed 20261025 IQ3 A/B was **12/12, 11/12**; new ROCm OFF is **11/12, 11/12**. That backend/build difference is **not** evidence of a Gather effect. Original IQ4 Vulkan and the new ROCm both scored **12/12 A/B**.

**Gate decision:** **PASS** seed20261025 basic quality parity screening for IQ3 and original IQ4, with the Q03 IQ3 variation explicitly preserved. Gather still **source default OFF**; no broader production approval. **Next:** run the same frozen **seed20261026** 8-case `-OnlyCase seed20261026 -StopOnError` cohort and independently score it with that seed's manifest. This verifies another content/position configuration and may reveal IQ3's prior borderline cases. If an ON-only repeatable regression emerges, perform targeted paired repeat at the exact question order/seed before attributing it to Gather. The deferred RGP CPU-bound gap and ROCmFP4 backend support question remain separate topics.

## 2026-11-03 — MH-128K seed 20261026: 8-run quality evidence and IQ4-B Q08 targeted-repeat HOLD

**Evidence provided:** eight complete leaf folders in `20261103-041033-319-cli-rocm-b12013-ctx131072-11fc8f31cba3.zip`, SHA256 `398e3717c322f1ebddae99db84a3c822d68c5c5158fec2a84ff46e94c8c2f215`; original user scorer `common005-details2.json` SHA256 `fbf9c1d77ad0eb1f964e5f6aa973ad0b8ff244f58880d37c05e67fc51f44a2f9`, `common005-scores2.csv` SHA256 `f038b338fed2481a7b08886c5fca3b5d30c3ce4fa899cfdb84fbc38bec784783`. JSON independent oracle returned `VALID`, seed `20261026`, **1137 records**, token count verified, frozen input hashes A `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3` and B `694edd15bb2f762a530b437800f67d3dc84eb085be17429e828e060a4fd69ef4`. Every `conditions.json` matches the appropriate A/B SHA; each run processed **111,148 prompt tokens** in 131072 context, **no truncation**.

| Order / RunId prefix | Model | Q-order | Gather | Main /12 | PP tok/s | TG tok/s | Gen tokens | Notable |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 `031008-455` | IQ3 XXS | A | OFF | **12** | 286.45 | 18.46 | 250 | all correct |
| 2 `032022-668` | IQ3 XXS | A | ON | **12** | 283.38 | 23.31 | 250 | all correct |
| 3 `032929-742` | IQ3 XXS | B | ON | **12** | 287.43 | 23.27 | 250 | all correct |
| 4 `033755-299` | IQ3 XXS | B | OFF | **12** | 284.27 | 18.71 | 250 | all correct |
| 5 `034706-284` | original IQ4 XS | A | OFF | **12** | 313.38 | 17.67 | 250 | all correct |
| 6 `035455-682` | original IQ4 XS | A | ON | **12** | 313.76 | 21.77 | 250 | all correct |
| 7 `040241-364` | original IQ4 XS | B | ON | **11** | 313.43 | 21.77 | 251 | **Q08 near_link_decoy** |
| 8 `041033-319` | original IQ4 XS | B | OFF | **12** | 313.97 | 17.68 | 250 | all correct |

- **Only failure: IQ4 seed20261026 B / Gather ON / Q08 (H, two-hop).** Expected `Q08=VAL-7FEC0BE34E44`, observed `Q08=VAL-379D05DD15C1`, independent scorer classification **`near_link_decoy`** (one-character-near `link_code`, target role-compatible). This classification identifies a possible answer pathway, **not proof** of which intermediate inference step failed. In the identical B prompt with Gather OFF, Q08 was correct. Q08 also correct in IQ4 A OFF/ON. The incorrect run generated **251** vs the otherwise consistent **250** tokens.
- **Output stability:** the four IQ3 runs (including A and B, OFF and ON) have **the same normalized stdout byte SHA256** `4463a9bc16f71697f63bee44ec6f04805aa95fe9bef9b08dc150180c4c60d622`. IQ4 A OFF / A ON / B OFF all share normalized SHA256 `edf7e5a6dd7614aa91063d22a8d1ecceb7717bd3118f07e2a30d33f1524ba375`; IQ4 B ON has unique SHA256 `5ae41fdec40435e185af8befeef92155eb352e4f152a878695b1e029a96e4d34`. **One ON-only difference is a regression *signal* but not causal proof** given fixed-seed ROCm QSA output nondeterminism, and the absence of an ON/OFF repeated same-cell sample.
- All **8/8** `Status=OK, ExitCode=0, RuntimeArtifactStatus=Verified`, binary `b12013/f29592d6a`, `llama-cli` executable SHA256 `4aa6dd0c1fd47baba0b0861be7b89c7cca4ad39c266f090f9bd04d9ddb81a628`, same verified ROCm runtime digest as seed20261025. Each ON stderr has one `qwen4exp_common005_v1 graph_built=compact n_kv=131072 n_sel=2051`, OFF has none. 49/49 GPU layers, single sequence, F16 KV, MTP OFF. All Q13/Q14 correct, `format_compliant=true`, and no extraction warnings/issues.
- All start/end **Performance** P-MODE, ADLX classification consistent (high GPU-load mean power **117.281–119.458 W**), temperatures max **81–83 °C**; no evident clock collapse or fatal GPU error. IQ3 high-load average VRAM clock varies **921.81–933.32 MHz** and below-900 sample count 9–26; original IQ4 average **960.41–965.93 MHz**, below-900 0–1. Named background monitor indicates `PartialCoverage/PossibleNoise=null` for IQ3 A OFF only, `Observed/PossibleNoise=false` for the other seven; these probes do not rule out transient OS activity.

**Seed20261026 speed summary, quality-run side observation (two runs per arm, not dedicated repeated performance ABBA):**

| Model | PP OFF mean | PP ON mean | TG OFF mean | TG ON mean | ON TG change |
| --- | ---: | ---: | ---: | ---: | ---: |
| IQ3 XXS | 285.360 | 285.405 | 18.585 | 23.290 | **+25.32%** |
| original IQ4 XS | **313.675** | **313.595** | 17.675 | 21.770 | **+23.17%** |

IQ4 PP exceeds IQ3 by about **+9.92%** in the matched OFF condition (313.675 vs 285.360), matching seed20261025's IQ4 PP advantage. Relative quantized kernel/matrix-multiplication efficiency and somewhat higher VRAM clock are **possible contributors, not proven causal mechanisms**. PP OFF vs ON is near-equal, and Gather applies to decode.

### Combined two-seed 16-run correctness (distinct question sets but A/B correlated)

| Model | Gather OFF (2 seeds × A/B) | Gather ON (2 seeds × A/B) |
| --- | ---: | ---: |
| Unsloth IQ3 | **46/48** | **47/48** |
| Original Unsloth IQ4 | **48/48** | **47/48** |
| **Both models** | **94/96** | **94/96** |

- Seed20261025 had IQ3 Q03 source-decoy error in three arms (IQ3 A OFF, B OFF and B ON); IQ3 A ON was correct. Seed20261026 IQ3 **all 4 runs exactly correct**. These do not imply a Gather quality improvement.
- Seed20261025 original IQ4 **4/4 runs 12/12**, seed20261026 **3/4 runs 12/12**, only `IQ4-B ON` missed Q08. This does not establish a systematic Gather regression; nor does the **94/96 vs 94/96** aggregate prove numerical parity.

**Decision: overall bounded ROCm quality screen completed, but COMMON-005 normal-use Gather-ON promotion remains HOLD pending targeted repeat.** Do **not** rerun the entire 16-case set or modify the patch on a single miss. Narrow follow-up for precisely the original IQ4 `seed20261026` Q-order **B** (A/B here means question order; separate from Gather flag):

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-common005-mh128k-quality-20261103.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan $plan -OnlyJob mh-IQ4-B -OnlyCase seed20261026 -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan $plan -OnlyJob mh-IQ4-B -OnlyCase seed20261026 -StopOnError
```

This yields **two new runs**, Gather **ON then OFF** using the exact same model, input SHA and executable. Score with `common005` seed20261026 manifest. If ON correct, interpret the original miss as **non-reproducible in the first repeat**, not conclusive random noise or mathematical parity. If ON misses Q08 again, or OFF also misses, run **one more identical 2-run matched pair**, then compare per-question error distributions. Do not label Gather causally harmful merely because it correlates with the first one or two errors under ROCm QSA top-k non-determinism; systematic ON-only mistakes over repetitions warrant numerical-path diagnostics. Preserve default OFF until this review. Broad 256k repeat and new RGP are not needed now.

## 2026-11-03 — IQ4-B seed20261026 exact paired repeat: Q08 miss NOT reproduced

**Targeted follow-up after the one IQ4 ON-only Q08 miss:** user supplied `20261103-082223-580-cli-rocm-b12013-ctx131072-11fc8f31cba3.zip` (SHA256 `72273a92b21d495fef954e40885c1ea96570e49a9badfc59e13064e3d83d8933`), `common005-details3.json` (SHA256 `b0097b89d314fb8d947021253a0510cfaa6767a981fdab39f4e2a67431bfcef2`) and `common005-scores3.csv` (SHA256 `fafb3b2527eddedfcac169a44b1ab277df500c1957af827c59102e25c0e3fc52`). Scorer `validation.status=VALID` for frozen 1137-record MH-128K seed `20261026`, Q-order B SHA256 `694edd15bb2f762a530b437800f67d3dc84eb085be17429e828e060a4fd69ef4`; independent archive contents/conditions inspected.

| Chronological run | Model / Q-order / Gather | Primary score | PP tok/s | TG tok/s | Generated | Normalized output SHA256 |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `20261103-081434-330` | Original IQ4 / B / **ON** | **12/12**, Q08 correct | 313.55 | 21.73 | 250 | `edf7e5a6dd7614aa91063d22a8d1ecceb7717bd3118f07e2a30d33f1524ba375` |
| `20261103-082223-580` | Original IQ4 / B / **OFF** | **12/12**, Q08 correct | 313.65 | 17.70 | 250 | `edf7e5a6dd7614aa91063d22a8d1ecceb7717bd3118f07e2a30d33f1524ba375` |

**Exact answer-parity observation:** the two retry normalized outputs are **byte-identical** (1774 bytes) and identical to the three original-IQ4 all-correct outputs from seed20261026. The original first-run **B ON Q08 near-link miss** had distinct full-answer bytes and 251 generated tokens; it **did not recur** in the first matching same-seed paired repeat. This does **not** prove it was random nondeterminism, exclude a rare ON-specific issue, or establish logits/numeric parity.

**Condition / activation checks:** both `Status=OK`, `ExitCode=0`, `RuntimeArtifactStatus=Verified`, b12013 / `f29592d6a`, same IQ4 GGUF path; 111,148 prompt tokens, 131072 context, generated 250, `truncated=0`, no scorer issues, E/M/H each 4/4, local Q13/Q14 correct and format compliant. ON alone logged `qwen4exp_common005_v1 graph_built=compact n_kv=131072 n_sel=2051`; OFF did not. Both P-MODE Performance start/end and ADLX present; 205 monitor samples each, high-load mean GPU clock ~2892.12 (ON) vs 2889.22 MHz (OFF), high-load VRAM clock ~963.07 vs 963.50 MHz, GPU temp max 83 vs 85 °C, no serious reported run issues. No RGP or extra speed ABBA was necessary to judge this answer-quality repeat.

**Bounded quality conclusion after 18 total 128k MH runs (16 full + two targeted repeats):**

| Model | OFF primary correct | ON primary correct |
| --- | ---: | ---: |
| Unsloth IQ3 | 46/48 | 47/48 |
| Original Unsloth IQ4 | **60/60** | **59/60** |
| Total (non-independent A/B questions) | **106/108** | **106/108** |

These are *response instances*, not independent statistical questions: original IQ4 ON has a **single non-reproduced Q08 error**, IQ3 has repeated seed20261025 Q03 source-decoy error with variability among flags. No repeated systematic **ON-only** regression demonstrated in this limited comparison. The historical Vulkan b11592 reference was a different backend/build. QSA ROCm output reproducibility remains unresolved, so **quality equivalence or improved reasoning is not proven by matched aggregate scores**.

**Decision: targeted quality follow-up COMPLETE; 128k ROCm IQ3/IQ4 MTP-OFF Gather ON has a bounded quality-screen PASS for explicit opt-in exploratory/daily testing.** Keep `QWEN4EXP_QSA_GATHER` **default OFF in source**, preserve fallback and published b11908 tag. It is reasonable to trial `=1` **only with these observed hardware/model/context/backend/MTP conditions** with easy rollback `=0`. Do **not** auto-enable it generally; no MTP-ON/Vulkan-active-path/256k full-answer quality test or numerical parity validation exists. If future use shows consistent ON-only factual differences or repeats of Q08, reopen targeted repeated tests and numerical QSA path investigation.

**Deferred separate performance research:** old Vulkan b11592 MH-128K model quantization/PP comparisons show original IQ4 ~0.7% ahead of IQ3, Huihui and ROCmFP4 within ~1–1.3% ahead; present ROCm b12013 original IQ4 ~9–10% ahead of IQ3. Not explained causally by clocks or GGUF size alone. User wants a **separate later** r6 updated-optimizations quantization-by-model speed comparison; keep it distinct from this finished Gather quality gate. Other pending priorities include r5 TOOL-001 real-input llama-bench port, mask/MoE route checks and alternative engines.
