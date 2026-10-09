# r5 VULKAN-002 grouped-union selective port — implementation / validation handoff

Recorded: 2026-10-09 JST. **Source implementation only. No Windows build or GPU execution verification yet.**
Branch: `r5/upstream-refresh-20261009`; pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`; COMMON-001+bench Phase A already accepted on Evo-X2.
Source donor: [r4 `5814fbe99e9249e8ac2c4c2e9b977c05735b0912`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/5814fbe99e9249e8ac2c4c2e9b977c05735b0912).

## Commits and exact scope

- Native selective port: [`b3d050492b1282feb1ea15aa682cf7d8a57f74b2`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/b3d050492b1282feb1ea15aa682cf7d8a57f74b2), **14 source/test/shader files**. r4 donor source-hunks matched the current r5 exact context except two `ggml-vulkan-types.h` struct insertions, which were adapted to r5's removed legacy MoE/GET_ROWS fields. The unrelated r4 GPU-info log hunk was deliberately omitted. Two original r4 QSA compute shaders were added. Activation log changed from `(r4)` to `(r5)`.
- Compatibility/test follow-up: [`0a3cf6a0e771feb7990d31748cbbf432681b055f`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/0a3cf6a0e771feb7990d31748cbbf432681b055f). Adds explicit `QSA grouped-union = on/off` initialization log and updates existing `tools/evox2/benchmark/Test-QsaUnion.ps1` to expect `qsa-union active (r5)`. Removes obsolete GET_ROWS diagnostic environment controls from that test script.
- New r5 code passes **source patch-context and structural checks only**. This is not equivalent to compiling or passing the 18 native CPU-reference cases; the user must run both.

## Design constraints retained

- Keep r5 `ggml_lightning_indexer()` fused score calculation, upstream pooled-key paths, newer sparse Flash Attention and quantized-KV/coopmat2 handling. We add propagation only for the **final KV cell IDs after dump-row remapping**, not initial pool IDs.
- The `ggml_flash_attn_ext` source 5 metadata is optional; the original graph/mask and all non-Vulkan backends keep their normal result path.
- `GGML_VK_QSA_UNION=1` opt-in (**default OFF**) and `GGML_VK_QSA_UNION_MIN_KV=32768` initially. 64-query groups. Only supported F16 K/V, F16 mask, compatible shapes/capabilities; single-query decode, multi-stream and unsupported formats fall back. The original r5 FA sparse flag 16 remains separate from dynamic count flag 32.
- Historical r4 MoE legacy tile/GET_ROWS 128x4 control code is **not** restored. The current pinned r5 upstream has the per-expert MoE tile revert. Do not use r4-specific environment variables to recreate an outdated combination.
- Phase C `GGML_VK_QSA_UNION_STATS` remains **unimplemented**. Do not enable or expect QSA union CSV yet.

## Windows build gate — DO THIS BEFORE SPEED MEASUREMENT

After `git pull --ff-only`, build a **new** Vulkan binary directory so that Phase A (b11526) and COMMON-001 (b11521) binaries remain available:

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r5

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-qsa-union `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

$bin = '.\build-vulkan-qsa-union\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\llama-bench.exe" --help
Test-Path "$bin\test-backend-ops.exe"
```

The build script configures `-DLLAMA_BUILD_TESTS=ON` and includes the `test-backend-ops` target. The new source should also retain the Phase A llama-bench `--prompt-file`, `--prompt-slice`, and `--ctx-size` options. All tested Windows compiler/shader generation errors are new evidence to be investigated; no compilation claim is made here.

## Targeted CPU-reference correctness gate (OFF and ON)

```powershell
.\tools\evox2\benchmark\Test-QsaUnion.ps1 `
  -BinDir .\build-vulkan-qsa-union\bin\Release `
  -Backend Vulkan0
```

The test wrapper runs **18/18 `FLASH_ATTN_EXT` CPU-reference cases for OFF and 18/18 for ON**, checks zero exits, no skips, `QSA grouped-union = off/on` log, and for ON verifies actual `qsa-union active (r5)` **and** an expected shape/threshold fallback. It writes `results.json` plus per-mode stdout/stderr logs under `evox2-logs`. These tests cover representative 2/63/64/65/349/1024 queries, high/dump IDs, mask behavior and unsupported inputs; they cannot establish universal GPU correctness.

If a test fails, attach `results.json`, `off.stdout.log`, `off.stderr.log`, `on.stdout.log`, `on.stderr.log`, and the build error if relevant. **Do not start 64k performance tests or Phase C statistics before this gate passes.**

## Optional short runtime check, then 64k

After the 18-case gate, register a local ignored build key pointing to `build-vulkan-qsa-union\bin\Release`; run an Original or PLE16 short llama-cli allocation/inference with `GGML_VK_QSA_UNION=0`, then same with `=1`. At a 256-token context, both take the fallback path because KV is below 32768; this is expected and **cannot prove grouped-union active**.

For the first real activation, use an existing **64k** real-input plan with the new Vulkan build, f16 K/V, MTP OFF. Compare same executable and same prompt/model with union OFF/ON; preserve existing non-union environment and do not re-enable retired MoE/GET_ROWS switches. Record `qsa-union active (r5)`, fallback and PP/TG, binary/source hashes, and model/input IDs. A small 64k single-pair sanity test is sufficient before a longer ABBA plan; 128k/256k remain follow-up, time permitting. **Only stats-disabled runs represent normal PP speed.**

## Next

1. Windows Vulkan compile and targeted 18x2 OFF/ON reference gate; fix if necessary.
2. Normal 64k Vulkan Original/PLE16 same-binary OFF/ON check, then r5 128k/256k as resources/time allow.
3. Phase C port the stats-branch opt-in `GGML_VK_QSA_UNION_STATS` feature into the validated r5 union backend as a separate commit, followed by STATS=0 regression check and STATS=1 CSV evidence.
4. Optional comparison inputs: English document and non-repeating Japanese document, initially single run each (not an acceptance blocker). [Staged plan](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md).

No runtime/benchmark result is claimed for VULKAN-002 on r5 at the time of this record.
