# r6 MTP Stage-B: isolated Draft KV-only prefill port - 2026-10-27

## Status and source lineage

- **Branch:** `r6/mtp-stageb-20261027`, created from the completed S6-NOOP GitHub commit `02e44a240a975bbb3de689425ebf3185edded057` (original upstream baseline b11870).
- **Scope:** Stage-B only. `mtp_eh_proj` flatten is **not ported**, and neither are the old Stage-A-only or KV snapshot diagnostics.
- **Stage-B flag:** `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` enables the new graph path; unset, `0`, or any other value uses the original full Draft graph. The default is **OFF**.
- **Port reference:** r5 integration rehearsal `integration-check/r5-noop-rocmfpx-stageb-flatten-20261021`, specifically `ad7b40242` (mask), `dafa1b826` (prefill guard), `efddcd28a` (helper declaration), `9ee8a940b` (dedicated K/V graph). The r5 source-level coexistence check is documented in [R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md).
- **Status:** local C++ syntax checks and source review PASS; **Windows build, real-model Stage-B activation, Draft K/V parity, output/acceptance/rollback and throughput remain unverified**. Do not call Stage-B PASS before native checks.

## Implementation boundaries

Only Qwen4Exp's Draft `graph_mtp` evaluates the opt-in flag. Stage-B runs if **all** conditions hold:

1. Exact env `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`.
2. `n_outputs == 0` with both `embeddings_nextn` and `embeddings_nextn_masked`.
3. No training, no unified KV, and exactly one unique sequence.
4. Draft layer's QSA compression ratio is zero (dense MTP layer).

For that graph, keep Draft token/hidden inputs, recurrent-copy root, `mtp_hnorm`, `mtp_enorm`, `mtp_eh_proj` and attention HC mixing. The new `build_layer_attn_kv_only()` then runs **the same** WK/WV projections, K RMS norm, M-RoPE and optional K/V rotations as the full dense attention path. It independently roots both KV `cpy_k`/`cpy_v` cache writes and returns without creating the query/gate, Flash Attention, attention output, FFN or output-head graph. It skips the zero-row `out_ids` input. There is no change to output-producing Draft verification/decode, Target graphs, QSA selection, Vulkan or HIP kernels.

The hybrid attention mask input now checks both tensor and allocated buffer before filling. This preserves the ordinary mask while allowing cache-write-only graphs where no mask is allocated.

**Correctness limits:** source shape and `ggml_build_forward_expand()` prove the intended graph roots are present but **do not prove native K/V equality or speculative rollback correctness**. Native output/acceptance parity and a dedicated K/V state comparison are separate gates. Do not infer correctness from a throughput gain.

## Preserved upstream and previous r6 features

- S1 PLE16, S2 ROCmFPx Vulkan, S3 old-HC MTP sidecar, S4 union, S5 DENSE and S6 NOOP sources unchanged.
- The ratio-zero MTP k-pool guard is preserved. Stage-B's KV-only helper asserts that the Draft has no k-pool input.
- Both S5 DENSE and S6 NOOP stay independently optional and default OFF; hold them **ON in both comparison arms** to measure only Stage-B.
- For this *combined* Stage-B check, keep previously validated Vulkan QSA union **ON in both arms**, min-KV 32768. This differs from S6-NOOP's isolated union-OFF experiment, so **do not compare absolute S6 and Stage-B numbers as a controlled pair**.
- Flatten's future flag `LLAMA_MTP_EH_PROJ_FLATTEN` is explicitly cleared in the new plans; the next integration commit can add it without changing this Stage-B baseline.
- 256k and unrelated RGP/kernel experiments are outside this gate.

## Local source checks (2026-10-27)

Passed:

```sh
g++ -std=c++17 -fsyntax-only -Iinclude -Isrc -Iggml/include -Iggml/src -Icommon src/models/qwen4exp.cpp
g++ -std=c++17 -fsyntax-only -Iinclude -Isrc -Iggml/include -Iggml/src -Icommon src/llama-graph.cpp
git diff --check
```

The scratch Linux environment lacks Windows PowerShell, the Vulkan SDK and the real GGUF models. The two new `.psd1` plans **must be parsed with Windows PowerShell** before native runs. No native build/smoke/throughput is claimed here.

## Windows test gate (one gate at a time)

