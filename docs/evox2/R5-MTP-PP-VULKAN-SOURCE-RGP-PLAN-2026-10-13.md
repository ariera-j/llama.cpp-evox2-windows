# r5 MTP ON PP Vulkan source audit and RGP capture gate — 2026-10-13

**Status:** pinned-source review COMPLETE; **no runtime/source optimization, no RGP measurement yet**. The next evidence gate is a small, controlled Vulkan GPU capture. DENSE-001 / NOOP-001 are **TG-only and not in this source**.

## Source and run identity

- Reviewed **compiled code ancestor** `f8d24494fcacee01f8c9858595c3e778a1698d11` (r5 b11560 compatibility-only). Opt-in 64k/128k phase tracing was built from `4b136c5bf48e14dc162f96b7457379684287cd20` / b11569 on separate `investigation/r5-mtp-pp-trace-20261013`; later branch head `2578e4672b6ecc2e9a2bd3674367558781e90427` only added 128k benchmark PSD1. Runtime identity is the embedded compiled commit, **not** the current Git checkout HEAD.
- Prior 128k traced Vulkan prompt: **OFF 382.96571 s**, **ON 420.90814 s**, +37.94243 s, 126,253 tokens, 62 target prompt batches. ON server target wrapper **220.60349 s**, target hidden getter (sync-inclusive) **178.29562 s**, draft process call CPU wall **20.02331 s**, verify row-copy/getter **1.91442 s**. The **~15.975s** difference between (ON target+getter) and OFF target CPU-wall envelopes **is not directly measured target kernel time**. [Full 128k report](R5-MTP-PP-TRACE-VULKAN-128K-2026-10-13.md). [64k and repeat](R5-MTP-PP-TRACE-VULKAN-64K-2026-10-13.md).

## Source-confirmed mechanisms and exact paths

### A. Target final-layer crop behavior changes when NextN is requested — HIGH priority

- `common/speculative.cpp` **L1477–1478**: MTP initializes `llama_set_embeddings_nextn(ctx_tgt, true, /*masked*/ false)`; draft uses masked=true.
- `src/llama-graph.h` **L1061–1067**: `crop_before_nextn()` permits an early row crop when `!embeddings_nextn || embeddings_nextn_masked`. **MTP ON unmasked disables early crop**. `crop_after_nextn()` enables a row crop *after* capturing all NextN hidden rows.
- `src/models/qwen4exp.cpp` **L487–535**: at last trunk layer **after attention** and **before final HC combine + HC norm/mix + MoE/FFN**, OFF can take only requested output rows. ON continues through the last block's HC combination and MoE/FFN for every prompt row before `res->t_h_nextn` exists. **The final output head still has an after-NextN row crop**, so the simple theory “MTP ON computes full vocabulary logits for every prompt token” is false here.
- Interpretation: this is a genuine ON/OFF **graph-compute difference** that might contribute to the CPU-wall target+getter envelope gap (~1.48s at first 64k, ~15.975s at 128k). But the gap itself also shifts GPU wait and includes copies and other work; **do not attribute all 16 seconds to the final MoE without RGP**. Removing early target computation without producing matching hidden vectors would violate MTP behavior.

### B. Draft catches up across the full prompt and uses DENSE attention — HIGH priority

