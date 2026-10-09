# Evo-X2 r4 overview

This directory contains downstream documentation for the Windows Evo-X2 work in this repository.

## Design principle

r4 is an **upstream-first** refresh from a newly pinned upstream revision.

r3 is frozen at `0a93fcbb8e5bcf51b331275c4f4b142d822168d6` as the comparison checkpoint. r4 first establishes clean Vulkan/ROCm build, load, and performance baselines, then applies only downstream changes justified by measurements.

The current base is:

```text
branch: r4/upstream-refresh-20261002
upstream base: bed0a856606ee4a24a164066f73d2379447033f5
```

The clean Vulkan/ROCm baseline is preserved. r4 now contains MoE legacy tile
selection, COMMON-001 split PLE16 support, VULKAN-002 grouped-union, a minimal
dense MTP pool-input guard and two opt-in TG candidates. The historical
COMMON-002 compatibility patch was not ported wholesale. MTP PP overhead and
ROCm long-context PP scaling remain unresolved; the real-prompt bench and union
statistics features remain on separate investigation branches.

The next phase is a separate **r5 latest-upstream validation**, with the upstream
SHA to be pinned when that branch is created. See
[R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md) for implemented controls,
validation limits and preserved branch heads, and [ROADMAP.md](ROADMAP.md) for
the r5 sequence.

The same source revision is used for both Vulkan and ROCm. Backend differences are created by build configuration, not by maintaining separate permanent source trees.

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

Upstream AI-agent instruction files are intentionally not part of the downstream r4 working tree. They describe contribution rules and agent behavior for the upstream project, while this repository is used as a private/downstream experimentation environment.

## Tooling layout

The reusable r3 build and benchmark tooling is imported from the frozen checkpoint:

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

`model/` and `experiments/` remain on r3 and are not imported at this stage.
The initial clean-baseline plan is `benchmark/configs/qwen38-r4-clean.psd1`;
use the dated validation reports for subsequent patch/MTP measurement plans.
Copy `local.example.psd1` to a new ignored `local.psd1`, set the r4 build paths and original model path (first GGUF shard), and reuse the actual input paths.

Build wrappers write `evox2-build.json` manifests and can reuse a shared
dependency cache outside the repository. Benchmark wrappers consume detected
runtime/build facts rather than trusting lookup-key labels.

## Documentation map

- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md): current r4 implementation state, open gates, investigation heads and r5 validation decision
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): upstream/model/engine research and the latest priority rationale
- [ROADMAP.md](ROADMAP.md): current optimization order and upstream-refresh policy
- [BASELINE.md](BASELINE.md): r4 source identity and pending validation gates; links to historical r3 results
- [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md): Vulkan build procedure
- [BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md): ROCm 10.0 / TheRock build and runtime procedure
- [BENCHMARKING.md](BENCHMARKING.md): measurement methodology and logging requirements
- [PATCHES.md](PATCHES.md): downstream patch registry and status
- [R4-BUILD-LOAD-VALIDATION-2026-10-03.md](R4-BUILD-LOAD-VALIDATION-2026-10-03.md): build/load results and ROCm test discrepancy

## Historical documents

Older r1/r2/r3 Evo-X2 documents are historical records. They may refer to:

- a LaurentZuijdwijk-based source tree
- selected upstream backports
- older build directories
- older patch names
- PLE16-converted models
- r2 QSA grouped-union experiments

Use the r4 build guides for current commands. The dated r3 validation/profiling documents and R3-BASELINE.md are retained as historical comparison evidence.

## Current performance decisions

- [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md) and [ROADMAP.md](ROADMAP.md): current r4 checkpoint and next r5 validation order.
- [PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md): 2026-10-09 research, real/random PP findings and refresh priorities.
- [BASELINE.md](BASELINE.md): completed six-run clean baseline through 256k.
- [R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md): source audit, historical comparisons, and Vulkan diagnosis before optimization ports.
- [PERFORMANCE-CANDIDATES-2026-10-03.md](PERFORMANCE-CANDIDATES-2026-10-03.md): external engine survey and additional candidates, after the existing patch decisions.
