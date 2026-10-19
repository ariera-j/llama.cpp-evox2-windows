# Evo-X2 optimization roadmap

> **2026-10-20 64k Natural MTP diagnostic completed:** C/A/B using b11695 produced identical 128-token output and all 52 ordered Draft decisions (30 accepted 2/2, 15 accepted 1/2, 7 accepted 0/2; aggregate 75/104 accepted). Same executable and input, P-MODE Performance; no explicit checkpoint restore in Natural. See [experiment report](R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md) in the rollback investigation branch. Next: 64k reject-after-one forced checkpoint and replay comparison. The diagnostic timings are not performance measurements.

> **ROLLBACK ACCEPT-ALL SHORT: C/A/B PARITY PASS; STRICT NO-REJECT GATE NOT PASS — 2026-10-19 ~23:39 JST:** b11695 Vulkan `--spec-synth-rates 1,1`: **41/43 2-of-2 full accept rounds**, but rounds **31 and 37** rejected 0/2 and invoked 2 full checkpoint restores/replay commits per arm, likely existing drafted-EOG safeguard (draft EOG token not explicitly logged, so mechanism **unconfirmed**). All C/A/B 134-event sequences, text, executable/conditions and acceptance 82/86 identical; P-MODE Performance. [Detailed source-ZIP analysis](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-rollback-diagnostic-20261019/docs/evox2/R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md). **Next P0: unchanged b11695 `rollback-64k` Natural, then forced Reject-after-one** if no divergence. Accept-all's strict no-rollback PASS remains outstanding, optional direct EOG-guard instrumentation; do not flatten this nuance into “all four strict PASS.” Synthetic speeds/results are not performance/quality data; stable r5 unchanged.

> **ROLLBACK REJECT-AFTER-ONE SHORT C/A/B PASS — 2026-10-19 ~23:31 JST:** On identical b11695 Windows Vulkan, `--spec-synth-rates 1,0` with forced Target/Draft checkpoint restoration: **41** first-accept/second-reject rounds + **1** all-reject round (round28, cause unconfirmed; drafted EOG safeguard possible) and one terminal 1/1 accept, yielding **42 actual checkpoint restores and 42 replay commits per C/A/B**. All 214 structured events/arm, generated text and acceptance **42/85**, exe/runtime/model/seed and Performance P-MODE agree. [Native evidence and details](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-rollback-diagnostic-20261019/docs/evox2/R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md). **Next P0: short Accept-all (1,1)** with the same b11695, then 64k Natural and forced partial-reject if all four short cases are clear. No source change or rebuild; synthetic output not a quality test.

> **ROLLBACK REJECT-ZERO SHORT C/A/B PASS — 2026-10-19 ~23:14 JST:** b11695 Vulkan [full analysis](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-rollback-diagnostic-20261019/docs/evox2/R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md): explicit synthetic `--spec-synth-rates 0,0`, `LLAMA_MTP_ROLLBACK_FORCE_CKPT=1`, 63 original 0/2 decisions + 63 Target/Draft checkpoint restore events + 63 replay commits **per C/A/B**. Native exit0 and P-MODE Performance, same b11695 executable SHA and input/model identities; all ordered 316-event streams and normalized 128-token output exactly match. **Next P0: same-binary Reject-after-one (1,0), then Accept-all (1,1); once short gate complete consider selective 64k.** Synthetic outputs are diagnostic, not verified semantic outputs. Stable r5 inference source unchanged.

> **ROLLBACK NATURAL SHORT C/A/B PASS — 2026-10-19 ~22:58 JST:** New b11695 Vulkan diagnostic binary, same exe SHA and models, all three C/A/B native runs completed OK, 163 prompt/128 generated, exact generated text and full **58 ordered accept/reject decisions** matched: 14 zero-of-two, 19 one-of-two, 25 two-of-two; Draft accepted **69/116**, P-MODE Performance, diagnostics ON. [Full run report](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-rollback-diagnostic-20261019/docs/evox2/R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md). Natural had 33 rejecting rounds using partial removal but **zero explicit checkpoint restores/replays**. Next P0: same-binary **reject-zero (0,0)** short C/A/B forced-checkpoint smoke; if it passes then reject-after-one (1,0), accept-all (1,1); no 64k until short complete. Diagnostic PP/TG not performance evidence; stable inference source unchanged.

> **ROLLBACK DIAGNOSTIC SOURCE PREPARED — 2026-10-19:** New isolated branch [`investigation/r5-mtp-rollback-diagnostic-20261019`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-rollback-diagnostic-20261019), based on 128k-complete K/V parity branch, adds opt-in structured MTP speculative `draft/decision/checkpoint_restore/commit` trace and **synthetic 0,0 / 1,0 / 1,1** accept/reject paths with explicit checkpoint-restore option; C/A/B short and optional 64k plans, plus automated fail-closed coverage analyzer/tests. [Detailed design and Windows steps](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-rollback-diagnostic-20261019/docs/evox2/R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md). **No native Windows compilation or execution has yet verified this new branch.** Next: test parser → build new Vulkan binary → run natural short C/A/B first → forced 0/0,1/0,1/1 one case at a time → 64k if passed. Synthetic text does **not** validate model response quality. Existing b11682 and r5 stable untouched.

> **128K COMPLETE DRAFT STATE HASHES MATCH — 2026-10-19 evening:** User computed SHA256 on **all nine existing 128k Draft sequence-state files**, with C=A and A=B **True at 32,768 / 65,536 / 126,253** tokens. [Canonical report](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-draft-kv-parity-20261019/docs/evox2/R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md). This extends the independently verified K/V element-wise PASS to **bit-identical serialized attention+recurrent+(when present) indexer states** at the recorded prompt checkpoints. Raw 64-character hashes/files were not uploaded; these equality booleans are user-reported. **Next P0: controlled speculative accept/reject/rollback + post-prefill continuation correctness** (and optional MTP-OFF negative control), not another KV parser. Integration candidate may be prepared separately but Stage-B/flatten are not yet final correctness-approved. Stable source unchanged.

> **DRAFT K/V 128K GATE PASSED — 2026-10-19 ~22:08 JST:** [128k C/A/B evidence and provenance](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-draft-kv-parity-20261019/docs/evox2/R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md): all six comparisons f16 Draft attention K/V **bitwise identical** at 32768/65536/126253 positions, same b11682 Vulkan exe SHA, P-MODE Performance, complete 512-token output identical, Draft acceptance 295/429. **Short + 64k + 128k attention K/V gate is complete.** Next P0: compare the entire existing sequence-state snapshot, then controlled reject/rollback/continuation and model recurrent state if serialization differs. New upstream integrated build remains a separate candidate task; diagnostic PP is NOT a speed result. No stable inference merge.

> **DRAFT K/V 64K GATE PASS — 2026-10-19 ~21:34 JST:** [Full 64k C/A/B native evidence](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-draft-kv-parity-20261019/docs/evox2/R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md) on Vulkan b11682: all six Draft attention K/V comparisons PASS **bit-for-bit** at actual 2,048 / 32,768 / 61,789 positions; K and V each 512 f16 elements/token, 1 layer. C/A/B all ran the identical verified binary and text/acceptance 295/430 matched; P-MODE Performance throughout. **Next P0 = 128k C/A/B thresholds 32768/65536/126253**, then separate recurrent-state and rollback/rejection gate; no further Vulkan RGP now. This updates the previous “next 64k” note without erasing historical checkpoints. Diagnostic PP/TG must not be used for benchmark claims. No source changes in r5 stable.

> **DRAFT K/V SHORT GATE PASS — 2026-10-19 ~21:16 JST:** In [isolated diagnostic branch](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-draft-kv-parity-20261019/docs/evox2/R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md), native Windows Vulkan b11682 compiled and C→A / A→B Draft attention f16 K and V snapshots for a 163-token prompt were **bitwise identical** (83,456 K and 83,456 V values per comparison, zero error). B-arm ZIP independently verified OK, acceptance17/27, P-MODE Performance. **Only short is validated; next P0 = full 64k C/A/B numeric snapshots at 1024/32768/61789, then 128k if pass.** Native build manifest recorded Source.Dirty=true; check local worktree diff and equal executable hashes across arms before final attestation. Stable r5 inference source unchanged.

> **P0 DIAGNOSTIC IMPLEMENTATION ADDED — 2026-10-19:** The new isolated branch [`investigation/r5-mtp-draft-kv-parity-20261019`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-draft-kv-parity-20261019) contains an opt-in public-API Draft sequence-state snapshot hook, a C/A/B (Stage-B OFF / Stage-B ON flatten OFF / Stage-B ON flatten ON) **short/64k/128k correctness plan**, a f16 K/V numerical comparator and synthetic parser tests. [Implementation / Windows handoff](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-draft-kv-parity-20261019/docs/evox2/R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md). **No native Windows build or real K/V comparison has run yet**, so code remains experimental. Next gate: build a NEW Vulkan binary, run short C/A/B, compare K/V numerically; only then 64k/128k and rollback. r5 stable inference source and the b11659 RGP/ABBA binary remain unchanged.

> **RGP MILESTONE CLOSED — 2026-10-19 20:22 JST:** [Same-binary A/B Vulkan RGP comparison](R5-MTP-EH-PROJ-FLATTEN-RGP-2026-10-19.md) is complete: two 1024-token Draft graphs, flatten OFF 61.015/63.891ms versus ON 9.238/9.370ms; main GEMM 55.866/58.487ms versus 4.043/4.046ms. Full Draft graphs ~85% faster, main GEMM ~93% faster in the RGP slice; both variants have 20 dispatches, so the benefit is **kernel shape/tile, not fewer dispatches**. **NEXT P0: numeric Draft K/V equivalence, continuation and rollback; no more routine RGP required.** Diagnostic PP and RGP overhead are explicitly separate from normal ABBA. No source merged into r5.

> **FOLLOW-UP 2026-10-19 19:53 JST:** [Flatten ON RGP + profiling overhead record](R5-MTP-EH-PROJ-FLATTEN-RGP-2026-10-19.md) is complete. Vulkan main Q8 GEMM ~4.04ms and Draft graph ~9.24/9.37ms locally versus historical old ~56–59ms/62–64ms. Optional same-binary A-flat-off RGP; **next required gate is numerical Draft K/V correctness**. Profiling PP 330.50 trace-only / 312.20 with RGP vs untraced 349.39 tok/s, observational not causally attributed. Stable source unchanged.

> **CURRENT NEXT STEPS — 2026-10-19:** [Oct 19 research, external update and new-upstream integration plan](R5-RESEARCH-AND-INTEGRATION-PLAN-2026-10-19.md). Today: focused **b11659 flatten-ON RGP**, optional same-binary flatten-OFF GPU comparison, then numerical Draft K/V correctness. Next substantive work window: **separate new-upstream candidate integration**, reviewing all beneficial past patches with source/dependency/correctness gates rather than merging blindly. If time before integration: s1-fork shape/CONCAT source review, isolated test only. Strata Windows gfx1151 is a later independent trial. No source integration/rebase/build is asserted by this document-only update.


> **UPDATE 2026-10-15 19:16: P-MODE IS NOW A RECORDED BENCHMARK CONDITION; PERFORMANCE/BALANCED/QUIET STATES ARE DISTINCT.** Direct Evo-X2 64k llama-bench sequence Performance→Quiet→Balanced→Performance measured **357.26 / 298.21 / 339.16 / 356.98 tok/s**, with high-load ADLX GPU clock/power approximately **2879MHz/114W, 2151MHz/53.5W, 2622MHz/84.8W, 2872MHz/115.3W**. ACPI-WMI method2 independently reads raw **0=Balanced, 1=Performance, 2=Quiet**; normal-user benchmark wrappers now obtain fresh start/finish values through a one-shot highest-privilege scheduled task and classify ADLX high-load power only as a consistency warning. End-to-end b11560 64k validation: PP **360.488 tok/s**, start/finish Performance, no mode change, 85 high-load samples averaging **115.047W**, `Performance-like`, warnings=0. The earlier ~339 tok/s Vulkan state is therefore **strongly consistent with Balanced mode**, but old runs without P-MODE metadata are not retroactively relabeled. Physical display/RDP routing is not the performance control: physical cable attached vs detached under RDP reproduced the fast state. **Operational rule: keep P-MODE=Performance and require start/finish metadata before interpreting future PP shifts. Source optimization work may continue; do not reopen Windows/RDP forensics first unless authoritative P-MODE and ADLX disagree.** [Validation report](R5-ADLX-PMODE-VALIDATION-2026-10-15.md).

