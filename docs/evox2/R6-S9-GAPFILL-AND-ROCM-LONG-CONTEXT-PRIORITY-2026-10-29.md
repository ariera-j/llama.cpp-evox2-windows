# R6 S9 gap-fill speed matrix and ROCm long-context priority — 2026-10-29

**Evidence scope:** Windows Evo-X2 / Radeon 8060S / UMA 96 GiB, b11908 integrated source `b82243bf0`, verified separate Vulkan and TheRock 10.0 ROCm binaries. This is a retrospective **measurement report and next-research priority**, not a new patch, S8 release sign-off or global flag-default change. G8-3 data were rechecked against the six archived ZIPs (22 runs). The later **21 unattended gap-fill runs + one manual ROCm all-five-enabled diagnostic** were parsed from a single multi-run ZIP (22 runs); **all 44 runs** reported `Status=OK`/`ExitCode=0`. The two groups' ZIPs are listed below; do not double-count the 22-run subfolders in the new archive as a further 22-run batch.

## 1. Why the additional 21 + 1 runs were requested

1. **IQ3 Original, MTP OFF, Vulkan/ROCm 64k:** ensure r6 clean upstream → b11908 integrated-all-OFF does not cause an appreciable regression.
2. **PLE16 IQ3/MTP ON 256k:** fill 256k absolute PP/TG baseline values; obtain the initially missing Vulkan OFF and ROCm OFF/eligible-ON conditions, keeping the earlier G8-5 Vulkan ON run as the control.
3. **IQ3 PLE16 and ROCmFP4 FAST PLE16 with MTP OFF:** separate MTP-on PP overhead from optional flag effects (especially union and common MTP graph changes).
4. **Original Unsloth IQ4 PLE16 and huihui IQ4 PLE16, MTP OFF:** sample all-ON effect vs previously tested all-OFF at real 64k.
5. **Manual ROCm all-five enabled 64k, IQ3 PLE16/MTP ON:** bound the risk of ROCm server launch inheriting Vulkan-oriented environment variables. This was a CLI compatibility/stability smoke **after** the 21-run batch, **not** a full router-mode test.

## 2. Four-column consolidated measured speed inventory

Values are **PP / TG in tokens/s**. `—` means no matching measurement in the reviewed record, not a failed test. Rows separate Original joined PLE vs PLE16, quant, backend, context and MTP state. The four build/config columns are **not** controlled same-model/SW comparisons across every row.

