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

## IQ4 b12032/b12038 128k allocation preflight — 2026-11-03

**Both backends PASS for native IQ4 PLE16 model load and 256-token PP at explicit context 131072.** Does not yet prove processing 126253-token source or GPU memory use under a full 128k workload. Logs provided as paired run ZIP `20261103-145024-894-bench-rocm-b12038-ctx131072-866fc960f647.zip`. ZIP is not stored in Git.

| Case | Run ID | Backend/build | Model | Context | Prompt | PP tok/s | Exit |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| Vulkan | `20261103-144911-745-bench-vulkan-b12032-ctx131072-65320fcdd146` | Vulkan b12032, `c4ddd239b` | original IQ4_XS Ple16 | 131072 | 256 | **237.082434** | 0 |
| ROCm | `20261103-145024-894-bench-rocm-b12038-ctx131072-866fc960f647` | ROCm b12038, `d321e7ff3` | original IQ4_XS Ple16 | 131072 | 256 | **214.603824** | 0 |

- Same GGUF path, size `93682576992` bytes. No full model SHA recomputed in these runs.
- Input: r5 repeated Japanese ANLP `nlp-survey-ch3-d31-b1.txt`, size `1261235` bytes, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, **255169 available raw tokens** (same count from both actual native logs), enough for 126253 tokens.
- Both `Status=OK`, exit0, one native JSON row and one sample, no warmup, `-b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16`. PowerShell status parse clean, P-MODE Performance start/end unchanged, ADLX exited0 with 19/22 samples, named background processes `PossibleNoise=false`.
- Vulkan `GGML_VK_QSA_UNION=1`, threshold32768 but runtime `qsa-union fallback: query count, selection size or KV threshold` because actual prompt is only 256 tokens; no claim that QSA activated in this short smoke. ROCm `QWEN4EXP_QSA_GATHER=0`. TheRock HIP_PATH and ROCM_PATH correctly point to venv root in both logs.
- No OOM, GPU reset, allocation errors observed. **n_ctx 131072 requested** via CLI, and process completed. Logs do not provide an independent verbose `llama_context: n_ctx` row here, so the inference of accepted allocation follows from successful execution on the 128k configured path, not a separate memory/verbose audit.

### Next Gate: 128k PP 12-case matrix

User requested **Vulkan/ROCm × original IQ3/IQ4 × Japanese/Random/llama.cpp code**, exactly 12 cases. Recommended common `-c 131072 -p 126253 -n 0 -d 0 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16`, warmup ON, 1 timed repetition; Japanese/code use raw file with `--prompt-slice head`; random uses unchanged native path. The Japanese source and code source SHA256 are fixed: `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` / `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`. Code is the same r5 file and was previously measured with ample tokens, but verify the current binary's available count in verbose/progress logs (models may tokenize differently).

Vulkan `GGML_VK_QSA_UNION=1`, `MIN_KV=32768`, statistics OFF; ROCm `QWEN4EXP_QSA_GATHER=0`. MTP OFF both. Use known b12032 and b12038 binaries and fixed model identities; no rebuild. Running one **full-length** pilot (`ROCm × IQ4 × Japanese`) before the other 11 protects against the gap between a 256-token allocation smoke and full 126253-token PP success. Stop on error or environmental anomaly. Keep native result JSON, conditions, model/input identities, ADLX/P-MODE and full stderr per case. The assistant supplied a separate temporary standalone PowerShell orchestration ZIP `Evox2-R6-PP128k-Matrix-20261103.zip` with Stage Plan, Pilot, Remaining, All and Package; user runs locally and shares result ZIP, **not a repo file**.

Future comparisons should separate within-backend model quantization ratio, within-backend input rank, and cross-backend ratios; warmup/repetition and other numerical differences matter. This initial 12-case sweep is exploratory; follow-up repetition can be targeted if a small margin or surprising ranking merits it.

## 128k PP matrix Pilot actual result — 2026-11-03

**Pilot PASS: ROCm × original IQ4_XS Ple16 × Japanese ANLP 126253-token PP completed.** Proceed with the remaining 11 cases under the frozen session plan; no need to repeat Pilot or rebuild the source/binary.

User ZIP: `evox2-r6-pp128k-matrix-20261103(1).zip`, containing `matrix-plan.json`, `matrix-records.csv` (one `OK`), and all native logs/monitoring for `runs/01-ROCm-IQ4-Japanese`. Recorded run directory `20261103-150619-433-bench-rocm-b12038-ctx131072-09cb593dd1c9`; actual start `2026-11-03T15:06:20+09:00`, finish `15:21:32+09:00`, elapsed `911.899` sec. ZIP itself is retained outside Git.

| Field | Verified |
| --- | --- |
| Case | `01-ROCm-IQ4-Japanese` |
| Native build | ROCm `llama-bench` b12038 `d321e7ff3`; executable SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a` |
| Model | original Unsloth IQ4_XS Ple16, GGUF 93682576992 bytes, not Huihui; model SHA not computed in run |
| Source | `nlp-survey-ch3-d31-b1.txt` 1261235 bytes, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` |
| Source tokenization | 255169 available, first 126253 used (`--prompt-slice head`) |
| Workload | `-c 131072 -p 126253 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --progress`, **warmup ON** |
| Optimization | `QWEN4EXP_QSA_GATHER=0`, HIP_PATH and ROCM_PATH TheRock 10.0 venv root; no Vulkan QSA flags |
| Native result | `Status=OK`, `ExitCode=0`, `RunException=null`, `ParseException=null`, JSON one row / one PP sample `434009227600 ns` |
| PP | **290.899345 tok/s** (7m14.009s timed); sample-only, not a repeated confidence estimate |
| P-MODE | Performance at start/end; `PModeChanged=false`, no P-MODE warnings |
| ADLX | 456 samples, exit0; high-load (>95% use) 433 samples; mean high-load GPU power `119.432 W` (Performance-like). Across all samples mean GPU clock ~2828 MHz, mean VRAM clock ~998 MHz, VRAM allocated ~67.3 GB at peak |
| Environment | RDP monitor present, no physical candidate found by probe; ADLX still shows consistently high clocks. No observed GPU reset, OOM or HIP error |
| Background | Process probes `Observed`, coverage `Complete`, named `PossibleNoise=false`; does not exclude all transient system activity |

The `QsaActiveLog=False` value in matrix CSV is **expected for ROCm**; Vulkan-specific `qsa-union active` log need not occur in the ROCm run. It does not indicate a missing ROCm path. The ROCm source's `QWEN4EXP_QSA_GATHER` is intentionally OFF.

Native `model_size` reported 93671551580 bytes, distinct from the filesystem GGUF length because native model size uses its own definition; this is not a model identity discrepancy.

Pilot proves 128k-length **actual PP** works with this binary/model/source, unlike the earlier 256-token `-c 131072` allocation preflight. It does **not** prove every future combination, and no 128k throughput difference between models/backends is concluded from this one case.

**Next:** in the same experimental environment with TheRock venv available, run the preexisting matrix runner `& $s -Stage Remaining`. It checks the existing Pilot `OK` record and runs `02` through `12`; no rerun of case `01`. It stops on failure and packages progress. Inspect final 12-case ZIP and validate per-case identities, context, inputs, errors, telemetry and missing cases before describing r6 IQ3/IQ4/backend/input rankings. Do not infer per-case speed from `r5` or the previous short smoke runs.

## Post-TDR comparison plan: finish Vulkan IQ3, then matched llama-cli/llama-bench tests — 2026-11-03

**Scope / sequencing:** After case08 Vulkan-IQ4 Japanese PP failed with Windows 0x141 GPU timeout and was isolated, do **not** restart `Evox2-R6-PP128k-Matrix-20261103.ps1 -Stage Remaining` (it retries failed Case08). Existing original matrix ZIP `evox2-r6-pp128k-matrix-20261103(2).zip`: 7 OK, Case08 FAIL, Case09–12 NOT RUN. User chose first to complete the two *IQ3-only* missing Vulkan cases, then design a small controlled `llama-cli` vs `llama-bench` follow-up.

### Gate 1: complete **only** Vulkan IQ3 Code/Random rows

Original `Cases` mapping (verified in archived PowerShell matrix runner):
- **Case10** `10-Vulkan-IQ3-Random`, native bench-generated random tokens.
- **Case11** `11-Vulkan-IQ3-Code`, raw `llamacpp-inference-code.txt`, SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`, head slice.
- **Excluded:** Case08 Vulkan IQ4 Japanese (TDR), Case09 Vulkan IQ4 Random, Case12 Vulkan IQ4 Code. Existing Case07 Vulkan IQ3 Japanese **306.831891tok/s** already complete.

Temporary downloadable ZIP `Evox2-R6-Vulkan-IQ3-Remaining-20261103.zip` generated for user, containing `Evox2-R6-Vulkan-IQ3-Remaining-20261103.ps1` and README; it is **not checked into GitHub**. This was derived from the exact original matrix runner, with only Case10/11 in the case array; separate session directory `$env:TEMP\evox2-r6-pp128k-vulkan-iq3-only-20261103`, separate ZIP, SHA checks for Vulkan EXE (b12032; SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`) and code corpus and model byte count (IQ3 PLE16 `81961816672`). No ROCm/TheRock prerequisite, no IQ4 loading, no change to the original 12-case records. Stages `Plan`, `Run`, `Package`. Each case `-c 131072 -p 126253 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/ctv f16`, **warmup ON**, `GGML_VK_QSA_UNION=1` + `MIN_KV=32768`, gather0, sparse-disable env removed. If both pass, overall *across original plus separate runs* statuses: 9 OK, 1 FAIL, 2 NOT RUN. Preserve the failed result, do not mark whole matrix successful; compare case07/10/11 Vulkan IQ3 to ROCm IQ3 cases02/03/06 only with noted native random-token reproducibility limitations.

### Gate 2: plan for matched `llama-cli` vs `llama-bench` quantization PP

**Question A — ROCm IQ4 faster in CLI?** Existing b12038 `llama-bench` 128k native JSON (Japanese/Random/Code) shows IQ3 faster than IQ4 **299.151698 vs 290.899345**, **313.880965 vs 308.615225**, **299.941061 vs 291.982779** tok/s, respectively, one run each. Conversely an earlier r6 ROCm b12013 quality-task `llama-cli` incidental 128k PP comparison reported IQ3 ~286.04 and IQ4 ~313.94tok/s on a different workload. **Do not treat these as contradictory on the same input or backend build**. Use the same b12038 **ROCm CLI binary** paired with its verified bench build, same original IQ3/IQ4 model files, a controlled real Japanese prompt, context 64k for an initial lower-risk screen and/or 128k to relate directly to original bench. Run **real text** not native Random for CLI/bench pairs, and ensure prompt *token IDs and prompt count* correspond; native bench `--prompt-slice head` on a long file is **not automatically the same input** as CLI reading the *entire* file. Generate/store controlled truncated prompt files, source SHA, actual token count and preferably token-ID hash/trace before claiming identical input. Same K/V f16, FA auto, batch2048/ubatch1024, GPU offload, MTP OFF, ROCm Gather OFF, P-MODE and environment; judge CLI PP-only timing, not generation speed or total process time. CLI wrapper requires `GenerationTokens>=1`; use 1 token (or minimal bounded) and distinguish this from bench n=0. To avoid prior interactive hang, use `Measure-LlamaCli.ps1 -NoJinja` and **do not add `-NoSingleTurn`** (wrapper then emits native `--single-turn`).

**Question B — Vulkan difference in GPU memory between CLI and bench?** Prefer the already successful lower-risk **64k context, IQ4, QSA UNION OFF and ON in separate runs**, comparing with successful bench 64k/60k no-warmup results (`94424 MiB` QSA OFF, `94578 MiB` QSA ON) and matching CLI source/prompt, context and batch. Alternatively first run IQ3 64k as a conservative parity preflight. **Avoid full 128k Vulkan IQ4** while near reported GPU-memory pressure and previous TDR. Compare ADLX **time series** (model-load baseline, first PP allocation, PP steady state, peak), Vulkan reported allocations/budget, QSA activation stderr, clock state, and warmup/generation effects. Do not equate ADLX total with free physical UMA. If CLI and bench use different token counts, warmup regimes, chat-template/BOS paths, `-n`, memory fit, prompt caches or KV behavior, label the comparison approximate until those are controlled.

These are **prospective plans, not completed new experiments**. Gate 2 detailed script/input preparation should be frozen **after** receiving Gate 1 results. No source/driver/BIOS/UMA/TDR changes in this plan.

## Vulkan IQ3 missing 128k matrix cases 10/11 complete — 2026-11-03

**PASS 2/2** using standalone scoped runner; source ZIP `evox2-r6-pp128k-vulkan-iq3-only-20261103.zip` from user. It contains `matrix-plan.json`, `matrix-records.csv`, `matrix-complete.txt` ("2/2 PASS"), and both runs' `conditions.json`, `result.json`, native `llama-bench.json`, `stderr.log`, ADLX `gpu-metrics.csv`, `output.log`, `summary.csv`. Raw ZIP not checked into repository.

Same **Vulkan b12032** source `c4ddd239b`, executable SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, original Unsloth IQ3_XXS Ple16 `81961816672` bytes; `-c 131072 -p 126253 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/ctv f16`, warmup ON. `GGML_VK_QSA_UNION=1`, `MIN_KV=32768`, `QWEN4EXP_QSA_GATHER=0`. Both stderr files independently show `ggml_vulkan: qsa-union active (r6)`. P-MODE Performance at start/end, no mode switch, both ADLX exit0, no device lost.

