# r5 MTP `mtp_eh_proj` flatten prototype and measurement plan — 2026-10-16

**Status (updated 2026-10-19): Vulkan short, 64k/128k ABBA and focused flatten-ON RGP Event timing COMPLETE; same-binary flatten-OFF RGP optional; numerical Draft K/V correctness and rollback gates OPEN before integration. See the 2026-10-19 section below.**

## Branch and scope

Branch:

```text
investigation/r5-mtp-eh-proj-flatten-20261016
```

Base:

```text
investigation/r5-mtp-pp-kv-crop-stage1-20261014
```

This deliberately does **not** derive from the #30511 Target re-warmup control
branch. The retained b11618 Stage-B result stays an immutable historical cohort.

Implementation commits:

- `cb069334` — initial opt-in HC/token flatten around Qwen4Exp MTP `eh_proj`
- `b3ff6a38` — restrict the experiment to Stage-B zero-output Draft prefill
- benchmark plans added afterward on this branch

The only runtime switch is:

```text
LLAMA_MTP_EH_PROJ_FLATTEN=1
```

Default/off behavior is unchanged.

## Source change

The Stage-B Draft catch-up path already computes:

```text
e_norm : [n_embd, hc, T]
h_norm : [n_embd, hc, T]
concat : [2*n_embd, hc, T]
```

The prototype changes only the shape passed to `build_lora_mm(nextn.eh_proj)`:

```cpp
ggml_tensor * eh_in = ggml_concat(ctx0, e_norm, h_norm, 0);

if (mtp_eh_proj_flatten) {
    eh_in = ggml_reshape_2d(ctx0, eh_in, 2*n_embd, hc*n_tokens);
    res_hc = build_lora_mm(layer.nextn.eh_proj, eh_in);
    res_hc = ggml_reshape_3d(ctx0, res_hc, n_embd, hc, n_tokens);
} else {
    res_hc = build_lora_mm(layer.nextn.eh_proj, eh_in);
}
```

For Qwen3.8-Flash-Next at `T=1024`:

```text
OFF: M=2560, N=4,    K=5120, batch=1024
ON : M=2560, N=4096, K=5120, batch=1
```

The arithmetic and logical column order are unchanged. `ggml_concat` creates
the contiguous source tensor required by `ggml_reshape_2d`, and the matmul
output is reshaped back before HC mixing.

### Important experiment guard

The flatten path additionally requires `draft_prefill_kv_crop == true`.
Therefore it is active only for the existing Stage-B zero-output Draft
catch-up path:

- MTP enabled with masked Draft NextN state;
- `n_outputs == 0`;
- one sequence;
- no training / unified KV;
- dense ratio-zero Draft block;
- `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`.

This is intentional. The initial experiment is a **PP-only** optimization:
ordinary speculative-generation MTP graphs keep the previous `eh_proj`
shape. That prevents TG/generation behavior from becoming a second causal
variable.

The environment variable is read when the graph is built. Changing it on an
already-running context whose graph can be reused is unsupported; the
benchmark harness launches a fresh process for each A/B arm.

## Benchmark plans

### Non-profiled speed plan

```text
tools/evox2/benchmark/configs/qwen38-r5-mtp-eh-proj-flatten.psd1
```

Build key:

```text
R5MtpEhProjFlattenVulkan
```

Jobs:

- `eh-proj-short`: functionality A/B
- `eh-proj-64k-abba`: primary A1/B1/B2/A2 causal test
- `eh-proj-128k-abba`: run only if the 64k result is clearly positive
- `eh-proj-128k-mtp-off-control`: optional after a positive 128k result to
  update the residual MTP penalty with the same binary

Stage-B is ON for every A/B speed run. The sole variant switch is:

```text
A: LLAMA_MTP_EH_PROJ_FLATTEN=0
B: LLAMA_MTP_EH_PROJ_FLATTEN=1
```

