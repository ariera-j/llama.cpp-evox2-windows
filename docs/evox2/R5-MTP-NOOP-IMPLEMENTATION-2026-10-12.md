# r5 MTP-NOOP-001 — source implementation and Windows validation handoff (2026-10-12)

**Status: SOURCE IMPLEMENTED / NOT YET BUILT OR VALIDATED ON EVO-X2.** This is an isolated candidate, not a merged, verified, or integrated release. No real model tests, backend build, benchmark, or Windows artifact identity have been run by the assistant. **Do not claim throughput gains** until paired A/B runs pass.

## Exact source identity and branch boundaries

- Repository/branch: `ariera-j/llama.cpp-evox2-windows` / `investigation/r5-mtp-noop-20261012`.
- Frozen DENSE-only parent: `0dc8672d8b9b8c81e167bc566a9d80aadfb90307`, validated on Windows Vulkan and ROCm with 24/24 completed 64k/128k/256k DENSE ON/OFF ABBA runs. This parent remains untouched.
- Branch initial plan commit: `745ec1b4d0ff38f80847a83c8e1d71dd0a971e9c`.
- Source implementation commit: `cac2c6998316665bbcff26ee1234db1abab56aa6`.
- Test runner/matrix commit: `76f857ea09afcfcc20bf538f89d3e02ae5c7367e`.
- r5 stable `r5/upstream-refresh-20261009` remains at `7fefdf6149287f6adfc85efd85133c0f51fbba04` (at implementation time) and has **not** been merged, cherry-picked, or modified. Its two unique commits since merge-base `4cc8050c` modify only `docs/evox2/PERFORMANCE-RESEARCH-LOG.md`.
- Do not upgrade pinned upstream or backport r4's shared-cell k-pool/layout implementations.

## Implemented changes

| File | Source candidate behavior |
| --- | --- |
| `src/llama-qsa-noop-policy.h` | Reused r4's small pure, fail-closed policy: exact `1`, QWEN4EXP DEFAULT target, indexer exists, by-order pool4, one configured sequence and one stream, no SWA |
| `src/llama-model.cpp` | Supplies the *actual* `params.ctx_type == LLAMA_CONTEXT_TYPE_DEFAULT` to the hybrid-indexer constructor, preserving DENSE-001 unchanged |
| `src/llama-memory-hybrid-idx.h/.cpp` | Holds per-memory policy decision; emits startup evidence when NOOP setting is explicit. In `seq_rm`, keeps recurrent-before-indexer-before-attention order, observes indexer membership only when eligible and NOOP enabled or explicit tracing, and suppresses only a new stale mark when counts stay equal. Previously pending stale remains untouched |
| `src/llama-memory-hybrid-idx.cpp` opt-in proof | `LLAMA_QSA_NOOP_TRACE=1` enables **test-only** per-trim lines: before/after indexer membership, pending stale before/after, whether the new mark was suppressed. Default unset/0 logs nothing and no count lookup is done in NOOP=OFF non-trace path |
| `tests/test-qsa-noop-policy.cpp` | r4 pure policy and actual cell-metadata test; registered with CTest |
| `tests/test-qsa-noop-invalidation.cpp` | r4 main-model-based logit/NextN-hidden, kpool boundaries, accept0/1/2, target trim/no-op, pending stale, full/partial restore, shared/ineligible fallback and state tests; r4 broad `mtp_diag` assertion replaced with focused opt-in r5 trace proof; **not automatically run by CTest** because it requires a large external GGUF |
| `tests/CMakeLists.txt` | Registers two test executables without removing DENSE-001 targets |
| `tools/evox2/tests/Test-QsaNoopInvalidation.ps1` | r5 SourceOnly plan/evidence assertions, native executable & DLL manifest verification, optional large-model validation. Defaults to `R5MtpNoopVulkan` |
| `tools/evox2/benchmark/configs/qwen38-r5-mtp-noop-check.psd1` | 32k allocation context / short prompt; MTP ON, DENSE=1; two normal + two trace proof variants |
| `tools/evox2/benchmark/configs/qwen38-r5-mtp-noop-abba.psd1` | Vulkan normal A1/B1/B2/A2, 128k then 64k/256k as separate jobs, all with MTP ON / DENSE=1 and trace OFF |
| `tools/evox2/benchmark/configs/qwen38-r5-mtp-noop-rocm-abba.psd1` | Separate ROCm jobs for after Vulkan gating; Vulkan-only controls cleared |

The runtime switch is `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` (default OFF). The DENSE control is **separate** `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, always fixed ON in NOOP A/B. All native/test changes are source only; the r5 common loader, graph, GGML kernels, and backend dispatch were not modified.

**Safety:** the "not shared" premise is established only under the policy's single configured sequence + single indexer stream. r5 no longer has r4's `kpool_layout_shared()` and the source does not introspect sharing per removal. Native multi-sequence/shared fallback and state tests remain **mandatory**; if a real shared/other-owner case slips through these constraints, stop and tighten the policy before performance tests.

## Static source checks completed

- Reviewed current r5 source and its matching upstream hybrid-indexer `seq_rm` / constructor / layout path; NOOP behavior was not already present upstream.
- Source change anchors matched exactly once when assembling code; constructor/target-flag insertion occurred once; CMake added two distinct test targets; no DENSE code changed.
- PowerShell runner and matrix generation passed basic source structural checks (balanced delimiters and invariant markers). These **are not PowerShell parser execution**, which requires a host with PowerShell.
- Performed GitHub ref/commit/diff verification; r5 stable and DENSE-only HEADs not modified.
- **No C++ compilation, native model tests, SourceOnly PowerShell execution, ROCm/Vulkan inference, logit equality or benchmark measurement has occurred.** Report status is not `Complete`.

## Windows preparation (PowerShell from checked-out NEW branch)

Use the branch in a **new separate checkout/build directory**. Do not reuse or overwrite `build-vulkan-r5-mtp-dense` or the ROCm DENSE-only binary. The local config `tools/evox2/benchmark/configs/local.psd1` is ignored by Git; add entries for the following build keys, using the actual paths on this machine:

```powershell
# Example additions under Builds in local.psd1:
R5MtpNoopVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5-mtp-noop\build-vulkan-r5-mtp-noop\bin\Release'
    ExpectedBackend = 'Vulkan'
}
R5MtpNoopROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5-mtp-noop\build-rocm-r5-mtp-noop\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Use your already configured `UnslothPle16`, `UnslothMtp`, `Inputs` and `UmaLabel`. Update the example `BinDir` for the actual local checkout rather than assuming it exists. The new branch can be fetched with:

```powershell
git fetch origin
git switch investigation/r5-mtp-noop-20261012
git rev-parse HEAD
```

**Gate 0 — static/source validation** (before building):

```powershell
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 -SourceOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-noop-abba.psd1 -PlanOnly
```

Expect SourceChecksPassed only; this is **not** a GPU or model PASS.

**Gate A — new Vulkan full configure/build with explicit native targets** (PowerShell; adjust SDK/LLVM locations as needed):

```powershell
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r5-mtp-noop `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4 `
    -ExtraTargets @('test-qsa-noop-policy','test-qsa-noop-invalidation')
```

The build scripts compile `llama-cli`, server, bench, `test-backend-ops` by default. **ExtraTargets is required** to build the two NOOP test binaries, even though CMake registers them. Do not accept a ManifestOnly update as evidence of recompilation. The build must yield a Verified manifest for the new checkout source and runtime DLLs.

**Gate B — policy, target state/rollback/hidden tests**:

```powershell
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 `
    -BuildKey R5MtpNoopVulkan -ModelKey UnslothPle16 -RunModelTests
```

Native exit0 + `QSA no-op policy: PASS` and `QSA no-op invalidation: PASS (...)` are required, plus Verified executable/runtime manifest identity. Review actual `QSA no-op trim` events (unchanged membership + stale preserved and real deletion + stale marked). r4-sourced model code has not been tested against the r5 API/Windows compiler, so fix any legitimate compile/model issue **on the NOOP investigation branch only**, then rebuild before running long A/B.

**Gate C — short real CLI validation**: after Gate B:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-noop-check.psd1
```

All four A/B variants must be exit0/runtime Verified, show target NOOP startup evidence and draft DENSE omission `layer=48 ratio=0 omitted=1`. Compare normal A/B response and draft acceptance; proof runs have extra logs and are **not** TG controls. Trace ON proves real suppressions plus retained suffix stale marks.

**Gate D — Vulkan normal ABBA**: diagnostics/trace OFF; **one context at a time**:

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-noop-abba.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob vulkan-128k
# Only after the 128k evidence/output gate:
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob vulkan-64k
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob vulkan-256k
```

Same executable, exact input and model, `-n 512 --temp 0 --seed 1234 --ignore-eos`, f16 KV, batch2048/ubatch1024, threads4, draft max2/min0, target QSA union ON/min KV32768. The four variants differ in NOOP=0/1/1/0 only; DENSE=1 and MTP ON throughout. Compare actual generated-response hashes, acceptance, TG and PP; if any correctness/evidence gate fails, **stop**.

**Gate E — ROCm only after Vulkan**: build separately, include native targets:

```powershell
& .\tools\evox2\build\Build-ROCm.ps1 `
    -BuildDir .\build-rocm-r5-mtp-noop -Parallel 4 `
    -ExtraTargets @('test-qsa-noop-policy','test-qsa-noop-invalidation')
& .\tools\evox2\tests\Test-QsaNoopInvalidation.ps1 `
    -BuildKey R5MtpNoopROCm -ModelKey UnslothPle16 -RunModelTests
$rocmPlan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-noop-rocm-abba.psd1'
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $rocmPlan -OnlyJob rocm-128k
```

Add optional ROCm 64k/256k jobs only after review. For ROCm, **temp=0 nondeterminism already occurred within identical-setting DENSE-only repeats**; do not infer that NOOP caused text/acceptance changes without repeat-matched controls. Never run long ROCm and Vulkan GPU jobs concurrently.

## Acceptance and reporting checklist

1. SourceOnly PowerShell parsing and plan/evidence fixtures actually PASS.
2. Vulkan and then ROCm new build identity, test target DLL artifacts verified; no DENSE binary reuse.
3. Policy test PASS, model target/state/rollback PASS, A/B matching finite logits and NextN hidden, true no-op suppression and pending-stale/real-removal proof.
4. Real MTP ON + DENSE ON short A/B output/acceptance checks; no missing or malformed target/startup evidence.
5. Vulkan same-binary 128k ABBA first, then 64k/256k; only NOOP changes.
6. ROCm correctness first, then bounded long A/B; keep intrinsic nondeterminism and actual A/B acceptance changes explicit.
7. Preserve full ZIPs, SHA256, `conditions.json`, `result.json`, `resources.csv`, executable/dll digests, model/input identity. Record PP/TG and elapsed times; do not treat r4 +12.99% as forecast.
8. NOOP default remains OFF. No r5 stable merge or integrated release promotion without separate user decision.

See [implementation plan](R5-MTP-NOOP-IMPLEMENTATION-PLAN-2026-10-12.md), [DENSE-only closure](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md), [r4 NOOP validation](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md).
