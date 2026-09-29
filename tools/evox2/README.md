# Evo-X2 Windows tooling

This directory contains downstream build, benchmark, model-conversion, and experiment utilities for the Evo-X2 Windows work.

The tools are designed around one rule:

> Prefer detected facts over manually typed labels.

A benchmark result should derive its backend, llama.cpp build identity, executable hash, context settings, and other machine-readable metadata from the actual executable and run configuration whenever possible.

The BIOS UMA setting remains a manual test-condition label because the current tooling does not have a reliable method to read the configured BIOS value directly.

## Directory layout

Target r3 layout:

```text
tools/evox2/
├─ README.md
├─ lib/
│  └─ Evox2.Common.psm1
├─ build/
│  ├─ Build-Vulkan.ps1
│  └─ Build-ROCm.ps1
├─ benchmark/
│  ├─ Evox2.Benchmark.psm1
│  ├─ Measure-LlamaCli.ps1
│  ├─ Measure-LlamaBench.ps1
│  ├─ Monitor-LlamaProcess.ps1
│  ├─ Invoke-BenchmarkMatrix.ps1
│  └─ configs/
│     ├─ local.example.psd1
│     ├─ local.psd1
│     ├─ qwen38-baseline.psd1
│     ├─ qwen38-longctx.psd1
│     └─ qwen38-mtp.psd1
├─ model/
│  ├─ Convert-Unsloth-Ple16.ps1
│  └─ verify-ple16.py
└─ experiments/
   └─ qsa/
      ├─ Measure-Qsa-Union.ps1
      └─ Test-Qsa-Union.ps1
```

Not every file above is implemented yet. The r3 migration is intentionally incremental so the measurement framework itself can be validated before downstream inference patches are measured.

## Local logs

All generated Evo-X2 benchmark output should live under the repository-local directory:

```text
<repo>\evox2-logs\
```

For the primary r3 checkout:

```text
C:\llama-build\llama.cpp-evox2-windows-r3\evox2-logs\
```

The directory is ignored by Git.

A future matrix run will use a layout similar to:

```text
evox2-logs/
└─ 20260929-230501-qwen38-r3-baseline/
   ├─ batch.json
   ├─ summary.csv
   └─ runs/
      ├─ 001-cli-rocm-b11247-ctx65536/
      │  ├─ conditions.json
      │  ├─ output.log
      │  ├─ result.json
      │  └─ resources.csv
      └─ 002-bench-rocm-b11247/
         ├─ conditions.json
         ├─ output.log
         ├─ result.json
         └─ resources.csv
```

Detailed conditions belong in JSON/CSV metadata, not only in filenames.

## Machine-local configuration

Copy:

```powershell
Copy-Item `
  .\tools\evox2\benchmark\configs\local.example.psd1 `
  .\tools\evox2\benchmark\configs\local.psd1
```

Then edit `local.psd1` for the local machine.

`local.psd1` is ignored by Git.

It contains machine-specific paths such as:

- Vulkan and ROCm binary directories
- model paths
- private input paths
- log root
- manual UMA label

Aliases such as `R3ROCm` and `UnslothPle16` are lookup keys and human-readable labels. They must not override detected runtime facts.

For example, if a build configured as `R3ROCm` actually reports a Vulkan device, the detected backend must remain `Vulkan`, and an expectation check may fail the run.

## PowerShell compatibility

The scripts are intended to work with Windows PowerShell 5.1 as used on the primary Evo-X2 system. The common module avoids direct array-subexpression conversion of `List[object]`, which can raise `Argument types do not match` on Windows PowerShell 5.1.

## Common metadata module

Import the common module:

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
```

### Repository identity

```powershell
$git = Get-Evox2GitMetadata `
  -RepoRoot 'C:\llama-build\llama.cpp-evox2-windows-r3'

$git | Format-List
```

The metadata includes:

```text
commit
short commit
branch
dirty/clean state
dirty fingerprint
origin URL
porcelain status
```

The dirty fingerprint is a SHA-256 over Git status plus staged and unstaged diffs. It is intended to distinguish modified working trees during local experiments. It is not a hash of every byte in the repository.

### llama.cpp executable identity

```powershell
$cli = 'C:\llama-build\llama.cpp-evox2-windows-r3\build-rocm-b11247\bin\Release\llama-cli.exe'

$exe = Get-Evox2ExecutableMetadata -Executable $cli
$exe | Format-List
```

The module reads `--version` and records:

```text
executable path
SHA-256
file size
llama.cpp build number
llama.cpp commit
compiler
raw version text
```

### Backend and device detection

```powershell
$device = Get-Evox2DeviceMetadata -Executable $cli
$device | ConvertTo-Json -Depth 6
```

