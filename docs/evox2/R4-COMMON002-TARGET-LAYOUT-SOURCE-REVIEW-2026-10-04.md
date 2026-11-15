# r4 COMMON-002: target layout source investigation

Reviewed branch `r4/upstream-refresh-20261002` at
`3400c189e3947953fe030ed70003d399b4d06b70`; upstream remains
`bed0a856606ee4a24a164066f73d2379447033f5`.
Status: source investigation complete. No runtime code/config/default changes
or Windows rebuild are included in this recording.

The subsequent [target no-op implementation plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md)
is now prepared for review. It specifies a separate default-off target switch,
actual membership-count comparison, pending stale preservation, numeric target
QSA tests and short/wall/normal A/B with draft omission1 fixed. Runtime code,
new native targets/scripts and new benchmark plans are not delivered yet.

## Findings and first candidate

The retained target layout cost has two distinct causes:

1. **No-op removal still invalidates layout.** Server speculative verification
   calls the shared memory trim even after full acceptance. No target cells
   are removed in that case, but hybrid-indexer memory sets a stale marker
   unconditionally. The next decode copies and scans the entire target layout.
2. **Real suffix removal also rebuilds the whole prefix.** The pooled-key stale
   position already preserves pools before the edited suffix, but CPU layout
   update treats any stale position as a reason to discard the complete
   cells/pools mapping and reconstruct it from the ordered metadata set.

In omission-ON B-wall, the5.499980 s target generation layout scope consists
of3.092231 s following full acceptance/no-op trims and2.407742 s following real
suffix removals (plus7 microseconds on the initial clean append).
This supports a small first candidate: detect whether indexer membership
actually changed during a single-sequence removal, and suppress *new*
invalidation only when it did not. Real suffix maintenance is a separate,
more complex second candidate.

## Verified sources

Core source files were checked against the reviewed remote Git tree. Where the
local sparse checkout differed or omitted a file, the exact remote blob was
read separately; stale local KV-cache/header copies were not used for conclusions.

| Source | Relevant functions / evidence |
|---|---|
| `tools/server/server-context.cpp` | Speculative verify/accept block, `target_trim`, `slot.prompt.tokens.pos_next()` |
| `common/common.cpp` | `common_memory::seq_rm` applies the operation to target and draft |
| `src/llama-memory-hybrid-idx.cpp` | `seq_rm`, stale helpers, `kpool_layout_update`, context `apply/next`, `kpool_build_state`, state restore/drop |
| `src/llama-memory-hybrid-idx.h` | `mem_idx_stale`, `POS_CLEAN`, independent layout/state ownership |
| `src/llama-kv-cache.cpp` | `seq_rm`, `prepare`, `apply_ubatch`, physical-cell reuse/prefix purge, stream copies and state restore |
| `src/llama-kv-cells.h` | Ordered per-sequence `seq_pos` set and membership removal |
| `src/models/qwen4exp.cpp` | QSA uses indexer pools; `indexer_kpool_by_order=true`; ratios define pool size |
| `tests/test-mtp-dense-indexer.cpp` | Existing correctness harness scope and batch-partition limitation |

The source is available at the
[reviewed commit](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/3400c189e3947953fe030ed70003d399b4d06b70).
This is a pinned-source investigation; no latest-upstream comparison is
required to establish the local cost.

## Call path and no-op invalidation

The server computes `n_rollback = drafted + 1 - accepted.size()` and handles
checkpoint restore/replay if needed. It then updates accepted prompt tokens
and invokes `slot.mem.seq_rm(slot.id, slot.prompt.tokens.pos_next(), -1)`
inside the target_trim scope, whether acceptance is partial or full.

With two drafts fully accepted, the removal starts immediately after the last
verified target position. It removes no target KV cells. This is inferred from
the verified server token/position update, not from a dedicated no-op counter.

The common-memory wrapper applies the same range to target and draft.
Skipping this whole server/common call would broaden the change to recurrent/
draft handling and other models; it is not the preferred first patch.

Hybrid-indexer `seq_rm` currently:

1. Calls recurrent removal first and returns false immediately if it refuses.
2. Computes an indexer stale position from the requested lower bound.
3. Calls indexer KV removal, then always calls `mem_idx_stale_set`.
4. If layout sharing was active, additionally stales all sequences.
5. Calls attention removal and preserves its return status.

The indexer KV removal reports success rather than a removed-cell count.
Its loop only removes sequence membership; an empty range or a range beyond
the last member changes nothing in that sequence's ordered set. The current
caller does not distinguish that success from an actual edit.

