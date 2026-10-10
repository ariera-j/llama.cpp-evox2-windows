# r5 ROCm vs Vulkan corpus-dependent PP at 64k and 128k (2026-10-10)

Status: **ROCm 64k 7/7 and 128k 6/6 complete; same-corpus comparisons against previously measured Vulkan QSA union OFF/ON**. This report compares **backend-specific PP behavior**, not an identical attention algorithm across backends. Branch: `r5/upstream-refresh-20261009`. Prior [Vulkan 64k/128k normal-throughput report](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md) and [Vulkan union diagnostics at 128k](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md).

## Raw evidence / validation

Two user-submitted ROCm ZIPs (not checked into Git):
- `20261010-105758-811.zip`: ROCm 64k, **7/7 OK**; manifest `COMPLETE`, 2026-10-10 **10:57:58–11:38:57 JST**, 40 min 59 sec.
- `20261010-114203-549.zip`: ROCm 128k, **6/6 OK**; manifest `COMPLETE`, 2026-10-10 **11:42:03–13:10:23 JST**, 88 min 20 sec.
- Each archive includes batch manifest, plan/runs CSV, and per-corpus `conditions.json`, `result.json`, raw llama-bench JSON, stdout/stderr, and `summary.csv`. All 13 `result.json` native rows were individually re-read for this report rather than relying only on aggregate CSV values.

Fixed ROCm conditions: Evo-X2 Ryzen AI Max+ 395 / Radeon 8060S, reported UMA label 96 GB; **ROCm `llama-bench` b11543**, Clang 23.0.0, embedded commit `28d0f32d0`, clean repository commit `28d0f32d02ae46a137c34c50240aaab4432fd956`; executable SHA-256 **`fc6559c7cc6f07063fe4c44ab94f29a380598d26b3902bc0c90ba99847b8872c`** for all 13 runs, backend reported **ROCm0** only. PLE16 GGUF `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`, recorded file size **81,961,816,672 bytes**, same path as the Vulkan comparison. The full model SHA-256 was not recorded, so identity is supported by name/path/size rather than full hash.

Common settings: `-b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -n 0 -d 0 -r 1`, **warmup ON**, no MTP, PP only (no TG), context 65536 with **61789 tokens** for 64k or context 131072 with **126253 tokens** for 128k. Text inputs use the real-file extension to llama-bench with `--prompt-slice head`, i.e. tokenizer output from the first N tokens, **not a chat-templated prompt**. The standard native random-token mode uses no input file. All six real-file SHA-256 values in the 64k run and all five in 128k match the corresponding Vulkan study's source identities (see corpus manifest in the linked report). Japanese technical has 65,007 raw tokens and was excluded from 128k rather than padded/repeated.

Environment recorded by ROCm runs includes `HIP_PATH`, `HIP_PATH_72`, and `VULKAN_SDK`. The ROCm binary is a new build from r5 source with real-file llama-bench support (previous ROCm binary contained only COMMON-001). Vulkan comparator: **b11535**, Clang 20.1.8, SHA-256 `9d32422898d4c8038acc3da9c8e3045841726d8cf1df6cea2e68241e4c707159`, earlier experiment. Its opt-in grouped-union QSA feature is Vulkan-only; ROCm has **neither a Vulkan union ON nor an equivalent union OFF mode**. No Vulkan union stats instrumentation was enabled for the normal PP comparator.

User-reported ambient conditions differed: about **22°C** during the previous evening's Vulkan run versus about **27°C** around this day's ROCm run; these are approximate room temperatures, **not GPU temperature/clock telemetry**. Runs were on different sessions and binaries. No clock/power/thermal normalization or A/B interleaving across backends. Each ROCm corpus was measured only once per context, so small (~1–5%) rank differences cannot be treated as stable without repeats.

## 64k: 7-corpus results, PP tok/s

Vulkan values are from the prior `STATS=0` study; **for ANLP, C/C++ and random use the repeat 64k ABBA means**, while the four other Vulkan corpus results are single observations. ROCm has one timed repetition per input.

| Corpus | Vulkan OFF | Vulkan ON | ROCm | ROCm vs Vulkan OFF | ROCm vs Vulkan ON |
| --- | ---: | ---: | ---: | ---: | ---: |
| Repeated Japanese ANLP | 272.344 | 342.640 | **394.030** | +44.7% | +15.0% |
| Japanese literature (*I Am a Cat*) | 285.479 | 344.105 | **404.027** | +41.5% | +17.4% |
| English literature (*Count of Monte Cristo*) | 304.394 | 368.631 | **405.360** | +33.2% | +10.0% |
| Japanese technical (biopapyrus) | 299.235 | 366.032 | **397.652** | +32.9% | +8.6% |
| English technical (D2L) | 312.423 | 378.992 | **398.776** | +27.6% | +5.2% |
| llama.cpp source C/C++ | 329.465 | 378.014 | **394.669** | +19.8% | +4.4% |
| Native random tokens | 308.245 | 323.346 | **415.821** | +34.9% | +28.6% |

Fastest / slowest PP ratio (`max / min - 1`) across seven inputs: **Vulkan OFF 20.9%**, **Vulkan ON 17.2%** with updated three-corpus ABBA means (**16.9%** when using original seven single-pair runs), **ROCm 5.5%**. ROCm real-text only: 405.360 vs 394.030 tok/s, **2.9%** spread; thus its detailed corpus ranking should not be overinterpreted. ROCm random 415.821 tok/s is highest; Vulkan union ON native random is slowest in its seven-corpus set. ROCm was faster than both measured Vulkan modes for all seven at 64k.

