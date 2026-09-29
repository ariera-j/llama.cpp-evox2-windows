# Evo-X2 Windows tooling

This directory contains downstream build, benchmark, model-conversion, and experiment utilities for the Evo-X2 Windows work.

The tools are designed around one rule:

> Prefer detected facts over manually typed labels.

A benchmark result should derive its backend, llama.cpp build identity, executable hash, context settings, and other machine-readable metadata from the actual executable and run configuration whenever possible.

The BIOS UMA setting remains a manual test-condition label because the current tooling does not have a reliable method to read the configured BIOS value directly.

## Current implementation status

Implemented:

```text
tools/evox2/
├─ README.md
├─ lib/
│  └─ Evox2.Common.psm1
└─ benchmark/
   ├─ Evox2.Benchmark.psm1
   ├─ Measure-LlamaCli.ps1
   ├─ Measure-LlamaBench.ps1
   ├─ Monitor-LlamaProcess.ps1
   └─ configs/
      ├─ local.example.psd1
      └─ local.psd1              # local only, ignored by Git
```

Planned next:

```text
benchmark/
├─ Invoke-BenchmarkMatrix.ps1
└─ configs/
   ├─ qwen38-baseline.psd1
   ├─ qwen38-longctx.psd1
   └─ qwen38-mtp.psd1
```

The final r3 layout will also include cleaned build, model-conversion, and experiment-specific scripts.

## PowerShell compatibility

The scripts target Windows PowerShell 5.1 on the primary Evo-X2 system.

The Phase 1 common module was validated on Windows PowerShell 5.1 with:

```text
llama.cpp build: 11247
commit: 0bc845d35
compiler: Clang 23.0.0
detected backend: ROCm
device: AMD Radeon(TM) 8060S Graphics
```

## Local logs

Generated benchmark output lives under:

```text
<repo>\evox2-logs\
```

For the primary r3 checkout:

```text
C:\llama-build\llama.cpp-evox2-windows-r3\evox2-logs\
```

The directory is ignored by Git.

A Phase 2 `llama-cli` run creates one directory such as:

```text
evox2-logs/
└─ 20260930-001500-123-cli-rocm-b11247-ctx65536-a1b2c3d4e5f6/
   ├─ conditions.json
   ├─ result.json
   ├─ summary.csv
   ├─ output.log
   ├─ stdout.log
   ├─ stderr.log
   └─ resources.csv              # only when -ResourceMonitor is used
```

The directory name contains only detected/basic run facts. Detailed conditions belong in `conditions.json`.

`output.log` is a combined post-run file with clearly separated stderr and stdout sections. `stdout.log` is kept separately so generated model text is easy to inspect.

## Machine-local configuration

Copy the example once:

```powershell
Copy-Item `
  .\tools\evox2\benchmark\configs\local.example.psd1 `
  .\tools\evox2\benchmark\configs\local.psd1
```

Edit `local.psd1` with machine-specific paths.

`local.psd1` is ignored by Git.

It may contain:

- Vulkan and ROCm binary directories
- model paths
- private input paths
- log root
- manual UMA label

Aliases such as `R3ROCm` and `UnslothOriginal` are lookup keys. They are not trusted as runtime facts.

If a build entry says:

```powershell
ExpectedBackend = 'ROCm'
```

but `llama-cli --list-devices` detects Vulkan, the measurement wrapper stops before inference.

## Common metadata module

Import manually when metadata-only inspection is useful:

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
```

Example:

```powershell
$cli = '.\build-rocm-b11247\bin\Release\llama-cli.exe'

Get-Evox2LlamaIdentity `
  -Executable $cli `
  -RepoRoot $PWD |
  ConvertTo-Json -Depth 10
```

The common module records executable, backend/device, Git, host-system, optional build-manifest, and file identity metadata.

## Phase 2: `Measure-LlamaCli.ps1`

This is the primary practical benchmark wrapper.

It:

- resolves local build/model/input lookup keys
- detects backend from `--list-devices`
- records `--version` build/commit/compiler information
- hashes the executable
- hashes the private input file
- records model path/size/mtime without hashing a 70+ GB GGUF by default
- records the manual UMA label separately
- writes a stable condition ID
- captures stdout and stderr separately
- parses PP, TG, token counts, actual context, MTP acceptance, and selected memory information
- optionally launches resource monitoring against the exact `llama-cli` PID
- writes JSON plus a compact CSV summary

### Recommended first Phase 2 test

With `local.psd1` configured:

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -InputKey 64k `
  -Context 65536 `
  -KvType f16 `
  -UBatch 1024 `
  -ResourceMonitor
```