The next successful memory-context apply invokes `kpool_layout_update`.
Its append path requires `mem_idx_stale[s] == POS_CLEAN`, and its rebuild
condition is true whenever `mem_idx_stale[s] != POS_CLEAN`. Thus even an
unchanged sequence after a full-accept trim is fully rebuilt.

## Log attribution

Input evidence is the previously validated256k wall ZIP
`20261004-151130-034-qwen38-r4-mtp-dense-indexer-wall.zip`, with MTP ON in both
arms. B omits only the dense draft indexer; target indexer remains.

Reclassification uses server target_trim records and target generation layout
records sorted by timestamps. Each later layout is associated with the
immediately preceding completed trim. All218 target generation seq_rm records
have the corresponding target_trim as resolved parent. All target generation
layouts report cache_safe=1.

Both arms have218 trims: full acceptance123, partial47, rejection48.
The final trim is full acceptance and has no subsequent generation decode,
so it contributes no next-layout record. The217 rebuilds therefore divide into
122 following full acceptance and95 following partial/rejected drafts.

| Target generation layout | A-wall calls / seconds | B-wall calls / seconds | Copied cells in either arm |
|---|---:|---:|---:|
| Initial clean append | 1 / 0.000008 | 1 / 0.000007 | 0 |
| Following full acceptance / no-op | 122 / 2.820295 | 122 / 3.092231 | 31,164,117 |
| Following real suffix removal | 95 / 2.207619 | 95 / 2.407742 | 24,265,693 |
| Total | 218 / 5.027922 | 218 / 5.499980 | 55,429,810 |

The no-op-associated rebuilds are about56.22% of217 rebuild calls and56.22%
of B's target layout time. Scan steps similarly divide into38,955,101 after
full acceptance,30,332,078 after real suffix edits, plus4 on the clean append.

These are CPU scope times from wall mode. They identify avoidable work; they
do not promise an exact3.09 s normal-time reduction or a specific TG value.
The normal ABBA already validates draft omission at15.220 ->20.185 tok/s;
no new GPU attribution measurement is needed to select this source candidate.

## Candidate 1: suppress invalidation when membership did not change

The lowest-impact approach is to leave all memory removal calls/order/status
handling intact and change only hybrid-indexer invalidation bookkeeping.

For a valid, explicitly scoped single sequence, record the indexer sequence's
ordered-set size before and after `mem_idx->seq_rm`. That function can only
remove membership in this operation, so equal sizes mean no indexer member
was removed. Set size is constant-time; no new full-prefix scan or vector copy
is required. Only when the size decreases should this path set a new stale
marker and perform the existing sharing invalidation.

Pool input/mask/representative construction still runs through set_input_kpool
and kpool_build_state; this first candidate does not optimize those other CPU
scopes or change the target QSA kernels.

An alternative is a normalized range lookup in the ordered set before removal.
It must honor lower-inclusive/upper-exclusive semantics, negative bounds and
duplicate positions. Before/after membership count is simpler for this bounded
candidate and uses the actual removal result.

Required scope/invariants for an implementation plan:

- Keep recurrent refusal handling first, indexer removal and attention removal,
  and their existing success/failure semantics. Do not early-return the whole
  hybrid operation merely because the indexer has no members in the range.
- Suppress only *new* invalidation. A pending stale marker from an earlier
  edit/restore must survive unchanged; never clear it in this fast path.
- Keep existing conservative behavior for all-sequence removal, unsupported
  model/cache configurations and any operation whose effects cannot be proved.
  The first experiment can restrict eligibility to the intended QWEN4EXP,
  by-order, single-stream/unshared configuration with an independent default-off
  opt-in. Final toggle/eligibility design belongs to the implementation plan.
- Observe actual indexer metadata, not public hybrid sequence min/max APIs:
  those APIs report attention/recurrent range intersection, not indexer contents.
- A zero-size-change result cannot imply that recurrent/attention handling was
  unnecessary; their calls still run.
- Candidate evidence/counters should distinguish no-op suppression from real
  edits and report whether pre-existing invalidation was preserved.

This should allow ordinary incremental append after full acceptance rather
than forcing a full rebuild. It leaves the95 real suffix rebuilds unchanged.
The indexer/attention seq_rm cell loops themselves also remain; their CPU time
is small compared with repeated full layout copies.

## Candidate 2: preserve layout prefix on real suffix removal

QWEN4EXP groups pools by ordered-cell rank, with the measured model pool size4.
A pure suffix removal leaves the surviving cells and complete prefix pools
unchanged when sequence sharing, stream assignment and first-member identity
are unchanged. In that restricted case:

- Truncate the cached cell vector at the first removed ordered member.
- Retain only complete surviving pools. In by-order mode with K cells per pool,
  the retained count is floor(surviving_cells/K).
