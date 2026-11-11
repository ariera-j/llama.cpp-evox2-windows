# HIP FA RGP survey - portable KV-band location markers

**Status (2026-11-11): implemented; first Windows HIP RGP survey marker visualized at band11/layer47. Exact target band12/layer19 alignment still pending.** Survey-only instrumentation, not a speed optimization.

## Background and objective

Previous old-IQ3 ub512 llama-cli 64k RGP windows at start=386000, 390000, and 394000 (512 dispatches each) contained FA events but not the very selective layer19/23, KV49152 anchor kernels. The run log had confirmed the FA anchor launch requests. Guessing more global dispatch indices is not an efficient way to find the desired KV.

The independent environment flag GGML_HIP_RGP_FA_SURVEY=1 now inserts **one named HIP GPU marker immediately before every FA host submission**, for every KV length and layer, including partial batches. The feature is **default OFF** and does not introduce GPU synchronization, readback, or tensor mutations. It is **not** a Vulkan debug-utils marker: RGP shows its own kernel dispatch instead.

## Self-contained implementation and porting

- [evox2-hip-fa-survey.cuh](../../ggml/src/ggml-cuda/evox2-hip-fa-survey.cuh) owns the HIP kernel symbols, band/grid encoding, opt-in flag, and rate-limited host summary. It has no ggml_tensor types, Qcur assumptions, or model-specific dependencies.
- [fattn.cu integration](../../ggml/src/ggml-cuda/fattn.cu) adds only an include and a guarded call before the actual FA kernel. It extracts KV, N and layer from the existing ggml metadata. To port to another model or engine, change only this adapter.
- [CLI matrix](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1) offers a separate rgp-survey variant for each of the existing four jobs; host-trace, rgp-anchor and rgp-clean remain.

Minimal integration in a HIP caller:

~~~cpp
#if defined(GGML_USE_HIP)
#include "evox2-hip-fa-survey.cuh"
#endif

// With a valid HIP-compatible stream and FA metadata:
#if defined(GGML_USE_HIP)
if (evox2_hip_fa_survey::enabled()) {
    evox2_hip_fa_survey::submit(kv_tokens, query_tokens, layer_index, stream);
}
#endif
~~~

Inputs: kv_tokens and query_tokens are int64_t; layer_index is long (-1 when unknown); stream is cudaStream_t in llama.cpp's HIP/CUDA-compatible backend. The port supplies its own layer extraction. The header assumes an existing CUDA_CHECK macro and the HIP compiler launch syntax. No CMake source registration is needed since it is a header-only feature. Suitable for copying between llama.cpp HIP investigation branches; other engines need a matching stream and error-check adapter.

## RGP decoding rules

Marker kernel symbol: evox2_hip_fa_survey_kv_band<N>, where N = floor(KV / 4096).

- Each band covers a half-open range from N*4096 to (N+1)*4096 - 1, in token positions.
- Specializations 0..64 cover KV from 0 to 262144. Larger KV uses evox2_hip_fa_survey_kv_overflow, not a misleading final band.
- The **layer** is encoded into the HIP launch workgroup/grid dimension: grid_blocks_x = 129 + layer for known layer 0..126. grid_blocks_x=128 means layer unavailable. If RGP displays total work-items instead of workgroups, divide the total X thread count by 64 first.
- Example: evox2_hip_fa_survey_kv_band<12>, grid blocks X=148 means **KV49152..53247, layer19**. X=152 means layer23. Band-only identification does **not** resolve exact KV within 4096 tokens.
- A short different-length AMD s_nop sequence per template specialization prevents identical instruction bodies from being mistaken for the same specialization. This is diagnostic and can add profiling overhead.

Only on entering a new KV band the host writes a summary like:
~~~text
evox2_hip_fa_survey_v1 band=12 band_tokens=4096 KV=49152 N=512 layer=0 grid_blocks=129 note=host_submission_not_RGP_event
~~~
This is a **host submission log**, not a GPU dispatch ordinal or an exact source for an individual RGP Event ID. A real GPU marker symbol visible in the Events timeline verifies the dispatch location.

The FA kernel follows the marker in the same HIP stream. HIP Graph capture/replay or additional graph operations can change event timing/order; verify adjacency in each run. The survey adds many GPU dispatches and is **for finding a region only**. Do not interpret its PP throughput as normal speed, and do not use marker-on GPU timings as unbiased MMQ/FA timings.

## Rebuild the existing diagnostic checkout

The old b12165 executable does not contain this feature. On the EVO-X2, activate the already validated TheRock ROCm SDK 10.0.0 environment. Use the existing worktree and build directory, but keep b12013/b12038 frozen builds untouched.

