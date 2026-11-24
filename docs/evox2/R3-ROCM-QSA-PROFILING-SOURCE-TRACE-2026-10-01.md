# ROCm QSA residual profiling and source trace - 2026-10-01

## Purpose

Record the post-COMMON-004 ROCm profiling result and the source-level trace that
selects COMMON-005 as the next r3 implementation target.

This note is diagnostic. It does not contain the detailed COMMON-005 design;
that comes after this documentation checkpoint.

## Test context

Target workload:

- GMKtec Evo-X2 / Radeon 8060S / gfx1151
- ROCm/HIP build from the COMMON-004 branch
- Qwen3.8-Flash-Next, PLE16-converted Unsloth UD-IQ3_XXS
- 48 layers, `full_attention_interval = 4`
- QSA `top_k = 2048`, compression ratio 4
- f16 attention/indexer KV
- MTP disabled
- COMMON-004 pooled indexer-key cache enabled

Radeon GPU Profiler used dispatch-timer captures of steady single-token decode at
128k and 256k.

## RGP result

Representative timings:

| Kernel | 128k | 256k | Change |
|---|---:|---:|---:|
| `flash_attn_tile<256,256,1,4,false>` | ~1.452 ms | ~2.939 ms | ~2.02x |
| `k_get_rows_float` | ~0.451 ms | ~0.907 ms | ~2.01x |
| `mul_mat_vec_q<type14>` | ~2.835 ms | ~2.836 ms | essentially flat |

The repeated `flash_attn_tile` events were separated by about 586 dispatches.
With 48 layers and `full_attention_interval = 4`, there are 12 full-attention
layers per token, which matches the observed periodic structure.

The RGP runs reported approximately:

```text
128k: 62.11 ms/token
256k: 85.79 ms/token
Delta: +23.68 ms/token
```

Using the representative per-layer increases:

```text
Flash Attention: (2.939 - 1.452) * 12 ~= +17.84 ms/token
get_rows:        (0.907 - 0.451) * 12 ~=  +5.47 ms/token
Total:                                      +23.31 ms/token
```

The estimate is not a strict event-by-event token sum, but it explains almost
the entire measured latency increase.

The radix top-k kernels were individually in the microsecond range and are not
the first target for the remaining 128k -> 256k slowdown.

## Source trace: `k_get_rows_float`

In `src/models/qwen4exp.cpp`, `build_qsa_top_k()` first computes scores in the
compressed block domain, then expands those scores back to KV-cell granularity
through `cell_blk` before running top-k.

Conceptually:

```text
block score
  -> ggml_get_rows(..., cell_blk)
  -> full cell-level score [n_kv, ...]
  -> ggml_top_k(...)
```

`cell_blk` spans `n_kv`, so this `get_rows` scales with the full cache length.
That is the strongest source-level match for the RGP `k_get_rows_float` result:

```text
128k: ~0.451 ms
256k: ~0.907 ms
```

This changes the earlier interpretation. The expensive `k_get_rows_float` is
not evidence that selected K/V are already being compacted; it is evidence of
the block-score-to-full-cell expansion that happens before top-k.

## Source trace: QSA attention still receives full K/V

`build_attn_qsa()` uses the top-k indices to create a sparse full-length KQ mask,
but it still retrieves K and V directly from the full KV cache.

Conceptually:

```text
top-k cell indices
  -> full-length sparse mask
  -> K = full KV cache
  -> V = full KV cache
  -> build_attn_mha(...)
```

The selected width is:

```text
min(n_kv, indexer_top_k + compress_ratio - 1)
```

For the target model:

```text
indexer_top_k = 2048
compress_ratio = 4
selected width = 2051
```

So the logical sparse budget is nearly fixed while the physical K/V tensors
passed to attention continue to grow with context depth.

## The graph already passes a sparse hint

`build_attn_mha()` calls `ggml_flash_attn_ext_set_n_kv_max()` on the Flash
Attention node.

For this workload the graph can therefore communicate roughly:

```text
full K/V length: 128k or 256k
maximum finite mask entries per query: 2051
```

The model graph is not missing the sparse-budget hint. The backend behavior is
the important part of the remaining ROCm scaling.

## HIP sparse Flash Attention is currently disabled

In `ggml/src/ggml-cuda/fattn.cu`, the sparse mask-compaction implementation is
guarded out for HIP/MUSA, and the HIP sparse-selection predicate returns false.
The helper that compacts a mask into sparse KV indices aborts if called under
HIP.

Therefore the observed HIP path:

```text
flash_attn_tile<256,256,1,4,false>
```

does not use the QSA `n_kv_max` hint to reduce K/V work. It continues to process
the full K/V length, which explains the almost exact 2x growth when context is
doubled from 128k to 256k.

## Vulkan and MiniMax-M3 precedents

Two existing implementations are useful references, but they solve the problem
at different layers.

### Vulkan backend

The current Vulkan backend has a sparse Flash Attention mask-compaction path.
It can convert finite entries of a full mask into a compact KV-index list and
use the `n_kv_max` hint when its backend conditions are satisfied.

This helps explain why the post-COMMON-004 Vulkan TG slope is much flatter than
ROCm even though both use the same qwen4exp graph.

### MiniMax-M3 model graph

The current MiniMax-M3 decode implementation provides a model-layer precedent:
it runs top-k, builds selected row indices, gathers K/V/mask with
`ggml_get_rows()`, and calls Flash Attention on the compact tensors.

Conceptually:

```text
top-k
  -> selected row indices
  -> get_rows(K)
  -> get_rows(V)
  -> get_rows(mask)
  -> compact K/V/mask
  -> Flash Attention
```

This is especially relevant to COMMON-005 because it avoids depending on a new
HIP sparse-FA backend implementation for the first prototype.

## Decision: COMMON-005 starts next

The profiling and source trace now justify the gather-based QSA decode path.

Basic scope for COMMON-005:

- qwen4exp single-token decode first
- gather the selected K/V rows and required mask rows after top-k
- run ordinary Flash Attention on the compact tensors
- leave prompt/batched QSA unchanged initially
- keep a short-context gate
- keep a runtime A/B switch
- verify row/mask correctness before accepting performance results
- use 128k and 256k ABBA measurements as the primary long-context comparison

Do not combine the score-expansion rewrite into this patch. The exact tensor
shapes, index construction, fallback rules, and runtime-control name are left to
the dedicated COMMON-005 design step.

## COMMON-006 candidate

After COMMON-005, evaluate moving QSA selection closer to the block domain.

Current flow:

```text
block score
  -> expand to every KV cell
  -> cell-level top-k
```

Candidate flow:

```text
block-domain selection
  -> expand only selected blocks to cell indices
```

This targets the RGP `k_get_rows_float` path, which still scales approximately
linearly with context depth.

The design must preserve qwen4exp reference behavior for:

- `indexer_top_k + compress_ratio - 1`
- tail-block handling
- causal/visibility masking
- tie/ordering behavior

COMMON-006 should remain a separate correctness-first A/B so COMMON-005's
attention effect can be measured independently.

## Bottom line

COMMON-004 removed the repeated full pooled-summary reconstruction, but ROCm
still had two context-linear decode costs. RGP and source tracing now align:

1. `k_get_rows_float` matches full block-score-to-cell expansion.
2. `flash_attn_tile` still receives full K/V because HIP does not use the sparse
   Flash Attention hint.

Those two paths account for nearly all of the measured 128k -> 256k latency
increase. COMMON-005 is therefore the next implementation target; COMMON-006 is
the follow-up candidate for the remaining full-cell score expansion.
