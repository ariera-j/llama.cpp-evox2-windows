# llama.cpp for Evo-X2 on Windows

Experimental Windows-focused downstream of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) for the GMKtec Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S (`gfx1151`).

The current `r4` work is intentionally **upstream-first**. It starts from an exact upstream baseline and reintroduces Evo-X2-specific changes one patch at a time, with Vulkan and ROCm measured from the same source revision.

## Current r4 baseline

- Development branch: `r4/upstream-refresh-20261002`
- Upstream base: llama.cpp `b11352`
- Commit: `bed0a856606ee4a24a164066f73d2379447033f5`
- Windows Vulkan: LLVM/Clang 20.1.8 + Vulkan SDK 1.4.357.0
- Windows ROCm: ROCm 10.0.0 / TheRock + Clang 23.0.0
- ROCm host toolchain: Visual Studio 2022 Build Tools / MSVC 14.44
- GPU target: Radeon 8060S / `gfx1151`
- The r4 clean Vulkan/ROCm baseline has not been measured yet.

Imported docs/tooling come from the frozen r3 checkpoint
`0a93fcbb8e5bcf51b331275c4f4b142d822168d6`; downstream inference patches are
not imported. The current plan is `tools/evox2/benchmark/configs/qwen38-r4-clean.psd1`.

## Previous validated r3 baseline

- Upstream base: llama.cpp `b11247`
- Commit: `0bc845d356f437d5ce4fe975c36428f7522829cb`
- Windows Vulkan: LLVM/Clang 20.1.8 + Vulkan SDK 1.4.357.0
- Windows ROCm: ROCm 10.0.0 / TheRock + Clang 23.0.0
- ROCm host toolchain: Visual Studio 2022 Build Tools / MSVC 14.44
- GPU target: Radeon 8060S / `gfx1151`
- Primary long-context baseline: Qwen3.8-Flash-Next UD-IQ3_XXS, 65,536 context, MTP off

At the 61,789-token input used for the historical clean r3 64k baseline:

| Build | PP | TG |
|---|---:|---:|
| self-built b11247 Vulkan | 265.10 tok/s | 16.75 tok/s |
| self-built b11247 ROCm | 359.84 tok/s | 14.50 tok/s |
| official b11243 ROCm reference, 2-run average | 358.42 tok/s | 14.42 tok/s |

These numbers are machine- and workload-specific. They are recorded as regression baselines, not as general performance claims.

## Documentation

- [Evo-X2 r4 overview](docs/evox2/README.md)
- [Current optimization roadmap](docs/evox2/ROADMAP.md)
- [Baseline and validation record](docs/evox2/BASELINE.md)
- [Windows Vulkan build](docs/evox2/BUILD-VULKAN-WINDOWS.md)
- [Windows ROCm build](docs/evox2/BUILD-ROCM-WINDOWS.md)
- [Benchmarking methodology](docs/evox2/BENCHMARKING.md)
- [Patch registry](docs/evox2/PATCHES.md)

Upstream documentation under `docs/` is retained unless a downstream-specific change requires otherwise. Older r1/r2/3 Evo-X2 notes may remain in this repository as historical records; they are not r4 instructions.

## Tools

Evo-X2-specific scripts live under `tools/evox2`.

Machine-specific model paths, prompts, and raw benchmark logs are not intended to be committed.

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
