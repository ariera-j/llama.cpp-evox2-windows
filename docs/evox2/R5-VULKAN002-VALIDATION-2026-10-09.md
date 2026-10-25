# r5 VULKAN-002 actual-model 64k/128k/256k validation (pre-stats b11530)

Recorded: 2026-10-09 JST. Branch: `r5/upstream-refresh-20261009`.
**Decision: ACCEPT VULKAN-002 grouped-union opt-in as validated on Evo-X2 for the measured Qwen3.8-Flash-Next Vulkan f16 workloads.** The complete 12-run r5 matrix finished OK; no source rollback or optimization tuning is required before the separate diagnostic build. Keep `GGML_VK_QSA_UNION` **default OFF**. This is a performance and native-kernel acceptance, not a general output-quality or device-portability certification.

## Raw evidence and fixed conditions

Source ZIP kept out of Git: `20261009-194011-878-qwen38-r5-qsa-union-batch.zip` (matrix results, plans, per-run conditions/result/stderr/stdout and resource logs). Matrix ID `20261009-194011-878-qwen38-r5-qsa-union-batch`; start 2026-10-09 19:40:12 JST; end 21:27:11 JST; **12/12 OK, NonOK=0, Complete=true, StoppedEarly=false**, elapsed 106.985 min. Runner source Git identity: `aed2371088c99c5a0a2861a05d15eccac9582a28`, clean checkout. Plan SHA256 `ef34c18c3bc7ff86a6e3baa84668753bb7c7495291ce408cc6795a0e70e78088`.

All 12 runs: `llama-cli` b11530, Clang 20.1.8, executable-embedded commit `9391d35c0`; binary SHA256 `8d45bad26c1460d6bd9c22a4a87389d6ab2855befe939c0a2e3e42297d33714f` and runtime digest `5d83efa4cb808e1e69fb38964c7992ae22f940c986ce0c18d096f72d75390579` identical across runs, runtime verified. Vulkan0 Radeon 8060S, UMA label 96GB. Fixed `f16` K/V, `-b 2048 -ub 1024 -t 4 -tb 4 -ngl 999 -ncmoe 0`, Flash Attention auto, fit off, cache-ram 0, context checkpoints 0t, MTP OFF, seed 1234, temperature 0.2, top-p 0.8, fixed 512 generated tokens with ignore-EOS, resource monitor ON. No profiler or union diagnostic statistics enabled. `GGML_VK_QSA_UNION` was the OFF/ON toggle; min KV remained default 32768. Old `GGML_VK_MOE_LEGACY_TILE_SELECTION`, `GGML_VK_GET_ROWS_128X4` controls were **unset** (not the same implementation/settings as r4).

| Context | Prompt tokens | Source file | Input SHA256 |
|---|---:|---|---|
| 64k | 61,789 | `nlp-survey-ch3-d7-b1.txt` | `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` |
| 128k | 126,253 | `nlp-survey-ch3-d15-b1.txt` | `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` |
| 256k | 255,181 | `nlp-survey-ch3-d31-b1.txt` | `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` |

Source hashes and prompt tokens exactly match r4's [VULKAN-002 acceptance](R4-VULKAN002-VALIDATION-2026-10-04.md). Original is the three-shard Unsloth UD-IQ3_XXS; PLE16 is the transformed `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`. Full model SHA256 was not computed (large files), so only file identity/path/length available in per-run conditions.

## r5 observed PP/TG and ON/OFF effect

PP and TG are native `llama-cli` prompt-eval and generation timing statistics in tokens/second. For ABBA contexts, average the **two tok/s observations per setting**, exactly as r4 reported; for 128k and 256k there is **only one observation per setting**.

| Model | Context | A1 OFF PP | B1 ON PP | B2 ON PP | A2 OFF PP | OFF mean | ON mean | ON PP gain | TG OFF mean | TG ON mean |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Original | 64k | 270.67 | 342.21 | 341.66 | 270.81 | **270.74** | **341.94** | **+26.30%** | 25.58 | 25.89 |
| PLE16 | 64k | 270.34 | 339.64 | 339.32 | 270.18 | **270.26** | **339.48** | **+25.61%** | 25.97 | 25.80 |
| PLE16 | 128k | 179.34 | 307.15 | — | — | **179.34** | **307.15** | **+71.27%** | 24.03 | 23.53 |
| PLE16 | 256k | 135.10 | 277.68 | — | — | **135.10** | **277.68** | **+105.54%** | 20.19 | 20.12 |

PP time reduction: 64k Original average approx 47.52 s; 64k PLE16 approx 46.62 s; 128k PLE16 292.93 s; 256k PLE16 969.82 s. The earlier isolated 64k PLE16 sanity OFF/ON was 269.44→338.71 tok/s (+25.71%), consistent with this ABBA (270.26→339.48).

