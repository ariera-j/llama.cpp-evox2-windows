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
