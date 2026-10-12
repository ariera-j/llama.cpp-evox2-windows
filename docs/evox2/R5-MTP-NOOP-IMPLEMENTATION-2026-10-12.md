# r5 MTP-NOOP-001 — source implementation and Windows validation handoff (2026-10-12)

**Status: Vulkan native and real-MTP correctness + 64k/128k/256k same-binary ABBA COMPLETE (2026-10-12, user-run Evo-X2).** All three contexts passed 4/4 runs with identical generated stdout after removing only CLI timing lines and matching draft acceptance within each context. TG gains: **+2.10%, +6.73%, +14.40%** at 64k/128k/256k. **ROCm native/short correctness PASSED; ROCm 128k ABBA 4/4 OK with ON TG +6.42%, but output and draft acceptance differ even within OFF/OFF and ON/ON repetitions (provisional throughput only). ROCm 64k/256k pending; PP-side investigation not started.** This remains an isolated branch, not a stable merge or release. Detailed evidence: [Vulkan validation](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md).

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


## Vulkan validation closure — 2026-10-12

The user ran SourceOnly (after fixing the `$kind:` parsing issue and ROCm plan build-key mix-up in `b84d18870`), completed the Vulkan build, passed native model/policy and short real-MTP tests, and measured 12 normal Vulkan runs across three contexts. **The validated runtime was built at source `b84d18870` (embedded `b11577-b84d18870`)**; subsequent documentation commits are not a new compiled baseline.

| Depth | Input | PP OFF/ON (tok/s) | TG OFF/ON (tok/s) | TG delta | Acceptance (all four) |
| --- | ---: | ---: | ---: | ---: | --- |
| 64k | 61,789 | 335.865 / 335.230 | 31.385 / 32.045 | **+2.10%** | 295/430 |
| 128k | 126,253 | 303.645 / 303.365 | 26.960 / 28.775 | **+6.73%** | 295/429 |
| 256k | 255,181 | 266.035 / 265.690 | 21.075 / 24.110 | **+14.40%** | 300/421 |

All 12 executions returned `OK` / exit0, evidence Verified for DENSE draft indexer omission and NOOP target policy, runtime identity Verified, same binary SHA and DLL digest, and generated text identical **within each depth** after removing printed speed lines. ABBA A1/B1/B2/A2; MTP ON, DENSE=1, NOOP=0/1/1/0; no performance diagnostics. As PP dominates fresh long-prompt elapsed time, total PP+TG time saved is negligible (~0.00%, ~0.19%, ~0.18% at 64k,128k,256k). This is a **TG**, not a full-request latency, improvement.

The [full validation record](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md) contains per-run timing, startup evidence, exact runtime hashes, native mechanism proof, ZIP names and SHA256, and caveats. Retain the raw ZIP files outside Git; no large logs were committed.

**Next active steps:** (1) separate Windows ROCm build of this exact source candidate, (2) native policy/model/state checks, (3) ROCm short A/B and same-binary 128k ABBA before optional 64k/256k; interpret ROCm text/acceptance nondeterminism against same-setting repeat controls, (4) **only after ROCm NOOP concludes**, open a separate PP-overhead research plan/branch; keep NOOP source untouched and distinguish MTP ON/OFF PP from speculative decode TG. No integrated release promotion is authorized.


## ROCm native correctness checkpoint — 2026-10-12 evening

**Verdict: PASS, native correctness only; not ROCm CLI output equivalence or TG improvement.** User-uploaded Windows test artifact: `20261012-192405-917-qsa-noop-invalidation.zip`, SHA256 `1496b75dbd6af44c17b384c0e391b7c63c9e0fd1ada075897f36576817b5c90b`. ZIP contains `result.json`, `policy.stdout.log`, `model.stdout.log` and `model.stderr.log` (policy stderr empty).

