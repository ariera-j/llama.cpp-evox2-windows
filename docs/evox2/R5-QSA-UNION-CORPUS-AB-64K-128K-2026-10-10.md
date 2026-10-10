# r5 QSA union — real-prompt 64k ABBA and 128k OFF/ON, plus ROCm triage plan

Recorded: 2026-10-10 JST. Branch: `r5/upstream-refresh-20261009`. This is **normal PP throughput**, measured with optional QSA union diagnostics disabled. Complements the [seven-corpus 64k union statistics report](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md) and [r5 b11535 validation](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md).

## Raw evidence / verification

Three user-provided result ZIPs; **not committed**:
- `20261010-002749-656.zip`: 64k single OFF/ON pairs across 7 corpora; 14/14 success, comparison CSV `qsa-64k-union-ab-pairs.csv`.
- **Main repeat experiment** `20261010-022801-440.zip`: overnight 64k ABBA for 3 corpora and 128k OFF/ON for 6 corpora; `batch-manifest.json`, `overnight-plan.csv`, `overnight-runs.csv`, `overnight-pairs.csv`, and per-run raw logs/results/conditions. **24/24 OK, ExitCode=0, manifest COMPLETE**, 2026-10-10 **02:28:01–07:31:34 JST** (~5 h 04 min).
- Initial 64k stats: `20261009-232215-046.zip` + random control `20261009-235450-253.zip`; see linked stats report.

For overnight runs, **all 24** independently checked against `result.json` and `conditions.json`: same `llama-bench.exe` **b11535** (Clang 20.1.8; executable embedded commit `fbb6e15bd`; SHA-256 `9d32422898d4c8038acc3da9c8e3045841726d8cf1df6cea2e68241e4c707159`), Vulkan/AMD Radeon 8060S, PLE16 GGUF at the same recorded path and 81,961,816,672-byte size, no full model SHA, clean r5 checkout at `de65697c647eb7f918ccb6818f4176013be4f41c` at measurement time (distinct from embedded executable source commit). Model: Qwen3.8-Flash-Next UD-IQ3_XXS PLE16. Device's labeled UMA: 96GB.

Shared PP settings: `-b 2048 -ub 1024 -ctk f16 -ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto -n 0 -d 0 -r 1`, **warmup enabled** (`NoWarmup=false`), no MTP, no sampled generation, `GGML_VK_QSA_UNION_MIN_KV=32768`, `GGML_VK_QSA_UNION_STATS=0`; only `GGML_VK_QSA_UNION=0/1` changes per A/B pair. Six real inputs use patched real-prompt `llama-bench -f` and **head** slice of tokenized text, no chat template or instruction appended for this test. Random uses native llama-bench random-token path, no `-f` or input file SHA. Same file hashes as the linked seven-corpus provenance report for each text. Every ON stderr contains `qsa-union active (r5)` and fallback evidence; OFF stderr has no activation. These results test **PP** only; no TG or text quality.

Caveats: 64k three-corpus repeat has 2 timed samples per mode in ABBA, but other 64k cases and all 128k cases have just **one** sample per mode. A PowerShell run starts a fresh process per measurement; physical clock/temperature, RAM/system state and order may still affect comparisons. There is no per-kernel profiling. `OFF` reverts to Vulkan's other FA dispatch (including eligible sparse FA), **not** an ablation that removes only deduplication. Random-token identity between different binaries/backends is not verified by file hash.

## 64k initial 7-corpus same-binary A/B — 2026-10-10, 61,789 raw tokens, ctx 65,536

| Input | OFF PP tok/s | ON PP tok/s | ON gain |
| --- | ---: | ---: | ---: |
| Repeated Japanese ANLP | 272.362 | 342.858 | +25.883% |
| Japanese novel (*I Am a Cat*) | 285.479 | 344.105 | +20.536% |
| English novel (*Count of Monte Cristo*) | 304.394 | 368.631 | +21.103% |
| Japanese technical (biopapyrus) | 299.235 | 366.032 | +22.323% |
| English technical (D2L) | 312.423 | 378.992 | +21.307% |
| llama.cpp C/C++ | 329.275 | 377.754 | +14.723% |
| Native random tokens | 308.390 | 324.074 | +5.086% |