Most other arguments default to the current r3 long-context baseline:

```text
ngl: 999
ncmoe: 0
threads: 4
batch: 2048
ubatch: 1024
flash attention: 1
verbosity: 4
K/V: f16/f16
fit: off
cache-ram: 0
temperature: 0.2
top-p: 0.8
jinja: on
single-turn: on
reasoning: off
MTP: off
generation limit: 1024
```

The actual backend/build are detected. `R3ROCm` is only a lookup key plus an optional expectation.

### Dry run

Use:

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -InputKey 64k `
  -Context 65536 `
  -DryRun
```

This performs preflight and metadata detection, displays the effective command and condition ID, and does not start inference.

### Direct paths

The local config is optional when direct paths are supplied:

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -LlamaCli 'C:\path\to\llama-cli.exe' `
  -ModelFile 'C:\path\to\model.gguf' `
  -InputFile 'C:\path\to\prompt.txt' `
  -Context 65536
```

### Allocation-only smoke check

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -Context 65536 `
  -AllocationOnly `
  -ResourceMonitor
```

This uses a short prompt and 32 generated tokens. It checks allocation/model loading; it is not a long-context PP benchmark.

### MTP

After COMMON-002 is ready:

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R3Vulkan `
  -ModelKey UnslothPle16 `
  -InputKey 64k `
  -Context 65536 `
  -Mtp `
  -DraftModelKey UnslothMtp `
  -DraftMax 2 `
  -ResourceMonitor
```

MTP on/off is derived from the actual wrapper configuration. It is not inferred from a filename.

### Extra llama.cpp arguments

For temporary experiments:

```powershell
-ExtraArgs @('--ctx-checkpoints', '0t')
```

Anything supplied through `-ExtraArgs` is written to `conditions.json` and included in the condition ID.

## Resource monitoring

`Monitor-LlamaProcess.ps1` is normally started automatically by `Measure-LlamaCli.ps1` when `-ResourceMonitor` is specified.

The wrapper starts `llama-cli`, obtains its exact PID, and launches the monitor against that PID.

This avoids the previous behavior of summing every process named `llama-cli`.

The unified monitor records the richer previous CLI counter set:

- target working/private/virtual memory
- GPU process local/dedicated/shared/committed/non-local memory when exposed by Windows
- GPU engine utilization sum
- adapter local/dedicated/shared/committed memory
- physical RAM
- committed memory and commit limit
- paging counters
- disk throughput
- total CPU usage

If process-specific GPU counters are unavailable while the target process is still running, it falls back to adapter/system counters and records that process counters were unavailable.

A PID-scoped GPU counter can also disappear during the normal shutdown race after `llama-cli` exits. That end-of-run condition is not treated as a warning and no misleading fallback sample is appended.

For GPU engine utilization, each individual Windows GPU Engine counter is validated before summing. Individual values outside `0..100.5%` are rejected as invalid counter data. The final `TargetGPUEngineSum_Percent` is still allowed to exceed 100% because multiple GPU engines can be active simultaneously.

The resource CSV includes:

```text
GpuEngineCounterInstances
GpuEngineRejectedValues
```

so any filtering remains visible in the measurement record.

### Manual monitor invocation

```powershell
.\tools\evox2\benchmark\Monitor-LlamaProcess.ps1 `
  -TargetProcessId 12345 `
  -LogPath .\evox2-logs\manual-resources.csv `
  -IntervalSeconds 2
