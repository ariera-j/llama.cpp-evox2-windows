# r6 / b11908 Evo-X2 integrated source checkpoint — 2026-10-29

**Proposed public tag:** `evox2-integrated-2026-10-29` (annotated tag to be created at the final `main` publication commit). This is a **source checkpoint with bounded validation**, not an assertion of full router-mode/server/vision compatibility or a new upstream release.

## What was integrated

- Upstream inference base: b11870, `74bca3950054eed1795f525cb9cf06bfe796492d`.
- Verified compiled implementation source: b11908, `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`. All subsequent Git commits changing docs, benchmark plans and README **did not rebuild/revalidate inference binaries**. The eventual public tag will have the same inference source tree for the validated paths, plus newer documentation.
- Hardware: GMKtec NucBox EVO-X2 / Radeon 8060S (gfx1151), Windows 11, UMA 96 GiB; ROCm TheRock SDK/runtime 10.0.0 staged separately from the Vulkan build.
- Included compatible functions: PLE16 loader, ROCmFP4 FAST PLE16 Vulkan quant/shader ops, MTP Draft compatibility. Five independent opt-in speed flags: Vulkan QSA-union (f16 KV), common MTP DENSE, NOOP, Stage-B, flatten. All five **default OFF in source**.
- Selected test models: Qwen3.8 IQ3 Original/PLE16, Agention ROCmFP4 FAST PLE16 (Vulkan), Unsloth and huihui IQ4_XS PLE16 (Vulkan), Gemma4 31B and 26B A4B (Vulkan). Weights and sidecar models are not distributed.

## Evidence status

- **S8 G8-0–G8-6:** passed within documented scopes (backend build identity, selected native backend tests, short model output, Vulkan MTP state/continuation checks, same-binary PP/TG A/B, selective 256k and traditional `llama-server`/Jinja/tokenizer tests).
- **S9 G9-0–G9-4:** scoped IQ4/huihui and Gemma4 text-only checks completed. Gemma4 31B/26B 32k text run passed allocation/full-GPU/truncation and bounded output checks; the old b10919 fallback remains recommended for rollback.
- **G8-3 original A/B:** six archived ZIPs, 22 individual runs. **S9 gap-fill 21 runs** plus **one separate ROCm five-flag 64k CLI smoke** ended with exit0 and intact input. Archives and SHA256 IDs are listed in the [measurements](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md).
- **Vulkan IQ3 PLE16 MTP ON:** 64k 358.29 PP / 33.90 TG; 128k 322.98 / 30.49; 256k 301.30 / 25.08 tokens/s under *five flags ON (experimental profile)*.
- **ROCm IQ3 PLE16 MTP ON:** 64k 371.43 PP / 28.63 TG; 128k 282.24 / 22.64; 256k 184.79 / 15.04 tokens/s with *only DENSE + NOOP ON*.
- These are measured profiles with uneven repetition; not standard universal performance figures or isolated patch gains. The [README](../../README.md) places the r6 clean upstream Original/MTP-OFF comparison alongside these numbers with the layout and MTP differences clearly called out.

## Verified build provenance (no binaries attached by this publication step)

| Artifact | Vulkan b11908 SHA256 | ROCm b11908 SHA256 |
| --- | --- | --- |
| `llama-cli.exe` | `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a` | `1bbd4a5102b6181d8de92faf2d42e49f96ba2ad4b04b7c7f9e6aafc168d322b1` |
| `llama-server.exe` | `89b575891366cd5d697686c84ef78ff09127088a6330d86b64da73f6b73d3615` | `9187ebec46825efc88a98644581ee6b856f30472b6a99671f95b237459ec9c82` |
| `llama-tokenize.exe` | `a85e803bf30c1385ddb35ed24dda8f4a732608050c59c2cad24a2d876cc9cea8` | `0333a9c90825729866241510b9a2970f6bdbe733331a83c63eeb0c6953c56581` |

Preserve these two independently verified backend directories and the build manifests. The Git tag identifies **source**; it is not a container of those exe/DLL files or an assertion that the binaries were rebuilt from the docs/tag commit. The exact measured source remains the b11908 SHA above.

## Flag support, risk boundaries, and what is NOT approved

- Vulkan QSA union, DENSE, NOOP: opt-in in the [tested model/shape/profile scope](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md). Stage-B and flatten: working lab samples but **numerical Draft K/V state parity DEFER**, therefore no globally supported five-flag-on preset.
- ROCm DENSE+NOOP: selected CLI/MTP-on opt-in PASS. ROCm's all-five-flag environment CLI 64k single smoke PASS does **not** establish general S7 numerical parity, and Vulkan QSA-union does not apply to HIP.
- **G9-5 `llama-server` router mode**, built-in WebUI/Open WebUI model switching, and **ROCm MTP-ON server**: not yet tested, explicitly deferred by user. Traditional `llama-server` MTP-OFF/ON cases do not cover router reload or cross-model memory lifetime.
- Gemma4 vision/projector and finished long-form response are not validated; Gemma4 64k/128k and ROCm HIP FP4 GPU kernels are out of scope.
- This fork does not bundle GGUFs or propose global environment variable settings. Existing binary fallbacks remain; do not run broad Windows/gfx1151 `FLASH_ATTN_EXT` backend tests.

## Project next steps

1. Complete the later real-use router-mode check with llama.cpp WebUI and Open WebUI, separate from this source checkpoint.
2. Profile ROCm long-context PP/TG under matched controls at 128k/256k, with possible HIP attention/QSA/host bottlenecks treated as **hypotheses**, not proven causes.
3. Preserve r5 baseline and individual r5 experimental branch histories. New experiments branch from this frozen checkpoint, not by amending the public tag.

For complete details: [S8 combined results](R6-S8-COMBINED-RESULTS-2026-10-28.md), [S9 IQ4](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md), [S9 Gemma4](R6-S9-GEMMA4-G9-4-RESULTS-2026-10-29.md), [speed inventory](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md), [integration registry](INTEGRATED-RELEASES.md).
