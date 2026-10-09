# r4 COMMON-002: target QSA no-op invalidation implementation plan

Planning baseline: `r4/upstream-refresh-20261002` at
`f24b6e3e654a2826b9459d379dce0ac3b2d4b1f3`; pinned upstream
`bed0a856606ee4a24a164066f73d2379447033f5`.
Status: approved and implemented. The original planning commit was documents
only; the runtime switch, native targets, scripts and focused plans are now
delivered. Windows build/model and new performance gates remain pending. See
[implementation and commands](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md).

## Goal and bounded scope

Suppress a **new** indexer stale marker when target sequence removal actually
removes no indexer members. Retain every recurrent/indexer/attention operation,
return value and any already-pending stale marker. Do not alter real suffix
removal or the current full-layout rebuild algorithm.

Source investigation classifies B-wall target generation layout:
122 rebuilds after full acceptance/no-op trims cost3.092231 s;95 after real
suffix removal cost2.407742 s; total5.499980 s including the initial clean
append. The first component is the optimization target, not an exact normal
saving forecast.

The validated draft omission remains a separate control. All MTP ON target
candidate A/B runs keep `LLAMA_MTP_SKIP_DENSE_INDEXER=1`. This new patch neither
removes the target indexer nor introduces CPU suffix-prefix reuse. Changes to
pooled-key caching, kernels, acceptance/carry, state format and MTP PP batching
remain outside this first candidate.

## Switch, eligibility and initialization

Proposed switch: `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1`, default OFF.
Only the exact value1 requests enablement; unset/0/other values do not.

Determine the setting once per memory/context creation, with no static
environment cache and no per-token getenv. Store a private decision in the
hybrid-indexer memory object. The model create_memory path has the actual
`params.ctx_type`; pass target-context information explicitly to the
constructor rather than deriving role from logging or model filename.
Require `ctx_type == LLAMA_CONTEXT_TYPE_DEFAULT`; MTP contexts remain ineligible
even when a sidecar retains an indexer.

For this first experiment require all of:

- Architecture QWEN4EXP, actual DEFAULT target context.
- Indexer present, by-order pools with size4.
- Configured n_seq_max1 and actual indexer stream count1.
- No SWA; retain the current full-cache configuration.
- At a removal call, explicit valid sequence0 and no shared layout.

Other architectures, MTP contexts, pool sizes/modes, SWA, multi-sequence/stream,
sharing and all-sequence removal retain the original invalidation path.
A target may be eligible even when MTP inference is OFF: QSA target memory
still exists. Do not label that control MtpDisabled in the new evidence parser.

Initialization should use a private policy helper, similar in shape to the
existing dense-indexer helper but independent of it. Pass primitive eligibility
facts to the helper; preserve actual source context type. A trailing internal
constructor argument with a neutral default lets other hybrid-indexer creation
sites keep the current behavior. Check the actual indexer stream count after
allocation; log the final decision once.

Proposed startup evidence, emitted only when the new switch is explicitly set:

```text
QSA no-op invalidation: requested=1 eligible=1 enabled=1 target=1 kpool=4 streams=1 seq_max=1 reason=target_single_sequence
```

Use the same fixed fields for OFF/ineligible decisions with an explicit reason.
The draft may emit target0/ineligible evidence; the benchmark parser must select
the target1 decision rather than allowing a draft record to overwrite it.
No log spam or per-call normal-mode counters are required.

## Removal algorithm

Only change the bookkeeping in `llama_memory_hybrid_idx::seq_rm`.

1. Preserve recurrent removal first. If it refuses, return false before touching
   indexer/attention, exactly as today.
2. After recurrent success, determine whether this call may inspect the single
   target indexer sequence. Never access an invalid/all-sequence ID.
3. If inspection is needed, read `seq_pos_get(seq_id).size()` before indexer
   removal. This uses indexer metadata and is constant-time.
4. Compute the existing stale position and call `mem_idx->seq_rm` in the same
   order as before. Read the post-removal member count when inspected.
5. If the new opt-in is enabled, per-call scope is eligible and the counts are
   equal, skip this operation's `mem_idx_stale_set` and sharing-invalidations.
   Do not clear, replace or advance a pre-existing stale marker.