```

The monitor exits automatically when the target PID exits.

### Windows PowerShell 5.1 exit-code handling

The wrapper keeps the native `llama-cli` process handle. It first reads
`System.Diagnostics.Process.ExitCode` after `WaitForExit()` and uses the
Windows `GetExitCodeProcess` API as a fallback if Windows PowerShell 5.1
returns a blank managed exit code.

`result.json` and `summary.csv` record `ExitCodeSource` so the retrieval path
is visible.

## Output behavior

Phase 2 deliberately uses `Start-Process` with separate stdout/stderr redirection so the exact `llama-cli` PID is known before resource monitoring starts.

On Windows PowerShell 5.1, this means native llama.cpp output is not streamed line-by-line through the parent PowerShell pipeline.

Instead:

- a progress heartbeat is printed every 15 seconds by default
- `stderr.log` and `stdout.log` are written during execution
- generated stdout is printed after the run
- `output.log` combines both streams afterward

This trades live diagnostic scrolling for reliable PID-based monitoring and unambiguous raw stream files.

## Result status

The wrapper reports:

```text
OK
FAILED
FAILED_EXCEPTION
CHECK_CONTEXT
CHECK_TIMING
```

For a normal long-input run, `OK` requires:

- native exit code 0
- detected actual context equals the requested context
- prompt timing was parsed successfully

A warning is emitted if the prompt uses less than 80% of the requested context.

## Model hashing

The executable and input file are SHA-256 hashed automatically.

Large GGUF files are not SHA-256 hashed by default because repeatedly reading a 70+ GB model would add substantial I/O before each benchmark.

Use:

```powershell
-HashModel
```

when a full model SHA-256 is required.

Otherwise the model identity records path, size, and last-write time.

## Build manifests

`evox2-build.json` support already exists in the common module, but the current clean b11247 build directories do not have manifests yet.

The build-script cleanup phase will generate them automatically.

Official/prebuilt llama.cpp builds can still be benchmarked without a manifest because runtime identity is detected from the executable.


## Phase 3: `Measure-LlamaBench.ps1`

`Measure-LlamaBench.ps1` is the synthetic/public reproducibility companion to the real-input `Measure-LlamaCli.ps1`.

It uses the same foundations:

- local build/model lookup keys
- runtime backend detection via `--list-devices`
- build/commit/compiler detection via `--version`
- executable SHA-256
- optional model SHA-256
- Git/system metadata
- condition IDs
- exact-PID resource monitoring
- repository-local `evox2-logs` output

The wrapper forces native llama-bench JSON output and preserves it as:

```text
llama-bench.json
```

It also writes:

```text
conditions.json
result.json
summary.csv
output.log
stderr.log
resources.csv              # with -ResourceMonitor
```

### Important llama-bench semantics

For the exact b11247 baseline, llama-bench supports:

```text
-p / --n-prompt
-n / --n-gen
-d / --n-depth
-r / --repetitions
-o json
```

`-p` and `-n` are separate benchmark types. For example:

```powershell
-PromptTokens 512,4096,65536 `
-GenerationTokens 128
```

produces prompt-processing tests for 512, 4096, and 65536 tokens plus a separate 128-token generation test. It does **not** mean "generate 128 tokens after each of those prompt sizes."

To benchmark generation after a prefilled long context, use depth:

```powershell
-PromptTokens 0 `
-GenerationTokens 128 `
-Depths 65536
```

`-d` pre-fills the KV cache before the measured test.

llama-bench does not include tokenization or sampling time in its measurements. This is one reason the llama-cli real-input benchmark remains the primary practical measurement.

The Phase 3 wrapper intentionally does not add MTP/speculative decoding. The b11247 llama-bench interface does not expose the draft-MTP controls used by the llama-cli/server path. Use `Measure-LlamaCli.ps1` for MTP measurements.

### Dry run

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -PromptTokens 512 `
  -GenerationTokens 128 `
  -Repetitions 3 `
  -DryRun
```

### Short reproducibility smoke benchmark

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -PromptTokens 512 `
  -GenerationTokens 128 `
  -Repetitions 3 `
  -ResourceMonitor
```

### Prompt-processing sweep

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -PromptTokens 512,4096,16384,32768,65536 `
  -GenerationTokens 0 `
  -Repetitions 3
```

### Short-context generation only

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -PromptTokens 0 `
  -GenerationTokens 128 `
  -Depths 0 `
  -Repetitions 3
```

### Generation after a 64k prefilled context

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R3ROCm `
  -ModelKey UnslothOriginal `
  -PromptTokens 0 `
  -GenerationTokens 128 `
  -Depths 65536 `
  -Repetitions 3
