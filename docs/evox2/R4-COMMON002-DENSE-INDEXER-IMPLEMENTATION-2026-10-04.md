# r4 COMMON-002: dense MTP indexer implementation and Windows gates

Implemented on `r4/upstream-refresh-20261002` from planning baseline
`c167f7abfb4582d8ad46305b135076bcf14859b5`; upstream remains pinned at
`bed0a856606ee4a24a164066f73d2379447033f5`.

Status: runtime switch, native tests, Windows gate script and three benchmark
plans are implemented. Windows source checks, native policy and build/runtime
identity checks passed in the supplied runs. The 14:50 rebuilt Windows Vulkan
model gate is Complete: all native cache/state/rollback and A/B comparisons
pass with the corrected batch partitions. Gate B's three allocation smokes
and five short real CLI runs also pass in the 14:58-15:06 collection: all four
MTP ON response bodies/acceptance match and B removes draft indexer work.
Next run the two 256k wall arms and review before ordinary ABBA. Performance
and exhaustive model correctness remain unproven;
keep the runtime switch default OFF.

See [allocation and short CLI validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md)
for all eight runs, diagnostic scope counts and the next commands.

## Delivered behavior and evidence

`LLAMA_MTP_SKIP_DENSE_INDEXER=1` omits indexer allocation only inside the
existing QWEN4EXP hybrid-indexer MTP path, with an existing indexer filter,
exactly one valid MTP block and ratio zero for that block. Unset, empty, `0`,
`off` and other values preserve allocation. Positive-ratio MTP, target
contexts and other memory/architecture paths retain their existing behavior.

`create_memory` reads the switch once per context, uses the private policy
helper to validate count/subtraction/array bounds, and sets `filter_idx=nullptr`
when eligible. It retains the hybrid-indexer wrapper/context, attention K/V,
recurrent handling and empty recurrent graph input. Existing null-cache
branches skip indexer cells, sequence maintenance, layout and pool state.
No per-token environment read, process-wide cached decision, new waits,
kernel change, compression metadata change or target pool-size change occurs.

When the variable is explicitly present, the MTP startup decision is logged:

```text
MTP dense indexer: requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled
MTP dense indexer: requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block
```

The benchmark module records parsed decisions in
`result.json.MtpDenseIndexerEvidence` and CSV evidence/omission columns.
For MTP ON with an explicit candidate `0` or `1`, missing, malformed,
mismatched or unapplied evidence produces a non-OK `CANDIDATE_EVIDENCE_*`
status, preserving process exit code and measured fields. An old/ineligible
binary cannot silently pass as an optimized arm. MTP OFF with candidate=1
is a valid inactive control; unset historical runs are unaffected.

## Native and script gates

| Deliverable | Coverage |
|---|---|
| `test-mtp-indexer-policy` | Model-free boundaries: disabled/invalid values, positive trunk plus dense head, target/other architecture, absent indexer, missing/multiple heads, invalid/short/null ratio data, positive-ratio MTP |
| `test-mtp-dense-indexer` | One target model, one draft model and two small draft contexts with identical real target token/hidden traces; target indexer retention, A/B logits/nextn output, append/no-op, simulated accept lengths 0/1/2, same-setting full and PARTIAL_ONLY restore |
| `Test-MtpDenseIndexer.ps1` | PowerShell parsing, cleared inherited switch, plan count/order, startup-evidence fixtures, verified executable/DLL identities, explicit native model gate and retained reports |
| Build scripts/manifest | Vulkan and ROCm build both native targets and record their hashes; no automatic model download or model execution |

The native cache test compares suffix-trim/replay against a fresh replay and
full/partial restore against uninterrupted continuation. Read/write byte counts
must match exactly; failed restore clears the context. Full draft-state size
must shrink in B; PARTIAL_ONLY size must remain equal. Numeric comparisons use
the existing state-test `NMSE <= 1e-5`, log maximum absolute differences and
reject non-finite values; a zero-energy reference must match exactly.

