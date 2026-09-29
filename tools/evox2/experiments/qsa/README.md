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
