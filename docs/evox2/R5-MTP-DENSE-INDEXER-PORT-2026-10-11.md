# r5 MTP-DENSE-001: isolated source port and Windows validation plan — 2026-10-11

**Source port completed; native policy/model tests PASS and r5 Vulkan 128k DENSE-only TG ABBA +15.52%.** This is a one-mechanism experiment, **not an approved integrated-release patch**. Source branch `investigation/r5-mtp-dense-indexer-20261011` starts from `investigation/r5-mtp-dense-compat-20261011` at `5492421d898ceb8a86d7594e26f5086d0371dd2d` (r5 Vulkan/ROCm MTP 64k/128k ABBA documented). The baseline r5 and all existing compiled binaries remain unchanged.

## Exact port scope

- From **r4** `src/llama-mtp-indexer-policy.h`: copy the **allocation-time, pure, fail-closed** policy; it checks requested `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, QWEN4EXP, MTP context, **exactly one NextN block**, valid layer/ratio-array bounds, an existing indexer, and **ratio0** at the NextN layer. A positive-ratio QSA draft is ineligible regardless of format/quantization, protecting future AgentionAI FP4 MTP support.
- In **r5** `src/llama-model.cpp`: add the policy header and conditional around the **existing** `llama_memory_hybrid_idx` construction in `create_memory`. When eligible/enabled, pass `filter_idx = nullptr` but **do not bypass the hybrid wrapper, dense attention KV, or recurrent state**. Log `MTP dense indexer: requested=... eligible=... omitted=... layer=... ratio=... reason=...` only when the environment variable is set. Default OFF.
- Port r4's unmodified `tests/test-mtp-indexer-policy.cpp` (automated independent policy test) and `tests/test-mtp-dense-indexer.cpp` (model-dependent state, A/B logits+hidden, accept 0/1/2, full/partial restore test). Register them in r5 `tests/CMakeLists.txt`. The model-dependent test is **built but not run by CTest automatically** because it requires the ~80GB main model and separate sidecar.
- **No** r4 `llama-memory-hybrid-idx.cpp/.h` backport. r5's newer `seq_cp` and k-pool state code, including `seq_rm` behavior, is unchanged. **MTP-NOOP-001 is NOT included.** No graph, backend shader, CPU sampling, CPP perf logger, model loader, QSA union, FP4, ROCm/HIP or MTP ON PP patch.

Source-inspection prerequisite: r5 `llama-memory-hybrid-idx.cpp` already checks null indexer in allocation/next/seq-remove/write/load and restricts `kpool_track` to a present indexer. This is **not enough to claim correctness** without native rollback and output tests.

## Windows native test results: 2026-10-11 (user-run on EVO-X2)

**Both first-stage gates PASS; 128k performance ABBA subsequently completed (see below).**

- **Policy:** `test-mtp-indexer-policy.exe` prints **`MTP indexer policy: PASS`** (direct user console report). This covers the fail-closed ratio0 policy with synthetic positive ratio etc; not a real compressed MTP GGUF.
- **Model/state:** `test-mtp-dense-indexer.exe` prints **`MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)`**. User-provided native-output capture `output.txt` in external chat attachment, **UTF-16 LE**, 10,683 decoded lines, ~1.5 MB. Captures new Windows Vulkan binary under `build-vulkan-r5-mtp-dense\bin\Release`, Radeon 8060S, main Unsloth PLE16 GGUF; executable/DLL SHA not included in this log (take from manifest for TG run).
- Runtime policy proof: OFF **`requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled`**; ON **`requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`**. Target indexer cache creation remains in the log; draft ON omits the unnecessary indexer. Tests cover no-op, append, accepted=0/1/2 rollback, FULL and PARTIAL restore.
- All eight same-trace A/B logits and hidden checks show **NMSE=0, max_abs=0**. Rollback/reference numerical tests passed NMSE<=1e-5. **Full-state** size OFF **15,688 bytes**, ON **12,508 bytes** (−3,180 B; −20.3% **saved-state size only**, not a statement about physical VRAM). PARTIAL_ONLY state 28 bytes in both arms.
- **Not a failure:** diagnostic-only *different batch partition* comparisons show `partition_matched=0` at tails 6 and 7 **in both A and B**, with identical NMSEs for A and B; these are expressly non-gating numerical diagnostics, not an indexer-policy A/B regression. Investigate partition sensitivity separately only if it affects real MTP output/acceptance.
- PowerShell 5.1 wraps the native stderr backend-load line in `NativeCommandError`; **the native test proceeds to final PASS**. This does not demonstrate an inference failure. Native exit code was not separately included in the capture, but the code prints PASS at the end.
- `ggml_vulkan: QSA grouped-union = off` in this native model/state gate: it uses **n_ctx=1024**, below the PP QSA union threshold and is not the 128k performance configuration.
- **Next gate**: same new r5 binary and main/draft pair, short real `llama-cli` smoke then **128k ABBA with MTP ON throughout, `LLAMA_MTP_SKIP_DENSE_INDEXER` OFF→ON→ON→OFF**, fixed output512, temp0 seed1234, union ON/min KV32768, f16 KV, no NOOP-001. Fail fast if benchmark wrapper reports missing/evidence-mismatch and collect condition/result/stdout/stderr/resource logs. Compare TG, accept rates, and generated text, not PP improvement.

**Do not call this r5 TG optimization validated until the paired 128k real-cli A/B is complete.**

## Windows Vulkan 128k: native DENSE-001 TG ABBA PASS — 2026-10-11

**DENSE-001 independently improves r5 Vulkan 128k MTP ON TG by +15.52% (same binary, ABBA).** This is a scoped TG result; MTP-NOOP-001 was **not** ported or enabled, and MTP ON PP optimization remains deferred.

- User archive `r5-mtp-dense-128k-abba-20261011-204709.zip`, SHA256 `6ddd1d7c78d35077c1454e7417d3925d4ec15ed61df4a2dcd1f0acf21780d18e`; 38 entries with all four `conditions.json`/`result.json`, stdout, stderr, resources and summary. Original ZIP retained outside Git.
- Runtime: EVO-X2 96GB UMA, Windows Vulkan Radeon8060S, b11566 / executable source `5b6a21557`, Clang20.1.8, executable SHA256 `ffad8bb05be1de30f0fc2be87772bef6f518a8d7af414bd430ba5e508e99df04`, runtime DLL digest `d5504292bfa98f562a84f6d0ffddae3e6ec36ba953ee1115aa64f85e7bf3dbf2`. Four runs **OK/exit0**, `RuntimeArtifactStatus=Verified`.
- Identical settings in four runs: main Unsloth PLE16 GGUF, MTP Unsloth Q8_0, 128k n_ctx=131072, 126,253 prompt tokens, input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, 512 generated tokens, seed1234 temp0 ignore-eos, DraftMax2 p-min0, f16 target+draft K/V, Vulkan QSA union ON/minKV32768. Only substantive `conditions.json` A/B difference: `LLAMA_MTP_SKIP_DENSE_INDEXER=0/1`; IDs/timestamps differ as expected.
- Evidence in stdout/stderr for every run: OFF `requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled`, ON `requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`. All statuses **Verified**, not just environment requests.

| Run | DENSE | PP tok/s (telemetry) | **TG tok/s** | TG elapsed sec | Accepted/generated |
| --- | --- | ---: | ---: | ---: | ---: |
| A1 | OFF | 303.60 | 23.44 | 21.79874 | 295/429 |
| B1 | ON | 304.38 | **27.07** | 18.87426 | 295/429 |
| B2 | ON | 303.89 | **27.04** | 18.89466 | 295/429 |
| A2 | OFF | 303.39 | 23.40 | 21.83934 | 295/429 |
| **OFF mean** | | **303.495** | **23.420** | **21.81904** | 68.765% |
| **ON mean** | | **304.135** | **27.055** | **18.88446** | 68.765% |

- **TG +3.635 tok/s / +15.52%; native 512-token generation elapsed −2.93458 sec / −13.45%.** PP +0.21% is incidental telemetry, not a PP-optimization result. On and off runs have tight intra-condition repeatability.
- **Generated output is identical across all four runs** after replacing only the final dynamic timing banner (`[ Prompt: ... | Generation: ... ]`); resulting normalized stdout SHA256 `557c7c9c991bc0880f56d5768f3cf97a4aaea147521b28503ccc63c223213402` in every run. MTP acceptance all runs **295/429 = 68.765%**. Therefore neither text nor acceptance divergence explains the speedup.
- Resource monitor peaks: `TargetGPULocal_GiB` OFF **88.674**, ON **88.611**; `TargetGPUDedicated_GiB` OFF **86.820**, ON **86.757**. System committed OFF peaks **101.963/101.929 GiB**, ON **101.878/101.849 GiB**; Windows GPU Local/UMA metrics must not be equated to exact physical VRAM savings. Reduction ~64MiB local, much smaller than relative TG change.
- r4 **256k +32.62%** is not directly comparable to current r5 **128k +15.52%** (different context and source). The unoptimized r5 128k OFF-dense mean **23.42** closely matches previous b11560 MTP-ON **23.475**. New ON-dense **27.055** is above previous different-build MTP-OFF **24.14** (illustrative +12.1%), but a **same-binary MTP OFF control is required to establish net MTP ON gain**.
- Research next gates: consider same new-binary MTP OFF 128k control; extend DENSE-only to 256k ABBA subject to memory/commit safety; ROCm independent tests. **Do not** introduce NOOP-001 or Agention FP4 model-format changes into this A/B. Preserve the tested code on the experiment branch until integration review.

## Console-only CJK display corruption and safe logging fix — 2026-10-11 late evening

**Observed:** The PowerShell console copy of model output showed duplicated/dropped Japanese characters in 32k smoke input preview, 128k A2 (DENSE OFF) and 256k safety (DENSE ON). The **same run's captured `stdout.log` and combined `output.log` generation text were intact**. This refines the earlier "output quality normal" statement: it applies to the **saved raw capture**, not the visibly garbled console playback. Since both DENSE states and multiple context sizes show it, the symptom is **not evidence of MTP-DENSE-001 or 256k inference corruption**. Exact terminal/host defect remains unproven.

**Correction:** `tools/evox2/benchmark/Measure-LlamaCli.ps1` no longer reads the whole `stdout.log` into a single string and executes `[Console]::WriteLine($stdoutText)` after the run. The console prints only the saved `stdout.log` path; inspect it with Notepad or a text editor. This is a **reporting-only change**, with **no modifications** to `Start-Process -RedirectStandardOutput`, `Start-Process -RedirectStandardError`, combined `output.log` construction, parser, timings, MTP/NOOP evidence detection, native DLL/executable hashes, tests or CMake builds.

**Scope:** The same benchmark script is used by Vulkan and ROCm. Pull this branch to update the script; **no recompile is needed**, including if the ROCm binary has already been built. A post-pull `GitCommit` may be newer than `ExecutableCommit` because reporting/docs changed since building, but unchanged runtime binaries must still pass the manifest/digest check; do not misattribute a binary commit from source checkout identity.

**Verification:** Static change review completed. A live PowerShell 5.1 console smoke after the update is still required to confirm that no garbled replay appears. Prior saved 128k DENSE TG +15.52% and accepted/output identity remain valid.

## ROCm native model test + 32k smoke — 2026-10-11 22:44 JST

**ROCm model-dependent state/rollback correctness: PASS. ROCm 32k real MTP ON DENSE=1 smoke: OK. ROCm 128k DENSE ABBA: not yet measured.**

Artifacts supplied by EVO-X2 operator (not stored in Git):
- Model test `rocm-mtp-dense-test.txt`, SHA256 `9bb64303e40b88655e4796013fb39f56ec837e72fa75055268374930c870036b`, UTF-16 LE, 10,747 lines. Terminal line: `MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)`; no `MTP dense indexer: FAIL`.
- Smoke ZIP `r5-mtp-dense-rocm-128k-smoke-20261011-224432.zip`, SHA256 `9ddb7fb279e21b28d9e7815c7febf3d852c52f99109778b81a27eb56a4217bce`, 11 entries containing one 32k run with conditions/result/stdout/stderr/resource logs. Filename indicates the intended 128k test series, **not a 128k smoke**.
- **Model-test proof:** startup log OFF `requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled`; ON `requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`. For all 8 A/B state checks, both logits and hidden (`16 A/B metrics`) were exact, **NMSE=0,max_abs=0**. All accept-0/1/2, full/partial restore same-arm comparisons were exact. Full saved state OFF **15,688 B**, ON **12,508 B**; partial state 28 B both. As in Vulkan, **diagnostic-only** alternate bulk-vs-split partition at tails 6 and 7 shows `partition_matched=0` for **both** OFF and ON. ROCm A/B has identical diagnostic NMSE in both arms; not a gated DENSE-001 failure. Batch partition numeric stability is a separately tracked correctness topic, not a causal DENSE regression.
- The model test opens ROCm0 AMD Radeon8060S (`gfx1151`) using `ggml-hip.dll`; Windows PowerShell 5.1 starts the capture with `NativeCommandError` for backend stderr info but the test eventually prints PASS. The **separate simple `test-mtp-indexer-policy.exe` ROCm execution transcript was not included**; do not claim it was independently observed from this attachment. The same policy implementation was validated on Vulkan and is included in the tested ROCm model-dependent path.
- Smoke: `Status=OK,ExitCode=0,RuntimeArtifactStatus=Verified`; **b11566 / Clang23.0.0 ROCm**; binary executable SHA256 `b0602a7983459bc6c0f32e662bc391164c1c9b7c9314aaea4acca4238da26b62`, runtime DLL digest `a13befc7328e321b7a438e71406b3a58c2c34a0f48c0e61f2b8bdc1cbecfc525`, embedded source `5b6a21557`; reporting-script Git checkout `5fd2a4db` is newer and **not the compiled code**, which build manifest verifies.
- Smoke settings: Unsloth PLE16 target + Unsloth Q8_0 draft, n_ctx32768, **29,557 prompt tokens**, **64 generated tokens**, temp0 seed1234, draft max2 pmin0, f16 target/draft KV; ROCm backend default, **no Vulkan union**, **no NOOP patch**. Candidate evidence `Verified`: `requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`. **PP 438.50 tok/s**, **TG 32.91 tok/s**, **MTP draft acceptance 39/48 (81.25%)**; these 64-token smoke rates do **not** quantify DENSE speedup.
- ROCm smoke resource maxima: `Committed_GiB` **96.554**, commit limit **127.647 GiB**; `TargetGPULocal_GiB` **56.670**; `TargetGPUDedicated_GiB` **55.071**. Resource counters are sampling-based and the ROCm-reported `VRAM 110456 MiB` must not be confused with BIOS UMA 96GB. No native crash or out-of-memory errors in this smoke.
- The generated Japanese `stdout.log` is recorded; short 64-token generation ends mid-sentence by design, with no duplicated-character corruption in the saved file. The measure-script change at `5fd2a4db` disables full console replay; source output capture was unchanged. This is **not a longer-response quality verdict**.

**Decision:** Proceed to **ROCm 128k MTP ON-only DENSE OFF→ON→ON→OFF ABBA** using exactly the above executable and same 126,253-token input used for Vulkan's 128k DENSE ABBA. Confirm the performance changes against the ROCm OFF arm in **this same new binary**, and match acceptance and generated text before attributing the gain to DENSE. **Do not** infer an ROCm 128k gain from the 32k smoke alone.

## ROCm 128k DENSE-001 MTP ON TG ABBA — 2026-10-11 22:52–23:31 JST

**Measured ROCm TG improvement +17.42% under same-binary A/B; unlike Vulkan, output text and draft acceptance are NOT identical across runs.** Treat this as a strong performance signal rather than output-identical causality proof. This finding does **not** mean that DENSE itself caused text differences: each OFF repeat differs from the other OFF repeat, and each ON repeat also differs from the other ON repeat.

Archive: `r5-mtp-dense-rocm-128k-abba-20261011-225255.zip`, **SHA256 `9371f4131eac0f3189374dbccf2f72ccb45b6da08fde6d45a5f78d47327c9edf`**, 38 members, four directories containing condition/result/stdout/stderr/resource logs, archived summary, run-info (ZIP is retained in the user's external artifacts, not in Git).

**Runtime identity and conditions:** Windows EVO-X2 96GB UMA label, ROCm/HIP `ggml-hip.dll` for Radeon8060S/gfx1151, Clang23.0.0, b11566, `llama-cli.exe` SHA256 `b0602a7983459bc6c0f32e662bc391164c1c9b7c9314aaea4acca4238da26b62`, DLL/artifact digest `a13befc7328e321b7a438e71406b3a58c2c34a0f48c0e61f2b8bdc1cbecfc525`, executable/build source `5b6a21557f5d8943527e18bca9809fe74b825f38`. Script checkout at testing `5fd2a4db` (newer reporting script, *not* recompiled source). All 4: `Status=OK`, `ExitCode=0`, `RuntimeArtifactStatus=Verified`, `MtpDenseIndexerEvidence.Status=Verified`.

Same main/draft GGUF as Vulkan, **126,253 prompt tokens**, n_ctx=131072, `nlp-survey-ch3-d15-b1.txt` SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, output512, `--temp 0 --seed 1234 --ignore-eos`, `--spec-draft-n-max 2 --spec-draft-p-min 0`, f16 target+draft KV, `-b 2048 -ub 1024 -t 4 -tb 4 -ngl 999 -ncmoe 0 --ctx-checkpoints 0t`. No Vulkan-only QSA union environment, and no NOOP-001. Recursive `conditions.json` comparison A1 vs B1 shows only the two representations of `LLAMA_MTP_SKIP_DENSE_INDEXER` switch plus auto-generated timestamps/run IDs/condition IDs. No other meaningful A/B setting difference. OFF policy marker `requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled`; ON marker `requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block`.

| Order | Arm | PP tok/s (telemetry) | **TG tok/s** | TG elapsed ms | Draft accepted/generated | Acceptance |
|---|---|---:|---:|---:|---:|---:|
| A1 | OFF | 275.45 | 18.40 | 27778.20 | 297/427 | 69.555% |
| B1 | ON | 274.59 | **21.39** | 23893.34 | 298/424 | 70.283% |
| B2 | ON | 275.44 | **21.00** | 24338.15 | 297/428 | 69.393% |
| A2 | OFF | 274.74 | 17.70 | 28863.37 | 299/424 | 70.519% |
| **OFF mean** | | **275.095** | **18.050** | **28320.785** | 298/425.5 | **70.037%** |
| **ON mean** | | **275.015** | **21.195** | **24115.745** | 297.5/426 | **69.838%** |

**Measured effect:** TG **+3.145 tok/s / +17.42%**; 512-token generation eval time **−4205.04 ms / −14.85%** (means). Two ONs faster than both OFFs. PP means **−0.03%**, an incidental observation outside current PP investigation.

**Quality/reproducibility caveat:**
- The four generated Japanese texts (after removing the common prompt-preview and timing banner) have **four distinct SHA256 hashes**; **even A1 and A2 (both OFF) differ**, as do B1/B2 (both ON). Excerpt content is topical and coherent in all four, with no duplicated-character corruption, but no full output-identical assertion is possible. Draft acceptance likewise varies **69.393–70.519%**. Unlike Vulkan's exact-output ABBA, variation means attribution is less strict, even though the ON/OFF timing separation is larger than in-arm variability.
- Neither temp0 nor fixed seed guarantees bitwise identical ROCm/GPU outputs; **the exact source of ROCm nondeterminism remains uninvestigated**. This observation does **not** establish a DENSE-specific correctness regression; the OFF-OFF repeat also diverges. Model-dependent test earlier passed same-trace OFF/ON hidden/logits NMSE=0, but only short context, not 128k runtime output equivalence.
- The `stdout.log` buffers contain a known invalid UTF-8 byte in the *prompt-preview* truncation at `3.2� ... (truncated)` on each run; the **actual generated response** portion is valid UTF-8, natural Japanese with **zero U+FFFD**. This is unrelated to the repaired console replay issue and must not be described as corrupt model generation.

**Resource peaks** across each arm (Windows counters from sampled `resources.csv`):
- GPU Local OFF **60.895 GiB** vs ON **60.832 GiB**, dedicated OFF **58.873 GiB** vs ON **58.810 GiB** (~64 MiB sampled difference); GPU Shared both **2.022 GiB**. Windows GPU Local/UMA accounting is not the exact physical dedicated VRAM allocation.
- System committed OFF max **100.859 / 100.845 GiB**, ON max **100.818 / 100.776 GiB**, commit limit **127.647 GiB**. No OOM or backend error in supplied logs.
- End-to-end run durations A1 **530.571s**, B1 **529.146s**, B2 **655.873s**, A2 **538.580s**. These include non-generation time and initialization and must not be treated as TG; B2 longer wall-clock run despite similar PP and TG.

**Cross-backend reference, same input but different compiled backend:**
- **Vulkan 128k** DENSE OFF **23.420**, ON **27.055**, **+15.52%**, identical acceptance/output in four runs.
- **ROCm 128k** DENSE OFF **18.050**, ON **21.195**, **+17.42%**, *nonidentical* acceptance/output even in same-arm repeats.
- Do **not** ascribe the absolute Vulkan/ROCm speed difference solely to DENSE, as backend implementation and runtime environment differ.

**Disposition:** DENSE-001 TG 128k gain is established separately in both backends, with stronger output-equivalence proof for Vulkan. Preserve this as a single-patch measurement, no NOOP-001. The user's next planned step is **nighttime Vulkan 256k DENSE OFF→ON→ON→OFF**; 256k ON solo safety previously completed at TG21.03tok/s, GPU Local94.56GiB and system commit107.9/127.65GiB. Continue resource monitoring and inspect outputs from saved `stdout.log`, not console copies. After overnight run, assess 256k gains; the ROCm temp0 repeatability question may be addressed later in a separate targeted investigation.

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

**Validation status as of this update:** Windows policy/model-state tests PASS; r5 Vulkan 128k DENSE-only MTP-ON TG ABBA **+15.52%** validated. 256k and ROCm pending; integrated-release acceptance not decided.
