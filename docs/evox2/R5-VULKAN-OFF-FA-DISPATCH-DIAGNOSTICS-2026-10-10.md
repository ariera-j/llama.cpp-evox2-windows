# r5 Vulkan OFF Flash Attention dispatch diagnostics (investigation)

Status: **source and benchmark-wrapper implementation committed; Windows build and GPU validation PENDING**. Date: 2026-10-10 JST. Branch: `investigation/r5-vulkan-off-fa-dispatch-20261010`, forked from stable r5 HEAD `d89343fe08175fd86944b95028da59d7e3c950df`. **Do not merge this instrumentation before reviewing actual GPU results.** The stable r5 branch and its tested b11535 binary are unchanged.

## Why

User measured 64k prompt-prefill `GGML_VK_QSA_UNION=0` Japanese novel **286.158** PP tok/s versus code **330.443**, while `GGML_VK_FA_SPARSE_DISABLE=1` yielded **285.796** and **330.384** respectively (negligible ~0.13% and ~0.02% changes). All four runs completed without error. Source review: the sparse FA condition in `ggml/src/ggml-vulkan/ggml-vulkan.cpp` requires `gqa_ratio > 1 || (path == FA_SCALAR && N == 1)`; `gqa_ratio` changes from one only for `N <= 8`. In the ordinary prefill with `-ub 1024`, this makes sparse dispatch unlikely. This needs actual dispatch evidence, not inference alone.

Earlier [ROCm vs Vulkan 64k/128k comparison](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md) found that ROCm's corpus-dependent PP spread is small (~5.5% at 64k and ~4.1% at 128k), while Vulkan OFF ranges ~20.9% and 40.5%, respectively. A Vulkan-specific input-sensitive path is plausible but not proven.

## Implementation scope

- New `GGML_VK_FA_DISPATCH_DIAG=1` **opt-in**, default **disabled**. Only the literal value `1` turns on data collection. A once-initialized flag adds a branch to the ordinary FA path; with diagnostics off, the original pipeline choice and shader dispatch remain untouched.
- When QSA union does not capture an FA op (including union OFF), record CPU-side counts in a `std::map` per Vulkan backend context, keyed by: `KV` bucket (16,384 cells), query-size class (`N <= 8`, `<=64`, `<=512`, or `>512`), FA tuning path (numeric enum), sparse flag, mask-opt flag, aligned, F32 accumulation flag, `Br`, `Bc`. This records the **selected host code path**, not which shader dominates GPU time.
- For each key: `calls`, `query_tokens`, `kv_sum`, `n_kv_max_sum`, `split_k_sum`, and `split_kv_sum`. These can be divided by calls to derive averages. `N` is the FA shader's post-GQA-transform query count, not always original token count. A query-size bucket of 1024 also includes >1024.
- At Vulkan backend **context free**, append aggregate rows to `GGML_VK_FA_DISPATCH_DIAG_FILE` (CSV, header emitted only for an absent/empty file). Write failure and missing path are reported to stderr. A mutex serializes appends across contexts. No GPU readback, new compute shader, per-token logging, token content or elapsed time; CPU map lookups have overhead when diagnostics are on, so these runs are **not** normal PP baselines.
- `Measure-LlamaBench.ps1` creates `fa-dispatch-diag.csv` automatically in its unique run directory if diagnostics are enabled and the file path variable is unset; it records `FaDispatchDiagFile` in conditions, `Files.FaDispatchDiag` in results, and warns if requested CSV is missing. It only restores the file environment variable if it automatically set it. Existing `GGML_VK_QSA_UNION_STATS` CSV functionality remains independent.
- This implementation does **not** add timer queries, alter MoE or Lightning Indexer, override `use_sparse`, or change the existing QSA union ON/OFF behavior. It is specifically to establish whether the literature/code input pair selects the same FA host path and to compare dispatch frequency/bins.

Files:
- `ggml/src/ggml-vulkan/ggml-vulkan-types.h`: small per-context counters.
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: opt-in setting, aggregation and CSV at backend free.
- `tools/evox2/benchmark/Measure-LlamaBench.ps1`: capture generated diagnostics in regular benchmark artifacts.
- This handoff documentation.

## Windows build and validation

Use the existing r5 **Vulkan SDK 1.4.357.0**, LLVM/Clang 20.1.8 setup; create a **new build directory**. Do not replace the known-good b11535 stats build or the ROCm build.

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r5
git fetch origin
git switch investigation/r5-vulkan-off-fa-dispatch-20261010
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-fa-dispatch `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

$bin = '.\build-vulkan-fa-dispatch\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\llama-cli.exe" --list-devices

.\tools\evox2\benchmark\Test-QsaUnion.ps1 -BinDir $bin -Backend Vulkan0
```

