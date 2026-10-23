# r5 huihui Qwen3.8-Flash-Next UD-IQ4_XS PLE16: Windows 128k validation (2026-10-23–24)

## Status / conclusion

**PASS for the bounded objective:** the huihui-ai abliteration variant based on Unsloth Qwen3.8-Flash-Next **UD-IQ4_XS**, converted to split PLE16, loaded on the Evo-X2 in Windows/96GB UMA on **Vulkan COMMON-001 b11521**, retained 49/49 GPU-offloaded layers, passed context-allocation/short-inference gates at **4k, 16k, 32k, 64k, 128k**, and finished one **126,253-token real-document prefill plus 256 generated tokens** at `-c 131072`. Long-document `truncated = 0`.

This is a **model-format and bounded long-context execution validation**, not a repeated performance A/B, model-quality ranking, or evidence that every 128k prompt will fit. Maximum intended context for this model-comparison project is 128k; no 256k gate requested.

The original joined PLE model completed 4k and 16k allocation checks on clean b11517 Vulkan and ROCm, but left **26.82 GiB** of model data in a CPU buffer and drove free physical RAM into the tens of MiB. With PLE16, **Vulkan moved this 26.82 GiB to the device model buffer** and left ~25 GiB of Windows free RAM. **ROCm PLE16 did not change placement** in its single 4k test. The user elected to continue **Vulkan only**.

The representative result is the **128k input-file run**: **PP 183.26 tok/s**, **TG 22.73 tok/s**, **total wall 738.354s**, **FreeRAM minimum 24.644 GiB**, **target GPU Dedicated maximum 92.711 GiB**. Do not compare these throughputs directly to the earlier 18-token allocation smokes.

## Environment and artifact identity

- Host: GMKtec Evo-X2, AMD Ryzen AI Max+ 395 / Radeon 8060S, Windows; **BIOS UMA label 96GB** (manual label, not independently read from BIOS). Power mode intended Performance.
- Model: huihui-ai Qwen3.8-Flash-Next abliteration derived from Unsloth `UD-IQ4_XS`; GGUF reported **87.24 GiB / IQ4_XS (4.25 bpw)**. Three source shards, aggregate **93,682,584,224 bytes**. Split output `Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf`.
- Source PLE: single joined `per_layer_token_embd.weight`, 26.82 GiB; output 16 `ple_ngram_embd.N.weight` heads.
- Clean reference binaries **b11517** Vulkan/ROCm; split-compatible **COMMON-001 b11521**, commit `b45025848`, Clang 20.1.8. The current r5 stable source is **not** a fully integrated ROCmFPx + MTP optimization build.
- COMMON-001 Vulkan executable SHA-256: `3eb770f43555399b4fb467fe1991ebe8b2acd75a751da25f8733f637c7687ab9`. Runtime artifacts digest: `3010eec7d5f9f95e0dec8057f9520e45e746676b9dcf03aa249e643b7ee88635`.
- Normal gates: `llama-cli`, `-ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 512 -fa auto -ctk f16 -ctv f16 -fit on --cache-ram 0 --temp 0.2 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none --ctx-checkpoints 0t`; MTP OFF; resource monitor 1s, ADLX GPU monitor and authoritative P-MODE start/finish probes.
- **Allocation-only limitation:** `AllocationOnly` checks context allocation + the 18-token short prompt / short generation (2 output tokens in these logs). It does **not** prefill the context with user content.

## Conversion-tool port and failure/recovery

The r2/MIT LaurentZuijdwijk `gguf_split_ple_heads.py` was adapted into `tools/evox2/model/` for the r5 GGUF API; r3's `Convert-Unsloth-Ple16.ps1`, `verify-ple-layout.py` and r2's `verify-ple16.py` were restored/adapted. The original split-head enum does not exist in r5 GGUF Python, so the converter explicitly constructs `ple_ngram_embd.{head}.weight`. See [model tool README](../../tools/evox2/model/README.md).

