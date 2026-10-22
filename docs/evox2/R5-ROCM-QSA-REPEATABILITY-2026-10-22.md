# ROCm Qwen3.8 QSA output repeatability — 2026-10-22

## Scope

This note closes the focused ROCm output-repeatability investigation that followed the Windows ROCm runtime-provenance work.

The practical question was not whether greedy decoding must always be byte-identical for normal use. The goal was to determine why Qwen3.8 Flash-Next on ROCm produced different text across otherwise identical fresh-process runs, because deterministic output is useful for:

- quality/regression checks;
- input-corpus comparisons;
- model/backend A/B work where output drift is a confounder.

The default performance path should remain the faster path unless determinism is explicitly required.

## Initial observation

The 2026-10-21 same-binary mixed-runtime vs unified-TheRock ABBA already showed that runtime packaging was not the cause:

- A1 != A2 inside the historical mixed-runtime arm;
- B1 != B2 inside the unified-TheRock arm;
- all runs used temp=0, fixed seed, MTP OFF, the same model/input/binary.

See [R5-ROCM-RUNTIME-PROVENANCE-ABBA-2026-10-21.md](R5-ROCM-RUNTIME-PROVENANCE-ABBA-2026-10-21.md).

## Fresh-process FA isolation

A follow-up 64k repeatability matrix used pure TheRock 10.0 and fresh llama-cli processes.

Conditions:

- Qwen3.8 Flash-Next PLE16;
- 61,789 prompt tokens;
- 512 generated tokens;
- temp=0;
- seed=1234;
- MTP OFF;
- f16 K/V;
- P-MODE Performance;
- fixed executable/runtime/model/input.

Results:

- **FA auto: 4/4 distinct outputs**.
- **FA OFF: 4/4 distinct outputs**.
- FA OFF reduced throughput substantially but did not restore repeatability.

The FA-OFF result rules out Flash Attention as a sufficient explanation for the run-to-run text drift.

A separate diagnostic using `HIP_LAUNCH_BLOCKING=1` was unsafe on this Windows/TheRock configuration: the process reached the prefill/decode transition and then terminated with Windows heap-corruption/fail-fast status. That condition is retained only as a crash diagnostic and is not part of the repeatability conclusion.

## QSA top-k hypothesis

Upstream issue ggml-org/llama.cpp#28497 reports a matching Qwen4Exp/Qwen3.8 failure mode: QSA top-k selection can return a different member set around exact-score ties, producing different greedy streams even when temperature is zero.

The pinned r5 Qwen4Exp graph selects pooled QSA blocks with:

~~~cpp
ggml_tensor * top_k = ggml_top_k(ctx0, score, n_top_pool);
~~~

The tested model uses:

~~~text
indexer_top_k = 2048
compress_ratio = 4
n_top_pool = min(n_pool, 512)
~~~

The investigation therefore replaced only the QSA selector with a deterministic full-sort selection:

~~~cpp
ggml_tensor * top_k =
    ggml_cont(ctx0, ggml_argsort_top_k(ctx0, score, n_top_pool));
~~~

The `ggml_cont()` is required because `ggml_argsort_top_k()` returns a view; the following Qwen4Exp reshape requires contiguous storage.

## Same-parent controlled A/B

To remove the earlier build-generation confounder, both sides were rebuilt from the same parent commit:

~~~text
512014dd3e751a23e2ac8b6a77146c00cf6a9cd2
~~~

Both builds used the corrected `Build-ROCm.ps1` unified TheRock 10.0 runtime policy:

- ROCm SDK 10.0.0;
- Clang 23;
- gfx1151;
- full HIP/BLAS DLL closure staged beside the executable;
- matching rocBLAS and hipBLASLt gfx1151 runtime-data trees;
- matching runtime DLL hashes/data-tree digests.

Control branch:

~~~text
investigation/rocm-qsa-topk-baseline-20261022
QSA selector: ggml_top_k(...)
~~~

Deterministic experiment branch:

~~~text
investigation/rocm-qsa-argsort-topk-20261022
QSA selector: ggml_cont(ggml_argsort_top_k(...))
~~~

### 64k results

| path | run | PP tok/s | TG tok/s | output |
| --- | --- | ---: | ---: | --- |
| `ggml_top_k` | r1 | 394.95 | 21.07 | distinct |
| `ggml_top_k` | r2 | 394.09 | 21.08 | distinct |
| `ggml_top_k` | r3 | 393.92 | 21.15 | distinct |
| `ggml_top_k` | r4 | 394.38 | 21.24 | distinct |
| argsort+cont | r1 | 382.38 | 20.04 | identical |
| argsort+cont | r2 | 382.37 | 20.06 | identical |
| argsort+cont | r3 | 361.98 | 20.06 | identical |
| argsort+cont | r4 | 380.88 | 20.00 | identical |

Baseline fingerprints were **4 distinct / 4**.

All four argsort runs produced the same output fingerprint:

~~~text
8a177e4db49d2505055c52e3bb455cb23ab7c4d3e654c2e2cca5adcbe894aecf
~~~