Record any build errors verbatim. `test-backend-ops` should run 18/18 OFF and ON, including the union active/fallback tests. This test suite does **not** yet verify diagnostics CSV correctness.

Add a new local `Builds` entry in the ignored `tools/evox2/benchmark/configs/local.psd1` pointing to `build-vulkan-fa-dispatch\bin\Release`, e.g. `R5FaDispatchVulkan` with `BinDir` and `ExpectedBackend = 'Vulkan'`. Keep `UnslothPle16` and the source files already registered. The new build's executable SHA256 must be recorded separately from b11535.

### Short smoke (recommended before 64k)

Use a unique process/run directory; `GGML_VK_FA_DISPATCH_DIAG_FILE` should be **unset** so the wrapper places the CSV beside the logs:

```powershell
$env:GGML_VK_QSA_UNION = '0'
$env:GGML_VK_QSA_UNION_STATS = '0'
$env:GGML_VK_FA_DISPATCH_DIAG = '1'
Remove-Item Env:GGML_VK_FA_DISPATCH_DIAG_FILE -ErrorAction SilentlyContinue
Remove-Item Env:GGML_VK_FA_SPARSE_DISABLE -ErrorAction SilentlyContinue

.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R5FaDispatchVulkan -ModelKey UnslothPle16 `
  -InputFile 'C:\path\to\wagahaiwa_nekodearu_utf8.txt' -PromptSlice head `
  -Context 1024 -PromptTokens 256 -GenerationTokens 0 -Depths 0 `
  -Repetitions 1 -NoWarmup -KvType f16 -Batch 2048 -UBatch 1024 `
  -Threads 4 -GpuLayers 999 -CpuMoe 0 -FlashAttn auto

# Inspect the resulting run directory's fa-dispatch-diag.csv, conditions.json,
# result.json, and stderr.log. Do not rely on a PP comparison from this smoke.
```

After confirming nonempty valid CSV and successful tests, perform **64k Japanese novel and source code** with `-Context 65536 -PromptTokens 61789`, otherwise identical `-NoWarmup -Repetitions 1`, QSA union OFF, STATS OFF. Use the same source file SHA hashes used previously:
- Japanese novel: `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`.
- Code corpus: `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`.

**Control run:** repeat each source on the **same newly built binary** with `GGML_VK_FA_DISPATCH_DIAG=0` and QSA union OFF, using the same conditions. Compare PP with diagnostics OFF to the saved b11535 baseline (~286/330 tok/s); evaluate diagnostic overhead separately rather than using diagnostic PP as a speed baseline.

### CSV checks and analysis

- `calls > 0` in all rows, `sparse`/ `mask_opt` are 0 or 1, `n_kv_max_sum / calls`, `split_k_sum / calls`, `kv_sum / calls` are meaningful.
- Sum calls across rows, compare distribution by KV bucket and FA path for Japanese literature and code. Confirm if prefill really has `sparse=0` and whether `mask_opt`/path/split-K differ.
- If both inputs have essentially the same dispatch mix, **this diagnostic does not rule out different GPU kernel cost for identical shapes/paths**. Next, use RGP per-kernel timings to check mask processing, FA, Lightning Indexer and MoE. Backend CSV counts are **not elapsed time**.
- Caveat: the row is emitted at backend destruction; a process abort or forced termination can prevent writing CSV. The wrapper warns when it cannot find the file.

After experiments, restore/remove `GGML_VK_FA_DISPATCH_DIAG`, `GGML_VK_FA_DISPATCH_DIAG_FILE`, `GGML_VK_QSA_UNION` and any experiment-specific environment variables. Keep the diagnostic branch separate until results warrant an upstream change.


## Windows 64k result: FA dispatch matches across Japanese literature and C/C++ (2026-10-10)

**Status: PASS, experiment decision completed.** Both opt-in diagnostics on b11551 were supplied in archive `20261010-201416-606-bench-vulkan-b11551-ctx65536-0abd151f45bc.zip` (run-local folders below). Full logs were read, not only printed PP averages.

| Item | Japanese literature | llama.cpp C/C++ |
| --- | ---: | ---: |
| Run ID | `20261010-201004-197-bench-vulkan-b11551-ctx65536-38192f507814` | `20261010-201416-606-bench-vulkan-b11551-ctx65536-0abd151f45bc` |
| Input SHA-256 | `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143` | `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` |
| Measured PP | **285.818046 tok/s** | **330.343839 tok/s** |
| Timed PP time | 216.1829904 seconds | 187.0445056 seconds |
| Exit status | OK / 0 | OK / 0 |
| FA dispatch CSV rows | 5 | 5 |
| Aggregated FA calls | **732** | **732** |
| Sum query tokens | 741,468 | 741,468 |
| Sum KV length | 23,230,464 | 23,230,464 |
| Sum n_kv_max | 1,492,116 | 1,492,116 |