On **2026-10-24 ~00:36 JST**, the Python converter completed writing all model tensors (`100.0%` and `wrote ...partial.gguf`), but the PowerShell wrapper rejected the run because `Start-Process -PassThru` returned a **blank exit code** in Windows PowerShell 5.1. Inspection also found incorrect final-vs-partial path selection in the wrapper. These were **wrapper defects**, not evidence of corrupt tensor payloads.

The wrapper was fixed to retain a native process handle and use `GetExitCodeProcess` fallback (as in the benchmark launcher), to verify the `.partial.gguf` filename, and to support `-FinalizePartial` **without rerunning the 87 GiB conversion**. The user then ran:

```powershell
& $converter -InputFile $inputModel -OutputFile $outputModel -FinalizePartial -VerifyBytes
```

The recovery reported `PLE recovery verified and finalized successfully`. `-VerifyBytes` checks every converted tensor payload by SHA-256 as well as metadata/layout; existing partial output was renamed to the final GGUF. Recorded provenance sidecar: `Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf.evox2-conversion.json`; recovery run logs in `evox2-logs/model-conversion/20261024-004702-223-ple-layout`. Source input shards retained; no unverified output published. The earlier incomplete wrapper run logs are at `20261024-003604-840-ple-layout`. **No further conversion run is needed for this model.**

## Allocation and placement gates

All rows below are **single runs** with `Status=OK`, `ExitCode=0`, 49/49 GPU layers and successful short output. Values are MiB/GiB counters from `stderr.log` and `resources.csv`; GPU Dedicated is **target process's Windows GPU counter maximum**, not an exact inference allocation budget. Absence of a CPU model-buffer line is not zero total host RAM.

| Model layout | Backend/build | Context | Device model GiB | CPU model GiB | KV cache MiB | Min free RAM GiB | Max target GPU Dedicated GiB | P-MODE start→finish |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Joined | Vulkan b11517 | 4k | 59.79 | 26.82 | 120 | 0.012 | 61.418 | Performance→Unknown* |
| Joined | ROCm b11517 | 4k | 59.79 | 26.82 | 120 | 0.037 | 60.600 | Performance→Performance |
| Joined | Vulkan b11517 | 16k | 59.79 | 26.82 | 480 | 0.065 | 61.795 | Performance→Performance |
| Joined | ROCm b11517 | 16k | 59.79 | 26.82 | 480 | 0.026 | 60.956 | Performance→Performance |
| **PLE16** | **Vulkan b11521** | **4k** | **86.61** | **not reported** | **120** | **24.762** | **88.506** | Performance→Performance |
| PLE16 | ROCm b11521 | 4k | 59.79 | 26.82 | 120 | 0.052 | 60.602 | Performance→Performance |
| **PLE16** | **Vulkan b11521** | **16k** | **86.61** | **not reported** | **480** | **25.002** | **88.070** | Performance→Performance |
| **PLE16** | **Vulkan b11521** | **32k** | **86.61** | **not reported** | **960** | **24.981** | **88.070** | Performance→Performance |
| **PLE16** | **Vulkan b11521** | **64k** | **86.61** | **not reported** | **1,920** | **24.797** | **90.421** | Performance→Performance |
| **PLE16** | **Vulkan b11521** | **128k** | **86.61** | **not reported** | **3,840** | **24.793** | **92.522** | Performance→Performance |

`* ` One Vulkan b11517 4k **finish P-MODE probe failed**, due to WMI direct access Win32 error 5 and 5-second scheduled-task state-file timeout. Model inference still succeeded; do **not** label the finish state as Performance. Other probes including all PLE16 Vulkan gates were Performance→Performance.

**Interpretation:** PLE16 Vulkan increases the device model buffer by ~26.82 GiB, almost exactly the missing CPU model-buffer amount. ROCm at 4k still keeps the joined-equivalent PLE data in CPU model memory. Clean b11517 versus COMMON-001 b11521 is **not a same-binary A/B**, so do not claim an isolated PLE16 speedup. Chrome/Edge were closed during the later joined-layout checks, yet minimum Windows free RAM remained near zero. The 96GB UMA label is a BIOS partition label; driver virtual memory counters are not a fixed physical VRAM capacity.

