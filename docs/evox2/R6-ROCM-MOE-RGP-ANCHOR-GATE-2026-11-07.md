# ROCm MoE RGP marker Gate (2026-11-07)

Status: source and benchmark plan implemented. Real HIP build and RGP visibility are NOT verified.

Branch: investigation/r6-rocm-rgp-moe-anchor-20261107
Base commit: 1142fc2f87ad492497d62a9f56ab762155f4b995
The old b12038 RGP Event IDs have not been mapped to layers or exact KV positions.

## Purpose and implementation

The 16k / 32k / 48k Expert histogram gate used an eval callback and GPU synchronization. Its PP timings cannot be compared with RGP. This gate adds default-OFF GPU markers before selected HIP FA and routed MMQ operations with NO new tensor readback or explicit GPU synchronization.

The same-stream, 1-thread markers are named:
- evox2_hip_anchor_fa_layer19
- evox2_hip_anchor_fa_layer23
- evox2_hip_anchor_moe_layer19
- evox2_hip_anchor_moe_layer23

Set GGML_HIP_RGP_ANCHOR=1 to launch markers. GGML_HIP_RGP_ANCHOR_KV=49152 selects the corresponding FA operations only. In the smoke variant it is set to 1024. MoE MMQ receives no KV length, so its marker fires for all layer19/23 routed MMQ calls where ne12=1024. Layer is obtained from the source weight name; currently blk.<layer> or ffn_*-<layer>. If the weight name differs, adjust detection before RGP.

Set GGML_HIP_MMQ_TRACE=1 for sequential host MMQ ID and layer, src0/dst tensor names, weight type, J, expert count, selected-k and anchor status. The log explicitly records KV=unknown and is capped at 512 matching MMQ calls. Host call IDs and original HIP RGP Event IDs are not interchangeable.

No cb_eval callback is used; the config unsets GGML_EVOX2_MOE_TOPK_TRACE. Markers and CPU logs can still change scheduling or graph capture. Do not interpret marker-on PP throughput as clean performance, or assume HIP RGP displays empty one-thread markers until verified.

## Windows build

Run in the existing r6-ppdiag checkout and preserve unrelated untracked files.

    Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
    git status --short
    git fetch origin
    git switch investigation/r6-rocm-rgp-moe-anchor-20261107
    git pull --ff-only
    python .\tools\evox2\tests\test_r6_rocm_moe_rgp_anchors.py
    & C:\TheRock\build\.venv\Scripts\Activate.ps1
    .\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-moe-anchor-r6 -Parallel 4 -AmdGpuTarget gfx1151
    .\build-rocm-moe-anchor-r6\bin\Release\llama-bench.exe --version

Add this NEW key to the local ignored tools/evox2/benchmark/configs/local.psd1. Do not overwrite R6RocmMoeTopk:

    R6RocmMoeAnchor = @{ BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-moe-anchor-r6\bin\Release'; ExpectedBackend = 'ROCm' }

## Smoke then 64k profiling

    $plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-moe-rgp-anchor-20261107.psd1'
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-anchor-smoke -StopOnError

Check for Status OK / ExitCode0 and in stderr.log:
- evox2_hip_rgp_anchor_v1 kind=fa layer=19 KV=1024 N=1024
- evox2_hip_mmq_trace_v1 layer=19 and layer=23 with anchor=1
- Existing evox2_hip_fa_trace_v1 layer19/23, and no eval-callback histogram.

If MoE MMQ trace rows are missing, first inspect actual src0 weight names and change the layer parser. Do not start RGP until smoke is verified.

    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-anchor-code-64k -StopOnError
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-anchor-literature-64k -StopOnError

Capture RGP using the same binary and setup from the earlier ROCm PP RGP runbook. Do not assume the old Event IDs or Dispatch range 181200 still refer to the same work. Look for anchor names adjacent to flash_attn_ext_f16 and mm_ids_helper -> quantize_mmq_q8 -> mul_mat_q. Correlate host MMQ entries by layer/weight/order, not by absolute GPU event ID. The strict MMQ-to-KV mapping remains a verification step because MMQ does not know KV.

Next: compare code/literature at matched RGP positions, then measure unmarked equivalent runs to avoid marker-induced bias.
