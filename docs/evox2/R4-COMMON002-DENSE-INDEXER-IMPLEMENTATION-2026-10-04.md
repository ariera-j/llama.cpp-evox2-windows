# r4 COMMON-002: dense MTP indexer implementation and Windows gates

Implemented on `r4/upstream-refresh-20261002` from planning baseline
`c167f7abfb4582d8ad46305b135076bcf14859b5`; upstream remains pinned at
`bed0a856606ee4a24a164066f73d2379447033f5`.

Status: runtime switch, native tests, Windows gate script and three benchmark
plans are implemented. Local checks pass below. Windows build/linkage,
PowerShell execution, real model/state/rollback gates and GPU measurements
are pending. No speedup or model correctness pass is asserted yet.

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
