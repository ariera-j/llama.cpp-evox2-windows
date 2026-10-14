# r5 MTP-ON PP Stage A: optional Draft catch-up graph root crop (2026-10-14)

**Status: BUILT / VULKAN SHORT SMOKE PASS / 64K + KV-PARITY UNVALIDATED / NO PERFORMANCE CLAIM.**
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

## Known concerns / blockers

- A removed hidden/logits output is expected and intentional **only for zero-output catch-up**; ordinary outputs must remain present. The complete graph is preserved by default or on any nonzero-output batch.
- `llm_graph_input_mem_hybrid` historically sets the FA mask unconditionally. Stage A allows the mask buffer to be pruned and the setter now tests allocation; test for other unallocated input setters before declaring backend correctness.
- If this graph is fully allocated with K/V roots but unexpectedly still dispatches FA, revise after reading the active graph nodes rather than assuming GGML dead-code pruning succeeded.
- No synthetic CPU-only cache-state test has been implemented. Static source tests are *not* sufficient for merged or validated status.
- No upstream/r5 stable inference code, DENSE or NOOP branch, GGUF, prebuilt binary, build key from another experiment or release artifact has been changed.
