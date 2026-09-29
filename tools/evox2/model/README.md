# PLE layout conversion

## Attribution

The actual PLE tensor conversion algorithm used here is **not authored by
this repository**.

External source:

```text
Repository:
https://github.com/LaurentZuijdwijk/llama.cpp

Script:
gguf-py/gguf/scripts/gguf_split_ple_heads.py
```

The external repository is MIT licensed.

`Convert-Unsloth-Ple16.ps1` in this repository is only a wrapper around that
external script. It adds:

- local path validation
- source-checkout Git identity
- converter-script SHA-256
- input/output file identities
- progress heartbeat
- conversion logs
- post-conversion layout verification
- an `evox2-conversion.json` provenance sidecar

The external Python converter itself is deliberately **not copied into this
repository**, which keeps authorship and provenance unambiguous.

## What the external converter does

The external script auto-detects the qwen4exp PLE layout.

For a joined input it splits:

```text
per_layer_token_embd.weight
```

into per-head tensors:

```text
ple_ngram_embd.N.weight
```

using the GGUF file's own:

```text
qwen4exp.ple.head_offsets
qwen4exp.ple.head_vocab_sizes
```

The external script documents that the quantized tensor bytes are copied
without dequantization/requantization when splitting the heads.

It also supports the reverse operation when the input already contains the
full per-head layout.

## Wrapper usage

Point `-SourceForkRoot` at a local checkout of the LaurentZuijdwijk fork:

```powershell
.\tools\evox2\model\Convert-Unsloth-Ple16.ps1 `
  -SourceForkRoot C:\path\to\LaurentZuijdwijk-llama.cpp `
  -InputFile C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf `
  -OutputFile C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf `
  -DryRun
```

After checking the source commit and converter hash shown by `-DryRun`,
remove `-DryRun` to perform the conversion.

By default, huge model files are not SHA-256 hashed because that adds another
full pass over tens of gigabytes.

Use:

```powershell
-HashModels
```

when a complete content hash is worth the extra time.

## Existing PLE16 model

An already-converted model should not be described as being converted by the
Phase 5 PowerShell wrapper if that wrapper did not exist at the time.

For historical results, keep the factual wording:

```text
Converted with gguf-py/gguf/scripts/gguf_split_ple_heads.py
from LaurentZuijdwijk/llama.cpp.
```

The wrapper and sidecar are for future reproducible conversions.

## Verification helper

`verify-ple-layout.py` is a small local inspection helper authored for this
tooling. It does not convert tensor data.

It checks:

- qwen4exp PLE metadata presence
- joined vs per-head layout
- expected number of head tensors
- each head's row count against the GGUF metadata

The PowerShell wrapper runs it automatically unless `-SkipVerify` is used.
