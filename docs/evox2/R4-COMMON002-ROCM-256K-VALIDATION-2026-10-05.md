# r4 COMMON-002: ROCm 256k normal comparison

## Decision

The three-run matrix completed with 3/3 OK, exit0 and Verified runtime/startup
evidence. Current combined MTP B has TG14.44 versus MTP OFF12.39 tok/s, so
the earlier long-context MTP TG reversal is absent in this sample. Its PP
overhead still dominates a fresh prompt: reported PP+TG is88.318 s longer
than OFF (+6.24%). These are observed single-run results, not reproduced means.

A/B response bodies and aggregate acceptance differ. The observed target-switch
TG13.57->14.44 (+6.41%) therefore does **not** establish an isolated no-op
speedup or a passed long-context output-equivalence gate on ROCm. Whether this
is existing backend/run variability or candidate-related remains unresolved.
Native exactness and short matching results remain valid within their tested
scope; they do not explain this long-run difference. Source defaults stay OFF.

Proceed with the user-requested staged MTP OFF CLI/bench comparison. It is
independent of speculative acceptance and does not validate MTP correctness.
Keep the long A/B difference open before broadening ROCm candidate use or
claiming its reproduced benefit. No runtime changes, rebuild or automatic
all-context matrix is requested by this record.

## Input and identity

Uploaded archive: `20261005-000812-347-qwen38-r4-qsa-noop-rocm-256k.zip`.
Matrix: `20261005-000812-347-qwen38-r4-qsa-noop-rocm-256k`,
2026-10-05 00:08:12–01:24:36 JST. Complete=true; planned/finished/OK=3;
NonOK=0; StoppedEarly=false. Order is OFF, A, B; no repetitions or wall
attribution were collected.

All three share ROCm b11420, embedded commit `131288531`, Clang23.0.0 and
Verified build/runtime. The working checkout is documentation commit
`d45985f3ed5b131898f09bd56a4f57fff64b9fe6`; the binary source is
`1312885310f75c324f743cdf205dbb471fabd99c`. Documentation updates did not
change inference code.

- Runtime digest: `aba45b977bb8bc68bc702142d7ad5db923af002705361f295c8f1ddb1a7b472f`.
- CLI SHA256: `93a1f5fdcf7f9b7cfb2a4a32bf58b1d6591587ec0cbab6ac1f17689b5ca80145`.
- Main model: `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`,81961816672 bytes.
- MTP draft: `mtp-Qwen3.8-Flash-Next-Q8_0.gguf`,4137429120 bytes.
- Input SHA256: `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.

Model path/size/mtime match; full model hashes were not collected. The ON
result's last Q8_0 metadata describes the draft, not the PLE16 main model.
Actual/requested context262144, prompt255181, generated512, UMA96GB, f16
K/V, batch2048/ubatch1024, t4/tb4, ngl999/ncmoe0, FAauto, fitOFF,
cacheRAM0, checkpoints0t, temperature0.2/topP0.8, seed1234, ignoreEOS,
reasoningOFF and resource monitoring are common. Vulkan-only controls are
cleared; LLAMA_MTP_DIAG=off. A/B command arguments and effective conditions
match except LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1.

Target startup evidence is Verified in all three: target1/eligible1,
k_pool4/streams1/seq_max1; enabled1 for OFF/B and enabled0 for A.
ON draft evidence is Verified: dense single-block layer48/ratio0 omitted;
draft target-no-op eligibility is false with reason not_target. OFF has no
draft and records MtpDisabled. Startup enablement is not a count of executed
suppressions; this normal matrix supplies no suppression/rebuild trace.

## Results

| Arm | MTP | Target switch | PP tok/s | TG tok/s | Prompt s | Generation s | PP+TG s | Draft accepted/generated |
|---|---|---:|---:|---:|---:|---:|---:|---|
| control-mtp-off | OFF | 1 | 185.76 | 12.39 | 1373.72013 | 41.25221 | 1414.97234 | — |
| A-normal | ON | 0 | 173.91 | 13.57 | 1467.30608 | 37.64889 | 1504.95497 | 289/441 (65.53%) |
| B-normal | ON | 1 | 173.84 | 14.44 | 1467.89645 | 35.39357 | 1503.29001 | 286/448 (63.84%) |

Dense omission is1 in both ON arms. Process durations including loading are
1455.341/1550.128/1551.513 s; these are distinct from reported evaluation.
No fatal stderr entries were found; each run has RunException=null.

- B versus A: PP−0.04%, TG+6.41%; prompt+0.59037 s,
  generation−2.25532 s, reported evaluation−1.66496 s (−0.11%).
  Different responses/acceptance prevent attributing that generation saving
  solely to target no-op suppression.
- B versus OFF: PP−6.42%, TG+16.55%; prompt+94.17632 s,
  generation−5.85864 s, reported evaluation+88.31767 s (+6.24%).
  MTP improves observed TG but does not improve this fresh-prompt total.
- The short B-normal PP48.16 anomaly is not reproduced as an A/B PP collapse
  here:173.91/173.84. Its original cause remains unknown; do not mark it fixed.

## Output and acceptance limits

Bodies were extracted from raw stdout between the truncated prompt marker
and the Prompt performance footer, retaining original bytes and excluding
timings. All512 generated-token counts are recorded, but bodies differ:

| Arm | Body bytes | Body SHA256 |
|---|---:|---|
| OFF | 2420 | `7c463a09e94d6621043e00adebd737b63d537a4d15aa5dc66de34d2905657dc7` |
| A | 2567 | `820ec4bc0a3acd3b4f9760511d075c9325207c794b2fac11b9ce7dd80855d79f` |
| B | 2555 | `6ad1857d61a45196f718ca129d64ad834b9912a48144a7d8f6715390293b2fa3` |

A/B first differ at byte3: A starts “本文書は”, B starts “本稿は”. This
is a generated-text difference, not a performance-footer/hash artifact.
Acceptance also differs,289/441 versus286/448. Temperature is0.2; equal
seed alone is not evidence of identical computation/output. There is no
ordered acceptance or layout trace in diagnostic-OFF runs, nor a same-arm
repeat to establish the underlying variability. These logs cannot decide
whether the candidate caused the difference. Do not label ROCm long A/B
numerically validated or assume ordinary sampling explains it.

If stronger ROCm MTP evidence is needed after bench review, first distinguish
same-arm repeat variability from switch-correlated differences, then use
focused ordered diagnostics/numeric comparisons for the remaining question.
Do not change stale/layout semantics merely to force matching text.

## Next stage

Use the existing verified Vulkan/ROCm binaries. First collect two64k MTP OFF
CLI controls with `qwen38-r4-cli-bench-comparison.psd1 -Tool cli -OnlyCase 64k`.
Check both statuses and actual prompt61789/generated512, then run its four
64k bench invocations after the documented bench-manifest/runtime preflight.
Review64k before256k. This ROCm256k OFF result can be reused if the binary,
runtime, model/input and conditions remain identical; only the missing
Vulkan256k OFF CLI control then needs collecting.

Bench has no MTP execution path. Random-token MoE routing, allocation size,
warmup/state reuse and timing boundaries still differ from CLI; its comparison
cannot settle this MTP A/B output issue. Decide MTP PP, residual suffix work,
ROCm PP scaling or further candidate validation after the requested comparison.

See [ROCm native/short results](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md),
[runnable CLI/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md)
and [current priorities](ROADMAP.md).