OFF logs consistently reported `QSA grouped-union = off (group=64, min_kv=32768)`, without activation. **All 6 ON runs** logged `QSA grouped-union = on`, plus `qsa-union active (r5)` with group=64, path=1, Br=16, Bc=64, min_kv=32768 and an expected `qsa-union fallback: query count or KV threshold`. On activation, the first full-ubatch message used groups=16, capacity=32768 and scratch=73400576 bytes (not a full-run memory peak). All 12 runs used the same executable.

## Direct comparison with r4 b11390

Source of r4: [`R4-VULKAN002-VALIDATION-2026-10-04.md`](R4-VULKAN002-VALIDATION-2026-10-04.md). r4 64k/128k/256k are ABBA **two per setting**, whereas r5 128k/256k are single OFF→ON pairs. r4 used the legacy Vulkan MoE tile switch `GGML_VK_MOE_LEGACY_TILE_SELECTION=1`, r5 uses refreshed upstream with that retired switch unset; compiler/driver/OS/session and QSA surrounding code differ. Cross-generation differences **are descriptive**; the same-r5 OFF/ON gains are the rigorous observations.

| Model/context | r4 OFF PP | r4 ON PP | r4 union PP gain | r5 OFF PP | r5 ON PP | r5 union PP gain | r5 ON vs r4 ON |
|---|---:|---:|---:|---:|---:|---:|---:|
| Original 64k | 269.08 | 337.45 | +25.41% | 270.74 | 341.94 | +26.30% | +1.33% |
| PLE16 64k | 268.42 | 335.38 | +24.95% | 270.26 | 339.48 | +25.61% | +1.22% |
| PLE16 128k | 178.97 | 295.68 | +65.21% | 179.34 | 307.15 | +71.27% | +3.88% |
| PLE16 256k | 132.96 | 266.75 | +100.62% | 135.10 | 277.68 | +105.54% | +4.10% |

The ON PP is numerically faster at all four tested rows. Especially 128k and 256k show preserved or stronger same-build OFF→ON PP gains. **Do not claim** the r5-vs-r4 numerical speed difference comes solely from an improved union shader: this is a different upstream/MoE combination and different run sequence.

### TG and caution

| Model/context | r4 TG OFF/ON | r5 TG OFF/ON | r5 ON/OFF change |
|---|---|---|---:|
| Original 64k | 24.72 / 24.82 | 25.58 / 25.89 | +1.21% |
| PLE16 64k | 25.30 / 25.40 | 25.97 / 25.80 | −0.65% |
| PLE16 128k | 23.22 / 23.28 | 24.03 / 23.53 | **−2.08%** (one pair; monitor) |
| PLE16 256k | 19.58 / 19.59 | 20.19 / 20.12 | −0.35% |

There is **no compelling broad TG regression**; however, retain 128k's ~2% one-pair ON dip as a follow-up if decode optimization becomes important. The 64k ABBA run-to-run PP spread is small (Original OFF 270.67/270.81, ON 342.21/341.66; PLE16 OFF 270.34/270.18, ON 339.64/339.32).

Resource logs were collected for all runs. During 256k PLE16, the resource monitor recorded peak target GPU local commitments ~88.30 GiB OFF/~88.57 GiB ON, with no run failure. This metric is not directly a QSA scratch peak. stderr emitted the same cache-idle-slots, reasoning template and unauthenticated loopback server warnings across modes; those are not compilation or Vulkan operator failure events. No output-content equality or generation quality equivalence is claimed; sampling temperature 0.2 may produce different text.

## Decision and next gate

1. **Accept VULKAN-002 opt-in**, default OFF; r5 has both GPU 18/18 OFF + 18/18 ON correctness and normal-model same-binary PP evidence through 256k.
2. Preserve the b11530 executable, its binary SHA256 and these raw archives as **pre-stats normal-performance baselines**. The r5 [stats source port](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md) was committed later; it must be built in a **new directory** and checked with `GGML_VK_QSA_UNION_STATS=0` for regression against the relevant pre-stats measurements. The 64k **PLE16 ABBA ON mean 339.48 tok/s** is the stronger comparison than the earlier 338.71 single run.
3. Then validate `STATS=1` produces nonempty, correctly binned CSV and `dropped_groups=0`. Its PP values are *not* speed baselines.
4. Longer-term, compare fixed-token-count Japanese/English literary, technical and code sources after preserving per-input source commit/manifest/token counts. This is an exploration of *input distribution*, not yet a document-type causality study.

The r5 actual-model measurements are complete. The stats feature is source-ported but **its new Windows compile/runtime/CSV remains pending**, independently of this acceptance.
