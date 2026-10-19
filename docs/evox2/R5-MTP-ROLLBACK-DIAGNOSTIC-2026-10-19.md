# r5 MTP rollback / replay correctness diagnostic — 2026-10-19

**Status updated 2026-10-19 ~23:14 JST: native Windows Vulkan b11695 short Natural C/A/B PASSED, and synthetic Reject-zero (0,0) C/A/B PASSED with 63 genuine checkpoint restores and 63 replay commits per arm. Reject-after-one (1,0), Accept-all (1,1), and 64k rollback tests remain OPEN.** The same-bit full Draft sequence-state comparison was already completed at 32k/64k/128k on b11682: see [numerical parity report](R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md). This change adds an **entirely separate generation-time stress diagnostic**, not a performance optimization or release source merge.

- Branch: `investigation/r5-mtp-rollback-diagnostic-20261019`, forked from `investigation/r5-mtp-draft-kv-parity-20261019`.
- Preserve b11682 and its 128k raw snapshots. Do **not** overwrite `build-vulkan-r5-mtp-kv-parity`.
- Stable r5 and previous flatten branch source remain unchanged.

## Why synthetic acceptance, and what is being tested

Existing `--spec-synth-rates` in llama.cpp is a diagnostic facility that replaces verification probabilities with deterministic synthetic acceptance rates (seed 1234). We use it to cover these **specific** server speculative-decoding branches. `--spec-draft-n-max 2` in the benchmark runner produces up to two draft tokens.

| Case name | Existing CLI option | Expected branch | Force speculative checkpoint restore |
| --- | --- | --- | --- |
| `natural` | none | Real target verification, naturally accepted/rejected drafts, ordinary prefix rollback when needed | No |
| `reject-zero` | `--spec-synth-rates 0,0` | Reject first drafted token; restore saved Target and Draft checkpoints and replay accepted target token | Yes |
| `reject-after-one` | `--spec-synth-rates 1,0` | Accept first, reject second; restore checkpoints and replay prefix+target token | Yes |
| `accept-all` | `--spec-synth-rates 1,1` | Accept both drafts, no rollback or replay | Yes (checkpoint produced, not normally restored) |

**IMPORTANT: Synthetic acceptance intentionally produces outputs not validated against the target distribution; these are invalid as quality or ordinary generation test samples.** A/B parity and branch coverage within a *single identical synthetic scenario* is meaningful as a regression gate; it does not prove the synthetic text is correct, nor guarantee equivalence to MTP OFF output. `natural` separately compares genuine model output. If one or both draft positions produce EOG tokens, synthetic helper rejects drafted EOG; `accept-all` may not cover the intended path and MUST NOT be marked PASS by the analyzer.

Model under test: existing Unsloth Qwen3.8-Flash-Next PLE16 + MTP Q8_0 Draft on Windows Vulkan Evo-X2. Main targets: short (<1k input) first, then 64k longer-kv extension if smoke is solid.

## Added implementation

- `tools/server/server-context.cpp` (only C++ file changed on this branch): `LLAMA_MTP_ROLLBACK_DIAG=1` enables structured stderr events `mtp_rollback_diag_v1`, with `event=init/draft/decision/checkpoint_restore/commit`; includes tag (C/A/B), slot, monotonically increasing draft round, drafted/accepted/rolled-back count, restoration and replay evidence. A per-slot counter is reset at each task.
- `LLAMA_MTP_ROLLBACK_FORCE_CKPT=1`: **strictly diagnostic**; allowed only when DIAG=1 and synthetic acceptance is enabled. It makes the existing `spec_ckpt.update_tgt/update_dft` and `ckpt.load_tgt/load_dft` path run even on a context where partial `seq_rm` would normally suffice. The existing checkpoint serialization/restore APIs are used; the actual model kernels, Draft K/V write paths, and synthetic acceptance helper were NOT changed. Switch OFF (`0`) for normal inference or normal MTP behavior tracing. FORCED mode is **not** a benchmark.
- `LLAMA_MTP_ROLLBACK_TAG` is C/A/B for correlation.
- `tools/evox2/benchmark/configs/qwen38-r5-mtp-rollback-diagnostic.psd1`: `rollback-short` with four cases × three C/A/B variants (12 runs in all), `rollback-64k` with `natural` and `reject-after-one` × C/A/B (six runs). `-OnlyCase` supports bounded smoke, `-OnlyVariant` supports triage. Previous snapshot env vars, RGP markers and MTP PP traces are disabled.
- `tools/evox2/benchmark/analyze_mtp_rollback.py`: read one **combined** ZIP containing the C/A/B child run folders (or an extracted directory), parse `result.json`, `conditions.json`, `stderr.log`, and `stdout.log`. Reject missing/duplicate arms, digest/model/input divergence, bad env/CLI settings, failed native runs, generated output mismatch, and failure to observe required restore/replay/accept paths. Returns JSON `PASS/FAIL/ERROR` with event and coverage counts.
- `tools/evox2/tests/test_mtp_rollback.py`: synthetic regression fixtures for every scenario, missing replay and output mismatch. Does not constitute Vulkan runtime validation.

