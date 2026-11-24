# 2026-11-15 Windows ROCm r6 operator-timing run: 64K Japanese paper

## Provenance and gating

- **User private ZIP**: `20261115-023352-983-cli-rocm-b11933-ctx65536-61066389b549.zip`. The raw ZIP and prompt **are not committed**; only derived results appear here.
- Run ID `20261115-023352-983-cli-rocm-b11933-ctx65536-61066389b549`; status **OK**, exit 0; 2026-11-15 02:33:54–02:37:16 JST.
- ROCm `llama-cli` **b11933**, compiled from dedicated profiler branch commit `9ae6f153945fc9a67134732f2e5895553c3d7d23`, Windows TheRock ROCm SDK 10.0.0, Clang 23, Radeon 8060S gfx1151, **actual UMA configuration consistent with 64GB**; run metadata is incorrectly manually labeled `UmaLabel=96GB`; `GGML_EVOX2_PP_TIMING=1`, `-lv 4`. GPU instrumentation is experimental.
- Original 3-shard Unsloth `Qwen3.8-Flash-Next-UD-IQ3_XXS` (old, obtained Aug 29). Input `nlp-survey-ch3-d7-b1.txt`, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; `61789` llama API prompt tokens, `cache_n=0`.
- `--context 65536 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -fit off --cache-ram 0 --reasoning off --spec-type none -n 8`, MTP OFF, temp0. Model log: `offloaded 49/49 layers`, model buffers CPU **27465.95 MiB**, ROCm0 **50191.17 MiB**, ROCm host **497.31 MiB**; ROCm0 main KV **1536 MiB** and indexer KV **384 MiB** (f16, 65536 resident cells), model shared host allocations do not by themselves establish CPU MoE computation.
- Prompt eval `155609ms` = **397.08 tok/s**, TG `366.98ms` / 8 tokens = **19.07 tok/s**. Overall process wall ~202s includes loading and setup. **Profiling-on speed is not a normal performance baseline**.

## Correct parsing of the profiler lines

The complete `stderr.log` has **71** `evox2 pp timing:` lines:
- **2 model warmup** before line `new prompt ... task.n_tokens=61789`; never include.
- **61 prompt graph invocations** from this marker through the line `progress = 1.00, n_tokens=61785` inclusive; this is the measured 1024-microbatch prompt processing region (60 full or near-full plus one last; the server may handle a few final prompt tokens in the first generation-side transition; do not conflate chunk end `61785` with the 61789 total).
- **8 generation-transition/decode graph invocations** after the 100%-prompt milestone and before the final timing print; excluded from the PP totals (the first can include last-prompt logic).
- All **61 PP graph lines**: `nodes=6540`, `fa_n=12`, `qsa_select_n=36`, `moe_id_n=141`, `gdn_core_n=72`, `hc_fused_n=95`, `concurrent=0`. Fused operator attribution is based on **root GGML op** only, so it cannot be mapped one-to-one to Strata stages.

Summation is of per-call fields, without the two warmups or 8 decode calls. Rounded values:

| GGML label | 61 PP calls (seconds) | Percent of event-total |
|---|---:|---:|
| **GPU event total** | **154.406405** | 100.0% |
| **`moe_id_ms`** | **46.806963** | **30.31%** |
| **`fa_ms`** | **44.350521** | **28.72%** |
| `gdn_core_ms` | 4.628318 | 3.00% |
| `hc_fused_ms` | 3.369798 | 2.18% |
| `qsa_select_ms` | 2.587018 | 1.68% |
| *Unclassified / residual (by subtraction)* | **52.663787** | **34.11%** |

`154.406s` event-total vs `155.609s` llama PP wall differ by **1.203s** (~0.77%). However, category events are anchored on the active stream, and can include CPU launch stalls; these are **not kernel-only durations**. `concurrent=0` is reported at end of each call, not a proof that no other work occurred outside the measured stream. Because the classification covers only selected ops, do not interpret 3% GDN or 2% HC as the cost of the entire GDN/HC subsystem.

### Equal-work prefix-window scaling (8,192 tokens each)

For PP microbatches numbered 0..55 (8 per row), aggregate the events in successive *equal-input-token* windows; excluded the partial trailing window:

| Ingested prompt range | Total GPU (s) | FA (s) | MoE ID (s) | QSA select (s) | GDN core (s) | HC fused (s) | Residual (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0–8K | 14.792 | **0.696** | 5.757 | 0.075 | 0.622 | 0.457 | 7.185 |
| 8–16K | 16.346 | **2.245** | 5.998 | 0.135 | 0.610 | 0.452 | 6.905 |
| 16–24K | 18.283 | **3.825** | 6.253 | 0.214 | 0.609 | 0.445 | 6.937 |
| 24–32K | 20.034 | **5.446** | 6.279 | 0.317 | 0.612 | 0.448 | 6.931 |
| 32–40K | 21.802 | **7.112** | 6.287 | 0.405 | 0.613 | 0.442 | 6.943 |
| 40–48K | 23.507 | **8.711** | 6.302 | 0.499 | 0.617 | 0.443 | 6.935 |
| 48–56K | 25.323 | **10.353** | 6.342 | 0.589 | 0.614 | 0.447 | 6.978 |

The last equal-sized interval's FA is **14.88×** the first, while MoE ID is **1.10×**. This supports context-length growth in **llama.cpp FA as a strong driver of long-context PP slowdown**, with MoE comparatively stable per token. `QSA select` also grows, albeit on a smaller scale, while the residual (most general GEMMs, other ops and event gaps) stays around 6.9–7.2s per 8K.

## Corrected UMA identification (2026-11-15)

The user's EVO-X2 BIOS UMA allocation has **not** been changed since Strata setup; it is 64GB. The 64K llama ZIP's `conditions.json` and `result.json` include a stale **manual** `UmaLabel=96GB`; the log explicitly calls it `manual label; not auto-detected`. This value is **not** a BIOS/firmware measurement. The same ZIP's `SystemIdentity.TotalPhysicalBytes=68,340,748,288` = **63.647GiB** Windows-visible system RAM, and `common_param - CPU` reports **65,174MiB**, matching a 128GB physical-RAM machine with ~64GB reserved for GPU UMA. GPU's `ROCm0: 102129 MiB` refers to the ROCm runtime-reported GPU capacity, **not a direct reading of reserved UMA**; it must not override the Windows RAM evidence. The earlier draft of this report incorrectly compared **UMA96GB vs UMA64GB**; this is corrected. The remaining substantial **KV type/capacity/engine and microbatch differences** still preclude apples-to-apples kernel attribution. For future 128K runs, pass `-UmaLabel '64GB'` explicitly to `Measure-LlamaCli.ps1` (or fix only the local config label); preserve the original source's reported value in the archived raw ZIP for provenance.

## Cross-engine interpretation: STRATA is NOT the same profiler or KV config

Separate existing Strata 0.2.13/HIP engine 0.1.59 **UMA64GB**, old original 3-shard IQ3 model, 64K same frozen file:

| Strata full-stage category | Time (seconds) |
|---|---:|
| GPU timeline | **41.853** |
| `qsa attn` | **3.582** |
| `qsa proj` | 2.312 |
| `qsa select` | 1.603 |
| QSA full (with indexer-related phases) | **7.606** |
| MoE/routing full | **14.717** |
| GDN full | **10.087** |
| HC full | **9.069** |

llama.cpp's individual **`FA` subtotal 44.351s is even larger than Strata's *entire* 41.853s GPU timeline**, and is ~12.4× the Strata-specific `qsa attn` phase's 3.582s. **These are observations, NOT an apples-to-apples kernel speedup ratio:** Strata's timer samples broad phases, llama's samples selected backend-root GGML ops and changes synchronization; llama uses **f16 full-resident 65536-cell KV**, Strata uses **int8, 32768 GPU-resident KV** with different QSA implementation/launch strategies; **both runs appear to use UMA64GB** (llama run's manual label was stale); source architecture and microbatch differ. The full-Prefill difference is llama **155.609s** vs Strata ~**41.981s**, ~**3.71×** in these profiling runs, but cannot yet isolate that gap among mathematical work, kernels, sync, KV or host. MoE `MUL_MAT_ID` vs Strata entire MoE is likewise not directly comparable.

## Resource telemetry and alternate bottlenecks

PP time window approx 02:34:37–02:37:12 JST, ADLX **78** samples: GPU utilization median **99%**, clock median **2874.5 MHz**, power median **119W**, max temperature **80°C**, VRAM signal stable at **53909 MB**. Windows PDH **77** PP samples: free RAM **28.218–28.442 GiB**, page-read rate nonzero **7/77**, peak 1018.2/s on a sample near PP start; intermittent late page reads but no sustained hard-pagein pattern throughout PP. GPU busy median high, no evidence of persistent RAM exhaustion; sample counters are system-wide and can miss brief events. RDP session active. The pp wall/event correspondence argues that the measured HIP execution is the main duration.

## Next proposed experiment

**No profiler-code changes are necessary to obtain this 64K first pass.** First validate input and KV choices before concluding kernel attribution. Next run one **128K** paper with unchanged profiling binary and parallel/microbatch flags to measure how the 44.351s FA subtotal scales. Then refine category attribution of **52.664s residual** if needed, splitting projection, shared expert and HC/GDN general GEMMs via graph node labels/fusion-root metadata. Do not attempt to compare GDN/HC with Strata's totals from the current undercount. Matched-KV further runs can follow using supported KV settings, keeping logs.
