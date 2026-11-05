# Gate 1: 4k Vulkan RGP capture — runbook (2026-11-06)

**Purpose:** find at least one real \`EVOX2_FA_\` event in Radeon GPU Profiler (RGP) on an instrumented r6 Vulkan GGUF prefill. This is **capture-position calibration**, not a speed comparison or a 64k/128k experiment.

**Status:** plan + instructions only; 4k run and RGP captures have NOT been conducted as part of this commit. No C++ patch or rebuild required if diagnostic **b12100** from the successful 1024 \`hosttrace-on\` run is still available.

## Background and caution

The successful 2026-11-06 1024-token host trace recorded 12 \`MASK_OPT\` + 12 \`MAIN\` FA dispatches; the first pair was at **CPU-recorded dispatch ordinal 351/352**, and \`Qcur-19\` at **1619/1620**. There were 3879 CPU dispatch records overall. In contrast, RDP 3.5.0.18 successfully captured start1/count256 and start257/count16 but failed later windows on the short case, with no FA markers in those two successful captures. **These numbering systems have NOT been proved equivalent**; RDP captures also may fail when the target disconnects before the requested range completes.

The 4k corpus comes from the same Japanese novel source as the 1024 run; model is Unsloth IQ3_XXS PLE16 and UMA96GB, P-MODE Performance. \`GGML_VK_QSA_UNION=0\`, MTP OFF, native real-input llama-bench \`-p 4096 -c 8192 -b 2048 -ub 1024 -t4 -ngl 999 -fa auto -ctk f16 -ctv f16 -n0 -d0 -r1\` and \`--prompt-slice head\` with no warmup. The total PP may be subdivided into multiple physical 1024-token microbatches; **validate actual physical N/KV in logs**, do not assume every FA has N4096.

## A. Sync and local environment

\`\`\`powershell
cd C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag
git pull --ff-only

# Confirm this is the diagnostic worktree, not the main r6 checkout.
git branch --show-current
& '.\build-vulkan-ppdiag-rgp\bin\Release\llama-bench.exe' --version
Get-FileHash '.\build-vulkan-ppdiag-rgp\bin\Release\llama-bench.exe' -Algorithm SHA256

# Reuse existing ignored tools\evox2\benchmark\configs\local.psd1.
# Ensure Builds.R6PpFaRgpVulkan maps to the b12100 diagnostic Vulkan bin,
# Models.UnslothPle16 to IQ3 PLE16, and UmaLabel to '96GB'.
\`\`\`

The plan is \`tools\evox2\benchmark\configs\qwen38-r6-pp-fa-rgp-gate1-4k-20261106.psd1\`. \`local.psd1\` is not committed.

## B. Preflight without GPU execution

\`\`\`powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-pp-fa-rgp-gate1-4k-20261106.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
\`\`\`

Check exactly 2 variants, same build/model/input, context8192, PP4096, UBatch1024, generation0.

## C. Run 1 — host dispatch trace ONLY, without Radeon Developer Panel

\`\`\`powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant hosttrace-4k -StopOnError
\`\`\`

Inspect \`stderr.log\` for:
- \`ggml_vulkan: FA host dispatch trace enabled\`;
- \`evox2_vk_graph_dispatch_v1 state=begin/end ...\`;
- \`evox2_vk_fa_dispatch_v1 ... stage=MASK_OPT/MAIN ... cpu_dispatch_ordinal= ... KV=... N=...\`.
- The implementation caps output to **128 FA events**. If truncation is reported, do not treat missing later layers as no FA; use the initial events for calibration.

RGP **must not** be running/recording during this run because the extra stderr logging is diagnostic.

## D. RDP (Vulkan) settings for initial 4k capture

Prepare the RDP **Profiling** target **before** launching the next \`llama-bench.exe\`, and ensure the recognized process path is the b12100 diagnostic bin.

| Setting | Initial value |
|---|---|
| Graphics API / process | Vulkan / \`llama-bench.exe\` in \`build-vulkan-ppdiag-rgp\bin\Release\` |
| Auto capture mode | **Dispatch range** |
| Dispatch start index | **321** (heuristic candidate, not yet calibrated) |
| Dispatch count | **64** |
| Capture delay | **0 / disabled** |
| SQTT buffer | **High** |
| Collect counters | **OFF** |
| Instruction tracing | **OFF** |
| Shader instrumentation | **OFF** |
| Trigger | Automatic for target process; RDP capture profile output path must exist/be writable |

These values are intended to bracket the first CPU FA recorded at 351/352 **if** RDP RenderOp indexing is approximately aligned. The mapping is NOT established. The longer 4k run gives more opportunity for the selected window to complete than 1024.

Only if this first capture fails: examine RDP Output log for \`Successfully requested trace\`, \`Successfully collected and dumped trace\` or \`Profiling capture failed\`. To confirm RDP operation in the 4k run without depending on a late index, a **single fallback** \`start=1, count=256\` is reasonable (this window succeeded at 1024). Do not continue blindly increasing indices or count; report the logs.

## E. Run 2 — marker-only, with RDP armed

\`\`\`powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant rgp-markers-4k -StopOnError
\`\`\`

The run should emit \`FA RGP markers enabled\` but **not** \`FA host dispatch trace enabled\`. RGP → **Events → Event timing**, enable group by user events, clear any filter and then find \`EVOX2_FA_\`, \`MASK_OPT\`, \`flash_attn_f32_f16_aligned_cm1\`. Capture a screenshot showing at least one nested FA GPU event label, its \`KV\`, \`N\`, \`q\`, \`shader\` and workgroups.

**Do not confuse CPU ordinal with RDP start index, or CPU source-level event time with RGP GPU duration.** For RGP labels to be considered validated, the RGP event tree must show an actual \`EVOX2_FA_\` user event. A successful \`.rgp\` that only contains other user events is an exploratory capture, not a PASS of this last gate.

## F. Return evidence

Provide: (1) new \`hosttrace-4k\` benchmark ZIP (run + summary), (2) \`rgp-markers-4k\` ZIP, (3) generated \`.rgp\` if reasonably sized (or screenshot + RDP log for failed capture), (4) actual RDP start/count. Include the unchanged binary identity if a new build was unexpectedly used.

**Stop** on DeviceLost, Win 0x141/TDR, OOM, marked sustained paging, driver reset or missing intended Vulkan backend. RDP capture changes GPU clocks; neither run should overwrite clean baseline metrics.