QSA union remains ON with minimum KV 32768, matching the retained Stage-B
cohort. Graph/RGP/perf diagnostics are explicitly unset for timing runs.

### RGP plan

```text
tools/evox2/benchmark/configs/qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1
```

This plan enables the existing role markers, dispatch trace and detailed MTP
phase trace. Its PP/TG numbers are **not** benchmark results.

It provides both `A-flat-off` and `B-flat-on`. Normally profile B first.
A is optional if an exact same-binary GPU comparison is needed beyond the
retained b11618 reference.

## Local build

After fetching and switching to the branch:

```powershell
git fetch origin
git switch investigation/r5-mtp-eh-proj-flatten-20261016

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r5-mtp-eh-proj-flatten `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

Do not overwrite or rebuild the retained b11618 Stage-B directory.

Add a machine-local build entry to ignored
`tools/evox2/benchmark/configs/local.psd1`:

```powershell
R5MtpEhProjFlattenVulkan = @{
    BinDir = 'C:\path\to\this-worktree\build-vulkan-r5-mtp-eh-proj-flatten\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

Keep the existing `UnslothPle16`, `UnslothMtp`, `64k` and `128k` keys.

## Measurement sequence

### 0. Plan validation

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten.psd1 `
  -PlanOnly
```

Confirm that the expanded conditions use one executable/build key and that
the A/B environment differs only in `LLAMA_MTP_EH_PROJ_FLATTEN`.

### 1. Short functionality gate

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten.psd1 `
  -OnlyJob eh-proj-short
```

Required before long runs:

- both arms exit 0;
- model / Draft load succeeds;
- requested context is reported correctly;
- MTP remains active;
- no graph allocation/assertion/backend failure;
- generated text is coherent;
- Draft acceptance does not collapse.

Strict byte identity is not required at this stage. A different matmul tile can
change floating-point accumulation order even though the operation is
algebraically equivalent.

### 2. 64k ABBA — primary decision point

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten.psd1 `
  -OnlyJob eh-proj-64k-abba
```

Expected workload remains the retained real 64k input (~61,789 prompt tokens),
f16 K/V, batch 2048, ubatch 1024, MTP DraftMax 2, QSA union ON/minKV32768.

Validate before computing means:

- 4/4 runs status OK / exit 0;
- identical executable SHA/runtime artifact across A1/B1/B2/A2;
- prompt token count matches across runs;
- P-MODE starts and ends in Performance with no transition warning;
- ADLX high-load state remains Performance-like;
- no diagnostic environment accidentally enabled;
- acceptance/output behavior has no obvious regression.

Then compare:

```text
A mean = mean(A1, A2)
B mean = mean(B1, B2)
PP gain = B/A - 1
prompt-time reduction = mean(A prompt sec) - mean(B prompt sec)
```

Proceed to 128k when both B runs are directionally better than the A runs and
the mean effect clearly exceeds run-to-run drift. If the result is borderline,
prefer one repeat 64k cohort or the focused RGP check before spending four long
128k runs.

### 3. 128k ABBA — only after positive 64k

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten.psd1 `
  -OnlyJob eh-proj-128k-abba
```

Use the same validation rules as 64k. Do not compare the absolute new values
directly to a different-build cohort without labeling that limitation.

If the 128k result is positive, optionally run the same-binary MTP-OFF control:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten.psd1 `
  -OnlyJob eh-proj-128k-mtp-off-control
```

That control is a residual-gap estimate, not a repeated MTP-OFF confidence
interval unless additional OFF runs are added.

### 4. Focused RGP after speed confirmation

Validate the profiling plan first:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1 `
  -PlanOnly
```

For the first capture, select B only:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1 `
  -OnlyVariant B-flat-on
