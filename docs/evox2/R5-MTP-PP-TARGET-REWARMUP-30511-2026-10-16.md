# r5 MTP PP target re-warmup control (#30511 minimal port) — 2026-10-16

**Status: 64K SAME-BINARY ABBA COMPLETE; NO MATERIAL LONG-PREFILL EFFECT. C0 CLOSED; 128K RE-RUN NOT JUSTIFIED.**

Branch: `investigation/r5-mtp-pp-target-rewarmup-30511-20261016`  
Parent: `investigation/r5-mtp-pp-kv-crop-stage1-20261014` at `df74d2f221d651ce3916973819f92d37fff94ab3`.

## Purpose

Stage-B removes the zero-output Draft Flash Attention path, but the same-day 128k
MTP ON Stage-B run still trails MTP OFF by about 11.61 s of native prompt time.
The MTP constructor enables unmasked Target NextN extraction *after* the target
context's normal startup warmup. That changes the target graph shape and marks
the scheduler for reserve. Upstream PR #30511 proposes running target warmup
again after this change so the first real request does not pay the reserve /
buffer mapping cost.

This branch ports only that idea for a controlled experiment. It does **not**
change Stage-B K/V math, Target NextN semantics, Draft weights, QSA union,
sampling, or the stable r5 branch.

Upstream reference:
https://github.com/ggml-org/llama.cpp/pull/30511

## Experimental difference from upstream #30511

Upstream intends the post-NextN warmup to follow the normal warmup setting.
For this investigation branch, the re-warmup is **default OFF** and enabled
only by:

```text
LLAMA_MTP_TARGET_REWARMUP=1
```

Any other value, including unset or `0`, preserves the pre-port behavior.
This allows OFF/ON timing from the **same compiled executable**.

The port:
1. extracts the branch's existing startup empty-decode warmup body into
   `common_warmup(llama_context *, uint32_t)`;
2. keeps ordinary startup warmup behavior unchanged by calling that helper from
   `common_init_from_params()`;
3. after MTP enables Target unmasked NextN and Draft masked NextN, optionally
   calls `common_warmup(ctx_tgt, llama_n_batch(ctx_tgt))`;
4. adds same-binary short, 64k ABBA and 128k ABBA benchmark jobs.

No upstream `common_batch_set_zero_state` change or server plumbing is imported;
those belong to newer-source integration, not this pinned r5 causal test.

## Interpretation

The re-warmup runs during initialization, before the real prompt. Therefore an
improvement in native `prompt eval time` means that work was moved out of the
first prompt path; it is **not automatically an end-to-end process speedup**.
For one-shot `llama-cli`, also compare total process elapsed time. For a
long-lived server, first-request latency is the more relevant effect.

A positive PP delta here should be subtracted from the observed ~11.61 s
first-prompt MTP residual before attributing the rest to Draft `mtp_eh_proj`,
Target final-layer NextN HC/FFN, or hidden-state synchronization.

## Build/test identity

Use a fresh Vulkan build directory and a new ignored local BuildKey:

`R5MtpTargetRewarmVulkan`

Do not repoint `R5MtpKvOnlyVulkan`; the retained b11618 Stage-B binary remains
the historical baseline.

Static test:

```powershell
python .\tools\evox2\tests\test_mtp_kv_crop_stage1.py
```

Native sequence:
1. build once;
2. run `stage1-target-rewarmup-short`;
3. if both arms exit 0 and generated output / Draft acceptance match, run
   `stage1-target-rewarmup-64k-abba`;
4. only if the 64k result is stable enough to matter, run
   `stage1-target-rewarmup-128k-abba`.

Do not enable RGP, graph diagnostics, `LLAMA_MTP_PP_TRACE`, or other profiling
flags during these timing jobs.


## 2026-10-16 native validation

### Build / workload identity

The opt-in control was built as **b11652-db25093e5** from this branch. All four
64k runs used the same verified Vulkan runtime artifact:

