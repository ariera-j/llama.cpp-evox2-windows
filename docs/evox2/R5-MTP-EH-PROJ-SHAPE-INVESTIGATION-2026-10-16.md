# r5 MTP `mtp_eh_proj` shape / Vulkan dispatch investigation — 2026-10-16

**Status: SOURCE/RGP ATTRIBUTION COMPLETE ENOUGH FOR A SHAPE-ONLY A/B PROTOTYPE. NO SOURCE OPTIMIZATION IMPLEMENTED YET.**

## Why this operator is next

The retained b11618 Stage-B RGP captured two consecutive 1024-token Draft
catch-up graphs near 51–53k prompt depth:

- Draft graph: **61.661875 / 63.845977 ms**
- `mtp_eh_proj` main kernel: **56.509501 / 58.642678 ms**
- kernel share of Draft graph: **91.65% / 91.85%**
- RGP kernel: `matmul_q8_0_q8_1_0 (80,1,1024)`
- captured pipeline: VGPR256, occupancy 3/16

The parent `MUL_MAT mtp_eh_proj` groups were about 57.157 / 59.270 ms, so the
main kernel itself is about **98.87% / 98.94%** of that parent envelope. The
immediate opportunity is therefore the matmul geometry rather than Q8_1
quantization or barriers.

## Exact Qwen3.8-Flash-Next MTP dimensions

For the tested model:

- `n_embd = 2560`
- hyper-connection count `hc = 4`
- wide Target hidden width = `2560 * 4 = 10240`
- `nextn.eh_proj` weight shape = `[2*n_embd, n_embd] = [5120,2560]`

The MTP graph currently builds:

```cpp
h_norm : [2560, 4, T]
e_norm : [2560, 4, T]   // repeated from [2560,T]
concat : [5120, 4, T]
res_hc = eh_proj * concat
```

For a Stage-B catch-up ubatch with `T=1024`, `ggml_mul_mat` therefore reaches
Vulkan as:

```text
M = 2560
N = 4
K = 5120
batch = 1024
```

The pinned Vulkan backend selects the RDNA3/4 coopmat1 integer Q8 path. Because
`N <= 32`, the generic non-coopmat2 tile selector chooses configuration 0,
the **32x32 small tile**. Its dispatch denominators produce exactly:

```text
ceil(2560/32), ceil(4/32), 1024 = (80,1,1024)
```

which matches the RGP event. This establishes that the 1024 token dimension is
being executed as the Vulkan batch/Z dimension rather than as a wide GEMM N
dimension. There is no hidden backend flattening of the HC and token axes.

The operation performs about **107.36 billion multiply/add FLOP-equivalent
operations** per 1024-token catch-up. At the observed mean ~57.576 ms kernel
time this is only about **1.86 TFLOP/s equivalent**, consistent with a strong
geometry/utilization problem but not by itself proof of the exact bottleneck.

## Highest-value prototype: flatten HC x token before `eh_proj`

The same linear projection is applied independently to every HC stream and
token. Because GGML dim0 is contiguous, the concat tensor can be reshaped
without changing data order:

```cpp
ggml_tensor * eh_in = ggml_concat(ctx0, e_norm, h_norm, 0); // [5120,hc,T]
eh_in = ggml_reshape_2d(ctx0, eh_in, 2*n_embd, hc*n_tokens); // [5120,4*T]

ggml_tensor * res_hc = build_lora_mm(layer.nextn.eh_proj, eh_in); // [2560,4*T]
res_hc = ggml_reshape_3d(ctx0, res_hc, n_embd, hc, n_tokens);      // [2560,hc,T]
```

For T=1024 this changes only the execution geometry:

```text
before: M=2560, N=4,    K=5120, batch=1024
after:  M=2560, N=4096, K=5120, batch=1
```

The arithmetic and logical output mapping are unchanged. `build_lora_mm()`
is simply `ggml_mul_mat` plus optional scale/LoRA operations, so the same
column flattening is also algebraically valid with LoRA.