6. Otherwise run the original stale-set/sharing path unchanged. A decreased
   count is a real edit; an unexpected increase must fall back conservatively.
7. Always continue to attention removal and preserve its status. Keep the
   existing treatment of indexer return values; do not broaden error semantics.

The KV seq_rm operation removes membership only, so equal before/after counts
prove no members were removed by that operation. This avoids interpreting
negative ranges or duplicate positions in a new range-normalization algorithm.
It also avoids the public hybrid min/max APIs, which report the intersection
with recurrent state rather than actual indexer contents.

Use a small private production helper for the inspect/suppress decision, called
from this path and directly by model-free tests. Inspect the counts when either
the candidate is active or wall diagnostics need them. With the switch disabled
and diagnostics OFF, avoid new metadata lookups/counting; keep the existing
hot path apart from a cached false branch.

The layout update/pooled-key state builder/graph input code is unchanged.
After a clean no-op trim, the next apply takes its existing append path and
marks newly completed pools from the new ubatch as usual. If an earlier real
edit already marked the sequence stale, the next apply must still rebuild and
re-pool it even when a later no-op was suppressed.

## Diagnostics and benchmark evidence

Add per-call observations to the existing memory seq_rm end record in wall
mode. Keep record schema1 and existing refusal classification.

| Field | Meaning |
|---|---|
| idx_cells_before / idx_cells_after | Member counts when inspected; observations, not summable work counters |
| noop_observed | 0/1: inspected counts equal |
| noop_suppressed | 0/1: candidate actually skipped new invalidation |
| stale_marked | 0/1: this operation applied the original stale-set path |
| pending_stale_preserved | 0/1: suppression retained a previously dirty marker |
| stale_before / stale_after | Raw stale positions for structural validation, not CounterSums |

Only the four0/1 event flags belong in diagnostic CounterSums. Count snapshots
must not be added together or used as saved-cell totals. Excluded calls do not
invent inspected/no-op observations. Recurrent refusal still emits the existing
status and returns before any suppression.

Add `Get-Evox2QsaNoopInvalidationEvidence` to Evox2.Benchmark.psm1 and a
`QsaNoopInvalidationEvidence` result field plus CSV/matrix summary columns.
Require exactly one well-formed target decision for explicitly selected0/1,
with matching requested/eligible/enabled/configuration/reason fields. Handle
Missing/Malformed/Mismatch/NotApplied separately; unsupported requested1 is not
Verified merely because the process ran successfully. Preserve native exit
code/metrics/logs, but mark a requested candidate run non-OK on evidence failure.

The existing environment collector captures every LLAMA_ variable; the new
switch is automatically included in condition identity. Add regression checks
for identity differences between target-candidate A/B and for environment
restoration. Clear the new switch in all maintained r4 benchmark plan defaults,
including old dense-indexer plans and diagnostic plans, and in the old native
dense-indexer gate. Reuse the existing runner/recovery infrastructure.

## Planned change list

Paths below are proposed, not created by this document-only commit.

| File / group | Planned change |
|---|---|
| `src/llama-qsa-noop-policy.h` (new) | Independent pure initialization/per-call policy; default-off/exact1, primitive context/cache eligibility and conservative count handling. |
| `src/llama-model.cpp` | Pass actual DEFAULT/MTP context role into the intended hybrid-indexer creation path; avoid enabling the draft or other creation sites. |
| `src/llama-memory-hybrid-idx.h/.cpp` | Cache the decision, log it once, inspect member count when needed and suppress only new no-op invalidation; add diagnostic observations/flags. |
| `tests/test-qsa-noop-policy.cpp` (new) | Exercise the production policy and real llama_kv_cells metadata semantics without a model. |
| `tests/test-qsa-noop-invalidation.cpp` (new) | Actual target QSA contexts A/B, fixed tokens/matched partitions, numeric/state/fallback gate. |
| `tests/CMakeLists.txt` | Register the policy test as model-free CTest; build the model-dependent executable without adding an unparameterized model CTest. |
| `tools/evox2/build/Build-Vulkan.ps1`, `Build-ROCm.ps1`, `Evox2.Build.psm1` | Build both native targets and include executable hashes/runtime identities in the manifest. Build/test Vulkan first; no immediate ROCm rebuild required. |
| `tools/evox2/tests/Test-QsaNoopInvalidation.ps1` (new) | SourceOnly/native policy/RunModelTests modes, verified binaries, preserved logs, real exit codes and completion marker. Default mode must distinguish policy pass from model NotRun. |
| Benchmark module / Measure-LlamaCli / matrix summaries | Separate target startup evidence and status fields, matched-condition/identity handling. |
| `mtp_diagnostics.py` and existing diagnostic tests | Parse/aggregate the new per-event flag counters, retain snapshots and old schema/refusal/recovery behavior. |
| Three new configs `qwen38-r4-qsa-noop-{check,wall,abba}.psd1` | Focused short,256k wall and normal ABBA plans. All MTP ON A/B retain draft omission1. |
| Maintained r4 configs / existing native gate | Explicitly clear the new inherited switch; preserve existing experiments and their evidence. |
| Implementation/results docs, ROADMAP, PATCHES | Actual commands/evidence/status after implementation; no default promotion implied. |

