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
