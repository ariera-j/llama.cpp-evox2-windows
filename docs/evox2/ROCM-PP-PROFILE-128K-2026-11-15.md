# Windows ROCm r6: 128K old-IQ3 prefill op events compared with 64K and Strata (2026-11-15)

**Status**: 128K ONE RUN completed and segmented/verified from raw private ZIP. The profiler is diagnostic/instrumented and timing comparisons are **not** an unprofiled performance benchmark. No source-code fix is required to collect these results.

## Provenance

- ZIP supplied by user: `20261115-025355-998-cli-rocm-b11933-ctx131072-fb4e4924974c.zip`, SHA256 `0dc8946f455ce1a131ac001e60c8d0a7c3eb428ac71529aed022851c50844513`. Raw logs and private Japanese paper are **not committed to GitHub**.
- Tool `tools/evox2/benchmark/Measure-LlamaCli.ps1`; run 2026-11-15 02:53:56–03:01:49 JST; status `OK`, exit0.
- `llama-cli` b11933, commit `9ae6f153945fc9a67134732f2e5895553c3d7d23` from dedicated branch `r6/rocm-pp-timing-20261115`, Radeon 8060S `gfx1151`, HIP/ROCm TheRock SDK 10.0.0, compiler Clang 23, Windows 11 Pro, **UMA64GB** (current manual label correctly fixed; Windows-visible physical memory 63.65 GiB), remote/RDP active.
- Original old Unsloth Qwen3.8 Flash Next `UD-IQ3_XXS`, **3-shard**, original August 29 2026 GGUF, same as the 64K run and Strata experiments.
- Japanese paper `nlp-survey-ch3-d15-b1.txt`, SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, `126253` prompt tokens. Model offloaded `49/49` GPU layers; model buffers CPU 27465.95 MiB, ROCm0 50191.17 MiB, ROCm_Host 497.31 MiB.
- Flags: `-c 131072 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -fit off --cache-ram 0 --reasoning off --spec-type none -n 8 -lv 4`; MTP/drafting OFF; temp0; `GGML_EVOX2_PP_TIMING=1` enabled. The 128K cache buffers are ROCm0 standard KV 3072MiB + indexer KV 768MiB.
- CLI reports **PP 424467.14ms / 126253 tokens = 297.44 tok/s**, and TG 456.66ms / 8 output tokens = 15.33 tok/s. The `output.log` and `stderr.log` contain the full op profiler lines.

## Profiler segmentation and complete PP results

Raw `stderr.log`: **134** `evox2 pp timing:` entries; **2** pre-prompt setup/warmup, **124** prompt-backend graph invocations bounded by `new prompt, ... task.n_tokens = 126253` and `progress = 1.00, n_tokens = 126249`, **8** generation/decode graph calls afterwards. These boundaries avoid attributing decode timing to PP; 4 final prompt tokens are handled in the transition to generation. All 124 selected calls have the same `nodes=6540, fa_n=12, qsa_select_n=36, moe_id_n=141, gdn_core_n=72, hc_fused_n=95, concurrent=0`. These counts are events of **GGML ops**, not the number of QSA layers and not the same stages as Strata.

The category events are recorded on the primary backend stream and `cudaDeviceSynchronize` is used at graph end; each event interval may contain host/queue gaps. `concurrent=0` means the instrumentation recorded no concurrent graph-work markers; it is not proof of absence of all GPU activity outside the stream. The residual is **total minus observed subtotals** and is an approximate bucket only.

