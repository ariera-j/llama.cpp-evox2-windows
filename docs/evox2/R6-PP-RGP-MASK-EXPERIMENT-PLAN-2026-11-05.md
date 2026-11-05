# r6 64k PP: Vulkan FA mask heatmap + Vulkan/ROCm aligned RGP experiment (2026-11-05)

> **Status: DESIGN COMMITTED / IMPLEMENTATION NOT STARTED / NATIVE GPU TEST NOT STARTED.**
> Dedicated research branch: `investigation/r6-pp-fa-mask-rgp-20261105`.
> Parent: `feature/r6-llama-bench-real-prompt-20261103` at commit `6a092fd2e60789d6ff7001cbe8e342fccff323ac`. Do not merge this branch into r6 stable/feature until the experiments have an independently verified reason.

## 0. Why now / existing reproducible observations

New controlled-within-setup 64k measurements dated 2026-11-04–05 established that the same input type produces different PP behavior on Vulkan and ROCm:

| Setup / IQ3 | literature PP | llama.cpp code PP | code vs literature |
|---|---:|---:|---:|
| r6 Vulkan b12032 / PLE16 / UMA96 / native real-input `llama-bench` | 356.745 | 386.292 | +8.28% |
| r6 ROCm b12038 / PLE16 / UMA96 / native real-input `llama-bench` | 407.966 | 401.958 | −1.47% |
| upstream b12125 Vulkan / original 3-shard GGUF / UMA64 / `llama-cli` | 361.75 | 382.99 | +5.87% |
| upstream b12125 ROCm / original 3-shard GGUF / UMA64 / `llama-cli` | 422.09 | 418.87 | −0.76% |

For the upstream stock CLI, progress snapshots indicate an approximate **+19% code advantage at input depth 48k–58k** on Vulkan, while ROCm stays around ±1% in the same interval. Each cell is **r=1**; we have a repeatable *direction across setups*, not a quantified per-kernel causal result.

A separate r6 ROCm code-only UBatch experiment showed PP IQ3 **347.908 (UB512) / 401.958 (UB1024)** versus IQ4_XS **389.717 / 388.106** tok/s. This motivates a later MoE/quantized kernel track, **not** immediate expansion of the RGP matrix.

**Raw-data provenance and analysis:**
- [experiments: 64k input-dependence folder](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/pp-input-dependence-64k-20261104)
- [experiments: results](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/RESULTS.md)
- [experiments: RGP/mask handoff](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/NEXT-RGP-MASK.md)
- [preceding four-theme research design](R6-PP-INPUT-FA-MASK-MOE-QUANT-PROFILING-DESIGN-2026-11-04.md) (originally deferred; this document activates a narrower first investigation).

**Critical comparison limit:** upstream and r6 do not share model layout (original vs PLE16), UMA (64 vs 96 GiB), tool (CLI vs bench), or exactly verified token-ID arrays; absolute tok/s across those rows are **not** an isolated fork-speed comparison. Profile **r6 inside r6**, same executable/model and each corpus.

## 1. Question and hypotheses

Main question: **At an identical physical PP block and model layer, why is Vulkan code-prefill faster than Japanese literature while ROCm changes little?**

- **H1 (Vulkan tile skip):** QSA selection mask has input-dependent **positions** of all-`-inf` Br×Bc tiles. `flash_attn_mask_opt.comp` packs tile classes; `flash_attn_cm1.comp` skips a GPU compute tile on `MASK_OPT_ALL_NEG_INF`. Counts *and spatial distribution* plausibly explain Vulkan late-depth variation.
- **H2 (ROCm different FA execution):** HIP FA dispatch can take a different kernel/scan/cutoff path and may not exploit the same interior tile skip. RGP should isolate masked FA compute and scanning at the **same** KV/layer/UBatch in each corpus.
- **Alternative:** Changes in MoE routing/quantization GEMM, GPU clock state, CPU submit/idle or cache/memory behavior contribute; H1 is not presumed true. The new profiling should quantify **unexplained residual** rather than force all PP difference into FA.

Old r5 **historical, not r6** evidence: at Vulkan `KV=49152 N=1024 Qcur-19 Br=16 Bc=64`, matched RGP FA main literature ~311–314 ms and code ~75.8–76.0 ms. Across the 49,152 16×64 tile classes, non-skippable tile counts were 31,614 vs 12,271. The old histogram alone did **not** save the 2D tile map. In this r6 investigation, first **revalidate** selected shader, query tensor/layer, tile geometry and mask classes; don't transfer r5 node timing.