Simulated accept lengths do not replace the real CLI speculative gate. A real
positive-ratio MTP fixture is unavailable here: its retention is policy-tested,
not claimed as a model/GPU pass. No new download/conversion is needed for the
initial dense-sidecar gate.

Local verification: model-free policy test passes with warnings as errors,
including AddressSanitizer/UndefinedBehaviorSanitizer with leak detection
disabled (LeakSanitizer cannot inspect threads under this environment's tracing
restrictions; no leak-check pass is claimed). The changed model translation
unit and model-dependent test pass C++17 syntax checks, with warnings as errors
for the latter. All 14 existing Python/native diagnostic tests pass, no skips.
Whitespace and repository links are checked before commit. PowerShell, full
Vulkan/ROCm builds and model execution are unavailable here and remain Windows
gates. Previous Windows diagnostic passes do not validate these new features.

## 14:23 Windows model-gate failure and correction

Source: `20261004-142343-911-mtp-dense-indexer.zip`, containing the 14:23
model run and the preceding 14:22 SourceOnly report. Both source checks and
the native policy passed. Executable/DLL identities were Verified, while
`test-mtp-dense-indexer.exe` returned 1 and stdout was empty. Its stderr ended:

```text
MTP dense indexer: FAIL: Attention sequence positions differ from the input trace
```

Target trace generation and both draft initializations had succeeded; stderr
contains the expected A `omitted=0` and B `omitted=1` startup evidence. Failure
occurred during A's first six-token prefix, before numeric output comparisons,
state save/restore or execution of B. This result does not identify an omission
runtime failure and is not a correctness pass for either arm.

The harness incorrectly treated public `llama_memory_seq_pos_min` as attention
cache minimum and required zero. `llama_memory_hybrid_idx` inherits the hybrid
position APIs: minimum is the maximum of attention/recurrent minima; maximum
is the minimum of their maxima. The empty draft recurrent cache still tracks
sequence positions. With one sequence, no rollback snapshots and a six-token
prefix, its sole cell is at position 5, so the source contract predicts hybrid
min=max=5. The original log did not print the actual values.

The correction checks both public bounds against the current tail, including
after no-op removal, accepted-suffix trimming and same-setting restore. It
reports arm/stage plus actual min/max and expected tail on failure. Attention
history remains checked through fresh replay and continuation output
comparisons; NMSE limits, A/B comparisons, exact state byte counts, full-state
shrinkage and PARTIAL_ONLY size equality are unchanged. The runtime candidate
and memory APIs are unchanged.

The PowerShell report now records an attempted failing native gate as Failed
instead of NotRun and includes its native FAIL message and exit code in Error.
Local C++17 syntax and native policy checks pass for this correction. Windows
model execution and PowerShell execution of the correction remain pending.
Rebuild with Gate A's BuildOnly command, then rerun `-RunModelTests`; do not
advance to long measurements until that report is Complete.

## 14:35 Windows numeric failure and batch-partition correction

Source: `20261004-143511-352-mtp-dense-indexer.zip`, rebuilt after `03520d8`.
Source/policy checks and build/runtime identity passed. Position, append and
no-op checks progressed to A's first accept-0 replay comparison:

```text
MTP dense indexer: A/accept-0/logits nmse=0.00242120861 max_abs=0.353354931
MTP dense indexer: FAIL: A/accept-0/logits: NMSE exceeds state-test threshold
```

This exceeds the unchanged `1e-5` threshold. A is omission OFF; B was initialized
but its exercise and A/B comparison had not run. Hidden comparison was also
not reached because the logits comparison threw first. This establishes a
failure in the existing-arm test, not a demonstrated candidate regression.