```

Use the new dispatch trace to calibrate the Draft range near 51–53k. **Do not
reuse the retained b11618 dispatch ordinals.**

The old captured Stage-B geometry was:

```text
matmul_q8_0_q8_1_0 (80,1,1024)
~56.51 / 58.64 ms
```

The shape model predicts a large-tile, batch=1 dispatch near:

```text
(20,32,1)
```

for a 128x128 Q8 coopmat tile. The exact shader suffix and dispatch must be read
from RGP rather than assumed.

RGP success criteria:

- `role=draft` still contains no Draft `FLASH_ATTN_EXT` in the Stage-B
  zero-output graph;
- `mtp_eh_proj` is no longer the old `(80,1,1024)` dispatch;
- measure the new main matmul and parent `MUL_MAT mtp_eh_proj` inclusive time;
- record pipeline VGPR / occupancy, but do not treat occupancy alone as cause;
- compare whole Draft graph duration as well as the individual kernel.

If needed, repeat the same profiling plan with
`-OnlyVariant A-flat-off` for an exact same-binary RGP control.

## Correctness before merge

A positive PP result is not enough to merge.

The final gate should compare Stage-B Draft K/V state between flatten OFF and
ON at selected prompt positions, or use an equivalently strong numerical
continuation/logit test. Expected differences from changed accumulation order
must be quantified rather than silently assumed to be zero.

Also verify:

- prompt catch-up works at short / 64k / 128k;
- speculative generation after catch-up remains healthy;
- acceptance does not materially regress;
- MTP OFF is unaffected;
- flag OFF reproduces the existing Stage-B behavior.

Until that gate passes, keep the feature opt-in and investigation-only.

## Decision tree

```text
build
  -> short A/B
     -> 64k ABBA
        -> no/negative effect: stop; document
        -> ambiguous: repeat 64k or RGP first
        -> clear positive:
             -> 128k ABBA
             -> optional same-binary MTP-OFF residual control
             -> focused RGP
             -> numerical K/V correctness gate
             -> only then consider integration / broader MTP use
