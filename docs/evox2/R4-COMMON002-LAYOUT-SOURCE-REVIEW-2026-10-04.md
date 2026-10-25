# r4 COMMON-002: layout source review and first optimization candidate

Reviewed source: `r4/upstream-refresh-20261002` at
`4051671d23d03d0a94b8978ddc9cfd0934e0cc93`, pinned upstream
`bed0a856606ee4a24a164066f73d2379447033f5`.

Status: source investigation complete; diagnostic relative-path repair is
confirmed on Windows. The guarded dense-draft indexer candidate is now
implemented after user approval. The 14:50 Windows Vulkan native model/state/
rollback and A/B gate passes after harness corrections. Allocation/short CLI
also passes 8/8 runs and confirms removal of draft indexer/layout/pool work;
the 256k wall pair also passes with TG +35.16% and matching output/acceptance.
Draft layout 9.767278 s is removed; target layout remains 5.499980 s.
Normal 256k ABBA also passes: TG mean 15.220 -> 20.185 (+32.62%), matching
response/acceptance and effectively unchanged PP. Proceed with separate target
suffix/no-op source investigation; retain focused 128k confirmation before
expansion. MTP PP overhead is unresolved and the source default remains OFF.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md)
and [implementation and commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md)
and [the design](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md).

The subsequent [target layout source investigation](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md)
is now complete. It separates B-wall's residual 5.499980 s into 3.092231 s
following full-accept no-op trims and 2.407742 s following actual suffix
removal. The next bounded proposal is no-op invalidation suppression, keeping
real removal calls and pending stale state; suffix-prefix reuse is a separate
candidate requiring distinct CPU-layout and pooled-key invalidation.

## Decision before further measurement

Use the completed wall collection to select the first bounded source change.
Additional sync, ROCm or Unsloth mix collection is not a prerequisite: the
measured CPU layout cost already identifies a concrete candidate. Keep those
comparisons available if a residual bottleneck remains after this candidate.

The user successfully recovered the existing matrix with an absolute path:
all three reports are Complete, with 16,487 / 19,861 / 13,734 events; all
existing runs are OK and no model was executed again. The supplied Windows
test run passes 14 tests with three native-helper tests skipped because g++
is unavailable. These skips are unrelated to path resolution or recovery.

## Two source findings

### Dense MTP does not consume its indexer, but memory maintains it

The supplied GGUF has 49 compression-ratio entries. Its trunk includes ratio
4 layers; MTP layer 48 has ratio 0. The pinned `qwen4exp` graph asserts exactly
one MTP block and selects `il = hparams.n_layer()`.

| Source and function | Behavior | Consequence for this sidecar |
|---|---|---|
| `src/models/qwen4exp.cpp`, `load_arch_hparams` | Derives `indexer_kpool` from positive ratios across all layers | Trunk ratios keep the global pool size at 4 even though MTP layer 48 is dense |
| `src/models/qwen4exp.cpp`, `graph_mtp` | Registers pool input only when indexer context exists, pool size is positive and this MTP layer's ratio is positive | Ratio 0 skips the pool input; dense draft attention does not use indexer keys |
| `src/llama-model.cpp`, `llama_model::create_memory` | For QWEN4EXP MTP, selects attention and indexer layers with `il >= hparams.n_layer()`; indexer selection does not test compression ratio | Allocates an indexer cache for the dense MTP block |
| `src/llama-memory-hybrid-idx.cpp`, constructor | Creates `mem_idx` whenever `filter_idx` is non-null | The unused cache has per-token cells and its own maintenance |
| Same file, `llama_memory_hybrid_idx_context::kpool_track` and `apply` | Tracks pools when `mem_idx` exists, pool size is positive and batch streams exist; it does not inspect graph consumption or per-layer ratio | Each successful draft batch updates CPU layout and pool state despite dense attention |

The earlier ratio check fixed the graph's unused-input assertion. It did not
disable the memory-side cache or CPU layout work.

### Sequence removal causes full CPU layout reconstruction

The second chain affects both target and draft, even though only the target
needs QSA for this model:

1. Draft generation/catch-up and target verification trim speculative history
   through `seq_rm`.
2. `llama_memory_hybrid_idx::seq_rm` first honors recurrent-cache refusal,
   then removes indexer cells and marks the affected sequence stale. It marks
   stale even when the indexer removal changes no cells; shared layouts can
   invalidate all sequences.
3. The next successful memory-context `apply` calls `kpool_layout_update`.
4. A stale sequence takes `sq.cells.assign(sp.begin(), sp.end())`, clears its
   pool list, resets `j_next` and reconstructs the layout from the full visible
   history. A suffix edit therefore defeats the append-only fast path.

The GPU pooling state already uses the earliest stale position to limit
re-pooling. That incremental GPU behavior does not prevent this separate
CPU vector/list reconstruction. Restoring the historical COMMON-004 GPU pool
cache would not address the identified source chain.

The source matches the wall results: 256k ON has 435 draft full/stale rebuilds,
111,114,370 copied draft cells and 9.901350 seconds of draft layout CPU time.
Target layout contributes another 5.113921 seconds. These are observed
diagnostic scope times, not a forecast that removing the indexer saves exactly
9.9 seconds in normal generation. Cache allocation and scheduling may also
change; unprofiled A/B is the performance gate.

## First proposed implementation: omit the unused dense-draft indexer