| モデル | Backend | ctx | MTP | r5 upstream | r6 upstream | R6 b11908 OFF | R6 b11908 ON |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: |
| IQ3 Original | Vulkan | 64k | OFF | 269.24 / 25.31 | 339.72 / 25.42 | 344.38 / 25.06 | 343.80 / 25.32 |
| IQ3 Original | Vulkan | 128k | OFF | 179.51 / 23.67 | 268.60 / 23.54 | — | — |
| IQ3 Original | Vulkan | 256k | OFF | 135.41 / 20.02 | 228.89 / 20.30 | — | — |
| IQ3 Original | ROCm | 64k | OFF | 390.73 / 21.18 | 405.24 / 21.86 | 402.08 / 21.79 | 403.97 / 21.38 |
| IQ3 Original | ROCm | 128k | OFF | 292.69 / 17.13 | 303.66 / 17.50 | — | — |
| IQ3 Original | ROCm | 256k | OFF | 193.64 / 12.37 | 200.59 / 12.55 | — | — |
| IQ3 PLE16 | Vulkan | 64k | OFF | — | — | 346.05 / 26.09 | 350.59 / 26.07 |
| IQ3 PLE16 | Vulkan | 128k | OFF | — | — | 270.79 / 24.18 | 311.75 / 24.03 |
| IQ3 PLE16 | ROCm | 64k | OFF | — | — | 402.61 / 21.80 | 403.08 / 21.81 |
| IQ3 PLE16 | ROCm | 128k | OFF | — | — | 300.44 / 17.61 | 300.51 / 17.61 |
| IQ3 PLE16 | Vulkan | 64k | ON | — | — | 319.31 / 32.51 | 358.29 / 33.90 |
| IQ3 PLE16 | Vulkan | 128k | ON | — | — | 248.01 / 25.33 | 322.98 / 30.49 |
| IQ3 PLE16 | Vulkan | 256k | ON | — | — | 202.31 / 16.22 | 301.30 / 25.08 |
| IQ3 PLE16 | ROCm | 64k | ON | — | — | 371.99 / 27.02 | 371.43 / 28.63 |
| IQ3 PLE16 | ROCm | 128k | ON | — | — | 280.50 / 18.83 | 282.24 / 22.64 |
| IQ3 PLE16 | ROCm | 256k | ON | — | — | 184.42 / 10.34 | 184.79 / 15.04 |
| Agention ROCmFP4 FAST PLE16 | Vulkan | 64k | OFF | — | — | 352.79 / 25.73 | 354.99 / 25.87 |
| Agention ROCmFP4 FAST PLE16 | Vulkan | 128k | OFF | — | — | 275.53 / 23.80 | 309.02 / 23.74 |
| Agention ROCmFP4 FAST PLE16 | Vulkan | 64k | ON | — | — | 325.12 / 33.21 | 365.19 / 34.79 |
| Agention ROCmFP4 FAST PLE16 | Vulkan | 128k | ON | — | — | 237.22 / 27.41 | 319.34 / 32.56 |
| Original Unsloth IQ4 PLE16 | Vulkan | 64k | OFF | — | — | 314.08 / 24.72 | 316.76 / 24.27 |
| Original Unsloth IQ4 PLE16 | Vulkan | 128k | OFF | — | — | 250.67 / 22.85 | — |
| huihui IQ4 PLE16 | Vulkan | 64k | OFF | — | — | 313.75 / 24.71 | 317.03 / 24.36 |
| Gemma4 31B QAT Q4_0 | Vulkan | 32k | OFF | — | — | 64.63 / 8.93 | — |
| Gemma4 26B A4B QAT UD-Q4_K_XL | Vulkan | 32k | OFF | — | — | 267.45 / 50.16 | — |

**Scope and interpretation of columns:**

- `r5 upstream` = clean b11517, `r6 upstream` = clean b11875 (upstream b11870 + docs/tools commits). These columns contain **IQ3 Original joined-PLE, MTP OFF** only; source runbooks: [r5 baseline](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md), [r6 S0 baseline](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md).
- `R6 b11908 OFF` = all five optional flags disabled; `R6 b11908 ON` = **Vulkan: five flags ON; ROCm: eligible DENSE+NOOP only**. For 2026-10-29 ROCm runs, Vulkan union, Stage-B and flatten were explicitly `0` even in the 2-flag ON variant. The separate manual all-five ROCm test is reported in §5 and **not substituted into this ON column**.
- G8-3 Vulkan IQ3/FP4 64k/128k uses OFF-vs-ON ABBA means (each 2+2) except FP4 128k, A/B single each. G8-3 ROCm 64k/128k uses DENSE+NOOP OFF-vs-ON ABBA means. 256k Vulkan ON is one older G8-5 run; other newly filled conditions are **one run per variant**. The IQ4/huihui and Gemma all-OFF values come from separate S9 gates.
- 64k / 128k / 256k real-paper Qwen inputs: **61,789 / 126,253 / 255,181 tokens** (same raw fixture SHA for each model cohort); `-ngl 999 -ncmoe 0 -ctk f16 -ctv f16 -fa auto`, one inference at a time, no sustained wrong P-MODE. **The additional MTP-OFF 21-run tests used `-n` as a cap but did not all generate precisely 512 tokens**: 482–670 output tokens depending on model/sampler/EOS; do not interpret TG or wall time as repeated-run estimates with equal generated lengths. The MTP-ON 256k and manual ROCm runs generated 512 tokens.
- Some combined ON results come from different batches/dates and should not be treated as balanced/randomized ABBA comparisons. The performance differences for ~1–2% effects especially need caution.

## 3. Clean-upstream versus integrated operational MTP-on profile (six illustrative comparisons)

Here, `r6 S0` uses **IQ3 Original joined PLE/MTP OFF**, while integrated uses **IQ3 split PLE16/MTP ON**. The input corpus, context and device/backend match, but **model layout, Draft MTP and flags differ**: these percentage differences describe an *operational profile comparison*, **not a causal patch speedup**.