The module reads `--list-devices`.

For the tested r3 ROCm build, the expected shape is similar to:

```text
BackendDetected: ROCm
ROCm0: AMD Radeon(TM) 8060S Graphics (...)
```

The backend label is derived from the reported device ID, not from a manually typed benchmark label.

### Combined runtime identity

```powershell
$identity = Get-Evox2LlamaIdentity `
  -Executable $cli `
  -RepoRoot 'C:\llama-build\llama.cpp-evox2-windows-r3'

$identity | ConvertTo-Json -Depth 10
```

This combines executable, device, optional build-manifest, Git, and host-system metadata.

### File identity

For small input files, SHA-256 can be recorded automatically:

```powershell
Get-Evox2FileIdentity `
  -Path 'C:\path\to\input.txt' `
  -Sha256
```

For very large GGUF files, full SHA-256 hashing can take noticeable time. The measurement layer will therefore record path, size, and modification time automatically and can use a cached or explicit full hash when required.

### Stable condition ID

A condition object can be converted to a short deterministic ID:

```powershell
$condition = [ordered]@{
    Backend = 'ROCm'
    Context = 65536
    KvType  = 'f16'
    UBatch  = 1024
    MTP     = $false
}

Get-Evox2ConditionId -Condition $condition
```

The future benchmark layer will use this for grouping repeated runs with the same effective conditions.

## Build manifests

The r3 build scripts will create:

```text
evox2-build.json
```

beside the generated executables.

The manifest will contain build-time facts such as:

```text
backend
source commit
dirty state
compiler
GPU target
build directory
build timestamp
```

Benchmark scripts will read this manifest when available and will still query `llama-cli --version` and `--list-devices` as runtime checks.

Official/prebuilt llama.cpp packages do not need this manifest; the benchmark tools will fall back to runtime detection.

## Benchmark tools

The following tools are planned for the next migration stages.

### `Measure-LlamaCli.ps1`

Primary practical benchmark.

It will:

- run a real input file through `llama-cli`
- preserve model output for quality inspection
- parse PP and TG
- record actual prompt and generated-token counts
- record MTP acceptance when enabled
- write `conditions.json`, `result.json`, and `output.log`
- optionally launch the generic resource monitor by PID

This remains the main benchmark for the Evo-X2 project.

### `Measure-LlamaBench.ps1`

Public reproducibility reference.

It will:

- run synthetic llama-bench workloads
- use the same detected build/model metadata as the CLI wrapper
- record PP/TG and native llama-bench output
- support repeated measurements
- optionally use the generic resource monitor

It is supplemental to the real-input `llama-cli` benchmark, not a replacement for it.

### `Monitor-LlamaProcess.ps1`

Generic process/resource monitor.

Matrix-driven runs will attach by PID to avoid accidentally aggregating another simultaneous `llama-cli` process.

Manual mode may fall back to a process name.

The unified monitor will retain the richer counter set from the previous CLI resource monitor, including system commit, paging, disk throughput, GPU process memory, adapter memory, and GPU engine utilization when Windows exposes those counters.

### `Invoke-BenchmarkMatrix.ps1`

Runs multiple conditions from declarative `.psd1` configuration files.

Planned capabilities:

- preflight validation
- `-PlanOnly`
- CLI-only or CLI+llama-bench runs
- cooldown between runs
- continue-after-failure behavior
- per-run logs
- summary update after every run
- detected metadata and expectation checks

The matrix file describes what should be measured. It should not duplicate the execution implementation.

## Manual versus automatic metadata

Expected policy:

| Field | Source |
|---|---|
| llama.cpp build | automatic |
| llama.cpp commit | automatic |
| Git commit/branch/dirty | automatic |
| executable SHA-256 | automatic |
| compiler | automatic |
| backend | automatic |
| GPU name/reported memory | automatic |
| driver version | automatic where Windows exposes it |
| context/batch/ubatch/KV | execution arguments |
| MTP on/off | execution configuration |
| model path/name/size | automatic |
| input hash | automatic |
| PP/TG/token counts | parsed automatically |
| MTP acceptance | parsed automatically |
| PLE16 semantic label | optional human alias |
| BIOS UMA setting | manual label |
| room temperature / notes | manual |

## Current migration order

1. common metadata module and local configuration
2. `llama-cli` wrapper plus generic resource monitor
3. `llama-bench` wrapper
4. benchmark matrix runner
5. Vulkan/ROCm build-script cleanup and build-manifest generation
6. model-conversion and QSA experiment script cleanup

The measurement framework should be validated against the clean b11247 r3 baseline before COMMON-001 or later inference patches are benchmarked.