Make the memory-creation decision once, inside `llama_model::create_memory`.
Use a default-off opt-in control for matched A/B; proposed name:
`LLAMA_MTP_SKIP_DENSE_INDEXER=1`. The switch is now delivered, default OFF;
the sections here retain the source rationale for that implementation.

Initial eligibility must require all of:

- Architecture is QWEN4EXP and context type is MTP.
- The currently supported single MTP block is present: `n_layer_nextn == 1`
  and `hparams.n_layer()` is within `n_layer_all`.
- That block's compression ratio is exactly zero.
- The opt-in control is enabled. Unset/off retains the existing allocation.

When eligible, set **`filter_idx = nullptr`** before constructing
`llama_memory_hybrid_idx`. An always-false layer filter is insufficient:
`llama_kv_cache` creates cell metadata before applying per-layer tensor
filters, so that approach would retain the unused bookkeeping.

Retain the `llama_memory_hybrid_idx` wrapper and derived context. The graph
casts to that context type. Its constructors and operations already guard
the null-indexer case; `kpool_track()` then returns false. Preserve attention
K/V, its slot preparation and sequence trimming, recurrent-cache handling,
hidden-state transfer, acceptance and catch-up semantics. The empty recurrent
input still has to be allocated by `graph_mtp`.

Do not zero the model's global `indexer_kpool`: trunk QSA still needs it.
Positive-ratio MTP and any future unsupported/multiple-block configuration
must retain the old path. If multi-block QWEN4EXP support is added later, revisit
the eligibility rule against every graph-selected block; never extrapolate
the current single-block rule silently.

Full state serialization appends an indexer section only when `mem_idx`
exists; PARTIAL_ONLY checkpoints exclude it. Same-configuration save/restore
and rollback need validation. Cross-configuration full-state compatibility
is not established and must not be promised; use fresh runs/cache files for
the first A/B and investigate existing cache-identity/restore checks before
supporting reuse between the two settings.

## Focused validation order after implementation

| Step | Conditions | Gate |
|---|---|---|
| Eligibility and construction | Opt-in off/on; zero vs positive MTP ratio; target context; other architecture; absent/multiple MTP blocks | Omit indexer only for the supported dense MTP case. Positive-ratio and target QSA keep their cache. Allocation log/diagnostic metadata makes the selected path explicit. |
| Windows allocation/short correctness | Same rebuilt binary; MTP OFF control, MTP ON opt-in off/on; existing short deterministic prompt | AllocationOnly and inference succeed; compare generated tokens, acceptance and rollback/catch-up across rejected, partial and full drafts. Investigate divergent logits/state rather than accepting text differences blindly. Check same-setting state restore separately. |
| One focused 256k wall A/B | MTP ON with opt-in off/on; fixed existing model, draft, seed, sampling, DraftMax, MoE/union settings | Candidate has no draft indexer/layout/pool-state work. Target layout remains present; complete reports and comparable acceptance verify the intended scope. Compare PP and TG; do not add inclusive parent times. |
| Normal 256k ABBA | `LLAMA_MTP_DIAG=off`, MTP ON throughout; toggle only the candidate | Same binary/artifact identity; correctness gate passed; judge actual TG and PP+TG gain. Keep MTP OFF as the preserved overall reference, not as the candidate A/B control. |
| Expansion only after useful gain | Normal 128k confirmation, then short-context cost and ROCm as needed | Avoid a repeated overnight/full matrix before the bounded candidate proves useful. |

The existing 9.9-second draft layout component is enough to prioritize this
change. If it succeeds, separately design target suffix/no-op layout updates.
That second change must account for real removed cells, pooled tail boundaries,
first-position changes, duplicate positions, shared sequences, streams and
restore invalidation. It must not bypass recurrent rollback merely because an
indexer removal looks empty. A general layout rewrite is outside the first
candidate.

MTP PP overhead and ROCm long-context PP scaling remain next in the agreed
order. The first candidate may reduce some draft-prefill bookkeeping, but
does not remove draft inference or hidden-state transfer; its PP benefit
must be measured. COMMON-005's ROCm decode port stays deferred.

## Diagnostic script path repair and checks

The failing relative path was resolved as
`C:\Windows\System32\evox2-logs\matrix\...`, despite the PowerShell prompt being
at the repository. `[IO.Path]::GetFullPath` uses the .NET process directory,
which may differ from PowerShell's current location.

Both `Repair-MtpDiagnostics.ps1` and `Summarize-MtpDiagnostics.ps1` now resolve
their input with `(Resolve-Path -LiteralPath ...).ProviderPath` before passing
an absolute path to Python. They keep progress messages on `Out-Host`, so no
extra matrix row is returned through the success pipeline.

The PowerShell fixture now deliberately separates shell and process
directories, invokes both wrappers with relative paths, checks empty success
output and verifies recovery keeps the performance metric unchanged. It
restores the process directory and shell location afterward.

Local verification: all 14 Python/native helper tests pass, with no skips.
PowerShell is unavailable in this environment. The user subsequently ran the
updated `Test-MtpDiagnostics.ps1` on Windows successfully: parsing, artifact
verification, relative paths, success pipelines and recovery all pass; 14
Python tests report 11 passing and three g++ helpers skipped. The relative-path
prerequisite is complete. No GPU rebuild, inference rerun or repeated repair
of the already recovered real matrix is required for this script-only change.

Related evidence:
[wall diagnostics](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md),
[implemented diagnostics](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md),
[roadmap](ROADMAP.md).
