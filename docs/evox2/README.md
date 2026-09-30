# Evo-X2 r3 overview

This directory contains downstream documentation for the Windows Evo-X2 work in this repository.

## Design principle

r3 is an **upstream-first** rebuild of the Evo-X2 work.

Instead of carrying a large mixed patch stack from an older fork, r3 starts from one exact upstream llama.cpp revision and then applies downstream changes in small, independently testable steps.

The current base is:

```text
llama.cpp build: b11247
commit: 0bc845d356f437d5ce4fe975c36428f7522829cb
```

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

Upstream AI-agent instruction files are intentionally not part of the downstream r3 working tree. They describe contribution rules and agent behavior for the upstream project, while this repository is used as a private/downstream experimentation environment.

## Tooling layout

The r3 tooling cleanup is now in place:

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
├─ model/
│  ├─ Convert-Unsloth-Ple16.ps1
│  ├─ verify-ple-layout.py
│  └─ README.md
└─ experiments/
   └─ qsa/
```

This layout separates reusable build/benchmark infrastructure from
experiment-specific controls.

Build wrappers write `evox2-build.json` manifests and can reuse a shared
dependency cache outside the repository. Benchmark wrappers consume detected
runtime/build facts rather than trusting lookup-key labels.

## Documentation map

- [ROADMAP.md](ROADMAP.md): current optimization order and upstream-refresh policy
- [BASELINE.md](BASELINE.md): exact baseline, validation, and current reference results
- [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md): Vulkan build procedure
- [BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md): ROCm 10.0 / TheRock build and runtime procedure
- [BENCHMARKING.md](BENCHMARKING.md): measurement methodology and logging requirements
- [PATCHES.md](PATCHES.md): downstream patch registry and status

## Historical documents

Older r1/r2 Evo-X2 documents are historical records. They may refer to:

- a LaurentZuijdwijk-based source tree
- selected upstream backports
- older build directories
- older patch names
- PLE16-converted models
- r2 QSA grouped-union experiments

Do not use historical r1/r2 instructions as r3 build instructions unless the relevant step has been explicitly carried forward into the r3 documents.