- `result.json`: `Status=Complete`, `SourceChecks=Passed`, `PolicyTest=Passed`, `ModelTest=Passed`, `BuildIdentity.Status=Verified`. Native policy/model processes each `ExitCode=0`. Source and binaries were identified against the current ROCm build manifest by the runner; **do not confuse this with the old Vulkan DLL digest**.
- Backend proof: `ggml-hip.dll` loaded from `build-rocm-r5-mtp-noop\bin\Release`; AMD Radeon 8060S, `gfx1151` ROCm device. The ZIP reports policy-test runtime artifact digest `509ae8d294f3579f0f91197764cd79315c967fc2eb1d556143e9521bde090a65` and model-test digest `d1132ef24b64f55ff062a06fff08a4f01c1b29716623243c461f419cca9aa992`.
- **524 logits/NextN-hidden comparisons** in `model.stdout.log`: every one `nmse=0 max_abs=0`. Includes single/two-sequence, 32–35 token boundaries, accepted=0/1/2, full/partial state, rollback, sharing/keep fallback, offset/gapped, rejected state restore, and recurrent refusal. Final `QSA no-op invalidation: PASS (target numeric, pools, rollback, state and fallback)`.
- Mechanism trace `model.stderr.log`: both arms produced 121 inspected indexer trim events each. In NOOP OFF, 67 unchanged-membership operations **all marked stale**, and 54 real cell removals marked stale. In NOOP ON, **all 67 unchanged-membership operations suppressed a *new* mark**, while all **54 true removals kept stale invalidation**. All 67 suppressed operations preserved the previous stale marker, including 33 with non-clean pending stale state; 66/67 suppressed operations had nonzero indexer cells before trim. Startup evidence showed target eligible at `seq_max=1`, and refusal for `seq_max=2` (`unsupported_cache`).
- Four `state_seq_set_data: error loading state: unexpectedly reached end of buffer` messages are intentional malformed-restore test activity; final native exit=0 and numerical comparisons pass.

**Next:** r5 lacked a dedicated ROCm short-MTP plan. Added `tools/evox2/benchmark/configs/qwen38-r5-mtp-noop-rocm-check.psd1`, using `R5MtpNoopROCm`, Vulkan-only environment overrides explicitly unset, and A-normal/B-normal/A-proof/B-proof with MTP ON, DENSE ON, NOOP variable, proof logs only in proof arms. SourceOnly now checks four plans and rejects wrong backend/override combinations. This is **script/config only**, so no source rebuild is needed for the existing Verified ROCm executables. Use `Invoke-BenchmarkMatrix.ps1 -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-noop-rocm-check.psd1 -OnlyJob rocm-short` after the updated SourceOnly gate; compare A/B text, acceptance, evidence and diagnostic trim counters before 128k ROCm ABBA. ROCm temp0 non-determinism observed in prior DENSE-only work requires same-setting variability checks if short outputs diverge.

## ROCm real-MTP short verification — 2026-10-12 20:00 JST

**Verdict: PASS as a correctness/mechanism smoke gate; not evidence of ROCm NOOP TG improvement.** User ZIP `20261012-195627-785-qwen38-r5-mtp-noop-rocm-check.zip` SHA256 `62fb907b813941d671a6da2e70b5985b74ae089f6f7e2422e16b8b0c74154d4b`.

