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

## Forensic 10/11-vs-10/14 Windows Update + 128k resources — 2026-10-14 22:00 JST

**Finding: SAME EXECUTABLE, IDENTICAL PARAMETERS/OUTPUT, ~9% PP cross-date loss isolated to KV above 32k. Windows/Defender changes are observed but root cause NOT established.** Primary user evidence: uploaded recovered `r5-mtp-vulkan-64k128k-abba-20261011-171132(1).zip` (74 members) and `WU-Defender-20261011-14.csv` (90 selected events); compared with independently archived 2026-10-14 b11560 and b11618 MTP-OFF ZIPs. Historical 10/11 128k A1 17:28:06 and A2 17:51:47, versus 10/14 archived b11560 21:45 and b11618 21:00, each ctx131072, 126,253 input, 512 generated, temperature0, QSA union=1/minKV32768, `-b2048 -ub1024 -t4 -tb4`, f16 KV, and all other CLI arguments identical. Input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`; main GGUF path, size 81961816672, and mtime identical (model SHA absent). Archived `llama-cli.exe` sha256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949` and FULL 20-artifact runtime digest `be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2` match 10/11 and 10/14; executable and DLL blobs were not overwritten. All three b11560 output `stdout.log` byte-identical except final native timing footer. OS reporting `10.0.26300` and Radeon driver `32.0.31041.1004` unchanged, RDP active all runs.

**Material Windows-side version delta:** `SystemIdentity.PowerShellVersion` and Microsoft Remote Display Adapter `DriverVersion` both **`5.1.26100.9549` / `10.0.26100.9549` on 10/11**, and **`5.1.26100.9711` / `10.0.26100.9711` on 10/14**; the RDP adapter session ID also changes `0001`→`0002`. Same reported OS major build does not mean identical updated Windows components. Do NOT conclude RDP causes QSA slowdown without an independent test or detailed installed KB record.

### PP changepoint at 32k (b11560 archived exe only)

The `stderr.log` `slot print_timing: ... prompt processing ... n_tokens ... t=...` records give cumulative prompt-time since prompt evaluation started (not startup/model-load time):

| Checkpoint | 10/11 b11560 A1/A2 mean | 10/14 b11560 | Time gap |
| --- | ---: | ---: | ---: |
| 4,096 | 5.790s | 5.830s | +0.040s |
| 16,384 | 31.960s | 31.810s | −0.150s |
| **32,768** | **79.335s** | **78.820s** | **−0.515s** |
| 49,152 | 127.165s | 132.610s | +5.445s |
| 65,536 | 177.060s | 188.880s | +11.820s |
| 98,304 | 281.135s | 306.220s | +25.085s |
| 124,928 | 368.475s | 404.690s | **+36.215s** |

| PP interval | 10/11 A1/A2 mean s | 10/14 b11560 s | Extra time relative to old |
| --- | ---: | ---: | ---: |
| 16–32k | 47.375 | 47.010 | **−0.77%** |
| 32–49k | 47.830 | 53.790 | **+12.46%** |
| 49–65k | 49.895 | 56.270 | **+12.78%** |
| 65–82k | 51.695 | 58.210 | **+12.60%** |
| 82–98k | 52.380 | 59.130 | **+12.89%** |
| 98–115k | 53.495 | 60.310 | **+12.74%** |
| 115–125k | 33.845 | 38.160 | **+12.75%** |

This abrupt speed breakpoint coincides with configured **`GGML_VK_QSA_UNION_MIN_KV=32768`**. Identical b11560 QSA startup lines on both dates: grouped union ON, fallback before threshold, then `qsa-union active (r5)`, `path=1 Br=16 Bc=64 f32acc=1 groups=16 capacity=32768 min_kv=32768 scratch=73400576`. This is strong evidence to localize the slowdown to workload conditions introduced above 32k, in particular the Vulkan QSA-union path or its GPU scheduling/power circumstances. **Temporal correlation is NOT proof that QSA shader or the Windows update is defective**: longer KV also increases generic GPU demand, and 32k coincides with ≈80 seconds of continuous inference which might cross a temperature/power threshold. More controlled profiling is needed. The same-date b11618 progress tracks b11560 throughout, reinforcing this is not the Stage-B source change.

### Native resource CSV comparison (PP middle, ~65–330 seconds after first sample)

| Monitor median | 10/11 b11560 A1 / A2 | 10/14 b11560 |
| --- | ---: | ---: |
| Target process GPU Local | 83.119 / 83.119 GiB | 83.088 GiB |
| GPU Shared | 0.843 / 0.843 GiB | 0.843 GiB |
| System RAM in use | 6.662 / 6.677 GiB | **8.797 GiB** |
| System Committed | 94.901 / 94.927 GiB | 93.827 GiB |
| System CPU % (sampled) | 2.4 / 2.35% | 3.7% |
| Disk read median | 0 / 0 MiB/s | 0 MiB/s |
| Hard PageReads median | 0 / 0/s | 0/s |
| Monitor counter collection median | 1066.5 / 1067 ms | 1050 ms |

System RAM +~2.1GiB used on 10/14 and system CPU sampling slightly elevated (may reflect other background processes), but no sustained disk or hard-page readings; GPU Local and KV allocation/logged Vulkan0 memory breakdown are essentially unchanged. Aggregate `TargetGPUEngineSum_Percent` telemetry is sparse and inconsistent (10/11 maximum ~17% vs sporadic 10/14 readings ~90%), so **do not treat it as calibrated clock, true GPU utilization or evidence of GPU contention**. No GPU sensor frequency/power/hotspot/throttle fields in any monitor CSV. Counter-monitor collection time itself was not higher on 10/14.

### Windows Update and Defender event CSV timeline

- 10/11 17:28–17:59: fast b11560 measurements. First subsequent logged quick-scan request is 19:51, skipped; Defender signatures updated at 23:59.
- 10/13 21:02–21:26: multiple WindowsUpdateClient event 26 detections and event 41 downloads; 21:26:50–21:28:26 Defender quick scan completed. These logs are not a full installation/reboot ledger; event 41 descriptions are generic and do not identify specific KBs.
- **10/14 11:52:22**: Defender event **2002** engine version `1.1.26080.3` → `1.1.26090.9`; event 2000 security intelligence `1.459.691.0` → `1.461.17.0` (full update), before the slow 21:00 and 21:45 runs.
- 10/14 19:41:53–19:42:55: Defender quick scan completed, well before the slow 21:00 run.
- **10/14 21:37:50–21:40:19**: Windows Update detections/downloads **between** slow b11618 21:00 and slow b11560 21:45; this particular logged download series cannot by itself explain the 21:00 slowdown. Later 22:04–22:05 signature update to `1.461.20.0` and other update download; screenshot showed platform KB4052623 downloading, but event CSV cannot identify its start time or complete installation history.

**Assessment:** Windows-side component versions changed and Defender updates took place between dates, but evidence **does not attribute** ~9% PP change to Windows Update or Defender; do not disable security or assume thermal throttling. Distinctive 32k changepoint raises priority of Vulkan QSA union/high-KV dispatch timing. Next low-risk action: after pending Windows Update completes and a controlled reboot, run same archived b11560 with 128k/64k OFF to check if the 32k+ loss persists, and collect GPU actual frequency/power/hotspot concurrently. If persistent, use a small controlled 64k QSA union min-KV threshold toggle (32768 vs >=65536) and/or RGP on 40–60k range on same binary to separate union-path-specific latency from generic long-KV clocks; the alternate-flag run cannot by itself be compared causally against an older same-flag run. If investigating Windows packages, collect `Get-HotFix`/full WindowsUpdate installed history and versioned RDP components, keeping update changes as a hypothesis. No source modifications/merge warranted.

## New 10/14 hypothesis: Visual Studio Native Tools inherited environment

**Status: USER-REPORTED ENVIRONMENT DIFFERENCE; NOT YET VERIFIED AS CAUSE.** On 2026-10-14 benchmarks were invoked from PowerShell spawned by **VS2022 x64 Native Tools Command Prompt**. On 2026-10-11, user probably launched **Windows PowerShell directly from Start** and set only execution policy. User also reports RDP was likely active on both dates. This weakens the hypothesis that RDP *presence* changed, although observed RDP driver build still changed 26100.9549→26100.9711.

