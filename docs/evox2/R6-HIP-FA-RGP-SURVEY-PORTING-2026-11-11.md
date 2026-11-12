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

**CORRECTED (KV is the K tensor's right-hand extent, NOT query starting offset):** A matched 1024-token query interval **positions49152..50175** needs old IQ3 ub512 **KV49664 N512 slot1 (positions49152..49663) + KV50176 N512 slot2 (positions49664..50175)** compared against ub1024 **KV50176 N1024 slot2 (positions49152..50175)**. The first earlier proposal (ub512 slot2 + slot3 and ub1024 slot2) was wrong. For standard contiguous full aligned microbatches, K length already includes the current query block; in non-contiguous contexts/padded shapes the tensor length may not uniquely fix the query positions. The earlier FA suffix_scan state at KV49152 does not automatically transfer. A coarse/fine marker reveals the 512-token *range*, not an exact integer KV; exact verification via host trace or a retargeted FA anchor should be considered if needed. First ensure that both ub512 slots and the corresponding ub1024 group have identifiable layer19 MMQ Gate/Up/Down and reduction, then capture clean GPU timings. Avoid additional searches solely to force KV49152 unless comparison with that exact previous FA point is required.

**Optional probe to reach the original KV49152 reference**: RDP **start396500/count1024**, same `rgp-survey-fine` model and binary (no rebuild). This is **a rough estimate only**, based on earlier survey-only captures suggesting about 1000 dispatches per 12 layers, and 48-layer ubatch ~4000 dispatch; moving two ubatches backward might require ~8000 dispatches. Different modes, HIP Graph behavior and marker overhead invalidate direct transfer of these numbers: do **not** interpret 396500 as a verified exact global offset. Inspect any coarse band and fine slot obtained; if slot0 appears, also look for the exact FA anchor in the same local sequence. If the window lacks a survey marker, reconsider the coordinate estimate before taking repeated long runs.

The source survey's portability and 512-token specialization are now demonstrated by RGP for slot2; exact KV49152 validation and clean RGP timing remain pending.


## 2026-11-11: b12188 IQ3 ub512 run ZIP validated, plan for ub1024

User provided `20261111-194328-204-cli-rocm-b12188-ctx65536-db84c4f27fa6.zip`, SHA256 `4dd7b4a979c1b04ea7b5656d1abc2a5c9f4e6c89ee991f326c43074e27780325`. The recorded `rgp-survey-fine` old IQ3 ub512 64k run was **OK**, no truncation, 61788 tokens, same fixed input SHA `a8289b8e6f5c2cabf0d85940874c3c80e39f4c1c879c3766f98f0b8946b26d9a`; code commit `832f0c5e7`, executable SHA `543bf88826a9fe362815a9503e3cdaeda041eb40e52aafbbe5e6d1c569dd15a5`, runtime verified. Host fine logs explicitly say `band=12 slot=2 KV=50176 N=512 layer=19` (also slots0..7 at KV49152..52736), confirming exact KV for the prior RGP slot2 event by cross-checking logs. The FA exact-KV49152 layer19/23 anchor host launch also logged; its presence in stderr does not imply it lies in the RGP capture. Diagnostic-on PP328.19 tok/s is not a clean baseline.

Next: unchanged binary, same input, **pp64k-oldiq3-ub1024 / rgp-survey-fine**, one run. First RDP exploratory capture **start202000,count1024**, HIP / SQTT High / counters and instruction tracing OFF. Start chosen loosely from ub512 at 404500 and older different-build ub1024 matched RGP near 197240; do not assume linear dispatch scaling or transfer Event IDs. Target layer19 survey coarse band12 and fine **slot2=KV50176**; ub1024 KV50176 N1024 covers the query positions49152..50175, aligned to ub512 KV49664/slot1 plus KV50176/slot2. The earlier slot2+slot3 mapping was incorrect. Find all three J32 MMQ GPU kernels and reduction if they are fully included in the SQTT region. If another band appears, adjust the next start based on observed band instead of guessing blindly. Eventually obtain marker-free `rgp-clean` captures for performance comparison. The current update changes only documentation, **no rebuild needed**.

## 2026-11-11: ub1024 survey start202000 captured layer31, not target layer19

Screenshot from `llama-cli-20261111-202629075.rgp`, RDP HIP, `rgp-survey-fine`, old IQ3, ub1024, start202000/count1024: **Event387** `evox2_hip_fa_survey_kv_band<12>` 0.344us, **total threads=10240**. As survey launches 64 threads/block, gridX=160, i.e. **layer31**, not layer19 (expected gridX=148 and total threads9472). Absence of `evox2_hip_anchor_moe_layer19` and fine `kv_slot<N>` is expected when capturing layer31; both are deliberately restricted to layer19 (or for MoE layer19/23). This capture is not evidence of broken anchor instrumentation.

Nearby RGP events: Event389 `flash_attn_mask_to_KV_max<16>` 101.050us; Event391 `flash_attn_ext_f16` 117248.419us; Event392 CmdBarrier 10239.438us. MoE MMQ: Event433 `mul_mat_q<ggml_type22,32>` 3789.023us, Event439 same 3858.895us, Event447 `mul_mat_q<ggml_type20,32>` 6878.323us; sum 15526.241us. Event449 `moe_weighted_reduction_f32` 1297.673us. These durations are **layer31 and N1024 with marker ON**, not comparable directly to old ub512 layer19/N512 MMQ10.265ms.

**Next single probe**: keep the existing model, diagnostic binary and `rgp-survey-fine` variant, RDP HIP/SQTT High, **start=201000,count=1024** (heuristic; no rebuild). This moves one 1000-dispatch step earlier because prior ub512 survey runs associated start403000/404000/405000 with band12 layers7/19/31, respectively. The ub1024 dispatch distribution can differ substantially; always decode the new capture's survey band and total threads before adjusting again. Target band12, gridX148 / total threads9472 (layer19), `kv_slot<2>` for K extent KV50176, where the 1024-token query block is positions49152..50175, three `mul_mat_q<...,32>` and reduction. Strict match of exact KV can be verified with run stderr if needed. Do not use RGP Event IDs as global dispatch offsets. GPU idle/barrier cause remains a separate deferred task.

## 2026-11-11: ub1024 exact KV49152 layer19 RGP anchors all visible

**RGP target-position gate PASS** at `start201000/count1024` using old IQ3 `rgp-survey-fine` (user RGP screenshots `llama-cli-20261111-203802887.rgp`). Unlike `start202000` (band12/layer31), the earlier window showed **Event317 coarse band12**, **Event319 fine slot0**, **Event321 `evox2_hip_anchor_fa_layer19`** in sequence, followed by **MoE markers Event363/371/381** and Gate/Up/Down MMQ **Event369/377/387**. The exact FA anchor additionally fixes **KV=49152, N1024, layer19**, not merely the 512-token slot0 band. The attached run ZIP `20261111-203457-055-cli-rocm-b12188-ctx65536-983efa20685d.zip`, SHA256 `b1896c57b7c61b3b42c630e0f1ece7f1bd760be5f1044abcd0952fce6b048679`, confirms `band=12 slot=0 KV=49152 N=1024 layer=19` and `evox2_hip_rgp_anchor_v1 kind=fa layer=19 KV=49152 N=1024` host launches. Status OK, same frozen code input SHA and old model, ROCm b12188/commit832f0c5e7, verified runtime.

MMQ GPU event durations: **J32 Gate IQ2_S 4086.137us, Up IQ2_S 4127.292us, Down IQ4_NL 7400.045us**; GPU event-time sum **15613.474us** for N1024, with `moe_weighted_reduction_f32` 1271.714us. FA Event325 was 117821.701us, post-FA barrier Event326 10073.011us; survey marker overhead and RGP perturbation remain, so no clean GPU speedup is established.

**Important comparison target:** existing ub512 GPU measurement was **slot2, exact KV50176, N512** (3 MMQ sum10264.692us). This ub1024 RGP capture is **slot0, KV49152**, so do not compare its sum as a paired throughput result. ZIP host log also records ub1024 `slot2 KV50176 N1024 layer19` in the same **execution**, but that location is outside the photographed RGP window. For a like-for-like 1024-token query region (positions49152..50175), **ub1024 slot2 KV50176** and **ub512 slot1 KV49664 + slot2 KV50176** are required. The previous ub512 slot2 at KV50176 captures only the later half, and the missing capture is **ub512 slot1**, not slot3. Then obtain matching marker-free `rgp-clean` captures.

For an exploratory **ub1024 slot2** region, try `start205000/count1024` only if another diagnostic-on capture is necessary: it is a heuristic extrapolation from the observed ub1024 band12/layer19 at start201000 and layer31 at start202000, not a confirmed global dispatch index. Read the survey slot and grid in the next RGP before adjusting. `rgp-clean` changes dispatch layout; start201000/205000 cannot be carried over without calibrating neighboring kernel sequences. No C++ change needed. Full [numeric report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-iq3-ub1024-rgp-exact-kv49152-layer19.md).


## 2026-11-11: ub1024 RGP start205000 captured slot2 / layer19 — paired token range corrected

The user submitted screenshots `llama-cli-20261111-205048935.rgp` and the successful b12188 ub1024 execution ZIP `20261111-204734-665-cli-rocm-b12188-ctx65536-983efa20685d.zip`, SHA256 `7e914138c604cb0541adad9d3c84f58db8d815309e2b9b984b260ba145263bf3`. RDP HIP start205000/count1024 showed **Event533 `kv_band<12>`, Event535 `kv_slot<2>`, layer19 (9472 total threads), Event539 FA=107970.800us**, and subsequent MoE MMQ Gate **Event583 IQ2_S J32=4180.587us**, Up **Event591 IQ2_S J32=4192.739us**, Down **Event601 IQ4_NL J32=7615.959us**, and reduction Event603=1277.590us. MMQ3 sum **15989.285us** (not entire MoE elapsed time). Run status OK, prompt61788 tokens, same frozen code input and model, runtime verified, stderr confirms `band=12 slot=2 KV=50176 N=1024 layer=19`.

**CRITICAL KV SEMANTICS CORRECTION:** the survey passes `k->ne[1]` (FA K extent), built from the KV cache's current `get_n_kv()` including the tokens in the active ubatch. **KV=50176 is therefore the exclusive end**, not the start, of the current contiguous block. For these aligned full batches: ub1024 KV50176/N1024 handles query positions49152..50175; ub512 KV50176/N512 handles positions49664..50175; ub512 KV49664/N512 handles positions49152..49663. To compare the same 1024 tokens, the **missing ub512 capture is slot1 / KV49664**, not slot3 / KV50688. The old plan "ub512 slot2+slot3" is superseded. See `src/llama-kv-cache.cpp::get_n_kv`, `src/llama-graph.cpp` and the portable FA survey's `submit(k->ne[1], q->ne[1], layer, ctx.stream())` call.

**Next optional single diagnostic capture:** old IQ3 ub512 `rgp-survey-fine`, initial RDP start**400500/count1024** (heuristic derived from prior slot2 start404500, ~4000 dispatch per 512-token batch; not a verified global offset), to catch band12/slot1/layer19 and its J16 Gate/Up/Down. Old ub512 slot2 and ub1024 slot2 are already measured, although survey/anchor ON timing cannot replace later marker-OFF `rgp-clean`. A clean RGP window needs its own dispatch location calibration, and without an anchor does not itself prove exact KV.

**Resource caveat:** ADLX monitoring shows high GPU usage/normal ~2880MHz GPU clock with VRAM clock at 800MHz for much of the run, moving toward 950–1000MHz around 20:50:52 local. RGP file timestamp is close to that transition, but there is no event-level cross-timestamp calibration. Track VRAM clock alongside subsequent PP and RGP comparisons. The pending GPU-idle/CmdBarrier causality remains a separate investigation.

Detailed numerical analysis: [experiment report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-iq3-ub1024-rgp-kv50176-j32-and-kv-range-correction.md).

## 2026-11-11: RGP ub512 slot1 captured; real 1024-token J16/J32 MMQ comparison complete

**RGP fine-survey alignment and matched 1024-token marker-on IQ3 MoE comparison PASS.** The missing old IQ3 **ub512 FA K extent KV49664 / N512 / slot1 / layer19** was captured in `llama-cli-20261111-212440046.rgp` at **RDP start400500/count1024**. Event437 coarse `kv_band<12>` and Event439 `kv_slot<1>` (RGP **9472 total threads** → 148 workgroups → layer19) precede FA Event441=56554.591us. Three MoE anchors Event479/487/497 and MMQ Gate **Event485 IQ2_S/J16=3191.040us**, Up **Event493 IQ2_S/J16=3172.109us**, Down **Event503 IQ4_NL/J16=4091.872us**, and reduction Event505=597.872us all occurred in the same captured frame.

Run ZIP `20261111-212112-355-cli-rocm-b12188-ctx65536-db84c4f27fa6.zip` SHA256 `8ce37842e620f6f5bcdb99f54016332635da5192365d31467cf6930392aad43e`: **Status OK, ExitCode0, no truncation**; old IQ3/61788-token frozen input, b12188 commit832f0c5e7, same executable SHA and runtime digest as earlier matched diagnostic runs, ctx65536/ub512. Host log states `band=12 slot=1 KV=49664 N=512 layer=19`. This is an exact FA K extent, not the query-token start. Diagnostic-on PP329.17 tok/s is not a baseline.

**Correct, matched query token positions [49152,50176), with FA KV being right-edge length inclusive of active microbatch**:

| Condition (same old IQ3, layer19) | K length and N | Gate IQ2_S J | Up IQ2_S J | Down IQ4_NL J | 3 MMQ kernel time (us) |
| --- | --- | --- | --- | --- | ---: |
| ub512 first half | KV49664/N512 | J16 | J16 | J16 | **10455.021** |
| ub512 second half | KV50176/N512 | J16 | J16 | J16 | **10264.692** |
| **ub512 two-batch total** | **same tokens** | 6327.797us | 6310.837us | 8081.079us | **20719.713** |
| **ub1024 one batch** | **KV50176/N1024** | 4180.587us J32 | 4192.739us J32 | 7615.959us J32 | **15989.285** |
| ub1024 vs ub512 sum | | **−33.93% Gate** | **−33.56% Up** | **−5.76% Down** | **−22.83%** |

**This is a real pair of observed J16 microbatches**, not the earlier hypothetical 2×slot2 estimate. It is still a **GPU marker ON, distinct-RGP-session event-duration sum**, not marker-free profiling, not whole PP improvement, and not evidence for the complete cause of the old IQ3/IQ4 inversion. For these same query tokens, `moe_weighted_reduction_f32` sum in 2xub512 was1198.975us versus ub1024 1277.590us (a slight regression); FA event sums were116558.225us versus107970.800us (cross-session caveat).

ADLX high-utilization VRAM frequency was mostly 800MHz in all three runs (ub512 slot1, ub512 slot2, ub1024 slot2), with later increases toward 900–1000MHz, GPU clock broadly 2.88–2.89GHz. Near each RGP filename timestamp the nearest 2-second ADLX sample recorded 800MHz, **but RGP per-event GPU timestamps are not synchronized to ADLX sampling**. Do not ascribe the GPU event-duration delta exclusively to J without a matched marker-free, clock-controlled test.

**Next decision:** stop the fine-survey IQ3 measurements for the scoped local question. If continuing, use `rgp-clean` for both ub512 and ub1024, with separately calibrated RDP ranges (marker-on dispatch start 400500/404500/205000 MUST NOT be reused as if mapped), or study IQ4 in equivalent conditions to investigate the ranking inversion. If the next priority is Strata, archive the above as a completed exploratory marker-ON finding. The earlier reference to ub512 slot2+slot3 remains superseded by correct **slot1+slot2** mapping.

Full verified report: [evox2-llm-experiments](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-iq3-ub512-slot1-slot2-vs-ub1024-slot2-layer19.md).


## 2026-11-11: IQ4 ub1024 start205000 captured band13 layer47, not target slot2

User RGP screenshots `llama-cli-20261111-214937145.rgp`, old IQ4 model, HIP `rgp-survey-fine` variant, RDP start**205000**/count**1024**, show **Event483 `evox2_hip_fa_survey_kv_band<13>`**. Its RGP properties: **11264 total threads /64=176 workgroups => layer47** (survey encoding=129+layer). K extent band13 is [53248,57344), not target **band12 / exact K=50176 / layer19**. Fine 512-token marker is restricted to band12/layer19, so the absence of `kv_slot<2>` and of MoE layer19 tags is expected. This is not a failed build or a reason to change the source instrumentation.

Same capture contains FA Event487 `flash_attn_ext_f16` 119950.380us and Event488 `CmdBarrier` 9921.628us. MoE `mul_mat_q` Gate **Event593 IQ4_XS (ggml_type21), J32, 7413.552us**, Up **Event599 IQ4_XS J32, 7410.615us**, Down **Event607 IQ4_NL (ggml_type20), J32, 7914.678us** and reduction Event609 1336.778us. Three-MMQ GPU event durations total **22738.845us**. This is a **different layer and K extent**, and cannot be compared quantitatively to the IQ3 layer19/K50176 J32 MMQ 15989.285us to attribute the inversion.

Overview shows `The application is GPU bound`, profile duration366024.159us, **GPU idle 0.47%** and a brief activity gap around a command-buffer transition, with copy queue DMA nearby. Driver submission, dependency and transfer causes are unverified; continue deferring GPU idle analysis as agreed. A ~9.92ms CmdBarrier exists but is not a measurement of all-GPU idle.

**Next one-off RDP exploratory window:** old IQ4/ub1024, **start190000/count1024**, same `rgp-survey-fine` plan, input, executable, SQTT High, instrumentation/counters OFF. The guess moves ~15k dispatches earlier because band13/layer47 is several ubatches plus 28 layers after band12/layer19; this guess is not calibrated for IQ4. Inspect captured `kv_band<N>` and total threads (target layer19=9472), then fine `kv_slot<2>` and 3 MMQ kernels. Adjust only after interpreting the next band/layer; avoid transferring IQ3 205000 as a fixed coordinate for IQ4. No rebuild necessary, but no ZIP was supplied for independent run-condition verification on this RGP.


## 2026-11-11: IQ4 ub1024 start190000 is band12 layer39

User-provided RGP screenshots of `llama-cli-20261111-220225838.rgp`, HIP, old IQ4, ub1024, `rgp-survey-fine`, RDP **start190000/count1024**. Survey Event379 `evox2_hip_fa_survey_kv_band<12>` had **10752 total threads** → 168 workgroups (64 threads each) → **layer39** (gridX=129+layer), **not layer19**. With the fine marker limited to band12/layer19, its absence is expected and does not signal an implementation failure. FA Event383 `flash_attn_ext_f16` duration111396.947us; following Event384 `CmdBarrier` 8927.556us. Exact K extent is not known from this coarse band marker.

Earlier IQ4 start205000 yielded band13/layer47. Current start190000 yielded band12/layer39, bringing the scan toward the intended band12/layer19. **Next heuristic probe: start188000/count1024**, same model/input/binary/diagnostic variant, SQTT High. The 2000-dispatch retreat is *not calibrated for IQ4*: it roughly extrapolates from prior IQ3 12-layer/1000-index observations, which may not transfer to IQ4. Check actual band, layer from total threads, and fine `kv_slot<2>` next; target layer19=9472threads/K extent50176. No rebuild needed. No result ZIP was supplied for this capture, so execution metadata could not be independently verified.


## 2026-11-11: IQ4 ub1024 start188000 covers band12 layers11 and15

User screenshots `llama-cli-20261111-221831707.rgp`, RDP HIP `start188000/count1024`, old IQ4 `rgp-survey-fine`: both visible survey markers were **band12**, but **Event165 total threads8960** identifies layer11 (140 workgroups -129), and **Event765 total threads9216** identifies layer15 (144 workgroups -129). Marker durations0.307us/0.322us. Neither is target **band12/layer19**, where fine marker `kv_slot<2>` is configured and where MoE layer19 anchors would occur. This explains the absence of fine/MoE markers without implying a broken build.

These two same-capture markers are about600 RGP Event IDs and four layers apart; Event IDs include barriers and **must not be interpreted as GPU dispatch indices**. Nevertheless, they establish the traversal direction. Next **RDP start188500/count1024** (exploratory, not a confirmed dispatch location) with the same binary/input/variant; search for layer19 via 9472 total threads, band12, then fine slot2/K extent50176 N1024. Unlike previous broad 188000/190000 offsets, this retarget uses adjacent layer locations within one RGP capture, although HIP graph scheduling could still shift the window. No rebuild required. ZIP of this specific run not provided.


## 2026-11-11: IQ4 ub1024 start188500 reached layer19 but slot6

User RGP screenshot `llama-cli-20261111-223230073.rgp`, HIP Radeon GPU Profiler 2.7.0.32, old IQ4 / ub1024, diagnostic `rgp-survey-fine`, RDP **start188500/count1024**: survey **Event365 `evox2_hip_fa_survey_kv_band<12>`** (0.357µs), next **Event367 `evox2_hip_fa_survey_kv_slot<6>`** (0.369µs). RGP total threads **9472**, workgroups148 (64threads/workgroup), **layer=148−129=19**. MoE layer19 anchor events **405,413,423** are visible for Gate/Up/Down. No exact-KV49152 FA marker is expected for slot6. Exact K extent should be verified in stderr if needed; the slot marker by itself only establishes `KV∈[52224,52736)`. For this contiguous aligned N1024 workload the expected exact value is **KV52224**, corresponding to query token positions51200..52223. Our target remains **KV50176/N1024/slot2**, query positions49152..50175. Thus need two 1024-token microbatches earlier, not another layer adjustment.

**Next one-off exploratory RDP start181500/count1024** with unchanged IQ4 ub1024 `rgp-survey-fine` binary and CLI plan, SQTT High. **Heuristic only:** old IQ4 start188500 at layer19 versus start190000 at layer39 within band12 suggests ~1500 /20 ≈75 GPU dispatches/layer in the local portion; 48 layers per ubatch ×75 ≈3600 dispatches/batch, so two batches earlier implies ~188500−7200≈181300. Start181500 is a rounded search window, **not a verified global position**. It extrapolates across layers/ubatch boundaries where HIP Graph and kernel mixes can change. Do not add RGP Event IDs to RDP Dispatch start. Determine band+layer from actual survey marker, and slot only when layer19 appears. IQ4 source/model input ZIP was not supplied in this turn, so this is screenshot-only evidence.


## 2026-11-11: IQ4 ub1024 start181500 returned band12 layer23 (ubatch boundary caveat)

User-provided RGP screenshot `llama-cli-20261111-224144679.rgp`: old IQ4, ub1024, `rgp-survey-fine`, RDP **start181500/count1024**. Event **517** `evox2_hip_fa_survey_kv_band<12>` duration 0.466µs; 9728 total threads /64 =152 workgroups, thus **layer23** (152−129). Followed by `evox2_hip_anchor_moe_layer23` Event **555/563/573**. Previous start188500 gave band12/layer19/**slot6**. The apparent layer increase 19→23 does **not** necessarily mean a move later in prompt ingestion: **layers reset to 0 at each ubatch**, and moving from start188500 back 7000 global dispatches can cross one or more ubatch boundaries. Both captured FA events are in coarse KV band12 (K extent 49152..53247), which covers several full1024-token ubatches. Since the fine marker only launches for **layer19**, this screenshot at layer23 does not expose the precise KV slot; it is therefore **not yet proven** that the new position is target slot2 (K extent50176).
 
**Next short exploration:** keep same IQ4/ub1024 run and diagnostic code, RDP **start181000/count1024** to find layer19 **earlier within the current observed layer23-containing ubatch**. 500-dispatch retreat for 4 layers is a heuristic based on prior local layer observations; global dispatch mapping differs between captures under HIP Graph. If band12/layer19 appears, inspect `kv_slot<N>` (target **slot2**, layer19=9472 total threads), then MoE J32 MMQ Gate/Up/Down. If slot is 0 or 4 rather than 2, the correct direction needs another calibration; do not claim exact KV from band12+layer23 alone. No rebuild necessary. The user did not provide the run ZIP in this turn.


## 2026-11-11: IQ4 ub1024 start181000 is band12 layer15; next probe181250

User screenshot `llama-cli-20261111-225545191.rgp`, HIP/RGP 2.7.0.32, old IQ4, ub1024, `rgp-survey-fine`, RDP start**181000/count1024**: **Event309 `evox2_hip_fa_survey_kv_band<12>`**, duration **0.422µs**, Total threads **9216**, 64threads/workgroup ⇒ 144 blocks ⇒ **layer15** (144−129). No layer19 MoE anchors or fine marker is expected because the photographed survey is at layer15; the marker limitation is configured for band12/layer19. Earlier start181500/count1024 gave band12/layer23 (9728threads); start188500 gave band12/layer19 but fine **slot6**, which is later than target **slot2 (FA K extent50176/N1024)**.

**Next single tentative capture:** keep same old IQ4/ub1024 diagnostic variant/inputs and use RDP **start181250/count1024**, SQTT High. This is a midpoint probe between captures showing layers15 and23, **not a verified global dispatch offset**; different runs/graph scheduling and overlapping 1024-dispatch windows may change which events RGP reports. If band12/layer19 appears, inspect the fine slot (want2), then MoE J32 kernels/reduction; if not, use the observed layer+slot and avoid assuming Event ID is a global dispatch number. No rebuild needed. No run ZIP supplied for this screenshot, so exact K and runtime are not independently verified.


## 2026-11-11: old IQ4 ub1024 band12 slot2 layer19 RGP captured at start181250

**Exact-position marker-ON IQ4 J32 gate PASS.** User RGP screenshots `llama-cli-20261111-230644298.rgp`, HIP, **start181250/count1024**, showed Event409 `evox2_hip_fa_survey_kv_band<12>` and Event411 `evox2_hip_fa_survey_kv_slot<2>` (9472 threads/64=148 groups→**layer19**), followed by MoE `evox2_hip_anchor_moe_layer19` Events449/457/467. The uploaded archive `20261111-230336-936-cli-rocm-b12188-ctx65536-492dbc43b50e.zip` (SHA256 `8394425029563d21636f662623d7c23f7f696ce3a9308d1e2755fffdb8d213bd`) verifies run **OK / ExitCode0**, old **IQ4_XS** (model file ~87.24GiB), ROCm b12188 commit832f0c5e7, exact same binary SHA and fixed 61788-token code input SHA as prior old IQ3, ctx65536, ub1024, MTP OFF, Performance/UMA96GB, diagnostic ON. stderr confirms **`band=12 slot=2 KV=50176 N=1024 layer=19`**, meaning a query batch covering **positions49152..50175** (0-based) under this full aligned context. PP **350.20 tok/s** is diagnostic ON, not a marker-free performance baseline.

| Same layer19, KV50176/N1024 | IQ3 J32 GPU event µs | IQ4 J32 GPU event µs | IQ4 vs IQ3 |
| --- | ---: | ---: | ---: |
| Gate (IQ3 IQ2_S; IQ4 IQ4_XS) | 4180.587 | **7120.513 (E455)** | **+70.32%** |
| Up (IQ3 IQ2_S; IQ4 IQ4_XS) | 4192.739 | **7177.947 (E463)** | **+71.20%** |
| Down (both IQ4_NL) | 7615.959 | **7586.650 (E473)** | **−0.38%** |
| **3 MMQ kernel durations sum** | **15989.285** | **21885.110** | **+36.87% (+5.896ms)** |

IQ4 captured FA Event415=**108117.744µs**, `CmdBarrier` Event416=**8838.715µs**, reduction Event475=**1286.643µs**. All event times are local GPU kernel/driver events, not complete PP elapsed time. The Gate/Up difference matches the quantization change (`ggml_type22` IQ2_S→`ggml_type21` IQ4_XS); the Down path (`ggml_type20` IQ4_NL) is nearly equal at this scope. **Do not attribute full IQ3/IQ4 ubatch PP inversion to this alone**; IQ4 J16/ub512 paired marker-on measurements have not yet been captured. ADLX shows VRAM800MHz during much of high utilization and a rise near the RGP file time; timestamp correspondence to each RGP GPU event is not calibrated.

**Next** old IQ4 **ub512 `rgp-survey-fine`**: collect layer19 **KV50176/N512/slot2** then **KV49664/N512/slot1** for the same query positions49152..50175. Start with exploratory RDP **start358000/count1024** for slot2: rough estimate from IQ4/IQ3 ub1024 target dispatch ratio (181250/205000) applied to IQ3 ub512 slot2 start404500 (~357600), **not validated by any IQ4 ub512 RGP**. Read coarse band, total threads→layer, and fine slot; recalibrate after the first result. Use plan job `pp64k-oldiq4-ub512`, variant `rgp-survey-fine`, no code changes. Existing IQ3 J16×2/J32 marker-on MMQ improvement **−22.83%** is the comparison baseline for the **IQ4 J16×2/J32 speedup**, not the cross-model +36.87% figure above. Marker-OFF `rgp-clean` and unrelated GPU idle remain deferred.

Full report: [old IQ4 KV50176/layer19 RGP](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-oldiq4-ub1024-slot2-layer19-rgp.md).


## 2026-11-11: old IQ4 ub512 RGP start358000 shows band12 layer35 and layer39

User-supplied RGP screenshots `llama-cli-20261111-233317228.rgp`, old IQ4 / ub512, HIP / `rgp-survey-fine`, RDP **start358000/count1024**. Two FA coarse survey markers in one captured trace:

| Event | `evox2_hip_fa_survey_kv_band` | Total threads | Workgroups (=threads/64) | Layer (=workgroups−129) | Duration |
| ---: | --- | ---: | ---: | ---: | ---: |
| 191 | **band12** | **10496** | 164 | **35** | 0.330µs |
| 789 | **band12** | **10752** | 168 | **39** | 0.371µs |

Both are **later in layer sequence than layer19**, so retarget to a **lower** dispatch start. Neither event identifies the precise KV slot because fine survey is restricted to layer19. These two markers are 598 **RGP events**, not 598 GPU dispatches: the event stream includes `CmdBarrier` and other entries. A very rough model of ~2 RGP events per dispatch gives ~300 dispatch for 4 layers, ~1200 dispatch for 16 layers. **Next exploratory setting start356600/count1024** to place layer19 away from the capture edge; this is an unverified heuristic, not calibrated global dispatch mapping and may miss due to varying graph/event patterns. Reuse the same IQ4/ub512 `rgp-survey-fine` build/model/inputs, no rebuild. Seek `kv_band<12>` with Total threads9472 (layer19), then fine `kv_slot<2>` (K extent50176/N512); only after that collect the Gate/Up/Down J16 MMQ/reduction. Subsequently capture `kv_slot<1>` (K extent49664/N512) for exact same 1024 query tokens as the existing IQ4 ub1024 slot2. No CLI ZIP included with this message, so exact host KV and run status were not independently reverified.


## 2026-11-11: old IQ4 ub512 KV50176/N512 slot2 – J16 MMQ ranking reversal vs IQ3

ユーザー提供 `llama-cli-20261111-234202312.rgp` RDP HIP **start356600/count1024** で、旧IQ4/ub512の**band12 slot2 layer19**を捕捉：RGP Event585 `kv_band<12>`, Event587 `kv_slot<2>`, total threads**9472** (=148 workgroups→layer19)、FA Event589=**59957.775µs**、Event590 CmdBarrier**10724.432µs**、MoE layer19 anchors Event623/631/641。MMQ Gate **Event629 `mul_mat_q<ggml_type21,16>`=2441.401µs**、Up **Event637同=2442.065µs**、Down **Event647 `mul_mat_q<ggml_type20,16>`=4001.136µs**、reduction Event649=592.218µs。MMQ3 GPUイベント時間単純合計 **8884.602µs（8.885ms）**。

受領ZIP `20261111-233901-665-cli-rocm-b12188-ctx65536-42367a061f58.zip`, SHA256 `f05aec038a2c2cee61808f3a7476db68a8fe408096250a645b3b5dde01f68171`：**Status OK/ExitCode0**、旧IQ4_XS PLE16、61788トークンの同一入力SHA、ROCm b12188/commit832f0c5e7/同一exe SHA・runtime Verified、ctx65536、ub512、f16 KV、MTP OFF、P-Mode Performance、UMA96GB。stderrでも **`band=12 slot=2 KV=50176 N=512 layer=19`** 確認。これは**処理トークン位置49664..50175（後半512トークン）**のFA K extentであり、KV値＝処理開始位置ではない。診断ONのPP **361.80 tok/s**（本来の性能順位には使用しない）。

**同じlayer19・KV50176・N512のJ16 MMQ時間比較**：既存旧IQ3のGate3136.757/Up3138.728/Down3989.207、合計10264.692µsに対し、今回旧IQ4のGate2441.401（−22.17%）、Up2442.065（−22.20%）、Down4001.136（+0.30%）、合計8884.602µsで**旧IQ4が13.45%短い**。一方、同じ位置の**J32/ub1024**では旧IQ4 MMQ3合計21885.110µs、旧IQ3合計15989.285µsで**旧IQ4が36.87%長い**。したがって**J16とJ32の局所MoE MMQ速度順位逆転は直接観測された**。Gate/Upの量子化形式はIQ3 `ggml_type22` (IQ2_S) 対 IQ4 `ggml_type21` (IQ4_XS)、Downは両者 `ggml_type20` (IQ4_NL)。ただし**PP全体の逆転理由の完全証明ではない**。

IQ4のJ16 slot2を**仮に単純2倍**したMMQ17769.204µsとIQ4 J32実測21885.110µsの比較は、仮換算で**J32が23.16%長い**が、前半512トークンの実測がなく正式比較ではない。**残りの1窓**は旧IQ4/ub512 **KV49664・N512・band12/slot1・layer19**、処理位置49152..49663。今回start356600と以前IQ4 start358000のlayer35/39アンカーから、約48レイヤー分の推定退行を踏まえて**RDP start353000/count1024**を次の**未検証探索値**とする。同じ`pp64k-oldiq4-ub512`＋`rgp-survey-fine`、SQTT High、再ビルド不要。band/layer/slotとstderrで正確な位置を照合してからpaired J16×2/J32を集計。ユーザー予定どおり`rgp-clean`とGPU idleは後段。

ADLXの本run：高GPU負荷（≥95%、n83）平均GPU core約2889MHz、VRAM約834MHz（ファイル時刻付近2秒間隔サンプルは800MHz）、消費電力約119W。個別RGPイベントとの厳密同期はない。詳細： [旧IQ4 J16 slot2検証レポート](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-oldiq4-ub512-slot2-layer19-rgp.md)。


## 2026-11-11: Final old IQ3/IQ4 layer19 matched-1024-token MMQ RGP J16/J32 comparison — marker ON complete

**Final required slot obtained:** old IQ4 / ub512 at RDP HIP **start353000/count1024**, `llama-cli-20261111-235659870.rgp`. Coarse survey Event581 `kv_band<12>` and fine Event583 `kv_slot<1>` at **9472 threads→layer19**. Same capture shows layer19 MoE anchors Events619/627/637 and **Gate E625 `mul_mat_q<ggml_type21,16>` 2489.574µs, Up E633 same 2465.947µs, Down E643 `mul_mat_q<ggml_type20,16>` 4090.038µs**, plus reduction E645 599.148µs. This is **KV49664/N512/layer19**, contiguous query-token positions **49152..49663**. Other IQ4 J16 slot2 was already captured at **KV50176/N512**, query positions49664..50175. IQ3's two slots and both models' J32/KV50176/N1024 had also already been captured. **All four matched-condition coverage gates PASS.**

Execution archive `20261111-235357-680-cli-rocm-b12188-ctx65536-42367a061f58.zip` SHA256 `ef94621a9dcd1a767a50bd26dedd25eb87a0b9821f632bbf7722daa7b8832e30`, independently read: **Status OK/ExitCode0**, old IQ4_XS, ROCm b12188/commit832f0c5e7, executable SHA `543bf88826a9fe362815a9503e3cdaeda041eb40e52aafbbe5e6d1c569dd15a5`, runtime artifacts Verified with matching digest, 61788-token same code input SHA `a8289b8e6f5c2cabf0d85940874c3c80e39f4c1c879c3766f98f0b8946b26d9a`, ctx65536/ub512, f16 KV, MTP OFF, P-MODE Performance/UMA96GB. Host stderr exactly `band=12 slot=1 KV=49664 N=512 layer=19`. Diagnostic-on PP **364.29 tok/s**, TG20.44 tok/s, not marker-free PP baseline.

**MMQ3 GPU event durations (microseconds), actual measured same query token region positions49152..50175**:

| Model / GPU kernel | J16 ub512 first slot1 | J16 ub512 second slot2 | J16×2 actual sum | J32 ub1024 full | J32 versus J16×2 |
| --- | ---: | ---: | ---: | ---: | ---: |
| IQ3 Gate IQ2_S | 3191.040 | 3136.757 | 6327.797 | 4180.587 | **−33.93%** |
| IQ3 Up IQ2_S | 3172.109 | 3138.728 | 6310.837 | 4192.739 | **−33.56%** |
| IQ3 Down IQ4_NL | 4091.872 | 3989.207 | 8081.079 | 7615.959 | −5.76% |
| **IQ3 3 MMQ sum** | **10455.021** | **10264.692** | **20719.713** | **15989.285** | **−22.83% (−4.730ms)** |
| IQ4 Gate IQ4_XS | 2489.574 | 2441.401 | 4930.975 | 7120.513 | **+44.40%** |
| IQ4 Up IQ4_XS | 2465.947 | 2442.065 | 4908.012 | 7177.947 | **+46.25%** |
| IQ4 Down IQ4_NL | 4090.038 | 4001.136 | 8091.174 | 7586.650 | −6.24% |
| **IQ4 3 MMQ sum** | **9045.559** | **8884.602** | **17930.161** | **21885.110** | **+22.06% (+3.955ms)** |

**Direct local MMQ inversion observed:** IQ4's J16×2 sum **17.930ms** is **13.46% shorter** than IQ3's **20.720ms**, but IQ4's J32 sum **21.885ms** is **36.87% longer** than IQ3's **15.989ms**. Difference originates chiefly in Gate/Up: IQ3 uses `ggml_type22` IQ2_S and IQ4 uses `ggml_type21` IQ4_XS, while Down `ggml_type20` IQ4_NL is about equal and improves moderately with larger J in both models. This matches the *direction* of the prompt PP speed crossover, but **is NOT a whole-PP or causal attribution**: these are **SQTT captured, GPU diagnostic marker ON, cross-session event-time sums** omitting helper and host scheduling. Other layers/positions, CPU/GPU overlap, FA, kernel clocks and marker-free runs must be considered for attribution. FA sum for this 1024-token interval: IQ3 J16×2 116.558ms vs J32 107.971ms; IQ4 J16×2 117.118ms vs J32 108.118ms. Reduction sums: IQ3 1.199ms vs1.278ms; IQ4 1.191ms vs1.287ms. No evidence that all operations improve with larger ubatch.

Newest ZIP ADLX at high GPU usage≥95%: n83, core clock mean~2886.9MHz, VRAM mean~834.5MHz and median800MHz, power mean~119W. Near RGP file time 23:56:59 JST, 2s sampling showed ~800MHz VRAM at high GPU load. **No calibrated per-event RGP-to-ADLX clock correlation**; cannot assign individual kernel clock states or rule out profiling/thermal or scheduling confounds.

**Scope gate for `rgp-survey-fine` is now CLOSED for both IQ3 and IQ4.** User preference: do marker-OFF tests **together afterwards** (don't chase GPU idle right now). If proceeding, use `rgp-clean` or plain marker-free run across IQ3/IQ4×ub512/1024, verify variant flags really remove survey and anchor dispatch kernels, independently remap RDP capture starts (marker-on indexes are invalid after removing extra dispatches), and avoid claiming clean captures match exact K/layer without separate proof. Detailed evidence: [final paired 4-condition RGP report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-11-iq3-iq4-matched-1024-token-j16-j32-final-rgp.md). GPU idle and CmdBarrier root causes remain a separate deferred investigation.

## 2026-11-12: Planned marker-OFF PP-only six-condition sweep (including updated IQ3)

The **marker-ON** RGP layer19 IQ3/IQ4 J16/J32 matching gate is complete; the next requested measurement is a **normal PP-only throughput sweep without opening/capturing RGP**, before any clean RGP location remapping. Includes updated/new IQ3 PLE16 (but **not** any updated/new IQ4, which is not downloaded). The logical MoE matrix/tensor dimensions are shared for the same architecture, ubatch and layer, but physical compressed weight layouts, GGML type, effective expert assignment distribution, and per-type MMQ config differ. The `J=16/32` shown by RGP is **column tile width**, not the complete matrix dimension. Source: `ggml/src/ggml-cuda/mmq.cu` sets `ncols_opt` from MoE activations / expert counts and selects `ggml_cuda_mmq_get_config(src0->type, J,...)`; `mmq.cuh` defines config including SRAM tile width I/J, K tile and threads. Therefore local timing crossover is **not just identical instruction sequences executing at different speeds**.

**New complete 6-job matrix plan:** [qwen38-r6-rocm-pp64k-marker-off-oldiq3-oldiq4-newiq3-6run-20261112.psd1](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp64k-marker-off-oldiq3-oldiq4-newiq3-6run-20261112.psd1). Same 61788-token frozen `PPCode64kRgp` input, ctx65536, ROCm **R6RocmPp64kMmqTrace** b12188 executable, `-b2048 -ub{512,1024} -t4 -tb4 -ngl999 -ncmoe0 -fa auto`, f16 KV, MTP disabled, 256 generation tokens (unchanged from RGP tests; evaluate **PP metric only**), one run per job, 45s cooldown, 96GB UMA/P-MODE Performance. The only variant is `rgp-clean`; all survey, anchor, MMQ trace, FA trace and SSE trace env flags are explicitly zero or null. RDP/SQTT capture must also be disabled for this PP-only measurement.

**Order balanced by ubatch:** old IQ3/512 → old IQ4/512 → **new IQ3/512** → **new IQ3/1024** → old IQ4/1024 → old IQ3/1024. Local model key `MHHNewIQ3` is the converted updated Unsloth PLE16 model; it was used in the earlier quality comparison. Other model keys `MHHOldIQ3`, `MHHOldIQ4` and build key `R6RocmPp64kMmqTrace` are shared with the RGP plan. Input `PPCode64kRgp` must be present in local.psd1 as it was for recent RGP captures.

PowerShell (execute in installed diagnostic worktree, but reuse main r6 local.psd1):
```powershell
$diag  = 'C:\llama-build\llama.cpp-evox2-windows-r6-pp64k-mmq'
$main  = 'C:\llama-build\llama.cpp-evox2-windows-r6'
git -C $diag pull --ff-only
$matrix = Join-Path $diag 'tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$local  = Join-Path $main 'tools\evox2\benchmark\configs\local.psd1'
$plan   = Join-Path $diag 'tools\evox2\benchmark\configs\qwen38-r6-rocm-pp64k-marker-off-oldiq3-oldiq4-newiq3-6run-20261112.psd1'
& $matrix -Plan $plan -LocalConfig $local -MaxRuns 6 -PlanOnly
& $matrix -Plan $plan -LocalConfig $local -MaxRuns 6 -StopOnError
```

**Must verify first:** dry-run six expected jobs and `MHHNewIQ3` resolved to **updated PLE16** file, not old IQ3 nor pre-conversion shards; all six use same input SHA and executable SHA. Compare PP tok/s and ADLX clock history; do **not** claim a 6-run comparison yet because this is a plan only. Clean RGP capture may be done later and requires new dispatch coordinates; old marker-on RDP starts are invalid without markers.


## 2026-11-12: 64k code PP marker-OFF — 12run (RDPあり6 / RDPなし6)

受領ZIP `20261112-012850-438-cli-rocm-b12188-ctx65536-a84871ff3d62.zip` SHA256 `c43d69cd23e6f099dae48e0e5399e49dc8f3778c7228c9f35d8f7386d5d8b6be` に**12run（前半Radeon Developer Panel/RDP起動・start353000自動capture設定6run、後半RDP終了6run）**が含まれる。全部Status OK/ExitCode0、ROCm b12188同一exe/runtime、同一コード入力61788tok/SHA、ctx65536、f16 KV/MTP OFF、P-Mode Performance、UMA96GB。前後ともHIP survey/anchor/MMQ trace/FA trace/SSE traceはすべて環境変数OFF。RDPなし後半6runを**正式PP値**とする。

| モデル | ub512 RDPあり | ub512 RDPなし | ub1024 RDPあり | ub1024 RDPなし |
| --- | ---: | ---: | ---: | ---: |
| 旧IQ3 | 330.88 | **351.48** | 359.84 | **405.49** |
| 旧IQ4 | 364.57 | **393.69** | 341.68 | **387.97** |
| 新IQ3（更新版PLE16） | 339.75 | **364.16** | 363.00 | **405.29** |

**マーカーOFFかつRDPなしで逆転再現：ub512は旧IQ4が旧IQ3比+12.01%、ub1024は旧IQ3が旧IQ4比+4.52%。** IQ3自身のub512→1024は旧版+15.37%、新IQ3+11.30%；旧IQ4は−1.45%。新IQ3はub1024で旧IQ3とほぼ同速（405.29/405.49）。ただし各1runで、反復の統計精度を保証するものではない。

**RDPありは参考用**：RDPあり高GPU使用率サンプルのVRAMクロックは平均800〜844MHz、RDPなしでは平均929〜999MHz。GPUコアクロックは概ね2874〜2896MHzと近い。RDPあり→なしで全6条件PPが+6.2〜13.6%上がった。シーケンシャル比較のため**RDP起動／RGPキャプチャがVRAMクロック低下の原因と断定は不可**。非計測時のRGP開放を推奨。RDPはRadeon Developer Panelで、Windowsのリモートデスクトップではない。

**start353000のマーカーOFF RGP×6の再利用可否**：各ファイル内でGPUカーネル列、FA/MoE、barrier/idle等を**予備分析・粗い位置推定**する材料にはなる。**同じstart番号が同じKV/layerを保証しない**（survey/anchor OFFによるdispatch数変化、IQ3/IQ4/新IQ3の処理差、ub512/1024差）；特にub1024は過去のmarker-ON layer19アタリ位置（旧IQ3≈205000、旧IQ4≈181250）を大きく越えるので後半／TGの可能性あり。マーカーOFFのRGPデータ自体は**今回ZIPに含まれておらず**、各RGPのイベント内容は未確認。前半RDPありのクロック条件が後半RDPなしと異なるため、RGPイベント時間を後半PPの絶対的な内訳として換算しないこと。必要なら既存6 RGPのうちold IQ4 ub512から確認、FA/MoEの並び・イベント・末尾を見てから狙う位置を再校正。マーカーONで一致済みのMMQ3 J16/J32局所速度逆転も引き続き有効な機序候補。

詳細： [2026-11-12・RDPあり/なし12run解析](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-12-rocm-64k-marker-off-12run-rdp-on-off.md)。**マーカーOFFのPP確認ゲートは完了**、新IQ4は未入手につき対象外、GPU idleの詳細解析は別途保留。


## 2026-11-12: rgp-clean old IQ4 ub512 start353000 binary RGP, two FA groups

Received raw AMD RDF/RGP file `llama-cli-20261112-004203560.rgp` (**285455832 bytes**, SHA256 `2e7ff430a2fa8fac6132dbf960c487df7f1065742d896ad48610590a4d215433`) and five event screenshots, Radeon GPU Profiler 2.7.0.32, **RDP start353000/count1024**, old IQ4_XS/ub512/`rgp-clean`. Corresponds to preliminary RDP-open PP run `20261112-003905-914` (**364.57 tok/s**, original 61788tok frozen code, ROCm b12188, successful execution, all in-app GPU markers off). User screenshots give **FA E43=55664.055µs**, **FA E639=57196.743µs**, and following `CmdBarrier` E44=9870.983µs/E640=10500.385µs. Corresponding three J16 MoE MMQ operations:

| | Gate IQ4_XS | Up IQ4_XS | Down IQ4_NL | 3 MMQ sum | Reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| FA E43 group | E81 2492.452µs | E87 2527.682µs | E95 4168.614µs | **9188.748µs** | E97 606.262µs |
| FA E639 group | E677 2568.534µs | E683 2569.896µs | E691 4208.512µs | **9346.942µs** | E693 601.473µs |

The **596-event separation** between FA events and also between corresponding MoE events is very close to previous marker-ON survey observations (**598 RGP events** separated FA **layer35→layer39**, hence 4 layers). **Strong hypothesis: two FA events come from neighboring FA layers four layers apart within a single ubatch, NOT from consecutive ubatches of one layer.** But **actual layer and K cannot be uniquely identified without markers or calibrated host trace**. Do not combine these two MMQ groups as if they were J16×2 for a single fixed layer (the marker-ON paired J16×2/J32 investigation already had proper KV/layer alignment). Marker-on start353000=IQ4 ub512 KV49664/layer19 does **not** imply identical marker-free start353000=KV49664/layer19; removal of thousands of earlier marker GPU launches shifts global dispatch mapping. Earlier marker-free PP crossover remains unaffected.

Adjacent run ADLX samples around RGP timestamp 2026-11-12 00:42:03 local: at 00:42:01 GPU100%/core2894MHz/VRAM800MHz; 00:42:03 GPU99%/core2886MHz/VRAM800MHz; 00:42:05 GPU99%/core2838MHz/VRAM800MHz. RGP event clock not calibrated to ADLX individual samples. The RGP binary was verified to start `AMD_RDF ` but **full binary SQTT event decoding was not performed**; timings are transcribed from user's screenshots. CmdBarrier event duration is not automatically whole-GPU idle.

Full report: [old IQ4 ub512 marker-OFF RGP start353000](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-12-rgp-clean-oldiq4-ub512-start353000-two-fa.md).

**Positioning next gate**: if an exact clean K/layer comparison is essential, a separate calibration is needed (count FA occurrences from a known ubatch start or use CPU-side-only K/layer instrumentation). Existing six clean files may still be useful for qualitative kernel sequence/barrier comparisons, but `start353000` by itself cannot align IQ3/IQ4/ub variants. Hold unrelated GPU idle investigation per user.


## 2026-11-12: rgp-clean old IQ3 ub512 start353000, two FA→MoE groups

User-provided four Event timing screenshots of `llama-cli-20261112-003653622.rgp`, RDP HIP **start353000/count1024**, old IQ3_XXS / ub512, **markers OFF**. The corresponding **`.rgp` binary was NOT uploaded** in this message (unlike the earlier old IQ4 `.rgp`); event times were transcribed from screenshots. Associated earlier verified RDP-open PP run `20261112-003344-380` recorded **330.88 tok/s**; RDP-closed counterpart **351.48 tok/s**. GPU-high-load ADLX mean VRAM clock for former ~840.7MHz but no per-event synchronization.

| | First FA group | Second FA group |
| --- | --- | --- |
| FA | **E229 52766.965µs** | **E909 52930.341µs** |
| CmdBarrier after FA | E230 9297.721µs | E910 9332.860µs |
| Gate `mul_mat_q<ggml_type22,16>` IQ2_S | **E271 3139.622µs** | **E951 2910.971µs** |
| Up same IQ2_S/J16 | **E277 3185.156µs** | **E957 2893.999µs** |
| Down `mul_mat_q<ggml_type20,16>` IQ4_NL | **E285 4089.146µs** | **E965 3654.267µs（参考値・集計除外）** |
| **3 MMQ sum（採用値）** | **10413.924µs** | **—（E965除外で算出しない）** |
| `moe_weighted_reduction_f32` | E287 639.805µs | screenshot not shown after E965 |

**品質上の注記（ユーザー指摘で修正）：** E965 DownはRGP最後の表示イベントであり、過去にRGP末尾イベントの実行時間が不自然に短くなった事例があるため、**3654.267µsは参考値のみ、すべてのMMQ3合計・%変化・IQ3/IQ4比較から除外する**。E965が本当に切断されたかはスクショだけでは未確定。旧記載の二回目「9459.237µs」および「前半比−9.17%」は採用しない。E951 Gate2910.971µs、E957 Up2893.999µsは個別の参考GPUイベントとして維持。2回目MoEの完全な合計値を確定させるための追加撮影は現段階で必須ではない。位置合わせ済みmarker-ONのIQ3/IQ4 J16×2/J32比較には影響なし。

The two FA and matching MoE events are **680 Event IDs apart**, while old IQ4/ub512 `rgp-clean` at same global start353000 had **596 event IDs** between its FA/MoE groups (FA E43/E639, Gate E81/E677). Previous marker-on IQ4 4-layer-spaced survey had 598 IDs between layer35→39. Hence the two FA groups within each clean RGP **likely represent four-layer-separated FA operations in one ubatch, NOT two consecutive ubatches at fixed layer**; exact K/layer unproven with markers OFF. IQ3's extra 84 displayed events may reflect different intermediate scheduling/dispatch structure, not proven to be quantization alone.

**Do NOT directly compare IQ3 vs IQ4 based solely on the shared RDP start353000**: removing earlier GPU markers shifts absolute dispatch indices, and quantization/model type also shifts position, so not guaranteed same KV or layer. In particular do not add the two FA-linked MMQ groups as a J16×2 same-layer result. The previously correctly paired marker-ON J16×2/J32 result remains the valid position-matched comparison. Source report: [old IQ3 ub512 clean RGP](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-12-rgp-clean-oldiq3-ub512-start353000-two-fa.md). No need to repeat six-run PP; keep GPU idle analysis deferred.


## 2026-11-12: old IQ3 ub1024 start353000 – TG, not PP

User supplied 8 RGP Event screenshot views of `llama-cli-20261112-010236922.rgp` (`.rgp` binary not supplied), marker-OFF **old IQ3/ub1024** at **RDP start353000**. Four FA events **E401, E913, E1425, E1937** each `flash_attn_tile<256,256,1,4,false>` at **751.260, 751.743, 742.016, 743.503 µs**, exact **512 event IDs** apart; starts 2311.878/6330.638/10351.671/14376.598 µs, ~4.02 ms between starts. Each segment includes J=1 **`mul_mat_vec_q<ggml_type22,1>`** (old IQ3 IQ2_S) and `mul_mat_vec_q<ggml_type20,1>` (IQ4_NL), **not** the `mul_mat_q<...,16/32>` from PP. 64k code PP previously showed `flash_attn_ext_f16<256,256,16,4,...>` of ~53ms.

**Conclusion: the capture is a TG/one-token graph, NOT the desired PP J32 RGP window.** Four FA calls need **not** mean four generated tokens: regular 512-event interval + repeated FA/MoE sequence is consistent with FA-bearing layers spaced through one token's network pass, though layer IDs are unverified. **Exclude all event times from PP crossover comparison.** Unlike old IQ3 ub512 & old IQ4 ub512 start353000 marker-OFF RGP, this ub1024 window lies too late; old marker-ON IQ3 ub1024 layer19 near 201000–205000 but clean marker-off start must be **recalibrated**, not copied. No new PP benchmark needed. Raw/screenshots-only evidence report: [Old IQ3 ub1024 clean RGP TG classification](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-12-rgp-clean-oldiq3-ub1024-start353000-tg-not-pp.md). GPU idle root-cause work still deferred.

## 2026-11-12: marker-OFF new IQ3 ub512 clean RGP start353000 vs old IQ3

Screenshots for `llama-cli-20261112-004642192.rgp`, new IQ3/ub512, RDP open, marker-off, start353000. **Old/new IQ3 same event IDs** FA E229/E909, Gate E271/E951, Up E277/E957, Down E285/E965; same `flash_attn_ext_f16<256,256,16,4>`, IQ2_S Gate/Up `mul_mat_q<ggml_type22,16>`, IQ4_NL Down `mul_mat_q<ggml_type20,16>`. FA times old **52.766965 / 52.930341 ms**, new **52.549143 / 53.180077 ms**. First three MoE MMQ kernels: old **3.139622+3.185156+4.089146=10.413924ms**; new **3.116612+3.163225+4.032555=10.312392ms (−0.975%)**. Second Gate/Up old **2.910971+2.893999ms**; new **2.944963+2.930239ms**. **Second Down E965 old 3.654267ms/new 3.713219ms is reference only and excluded** because it is the last displayed event and earlier last-event truncation problem was observed; no accepted second MMQ3 total or percentage is reported. E229→E909 interval **680** for both, unlike IQ4's 596: strong evidence of same local dispatch pattern between old/new IQ3 but **no verified absolute layer/K**. Differences are small, mixed-sign, and not a proven causal new-IQ3 speedup. User has checked remaining ub1024 IQ4/new IQ3 start353000 captures: similarly TG-like, therefore these PP/J32 RGP captures will be reacquired at a separately calibrated earlier dispatch start **later**; do not treat them as PP. Detailed report: [new vs old IQ3 clean RGP comparison](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/qwen38-rocm-iq3-iq4-pp-20261110/runs/2026-11-12-rgp-clean-newiq3-ub512-start353000-oldiq3-compare.md).
