# r5 MTP-NOOP-001 — ROCm 64k/128k/256k validation closure (2026-10-12)

**Verdict:** native state/rollback/policy and 163-token short real-MTP A/B proof all PASS. Three-depth normal ROCm ABBA **12/12 OK**, NOOP ON faster in TG in both ON repetitions than either OFF repetition at each depth. **Long-context ROCm generated text and draft acceptance vary even within identical-condition A/A and B/B repeats; all TG gains remain observational/qualified**, not deterministic proof of equivalence or a fully isolated speedup. Keep separate from [Vulkan three-depth fully text-matched validation](R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md).

## Evidence, model, environment and run identities

- Final user-uploaded 64k+256k ZIP: `20261012-205808-054-qwen38-r5-mtp-noop-rocm-abba.zip` **SHA256 `93268e99b7d4eb563b23b46308e9e745c6f52417c7433632004cd3be00f04b0a`**; covers **20:58:08 to 22:56:30 JST**, 118.38 minutes, 8/8 OK, `StoppedEarly=false`. Prior 128k ZIP: `20261012-200801-743-qwen38-r5-mtp-noop-rocm-abba.zip` SHA256 `b1edf09bb0f2b66bc3f5332ece56088312761b92a810bf48aff7282a39064624`, 4/4 OK; detailed 128k evidence at [ROCm 128k checkpoint](R5-MTP-NOOP-ROCM-128K-2026-10-12.md).
- Actual compiled ROCm runtime (all 12 runs): `llama-cli.exe` b11579, source commit `f62ca1cd4`, **SHA256 `1a3ef3de0d9cb83a1278fadf060baf1c36cbcfc16c9066a330d0692877f5293e`**, runtime artifact digest **`6bb0ee22c133f1b44226a6f743299a11c17512ae5509de91961c420f982ef12c`**, `RuntimeArtifactStatus=Verified`, AMD Radeon 8060S/gfx1151 and Clang 23.0.0 Windows. Newer documentation commits do not change the compiled runtime.
- Main Qwen3.8-Flash-Next Unsloth UD-IQ3_XXS PLE16 GGUF + Unsloth MTP Q8_0 draft. `conditions.json` holds original absolute paths/byte lengths; neither GGUF's full-file SHA was recorded (`Sha256=null`), so do not invent model hashes. EVO-X2 Windows, manual 96GB UMA condition.
- 64k: `nlp-survey-ch3-d7-b1.txt` SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, 61,789 input tokens, `n_ctx=65536`. 128k: 126,253 input tokens `n_ctx=131072` (see prior checkpoint). 256k: `nlp-survey-ch3-d31-b1.txt` SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, 255,181 input tokens, `n_ctx=262144`. All produced 512 tokens; `--temp 0 --seed 1234`, draft-max=2, KV=f16, batch=2048 / ubatch=1024, MTP ON, `LLAMA_MTP_SKIP_DENSE_INDEXER=1` in all arms.
- `LLAMA_QSA_SKIP_NOOP_INVALIDATION` = `0,1,1,0` (A1 B1 B2 A2); `LLAMA_QSA_NOOP_TRACE=0`, `LLAMA_MTP_DIAG=off`, Vulkan-specific QSA union env variables unset. Every run had NOOP decision `Verified`, DENSE draft-indexer omission `Verified`, exit0; all four per-depth arms use the same executable/digest. `EVOX2_ABBA_RUN` differed as identification labels, not inference mechanism.

## Detailed new ABBA (PP/TG units tok/s, ms timings from llama-cli)

| Depth | Arm | NOOP | PP | TG | PP ms | TG ms | Draft accepted/generated |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 64k | A1 | OFF | 365.75 | 27.04 | 168,939.51 | 18,898.71 | 292/436 |
| 64k | B1 | ON | 366.81 | 28.28 | 168,448.22 | 18,068.45 | 301/420 |
| 64k | B2 | ON | 366.96 | 28.48 | 168,381.04 | 17,941.76 | 301/419 |
| 64k | A2 | OFF | 365.94 | 27.25 | 168,849.76 | 18,751.40 | 297/426 |
| 256k | A1 | OFF | 182.00 | 13.99 | 1,402,115.99 | 36,525.54 | 296/430 |
| 256k | B1 | ON | 182.41 | 14.77 | 1,398,925.63 | 34,608.63 | 290/440 |
| 256k | B2 | ON | 182.41 | 14.91 | 1,398,964.45 | 34,281.86 | 292/437 |
| 256k | A2 | OFF | 182.34 | 13.47 | 1,399,462.91 | 37,932.39 | 290/440 |

