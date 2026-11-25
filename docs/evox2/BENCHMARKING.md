# Benchmarking methodology

## Scope

This page records the historical long-context workload, metrics and baseline references. Follow the [EVO-X2 benchmark rules](automation/BENCHMARK-RULES.md) for tool selection, run design, warmup, metadata, monitoring, and result storage. The [tooling README](../../tools/evox2/README.md) documents wrapper arguments and Matrix examples.

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

## TG caveat

TG can be affected by:

- generated-token count
- output content
- sampler settings
- speculative decoding acceptance
- context length
- backend-specific decode behavior

A comparison using different generated-token counts is still useful as a practical run record, but it should not be presented as a tightly controlled microbenchmark.

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


## Historical P-MODE and ADLX calibration

On the target Evo-X2, P-MODE materially affected long-context PP in the 2026-10-15 calibration. The [calibration record](R5-ADLX-PMODE-VALIDATION-2026-10-15.md) gives the sample criteria and power bands used for supplementary warnings. For current collection rules and the approved read-only path, see the [benchmark rules](automation/BENCHMARK-RULES.md) and [P-MODE probe procedure](automation/PMODE-PROBE.md).