Fixed conditions: **b11551**, Clang 20.1.8, native commit `26814cb93`, executable SHA-256 `ee32d6c6b0658ebcb07a21d999da800564492f8fd2b98bf157ad58d160118a74`, Qwen3.8-Flash-Next PLE16, Vulkan0 Radeon 8060S, c65536/p61789, generation 0, depth 0, `-b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16`, raw-file `head` slice, warmup OFF, one timed repetition. Recorded environment: `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, `GGML_VK_FA_DISPATCH_DIAG=1`. All settings and executable identity match across runs.

**The two `fa-dispatch-diag.csv` files are byte-for-byte identical**, including all five bin rows. Their FA tuning `path=1` means **`FA_COOPMAT1`** (enum `FA_SCALAR=0`, `FA_COOPMAT1=1`, `FA_COOPMAT2=2` from `ggml-vulkan-types.h`). Every row has `sparse=0`, `mask_opt=1`, `aligned=1`, `f32acc=1`, `Br=16`, `Bc=64`, mean `split_k=1`. Full bin contents:

| KV bin | N class | FA calls | Query tokens | KV sum | n_kv_max sum |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0–16384 | 1024 | 180 | 184320 | 1474560 | 359964 |
| 16384–32768 | 1024 | 192 | 196608 | 4620288 | 393792 |
| 32768–49152 | 1024 | 192 | 196608 | 7766016 | 393792 |
| 49152–65536 | 512 | 12 | 4188 | 743424 | 24612 |
| 49152–65536 | 1024 | 156 | 159744 | 8626176 | 319956 |

For 61,789 input tokens the expected prefill layout is **60 full 1024-token microbatches plus one 349-token tail**, each with 12 QSA attention instances: `(60+1)*12 = 732` FA calls and `61789*12 = 741468` summed FA query tokens. The diagnostic therefore collected a complete and consistent dispatch census.

Code PP is **15.58% faster** relative to Japanese literature. The absolute timed PP difference is ~**29.14 seconds**. Compared with the immediate earlier sparse-disable screen on b11535, the diagnosed PP rates differ by only **−0.119% (Japanese)** and **−0.030% (code)** from the regular-`sparse` values of 286.158 and 330.443 tok/s. These are different binaries and separate runs, **not** a controlled instrumentation overhead measurement; nevertheless there is no obvious large regression.

### Interpretation / next gate

- This directly **confirms zero sparse FA selections** in all 732 recorded prefill FA calls per corpus; it explains why `GGML_VK_FA_SPARSE_DISABLE` had negligible effect.
- This rules out **differences in the recorded host FA dispatch classes, shapes, or `n_kv_max` upper bounds** as the cause of the **15.6% PP gap**. The CSV does not report the actual selected mask contents, GPU kernel elapsed time, MoE routing distribution, Lightning Indexer timings, or per-layer timings. The same host-selected shader can do different GPU work when the *mask bits or expert routing* differ.
- In particular, `mask_opt=1` means `fa_mask_opt` generates compact mask metadata consumed by FA. Different selected-cell positions could change active/empty tiles even when the **upper bound n_kv_max and all tensor shapes coincide**. This is a **hypothesis**, not an established cause.
- **NEXT:** for the same pair of inputs, QSA union OFF, run a **Vulkan GPU performance-logger** comparison (or RGP after that) with `GGML_VK_PERF_LOGGER=1`, `GGML_VK_PERF_LOGGER_FREQUENCY=1`, `GGML_VK_PERF_LOGGER_CONCURRENT` absent, and **`GGML_VK_FA_DISPATCH_DIAG` absent**. Use the same b11551 binary, prompt tokens, hashes and no-warmup settings. Compare the 61 prefill timing blocks by bucket and op name: `FLASH_ATTN_EXT`, `fa_mask_opt`/FA pipeline, `MUL_MAT_ID` MoE, Lightning Indexer, other operations. These logger-enabled PP numbers are diagnostic and must **not** be conflated with normal non-profiled throughput.
- Rebuilding more host FA dispatch counters will not help distinguish these two inputs. Keep the diagnostic branch separate until the GPU timing result is interpreted. No r5 stable-source modification is warranted from this result alone.


## Vulkan GPU performance logger: Japanese literature vs source code (2026-10-10)

**Status: COMPLETE; 2/2 profiler runs OK.** Evidence archive: `20261010-203441-045-bench-vulkan-b11551-ctx65536-47b0cde1f5ff.zip` (both run directories, `stderr.log`, `result.json`, `conditions.json`, `summary.csv`). The experiment uses **the same b11551 executable** as the prior host-dispatch diagnostic, but with the host-side FA dispatch diagnostic disabled and the built-in GPU logger enabled. Every metric below comes from parsing the 61 complete `Vulkan Timings` blocks in each `stderr.log` (60 full 1024-token microbatches plus a 349-token tail), not from a single example block.

### Fixed conditions / integrity

| Condition | Japanese literature | llama.cpp source code |
| --- | --- | --- |
| Run directory | `20261010-203020-728-bench-vulkan-b11551-ctx65536-9394b19c6e70` | `20261010-203441-045-bench-vulkan-b11551-ctx65536-47b0cde1f5ff` |
| Input SHA-256 | `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143` | `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` |
| `Status / ExitCode` | OK / 0 | OK / 0 |
| PP with Vulkan perf logger | **275.203868 tok/s** | **316.493093 tok/s** |
| Approx. timed PP wall duration (`p/PP`) | 224.521 seconds | 195.230 seconds |
| Complete Vulkan timing blocks | **61** | **61** |
| GPU op-time total (sum of 61 `Total time` lines) | **217.23743 seconds** | **187.70091 seconds** |

Same build: Vulkan b11551 / Clang 20.1.8, exe SHA-256 `ee32d6c6b0658ebcb07a21d999da800564492f8fd2b98bf157ad58d160118a74`, PLE16 UD-IQ3_XXS, Radeon 8060S. Both use ctx **65536**, input `head` **61789 tokens**, `-n 0 -d 0 -r 1 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --no-warmup`. All relevant environment variables match: `GGML_VK_QSA_UNION=0`, `GGML_VK_QSA_UNION_STATS=0`, `GGML_VK_PERF_LOGGER=1`, `GGML_VK_PERF_LOGGER_FREQUENCY=1`; `GGML_VK_PERF_LOGGER_CONCURRENT`, `GGML_VK_FA_DISPATCH_DIAG`, `GGML_VK_FA_SPARSE_DISABLE` absent. Both stderr logs contain **61 complete** timing blocks, and for each block the operation-time sum agrees with that block's printed `Total time` up to log rounding.

The logger-enabled PP rates are lower than the same build's previous diagnostics-on PP (~285.818 / 330.344 tok/s) by ~3.7% / ~4.2%. Profiler PP is **not** a normal-speed baseline, and this cross-run difference should not be interpreted as a calibrated logger overhead measurement.

### GPU op-time decomposition (seconds, all 61 prefill blocks)

| Category | Japanese literature | Code | Code minus literature |
| --- | ---: | ---: | ---: |
| **FLASH_ATTN_EXT** | **102.4600** | **69.5648** | **−32.8952** |
| MoE `MUL_MAT_ID*` | 40.7900 | 45.2403 | **+4.4503** |
| `LIGHTNING_INDEXER` | 1.1681 | 1.1697 | +0.0015 |
| All other Vulkan GPU ops | 72.8193 | 71.7261 | −1.0932 |
| **GPU op-time total** | **217.2374** | **187.7009** | **−29.5365** |

- Code's aggregate `FLASH_ATTN_EXT` GPU op time is **32.1% lower**. This **32.895 s reduction exceeds the total 29.537 s GPU op-time reduction** (~111.4%): the non-FA ops collectively take ~3.359 s *longer* for code, principally MoE (+4.450 s).
- FA accounts for **47.2%** of Japanese-literature GPU op time versus **37.1%** of code; MoE accounts for 18.8% versus 24.1%.
- `LIGHTNING_INDEXER` time differs by only ~0.002 seconds over the entire PP. MoE differs but in the **opposite direction** to the observed total PP advantage for code. Thus the previously suspected MoE/Indexer as a primary explanation for the literature-vs-code difference is not supported by the op-time totals.
- This GPU-op-time decomposition is consistent with the wall-time difference inferred from bench PP (~29.29 seconds) without claiming that GPU `Total time` is the entire wall clock.

### Difference by KV range (FLASH_ATTN_EXT aggregate GPU seconds)

The 61 blocks correspond to progressive 1024-token KV lengths and a 349-token last block; sums below are **per group of blocks**, not average latency per 1024-token microbatch. They do not include warmup or generation.

| KV depth by microbatch | Blocks | Japanese literature FA | Code FA | Literature minus code |
| --- | ---: | ---: | ---: | ---: |
| 1–16k | 16 | 4.594 | 4.388 | +0.207 |
| 17–32k | 16 | 16.636 | 16.624 | +0.013 |
| **33–48k** | **16** | **36.779** | **26.929** | **+9.849** |
| **49–60k** | **12** | **43.465** | **21.051** | **+22.414** |
| 349-token tail (~61.8k KV) | 1 | 0.986 | 0.573 | +0.412 |

**Critical observation: the large FA timing gap appears predominantly *after KV exceeds 32k*.** At 17–32k the FA times are nearly equal (~16.64 vs 16.62 sec), while at 49–60k Japanese-literature FA time is ~2.06× the code FA time (43.465 vs 21.051 sec). This is much more diagnostic than the aggregate PP difference. The `GGML_VK_QSA_UNION` switch stays OFF throughout; there is no union ON transition at 32k. The available evidence cannot yet establish which FA shader instruction or memory-access pattern causes the difference.

### Mechanism hypotheses and next decision

The immediately previous **host FA dispatch CSVs were byte-for-byte identical** for these two inputs at 64k: 732 calls, same KV bins, `FA_COOPMAT1` (`path=1`), `sparse=0`, `mask_opt=1`, `Br=16`, `Bc=64`, `split_k=1`, identical n_kv_max sums. This excludes a *host-selected FA pipeline/shape/count* change as the explanation. It **does not imply identical GPU work** when masks differ.

Source-level clue: `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_mask_opt.comp` identifies all-negative-infinity versus all-zero mask tiles; `flash_attn_cm1.comp` examines those flags and has a `MASK_OPT_ALL_NEG_INF` fast skip (`continue`) before the key/value computation. Since the QSA selection mask contains input-dependent selected-cell positions, a different number/placement of nonempty tiles is a strong **hypothesis** for the observed FA op-time gap. Neither the mask-tile histogram nor the RGP kernel-level times have been measured yet.

**Next priority:** collect **RGP** profiles for the same two inputs, QSA union OFF, matched conditions. Isolate time in `fa_mask_opt` (mask preprocess) versus actual `flash_attn_cm1` dispatch and check read traffic / wave occupancy / shader duration at representative late-KV depths (~48–60k). If RGP shows a large FA shader rather than mask-prepass difference, instrument or A/B the number of nonempty FA tiles before attempting more optimizations. A temporary **mask-opt disable** flag is possible in the investigation branch but would require a rebuild and CPU-reference correctness gate, so prefer read-only profiling first. Do not merge diagnostics into r5 stable based on this result alone.

**Bottom line:** the Vulkan OFF corpus sensitivity at 64k is now localized to the **`FLASH_ATTN_EXT` operator** in the GPU profiler, rather than MoE, Lightning Indexer, or a different FA host pipeline. Shader-level causality is the remaining unknown.


## RGP SQTT exploratory two-corpus comparison (2026-10-10, RDP timer)

**State: two valid, non-truncated RGP captures; shader identity confirmed; equivalent KV position and FA kernel identity NOT YET confirmed.** These are preliminary **~0.18–0.19 second SQTT windows**, not complete 64k PP runs. They must not displace the prior whole-run GPU performance logger result attributing the overall 29.5-second difference primarily to `FLASH_ATTN_EXT`.

Capture settings for both: Radeon Developer Panel on Windows 11, Vulkan, automatically attach `llama-bench.exe`, **Dispatch timer / 195,000 ms / count 256**, SQTT buffer setting **High**, no instruction tracing, no shader instrumentation, hardware counters unchecked. RGP's RDF `TraceConfig` records `captureRenderOpCount=256`, `renderOpMode=dispatch`, `memoryLimitInMb=128`, and SPM disabled. After reducing count from 4096 and raising buffer from default, both RGPs open without the preceding `Truncated SQTT data` warning.

| Item | Japanese literature | llama.cpp C/C++ |
| --- | ---: | ---: |
| RGP evidence | `llama-bench-20261010-222243750.rgp` | `llama-bench-20261010-224538527.rgp` |
| File size | 154,953,898 bytes | 155,963,842 bytes |
| RGP Profile duration | **183,602.786 µs** | **194,373.615 µs** |
| GPU idle | 0.35% | 0.37% |
| Queue submissions/command buffers | 17 / 17 | 20 / 20 |
| Events (dispatch / barrier) | 550 (325 / 225) | 550 (325 / 225) |
| Unique pipelines | 55 | 55 |
| RDF code-object blobs | **69** | **69** |

**Independent binary cross-check:** RDF header magic `AMD_RDF` and chunk directory parsed successfully. All **69/69 CodeObject payloads** are *byte-for-byte identical* between the two RGPs (matching SHA-256 and lengths in order). The `PsoCorrelation` payload is also byte-for-byte identical (6,624 bytes), as are `TraceConfig`, `SystemInfo` and `AsicInfo`. This gives stronger support than visual similarity that both profiles use the **same compiled GPU shader binaries / pipeline correlation map**; it does **not** establish that they process the same KV length or mask contents. The actual SQTT payloads and queue events differ, as expected from different run times and input data.

### Selected matched pipeline timings from RGP's Pipeline summary

Values are **GPU event times within the short captures**, not whole-run operator totals. Hash identity and event counts match; kernel labels such as `flash_attn_cm1` have NOT been recovered. Milliseconds below are calculated from RGP's µs display, rounded.

| RGP API pipeline hash | Call count (each) | Literature, ms | Code, ms | Code relative difference |
| --- | ---: | ---: | ---: | ---: |
| `0x91D300D08410103C` | 4 | 24.231 | 29.030 | +19.8% |
| `0x8E6F51C3BA1CD7C4` | 2 | 20.414 | 25.728 | +26.0% |
| `0xB035AE81CBB19009` | 21 | 20.822 | 20.927 | +0.5% |
| `0x3E31874274449F8A` | 14 | 19.643 | 19.554 | −0.5% |

The same shader hashes, but non-identical kernel durations: code is **slower** for the first two in these short captures, although its **whole-run PP is faster**. The captures used the same **195,000 ms process-relative timer**, not the same KV position. Since the source-code corpus has different PP speed, they likely sampled **different KV depths**. The difference here should NOT be attributed to content, FA, cache/occupancy, or regression without aligning KV and mapping pipelines to named shader operations.

The earlier 4096-dispatch Japanese literature file `llama-bench-20261010-211926699.rgp` raised a truncation warning and should not serve as a timing comparison. Do not confuse the **RGP Profile duration (~184/194 ms)** with the **Queue submission overview horizontal span (~3 sec)** or with 195 sec from process startup: these report different things.

### Next profiling gate

1. **Keep 256 dispatch / SQTT High / counters OFF**; both captures are valid with this setting.
2. Obtain a reliable **KV-depth and shader-name annotation** before interpreting more GPU timing A/B. Preferred investigation-only solution: add read-only Vulkan `VK_EXT_debug_utils` labels around named dispatch paths (`fa_mask_opt`, `flash_attn_cm1`, optional MoE/Indexer) and annotate KV / N at FA dispatch (or emit a minimal dispatch-index-to-KV trace). Confirm in RGP whether the Vulkan driver and capture preserve these labels. Do not alter FA mask/shader math or merge to stable r5 before correctness/overhead checks.
3. Alternatively use the already collected per-ubatch perf logger curves to estimate equivalent-KV capture offsets; **195 sec fixed timer is not equivalent-KV alignment**. If testing this coarse alternative, code's earlier capture time would be a provisional estimate, not a guaranteed KV-matched pair.
4. Once matching FA shader and late KV (48–60k) are identified, compare `fa_mask_opt` preprocessing separately from `flash_attn_cm1` and investigate mask tile skip rate. Whole-run FA time remains the established large difference, shader-level cause still unconfirmed.


## Investigation-only RGP kernel and KV-depth labels (2026-10-10)

**Source implemented on `investigation/r5-vulkan-off-fa-dispatch-20261010`; Windows rebuild / Vulkan validation / RGP visibility PENDING.** This follows the two-corpus RGP comparison above; no source code on stable `r5/upstream-refresh-20261009` was changed.

### Discovery: ggml already has Vulkan debug labels

Upstream's existing `GGML_VK_DEBUG_MARKERS` opt-in enables `VK_EXT_debug_utils` and adds **a label around every dispatch with its native pipeline name and workgroup count**, as well as graph-op and submit labels. Previous RGP captures did not enable that flag, explaining why the UI showed only pipeline hashes. Thus custom shader-name infrastructure was unnecessary.

This investigation now adds a more specific, separate `GGML_VK_FA_RGP_MARKERS=1` (literal `1` only) that:
- Automatically requests `VK_EXT_debug_utils` if available, **even if `GGML_VK_DEBUG_MARKERS` is unset**. It therefore also enables upstream's existing nested per-dispatch name labels for the duration of a capture.
- Around each FA *compute dispatch* emits an additional parent marker of the form `EVOX2_FA_MAIN shader=<actual pipeline name> KV=49152 N=1024 Br=16 Bc=64 n_kv_max=2051 q=<query tensor name>`. `KV` is the actual K tensor length in that FA invocation, **not the RGP capture timestamp**. `N` is that FA invocation's query dimension after any decode GQA reshaping.
- Also labels `EVOX2_FA_MASK_OPT` (mask prepass), `EVOX2_FA_SPARSE` (optional sparse compact), `EVOX2_FA_MAIN_SPLIT` (split-K main FA), and `EVOX2_FA_SPLIT_REDUCE` (split-K reduction). For the previous 64k QSA union OFF PP test, we expect `EVOX2_FA_MASK_OPT` and `EVOX2_FA_MAIN`; neither sparse nor split-K is expected.
- Leaves all workgroup counts, shader binaries, masks, QSA union decisions, and compute arguments unchanged. It adds CPU label formatting and Vulkan debug-region commands when enabled; the resulting profile is **diagnostic, not a normal PP baseline**.
- Leaves `GGML_VK_FA_DISPATCH_DIAG` (host CSV counters) independent. For RGP, **set `GGML_VK_FA_RGP_MARKERS=1` only** and clear other profiling/diagnostic flags to limit interference.
- Prints a **one-time stderr log** `ggml_vulkan: FA RGP markers enabled (VK_EXT_debug_utils, label prefix EVOX2_FA_)`. If `VK_EXT_debug_utils` is unavailable, prints a warning and does **not** add labels. If RGP does not preserve labels despite successful Vulkan registration, RGP label visibility remains a separate, still-unverified tooling issue.

Changes are confined to `ggml/src/ggml-vulkan/ggml-vulkan.cpp` and `ggml/src/ggml-vulkan/ggml-vulkan-types.h`. The common dispatch template `ggml-vulkan-common.h` was intentionally left unchanged. `Measure-LlamaBench.ps1` already records `GGML_` environment variables in `conditions.json`, so it needs no change.

### Build: keep b11551 and stable r5 binaries intact

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r5
git fetch origin
git switch investigation/r5-vulkan-off-fa-dispatch-20261010
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-rgp-kv-labels `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

