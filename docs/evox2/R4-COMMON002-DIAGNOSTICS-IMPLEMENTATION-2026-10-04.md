# r4 COMMON-002: implemented MTP diagnostics and Windows handoff

Recorded: 2026-10-04 JST. Implementation based on
`c1d8dcfc8a7bbea8b1159529ec1f040f48402245`, branch
`r4/upstream-refresh-20261002`. Upstream pin remains
`bed0a856606ee4a24a164066f73d2379447033f5`.

The [implementation plan](R4-COMMON002-DIAGNOSTICS-IMPLEMENTATION-PLAN-2026-10-04.md)
is now implemented. Windows build, allocation, generation and GPU validation
are pending. This patch measures the existing path; it does not implement a
performance candidate or claim a speedup.

## Implemented observations

`LLAMA_MTP_DIAG` is read once per loaded component. Unset, empty, `0` and `off`
disable diagnostics. `wall` preserves the existing synchronization behavior.
`sync` additionally drains the relevant target/draft context before evaluations
and at completion. Invalid values warn and disable the feature.

Records use `mtp_diag v=1` with begin/end, monotonic timestamps, event/parent
IDs, thread, context/memory identity, role, phase, return code and completeness.
The shared private helper is `ggml/src/ggml-mtp-diag.h`; common and llama have
small private logging adapters. There is no added public C API.

| Location | Measurements |
|---|---|
| Server | Target evaluation/process/existing wait, draft round, catch-up, verification/acceptance, target/draft suffix removal and completion timing summary |
| MTP implementation | Catch-up preparation and evaluations; target hidden getter; verified hidden carry; draft evaluations, sampling, hidden getter and acceptance carry |
| Hybrid indexer memory | Recurrent/indexer/attention sequence removal; CPU layout time, full/stale rebuild counts, copied/appended cells and visited scan steps; pool-state construction and logical/padded new pools |
| Vulkan | Backend graph invocation and the selected union/sparse/dense FA dispatch, tensor identifier, query and KV counts |

Hidden-row getter/copy times and bytes are accumulated within an existing loop,
without per-row log emission. Getter time can include synchronization. Pending
row carry and vector resizing remain within the enclosing carry time, so
`copy_us` alone is not all hidden-state handling.

Vulkan emits one scope per FA operation, rather than a single accumulated graph
record proposed in the plan. The summarizer groups these by phase/role/path/query
count, while retaining individual records and enclosing graph scopes. These
records measure CPU command construction and selected dispatches, not completed
GPU kernels, union utilization or compacted rows. They add no GPU readbacks.

`target_evaluation` identifies actual batch token count. Generation queries above
one distinguish verification-shaped work in the serial workload, but do not
define phase: server state defines prompt/generation/mixed/unknown. Cross-module
memory roles use registered memory-interface pointers. Cross-DLL parent matching
uses same-thread containment; asynchronous worker records can remain unknown.

Diagnostics off produces no diagnostic allocation, clock calls, formatting or
logs, and adds no synchronization. Disabled scopes and small guarded branches
remain in the code. Existing acceptance, rollback, pool update, graph reuse,
DraftMax and Vulkan branch-selection logic are preserved.

## Build identity and benchmark integration

Real `-BuildOnly` builds now validate the existing source/backend cache and run
`cmake -S <source> -B <existing build>` before compilation, preserving cached
generator/toolchain/options. The action is recorded as
`Configure.MetadataRefresh`, rather than a full configure. Build-start and
build-end Git identity and the embedded executable commit are checked. A real
build mismatch saves its manifest and then fails; `-ManifestOnly` records an
unverified identity and warns on stale labels without rebuilding.

Runtime exe/DLL SHA-256 identities are compared against the existing manifest
before measurement. Enumeration includes installed CPU DLL variants and known
llama runtime DLLs. Known mismatches fail measurement; missing/legacy manifests
remain explicitly unverified. A verified artifact-set digest participates in
the condition fingerprint. This checks the bounded local artifact set, not
system driver provenance or which DLLs the operating system actually loaded.

Normal r4 matrix defaults explicitly clear `LLAMA_MTP_DIAG`. With wall/sync
enabled, `Measure-LlamaCli.ps1` automatically runs the new PowerShell summary
wrapper and Python standard-library parser. Python must be on PATH, as for
the earlier GGUF metadata checks; no additional Python packages are needed.

Each run retains ordinary result fields and raw logs, and adds:

- `mtp-diagnostics.json`: events, resolved roles/phases, groups, counters,
  unmatched phase count and completeness issues.
- `mtp-diagnostics.csv`: grouped observations for comparison.
- `result.json`: diagnostic status/report path and runtime artifact status/digest.

Incomplete/missing records cannot become zero-cost observations. Summary failure
changes an otherwise successful run to `DIAGNOSTIC_INCOMPLETE`, so a matrix with
`-StopOnError` stops. Partial diagnostic reports remain available for inspection.

Group times are inclusive and nested: **do not sum all group times**. Exclusive
time subtracts matched child interval unions. Covered server generation time
also uses interval union. The residual against reported TG is approximate and
can be negative because phase boundaries differ; the report flags this instead
of interpreting it as a measured negative operation. Parent timings include
child logging overhead. Diagnostic runs, particularly sync runs, are not normal
performance comparisons.

