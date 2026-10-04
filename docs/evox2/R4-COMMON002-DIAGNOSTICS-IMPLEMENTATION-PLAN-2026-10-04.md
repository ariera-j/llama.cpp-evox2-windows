# r4 COMMON-002: MTP diagnostics implementation plan

Recorded: 2026-10-04 JST. Historical design proposal. **Diagnostic code is now
implemented; Windows Vulkan allocation/short gates pass, long-context diagnostic
collection is pending.** See the
[implementation record and Windows handoff](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-2026-10-04.md)
for delivered behavior, differences from this proposal and completed checks.
Source reviewed: `29d832821e8366bed450aba8ee1b36a6eb49c86a` on
`r4/upstream-refresh-20261002`; upstream remains
`bed0a856606ee4a24a164066f73d2379447033f5`.

## Goal and decision to support

Explain the 256k MTP TG loss before changing an inference algorithm. Vulkan
128k/256k has almost identical acceptance and 218 draft rounds, while generation
rises 22.203 -> 33.518 s. The existing draft-hook timer accounts for only
3.845 s of this increase; 7.470 s lies outside it.

The implementation must distinguish:
1. Draft generation and dense draft catch-up after target batches.
2. Main-model verification versus ordinary one-token decode.
3. CPU sequence edits and full-history pool-layout reconstruction.
4. Hidden-state synchronization, CPU copies and subsequent draft input handling.
5. Actual Vulkan attention branch selection for small-query verification.

Use these measurements to choose one bounded candidate: unused dense-draft
indexer management, suffix-only layout maintenance, small-query verification
dispatch, or dense draft/catch-up work. This stage changes observation and build
identity only. It does not remove caches, alter rollback, force QSA, change
DraftMax, change union selection or promote defaults.

## Source findings that determine the design

- `common_speculative_process()` has no existing time counter.
  `common_speculative_impl_draft_mtp::process()` invokes draft decode after
  target batches and copies verified hidden rows. Existing `dur(b,g,a)` excludes it.
- The server calls target `llama_process()` and already synchronizes when
  `has_output` is true. Prefill without outputs can return with GPU work pending.
  Instrument the process call and existing wait separately, inside
  `queue_tasks.yield_to_queue`; do not count queue scheduling as target compute.
- `llama_get_embeddings_nextn()` and its `_ith` variant synchronize the context
  before output reordering. Their elapsed time includes waiting and is not a
  pure host-copy measurement.
- `seq_rm()` can stale the indexer layout. `kpool_layout_update()` may copy all
  sequence cells and rebuild CPU pool lists, while `kpool_build_state()`
  normally marks only affected GPU pools. These need separate counters.
- Dense MTP still has an indexer memory wrapper/cache in the current factory.
  Diagnostic registration must distinguish target and draft memory objects.
- Vulkan grouped union is eligible for 2+ queries; DraftMax=2 verification can
  contain up to three queries. Eligibility or the first prefill activation log
  does not establish the selected verification branch.
- Both overnight build manifests show `Configure.Executed=false` and
  `Build.Executed=true`. Both already include SHA-256 for the major DLLs.
  BuildOnly skips explicit configure; generated build info is produced at
  configure time, with the existing dependency watching the Git index.
  This is a plausible stale-metadata mechanism; it is not proof that the
  runtime source or DLLs were old.

## 1. Opt-in controls and timing semantics

Proposed new environment variable: **`LLAMA_MTP_DIAG`**.

| Value | Behavior | Interpretation |
|---|---|---|
| unset / `0` / `off` | Disabled | No diagnostic timers, per-operation formatting, logs or added synchronization |
| `wall` | CPU counters and wall-time scopes; preserve existing waits | Closest to normal execution, but asynchronous work can finish in a later scope; diagnostic logging still adds overhead |
| `sync` | Same records, plus deliberate context drains at target/draft evaluation boundaries | Attribution experiment; changes overlap and throughput, not a performance baseline |

Invalid values emit one warning and disable the feature. Read the setting once
per relevant component, not per token. Print mode and schema at startup. This
control is backend-independent and is captured by the existing benchmark
environment prefix filter (`LLAMA_`).

In sync mode:
- Measure a pre-boundary drain separately as `pending_wait_us`; do not silently
  charge earlier submitted work to the next operation.
- Measure the process call and its completion wait separately.
- Retain existing target-output/getter waits; do not wait twice unnecessarily.
- Drain only the context being measured. Do not synchronize per CPU layout
  loop, per tensor, or all devices globally.
- A sync-scope elapsed time includes CPU submission plus completion wait.
  It is **not** GPU kernel time; kernel attribution requires a scoped GPU profile.

The disabled branch must not construct timing scopes or collect detailed
counters. Small per-context diagnostic state is created only when enabled.
Use private helpers for common/server and library memory instrumentation;
do not add public C APIs or a general telemetry framework solely for this work.