**Code-change footprint:** one server implementation, one new plan, one analyzer, one unit test, this documentation. Previous Draft K/V snapshot and numerical comparator code are retained and not altered.

## Windows steps (new build; do not reuse b11682)

Ensure any existing P-MODE/ADLX-local tool modifications are preserved. They previously caused `Source.Dirty=true` and should remain distinguishable from inference source changes. Check worktree before switching:

```powershell
git status --short
git fetch origin
git switch --track origin/investigation/r5-mtp-rollback-diagnostic-20261019
# If the branch already exists locally: git switch investigation/r5-mtp-rollback-diagnostic-20261019

python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_rollback.py' -v
python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_kv_parity.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r5-mtp-rollback `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

Add `R5MtpRollbackVulkan` to ignored local build mapping `tools/evox2/benchmark/configs/local.psd1` by **copying the previously working `R5MtpKvParityVulkan` entry** and modifying only its `BinDir` to point to the new `build-vulkan-r5-mtp-rollback/bin/Release`. Do not change or delete the previous BuildKey. Confirm new binary SHA256 and runtime digest are constant within C/A/B and different from the retained b11682 (otherwise you did not build new source).

### Bounded execution order

**FIRST only `natural` short C/A/B, then inspect ZIP**. This is the most important genuine-generation control.

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-rollback-diagnostic.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-short -OnlyCase natural
```

Then one at a time, and only if the preceding run succeeds:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-short -OnlyCase reject-zero
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-short -OnlyCase reject-after-one
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-short -OnlyCase accept-all
```

**Do not select the entire 12-run matrix until smoke has passed.** The synthetic cases intentionally serialize checkpoints and may be markedly slower than normal generation. Do not activate RGP concurrently.

Each matrix run should create **three** child directories with `stderr.log`, `stdout.log`, `conditions.json`, and `result.json`. Existing Evo-X2 logging/monitoring records also remain available.

### Automatic PASS / FAIL on a combined ZIP

After saving the **three child run directories of one scenario** into one ZIP (the same convention as the previous 64k C/A/B ZIP), run:

```powershell
python .\tools\evox2\benchmark\analyze_mtp_rollback.py `
  --source .\rollback-short-natural.zip --scenario natural `
  --report .\rollback-short-natural-report.json
```

Use `reject-zero`, `reject-after-one`, or `accept-all` in `--scenario` for the corresponding archive. Instead of a ZIP, `--source` may be an extracted directory containing all three child run folders. The parser expects **exactly C, A and B, same scenario**, not a mixture of different cases.

Expected synthetic outcomes:
- `reject-zero`: at least one original decision accepting 0 / rejecting drafts, actual `checkpoint_restore` > 0 and a later `commit replay=1`; restoration/replay counts match.
- `reject-after-one`: at least one original decision accepting exactly one, rejecting another, followed by restore and replay commit.
- `accept-all`: non-replay original decisions fully accept the draft, no restore, no replay.
- `natural`: real target verification logs and deterministic 128-token outputs should match across C/A/B; no forced restore is claimed.
- Every scenario: matched C/A/B executable and runtime hashes, model/input, generation length, normalized `stdout.log` (only timing banner removed), and proper flag/tags.

The analyzer is **fail-closed on branch-coverage gaps**, not a proof that all possible rollback histories have been exercised. Any `FAIL` requires logs and code investigation; do not proceed to 64k blindly. Some failures may originate from the synthetic checkpoint path itself and are useful findings.

### If short passes, optional 64k and acceptance decisions

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-64k -OnlyCase natural
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan `
  -OnlyJob rollback-64k -OnlyCase reject-after-one
```

Avoid 128k rollback runs until the short + 64k correctness results justify the cost. No need to save or upload huge new KV snapshots; this branch's rollback test uses structured logs and the ordinary benchmark ZIP only.

**What this can establish if all gates pass:** C/A/B behaved identically for genuine generation on fixed seed and for forced synthetic accept/reject, checkpoint restore and replay; generated text, branch counts and provenance agreed. **What it cannot establish:** synthetic output quality, recovery of every possible concurrent/long-lived state, production checkpoint restore use when not otherwise taken, or correctness on ROCm/other GGUF types.

**Next after confirmed native results:** mark tested generation paths PASSED, record exact SHA256, mode and counts, then consider porting Stage-B/flatten as individually optional optimizations into the separately planned new-upstream integration candidate. Never merge the diagnostic `FORCE_CKPT` mode as a default runtime setting.

