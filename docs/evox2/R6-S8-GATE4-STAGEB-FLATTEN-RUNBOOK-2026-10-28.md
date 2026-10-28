# R6 S8 Gate 4 — Stage-B / flatten interaction and parity runbook (2026-10-28)

## Purpose and status

**Status: PREPARED; no Gate 4 runs have been executed from this plan.** This gate follows G8-3 and isolates S7-A (Stage-B) and S7-B (flatten) on the final S8 Vulkan executable. It does **not** repeat all-flags-OFF versus all-flags-ON, which changes QSA union and produced differing output fingerprints in G8-3.

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
