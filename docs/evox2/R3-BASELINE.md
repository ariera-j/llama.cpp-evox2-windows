# r3 baseline and validation record

## Purpose

This document defines the clean r3 starting point before downstream inference patches are applied.

The baseline is deliberately boring: exact upstream source, reproducible Windows builds, runtime validation, and a known long-context workload.

## Source baseline

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
commit title: vulkan : reuse descriptor sets when bindings are constant (#29280)
```

No r2 QSA patch, PLE16 loader patch, Unsloth MTP compatibility patch, or MTP-QSA prototype is part of this baseline.

## Primary model and workload

Model:

```text
Qwen3.8-Flash-Next
Unsloth GGUF
UD-IQ3_XXS
original split GGUF, not the PLE16-converted file
MTP: off
```

Primary 64k input:

```text
nlp-survey-ch3-d7-b1.txt
actual prompt tokens: 61,789
requested context: 65,536
```

Common inference settings:

```text
n_gpu_layers: 999
threads: 4
batch: 2048
ubatch: 1024
K cache: f16
V cache: f16
flash attention: enabled
context: 65536
generation limit: 1024
prompt cache: disabled
MTP/speculative decoding: disabled
```

The benchmark harness may also set sampling and single-turn options. Performance comparisons should preserve the same workload and relevant CLI settings.

## Vulkan baseline

Build:

```text
source: b11247 / 0bc845d35
compiler: LLVM/Clang 20.1.8
Vulkan SDK: 1.4.357.0
build directory: build-vulkan-b11247
```

64k result:

```text
PP: 265.10 tok/s
TG: 16.75 tok/s
```

Observed model buffers:

```text
CPU:         27465.95 MiB
Vulkan:      50191.11 MiB
Vulkan_Host:   497.31 MiB
```

This result is close to the tested official b11243 Vulkan package and is accepted as the self-built Vulkan r3 baseline.

## ROCm baseline

Build:

```text
source: b11247 / 0bc845d35
ROCm: 10.0.0 / TheRock
compiler: Clang 23.0.0
host toolchain: VS2022 / MSVC 14.44
GPU target: gfx1151
build directory: build-rocm-b11247
```

Device discovery after installing the correct ROCm runtime DLLs beside the executables:

```text
ROCm0: AMD Radeon(TM) 8060S Graphics (110456 MiB, 110301 MiB free)
```

Backend validation:

```text
FLASH_ATTN_EXT
3982/3982 tests passed
Backend ROCm0: OK
```

64k result:

```text
prompt tokens: 61,789
generated tokens: 553
PP: 359.84 tok/s
TG: 14.50 tok/s
prompt eval time: 171711.21 ms
eval time: 38079.02 ms
total time: 209790.23 ms
```

ROCm memory breakdown at the end of the run:

```text
total:   110456 MiB
free:     55341 MiB
self:     53132 MiB
model:    50191 MiB
context:   1840 MiB
compute:   1100 MiB
```

## Reference results

The following values are reference points, not part of the self-built b11247 baseline:

| Build | PP | TG |
|---|---:|---:|
| official b11243 ROCm, 2-run average | 358.42 tok/s | 14.42 tok/s |
| self-built b11247 ROCm | 359.84 tok/s | 14.50 tok/s |
| self-built b11247 Vulkan | 265.10 tok/s | 16.75 tok/s |

The b11247 ROCm result is effectively in line with the tested official ROCm package on this workload.

The backend comparison also reproduces the previously observed machine-specific pattern: ROCm is substantially faster for long prompt processing, while Vulkan is faster for token generation on this model and configuration.

## Baseline acceptance criteria

A new build is suitable as an r3 comparison baseline when all of the following are true:

1. `llama-cli --version` reports the intended source revision and compiler.
2. `llama-cli --list-devices` reports the intended GPU with a plausible memory size.
3. backend tests required for the experiment pass.
4. the target model loads without backend/runtime errors.
5. the long-context workload completes without truncation or crash.
6. the log records the actual context, prompt-token count, PP, TG, build identity, model path, and backend.
7. no unrelated downstream patch is mixed into the candidate being measured.

## Known caveats

- TG is sensitive to generated-token count and output content. Compare like-for-like runs when possible.
- The 96 GB UMA label is a manual test-condition label.
- A single PP/TG number is not a universal backend ranking.
- Windows driver, firmware, background activity, thermals, and memory pressure can affect results.
- r3 patch work should be measured against this clean baseline before multiple changes are combined.