> **UPDATE 2026-10-15 00:21: OCT11 ROCm 15:25–16:19 RAW ABBA VERIFIED; NO SIMULTANEOUS ROCm FAST-SIDE EVIDENCE.** Full 74-entry ROCm ZIP SHA matches archived report. Same b11560 64k OFF A1/A2 PP392.61/391.98, 128k OFF PP293.76/295.66; 128k 32–49k→98–115k segment times grow smoothly, A1/A2 differ by near-constant ~2.5s accumulated offset, with no 32k-specific acceleration. Oct10 ROCm b11543 `llama-bench` repeated ANLP 64k394.030/128k296.274 is close context (not same-binary CLI control). Oct11 subsequent Vulkan 17:11–17:59 high PP cannot be attributed to simultaneous 15:25–16:19 ROCm high state on present evidence. September Qiita ROCm >20% spikes are real history but not proven same mechanism as October11 Vulkan ~6–9% elevation. Continue to treat intermittent high PP as a separate hypothesis; seek GPU frequency/power/hotspot and per-kernel timing when high state recurs rather than optimizing source against an alleged Windows regression. [Raw checkpoint analysis](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#2026-10-15-0021-rocm-pre-vulkan-archive-independently-reverified).

> **UPDATE 2026-10-14 23:39: QSA-OFF CONTROL MATCHES 10/09 BASELINE; INVESTIGATE EPISODIC HIGH PP, NOT A PROVEN REGRESSION.** Reused exact archived b11560 with 128k PLE16/MTP OFF: QSA OFF PP180.32 TG23.63, versus Oct09 b11530 OFF179.34/TG24.03; post-reboot Oct14 same-binary QSA ON306.75/TG23.64, versus Oct09 b11530 ON307.15/TG23.53. Oct11 b11560 ON A1/A2 PP336.06/334.85 (mean335.455); 64k Oct11 OFF-MTP QSA-ON A1/A2 PP360.57/362.47 vs Oct09 b11530 ON mean339.48. Stable elevated output across many runs **is not a single random spike**, and user recalls sporadic PP upside for >1 month. Off/ON progress identical to ~32k then diverges, and Oct11 elevated ON rate materializes above same 32k boundary. Missing Oct11 QSA-OFF control means it remains unproven whether boost was QSA-specific. **NEXT:** preserve high-versus-normal regimes as distinct session states, seek archival high samples or sample GPU frequency/power/hotspot when it recurs, keep current r5 optimization source untouched; do not overstate Windows Update/RDP effects. [Forensic details](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#2026-10-14-2339-b11560-128k-mtp-off-union-off-control-and-episodic-high-pp-hypothesis).

> **UPDATE 2026-10-14 22:37: NORMAL POWERSHELL MATCHES DEVELOPER SHELL (PP ~305).** Reused exact archived b11560 executable, identical runtime digest/input/effective inference conditions; normal Windows PowerShell 128k MTP OFF PP305.90 TG23.66 vs VS2022 Native Tools-origin PP305.18 TG23.68, while 10/11 old b11560 A1/A2 mean PP335.455. The >32k-only ~12–13% per-interval slowdown persists with both shells and same QSA union path=1/minKV32768. Neither developer-shell PATH inheritance nor Stage B source/binary changes explain ~9% cross-date PP loss. Windows Update finished but system **has not yet rebooted**. NEXT: controlled reboot + one archived b11560 128k MTP OFF retest before QSA min-KV/RGP and GPU clock/power sensors. [Native 22:37 same-binary comparison](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#normal-powershell-b11560-128k-control--2026-10-14-2237-jst).

> **UPDATE 2026-10-14 22:00: CROSS-DATE PP BREAKPOINT IS KV=32768.** Recovered original 10/11 b11560 128k MTP OFF A1/A2 and Windows Update/Defender event CSV. Same executable/DLL SHA and command/input/model, same OS major build 26300 and AMD GPU driver 32.0.31041.1004 on 10/11 and 10/14; 10/14 b11560 matches 10/14 b11618 at ~305 PP vs 10/11 old 335 PP. Per-PP checkpoints: at 32k **10/11 79.335s vs 10/14 78.82s**, essentially equal, then all later intervals **+12.46%–12.89% slower** on 10/14; threshold exactly matches QSA union min KV 32768 with same union path/shape logs. Source of degradation **unknown**, QSA path and GPU/power state prioritized (correlation, NOT attribution). Resource medians GPU Local ~83.1GiB equal, disk and hard pages mostly zero; 10/14 system RAM ~+2.1GiB, CPU somewhat higher, no clock/thermal counters. Defender engine updated 10/14 11:52; Windows Update downloaded at 21:37 **between** two already-slow same-day runs. Microsoft Remote Display Adapter and PowerShell versions changed 26100.9549→26100.9711 while AMD GPU driver remains identical. **NEXT:** complete pending Windows Update, controlled reboot and same old-binary 64k/128k retest; capture GPU clocks/hotspot/power; if persistent, targeted 32k/64k QSA min-KV or RGP A/B. No code changes or conclusive Windows Update attribution. [Full native CSV and event comparison](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#forensic-1011-vs-1014-windows-update--128k-resources--2026-10-14-2200-jst).

> **UPDATE 2026-10-14 21:45: ARCHIVED b11560 RECHECK REPRODUCES ~305 tok/s.** Same exact b11560 SHA as 10/11 now measures 305.18 PP /23.68 TG at 128k MTP OFF; 10/14 b11618 measures 305.98/23.74. Thus the b11560 10/11 OFF PP335.455 to 10/14 PP305.18 (~-9.03%) is cross-date/environmental in evidence, not an isolated b11618 regression. Same-day GPU Local median 83.15GiB both, paging/disk not sustained; clocks/temp/power unavailable. **NEXT: obtain 2026-10-11 `r5-mtp-vulkan-64k128k-abba-20261011-171132.zip`, 128k OFF A1 17:28:06 and A2 17:51:47, compare resource/conditions/drivers and decide whether external GPU clock/power logs are needed.** See [Stage-B implementation report](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#b11560-same-day-rerun-and-resource-csv-triage--2026-10-14-2145-jst).

> **LATEST 2026-10-14: b11618 128K MTP-OFF CONTROL COMPLETE.** Same-build Stage B ON PP 296.63 vs OFF 305.98 tok/s (−3.06%, +13.01s), TG 23.79 vs 23.74 practically equal. Historical b11560 OFF 335.455 vs new OFF 305.98 (−8.79%) is cross-build/time drift, not yet a causal source regression. NEXT: current-day archived b11560 OFF rerun to isolate source/runtime from environment before more optimizations. **Previous Stage-B 64k +3.63% and 128k +6.68% improvements are ON-vs-ON crop-toggle effects, not ON-vs-MTP-OFF.** Qwen4Exp Draft zero-output branch now uses a dedicated K/V cache-write helper without calling the common FA builder; correct src[1]-based K/V root diagnostic; 12 static Python source tests and new R5MtpKvOnlyVulkan diagnostic/ABBA jobs. **b11618 diagnostic: OFF graph 133 nodes/FA1, ON 31 nodes/FA0 with K/V classified 1/1; exit0, output bytes and MTP acceptance 17/27 match.** Baseline A K/V name classifier is still zero despite SET_ROWS=2. **64k diagnostics-OFF ABBA: A PP avg 314.135 vs B 325.535 tok/s (+3.629%); A TG avg 28.21 vs B 28.88 (+2.375%); total runtime -7.313s. All four 61,789-input / 512-output runs exit0, bytes and Draft acceptance 295/430 identical. Longest 49–61k segment reduces PP time 4.57%, consistent with FA elimination. NEXT: 128k scaling and/or RGP dispatch check; prior to any merge, verify numerical Draft KV parity.** Previous Stage-A ABBA +0.53% is not evidence of Stage-B performance. [Validation and source review](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#stage-b-implementation-dense-draft-kv-only-no-fa-graph-root--2026-10-14).

> **2026-10-14 MTP PP Stage-A: SHORT + 64K FUNCTIONAL PASS / FA CROP INCOMPLETE:** On isolated [`investigation/r5-mtp-pp-kv-crop-stage1-20261014`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-kv-crop-stage1-20261014), an opt-in `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` branch keeps Q/K/V and cache-copy graph roots, but omits the full output-dependent Draft FA/HC/FFN path when no output rows are requested. It explicitly handles an unallocated Hybrid attention mask. **Stage-A active catch-up diagnostic BUILT and run on Vulkan b11608:** `LLAMA_MTP_KV_CROP_DIAG=1`, first 8 real Draft zero-output ubatches, graph node and K/V root counts; separate `stage1-diag-short` BuildKey. A/B diagnostic confirms crop_applied=1, nodes 133→44 and MoE/FFN reduction, but Flash Attention remains 1 node due to unconditional expansion inside `build_attn_mha()`. Two SET_ROWS nodes persist; K/V name-based subcounts are broken. Optimization also applies to generation-time n_tokens=3 Draft catch-ups, revising the prior TG-warmup-only assumption. NEXT = Qwen4Exp-specific cache-only K/V path avoiding FA builder, with stronger K/V graph root checks; retest short graph before 64k/128k. [Validation gate](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#stage-a-active-catch-up-graph-diagnostic--2026-10-14).

**Native Vulkan b11597 short A/B and 64k ABBA PASS functionally; 64k output/acceptance identical, mean Stage-A ON/OFF PP +0.53% (~1.04s/61,789 tokens). No depth-growing gain; 2 repetitions/arm insufficient and zero-output graph crop is confirmed but incomplete (FA still present). NEXT: bypass FA in the Stage-A Draft path, then verify K/V write roots and run a diagnostics-OFF ABBA; defer 128k/ROCm until full graph omission is proven.** Research report, environment flag and test matrix: [Stage-A implementation and stop gates](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md). Previous b11587 RGP proves Draft FA is costly (~140ms/1024 at KV≈51k), **not** that this prototype is correct or fast. Do not refresh upstream, merge source to stable, or mix DENSE/NOOP; Vision awaits newer input/state ABI. [Upstream/Unsloth review](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md#pre-implementation-upstream-and-unsloth-update-review--2026-10-14).


**Research documentation source of truth (2026-10-13):** this copy on pinned r5 stable records completed experiment results; neither DENSE-001 nor NOOP-001 code is integrated into stable source. See [PATCHES.md](PATCHES.md) for branch-specific status and [README](README.md) for synchronization rules.

## Current execution order — 2026-10-13 (supersedes earlier NEXT sections)

1. **MTP-NOOP-001 Vulkan VALIDATED on isolated r5 branch:** native policy/model/rollback and short real-MTP gates passed on Evo-X2; normal same-binary A1/B1/B2/A2 64k/128k/256k **12/12 OK**, MTP ON/DENSE ON throughout, equal text and acceptance per depth. NOOP TG OFF→ON **31.385→32.045 (+2.10%)**, **26.960→28.775 (+6.73%)**, **21.075→24.110 (+14.40%)** tok/s. PP essentially unchanged, PP+TG total impact tiny. Source/runtime `b84d18870` / `b11577`. Details: [r5 NOOP Vulkan validation](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md).
2. **MTP-NOOP-001 ROCm measurement CLOSED (qualified):** Native/short gates PASS; normal same-binary A1/B1/B2/A2 64k/128k/256k **12/12 OK**, TG OFF→ON +4.55%/+6.42%/+8.08% (observational). Unlike Vulkan, output and MTP draft acceptance differ even for identical-condition repeats at all three depths. Do not infer deterministic equivalence or exact causal speedup. See [full ROCm validation](R5-MTP-NOOP-ROCM-VALIDATION-2026-10-12.md).
3. **NOW: MTP ON PP candidate evaluation after completed Vulkan attribution** — run all performance matrices with authoritative start/finish **P-MODE=Performance** logging and ADLX enabled; treat mismatches as environment warnings before source attribution. (`investigation/r5-mtp-pp-trace-20261013`; compatibility-only source, DENSE/NOOP isolated). Verified b11569 64k/128k phase traces and b11587 Draft RGP (FA GPU ~140ms/1024 tokens at KV~51k) are **complete**. [2026-10-14 source review](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md) recommends **Draft prompt KV-only graph feasibility P0**, Target NextN/final hidden handoff and Vulkan CM1 FA tuning P1. **NEXT: bounded ROCm mechanism comparison, then correctness-gated source prototype if justified.** Preserve r2 MTP-QSA NO PORT, stable source untouched and DENSE/NOOP in separate TG branches.
4. **No stable merge/refresh or release promotion.** Preserve `r5/upstream-refresh-20261009`, validated DENSE branch and NOOP candidate binaries. Earlier roadmap sections below are historical and do not override this sequence.


**PP source-review checkpoint 2026-10-14 (read-only):** [Vulkan candidate/feasibility audit](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md) complete after Draft RGP FA timings. Evidence: Qwen4Exp MTP is a single block, `common_speculative_impl_draft_mtp::process()` feeds **all** Target NextN rows to Draft with output=false, but its carry-over `pending_h` and `verify_h` come from **Target** rather than Draft logits/hidden. Draft's dense graph builds Q/K/V→FA→FFN→logits for every prompt ubatch, while `llm_graph_context::build_attn()` explicitly registers **K/V cache write nodes** before FA. Thus **P0 *investigate* a Draft prompt-only KV-write graph** that preserves K/V and bypasses needless Q/FA/post-attn outputs (only if all hidden/rollback dependencies prove correct); separate full-MTP generation graph required. **P1** Target unmasked NextN last-layer all-row HC/MoE and D2H/H2D handoff (GPU share unmeasured), **P1** Vulkan CM1 tuning (actual Br16/Bc64, no simple safe flag), **P2** Draft eh_proj Q8_0 matmul (~56.5ms at KV~51k) and ubatch. RGP FA-main ~139.9ms/1024 at 50–51k; mask opt ~1.1ms, do not pursue first. Keep r2 MTP-QSA / ratio-metadata no-port and DENSE/NOOP isolation. **NEXT: targeted ROCm architectural-path comparison** to distinguish cross-backend graph opportunity vs Vulkan-only FA, followed by optional opt-in new-graph prototype with K/V, logits, acceptance and rollback correctness gates; no implementation in this review. No repeat PP/RGP needed now.

## MTP ON PP investigation and r2 MTP-QSA reconsideration — 2026-10-13

The [r5 MTP ON PP investigation plan](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md) is now the authoritative step-by-step plan for this workstream. Existing **same-binary r5 b11560** MTP OFF→ON PP results: Vulkan **64k 361.520→333.995 tok/s (−7.61%, +14.084s)**; **128k 335.455→303.965 (−9.39%, +38.991s)**. ROCm **64k 392.295→365.390 (−6.86%, +11.600s)**; **128k 294.710→274.465 (−6.87%, +31.601s)**. These values are the **server slot prompt-wall timer**, which can include draft processing between target prompt batches and must not be equated directly with `llama_context::t_p_eval_us`. The final prompt batch boundary may classify some speculative work differently; profile explicit boundaries.

**Decision on historical r2 MTP-QSA:** keep **NO PP BENEFIT / NO PORT**. Recovered r2 single-pair dense→QSA PP is **259.23→259.12 (64k first design), 255.73→252.97 (64k prefill-only), 209.44→207.93 (128k prefill-only)**; no improvement. The old profiler memo suggests a smaller FA time was offset by indexer/top-k/gather and higher buffers/peak memory, but those memo-level times are not new raw-log proof. r5 has a conditional native QSA path for positive-ratio MTP; the tested Unsloth ratio-zero Q8_0 sidecar stays dense. Therefore do not merge or copy `test/mtp-qsa-prototype`, whose inferred ratio=4 is a semantic change. Reconsider a **new** r5-native draft-attention approach only if stage timing shows it dominates PP **and** correctness/acceptance checks justify the model behavior.

**Next gate:** isolated opt-in aggregate timing on the compatibility-only ancestor (`f8d24494f`) for target process, NextN hidden getter/synchronization/host copy, draft input preparation and `llama_process(ctx_dft)`, with coarse KV bins and no per-ubatch logging. Normal timing and forced synchronization/profiler timing remain separate. **No stable source code, TG patch merge, or upstream refresh** as part of this gate. The DENSE/NOOP TG branches and tested binaries remain frozen.

### 2026-10-13 independent DeepSeek review: adopted diagnostics, gated KV-only candidate

The user supplied an independent review based on a **pre-documentation-update** snapshot. Reconciliation and source-specific limitations are now in the [MTP PP plan — DeepSeek review triage](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md#independent-deepseek-review-triage--2026-10-13-incorporated-with-qualifications).

- **Add to the FIRST diagnostic gate:** chart draft catch-up **duration/ubatch versus cumulative KV**, including token count and hidden getter/sync separation; independently confirm **draft** f16 FA dispatch (a target union log is not draft proof); watch GPU memory budget/paging using normal r5 resource logs.
- **Retain the draft KV-only / early attention-query pruning hypothesis**, but **do not implement yet**: the r5 `graph_mtp` final output-row mask is after FA/FFN, so output selection alone cannot eliminate attention work. Prove same-block pre-attention KV independence, required tail output rows, target hidden input coverage and draft KV state continuity, then test output/acceptance/rollback before any benchmark claim.
- **Do not port r4 `LLAMA_MTP_DIAG=wall` or use inherited `qwen38-r4-mtp-diagnostics.psd1` as-is**. The matrix/script exists in r5 docs/tooling, but the r4 `ggml-mtp-diag.h`/source instrumentation is absent and its BuildKey/128k/256k settings are not this experiment's controls. Reuse only narrowly applicable instrumentation design and r5-specific build artifacts.
- **Do not declare dense attention already proven as the cause.** Three-point r4 quadratic fitting is a descriptive screen, not a measured “82%/68% GPU time” breakdown. r5 already has working b11560 ABBA and remains pinned; source refresh/MTP-OFF repeat is not a prerequisite.
- **Do not treat MTP GGUF ratio>0 reconversion as a safe speed fix** absent evidence the head's *trained* attention definition expects it. The r2 MTP-QSA negative outcome stands.

**Implementation checkpoint 2026-10-13 (source only):** The isolated [PP trace branch](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-trace-20261013) now contains opt-in server target and MTP draft phase wall tracing with explicit prompt/generation tagging, per-KV bins and optional per-ubatch details; a 64k Vulkan OFF/ON diagnostic matrix, Python summarizer and parser regression tests are committed at `4b136c5bf48e14dc162f96b7457379684287cd20`. **Windows compile, unit-test execution, short smoke, real model 64k/128k results and exact draft GPU FA attribution are ALL PENDING.** Source was branched from ratio-zero-guard-only `f8d24494f`; no DENSE/NOOP merge or r2 MTP-QSA port. [Experiment-branch build and analysis instructions](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-TRACE-IMPLEMENTATION-2026-10-13.md). Full design remains [here](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md). Run parser/unit tests and Windows smoke first, **then** 64k; do not treat trace-mode wall figures as performance A/B.

**First Windows Vulkan PP trace result — 2026-10-13:** Five Windows Python unit tests PASS, Vulkan b11569/`4b136c5bf` verified build, 4/4 native short/64k OFF/ON runs OK (one diagnostic pair each). At 64k (61,789 tokens) PP OFF171.12167s / ON181.30886s, +10.18719s. All 31 prompt batch lines and stage totals check out. ON has server target wall94.147s, synchronizing NextN getter78.439s (largely **deferred target GPU wait, not host copy**), draft llama_process call6.756s, verify hidden-row getter/copy1.923s. Draft-call wall increases with KV, but the measured total PP penalty is **larger in first 32k (+8.23s) than next 29k (+1.94s)**. Distinguish GPU kernel time and confirm draft FA before calling attention the dominant cause. ON also shows persistent sampled system-wide page/disk reads, **unattributed** to process paging. **NEXT:** verify reproducibility/IO and native draft FA, then 128k Vulkan traced and 64k ROCm as justified. Do not compare trace PP speeds as a new faster source. Canonical [64k validation report](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md); unchanged [plan](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md). No stable inference source change.

**64k repeat diagnostic — 2026-10-13 21:50–21:59 JST:** identical b11569 source/binary/model/input; 2/2 OFF/ON runs OK; outputs identical **within** OFF and **within** ON across sessions, ON draft acceptance 295/430 both. PP first pair OFF/ON **171.122/181.309s** (+10.187s); repeat **171.731/186.210s** (+14.478s). Repeat ON draft `llama_process` CPU wall **6.756→6.584s**, hidden getter sync-inclusive **78.439→81.119s**. Earlier **system-wide** sustained disk/page reads in ON's 50–190s window **did not recur** (disk-read median 14.84→0.00 MiB/s; page-read median 525→0/s), even as the PP ON penalty increased. No proof that earlier reads were a specific process, pagefile, Defender or Windows Update; **do not prioritize memory/paging tweaks on this evidence**. 64k repeatability check closed; **NEXT 128k Vulkan same b11569 OFF/ON trace**, then draft f16 FA GPU dispatch attribution. [Updated source-grounded report](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md#repeat-64k-vulkan-offon-diagnostic--2026-10-13-21502159-jst). Source branch untouched; retain untraced b11560 ABBA as independent speed control.

**128k Vulkan PP phase attribution gate COMPLETE — 2026-10-13 22:19–22:35 JST:** Same verified b11569 source/binary as 64k diagnostic; 126,253 prompt tokens, **62 prompt batches**, native OFF/ON **2/2 OK**. OFF 382.966s PP, ON 420.908s (**+37.942s**), ON MTP acceptance 295/429; prior b11560 *untraced* 128k ABBA penalty +38.991s separately corroborates magnitude, **not stage attribution**. ON CPU-wall: target wrapper220.603s, sync-inclusive NextN hidden getter178.296s, draft `llama_process`20.023s, hidden verify/copy1.914s. CPU-wall target+getter envelope difference vs OFF is **~+15.975s**, while draft-call stage is +20.023s: cannot claim the whole ~38s is draft dense FA without actual GPU operator timings. Draft full-batch CPU wall grows with KV (r≈0.998 excluding initial/last short), but **last 1325-token batch moves GPU completion wait into target explicit sync**, so it must be separated. Depth-bin penalties +8.612/+8.217/+21.091s; 128k resources ON GPU Local max88.674GiB, system committed100.757GiB; normal-time disk/page-read medians zero in both ON/OFF. **NEXT: instrument or externally profile target/draft f16 FA kernel/NextN graph work without artificial sync; consider 64k ROCm independent control.** No need for another full 128k PP-only repeat before GPU-path investigation. Full [128k source-grounded report](R5-MTP-PP-TRACE-VULKAN-128K-2026-10-13.md); [64k + repeat](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md); keep experimental trace source outside r5 stable.

**Vulkan PP source-audit gate — 2026-10-13 (no source edits):** [source/RGP plan](R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md) establishes (1) MTP unmasked NextN disables target pre-hidden early output-row crop, requiring full-row final HC/FFN/MoE; (2) ratio-zero MTP draft is dense FA, distinct from target QSA union, actual coopmat/scalar GPU path unverified; (3) all-row f32 hidden readback is attempted via pinned host buffer with possible synchronous staging fallback, path unconfirmed. 128k CPU-wall target+getter envelope residual +~15.975s is **not final-MoE GPU time**; draft-call +20.023s is **not measured FA GPU time**. **RGP ON/OFF matched-depth 64k CAPTURE COMPLETE (2026-10-14):** same top 13 pipeline hashes with near-identical GPU time ~300.46ms/300.47ms in separate 512-dispatch samples at KV~51–53k, although whole native PP OFF169.664s vs ON183.405s (+13.741s). Current samples primarily show **shared target work**; MTP incremental kernels not yet isolated. **2026-10-14: LABEL SOURCE b11577 BUILT / SHORT MTP ON GATE PASS; RGP CAPTURE PENDING.** Experimental `GGML_VK_MTP_PP_RGP_MARKERS=1` in [source/plan](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-RGP-MARKERS-IMPLEMENTATION-2026-10-14.md) builds on the prior llama-bench validated `VK_EXT_debug_utils` debug-region technique, adding QSA/dense-FA shader/KV/query labels, best-effort target/draft graph role and matmul markers. New standalone RGP PSD1 + five static source tests (user reports PASS); native Windows Vulkan build b11577 `34ebb6933` and short 163 prompt / 32 generation MTP ON **PASS** (runtime artifact Verified, exit0, 17/27 accepted, trace target/draft sums exact), `VK_EXT_debug_utils` marker enabled log observed. **64k native b11577 ON RGP label visibility PASSED (2026-10-14):** Dispatch range start512/count256 screenshot shows real `EVOX2_MTP_MATMUL role=target` regions nested under GPU matmul events; early capture at ~+40.25s overlaps model setup, before steady PP, so draft role/FA `KV=` is **NOT YET verified**. Native PP 61,789 tokens 331.42 tok/s / 186.439s, MTP acceptance295/430, build/runtime Verified. **RGP 50,000/256 CAPTURE PASSED (2026-10-14 01:45):** GPU compute Event timing displays `EVOX2_MTP_MAIN role=target shader=flash_attn_f32_f16_aligned_cm1` under `FLASH_ATTN_EXT`, target indexed MoE `ffn_moe_gate/up/down-19` with RGP shader names and ~6ms kernels. Same verified b11577, same old Q8_0, full prompt completed. RGP timestamp relative to native progress places slice near 12–14k KV (below 32k union threshold); truncated screenshot hides exact label `KV=`. **Draft FA not yet observed/identified**. **180000/256 RGP CAPTURE ALSO COMPLETED**: b11577 MTP ON at +181.721s after launch near 41–43k KV, screenshot shows target QSA `indexer_k_raw-43`; user GUI found neither `role=draft` nor `role=unknown` in this 256-dispatch slice. Native log confirms all 31 draft calls, late draft CPU-call wall ~4.001s, so absence from sampling ≠ no draft GPU work. **Vulkan dispatch ordinal b11587 built; short MTP ON native role identification PASSED (2026-10-14 09:29)** [calibration design](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md): `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1` counts actual `ggml_vk_dispatch_pipeline`'s `vkCmdDispatch` across target+draft, logs per-graph `[begin,end)`, label role and name. New unique build key and PSD1, four static source-contract checks, no changes to FA/QSA/spec scheduling. Native short Verified/exit0, 163 prompt /32 generated, 17/27 MTP accepted. Log contains 60 contiguous intervals (16 target and **44 draft**, 0 unknown), total 64,653 dispatch calls; real prompt target [0,3767) immediately followed by draft [3767,3846). Existing phase trace bins/detail match. **64k native b11587 ordinal calibration PASSED (2026-10-14 09:47):** 986 continuous graph role/ordinal records, no unknown (278 Target/708 Draft including TG); PP prefill [3846,268204) is 61 Target+61 Draft Vulkan graphs, Target260330 and Draft4028 `vkCmdDispatch` (Draft 1.524% of PP dispatch count, **not GPU time**). Verified b11587 runtime, 61,789 prompt, PP186.485s/331.34 tps, acceptance295/430. At 51200 prompt KV: Target[208279,217403), Draft[217403,217535), next Target[217535,226659). Previous RGP start180000/256 fell in a Target graph, ending 123 ordinals before Draft began at 180379. **DRAFT GPU CAPTURE SUCCESS (2026-10-14 10:59):** proposed b11587 start217300/count512 RGP **visibly includes** `EVOX2_MTP_GRAPH role=draft` and `EVOX2_MTP_MAIN role=draft shader=flash_attn_f32_f16_aligned_cm1`; one draft graph interval232.580ms, nested `mtp_eh_proj-48` 57.138ms and underlying `matmul_q8_0_q8_1`56.497ms. Target/draft marker and ordinal strategy validated! **Draft GPU FA measurement GATE COMPLETE:** new screenshot shows `KV=50176`/`51200`, `N=1024`, `Br=16/Bc=64`, Draft shader `flash_attn_f32_f16_aligned_cm1` dispatched `(64,24,1)`, main GPU event **139.918/139.159ms**, mask optimization **1.094/1.159ms**, per 1024-token microbatch. Two FA mains sum279.077ms. Earlier unfiltered Draft graph232.580ms contains `mtp_eh_proj`57.138ms; filtered FA tree shows141.013ms first event, **not the full graph duration**. Local FA contributes heavily, but 128k ON PP overhead also has Target+NextN wait envelope~15.975s, so do NOT equate FA milliseconds to entire slowdown. **NEXT: source-only correctness and optimization feasibility review, optional unfiltered stage accounting screenshot; no rebuild/RGP required immediately.** No source changes required. Avoid further arbitrary range guesses. Preserve b11569 legacy capture and r5 stable source; avoid another blind whole-64k capture. RGP should focus draft FA pipeline, target final layer, transfer/barriers; reconcile with existing phase trace. Avoid `GGML_VK_PERF_LOGGER` as it forces GPU fences and perturbs wall clocks. No need yet for new 128k PP A/B or performance patch.

## Current measurement closure and next research — 2026-10-12 (supersedes the 2026-10-11 active queue)

- **MTP-DENSE-001 isolated TG validation COMPLETE:** b11566, same-binary MTP ON DENSE OFF/ON ABBA at 64k/128k/256k, both Vulkan and ROCm **24/24** successful runs. TG gains Vulkan **+6.81%, +15.52%, +36.22%**; ROCm **+7.72%, +17.42%, +23.48%**. Vulkan outputs/acceptance are identical in each four-run matrix; ROCm temp0 outputs/acceptance vary even within same-setting repeats. Detailed hashes, controls and caveats: [r5 DENSE-001 validation](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md).
- **NEXT: MTP-NOOP-001 bounded r4→r5 source review, then opt-in candidate only if still applicable.** Use a new investigation branch from validated DENSE source, not the pinned stable r5. When testing MTP ON, fix `LLAMA_MTP_SKIP_DENSE_INDEXER=1` in both arms; only change no-op invalidation switch. Keep the earlier r4 default-OFF target-only policy as the reference and redo native state/rollback and same-binary TG A/B. Never assume r4's +12.99% Vulkan 256k carries over.
- **THEN: PP cost of MTP ON** (64k/128k prompt overhead observed); revisit ROCm generation nondeterminism separately, sooner if it prevents a correctness gate. 256k MTP OFF is intentionally deferred; missing 64k/128k MTP OFF values are from a different b11560 build and must be labeled.
- **NO RELEASE PROMOTION:** This closes a measurement workstream, not AgentionAI compressed-ratio support, combined-patch correctness, first integrated snapshot or external correctness review. Preserve original runtime binaries and raw ZIPs.


## User decision: focus MTP ON TG and future Agention FP4/MTP compatibility — 2026-10-11 evening

**This section supersedes older "current priority" prose below, which is retained as an historical sequence.** The paired r2 b10813 64k/128k real-input Vulkan ABBA is **complete 8/8**. Within r2, MTP ON TG benefit **+10.99% / +16.40%** versus r5 Vulkan **+10.52% / −2.75%**. See [matched r2/r5 TG review](R5-MTP-TG-R2-R5-RECHECK-2026-10-11.md). Historical r2 b10811 measurements should not be substituted for this newer b10813 binary.

Research scope from now:
- **ACTIVE:** resolve the extra/depth-dependent **MTP ON TG** cost; first isolate r4 **MTP-DENSE-001** (dense draft indexer omission) on r5 at 128k, then **MTP-NOOP-001** (target no-op invalidation) independently, with correctness and one-change-only ABBA. If necessary, investigate r2 vs r5 short-query Vulkan union verification. Extend to 256k only when safe.
- **PARKED:** MTP ON **PP** overhead since r2. Record PP as a control/telemetry metric in TG A/B, but **do not optimize PP yet**.
- **CLOSED FOR THIS PHASE:** r3 **MTP OFF TG** pooled-summary full-context recomputation was addressed by COMMON-004, and the functional equivalent is included upstream in r4/r5. **Do not reopen** absent a new strong regression or correctness issue. r3 COMMON-005 remains a separate later non-MTP deep-decode topic.
- **INTEGRATION REQUIREMENT, NOT CURRENT IMPLEMENTATION:** include AgentionAI ROCmFP4-FAST main **and matching ROCmFP4-FAST MTP draft** as quality-comparison choices in the first integrated build. [Compatibility review](R5-MTP-AGENTION-FP4-INTERACTION-2026-10-11.md) finds no necessary structural conflict **if** draft indexer omission applies only to **ratio0** and target no-op suppression only to verified no-change state; the actual Agention MTP GGUF ratio/tensor names, custom FP4 loaders and backend kernels are **unverified**. Do not mix new FP4 format port with the current MTP TG A/B.
- Historical r2 predates build manifests: **`MissingManifest` / `build-unknown` on the r5 runner is a metadata limitation**, not a runtime failure. Identify with r2 executable SHA and embedded b10813 version; do not retrofit an invented manifest.

No inference source change or upstream refresh is implied by this decision.


## Planned follow-on program — 2026-10-11 (research first; no release yet)

The user has chosen the following **order of intentions**, not fixed deadlines or a requirement to interrupt the active research branch:

1. **Continue bounded r5 ROCm/HIP Flash Attention source/runtime research now.** Preserve the pinned upstream and validated baseline. Decide after this gate whether to study COMMON-005 ROCm decode or another narrowly justified question. No forced upstream refresh.
2. **At a convenient future research boundary, prepare the first integrated snapshot.** Re-evaluate the previously verified beneficial patches on a deliberately selected newer upstream, with COMMON-001 mandatory for PLE16 comparisons. **Add ROCmFP4 compatibility work to the first integration preparation**, not just a passive backlog item: audit the AgentionAI ROCmFP4-FAST GGUF format, COMMON-003 loader/core support and actual Windows HIP kernels; separately decide whether VULKAN-001 is needed. Validate load, short inference and correctness before any optimization claims; then test the combined source.
3. **Only after an integrated snapshot has passed and been tagged**, try [Niko1221/Strata](https://github.com/Niko1221/Strata) as a separate experimental runtime/engine. Do not fold Strata into the llama.cpp integration acceptance test or claim it has been tested on Windows Evo-X2 yet.
4. **Later research: quantization-dependent answer accuracy of Qwen3.8-Flash-Next.** Reuse the long-context question/prompt fixtures created for the earlier **Qwen3.5** testing, but keep the prompt/data provenance separate from the **Qwen3.8-Flash-Next** model under comparison. Compare quantizations of the **same Qwen3.8-Flash-Next model**, scoring predefined answer keys; hold model revision, prompt tokens/slices, context, decoding parameters and engine fixed where possible. If comparing Strata/llama.cpp, report engine as a distinct factor, not quantization alone. No accuracy run or result has been produced for this question yet.

**Release gate:** ROCmFP4 is an intended *first-snapshot prerequisite* rather than an already-verified patch. If its build/correctness cannot be completed in the integration session, keep the snapshot **candidate/incomplete** or explicitly re-decide scope; do not label an FP4-less build as having met this plan. The first integrated branch, tag, binary and tests are **not created yet**. Reference [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md) and [PATCHES.md](PATCHES.md).

## r2 MTP raw-log recovery and r5 first smoke — 2026-10-11

[**R2-MTP-LOG-RECOVERY-2026-10-11.md**](R2-MTP-LOG-RECOVERY-2026-10-11.md) reconciles the 2026-09-18 memo with 30 CSV + 30 historical Windows/Vulkan r2 log files. Recoverable 64k MTP OFF/ON: **PP 273.34/262.28**, **TG 19.60/22.52 tok/s**, acceptance **294/402** (the 64k runs had `GGML_VK_PERF_LOGGER=1`); 128k **PP 220.57/209.76**, **TG 21.61/24.31**, acceptance **264/366** (no PERF_LOGGER). All were single-run and different output lengths; do not claim a source-only r5 regression from absolute speeds. MTP-QSA prototype logs, 99 partial-reject checkpoint-smoke events and the 128k threshold/ops count are independently documented; **the final MTP-QSA did not improve PP**, and its extra memory/profile numbers are memo-only without raw profiler CSVs. **Next action:** test existing r5 + self-contained Unsloth Q8_0 sidecar *without source changes*, first short OFF/ON smoke; current r5 graph still lacks the r4 ratio-zero input guard, so catch expected buffer assertion rather than treating it as a proven runtime failure. If it fails, only minimal isolated compatibility fix; then fixed-length 32k/64k comparisons before revisiting performance patches. See [r4 MTP evidence](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md).

## Research/refresh policy update — 2026-10-11

The goal is **personal optimization research and repeatable experiments**, not continually delivering the fastest current end-user build. The pinned r5 branch and the technical ROCm FA investigation queue below remain valid; upstream changes alone do **not** mandate an immediate r6 refresh.

- **New upstream/research branch:** take a clean baseline and **always restore COMMON-001** before using the historic PLE16 benchmark model. Port other patches only when necessary for the selected hypothesis. The branch can stay pinned while the experiment continues.
- **Integration lane (future):** at a natural stopping point, roughly every 4–6 weeks if convenient, choose a reasonably current upstream SHA and **evaluate all previously verified beneficial patches**. Apply only those still required and passing in combination. No new optimization investigation is required during that session. An integration attempt may defer a patch instead of blocking research indefinitely.
- **No integrated snapshot exists yet.** First integrated branch/tag and combined Vulkan/ROCm performance results are **planned**, not created/verified. See [INTEGRATION-POLICY.md](INTEGRATION-POLICY.md) and [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md).
- **Records:** [PATCHES.md](PATCHES.md) now indexes source-presence, validation and upstream replacement by r3/r4/r5, and holds not-yet-implemented ROCm/upstream candidates. Historical implementation/measurement sections remain intact. Upstream correctness fixes may be evaluated as isolated cherry-picks without moving the research pin; merged performance fixes wait until relevant to the current experiment or the next integration checkpoint.
- **Current next research question is unchanged:** bounded ROCm/HIP FA path attribution, with #30103 applicability review and later independent COMMON-005 decode re-evaluation. This is an exploration order, **not** a deadline or prerequisite for an integrated build.

The dated “Active priority decision” section below was written **before** this workflow distinction. Read it as the current technical research handoff only, not an instruction to refresh upstream or port every successful historical patch.


Original baseline snapshot: 2026-10-09 (r5 clean Vulkan/ROCm baseline verified through 256k; r4 clean 64k replayed on Windows 26H2; Vulkan MoE tile selection UPSTREAMED / RETIRE). Active execution priorities last reviewed 2026-10-11; the new dated section below supersedes older future-work lists.

This document records the current execution order for the Evo-X2 optimization
work. Patch IDs remain stable even when implementation priority changes.

## Active priority decision — 2026-10-11

**Decision:** return from the deep Vulkan OFF FA investigation to a breadth-first project priority review. **First perform a bounded ROCm/HIP FA runtime diagnosis; then make a fresh r5 MTP decision.** Do not start a new Vulkan shader optimization merely to resolve the remaining `non-skippable-tile ratio ≈2.58× vs single-kernel GPU-time ratio ≈4.1×`. Do not silently move the r5 pinned upstream or merge experimental diagnostics into the stable branch.

The evidence and public upstream status checks behind this decision are in [PERFORMANCE-RESEARCH-LOG.md — 2026-10-11](PERFORMANCE-RESEARCH-LOG.md) and the archived [Vulkan FA diagnosis](R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md). The earlier 2026-10-09 refresh sequence, old `NEXT` text in historical sections and pending states in earlier checkpoint descriptions are preserved as *historical*, not a competing current plan.

### Why the order changed

- r5 now has **validated real-input `llama-bench`**, grouped QSA union ON/OFF and statistics on Windows Vulkan, with 64k/128k real-text controls; 64k/128k cross-backend ROCm real-input PP collection is complete. Earlier real/random input mismatch no longer blocks optimization.
- At 64k Vulkan union ON benefits **all seven** evaluated inputs and gains differ by content; 128k ON is **+46.8% to +74.9%** on the six tested inputs. The union path is a validated local feature, not an untested candidate. At 128k Vulkan union ON outperformed ROCm on **four of six** inputs, so “ROCm always faster” is false.
- The unusual Vulkan **union OFF** literature/code PP difference has been traced to `FLASH_ATTN_EXT` in whole-run GPU logger timings and to a ~4.1× matched FA-main kernel-time difference at `KV=49152`. A separate mask metadata histogram shows **35.68%** versus **75.03%** completely skip-eligible `16×64` tiles in literature versus code, across 64 matching query-tile rows. This strongly implicates mask-tile occupancy; the residual nonlinear timing relationship is **not itself a reason to spend more time profiling immediately**.
- ROCm instead showed relatively small per-input PP spread (**5.5% at 64k, 4.1% at 128k**) and different depth scaling. We have **not measured its actual selected HIP FA kernel, suffix mask scan, Stream-K choice or comparable FA GPU time**, so its execution path is a more informative, tractable next unknown than finer-grained Vulkan tile counting.
- Practical user-facing opportunities outside FA remain: **r5 MTP total-latency/PP cost**, **ROCm 128–256k PP depth scaling**, and **AgentionAI ROCmFP4-FAST support**. These should not disappear from view because profiling is interesting.

### Re-ranked queue and decision gates

| Order | Workstream and classification | Immediate action / stop or promotion gate |
| --- | --- | --- |
| **P0 (next)** | **ROCm/HIP Flash Attention runtime path** — `INVESTIGATE`, **bounded** | On stable r5 sources, trace the selected `ggml-hip`/`ggml-cuda` FA kernel for qwen4exp; confirm whether conditional `scan_mask`/`flash_attn_mask_to_KV_max` and FA Stream-K actually apply to **Radeon 8060S** at 64k. Inventory Windows HIP profiler support **before** implementing any GPU instrumentation. If practical, compare the **same Japanese literature vs llama.cpp C/C++** at `-c 65536 -p 61789 -ub 1024` and relevant late-KV/layer shape, reporting FA op-time separately from PP. Stop once kernel path, major FA contribution and likely actionable difference are known; otherwise write down limitations and move on. |
| **P1 (high practical impact)** | **r5 upstream-native MTP correctness and end-to-end performance** — `INVESTIGATE` | Confirm the existing Unsloth MTP draft loads on current r5, validate short/rollback/output, then short and long MTP ON/OFF with both target+draft prefill latency, TG/acceptance and **fresh-prompt total latency**. The r4 dense-draft indexer and target QSA no-op candidates were **not** wholesale ported; retest relevance rather than porting by habit. Investigate PP overhead before developing additional speculative-kernel complexity. |
| **P1–P2** | **ROCm 128k/256k PP scaling** — `INVESTIGATE` | Reuse the P0 FA findings; break down FA versus GDN, MoE, CONCAT, copies and scheduling on comparable 64k/128k/256k workloads. The prior 64k→128k decrease is about **25% across six corpora**, but input slice also changes; not proof of a single attention bottleneck. Prior 64k→256k PP fall seen in r4 CLI and bench stays a follow-up, not a duplicate task. |
| **P1 feature-dependent / P2 otherwise** | **COMMON-003 / VULKAN-001 — AgentionAI ROCmFP4-FAST** — `LOCAL-CANDIDATE` | Audit native current/pinned model type, GGUF reader and Vulkan/ROCm kernels; first target *model load and correct execution*. Raise priority to P1 if comparative use of the AgentionAI FP4 model is immediately required. Keep format compatibility separate from speed claims and from the Vulkan/RGP FA changes. |
| **P2 / defer** | **Vulkan FA refinements** — `INVESTIGATE only on trigger` | Keep old RGP markers and one-shot mask histogram **on the investigation branch**; stable r5 retains only the report. Potential ROCm-style suffix cutoff, FA Split-K, tile placement/wave occupancy tests only after HIP profiling or a clear actionable benefit. Do not equate [upstream #30280](https://github.com/ggml-org/llama.cpp/pull/30280) **MUL_MAT Split-K** with FA Split-K. |
| **WATCH-UPSTREAM** | **GDN/CONCAT/recurrent/MTP and other engine updates** | Monitor [#29353](https://github.com/ggml-org/llama.cpp/pull/29353), [#28303](https://github.com/ggml-org/llama.cpp/pull/28303), [#30191](https://github.com/ggml-org/llama.cpp/pull/30191), [#30149](https://github.com/ggml-org/llama.cpp/pull/30149), [#30139](https://github.com/ggml-org/llama.cpp/pull/30139), [#30190](https://github.com/ggml-org/llama.cpp/pull/30190) and new correctness fixes such as **merged [#30103](https://github.com/ggml-org/llama.cpp/pull/30103)**. Verify model/device/shape applicability and same-binary gains; do not predict Evo-X2 gains from unrelated published hardware. Unsloth mix, Strata 0.1.42, and Halogen 0.17.5 remain reference systems, not an automatic switch. |

### COMMON-005 r3 → r5 migration feasibility — 2026-10-11

[**R5-COMMON005-PORT-FEASIBILITY-2026-10-11.md**](R5-COMMON005-PORT-FEASIBILITY-2026-10-11.md) compares r3 `d03c91b` with the pinned r5 k-pool selection/mask interfaces. **Keep the compact selected-K/V decode idea but do not cherry-pick r3's 71 lines**: r5's `selected_rows` can include dump rows `>= n_kv`, and its `sel` is a full-length additive mask rather than the original per-cell `top_k`. A safe port needs valid gather IDs, explicit dead-slot masking and attention/graph-shape adaptation; no new HIP kernel is intrinsically required. **Current decision: DEFER** until non-MTP ROCm decode is the chosen topic or first integration patch review. The old gate was single-token-only and does not optimize speculative MTP verification. This is an inspection decision, **not** an implemented/tested r5 port.

### Source-only ROCm HIP FA investigation checkpoint — 2026-10-11

[**R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md**](R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md) now records **both source tracing and successful r5 Windows HIP RGP 64k captures**. Literature vs C++ sampled `flash_attn_ext_f16<256,256,16,4,...>` GPU time: **104.911 vs 111.198 ms**; `flash_attn_mask_to_KV_max<16>` executed, **46.914 vs 68.492 µs**. Both samples reported **3,072 wavefronts**, **VGPR 256, LDS 36,864 B, occupancy 4/16**; C++ occupancy graph remains at a relatively low steady level during the ~111 ms FA call. No `fixup` or `combine` events were found within the inspected capture. These support the WMMA-path and weak input-sensitivity hypothesis **at one sampled FA node**. Actual HIP KV depth/warmup-vs-timed iteration and total GPU operator attribution are **still unverified**. At 64k ROCm outperformed Vulkan on both normal workloads, but the source-code FA single node is shorter on prior Vulkan OFF; **ROCm's whole-run advantage cannot be attributed solely to FA**. HIP sparse-pre-fill and COMMON-005 remain separate **optional next research questions**; no code/refresh required to close this bounded source/runtime checkpoint.

### Starting the next ROCm chat (handoff / no immediate code changes)

1. **Branch and reproducibility:** use `r5/upstream-refresh-20261009` for stable source inspection; pinned upstream stays `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Record the checked-out repo HEAD, HIP binary b11543/commit `28d0f32d0` if reusing the October 10 baseline, model path/size, input hashes and compiler/HIP toolchain. The separate Vulkan FA investigation branch contains instrumentation; **do not merge it** merely to start ROCm. An isolated new ROCm investigation branch is optional **after** source-only research defines a need for instrumentation.
2. **Source-first questions:** for `KV≈49152`, `N=1024`, f16 K/V, qwen4exp/QSA, identify the actual HIP FA path and kernel specialization, conditional `scan_mask` and trailing-KV cutoff, Stream-K/workgroup assignment, and what is different from Vulkan `FA_COOPMAT1` `mask_opt` with an interior `ALL_NEG_INF` early skip. The CUDA-only sparse path guarded off under `GGML_USE_HIP` is a different feature from suffix scanning. Do **not** presume Vulkan `Qcur-19` has an identically named HIP event.
3. **Tool feasibility:** check tools available for Windows HIP timing/dispatch traces before adding diagnostic kernels or relying on Vulkan-only RGP captures. Begin with existing source and low-overhead op attribution; if unavailable, explicitly state the observability limit.
4. **Narrow measurement:** use matched Japanese novel `wagahaiwa_nekodearu_utf8.txt` (SHA-256 `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`) and `llamacpp-inference-code.txt` (SHA-256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`), `-p 61789 -c 65536 -b 2048 -ub 1024 -ctk f16 -ctv f16`, and the validated GGUF. Measure FA and non-FA contributions separately if feasible; account for different backend algorithms/compilers and ambient conditions.
5. **Exit gate:** summarize actual HIP FA path and evidence, attribution confidence, potential Vulkan-applicable change **if any**, profiling cost and recommendation to continue ROCm FA, advance r5 MTP, or move to depth-scaling/FP4. Avoid another open-ended series of local shader modifications without a demonstrated payoff.

### Change-control guard

This review is **documentation and prioritization only**. Preserve validated r5 Vulkan union OFF/ON / ROCm baseline build identities and the original raw ZIP evidence; do not merge investigative FA instrumentation into r5, delete saved research documents, upgrade drivers/ROCm, switch GGUF or revise a baseline silently. Re-check upstream PR state on the day of any implementation, and keep article-draft Markdown **outside Git**, as requested.

---

## Current r5 checkpoint

- Branch: `r5/upstream-refresh-20261009`
- Pinned upstream: `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`
- Documentation/tooling source: r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8`
- Native inference source: r5 pinned-upstream clean b11517 Vulkan/ROCm 64k/128k/256k reference; COMMON-001 compatibility b11521 passed Original+PLE16 Vulkan/ROCm 64k. **VULKAN-002 grouped-union is now implemented and its Windows Vulkan0 targeted 18/18 OFF + 18/18 ON CPU-reference correctness gate PASSED (2026-10-09)**, but model-level 64k/128k/256k performance and answer agreement are not yet validated. r5 real-prompt llama-bench Phase A also passed b11526 short smoke.
- Entry point: [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md)
- Accepted measurements and environment: [R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md); r4 clean 64k binary replay on Windows 26H2 confirms PP close to old r4, while r5 PP is higher
- Vulkan MoE tile investigation: [R5-MOE-TILE-UPSTREAM-REVERT-2026-10-09.md](R5-MOE-TILE-UPSTREAM-REVERT-2026-10-09.md); upstream PR #29936 reverted the per-expert selector, matching the r4 legacy-ON expression: **UPSTREAMED / RETIRE**, no r5 diagnostic switch port
- r5 COMMON-001 split PLE16 support: [implementation](R5-COMMON001-IMPLEMENTATION-2026-10-09.md) / [Windows validation](R5-COMMON001-VALIDATION-2026-10-09.md). **Accepted for allocation, short inference and matched-workload 64k compatibility/performance gate** (b11521; Vulkan/ROCm Original and PLE16, 4/4 OK). Small Vulkan TG layout difference observed but unexplained; no extra repeat now. r5 128k/256k PLE16 measurements are deferred to VULKAN-002.
- r2/source-fork PLE inspection: [R2-PLE-LEGACY-SOURCE-REVIEW-2026-10-09.md](R2-PLE-LEGACY-SOURCE-REVIEW-2026-10-09.md); **no additional port**, reopen only on relevant LaurentZuijdwijk fork update or changed requirements. Agreed order: validate COMMON-001 → reorganize main/r2/r4 refs → evaluate VULKAN-002
- r5 VULKAN-002 + benchmark/stats staged port: [plan](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md), [Phase A bench](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md), [Phase B native/initial 64k](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md), **[Phase B complete r5 64k/128k/256k validation](R5-VULKAN002-VALIDATION-2026-10-09.md)**, [Phase C stats port](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md). Windows GPU 18/18 OFF+ON and **12/12 normal runs PASSED**; PP gains 64k Original +26.30%, PLE16 64k +25.61%, 128k +71.27%, 256k +105.54%, with r4 comparison recorded. Pre-stats b11530 binary frozen as the baseline; **Phase C stats b11535 Windows build and 64k STATS=0 normal CLI / STATS=1 CSV gates PASSED** (PP=337.84 vs pre-stats PLE16 64k ON mean 339.48, −0.48%; 30 CSV rows/5640 groups/dropped=0); extra native correctness 18/18 re-run on b11535 not supplied. Phase D optional mixed text/code genres.
- Repeatable procedure: [UPSTREAM-REFRESH.md](UPSTREAM-REFRESH.md)

Follow the r5 sequence below. Historical r4 implementations and validation reports are retained for comparison and do not imply those patches are present in this initial r5 tree.

## Preserved r3/r4 checkpoint and policy

The validated r3 source baseline remains:

```text
upstream: ggml-org/llama.cpp
build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

The r3 branch is frozen at:

```text
r3/upstream-first
0a93fcbb8e5bcf51b331275c4f4b142d822168d6
```

The r4 branch was created directly from the pinned upstream commit:

```text
r4/upstream-refresh-20261002
bed0a856606ee4a24a164066f73d2379447033f5
```

Fork housekeeping is committed at `39f35efdfa135b36d0181a393178cc53719e5363`.
The clean refreshed-upstream baseline remains preserved as the comparison point.
COMMON-001 has now been adapted to r4 and committed as:

```text
a60a57879a9ffb4d51acd45d4de7e80d721548f9
qwen4exp: restore split PLE n-gram tensor support
```

The joined Original model and split PLE16 model both load after the port.
Vulkan/ROCm AllocationOnly and short inference pass, the matched 64k
Original/PLE16 gate passes, and PLE16 completes 128k/256k on both backends.
See [R4-COMMON001-VALIDATION-2026-10-03.md](R4-COMMON001-VALIDATION-2026-10-03.md).
Do not move the upstream base silently or rewrite r3 onto it. Re-apply only
downstream deltas justified by measurements.

### r4 checkpoint and r5 validation decision (2026-10-09)

The confirmed r4 implementation state, MTP qualification, open validation gates
and separate investigation-branch HEADs are recorded in
[R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md).

r4 contains MoE legacy tile selection, COMMON-001, VULKAN-002, the minimal dense
MTP pool-input guard and two default-OFF TG candidates. The historical
COMMON-002 compatibility patch was not ported wholesale; upstream-native MTP
with a local guard is the accurate description. MTP PP overhead and ROCm
long-context PP scaling remain unresolved. Real-document llama-bench input and
QSA union statistics are implemented on separate investigation branches and are
not integrated into r4.

The next phase is **r5 validation from a newly pinned upstream base**.
The r4 decision has now progressed to the pinned r5 preparation recorded at the top of this document. Keep r4 and the investigation heads as comparison references; their unresolved items do not all need to be closed before the clean r5 baseline.

### Upstream-watch-first implementation policy (2026-10-06)

The r3/r4 cycle showed that several locally investigated or implemented
optimizations were superseded by upstream changes within roughly one week.
The profiling, bounded implementation and validation workflow remains useful,
but not every observed regression should immediately become a downstream patch.

Separate **investigation** from **implementation**:

- reproduce and record a suspicious regression when it is found
- preserve measurements, profiles, source attribution and comparison conditions
- search upstream issues/PRs and external reports before writing a fix
- when an upstream solution is already active, prefer watching it over duplicating it
- implement locally only when the problem remains relevant after the watch gate,
  or when the requirement is sufficiently Evo-X2/model-specific that upstream is
  unlikely to prioritize it

Use the following working states for future candidates:

| State | Meaning |
|---|---|
| `WATCH-UPSTREAM` | Problem is recorded, but active upstream work or an obvious upstream solution exists. Do not duplicate it yet. |
| `INVESTIGATE` | Cause or scope is not established. Profiling, reproduction and source tracing are useful; implementation is not yet approved. |
| `LOCAL-CANDIDATE` | Requirement is niche, old, Evo-X2/model-specific, or lacks a plausible upstream path. Local design work is justified. |
| `IMPLEMENT` | A bounded local change has passed the decision gate and is ready for implementation/validation. |
| `UPSTREAMED / RETIRE` | Upstream now provides an equivalent or better path. Re-test and remove/defer the downstream delta rather than maintaining it automatically. |

Suggested waiting gates are deliberately approximate rather than hard deadlines:

- obvious regression with an active fix/PR: normally watch for **7-14 days**;
  if the PR is still actively changing, continue to wait
- issue/report with a plausible solution but no merge: re-evaluate after about
  **two weeks** before duplicating it
- older performance problem with no upstream resolution: if it survives
  **two upstream refresh checkpoints or roughly 2-4 weeks**, promote it toward
  local implementation
- no similar public report, no proposed solution, or clearly niche requirement:
  give it higher local investigation/implementation priority without waiting for
  a generic upstream fix
- correctness failures, output corruption, crashes, or repeatable state errors
  are exceptions and can bypass the performance waiting gate

Prioritization should not be based on expected speedup alone. Rank candidates by:

1. expected user-visible PP/TG/latency impact
2. likelihood that upstream will solve the same problem soon
3. age/persistence of the problem across upstream refreshes
4. uniqueness to Evo-X2, Windows, the target model or the downstream model format
5. whether similar reports exist
6. whether an issue exists but no implementation direction has been proposed
7. investigation/implementation/validation cost

Examples for the current backlog:

- COMMON-001 and ROCmFPx support remain strong local candidates because they are
  specialized model-format/operational requirements.
- MTP PP overhead should remain measurable and visible, but do not immediately
  start a large local rewrite while qwen4exp/MTP upstream is moving quickly.
  If it remains after two refresh checkpoints or roughly 2-3 weeks without a
  credible upstream fix, promote it.
- The Vulkan 256k CLI/random-token bench PP gap is now substantially explained
  by input-dependent QSA union behavior; real-document bench input closely
  matches CLI. Preserve the investigation, but do not reopen it as an unexplained
  tool-overhead blocker for r5. The remaining union-OFF mechanism question is
  lower priority. See [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md).
- known regressions with an upstream fix or active PR should normally stay
  `WATCH-UPSTREAM`.

This policy supersedes the earlier implicit assumption that every measured
regression should proceed directly from diagnosis to a downstream patch.

### Planned r5 validation and implementation sequence (2026-10-09)

1. **Establish a clean latest-upstream baseline on a separate r5 branch.**
   Re-check upstream at branch creation and pin its exact SHA. Start with the
   joined Original model, MTP OFF and f16 KV. Validate Vulkan/ROCm builds, backend
   tests, load and short inference, then matched 64k/128k PP/TG on both backends;
   extend to 256k for long-context decisions. Preserve source/build/driver/input
   identity and repeat material differences. Carry only necessary docs and
   measurement tooling; do not merge the full r4 inference patch stack first.
2. **Reclassify the existing downstream deltas against the new base.**
   Mark COMMON/VULKAN items and MoE tile selection as still-needed,
   WATCH-UPSTREAM, or UPSTREAMED / RETIRE. Re-check native MTP and the dense-sidecar
   guard before considering old compatibility code or the two TG candidates.
   Keep MTP correctness/overhead work separate from the initial MTP-OFF baseline.
   Review real-prompt and union-statistics tool integration separately, including
   the outstanding stats-OFF performance gate.
3. **Restore COMMON-001 first if split PLE16 support remains necessary.**
   Port only the missing path, preserve joined-model compatibility and repeat the
   required load/output/performance gates for the new base.
4. **Re-evaluate VULKAN-002 before the model comparison.**
   Measure current-upstream QSA PP first. Port the minimum grouped-union change
   only if it still adds value; validate OFF/ON output and performance through
   the relevant long contexts. Its r4 benefit is not proof of an r5 benefit.
5. **Add missing ROCmFPx / AgentionAI model support.**
   Audit current upstream first, then implement missing COMMON-003 format/core
   support and VULKAN-001 Vulkan kernels only where required.
6. **Run matched AgentionAI versus Unsloth speed comparisons.**
   Use the same machine, source, input/task, context and runtime conditions where
   practical, with model-format differences recorded. Begin with MTP OFF.
7. **Compare long-context quality using the Qwen3.5 validation methodology.**
   Reuse the established questions/checks and compare output failure modes as
   well as throughput.
8. **Select the next general optimization from the remaining measured gaps.**
   Re-rank MTP PP overhead, ROCm long-context PP scaling and new candidates under
   the upstream-watch policy. The already investigated real/random PP gap is
   not a mandatory prerequisite to this refresh.

Use **llama-cli for primary first-pass measurements** with real input and output
sanity checks. Use **llama-bench for repeated samples, variance and confirmation
of small differences**, matching the real-document input when comparing PP.
Preserve the real-prompt/statistics investigation heads and selectively integrate
their changes only after reviewing the required validation gates.

The dated r4/r3 sections below preserve execution history. The r5 sequence above
supersedes their old priority orders for the next phase.

### Historical r4 order after VULKAN-002 validation (2026-10-04)

This order supersedes the older refresh sequence below. The clean six-run
baseline, scoped 64k PP regression diagnosis, GET_ROWS tensor breakdown, and
COMMON-001 compatibility port are complete.

1. **Completed:** capture tensor-level Vulkan GET_ROWS with Original 64k,
   before COMMON-001, fixing MoE legacy selection to 1. Windows run is OK:
   GET_ROWS 2.487 ms/token, including cached pool gather 1.662 ms (66.82%).
   Preserve b11377 / acf7fea2b and its logs as the pre-port reference.
2. **Completed:** COMMON-001 adapted port. Split PLE16 compatibility is restored
   while preserving the joined Original path. 64k matched-layout comparison and
   PLE16 128k/256k validation pass on Vulkan and ROCm. The implementation commit
   is `a60a57879a9ffb4d51acd45d4de7e80d721548f9`.
3. **Completed, candidate not promoted:** investigate a small cached-pool gather
   fix without restoring COMMON-004 or rewriting cache/layout management.
   Source inspection is complete at `43feb226...`: direct view replacement is
   constrained by variable cell ids, padding, graph reshapes, and backend copies.
   A scoped Vulkan GET_ROWS `128 x 4` workgroup candidate is now implemented behind
   `GGML_VK_GET_ROWS_128X4=1`, default OFF. The b11387 / `109e238b...` Windows
   64k profile pair completed OK: steady cached gather 1.658893 -> 1.671003
   ms/token and GPU total 40.688344 -> 40.716906 ms/token (OFF -> ON).
   No useful improvement was observed. Skip normal ABBA and 128k/256k for this
   candidate; keep default OFF and close this gate. Dedicated GPU correctness
   logs were not supplied in that archive; no value-test pass is asserted.
   Do not broaden this gate into cache/layout or gather/matmul-fusion work.
   See [R4-GET-ROWS-128X4-AB-2026-10-03.md](R4-GET-ROWS-128X4-AB-2026-10-03.md).
4. **Completed: VULKAN-002 opt-in validation.** Implementation `5814fbe99...`
   passes the Windows build and 18/18 GPU cases in OFF and ON. 64k profile and
   normal ABBA pass on Original/PLE16; PLE16 128k/256k ABBA also passes. PP gains
   are +24.9% at 64k PLE16, +65.2% at 128k and +100.6% at 256k; TG is neutral.
   Vulkan ON PP 295.68/266.75 tok/s exceeds earlier COMMON-001 ROCm
   279.80/185.90. Keep source default OFF and explicitly enable it for the
   validated Vulkan baseline; broader/default promotion is separate. See
   [R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).
5. **COMMON-002 long-context MTP investigation is active.** Native upstream
   MTP plus the dense-sidecar input guard completes all 28 overnight runs:
   Vulkan 64k/128k/256k and ROCm 32k/64k/128k/256k, ABBA, 512 output tokens.
   Runtime success does not establish exhaustive output/logit/rollback equivalence.
   At 256k MTP reduces TG by 22.8% on Vulkan and 11.7% on ROCm; all 64k+
   cases also have worse total PP+TG latency. Follow the user's order:
   first split draft generation, catch-up, verification and CPU layout/rollback
   costs at 128k/256k; then investigate MTP PP overhead; then ROCm PP scaling.
   Check unused dense-draft indexer bookkeeping and suffix-triggered CPU layout
   rebuilds before reviving the unsuccessful r2 MTP-QSA prototype. Check actual
   small-query Vulkan union dispatch during verification. For ROCm PP, profile
   the growing full-KV attention path before considering grouped selected-K/V
   compaction. See
   [R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md).
   Opt-in diagnostics and build identity checks passed the rebuilt Windows
   Vulkan allocation/short gate. Normal ON and wall ON text/acceptance match;
   partial/full acceptance and rejection are observed. A summary success-stream
   fix was applied before the focused Vulkan 128k ON, 256k ON/OFF wall collection.
   All three inference runs finished; the user has recovered all three reports
   with the startup capability-refusal classification fix, without rerunning.
   Layout CPU time grows from
   5.207 s at 128k ON to 15.015 s at 256k ON, versus 0.004 s at 256k OFF.
   Source review confirms that dense MTP skips the graph's pool input while
   memory still allocates and maintains its indexer. Opt-in null indexer
   allocation for the supported single ratio-zero MTP block is now implemented,
   retaining hybrid/attention/recurrent semantics and source default OFF.
   Windows native policy/model/state/rollback gates pass in the 14:50 Vulkan
   report after harness position/partition corrections. All eight A/B output
   pairs have identical logits/hidden; default remains OFF. Three allocation
   smokes and five short real CLI runs also pass (8/8 OK): output/acceptance
   match across MTP ON arms, rejected/partial/full drafts are covered, and B
   removes draft indexer/layout/pool work while target work remains. The 256k
   wall pair also passes: TG 14.76 -> 19.95 tok/s (+35.16%), generation time
   -9.00755 s, identical generated response bytes and acceptance history.
   Draft layout is absent in B; target layout remains 5.499980 s. PP is
   effectively unchanged (229.91 -> 230.21). Diagnostic-off normal ABBA now
   also passes 4/4: TG mean 15.220 -> 20.185 (+32.62%), response/acceptance
   match, PP mean 228.835 -> 229.650. The earlier normal MTP OFF reference is
   TG19.76/PP265.02: B has only +2.15% TG and total latency remains higher.
   Target source review is complete: no-op invalidation is the first bounded
   candidate (3.09 s of B-wall's 5.50 s). The approved no-op candidate is now
   implemented: separate default-off target switch, actual membership-count
   comparison and preserved existing stale state. Native target tests, Windows gate and short/wall/normal plans retain
   draft omission1. The19:12 Windows Vulkan native gate now passes after the
   accessor fix: all524 logits/hidden comparisons match exactly,67 no-op
   invalidations are suppressed and33 pending stale markers are preserved.
   Allocation/short CLI gate now passes8/8: A/B output and acceptance match,
   25 no-op invalidations are suppressed and all33 real removals retain stale
   marks; target full rebuilds fall57->33. The256k wall gate now also passes
   2/2 with matching output and ordered acceptance:123 no-op suppressions,
   all95 real-removal stale marks retained, full rebuilds217->95 and layout
   5.529702->2.436146 s. Wall TG19.96->22.71 (+13.78%), PP unchanged. Normal
   ABBA now passes4/4: mean TG20.205->22.830 (+12.99%), matched response and
   aggregate acceptance, mean PP229.940->229.565 (-0.16%). Source default stays
   OFF. ROCm native model gates and all8 allocation/short CLI runs now pass
   with matching A/B output/acceptance and full rebuilds58->36. Short B-normal
   PP48.16 is an explicit unexplained outlier. ROCm256k normal collection is
   now3/3 OK: OFF/A/B TG12.39/13.57/14.44 and PP185.76/173.91/173.84.
   A/B bodies and acceptance differ; long equivalence and isolated no-op benefit
   remain open. B fresh-prompt evaluation is88.318 s slower than OFF. MTP OFF
   CLI/bench is now collected at64k/256k:11 new runs OK plus the
   reused ROCm256k OFF control. TG tool gaps stay within2.40%, ROCm PP agrees
   closely, Vulkan256k bench PP is19.40% below CLI. ROCm PP halves between
   these depths in both tools without MTP. Choose the next investigation,
   retaining unresolved ROCm long A/B divergence and a separate native time-SD
   overflow finding. See
   [CLI/bench results](R4-COMMON002-CLI-BENCH-COMPARISON-2026-10-05.md) and
   [ROCm256k review](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md) and
   [ROCm native/short validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md) and
   [no-op normal ABBA validation](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md) and
   [ROCm/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md) and
   [256k wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md) and
   [allocation and short validation](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md) and
   [implementation and commands](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md).
   Focused 128k confirmation remains before broader expansion. See
   [candidate normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
   See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md) and
   [candidate short validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md).
   Residual target suffix maintenance is parked during the requested checks. The earlier relative-path
   Windows fixture is confirmed. No extra sync collection is required. See
   [dense-indexer implementation and runnable gates](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md),
   [dense-indexer implementation plan](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
   [layout source review and focused gates](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md),
   [wall diagnostics and recovery](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md),
   [short validation](R4-COMMON002-SHORT-VALIDATION-2026-10-04.md) and the
   [implementation and commands](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md)
   and the earlier
   [R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md).
6. **COMMON-005 historical decode port remains deferred.** ROCm still leads
   PP through 64k, while Vulkan leads at 128k/256k. The requested ROCm PP
   investigation is a candidate for the post-ROCm/bench decision; related compact-K/V work
   must be designed and validated for PP rather than restoring the r3
   single-token decode patch automatically.
7. Use the consolidated priorities below for usage-policy work, cross-cutting
   checks and the remaining conditional/deferred candidates.

### Historical r4 priorities after ROCm and CLI/bench collection

This follows the user's22:41 sequence request on2026-10-04. ROCm normal and
CLI/bench64k/256k collection have now arrived; the next source investigation
is ready for a decision. Data completion does not close the unresolved ROCm
MTP long-output issue.
Vulkan256k target no-op validation is complete through native, allocation/short,
wall and normal ABBA. Normal TG20.205->22.830 (+12.99%) is reproduced with
matched output/acceptance; PP is effectively unchanged. Source default stays OFF.
Historical dense omission improved TG15.220->20.185; that is separate from the
current same-binary no-op comparison. See [normal results](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md).

| Order | Work | Next action and completion gate |
|---|---|---|
| 1 | ROCm coverage of current MTP candidates | Both native model/state/rollback gates and all8 allocation/short runs pass with Verified b11420/131288531 runtime, matched A/B output/acceptance, 23 no-op suppressions and 36 real removals retained (full rebuilds58->36). 256k normal collection is3/3 OK: OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84; B evaluation is88.318s slower than OFF. A/B response/acceptance differ, so long candidate equivalence and isolated speedup remain open. Short PP48.16 collapse is absent here but unexplained. OFF-only bench collection is complete; retain focused ROCm equivalence/variability review before broader candidate use. |
| 2 | CLI versus llama-bench | Collected at64k/256k:11 uploaded runs OK, eight bench rows/20 timed repetitions and reused ROCm256k OFF reference. TG gaps within2.40%; ROCm PP agrees closely; Vulkan256k PP268.10 CLI versus216.09 bench (−19.40%). ROCm PP falls about49% between depths in both tools without MTP. Reported runtime preflight digests match manifests. Native integer time-SD overflow identified; throughput statistics verify. Bench has no MTP path and allocation/routing/warmup/timer differences remain. No extra collection required for data organization. |
| 3 | Decide the next optimization | After the preceding results, choose MTP PP attribution (target/draft prefill, hidden copy/sync, bookkeeping), residual target suffix reuse (95 rebuilds/2.436146s, separate CPU/GPU invalidation), ROCm128k/256k PP scaling (early/late batches, MTP OFF), focused Vulkan128k coverage, unresolved ROCm256k candidate equivalence/variability, or Vulkan256k PP workload/tool divergence. Bench OFF cannot settle MTP equivalence. Native time-SD overflow is a separate small measurement-tool fix. No implementation automatically starts. Do not revive r2 MTP-QSA without attribution. |
| 4 | MTP usage policy | Once the selected path is stable, assess representative output quality, prompt reuse and fresh-prompt total latency; DraftMax1/2 only if acceptance/cost supports it. TG improvement does not alone establish total-latency superiority. |
| 5 | COMMON-005: residual ROCm decode | Remains deferred. Reprofile after the selected PP/coverage work; port only a still-needed compact-K/V delta. COMMON-003/VULKAN-001 and conditional upstream reviews remain in their existing backlog. |

See [collected CLI/bench results](R4-COMMON002-CLI-BENCH-COMPARISON-2026-10-05.md)
and [runnable ROCm/bench sequence](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).
The prior four observations and baseline records remain historical evidence;
this table replaces their earlier implementation ordering.

#### Next-chat handoff: PP investigation items (2026-10-05 09:21 JST)

The user will decide priorities in a new chat. Preserve the following items
in that decision; their order in this table does not assign a new priority.

| Item | Evidence to carry into the decision | Status |
|---|---|---|
| Vulkan256k CLI/bench PP discrepancy | MTP OFF CLI268.10 versus bench216.09 tok/s (bench−19.40%); both bench repetitions218.31/213.87 are below CLI. Retain a focused investigation of input/MoE routing, allocations, graph setup, warmup and timer differences; cause is not established. TG agrees closely. | Explicit investigation candidate for the new-chat priority review |
| Existing ROCm long-context PP scaling item | Reproduced with MTP OFF in llama-bench as well as CLI:64k→256k PP366.88→185.78 tok/s in bench (−49.36%), CLI370.22→185.76 (−49.82%). This is additional evidence for the existing item, not a separate duplicate task; it is not solely a speculative/CLI-application issue. | Retained existing investigation item, now with bench reproduction evidence |

See [conditions, repetitions and comparison limits](R4-COMMON002-CLI-BENCH-COMPARISON-2026-10-05.md).
The separate native time-SD overflow does not invalidate these mean PP rates.

Steps are scoped investigations, not promises that every slowdown can be fixed.
Do not let one unsuccessful candidate indefinitely block the next question.

#### Checks integrated with that work

| Observation | Priority and placement | Escalation or acceptance rule |
|---|---|---|
| Output and rollback correctness | Start a small baseline case alongside step 1; require a focused correctness gate before adopting every state/cache/attention change | Exercise rejected and partially accepted drafts and inspect the first divergent logits/state if outputs differ. Greedy text divergence alone is not proof of a bug. A confirmed state/logit error takes priority over speed work. |
| Build identity | Small prerequisite bundled with the next diagnostic implementation/build | Ensure source identity is explicit and preserve backend DLL identities as well as the launcher. Address stale embedded build metadata within this narrow scope; no broad build-system rewrite. Existing manifests keep the current comparison usable. |
| Memory and destructor warnings | Continue phase-aligned resource logging in steps 1–3 | Track warnings and allocation changes. Investigate immediately if an assert, allocation failure, output corruption or repeatable steady-phase paging appears; current destructor-only warnings and counters alone do not justify changing UMA/context first. |
| Output-length / prompt-reuse break-even | Step 4, after throughput changes settle | The current 64k constant-speed estimates (~2700 output tokens Vulkan, ~1300 ROCm) are illustrative, not deployment thresholds. The initial Vulkan 32k pair uses 128-token greedy generation; overnight rows use 512 tokens at temperature 0.2. Do not treat those as matched backend conditions. |

The step-1 diagnostics, build identification and short correctness gate are
implemented and the focused wall collection is complete. The next bounded
optimization proposal, change list and validation order are recorded in
[R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
with supporting source evidence in
[R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md).
The optimization is implemented behind the default-off opt-in; Windows native,
allocation/short, candidate 256k wall and diagnostic-off normal ABBA gates pass.
Use explicit candidate=1 for subsequent Vulkan MTP tests while retaining source
default OFF. Target source review is now complete: all-accepted trims still
set indexer stale markers and force full layout copies. In B-wall, 122 such
rebuilds cost 3.092231 s; 95 real suffix rebuilds cost 2.407742 s. The
[no-op implementation plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md)
is ready for review, leaving real edits intact;
then consider suffix-prefix reuse with distinct CPU/GPU invalidation. See
[target layout source investigation](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md).
Focused 128k confirmation remains before broader use. Results and commands are in
[the implementation document](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md).

The earlier diagnostic design and event/timing semantics are recorded in
[R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-PLAN-2026-10-04.md](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-PLAN-2026-10-04.md).

#### Deferred, conditional and completed items

| Item | Current disposition | When to revisit |
|---|---|---|
| COMMON-004 historical incremental-pool port | No wholesale port; upstream incremental pooling is already present | Only a measured residual gap. The new suffix-triggered CPU layout rebuild candidate belongs to step 1 and is distinct from restoring the old GPU pooling implementation. |
| COMMON-006 historical block-domain selection rewrite | Upstream validation, not a queued implementation | If a current profile demonstrates remaining selection/top-k/expansion cost that the upstream path fails to address. |
| COMMON-003 ROCmFPx format/core and VULKAN-001 kernels | Later model-expansion work | After the current Unsloth PLE16/MTP questions, when resuming ROCmFPx model evaluation. Check pinned-upstream support first; add only missing common support, then Vulkan kernels if required. |
| Historical MTP-QSA prototype | Conditional experiment; remains outside the stable stack | Only if step 2 demonstrates a concrete opportunity beyond the r2 negative result. Use a separate experiment and validate PP, TG and output; do not force QSA by changing GGUF metadata. |
| VULKAN-002 broader/default promotion and MoE default policy | Separate, lower-priority validation | After current MTP interactions are understood and broader model/device evidence is available. Keep existing explicit experiment settings and source defaults. |
| GET_ROWS 128x4 candidate | Closed with no useful measured gain; default OFF | Only new evidence, not routine long-context retesting. |
| COMMON-001 and current VULKAN-002 target validation | Complete for the documented scope | Regression checks for affected code; no re-port or full repeat without a reason. |
| External engines such as Strata | Later exploration after the r4 baseline and current investigations settle | Separate compatibility/value review; no change to the pinned r4 base or present measurement scope. |

Results and detailed hypotheses:
[R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md).

COMMON-001 is treated as a compatibility/layout patch, not a throughput
optimization. ROCm clean Original and COMMON-001 PLE16 are effectively neutral
across 64k/128k/256k. Vulkan COMMON-001 runs use legacy MoE tile selection, so
the clean-to-COMMON-001 PP gain is not attributed to PLE16; the 64k delta closely
matches the previously measured same-binary MoE A/B result.

Instructions: [R4-GET-ROWS-PROFILE-2026-10-03.md](R4-GET-ROWS-PROFILE-2026-10-03.md).
COMMON-001 result: [R4-COMMON001-VALIDATION-2026-10-03.md](R4-COMMON001-VALIDATION-2026-10-03.md).
Source evidence and historical decisions:
[R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md).

### First r4 Vulkan profile (64k)

The next PP diagnostic is implemented as an opt-in MoE tile-selection switch,
with one binary for current/legacy A/B and separate profile/normal matrix jobs.
Default selection remains upstream. Windows A/B profiles now show PP MoE GPU
time 63.933 -> 47.807 s (legacy), with FA unchanged and steady TG essentially
unchanged. Both modes pass 939/939 MUL_MAT_ID tests. Normal ABBA now confirms
PP 248.475 -> 268.985 tok/s (+8.25%) with all four runs OK. This completes the
64k PP diagnosis for the tested model/device/shapes. TG averages -2.50% with
short, differing generations; do not claim no TG impact. Keep legacy opt-in.
The subsequent tensor-level TG GET_ROWS profile and COMMON-001 validation are
now complete; use the active order above for the next decision.
See [R4-MOE-TILE-AB-2026-10-03.md](R4-MOE-TILE-AB-2026-10-03.md).

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

### r2 grouped-union remains the long-context PP reference

r3 intentionally does **not** include the r2 QSA grouped-union optimization.
This is by design: r3 is an attribution-focused upstream-first checkpoint, not
a claim that every r2 performance optimization has already been superseded.

Keep the validated r2 grouped-union results as the long-context Vulkan PP
reference when evaluating the refreshed upstream:

| Context | r2 QSA union PP |
|---|---:|
| 64k | ~275 tok/s |
| 128k | 222.77 tok/s |
| 256k | 177.01 tok/s |

The r4 COMMON-001 PLE16 validation with legacy MoE selection measures 268.79,
178.99, and 132.99 tok/s at 64k/128k/256k respectively. The 64k gap is small,
but the long-context gap remains material, which keeps VULKAN-002 relevant.
Do not add grouped-union to r3 merely to make the checkpoint faster; preserving
the clean attribution of COMMON-001/004/005 is more valuable at this stage.

The 2026-10-02 observation `a868c3e3c56657f7e8a6231190dbbe90e7dd86c0`
was a candidate only. The base was pinned on 2026-10-03 JST at `bed0a856...`
after fetching upstream and verifying the raw source identity. #29824 is
included; #29825 was open and excluded at pin time.

## Completed r3 foundation

The r3 checkpoint includes:

- clean upstream-first b11247 Vulkan and ROCm baselines
- COMMON-001 PLE16 loader support, validated through 256k on Vulkan and ROCm
- COMMON-004 incremental pooled-key cache, validated through 256k on Vulkan and ROCm
- COMMON-005 gather-based QSA decode, validated through 256k on Vulkan and ROCm
- benchmark wrappers for real-input `llama-cli` and synthetic `llama-bench`
- benchmark matrix runner with environment-variable A/B support
- Vulkan and ROCm build wrappers with build manifests
- shared dependency caching for fresh build directories

## Completed diagnostic gate: r2 versus r3 decode profile

The 64k Vulkan profile that preceded COMMON-004 isolated repeated QSA pooled-
summary reconstruction as the dominant r3 decode regression.

Steady single-token decode GPU graph time:

| Build | QSA union | Steady GPU graph |
|---|---|---:|
| r2 | OFF | 44.18 ms/token |
| r2 | ON | 44.31 ms/token |
| r3 + COMMON-001 | n/a | 59.13 ms/token |

The extra r3 cost was concentrated in full pooled-summary `CONT`, RMS norm, and
RoPE work. This motivated COMMON-004.

## Completed: COMMON-004 pooled-key cache

Implementation commit:

```text
6559dd272fd0d5f553823e8851c78b9edc2a5016
qwen4exp: cache pooled QSA keys across decode steps
```

Key TG results with the pooled cache enabled:

| Backend | 64k | 128k | 256k |
|---|---:|---:|---:|
| Vulkan | 25.95 | 24.00 | 21.03 |
| ROCm | 20.62 | 16.44 | 11.60 |

COMMON-004 removed a large long-context decode cost on both backends. Vulkan
retained relatively little TG depth loss; ROCm still showed substantial
64k -> 256k degradation.

## Completed diagnostic gate: ROCm residual scaling after COMMON-004

Radeon GPU Profiler at 128k and 256k showed two context-linear paths:

| Kernel | 128k | 256k | Change |
|---|---:|---:|---:|
| `flash_attn_tile<256,256,1,4,false>` | ~1.452 ms | ~2.939 ms | ~2.02x |
| `k_get_rows_float` | ~0.451 ms | ~0.907 ms | ~2.01x |
| `mul_mat_vec_q<type14>` | ~2.835 ms | ~2.836 ms | flat |

Source tracing matched them to:

1. full-context K/V Flash Attention on HIP, despite a sparse `n_kv_max` hint
2. block-score-to-full-cell expansion before qwen4exp top-k

This diagnostic gate selected COMMON-005 as the next r3 patch and retained the
score-expansion rewrite as the original COMMON-006 idea.

## Completed: COMMON-005 gather-based QSA decode

Implementation commit:

```text
d03c91b6342b099457de3508c5d67533a9a5f0ee
qwen4exp: gather selected QSA KV rows for decode
```

COMMON-005 gathers selected K/V and matching KQ-mask rows during eligible
single-token decode and runs ordinary Flash Attention on compact tensors. The
existing path remains available through:

```text
QWEN4EXP_QSA_GATHER=0
QWEN4EXP_QSA_GATHER=1
```

### ROCm result

| Context | Gather OFF TG | Gather ON TG | Gain |
|---|---:|---:|---:|
| 64k | 20.55 | 22.60 | +10.0% |
| 128k | 16.425 | 20.41 | +24.3% |
| 256k | 11.68 | 17.37 | +48.7% |

128k -> 256k added decode latency falls from about +24.73 to +8.57 ms/token.

RGP directly confirms that compact Flash Attention no longer scales with full
context depth:

```text
128k ~= 41.93 us
256k ~= 42.00 us
```

The remaining repeated `k_get_rows_float` still scales from about 447.92 us at
128k to 907.13 us at 256k.

### Vulkan result

Vulkan already has backend sparse Flash Attention, so the model-side gather path
is a much closer tradeoff:

| Context | Gather OFF TG | Gather ON TG | Change |
|---|---:|---:|---:|
| 64k | 25.95 | 25.42 | -2.0% |
| 128k | 24.61 | 24.12 | -2.0% |
| 256k | 21.135 | 21.69 | +2.6% |

64k is one OFF/ON pair. 128k and 256k are ABBA averages. PP is effectively
unchanged.

Interpretation:

- ROCm: Gather ON is strongly beneficial and grows more valuable with context
- Vulkan: existing sparse-FA is slightly faster at 64k/128k, Gather ON slightly
  faster at 256k
- keep the r3 runtime A/B control as part of the reference checkpoint

Detailed final validation is recorded in
[COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md).

## Why the plan changes here

The 2026-10-02 upstream review crossed the refresh threshold that the previous
roadmap had intentionally deferred.

### COMMON-006 direction is now upstream

Upstream PR #29751 (`llama: fix qwen4exp`, merge commit
`66e0c17ee1741fef493312e17fe60a5d2cf5f7d5`) reworked the qwen4exp QSA/k-pool
path. Current upstream qwen4exp now selects top pools/blocks before expanding
them to cell indices:

```text
pool/block score
  -> pool-domain top-k
  -> expand selected pools to cell indices
  -> append retained tail indices
```

This is materially the same direction as the planned COMMON-006. Building a
second b11247 implementation immediately before refreshing upstream would add
maintenance and validation work without a clean long-term target.

Therefore COMMON-006 changes from `next implementation` to `upstream evaluation`.

### MTP support also moved upstream

Upstream PR #29761 (`Qwen4Exp: add MTP`) merged on 2026-10-01 and adds qwen4exp
MTP conversion/tensor support plus the draft-model load-path fix.

COMMON-002 should therefore start by testing the existing Unsloth MTP sidecar on
the refreshed upstream. Only a remaining compatibility delta should be ported.

### Relevant post-b11247 Vulkan work is already merged

The refresh also brings several changes that were previously independent
candidate ports, including:

- #28501: 512-expert Vulkan row-id hoisting, measured as a Qwen3.8 prefill gain
- #29182: MoE-aware Vulkan `mul_mat_id` tile selection
- #29520: qwen4exp HC post-gate Vulkan fusion
- #29599: PLE row prefetch; Windows behavior still needs real Evo-X2 validation

This makes a clean refreshed baseline more informative than cherry-picking the
same changes individually onto b11247.

### COMMON-005 may still matter on ROCm

Do not assume the refresh supersedes COMMON-005.

Current upstream CUDA sparse Flash Attention code explicitly excludes HIP, so
ROCm can still retain a full-context attention cost even with the newer model
QSA/k-pool selection path. The r3 COMMON-005 result remains the reference for
this question.

## Historical r3-to-r4 refresh execution order

The numbered sequence below records the original r3-to-r4 refresh plan.
The **Planned r5 validation and implementation sequence (2026-10-09)** above is
the current order for the next phase.

### 1. Freeze r3 at this documentation checkpoint (complete)

The frozen checkpoint is `0a93fcbb8e5bcf51b331275c4f4b142d822168d6`:

- keep `r3/upstream-first` as the validated b11247 reference
- do not rebase it onto current upstream
- use the committed COMMON-004/005 measurements and validation documents as the
  comparison baseline for all refresh work

### 2. Create a separate upstream-refresh branch (complete)

Created branch:

```text
r4/upstream-refresh-20261002
```

Completed at branch creation:

1. fetch current `ggml-org/llama.cpp` master
2. pin the exact upstream commit used for the branch
3. record that SHA before adding downstream patches
4. keep r3 available as the comparison branch

Do not carry COMMON-001/004/005 into the initial refreshed source tree.

### 3. Establish clean refreshed-upstream load/build baselines

Build Vulkan and ROCm from the pinned refresh source before optimization work.

First model-loading checks:

1. try the original joined Unsloth Qwen3.8-Flash-Next model
2. verify allocation/load on Vulkan and ROCm
3. test whether the upstream PLE changes remove the practical reason COMMON-001
   was needed
4. only re-port PLE16 support if the joined path remains problematic or the
   split model is still required operationally

Also run the relevant backend tests and allocation-only smoke before long runs.

### 4. Measure refreshed QSA baseline at 64k / 128k / 256k

Use MTP off first so the main-model QSA path is isolated.

Primary comparison:

```text
new upstream, no downstream QSA patches
vs
r3 COMMON-004 + COMMON-005 validated checkpoint
```

Record PP and TG for Vulkan and ROCm at 64k, 128k, and 256k using the existing
matrix/wrapper tooling.

Questions to answer:

- does upstream pool-domain selection remove the old COMMON-006
  `k_get_rows_float` depth slope?
- how does the new upstream pooled-key/k-pool path compare with COMMON-004?
- is ROCm TG still materially behind the r3 COMMON-005 result at 128k/256k?
- does Vulkan PP improve enough that historical grouped-union work becomes less
  valuable?

### 5. Re-evaluate COMMON-005 on ROCm only if the refreshed baseline needs it

If ROCm long-context TG still scales badly:

1. profile 128k and 256k on the clean refreshed build
2. confirm whether Flash Attention still sees the full KV depth
3. if so, port the minimum COMMON-005 compact selected-K/V path onto the new QSA
   structure
4. A/B against the clean refreshed build

Do not port COMMON-005 first and diagnose later.

For Vulkan, keep COMMON-005 out initially. Its r3 benefit was only a few percent
and changed sign with context depth.

### 6. Treat COMMON-006 as an upstream-validation gate

Do not write a downstream COMMON-006 unless measurement shows a remaining gap.

Validation points:

- pool-domain top-k is actually exercised by the real model
- selected pool expansion and tail indices preserve expected output behavior
- the old full-cell score expansion is gone or materially reduced
- 128k -> 256k ROCm residual latency slope is re-accounted after the refresh

If a new bottleneck remains, define a new downstream delta from the refreshed
source rather than reviving the b11247 design verbatim.

### 7. Re-evaluate COMMON-002 MTP on refreshed upstream

Start without old r2/r3 compatibility patches.

- load the existing Unsloth MTP draft model
- confirm draft residual-stream inputs and recurrent rollback behavior
- measure acceptance statistics
- compare MTP on/off at short and long context
- measure long-context PP overhead
- add only the compatibility change that is still demonstrably required

Keep MTP-QSA outside this compatibility step.

### 8. Reconsider VULKAN-002 grouped-union only after refreshed PP data

Historical grouped-union remains a useful reference, but the decision gate moves
after the new upstream baseline because several Vulkan/QSA changes have already
landed.

Use 128k and 256k as the primary PP decision points. If refreshed upstream has
already recovered most of the historical PP gap, do not re-port the larger r2
implementation.

### 9. COMMON-003 / VULKAN-001 ROCmFPx

For the AgentionAI ROCmFP4-FAST model:

1. identify what the pinned refreshed upstream already supports
2. add only missing common format/core support as COMMON-003
3. add Vulkan-specific ROCmFPx kernels as VULKAN-001 only if still required

## Upstream items to watch during the refresh

Do not mix unmerged work into the first clean baseline, but keep these visible:

- #29824: qwen4exp mask-construction optimization; merged and included in the
  pinned r4 base (`4e2713c1620f1fadb2c3afcc0a8f01500d68ac17`)
- #29825: qwen4exp indexer score-memory reduction; open and not included at
  pin time (2026-10-03 JST)

The base is now fixed. Later upstream merges are separate A/B candidates;
recheck their status when evaluating them rather than silently moving the base.

## Independent follow-up candidates

After the refreshed main path is understood:

- Laurent reverse-scan `get_prev_tokens` optimization if a meaningful
  depth-dependent CPU/cache scan remains
- q8_0 K/V cache as an operational A/B
- `GGML_VK_SHMEM_PAD` Windows driver-specific sweep
- `GGML_VK_DENSE_WAVE32`
- Strix Halo/RDNA matvec tuning
- MMID row-list prepass if refreshed MoE prefill still warrants it
- grouped-union scan/FA overlap and indexer-pipeline work only if profiling points there
- per-row index Flash Attention prefill
- persistent prompt-cache and PLE residency/mmap experiments

## Refresh acceptance checkpoint

The refresh branch now has the clean baseline and COMMON-001 validation recorded.
Before re-porting the remaining historical optimization stack, keep the following
checkpoint items explicit:

1. exact upstream base SHA
2. successful Vulkan and ROCm builds
3. relevant backend tests / allocation-only smoke
4. joined Original and split PLE16 load results
5. 64k/128k/256k PP/TG baseline where practical
6. direct comparison against the r3 COMMON-004/005 checkpoint
7. written decisions for COMMON-004, COMMON-005, COMMON-006, and VULKAN-002

That checkpoint becomes the basis for later MTP, grouped-union, and ROCmFPx work.