```

The separate "split HF fc_embedding / fc_hidden" idea remains a later stage.
Do not combine it with this experiment; the current test intentionally changes
only the matmul geometry.


## 2026-10-16 native benchmark results

Prototype build: **b11659-c192befce**, Vulkan, Clang 20.1.8.

- executable SHA-256: `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`
- runtime artifact: **Verified**
- runtime digest: `0b8087e7c2a1ac99a6223c576dc5d6f9c19b77d2e61f3ac63bebd298333b56f8`
- 96GB UMA; f16 K/V; batch 2048; ubatch 1024
- Stage-B Draft KV-only ON and QSA union ON/minKV32768 in both A/B arms
- A/B causal switch: `LLAMA_MTP_EH_PROJ_FLATTEN=0/1`

### Short gate

Both short runs completed successfully. Draft acceptance was identical
(**17/27 = 0.62963**) and generated content was identical after stripping the
final timing-summary line (SHA-256
`69bd5ec01825cf42c1efbad09dc3a6515ce7863518a28755027c402d1929a0ce`).
The very large short PP delta is **not** used as speed evidence because the
first process is exposed to cold-start effects.

### 64k ABBA

Prompt: **61,789 tokens**. Order: A1/OFF -> B1/ON -> B2/ON -> A2/OFF.

| Run | Flatten | PP tok/s | Prompt s | TG tok/s |
| --- | --- | ---: | ---: | ---: |
| A1 | OFF | 344.64 | 179.28540 | 29.24 |
| B1 | ON  | 349.89 | 176.59527 | 29.79 |
| B2 | ON  | 348.89 | 177.09986 | 29.87 |
| A2 | OFF | 344.59 | 179.31212 | 30.00 |

Means:

- OFF: **344.615 tok/s**, **179.298760 s**
- ON: **349.390 tok/s**, **176.847565 s**
- gain: **+1.386% PP**
- prompt saving: **2.451195 s (-1.367%)**

Draft acceptance was exactly **295/430 = 0.68605** in all four runs. P-MODE
started/finished at Performance with no transition warning; ADLX high-load
power was **117.174–117.744 W**, Performance-like. Normalized generated content
was byte-identical across all four runs (SHA-256
`9d4fcdae21a66b926edc1a4b467f426f33d0cd892d2ce35dffd120cce177da4b`).

### 128k ABBA

Prompt: **126,253 tokens**. Order: A1/OFF -> B1/ON -> B2/ON -> A2/OFF.

| Run | Flatten | PP tok/s | Prompt s | TG tok/s |
| --- | --- | ---: | ---: | ---: |
| A1 | OFF | 320.93 | 393.39638 | 23.85 |
| B1 | ON  | 323.79 | 389.92786 | 23.87 |
| B2 | ON  | 324.35 | 389.25083 | 23.81 |
| A2 | OFF | 318.28 | 396.67002 | 24.02 |

Means:

- OFF: **319.605 tok/s**, **395.033200 s**
- ON: **324.070 tok/s**, **389.589345 s**
- gain: **+1.397% PP**
- prompt saving: **5.443855 s (-1.378%)**

A1->A2 shows some drift, but the ABBA ordering places both ON runs between the
controls and both B runs remain faster than A1. Draft acceptance was exactly
**295/429 = 0.68765** in all four runs. P-MODE remained Performance; ADLX
high-load power was **115.326–115.415 W**, Performance-like. Normalized
generated content was byte-identical (SHA-256
`31ae6e0aa59265e19609327ff389e32c1079fe581125ec69dbdda6959fef594d`).

### Scaling interpretation

64k -> 128k prompt tokens grow **2.043x**. The measured absolute prompt-time
saving grows **2.221x**, from **2.451 s** to **5.444 s**, while the relative PP
gain is nearly unchanged (**+1.386% / +1.397%**).

Approximate observed saving per 1024 prompt tokens:

- 64k: **40.6 ms**
- 128k: **44.2 ms**

This strongly supports a repeated Draft catch-up cost reduction rather than a
fixed startup effect. It is consistent with the retained b11618 RGP finding
that old unflattened `mtp_eh_proj` consumed ~56.51/58.64 ms per local
1024-token Draft graph, but the new kernel time has **not yet been measured**.

Do not subtract the new 5.444 s directly from the historical b11618
~11.608 s Stage-B residual and call the result exact: those are different
binary/session cohorts. A same-binary MTP-OFF control remains available later.

## Exact next-session handoff: RGP first

**Do not run another PP cohort first. Resume with the prepared 64k RGP
flatten-ON run.**

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1 `
  -PlanOnly

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1 `
  -OnlyVariant B-flat-on
```

Use the **new** dispatch trace to find a Draft graph near ~51–53k. Do not reuse
the retained b11618 dispatch ordinal.

RGP questions:

1. Does old `matmul_q8_0_q8_1_0 (80,1,1024)` become a batch=1 large-tile
   dispatch (source prediction: approximately `(20,32,1)`)?
2. What is the new main `mtp_eh_proj` kernel duration versus old
   ~56.51/58.64 ms?
3. What is the new parent `MUL_MAT mtp_eh_proj` inclusive time?
4. What is the new whole `role=draft` graph duration versus old
   61.662/63.846 ms?
5. Does the fully expanded Stage-B Draft graph still contain no
   `FLASH_ATTN_EXT`?
6. Record VGPR/occupancy only as secondary evidence.

If B is clear, same-binary A-flat-off RGP is optional. After GPU attribution,
move to the numerical Draft K/V correctness gate before merge/integration.

## 2026-10-19 Vulkan flatten-ON RGP closure and profiling-overhead reference

**Status: focused flatten-ON RGP Event timing visually captured; numerical Draft K/V equality and same-binary flatten-OFF RGP remain open.** This is an evidence checkpoint based on the uploaded native 64k ZIPs and five consecutive top-to-bottom RGP Event timing screenshots; the raw `.rgp` file was **not** supplied. The RGP export's SQTT warning state and shader pipeline VGPR/occupancy have **not** been confirmed from the screenshots.

### Same-binary run provenance and timings