Reopened source `tools/evox2/benchmark/Evox2.Benchmark.psm1::Get-Evox2RelevantEnvironment`: the logger captures **only names matching `^(GGML_|LLAMA_|HIP_|ROCM_|HSA_|ROCBLAS_|VULKAN_|AMD_)`**. It does NOT capture `PATH`, `VK_*` (e.g. `VK_LAYER_PATH`, `VK_DRIVER_FILES`, `VK_ICD_FILENAMES`, `VK_INSTANCE_LAYERS`), `OMP_*`, `KMP_*`, `VSCMD_*`, `VSINSTALLDIR`, `INCLUDE`, `LIB` or `CL`. Reinspect native 10/11 b11560 128k A1/A2 `conditions.json` vs 10/14 same-binary b11560: logged `Environment` dictionaries are IDENTICAL: `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `HIP_PATH=C:\Program Files\AMD\ROCm\7.2\`, `HIP_PATH_72` same, `VULKAN_SDK=C:\VulkanSDK\1.4.357.0`. Therefore the *logged* environment proves matching QSA threshold but does NOT rule out command prompt inheritance differences.

Source-binary and accompanying runtime bundle SHA are identical across dates, so changed **compile flags** cannot explain differences in this prebuilt b11560 executable. Runtime `PATH`/Vulkan loader/ICD/layer resolution and OpenMP state are plausible but unproven; VS toolchain variables by themselves should not modify the inference algorithm. The striking 32k threshold remains consistent with a GPU dispatch path difference, but also potentially with runtime device state as longer KV increases load.

**Minimal controlled next test (before changing more variables such as reboot):** Launch a truly independent Windows PowerShell session from Start, not a PowerShell child of VS Developer Prompt. With the same archived b11560 executable and same 128k MTP-OFF command, test whether PP returns toward the 10/11 **335.455** tok/s from today's VS-origin **305.18** tok/s. A faster 64k probe can be used first but will expose a smaller portion of the >32k interval. Record selective environment snapshots in both shell types BEFORE setting benchmark-specific QSA variables, including `PATH`, `VK_*`, `GGML_*`, `VULKAN_*`, `OMP_*`, `KMP_*`, `VSCMD_*`, `VS*`, `CL`, `INCLUDE`, `LIB`. Compare carefully; do not post full environment blindly because unfiltered env dumps may include credentials. If normal shell also slow, inheritance becomes less likely and attention returns to Windows/Vulkan runtime or power state. Keep reboot/Defender update changes separate from shell A/B if possible. No code changes to runtime.

## Normal PowerShell b11560 128k control — 2026-10-14 22:37 JST

**Finding: VS2022 Native Tools parent-shell NOT THE PRIMARY CAUSE of cross-date PP slowdown.** User archive `20261014-223706-813-cli-vulkan-b11560-ctx131072-84b9ed15488a.zip`, SHA256 `d905e5c5c8f7b6362044748e74a39706644021858181918541d42cdf2e223b27`, started 22:37:06 JST. Launched directly from normal Windows PowerShell; Windows Update downloads completed but machine **not rebooted**. Same exact archived b11560 `llama-cli.exe` SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`, identical runtime digest `be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2` as 10/11 and 10/14 developer-shell tests. Native exit 0, MTP completely OFF (`--spec-type none`), 126253 input and 512 output, current `Environment` and entire `EffectiveCondition` dictionary **identical** to both old-binary VS-shell run and 2026-10-11 old-binary OFF A1/A2. Input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`. No Draft model, QSA union=1/minKV32768, `ggml_vulkan` logs same qsa-union activation `path=1 Br=16 Bc=64 capacity=32768`; binary/driver/model command unchanged. Generated stdout byte-for-byte identical after stripping final CLI timing footer compared with both 10/11 b11560 OFF runs and 10/14 developer-shell run. No runtime errors.

| 128k MTP OFF (b11560 except row shown) | PP tok/s | TG tok/s | PP seconds | TG seconds |
| --- | ---: | ---: | ---: | ---: |
| 2026-10-11 b11560 A1/A2 mean | **335.455** | **24.140** | **376.363** | 21.171 |
| 2026-10-14 b11560 developer-shell | 305.18 | 23.68 | 413.701 | 21.579 |
| 2026-10-14 b11560 normal PowerShell | **305.90** | **23.66** | **412.733** | 21.599 |
| 2026-10-14 b11618 developer-shell | 305.98 | 23.74 | 412.617 | 21.529 |

Normal versus developer-shell old-binary PP **+0.236%** (0.72 tok/s), while 10/11 mean versus normal old-binary PP **−8.81%**. Minor same-day drift is far too small to explain cross-date regression. The normal-shell native run did load QSA env vars from benchmarking invocation despite the earlier shell snapshot `env-normal.csv` lacking them *before the benchmark*: use captured `conditions.json` rather than presuming the initial CSV reflects inference time.

**KV progression, actual b11560 `slot print_timing` time in seconds**:

| Prompt tokens | 10/11 A1/A2 mean | 10/14 developer shell | 10/14 normal shell |
| --- | ---: | ---: | ---: |
| 32768 | 79.335 | 78.82 | **78.86** |
| 34816 | 85.195 | 85.25 | **85.35** |
| 49152 | 127.165 | 132.61 | **132.41** |
| 65536 | 177.06 | 188.88 | **188.28** |
| 98304 | 281.135 | 306.22 | **305.33** |
| 124928 | 368.475 | 404.69 | **403.89** |

Once the 32768-KV union threshold is crossed, each subsequent 2k/16k step is roughly 10–13% slower on 10/14 regardless of parent shell. It is not an 80s-on-clock universal warming issue from independent evidence; that competing thermal/power explanation remains open because the same absolute time coincides with crossing 32k. A direct QSA threshold counterfactual or frequency sensor would discriminate.

**Normal-shell resource CSV** ~235 sampled rows; at 65–330sec after monitor start: process GPU Local median 83.088GiB, GPU Shared 0.843GiB, RAM used 8.834GiB, commit 94.070GiB, aggregate CPU median 3.75%, disk read median 0 MiB/s, hard PageReads median 0/s; developer-shell old run Local 83.088GiB, RAM 8.797GiB, CPU 3.7%; 10/11 old A1/A2 Local 83.119GiB, RAM ~6.66–6.68GiB, CPU ~2.4%. No evidence of sustained swapping or process-local GPU memory shift. This monitor still does NOT report actual GPU core clock, VRAM clock, package power, junction/hotspot or throttling flags; aggregate GPU Engine samples unreliable for inference scheduling.

**Next checkpoint:** Since Windows Update finished without reboot and new shell still 305.90 PP, perform ONE controlled reboot, allow Windows/Defender to settle and retest the exact archived b11560 with same 128k MTP OFF. Save pre-reboot `conditions.json`, note power plan and any Windows KB changes; continue to avoid source changes. If PP returns to ~335, transient Windows/GPU execution state is implicated (not proof Defender caused it). If 305 persists, prioritize externally monitored clocks/power/hotspot on >32k and a paired QSA union-threshold A/B or RGP ~34–60k on same binary. Because minKV threshold is the changepoint, changing it will also change compute path and thus cannot by itself prove a Windows OS regression. The next step is runtime/environment A/B, not Stage B source optimization.

## 2026-10-14 22:58 post-reboot b11560 check and RDP certificate

User provided `20261014-225840-041-cli-vulkan-b11560-ctx131072-84b9ed15488a.zip`, native exit0. Archived b11560 executable SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`; same runtime digest as original 10/11 and pre-reboot. Still MTP OFF, main-model/input/provenance same, QSA union ON/minKV32768, grouped-union activated `path=1 Br=16 Bc=64`. Pre-reboot normal PowerShell PP305.90/TG23.66/PP412.733s vs **post-reboot PP306.75/TG23.64/PP411.589s**; PP +0.28%, insufficient to restore old 10/11 b11560 PP335.455. Post-reboot checkpoint: 32768 78.96s, 49152 131.64s, 65536 187.60s, 98304 304.30s, 124928 402.82s; >32k slowdown persists. Windows Update had finished before reboot, and developer PowerShell inheritance was already ruled out; do not conclude update or driver caused loss.

User reports RDP Remote Desktop store certificate subject `CN=NucBox_EVO-X2`, SHA1 thumbprint `3228E07EE0A1ABE02E559D5221BABD3F0D2D6C06`, validity **NotBefore 2026-10-12 21:00:49**, NotAfter 2027-04-13 21:00:49, with previously unseen self-signed/untrusted-CA RDP prompt around 10/13-10/14. Evidence indicates a newer *certificate validity period* than 10/11; not proof of exact generation/installation time, nor of GPU performance change; user suggests RDP itself was active on both dates.

**NEXT user-selected controlled test:** on the **same archived b11560 executable** and same input/128k/MTP OFF parameters, set `GGML_VK_QSA_UNION=0` explicitly, retain `GGML_VK_QSA_UNION_MIN_KV=32768` for a one-switch experiment. Source `ggml-vulkan.cpp` only enables union when `strcmp(value,"1")==0`, so `0` disables it. Check log `ggml_vulkan: QSA grouped-union = off` and absence of `qsa-union active`; capture per-KV PP checkpoints, GPU memory, native runtime. Do NOT directly compare 10/14 union-OFF PP to 10/11 union-ON PP as an equivalently controlled regression test; changing the algorithm may improve or slow throughput for unrelated reasons. A stronger follow-up after OFF is matched old/new OFF if archived, or shifting union minKV to 65536 and testing where the changepoint moves, plus GPU clocks/power/hotspot monitoring. No runtime source changes.

## Historical QSA-OFF baseline and Measure-LlamaCli file timestamp audit — 2026-10-14 late

**Key reframe**: 2026-10-11 17:xx 64/128k ABBA A1/A2 `OFF` meant **MTP OFF**, whereas `GGML_VK_QSA_UNION=1` remained ON in all 8 runs. There is NO 10/11 17:xx QSA-OFF measurement in the recovered full ZIP/script.

Actual earlier 128k QSA-OFF reference: `R5-VULKAN002-VALIDATION-2026-10-09.md`, b11530 `llama-cli`, PLE16 GGUF, same 126253 input tokens and SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, 131072 context, MTP OFF, Vulkan, `-b2048 -ub1024` K/V f16, 512 outputs. **QSA OFF PP179.34/TG24.03; QSA ON PP307.15/TG23.53**. The 2026-10-10 `llama-bench` b11535 head-slice repeated-ANLP 128k OFF183.660/ON310.682 is qualitative secondary context, not exact CLI-equivalent (no generation, no chat template, different prompt-input method). r4 PLE16 128k QSA OFF 178.97 and ON295.68 is more distant cross-build corroboration.

| Data point | Binary / modality | QSA union | PP tok/s | TG tok/s |
| --- | --- | --- | ---: | ---: |
| 10/09 r5 VULKAN-002 128k PLE16 | b11530 llama-cli | OFF | **179.34** | 24.03 |
| 10/09 same-binary control | b11530 llama-cli | ON | **307.15** | 23.53 |
| 10/11 17:xx archived b11560 MTP OFF mean | b11560 llama-cli | ON | **335.455** | 24.140 |
| 10/14 post-reboot b11560 MTP OFF | b11560 llama-cli | ON | **306.75** | 23.64 |
| 10/14 proposed QSA OFF | b11560 llama-cli | OFF | pending | pending |

**Interpretation update:** 10/14 QSA ON PP306.75 is almost the same as 10/09 b11530 QSA ON PP307.15; 10/10 b11535 bench union ON310.682 is also broadly similar but not directly comparable. Therefore **it is possible 10/11 b11560 QSA ON was unusually fast**, rather than 10/14 being uniquely degraded. This cannot be resolved by comparing only dates or mixing different binaries/temperature (10/09 CLI temp0.2 vs 10/11/10/14 temp0). The 10/11 measured within-binary and within-date MTP overhead remains valid. The QSA-OFF 10/09 179.34 is a *historical context baseline*, **not** a same-b11560 October11 OFF control; lack of 10/11 QSA-OFF means its hypothetical value must not be interpolated. The upcoming **10/14 b11560 QSA-OFF** run establishes a new matched same-day ON/OFF reference. If it is roughly ~180, that is compatible with the old QSA-OFF path performance but does not on its own explain 10/11 ON335.46. Analyze per-KV progression and actual driver/power-state evidence before claiming cause.

**Local script timestamp query:** user reports Windows `Measure-LlamaCli.ps1` LastWriteTime 2026-10-13 21:10. GitHub inspect for `tools/evox2/benchmark/Measure-LlamaCli.ps1` yields the same Git blob SHA **`aded8591a070bac05129526c974277207ea43296`** at r5 bootstrap `e76ca92b` on 2026-10-09, at the 10/11 pinned b11560 source `f8d24494f`, and at current stable+investigation branch heads. GitHub `commits?path=...&sha=r5/upstream-refresh-20261009` lists only its 10/09 bootstrap commit, no intervening content revision. Thus 10/13 Windows file timestamp need not mean a source modification; checkout/copy/extraction may reset timestamp. To verify actual local bytes compare `git hash-object tools/evox2/benchmark/Measure-LlamaCli.ps1` with that blob and `git status --short` / `git diff HEAD -- path`; absent local file bytes cannot attest exact local cause of timestamp change.

## 2026-10-14 23:39 b11560 128k MTP-OFF union-OFF control and episodic high-PP hypothesis

**Result: 128k QSA union OFF matches historic October 9 OFF baseline; ordinary October 14 union ON matches historic October 9 ON baseline; October 11 appears to be a stable elevated session, not a single-run outlier. Mechanism UNRESOLVED.** User-provided ZIP `r5-128k-mtpoff-qsa-off-20261014-233908.zip`, one CLI run 2026-10-14 23:39–23:51 JST (inside `20261014-233910-041-cli-vulkan-b11560-ctx131072-6a188646add9`), status OK, exit0; main model PLE16 81961816672 bytes and input SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` (126253 tokens), ctx131072, 512 generated, MTP completely OFF; executable SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`, full runtime digest `be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2`, Clang20.1.8, b11560. The **only intentional change** from same-day b11560 MTP-OFF ON is `GGML_VK_QSA_UNION=0` instead of `1`; log says `ggml_vulkan: QSA grouped-union = off (group=64, min_kv=32768)` and has no `qsa-union active`. Other condition fields/arguments match earlier runs. Native PP **180.32 tok/s** (700153.62ms), TG **23.63 tok/s** (21621.51ms), PP+TG 721775.13ms.

| Reference | Executable | MTP | Union | PP tok/s | TG tok/s |
| --- | --- | --- | --- | ---: | ---: |
| 2026-10-09 r5 VULKAN-002 PLE16 128k single pair | b11530 llama-cli | OFF | **OFF** | **179.34** | 24.03 |
| 2026-10-14 23:39 native control | b11560 llama-cli | OFF | **OFF** | **180.32** | 23.63 |
| 2026-10-09 same r5 VULKAN-002 pair | b11530 llama-cli | OFF | ON | **307.15** | 23.53 |
| 2026-10-14 22:58 post reboot | b11560 llama-cli | OFF | ON | **306.75** | 23.64 |
| 2026-10-11 17:28/17:51 A1/A2 mean | b11560 llama-cli | OFF | ON | **335.455** | 24.140 |