## One real-input 128k gate (2026-10-24 01:35 JST)

**ZIP/run:** `20261024-013553-926-cli-vulkan-b11521-ctx131072-81b9e555aa49`

- Source: `nlp-survey-ch3-d15-b1.txt`, the standard repeated research-paper chapter-3 input. The actual input-file path is preserved in `conditions.json`.
- `-c 131072`, `-n 256`, other settings as above; P-MODE Performance→Performance; resource monitor and ADLX both completed.
- `result.json`: **126,253 prompt tokens**, **256 generated**, total **126,509**; 126,253/131,072 = **96.32%** input occupancy; **4,563** tokens remain after input+generation.
- `stderr.log`: `new prompt, n_ctx_slot = 131072, ... task.n_tokens = 126253` and `stop processing: n_tokens = 126508, truncated = 0`. No observed context-shift message; input was not silently truncated.
- **PP = 183.26 tok/s** (688,914.85 ms), **TG = 22.73 tok/s** (11,219.47 ms), **total measured model processing = 700,134.31 ms**, **end-to-end wall 738.354 s** (includes model load and other overhead). Not a repeated benchmark.
- `resources.csv`: **min FreeRAM 24.644 GiB**, max target GPU Dedicated **92.711 GiB**, max target GPU Shared **0.810 GiB**, max system Committed **104.540 GiB**. No CPU model-buffer allocation was printed; device model buffer remained **86.61 GiB**. Vulkan final memory breakdown reported **14,635 MiB free** on the device's reported budget; avoid treating this as a hard physical-VRAM spare capacity.
- `gpu-metrics.csv`: peak GPU temperature **80°C**, median GPU clock **2,882 MHz**, peak GPU power **126 W**. ADLX high-load mean power **103.121 W** was classified `Ambiguous`; authoritative P-MODE still Performance→Performance without warning.
- Output remained coherent Japanese technical prose through the specified 256 generation tokens; this is a **basic functionality observation, not a judged summary-quality test**. The output ends at the generation budget.
- Representative prefill behavior: cumulative PP rate declined as prefill progressed (e.g. 118,784 tokens: 190.64 tok/s cumulative; 124,928 tokens: 185.52 tok/s cumulative). The local segment rate is slower at deep contexts. This is compatible with context-dependent attention cost, **not an isolated demonstration of a specific kernel bottleneck**. COMMON-001 b11521 has no later grouped-union/MTP acceleration integrated.

## Raw evidence (external ZIPs, not committed)

The following actual user-provided archives were inspected. SHA-256 hashes identify each **ZIP**, not the GGUF. Every archive contains `conditions.json`, `result.json`, `stderr.log`, `resources.csv`, and ADLX records. Multi-run archives contain two top-level run folders.

| Archive filename | SHA-256 |
|---|---|
| `20261023-233507-629-cli-rocm-b11517-ctx4096-91d7f7d2ac31.zip` | `47c89d9a21a93398d5139acc3be8ca8501e34d833dff70eec7a213b560f29f63` |
| `20261023-234738-805-cli-rocm-b11517-ctx16384-87fd2e3ed24c.zip` | `efcc267afe5f39ecbd0959b9ae68fffdcfea3f3bdfae7a978d2fe0b1741ee4e2` |
| `20261024-010405-547-cli-rocm-b11521-ctx4096-e1ec72166fb7.zip` | `f2c67c94ec79518d5989694f589fab79c39ed94ef07b8b56de7bb56bd47fa35a` |
| `20261024-011009-526-cli-vulkan-b11521-ctx16384-8bf57305ca03.zip` | `8952a5e2394223110d1df7fb46f71dcd087b94043a297395a39f93b3bbcce6f9` |
| `20261024-011600-015-cli-vulkan-b11521-ctx32768-22d3f558562a.zip` | `9d6f1f37c01761c2ad50d668ea7ad635cdbd231386ba836ff739e1ce695daf5d` |
| `20261024-012031-764-cli-vulkan-b11521-ctx65536-05177f8186ca.zip` | `7dc5d616a5631d5f5ff9fa57920a3815d57664fc07d2d1d0ef6185efbab19abb` |
| `20261024-013051-775-cli-vulkan-b11521-ctx131072-5b2dca67edec.zip` | `d0a1fc88b0109f0556150cf86a2f0d0568f9e32498b3ee92d7eaad3cdcb51453` |
| `20261024-013553-926-cli-vulkan-b11521-ctx131072-81b9e555aa49.zip` | `cfd53fe10edf312136fd2fe500ca20f12dc11feb1ea09d5454b8fb113a6fc45e` |