```

This last test answers a different question from the short-context `tg 128` result, so keep the depth visible when comparing TG numbers.

### Native JSON and summary

The native JSON contains llama-bench's own averages, standard deviations, and per-repetition samples.

`summary.csv` flattens the most useful fields, including:

```text
Test
PromptTokens
GenerationTokens
Depth
AvgTokensPerSec
StdDevTokensPerSec
RepetitionSamples
BenchBackends
BuildNumber
BenchBuildCommit
```

The full native rows are also embedded in `result.json`.


## Phase 4: benchmark matrix runner

`Invoke-BenchmarkMatrix.ps1` orchestrates the already-validated
`Measure-LlamaCli.ps1` and `Measure-LlamaBench.ps1` wrappers.

The matrix layer does not parse llama.cpp output itself. Each child wrapper
remains responsible for:

- executable/backend/build detection
- exact benchmark command construction
- condition IDs
- native output parsing
- resource monitoring
- per-run result files

The matrix runner adds:

- declarative `.psd1` plans
- CLI-only, llama-bench-only, or combined execution
- multiple build keys/backends
- context/input pairs
- CLI MTP variants
- cooldown between runs
- continue-on-error or stop-on-error behavior
- filtering before execution
- a hard `MaxRuns` guard
- batch-level plan, status, and result summaries

### Phase 4 files

```text
benchmark/
├─ Invoke-BenchmarkMatrix.ps1
└─ configs/
   ├─ qwen38-baseline.psd1
   ├─ qwen38-longctx.psd1
   └─ qwen38-mtp.psd1
```

`local.psd1` remains machine-local and ignored by Git. Matrix plans refer to
lookup keys from `local.psd1`; they do not contain machine-specific model or
build paths.

### Plan schema

A plan contains:

```text
SchemaVersion
Name
Settings
Defaults
Jobs
```

Each job chooses:

```text
Tool       = cli | bench
BuildKeys
ModelKeys
Cases
Variants
Parameters
```

Parameter precedence is:

```text
Defaults for the selected tool
    < Job.Parameters
    < Case.Parameters
    < Variant.Parameters
    < command-line matrix overrides
```

`BuildKey`, `ModelKey`, `LocalConfig`, executable/model direct paths,
`DryRun`, and `NoThrowOnFailure` are reserved by the matrix runner.

For CLI long-context plans, keep `Context` and `InputKey` together in a
single Case. This avoids generating meaningless Cartesian combinations such
as a 128k context paired with the 32k input file.

### Expansion order

The runner expands jobs in this order:

```text
Case
  -> BuildKey
     -> ModelKey
        -> Variant
```

This deliberately keeps no-MTP/MTP variants adjacent for the same context.

### Plan-only validation

Always inspect a new or edited plan before a long run:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-baseline.psd1 `
  -PlanOnly
```

`-PlanOnly`:

- loads `local.psd1`
- verifies referenced build/model/input keys
- verifies tool-specific parameter names
- validates MTP draft-model requirements
- expands the selected matrix
- rejects duplicate expanded conditions
- applies the `MaxRuns` safety limit
- starts no benchmark process

### CLI only, bench only, or both

A plan may contain both tool types.

Run everything selected by the plan:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-baseline.psd1
```

Run only real-input llama-cli jobs:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-baseline.psd1 `
  -Tool cli
```

Run only llama-bench jobs:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-baseline.psd1 `
  -Tool bench
```

### Filters

Filters accept PowerShell wildcard patterns:

```powershell
-OnlyJob cli-*
-OnlyCase 64k
-OnlyVariant mtp
-OnlyBuild R3ROCm
```

For example, run only the 64k MTP case from the MTP plan:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-mtp.psd1 `
  -OnlyCase 64k `
  -OnlyVariant mtp
