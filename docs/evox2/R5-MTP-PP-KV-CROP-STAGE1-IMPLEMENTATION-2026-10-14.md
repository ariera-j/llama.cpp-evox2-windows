# r5 MTP-ON PP Stage A: optional Draft catch-up graph root crop (2026-10-14)

**Status: VULKAN SHORT + 64K FUNCTIONAL PASS / NO VERIFIED PP SPEEDUP / KV-PARITY & GRAPH-CROP UNVALIDATED.**
This is a scoped experimental change only on
[`investigation/r5-mtp-pp-kv-crop-stage1-20261014`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-kv-crop-stage1-20261014).
Do **not** merge source to `r5/upstream-refresh-20261009`. This document is copied to stable for tracking; compiled experiment source remains a separate branch. The 2026-10-14 short Vulkan smoke is reported below; full K/V parity, FA dispatch elimination, and long-context ABBA are still pending.

## Provenance and why not refresh first

- Donor: `investigation/r5-mtp-pp-trace-20261013` at `61c9c5ee8db1aa4f0609458234d9bddaa0151239`; tested diagnostic Vulkan b11587 was **built** from `1453c9063` on that lineage, not this prototype.
- Stable r5 base pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Current upstream `091b6a7fc561` (2026-10-14) contains `#30257` token/image vs MTP hidden-state separation, `#30397` Qwen MTP embedding acceptance, and LM-head allocation changes, but **no** equivalent no-output Draft KV-only execution.
- Unsloth published b11541-mix-2500203 (2026-10-11) supports Windows Vulkan and gfx1151 ROCm; its 2026-10-13 dev-branch CM1 2-subgroup fix (`#270`) targets Gemma4 HSK 512/576 scalar fallback, not the already-CM1 Qwen3.8 Draft observed in RGP. Full source audit and upstream issue `#29811` for ratio-zero dense MTP k-pool guard: [research report on r5](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/r5/upstream-refresh-20261009/docs/evox2/R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md).
- Keep Unsloth pre-update *self-contained* Q8_0 sidecar SHA256 `cd87e5d1a4dadaeed63e35929f3b2f28d13e081b4cd32e00f2835095ec09351e` and original fixed input hashes. Do not switch to a newer GGUF or shared-head revision during this A/B.

## Modified files / mechanism

| File | Change | Scope |
| --- | --- | --- |
| `src/models/qwen4exp.cpp` | An opt-in zero-output, dense one-layer Draft prefill switch; bypass creating `inp_out_ids`; return after `build_layer_attn` expands its K/V copy graph roots, before all-row attention-output HC/FFN/NextN/logits are rooted | Qwen4Exp MTP **only**; Target and normal Draft generation remain on full graph |
| `src/llama-graph.cpp` | Skip Hybrid Attention mask input-setting if that graph's mask was not allocated (same pattern as normal `llm_graph_input_attn_kv::set_input`) | Generic hybrid input safety guard; no behavior change when mask allocated |
| `tools/evox2/tests/test_mtp_kv_crop_stage1.py` | Static source guard and control checks | **Not** runtime correctness testing |
| `tools/evox2/benchmark/configs/qwen38-r5-mtp-kv-crop-stage1.psd1` | Same-binary short A/B and 64k A1/B1/B2/A2 plan | Diagnostic/reproduction; no results yet |

Runtime flag (exactly `1` enables; absent/`0` OFF):

```powershell
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1' # Stage A ON
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0' # Stage A OFF
Remove-Item Env:\LLAMA_MTP_DRAFT_PREFILL_KV_CROP -ErrorAction SilentlyContinue # default OFF
```

The first-stage *narrow guard* is `n_outputs == 0`, `cparams.embeddings_nextn`, `cparams.embeddings_nextn_masked`, non-training, `!kv_unified`, one unique sequence, and `dsv4_compress_ratios[il] == 0`. The Qwen4Exp MTP constructor already enforces `n_layer_nextn == 1`. **The flag is not a general flash-attention switch.** Normal generation/verification requires at least one output row, so the old full graph remains. For unsupported modes the flag is inert.

