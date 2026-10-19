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
- The local Windows worktree previously showed uncommitted P-MODE/ADLX tracking modifications and untracked `tools/evox2/adlx-gpu-monitor/` and `tools/evox2/pmode/`. **Remote Git tree cannot reveal or import those local uncommitted bytes.** This sync does not resolve local `Source.Dirty=true`. Before 10/25–26 integration, inspect `git status --short`, diff the local tooling against stable remote, and commit only verified desired changes on a separate tooling branch if still needed. **Do not use `git reset --hard` or a forced branch switch** and accidentally discard user changes.
- The legacy `Test-QsaNoopInvalidation.ps1` still covers its original r4 use. r5 experiment variant is kept under a distinct name; executing native test requires the experimental NOOP implementation and corresponding binaries.
- Re-warmup plan variant kept in `configs/archive/` intentionally because the general Stage1 plan already has a newer differing set of cases.

## Next preparation checkpoint, not integration now

1. Verify that stable r5 source and existing tracked benchmarking modules have identical blobs before/after this documentation/tool sync. Keep baseline binaries (especially b11682 and b11695) untouched.
2. Review any uncommitted local P-MODE/ADLX tool differences at the user's workstation; plan an isolated tools-only preservation commit if necessary.
3. Around **10/25–26** and **only on explicit new request**, check latest upstream/Unsloth/Strix Halo changes; fork an integration candidate branch and pin the exact upstream SHA. Port Stage-B and flatten separately behind switches, excluding diagnostic checkpoint-force.
4. Validate new candidate (Vulkan first: builds/smoke, 64k/128k correctness, uninstrumented ABBA). ROCm validation should also check **actual compile-time ROCm/HIP SDK and runtime-loaded ROCm/HIP DLL versions**; do not assume they match from labels. Keep ROCmFP4/MTP variants as independent gates.
5. Decide promotion only after recorded native results; never equate consolidated documentation with accepted or enabled source optimizations.

## Source branches catalog

- Latest combined rollback and Stage-B/flatten: [rollback investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-rollback-diagnostic-20261019)
- Separate target re-warmup control: [rewarmup investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-target-rewarmup-30511-20261016)
- DENSE/NOOP plans: [NOOP investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-noop-20261012)
- Earlier source experiments are retained on `investigation/r5-mtp-dense-compat-20261011`, `investigation/r5-mtp-dense-indexer-20261011`, `investigation/r5-mtp-pp-trace-20261013`, `investigation/r5-mtp-pp-kv-crop-stage1-20261014`, `investigation/r5-mtp-eh-proj-flatten-20261016`, `investigation/r5-vulkan-off-fa-dispatch-20261010`, and `investigation/r5-adlx-gpu-monitor-20261015`. None was merged into stable inference source here.