All native runs used the **same** compiled Vulkan b11659-c192befce, SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, verified runtime digest `0b8087e7c2a1ac99a6223c576dc5d6f9c19b77d2e61f3ac63bebd298333b56f8`; identical command, arguments, model/Draft/input identities, effective conditions and environment. Both runs: 61,789 input, 512 output; 64k context; f16 KV; 96GB UMA; Vulkan QSA union ON/minKV32768; MTP Stage-B `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` and flatten `LLAMA_MTP_EH_PROJ_FLATTEN=1`; dispatch trace `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1`, RGP role markers `GGML_VK_MTP_PP_RGP_MARKERS=1`, phase trace `LLAMA_MTP_PP_TRACE=detail`; P-MODE Performance at start/finish; consistent ADLX. Native ZIPs contain logs, not the `.rgp` binary.

| Cohort | ZIP run ID | SHA256 of uploaded ZIP | PP tok/s | Prompt seconds | TG tok/s | ADLX GPU high-load avg |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 2026-10-16 untraced ABBA B-flat-on mean | 64k B1/B2; retained report above | refer to prior report | **349.390** | **176.847565** | separate per-arm values above | Performance-like |
| 2026-10-19 19:40 diagnostic trace, **no RGP capture** | `20261019-194034-647-cli-vulkan-b11659-ctx65536-024dd180ad0f` | `a080a377a386cd6f9c85b8a36cf6c2227688bb0495a4f38db8343faaf1ecaabf` | **330.50** | **186.955460** | 28.48 | **109.333 W** |
| 2026-10-19 19:53 diagnostic trace **with RGP capture** | `20261019-195315-755-cli-vulkan-b11659-ctx65536-024dd180ad0f` | `0130198b570c4ec431eb09bbc1484d570830196d3af2feef39e4a62d2584fdb3` | **312.20** | **197.911840** | 28.37 | **110.719 W** |

Both 10/19 runs: native `Status=OK`, exit 0, accepted **295/430**; MTP mode Performance -> Performance, no warnings. The exact model/output and environmental identities are equal between the two diagnostic runs, including monitor and tracing flags. The measured PP rate differences are **reference observations, not isolation-proven causal overhead**:

| Comparison | PP-rate difference | Prompt-time difference | Prompt-time ratio |
| --- | ---: | ---: | ---: |
| Trace-only vs normal ABBA B mean | **-5.41%** | **+10.108 s** | +5.72% |
| Trace+RGP vs normal ABBA B mean | **-10.64%** | **+21.064 s** | +11.91% |
| Trace+RGP vs trace-only | **-5.54%** | **+10.956 s** | +5.86% |

Important: “trace-only” still had **RGP role markers enabled and the dispatch/phase trace enabled**; it means only that **Radeon Developer Panel did not capture an RGP**. This is not a factorial test for each individual marker/trace. Inter-run GPU/runtime variation and profiling-arm state are not controlled by randomized repetitions. The ABBA reference was on 10/16, so cross-day differences must **not** all be attributed to instrumentation. RGP observations and timings are **never** substituted for the untraced ABBA PP benefit.

### Draft dispatch and RGP screenshots

Both 10/19 diagnostic `stderr.log` sets contain **986 contiguous graph records**, and the targeted interval near ~51k prompt tokens is exactly:

```text
EVOX2_MTP_GRAPH role=draft [215195, 215215) 20 dispatch / 32 nodes
EVOX2_MTP_GRAPH role=draft [215215, 215235) 20 dispatch / 32 nodes
```

The RDP Auto capture setting used: **Dispatch range start 215180, count 64, SQTT High**. The five supplied Event timing screenshots traverse both Draft graphs from top to bottom, exposing a full event tree including HC and K/V write paths. Exact **RGP screenshot-derived** local timings:

| Event | Flatten-ON Draft 1 | Flatten-ON Draft 2 |
| --- | ---: | ---: |
| `EVOX2_MTP_GRAPH role=draft` inclusive duration | **9,237.963 us (9.238 ms)** | **9,369.707 us (9.370 ms)** |
| `MUL_MAT node_10` parent / `EVOX2_MTP_MATMUL` group | **4,678.655 us** | **4,751.532 us** |
| `quantize_q8_1_x4 (81920,1,1)` | **634.449 us** | **705.248 us** |
| `matmul_q8_0_q8_1_1 (40,64,1)` main kernel | **4,042.842 us** | **4,045.548 us** |
| `FLASH_ATTN_EXT` inside these Draft graphs | **not present** | **not present** |
| K/V cache-write evidence | visible `SET_ROWS mtp_draft_cache_write_v` | visible `SET_ROWS mtp_draft_cache_write_v` |

Previous *different-binary* b11618 unflattened Stage-B RGP around ~50–52k KV was Draft inclusive **61,661.875 / 63,845.977 us** and unflattened Q8 main **56,509.501 / 58,642.678 us**, dispatch `(80,1,1024)`. Against those historical local event times, the new main kernels are ~**92.85% / 93.10% shorter**, and the Draft graph durations ~**85.02% / 85.32% shorter**. **These are cross-binary RGP indications, not a same-binary causal GPU A/B.**

Shape inference: current `MUL_MAT node_10` is consistent with the flattened `mtp_eh_proj` (5120 input rows flattened to 4096 HC-token columns); the source model predicted `(20,32,1)` only for a 128x128 tile, while the actual `(40,64,1)` indicates the backend selected a different workgroup tile. The screenshots did **not** literally label `node_10` as `mtp_eh_proj`; source/shape or an OFF counterpart should validate its exact identity. Do not report pipeline occupancy or VGPR until viewing the relevant Pipeline state tab.

All five screenshots together include HC-mix kernels and K/V write nodes and show **no Draft `FLASH_ATTN_EXT`** in the two captured zero-output Draft graphs. This confirms Stage-B FA pruning persists with flatten ON in the sampled RGP interval, **not** Draft K/V numerical equivalence or universal absence in generation-time graphs. The inclusive group and nested Q8/quantize events must **not** be added together as independent time.

### Implication, controls and next action

The roughly 50ms/1024 Draft difference compared with b11618 is consistent in scale with **2.451s** saved over 61,789 prompt tokens in the normal same-binary 64k ABBA, but exact integration/scheduler overlap prevents using local RGP as an additive PP decomposition. The decisive same-binary PP evidence remains +1.386% at 64k and +1.397% at 128k.

**Next recommended step:** a bounded **same-binary A-flat-off RGP** near the identical ~51k KV depth if the user wants to turn this cross-binary GPU comparison into a direct control; remeasure A's dispatch indexes and use only the prepared A variant. It is acceptable to stop RGP after the two clearly measured ON graphs and proceed directly to **numerical Draft K/V parity**, continuation and rollback if GPU instrumentation time is better spent elsewhere. Preserve the b11659 executable. Numerical K/V correctness remains a prerequisite to any source integration.

## 2026-10-19 20:10 — A-flat-off trace and B occupancy follow-up

A source-control run `LLAMA_MTP_EH_PROJ_FLATTEN=0` completed normally on the **same b11659 Vulkan binary**, SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, identical input/model/trace flags. A trace-only: **PP326.56 tok/s / 189.213430s, TG28.61 tok/s**, Draft 295/430, P-MODE Performance→Performance, ADLX high-load avg 110.591W. Archive: `20261019-201026-929-cli-vulkan-b11659-ctx65536-30acd689bd50.zip`; SHA256 `f5cc9e8c4ca2909fa03fbaa76a96112458d9903c48048633f21f0f34d3d28749`.

