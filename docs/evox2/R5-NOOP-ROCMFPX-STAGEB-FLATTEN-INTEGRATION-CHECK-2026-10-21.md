# r5 NOOP + ROCmFPx + Stage-B + eh_proj flatten integration check — 2026-10-21

## Purpose

This is a source-level integration rehearsal only.

Base branch:

```text
integration-check/r5-noop-rocmfpx-20261021
```

Second rehearsal branch:

```text
integration-check/r5-noop-rocmfpx-stageb-flatten-20261021
```

The base branch already passed the bounded Windows integration gate for:

- VULKAN-002 grouped-union;
- MTP-DENSE;
- MTP-NOOP;
- ROCmFP4 / ROCmFPx core + Vulkan;
- old-layout Agention ROCmFP4 MTP sidecar compatibility.

This check asks only whether the validated Stage-B Draft prefill path and the eh_proj flatten experiment can be added without structurally displacing those features.

No new Windows build or runtime performance claim is made here.

## Production source selected from the Stage-B / flatten line

### Stage-B functional commits

```text
792d231f0902  mtp: add opt-in zero-output Draft graph root crop
be45701a811c  graph: tolerate unallocated hybrid attention mask for KV-only graph
82812e18841d  refactor(evox2): declare Qwen4Exp Draft-only KV graph helper
f1c6df45a407  feat(evox2): bypass Flash Attention for zero-output Qwen4Exp Draft KV catch-up
```

The later commit:

```text
723961925dcb  fix(evox2): classify K/V cache graph writes using ggml_set_rows index operand
```

was intentionally **not** ported. It only corrects the opt-in Stage-B diagnostic counters/log label and is not required by the production KV-only graph path.

### eh_proj flatten commits

```text
cb069334ec45  experiment: flatten qwen4exp MTP eh_proj columns
b3ff6a38ece1  experiment: scope MTP eh_proj flatten to Stage-B prefill
```

The final flatten control remains opt-in and is scoped to the Stage-B prefill condition:

```cpp
const bool mtp_eh_proj_flatten =
    draft_prefill_kv_crop &&
    eh_proj_flatten_env && std::strcmp(eh_proj_flatten_env, "1") == 0;
```

Therefore enabling `LLAMA_MTP_EH_PROJ_FLATTEN=1` alone does not alter normal output-producing MTP verification/decode graphs.

## Integration result

Compared with the already-passing
`integration-check/r5-noop-rocmfpx-20261021`
base, this branch changes only three production files:

```text
src/llama-graph.cpp      +6 / -1
src/models/models.h     +10 / -0
src/models/qwen4exp.cpp +106 / -2
```

No Vulkan, ROCmFPx, DENSE, NOOP or speculative-runtime source file is replaced.

### Clean applications

The following applied without semantic conflict:

- hybrid-mask buffer guard in `src/llama-graph.cpp`;
- `build_layer_attn_kv_only()` declaration in `models.h`;
- Stage-B dedicated KV-only helper implementation and call path in `qwen4exp.cpp`.

### Expected qwen4exp overlap

Two source patches used the old mandatory:

```cpp
layer.nextn.hc_head_norm
```

assert as context.

The ROCmFPx integration base already replaces that assertion with the validated old-HC-compatible condition accepting either:

- current `blk.<il>.nextn.hc_head_*`, or
- old Agention `output_hc_*`.

This is a textual overlap, not a functional conflict.

The Stage-B and flatten logic was inserted around the already-integrated old-HC condition, preserving both behaviors.

The existing ratio-zero dense-MTP k-pool guard is also retained.

## Final static coexistence state

Verified present together on this branch:

| Feature | Result |
| --- | --- |
| VULKAN-002 grouped-union | preserved |
| selected-row FA API | preserved |
| MTP-DENSE | preserved |
| MTP-NOOP | preserved |
| ROCmFP4 / ROCmFPx Vulkan paths | preserved |
| old Agention `output_hc_*` fallback | preserved |
| ratio-zero dense-MTP k-pool guard | preserved |
| Stage-B `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` | present, opt-in |
| Stage-B KV-only helper | declaration + implementation present |
| KV-only hybrid attention-mask buffer guard | present |
| eh_proj flatten `LLAMA_MTP_EH_PROJ_FLATTEN` | present, opt-in |
| flatten scoped to Stage-B prefill | verified |

The dedicated Stage-B helper still asserts that it is only used on the dense MTP block:

```cpp
GGML_ASSERT(hparams.dsv4_compress_ratios[il] == 0 &&
            "KV-only MTP catch-up cannot use a QSA/indexer layer");
```

and the call site retains:

```cpp
GGML_ASSERT(inp_kpool == nullptr && "KV-only Draft requires dense MTP");
```

These constraints align with the existing DENSE/ROCmFP4 MTP sidecar path.

## Integration note discovered during rehearsal

When replaying Stage-A/Stage-B semantically, do not apply the
`inp_out_ids = draft_prefill_kv_crop ? ...`
change by a global first-text match.

Qwen4Exp has both target and MTP graph builders with similar
`inp_pos / inp_out_ids` text. The conditional belongs specifically inside
`graph_mtp::graph_mtp`.

The rehearsal caught and corrected this before finalizing the branch. The weekend newest-upstream port should anchor this edit by function scope rather than by nearby text alone.

## Decision

**SOURCE-LEVEL INTEGRATION FEASIBILITY: PASS.**

There is no structural blocker to combining:

- VULKAN-002;
- MTP-DENSE;
- MTP-NOOP;
- ROCmFP4 / ROCmFPx;
- old-HC MTP compatibility;
- Stage-B Draft KV-only prefill;
- Stage-B-scoped eh_proj flatten

on the pinned r5 lineage.

No extra long-context measurement is justified for this rehearsal.

The final weekend integration should still start from the chosen newest upstream and reapply these behaviors semantically. Qwen4Exp and k-pool code have moved upstream, so this branch is a compatibility proof and porting reference, not a merge target to copy wholesale.
