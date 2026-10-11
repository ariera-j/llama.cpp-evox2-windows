# r5 MTP-DENSE-001: isolated source port and Windows validation plan — 2026-10-11

**Source implementation: prepared / NOT Windows-built or benchmark-validated.** This is a one-mechanism experiment, **not an approved integrated-release patch**. Source branch `investigation/r5-mtp-dense-indexer-20261011` starts from `investigation/r5-mtp-dense-compat-20261011` at `5492421d898ceb8a86d7594e26f5086d0371dd2d` (r5 Vulkan/ROCm MTP 64k/128k ABBA documented). The baseline r5 and all existing compiled binaries remain unchanged.

## Exact port scope

- From **r4** `src/llama-mtp-indexer-policy.h`: copy the **allocation-time, pure, fail-closed** policy; it checks requested `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, QWEN4EXP, MTP context, **exactly one NextN block**, valid layer/ratio-array bounds, an existing indexer, and **ratio0** at the NextN layer. A positive-ratio QSA draft is ineligible regardless of format/quantization, protecting future AgentionAI FP4 MTP support.
- In **r5** `src/llama-model.cpp`: add the policy header and conditional around the **existing** `llama_memory_hybrid_idx` construction in `create_memory`. When eligible/enabled, pass `filter_idx = nullptr` but **do not bypass the hybrid wrapper, dense attention KV, or recurrent state**. Log `MTP dense indexer: requested=... eligible=... omitted=... layer=... ratio=... reason=...` only when the environment variable is set. Default OFF.
- Port r4's unmodified `tests/test-mtp-indexer-policy.cpp` (automated independent policy test) and `tests/test-mtp-dense-indexer.cpp` (model-dependent state, A/B logits+hidden, accept 0/1/2, full/partial restore test). Register them in r5 `tests/CMakeLists.txt`. The model-dependent test is **built but not run by CTest automatically** because it requires the ~80GB main model and separate sidecar.
- **No** r4 `llama-memory-hybrid-idx.cpp/.h` backport. r5's newer `seq_cp` and k-pool state code, including `seq_rm` behavior, is unchanged. **MTP-NOOP-001 is NOT included.** No graph, backend shader, CPU sampling, CPP perf logger, model loader, QSA union, FP4, ROCm/HIP or MTP ON PP patch.

Source-inspection prerequisite: r5 `llama-memory-hybrid-idx.cpp` already checks null indexer in allocation/next/seq-remove/write/load and restricts `kpool_track` to a present indexer. This is **not enough to claim correctness** without native rollback and output tests.

## Windows native test results: 2026-10-11 (user-run on EVO-X2)

**Both first-stage gates PASS; performance ABBA pending.**

- **Policy:** `test-mtp-indexer-policy.exe` prints **`MTP indexer policy: PASS`** (direct user console report). This covers the fail-closed ratio0 policy with synthetic positive ratio etc; not a real compressed MTP GGUF.
- **Model/state:** `test-mtp-dense-indexer.exe` prints **`MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)`**. User-provided native-output capture `output.txt` in external chat attachment, **UTF-16 LE**, 10,683 decoded lines, ~1.5 MB. Captures new Windows Vulkan binary under `build-vulkan-r5-mtp-dense\bin\Release`, Radeon 8060S, main Unsloth PLE16 GGUF; executable/DLL SHA not included in this log (take from manifest for TG run).
- Runtime policy proof: OFF **`requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled`**; ON **`requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`**. Target indexer cache creation remains in the log; draft ON omits the unnecessary indexer. Tests cover no-op, append, accepted=0/1/2 rollback, FULL and PARTIAL restore.
- All eight same-trace A/B logits and hidden checks show **NMSE=0, max_abs=0**. Rollback/reference numerical tests passed NMSE<=1e-5. **Full-state** size OFF **15,688 bytes**, ON **12,508 bytes** (−3,180 B; −20.3% **saved-state size only**, not a statement about physical VRAM). PARTIAL_ONLY state 28 bytes in both arms.
- **Not a failure:** diagnostic-only *different batch partition* comparisons show `partition_matched=0` at tails 6 and 7 **in both A and B**, with identical NMSEs for A and B; these are expressly non-gating numerical diagnostics, not an indexer-policy A/B regression. Investigate partition sensitivity separately only if it affects real MTP output/acceptance.
- PowerShell 5.1 wraps the native stderr backend-load line in `NativeCommandError`; **the native test proceeds to final PASS**. This does not demonstrate an inference failure. Native exit code was not separately included in the capture, but the code prints PASS at the end.
- `ggml_vulkan: QSA grouped-union = off` in this native model/state gate: it uses **n_ctx=1024**, below the PP QSA union threshold and is not the 128k performance configuration.
- **Next gate**: same new r5 binary and main/draft pair, short real `llama-cli` smoke then **128k ABBA with MTP ON throughout, `LLAMA_MTP_SKIP_DENSE_INDEXER` OFF→ON→ON→OFF**, fixed output512, temp0 seed1234, union ON/min KV32768, f16 KV, no NOOP-001. Fail fast if benchmark wrapper reports missing/evidence-mismatch and collect condition/result/stdout/stderr/resource logs. Compare TG, accept rates, and generated text, not PP improvement.

**Do not call this r5 TG optimization validated until the paired 128k real-cli A/B is complete.**

## Windows build and first tests (operator-run; no hardware in this session)

From Windows PowerShell 5.1, in the **new source checkout/branch**; keep the validated `build-vulkan-r5-mtp-compat` untouched. Paths are examples; use your installed LLVM/Vulkan SDK.

```powershell
git status --short --branch
git rev-parse HEAD

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r5-mtp-dense `
  -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -ExtraTargets @('test-mtp-indexer-policy','test-mtp-dense-indexer') `
  -Parallel 4
