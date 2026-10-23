# PLE16 conversion for qwen4exp on r5

## Provenance and scope

This is **model conversion tooling**, not an inference-source optimization.
The algorithm is adapted from LaurentZuijdwijk/llama.cpp (MIT), previously
archived in our r2/legacy
`gguf-py/gguf/scripts/gguf_split_ple_heads.py`. The PowerShell wrapper and
layout verifier are based on r3/upstream-first `tools/evox2/model/`, and the
payload checker on r2 `tools/evox2/verify-ple16.py`.

The r5 adaptation uses the local `gguf-py` API and constructs
`ple_ngram_embd.N.weight` without the r2-only `GGUF.MODEL_TENSOR.PLE_NGRAM_EMBD`
symbol. No changes were made to llama.cpp inference code, GGUF upstream
library, build configuration or benchmark runner.

## Files

- `gguf_split_ple_heads.py`: input-shard discovery, preflight, joined-to-16
  split conversion and reverse join for investigation; memory-mapped reader,
  streamed tensor writes into a **single** GGUF; original inputs untouched.
- `Convert-Unsloth-Ple16.ps1`: Windows PowerShell 5.1 wrapper: metadata
  preview, source identity, disk space, detailed logs, output quarantine and
  verification; only split output is supported by the wrapper.
- `verify-ple-layout.py`: r3 output layout and head dimensions as JSON.
- `verify-ple16.py`: r2 input/output metadata, tensor names/types/shapes
  verification. Optional slow streaming per-tensor byte SHA-256 check.

## First use: huihui-ai Unsloth UD-IQ4_XS-based model

Make sure the entire original 3-shard GGUF set is in the same directory.
From **r5 worktree root**, in Windows PowerShell:

```powershell
$inputModel = 'C:\llama\models\huihui\unsloth-UD-IQ4_XS\Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00003.gguf'
$outputModel = 'C:\llama\models\huihui\unsloth-UD-IQ4_XS\Qwen3.8-Flash-Next-UD-IQ4_XS-ple16.gguf'
$converter = '.\tools\evox2\model\Convert-Unsloth-Ple16.ps1'

# Configuration/paths preview only (no GGUF parsing)
& $converter -InputFile $inputModel -OutputFile $outputModel -DryRun

# Real preflight: read split shards, check architecture/PLE metadata and rows;
# no large output is written.
& $converter -InputFile $inputModel -OutputFile $outputModel -PreflightOnly

# Convert. Runs preflight again, writes *.partial.gguf and publishes only
# after output layout + input/output tensor metadata checks both succeed.
& $converter -InputFile $inputModel -OutputFile $outputModel
```

By default `-Python python` is used. If it does not resolve to an interpreter
with NumPy and the local gguf-py dependencies, specify your Python executable:

```powershell
& $converter -InputFile $inputModel -OutputFile $outputModel -Python 'C:\path\to\python.exe' -PreflightOnly
```

The wrapper uses this checkout's `gguf-py` package, even when another gguf
package is installed. It records converter SHA-256, source Git identity and
model-file metadata; by default it does not hash whole models.

## Disk space, resources and failure behavior

- **This 87.24 GiB GGUF needs another full GGUF's worth of output space**.
  The wrapper checks available output-drive space against input shard bytes
  plus 1 GiB. The reported ~600 GB free space is ample for one conversion.
- Model input shards are not overwritten or deleted.
- The output is written to `<final-path>.partial.gguf` until both default
  verification checks succeed, then renamed to `<final-path>`.
- On interrupted/failed conversion or verification, the partial file is
  retained for examination. There is **no resume** functionality.
  Inspect/delete the partial file yourself before retrying.
- `-VerifyBytes` enables SHA-256 comparison for every model tensor, streaming
  through all original and resulting payloads. It substantially increases
  disk reads and elapsed time. Use it for strict correctness auditing.
- `-HashModels` requests full-file SHA-256 in the wrapper's provenance
  metadata; this is separate from `-VerifyBytes`, and also costly.
- Avoid simultaneous benchmark runs and large applications while converting.
- Conversion success alone does **not** prove GPU placement or long-context
  stability. Verify with llama.cpp.

## Recovering a completed 87 GiB partial GGUF (2026-10-24)

The initial r5 wrapper had a Windows PowerShell 5.1 `Start-Process`
ExitCode=$null problem and mistakenly checked the final output name before
verification. This is a wrapper failure, **not proof the Python converter
failed**. If the converter printed `100.0%` and `wrote ...partial.gguf`,
retain the partial file rather than rerunning conversion.

After pulling the fixed r5 branch:

```powershell
# Use the inputModel, outputModel and converter variables defined above.
# Inspect the existing partial first; it should be roughly the input size:
Get-Item -LiteralPath ($outputModel + '.partial.gguf') |
    Select-Object FullName, Length, LastWriteTime

# Verify the existing partial against the original three GGUF shards and
# then atomically rename it. No Python conversion or second 87 GiB write.
& $converter -InputFile $inputModel -OutputFile $outputModel -FinalizePartial -VerifyBytes
```

`-FinalizePartial` requires the existing `*.partial.gguf`, never overwrites
an already existing final GGUF, skips conversion, checks the 16-head layout and
all tensor metadata, and then renames the existing verified file. Add
`-VerifyBytes` (strongly recommended when the original exit code is unknown)
for a **streaming SHA-256 check of every tensor's payload**. It reads substantial
disk data but does not regenerate the GGUF.

If verification fails, the partial file stays in place for diagnosis. The
recovery invocation writes a new provenance record with
`RecoveredExistingPartial=true` and **does not claim the original Python
process exited with code zero**. Keep the original
`20261024-003604-840-ple-layout` converter logs separately as evidence.

The fixed normal conversion path now uses the same native
`GetExitCodeProcess` fallback already established in Measure-LlamaCli.ps1,
checks the partial rather than final path, and verifies before the rename.

## Testing converted model

`build-vulkan-clean`/`build-rocm-clean` at b11517 lack COMMON-001 split-PLE
support; **do not use those for the converted GGUF**.

Use the saved `build-vulkan-common001` / `build-rocm-common001` binaries
(or another build with split-PLE support), with `-ngl 999` and initial
`-c 4096`. Use the existing Evo-X2 benchmark resource monitor and advance
context lengths only after reviewing memory/paging logs.

For an existing `configs/local.psd1`, register a separate converted-model
entry with the new single-file `Path`; do not overwrite the original model
entry. Define BuildKeys pointing at the saved COMMON-001 binaries.

The previous UD-IQ3_XXS verification showed PLE heads on Vulkan GPU but on
ROCm CPU. **The huihui IQ4_XS model has not yet been converted or tested**.
Its backend placement must be measured independently.

## Source boundaries

The converter has been adapted to the checked-in r5 GGUF API and includes
checks for 16 heads and 3-shard discovery. There has been no real 87 GiB
model execution on the user's local Windows machine as part of this commit.
The Python conversion can also join a split model (direct invocation only),
but the wrapper and `verify-ple16.py` are specifically for joined-to-split.
