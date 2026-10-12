# r5 MTP-NOOP-001 Vulkan final validation — 2026-10-12

**Result: VULKAN VERIFIED for the tested main/draft models and single-sequence contexts; ROCm remains untested.** This note records the *user-supplied* Windows/Evo-X2 ZIPs, inspected on 2026-10-12. It is **not** a claim of a release, broadly generalized model correctness, or ROCm performance.

## Source, scope, and controls

- **Repository branch:** `investigation/r5-mtp-noop-20261012`. The **compiled source/runtime** carries `b11577-b84d18870`; the code/plan at `b84d18870d3f0784df9860d477a755e9d8192feb` is the validation baseline. Subsequent record-only commits do not recompile the executable.
- **Unchanged comparison binary:** `llama-cli.exe` SHA256 `0239c8cddba05651efd30d95f25f4f592ab6abbde2638a93866a45459755ade8`; runtime artifact digest `e75619615cd7694bbfc1807071f9890c64be92aed8e824441ec174213bfe1e2c`; Vulkan Windows, compiler and driver details in raw conditions/manifest ZIP.
- **Model:** Unsloth PLE16 Qwen3.8-Flash-Next main (UD-IQ3_XXS GGUF) + Unsloth MTP draft Q8_0 GGUF. Same GGUF identities within each matrix, same input file within each depth. Hardware label Evo-X2 UMA 96GB; **model/driver SHAs are retained in raw conditions JSON**.
- **Workload:** 61,789 (64k), 126,253 (128k), 255,181 (256k) prompt tokens. Each run generated 512 tokens, `--temp 0 --seed 1234 --ignore-eos`, f16 target/draft KV, `-b 2048 -ub 1024 -t 4 -tb 4 -ngl 999 -ncmoe 0`, draft max2/min0, no prompt cache or ctx checkpoints.
- **Fixed:** MTP ON, `LLAMA_MTP_SKIP_DENSE_INDEXER=1` (omit ratio-zero MTP draft indexer), Vulkan QSA union ON with min KV=32768, `LLAMA_MTP_DIAG=off`, `LLAMA_QSA_NOOP_TRACE=0`.
- **Only tested variable:** `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1/1/0` for **A1/B1/B2/A2** respectively. No MTP-OFF run was needed for this NOOP-isolated comparison. Neither the target indexer nor r5 pool/attention/recurrent layout code was disabled.
- **Batch status:** 128k matrix 4/4 OK (12:37–13:09 JST); 64k+256k matrix 8/8 OK (13:20–14:54 JST); no stopped-early run, exit0, runtime `Verified`, policy evidence `Verified`, DENSE draft omission evidence `Verified` in all 12.
- **Output equivalence:** for each depth, the four `stdout.log` files become **exactly identical after normalizing only the CLI printed `[ Prompt: ... | Generation: ... ]` speed line**. Acceptance and generated-token count also match across the four runs of each depth; separate depths have different text and acceptances, as expected.

## ABBA: every timed run (PP/TG tok/s)

| Depth | Arm | NOOP | PP tok/s | TG tok/s | PP ms | TG ms | Accepted/generated draft |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| 64k | A1 | OFF | 336.42 | 31.41 | 183,663.87 | 16,266.42 | 295/430 |
| 64k | B1 | ON | 335.84 | 32.04 | 183,981.47 | 15,949.06 | 295/430 |
| 64k | B2 | ON | 334.62 | 32.05 | 184,652.03 | 15,943.41 | 295/430 |
| 64k | A2 | OFF | 335.31 | 31.36 | 184,271.69 | 16,293.73 | 295/430 |
| 128k | A1 | OFF | 303.89 | 26.49 | 415,455.92 | 19,288.66 | 295/429 |
| 128k | B1 | ON | 303.24 | 28.81 | 416,346.36 | 17,735.24 | 295/429 |
| 128k | B2 | ON | 303.49 | 28.74 | 416,009.99 | 17,781.30 | 295/429 |
| 128k | A2 | OFF | 303.40 | 27.43 | 416,120.80 | 18,628.08 | 295/429 |
| 256k | A1 | OFF | 266.33 | 21.07 | 958,154.52 | 24,250.83 | 300/421 |
| 256k | B1 | ON | 265.98 | 24.14 | 959,407.00 | 21,171.87 | 300/421 |
| 256k | B2 | ON | 265.40 | 24.08 | 961,495.33 | 21,220.56 | 300/421 |
| 256k | A2 | OFF | 265.74 | 21.08 | 960,247.80 | 24,236.43 | 300/421 |

Means are arithmetic averages of two timed **normal** A arms and two timed **normal** B arms. `+%` means (mean ON TG / mean OFF TG − 1) ×100; PP delta is the same calculation for PP rate. Times are model-reported timings, not total per-process elapsed including loading.