| GGML classification | 64K 61 prompt calls (s) | 128K 124 prompt calls (s) | 128K / 64K | 64K share | 128K share |
|---|---:|---:|---:|---:|---:|
| **FA `FLASH_ATTN_EXT`** | **44.351** | **189.788** | **4.28×** | 28.72% | **45.00%** |
| **MoE `MUL_MAT_ID`** | 46.807 | 97.605 | 2.09× | 30.31% | 23.14% |
| **QSA select/Indexer** | 2.587 | 10.638 | **4.11×** | 1.68% | 2.52% |
| GDN core (selected op roots) | 4.628 | 9.659 | 2.09× | 3.00% | 2.29% |
| HC fused (selected op roots) | 3.370 | 6.773 | 2.01× | 2.18% | 1.61% |
| Unclassified/residual | 52.664 | 107.304 | 2.04× | 34.11% | 25.44% |
| **Summed primary-stream event timeline** | **154.406** | **421.768** | **2.73×** | 100% | 100% |
| **llama backend PP reported** | **155.609** | **424.467** | **2.73×** | — | — |

64K prompt tokens 61789 →128K 126253 = **2.0433×**. At constant per-token cost, the 128K event total would be 154.406 × 2.0433 = **315.50s**; observed **421.77s**, **106.27s** more than token-proportional. FA alone would grow to 44.351 × 2.0433 = **90.62s**, but is **189.79s**, **99.17s** above proportional. Hence about **93% of the extra above-linear 128K GPU event time is associated with the observed FA intervals** across these two runs; this is an *empirical accounting of event duration*, **not** proof the extra delay comes exclusively from FA device instructions, given queue/host stalls and instrumentation effects. QSA select accounts for much of the remainder. Changing 64K vs128K text could change kernel mixtures, but per-GGML-graph counts remain identical and both runs use same model and flags (apart from context/file/UMA label).

### 8,192-token microbatch windows, 128K run

Each full window consists of eight consecutive **1024-token GGML graph calls**. Last interval has just 4 graph calls (incl. a short tail) and is omitted from the equal-work table.

| Range of input processed | GPU total (s) | FA (s) | MoE ID (s) | QSA select (s) |
|---|---:|---:|---:|---:|
| 0–8K | 14.788 | 0.692 | 5.787 | 0.075 |
| 24–32K | 20.069 | 5.436 | 6.325 | 0.318 |
| 48–56K | 25.288 | 10.311 | 6.384 | 0.592 |
| 64–72K | 28.797 | 13.610 | 6.410 | 0.767 |
| 88–96K | 33.947 | 18.494 | 6.389 | 1.028 |
| 112–120K | 39.325 | 23.578 | 6.423 | 1.279 |

FA increases from 0.692 to 23.578s for equal 8K token work (~34×), MoE ID remains ~5.8 to 6.4s and the residual stays around 6.9–7.0s per full 8K interval. These data confirm the *intra-run* KV-length-related increase rather than relying solely on 64K-to-128K whole-run ratios.

**Interpretation**: in llama r6, QSA (particularly its FA compute/queue event interval) is the major reason PP speed falls with longer contexts. Routed MoE and selected GDN/HC are nearly input-proportional; their absolute costs remain substantial, but they do not explain the superlinear increase.

## Comparison with Strata v0.2.13, HIP engine 0.1.59

Strata used **same old original IQ3, same input SHA and 126253 API prompt tokens, and UMA64GB**, but **different** inference engine, matrix algorithms, KV representation and timer. It profiled `STRATA_PREFILL_TIMING=1`, **int8 KV, GPU-resident 32768 cells**, while r6 uses **f16 KV at context131072**. Profiles are not kernel-matched; source has independent architecture-specific optimization and buffers.

| Relevant observation | llama ROCm 64K | llama ROCm 128K | Strata 64K | Strata 128K |
|---|---:|---:|---:|---:|
| Full PP wall (s) | **155.609** | **424.467** | **41.981** | **89.228** |
| Full PP GPU timeline (s) | 154.406 | 421.768 | 41.853 | 89.090 |
| GGML FA subtotal (s) | **44.351** | **189.788** | n/a | n/a |
| Strata QSA attention phase (s) | n/a | n/a | **3.582** | **7.560** |
| GGML QSA select/indexer subtotal (s) | 2.587 | 10.638 | n/a | n/a |
| Strata QSA select phase (s) | n/a | n/a | **1.603** | **6.672** |
| Strata full QSA (s) | n/a | n/a | 7.606 | 19.184 |