- `common/speculative.cpp` **L1519–1645**: each non-shared prompt batch retrieves target NextN hidden, constructs shifted embeddings/tokens for all rows, then calls `llama_process(ctx_dft, LLAMA_PROCESS_TYPE_DECODE, batch.get())` once per MTP head (Qwen4Exp has 1), then obtains verification hidden and saves the last row for the next batch. It is **not just an extra two-token decoding** during PP. 2,048-token caller batches may be split into 1,024-token ubatches by the context.
- `src/models/qwen4exp.cpp` **L584–618, L954–1036**: Unsloth Q8_0 MTP layer compression ratio **0** means no k-pool input and `qsa=false`, which goes to `build_attn()`, not `build_attn_qsa()`. This is a trained **dense** block, not a model that can safely be switched to QSA by editing GGUF metadata.
- `src/llama-graph.cpp` **L2767–2799**: when `cparams.flash_attn` true, this dense branch generates **`GGML_OP_FLASH_ATTN_EXT`**. `ggml/src/ggml-vulkan/ggml-vulkan.cpp` **L13024–13026** dispatches that op to `ggml_vk_flash_attn`; **L1342–1388** chooses scalar, coopmat1 or coopmat2 based on device capability and shape. **Dense ≠ Flash Attention disabled.** The exact shader and measured GPU operator time on Radeon8060S remain unverified.
- Vulkan **QSA union** requires a non-null selected-rows/top tensor at `ggml-vulkan.cpp` **L8203–8237**; plain draft ratio-zero `build_attn()` has no QSA `top`. So the target's `qsa-union active` log and `GGML_VK_QSA_UNION=1` do **not** mean this draft uses QSA union. The draft dense-FA path is a distinct profiling target.
- `graph_mtp` `qwen4exp.cpp` **L602–637**: it runs HC mix + dense attention + HC FFN for all draft prompt rows; only **after** those does `flat_out` apply output ids for a logits/head subset. Draft **KV-only prefill** remains a separate correctness-gated design, not a trivial output-row crop or authorized performance fix.
- Depth evidence: 64k draft `llama_process` CPU-call wall ~6.76s; 128k ~20.02s, nearly linear **per fixed 2,048-row batch** with accumulated KV, but cumulative times mix more batches and text/shape differences. These wall numbers are **not FA GPU timings**.

### C. All-row target NextN host readback and draft reinjection — MEDIUM/HIGH priority, GPU wait not copy

- `src/llama-context.cpp` **L2143–2166**: with unmasked NextN, output buffer is sized by entire `n_batch` (not just output-token count). It first attempts an output-device **host buffer type** `L2212–2224`, not necessarily a normal pageable CPU allocation.
- `src/llama-context.cpp` **L2033–2048**: one `ggml_backend_tensor_get_async(..., n_rows * n_embd_out * sizeof(float))` per underlying target ubatch. The model's 10,240-element f32 NextN output is **40 KiB per token**, ~80 MiB across the caller's 2048 tokens, ~4.82 GiB for 126,253 prompt tokens, in a single readback direction, plus reupload of draft input. It is 80 MiB **per 2048-token caller batch**, not necessarily one Vulkan DMA operation due to 1024 microbatch splits.
- `src/llama-context.cpp` **L4164–4173**: both `llama_get_embeddings_nextn()` and `_ith()` call **`ctx->synchronize()`** before returning pointers. Thus the phase tracer's **178.296s** getter at 128k can include **prior queued target inference GPU work** (not 178s pure PCIe or RAM copying).
- `ggml/src/ggml-vulkan/ggml-vulkan-buffers.cpp` **L541–615**: `ggml_vk_buffer_read_2d_async` uses a pinned registered destination if `ggml_vk_host_get` finds it; otherwise returns false when asynchronous staging is unavailable. `ggml/src/ggml-vulkan/ggml-vulkan.cpp` **L13580–13633** responds with **synchronous staging + deferred CPU memcpy + `ggml_vk_synchronize`**. This is a **real possible alternative execution path**, not proof that the user's buffer used it. The attempt to choose Vulkan host buffer in `output_reserve()` makes a pinned destination plausible; verify actual path before proposing expensive handoff redesign.
- The phase trace **does not flag whether readback used direct pinned/async or synchronous fallback**. This is a good tiny opt-in counter if GPU capture leaves the copy question open. On unified-memory hardware it remains a real scheduling/data-movement path; do not assume physically separate PCIe.