The current `build_layer_attn` explicitly expands `q_cur`, `v_cur`, `k_cur` and separate `mctx_cur->cpy_k/cpy_v` nodes in `src/llama-graph.cpp`. In Stage A, K/V writes remain graph roots, **Q projection is still executed** (Stage B could remove it). The graph branch that builds FA, attention output and HC/FFN is deliberately *not* rooted by `t_h_nextn` or logits. This is an execution-graph pruning hypothesis; **inspect actual compiled graph** and RGP before claiming eliminated FA dispatches. The draft recurrent `s_copy` input root is also preserved.

Graph cache parameters already distinguish output count and shape. The environment variable is intended to be held **constant for an entire process**; live on-the-fly flag switching without rebuilding cached graph is not supported or tested. A/B must use separate processes.

## Upstream and vision-forward-port requirements

**Important limitation:** the pinned Qwen4Exp MTP graph still asserts `ubatch.token`, and `llm_graph_input_embd_h` overloads `ubatch.embd` as the Target hidden input. **MTP+vision is NOT yet supported in this experimental build.**

Do not fold upstream `#30257` or `#30397` into this isolated latency benchmark. When upstream is refreshed:
1. Rebase Stage A *as a small semantic graph-root crop*, not a wholesale replacement of `graph_mtp`; keep the upstream's new `embd_state` hidden channel, `tok_embd = ubatch.token ? get_rows(...) : inp->embd`, and its widened input dimensions.
2. The crop guard **must not rely on `ubatch.token` or `ubatch.embd`**. All output flags remain false for the one-layer catch-up path whether a token ID or image embedding is supplied; selection uses output count and MTP context semantics.
3. Preserve `n_layer_nextn == 1`, ratio-zero k-pool guard (`#29811` still open at check time), memory, positions and both K/V writes. Multi-layer heads, shared-head memory, multiple simultaneous sequences and `kv_unified` require separate analysis.
4. Verify three cases under the new source: pure text, image-only/mixed image+text with `--mmproj`, and image followed by text/continuation. Compare MTP OFF/ON, Stage A OFF/ON, hidden input/timing and cache correctness, not only output surface text.

## Local test gates / commands (not yet run)

**1. Source sanity.** From experiment branch checkout:

```powershell
git switch investigation/r5-mtp-pp-kv-crop-stage1-20261014
git status --short
python .\tools\evox2\tests\test_mtp_kv_crop_stage1.py
```

**2. Windows Vulkan build.** Use a **new** clean build directory, not the old RGP diagnostic one. Configure in the same Visual Studio Native Tools + LLVM/Vulkan SDK environment as your validated r5 setup:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-mtp-kv-crop-stage1 `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

.\build-vulkan-mtp-kv-crop-stage1\bin\llama-cli.exe --version
```

The BuildKey `R5MtpKvCropVulkan` in the benchmark plan **must point to this new binary in the existing ignored** `tools/evox2/benchmark/configs/local.psd1`. Preserve the BuildKey mapping structure already used locally; the old `R5MtpRgpDispatchVulkan`/b11587 binary cannot test this source change.

**3. Plan dry run (before executing).** The plan uses MTP ON in both variants. A = the old full Draft graph (`LLAMA_MTP_DRAFT_PREFILL_KV_CROP=0`), B = Stage A crop (`=1`). Markers and CPU/GPU forced synchronization diagnostics are explicitly cleared:

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-kv-crop-stage1.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-short -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-short
```

**STOP if any B short run crashes or differs in output/acceptance from A under the same Vulkan binary.** Also check no `GGML_ASSERT(buffer)`, missing GPU tensor backend, or failed shader allocation. After a short pass, use 64k A1/B1/B2/A2; do not run 128k before the 64k gate:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-64k -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-64k
```

