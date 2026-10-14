# r5 MTP-ON PP Stage A: optional Draft catch-up graph root crop (2026-10-14)

**Status: STAGE-B VULKAN PP IMPROVEMENT VALIDATED WITHIN BUILD; SAME-DAY ARCHIVED b11560 MTP-OFF RECHECK MATCHES b11618 (~305 tok/s), WHILE 2026-10-11 b11560 WAS ~335 tok/s. CROSS-DATE SLOWDOWN CAUSE UNKNOWN; GPU DISPATCH/KV PARITY UNVERIFIED.**
This is a scoped experimental change only on
[`investigation/r5-mtp-pp-kv-crop-stage1-20261014`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-kv-crop-stage1-20261014).
Do **not** merge source to `r5/upstream-refresh-20261009`. This document is copied to stable for tracking; compiled experiment source remains a separate branch. The 2026-10-14 short Vulkan smoke is reported below; full K/V parity, FA dispatch elimination, and long-context ABBA are still pending.

## Provenance and why not refresh first

- Donor: `investigation/r5-mtp-pp-trace-20261013` at `61c9c5ee8db1aa4f0609458234d9bddaa0151239`; tested diagnostic Vulkan b11587 was **built** from `1453c9063` on that lineage, not this prototype.
- Stable r5 base pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. Current upstream `091b6a7fc561` (2026-10-14) contains `#30257` token/image vs MTP hidden-state separation, `#30397` Qwen MTP embedding acceptance, and LM-head allocation changes, but **no** equivalent no-output Draft KV-only execution.
- Unsloth published b11541-mix-2500203 (2026-10-11) supports Windows Vulkan and gfx1151 ROCm; its 2026-10-13 dev-branch CM1 2-subgroup fix (`#270`) targets Gemma4 HSK 512/576 scalar fallback, not the already-CM1 Qwen3.8 Draft observed in RGP. Full source audit and upstream issue `#29811` for ratio-zero dense MTP k-pool guard: [research report on r5](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/r5/upstream-refresh-20261009/docs/evox2/R5-MTP-PP-VULKAN-OPTIMIZATION-SOURCE-REVIEW-2026-10-14.md).
- Keep the same Unsloth pre-update *self-contained* Q8_0 sidecar and original fixed input hashes. Target/Draft GGUF SHA256 is unavailable (null) in the supplied log ZIPs; verify it locally rather than asserting an unconfirmed hash. Do not switch to a newer GGUF or shared-head revision during this A/B.

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

## Native Vulkan active-graph diagnostic result — 2026-10-14 16:52 JST