| Case | Input | Native avg_ns | Native PP tok/s | Wrapper wall-time | ADLX 2-sec samples | Max ADLX GPU memory | High GPU use >=95% | High-load mean VRAM clock | Max temperature |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 Vulkan IQ3 Random | Native random, no source file | 450934476900 | **279.980810** | **987.175 s** | **491** | **85599 MiB** | **466** | **795.44 MHz** | **84 C** |
| 11 Vulkan IQ3 Code | `llamacpp-inference-code.txt` first126253 tokens, SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` | 364489724100 | **346.382879** | **772.504 s** | **386** | **85599 MiB** | **360** | **881.94 MHz** | **86 C** |

Native JSON `Status=OK`, exit0 and one valid row per run; 1 repetition so native stddev 0 does NOT indicate statistical confidence. Native code input stderr reports 1,865,856 available tokens, using126253 head. Random is native generated random-token path, not raw text with a SHA; the exact token-sequence identity across backends is not established.

- Case10 RunID `20261103-195939-547-bench-vulkan-b12032-ctx131072-b839a234580a`; started 19:59:40.843 JST, finished 20:16:08.018 JST. ADLX high-load mean GPU clock **2884.15 MHz**, GPU power **97.157 W**; P-MODE hardware probe Performance both ends, but ADLX `PowerClass=Ambiguous` and `Consistent=null` because power is 97.157W (between configured thresholds). Do NOT mislabel it a proven P-MODE switch. In high-load samples VRAM clock **<=750MHz in 288/466**, and <=900MHz in332/466. High-load mean GPU memory context includes a last sample that drops to 12000 MiB after deallocation. `BackgroundActivitySummary.Status=PartialCoverage`, `PossibleNoise=null`: cannot conclude all other work absent.
- Case11 RunID `20261103-201622-079-bench-vulkan-b12032-ctx131072-ffbdddeb3cc1`; started 20:16:22.923 JST, finished 20:29:15.427 JST. ADLX high-load mean GPU clock **2864.50 MHz**, GPU power **111.217 W**, `PowerClass=Performance-like` consistent with P-MODE Performance; VRAM clock **<=850MHz in 199/360**, <=900MHz in236/360. Background summary PartialCoverage; PossibleNoise=null. No true P-MODE change. Both runs remote session RDP-Tcp#0.
- GPU memory peaked at **85599MiB (~83.59GiB)** for both; compare **failed 128k Vulkan IQ4** peak **97130MiB (~94.85GiB)**: IQ3 ~**11531MiB lower**, but across different model/inputs, activity and pre/post TDR runs; not proof of out-of-memory. IQ3 GGUF 81,961,816,672 bytes vs IQ4 GGUF 93,682,576,992 bytes (~11.72 billion bytes file size difference). Both model and other allocations matter.
- Importantly high GPU utilization coexists with repeated/deep **VRAM-clock reduction** in *both* IQ3 QSA ON runs. Earlier IQ4/64k/60k QSA ON had one late transition to 800MHz range while QSA OFF paired run was steady ~1000MHz. This new observation rules out **IQ4-only** clock behavior, but does NOT establish QSA UNION as its root cause. Possible thermal/power management, RDP/system and workload interactions remain. Clock regime is a potential confounder of PP rankings, especially Random; avoid attributing the full Vulkan input spread to QSA.
- Cross-backend IQ3 128k 3-input table from original matrix case07 and ROCm:
  - Japanese: Vulkan **306.831891**, ROCm **299.151698**, Vulkan +**2.567%**.
  - Random: Vulkan **279.980810**, ROCm **313.880965**, Vulkan **-10.800%**.
  - C/C++ code: Vulkan **346.382879**, ROCm **299.941061**, Vulkan **+15.484%**.
  - Direction: Vulkan code > Japanese > random, ROCm random > code ~= Japanese. One run per input; random-token identity not established across backends, different backend kernels and clock behavior confound causal claims.
- **Updated original 12-case matrix status, across separate original and IQ3-only archives: 9/12 OK, 1/12 failed (Case08 Vulkan IQ4 Japanese GPU TDR), 2/12 not attempted (Case09 Vulkan IQ4 Random, Case12 Vulkan IQ4 Code)**. Do not mark Case08 pass, do not run remaining IQ4 cases or relaunch original `-Stage Remaining` (it retries failed 08). Matched IQ3 6-case cross-backend matrix is complete.

### Follow-on paired CLI vs bench testing: freeze only after input normalization

User's next two scientific questions:
1. ROCm: why historical **CLI** IQ4 sometimes faster than IQ3 while new 128k **bench** IQ3 faster than IQ4? Same backend **b12038**, use one fixed Japanese real source and token length per model, compare a 2x2 table (IQ3/IQ4 x CLI/bench), MTP OFF, QWEN4EXP_QSA_GATHER=0, identical f16 KV, FA auto, context, GPU offload and batch/ubatch. Start at safer 64k context with bounded input and then decide on 128k if relevant; a 64k result does not settle the historical 128k reversal. The earlier CLI incidental quality-task numbers **286.04 IQ3 vs 313.94 IQ4** on b12013 had a different prompt and build and cannot be directly equated with new bench Japanese **299.15 IQ3 vs 290.90 IQ4** b12038.
2. Vulkan: isolate GPU memory between **CLI and bench** with same model/context/input, starting with original IQ4 **32k QSA OFF** after TDR, then 64k if stable. Prefer compare ADLX time series from model-load/buffer allocation/steady PP (not just one max), check Vulkan-reported memory budget, QSA activation logs, driver events. Avoid IQ4 128k until risk reviewed.
3. Crucial **same raw file is not proof of same token IDs**: r6 Vulkan b12032 earlier CLI/bench using the same `nlp-survey-ch3-d7-b1.txt` differed CLI **61789** vs bench **61777** tokens even with -NoJinja. Compare prompt-token logs and optionally tokenizer-generated token ID traces; do not assert bit-identical sequence without direct proof. Bench `--prompt-slice head` truncates to `-p`, whereas CLI reads full file. Use bounded pre-sliced raw file if needed and verify each model separately.
4. CLI wrapper `Measure-LlamaCli.ps1` does **not** accept `-GenerationTokens 0`; use `-GenerationTokens 1`, `-Fit off`, `-PromptCacheMiB 0`, `-NoJinja`, and **do not specify `-NoSingleTurn`** to avoid earlier apparent interactive hang. Compare CLI *prompt eval* only with bench *PP*, not total runtime nor TG, noting extra CLI generation/cache or BOS/chat framing may change memory/timing. Keep QSA settings fixed per pair, P-MODE and backend executable SHA.
5. Before a large comparison, run a single matched 32k or 64k input proof-of-identity gate to confirm CLI prompt counts and bench prompt counts. Keep the experimental comparison scoped and avoid uncontrolled four-run sweep if model input lengths/counters mismatch.

No C++/driver/BIOS/UMA/TDR modifications are required by these finished tests. User will decide when to run the next compare.

## Historical r5 → r6 IQ3 128k same-workload comparison — 2026-11-03

User requested comparison against Qiita [EVO-X2 x Qwen3.8-Flash-Next 番外編4, 128k Vulkan OFF/ON/ROCm](https://qiita.com/ariera/items/2f9353899c2265dea7cd#128kvulkan-off--on--rocm%E6%AF%94%E8%BC%83). **Naming correction: that article explicitly describes experiments off `r5/upstream-refresh-20261009`, not r4.** Values from its 128k table are r5 Vulkan b11535 UNION ON and ROCm b11543, original IQ3_XXS Ple16. New r6 b12032 Vulkan UNION ON and b12038 ROCm IQ3 numbers are the original matrix Case07, ROCm cases02/03/06, and separate IQ3-only Cases10/11. All PP126253/context131072, warmup ON, batch2048/ubatch1024, f16 KV, no MTP, one timed repetition. R5 and r6 use different binaries and backends, so this is a cross-build trend, not same-binary A/B.

| Input | r5 Vulkan ON | r6 Vulkan ON | r6/r5 | r5 ROCm | r6 ROCm | r6/r5 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Japanese repeated ANLP | 310.682 | 306.831891 | **-1.239%** | 296.27 (Qiita rounded; underlying ~296.27) | 299.151698 | **+0.973%** |
| C/C++ llama.cpp code | 346.600 | 346.382879 | **-0.063%** | 296.08 | 299.941061 | **+1.304%** |
| Native random token | 261.673 | 279.980810 | **+6.998%** | 308.22 | 313.880965 | **+1.837%** |

Rounded percentage arithmetic uses Qiita's displayed ROCm 2-decimal figures. For exact r5 source values refer to [r5 ROCm/Vulkan report](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md). Same Japanese source `nlp-survey-ch3-d31-b1.txt` SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` and same code source `llamacpp-inference-code.txt` SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` (head126253 tokens), consistent with historical r5 manifest. Native random-generation token IDs are not externally pinned/verified identical across r5 and r6, so treat +6.998% Vulkan Random as an observed speed delta for the random-generation condition, **not a guaranteed exact-token matched A/B**.

Rankings are conserved:
- Vulkan ON: **Code > Japanese ANLP > Random** in both r5/r6.
- ROCm: **Random > Japanese/Code ~equal** (r5 Japanese slightly above Code, r6 Code slightly above Japanese).
- Vulkan vs ROCm within Japanese: r5 +4.864%, r6 +2.567%; Code: r5 +17.063%, r6 +15.484%; Random: r5 **-15.103%**, r6 **-10.800%**. Ranking still input-dependent, but Random's Vulkan gap shrank.

**Interpretation limitations:** r6 Vulkan IQ3 Random PP was heavily confounded by ADLX memory-clock drops (high-load mean ~795.44MHz), while r6 Code averaged ~881.94MHz. r5 article does **not** publish matching ADLX clock regime, so do not claim Random's +7% as a pure algorithm or upstream speedup, and don't assign QSA causality from this comparison. R6 ROCm changes +1–2% are single-run/cross-build observations, not statistically significant improvements. The r5/Qiita OFF column (183.66 ANLP, 236.13 Code, 170.62 Random) has **no r6 same-condition 128k OFF counterpart** here and must not be mixed with r6 Vulkan ON.

**Conclusion:** same essential input-dependence signature reproduced and no major IQ3 128k Vulkan PP regression found in these three inputs. Continue the planned matched CLI/bench ROCm quantization and Vulkan memory study, but capture runtime GPU/VRAM clocks and verify prompt-token equivalence first.

## 2026-11-03 ROCm b12038 64k CLI-vs-bench IQ3/IQ4 paired 4-run result

**All 4/4 PASS; both CLI and bench place IQ3 ahead of original IQ4 on the same 64k real-document task.** Source user archive `20261103-211207-672-cli-rocm-b12038-ctx65536-5bbf39318cc6.zip`, containing four run directories and complete `conditions.json`, `result.json`, `summary.csv`, `gpu-metrics.csv`, stderr/output, with `llama-bench.json` for the two bench runs. Raw ZIP is not committed.

Fixed backend/conditions: ROCm b12038 `d321e7ff3` (source `d321e7ff38052be311fde9392598fe02c7548956`); original Unsloth PLE16 IQ3 `81961816672` bytes vs original IQ4 `93682576992` bytes; `nlp-survey-ch3-d7-b1.txt` 304931 bytes, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; `-c 65536 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/ctv f16`; `QWEN4EXP_QSA_GATHER=0`, `GGML_VK_QSA_UNION=0` (Vulkan-only flag); MTP disabled. HIP_PATH/ROCM_PATH both `C:\TheRock\build\.venv`; HIP_PATH_72 still points to AMD ROCm7.2 SDK path as an auxiliary env var, but runtime has been previously verified/staged as TheRock. P-MODE Performance at start/finish on all four; all exit0 and wrapper Status OK, ADLX monitors exit0. GPU trace samples via RDP, GPU hotspot not exposed.

| Order | Run ID | Model | Tool | Prompt tokens | Prompt eval time | PP tok/s | ADLX max GPU memory MiB | ADLX high-load samples (GPU>=95%) | High-load mean VRAM MHz | High-load mean GPU MHz | High-load mean W | Max GPU temp C |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | `20261103-205857-078-cli-rocm-b12038-ctx65536-0ee10f33bf8e` | IQ3 | CLI | 61789 | 154114.48 ms | **400.93** | **53715** | 76/104 | **971.789** | 2875.46 | 119.921 | 80 |
| 2 | `20261103-210259-423-bench-rocm-b12038-ctx65536-953303403af0` | IQ3 | bench | 61777 | 154537.7814 ms | **399.753377** | **54361** | 75/102 | **976.027** | 2872.81 | 119.907 | 83 |
| 3 | `20261103-210814-443-bench-rocm-b12038-ctx65536-4aa94ce4c524` | IQ4 | bench | 61777 | 161263.1806 ms | **383.081865** | **65278** | 79/101 | **998.823** | 2885.80 | 120.152 | 83 |
| 4 | `20261103-211207-672-cli-rocm-b12038-ctx65536-5bbf39318cc6` | IQ4 | CLI | 61789 | 160875.52 ms | **384.08** | **64662** | 79/101 | **998.722** | 2880.05 | 120.278 | 83 |

CLI binary SHA256 `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347`; bench binary SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`, both verified earlier with the same source commit, correct ROCm backend. CLI command uses `--single-turn` without `--jinja`, `-n 1`, `-fit off`, `--cache-ram 0`, `--reasoning off`, `--spec-type none` and exits normally. bench uses `--no-warmup`, `-n 0 -d 0 -r 1 -f <same source> --prompt-slice head`. No multi-sample variance estimate. Named-process interference observed as low (~0.018–0.025% of system CPU; PossibleNoise=false), not an exhaustive system activity audit.

**Comparison:**
- IQ4-vs-IQ3 CLI: `384.08/400.93 - 1 = -4.20%`; bench: `383.081865/399.753377 -1 = -4.17%`. **Both rank IQ3 faster by ~4.2%** on this 64k workload.
- bench-vs-CLI: IQ3 `399.753377/400.93 -1 = -0.29%`; IQ4 `383.081865/384.08 -1 = -0.26%`. Near-equal average PP despite slightly different actual prompt tokens.
- Actual CLI prompt `61789` vs bench `61777` for both IQ3 and IQ4 (**12-token difference**). Same raw file SHA does **not** establish identical token IDs/prompt construction; compare as *approximately matched original-document prefill*, not bit-identical input.
- ADLX max GPU memory bench-CLI **+646MiB** IQ3 (54361 vs53715), **+616MiB** IQ4 (65278 vs64662). Distinct tools manage additional contexts/generation and workspaces differently; not evidence of a leak or inefficiency. Because generation differs, memory parity is not strict even when prompt length is close. Adlx GPU-memory use is not direct physical UMA free margin.
- All four GPU high-load core clocks clustered ~2873–2886MHz; GPU mean power ~120W. IQ3 showed mild high-load VRAM clock reduction (~972/976MHz), IQ4 near1000MHz. No observed sustained deep clock reduction comparable to earlier Vulkan 128k IQ3 random case; no TDR/reset/driver error. This supports the within-tool IQ3 advantage as an observed workload-specific performance difference, not a universal model ranking.

**Interpretation:** Earlier b12013 ROCm quality-task `llama-cli` incidental 128k PP mean IQ3 ~286.04 vs IQ4 ~313.94 tok/s used a **different input** and software build. New b12038 128k **bench** Japanese/Random/Code showed IQ3 > IQ4 by 1.7–2.8%, now corroborated by both tools at 64k on a different (shorter) ANLP file. A tool-specific speed reversal is **not supported** by the present 64k comparison. Input length/content, backend version, quality-task prompt framing, and runtime behavior remain plausible explanations for the historical b12013 observation. Do not generalize 64k result to 128k.

**Next decision:** If investigating historical 128k IQ4-fast anomaly, prefer a carefully controlled **128k CLI IQ3/IQ4 paired run** on the exact source used for 128k bench and ensure the CLI processes a bounded ~126253-token *actual* prompt. **Do not simply give CLI the full d31 raw text** because bench only processed the first 126253 out of ~255169 available tokens and the CLI will otherwise not be evaluating the same sequence (and may exceed ctx). Validate CLI request token count, model-specific tokenization, template/BOS, no synthetic padding, actual warmup (bench 128k had warmup ON vs CLI single request), clocks and P-MODE; if strict source-truncation cannot be guaranteed, label that comparison approximate or generate a new short controlled 128k input and redo both tools. A 128k CLI speed comparison to existing bench may only be accepted as strong evidence with matched input. Keep separate Vulkan IQ4 128k TDR case on hold; ROCm context memory and successful 128k tests do not remove memory/driver risks.

## Next planned ROCm 128k CLI head-slice IQ3/IQ4 check — 2026-11-03

