# r3 downstream patch registry

## Purpose

r3 applies downstream changes in small units on top of one exact upstream baseline.

This file is the human-readable patch registry. It should answer:

- what the patch changes
- why it exists
- which backend it affects
- whether it is currently applied
- how it is validated
- what performance effect was measured

Patch IDs are stable documentation identifiers. They do not need to match Git commit hashes.

## Base

```text
BASE-000
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
status: validated
```

Validation is recorded in [BASELINE.md](BASELINE.md).

## Registry

| ID | Scope | Status | Purpose |
|---|---|---|---|
| COMMON-001 | common | validated | PLE16 model loading support |
| COMMON-002 | common | planned | Unsloth MTP compatibility |
| COMMON-003 | common | evaluate | ROCmFPx format/core support only if still required by target models |
| VULKAN-001 | Vulkan | evaluate | ROCmFPx Vulkan kernels only if still required |
| VULKAN-002 | Vulkan | evaluate | QSA grouped-union optimization if current upstream still benefits |
| ROCM-001 | ROCm | none yet | reserved for a demonstrated ROCm-specific requirement |

`planned` means the feature is expected to be ported.

`evaluate` means the feature existed or was relevant in earlier work, but r3 will first verify whether current upstream still needs it.

## COMMON-001 - PLE16 loader

Status:

```text
validated
```

Base:

```text
upstream build: b11247
upstream commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

Goal:

Support the PLE16 layout used by the converted Unsloth Qwen3.8-Flash-Next model while preserving support for the original joined PLE layout.

Source/history:

```text
LaurentZuijdwijk/llama.cpp
bf9e0a2ace3b86f77950e5516f351110baa37f5d
qwen4exp: store the n-gram table one tensor per head
```

The historical conversion uses:

```text
gguf-py/gguf/scripts/gguf_split_ple_heads.py
```

The conversion splits the combined PLE n-gram table into per-head tensors without dequantizing or requantizing the model weights. The converter remains external and is not vendored into this repository.

Changed files:

```text
src/llama-arch.h
src/llama-arch.cpp
src/models/models.h
src/models/qwen4exp.cpp
```

Behavior:

- the original joined `per_layer_token_embd.weight` layout remains supported
- the loader auto-detects the split `ple_ngram_embd.N.weight` layout
- when the joined tensor is absent, all 16 split PLE head tensors are required
- split-head row indices are converted to each head's local vocabulary range before `get_rows`
- the per-head results are concatenated back to the layout expected by the qwen4exp graph

Runtime controls:

```text
none
```

Correctness validation:

- original joined model allocation/load: Vulkan OK, ROCm OK
- PLE16 model allocation/load: Vulkan OK, ROCm OK
- 64k real-input inference: Vulkan OK, ROCm OK
- 128k real-input inference with PLE16: Vulkan OK, ROCm OK
- 256k real-input inference with PLE16: Vulkan OK, ROCm OK
- no extreme long-context slowdown, allocation failure, or crash was observed through 256k

Benchmark workload:

- Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS
- PLE16 conversion for split-layout runs
- MTP off
- f16 K/V cache
- batch 2048, ubatch 1024
- 4 CPU threads
- all model layers offloaded where supported
- Flash Attention enabled
- 1024-token generation budget
- temperature 0.2, top_p 0.8

Measured results:

| Backend | Model | Context | PP (tok/s) | TG (tok/s) |
|---|---|---:|---:|---:|
| Vulkan | original joined | 64k | 266.23 | 16.96 |
| Vulkan | PLE16 | 64k | 267.90 | 17.20 |
| ROCm | original joined | 64k | 357.84 | 14.55 |
| ROCm | PLE16 | 64k | 357.93 | 14.86 |
| Vulkan | PLE16 | 128k | 159.56 | 12.00 |
| ROCm | PLE16 | 128k | 259.41 | 9.91 |
| Vulkan | PLE16 | 256k | 103.75 | 7.30 |
| ROCm | PLE16 | 256k | 167.35 | 5.74 |

Interpretation:

- at 64k, PLE16 has only a small performance effect relative to the original joined model
- the primary purpose of COMMON-001 is reliable loading and execution of the split PLE layout, especially at long context
- PLE16 completed the 128k and 256k validation runs on both Vulkan and ROCm without the extreme slowdown or crash behavior that motivated the split layout
- long-context PP/TG still decreases with context depth; this is treated as a separate performance-optimization topic rather than a COMMON-001 correctness issue

Known limitations:

- the PLE16 conversion utility is external to this patch
- COMMON-001 does not include MTP compatibility, MTP-QSA, grouped-union QSA, or ROCmFPx support
- ROCm and Vulkan place the model buffers differently; this patch does not attempt to normalize backend-specific placement

Upstream interaction:

The patch is intentionally limited to qwen4exp PLE tensor naming, loading, and graph assembly so that later upstream changes can be compared or dropped independently.

## COMMON-002 - Unsloth MTP compatibility

Status:

```text
planned
```

Goal:

Load and run the Unsloth MTP draft model used in the earlier Evo-X2 tests.

The r2 work required compatibility handling beyond the clean upstream baseline. r3 should port only the minimum compatibility change needed by the current upstream source.

Validation plan:

- draft model allocation succeeds
- short-context generation succeeds
- MTP acceptance statistics are reported
- compare MTP on/off at a short context where TG is the primary metric
- separately measure long-context PP overhead

Do not combine this patch with MTP-QSA work.

## COMMON-003 - ROCmFPx format/core support

Status:

```text
evaluate
```

Earlier work used ROCmFP4-FAST model variants from AgentionAI.

Before porting format/core changes, verify exactly what current upstream b11247 already supports and what the target model still requires.

Only missing functionality should be carried forward.

## VULKAN-001 - ROCmFPx Vulkan kernels

Status:

```text
evaluate
```

Port only if the target ROCmFPx model requires downstream Vulkan kernel support after COMMON-003 evaluation.

Keep format/core support and Vulkan kernel support as separate reviewable changes where practical.

## VULKAN-002 - QSA grouped-union

Status:

```text
evaluate
```

Earlier r2 measurements showed a large long-context prefill benefit from a grouped-union QSA path.

r3 must not assume the old patch is still optimal because the new base already contains newer upstream Vulkan/QSA changes.

Before porting:

1. measure current upstream behavior at 128k and 256k
2. identify whether the same bottleneck remains
3. port only the required grouped-union delta
4. validate correctness before benchmarking

Historical r2 results are useful references but are not r3 baseline values.

## MTP-QSA prototype

The earlier MTP-QSA prototype is intentionally outside the initial r3 patch stack.

It should only be reconsidered after:

- COMMON-002 is stable
- normal MTP on/off measurements are complete
- current upstream QSA behavior is understood
- a separate performance case justifies the added complexity

## Patch documentation template

Add a section for every patch that reaches implementation status.

Recommended fields:

```text
ID:
scope:
status:
base commit:
purpose:
source/history:
changed files:
build requirements:
runtime controls:
correctness validation:
benchmark workload:
benchmark result:
known limitations:
upstream interaction:
```

## Commit discipline

A patch should not be marked `validated` merely because it compiles.

For this project, validation normally means:

1. targeted build succeeds
2. relevant backend test succeeds
3. target model loads
4. target workload completes
5. result is compared to the immediately preceding baseline
6. logs are retained outside Git when they are too large or machine-specific
