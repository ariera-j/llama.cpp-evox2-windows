# R6 S9 Qwen IQ4/huihui measured closure — 2026-10-28/29 JST

## Scope and decision

**Measured G9-0, G9-1, G9-2 and bounded G9-3 PASS for the cases below. G9-4 Gemma4 and G9-5 server/vision/release remain PENDING.** This records the completed Windows Evo-X2 tests in the [S9 runbook](R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md), including the **2026-10-29 original IQ4 B-order** MH-128K follow-up. All result ZIPs and independent scorer outputs remain in the user's local archive, not Git.

The decision is model-, backend-, quant-, context- and flag-specific. It does **not** promote any S4–S7 optimization to ON by default, establish 256k IQ4 quality, prove MTP-ON behavior, replace an operational Gemma4 b10919 binary, or authorize public distribution.

| Gate | Covered Windows cases | Result | Limits |
| --- | --- | --- | --- |
| G9-0 original Unsloth IQ4_XS PLE16 | Vulkan b11908 4k then 16k short fixture | **PASS 2/2** | 163 actual prompt tokens; allocation/load/short text, **not** filled 4k/16k speed |
| G9-1 huihui abliterated IQ4_XS PLE16 | Vulkan b11908 4k then 16k short fixture | **PASS 2/2** | Separate weights; initial 4k human alias was stale (see audit below) |
| G9-2 real input | Original + huihui real 64k; selected original real 128k | **PASS 3/3** | Huihui real 128k intentionally **not** run; no 256k IQ4 |
| G9-3 frozen MH-128K | Original A/B, huihui A/B; seed 20261026 | **PASS bounded 4/4** | Original 12/12 both orders; huihui 12/12 A, 11/12 B; no claim of quality uplift |
| G9-4/G9-5 | Gemma4 and conditional server/vision/adoption | **NOT EXECUTED** | Keep independent b10919 baseline and rollback |

## 1. Provenance and test policy

- Device: GMKtec Evo-X2 / Ryzen AI Max+ 395 / AMD Radeon 8060S, Windows 11, UMA label **96GB**, P-MODE **Performance**. Every measured ZIP reports `Status=OK`, `ExitCode=0`, direct Performance probes at both ends, ADLX consistent, and no recorded fatal GPU reset/OOM. All relevant short/long stdout/stderr logs report **49/49 layers GPU-offloaded**.
- **Actual executable**, not the scripts' Git HEAD: `llama-cli.exe` Vulkan **b11908**, compiled source `b82243bf0`, Clang 20.1.8, SHA256 `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`; runtime-artifact digest `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3` on all **four** MH runs. The user's script worktree was at `f91c6d2` when those cases ran. A later docs-only commit does not change the built DLLs.
- All runs: Vulkan, full GPU requested, `-ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 512 -fa auto -ctk f16 -ctv f16 -fit on --cache-ram 0`, `--jinja --single-turn --reasoning off`, **MTP OFF**, `GGML_VK_QSA_UNION=0`, all S8 speed switches OFF (including DENSE, NOOP, Stage-B and flatten). Both PLE16 variants are reported `qwen4exp`, `IQ4_XS - 4.25 bpw`, GGUF V3, file size **93,682,576,992 bytes**. Generation caps: short **64**, real papers **256**, MH **512**.
- User-supplied full GGUF SHA256, computed separately on Windows: **original** `BA65BD1E3631DA5FC99764686C05D68DB45FEAF22A36C2C5F824F9255DAC614A`; **huihui** `47F2F224CE35177DA01778929670F4D25A1A6C23DEFE2A82F8010B223C1A96F2`. They are **distinct models despite the same output filename/length**. Per-run `conditions.json` and conversion manifests have `ModelIdentity.Sha256=null` / `OutputFile.Sha256=null`, so those logs alone do **not** cryptographically rehash the 87-GiB files. Path, size and metadata match the user's separately recorded full hashes.
- Both PLE16 conversion reports verify 16 split head tensors, 1,239 tensors and correct metadata/layout, `valid=true`. The **original** converter's payload check used `VerifyBytes=false` (metadata/types/layout only); the **huihui** converter used `VerifyBytes=true` and checked every tensor payload SHA256. Original and huihui conversion sidecar SHA256: `0d401fd606091e9c3c81841b3ac2f1d9f1bdd7bd7194fecb824c80cc7098427c` and `7815412f86451c259a54943cdb50f318134ad29fc111abeadea9c685d7812779`. No converter rerun or GGUF modification is part of this gate.
- **Audit:** Huihui's first **4k** run had the stale human alias `gemma4-31b-qat-q4_0` in ignored `local.psd1`; `ModelIdentity.Path`, GGUF metadata, quant, `49/49` offload and output confirm the **huihui** model was actually loaded. The alias was corrected to `huihui-iq4xs-ple16` before its 16k, 64k and all MH runs. The affected 4k measurement is not a Gemma4 test.

## 2. Short and real-paper measurements

Numbers are **single runs**, PP/TG in tokens/s and wall time in seconds. The 4k/16k row labels identify allocated **context**, not input occupancy. No prompt/context truncation was detected in any of these cases.

