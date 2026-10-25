# r4 COMMON-002: dense MTP indexer omission implementation plan

Planning baseline: `r4/upstream-refresh-20261002` at
`fa6caa2f731902ed651023c60ed0b24989cb5ce4`; upstream remains pinned at
`bed0a856606ee4a24a164066f73d2379447033f5`.

Status: implemented after user approval. The runtime switch, native tests and
focused benchmark plans are delivered. The 14:50 Windows Vulkan native model/
state/rollback and A/B gate passes after harness corrections. Allocation/short
real CLI subsequently passes 8/8 runs. The 256k wall pair also passes: TG
14.76 -> 19.95 tok/s (+35.16%), identical response bytes/acceptance, draft
layout removed and target layout retained. Normal 256k ABBA also passes:
TG mean 15.220 -> 20.185 (+32.62%), matched output/acceptance, PP unchanged.
The earlier normal OFF TG19.76 is only 2.15% below B; MTP PP overhead remains.
Next: retained target layout source investigation and focused 128k confirmation
before expansion. Default remains OFF. This document preserves the design.
See [normal ABBA validation](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
See [candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md).
See [implementation and runnable gates](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md)
for actual delivered behavior, local checks and Windows commands.

## Goal and measured basis

Remove the indexer cache that the current dense QWEN4EXP MTP graph never reads,
while retaining draft attention K/V, the hybrid memory/context types and
speculative decoding behavior. Keep the current default and use one rebuilt
binary for OFF/ON comparison.

The supplied sidecar's MTP block is layer 48 with compression ratio 0. Trunk
ratio-4 entries keep the model-wide pool size positive. `create_memory` still
selects that MTP block for an indexer cache, and `kpool_track` therefore keeps
maintaining its CPU layout although `graph_mtp` omits pool inputs. At 256k ON,
the measured generation component is 9.901350 seconds of draft layout, with
435 full/stale rebuilds and 111,114,370 copied cells. Target layout adds
5.113921 seconds. See the
[source review](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md) and
[wall results](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md).

These observations select the candidate; they do not predict an exact TG
gain. Removing a cache also changes allocation and scheduling. Dense draft
inference, hidden-state transfer and target QSA layout work still remain.

## Runtime contract

Proposed switch: **`LLAMA_MTP_SKIP_DENSE_INDEXER`**.

| Value / context | Required behavior |
|---|---|
| Unset, empty, `0`, `off`, or any value other than exact `1` | Preserve the existing indexer allocation and maintenance |
| `1`, QWEN4EXP MTP in the existing hybrid-indexer path with a non-null indexer filter, exactly one valid MTP block, that block's ratio is 0 | Construct the hybrid-indexer wrapper with `filter_idx = nullptr`; omit `mem_idx` |
| `1`, positive MTP compression ratio | Preserve indexer allocation and QSA |
| `1`, target/default context or another architecture | Preserve the existing memory path |
| Indexer already absent or a different memory-wrapper branch selected | No effective omission; preserve that path and identify it as ineligible/already absent |
| `1`, missing/unsupported multi-block metadata or invalid MTP layer range | Do not apply this optimization; leave existing model validation responsible for unsupported metadata |

Read the switch once per context memory creation, without a process-wide
static cache. Do not read it inside decode, `seq_rm`, `apply` or layout loops.
The effective choice is fixed for that context's lifetime; changing the
environment afterward does not mutate live cache state.

Validate the MTP block count and layer range before indexing the ratio array.
For this pinned graph, the active block is `il = hparams.n_layer()` and the
graph explicitly asserts `n_layer_nextn == 1`. Do not infer eligibility from
the last raw metadata entry without checking that relationship. A future
multi-block graph needs a new review of all selected blocks.

## Proposed implementation files and behavior

| File / area | Planned change |
|---|---|
| `src/llama-model.cpp`, `llama_model::create_memory` | Inside the actual `else if (needs_mem_idx)` branch, after the QWEN4EXP MTP layer filters are selected and immediately before constructing `llama_memory_hybrid_idx`, apply the guarded policy. Add `<cstdlib>` for the environment read if needed. Set only `filter_idx = nullptr` for an eligible opt-in. |
| `src/llama-mtp-indexer-policy.h` (new internal helper) | Keep eligibility checks small and testable: architecture, context type, existing indexer filter, supported block count, valid layer and ratio. Check bounds before ratio access; no cache ownership, global state, environment reads or public API. The native decision test uses the same helper. |
| Existing hybrid-indexer memory/context code | Use its existing null-indexer branches. Constructors leave `ctx_idx` null and stream tracking empty, `kpool_track()` returns false, and indexer-specific sequence/state operations are skipped. Do not add a second layout bypass or change stale bookkeeping for active indexers. |
| `tests/test-mtp-indexer-policy.cpp` (new) and `tests/CMakeLists.txt` | Add a small model-free native test for the policy boundaries, built with the existing toolchain rather than depending on g++. |
| `tests/test-mtp-dense-indexer.cpp` (new) and `tests/CMakeLists.txt` | Add an explicitly invoked, model-dependent cache/state/logit test using the existing llama/llama-common linkage. Keep it outside automatic model-free test runs; accept main/draft paths as arguments. |
| `tools/evox2/tests/Test-MtpDenseIndexer.ps1` (new) | Parse changed/new PowerShell plans, invoke the native policy test from the actual build, validate plan variants and run the explicitly requested model-dependent gate. Report missing native artifacts as a missing gate, not as a correctness pass. |
| Maintained r4 benchmark plans | Explicitly clear the new variable in default environments, including clean/control, existing MTP check, diagnostic and overnight plans, to prevent inherited settings from changing historical controls. |
| Three new focused benchmark plans | Separate short correctness, 256k wall attribution and normal ABBA, as specified below. Reuse `local.psd1` build/model/input keys and the existing runner; no new runner protocol. |

**Null filter matters:** an always-false layer filter only omits layer tensors
while leaving the cache's cell metadata allocated. The constructor's
`filter_idx == nullptr` branch is what avoids the cache itself.

Retain `llama_memory_hybrid_idx` and `llama_memory_hybrid_idx_context` even
when their indexer is absent: `graph_mtp` casts to that context type. Preserve
the empty recurrent input allocation, recurrent refusal/rollback handling,
attention slot preparation, attention trimming, catch-up, hidden carry and
acceptance. Do not set the shared model's `indexer_kpool` to zero: the target's
trunk QSA still needs it. No backend kernel, QSA union setting, DraftMax or
compression metadata is changed by the candidate.

### Startup evidence and artifact identity

When the switch is explicitly present, log one decision line for QWEN4EXP
MTP memory creation containing requested setting, eligibility, effective
omission, active layer/ratio and a reason. Both A=`0` and B=`1` must make the
effective path identifiable. The unchanged target indexer creation must also
remain visible in the existing allocation log. Do not add per-token logs,
diagnostic clocks or synchronization for this switch.

The existing `Get-Evox2RelevantEnvironment` already captures `LLAMA_*` into
run artifacts; no new environment-capture API is needed. The implementation
must check that `result.json`/matrix plans record the requested switch and
that startup evidence records the effective choice. A requested `1` that was
ineligible must not be reported as a successful optimized run.

Rebuild the current Vulkan directory after the C++ change. Run both arms from
that one executable/DLL set with a refreshed Verified manifest. Do not compare
the old diagnostic binary directly to a separately rebuilt ON-only binary or
use ManifestOnly in place of rebuilding. The new native CMake targets require
the normal build-system regeneration/reconfigure as appropriate; deliver the
exact build commands with the implementation.

## State and rollback policy for the first experiment

The current hybrid-indexer serializer writes its indexer section as a suffix
only when `mem_idx` exists. PARTIAL_ONLY state excludes this section. The
optimization therefore changes full draft-state size but should leave the
speculative recurrent checkpoint format unchanged.

Source inspection adds an important limit: `state_load_file` checks full
consumption, but the sequence-file reader permits `nread <= state_size`, and
the raw sequence-state API returns bytes consumed. A saved indexer suffix can
therefore be ignored by some readers after the setting changes. Do not claim
that all mismatched OFF/ON restores are automatically rejected.

For this initial opt-in experiment:

- Support and test same-setting save/restore and speculative rollback.
- Use fresh processes/contexts for each arm. Keep `--cache-ram 0` and
  `--ctx-checkpoints 0t`; do not load a session or reuse saved draft state from
  the other arm. Ordinary MTP speculative checkpoints remain exercised.
- Require the test harness to check written/read byte counts exactly and
  clear/reinitialize a context after a failed restore.
- Do not change the global state format/version or expand cross-setting full
  restore support in this patch. Document this limitation next to the switch.
  Production/default promotion or reusable saved draft states require a
  separate compatibility decision and explicit configuration identity checks.

### Model-dependent native gate

Use one target model and one draft model, with small contexts; avoid loading
two full target copies on UMA. Create A and B draft contexts from the same
draft model under the two switch settings. Enable the existing nextn hidden
outputs, capture a short target token/hidden trace, and feed identical token,
position and hidden rows to both drafts using the existing MTP batch API.

Check real cache behavior, not only the policy helper:

1. Initial decode, pure append, `seq_rm` of a non-empty speculative suffix and
   a removal beyond the current end all succeed; attention sequence positions
   match between A and B.
2. Compare draft logits and nextn hidden outputs for identical inputs. Reuse
   the `NMSE <= 1e-5` state-test criterion from `test-save-load-state.cpp`, reject
   non-finite values and record maximum absolute differences as well. Handle
   a zero-energy reference explicitly rather than dividing by zero; a differing
   zero-reference case fails the initial gate. Changed greedy text still needs
   first-divergence investigation rather than being equated with a proven bug.
3. For simulated accept lengths 0, 1 and 2, remove the rejected suffix and
   replay the retained/verified input. Compare the resulting logits/hidden
   rows to a fresh replay reference for each setting. The CLI short gate below
   separately exercises real speculative acceptance/catch-up.
4. Save full and PARTIAL_ONLY sequence state, restore within the same setting,
   append identical rows and compare to uninterrupted execution. Ensure the
   state getters return nonzero sizes and the reader consumes exactly the saved
   size. Use realistic hidden rows, not an invented token-only MTP input.

Policy tests cover positive-ratio MTP without editing a production GGUF to
force QSA. If a real compatible compressed-MTP fixture is available, run it
as an additional retained-indexer check; otherwise report that model gate as
unmeasured. The optimization remains default OFF and single-block/ratio-zero
only. Do not download or convert a new model just to start this bounded gate.

## Focused Windows validation and measurement

The three plan filenames below are now delivered. Run their commands from
the implementation document after rebuilding and passing preceding gates.

Common conditions: `R4QsaUnionVulkan`, `UnslothPle16`, `UnslothMtp`, f16,
batch 2048, ubatch 1024, t4/tb4, GPU layers 999, CPU MoE 0, flash attention
auto, fit off, reasoning off, resource monitor on. Preserve MoE legacy tile=1,
GET_ROWS 128x4=0 and QSA union=1. Clear other diagnostic/profiler experiments
through the plans. Every arm runs as a new child process and restores the
caller's environment through the existing matrix runner.

| Gate | Planned runs | Required evidence / next step |
|---|---|---|
| Build and native tests | Vulkan rebuild; model-free policy test; model-dependent cache/state gate | Verified binary/DLL manifest; eligibility boundaries and state/rollback checks pass. A missing model-dependent test is not completion. |
| Allocation smoke | MTP OFF with candidate=1; MTP ON with candidate=0; MTP ON with candidate=1; all at context 32768 | Exit/status OK; candidate applies only in the last case; target indexer remains. AllocationOnly includes short generation, so continuation output is expected. |
| `qwen38-r4-mtp-dense-indexer-check.psd1` | Five short runs: MTP OFF control (candidate=1), A-normal, B-normal, A-wall, B-wall | Existing `mtp-short.txt`, context 32768, 128 generated tokens, greedy/top-k=1, seed1234. A/B MTP ON, DraftMax2, DraftPMin0. Confirm real rejected/partial/full drafts, token output, acceptance and catch-up. This is a short prompt at 32k capacity, not a full 32k prompt benchmark. |
| `qwen38-r4-mtp-dense-indexer-wall.psd1` | Two 256k runs: A-wall, B-wall; both MTP ON | Existing 256k input; 512 output tokens, temp0.2, top-p0.8, seed1234, ignore-eos. Complete reports; B has zero draft indexer/layout/pool-state events across prompt and generation, target layout remains. |
| `qwen38-r4-mtp-dense-indexer-abba.psd1` | Four 256k runs: A1, B1, B2, A2; both MTP ON, diagnostics off | Same workload/sampling as wall pair. Compare A and B mean TG, generation seconds, PP, prompt seconds and total PP+TG. Keep acceptance/round counts and memory logs with each arm. |
| Expansion if useful | Normal 128k candidate ABBA; short-context cost and ROCm afterward as needed | Confirm useful gain before another overnight/full matrix. Preserve prior MTP OFF reference for total-latency context. |

A always means MTP **ON**, indexer omission **OFF** (`0`); B means MTP **ON**,
indexer omission **ON** (`1`). Do not label the candidate A/B as MTP OFF/ON.
Use explicit unique variants and `EVOX2_ABBA_RUN` labels; set normal
`LLAMA_MTP_DIAG=off` and wall `LLAMA_MTP_DIAG=wall`. Do not request sync by
default. Existing historical benchmark defaults clear the new switch.

Before actual measurements, use the existing runner's `-PlanOnly` to inspect
effective settings, run order, counts and input/build/model keys. Include
`-StopOnError` in execution commands. Deliver runnable commands only when
these plans and the runtime switch are implemented.

## Acceptance, stop conditions and subsequent work

- Correctness and applied-path evidence come before throughput. If A/B
  output or acceptance unexpectedly diverges, stop expansion; compare repeated
  A controls and the first divergent logits/state to separate existing GPU
  variation from the new cache decision. Do not accept speed alone.
- A normal run with diagnostic records, an unverified artifact set, an
  ineligible candidate or incomplete output is not a valid performance arm.
- The wall pair must remove the intended draft work while retaining target
  QSA. If draft layout remains, fix scope/eligibility before more measurement.
- Promote only if normal ABBA shows a useful and consistent gain without
  material correctness, memory or total-latency regression. A small ambiguous
  difference remains inconclusive; repeat only the necessary comparison.
- Keep default OFF after the first Evo-X2 gate. Default promotion, other
  architectures, multi-block MTP and cross-setting state reuse are separate.

After this candidate, target suffix/no-op layout maintenance is a separate
implementation proposal. It must handle shared sequences, changing first
positions, duplicate positions, pool-tail boundaries and restore invalidation.
Do not combine it with the initial indexer omission or bypass recurrent
rollback. MTP PP attribution and ROCm long-context PP scaling remain next in
the agreed order; COMMON-005 ROCm decode stays deferred.

## Completed prerequisite and review boundary

User Windows validation on 2026-10-04 passes PowerShell parsing, artifact
verification, deliberately differing shell/process directories, both relative
path wrappers, clean success pipelines and diagnostic recovery. The Python
suite reports 14 tests, 11 passing and three native helpers skipped because
g++ is unavailable. Local prior validation passed all 14 with g++ available.
The repeated progress lines are fixture reports, not inference or extra
matrix rows. The script path fix at `fa6caa2f...` is therefore confirmed.

This document preserves the implementation design and gates. Delivery does
not establish native model/state correctness or any new speedup.