**4. Stronger correctness than output equality.** At the prefill boundary, compare full Draft cache **K and V** (or an equivalent trusted replay producing matching next-step logits), K/V cell IDs and seq/position maps, acceptance/drafted counts and entire generated text under identical parameters. Test first prompt, 2048→1024 ubatch split, partial final ubatches (~349/1325), fresh prompt continuation, rollback/verification. Existing RGP debug markers may be re-enabled **only in a separate trace cohort** to prove B catch-up has no Draft FA/FFN dispatch while generation still uses FA/FFN. Changing the graph can affect schedule/time even without arithmetic differences, so numerical tolerances and repeatability must be declared before declaring parity. ROCm output nondeterminism requires a separate tolerance-aware verification.

**5. ABBA result gate.** Capture actual source/binary DLL hash, Windows driver, model and input hashes, process exit status, prompt eval seconds/tok/s, generation tok/s, end-to-end PP+TG, Draft acceptance, GPU local/shared and disk/page-fault pressure. The existing untraced 64k/128k r5 ON/OFF controls are reference context only; the causal metric is same-source/same-binary **Stage A OFF vs ON**. No claim of speedup until native A/B confirms it.


## Native Vulkan short smoke — 2026-10-14 15:00 JST

**Gate result: SHORT SMOKE PASS (qualified); performance effect not established.** User-provided raw archive `20261014-150020-188-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `4cef5849805a1ba7845606b72faf7e3f4329dc5da40f211a1f4966ba7252e48a`. Two successful **separate-process** runs from the same executable, same input/model/settings; only `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=0/1` and run IDs/timestamps differed in `conditions.json`.

- Actual compiled/running source `301564c2a19d567cca8891f6eb439ab69bb69aea`, `llama-cli` **b11597** (Clang 20.1.8, Windows 11 build 26300, Vulkan Radeon 8060S, manual UMA 96GB), identical executable SHA256 `9d8e68f99cb0b02fe177882cf0316a5bc92b86f1f2ef0b3beaba06be0e6324c6`; runner says `RuntimeArtifactStatus=Verified`. **Later documentation commits do not identify a different compiled binary.**
- Input `mtp-short.txt` SHA256 `88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`; 163 prompt tokens, 32 generated, ctx32768, -b2048/-ub1024, KV f16, MTP ON/Unsloth self-contained Q8_0, QSA-union enabled at min-KV32768, -temp0, same 1-slot/kv_unified=false settings. The archive has file paths for base and Draft GGUF but no GGUF SHA256 value (null), so **model-file content hashes cannot be verified from this ZIP**.
- A/OFF: `20261014-150022-831-cli-vulkan-b11597-ctx32768-1fb493b0810e`; B/ON: `20261014-150120-936-cli-vulkan-b11597-ctx32768-94bd78177716`. Both `Status=OK`, exit 0; **no compute error / buffer assert**.
  
| Metric | A = 0 (full Draft graph) | B = 1 (Stage A candidate) |
| --- | ---: | ---: |
| Prompt seconds / tokens/s | **1.64712s / 98.96** | **0.59208s / 275.30** |
| Generation seconds / tokens/s | **1.98772s / 15.60** | **0.89227s / 34.74** |
| Total measured prompt+generation | **3.63484s** | **1.48435s** |
| Draft generated / accepted | **27 / 17** | **27 / 17** |
| Draft acceptance ratio / #gen drafts | **0.62963 / 14** | **0.62963 / 14** |
| Graphs reused | **12** | **12** |
| Output | **byte-identical** after removing only CLI performance footer | **byte-identical** |

**Causal interpretation:** This is **NOT** evidence of 2.78× PP or 2.23× TG gain. A was run first, B second; a single 163-token prompt is vulnerable to driver pipeline warmup/shader compilation, OS caching or other run-order effects. Stage A is designed to affect only all-false-output Draft catch-up, *not generation*, so the simultaneous >2× TG difference is a strong negative control against attributing all observed short-run gains to the patch. The resource monitor also mainly covers large model initialization; aggregate disk/page-read medians are not prompt-only counters. No per-dispatch GPU trace/complete Draft K/V dump has been collected.

**Decision:** Short functionality gate is passed; **next run the existing 64k A1/B1/B2/A2 same-binary plan** (`stage1-64k`) to control run order and amortize short prompt effects. Reuse **this exact b11597 binary**; do not rebuild merely because this documentation is updated. Stop if crash, output/acceptance mismatch, failed KV updates, or unverifiable run identity; qualify output and draft acceptance as observed rather than K/V bitwise parity. Optionally repeat the short test in reversed order after the 64k gate, but do not infer speedup from short timings. Native Draft FA dispatch absence and exact K/V equivalence remain open; they require targeted graph/RGP validation before calling this optimization verified.


## Native Vulkan 64k ABBA — 2026-10-14 15:09–15:27 JST

**Gate: 64K FUNCTIONAL/PARITY PASS; SPEED EFFECT NOT CONFIRMED; FA/FFN PRUNING NOT YET VERIFIED.** Raw archive `20261014-150945-740-qwen38-r5-mtp-kv-crop-stage1.zip` SHA256 `47b7d7a665a9e25d3d94c92a34500a5c9508c1c0a20a573dfeddab6ed9825f41`. All four runs from **same Vulkan b11597** `301564c2a19d567cca8891f6eb439ab69bb69aea`, executable SHA256 `9d8e68f99cb0b02fe177882cf0316a5bc92b86f1f2ef0b3beaba06be0e6324c6`; verified runtime, `ctx=65536`, same 61,789 input tokens, f16 KV, batch2048/ubatch1024, identical original PLE16 target and Q8_0 sidecar path/metadata, -temp0, 512 generated, Vulkan QSA union enabled, diagnostics unset, same 1-sequence context. Only experimental flag and per-run provenance vary.

| Order | Variant | Flag | PP tok/s | PP seconds | TG tok/s | Exit | Draft accepted/generated |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| 1 | A1 | 0 | 313.66 | 196.99572 | 27.80 | OK/0 | 295 / 430 |
| 2 | B1 | 1 | 315.68 | 195.73278 | 28.76 | OK/0 | 295 / 430 |
| 3 | B2 | 1 | 315.41 | 195.89783 | 28.63 | OK/0 | 295 / 430 |
| 4 | A2 | 0 | 314.10 | 196.71836 | 28.61 | OK/0 | 295 / 430 |
| **Mean** | **A (OFF)** | 0 | **313.880** | **196.85704** | **28.205** | 2/2 OK | same |
| **Mean** | **B (ON)** | 1 | **315.545** | **195.81531** | **28.695** | 2/2 OK | same |

Observed mean PP **+0.5305% / 1.042s shorter**; A replicate range 313.66–314.10 tok/s (+0.44), B range 315.41–315.68 (+0.27); B > A2 in both repetitions, but **two replicates/arm are inadequate to distinguish a tiny real effect from clock/warmup/order drift**. Same-generated `stdout.log` binary-identical across all four after removing only the timing footer; `draft acceptance=0.68605`, 295/430 for all. No evidence of correctness divergence at output level; **KV contents have not been compared**.

**Progress-bin observation** (approx. cumulated server progress times; 2k-token progress): A/B mean difference already ~0.33s at 4,096 tokens and ~1.02s at 61,440; interval savings ~0.405s in first 16k, ~0.330s at 16–32k, ~0.110s at 32–49k, ~0.180s at 49–61k. **No clear growth with KV depth**, unlike a simple proportional-to-KV Draft FA cost model. TG mean B +1.74% is confounded by unusually slow A1 TG=27.80 compared with A2=28.61, B1=28.76, B2=28.63; the patch is not intended to improve generation.

**Critical interpretive limit:** The identical startup `sched_reserve: graph: nodes=127/133` lines are *not evidence the runtime crop was bypassed*, because `llama_context::sched_reserve` deliberately reserves the graph with `n_outputs>=1`; Stage A requires `n_outputs==0`, so a **real prompt catch-up graph** must be inspected. `common_speculative_impl_draft_mtp` sets `ctx_dft` NextN=true/masked=true and constructs all-false-output catch-up batches, but no per-catch-up activation counter/active graph node tally is present in this release. Explicit activation, actual omission of FA/FFN GPU dispatches, retained K/V and sync effects **remain unknown**. Do not interpret the observed ~0.5% as proven optimized execution or as proof that pruning is pointless.

**Decision (priority):** Hold 128k and ROCm comparisons. First add an **opt-in low-overhead one-shot diagnostic** to confirm (a) `draft_prefill_kv_crop` guard evaluated true for representative 1024-token prompt catch-up ubatches and (b) active `ggml_cgraph` really lacks `GGML_OP_FLASH_ATTN_EXT` / FFN nodes while retaining K/V `GGML_OP_SET_ROWS` / cache copy roots, and compare to the default graph. Existing RGP Draft role markers may be used separately with diagnostics kept OFF in speed tests. Only after proving activation/graph difference, re-run 64k A/B for causal PP and consider 128k. This is a recommendation, **not implemented in this update**. Do not change any inference source, runtime flag semantics, GGUF, DENSE/NOOP branch or stable r5 runtime during this documentation-only update.

## Known concerns / blockers

- A removed hidden/logits output is expected and intentional **only for zero-output catch-up**; ordinary outputs must remain present. The complete graph is preserved by default or on any nonzero-output batch.
- `llm_graph_input_mem_hybrid` historically sets the FA mask unconditionally. Stage A allows the mask buffer to be pruned and the setter now tests allocation; test for other unallocated input setters before declaring backend correctness.
- If this graph is fully allocated with K/V roots but unexpectedly still dispatches FA, revise after reading the active graph nodes rather than assuming GGML dead-code pruning succeeded.
- No synthetic CPU-only cache-state test has been implemented. Static source tests are *not* sufficient for merged or validated status.
- No upstream/r5 stable inference code, DENSE or NOOP branch, GGUF, prebuilt binary, build key from another experiment or release artifact has been changed.


## Stage A active catch-up graph diagnostic — 2026-10-14

**Status: SOURCE ADDED / STATIC SOURCE CHECKED / NOT YET BUILT OR MEASURED ON WINDOWS.** After the 64k ABBA showed only +0.53% PP and no clear depth-dependent gain, add an isolated read-only graph inspection before spending time on 128k.

- Changed `src/llama-context.cpp::process_ubatch`, *after* actual `model.build_graph` and scheduler graph allocation/reuse but *before* `res->set_inputs` and compute. This is **not** the `sched_reserve()` graph (`n_outputs>0`). Scope is only `LLM_GRAPH_TYPE_DECODER_MTP`, `LLM_ARCH_QWEN4EXP`, and a real `n_outputs==0` microbatch. No token/embedding input-type predicate, to simplify a future upstream `embd_state` and MTP+vision port.
- Opt in with `LLAMA_MTP_KV_CROP_DIAG=1`. Separate from `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` (the actual Stage A optimization flag). Disabled unless exactly `1`; when enabled it logs **at most the first 8 real catch-up ubatches per process**, with an atomic counter. The log scans the *active* `ggml_cgraph`, including when reused. No debug output from reserve graphs or other models; the diagnostic does not select or alter any computation.
- The `crop_applied` bit is **observed from actual graph result outputs**, not re-evaluated model eligibility: Qwen4Exp Stage A is the unique early return leaving both `res->t_logits` and `res->t_h_nextn` null; original Qwen4Exp full path provides both. The existing optimization guard is untouched.
- Log label `mtp_kv_crop_graph_v1`. Fields: `sample`, `crop_requested`, `crop_applied`, `n_tokens`, `n_outputs`, `n_seqs`, `graph_reused`, `kv_slots`, `last_pos`, `graph_nodes`, `fa`, `moe_matmul_id`, `ffn_weight_mm`, `matmul`, `set_rows`, `k_writes`, `v_writes`, `logits`, `nextn`.
  - `fa`: `GGML_OP_FLASH_ATTN_EXT` **graph nodes**, not measured Vulkan GPU dispatches.
  - `k_writes/v_writes`: `GGML_OP_SET_ROWS` with `src[2]->name` equal to `attn_inp_k_idxs` / `attn_inp_v_idxs`, matching the pinned `llama_kv_cache::cpy_k/v` implementation. `set_rows` is the total of all such nodes.
  - `moe_matmul_id`: `GGML_OP_MUL_MAT_ID`; `ffn_weight_mm`: a **heuristic**, MM operators with a source-weight name containing `ffn_`. Neither proves the absence of *every* FFN operator, especially under fusion/renaming. Direct FA/KV-node comparisons and total graph node counts are primary; use RGP separately to verify actual GPU dispatch removal.
  - `kv_slots`: attention cache's `get_n_kv()`, **not** necessarily the exact sequence length; use `last_pos` to locate the last input position.
  - `graph_reused=1` means reusing the already-constructed active result; `crop_applied` still reflects the actual reused graph result.
- The same-binary A/B diagnostic is a new `stage1-diag-short` job within `tools/evox2/benchmark/configs/qwen38-r5-mtp-kv-crop-stage1.psd1`, using a **new dedicated BuildKey `R5MtpKvCropDiagVulkan`**. The old normal `stage1-short` and `stage1-64k` jobs keep the old build key and explicitly unset the diag environment variable. The static regression suite now includes tests for this isolation.

### Windows Evo-X2 test gate

**Rebuild required**: previous b11597 executable did not include the new diagnostic code. Reuse the experimental branch name but a separate build directory so that the previously tested b11597 binary remains identifiable.

```powershell
git fetch origin
git switch investigation/r5-mtp-pp-kv-crop-stage1-20261014
git pull --ff-only

