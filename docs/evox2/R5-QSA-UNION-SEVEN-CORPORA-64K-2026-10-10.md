# r5 Vulkan QSA union: seven-corpus 64k input-distribution study (2026-10-09/10)

## Scope and evidence

This is an **exploratory, statistics-enabled input-distribution comparison**, **not** a measurement of QSA union speedup. Seven cases were checked against the user-supplied raw artifacts, not just the summary CSVs:

- Six real-text/coded inputs: `20261009-232215-046.zip` (six per-corpus `conditions.json`, `result.json`, `summary.csv`, `qsa-union-stats.csv` and logs).
- Native llama-bench random-token control: `20261009-235450-253.zip` (same artifacts).
- Both ZIP files are private experiment artifacts and are **not committed** to Git.

All seven runs: `Status=OK`, `ExitCode=0`, b11535, Vulkan/AMD Radeon 8060S, build/source commit `fbb6e15bdfe85737683c56c74ab7fae13d520f17` reported in prior validation (runtime shortened commit `fbb6e15bd`), `llama-bench.exe` SHA-256 `9d32422898d4c8038acc3da9c8e3045841726d8cf1df6cea2e68241e4c707159`. The clean r5 worktree commit reported during this batch is `de65697c647eb7f918ccb6818f4176013be4f41c`. This distinguishes the compiled binary's source identity from the current checkout HEAD.

Fixed conditions: Evo-X2, manually labeled UMA 96 GB, Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS PLE16 GGUF (model file size 81,961,816,672 bytes; no model SHA supplied), `-c 65536 -p 61789 -n 0 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16`. MTP OFF. For the six files: raw-text tokenization by the patched llama-bench `-f` path, `--prompt-slice head`, **first 61,789 raw tokens**; no chat template. The repeated ANLP source uses the larger `nlp-survey-ch3-d31-b1.txt` (256k source), *not* the historical 64k `d7` CLI prompt. The seventh test omits `-f` and uses the native random-token path; there is no file hash or slice mode.