```

New binary directory (after successful build): `.\build-vulkan-r5-mtp-dense\bin\Release`. The command relies on the r5 build helper's tests-ON configuration. If the CLI baseline test/executable targets are missing, stop and report the build log; do not copy old DLLs from a different build.

**Gate 1: policy test** (model independent):

```powershell
$bin = (Resolve-Path '.\build-vulkan-r5-mtp-dense\bin\Release').Path
& (Join-Path $bin 'test-mtp-indexer-policy.exe')
if ($LASTEXITCODE -ne 0) { throw 'Policy test failed' }
```

Required terminal line: `MTP indexer policy: PASS`. Negative policy coverage includes other architectures, target context, 0 or multiple NextN heads, missing/bad ratio metadata, missing indexer and **positive ratio**, plus invalid environment values.

**Gate 2: native model-dependent test**. Substitute the actual working main/draft GGUF paths; check disk and memory headroom. Use model **Unsloth PLE16 + matching Q8_0 sidecar** first, **not AgentionAI FP4**:

```powershell
$main = 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf'
$draft = 'D:\models\mtp-Qwen3.8-Flash-Next-Q8_0.gguf'
& (Join-Path $bin 'test-mtp-dense-indexer.exe') -m $main -md $draft -ngl 999
if ($LASTEXITCODE -ne 0) { throw 'Model/state/rollback test failed' }
```

Required terminal line: `MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)`. Confirm startup logs show `requested=0 eligible=1 omitted=0` and `requested=1 eligible=1 omitted=1` for the draft, **target indexer retained**, and recorded full-state size decreases with omission. This test has r4 origins; **r5 compilation and runtime compatibility remain unverified** until execution.

**Gate 3: short real MTP CLI A/B**. With the same freshly built `llama-cli.exe`, record compiler/runtime digest and logs. Run 32k short then 128k long input; keep MTP ON and change only `LLAMA_MTP_SKIP_DENSE_INDEXER` **0→1→1→0**, `--spec-draft-n-max 2 --spec-draft-p-min 0 -n 512 --ignore-eos --temp 0 --seed 1234`, f16 target+draft K/V, `GGML_VK_QSA_UNION=1`, threshold `32768`, `GGML_VK_PERF_LOGGER` unset. Compare TG, acceptance, and generated response. With MTP ON on **both** arms, this is **not** an MTP OFF/ON ABBA and must not be labeled that way.

Use existing `tools/evox2/benchmark/Measure-LlamaCli.ps1` only if the selected plan **preserves** `LLAMA_MTP_SKIP_DENSE_INDEXER` from the variant; older r4 plans intentionally clear inherited candidate settings. A dedicated r5 plan/runner or explicit tested environment handling should be established **before** an unattended 128k matrix.

**Next:** if the first 128k A/B works and preserves rollback, expand to 256k with memory monitoring and ROCm; decide independently whether MTP-NOOP-001 merits a second opt-in patch. Do not merge into mainline or declare r5 speed gain until real Windows logs are reviewed.

## AgentionAI forward compatibility

The AgentionAI FP4 MTP draft was previously tested successfully in the dedicated fork through 256k (user's Qiita article), **not with upstream-native r5**. Quantization does not change the policy; actual MTP ratio and tensor presence do. **For ratio > 0 the indexer must remain allocated even when the switch is ON**. First integrated-release GGUF compatibility and HIP/Vulkan custom FP4 kernel verification remain separate gates: [interaction review](R5-MTP-AGENTION-FP4-INTERACTION-2026-10-11.md).

## Historical measured motivation (r4 only)

- r4 Vulkan 256k, MTP **ON in both arms**: indexer omission OFF vs ON **15.220→20.185 tok/s** (**+32.62% TG**), output/acceptance matched, PP effectively unchanged. [r4 ABBA](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
- r5 current baseline 128k Vulkan MTP ON **23.475 tok/s** vs MTP OFF **24.140 tok/s**, and matched r2 b10813 MTP ON **25.625 tok/s** vs OFF **22.015 tok/s**. These are distinct version-level controls, **not a forecast** for the new toggle. See [r2/r5 TG recheck](R5-MTP-TG-R2-R5-RECHECK-2026-10-11.md).

**Validation status at commit:** static source review only; native builds, policy CTest, model/state/rollback tests and model TG A/B pending user-side Windows execution.
