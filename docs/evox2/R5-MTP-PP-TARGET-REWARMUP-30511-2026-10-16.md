# r5 MTP PP target re-warmup control (#30511 minimal port) — 2026-10-16

**Status: SOURCE/PLAN/STATIC TESTS COMMITTED; WINDOWS BUILD AND NATIVE TIMING NOT YET RUN.**

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