Add these entries to the ignored `tools/evox2/benchmark/configs/local.psd1` under `Builds` after the new binaries have been built, leaving all existing S6 paths untouched:

```powershell
StageBVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-stageb\bin\Release'
    ExpectedBackend = 'Vulkan'
}
StageBROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-r6-stageb\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Keep `UnslothPle16`, `UnslothMtp`, `AgentionRocmFp4FastPle16`, `AgentionRocmFp4FastMtp` and `Inputs.64k/128k` at their previous verified model/input paths. Do not reuse/overwrite the S6 binary directory.

**Gate 0 - confirm the branch and parse plans:**

```powershell
git branch --show-current
git rev-parse HEAD
$plans = @(
    '.\tools\evox2\benchmark\configs\qwen38-r6-stageb-smoke.psd1',
    '.\tools\evox2\benchmark\configs\qwen38-r6-stageb.psd1'
)
foreach ($plan in $plans) {
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $plan), [ref]$tok, [ref]$err)
    if ($err.Count -gt 0) { throw ($err.Message -join '; ') }
}
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plans[0] -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plans[1] -PlanOnly
```

**Gate 1 - build the independent Vulkan binary:**

```powershell
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-stageb `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4 `
    -ExtraTargets @('test-mtp-indexer-policy', 'test-mtp-dense-indexer',
                    'test-qsa-noop-policy', 'test-qsa-noop-invalidation')
```

Check `evox2-build.json`, Vulkan/GPU offload and DLL hashes. The S5/S6 native tests are **regressions**, not a substitute for exercising the Stage-B graph. Run the test executables and the existing `Test-R6MtpNoop.ps1 -BuildKey StageBVulkan -ModelKey UnslothPle16 -RunModelTests` if available.

**Gate 2 - Vulkan short OFF/ON, IQ3 first, then FP4:**

```powershell
$smoke = '.\tools\evox2\benchmark\configs\qwen38-r6-stageb-smoke.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -OnlyJob stageb-iq3-vulkan-smoke
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -OnlyJob stageb-fp4-vulkan-smoke
```

Both variants must load Target/Draft on GPU and exit successfully. Compare generated text, Draft acceptance, input/model/binary hashes, P-MODE and ADLX. The ON path must actually reach zero-output Draft catch-up; for definitive FA absence/KV parity, use the existing r5 KV-snapshot diagnostic **only as an optional separately isolated follow-up**, never automatically merge that instrumentation into this candidate.

**Gate 3 - Vulkan 64k ABBA, then 128k; FP4 64k after IQ3 gates:**

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-stageb.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stageb-iq3-vulkan -OnlyCase 64k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stageb-iq3-vulkan -OnlyCase 128k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stageb-fp4-vulkan -OnlyCase 64k
```

ABBA order is `C1 (Stage-B OFF) / A1 (Stage-B ON) / A2 (ON) / C2 (OFF)`; the normal `EVOX2_ABBA_RUN` labels remain `A1/B1/B2/A2`. No flatten. Record PP, TG, complete elapsed time, Draft acceptance, active context/outputs and resource state. r5 recorded **64k improvement but 128k regression**, so do not enable Stage-B by default on a 64k-only result. If output differs on Vulkan, or there is a native correctness/rollback error, stop.

**Gate 4 - ROCm only after Vulkan correctness, TheRock 10.0:** build to a new `build-rocm-r6-stageb` directory using the existing `Build-ROCm.ps1` workflow with the same four optional test targets. Do not run `-RunBackendTest` or the broad `FLASH_ATTN_EXT` backend test. Confirm the staged TheRock DLL set, run native test regressions and `stageb-iq3-rocm-smoke`, then `stageb-iq3-rocm -OnlyCase 64k`. ROCm temp=0 output nondeterminism is known; inspect correctness and acceptance separately from PP/TG.

## Gate decision / future flatten step

Until the Windows/native results arrive, Stage-B is **IMPLEMENTED / UNVERIFIED**, with its default OFF. If the independent C/A gate passes, add flatten in a **separate commit on this lineage**, with its own exact-1 flag and Stage-B-prefill-only scope. Then measure C (neither), A (Stage-B only), and B (Stage-B plus flatten) without changing the Stage-B baseline binary identity within each comparative set.