The test mixed two batch partitions: the edited path evaluated all eight rows
at once, removed positions 6 and 7, then evaluated position 6 alone. Its fresh
reference evaluated positions 0 through 6 as one seven-row batch. In the
single-sequence QWEN4EXP path, `common_speculative_impl_draft_mtp::draft` adds
one new token/hidden row per step. Vulkan's `ggml_vk_mul_mat` dispatch also
selects matvec vs matmul using output column count. Therefore the old fixture
confounds cache edits with evaluation partition and kernel selection. That
source finding does not prove which GPU operation caused the observed NMSE.

The corrected edited path evaluates prefix `[0,6)` together, then positions 6
and 7 individually, trims the rejected suffix and evaluates one continuation.
The reference uses the same six-row prefix and individual retained/continuation
rows. Accept-0/1/2 now compare identical input partitions for all retained rows
and the final output. The fixed target token/hidden fixture is retained for
cache isolation; sampling and recursive draft carry still require Gate B's
real CLI coverage. Full/PARTIAL_ONLY restore and A/B checks remain strict.

Two diagnostic-only comparisons per arm measure bulk `[0,7)` vs `[6,1]` and
bulk `[0,8)` vs `[6,1,1]`, without any removal or restore. Their names contain
`diagnostic-only-partition` and summary lines contain `diagnostic_only=1`.
They print logits/hidden NMSE and maximum absolute difference but do not decide
the candidate cache gate. A partition mismatch together with passing matched
cache checks would support partition-dependent numerics as the old test's
confound; that result is still pending. A matched-partition cache mismatch
remains a blocking failure requiring further source/runtime investigation.

All gating numeric comparisons keep `NMSE <= 1e-5`. Finite numeric failures are
collected so A, B, logits, hidden and A/B results can be inspected in one run;
any collected failure returns 1 before the completed PASS marker. Structural
or non-finite failures still stop immediately. Exact state byte counts,
full-state shrinkage and PARTIAL_ONLY equality are unchanged. No inference
runtime or kernel change is included in this correction.

Local C++17 syntax checks with warnings as errors pass. A model-free regression
of the actual comparison/report helpers confirms that multiple numeric
failures are retained and block completion, equal outputs pass, zero-energy
mismatches fail and non-finite output throws. This does not execute model or
GPU code. Windows model execution remains pending. Run Gate A's pull,
BuildOnly and `-RunModelTests` commands again, retaining the entire report even
if it fails; do not proceed to long measurements until Gate A is Complete.

## 14:50 Windows native gate: Complete

Source: `20261004-145014-722-mtp-dense-indexer.zip`, submitted after the
`e2deea7` harness correction. Run interval: 2026-10-04 14:50:14.722 through
14:50:52.409 JST. `result.json` reports Status Complete, SourceChecks/PolicyTest/
ModelTest Passed, native policy/model exit codes 0 and BuildIdentity Verified.
The model runtime artifact digest is
`d514e17f80919756d8490824127bc1e1add10d036083fb8400be9971646bc25f`;
policy runtime artifact digest is
`17a4dfaef459451063d350ea4c4644a0fbc7cabe8356694600266b6ef51f0357`.
These are runtime artifact-set digests, not Git commit IDs.

The Vulkan gate used Unsloth PLE16 UD-IQ3_XXS plus the Q8_0 MTP sidecar,
`-ngl 999`, with small 1024-token contexts and a fixed twelve-token target
trace. Startup evidence confirms A requested=0/eligible=1/omitted=0 and B
requested=1/eligible=1/omitted=1 at layer 48, ratio 0. Target indexer retention,
append/no-op, accepted suffix lengths 0/1/2, same-setting full and PARTIAL_ONLY
restore, exact state byte counts and state-size gates all pass.

| Native evidence | A (omission OFF) | B (omission ON) |
|---|---:|---:|
| Accept-0 logits NMSE / max absolute error | 2.68728732e-8 / 0.00196957588 | Same |
| Accept-0 hidden NMSE / max absolute error | 3.44411158e-8 / 0.00199985504 | Same |
| Accept-1 and accept-2 logits/hidden NMSE | 0 | 0 |
| Full/PARTIAL_ONLY continuation logits NMSE | 2.68728732e-8 | Same |
| Full/PARTIAL_ONLY continuation hidden NMSE | 3.44411158e-8 | Same |
| Full sequence-state bytes | 15,672 | 12,500 |
| PARTIAL_ONLY bytes | 28 | 28 |