Cross-build 10/09→10/14 OFF baseline +0.55%, ON baseline −0.13%. Contemporaneous 10/14 b11560 union ON/OFF PP ratio **+70.12%**; 10/09 b11530 ON/OFF ratio **+71.26%**. These are close but October9 had b11530 and temp0.2 versus October14 b11560 temp0, so descriptive historical context, not a same-binary reproduction. There was NO 10/11 union-OFF control, hence data do not establish whether 10/11 speed uplift affected only union ON or also OFF. Archived 10/11 eight-run ABBA shows **64k MTP OFF A1/A2 360.57/362.47 PP** (versus Oct9 b11530 64k PLE16 ON mean339.48) and **128k MTP OFF A1/A2 336.06/334.85 PP** (versus ~307 normal). The high state persisted across 17:11–17:59 and different workloads/runs; it is not an isolated random observation. User recalls similar intermittent PP high-side bursts across preceding month; this retrospective report is important but no same-condition sensor trace has yet verified the mechanism.

**New depth-segment comparison:** Actual CLI cumulative PP timestamps for 10/14 b11560 union OFF / union ON(post reboot) / 10/11 union ON(A1/A2 mean): at 32k **78.85 / 78.96 / 79.34 s**; at 48k **149.92 / 131.64 / 127.17 s**; at 64k **242.86 / 187.60 / 177.06 s**; at 96k **470.72 / 304.30 / 281.14 s**; at 122k **680.17 / 402.82 / 368.48 s**. Ordinary ON path reduces each 16k interval increasingly relative to OFF. More importantly the 10/11 faster ON session differs **only after 32k threshold** and is ~10–12% faster in time per 16k segment above that point than 10/14 ordinary ON, despite otherwise identical archived b11560 process/binary. The 32k changepoint is compatible with QSA dispatch/cached shader/runtime state but is not proof the QSA kernel specifically changes; clock/power, dynamic kernel scheduling and GPU availability may correlate with increasing KV. Current resource CSV retains model residency (GPU-local median ~83GiB), no sustained disk/paging, and lacks actual GPU clocks, power or thermal-throttle evidence.

**Revised interpretation / priority:** Avoid labeling October14 a newly introduced Windows/Defender slowdown: October9 pre-update QSA ON and OFF throughput are close to October14, with an intervening reproducible October11 fast period. Windows/RDP updates are chronological clues only, NOT causes identified. The next useful work is to locate another historical unusually-fast **same-executable/same-input QSA ON** session (or an on/off pair within the fast period), log per-2048-token progress plus source/binary/GPU driver identities, and correlate with GPU shader/clock/power/temperature telemetry if it recurs. For prospective repeats, favor a bounded 64k session-level A/B/ABBA (less cost), tagging whether QSA ON is in normal vs high regime; only add QSA OFF if needed to test whether anomaly is union-specific. RGP work should compare the same active dispatch path between normal and high regimes, not infer kernel cause from a QSA flag flip alone. Preserve source and avoid optimizing against an assumed 'regression' until high-state mechanism is understood.

## 2026-10-15 retrospective Qiita ROCm spikes and 10/11 ROCm-before-Vulkan session comparison

**New historical source:** Public Qiita article 6, published 2026-09-06 / updated 2026-09-09, `https://qiita.com/ariera/items/8a4e815db1d109070960`, section `PPは変動が大きい？`. In ROCm `b10798-mix-659e406` on Evo-X2, 32k same-run conditions one high PP **310.33** vs following five trials **248.99–250.33** (median **249.79**, high **+24.24%**), with TG high-run **20.90** vs typical median **20.73**. Separate earlier 64k ROCm PP **245.62** vs four later **190.70/192.14/191.79/192.01** (median **191.90**, earlier **+27.99%**). The author notes prompt-processing checkpoints genuinely faster, not solely final timing summary; consecutive runs within a session are tightly grouped. This demonstrates intermittent ROCm high-PP states **independently of any Vulkan QSA union implementation**, but September setup differs (Unsloth mix binary, UD-IQ3_XXS split, UMA64GiB, OS26200 and earlier input/templates), so it does NOT prove identical October root cause.

**10/11 15:25–16:19 ROCm b11560 immediately preceding 17:11–17:59 Vulkan b11560 ABBA:** `R5-MTP-ROCM-64K128K-ABBA-2026-10-11.md` records ROCm MTP OFF 64k **392.61/391.98 (mean392.295)**, 128k **293.76/295.66 (mean294.710)**; ROCm MTP ON 64k **366.00/364.78**, 128k **274.20/274.73**. All 8 OK, same ROCm executable b11560 `cb50e8092d18381d682c32e3218c5f343eb13108542e5bf8027db0765e22ad11`, source `f8d24494f`; no QSA grouped-union implementation in ROCm. Reproducible on 10/11 (OFF PP arm pair spread 0.16% 64k /0.65% 128k), not a single outlier.

**Cross-check against 10/10 ROCm real-prompt `llama-bench`** report `R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md`: b11543 ROCm repeated ANLP 64k **394.030** and 128k **296.274**. Oct11 b11560 ROCm OFF CLI relative −0.44% at 64k / −0.53% at 128k. This close match gives *no evident large ROCm high-side anomaly specifically on 10/11*, but bench and CLI differ in template/input handling, warmup/outputs and binary: **not a formally controlled same-binary comparison**.

**Additional weaker ROCm reference:** Oct04 r4 ROCm initial OFF means 64k **370.13** and 128k **277.57** (`R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md`), ~6% below Oct11, but upstream/build/temp differed (Oct04 temp0.2 vs Oct11 temp0): don't label Oct11 ROCm upshift from this cross-build contrast.

**Reframed conclusion:** Historical PP-upside events are backend-nonexclusive (ROCm also seen in September), so a universal explanation confined to Vulkan grouped-union code would be inadequate; however October11 data do NOT show ROCm and Vulkan elevated together. ROCm Oct11 15:25–16:19 behaved close to prior-day ROCm, while Vulkan Oct11 17:11–17:59 was +~6.5% 64k and +~9.2% 128k versus Oct09 Vulkan b11530 CLI union ON, and ~9% faster 128k than Oct14 same b11560. Time gap ~52 min between ROCm end and Vulkan start; conditions could change. Distinguish possible shared GPU/power state, Vulkan QSA-specific conditions, and separate unrelated mechanisms; none proven. To resolve, find another matched ROCm CLI at same b11560/session or collect simultaneous GPU sensor and profiler traces when elevated state recurs.

## 2026-10-15 00:21 ROCm pre-Vulkan archive independently reverified

**Native data verified** from recovered full archive `r5-mtp-64k128k-abba-20261011-152536(1).zip`, SHA256 `bf5afa3898fb378746614e271e25a05b2c20a5aaf81adf59c6c4bc3727fb28b2` identical to previously reported archive. 74 members, eight child conditions/results/stderr/stdout/resource CSVs; all 8 pass. 2026-10-11 ROCm b11560 15:25:38–16:19 JST, archived executable SHA `cb50e8092d18381d682c32e3218c5f343eb13108542e5bf8027db0765e22ad11`, runtime digest `063406ed83587bd6ce41250c284b97fb7a7610d78f0a801fedaabbd7a0254f7e`. Qwen3.8 Flash Next PLE16 plus draft for MTP ON; no grouped-union Vulkan feature on ROCm.

| Context | ROCm A1 MTP OFF PP | B1 MTP ON | B2 MTP ON | A2 MTP OFF | OFF pair spread |
| --- | ---: | ---: | ---: | ---: | ---: |
| 64k | 392.61 | 366.00 | 364.78 | 391.98 | 0.16% |
| 128k | 293.76 | 274.20 | 274.73 | 295.66 | 0.65% |

**Per-2048 checkpoint profile of ROCm 128k OFF A1/A2**: at 32768 70.48/68.12s, at 49152 115.96/113.43s, 65536 168.56/166.01s, 98304 294.34/291.92s, and 124928 417.94/415.23s. A1-A2 fixed time difference ~2.4–2.7s from 32k to the end, no widening difference after 32k. Segment times: 32–49k 45.48/45.31s, 49–65k 52.60/52.58s, 65–82k 59.36/59.49s, 82–98k 66.42/66.42s, 98–115k 73.65/73.59s. ROCm segment duration grows smoothly with length; **no 32k-specific transition, nor within-pair regime change**, unlike the separate cross-date Vulkan 32k union-threshold difference. Note this does *not* demonstrate absence of a transient ROCm fast state from other dates.

Resource monitor 128k OFF process GPU Local max 55.475GiB in both repeats and GPU Shared ~0.932GiB; MTP ON process GPU Local max60.895GiB. Sustained huge disk paging cannot be inferred from occasional startup spikes; no GPU clock, power, hotspot temperature or exact compute-engine busy measurement. ROCm 64k B2 has a ~144s extra initialization/load stall (total wall 376.43s vs B1 231.51s), but native PP is 364.78 vs366.00 tok/s, so this is **not** a prompt-compute acceleration or slowdown.

Oct10 ROCm `llama-bench` repeated ANLP PP b11543 64k394.030/128k296.274; Oct11 ROCm b11560 CLI OFF392.295/294.710 (−0.44%/−0.53%) provides a **qualitative prior-day control only**, since binaries, sampling and prompt templates differ. Oct11 Vulkan b11560 starts 17:11, around 52 minutes after ROCm finish; its OFF-MTP union-ON means 64k361.520/128k335.455 exceed Oct09 and Oct14 reference rates for the Vulkan path. There is **no evidence that October11 ROCm was in a simultaneous high-side regime**, although historical Qiita article `https://qiita.com/ariera/items/8a4e815db1d109070960` independently documents ROCm PP bursts in September. Do not infer a shared triggering condition, GPU clock/power origin or defective QSA solely from this archive. For further progress, collect per-kernel timings or actual GPU frequency/power/hotspot if another fast state is observed; existing CSVs do not record them.

## 2026-10-15 64k Vulkan 10/11 evening to 10/12 DENSE/NOOP follow-through

Cross-checked source reports `R5-MTP-VULKAN-64K128K-ABBA-2026-10-11.md`, `R5-MTP-TG-R2-R5-RECHECK-2026-10-11.md`, `R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md`, and `R5-MTP-NOOP-VULKAN-VALIDATION-2026-10-12.md`. All 64k r5 inputs use `nlp-survey-ch3-d7-b1.txt` SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, 61789 tokens, ctx65536, main PLE16 GGUF; MTP ON also Unsloth Q8_0 draft; native -n512 temp0 seed1234; Vulkan QSA union ON/minKV32768; batch2048/ubatch1024, f16 KV. **DENSE/NOOP are TG-only toggles and do NOT provide any r5 MTP-OFF measurements.**

| Time / archive | Binary | MTP | DENSE | NOOP | A1/B1/B2/A2 individual PP tok/s | Mean PP tok/s | TG tok/s mean |
| --- | --- | --- | --- | --- | --- | ---: | ---: |
| 10/11 17:11–17:28 (within `r5-mtp-vulkan-64k128k-abba-20261011-171132.zip`) | b11560 | OFF | absent | absent | A1 **360.57**, A2 **362.47** | **361.520** | 26.135 |
| same original b11560 64k MTP ON | b11560 | ON | absent | absent | B1 333.91, B2 334.08 | **333.995** | 28.885 |
| 10/11 18:28–19:28 batch `20261011-182831-abba.zip` (64k first) | **r2 b10813, unrelated architecture** | OFF | n/a | n/a | A1 294.39, A2 293.13 | **293.760** | 23.710 |
| same r2 64k | r2 b10813 | ON | n/a | n/a | B1 277.24, B2 276.89 | **277.065** | 26.315 |
| 10/12 morning, `vulkan-64k-abba.zip` (precise per-run start NOT documented) | b11566 | ON | OFF | absent | A1 335.29, A2 334.31 | **334.800** | 29.275 |
| same ZIP | b11566 | ON | ON | absent | B1 334.76, B2 334.64 | **334.700** | 31.270 |
| 10/12 batch start 13:20:38, `20261012-132038-024-qwen38-r5-mtp-noop-abba.zip` (64k+256k) | b11577 | ON | ON | OFF | A1 336.42, A2 335.31 | **335.865** | 31.385 |
| same ZIP | b11577 | ON | ON | ON | B1 335.84, B2 334.62 | **335.230** | 32.045 |

