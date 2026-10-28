# r6 S7-B: opt-in MTP `mtp_eh_proj` flatten - 2026-10-27

## Scope and decision state

- **Branch:** `r6/mtp-eh-proj-flatten-20261027`, based on the [S7-A Stage-B measured Vulkan gate](R6-MTP-STAGEB-IMPLEMENTATION-2026-10-27.md#s7-a-windows-vulkan-native-and-runtime-gate---2026-10-27). Stage-B source was built as b11903; the next flatten build must use a **new** build directory and executable SHA.
- **Stage:** S7-B only. No modifications to previously validated S1-S6 features, Vulkan shaders, ROCm kernels, Stage-B's K/V-only attention helper, speculative runtime, or server behavior.
- **Flag:** `LLAMA_MTP_EH_PROJ_FLATTEN=1`. Unset or any other value, including `0`, keeps the previous projection shape. **Default OFF.** It is only effective when the separately guarded `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` Stage-B Draft prefill graph is active.
- **Status (2026-10-28):** Windows Vulkan b11906 and the existing S5/S6 native regressions PASS; IQ3/ROCmFP4 4k C/A/B, IQ3 64k (two ABBA sets), 128k (one ABBA set), and ROCmFP4 64k (one ABBA assembled from A/B then reverse B/A) all PASS for runtime and output parity. **16/16 long runs completed**, with a reproducible small PP benefit. See [measured closure](#s7-b-windows-vulkan-measured-closure---2026-10-28-jst). Dedicated flatten/Stage-B K/V numerical-state comparison and ROCm S7 runtime are **not** verified. Retain default OFF.
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

The following files were committed with the S7-B implementation branch:

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
- PowerShell parser and Windows build: **initially pending** in this Linux environment; Windows b11906 verification is recorded in the measured closure below.
- Dedicated flatten-OFF/ON Draft K/V numerical-state parity: **pending**. Real-model output and acceptance checks are recorded below, and do not replace that proof.
- GitHub S7-A documented evidence remains immutable on the separate Stage-B branch. Do not label S7-B implemented/verified in the S7-A source commit.

## S7-B Windows Vulkan measured closure - 2026-10-28 JST

### Build identity, native correctness and smoke

- **Source:** GitHub `r6/mtp-eh-proj-flatten-20261027`, commit `3e377c23827945a7f71bfc741bd03d1c97e7fe89`. Build manifest Source/BuildSource clean and `BuildIdentity.Status=Verified`.
- **Binary:** Vulkan `llama-cli.exe` b11906, Clang 20.1.8, SHA256 `27de7107bd25dc1ec44a818e200c56b0de13d3253c2990a6c534cd513953b97b`; `--version`, `--list-devices` both exit0; Vulkan0 Radeon 8060S.
- **Gate 1b:** S5 `test-mtp-indexer-policy` and `test-mtp-dense-indexer` exit0. S6 QSA NOOP policy and model/state/rollback exit0; model log has **524/524** comparisons with `nmse=0 max_abs=0`. These are existing S5/S6 regressions, **not** an independent S7-B K/V numerical test.
- **Gate 2:** IQ3 PLE16 and ROCmFP4 FAST PLE16 each ran C (Stage-B OFF/flatten OFF), A (Stage-B ON/flatten OFF), B (both ON) at ctx4096. **6/6 PASS**; both models preserve the output SHA and Draft acceptance across all three arms: IQ3 **35/54**, FP4 **34/56**. Both Main and Draft fully offload to Vulkan (**49/49 + 50/50 layers**). Input is only **163 prompt tokens**, so smoke PP/TG differences must not be interpreted as a throughput verdict.

### Same-binary long-context A/B

All rows below are Vulkan `llama-cli`, MTP ON / DraftMax=2, `temp=0`, `n-predict=512`, f16 KV, P-MODE Performance, S5 DENSE=1, S6 NOOP=1, Vulkan QSA union=1 (`MIN_KV=32768`) and **Stage-B=1 fixed**. The **only independent speed switch** is `LLAMA_MTP_EH_PROJ_FLATTEN=0/1`. Means below are arithmetic means of per-run rates or reported elapsed milliseconds, not pooled tokens divided by inferred elapsed time. Do not add isolated patch percentages to predict an S8 all-on speed.

| Model / ctx | Run order | OFF PP | ON PP | PP delta | OFF TG | ON TG | TG delta | Total time OFF -> ON | Runs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| IQ3 PLE16 / 64k | ABBA twice | 352.803 | 358.365 | **+1.58%** | 33.813 | 33.373 | -1.30% | 190.253 -> 187.744 s (**-1.32%**) | **8/8 OK** |
| IQ3 PLE16 / 128k | ABBA | 318.900 | 323.070 | **+1.31%** | 30.490 | 30.460 | -0.10% | 412.666 -> 407.561 s (**-1.24%**) | **4/4 OK** |
| ROCmFP4 FAST PLE16 / 64k | A1/B1 then B2/A2 | 359.655 | 366.930 | **+2.02%** | 34.740 | 33.770 | -2.79% | 186.511 -> 183.543 s (**-1.59%**) | **4/4 OK** |

Actual prompt lengths: 64k **61,789**, 128k **126,253**; all produced 512 tokens. Each cohort preserved exact generated output SHA and Draft accepted/generated counts for **all** of its OFF/ON runs:

| Cohort | Output SHA256 | Draft accepted/generated |
| --- | --- | --- |
| IQ3 64k (all eight) | `aa1c3db180847699c195094867bb7ff76fd73861a1881d6393c78deb7b91adfb` | **301/419** |
| IQ3 128k (all four) | `a69fe4cfc02c69f8851e86254660758869143ecda7546b15f2e9060206523c9e` | **301/420** |
| FP4 64k (all four) | `598eb18e10bc590082dc93b4e2316a2eb639fdc1c89a685e7cd3d80cfd505c49` | **295/431** |

**TG dispersion must not be hidden by averaging:** IQ3's first 64k B1 had TG **31.86** versus A1 **33.78**, but B2 **33.84** and the second independent ABBA's B1/B2 **33.90/33.89** showed no sustained regression. FP4's first 64k B1 was **32.73** versus A1 **34.79**, but the reverse-order B2 was **34.81** versus A2 **34.69**. Each anomalous TG difference was approximately **0.9 s** of actual 512-token generation time; associated P-MODE/ADLX, GPU/VRAM clocks and temperatures showed no obvious throttle. Short 4k FP4 smoke also showed lower B TG, but 64-token timing is not a reliable performance estimate. **An intermittent flatten-specific TG effect is not excluded**, especially for FP4, and remains a risk for S8.

All **16/16** long runs: `Status=OK`, exit0, backend Vulkan, Main/Draft full GPU offload, identical b11906 executable SHA, P-MODE Performance at start/end and ADLX high-load class Performance-like without warnings. No 256k measurement was run in S7.

### Raw archive provenance (not committed into Git)

| Uploaded file | SHA256 |
| --- | --- |
| `(vulkan-flatten)evox2-build.json` | `f1933edb62443f87f163f62ebf2e9dcaebc5ca976a83e3ca0972dd98b97e39b9` |
| `test-20261027-232644.log` | `d3085298bd2fdcaedd49b6e56e3912744461987c51521eaa5749eaddaa921c7b` |
| `20261027-232813-483-qsa-noop-invalidation.zip` | `fe29787cad21f99ab7aeff741798d231e7b5514952bb7e63b8405e3b8cb16fa0` |
| `20261027-234200-023-cli-vulkan-b11906-ctx4096-095f9b9cb3c6.zip` | `6d8324d87ad706e1ec3170a1aeaa5c97fcbc4c246dd9480d9da67cd30e461f05` |
| `20261028-000206-652-cli-vulkan-b11906-ctx65536-672fece75a48.zip` | `81fd71e777714afccd24b68a95af8d15386171ff60d01a52bca0de20e4c35bc2` |
| `20261028-003319-872-cli-vulkan-b11906-ctx65536-672fece75a48.zip` | `f2a81b91101a2f4738fdddbeed0b62015129999f8858337c9aa38599c33add9b` |
| `20261028-010534-102-cli-vulkan-b11906-ctx131072-2fb06efa2e14.zip` | `f826e45c65b5564399e3e41f6402bba0bae126e0f3cec3bee3a1ac944b4e7ae3` |
| `20261028-082239-970-cli-vulkan-b11906-ctx65536-18591083eb01.zip` | `9ec71c7269e4706198e2dd1ba517319d975bef5a46ef9dc16b5018ac44691537` |
| `20261028-102857-103-cli-vulkan-b11906-ctx65536-ead84311029d.zip` | `00bc1198a8497f1f923219215b2821f986d7c94d4857454e8f1b9456aed980ec` |

### S7-B decision and S8 handoff

**Vulkan smoke/native and bounded performance gate PASS; retain flatten as an independently switchable, default-OFF S8 candidate.** IQ3 64/128k and FP4 64k PP gains are modest but directionally repeatable, with identical per-cohort outputs and Draft acceptance. It is **not a default-ON decision**, a direct K/V parity proof, or an ROCm S7 validation. Stage-B must stay independently switchable, and `LLAMA_MTP_EH_PROJ_FLATTEN=1` has no effect without an eligible Stage-B graph. At S8, compare both combined-ON and combined-OFF **within the same new binary**; test FP4 128k and selectively validate ROCm S7 before enabling either Stage-B or flatten there. If TG degradation is repeatable, leave flatten OFF while retaining Stage-B. Full next-stage scope and stop conditions: [S8 combined integration plan](R6-S8-COMBINED-INTEGRATION-PLAN-2026-10-28.md).