## Aggregated ROCm NOOP TG measurements (2 repeats/arm at each depth)

| Context | PP OFF mean → ON mean (tok/s) | PP Δ | TG OFF mean → ON mean (tok/s) | TG Δ | TG time mean OFF → ON | Draft/decoded output stability |
| --- | --- | ---: | --- | ---: | --- | --- |
| 64k | 365.845 → 366.885 | +0.28% | 27.145 → 28.380 | **+4.55%** | 18,825.06 → 18,005.11 ms (−0.82s) | 4 distinct texts/acceptances |
| 128k | 273.995 → 275.530 | +0.56% | 20.640 → 21.965 | **+6.42%** | 24,779.45 → 23,264.22 ms (−1.52s) | 4 distinct texts/acceptances |
| 256k | 182.170 → 182.410 | +0.13% | 13.730 → 14.840 | **+8.08%** | 37,228.97 → 34,445.25 ms (−2.78s) | 4 distinct texts/acceptances |

OFF and ON are arithmetic means of the two matching normal ABBA arms. The percentage refers to **TG token rate** (not time-saved percentage). At 256k, TG-rate +8.08% and TG-time −7.48% are different metrics. PP is slightly higher ON in these runs, but this is within possible order/trajectory drift and **not proof of a PP code improvement**. Prompt evaluation dominates fresh 64k/128k/256k PP+TG latency, and no cache reuse was measured. No r5 ROCm GPU-kernel trace of saved layout rebuild work was captured, so do not infer kernel-level savings.

## Correctness and acceptance boundary

- All **four raw `stdout.log` files differ at 64k and at 256k** even when removing the printed CLI speed line. This also holds within identical settings (A1 vs A2; B1 vs B2); it is not merely speed metadata. Some raw stdout captures contain malformed UTF-8 byte sequences associated with console/text capture; compare original bytes/text carefully and do not claim fully validated answer quality solely from stdout hashes. The draft accepted/generated paths differ in every 64k run and 256k run (though some counts coincide without identical text).
- 128k already demonstrated same-arm nondeterminism, so this is a **ROCm deep-context reproducibility limitation**, consistent with prior DENSE-only observations. One cannot conclusively attribute observed +4.55/+6.42/+8.08% solely to NOOP while accepted-token paths vary. A broader ROCm numerical-equivalence study may be started separately if needed for future release gates.
- Native correctness gate: test-qsa-noop-policy / test-qsa-noop-invalidation PASS, 524 logits/NextN-hidden comparisons exact, target stale suppression 67/67 unchanged removals and preservation 54/54 true removals. Short real-MTP ROCm A-normal/B-normal/A-proof/B-proof 4/4 PASS, matching text and acceptance 74/106, trace 34 suppressions and 20 real invalidations retained. See [implementation record](R5-MTP-NOOP-IMPLEMENTATION-2026-10-12.md). These do **not** establish deterministic equality for 61k–255k prompts.

## Closure and next work

1. **NOOP-001 Vulkan** has matched long-context generated text + draft acceptance and TG wins at 64/128/256k; **NOOP-001 ROCm** has native/short correctness and consistent normal TG association with qualified long-context nondeterminism. Keep NOOP opt-in and do **not** automatically promote to stable/integrated runtime. Real-world application output QA remains separate.
2. Conclude NOOP research for now, preserving compiled source SHA and raw ZIPs externally. **Next: isolate MTP ON PP overhead** on new diagnostic-only investigation branch/plan, choose clean controls/baselines before changing any kernels. ROCm temp0 nondeterminism is separate research.
3. Copy finalized docs selectively to `r5/upstream-refresh-20261009` as **documentation only**: no cherry-pick/merge of source, tests or benchmark scripts. The pinned r5 stable source must remain unchanged. Update its `PATCHES.md` to distinguish *source in r5 stable* from *validated isolated research branches*, and keep roadmap/README links pointing to this report.