All eight cross-arm output pairs have logits and hidden NMSE=0 and maximum
absolute error=0 (16 vector comparisons). The largest gating NMSE is
3.44411158e-8, below the unchanged 1e-5 threshold. The 3,172-byte full-state
difference proves omission in this small fixture; it is not a VRAM saving or
speedup estimate for the long-context workload.

Diagnostic-only bulk versus split results are identical between A and B:

| Compared tail | Logits NMSE / max absolute error | Hidden NMSE / max absolute error |
|---|---:|---:|
| 6: bulk seven rows vs [6,1] | 0.0024256991 / 0.353331089 | 0.000253505524 / 0.102178574 |
| 7: bulk eight rows vs [6,1,1] | 0.000822770938 / 0.255668283 | 0.000178434587 / 0.0826435089 |

These differences occur without sequence removal or state restore, reproduce
in both arms, and disappear from the strict cache comparisons when retained
input partitions match. This supports evaluation-partition dependence as the
confound in the previous 0.00242120861 rollback comparison. It does not isolate
the responsible kernel or prove all bulk/step differences benign. Kernel-level
attribution is a separate question if real CLI output behavior warrants it.

Gate A is now passed on the supplied Vulkan models. No additional native model
rerun, rebuild or ROCm run is required before Gate B with these verified
binaries. This recording commit changes documentation only; retain the existing
build manifest and artifact hashes for the next runs. At this 14:50 checkpoint,
Gate B's real speculative acceptance/carry/CLI checks were still pending; they
now pass in the [later short validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md).
The next gate is the 256k wall pair, with ordinary ABBA conditional on review.

## Gate A: source checks, rebuild and native correctness

Run from the repository root and stop processes using this build's exe/DLLs.
Keep explicit tool paths needed by the preceding build. Adjust BuildDir only
if `local.psd1` points somewhere other than the existing QSA-union directory.

```powershell
git pull --ff-only
& .\tools\evox2\tests\Test-MtpDenseIndexer.ps1 -SourceOnly
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r4-qsa-union -BuildOnly
& .\tools\evox2\tests\Test-MtpDenseIndexer.ps1 -RunModelTests
```

BuildOnly uses existing metadata refresh/reconfigure and builds the new CMake
targets. Do not substitute ManifestOnly for rebuilding. The script requires
a Verified build manifest and verifies each native executable/runtime DLL set.
`-SourceOnly` explicitly leaves native gates NotRun. Without `-RunModelTests`,
the report is `PolicyPassedModelNotRun`; a missing executable or failed model
gate is not a skipped correctness pass.

The script uses `R4QsaUnionVulkan`, `UnslothPle16` and `UnslothMtp` from
`local.psd1`; optional LocalConfig/BuildKey/ModelKey/DraftModelKey parameters
support existing aliases. The model gate clears inherited experiments, sets
the validated MoE/union controls and restores the caller's environment.
Logs and `result.json` are under
`evox2-logs\tests\<timestamp>-mtp-dense-indexer`, including failure logs.

## Gate B: three allocation smokes and five short runs

After gate A, use a dedicated measurement session:

```powershell
Get-ChildItem Env: | Where-Object {
    $_.Name -match '^(LLAMA_MTP_|LLAMA_QSA_|QWEN4EXP_QSA_|GGML_VK_)' -or
    $_.Name -eq 'LLAMA_GRAPH_REUSE_DISABLE' -or $_.Name -match '^EVOX2_(AB|ABBA)_'
} | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
$env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
$env:GGML_VK_GET_ROWS_128X4 = '0'
$env:GGML_VK_QSA_UNION = '1'
$env:LLAMA_MTP_DIAG = 'off'
$smoke = @{
    BuildKey = 'R4QsaUnionVulkan'; ModelKey = 'UnslothPle16'
    Context = 32768; KvType = 'f16'; UBatch = 1024; Batch = 2048
    Threads = 4; GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
    Fit = 'off'; Temperature = 0; PromptCacheMiB = 0
    ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
}
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke -AllocationOnly
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '0'
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
    -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
    -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
Remove-Item Env:LLAMA_MTP_SKIP_DENSE_INDEXER
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-check.psd1 -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-check.psd1 -StopOnError
```

