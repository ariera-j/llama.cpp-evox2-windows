# r5 MTP-NOOP-001: ROCm 128k ABBA checkpoint (2026-10-12)

**Status: 4/4 successful ROCm runs; TG advantage observed for NOOP ON, but same-setting long-context output and MTP-acceptance nondeterminism prevents a deterministic equivalence or causal speedup conclusion.** Follow-up ROCm 64k/256k is pending. Native model/rollback and short real-MTP proof gates have passed separately; Vulkan full three-depth validation is documented in [Vulkan validation](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md).

## Evidence and experimental control

- User-supplied `20261012-200801-743-qwen38-r5-mtp-noop-rocm-abba.zip`, SHA256 `b1edf09bb0f2b66bc3f5332ece56088312761b92a810bf48aff7282a39064624` (original raw ZIP retained externally, **not committed**). Includes four `result.json`, `conditions.json`, `stdout.log`, `stderr.log`, resource CSVs and matrix summary.
- Execution: 2026-10-12 20:08–20:48 JST, 4/4 `OK`, 0 non-OK, all exit0; same Windows 96GB UMA Evo-X2, ROCm AMD Radeon 8060S/gfx1151, Clang 23.0.0; build `b11579`.
- Compiled source `f62ca1cd4`, separate from later docs-only checkout `31a148e2`; CLI SHA256 `1a3ef3de0d9cb83a1278fadf060baf1c36cbcfc16c9066a330d0692877f5293e`, runtime artifact SHA/digest `6bb0ee22c133f1b44226a6f743299a11c17512ae5509de91961c420f982ef12c` **identical and Verified across four runs**.
- Input: `nlp-survey-ch3-d15-b1.txt`, SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, **126,253 prompt tokens** at `n_ctx=131072`. Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS PLE16 main and matching Unsloth Q8_0 MTP draft; `GeneratedTokens=512` in all four runs.
- Common flags: MTP ON, `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, `LLAMA_QSA_NOOP_TRACE=0`, `LLAMA_MTP_DIAG=off`; ROCm **does not use Vulkan QSA union flags**. All relevant policy and DENSE startup decisions `Verified`; the only performance toggle is `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1/1/0` for A1/B1/B2/A2. `EVOX2_ABBA_RUN` also labels the arms for the harness.

## Per-run observations

| Arm | NOOP | PP tok/s | TG tok/s | PP ms | TG ms | Draft accepted/generated |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| A1 | OFF | 275.64 | 20.07 | 458,033.82 | 25,465.98 | 299/423 |
| B1 | ON  | 275.38 | 21.88 | 458,473.97 | 23,357.53 | 297/428 |
| B2 | ON  | 275.68 | 22.05 | 457,969.74 | 23,170.91 | 298/426 |
| A2 | OFF | 272.35 | 21.21 | 463,574.41 | 24,092.92 | 298/425 |
| **OFF mean** | | **273.995** | **20.640** | **460,804.12** | **24,779.45** | variable |
| **ON mean** | | **275.530** | **21.965** | **458,221.86** | **23,264.22** | variable |

Observed TG ON/OFF ratio `(21.965 / 20.640 - 1) * 100 = +6.42%`; TG-time change −1,515.23 ms per 512-token run (−6.11%). PP means differ +0.56%; because NOOP is target **decode** invalidation handling, the PP drift must not be attributed to the optimization. PP+TG mean elapsed computed from *model-reported* timing is 485,583.57 ms OFF and 481,486.08 ms ON, ≈−0.84% (not a validated end-to-end speedup). Process-level elapsed differs from model timings; avoid comparing batch wall times as TG.

## Correctness and interpretation limits

- **All four decoded stdout texts differ even after removing CLI Prompt/Generation speed lines.** This includes **A1 vs A2 (same NOOP OFF)** and **B1 vs B2 (same NOOP ON)**. The difference is genuine generated Japanese text, not merely timing printouts; some divergence appears early in generation. Full-text identity passed for ROCm *short* test and Vulkan 64k/128k/256k, but **does not hold for this ROCm 128k test**.
- Draft accepted/generated counts also vary: 299/423, 297/428, 298/426, 298/425. The acceptance ratios are about 70.686%, 69.393%, 69.953%, 70.118% respectively. Slightly different trajectories can influence performance. A1 TG 20.07 vs A2 21.21 also shows variation without changing NOOP.
- Both ON runs (**21.88 and 22.05**) exceed both OFF runs (**20.07 and 21.21**), a promising trend; however, four runs alone cannot separate that association from nondeterministic output paths, hardware/thermal variation, or sequence effects. This **does not invalidate** the passed native NOOP model/state correctness checks or ROCm 163-token short text-equivalence proof; conversely those tests do not prove long-context ROCm output equality.
- The 128k result should be reported as **provisional ROCm TG benefit**, not a proven +6.42% causal NOOP effect. No r5 layout-rebuild profiler measurement was made in this batch; do not assert exact avoided-kernel or stall time.

## Next action

1. Keep compiled ROCm runtime `b11579-f62ca1cd4` and source unchanged. Measure the existing `qwen38-r5-mtp-noop-rocm-abba.psd1` jobs `rocm-64k` and `rocm-256k` (4 runs each; normal trace OFF, MTP ON, DENSE ON). Confirm identity, output differences, acceptance variations and throughput at each depth.
2. After these runs, close ROCm NOOP as successful native/smoke validation with **qualified** TG observations if nondeterminism persists; decide whether additional ROCm determinism work warrants an independent task. Do not convert this into an unplanned NOOP code rewrite.
3. **Then investigate MTP ON PP overhead** as an independent branch and source/measurement hypothesis rather than mixing in further decode NOOP changes. Stable r5 and frozen DENSE parent stay untouched.
