# r6 MTP-NOOP-001 S6: implementation and Windows verification - 2026-10-26

- **Branch:** `r6/mtp-noop-20261026`, forked from `r6/mtp-dense-20261026` (`7c819cffb`, upstream baseline b11870).
- **Scope:** target-QSA no-op invalidation only. No upstream refresh, Stage-B, flatten, ROCm/HIP change, Vulkan kernel change or 256k run.
- **Source status:** implemented and locally syntax-checked; **Windows builds, model tests, real MTP smoke and long A/B remain pending**.
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