$bin = '.\build-vulkan-rgp-kv-labels\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\llama-cli.exe" --list-devices
.\tools\evox2\benchmark\Test-QsaUnion.ps1 -BinDir $bin -Backend Vulkan0
```

`local.psd1` is ignored/untracked. Add **one** entry in its existing `Builds` section (without replacing the old b11551 `R5FaDispatchVulkan`):

```powershell
R5RgpKvVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-rgp-kv-labels\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

### 256-token smoke before RGP

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r5
$env:GGML_VK_QSA_UNION = '0'
$env:GGML_VK_QSA_UNION_STATS = '0'
$env:GGML_VK_FA_RGP_MARKERS = '1'

# Avoid mixing diagnostic mechanisms in the short RGP preparation test.
@('GGML_VK_FA_DISPATCH_DIAG', 'GGML_VK_FA_DISPATCH_DIAG_FILE',
  'GGML_VK_PERF_LOGGER', 'GGML_VK_PERF_LOGGER_FREQUENCY',
  'GGML_VK_PERF_LOGGER_CONCURRENT', 'GGML_VK_FA_SPARSE_DISABLE') | ForEach-Object {
    Remove-Item "Env:$_" -ErrorAction SilentlyContinue
}

$base = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test'
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R5RgpKvVulkan -ModelKey UnslothPle16 `
  -InputFile (Join-Path $base 'wagahaiwa_nekodearu_utf8.txt') -PromptSlice head `
  -Context 1024 -PromptTokens @(256) -GenerationTokens @(0) -Depths @(0) `
  -Repetitions 1 -NoWarmup -KvType f16 `
  -Batch 2048 -UBatch 1024 -Threads 4 -GpuLayers 999 -CpuMoe 0 `
  -FlashAttn auto -UmaLabel '96GB'
```

