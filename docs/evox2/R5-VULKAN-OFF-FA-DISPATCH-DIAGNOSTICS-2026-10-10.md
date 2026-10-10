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