| Backend | ctx | S0 IQ3 Original/MTP OFF | b11908 IQ3 PLE16/MTP ON・最適化ON | PP差 | TG差 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Vulkan | 64k | 339.72 / 25.42 | 358.29 / 33.90 | +5.47% | +33.36% |
| Vulkan | 128k | 268.60 / 23.54 | 322.98 / 30.49 | +20.25% | +29.52% |
| Vulkan | 256k | 228.89 / 20.30 | 301.30 / 25.08 | +31.64% | +23.55% |
| ROCm | 64k | 405.24 / 21.86 | 371.43 / 28.63 | -8.34% | +30.97% |
| ROCm | 128k | 303.66 / 17.50 | 282.24 / 22.64 | -7.05% | +29.37% |
| ROCm | 256k | 200.59 / 12.55 | 184.79 / 15.04 | -7.88% | +19.84% |

- Vulkan has PP and TG improvements across the three measured context sizes in this operational comparison. Vulkan 256k improves to **301.30 PP / 25.08 TG** with MTP ON and all five flags enabled; this remains G8-5 **one-run** stability evidence, not an ABBA 256k speed proof.
- ROCm's optimized MTP-ON PP is **~7–8% below** the clean upstream MTP-OFF Original baseline across 64k–256k, despite improved TG relative to upstream. For 256k, optimized ROCm's **184.79 PP / 15.04 TG** is substantially below integrated Vulkan's **301.30 PP / 25.08 TG**. These are observed backend/profile gaps, **not yet attributed to a single kernel or patch**.
- As context grows from 64k to 256k, ROCm optimized MTP-on PP **371.43 → 184.79** and TG **28.63 → 15.04**; this scaling merits priority attention. The same context-dependent slowdown exists even in upstream MTP OFF (ROCm 64k 405.24/21.86 → 256k 200.59/12.55), so the context slope alone does **not** prove an integration regression.

### Controlled-ish comparisons that help separate causes

| Test | OFF PP/TG | ON PP/TG | Interpretation |
| --- | ---: | ---: | --- |
| IQ3 Original / Vulkan 64k / MTP OFF, b11908 | 344.38 / 25.06 | 343.80 / 25.32 | no material ON regression; r6 upstream 339.72 / 25.42 is close |
| IQ3 Original / ROCm 64k / MTP OFF, b11908 | 402.08 / 21.79 | 403.97 / 21.38 | eligible flags only; r6 upstream 405.24 / 21.86 is close |
| IQ3 PLE16 / Vulkan 64k / MTP OFF | 346.05 / 26.09 | 350.59 / 26.07 | +1.31% PP; TG essentially unchanged |
| IQ3 PLE16 / Vulkan 128k / MTP OFF | 270.79 / 24.18 | 311.75 / 24.03 | **+15.13% PP** with Vulkan union-containing all-ON profile despite MTP OFF |
| IQ3 PLE16 / ROCm 64k / MTP OFF | 402.61 / 21.80 | 403.08 / 21.81 | negligible DENSE/NOOP impact |
| IQ3 PLE16 / ROCm 128k / MTP OFF | 300.44 / 17.61 | 300.51 / 17.61 | negligible DENSE/NOOP impact |
| ROCmFP4 FAST / Vulkan 64k / MTP OFF | 352.79 / 25.73 | 354.99 / 25.87 | small positive single-run effect |
| ROCmFP4 FAST / Vulkan 128k / MTP OFF | 275.53 / 23.80 | 309.02 / 23.74 | **+12.16% PP**, TG essentially unchanged |

**MTP ON vs OFF with all-ON Vulkan IQ3 PLE16:** 64k PP 350.59 (MTP OFF) vs 358.29 (MTP ON); 128k PP 311.75 vs 322.98. With all-flags-OFF Vulkan: 64k 346.05 vs 319.31, 128k 270.79 vs 248.01. Thus the MTP-related prefill penalty in the unoptimized condition is roughly 8% but is compensated/overcome by the measured ON profile. **Runs were collected on different dates and the results do not identify which internal patch caused the recovery.**