## 2. Events and accounting

Use one stable prefix, e.g. `mtp_diag v=1`, at an information log level.
The names and fields below are the proposed schema, not current log output.

| Field | Meaning |
|---|---|
| `domain`, `event`, `id`, `parent` | Unique event identity within its domain and explicit nesting where available |
| `ctx`, `mem`, `role` | Context/memory identity and target/draft role; register the relationship at startup |
| `task`, `slot`, `seq`, `phase` | Request/sequence and prompt, generation, mixed or unknown phase |
| `t0_us`, `t1_us`, `thread` | Monotonic timestamps and execution thread for correlation |
| `n_tokens`, `n_query`, `pos_first`, `pos_last` | Actual batch/query shape and position range |
| `elapsed_us`, `pending_wait_us`, `completion_wait_us` | Distinct wall/CPU/wait observations |
| `rc`, `complete` | Return status and whether the event completed normally |

Emit begin/end for outer evaluation scopes so internal memory/backend records
can be associated with their active call. End records contain measured values;
formatting/emission occurs outside the measured operation. Add a task summary
for successful or failed completion; destructors may flush orphaned summaries
but are not the primary completion signal.

Accounting rules:
- Keep inclusive parent totals and exclusive child totals separate. Do not
  add `process_total` to its hidden-copy and draft-decode children.
- Do not add an existing getter wait to a newly introduced wait for the same
  work. Record which boundary consumed the pending work.
- Report unassigned generation time; do not rename it target-model time.
- Determine phase from server request/slot state at the call boundary, not from
  query count. Mixed batches must be labeled mixed; never divide them into
  invented per-slot timings.
- First supported attribution scope is the existing serial CLI workload with
  one slot. Multi-slot inference remains functional; ambiguous attribution
  stays mixed/unknown. No cross-DLL thread-local assumption.
- Use the shared `ggml_time_us()` monotonic clock and explicit maps for correlation.
  Log memory identity through the same memory-interface pointer returned by
  `llama_get_memory()`, not an unrelated embedded cache address. If backend worker
  execution cannot be matched unambiguously, retain it as unmatched.
- Do not log every cell, tensor element, hidden value or full vocabulary vector.
  Counters are accumulated in existing loops. Expose completeness and unmatched
  records in the summary rather than silently dropping them.

## 3. Instrumentation map

| File / function | Proposed change |
|---|---|
| `tools/server/server-context.cpp`: drafting, target decode, process and post-decode | Register target/draft contexts and memory handles; tag phases; measure draft call, target call/existing sync, draft-state trim, catch-up call, acceptance/sampling and target suffix trim. Put compute timers inside queue callbacks; measure other host work separately. |
| `common/speculative.cpp`: MTP `process()` | Record total catch-up, target hidden getter, batch construction/`set_embd`, each draft `llama_process()`, verified-row getter/copy and pending-row copy. Include actual token/head counts and failures. |
| `common/speculative.cpp`: MTP `draft()` / `accept()` | Subdivide existing draft-hook work into input preparation, draft evaluations/waits and sampling/hidden carry where practical; preserve the existing statistics line. Record accepted counts without changing acceptance decisions. |
| `src/llama-memory-hybrid-idx.cpp/.h`: `seq_rm()` | Measure recurrent, indexer and attention removal as nested CPU operations; record requested range, success, stale position and memory identity. Avoid a diagnostic-only whole-history scan to count removals. |
| Same: `kpool_layout_update()` | Per memory/sequence, count append versus full rebuild, stale/size-change reasons, copied cells and actual visited cells/pools in the existing loops; report CPU time and cache-safe/shared state. Calls beyond `apply()` must also be counted. |
| Same: `kpool_build_state()` / `apply()` | Record state-building CPU time, real pool count, logical `n_new`, padded `n_new_g` and cache safety. These are planned pool work, not measured GPU recomputation counts. |
| `ggml/src/ggml-vulkan/ggml-vulkan.cpp`: FA / graph compute | Count the branch actually chosen: union, sparse fallback or dense fallback, with tensor name/layer, query/KV counts and backend graph invocation. Increment after branch selection, not at eligibility checks or reservation. Aggregate per graph invocation. |
| `common/mtp-diag.h` and `src/llama-mtp-diag.h` (proposed private helpers) | Small mode/timer/log helpers appropriate to each library; one documented record schema, with no cross-module global timing state required |

Vulkan records identify command construction/dispatch selection, not completed
kernel duration. Check that counters follow each executed backend graph call,
including llama graph reuse; do not disable graph reuse to make counters easier.
A layer/tensor identifier distinguishes dense draft attention from main QSA.
Actual union utilization and compacted-row count require additional GPU data;
do not introduce a per-dispatch readback in the first patch.

