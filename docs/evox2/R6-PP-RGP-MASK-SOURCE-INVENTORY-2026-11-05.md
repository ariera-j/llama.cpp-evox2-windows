# r5 → r6 source compatibility inventory for PP mask/RGP (2026-11-05)

> Review complete **at source level only**. No r6 Vulkan diagnostic implementation, build, GPU execution, or RGP trace was produced by this review.

## Baselines / exact branches

- r6 source chosen: `feature/r6-llama-bench-real-prompt-20261103`, commit `6a092fd2e60789d6ff7001cbe8e342fccff323ac` (new investigation branch forked here).
- Historical diagnostic source: [`investigation/r5-vulkan-off-fa-dispatch-20261010`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-vulkan-off-fa-dispatch-20261010) at reviewed branch head `65ed1285c3d6429b4d63c75fba7a87d7f627ac50`.
- Historical experiment report: [r5 OFF FA dispatch and mask diagnostics](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-vulkan-off-fa-dispatch-20261010/docs/evox2/R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md).
- Other RGP marker / dispatch ordinal design (not the same branch): [r5 MTP markers](R5-MTP-PP-RGP-MARKERS-IMPLEMENTATION-2026-10-14.md), [r5 MTP dispatch calibration](R5-MTP-PP-RGP-DISPATCH-CALIBRATION-2026-10-14.md).
- ROCm preexisting 128k decode trace: [r6 COMMON-005 RGP](R6-COMMON005-RGP-2026-11-02.md); **decode** at 128k does not identify **prefill** at 64k.

## 1. Vulkan two-bit mask: existing shader works in both branches

**r5 and r6** `ggml/src/ggml-vulkan/vulkan-shaders/flash_attn_mask_opt.comp`:
- Implements per-`Br×Bc` tile classification, 16 tiles packed into each 32-bit word.
- Bit code **1 = ALL_NEG_INF**, **2 = ALL_ZERO**, **0 = mixed/other**, **3 = invalid/reserved**.
- Produces *metadata*, not the underlying raw token-level attention mask.

**r6** `flash_attn_cm1.comp` checks the packed 2-bit classification. On `MASK_OPT_ALL_NEG_INF` it immediately skips the KV tile (with its existing shader control flow). The code also checks mixed masks and may skip additional blocks, meaning **1-bit empty statistics alone cannot count all actual skips**.

## 2. r5 opt-in debug instrumentation is NOT present on r6

In r5 diagnostic branch `ggml/src/ggml-vulkan/ggml-vulkan.cpp`:
- `GGML_VK_FA_RGP_MARKERS=1` / `ggml_vk_fa_rgp_dispatch` wraps the **existing** FA mask/main/sparse/split/reduce dispatches in `VK_EXT_debug_utils` labels `EVOX2_FA_<stage> shader=... KV=... N=... Br=... Bc=... n_kv_max=... q=...`.
- `GGML_VK_FA_MASK_DIAG=1`, `..._KV`, `..._QUERY`, `..._FILE` trigger one bounded copy of already-computed mask-opt packed metadata into a persistent GPU buffer, defer the CPU readback until backend synchronization, and emit a **per-query-tile-row + total** CSV.
- `GGML_VK_FA_DISPATCH_DIAG=1` collects per-context CPU FA-path histogram, **not** GPU timings. Useful only if host dispatch path changes.
- r5 uses `GGML_VK_QSA_UNION=0` to preserve the non-union path. Old markers and snapshot are independent opt-ins, not production features.

In the pinned r6 `ggml-vulkan.cpp` these three `GGML_VK_FA_*` diagnostic mechanisms and `ggml_vk_fa_rgp_dispatch` are **absent**. The normal Vulkan FA mask-opt dispatch still exists, around the existing `if (use_mask_opt)` block, as does the `GGML_VK_QSA_UNION` implementation. **Port selectively**; do **not** cherry-pick an entire r5 17k-line file, since r6 QSA, layout and upstream dispatch code changed.

Historical r5 one-shot snapshot implementation locations for guided diff (line numbers are approximate on that frozen branch):
- `ggml-vulkan.cpp` ~8–50: env gates;
- ~1468–1545: `ggml_vk_fa_mask_diag_flush` and packed-tile decoder;
- ~5558–5611: debug-utils initialization;
- ~8558–8580: FA stage marker wrapper;
- ~8980–9025: one-shot capture immediately after mask-opt dispatch; note independent buffer because `prealloc_y` is reused;
- ~13771 / ~14047: backend deinit/sync points and deferred CSV flush;
- `ggml-vulkan-types.h`: per-context snapshot counters and buffer.
- r5 `Measure-LlamaBench.ps1` had run-local diagnostic-file wiring. The current r6 bench wrapper needs explicit compatibility checks before claiming it automatically captures the **new** tile-map artifact.