**Result: STAGE-A BRANCH CONFIRMED ACTIVE, BUT DRAFT FLASH ATTENTION STILL ROOTED; KV WRITE NODE IDENTIFICATION NEEDS A FIX.** Raw ZIP `20261014-165223-584-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `ff4fadcb3a41f208fab36aed094399cff8203dc566f31fc827c9be3d8631a186`. Tests reported by the Windows operator as 10/10 passing after the literal-backslash-n assertion fix. Actual Vulkan executable `b11608`, compiled **clean** from `bdb3bb87f6967426a66cb9ddba86b17fcf85799e` via Clang 20.1.8; same executable SHA256 `64db0eb57423ce818540013599e6b02327d605e882d05d426350f4b8b2cada70` in A and B; verified runtime artifact. 163 prompt tokens, 32 generated, ctx32768, KV f16, same target/Draft paths and fixed runtime conditions; `LLAMA_MTP_KV_CROP_DIAG=1` in both runs, experimental crop flag changed from `0` to `1`.

| Active Draft zero-output graph (sample 1; 163 input tokens) | A-diag: OFF | B-diag: ON |
| --- | ---: | ---: |
| `crop_requested / crop_applied` | 0 / 0 | **1 / 1** |
| `graph_nodes` | **133** | **44** |
| `fa` (GGML Flash Attention EXT graph nodes) | **1** | **1 (still present)** |
| `moe_matmul_id` | 3 | **0** |
| `ffn_weight_mm` (heuristic) | 11 | **0** |
| `matmul` | 22 | **6** |
| `set_rows` | 2 | 2 |
| `k_writes / v_writes` (name-based detector) | **0 / 0** | **0 / 0** |
| `logits / nextn` tensors | 1 / 1 | 0 / 0 |
| `graph_reused` | 0 | 0 |

All diagnostic samples (#1–8) have exactly the same per-condition graph-node counts and crop status; after the initial `n_tokens=163, n_outputs=0, last_pos=162`, samples #2–8 each have **`n_tokens=3, n_outputs=0` and `last_pos>=165`**, meaning **the Stage-A crop also activates during token generation, not only prompt prefill**. This corrects the previous interpretation of large TG changes as purely a warmup/control effect; zero-output MTP catch-up in generation *is* affected, so an actual TG impact is plausible. The two timing results (`PP 97.93/275.89 tok/s`, `TG 15.52/34.86 tok/s`, OFF/ON) are not reliable rate estimates because only one A→B order was run and logging is enabled; the observed TG gap repeats the earlier short smoke qualitatively, but is not a controlled ABBA estimate. Both exit0, generated stdout byte-identical apart from performance footer, Draft accepted/generated **17/27** each.

**Root cause of remaining FA is identified in pinned source**: `src/models/qwen4exp.cpp::graph::build_layer_attn()` calls `llm_graph_context::build_attn()` even in the Stage-A cache-only branch. In turn `src/llama-graph.cpp::llm_graph_context::build_attn_mha()` contains an unconditional **`ggml_build_forward_expand(gf, cur)` at the end** (near line 2885), explicitly rooting the Flash Attention output in the active graph. Returning early from the Qwen4Exp constructor suppresses the downstream HC/FFN/logits but **cannot undo the pre-rooted FA**. Stage-A graph still contains one FA node; real GPU dispatch absence was not claimed or proven. This explains why source-level Stage A has not achieved its intended FA pruning and is a plausible reason the previous 64k PP benefit was only +0.53%.

**K/V detection limitation:** Both graph variants have exactly **two `GGML_OP_SET_ROWS` nodes**, consistent with `llama_kv_cache::cpy_k()` and `cpy_v()`. However the diagnostic's hard-coded test of `node->src[2]->name == attn_inp_k_idxs / attn_inp_v_idxs` matches **neither**: `k_writes=v_writes=0` even for the full OFF graph. Treat this as a **broken/overstrict classifier**, *not evidence of missing KV writes*. Print actual operand names/ops or directly tag cache-write tensors in a follow-up instrumented patch; verify K/V roots and numerical equivalence before declaring Stage-B implementation complete.

**Recommended next step, not implemented here:** Implement a **separately guarded Qwen4Exp Draft cache-only K/V projection and cache-writing path** (keep original Target/full Draft path intact and opt-in). In Stage-A early exit, avoid constructing the unused Q projection/gate and avoid calling shared `build_attn_mha()` altogether; explicitly retain K and V projections, normalization, rope, model-specific rotations, K/V cache copy roots, and required recurrent-copy roots. Then repair the K/V diagnostic classification, re-run the 163-token OFF/ON graph test, require **B `fa=0`, K/V writes present, exit0, same output/acceptance**, and only then use a diagnostics-OFF 64k ABBA followed by 128k and GPU RGP to validate dispatch elimination/performance. Design by `n_outputs` / context semantics rather than `ubatch.token` to ease a future upstream `embd_state` and MTP+Vision integration. Do not accidentally share a KV-only mode with Target or output-producing Draft graphs.

**Note on provenance:** `conditions.json` in this and prior ZIPs reports **null** for target/Draft GGUF SHA256. Model content hashes cannot be asserted from these logs; the earlier documentation's purported Draft-sidecar SHA was not derived from the attached logs and must not be treated as verified. Current test reports are based on same model paths, file sizes and write timestamps, not cryptographic content hashes.



## Stage B implementation: dense Draft K/V only, no FA graph root — 2026-10-14

**Status: SOURCE COMMITTED, STATIC SOURCE CHECKS REVIEWED, NOT YET BUILT OR TESTED ON WINDOWS.** The prior b11608 diagnostic proved Stage A's outputless Draft graph still had one GGML_OP_FLASH_ATTN_EXT: the common build_attn_mha() explicitly calls ggml_build_forward_expand(gf, cur). Returning early from graph_mtp after normal attention creation could not remove that root. Stage B replaces the cache-only route, not the normal full graph.

### Source changes and compatibility

- New Qwen4Exp-only graph::build_layer_attn_kv_only() declared in src/models/models.h and implemented in src/models/qwen4exp.cpp. The existing llm_graph_context::build_attn(), build_attn_mha(), Target path and output-producing Draft path remain unchanged.
- Retain the existing strict Stage-A guard: exact environment switch LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1, n_outputs==0, masked NextN, no training, non-unified KV, one sequence, dense (MTP compress ratio 0), one MTP layer. This includes Draft zero-output catch-up during TG. Do not change graph selection based on token vs image embeddings: an eventual upstream hidden-state/vision ABI can be ported without changing semantics. NOTE: the current pinned graph_mtp constructor still requires ubatch.token, so Vision compatibility is not implemented yet.
- Stage B calls the new helper, then returns *before* full build_layer_attn() (whose output invokes FA). The helper computes K and V LoRA projections, K RMS norm, K IMRoPE, optional K and V Hadamard rotations, then roots both K and V cache writes via mctx_cur->cpy_k / cpy_v and ggml_build_forward_expand. Its output nodes are tagged mtp_draft_cache_write_k and mtp_draft_cache_write_v for diagnostics. No query projection, FA, output gate, WO, FFN, NextN or logits are constructed in this branch. The draft recurrent-copy root is retained.
- Exact transform order and rope arguments were copied from existing build_layer_attn() and build_attn(llm_graph_input_attn_kv). Duplication is intentional to keep other inference source stable; re-audit if upstream changes Qwen4Exp K/V logic.
- Correct the diagnostic's SET_ROWS operand semantics: source ggml/src/ggml.c::ggml_set_rows sets src[0]=values, src[1]=indices, src[2]=cache. Earlier b11608 diagnostics wrongly inspected src[2], thus printed zero K/V writes despite two SET_ROWS operations. New source examines src[1] and also accepts specifically named Stage-B output nodes. Diagnostic prefix is now mtp_kv_crop_graph_v2.
- Static regression suite tools/evox2/tests/test_mtp_kv_crop_stage1.py now has 12 tests for isolated early return, K/V projections/rotation/cache roots, unchanged full path, diagnostic operand correction and isolated test jobs. These are source assertions, NOT proof of compilation or correctness.

### New Windows build / first validation

Preserve previously measured executable identities: DO NOT repoint the older R5MtpKvCropVulkan (b11597) or R5MtpKvCropDiagVulkan (b11608) BuildKeys. Define a new R5MtpKvOnlyVulkan in ignored tools/evox2/benchmark/configs/local.psd1, copying the existing mapping format but pointing to the new build-vulkan-mtp-kv-only/bin/Release directory (the BuildKey uses BinDir, not a filename; follow the actual Build-Vulkan.ps1 output).

~~~powershell
git fetch origin
git switch investigation/r5-mtp-pp-kv-crop-stage1-20261014
git pull --ff-only

python .\tools\evox2\tests\test_mtp_kv_crop_stage1.py

.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-mtp-kv-only -VulkanSdk C:\VulkanSDK\1.4.357.0 -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4

$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-kv-crop-stage1.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-diag-short -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-diag-short
~~~

**Short gate:** Verify 12 static tests pass and actual build source hash/CLI binary hash match this branch; run A-diag and B-diag with identical inputs/models and binary, only the crop flag different. Expected OFF: requested=0, applied=0, FA>=1, logits/nextn present, 1+ K write and 1+ V write. Expected ON: requested=1, applied=1, **FA=0**, logits/nextn absent, **1+ K write and 1+ V write**. Compare measured graph_nodes, full output text (strip performance footer) and Draft generated/accepted counts; both exit 0 and no backend errors. If ON has FA>0, or K/V writes are not demonstrably present, STOP; inspect graph and cache buffers. No numbers for Stage B have been measured yet.

**Performance only after short gate:** Use separate, diagnostics-OFF same-binary ABBA:
~~~powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-64k -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-64k
~~~
Measure PP, TG and total because Stage B also affects generation-time zero-output Draft catch-up. Full Draft KV numerical parity and RGP confirmation of actual GPU FA dispatch absence remain future validation. Stable r5 inference source is unchanged; only this experiment branch contains the new C++ code.

## Vulkan b11618 Stage-B KV-only short result — 2026-10-14 19:26 JST

**Status: SHORT ACTIVE-GRAPH AND OUTPUT PARITY PASS; 64K PERFORMANCE UNMEASURED.** User ZIP `20261014-192602-059-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `22a2140ed0cad167dfb9bce7efc71182f68dd480631e49575b575457dc06744e`. Clean source commit `5ea504315450aeb3ef9e0160bfeea2c0da965960`, Vulkan b11618, Clang 20.1.8, identical validated executable SHA256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2` in both A/B. Target/Draft GGUF paths and metadata match; their SHA256 are null in `conditions.json` and have not been verified cryptographically. Exact same CLI args, 163 input/32 generated tokens, ctx32768; both with `LLAMA_MTP_KV_CROP_DIAG=1`, only crop env = 0/1.

| Active Draft zero-output graph | A OFF | B ON |
| --- | ---: | ---: |
| crop_requested / crop_applied | 0 / 0 | **1 / 1** |
| graph_nodes | 133 | **31** |
| GGML_OP_FLASH_ATTN_EXT nodes | 1 | **0** |
| moe_matmul_id / ffn_weight_mm | 3 / 11 | **0 / 0** |
| matmul | 22 | 5 |
| GGML_OP_SET_ROWS | 2 | **2** |
| classified k_writes / v_writes | **0 / 0 (unrecognized)** | **1 / 1** |
| logits / nextn | 1 / 1 | 0 / 0 |
| Process status | OK, exit 0 | OK, exit 0 |
| Draft accepted / generated | 17 / 27 | **17 / 27** |

All eight active graph samples agree (163-token prefill and subsequent 3-token generation catch-ups): Stage B prunes FA, retains two named K/V cache writes and avoids output tensors. A's two SET_ROWS graph nodes remain, but index-name classification still fails even with src[1]; do not interpret the A k/v=0 labels as missing caches. Stage B graph reduction is 133→31 (~77%). GPU dispatch elimination and bytewise K/V equality have NOT been separately measured.

Generated `stdout.log` is byte-identical after removing only the trailing performance footer. Both runs exit 0 without runtime errors. A: PP 97.89 tok/s (1665.14 ms), TG 15.59 tok/s (1988.58 ms). B: PP 275.56 tok/s (591.52 ms), TG 35.05 tok/s (884.33 ms). These ratios are **NOT causal speed estimates**: only A→B one run each, short prompt, diagnostic overhead and possible driver/kernel warmup. Earlier Stage A (still with FA=1) showed similarly large short A→B timing changes. 64k diagnostics-OFF ABBA is needed.

**Next gate:** With the same b11618 executable and existing `R5MtpKvOnlyVulkan` BuildKey, run `stage1-kv-only-64k` A1/B1/B2/A2 after `-PlanOnly`; do not rebuild or turn on graph diagnostics. Require exit0, output and MTP acceptance equality; compare PP and TG under counterbalanced order. Stop before 128k on any mismatch/crash. Full K/V numerical parity and RGP GPU-dispatch verification remain future checks. This update changes documentation only.

## Stage B native Vulkan 64k ABBA — 2026-10-14 19:37–19:55 JST

**Status: STAGE-B 64K FUNCTIONAL + PERFORMANCE A/B PASS (2 runs/arm); PP improvement strongly supported within this session; TG improvement smaller/noisier; KV buffer parity and actual GPU dispatch still unverified.** ZIP `20261014-193747-315-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `a83c1eef972acf74da174aac424ddef1a2c5874c89ec0ff4b641fe466021520c`. Four consecutive complete OK/exit0 runs in 17.5 minutes (A1,B1,B2,A2). Native Vulkan b11618, compiler Clang20.1.8, source `5ea504315450aeb3ef9e0160bfeea2c0da965960` clean, same `R5MtpKvOnlyVulkan` CLI sha256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2`, verified artifact digest `c719ec9e0801852fcc29bc5aebe3ebcc6c1e7811bdfd42acd011071f6c81f30a`. Same target PLE16 and standalone MTP Q8_0 paths/filesizes/timestamps, identical input sha256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, target/Draft GGUF hashes null/unverified; ctx65536, 61,789 input tokens, 512 output, 2048/1024 batch, f16 KV, QSA union=1/minKV32768, temperature0, UMA label96GB. `LLAMA_MTP_KV_CROP_DIAG` explicitly **unset**, RGP/profiler markers unset. `conditions.json` A1 vs B1 differ only in crop flag and routine run IDs/times/label.

| Sequence | Flag | PP tok/s | PP time (s) | TG tok/s | TG time (s) | Total (s) | Draft accepted/generated |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | OFF | 314.41 | 196.526 | 27.80 | 18.381 | 214.907 | 295/430 |
| B1 | ON | **325.50** | 189.828 | 28.74 | 17.778 | 207.606 | 295/430 |
| B2 | ON | **325.57** | 189.785 | 29.02 | 17.609 | 207.394 | 295/430 |
| A2 | OFF | 313.86 | 196.865 | 28.62 | 17.854 | 214.719 | 295/430 |
| **A mean** | OFF | **314.135** | **196.696** | **28.210** | **18.117** | **214.813** | same |
| **B mean** | ON | **325.535** | **189.807** | **28.880** | **17.693** | **207.500** | same |

Mean B–A PP throughput **+11.400 tok/s / +3.629%**, PP duration **−6.889s / −3.502%**. Mean TG throughput **+0.670 tok/s / +2.375%**, TG duration **−0.424s / −2.339%**. Total inference duration **−7.313s / −3.404%**. Throughput and duration percentages differ because denominators differ; do not swap them. PP A1/A2 314.41/313.86 (spread 0.55), B1/B2 325.50/325.57 (spread 0.07), so the PP difference is substantial relative to observed within-arm variation and survives the reversed A2 check. TG A1/A2 27.80/28.62 (spread 0.82), B1/B2 28.74/29.02 (spread 0.28); TG is positive on average but there is substantial run-order drift, so weaker causal claim. Only two repetitions/arm: not a formal confidence interval.

**Functional correctness:** All four `stdout.log` files are byte-identical up to the single trailing `[ Prompt: ... | Generation: ... ]` line. `stdout.log` contains a pre-existing invalid UTF-8 byte sequence, so bytewise equality was assessed on raw bytes after stripping the performance footer rather than via strict UTF-8 decoding. All runs exit0 with no differing generated text; each reports 512 generated tokens, Draft 295 accepted / 430 generated, acceptance ratio 0.68605, graphs reused 210. No model/source/binary changes between runs. GPU resource CSV monitor medians for process-local memory ~85.36–85.47GiB across arms, similar peak 85.57GiB, and RAM ~9.85–9.96GiB; no obvious memory pressure distinction. Those counters are not calibrated GPU utilization measurements.

**Where PP gain develops:** Using `slot print_timing` progress lines at 2k intervals, paired means and approximate block clock times:

| Prompt segment | Mean A segment time | Mean B segment time | B savings / A |
| --- | ---: | ---: | ---: |
| 4–8k | 8.670s | 8.520s | **1.73%** |
| 8–16k | 19.745s | 19.475s | **1.37%** |
| 16–32k | 51.250s | 49.975s | **2.49%** |
| 32–49k | 58.485s | 56.210s | **3.89%** |
| 49–61k | 46.355s | 44.235s | **4.57%** |

Cumulative A–B time gap from 4,096 to 61,440 tokens grows from 0.345s to **6.435s**. Later KV ranges show stronger improvements, **consistent with removal of increasingly costly Draft flash-attention work**. This is a better causal fingerprint than Stage A's 64k +0.53% mean PP with no convincing KV-depth gradient. Stage A and B use different compiled binaries and times, so the direct within-Stage-B ABBA is the primary comparison. Stage B has already shown `fa=0` on the real zero-output Draft graph in the earlier short diagnostic (b11618); actual Vulkan dispatch reduction remains a targeted RGP verification.

**Assessment / next:** Pass the 64k functional and practical performance gate for single-session experimentation. PP gain is reproducible across the paired OFF/ON runs here, TG gain plausible but less robust. Preserve b11618 binary, commit and raw ZIP; do **not** merge experimental source into stable r5 yet. Next optional steps by value: (1) independently verify GPU Draft FA dispatch absence using RGP when useful, (2) check a longer 128k workload with same-build OFF/ON (start with a shorter A/B functional run; ABBA if resource/time allow), (3) if preparing source for merge, validate numerical Draft K/V cache parity instead of relying only on output/acceptance coincidence, then ROCm/upstream+Vision compatibility. Neither 128k nor ROCm has been measured for Stage B. Stable r5 changes here are documentation only.

## Stage B Vulkan 128k A/B and historical MTP-OFF comparison — 2026-10-14

**Status: STAGE-B 128K SINGLE A/B FUNCTIONAL PASS; PP +6.68% WITH LONG-KV GRADIENT, TG +1.36% SINGLE-PAIR INCONCLUSIVE; HISTORICAL MTP OFF NOT REACHED (CROSS-BUILD).** User ZIP `20261014-201218-810-qwen38-r5-mtp-kv-crop-stage1.zip` actual SHA256 `26426595ac0a342dce22ab87bb52e930351149dbc80afe2aa5541e7e625c63d1`. 2/2 OK exit0; start 20:12–20:29 JST. Both Vulkan b11618 from embedded executable commit `5ea504315`, executable SHA256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2`, runtime bundle Verified `c719ec9e0801852fcc29bc5aebe3ebcc6c1e7811bdfd42acd011071f6c81f30a`. `GitIdentity.Dirty=True` in both local checkouts, identical fingerprint; the **compiled executable** is verified against the Stage-B build identity. Same PLE16 main GGUF and Unsloth self-contained Draft Q8_0 paths, lengths, mtimes; their SHA256 is null and not independently confirmed. Input `nlp-survey-ch3-d15-b1.txt`, SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, 126,253 tokens, ctx=131072; 512 generated. 96GB UMA label, f16 KV, threads4, batch2048/ubatch1024, temperature0, QSA union ON/minKV32768, diagnostic OFF, source/binary identical within pair.

