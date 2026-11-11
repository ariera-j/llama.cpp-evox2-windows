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


## 2026-11-11 follow-up: band12 / layer31 captured

User screenshot of `llama-cli-20261111-135305683.rgp` confirms RDP HIP **start405000/count512** returned `evox2_hip_fa_survey_kv_band<12>()` at **Event499** (0.297us). RGP reports **10240 total threads**; with 64 threads/block, grid X=160; 160-129=**layer31**. Band12 is KV **[49152,53248)**. This is not yet exact KV49152 or layer19. The nearby FA Event501 is **60460.161us** and following CmdBarrier Event502 is **10842.386us** (causal meaning and GPU-idle attribution not established).

Next search probe: start**403000**, count512, unchanged survey binary/model/input, to find band12 layer19. This is a heuristic probe, not a fixed offset. Use marker's band + grid X to adjust. If exact band12/layer19 is found, move to the selective anchor and later marker-OFF clean RGP to measure timing. Keep GPU idle/barrier cause inquiry deferred separately.


## 2026-11-11: start403000 captured band12 / layer7 (range narrowed)

Screenshot of `llama-cli-20261111-152111785.rgp`, HIP, survey, RDP Dispatch start403000 count512: Event407 `evox2_hip_fa_survey_kv_band<12>`, GPU duration 0.358us; 8704 threads at 64 threads/block = 136 X workgroups; 136-129=**layer7**. Adjacent Event409 FA `flash_attn_ext_f16`=60177.043us and Event410 `CmdBarrier`=10612.167us. Band12=KV [49152,53248), not an exact 512-token batch.

Earlier start405000 showed band12/layer31, so target band12/layer19 is plausibly between the two captured positions. Next survey probe **start404000/count512**, a heuristic interpolation. Check marker band and grid per capture, do not reuse Event IDs across captures.

Overview shows **GPU idle 0.26% / GPU bound**, with no conspicuous GPU-wide idle stretch in the user's occupancy/system activity screenshots even though an ~10.6ms CmdBarrier exists. Barrier elapsed duration does not directly measure full-GPU inactivity; separate idle investigation deferred.


## 2026-11-11: start404000 verified band12 / layer19 (survey location gate PASS)

The user supplied RGP screenshots from `llama-cli-20261111-162802120.rgp`, HIP, survey variant, RDP Dispatch start=404000 and count=512:

- Event **453**: `evox2_hip_fa_survey::evox2_hip_fa_survey_kv_band<12>()`, duration **0.337us**. Total threads **9472**, divided by 64 threads/block = **148 workgroups**; workgroups X minus 129 = **layer19**.
- Event **455**: `flash_attn_ext_f16`, **59846.840us**. Event **456**: `CmdBarrier()`, **10639.969us**.
- **band12 corresponds to KV [49152,53248)**. Neither this special marker nor its layer grid encodes the *exact* 512-token KV position. Do not call this a verified exact KV49152 capture.
- Prior survey captures of the same region had band12/layer7 at start403000 and band12/layer31 at start405000. The interpolation established a useful location for this instrumented CLI build.
- Survey marker names and grid values are now **verified in RGP for the intended band/layer**. Additional survey-start probing is not needed for this gate.

**Proceed without another run first:** open the existing `start404000` RGP and inspect Events after the layer19 FA (Event455), especially `mm_ids_helper`, `quantize_mmq_q8_1`, `mul_mat_q<iq2_s,16>`, `mul_mat_q<iq4_nl,16>`, and the subsequent MoE reduction. Capture names and durations only if present in the same valid SQTT window. This verifies MoE coverage/operation ordering, not unbiased clean timings.

For exact KV49152 and uncontaminated GPU time, the next measurement gate remains **separate**: narrow `rgp-anchor` (GPU anchor at exact KV plus layer), then `rgp-clean` for kernel timings. Both variants alter global dispatch numbering relative to survey, so recalculate the RDP window and verify by independent event-sequence matching. Do not assume that start404000 in the non-survey run captures layer19.

More detailed logged result: [research results](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/RESULTS.md).



## 2026-11-11: narrowed anchor-only capture missed - use combined survey+anchor

User's HIP `llama-cli-20261111-190427633.rgp` was captured at **start403500/count512**, with exactly three `evox2_hip_anchor_moe_layer19` Event275/283/293 and three `evox2_hip_anchor_moe_layer23` Event961/969/979. The same capture contained two FA kernels, but **no `evox2_hip_anchor_fa_layer19`**. The three MoE markers are Gate/Up/Down **per layer, not evidence for three separate ubatches**. MoE has no KV filter, whereas FA anchor is only emitted when the caller's KV equals49152.

The subsequent **start400000/count512** anchor-only capture contained neither FA nor MoE anchor. The first-order subtraction of static dispatch counts was not accurate enough to predict the matching GPU window. No more uninformed start-index guessing.

