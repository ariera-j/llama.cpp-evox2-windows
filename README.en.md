# llama.cpp Evo-X2 Windows fork

**A research fork for local LLM inference and performance experiments on Windows 11, GMKtec NucBox EVO-X2, and AMD Radeon 8060S (gfx1151).**

Based on [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp), this fork investigates Qwen3.8-Flash-Next PLE16 compatibility, long-context Vulkan and ROCm inference, and MTP (speculative decoding) optimizations.

**[日本語版 README](README.md)** · [Original upstream README](README.upstream.md) · [Source checkpoint tag](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/evox2-integrated-2026-10-29)

> **r6 integration checkpoint, October 29, 2026 (based on llama.cpp b11908).** Bounded S8/S9 checks were completed on the Windows machine described below. This is a research and reproducibility checkpoint, **not a universally supported stable distribution or a performance guarantee**. All five optional speed switches default to **OFF** in the source. A subsequent Vulkan router / Open WebUI 3-model test passed within its 35-response scope; numeric Draft K/V state parity remains unverified.

[Build instructions](tools/evox2/build/README.md) · [Full benchmark inventory](docs/evox2/R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md) · [Patch registry](docs/evox2/PATCHES.md) · [Integration checkpoint records](docs/evox2/INTEGRATED-RELEASES.md)

## Prebuilt Windows Vulkan binary (experimental Pre-release)

**[GitHub Release: Evo-X2 r6 b11908 Vulkan Experimental Preview](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/tag/evox2-integrated-2026-10-29)**

- **[Windows Vulkan ZIP (~34.1 MiB)](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/download/evox2-integrated-2026-10-29/llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip)** · [ZIP SHA256 checksum file](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/download/evox2-integrated-2026-10-29/llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip.sha256)
- Platform: **Windows x64 / Vulkan**. Tested on Windows 11 with a GMKtec NucBox EVO-X2 and AMD Radeon 8060S (gfx1151). **No ROCm/HIP binaries are included**.
- Contents: `llama-cli.exe`, `llama-server.exe`, `llama-bench.exe`, `llama-tokenize.exe`, Vulkan/CPU backend DLLs, license notices and checksum files. **GGUF model weights and MTP Draft sidecars are not included.**
- The executable build is **b11908**, measured source commit `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`. The annotated `evox2-integrated-2026-10-29` tag is a **source checkpoint** containing later documentation; it does not mean the binary was rebuilt from the tagged documentation commit.

Extract to a **new standalone directory**, without mixing EXEs/DLLs from another llama.cpp build. In PowerShell, assuming the ZIP is in the current directory:

```powershell
$zip = '.\llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip'
$expected = '8e68dd4de9f5eccdf454ba33705a9da18ad252fecb4ed55144915c24d56775b6'
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'ZIP SHA256 mismatch' }

Expand-Archive -LiteralPath $zip -DestinationPath '.\evox2-vulkan-preview'
Set-Location '.\evox2-vulkan-preview\llama.cpp-evox2-b11908-win-vulkan-preview-v2'
.\llama-cli.exe --version
.\llama-cli.exe --list-devices
.\llama-server.exe --version
```

Check that `--list-devices` shows a `Vulkan0` device. A compatible AMD Vulkan driver and required Windows/VC++ runtimes are needed. **The built-in WebUI is not included** (`LLAMA_BUILD_UI=OFF` at build time); the CLI and API server are included. **Vulkan router mode and switching three models through Open WebUI passed a bounded [35-response test](docs/evox2/R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md).** Image correctness and long-term stability remain unvalidated. A separate [ROCm MTP-ON router 3-model / 16-response smoke test](docs/evox2/R6-S9-GATE5-ROCM-ROUTER-RESULTS-2026-10-29.md) also passed within its bounded scope, excluding one oversized Web-search request; **ROCm binaries are not in the public ZIP**. All five optional speed flags default to **OFF**. Consult the [flag decision sheet](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md) and [Release limitations](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/tag/evox2-integrated-2026-10-29) before changing per-process settings.

