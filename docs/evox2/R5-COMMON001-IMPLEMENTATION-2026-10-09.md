# r5 COMMON-001 minimal split PLE16 support (2026-10-09)

## Scope and reason

The pinned r5 clean upstream b11517 accepts the Original joined `per_layer_token_embd.weight` GGUF but rejects the split PLE16 GGUF at load time with `check_tensor_dims: tensor 'per_layer_token_embd.weight' not found` (user-provided Windows Vulkan AllocationOnly log, exit 1 on 2026-10-09). The r4 COMMON-001 patch `a60a57879a9ffb4d51acd45d4de7e80d721548f9` already validated split support through 256k on Windows Vulkan and ROCm, but its performance history is **not** a claim that PLE16 is intrinsically faster.

The r5 implementation is **an additive compatibility branch against r5 clean**, intentionally minimal. Only four native source files change: `src/llama-arch.h`, `src/llama-arch.cpp`, `src/models/models.h`, `src/models/qwen4exp.cpp`. This does not import the old r4 source file, MoE-tile diagnostics, VULKAN-002, COMMON-004/005, MTP guard, or GGML backend changes.

## What was implemented

- New split tensor name `ple_ngram_embd.%d.weight`, mapped as layer-repeating and `GGML_OP_GET_ROWS`.
- Per-head `ple_ngram_embd` vector in `llama_model_qwen4exp`; empty for Original/metadata-only.
- Loader:
  - `ml.files.empty()` virtual/metadata-only: retain the joined synthetic tensor path.
  - Real Original with joined `per_layer_token_embd.weight`: retain existing tensor dimension check, padded row handling, `TENSOR_READ_LAZY`, and normal prefetch.
  - Real GGUF without joined: require every split-head tensor, check each head's row count against metadata, create each tensor with actual stored row count and ordinary load flags (`0`). Missing or undersized heads fail explicitly.
- PLE hash computation, EOS reset, predecessor history, KV and other qwen4exp code are unchanged.
- Joined input row indices remain token-major, global-offset; split indices become head-major, head-local.
- Joined graph retains one `ggml_get_rows`; split graph gathers each head with `ggml_view_1d` index slices and concatenates on axis 0 to the same `[ple_head_dim * n_heads, n_tokens]` embedding.
- No new run-time switches and no change to the upstream default MoE tile selector.
- Reuses r4's layer-id-per-head placement convention. This path is targeted at the tested Unsloth Qwen3.8-Flash-Next split GGUF and all-layer-offloaded Evo-X2; partial-offload/multi-GPU routing remains an explicit validation boundary.

## Status

**Windows implementation validation accepted (2026-10-09).** User-provided b11521 Vulkan/ROCm allocation + short inference results pass on both Original and PLE16, and 64k real-input single-run comparisons pass all four backend/model combinations with no material Original regression. See [r5 COMMON-001 Windows validation](R5-COMMON001-VALIDATION-2026-10-09.md). Vulkan PLE16 TG was modestly higher, but its cause is unresolved and no extra measurement is scheduled. The saved b11517 clean binaries remain the comparison reference.

## Original implementation handoff (retained for reproducibility; gates now recorded complete through 64k)

The following were the *pre-validation* instructions. The allocation/short and 64k gates have since passed on the Evo-X2; a standalone COMMON-001 128k/256k sweep is **not required** for acceptance. A future VULKAN-002 experiment will use PLE16 at longer contexts.

## Windows gates (run from the r5 checkout after pulling)

1. Build Vulkan/ROCm in distinct, new build directories, not `build-vulkan-clean` or `build-rocm-clean`. Identify actual executable commit, build ID and SHA.
2. AllocationOnly and short inference on Original and `UnslothPle16`, MTP OFF, f16 KV, on each backend. Check original lazy prefetch and PLE16 tensor offload log/available system memory. Confirm no missing/unused unexpected head tensors.
3. At 64k, compare same-binary Original against PLE16 with identical inputs and config, and compare Original performance to saved r5 clean (Vulkan 269.24 PP/25.31 TG; ROCm 390.73 PP/21.18 TG, single-run references).
4. For VULKAN-002 preparation, extend PLE16 to 128k/256k only after load and 64k gates; the longer comparison should use the same model, stable sampling/seed, QSA union OFF/ON interleaved.
5. If a load/shape/placement regression occurs, preserve stderr, `conditions.json`, hashes, and exact model filename; do not silently fall back to Original or treat an unbuilt patch as validated.

Source-only structural checks performed at implementation: exact one-location edits; joined loader, joined hash/index, prefetch and single GET_ROWS remain present; PLE16 branch is explicit and guarded; no ggml/Vulkan/ROCm files touched. **No compiler/runtime validation performed by this commit.**

Earlier history: [r4 COMMON-001 validation](R4-COMMON001-VALIDATION-2026-10-03.md).
