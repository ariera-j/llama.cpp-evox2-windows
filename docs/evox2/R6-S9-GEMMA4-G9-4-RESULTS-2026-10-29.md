# R6 S9 G9-4 Gemma4 Vulkan measured results - 2026-10-29

## Scope and decision

**G9-4: bounded text-only `PASS candidate` for both Gemma4 31B QAT Q4_0 and 26B A4B QAT UD-Q4_K_XL on the combined b11908 Vulkan build.** The two models completed short 4k/16k allocation and response checks and a real 32k paper input with full GPU offload, stable Performance P-MODE, no context truncation, no OOM or GPU reset. The user's acceptance criterion for the known-slow 31B was **no extreme slowdown relative to the retained b10919 Vulkan build**, not a new 31B throughput target. A selected b10919 31B real-32k CLI control did not show such a regression.

This is **not** approval to remove b10919, switch launch profiles automatically, enable S8 optimization flags or MTP for Gemma4, claim 64k/128k compatibility, or release an untested server/vision configuration. A complete long-answer quality check remains **DEFER** because both real-32k outputs ended at the configured `-n 128` limit rather than finishing the requested answer. Continue to G9-5 only if the user's actual server/multiturn/vision use case requires it.

All observations are on Windows Evo-X2, UMA 96 GiB and P-MODE Performance, with one GPU inference at a time. GGUF paths were checked locally; private directories and raw input text are not committed. The source artifacts are retained as measured ZIPs and one b10919 text log, identified by SHA256 below.

## Build, model and input identities

| Item | Verified identity |
| --- | --- |
| Combined Vulkan CLI | b11908 `b82243bf0`, Clang 20.1.8, SHA256 `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a` |
| Combined Vulkan runtime artifact digest | `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3` |
| Retained b10919 Vulkan CLI | b10919 `d3146f2b5`, Clang 20.1.8, SHA256 `a911d81cba7547695bd46da1897d8fdb712f39d08402b42f01c205d6cd45202b`; kept in separate known-good directory |
| 31B GGUF | `google/gemma-4-31B-it`, QAT `q4_0`, 16.439 GiB, SHA256 `0374ce7b0124db9ba96fc649e835c531223ee224a497ce88a374baaea10932ec` |
| 26B GGUF | `gemma-4-26B-A4B-it`, QAT `UD-Q4_K_XL`, 13.270 GiB, SHA256 `a7c5bc715f5ff8e99a3e8901ce7d2b42b402c669bf24f7c5250747633d0f5891` |
| Short QA input | `tools/evox2/benchmark/inputs/mtp-short.txt`, 811 bytes, SHA256 `88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5` |
| Real 32k input | existing `Inputs.'32k'` paper fixture, 145,547 bytes, SHA256 `1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601`; Gemma4 actual **29,379 prompt tokens** on both models |

The combined-binary runs used `-ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 512 -fa auto -lv 4 -ctk f16 -ctv f16 -fit on --cache-ram 0 --jinja --single-turn --spec-type none --ctx-checkpoints 0t --seed 1234 --temp 0.2 --top-p 0.8`. All five S8 speed flags were explicitly OFF, no Draft/MTP, and both models were fully offloaded (31B 61/61 GPU layers, 26B 31/31). The stock smoke was initially `--reasoning auto` and `-n 64`; the local **QA follow-up** used `--reasoning off`, `-n 256` for short 4k/16k and `-n 128` for real 32k. The QA plan was a local log-area copy, not a new committed executable profile.

## Measured speed and quality

`PP` = prompt processing tokens/sec; `TG` = output generation tokens/sec. Context columns describe **allocation**; actual prompt lengths are stated separately. Each row is one run, not a repeated-run mean.

| Build / case | Model | Context | Actual prompt | Generated | PP tok/s | TG tok/s | Text/termination |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| b10919 4k baseline (`reasoning auto`) | 31B | 4,096 | short fixture | 64 limit | 71.5 | 12.0 | Thinking-only; **not** a final-answer QA PASS |
| b10919 4k baseline (`reasoning auto`) | 26B | 4,096 | short fixture | 64 limit | 307.6 | 66.3 | Thinking-only; **not** a final-answer QA PASS |
| b11908 stock 4k (`reasoning auto`) | 31B | 4,096 | 173 | 64 | 269.91 | 11.85 | Process OK; thinking-only |
| b11908 stock 4k (`reasoning auto`) | 26B | 4,096 | 173 | 64 | 775.41 | 72.94 | Process OK; thinking-only |
| b11908 QA 4k (`reasoning off`) | 31B | 4,096 | **170** | 100 (EOS) | **336.15** | **11.85** | Coherent Japanese summary; PASS |
| b11908 QA 4k (`reasoning off`) | 26B | 4,096 | **170** | 132 (EOS) | **1,331.17** | **72.19** | Coherent Japanese summary; PASS |
| b11908 QA 16k (`reasoning off`) | 31B | 16,384 | **170** | 100 (EOS) | **337.82** | **11.83** | Allocation and output PASS; **not a 16k-filled prompt** |
| b11908 QA 16k (`reasoning off`) | 26B | 16,384 | **170** | 132 (EOS) | **1,342.21** | **69.94** | Allocation and output PASS; **not a 16k-filled prompt** |
| b11908 real 32k (`reasoning off`) | 31B | 32,768 | **29,379** | **128 (cap)** | **64.63** | **8.93** | Full input accepted, stable; answer cut by output cap |
| b11908 real 32k (`reasoning off`) | 26B | 32,768 | **29,379** | **128 (cap)** | **267.45** | **50.16** | Full input accepted, stable; answer cut by output cap |
| b10919 real 32k (`reasoning off`) | 31B | 32,768 | Same paper file requested; token count **not exposed** in saved CLI text | 128 limit requested | **59.5** | **9.0** | CLI completed and began a coherent Japanese summary; no telemetry or detailed counter log |