**Key control discovery:** A and B have the **same** `role=draft` half-open Vulkan dispatch intervals near 51k KV: `[215195,215215)` and `[215215,215235)`, **20 dispatches per graph**. A graphs have **30 nodes**, B graphs **32 nodes** (extra reshape/view nodes). **Correction:** flatten did **not** reduce the number of dispatches in this same-binary A/B; it changes the key GEMM geometry and shader latency. Since A's ordinals were measured, reuse **RDP Auto capture Start=215180, Count=64, SQTT High** for the exact A GPU comparison, then verify both Draft events are present. The diagnostic trace-only B PP 330.50 vs A 326.56 is **+1.21%**, a non-repeated single-pair observation; the untraced ABBA +1.386% remains authoritative.

**Additional B RGP Pipeline state screenshot**: `matmul_q8_0_q8_1_1 (40,64,1)` runs wave32, 128 threads/workgroup, VGPR 185 used/192 allocated, SGPR 45 used/128 allocated, LDS 20,480B/group, no spill, theoretical occupancy **6/16 wavefronts/SIMD, LDS-limited**. Historical unflattened b11618 kernel occupancy 3/16 is a different-binary reference, not a proof that occupancy is the primary cause.

**Target→Draft compute-idle interval**: B Wavefront occupancy screenshot shows approximately 40–45ms with no visible compute wavefronts between late Target and Draft work. The source in `common_speculative_impl_draft_mtp::process()` calls `llama_get_embeddings_nextn(ctx_tgt)`, prepares an embedding batch on the host, then calls `llama_process(ctx_dft,...)`; host synchronization, target hidden-state readback, copy or submit latency are candidate contributors. The GPU Compute timeline **cannot show CPU work or uniquely attribute a DMA transfer**. At prompt `end_pos=51199`, A CPU phase trace had `hidden_get_us=3309910, draft_us=94569, prepare_us=19, verify_copy_us=22434`; B trace-only had `hidden_get_us=3242438, draft_us=42064, prepare_us=18, verify_copy_us=22595`. `hidden_get_us` **includes waiting for previously queued Target GPU compute**, so it is not 3.3s of CPU-only processing and cannot be equated with the local RGP idle gap. A host/GPU timestamp correlation would be needed to distinguish CPU, sync, memcpy or GPU queue idleness. Do not branch into that optimization before the current A RGP and Draft K/V numerical correctness gate.

## 2026-10-19 20:22 — same-binary A-flat-off RGP closes flatten GPU attribution

