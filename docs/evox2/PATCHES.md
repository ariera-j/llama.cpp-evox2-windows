# Evo-X2 downstream patch registry

> **r6/S8 G8-6 runtime decision closed (2026-10-28):** [Measured G8-6 PASS and raw ZIP SHA256](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md#g8-6-windows-measured-closure---2026-10-28-jst); [S8 combined results](R6-S8-COMBINED-RESULTS-2026-10-28.md) and [supported flag profiles](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md). Vulkan IQ3 server MTP-OFF/ON, Jinja multi-turn, real64 input and ROCm independent MTP-OFF server PASS; tokenizer EN/JA parity PASS. G8-6 ZIP SHA256 `6d143104949649cf89b3ffa6fa11b4a848eab61a0d2aaf9829871712b0395f38`. Vulkan union/DENSE/NOOP PASS opt-in for tested paths; Stage-B/flatten numerical parity DEFER and defaults OFF. ROCm DENSE/NOOP CLI opt-in, MTP-ON server DEFER. **Next S9 final models, not new S8 patch work.** The PREPARED block below is superseded.

> **r6/S8 G8-6 runbook prepared (2026-10-28; NOT EXECUTED):** [Windows `llama-server`/Jinja/multi-turn/real64 procedure](R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md) and [backend/model flag decision sheet](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md). G8-5 measured evidence below remains authoritative. All five switches stay source-default OFF; Vulkan all-ON is an explicit lab profile, not a general default. ROCm Stage-B/flatten and numerical Draft K/V parity remain DEFER; do not grant S9 candidate status until G8-6 evidence is reviewed.

> **r6/S8 G8-5 selective 256k stability PASS (2026-10-28):** [Measured 1/1 run and raw ZIP SHA256](R6-S8-GATE5-SELECTIVE-STABILITY-RUNBOOK-2026-10-28.md#windows-measured-result-and-g8-5-closure---2026-10-28-jst). IQ3 PLE16 Vulkan b11908, MTP ON with five explicit S8 flags: 255,181 input / 512 generated, PP 301.30 / TG 25.08 tok/s, accepted 298/425, exit0, no truncation. GPU 49/49 main + 50/50 Draft, QSA-union active, DENSE/NOOP Verified, P-MODE/ADLX consistent, minimum free RAM 22.64 GiB. **Stability PASS only**, not a 256k performance attribution, numerical Draft K/V parity PASS or default flag promotion. No second 256k run; proceed G8-6 and S9 after runtime/preset decision freeze.

> **r6/S8 G8-4 Stage-B/flatten Vulkan output gate closed (2026-10-28):** [Measured 14/14 results and caveats](R6-S8-GATE4-STAGEB-FLATTEN-RUNBOOK-2026-10-28.md#g8-4-windows-measured-closure---2026-10-28-jst). IQ3/ROCmFP4 4k C/A/B/D and 64k C/A/B all exited 0, retained per-cohort normalized output hashes and exact MTP accepted/generated, verified D=C 4k inertness, and passed 64k P-MODE/ADLX. Single ordered 64k C/A/B PP was +4.27/+5.69% (IQ3 A/B versus C) and +4.22/+6.10% (FP4); **not repeated speed proof**. A possible Windows Defender scan during FP4 M002 is a performance confounder, not an observed functional failure. No b11908 Draft K/V snapshot support: **numerical parity DEFER; Stage-B/flatten default OFF**. G8-5 is now complete (see checkpoint above); no source changes for this evidence-only closure.

> **r6 / b11870 active execution plan (2026-10-25):** [R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md) fixes patch order, prerequisites, per-stage performance gates, model scope and failure/defer rules. The r5 matrix below remains the prior validated patch inventory and historical evidence; old unqualified "next" wording no longer overrides the r6 plan.

> **r6 S5 DENSE closure (2026-10-26):** [Final S5 evidence](R6-MTP-DENSE-S5-IMPLEMENTATION-2026-10-26.md#5-evo-x2-final-s5-results-and-closure-2026-10-26-jst) records native correctness PASS and 18/18 long runs: IQ3 Vulkan TG +6.99%/+16.32% (64k/128k), IQ3 ROCm +9.55%/+12.11% observed with inherent output variability, ROCmFP4 FAST Vulkan 64k +7.51%. All PP differences within 0.21%; DENSE remains opt-in/default OFF. Next: the separately toggleable MTP-NOOP-001 experiment, then Stage-B/flatten without reordering the pinned plan.

> **r6 S6-NOOP gate complete (2026-10-26):** [Source audit, Windows native tests, 18/18 long runs and archived evidence](R6-MTP-NOOP-S6-IMPLEMENTATION-2026-10-26.md#windows-final-gates-and-s6-noop-closure-2026-10-26-jst). `r6/mtp-noop-20261026` extends S5 with target-only `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` (default OFF); DENSE stayed ON in both A/B arms. Vulkan IQ3 TG improved **+3.00%/+6.18%** at 64k/128k with exact output/Draft acceptance parity; FP4 FAST Vulkan 64k **+3.01%** (one A/B pair). ROCm IQ3 observed **+2.80%/+3.00%** with previously known nondeterministic output/acceptance. Both backends' native policy/state/rollback tests and short smoke PASS; P-MODE/ADLX normal, PP near-flat, no 256k. **Retain as an independently switchable integration candidate; next distinct source task is Stage-B, then flatten under separate flags.** The original integration patch order is unchanged.

> **r6 S7-A Stage-B Vulkan gates PASS (2026-10-27):** [`r6/mtp-stageb-20261027` implementation and measured closure](R6-MTP-STAGEB-IMPLEMENTATION-2026-10-27.md#s7-a-windows-vulkan-native-and-runtime-gate---2026-10-27) derives from S6-NOOP `02e44a240`. Exact-1 `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` remains opt-in/default OFF; no flatten yet. b11903 source/build identity verified; S5/S6 policy/state/rollback tests PASS (NOOP 524/524), 4k IQ3/FP4 smoke PASS. IQ3 Vulkan 64k/128k ABBA PP **+4.65/+6.87%**, TG **+1.97/+2.94%**; ROCmFP4 FAST Vulkan 64k A/B PP **+4.74%**, TG **+1.78%**. **10/10 long runs PASS** with exact per-cohort output/Draft acceptance parity and consistent Performance-mode ADLX; FP4 has one ordered pair, not a repeated ABBA. Direct K/V numeric parity and GPU FA-pruning proof remain separate, ROCm remains untested. **Next is a separate S7-B flatten branch**, never silently combining its PP with Stage-B. The [2026-10-27 numbering revision](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md) uses S5 DENSE, S6 NOOP, S7 Stage-B/flatten, S8 combined, S9 final models.

> **r6 S7-B flatten Vulkan measured closure (2026-10-28):** [Complete b11906 evidence, run-level anomalies, and archive SHA256](R6-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-27.md#s7-b-windows-vulkan-measured-closure---2026-10-28-jst). `r6/mtp-eh-proj-flatten-20261027` / `3e377c238` builds on S7-A; `LLAMA_MTP_EH_PROJ_FLATTEN=1` works only inside the eligible Stage-B graph, and defaults OFF. S5/S6 native regressions PASS (NOOP **524/524**); IQ3/FP4 C/A/B smoke **6/6 PASS**; IQ3 Vulkan 64k (8run) PP **+1.58%**, 128k (4run) **+1.31%**, FP4 FAST Vulkan 64k (4run) **+2.02%**. **16/16 long runs** preserve generated-output SHA and Draft accepted/generated per cohort with P-MODE/ADLX normal. The first B1 at IQ3 and FP4 64k each showed ~0.9s TG lag, not repeated in B2/second IQ3 ABBA; do not claim TG parity is proven in every run. Independent Draft K/V numeric parity and ROCm S7 remain open. **S8 candidate / default OFF**. Next: [S8 combined-source validation and per-flag decision plan](R6-S8-COMBINED-INTEGRATION-PLAN-2026-10-28.md). Never add isolated percentage gains to predict an all-on build.

## Authoritative current r5 patch disposition — 2026-10-21

**This section is the current integration decision table.** It supersedes dated “LATEST/NEXT” text below for planning, while all older sections remain as time-stamped experimental evidence.

The pinned research/control lineage remains `r5/upstream-refresh-20261009`. No latest-upstream integrated release exists yet. The next integration session should freeze one exact current upstream SHA first; the point-in-time 2026-10-21 master snapshot `493253fe5a5af7e800b3c92a2452b5684a99e961` is 270 commits ahead of the pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`, but it is **not yet the selected candidate base**.

Current authoritative build/order details: [R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md).

Post-integration optimization research is tracked separately in [R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md). That 2026-10-21 snapshot does **not** add s1/Strata/halo/Gufo experiments to the first integration candidate. Its provisional order begins only after the integrated baseline is frozen: runtime/build/MMVQ audit → transposed CONCAT → residual Vulkan FA → measured remaining GPU/host work → small-weight/Draft/QSA follow-ups. Re-audit upstream and donor revisions when that work actually starts.

### ROCm runtime provenance policy — 2026-10-21

[ROCm runtime provenance / same-binary ABBA](R5-ROCM-RUNTIME-PROVENANCE-ABBA-2026-10-21.md) establishes a new provenance boundary for Windows ROCm results.

- Existing b11521 and earlier r5 ROCm binaries may have been **compiled with TheRock 10.0 but run with a mixed BLAS stack** because the old build script staged only `amdhip64_7.dll`, `amd_comgr.dll` and `rocm_kpack.dll`. On the investigated b11521 run, `hipblas.dll`, `rocblas.dll` and `hipblaslt.dll` were loaded from the `C:\Program Files\AMD\ROCm\7.2\bin` install root.
- This does **not** invalidate same-environment patch A/B results. It does mean that old absolute ROCm results and cross-build/runtime claims must preserve the historical runtime qualification.
- From build-script change **2026-10-21 onward**, normal `Build-ROCm.ps1` staging is `TheRockUnified`: SDK version guard defaults to **10.0.0**, and the script copies the full HIP/BLAS DLL closure plus `rocblas` and `hipblaslt` target data trees beside the executables and records their provenance/digests in `evox2-build.json`.
- The 64k same-binary mixed-vs-unified ABBA found no meaningful warmed throughput advantage for the mixed layout (B2 pure TheRock vs A2 mixed: PP +0.19%, TG -0.76% for pure TheRock). First-run PP differences were concentrated in the first 8k and correlate with cold disk/runtime data activity.
- Do not retroactively relabel pre-change binaries as pure TheRock. Future performance baselines should use the unified runtime unless a runtime-compatibility experiment explicitly requires otherwise.
- The follow-up ROCm output-repeatability investigation is now complete: [R5-ROCM-QSA-REPEATABILITY-2026-10-22.md](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md). Same-parent / same-TheRock-10.0 64k control runs using Qwen4Exp `ggml_top_k` produced **4 distinct outputs / 4**, while `ggml_cont(ggml_argsort_top_k(...))` produced **1 identical output / 4**. FA OFF did not restore repeatability, so QSA top-k selection is the strongest localized cause of the observed ROCm greedy-output drift.
- Keep the normal fast `ggml_top_k` path as the performance/default path. A proposed future opt-in `QWEN4EXP_QSA_DETERMINISTIC_TOPK=1` may select argsort+cont for quality/regression/corpus-comparison runs where stable output matters. This is a **QSA-selection determinism control**, not a guarantee of global model determinism. Current ROCm validation is 64k only; longer contexts need separate coverage.
- **Windows/gfx1151 backend-test safety:** the 2026-10-22 broad `FLASH_ATTN_EXT` sweep hit the known DKQ=64 + logit-softcap support/dispatch mismatch, reached a HIP `NO_DEVICE_CODE` / trap path, and the same incident is correlated with Windows `LiveKernelEvent 141` plus `WATCHDOG-20261022-0244.dmp`. Until that mismatch is fixed, do **not** use the full FA sweep or `Build-ROCm.ps1 -RunBackendTest` as a routine build gate on this machine; use targeted backend-op tests instead.

### Status meanings

- **移植予定**: semantically reapply on the selected newer upstream only if equivalent functionality is still missing; no blind cherry-pick or whole-file copy.
- **要確認**: audit upstream overlap/need first.
- **移植しない予定**: keep evidence, but do not carry the historical source into the first candidate.
- **本流に存在**: actually tracked on `r5/upstream-refresh-20261009`.
- **検証済み** always refers to the exact dated branch/build/backend/model/conditions in the linked report.

### A. First integrated candidate — planned feature set and gates

| Patch / capability | Stable r5 source | New evidence through 2026-10-21 | Integration decision |
| --- | --- | --- | --- |
| **COMMON-001** — split PLE16 loader | **Present / verified** | Original + split PLE16 load and Vulkan/ROCm checks completed on r5 | **移植予定 / required if still missing upstream**; smoke Original + split before benchmarks |
| **COMMON-003 / ROCmFPx core** | **Not in stable inference source** | Isolated r5 port complete: loader/core + CPU fallback; Agention ROCmFP4-FAST target real inference through 256k; matching old-layout ROCmFP4 MTP sidecar works at 32k/64k and DraftMax=7. [Core](R5-COMMON003A-ROCMFPX-CORE-IMPLEMENTATION-2026-10-20.md), [full port record](R5-ROCMFPX-VULKAN-PORT-PLAN-2026-10-20.md) | **移植予定 / feature prerequisite** for Agention target+draft if selected upstream still lacks it. Treat as compatibility/correctness support, not a speed patch |
| **VULKAN-001A/B** — ROCmFPx Vulkan correctness + integer-dot | **Not in stable inference source** | Isolated and NOOP-integrated validation complete. Five formats, MUL_MAT + MUL_MAT_ID, widths 1,3–8, default + forced-MMVQ: **140/140 PASS**. Real target full-GPU, coherent output. [001A](R5-VULKAN001A-ROCMFPX-CORRECTNESS-IMPLEMENTATION-2026-10-20.md), [001B](R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-21.md) | **移植予定** when Agention ROCmFP4 is required on Vulkan; semantic/hunk-level port only |
| **Agention old-HC MTP compatibility** — old `output_hc_*` final mixer | **Not in stable** | Required by the current Agention MTP sidecar; validated through 64k plus DraftMax=7 on isolated ROCmFPx branch | **移植予定 only if latest upstream still requires it**; prefer current layout when present, fallback to old layout |
| **COMMON-002 minimal ratio-zero k-pool guard** | Stable native MTP; local guard **not in stable** | Required by old ratio-zero dense MTP sidecars; same failure/fix validated on ROCmFPx Stage5. NOOP branch already contains equivalent guard in its experimental lineage | **移植予定 only if native selected upstream still registers unused k-pool input**; no wholesale COMMON-002 resurrection |
| **VULKAN-002** — grouped-union QSA prefill | **Present / opt-in** | Historical 64/128/256k PP gains remain valid for pinned r5/f16 KV. New NOOP+ROCmFPx all-on smoke actually entered `qsa-union active` during prefill and correctly fell back for one-query decode. [integration rehearsal](R5-NOOP-ROCMFPX-INTEGRATION-CHECK-2026-10-21.md) | **移植予定 / P0 source audit** unless newest upstream provides equivalent functionality; keep opt-in and f16-KV-specific |
| **MTP-DENSE-001** — skip ratio-zero Draft indexer | **Not in stable** | Pinned-r5 Vulkan 64/128/256k TG +6.81/+15.52/+36.22%; ROCm observed +7.72/+17.42/+23.48% with nondeterministic outputs. Runtime coexistence with ROCmFPx + VULKAN-002 + NOOP proved in 10/21 integration rehearsal | **移植予定 / after native MTP compatibility**, independent switch and new-base A/B |
| **MTP-NOOP-001** — suppress Target QSA no-op invalidation | **Not in stable** | Pinned-r5 Vulkan incremental TG +2.10/+6.73/+14.40% on top of DENSE. Native policy/model-state/rollback gate passed in combined ROCmFPx rehearsal; all-on short run had target/draft full GPU and coherent MTP. [integration rehearsal](R5-NOOP-ROCMFPX-INTEGRATION-CHECK-2026-10-21.md) | **移植予定 / after DENSE**, keep policy fail-closed and independent switch |
| **MTP Stage-B** — Draft KV-only zero-output prefill | **Not in stable** | b11618 Vulkan PP improvement previously validated; later 128k Draft state equality + 64k natural/forced rollback parity. 10/21 source rehearsal shows Stage-B can coexist structurally with VULKAN-002+DENSE+NOOP+ROCmFPx+old-HC. [combined source review](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md) | **移植予定 / P0 after DENSE+NOOP**, separate opt-in, short C/A/B then 64k/128k |
| **MTP `mtp_eh_proj` flatten** | **Not in stable** | Pinned-r5 same-binary +1.386/+1.397% PP at 64/128k under Stage-B; RGP main projection ~56–58ms→~4ms. Source-level coexistence with the full pre-Stage-B stack confirmed 10/21 | **移植予定 / after Stage-B**, separate flag scoped to Stage-B prefill |
| **Gemma 4 regression gate** | Existing working fallback is upstream prebuilt b10919, outside r5 source | No new integrated-build run yet | **Required post-integration acceptance**, per-model for 31B IT QAT q4_0 and 26B A4B IT QAT UD-Q4_K_XL before replacing b10919 |

### Combination status — do not overstate

The earlier caveat that DENSE/NOOP and ROCmFPx had never been combined is now obsolete.

**Runtime PASS on pinned r5 lineage:** VULKAN-002 + DENSE + NOOP + ROCmFPx Vulkan + old-HC MTP sidecar. The integrated ROCmFPx backend suite remained 140/140 PASS; native NOOP state/rollback passed; short all-on MTP output was coherent and union prefill actually activated.

**Source-level PASS only:** adding Stage-B + flatten to the above stack. The second rehearsal changes only `src/llama-graph.cpp`, `src/models/models.h`, and `src/models/qwen4exp.cpp`; no native build/run of the complete all-feature stack was performed. This is sufficient to remove the structural-incompatibility unknown, but not to claim final runtime/performance acceptance.

**No performance additivity assumption:** every final combined candidate needs its own baseline and measured PP/TG/latency.

### B. Measurement/provenance tooling — preserve in the integration

| Item | Stable r5 state | Integration action |
| --- | --- | --- |
| **TOOL-001** real-prompt `llama-bench` support | **Present / verified** | Carry the harness or run it externally against untouched/new candidate binaries. Preserve real-input fingerprints and tool/CLI comparison capability |
| **TOOL-002** ADLX GPU monitor | **Present / native verified**: `tools/evox2/adlx-gpu-monitor/`; automatic llama-cli/bench logging; 2s sample overhead validation showed no material 64k PP penalty | **必須計測基盤** for performance gates. Preserve `gpu-metrics.csv`, start/exit/sample status and high-load clock/power/temp |
| **TOOL-003** authoritative Evo-X2 P-MODE probes | **Present / verified**: `tools/evox2/pmode/` + `Evox2.Common.psm1` integration | **必須計測基盤**: require Performance start→finish for normal performance claims; ADLX classification is consistency only |
| **Benchmark wrappers/manifests** | `Evox2.Benchmark.psm1`, `Measure-LlamaCli.ps1`, `Measure-LlamaBench.ps1`, `Invoke-BenchmarkMatrix.ps1`, `Monitor-LlamaProcess.ps1`, build-manifest/provenance helpers are in stable r5 | **Preserve newer stable copies**. Never overwrite them with older investigation branches while porting source |
| **DIAG-001** union statistics | Present / opt-in | Preserve if compatible; logging is diagnostic, not the speed patch itself |
| **Collected research plans/analyzers** | Present and indexed in [R5-RESEARCH-ASSET-INVENTORY-2026-10-20.md](R5-RESEARCH-ASSET-INVENTORY-2026-10-20.md) | Preserve selectively; archived configs may require historical BuildKeys and are not automatic final-candidate plans |

Performance attribution requires executable/runtime/model/input identities plus P-MODE start/finish and ADLX evidence. Telemetry failure is fail-open for execution but weakens or invalidates a strong performance claim.

### C. 要確認 — audit latest upstream before porting

| Item | Current evidence | Decision |
| --- | --- | --- |
| **UPSTREAM-FIX-001** HIP/CUDA FA synchronization #30103 | Merged after r5 pin | Verify selected upstream already contains it; no duplicate backport |
| **UPSTREAM-FIX-002** MTP checkpoint/hidden-state restore #30141 | Upstream status/semantics may overlap later Qwen/MTP changes | Re-audit selected SHA; keep diagnostic force-checkpoint code out of production |
| **Current Qwen4Exp/k-pool graph structure** | Has changed materially since r5 pin; the ROCmFPx and Stage-B rehearsals proved semantic ports on pinned r5 only | Re-anchor by function/semantics, especially `graph_mtp::graph_mtp()`; do not first-match similar Target/MTP text |
| **Current Vulkan backend** | Changed since r5 pin; VULKAN-001 and VULKAN-002 both touch overlapping backend areas | Reapply hunks/logic, never whole-file copy from isolated branches |
| **Qwen4Exp deterministic QSA selection** | Same-parent 64k ROCm A/B: `ggml_top_k` = 4 distinct outputs / 4; argsort+cont = 1 identical output / 4. Normal PP cost ~3.16% and TG cost ~5.18%; ROCm ARGSORT verified only through width 16,384 | **要確認 / optional opt-in only**. Keep default OFF for normal inference/performance. If implemented, prefer `QWEN4EXP_QSA_DETERMINISTIC_TOPK=1`; validate longer contexts before claiming >64k support |
| **q8_0 K/V FA path** | Upstream core support exists; VULKAN-002 union evidence is f16-KV-specific | Treat q8_0 as separate config A/B, not part of union performance claim |
| **COMMON-005 compact selected-K/V decode** | Historical r3 deep-decode ROCm benefit, no safe r5 semantic port | Defer from first candidate; separate later deep-context/non-MTP investigation |
| **New s1/Strata/other optimizations** | External evidence only or separate runtime | Exclude from first controlled integration; evaluate after candidate baseline |

### D. 移植しない予定 — first integration excludes these historical/diagnostic sources

- old COMMON-004/COMMON-006 source text already overlapped by later upstream architecture;
- VULKAN-MOE-001 local historical selector where upstream already restored equivalent behavior;
- VULKAN-GR-001 GET_ROWS 128x4 (no useful local gain);
- r2 MTP-QSA prototype;
- Stage-A as a standalone speed patch (Stage-B is the successor);
- Target NextN re-warmup local probe;
- RGP/phase/dispatch-ordinal instrumentation C++ in default inference source;
- Draft KV snapshot and synthetic forced rollback instrumentation C++;
- speculative HIP sparse-QSA experiment;
- unverified s1-derived CONCAT/MoE/shader optimizations.

Keep reports and analyzers; do not merge instrumentation into the production candidate.

### E. Required latest-upstream integration order

1. **Freeze one current upstream SHA at session start.** Build untouched Vulkan + ROCm baselines first. Use stable r5 measurement tooling externally if needed.
2. **Preserve measurement provenance:** ADLX/P-MODE wrappers, manifests, model/input hashes, effective flags. Do not let older branch tooling replace stable copies.
3. **COMMON-001 if still needed**, then **COMMON-003 ROCmFPx core** if still needed.
4. **VULKAN-001A/B** if Agention ROCmFP4 will run on Vulkan; require 140/140 backend gate before model acceptance.
5. Test **native target+MTP**. Add **old-HC** and/or **ratio-zero k-pool guard** only if native selected upstream still needs them.
6. **VULKAN-002** if no equivalent upstream path; prove active prefill, not merely env flag presence.
7. **MTP-DENSE**, then **MTP-NOOP**, each separately gated; repeat one short all-on ROCmFPx/VULKAN-002/DENSE/NOOP smoke.
8. **Stage-B**, then **flatten** behind independent flags. Run short C/A/B first, then bounded 64k/128k correctness/performance.
9. Final Qwen3.8 integrated 32/64 → 128 → one 256k gate when stable; MTP OFF/ON and bounded DraftMax=7 correctness.
10. Separate **Gemma 4 31B + 26B** regression against retained b10919 fallback before replacement.
11. Update [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md) and tag only after exact upstream SHA, final patch matrix, telemetry/provenance and model/backend coverage are documented.

### F. Stop criteria / deferred items

Stop promotion and isolate the feature on build/shader failure, unsupported type/backend fallback, numerical-test failure, repeatable output corruption, MTP state/rollback inconsistency, required path not activating, P-MODE changes, strong ADLX/P-MODE inconsistency, or unexpected ROCm runtime pairing.

Do **not** block the first candidate on the deferred 256k Stage3-vs-Agention telemetry rerun/RGP, COMMON-005, s1 experiments or Strata. Those resume after the integrated candidate is frozen.

**Documents:** [current integration plan](R5-INTEGRATION-PLAN-2026-10-21.md), [ROCm QSA repeatability](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md), [ROCmFPx full port record](R5-ROCMFPX-VULKAN-PORT-PLAN-2026-10-20.md), [NOOP+ROCmFPx runtime rehearsal](R5-NOOP-ROCMFPX-INTEGRATION-CHECK-2026-10-21.md), [Stage-B+flatten source rehearsal](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md), [ADLX/P-MODE validation](R5-ADLX-PMODE-VALIDATION-2026-10-15.md), [asset inventory](R5-RESEARCH-ASSET-INVENTORY-2026-10-20.md), [ROADMAP](ROADMAP.md), [INTEGRATION-POLICY](INTEGRATION-POLICY.md).

---

## Historical checkpoints below — retained from their original dates

The following 2026-10-14/15 lead notices and 2026-10-13 matrix were accurate **at the time** and are intentionally retained for provenance. Their earlier “NEXT” wording should **not** be read as the 2026-10-20 integration decision. See the authoritative register above.

> **MEASUREMENT UPDATE 2026-10-15:** canonical r5 now includes the validated ADLX GPU monitor and read-only P-MODE start/finish probe tooling. This is **measurement infrastructure, not an inference optimization patch**. Performance-mode 64k calibration is ~357 tok/s / ~115W; Balanced ~339 tok/s / ~85W; Quiet ~298 tok/s / ~54W. Normal-user benchmark integration passed end-to-end with authoritative Performance→Performance and ADLX `Performance-like` consistency. [Full report](R5-ADLX-PMODE-VALIDATION-2026-10-15.md).

> **LATEST (2026-10-14): b11618 128K MTP-OFF SAME-BINARY CONTROL PASS; STAGE-B ON VS OFF PP −3.06% (~13.01s), TG NEAR-EQUAL. CROSS-BUILD OFF PP −8.79% VS b11560 UNEXPLAINED:** Previous Stage A did execute (b11608) but still rooted one Draft FA node. New Qwen4Exp-only helper bypasses FA generation entirely, retains K/V projection/normalization/rope/cache write roots, and repairs SET_ROWS diagnostic input position (src[1], not src[2]). Vulkan b11618 real Draft graph A 133 nodes/FA1 vs B 31 nodes/FA0, B retains 1 K and 1 V SET_ROWS, short generated text and MTP 17/27 match, both exit0. A classifier still labels K/V 0/0 despite two SET_ROWS. 64k ABBA on same b11618 with diagnostics OFF: A1/B1/B2/A2 PP 314.41/325.50/325.57/313.86, TG 27.80/28.74/29.02/28.62 tok/s; mean PP +3.63%, TG +2.38%, 7.31s total saved. All generated bytes and Draft 295/430 match. Improvement rises to 4.57% PP segment savings at KV 49–61k. This is a two-repetition session, not a broad statistical guarantee. Actual GPU dispatch and KV numerical parity unverified; stable inference source unchanged. 128k A/B input126253: crop OFF 278.06/23.47 vs ON 296.63/23.79 PP/TG (+6.68%/+1.36%), 28.72s total saved, identical generated bytes and Draft 295/429. Per-bin PP gain rises to 9.30% at 115–125k. Historical b11560 MTP OFF PP335.46/TG24.14 and old ON PP303.97/TG23.48 are NOT source-identical: new ON remains below old OFF and even slightly below old ON. Same-binary 128k MTP-OFF control now measured: PP 305.98, TG 23.74, native total 434.15s; Stage B ON PP296.63, TG23.79, total447.10s. Old b11560 MTP OFF PP335.455 implies -8.79% apparent cross-build shift. Source-diff 58 intervening commits are mostly opt-in RGP/phase diagnostics plus Draft-only feature; possible Vulkan wrapper/codegen or thermal/power effects, no proven cause. Next: archived b11560 OFF rerun now for runtime vs environment isolation; then optional RGP/KV numerical parity. [Stage-B details and native stop gates](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#stage-b-implementation-dense-draft-kv-only-no-fa-graph-root--2026-10-14).

> **2026-10-14 Stage-A: SHORT + 64K FUNCTIONAL PASS; ACTIVE GRAPH INSPECTED, FA REMAINS:** Opt-in Draft dense MTP prefill graph-root crop is implemented on [`investigation/r5-mtp-pp-kv-crop-stage1-20261014`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-kv-crop-stage1-20261014), **not** stable r5. It retains explicit Q/K/V and cache-copy graph nodes, stops before FA-output HC/FFN/NextN/logits roots for `n_outputs=0` only and guards unallocated Hybrid attention masks. Enabled only with `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`, single sequence, one-layer Qwen4Exp, dense ratio0, masked NextN; other cases use the existing graph. [Report and test gates](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md). **2026-10-14 ACTIVE GRAPH DIAGNOSTIC COMPLETED (Vulkan b11608):** On the same Stage-A experimental branch, `LLAMA_MTP_KV_CROP_DIAG=1` inspects the actual outputless Qwen4Exp MTP catch-up graph (not reserve graph), caps logging at 8 batches, reports FA/MoE/MM and K/V `SET_ROWS` nodes, plus active graph output presence and reuse. A separate `stage1-diag-short` job and BuildKey isolate the diagnosis from PP benchmarking. [Instructions](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#stage-a-active-catch-up-graph-diagnostic--2026-10-14). **b11608 built and tested: OFF 133 graph nodes / ON 44, crop_applied=1, MoE and named FFN operators removed, but FA=1 both cases because `build_attn_mha()` explicitly roots attention. K/V name-based classifier returns zero even though two SET_ROWS nodes remain: do not mistake these for missing KV. Samples with 3 tokens show optimization also occurs during TG. Next: dedicated K/V-only Draft path avoiding `build_attn_mha()`, then repeat graph and speed verification.**

**Built b11597 from source 301564c2a. Vulkan short and 64k ABBA functionality PASSED (4/4 64k runs exit0, output bytes and MTP acceptance identical). 64k B vs A PP +0.53% / ~1.04s, too small to attribute without confirming the crop actually executes; TG is also touched by the crop (confirmed n_tokens=3 zero-output Draft catch-ups); prior warming-only interpretation was incomplete. Draft KV bitwise parity, active GPU FA/FFN pruning and PP benefit remain UNVERIFIED. [64k report](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#native-vulkan-64k-abba--2026-10-14-15091527-jst). Next milestone: avoid explicit FA graph root and confirm KV writes before new 64k/128k benchmarks.** Previous [RGP evidence](R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md) is baseline diagnosis, not evidence this patch works. Latest upstream/Unsloth change review is in [source audit](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md#pre-implementation-upstream-and-unsloth-update-review--2026-10-14). DENSE/NOOP TG branches and stable r5 inference source remain untouched.


## Historical cross-branch patch and candidate register — 2026-10-13 (superseded by 2026-10-20 table)

**Research policy:** [INTEGRATION-POLICY.md](INTEGRATION-POLICY.md). **Integrated snapshots:** [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md) — **none created yet; first checkpoint planned**. The research objective is understanding and testing performance mechanisms, not continuously shipping the newest upstream. r5 remains pinned at `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Neither this registry nor the new policy changes a runtime binary, source pin or experimental code.

**How to read the tables:** “ported” means native code is in that series, **not** that a particular runtime flag was enabled. “verified” is scoped to the cited backend/model/context. “upstream-covered” means the relevant functionality was audited in the indicated pinned upstream; it does not assert byte-identical source or speed parity. “not ported” is a deliberate absence, not a regression verdict. Each row's r3/r4/r5 status is **independent**; historical wins do not automatically transfer to r5. The **r5 column describes only pinned `r5/upstream-refresh-20261009` source** and does *not* include experimental branches.

### r5 experimental branches — historical checkpoint 2026-10-13

| Patch | r5 stable | Experimental branch / source | Verification and integration status |
| --- | --- | --- | --- |
| **MTP ratio-zero compatibility** (subset of COMMON-002) | **Not added to stable**; upstream-native MTP only | [`investigation/r5-mtp-dense-indexer-20261011`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-dense-indexer-20261011); carried into NOOP descendant | Unsloth self-contained MTP Q8_0 sidecar works on candidate; positive-ratio Agention FP4 sidecar is **unverified**. [Compatibility record](R5-COMMON002-DENSE-MTP-COMPAT-2026-10-11.md) |
| **MTP-DENSE-001** | **Not ported** | [`investigation/r5-mtp-dense-indexer-20261011`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-dense-indexer-20261011) frozen `0dc8672d` | Implemented/validated for tested Unsloth MTP ratio0; 64/128/256k **24/24** normal Vulkan+ROCm ABBA OK. Vulkan TG **+6.81/+15.52/+36.22%** with matched outputs; ROCm **+7.72/+17.42/+23.48% observed**, varying outputs even within same setting. [Report](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md). **NOT MERGED** |
| **MTP-NOOP-001** | **Not ported** | [`investigation/r5-mtp-noop-20261012`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-noop-20261012), from DENSE-only. Compiled source **Vulkan `b84d18870`**, **ROCm `f62ca1cd4`** (later docs HEAD is *not* the tested compiled source). | Native/short gates PASS. Vulkan 64/128/256k **12/12 OK**, text+acceptance identical per depth, TG **+2.10/+6.73/+14.40%**. ROCm **12/12 OK**, TG **+4.55/+6.42/+8.08% observed**, but text+acceptance vary including same-setting repeats, so not exact equivalence/fully isolated causal gain. [Vulkan](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md) / [ROCm](R5-MTP-NOOP-ROCM-VALIDATION-2026-10-12.md) / [implementation](R5-MTP-NOOP-IMPLEMENTATION-2026-10-12.md). Default OFF, **NOT MERGED** |
| **MTP ON PP overhead / DIAG-003** | **No PP fix; trace source not in stable** | [`investigation/r5-mtp-pp-trace-20261013`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-trace-20261013) **compiled `4b136c5bf`/b11569** from compatibility-only `f8d24494f`, not DENSE/NOOP | **Vulkan source/build/short +64k diagnostic gate PASS 2026-10-13**: 5 Python unit tests, 4/4 native runs OK, runtime verified. 64k 61,789 tokens: OFF PP171.122s, ON181.309s (**+10.187s**, traced single pair); ON prompt stage target wall94.147s, NextN hidden getter78.439s (**includes target GPU wait**), draft llama_process6.756s, verify-copy1.923s. 31 prompt batches exactly accounted. Draft CPU-wall rises with KV, **not proven FA kernel GPU time**; trace-only results not untraced ABBA. **64k repeat OFF/ON 2/2 PASS** on identical b11569: OFF 171.731s, ON 186.210s (+14.478s; first traced pair +10.187s). OFF/ON outputs respectively identical across sessions; ON acceptance again 295/430. Previous ON sustained disk/page reads disappeared (median 14.84→0.00 MiB/s disk, 525→0 page reads/s) while ON PP slowed, so paging is not a proven PP cause. Repeat phase shifts concentrated in target GPU wait, not draft CPU-call. **128k Vulkan diag PASS 2/2** (126,253 tokens, identical b11569 executable; clean checkout later at `2578e4672b` only adds config): PP OFF 382.966s / ON 420.908s (**+37.942s**), ON 295/429 accepted, 62 prompt batches and 4/8 total bins cross-validated. ON target wall220.603s, synchronizing NextN getter178.296s (**includes queued target GPU**), draft `llama_process` CPU20.023s, verify hidden1.914s. CPU-wall envelope target+hidden difference **+15.975s** vs OFF; not proof of target GPU NextN compute overhead. Draft CPU wall scales with KV; first/second/third depth-bin penalty +8.612/+8.217/+21.091s. ON GPU Local max88.674GiB vs OFF83.370GiB; ongoing system-wide paging/disk-read medians zero in both. **Vulkan source audit COMPLETE**: unmasked NextN ON disables early final-layer output crop, forcing per-token final HC/MoE/FFN; ratio-zero draft uses dense Flash Attention (not QSA union); all-row NextN readback uses pinned/async when available, synchronous staging fallback possible and unverified. **64k RGP ON/OFF at KV~51–53k COMPLETE**: same b11569, 63 pipeline configurations, 512-dispatch samples; identical 13 highest-rank shader hashes; their summed GPU durations ON **300.462ms** vs OFF **300.473ms**, while full native PP is ON183.405s vs OFF169.664s (+13.741s). The short sample primarily covers common target computation, NOT proof of zero draft/final-layer GPU cost. **EXPERIMENTAL RGP MARKERS b11577 GPU EVENT VISIBILITY PASSED (2026-10-14; draft GPU time still pending)** on `investigation/r5-mtp-pp-trace-20261013`: `GGML_VK_MTP_PP_RGP_MARKERS=1` opt-in adds graph role hints, explicit shader/KV/query labels for QSA union and dense FA, and MoE/matmul stage labels, adapted from prior verified llama-bench RGP work. Dedicated build-key/short+64k plan and 5 static source-contract tests; **Windows Vulkan Clang build b11577 and MTP ON 163+32-token smoke PASS** (new binary SHA256 `6d141c6b2e627e89c380922573f1b62a08ea48fbdb362f9e0ce31860a73ebe34`, runtime Verified, exit0, acceptance17/27, trace target/draft row sums match); marker enable log confirms `VK_EXT_debug_utils`. **Native 64k ON RGP-visible labels PASS**: start512/count256 screenshot shows `EVOX2_MTP_MATMUL role=target` around `ffn_shexp-4`, `hc_gate-5`, etc.; early capture coincides with model setup (~40s after start), **not high-KV prompt and not yet `role=draft`/FA verified**. [Experimental implementation+gates](R5-MTP-PP-RGP-MARKERS-IMPLEMENTATION-2026-10-14.md). **b11577 MTP ON 64k RGP Dispatch range 50000/count256 PASS:** uploaded RGP+native ZIP confirms ordinary PP **KV~12–14k** inferred from 01:45:26.667 filename / native elapsed+73.552s, and real nested target MoE (`ffn_moe_{gate,up,down}-19`) plus `EVOX2_MTP_MAIN role=target shader=flash_attn_f32_f16_aligned_cm1 (64,24,1)` in RGP. This is target **dense** FA before QSA union min KV32768, **not draft proof**. PP 189.572s/325.94tps, old MTP Q8_0 acceptance 295/430; marker timing non-baseline. **RGP start180000/count256 also completed** on same b11577 MTP ON: 64k PP 202.734s (304.78tps), screenshot shows target QSA `indexer_k_raw-43`, capture filename at +181.721s lies in 40,960–43,008 input tokens (after QSA threshold). User explicitly searched `role=draft` and `role=unknown`: **neither occurs in the two narrow captured PP slices**; existing `mtp_pp_trace_v1` still records all 31 draft prompt batches (the late-bin draft CPU-call wall totals ~4.001s). **DO NOT conclude no draft GPU work**. **Dispatch ordinal diagnostic b11587 built and native short ON PASSED (2026-10-14)** on experiment branch; `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1` counts Vulkan dispatch calls and logs graph `[begin,end)` + role hint to target the draft interval deterministically. [Implementation / validation gates](R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md). Short smoke runtime Verified / exit0, MTP 17/27 accepted, **16 target + 44 draft graph records**, no unknown, 60 contiguous half-open dispatch ranges [0,64653), including real prompt target [0,3767) and draft [3767,3846). **64k b11587 RGP ordinal calibration COMPLETE (2026-10-14 09:47):** 986 contiguous graph records (278 target/708 draft), no unknown; PP interval [3846,268204), 61 Target graphs /260330 vkCmdDispatch and 61 Draft graphs /4028 dispatch (1.524% of PP dispatch COUNT, not GPU TIME), 31 prompt batches. At **51,200** input tokens Target [208279,217403) → **Draft [217403,217535)** (two 66-dispatch graphs) → Target [217535,226659). Previous start180000/count256 landed within Target [175817,180379), ending before Draft [180379,180511): explains absent draft labels. **DRAFT GPU EVENT CAPTURE PASSED (2026-10-14 10:59):** b11587 MTP ON, RGP Dispatch range start217300/count512 contains genuine `EVOX2_MTP_GRAPH role=draft` regions and `EVOX2_MTP_MAIN role=draft shader=flash_attn_f32_f16_aligned_cm1` (dense FA). One visible RGP Draft graph inclusive interval **232.580ms**; nested `mtp_eh_proj-48` matmul region **57.138ms**, native `matmul_q8_0_q8_1` GPU dispatch **56.497ms** (nested, not additive). This strongly validates targeting/labels and shows **draft projection work besides FA**; **FA GPU latency and exact KV now confirmed by next screenshot**: two 1,024-query Draft microbatches at `KV=50176`/`51200` using `flash_attn_f32_f16_aligned_cm1` (`Br16/Bc64`) cost **139.918/139.159ms for FA main** and **1.094/1.159ms for mask opt**; FA main combined **279.077ms** over the two microbatches. First graph's earlier unfiltered 232.580ms and nested projection57.138ms imply approximate FA~60.6%, projection~24.6% *if same graph*, **not proven exclusive attribution**. New screenshot demonstrates an expensive Draft dense FA, NOT proof all ON PP overhead is Draft FA; 128k Target+NextN extra envelope remains a separate candidate. **SOURCE REVIEW COMPLETE (2026-10-14):** [Vulkan optimization candidates](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md) ranks P0 Qwen4Exp single-block Draft KV-only prefill (prompt `process()` consumes Target hidden rather than Draft outputs; K/V copy nodes are explicit), P1 Target unmasked NextN final HC/MoE/host path, P1 opt-in CM1 FA tuning, P2 draft eh_proj matmul/ubatch. These are **HYPOTHESES, NO IMPLEMENTATION**; graph/scheduler/cache correctness and separate regular MTP drafting must be protected. Mask optimization ~1ms compared with FA~140ms so low priority; qsa-ratio override NO PORT. **NEXT: bounded ROCm mechanism comparison, then isolated correctness-first draft KV-only prototype only if justified.** Retain existing b11587 source/build. Do not use GGML_VK_PERF_LOGGER for speed controls (forces sync). [Source/RGP plan](R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md). [64k evidence](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md) / [128k evidence](R5-MTP-PP-TRACE-VULKAN-128K-2026-10-13.md), [implementation](R5-MTP-PP-TRACE-IMPLEMENTATION-2026-10-13.md), [plan/r2 no-port](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md). |

**Reading rule:** a source patch in an investigation branch does *not* become a stable feature just because its report is copied to the stable documentation directory. The main matrix below retains its stable-only meanings; individual older dated checkpoints below are historical. Exact runtime binary SHA/artifact digest and raw ZIP identifiers are in the linked reports. See [README](README.md) for the docs synchronization policy.

**2026-10-13 external-review triage (no source port):** A pre-update DeepSeek review suggested (1) draft catch-up time **by KV depth**, (2) check **draft-specific f16 FA versus fallback**, (3) possible **draft KV-only prefill/query pruning**, and (4) optional hidden-state handoff and memory-budget checks. Adopt **(1) and (2) as measurement gates**, with (4) conditional on traced costs; retain (3) as a *correctness-gated hypothesis only*, **not an implemented feature or guaranteed O(N) optimization**. r4 3-point quadratic fits are descriptive and do **not** demonstrate that draft FA explains 82%/68% of PP time. Existing r4 diagnostic plan and script are carried over but the r4 source helper `ggml-mtp-diag.h` is absent from r5; `LLAMA_MTP_DIAG=wall` will not produce sidecars by itself. Original r5 b11560 Vulkan/ROCm ABBA and r2 MTP-QSA **NO-PORT** decision unchanged. [Full review disposition](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md#independent-deepseek-review-triage--2026-10-13-incorporated-with-qualifications). No stable inference source changed.

### Downstream feature/optimization matrix

| ID / feature | r3 | r4 | r5 | Best established local evidence / next gate |
| --- | --- | --- | --- | --- |
| **COMMON-001** — split PLE16 loading | Ported / verified | Ported / verified | **Ported / verified** | Mandatory on every new base before established PLE16 comparison; r5 Original + PLE16 Vulkan/ROCm 64k gates [passed](R5-COMMON001-VALIDATION-2026-10-09.md) |
| **COMMON-002** — MTP compatibility *umbrella* | Evaluate/native MTP | Native MTP + minimal dense draft guard | Native upstream MTP; local guard **not ported** | [Recovered r2 64k/128k MTP ON/OFF logs](R2-MTP-LOG-RECOVERY-2026-10-11.md) verify r2 MTP works with Unsloth self-contained Q8_0 and PP/TG trade-off; r5 not yet smoke-tested, likely ratio-zero draft input issue. r4 minimal guard candidate first, before performance ports |
| **MTP-DENSE-001** — omit dead dense-draft indexer | Not ported | Ported / Vulkan verified | **Not ported (stable only)** | r4 Vulkan 256k MTP ON TG **15.220→20.185 (+32.62%)**, matched response/acceptance ([report](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md)); not a total-latency win against MTP OFF |
| **MTP-NOOP-001** — suppress target QSA no-op invalidation | Not ported | Ported / Vulkan verified; ROCm long output gate open | **Not ported (stable only)** | r4 Vulkan 256k TG **20.205→22.830 (+12.99%)** with dense omission already ON ([report](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md)); ROCm 256k attribution/equivalence not established |
| **COMMON-003** — ROCmFPx loader/core | Not ported | Not ported | Not ported | **Planned for first integrated snapshot preparation**: AgentionAI ROCmFP4-FAST GGUF loader/core + HIP correctness and model inference; not yet implemented or validated, no r5 speed claim |
| **COMMON-004** — incremental pooled-key cache | Ported / verified | Upstream functionally covered; old patch not ported | Upstream functionally covered; old patch not ported | Major pooled-key path revised via [#29751](https://github.com/ggml-org/llama.cpp/pull/29751), graph stability via [#29958](https://github.com/ggml-org/llama.cpp/pull/29958). Avoid treating this as source-identical port |
| **COMMON-005** — compact selected-K/V decode | **Ported / ROCm verified** | Not ported | **Not ported; adaptation required; deferred** | r3 ROCm 256k TG **11.68→17.37 (+48.7%)** ([ABBA/RGP](COMMON005-ROCM-VALIDATION-2026-10-02.md)). [r5 source review](R5-COMMON005-PORT-FEASIBILITY-2026-10-11.md): same gather *principle*, but `top_k` replaced with additive `sel` + `selected_rows` including dump ids; old text cannot be cherry-picked safely. Not a normal MTP-verification optimization; defer until non-MTP deep decode/integration. |
| **COMMON-006** — block-domain QSA select | Proposed; not ported | Upstream-covered | Upstream-covered | Direction implemented in [#29751](https://github.com/ggml-org/llama.cpp/pull/29751); retain semantic checks, not a standing port |
| **VULKAN-001** — ROCmFPx Vulkan kernels | Not ported | Not ported | Not ported | **Conditional** on target model/Vulkan path during first integration; separate compatibility and backend decision from COMMON-003 |
| **VULKAN-002** — grouped-union prefill QSA | Not ported (r2 donor existed) | **Ported / verified** | **Ported / verified, opt-in** | r5 PLE16 64k **+25.61%**, 128k **+71.27%**, 256k **+105.54% PP** with f16 K/V; native Vulkan FA OFF/ON 18/18, real runs 12/12 ([report](R5-VULKAN002-VALIDATION-2026-10-09.md)); model-level quality/default ON not certified |
| **VULKAN-MOE-001** — legacy per-expert tile selection | Not ported | Ported / verified | **Upstream-covered; no port** | r4 64k PP **+8.25%**; [#29936](https://github.com/ggml-org/llama.cpp/pull/29936), merged **2026-10-05**, restored selector semantics on r5 ([audit](R5-MOE-TILE-UPSTREAM-REVERT-2026-10-09.md)) |
| **VULKAN-GR-001** — GET_ROWS 128x4 experiment | Not ported | Ported experiment / **no useful measured gain** | Not ported | r4 [profile](R4-GET-ROWS-128X4-AB-2026-10-03.md); do not carry by default |
| **MTP-QSA prototype** | r2 experimental `test/mtp-qsa-prototype` | Not part of r4 normal stack | **Not ported; keep verdict** | **No measured PP gain:** r2 full-QSA 64k 259.23→259.12; prefill-only 64k 255.73→252.97, 128k 209.44→207.93 tok/s (single pairs). Old memo suggests FA-only gain was offset by indexer/top-k/gather/CONT and higher memory, but per-op times are not independently verified from archived logs. r5 already supports native MTP QSA **when per-layer ratio>0**; current Unsloth sidecar ratio=0 takes dense attention. Do not copy r2's reference-ratio override; reopen only after r5 draft-attention attribution and correctness/acceptance gates. [Decision](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md) / [r2 evidence](R2-MTP-LOG-RECOVERY-2026-10-11.md) |

**Historical r3 names:** COMMON-002 is an umbrella, not a single always-portable patch. `MTP-DENSE-001`, `MTP-NOOP-001`, `VULKAN-MOE-001` and `VULKAN-GR-001` are new **registry aliases**, not claims that earlier commits used those identifiers. Exact source commits, controls and test conditions remain in linked dated records.

### Planned first integration and later non-patch experiments

- **First integration preparation:** target **COMMON-003 ROCmFP4-FAST support** (initial target AgentionAI ROCmFP4 model) with format/core/HIP build+load+correctness gates; no source change or working model claim yet. Evaluate **VULKAN-001** only if the selected Vulkan model requires it. Compare verified speed patches against newer chosen upstream; never substitute this future integration for current r5 research.
- **After an accepted integrated tag:** try **Strata** as a distinct runtime on Evo-X2 (planned, not started). It is not a downstream patch and will not be bundled into the llama.cpp integrated snapshot.
- **Separate accuracy study (later):** reuse Qwen3.5 long-context prompt/question fixtures as the test set to compare **Qwen3.8-Flash-Next** quantizations; distinguish the model under test from the corpus origin, fix scoring/engine/decoding factors, and record correctness independently of PP/TG. No measurements yet.

See [ROADMAP.md](ROADMAP.md) and [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md).

### Candidates and upstream watch (no local speed claim unless stated)

| ID / type | Candidate and upstream relationship | State at r5 pin / re-evaluation gate |
| --- | --- | --- |
| **UPSTREAM-FIX-001** (correctness) | [#30103](https://github.com/ggml-org/llama.cpp/pull/30103): HIP/CUDA FA tile synchronization for `nbatch_combine != DKQ/2` | Merged **2026-10-10**, **after** r5 pinned upstream; **not cherry-picked or tested on r5**. Source review [2026-10-11](R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md) found **256-dimension RDNA ncols32/64 have np>1**, so existing r5 sync already runs in those configs despite nbatch_combine mismatch; other configs and actual dispatch still need review. No local race reproduction established |
| **ROCM-001** (research/possible patch) | **HIP sparse QSA prefill**: enable/adapt compact sparse FA, grouped gather, or safe interior-mask tile skipping | **Proposed, no implementation.** HIP path in pinned code excludes NVIDIA sparse compact. [64k RGP](R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md) captured WMMA/scan and ~105–111 ms sampled FA, but **not** matched HIP KV or per-op aggregate time. Only consider prototype after a specific performance/correctness gate, not by automatically lifting HIP guards |
| **ROCM-PP-001** (diagnostic) | HIP FA specialization / `scan_mask` suffix cutoff / Stream-K / 64k→256k operator-time scaling | **Source + HIP RGP 64k sampled calls captured** [2026-10-11](R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md): AMD WMMA `flash_attn_ext_f16<256,256,16,4>`, literature/code **104.911/111.198 ms**, mask suffix scan present, occupancy **4/16**; no fixup/combine found in captured window. **Exact KV / total FA operator contribution not measured**; bounded gate may close without sparse port |
| **VULKAN-KV-001** (configuration A/B) | [#29639](https://github.com/ggml-org/llama.cpp/pull/29639): quantized K/V sparse Flash Attention | Merged and in r5 pinned source, **not validated in this project's q8_0 KV A/B**. VULKAN-002 grouped-union supports **f16 K/V only**; with q8_0 it falls back. Compare f16 union OFF/ON and q8_0 as **different paths**, not “q8_0 + union acceleration” |
| **UPSTREAM-PERF-001** | [#29353](https://github.com/ggml-org/llama.cpp/pull/29353) CUDA/HIP chunked GDN | Open at 2026-10-11 watch snapshot; model/`ub1024` shape and ROCm operator share first |
| **UPSTREAM-PERF-002** | [#28303](https://github.com/ggml-org/llama.cpp/pull/28303) ROCm tiled transposed CONCAT | Open at 2026-10-11 snapshot; strong gfx1151 relevance but Flash-Next tensor shape/time unverified |
| **UPSTREAM-PERF-003** | [#30139](https://github.com/ggml-org/llama.cpp/pull/30139) recurrent-state view/identity GET_ROWS removal | Open at 2026-10-11 snapshot; candidate decode improvement, not local verified |
| **UPSTREAM-PERF-004** | [#30149](https://github.com/ggml-org/llama.cpp/pull/30149) Vulkan tiled transposed CONCAT | Draft at 2026-10-11 snapshot; inspect graph shape and published PR status before trial |
| **UPSTREAM-PERF-005** | [#30191](https://github.com/ggml-org/llama.cpp/pull/30191) Vulkan deep-KV FA query-row slicing | Draft at 2026-10-11 snapshot; narrow eligibility, do not assume it affects union ON |
| **UPSTREAM-PERF-006** | [#30190](https://github.com/ggml-org/llama.cpp/pull/30190) MTP verification-token/GQA path | Draft at 2026-10-11 snapshot; only after actual Flash-Next target/draft eligibility and r5 MTP correctness |
| **UPSTREAM-FIX-002** | [#30141](https://github.com/ggml-org/llama.cpp/pull/30141) MTP hidden-state checkpoint restore | Open at 2026-10-11 snapshot; correctness watch if cache/checkpoints become an experimental focus |
| **TOOL-001** (measurement) | `llama-bench` real prompt input / prompt slicing | r4 investigation, **selectively ported to r5**; r5 smoke plus 64k/128k corpus studies verified ([r5 record](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md)) |
| **TOOL-002** (measurement) | ADLX GPU telemetry + Evo-X2 P-MODE boundary probe | **Integrated into canonical r5 2026-10-15**. ADLX 2s logging overhead ABBA was +0.318% (inside ±0.5% negligible band). P-MODE method2 read is authoritative; wrappers record start/finish and warn on non-Performance/change or confident ADLX power mismatch. End-to-end 64k validation passed with Performance→Performance, 115.047W Performance-like, warnings0 ([report](R5-ADLX-PMODE-VALIDATION-2026-10-15.md)) |
| **DIAG-001** (measurement) | Vulkan QSA union statistics | r4 investigation, **selectively ported to r5**; r5 opt-in CSV / STATS=0 smoke verified ([r5 report](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md)); not a default inferencing feature |
| **DIAG-002** (investigation) | Vulkan union-OFF FA dispatch labels and mask-tile histogram | Instrumentation lives only on `investigation/r5-vulkan-off-fa-dispatch-20261010`; report [archived on r5](R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md), **not merged** into stable r5 |

The public upstream status labels above are a **dated snapshot**, not claims of continuously refreshed PR state. Also watch graph/k-pool issue [#30005](https://github.com/ggml-org/llama.cpp/issues/30005), speculative MMVQ changes [#25666](https://github.com/ggml-org/llama.cpp/pull/25666) / [#29679](https://github.com/ggml-org/llama.cpp/pull/29679) and external engines per [research log](PERFORMANCE-RESEARCH-LOG.md), but do not make them mandatory refresh tasks.

### Upstream replacement / porting chronology

| When / series | Observation | Local patch disposition and evidence |
| --- | --- | --- |
| r3 baseline (b11247) | COMMON-004 pooled-key and COMMON-005 compact selected-KV decode locally implemented | COMMON-005's ROCm long-context benefit **measured on r3 only**; [record](COMMON005-VALIDATION-2026-10-02.md) |
| r4 refresh (2026-10-02) | [#29751](https://github.com/ggml-org/llama.cpp/pull/29751) changed QSA pool-domain selection/caching | COMMON-004 and COMMON-006 **not automatically re-ported**; review by behavioral overlap ([COMMON-006 notes](#common-006---block-domain-qsa-selection-upstream-evaluation)) |
| r4 experiments (2026-10-03–05) | Local MoE tile selection and Vulkan grouped-union independently accelerated PP; MTP-DENSE / MTP-NOOP TG improved on their tested paths | r4 exact measurements preserved below and in dated reports; not a blanket commitment to future ports |
| r5 upstream pin (2026-10-09, SHA `de7fa0a3`) | [#29936](https://github.com/ggml-org/llama.cpp/pull/29936) MoE tile revert (merged 2026-10-05) reproduces r4 legacy selector behavior; [#29958](https://github.com/ggml-org/llama.cpp/pull/29958) k-pool graph-stability work present | VULKAN-MOE-001 **retired from r5 port list** after source audit; older r4 measurements preserved. COMMON-005 still not ported, VULKAN-002 ported and measured |
| Upstream after r5 pin (2026-10-10) | [#30103](https://github.com/ggml-org/llama.cpp/pull/30103) HIP/CUDA FA race fix merged | Registry **backport candidate**, not present in r5; evaluate actual dispatch/need before cherry-pick |

### Registry maintenance on each experiment or integration checkpoint

For each patch/candidate, record **(a)** source category and exact upstream/local commit or PR, **(b)** explicit branch source-presence and effective runtime control, **(c)** correctness gate scope, **(d)** performance table with backend/context/KV/model/source SHA and linked raw evidence, **(e)** dependencies and known incompatibilities, **(f)** first upstream overlap/merge date and first series where tested, **(g)** planned integration decision: eligible / inapplicable / replaced / blocked / insufficient evidence. Do not use a single global “validated” flag across versions. Append a new dated checkpoint rather than mutating the meaning of old data.

**Recovered pre-r3 r2 MTP evidence:** [R2-MTP-LOG-RECOVERY-2026-10-11.md](R2-MTP-LOG-RECOVERY-2026-10-11.md) (Vulkan MTP ON/OFF, QSA prototype failure/gates and synthetic rollback; source/metrics strictly historical). **Older sections below are chronological r3/r4/r5 evidence and can contain historical TODO/PENDING text.** The table in this 2026-10-13 historical section is a dated snapshot only; the authoritative 2026-10-20 dispositions are at the top of this file. [ROADMAP.md](ROADMAP.md) governs the next research checkpoint.

## Preserved r4 status (2026-10-09)

The full source/validation checkpoint and investigation-branch references are in
[R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md).

| Item | Current status |
|---|---|
| MoE legacy tile selection | Implemented and measured; opt-in, default OFF. |
| COMMON-001 | Split PLE16 support implemented; Vulkan/ROCm validation through 256k. |
| VULKAN-002 | Grouped-union implemented; Vulkan PP/TG validation through 256k; default OFF. |
| COMMON-002 | Historical compatibility port not applied wholesale. Uses upstream-native MTP plus the minimal dense-sidecar pool-input guard; includes diagnostics and the two TG candidates below. |
| Dense MTP indexer omission | Implemented, default OFF; Vulkan 256k normal ABBA validated. |
| Target no-op QSA invalidation suppression | Implemented, default OFF; Vulkan 256k normal ABBA validated with indexer omission enabled. |
| MTP PP overhead / ROCm PP scaling | Unresolved. ROCm long-context MTP equivalence and focused confirmation gates remain open. |
| COMMON-003 / VULKAN-001 | ROCmFPx support not implemented in r4. |
| COMMON-004 / COMMON-005 / COMMON-006 | No automatic historical port; old ROCm selected-KV decode remains deferred; COMMON-006 is an upstream-validation gate. |
| Real-prompt bench / union statistics | Implemented on separate investigation branches, not integrated into r4; statistics-OFF performance validation remains pending. |

Next work moves to a clean, separately pinned **r5 upstream-refresh validation**.
Reclassify and selectively re-port only still-needed deltas after measuring the
new baseline. See [ROADMAP.md](ROADMAP.md) for the current priority order.

## Historical r4 implementation progression (2026-10-03 to 2026-10-05)

The narrative below preserves the original progression. Statements about the
next candidate or investigation reflect those dates; use the checkpoint above
for the current state.

The r4 base is pinned at `bed0a856606ee4a24a164066f73d2379447033f5` on
`r4/upstream-refresh-20261002`. A diagnostic Vulkan MoE tile-selection switch is
now prepared; its default preserves the upstream selection. COMMON-001 split-PLE16
compatibility is validated through 256k; the historical COMMON-004/005 optimization
ports remain deferred. Windows profile A/B and both 939/939 MUL_MAT_ID
test runs pass. Legacy selection reduces PP MoE GPU time by 25.22% and total
PP GPU time by 8.82%. Normal 64k ABBA also passes: PP mean 248.475 -> 268.985
tok/s (+8.25%, 18.959 s less prompt time). TG mean is 25.195 -> 24.565 (-2.50%);
two short generations per mode do not establish TG equivalence or regression.
The scoped PP diagnosis is complete; keep the opt-in switch. Tensor-level
GET_ROWS diagnostics passed on Windows: steady GPU 40.671 ms/token, including
2.487 ms GET_ROWS across 124 calls. Cached pooled-key gathering contributes
1.662 ms (66.82% of GET_ROWS); incremental raw-key gathering is only 0.030 ms.
This isolates a residual cache-read cost, not missing incremental caching.
The pre-port reference is preserved. COMMON-001 was committed at `a60a57879...`
and the subsequent small GET_ROWS 128x4 candidate at `109e238b...` was profiled
on Windows. Steady cached gather is 1.658893 -> 1.671003 ms/token and GPU total
40.688344 -> 40.716906 ms/token (OFF -> ON), with both runs OK. No useful gain
was observed: keep default OFF, skip normal ABBA and long-context expansion for
this candidate, and advance to VULKAN-002. Dedicated value-test logs were not
included in that profile archive; no numerical pass is asserted.
See [R4-GET-ROWS-128X4-AB-2026-10-03.md](R4-GET-ROWS-128X4-AB-2026-10-03.md).
See [R4-GET-ROWS-PROFILE-2026-10-03.md](R4-GET-ROWS-PROFILE-2026-10-03.md).
See [R4-MOE-TILE-AB-2026-10-03.md](R4-MOE-TILE-AB-2026-10-03.md).
Clean 64k/128k/256k runs now pass on both backends.
COMMON-006 remains an upstream-validation gate. The registry and measurements below
are the historical r3 checkpoint frozen at
`0a93fcbb8e5bcf51b331275c4f4b142d822168d6`, not r4 validation.

VULKAN-002 `5814fbe99...` now passes the Windows build, 18/18 GPU OFF/ON tests,
64k profile/normal ABBA and PLE16 128k/256k ABBA. Normal PP gains reach +65.2% /
+100.6%, with TG effectively unchanged. Keep the default OFF; validated target
runs explicitly enable union. COMMON-002 dense MTP now completes all 28 overnight
Vulkan/ROCm runs through 256k. Investigate its long-context TG regression first,
then MTP PP overhead and ROCm PP scaling; COMMON-005's historical decode port
remains deferred. See
[R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md)
for implemented opt-in diagnostics and build identity checks; the rebuilt Vulkan
allocation/short diagnostic gate now passes.
The wall collection now completes all three inference runs and identifies a
15.015 s CPU layout cost at 256k MTP ON. The user has recovered all three reports
with the script-only startup-capability-probe classification fix; no GPU rerun.
Source review confirms that the ratio-zero MTP graph omits pool inputs while
memory still maintains an indexer. A default-off dense-draft indexer omission
is now implemented, default OFF. The 14:50 Windows Vulkan native gate is
Complete after test position/partition corrections: policy, cache/state/
rollback and all eight A/B output pairs pass. Allocation/short real CLI now
passes 8/8 runs; MTP ON output/acceptance match and draft indexer work disappears
only in B. The 256k wall pair also passes: TG 14.76 -> 19.95 (+35.16%),
generation time -9.00755 s, matching response bytes/acceptance, no draft layout
in B and 5.499980 s target layout remaining. PP is effectively unchanged.
Normal 256k ABBA also passes 4/4: TG mean 15.220 -> 20.185 (+32.62%),
identical response/acceptance and effectively unchanged PP. Versus the earlier
normal MTP OFF reference TG19.76, the advantage is only +2.15%; PP overhead
still makes fresh-prompt total latency worse. Target source review is complete:
no-op invalidation (3.09 s of 5.50 s) is the first bounded proposal, with 128k
confirmation before expansion. Default OFF.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md).
See [short validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md)
and [implementation and commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).
Both diagnostic
wrappers now resolve relative paths against PowerShell's location, and the
updated Windows path/pipeline/recovery fixture passes. The concrete candidate
plan adds eligibility, same-setting state/rollback and focused A/B gates. See
[R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
[R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md) and
[R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md).
See [R4-COMMON002-SHORT-VALIDATION-2026-10-04.md](R4-COMMON002-SHORT-VALIDATION-2026-10-04.md);
[R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md) and
[R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).

See [BASELINE.md](BASELINE.md) for the current r4 gates.

## Provisional r4 decisions through 256k (updated 2026-10-04)

These decisions apply to the pinned r4 source, not moving upstream master.
Historical r3 `validated` statuses below remain unchanged.

| ID | Upstream coverage in r4 | Provisional action |
|---|---|---|
| COMMON-001 | Joined-PLE upstream path plus adapted split PLE16 support | Completed; Original/PLE16 load and 64k gates, PLE16 128k/256k validated on both backends |
| COMMON-004 | Persistent pooled keys and incremental dirty/new-pool updates exist | Do not port the old cache; scoped Vulkan cached-gather 128x4 gate closed without promotion |
| COMMON-002 | Native MTP loading, dense-sidecar graph guard, opt-in attribution diagnostics and guarded dense-indexer omission implemented | Earlier overnight 28/28 and short gates pass; wall reports recovered. New omission candidate passes Windows Vulkan native policy/model/state/rollback and A/B gates, then 8/8 allocation/short CLI runs and 256k wall A/B (draft layout removed) and normal ABBA (TG +32.62%, output/acceptance match); target source review complete (3.09 s no-op / 2.41 s suffix rebuilds), target no-op candidate implemented and Windows native gate Complete, then 8/8 allocation/short CLI runs pass with matched output/acceptance and target full rebuilds 57->33; 256k wall also passes 2/2 with matched output/ordered acceptance, target rebuilds 217->95, layout 5.53->2.44 s, wall TG +13.78% and PP unchanged; normal ABBA now passes 4/4 (TG mean 20.205->22.830, +12.99%, output/acceptance match); ROCm native gates and 8/8 allocation/short CLI now pass (matched output/acceptance, rebuilds58->36); ROCm256k normal collection3/3 OK (OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84), but A/B output/acceptance differ so long equivalence and isolated no-op benefit remain unresolved; B fresh-prompt evaluation+88.318s versus OFF; MTP OFF CLI/bench64k/256k collected (11 new runs OK, reused ROCm256k OFF); TG tool gaps within2.40%, ROCm PP agrees closely, Vulkan256k bench PP−19.40% versus CLI; next investigation decision including ROCm equivalence and PP workload/scaling gaps; 128k confirmation retained, default OFF |
| COMMON-005 | qwen4exp passes full K/V plus a selection mask; HIP sparse-FA dispatch is disabled | Deferred: mainly ROCm decode; retain its validated r3 evidence and revisit when ROCm is needed |
| VULKAN-002 | Adapted grouped-union PP added without replacing upstream sparse decode | Validated opt-in on Evo-X2 through 256k; keep default OFF and preserve the measured baseline |

The following historical regression gate led to the completed MoE diagnosis
above. The new user-directed order (GET_ROWS reference, COMMON-001, then TG/QSA
work) supersedes the earlier priority discussion below.

Before the optimization ports, investigate the Vulkan r3-to-r4 slowdown:
64k original-model PP is down 6.3%; TG versus the initial COMMON-004 ON
checkpoint is down 5.2% at 64k, 5.0% at 128k, and 8.4% at 256k. Neither r3 nor r4 has
VULKAN-002, so its absence does not explain this regression signal.
COMMON-004 is functionally covered but performance parity remains unverified.
A matched rerun/profile gate now precedes implementation priority 1.

Priority favors long-context wall-clock time: 128k Vulkan prompt evaluation
is 751 s versus 20 s of generation. COMMON-005 remains the strongest decode
candidate, and may move first if its residual bottleneck is confirmed and the
Vulkan port needs substantial investigation. COMMON-001 moves first if the
joined-layout comparison is needed or PLE16 is required. The 256k clean run passed.
At 256k, ROCm TG is 12.23 versus r3 Gather OFF 11.68 / ON 17.37;
Vulkan PP is 126.76 versus the r2 grouped-union reference 177.01.
These cross-version/layout gaps support continued investigation, not gain forecasts.
See [R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md)
for source evidence, comparison limits, and implementation gates.

### First r4 Vulkan profile (64k)

The first logger run completed with 61 prefill and 127 decode timing blocks.
Prefill FA accounts for 43.0% of measured GPU operator time (62.5% at the last
full ubatch). The current Vulkan sparse dispatch excludes the observed 1024/349
query prefill batches. Steady decode averages 40.60 ms of GPU operator timings;
pool norm shapes support incremental updates rather than full-pool recomputation.
See [R4-VULKAN-PROFILE-64K-2026-10-03.md](R4-VULKAN-PROFILE-64K-2026-10-03.md).

The matched COMMON-004 + Original profile is now available. GPU operator time
increases from 233.203 to 251.893 s for PP and 39.022 to 40.597 ms/token for
steady TG. PP MoE matmul accounts for +16.634 s; FA changes by only +0.735 s.
First isolate upstream `94a0ae3e7` (MoE tile selection) with a targeted A/B.
TG GET_ROWS + QSA fused/top-k timing increases by 1.022 ms/token; obtain tensor
names/shapes before assigning this to pooled-key gathering. Keep the incremental
cache and pool-domain selection; neither wholesale COMMON-004 restoration nor
VULKAN-002 explains the measured regression yet. Confirm fixes with the logger off.
See [R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md](R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md).

## Purpose

r3 applies downstream changes in small units on top of one exact upstream baseline.

This file is the human-readable patch registry for the validated r3 checkpoint. It should answer:

- what the patch changes
- why it exists
- which backend it affects
- whether it is currently applied
- how it is validated
- what performance effect was measured
- whether a newer upstream implementation changes the need to carry the patch forward

Patch IDs are stable documentation identifiers. They do not need to match Git commit hashes.

## Base

```text
BASE-000
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
status: validated
```

Historical clean r3 validation is recorded in [R3-BASELINE.md](R3-BASELINE.md).

The r3 branch remains the fixed comparison point while a separate upstream-refresh
branch is evaluated. A patch marked `validated` below means validated on this r3 base;
it does not mean the patch should automatically be re-applied to the refresh branch.

## Historical r3 registry (not the current branch matrix)

| ID | Scope | Status | Purpose |
|---|---|---|---|
| COMMON-001 | common | validated | PLE16 model loading support; re-evaluate need on refreshed upstream |
| COMMON-002 | common | evaluate | validate refreshed upstream MTP against the existing Unsloth draft model before porting compatibility code |
| COMMON-003 | common | evaluate | ROCmFPx format/core support only if still required by target models |
| COMMON-004 | common | validated | incremental pooled-key cache for the QSA indexer; compare with refreshed upstream k-pool implementation |
| COMMON-005 | common | validated | gather selected QSA K/V for long-context single-token decode; likely ROCm re-evaluation candidate after refresh |
| COMMON-006 | common | evaluate | intended block-domain QSA selection now exists upstream; validate instead of implementing on b11247 |
| VULKAN-001 | Vulkan | evaluate | ROCmFPx Vulkan kernels only if still required |
| VULKAN-002 | Vulkan | evaluate | QSA grouped-union / sparse-FA PP optimization after refreshed-upstream baseline |
| ROCM-001 | ROCm | none yet | reserved for a demonstrated ROCm-specific requirement |

`evaluate` means the feature existed or was relevant in earlier work, but the next
step is to verify what the refreshed upstream already provides before carrying a
downstream implementation forward.

Current execution order is tracked separately in [ROADMAP.md](ROADMAP.md).
Patch IDs remain stable and are not renumbered when priorities change.

## COMMON-001 - PLE16 loader

Status:

```text
validated
```

Base:

```text
upstream build: b11247
upstream commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

Goal:

Support the PLE16 layout used by the converted Unsloth Qwen3.8-Flash-Next model while preserving support for the original joined PLE layout.

Source/history:

```text
LaurentZuijdwijk/llama.cpp
bf9e0a2ace3b86f77950e5516f351110baa37f5d
qwen4exp: store the n-gram table one tensor per head
```

The historical conversion uses:

```text
gguf-py/gguf/scripts/gguf_split_ple_heads.py
```

The conversion splits the combined PLE n-gram table into per-head tensors without dequantizing or requantizing the model weights. The converter remains external and is not vendored into this repository.

Changed files:

```text
src/llama-arch.h
src/llama-arch.cpp
src/models/models.h
src/models/qwen4exp.cpp
```

Behavior:

- the original joined `per_layer_token_embd.weight` layout remains supported
- the loader auto-detects the split `ple_ngram_embd.N.weight` layout
- when the joined tensor is absent, all 16 split PLE head tensors are required
- split-head row indices are converted to each head's local vocabulary range before `get_rows`
- the per-head results are concatenated back to the layout expected by the qwen4exp graph

Runtime controls:

```text
none
```

Correctness validation:

- original joined model allocation/load: Vulkan OK, ROCm OK
- PLE16 model allocation/load: Vulkan OK, ROCm OK
- 64k real-input inference: Vulkan OK, ROCm OK
- 128k real-input inference with PLE16: Vulkan OK, ROCm OK
- 256k real-input inference with PLE16: Vulkan OK, ROCm OK
- no extreme long-context slowdown, allocation failure, or crash was observed through 256k

Benchmark workload:

- Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS
- PLE16 conversion for split-layout runs
- MTP off
- f16 K/V cache
- batch 2048, ubatch 1024
- 4 CPU threads
- all model layers offloaded where supported
- Flash Attention enabled
- 1024-token generation budget
- temperature 0.2, top_p 0.8

Measured results:

| Backend | Model | Context | PP (tok/s) | TG (tok/s) |
|---|---|---:|---:|---:|
| Vulkan | original joined | 64k | 266.23 | 16.96 |
| Vulkan | PLE16 | 64k | 267.90 | 17.20 |
| ROCm | original joined | 64k | 357.84 | 14.55 |
| ROCm | PLE16 | 64k | 357.93 | 14.86 |
| Vulkan | PLE16 | 128k | 159.56 | 12.00 |
| ROCm | PLE16 | 128k | 259.41 | 9.91 |
| Vulkan | PLE16 | 256k | 103.75 | 7.30 |
| ROCm | PLE16 | 256k | 167.35 | 5.74 |

Interpretation:

- at 64k, PLE16 has only a small performance effect relative to the original joined model
- the primary purpose of COMMON-001 is reliable loading and execution of the split PLE layout, especially at long context
- PLE16 completed the 128k and 256k validation runs on both Vulkan and ROCm without the extreme slowdown or crash behavior that motivated the split layout
- long-context PP/TG still decreases with context depth; this is treated as a separate performance-optimization topic rather than a COMMON-001 correctness issue

Known limitations:

- the PLE16 conversion utility is external to this patch
- COMMON-001 does not include MTP compatibility, MTP-QSA, grouped-union QSA, or ROCmFPx support
- ROCm and Vulkan place the model buffers differently; this patch does not attempt to normalize backend-specific placement

Upstream interaction:

The r3 patch is intentionally limited to qwen4exp PLE tensor naming, loading, and
graph assembly. On the refresh branch, first test the refreshed upstream with the
original joined Unsloth model. Only re-port COMMON-001 if the joined path still has
the stability/resource problem or if the PLE16 model remains operationally necessary.

## COMMON-004 - incremental pooled-key cache

Status:

```text
validated
```

Goal:

Reduce the long-context decode cost of the qwen4exp QSA indexer by caching
complete block summary keys instead of rebuilding pooled/normed/roped summaries
from the full raw indexer cache on every decode step.

Primary references:

```text
LaurentZuijdwijk/llama.cpp
d8ec9e66329c1340e6fc74eee9d66ea5eebdb7c4
qwen4exp: incremental pooled-key cache for the QSA indexer

LaurentZuijdwijk/llama.cpp
c659bd6d0c515e4f33f432139c71f3dfc19551de
qwen4exp: bound the pooled-cache dirty tables against speculative drafts

ggml-org/llama.cpp
PR #28699
qwen4exp: incremental pooled-key cache for the QSA indexer
```

The upstream PR is the preferred structural reference for the r3 port because
it includes later state/rollback and per-buffer allocation handling. The
Laurent version remains useful for Evo-X2/Vulkan behavior, the decode-sized
ubatch gate, and later speculative-safety fixes.

### Pre-implementation evidence

A 64k Vulkan diagnostic profile used the same PLE16 model, the same 61,789-token
input, MTP off, f16 K/V, batch 2048, ubatch 1024, and
`GGML_VK_PERF_LOGGER=1`.

| Build | QSA union | PP (tok/s, profiler on) | TG (tok/s, profiler on) | Steady GPU graph |
|---|---|---:|---:|---:|
| r2 | OFF | 221.44 | 7.78 | 44.18 ms/token |
| r2 | ON | 263.28 | 7.77 | 44.31 ms/token |
| r3 + COMMON-001 | n/a | 259.73 | 6.62 | 59.13 ms/token |

The profiler adds substantial wall-clock overhead, so its PP/TG values are not
used as absolute performance numbers. The GPU timestamp comparison is used to
locate the decode gap.

Relative to r2 union OFF, r3 adds about 14.95 ms/token of steady GPU graph time.
The following QSA-summary differences account for about 14.15 ms/token, or
94.6% of that gap:

- `CONT`: +11.38 ms/token
- full-block indexer RMS norm: +2.18 ms/token
- QSA-related RoPE: +0.59 ms/token

The r2 graph performs the expensive full pooled-summary refill on the first
decode step and then stops rebuilding the full block set. r3 continues the
full-context work on every decode step. All profiled runs reported
`graphs reused = 127`.

The grouped-union switch is therefore not the explanation for the r2 TG
advantage and remains a separate PP optimization.

### Implemented r3 behavior

- one persistent f32 summary row per complete position block per QSA layer
- pooled buffers allocated with the QSA indexer K storage on the appropriate
  buffer type/device
- only newly completed or invalidated blocks are pooled, normalized, RoPE'd,
  and written with `set_rows`
- QSA layers only; recurrent layers are excluded using the same layer filter as
  the indexer cache
- full state loads invalidate pooled trust and refill lazily
- sequence edits clamp or reset pooled validity as required
- speculative dirty writes are bounded so a build-time dirty-table estimate
  cannot overflow at fill time
- dirty-table sizing remains safe for M-RoPE / repeated-position inputs
- pooled-cache support is limited to a single-sequence memory configuration;
  unsupported multi-sequence/server cases use the full recompute path

### Runtime controls

```text
LLAMA_QSA_NO_POOLED_CACHE=1
```

Disables the pooled path for same-binary A/B and also skips pooled-buffer
allocation so memory A/B is meaningful.

```text
LLAMA_QSA_POOLED_MAX_TOKENS=32
```

Default 32; `0` means no ubatch-size limit. The default keeps the incremental
path focused on decode-sized ubatches and preserves the reference first-decode
refill behavior.

### Explicitly outside COMMON-004

Do not combine this patch with:

- multi-sequence pooled row windows or `--parallel > 1` pooled caching
- COMMON-005 gather-based QSA decode
- Laurent `44041e78650c9f8aca2642842302dc8139907ded` reverse-scan `get_prev_tokens`
- grouped-union / Vulkan sparse-FA changes
- Unsloth MTP compatibility
- MTP-QSA
- ROCmFPx format or kernel work

### Validation results

COMMON-004 is validated on both Vulkan and ROCm with the PLE16 model and MTP
disabled.

| Backend | Context | Pooled cache | PP (tok/s) | TG (tok/s) |
|---|---:|---|---:|---:|
| Vulkan | 64k | OFF | 269.18 | 17.13 |
| Vulkan | 64k | ON | 262.89 | 25.95 |
| Vulkan | 128k | OFF | 159.39 | 11.91 |
| Vulkan | 128k | ON | 156.47 | 24.00 |
| Vulkan | 256k | OFF | 102.77 | 7.27 |
| Vulkan | 256k | ON | 98.63 | 21.03 |
| ROCm | 64k | OFF | 348.90 | 14.82 |
| ROCm | 64k | ON | 356.55 | 20.62 |
| ROCm | 128k | OFF | 262.67 | 9.89 |
| ROCm | 128k | ON | 261.67 | 16.44 |
| ROCm | 256k | OFF | 167.07 | 5.52 |
| ROCm | 256k | ON | 166.18 | 11.60 |

TG improvement with pooled caching enabled:

- Vulkan: +51.5% at 64k, +101.6% at 128k, +189.3% at 256k
- ROCm: +39.1% at 64k, +66.2% at 128k, +110.1% at 256k

The pooled-cache allocation grows as expected with context depth. ROCm compute
buffers are unchanged by cache ON/OFF. Vulkan retains the previously observed
compute-buffer expectation warning on successful pooled-cache runs.

ROCm residual profiling after COMMON-004 identified two remaining O(n_kv)
decode costs: full-context Flash Attention and block-score-to-full-cell
expansion. That profiling motivated COMMON-005 and the original COMMON-006
design. The refresh branch should compare this r3 implementation with the newer
upstream k-pool path rather than blindly re-applying COMMON-004.

Detailed RGP and source-trace notes are recorded in
[ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md](ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md).

> **r5 migration assessment (2026-10-11):** [R5-COMMON005-PORT-FEASIBILITY-2026-10-11.md](R5-COMMON005-PORT-FEASIBILITY-2026-10-11.md). The r3 compact-K/V **concept** remains usable, but the old patch is not source-portable: r5's `selected_rows` contains invalid dump rows, and `build_qsa_sel` constructs an additive mask rather than passing per-cell top-k IDs. Separate correctness-first r5 adaptation needed; deferred for now. The historical validation below remains r3-only.

## COMMON-005 - gather-based QSA decode

Current r4 priority (2026-10-04): deferred while Vulkan/COMMON-002 MTP is
prioritized. The validated status and implementation below describe r3.

Status:

```text
validated
```

Implementation commit:

```text
d03c91b6342b099457de3508c5d67533a9a5f0ee
qwen4exp: gather selected QSA KV rows for decode
```

Goal:

Reduce the remaining long-context QSA attention cost after COMMON-004 by
running decode attention on selected compact K/V rows instead of feeding the
full KV cache to Flash Attention.

Primary references:

```text
ggml-org/llama.cpp
PR #28213
qwen4exp : gather-based sparse attention for QSA decode

current upstream MiniMax-M3 decode path
selected K/V/mask gather before Flash Attention
```

Implemented behavior:

- qwen4exp single-token decode only
- gathers selected K rows, V rows, and existing KQ-mask rows after top-k
- runs ordinary Flash Attention on physically compact K/V tensors
- prompt/batched/speculative paths retain the existing fallback
- short contexts retain the existing fallback through the `n_kv >= 4*width` gate
- fallback keeps the existing `n_kv_max` sparse-FA hint
- COMMON-004 pooled-key handling and `build_qsa_top_k()` are unchanged

Runtime control:

```text
QWEN4EXP_QSA_GATHER=0   # force fallback
QWEN4EXP_QSA_GATHER=1   # enable gather path where eligible
```

The current source treats unset/empty as enabled. Vulkan A/B results show that
this is not necessarily the fastest choice at every context depth, so retain
the runtime control while backend/context policy remains under evaluation.

### ROCm validation

ROCm build/backend tests, allocation-only smoke, and all 10 real-input A/B runs
passed.

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG gain |
|---|---:|---:|---:|---:|---:|
| 64k | 359.37 | 357.27 | 20.55 | 22.60 | +10.0% |
| 128k | 262.44 | 262.50 | 16.425 | 20.41 | +24.3% |
| 256k | 167.58 | 167.99 | 11.68 | 17.37 | +48.7% |

128k and 256k are ABBA averages; 64k is one OFF/ON pair. PP is effectively
unchanged.

128k -> 256k added decode latency falls from about +24.73 ms/token with Gather
OFF to +8.57 ms/token with Gather ON, removing about 65% of the residual depth
slope.

RGP confirms the intended mechanism:

```text
pre-COMMON-005 Flash Attention
128k ~= 1.452 ms
256k ~= 2.939 ms

COMMON-005 compact Flash Attention
128k ~= 41.93 us
256k ~= 42.00 us
```

The full-context Flash Attention scaling is therefore removed on the profiled
ROCm path.

The remaining repeated `k_get_rows_float` still scales approximately 2x:

```text
128k ~= 447.92 us
256k ~= 907.13 us
```

This was the post-COMMON-005 evidence for the original COMMON-006 proposal.

### Vulkan validation

Vulkan FLASH_ATTN_EXT backend tests passed 5297/5297, allocation-only smoke
passed, and all real-input A/B runs completed.

| Context | Gather OFF PP | Gather ON PP | Gather OFF TG | Gather ON TG | TG change |
|---|---:|---:|---:|---:|---:|
| 64k | 261.98 | 262.44 | 25.95 | 25.42 | -2.0% |
| 128k | 156.275 | 156.16 | 24.61 | 24.12 | -2.0% |
| 256k | 98.065 | 97.975 | 21.135 | 21.69 | +2.6% |

64k is one OFF/ON pair. 128k and 256k are ABBA averages.

Vulkan already has backend sparse Flash Attention support, so COMMON-005 is not
a universal speedup there. The existing fallback is slightly faster at 64k and
128k, while model-side gather is slightly faster at 256k. Both ABBA pairs show
the same direction at each depth, but the effect is only a few percent and does
not justify a precise automatic crossover threshold from the current data.

The known Vulkan compute-buffer expectation warning occurs on both Gather OFF
and Gather ON runs and is not treated as a COMMON-005 regression.

### Final interpretation

COMMON-005 is validated because correctness/build/runtime gates pass on both
backends and the intended ROCm bottleneck is removed. Performance policy remains
backend-dependent:

- ROCm: gather is strongly beneficial and increasingly valuable with context depth
- Vulkan: gather and the existing sparse-FA fallback are close; fallback wins
  slightly at 64k/128k and gather wins slightly at 256k

The refreshed upstream must be measured before deciding whether COMMON-005 is
still required. Current upstream CUDA code explicitly excludes HIP from sparse
Flash Attention, so ROCm remains the highest-value place to look for a residual
need for this downstream compact-K/V path.

Detailed final results are recorded in
[COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md).

## COMMON-006 - block-domain QSA selection upstream evaluation

Status:

```text
evaluate
```

Original r3 goal:

Remove the remaining O(n_kv) score-expansion work in `build_qsa_top_k()` after
COMMON-005 removed the full-context ROCm attention cost.

The b11247/r3 flow was:

```text
block score
  -> expand score to every KV cell through cell_blk
  -> cell-level top-k
```

The intended downstream direction was:

```text
block-domain selection
  -> expand only selected blocks to cell indices
```

Post-COMMON-005 RGP showed the repeated block-to-cell `k_get_rows_float` at
about 0.448 ms at 128k and 0.907 ms at 256k. With 12 full-attention groups per
token, its nominal increase accounts for roughly 64% of the measured
COMMON-005 ON 128k -> 256k ROCm latency increase.

### Upstream checkpoint decision

Do not implement COMMON-006 on the frozen b11247 base.

Upstream PR #29751 (`llama: fix qwen4exp`, merge commit
`66e0c17ee1741fef493312e17fe60a5d2cf5f7d5`) replaced the qwen4exp QSA/k-pool
path. In the current upstream source observed on 2026-10-02, qwen4exp now:

- computes `n_top_pool = min(n_pool, indexer_top_k / kpool)`
- applies `ggml_top_k()` directly to the pool/block score
- expands only the selected pool indices to cell indices
- appends the retained tail indices separately

That is materially the same optimization direction COMMON-006 was meant to
explore. Implementing an independent b11247 version now would create a second
lineage immediately before an upstream refresh.

### Refresh-branch validation

Treat COMMON-006 as an upstream validation item, not a downstream patch, until
measurements say otherwise:

- establish clean Vulkan and ROCm baselines on the pinned refresh commit
- compare 64k/128k/256k PP and TG against the r3 COMMON-005 checkpoint
- verify the old full-cell score-expansion `k_get_rows_float` slope is gone or
  materially reduced
- verify tail/causal/visibility behavior with real model output
- only create a new downstream delta if the refreshed upstream leaves a measured
  bottleneck or correctness gap on Evo-X2

The historical semantic requirements remain useful as review checks:

- `indexer_top_k` budget behavior
- tail-block handling
- causal/visibility masking
- tie and ordering behavior

## COMMON-002 - Unsloth MTP compatibility

Status:

```text
evaluate
```

Goal:

Load and run the existing Unsloth Qwen3.8-Flash-Next MTP draft model on the
refreshed upstream, adding only the compatibility delta that is still missing.

Upstream PR #29761 (`Qwen4Exp: add MTP`) merged on 2026-10-01. It adds qwen4exp
MTP conversion/tensor support and fixes the draft-model load path, so the old
r3 plan to port MTP support first is no longer the correct starting point.

Current priority (2026-10-04): active after validated VULKAN-002; COMMON-005's
historical ROCm decode port is deferred. Pinned-source inspection is complete: native sidecar
loading, HC-wide hidden transfer, MTP-layer QSA and bounded recurrent rollback
are present. The dense sidecar's unused QSA-input assertion is fixed by the
layer-ratio guard. Rebuilt Vulkan allocation and 32k OFF/ON generation pass;
TG improves in the first pair but total latency increases for 128 generated
tokens. The overnight matrix now passes 28/28 runs through 256k. TG OFF -> ON
at 256k is Vulkan 19.76 -> 15.245 and ROCm 12.405 -> 10.955 tok/s. Vulkan
128k/256k acceptance stays near 67%, so acceptance alone does not explain the
loss. Dense draft/catch-up work, CPU pool-layout rebuilding after sequence edits,
unused dense-draft indexer bookkeeping and small-query verification dispatch
need separate timing. Exhaustive output/rollback equivalence remains unproven.
Investigate TG first, then MTP PP overhead, then ROCm long-context PP scaling.
See [R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md)
for all results and focused diagnostic gates, and
[R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md)
for the initial source review, compatibility fix and matrix plan.

Diagnostics, artifact identity and the focused wall collection are complete.
The bounded optimization is implemented; design:
[R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
based on the
[layout source review](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md).
The default-off opt-in omits allocation only for the supported single
ratio-zero MTP block and retains hybrid, attention and recurrent handling.
Windows Vulkan build, native rollback and same-setting restore now pass in the
14:50 report, with identical A/B logits/hidden on eight output pairs. All three
allocation smokes and five short CLI gates also pass; draft indexer/layout/pool
events are absent only in B. Candidate 256k wall A/B passes with TG
14.76 -> 19.95 tok/s and generation time 34.61605 -> 25.60850 s.
Output bytes and ordered acceptance history match. Draft layout 9.767278 s
is removed; target layout remains 5.499980 s. PP gains only 0.13%, so MTP PP
overhead remains open. Normal 256k ABBA now passes with the same binary:
TG mean 15.220 -> 20.185 (+32.62%), generation time -8.247875 s, matched
output/acceptance and effectively unchanged PP. Earlier normal OFF is
TG19.76/PP265.02, so B's TG advantage is small and fresh-prompt latency still
loses. Retain the opt-in for subsequent Vulkan MTP tests; investigate retained
target layout separately and confirm 128k before wider expansion.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md) and
[implementation and Windows commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).

Target layout source investigation is complete at the current source baseline:
full acceptance still calls trim, and no-op indexer removals unconditionally
stale the layout. B-wall target cost splits into 122 no-op-associated rebuilds /
3.092231 s and 95 real suffix rebuilds / 2.407742 s. A separate default-off
no-op invalidation candidate is now implemented and retains recurrent/indexer/
attention removal calls and pending stale markers. Actual suffix reuse follows separately;
CPU layout dirtiness must not clear required pooled-key invalidation.
No runtime change is included in this review. The
[target no-op implementation plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md)
is approved and delivered: separate default-off switch, actual membership-count
check, existing dirty-state preservation, numeric target QSA tests and short/
wall/normal A/B with draft omission1 fixed. Local policy, C++ syntax, PowerShell
source and diagnostic checks pass. The19:12 Windows Vulkan native gate is now
Complete after the accessor correction: all524 vector comparisons match exactly,
with67 actual no-op suppressions and33 preserved pending stale markers. The
allocation/short CLI gate now also passes8/8 with Verified startup/runtime
evidence, matched A/B response bodies and acceptance,25 no-op suppressions
and all33 real-removal stale marks preserved. Target full rebuilds fall57->33.
Short normal TG34.81->34.86 does not establish a speedup. The256k wall gate
now also passes2/2 with matching output and ordered218-round acceptance
history:123 no-op suppressions, all95 real-removal stale marks retained,
full rebuilds217->95 and layout5.529702->2.436146 s. Wall TG19.96->22.71
(+13.78%) while PP230.12->229.92 is effectively unchanged. Diagnostic-OFF
normal ABBA now also passes4/4 with matched output/aggregate acceptance:
mean TG20.205->22.830 (+12.99%), mean PP229.940->229.565 (-0.16%). Keep source
default OFF. Residual suffix rebuilds retain2.436146 s but further TG/PP
implementation is parked: the user requests ROCm build/measurement, then
CLI/bench comparison, then the next optimization decision. New focused ROCm
short/256k and staged CLI/bench plans are prepared; local source/PlanOnly checks
pass. Windows ROCm native gates now both pass and all8 allocation/short runs
are OK with Verified runtime and matched A/B output/acceptance. The short
wall confirms23 no-op suppressions and36 real-removal stale marks retained
(full rebuilds58->36). B-normal PP48.16 is an unexplained outlier, retained
for follow-up. ROCm256k normal collection now finishes3/3 OK with the same
Verified runtime: OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84.
The short PP collapse is absent here, but A/B response/acceptance differ
(289/441 versus286/448), leaving long equivalence and isolated speedup open.
B evaluation remains88.318s slower than OFF. MTP OFF CLI/bench64k/256k is now
collected:11 new runs OK, eight bench rows/20 timed repetitions, plus the reused
ROCm256k OFF reference. TG gaps within2.40%; ROCm PP agrees closely, while
Vulkan256k bench PP216.09 is19.40% below CLI268.10. ROCm PP roughly halves
between depths in both tools without MTP. Native uint64 time-SD overflow is
identified; mean speed and throughput SD verify against samples. Bench does
not settle speculative correctness. Choose the next source investigation
separately. No inference code changed or rebuild needed.
See [CLI/bench data](R4-COMMON002-CLI-BENCH-COMPARISON-2026-10-05.md).
See [ROCm256k review](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md).
See [ROCm native/short validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md).
See [normal ABBA validation](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md) and
[ROCm/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).
See [256k wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md).
See [allocation and short CLI validation](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md).
See [implementation and Windows commands](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md) and
[target source review](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md).

Refresh-branch validation plan:

- test the existing Unsloth Q8_0 MTP sidecar without downstream MTP patches
- confirm draft model allocation and short-context generation
- confirm recurrent rollback behavior and no state-replay regression
- report draft acceptance statistics
- compare MTP on/off at short and long context
- separately measure long-context PP overhead
- port only the minimum compatibility change if the existing sidecar still fails

Keep historical downstream MTP-QSA changes outside this compatibility gate.
Ordinary upstream MTP already uses QSA when its pool/compression metadata is
present; any additional prototype must demonstrate a missing delta and value.

## COMMON-003 - ROCmFPx format/core support

Status:

```text
evaluate
```

Earlier work used ROCmFP4-FAST model variants from AgentionAI.

Before porting format/core changes, verify exactly what the pinned refresh
upstream already supports and what the target model still requires.

Only missing functionality should be carried forward.

## VULKAN-001 - ROCmFPx Vulkan kernels

Status:

```text
evaluate
```

Port only if the target ROCmFPx model requires downstream Vulkan kernel support after COMMON-003 evaluation.

Keep format/core support and Vulkan kernel support as separate reviewable changes where practical.

## VULKAN-002 - QSA grouped-union / sparse-FA PP optimization

r4 status:

```text
validated opt-in on Evo-X2 through 256k; default OFF
```

Implementation `5814fbe99e9249e8ac2c4c2e9b977c05735b0912` adapts the r2
64-query grouped-union/gather path to current FA, with final remapped cell-id
metadata, device-local counts and dynamic flag 32 separate from sparse bit 16.
It preserves the current selector/cache and one-query sparse/decode fallback.

Windows build and 18/18 GPU tests pass OFF/ON. Profile and normal 64k gates pass,
and PLE16 normal ABBA at 128k/256k yields PP 178.97 -> 295.68 and
132.96 -> 266.75 tok/s (+65.2%/+100.6%), with effectively neutral TG.
The recorded earlier ROCm PP is 279.80/185.90, so Vulkan now leads this tested
long-context workload. Source defaults stay OFF; broader device/model/default
promotion and ordinary MTP validation remain separate.

The two Vulkan-specific switches in the tested baseline are legacy MoE tile
selection=1 (already used at COMMON-001) and union=1. GET_ROWS 128x4 remains 0.
These switches do not provide ROCm acceleration. COMMON-001 is a common layout
compatibility patch; optional FA metadata does not replace ROCm's algorithm.

- Results and comparison limits:
  [R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).
- Implementation and original execution gates:
  [R4-VULKAN002-IMPLEMENTATION-2026-10-03.md](R4-VULKAN002-IMPLEMENTATION-2026-10-03.md).
- Historical donor/source review:
  [R4-VULKAN002-PORT-REVIEW-2026-10-03.md](R4-VULKAN002-PORT-REVIEW-2026-10-03.md).

## MTP-QSA prototype

The historical downstream MTP-QSA prototype remains outside the refresh stack.
Pinned upstream's ordinary MTP graph already builds its own QSA/indexer path.
The old assumption that draft QSA must first be added no longer applies.

Reconsider a prototype only after COMMON-002 sidecar compatibility, actual QSA
activation and normal MTP OFF/ON/long-context overhead are measured. Identify a
concrete gap relative to the pinned implementation and validate only that delta.
Deferred ROCm COMMON-005 work is not a prerequisite for ordinary Vulkan MTP.

## Patch documentation template

Add a section for every patch that reaches implementation status.

Recommended fields:

```text
ID:
scope:
status:
base commit:
purpose:
source/history:
changed files:
build requirements:
runtime controls:
correctness validation:
benchmark workload:
benchmark result:
known limitations:
upstream interaction:
```

## Commit discipline

A patch should not be marked `validated` merely because it compiles.

For this project, validation normally means:

1. targeted build succeeds
2. relevant backend test succeeds
3. target model loads
4. target workload completes
5. result is compared to the immediately preceding baseline
6. logs are retained outside Git when they are too large or machine-specific