All seven showed higher PP ON. Gain is **not monotonic** with the measured ON-path unique union size: the shortest 64k union was C/C++, yet its 14.7% gain was lower than repeated Japanese ANLP's 25.9%. OFF itself has significant input dependence.

## 64k three-corpus overnight ABBA repeat — 2026-10-10, 61,789 raw tokens, ctx 65,536

Each per-corpus order was `OFF → ON → ON → OFF`; means computed as arithmetic average of the two tok/s observations per mode (consistent with existing r4/r5 A/B reporting).

| Corpus | OFF samples | ON samples | OFF mean | ON mean | ON gain | Prior single-pair gain |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Repeated Japanese ANLP | 272.399 / 272.288 | 342.454 / 342.825 | **272.344** | **342.640** | **+25.812%** | +25.883% |
| llama.cpp C/C++ | 329.460 / 329.470 | 378.229 / 377.798 | **329.465** | **378.014** | **+14.736%** | +14.723% |
| Random tokens | 308.400 / 308.090 | 323.238 / 323.455 | **308.245** | **323.346** | **+4.899%** | +5.086% |

The relative ordering and near-identical gains repeat the first 64k observation. This gives good local repeatability, not a general cross-device confidence interval.

## 128k six-corpus overnight A/B — 2026-10-10, 126,253 raw tokens, ctx 131,072

Japanese technical source has only **65,007** available raw tokens and was deliberately excluded rather than repeating/padding; all other six inputs include the random control. Case order alternated between OFF→ON and ON→OFF; one measurement per mode.

| Corpus | OFF PP tok/s | ON PP tok/s | ON gain |
| --- | ---: | ---: | ---: |
| Repeated Japanese ANLP | 183.660 | 310.682 | **+69.161%** |
| Japanese novel (*I Am a Cat*) | **168.064** | 294.020 | **+74.945%** |
| English novel (*Count of Monte Cristo*) | 204.938 | 335.141 | +63.533% |
| English technical (D2L) | 214.921 | 343.589 | +59.868% |
| llama.cpp C/C++ | **236.129** | **346.600** | +46.784% |
| Native random tokens | 170.615 | **261.673** | +53.370% |

OFF varies from **168.064 to 236.129** tok/s (fastest is **40.5%** faster than slowest). ON varies from **261.673 to 346.600** tok/s (fastest **32.5%** faster than slowest). Both paths are input-dependent. Larger 128k OFF→ON gains mainly arise because OFF degrades more sharply as context extends, rather than ON speeding up with context.

### Relative PP decrease from 64k to 128k

Use the new 64k ABBA means for ANLP, C/C++ and random; use the initial 64k pair for the remaining three corpora. These are **different source slices** (leading 61,789 versus 126,253 tokens of the same raw file), so the table captures both longer KV and additional content, not solely a pure length effect.

| Corpus | 64k OFF → 128k OFF | 64k ON → 128k ON |
| --- | ---: | ---: |
| Repeated Japanese ANLP | −32.6% | −9.3% |
| Japanese novel | −41.1% | −14.6% |
| English novel | −32.7% | −9.1% |
| English technical (D2L) | −31.2% | −9.3% |
| llama.cpp C/C++ | −28.3% | **−8.3%** |
| Random | **−44.6%** | −19.1% |

Previous pre-stats `llama-cli` 128k repeated ANLP result: **179.34 OFF → 307.15 ON tok/s (+71.27%)**. The new `llama-bench` **183.66 → 310.68 (+69.16%)** is close, though input templating, program/method and source slice are not guaranteed identical; this is a qualitative cross-check.

## Interpretation / open questions

1. **Do not equate union size with gain percentage.** 64k stats ON measured a strong descriptive relation between smaller union and faster *ON-path* PP across the seven cases; however, OFF PP follows a different distribution and dispatch. The ratio ON/OFF need not follow union-size ordering.
2. **Input-dependent OFF cost is real in these same-binary measurements, but its exact cause is unknown.** Candidates: Vulkan sparse FA compact/gather/mask paths, memory locality, indexer/key selection structure, non-FA model kernels. No profiling evidence yet isolates them.
3. Relative gain expands at 128k (46.8–74.9%, all six) compared with 64k (5.1–25.9%, seven), consistent with a longer share of prefill above QSA union's default `MIN_KV=32768` and greater long-KV work. This does not prove which kernel accounts for the gap.
4. Prompt wording or document genre alone is **not** established as the cause. The repeated ANLP file for these real-prompt bench tests is the **256k corpus sliced from the head**; its end-of-document “please summarize” instruction was not included at 64k/128k. The source starts with an instruction to read through, but this test does not isolate its effect.