**Assessment:** 10/11 b11560 **MTP ON 64k PP333.995** and 10/12 b11566 DENSE OFF/ON **334.8/334.7** and 10/12 b11577 NOOP OFF/ON **335.865/335.230** form a stable **~334–336 tok/s** sequence over multiple sessions and two implementation tweaks. The controls prove the DENSE and NOOP feature toggles do not meaningfully affect PP in their corresponding b11566/b11577 sessions, but cannot establish whether b11560 **MTP OFF 361.52** persisted into October12: there is no comparable r5 MTP-OFF control in those files. By build/source design these MTP ON runs have ~5GiB more GPU Local allocation and do extra draft catch-up work. A high-rate state in MTP OFF might or might not be visible in MTP ON; cannot attribute a mechanism or label all Oct11 r5 PP paths as 'fast'. Cross-version r2 b10813 numbers are chronology ONLY, not a performance reference for r5. The contemporaneous r5 **128k MTP ON** PP also remains ~303–304 across Oct11 baseline b11560, Oct11 late DENSE b11566 and Oct12 NOOP b11577, despite October11 MTP OFF 128k PP335.455; no matched MTP-OFF arm on newer builds.

**Raw files to find**: `r5-mtp-vulkan-64k128k-abba-20261011-171132.zip` (10/11 17:11–17:59, 64k first); `20261011-182831-abba.zip` (r2 10/11 18:28–19:28; 64k first); `vulkan-64k-abba.zip` (DENSE b11566, **2026-10-12 morning**, documented full SHA256 `392b30b34e0c97526aabe8a2e617863b5a6b1cd958b1c7507f6b49329e6d6777`, **no recorded precise start**); `20261012-132038-024-qwen38-r5-mtp-noop-abba.zip` (NOOP b11577, combined 64k+256k, documented SHA256 `da14a5bb63605cdc31116f5352e8286e8df29a77303b1b708838432b27acc945`). Additional **128k** DENSE b11566 `r5-mtp-dense-128k-abba-20261011-204709.zip` (10/11 20:47), NOOP b11577 `20261012-123715-904-qwen38-r5-mtp-noop-abba.zip` (10/12 12:37) can be used to study same-depth contextual PP if needed. Precise DENSE 64k per-run time should be read from the raw archive, not invented.

**Measurement wrapper correction:** Prior investigation incorrectly asserted `Measure-LlamaCli.ps1` was unchanged since 10/09 on *all* relevant GitHub branches. Actual `investigation/r5-mtp-dense-indexer-20261011` and `investigation/r5-mtp-noop-20261012` have blob `f8cc2901eedc8018d53d5bdd713a4568aa4fe9bb`, commit `5fd2a4db553c` authored 2026-10-11 22:31 JST `fix(evox2): avoid garbled console replay of captured model stdout`, whereas stable r5 and current Stage-B experimental branch still carry blob `aded8591a070bac05129526c974277207ea43296`. This change only removes the post-run `[Console]::WriteLine($stdoutText)` replay, NOT model invocation, stored capture, timing, or parsing. A 10/13 local file modified timestamp is not proof of source patch creation on that date; compare local `git hash-object` to both known blobs if investigating. No runtime speed effect expected from end-of-run console replay after native process has terminated.

## 2026-10-15 recovered October 9/11/12 Vulkan CLI progression: 64k and 128k fast regimes

User recovered original native archives, re-read in full:
- `20261009-194011-878-qwen38-r5-qsa-union-batch(1).zip`: SHA256 `6c2d454c6db900b15d7e49beb88d63129f85933c6f33d039d032c873a71bc14d`, 12/12 OK, b11530 Vulkan, 2026-10-09 19:40–21:27. Contains 128k PLE16 QSA-OFF/ON A/B at 19:40/19:53, original 64k ON at 20:55/20:59, and matched **PLE16** 64k QSA ON B1/B2 **21:14:09 / 21:18:18**, OFF A1/A2 21:09/21:22. Original 64k ON PP342.21/341.66 must NOT substitute for PLE16 339.64/339.32.
- `r5-mtp-vulkan-64k128k-abba-20261011-171132(1).zip`: previously verified 10/11 b11560, 8/8 OK, MTP OFF/ON 64k 17:11–17:24 and 128k 17:28–17:51; SHA256 `d4d9f6b08afeed374aaafcdbf0221e66c099b7e1c389a3b29206442a62851e70`.
- `20261011-182831-abba(1).zip`: SHA256 `49406bb5e7b652469b0934d4826aea445243663a233ce5e4e28db7b9a7396b2d`, 8/8 OK, **older r2 b10813 Vulkan** MTP OFF/ON ABBA 64k 18:28–18:49 and 128k 18:49–19:28. Distinct binary, not an r5 longitudinal control. r2 OFF A1/A2 64k 294.39/293.13 (mean293.760), 128k251.87/251.93 (mean251.900). Relative to 2026-09-18 r2 b10811 OFF 64k273.34/128k220.57, it looks higher; **but** older runs differ in source binary, temp, generated length, logger/stats and cannot prove a continuous GPU fast state. Another Sep29 b10813 result is noted PP276.86 QSA ON MTP OFF, but older SHA/settings are not yet independently matched; request raw archive if this comparison becomes important.
- `vulkan-64k-abba(1).zip`: SHA256 `392b30b34e0c97526aabe8a2e617863b5a6b1cd958b1c7507f6b49329e6d6777`, 4/4 OK, b11566 Vulkan, **2026-10-12 08:56:52 /09:01:26 /09:05:59 /09:10:32 JST**. All MTP ON, QSA ON, DENSE OFF/ON/ON/OFF, NOOP absent. Mean PP DENSE OFF334.800 vs ON334.700; 64k 32–49k interval both ~52.6 s. Compiled source 5b6a21557, checkout 5fd2a4db55 (reporting-only later commit).

**Matched-source input identities:** PLE16 64k input `nlp-survey-ch3-d7-b1.txt`, SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, exactly 61789 tokens; 128k input `nlp-survey-ch3-d15-b1.txt`, SHA `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`, exactly 126253 tokens. Identical `-b2048 -ub1024 -t4 -tb4 -ngl999 -ncmoe0 -fa auto -ctk/v f16`, model and n512 except 10/9 temp0.2 vs 10/11/12 temp0. In 10/09 runtime QSA minKV env **unset** but binary defaults 32768; startup logs on 10/09, 10/11, 10/12 all confirm `ggml_vulkan: QSA grouped-union=on,min_kv=32768`, `qsa-union active (r5)` **same `path=1 Br=16 Bc=64 f32acc=1 groups=16 capacity=32768 scratch=73400576`**. This does NOT imply same per-kernel clocks/times.

| Session (all QSA ON) | Binary | 64k MTP state | 64k PP (tok/s) | 128k MTP state | 128k PP |
| --- | --- | --- | ---: | --- | ---: |
| 10/09 21:14–21:18 PLE16 | b11530 | OFF | **339.64/339.32** mean339.48 | OFF at 19:53 | **307.15** |
| 10/11 17:11–17:24 PLE16 | b11560 | OFF | **360.57/362.47** mean361.520 | OFF at 17:28/17:51 | **336.06/334.85** mean335.455 |
| same 10/11 block | b11560 | ON | 333.91/334.08 mean333.995 | ON | 304.13/303.80 mean303.965 |
| 10/12 08:56–09:10 PLE16 DENSE A/B | b11566 | ON | **335.29/334.76/334.64/334.31** mean334.75 | — | — |
| 10/12 13:20 onward PLE16 NOOP A/B, report only (raw ZIP not provided this turn) | b11577 | ON | NOOP OFF335.865 vs ON335.230 | ON at 12:37, PP~303–304 | — |

**Native CLI cumulative prefill time, seconds (averaged paired repeats where available):**

| Workload / session | 16,384 | 32,768 | 49,152 | 61,440 | 65,536 | 98,304 | 124,928 | 32k→49k step |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10/09 b11530 64k MTP OFF union ON | 32.465 | **80.410** | 134.580 | 177.165 | — | — | — | **54.170** |
| 10/11 b11560 64k MTP OFF union ON | 32.770 | **80.530** | **128.900** | **166.595** | — | — | — | **48.370** |
| 10/11 b11560 64k MTP ON union ON | 34.855 | 85.985 | **138.520** | 180.020 | — | — | — | 52.535 |
| 10/12 b11566 64k MTP ON DENSE ABBA | 34.565 | 85.520 | **138.123** | 179.618 | — | — | — | **52.603** |
| 10/09 b11530 128k MTP OFF union ON | 32.040 | 79.400 | 132.970 | — | 187.530 | 303.650 | 402.150 | 53.570 |
| 10/11 b11560 128k MTP OFF union ON | 31.960 | **79.335** | **127.165** | — | 177.060 | 281.135 | 368.475 | **47.830** |

**Interpretation update:** Cross-binary 10/09 PLE16 union ON 64k PP339.48 and 128k PP307.15 show ordinary/healthy QSA baseline. Oct11 same-input faster 64k +6.49% and 128k +9.22% as described; at 32k absolute timing matches Oct09 (both 64k ~80.5s, 128k ~79.4s), whereas 32→49k time is **~10.7% shorter** on 10/11 in BOTH contexts, continuing throughout longer KV. Runtime paths and source fixture match but binaries differ. **Important same-binary cross-date proof remains 10/11 b11560 128k PP335.455 vs 10/14 b11560 128k PP306.75/305.x, so the shift is not solely code changes.**

**MTP caveat and refinement:** 10/11 b11560 **MTP ON** was PP333.995 at 64k and 303.965 at 128k; 10/12 b11566 MTP ON 334.75, and 10/12 NOOP b11577 MTP ON ~335. Those are remarkably stable across >16h and feature toggles. **It is NOT safe to call this 'normal regime' solely because absolute 64k MTP ON ~334 resembles 10/09 *MTP OFF* ~339; enabling MTP incurs a within-binary −7.61% 64k PP penalty and −9.39% 128k PP penalty, so 10/11/12 MTP ON could still represent elevated underlying target PP.** The 10/11 64k MTP ON 32–49k step52.535 and 10/12 52.603 are identical to <0.2%, showing *the MTP-ON processing regime persisted through next morning*, though we lack MTP OFF measurements on 10/12 and cannot establish the session-wide uplift was retained. In 10/12 DENSE and NOOP only TG alters, not PP as isolated within each run.

**Resource summary 64k MTP OFF:** user resource csv 10/09 PLE16 b11530 union ON peak process GPU Local **80.614GiB**, 10/11 b11560 OFF **80.614GiB**, median 80.519GiB vs80.404GiB, no meaningful residency gap; system commit 10/09 ~91.3GiB vs 10/11 ~92.2GiB median. 10/11 b11560 MTP ON max85.572GiB, 10/12 b11566 MTP ON max85.572GiB. No explicit GPU core clock, memory clock, power or hotspot telemetry in these CSVs, therefore no causation established.

**Next controlled test:** when a fast PP period is suspected, same b11560 binary, 64k PLE16/MTP OFF and same b11560 128k MTP OFF, QSA ON and OFF separately as warranted; log GPU clocks/power/hotspot if instrumentation available. Seek matching same-r2 b10813 reference before using the 10/11 18:28 post-Vulkan experiment to attribute GPU state. 10/12 NOOP original `20261012-132038-024-qwen38-r5-mtp-noop-abba.zip` not included in this attachment set; values from archived report only. Do not assert every ON run was or was not in 'fast' state from absolute PP alone. No runtime code changes.