Pass gate: wrapper result `Status=OK`, `ExitCode=0`, detected backend Vulkan, and `stderr.log` containing the one-time FA markers enabled message **and no Vulkan error**. This only confirms that Vulkan instance/extension initialization succeeded. It does **not** prove that RGP can display or preserve debug-region names; that requires an actual capture.

### 64k RGP capture

In Radeon Developer Panel, reuse the **validated non-truncated capture parameters**: Vulkan, Auto capture `Dispatch timer`, time `195000 ms`, `Dispatch count=256`, SQTT buffer **High**, Collect counters OFF, instruction tracing OFF. Keep these fixed in the first labeled run, but do not claim equivalent KV position until the marker is visible. Configure the panel before launching `llama-bench.exe`.

Run the same command as the smoke, but with `-Context 65536 -PromptTokens @(61789)` and unchanged QSA/FA marker env. Start with **Japanese literature** only. When the profile is opened, look for `EVOX2_FA_` in the RGP event hierarchy / grouping and inspect `KV=...` and `shader=...` in the labels. `EVOX2_FA_MASK_OPT` identifies mask preprocessing; `EVOX2_FA_MAIN` identifies the actual FA compute dispatch (expected existing nested pipeline name contains `flash_attn...`).

If labels are visible, determine captured KV position before running code and adjust the code-side timer only as necessary to target an overlapping **KV=48k–60k** range. Prefer comparison of the same `shader` and `KV` at a matching query tensor/layer, not top-of-list pipeline durations at equal wall-clock delay.

