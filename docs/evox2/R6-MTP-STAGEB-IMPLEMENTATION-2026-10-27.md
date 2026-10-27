# r6 MTP Stage-B: isolated Draft KV-only prefill port - 2026-10-27

## Status and source lineage

- **Branch:** `r6/mtp-stageb-20261027`, created from the completed S6-NOOP GitHub commit `02e44a240a975bbb3de689425ebf3185edded057` (original upstream baseline b11870).
- **Scope / stage:** S7-A Stage-B only (2026-10-27 corrected plan numbering). S7-B `mtp_eh_proj` flatten is **not ported**, and neither are the old Stage-A-only or KV snapshot diagnostics.
- **Stage-B flag:** `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` enables the new graph path; unset, `0`, or any other value uses the original full Draft graph. The default is **OFF**.
- **Port reference:** r5 integration rehearsal `integration-check/r5-noop-rocmfpx-stageb-flatten-20261021`, specifically `ad7b40242` (mask), `dafa1b826` (prefill guard), `efddcd28a` (helper declaration), `9ee8a940b` (dedicated K/V graph). The r5 source-level coexistence check is documented in [R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md).
- **Status (2026-10-27 22:24 JST):** local source checks, Vulkan b11903 build identity, native S5/S6 regressions, 4k IQ3/FP4 smoke, IQ3 64k/128k ABBA, and FP4 64k A/B **PASS**. All 10 long-context Vulkan runs completed with exact within-model output/acceptance parity; Stage-B improves PP and TG in all tested conditions. **ROCm native runtime and a dedicated K/V numerical parity test remain open; flag remains default OFF.**

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

The scratch Linux environment lacks Windows PowerShell, the Vulkan SDK and the real GGUF models. The two new `.psd1` plans **must be parsed with Windows PowerShell** before native runs. The local source checks above alone do not establish Windows build, smoke or throughput; the independent Windows build evidence is recorded below.

## Windows Vulkan build report - 2026-10-27 20:28 JST

The uploaded `(vulkan-stageb)evox2-build.json` confirms the first Windows Vulkan build gate:

- **Source/build:** branch `r6/mtp-stageb-20261027`, GitHub commit `c162ba762b63856b3315c489f0b912e09e743337`, both Source and BuildSource clean; `BuildIdentity.Status=Verified`.
- **Executable:** Vulkan `llama-cli.exe` b11903 / `c162ba762` / Clang 20.1.8; `--version` exit0.
- **Device:** `--list-devices` exit0 and Vulkan0 AMD Radeon 8060S, 114507 MiB reported. `ggml-vulkan.dll` created.
- **Targets present:** `llama-cli`, `llama-server`, `llama-bench`, `test-backend-ops`, `test-mtp-indexer-policy`, `test-mtp-dense-indexer`, `test-qsa-noop-policy`, `test-qsa-noop-invalidation`.
- **Limits:** the four native policy/state test binaries were **built, not yet run**. Stage-B path activation, output/KV equality, rollback and PP/TG have **no passing evidence yet**. The toolchain's `cl` probe exit2 (`D8003`, no source file supplied) does not indicate a failed Clang build.

**Completed:** S5/S6 policy/state regression tests, S7-A IQ3/FP4 short smoke, and same-binary Vulkan long-context runs. Preserve the original b11903 executable for all comparisons; details and remaining limits are recorded below.

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

Check `evox2-build.json`, Vulkan/GPU offload and DLL hashes. The uploaded b11903 report has passed this build check.

**Gate 1b - mandatory S5/S6 native policy/state/rollback regressions before any smoke:**

After adding `StageBVulkan` under `Builds` in `local.psd1`, execute from the repository root:

```powershell
$config = Import-PowerShellDataFile .\tools\evox2\benchmark\configs\local.psd1
$bin = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-stageb\bin\Release'
$mainModel = $config.Models.UnslothPle16.Path
$draftModel = $config.Models.UnslothMtp.Path

# S5 DENSE: pure policy, then actual model/state/rollback parity.
& (Join-Path $bin 'test-mtp-indexer-policy.exe')
if ($LASTEXITCODE -ne 0) { throw 'S5 indexer policy failed' }
& (Join-Path $bin 'test-mtp-dense-indexer.exe') -m $mainModel -md $draftModel -ngl 999
if ($LASTEXITCODE -ne 0) { throw 'S5 model/state/rollback failed' }

# S6 NOOP: source/plan checks, policy and actual model/state/rollback.
& .\tools\evox2\tests\Test-R6MtpNoop.ps1 `
    -BuildKey StageBVulkan -ModelKey UnslothPle16 -RunModelTests
