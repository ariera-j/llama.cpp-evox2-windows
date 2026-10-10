# Evo-X2 upstream-refresh overview

This directory contains downstream documentation for the Windows Evo-X2 work in this repository.

## Current refresh

r5 began as a clean upstream-first refresh pinned at `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Documentation/tooling were imported from r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8`. Since the clean baseline, r5 has selectively added COMMON-001, real-prompt llama-bench and opt-in Vulkan QSA grouped union/statistics. **Windows Vulkan/ROCm builds, model-loading and the 64k/128k corpus PP comparison were validated by 2026-10-10**; read the dated r5 reports for exact builds and gates.

The durable current identity is [CURRENT-REFRESH.json](CURRENT-REFRESH.json). Start with [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md) and follow [UPSTREAM-REFRESH.md](UPSTREAM-REFRESH.md) for the next refresh cycle.

The validated r3 comparison branch and the [r4 checkpoint](R4-CHECKPOINT-2026-10-09.md) remain available. Their implemented patches and results do not describe the initial r5 source.

Use the same source revision for Vulkan and ROCm. Re-port only downstream changes justified by the clean baseline and the roadmap.

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

- [CURRENT-REFRESH.json](CURRENT-REFRESH.json): current branch and pinned source identities
- [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md): r5 bootstrap and pending validation gates
- [UPSTREAM-REFRESH.md](UPSTREAM-REFRESH.md): reusable branch/import/verification procedure
- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md): current r4 implementation state, open gates, investigation heads and r5 validation decision
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): upstream/model/engine research and the latest priority rationale
- [ROADMAP.md](ROADMAP.md): current optimization order and upstream-refresh policy
- [BASELINE.md](BASELINE.md): current pending validation gates and preserved r4/r3 measurements
- [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md): Vulkan build procedure
- [BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md): ROCm 10.0 / TheRock build and runtime procedure
- [BENCHMARKING.md](BENCHMARKING.md): measurement methodology and logging requirements
- [PATCHES.md](PATCHES.md): downstream patch registry and status
- [R4-BUILD-LOAD-VALIDATION-2026-10-03.md](R4-BUILD-LOAD-VALIDATION-2026-10-03.md): build/load results and ROCm test discrepancy

## Historical investigation documents imported from r4 (2026-10-10)

These records were copied from the two now-superseded `investigation/` branches **with the original experiment narrative preserved**. Their opening/closing annotations describe the later r5 ports and point to the current comparisons. The original investigations refer to older b11427/b11433 code, environment flags, and some different source-text slices; do not reuse them as current r5 settings.

- [R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md): real-file llama-bench semantics, r4 64k/256k real-vs-random PP comparisons, b11433 OFF rank reversal and related MoE tile caveats
- [R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md](R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md): original diagnostic design, CSV column meanings, group-weighted aggregation, 64k/256k union figures and error/overhead caveats

Original fixed investigation heads: `investigation/llama-bench-real-prompt-20261007` `e3466e8fa769928140f81c93c84889860732ff82` and `investigation/vulkan-qsa-union-stats-20261008` `979ef17eeff14440a58c866a966b355a1b63b17e`.

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

r5 completed baseline and follow-up PP measurements by 2026-10-10; the old checklist below is historical decision context, **not a current pending-validation status**. For active evidence see [r5 Vulkan 64k/128k real-document A/B](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md), [Vulkan 64k seven-corpus union statistics](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md), [Vulkan 128k union statistics](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md), and [ROCm vs Vulkan 64k/128k](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md). The Vulkan OFF FA dispatch investigation is isolated in [`investigation/r5-vulkan-off-fa-dispatch-20261010`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-vulkan-off-fa-dispatch-20261010), **not merged into stable r5**.

- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md) and [ROADMAP.md](ROADMAP.md): current r4 checkpoint and next r5 validation order.
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): 2026-10-09 research, real/random PP findings and refresh priorities.
- [BASELINE.md](BASELINE.md): completed six-run clean baseline through 256k.
- [R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md): source audit, historical comparisons, and Vulkan diagnosis before optimization ports.
- [PERFORMANCE-CANDIDATES-2026-10-03.md](PERFORMANCE-CANDIDATES-2026-10-03.md): external engine survey and additional candidates, after the existing patch decisions.