- Reset the append scan boundary to the end of those complete pools; preserve
  the incomplete tail for subsequent append. Do not retain a representative
  that belonged to a removed cell.
- Append only subsequent new metadata pairs. Use ranks/cell identities, not
  position/K, because multiple cells may share a position.

However, trimming the vector alone cannot activate the existing append path:
the same `mem_idx_stale` currently means both CPU layout invalidity and pooled
GPU key invalidity. The optimization must distinguish layout dirtiness from
pooled-key stale positions (or add an equally explicit edit classification).
Real suffix edits must retain their pooled-key stale marker, so the next batch
re-pools affected complete pools from valid raw key rows. Setting POS_CLEAN
merely to bypass the CPU rebuild would risk stale pooled-key reads.

Full rebuild remains required for unsupported/general changes: prefix/middle
edits, first-member changes, sharing/copy/keep, position shift/division, full
state restore/drop/clear and stream changes. Physical slot reuse can trigger
prefix purge in KV apply_ubatch without a hybrid-level stale-set call.
Therefore size/min equality alone does not prove an unchanged prefix after
arbitrary writes. A suffix fast path needs explicit mutation provenance and
fallback checks for eviction/remapping, rather than assuming every stale
position is a harmless suffix.

A pending full invalidation must dominate a later suffix hint; multiple edits
must preserve the earliest affected rank/position. Sharing must be re-derived
where the existing path requires it. Full restore continues to adopt attention
slot information for the indexer, and half-failed restores must retain the
existing drop/clear behavior.

## Validation required for the first implementation

The current dense-indexer native test mainly compares two **draft** contexts
with identical target hidden traces. It confirms target indexer retention but
does not numerically test a changed target QSA layout. It cannot be the sole
correctness gate for this next patch.

| Gate | Required evidence |
|---|---|
| Model-free metadata/invalidations | No-op at max+1, empty/equal/reversed ranges, empty sequence and finite out-of-range interval; real suffix/middle/prefix removal; pending stale preservation; recurrent refusal; negative/all-sequence fallback. Compare actual production helper/metadata, not only a copied algorithm. |
| Target model correctness | Two fresh target contexts, candidate OFF/ON, identical tokens and **matched batch partitions**. Compare logits and nextn hidden outputs across no-op, reject/partial/full edits; cover every modulo4 pool boundary, incomplete tail and physical cell reuse. |
| State and conservative paths | Same-setting full/PARTIAL_ONLY restore, failed/partial restore clear behavior, sharing/seq_cp/seq_keep, position changes and fallback conditions. Dirty/no-op classification must not erase a required full rebuild. |
| Real CLI short gate | MTP OFF control and MTP ON with draft omission=1 throughout the target-candidate A/B. Greedy fixed prompt, real rejection/partial/full acceptance; output/acceptance and explicit candidate evidence. |
| Focused256k wall A/B | Keep draft omission=1 in both arms; toggle only target candidate. Complete reports, matched conditions/output/acceptance. No-op-associated target full rebuilds disappear while real edits still rebuild in candidate1. |
| Normal256k ABBA | Diagnostics off, same binary/DLL identity, draft omission=1. Confirm useful repeated TG/generation-time gain and track PP/total time. |

The previous native test had a false mismatch from bulk-versus-step input
partition differences. Target reference comparisons must match partition
shape, independent of cache edit, before interpreting a difference as a bug.
Pool/mask/tail/representative metadata comparisons are also valuable for
candidate2, whose structural changes are broader.

## Decision and current priority

Prepare the implementation plan for candidate1 first, with separate opt-in,
target correctness tests and focused A/B. It addresses roughly3.09 s of the
residual5.50 s in B-wall with a smaller semantic change than suffix caching.
Candidate2 follows only after that result; keep CPU/GPU invalidation distinct.

No additional sync, ROCm or full overnight matrix is needed before preparing
the plan. Focused128k confirmation of the already validated draft omission
remains an expansion gate; it need not block this target source investigation.
MTP PP overhead and ROCm long-context PP scaling retain their agreed order.
COMMON-005 historical decode remains deferred.

Related:
[normal draft-omission ABBA](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md),
[wall work removal](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md),
[earlier layout review](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md),
[roadmap](ROADMAP.md).

## Approved candidate implementation

Candidate1 is now implemented as a separate default-off target opt-in, with
actual membership-count checks and preserved pending stale state. Code, native
numeric/fallback tests, Windows gate and isolated short/wall/normal plans are
delivered. Local checks pass; Windows Vulkan build/model results must be reviewed
before additional measurements. This does not validate the expected time saving.
See [implementation and commands](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md).
