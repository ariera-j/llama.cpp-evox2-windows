# r5 MTP PP diagnosis: first 128k Vulkan OFF/ON trace — 2026-10-13

**Status: diagnostic gate PASS, 2/2 native runs OK. Cause not yet isolated to actual GPU kernels; do not promote KV-only or QSA optimization based solely on these CPU-wall observations.**

## Evidence, benchmark identity, reproducibility

- User ZIP **`20261013-221959-023-qwen38-r5-mtp-pp-trace-128k.zip`**, SHA256 **`14a2317b1692d2a93e394ae65103b778753929a34a63e2a1e87980ad4ddaf687`**; **23 ZIP members** (matrix plan/results, OFF/ON result, conditions, raw stderr/stdout, resources). Matrix start **2026-10-13 22:19:59 JST**, finished 22:35:38, `RunCountPlanned=2/RunCountFinished=2`, `OK=2/NonOK=0`.
- **Executable**: Windows Vulkan `llama-cli` **b11569**, compiled source `4b136c5bf48e14dc162f96b7457379684287cd20`, Clang 20.1.8. Executable SHA256 **`8118a4334c52060a7c8ede371ac5f0ad33cdf94b1f017d3a28a84106044f1657`**, runtime artifact digest **`06e04e991de8d49fbc31fc68fce9f02957db6bbd16eac2efe5e445d9cc512a9b`**, `RuntimeArtifactStatus=Verified` in both runs, same binary as [64k trace and repeat](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md). **Git checkout** during measurement is later, clean `2578e4672b6ecc2e9a2bd3674367558781e90427` (128k *PSD1 added*); this **does NOT mean the executable was rebuilt**.
- Model: target Unsloth Qwen3.8-Flash-Next PLE16 UD-IQ3_XXS (81,961,816,672 B), MTP ON sidecar Unsloth Q8_0 (4,137,429,120 B). GGUF SHA256s not captured in conditions. Input `nlp-survey-ch3-d15-b1.txt`, **623,699 B**, SHA256 **`182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`**, **126,253 tokens**.
- Runtime `-c131072 -b2048 -ub1024`, f16 main/draft KV, `-t4 -tb4 -ngl999 -ncmoe0 -fa auto -fit off --cache-ram 0 --temp 0 --top-p 0.8 -n 512 --seed 1234 --ignore-eos --ctx-checkpoints 0t`; MTP ON `draft-mtp` max2/p-min0. Vulkan grouped-union setting `GGML_VK_QSA_UNION=1`, minKV32768, **does not prove draft FA path**. `LLAMA_MTP_PP_TRACE=detail`. Source trace branch `investigation/r5-mtp-pp-trace-20261013` from only MTP ratio-zero compatibility guard; no DENSE-001/NOOP-001.
- Parsed all `mtp_pp_trace_v1` raw stderr rows: **OFF 4 bins / 573 detail rows; ON 8 bins / 556 detail rows** (prompt + generation). For **every role/phase/depth bin**, row count, token sum and **all timer sums matched** the bin record; no malformed/negative measurements. Exactly **62 target prompt batches** per arm, and **62 draft prompt batches** for ON; 61 full 2,048-token batches and final **1,325** tokens; prompt tokens sum to 126253. Reported server PP seconds agree with trace target totals within ~0.04s (OFF), ~0.06s (ON). The two source logs carry the full raw detail; no postprocessed native summarizer artifact was shipped in the ZIP.
- Output/acceptance: 512 generated tokens each; ON acceptance **295/429 = 68.765%**, matching prior r5 b11560 128k ABBA acceptance. This is one run per arm, not evidence of OFF/ON output equality or logit equivalence.

## Native timers — one DIAGNOSTIC pair, not an untraced ABBA

| 128k Vulkan | MTP OFF | MTP ON | ON−OFF |
| --- | ---: | ---: | ---: |
| PP tok/s | **329.67** | **299.95** | **−9.02%** |
| Server prompt PP seconds | **382.96571** | **420.90814** | **+37.94243** |
| TG tok/s | 23.97 | 23.56 | −1.71% |
| Generation TG seconds | 21.32068 | 21.68786 | +0.36718 |
| Native PP+TG seconds | **404.28639** | **442.59600** | **+38.30961** |

Existing **b11560 untraced 128k Vulkan ABBA** OFF→ON **335.455→303.965 tok/s, prompt +38.991s**, separate binary/diagnostic mode. A similar +38s penalty is repeatable in broad magnitude, but trace-enabled single-pair PP rates are **not** a speed baseline or proof of per-operator cause.

## CPU-observed MTP ON prompt stage decomposition

**These are nested CPU wall durations; not GPU timing.** Getter may wait for previously queued target GPU work; draft `llama_process` CPU scope may submit asynchronous GPU work.

| Prompt-stage trace | MTP ON |
| --- | ---: |
| Server target + speculative processing wrapper (62 prompt batches) | **420.84554 s** |
| ↳ target `llama_process` + server queue/yield wall | **220.60349 s** |
| ↳ speculative-process wrapper | **200.24115 s** |
| ↳ ↳ MTP draft `process` total | **200.23602 s** |
| ↳ ↳ ↳ synchronizing `llama_get_embeddings_nextn` | **178.29562 s** |
| ↳ ↳ ↳ draft input preparation | **0.00167 s** |
| ↳ ↳ ↳ draft `llama_process(ctx_dft)` CPU call(s) | **20.02331 s** |
| ↳ ↳ ↳ verified hidden getter/resize/copy | **1.91442 s** |
| Existing explicit target sync | **1.22345 s** (subset of 220.60349s) |

