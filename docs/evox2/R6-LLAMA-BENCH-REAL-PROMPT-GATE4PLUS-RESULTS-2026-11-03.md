# r6 llama-bench real prompt: Gate 4+ verification (2026-11-03)

Status: **PASS**. Existing Vulkan b12032, no C++ changes. Branch: `feature/r6-llama-bench-real-prompt-20261103`.

Related history: [Gate 1-4](R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md).

## Inputs and provenance

- Token log: `evox2-bench-slice-fit-token-20261103-121720.zip`
- Fit log: `evox2-bench-slice-fit-fit-20261103-121734.zip`
- Native C++ blob: `cd551f9a67a0975423da022342cb694bd772f02f`.
- Fit executable: `llama-bench.exe` SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`, build `c4ddd239b` / b12032.
- GPU/backend: AMD Radeon 8060S / Vulkan. Model: Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.

## Token: 12/12 PASS

The exact `select_prompt_tokens()` function was extracted from the current C++ and compiled separately (CMake, Clang 20.1.8). Configure, build and executable returned exit code 0. The Golden test printed `TOTAL 12/12`.

Cases: `head5`, `headtail5`, `headtail4`, `head1`, `headtail1`, `head0`, `headtail0`, `full10`, `negative_length`, `overlong_length`, `headtail257`, `headtail256`. Odd 257 = first 129 + last 128. Even 256 = first 128 + last 128.

Scope: verifies the actual selection function on known token IDs, not a runtime dump of the token IDs produced by the model tokenizer. `verify-summary.csv` has a truncated T02 Details field; `T02-golden-ids.stdout.txt` independently confirms all 12 PASS.

## Fit: 2/2 PASS

Common: `-p 33 -n 0 -d 0 -r 1 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --no-warmup -v -o json -fitt 4096 -fitc 2048`, with the same real input SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`.

| Case | Explicit -c | Fit minimum -fitc | Observed actual n_ctx | Result |
|---|---:|---:|---:|---|
| F01-fitmin-over-ctx | 1024 | 2048 | **2048** | PASS, exit 0 |
| F02-ctx-over-fitmin | 4096 | 2048 | **4096** | PASS, exit 0 |

Both stdout JSON results report `fit_target=4096`, `fit_min_ctx=2048`, `n_prompt=33`, one sample and b12032. Verbose stderr explicitly reports both `llama_context: n_ctx` and `n_ctx_seq` as 2048/4096 respectively. In both cases 49/49 model layers were offloaded to GPU. This verifies the actual context selected for these two cases, not merely successful execution. These one-off 33-token speeds are not a performance comparison.

## Conclusion and next step

Gate 4 (16/16 native) + Gate 4+ (14/14) confirms **30/30 test-case behaviors**. The only Gate 4 false negative was Core C03's PowerShell log wrapping; native full-file mode succeeded. The source and binary have not been modified.

Next: Gate 5, controlled real-text vs random PP measurements. **Important:** the current text input provides only **61,777 model tokens** according to native progress. It cannot support `-p 65536`; a longer text input is needed for full 64Ki-token tests, otherwise use an equal lower prompt length (for example 61,440). Keep model, backend, build, batch, context, P-MODE and timing repetitions consistent.

Minor test-tool issues to address later: C03 line wrapping, truncated T02 Details CSV, F05 diagnostic message saying `--fit-target` when only `-fitc` was supplied.
