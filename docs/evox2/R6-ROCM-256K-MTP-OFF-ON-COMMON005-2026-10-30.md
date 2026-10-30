# R6 ROCm 256k MTP OFF/ON night run and COMMON-005 research direction — 2026-10-30

**Status: MEASURED, 2/2 CLI runs PASS; next step is MTP-OFF-first COMMON-005 investigation, not a patch or a runtime-default change.**
This is a post-tag follow-up to the [S9 long-context inventory](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md), using the newer `main` branch benchmark scripts. The user explicitly prefers investigating the ROCm **MTP OFF** path first: if a safe compact-QSA implementation makes ROCm MTP OFF's *TG* faster than the current ROCm MTP ON setting while retaining its PP advantage, then ROCm MTP OFF is an acceptable operational profile. This is a conditional research decision, not an immediate switch.

## 1. Measured workload and provenance

- Host: GMKtec EVO-X2 / Radeon 8060S `gfx1151` / Windows / manually configured **96 GiB UMA**, Performance P-MODE, ROCm/TheRock 10.0.
- Verified existing integrated ROCm **b11908**, executable source commit `b82243bf0` (full source `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`); both runs have the same `llama-cli.exe` SHA256 `1bbd4a5102b6181d8de92faf2d42e49f96ba2ad4b04b7c7f9e6aafc168d322b1` and runtime-artifact digest `e110ec316834fc92e80e0b7460d60431793a1a3a579e22968e153d0991a073f7`, `Verified`.
- Model: Unsloth Qwen3.8 Flash Next **UD-IQ3_XXS PLE16**; MTP ON uses Unsloth Q8_0 MTP draft. Main-model GGUF size/mtime match between the two runs; a full model SHA256 was *not* requested, so avoid claiming full GGUF hash equivalence.
- Input: same 255,181-token paper `nlp-survey-ch3-d31-b1.txt`, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, `-c 262144`, 512 generated tokens per run, no context truncation.
- Common settings: `-ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 1024 -fa auto -ctk f16 -ctv f16 -fit off`, `--cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --jinja --single-turn --ctx-checkpoints 0t --seed 1234 --ignore-eos`. MTP ON: `draft-mtp`, draft GPU layers 999, `--spec-draft-n-max 2 --spec-draft-p-min 0`, f16 Draft KV.
- Run order: **MTP OFF → 60-second cooldown → MTP ON**, sequential, **one run for each arm**. MTP OFF: `LLAMA_MTP_SKIP_DENSE_INDEXER=0`, `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0`. MTP ON: both `=1`, with both implementation decisions `Verified` in `result.json`. ROCm's Vulkan union, Stage-B and EH-proj flatten flags explicitly `0` in both conditions.
- Measurement plan: [`qwen38-r6-rocm-256k-mtp-off-on-20261030.psd1` on main](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-256k-mtp-off-on-20261030.psd1). New post-tag monitoring from `main`: system resources 2s, background process activity 15s, ADLX enabled, P-MODE sampled at start/end.
- Uploaded ZIP: `20261030-005502-610-cli-rocm-b11908-ctx262144-6beafe3347f6.zip`, **SHA256 `2bb7a64790cdb0fbd3a766926b04b4fde96e6748b496db206e71c1b4f40f00f4`**. The ZIP contains **two** separate run directories (do not infer run count from ZIP filename): `20261030-003047-618-cli-rocm-b11908-ctx262144-ff02ad956445` (OFF) and `20261030-005502-610-cli-rocm-b11908-ctx262144-6beafe3347f6` (ON). Both `Status=OK`, `ExitCode=0`. Raw ZIP/model/host-local paths are not committed.

## 2. ROCm 256k measured results

Values come directly from the two archived `result.json` records; PP and TG are reported by the existing CLI parser. One run per arm is **not** a statistical A/B proof.

| Metric | MTP OFF / DENSE+NOOP OFF | MTP ON / DENSE+NOOP ON |
| --- | ---: | ---: |
| Status / exit code | OK / 0 | OK / 0 |
| Prompt tokens / generated tokens | 255,181 / 512 | 255,181 / 512 |
| **PP tokens/s** | **198.95** | 185.00 |
| **TG tokens/s** | 12.66 | **14.80** |
| PP eval time (ms) | 1,282,656.53 | 1,379,350.42 |
| TG eval time (ms) | 40,374.35 | 34,525.96 |
| Total eval time (ms) | **1,323,030.88** | 1,413,876.38 |
| Draft accepted / generated | N/A | 286 / 448 |
| Draft acceptance | N/A | 63.839% |