Do not modify server acceptance, common_memory trim dispatch, KV membership
removal, suffix layout reconstruction, GPU kernels or state serialization.

## Native target correctness

Load the PLE16 main model once and share that model across two fresh target
contexts A/B; do not duplicate model allocations. No draft model is needed for
this numerical target gate. Real MTP is exercised later by CLI with the Q8_0
sidecar. Take the new setting at context creation: A0 and B1.

Use f16/FAauto/t4/tb4, context1024, b32/ub32, n_seq_max1,
`n_rs_seq=2`. The production server derives target recurrent rollback capacity
from MTP DraftMax2; copying the old draft test's n_rs_seq0 would be the wrong
primary configuration. Add a focused n_rs_seq0 fallback/control where suitable.
Enable target nextn hidden output with the existing API.

Feed deterministic valid token IDs and identical position/output flags with
exactly matched batch/ubatch partitions. Use prefix lengths covering all
modulo4 pool boundaries and incomplete tails. Verify that the compressed-layer
QSA path and indexer allocation are present, not just that a dense short model
context can be created.

Compare every captured target logits vector and nextn hidden vector:
same nonempty dimensions, all finite, NMSE<=1e-5 (the existing strict gate's
threshold), with maximum absolute difference and stage/arm printed. Do not
relax thresholds on failure; accumulate finite failures and reject gate
completion after reporting them. Nonfinite/structural mismatches fail directly.

Required cases:

- Append-only baseline; no-op at last+1; equal/reversed/finite out-of-range
  intervals; empty-sequence handling with actual cache metadata.
- Three-token verification batches, simulated accepted drafts0/1/2,
  then one continuation token after identical suffix trimming.
- Real suffix removal followed by a no-op **before** continuation: prior
  invalidation must survive in B, with rebuild/re-pooling on the next apply.
- No-op then real edit; repeated no-op; nonzero sequence positions and gaps.
- Same-setting full and PARTIAL_ONLY restore/continuation; restore followed
  by no-op; clear/drop and malformed restore retain original failure/clear
  semantics. Serialized A/B state sizes should be equal, unlike draft omission.
- General prefix/middle edits, position shift/division where supported, physical
  slot reuse/eviction and sharing/seq_cp/seq_keep. Use fresh multi-sequence
  ineligible contexts for actual sharing/fallback checks; do not make a
  single-sequence eligible context fake sharing.
- Recurrent refusal must preserve return status and prevent later mutation;
  unsupported operations are validated against the OFF baseline rather than
  forcing them to succeed.

A/B identical edit histories are the main numerical reference. Any fresh
prefix/replay reference must use the same evaluation partitions; do not repeat
the previous bulk-versus-step false mismatch. Diagnostic-only partition
comparisons, if retained, must be separate from the candidate correctness gate.

Model-free tests cover the actual production decision plus real ordered-cell
metadata: duplicate positions with distinct physical cells, empty/no-op/real
removal, count equality/decrease/unexpected increase, exact1 parsing, role/
pool/stream/sequence eligibility and pending stale preservation. They are not
a copied fake layout implementation. Model-dependent diagnostics establish
that the real wrapper follows that decision.

