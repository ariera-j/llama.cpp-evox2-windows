# Gemma 4 31B Vulkan PP: isolated upstream #31323 port (2026-11-21)

## Scope and provenance

- Branch: `investigation/gemma4-v1-fa31323-20261121`
- Parent: `investigation/strata-pp-v1.0.0-20261115` at `934a6574780035863ffa1903d3449f3505ac1f93`.
- True inference baseline: upstream `v1.0.0` commit `b1b770d90d94cad9e9ea5b993bdbc383a522fb28`; its successor on the research branch contains only EVO-X2 docs/tooling and `.gitignore`, no engine edits.
- Ported [upstream PR #31323](https://github.com/ggml-org/llama.cpp/pull/31323), merge `d8f30a5b6db907110b6f8d67c2f84c1443b871ef`, on 2026-11-14: RDNA3/RDNA4 cooperative-matrix Flash Attention PP optimization, larger Q tiles on UMA, Q register reuse, and the new flipped-FA shader.
- Included [upstream PR #32415](https://github.com/ggml-org/llama.cpp/pull/32415), merge `8f647f1fdb0c3bf72bf36e23641da2a28cea993f`, on 2026-11-17: **disable flipped FA on AMD proprietary Windows Vulkan driver** (driver compiler issue). This is a one-condition guard inside the #31323 shader selection code; it leaves the improved existing coopmat1 PP path enabled.
- No unrelated upstream commits, Strata changes, Qwen-specific patches, experimental GEMM work, or Gemma 4 model changes were brought over.

## Files and exact port procedure

The upstream #31323 unified diff applies **without context adaptations** to the true v1.0.0 research branch in all eight pre-existing files. Added `flash_attn_cm1_flip.comp` (441 lines) as the ninth file. Then added only the #32415 `eAmdProprietary` check. The nine inference files are:

1. `ggml/src/ggml-vulkan/ggml-vulkan-common.h`
2. `ggml/src/ggml-vulkan/ggml-vulkan-types.h`
3. `ggml/src/ggml-vulkan/ggml-vulkan.cpp` (also #32415 guard)
4. `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn.comp`
5. `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_base.glsl`
6. `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_cm1.comp`
7. `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_cm1_flip.comp` (added)
8. `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_cm2.comp`
9. `ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp`

Git API port preserves the baseline ancestry and changes only these files. Unlike a merge of current upstream, this isolates the effects of #31323 in a reproducible older-core build.

## What this A/B can and cannot establish

Compare this branch to its **actual parent commit**, using new Vulkan builds with the same compiler, Vulkan SDK and build options. A performance improvement supports #31323 as a major cause of b12600's Vulkan PP improvement. It does not rule out smaller later upstream changes, and the Windows proprietary driver makes flipped-FA unselectable by default. `GGML_VK_DISABLE_FA_FLIP` disables only flip, **not** the existing coopmat1 optimization; it is not an OFF switch for the whole PR. **Do not use `GGML_VK_FORCE_FA_FLIP` on this Windows driver**. If desired, use a separate compile-time ablation of the 32-Q-row tile and Q-in-register changes only after the full-PR result.

Reference benchmark: [Gemma4 Stage A 8run on b12600](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-b12600-stagea-8run-and-release-diff.md).
Historical same-core Vulkan b12363 29,379-token paper PP: 63.56 tok/s; official b12600 Vulkan Stage A 2run mean: 170.11 tok/s, ROCm 192.99 tok/s. These are historical references, **not measured results of this port**.

## Build and validation on EVO-X2

This branch has **not** been compiled or run by the GitHub-side port. Build in a separate worktree; do not overwrite the clean v1 benchmark binary or r6 build:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git fetch origin
git worktree add 'C:\llama-build\llama.cpp-evox2-v1-fa31323' origin/investigation/gemma4-v1-fa31323-20261121
Set-Location 'C:\llama-build\llama.cpp-evox2-v1-fa31323'

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir '.\build-vulkan-fa31323' `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

Adjust the worktree root, SDK and LLVM path to the EVO-X2 installation. Before benchmarking, verify `llama-cli.exe --version`, `--list-devices`, the build manifest, detected `Vulkan0` and fully GPU-resident 61/61 model layers. Use the same model GGUF, 217-token Japanese short and 29,379-token paper input, `-c 4096/32768 -b 2048 -ub 512 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -fit on --cache-ram 0 --jinja --single-turn --spec-type none --ctx-checkpoints 0t --seed 1234 --temp 0.2 --top-p 0.8 --reasoning off`.

Suggested order: original clean-v1 32k one run -> patched-v1 32k one run -> patched-v1 32k second run only if needed. Keep P-MODE, UMA, active GPU workload, driver/compiler and cooldown controlled. For diagnosis, collect progress checkpoints at 8192, 16384, 24576 and 28672 tokens and compare the last 2048-token effective speed. If the improvement is reproduced, proceed to RGP and identify the actual coopmat1 FA shader path for SWA256 and global512.

## Validation status

- Source review: #31323 patch matches all eight original target files on the *correct* true-v1 research base; #32415 guard added.
- Pending: Windows compiler + shader build, Vulkan device smoke, short/32k model run, PP/TG benchmark, and RGP source attribution.
- Never commit generated logs with source papers or model outputs to the public repo; store only safe aggregate metrics and command/commit hashes.

## EVO-X2 validation result (2026-11-21, first 32k run)

**Windows Vulkan build and 32k inference are now verified**, superseding the pending statements above.

- Clean source commit `1da79f0689c4a963fbd032dea109e1ca015c44bc`; build `12364`; Clang20.1.8; `BuildIdentity=Verified`, runtime manifest `Verified`; Vulkan0 Radeon 8060S.
- Run ID `20261121-132547-424-cli-vulkan-b12364-ctx32768-398319325e76`, `Status=OK`, exit 0; 61/61 GPU layers, F16 KV, `ubatch=512`, exact paper input SHA `1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601`, actual 29,379 prompt and 512 generated tokens, UMA64GB and Performance P-MODE.
- PP: **170.11 tok/s**, **172.704 seconds**. Old v1 b12363 same-input Vulkan PP 63.56 tok/s and 462.256 seconds; official b12600 two-run mean 170.105 tok/s and 172.713 seconds. Isolated port improved PP by **2.68x** and saves **289.55 seconds**, matching official b12600 closely.
- Last full 2,048-token PP interval through cumulative 28,672: old v1 37.79 tok/s -> port **114.93** tok/s; official b12600 second run 114.86. The shape of the entire cumulative PP curve is consistent with b12600.
- TG: **8.92 tok/s**, effectively unchanged from old v1. ADLX telemetry: ~99.67% mean PP GPU use, ~2,827 MHz, ~104 W (steady middle-window) and P-MODE unchanged.
- Interpretation: **#31323 with Windows #32415 is sufficient to reproduce nearly all observed b12600 Vulkan 32k PP improvement for this experiment.** The AMD proprietary driver safeguard disables flipped FA by default; the optimized original CM1 FA path is the leading explanation. Actual shader selection and per-kernel GPU timing remain unmeasured. One ported run so far; repeat once or inspect RGP before asserting individual kernel attribution.

[Full private-experiment aggregate report (no raw prompt or model output)](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-fa31323-port-32k-validation.md).

## Matched 2-run revalidation (2026-11-21, 13:43–13:56 JST)

Both original v1.0.0 Vulkan and the isolated #31323 + #32415 Vulkan build were re-measured **in sequence with exactly identical model/input identity, CLI arguments, relevant environment and hardware settings**. Binary and runtime artifact identities were independently verified; both `Status=OK`, exit 0, Clang 20.1.8, UMA64GB, Performance P-MODE, 61/61 GPU offload.

| New sequential A/B: Japanese paper 29,379 prompt tokens | PP tok/s | PP seconds | TG tok/s |
| --- | ---: | ---: | ---: |
| Original v1 b12363 (executable `934a65747`) | 64.34 | 456.59479 | 8.92 |
| Isolated FA port b12364 (executable `1da79f068`) | **170.83** | **171.97459** | 8.92 |

The port yields **2.655x** PP throughput, with **284.62 seconds less PP time**. The last full 2,048-token native-progress interval (cumulative 28,672 prompt tokens) improved **37.99 → 116.56 tok/s** (~3.07x). Previous independent original-v1 and port values (63.56 → 170.11 tok/s) agree. Official unmodified b12600 Vulkan (169.79 and 170.42) corroborates the improvement scale. Both ADLX monitors completed normally; GPU use remained ~99.7–99.8% in estimated PP middle windows. No indication of a P-MODE transition or sustained UMA exhaustion.

**Conclusion:** #31323, with the required AMD Windows guard #32415, reproduces virtually the full b12600 32k PP gain for Gemma 4 31B QAT. This is replicated in **two original-v1 and two isolated-port runs**. It is strong *package-level* evidence, but not yet per-shader GPU attribution; the flipped shader is disabled for proprietary AMD Windows drivers. No further whole-prompt A/B repetition is needed solely for confirmation. For mechanisms, profile existing coopmat1 FA variants with RGP at matched early/late ubatches, or isolate the 32-Q-row-tile and Q-register caching subfeatures.

[Detailed aggregate 2-run validation (private experimental repository)](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/gemma4-31b-pp-tg-20261115/runs/2026-11-21-v1-fa31323-matched-2run-revalidation.md).
