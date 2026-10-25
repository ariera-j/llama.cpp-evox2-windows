# r5 Vulkan QSA union: 128k three-corpus diagnostics (2026-10-10)

Status: **128k STATS ON, three inputs completed and validated (3/3 OK); diagnostics only, not ordinary throughput**. Branch: `r5/upstream-refresh-20261009`. Follow-up to [64k seven-corpus statistics](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md) and [64k ABBA / 128k A/B throughput](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md).

## Evidence and fixed conditions

- User-supplied source archive: **`qsa-128k-stats-20261010-084933.zip`**. It contains three run folders (`ja-literature`, `llamacpp-code`, `random`) with `conditions.json`, `result.json`, `qsa-union-stats.csv`, `stderr.log`, `summary.csv`, native bench JSON, and `run-index.csv`. Raw artifacts remain outside Git.
- Runs from **2026-10-10 08:49:36–09:12:51 JST**, each `Status=OK`, `ExitCode=0`. Binary: **Vulkan `llama-bench` b11535**, Clang 20.1.8, executable embedded commit `fbb6e15bd`, executable SHA-256 **`9d32422898d4c8038acc3da9c8e3045841726d8cf1df6cea2e68241e4c707159`** across all three; backend Vulkan / AMD Radeon(TM) 8060S Graphics, manual 96GB UMA label. Same Qwen3.8-Flash-Next UD-IQ3_XXS PLE16 GGUF, f16 K/V, no MTP.
- Fixed native workload: `-c 131072 -p 126253 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16`; no chat template or generation. `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `GGML_VK_QSA_UNION_STATS=1`, `GGML_VK_QSA_UNION_STATS_KV_BIN=16384`. Statistics file is generated per run. Logs contain both `qsa-union active (r5)` and an expected fallback message.
- Input `ja-literature`: first 126,253 raw tokens of `wagahaiwa_nekodearu_utf8.txt` (`--prompt-slice head`), SHA-256 `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`.
- Input `llamacpp-code`: first 126,253 raw tokens of `llamacpp-inference-code.txt` (`--prompt-slice head`), SHA-256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`; corpus generated from pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b` with `make_llamacpp_code_corpus.py --preset inference`.
- Input `random`: standard llama-bench native random-token path, without `-f`, file hash, or `--prompt-slice`. Treat this as a distributional control, **not a fixed cross-backend token-identical sequence**.
- All three CSVs: **93 rows, 93 backend sync IDs, 17,724 total recorded groups, no dropped groups**, six 16,384-wide KV bins beginning at 32,768. The first five bins each have 16 rows / 3,072 groups; the final bin has 13 rows / 2,364 groups. No invalid group count, impossible unique/padded ordering or empty statistics observed.

## Group-weighted aggregate statistics

Each figure is `sum(groups * row_metric) / sum(groups)`, over all 93 per-sync/per-bin CSV rows; never use plain arithmetic row averages. `selected_mean` includes invalid slots, so `unique_over_selected` is **not** a strict duplicate ratio.

| Input | Unique mean | Padded mean | Selected mean | Unique / selected | Instrumented PP (tok/s, **not a speed baseline**) |
| --- | ---: | ---: | ---: | ---: | ---: |
| Japanese literature | **22,798.57** | 22,925.16 | 131,237.62 | 17.372% | 291.81 |
| llama.cpp C/C++ | **14,155.45** | 14,282.30 | 131,237.62 | 10.786% | 343.08 |
| Native random tokens | **29,598.36** | 29,724.83 | 131,237.62 | 22.554% | 260.46 |

Unique union ordering is **random > Japanese literature > code**; code / random = **47.8%**. Instrumentation copies counters/synchronizes the GPU and changes timing; compare performance instead using the separately recorded STATS OFF 128k results.

## Unique union by KV bin, group weighted

The CSV records `kv_bin_end` as an **exclusive** endpoint. The final bin extends to 131,072, although the input contains only 126,253 tokens.

| KV [start, end) | Groups | Japanese literature | llama.cpp code | Random tokens |
| --- | ---: | ---: | ---: | ---: |
| 32,768–49,152 | 3,072 | 18,236.11 | 12,487.00 | 23,040.95 |
| 49,152–65,536 | 3,072 | 20,638.03 | **10,941.06** | 26,643.36 |
| 65,536–81,920 | 3,072 | 22,718.89 | 13,330.23 | 29,945.45 |
| 81,920–98,304 | 3,072 | 23,938.47 | 15,540.60 | 31,416.66 |
| 98,304–114,688 | 3,072 | 25,247.82 | 16,230.71 | 33,406.49 |
| 114,688–131,072 | 2,364 | 26,974.55 | 17,076.28 | 34,197.11 |

Code is distinctive: its measured unique union drops from **12,487 at KV 32–48k** to **10,941 at KV 48–64k**, then grows after 64k, reaching **17,076 at KV 112–128k**. Japanese literature and random increase throughout these six bins. The first 64k result therefore did **not** establish that code union would continue shrinking at higher KV lengths. At the end of 128k, code union is still about half of random. Differences could reflect code/token recurrence and positions in the selected corpus; this is a hypothesis, not a demonstrated cause.

## Comparison with earlier 64k diagnostics

| Input | 64k unique mean (5,640 groups) | 128k unique mean (17,724 groups) | Change in reported *whole-run weighted mean* |
| --- | ---: | ---: | ---: |
| Japanese literature | 19,225.61 | 22,798.57 | +18.6% |
| llama.cpp C/C++ | 11,836.90 | 14,155.45 | +19.6% |
| Random | 24,562.67 | 29,598.36 | +20.5% |

**Caution:** 64k and 128k averages cover **different KV-bin mixtures and group weights**; this ~19–21% change does **not** mean identical KV ranges became ~20% more expensive. Even overlapping 48–64k bin means differ across runs. For 128k time/performance comparisons use the STATS OFF overnight experiment: 128k ON normal PP **294.02** Japanese literature, **346.60** code, **261.67** random (tok/s), from a different run, not directly subtractable from diagnostic STATS ON throughput.

The present observations are still insufficient to explain why **Vulkan union OFF** has large input-dependent PP differences. OFF takes a different Vulkan Flash Attention dispatch path, and code contents, selected key distributions, and non-FA kernels may affect it. No profiling was run for this document.

## Next experiment order

1. **Completed:** Vulkan 128k union statistics for Japanese literature, code and random.
2. **Next:** independent **ROCm** real-prompt `llama-bench` baseline: 64k all seven inputs (including short Japanese technical), ideally 128k six eligible inputs, with identical GGUF, source-text hashes, tokenizer lengths, `head` slicing, `-b/-ub`, f16 KV, and MTP off. The user's latest ROCm binary contained only COMMON-001 and **predates the native real-file `llama-bench -f` port**; build current r5 sources in a **new ROCm build directory**, preserve previous ROCm builds, and verify `-f`, `--prompt-slice`, `-c` via help plus smoke tests before long runs.
3. Then investigate **Vulkan union OFF** kernel dispatch and timings only after reviewing ROCm comparison. ROCm does not implement this Vulkan-specific grouped union; do not label its results as an equivalent “union OFF” mode. Within-backend input ordering and per-context scaling are more informative than attributing cross-backend absolute speed gaps to any one kernel.

References: [r5 stats implementation](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md); [r5 comparative throughput report](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md).

## ROCm study follow-up completed

The subsequent [ROCm vs Vulkan 64k/128k real-prompt PP comparison](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md) completed **13/13** ROCm normal-throughput runs. ROCm 128k had only a **4.1%** fastest/slowest PP spread versus Vulkan union OFF **40.5%**, motivating a bounded Vulkan OFF sparse-attention dispatch diagnostic before MTP or ROCmFP4 investigation.
