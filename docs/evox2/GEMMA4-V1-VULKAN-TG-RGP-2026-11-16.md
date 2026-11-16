# Gemma 4 31B QAT: Vulkan TG RGP marker gate (2026-11-16)

## Goal and boundaries

Identify GPU shaders and operator groups contributing to Gemma 4 31B QAT Q4_0 single-token generation (TG), where the clean v1.0.0-dev b12363 Vulkan baseline gives about 11.41 tok/s on short Japanese text and 8.92 tok/s after a 29,379-token input.

The diagnostic starts from source commit `934a6574780035863ffa1903d3449f3505ac1f93` (upstream inference core unchanged) on branch `investigation/gemma4-31b-v1-rocm-20261116`. The source change is limited to `ggml/src/ggml-vulkan/ggml-vulkan.cpp`. Do not merge into an optimized release until validated.

### What the patch does

- `EVOX2_VK_TG_RGP_MARKERS=1` enables Vulkan `VK_EXT_debug_utils` and existing upstream graph-node/pipeline command-buffer debug labels even if `GGML_VK_DEBUG_MARKERS` is not separately set.
- During `ggml_backend_vk_graph_compute`, inspect `GGML_OP_FLASH_ATTN_EXT` nodes. If at least one exists and every found FA query has `src[0]->ne[1] == 1` (query tokens after the `ggml_permute(... 0,2,1,3)` used by `build_attn_mha`), label the enclosing **queue scope** with `EVOX2_VK_TG_<ordinal>_Q1_FA<n>_N<nodes>`. This spans all submissions for that backend graph evaluation.
- Existing command-buffer labels still give the operator name and tensor name, and nested pipeline labels give shader name and workgroup counts. In RGP Events, inspect the queues/dispatches inside a `EVOX2_VK_TG_` region, including Q4_0 matvec/mul_mat and flash-attn pipelines.
- The first four TG region names are also logged once to stderr for validation. This is a source-level marker, not a GPU execution timestamp or an RDP dispatch ordinal.
- Normal runs with the environment variable unset/0 follow the old graph label path, no per-graph FA-node scan, and no changed math/sampling/kernel selection. **No runtime speedup is expected.** The diagnostic can add overhead and is **not** a valid throughput benchmark.
- The marker is deliberately not model-name-based; it selects FA graphs with a single query token. It may not label graphs with no FA nodes, or mixed-query graphs. It does not prove that an entire CPU decode step has completed. The TG ordinal is process-local (not necessarily the final user-visible token count) and resets on program startup.

### Build the diagnostic executable in a separate directory

Use the EVO-X2 Windows PowerShell 5.1 shell:

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-v1-gemma4'
Set-Location $root

git status --short
git pull --ff-only
git log -1 --oneline

.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir (Join-Path $root 'build-vulkan-gemma4-rgp') -Parallel 4

& (Join-Path $root 'build-vulkan-gemma4-rgp\bin\Release\llama-cli.exe') --version
```

Do **not** overwrite `build-vulkan-gemma4` (the untouched v1 b12363 Vulkan baseline), and do **not** use the ROCm executable to capture Vulkan RGP events. The clean source build before this patch is `934a657`; the diagnostic build will have a newer SHA/build identity. Check the produced `evox2-build.json` and share it with the capture results.

### Prepare ignored local.psd1

The reusable plan is `tools/evox2/benchmark/configs/gemma4-v1-vulkan-tg-rgp-20261116.psd1`.

Add these entries to the **new worktree's** ignored `tools/evox2/benchmark/configs/local.psd1`, keeping other valid entries if present:

```powershell
@{
    UmaLabel = '64GB'
    Builds = @{
        Gemma4V1RgpVulkan = @{
            BinDir = 'C:\llama-build\llama.cpp-evox2-v1-gemma4\build-vulkan-gemma4-rgp\bin\Release'
            ExpectedBackend = 'Vulkan'
        }
    }
    Models = @{
        Gemma4_31B = @{
            Path = 'C:\path\to\Gemma4-31B-it-QAT-Q4_0.gguf'
            Alias = 'gemma4-31b-qat-q4_0'
        }
    }
    Inputs = @{
        Gemma4Short = 'C:\path\to\short-ja-writing-v1.txt'
    }
}
```

Replace the two placeholders with the actual model and input paths from the earlier r6/v1 benchmark. The fixed short Japanese prompt SHA256 is `ad29fe3ec728057ce0736594ed79886ed278cb0b0f6ed35e9eaca26cb27b0bb6` and the baseline had 217 prompt tokens. No proprietary input text or credentials should be committed.

The `Measure-LlamaCli.ps1` wrapper also attempts to launch the ADLX monitor from the **new** worktree's `tools/evox2/adlx-gpu-monitor/build/bin/evox2-adlx-gpu-monitor.exe`. If it is not built, use the previously validated r6 ADLX monitor binary (copy into that path) or build it locally. The RGP label feature itself does not depend on ADLX.

### Preflight and one diagnostic run

```powershell
$root = 'C:\llama-build\llama.cpp-evox2-v1-gemma4'
Set-Location $root
$plan = '.\tools\evox2\benchmark\configs\gemma4-v1-vulkan-tg-rgp-20261116.psd1'

