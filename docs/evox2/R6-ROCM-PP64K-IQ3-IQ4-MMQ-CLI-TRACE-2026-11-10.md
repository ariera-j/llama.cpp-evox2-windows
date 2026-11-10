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
git worktree add -b $branch $diag "origin/$branch"
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
$promptFile = 'C:\pp-rgp\qwen38-code-64k-20261110.prompt.txt'
python (Join-Path $diag 'tools\evox2\benchmark\prepare-code-64k-cli-prompt.py') --source $code --tokenizer (Join-Path $bin 'llama-tokenize.exe') --model $model --out $promptFile --max-tokens 61777
Get-Content "$promptFile.meta.json"
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


## 2026-11-11: Windows native Gate A PASS (old IQ3 ub512/1024 host trace)

Received two-run ZIP `20261111-003942-051-cli-rocm-b12165-ctx65536-a75ae1fb0c8f.zip`, SHA256 `d1a81c0b49b004570d7facf5b217bf3e8f7c721f5d01a8883e525ea4f503aa47`. Both runs used ROCm b12165, source `ba1ccc53a3182fdb92e811334bcc0baf51286906`, executable SHA `51f065c25e9ac504261a81d07866daf99a9dff6054abe73daebe829f516eb2da`, runtime artifact **Verified** / digest `137c2d7d5967b07b541a0338c47f2e1bfcbd51d9839890b3bfbcf836cbc36e37`. Both are Status OK/ExitCode0. The user has therefore successfully **compiled and executed** the diagnostic on Windows ROCm; separate RGP marker visibility and GPU timings are not yet validated for this branch.

The two runs share the original old IQ3 PLE16 file path/size (GGUF full SHA not calculated), a new frozen code input `qwen38-code-64k-20261110.prompt.txt`, exact input SHA256 `a8289b8e6f5c2cabf0d85940874c3c80e39f4c1c879c3766f98f0b8946b26d9a`, real prompt **61788 tokens**, ctx65536, batch2048, MTP/Gather OFF, f16 KV, UMA96GB, Performance P-MODE unchanged. `truncated=0` in both. CLI generated 256 tokens and captured outputs. `GGML_HIP_RGP_ANCHOR=0`, so both are host-only, not GPU marker runs.

| Field | UBatch512 | UBatch1024 |
| --- | ---: | ---: |
| Run ID suffix | `a75ae1fb0c8f` | `bd065d714c5c` |
| PP tok/s (diagnostic ON) | **360.66** | **409.03** |
| Prompt eval milliseconds | 171318.99 | 151061.32 |
| TG tok/s | 21.75 | 21.87 |
| layer19 MMQ trace rows | **960 = 120 full ubatches x 8 ops** | **480 = 60 full ubatches x 8 ops** |
| MoE Gate/Up/Down J | **16/16/16** | **32/32/32** |
| Dense MMQ J | 128 | 128 |
| FA layer19 KV/N | 49152 / 512 | 49152 / 1024 |
| FA kernel | mma_f16 | mma_f16 |
| FA suffix_scan_candidate | **0** | **1** |
| high-load GPU VRAM clock mean MHz | 976.46 | 990.63 |

**Main finding:** MMQ J selection shifts 16 to 32 for three MoE weights at layer19. These correspond to `blk.19.ffn_gate_exps.weight` and `ffn_up_exps.weight` (iq2_s), and `ffn_down_exps.weight` (iq4_nl). Each selected J is consistent in all filtered full ubatches. All five remaining dense weight calls (q8_0) choose J128 in both configurations. Previous 64k b12038 RGP identified analogous IQ2_S and IQ4_NL `mul_mat_q` kernel specializations, but these new CLI runs have not yet measured GPU kernel duration. J selection may affect the work distribution and execution efficiency; it does not by itself establish the reason for the +13.41% PP throughput difference.

FA host metadata independently confirms layer19 at KV49152 (FA ids 1169/593, **host IDs not dispatch IDs**). `suffix_scan_candidate=0` at N512, `1` at N1024 is another path difference, not proof of a scan's executed duration. There is **no requirement to modify the diagnostic source** to proceed from Gate A on these logs. Both runs' high-GPU-load VRAM clock means differ by about +1.45% and available Windows RAM briefly approached zero; page-read telemetry is active. Clock, memory and other resource effects remain possible.

**Next Gate B:** start with only the old IQ3 ub512 `rgp-anchor` variant, one run, on the **same built b12165**. RDP HIP / `llama-cli.exe` / bounded Dispatch range, SQTT High; find named `evox2_hip_anchor_fa_layer19` at `KV=49152` and adjacent `evox2_hip_anchor_moe_layer19`, then `mul_mat_q<...16...>` Gate/Up/Down. Recalibrate dispatch start for CLI rather than copying older `llama-bench` starts. Run ub1024 after successful anchor visibility; compare two adjacent 512-token batches with one 1024-token batch covering the same 1024-token range. Use separate `rgp-clean` variants for GPU timing (anchors add dispatches and can perturb timings). If markers cannot be located in one or two bounded captures, stop and inspect RDP settings/host anchor lines rather than repeatedly guessing offsets.

Full measurements and provenance are archived in [experiment run report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-rocm-pp64k-oldiq3-hosttrace-ub512-1024.md).