| Model | Context / workload | Actual input tokens | Generated | PP | TG | Wall | Min free physical RAM (GiB) | Peak process GPU committed (GiB) | Verdict |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Original IQ4 | 4k short | 163 | 64 | 283.43 | 27.12 | 42.368 | 24.650 | 89.130 | PASS |
| Original IQ4 | 16k short | 163 | 64 | 341.43 | 27.18 | 40.358 | 24.459 | 89.516 | PASS |
| Huihui IQ4 | 4k short | 163 | 64 | 339.75 | 27.12 | 40.559 | 24.639 | 89.130 | PASS; alias audit above |
| Huihui IQ4 | 16k short | 163 | 64 | 339.93 | 27.07 | 40.697 | 24.442 | 89.516 | PASS |
| Original IQ4 | real 64k | 61,789 | 256 | 314.08 | 24.72 | 244.791 | 24.527 | 91.162 | PASS |
| Huihui IQ4 | real 64k | 61,789 | 256 | 313.75 | 24.71 | 246.355 | 24.381 | 91.162 | PASS |
| Original IQ4 | selected real 128k | 126,253 | 256 | 250.67 | 22.85 | 552.497 | 23.909 | 93.339 | PASS |

Frozen input SHA256: short `mtp-short.txt` = `88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`; real64 = `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; real128 = `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`. The 128k case fits the 131,072-token context and generated its requested 256 tokens. Compare speed with older b11521/b11592 only after checking build, input, sampling, KV, MTP and power conditions; no individual S8-patch attribution is supported.

## 3. G9-3 frozen MH-128K quality regression

Reuse the independent [`evox2-llm-experiments` MH-128K v0.1 oracle/scorer](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval/mh-128k). The **same 1,137-record seed `20261026`** and frozen 111,148-token prompt were used, with input order **A** SHA256 `3df86efedd7e3fbc1f71226392fbcf076f68a0a9b3135647087f3340040275e3` and **B** SHA256 `694edd15bb2f762a530b437800f67d3dc84eb085be17429e828e060a4fd69ef4`. All **four** scorer JSONs say `validation.status=VALID`, `token_count_verified=true`, `RunStatus=OK`, `ExitCode=0`, `truncated=0`, `format_compliant=true`, no scorer issues, and **Q13/Q14 both correct**. Sampler fixed at temperature 0, `top-p=0.8`, `top-k=20`, `min-p=0.05`, `seed=1234`; 14 requested output lines.

| Model / order | Historical b11592 main 12 | b11908 main 12 | E/M/H | Q13/Q14 | PP | TG | Wall (s) | Min free RAM (GiB) | Peak GPU (GiB) |
| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| Original IQ4 / A | 12/12 | **12/12** | 4/4, 4/4, 4/4 | correct/correct | 248.47 | 23.26 | 496.428 | 24.215 | 93.308 |
| Original IQ4 / B | 12/12 | **12/12** | 4/4, 4/4, 4/4 | correct/correct | 248.58 | 23.20 | 498.367 | 23.921 | 93.308 |
| Huihui IQ4 / A | 11/12 | **12/12** | 4/4, 4/4, 4/4 | correct/correct | 249.40 | 23.23 | 494.360 | 24.123 | 93.308 |
| Huihui IQ4 / B | 11/12 | **11/12** | 4/4, 3/4, 4/4 | correct/correct | 249.67 | 23.22 | 494.389 | 24.213 | 93.308 |

**Per-question distinction:** On b11908 **original IQ4 A and B**, all Q01–Q12 (including Q01 and Q08) are correct, exactly matching the b11592 12/12 aggregates. On the b11908 huihui **A**, Q01–Q12 are all correct, including formerly troublesome hard **Q08**. On huihui **B**, **Q01** (medium) is the sole wrong main answer: expected `VAL-A8A73716B990`, emitted `VAL-7826779DF3FE`, classified by the scorer as `other_known_or_valid_value`. **Q08 is correct in both b11908 huihui orders**, and Q13/Q14 controls remain correct in all four runs. This is not output-format truncation or prompt-hash mismatch. The exact wrong-question ID in the historical b11592 **huihui B** has not been independently matched here; only that historical run's **11/12** aggregate is supported by the [r5 handoff](R5-MODEL-QUALITY-AND-POST-INTEGRATION-HANDOFF-2026-10-25.md).

These are **A/B orderings of one seed, not independent replications**. The original b11592 16-case study also found huihui 12/12 for both orders of a **different** seed (20261025), so b11908 huihui A's 12/12 alone is **not proof of a causal quality improvement**. The bounded regression shows **no measured score regression** against matching historical seed/order across all four cases, with a single huihui B wrong answer; it does not establish statistical significance or explain internal routing. Two-model Qwen candidate testing is complete only within this exact stock/MTP-OFF Vulkan scope. The requested **original IQ4 B** follow-up is now **PASS**; no mass 16-run repeat.

## 4. Raw evidence integrity (private archives, hashes public)

Run ZIP names and their SHA256 identify the source of the tabulated result; ZIPs contain raw outputs/resource telemetry and stay off Git. Dates and run IDs use local JST from the Windows runner.

| Case | Local run ZIP (`evox2-logs/`) | ZIP SHA256 |
| --- | --- | --- |
| Original 4k | `20261028-213920-642-cli-vulkan-b11908-ctx4096-e5e5245840a5.zip` | `8d6fddc28599dd1326aee8414f832c7a002047e1221f0fc1306ea9be05c57a86` |
| Original 16k | `20261028-215218-091-cli-vulkan-b11908-ctx16384-5ee8becb91bd.zip` | `69a49a8ace1cdd9f14106d669c9ea8548e573360d4d70b3b0ef5bd7efb64c8e8` |
| Huihui 4k | `20261028-215840-516-cli-vulkan-b11908-ctx4096-cbb043136969.zip` | `a3cd20b852db48728e327b81a692912ecfe8644e021a96ff511eb1d62aca5620` |
| Huihui 16k | `20261028-220539-121-cli-vulkan-b11908-ctx16384-89b8d0822e21.zip` | `95ebdde032eb3b25e91716317be5e68f4082840f2b7f317a3f886832cf3a91e0` |
| Original real64 | `20261028-221114-238-cli-vulkan-b11908-ctx65536-66734dca3979.zip` | `006dc7bc201bb0d8e1106ef8732dfa0e11d06c80921bffac96a132679762d44b` |
| Huihui real64 | `20261028-221839-903-cli-vulkan-b11908-ctx65536-96754852b48d.zip` | `9054767da944e963210ce1fe6ecdecddb351bbd44f1ff29d47082f32e3f3961c` |
| Original real128 | `20261028-222548-980-cli-vulkan-b11908-ctx131072-76ead0584bf3.zip` | `9bf0eb4fe806ff31d52a0498fee273964670ecfba2cd5afdba5de64328e3dc85` |
| Original MH-A | `20261028-225754-044-cli-vulkan-b11908-ctx131072-ad23c7f638dc.zip` | `df4f5a79d36fb82357ecf09bf286fe3815bedfc84a9d688f00da6312c2b20b85` |
| Original MH-B | `20261029-002531-955-cli-vulkan-b11908-ctx131072-55d5bc35cc77.zip` | `0e69c1a96939ad18c81966f5dbaf1cd1da2a45ac38abf6d8810f75e8df816d49` |
| Huihui MH-A | `20261028-231415-207-cli-vulkan-b11908-ctx131072-3b087ebcb5a3.zip` | `4dec10d40d31ea6e17332ee7866f460b8862a6d96da61cead5ae40be458de9b7` |
| Huihui MH-B | `20261028-235308-609-cli-vulkan-b11908-ctx131072-0799b12d999f.zip` | `4dabe136290765adaa22a9383525b2a20736d00d1dc83b4d9fb019406366a043` |

Independent scorer artifacts (CSV SHA / JSON SHA respectively):

- Original MH-A: `3b7fb2900fc7f03419c119a5c624992eebb0d00c608b1e9eb8e431c87555da71` / `df23b85952d53b8910c335f0de0e0d537985cb76653f14b944897f4a46f4a314`.
- Original MH-B: `149e8a4df744fef91a88be2750bfdce5700c36898c5bba8d9c725ad103d9806b` / `fb73fb1ad4aac7b0ed358728646fe7d1e8b8a1ea597aa5bb8c7fb7a4fe737b58`.
- Huihui MH-A: `ff5df70bc46166434175c1d678e216740622121a9d995d5cf5947e7fa2012950` / `04837446b09437e99e18ba3689c8c259b5723b6d4b816971e0c9bbaa6eaa4021`.
- Huihui MH-B: `82ab2f9cdeaa391e0dafb6716bfcba5a371f5f2e844a5630db0d0b5df81c8c98` / `005f49b2979b755963fc5be2ddaf84752a19b1f0ff2e284710c1bee04bb2a4a4`.

The three recorded G9-3 PSD1 plans under `tools/evox2/benchmark/configs/` contain only model/build/input **keys** and fixed safe settings. The ignored `local.psd1`, private input texts, GGUF files, conversion payloads, run ZIPs and full independent oracle records were **not** committed.

## 5. Next actions / rollback

1. The single frozen original IQ4 seed-20261026 **B** follow-up is **PASS** (12/12); preserve its ZIP/score in the local archive. Do not reopen the S8 patch gates or repeat the 16-run study to improve the aggregate.
2. Begin **G9-4 per-Gemma independent b10919-to-b11908 rollback testing** only after confirming the user's actual b10919 executable/DLL directory, both specific Gemma model paths/SHA, template and known-good settings. Gemma4 31B and 26B must be judged separately. A bounded night batch can be prepared **after** this preflight; no Gemma4 test has yet been run on the S9 candidate.
3. Keep previous working Qwen builds and saved **b10919 Gemma4** binaries intact. Do not claim any default switch enablement, unattended production adoption, server/vision acceptance or general release from these CLI results.