- executable SHA-256: `e9a6f8457090ec28a5e313d30fe60a94617d1bfee6ab6095bbdd2216624b1f4b`
- runtime artifact digest: `194eac81f157c079c0bd7510f9bd8889a228ee968338b63576f00003320bf3f6`
- main model: Unsloth Qwen3.8-Flash-Next PLE16, IQ3_XXS
- Draft: standalone Q8_0 MTP model
- context 65536, prompt **61,789 tokens**, batch 2048 / ubatch 1024
- f16 K/V, Vulkan QSA union ON, minimum KV 32768
- Stage-B `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1` in all arms
- the only causal switch was `LLAMA_MTP_TARGET_REWARMUP=0/1`
- all runs exited 0; P-MODE was **Performance** at start and finish with no
  transition warning; ADLX high-load power classification was
  **Performance-like** in all four runs.

The generated response extracted from `stdout.log` was byte-identical across
all four runs (SHA-256
`94d7b8bb5fcd0dd8fceb46939805b742478bb469b52cf50af8d7c029d33a2684`).
Draft acceptance was also identical: **295 / 430 = 0.68605**.

### 64k ABBA result

Run order: **A1 OFF -> B1 ON -> B2 ON -> A2 OFF**.

| Run | Target re-warmup | PP (tok/s) | Prompt time (s) | TG (tok/s) | Process duration (s) |
| --- | --- | ---: | ---: | ---: | ---: |
| A1 | OFF | 344.28 | 179.47544 | 29.24 | 238.422 |
| B1 | ON  | 344.31 | 179.45646 | 29.75 | 238.364 |
| B2 | ON  | 344.48 | 179.36988 | 29.80 | 238.379 |
| A2 | OFF | 344.30 | 179.46111 | 29.84 | 238.386 |

ABBA means:

| Metric | OFF mean | ON mean | ON - OFF |
| --- | ---: | ---: | ---: |
| PP | **344.290 tok/s** | **344.395 tok/s** | **+0.105 tok/s (+0.0305%)** |
| Prompt time | **179.468275 s** | **179.413170 s** | **-0.055105 s (-0.0307%)** |
| TG | 29.540 tok/s | 29.775 tok/s | +0.235 tok/s (+0.796%) |
| Whole child process | **238.4040 s** | **238.3715 s** | **-0.0325 s (-0.0136%)** |

The PP effect is only **55 ms over ~179.4 s**, and the whole-process difference
is only **32.5 ms**. These are not material relative to the prior
Performance-verified 128k Stage-B residual of **11.608 s** versus MTP OFF.

The TG mean should not be interpreted as a re-warmup gain: A1 is the lowest TG
run, while the final A2/OFF run reaches **29.84 tok/s**, slightly above both ON
runs. The same ordering pattern also explains the large short-smoke apparent
gain: the first process in the cohort can pay cold driver / shader-pipeline /
OS-GPU startup work. The 64k ABBA removes that ordering ambiguity.

### Decision

**C0 / upstream #30511 hypothesis is closed for this long-prefill PP
investigation.** On this Windows/Vulkan Evo-X2 setup, post-NextN Target re-warmup
does not materially change 64k native PP once run order is counterbalanced.
Therefore:

- do **not** spend another four long runs on the prepared 128k re-warmup ABBA;
- do **not** subtract a meaningful #30511 reserve term from the measured
  ~11.608 s 128k MTP residual;
- retain this branch and result as a negative control;
- return the optimization priority to the repeating steady-state Draft
  `mtp_eh_proj` matmul, then Target NextN final-layer HC/FFN and
  hidden-state synchronization / host preparation.

This result does **not** argue against upstream #30511 as a first-request
latency fix in other backends/models or server configurations. It only shows
that it is not a material explanation for this project's measured long-prompt
MTP PP deficit under the tested Vulkan configuration.
