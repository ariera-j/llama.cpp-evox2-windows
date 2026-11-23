# r4 COMMON-002: 256k dense MTP indexer normal ABBA validation

Status: Gate D passed on Windows Vulkan for the supplied PLE16 main model and
Q8_0 MTP sidecar. The default-off candidate has a useful, consistent normal TG
gain at 256k, with identical response bytes and acceptance totals. Retain the
explicit opt-in for subsequent Vulkan MTP tests; do not change the source
default or claim ROCm/cross-context validation from these runs.

MTP ON is now near the earlier MTP OFF TG reference. It still pays a large
fresh-prompt PP penalty, so this result does not establish a total-latency
advantage for MTP ON.

## Collection and controls

Source ZIP: `20261004-161613-418-qwen38-r4-mtp-dense-indexer-abba.zip`.
Matrix of the same name, collected 2026-10-04 16:16-17:35 JST, is Complete,
StoppedEarly=false, planned/finished4/4, OK4/NonOK0, duration79.511 minutes.
Actual order is A1, B1, B2, A2. Both arms have MTP ON; A omission=0 and B=1.

All four use Verified b11408 / embedded `e2deea70a`, Clang20.1.8, Vulkan
Radeon(TM) 8060S Graphics, manual UMA96GB. Checkout recorded in all conditions:
clean `664e34c246e24d7c8326af8a1b6e53d84a799e47`. This differs from the
embedded executable commit because intervening commits are documentation only.

- Runtime artifact digest:
  `04eb0847d003a55f562c59fd33fca8c298c20d072023c592f8241ffc8c59cdb6`.
- CLI SHA256:
  `406e37421b1efdfad2a6fdc50356f30404bef59bb57b6e3158d5d793db306741`.