- Matrix `qwen38-r5-mtp-noop-rocm-check`: **4/4 OK, exit0, runtime identity Verified, DENSE evidence Verified and target NOOP evidence Verified**, SourceOnly/ROCm native gates passed previously. `A-normal`, `B-normal`, `A-proof`, `B-proof`, in that order.
- Actual ROCm runtime: Windows Clang 23.0.0, `b11579`, executable source `f62ca1cd4`, `llama-cli.exe` SHA256 `1a3ef3de0d9cb83a1278fadf060baf1c36cbcfc16c9066a330d0692877f5293e`, runtime artifact digest `6bb0ee22c133f1b44226a6f743299a11c17512ae5509de91961c420f982ef12c`, same in all four.
- Workload: **163 prompt tokens, 128 generated tokens** with Qwen3.8 Flash-Next Unsloth PLE16 target, Q8_0 MTP sidecar, `n_ctx=32768`, `--temp 0 --seed 1234 --top-k 1 --ignore-eos`, MTP ON, DENSE ON, target NOOP OFF/ON. `LLAMA_QSA_NOOP_TRACE=1` **only** in the two proof arms.
- Text after stripping only the CLI printed Prompt/Generation speed line **byte-identical for all four stdout files** (normalized UTF-8 SHA256 `4a116ad0669dfa0be200524b5593280ebe2d8e8ea0a17ffc56a482ce93c52052`); `DraftAccepted=74` / `DraftGenerated=106` (69.81%) in all four. Identical input/model/executable/digest; normal A/B environment differs only in `LLAMA_QSA_SKIP_NOOP_INVALIDATION`.
- Proof: **54 inspected indexer-removal events in each proof arm**. OFF: 34 no-membership-change calls marked stale, 20 real removals marked stale. ON: **all 34 unchanged-membership calls suppressed new stale marks** (33 with nonzero cells, one empty/pending-stale case), while **all 20 real removals still marked stale**. Existing stale preserved in all 34 suppressions, including one with a pending non-clean marker.
- Observed short-run timing (not a controlled performance comparison): `A-normal` PP/TG **194.41 / 36.08 tok/s**, `B-normal` **142.92 / 33.15**, `A-proof` **170.94 / 34.80**, `B-proof` **145.77 / 35.16**. Tiny 163-token PP and 128-token TG fluctuate with warm-up/run order; proof logging alters run conditions. Do **not** infer a NOOP regression/speedup from these four single runs.
- Short ROCm output equality is a valuable gate but does **not** supersede earlier ROCm **temp0 long-context, within-identical-setting output/acceptance variability**. Next: same-binary ROCm **128k A1→B1→B2→A2**, normal trace OFF, MTP ON and DENSE=1 fixed; assess repeated A/A and B/B numerical/output/acceptance/temperature stability before attributing TG difference. Only then schedule optional 64k/256k. PP optimization remains a separate future workstream.



## ROCm 128k same-binary ABBA checkpoint — 2026-10-12

User ZIP `20261012-200801-743-qwen38-r5-mtp-noop-rocm-abba.zip`, SHA256 `b1edf09bb0f2b66bc3f5332ece56088312761b92a810bf48aff7282a39064624`. **4/4 OK**, `ExitCode=0`, runtime identity `Verified`, NOOP startup decision `Verified`, draft DENSE omission `Verified`; each generated exactly 512 tokens from 126,253 input tokens. Vulkan-specific controls unset and trace disabled. All arms used `b11579-f62ca1cd4`, `llama-cli.exe` SHA256 `1a3ef3de0d9cb83a1278fadf060baf1c36cbcfc16c9066a330d0692877f5293e` and artifact digest `6bb0ee22c133f1b44226a6f743299a11c17512ae5509de91961c420f982ef12c`. Code build and current docs HEAD are distinct.

- **NOOP OFF A1/A2:** PP 275.64/272.35, TG 20.07/21.21 tok/s; acceptance 299/423 and 298/425.
- **NOOP ON B1/B2:** PP 275.38/275.68, TG 21.88/22.05 tok/s; acceptance 297/428 and 298/426.
- **Two-run means:** TG **20.640→21.965 tok/s (+6.42%)**; PP **273.995→275.530 (+0.56%)**; generation time **24,779.45→23,264.22 ms (−1.515 s)**. PP changes are not causally attributed to NOOP; observed whole prompt+generation timing difference is dominated by PP drift and should not be marketed as a confirmed total-latency gain.
- **Important constraint:** four distinct generated texts, **including A1 != A2 and B1 != B2**; draft accepted/generated counts differ. This corroborates previously observed ROCm long-context temp0 nondeterminism and precludes a same-trajectory correctness/equivalence claim. Native and short ROCm correctness gates passed independently, and both B rates exceed both A rates, but the **+6.42% is a provisional observed TG association, not a deterministic isolated speedup proof**.

Detailed per-run timing, provenance and limitations: [ROCm 128k checkpoint](R5-MTP-NOOP-ROCM-128K-2026-10-12.md). **Next:** collect 64k and 256k normal A1/B1/B2/A2 on this same ROCm runtime using the existing `qwen38-r5-mtp-noop-rocm-abba.psd1` plan, then close the ROCm NOOP measurement with appropriate nondeterminism caveat and proceed to independent MTP ON PP research. No source modification or release promotion.
