# r6 S5 / MTP-DENSE-001: upstream audit, isolated source port and fixed validation gate

- **Date:** 2026-10-26 JST
- **Branch:** `r6/mtp-dense-20261026`, based on the documented S4 `r6/vulkan-qsa-union-20261025` state. Frozen upstream b11870, without refreshing the upstream base.
- **Status (updated 2026-10-26):** Windows Vulkan b11898 build **PASS**, independent policy test **PASS** (user report). The first native model-state test stopped on an r6 test-harness API mismatch; a one-line **test-only** compatibility correction has been applied, but **the corrected Windows native test and all MTP TG measurements remain unverified**.
- **Fixed order:** S5 MTP-DENSE-001 only. After a PASS, proceed to MTP-NOOP-001 on a separate branch; do not combine changes or add Stage-B/flatten yet. No 256k tests in S1-S6.

## 1. Audit against b11870 before porting

The current r6 `llama_model::create_memory()` already has Qwen4Exp-aware hybrid/indexer allocation in `src/llama-model.cpp`. For `LLAMA_CONTEXT_TYPE_MTP`, it selects only the NextN layer via `filter_attn` and `filter_idx` callbacks, and passes them to `llama_memory_hybrid_idx`. `src/llama-memory-hybrid-idx.cpp` already makes `mem_idx` optional when **`filter_idx == nullptr`**, with null guards on memory/state operations. Thus the **null-indexer mechanism is upstream**, and neither hybrid cache classes nor rollback internals require an r5 replacement.

However, b11870 still installs the MTP indexer filter whenever `hparams.indexer_head_size > 0`, without testing `dsv4_compress_ratios[NextN]`. A single **ratio-zero dense NextN block** does not need a QSA indexer cache. The existing selection is based on tensor metadata, not the per-Draft ratio, so upstream has **not automatically implemented MTP-DENSE-001**. The S3 Qwen4Exp MTP ratio-zero pool guard is already present and remains untouched.

Source behavior to preserve:

| Context | Ratio / metadata | DENSE OFF (or unset) | DENSE ON |
| --- | --- | --- | --- |
| Qwen4Exp Target | Any | Original indexer | **Unchanged** |
| Qwen4Exp, one NextN Draft | `ratio=0`, indexer present | Original indexer | **Omit unused indexer cache only** |
| Qwen4Exp MTP Draft | `ratio>0` | Original indexer | **Keep indexer** (fail closed) |
| Other architecture, no indexer or invalid NextN metadata | Any | Original behavior | **Unchanged** |

## 2. Minimal r6 port

Donor: r5 `investigation/r5-mtp-dense-indexer-20261011`, implementation commit `9d0d4ad36` and validated b11566 source `5b6a21557`. [r5 DENSE implementation and complete results](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md) documents separate 64/128/256k TG gains, including Vulkan 128k **+15.52%** and ROCm 128k **+17.42%**. Those numbers **are historical motivation, not r6 measurements**.

Changes scoped to S5:

1. Add the r5 fail-closed `src/llama-mtp-indexer-policy.h` pure predicate. Only exact `LLAMA_MTP_SKIP_DENSE_INDEXER=1` enables the omission; the default is OFF.
2. In the existing Qwen4Exp MTP `llama_memory_hybrid_idx` branch of `src/llama-model.cpp`, evaluate the single NextN layer's compress ratio before allocation. If eligible and enabled, pass `filter_idx=nullptr` and keep the entire hybrid wrapper, normal attention KV, recurrent state and NextN path. Log the requested/eligible/omitted/layer/ratio/reason fields when the variable is set.
3. Add the independent `tests/test-mtp-indexer-policy.cpp` and model-dependent `tests/test-mtp-dense-indexer.cpp` from r5 and register both build targets. The latter checks OFF/ON logits and hidden states, full/partial checkpoint sizes, no-op, append, speculative rejection/acceptance 0/1/2 and rollback; it **must not** auto-run as a generic CTest because it requires the real main and Draft GGUFs.
4. Add a fixed matrix: [`qwen38-r6-s5-mtp-dense.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s5-mtp-dense.psd1). Same source/binary per backend, MTP ON in both arms, union OFF, NOOP unset, temperature 0, seed 1234, `--ignore-eos`, 512 output tokens. Only DENSE 0/1 changes within each ABBA block.

**Not changed:** QSA union code or default, MTP compatibility, `llama-memory-hybrid-idx` methods, GGUF readers, Vulkan/HIP kernels, source graph, sampler, NOOP/Stage-B/flatten. No attempt to reclaim unrelated positive-ratio indexer state.

### Local non-GPU checks (developer environment)

- `g++ -std=c++17 -Wall -Wextra -Werror tests/test-mtp-indexer-policy.cpp` built and the executable printed **`MTP indexer policy: PASS`**.
- `g++ -std=c++17 -fsyntax-only` succeeded for the new model-dependent test source and modified `src/llama-model.cpp` with the repository headers.
- These checks **do not** replace native Windows Clang build, GPU inference, saved-state regression or long-context A/B.

## 3. Windows build and acceptance gates (run in order)

### First Windows feedback: build PASS, old test input ABI STOP, test-only correction

User-supplied `(vulkan-mtp-dense)evox2-build.json` identifies **b11898**, commit `45322c0423a08bc1632cf8eee978352fff0691bd`, clean branch `r6/mtp-dense-20261026`, `BuildIdentity=Verified`, Clang20.1.8, Radeon8060S Vulkan0, and both test targets successfully built. `llama-cli.exe` SHA-256: `c5eb0ce90f89bfcaa61ef63570b04c719532a0e1555c96663ed90668c0875fa2`; `ggml-vulkan.dll` SHA-256: `2680fccd120afe145cdd29b37da7a344fae72fcff5ddec92d0cf94844949a3bf`. Version and device probes both exited 0. The `cl.exe` toolchain probe exit code 2 is due to invoking CL without a source filename, not an actual Clang build error.

The user confirmed `test-mtp-indexer-policy.exe` **PASS**. The first `test-mtp-dense-indexer.exe` log (`貼り付けたテキスト（1）(20261026-020912).txt`) confirms **both policy decisions were correct** before its first Draft trace decode:

```text
create_memory: MTP dense indexer: requested=0 eligible=1 omitted=0 layer=48 ratio=0 reason=disabled
create_memory: MTP dense indexer: requested=1 eligible=1 omitted=1 layer=48 ratio=0 reason=dense_single_block
set_token_embd: embedding size mismatch, got 1 rows x 10240 = 10240, expected 2560 or 2560
common/common.cpp:2262: get_sub_batch: failed to set the embedding of token 5328 at index 0
```

This is a **test-harness API mismatch**, not observed evidence of a DENSE cache failure. r5's model test used `common_batch::set_embd` to pass the 10240-wide MTP hidden vector, but b11870's `common_batch::set_embd` routes to `llama_batch_ext_set_embd_token` (expects the 2560-wide *token embedding*). Current upstream's actual MTP speculative decoder uses `common_batch::set_embd_state` to route the same hidden vector through `llama_batch_ext_set_embd_state` (`common/speculative.cpp`). The isolated S5 model test now likewise calls **`batch.set_embd_state`**, leaving every source inference/cache/policy path unchanged. Local C++17 syntax check after correction PASS.

**Required retry:** pull the follow-up S5 commit, then rebuild **only `test-mtp-dense-indexer`** in the existing `build-vulkan-r6-mtp-dense` directory. Do not discard the known-good b11898 source/binaries or re-run broad backend tests. Run that native test again with the same main/Draft paths; do **not** advance to 4k smoke or long-context ABBA until the final model-state/rollback PASS is observed. Later changes, if any, must be separately identified in test manifests; the original b11898 build evidence stays recorded as historical.

Keep S3 b11889 and S4 b11895 binaries untouched. After the S5 branch is published, update the **same r6 source checkout** and use new build directories:

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git switch r6/mtp-dense-20261026
git pull --ff-only
git status --short --branch

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-mtp-dense `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -ExtraTargets @('test-mtp-indexer-policy', 'test-mtp-dense-indexer') `
    -Parallel 4
```

**Gate 5a: build and policy.** Save the build JSON and confirm clean BuildIdentity/commit, Radeon 8060S Vulkan0, generated test executables and proper DLLs. Do not run the broad `FLASH_ATTN_EXT` backend test. Then:

```powershell
$bin = (Resolve-Path .\build-vulkan-r6-mtp-dense\bin\Release).Path
& (Join-Path $bin 'test-mtp-indexer-policy.exe')
if ($LASTEXITCODE -ne 0) { throw 'S5 policy gate failed' }
```

**Gate 5b: model-dependent state and rollback test.** Point to the **actual** Unsloth PLE16 target and matching Unsloth Q8_0 MTP Draft. Do not use FP4 Draft for this test yet:

```powershell
$mainModel  = '<full path to Unsloth IQ3 PLE16 main GGUF>'
$draftModel = '<full path to matching Unsloth Q8_0 MTP GGUF>'
& (Join-Path $bin 'test-mtp-dense-indexer.exe') -m $mainModel -md $draftModel -ngl 999
if ($LASTEXITCODE -ne 0) { throw 'S5 model/state/rollback gate failed' }
```

Required output: `MTP dense indexer: PASS (append, no-op, accept 0/1/2, full/partial restore, A/B logits and hidden)`. Require the draft startup markers **OFF `requested=0 eligible=1 omitted=0 ... ratio=0`** and **ON `requested=1 eligible=1 omitted=1 ... ratio=0`**, target indexer retained, and smaller FULL state with identical PARTIAL_ONLY state size. Treat the test's separately labeled different-batch-partition diagnostic as non-gating, exactly as in the r5 record.

**Gate 5c: short real `llama-cli` MTP smoke.** Using the same S5 Vulkan binary, IQ3 PLE16 + Q8_0 Draft, start with 4k and DraftMax2. MTP must be ON in both OFF/ON indexer arms; keep union OFF and NOOP unset. Both runs need normal Japanese output, main 49/49 + Draft 50/50 GPU offload, positive acceptance, `Status=OK`, Performance P-MODE, and the explicit requested/eligible/omitted logs. If either fails, **STOP before the long matrix**. Then repeat an FP4 FAST target+FP4 Draft short smoke to verify that the FP4 metadata and loading remain compatible; if its MTP ratio is positive, the fail-closed policy must keep the indexer and an FP4 speed A/B is not meaningful.

**Gate 5d: MTP TG A/B.** In the ignored `tools/evox2/benchmark/configs/local.psd1`, add:

```powershell
S5Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-mtp-dense\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

Run each group independently, with `-PlanOnly` immediately before starting. First IQ3 Vulkan 64k ABBA, inspect result/acceptance/resource logs, then 128k ABBA. Do not begin 128k if P-MODE, state, output or GPU allocation is abnormal:

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"
$plan  = "$bench\configs\qwen38-r6-s5-mtp-dense.psd1"
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local `
    -OnlyJob s5-iq3-vulkan -OnlyCase 64k -MaxRuns 4 -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local `
    -OnlyJob s5-iq3-vulkan -OnlyCase 64k -MaxRuns 4
```

Substitute `-OnlyCase 128k` only after 64k PASS. Record TG, PP, PP+TG, draft accepted/proposed, generated-output identity, policy evidence, n_ctx/input SHA, binary hash and ADLX P-MODE. DENSE is a **TG-oriented optimization**; do not claim an improvement from cross-binary S3 or historical r5 rates.

**ROCm and FP4 follow the fixed G5 plan:** prepare a **new** `build-rocm-r6-mtp-dense` using `Build-ROCm.ps1` with TheRock **10.0** build/runtime DLL provenance (no `-RunBackendTest`), test policy/model-state and 4k/short MTP, then IQ3 ROCm 64k and 128k ABBA using `-OnlyJob s5-iq3-rocm` and a new `S5ROCm` key. ROCm temperature-zero text/acceptance can vary between same-arm repetitions; evaluate coherent output, state test and TG distribution, not byte equality. Finally run FP4 FAST PLE16 **Vulkan 64k OFF/ON only** (`-OnlyJob s5-fp4-vulkan`), provided FP4 Draft was eligible in the short gate. No 128k FP4 DENSE matrix and no 256k in S5.

## 4. Decision and handoff

- **PASS:** policy model-state/rollback, 4k compatibility, actual `omitted=1` on eligible Draft, positive acceptance, and useful same-binary TG gain with no material PP/output regression. Keep default OFF pending S7 combined evaluation.
- **DEFER:** gain at most around 3%, ambiguous A/B noise or FP4 Draft `ratio>0` ineligible. Do not force eligibility or expand unrelated benchmarks; at most one targeted repeat of a disputed IQ3 ABBA as specified in the integration plan.
- **STOP:** nonzero model-state test, missing eligible startup evidence, bad GPU offload, collapsed output, MTP rollback mismatch, repeated crash or resource anomaly. Preserve logs and return to the independent next patch only after recording the decision.

On closing S5 DENSE, update [r6 integration execution plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md). Next isolated stage is **MTP-NOOP-001**, independent from DENSE and without Stage-B/flatten; final combined optimization decisions belong to S7.