| b11618 128k | A: MTP ON, KV-crop OFF | B: MTP ON, KV-only ON | Relative B to A |
| --- | ---: | ---: | ---: |
| PP tok/s | 278.06 | **296.63** | **+6.678%** |
| TG tok/s | 23.47 | **23.79** | +1.363% (single-pair uncertainty) |
| PP seconds | 454.056 | **425.627** | **−28.429 s / −6.26%** |
| TG seconds | 21.772 | 21.477 | −0.295 s |
| Native PP+TG seconds | 475.828 | **447.104** | **−28.724 s / −6.04%** |
| Draft accepted/generated | 295 / 429 | 295 / 429 | identical 68.765% |
| Graph reuse | 210 | 210 | equal |

Both `stdout.log` files are byte-identical *except* for the trailing `[ Prompt: ... | Generation: ... ]` footer; raw bytes used because this CLI output contains invalid UTF-8. Both have 512 output tokens and exit0. GPU process-local monitor maxima ≈88.7GiB in both, median ≈88.5/88.4GiB; no obvious memory pressure divergence. The result is one A→B sequence with no counterbalanced replicate. Hence the **PP increase is large but not yet independently replicated at 128k**; the modest TG +1.36% is potentially normal run variation.

PP interval timings extracted from 2,048-token progress checkpoints show depth dependence:

