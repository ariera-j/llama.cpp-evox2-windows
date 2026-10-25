# r5 VULKAN-002, real-prompt llama-bench and union statistics: staged port plan

Decision date: 2026-10-09. **Implementation plan, not a validation claim.**
Target: `r5/upstream-refresh-20261009` at `e558af1a5a58a61091314dc23e3731c9eb7f7767`, pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`.
r5 COMMON-001 has passed Vulkan/ROCm Original+PLE16 short and 64k gates. Repository `main` now points at frozen r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8`; previous r2 is preserved at `r2/legacy` `23c316fb5af67da74e614af4a7453fba9ae46189`.

## Pinned donor sources — use selective ports, never merge a full branch

| Feature | Source branch (pinned HEAD) | Existing source/report |
|---|---|---|
| Real-prompt llama-bench | `investigation/llama-bench-real-prompt-20261007` at `e3466e8fa769928140f81c93c84889860732ff82` | [Real-prompt report](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/e3466e8fa769928140f81c93c84889860732ff82/docs/evox2/R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md) |
| QSA grouped-union | r4 commit `5814fbe99e9249e8ac2c4c2e9b977c05735b0912` | [r4 implementation](R4-VULKAN002-IMPLEMENTATION-2026-10-03.md) and [validation](R4-VULKAN002-VALIDATION-2026-10-04.md) |
| Optional union statistics | `investigation/vulkan-qsa-union-stats-20261008` at `979ef17eeff14440a58c866a966b355a1b63b17e` | [Union stats investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/979ef17eeff14440a58c866a966b355a1b63b17e/docs/evox2/R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md) |

The stats branch includes the real-prompt work and is based on older r4 code. **Do not merge, cherry-pick indiscriminately, or overwrite current r5 backend files**. Adopt only the relevant feature deltas and preserve current r5 upstream improvements (Lightning Indexer and new Vulkan sparse/quantized-KV/coopmat2 FA).

## Strict order and acceptance gates

### Phase A — portable real-prompt llama-bench (NOW)

1. Port `-f/--prompt-file`, `--prompt-slice head-tail|head`, and `-c/--ctx-size` to r5 `tools/llama-bench/llama-bench.cpp`. Preserve all r5 native CLI flags/default/random-token benchmark semantics, context auto-size when `-c` is omitted or 0, warmup/repetition behavior, and model/fit handling. Text is tokenized outside timed sections. Refuse short input instead of wrapping/padding.
2. Port matching `-InputKey/-InputFile/-PromptSlice/-Context` and input hash/identity metadata to `tools/evox2/benchmark/Measure-LlamaBench.ps1`; do **not** yet import the stats-file output changes from the later investigation branch.
3. Commit real-prompt support independently from VULKAN-002. **Stop for the user's Windows rebuild and a small smoke test before Phase B.** Test `llama-bench.exe --help`, native normal random PP, real-prompt `head` and `head-tail`, explicit context, short-source error, and wrapper run/result metadata with the source-file SHA256. `llama-cli` inference source must be unchanged by this phase. An optional very small PP case suffices for this gate; a 64k performance sweep is **not** required before Phase B.
4. Real-prompt mode performs raw-text tokenization, **not llama-cli Jinja chat templating**. Thus a close PP value does not prove identical input tokens or request-path semantics. `--prompt-slice head-tail` chooses ceil(N/2) head + floor(N/2) tail with no separator; `head` selects first N. With no prompt file, standard random behavior stays unchanged. Always identify the source file, slice and exact prompt count.

### Phase B — grouped-union (AFTER Phase A build/smoke passes)

1. Port only the r4 union-specific `ggml` FA metadata setter, qwen4exp final **remapped KV-cell ids**, graph propagation, Vulkan 64-query union/gather shaders, device count/dynamic-KV flag and opt-in dispatch. Do not port r4 indexer score/pooling code: r5 uses the fused `ggml_lightning_indexer`. Keep actual attention mask authoritative; selected-id metadata must cover all finite positions. Retain upstream sparse FA and decode/multistream fallbacks, old flag bit 16, use bit 32 only for dynamic counts.
2. `GGML_VK_QSA_UNION=1` opt-in, default OFF; initial `GGML_VK_QSA_UNION_MIN_KV=32768`; K/V f16 for initial qualification, query group=64, Q=1 fallback. Keep r5 MoE/upstream defaults unchanged and do not port r4 legacy tile or unproven GET_ROWS candidates.
3. Commit native implementation independently; rebuild Vulkan with tests; adapt/restore the r4 18 targeted `FLASH_ATTN_EXT` CPU-reference test fixtures and `Test-QsaUnion.ps1`. Require OFF/ON all-pass, actual ON activation and fallback evidence. A copied script without its native fixtures is not a completed test.
4. Validate same-binary normal 64k Original+PLE16 union OFF/ON, then 128k and 256k PLE16 if correctness and system resources allow. Fixed real text/input, seed 1234, 512 generation tokens with ignore-EOS, f16 KV, MTP OFF, same binary. Normal throughput measured with profiler and statistics disabled. Prefer ABBA as in r4, but shorter repeats are acceptable when time-limited if explicitly marked preliminary. Track PP, TG, memory and actual path activation.

