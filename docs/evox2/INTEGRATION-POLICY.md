# Evo-X2 upstream and integration policy

> 2026-10-29 update: **R6 combined b11908 candidate is measured and source-frozen; public release/tag/default-branch switch remain pending.** S8 G8-0–G8-6 and S9 G9-0–G9-4 pass within documented limits; 21 additional speed runs + one ROCm all-five CLI smoke completed. Router-mode/G9-5 and ROCm MTP-ON server are **deliberately deferred**, S7 Draft K/V numerical parity is unverified and source defaults stay OFF. See [current branch inventory and publication preparation](R5-R6-BRANCH-INVENTORY-AND-PRE-RELEASE-CHECKLIST-2026-10-29.md), [consolidated measurements](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md), and [frozen flag sheet](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md). Earlier date-stamped "planned / not run" paragraphs are historical, not current status. This document retains the original October 11 workflow policy; dated pre-integration statements below reflect the state **then**, and are superseded by the r6 candidate checkpoint in [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md).


**Decision date:** 2026-10-11 JST. **Status:** adopted as a documentation/workflow policy; **no integrated build, release branch, or tag exists yet**. The first integration checkpoint is planned for a convenient near-term stopping point, not a fixed deadline.

## Purpose and non-goals

This is a personal research/hobby project: understand and measure Windows/Evo-X2/llama.cpp optimization mechanisms, preserve reproducible experiments, and accumulate useful source changes. Providing the newest or fastest user-facing inference product is **not** the scheduling objective. Occasional document summarization, chatting, or unrelated model experiments can use the most recently validated integrated snapshot once one exists.

Never require a research series to rebase simply because upstream moved. Upstream may change weekly; preserving a comparable pinned baseline is more valuable than having every experiment on the newest HEAD.

## Two independent lanes

| Lane | Branch/tag concept | Allowed change | Advancement criterion |
| --- | --- | --- | --- |
| Research | `r5/upstream-refresh-20261009` and future pinned `rN/...` plus separate `investigation/...` | One question/patch at a time, pinned upstream, isolated experiments | Finish or stop the research hypothesis; re-pin only for a demonstrated dependency, blocker, or intentional new series |
| Integration | Future `integrated/YYYY-MM` branch + immutable `evox2-integrated-YYYY-MM-DD` tag (names illustrative) | Current chosen upstream snapshot + selected previously validated downstream changes | Pass integration correctness and target benchmark matrix; explicitly record unsuccessful or skipped candidates |

An integration checkpoint must **not** reset the current research branch or pull experiment-only instrumentation into it. The two lanes may have different upstream SHAs and different validated performance characteristics. Preserve original r3/r4/r5 baselines, benchmark manifests, sources, and historic measurement interpretations.

## Default patch-porting rule

1. **COMMON-001 is mandatory before comparing the established PLE16 converted model on each new research or integration base.** A clean-upstream baseline with the Original joined-PLE model may be captured beforehand. Do not compare Original-only clean results with PLE16 results as if model/layout were unchanged.
2. For **research series**, after COMMON-001 port **only** patches whose functionality, metrics, or graph execution are relevant to the next experiment. An old patch being fast on an old branch is not by itself a reason to port it.
3. For **integration checkpoints**, review **all** previously measured beneficial candidates in PATCHES.md, but never apply all blindly. Confirm they are not already covered upstream, check prerequisites and interactions, then carry forward only the variants that pass on the chosen integration base.
4. Distinguish **present in source**, **enabled in measured runs**, **correctness-tested**, **performance-verified on that exact base**, and **approved for the integrated snapshot**. Those are separate states.
5. Keep fallback/default-OFF controls for domain-limited or incompletely tested optimizations; a recommended Evo-X2 runtime preset may explicitly enable a validated switch without changing global defaults.
6. Retire a downstream implementation only when the newer upstream covers its required behavior **and** the equivalence/performance gate is documented. Similar PR wording or a merge event alone is insufficient.

## Upstream intake and refresh gates

- **Watch/read** upstream changes as useful (roughly weekly is fine); this does not imply a build or rN increment.
- **Merged correctness, crash, or data-corruption fix:** evaluate immediately if the actual affected model/backend/shape may be used. A minimal isolated cherry-pick onto pinned research source is allowed after applicability review; record exact source commit, applicability, test result, and whether it changed experiment comparability. Do not infer a bug was reproduced merely because the fix's conditions could apply.
- **Merged performance PR:** add/update a candidate in PATCHES.md. Test only if it directly bears on the current research question, or at the next integration checkpoint. Avoid pre-emptive baseline rebuilds.
- **Open/draft PR or new engine idea:** keep in the research candidate pool. Use an isolated investigation branch for experiments; do not silently call it part of the baseline.
- **Upstream supersedes a downstream patch:** record first known upstream SHA/PR, exact functional overlap and differences, first tested refreshed series, and performance/correctness outcome. A patch can be functionally replaced but still a local speed candidate until A/B evidence resolves it.
- **New upstream pin:** create a new research series only when required to answer the question or at an intentional experiment boundary. Record the upstream SHA plus OS/driver/ROCm/Vulkan/toolchain and model/input identities. Do not combine an upstream refresh, driver change and patch change in a claimed isolated A/B.