| Prompt segment | A seconds | B seconds | B segment reduction |
| --- | ---: | ---: | ---: |
| 16–32k | 50.08 | 49.14 | 1.88% |
| 32–49k | 57.42 | 54.97 | 4.27% |
| 49–65k | 60.99 | 57.76 | 5.30% |
| 65–82k | 63.57 | 58.62 | 7.79% |
| 82–98k | 65.77 | 60.74 | 7.65% |
| 98–115k | 68.13 | 62.03 | 8.95% |
| 115–125k | 43.54 | 39.49 | **9.30%** |

This trend is consistent with skipping the Draft's KV-length-dependent FA in zero-output catch-up; it does not independently measure Vulkan GPU dispatch and cannot identify all remaining MTP-ON target/Draft costs.

### Historical MTP OFF reference — not a source-identical comparison

From `R5-MTP-VULKAN-64K128K-ABBA-2026-10-11.md`: Vulkan r5 **b11560**, source `f8d24494f`, same input file/126253, context, QSA union=1/minKV32768, main/draft model names, temp0, 512 output, four-run ABBA. 128k **MTP OFF** (A1/A2 mean) PP **335.455 tok/s**, TG **24.140 tok/s**, PP 376.363s, TG 21.171s, PP+TG 397.535s. That old same-binary MTP ON (B1/B2 mean) PP **303.965**, TG **23.475**, total 437.121s. Against the old **OFF** numbers the new b11618 Stage B ON is PP **−11.57%**, TG **−1.45%**, and **+49.57s (+12.47%)** total. However old b11560 MTP ON PP **303.965** is itself **faster than today's b11618 ON PP 296.63**, despite Stage B improving its own b11618 OFF-crop counterpart (278.06→296.63). The cross-build absolute differences are NOT a controlled Stage B or MTP penalty and may reflect source/kernel/scheduler differences, measurement drift and other conditions. Historical b11560 MTP OFF vs ON generated text differed, so full output equality across ON/OFF is not guaranteed.