## Agreed next experiment order (before Vulkan OFF profiling)

**A. Vulkan 128k union diagnostics on three sources first.**
- `ja-literature`, `llamacpp-code`, `random-tokens`, with **the same 126,253-token head/random workload** and `-c 131072`, `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_STATS=1`, `GGML_VK_QSA_UNION_STATS_KV_BIN=16384`, ideally `--no-warmup` and `-r 1` as in the prior 64k STATS runs. Verify `dropped_groups=0`, same source SHA, activation, and weighted union by KV-bin. **Stats-on PP is diagnostic only.** Continue only if 128k diagnostics show meaningful distributions; include repeated ANLP later as a useful reference if needed.

**B. ROCm cross-backend control before GPU profiling.**
- **First 64k all seven inputs** (including the 65,007-token Japanese technical source), `-p 61789 -c 65536`. Use same exact PLE16 GGUF, same input source SHA, `--prompt-slice head`, batch/ubatch, K/V f16, MTP off, zero generation/depth, warmup and comparable repetitions. For random use original llama-bench path.
- Because the most striking OFF differences emerge at **128k**, follow with **128k six eligible inputs** (`-p 126253 -c 131072`) when feasible. A 64k-only ROCm sweep **cannot adjudicate the 128k input-specific OFF divergence**. To economize, 128k can initially use Japanese novel, C/C++, random plus repeated ANLP; if necessary expand to the other two eligible inputs.
- ROCm has **no `GGML_VK_QSA_UNION` grouped-union implementation** in these changes. Do **not** describe ROCm as Vulkan “union OFF” nor compare `GGML_VK_QSA_UNION=1/0` as though it affected ROCm. ROCm uses its own FA/kernel implementations; treat it as an **independent backend baseline** to compare within-backend input rankings, per-input PP ratios, and 64k→128k change against Vulkan OFF and ON. Match settings, model and SHA, but do not ascribe cross-backend absolute t/s differences to one kernel.
- **Build requirement:** the pre-existing clean ROCm executable may predate the native `llama-bench -f/--prompt-file` Phase A addition (b11526). Confirm `llama-bench.exe --help` advertises `-f`, `--prompt-slice`, and `-c`; if not, build ROCm from a current r5 source commit in a **separate build directory**. Verify ROCm/AMD Radeon 8060S device detection, no Vulkan backend, load of the same PLE16 model, and a small real-prompt smoke before long runs. ROCm build and Vulkan build cannot have the same binary SHA, so record each binary source commit and settings.
- A similar input ranking on both backends would point toward upstream/model/QSA-distribution or broadly shared costs; a conspicuous difference could narrow investigation to backend-specific FA, memory layouts or kernel selection. Neither outcome alone proves the responsible code path.

**C. Vulkan OFF GPU profiling only after A+B.**
- Compare the Japanese novel and C/C++ at 128k for Vulkan OFF, plus random if practical, using suitable per-kernel timing/profiling. Confirm actual fallback/sparse/dense dispatch selection; use same input SHA and no diagnostic stats. Reassess profiling priorities after ROCm results.

Raw ZIPs, GGUF and large corpora stay out of Git. Avoid inferring that the repeated ANLP is representative of all business documents: these tests demonstrate variability across the selected sources, not production-wide distributions.

## 128k three-corpus union diagnostics — completed 2026-10-10

The planned 128k STATS ON comparison of Japanese literature, llama.cpp C/C++ and random-token input is **complete (3/3 OK)**. Each run recorded 93 rows / 17,724 groups, zero dropped groups, and unique union means **22,798.57**, **14,155.45**, and **29,598.36** respectively. Code unique union fell in the 48–64k KV bin, then grew through 128k. Methodology, group-weighted six-bin table, SHA-256 and run audit are in the standalone [128k three-corpus QSA union diagnostics report](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md). **The next step is ROCm real-document llama-bench comparison**, with a fresh current-r5 ROCm build since the existing COMMON-001 ROCm binary lacks the prompt-file extension; Vulkan OFF profiling is intentionally deferred until after ROCm results.
