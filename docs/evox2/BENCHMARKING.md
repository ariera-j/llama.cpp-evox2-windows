# Benchmarking methodology

## Goal

The Evo-X2 benchmark tooling is intended for regression testing and A/B comparison of llama.cpp builds and downstream patches.

The primary rule is simple:

> Change one meaningful variable at a time and record enough metadata to reproduce the run.

Reusable scripts are under `tools/evox2/benchmark/`. The r4 clean plan is
`configs/qwen38-r4-clean.psd1`; r3 plans are retained as historical definitions.

## Primary long-context workload

Historical r3 clean 64k workload (same input/settings are reused for r4):

```text
model: Qwen3.8-Flash-Next UD-IQ3_XXS
model variant: original Unsloth split GGUF
context requested: 65,536
actual prompt tokens: 61,789
MTP: off
K/V cache: f16/f16
batch: 2,048
ubatch: 1,024
threads: 4
GPU layers: 999
generation limit: 1,024
prompt cache: disabled
```

The input file used for this baseline is:

```text
nlp-survey-ch3-d7-b1.txt
```

Input data exists for additional 32k, 96k, 128k, and 256k experiments. Those runs should record actual prompt-token counts rather than relying on filenames alone.

## Metrics

At minimum, record:

```text
PP: prompt-processing throughput in tokens/second
TG: token-generation throughput in tokens/second
prompt tokens
generated tokens
prompt eval time
generation eval time
total time
```

For resource measurements, also record relevant memory and process-level data when available.

## Required metadata

Every benchmark result should identify:

- source commit
- llama.cpp build number if available
- backend
- compiler/toolchain
- executable path
- executable SHA-256 when practical
- model path
- model size or hash when practical
- input path
- input SHA-256 when practical
- requested context
- actual context
- actual prompt-token count
- KV cache type
- batch and ubatch
- MTP/speculative-decoding state
- relevant backend environment variables
- manual UMA/VRAM test-condition label
- start and finish timestamps
- exit status
- log path

Do not encode facts in filenames that were not actually detected or supplied. For example, a run must not be named `Vulkan` or `PLE16` merely because an older script had those words hard-coded.

## Backend identification

The benchmark log should capture the device lines emitted by llama.cpp.

Examples:

```text
Vulkan0: ...
ROCm0: AMD Radeon(TM) 8060S Graphics ...
```

The benchmark wrapper should also accept an explicit backend label so that filenames and summary CSVs remain correct.

## Warm-up and caches

Unless an experiment is specifically about cache behavior:

- keep prompt-cache behavior constant
- do not mix cached and uncached runs in one comparison
- record whether llama.cpp model warm-up is enabled
- record context-checkpoint settings when they can affect behavior or memory

If a script disables a cache, record that explicitly.

## Repetition

For small expected differences, use repeated runs and an order that reduces drift.

Examples:

```text
A B B A
```

or a balanced multi-run sequence.

For large structural comparisons, one run may be enough for an initial screen, but it should not be treated as a precise percentage claim until repeated.

## TG caveat

TG can be affected by:

- generated-token count
- output content
- sampler settings
- speculative decoding acceptance
- context length
- backend-specific decode behavior

A comparison using different generated-token counts is still useful as a practical run record, but it should not be presented as a tightly controlled microbenchmark.

## Resource monitoring

`Monitor-LlamaProcess.ps1` is shared by the CLI and bench wrappers.

Preferred behavior:

1. attach to a specific PID when possible
2. fall back to process-name matching only when necessary
3. record the monitored executable path and PID
4. sample CPU, committed memory, working set, and GPU-related counters available on the machine
5. keep resource logs separate from llama.cpp stdout/stderr logs
6. avoid silently aggregating unrelated simultaneous `llama-cli` processes

## Benchmark matrix runner

`Invoke-BenchmarkMatrix.ps1` keeps experiment definitions separate from execution code.

Preferred structure:

```text
tools/evox2/benchmark/
├─ Invoke-BenchmarkMatrix.ps1
└─ configs/
   ├─ local.example.psd1
   ├─ qwen38-baseline.psd1
   ├─ qwen38-longctx.psd1
   └─ qwen38-r4-clean.psd1
```

PowerShell data files (`.psd1`) are preferred for local benchmark matrices because they support comments and native PowerShell arrays while remaining declarative.

Machine-specific paths should live in a local configuration file that is ignored by Git, with a committed example file documenting the expected keys.

## Historical r3 accepted 64k baseline

| Build | PP | TG |
|---|---:|---:|
| self-built b11247 Vulkan | 265.10 tok/s | 16.75 tok/s |
| self-built b11247 ROCm | 359.84 tok/s | 14.50 tok/s |

Reference only:

| Build | PP | TG |
|---|---:|---:|
| official b11243 ROCm, 2-run average | 358.42 tok/s | 14.42 tok/s |

See [R3-BASELINE.md](R3-BASELINE.md) for the historical context. The r4 plan uses
the original joined model, not the PLE16-converted model; record this layout
condition when comparing against r3 COMMON-004/005. All r4 results remain
pending in [BASELINE.md](BASELINE.md).