## What this fork adds

| Feature | Purpose and validation scope |
| --- | --- |
| PLE16 / GGUF | Compatibility for Unsloth Qwen3.8-Flash-Next split-PLE16 GGUF (COMMON-001). [Conversion and verification](tools/evox2/model/README.md) |
| ROCmFP4 / Vulkan | Support for Agention ROCmFP4 FAST PLE16 data layout and Vulkan GPU operations. **This is not ROCm/HIP FP4 GPU-kernel support.** |
| Vulkan QSA-union | Long-context prompt-processing optimization for f16 KV. Opt in with `GGML_VK_QSA_UNION=1`; tested eligibility includes `GGML_VK_QSA_UNION_MIN_KV=32768`. |
| MTP DENSE / NOOP | Avoid unnecessary Draft indexing and Target invalidation on eligible Qwen4Exp paths. Opt-in only for validated model/backend conditions. |
| Stage-B / flatten | Experimental Draft KV-only prefill and `mtp_eh_proj` flattening. **Numeric Draft K/V parity has not been established.** Lab-only opt-in, not a recommended default profile. |
| Build and measurement tooling | Separate Vulkan/ROCm builds, TheRock runtime provenance, ADLX/P-MODE monitoring, benchmark plans and SHA-based records. Added [Vulkan preflight/CMake pin](tools/evox2/build/README.md) and [Windows background-activity evidence](tools/evox2/benchmark/BACKGROUND-ACTIVITY-MONITORING.md) (pending Windows rerun verification). |

For backend-specific restrictions and the difference between tested and deferred flags, consult the [supported flag decision sheet](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md).

## Benchmarks: Qwen3.8-Flash-Next on EVO-X2

**PP** = prompt processing, **TG** = token generation. Both are measured in **tokens per second**.

| Backend | Real input | r6 clean upstream PP / TG | r6 integrated PP / TG |
| --- | ---: | ---: | ---: |
| Vulkan | 64k | 339.72 / 25.42 | **358.29 / 33.90** |
| Vulkan | 128k | 268.60 / 23.54 | **322.98 / 30.49** |
| Vulkan | 256k | 228.89 / 20.30 | **301.30 / 25.08** |
| ROCm | 64k | 405.24 / 21.86 | **371.43 / 28.63** |
| ROCm | 128k | 303.66 / 17.50 | **282.24 / 22.64** |
| ROCm | 256k | 200.59 / 12.55 | **184.79 / 15.04** |

**Experimental conditions and important caveat:** GMKtec NucBox EVO-X2; AMD Radeon 8060S; Windows 11; **96 GiB UMA**; Performance P-MODE; f16 KV; all model layers offloaded to the GPU. Real document prompt sizes were **61,789 / 126,253 / 255,181** tokens for the 64k / 128k / 256k cases.

The **r6 clean upstream** column uses b11875 (same inference source as upstream b11870), **IQ3 Original joined-PLE GGUF, MTP OFF**. The **integrated** column uses b11908 (measured source SHA `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`), **IQ3 split PLE16 GGUF, MTP ON**. The integrated Vulkan profile had **all five optional flags ON for research**; the integrated ROCm profile used **DENSE + NOOP only**. These are **operational configuration comparisons**, not isolated patch speedups: the model layout and MTP state also differ. Samples were not all collected with equal repetition; the 256k values are representative single runs. **Do not interpret the five-flag Vulkan benchmark configuration as a generally recommended preset.**

Same-binary opt-in ON/OFF comparisons, the additional 21-run speed matrix, a separate manual ROCm five-flag-on CLI stability smoke, caveats, and raw artifact SHA256 values are in the [detailed measurements](docs/evox2/R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md). The next optimization priority is **long-context ROCm PP and TG at 128k–256k**.

## Models and configurations exercised