Updated [CLI plan](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1) adds **rgp-survey-anchor** to all four jobs without touching C++ sources: GGML_HIP_RGP_FA_SURVEY=1, GGML_HIP_RGP_ANCHOR=1, GGML_HIP_RGP_ANCHOR_KV=49152, all host trace flags remain off. In the **same RGP run**, a band12 marker with gridX=148 identifies layer19 in KV49152..53247, while the adjacent `evox2_hip_anchor_fa_layer19` marks **exact KV49152**. The MoE anchors show the routed MMQ group.

**Recommended one-shot exploratory capture:** RDP HIP target llama-cli.exe, Dispatch range **start=404500/count1024**, SQTT High, counters/instruction tracing OFF, old IQ3 ub512. This is a *wide search window*, not a known target index. This is a deliberately broader exploratory window near previously observed survey and anchor regions, not a computed dispatch offset. **RGP Event IDs include barrier events and must not be added to RDP's Dispatch start index**; the number of added survey/MoE marker dispatches is also not a reliable offset under HIP Graph. Treat start404500/count1024 only as a location probe, and determine the true position from any captured survey band and grid. If RDP rejects count1024 or RGP SQTT resources fail, stop to choose a smaller verified window rather than assuming the event was captured.

~~~powershell
$diag = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq'
$main = 'C:\llama-build\llama.cpp-evox2-windows-r6'
Set-Location $diag
git pull --ff-only
$matrix = Join-Path $diag 'tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$local = Join-Path $main 'tools\evox2\benchmark\configs\local.psd1'
$plan = Join-Path $diag 'tools\evox2\benchmark\configs\qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1'
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey-anchor' -MaxRuns 1 -PlanOnly
# Only after checking exact job, model, input, build, flags and enabling RDP:
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey-anchor' -MaxRuns 1 -StopOnError
~~~

Interpretation: (1) band12+grid148 and immediate FA anchor implies exact layer19/KV49152; (2) band12+grid148 without FA exact anchor indicates some other KV within band12, or anchor not present in captured sequence; (3) any other band gives true search position; (4) no survey markers despite FA means inspect executable/plan/RDP rather than infer KV. Only **rgp-clean** marker-OFF profiling is suitable for evaluating MMQ/FA time. All source code is unchanged by this new combined plan mode, so **no rebuild** is needed. Do not copy the combined-mode start index into clean mode.


## 2026-11-11: combined capture had band12/layer19 + MoE, but not the exact-KV FA marker

From `llama-cli-20261111-193140056.rgp`, the **rgp-survey-anchor** variant with RDP start404500/count1024 yielded **Event621** `evox2_hip_fa_survey_kv_band<12>`; total threads9472 => gridX148 => **layer19**; next FA Event623 duration **59768.004us**. Layer19 MoE anchor kernels were **Event661/669/679** (three routed MMQ operations, not three ubatches). The exact `evox2_hip_anchor_fa_layer19` marker was not visible. This is consistent with a KV in band12 but **not exact KV49152**, or with the exact marker falling outside the limited capture; the screenshots cannot distinguish these cases. No `stderr.log`/binary RGP was provided to verify all source-level marker submissions in this specific run.

### Fine-grained survey enhancement

The portable header [evox2-hip-fa-survey.cuh](../../ggml/src/ggml-cuda/evox2-hip-fa-survey.cuh) now supports **optional 512-token sub-bands**, without replacing or reinterpreting the original 4096-token marker:

- `GGML_HIP_RGP_FA_SURVEY_FINE_BAND=12` selects the coarse band. Default unset disables all extra fine-marker dispatches.
- `GGML_HIP_RGP_FA_SURVEY_FINE_LAYER=19` optionally limits the additional marker to one layer (unset means any layer in the selected band).
- For a matching FA only, **one extra named GPU marker** `evox2_hip_fa_survey_kv_slot<0..7>` is launched after the coarse band marker, in the same HIP stream before the FA. Each slot covers **512 KV tokens** within the band. This does not add a new synchronization/readback or change real FA kernel args.
- At band12: slot0=KV49152..49663, slot1=49664..50175, ..., slot7=52736..53247. A slot marker identifies a **range**; `evox2_hip_anchor_fa_layer19` still provides the exact KV49152 check.
- GridX=129+layer is retained for both marker types. A selected slot marker therefore also reports 9472 total threads (148 workgroups) when layer19.
- The new `rgp-survey-fine` matrix variant enables coarse survey, fine band12/layer19, and the exact-KV FA/MoE anchors together. Other variants (`rgp-survey`, `rgp-survey-anchor`, `rgp-anchor`, `rgp-clean`, `host-trace`) retain their behavior. The header itself needs only `kv,n,layer,stream`; no GGUF/model naming dependency was introduced.

### Next RGP gate: rebuild and capture one fine-marked window

The `.cuh` source changed, so **a Windows HIP rebuild is mandatory**; `git pull` by itself is insufficient. Earlier RGP binaries do not emit any `kv_slot` kernel. On the already configured Windows worktree:

~~~powershell
$diag = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq'
$main = 'C:\llama-build\llama.cpp-evox2-windows-r6'
Set-Location $diag
git status --short
git pull --ff-only
python -m unittest discover -s .\tools\evox2\tests -p 'test_rocm_mmq_host_trace.py' -v
.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-pp64k-mmq -BuildOnly -Parallel 4 -SkipSmoke
$bin = Join-Path $diag 'build-rocm-pp64k-mmq\bin\Release'
& (Join-Path $bin 'llama-cli.exe') --version
Get-FileHash (Join-Path $bin 'llama-cli.exe') -Algorithm SHA256
$matrix = Join-Path $diag 'tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$local = Join-Path $main 'tools\evox2\benchmark\configs\local.psd1'
$plan = Join-Path $diag 'tools\evox2\benchmark\configs\qwen38-r6-rocm-pp64k-iq3-iq4-mmq-cli-20261110.psd1'
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey-fine' -MaxRuns 1 -PlanOnly
~~~

RDP: HIP `llama-cli.exe`, auto capture Dispatch range **start404500/count1024**, SQTT High, shader instrumentation/counters OFF. This is **only a first exploration window** anchored to the preceding combined-mode capture; new fine-marker dispatches can shift absolute indices. After arming RDP:

~~~powershell
& $matrix -Plan $plan -LocalConfig $local -OnlyJob 'pp64k-oldiq3-ub512' -OnlyVariant 'rgp-survey-fine' -MaxRuns 1 -StopOnError
~~~

Inspect the RGP Event filter `evox2`: the coarse `kv_band<12>` and **adjacent** `kv_slot<N>` with total threads 9472 identify the specific 512-token position at layer19. If slot0 and `evox2_hip_anchor_fa_layer19` both appear, **exact KV49152 is verified**; if only slot1..7 appears, use the slot number to determine where to move the capture and stop trying uncalibrated offsets. The host `evox2_hip_fa_survey_fine_v1` lines also record exact KV but are not RGP Event IDs. Keep existing b12013/b12038 speed baselines frozen. `rgp-survey-fine` timing and PP throughput are instrumentation-heavy and cannot serve as the baseline; use `rgp-clean` in a separate run after locating a matched region.

Native rebuild, Python tests, and RGP marker visibility for **this new fine mode** are currently **NOT verified**.


## 2026-11-11: fine survey slot2 observed at band12 layer19

User RGP screenshot `llama-cli-20261111-194656970.rgp`, HIP `rgp-survey-fine`, RDP start404500/count1024, shows Event625 coarse `evox2_hip_fa_survey_kv_band<12>` and Event627 fine `evox2_hip_fa_survey_kv_slot<2>`, **layer19** (9472 threads /64=148 blocks, 148-129=19). The fine marker conclusively establishes **KV subrange [50176,50688)** at this particular FA, not exact KV50176. The goal is slot0 [49152,49664), two 512-token sub-bands earlier. No `evox2_hip_anchor_fa_layer19` exact-KV49152 marker was visible in this window, consistent with the later KV location.

Neighboring Event629 FA took 60003.634us, Event630 barrier 10603.584us. Layer19 MoE markers Event667/675/685 indicate Gate/Up/Down work in this same captured block.

**More efficient alternative for the actual MMQ J16/J32 comparison:** slot2 begins at **KV50176 = 49 × 1024**, an exact 1024-token alignment. Thus old IQ3 ub512 **slot2 KV50176..50687 + slot3 KV50688..51199** can be compared with ub1024 **KV50176..51199** without necessarily locating exact KV49152. This changes the target KV (and FA context) by 1024 tokens from the earlier host FA anchor, so retain that distinction; the measured host FA suffix_scan state at KV49152 does not automatically transfer. A coarse/fine marker reveals the 512-token *range*, not an exact integer KV; exact verification via host trace or a retargeted FA anchor should be considered if needed. First ensure that both ub512 slots and the corresponding ub1024 group have identifiable layer19 MMQ Gate/Up/Down and reduction, then capture clean GPU timings. Avoid additional searches solely to force KV49152 unless comparison with that exact previous FA point is required.

**Optional probe to reach the original KV49152 reference**: RDP **start396500/count1024**, same `rgp-survey-fine` model and binary (no rebuild). This is **a rough estimate only**, based on earlier survey-only captures suggesting about 1000 dispatches per 12 layers, and 48-layer ubatch ~4000 dispatch; moving two ubatches backward might require ~8000 dispatches. Different modes, HIP Graph behavior and marker overhead invalidate direct transfer of these numbers: do **not** interpret 396500 as a verified exact global offset. Inspect any coarse band and fine slot obtained; if slot0 appears, also look for the exact FA anchor in the same local sequence. If the window lacks a survey marker, reconsider the coordinate estimate before taking repeated long runs.

The source survey's portability and 512-token specialization are now demonstrated by RGP for slot2; exact KV49152 validation and clean RGP timing remain pending.