**Observed trade-off:** vs MTP OFF, MTP ON PP is **7.01% lower**, TG **16.90% higher**. With this 255k-input / 512-output workload, MTP OFF completes evaluation about **90.85 seconds earlier** (~6.4% less than the ON total) because the PP cost dwarfs the ~5.85 seconds saved in generation. For generation-centric or short-prompt workloads the choice can differ. The total values are inference evaluation times, **not full process launch/model-loading wall time**.

### Historical checkpoints: do not imply identical experimental conditions

| Checkpoint | MTP | PP tok/s | TG tok/s | Interpretation |
| --- | --- | ---: | ---: | --- |
| r3 COMMON-005 Gather OFF (256k ROCm) | OFF | 167.58 | 11.68 | Historical ABBA average |
| r3 COMMON-005 Gather ON (256k ROCm) | OFF | 167.99 | **17.37** | Historical ABBA average; gather enabled |
| r6 b11908 DENSE+NOOP ON (2026-10-29) | ON | 184.79 | **15.04** | Older single run, acceptance 289/441 |
| r6 b11908 DENSE+NOOP ON (2026-10-30) | ON | 185.00 | 14.80 | New monitor, acceptance 286/448 |
| r6 b11908 MTP OFF (2026-10-30) | OFF | **198.95** | 12.66 | New 256k PLE16 MTP-OFF baseline |

Historical r3 reference: [COMMON-005 validation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/r3/upstream-first/docs/evox2/COMMON005-VALIDATION-2026-10-02.md), implementation commit [`d03c91b`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/d03c91b6342b099457de3508c5d67533a9a5f0ee). r3 used MTP OFF, generation budget 1024, temperature 0.2 and earlier qwen4exp/QSA code; r6 uses generation 512, temperature 0 and a newer architecture. **17.37 is a historical research target, not an achievable-speed prediction or a directly controlled regression measurement.**

Prior b11908 256k MTP ON **15.04 → 14.80 TG** in the new run (~-1.60%), with acceptance changing from 289/441 (~65.5%) to 286/448 (~63.8%). This one historical-versus-new comparison does not establish a monitoring-related slowdown.

## 3. New monitoring evidence and limitations

| Metric | MTP OFF | MTP ON |
| --- | ---: | ---: |
| Resource rows (2s nominal cadence) | 682 | 727 |
| ADLX rows | 688 | 736 |
| In-run named-background-process probes | 85 | 90 |
| Median background probe duration | 60.6 ms | 58.25 ms |
| Maximum background probe duration | **4,914.1 ms** | **5,051.5 ms** |
| Background probes over 1s | 1 | 2 |
| Maximum observed resource sample interval | 5.983 s | 6.123 s |
| Mean high-load GPU power (ADLX) | 116.956 W | 116.534 W |
| P-MODE start / end | Performance / Performance | Performance / Performance |
| Named-process background activity coverage at run boundary | **Partial/unknown** | **Complete; PossibleNoise=False** |

The 15s named-process probes are not free: rare ~5s PerfProc/CIM calls can delay resource-sampling cadence, and cannot be assumed to have zero inference overhead. The OFF run's `BackgroundActivitySummary.PossibleNoise` is **null** due to partial coverage; do **not** present it as a clean/quiet run. ON had complete coverage at boundary but this still cannot rule out short-lived interference or generic `svchost` work. Neither run reports a P-MODE inconsistency; high-load GPU power is Performance-like (117.0 / 116.5 W), ADLX monitor exited with code 0. Nothing in this small sample proves that the monitor caused the ~1.6% TG difference.

For a later *causal* measurement-overhead test, use same-executable/same-input A/B with `-ResourceMonitor` vs no resource monitor, or hold identical 30s/60s background cadence in all patch comparisons. Remember start/end named-process snapshots occur even when resource monitoring is disabled in the new wrappers. [Post-tag monitoring implementation and caveats](../../tools/evox2/benchmark/BACKGROUND-ACTIVITY-MONITORING.md).