## 2026-10-19 22:55–22:57 JST: native b11695 short Natural C/A/B PASSED

The user supplied the **complete three-child run ZIP**: `20261019-225741-655-cli-vulkan-b11695-ctx32768-2ae89c1622fc.zip`, SHA256 **`84aa97db96dd8558fe41b82ddd04680150277da09dfa3481cc8bb02e02f8dca7`**. All three native children ran on the Evo-X2 Windows Vulkan runtime.

| Run | C Stage-B OFF / flatten OFF | A Stage-B ON / flatten OFF | B Stage-B ON / flatten ON |
| --- | --- | --- | --- |
| Native child ID | `20261019-225527-229-cli-vulkan-b11695-ctx32768-4258fc984848` | `20261019-225637-366-cli-vulkan-b11695-ctx32768-8c2df0ad3598` | `20261019-225741-655-cli-vulkan-b11695-ctx32768-2ae89c1622fc` |
| `Status` / `ExitCode` | OK / 0 | OK / 0 | OK / 0 |
| Prompt/output | 163 / 128 | 163 / 128 | 163 / 128 |
| Draft accepted/generated | **69/116** | **69/116** | **69/116** |
| Draft rounds | **58** | **58** | **58** |
| 0 of 2 accepted | **14** | **14** | **14** |
| 1 of 2 accepted | **19** | **19** | **19** |
| 2 of 2 accepted | **25** | **25** | **25** |
| Checkpoint restorations / replay commits | 0 / 0 | 0 / 0 | 0 / 0 |
| P-MODE start → finish | Performance → Performance | Performance → Performance | Performance → Performance |
| PP tok/s, diagnostics ON | 98.60 | 275.39 | 279.22 |
| TG tok/s, diagnostics ON | 26.49 | 35.45 | 34.80 |

**Provenance:** b11695, Git commit **`5a5af4b949d0d481229a8ee1a0310c1f5d98c9f9`** (diagnostic tracing fix included). All three children use the identical executable SHA256 **`6cc24550d7b3d7f4c54f5570b91bf662b7fdd7b79f0e2ed97210109ab48c4f5e`** and verified runtime digest **`96eeb77cf15d4f398043e459d945766a33d408d550a5090ac88d3dfcf5f13064`**. Same model, self-contained MTP Draft, input SHA256 **`88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`**, 32768 context, f16 K/V, seed1234, no synthetic rates, `LLAMA_MTP_ROLLBACK_DIAG=1`, `LLAMA_MTP_ROLLBACK_FORCE_CKPT=0`. C/A/B flags 0/0, 1/0, 1/1. Local `Source.Dirty=true` still corresponds to the earlier P-MODE/ADLX harness tools; the identical fingerprint **`13afa3188e82c7377ad0ebbfc9fd763b6df3b7a910ec24fb6370f91618bb3568`** was reported for all arms; no inference-source local modification shown.

**Independent log checks:** 58 ordered `event=draft`, 58 `event=decision`, 58 `event=commit`, one `event=init` in each stderr log. Ordered decision tuples (round, drafted, accepted, rollback, checkpoint, replay) have the same SHA256 across C/A/B: **`8507fb5e075afd51402c413bbaeed83c9d93799a45bfda5cd72c6fbf047006cf`**. The actual generated `stdout.log` contents, after removing ONLY the changing throughput footer, are byte-identical (normalized SHA256 **`76dc3bb876829cf1eb376464e0d5268b0ef53b7194ab767647a63ce47ecc767b`**); original stdout files differ only in reported rates. All child stderr logs contain **no observed runtime error lines**.

Natural case includes **33 rejecting rounds (14 all-reject, 19 partial-reject)** and 25 full-accept rounds, all using **the normal native partial sequence-removal path** (`checkpoint=0` at every decision). It **does not** test forced Target/Draft checkpoint restoration, replay after checkpoint restore, or alternative acceptance rates. This is a genuine target-verification and continuation smoke PASS, not the end of the rollback gate.

**Measurement limitations:** b11695 diagnostics are ON; PP/TG from this case are not a general uninstrumented optimization A/B. GPU high-load power classifier says `InsufficientSamples` in all short runs; authoritative P-MODE is Performance from the native WMI probe, no warnings. Avoid turning the very large short C→A PP gap into a speed claim.

**NEXT (bounded):** preserve the same newly compiled b11695 binary and run **`-OnlyJob rollback-short -OnlyCase reject-zero`** with all three variants. This uses existing synthetic rates `0,0` and opt-in force checkpoint; compare the resultant ZIP with `analyze_mtp_rollback.py --scenario reject-zero`. It must show `checkpoint_restore > 0` and replay commits > 0 per arm. If this test fails (including crashes), **do not** proceed to `reject-after-one`, `accept-all`, or 64k; first inspect the diagnostic restore path. If it passes, test `reject-after-one`, then `accept-all` one at a time. Synthetic outputs are intentionally not quality-valid.