## 2026-10-15 00:47 post-reboot ON recheck and recovered 10/13–14 RGP 64k PP

**New user archive** `r5-128k-mtpoff-qsa-on-20261015-004716.zip`, SHA256 `450e07701633fcb147b0dff19eeec069a7f0ed43c8132b248887c26646eb42f5`. Child run `20261015-004718-589-cli-vulkan-b11560-ctx131072-84b9ed15488a` 00:47:18–00:55:13 JST, Status OK/exit0, **128k 126253 input, 512 output**, MTP OFF, QSA union ON/minKV32768; same old executable SHA `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`, runtime digest `be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2` and 128k input SHA `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` as 10/11. `ggml_vulkan` stderr shows QSA grouped-union ON, qsa-union active path=1 Br16 Bc64 f32acc1 minKV32768 scratch73400576. PP **307.01 tok/s**, time **411.23935s**; TG **23.87 tok/s**, time **21.40586s**. Slightly faster than Oct14 22:58 post-reboot PP306.75/411.589s but ~8.48% below 10/11 A1/A2 PP335.455 (same exact b11560 bundle).

| Oct11 b11560 128k MTP OFF A1/A2 mean versus Oct15 00:47 same b11560 | Cum PP time Oct11 | Cum PP time Oct15 | Difference Oct15-Oct11 |
| --- | ---: | ---: | ---: |
| 32768 | **79.335s** | **78.85s** | −0.485s |
| 49152 | **127.165s** | **132.69s** | +5.525s |
| 65536 | **177.06s** | **188.84s** | +11.78s |
| 81920 | ~228.755s | **246.13s** | +17.38s |
| 98304 | **281.135s** | **303.94s** | +22.805s |
| 124928 | **368.475s** | **402.35s** | +33.875s |

The 32768→49152 interval 10/11 ~47.830s vs Oct15 **53.84s**, Oct15 ~12.57% slower in time despite virtually identical 32k timing. The full 10/15 cumulative trajectory is effectively the 10/14 post-reboot ordinary session (10/14 checkpoint 32768 78.96s, 49152 131.64s, 65536 187.60s, 98304 304.30s, 124928 402.82s). Resource CSV has 236 samples, GPU Local median83.151GiB/max83.370GiB, matching 10/11 b11560; system RAM used median8.092GiB (Oct11 ~6.66GiB, Oct14 post-reboot ~8.0GiB), system commit median93.567GiB. No GPU clock/power/hotspot in logger; RAM difference is correlational and does not explain why difference first appears beyond union threshold.

**Recovered earlier 64k RGP-period observations, previously already documented in Git (NOT re-read from raw ZIP in this specific turn):** `R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md` reports 2026-10-13 21:21 b11569 trace-enabled OFF **361.10 PP**, ON **340.79** (second b11569 pair at 21:50 OFF **359.80**, ON **331.82**). `R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md` reports 2026-10-13 23:45 b11569 ON **336.90** PP and **2026-10-14 00:37 b11569 MTP OFF 364.18 PP**, exact OFF raw ZIP **`20261014-003724-476-cli-vulkan-b11569-ctx65536-e9bd074ab6f9.zip`**. The source report confirms same b11569 compiled runtime digest within its ON/OFF RGP pair, main PLE16, input SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, QSA union ON/minKV32768, LLAMA_MTP_PP_TRACE=detail enabled and RGP short capture. Thus the ~361–364 64k OFF PP also appears 10/13 night–10/14 *before later slow 128k Oct14 afternoon*, not just October11. Different b11569 binary and phase trace/RGP overhead mean this is strong chronological corroboration but not proof of the same performance root cause at 128k.

Further 2026-10-14 early marker-enabled **b11577** RGP 64k MTP ON native logs already recorded at 01:32 PP331.42, 01:44 PP325.94 (`R5-MTP-PP-RGP-MARKERS-IMPLEMENTATION-2026-10-14.md`), 02:01 PP304.78 (`R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md`). These are diagnostic binaries with `LLAMA_MTP_PP_TRACE=detail` and `GGML_VK_MTP_PP_RGP_MARKERS=1`, and capture configuration varies; **do not interpret their falling absolute PP as a proven GPU performance-state change without same-binary, instrument-equal control**. User remembers possible other 10/14 RGP-session 64k OFF~370/ON~330; archive names and true conditions must be checked before quoting as observations.

**Updated priority:** search user's RGP 10/14 64k raw `result.json/conditions.json/stderr.log` for MTP OFF ~370 and ON ~330 and correlate with b11569 OFF 00:37 and diagnostic flags. For decisive periodic fast/normal contrast, prefer *exact b11560 uninstrumented 64k/128k MTP-OFF QSA-ON* archived across days and GPU sensor telemetry; do not lump 64k and 128k values into one session hypothesis without matching code/workload. No inference source modified.

## 2026-10-15 recovered September 29 r2 four-way 64k control and Oct14 b11569 OFF 64k native ZIP

**Raw verified user archive:** `evox2-r2-unsloth-mtpoff-64k.zip` includes 21 CSV/log pairs **across TWO subdirectories** despite its misleading `mtpoff` filename: `evox2-r2-unsloth-mtpoff-64k/` plus `evox2-r2-unsloth-mtp-64k/`. The 9/29 four successful 64k PLE16 native runs are comparable *in workload* (61789 tokens, ctx65536, Vulkan f16, batch2048 ubatch1024, threads4, temp0.2, nmax1024, no fixed seed/ignoreEOS). `--spec-type none` vs `draft-mtp` clearly distinguishes MTP state; literal `ENV GGML_VK_QSA_UNION=1` or unset distinguishes union state. All 9/29 runs embedded **r2 b10813**; executable SHA not present in legacy CSV. Union-ON cases set **`GGML_VK_QSA_UNION_STATS=1`** and context checkpoints are **enabled max32**. 10/11 r2 b10813 64k native ABBA, by contrast, uses union ON **stats unset**, **`--ctx-checkpoints 0t`** (disabled), temp0, output512/ignore-eos/seed1234; direct speed comparisons are suggestive but **confounded**, not an ablation of high-speed state.

| 9/29 time JST | Native b10813 condition | PP tok/s | TG tok/s | Relevant individual log prefix |
| --- | --- | ---: | ---: | --- |
| 13:48 | **MTP OFF, QSA OFF (unset)** | **231.66** | 23.25 | `20260929-134805-285-...-nomtp-input-file.log` |
| 13:53 | **MTP ON, QSA OFF (unset)** | **217.01** | 26.78 | `20260929-135351-894-...-mtp-input-file.log` |
| 14:17 | **MTP OFF, QSA ON, STATS=1** | **276.86** | 23.41 | `20260929-141736-762-...-nomtp-input-file.log` |
| 14:27 | **MTP ON, QSA ON, STATS=1** | **259.28** | 25.89 | `20260929-142743-867-...-mtp-input-file.log` |
| 10/11 18:28–19:28 same embedded r2 b10813 but **stats unset/checkpoints disabled** | MTP OFF / QSA ON A1/A2 | **294.39 / 293.13 (mean293.76)** | 23.72/23.70 | `20261011-182831-abba.zip` |
| same Oct11 | MTP ON / QSA ON B1/B2 | **277.24 / 276.89 (mean277.065)** | 26.26/26.37 | `20261011-182831-abba.zip` |

9/29→10/11 OCT11 PP is +6.10% for r2 union-ON MTP OFF (276.86→293.76), +6.86% for union-ON MTP ON (259.28→277.065). **Do not call this demonstrated r2 high-speed uplift**: Sep29 was collecting QSA union stats at QSA-active KV while Oct11 was not, and checkpoints also changed. Native progression: 9/29 14:17 OFF cumulative 32768 94.44s, 49152 161.02s; Oct11 OFF A1 32768 94.31s, 49152 155.36s. 9/29 14:27 ON cumulative 32768 100.13s, 49152 172.30s; Oct11 ON B1 32768 100.13s, 49152 164.80s. The **identical ~32k times** and divergence in the 32–49k QSA-active interval could arise from STATS readback/logging overhead as well as dynamic performance state; separating requires flag-matched measurements and exact executable hash, which 9/29 does not provide. Key risk: `GGML_VK_QSA_UNION_STATS` instrumentation is *not* an inert on/off performance control.

**Raw independently verified Oct14 RGP-period MTP OFF 64k** ZIP `20261014-003724-476-cli-vulkan-b11569-ctx65536-e9bd074ab6f9(1).zip`: child start Oct14 00:37:24, end 00:41:12, status OK, exit0, 61789 tokens, n512, QSA ON/minKV32768, b11569 source `4b136c5bf`, executable SHA `8118a4334c52060a7c8ede371ac5f0ad33cdf94b1f017d3a28a84106044f1657`, `LLAMA_MTP_PP_TRACE=detail` present; **PP364.18 tok/s (169.66402s), TG26.10**. Native accumulated progress 16384 31.90s, 32768 79.19s, 49152 126.47s, 61440 165.31s, so Oct14 QSA-active 32768→49152 interval **47.28s**, even faster than Oct11 b11560 MTP OFF 64k **48.37s**. It is already documented in `R5-MTP-PP-VULKAN-SOURCE-RGP-PLAN-2026-10-13.md`; diagnostics and capture are differences from b11560. This is confirmed that high-side 64k PP persists/recurs near Oct14 00:37, but cannot ascribe 128k Oct14 daytime ordinary state to a single switch.

**Practical next after reboot:** no post-reboot 64k b11560 MTP ON/QSA ON nor post-reboot 64k b11560 MTP OFF/QSA ON have yet been recorded. Rebooted 128k b11560 MTP OFF/QSA ON ~306.75/307.01 and OFF/QSA OFF180.32 have been measured. If doing more new work, first a bounded **64k b11560 MTP OFF/QSA ON** matched cross-date vs Oct11 361.52, then optionally 64k MTP ON/QSA ON vs Oct11 333.995; do not mix r2 128k OFF with r2 64k ON because their native PP can look similar but compute/workloads are different. Otherwise prioritize analysis of archived RGP-period 64k raw data.

## 2026-10-15 raw b11587 64k RGP diagnostic comparison: identical effective condition, different pre-32k PP

Recovered and independently diffed **both** ZIPs:
- `20261014-094739-371-cli-vulkan-b11587-ctx65536-dee8a8f1085d(1).zip` SHA256 `53e20c2590433b6fcc3d6c4de3a57ba31fb779aa1e98bbc7e8743b40af3aeb62`, 2026-10-14 **09:47:39–09:51:44 JST**, PP **331.34 tok/s /186.48492s**, TG **27.76**, 512 output.
- `20261014-105604-956-cli-vulkan-b11587-ctx65536-dee8a8f1085d(1).zip` SHA256 `6be2d7463a81a29b68ac4f76247a3b5442bad9f61618d42732e38e7af19e1457`, **10:56:04–11:00:31 JST**, PP **303.23 tok/s /203.76986s**, TG **28.44**, 512 output; contemporaneous RGP screenshot/capture reported separately at ~10:59:35.