| Model | Verified scope (not general support) |
| --- | --- |
| Unsloth Qwen3.8 UD-IQ3_XXS Original / PLE16 | Vulkan and ROCm CLI; MTP OFF/ON; representative 64k/128k/256k real inputs. Traditional Vulkan MTP-ON `llama-server` short chat, multi-turn and one real 64k test were checked separately. |
| Agention ROCmFP4 FAST PLE16 | **Vulkan** 4k/16k and real 64k/128k input with scoped MTP tests; not ROCm HIP FP4 kernels. |
| Unsloth / huihui UD-IQ4_XS PLE16 | **Vulkan** 4k/16k startup, real 64k and selected 128k tests, and bounded MH-128K retrieval regressions. |
| Gemma4 31B QAT Q4_0 / Gemma4 26B A4B QAT | **Vulkan** 4k/16k startup/output and a real 32k text input. The older b10919 binaries are retained as fallback. |

No GGUF model weights or Draft sidecars are included. See the [S9 model runbook](docs/evox2/R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md) and [Gemma4 verification report](docs/evox2/R6-S9-GEMMA4-G9-4-RESULTS-2026-10-29.md) for precise conditions.

## Building and running

To use this fork's patches, either download the **verified experimental Vulkan ZIP** above or **build from this repository**. Build from source for ROCm and configurations not included in the preview ZIP. Official upstream llama.cpp installers and binaries do not contain these downstream patches.

- [Windows Vulkan build guide](docs/evox2/BUILD-VULKAN-WINDOWS.md)
- [Windows ROCm build guide](docs/evox2/BUILD-ROCM-WINDOWS.md)
- [EVO-X2 PowerShell build tools](tools/evox2/build/README.md), [benchmark scripts and plan configurations](tools/evox2/benchmark/configs/)
- [PLE16 conversion tools](tools/evox2/model/README.md), [validated flag profiles](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md)

Set optimization flags **per backend and per process**. Avoid permanent `setx` configuration or letting Vulkan-specific settings silently propagate to the ROCm process. The examples below are *conservative opt-in candidates*; they are **not** the all-five-on research benchmark profile.

**Vulkan IQ3 PLE16 / f16 KV / eligible MTP path:**

```powershell
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_MIN_KV = '32768'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
```

**ROCm IQ3 PLE16 / MTP ON (validated in CLI only; server deferred):**

```powershell
$env:GGML_VK_QSA_UNION = '0'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
```

See the [G8-6 server runbook](docs/evox2/R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md) for model/Draft arguments, context, KV settings and scoped server verification. **All five optional switches default to OFF in source.**

## Known limitations and deferred checks

- **Vulkan `llama-server` router mode with Open WebUI:** scoped PASS for Gemma4 31B, Gemma4 26B and Qwen3.8 IQ3 PLE16 (**35/35 responses completed**), including serial child unload/load. [G9-5 report](docs/evox2/R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md). Built-in WebUI was disabled at build time; Qwen image-position warnings (24) and long-term GPU/UMA memory recovery remain open.
- **ROCm MTP-ON `llama-server`** is untested. ROCm MTP-ON CLI and ROCm MTP-OFF server tests passed separately.
- **Numeric Draft K/V state parity** for Stage-B/flatten is pending. All-five-flag-on is not approved as a universal preset.
- ROCm generation can vary even with the same seed. Gemma4 vision/projector, complete long-answer generation and contexts beyond the tested scope are not approved.
- Avoid the broad `FLASH_ATTN_EXT` backend test suite previously associated with Windows/gfx1151 issues.
- Do not generalize these measurements to other machines, model quantizations or input corpora.

## Upstream attribution and license

This is an **unofficial fork** of [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp). The upstream README from the forked snapshot is preserved as [README.upstream.md](README.upstream.md), and upstream maintains the latest general documentation. Statements about downstream patches and speed measurements are **not official upstream claims**. Source code is distributed under the [MIT License](LICENSE); verify third-party model terms separately.