OFF target prompt wrapper **382.92431s**. Accounting decomposition for *disjoint CPU time*:
- **(ON target 220.60349 + ON hidden getter 178.29562 − OFF target 382.92431) = +15.97480s**. This is a **difference in measured wall envelopes**, not a pure target nextn computation or DMA copy measurement.
- ON draft `llama_process` call ~**+20.02331s**; ON verified-hidden getter/copy ~**+1.91442s**; other very small bookkeeping/timing ~0.002s. This reconstructs the trace penalty `420.84554 − 382.92514 = +37.92040s` (native prompt-time +37.94243s).
- At **first 64k diagnostic**: 1.480s target+hidden envelope gap + 6.756s draft-call + 1.923s verify hidden. At **128k** the gap rose to 15.975s and draft call to 20.023s, while verified hidden (~1.91s) stayed nearly flat. This comparison uses **different text corpora**, plus one diagnostic pair per depth; it supports hypotheses and not formal complexity fitting.

The existence of ~**16s** non-draft-call gap at 128k means **“all extra PP is MTP draft dense FA” is not established**; target NextN hidden materialization, shifted async waits, tensor transfers or other context-specific work remain candidates.

## KV depth and 2,048-token batch results

| Prompt end KV region | OFF wrapper | ON wrapper | ON−OFF | Draft `llama_process` | Draft hidden getter |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0–32,768 (16×2048) | **78.673s** | **87.285s** | **+8.612s** | **2.875s** | 38.550s |
| 32,769–65,536 (16×2048) | **100.285s** | **108.502s** | **+8.217s** | **4.320s** | 47.309s |
| 65,537–126,253 (29×2048 + last 1325) | **203.967s** | **225.058s** | **+21.091s** | **12.828s** | 92.437s |
| **Total** | **382.925s** | **420.846s** | **+37.920s** | **20.023s** | **178.296s** |

- For 61 *full-size* prompt batches, the draft `llama_process` wall has a near-linear trend versus KV end position; exclude initialization outlier (first 2048-token batch) and short final batch: **Pearson r~0.998** over full batches #2–61, linear descriptive slope ~**3.215 ms per extra 1k KV** per 2048-token batch. This is *CPU-call wall*, not a direct Flash Attention measurement.
- The **last 1325-token prompt batch** differs: OFF target wall **8.006s**, ON server total **5.718s** (ON−OFF **−2.288s**). ON target `llama_process` wrapper **5.168s**, which includes existing explicit target sync **1.223s**; ON draft hidden-getter returns in just **21µs**; the GPU completion wait migrated to the final server target boundary. Exclude this shorter batch when plotting regular 2048-token timing shapes. If excluded, the prior 61 full batches have *combined* ON−OFF ~**+40.208s** before this final −2.288s.
- Both OFF and ON first full batch show warmup/initialization behavior; do not fit all batches assuming stationary cost.
- Total 128k PP penalty is not monotonically concentrated in draft CPU call only. Changes to target full nextn graph or GPU work scheduling may occur while `target_us` decreases because outstanding work is drained at the hidden getter. The 32768 union minKV boundary is not itself proof that draft FA uses union, because draft sidecar ratio0 should take dense path.

## Resource logs / memory and I/O sanity check

Maxima in **this same 128k diagnostic pair**:

| Measured counter | OFF | ON |
| --- | ---: | ---: |
| Process GPU Local (GiB) | **83.370** | **88.674** |
| Process GPU Dedicated (GiB) | 82.528 | 86.820 |
| Process GPU Shared (GiB) | 0.843 | 1.854 |
| System committed (GiB) | **94.139** | **100.757** |

For resource monitor samples ~50–200s after process launch (model-loading burst mostly past), median **DiskRead_MiBps=0.0** and **PageReads_PerSec=0.0**, for **both** OFF and ON; PageInput median likewise zero. This corroborates the repeated 64k evidence: sustained system-wide reads from the first 64k ON run are **not a necessary condition** for a sizable PP penalty. Counters are system-wide and do **not** establish process-private paging or true physical UMA residency; allocated GPU Dedicated/Shared labels alone do not prove a WDDM eviction.

## Implications and next diagnostic gate

1. **128k source + instrumentation complete: no rerun needed to validate trace integrity.** Keep source unchanged, preserve raw ZIP and exact executable digest.
2. **Next high-value question is actual *target versus draft* GPU operator time:** identify **draft dense f16 Flash Attention** dispatch/kernel time (as distinct from CPU draft-call envelope), target graph NextN output materialization costs, scheduler sync/transfer wait. Use a separate opt-in low-overhead GPU-path measurement or targeted RGP capture on a bounded 64k (or selected 128k) run; *do not force sync in ordinary phase trace*.
3. **64k ROCm** becomes useful as an independent backend control after or alongside native Vulkan GPU-path inspection; compare matched model/input/build identity. Do not assume improvements from r4 without measuring.
4. **KV-only draft prefill remains correctness-gated**, not authorized for implementation from this evidence. r2 MTP-QSA ratio-inference prototype remains **NO PORT**; no DENSE/NOOP merging, no stable source changes.

Related: [original 64k plus repeat trace](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md) · [r5 PP investigation plan](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md) · [trace branch implementation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-TRACE-IMPLEMENTATION-2026-10-13.md).