## 3. r5 dump limitation → r6 requested enhancement

**r5 emitted row aggregates, NOT tile positions.** It decoded the packed 2-bit data and immediately reduced them to `all_neg_inf,all_zero,mixed,invalid` totals per query row.

For the new investigation, save **exact positions** at fixed `KV=49152 N=1024 Br=16 Bc=64` (subject to actual r6 runtime verification):
- normalized logical grid per mask plane: `query_tile_index 0..63` × `kv_tile_index 0..767` (**64×768 = 49,152 tiles**);
- packed size when one plane: `49152*2/8 = 12,288 bytes` before any serializer overhead;
- stable format: a small `mask-meta.json` containing run ID, source/model/exe hash, q tensor/layer, KV/N/Br/Bc, plane count, row stride and bit-code mapping; a `mask-tiles.bin` of exact copied `uint32` packed words; and `mask-row-summary.csv` with category counts.
- label the plane/slice dimension; don't assume `nem2*nem3 == 1` without runtime proof.
- clamp any saved raw tile blob to **<=1 MiB**, one-shot, explicit target mask tensor and query, and save its file SHA256. A missing target should leave an explicit `not_captured` reason, not a fake all-zero map.

Correctness assertions: byte count equals metadata dimensions; no code3; row sum=tiles per row; total sum=rows×columns×planes; all tile positions valid; old row summary reproduced by decoding saved `.bin`; decode a known causal triangular 1k smoke before 64k. Do **not** use `mask-row-summary.csv` alone as the heatmap data source.

## 4. Instrumentation design constraints

**Vulkan marker-only mode**
- Propose `GGML_VK_PP_FA_RGP_MARKERS=1` or reuse old `GGML_VK_FA_RGP_MARKERS=1`; decide **one canonical flag** before implementation, document literal-1 semantics.
- Label each FA dispatch by **actual** shader/pipeline, K tensor KV, N, Br, Bc, n_kv_max, q name, graph/layer hint if available, and explicit phase if reliably available. Never fabricate a phase from host timestamp.
- No new GPU compute, buffer copy or forced sync in marker-only mode.
- Calibrate and verify RGP marker visibility on **r6**; r5 marker visibility is historical proof only.

**Vulkan snapshot-only mode**
- Recommend canonical `GGML_VK_FA_MASK_DIAG=1` family **for compatibility with r5**, but output richer packed-data artifacts. Default OFF.
- Reuse r5 one-shot post-mask-opt device→device copy pattern; perform CPU mapping/decoding **after** existing sync and before backend memory destruction, never read/overwrite live `prealloc_y` too late.
- Distinct output prefix/run ID; no source token text dumped. Save bounded artifacts and a single explicit capture confirmation. Existing output must not be overwritten inadvertently.
- No marker + snapshot + perf logger simultaneous invocation in the same matched timing comparison.

**ROCm/HIP RGP**
- Existing AMD RGP HIP capture successfully sampled `flash_attn_tile`, mask/indexer events for r6 **decode**. For 64k prefill, the actual FA template, layer and token position need independent confirmation.
- A HIP RGP kernel name and grid alone may repeat across layers and UBatches; propose a bounded CPU-side graph/dispatch correlation record plus an experimentally verified HIP marker/launch ID if available. Do **not** assume Vulkan debug-utils marker syntax or exact RDP ordinal equivalence for HIP.
- Avoid introducing a HIP `deviceSynchronize`, per-kernel profiler callbacks or kernel mode switches just to annotate; these can alter scheduling. If source-level HIP correlation is required, implement as a separate opt-in patch and test with short PP first.
- r5 HIP historical suffix scan `flash_attn_mask_to_KV_max` may or may not appear in r6 prefill; verify actual kernel names and selected QSA path in RGP rather than assuming.

## 5. Open implementation questions (resolve at G0/G1)

1. Verify current r6 `ggml-vulkan-types.h` lifetime and deferred destruction sequence suitable for one-shot copy; no premature free.
2. Does `Qcur-19` still map to the same logical layer/query operation? Calibrate with short+64k marker only before fixing output filter.
3. Does r6 choose `Br=16 Bc=64`, `use_mask_opt` and `KV=49152` for this exact input and QSA OFF? If not, record actual geometry and revise expected tile grid.
4. Do we need a CPU-side dispatch ordinal/range trace to map Vulkan RDP absolute dispatch range to the correct FA call? r5 `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE` is reference code in a **different** r5 branch, and host-call counter may not equal RDP's global renderop ordinal.
5. How to prove HIP launch/graph layer identity in RGP without perturbing the PP? If unprovable, report observed **unmatched HIP exploratory event timings only**.

**Next code change:** implement marker-only first on r6 and native smoke test it; only then implement the separate packed mask snapshot/export.