python .\tools\evox2\tests\test_mtp_kv_crop_stage1.py

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-mtp-kv-crop-diag `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

In your locally ignored `tools/evox2/benchmark/configs/local.psd1`, add `R5MtpKvCropDiagVulkan` by copying the *shape* of `R5MtpKvCropVulkan` but pointing at the **new** `build-vulkan-mtp-kv-crop-diag/bin/llama-cli.exe`; do not repoint or overwrite the old ABBA BuildKey.

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-kv-crop-stage1.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-diag-short -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-diag-short
```

Expected *criteria*, **not measurements** (do not invent node counts):
- A-diag `crop_requested=0 crop_applied=0`, `logits=1 nextn=1`; dense attention `fa>0`, `k_writes>=1 v_writes>=1`.
- B-diag `crop_requested=1 crop_applied=1`, `logits=0 nextn=0`; **`fa=0`**, `k_writes>=1 v_writes>=1`, normally fewer `graph_nodes` and MoE/MM operators.
- Both exit0, generated text and MTP Draft acceptance must match. If `B crop_applied=0`, investigate the Stage A eligibility guard first. If `B crop_applied=1` but `fa>0`, inspect hidden graph roots. If K or V write count is zero, **do not** run 64k/128k; audit cache graph roots.
- If `mtp_kv_crop_graph_v1` lines are absent in **both**, check actual runtime hash, BuildKey, env propagation and `LLAMA_CONTEXT_TYPE_MTP` before assuming the code is not reached.

Do **not** compare PP/TG in this diagnostic cohort: graph scanning and logging perturb timing. Normal ABBA remains separate with diagnostics disabled. Do not enable RGP markers at the same time. New compiled executable SHA256/commit and diagnostic log ZIP must be captured before declaring graph-crop confirmed. No Windows build or new runtime result has been obtained while making this commit; previous b11597 functionality results remain valid only for the old binary.