**Full structural `conditions.json` diff:** ONLY `RunId`, `StartedAt`, `SystemIdentity.CapturedAt` differ. Identical `ConditionId=dee8a8f1085d`, *literal full CLI Command/Arguments*, executable SHA `90f2540f0e2af5d15ad58364a58a582a079bc27afc3084c0326595819b569318`, runtime digest `e9356ae6ef7fb0853cdf0e09bb6df4cc26a04c9c3e0b2e7b5da5913b9dbe8619`, source commit `1453c9063` b11587, target PLE16+MTP Q8_0 file metadata, input SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` 61789 tokens/ctx65536, temperature0/seed1234/512 output, K/V f16 batch2048 ubatch1024, QSA union ON/minKV32768, `LLAMA_MTP_PP_TRACE=detail`, `GGML_VK_MTP_PP_RGP_MARKERS=1`, `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1`, MTP ON. Vulkan `qsa-union active` same path=1 Br16 Bc64, and **986 logged graph records / final ordinal1153078** same in both. Thus no recorded inference setting/source/model change explains the PP difference; the second was an *externally triggered RDP/RGP capture run*, which the `conditions.json` does not capture: external profiler attachment/capture settings are not verified equivalent.

| KV tokens processed | First cumulative PP s | Second cumulative PP s | Extra second s |
|---|---:|---:|---:|
| 4,096 |6.90|6.97|+0.07|
| 16,384|35.07|39.50|+4.43|
| 24,576|58.10|67.55|+9.45|
| **32,768**|**86.17**|**101.36**|**+15.19**|
| 49,152|139.34|156.44|+17.10|
| 61,440|181.44|198.74|+17.30|
| Native whole PP|186.48492|203.76986|**+17.28494**|

In contrast with Oct11 vs Oct14 **128k MTP OFF** b11560 case (32k checkpoint virtually equal, ~10% per-bin change **above** 32k), **this 64k MTP ON diagnostic pair is slower mainly before 32k**, ~**15.19/17.285 = 87.9%** of all PP-time gap at KV32k. Between 32k and 49k, interval53.17→55.08s (difference1.91s, +3.6%); at 49k→61k 42.10→42.30s (+0.2s). Therefore **do not assert this 64k delta is QSA union-speed state** merely because total PP331→303.

Native `mtp_pp_trace_v1` **prompt** 0–32768 target envelope 89.156→104.488s (+15.332s), its `target_us` 46.325→54.536s (+8.210s) and `spec_us` 42.830→49.952s (+7.123s). Draft `hidden_get_us` 39.046→46.478s (+7.432s), but this is *nested within* target spec/envelope, so **do not sum**; Draft `draft_us` 2.895→3.073s (+0.179s) in the first bin. 32769–65536 target envelope97.306→99.261s (+1.955s). These are CPU-side synchronized/wait-containing envelopes, NOT independently isolated GPU op timings. Saved generated stdout **identical except CLI PP/TG footer**, acceptance **295/430** both, 986 graph records identical, status OK/exit0 both.

Resource logging 2s: Target GPU Local median **85.361→85.363 GiB**, peak **85.572→85.810GiB**, near-identical steady local allocation. System Used RAM median9.961→10.571GiB; committed median97.55→97.995GiB, GPU clock, memory frequency, power and hotspot temperature **not recorded**; do not assign causation to small system-memory differences. Both are **debug/trace-marker/dispatch-counter-enabled** runs, not normal native unprofiled benchmarks; do NOT compare their absolute PP with regular b11560 ABBA as if instrumentation were equal. The RGP 10:56 externally triggered 512-dispatch capture may affect the second, but since most PP gap accrued **before 32k**, ahead of ~51k selected capture interval, the GPU capture event itself cannot straightforwardly explain the early accumulated difference; an armed capture/profiler state or independently varying runtime state remain possible, unproven. For reliable future test, log RDP connected/armed settings and GPU clocks/power, and compare same compiled *unprofiled* b11560 with no diagnostics.


## 2026-10-15 01:22 regular b11560 64k OFF/ON post-reboot matched check

**Raw file independently inspected:** `r5-64k-mtpoff-mtpon-qsaon-20261015-012248.zip`, SHA256 `001f6f72c64bec7de7cf03d4b2408a9e4fe72edca0a6a7fe6d9d68cff2570730`; two `llama-cli` child runs, both OK/exit0. Original 2026-10-11 ABBA comparator raw ZIP `r5-mtp-vulkan-64k128k-abba-20261011-171132(1).zip` re-read. 10/15 new OFF started 01:22:50, ended 01:26:49; ON 01:27:01–01:31:19 JST, ten second cooldown. Same archived **b11560 executable SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949` and runtime digest `be772e9a83324cfb77db3849f6b66eb4200b0209c8289a04b6ac7318431fe9a2`**. Identical full CLI `Command` and `ConditionId` within each MTP arm across dates: OFF `54673c8db655`, ON `192f9a42fc95`; same input SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, 61789 prompt tokens, 512 output, 65536 ctx, Vulkan QSA union ON/minKV32768, batch2048 ubatch1024 f16 KV, `--temp 0 --seed 1234 --ignore-eos`. Diagnostic/RGP flags **unset**, no DENSE/NOOP. Per-arm `conditions.json` difference to Oct11 limited to Git *checkout* commit/branch, timestamp, RDP indirect-display session identifier, Windows Remote Display driver/PowerShell patch 5.1.26100.9549→.9711. Actual compiled binary/runtime and AMD GPU driver identical. Causal effects of OS/RDP state **not established**.

| Arm/metric | Oct11 A1 | Oct11 A2 or B2 | Oct11 mean | Oct15 single | Oct15 vs mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| MTP OFF PP (tok/s) | 360.57 | 362.47 | **361.520** | **340.37** | **−5.85%** |
| MTP ON PP (tok/s) | 333.91 | 334.08 | **333.995** | **314.79** | **−5.75%** |
| MTP OFF TG (tok/s) | 26.01 | 26.26 | 26.135 | **25.93** | −0.78% |
| MTP ON TG (tok/s) | 28.60 | 29.17 | 28.885 | **28.56** | −1.13% |
| MTP effect ON vs OFF PP | | | **−7.61%** | **−7.52%** | difference just **0.09 percentage points** |

10/15 OFF native PP time **181.53415s**, TG **19.70368s**, output512. ON PP **196.28453s**, TG **17.89189s**, acceptance **295/430 = 68.605%**; same as original Oct11 ON B1/B2. Within each arm, full generated stdout is byte-identical after replacing only the speed footer. MTP ON-OFF PP penalty is **14.75038s on Oct15** versus **14.084s mean on Oct11**.

**Cumulative per-prompt checkpoint times (seconds, Oct11 mean of 2 vs Oct15 one):**

| Prompt tokens | Oct11 OFF | Oct15 OFF | Oct11 ON | Oct15 ON |
| ---: | ---: | ---: | ---: | ---: |
| 16384 | 32.77 | 32.31 | 34.86 | 34.83 |
| 32768 | **80.53** | **79.88** | **85.98** | **85.90** |
| 40960 | 104.40 | 106.57 | 111.82 | 114.43 |
| 49152 | **128.90** | **134.04** | **138.52** | **144.21** |
| 57344 | 153.80 | 162.23 | 165.94 | 175.01 |
| 61440 | 166.59 | 176.74 | 180.02 | 190.77 |

The first **16k→32k** segment time essentially matches across dates (OFF47.76→47.57s, ON51.13→51.07s). The **32k→49k** segment slows in 10/15 by **+11.97% OFF** (48.37→54.16s) and **+10.99% ON** (52.53→58.31s), followed by **49k→61k** slowdown **+13.28% OFF**, **+12.19% ON**. Both logs explicitly report QSA union active, path=1, Br16/Bc64 after minKV32768. Same stage boundary was previously confirmed in 128k b11560 OFF OCT11 vs Oct14/15. This is **strong evidence for reproducible date-dependent difference in the long-KV compute regime common to MTP OFF/ON**; not proof that QSA shader/kernel or memory layout is the sole cause. CPU/GPU throttling or scheduling could also scale more with long KV. Oct9 b11530 64k PLE16 MTP-OFF union-ON mean339.48, also matches Oct15 b11560 OFF340.37 (+0.26%) cross-build. Independent 10/13–14 64k b11569 OFF in high band ~361–364 (RGP diagnostics) recorded elsewhere.

**Resources/quality:** 10/15 steady process GPU Local OFF median80.519 GiB peak80.614; ON median85.361 peak85.572, both same peak as Oct11 and no sustained hard page input in resource CSV. Oct15 system committed median OFF90.855/ON97.045 GiB vs Oct11 OFF~92.1–92.2/ON~98.3, direction opposite to 10/15 lower PP (so system commit alone no explanation). No real GPU clock, hotspot, power telemetry. 10/15 generation output matches Oct11 for same MTP condition (after variable footer), supporting correct repeated workload.

**RGP caution:** Two b11587 10/14 64k diagnostic runs were command/environment identical but differed in *externally armed* dispatch-range Radeon Developer Panel capture mode. Their 331.34→303.23 PP gap accrued mainly **before 32k**, unlike b11560 *unprofiled* session gap that begins only **after32k**. Dispatch-range capture may impose preparation/tracking overhead before capture, but cause has NOT been directly isolated. The latest no-RGP b11560 run still shows date-dependent ~6% lower PP and a clean 32k boundary; therefore **do not use the diagnostic b11587 pair as decisive proof about b11560 performance-state mechanism**. To test RGP influence specifically, do controlled same-b11587 instrumented runs with/without Radeon Developer Panel capture armed (not merely trigger changed), and monitor clocks; only if necessary.

**Decision:** both 64k and 128k post-reboot regular controls now collected. Stop gratuitous repeats. Preserve high/normal two-regime evidence with 32k changepoint and separate RGP-induced early-Prefill variability; next test only after designing GPU clock/power/thermal sampling or targeted matched-kernel attribution. No inference source changes.

## 2026-10-15 Windows event-log audit: October 14 patch and two reboots between PP regimes

**Raw external evidence examined**: `evox2-windows-events-20261014-20261015-015925.zip`, SHA256 `3694a15fb489ccac50eafdbe83d5877b0b6f89c0f19dce1a7c5844acd1713ae4`, collected **2026-10-15 01:59:25 JST**, local window **2026-10-14 09:30–15:30 JST**. Inside: `windows-events.csv` **102 entries**, `windows-events-readable.txt`, `windows-update-history.csv` 2 records, `setupapi-device-installs.txt`, current driver list, collection info. `System`, `Setup`, WindowsUpdateClient, Kernel-PnP, DeviceSetupManager logs were readable; `Microsoft-Windows-UpdateOrchestrator/Operational` channel unavailable, so absence of events elsewhere is not an absolute absence. Evidence includes both Windows Update and two actual boot records:

| Timestamp JST Oct14 | Event source / ID | Exact logged observation |
| --- | --- | --- |
| 09:47:39–09:51:44 | b11587 64k MTP ON/QSA ON normal diagnostic run | PP **331.34 tok/s**; **no RGP capture**; recorded remote display in-box version **10.0.26100.9549**, PS **5.1.26100.9549**, Radeon GPU driver **32.0.31041.1004** |
| **09:51:52**, 09:52:04 | WindowsUpdateClient/Operational ID26 | 1 then 2 updates found; notably first log about **8 sec after** high-PP run ended; no inference update worker had been idle earlier |
| 09:53–10:06 | UpdateClient/Operational ID41, Setup Servicing IDs1/2/4 | Downloads; KB5127647 staging/installed **10:03:59**; KB5127694, KB5127648, KB5121794 staging/installing; reboot required logged **10:06:39** for KB5127648/KB5121794/Fod metadata |
| **10:56:04** | b11587 same condition, RDP dispatch-range RGP capture later in run | PP **303.23 tok/s**; STILL PRE-REBOOT and **remote display `.9549`, PowerShell `.9549`**; capture process is a confound, early 32k difference unusually large; cannot ascribe to post-reboot patch |
| **11:36:27** | System User32 ID1074 | Windows updater process `MoNotificationUx.exe` initiated planned OS restart |
| **11:37:29** | System Kernel-General ID12, Kernel-Boot ID20 | **First boot**; prior shutdown OK; EventLog ID6005 at 11:37:42 |
| **11:40:36** | System User32 ID1074 | `TrustedInstaller.exe` initiated planned second restart (upgrade reason) |
| **11:40:51** | System Kernel-General ID12, Kernel-Boot ID20 | **Second boot**; prior shutdown OK; EventLog ID6005 at 11:41:03 |
| **11:41:04–11:42:41** | Setup Servicing ID2; System WindowsUpdateClient ID19 | KB5127694, KB5127648, KB5121794 installed after reboot; Windows **2026-10 security patch KB5127648, build 26300.9711** and **2026-10 .NET patch KB5127694** success at 11:42:41 |
| 11:52:22 | System WindowsUpdateClient ID19 | Defender intelligence **KB2267602 / 1.461.17.0** installed |
| 13:05:08, 13:05:37 | Windows Update History | Defender intelligence **KB2267602 / 1.461.20.0** and platform **KB4052623 / 4.18.26090.9** update history records (`Operation=1, ResultCode=2, HResult=0`). History and event channels capture different stages. |
| **14:52:43** | Kernel-PnP ID400/410, DeviceSetupManager | New Microsoft Remote Display Adapter `rdpidd.inf` configured/started, **10.0.26100.9711**, RDP indirect display **SessionId_0002** |
| **15:09:47** | b11597 Stage A disabled, 64k MTP ON union ON | PP **313.66 tok/s**, in-box Remote Display `.9711`, PS `.9711`, Radeon GPU driver **32.0.31041.1004** |

