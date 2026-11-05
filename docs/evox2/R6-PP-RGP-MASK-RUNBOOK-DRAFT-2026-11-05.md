# r6 PP RGP/mask GPU runbook — DRAFT (2026-11-05)

> **NOT YET EXECUTABLE.** The branch currently has no r6 FA markers or mask snapshot implementation. Do not set any proposed diagnostic env var and assume it works until the feature is built, its help/init log checked, and the required smoke gates pass.

## 1. Local checkout without disturbing r6 baseline

New branch on GitHub: `investigation/r6-pp-fa-mask-rgp-20261105`, forked from `feature/r6-llama-bench-real-prompt-20261103` commit `6a092fd2e60789d6ff7001cbe8e342fccff323ac`.

Recommended **separate worktree** and new build directories, rather than changing the r6 worktree currently used for real-input b12032/12038 tests.

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git worktree add -b investigation/r6-pp-fa-mask-rgp-20261105 `
    C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag `
    origin/investigation/r6-pp-fa-mask-rgp-20261105

cd C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag
git branch --show-current
git rev-parse HEAD
```

If the branch is already created locally, omit `-b` and the remote base and use `git worktree add <path> investigation/r6-pp-fa-mask-rgp-20261105`. Never force checkout or delete existing worktrees.

**After implementation** build unique paths e.g. `build-vulkan-ppdiag`, `build-rocm-ppdiag` with the **same Clang/SDK/TheRock** configurations as their respective already working b12032/b12038 r6 builds. Their CMake cache, compiler, DLL staging and build identity must be reviewed before writing a copy/paste build command. **Do not reuse/overwrite** `build-vulkan-bench-real-r6`, `build-rocm-bench-real-r6` or tested release ZIPs.

## 2. Capture manifest and environment gate

For *every* future diagnostic process save:
- `git rev-parse HEAD`, `git status --short`, source branch, compiled llama.cpp version/commit, EXE SHA-256, ROCm/Vulkan DLL runtime digest;
- model path/length/SHA (or justified verified identity), input path and SHA (source hashes below), token length and head slice, actual `n_prompt`, `ctx`, `ub`;
- `UmaLabel=96GB` **only after confirming the 96GiB allocation from OS/GPU observations**, ADLX+Windows memory samples, P-MODE Performance, GPU core/VRAM clock/power/temp, Windows page/commit pressure and display/RDP state;
- **explicit** QSA/FA diagnostic flags, `-NoWarmup` versus warmup-ON, actual RDP capture config, timestamp/capture ID and any user-event labels;
- `Status=OK`, native exit code, monitor sample coverage; beware that one memory minimum during model load does not prove persistent thrashing.

Source SHA256:
- Literature `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`;
- llama.cpp C/C++ `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`.

Freeze `-p61777 -c65536 -b2048 -ub1024 -n0 -d0 -r1`, `--prompt-slice head`, `-t4 -ngl999 -ncmoe0 -fa auto -ctk f16 -ctv f16`. Start with IQ3 PLE16 only; MTP OFF. For **diagnostic** captures, prefer `-NoWarmup` and log the resulting phase difference from prior benchmark baselines.

Environmental hygiene before each benchmark (only within the intended PowerShell process):
```powershell
# Keep unrelated instrumentation out of the run; run one diagnostic mode at a time.
@('GGML_VK_PERF_LOGGER','GGML_VK_PERF_LOGGER_CONCURRENT',
  'GGML_VK_QSA_UNION_STATS','GGML_VK_DEBUG_MARKERS',
  'GGML_VK_FA_SPARSE_DISABLE',
  'GGML_VK_MTP_PP_RGP_MARKERS','GGML_VK_MTP_PP_RGP_DISPATCH_TRACE',
  'LLAMA_MTP_DIAG') | ForEach-Object {
    Remove-Item ("Env:" + $_) -ErrorAction SilentlyContinue
}
# No MTP / no experimental gather. Exact effective environment will be logged.
$env:GGML_VK_QSA_UNION = '0'
$env:QWEN4EXP_QSA_GATHER = '0'
```
For the actual benchmark, use the existing `Measure-LlamaBench.ps1` with `-LlamaBench <new diagnostic exe>`, `-ExpectedBackend Vulkan|ROCm`, `-InputFile <file>`, `-PromptSlice head`, `-ModelKey UnslothPle16` (verify current local config), `-ResourceMonitor` and ADLX. Do not reuse a production build key for a diagnostic binary.

## 3. Proposed future run sequence (must satisfy gates)

| Order | Binary / mode | Work | Pass requirement |
|---|---|---|---|
| 0 | original r6 b12032/12038, diagnostic OFF | Optional short sanity after UMA change, check model/OS and 64k allocation budget | Device and RAM observed, no TDR/OOM |
| 1 | new Vulkan marker-only | ctx2048/p1024 literary smoke; verify marker flag initialization and an RGP capture of named FA | `Status=OK`, correct shader and `KV=...` label **visible in RGP GUI** |
| 2 | new Vulkan mask-snapshot-only | ctx2048/p1024, first locate actual Qcur (historically Qcur-7 at KV1024); one limited tile-map | file exists, **1 shot**, 2-bit decode valid, expected causal diagonal mask near initial prompt |
| 3 | new Vulkan mask-snapshot-only | ctx65536/p61777 literature then code; request actual same layer at KV49152 | both valid 2D tile maps, identity confirmed, no data overwrite |
| 4 | new Vulkan marker-only / RGP | literature then code; small **256-dispatch** window, **SQTT High**, counters and instruction tracing OFF. Calibrate start ordinal first (r5 180000 **not reused**). | matching physical N, KV, layer, pipeline; FA mask/main timings from 2 separate traces |
| 5 | new ROCm HIP / RGP | separately profile literature then code. Start with short PP to verify HIP RGP process and stage, then ctx65536. | same HIP FA specialization / KV / layer identified, or explicitly classified exploratory; no forced sync |
| 6 | separate OFF control / analysis | compare diagnostic-vs-off output sanity and counter behavior on same new build; join to existing normal PP baselines qualitatively | no silent behavioral changes; measured mask and RGP observations archived |

Do **not** enable mask snapshot while timing RGP FA MAIN. Their outputs join by **known same model/conditions/layer/KV**, not by single timed dispatch.

## 4. Tools and exact capture criteria

Vulkan:
- RDP/RGP process must be the `llama-bench.exe` associated with the diagnostic Vulkan DLL (check EXE SHA).
- `Dispatch range` mode, **count 256 initially**; SQTT High, instruction trace/counters OFF. The first range is a **calibration**, not an attempt to hit KV49152 by a hardcoded time/index.
- RGP → Event timing → group/filter by **user event** and search `EVOX2_FA_`. Read **actual displayed** `KV=`, `N=`, `q=`, `shader=`, plus workgroup and kernel durations for both `MASK_OPT` and `MAIN`. If FA not in 256 dispatches, do not compare a MoE shader to FA just because it is the top pipeline.
- Need two successful same-anchor captures per input **if** the first pair shows a material gap; otherwise a single exploratory pair suffices to decide next probe. Changing the RDP capture ordinal/index is allowed **only to align the actual observed GPU node**.

Vulkan mask map:
- Read packed `mask-tiles.bin` + `mask-meta.json`, not just a row CSV. For the expected single-plane 64×768 tile map, original packed payload is ~12KiB; generate **two heatmaps on identical axes and 2-bit legend**, a difference map, row/column skip fractions and contiguous runs.
- Confirm exact r6 geometry from runtime; one-shot target `KV=49152` and query layer. If wrong tensor/layer or multiple planes, **stop and correct filter**, don't silently coerce to 64×768.
- Keep raw mask dump out of production timing runs.

ROCm:
- Radeon Developer Panel HIP process selection, SQTT/timing capture (the exact HIP RGP controls may differ).
- The 2026-11-02 r6 HIP capture sampled `flash_attn_tile` in **128k decode**, not aligned 64k prefill; do not assign old 1.49ms to this new work.
- Analyze only same **physical** query size, K depth, selected template/kernel resource footprint and layer; when host ↔ GPU correlation is unverified, save trace as exploratory and consider adding a dedicated opt-in host correlation marker.

## 5. Deliverables / review checklist

Small Git changes (once source changes have been separately implemented): read-only diagnostic source, static tests, diagnostic-off verified binary manifest, and new test plan in `tools/evox2/benchmark/configs/`.

Outside Git: `.rgp`, captured native ZIPs, detailed GPU activity traces and packed mask maps (save their file hashes).

In `evox2-llm-experiments`: update the Nov 4–5 benchmark folder with **matching capture IDs**, heatmaps/derived small figures, explicit identical-position event table, FA-main-vs-mask-prepass time table, retained unexplained PP share, and recording of any GPU idle and clock differences.

Stop and report rather than retrying blindly on DeviceLost, TDR 0x141, OOM, massive paging, truncated SQTT, missing labels or unexplained sample misalignment.