**Recommended next:** If the immediate question is whether Stage B has overcome the **MTP OFF** baseline, measure **MTP OFF on the same b11618 executable** at 128k (one run minimum, A/B counterbalanced if making a speedup claim), same input, --seed, temp, batch, union and f16 cache; disable Draft MTP completely, not just `LLAMA_MTP_DRAFT_PREFILL_KV_CROP`. This clean reference isolates the current-binary MTP penalty and avoids comparing b11560 to b11618. Alternatively run B→A repeat for robust 128k Stage B PP effect/TG uncertainty. No further source merge or ROCm conclusion is warranted yet. Stable r5 has documentation only.

## Same-binary MTP-OFF 128k benchmark plan — 2026-10-14

**Status: PLAN ONLY; MTP-OFF RUN NOT YET EXECUTED.** Added a dedicated `stage1-kv-only-128k-mtp-off` CLI job to `tools/evox2/benchmark/configs/qwen38-r5-mtp-kv-crop-stage1.psd1` on the Stage-B investigation branch, and committed the earlier manually supplied `stage1-kv-only-128k` A/B job into the tracked plan for repeatability.

**Comparability:** Both use the exact `R5MtpKvOnlyVulkan` BuildKey (preserve the already measured Vulkan b11618 binary; **do not rebuild**), `UnslothPle16` main model, `Context=131072`, `InputKey='128k'`, the existing 512-output/default sampling/batch/f16 settings, `GGML_VK_QSA_UNION=1` and `GGML_VK_QSA_UNION_MIN_KV=32768`. The new job's effective parameters override inherited plan defaults with `Mtp=$false` **and** `DraftModelKey=''`: `Measure-LlamaCli.ps1` otherwise throws when a Draft model key is present but MTP is false. With the blank key, it emits `--spec-type none` and no `-md`/Draft args. `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` and `LLAMA_MTP_KV_CROP_DIAG` are explicitly unset. It has one variant `MTP-off` (not an ABBA run).

