# Strata v0.2.13 vs llama.cpp v1 Dense GEMM (gfx1151, 2026-11-15)

## Scope and evidence

This is a **pinned-source comparison**, NOT a matched-kernel benchmark and NOT evidence that a specific fast path was chosen at runtime. Sources:

- [Strata v0.2.13 `src/prefill/gemm.cu`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/prefill/gemm.cu), [`wmma_gemm.cu`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/prefill/wmma_gemm.cu), [`prefill.cpp`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/prefill/prefill.cpp), [`arch_defaults.cpp`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/core/arch_defaults.cpp), [`dequant_bf16.cu`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/kernels/cuda/dequant_bf16.cu), [`hipblaslt_tuning.hpp`](https://github.com/Niko1221/Strata/blob/v0.2.13/src/prefill/hipblaslt_tuning.hpp), and [gfx1151/hipBLASLt100500 table](https://github.com/Niko1221/Strata/blob/v0.2.13/tools/hip/gfx1151-hipblaslt-100500.txt).
- [llama.cpp v1 research branch `ggml/src/ggml-cuda/ggml-cuda.cu`](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/v1-strata-dense-gemm-20261115/ggml/src/ggml-cuda/ggml-cuda.cu) (upstream v1.0.0 source plus opt-in trace and Q6K override).
- [Q6K BLAS/MMQ measurement and real-model run](V1-STRATA-Q6K-DENSE-BLAS-MMQ-EXPERIMENT-20261115.md).
- [Earlier Strata-vs-r6 broader source study](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/STRATA_V0213_VS_LLAMA_R6_PP_SOURCE_COMPARISON_20261115.md) and [Strata A/C/E 2x2](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/runs/2026-11-15-pp-matrix8-hipblaslt-interaction-ace.md). Earlier audit compared **r6**; this document checks the **current v1 research branch**.

Target: Radeon 8060S gfx1151, old original 3-shard Unsloth Qwen3.8 Flash Next UD-IQ3_XXS. Actual llama layer-19 Dense Attention Q uses Q6_K `K=2560,M=12288`, Attention Output Q6_K `K=6144,M=2560`.

## Side-by-side operation pipeline

| Area | llama.cpp v1 ROCm branch | Strata v0.2.13 Windows HIP | What it means |
| --- | --- | --- | --- |
| Model graph entry | `ggml_cuda_mul_mat` dispatches `MMVQ`, `MMQ` or `ggml_cuda_mul_mat_cublas` | `native_proj` -> `Gemm::native`, and separate BF16/FP16 paths | The graph and physical row T / GGML N schedule are not identical |
| Quantized weight | BLAS uses `ggml_get_to_fp16_cuda` into pooled temporary buffer | Dense native path uses `dequant_f16` / `dequant_f16_ld` into scratch, then F16 GEMM; optional Windows HIP `STRATA_DENSE_MMQ=1` is **off unless explicitly enabled** | Both can expand quantized weights; kernels/layouts and scratch lifetime differ |
| Dense shape specialization | Existing GGML heuristics select MMQ or generic BLAS. The research override tests only Q6_K two shapes at N=256/512/1024, **off by default** | `STRATA_PF_GEMM=1` invokes custom gfx11 FP16 WMMA before library fallback if T>=min, T>=64, N>=512, K multiple of 32, supported buffers | A distinct shape-/arch-specialized GEMM path exists in Strata; its actual runtime occupancy needs confirmation |
| Padded leading dimensions | No equivalent gfx1151 `K+64` padded dequant + WMMA route in the reviewed normal BLAS implementation | `STRATA_PF_PAD=1` plus `PF_GEMM=1` can dequantize weights to F16 scratch with row stride `K+64` and use padded X/WMMA; `prefill.cpp` explicitly targets two K=6144 projections, including `attn_output` | **Most concrete Attention Output-specific difference**; possibly reduces memory-channel stride conflicts |
| GEMM library | `cublasGemmEx` through HIP compatibility (hipBLAS/rocBLAS) with default tensor-op algorithm; no custom tuned solution-file lookup in this code path | If custom PF_GEMM does not take, `try_hipblaslt` consults an arch+version+shape table; then alternative paths and `cublasGemmEx` fallback | Do not reuse Strata's solution IDs with TheRock ROCm 10.0.0 or assume its table was consulted for a shape taken by PF_GEMM |
| Output format | With quantized source and selected compute_type F16 on this RDNA3.5 target, regular cublas code typically uses an F16 temporary output then converts to GGML F32. See the `prefer_f32_output` decision. | Normal `Gemm::f16`/PF_GEMM writes F32 results; a separately gated `STRATA_HIP_PROMPT_F16` path can use F16 output/widening | Not guaranteed bitwise-equivalent; do not claim numeric identity or map PF_F16 (MoE flag) to the dense F16 output switch |
| Physical prompt shape | Observed Layer19 N=1024 x60 and N=351 x1; N=512 absent for 64k/ubatch1024 | Strata uses different auto prefill chunking (Windows guide ~16K) and a different engine API PP timer | Existing standalone microbench N<=1024 is **not** a matched-T Strata GEMM comparison |

### Specific source-level dispatch rules

**Strata:** `Gemm::native()` in `gemm.cu` checks `PF_PAD && PF_GEMM`, T>=64, output width N>=512, K%32=0 and room for `N*(K+64)` elements, then calls `dequant_f16_ld` and `strata_pf_gemm_f16_ld` (roughly lines 1368-1386). `dequant_f16_ld` rejects i-quants, but supports the standard Q6_K geometry (the branch's Q6_K type is handled by the normal dequant kernel). For eligible `attn_output` (K=6144, M=2560) with padded X and weights, this route is structurally applicable; **a real dispatch trace is still needed to assert it was taken**. If it does not take, the code falls back to other dequant+F16 GEMM paths.

`Gemm::f16()` (roughly lines 1186-1270) first offers `strata_pf_gemm_f16` under `STRATA_PF_GEMM`, before optional WMMA GEMM, an F16-output-specific route, `try_hipblaslt`, a special SGEMM and `cublasGemmEx`. `strata_pf_gemm_f16_ld` validates T>=64, N>=512, K divisible by block K (32), and gfx11, then chooses a WMMA kernel; the larger N branch can use a 64-step K tile. The explicit `STRATA_DENSE_MMQ=1` route is separate and is not the default native Dense mechanism.

**llama.cpp:** `ggml_cuda_mul_mat()` (roughly lines 2478-2564) chooses MMVQ/MMQ for eligible small and quantized cases; the default BLAS path (`ggml_cuda_mul_mat_cublas_impl`, roughly 1832-2043) allocates and converts quantized weights/activations to the chosen compute type, launches `cublasGemmEx` on nonbatched F16 matrices, and may convert F16 temporary output back to F32. No per-shape hipBLASLt solution table or Strata's explicit K+64 padded dequant path is found in the reviewed function. The opt-in route override in this branch is only a diagnostic experiment, not a performance patch.

**hipBLASLt table:** Strata's packed table has 32 BF16/F16 records, keyed by output N, input K, output leading dimension, and T bucket. For example F16 `N=2560,K=6144,ldy=2560` and `N=12288,K=2560,ldy=12288` exist at T buckets 4096/8192, tied to gfx1151 and hipBLASLt version 100500. Runtime `T` may choose its nearest bucket if that route is reached. But an eligible PF_GEMM branch precedes hipBLASLt; table presence **does not prove** a particular Dense projection used it. A different hipBLASLt build may reject/reassign IDs; do not copy this table into llama.cpp.

## What has actually been measured

### llama.cpp operator tests (two runs each)

- Attention Q: N256 BLAS~MMQ (1076.53 vs 1079.41 us); N512 BLAS 1501.72 vs MMQ 2220.61 us; N1024 BLAS 2581.34 vs MMQ 4122.41 us.
- Attention Output: N256 BLAS 1196.68 vs MMQ 508.00 us; N512 BLAS 1832.11 vs MMQ 1100.88 us; N1024 BLAS 2405.51 vs MMQ 2709.23 us.
- CPU reference test passed separately for both routes on Attention Q N256 and Attention Output N512. Other perf shapes are not CPU-reference-validated.
- In one code64k real-model trace (build b12367, batch2048, ubatch1024, KV f16), Layer19 Attention Q and Output each showed 60 BLAS records at N1024 and one at N351, **zero N512**. 1253/1253 trace lines, not truncated; tracing changes throughput. No full-model improvement demonstrated.

### Strata previously completed whole-PP ablations

- Old frozen code64k, Strata v0.2.13/engine HIP 0.1.59, one run per arm in controlled A/C/E 2x2 (20 exact gfx1151 flags and buffers held): normal A ~1461.5 PP tok/s, Matrix8 OFF ~775.2, packaged hipBLASLt table OFF ~1050.9, both OFF ~349.7.
- Matrix8 includes **eight switches**, among them PF_GEMM, PF_FUSED, PF_F16, PF_DM16, WMMA attention, selector and HC. Table OFF can cause large PP loss through several shapes/fallbacks. **Neither toggle isolates Dense PF_GEMM or Attention Output**, and these whole-PP data are not a speedup of a named kernel.
- llama.cpp v1 code64k with TRACE ON reported PP 411.42 tok/s (61795 tokens); Strata same frozen file tokenized as 61813, uses int8 KV, different chunking and timer boundaries. **Do not interpret their PP ratio as the GEMM speedup.**

## Provisional judgment and recommended next measurement

1. The existing BLAS -> MMQ blanket swap is *not* the priority. In the observed 64k llama.cpp N1024 case, BLAS is faster for both relevant projections. Preserve automatic dispatch.
2. Most concrete **new** candidate: **Strata `PF_GEMM` custom FP16 WMMA and `PF_PAD` K6144 leading-dimension trick**, not merely a different MMQ threshold. Check the actual native GEMM path and count before porting or attempting a rewrite.
3. Highest-value small Strata ablation: reproduce A under unchanged default conditions, then compare **only `STRATA_PF_GEMM=0`**, keeping the packaged hipBLASLt table, all other Matrix8 switches, 20 exact flags and auto chunk/buffer settings constant. Note that PF_PAD becomes inert with PF_GEMM off, so this measures a **PF_GEMM + dependent PF_PAD combined effect**, not PF_GEMM alone. If reproducible, test **only `STRATA_PF_PAD=0`** (PF_GEMM stays on), to isolate the extra K6144 padding contribution. Recheck start logs, output hashes, PP/TG and resource/clock stability; do not claim numerical parity.
4. If controlled ablation indicates meaningful benefit, match actual physical GEMM shapes (`T`, output `N`, input `K`), compare GEMM wall/event timings and relevant rocBLAS/hipBLASLt algorithm IDs using a targeted profiler before deciding which gfx1151 kernel/dispatch technique to prototype in llama.cpp. Avoid porting wholesale source; start with the smallest isolated opt-in experiment and CPU-reference/long-context correctness gates.

**Status:** source-only investigation complete; no fresh Strata engine run, no paired kernel timings, no llama.cpp GEMM optimization applied.