This same-parent result makes the QSA `ggml_top_k` selection path the strongest identified cause of the observed ROCm greedy-output nondeterminism.

This does **not** prove that one specific HIP kernel primitive (for example one atomic operation) is the sole low-level cause. The experimentally established statement is narrower: replacing Qwen4Exp QSA `ggml_top_k` selection with argsort+cont restores 4/4 repeatability under the tested 64k configuration.

Raw archives used for the final controlled comparison include:

~~~text
20261022-101740-829-cli-rocm-b11814-ctx65536-f3bfd5c64ae7.zip
20261022-103659-242-qwen38-r5-rocm-qsa-argsort-topk-64k.zip
20261022-112848-952-qwen38-r5-rocm-qsa-topk-baseline-64k.zip
~~~

## Performance cost

The same-parent top-k control is unusually stable:

~~~text
mean PP = 394.34 tok/s
mean TG = 21.14 tok/s
~~~

The argsort r3 run contains a separate ~9 s host-side stall between approximately 6k and 8k prompt tokens. GPU utilization/clock/power dropped close to idle during the stall, then returned to normal. It should not be interpreted as steady-state argsort compute cost.

Using the non-stalled argsort runs r1/r2/r4:

~~~text
mean PP = 381.88 tok/s
PP cost vs top-k = -3.16 %
~~~

All four argsort TG runs are stable around:

~~~text
mean TG ~= 20.04 tok/s
TG cost vs top-k ~= -5.18 %
~~~

For normal inference and performance measurement, the current faster `ggml_top_k` path should therefore remain the default.

## ROCm ARGSORT coverage caveat

Focused ROCm backend testing on gfx1151 passed all supported ARGSORT cases: **74/74 tests passed**.

Observed one-dimensional support:

~~~text
up to 16,384 elements: supported
32,767 and above: reported not supported on ROCm0
~~~

The current HIP ARGSORT path without CUB is bounded by bitonic-sort shared-memory requirements.

The tested 64k QSA workload fits the supported width after compress-ratio pooling. Longer contexts, especially 128k and above, are **not yet validated** for the deterministic selector and may require fallback or a different deterministic top-k implementation.

Do not treat the 64k success as proof that the same mode is suitable for all context lengths.

## Proposed opt-in deterministic QSA mode

A useful downstream feature is an **opt-in**, Qwen4Exp-specific deterministic selector while preserving the current fast default.

Proposed environment variable:

~~~text
QWEN4EXP_QSA_DETERMINISTIC_TOPK=1
~~~

Proposed semantics:

~~~text
unset / 0:
    ggml_top_k(...)
    fast default
    normal inference and performance measurements

1:
    ggml_cont(ggml_argsort_top_k(...))
    deterministic QSA selection under validated conditions
    quality/regression/input-corpus comparisons
~~~

Important naming/claim boundary:

- call this a **deterministic QSA top-k mode**, not a global “deterministic output” switch;
- the experiment shows that it fixes the observed 64k ROCm output drift;
- other sources of nondeterminism could still exist in other models/backends/configurations.

Recommended benchmark policy:

- **speed/performance claims:** leave the variable unset;
- **quality/regression/corpus-difference checks where stable output matters:** enable it and record the effective value in run metadata;
- never compare PP/TG from deterministic mode directly against normal-mode historical performance without labeling the mode.

## Build-script side findings during this investigation

The corrected Windows ROCm build path was successfully exercised end to end:

- `BuildIdentity.Status = Verified`;
- SDK expected/observed = 10.0.0;
- runtime policy = `TheRockUnified`;
- complete DLL closure staged and hash-verified;
- rocBLAS/hipBLASLt gfx1151 runtime-data trees staged with matching digests.

A separate full `FLASH_ATTN_EXT` backend-test run exposed an existing support-check mismatch for a DKQ=64 + logit-softcap test. The HIP kernel intentionally enters `NO_DEVICE_CODE` / trap for that combination even though the higher-level support path allowed the test to launch. This was unrelated to the QSA argsort change. Until that support-test mismatch is fixed, do not use the full FLASH_ATTN_EXT sweep as a mandatory post-build gate on this gfx1151 Windows configuration.

The focused ARGSORT backend suite is safe and passed 74/74.

## Decision

For the pinned r5 research line:

- output-repeatability root cause is sufficiently localized for current project needs;
- keep normal QSA `ggml_top_k` as the default performance path;
- preserve the argsort experiment as evidence;
- add an opt-in deterministic QSA top-k mode only if/when it is useful for quality/regression/corpus-comparison workflows;
- validate any such mode separately at longer contexts before claiming support beyond 64k.

The next planned performance task remains:

~~~text
ROCmFP4 vs Unsloth model speed comparison using the same llama.cpp binary
~~~

Before that comparison, separately perform the lightweight Windows-event checks for:

1. the early-morning GPU/backend-test system hang;
2. the ~9 s host-side stall seen in argsort r3.