~~~powershell
$diag = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq'
$main = 'C:\llama-build\llama.cpp-evox2-windows-r6'
Set-Location $diag
git status --short
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_rocm_mmq_host_trace.py' -v

.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-pp64k-mmq -BuildOnly -Parallel 4 -SkipSmoke

$bin = Join-Path $diag 'build-rocm-pp64k-mmq\bin\Release'
& "$bin\llama-cli.exe" --version
Get-FileHash -LiteralPath "$bin\llama-cli.exe" -Algorithm SHA256

$matrix = Join-Path $diag 'tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$local = Join-Path $main 'tools\evox2\benchmark\configs\local.psd1'
$plan = Join-Path $diag 'tools\evox2\benchmark\configs\qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1'

& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey' -MaxRuns 1 -PlanOnly
~~~

Review the PlanOnly output before executing. It must say **one old-IQ3, ub512, code 64k, ctx65536, new diagnostic build, rgp-survey**. The local config already contains the frozen prompt alias PPCode64kRgp and new build alias R6RocmPp64kMmqTrace from the previous host-trace gate.

## Capture one survey

Radeon Developer Panel: API HIP, target llama-cli.exe, Dispatch range **count512**, SQTT High, shader counters and instruction tracing OFF.

**Start 390000 is a reasonable first survey attempt** solely because a previous *non-survey* capture there showed actual FA kernels. Survey inserts a new marker before every FA, so the absolute dispatch number can shift; 390000 is NOT an established KV estimate.

After arming capture:

~~~powershell
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey' -MaxRuns 1 -StopOnError
~~~

Search RGP Event timing for evox2_hip_fa_survey (or just survey). **Report the band numbers and grid-X blocks** of at least one captured marker, plus its next FA. If a marker is band12, use grid=148 to identify layer19 and look for near-by MMQ Gate/Up/Down. If a different band appears, that is valuable location data even when it is not the target band. Do not guess KV from the prior dispatch index.

If the new ZIP has evox2_hip_fa_survey_v1 entries but a captured window has FA and no named survey markers, verify new executable SHA/branch and HIP graph capture behavior first rather than guessing more starts.

Once the KV/layer window is located, use the existing narrower rgp-anchor mode to confirm KV49152 and **rgp-clean** (no added marker dispatches) for GPU kernel times. The clean capture will have different dispatch indices, so match by neighboring kernel sequence rather than reusing survey Event IDs.

## Validation requirements and limitations

1. Static unit tests for default-OFF, range mapping, portable adapter and no sync/readback.
2. Windows TheRock ROCm native build and llama-cli --version; record binary/source/runtime SHA.
3. One survey run: Status OK, no truncation, frozen input identity, band host logs; confirm **RGP actually displays** a named survey kernel. Previous marker visibility was established in a different diagnostic build and does not automatically validate this new one.
4. Only after location mapping, compare a matched 1024-token region (two ub512 batches versus one ub1024) using separate marker-OFF RGP captures.

Store bulky RGP/ZIP files outside Git. Do not merge this instrumentation branch into main for normal deployment.


## 2026-11-11 native RGP result: first survey marker visible

**First GPU-visible marker PASS.** Based on user screenshots from llama-cli-20261111-132944141.rgp, HIP / Radeon GPU Profiler 2.7.0.32, RDP Dispatch start390000 count512. This confirms one marker visualization, NOT precise band12/layer19 alignment.

- Event531: evox2_hip_fa_survey::evox2_hip_fa_survey_kv_band<11>(), GPU duration 0.328us.
- Event531 total threads=11264. At 64 threads/block, grid X=176; survey layer =176-129=**47**.
- Band11 represents KV [45056,49152), not the exact KV or an individual microbatch.
- Event532 CmdBarrier was immediately followed by Event533 flash_attn_ext_f16 taking 58213.388us (~58.213ms).
- Event534 CmdBarrier took 10618.542us (~10.619ms). Wavefront occupancy dropped nearby. Overview reports GPU idle=1.80%, profile duration=219559.674us, and GPU bound.
- Official RGP documentation distinguishes queue-based GPU idle from SQTT shader wavefront occupancy. HIP CmdBarrier is driver scheduling/dependency instrumentation and is not proof of explicit hipStreamSynchronize or a GPU-wide idle interval. Do not equate barrier duration with fully idle GPU duration.

**Next targeted exploration:** one rgp-survey capture at start405000/count512 to inspect band and layer. This is a search point, not a guaranteed band12 location. If still band11, move forward; if band13, backward; if band12, grid X=148 identifies layer19. Validate exact KV49152 separately via the existing narrower anchor and/or host FA metadata. Use marker-free rgp-clean for performance timings; the survey adds a kernel before every FA.

Screenshot-derived details and idle/barrier follow-up are stored in the [experiment report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-rgp-survey-kv-band11-and-barrier-observation.md).