- Target Unsloth PLE16 UD-IQ3_XXS, draft Unsloth Q8_0 MTP.
- Input `nlp-survey-ch3-d31-b1.txt`, 1,261,235 bytes, SHA256
  `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.
- Context262144, prompt255181, generated512; f16, b2048/ub1024, t4/tb4,
  ngl999/CpuMoe0/FAauto, fit/reasoningoff, cache RAM0/checkpoints0t.
- DraftMax2/Pmin0, temperature0.2/top-p0.8/seed1234/ignore-eos.
- MoE legacy1, GET_ROWS128x4=0, QSA union1.
- LLAMA_MTP_DIAG=off throughout; zero `mtp_diag v=` records in every stderr.

EffectiveCondition objects match after removing the candidate switch
(and any label-only ABBA field). Paths/size/mtime identify the same target
and draft in all runs; GGUF content hashes were not collected.
There are no diagnostic sidecars or DiagnosticStatus fields when diagnostics
are off; this is expected for these normal measurements, not a skipped gate.

## Individual runs and arithmetic means

| Variant | Child run suffix | PP tok/s | TG tok/s | Prompt seconds | Generation seconds | PP+TG seconds |
|---|---|---:|---:|---:|---:|---:|
| A1 | `161615-382-...-a2b21113a6b9` | 229.85 | 15.14 | 1110.20656 | 33.74618 | 1143.95274 |
| B1 | `163613-284-...-98b521af6f47` | 229.54 | 20.10 | 1111.72293 | 25.42538 | 1137.14831 |
| B2 | `165602-316-...-98b521af6f47` | 229.76 | 20.27 | 1110.66470 | 25.21437 | 1135.87907 |
| A2 | `171550-159-...-a2b21113a6b9` | 227.82 | 15.30 | 1120.08028 | 33.38932 | 1153.46960 |
| A mean | omission OFF | 228.835 | 15.220 | 1115.143420 | 33.567750 | 1148.711170 |
| B mean | omission ON | 229.650 | 20.185 | 1111.193815 | 25.319875 | 1136.513690 |

Full child names have the prefix `20261004-` and middle
`cli-vulkan-b11408-ctx262144`. A repetitions share a condition ID and B
repetitions share a condition ID; distinct run IDs preserve both observations.

B versus A:

- TG +32.62%; both B values are well above both A values.
  Adjacent comparisons A1/B1 and A2/B2 improve +32.76% and +32.48%.
- Generation time -8.247875 s (-24.57%).
- PP +0.36%, prompt time -3.949605 s (-0.35%); treat PP as effectively
  unchanged. A2 prompt time is about9.87 s above A1, while B1/B2 are close.
  The small PP difference is not a demonstrated PP optimization.
- Prompt+generation -12.197480 s (-1.06%). That mean includes the small
  prompt variation; the robust result is the TG difference.
- Means are arithmetic per-run means, consistent with the earlier reports.
  Two observations per arm do not support a precise population confidence
  interval or a cross-workload speed claim.

Normal A TG15.220 is also near the earlier overnight MTP ON mean15.25.
The normal result follows the wall pair (14.76 -> 19.95, +35.16%) with the same
direction and a large separated effect. No extra repeated 256k A/B is needed
to decide whether this candidate removes a useful cost in this workload.

## Correctness and applied-candidate evidence

All four Status=OK, exit0, RunException=null, runtime Verified and candidate
evidence Verified. Startup A requested0/eligible1/omitted0/reason disabled;
B requested1/eligible1/omitted1/reason dense_single_block, layer48/ratio0.

Every generated response body is exactly the same 2,538 UTF-8 bytes:
SHA256 `70584ef998b9bbaf454e52f5d41dae21ade4e9ed4d53d406a742b52011ffd90a`.
It also matches both preceding wall arms. Compare the generated body after
the prompt-preview `... (truncated)\r\n` delimiter and before the timing
footer, rather than whole stdout/output logs. The preview's truncated UTF-8
character is outside the generated body, as recorded in the wall validation.
Each response stops at the imposed512-token budget.

All acceptance totals are293/436=67.202%, mean length2.34. Normal diagnostics
are off, so per-round histories are not captured here; the preceding wall pair
has identical ordered histories over218 rounds, including reject/partial/full
acceptance. Native state/rollback/logit gates and the short CLI gate already
passed. Text/acceptance agreement does not prove exhaustive token/logit
equivalence for other prompts or context sizes.

Buffer logs retain target attention6144MiB/indexer1536MiB and draft
attention512MiB in every run. Only A logs draft indexer128MiB. This verifies
the intended allocation scope; it is not a claim of a measured128MiB
process-memory reduction. No error/failure line is found in stderr.

## Comparison with MTP OFF

Use the earlier **normal overnight OFF** average as the contextual reference,
rather than substituting the diagnostic wall OFF result.

| Vulkan 256k condition | PP tok/s | TG tok/s | PP+TG seconds |
|---|---:|---:|---:|
| Earlier normal MTP OFF | 265.02 | 19.76 | 988.73 |
| Current normal MTP ON, omission OFF | 228.835 | 15.220 | 1148.711170 |
| Current normal MTP ON, omission ON | 229.650 | 20.185 | 1136.513690 |

The current upload has no MTP OFF arm. The earlier reference uses b11390 /
embedded `5814fbe99`; current A/B use the verified b11408 binary. Workload
and main tuning controls are comparable, but this is not a same-binary,
same-session MTP OFF/ON experiment.

Current B relative to the earlier normal OFF:

- TG +2.15%: B repeats20.10/20.27 versus earlier OFF19.80/19.72.
  A small historical difference does not establish a robust general MTP
  advantage across builds/runs.
- PP -13.35%.
- Prompt+generation +147.783690 s (+14.95%), about2.46 minutes longer.
- Earlier OFF prompt mean962.867 s versus current B1111.193815 s:
  approximately148.33 s extra PP. Earlier OFF generation is about25.863 s
  versus current B25.319875 s, only about0.54 s saved.

Thus the dense-indexer omission succeeds at removing much of the anomalous
MTP TG slowdown. It has not yet made MTP clearly faster than OFF or worthwhile
for this fresh255k-prompt/512-output workload. Prompt reuse and other output
lengths need separate evidence; do not extrapolate constant TG to an arbitrary
break-even output length.

The earlier wall diagnostic OFF PP268.37/TG19.69 remains a separately labeled
diagnostic reference; it is not the normal OFF baseline used above.

## Remaining work and priorities

1. Retain the explicit dense-indexer opt-in for subsequent Vulkan MTP tests;
   all delivered gates through normal256k now pass. Source default stays OFF,
   with focused normal128k confirmation retained before broader expansion.
2. Start separate source investigation of retained **target** layout suffix/
   no-op maintenance. In preceding B-wall, target layout still costs5.499980 s
   (~21.48% of generation time), with217 full/stale rebuilds and55,429,810 copied
   cells. This is a concrete residual TG cost even after draft removal.
   Target indexer cannot simply be omitted: the target graph uses QSA.
   Preserve pool-boundary, sharing, position-change and restore invariants.
3. Continue MTP PP attribution after that bounded TG work. The negligible PP
   response to draft-indexer removal shows that most of the roughly148 s
   fresh-prompt penalty remains elsewhere; distinguish draft prefill, hidden
   transfer/synchronization and target work before choosing a change.
4. ROCm long-context PP scaling follows the two MTP questions. COMMON-005
   historical decode port remains deferred. No full overnight matrix or
   automatic source-default promotion is justified by these four runs.

A new source investigation/implementation must remain separate from this
validated candidate. The5.5 s target scope is attribution evidence from wall
mode, not a promise of an exact normal-speedup amount. This recording changes
documentation only; keep the current binary and build manifest.

Related:
[implementation and commands](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md),
[candidate wall validation](R4-COMMON002-DENSE-INDEXER-WALL-VALIDATION-2026-10-04.md),
[overnight normal reference](R4-COMMON002-OVERNIGHT-ANALYSIS-2026-10-04.md),
[roadmap](ROADMAP.md).
