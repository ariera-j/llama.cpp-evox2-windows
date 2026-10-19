# r5 MTP rollback / replay correctness diagnostic — 2026-10-19

**Implementation status: committed on isolated experimental branch; native Windows Vulkan compile and GGUF runs NOT YET VERIFIED.** The same-bit full Draft sequence-state comparison was already completed at 32k/64k/128k on b11682: see [numerical parity report](R5-MTP-DRAFT-KV-PARITY-IMPLEMENTATION-2026-10-19.md). This change adds an **entirely separate generation-time stress diagnostic**, not a performance optimization or release source merge.

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
