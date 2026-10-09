# r5 VULKAN-002 grouped-union selective port — implementation / validation handoff

Recorded: 2026-10-09 JST. **Windows Vulkan build and 18-case-per-mode GPU correctness smoke ACCEPTED. Actual model 64k OFF/ON speed and quality have not been measured on this VULKAN-002 binary.**
Branch: `r5/upstream-refresh-20261009`; pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`; COMMON-001+bench Phase A already accepted on Evo-X2.
Source donor: [r4 `5814fbe99e9249e8ac2c4c2e9b977c05735b0912`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/5814fbe99e9249e8ac2c4c2e9b977c05735b0912).

## Commits and exact scope

- Native selective port: [`b3d050492b1282feb1ea15aa682cf7d8a57f74b2`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/b3d050492b1282feb1ea15aa682cf7d8a57f74b2), **14 source/test/shader files**. r4 donor source-hunks matched the current r5 exact context except two `ggml-vulkan-types.h` struct insertions, which were adapted to r5's removed legacy MoE/GET_ROWS fields. The unrelated r4 GPU-info log hunk was deliberately omitted. Two original r4 QSA compute shaders were added. Activation log changed from `(r4)` to `(r5)`.
- Compatibility/test follow-up: [`0a3cf6a0e771feb7990d31748cbbf432681b055f`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/0a3cf6a0e771feb7990d31748cbbf432681b055f). Adds explicit `QSA grouped-union = on/off` initialization log and updates existing `tools/evox2/benchmark/Test-QsaUnion.ps1` to expect `qsa-union active (r5)`. Removes obsolete GET_ROWS diagnostic environment controls from that test script.
- New r5 code passed strict patch-context checks, and **the user-provided Windows Vulkan0 GPU correctness gate subsequently passed 18/18 OFF and 18/18 ON**. See actual evidence below. Model-specific 64k activation/performance remains pending.

## Design constraints retained

- Keep r5 `ggml_lightning_indexer()` fused score calculation, upstream pooled-key paths, newer sparse Flash Attention and quantized-KV/coopmat2 handling. We add propagation only for the **final KV cell IDs after dump-row remapping**, not initial pool IDs.
- The `ggml_flash_attn_ext` source 5 metadata is optional; the original graph/mask and all non-Vulkan backends keep their normal result path.
- `GGML_VK_QSA_UNION=1` opt-in (**default OFF**) and `GGML_VK_QSA_UNION_MIN_KV=32768` initially. 64-query groups. Only supported F16 K/V, F16 mask, compatible shapes/capabilities; single-query decode, multi-stream and unsupported formats fall back. The original r5 FA sparse flag 16 remains separate from dynamic count flag 32.
- Historical r4 MoE legacy tile/GET_ROWS 128x4 control code is **not** restored. The current pinned r5 upstream has the per-expert MoE tile revert. Do not use r4-specific environment variables to recreate an outdated combination.
- Phase C `GGML_VK_QSA_UNION_STATS` **source implementation has been selectively ported** in commit `37ba95673a061c1b4c0991e8eeea5eb003bbe898`. **Do not yet assume it compiles or produces valid CSV on r5**; see [Phase C Windows handoff](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md). Use a new build directory, never overwrite the accepted b11530 binary.

## Windows build gate — COMPLETED (commands retained for reproducibility)

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

## Targeted CPU-reference correctness gate (OFF and ON) — COMPLETED

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

1. **Completed:** Windows Vulkan compile and targeted 18x2 OFF/ON CPU-reference gate, 2026-10-09, attached ZIP below.
2. Normal 64k Vulkan Original/PLE16 same-binary OFF/ON check, then r5 128k/256k as resources/time allow.
3. **Phase C source port committed**. Next build a separate stats-enabled r5 binary; compare STATS=0 against the preserved b11530 64k results and validate STATS=1 CSV, zero drop count and opt-in behavior. [Implementation handoff](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md).
4. Optional comparison inputs: English document and non-repeating Japanese document, initially single run each (not an acceptance blocker). [Staged plan](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md).

**Validation scope at phase B:** native targeted Vulkan correctness accepted. Subsequent 64k PLE16 model PP/TG sanity is recorded below. Phase C stats source port is present, but its new Windows build/CSV and STATS=0 regression are untested.

## Actual Windows Vulkan correctness result — 2026-10-09 (Evo-X2)

User-submitted archive (retained locally, not committed): `20261009-191137-742-qsa-union-tests.zip`; directory `20261009-191137-742-qsa-union-tests/`. Includes `results.json`, `off/on.stdout.log`, `off/on.stderr.log`. It does **not** include a build manifest; the exact source checkout and compiler identity must be obtained from a manifest or CLI `--version` if needed, rather than inferred from a ZIP filename.

- Binary: `C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-qsa-union\bin\Release\test-backend-ops.exe`
- Executable SHA256: `8710862824bc7f953dd9d9182806f8b1bb7ec175c038f78b0f146ebda650cc72`
- Backend: `Vulkan0`, AMD Radeon(TM) 8060S Graphics (AMD proprietary driver, UMA).
- Arguments: `-b "Vulkan0" -o FLASH_ATTN_EXT -p "qsa_union=1"`.
- OFF: `GGML_VK_QSA_UNION=0`, explicit `QSA grouped-union = off (group=64, min_kv=32768)`; 18/18 native test cases **OK**, ExitCode=0, no unsupported cases, no union activation.
- ON: `GGML_VK_QSA_UNION=1`, explicit `QSA grouped-union = on (group=64, min_kv=32768)`; 18/18 native test cases **OK**, ExitCode=0, no unsupported cases. Activation shown: `qsa-union active (r5), group=64, bitmap=16KiB, path=1, Br=16, Bc=64, f32acc=1, groups=1, capacity=256, min_kv=32768, scratch=98384 bytes`. Fallback shown: `qsa-union fallback: query count or KV threshold`.
- `test-backend-ops` prints `Backend 2/2: CPU / Skipping`; this does **not** mean any of the 18 Vulkan0 test cases was skipped. CPU reference comparisons are performed by the harness when evaluating Vulkan0.
- Coverage includes Q=2/63/64/65/349/1024, high-KV positions (131073 and 262144), varied head dimensions, hints, decode-style 1-query, threshold below min, and unsupported shapes/bias/sinks/types. The full output lists 18/18 for each mode and the script's `Passed=true` for both.
- Interpretation: no skip/fatal/incorrect GPU cases in this targeted fixture, correct opt-in routing and fallback. It is **not** a measurement of long-prompt Qwen3.8 PP or text quality.

**Next runnable matrix plan:** [`configs/qwen38-r5-qsa-union.psd1`](../../tools/evox2/benchmark/configs/qwen38-r5-qsa-union.psd1) defines 64k PLE16 OFF/ON two-run sanity as `sanity64k`, 64k Original+PLE16 ABBA as `normal64k`, and optional 128k/256k PLE16 ABBA as `longctx`. For a single unattended execution, [`qwen38-r5-qsa-union-batch.psd1`](../../tools/evox2/benchmark/configs/qwen38-r5-qsa-union-batch.psd1) selects only PLE16 128k OFF/ON, PLE16 256k OFF/ON, then Original and PLE16 64k OFF/ON/ON/OFF (**12 runs, with no repeat at 128k or 256k**). The matrix stops at the first non-OK run (`ContinueOnError=$false`). Use `-PlanOnly` before starting. This second plan is a workload scheduling artifact; no new GPU validation/performance is claimed. Register `R5QsaUnionVulkan` under ignored `configs/local.psd1` to point at the tested `build-vulkan-qsa-union\bin\Release`. Before any test, use `-OnlyJob sanity64k -PlanOnly` and check the resolved build, model and environment. No obsolete r4 MoE/GET_ROWS variables are enabled. The historical standalone 18-case gate must remain completed before using this plan.

## r5 actual-model 64k PLE16 QSA OFF/ON — preliminary pre-statistics baseline (2026-10-09)

**Follow-up validated:** 12/12 additional normal CLI runs across 64k/128k/256k are complete; detailed ABBA and r4 comparisons: [R5-VULKAN002-VALIDATION-2026-10-09.md](R5-VULKAN002-VALIDATION-2026-10-09.md). The 64k PLE16 ABBA ON mean **339.48 tok/s** supersedes the isolated 338.71 single-run value for pre-stats regression checks; the prior record below is preserved as historical evidence.

Source archive: `20261009-191835-955-qwen38-r5-qsa-union.zip` (two complete matrix children; source logs retained outside Git). Matrix `sanity64k` ran `A1-off` → `B1-on`, 2/2 OK, no early stop, 1 observation per condition. This baseline **predates the stats-feature port** and is essential for the later `STATS=0` no-regression check. It is **not** ABBA; avoid treating small percent differences as significant.

| Metric | OFF | ON | ON change |
|---|---:|---:|---:|
| PP tokens/s | 269.44 | 338.71 | +25.71% |
| PP time (ms) | 229322.97 | 182426.59 | -46896.38 ms |
| TG tokens/s | 25.71 | 26.12 | +1.60% (single run, not an established gain) |
| TG time (ms) | 19872.81 | 19565.56 | -307.25 ms |
| Exit / Matrix status | 0 / OK | 0 / OK | both |

Fixed: `llama-cli` b11530, Clang 20.1.8, embedded source commit `9391d35c0`, Vulkan0 AMD Radeon 8060S, executable SHA256 `8d45bad26c1460d6bd9c22a4a87389d6ab2855befe939c0a2e3e42297d33714f` (identical), runtime artifact digest `5d83efa4cb808e1e69fb38964c7992ae22f940c986ce0c18d096f72d75390579`, `GitIdentity.Commit=dabe0c58288961518fc2d64e9514207a6e0d1847`, GitDirty false. PLE16 model `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf` (81,961,816,672 bytes, **model full SHA not recorded**). Input `nlp-survey-ch3-d7-b1.txt`, 304,931 bytes, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, matches r4; 61,789 evaluated tokens. Context 65,536; batch/ubatch 2048/1024; f16 K/V; `-t 4 -tb 4 -ngl 999 -ncmoe 0`, FA auto, cache RAM 0, checkpoints `0t`, reasoning off, MTP OFF, seed 1234, temp 0.2, top_p 0.8, fixed 512 tokens with ignore-eos. Resource-monitor logs retained in archive. Stats/profiler disabled. r4 legacy MoE and GET_ROWS toggles unset.

Runtime stderr explicitly logs OFF `QSA grouped-union = off` and ON `QSA grouped-union = on`, then `qsa-union active (r5), group=64, path=1, Br=16, Bc=64, groups=16, capacity=32768, scratch=73400576 bytes`. CPU-reference 18/18 OFF and ON previously accepted. First-pass comparison with **r4 PLE16 64k ABBA mean** (OFF PP 268.42, ON PP 335.38, +24.95%; TG 25.30/25.40) shows similar improvement. Cross-build and 1 vs 2 samples limit comparisons; longer-context and r5 64k ABBA pending while this record is written.

**Next:** the pre-stats 12-run matrix has **completed** and is recorded in [r5 validation](R5-VULKAN002-VALIDATION-2026-10-09.md). Build the stats-enabled source in a separate directory, preserve the b11530 binary, and compare STATS=0 against the 64k PLE16 ABBA ON mean 339.48 tok/s before STATS=1 CSV verification.
