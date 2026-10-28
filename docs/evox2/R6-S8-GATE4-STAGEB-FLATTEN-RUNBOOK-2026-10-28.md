# R6 S8 Gate 4 — Stage-B / flatten interaction and parity runbook (2026-10-28)

## Purpose and status

**Status: EXECUTED; output/continuation gate PASS (14/14), numerical Draft K/V parity DEFER.** See the measured closure below. This gate follows G8-3 and isolates S7-A (Stage-B) and S7-B (flatten) on the final S8 Vulkan executable. It does **not** repeat all-flags-OFF versus all-flags-ON, which changes QSA union and produced differing output fingerprints in G8-3.

The S8 combined Gate 3 evidence includes:

- Vulkan IQ3 64k ABBA: PP +12.21%, TG +4.26%; 128k ABBA: PP +30.23%, TG +20.37%.
- Vulkan ROCmFP4 64k ABBA: PP +12.32%, TG +4.76%; 128k A/B: PP +34.62%, TG +18.79% (one run each).
- ROCm IQ3 64k ABBA: PP -0.15%, TG +5.96%; 128k ABBA: PP +0.62%, TG +20.24%. ROCm output fingerprints differ between repeated `temp=0` runs. Do not use ROCm bytewise output parity as a correctness gate without controlling its existing nondeterminism.
- G8-3 used executable b11908, source commit `b82243bf0`; S8 Windows `CombinedVulkan` is the **fixed** Clang-20 build path (not the original mixed-Clang build).

## Scope and fixed conditions

Use [the Gate 4 plan](../../tools/evox2/benchmark/configs/qwen38-r6-s8-gate4-stageb-flatten.psd1). **Every variant** fixes the other three speed patches as ON: `GGML_VK_QSA_UNION=1` with `MIN_KV=32768`, `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1`. Stage-B and flatten alone vary:

| Variant | Stage-B (`LLAMA_MTP_DRAFT_PREFILL_KV_CROP`) | Flatten (`LLAMA_MTP_EH_PROJ_FLATTEN`) | Purpose |
| --- | --- | --- | --- |
| C | `0` | `0` | Reference under the final other-flags-ON profile |
| A | `1` | `0` | Stage-B-only correctness and performance |
| B | `1` | `1` | Additional flatten correctness and performance |
| D (short only) | `0` | `1` | Prove flatten is inert when Stage-B is OFF |

The benchmark uses the same `CombinedVulkan` executable and model within each job, `MTP ON`, DraftMax=2, `f16` main/draft KV, `FA auto`, batch 2048, ubatch 1024, threads/tb=4, GPU layers 999, temperature 0, seed 1234, and P-MODE/ADLX logging. The short input is **163 tokens**, irrespective of its 4k context allocation. Real 64k input is **61,789 tokens** and can exercise union; a short 4k test cannot prove union activation.

### Important numerical limitation

The current combined executable **does not implement** `LLAMA_MTP_KV_SNAPSHOT_*` / `mtp_kv_snapshot_v1`: those diagnostics existed on a separate r5 investigative branch. Although `tools/evox2/benchmark/analyze_mtp_kv_parity.py` is present, setting the old environment variables on b11908 will **not** produce usable Draft K/V state files. This plan therefore verifies output/acceptance/continuation behavior, **not numerical Draft K/V equality or snapshot-backed rollback parity**. Do not mistake exact generated text for internal state identity.

If promotion of Stage-B/flatten as a fully parity-verified production preset is required, make an **independent, diagnostic-only follow-up branch/build** to port state snapshots from the documented r5 investigation, verify their runtime compatibility, then compare active K/V elements and rollback state. Keep the S8 source-frozen release candidate untouched. Until then record `G8-4 numerical Draft K/V parity = DEFER`, and keep both S7 flags default OFF; a separately documented opt-in performance experiment remains possible.

## Windows execution sequence

