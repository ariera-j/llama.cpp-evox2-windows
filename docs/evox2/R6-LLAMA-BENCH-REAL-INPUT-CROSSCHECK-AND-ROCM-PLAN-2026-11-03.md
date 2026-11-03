# TOOL-001 follow-up: short Vulkan PP cross-check and ROCm build/smoke

Date: 2026-11-03 JST. Status: **plan only; no new execution logs, code changes or benchmark measurements**.
Branch: `feature/r6-llama-bench-real-prompt-20261103`.
Baseline native C++ functional verification: [Gate 1-4](R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md) and [Gate 4+](R6-LLAMA-BENCH-REAL-PROMPT-GATE4PLUS-RESULTS-2026-11-03.md).

## User's intended scope

The r5 corpus-dependency experiment has already been completed. Do **not** run another 7-corpus × 2-context sweep. Instead, perform a quick r6 check for the earlier rank/ratio trends and approximate real-input `llama-cli` parity; then separately build/smoke a Windows ROCm backend that can be reused for future IQ3/IQ4 quantization PP comparisons.

### r5 source-derived reference (not a prediction for r6)

From [r5 Vulkan corpus ABBA](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md) and [r5 ROCm comparison](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md), 64k `-p 61789 -c 65536`, warmup ON, 2048/1024 batch, f16 KV, MTP OFF, Qwen3.8 Flash Next IQ3 PLE16:

| Source | Vulkan QSA UNION ON | ROCm |
|---|---:|---:|
| Repeated Japanese ANLP | 342.640 tok/s | 394.030 tok/s |
| llama.cpp C/C++ | 378.014 tok/s | 394.669 tok/s |
| Native random | 323.346 tok/s | 415.821 tok/s |

Main observation: Vulkan text/code/random ranking differs considerably; ROCm corpus spread is much narrower, with random fastest in this set. Two same-binary repetitions for a subset of r5 Vulkan results, one for individual ROCm results. Do not assign statistical significance to small gaps. r5 `llama-cli` cross-check 128k ANLP QSA OFF/ON 179.34/307.15 vs `llama-bench` 183.66/310.68, but the prompts/methods are not guaranteed token-identical. Historical r4 64k CLI 337.45 vs real bench 337.68 also comes from another build.

## Stage A: short r6 Vulkan comparison

Use the already verified Vulkan `build-vulkan-bench-real-r6` b12032. Same model, 65536 context, K/V f16, 2048/1024 batch, threads 4, 61,777 PP tokens, 2 timed bench repetitions with warmup enabled. Why 61,777: `nlp-survey-ch3-d7-b1.txt` was tokenized by this model to 61,777 tokens; the historical r5 61,789-token setting is **12 tokens too long** for this particular source and must not be reused. For this source and 61,777, `head` equals full source; code source must contain at least 61,777 tokens. Source and code file SHA and size must be retained.

Opt in explicitly to Vulkan QSA UNION `GGML_VK_QSA_UNION=1`, threshold 32768. QSA UNION is default OFF in r6. Use `QWEN4EXP_QSA_GATHER=0` so the independent ROCm QSA-gather optimization does not interfere in future cross-backend checks.

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
$bin = '.\build-vulkan-bench-real-r6\bin\Release'
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_MIN_KV = '32768'
$env:QWEN4EXP_QSA_GATHER = '0'

$bench = @{
    LlamaBench = (Resolve-Path "$bin\llama-bench.exe").Path
    ModelKey = 'UnslothPle16'
    Context = 65536
    PromptTokens = @(61777)
    GenerationTokens = @(0)
    Depths = @(0)
    Repetitions = 2
    Batch = 2048
    UBatch = 1024
    Threads = 4
    KvType = 'f16'
    GpuLayers = 999
    CpuMoe = 0
    FlashAttn = 'auto'
}

.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @bench -InputKey '64k' -PromptSlice head
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @bench