The Windows script must resolve caller-relative paths before launching native
processes, retain the process handle/ExitCode, check Verified executable/DLL
identity, and require both exit0 and an explicit final PASS marker. Preserve
failure logs and phase/state; SourceOnly must not be reported as model Complete.

## Windows measurement gates

| Gate | Planned runs | Acceptance / next action |
|---|---|---|
| Build and native correctness | SourceOnly; Vulkan BuildOnly with new targets; native policy and target RunModelTests | New manifest verified, target decisions/configuration correct, all numeric/state/fallback cases pass. No long runs before this. |
| Allocation smoke | ctx32768 MTP OFF/new switch1; MTP ON draft omission1/new switch0; MTP ON draft omission1/new switch1 | All OK, target indexer/attention and draft attention retained. New target switch can be active even on MTP OFF. AllocationOnly includes short inference. |
| Short check plan | Five runs: MTP OFF control(new switch1), A-normal, B-normal, A-wall, B-wall | Same mtp-short.txt, ctx32768 capacity,128 generated, greedy/top-k1/seed1234. ON pairs keep draft omission1/DraftMax2/Pmin0. Check text/acceptance and actual no-op/real-edit evidence. |
|256k wall plan | A-wall then B-wall, MTP ON/draft omission1 throughout | Complete diagnostics; candidate evidence Verified. No-op-associated target full rebuilds disappear; real suffix edits still invalidate/rebuild. Compare raw trim history, counters, output/acceptance and scope times. |
| Normal256k ABBA | A1,B1,B2,A2, all MTP ON/draft omission1, diagnostics OFF | Same rebuilt binary/DLLs/workload. Useful repeated TG/generation-time gain, no PP regression supported beyond variation, complete outputs/evidence. |
| Conditional expansion | Focused128k confirmation, then ROCm/short-context coverage as needed | No automatic overnight/full matrix or global default change. Keep prior MTP OFF for overall usage context. |

Use existing R4QsaUnionVulkan/UnslothPle16/UnslothMtp/input keys.
Long plans retain ctx262144/input256k,512 generated, temperature0.2/top-p0.8/
seed1234/ignore-eos, f16/b2048/ub1024/t4/tb4/ngl999/CpuMoe0/FAauto,
fit/reasoningoff/cache RAM0/checkpoints0t, MoE legacy1/GET_ROWS128x4=0/union1,
cooldown10s and StopOnError. The new switch is0 in A and1 in B;
old draft omission is1 in both. Explicitly clear other experiment/profiler
variables and restore the caller's environment.

The new target plan's A reproduces the **already optimized** draft-omission B,
not the original slow MTP baseline. Do not compare target-candidate B against
old draft-omission A and attribute the combined gain to this patch.

With the same218-round history as B-wall, A should again show217 target full
rebuilds. B should retain95 after actual suffix edits and suppress the122
unnecessary subsequent rebuilds (123 observed full-accept trims, final one has
no next decode). These exact counts are conditional on identical history;
classify by actual before/after counts and timestamps rather than hardcoding
them as a gate for every prompt. Required dirty-state preservation cases can
legitimately rebuild after a suppressed no-op.

The two long wall runs cost about40 minutes and the normal four about80 minutes
in previous collections; these are planning estimates. Review wall results
before starting normal ABBA. No new MTP OFF long run, sync pair, ROCm matrix
or Unsloth mix build is needed to isolate this candidate.

## Completion and priority

Retain default OFF until correctness and normal performance pass. A useful
target TG gain does not establish MTP total-latency advantage: current
draft-omission B is TG20.185 versus earlier normal OFF19.76, while PP229.65
versus265.02 still adds about148 s to a fresh255k-prompt request.

After this bounded no-op candidate, separately design real suffix-prefix
layout reuse with independent CPU-layout/pooled-key invalidation. MTP PP
attribution and ROCm long-context PP scaling follow; COMMON-005 decode remains
deferred. The already validated draft omission's128k confirmation remains a
coverage gate before wider use.

Code/tests/plans and the runnable implementation document are delivered.
Review Windows build/native results before longer measurements; the new
scripts/configs and their commands are in the implementation document.

Related:
[target source investigation](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md),
[draft omission normal ABBA](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md),
[roadmap](ROADMAP.md).
