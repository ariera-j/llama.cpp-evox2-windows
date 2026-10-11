# r5 Vulkan MTP OFF/ON 64k and 128k ABBA — 2026-10-11

**Status: 8/8 PASS (64k and 128k A1 OFF→B1 ON→B2 ON→A2 OFF).** This is a measured **Vulkan** long-prompt MTP comparison, after the isolated ratio-zero Unsloth draft compatibility guard, in the same-source r5 build. **The r4 indexer-removal and target-QSA-no-op optimizations are absent**; no new performance patch was applied.

## Reproducibility, provenance and scope

- User-supplied ZIP: \`r5-mtp-vulkan-64k128k-abba-20261011-171132.zip\`, SHA256 **\`d4d9f6b08afeed374aaafcdbf0221e66c099b7e1c389a3b29206442a62851e70\`**, 74 entries, including 8 native \`stderr/stdout\`, \`result.json\`, \`conditions.json\`, run-specific resource monitor CSVs, \`summary-abba.csv\`, \`run-info.txt\`. Raw archive remains outside Git. Execution from **17:11 to 17:59 JST**; 10s cooldown; 8/8 \`Status=OK, ExitCode=0\`, 512 generated tokens each.
- **Binary:** Windows Vulkan \`llama-cli.exe\` b11560 / embedded commit \`f8d24494f\`, Clang 20.1.8. Full **source commit \`f8d24494fcacee01f8c9858595c3e778a1698d11\`**, clean on \`investigation/r5-mtp-dense-compat-20261011\`. Executable SHA256 **\`611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949\`**, DLL-group digest **\`be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2\`**, Verified. 96GB UMA label; Radeon 8060S. **Do not substitute the earlier r5 b11530 or ROCm b11560 executable**.
- Unsloth main GGUF \`Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf\`, 81,961,816,672 bytes; MTP ON adds self-contained Unsloth \`mtp-Qwen3.8-Flash-Next-Q8_0.gguf\`, 4,137,429,120 bytes. Model SHA256s not recorded in this run. f16 main/draft K/V, GPU layers=999, CPU MoE=0, batch=2048, ubatch=1024, threads \`-t 4 -tb 4\`, \`-fa auto -fit off --cache-ram 0 --jinja --single-turn --reasoning off --temp 0 --top-p 0.8 -n 512 --seed 1234 --ignore-eos --ctx-checkpoints 0t\`; MTP ON \`draft-mtp\`, draft max 2, p-min 0.
- **Vulkan QSA grouped-union explicitly ON throughout**: \`GGML_VK_QSA_UNION=1\`, \`GGML_VK_QSA_UNION_MIN_KV=32768\`, log \`qsa-union active (r5)\` in **all 8**. \`GGML_VK_PERF_LOGGER\` not set; union stats not enabled. Activation message is **not proof** that union was used in each 2–3 query-token verification batch. The r5 source guard permits \`q->ne[1] = 2..4096\`, so **short-query verification is an actionable hypothesis**, not established execution attribution.
- 64k input \`nlp-survey-ch3-d7-b1.txt\`, **61,789 tokens**; 128k input \`nlp-survey-ch3-d15-b1.txt\`, **126,253 tokens**. Matches previous r5 ROCm ABBA fixtures/contexts; input hashes archived in conditions (see [ROCm ABBA](R5-MTP-ROCM-64K128K-ABBA-2026-10-11.md) for SHA256). Same binary and input across the two repeats of each arm.
- Each arm's measurements below average **two observations**. \`Total\` is **native PP + native TG**, not wall time including model load and teardown.

## Individual runs (original native timings)

| Context | Variant / run start JST | PP tok/s | TG tok/s | PP s | TG s | PP+TG s | Accepted/drafted | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 64k | A1 OFF 17:11:35 | 360.57 | 26.01 | 171.364 | 19.649 | 191.013 | — | OK |
| 64k | B1 ON 17:15:34 | 333.91 | 28.60 | 185.047 | 17.867 | 202.913 | 295/430 (68.605%) | OK |
| 64k | B2 ON 17:19:52 | 334.08 | 29.17 | 184.950 | 17.520 | 202.470 | 295/430 (68.605%) | OK |
| 64k | A2 OFF 17:24:04 | 362.47 | 26.26 | 170.465 | 19.459 | 189.924 | — | OK |
| 128k | A1 OFF 17:28:06 | 336.06 | 24.05 | 375.686 | 21.249 | 396.935 | — | OK |
| 128k | B1 ON 17:35:32 | 304.13 | 23.51 | 415.124 | 21.735 | 436.859 | 295/429 (68.765%) | OK |
| 128k | B2 ON 17:43:39 | 303.80 | 23.44 | 415.585 | 21.799 | 437.384 | 295/429 (68.765%) | OK |
| 128k | A2 OFF 17:51:47 | 334.85 | 24.23 | 377.041 | 21.093 | 398.135 | — | OK |

## Means and r5 MTP effects

| Metric | 64k OFF | 64k ON | ON change | 128k OFF | 128k ON | ON change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| PP tok/s | **361.520** | 333.995 | **−7.61%** | **335.455** | 303.965 | **−9.39%** |
| TG tok/s | 26.135 | **28.885** | **+10.52%** | **24.140** | 23.475 | **−2.75%** |
| Prompt s | 170.914 | 184.998 | **+14.084 s** | 376.363 | 415.354 | **+38.991 s** |
| Generation s | 19.554 | 17.693 | **−1.861 s** | 21.171 | 21.767 | **+0.595 s** |
| Native PP+TG s | **190.468** | 202.692 | **+12.224 s (+6.42%)** | **397.535** | 437.121 | **+39.586 s (+9.96%)** |
| Acceptance | — | 68.605% | — | — | 68.765% | — |

**Result:** At 64k, MTP improves TG modestly but does not amortize the additional prompt time with 512 output tokens. At **128k the observed TG benefit reverses** despite **near-identical acceptance 64k→128k**, and fresh-prompt total time becomes ~10% longer. This is *not* a demonstrated acceptance-quality regression. If the observed generation time/token stayed fixed (unsupported for longer sequences), the 64k PP+TG break-even would be approximately **3,875 tokens**; not a validated estimate for actual long outputs. At 128k MTP generation is slower even before amortizing PP.

For memory assessment, peak sampled **process GPU Local**: 64k OFF/ON **80.614 / 85.572 GiB**; 128k **83.370 / 88.674 GiB**. MTP adds ~4.96 / ~5.30 GiB as Windows process GPU-local counters. GPU **Dedicated** 128k OFF/ON **82.528 / 86.820 GiB**, **Shared** 0.843 / 1.854 GiB. System-wide committed memory sampled peak 64k OFF ~92.4–92.5 / ON ~98.6–98.7 GiB; 128k OFF ~95.2 / ON ~101.8 GiB. **These are accounting counters, not proof of physical UMA placement or predictor of r2 256k safety.** Resource monitoring only sampled, not an allocation trace.

**Output identity:** with temp0/seed1234, the *generated text* in A1/A2 and B1/B2 within each context matches; stdout log endings differ due to printed timing figures. **OFF vs ON generated content differs** in both contexts despite greedy sampling. Acceptance and output quality should not be inferred from tok/s alone. A forced full/partial rejection test was **not** performed in these eight runs. \`graphs reused\` was 507 for OFF vs 210 for ON; different graph-call counts are **not** evidence of a graph-reuse bug.

## Matched 2026-10-11 r2 b10813 ABBA now complete

[**r2 versus r5 MTP TG matched recheck**](R5-MTP-TG-R2-R5-RECHECK-2026-10-11.md) supersedes the **old r2 b10811, temp0.2, variable-length** control as the fairer comparator. The recovered **b10813** binary SHA is `daef251a001809a48cb337cafe858f10fc8d36829302267e2f88248b03e189f5`; MTP TG benefit is **+10.99% at 64k and +16.40% at 128k**, versus current r5 **+10.52% / −2.75%**. The r2 binary has **no build manifest**, which is expected for that historical toolchain; `build-unknown` is an r5 harness metadata parsing limitation. A *cause* has **not** been proved: r2/r3 plain NextN draft attention KV differs from r4/r5 hybrid indexer, acceptance differs, and small-query union eligibility changed. The user currently studies **MTP ON TG only**; PP and MTP OFF TG depth study are parked.

## Historical cross-check: measure relative effects inside a version

| Backend / version | 64k MTP TG ON change | 128k MTP TG ON change | 64k PP ON change | 128k PP ON change |
| --- | ---: | ---: | ---: | ---: |
| **r2 Vulkan, 2026-09-18** | **+14.9%** | **+12.5%** | −4.05% | −4.90% |
| **r4 Vulkan, initial 2026-10-04** | **+15.9%** | **−1.1%** | −7.32% | −9.58% |
| **r5 Vulkan, current** | **+10.52%** | **−2.75%** | **−7.61%** | **−9.39%** |
| r4 ROCm, initial | +20.6% | +5.1% | −6.14% | −6.28% |
| r5 ROCm, current | +22.55% | +9.01% | −6.86% | −6.87% |

Refs: [r2 recovered](R2-MTP-LOG-RECOVERY-2026-10-11.md), [r4 native initial matrix](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md), [r5 ROCm ABBA](R5-MTP-ROCM-64K128K-ABBA-2026-10-11.md). **r2 used single unpaired repetitions with variable output counts, temp 0.2, and the 64k runs had Vulkan PERF_LOGGER on**; r4 also used temp0.2 with 512 generated tokens, while r5 temp0 with 512 generated. Consequently **do not assert a proven r2→r5 code-caused regression** despite striking apparent 128k difference. Rerun archived r2 executable with fixed identical input/seed/temperature/512 output before making that claim.

**Within r5, the main backend split is confirmed:** both Vulkan and ROCm are the same source commit \`f8d24494f\` but different compiler/runtime. At 64k, ROCm native PP OFF 392.30 beats Vulkan union ON PP OFF 361.52; at 128k Vulkan PP OFF **335.46** beats ROCm **294.71**. MTP ON does not remove this PP crossover (64k ROCm 365.39 > Vulkan 334.00, 128k Vulkan 303.97 > ROCm 274.47). MTP relative TG is stronger on ROCm at both context lengths. Neither backend alone explains the universal dense-draft and target bookkeeping costs.

**Hypotheses requiring independent tests:** Draft block 48 uses **dense attention** (ratio0), so its own KV history cost rises with depth; speculative verification has multiple query tokens and potentially uses Vulkan grouped-union (current Vulkan shader source accepts query count 2–4096), whereas ordinary OFF single-token decode falls back. r4 source review already identified draft catch-up and CPU-side indexer layout reconstruction, but these **are not measured individual-phase timings in this archive**. To test small-query union without losing large-batch PP union, add a *separate minimal experimental verification-only guard/counter* on a new branch; do not use a global union OFF comparison as sole causal proof.

## Next gates

1. **Reproduce r2 under matched conditions, first at 64k/128k** if r2 vs r5 long-context MTP performance is the question. Preserve original executable location \`C:\llama-build\llama.cpp-evox2-windows-r2\build-llvm20-r2\bin\Release\`; first log \`--version\`, executable/DLL SHA, 32k or 64k smoke with existing self-contained MTP sidecar, and verify CLI supports \`--seed\` / \`--ignore-eos\` / \`--spec-draft-n-max\`. Original r2 256k **MTP ON not confirmed measured**; do not infer from r2 MTP-OFF PP. A 256k MTP ON request needs a memory/residency guard. MTP ON raises 128k process GPU-local ~5 GiB and 256k r2 MTP OFF was already ~91.4 GiB by historical memo; beware 96GB UMA and Windows shared/committed/pagefile. Use **single 256k smoke/check before ABBA**, not an unattended large sweep.
2. Separately test *small-query Vulkan union* use/cost, r4 dense draft indexer omission/no-op optimizations, and/or phase timing of draft catch-up/host hidden transfers; do not combine mechanisms in first diagnostic run. Current performance/code data do not warrant immediately copying the unsuccessful r2 MTP-QSA prototype.
3. If promoting compatibility fix to pinned r5 stable branch, keep the ratio-zero guard as its own minimal commit, no extra TG patches.

**No source or benchmark modifications were made as part of this analysis.**
