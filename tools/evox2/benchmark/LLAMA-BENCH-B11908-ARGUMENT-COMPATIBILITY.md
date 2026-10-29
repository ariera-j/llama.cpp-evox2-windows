# b11908 llama-bench argument compatibility (r6, 2026-10-29)

**Status: source / --help confirmed; Windows measurement rerun pending.** The measured Windows Vulkan b11908 executable is built from `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`. The public b11908 tag and binaries remain unchanged.

## Failure and root cause

The first attempt to verify the lightened Windows background-resource monitor used the existing `Measure-LlamaBench.ps1` wrapper with `-Context 4096`. Its generated command line included `-c 4096`, but b11908's `llama-bench.exe --help` does **not** offer `-c`:

```text
error: invalid parameter for argument: -c
```

The native Vulkan, CPU and RPC backends had loaded for argument parsing, but no benchmark PP or TG iterations ran. The six-second wall-time failure is **not** a speed sample, and it provides no meaningful evidence of the new background-monitor sampling cadence.

The pinned b11908 source at `tools/llama-bench/llama-bench.cpp` confirms that ordinary tests derive their context as **`n_ctx = n_prompt + n_gen + n_depth`**. Plain `-p` and `-n` are *separate test types* (unless using `-pg`); the example with `-p 512 -n 1024 -d 0` consequently has nominal requested context **512 for PP** and **1024 for TG**, not a forced 4096 for both. Native memory allocation may pad/align requested sizes.

`-fitc, --fit-ctx` is not a general replacement for `-c`: it sets the minimum context while **model-fit-to-device** logic is active and can alter offloading.

**Another b11908 difference:** native `llama-bench` does **not** accept the older fork's `-f / --prompt-slice` real-file input feature. For real-document tests use `Measure-LlamaCli.ps1` and record the actual input, or deliberately test a compatible historical fork. Do not assume random-token and real-document PP results are interchangeable.

## Wrapper compatibility change

`Measure-LlamaBench.ps1`:

- With default `-Context 0`, passes **no context override**, letting b11908 derive context from workloads; preview, output header, JSON and CSV now distinguish this `PerTestAuto` mode and include maximum workload context **hint**, not a guaranteed allocated context.
- With explicit `-Context 4096` or an `-InputFile / -InputKey`, inspects the selected executable's `--help` and **fails before starting measurement** if it lacks the relevant options. This retains intentional compatibility with older custom binaries that advertise the flags while preventing silent semantic changes in the r6 binary.
- Does not silently drop a requested context, add `-fitc`, truncate/extend prompts, or alter the test workload.
- Matrix plans containing `Context > 0` or `InputKey` in llama-bench cases must be reviewed for the selected executable; this new preflight exposes the incompatibility rather than hiding it.

## Correct monitoring smoke measurement

Use the existing local configuration keys (they are machine-local and are not committed):

```powershell
# From C:\llama-build\llama.cpp-evox2-windows-r6
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
    -BuildKey CombinedVulkan `
    -ModelKey UnslothPle16 `
    -PromptTokens @(512) `
    -GenerationTokens @(1024) `
    -Depths @(0) `
    -Repetitions 4 `
    -Threads 4 `
    -GpuLayers 999 `
    -CpuMoe 0 `
    -FlashAttn auto `
    -ResourceMonitor `
    -ResourceIntervalSeconds 2 `
    -BackgroundIntervalSeconds 15 `
    -NoAdlxMonitor
```

**Intentionally omit `-Context`**. If the inference finishes before two 15-second in-run probes, a longer TG or more repetitions can increase test duration. The wrapper still collects a beginning and ending named-process snapshot.

After measurement, use `Test-ResourceMonitorCadence.ps1 -CsvPath <path-to-resources.csv>` and inspect `BackgroundSampleTaken` plus `BackgroundCollectionMilliseconds`. A passing synthetic CSV validator alone does not establish GPU benchmark throughput stability; compare with and without `-ResourceMonitor` if quantifying overhead.

**Scope:** only the benchmarking wrapper, documentation and runtime check have changed. No r6 inference source or release binaries were rebuilt.