## 2. Frozen experiment conditions (start with these, change one factor at a time)

| Factor | Freeze |
|---|---|
| GPU/OS | Radeon 8060S / Windows 11, physical display/RDP state logged, P-MODE Performance |
| UMA | **96 GiB** (user rebooted and restored on 2026-11-05); validate actual RAM/GPU allocation before a diagnostic capture |
| Source | r6 fork research branch, exactly pinned source commit and distinct new diagnostic EXE SHA + runtime manifest |
| Baseline binaries (do not overwrite) | Vulkan `build-vulkan-bench-real-r6` b12032; ROCm `build-rocm-bench-real-r6` b12038 |
| Model | Unsloth IQ3_XXS PLE16, file length 81,961,816,672 B (verify actual model identity per run); no updated Hugging Face weights |
| Corpus | Japanese `wagahaiwa_nekodearu_utf8.txt` SHA256 `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`; code `llamacpp-inference-code.txt` SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345` |
| Main measurement | ctx65536; `-p 61777`; **`--prompt-slice head`**; no generation; `-b2048 -ub1024 -t4 -ngl999 -ncmoe0 -fa auto -ctk f16 -ctv f16 -d0 -r1` |
| MTP | OFF, no draft |
| Vulkan | QSA UNION **OFF**; no experimental sparse switch, stats or perf logger; verify effective runtime env rather than assuming no env inheritance |
| ROCm | `QWEN4EXP_QSA_GATHER=0`, no experimental gather or MTP |
| Warmup/phase | Original seven baseline runs: **warmup ON**. For unambiguous diagnostic event alignment prefer **`--no-warmup`** on ALL new RGP/dump runs and their matching diagnostics-OFF control. This is a **new diagnostic control**, not interchangeable with the old warmup-ON speed baseline. Confirm first that the selected node reaches the expected prompt pass. |
| Resource | ADLX + Windows resource logging when usable; record physical RAM minima and GPU memory, GPU core/VRAM clocks, power/temp, background probe confidence |
| Files | Raw `.rgp`, tile maps, diagnostics archives saved outside Git; Git holds exact manifest, hashes, tables and small derived figures/analysis |

Use the **real-input r6 native `llama-bench`** for profiles so the same `-p 61777` and head slicing can be used on both backends. Do not substitute `llama-cli -f` without labelling it a distinct setup.

## 3. Coordinate contract: exact-matched GPU work

An RGP event match is valid **only** when both corpora agree, within one backend and one diagnostic build, on:
- actual PP phase (warmup vs timed; if warmup disabled, only one PP);
- real prompt source SHA and model identity; source/actual token count and tokenizer semantics;
- **physical** UBatch `n_q` (target 1024), **K tensor KV dimension** (target 49152), number of heads/GQA and any Q reshaping;
- same layer/query tensor identity (old `Qcur-19` is a candidate, not guaranteed on r6), same FA stage/pipeline/template, same Br/Bc/tensor shapes;
- exact user event/dispatch and captured RGP file identifier; effective QSA UNION/Gather env;
- GPU clock/power/occupancy context, and actual mask classifications where available.

Joint key proposal: `capture_id, source_commit, exe_sha, backend, model_id, corpus_sha, token_ids_sha_if_available, warmup_phase, n_prompt, ubatch, layer, query_tensor, KV, N, Br, Bc, fa_stage, shader, workgroup_shape, ordinal_range, capture_mode`.

**Matching by timer delay or by RGP dispatch ordinal alone is NOT matching.** The r5 Vulkan range start 180000 yielded KV49152 for r5 and cannot be presumed to do so on r6. RGP measures GPU dispatch work; a mask snapshot may change scheduling. **Never combine snapshot-ON timing with RGP marker-only timing into one single-event causal comparison.**

## 4. Gates / prioritized minimal experimental matrix

| Gate | Work | Result required before next gate |
|---|---|---|
| **G0 source + build design** | Compare exact r5 instrumentation to r6; create opt-in separate markers and packed-mask snapshot implementation plan, output schemas, test plan. Review HIP RGP correlation feasibility. | Native diff/patch list, verified flag OFF behavior, no foreign r5 source assumptions. This is the current deliverable. |
| **G1 short smoke** | Diagnostic Vulkan build in a NEW build directory; `-c2048 -p1024`, one corpus, `--no-warmup`; marker mode and snapshot mode separately. ROCm build only once needed. | `Status=OK`, correct GPU/backend, RGP label visible, one correct mask snapshot at reached KV1024 and `Qcur` selected from actual log; no GPU reset. |
| **G2 Vulkan mask** | One-shot **mask-map only**: literature and code, ctx65536, p61777, `KV=49152`, actual matched query/layer, 16×64 tiles if still selected. Separate control with all diagnostics OFF if needed. | Both maps with matching shape, valid category values, all rows/columns accounted for; compute 2D map + row/column skip hist + contiguous skip-run metrics. |
| **G3 Vulkan RGP** | Marker-only, no mask readback. Small 256-dispatch SQTT High capture; calibrate r6 ordinal→actual KV; target exact same `KV=49152` and query/layer on literature and code; obtain at least two matched captures per corpus only if the first pair demonstrates a meaningful difference. | FA `MASK_OPT` and `MAIN` timings separated; observed dispatch labels and shader identity, not inferred from r5; record GPU idle/occupancy. |
| **G4 ROCm RGP** | Same two corpora, r6 ROCm IQ3, ctx65536/p61777/UB1024. Verify HIP capture identifies prompt/layer/KV; start narrow, add host correlator if needed. | Matching ROCm FA kernel/template and exact KV/layer or clearly mark as exploratory and STOP causal cross-backend comparison. |
| **G5 interpretation/optional MoE** | Account for FA mask, GPU FA, MoE GEMM and CPU idle; only if residual warrants inspect selected experts or IQ3/IQ4×UBatch. | Explicit GPU contributions + remaining unexplained share, counterexamples and limitation statement. |

**Avoid** a full IQ3×IQ4×UB512×UB1024×2 corpora×2 backends RGP grid. G1–G4 prioritize **IQ3 UBatch1024**; add IQ4 only after FA hypothesis is tested.

## 5. Falsification and analysis

- A heatmap with **more code `ALL_NEG_INF` tiles** supports H1, but does not prove the actual warp executed fewer K/V loads. Check location (runs, distribution by query/KV), empty/sparse validity and the shader's other mask-dependent paths.
- If total skippable fractions look similar, but r6 Vulkan FA MAIN times diverge, prioritize placement, branch divergence, cache/memory behavior, and MoE/CPU residual. Do not dismiss H1 on aggregate ratio alone.
- If ROCm FA times at **matched** KV/layer are similar, H2 gains support; do not use r5 sampled 104.911ms / 111.198ms as matched-kernel evidence for new r6.
- Do not sum GPU operator times and equate them to PP wall time without overlap/idle accounting.
- Separate **observed**, **hypothesis**, **new instrumentation needed**, **not comparable** in findings.

## 6. Hard stop / safety

Stop the run, save all partial artifacts, and change scope before another GPU experiment on:
- Windows LiveKernelEvent/TDR 0x141, Vulkan `DeviceLost`, driver reset or system reboot;
- OOM, anomalous sustained disk/page-in behavior, sharply falling physical RAM, RGP SQTT truncation, unbounded GPU memory growth or monitor loss;
- incorrect model/binary/source hash, P-MODE mismatch, RGP targeting a different process, missing query/KV anchor, or label mismatch;
- a trace requiring guesswork to associate RGP event with a layer/token location.

r6 Vulkan IQ3 already peaked **82,950 MiB ADLX GPU memory** at UMA96. ROCm PLE16 IQ3 peaked around **54 GiB GPU memory**, **but host free physical RAM transiently fell to ~0.05 GiB when loading at UMA96**; profile with ADLX+RAM monitor and **separate capture windows**, not aggressive overlapping instrumentation. If ROCm profiling needs UMA64 for safety, do so as a labelled **separate condition with its own unprofiled control**; never mix an UMA64 profile with the UMA96 baseline as if the environment were identical.

## 7. Ownership and current boundary

This branch contains **design documents only** as of 2026-11-05. No existing r6 source, shaders, wrappers or known-good binaries are modified in this planning commit. Target future instrumentation changes: `ggml/src/ggml-vulkan/ggml-vulkan.cpp` and the Vulkan context types for the snapshot, possibly a minimal backend-independent token/graph anchor and HIP correlation surface; tests and experiment configs are later separate commits.

Read [source inventory](R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md) and [native runbook draft](R6-PP-RGP-MASK-RUNBOOK-DRAFT-2026-11-05.md) before implementing G1.