**Raw identity cross-check** across archives: 2026-10-11 b11560 high MTP OFF/ON 64k, 2026-10-14 00:37 b11569 64k MTP OFF PP364.18, and 09:47 b11587 high ON PP331.34 have the **older** Microsoft remote-display driver version **10.0.26100.9549**, `SessionId_0001` and PowerShell **5.1.26100.9549**. At 15:09 b11597 PP313.66 and 2026-10-15 01:27 b11560 ON PP314.79, newer Microsoft remote-display **10.0.26100.9711**, `SessionId_0002` and PowerShell **5.1.26100.9711**. Exact Radeon 8060S `32.0.31041.1004` unchanged in these pre/post `conditions.json`, and no AMD/MediaTek display driver installation event within collected window. Current driver enumeration in ZIP is **not** a historical installation trace. `setupapi-device-installs.txt` only shows storage volume cleanup + enable-device-install around 11:40; PnP root virtual switch driver reconfiguration, RDP display enumerate events occur after OS restart and don't demonstrate updating the real AMD GPU driver.

**Interpretation / causal limits:** This is a **strong temporal alignment** of Windows security servicing, **two confirmed restarts** and in-box remote-display driver refresh **between** high (64k ON ~331–334) and subsequent baseline (64k ON ~314–315). The `conditions.json` OS build field is coarse (`26300`) and unchanged, but the *PowerShell and RDP driver component versions visibly changed* and Windows Setup/System events explicitly show `26300.9711`. One cannot distinguish OS patch effects, process restart/GPU cold-init, RDP connection state, dynamic clocks/power, GPU scheduler/prefill QSA or other background changes without a clean matched pre/post control. Crucially, 10:56 debug/RGP-run PP303.23 **occurred BEFORE reboots** with old component versions, so some measured drops predate update completion but this 10:56 run is **externally RGP-instrumented** and has anomalous pre-32k overhead rather than the typical post-32k drop. Thus it does *not* disprove the update hypothesis and does *not* prove the update was responsible.

**Recommended safe next**: preserve this as a significant observation, **do not uninstall patches or switch GPU drivers based on correlation**. If high PP recurs on build `.9711`, the simple theory 'OS patch necessarily prevents the fast regime' is falsified. Add actual GPU clock/power/hotspot and RDP active/armed state to normal b11560 64k/128k run metadata, and distinguish external RGP dispatch-range capture from native unprofiled ABBA. Driver-binary digests pre/post, if future proof needed, require independent snapshots; current Windows update ZIP contains only present driver versions.

## 2026-10-15 02:08 RDP disconnect 64k OFF/ON: adapter transitioned between run starts

User RDP-disconnect overnight experiment native ZIP independently parsed: `r5-64k-mtpoff-mtpon-qsaon-20261015-020854.zip`, SHA256 `e6b1cf793508a4925c70f46d6e92fac98f7450389c7d17ab92bc7c484cbed79e`, two runs 2026-10-15 02:08:56 OFF and 02:13:08 ON JST, both status OK/exit0. Original comparison 2026-10-15 01:22 OFF and 01:27 ON `r5-64k-mtpoff-mtpon-qsaon-20261015-012248.zip`, SHA256 `001f6f72c64bec7de7cf03d4b2408a9e4fe72edca0a6a7fe6d9d68cff2570730` re-read. **Same exact old unmodified b11560 exe SHA256 `611b1004e6596415f126695ab32adf11d9422686fb352bcaf152d19a14f7c949`, same runtime digest, per-arm ConditionId (OFF `54673c8db655`, ON `192f9a42fc95`), command, input hash, model, QSA ON/minKV32768, 61789 input tokens, n512, seed/temp0, f16 KV, no diagnostics.** All four ON native output texts identical after replacing CLI speed banner, draft acceptance295/430. Both OFF texts likewise identical. No program settings changed.

| b11560 64k QSA ON | Oct11 high mean (2 each) | Oct15 01:22–01:31 RDP-present | Oct15 02:08–02:17 disconnect experiment | Relative to 01:22 |
|---|---:|---:|---:|---:|
| MTP OFF native PP tok/s | **361.520** | 340.37 | **339.20** | −0.34% |
| MTP ON native PP tok/s | **333.995** | 314.79 | **322.08** | +2.32% |
| MTP OFF TG tok/s | 26.135 | 25.93 | 25.98 | +0.19% |
| MTP ON TG tok/s | 28.885 | 28.56 | 28.13 | −1.51% |
| ON vs OFF PP penalty rate | −7.61% | −7.52% | **−5.05%** | −2.47 points |

**Critical qualification on RDP controls:** `conditions.json SystemIdentity.VideoControllers` for **01:22 OFF** and **01:27 ON** each lists Microsoft Remote Display Adapter **10.0.26100.9711** plus Radeon **32.0.31041.1004**. In 02:08 **OFF** it **STILL lists both adapters**, while 02:13 **ON** lists **Radeon only** (Remote Display Adapter no longer enumerated). Thus the display device disappeared **between the two start snapshots**, consistent with user disconnecting RDP after starting the script. No session disconnect event timestamp was included, and adapter enumeration is a snapshot, not incontrovertible real-time 'RDP connected' state. **Do NOT label both 02:08 and 02:13 runs 'fully RDP OFF'.** The OFF measurement may have run through a connection-state transition; only the ON second run started with no remote display enumerated. The abrupt artifact difference is a better explanation for the unequal conditions, but is NOT proof RDP causes ON PP uplift.

**Native cumulative PP segment evidence, using stderr progress checkpoints:**

| KV processed | Oct15 01:27 ON (RDP adapter present) | Oct15 02:13 ON (adapter absent) | Connected minus absent (s) |
|---:|---:|---:|---:|
| 16,384 |34.83|34.85|−0.02|
| 32,768 |85.90|85.76|+0.14|
| 40,960 |114.43|114.43|0.00|
| **45,056** | **129.15** | **128.38** | **+0.77** |
| 49,152 |144.21|141.41|+2.80|
| **53,248** |**159.56**|**154.78**|**+4.78**|
| 57,344 |175.01|170.35|+4.66|
| 61,440 |190.77|186.31|+4.46|

Segment 40,960→53,248 on RDP-present ON **45.13s** vs adapter-absent ON **40.35s** (−10.6% time), with five consecutive 2048-row chunks ending **45,056–53,248** experiencing ~0.8–1.1 sec each acceleration; up to 40,960 and after 55,296, per-2048 batch time is approximately unchanged. This **localized temporary PP acceleration** produces most of whole-run gain4.4405s native PP (196.28453→191.84403s), not a sustained fast-state return across all KV>32k. Same-date OFF both 01:22 and 02:08 show essentially unchanged KV profile (PP181.534→182.159s, OFF 32k→49k 54.16→54.54s); 02:08 OFF still enumerated the RDP adapter at job start.

**Resource correlation, not root cause:** the 02:13 ON during prompt at elapsed181–191s records whole-system disk reads spikes **~59–384MiB/s** and whole-system page reads up to **3789/s**, absent in the comparator 01:27 ON in the corresponding time window. Around this time 02:13 ON processes approximately 45–53k prompt tokens depending on elapsed startup; disk reads can be from unrelated processes, not proven process-private. Faster PP occurs *despite*, not necessarily because of, elevated counters. Local GPU memory peak roughly **85.572GiB** both ON conditions; median process GPU Local **85.361GiB**, consistent process GPU residency at this coarse sample level. AMD driver unchanged. No GPU clock/temperature/power telemetry in either ZIP.

**Inference and next control:** disconnecting RDP did **NOT** bring both MTP conditions back to Oct11 high range; OFF ~339 vs high361.5, ON ~322 vs high334. The strict claim 'RDP disconnect improves MTP ON by +2.32%' is premature: one run per arm and the adapter only absent in the *second* snapshot, with a ~10k-token isolated speed burst and varying system I/O. For repeatable A/B first ensure Remote Display Adapter absence in BOTH 64k run-start conditions: e.g. issue `Start-Sleep -Seconds 120` **before** the same OFF→ON script, then disconnect promptly; check new snapshots. For a direct ON RDP connected/disconnected A/B do replicated short/single-arm runs and avoid connecting RDP during capture. Do NOT conclude that RDP/OS patch, QSA state or power-management root cause was established. No source changes.


## Stage B Vulkan 64k P-MODE + ADLX controlled ABBA recheck — 2026-10-15

**Status: 64K FUNCTIONAL + PP PERFORMANCE REPRODUCED WITH AUTHORITATIVE PERFORMANCE P-MODE IN ALL FOUR RUNS.** Raw user archive: `20261015-193942-281-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `b316923f18a8849cd591e513d6b54c72df18d368525b2badd7644a8b1cd0bfdd`. Matrix: `stage1-kv-only-64k`, started 19:39:42 and completed 19:57:09 JST, **4/4 OK, exit 0**. This rerun addresses the missing *direct* P-MODE metadata in the October 14 experiment; it does **not** establish the October 14 mode retrospectively.

### Test identity and controls

- Exact retained **Vulkan b11618 / Clang 20.1.8** executable: SHA256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2`; compiled source `5ea504315450aeb3ef9e0160bfeea2c0da965960`; runtime artifacts `Verified` with bundle digest `c719ec9e0801852fcc29bc5aebe3ebcc6c1e7811bdfd42acd011071f6c81f30a`. All four have matching executable and runtime identities; **no rebuild**.
- Git working tree at measurement: branch `investigation/r5-mtp-pp-kv-crop-stage1-20261014`, HEAD `4b08acd12d47324286d556e5fafaac5850a0441f`, `Dirty=true` because the r5-mainline ADLX/P-MODE-enabled benchmark wrappers and supporting tools were copied into the worktree. The running Stage-B binary was independently verified and is unaffected by this reporting-tool difference.
- Fixed PLE16 main GGUF + self-contained Unsloth Q8_0 Draft GGUF, 61,789 prompt tokens, input SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, 512 generated tokens; ctx65536, f16 K/V, batch2048, ubatch1024, threads4, GPU layers999, CPU MoE0, FA auto, temp0, seed1234, QSA union ON/minKV32768, UMA label 96GB, MTP ON in **both** arms. Model/Draft GGUF paths, sizes and mtimes match previous reports; full GGUF SHA256 values are **not** present in the archive.
- Independent processes in ABBA order; `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=0` (A) vs `=1` (B). Graph/marker diagnostics OFF. Shared 2-second ADLX telemetry and resource monitoring enabled.

