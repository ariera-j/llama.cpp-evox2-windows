# r5 integration handoff: long-context model quality and follow-up — 2026-10-25

## Status and source of truth

**Quality comparison completed; now prioritize refreshed-upstream r5 integrated candidate.** This document is a scheduling/regression note, not a change to the patch porting order, QSA/ROCm implementation, build procedure or integration safety gates.

Full benchmark designs, runnable Python tools, PSD1 plans, synthetic smoke fixtures, provenance and per-question results are in the separate [evox2-llm-experiments search/retrieval directory](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval). See [experiment overview](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval/EXPERIMENTS-2026-10-25.md) and [MH-128K results](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval/mh-128k/results/MH-128K-QUALITY-SUMMARY-2026-10-25.md). **Do not duplicate these scripts or the detailed dataset in the llama.cpp source repository.** Keep raw run ZIPs and full calibrated Windows production prompts in local archival storage.

## Completed work (Vulkan b11592, Qwen3.8 and reference Gemma)

- Historical Qwen3.5-derived “V1” *direct DOC-ID lookup* (not to be confused with the conceptual V1 conjunction taxonomy): IQ3 128k A/B **7/7**, 192k A/B **7/7**. Its Q7 is a constant `NO` control, not an independent hard question.
- CR-128K conjunctive retrieval: IQ3 A/B **12/12** at seed 20260913. These are valid direct/conjunction baselines but showed a ceiling effect for this model.
- MH-128K two-hop retrieval: 128k, **two independent data seeds (20261025, 20261026)**, A/B question order, 12 main + 2 local control questions; 4 Qwen variants × 2 seeds × A/B = **16 runs**.

| Model | 20261025 A / B | 20261026 A / B | Total (A/B not independent samples) |
|---|---|---|---:|
| Unsloth IQ3_XXS PLE16 | 12 / 11 | 11 / 11 | 45/48 |
| Agention ROCmFP4 FAST v2 PLE16 | 12 / 12 | 12 / 12 | 48/48 |
| Unsloth IQ4_XS PLE16 | 12 / 12 | 12 / 12 | 48/48 |
| Huihui abliterated IQ4_XS PLE16 | 12 / 12 | 11 / 11 | 46/48 |

All 16 succeeded with exit 0, no truncation, valid schema, Q13/Q14 local controls correct, ADLX telemetry present and direct P-MODE Performance at both ends. IQ3 misses match one-condition SRC decoys; Huihui misses match a near-link-code DST and a known background DST value, respectively. These are **output/data correspondences, not proven internal decision paths**. Huihui is an abliterated derivative, not byte-identical weights to original IQ4. The observed gaps are **not proof of a causal quantization-quality effect or statistical significance**.

## Measurement provenance and comparability

- EVO-X2 / Windows 11 / UMA96GB, `llama-cli` Vulkan **b11592, binary-source commit `9d4721fb8`** from `build-vulkan-r5-noop-rocmfpx` (integration-check lineage). r5 main supplied the **benchmark/ADLX/P-MODE scripts**. Running `git rev-parse HEAD` on the script branch does not identify the compiled binary source.
- Context 131072, MTP OFF, QSA optimization OFF, f16 KV, full GPU offload and fixed sampling for matched conditions. Model-specific tokenizer counts differ; data were calibrated against all five tokenizers. For MH, Qwen raw input 111166/111148 llama-cli tokens for seeds 20261025/20261026, respectively.
- Across 16 MH runs, high-load VRAM clock did not fall below 900 MHz; observed top GPU temp 92°C (FP4-B of second seed). Keep ADLX clock/power/temp and P-MODE for the integration regression, including the known possible non-decisive power-derived P-MODE mismatch warnings.
- Separate reference: Gemma 4 31B IT QAT q4_0 completed 128k MH A/B but PP was approximately **17 tok/s** and TG approximately **5.66 tok/s** (about **114 minutes/run**); it had lower retrieval scores (A 4/12, B 6/12). It is **not** one of the four models in the 16-run Qwen primary table. Not a reason to delay integration or to automatically prioritize Gemma tuning. The execution was GPU-offloaded but backend kernel attribution (e.g. Flash Attention fallback) has **not** been proven.

## Immediately next: integrated build and minimum regression gate

1. Freeze a fresh upstream SHA as prescribed by [R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md); do not infer it from stale watchpoint hashes. Preserve the semantic port order and backend acceptance tests from that authoritative plan (ROCmFPx, PLE16, VULKAN-002, MTP-DENSE/NOOP, Stage-B/flatten where accepted).
2. Confirm source/runtime identities, TheRock SDK 10.0 DLL policy, GGUF hashes, driver, P-MODE, ADLX, memory and actual binary build SHA in every comparison. Never rebuild the archived `build-vulkan-r5-noop-rocmfpx` under a different branch and misattribute it.
3. Validate short-context functionality and model-load smoke tests for IQ3, IQ4, Huihui, ROCmFP4, and Gemma 4 as required by the existing integration plan; verify target/draft MTP and the ROCmFPx backend separately.
4. After a working candidate, run **a minimal set of frozen-input quality regressions** with MH-128K. Prefer seed **20261026** where IQ3 and Huihui exhibited known failures: use A/B as needed for IQ3, original IQ4, FP4 and Huihui; verify exact question mapping, controls and stdout format. Start with small samples rather than reflexively repeating 16 costly runs. Any changed answer requires first checking prompt SHA, model hash, sampling, executable identity, KV and backend before asserting an algorithm regression.
5. Compare PP/TG and ADLX telemetry against the old b11592 **only where matched inputs and backend conditions permit**. Preserve old results; a refreshed upstream is not a like-for-like patch microbenchmark unless controlled.

## Post-integration, not blocking candidate creation

- **Quality**: design a separate harder MH-Hard test requiring discriminating **multiple valid SRC→DST paths** with cross-block conditions. Avoid changing the frozen MH-128K seed datasets or tuning questions to force failure by IQ3 specifically. Extend seeds / counterbalancing and diagnostic intermediate `LINK_CODE` only where needed.
- **Gemma 4 speed**: repeat first on the integrated build, with 16k/32k and a representative longer context. If still disproportionately slow, profile Vulkan Flash Attention (possible kernel-selection/large-head fallback is a hypothesis, **not confirmed**), then decide whether Gemma is a performance optimization target and where to rank it among Qwen work. Do **not** put Gemma optimization ahead of r5 completion based solely on the old 128k number.
- **Deferred technical research**: visualize QSA selected IDs/masks across input types, inspect MoE expert-selection/routing differences for the same corpora, finish selected ROCm RGP captures; use the separate [post-integration candidate review](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md) to rank new patches based on the integrated baseline.
- **Local scripts hygiene**: old Huihui test configurations may remain untracked in the local Windows checkout; decide which generic examples belong in source control after integrating, and preserve machine-local file paths outside public docs. Do not delete local test evidence as part of branch switching.

## Interpretation boundary

The two-seed/16-run MH suite is **diagnostic evidence** for these fixed datasets, not a statistical quality ranking. A/B reuses the same questions. Incorrect values can match known decoy outputs without proving that the model actually traversed those internal records. Keep this distinction in future publications and regressions.