## 2026-10-19 ~23:13 JST: synthetic Reject-zero (0,0) C/A/B PASSED

**Source archive examined:** `20261019-231240-100-cli-vulkan-b11695-ctx32768-ac765f161990.zip`, SHA256 **`fe2acf61afed53470a45a04a43e22a1dca32811ba444efb3905911124eacd151`**. Archive contains all 3 children:

- C: `20261019-231019-514-cli-vulkan-b11695-ctx32768-7b8cdc514d99`;
- A: `20261019-231129-912-cli-vulkan-b11695-ctx32768-cba56012b172`;
- B: `20261019-231240-100-cli-vulkan-b11695-ctx32768-ac765f161990`.

All native runs completed status **OK / exit0**, same b11695 executable commit `5a5af4b94`, SHA256 **`6cc24550d7b3d7f4c54f5570b91bf662b7fdd7b79f0e2ed97210109ab48c4f5e`**, and same verified runtime artifact digest **`96eeb77cf15d4f398043e459d945766a33d408d550a5090ac88d3dfcf5f13064`**. Same target and Draft GGUF identities, 163-token prompt, 128 generated tokens, input SHA256 **`88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`**, context32768, f16 K/V and seed1234. C/A/B Stage-B/flatten flags **0/0, 1/0, 1/1**; each had `LLAMA_MTP_ROLLBACK_DIAG=1`, `LLAMA_MTP_ROLLBACK_FORCE_CKPT=1`, and CLI `--spec-synth-rates 0,0`. P-MODE **Performance at start and finish** each arm (ADLX classifier: `InsufficientSamples` for short job, not a P-MODE failure).

| Native event / outcome | C | A | B |
| --- | ---: | ---: | ---: |
| `event=init` | 1 | 1 | 1 |
| `event=draft` | 63 | 63 | 63 |
| `event=decision` | 126 | 126 | 126 |
| Original decisions: `accepted=0`, `rollback=2`, `checkpoint=1` | 63 | 63 | 63 |
| `event=checkpoint_restore` | **63** | **63** | **63** |
| Replay decisions `replay=1` | 63 | 63 | 63 |
| `event=commit replay=1` | **63** | **63** | **63** |
| Draft acceptance (user-facing measured metric) | **0/126** | **0/126** | **0/126** |
| 128-token generated output after volatile throughput-footer removal | identical | identical | identical |
| Native run status | OK | OK | OK |

**Ordered diagnostic event stream equality:** after removing tag and slot fields, C/A/B event records (316 events per arm) have identical SHA256 `c38f7d59e4db9b6946993d9711dbb226d43590cf612473ad2795d7452fd1f944`. Decision tuples likewise SHA256 `c7502d845820f14bf48a9aa4a93d44db73531bb19cd8045c6d0ffe271819beac`. Generated `stdout.log` normalized by removing *only* the printed Prompt/Generation throughput footer: identical SHA256 `76dc3bb876829cf1eb376464e0d5268b0ef53b7194ab767647a63ce47ecc767b`. The 63 rounds are contiguous from 1 to 63, each forces a full 0/2 Draft rejection followed by checkpoint restore, a replay decision and a completed replay commit. These counters prove the requested branches were actually traversed; this is **not** a success inferred solely from exit0.

C/A/B observed diagnostic-only PP respectively **269.53 / 275.84 / 275.04 tok/s**, TG **14.13 / 14.79 / 13.30 tok/s**. Do **not** benchmark these because forced checkpoints materially change work and memory synchronization. Synthetic text is **not a valid generative-quality test**. The MTP implementation's internal `#acc tokens=63` statistic counts replay-handled accepted tokens and is **not** interchangeable with the final-slot `DraftAccepted=0` metric in this scenario; use the explicit original `event=decision` and `event=commit` fields to establish behavior, avoiding a false contradiction.

**Conclusions:** synthetic zero-accept / checkpoint restore / replay is now **PASS** with exact C/A/B output and all-event traces, on the specified Windows Vulkan configuration. Natural short C/A/B and prefill full-state parity through 128k were already PASSED separately. This does **not** prove synthetic answer quality, partial acceptance with forced restore, or whole-path correctness on 64k/128k.

**NEXT:** Run `-OnlyJob rollback-short -OnlyCase reject-after-one` on **the same b11695 binary** (no rebuild), confirm each arm has at least one original decision accepting **one** token then restoring/replaying after rejecting the second and that normalized C/A/B output and decision traces match. Only then do `accept-all`. Once all short cases pass, perform selected 64k cases; no 128k rollback before assessing new evidence.