PP events are retained using the same scheme. They will inform the later MTP PP
investigation, while the first report and decision focus on steady TG.
Host input preparation/getter timing does not separately prove device upload
bandwidth; defer deeper backend-copy instrumentation until a measured need.

## 4. Narrow build-identity correction

Keep current compiler, toolchain, backend options and dependency cache behavior.

1. In `Evox2.Build.psm1`, add a shared metadata-refresh/validation helper used
   by `Build-Vulkan.ps1` and `Build-ROCm.ps1`.
2. Before a real `-BuildOnly` build, run a cache-preserving CMake configure:
   `cmake -S <RepoRoot> -B <existing BuildDir>`. Require the cache to belong to
   this source/backend and preserve generator/toolchain/options. Capture this
   action as metadata refresh in the manifest; do not pretend the full configure
   path ran. This refresh may execute normal CMake checks; it is not a clean build.
3. Full configure/build keeps its existing path. After a successful build,
   compare embedded short commit with the build-start Git HEAD prefix, and
   verify source identity did not change mid-build. Dirty state stays explicit.
   Fail a newly built benchmark artifact on an unexplained mismatch.
4. `-ConfigureOnly` remains configure-only. `-ManifestOnly` remains read-only
   with respect to binaries: expose stale/mismatched metadata as a warning/
   validation status, not a claim of a successful rebuild. `-SkipSmoke` must
   not accidentally bypass identity validation needed for a benchmark build.
5. Reuse existing `Artifacts` SHA-256s. Extend the bounded artifact enumeration
   to installed `ggml-cpu*.dll` variants where applicable, deduplicated.
   Do not hash unrelated system/driver directories.
6. In `Get-Evox2LlamaIdentity()` / measurement startup, compare required local
   runtime artifact identities against the supplied manifest and record the
   result. Verify required DLLs before measured inference; prevent a known
   mismatch from producing a trustworthy-looking benchmark. A missing legacy
   manifest remains explicitly unverified rather than silently upgraded.
7. Add a backend artifact-set digest to the condition fingerprint when verified,
   alongside the existing launcher identity. Keep old CSV/result readers working.

Avoid modifying upstream CMake Git dependency logic in the first patch; explicit
wrapper refresh addresses the observed BuildOnly path and is easy to verify.
No build number hard-coding and no version-label rewrite without rebuilding.

## 5. Benchmark integration and deliverables

| Proposed deliverable | Purpose |
|---|---|
| `tools/evox2/benchmark/Summarize-MtpDiagnostics.ps1` | Parse completed diagnostic records from existing run directories into `mtp-diagnostics.json` and `mtp-diagnostics.csv`; validate nesting, contexts, phases, completeness and non-additive timing semantics |
| `configs/qwen38-r4-mtp-diagnostics.psd1` | Three serial wall-mode runs: Vulkan 128k ON, 256k ON, 256k OFF; fail/stop on non-OK, no ABBA repetitions |
| `configs/qwen38-r4-mtp-diagnostics-sync.psd1` | Conditional second-stage 256k ON/OFF pair in sync mode if asynchronous attribution remains unresolved |
| `configs/qwen38-r4-mtp-check.psd1` and a short checked-in text prompt | Controlled short generation with fresh process/state, greedy settings, normal OFF/ON and diagnostic-enabled ON |
| `Measure-LlamaCli.ps1` / common identity helper | Artifact verification and optional diagnostic sidecar summary; preserve existing normal timing fields |
| Relevant normal/profile matrix configs | Explicitly clear `LLAMA_MTP_DIAG` in normal performance runs; restore caller environment as the runner already does |

Existing environment capture already records LLAMA-prefixed variables; no new
environment filter is needed. Do not add diagnostic columns to the historical
normal summary CSV unnecessarily. Store the diagnostic schema in its sidecars
and reference them from `result.json` only when present. A missing/incomplete
diagnostic report must not be interpreted as zero overhead.

Suggested implementation commits:
- A: build identity refresh/verification plus its focused script checks.
- B: default-off MTP/memory/Vulkan diagnostics.
- C: summarizer, short check, focused matrices and documentation.

Each commit should be independently reviewable. Runtime candidate optimizations
come after the measured report, in separate changes.

## 6. Validation and execution plan

### Local/static checks before the Windows handoff

- Compile affected C++ paths where the available toolchain permits; verify the
  disabled mode has no extra sync/counter traversal and all error exits close
  diagnostic scopes. Windows Vulkan/ROCm success must be reported separately.
- Use Windows PowerShell 5.1 parsing for edited scripts; the summarizer may be
  tested locally with fixtures where PowerShell is available.
- Parser fixtures cover nested timings, repeated phases, unmatched backend
  events, interrupted runs, absent diagnostics, and mixed batches. Tests must
  reject adding inclusive parents and children into one total.
