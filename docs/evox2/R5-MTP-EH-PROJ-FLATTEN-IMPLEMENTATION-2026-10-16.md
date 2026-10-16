# r5 MTP `mtp_eh_proj` flatten prototype and measurement plan — 2026-10-16

**Status: SOURCE + BENCHMARK PLANS COMMITTED; WINDOWS BUILD / NATIVE TIMING NOT YET RUN.**

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
