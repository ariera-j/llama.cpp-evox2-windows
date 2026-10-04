# r4 COMMON-002: target QSA no-op invalidation implementation

Implementation parent: `feec722ade5b9a22e4c9555c72a6841c50afd5e8` on
`r4/upstream-refresh-20261002`; upstream remains pinned to
`bed0a856606ee4a24a164066f73d2379447033f5`.
Status: code, native targets, Windows gate and focused plans delivered;
Windows Vulkan source/policy/model gate is Complete after the hidden-row
accessor correction. All524 logits/hidden comparisons are exactly equal; actual
no-op suppression and pending stale preservation are confirmed. All three
allocation smokes and five short CLI runs now pass: A/B output and acceptance
match, 25 unnecessary invalidations are suppressed, and real removals remain
intact. The 256k wall gate now also passes2/2 with matching output and ordered
acceptance history: target full rebuilds217->95, layout5.529702->2.436146 s,
wall TG19.96->22.71 (+13.78%), PP effectively unchanged. Diagnostic-OFF normal
ABBA now passes4/4: mean TG20.205->22.830 (+12.99%), matching response and
aggregate acceptance, mean PP229.940->229.565 (-0.16%). Source default stays OFF.
ROCm native gates and all8 allocation/short CLI runs pass. The256k normal
matrix is3/3 OK: OFF/A/B TG12.39/13.57/14.44, PP185.76/173.91/173.84.
A/B response and acceptance differ, so ROCm long equivalence and isolated
no-op performance remain unresolved. B adds88.318 s versus OFF to fresh-prompt
evaluation. Next: MTP OFF CLI/bench64k before choosing the next investigation.
The short PP outlier is not reproduced here but its cause remains open. See
[ROCm256k review](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md) and
[ROCm native/short validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md). See [normal ABBA validation](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md) and
[ROCm/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md). See
[256k wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md) and
[allocation and short CLI validation](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md).
The existing draft-omission measurements do not validate this new runtime.

## Runtime change

`LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` enables the candidate. Only exact `1`
requests enablement; the source default remains OFF. The setting is read once
when each hybrid-indexer memory is constructed. The actual context type,
passed from `llama_model::create_memory`, distinguishes DEFAULT target from
MTP; filenames and `load_mtp` do not determine the target role.

Eligibility requires QWEN4EXP, DEFAULT target, an allocated indexer, by-order
pool4, one configured sequence, one actual indexer stream and no SWA. Each
removal additionally requires explicit sequence0 and unshared layout metadata.
Unsupported configurations and all-sequence operations retain the old path.

Recurrent removal still runs first; refusal returns before indexer/attention
mutation. After recurrent success, the wrapper records the actual sequence's
ordered indexer cell-set size before and after the existing indexer removal.
Only equal counts in an enabled, eligible call suppress the **new** stale
marker. A previous stale marker is preserved exactly. Real removal, unexpected
increase and unsupported calls retain the existing invalidation/sharing path.
Attention removal and its return status are unchanged.

There is no per-token environment lookup. With candidate and diagnostics OFF,
there are no new cell-count lookups. The layout rebuild algorithm, GPU pooled
keys, kernels, server trim/acceptance and serialized state format are unchanged.
Real suffix removal is deliberately left for a separate candidate.

Explicit switch settings emit a startup decision, for example:

```text
QSA no-op invalidation: requested=1 eligible=1 enabled=1 target=1 kpool=4 streams=1 seq_max=1 reason=target_single_sequence
```

The benchmark evidence parser requires exactly one well-formed target1
decision; well-formed target0 draft decisions are not selected. Missing,
malformed, duplicate, mismatched or ineligible target evidence prevents an OK
candidate run. MTP OFF can legitimately enable this target switch. Evidence
is retained in `result.json`, `summary.csv` and matrix result rows, without
overwriting exit codes, timings or other metrics.

Wall/sync `seq_rm` records gain these schema1 fields:

| Field | Treatment |
|---|---|
| `idx_cells_before`, `idx_cells_after` | Per-event observations, never summed |
| `stale_before`, `stale_after` | Per-event observations, never summed |
| `noop_observed` | Sum of inspected equal-count removals |
| `noop_suppressed` | Sum of removals suppressing new invalidation |
| `stale_marked` | Sum of inspected removals taking the old invalidation path |
| `pending_stale_preserved` | Sum of suppressed removals retaining prior dirty state |

Observations are emitted only for inspectable calls. They are not invented
for recurrent refusals, unsupported contexts or older logs. Existing startup
capability-refusal accounting and diagnostic-only repair behavior remain valid.

## Native correctness and local validation

`test-qsa-noop-policy` exercises the production helper plus actual
`llama_kv_cells` metadata: exact1, role/pool/stream/sequence/SWA exclusions,
all-sequence/shared-call exclusions, duplicate positions with distinct cells,
empty/equal/reversed/out-of-range removal, real removal and count increase.

`test-qsa-noop-invalidation` loads the main model once and creates fresh OFF/ON
target contexts. It uses context1024, batch64/ubatch32, f16, FA auto, t4/tb4
and `n_rs_seq=2`, matching DraftMax2's target rollback setting. Batch64 admits
prefix lengths32–35 in one API call; both arms use identical ubatch partitions.
Nextn hidden output is enabled. Every captured logits/hidden vector must have
matching nonempty dimensions, finite values and NMSE<=1e-5. Numerical failures
are accumulated and fail the final gate; the threshold is unchanged.

Cases include all four pool boundaries, three-token verification with accepted
drafts0/1/2, real trim then no-op before continuation, equal/reversed/finite
ranges, full/PARTIAL_ONLY restore then trim/no-op/continuation, malformed restore
and defensive clear, empty/drop/reuse, nonzero positions/gaps, repeated no-ops
and no-op then real edit. Fresh multi-sequence unified ineligible contexts test actual shared-prefix
evaluation, no-op removal and copy/keep fallback. Shift/division are exercised only if both arms
advertise support; otherwise unchanged capability is reported. A focused
`n_rs_seq=0` control requires recurrent refusal and compares continuation.
No forced eviction is advertised for this non-SWA full cache; drop and suffix
edits exercise physical slot reuse through the normal allocator.

The model gate also inspects real end records: suppression must retain cell
counts and stale position, pending stale must be genuinely dirty, and real
removal must mark stale. Nonempty indexer observations and an actual layout
event are required. Startup logs alone cannot satisfy this gate. A/B histories
are the numerical reference, avoiding bulk-versus-step replay confounding.

Local checks completed on Linux:

- Production policy/real-cell test compiled and passed with g++13/C++17 and
  warnings as errors; ASan/UBSan also passed with leak detection disabled
  because the sandbox prevents LeakSanitizer from inspecting process threads.
- Changed hybrid-indexer/model code and the model test passed C++ syntax
  checks; the model test also passed warnings as errors.
- PowerShell7.4 source parsing, all maintained r4 plan validation, target
  evidence fixtures and inherited-switch checks passed in the new SourceOnly
  gate. The existing dense-indexer SourceOnly gate passed.
- `Test-MtpDiagnostics.ps1` passed parsing, artifact identity, relative-path,
  summary/repair pipeline checks and all16 Python/native diagnostic tests,
  including the new counter-versus-observation test. No skips locally.

Windows PowerShell5.1, the Vulkan/ROCm builds and GPU numerical tests have not
run here. SourceOnly is explicitly not a model correctness pass.

Both build scripts now build the two native targets, and the build manifest
hashes their executables. No ROCm build/measurement is required for this first
Vulkan candidate.

## Gate A: rebuild and target native test

From the repository root in Windows PowerShell:

```powershell
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 -SourceOnly
& .\tools\evox2\tests\Test-MtpDiagnostics.ps1
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r4-qsa-union -BuildOnly
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 -RunModelTests
```

Use the existing configured build directory if different. BuildOnly refreshes
metadata/reconfigures and builds the new targets; ManifestOnly is not a rebuild.
The gate defaults to `R4QsaUnionVulkan` and `UnslothPle16` in `local.psd1`;
`-LocalConfig`, `-BuildKey`, `-ModelKey`, `-GpuLayers` can override them. Only
the main model is loaded; no draft model argument is needed by this target test.

The script verifies manifest/source and executable/DLL identities, resolves
paths before launch, retains the native handle/ExitCode and requires exit0
plus a final PASS marker. It isolates inherited experimental environment and
restores it afterward. SourceOnly yields `SourceChecksPassed`; default native
mode yields `PolicyPassedModelNotRun`; only `-RunModelTests` can yield Complete.
The report and full stdout/stderr are retained under
`evox2-logs\tests\<timestamp>-qsa-noop-invalidation`, including failures.

Review Gate A's complete report before any longer measurements. In particular,
a build from the previous `e2deea7` runtime cannot test this new switch.

## Gate B: three allocation smokes and five short runs

After Gate A is Complete, use the following allocation smokes. This block
saves and restores the caller's experimental environment.

```powershell
$names = @(Get-ChildItem Env: | Where-Object {
    $_.Name -match '^(LLAMA_MTP_|LLAMA_QSA_|QWEN4EXP_QSA_|GGML_VK_)' -or
    $_.Name -eq 'LLAMA_GRAPH_REUSE_DISABLE' -or $_.Name -match '^EVOX2_(AB|ABBA)_'
} | ForEach-Object { $_.Name })
$names = @($names + @('LLAMA_QSA_SKIP_NOOP_INVALIDATION', 'LLAMA_MTP_SKIP_DENSE_INDEXER',
    'LLAMA_MTP_DIAG', 'GGML_VK_MOE_LEGACY_TILE_SELECTION', 'GGML_VK_GET_ROWS_128X4',
    'GGML_VK_QSA_UNION') | Sort-Object -Unique)
$saved = @{}
foreach ($name in $names) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
try {
    $env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
    $env:GGML_VK_GET_ROWS_128X4 = '0'; $env:GGML_VK_QSA_UNION = '1'
    $env:LLAMA_MTP_DIAG = 'off'; $env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
    $smoke = @{
        BuildKey = 'R4QsaUnionVulkan'; ModelKey = 'UnslothPle16'
        Context = 32768; KvType = 'f16'; UBatch = 1024; Batch = 2048
        Threads = 4; GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
        Fit = 'off'; Temperature = 0; PromptCacheMiB = 0
        ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
    }
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke -AllocationOnly
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
        -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
    $env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
    & .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
        -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
} finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-check.psd1
```

The short plan runs MTP OFF/target1 control, A-normal0, B-normal1, A-wall0,
B-wall1. All MTP ON arms retain `LLAMA_MTP_SKIP_DENSE_INDEXER=1`; only the new
target switch changes. Settings retain the validated Vulkan MoE/union controls,
no checkpoints/cache reuse, deterministic short input/output and DraftMax2.
All existing r4 plans clear the new switch in Defaults, so the caller's
environment cannot silently change older comparisons.

Review all8 statuses, Verified evidence/runtime identity, response bytes,
acceptance and diagnostic accounting before the long wall pair.

## Gates C and D: collect only after reviewing the preceding gate

```powershell
# Gate C: only after Gate B review.
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-wall.psd1

# Gate D: only after the wall results confirm intended work removal and correctness.
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-abba.psd1
```

Both use the existing256k input, context262144, 512 generated tokens, f16,
batch2048/ubatch1024, t4/tb4, seed1234, temp0.2/topP0.8, ignore EOS, FA auto,
fit/reasoning OFF, RAM prompt cache0 and checkpoints0t. No-op A=0/B=1 while
draft omission stays1. Wall has two runs; diagnostic-OFF ABBA has A1/B1/B2/A2
from the same binary. The plans preserve environment and repetition identity.

