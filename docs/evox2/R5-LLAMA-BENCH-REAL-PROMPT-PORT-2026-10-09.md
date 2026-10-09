# r5 real-prompt llama-bench: phase A implementation / Windows smoke handoff

Date: 2026-10-09. Target: `r5/upstream-refresh-20261009`; original donor commit [`4bf9af6fefa98622a65bd8d4c04ba73a02e27422`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/4bf9af6fefa98622a65bd8d4c04ba73a02e27422). Integrated with the current r5 branch, **not an r4 file replacement or branch merge**.

## What was ported

- `tools/llama-bench/llama-bench.cpp`: native `-f/--prompt-file` to read a text file, raw tokenize per loaded model outside measurement, optional `--prompt-slice head-tail|head` (default head-tail), optional `-c/--ctx-size` (0/omitted preserves auto allocation). Exactly N tokens with `-p N`; without `-p`, full file. Reject empty/insufficient files; do not repeat/pad. Original default random path remains active if `-f` is absent. Preserve warmup/repetition and original `test_prompt` behavior in random mode.
- `tools/evox2/benchmark/Measure-LlamaBench.ps1`: `-InputKey` (existing `local.psd1` Inputs), `-InputFile`, `-PromptSlice`, `-Context`, accurate file size/hash and mode/context/slice in `conditions.json`, results/summary and run metadata. No input key means the original random mode. Only `local.psd1` has local paths; never commit it.
- Apply **19 native C++ hunks + 15 PowerShell wrapper hunks with exact matching context** to existing r5 files. These are the *only implementation files changed*. They do not edit model loading, QSA, GGML, Vulkan, ROCm, shaders, MTP, or backend tests.
- **Not ported yet**: VULKAN-002 grouped-union backend, any QSA union statistical reporting or statistics-file wrapper support. Source donors remain frozen.

## Verification status

**Code-integrity/structural check only, Windows build and runtime smoke not yet performed.** Automated patch application required a unique exact original-context match for every one of the 34 source hunks. Checks confirmed new option/file handling, raw tokenization, token slice, original random fallback, explicit context path, input hash metadata and absence of union diagnostics in the two changed files. This does *not* establish C++/PowerShell compile success or actual runtime speed. Need the user's Evo-X2 test before beginning Phase B.

## Windows Vulkan build

Run from the r5 worktree **after `git pull --ff-only`**. Do not rebuild in/overwrite the accepted COMMON-001 directory. Reuse the prepared dependency cache:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-bench-real-prompt `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4

$bin = '.\build-vulkan-bench-real-prompt\bin\Release'
& "$bin\llama-bench.exe" --help
& "$bin\llama-bench.exe" --version
```

`--help` must show `-f/--prompt-file`, `--prompt-slice`, and `-c/--ctx-size`. If `--version` is not supported by the current bench executable, obtain build identity from the build manifest and executable SHA instead; an unsupported bench version switch alone is not a build failure.

## Quick smoke (not a long performance benchmark)

Update **ignored** `tools/evox2/benchmark/configs/local.psd1` with a new `Builds.R5BenchVulkan` that points to `build-vulkan-bench-real-prompt\bin\Release` and `ExpectedBackend='Vulkan'`. Existing `Models.UnslothPle16` and `Inputs.'64k'` should still resolve. If there are no input keys, provide the same real input with `-InputFile` instead.

Run the wrapper in the same prepared shell:

```powershell
$common = @{
    BuildKey         = 'R5BenchVulkan'
    ModelKey         = 'UnslothPle16'
    Context          = 1024
    PromptTokens     = @(256)
    GenerationTokens = @(0)
    Depths           = @(0)
    Repetitions      = 1
    Batch            = 256
    UBatch           = 256
    Threads          = 4
    KvType           = 'f16'
    GpuLayers        = 999
    CpuMoe           = 0
    FlashAttn        = 'auto'
    NoWarmup         = $true
}

# Case 1: original random token workload (no -InputKey).
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common

# Case 2: real file, first and last token slices.
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head-tail

# Case 3: real file, leading tokens only.
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head
```

If `ModelKey='UnslothPle16'` or `BuildKey='R5BenchVulkan'` differ in the user's `local.psd1`, adjust the keys only; use the new build directory and the existing model. The smoke source must have at least 256 raw tokens; the `64k` source should suffice. Verify success and non-empty valid `llama-bench.json`, `summary.csv`, `conditions.json`, `result.json`; real-file cases must report the input SHA256, path, `PromptSlice` and requested context. Random case must report random tokens, without input-file arguments. A missing/too-short text source should fail explicitly, not be padded.

A direct native check can also use `-f <file> --prompt-slice head-tail -c 1024 -p 256 -n 0 -d 0 -r 1 -b 256 -ub 256 -ctk f16 -ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto` with the model supplied via `-m`. Do not confuse the raw-token source with the chat-template-expanded llama-cli 64k prompt.

## After user validation

- Record build ID, commit identity, binary hash, three child outcomes and source SHA in this report or a separate validation note; if any case fails, repair Phase A only.
- **Do not start Phase B (VULKAN-002) until the Windows build and small smoke pass.** Next native change will be separately committed. Phase C optional stats follows after Phase B correctness/PP gate.
- English or non-repeating Japanese full-text inputs are [optional later comparison cases](R5-VULKAN002-BENCH-AND-STATS-PORT-PLAN-2026-10-09.md), not smoke blockers.