# Optional third bench: use the same llama.cpp C/C++ corpus as r5.
# $codeFile = '<full path to llamacpp-inference-code.txt>'
# .\tools\evox2\benchmark\Measure-LlamaBench.ps1 @bench -InputFile $codeFile -PromptSlice head

# CLI PP: same source text as the real bench; no Jinja chat template.
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
    -LlamaCli (Resolve-Path "$bin\llama-cli.exe").Path `
    -ModelKey 'UnslothPle16' -InputKey '64k' `
    -Context 65536 -GenerationTokens 1 `
    -Batch 2048 -UBatch 1024 -Threads 4 `
    -GpuLayers 999 -CpuMoe 0 -FlashAttn auto `
    -KvType f16 -Fit off -PromptCacheMiB 0 `
    -NoJinja -NoSingleTurn
```

`llama-cli` must generate >= 1 token because its wrapper disallows `-GenerationTokens 0`. The reported CLI prefill count may include a BOS token and differs from bench tokenization, batching and output requests. Compare the measured prompt-processing segment only; do not confuse total CLI time with PP throughput. This is a directional cross-check, not a claim of bit-identical request paths. Record model file identity, build/source SHA, environment (especially QSA union active), PowerShell logs, P-MODE/ADLX, actual CLI prompt count and GPU errors. If CLI result deviates materially from real bench, inspect token count, Jinja, QSA activation, prompts and model/KV/FA settings before changing code.

Expected directional reference: in r5 Vulkan QSA union ON, code > ANLP > random; in ROCm random >= code~ANLP, with much smaller corpus spread. This **does not** impose a rigid performance threshold on r6.

## Stage B: separate ROCm build (after reviewing Stage A)

Use **Visual Studio 2022 x64 Native Tools PowerShell** (MSVC 14.44) with the existing TheRock 10.0.0 venv; preserve prior r6 Vulkan output and b11908 preview. No new branch is necessary to build the same C++ source with ROCm. Do not use `-RunBackendTest` / entire `FLASH_ATTN_EXT` matrix on this gfx1151 Windows stack (previously correlated with GPU watchdog/HIP trap); targeted operator testing only if later required.

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
& C:\TheRock\build\.venv\Scripts\Activate.ps1
rocm-sdk version
git status --short
$env:QWEN4EXP_QSA_GATHER = '0'
Remove-Item Env:\GGML_VK_QSA_UNION -ErrorAction SilentlyContinue
Remove-Item Env:\GGML_VK_QSA_UNION_MIN_KV -ErrorAction SilentlyContinue

.\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-bench-real-r6 `
    -Parallel 4 -AmdGpuTarget gfx1151

$rocmBin = '.\build-rocm-bench-real-r6\bin\Release'
& "$rocmBin\llama-bench.exe" --version
& "$rocmBin\llama-bench.exe" --help
& "$rocmBin\llama-bench.exe" --list-devices
& "$rocmBin\llama-cli.exe" --list-devices