**Commands:**

~~~powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-kv-crop-stage1.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-128k-mtp-off -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob stage1-kv-only-128k-mtp-off
~~~

**Local-modified plan caveat:** The 128k A/B job was previously added manually from chat instructions, so a tracked local plan edit may block `git pull --ff-only`. Save a copy outside the worktree first; restore only that tracked plan file, then pull. The repository's plan now includes both the original A/B and the new MTP-OFF job. Do not stash-pop the old manual A/B job on top of the canonical plan without reviewing duplicates. Keep `local.psd1` / BuildKey and 128k input mapping unchanged.

**Validation:** New `test_128k_mtp_off_baseline_has_no_draft_and_reuses_stage_b_binary` static regression checks job defaults/overrides and `Measure-LlamaCli.ps1` OFF behavior. Suite now has **13 tests**. Source review and structural checks passed; Windows PowerShell `-PlanOnly` / actual benchmark not run by the remote assistant. Check the plan row reports `nomtp`, has no Draft model argument, and uses the preserved b11618 artifact. After measurement compare PP/TG/PP+TG to b11618 Stage B ON; historical b11560 OFF comparison remains only secondary cross-build context.

## Native Vulkan b11618 128k MTP-OFF control and baseline drift — 2026-10-14 21:00 JST

