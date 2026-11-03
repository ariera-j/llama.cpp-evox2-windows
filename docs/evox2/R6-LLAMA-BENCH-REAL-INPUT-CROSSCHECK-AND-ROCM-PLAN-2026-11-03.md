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