Run from `C:\llama-build\llama.cpp-evox2-windows-r6` after updating the S8 branch that contains this plan. `local.psd1` is ignored and must map `Builds.CombinedVulkan.BinDir` to `C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-combined-fixed\bin\Release`. Do **not** use the earlier non-fixed build directory. Keep b11908, source SHA and executable identity consistent across all variants.

```powershell
$plan   = '.\tools\evox2\benchmark\configs\qwen38-r6-s8-gate4-stageb-flatten.psd1'
$runner = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'

# G4-A: IQ3 4k, four variants (includes flatten-with-Stage-B-OFF inertness).
& $runner -Plan $plan -OnlyJob s8-g4-iq3-vulkan-short -OnlyCase 4k -PlanOnly
& $runner -Plan $plan -OnlyJob s8-g4-iq3-vulkan-short -OnlyCase 4k -StopOnError
```

**Stop and inspect the IQ3 output before proceeding.** If all four have matching output fingerprints, `Status=OK`, valid MTP acceptance and no rollback/CPU fallback anomalies, run FP4 short:

```powershell
# G4-B: ROCmFP4 4k, same four variants and same final Vulkan executable.
& $runner -Plan $plan -OnlyJob s8-g4-fp4-vulkan-short -OnlyCase 4k -PlanOnly
& $runner -Plan $plan -OnlyJob s8-g4-fp4-vulkan-short -OnlyCase 4k -StopOnError
```

Only after both short checks pass, measure three 64k variants for IQ3 (not a repetition of the G8-3 all-OFF/all-ON comparison):

```powershell
# G4-C: IQ3 64k C/A/B. Actual input 61,789 tokens, 512 generated.
& $runner -Plan $plan -OnlyJob s8-g4-iq3-vulkan-real -OnlyCase 64k -PlanOnly
& $runner -Plan $plan -OnlyJob s8-g4-iq3-vulkan-real -OnlyCase 64k -StopOnError
```

Finally, if G4-C is clean, run the ROCmFP4 64k C/A/B matrix:

```powershell
# G4-D: ROCmFP4 64k C/A/B.
& $runner -Plan $plan -OnlyJob s8-g4-fp4-vulkan-real -OnlyCase 64k -PlanOnly
& $runner -Plan $plan -OnlyJob s8-g4-fp4-vulkan-real -OnlyCase 64k -StopOnError
```

Do not launch all jobs at once. Send each completed ZIP before moving to the next job, as in G8-3. No new source build is needed for this output-level gate.

## Review and stop criteria

| Check | Short 4k | Real 64k | Action on failure |
| --- | --- | --- | --- |
| Correct build / conditions | Same executable SHA, source/b11908, fixed main+Draft GGUF; only Stage-B/flatten vary | Same, and identical actual input SHA/tokens | Stop and fix plan/local build key |
| Normal operation | All variants exit 0, main+Draft on GPU, no malformed output | Same | Stop affected model |
| Output-level parity | Expected C=A=B=D within each model | Expected C=A=B within each model | Stop, inspect normalized text and exact input; do not infer internal KV parity |
| MTP behavior | Accepted/generated and acceptance unchanged across variants where output is identical | Same | Diagnose unexpected divergence/rollback before production opt-in |
| Inertness of flatten | D (`Stage-B OFF / flatten ON`) must equal C (`0/0`) | Covered by source guard and short dynamic test | If D differs, disable flatten and stop |
| Stage-B / flatten actual path | Source eligibility requires zero-output Draft, single sequence, dense MTP; environment flags alone do not prove execution | At 64k additionally check `qsa-union active` in stderr | Mark path DEFER if missing evidence |
| P-MODE / GPU clock | Performance and expected offload | Performance, ADLX power consistency, no VRAM-clock collapse | Stop performance interpretation |
| Internal Draft K/V, rollback numerical parity | **Not instrumented in b11908** | **Not instrumented in b11908** | Keep separate `DEFER`, do not mark full numerical PASS |