User chose **two ROCm 128k CLI runs (IQ3, IQ4)** next, comparing to the already completed b12038 `llama-bench` Japanese ANLP `-c 131072 -p 126253` with original source `nlp-survey-ch3-d31-b1.txt`. Previous bench: IQ3 **299.151698 tok/s**, original IQ4 **290.899345 tok/s**. After result: if IQ3 remains faster, repeat on **MH-128K** as a new fixed-source input experiment; only if that too fails to reproduce the earlier IQ4-fast CLI phenomenon, consider explicitly testing **COMMON-005 `QWEN4EXP_QSA_GATHER=1` vs 0**, preferably same build, same model, same input/clock for each paired comparison. The 2026-11-03 COMMON-005 TG efficacy is not evidence of a similarly sized PP effect; mark it a secondary hypothesis.

**Input preparation is essential:** original d31 source SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` contains **255169 raw tokens**, while prior bench used first **126253** (`--prompt-slice head`). Directly passing the whole `-InputKey '256k'` to CLI is not a matched comparison. A standalone user-side script `Evox2-R6-ROCm128k-Cli-IQ3-IQ4-20261103.ps1` (separately supplied ZIP, *not committed*) has `Prepare`, `Run`, and `All` stages: tokenizer `vocab_only` on source, UTF-8 prefix search targeting 126253 tokens in IQ3, verify IQ4 token count (<=2 discrepancy), save prefix SHA and metadata; then serially run IQ3 and IQ4 CLI via existing `Measure-LlamaCli.ps1`, collecting run folders into a shareable ZIP in `%TEMP%`. It checks expected b12038 CLI SHA256 `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347` and bench SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`, model byte counts and source hash. If `llama-tokenize.exe` is absent, only build that one target in the existing ROCm CMake tree, then recheck CLI/bench hashes. Input remains private/local; output ZIP has metadata+logs, not the cut text itself.

CLI settings: same ROCm b12038, `-c 131072 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -n 1 -fit off --cache-ram 0 --reasoning off --spec-type none --single-turn`, **no Jinja**, temperature0, TheRock venv `HIP_PATH` and `ROCM_PATH`, `QWEN4EXP_QSA_GATHER=0`, all MTP speed flags explicit0. Normal CLI/bench startup warmup may not be identical; compare **CLI prompt eval** to bench PP only. Historical 64k same-file comparison showed CLI ~12 more prompt tokens than bench; the cut prefix approximates shared head text but **does not guarantee identical token IDs or text-boundary segmentation**. Validate actual CLI tokens and native stderr; refuse claims of strict bitwise parity. No Vulkan IQ4 128k rerun is authorized. Stop on GPU fault or nonzero exit.

MH-128K next stage must **not** reuse prior d31-source bench results as if they were MH-input benchmarks: use the same frozen MH seed/order and prompt SHA within each model/tool; choose whether to use the 111148-token original test prompt or another fixed variant. To separate context from input, record exact target `-c`, prompt tokens, formatting and generation limits. For Gather A/B, preserve exact input SHA, models and executable, compare ON/OFF with ADLX clocks and where useful repeat order; avoid interpreting MTP TG improvements as PP effects before measuring.

### 128k CLI prefix-preparation script build-output bug (2026-11-03)

User reported `-Stage Prepare` failure after on-demand compilation of `llama-tokenize.exe`. The compile actually succeeded; stdout lines `[1/2] Building ...` and `[2/2] Linking ...` were emitted on the **PowerShell function's success output stream** along with the desired final path by `Get-TokenizerExe`. In PowerShell, assigning `$tokenizer = Get-TokenizerExe` captured *all* those lines as an array, and later `Start-Process -FilePath $Exe` failed with "specified file not found". Logged display was diagnostic: `Model tokenizer: [1/2] ... [2/2] Linking ... C:\...\llama-tokenize.exe`. **This was a standalone script control-flow bug, not a ROCm/Vulkan error or tokenizer-build failure; no GPU PP run had begun.**

Correction in downloadable replacement `Evox2-R6-ROCm128k-Cli-IQ3-IQ4-20261103-fixed.zip` (not tracked in this repo): change native build invocation in `Get-TokenizerExe` to `& cmake --build ... --target llama-tokenize --parallel 4 | Out-Host`, so progress appears without entering function return values. If executable is already built at `build-rocm-bench-real-r6\bin\Release\llama-tokenize.exe`, re-running the *original* `& $s -Stage Prepare` is also expected to pass the problematic build branch and return only the path. A completed prefix metadata/token count gate remains necessary before `-Stage Run`; success has **not** yet been measured. Leave original CLI/bench binaries and the 128k QSA Gather OFF comparison plan unchanged.

## ROCm 128k CLI paired IQ3/IQ4 ANLP actual result — 2026-11-03 night

**Two real user CLI runs PASS 2/2; IQ3 faster.** Source user ZIP: `evox2-r6-rocm128k-cli-iq3-iq4-20261103(1).zip`; includes `prefix-metadata.json`, `paired-runs-summary.json`, two complete folders with `conditions.json`, `result.json`, `summary.csv`, `stderr.log`, `stdout.log`, `output.log`, ADLX `gpu-metrics.csv` and ADLX monitor logs. Raw ZIP/large source text not committed.

**Input/provenance** (verified directly from ZIP):
- Original ANLP `nlp-survey-ch3-d31-b1.txt` 1,261,235 bytes SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, original tokenizer count **255169**.
- Cut **UTF-8 text prefix**, 233840 chars, 623907 bytes; SHA256 `b7c429ad4a0fc71f92d4c95501960aecc532eb9c4627a40df725cdd517b9d0aa`. Both IQ3 and IQ4 independent tokenizer checks report **126253** pre-CLI tokens. Native CLI under `--single-turn` without Jinja processed **126265** prompt tokens for both (same +12 as at 64k); **not claimed bit-identical token IDs or native bench tokenizer boundary**.
- tokenizer EXE SHA256 `2dfbb41d785045aeeda202bbe281a53aa2a3944a2daccc92d2054a99edf312c1`; CLI EXE `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347`; bench EXE `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`; source/build `d321e7ff3`, ROCm b12038, unified TheRock staging `RuntimeArtifactStatus=Verified`.
- CLI args `-c 131072 -ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa auto -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --single-turn --spec-type none -n 1 -f <same prefix>`; environment `QWEN4EXP_QSA_GATHER=0`, MTP-related DENSE/NOOP/Stage-B/flatten all explicit0, `GGML_VK_QSA_UNION=0`, `HIP_PATH/ROCM_PATH=C:\TheRock\build\.venv`. CLI logs show default model warmup, `n_ctx=131072`, `n_batch=2048`, valid ROCm device, no graph reallocs. No Jinja, no Draft. Single time observation each.

| Model | CLI Run ID | Actual prompt tokens | Prompt eval ms | CLI PP tok/s | Existing 128k bench PP tok/s | CLI/bench | GPU-mem peak ADLX MiB | high-load VRAM mean MHz | high-load GPU core mean MHz | high-load GPU power mean W | max temp C |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| IQ3 original Unsloth PLE16 | `20261103-215228-110-cli-rocm-b12038-ctx131072-1f2f55b20568` | 126265 | **420009.12** | **300.62** | **299.151698** | **+0.491%** | **55815** | **973.83** | **2883.81** | **119.18** | **84** |
| IQ4 original Unsloth PLE16 | `20261103-220038-172-cli-rocm-b12038-ctx131072-1792142767d2` | 126265 | **433699.38** | **291.13** | **290.899345** | **+0.079%** | **66794** | **998.60** | **2890.07** | **119.40** | **85** |

Bench (already archived original 12-case matrix) uses `-p 126253 -c 131072 -n 0 -r 1`, warmup ON, source head; same ANLP file, backend/binary family, f16 KV, batch2048/ubatch1024 and Gather OFF; CLI requests 1 generated token, not bench0, and adds 12 prompt tokens. In CLI, IQ4 vs IQ3 speed **291.13 / 300.62 - 1 = -3.1568%**; existing bench **290.899345 / 299.151698 - 1 = -2.7586%**. Both unequivocally rank IQ3 faster for this ANLP 128k workload within the limitations of one sample and approximate text parity. At 64k CLI IQ3 400.93, IQ4 384.08; bench IQ3 399.753377, IQ4 383.081865, also rank IQ3 faster. Cross-tool PP rate matches to <0.5% at 128k; this is **strong directional parity evidence**, not proof all request paths or token IDs are identical.

Health/telemetry: Both statuses `OK`, `ExitCode=0`, `RunException=null`, `RuntimeArtifactStatus=Verified`, effective n_ctx131072, no context truncation indicated, `AdlxMonitorExitCode=0`, high GPU-use >=95% samples IQ3 **208/236** and IQ4 **215/238**, temperatures max84/85 C, high-load GPU memory nearly steady. VRAM minimum under high-load was IQ3 **954MHz**, IQ4 **992MHz**, no <900MHz high-load samples. Endpoints P-MODE Performance, no PModeChanged; named background process CPU coverage complete, `PossibleNoise=false` (~0.008%/0.01% CPU share) though unobserved activity possible. Active RDP session in ADLX. ROCm0 memory print at shutdown: IQ3 `total110456 = free53888 + (self54797 = model50191 + context3952 + compute653) + unaccounted1770` MiB; IQ4 `total110456 = free42642 + (self65828 = model61222 + context3952 + compute653) + unaccounted1985` MiB. These are driver-reported accounting snapshots and do not directly equal free physical UMA headroom.

**Conclusion:** 128k ANLP IQ3-fast repeats in CLI and bench; the historical b12013 quality-task IQ4-fast result is not reproduced, so *tool identity alone* is a poor explanation. Different MH-128K input composition and prompt formatting, older build/runtime, and COMMON-005 ON/OFF remain separate testable candidates. Next user-requested **MH-128K**: reuse the **previously frozen prompt**, e.g. order A SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`, order B `694edd15bb2f762a530b437800f67d3dc84eb085be17429e828e060a4fd69ef4`, each historical ~111148 tokens, but verify actual source and identity for the *same* selected order and model and whether MTP/Jinja/template enabled. Start with 2 CLI runs IQ3/IQ4 under same b12038, QSA Gather OFF; do not assume historical speed reversal was measured on exactly this prompt. If needed compare against fresh MH bench rather than reusing ANLP bench, because input genre and count differ. Only if MH also does not reproduce IQ4-fast, consider independent **COMMON-005 Gather=1** A/B under otherwise unchanged 128k MH conditions; this optimization's documented TG benefit does not establish PP gain, so look for measured PP rather than extrapolate.

## Next ROCm MH-128K seed20261026 A paired CLI PP check (planned)

User selected a **two-run ROCm b12038 CLI MH-128K IQ3/IQ4 comparison** after successful 64k and 128k Japanese-ANLP checks. This is a new **input-controlled comparison**, not a rerun of 128k ANLP bench. Use the **same frozen MH-128K seed 20261026 question order A** for both, not seed 20261025 or B or a regenerated corpus:
- Local-config input key `MH128K_S20261026_A`, historically `mh128k_s20261026_A.prompt.txt` in user's private MH data dir; expected SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3` (check before loading GPU).
- Historical **b12013 ROCm / Gather OFF** exact **A-order** speed (quality-run incidental PP) was IQ3 **286.45** vs original IQ4 **313.38 tok/s**; **not** the mean of other seeds/orders. Historical input processed **111148 tokens** with `--jinja`, `-ub512`, `-fit on`, `-n512`, `-b2048`, `-t4 -tb4`, f16 KV, FA auto, `--single-turn --reasoning off --temp0 --top-p0.8 --top-k20 --min-p0.05 --seed1234 --ctx-checkpoints 0t`, MTP OFF. That is **materially different** from the recent ANLP performance checks (`-NoJinja -ub1024 -fit off -n1`). Match the previous MH run flags before interpreting any inversion; measure PP-only from CLI result, not generation/wall clock.
- New binaries: ROCm b12038 `llama-cli.exe` SHA256 `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347`; model keys `UnslothPle16` (IQ3 original PLE16) and `Qwen38Iq4XsPle16` (original Unsloth IQ4, **not Huihui**); `-LlamaCli` explicit resolved `build-rocm-bench-real-r6\bin\Release\llama-cli.exe`; `-ExpectedBackend ROCm`.
- Set `QWEN4EXP_QSA_GATHER=0`, all MTP flags 0, `GGML_VK_QSA_UNION=0` (irrelevant to ROCm), TheRock10 venv `HIP_PATH`/`ROCM_PATH` fixed. Run IQ3 A, inspect ExitCode/Status, then IQ4 A, never parallel. Capture RunDirectory with `Measure-LlamaCli.ps1`, per-run zip/log/ADLX/P-MODE; no GGUF or full input in Git.
- Gate outcomes: independently check input SHA, CLI prompt tokens (historically 111148, but verify b12038), model identity, actual `--jinja` and `--single-turn`, GPU offload and clocks. If IQ4 faster again, the difference is *input or settings/backend build dependent* and isolate tokenizer/Jinja/ubatch/fit in later A/B; it is not proof MH content alone caused the reversal. If IQ3 faster again, the historical b12013 vs b12038 build/runtime difference or run environment remains; only then consider COMMON-005 ON/OFF as a **separate variable** on this same MH source. The documented COMMON-005 PP effect was near-zero and its primary gains TG, so it is a low-priority PP-reversal hypothesis.

## ROCm b12038 MH-128K seed20261026 A CLI result and native bench next gate

**User-measured 2/2 PASS on 2026-11-03:** source user ZIP `evox2-r6-rocm-mh128k-iq3-iq4-20261103.zip`, two complete `llama-cli` run directories (raw ZIP not in Git). This experiment **reproduced** the historical ~9% IQ4 PP advantage on MH-128K with **current ROCm b12038**, while the same binary's ANLP-64k/128k controls favored IQ3. It weakens the hypothesis that the IQ4 advantage requires the old b12013 binary or COMMON-005 enabled. It does **not** yet separate MH content from Jinja/UBatch/Fit setting differences.

Fixed conditions explicitly independently checked: b12038 `d321e7ff3`, CLI SHA256 `d710c9baf82a33c3294e6f82f618416d41da9d9b39a89050de14d48318323347`, RuntimeArtifactStatus Verified, TheRock10 runtime digest `fc2d7264ae8d38d5d1593de5676ad5888c251dd04d041eb538f37fce776eddf2`; input **MH-128K seed20261026 A** `mh128k_s20261026_A.prompt.txt` size **172120 bytes** SHA256 **`3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`** in both, actual CLI **111148 tokens** each. Original Unsloth `UnslothPle16` (IQ3 GGUF 81961816672 bytes), `Qwen38Iq4XsPle16` (IQ4 GGUF 93682576992 bytes; **not Huihui**). `-c 131072 -b 2048 -ub 512 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk/-ctv f16 -fit on --cache-ram 0 --reasoning off --jinja --single-turn --spec-type none -n 512 -tb 4 --ctx-checkpoints 0t --seed 1234 --top-k 20 --min-p 0.05 --temp 0 --top-p 0.8`. `QWEN4EXP_QSA_GATHER=0`, all MTP speed flags=0; P-MODE Performance both endpoints, ADLX monitor exit0, no named CPU noise, no GPU faults/truncation. First IQ3 then IQ4.