Historic documents may contain older `NEXT` sections and snapshots: dated new decisions take precedence without rewriting historic results.

## Integration checkpoint cadence and execution

**Target:** approximately every 4–6 weeks **or** at a natural pause after several validated patches. This is optional, not an automatic monthly obligation; skip when research is at a sensitive comparison point, GPU time is limited, or upstream is unstable. Also allow an earlier checkpoint before unrelated model use if a stable snapshot is genuinely needed. **First integration is planned but not yet scheduled or created.**

Suggested workflow:

1. Freeze a candidate upstream commit intentionally (not necessarily that day's HEAD). Create a clean integration branch separate from research. Record the selected SHA and checkout/commit identity.
2. Build/validate **unmodified** Vulkan and ROCm and collect a bounded Original-model baseline as needed. Port and validate COMMON-001 next, so established PLE16 inputs can be reused.
3. Pull the candidate list from PATCHES.md. For each measured-beneficial local patch, merged upstream improvement, and relevant correctness fix: check overlap, dependencies, source applicability, and known limitations. Choose **included / upstream-covered / excluded / failed / deferred** with an evidence link.
4. Apply chosen changes **one at a time**. Use build/backend-ops and model-load/short-run gates first; perform bounded A/B for uncertain or interacting changes. Do not spend the integration session inventing a new optimization. When work grows beyond the gate, record the blocker and defer to the research lane.
5. Validate the **combined** build(s) using representative 64k/128k/256k PLE16 workloads for both backends when supported, with deeper runs focused on affected PP/TG paths. Record exact switch settings, MTP state, f16/quantized KV, executable/source SHA, benchmark archive ID, samples/repetitions and measured memory. Compare both with the clean new-upstream control and (descriptively, not as a source-only A/B) the previous integrated snapshot.
6. Do model-level sanity/correctness checks appropriate to changes: backend tests, short inference, fixed greedy/logit comparisons where meaningful, long-input completion, and rollback/cache/acceptance checks when relevant. Do not require arbitrary long sampled generations to be byte-identical, but never treat plausible text alone as a numerical equivalence gate.
7. **Only on a passing checkpoint:** record final included patches and combined measurements in INTEGRATED-RELEASES.md, set a read-only tag at the tested commit, and retain build manifests/binaries locally as feasible. Preserve an incomplete attempt as an explicitly **unreleased candidate**, not an accepted integration release.

If one backend lacks support for a patch, state the asymmetric selection; never imply ROCm and Vulkan exercised the same code merely because they came from one source tree.

## Testing depth and stop rules

| Gate | Required context | Typical stopping point |
| --- | --- | --- |
| Smoke | build, relevant backend ops, PLE16 allocation/short inference | Any failure blocks the candidate |
| Focused A/B | same binary/source conditions with switch, 64k or most diagnostic workload | No convincing isolated benefit or correctness issue → leave out / research separately |
| Long-context candidate | affected backend 128k and/or 256k; repeat or ABBA material differences | Stop after gain/side-effect is clear |
| Integration acceptance | combined Vulkan/ROCm selected stack, documented 64k/128k/256k coverage or explicit exclusions | Publish tag only after all chosen must-pass gates complete |

Keep benchmark throughput and end-to-end wall time separate. Preserve raw runs outside Git when large/private; commit compact references and conditions. Do not ascribe rN-to-r(N+1) differences only to source if OS, drivers, model layout, toolchain or sampled output differ.

## Registry and decision ownership

- `PATCHES.md`: canonical cross-branch status and **candidate** inventory (including not-yet-coded ideas, upstream PRs, and experimental tools), with links to authoritative test reports.
- `ROADMAP.md`: current research hypothesis and short exit gate; not a mandatory queue for integration.
- `PERFORMANCE-RESEARCH-LOG.md`: dated upstream watch and external performance claims; do not convert external claims into local measurements.
- `CURRENT-REFRESH.json`: identity of the active pinned **research** series; not an integrated-release manifest.
- `INTEGRATED-RELEASES.md`: integrated attempts/releases, with the first release currently **PLANNED / NOT CREATED**.

This policy changes scheduling and record keeping only. It does not rebase r5, approve untested patches, produce a combined binary, or assert a new benchmark result.
