# ROCm PP inversion 64k: HIP MMQ host trace and llama-cli

**2026-11-10: source committed, Windows native compile / GPU execution / RGP not yet verified.**

Branch: [investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110)

Parent branch: investigation/r6-rocm-pp-fa-trace-20261107. The parent already includes a host-only, default-OFF FA KV/layer trace. The default-OFF MMQ host trace does not change model kernels or introduce synchronization. An independent default-OFF RGP-anchor variant reuses the previously GPU-verified HIP marker kernels. It deliberately inserts extra marker dispatches only when enabled.

## Motivation

ROCm b12013 with identical MH-Hard 110k input: old IQ3 PP ub512=296.48 vs ub1024=326.13 tok/s; old IQ4 ub512=319.02 vs ub1024=312.74 tok/s. The older 64k llama-bench code input also showed the same inversion. We now use llama-cli to inspect host trace and generated output, with a frozen line-aligned ~64k-code prefix, without extending the 110k prompt processing time.

### New feature

- ggml/src/ggml-cuda/mmq.cu implements **GGML_HIP_MMQ_TRACE=1**. When enabled, it emits host MMQ call ordinal, selected tile width J, weight type, tensor shapes/names, layer (from blk.N), logical physical token count N, and routed MoE versus dense.
- Optional GGML_HIP_MMQ_TRACE_LAYER=19 and GGML_HIP_MMQ_TRACE_N=512 or 1024 narrow output. At most 2048 matched events per process.
- Existing ggml/src/ggml-cuda/fattn.cu uses GGML_HIP_FA_TRACE=1, GGML_HIP_FA_TRACE_KV=49152 and GGML_HIP_FA_TRACE_LAYER=19 to supply a host-side FA KV anchor.
- The **host-trace** mode has no GPU readback, new kernel or synchronization. The **rgp-anchor** mode launches previously validated same-stream layer19/23 marker kernels (128 blocks x 64 threads) before FA at filtered KV and before routed MoE MMQ at ub512 or ub1024. Their extra dispatches can perturb GPU execution; they are only for locating the relevant RGP region.
- Three variants per job: **host-trace** (host metadata only), **rgp-anchor** (GPU-visible marker kernels, host metadata flags OFF), and **rgp-clean** (no trace or marker). HIP RGP cannot display Vulkan VK_EXT_debug_utils labels; it **can** show the distinguishable GPU marker-kernel names from the previous successfully tested HIP anchor gate. Host IDs are not GPU dispatch/Event IDs. See [previous validated HIP anchor results](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-rocm-rgp-moe-layer-tags-20261107/docs/evox2/R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md).
- GGML_HIP_MMQ_TRACE captures only the MMQ branch, not alternative MMF/cublas or non-MMQ kernels.

## Files

- [MMQ source](../../ggml/src/ggml-cuda/mmq.cu)
- [64k prefix preparer](../../tools/evox2/benchmark/prepare-code-64k-cli-prompt.py)
- [CLI plan](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1)
- [Static contract tests](../../tools/evox2/tests/test_rocm_mmq_host_trace.py)
- [Older MMQ source audit](R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md)

## 1. Isolated Windows build

Requires existing EVO-X2 TheRock ROCm 10.0.0 environment, UMA96GB / Performance P-MODE. Use a separate worktree and build folder; do not replace frozen b12013/b12038 executables. **Do not run -RunBackendTest** (previous reset risk).

~~~powershell
$main = 'C:\llama-build\llama.cpp-evox2-windows-r6'
$diag = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq'
$branch = 'investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110'
Set-Location $main
git fetch origin
git worktree add $diag "origin/$branch"
Set-Location $diag
git log -1 --oneline

python -m unittest discover -s .\tools\evox2\tests -p 'test_rocm_mmq_host_trace.py' -v

.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-pp64k-mmq -Parallel 4 -SkipSmoke -ExtraTargets @('llama-tokenize')

$bin = Join-Path $diag 'build-rocm-pp64k-mmq\bin\Release'
& "$bin\llama-cli.exe" --version
& "$bin\llama-tokenize.exe" --help
Get-FileHash "$bin\llama-cli.exe" -Algorithm SHA256
~~~

If the worktree is already present, inspect git worktree list before proceeding. Keep the binary/runtime SHA from the build. Passing the static test does NOT establish that Windows ROCm compilation succeeded.

## 2. Freeze the common 64k code input once

The original source is the 64k llama-bench corpus, but the earlier benchmark used an internal tokenizer head slice. Do **not** pass the entire 1.86M-token code corpus directly to llama-cli -f and rely on automatic truncation: a common, verified text prefix is needed.

The helper runs llama-tokenize in vocab-only mode and binary-searches the number of **complete UTF-8 source lines** that fit within 61777 raw no-BOS tokens, leaving margin for chat template and output. It records source SHA, generated-file SHA, prefix lines and raw token count. It refuses to overwrite the frozen file. Since it cuts by complete lines and llama-cli adds a chat template, it is **not byte-identical** to the old llama-bench 61777-token head slice. Compare the new CLI runs only against **the same** new fixture.

