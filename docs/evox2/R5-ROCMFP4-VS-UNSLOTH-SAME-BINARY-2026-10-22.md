# ROCmFP4 FAST vs Unsloth IQ3 — same-binary Vulkan comparison (2026-10-22)

## Scope and sources

GMKtec Evo-X2, Windows/Vulkan, identical Stage-5 llama.cpp binary `b11561`, MTP OFF, normal dispatch. Targets are Agention ROCmFP4-FAST v2 PLE16 and Unsloth UD-IQ3_XXS PLE16. Input is the same ANLP ch3 corpus across sizes (not three independent domains). Temperatures 0, reasoning off, generation cap 512, f16 KV, -ngl 999 -ncmoe 0, -t/-tb 4, -b 2048, -ub 1024, --fa auto, P-MODE Performance and ADLX logging. Every context has ABBA four independent process runs (two per model).

Raw submitted archives:
- `20261022-130606-837-qwen38-stage5-rocmfp4-vs-unsloth-32k-abba.zip`
- `20261022-131344-441-cli-vulkan-b11561-ctx32768-183523a398ca.zip` (32k detailed logs)
- `20261022-133121-908-qwen38-stage5-rocmfp4-vs-unsloth-64k128k-abba.zip` (matrix plus detailed logs)

Measured with `tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1`, one build `R5RocmFpxStage5Vulkan`; models `AgentionRocmFp4FastPle16` and `UnslothPle16`. Per-run uniqueness provided through `EVOX2_ABBA_RUN` (no inference behavior change).

## ABBA PP and TG measurements

Values are tok/s, listed in chronological order. Averages are arithmetic means of two runs per model.

| Context | Prompt tokens | ROCmFP4 PP (runs) | Unsloth PP (runs) | ROCmFP4 PP avg | Unsloth PP avg | ROCmFP4 PP advantage | ROCmFP4 TG avg | Unsloth TG avg |
|---|---:|---|---|---:|---:|---:|---:|---:|
| 32k | 29,557 | 424.13 / 421.52 | 407.57 / 409.25 | 422.83 | 408.41 | +3.53% | 27.24 | 27.28 |
| 64k | 61,789 | 277.51 / 277.48 | 272.57 / 272.00 | 277.50 | 272.29 | +1.91% | 26.12 | 26.27 |
| 128k | 126,253 | 180.83 / 180.66 | 178.61 / 178.50 | 180.75 | 178.56 | +1.23% | 23.90 | 23.97 |

TG is effectively tied, with Unsloth slightly ahead (<1%). The PP advantage of ROCmFP4 shrinks as context grows. The difference may reflect changing attention-versus-weight-compute fractions, but this benchmark does **not** establish the cause. Each model's repeated PP readings are very close. The 32k and long-context runs consistently finished with exit 0; P-MODE remained Performance throughout and ADLX was recorded. 128k power consistency classification was Ambiguous for both models, **not** evidence of P-MODE switching.

32k GPU Vulkan model buffers were approximately ROCmFP4 88,645.69 MiB vs Unsloth 77,657.05 MiB, with 49/49 target layers offloaded in both cases. These buffer numbers are not total process memory.

## Output sanity and reproducibility

No obvious mojibake, uncontrolled repetition or incoherent Japanese observed in sampled generated answers. At 32k both copies for each model generated identical text at temperature 0. Unsloth stopped naturally at 479 generated tokens; ROCmFP4 reached the 512-token cap. At 64k both reached 512. At 128k Unsloth stopped at 481, ROCmFP4 at 512. A length cap is not itself an output-degeneration error.

Qualitative observation over related ANLP inputs: ROCmFP4 tended to mention individual authors/studies and details, while Unsloth tended to summarize methods into higher-level categories and limitations. This is **exploratory, not a verified quantization-specific quality trait**: inputs are all excerpts of the same source, and autoregressive divergences from small logit shifts can produce different levels of detail. A separate cross-domain, multi-prompt evaluation is needed to test that hypothesis; no winner in accuracy is inferred.

## Historical comparison boundary

Older Qiita write-up: https://qiita.com/ariera/items/d4026ad03775ebb1daa5

The older comparison differed substantially in binary/fork and upstream baseline, OS, Unsloth pre-PLE16 state, sampling/output settings, run count and measurement conditions. Its broad direction (ROCmFP4 PP lead / nearly tied TG) is useful qualitatively, **but its percent gaps must not be used as a controlled longitudinal speed improvement metric**. The present study isolates target GGUFs on one executable but does not equate their quantization accuracy.

## Follow-up: optimized r5 integration binary, MTP ON

Use separate matched plans on `build-vulkan-r5-noop-rocmfpx` (`R5NoopRocmFpxVulkan` local key): 32k ABBA gate, then 64k+128k continuous ABBA. Each target uses its own matching MTP sidecar (Agention ROCmFP4 or Unsloth Q8_0), DraftMax=2, DraftPMin=0.0, identical normal Vulkan/QSA union/DENSE/NOOP settings. This next experiment measures **model+draft system throughput and acceptance**, not a target-only quantization effect. Review matched draft compatibility and memory allocation at 32k before committing to longer workloads. P-MODE/ADLX and output checks remain mandatory.