# Confirm SHA of fixed prompt and current source/build metadata separately.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# Do a run without RDP/RGP first, to validate that labels are being created.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -StopOnError
```

Inspect `stderr.log` for `ggml_vulkan: EVOX2 TG RGP markers enabled` and at least one `ggml_vulkan: EVOX2_VK_TG_1_Q1_FA...` line. Confirm correct model, 61/61 GPU layers, Vulkan0 backend, FA enabled and `Status=OK`. The plan deliberately uses `--ignore-eos -n 512` to provide a reasonable RGP capture window; this differs from the `-n 1024` non-profiled speed baseline. RGP run PP/TG values must not overwrite the clean baseline.

### Capture with Radeon Developer Panel (RDP)

1. Start Radeon Developer Panel, select the **diagnostic** `llama-cli.exe` under `build-vulkan-gemma4-rgp\bin\Release` as the Vulkan application and ensure the capture target is a newly launched process. Set the SQTT trace memory high enough for an initial short capture; leave experimental shader instrumentation off.
2. The initial prompt has 217 tokens; generation lasts tens of seconds with `-n 512`. Trigger a small dispatch-range capture **after printed Japanese output begins**, if using an interactive/manual capture mode. In an automatic absolute dispatch-index mode, remember that an early range from index 1 can sample PP rather than TG; calibrate the start instead of guessing a large ordinal.
3. Open RGP, go to **Events / Event timing** and search `EVOX2_VK_TG_`, `MUL_MAT`, `flash_attn`, `matmul`, or `mmvq`; expand GPU dispatches under the TG region. Record the most expensive shader names, number of dispatches/workgroups and GPU execution times. Use RGP's raw event timing; queue labels alone are not timing measurements.
4. If `EVOX2_VK_TG_` is not visible, capture `submit` / `FLASH_ATTN_EXT` / `matmul` nodes and check whether the trace starts during PP. Confirm the stderr label printed before interpreting the capture. A valid RGP file without any TG-region event is **not** evidence that no TG GPU work occurred.
5. Keep a separate GPU capture from non-captured measurement runs. The RGP overhead and RDP frame/capture window can change timing, and per-dispatch RGP timings are not equivalent to total `llama-cli` TG ms.

Please return: diagnostic build JSON, the benchmark ZIP, RGP screenshots (or `.rgp` if manageable), RDP start/count and any capture warnings. No backend/GPU kernel optimization is included in this patch.

### Known limitations and later steps

- The host CPU sampling, command recording and idle gaps are **not** measured by RGP GPU event timing. If GPU event sums fall well short of ~88 ms/token, add a separate host trace after kernel-level classification.
- As this label is added around an entire backend graph, each region may contain many shader dispatches and multiple queue submissions; it does not produce precomputed per-operator percentages.
- First investigate short-context TG, then confirm whether the candidate also dominates under ROCm. Once TG is understood, separately profile 32k PP where Vulkan is about 3x slower than ROCm.
- The patch has been source-reviewed against existing upstream Vulkan debug label facilities; **Windows build, a successful RGP capture and speed regression have not yet been executed here.**