| Model | Run ID | CLI PP | PP time | Generated | TG | ADLX GPU memory max | high-use samples >=95% | high-use VRAM mean/min | high-use GPU clock mean | high-use GPU power mean | temp max |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| IQ3 | `20261103-222918-486-cli-rocm-b12038-ctx131072-6b745c3aef9c` | **287.26 tok/s** | **386928.38 ms** | **250** | **18.63 tok/s** | **55504 MiB** | **196/226** | **932.21 / 829 MHz**, 14 high-use samples <900MHz | **2894.06 MHz** | **117.11 W** | **82 C** |
| IQ4 | `20261103-223707-710-cli-rocm-b12038-ctx131072-dc5b21f3e904` | **313.89 tok/s** | **354103.37 ms** | **249** | **17.63 tok/s** | **66447 MiB** | **182/205** | **964.93 / 933 MHz**, 0 high-use samples <900MHz | **2889.82 MHz** | **119.18 W** | **85 C** |

Within-run IQ4/IQ3 **+9.270%** PP speed and **−32.825s** prompt time. Historical same **MH seed20261026 A, b12013 Gather OFF** IQ3 **286.45**, IQ4 **313.38 tok/s**. Near-perfect reproduction with b12038 (IQ3 +0.283%, IQ4 +0.163% versus b12013). At r6 b12038, comparison on **ANLP file** showed **IQ3 faster** at 64k CLI 400.93/384.08 and 128k CLI 300.62/291.13 (IQ3/IQ4); the changed genre, actual prompt length, Jinja, UBatch (ANLP 1024 vs MH 512), Fit, generation, and clock mean are *confounded*. MH IQ3 has some VRAM-clock dips (below900MHz 14 of196 high-use samples), while IQ4 did not; do not prematurely attribute the entire +9.27% advantage to kernel-only effects.

### User-requested follow-up: same MH input through llama-bench (planned, no new bench result yet)

A standalone PowerShell ZIP `Evox2-R6-ROCm-MH128K-Bench-IQ3-IQ4-20261103.zip` was supplied outside the repository, with stages `-Stage Plan` and `-Stage Run`. `Plan`: checks existing b12038 bench SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`, CLI SHA, input SHA, actual model GGUF paths/sizes; invokes available same-tree `llama-tokenize.exe` vocabulary-only to determine independent **full raw text tokens per model** (`--no-escape --show-count` output redirected to local temp and only final count parsed), without GPU inference; writes JSON plan metadata in %TEMP%. `Run` repeats preflight and executes **two** independent `Measure-LlamaBench.ps1` PP-only tests (IQ3 then IQ4), same input SHA, `-c 131072 -b2048 -ub512 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16 -n0 -d0 -r1`, `--prompt-slice head --progress`, **warmup ON**, Gather OFF and MTP OFF. Results ZIP includes run directories + planned input/model/token metadata; no tokenizer token dump or GGUF file is included.

**Important methodological limitation:** `llama-bench` uses `common_tokenize(vocab, prompt_file_text, true, false)`, direct raw file input; CLI MH was `--jinja` with conversation framing. The raw tokenizer count may be fewer than the CLI's 111148 prompt tokens and native bench may add BOS: the script sets `-p` to the independently counted raw token length to avoid exceeding the available length (potentially omits 1 trailing token if an extra BOS was added). Check bench native stderr `available tokens, using N` before asserting complete equality. A positive IQ4-fast result in bench would demonstrate robustness across tools on the same source; a negative result would motivate CLI no-Jinja input with matched ubatch/Fit and direct tokenizer-ID inspection before claiming that Jinja alone explains it.

Do not turn on COMMON-005 yet. Its previous MH seed20261026 A OFF IQ4 superiority and current b12038 OFF reproduction already show Gather is not needed for the crossover. Later Gather ON/OFF can be pursued as a distinct question if desired, but not as a prerequisite for this same-source bench test. Do not rerun Vulkan IQ4 128k after the earlier driver TDR.

### 2026-11-03 MH-bench Plan-only Windows PowerShell NativeCommandError fix

User ran the standalone `Evox2-R6-ROCm-MH128K-Bench-IQ3-IQ4-20261103.ps1 -Stage Plan` on Windows PowerShell (TheRock venv). `llama-tokenize.exe` printed `llama_context: n_ctx_seq (512) > n_ctx_train (0) -- possible training context overflow` on **native stderr** while loading the GGUF vocabulary only. Because script sets `$ErrorActionPreference = 'Stop'`, the native `& $Exe ... 1> $stdoutFile 2> $stderrFile` command at line68 was surfaced as `NativeCommandError` and aborted before checking `$LASTEXITCODE` or parsing the final token count. The `n_ctx_train=0` diagnostic under vocab-only mode is not independent proof that tokenization failed or a GPU/ROCm runtime error. No inference measurement was started.

**Fix supplied** in standalone ZIP `Evox2-R6-ROCm-MH128K-Bench-IQ3-IQ4-20261103-fixed.zip` (not committed into the repo): set a **function-local** `$ErrorActionPreference = 'Continue'` before invoking `llama-tokenize.exe`; retain both redirected stdout/stderr files; then explicitly check `$LASTEXITCODE -eq 0` and parse exactly one `Total number of tokens: N` in stdout tail. Nonzero exit or bad/missing count still fails the preflight. Continue strict Stop handling for rest of script. Replace ZIP contents in existing tool directory, repeat `-Stage Plan`, proceed `-Stage Run` **only after** Preflight PASS. Expected original MH input SHA, model identity, ROCm b12038 CLI/bench, QSA Gather OFF and PP settings unchanged. On-the-fly tokenizer compilation is **not** required; binary is already present.

Do not record the initial Plan error as GPU or model correctness failure. The benchmark result remains PENDING until user supplies real runs.

### 2026-11-03 MH-bench IQ3 result PASS; wrapper result.PP mismatch and IQ4-only resume

User reported first **ROCm b12038 MH-128K seed20261026 A `llama-bench` IQ3** run **PASS**, then a crash in the separately supplied PowerShell orchestration script *after* the benchmark returned. Native wrapper output:
- Run dir: `evox2-logs/20261103-230329-964-bench-rocm-b12038-ctx131072-41e29760584b`.
- Native bench **`pp 111137`**, **285.350153 tok/s**; exactly one repetition, StdDevTokensPerSec 0 is not statistical validation.
- `Status=OK`, `ExitCode=0`, `ExitCodeSource=System.Diagnostics.Process.ExitCode`, `BenchBackends=ROCm`, `ADLXSamples=413`, P-MODE Performance start/end, `ADLXPowerClass=Performance-like (118.091W)`, `ResourceSamples=0` (disabled by default; ADLX still monitored).
- Compared with the existing same-source CLI IQ3 run **287.26 tok/s** at 111148 CLI prompt tokens (11-token difference), bench is **−0.665%**; close directional parity. Input source SHA and complete model/env/native JSON identity **not yet independently inspected from the new IQ3 folder**; preserve as user-reported until combined ZIP arrives.
- PowerShell error: `PropertyNotFoundStrict: property 'PP' not found` at `Write-Host (..., $result.PP, ...)` in supplied `Evox2-R6-ROCm-MH128K-Bench-IQ3-IQ4-20261103.ps1`. `Measure-LlamaBench.ps1` returns a CSV-like summary with **`AvgTokensPerSec`**, not CLI's `PP`. This orchestration mistake happened after the wrapper had completed and is *not* an inference/backend failure. Because the loop aborts before the IQ4 iteration, IQ4 is **not measured**; no IQ4 PP inference yet.

**Recovery delivered** as standalone `Evox2-R6-ROCm-MH128K-Bench-IQ3-IQ4-20261103-resume.zip` (outside repository), updating `Write-Host` to `$result.AvgTokensPerSec` and introducing **`-Stage Resume`**. Resume re-checks preflight, confirms saved IQ3 `result.json` native OK/backend/executable SHA, `conditions.json` exact model/input hash/ctx/ubatch/actual prompt count/Gather OFF, `summary.csv` and `llama-bench.json` one valid PP row; it then skips IQ3 GPU compute and runs only IQ4, ultimately packaging both folders and plan metadata in the original expected output ZIP `%TEMP%\evox2-r6-rocm-mh128k-bench-iq3-iq4-20261103.zip`. The user must invoke **`& $s -Stage Resume`**, not `Run`, after replacing script. No source patches, inference binary rebuild or change to benchmark flags. IQ4 result **pending**.

## ROCm MH-128K llama-bench 2/2 PASS and exact ANLP 128k comparison

User archive `evox2-r6-rocm-mh128k-bench-iq3-iq4-20261103(1).zip` (reviewed direct raw `conditions.json`, `llama-bench.json`, `stderr.log`, `summary.csv`, `gpu-metrics.csv`, `mh-bench-plan.json` in all two runs), **2/2 native ROCm b12038 PASS**, exact seed20261026 **A** source SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`, byte length172120, original IQ3/IQ4 PLE16.

| Model | MH bench run | Native PP tokens | Time ns | PP tok/s | Earlier MH CLI tok/s | bench vs CLI | ADLX high-use mean VRAM MHz | high-use VRAM <900 MHz samples | high-use mean GPU MHz | high-use mean GPU W | Peak ADLX GPU memory MiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| IQ3 | `20261103-230329-964-bench-rocm-b12038-ctx131072-41e29760584b` | **111137** | 389475873200 | **285.350153** | 287.26 | **-0.665%** | **925.74** | 41/386 | **2894.52** | **118.09** | **55734** |
| IQ4 | `20261103-232650-185-bench-rocm-b12038-ctx131072-ee10fb54af0a` | **111137** | 355654709800 | **312.485669** | 313.89 | **-0.447%** | **957.86** | 3/353 | **2892.29** | **119.53** | **66659** |

Both `Status=OK`, native `ExitCode=0`, `BenchBackends=ROCm`, `BuildNumber=12038`, `Commit=d321e7ff3`, **same llama-bench SHA256** `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`; input 111137 available and all 111137 used (head), both stderr show warmup prompt run + timed prompt run1/1, ADLX 413/375 samples, performance P-MODE maintained, no fatal GPU errors, resource monitor deliberately off. Each single repetition: stddev0 does not estimate speed variance.

**Speed rank reversal reproduces in both tools:** MH IQ4/IQ3 `312.485669/285.350153-1=+9.509%`; earlier same-input CLI `313.89/287.26-1=+9.270%`. Earlier ANLP head-128k bench (from `evox2-r6-pp128k-matrix-20261103(2).zip`) **IQ3 299.151698**, **IQ4 290.899345**, IQ4/IQ3 **−2.7586%**. This is a measured **crossover**, but not yet uniquely attributable to content.

**Direct machine audit of raw ANLP-vs-MH bench `conditions.json` (both IQ3/IQ4):**
- EXACT MATCH: ROCm backend and device, same quant-specific GGUF path and model file identity, identical executable build SHA, source commit, `-n0 -d0 -r1 --delay0 -b2048 -ctk/-ctv f16 -t4 -ngl999 -ncmoe0 -fa auto -o json -c131072 --prompt-slice head --progress`, **warmup ON** (NoWarmup=false), no resource monitor, QWEN4EXP_QSA_GATHER='0', no MTP use, Performance P-MODE, UMA96 GB.
- **Runtime option difference: `-ub 1024` ANLP vs `-ub 512` MH.** Native `llama-bench.json` directly confirms n_ubatch 1024/512. Also `-p126253` ANLP vs `-p111137` MH. The ANLP case slices *first126253* of >255k text-source tokens; MH case uses all111137 raw file tokens. Therefore differences are **source/content, prefill length, and UBatch**, not only document content.
- **Environment provenance difference:** earlier ANLP `HIP_PATH=ROCM_PATH=C:\TheRock\build\.venv\Lib\site-packages\_rocm_sdk_devel`, MH `HIP_PATH=ROCM_PATH=C:\TheRock\build\.venv`. Both use staged same binary/DLL set and ROCm `ggml-hip.dll`, but runtime env differs and should be normalized in a strict controlled study; do not assume exact DLL-loaded dependency identity from environment strings alone. Additional `GGML_VK_QSA_UNION`, `LLAMA_MTP_SKIP_DENSE_INDEXER`, `LLAMA_QSA_SKIP_NOOP_INVALIDATION`, `LLAMA_MTP_DRAFT_PREFILL_KV_CROP`, `LLAMA_MTP_EH_PROJ_FLATTEN`, `LLAMA_EVOX2_RGP_SSE_TRACE` are **unset in ANLP** vs explicit '0' in MH; these are default-OFF flags, not evidence of feature enabled in ANLP. No Jinja in *either* native bench workload; earlier CLI MH Jinja does not explain this bench crossover.
- Native `llama-bench.json` differences restricted to `n_ubatch`, `n_prompt`, timing output and test timestamp; otherwise listed native parameters match. Timing sessions differ by ~8h.
- ADLX during GPU-load >=95%: ANLP IQ3 mean VRAM **971.8MHz** (0 under900), IQ4 **998.6MHz** (0 under900); MH IQ3 **925.7MHz** (41/386 under900), IQ4 **957.9MHz** (3/353 under900); GPU core means ANLP 2882.7/2888.4 vs MH 2894.5/2892.3MHz (IQ3/IQ4). VRAM-clock difference is a **possible additional confound**, not proven cause. Small single-run sample count does not isolate these mechanisms.

**Next narrow controlled step:** Hold raw source, `-p`, runtime env fixed within arms and vary only UBatch via **MH IQ3 + IQ4 `-ub1024`** two-run pair. Alternatively/next to isolate text with *matched token count AND UBatch*, run the **ANLP `d31` head 111137 tokens with `-ub512`** for IQ3/IQ4 (two runs), same 131072 ctx, binary, backend, Gather OFF, native CLI Jinja not involved. That directly matches MH PP length and UBatch and leaves original content as main controlled difference; keep HIP_PATH/ROCM_PATH consistent and inspect high-load VRAM clocks for confounding. Do not conflate raw source file length with actual processed PP tokens. COMMON-005 is OFF in both existing crossover arms, so its ON/OFF is not needed to explain existence of crossover. Exact kernel explanation (ROCm quantized matmul/dequant/expert behavior) needs RGP or graph-level microbench after flags/token length controls.

## Controlled ANLP-versus-MH bench follow-up: same 111137 PP tokens and ubatch512 (planned)

User requested a **two-run ROCm b12038 ANLP bench controlled check** to isolate input content after MH-128K demonstrated IQ4 PP +9.51% and previous ANLP bench (126253 tokens, ubatch1024) had IQ3 advantage. Command supplied as a **single inline PowerShell block**, no new standalone orchestrator script (the earlier wrappers already handle ADLX and logging). **No results yet.**

**Source:** original ANLP 256k text `C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\long-input-abstract-out\nlp-survey-ch3-d31-b1.txt` SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, verify exact hash in PowerShell before launch, `--prompt-slice head` **111137** tokens (file contains ~255169 available). This avoids re-slicing text and eliminates the previous tokenizer/PowerShell preflight failure modes.