If output/acceptance history matches the prior B-wall, the old217 post-trim
full rebuilds could fall to95, corresponding to122 avoided no-op-associated
rebuilds. This is a conditional mechanism check, not a universal required count
or a predicted3.09-second normal gain. Genuine suffix rebuilds and previously
pending invalidation must remain; reduced scan/copy work must accompany lower
layout time. Check PP, generated tokens, response bytes, acceptance, target/draft
roles, native status and runtime identity before interpreting normal TG.

Default stays OFF until these gates pass. Subsequent work remains separate
suffix-layout reuse with CPU/GPU dirtiness distinguished, then MTP PP attribution
and ROCm long-context PP scaling. Focused128k coverage remains an expansion gate;
COMMON-005 stays deferred. This implementation does not establish MTP total
latency superiority over OFF.

Related: [approved plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md),
[target source review](R4-COMMON002-TARGET-LAYOUT-SOURCE-REVIEW-2026-10-04.md),
[draft omission ABBA](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md),
[roadmap](ROADMAP.md).


## 19:02 Windows gate failure: unmasked NextN row selection corrected

Source: `20261004-190252-816-qsa-noop-invalidation.zip`, including the19:01
SourceOnly report and19:02 native run from implementation commit `8f421386`.
SourceChecks Passed, PolicyTest Passed/exit0, BuildIdentity Verified. The target
model test exited1 at the first `seqs-1/prefix-32/accept-0` evaluation, before
any logits/hidden numerical comparison or removal case. Startup decisions
confirmed A requested0/eligible1/enabled0 and B requested1/eligible1/enabled1,
both target1/pool4/streams1/seq_max1. The model runtime artifact digest was
`a1ca0f5a7c6e4d188445d0b28b4d46eb034bba5472bc307e85d352eec1adac56`.

The decisive stderr line is:

```text
get_embeddings_nextn_ith: invalid nextn embeddings id -1, reason: out of range [0, 64)
```

This is a test API misuse. `llama_context::get_embeddings_nextn_ith` supports
negative output selection only for masked NextN; unmasked NextN rows are
indexed by the token's nonnegative row within the current batch. The new target
gate enables unmasked output but copied a `-1` accessor from the older masked
draft gate. Logits' `-1` selection remains valid. This failure does not establish
a candidate numerical error and is not a correctness pass.

The corrected helper receives `common_batch::size()-1`, after checking that the
batch is nonempty, and uses it only for the target NextN accessor. This selects
the last token of the current batch after output reordering, including batches
split into multiple ubatches. It does not use the absolute sequence position
or the allocated buffer capacity. Missing logits/hidden diagnostics now identify
the failing output explicitly. Target output remains unmasked, and the strict
finite/dimension/NMSE<=1e-5 gate is unchanged.

A new model-free regression compiles the actual capture/decode helper bodies
against accessor stubs. It verifies batches32/33/3/1, nonzero sequence positions,
stale unused capacity and empty-batch rejection. The old `-1` access is rejected
by these stubs; no copied replacement capture implementation is tested.
The regression and C++17 syntax/warnings-as-errors check pass locally. This
validates accessor wiring, not Vulkan numeric correctness. The source fix,
regression and this record do not change the optimization runtime.

After pulling the fix, repeat Gate A's BuildOnly and `-RunModelTests` commands.
Retain the whole test report, including on failure. ModelTest must pass and the
report must be Complete before allocation/short or long measurements proceed.


## 19:12 Windows target native gate: Complete