**If labels are absent:** preserve `stderr.log`, `conditions.json` and a screenshot of RGP Event timing including the event tree; check the one-time enabled message, RGP capture warning, and `ggml_vk_debug_label` behavior. Do not assume the shader label is displayed simply because the Vulkan extension initialized. Pipeline hash alone is insufficient to align KV and kernel identity.

After testing, remove `GGML_VK_FA_RGP_MARKERS` and any explicitly set `GGML_VK_DEBUG_MARKERS` from the process environment. Keep the known-good b11551 for uninstrumented measurements.


## First labelled RGP 64k Japanese literature capture — 2026-10-11 (00:00 JST)

**Preliminary result — Vulkan upstream debug labels visible, but FA KV-specific labels not verified yet.** Capture file: `llama-bench-20261011-000053596.rgp`, 155,014,948 bytes (RDF `AMD_RDF` header confirmed). Captured using RGP's timer workflow after adding `GGML_VK_FA_RGP_MARKERS` support on the investigation branch; inspect the native run's `stderr.log` or `conditions.json` to prove the specific opt-in flag was set and initialization succeeded. Merely seeing ordinary pipeline names does not establish that the **new FA-specific label** was activated.

Observed in user-provided RGP screens:

| RGP field | Result |
| --- | --- |
| Target API/device | Vulkan / Radeon 8060S |
| Profile duration | 182,576.905 µs (~182.58 ms) |
| GPU idle | 0.36% (RGP says GPU bound) |
| Queue submissions / command buffers | 16 / 16 |
| Sync primitive events | 0 |
| RGP event statistics | 550 events = 325 `vkCmdDispatch` + 225 `vkCmdPipelineBarrier` |
| Pipeline count | 55 |
| Top API PSO hash | `0x91D300D08410103C` |
| Top pipeline GPU time | 24,129.879 µs / 4 dispatches |

