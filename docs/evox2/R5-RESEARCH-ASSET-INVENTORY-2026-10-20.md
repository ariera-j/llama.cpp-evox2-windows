# r5 research assets consolidated — 2026-10-20

**Scope: documentation and opt-in measurement assets only. NO inference-engine/source optimization was merged.** Target date for **separately authorized** latest-upstream integration work: **around 2026-10-25 or 2026-10-26** (tentative, not a scheduled automated task). The current pinned r5 runtime and baseline remain unchanged.

## Inventory and provenance

This sync identified eleven r5 investigation branches and checked the tracked r5 stable Git trees. Completed 10/11–10/14 DENSE/NOOP, PP and Vulkan OFF-FA reports were **already present in stable**; do not replace them with older branch versions. The following **five** historical documents were missing and copied without modifying their contents:

| Document now in stable | Source branch | What it preserves |
| --- | --- | --- |
| [Stage-B/flatten RGP, ABBA and implementation](R5-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-16.md) | `investigation/r5-mtp-rollback-diagnostic-20261019` | branch-only source, shader findings, ABBA |
| [Flatten shape investigation](R5-MTP-EH-PROJ-SHAPE-INVESTIGATION-2026-10-16.md) | `investigation/r5-mtp-rollback-diagnostic-20261019` | projection-shape choice |
| [Draft K/V numerical and 128k full-state parity](R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md) | `investigation/r5-mtp-rollback-diagnostic-20261019` | b11682 C/A/B, exact K/V and saved-state parity |
| [Rollback/replay events, through 64k](R5-MTP-ROLLBACK-DIAGNOSTIC-2026-10-19.md) | `investigation/r5-mtp-rollback-diagnostic-20261019` | b11695 64k forced restore/replay, short accept-all caveat |
| [Target re-warmup negative control](R5-MTP-PP-TARGET-REWARMUP-30511-2026-10-16.md) | `investigation/r5-mtp-pp-target-rewarmup-30511-20261016` | #30511 same-binary 64k ABBA no material long-PP gain |


### 2026-10-21 ROCmFPx / integration-rehearsal documentation sync

Six additional canonical reports were copied to stable r5 without importing experimental inference source:

| Document now in stable | Source branch | What it preserves |
| --- | --- | --- |
| [ROCmFPx core implementation](R5-COMMON003A-ROCMFPX-CORE-IMPLEMENTATION-2026-10-20.md) | `investigation/r5-rocmfpx-vulkan-20261020` | COMMON-003A format/core + CPU fallback port |
| [ROCmFPx full port/validation plan](R5-ROCMFPX-VULKAN-PORT-PLAN-2026-10-20.md) | `investigation/r5-rocmfpx-vulkan-20261020` | isolated target/MTP validation through 256k / wide verify |
| [VULKAN-001A correctness implementation](R5-VULKAN001A-ROCMFPX-CORRECTNESS-IMPLEMENTATION-2026-10-20.md) | `investigation/r5-rocmfpx-vulkan-20261020` | Vulkan correctness/dequant/copy path |
| [VULKAN-001B integer-dot implementation](R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-21.md) | `investigation/r5-rocmfpx-vulkan-20261020` | MMVQ/MMQ/MUL_MAT_ID and 140/140 width gate |
| [NOOP + ROCmFPx runtime integration rehearsal](R5-NOOP-ROCMFPX-INTEGRATION-CHECK-2026-10-21.md) | `integration-check/r5-noop-rocmfpx-20261021` | VULKAN-002 + DENSE + NOOP + ROCmFPx + old-HC runtime coexistence |
| [Stage-B + flatten source integration rehearsal](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md) | `integration-check/r5-noop-rocmfpx-stageb-flatten-20261021` | source-level coexistence of Stage-B/flatten with the combined stack |

The current integration ordering is now centralized in [R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md).

### 2026-10-21 post-integration optimization research snapshot

[R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md) preserves the current external-source review and final provisional priority after the integrated candidate is frozen. It consolidates s1/Strata research with halo-box, tetherto, Gufo Windows, pwilkin and wider upstream/fork evidence, plus the DeepSeek review corrections.

This is **documentation/research only**: no new Windows build, Evo-X2 benchmark or source adoption was performed. It does not alter the first integration candidate. The snapshot's current order is audit/MMVQ widths → transposed CONCAT → residual Vulkan FA → select remaining GPU/host work from measured cost → smaller-weight/Draft/QSA follow-ups. Re-check all upstream PR and donor states at the actual post-integration start rather than treating the 2026-10-21 revisions as permanent pins.

**Other existing stable documents**: [PATCHES.md](PATCHES.md), [ROADMAP.md](ROADMAP.md), [research/integration plan](R5-RESEARCH-AND-INTEGRATION-PLAN-2026-10-19.md), [Stage-B Stage1 implementation](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md), [RGP evidence](R5-MTP-EH-PROJ-FLATTEN-RGP-2026-10-19.md), MTP-DENSE/NOOP reports, [performance research log](PERFORMANCE-RESEARCH-LOG.md), and [Vulkan FA dispatch diagnostics](R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md). The long-lived log and stable PATCHES/ROADMAP are more current than older branch snapshots; this sync does **not** overwrite them.

### Tool copies in `tools/evox2/`

**Copied 26 tool files**; the original source blobs are preserved bit-for-bit. These are archival/reproduction **assets, not active production features**:

| Class | Count | Location / source |
| --- | ---: | --- |
| MTP K/V and rollback analyzers + PP trace aggregator | 3 | `benchmark/analyze_mtp_kv_parity.py`, `analyze_mtp_rollback.py`, `summarize_mtp_pp_trace.py` from rollback branch |
| Stage-B / flatten / PP trace / Vulkan RGP / K/V / rollback diagnostic plans | 11 | `benchmark/configs/qwen38-r5-mtp-*.psd1` from rollback branch |
| Python regression tests for PP/RGP/KV/rollback analyzers | 6 | `tests/test_mtp_*.py` from rollback branch |
| MTP-NOOP Vulkan/ROCm short and ABBA plans | 4 | `benchmark/configs/qwen38-r5-mtp-noop-*.psd1` from NOOP branch |
| MTP-NOOP experimental PowerShell test | 1 | `tests/Test-R5QsaNoopInvalidation.ps1` from NOOP branch (renamed only to preserve the existing r4 `Test-QsaNoopInvalidation.ps1`) |
| Re-warmup extended Stage1 plan variant | 1 | `benchmark/configs/archive/qwen38-r5-mtp-kv-crop-stage1-rewarmup-20261016.psd1` from rewarmup branch (renamed to avoid replacing the newer general Stage1 plan) |

**Important:** Plans refer to `R5Mtp...` local BuildKeys, opt-in environment flags, and compiled changes **present only in their historical investigation branches**. Running the plans against pinned stable r5 does *not* recreate the experiment and may fail/produce irrelevant controls. Keep original source branch, exact binary SHA and model/input hashes from the respective reports. Source scripts imported here have NOT been retested solely by this Git copy. Native result ZIPs / raw RGP captures / local GGUF and generated state snapshots were not copied.

For rollback stress, `--spec-synth-rates` forces artificial accept/reject; **synthetic generated text is not suitable as a model-quality baseline**. Strict short Accept-all was not a no-rejection PASS because two identical C/A/B rejects occurred; potential drafted EOG guard was not directly instrumented. 64k forced rollback and replay C/A/B passed.

### Deliberate exclusions and no-overwrite rule

- **NOT copied:** `common/`, `src/`, `ggml/`, `tools/server/` inference source or experimental C++ headers; specifically exclude checkpoint-force and trace hooks from production.
- **NOT overwritten:** stable `tools/evox2/benchmark/{Evox2.Benchmark.psm1,Invoke-BenchmarkMatrix.ps1,Measure-LlamaBench.ps1,Measure-LlamaCli.ps1,Monitor-LlamaProcess.ps1}`, `tools/evox2/lib/Evox2.Common.psm1`, ADLX/P-MODE monitoring implementation, benchmark manifests or stable QSA test. Older branches lack newer measurement/monitoring fixes.
- **2026-10-21 status:** validated ADLX/P-MODE monitoring source is tracked on stable r5 (`tools/evox2/adlx-gpu-monitor/`, `tools/evox2/pmode/`, benchmark wrappers and `Evox2.Common.psm1`) and is now part of the required integration measurement plan. Preserve these newer stable copies; do not replace them with older experiment-branch variants. Local working-tree cleanliness still has to be checked before switching integration branches, but there is no remaining plan to reconstruct ADLX/P-MODE from investigation branches.
- The legacy `Test-QsaNoopInvalidation.ps1` still covers its original r4 use. r5 experiment variant is kept under a distinct name; executing native test requires the experimental NOOP implementation and corresponding binaries.
- Re-warmup plan variant kept in `configs/archive/` intentionally because the general Stage1 plan already has a newer differing set of cases.

## Next preparation checkpoint

1. Keep the pinned r5 runtime/binaries as controls; this documentation sync does not merge inference optimizations into stable.
2. At the integration session, re-check upstream and freeze one exact immutable SHA before source edits; follow [R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md).
3. Build untouched new-upstream Vulkan/ROCm baselines first, using the stable ADLX/P-MODE benchmark harness for provenance.
4. Port required functionality semantically: COMMON-001 if needed, ROCmFPx core/Vulkan, native MTP compatibility, VULKAN-002, DENSE, NOOP, Stage-B, then flatten. Do not copy whole files from isolated branches.
5. Validate the combined candidate with backend tests, short all-on gates, bounded 64k/128k, final 256k only when stable, and explicit ROCm compile/runtime DLL provenance.
6. Decide promotion only after recorded native results and the Gemma 4 regression gate; never equate consolidated documentation with accepted/enabled source optimizations.

## Source branches catalog

- Latest combined rollback and Stage-B/flatten: [rollback investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-rollback-diagnostic-20261019)
- Separate target re-warmup control: [rewarmup investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-target-rewarmup-30511-20261016)
- DENSE/NOOP plans: [NOOP investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-noop-20261012)
- Earlier source experiments are retained on `investigation/r5-mtp-dense-compat-20261011`, `investigation/r5-mtp-dense-indexer-20261011`, `investigation/r5-mtp-pp-trace-20261013`, `investigation/r5-mtp-pp-kv-crop-stage1-20261014`, `investigation/r5-mtp-eh-proj-flatten-20261016`, `investigation/r5-vulkan-off-fa-dispatch-20261010`, and `investigation/r5-adlx-gpu-monitor-20261015`. None was merged into stable inference source here.