Environment: `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `GGML_VK_QSA_UNION_STATS=1`, `GGML_VK_QSA_UNION_STATS_KV_BIN=16384`. Every stderr confirms the r5 union active path (and expected short-KV/query fallback). All seven CSVs: **30 rows, 5,640 recorded groups, `dropped_groups=0`**, same group distribution across the two observed KV bins. Per-sync rows, not independent runs. These figures describe the union-enabled eligible prefill groups only.

## Input provenance and raw-file SHA-256

The full-file token counts below were supplied by the user, who ran `llama-tokenize.exe` with the PLE16 model. Actual `-p` in every benchmark is 61,789. Hashes were independently extracted from each run's recorded `InputIdentity`; the raw input contents are not in the ZIPs.

| Key | Filename | Source / construction | Full-file tokens | Input SHA-256 |
| --- | --- | --- | ---: | --- |
| `ja-repeated` | `nlp-survey-ch3-d31-b1.txt` | Repeated Japanese NLP research text, previous long-context ANLP corpus | see original corpus manifest | `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` |
| `ja-literature` | `wagahaiwa_nekodearu_utf8.txt` | Soseki, *I Am a Cat*; [Aozora Bunko](https://www.aozora.gr.jp/cards/000148/card789.html), converted to UTF-8 in Sakura Editor | 251,252 | `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143` |
| `en-literature` | `pg1184.txt` | Dumas, *The Count of Monte Cristo*; [Project Gutenberg #1184](https://www.gutenberg.org/ebooks/1184) | 668,434 | `64f8d5cfa51fcecb904abf7312d395d512a71817e7359b91288beb50517c3836` |
| `ja-technical` | `biopapyrus-prose.txt` | [Deep Learning Introduction](https://dl.biopapyrus.jp/index.html), [biopapyrus/dl](https://github.com/biopapyrus/dl); distinct sections joined by `make_biopapyrus_corpus.py` | 65,007 | `dc4f1e41f2352c15d1c690a8fe6aade9c454d9f6b8892cf853941bba73b459e9` |
| `en-technical` | `d2l-prose.txt` | [Dive into Deep Learning](https://github.com/d2l-ai/d2l-en), English v1.0.3, `make_d2l_corpus_v2.py` | 520,411 | `c88a608b6f26681514bd9c5c2304356b4c942b23ed27410b64c21599d69c551f` |
| `llamacpp-code` | `llamacpp-inference-code.txt` | Selected C/C++ from upstream [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) commit `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`, `make_llamacpp_code_corpus.py --preset inference`; file boundary comments preserved | 1,864,775 | `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` |
| `random-tokens` | *(none)* | Unmodified llama-bench random-token input path | n/a | n/a |

The text/corpus transformations and source version must be kept with future repeat tests. The present data **do not** isolate language, repetition, code density or document genre as independent variables.

## Statistics — group-weighted overall means

For each property `x`, compute `sum(groups_i * x_mean_i) / sum(groups_i)` across **all** rows, rather than taking the unweighted mean of sync rows. Percentages versus random use mean unique counts, not `unique_over_selected`.

| Corpus | Unique mean | Padded mean | Selected mean | Unique / selected | Unique vs random | Instrumented PP tok/s (reference only) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Random tokens | **24,562.67** | 24,688.34 | 131,111.27 | 18.73% | 100.0% | 324.98 |
| Japanese literature | 19,225.61 | 19,352.74 | 131,111.27 | 14.66% | 78.3% | 342.69 |
| Japanese repeated ANLP | 17,406.27 | 17,532.78 | 131,111.27 | 13.28% | 70.9% | 342.71 |
| English literature | 15,424.84 | 15,552.09 | 131,111.27 | 11.77% | 62.8% | 366.77 |
| Japanese technical | 14,471.06 | 14,596.95 | 131,111.27 | 11.04% | 58.9% | 364.43 |
| English technical | 13,396.22 | 13,524.24 | 131,111.27 | 10.22% | 54.5% | 376.44 |
| llama.cpp C/C++ | **11,836.90** | 11,964.69 | 131,111.27 | 9.03% | **48.2%** | 376.34 |

`selected_mean` includes invalid selected slots: `unique/selected` is **not a pure deduplication percentage**. `padded_mean` better approximates actual downstream FA KV work. Stats copying/barriers/readback affect throughput: the last column **must not** be used to claim a union speedup or representative production PP performance.

## KV-bin trend (unique union, group weighted)

| Corpus | KV 32,768–49,151 (3,072 groups) | KV 49,152–65,535 (2,568 groups) | Change |
| --- | ---: | ---: | ---: |
| Random tokens | 23,040.95 | 26,383.05 | +14.5% |
| Japanese literature | 18,236.11 | 20,409.31 | +11.9% |
| Japanese repeated ANLP | 16,917.08 | 17,991.48 | +6.4% |
| English literature | 14,465.03 | 16,573.03 | +14.6% |
| Japanese technical | 13,823.39 | 15,245.83 | +10.3% |
| English technical | 12,774.49 | 14,139.97 | +10.7% |
| llama.cpp C/C++ | **12,487.00** | **11,059.21** | **−11.4%** |

The code slice is the only tested input whose recorded unique union **decreases** in the higher KV bin. Other six inputs increase. This might reflect source structure/token recurrence but requires additional controlled tests. In particular, the Japanese deep-learning text contains sample code, whereas the ANLP baseline is primarily prose with occasional formulas; this is a plausible variable to investigate, **not an established causal explanation**. The technical texts also differ in language, topic, construction and position within the original source.

## Conclusions limited to this dataset

1. The repeated Japanese ANLP input is **not** the smallest-union case; the C/C++ input is smallest, at 48.2% of random, and random is largest. This removes one possible concern that the repeated ANLP input is uniquely favorable to union compaction, but **does not establish its throughput relative to typical production tasks**.
2. Genre/input distribution matters substantially for union statistics: Japanese literature (19.2k) is above the repeated ANLP (17.4k), while English technical (13.4k) and C/C++ (11.8k) are below it.
3. A smaller unique/padded union is not a sufficient performance explanation: other kernels, MoE selection and fallback paths also depend on input. Stats-enabled PP is explicitly instrumented.

## Next: seven-corpus 64k union OFF/ON ordinary PP comparison

Run all seven cases on the **same b11535 binary** with `GGML_VK_QSA_UNION_STATS=0`, the other model/length/batch settings unchanged, and both `GGML_VK_QSA_UNION=0` and `=1`. Use `--prompt-slice head` for real files and native random for the control. Keep environment, order, timestamps, raw prompt counts, input SHA and per-case PP in outputs; ideally use balanced ordering/repetitions later. **OFF is a different attention dispatch path, not an isolated removal of the union compaction step.** Start with one OFF and one ON per corpus (14 measurements; preliminary); extend only if the differences warrant it. Hold 128k selection until results are reviewed.

See [r5 statistics implementation and runtime smoke](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md), [r5 selective port plan](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md), and [benchmarking methodology](BENCHMARKING.md).

## Follow-up normal-speed validation (completed 2026-10-10)

The seven-corpus 64k **STATS OFF** QSA union OFF/ON A/B finished **14/14 OK**; a further **24/24 OK** overnight batch covered three 64k ABBA repeats and six 128k pairs. On the overnight three 64k cases, ON gains repeated at **+25.812%** (repeated Japanese ANLP), **+14.736%** (C/C++), and **+4.899%** (random). At 128k, ON gains were **+69.161%** ANLP, **+74.945%** Japanese novel, **+63.533%** English novel, **+59.868%** English technical, **+46.784%** C/C++, **+53.370%** random. The Japanese technical file is too short for 126,253 tokens. **Full evidence, measurement caveats, and revised Vulkan 128k STATS → ROCm control → Vulkan OFF profiling order** are recorded in [R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md). The preceding “Next” section is retained as the original historical plan and has now been executed.
