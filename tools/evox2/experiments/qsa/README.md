# QSA experiment helpers

The benchmark wrappers do not hard-code QSA behavior.

Instead, the matrix runner supports version-controlled environment overrides at
four levels:

```text
Defaults.Environment
Job.Environment
Case.Environment
Variant.Environment
```

Precedence follows the same pattern as benchmark parameters:

```text
Defaults < Job < Case < Variant
```

The matrix runner sets those environment variables only around the selected
child run and restores the original shell environment afterward.

The existing `Measure-LlamaCli.ps1` / `Measure-LlamaBench.ps1` automatically
record `GGML_*`, `LLAMA_*`, `HIP_*`, `ROCM_*`, `HSA_*`, `ROCBLAS_*`,
`VULKAN_*`, and `AMD_*` variables in each run's condition metadata.

This makes QSA A/B conditions visible without adding one-off PowerShell
launchers for every threshold.

## Important

An environment variable only has an effect if the selected llama.cpp source
and binary actually implement it.

Do not interpret a successful matrix run as proof that the binary honored an
unknown or absent QSA variable.

The example plans are intended for builds where the relevant QSA patch has
already been integrated and validated.

## Completed r2/r3 decode diagnostic

Before COMMON-004 implementation, a 64k Vulkan profile compared:

```text
R2Vulkan / union OFF
R2Vulkan / union ON
Common001Vulkan / current full-recompute QSA path
```

All runs used the same PLE16 model, 61,789-token input, MTP off, f16 K/V,
batch 2048, ubatch 1024, 128 generated tokens, and:

```text
GGML_VK_PERF_LOGGER=1
```

Steady single-token GPU graph time was approximately:

```text
r2 union OFF     44.18 ms/token
r2 union ON      44.31 ms/token
r3 COMMON-001    59.13 ms/token
```

The union switch was effectively neutral for steady decode. The r3 gap was
mostly explained by full-context pooled-summary reconstruction (`CONT`,
full-block RMS norm, and QSA-related RoPE), which is the target of COMMON-004.

The profiler adds substantial wall-clock overhead, so these profiling runs are
for operator attribution rather than absolute PP/TG reporting.

## Planned COMMON-004 pooled-key-cache A/B

COMMON-004 is the next source optimization target.

The r3 implementation is planned to expose:

```text
LLAMA_QSA_NO_POOLED_CACHE=1
```

The intended A/B shape is:

```text
A: pooled cache enabled (default)
B: LLAMA_QSA_NO_POOLED_CACHE=1
```

For r3, the kill switch should disable pooled-buffer allocation as well as the
pooled graph path so memory A/B remains meaningful.

The r3 plan also retains the Laurent decode-sized gate:

```text
LLAMA_QSA_POOLED_MAX_TOKENS=32
```

with `0` meaning no ubatch-size limit. Default 32 keeps the pooled path focused
on decode-sized ubatches and preserves the first-decode refill behavior seen in
the r2 profile.

Once COMMON-004 exists in r3, use the matrix runner's `Variant.Environment`
override so cache ON/OFF runs share the same binary and all environment
differences are recorded in `conditions.json`.

Initial order:

1. Vulkan 64k ON/OFF without PERF_LOGGER
2. Vulkan 128k ON/OFF
3. Vulkan 256k ON/OFF
4. ROCm 128k ON/OFF
5. fill remaining Vulkan/ROCm 64k/256k cells after the signal is established

Keep MTP off. Record PP, TG, memory use, graph reuse, and first-decode refill
behavior. Prefer interleaved/ABBA ordering for close results.

Do not create a committed COMMON-004 matrix example until the source port has
landed and the final runtime controls have been verified by smoke testing.

## Future COMMON-005 gather A/B

After COMMON-004, evaluate whether qwen4exp decode still performs attention over
the full KV cache even though QSA selects a much smaller top-k set.

The reference candidate is upstream PR `#28213`, which gathers selected K/V rows
before dense attention. Keep this as a separate patch and separate matrix A/B so
its effect is not mixed with pooled-summary caching.

A future r3 port should keep a runtime switch and a short-context gate. Do not
add a committed matrix definition until its actual r3 control name and gate are
known.

## Example: main Vulkan QSA threshold

See:

```text
qsa-union-thresholds.example.psd1
```

It demonstrates:

```text
GGML_VK_QSA_UNION_MIN_KV
```

with the previous Evo-X2 experiment values:

```text
26624
32768
```

The plan uses a synthetic long-context llama-bench PP case so it can serve as a
public/reproducible performance comparison once the QSA-capable build is
available.

Always inspect it first:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\experiments\qsa\qsa-union-thresholds.example.psd1 `
  -PlanOnly
```

## Example: MTP QSA threshold

See:

```text
mtp-qsa-threshold.example.psd1
```

It demonstrates:

```text
LLAMA_MTP_QSA_MIN_KV=49152
```

for the MTP prototype path.

This example is also a template only. Use it only with a build that contains
the MTP-QSA implementation.