**Evidence:** Seven uploaded RGP Event timing / Pipeline state / Wavefront occupancy screenshots plus native diagnostic ZIP `20261019-202229-773-cli-vulkan-b11659-ctx65536-30acd689bd50.zip`, SHA256 `cd19ed5c54d3c6540efd33a570695e801ede2043a36a651d727cca3ec6a5bd1e`. The raw `.rgp` file was not uploaded, so source is screenshot-derived events rather than an exported machine-readable GPU trace. All A/B RGP captures were made using the *same b11659-c192befce*, exe SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`, runtime artifact digest `0b8087e7c2a1ac99a6223c576dc5d6f9c19b77d2e61f3ac63bebd298333b56f8`; same model/input/MTP Stage B ON/64k (61,789 actual tokens)/f16 KV/QSA union minKV32768/ubatch1024, same debug/trace flags, effective flatten OFF on A vs ON on B. Both user-supplied RGP event trees sample the same two zero-output 1024-token Draft graphs around 51–53k prompt/KV. Graph dispatch intervals are identical `[215195,215215)` and `[215215,215235)` (20 each; A 30 graph nodes, B 32 reshape-related nodes). User RDP settings Start215180/Count64/SQTT High.

### Direct controlled GPU measurements (microseconds)

| Event from Event timing | A OFF Draft 1 | B ON Draft 1 | A OFF Draft 2 | B ON Draft 2 |
| --- | ---: | ---: | ---: | ---: |
| `EVOX2_MTP_GRAPH role=draft` inclusive | **61,014.624** | **9,237.963** | **63,890.600** | **9,369.707** |
| `MUL_MAT mtp_eh_proj-48` / B `MUL_MAT node_10` parent inclusive | **56,507.117** | **4,678.655** | **59,145.802** | **4,751.532** |
| `quantize_q8_1_x4` | 640.590 | 634.449 | 656.664 | 705.248 |
| main Q8 matmul dispatch | **55,865.803** | **4,042.842** | **58,487.483** | **4,045.548** |
| main dispatch | `matmul_q8_0_q8_1_0 (80,1,1024)` | `matmul_q8_0_q8_1_1 (40,64,1)` | `(80,1,1024)` | `(40,64,1)` |

Each A graph has an explicitly named `MUL_MAT mtp_eh_proj-48`. In B that source projection is reshaped into `MUL_MAT node_10`; the same surrounding graph sequence, quantize node and flattened shape support identifying it as the corresponding projection. Main Q8 kernel reductions **92.763% / 93.083%** (13.82x / 14.46x faster); entire Draft graph reductions **84.859% / 85.335%** (6.61x / 6.82x faster). Per Draft graph **51.777ms / 54.521ms** less inclusive GPU time; main Q8 reduction **51.823ms / 54.442ms**, accounting for almost the full graph reduction. Rest-of-graph envelope (`Draft inclusive - main Q8`) stays approximately **5.149/5.403ms A vs 5.195/5.324ms B**; this difference is descriptive and does not establish an exact exclusive operator-time decomposition.

**Kernel Pipeline state**, same-binary: A wave32, VGPR **256/256**, SGPR **48/128**, LDS **10240B**, no spill, theoretical occupancy **3/16 (LDS-limited)**; B wave32, VGPR **185 used/192 allocated**, SGPR **45/128**, LDS **20480B**, no spill, theoretical occupancy **6/16 (LDS-limited)**. Dispatch group size also changes (A 32 threads/workgroup, B 128). Occupancy correlates with much better tile shape and GEMM performance but is not by itself proven causal.

Both sampled Stage-B Draft graphs retain cache-write events and **no FLASH_ATTN_EXT** appears in the inspected whole trees; these observations do **not** certify numerical Draft K/V equality or ensure generation-time Draft graphs omit attention.

### Native A capture result and instrumentation reference

A capture 20:22 status OK, exit0, MTP accepted **295/430**, generated512, P-MODE Performance→Performance, ADLX high-load average **111.354W / Performance-like**, PP **309.14 tok/s** / prompt **199.876480s**, TG **28.38 tok/s**. A trace-only 20:10 (identical source/args/env, no RGP capture): PP **326.56 tok/s / 189.213430s**. Compared to its same-arm trace-only run, A captured PP rate was **-5.33%** and prompt time **+10.663s (+5.64%)**. Compared with 10/16 normal ABBA A mean **344.615 tok/s**, A trace+RGP is **-10.29%**; cross-day, nonrandomized descriptive only. Similar B trace-only **330.50** vs trace+RGP **312.20** (-5.54%); normal B ABBA mean **349.390**. Profiling runs are *not* new performance baselines and changes cannot be causally attributed exclusively to RGP given possible between-run variation.

### Closure and next action

**Mechanism/RGP gate PASSED for the tested Windows Vulkan 64k Stage-B zero-output Draft path:** shape flattening moved narrow batched `eh_proj` Q8 GEMM into large unbatched Vulkan GEMM, saving ~52–54ms of GPU time per observed 1024-token Draft graph while retaining the FA-bypassed cache-write path. The independent *normal*, marker-free same-binary ABBA still establishes whole-prompt PP gain **+1.386% at 64k / +1.397% at 128k**; do not confuse RGP-local 6.7x Draft speed with whole-inference PP speed.

**Stop GPU profiling for now. Next required gate before integration: numerical K/V correctness and continuation/rollback** across (C) Stage-B OFF, (A) Stage-B ON/flatten OFF, (B) Stage-B ON/flatten ON. Existing text/acceptance identity is insufficient. This report is *not* a declaration that any experimental source is integrated into pinned r5.