**Executable:** `build-rocm-bench-real-r6\bin\Release\llama-bench.exe`, b12038 commit `d321e7ff3`, SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`. Same model keys `UnslothPle16` and original `Qwen38Iq4XsPle16` (not Huihui), same binary and models as MH. Native invocation via `Measure-LlamaBench.ps1` with `-c131072 -p111137 -n0 -d0 -r1 -b2048 -ub512 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16 --prompt-slice head --progress`, **warmup ON**, `ResourceMonitor` OFF, ADLX enabled, P-MODE Performance. Set `HIP_PATH=ROCM_PATH=C:\TheRock\build\.venv` via activated venv, Gather `QWEN4EXP_QSA_GATHER=0` and all MTP flags explicit0; no Vulkan QSA optimization. Each wrapper result must have `Status=OK`, backend ROCm, `PromptTokens=111137`; note returned PP rate property **`AvgTokensPerSec`** (not CLI `PP`), store both RunDirectory paths and archive. Expected ZIP `%TEMP%\evox2-r6-rocm-anlp-111137-ub512-iq3-iq4.zip`.

**Decision:** Compare **IQ4/IQ3 PP speed ratios** between new ANLP matched-token/ubatch pair and MH IQ3 **285.350153** / IQ4 **312.485669 tok/s**. A continued IQ3 advantage for ANLP makes input-dependent kernel/expert selection or token distribution plausible; clock/driver interference remain caveats. If ANLP also favors IQ4 at ubatch512, test UBatch 1024 on MH while retaining prompt length to isolate batching effect. This source-level and option-level check is *not* mathematical proof of same MoE expert routing; route/graph trace is a separately proposed follow-up.

## Historical Vulkan MH-128K IQ3/IQ4 PP ratio and older successful IQ4 128k GPU memory review — 2026-11-04

User asked to confirm the earlier conversation that **Vulkan also showed a small IQ4 PP advantage in MH-128K**, vs larger ROCm advantage, and whether archived **Vulkan IQ4 MH-128K** runs could be re-opened to inspect memory/VRAM behavior relative to **2026-11-03 b12032 Vulkan IQ4 ANLP 128k device-lost**.

**Confirmed old Vulkan data from** [MH-128K original 16run study](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/search-retrieval/mh-128k/results/MH-128K-QUALITY-SUMMARY-2026-10-25.md): Vulkan **b11592**, same seeds 20261025 and 20261026 A/B, ctx131072, MTP OFF, f16 KV, QSA optimization OFF, Performance P-MODE, IQ3 PP average **182.93**, original IQ4 PP **184.22 tok/s** (+**0.705%** original IQ4 relative to IQ3), IQ3 TG **24.56**, IQ4 TG **23.13 tok/s**. Both had high-load VRAM mean ~987.3/~989.6 MHz and high-load VRAM min943/948MHz, with **0 samples under900MHz in all 16-run cohort**. Thus the historical direction was indeed Vulkan IQ4>IQ3 by a *small* magnitude. This is not a same-binary comparison to later ROCm b12013/b12038; the ~9–10% ROCm advantage may reflect backend differences and/or software generations, memory clocks, quantized kernels, source/flags. Don't assert the backend alone is causal.

**Separate later successful original IQ4 Vulkan b11908 20261028–29 runs** from [R6-S9 IQ4 results](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md). For frozen **MH-128K seed20261026 A/B** (111148 CLI input tokens; `-c131072 -b2048 -ub512`, `--jinja --single-turn`, `-fit on`, QSA UNION OFF, MTP OFF), the original IQ4 finished normally, PP **248.47/248.58 tok/s**, max **process GPU committed 93.308GiB** both, min free physical RAM **24.215/23.921GiB**. Separate b11908 original IQ4 **real paper128k** (raw SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, 126253 actual CLI prompt tokens, *different text* from b12032 ANLP d31 input) also finished normally with PP **250.67tok/s**, max process GPU committed **93.339GiB**, min physical free **23.909GiB**, generation 256. `b11908` successful archive filenames and expected hashes:
- `20261028-225754-044-cli-vulkan-b11908-ctx131072-ad23c7f638dc.zip` (MH-A), SHA256 `df4f5a79d36fb82357ecf09bf286fe3815bedfc84a9d688f00da6312c2b20b85`;
- `20261029-002531-955-cli-vulkan-b11908-ctx131072-55d5bc35cc77.zip` (MH-B), SHA256 `0e69c1a96939ad18c81966f5dbaf1cd1da2a45ac38abf6d8810f75e8df816d49`;
- `20261028-222548-980-cli-vulkan-b11908-ctx131072-76ead0584bf3.zip` (separate real paper128k), SHA256 `9bf0eb4fe806ff31d52a0498fee273964670ecfba2cd5afdba5de64328e3dc85`.

These ZIP **names and Library metadata were located**, but **raw bytes were not accessible in this session**: Project-backed file materialization was rejected with `This Project file does not have an authorized raw-byte materialization path`, and Files read reported no readable content for the ZIP. Consequently **b11908 per-sample ADLX GPU VRAM usage, RDP status, GPU core/VRAM clocks and whether an end-of-run hidden spike existed remain unexamined**. Do not claim to have analyzed these resource histories. Request user to re-upload preferably MH-A and old real-paper128k ZIP for detailed telemetry if they still exist locally.

**Failed 2026-11-03 b12032 original IQ4 Vulkan ANLP head-128k native `llama-bench` Case08**: re-opened current available archive `evox2-r6-pp128k-matrix-20261103(2).zip` and read raw stderr, `result.json`, and **373 ADLX 2s `gpu-metrics.csv` samples**. Source `nlp-survey-ch3-d31-b1.txt` SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, processed **126253 head tokens**, ctx131072, `-ub1024`, native **warmup ON**, `GGML_VK_QSA_UNION=1`/MIN_KV32768 and stderr has `qsa-union active`. Exit failed (Windows `3221226505`), stderr `ggml_vulkan: device lost on Vulkan0`, process result parse failed due truncated native JSON; Windows LiveKernelEvent0x141 reported earlier. ADLX peak **97130 MiB ≈94.85 GiB** `gpu_vram_mb`, first at 17:08:44.080 JST ~444s into run and remained until final failure; near tail 97,130 MiB ->88,428 MiB (17:13:36) ->609 MiB (17:13:38) following device loss/release; high-use GPU >=95% **352/373** ADLX samples, high-use mean VRAM clock ~**848.5 MHz**, and low clock values as low as ~513–544MHz during the busy failure window. Interpretation: near-UMA high ADLX GPU-memory use + depressed VRAM clocks, but **not proof that memory exhaustion caused the GPU TDR**.

**Critical metric mismatch**: `b11908 93.308GiB` is documented *process GPU committed*, while `b12032 97130MiB` is ADLX `gpu_vram_mb` system-reported usage (and also includes possible other allocations). Converting units does not make them directly comparable. Need per-run `resources.csv` process GPU dedicated/shared/commit and `gpu-metrics.csv` ADLX **same metric definition** before asserting a difference. Old b11908 uses CLI, Jinja ON, `-fit on`, `-ub512`, generates 256–512 output tokens, QSA UNION OFF; failed b12032 uses native bench, `-ub1024`, PP-only, QSA UNION ON; older successful real paper SHA also differs. **Do not infer that MH content was uniquely safe, or that QSA caused device-lost, or that b12032 requires more VRAM until matched logs/testing**.

**Investigation order (non-destructive):** (1) analyze b11908 MH-A and real-paper128k logs if user re-uploads; compare clocks, GPU memory timeline, physical RAM minimum, GPU process committed and allocator warnings with new b12032 failure. (2) finish already-running ROCm ANLP vs MH matched 111137/ubatch512 experiment and establish robust quant rank vs input. (3) for backend-specific kernel/expert hypotheses consider source/quantized op/RGP and matched lower-context runs; avoid new Vulkan b12032 IQ4 128k until memory/TDR mechanism is understood. (4) If later benchmarking Vulkan IQ3/IQ4, use 32k/64k safe pilot(s) with otherwise identical builds, input length and flags, and repeat paired runs to resolve sub-1% differences.

## 2026-11-04 — Raw b11908 Vulkan IQ4 MH-A and real-paper128k GPU telemetry audit

On 2026-11-04 the user re-uploaded the two archived **complete Windows raw ZIPs**, which are accessible and have been parsed (distinct from previous metadata-only investigation). SHA256 matches the documented October evidence:
1. `20261028-225754-044-cli-vulkan-b11908-ctx131072-ad23c7f638dc(2).zip` (MH seed20261026 A): **`df4f5a79d36fb82357ecf09bf286fe3815bedfc84a9d688f00da6312c2b20b85`**.
2. `20261028-222548-980-cli-vulkan-b11908-ctx131072-76ead0584bf3(1).zip` (separate real ANLP `nlp-survey-ch3-d15-b1.txt`, not later d31): **`9bf0eb4fe806ff31d52a0498fee273964670ecfba2cd5afdba5de64328e3dc85`**.

Both have matching original IQ4_XS Ple16 GGUF path, identical b11908 Vulkan executable SHA `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`, build commit `b82243bf0`, runtime artifact Verified digest `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3`, `-c131072 -ngl999 -ncmoe0 -t4 -b2048 -ub512 -fa auto -ctk/ctv f16 -fit on --cache-ram0 --jinja --single-turn --reasoning off -tb4 --ctx-checkpoints 0t`, **`GGML_VK_QSA_UNION=0`**, MTP OFF, no graph realloc (stderr), 49/49 layers requested. Both `Status=OK ExitCode=0`, no truncation, P-MODE Performance direct probe at both start and end; session RDP, ADLX monitor valid and Windows resource monitor valid.

| Metric, exact source column | MH A b11908 | ANLP d15 b11908 | failed ANLP d31 b12032 llama-bench |
|---|---:|---:|---:|
| prompt tokens | 111148 | 126253 | 126253 |
| prompt PP tok/s | 248.47 | 250.67 | no complete native timed row |
| generated tokens | 250 | 256 | 0 requested |
| ADLX samples | 248 | 276 | 373 |
| Windows resources.csv samples | 246 | 274 | **0, disabled** |
| **ADLX `gpu_vram_mb` peak MiB** | **95435** | **95465** | **97130** |
| ADLX `gpu_vram_mb` at high utilization average MiB | 95353.10 | approx95400 | 95876.64, polluted by post-fault samples |
| GPU utilization>=95% samples | 228 | 256 | 352 |
| **high-use VRAM clock mean MHz** | **999.60** | **~1000** | **848.55** |
| high-use VRAM clock minimum MHz | **992** | check from raw | **459** (post-fault); <900 first at elapsed116s |
| count VRAM clock <900MHz at high-load | **0/228** | **0/256** | **274/352** |
| high-use GPU clock mean MHz | 2815.23 | approx2815 | 2840.47 |
| high-use GPU power mean W | **118.79** | **119.02** | **107.38** |
| GPU temperature peak C | **86** | **84** | **84** |
| **Windows process GPU committed max `TargetGPUTotalCommitted_GiB`** | **93.308 GiB** | **93.339 GiB** | unknown (no resource monitor) |
| Windows adapter total committed max `AdapterTotalCommitted_GiB` | **93.989 GiB** | **94.017 GiB** | unknown |
| Windows physical free RAM min `FreeRAM_GiB` | **24.215 GiB** | **23.909 GiB** | unknown |
| Windows system committed max / limit GiB | **104.781 / 127.647** | **105.672 / 127.647** | unknown |
| Windows hard paging page input `PagesInput_PerSec` sample median | **0** | **0** | unknown |
| peak ADLX GPU MiB relative to past MH | baseline | **+30 MiB** | **+1695 MiB** |

Both old runs at a 2s sampling interval held ADLX `gpu_vram_mb` at ~95.2–95.46k MiB throughout the busy phase, **without a VRAM clock collapse** and while physical RAM free stayed >23.9GiB. However the reported GPU memory use approaches configured UMA 96GiB (98,304MiB), so the successes do **not** prove generous VRAM allocation headroom. Windows hard paging `PagesInput_PerSec` had nonzero bursts (38/246 MH, 76/274 paper), but medians are zero and long sustained paging cannot be inferred from these stats. ADLX and Windows GPU process committed metrics are separate; the table labels each explicitly.

**Old b11908 stderr exact allocator breakdown (both):** Vulkan device `total=114507 MiB` (driver-reported internal budget-like metric, **not** UMA configured 96GiB), `self=93060 MiB`, comprising `model=88688 MiB`, `context=3952 MiB`, `compute=420 MiB`; separate recurrent/KV component lines include KV **3072+768 MiB**, RS **112.57 MiB**, CPU Vulkan_Host model **644 MiB**. Final memory breakdown `free 14798MiB` MH vs `14768MiB` paper; do not equate to spare system/UMA memory. Both graph realloc counters zero.

**Re-examined failed b12032 bench native stderr:** same original IQ4 GGUF, `-ub1024`, `GGML_VK_QSA_UNION=1,MIN_KV=32768` and `qsa-union active`; native `llama-bench` explicitly reports **`warmup prompt run` followed by `prompt run 1/1`** before `vkGetDeviceFaultInfoEXT ... failed:-4` and `device lost on Vulkan0`. Thus the bench executed a long warmup and **started a second full long PP**, unlike the successful single-request old CLI. ADLX memory rose from ~96.6k to97,130MiB; first high-GPU-use VRAM clock <900MHz at elapsed ~**116s** during warmup; subsequently 800–850MHz sustained for much of run, with occasional recovery to ~1000MHz. GPU usage typically 99–100%. The memory didn't fall until just before process shutdown. ADLX peaks old/new **+1695MiB** vs MH or +1665 vs old paper, on the same hardware-reported metric. **Vulkan QSA UNION scratch** logs `81801472 bytes` (~78 MiB), so its scratch alone does not explain all ~1.6GiB of ADLX memory difference. Difference also involves C++ version, CLI/bench contexts, batch/ubatch, warmup and input; no causal attribution to QSA, driver, UMA exhaustion or thermal throttling alone is supported.

**Risk-based next action:** Two valid *risk-reduction* variables from successful b11908 are **UNION OFF and UBatch512**, combined with bench's documented `-NoWarmup` to avoid a *second* full prefill. Nonetheless **no full-GPU b12032 128k IQ4 benchmark has been demonstrated safe**: old b11908 and b12032 are different C++/DLLs and old CLI vs new bench allocate differently; full 128k loaded IQ4 already occupies >95,000MiB ADLX, device lost near97,000MiB. Do not resume original b12032 `Remaining`/Case08 with UNION ON, UB1024 and warmup ON. Recommended approach: finish current ROCm ANLP matching study; use a **fresh small, isolated b12032 Vulkan 64k QSA-OFF / ub512 / no-warmup** IQ4 pilot and inspect ADLX+**enable `-ResourceMonitor`**; if peak memory high or clock falling, stop. Only if pilot is stable and user accepts residual TDR risk consider a **single** conditional MH-128K IQ4 case with `-p111137 -c131072 -ub512 GGML_VK_QSA_UNION=0 -NoWarmup`, ADLX/Windows memory monitor, followed by IQ3 control; the **failed original ANLP 126253** is more demanding and should wait. Alternative lower-memory diagnostic requires intentional change such as partial GPU offload `-ngl` reduction or verified quantized KV, and must be labeled **noncomparable** to all-GPU f16 prior performance. Full-gpu 128k single-pass settings are *lower risk, not guaranteed safe*; avoid overpromising. The original matrix statuses remain 9 OK / 1 FAIL / 2 not run, no automatic retry. The historical Vulkan b11592 original study per-case source shows IQ4 PP advantage in **each** of four A/B seed cells, approximately +0.49%, +0.64%, +0.85%, +0.85%, not just 4run average +0.71%, though A/B orderings are correlated and values are separated from modern ROCm by build/backend.

## 2026-11-04 ROCm b12038 ANLP matched UBatch512 results and four-run UBatch crosscheck

**Fresh user ZIP:** `evox2-r6-rocm-anlp-111137-ub512-iq3-iq4.zip`, two real `llama-bench` runs. Independently inspected binary SHA, `conditions.json`, `llama-bench.json`, `result.json`, native stderr, source SHA, model size and parameter identities. **Both PASS exit0, backend ROCm, b12038 `d321e7ff3`, bench EXE SHA `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`.** Same original ANLP source `nlp-survey-ch3-d31-b1.txt` SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`; `-p 111137 --prompt-slice head -c131072 -b2048 -ub512 -n0 -d0 -r1 -fa auto -ctk f16 -ctv f16`, warmup ON, QWEN4EXP_QSA_GATHER=0, all MTP flags off, TheRock venv-root HIP_PATH/ROCM_PATH, P-MODE / ADLX. No GPU error.