Get-FileHash "$rocmBin\llama-bench.exe" -Algorithm SHA256
```

Required build check: `evox2-build.json` says `BuildIdentity.Status=Verified`, same branch/clean source; HIP runtime DLL staging succeeds; `ROCm0` AMD Radeon 8060S appears with **non-zero GPU memory**, no unintended Vulkan backend device; `-f/--prompt-file`, `--prompt-slice`, `-c/--ctx-size` appear in help, and `--version` source ID matches manifest. `Build-ROCm.ps1` stages TheRock runtime by default; do not use `-SkipRuntimeDllCopy`. Having a GPU device listed is not a substitute for model decode smoke.

## Stage C: ROCm 256-token paired smoke

Run sequentially, not alongside Vulkan or llama-server; avoid exhausting UMA. Reuse same model/source as Vulkan smoke, but distinguish backend binary SHA. QSA gather remains explicitly OFF. These are smoke tests, not performance comparisons.

```powershell
$smoke = @{
    LlamaBench = (Resolve-Path "$rocmBin\llama-bench.exe").Path
    ModelKey = 'UnslothPle16'
    ExpectedBackend = 'ROCm'
    Context = 1024
    PromptTokens = @(256)
    GenerationTokens = @(0)
    Depths = @(0)
    Repetitions = 1
    Batch = 256
    UBatch = 256
    Threads = 4
    KvType = 'f16'
    GpuLayers = 999
    CpuMoe = 0
    FlashAttn = 'auto'
    NoWarmup = $true
}
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @smoke
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @smoke -InputKey '64k' -PromptSlice head-tail
```

Accept each if exit 0, valid `llama-bench.json` + `result.json` + `conditions.json`, a single native `n_prompt=256` record, valid input SHA for real source vs null for random, no CPU-only fallback/OOM/reset; verify ROCm active path in logs.

## Follow-on: ROCm quantization-dependent PP

Start with **IQ3 PLE16 vs original IQ4 PLE16** using one ROCm binary, same real input raw hash, head slice, model-generation/MTP OFF, `QWEN4EXP_QSA_GATHER=0`, same context, prompt length, batch/ubatch, f16 KV, flash-attn auto, GPU layers and clocks. Initially one short sanity and matched 64k samples; increase repeats if a difference matters. Historical r6 ROCm b12013 128k quality-task incidental PP averages: IQ3 286.04 vs IQ4 313.94 tok/s (different input, not an equal-controlled bench); it motivates but **does not establish** a causal quantization speed gap. Quantization-vs-input interaction and gathering ON/OFF should be separate experiments.

Do **not** include Agention `ROCmFP4 FAST v2` under the assumption that it runs on the ROCm backend: current r6 has Vulkan/CPU support but lacks complete HIP dequant/GET_ROWS/MMQ/MMVQ integration for the custom tensor types. That is an independent later implementation task.

## Stage A Windows actual measurements — 2026-11-03

**Verdict: directional input-dependence reproducibility PASS and approximate native CLI-vs-bench PP parity PASS.** All three `llama-bench` runs completed normally. The one `llama-cli` run completed prompt processing and printed its PP timing, but its wrapper was manually stopped after the program stayed interactive; thus no finalized `result.json` was produced. The CLI PP metric itself is valid as a diagnostic from stderr, **not** an ordinary completed wrapper-run result.

User ZIP: `20261103-140329-613-bench-vulkan-b12032-ctx65536-a98b531e3a08.zip` (3 full bench run directories + 1 partial CLI directory). Raw ZIP remains outside Git.

Build: Vulkan b12032 `c4ddd239b`, Clang 20.1.8, Radeon 8060S, UMA label 96GB, common Qwen3.8-Flash-Next UD-IQ3_XXS Ple16 GGUF (81961816672 bytes; full model hash unavailable). Native bench executable SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`; CLI executable SHA256 `e8516bc136f2340af45f622d593e199db9f826e41249518ce8bfb642f4956584`. `git Dirty=false`. All four recordings have `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `QWEN4EXP_QSA_GATHER=0`. CLI and all three bench stderr logs show `qsa-union active (r6)`.

All bench runs: `-p 61777 -n 0 -d 0 -r 2 -c 65536 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16`; warmup **enabled**, `--prompt-slice head` for real files. Each gives 1 JSON native row, 2 timed samples, `Status=OK`, `ExitCode=0`, `ParseException=null`, P-MODE Performance throughout, `PModeChanged=false`, ADLX monitor completed. Named-process background noise probe `PossibleNoise=false` for these runs, with coverage caveats.

| Input | Run id (short) | r6 PP tok/s | timed samples tok/s | r5 comparison, tok/s |
|---|---|---:|---|---:|
| Japanese technical (`nlp-survey-ch3-d7-b1.txt`) | `9137728a98e7` | **348.278425** | 348.648 / 347.909 | 342.640 |
| Native random (no `-f`) | `6b5f6b46f3d6` | **322.695353** | 322.864 / 322.527 | 323.346 |
| llama.cpp code (`llamacpp-inference-code.txt`) | `a98b531e3a08` | **387.549749** | 387.815 / 387.284 | 378.014 |

Real input identities:
- Japanese technical `nlp-survey-ch3-d7-b1.txt`: 304931 bytes, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`.
- llama.cpp code `llamacpp-inference-code.txt`: 6168010 bytes, SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`. **This SHA matches r5's seven-corpus code input**; r5 sliced 61789 tokens, r6 slices 61777.
- **Crucial difference:** the **r5 repeated Japanese ANLP** reference used `nlp-survey-ch3-d31-b1.txt` (SHA `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`), not r6's shorter `d7` file. Thus only the *directional ranking*, not precise numeric ANLP cross-version speed, is directly comparable. These are distinct files; do not claim an exact same-prompt benchmark. r5 prompt=61789, r6=61777 (12-token difference), though context and many PP settings are the same.

Within r6:
- code vs Japanese: **+11.28%**
- Japanese vs random: **+7.93%**
- code vs random: **+20.10%**.

The rank **code > Japanese > random** matches the r5 Vulkan QSA-union-ON direction; r5 code-vs-ANLP +10.32%, ANLP-vs-random +5.97%. Changing input source, source refresh, software versions and other environmental differences preclude causal attribution for absolute small differences (+1.65% ANLP, +2.52% code, -0.20% random). Prior r5 evidence was a set of warmup-ON measurements with other software source and environment details. No more large corpus sweep is needed for this limited acceptance question.

### CLI cross-check and its apparent hang

Run `20261103-130931-865-cli-vulkan-b12032-ctx65536-f6b5c06e4100`. Same file SHA/model/backend/context/PP batch/f16 KV/QSA-UNION conditions as the Japanese bench, but command had `-NoJinja -NoSingleTurn` on the **PowerShell wrapper**, translating to **neither `--jinja` nor `--single-turn` in the native CLI argv**.

Actual native stderr:
- `prompt eval time = 181114.72 ms / 61789 tokens (... 341.16 tokens per second)`; prompt completed normally, one requested generation token was accounted for in stats with 0.00 ms eval.
- `all slots are idle` after `stop processing: n_tokens = 61789, truncated=0` at approximately **4m56s** after native start.
- Then remained in interactive wait until user manually stopped it approximately **50m51s** after start; stderr subsequently shows `cleaning up before exit...` and stdout ends in `> Exiting...`. ZIP has `conditions.json` plus `stdout.log`/`stderr.log` and metrics, but no finalized `result.json` or condition `Status/ExitCode`.
- **Root cause:** earlier instructions incorrectly passed wrapper `-NoSingleTurn`, suppressing native `--single-turn` and leaving CLI in interactive mode after a completed request. The symptom is consistent with intentional input wait, **not** GPU PP still executing. This was an instruction error, not evidence of C++ or Vulkan freeze.
- **Correction:** when re-running CLI, keep `-NoJinja` but remove `-NoSingleTurn`, so wrapper sends native `--single-turn`. Not necessary to rerun 64k solely for this exploratory PP metric.

Comparison: CLI **341.16 tok/s** vs bench **348.278425 tok/s**; bench about **+2.09%** faster by bench/CLI ratio. Important: CLI token count **61789** vs bench `61777` (same raw input file SHA) reveals 12 extra tokens in the CLI path even without Jinja, and the tools use different input/request constructions and reporting. The logs do not isolate exactly where the 12 extra tokens arose; avoid claiming exact token-ID identity or an identified BOS cause. This is a **near-value cross-check, not strict performance parity**.

**Acceptance/next steps:** Stage A quick directional check passes. No code change or Vulkan rebuild is justified. Stage B/C ROCm build + 256-token real/random smoke remain next. Thereafter IQ3-vs-IQ4 quantization PP comparisons at matched context with the same ROCm binary and the same verified raw source. `QWEN4EXP_QSA_GATHER=0` is fixed until a separate gather A/B experiment.

## Stage B Windows ROCm build actual result — 2026-11-03 JST

**Build gate PASS.** Actual model PP smoke (Stage C) has **not yet been performed**, so there is no claim of inference correctness or IQ3/IQ4 performance.

User-provided `(rocm-bench)evox2-build.json` generated `2026-11-03T14:24:34.6741034+09:00`, plus manually run `llama-bench.exe --version`, `--help`, `--list-devices`.

| Item | Observed |
| --- | --- |
| Backend/config | ROCm / Release, GGML_HIP=ON, GGML_BACKEND_DL=ON, target gfx1151 |
| Branch/source | `feature/r6-llama-bench-real-prompt-20261103` / `d321e7ff38052be311fde9392598fe02c7548956`, clean |
| Identity | `BuildIdentity.Status=Verified`: stable source; embedded commit matched |
| Build/version | `0.7.0-dev`, b12038, `d321e7ff3`, AMD Clang 23.0.0 |
| Toolchain | TheRock ROCm SDK 10.0.0, VS2022 MSVC 14.44, CMake 3.31.6-msvc6, Ninja 1.12.1 |
| Build directory | `build-rocm-bench-real-r6`, separately from b12032 Vulkan and existing ROCm release binaries |
| Targets | `ggml-hip`, `llama-cli`, `llama-server`, `llama-bench`, `test-backend-ops` |
| GPU | `ROCm0: AMD Radeon(TM) 8060S Graphics (110456 MiB, 110301 MiB free)`; no Vulkan backend loaded |
| Native bench options | `-f/--prompt-file`, `--prompt-slice head-tail/head`, `-c/--ctx-size` all present |
| `llama-bench.exe` SHA256 | `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a` |
| `llama-cli.exe` SHA256 | `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347` |
| Runtime | `StagingPerformed=true`; `Verification=DllAndRuntimeDataHashesVerified`; unified TheRock HIP/rocBLAS/hipBLASLt/rocsolver runtime DLL staging verified |
| gfx1151 libraries | rocBLAS `150` files and hipBLASLt `100` files, source/destination tree digest equal |
| Automatic smoke | `llama-cli --version` and `--list-devices` both exit 0; independent native `llama-bench` invocation also succeeds |
| Broad backend ops | `BackendTestRequested=false`, intentionally avoids unsafe full `FLASH_ATTN_EXT` sweep on this Windows/gfx1151 combination |

The observed build source commit `d321e7ff3` predates subsequent **documentation-only** commits on this feature branch; the modified C++ source has not changed, and the executable identity is internally verified. Do not conflate current remote branch HEAD with the embedded build commit when interpreting the next smoke logs.

### Stage C immediate follow-up

In the same ROCm TheRock shell, keep `QWEN4EXP_QSA_GATHER=0` and avoid simultaneous GPU inference jobs; run `tools/evox2/benchmark/Measure-LlamaBench.ps1` for two short cases on the newly-built executable:

- Random path: `-p 256 -n 0 -d 0 -c 1024 -r 1 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --no-warmup`.
- Real path: same, plus `-InputKey '64k' -PromptSlice head-tail`.

Wrapper must be invoked with `-LlamaBench (Resolve-Path ...llama-bench.exe).Path`, `-ModelKey 'UnslothPle16'`, `-ExpectedBackend ROCm`. Compare source SHA and binary SHA per result; ExitCode=0, native n_prompt=256, JSON valid, ROCm active, P-MODE stable, no ROCm allocation/BLAS errors. Stage C is a correctness/smoke gate, not a throughput ranking.

If Stage C passes, next run same ROCm b12038 binary for IQ3 Ple16 versus original IQ4 Ple16 using fixed real-text hash, batch/ubatch, context and warmup, `QWEN4EXP_QSA_GATHER=0`, MTP OFF. No ROCmFP4 FAST custom tensor quantization until separate HIP implementation is completed.

## Stage C Windows ROCm 256-token smoke actual result — 2026-11-03

**Smoke gate PASS 2/2.** Native ROCm b12038 ran **one real PLE16 IQ3 model PP** workload each in random and file-token head-tail mode. These are correctness/operational tests, not long-context quantization/throughput results.

User ZIP: `20261103-143236-657-bench-rocm-b12038-ctx1024-4c74a84fbd7d.zip`, containing **two complete run directories**, separate per-run `conditions.json`, `result.json`, `llama-bench.json`, `summary.csv`, stdout/stderr and ADLX metrics. The ZIP itself is not committed. Both source and executable identity match the preceding verified b12038 ROCm build:

- Git/source `d321e7ff38052be311fde9392598fe02c7548956`, clean, `feature/r6-llama-bench-real-prompt-20261103`.
- `llama-bench.exe` SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`, b12038, Clang 23.0.0, native `backends=ROCm`, `gpu_info=AMD Radeon(TM) 8060S Graphics`; `ggml-hip.dll` explicitly loaded, no Vulkan backend loaded.
- Model `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`, 81,961,816,672 bytes at the same path in both runs. Model full SHA not calculated.
- Common `-p 256 -n 0 -d 0 -r 1 --no-warmup -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -c 1024`; `QWEN4EXP_QSA_GATHER=0`.