## Validation completed here

- GCC 13 C++17 syntax checks: `common/speculative.cpp`,
  `src/llama-memory-hybrid-idx.cpp`, `tools/server/server-context.cpp`.
- Nine Python/native-helper tests passed: nested accounting, cross-module roles,
  unknown worker attribution, mixed/error records, duplicate/schema errors,
  interrupted/absent logs, off-mode absence of logs/clock calls, wall/sync parsing
  and exception completeness.
- Python CLI generated both sidecars from actual native-helper records.
- Whitespace checks passed.

This environment has no Windows PowerShell, CMake/Vulkan SDK or Evo-X2 GPU.
The full Vulkan translation unit/build, Windows script parsing/artifact fixtures,
ROCm build and model/GPU execution have not been validated here. The checked-in
`Test-MtpDiagnostics.ps1` performs the Windows parsing/artifact gates; native
helper tests are explicitly skipped if g++ is unavailable there.

## Windows gate A: build, smoke and short generation

Run from the repository root. Reuse the current Vulkan build directory and
`local.psd1` model/draft settings. The example directory below is the existing
`R4QsaUnionVulkan` directory in `local.example.psd1`; adjust only if local.psd1
points elsewhere. Close processes using its exe/DLLs before rebuilding.

```powershell
git pull --ff-only
& .\tools\evox2\tests\Test-MtpDiagnostics.ps1
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r4-qsa-union -BuildOnly
```

Keep any explicit tool paths required by the previous build invocation. Verify
the build's version/device smoke and `BuildIdentity.Status = Verified` in
`bin\Release\evox2-build.json`. Do not use ManifestOnly to replace this rebuild.

In a dedicated measurement session, preserve the validated Vulkan flags and
clear inherited diagnostic/profiler experiments. The matrix does this itself;
for the direct allocation smoke below use:

```powershell
Get-ChildItem Env: | Where-Object {
    $_.Name -match '^(LLAMA_MTP_|LLAMA_QSA_|QWEN4EXP_QSA_|GGML_VK_)' -or
    $_.Name -eq 'LLAMA_GRAPH_REUSE_DISABLE' -or $_.Name -match '^EVOX2_(AB|ABBA)_'
} | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
$env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
$env:GGML_VK_GET_ROWS_128X4 = '0'
$env:GGML_VK_QSA_UNION = '1'
$smoke = @{
    BuildKey = 'R4QsaUnionVulkan'; ModelKey = 'UnslothPle16'
    Context = 32768; KvType = 'f16'; UBatch = 1024; Batch = 2048
    Threads = 4; GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
    Fit = 'off'; Temperature = 0; PromptCacheMiB = 0
    ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
}
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke -AllocationOnly
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @smoke `
    -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
```

AllocationOnly still performs short generation; continuation text is expected.
After both smokes pass, collect three short runs:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-check.psd1 `
    -OnlyVariant @('off', 'on-normal', 'on-wall') -StopOnError
```

Check exit/status, generated text, acceptance/rejection, and complete diagnostic
sidecars. Compare on-normal and on-wall for diagnostic-induced differences;
OFF/ON is not guaranteed byte-identical by existing inference numerics. If
partial rejection is absent, use another short prompt before claiming rollback
coverage. The input path is relative to the repository working directory.
Collect `on-sync` separately if the sync stage is needed. The default short plan
contains all four variants; the command above intentionally selects only three.

## Windows gate B: first long-context collection

After gate A passes, use the unchanged overnight long-context settings:
512 output tokens, temperature 0.2, f16, batch 2048, ubatch 1024, t4/tb4,
DraftMax=2/p-min=0 when enabled, no prompt cache, legacy MoE=1,
GET_ROWS 128x4=0, union=1. The focused plan runs once per condition:

| Order | Context | MTP | Mode |
|---|---|---|---|
| 1 | Vulkan 128k | ON | wall |
| 2 | Vulkan 256k | ON | wall |
| 3 | Vulkan 256k | OFF | wall |

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-diagnostics.psd1 `
    -StopOnError
```

Send the complete run/matrix archive, including stderr, outputs, conditions,
results, resources and sidecars. First compare TG phase/work counters and the
128k/256k change; retain PP observations for the next priority. If async waiting
prevents attribution, use the conditional 256k ON/OFF sync plan:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-diagnostics-sync.psd1 `
    -StopOnError
```

Manual regeneration from an existing diagnostic run is available via
`Summarize-MtpDiagnostics.ps1 -RunDirectory <run directory>`. Use diagnostic mode
off for any later unprofiled ABBA confirmation of a selected performance fix.

## Unsloth mix reference preparation

Start with prebuilt Vulkan: its normal OFF/ON results can determine whether the
long-context reversal occurs without porting r4's diagnostics. Record release
and exe/DLL identities, model/draft, arguments, inputs and raw logs. PLE16 is
downstream support and should not be assumed available in the prebuilt mix.
If loading fails, use original GGUF and obtain a corresponding r4 original
control; keep those results separate from existing r4 PLE16 timings.

Port equivalent diagnostic boundaries and build from source only if the reference
comparison leaves an internal attribution question. Equal record names alone do
not guarantee equivalent fork semantics or timing boundaries.
