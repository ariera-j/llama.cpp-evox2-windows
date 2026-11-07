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


## Visibility probe follow-up — 2026-11-07

Two b12161 RGP captures with start=181200 and start=181500, count512, show valid MoE kernels and long FA but do not show the four layer-specific anchors. This does not prove the anchor was optimized out: only layers19/23 are marked and each 512-dispatch capture covers a small part of the full PP.

For a discriminating follow-up, use the **separate** branch `investigation/r6-rocm-rgp-anchor-visibility-20261107` instead of guessing more start offsets. All HIP anchor kernels now launch 128 blocks x 64 threads instead of one thread. `GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE=1` adds a distinct `evox2_hip_anchor_moe_any_gate` immediately before the routed MoE Gate MMQ in **every** layer with N1024. It emits at most 16 short `evox2_hip_anchor_probe_v1` host messages. The original FA and layer19/23 MoE anchors remain in place.

This is deliberately a **visibility-only** experiment: many additional dispatches and HIP graph captures can change graph scheduling and profiling behavior. Never use its PP speed to compare code/literature or original RGP.

### New gate

1. Switch to the new branch. Build into a new directory `build-rocm-moe-anchor-probe-r6` using `Build-ROCm.ps1 -AmdGpuTarget gfx1151` and verify build commit identity.
2. Add a new local ignored build key `R6RocmMoeAnchorProbe` pointing to the new build directory (keep `R6RocmMoeAnchor` for the original b12161 build).
3. Run `python tools/evox2/tests/test_r6_rocm_moe_rgp_anchors.py`, then `-OnlyVariant moe-anchor-smoke` with no RGP. Confirm `evox2_hip_anchor_probe_v1` is present with `src0="blk.X.ffn_gate_exps.weight"`. Confirm FA and layer19/23 logs are still present.
4. For the only necessary full RGP run, use `-OnlyVariant moe-anchor-code-visibility-probe-64k`, HIP Dispatch range start=181500,count512, SQTT High, counters/instruction trace OFF. Search Event Timing for `evox2_hip_anchor_moe_any_gate`. This all-layer marker should appear beside at least one MoE Gate if visible, rather than relying on a rare layer19/23 target.
5. If the generic marker is seen: the earlier two captures likely missed target layers (not proven until layer matching). If no generic marker is seen *despite a trace window containing topk_moe_cuda/mm_ids_helper and logged probe launches*, investigate RGP/HIP graph marker visibility next. In that case do **not** keep adjusting dispatch starts blindly.

The ROCm build uses `GGML_HIP_GRAPHS` enabled by default in this source tree. A host launch message may describe graph capture, not a completed physical GPU dispatch. Kernel names and durations are confirmed only when the new RGP displays them.

Probe build key in ignored `tools/evox2/benchmark/configs/local.psd1`:

    R6RocmMoeAnchorProbe = @{ BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-moe-anchor-probe-r6\bin\Release'; ExpectedBackend = 'ROCm' }

All variants in this visibility branch's plan use this new BuildKey. Do not use the old b12161 binary for this probe.

## Layer-tagged RGP anchor gate — 2026-11-07

**Branch:** `investigation/r6-rocm-rgp-moe-layer-tags-20261107` (based on the successful HIP visibility experiment b12162).

The b12162 RGP HIP Event Timing captured five `evox2_hip_anchor_moe_any_gate()` GPU dispatches, including Event 101 between `topk_moe_cuda` and `mm_ids_helper`. This establishes that the 128-block x 64-thread HIP marker is visible to RGP. The generic names, however, cannot resolve the layer.

This gate replaces **only the all-MoE-gate probe** with `evox2_hip_anchor_moe_tagged<N>` when the source weight name gives layer `N` in the range 0..63. Each template specialization emits a different number of volatile `s_nop 0` instructions, avoiding identical GPU instruction sequences for every layer. The runtime switch instantiates all 64 tags. The old `evox2_hip_anchor_moe_any_gate` is retained as a fallback when the layer is unrecognized or >=64. Layer19/23-specific FA/MMQ probes stay unchanged. No model tensor readback or GPU synchronization is added.

`GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE=1` gates all tagged launches; default OFF. The bounded host log changes from `evox2_hip_anchor_probe_v1` to `evox2_hip_anchor_probe_v2` with `layer=<N> tagged=1` or `tagged=0` for fallback. Host logs are not GPU dispatch IDs, and HIP Graph capture/replay can change their relationship to GPU events.

### Build and test

Use a new directory so the previous b12162 binary remains available:

    git fetch origin
    git switch --track origin/investigation/r6-rocm-rgp-moe-layer-tags-20261107
    python .\tools\evox2\tests\test_r6_rocm_moe_rgp_anchors.py
    & C:\TheRock\build\.venv\Scripts\Activate.ps1
    .\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-moe-layer-tags-r6 -Parallel 4 -AmdGpuTarget gfx1151
    .\build-rocm-moe-layer-tags-r6\bin\Release\llama-bench.exe --version

Register a new key in the ignored `tools/evox2/benchmark/configs/local.psd1`:

    R6RocmMoeLayerTags = @{ BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-moe-layer-tags-r6\bin\Release'; ExpectedBackend = 'ROCm' }

### Smoke and one 64k RGP capture

    $plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-moe-rgp-anchor-20261107.psd1'
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-anchor-smoke -StopOnError

Check for `evox2_hip_anchor_probe_v2 ... layer=... tagged=1` in smoke stderr and that b12162 was NOT accidentally reused. Then run one 64k **code** variant and capture RGP:

    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-anchor-code-layer-tags-64k -StopOnError

RDP: **HIP / Dispatch range / start=181500 / count=512 / SQTT High**, shader counters and instruction tracing OFF. Previously this setting captured five generic anchors. The additional code changes GPU graph composition and timings, so the same dispatch start is only a sensible initial position, not a guaranteed exact location. Search RGP Event Timing for `evox2_hip_anchor_moe_tagged` and note `<N>` and adjacent `topk_moe_cuda`, `mm_ids_helper`, and MMQ kernel durations. If the capture includes several layer tags, it enables locating layer19/23 relative to them; do not claim a KV index until the FA KV49152 marker is also identified.

After the code gate confirms the template symbols, use the same build/settings for literature in a separate run; do not preemptively perform another full sweep. Ignore PP throughput in all marker-on and RGP-on runs.
