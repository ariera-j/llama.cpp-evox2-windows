# r2 vs r5 Vulkan MTP TG: matched 64k/128k ABBA — 2026-10-11

**Scope: TG investigation only.** User decision (2026-10-11): treat r3's *MTP OFF* full-context TG pooled-cache regression as addressed by COMMON-004/upstream r4/r5, **do not reopen it now**; defer the **MTP ON PP penalty** until the MTP ON TG study reaches a stopping point. Do not mix these three questions in a single optimization A/B. **No code changes or performance patch port has been authorized by this report.**

## r2 fresh ABBA data and runtime identity

- User archive: \`20261011-182831-abba.zip\` (74 ZIP members); **SHA256 \`49406bb5e7b652469b0934d4826aea445243663a233ce5e4e28db7b9a7396b2d\`**. Contains eight \`result.json\`, \`conditions.json\`, native stdout/stderr/output, resource logs, and the summary. **Raw archive is external to Git**. 2026-10-11 **18:28–19:28 JST**. 8/8 \`Status=OK\`, \`ExitCode=0\`, each **512 generated tokens**.
- Executed historical binary is **r2 Vulkan** at \`C:\llama-build\llama.cpp-evox2-windows-r2\build-llvm20-r2\bin\Release\llama-cli.exe\`. Embedded \`--version\` = \`version: 0.3.0-dev (build 10813, commit ee245db-evox2-r2)\`; **Clang 20.1.8**. **Executable SHA256 \`daef251a001809a48cb337cafe858f10fc8d36829302267e2f88248b03e189f5\`**. Beware the 2026-09-18 historical r2 pair used **b10811**, not this binary.
- The **r5 measurement harness** was invoked from checkout \`f8d24494fcacee01f8c9858595c3e778a1698d11\` but its \`GitIdentity\` is **the harness's r5 source, NOT the executed r2 source**. Old r2 predates project build manifests: \`RuntimeArtifactStatus=MissingManifest\`, no DLL-group runtime digest, \`BuildNumber=null\` and \`build-unknown\` derived from r5 harness regex failing on suffixed \`ee245db-evox2-r2\`. These are **metadata limitations, not execution failures**, and should not cause a synthetic manifest to be added to r2. The executable SHA and embedded version identify the binary; DLL integrity across sessions was not established.
- Main GGUF: Unsloth PLE16 \`Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf\` (81,961,816,672 bytes); MTP ON: Unsloth \`mtp-Qwen3.8-Flash-Next-Q8_0.gguf\` (4,137,429,120 bytes). Neither GGUF SHA recorded. Input at 64k \`nlp-survey-ch3-d7-b1.txt\`, **61,789 tokens**, SHA256 \`2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751\`; 128k \`nlp-survey-ch3-d15-b1.txt\`, **126,253 tokens**, SHA256 \`182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466\`.
- Actual CLI settings preserved: \`-c 65536/131072 -ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 1024 -fa auto -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --jinja --single-turn --ctx-checkpoints 0t --seed 1234 --ignore-eos -n 512\`. All eight \`GGML_VK_QSA_UNION=1\`, \`GGML_VK_QSA_UNION_MIN_KV=32768\`; no Vulkan perf logger or union stats enabled. ON: \`-md\` draft, \`--spec-type draft-mtp --n-gpu-layers-draft 999 --spec-draft-n-max 2 --spec-draft-p-min 0 --cache-type-k-draft f16 --cache-type-v-draft f16\`. No adaptive drafting. Same binary per arm, no per-run source edits. Conditions stored in ZIP.

## Eight native run results (ABBA: OFF→ON→ON→OFF at each depth)

| Context | Arm | PP tok/s | TG tok/s | PP sec | TG sec | Accepted/drafted |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 64k | A1 OFF | 294.39 | 23.72 | 209.885 | 21.542 | — |
| 64k | B1 ON | 277.24 | 26.26 | 222.873 | 19.458 | 258/364 (70.879%) |
| 64k | B2 ON | 276.89 | 26.37 | 223.155 | 19.376 | 260/367 (70.845%) |
| 64k | A2 OFF | 293.13 | 23.70 | 210.789 | 21.562 | — |
| 128k | A1 OFF | 251.87 | 22.11 | 501.257 | 23.116 | — |
| 128k | B1 ON | 235.67 | 25.94 | 535.719 | 19.698 | 275/356 (77.247%) |
| 128k | B2 ON | 236.62 | 25.31 | 533.568 | 20.191 | 269/358 (75.140%) |
| 128k | A2 OFF | 251.93 | 21.92 | 501.150 | 23.316 | — |

### Arithmetic means and depth slope

| r2 Vulkan | 64k OFF | 64k ON | 128k OFF | 128k ON |
| --- | ---: | ---: | ---: | ---: |
| TG tok/s | **23.710** | **26.315** | **22.015** | **25.625** |
| ON advantage within context | — | **+10.99%** | — | **+16.40%** |
| Acceptance | — | 70.862% | — | 76.194% |
| PP tok/s (context only; PP study parked) | 293.760 | 277.065 | 251.900 | 236.145 |
| Native TG duration s | 21.552 | 19.417 | 23.216 | 19.944 |
| Native PP+TG duration s (context only; no PP optimization) | 231.889 | 242.431 | 524.420 | 554.588 |

- **64k→128k OFF TG −7.15%; ON TG −2.62%.** The r2 **ON relative TG benefit increases** with depth, unlike r4/r5 native MTP. This is repeatable in both arms at the tested lengths, but is not a code-only causal experiment.
- r2 acceptance also increases from **70.86% to 76.19%**, whereas the matched r5 Vulkan arms recorded **68.61% and 68.77%**. Different draft acceptance can explain *part*, not proven all, of the relative TG trend. Do not assume output text, accepted sequence, or logits match across versions.
- Two repetitions per arm, no confidence intervals; generated length fixed but generated **contents are not a controlled token trace**. No forced-rejection or bitwise target equivalence gate was run in this ABBA.

### Cross-generation TG comparison (relative only)

| Vulkan / model same PLE16 + Unsloth Q8_0 | 64k OFF | 64k ON | ON gain | 128k OFF | 128k ON | ON gain |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **r2 b10813** fixed temp0 / 512 | 23.71 | 26.315 | **+10.99%** | 22.015 | 25.625 | **+16.40%** |
| **r4 initial** (temp0.2 / 512) | 25.75 | 29.84 | **+15.9%** | 23.27 | 23.02 | **−1.1%** |
| **r5 b11560** fixed temp0 / 512 | 26.135 | 28.885 | **+10.52%** | 24.140 | 23.475 | **−2.75%** |

r5 observations: [r5 Vulkan ABBA](R5-MTP-VULKAN-64K128K-ABBA-2026-10-11.md). r4 historical: [initial native MTP overnight](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md). With MTP OFF, 64k→128k r2/r5 Vulkan depth slopes are close (r2 **−7.15%**, r5 **−7.63%**), so **the chosen problem is the MTP ON extra/depth-dependent TG cost, not MTP OFF regression**.

## Source distinction: r2/r3 vs r4/r5 MTP memory

Inspected in this repo:
- \`r2/legacy\` and \`r3/upstream-first\` \`src/llama-model.cpp\`: \`mtp_on_hybrid_qwen\` excludes QWEN4EXP MTP from hybrid memory construction and selects a **plain \`llama_kv_cache\` filtered to NextN layers**. \`r2/legacy\` \`src/models/qwen4exp.cpp::graph_mtp\` uses \`build_attn_inp_kv()\` for the **dense** draft. Hence the r4 unused hybrid-indexer CPU layout mechanism did **not** exist in this r2/r3 Qwen4Exp draft path.
- \`r4/upstream-refresh-20261002\` and r5 \`src/llama-model.cpp\`: upstream-native QWEN4EXP MTP uses **\`llama_memory_hybrid_idx\`**; the default indexer filter selects NextN even if the particular block has **compression ratio=0**. This leaves an unused draft indexer/layout maintenance path. r4 **MTP-DENSE-001** (opt-in \`LLAMA_MTP_SKIP_DENSE_INDEXER\`) omits that indexer **only for validated QWEN4EXP MTP, single NextN block and ratio 0**, preserving the hybrid wrapper, attention KV and necessary rollback. It **brings the memory behavior closer to r2**, but is not an exact r2 port. r4 Vulkan 256k ON A/B TG **15.220→20.185 (+32.62%)**, 512-token output and acceptance matched; PP virtually unchanged. [Evidence](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md).
- r2 target pooled key path uses **\`pooled_w\` watermark** and \`pooled_rm()\` (only rolls back the affected block watermark), whereas r4/r5 target uses **CPU \`kpool_layout_update()\` + stale markers**. r4 **MTP-NOOP-001** (opt-in \`LLAMA_QSA_SKIP_NOOP_INVALIDATION\`) suppresses stale invalidation only on *no-op* sequence removal for narrowly qualified **target DEFAULT** QSA context. It does **not** remove target QSA or alter real suffix removals, and is **not a r2 patch**. After MTP-DENSE-001 r4 256k Vulkan ON TG **20.205→22.830 (+12.99%)**, output/acceptance matched; PP unchanged. [Evidence](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md).
- In r2's \`src/models/qwen4exp.cpp\`, the grouped-union hint requires **at least 32 query rows**. r5 Vulkan implementation can dispatch QSA union for **2–4096 query rows** when its other eligibility tests pass. MTP verification typically batches up to 3 target queries with DraftMax=2. **This is a plausible third difference to isolate**, not verified as the source of any r5 TG slowdown; an ordinary \`qsa-union active\` log during PP does not establish MTP verification use. Counter or short-query-only switch must preserve main PP union.
- r4 measures suggest major omitted draft and target-layout TG costs. They **do not prove** those two differences completely explain r2's 128k TG trend. QSA/verification behavior and acceptance may contribute.

## Research decisions, next gates

1. **Now:** r5 Vulkan 128k **MTP-DENSE-001** toggle-only A/B with MTP ON in **both** arms and strict correctness tests, then separate **MTP-NOOP-001** toggle-only A/B with dense omission on in both arms. Compare TG, acceptance, output/rollback; no PP-centric change. Prefer isolated branch for each bounded source change; source stable r5 remains unchanged. A 256k gate is justified if 128k passes and memory permits.
2. If r5 ON still loses TG relative to OFF, isolate r2 vs r5 **short-query Vulkan grouped-union verification** with a narrow instrumentation/dispatch guard rather than global union OFF. Additional probes: draft dense attention and catch-up, target real suffix rebuilds; attribute only measured costs.
3. **Defer/park:** fresh-prompt MTP PP overhead (present since r2; not fixed by r4 TG patches); MTP OFF long-depth TG (r3 COMMON-004 fixed the original pooled-summary recomputation regression; r4/r5 upstream functionality already covers it); r3 COMMON-005 compact decode (single-token only, *not* native 2–3 token MTP verification); original r2 draft MTP-QSA prototype (no measured PP gain).
4. **Future integrated snapshot:** bring AgentionAI ROCmFP4-FAST weights and MTP, with applicability/correctness gates in [Agention MTP compatibility review](R5-MTP-AGENTION-FP4-INTERACTION-2026-10-11.md). No conclusion that either candidate already works with that GGUF.

**Source and tests in this report are limited to code review + the Unsloth pair; no Agention GGUF loader or runtime verification was performed.**
