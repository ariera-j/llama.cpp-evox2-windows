# Evo-X2 optimization roadmap

Snapshot: 2026-10-09 (r5 clean Vulkan/ROCm baseline verified through 256k; r4 clean 64k replayed on Windows 26H2; Vulkan MoE tile selection classified UPSTREAMED / RETIRE)

This document records the current execution order for the Evo-X2 optimization
work. Patch IDs remain stable even when implementation priority changes.

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
- r5 VULKAN-002 + benchmark/stats staged port: [plan](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md), [real-prompt bench](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md), [VULKAN-002 64k + native validation](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md), [stats implementation](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md). Phase A OK, Phase B 18/18 OFF/ON and 64k PLE16 PP +25.71% sanity OK; 128k/256k + 64k ABBA matrix still running on **pre-stats** binary. Phase C source implemented in isolated commit; **build and STATS=0/STATS=1 gates pending**. Phase D optional mixed genre/language/code workloads.
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