Source: `20261004-191201-185-qsa-noop-invalidation.zip`, submitted after the
`5df0bdb` accessor fix. Run interval19:12:01.186–19:16:50.671 JST on2026-10-04.
The report is Complete: SourceChecks/PolicyTest/ModelTest Passed, both native
exit codes0, BuildIdentity Verified and an explicit final model PASS marker.
The main model is the existing Unsloth PLE16 UD-IQ3_XXS, ngl999; no draft model
is loaded by this native target gate.

| Native evidence | Result |
|---|---|
| Logits/hidden vector comparisons | 524; every NMSE0 and maximum absolute difference0 |
| Eligible sequence1 decisions | A requested0/eligible1/enabled0; B requested1/eligible1/enabled1 |
| Ineligible unified sequence2 decisions | A/B eligible0/enabled0; actual shared-prefix fallback is exercised |
| Inspected sequence removals | 242 across eligible A/B histories |
| Observed equal-count removals | 134 |
| Suppressed new invalidations | 67; every cell count and prior stale position preserved |
| Pending stale preserved | 33; previous stale marker remains dirty |
| Actual indexer membership decreases | 108 across A/B; all mark stale |
| Total inspected old-path invalidations | 175; includes A no-ops and actual edits |
| Recurrent refusals | 2, the intentional n_rs_seq0 A/B control; continuation matches |
| Actual layout events | 628, including2 cache_safe0 shared-prefix events |

All pool-boundary/accepted0/1/2, real-trim then no-op, no-op then real edit,
nonzero-position/gap, repeated no-op, empty/drop/slot-reuse and state cases
complete. The full and PARTIAL_ONLY stages each contain96 vector comparisons;
state byte-count and same-setting A/B size checks pass. Shared-prefix and keep
fallback continuations, malformed-restore clear/continuation and refusal
continuation are all numerically identical across arms.

Position shift/division are unsupported by both model contexts and reported
as unchanged capability; no unsupported operation was forced. The four
`state_seq_set_data: error loading state: unexpectedly reached end of buffer`
lines are intentional malformed-state rejection cases in A/B single/multi-sequence
contexts. The following clear/continuation checks pass; these lines are not
unexpected inference failures. The original negative-NextN-row error is absent.

Runtime artifact-set digests:

- Policy: `a47c6028b17995573d3819ff2f04d4d2f0e8b6491aa43bff9e30e05c6e9146ee`
- Model: `a36e6ae9df4147fc8fd74569d2abcd9c3a9b41fbb39b28ed7f2a90cb341f707d`

These are executable/DLL identity digests, not Git hashes. Gate B now passes
with the same source build; see the subsequent CLI identity and checks below.
The switch remains source-default OFF and no speedup is established yet.

## 19:23–19:30 allocation and short CLI gate: Complete

All eight runs are OK with exit0, Verified runtime and independent target
startup evidence. MTP ON A/B allocation responses match with13/34 acceptance;
all four short MTP ON responses match with69/116 acceptance. Wall A/B also
match the ordered58-round acceptance/position history.

In target generation, B suppresses25 unchanged-membership invalidations while
retaining stale marks for all33 actual removals. Full rebuilds fall57->33 and
copied cells13256->7976. The final no-op trim has no subsequent decode, which
explains24 fewer rebuilds for25 suppressions. Draft layout remains omitted.
Normal short TG34.81->34.86 is only+0.14% at163 prompt tokens, so this gate
validates behavior/work removal rather than a performance gain.

This gate authorized Gate C with the verified b11416 /5df0bdbaf CLI.
The subsequent wall gate passes as recorded below. No rebuild is needed.
See [complete allocation and short results](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md).


## 19:53–20:34 256k wall gate: Complete

Both runs are OK with Verified startup/runtime evidence and matching response
bytes and ordered218-round acceptance/position histories (293/436). Target B
suppresses123 no-op invalidations and retains all95 real-removal stale marks.
The final no-op trim has no next decode: full rebuilds217->95, copied
cells55429810->24265693, layout CPU5.529702->2.436146 s. Draft layout stays
omitted and pooled logical/padded new counts match.