**Status: SAME-BINARY MTP-OFF CONTROL PASS; MTP ON Stage B residual PP cost ~13.01 s at 128k. CROSS-BUILD MTP-OFF PP REGRESSION INDICATED, ROOT CAUSE UNDETERMINED.** Native ZIP `20261014-210036-513-cli-vulkan-b11618-ctx131072-199dda7e51ac.zip`, SHA256 `ce66f7d78a0b7fb769fdcdf4124549e6c6e626efafc3c05f11516fbc04f995d3`. 1/1 result OK exit0, ran 21:00:36–21:08:28 JST. Executable Vulkan b11618 / Clang20.1.8, exact same CLI SHA256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2` and runtime bundle digest `c719ec9e0801852fcc29bc5aebe3ebcc6c1e7811bdfd42acd011071f6c81f30a` as Stage-B A/B from ~20:12–20:29. Runtime compiled from `5ea504315450aeb3ef9e0160bfeea2c0da965960`; current Git working-tree HEAD at measure time differed due to docs/plan commits but manifest and CLI identity matched. Input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, 126253 tokens, ctx131072, 512 output, f16 KV, QSA union=1/minKV32768, same model path and measured driver `32.0.31041.1004`; draft absent. Confirmed actual command `--spec-type none`, no `-md`, `DraftModelIdentity=null`, effective MTP false and no Stage-B crop/diagnostic environment flags. Normal Vulkan union reports active (plus pre-threshold fallback). No exceptional GPU errors observed.

| 128k native | b11560 OFF old ABBA mean | b11560 ON old ABBA mean | b11618 OFF current | b11618 ON Stage-B ON |
| --- | ---: | ---: | ---: | ---: |
| PP tok/s | **335.455** | 303.965 | **305.98** | 296.63 |
| TG tok/s | 24.140 | 23.475 | **23.74** | 23.79 |
| PP seconds | **376.363** | 415.354 | **412.61658** | 425.62664 |
| TG seconds | 21.171 | 21.767 | 21.52917 | 21.47698 |
| PP+TG seconds | **397.535** | 437.121 | **434.14575** | 447.10361 |

**Same b11618 ON vs OFF**: Stage B ON PP throughput -3.0558% from the MTP-OFF control; +13.01006 seconds PP time and +12.95786 seconds total wall reported in native timing (~2.98% slower total). TG differs by just +0.05 tok/s and -0.05219s, not meaningful from one measurement per condition. Note ON and OFF are not necessarily text-identical, unlike Stage B ON/OFF within MTP; do not assume acceptance applies to MTP OFF. MTP OFF has 507 reused graphs, consistent with historical OFF 507; Stage-B ON has 210, consistent with historical ON 210.

**Cross-build drift**: historical b11560 MTP OFF (2-run mean) 335.455 tok/s / 376.363s PP vs current b11618 OFF 305.98 tok/s / 412.61658s: -8.7866% PP throughput, +36.2536s. This is a real difference between archived and current readings, not proof of a source-caused regression (different days/binaries, only one new control). Historical b11560 MTP OFF process GPU-local peak ~83.370 GiB vs b11618 ~83.4 GiB; memory broadly similar. Contemporary 128k Stage-B ON and OFF use slightly more process GPU-local (~88.7 GiB) as expected for Draft. GPU driver in contemporary conditions is `32.0.31041.1004`; recent monitor CSVs do not contain device temperature or clock frequency. No evidence currently distinguishes thermal/power/driver/kernel-cache/environment variation from compiler/code effects.

**Source-diff audit**: GitHub compare pinned b11560 source `f8d24494fcacee01f8c9858595c3e778a1698d11` against b11618 source `5ea504315450aeb3ef9e0160bfeea2c0da965960`: 58 descendant commits, 26 changed files. Changes are predominantly MTP phase tracing and RGP diagnostics, plus experimental opt-in Draft KV-only helper and mask allocation guard. In particular `ggml/src/ggml-vulkan/ggml-vulkan.cpp` now funnels several QSA/FA dispatch sites through an **opt-in marker wrapper** even when the marker environment is unset; `ggml-vulkan-common.h` adds a disabled-by-default dispatch ordinal check, and `ggml_vk_build_graph` an inactive per-node marker guard. The original Vulkan dispatch parameters appear preserved on uninstrumented paths, and no wholesale Target QSA algorithm replacement is apparent. Nevertheless wrapper overhead, codegen/layout effects or state-related behavior are **hypotheses only**, not measured causes. The recorded current build uses Ninja Multi-Config, Clang20.1.8, LLVM Windows toolchain; historical b11560 full toolchain manifest is not in the current ZIP, so do not assert perfect build-flag parity.

**Priority next experiment**: Re-run the archived **b11560 executable** (SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`) with exactly the same 128k MTP OFF input/settings **on the present machine now**. Do not rebuild either executable. If old b11560 restores ~335 tok/s while b11618 still gives ~306 on immediate recheck, focus on source/compiled-runtime differences and split out disabled diagnostic Vulkan wrapper versus generic inference differences. If b11560 also drops to ~306, focus on environment (clocks, temperature, background load, Windows power/RDP/process competition, memory pressure, shader cache), not Stage B. A cheap alternative is same-day 64k OFF old/new before repeating full 128k. For reliable significance use counterbalanced old/new/new/old with adequate cooldown, but begin with one recheck to conserve time. Capture executable/runtime hashes, driver, GPU clocks/temps by external instrumentation (current resource CSV has no thermal metrics), PP per-KV checkpoints and memory. Do NOT merge any experimental source into stable r5 on this evidence. Updated docs only.

## b11560 same-day rerun and resource CSV triage — 2026-10-14 21:45 JST