- Build identity fixtures cover matching artifacts, a substituted DLL, missing
  manifests and dirty source. The meaningful stale-version integration check
  requires an actual incremental Windows build across commits; do not fabricate
  a version-label pass.

### Windows gate A: build and short correctness/control

Build Vulkan first using the established local configuration, preserve manifest
and artifacts, verify `--version` and `--list-devices`. Test the metadata refresh
on the existing incremental build directory. Confirm DLL checks detect a copy
substitution using a disposable test directory, not the working binary set.

Run allocation smoke MTP OFF/ON. Then use one short prompt, a 32k allocated
context, 128 output tokens, greedy temperature 0/top-k 1, fixed seed, ignore-eos,
DraftMax=2/p-min=0, f16/batch2048/ubatch1024/t4/tb4 and no prompt cache/checkpoints:
1. MTP OFF, diagnostics off.
2. MTP ON, diagnostics off.
3. MTP ON, wall diagnostics.
4. Sync ON only if sync mode will be used in the long-context stage.

Compare case 2 vs 3 (and 4) for diagnostic-induced token/state differences.
Repeat a mismatch to establish whether it exceeds the baseline numerical
variation before claiming a defect. OFF vs ON may already diverge numerically;
compare against the pre-change behavior, not an invented exact-output guarantee.

Record natural full/partial/rejected drafts and position transitions from the
existing verifier. If the chosen prompt does not exercise partial rejection,
use a second short prompt rather than assuming coverage. Readable text, exit 0
and aggregate acceptance alone do not prove rollback equivalence.

For persistent OFF/ON divergence that suggests a state defect, stop candidate
adoption and add a focused fixed-prefix logit/state comparison: include a
non-speculative multi-token target control to separate batch-shape numerics
from rollback effects. Inspect first divergent row and top candidates; choose
tolerances from controlled baseline variation, not an arbitrary universal epsilon.
Do not emit full-vocabulary logs during the long-context performance runs.

Existing server `test_speculative.py` uses a tiny draft-simple model, not this
Qwen4Exp MTP sidecar. It is a useful general regression check if available but
does not substitute for the target-model gate.

### Windows gate B: first focused long-context collection

Use the overnight target model/input/cache/sampler settings, **512 output
tokens, temperature 0.2**, DraftMax=2/p-min=0 when ON. Vulkan legacy MoE=1,
GET_ROWS 128x4=0, union=1. Other profilers/experiments remain cleared.

| Order | Backend/context | MTP | Diagnostic mode | Why |
|---|---|---|---|---|
| 1 | Vulkan 128k | ON | wall | Reference near TG parity |
| 2 | Vulkan 256k | ON | wall | Reproduced TG loss |
| 3 | Vulkan 256k | OFF | wall | Ordinary one-token decode and append-only control |

The three runs are diagnostic samples, not a new statistical performance
comparison. Preserve acceptance, query counts, phases, resources and all raw logs.
Summarize steady TG separately from prompt/first-token work. Do not subtract
diagnostic ON times from old normal OFF times and call the result an exact cost.

Only if pending work makes attribution ambiguous, collect the same-build
256k ON/OFF sync pair. If the shared CPU/draft mechanism needs backend
confirmation, build ROCm and take one focused 256k ON wall sample; do not repeat
all ROCm contexts by default. If FA kernel attribution remains necessary, take
one deliberately scoped Vulkan GPU profile with phase/layer labels. Profiler and
sync throughput must not be compared directly with the overnight baseline.

### Decision gate after collection

| Observation | Candidate to evaluate next |
|---|---|
| Dense draft indexer/layout work is measurable despite unused QSA | Disable only its unused indexer cache while retaining the required wrapper; validate ratio-zero/positive-ratio and main paths |
| Main CPU full-layout rebuild dominates sequence-edit costs | Design a suffix-local update preserving shared cells, order/positions and partial pools |
| Small-query main verification union is a material extra cost | Test a small-query fallback guard while retaining large-batch PP union |
| Draft dense evaluations/catch-up dominate | Investigate draft kernels or safely avoiding redundant work with exact hidden/KV dependencies |
| No single material candidate | Record the bounded result and proceed to MTP PP; do not broaden the patch indefinitely |

An attribution claim needs time plus work counters, not merely increasing cell
counts. GPU pool-work counters do not prove measured kernel duration. A dispatch
choice alone does not prove it is slow.

After a selected performance change passes correctness checks, use diagnostic
mode off for unprofiled 256k ABBA, then only affected 64k/128k controls.
The current plan itself does not claim a speedup or a Windows build/test pass.

## Related records

- [Overnight results and hypotheses](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md)
- [Initial MTP source review and input fix](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md)
- [Current priorities](ROADMAP.md)

Source paths/function names above refer to the fixed review commit, not moving
upstream. The performance patch to implement next is chosen only after gate B.
