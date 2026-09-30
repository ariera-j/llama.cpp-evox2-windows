# llama.cpp for Evo-X2 on Windows

Experimental Windows-focused downstream of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) for the GMKtec Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S (`gfx1151`).

The current `r3` work is intentionally **upstream-first**. It starts from an exact upstream baseline and reintroduces Evo-X2-specific changes one patch at a time, with Vulkan and ROCm measured from the same source revision.

## Current r3 baseline

- Upstream base: llama.cpp `b11247`
- Commit: `0bc845d356f437d5ce4fe975c36428f7522829cb`
- Windows Vulkan: LLVM/Clang 20.1.8 + Vulkan SDK 1.4.357.0
- Windows ROCm: ROCm 10.0.0 / TheRock + Clang 23.0.0
- ROCm host toolchain: Visual Studio 2022 Build Tools / MSVC 14.44
- GPU target: Radeon 8060S / `gfx1151`
- Primary long-context baseline: Qwen3.8-Flash-Next UD-IQ3_XXS, 65,536 context, MTP off

At the 61,789-token input used for the current 64k baseline:

| Build | PP | TG |
|---|---:|---:|
| self-built b11247 Vulkan | 265.10 tok/s | 16.75 tok/s |
| self-built b11247 ROCm | 359.84 tok/s | 14.50 tok/s |
| official b11243 ROCm reference, 2-run average | 358.42 tok/s | 14.42 tok/s |

These numbers are machine- and workload-specific. They are recorded as regression baselines, not as general performance claims.

## r3 goals

The r3 series keeps one upstream-based source tree and uses separate build directories for Vulkan and ROCm.

Current execution priority:

1. COMMON-001 PLE16 loader support - validated
2. COMMON-004 incremental pooled-key cache - next implementation target
3. selected post-b11247 upstream changes - isolated A/B only
4. VULKAN-002 QSA grouped-union - re-evaluate after COMMON-004
5. COMMON-002 Unsloth MTP compatibility
6. COMMON-003 / VULKAN-001 ROCmFPx work only where still required
7. ROCM-001 only when a demonstrated ROCm-specific need exists

The earlier MTP-QSA prototype remains outside the initial patch stack until the
main QSA decode cost and ordinary MTP behavior are better characterized.

The b11247 upstream base is intentionally kept fixed during the current
COMMON-004 and Vulkan A/B sequence. A full upstream refresh is reconsidered at
explicit checkpoints rather than performed continuously.

Each patch is expected to be buildable, testable, and benchmarkable on its own.
See [ROADMAP.md](docs/evox2/ROADMAP.md) for the current execution order and
upstream-refresh policy.

## Documentation

- [Evo-X2 r3 overview](docs/evox2/README.md)
- [Current optimization roadmap](docs/evox2/ROADMAP.md)
- [Baseline and validation record](docs/evox2/BASELINE.md)
- [Windows Vulkan build](docs/evox2/BUILD-VULKAN-WINDOWS.md)
- [Windows ROCm build](docs/evox2/BUILD-ROCM-WINDOWS.md)
- [Benchmarking methodology](docs/evox2/BENCHMARKING.md)
- [Patch registry](docs/evox2/PATCHES.md)

Upstream documentation under `docs/` is retained unless a downstream-specific change requires otherwise. Older r1/r2 Evo-X2 notes may remain in this repository as historical records; they are not r3 instructions.

## Tools

Evo-X2-specific scripts live under `tools/evox2`.

The r3 tooling is being reorganized around separate build, benchmark, model-conversion, and experiment-specific layers. Machine-specific model paths, prompts, and raw benchmark logs are not intended to be committed.

## Scope

This repository is primarily for:

- Windows Vulkan and ROCm experiments on Strix Halo
- long-context Qwen3.8-Flash-Next inference
- reproducible A/B testing of downstream patches
- documenting the Windows-specific build and runtime details needed to reproduce the experiments

It is not a replacement for upstream llama.cpp documentation and does not imply upstream support for these downstream changes.

## Attribution and license

This work is based on [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp). Earlier r1/r2 work also used code and ideas from [LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp) and other sources recorded in the historical Evo-X2 documentation.

The existing [MIT license](LICENSE) and source notices are retained. Model weights are subject to their own licenses.