On the current RDNA3/4 coopmat1 Q8 path, the flattened shape should select the
128x128 large tile instead of the 32x32 small tile. The expected workgroup
geometry is approximately `(20,32,1)`, **640 workgroups**, versus the observed
`(80,1,1024)`, **81,920 workgroups**. This is a geometry prediction, not a
speedup claim; the actual kernel must be measured.

The existing Q8_1 activation quantization also remains naturally aligned:
K=5120 is divisible by 128, so flattening does not move a column boundary into
a Q8_1 x4 block. The total activation data and K-reduction length are unchanged.

## Split-K / upstream status

The pinned source already contains the RDNA3/4 **int8 coopmat1** implementation
from upstream PR #27952; that PR merged on 2026-09-24. The observed
`matmul_q8_0_q8_1_0` is direct evidence that this optimized family is already
being used. Porting #27952 is therefore not a next step.

Upstream PR #30280, **RDNA3/4 Vulkan Large-Tile Split-K Optimization**, remains
open as of 2026-10-16. Its new rule requires a large-tile case with
`N >= 512` and `K >= 2048`. The current unflattened `mtp_eh_proj` has
`N=4`, so the PR is categorically inapplicable to the current geometry.

After flattening, N becomes 4096, but a 128x128 tile already yields 20*32=640
M/N tiles. The existing split-K heuristic only needs K splitting when the M/N
tile count is small relative to shader-core count, so #30280 is not expected to
be the first-order optimization for this operator even after flattening.

Current upstream `master` still uses the same unflattened qwen4exp expression:

```cpp
build_lora_mm(layer.nextn.eh_proj, ggml_concat(ctx0, e_norm, h_norm, 0))
```

No matching upstream PR was found that already performs this HC/token flatten.

## Second-stage model-structure opportunity: remove repeated embedding projection

The converter documents the exact identity:

```text
eh_proj([e ; h_s]) = fc_embedding(e) + fc_hidden(h_s)
```

and currently concatenates the two HF weights into one `NEXTN_EH_PROJ`
tensor. Since the same normalized token embedding `e` is repeated to all four
HC streams, the joined form recomputes the embedding half four times.

Keeping the HF projections separate at GGUF conversion would permit:

1. `fc_embedding(e_norm)` once per token;
2. flattened `fc_hidden(h_norm)` once across all HC/token columns;
3. repeat/add the projected embedding across HC streams.

For hc=4 this reduces the projection's ideal arithmetic from four
`K=5120` projections per token to one `K=2560` embedding projection plus
four `K=2560` hidden projections: a theoretical **37.5% reduction in
multiply/add work** for this operator before backend effects.

This is **not** the first prototype. The current joined Q8_0 tensor cannot be
split into two contiguous Q8 matrices for the Vulkan fast path with a trivial
view: each half has the original full-row stride, so the backend treats it as
non-contiguous and may fall back/dequantize. A clean implementation would
likely require converter/model tensor changes and a newly generated MTP GGUF.
First measure the much smaller graph-only flatten change.

## Recommended A/B and correctness gates

Create a separate Stage-B-derived branch, not from the #30511 re-warmup C0
branch. Add an exact opt-in such as `LLAMA_MTP_EH_PROJ_FLATTEN=1` so one
binary can compare:

- A: Stage-B ON, eh_proj flatten OFF
- B: Stage-B ON, eh_proj flatten ON

Sequence:

1. static graph/shape test;
2. short native functionality gate;
3. 64k ABBA, same QSA/P-MODE/ADLX controls as Stage-B;
4. if material, 128k ABBA;
5. one focused RGP at ~51–53k to verify the kernel changes away from
   `matmul_q8_0_q8_1_0 (80,1,1024)` and measure the new `mtp_eh_proj`;
6. numerical Draft K/V parity or tight error comparison before any merge.

Do not start with VGPR/workgroup shader edits. The current dispatch geometry is
a higher-level and lower-risk explanation of the poor utilization, and it can
be changed without changing the model's mathematics or Vulkan backend.