**New conclusive name mapping:** screenshot of RGP **Event timing** with the expanded label tree shows that the top pipeline hash `0x91D300D08410103C` corresponds to **MoE `MUL_MAT_ID ffm_moe_gate-0` and the shader `matmul_id_subgroup_iq2_s_f32_f16acc_aligned_1`**, including dispatch `(10, 16, 512)`. Therefore the biggest pipeline in the earlier 195-second RGP snapshots was **not Flash Attention**. Other visible labels include `CONCAT`, `GET_ROWS`, `RMS_NORM`, `MUL_MAT`, and MoE-specific shader names. GPU event naming is working.

The visible two portions of Event timing (near event IDs 53–75 and 123–150) show **no `EVOX2_FA_` label**; however only partial portions of the 550-event trace are visible in screenshots. This is **not proof** that FA-specific labels are absent from the complete capture or that FA was not dispatched within the sampled interval. Profile duration is only ~183 ms, so it is also possible that the sampled interval consists mainly of a MoE section between FA calls. The capture does **not yet** locate a KV=48–60k FA invocation.

**Next minimal user-side gate before another RGP capture:**

1. In **RGP → Events → Event timing**, use `Filter event tree...` to search for **`EVOX2_FA_`**. If matches appear, show the event hierarchy and first `KV=` label, especially `EVOX2_FA_MASK_OPT` and `EVOX2_FA_MAIN`.
2. If none, inspect the corresponding benchmark's `stderr.log` for `ggml_vulkan: FA RGP markers enabled`, and its `conditions.json` for `GGML_VK_FA_RGP_MARKERS=1` and correct new executable SHA/build key. Note: generic named pipeline labels can come from the preexisting `GGML_VK_DEBUG_MARKERS`.
3. If confirmed enabled yet no FA markers in this ~183ms window, shift the **capture delay** slightly while retaining the proven 256 dispatch / SQTT High / counters OFF configuration, or collect a small number of indexed adjacent captures to find FA dispatches. Do not alter GPU shaders or equate captures based only on 195s wall-clock delay.
4. Only after identifying `KV`, shader and matching tensor/layer for FA in each corpus, compare per-kernel FA and mask-prepass timings. The previous whole-run FA attribution remains valid independently of this RGP snapshot.

No new C++ commit, refactoring, or stable r5 change is justified by this preliminary snapshot.