## 4. User-selected next research priority: MTP OFF first

**Decision on 2026-10-30:** prioritize **ROCm MTP-OFF single-token decode** and the formerly deferred **COMMON-005 selected-K/V gather → compact QSA Flash Attention** idea before attempting MTP-ON optimization. Do not switch the published defaults or declare COMMON-005 adopted until a controlled test passes.

Why: r3 COMMON-005 historically improved ROCm 256k TG **11.68 → 17.37 tok/s (+48.7%)** with essentially unchanged PP. Current r6 MTP OFF already gives **198.95 PP** versus MTP ON's 185.00 but **12.66 TG** versus 14.80–15.04. If compact QSA can raise OFF TG **above the current ON level** without losing PP or stability, the user may **choose ROCm MTP OFF for routine use**, avoiding Draft workload and MTP ON's long-context PP cost.

- A *minimum TG direction target*, not a promised patch result: **>14.80 tok/s** (+16.9% vs current OFF) to beat the new ON measurement; preferably exceed the older **15.04 tok/s** (+18.8%) with repeatable margin. Preserve/compare OFF PP near 198.95, full end-to-end workload time and output correctness. Do not require matching r3 17.37 before recognizing a practical gain.
- Do not promote a global ROCm MTP OFF default from a single 256k result. Compare at 64k and 128k and under realistic input/output ratios; ensure the chosen server/backend profile remains stable. Users can choose per-backend MTP OFF without changing Vulkan's independent MTP settings.
- Old COMMON-005 targeted **single-token decode** (`n_tokens == 1`). MTP-ON speculative target verification can have multiple tokens, so a single-token gather path may not run and cannot be assumed to improve MTP ON. Any MTP-ON port/rewrite is a separate follow-up only if needed.
- Current qwen4exp selection/mask semantics differ substantially from the r3 implementation (`build_qsa_sel` vs prior `build_qsa_top_k`, fused mask, selected block/tail handling). **Do not blindly cherry-pick** the old patch. Verify selected K/V indices, mask/causal visibility, tail placement, sentinel and layout contracts, fallback and correctness first.
- Maintain the stable integrated **b11908** and immutable tagged release as control; any source experiment lives on a new isolated research branch, opt-in with explicit default **OFF** and safe fallback. Both Gather ON/OFF need to be measured using the **same newly built patched binary**, not merely old r3 against b11908.

### Proposed validation sequence (not executed)

1. Reproduce the 256k/128k ROCm MTP-OFF baseline and, if useful, obtain narrowly scoped RGP/HIP evidence for full-KV Flash Attention and QSA mask/indexer time shares. Avoid guessing a bottleneck solely from total TG.
2. Audit current upstream/qwen4exp QSA selection and HIP FA eligibility; implement a guarded `QWEN4EXP_QSA_GATHER`-style **opt-in**, initially eligible only for validated MTP-OFF single-token decode shapes. Keep all other flags fixed.
3. Build/run short context and targeted correctness/shape/rollback-safe checks first, then 64k → 128k → 256k real-document A/B. Use same model/input hashes, 96GiB UMA, Performance P-MODE, known ROCm DLL provenance, f16 KV and a **fixed monitoring cadence**. For the 256k acceptance run, prefer repeated/ABBA ON/OFF (budget permitting) and examine output/PP/TG/wall time; ROCm has known output/`ggml_top_k` nondeterminism, so do not require byte-identical output.
4. If MTP-OFF TG repeatedly exceeds both contemporary MTP-ON TG controls without losing PP, correctness or stability, trial a **ROCm-only MTP OFF operating profile**; retain MTP ON as a selectable fallback. Otherwise keep MTP ON as appropriate and investigate the remaining long-context hotspot or MTP-specific work separately.
5. **Safety:** do not launch the broad ROCm `FLASH_ATTN_EXT` backend suite or `Build-ROCm.ps1 -RunBackendTest` on gfx1151 because of prior Windows WATCHDOG/Kernel-Power risk; use targeted tests only. No implementation, rebuild, new automation, source tag, release asset or default flag change is authorized by this research note.

This 2026-10-30 plan supersedes the **MTP-ON-first wording only** in the 2026-10-29 research priority; it does not revise the original 2026-10-29 measurement inventory, the S8/S9 acceptance decisions, the Vulkan release scope or older history.