**ROCm 256k MTP ON:** DENSE+NOOP OFF **184.42 PP / 10.34 TG**, ON **184.79 PP / 15.04 TG**. TG is **+45.45%** in this single A/B pair, while PP remains essentially flat. Draft acceptance differed (OFF 272/476, ON 289/441), so the TG change is associated with the total profile, not proven independent of acceptance differences. The user asked to prioritize improving **both long-context PP and TG** further.

**IQ4 and huihui 64k MTP OFF Vulkan:** original Unsloth IQ4 all-OFF 314.08/24.72 vs all-ON 316.76/24.27; huihui all-OFF 313.75/24.71 vs all-ON 317.03/24.36. Single-run effects are approximately +1% PP/-1–2% TG, **no demonstrated material speedup**; do not extrapolate S8 opt-in support to production IQ4/huihui profiles.

## 4. The standalone manual ROCm all-five-enabled safety smoke

- **Archive member:** `20261029-154552-717-cli-rocm-b11908-ctx65536-f6a562181b01` inside the multi-run ZIP below. b11908 ROCm CLI SHA256 `1bbd4a5102b6181d8de92faf2d42e49f96ba2ad4b04b7c7f9e6aafc168d322b1`; runtime artifact status `Verified`.
- Model IQ3 PLE16 / Draft Q8_0 (main 49/49 and Draft 50/50 GPU layers), actual **61,789 prompt / 512 generated**, `truncated=0`; **PP 390.63 / TG 29.42 tok/s**, acceptance **293/435**, status OK, exit code 0.
- Five flag values: `GGML_VK_QSA_UNION=1`, `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1`, `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`, `LLAMA_MTP_EH_PROJ_FLATTEN=1`. DENSE omitted and NOOP enabled were corroborated by the existing trace/decision evidence. **The flag values for Stage-B/flatten do not themselves establish numerical Draft K/V equivalence**; `GGML_VK_QSA_UNION` is Vulkan-specific.
- P-MODE start/end Performance and ADLX high-load **119.7 W Performance-like**, peak GPU temperature 81°C, high-load VRAM clock minimum ~956 MHz. No recorded OOM, reset, sustained paging, or nonsensical repeated output. ROCm MTP ON under all-five **CLI smoke PASS**, not server/router-model-switch PASS.
- An extreme transient free-RAM dip was observed during ROCm model loading; RAM then recovered. For future model-router runtime, retain independent memory/VRAM/load-unload gates; don't infer 24-hour multi-model reliability from one CLI completion.
- **Operational consequence:** user intends llama-server router-mode plus built-in WebUI or Open WebUI and may accidentally inherit Vulkan env vars in ROCm's process. This single smoke demonstrates no immediate failure for the tested backend/model/context, but production presets should still **sanitize per-backend flags**, with explicit logging/validation of the effective environment.

## 5. Next optimization priority (user decision, 2026-10-29)

**Priority 1 / next investigation: ROCm HIP long-context PP **and** TG, especially 128k–256k IQ3 PLE16 + MTP ON.** This overrides the generic pre-integration priority ordering as a *post-integration research focus*, **without changing the frozen S8 flags or the already completed integration gate**.

A staged research/benchmark approach, with **no new code or automatic wide stress suite** authorized yet:

1. **Freeze comparable controls** at b11908, TheRock 10.0, known binary/DLL SHA, 96GiB UMA, Performance mode, same GGUF/PLE layout, fixed paper SHA, KV f16, Flash Attention setting, DraftMax and GPU placement. Use matching 64/128/selected 256k inputs and record both PP time/throughput and TG time/throughput; keep MTP OFF vs ON isolated.
2. **Profile representative ROCm 128k and 256k** (selected RGP/HIP profiling plus host timings). Separate QSA gather/compaction or FA/GDN kernels, MoE/quant matmul, Draft prefill/rollback/state synchronizations, memory copies/host stalls, kernel dispatch and cache scaling. Measure *time share* before picking a port or rewrite; do not label any candidate as the proven bottleneck without evidence.
3. **Investigate the retained COMMON-005 HIP gathered-K/V compact-QSA idea** and existing HIP FA/GDN/selected-index paths *if* profiling reveals that they account for enough long-context time. Confirm b11908 upstream overlap first; compare one opt-in change in a separate branch, with old known-good baseline untouched.
4. **Distinguish MTP-on PP cost from broader long-context slope.** ROCm MTP OFF DENSE/NOOP has essentially zero effect, while MTP ON's 256k DENSE/NOOP TG gain is significant but still relatively slow. Diagnose acceptance, Draft work, target graph shape, and buffer/host overhead rather than claiming MTP itself causes all the long-context loss.
5. After safe one-at-a-time tests, decide whether to add a patch or leave it DEFER based on same-model/backend/fixture ABBA, total wall time, acceptance, stability and correct output. Keep prior ROCm non-deterministic output caveat, numerical Draft K/V parity DEFER, and **avoid the unsafe broad ROCm `FLASH_ATTN_EXT` backend test**.