The 4k/16k b11908 QA summaries broadly followed the text. In some sentences they compressed a **planned** schedule change into a definite-sounding statement, a small instruction-fidelity limitation worth preserving; this is not a newly established version-to-version regression. The 32k paper outputs remain **generation-cap-limited**, so only load, prompt processing, short continuation and stability were validated there, not completed multi-paragraph response quality.

### Real 32k resource and prompt checks

| Metric | 31B b11908 | 26B b11908 |
| --- | ---: | ---: |
| Requested/actual context | 32,768 / 32,768 | 32,768 / 32,768 |
| Actual prompt tokens / context truncation | 29,379 / `truncated=0` | 29,379 / `truncated=0` |
| Prompt-eval time | 454,549.56 ms | 109,847.78 ms |
| Generate-eval time | 14,214.57 ms | 2,531.88 ms |
| Total model time | 468,764.14 ms | 112,379.66 ms |
| Overall run duration | 482.348 s | 122.348 s |
| Minimum free physical RAM | 23.834 GiB | 24.750 GiB |
| Maximum monitored target GPU commitment | 22.344 GiB | 15.347 GiB |
| Paging after initial samples (mean PageReads/sec) | ~0.31 | ~0.02 |
| P-MODE | Performance at start/end | Performance at start/end |
| High-load ADLX power observation | ~118.8 W (`Performance-like`) | ~117.9 W (`Performance-like`) |

Both runs report `Status=OK`, exit code 0, no GPU reset/OOM, full model GPU placement and stable P-MODE. There is no sustained paging indication. In the 31B 32k run, observed long-context prompt-processing throughput decreases across the growing sequence; **no causal attribution to Vulkan attention or to the R6 patch stack is made** from one non-matched run. The 26B A4B model's higher raw speed is **not** a same-model backend or patch improvement measurement.

### 31B b10919 rollback/performance control

The user confirmed that 31B's low speed predates R6 and specified **no extreme regression versus b10919** as the criterion. The b10919 32k control used the same 31B GGUF, existing real-paper input path and `-c 32768`, common `-ngl 999`, f16 KV, FA auto, `--reasoning off`, Jinja, single-turn and `-n 128`. Its saved interactive CLI text reports `[ Prompt: 59.5 t/s | Generation: 9.0 t/s ]` and normal exit. The b11908 logged 64.63 PP / 8.93 TG is approximately **+8.6% PP and -0.8% TG** relative to these rounded old CLI counters, i.e. **no gross regression observed**.

**Comparison limit:** This is a coarse regression screen, not a controlled same-flag microbenchmark. b10919's saved text does not expose exact `PromptTokens`, GPU offload count, P-MODE/resource telemetry or a detailed timing breakdown, and the older command intentionally omitted some b11908-only options. Do not interpret the 8.6% as an attributable performance gain. A further b10919 deep-dive is not required for the user's stated acceptance threshold; keep b10919 preserved as a rollback.

## Artifact evidence (SHA256, no raw files in Git)

| Artifact | SHA256 |
| --- | --- |
| `20261029-011046-564-cli-vulkan-b11908-ctx4096-ed151d8b2ddc.zip` (b10919 4k text baselines + b11908 auto 4k) | `0bb553bde5a141fc5951f1f23606f5de7d752a163cdeff0680bfa0d33c53f722` |
| `20261029-011825-191-cli-vulkan-b11908-ctx4096-e18c52f65361.zip` (QA 4k) | `2c5a8a2ec5b491a2472ca45e0cc9fb8ab77a314c4b0eca3f616bab15c25881b0` |
| `20261029-012333-455-cli-vulkan-b11908-ctx16384-cb92e75a4ad9.zip` (QA 16k) | `0c202d03a8b2be364e609c1f735248493eb22af1d152bf9e52e516c7f58b1301` |
| `20261029-093841-574-cli-vulkan-b11908-ctx32768-3156a612874a.zip` (31B real 32k) | `8e80c0ae14ac6cfaf7cb7197625b86a59d60fef6e17937cdad5b1f1ca534f5ad` |
| `20261029-103006-670-cli-vulkan-b11908-ctx32768-8b31a6b969c2.zip` (26B real 32k) | `3cfb4e51541edb174c653842b9e8d9570997b370bf8a5970ce094d01e5e567b7` |
| `Gemma4_31B-32k-20261029-104241.txt` (b10919 31B real-32k console) | `5c82911cdb5a3fdf7e93c0859db0c31e0592daa4ba8b56be2086013465260373` |

## G9-4 closure and next step

- **31B/Vulkan b11908: `PASS candidate`** for bounded 4k/16k text QA and full real-32k input/stability; no extreme 32k PP/TG regression against the retained b10919, subject to the coarse-comparison caveats.
- **26B A4B/Vulkan b11908: `PASS candidate`** for bounded 4k/16k text QA and full real-32k input/stability; 4k generation is in the same general speed range as prior b10919. A matched b10919 26B real32k was **not** run.
- **G9-5: `PENDING/SELECTIVE`** for actual server multi-turn or vision paths if requested. No automatic rollback deletion, default profile change, generic Gemma release assertion or new long-context performance tuning.

See [the S9 final-model runbook](R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md#4-g9-4-gemma4-31b-and-26b-independent-b10919-rollback-gate) and the separately completed [Qwen IQ4/huihui S9 measured results](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md).