~~~powershell
$code = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
$expectedCodeSha = '249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4aace95717b345'
if ((Get-FileHash -LiteralPath $code -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedCodeSha) { throw 'Original code SHA differs' }

$local = Join-Path $main 'tools\evox2\benchmark\configs\local.psd1'
$cfg = Import-PowerShellDataFile -LiteralPath $local
$model = [string] $cfg.Models.MHHOldIQ3.Path
$input = 'C:\pp-rgp\qwen38-code-64k-20261110.prompt.txt'
python (Join-Path $diag 'tools\evox2\benchmark\prepare-code-64k-cli-prompt.py') --source $code --tokenizer (Join-Path $bin 'llama-tokenize.exe') --model $model --out $input --max-tokens 61777
Get-Content "$input.meta.json"
~~~

Register the following aliases INSIDE existing ignored config tables in $local (do not overwrite Builds/Inputs, MHHOldIQ3 or MHHOldIQ4):

~~~powershell
# Builds = @{ ... }:
R6RocmPp64kMmqTrace = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq\build-rocm-pp64k-mmq\bin\Release'
    ExpectedBackend = 'ROCm'
}
# Inputs = @{ ... }:
PPCode64kRgp = 'C:\pp-rgp\qwen38-code-64k-20261110.prompt.txt'
~~~

## 3. Host-only trace: old IQ3, ub512/1024, 2 runs

~~~powershell
$matrix = Join-Path $diag 'tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$plan = Join-Path $diag 'tools\evox2\benchmark\configs\qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1'

& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-*' -OnlyVariant 'host-trace' -MaxRuns 2 -PlanOnly
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-*' -OnlyVariant 'host-trace' -MaxRuns 2 -StopOnError
~~~

Expected: exactly old IQ3 ub512 and ub1024, ctx65536, -b2048, 256 generated tokens, f16 KV, MTP/Gather OFF, no prompt cache, same original GGUF and frozen input SHA. Check result.json/conditions.json for Status OK, PromptTokens below ctx65536, truncated=0, GPU offload, backend ROCm and expected diagnostic executable/runtime.

Check stderr.log for **evox2_hip_mmq_trace_v1** layer=19, N=512 or 1024, moe=1 and tile J. Check **evox2_hip_fa_trace_v1** KV=49152 layer=19. If the FA target is absent, remove only the KV filter for a short HOST-trace diagnostic and inspect the actual KV. If MMQ is absent, inspect kernel path and layer/name assumptions; do not infer zero MMQ work.

Printed host lines provide prefill activity information; the CLI output and generation are preserved by Measure-LlamaCli. They do not provide a guaranteed real-time progress percentage or an exact RGP GPU-dispatch ordinal.

## 4. HIP RGP: old IQ3, location anchor first, clean timing second

~~~powershell
# First: anchored location scan, not throughput data.
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-anchor' -MaxRuns 1 -PlanOnly
# Arm RDP HIP capture first.
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-anchor' -MaxRuns 1 -StopOnError

# Then: separate no-anchor RGP time capture.
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-clean' -MaxRuns 1 -PlanOnly
# First arm Radeon Developer Panel: API HIP, target llama-cli.exe,
# capture mode Dispatch range, SQTT High, bounded count (initially 512).
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-clean' -MaxRuns 1 -StopOnError
~~~

Calibrate the start index for this **CLI diagnostic binary** in the anchored variant. Find evox2_hip_anchor_fa_layer19 at KV49152 (the stderr anchor log confirms KV when launched) and the subsequent evox2_hip_anchor_moe_layer19 markers alongside quantize / mm_ids_helper / mul_mat_q. Their names are separate GPU dispatch kernels, NOT HIP user-event strings. The previous successful HIP study captured these markers around RDP starts 197240 / 197540, but those offsets belong to a different llama-bench binary and are NOT portable to this CLI build. Once you know the nearby kernel sequence, capture the **rgp-clean** variant to measure without extra marker kernels; offsets will shift when markers are removed, so realign by the neighboring GPU kernel sequence, not by copying Event IDs. If alignment remains ambiguous, document as exploratory and stop.

After a useful first capture, repeat the rgp-clean variant for old IQ3 ub1024. When comparing the physical region 49152..50175, use **two ub512 microbatches versus one ub1024 microbatch**, not one of each. Add old IQ4 only when the IQ3 local kernel difference identifies a plausible candidate.

## 5. Safety and interpretation

- HIP marker **kernels** are visible as named RGP dispatches, not as Vulkan debug-utils user-event labels. Only the rgp-anchor variant inserts them; the rgp-clean variant has no markers.
- Host trace adds CPU logging; rgp-anchor additionally adds 128x64-thread GPU dispatches, which can affect graph capture/replay and timings. RGP itself perturbs timings. Do not put host-trace/RGP-on PP tok/s into ordinary speed baselines; retain previous uninstrumented figures.
- A profile can include FA/QSA/MMQ/kernel waits but never proves a full-PP explanation from one isolated kernel.
- Stop on OOM, TDR, driver reset, model fallback to CPU, heavy sustained paging, input SHA mismatch, truncated input, or an unverified binary.
- Large ZIP/RGP/model/prompt data remain off Git. Store results and hashes under the dedicated experiment folder in evox2-llm-experiments.