### Phase C — union statistics (AFTER grouped-union gate passes)

1. Port only opt-in diagnostic state/counter copying into `ggml-vulkan.cpp` and `ggml-vulkan-types.h`, and the associated `Measure-LlamaBench.ps1` CSV-path tracking. Do not change `qsa_union.comp` or ordinary FA math to collect counts.
2. `GGML_VK_QSA_UNION_STATS=1` plus union ON enables copying the existing four counters per group into bounded GPU recording (65,536 records), reading at backend synchronization, binning by `GGML_VK_QSA_UNION_STATS_KV_BIN` (default 16384) and exporting CSV via `GGML_VK_QSA_UNION_STATS_FILE`. Report drops and never silently use incomplete statistics. STATS=0 creates no recording buffer, extra GPU copies/readback or CSV work.
3. Commit independently. Check **STATS=0 throughput against pre-statistics VULKAN-002** before relying on results. STATS=1 must produce valid CSV and `dropped_groups=0`; its PP values are **not** accepted for measuring union speedups because copy/barriers/readback distort timings.
4. CSV includes warmups as well as timed tests; per-run averages must weight rows by `groups`. `unique/selected` includes invalid selected slots in the denominator, so it is not a pure duplication percentage.

### Phase D — comparison expansion (TIME PERMITTING, not an acceptance blocker)

Required interpretation: differentiate **union OFF/ON speed** (STATS OFF) from **input-distribution diagnosis** (STATS ON). Prefer 64k first, then 128k/256k when practical. With the real-prompt bench in place, include random-token control and compare with real text using matched source build, context, prompt tokens, sampling and inputs as far as feasible.

Optional *one-run-per-source* cases when time allows:

- **English non-repeating document**: a copyright-safe, freely usable sizeable English text, with archived input SHA256, source/license and raw token counts.
- **Japanese non-repeating document**: an independent Japanese long-form passage with no repeated synthetic blocks (book/report or assembled distinct sections). Keep the source/license and hash.
- Code or long-form actual book input can be added later if available, but is not required.
- Repeating Japanese baseline and random tokens remain the reference. Use the same context, token count, slice mode, `model`, f16 KV, build and relevant environment flags. If the source is shorter than requested `-p`, lower `-p` or provide a longer source; **never silently loop it**.
- For expensive 256k, first compare union counts on a representative source at STATS ON; perform STATS OFF throughput only if time permits. Label single runs as exploratory; do not claim input-language causality without matching document structure, tokenization and repetition.

## Preserved r4 observations (NOT yet revalidated on r5)

| Context | Real-prompt bench QSA ON | Random bench QSA ON | Random penalty |
|---|---:|---:|---:|
| 64k | 337.68 PP tok/s | 316.10 | -6.39% |
| 256k | 270.42 | 213.42 | -21.08% |

Diagnostic observations (STATS=1, unsuitable for causal PP gains): 64k unique KV averages real 17,512 vs random 24,859; 256k real 19,704 vs random 32,876. 64k union OFF real 269.12, random 306.51 PP tok/s (random-first replay, two timed repetitions), showing **input behavior reverses when union is OFF**. Off-path mechanism is not yet isolated. These are prior r4 measurements, not a promise of identical r5 results.

## Work status and handoff

**Phase A source port implemented (2026-10-09)** from donor `4bf9af6fefa98622a65bd8d4c04ba73a02e27422`: 19 source hunks + 15 wrapper hunks applied with exact context to the r5 versions, preserving current upstream. See [r5 real-prompt bench implementation and Windows smoke handoff](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md). **Windows compile/smoke PASSED** (b11526, 2026-10-09; three 256-token runs; [evidence](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md)). Phase B may proceed in a separate change. **Phase B grouped-union source selectively ported on 2026-10-09**, native commit `b3d050492b1282feb1ea15aa682cf7d8a57f74b2` and r5 runtime-test logging fix `0a3cf6a0e771feb7990d31748cbbf432681b055f`; see [implementation and Windows build gate](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md). **Windows Vulkan build and 18-case OFF/ON GPU reference tests PASSED** (18/18 OFF, 18/18 ON, 2026-10-09; [r5 validation](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md)). **VULKAN-002 b11530 12-run normal matrix PASSED** (64k Original/PLE16 ABBA + 128k/256k PLE16 OFF/ON; [full r5 results](R5-VULKAN002-VALIDATION-2026-10-09.md)). Same-binary r5 PP gains +26.30%, +25.61%, +71.27%, +105.54% respectively; [r5 A/B plan](../../tools/evox2/benchmark/configs/qwen38-r5-qsa-union.psd1) is prepared. **Phase C statistics source port committed** (commit `37ba95673a061c1b4c0991e8eeea5eb003bbe898`), and **b11535 Windows build plus 64k STATS=0 CLI / STATS=1 CSV smoke PASSED** (2026-10-09; [runtime verification](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md)). The native targeted 18/18 OFF/ON rerun on b11535 was not included in submitted logs; treat 64k genre comparisons as the next stage. The older b11530 64k results are now the frozen pre-stats performance reference.