| Run | Stage B | PP tok/s | PP s | TG tok/s | TG s | Native PP+TG s | ADLX samples | High-load GPU power W | P-MODE start/finish |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| A1 | OFF | 334.18 | 184.898 | 29.51 | 17.316 | 202.213 | 122 | 115.967 | Performance / Performance |
| B1 | ON | **346.11** | **178.526** | 29.80 | 17.148 | 195.675 | 125 | 116.282 | Performance / Performance |
| B2 | ON | **344.81** | **179.198** | 29.86 | 17.113 | 196.311 | 118 | 116.057 | Performance / Performance |
| A2 | OFF | 332.81 | 185.660 | 29.45 | 17.354 | 203.014 | 122 | 116.989 | Performance / Performance |
| **A mean** | OFF | **333.495** | **185.279** | **29.480** | **17.335** | **202.614** | — | — | same |
| **B mean** | ON | **345.460** | **178.862** | **29.830** | **17.131** | **195.993** | — | — | same |

**Effect within the October 15 ABBA:** B vs A PP **+11.965 tok/s / +3.5878% throughput**; prompt duration **-6.41666 seconds / -3.4632%**; TG **+0.350 tok/s / +1.1873%**, TG duration **-0.20405s / -1.1771%**; native prompt+generation **-6.62071s / -3.2677%**. A range 332.81–334.18, B range 344.81–346.11 tok/s: no overlap. Two runs per arm support a repeatable practical PP difference in this session, not a formal confidence interval. TG is weaker because its change is small.

**Authoritative P-MODE gate passed:** All eight start/finish WMI method-2 checks succeeded; each reports `Mode=Performance`, `RawValue=1`, `Source=IP3-WMI-method2`, `Transport=ScheduledTask`. No mode change and **zero** P-MODE warnings per run. ADLX completed with exit 0, 118–125 samples/run, 85–91 high-usage (>=95%) power samples/run; mean high-load GPU power 115.967–116.989 W, class `Performance-like`, consistency true. High-load GPU clocks average about 2844.5–2859.8 MHz; similar across arms. These power bands are *provisional secondary checks*, not a replacement for the direct WMI read. ADLX samples report `remote_session=1` for all four runs; no RDP connection-state transition is inferred. GPU temperature rises across the sequence (~73.7 to ~79.0 C high-load mean), so retain workload/run order when assessing environmental drift.

**Functional gate:** All runs generated 512 tokens; Draft accepted/generated **295/430**, acceptance 0.68605, graphs reused 210. All four `stdout.log` payloads are **byte-identical after stripping the trailing CLI performance footer** (compare raw bytes because previous CLI output contains invalid UTF-8). No crash/backend error; **this is output-level correctness, not bytewise Draft K/V parity**. Actual GPU FA-dispatch absence still requires targeted GPU profiling.

### Compare against October 14 (P-MODE unknown)

| Date | A PP mean | B PP mean | B/A PP throughput gain |
| --- | ---: | ---: | ---: |
| Oct 14 b11618, direct P-MODE not logged | 314.135 | 325.535 | **+3.629%** |
| **Oct 15 b11618, direct Performance confirmed** | **333.495** | **345.460** | **+3.588%** |

October 15 absolute PP rises vs October 14 by **+6.16% A**, **+6.12% B**, but the relative Stage-B gain is nearly identical. This supports a genuine same-binary Stage-B speedup across two sessions rather than a *within-ABBA* P-MODE difference. **Do not back-label October 14 Balanced mode**: it had no authoritative mode metadata. Source-level explanation from active-graph diagnostics remains Stage-B pruning of Draft Q/FA/FFN while retaining K/V writes; causal GPU-dispatch attribution and numerical cache parity are open.

**Next measurement:** Perform a new **128k ABBA** using this retained b11618 `R5MtpKvOnlyVulkan` binary and the same ADLX/P-MODE-enabled wrappers, with a job isolating only crop=0/1 across A1/B1/B2/A2. Demand Performance on all eight mode probes and comparable ADLX high-load power. October 14 128k A/B showed PP 278.06→296.63 tok/s (+6.68%) under unknown P-MODE, and is a historical reference only. Consider a new same-day b11618 128k MTP-OFF control after the Stage-B ABBA; do not attribute historical cross-date baseline drift to source.


## 2026-10-15 128k Performance-mode ABBA and same-binary MTP-OFF control

**Status: 128K STAGE-B PP IMPROVEMENT REPRODUCED; MTP-ON STILL ~2.95% BELOW THE SAME-DAY MTP-OFF PP BASELINE.** Four-run ABBA ZIP `20261015-201511-238-qwen38-r5-mtp-kv-crop-stage1.zip`, SHA256 `64f65f9abde25647e5d3c4de172de68599e71ab6a288d2a3c38b78065f69706b`. MTP-OFF control ZIP `20261015-205606-737-cli-vulkan-b11618-ctx131072-199dda7e51ac.zip`, SHA256 `2066e46850f92362a74a181466289efe44ab64b32bab8cbb356eb64599fcb11e`. ABBA 20:15–20:47 JST; MTP-OFF 20:56–21:03 JST. The control is a single run after the ABBA, NOT a fifth counterbalanced ABBA arm.

### Provenance and comparability

- All five runs: **OK / ExitCode=0**, Vulkan `b11618-5ea504315`, Clang20.1.8, identical `llama-cli.exe` SHA256 `7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2`, runtime digest `c719ec9e0801852fcc29bc5aebe3ebcc6c1e7811bdfd42acd011071f6c81f30a` with artifact status `Verified`; no binary rebuild.
- PLE16 main GGUF path/size/mtime identical, input `nlp-survey-ch3-d15-b1.txt` identical (SHA256 `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`), **126,253 input tokens**, context **131072**, generated **512** tokens. Same QSA union ON/minKV32768, f16 K/V, batch2048/ubatch1024, threads4, GPU layers999, CPU MoE0, FA auto, temp0/top-p0.8/seed1234, Jinja/single-turn, 96GB UMA label. All five under the same remote RDP display session.
- In ABBA, MTP ON in all four; A `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=0`, B `=1`. Draft Q8_0 model path/size/mtime matches across the four. MTP-OFF control actually launches `--spec-type none` with **no** `-md` Draft flag and **no** Draft model, and the Stage-B environment variable is unset. Differences in the effective conditions are precisely the intended MTP/Draft/crop choices.
- All **ten authoritative P-MODE reads** (start+finish across five runs) succeeded with `Performance`, raw 1, IP3 WMI method2 / elevated scheduled-task transport; no mode changes, warning count zero. ADLX completed with exit0 and populated GPU traces in every run. Reported power classification `Performance-like` and consistent for every run. P-MODE confirms start and end points; it does not sample mode continuously during a run.

| Run | MTP | Stage-B | PP tok/s | PP seconds | TG tok/s | TG seconds | PP+TG seconds | ADLX samples | High-load GPU power W |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | ON | OFF | 301.23 | 419.128 | 23.54 | 21.704 | 440.832 | 241 | 114.164 |
| B1 | ON | ON | 321.27 | 392.982 | 24.00 | 21.291 | 414.273 | 228 | 113.933 |
| B2 | ON | ON | 320.99 | 393.322 | 23.95 | 21.336 | 414.658 | 228 | 114.062 |
| A2 | ON | OFF | 300.63 | 419.961 | 23.47 | 21.769 | 441.730 | 243 | 114.938 |
| **A mean** | ON | OFF | **300.93** | **419.545** | **23.505** | **21.737** | **441.281** | — | — |
| **B mean** | ON | ON | **321.13** | **393.152** | **23.975** | **21.313** | **414.465** | — | — |
| **MTP-OFF control** | **OFF** | n/a | **330.90** | **381.544** | **23.92** | **21.366** | **402.910** | **220** | **112.040** |

**Within-ABBA Stage-B effect:** PP **+20.20 tok/s / +6.713% throughput**, prompt duration **−26.393 seconds / −6.29%**, TG **+0.470 tok/s / +2.00%** (small, less robust), combined native PP+TG **−26.816 seconds / −6.08%**. B1/B2 tightly replicate each other, and A1/A2 also match closely. All four MTP-ON outputs are byte-identical except the trailing native timing footer; **Draft accepted/generated 295/429 and 512 generated** in every ON run, graphs reused 210. This is output-equivalence, **not a direct Draft KV numerical-parity check**.

**Same-binary, same-day MTP-OFF reference:** MTP OFF PP **330.90 tok/s**, TG **23.92 tok/s**; 507 graphs reused, 512 generated. MTP OFF output is **not** byte-identical to MTP ON output (different MTP state), and output parity is *not* a condition for performance comparison.

- Stage-B ON PP throughput relative to MTP OFF: **(321.13 / 330.90 − 1) = −2.953%** (−9.77 tok/s). Native PP time is **+11.608s** vs MTP OFF; PP+TG **+11.555s**. TG difference +0.055 tok/s is negligible at this replication level.
- MTP ON without Stage-B costs **419.545 − 381.544 = 38.001s** extra prompt time. Stage-B recovers **26.393s**, or **69.45% of this measured PP-time overhead**, leaving **11.608s = 30.55%** of the baseline prompt-time penalty. These fractions depend on this workload, KV length, MTP settings and implementation; do not generalize to other models or contexts.
- Oct 14 128k b11618 MTP-OFF PP **305.98** and Stage-B A/B **278.06/296.63** (mode unverified); today MTP-OFF **330.90 (+8.14%)**, Stage-B OFF **300.93 (+8.22%)**, ON **321.13 (+8.26%)**. The Stage-B gain **+6.68% then +6.71%** is reproducible across dates. Absolute throughput rose for **all** conditions, not only Stage-B: do not assert Oct 14 was in Balanced mode or that a source change caused the drift.

### Sensor and KV-depth observations

ADLX high-load (GPU usage >=95%) averages: A1/B1/B2/A2 GPU core clock **2854/2849/2850/2847 MHz** and power **114.16/113.93/114.06/114.94 W**; MTP OFF clock **2871 MHz** / power **112.04 W**. All are `Performance-like` by the supplementary classification. OFF draws less GPU power despite higher PP; different MTP workload and lower resident GPU memory likely affect power, so do **not** infer clock or power alone caused the performance delta. High-load GPU temperature means across A1/B1/B2/A2 **76.34/78.57/78.77/79.51 C**, OFF **76.87 C**. RDP remote-session=1 throughout.

Cumulative native prompt checkpoints reveal ON-B residual cost distributed across the KV range, not a singular late spike. Stage-B B1/B2 mean versus MTP OFF in 2k checkpoint-derived intervals:

| Prompt-token interval | MTP OFF seconds | Stage-B ON seconds | Residual ON-minus-OFF |
| --- | ---: | ---: | ---: |
| 4k–8k | 7.92 | 8.30 | +0.39 |
| 8k–16k | 18.00 | 18.95 | +0.95 |
| 16k–32k | 47.00 | 48.82 | +1.82 |
| 32k–49k | 48.72 | 50.13 | +1.41 |
| 49k–65k | 50.87 | 52.07 | +1.20 |
| 65k–82k | 52.43 | 54.03 | +1.59 |
| 82k–98k | 53.40 | 54.84 | +1.44 |
| 98k–115k | 54.52 | 56.00 | +1.48 |
| 115k–125k | 34.77 | 35.44 | +0.66 |

These intervals are sampled progress timing, not per-GPU-kernel profiling. Remaining MTP overhead may include Draft catch-up computation beyond Q/FA, target-side/speculative machinery, extra graph/execution/synchronization work or extra resources; **individual causes are not isolated yet**.

**Inference and next priority:** Stage-B 64k (+3.59%) and 128k (+6.71%) relative PP gains now have cross-session replication with direct P-MODE verification; 128k MTP-ON Stage-B still trails MTP OFF by ~3% in this **single** MTP-OFF reference. A repeat OFF/ON/ON/OFF matched MTP-state control would strengthen the absolute gap estimate if needed, but the highest-value engineering follow-up is focused profiling of the **remaining ~11.6s** PP overhead, plus Draft K/V numerical parity and a GPU-dispatch confirmation that Stage-B truly skips the intended Draft Q/FA/FFN. Avoid prematurely merging or claiming a fully eliminated MTP penalty.