All smokes must be OK; only the third applies omission. AllocationOnly includes
short generation, so continuation text is expected. Short plan order is
control-mtp-off, A-normal, B-normal, A-wall, B-wall. A/B all have MTP ON,
DraftMax2, DraftPMin0; only omission changes. The short prompt is at 32k
capacity, with 128 output tokens, greedy/top-k1 and seed1234; it is not a
full 32k prompt benchmark. Check Verified identity, output, acceptance/catch-up
and complete reports. Real rejected/partial/full drafts must be observed;
add only another short prompt if coverage is absent. Unexpected divergence
blocks expansion pending repeated A controls and first-logit/state inspection.

## Gate C: two 256k wall runs

After preceding correctness gates pass:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-wall.psd1 -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-wall.psd1 -StopOnError
```

Exactly A-wall and B-wall: both MTP ON and diagnostics wall, A omission=0,
B omission=1. Match existing 256k conditions: 512 output tokens, temp0.2,
top-p0.8, seed1234, ignore-eos, f16, batch2048, ubatch1024, t4/tb4, fit/reasoning
off, cache RAM0/checkpoints0t, MoE legacy1/GET_ROWS128x4=0/union1.

Both reports must be Complete. B must have no draft indexer removal/layout/
pool-state work in prompt or generation; target QSA layout remains. Compare
PP/TG, CPU scopes, acceptance and resources. Do not sum inclusive parents with
their children or interpret Vulkan dispatch CPU time as GPU kernel time.
If draft layout remains, resolve scope/evidence before further collection.
No default sync pair or ROCm rerun is required to check this CPU candidate.

## Gate D: normal 256k ABBA and conditional expansion

After the wall pair confirms work removal with no unresolved correctness issue:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-abba.psd1 -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-abba.psd1 -StopOnError
```

Exactly A1,B1,B2,A2. Both arms have MTP ON, diagnostics off and the same
binary/DLL digest and workload; unique labels distinguish repetitions. Compare
mean TG/generation time, PP/prompt time, PP+TG total, acceptance and memory.
A normal arm with diagnostic events or incomplete output is not valid. Prior
MTP OFF measurements remain the overall reference, not this candidate's A arm.

Only a useful, consistent normal gain justifies preparing 128k confirmation
and subsequent short-context/ROCm checks. This plan includes only 256k and
does not expand into an overnight matrix. Keep default OFF; ambiguous small
differences remain inconclusive, and no default promotion is included.

## State compatibility and scope

Use fresh processes/contexts for A and B. Same-setting restore is a native
gate; cross-setting full saved-state reuse is unsupported by this experiment.
Some sequence readers can ignore an extra suffix, so automatic mismatch
rejection is not promised. Global state format/version is unchanged; exact
byte-count enforcement and clear-on-failure belong to the test harness.

The measured 9.901 seconds of draft layout at 256k selects this candidate,
not an exact normal-speedup prediction. Dense inference, hidden transfer and
target layout remain. Target suffix/no-op maintenance needs a separate design
for sharing, pool boundaries, position changes and restore invalidation.
MTP PP and ROCm PP scaling remain next; COMMON-005 decode stays deferred.

Related:
[plan](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-PLAN-2026-10-04.md),
[source review](R4-COMMON002-LAYOUT-SOURCE-REVIEW-2026-10-04.md),
[wall baseline](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md),
[roadmap](ROADMAP.md).