```

Require `MTP indexer policy: PASS`, `MTP dense indexer: PASS (...)`, `QSA no-op policy: PASS`, and `QSA no-op invalidation: PASS (...)`. Retain the two S5 native test outputs and inspect the S6 wrapper's `evox2-logs/tests` JSON report; stop if any test fails. These are **regressions only**: passing them does **not** prove that the new S7-A Stage-B graph preserves K/V or rollback. Gate 2's real MTP OFF/ON smoke is still mandatory, and a dedicated K/V parity diagnostic is a separate follow-up if needed.

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

The **Vulkan** native/smoke/64k/128k Stage-B gates have passed; see the measured closure below. This is not a cross-backend or numerical K/V proof: the independently testable ROCm gate and dedicated K/V numerical parity remain open. Stage-B stays opt-in/default OFF. S7-B flatten must be introduced on a separate branch and commit with its own exact-1 flag, scoped to the Stage-B prefill path; C (neither), A (Stage-B only), and B (Stage-B plus flatten) must be independently selectable. In each new A/B performance cohort, compare variants using the **same new binary**, not old b11903 absolute speed.

## S7-A Windows Vulkan native and runtime gate - 2026-10-27

### Native regressions and 4k functional smoke

- Tested binary: `llama-cli` Vulkan **b11903**, commit `c162ba762`, SHA-256 `23b9ae23cf2a38f4d60bc0a9e726ba1c9304c6c9c299e8c47c7efbc1791edd4a`; `RuntimeArtifactStatus=Verified` throughout.
- S5 `test-mtp-indexer-policy` and `test-mtp-dense-indexer` **PASS**; real-model DENSE state/rollback checks `nmse=0`, `max_abs=0`. S6 `Test-R6MtpNoop.ps1 -RunModelTests` **PASS**, including `test-qsa-noop-policy` and the invalidation/state/rollback model checks (**524/524**, `nmse=0`, `max_abs=0`). The deliberate invalid-state restoration messages in native stderr are negative-test coverage, not runtime failures.
- IQ3 PLE16 + Unsloth Q8_0 Draft 4k: OFF/ON **2/2 OK**, 163 prompt/64 generated tokens, accepted **35/54**, exact normalized output SHA-256 `a4f6894871de763da852c0584c46111220fc91521c429ac96637fad41e96267b`. PP **110.22 -> 279.05**, TG **21.17 -> 37.25 tok/s**. Single ordered short pair; performance differences are **not** causal evidence.
- ROCmFP4 FAST-v2 PLE16 + FAST Draft 4k, **Vulkan backend**: OFF/ON **2/2 OK**, 163 prompt/64 generated, accepted **34/56**, exact normalized output SHA-256 `d2dee2f658525d4044a1f479c2e5639f0e0fae875223ea5d94ef31506372cb3a`. PP **145.95 -> 273.39**, TG **26.69 -> 38.30 tok/s**. Single short pair, likewise not speed evidence.
- Both short pairs fully offload Main **49/49** and Draft **50/50** layers on Radeon 8060S Vulkan. With `LLAMA_MTP_SKIP_DENSE_INDEXER=1` and `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1`, logs verify DENSE omission on Draft and NOOP application to Target. Short ADLX high-load sample count was insufficient for a power classification; authoritative P-MODE stayed Performance.

### Long-context same-binary comparison

**Fixed conditions:** 96GB UMA, Vulkan0 Radeon 8060S, MTP DraftMax=2, f16 KV, batch=2048, ubatch=1024, threads=4, `-ngl 999`, `--fa auto`, temp=0, seed=1234, `--ignore-eos`, 512 generated tokens, P-MODE Performance. Hold **DENSE=1, NOOP=1, Vulkan QSA union=1, min-KV=32768** in all arms; only `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` switches 0/1. No flatten, diagnostics, or HIP backend. Absolute results are not controlled comparisons against the prior S6 isolated NOOP/union-OFF cohort.

| Model / context | Run order | OFF PP tok/s | ON PP tok/s | OFF TG tok/s | ON TG tok/s | PP gain | TG gain | Total time reduction |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: |
| IQ3 PLE16 / 64k | A1/B1/B2/A2 | 337.81 / 336.17 | 352.45 / 352.88 | 33.22 / 33.17 | 33.84 / 33.86 | **+4.65%** | **+1.97%** | **4.25%** |
| IQ3 PLE16 / 128k | A1/B1/B2/A2 | 297.88 / 297.81 | 318.85 / 317.79 | 29.61 / 29.60 | 30.49 / 30.46 | **+6.87%** | **+2.94%** | **6.29%** |
| ROCmFP4 FAST PLE16 / 64k (Vulkan) | A1/B1 only | 342.52 | 358.74 | 34.18 | 34.79 | **+4.74%** | **+1.78%** | **4.31%** |

IQ3 64k OFF/ON mean PP **336.99/352.665**, TG **33.195/33.850 tok/s**, total **198.749/190.303 s**. All four use exactly **61,789 input / 512 generated** tokens, accepted **301/419** (71.84%) and identical output SHA-256 `e87ab51f3b9c3811c3d001d63538fbeed98b8fbc2c4fe98516836bc1740eadbb`.

IQ3 128k OFF/ON mean PP **297.845/318.320**, TG **29.605/30.475 tok/s**, total **441.150/413.391 s**. All four use exactly **126,253 input / 512 generated** tokens, accepted **301/420** (71.67%) and identical output SHA-256 `67c8d243ba38f05b66f718a667ff9002da193cb04a7a97caf6fc33fdefdf11f1`. In particular, A1 and A2 PP differ by only **0.07 tok/s**; neither r5's 128k regression nor a late-run slowdown appears in this cohort.

ROCmFP4 64k OFF/ON use **61,789 input / 512 generated** tokens, accepted **295/431** (68.45%) and identical output SHA-256 `b5dc142e58e537c6eb34826342b20d4857d549ebec796235a3f5f43ed12c0ee9`. Mean is not a replicated ABBA: the committed `stageb-fp4-vulkan` plan intentionally contains only **two variants**. Treat the +4.74% PP/+1.78% TG as one favorable controlled pair, not a repeated confidence interval. The FP4 label describes quantization, **not ROCm execution**.

All **10/10 long runs** exit 0 and report `Status=OK`, verified runtime artifacts, the same executable SHA-256, consistent model path/size and input SHA-256 within each cohort, identical within-cohort output/acceptance, and no run exception. Full GGUF file SHA-256 was not captured in these manifests, so model-file byte identity is not independently proven here. P-MODE started and finished as Performance, with ADLX high-load `Performance-like` classification matching on every long run. IQ3 64k high-load GPU core averages **2831-2842 MHz**, VRAM **954-963 MHz**, power **115.6-116.7 W**; IQ3 128k core **2836-2844 MHz**, VRAM **937-945 MHz**, power **114.7-115.4 W**; FP4 64k core **2831-2837 MHz**, VRAM **956-963 MHz**, power **116.1-117.0 W**. No material P-MODE or clock degradation detected.

The output parity and native S5/S6 regression tests establish a strong *behavioral* Vulkan gate, but **Stage-B-specific active GPU graph FA pruning and bitwise Draft K/V cache parity were not directly measured in these runs**. Do not label those narrower claims as demonstrated. ROCm native build/test/smoke/64k remains open; keep the default OFF until final combined S8 judgment.

### Uploaded raw archives and SHA-256

| Gate | Archive | ZIP SHA-256 |
| --- | --- | --- |
| IQ3 4k smoke | `20261027-210036-843-cli-vulkan-b11903-ctx4096-e53c79b73d7b.zip` | `7db8e1f131d7875e039bf852a3e43b82083a7885ce64d05a877c2c3c7e4065ee` |
| FP4 4k smoke | `20261027-210634-246-cli-vulkan-b11903-ctx4096-f6e1438814e9.zip` | `ac66ad8340f7426a2e68be245035fc939564108ff5db1e2ad69ee07d0dad62ad` |
| IQ3 64k ABBA | `20261027-212624-068-cli-vulkan-b11903-ctx65536-8b16e6083bdc.zip` | `69bb4379dba8beba3e6f34e31d18a6ba4398124d8f1324e88e019c3969ca1936` |
| IQ3 128k ABBA | `20261027-220116-244-cli-vulkan-b11903-ctx131072-fa5fd7016bd0.zip` | `71db70c83d4068701f7fbac5769a2eea9e23f2236ea50e54a548f255d6a74c46` |
| FP4 64k A/B | `20261027-222005-798-cli-vulkan-b11903-ctx65536-c9282c263716.zip` | `171807070938eec69355910d033b934456c47f0b05c1086fb56badd1af62db01` |

**Vulkan decision:** S7-A Stage-B **PASS as opt-in integration candidate**, after same-binary IQ3 64k/128k ABBA and independent FP4 64k A/B with output parity. **Next:** branch S7-B from this documented state; add only Stage-B-scoped `mtp_eh_proj` flatten behind separate exact-1 OFF-by-default switch. Benchmark flatten OFF/ON with Stage-B ON in both arms, and retain C (both OFF) as a separate control. ROCm Stage-B and dedicated numerical K/V checks may be completed as bounded follow-ups without altering the S7-B source scope.
