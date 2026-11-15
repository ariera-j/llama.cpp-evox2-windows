# r6 MTP-NOOP-001 S6: implementation and Windows verification - 2026-10-26

- **Branch:** `r6/mtp-noop-20261026`, forked from `r6/mtp-dense-20261026` (`7c819cffb`, upstream baseline b11870).
- **Scope:** target-QSA no-op invalidation only. No upstream refresh, Stage-B, flatten, ROCm/HIP change, Vulkan kernel change or 256k run.
- **Source status:** **Windows verification PASS (2026-10-26 JST)**. Vulkan and ROCm b11901 (`722a18926`) passed native policy/model-state tests, short MTP smoke and all **18/18 planned long-context runs**. See [final results](#windows-final-gates-and-s6-noop-closure-2026-10-26-jst). The switch remains opt-in/default OFF.
- **Naming:** the frozen [r6 integration plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md) groups DENSE and NOOP within original S5, then Stage-B/flatten under original S6. This separate continuation branch is called **S6-NOOP** for the experiment sequence. Patch order is unchanged; Stage-B/flatten is the *next* distinct code task after NOOP gates.
- **Prior result:** [S5 DENSE passed 18/18 long runs](R6-MTP-DENSE-S5-IMPLEMENTATION-2026-10-26.md#5-evo-x2-final-s5-results-and-closure-2026-10-26-jst). Its independently controlled optimization is held **ON** for both S6 comparison arms; the compiled default remains OFF.

## Upstream and r5 source audit

Pinned r6 `llama_memory_hybrid_idx::seq_rm()` still performs `mem_idx_stale_set()` after every successful indexer `seq_rm()`, even if no indexer cell was removed. There is no native r6 equivalent of NOOP-001. Unlike the old r4 implementation, r6 contains modern k-pool grouping and state/restore machinery which must remain unchanged. The accepted donor is the minimal r5 `investigation/r5-mtp-noop-20261012` implementation (`cac2c6998`), audited against r6 constructors and memory API.

This is relevant only to the **DEFAULT target** hybrid indexer, not the MTP draft. S5 skips the draft's unnecessary ratio-zero indexer independently. `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` enables the new target-only logic; unset, `0` and all other strings leave it OFF.

The creation-time policy fails closed unless all conditions hold:

1. QWEN4EXP model in a DEFAULT (non-MTP) context with an indexer cache.
2. By-order key grouping, k-pool=4, no SWA.
3. Exactly one configured sequence and one actual indexer stream.
4. For each candidate trim, `seq_id==0`; the configured single-sequence/single-stream model must preclude shared ownership.

After the recurrent-cache `seq_rm()` succeeds, the existing indexer `seq_rm()` is preserved. For eligible trims only, compare physical indexer membership count before and after; if unchanged, suppress **only the newly requested** stale mark. `seq_rm` can remove cells but cannot add them, making equal counts a no-op witness under the isolated ownership requirement. Do not clear a previous pending stale marker. A real edit, unsupported sharing, nonzero/negative seq ID, refused recurrent edit or OFF policy retains the original handling. The attention-cache remove and its return value are untouched.

## File changes

| File | Purpose |
| --- | --- |
| `src/llama-qsa-noop-policy.h` | Pure, fail-closed exact-1/target/sequence/cache policy |
| `src/llama-model.cpp` | Explicit target-role argument on Qwen4Exp hybrid-indexer construction, without touching draft DENSE policy |
| `src/llama-memory-hybrid-idx.h/.cpp` | Allocation-time policy, optional startup evidence, single-target no-op stale suppression; optional per-trim proof trace |
| `tests/test-qsa-noop-policy.cpp` | Policy and real cell-metadata cases (CTest behavior) |
| `tests/test-qsa-noop-invalidation.cpp` | Explicit real-model target logit/NextN, accepted=0/1/2 rollback, state/restore, no-op/real edit, fallback/refusal |
| `tests/CMakeLists.txt` | Adds two test executables while retaining S5 DENSE tests |
| `tools/evox2/tests/Test-R6MtpNoop.ps1` | Source/environment matrix assertions, manifest-verified policy and model tests |
| `tools/evox2/benchmark/configs/qwen38-r6-s6-mtp-noop-smoke.psd1` | 4k Vulkan IQ3 normal/trace, FP4 short compatibility and ROCm IQ3 short A/B |
| `tools/evox2/benchmark/configs/qwen38-r6-s6-mtp-noop.psd1` | Same-binary 64/128k IQ3 Vulkan+ROCm ABBA, FP4 FAST Vulkan 64k A/B |

`LLAMA_QSA_NOOP_TRACE=1` is **test only** and emits `QSA no-op trim` count/stale/suppression evidence; normal ABBA must leave it unset. Explicit `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1` emits target eligibility on startup. Existing benchmark-module log classification is reused.

## Local checks (not a Windows GPU PASS)

- `g++ -std=c++17 -O2 -Wall -Wextra -Werror -Iinclude -Iggml/include -Isrc tests/test-qsa-noop-policy.cpp`: executable built and printed `QSA no-op policy: PASS`.
- `g++ -std=c++17 -fsyntax-only` passed for `src/llama-memory-hybrid-idx.cpp`, `src/llama-model.cpp` and `tests/test-qsa-noop-invalidation.cpp` with their local include paths.
- The Linux workspace does not have CMake, Ninja, PowerShell, Vulkan SDK or the large GGUF files; **no end-to-end native/GPU gate has been performed here**.

## Windows runbook (from the new branch's checked-out root)

Configure `tools/evox2/benchmark/configs/local.psd1` with the new build keys (adapt the path if the source is in a different checkout):

```powershell
# Add under Builds; do not replace the proven S5 entries.
S6Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-mtp-noop\bin\Release'
    ExpectedBackend = 'Vulkan'
}
S6ROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-r6-mtp-noop\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Keep `UnslothPle16`, `UnslothMtp`, `AgentionRocmFp4FastPle16`, `AgentionRocmFp4FastMtp` and `Inputs.64k/128k` pointing at the same files used for S5. Confirm the checked-out branch with `git branch --show-current` and source SHA with `git rev-parse HEAD`. Do not build from a worktree that still points at S5.

**Gate 0 - source/plan check**, no model required:

```powershell
& .\tools\evox2\tests\Test-R6MtpNoop.ps1 -SourceOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r6-s6-mtp-noop.psd1 -PlanOnly
```

**Gate A - new Vulkan build and actual native tests**. The two `-ExtraTargets` are necessary, and the resulting JSON must report `BuildIdentity.Status = Verified`, valid executable and runtime DLL hashes:

```powershell
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r6-mtp-noop `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4 `
    -ExtraTargets @('test-qsa-noop-policy','test-qsa-noop-invalidation')

& .\tools\evox2\tests\Test-R6MtpNoop.ps1 `
    -BuildKey S6Vulkan -ModelKey UnslothPle16 -RunModelTests
```

Required: `QSA no-op policy: PASS` and `QSA no-op invalidation: PASS (...)`, finite matched logits/NextN hidden (NMSE <= 1e-5), saved and restored full/partial states, no-op suppressed without clearing pending stale, real removal still marks stale, and shared/multisequence fallback. STOP on any test failure, no timing claims.

**Gate B - short Vulkan CLI**. Confirm main/Draft loading and offload, `target=1 eligible=1 enabled=0/1` and `Draft omitted=1` from S5, same output/acceptance, no anomalous P-MODE/VRAM clock; the trace variants are only diagnostic:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r6-s6-mtp-noop-smoke.psd1 `
    -OnlyJob s6-iq3-smoke
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r6-s6-mtp-noop-smoke.psd1 `
    -OnlyJob s6-fp4-smoke
```

**Gate C - independent Vulkan 64k then 128k**. Same executable, model, input and 512 generated tokens across A1/B1/B2/A2; vary only `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1/1/0`. All variants have MTP ON, DENSE=1, QSA union=0, test tracing OFF:

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-s6-mtp-noop.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob s6-iq3-vulkan -OnlyCase 64k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob s6-iq3-vulkan -OnlyCase 128k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob s6-fp4-vulkan -OnlyCase 64k
```

Run one context at a time, reviewing results before proceeding. For Vulkan, a divergent generated-output hash or Draft acceptance between OFF and ON is a stop condition; compare PP, TG, total seconds and actual GPU clocks. Do **not** compare different S5/S6 binaries as if they were a controlled A/B.

**Gate D - ROCm** after Vulkan passes: build with TheRock 10.0, verify loaded DLL provenance/BuildIdentity, do not enable `-RunBackendTest` (avoid unsafe `FLASH_ATTN_EXT` tests), run the policy/model tests with `-BuildKey S6ROCm`, then IQ3 4k smoke with the ROCm BuildKey. Proceed to 64k then 128k ABBA:

```powershell
& .\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-r6-mtp-noop -Parallel 4 `
    -ExtraTargets @('test-qsa-noop-policy','test-qsa-noop-invalidation')
& .\tools\evox2\tests\Test-R6MtpNoop.ps1 `
    -BuildKey S6ROCm -ModelKey UnslothPle16 -RunModelTests
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r6-s6-mtp-noop-smoke.psd1 `
    -OnlyJob s6-iq3-rocm-smoke
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob s6-iq3-rocm -OnlyCase 64k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob s6-iq3-rocm -OnlyCase 128k
```

ROCm already produces varying temp=0 text and acceptance even for same-switch repeated runs; report hashes and per-run acceptance, interpret same-binary paired TG as **observed** rather than bitwise-equivalent acceleration. STOP on new model load, state or output-quality regressions, GPU/P-MODE anomalies or crashes. No 256k expansion. After both backends pass, evaluate S6-NOOP as an independent opt-in S7 integration candidate; only then plan the Stage-B/flatten source work.

## Windows final gates and S6-NOOP closure (2026-10-26 JST)

### Verified source, builds and native correctness

- Source and both executable manifests: clean `r6/mtp-noop-20261026`, commit **`722a189261d88102c481571cb5b8d4a0afcebeff`**, build **b11901**, `BuildIdentity.Status=Verified`. The ABBA matrix used the same binary per backend and varied only `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1`; S5 DENSE was **ON in both arms**, QSA union OFF, and diagnostic trace OFF.
- Vulkan: Windows Clang 20.1.8; ROCm: TheRock SDK **10.0.0** / `gfx1151`, Windows Clang 23.0.0. The ROCm `TheRockUnified` manifest reports the complete HIP/BLAS DLL closure and rocBLAS/hipBLASLt data copied with source/destination SHA-256 equality (`DllAndRuntimeDataHashesVerified`). `-RunBackendTest` was **not** used because of the known dangerous `FLASH_ATTN_EXT` test history.
- `Test-R6MtpNoop.ps1 -RunModelTests` on **both** backends: source checks PASS, `test-qsa-noop-policy.exe` PASS, `test-qsa-noop-invalidation.exe` PASS, exit 0. Each model log has **524/524** target logit / NextN hidden comparisons with **NMSE=0, max_abs=0**. Full/partial state restore, accepted=0/1/2 rollback, actual trim, previous-stale preservation, shared/multisequence fallback and refused edits were exercised. Four `unexpectedly reached end of buffer` stderr lines are intentional invalid-state restore probes, not a failure.
- Vulkan 4k smoke **6/6 PASS**: IQ3 OFF/ON and diagnostic OFF/ON, FP4 FAST OFF/ON. IQ3 and FP4 each preserved output hash and Draft acceptance between OFF/ON; target `eligible=1 enabled=0/1`, draft `enabled=0`, DENSE `omitted=1`. Traced eligible trims confirmed suppression on real no-op and preservation of real-removal marks. ROCm IQ3 4k smoke **2/2 PASS**, both with identical output hash and Draft **37/50** (74%). Speed is **not** inferred from these short runs.

### Same-binary 64k/128k throughput results

All figures are `llama-cli`, MTP ON, DraftMax=2, 512 generated tokens, `temp=0`, fixed input (64k: **61,789** prompt tokens; 128k: **126,253**). ABBA order is **A1 OFF / B1 ON / B2 ON / A2 OFF**. Means average the two runs per arm; FP4 FAST uses one OFF/ON pair only.

| Backend / model | Context | OFF PP | ON PP | PP change | OFF TG | ON TG | TG change | Runs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Vulkan / IQ3 PLE16 | 64k | 318.470 | 318.360 | -0.03% | 34.145 | 35.170 | **+3.00%** | 4/4 OK (ABBA) |
| Vulkan / IQ3 PLE16 | 128k | 247.825 | 247.710 | -0.05% | 29.265 | 31.075 | **+6.18%** | 4/4 OK (ABBA) |
| Vulkan / ROCmFP4 FAST PLE16 | 64k | 325.580 | 324.160 | -0.44% | 35.540 | 36.610 | **+3.01%** | 2/2 OK (A/B) |
| ROCm / IQ3 PLE16 | 64k | 377.560 | 376.765 | -0.21% | 28.065 | 28.850 | **+2.80%** | 4/4 OK (ABBA) |
| ROCm / IQ3 PLE16 | 128k | 282.220 | 282.075 | -0.05% | 21.640 | 22.290 | **+3.00%** | 4/4 OK (ABBA) |

**All 18/18 long runs finished `Status=OK` with Verified policy evidence**, `PModeStart=PModeFinish=Performance`, no P-MODE warnings and ADLX high-load power approximately **119–120 W**. High-load ROCm 64k GPU clocks averaged **2,830–2,841 MHz**, VRAM **992–994 MHz**; ROCm 128k GPU **2,853–2,860 MHz**, VRAM **992–994 MHz**. There was no restart, low-VRAM-clock regime or clock/power explanation for the ROCm TG dispersion. Target NOOP eligibility and OFF/ON activation were verified in every arm. **PP was effectively unchanged** except FP4 FAST's one-pair -0.44%.

**Vulkan output equivalence:** For each IQ3 depth, all four generated-output SHA-256 values **and Draft accepted/generated counts were identical** between OFF and ON. IQ3 64k: `f973fb6cf66bf1d666d7342aca0f5ecdb46c866b94a42ab7c07bccbbce91dc27`, Draft **300/421**. IQ3 128k: `ca205b843adc01ef7e2e820b70834904eeddd51561b4ae18ae0257e563f72db9`, Draft **299/424**. FP4 FAST 64k: both outputs `e2d2401999f445adec384cf1e8b602ef3de37aeecf02e6a6f4b1cba5f4856e31`, Draft **293/436**. FP4's 2run result is supportive but has less repeated-run confidence than IQ3 ABBA. Its PP+TG time was ~0.41 s slower ON because of the small PP difference and long prompt; interpret TG and end-to-end latency separately.

**ROCm nondeterministic-output limitation:** All four output hashes differ at both depths, including OFF/ON repetitions, consistent with pre-existing ROCm `temp=0` variability. Different generated text and acceptance confound a precise causal attribution of TG gain. The per-run evidence is retained rather than treating these as bitwise-matched trajectories:

| Context | Run | TG (tok/s) | Draft accepted/generated | Acceptance |
| --- | --- | ---: | ---: | ---: |
| 64k | A1 OFF | 27.72 | 290/441 | 65.76% |
| 64k | B1 ON | 29.07 | 298/425 | 70.12% |
| 64k | B2 ON | 28.63 | 295/429 | 68.77% |
| 64k | A2 OFF | 28.41 | 295/431 | 68.45% |
| 128k | A1 OFF | 21.76 | 298/423 | 70.45% |
| 128k | B1 ON | 22.06 | 292/435 | 67.13% |
| 128k | B2 ON | 22.52 | 297/428 | 69.39% |
| 128k | A2 OFF | 21.52 | 293/435 | 67.36% |

At 64k, B1/A1 gains **+4.87%** TG but also has markedly higher Draft acceptance; B2/A2 gains only **+0.77%** with near-equal Draft **295/429 vs 295/431**. At 128k B1/B2 TG is **22.06/22.52** while acceptance is **67.13/69.39%**. However B1 still beats A1 (**+1.38% TG**) despite **lower** acceptance, and B2 beats A2 (**+4.65%**). Thus the observed ROCm +2.80/+3.00% is a consistent *directional same-binary improvement*, **not** proof of its exact isolated magnitude. Neither the S5 and S6 gain percentages nor cross-binary results should be blindly added.

### Archived verification evidence (outside Git)

| Artifact | SHA-256 |
| --- | --- |
| `(vulkan-mtp-noop)evox2-build.json` | `54326a3d2e2fd0f40418cf8761c0d05fb8b83401cb1dc8c995e49b030adcb6db` |
| `(rocm-noop)evox2-build.json` | `948b0eb574eae9a20bb9e03f1770bdb5632fa4ef47e24b6f66992732c310892b` |
| `20261026-195255-255-qsa-noop-invalidation.zip` (Vulkan native) | `2feb05acb0a8c74a2964360b4305759f5b6c2d0722b73befabb8c665bded274a` |
| `20261026-222919-224-qsa-noop-invalidation.zip` (ROCm native) | `56d9e43dd246fad9497bddbc1cf7176ea0679ca6dbc1f2edb83cd6a95111ad0c` |
| `20261026-202757-822-cli-vulkan-b11901-ctx4096-f5a1b53e0eea.zip` (Vulkan short) | `698cb1e356e064d554f7d349a72f6a5acf7688c625f5921531d320826cf9685e` |
| `20261026-224437-896-cli-rocm-b11901-ctx4096-5bf6e7877d3c.zip` (ROCm short) | `9e92e792ebb52074a7eb03d6a81fcf3a7eabbaab5177892f7fc1ce917a06f05a` |
| `20261026-203844-191-qwen38-r6-s6-mtp-noop.zip` (Vulkan IQ3 64k) | `ea2e14da8369739a100bfa50cd39319f6958dafdb56f28dbfcd7c770de044866` |
| `20261026-210303-010-qwen38-r6-s6-mtp-noop.zip` (Vulkan IQ3 128k) | `20fa48f92b119428426cbc27087219b75cb2fcd26212e998c8b17f9d2ded00f5` |
| `20261026-220729-461-qwen38-r6-s6-mtp-noop.zip` (Vulkan FP4 FAST 64k) | `9cc9966a8520f58da1bf60e84ad7b59d30d84d042a1a1b0403f55428f397a3b9` |
| `20261026-224956-703-qwen38-r6-s6-mtp-noop.zip` (ROCm IQ3 64k) | `cfc324e4a2a24b9577f56df8b6425f07965975453ecd6b1d44313e77127630bc` |
| `20261026-231842-327-qwen38-r6-s6-mtp-noop.zip` (ROCm IQ3 128k) | `2f3138ce8773c9ac057d3b7be902e65bf1c6b3f7d8d1f5d924350d9b7257125e` |

**Decision: bounded Windows S6-NOOP gate PASS; retain independently switchable NOOP as a candidate for S7/combined integration, with default OFF.** This is an incremental TG optimization above S5 DENSE, not a new default runtime setting. No 256k tests were required or run. Do not conflate this independently named S6-NOOP experiment with the frozen plan's original **S6 Stage-B/flatten** step, which is **still pending**; preserve separate ON/OFF gates and the accepted C/A/B sequence when beginning the next source port.
