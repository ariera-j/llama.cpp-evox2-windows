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