| Context | PP OFF→ON tok/s | PP rate Δ | TG OFF→ON tok/s | TG rate Δ | TG-time saved / 512 tokens | PP+TG ms OFF→ON |
| --- | --- | ---: | --- | ---: | ---: | --- |
| 64k | 335.865→335.230 | −0.19% | 31.385→32.045 | **+2.10%** | 333.84 ms | 200,247.86→200,262.98 (**+15.12 ms**, effectively unchanged) |
| 128k | 303.645→303.365 | −0.09% | 26.960→28.775 | **+6.73%** | 1,200.10 ms | 434,746.73→433,936.45 (**−810.28 ms**, −0.19%) |
| 256k | 266.035→265.690 | −0.13% | 21.075→24.110 | **+14.40%** | 3,047.42 ms | 983,444.79→981,647.38 (**−1,797.41 ms**, −0.18%) |

**Interpretation:** NOOP yields increasingly large **decode/TG** benefit as KV grows; PP does not improve in these runs. This is consistent with avoiding repeated unnecessary target-indexer stale-layout invalidation, but no r5 GPU-kernel profiler was used in these runs, so do **not** claim measured layout-kernel savings from the ABBA numbers alone. Both B arms beat both A arms at each depth. A1 vs A2 at 128k differs somewhat, so the ABBA means, not a single run, are the reference. Fresh-prompt total PP+TG improvement remains small because 64k–256k PP dominates.

## Earlier correctness gates on the identical Vulkan build

1. **SourceOnly PowerShell:** passed after fixing an interpolated `$kind:` string and a mismatched ROCm plan build key in the r5 investigation branch at `b84d18870`.
2. **Native report:** `20261012-122056-303-qsa-noop-invalidation.zip`, newest report `Status=Complete`, `SourceChecks=Passed`, `PolicyTest=Passed`, `ModelTest=Passed`, `BuildIdentity.Status=Verified`. Model/state native test exercised target safety, rollback/restore, logits and NextN hidden; earlier review counted 524 pairwise output checks with NMSE=0 and target trace suppressions where cell count remained unchanged. Native tests explicitly verify real deletion still marks stale and a preexisting stale marker is preserved.
3. **Short real MTP:** `20261012-122732-873-qwen38-r5-mtp-noop-check.zip`, A-normal/B-normal/A-proof/B-proof **4/4 OK**, 163 input tokens, 128 generated, identical text, draft acceptance **69/116** in all four. Trace-proof runs demonstrate 26 unchanged-membership suppressions ON versus 26 stale marks OFF; 33 real removals remain marked in both. *Do not treat the first short A-normal's low PP/TG as a feature speedup*: warm-up/run-order dominates this tiny sample.

## Raw ZIP artifacts (retained by tester, not added to Git)

| Run/batch ZIP | Content | SHA256 |
| --- | --- | --- |
| `20261012-122056-303-qsa-noop-invalidation.zip` | Native/source/model policy report; previous SourceOnly failed attempts also archived | `5f4d6c63f50e2daed67aee0da8a79159a5b17779a45b701f8a4a37ee0d68dc9a` |
| `20261012-122732-873-qwen38-r5-mtp-noop-check.zip` | Short A/B + trace proof | `88efe60c32fd53545d06053119f7ec81a0c9a5cadce92a65f8ed13db7be25739` |
| `20261012-123715-904-qwen38-r5-mtp-noop-abba.zip` | 128k A1/B1/B2/A2, four runs | `dcce7673f600c69ba672e01bc78b6bf935f3a6532c6d84dd0a650d20de15ecc0` |
| `20261012-132038-024-qwen38-r5-mtp-noop-abba.zip` | 64k and 256k ABBA, eight runs | `da14a5bb63605cdc31116f5352e8286e8df29a77303b1b708838432b27acc945` |

These ZIPs contain `matrix-plan.json`, `matrix-result.json`, each child `conditions.json`/`result.json`, stdout/stderr and resource measurements. Store raw logs and model/driver fingerprints externally; this Git record intentionally contains only reproducible summaries/hashes.

## Completion decision and next sequence

- **Vulkan NOOP-001 complete for the tested mode**; leave NOOP opt-in default OFF, preserve the exact validated binary and DENSE-only source. No stable merge/release promotion.
- **Next = ROCm NOOP-001** on the same isolated branch: compile a separate Windows ROCm binary, rerun native policy/model/rollback gate, short real MTP ON A/B, then 128k ABBA before optional 64k/256k. Temp0 ROCm output and acceptance varied even within *identical setting* DENSE-only runs; record matched and repeated controls rather than assuming Vulkan determinism.
- **After ROCm = PP analysis workstream** (separate question/branch), concentrating on the cost of enabling MTP during prompt processing and target vs draft prefill, not on the now-validated TG optimization. Profiling hypothesis and baseline/source selection precede coding changes.