| Case | ConditionId | Input / slice | Native n_prompt | avg_ns | PP tok/s | Status |
|---|---|---|---:|---:|---:|---|
| Random | `12ebcc0c6fb6` | No `-f` / random | 256 | 2351161600 | **108.882350** | OK, exit 0 |
| Real text | `4c74a84fbd7d` | `-f nlp-survey-ch3-d7-b1.txt --prompt-slice head-tail` | 256 | 1195535800 | **214.129932** | OK, exit 0 |

For real-file case input path `C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\long-input-abstract-out\nlp-survey-ch3-d7-b1.txt`, byte size 304931, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`. Input identity null in the random case. Each run: native JSON row count 1, `samples_ns` length 1, `RunException=null`, `ParseException=null`, `PModeAtStart=Performance`, `PModeAtFinish=Performance`, `PModeChanged=false`. ADLX monitor completed with exit 0, 27 random / 26 real CSV samples. Background named-process `PossibleNoise=false` (short-lived/unmonitored processes not ruled out). Both sessions flagged `remote=yes` by ADLX.

**Caveat:** the user shell's captured `Environment.HIP_PATH` points to `C:\Program Files\AMD\ROCm\7.2\` and `HIP_PATH_72` to the same, despite executable manifest's **TheRock 10.0** runtime staging with hash verification. The short tests **passed** and no current mixed-DLL runtime failure is shown; however, for fair later long-context/quantization comparisons use a fresh activated TheRock shell and normalize/record `HIP_PATH` and runtime provenance before timing. Do not interpret environment path alone as proof of actual loaded-DLL path. If needed, inspect process-loaded modules separately.

**No PP speed inference from 256-token smoke:** the real/random ratio (~1.97x) is one short no-warmup run each and differs from r5 64k trends; do not generalize. There is no verbose proof here of every tensor's GPU offload, although native ROCm device was selected and real PP succeeded.

**Decision:** TOOL-001 native r6 real-prompt Vulkan+ROCm functional smoke gates passed. No source changes/rebuild required. Next task: controlled ROCm b12038 **IQ3 PLE16 vs original IQ4 PLE16** long-context PP test using a shared file SHA, `-p` at or below actual token count (the `d7` source provides 61777 token with IQ3; **IQ4 tokenize length must be checked independently**, since tokenization can vary by model). Fix `QWEN4EXP_QSA_GATHER=0`, MTP off; use same context/batch/ubatch/KV/FA and repetitions; check HIP SDK/runtime provenance, P-MODE and artifacts. Custom ROCmFP4 GGUF is outside this supported HIP experiment.