**Status: CROSS-DATE PP SLOWDOWN REPRODUCED ON ARCHIVED EXECUTABLE; CAUSE NOT YET IDENTIFIED.** User ZIP `20261014-214519-917-cli-vulkan-b11560-ctx131072-84b9ed15488a.zip`, SHA256 `50a807c73fae39610c4133932080056b9b2c806e51a1a2f684edc9f070db5cdc`. Actual archived executable SHA256 **`611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`** and runtime digest **`be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2`**, matching documented 2026-10-11 b11560 ABBA artifacts. b11560 2026-10-14 21:45:19–21:53:13 JST, Clang20.1.8, 128k ctx, 126253 input/512 output, `Mtp=false`, `--spec-type none`, exact input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, identical main model path/size/mtime to contemporary b11618. All effective conditions besides executable/build-runtime identity match: -b2048, -ub1024, f16 KV, 4/4 threads, -ncmoe0, temp0, seed1234, --ignore-eos, QSA union=1/minKV32768, diagnostic environments unset. Both contemporary runs exit0; 10/14 machine Win11 build26300 / Radeon driver32.0.31041.1004, RDP display adapter present. No GPU clocks or temperatures captured.

| 128k MTP OFF | Archived b11560 2026-10-11 mean (two ABBA OFF) | Same archived b11560 re-run 2026-10-14 | b11618 control 2026-10-14 |
| --- | ---: | ---: | ---: |
| PP tok/s | **335.455** | **305.18** | 305.98 |
| TG tok/s | 24.140 | **23.68** | 23.74 |
| PP seconds | 376.363 | **413.70089** | 412.61658 |
| TG seconds | 21.171 | **21.57938** | 21.52917 |
| Native total seconds | 397.535 | **435.28027** | 434.14575 |

Old executable's **cross-date PP rate −9.03%**, while contemporary b11560/b11618 rate difference is only ~**0.26%** (b11560 lower); thus a code-only explanation for the ~9% change is strongly disfavored. The 10/14 b11560 vs b11618 real prompt-progress checkpoints are nearly identical throughout: at 32768 tokens 78.82/78.81 s, 65536 188.88/188.47 s, 98304 306.22/305.52 s, and 124928 404.69/403.78 s (old/new). They do not show a unique code-path stall. The two were run ~45min apart rather than counterbalanced, so no formal equivalence claim.

**10/14 resource triage:** 234 samples b11618 and 235 samples b11560 at ~2s cadence. Exclude load ramp by using ~46–448s after first sample for PP-only descriptive medians:

| Counter | b11618 21:00 | b11560 21:45 |
| --- | ---: | ---: |
| Target GPU Local median | 83.15 GiB | 83.15 GiB |
| Target GPU Shared median | 0.843 GiB | 0.843 GiB |
| System RAM used median | 8.73 GiB | 8.75 GiB |
| System Commit median | 93.85 GiB | 93.84 GiB |
| Commit limit | 127.65 GiB | 127.65 GiB |
| Disk read median | 0 MiB/s | 0 MiB/s |
| Page reads median | 0/s | 0/s |

Most prompt intervals have no sustained disk reads or hard page reads; the intense spikes are primarily during GGUF startup. Model/VRAM/commit counters remain remarkably similar across b11560 and b11618. The prior 10/11 b11560 128k MTP-OFF ABBA also documented peak Target GPU Local ~83.370 GiB, equal to present peak ~83.37 GiB. Soft `PageFaults_PerSec` is not a valid disk-paging measure. `TargetGPUEngineSum_Percent` is sampled inconsistently (median zero, sporadic bursts) and does **not** establish GPU idle/busy or frequency. Neither 10/14 monitor has GPU core/memory clocks, junction/hotspot temperature, board/package power or throttling flags. Ambient outdoor/room temperature alone cannot exclude changes in thermal or power management.

**Unresolved hypotheses (not findings):** lower GPU effective clocks or power envelope, a changed Windows power plan/Windows/driver state, concurrent GPU load, or a differing benchmark/OS environment on 10/11. Do not blame Stage B, Vulkan RGP wrappers, paging or thermal throttling as a demonstrated cause without comparing the original run.

**Precise 2026-10-11 raw data to retrieve next:** Document `R5-MTP-VULKAN-64K128K-ABBA-2026-10-11.md` identifies ZIP **`r5-mtp-vulkan-64k128k-abba-20261011-171132.zip`**. Target its 128k **A1 MTP OFF started 17:28:06 JST** and **A2 MTP OFF started 17:51:47 JST** (two runs). Need both `conditions.json`, `result.json`, `stderr.log`, `resources.csv` at minimum; ideally full archive for consistent metadata. Compare same-binary SHA, driver/OS build, RDP state, model/input SHA, env, per-KV prompt timing, commit/VRAM/paging and concurrent-resource counters. Existing historical summary supplies only peak Local, not per-time samples. If clock/temperature not present in original CSV, compare resource profiles first and capture new dedicated AMD sensors (GPU clocks, temperature, power and throttling) before other optimization work. Stable r5 source untouched; analysis is documentation only.