| Model | Run ID | Native PP tokens | Native avg_ns | PP tok/s |
| --- | --- | ---: | ---: | ---: |
| IQ3 original Unsloth PLE16 | `20261104-000013-069-bench-rocm-b12038-ctx131072-8ca031edc181` | 111137 | 390254534000 | **284.780804** |
| IQ4 original Unsloth PLE16 | `20261104-001419-485-bench-rocm-b12038-ctx131072-767870d902fe` | 111137 | 357439814500 | **310.925072** |

IQ4/IQ3 advantage **+9.181%** on ANLP `111137/ub512`, versus **+9.509%** on *different MH source*, **same prompt tokens and UBatch** (MH IQ3 **285.350153** / IQ4 **312.485669**). Therefore previous *input genre* hypothesis is substantially weakened for these matched length+batch examples. Prior ANLP `126253/ub1024` was IQ3 **299.151698** vs IQ4 **290.899345**, IQ4 **−2.759%**. This change is still **confounded by prompt length and UBatch**, both changing simultaneously; cannot yet assert UBatch alone caused crossover. Each is one run, no variance estimate.

**User-requested narrow ROCm follow-up before Vulkan:** Vary UBatch holding `-p` fixed **within each source type**, reusing available original 128k native random runs:
- MH frozen **seed20261026 A, raw111137 tokens, UBatch512**: IQ3 **285.350153**, IQ4 **312.485669 tok/s** (**already done**). NEW: **UBatch1024 IQ3 and IQ4**, same SHA source `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`. 2 runs.
- Native random **126253 tokens, UBatch1024**: IQ3 **313.880965**, IQ4 **308.615225 tok/s**, original 12-case matrix `03-ROCm-IQ3-Random` and `04-ROCm-IQ4-Random` (**both already done; do not repeat IQ3 or IQ4**). NEW: **UBatch512 IQ3 and IQ4** with same `-p126253`, **no `-f`**, native `llama-bench` random-token path. 2 runs. Same executable `d321e7ff3`, all other inference args identical `-c131072 -b2048 -t4 -ngl999 -ncmoe0 -fa auto -ctk/-ctv f16 -n0 -d0 -r1`, warmup ON, Gather OFF, MTP OFF, venv-root HIP_PATH/ROCM_PATH, resource monitor as before (ADLX ON). Native random is pseudorandom within benchmark and not proven externally bit-identical token IDs between jobs; maintain same build/model/batch/length for interpretable UBatch comparison, do not mix with source-file tokenizer results.

Exactly **four new runs**, no repetition of completed cases. Standalone PowerShell `Evox2-R6-ROCm-UBatch-Crosscheck-20261104.ps1` and README supplied in `Evox2-R6-ROCm-UBatch-Crosscheck-20261104.zip` outside repo. Supports `-Stage Plan`, then independent `-Stage Run -Case MH-IQ3-UB1024`, `MH-IQ4-UB1024`, `Random-IQ3-UB512`, `Random-IQ4-UB512`, and `-Stage Package`. Each case logs using unchanged `Measure-LlamaBench.ps1`; validates fixed bench EXE hash and frozen MH prompt SHA; checks GGUF presence and size without rehashing whole models; runs exactly one new case per command, writes per-case JSON in `%TEMP%\evox2-r6-rocm-ubatch-crosscheck-20261104`; refuses automatic rerun of already recorded case; package can contain partial jobs and identifies missing. Expected final ZIP `%TEMP%\evox2-r6-rocm-ubatch-crosscheck-20261104.zip`. **The script has not been executed on Windows in this session.**

**Next interpretation:** If MH ub1024 switches to IQ3 advantage *with unchanged111137 tokens*, UBatch is strong contributor; if MH remains IQ4-fast even ub1024 then 111137 vs126253 length or structural batching differences become candidates. Random ub512 vs ub1024 at identical126253 and same model controls UBatch under pseudo-random input independently. If two UBatch tests disagree, inspect prompt length and expert routing / quantized GEMM and ADLX memory clock, avoiding premature single-cause attribution. Leave Vulkan b12032 128k IQ4 on HOLD pending ROCm gates and risk review.

## 2026-11-04 — ROCm b12038 UBatch 512/1024 matched 4run actual results

**User supplied four complete newly measured runs** in `evox2-r6-rocm-ubatch-crosscheck-20261104(1).zip` including native `llama-bench.json`, `summary.csv`, `conditions.json`, `result.json`, `stderr.log`, ADLX `gpu-metrics.csv`, `crosscheck-index.json`. Direct ZIP audit: **all 4/4 Status OK, ExitCode 0, BackendDetected ROCm, Build b12038 commit d321e7ff3**, same bench EXE SHA256 `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`, correct original Unsloth IQ3 and original IQ4 GGUF, `-c131072 -b2048 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16 -n0 -d0 -r1`, prompt warmup ON, Gather OFF and MTP OFF, P-MODE Performance maintained, ADLX monitoring success, no GPU faults. MH source `mh128k_s20261026_A.prompt.txt` SHA `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3` independently validated, 111137 native tokens head. Random uses native **no-file** `llama-bench` pseudo-random-token PP path, 126253 tokens, not a reusable explicit SHA-pinned sequence (cannot assert bit-identical token IDs across runs).

### All currently matched 128k-context ROCm bench PP rows

| Input | n_prompt | UBatch | IQ3 PP tok/s | original IQ4 PP tok/s | IQ4/IQ3 (%) | Evidence |
|---|---:|---:|---:|---:|---:|---|
| MH-128K seed20261026 A | 111137 | 512 | 285.350153 | 312.485669 | **+9.509** | prior 2026-11-03 MH bench ZIP |
| MH-128K seed20261026 A | 111137 | 1024 | **319.116692** | 310.343360 | **−2.749** | **new 4run ZIP** |
| ANLP d31 head | 111137 | 512 | 284.780804 | 310.925072 | **+9.180** | prior 2026-11-04 ANLP 111137 ZIP |
| ANLP d31 head | 126253 | 1024 | **299.151698** | 290.899345 | **−2.759** | prior 12-case matrix ZIP |
| Native random | 126253 | 512 | 283.042099 | 307.105801 | **+8.502** | **new 4run ZIP** |
| Native random | 126253 | 1024 | **313.880965** | 308.615225 | **−1.678** | prior 12-case matrix ZIP |
| llama.cpp code head | 126253 | 1024 | **299.941061** | 291.982779 | **−2.653** | prior 12-case matrix ZIP |

Every row one timed repetition (native stddev=0 does not establish low variance), same ROCm b12038 binary, ctx131072, batch2048, F16 KV, FA auto, Gather OFF, MTP OFF; at fixed n_prompt and source with only UBatch changed:
- **MH** UB512→1024: IQ3 **+11.833%**, IQ4 **−0.686%**. IQ4/IQ3 rank from **+9.509%** to **−2.749%**.
- **Random** UB512→1024: IQ3 **+10.895%**, IQ4 **+0.492%**. IQ4/IQ3 rank from **+8.502%** to **−1.678%**.
- Across sources at UB512, IQ3 ≈283–285 tok/s and IQ4 ≈307–312 tok/s. The other ANLP and code UB1024 rows have **different prompt lengths** from MH, so a quantization-specific batching conclusion should come from *within-source fixed-token* MH and Random pairs, not from those confounded contrasts.

### New four-run details / ADLX high GPU use >=95%

| Case / Run ID prefix | Native PP tok/s | avg PP ns | Samples >=95% GPU | high-use VRAM clock mean MHz | high-use VRAM <900MHz | high-use GPU clock mean MHz | high-use GPU power mean W | max ADLX gpu_vram_mb MiB | max temperature C |
|---|---:|---:|---:|---:|---|---:|---:|---:|---:|
| MH IQ3 UB1024 `20261104-005501-840` | 319.116692 | 348264452500 | 345 | **968.7** | 1/345 | 2884.4 | 119.2 | 56323 | 87 |
| MH IQ4 UB1024 `20261104-010801-682` | 310.343360 | 358109804600 | 357 | **997.9** | 0/357 | 2889.3 | 119.5 | 67240 | 87 |
| Random IQ3 UB512 `20261104-012122-516` | 283.042099 | 446057320100 | 443 | **932.4** | 54/443 | 2887.2 | 118.1 | 55745 | 85 |
| Random IQ4 UB512 `20261104-013734-679` | 307.105801 | 411105878400 | 408 | **951.2** | 2/408 | 2890.6 | 119.3 | 66689 | 87 |

The earlier **MH UB512** high-load averages were IQ3 VRAM **925.74MHz** (41/386 <900), IQ4 **957.86MHz** (3/353 <900), while MH UB1024 clocks improved to **968.7/997.9MHz**, respectively; **IQ4 throughput is nearly flat despite its similarly raised VRAM clock**. Thus the observed ~11% differential response is consistent with quantization-dependent compute efficiency/physical batch behavior and *possibly* secondary memory-clock policy, not proven exclusively one or the other. ROCm HIP kernel tracing or controlled clock matching/RGP will be needed to identify which quantized matmul/dequant/FFN/expert path causes it. Different dataset content & PP lengths affect absolute rates, but a strict UBatch-controlled MH and native Random double crossover now confirms UBatch is a major experimental factor.

**Scope/decision:** Requested four new ROCm runs are complete; no need to redo available IQ3. Leave Vulkan b12032 IQ4 128k retry on HOLD until independent memory/TDR controls are chosen, including existing successful b11908 QSA OFF, UB512, CLI, and ADLX logs. If proceeding to isolate source/token interplay, optional **ANLP head111137 UB1024 IQ3+IQ4** (2run) would hold source and prompt size fixed versus new MH UB1024, and/or targeted RGP high-load HIP comparisons (not broad matrix). Do not infer cross-backend performance solely from these ROCm figures.

## 2026-11-04 planned Vulkan b12032 MH-128K UBatch512 QSA-ON quant comparison: OFF safety gate first

**User decision:** ROCm UBatch investigation closed for now. Next requested performance comparison is **Vulkan b12032 `llama-bench` MH-128K, 111137 raw file tokens, UBatch512, original Unsloth IQ3 and original IQ4, QSA UNION ON**, but due to the previous `0x141 / device lost` on original-IQ4 Vulkan b12032 128k, the **IQ4 QSA-OFF pilot is an independent go/no-go gate**. This is a prospective plan, **not a Vulkan b12032 128k success claim**.

Baseline: old b11908 Vulkan IQ4 MH-A CLI processed 111148 Jinja-wrapped tokens, `-ub512 -fit on GGML_VK_QSA_UNION=0`, ADLX peak GPU memory **95435 MiB**, Windows process GPU committed93.308GiB, high-load VRAM clock999.6MHz, 0/228 high-use samples <900MHz, min free physical RAM24.215GiB, PASSED. Separately b12032 full IQ4 ANLP bench at PP126253 UB1024 UNION ON warmup ON, ADLX peak97130MiB and high-load VRAM clock848.5MHz, failed DeviceLost/LiveKernelEvent141. Different build/tool/input/memory layout. b12032 64k IQ4 QSA OFF/ON (earlier evidence) succeeded but does not establish 128k safety.