## Vulkan backend profiling warning

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp` **L5428–5439** uses **presence** of `GGML_VK_PERF_LOGGER` to enable logger: even string `0` is not OFF. **Unset the variable** for comparable normal PP traces.
- `ggml-vulkan.cpp` **L14984–15012** explicitly **submits, waits for GPU fence, reads timestamp queries** on that logger path, changing normal async overlap. It may help an isolated kernel probe but **must not be used to claim unprofiled OFF/ON PP difference**; it will distort the existing server phase boundaries. Do not enable together with RGP as a control.
- VK FA kernel tuning and dispatch: `ggml-vulkan.cpp` **L8371–8895**; scalar/cooperative matrix selection `L1342–1388`; possible split-K FA/reduction work. `GGML_VK_FA_SPARSE_DISABLE` and global `GGML_VK_QSA_UNION` changes are **not** clean single-hypothesis controls for these MTP ON/OFF runs; preserve environment.

## Recommended RGP acquisition — one cheap gate before another long suite

AMD RGP officially supports Windows 11 Vulkan **pure-compute** traces, using Radeon Developer Panel/Service or the headless capture CLI; tooling: [RGP documentation](https://gpuopen.com/manuals/rgp_manual/) and [RDP CLI dispatch capture](https://gpuopen.com/manuals/rdp_manual/radeon_developer_panel_cli/). On Evo-X2 first confirm that an RGP capture is actually accepted for Radeon8060S/installed driver; version/driver behavior may vary.

1. **First only one 64k MTP ON capture** using the existing, already-built **b11569** PP trace Vulkan binary. Use **original 61,789-token input**, target Unsloth PLE16 + Q8_0 sidecar, `-c 65536 -b 2048 -ub 1024 -n 512`, QSA union=1 minKV32768, trace=detail. Do **not** change GGUF, Vulkan driver, temperature, cache, FA toggle, DENSE/NOOP switches or benchmark source. Keep `GGML_VK_PERF_LOGGER` and `GGML_VK_PERF_LOGGER_CONCURRENT` **unset**. Target a short capture **during steady prompt prefill at ~KV40k–55k**, not model load or TG. Prefer a bounded dispatch selection rather than whole-run capture; avoid runaway .rgp size.
2. In RGP examine **(a)** FA dispatch shader/pipeline variant (scalar vs coopmat, split-K), **(b)** approximate GPU time for dense draft FA vs target final HC/MoE/FFN operations and memory copy/barriers, **(c)** command buffer/queue bubbles and overlapping work. Note that **RGP alone does not label llama.cpp target versus draft contexts definitively**: shader/pipeline and chronological operation groups must be reconciled against the PP phase trace; add markers in a follow-up only if needed. **GPU capture alone cannot measure CPU memcpy or identify an output buffer pin-registration failure.**
3. If the first RGP trace is readable and shows relevant prefill compute, **second 64k MTP OFF capture**, at approximately the same KV depth, can isolate target last-layer graph difference. Consider a late 128k MTP ON RGP slice only if draft attention complexity/pipeline remains ambiguous; don't demand a full 128k RGP recording now.
4. Save **native .rgp** (if reasonable file size) or screenshots from RGP **Overview/System activity**, **Events/top kernels**, relevant FA/HC/MoE pipelines with timings, plus run start/capture time and any trace capture errors. The ordinary benchmark's stderr/conditions and source manifest remain the cross-check. Capture timing is diagnostic only, **not an untraced wall PP speed ABBA**.

## Decision after first RGP capture

| Finding | Interpretation | Next test |
| --- | --- | --- |
| Draft dense FA dominates identifiable added GPU time and grows with KV | Supports draft query-pruning/KV-only *research*, not correctness | Map required K/V/query dependency and design isolated branch only after correctness audit |
| Target final layer MoE/HC per-row extra GPU time dominates | Prioritize target unmasked NextN graph organization/memory, but cannot drop required row states | Compare actual final layer kernel count/duration OFF vs ON; avoid invalid early row crop |
| Transfer/barrier or CPU/GPU queue stalls dominate | Check pinned output buffer and fallback, readback and draft input upload paths | Add one opt-in readback route counter, avoid tracing side effects |
| RGP cannot distinguish target/draft | Profiling identification incomplete | Add minimal Vulkan debug marker / per-context GPU event labels or bounded kernel counters; do not guess |

**Change policy:** documentation only in canonical r5. Keep validated b11569 trace binary, DENSE/NOOP branches, r5 stable source and untraced b11560 ABBA untouched.
