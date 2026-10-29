# r6 S2 ROCmFPx port: COMMON-003A / VULKAN-001A / VULKAN-001B

## Scope and state

- **Base:** `r6/common001-ple16-20261025` at `39920946753e14b0e9bc43eba00e186441370ba3` (S1 PASS), with ggml-org/llama.cpp b11870 as its original upstream.
- **Working branch:** `r6/rocmfpx-vulkan-20261025` (separate from S1 and r6 clean).
- **State: S2 PASS (2026-10-25).** Windows Vulkan build/shaders verified; focused numerical **150/150 PASS**; ROCmFP4 FAST PLE16 **4k/16k smoke PASS**, **64k IQ3/ROCmFP4 pair PASS**, and **128k ROCmFP4 PASS**. Next is a separate S3 MTP-compatibility branch; S2 inference source is fixed for handoff.
- **Donor:** `investigation/r5-rocmfpx-vulkan-20261020`. Reused tested commits `85ab8d79` (core), `202f4988` (correctness shaders), `8205db29` (integer dot), `fe36a4d3` (tests).
- **Unchanged roadmap:** S2 then S3, without opportunistic performance changes. ROCmFP4-specific HIP kernels and forcing MMVQ for normal use are **not** included.

| Part | r6 implementation | Notes |
| --- | --- | --- |
| COMMON-003A | GGML types 100, 101, 102, 103, 104, 107; corresponding file types, dequant/quant helpers, loader, CPU fallback | Preserve serialized GGUF IDs. `Q2_0_ROCMFPX` has **no Vulkan shader**, by historical design. |
| VULKAN-001A | 5 Vulkan-supported formats; dequantization, copy, MUL_MAT, MUL_MAT_ID | Covers ROCmFP4, FAST, FP3, FP6, FP8. |
| VULKAN-001B | `q8_1` MMVQ for ROCmFP4/FAST/FP8 and MMQ for ROCmFP4/FAST | FP3/FP6 keep float matvec paths. Default dispatch is unchanged. |
| Test gate | Five types, MUL_MAT and MUL_MAT_ID, widths 1/3/4/5/6/7/8 | Historical 140 cases across normal/forced MMVQ, plus 10 cases for skipped expert IDs (`-1`). |

### b11870-specific adjustment

`mul_mmq.comp` now invokes `block_a_to_shmem(buf_ib, ib, iqs, is_in_bounds)` with **four arguments**; the validated r5 ROCmFP4 donor used three. The port adapts ROCmFP4 and FAST to four arguments, avoids source reads for out-of-range blocks, and zero-initializes both integer-weight halves and the scale. This matters for partial K tiles and prevents a compile error on the new upstream.

The existing upstream `MUL_MAT_ID` test fixture also supports `skip=true` (`-1` expert IDs). Add five targeted ROCmFPx skipped-ID cases at width 4 to catch this edge case without changing the historical 140-case gate. Check both dispatch modes.

## Preliminary local verification

- Cherry-picked four source/test units against S1 without merge conflicts; inspected the resulting upstream dispatch, shader generator, and scope.
- `git diff --check` passed for code commits.
- Local GCC syntax checks passed for `rocmfp4.c`, `rocmfpx.c`, `ggml-quants.c`, `ggml-cpu.c`, and G++ syntax check passed for `ggml-cpu/ops.cpp`.
- This Linux workspace **does not contain the Windows Vulkan SDK, `glslc`, or CMake**. Actual shader compilation and end-to-end execution must be performed on Evo-X2. No performance or GPU correctness claim is made from syntax checks.

### Evo-X2 Vulkan build gate: PASS (2026-10-25 18:55 JST)

User-provided `(vulkan-rocmfpx)evox2-build.json` verifies:

| Item | Observed |
| --- | --- |
| Binary / commit | b11882 / `70545f99826cc1f9d6a0690cd44684124914f2e8` |
| Branch / source state | `r6/rocmfpx-vulkan-20261025`, `Dirty=false` |
| Build identity | **Verified**: embedded commit matches source and source remained stable |
| Config / compiler | Release; LLVM Clang 20.1.8; Ninja Multi-Config; Vulkan SDK 1.4.357.0 |
| Generated artifacts | `ggml-vulkan.dll` (51,179,008 bytes), `test-backend-ops.exe`, `llama-cli.exe`, `llama-server.exe`, `llama-bench.exe` |
| Runtime device | Vulkan0 AMD Radeon(TM) 8060S Graphics, 114507 MiB total |
| Lightweight checks | `llama-cli --version` and `--list-devices` both exit 0 |

The build targets include `llama-cli`, `llama-server`, `llama-bench`, and `test-backend-ops`. Shader build completion is established by the completed build and Vulkan artifact, **not yet by numerical execution**. The `cl` information probe produced D8003 / exit 2 because it was invoked without a source filename; Clang 20.1.8 is the actual compiler recorded for this build. No implication of a failed Vulkan build.

At this **build-only checkpoint**, S2 remained in progress and the next gate was the focused Vulkan numerical test (historical 140 width cases plus 10 skipped-expert cases). Its result is recorded below. `llama-tokenize` is intentionally deferred to the final integrated build; see the [r6 integration plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md#最終統合版のビルド対象2026-10-25追加).

### Evo-X2 numerical correctness gate: PASS (2026-10-25)

User-provided PowerShell log `貼り付けたテキスト（1）(20261025-100712).txt` contains six completed invocations of `test-backend-ops.exe test -b Vulkan0` against the b11882 build.

| Target | Normal | `GGML_VK_FORCE_MMVQ=1` | Total |
| --- | ---: | ---: | ---: |
| `MUL_MAT`, five formats × widths 1/3/4/5/6/7/8 | 35/35 | 35/35 | 70/70 |
| `MUL_MAT_ID`, normal expert IDs | 35/35 | 35/35 | 70/70 |
| `MUL_MAT_ID`, skipped (`-1`) expert IDs | 5/5 | 5/5 | 10/10 |
| **Total** | **75/75** | **75/75** | **150/150 PASS** |

Each invocation ended with `Backend Vulkan0: OK`, `2/2 backends passed`, `OK`. The CPU backend's `Skipping` line is expected from the explicit `-b Vulkan0` filter; the Vulkan-versus-CPU reference numerical comparison was performed inside the test runner. The driver reports `int dot: 1`; no failures or unexpected skipped test cases appeared. The loop's `finally` block removes the forced-MMVQ environment variable afterward.

**Decision:** S2 Vulkan **build and focused numerical correctness gates PASS**. No further numerical-test exploration or shader adjustment is warranted on this evidence. Next, execute the already-fixed 4k/16k ROCmFP4 FAST PLE16 model smoke, verify Vulkan placement, then the prescribed 64k and 128k model runs. **S2 overall remains pending real-model validation.**

### Evo-X2 ROCmFP4 FAST PLE16 actual-model smoke: PASS (2026-10-25)

User-provided archive `20261025-191205-491-cli-vulkan-b11882-ctx16384-1d0200287514.zip` includes the **4k** and **16k** `Measure-LlamaCli.ps1 -AllocationOnly` runs. Both used Vulkan b11882 / `70545f998`, `Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf` (`Q4_0_ROCMFP4_FAST`), no speculative draft (`--spec-type none`), f16 K/V, and Performance P-MODE.

| Evidence | 4k | 16k |
| --- | --- | --- |
| Run / context | `20261025-191051-044` / 4096 | `20261025-191205-491` / 16384 |
| `result.json` / exit | `OK`, 0 | `OK`, 0 |
| Model type | `Q4_0_ROCMFP4_FAST` | Same |
| GPU placement | `offloaded 49/49 layers to GPU` | Same |
| Vulkan0 model buffer | 88645.69 MiB | 88645.69 MiB |
| Vulkan_Host model buffer | 497.31 MiB | 497.31 MiB |
| **CPU model buffer** | **Not present** | **Not present** |
| Vulkan0 KV buffers | 96 + 24 MiB | 384 + 96 MiB |
| Vulkan graph splits | 3 | 3 |
| Generated output | `OK` (2 tokens) | `OK` (2 tokens) |
| P-MODE | Performance (`RawValue=1`) | Same |
| Runtime artifact verification | Verified | Verified |

Both logs show Flash Attention enabled and successful response generation. The earlier incomplete-port symptom of a **~41.8 GiB CPU model buffer** is absent; model weights are fully GPU-offloaded. The log contains `resolve_fused_ops: fused top-k mask not supported, set to disabled`, an explicitly disabled optional fusion path, **not a fatal model-load/operation error**. Also `common_conte: the context does not support partial sequence removal` is informational in these successful runs.

**Limitations:** Only two tokens were generated in each short prompt. The reported PP/TG values (4k: 7.90/4.67; 16k: 45.63/23.97 tok/s) are *not* throughput baselines; model initialization/warmup dominates. ADLX reports `InsufficientSamples` for high-load P-MODE consistency because these are smoke runs; start/end mode is Performance. Meaningful speed and longer-output correctness remain for the already-planned long runs.

**Decision:** S2 numerical correctness + actual-model **4k/16k load, full Vulkan placement and tiny generation gates PASS**. Next gate remains **64k IQ3 PLE16 regression control plus 64k ROCmFP4 FAST PLE16**, followed by **128k ROCmFP4 FAST PLE16** after reviewing the 64k result. No new 256k gate, MMVQ forcing, or patch-order change.

### Evo-X2 64k real-document measurement: PASS (2026-10-25)

User-provided archive `20261025-192456-512-cli-vulkan-b11882-ctx65536-2fd9fdb07ce1.zip` contains exactly the two fixed S2 64k matrix runs (`s2-iq3-ple16-control` and `s2-rocmfp4-fast-ple16`), both Vulkan b11882 / `70545f998`, MTP OFF, f16 KV, `-ngl 999`, `-ncmoe 0`, temperature 0.2, top-p 0.8, reasoning off, normal Vulkan MMVQ policy. The real-document input SHA-256 is **`2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`**, 61,789 tokens, identical to the S1 64k input.

| Evidence | IQ3 PLE16 control | ROCmFP4 FAST PLE16 |
| --- | ---: | ---: |
| Run ID prefix | `20261025-192032-239` | `20261025-192456-512` |
| `Status` / exit | `OK` / 0 | `OK` / 0 |
| PP (tok/s) | **343.56** | **351.27** |
| TG (tok/s) | 26.23 | 26.28 |
| Generated tokens | 518 | 602 |
| Duration (s) | 244.364 | 248.735 |
| GPU layers / CPU model buffer | 49/49; **none** | 49/49; **none** |
| Vulkan0 model buffer | 77657.05 MiB | 88645.69 MiB |
| Vulkan0 memory breakdown `free` | 27826 MiB | 16837 MiB |
| P-MODE start/end and ADLX power classification | Performance / Performance; consistent | Performance / Performance; consistent |
| High-GPU-usage ADLX samples | 97 | 98 |
| Mean GPU power in those samples | 116.3 W | 115.9 W |
| Mean VRAM clock in those samples | 994.8 MHz | 999.5 MHz |

Both models produced coherent Japanese technical summaries and have no error/crash, partial GPU placement, or sustained low-VRAM-clock evidence. The known Vulkan `fused top-k mask not supported, set to disabled` warning appeared in both, matching S1 behavior; it did not prevent the runs. Runtime artifact verification passed.

**Comparisons (one run per r6 S2 model):** S1 IQ3 PLE16 Vulkan 64k PP/TG **344.51 / 26.51** versus S2 **343.56 / 26.23** (PP **−0.28%**, TG **−1.06%**): no material regression. S2 ROCmFP4 has PP **+2.24%** relative to S2 IQ3, with essentially tied TG. This resembles r5 Stage5 b11561 MTP-OFF 64k ABBA (**277.50 ROCmFP4 vs 272.29 IQ3**, +1.91%), but **r5→r6 absolute performance differences are not the isolated effect of this ROCmFPx patch**: upstream version and sampling/output limits differ (r5 temp 0/max 512 versus r6 temp 0.2/max 1024), and GPU state can vary. No superiority in output quality is inferred from the different outputs or generation lengths.

**Decision:** S2 **64k dual-model real-document gate PASS**. The fixed remaining gate is **one 128k ROCmFP4 FAST PLE16 Vulkan run**; no new 64k repeats, 256k runs, or unrelated optimization work. If the 128k run passes model placement, coherent output, execution, and P-MODE/ADLX checks, complete S2 and proceed to the planned S3 MTP compatibility work.

### Evo-X2 128k ROCmFP4 FAST PLE16 real-document gate: PASS (2026-10-25)

User-provided archive `20261025-193755-157-cli-vulkan-b11882-ctx131072-bf7552400da9.zip` verifies the sole planned S2 128k case. Binary b11882 / `70545f998`; normal Vulkan dispatch, MTP OFF, f16 K/V, `-ngl 999`, `-ncmoe 0`, temperature 0.2, top-p 0.8, reasoning off. Input `nlp-survey-ch3-d15-b1.txt` has **126,253 tokens** and SHA-256 **`182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`**, matching S0/S1's 128k corpus.

| Evidence | Observed |
| --- | --- |
| Result / exit / runtime artifacts | `OK` / 0 / `Verified` |
| GGUF | `Q4_0_ROCMFP4_FAST`, model file 87.05 GiB |
| PP / TG | **275.28 / 24.19 tok/s** |
| Prompt / generated tokens | **126,253 / 577** |
| Duration | 532.357 s |
| GPU placement | **49/49 GPU layers**, no CPU model buffer |
| Vulkan0 model + KV + compute | 88645.69 + 3840.00 + 828.60 MiB |
| Vulkan0 memory breakdown `free` | 14788 MiB |
| P-MODE | Performance start/end, no mode change |
| ADLX high-load samples / power | 240 / **117.7 W**, Performance-like / consistent |
| ADLX VRAM clock / GPU temperature, high-load mean | **999.6 MHz / 82.9°C** |

Output is a coherent Japanese summary of sentiment lexicons, semantic relations, PMI/co-occurrence, context-sensitive polarity and document classification, with no mojibake or runaway repetition. The known nonfatal `fused top-k mask not supported, set to disabled` warning remains. No crashes, hidden model CPU placement, high-load P-MODE mismatch, or sustained low-VRAM-clock state occurred.

**Context-only comparisons:** r6 S1 b11879 IQ3 PLE16 128k was **270.57 PP / 24.35 TG**, versus r6 S2 ROCmFP4 **275.28 / 24.19**. These are different model formats and different builds, not an isolated ROCmFPx-patch A/B. Historical r5 Stage5 b11561 ROCmFP4 MTP-OFF 128k ABBA was **180.75 PP / 23.90 TG**; the r6 S2 PP is about **52.3% higher**, primarily a cross-upstream/build observation, **not attributable specifically to this port**. Measurement is one run, not a repeatability study.

**Final decision: S2 PASS.** COMMON-003A + VULKAN-001A/001B meet the predetermined build, 150-case numerical, 4k/16k smoke, 64k dual-model and 128k ROCmFP4 gates on Evo-X2. Preserve this branch/build as the S2 baseline. Next create a dedicated **S3 MTP compatibility** branch from the passing S2 source. Follow the precommitted plan: first check b11870 native MTP behavior for IQ3/ROCmFP4 target + matching draft, then port only compatibility differences actually needed. Do **not** introduce performance patches, 256k reruns, or HIP ROCmFP4 kernels into S3 scope.

## User-side build and validation sequence (Windows / Evo-X2)

**1. Preserve S1 baseline, fetch and check out the S2 branch.** Run in the existing r6 worktree; keep the S0 and S1 build directories untouched.

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git switch -c r6/rocmfpx-vulkan-20261025 --track origin/r6/rocmfpx-vulkan-20261025
git status

.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-r6-rocmfpx -Parallel 4
```

- First inspect the build JSON: branch/commit/build identity, Vulkan backend and compiler, and that new shader compilation succeeded.
- **Do not** start unfiltered `test-backend-ops` or the ROCm `FLASH_ATTN_EXT` suite. The earlier Windows watch-dog incidents make those unsuitable for this gate.

**2. Focused numerical gate.** The following test paths preserve the r5 140-case gate and independently test the five skipped-expert cases under both dispatch modes. The `type_a` regex selects only the new formats. If the upstream test runner's filter semantics differ from expected, inspect the printed case count before treating a test as passed.

```powershell
$bin = '.\build-vulkan-r6-rocmfpx\bin\Release'
$exe = "$bin\test-backend-ops.exe"
$types = 'type_a=(q4_0_rocmfp4|q4_0_rocmfp4_fast|q3_0_rocmfpx|q6_0_rocmfpx|q8_0_rocmfpx)'

try {
    foreach ($mode in @('normal', 'force-mmvq')) {
        if ($mode -eq 'force-mmvq') {
            $env:GGML_VK_FORCE_MMVQ = '1'
        } else {
            Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
        }
        & $exe test -b Vulkan0 -o MUL_MAT -p $types
        & $exe test -b Vulkan0 -o MUL_MAT_ID -p "$types.*skip=0"
        & $exe test -b Vulkan0 -o MUL_MAT_ID -p "$types.*skip=1"
    }
} finally {
    Remove-Item Env:GGML_VK_FORCE_MMVQ -ErrorAction SilentlyContinue
}
```

Expected focused cases: 35 MUL_MAT + 35 ordinary MUL_MAT_ID + 5 skipped-ID MUL_MAT_ID per mode; **150/150** over both modes. Keep stdout/stderr and all failures. `ggml` support/skipped messages are not numerical passes; verify tests actually executed and numerical comparison passed.

**3. Actual model smoke.** Update `tools/evox2/benchmark/configs/local.psd1` (ignored by Git) with:

```powershell
# Append inside Builds:
S2Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-rocmfpx\bin\Release'
    ExpectedBackend = 'Vulkan'
}
# Append inside Models (actual first GGUF shard or model path):
AgentionRocmFp4FastPle16 = @{
    Path = 'C:\path\to\Qwen3.8-Flash-Next-ROCmFP4-FAST-ple16.gguf'
    Alias = 'agention-rocmfp4-fast-ple16'
}
```

The local `UnslothPle16` and `Inputs.64k` / `Inputs.128k` entries remain the same as S1. Check the ROCmFP4 FAST model's own GGUF header/type IDs and keep the GGUF input checksum in logs.

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"
$plan = "$bench\configs\qwen38-r6-rocmfpx.psd1"

# Short smoke: do not proceed unless generation and GPU placement are correct.
& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan -ModelKey AgentionRocmFp4FastPle16 -AllocationOnly -Context 4096
& "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey S2Vulkan -ModelKey AgentionRocmFp4FastPle16 -AllocationOnly -Context 16384

# Only after numerical tests and smoke have passed.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k

# Only after 64k succeeds. No new 256k repetitions in S2.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k
```

`-AllocationOnly` in this measurement tool is the established short smoke mode. Verify it actually performs generation, not merely allocation. Check all-layer Vulkan placement versus the earlier ~41.8 GiB CPU buffer seen before VULKAN-001A, P-MODE and ADLX metadata, graph splits, coherent output, and unexpected CPU fallback. The 64k IQ3 PLE16 run is the S2-binary regression control, not proof of ROCmFP4-vs-IQ3 quality parity.

**STOP conditions:** compilation errors; failure/skipping in the 150-case numerical gate; model type 101 load failure; inappropriate CPU model placement; output corruption; abnormal power mode; repeated crashes. Record diagnostics in S2 before discussing S3. Keep ROCmFP4 MTP and the remaining r6 patch list for their planned later stages.