```

### Resource-monitor override

Normally each plan decides whether resource monitoring is enabled.

Force it on for all selected child runs:

```powershell
-ResourceMonitor
```

Force it off:

```powershell
-NoResourceMonitor
```

Do not specify both.

### Failure and cooldown policy

The example plans default to:

```text
CooldownSeconds = 10
ContinueOnError = true
```

Override the cooldown from the command line:

```powershell
-CooldownSeconds 30
```

Stop after the first non-OK child result:

```powershell
-StopOnError
```

The matrix runner always invokes child wrappers with `NoThrowOnFailure` so
their structured result can be recorded first. Exceptions such as invalid
paths or parameter-binding failures are still caught and stored as matrix
run failures.

### MaxRuns safety guard

The default is:

```text
MaxRuns = 100
```

If an edited plan accidentally expands beyond that limit, execution is
refused.

A deliberate larger run must explicitly opt in:

```powershell
-MaxRuns 200
```

### Matrix batch output

Each actual matrix execution creates:

```text
evox2-logs/
└─ matrix/
   └─ <timestamp>-<plan-name>/
      ├─ matrix-plan.json
      ├─ matrix-runs.csv
      ├─ matrix-results.csv
      └─ matrix-result.json
```

`matrix-plan.json` stores the fully expanded run plan plus the SHA-256 of the
plan and local config.

`matrix-runs.csv` contains one row per child invocation and is rewritten
after every completed run, so partial overnight results survive a later
failure or reboot.

`matrix-results.csv` contains normalized performance rows:

- one row per llama-cli run
- one row per native llama-bench result, so `pp 512` and `tg 128` remain
  separate

All detailed logs remain in the normal child run directories.

### Included plans

`qwen38-baseline.psd1` contains:

- real-input 64k, MTP off
- R3Vulkan + R3ROCm
- short `pp 512` / `tg 128` llama-bench anchor on both builds

`qwen38-longctx.psd1` contains:

- 32k / 64k / 96k / 128k / 256k real-input CLI measurements
- R3ROCm by default
- an optional disabled synthetic long-context PP sweep

`qwen38-mtp.psd1` contains:

- Unsloth PLE16 base
- R3ROCm by default
- 32k / 64k / 96k / 128k
- adjacent no-MTP / MTP variants using `UnslothMtp`

These are version-controlled experiment definitions, not private machine
configuration.

## Phase 5: build provenance, external PLE conversion, and experiment environments

Phase 5 adds three pieces that deliberately stay separate.

### Build wrappers and `evox2-build.json`

```text
build/
├─ README.md
├─ Evox2.Build.psm1
├─ Build-Vulkan.ps1
└─ Build-ROCm.ps1
```

The build wrappers preserve the documented Windows Vulkan / ROCm build
settings and write:

```text
<build>\bin\Release\evox2-build.json
```

The benchmark metadata layer already reads this file automatically.

For the existing b11247 builds, manifests can be backfilled without compiling:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-b11247 `
  -ManifestOnly

.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-b11247 `
  -ManifestOnly
```

See `build/README.md` for full-build examples.

### PLE layout conversion with explicit external attribution

```text
model/
├─ README.md
├─ Convert-Unsloth-Ple16.ps1
└─ verify-ple-layout.py
```

The PLE conversion algorithm is not owned by this repository.

The actual converter remains the external script:

```text
https://github.com/LaurentZuijdwijk/llama.cpp
gguf-py/gguf/scripts/gguf_split_ple_heads.py
```

It is not vendored here.

`Convert-Unsloth-Ple16.ps1` only invokes that external script and records
provenance: external checkout commit/dirty state, converter SHA-256,
input/output identities, logs, and a sidecar JSON.

This distinction is intentional. Existing PLE16 model files that were
converted before Phase 5 should continue to be described as having been
converted with the LaurentZuijdwijk script, not with this later wrapper.

### Environment-controlled experiments

The Phase 4 matrix runner now accepts `Environment` hashtables at:

```text
Defaults
Job
Case
Variant
```

The environment is applied only around the selected child benchmark and is
restored afterward.

This supports QSA threshold A/B tests without creating a new launcher for
every environment variable.

Examples live in:

```text
experiments/qsa/
├─ README.md
├─ qsa-union-thresholds.example.psd1
└─ mtp-qsa-threshold.example.psd1
```

These are templates for QSA-capable builds. An environment variable is not
evidence that a baseline binary implements or honors it.

## Suggested next phase

After Phase 5, the repository is ready to start the actual r3 patch-stack
integration:

```text
COMMON-001 PLE16 loader
COMMON-002 Unsloth MTP compatibility
COMMON-003 ROCmFPx core/format evaluation
VULKAN-001 ROCmFPx kernels evaluation
VULKAN-002 QSA grouped-union re-evaluation
```

The new build manifests and matrix conditions make those patch comparisons
much easier to audit.