Small PP gains of flatten (~1-2% in S7) are within the range of run-to-run variation; **do not make a performance acceptance claim from a single C/A/B**. The primary G8-4 objective here is preserving behavior under the final combination. If output mismatches or a recurring TG regression occur, perform at most one bounded follow-up, then defer/disable the optional S7 feature rather than extending the experiment indefinitely.

ROCm Stage-B/flatten is **not enabled in the supported ROCm profile**. The already prepared `qwen38-r6-s8-rocm-stageb-smoke.psd1` is optional and diagnostic-only; a successful short C/A/B there is not authorization to promote S7 flags on ROCm.

After the Gate 4 verdict, G8-5 is **one** representative 256k IQ3 Vulkan all-ON stability run (not ROCm), followed by G8-6 runtime/server usability checks and S9 final-model tests.

## G8-4 Windows measured closure - 2026-10-28 JST

**Verdict: output/continuation PASS, 14/14.** This is **not** a numerical Draft K/V or rollback-state parity PASS. No new code was built for this gate, and no production-wide flag defaults change.

### Evidence and provenance

- Two user-supplied ZIP sets contain the 14 run directories: `20261028-191233-060-cli-vulkan-b11908-ctx4096-5eb2068574fc(1).zip` (IQ3 short 4/4) and `20261028-192546-568-cli-vulkan-b11908-ctx4096-0b4ece667f7a.zip` (FP4 short 4/4 plus IQ3/FP4 64k 6/6). Raw logs remain outside Git.
- All runs report branch `r6/combined-20261028`, Git identity `d7a7dfa4ae8049ffb1e4fb38b409281622602698` (clean), Vulkan b11908 / source `b82243bf0`, Clang 20.1.8, `CombinedVulkan` **fixed** build directory. `llama-cli.exe` SHA256 is `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`; all 14 report `RuntimeArtifactStatus=Verified` and identical runtime digest `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3`.
- All runs used 96GB UMA, f16 main/Draft KV, MTP ON/DraftMax=2, FA auto, `-ngl 999`, `-b 2048`, `-ub 1024`, `-t 4`, `-tb 4`, `--seed 1234`, `--temp 0`, no prompt cache and `--ctx-checkpoints 0t`. QSA union (`min_kv=32768`), DENSE and NOOP remained ON in every variant; only Stage-B/flatten changed.
- Short: context allocation 4096, **actual input 163 tokens**, output 64. Real: context 65536, **actual input 61,789 tokens**, output 512. The real-input SHA256 is `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` in both model cohorts.
- All 14: `Status=OK`, `ExitCode=0`, `OutputFingerprintStatus=Captured`, no P-MODE change or warnings. Main 49/49 and Draft 50/50 layers offloaded to Vulkan. DENSE indexer omission and target QSA no-op invalidation decisions were `Verified`. `qsa-union active` appeared in all six 64k stderr logs. A 163-token short prompt does not test the union activation threshold.

### Short 4k: C/A/B/D

| Model | Variant | Stage-B | Flatten | PP tok/s | TG tok/s | Draft accepted/generated |
| --- | --- | --- | --- | ---: | ---: | ---: |
| IQ3 PLE16 | C | OFF | OFF | 274.75 | 36.44 | 35/54 |
| IQ3 PLE16 | A | ON | OFF | 277.47 | 37.02 | 35/54 |
| IQ3 PLE16 | B | ON | ON | 283.42 | 37.06 | 35/54 |
| IQ3 PLE16 | D | OFF | ON | 275.93 | 36.92 | 35/54 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | C | OFF | OFF | 269.81 | 37.89 | 34/56 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | A | ON | OFF | 274.31 | 38.32 | 34/56 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | B | ON | ON | 278.63 | 38.38 | 34/56 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | D | OFF | ON | 271.80 | 38.03 | 34/56 |

Each model's C/A/B/D normalized output SHA256 is identical; D=C output and acceptance prove short-path flatten inertness when Stage-B is OFF. Short ADLX had insufficient high-load samples for a power classification; authoritative WMI P-MODE stayed Performance at start and finish.