The `20261023-233507...`, `20261023-234738...` and `20261024-010405...` ZIPs each include **both** Vulkan and ROCm run folders. No raw GGUF, conversion payload or ZIP binary is committed here. This report records results, not actual replay or upload of the local ZIPs.

## Next work: four models, then the integrated build (user plan as of 2026-10-24)

**Do not expand 128k further now.** Preserve this 128k real-input result as a model usability gate, then switch to a small, bounded **output-content comparison**:

1. Overnight download the **original Unsloth UD-IQ4_XS** (the source-family counterpart to the tested huihui abliteration); next morning run `-PreflightOnly`, convert joined PLE to PLE16 with the r5 tool, verify, and do a **short Vulkan load/memory gate only**. Do not assume the original model's exact bytes/file size match the huihui variant without checking.
2. Intended **four models**: **Agention Qwen3.8-Flash-Next ROCmFP4-FAST-v2-ple16**, **Unsloth UD-IQ3_XXS PLE16**, **huihui abliteration UD-IQ4_XS PLE16**, **original Unsloth UD-IQ4_XS PLE16**. Existing first two were previously compared; new pair allows observing model/abliteration differences, but quantization and format differ across the four.
3. For tomorrow's initial comparison, use **one already-available r5 ROCmFPx-capable Vulkan build** (choose and log the actual branch, `llama-cli` commit/SHA and runtime). Its exact executable is **not selected in this document**. Check that every model loads and runs under that executable and the chosen prompt conditions before comparing. Historical ROCmFPx build results from other binaries are not same-run speed references.
4. Focus the prompt discussion on the unexpectedly different **explanation granularity/detail** observed on 2026-10-23: is it repeatable or incidental? Consider a **small v1-style test previously prepared for Qwen3.5** and a restrained follow-up to the two-model output comparison in Qiita #7. **Prompt wording, number of trials, temperature/seed and evaluation rubric remain to be decided with the user**; avoid an uncontrolled explosion of prompts/parameters.
5. After the first four-model output comparison, proceed with the **r5 latest-upstream integrated candidate** according to [authoritative integration plan](R5-INTEGRATION-PLAN-2026-10-21.md). The integration has **not** happened as of this report. After it passes its own compatibility/benchmark gates, **repeat the same four models × the exact same chosen input** on the new integrated binary and inspect how outputs change. Preserve prompts, model hashes, runtime/build identity and generation settings. Treat QSA top-k repeatability caveats documented in [ROCm QSA repeatability report](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md) separately; do not assume exact text equality on every run.
6. **Speed:** differing input lengths, contexts, quantization formats, kernels, binary revisions and MTP/sampler settings preclude a controlled speed ranking from today's ~183/22.7 reference alone. Keep speed as a qualitative observation until same-prompt, same-binary tests are available. The user's principal immediate question is output quality/detail, not optimized TG.
7. **ROCm/64GB UMA** is deliberately deferred. In principle more CPU-visible RAM may relieve joined/ROCm PLE pressure, but this 87GiB-class model already uses ~60GiB GPU model/dedicated memory at 4k; changing UMA can create GPU pressure. Do not change BIOS settings for this sequence.

### Integration-policy boundary

This addendum is **validation evidence and next-comparison planning** only. It does not change the priority/order in the authoritative [2026-10-21 integrated-candidate plan](R5-INTEGRATION-PLAN-2026-10-21.md), nor assert that MTP-DENSE/NOOP, Stage-B or ROCmFPx inference support is now present on stable r5. It introduces no new native source patch and no replacement release claim.
