# r6 S7-B: opt-in MTP `mtp_eh_proj` flatten - 2026-10-27

## Scope and decision state

- **Branch:** `r6/mtp-eh-proj-flatten-20261027`, based on the [S7-A Stage-B measured Vulkan gate](R6-MTP-STAGEB-IMPLEMENTATION-2026-10-27.md#s7-a-windows-vulkan-native-and-runtime-gate---2026-10-27). Stage-B source was built as b11903; the next flatten build must use a **new** build directory and executable SHA.
- **Stage:** S7-B only. No modifications to previously validated S1-S6 features, Vulkan shaders, ROCm kernels, Stage-B's K/V-only attention helper, speculative runtime, or server behavior.
- **Flag:** `LLAMA_MTP_EH_PROJ_FLATTEN=1`. Unset or any other value, including `0`, keeps the previous projection shape. **Default OFF.** It is only effective when the separately guarded `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` Stage-B Draft prefill graph is active.
- **Status:** source patch applied and Linux `g++ -fsyntax-only` PASS. Windows compilation, PowerShell plan parsing, native correctness, real-model C/A/B, performance and K/V numerical parity are **NOT YET VERIFIED**. Do not enable flatten by default on these source-only checks.
- **References:** [r5 isolated flatten prototype and RGP](R5-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-16.md), [r5 combined source rehearsal](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md), [fixed r6 stage plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md).

## Isolated source change

File: `src/models/qwen4exp.cpp`, strictly inside `llama_model_qwen4exp::graph_mtp::graph_mtp`.

For ordinary MTP paths the projection remains the same 3D matmul:

```text
concat([e_norm, h_norm]) -> [2*n_embd, hc, n_tokens]
eh_proj               -> [n_embd, hc, n_tokens]
```

For **Stage-B-eligible, zero-output Draft catch-up only**, with both exact-1 flags set:

```text
concat([e_norm, h_norm]) -> [2*n_embd, hc, n_tokens]
reshape_2d             -> [2*n_embd, hc*n_tokens]
eh_proj                -> [n_embd, hc*n_tokens]
reshape_3d             -> [n_embd, hc, n_tokens]
```

The HC mixer, Draft KV-only attention graph, K/V cache-write roots and all outputs after the reshaping boundary remain in their prior positions. The data order is preserved algebraically, but the changed matmul tiling can alter floating-point rounding. **A tensor-shape/code inspection alone is not numerical K/V parity proof.**

The branch-level gate is:

```cpp
const bool mtp_eh_proj_flatten =
    draft_prefill_kv_crop && eh_flatten_env && std::strcmp(eh_flatten_env, "1") == 0;
```

The base `draft_prefill_kv_crop` guard already requires `n_outputs==0`, masked NextN, no training, no unified KV, one sequence and dense ratio-zero MTP. Setting the flatten flag without Stage-B does nothing, including during Target decoding and regular output-producing Draft verification.

## Test plans (new build identity only)

The following files are committed with this implementation branch once the user authorizes its source commit/push:

- [4k C/A/B smoke](../../tools/evox2/benchmark/configs/qwen38-r6-flatten-smoke.psd1): IQ3/FP4 Vulkan, three variants each.
- [64k/128k long-context A/B](../../tools/evox2/benchmark/configs/qwen38-r6-flatten.psd1): IQ3 Vulkan 64k then conditional 128k **ABBA**, FP4 Vulkan 64k **two-run pair**, optional IQ3 ROCm 64k after backend gates.

In smoke, **C=Stage-B OFF/flatten OFF**, **A=Stage-B ON/flatten OFF**, **B=Stage-B ON/flatten ON**. Compare all three outputs and acceptance, using the same **new flatten-enabled binary**. Note that `C` is a functional control, not part of the flatten-only speed numerator/denominator.

In long-context ABBA, **Stage-B stays ON in all four arms**, and only `LLAMA_MTP_EH_PROJ_FLATTEN` switches `0/1/1/0`. Hold S5 DENSE=1, S6 NOOP=1, Vulkan union=1, minKV32768 and all inference parameters fixed. Do not derive flatten's speed from cross-binary b11903 Stage-B results or add its percentage mechanically to the older Stage-B percentage.

The historical r5 isolated flatten gains were approximately **+1.386% PP at 64k** and **+1.397% at 128k**, with no result difference in its Vulkan output parity cohort. Those are planning priors only, not predicted r6 gains. Under the integration plan's less-than-3% rule, a positive first ABBA may require one additional independent 64k ABBA; do not run unbounded retries.

## Windows Evo-X2 handoff

After the branch and implementation are committed/pushed, fetch this branch in `C:\llama-build\llama.cpp-evox2-windows-r6` without changing the preserved Stage-B binary:

```powershell
git fetch origin
git switch r6/mtp-eh-proj-flatten-20261027
git rev-parse HEAD

$paths = @(
    '.\tools\evox2\benchmark\configs\qwen38-r6-flatten-smoke.psd1',
    '.\tools\evox2\benchmark\configs\qwen38-r6-flatten.psd1'
)
foreach ($path in $paths) {
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $path), [ref]$tok, [ref]$err)
    if ($err.Count -gt 0) { throw ($err.Message -join '; ') }
}

& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-flatten `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4 `
    -ExtraTargets @('test-mtp-indexer-policy', 'test-mtp-dense-indexer',
                    'test-qsa-noop-policy', 'test-qsa-noop-invalidation')
```

Under ignored `tools/evox2/benchmark/configs/local.psd1`, add `Builds.FlattenVulkan.BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-flatten\bin\Release'`, `ExpectedBackend = 'Vulkan'`. Keep existing model/input mappings and **do not overwrite** `StageBVulkan` or its b11903 binary. Inspect the new `evox2-build.json`, `BuildIdentity=Verified`, backend and executable SHA before tests.

### Gate 1b - mandatory native regressions before smoke

```powershell
$config = Import-PowerShellDataFile .\tools\evox2\benchmark\configs\local.psd1
$bin = $config.Builds.FlattenVulkan.BinDir
& (Join-Path $bin 'test-mtp-indexer-policy.exe')
if ($LASTEXITCODE -ne 0) { throw 'S5 policy failed' }
& (Join-Path $bin 'test-mtp-dense-indexer.exe') -m $config.Models.UnslothPle16.Path -md $config.Models.UnslothMtp.Path -ngl 999
if ($LASTEXITCODE -ne 0) { throw 'S5 state/rollback failed' }
& .\tools\evox2\tests\Test-R6MtpNoop.ps1 -BuildKey FlattenVulkan -ModelKey UnslothPle16 -RunModelTests
```

Require the policy/state/rollback tests to pass, not merely the build of test binaries. Known deliberate invalid-state-restore negative probes may print stderr and still be PASS; rely on their exit codes and final assertions.

### Gate 2 - C/A/B short smoke

```powershell
$smoke = '.\tools\evox2\benchmark\configs\qwen38-r6-flatten-smoke.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -OnlyJob flatten-iq3-vulkan-smoke
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -OnlyJob flatten-fp4-vulkan-smoke
```

Require all three variants to load full GPU Main and Draft layers, terminate successfully, retain positive MTP acceptance and coherent output, and leave P-MODE unchanged. Output hash identity is **desirable but not guaranteed** after a changed projection tiling; quantify output/acceptance differences instead of declaring differing bytes a runtime error by themselves. If graph allocation, numerical-state/rollback, GPU-offload or text-quality failures occur, stop before 64k.

### Gate 3 - same-new-binary long-context measurement

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-flatten.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob flatten-iq3-vulkan -OnlyCase 64k
# Only after the 64k output/acceptance/performance review:
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob flatten-iq3-vulkan -OnlyCase 128k
# Only after the IQ3 gate:
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob flatten-fp4-vulkan -OnlyCase 64k
```

Stop at 64k if the optimization is absent, correctness degrades or repeatable regression appears. For gains below 3%, follow the bounded second-ABBA rule before considering promotion. Always report PP, TG, total time, Draft acceptance, normalized output SHA, actual tokens, executable SHA, P-MODE and ADLX. The native previous S5/S6 tests do **not** replace a direct flatten-OFF/ON K/V numerical-state check. A focused RGP comparison is optional only after the functional/speed gate; do not activate broad `FLASH_ATTN_EXT` backend tests.

## Local verification and remaining work

- `g++ -std=c++17 -fsyntax-only -Iinclude -Isrc -Iggml/include -Iggml/src -Icommon src/models/qwen4exp.cpp`: **PASS**.
- `git diff --check`: **PASS** on source change.
- PowerShell parser and Windows build: **pending**, not possible in this Linux scratch environment.
- R6 full-model CPU/GPU numerical-state and performance: **pending**.
- GitHub S7-A documented evidence remains immutable on the separate Stage-B branch. Do not label S7-B implemented/verified in the S7-A source commit.
