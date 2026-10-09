# llama.cpp for Evo-X2 on Windows

Experimental Windows downstream of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) for the GMKtec Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S (`gfx1151`).

The active refresh identity is recorded in [CURRENT-REFRESH.json](docs/evox2/CURRENT-REFRESH.json). Each refresh starts from an exact upstream commit and carries forward downstream documentation and build/measurement tooling. Inference changes are reconsidered individually after a clean Vulkan/ROCm baseline.

## Current work

r5 starts from upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b` and imports documentation/tooling from the r4 checkpoint `bddf73442c24545879c9acadc078ba5b2c3cb7d8`. Windows builds, load checks and PP/TG validation are pending. Imported r3/r4 results are historical references, not r5 results.

Start with the Original Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS model, joined PLE tensor layout, MTP OFF and f16 KV. Use the existing first GGUF shard; physically joining GGUF files is not required.

## Documentation and tools

- [Refresh handoff and current validation gates](docs/evox2/R5-REFRESH-2026-10-09.md)
- [Repeatable upstream refresh procedure](docs/evox2/UPSTREAM-REFRESH.md)
- [Evo-X2 overview](docs/evox2/README.md)
- [Optimization roadmap](docs/evox2/ROADMAP.md)
- [Baseline record](docs/evox2/BASELINE.md)
- [Windows Vulkan build](docs/evox2/BUILD-VULKAN-WINDOWS.md)
- [Windows ROCm build](docs/evox2/BUILD-ROCM-WINDOWS.md)
- [Benchmarking methodology](docs/evox2/BENCHMARKING.md)
- [Patch registry](docs/evox2/PATCHES.md)
- [Preserved r4 checkpoint](docs/evox2/R4-CHECKPOINT-2026-10-09.md)

Scripts are under `tools/evox2`. The version-independent clean plan is `tools/evox2/benchmark/configs/qwen38-clean.psd1`; its `CleanVulkan` / `CleanROCm` aliases point to new binaries in the current worktree. Private model/input paths, `local.psd1` and raw benchmark logs stay local.

Use the existing toolchains for the first comparison: Vulkan LLVM/Clang 20.1.8 + SDK 1.4.357.0; ROCm 10.0 / TheRock + Clang 23.0.0 with VS2022/MSVC 14.44, `gfx1151`. These are previous working conditions, not a claim that r5 has been built.

## Repository policy

Upstream inference and build source are retained. Upstream instruction files, including `AGENTS.md`, are retained as well; its opening note explicitly excludes work in another repository or fork from its upstream contribution rules. Evo-X2 procedures live in `docs/evox2` and `tools/evox2`.

Upstream GitHub workflows are retained with a `.disabled` suffix, continuing the downstream policy of avoiding automatic upstream CI in this experimentation repository. Build/runtime validation is performed on the Evo-X2.

The same source revision is used for Vulkan and ROCm. Compiler, SDK, driver, input and model-format differences must be recorded as measurement conditions.

## Attribution and license

Based on [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp). Earlier work also used [LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp) and sources recorded in the historical documents. The existing [MIT license](LICENSE) and source notices are retained; model weights have their own licenses.
