# llama.cpp for Evo-X2 on Windows

Windows Vulkan experiments for Qwen3.8-Flash-Next on the GMKtec Evo-X2 (Ryzen AI Max+ 395 / Radeon 8060S, 128 GB unified memory).

**[Windows build, model conversion and benchmark instructions (Japanese)](docs/evox2/README-ja.md)**

This repository starts from [LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp) at `5e085d123eead2e89b5c19f824fccb05727da6a2`, with selected upstream backports documented in [the r1 manifest](docs/evox2/backport-r1/manifest.json). It is not a full merge of current upstream. [README-source-fork.md](README-source-fork.md) retains the source fork's README and its separate Linux results.

## Current baseline

- The inference changes are the same r1 patch tested on Windows on 2026-09-16.
- The source fork's ROCmFPx formats, PLE16 support and MTP implementation are retained.
- The Unsloth conversion tool splits the joined PLE table into 16 tensors without requantizing the weights. The converted model completed the recorded 96 GB GPU-allocation tests.
- Measured settings: 65,536 context, 61,789 prompt tokens, f16 K/V cache, batch 2,048, ubatch 1,024, one conversation, MTP off, LLVM 20.1.8 and Vulkan SDK 1.4.357.0.
- 128k/256k, MTP and new sparse-prefill changes still need validation in this Windows setup. The fastest compiler/configuration has not been established.

Conversion and benchmark scripts are in [tools/evox2](tools/evox2). Model weights, private prompts and raw inference logs are not included. Inherited GitHub Actions definitions have a `.disabled` suffix because they assume the source project's runners, schedules and release setup. No downstream CI result is implied.

## Attribution and license

This work builds on [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), [LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp), and the authors of the changes listed in the r1 manifest. ROCmFPx attribution is preserved in [ggml/rocmfpx](ggml/rocmfpx).

The existing [MIT license](LICENSE) and source notices are retained. Model weights have their own licenses. AI assistance was used for backport selection/adaptation, scripts and documentation; the Windows measurements were performed by the repository owner.
