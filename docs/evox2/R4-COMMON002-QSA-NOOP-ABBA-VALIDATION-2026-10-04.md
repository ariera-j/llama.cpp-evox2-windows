# r4 COMMON-002: target QSA no-op normal ABBA validation

Gate D passes at Vulkan 256k: four diagnostic-OFF runs are OK with Verified
runtime/startup evidence, byte-identical responses and matched aggregate
acceptance. Mean TG improves 20.205 -> 22.830 tok/s (+12.99%) with draft
omission fixed at1. Mean PP changes 229.940 -> 229.565 (-0.16%).
The target no-op candidate's normal gain is reproduced in both B runs.
Source default remains OFF; ROCm coverage and smaller-context coverage are
separate gates. No further TG optimization is automatically started.

## Archive and identity

Archive: `20261004-204234-390-qwen38-r4-qsa-noop-abba.zip`.
Matrix runs 20:42:34.517–22:07:18.040 JST on 2026-10-04 (84.725 minutes).
Complete=true, four planned/finished/OK, zero NonOK, not stopped early.
All children exit0 without an exception.

All use Vulkan b11416 / embedded commit `5df0bdbaf`, Clang20.1.8,
Radeon8060S /96GB UMA. RuntimeArtifactStatus=Verified:

- Runtime digest: `a90aedcdccacaada6b6a3105d7da3573c2b26797d128a6acfecd1430d5d358e6`
- CLI SHA-256: `5b6b39f51395b707a3b2c9eddb50eedb05e625fb1cdc7c10e82727c095c53ef3`

Main PLE16 UD-IQ3_XXS /draft Q8_0 paths, lengths and mtimes match all arms.
Model hashes are unset. Main identity is from conditions/load records; the
last summary Q8_0 metadata belongs to the draft. Input is the same
1,261,235-byte `nlp-survey-ch3-d31-b1.txt`, SHA-256
`63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.

All process255181 prompt tokens and generate512 tokens; context262144,
f16, batch2048/ubatch1024, t4/tb4, ngl999, CPU MoE0, FA auto, fit/reasoning OFF,
cache RAM0, checkpoints0t, temperature0.2/top-p0.8, seed1234 and ignore EOS.
MTP is ON, DraftMax2/DraftPMin0 and dense draft omission1 in all four.
Vulkan legacy MoE tile1/get-rows-128x4=0/QSA union1 are fixed. Arguments match;
the target candidate changes0/1. Diagnostics are explicitly off and no wall
sidecar exists. A1/A2 share one condition ID; B1/B2 share another, with ABBA
repetition identity retained in the expanded plan.

Target startup evidence is Verified: eligible target1, pool4/stream1/seq_max1,
enabled0 for A and enabled1 for B. Draft remains target0/eligible0/enabled0.
Dense draft omission is Verified at layer48/ratio0/omitted1 throughout.

## Four runs

| Arm | Child run | PP tok/s | TG tok/s | Accepted/drafted |
| --- | --- | ---: | ---: | ---: |
| A1 | `20261004-204237-097-cli-vulkan-b11416-ctx262144-017ea93338a2` | 230.73 | 20.24 | 293/436 |
| B1 | `20261004-210430-537-cli-vulkan-b11416-ctx262144-3099c2a4e4ec` | 229.58 | 22.82 | 293/436 |
| B2 | `20261004-212418-727-cli-vulkan-b11416-ctx262144-3099c2a4e4ec` | 229.55 | 22.84 | 293/436 |
| A2 | `20261004-214628-432-cli-vulkan-b11416-ctx262144-017ea93338a2` | 229.15 | 20.17 | 293/436 |
| A mean | — | 229.940 | 20.205 | 293/436 |
| B mean | — | 229.565 | 22.830 | 293/436 |

All four response bodies are identical to each other and to the wall pair:
2538 bytes, SHA-256
`70584ef998b9bbaf454e52f5d41dae21ade4e9ed4d53d406a742b52011ffd90a`.
Echoed input and performance/exit footer are excluded. Aggregate acceptance
293/436=67.202% matches. No ordered acceptance trace is collected in normal
runs; ordered-history equality was established separately for the wall pair.

The B range22.82–22.84 is above the A range20.17–20.24 in this ABBA sequence.
The preceding wall pair already established123 suppressed no-op invalidations,
all95 actual-removal stale marks retained, target full rebuilds217->95 and
layout5.529702->2.436146s. Normal ABBA reproduces the timing gain without the
diagnostic instrumentation; it does not independently recount those events.

## PP and total latency

| Mean reported evaluation time | A, seconds | B, seconds | B minus A |
| --- | ---: | ---: | ---: |
| Prompt | 1109.782750 | 1111.571225 | +1.788475 |
| Generation | 25.290425 | 22.380190 | -2.910235 |
| Total | 1135.073175 | 1133.951415 | -1.121760 |

Mean total evaluation improves only about0.10% for512 output tokens; PP is
effectively unchanged and dominates total latency. PP variation between A1
and A2 alone exceeds the mean total saving, so do not claim a robust total
latency improvement. Whole-process times additionally contain loading/setup.

Historical normal stages were TG15.220 before draft omission,20.185 after
omission, and now22.830 with target no-op suppression. The cumulative change
from the historical15.220 reference is+50.0%, but only20.205->22.830 is the
current same-binary target-switch ABBA. The earlier MTP OFF TG19.76/PP265.02
reference is a different session/build and does not establish fresh-prompt
MTP superiority with this binary.

## User-directed next order

The user requests ROCm build/measurement first, then CLI/llama-bench comparison,
then a decision between MTP PP attribution and other candidates. This replaces
the immediate suffix-reuse/MTP-PP implementation sequence. Preserve the
remaining95 real suffix rebuilds /2.436146s as a documented candidate rather
than starting it automatically. Focused Vulkan128k validation remains pending;
COMMON-005 remains deferred and upstream stays pinned.

ROCm native/allocation/short checks precede the focused256k normal controls.
The existing benchmark binary has no MTP path: compare its long PP and
depth-filled single-token TG with MTP OFF CLI, first64k then256k. Keep
synthetic token content, context allocation, warmup/state reuse and timer
boundaries explicit. See [ROCm and CLI/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).

See [wall validation](R4-COMMON002-QSA-NOOP-WALL-VALIDATION-2026-10-04.md) and
[implementation](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md).
