# Evo-X2 upstream-refresh overview

This directory contains downstream documentation for the Windows Evo-X2 work in this repository.

## Completed research documentation and sync rule — 2026-10-12

**`r5/upstream-refresh-20261009` is the canonical home for completed r5 research documents**, but is **not an integrated optimized runtime**. The fact that `docs/evox2/` contains an experimental validation report does *not* mean the experimental source, tests, flags, build configuration, or measurement scripts are in this stable branch. [PATCHES.md](PATCHES.md) explicitly separates pinned stable source from experiment-branch source and the scope of validation.

Find research results here:

- **Source and verification matrix:** [PATCHES.md](PATCHES.md); **next research:** [ROADMAP.md](ROADMAP.md) — after MTP DENSE/NOOP TG, investigate MTP ON **PP overhead**.
- **MTP-DENSE-001:** [r5 candidate implementation and 64k–256k Vulkan/ROCm measurements](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md); actual source stays on `investigation/r5-mtp-dense-indexer-20261011`.
- **MTP-NOOP-001:** [implementation + correctness gates](R5-MTP-NOOP-IMPLEMENTATION-2026-10-12.md), [Vulkan 64k–256k](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md), [ROCm 64k–256k](R5-MTP-NOOP-ROCM-VALIDATION-2026-10-12.md), [ROCm 128k detail](R5-MTP-NOOP-ROCM-128K-2026-10-12.md); source/tests/scripts stay on `investigation/r5-mtp-noop-20261012`.
- **MTP ON PP investigation (2026-10-13):** [source trace, 64k/128k OFF/ON baselines, opt-in phase-tracing plan and r2 MTP-QSA no-port decision](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md). Source diagnostics belong only to `investigation/r5-mtp-pp-trace-20261013`; stable r5 carries **documentation only**.
- **MTP Stage-B K/V-only Draft FA-bypass (2026-10-14, b11618 64k ABBA / 128k A/B + MTP-OFF control pass):** [Stage-B implementation, exact K/V cache-write transforms, v2 active-graph diagnostic and Windows stop gates](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md#stage-b-implementation-dense-draft-kv-only-no-fa-graph-root--2026-10-14). Implementation and tests exist only on `investigation/r5-mtp-pp-kv-crop-stage1-20261014`; use the new `R5MtpKvOnlyVulkan` BuildKey, and b11618 active graph validates ON fa=0 and K/V writes 1/1 with identical short output; 64k ABBA with diagnostics disabled also passed: PP +3.63%, TG +2.38%, exact output bytes/acceptance, increasing PP benefit at long KV. 128k A/B additionally passes with PP +6.68%, TG +1.36% inconclusive and exact output/acceptance parity. Historical b11560 MTP OFF is faster but NOT a same-binary baseline; measure MTP OFF on b11618 before declaring full MTP PP overhead fixed. Same-build MTP OFF128k=305.98 PP /23.74 TG vs Stage B ON296.63/23.79, a remaining 13.01s PP penalty. Historical b11560 OFF335.455 PP is 8.79% faster than current OFF: prioritize old-binary contemporary rerun to isolate drift. Draft KV numeric parity/RGP still unverified. Stable r5 inference source unchanged.
- **MTP Stage-A Draft KV prefill graph crop (2026-10-14, 64k functional smoke passed; crop active but FA still present):** [opt-in implementation report, future upstream/Vision caveats, Windows build and A/B instructions](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md); source/tests/plan live **only** on [`investigation/r5-mtp-pp-kv-crop-stage1-20261014`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-kv-crop-stage1-20261014). Stable inference source unchanged. A dedicated active-Draft-graph diagnostic was added subsequently on the experiment branch (`LLAMA_MTP_KV_CROP_DIAG=1` and `stage1-diag-short`); Vulkan b11608 was built and run: active graph 133→44 nodes, but Flash Attention remains 1 node. K/V-name matching needs correction; the next experiment should bypass `build_attn_mha()` while preserving K/V writes.
- **ADLX / display / power / P-MODE instrumentation (2026-10-15):** [automatic ADLX validation, overhead ABBA, P-MODE performance split, ACPI-WMI raw/event mapping and ImagesShow analysis](R5-ADLX-PMODE-VALIDATION-2026-10-15.md). Source/tooling lives on `investigation/r5-adlx-gpu-monitor-20261015`; stable r5 is not yet updated with this investigation branch.\n- **Earlier MTP controls and compatibility:** [Unsloth sidecar](R5-COMMON002-DENSE-MTP-COMPAT-2026-10-11.md), [Vulkan](R5-MTP-VULKAN-64K128K-ABBA-2026-10-11.md) and [ROCm](R5-MTP-ROCM-64K128K-ABBA-2026-10-11.md) baseline measurements, [r2–r5 recheck](R5-MTP-TG-R2-R5-RECHECK-2026-10-11.md), [Agention FP4 risks](R5-MTP-AGENTION-FP4-INTERACTION-2026-10-11.md).

**Repeatable documentation sync:** finish the experiment report with the branch name, actual *compiled* commit/build/binary fingerprint, conditions and raw log ZIP checksums; at a test milestone, copy the **finalized documentation files only** onto this docs home. Merge **content** of PATCHES/ROADMAP/README rather than replacing canonical indices blindly. **Do not merge/cherry-pick a source experiment into stable simply to sync docs**, and do not overwrite stable-specific investigation logs or upstream pins. Keep original raw ZIPs external to Git, linked by file name/sha. Time-stamped historical “NEXT” messages are snapshots, not current instructions. Choose the next stable docs home explicitly at a future refresh instead of implicitly scattering new reports.

## Current refresh

r5 began as a clean upstream-first refresh pinned at `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Documentation/tooling were imported from r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8`. Since the clean baseline, r5 has selectively added COMMON-001, real-prompt llama-bench and opt-in Vulkan QSA grouped union/statistics. **Windows Vulkan/ROCm builds, model-loading and the 64k/128k corpus PP comparison were validated by 2026-10-10**; read the dated r5 reports for exact builds and gates.

The durable current identity is [CURRENT-REFRESH.json](CURRENT-REFRESH.json). Start with [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md) and follow [UPSTREAM-REFRESH.md](UPSTREAM-REFRESH.md) for the next refresh cycle.

The validated r3 comparison branch and the [r4 checkpoint](R4-CHECKPOINT-2026-10-09.md) remain available. Their implemented patches and results do not describe the initial r5 source.

Use the same source revision for Vulkan and ROCm. Re-port only downstream changes justified by the clean baseline and the roadmap.

### Research lane and planned integrated lane (2026-10-11)

This is a hobby research project: pinned research branches are allowed to run until a hypothesis is closed even if upstream refreshes weekly. On each research branch, COMMON-001 is restored to compare PLE16 models; additional downstream patches are applied only when relevant to that particular investigation. A separate future integration session will evaluate the recorded beneficial candidates on a selected newer upstream, approximately every 4–6 weeks if convenient or at a natural stopping point.

**No integrated snapshot has been created yet.** The first is planned for a future checkpoint; do not treat r5 or a current measurement as an all-patches integrated build. The proposed integrated branch/tag convention and acceptance procedure are in [INTEGRATION-POLICY.md](INTEGRATION-POLICY.md); pending and accepted snapshots are tracked in [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md). The [PATCHES.md cross-branch matrix](PATCHES.md) distinguishes implemented, validated, upstream-covered, and merely proposed candidates.

## Target machine

Primary validation machine:

```text
GMKtec Evo-X2
AMD Ryzen AI Max+ 395
Radeon 8060S
GPU architecture: gfx1151
System memory: 128 GB unified memory
Typical BIOS UMA allocation used for long-context tests: 96 GB
Windows 11
```

The manual `96GB` label used in benchmark files describes the configured test condition. Benchmark scripts should not pretend to detect the BIOS setting automatically unless they actually do so.

## Current toolchains

### Vulkan

```text
LLVM/Clang 20.1.8
Vulkan SDK 1.4.357.0
CMake 4.3.1
Ninja 1.13.2
```

### ROCm

```text
ROCm 10.0.0 / TheRock
ROCm compiler: Clang 23.0.0
Visual Studio 2022 Build Tools
MSVC 14.44.35207
GPU target: gfx1151
```

ROCm 10.0 requires the `device-gfx1151` package for the rocBLAS/Tensile runtime data used by real model inference.

## Repository policy for downstream files

The normal upstream source tree and documentation are kept as intact as practical.

Downstream-specific material is concentrated in:

```text
docs/evox2/
tools/evox2/
```

The root `README.md` is downstream-specific.

Upstream instruction files are retained unchanged. The pinned upstream AGENTS.md explicitly excludes another repository or fork from its contribution rules. Re-check its actual scope at each refresh; this downstream repository uses the Evo-X2 procedures here.

## Tooling layout

The build and benchmark tooling is carried from the pinned r4 checkpoint:

```text
tools/evox2/
├─ build/
│  ├─ Build-Vulkan.ps1
│  ├─ Build-ROCm.ps1
│  ├─ Evox2.Build.psm1
│  ├─ Evox2.DependencyCache.psm1
│  └─ README.md
├─ benchmark/
│  ├─ Evox2.Benchmark.psm1
│  ├─ Measure-LlamaCli.ps1
│  ├─ Measure-LlamaBench.ps1
│  ├─ Monitor-LlamaProcess.ps1
│  ├─ Invoke-BenchmarkMatrix.ps1
│  └─ configs/
└─ lib/
   └─ Evox2.Common.psm1
```

The clean plan is `benchmark/configs/qwen38-clean.psd1`; dated r3/r4 plans are historical references. Copy `local.clean.example.psd1` to ignored `local.psd1`, point `CleanVulkan` / `CleanROCm` at the new binaries, and reuse the actual model/input paths. Leave `LogRoot` empty for logs in the new worktree.

Use explicit `-BuildDir .\build-vulkan-clean` / `.\build-rocm-clean`; imported wrappers retain historical r4 defaults. See the dated r5 handoff before running imported experimental tests.

Build wrappers write `evox2-build.json` manifests and can reuse a shared
dependency cache outside the repository. Benchmark wrappers consume detected
runtime/build facts rather than trusting lookup-key labels.

## Documentation map

- [CURRENT-REFRESH.json](CURRENT-REFRESH.json): current research branch and pinned source identities
- [INTEGRATION-POLICY.md](INTEGRATION-POLICY.md): optional upstream intake, selective porting and future integrated-snapshot gates
- [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md): integrated snapshot index (first release not yet created)
- [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md): r5 bootstrap and pending validation gates
- [UPSTREAM-REFRESH.md](UPSTREAM-REFRESH.md): reusable branch/import/verification procedure
- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md): current r4 implementation state, open gates, investigation heads and r5 validation decision
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): upstream/model/engine research and the latest priority rationale
- [ROADMAP.md](ROADMAP.md): current optimization order and upstream-refresh policy
- [BASELINE.md](BASELINE.md): current pending validation gates and preserved r4/r3 measurements
- [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md): Vulkan build procedure
- [BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md): ROCm 10.0 / TheRock build and runtime procedure
- [BENCHMARKING.md](BENCHMARKING.md): measurement methodology and logging requirements\n- [R5-ADLX-PMODE-VALIDATION-2026-10-15.md](R5-ADLX-PMODE-VALIDATION-2026-10-15.md): ADLX benchmark integration/overhead, display/power-state validation and Evo-X2 P-MODE performance + WMI/event mapping
- [PATCHES.md](PATCHES.md): downstream patch registry and status
- [R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md](R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md): MTP ON prompt-wall slowdown breakdown plan and historical r2 QSA re-evaluation
- [R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md): verified b11569 Windows short/64k MTP PP phase diagnostic, draft depth trend and resource I/O caveat
- [R5-MTP-PP-TRACE-VULKAN-128K-2026-10-13.md](R5-MTP-PP-TRACE-VULKAN-128K-2026-10-13.md): same-binary b11569 128k Vulkan OFF/ON trace, stage/NextN wait depth trends and GPU-attribution boundary
- [R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md](R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md): pinned r5 target NextN final-layer crop, draft dense FA, Vulkan pinned-host readback/fallback, and bounded RGP evidence gate
- [2026-10-14 Draft K/V-only follow-up](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md#continuation-checkpoint--2026-10-14-outputfalse-is-not-a-kv-only-execution-mode): confirms zero Draft catch-up output flags do not suppress full-row FA/FFN; records implementation/correctness gates and keeps RGP evidence provenance.
- [R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md](R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md): RGP-grounded Vulkan PP candidate ranking, one-layer Draft KV-only graph dependency review and ROCm-before-implementation decision
- [MTP PP Vulkan RGP labels — experimental implementation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-RGP-MARKERS-IMPLEMENTATION-2026-10-14.md): Vulkan debug labels b11577 validated; extended b11587 captured both Target and Draft FA/MoE GPU events.
- [Vulkan MTP RGP dispatch-index calibration (2026-10-14)](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-pp-trace-20261013/docs/evox2/R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md): new opt-in dispatch ordinal logger; **b11587 RGP now confirms Draft dense FA 139.918/139.159ms GPU per 1024 queries at KV=50176/51200, mask ~1.1ms, plus separate draft projection ~57ms**.
- [R4-BUILD-LOAD-VALIDATION-2026-10-03.md](R4-BUILD-LOAD-VALIDATION-2026-10-03.md): build/load results and ROCm test discrepancy

## Historical investigation documents imported from r4 (2026-10-10)

These records were copied from the two now-superseded `investigation/` branches **with the original experiment narrative preserved**. Their opening/closing annotations describe the later r5 ports and point to the current comparisons. The original investigations refer to older b11427/b11433 code, environment flags, and some different source-text slices; do not reuse them as current r5 settings.

- [R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md): real-file llama-bench semantics, r4 64k/256k real-vs-random PP comparisons, b11433 OFF rank reversal and related MoE tile caveats
- [R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md](R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md): original diagnostic design, CSV column meanings, group-weighted aggregation, 64k/256k union figures and error/overhead caveats

Original fixed investigation heads: `investigation/llama-bench-real-prompt-20261007` `e3466e8fa769928140f81c93c84889860732ff82` and `investigation/vulkan-qsa-union-stats-20261008` `979ef17eeff14440a58c866a966b355a1b63b17e`.

Both donor investigations were **selectively ported to r5** rather than merge-committed: real-prompt llama-bench is documented in [R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md), and optional union statistics in [R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md). Their old branches are superseded despite divergent ancestry. The stats investigation head contains the real-prompt head in its history, so preserving a tag at the stats head retains both histories before deleting branch names. Confirm no unpublished local changes and verify the pinned head SHAs before any deletion.

## Historical documents

Older r1/r2/r3 Evo-X2 documents are historical records. They may refer to:

- a LaurentZuijdwijk-based source tree
- selected upstream backports
- older build directories
- older patch names
- PLE16-converted models
- r2 QSA grouped-union experiments

Use the current build guides for commands on this refresh. The dated r3 validation/profiling documents and R3-BASELINE.md are retained as historical comparison evidence.

## Current performance decisions

r5 completed baseline and follow-up PP measurements by 2026-10-10; the old checklist below is historical decision context, **not a current pending-validation status**. For active evidence see [r5 Vulkan 64k/128k real-document A/B](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md), [Vulkan 64k seven-corpus union statistics](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md), [Vulkan 128k union statistics](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md), and [ROCm vs Vulkan 64k/128k](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md). The Vulkan OFF FA dispatch **diagnostic source** is isolated in [`investigation/r5-vulkan-off-fa-dispatch-20261010`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-vulkan-off-fa-dispatch-20261010), **not merged into stable r5**. Its complete [Vulkan FA / mask-tile investigation report](R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md) is archived here on r5 for durable reference. The repeated late-KV result is ~4.1x FA-main GPU time (literature/code), while the completely skippable mask-tile share is 35.68%/75.03% respectively. **Next priority: verify ROCm HIP FA actual kernel/mask-scan/Stream-K runtime and FA time attribution, before attempting any Vulkan optimization or wholesale import of experimental diagnostics.**

- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md) and [ROADMAP.md](ROADMAP.md): current r4 checkpoint and next r5 validation order.
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): 2026-10-09 research, real/random PP findings and refresh priorities.
- [BASELINE.md](BASELINE.md): completed six-run clean baseline through 256k.
- [R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md): source audit, historical comparisons, and Vulkan diagnosis before optimization ports.
- [PERFORMANCE-CANDIDATES-2026-10-03.md](PERFORMANCE-CANDIDATES-2026-10-03.md): external engine survey and additional candidates, after the existing patch decisions.