Strata full PP grows **2.13×** from64K to128K, and Strata's attention phase grows **2.11×** (nearly linear), whereas llama's FA subtotal grows **4.28×**. The Strata *select* phase grows **4.16×**, quite close to llama's QSA-select aggregate **4.11×**, although the stages are not identical. Strata's full GDN/MoE/HC phases grow about 2×. At128K, the llama FA subtotal alone **189.788s** is over twice the Strata **entire** GPU prefill **89.090s**; this is a useful diagnostic flag, but **never claim FA kernels run 25× slower** based on different timer/category semantics or KV and implementation differences.

The observed PP end-to-end ratio is about **3.71× at64K**, **4.76× at128K** (instrumented, different timing overhead). This widening is strongly consistent with r6 attention/FA scaling being a major contributor. It is not proof which specific Strata gfx1151 optimization accounts for the efficiency.

### Resource data / alternative causes

For the approximate PP interval 02:54:40–03:01:45 JST, ADLX 212 samples: GPU usage median **99%**, clock median **2879MHz**, GPU power median **118W**, temperature median **78C**, maximum **85C**, VRAM signal median **56041 MB**. Windows PDH 212 samples: free Windows RAM **28.365–29.210 GiB**; page-read rate nonzero **9/212**, otherwise zero median. No evidence of sustained hard paging. Some short disk bursts/initial model faults were present; system counters are not process-specific. P-MODE consistent performance. RDP active. The source run completes normally, and GPU busy+PP wall/event match suggest the measured execution rather than swap dominates. The manual `UmaLabel` is **64GB**, matching the memory evidence and prior Strata, not 96GB.

## Next step: Strata gfx1151-specific optimization A/B

With matching-UMA evidence, a logical **follow-up** (after the current result, no need for additional r6 128K work) is **one 64K Strata baseline-vs-optimized-off trial** with same profiler, old IQ3, same frozen SHA, `--drafting off`, KV int8+resident32768 and unchanged chunk setting. Use a fresh Strata engine process for every condition. On pinned Strata v0.2.13, gfx1151 includes **two independently enabled default switch tables**:

1. `STRATA_GFX1151_DEFAULTS=0` disables bit-identical gfx1151 architecture defaults (GDN/HC etc).
2. `STRATA_IGPU_PROMPT_SET=0` disables independent Windows gfx1151 matrix-core prompt set (`STRATA_HIP_WMMA`, `STRATA_PF_GEMM`, `STRATA_PA_FAST`, `STRATA_HC_UPMIX`, `STRATA_PF_FUSED`, `STRATA_SELECT_WMMA`, `STRATA_PF_F16`, `STRATA_PF_DM16`).

A still-broader `STRATA_HIPBLASLT_TABLE=off`, `STRATA_HC_Q8=0` test can follow, but those change a separate library algorithm/weights/read path; `STRATA_PREFILL_BORROW=1` and `STRATA_GFX1151_CHUNK=0` change buffering/chunk policy so should be examined separately, not simultaneously with kernel opt-outs if attribution matters. A test where the switches are OFF is *not a model-independent unoptimized baseline*, and Strata's runtime may retain architecture-specific kernels selected by GPU arch. Preserve exact starting environment and effective engine startup logs. Restart engine each time, set environment for its process, restore vars after test.

## Associated reports

- [64K r6 ROCm operator profile](ROCM-PP-PROFILE-64K-2026-11-15.md)
- [Strata 64K phase profile](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/runs/2026-11-15-strata-64k-prefill-phase-profile.md)
- [Strata 128K phase profile](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/runs/2026-11-15-strata-128k-prefill-breakdown-and-llama-rocm-profiling-plan.md)
- [Strata v0.2.13 architecture defaults](https://github.com/Niko1221/Strata/blob/v0.2.13/src/core/arch_defaults.cpp)