## 128k: 6-corpus results, PP tok/s

| Corpus | Vulkan OFF | Vulkan ON | ROCm | ROCm vs Vulkan OFF | ROCm vs Vulkan ON |
| --- | ---: | ---: | ---: | ---: | ---: |
| Repeated Japanese ANLP | 183.660 | 310.682 | **296.274** | +61.3% | −4.6% |
| Japanese literature | 168.064 | 294.020 | **301.542** | +79.4% | +2.6% |
| English literature | 204.938 | 335.141 | **302.224** | +47.5% | −9.8% |
| English technical (D2L) | 214.921 | 343.589 | **298.894** | +39.1% | −13.0% |
| llama.cpp C/C++ | 236.129 | 346.600 | **296.075** | +25.4% | −14.6% |
| Native random tokens | 170.615 | 261.673 | **308.215** | +80.6% | +17.8% |

Input spread (`max/min-1`) at 128k: **Vulkan OFF 40.5%**, **Vulkan ON 32.5%**, **ROCm 4.1%**. ROCm remains relatively flat across inputs: **296.075–308.215** tok/s. Vulkan OFF spans **168.064–236.129**, and Vulkan ON spans **261.673–346.600** tok/s. Four of six Vulkan ON runs exceed the corresponding ROCm PP (ANLP, English literature, English technical, C/C++); ROCm is faster for Japanese literature and random. Vulkan ON and ROCm use different kernel strategies; cross-backend ratio cannot isolate a single optimization.

## 64k → 128k PP changes

The 64k run takes the first 61,789 tokens, 128k takes the first 126,253 tokens; **both context length and the latter portion of the source content change**. This comparison therefore does not isolate pure KV-length cost, although it does show within-backend workload scaling for these test inputs.

| Corpus | Vulkan OFF | Vulkan ON | ROCm |
| --- | ---: | ---: | ---: |
| Repeated Japanese ANLP | −32.56% | −9.33% | **−24.81%** |
| Japanese literature | −41.13% | −14.56% | **−25.37%** |
| English literature | −32.67% | −9.08% | **−25.44%** |
| English technical (D2L) | −31.21% | −9.34% | **−25.05%** |
| llama.cpp C/C++ | −28.33% | −8.31% | **−24.98%** |
| Native random | −44.65% | −19.07% | **−25.88%** |

ROCm's six input-specific PP drops lie between **−24.81% and −25.88%** (spread **1.07 percentage points**). The corresponding Vulkan OFF drops span **−28.33% to −44.65%**; Vulkan ON spans **−8.31% to −19.07%**. This contrast strongly motivates investigating the input-dependent **Vulkan Flash Attention dispatch path**, but **does not prove** FA (rather than MoE, indexer or memory behavior) is the complete explanation.

## Interpretation and next work (priority agreed with user)

1. **COMPLETED:** 64k seven-input and 128k six-input ROCm real-file comparison; both manifests COMPLETE, **13/13 OK**. ROCm corpus ranking differs from Vulkan and varies far less at both context lengths. Since the ROCm spread is only ~4–6% including random, repeat or interleave the extreme cases before any firm claim about ROCm ranking.
2. **NEXT — investigate Vulkan QSA union OFF without first changing source.** Study the existing fallback Flash Attention dispatch in `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: after failed `ggml_vk_qsa_union()`, the code calculates `use_sparse` based on `n_kv_max`, `KV`, `gqa_ratio`, dtype and tuning path, then can perform `fa_sparse_compact` and split-K. The code includes the diagnostic switch `GGML_VK_FA_SPARSE_DISABLE`: **any defined value disables sparse, including '0'**, since it tests environment-variable *presence*, not a Boolean value. Compare regular Vulkan union OFF with union OFF **and sparse disabled** using the **same b11535 binary**, model, text hashes, and all other settings.
3. **Conservative first gate:** 64k, real-text `ja-literature` vs `llamacpp-code` plus `random` if convenient. Run union OFF with `GGML_VK_FA_SPARSE_DISABLE` **absent** and present (`1`), separately for each input; start with a small smoke first since dense FA fallback can be slower and scratch/workload may increase. Preserve separate-process environment, full logs, and PP. Observe if the literature/code gap changes. Do **not** automatically regard an observed speed change as proof that sparse FA was actually selected; log/profiler evidence for `use_sparse` is necessary.
4. If the first gate implicates sparse FA, consider an appropriately bounded 128k test on Japanese literature and code, or add *temporary diagnostic counters/one-time logs* for actual FA dispatch without changing algorithms. If the sparse disable switch does not explain the difference, inspect whether OFF is falling into sparse, mask-opt, dense, different split-K or other paths and then use RGP for high-cost kernels. Reassess priorities from actual results rather than assuming sparse is the cause.
5. **Deferred:** MTP performance changes, ROCmFP4 support and TG task/genre comparisons (Japanese/English long-form and code generation) until the Vulkan OFF input-distribution question reaches a stopping point.

No code changes or binary builds are required for the proposed initial sparse-disable A/B. The raw ZIPs remain private/local.