### Real 64k: C/A/B

| Model | Variant | Stage-B | Flatten | PP tok/s | TG tok/s | PP+TG time s | Draft accepted/generated |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| IQ3 PLE16 | C | OFF | OFF | 338.06 | 33.25 | 198.141 | 301/419 |
| IQ3 PLE16 | A | ON | OFF | 352.50 | 33.92 | 190.353 | 301/419 |
| IQ3 PLE16 | B | ON | ON | 357.28 | 33.95 | 187.995 | 301/419 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | C | OFF | OFF | 345.30 | 34.21 | 193.878 | 295/431 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | A | ON | OFF | 359.88 | 35.15 | 186.231 | 295/431 |
| ROCmFP4 FAST v2 PLE16 (Vulkan) | B | ON | ON | 366.35 | 34.71 | 183.381 | 295/431 |

Normalized output SHA256, unchanged within each cohort:

| Cohort | SHA256 | MTP acceptance |
| --- | --- | --- |
| IQ3 4k C/A/B/D | `76d6eda48a5d9a928fa4138eed734aa407e82dce3bd33704210d11063a478482` | 35/54 (64.815%) |
| FP4 4k C/A/B/D | `971347e2b1c2b46b65a73b0252c1cb52e14587df6644750cf89a3774fb9863bd` | 34/56 (60.714%) |
| IQ3 64k C/A/B | `0bbeb2d882c2546566a91cf2bb14dd0ef293570aa30e19455827d04339020a03` | 301/419 (71.838%) |
| FP4 64k C/A/B | `cd4fe1840edf62a14300f07b071e284b6b80c7e270c99d6bf5a6a3a0d95d059f` | 295/431 (68.445%) |

All six 64k runs had direct Performance -> Performance P-MODE plus ADLX `Performance-like` power consistency, with no high-load P-MODE warning. Relative to C, A improved PP by **+4.27% IQ3 / +4.22% FP4**; B improved PP by **+5.69% / +6.10%** and PP+TG total time by **-5.12% / -5.41%**. These are **one ordered C/A/B pass per model**, descriptive results, not a repeatability or isolated-flatten speed verdict.

### Confounder, limits and decision

- The user saw a Windows Defender scan-results notification during the final FP4 64k **M002 = A** run (19:46:36-19:50:35 JST). System CPU sampling averaged **5.32%** in M002 versus **3.28%** (M001=C) and **3.48%** (M003=B). M002 ADLX high-load power averaged **115.5W** versus **116.2W/115.8W**, and its PP/TG did not exhibit an obvious gross stall. The monitor does not attribute CPU usage to Defender and cannot prove scanning or its causal impact. The measured B-vs-A PP gap (~1.80% FP4) could be overestimated if M002 was disturbed.
- One run per 64k variant and ordered C/A/B timing cannot prove a 1-2% flatten increment or exclude temporal drift. Stage-B's ~4.2% PP trend is encouraging. A bounded repeatability comparison can be made separately if needed for performance promotion; it is **not** required to close this output-level gate.
- `qsa-union active`, DENSE/NOOP eligibility and output/acceptance parity were observed, but the Stage-B/flatten environment settings alone do not constitute an independent per-graph execution trace. **The combined b11908 executable has no Draft K/V snapshot instrumentation.** G8-4 **numerical Draft K/V / serialized state / rollback parity remains DEFER**, not an inferred PASS. Keep S7 flags default OFF and any all-ON profile explicit/opt-in.
- No new source patch, binary rebuild, ROCm Stage-B promotion, broad 256k stress or extra performance run is part of this closure. **Next: [G8-5 selective stability](R6-S8-GATE5-SELECTIVE-STABILITY-RUNBOOK-2026-10-28.md)**, one IQ3 Vulkan 256k MTP-ON all-ON run using the existing S8 plan, gated on prior 64k/128k correctness and power checks; then G8-6 and S9.