**Gate conditions for first *single run***:
- Executable `build-vulkan-bench-real-r6\bin\Release\llama-bench.exe` exact SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` (Vulkan b12032 `c4ddd239b`).
- Frozen source input `MH128K_S20261026_A` local configuration key, SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`; native **`llama-bench` reads 111137 raw tokens** (unlike CLI's 111148 due chat Jinja). Fixed `--prompt-slice head -p111137 -c131072 -n0 -d0 -r1 -b2048 -ub512 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16`, standard original IQ4 model key `Qwen38Iq4XsPle16` (not Huihui).
- **`-NoWarmup`** to perform only one 111137-token prefill rather than warmup+timed 2x, **`-ResourceMonitor`** (Windows physical RAM/process committed/system commit) plus default ADLX GPU 2s and direct P-MODE probes. Set `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `QWEN4EXP_QSA_GATHER=0`, all MTP path optimizations OFF, Vulkan diagnostic stats OFF. Single `Measure-LlamaBench.ps1` invocation via PowerShell instead of a new custom orchestration script to avoid prior property/exception mistakes. `-DryRun` initial preflight recommended.
- **Do not automatically execute the ON comparison**. First check status exit0, `input_sha`, `n_prompt=111137`, GPU loading, native stderr for unexpected realloc/allocator/device warnings, Windows resource samples, ADLX `gpu_vram_mb` peak/time series, sustained high-use VRAM clock, temperature, Performance P-MODE, and spare physical memory/paging. Reference **>=96000MiB ADLX peak**, sustained VRAM slowdown, heavy paging, low physical free RAM (<12GiB), wrong build/model or any failure as *cautionary hold criteria*, not a guaranteed universal crash threshold. If sufficiently clean, proceed **Vulkan IQ3 QSA UNION ON with the same UB512,no-warmup,resource-monitor** then **Vulkan IQ4 QSA UNION ON as last highest-risk run**; inspect `qsa-union active` in ON stderr and compare at same source, PP length, settings.
- Distinguish the safety pilot OFF from the actual IQ3/IQ4 ON performance pair. The **NoWarmup** setting differs from historical ROCm runs (ON), so absolute cross-backend tok/s comparison is not strictly controlled unless repeated under identical warmup. On/off includes effect of QSA only but runs at separate times and have no repetition. At present no b12032 128k full-GPU IQ4 `llama-bench` configuration is certified safe; do not rerun original 12-case `Remaining`, do not presume reducing UB and warmup rules out TDR. This plan leaves already finished ROCm PP study untouched.

## 2026-11-04 Vulkan b12032 MH IQ4 QSA-OFF UBatch512 NoWarmup gate: PASS

**New user raw ZIP independently inspected:** `evox2-vulkan-mh128k-iq4-qsa-off-ub512.zip`, run ID `20261104-093619-985-bench-vulkan-b12032-ctx131072-b170b3f90bad`. Complete `result.json`, `conditions.json`, `llama-bench.json`, native `output.log`, `gpu-metrics.csv`, Windows `resources.csv`. All records consistent: **PASS** `Status=OK,ExitCode=0`, native build b12032 `c4ddd239b`, bench EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, Vulkan AMD 8060S, original Unsloth IQ4_XS Ple16 (not Huihui), frozen MH seed20261026 A SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`. Native stderr shows `111137 available, using111137 (head)`, `prompt run1/1` (no warmup), with no Vulkan device-lost or allocator errors. Args: `-p111137 -n0 -d0 -r1 -b2048 -ub512 -c131072 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16 --prompt-slice head --no-warmup --progress`; `GGML_VK_QSA_UNION=0`, `MIN_KV=32768`, stats0; Gather0, all speed flags0, resource monitoring ON and ADLX ON, Performance P-MODE both direct probe points.

**Measured PP:** **249.836469 tok/s**, mean **444838980700 ns**; one native repetition; total wrapper duration **487.455s** (09:36:21.339–09:44:28.794 JST), no statistical variance estimate.

**ADLX 241 samples (2 sec)**: GPU memory `gpu_vram_mb` **max95490MiB**, high-use >=95% `221` samples memory mean95406.85MiB (min95271), high-use mean VRAM clock **999.15MHz**, min **987MHz**, **0/221 samples below900MHz**, last ~6 minutes high-load VRAM clock essentially1000MHz; high-use mean GPU clock **2815.39MHz**, mean GPU power **119.66W**, temp max83°C; ADLX exit0 and `PModeConsistency=Performance-like`.

**Windows resources.csv 239 samples (2 sec):** process GPU committed max **93.431GiB**, adapter total committed max **94.025GiB**, physical RAM free min **24.246GiB**, system committed peak **104.192GiB** of limit **127.647GiB**. `PagesInput_PerSec` median **0**, nonzero 44/239, huge transient peak **838272 pages/s** during initial model load (along with DiskRead peak3272.52MiB/s); after loading, only sparse minor page input, not sustained PP swapping. Background named probe status Observed complete, `PossibleNoise=false`, but not an all-process guarantee. Direct Performance P-MODE start/end and no mode change.

**Reference comparison using the same ADLX gpu_vram_mb metric**: historical b11908 CLI MH IQ4 QSA OFF/UB512 `95435MiB` maximum, high-use VRAM clock999.60MHz, completely successful; this b12032 bench `95490MiB` maximum (**+55MiB**) and 999.15MHz, also successful. Failed earlier **b12032 bench ANLP IQ4 PP126253/UB1024/QSA ON/Warmup ON** reached `97130MiB` ADLX peak, high-use VRAM clock848.55MHz, DeviceLost/LiveKernelEvent141. This is NOT an A/B QSA-only comparison: different prompt, length, ubatch and warmup; do not claim specific cause. Existing 96GB UMA label =98304MiB, leaving relatively little *configured* budget headroom despite external Vulkan device reported larger total; ADLX not a proved hard allocator cap.

**Gate decision:** **PASS QSA-OFF pilot** (below proposed 96000MiB caution line, no high-load VRAM clock collapse, usable physical RAM), so proceed to **one separate Vulkan IQ3 QSA UNION ON** single-pass MH-128K PP111137 UBatch512 test with same flags, Windows resource monitor, ADLX, P-MODE, and inspect `ggml_vulkan: qsa-union active (r6)` and memory clocks. Only after that is reviewed, and user accepts residual driver-reset risk, consider **Vulkan IQ4 QSA ON as the final riskier case**; OFF success is NOT a safety guarantee for ON. Original failed ANLP b12032 128k Case08 is still FAILED and not retried, Vulkan original 12-case matrix status remains unchanged. Do not run failed original runner `-Stage Remaining`.

## 2026-11-04 Vulkan b12032 MH-128K IQ3 QSA ON/UB512 NoWarmup: PASS but VRAM-clock hold

User archive uploaded `evox2-vulkan-mh128k-iq3-qsa-on-ub512.zip`; raw ZIP inspected from `result.json`, `conditions.json`, `llama-bench.json`, `stderr.log`, `output.log`, `gpu-metrics.csv`, `resources.csv`, `summary.csv`. Original Unsloth IQ3 Ple16 and **b12032 Vulkan `c4ddd239b`** bench executable exact SHA256 **`9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`**. Frozen MH seed20261026 A prompt SHA256 **`3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`**, 111137 native prompt-file tokens, `-c131072 -p111137 -n0 -d0 -r1 -b2048 -ub512 -t4 -ngl999 -ncmoe0 -fa auto -ctk/-ctv f16 --no-warmup --progress`; exact QSA UNION **ON** (GGML_VK_QSA_UNION='1', MIN_KV32768, stats0), original model keys and all other MTP/Gather OFF. Native stderr shows `ggml_vulkan: qsa-union fallback: query count, selection size or KV threshold` followed by **`ggml_vulkan: qsa-union active (r6), source=mask-compact, group=64, path=1, Br=16, Bc=64, groups=8, capacity=32768, min_kv=32768, scratch=76552320 bytes`**. Fallback for ineligible sub-work does **not** cancel active QSA use. No device fault or allocator/OOM messages.

**Run:** `20261104-104146-891-bench-vulkan-b12032-ctx131072-920d68b3a67d`; started 2026-11-04 10:41:47 JST, ended 10:51:57 JST, wrapper duration609.160s, status **OK**, exit0, native pp avg_ns **430899212400**, **257.918782tok/s**, one measured repetition (stddev0 not an error estimate). Both direct IP3 P-MODE probes **Performance**, `PModeChanged=false`; power-derived indicator **Ambiguous** because 104.64W mean versus threshold105W, **not** proof of P-MODE switch. Windows RDP-only display active, no detected physical monitor candidate. ADLX 302 samples, resource monitor300 samples, ADLX monitor exit0.

**214 samples at GPU usage >=95%**: ADLX GPU memory `gpu_vram_mb` **max84201MiB**, high-use mean84038.36MiB; VRAM clock **mean835.34MHz, median804MHz, min747MHz**, **171/214 (79.9%) below900MHz**, first high-GPU-use <900 at **10:46:14.920** (elapsed262s), with sustained 780–815MHz in final full minutes. GPU core clock high-use mean**2882.60MHz**, power**104.64W**, temp max**78°C**. This is sustained isolated **VRAM clock reduction** despite healthy GPU core clock and low max temp. Minute-by-minute high-use VRAM-clock means: elapsed3m=974.2,4m=875.2,5m=794.3,6m=805.5,7m=812.7,8m=795.6,9m=780.4MHz. Not solely a brief post-run drop.

Windows monitor `resources.csv`: process `TargetGPUTotalCommitted_GiB` peak**82.261GiB**, adapter total committed**82.858GiB**, free physical RAM min**24.644GiB**, system commit peak**92.884GiB** against limit127.647GiB; `PagesInput_PerSec` median0 with many nonzero bursts concentrated around initial model loading, some sparse busy-period bursts; no evidence of sustained swap saturation sufficient to cause failure. Background process probe Observed complete, PossibleNoise=false (not a universal all-process guarantee). Resource monitor printed a single invalid GPU engine utilization counter value discard (not a benchmark GPU error).

**Cautionary comparison**: immediately previous **IQ4 QSA OFF** original same MH input PP111137 UB512, no-warmup b12032 bench **249.836469tok/s**, ADLX max**95490MiB**, high-load VRAM clock **999.15MHz**, 0/221 samples<900, finished clean. However IQ3-ON and IQ4-OFF **differ by both model and optimization**; the observed ~3.23% IQ3-ON speed advantage cannot be represented as model-specific QSA-ON speed ranking. IQ3-ON uses ~11.3GiB less ADLX GPU memory than IQ4-OFF. Previously b12032 **IQ4 QSA ON** UB1024/PP126253/WarmupON failed with ADLX GPU memory**97130MiB**, 0x141 Device Lost; causes cannot be identified from these mismatched workloads.

**Gate decision: HOLD on automatically launching IQ4 QSA ON at 128k.** Even though IQ3-ON succeeded with ample memory, sustained VRAM clock <900 is explicit caution criterion from prior gate plan. IQ4 OFF at ~95490MiB near 98304MiB UMA label means relatively small memory headroom; QSA scratch ~73MiB on IQ3 gives no guarantee of IQ4 ON peak or driver behavior. Recommended next low-risk diagnostic: single **Vulkan IQ3 QSA OFF** MH111137 UB512 NoWarmup with same build, ADLX+Windows resource monitors to isolate **QSA ON vs OFF** effect and see whether VRAM slowdown also happens without QSA; stop/reevaluate if OFF also exhibits collapse. Alternatively perform a shorter **64k IQ4 QSA ON** smoke only if uncertainty remains, but existing 64k QSA ON successes are limited evidence and neither path proves 128k safe. The end goal is a matched IQ3/IQ4 QSA-ON pair if user elects the residual 128k TDR risk after reviewing this gate; do not restart old 12-case runner or claim safe memory solely from one successful IQ3. ROCm UBatch controls remain CLOSED.

## 2026-11-04 Vulkan MH-128K IQ3 QSA OFF/ON matched comparison: OFF PASSED and VRAM clock stable

New user-uploaded raw ZIP **`evox2-vulkan-mh128k-iq3-qsa-off-ub512.zip`**, RunID `20261104-110741-676-bench-vulkan-b12032-ctx131072-e8f2e613589a`, audited directly against already-uploaded raw previous IQ3 QSA-ON and IQ4 QSA-OFF ZIPs. **OFF run PASS**, `result.Status=OK`, exit0, Vulkan b12032 `c4ddd239b`, exact benchmark EXE SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, original Unsloth PLE16 IQ3, MH-A `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`, n_prompt111137 head, Context131072, UBatch512, Batch2048, `-n0 -d0 -r1 -t4 -ngl999 -ncmoe0 -fa auto -ctk/-ctv f16 --no-warmup --progress`. **Exact command-line arguments match prior IQ3-ON**; `conditions.json` tracked relevant env vars differ **only `GGML_VK_QSA_UNION=0` vs `1`**, both `GGML_VK_QSA_UNION_MIN_KV=32768`, stats0, Gather/MTP off, same GFX config. No `qsa-union active` in OFF stderr (expected); previous ON had active log. Both P-MODE Performance direct start/end, both no reset/OOM.

| metric | IQ3 QSA OFF 20261104-110741 | IQ3 QSA ON 20261104-104146 | IQ4 QSA OFF 20261104-093619 |
|---|---:|---:|---:|
| measured PP tok/s | **248.367390** | **257.918782** | **249.836469** |
| measured PP seconds | **447.470** | **430.899** | **444.839** |
| wrapper wall seconds (includes load etc) | 499.014 | 609.160 | 487.455 |
| native status | OK | OK | OK |
| ADLX samples / resource samples | 247 / 245 | 302 / 300 | 241 / 239 |
| GPU >=95% samples | 222 | 214 | 221 |
| high-load VRAM clock mean MHz | **995.302** | **835.341** | **999.154** |
| high-load VRAM clock median/min MHz | 999 / 955 | 804 / 747 | 1000 / 987 |
| high-load VRAM clock <900 MHz | **0/222** | **171/214** | **0/221** |
| high-load GPU core clock mean MHz | **2839.61** | **2882.60** | **2815.39** |
| high-load GPU power mean W | **119.450** | **104.64** | **119.656** |
| ADLX `gpu_vram_mb` peak MiB | **84049** | **84201** | **95490** |
| max Windows process GPU committed GiB | **82.110** | **82.261** | **93.431** |
| max Windows adapter total committed GiB | **82.709** | **82.858** | **94.025** |
| min physical RAM free GiB | **24.497** | **24.644** | **24.246** |
| max system committed GiB / limit127.647 | **92.775** | **92.884** | **104.192** |
| GPU temperature peak C | **86** | **78** | **83** |
| P-MODE direct | Performance | Performance | Performance |

**Within-IQ3 QSA ON vs OFF PP effect** `257.918782/248.367390-1=+3.846%` (+9.551392 tok/s), despite **VRAM clock ~160MHz lower** on ON. ON also **GPU core clock ~43MHz higher**, GPU power **~14.81W lower**, and max ADLX memory just **152MiB higher**. OFF high-load samples VRAM clock **955–1000MHz**, none under900; 1-minute groups from minute2 onward ~998–999MHz, while ON dropped around elapsed minute4 and stayed ~780–815MHz in subsequent minutes. The distinct clock regimes are therefore **not explained by IQ3 memory footprint**; association of QSA ON with GPU memory clock reduction is strengthened but not proven causal without repeated/alternating runs, driver telemetry and QSA trace. Benchmark is one timed repetition per arm, run startup/overall duration differs due loading and system state, so do not compare wrapper wall time as PP. `PagesInput_PerSec` median0 in OFF and ON; OFF peak697417 during initial 80+GiB file load, not a sustained PP-swap problem.

**Within QSA OFF same-source/model pair:** original IQ3 248.367390 vs original IQ4 249.836469 tok/s -> **IQ4 +0.5915%**, which is directionally aligned with historical b11592 Vulkan MH 4run original-IQ4 ~+0.71%, though differing builds and bench/no-warmup vs CLI/Jinja. This **supports small Vulkan original IQ4 PP advantage with QSA OFF**, but single run and 0.6% difference cannot establish statistical significance.

**Safety / QSA ON IQ4 decision:** This IQ3 OFF control met the prior clock gate (0 low-clock samples), whereas IQ3 ON did not (171/214 under900), which increases reason to treat **Vulkan IQ4 QSA ON full128k as an explicit-risk opt-in**, not a routine automatic next run. IQ4 QSA OFF already at **95490MiB** vs UMA96GiB nominal98304MiB and previous IQ4 UB1024 ON/warmup failed at97130MiB. QSA ON alone added only ~152MiB in IQ3, but cannot extrapolate that as a guaranteed IQ4 peak. If user elects to pursue original IQ4 QSA ON, make one **isolated** test with same MH SHA, PP111137, UB512, warmup OFF, dual monitors, P-MODE unchanged and QSA active log, stopping on device lost, sustained clock depression/high memory; optional lower-context 64k pilot does not prove 128k safety. After that only compare same-QSA IQ3/IQ4 if it completes, and distinguish the earlier QSA OFF ratio. Do not relaunch old 12-case remaining runner. ROCm study remains closed.

## 2026-11-04 Vulkan b12032 MH IQ4 QSA ON/UB512 PASSED; ub1024 conditional plan

**New user raw archive** `evox2-vulkan-mh128k-iq4-qsa-on-ub512.zip`, **ZIP SHA256 `36453ed6b2045e4fcd20cf4f4545d79d408dac1b04111a736df3beb439c795ec`**, run `20261104-115012-829-bench-vulkan-b12032-ctx131072-b59b57493c09`. Verified unmodified original Unsloth IQ4_XS Ple16 model path/size, MH seed20261026 A source SHA `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`, Vulkan llama-bench b12032 `c4ddd239b` executable SHA `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, `-p111137 -c131072 -b2048 -ub512 -n0 -d0 -r1 -ctk/ctv f16 -fa auto -ngl999 -ncmoe0 --prompt-slice head --no-warmup`; QSA ON via `GGML_VK_QSA_UNION=1`, `MIN_KV=32768`, `qsa-union active` explicitly present in stderr, along with ineligible-operation fallback log. No reset/OOM/allocator/device-lost. `Status=OK,ExitCode=0,NativeRowCount=1`; **PP `260.986444 tok/s`**, native `avg_ns=425834378100`. P-MODE Performance direct probe at both ends, ADLX exit0, both ADLX and Windows resource monitoring active.

**ADLX** 232 samples; high GPU use>=95% **212 samples**; high-load VRAM clock **mean859.519MHz**, **median833MHz**, **min779MHz**, **169/212 below900MHz**; GPU core mean2855.632MHz, GPU mean power108.538W, max GPU temp79°C. The memory clock dropped after ~2 minutes, minute-aggregated 3–7min mostly around800–839MHz, despite normal completion. **ADLX `gpu_vram_mb` peak95657MiB**; high-load near peak ~95.4–95.6kMiB. **Windows resources.csv 230 samples:** process GPU total committed max**93.582GiB**, adapter total committed max**94.189GiB**, free physical RAM minimum**24.007GiB**, system committed max104.395 of limit127.647GiB; median page inputs/s0, large transient model-loading IO before PP. `BackgroundProbeStatus=PartialCoverage` (cannot exclude all background noise).

**Current same-build 2x2, fixed source and PP111137, UBatch512, NoWarmup, same backend and GGUF versions; each single run:** 
| Model | QSA OFF tok/s | QSA ON tok/s | QSA ON vs OFF | ADLX GPU memory OFF→ON | high-load VRAM-clock mean OFF→ON |
|---|---:|---:|---:|---:|---:|
| IQ3 | 248.367390 | 257.918782 | **+3.846%** | 84049→84201MiB | 995.30→835.34MHz |
| IQ4 | 249.836469 | **260.986444** | **+4.463%** | 95490→**95657MiB** | 999.15→**859.52MHz** |
Within QSA OFF original IQ4/IQ3 advantage **+0.592%**; within QSA ON IQ4/IQ3 advantage **+1.189%**. Both model QSA ON runs exhibit sustained VRAM-clock <900MHz and **both finish successfully**, so the prior simplistic clock-lower-than-900MHz STOP rule is overstrict: clock reduction alone is **not** proof of imminent TDR. It is an important speed/power confounder and signal to log, not a sufficient reject condition. QSA increases peak ADLX GPU memory **+167MiB** for IQ4 at UB512. Under the *nominal* 96GiB UMA label (=98304MiB), current 95657MiB leaves 2647MiB, but this arithmetic is **not a reliable free Vulkan allocator budget**.

**Prior failed b12032 IQ4 case** was ANLP126253/UB1024/QSA ON/warmup ON with peak ADLX GPU memory97130MiB and device lost, so current successful MH111137/UB512/NoWarmup case does **not** establish UB1024 safety. New user asks whether to check **Vulkan IQ3/IQ4 QSA ON UB1024**, motivated by a ROCm UB512→1024 quantized rank reversal. Risk judgment: higher than UB512 because bigger microbatches can alter memory allocation and prolonged different GPU power/clock profiles; exact incremental memory and TDR probability unknown, and ROCm's ~580MiB UBatch memory delta cannot be directly transferred to Vulkan. Still a bounded experiment is reasonable if user accepts a reboot risk, not an uncontrolled repeat of failed ANLP.

**Conservative staged plan:** first **IQ3 MH111137/UB1024/QSA ON/NoWarmup** single run with ADLX+Windows resource monitor, same b12032 binary/model/input SHA, inspect correctness, QSA activation, VRAM clock regime and GPU memory, no auto next case. Only after inspect run and user elects residual risk, one **IQ4 MH111137/UB1024/QSA ON/NoWarmup** test with same input and monitoring. Do not add warmup or repeat, don't change UMA/driver/GPU mode, don't restart old failed matrix. Preserve failed partial run logs and Windows 0x141 events if any. If IQ4 fails, conclude only that this bounded workload failed; do **not** claim UB1024 alone is proven cause relative to prior b12032 failure. If both pass, compare per-quantization UBatch shift within current QSA ON and ROCm (distinct backend, ROCm warmup ON), check high-use clock and memory before assigning algorithm cause.

## Deferred: independent Vulkan QSA UNION / VRAM-clock behavior investigation (2026-11-04)

**Status:** Deferred at the user's request while Vulkan MH-128K IQ3 QSA ON / UBatch1024 is already running. **No additional run or patch is authorized by this note.** Dedicated hardware/driver clock policy investigation, **not** part of PP speed-ranking experiment. Cross-link: [ROADMAP.md](ROADMAP.md).

### Evidence already measured; not causal proof

Windows Radeon 8060S / P-MODE Performance (direct start/end), same Vulkan b12032 `c4ddd239b`, MH-128K seed20261026 A, original Unsloth IQ3_XXS and IQ4_XS PLE16, native 111137 prompt tokens, context131072, `-b2048 -ub512 -fa auto -ctk/ctv f16 -ngl999 -ncmoe0 -r1 --no-warmup`, QSA threshold `GGML_VK_QSA_UNION_MIN_KV=32768`. Actual stderr QSA active confirmed for ON cases, no active path in OFF. Other MTP/Gather switches OFF. Single timed PP run per arm. ADLX high-load here means **GPU utilization >=95%**:

| Model | QSA OFF high-load VRAM avg / samples<900 | QSA ON high-load VRAM avg / samples<900 | PP OFF→ON tok/s | QSA ON memory extra (ADLX peak) |
|---|---|---|---|---|
| IQ3 | 995.3MHz / 0 of 222 | **835.3MHz / 171 of 214** | 248.37→257.92 | 84049→84201MiB |
| IQ4 original | 999.2MHz / 0 of 221 | **859.5MHz / 169 of 212** | 249.84→260.99 | 95490→95657MiB |

Both ON trials **finished cleanly**, despite sustained low VRAM clock; the old IQ4 ANLP126253 / UB1024 / warmup-ON device-lost event differs in several variables. Do not equate 900MHz crossing with a fatal GPU health limit. P-MODE Performance direct probes stayed Performance in both cases; lower QSA ON mean GPU power and increased GPU-core-clock behavior may be associated with driver dynamic performance policy, but do **not** infer firmware cause. Not a statistically controlled A/B yet; runs are chronological and RDP/physical display environment is a potential confounder.

### Later low-risk diagnostic protocol (not part of ongoing PP matrix)

1. **Start with IQ3 only**, so model GPU-memory footprint is much smaller than IQ4, and use a **64k-class real input** in a `-c65536` context with actual PP occupancy comfortably above the QSA activation threshold, e.g. existing **61,777 real tokens**, `-ub512 -b2048 -fa auto -ctk/ctv f16 -ngl999 -ncmoe0 -r1 --no-warmup`. Optional shorter ~48k may work, but **do not assume** a short context or `-c65536` automatically activates QSA: inspect `ggml_vulkan: qsa-union active` plus fallback logs for each ON run.
2. Hold actual Vulkan binary/DLL identity and SHA, driver/BIOS/UMA allocation, model GGUF, frozen input bytes/token IDs and PP length, temperature/power mode and RDP vs physical display state, system background tasks, sampling cadence, and all flags except `GGML_VK_QSA_UNION` constant. Do not change source, overclock, manually force VRAM clock or adjust firmware as part of this initial test.
3. Once the short IQ3 ON case is observed with matching high-load time windows, run small **alternating QSA OFF/ON pairs (e.g. ABBA)** rather than one chronological OFF then ON, with sufficient cooldown and recorded initial conditions. Preserve per-sample ADLX `gpu_vram_mb`, `gpu_vram_clock_mhz`, GPU clock/utilization, temperature/power, and Windows GPU committed/system RAM/page input and GPU reset events. Compare **clock-versus-PP-progress/time**, not just whole-run averages; split model load, start of prompt, sustained PP, tail/deallocation. Separate mean/median, <900MHz fraction, transition elapsed time and corresponding PP throughput; compare absolute watts/core clock to judge P-MODE/power-allocation differences.
4. If and only if an effect repeats with matched temperature/RDP/power across 64k, consider additional 32k/48k **after checking active-path eligibility** and/or IQ4 at lower PP/context with careful memory headroom review. IQ4 still has large weights and can occupy ~90GiB GPU memory even at lower context; **64k does not automatically mean safe**. A 64k negative result also **does not rule out** a 128k/KV-depth-specific driver or shader workload effect.
5. **Interpretation hypotheses, not findings:** QSA selected-row/mask-compact shader changes memory-vs-compute pressure and effective bandwidth utilization; Vulkan queue submissions and power policy; thermal/firmware or P-MODE / RDP state transitions; allocator/UMA budget; first-run graph compilation and warmup. Check whether a comparable **non-QSA Vulkan workload** triggers the same clock decline at similar power/GPU use. Use RGP narrowly only after reproducible correlation and with limited capture overhead; its absence is not a blocker for the first ADLX A/B.

**Success criterion:** a reproducible, per-sample QSA ON/OFF clock-regime difference at a **smaller safe-enough context**, without driver crash, that persists with matched conditions or a documented counterexample explaining the difference. Stop and preserve logs on device lost, hard memory pressure, GPU reset or unmanageable background interference. No calendar date set.

## 2026-11-04 Vulkan MH-128K IQ3 QSA-ON UB1024 measured PASS and IQ4 gate

**Latest user-provided raw ZIP audited:** `evox2-vulkan-mh128k-iq3-qsa-on-ub1024(1).zip`, run `20261104-120621-048-bench-vulkan-b12032-ctx131072-f87db00ec85c`, samples: `gpu-metrics.csv` **373** and Windows `resources.csv` **370**. The run **PASSED** (`Status=OK,ExitCode=0,RunException=null,ParseException=null,BackendDetected=Vulkan,NativeRowCount=1`). Exact Vulkan `llama-bench` b12032 `c4ddd239b`, EXE SHA256 `9ad4fa1220fb9241dfa6d5d1d694ec968edade16c9229f95ced3380d559298a`, **original Unsloth IQ3_XXS PLE16**, frozen MH seed20261026 A `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3`, file supplies 111137 raw tokens, head-sliced to same n_prompt 111137, `-c131072 -p111137 -n0 -d0 -r1 -b2048 -ub1024 -t4 -ngl999 -ncmoe0 -fa auto -ctk/ctv f16 --no-warmup --progress`. `GGML_VK_QSA_UNION=1`, threshold32768, stats0; stderr confirms `qsa-union active (r6), source=mask-compact, group=64, path=1, Br=16, Bc=64, groups=16, capacity=32768, min_kv=32768, scratch=81801472 bytes`, with a benign ineligible-path fallback preceding it. MTP/Gather OFF. Both direct P-MODE probes Performance and `PModeChanged=false`; mean high-load GPU power 99.665W is **Ambiguous** by ADLX heuristic and is **not** evidence the direct P-MODE changed. Named background processes show `PossibleNoise=false` but the monitoring does not exclude unmonitored activity.

**Measured PP:** `278.523246 tok/s`, `399022350000 ns` (399.02235s). Prior IQ3 QSA-ON UB512 `257.918782 tok/s`, `430.8992124s`; at same frozen input and all other flags, **UB512→UB1024 +7.9887% PP tok/s / -31.87686 seconds**. The analogous ROCm MH result IQ3 285.350153→319.116692 **+11.833%** was with warmup ON and a *different backend*. This Vulkan quant effect is an observed single-run result, not a stable variance estimate.

| Measured GPU/resource metrics | IQ3 Vulkan QSA-ON UB512 | **IQ3 Vulkan QSA-ON UB1024** | Note |
|---|---:|---:|---|
| ADLX gpu_vram_mb peak MiB | 84201 | **85554** | **+1353MiB** allocated, far greater than ROCm's approx+589MiB for this IQ3 input |
| Windows process GPU total committed max GiB | 82.261 | **83.627** | +1.366GiB |
| Windows adapter GPU total committed max GiB | 82.858 | **84.230** | +1.372GiB |
| Windows physical free RAM min GiB | 24.644 | **24.169** | Both have relatively stable free physical RAM |
| Windows system committed peak / 127.647 GiB limit | 92.884 | **94.314** | No sustained limit |
| High GPU use >=95% samples | 214 | **197** | Measured 2s ADLX |
| High-load VRAM clock mean / median / min MHz | 835.34 / 804 / 747 | **805.25 / 777 / 708** | Further ~30MHz decrease in mean |
| High-use VRAM clock below900MHz | 171/214 | **160/197** | **~81%** low-clock period |
| High-load GPU core mean MHz | 2882.60 | **2881.54** | Essentially same |
| High-load GPU power mean W | 104.64 | **99.665** | Lower; not a confirmed P-MODE switch |
| GPU temp peak C | 78 | **78** | No high-temperature escalation |
| ADLX / resource samples | 302/300 | **373/370** | More wall time in UB1024 run due to model load or scheduling, do not compare total wrapper runtime |

Minute-grouped ADLX high-use VRAM-clock after run start: 6m ~971MHz, 7m ~792MHz, 8m ~765MHz, 9m ~780MHz, 10m ~769MHz, 11m ~750MHz, and 12m ~749MHz. High-use phase begins ~5m after wrapper start because model load dominates early elapsed time. `gpu_vram_mb` peak was **85554MiB** at 12:18:02 JST, with high GPU utilization; process completed cleanly. `PagesInput_PerSec` median0, huge transient read early during GGUF loading, no sustained paging evident.

**Important safety finding for still-unrun IQ4-ON UB1024:** IQ4-ON UB512 previously peaked **95657MiB ADLX** and old b12032 IQ4 ANLP126253/UB1024/QSA-ON/warmup-ON failed with peak **97130MiB ADLX**. **Illustrative, non-predictive arithmetic:** if IQ4's ADLX memory increase matched IQ3's measured +1353MiB, it would approach **97010MiB**, **120MiB below the prior failed-run peak**. This is **NOT an exact allocation forecast**, **not a known crash threshold**, and ADLX total GPU MiB must **not be subtracted from nominal UMA as a precise Vulkan memory budget**; model-specific scratch/KV, token length and first/second pass may differ. Nonetheless it strengthens caution: **IQ4 UB1024 is materially higher risk than IQ3 UB1024 and IQ4 UB512**, and may trigger a driver reset even with no warmup and 111137 rather than126253 prompt tokens. User has previously expressed willingness to accept a one-off reboot risk. If opting in: single isolated `-ub1024` IQ4 original MH/111137 same QSA-ON and `--no-warmup`, both ADLX and Windows resource monitor, no background GPU activity, no automatic retry, preserve failed logs and Windows LiveKernelEvent if any, stop/reboot on driver issues. A shorter prompt/context can be safer for independent diagnostics but is **not** the same controlled MH-128K PP speed comparison. Defer the independent 64k QSA ON vs VRAM-clock ABBA hypothesis as already tracked in ROADMAP.