**Not promoted now:** extra Vulkan speed tweaks (CONCAT/union/FA), broad MoE-expert routing study, unverified ROCmFP4 HIP kernels, source repin or model-router deployment. Those remain candidates in the [post-integration research plan](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md), but the next *performance* investigation is ROCm long-context.

## 6. Raw artifact references / provenance

| Evidence | SHA256 | Description |
| --- | --- | --- |
| `20261029-154552-717-cli-rocm-b11908-ctx65536-f6a562181b01.zip` | `de7ac040f8e7d8335cb6a3e1ea3acd64761d8bf8973a9e97bb152583fe21c9d9` | **Combined archive: 21 unattended distinct runs + one manual ROCm all-five CLI run**, 22 `result.json`, all OK |
| `20261028-143814-285-cli-vulkan-b11908-ctx65536-8b2eee67ec4c.zip` | `975f373ea5e4c8d2da08017f303c384a346dd320a3f97bf4264592911fd22d81` | G8-3 2026-10-28 same-binary performance A/B evidence |
| `20261028-152717-748-cli-vulkan-b11908-ctx131072-8ce8ee1588a9.zip` | `87b9a269cc3e8d2f049505627efbbf4dfed1c283f4cc0a3d585043027238ec54` | G8-3 2026-10-28 same-binary performance A/B evidence |
| `20261028-161137-494-cli-vulkan-b11908-ctx65536-7755526e6e86.zip` | `8d9ed4f4c12e0b8024a253cf2df9782aa42c1bbe09835b32b54f4c6333ea9b90` | G8-3 2026-10-28 same-binary performance A/B evidence |
| `20261028-163232-295-cli-vulkan-b11908-ctx131072-46c6f243f85a.zip` | `3fba8b2cd89379bef3c0984635bcbe69010ba5b6290c920837dfcc9c1d5ea473` | G8-3 2026-10-28 same-binary performance A/B evidence |
| `20261028-171442-999-cli-rocm-b11908-ctx65536-7c8e42376fab.zip` | `d46ab6cd286fee1b97c75a1f56cc3274c85826c13b33dc732bd8fecabd046493` | G8-3 2026-10-28 same-binary performance A/B evidence |
| `20261028-181717-947-cli-rocm-b11908-ctx131072-be1114771ae7.zip` | `d7662a6799c3b707d11b17558eecfa0bb38731e8642f5e2bbc35367190842c78` | G8-3 2026-10-28 same-binary performance A/B evidence |

The six G8-3 archive names above are listed with original Windows filenames (uploads had an appended `(1)`), while SHA256 values refer to the uploaded identical-content ZIP bytes. These six archives collectively include **22 G8-3 runs**. Main ZIP names here are provenance locators; GGUF weights, raw text inputs, private `local.psd1` and megabyte-scale console/telemetry logs are **not committed**.

**Other source documents:** [S8 result/flag freeze](R6-S8-COMBINED-RESULTS-2026-10-28.md), [S9 Qwen IQ4 results](R6-S9-QWEN-IQ4-RESULTS-2026-10-29.md), [G9-4 Gemma4 results](R6-S9-GEMMA4-G9-4-RESULTS-2026-10-29.md), [S0 clean baseline](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md). Latest GitHub docs HEAD is *not* the frozen measured b11908 binary source; avoid interpreting docs-only commits as a new executable build.