Wall TG19.96->22.71 (+13.78%) accompanies3.108240 s less generation evaluation
and3.093556 s less layout work; PP230.12->229.92 (-0.09%). This supports the
mechanism but requires normal ABBA for repeatable performance. Total evaluation
improves only2.178570 s (about0.19%) because PP dominates; whole-process
duration differences include loading/startup and are not TG savings.

This wall gate authorized Gate D; the subsequent normal ABBA passes below.
Source default stays OFF; focused128k remains a separate coverage gate.
The95 real suffix rebuilds retain2.436146 s of layout cost for the separate
suffix-reuse investigation. See [complete wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md).


## 20:42–22:07 diagnostic-OFF normal ABBA gate: Complete

All4 runs are OK with Verified startup/runtime evidence, identical2538-byte
responses and293/436 aggregate acceptance, also matching the wall pair.
Normal runs do not collect ordered trim histories. A TG20.24/20.17 averages
20.205; B22.82/22.84 averages22.830 (+12.99%). PP means229.940->229.565
(-0.16%), effectively unchanged. Mean generation evaluation saves2.910235 s
while total evaluation saves only1.121760 s (about0.10%) with PP variation
larger than that saving. This validates TG improvement at Vulkan256k, not
robust fresh-prompt total-latency improvement or global MTP enablement.

The user now requests ROCm build/measurement, then CLI/bench comparison, then
a decision on MTP PP versus other work. Residual suffix reuse is parked during
those checks. New ROCm short/256k and staged64k/256k CLI/bench plans are
provided; no inference code changes. PowerShell7 source checks and PlanOnly
expansion pass locally; the subsequent Windows ROCm native/model and short
gates now pass as recorded below, with long performance still pending.
The currently verified Vulkan binaries need no rebuild. Rebuild ROCm to include
the candidates and native test targets. See [normal results](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md) and
[ROCm/bench commands and comparison limits](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).


## 23:08–23:41 ROCm native, allocation and short gate: Complete

Both native model suites are Complete with source/policy/model Passed and
Verified build identity. Dense suite36 matched-partition comparisons and
target suite524 comparisons are exact; eight dense diagnostic-only partition
comparisons remain separately informational. Target native records confirm67
no-op suppressions and33 pending-stale preservations.

All8 CLI runs are OK with Verified b11420/131288531 runtime and target/draft
evidence. Allocation A/B match16/29 acceptance; short MTP ON bodies match
with68/118 acceptance and wall ordered59-round trim histories match. B
suppresses23 no-op invalidations and retains all36 real-removal stale marks;
full rebuilds58->36 and copied cells13459->8625. Draft layout remains omitted.

Short B-normal PP48.16 (3.384780s) is an outlier against the other MTP ON
PP173.07–184.92 (0.881450–0.941810s). Cause is unconfirmed; retain it and
track PP in256k. Single short TG differences do not establish a speedup.
Proceed to the three ROCm256k normal arms with the same binaries; no rebuild
is needed for this documentation update. See [complete ROCm validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md).


## 2026-10-05 00:08–01:24 ROCm256k normal collection: Complete

The three OFF/A/B runs all finish OK with the same Verified b11420/131288531
runtime,255181 prompt and512 generated tokens. PP185.76/173.91/173.84 and
TG12.39/13.57/14.44 show current ON TG above OFF, but B evaluation remains
88.318 s longer than OFF because PP adds94.176 s while generation saves5.859 s.
A/B generation bodies differ from byte3 and acceptance is289/441 versus286/448.
Therefore collection is Complete, while long-context candidate equivalence and
isolated TG attribution are unresolved. Normal logs have no ordered trace;
existing native/short exactness does not settle this long difference.
Short B-normal PP48.16 collapse is absent in this pair, not explained or fixed.
Proceed independently to MTP OFF CLI/bench64k with existing binaries. No code
change or rebuild. See [full results and limits](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md).
