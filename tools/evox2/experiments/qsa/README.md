# QSA experiment helpers

Phase 5 does not hard-code QSA behavior into the benchmark wrappers.

Instead, the matrix runner now supports version-controlled environment
overrides at four levels:

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

The example plan is intended for a build where the relevant QSA patch has
already been integrated and validated.

## Planned COMMON-004 pooled-key-cache A/B

COMMON-004 is the next source optimization target.

The current reference implementations expose a same-binary cache-off control:

```text
LLAMA_QSA_NO_POOLED_CACHE=1
```

The intended A/B shape is:

```text
A: pooled cache enabled (default)
B: LLAMA_QSA_NO_POOLED_CACHE=1
```

The Laurent reference also has:

```text
LLAMA_QSA_POOLED_MAX_TOKENS=32
```

with `0` meaning no ubatch-size limit. Do not add that variable to an r3 matrix
plan until the COMMON-004 port explicitly retains it.

Once COMMON-004 exists in r3, use the matrix runner's `Variant.Environment`
override so cache ON/OFF runs share the same binary and all environment
differences are recorded in `conditions.json`.

The initial long-context order is Vulkan 128k, Vulkan 256k, and ROCm 128k with
MTP off. Fill the remaining 64k/256k backend cells after the first signal is
established. Prefer interleaved/ABBA ordering for close results.

Do not create a committed COMMON-004 matrix example until the final r3 runtime
controls are known.

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

The plan uses a synthetic long-context llama-bench PP case so it can serve as
a public/reproducible performance comparison once the QSA-capable build is
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
