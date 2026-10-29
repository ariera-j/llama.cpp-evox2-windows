# r4 COMMON-002: 256k dense MTP indexer wall validation

Status: Gate C passed on Windows Vulkan. Proceed to the existing diagnostic-off
256k ABBA plan, using the same verified binary. Keep the candidate default OFF
until normal performance review; no rebuild, sync, ROCm or Unsloth mix run is
required before ABBA.

## Collection and identity

Source ZIP: `20261004-151130-034-qwen38-r4-mtp-dense-indexer-wall.zip`.
Matrix `20261004-151130-034-qwen38-r4-mtp-dense-indexer-wall`, collected
2026-10-04 15:11:30-15:51:20 JST, contains exactly A-wall then B-wall.
Complete=true, StoppedEarly=false, planned/finished=2/2, OK=2, NonOK=0.
Both child runs have exit code 0, no run exception, Verified runtime identity,
Verified candidate evidence and Complete diagnostics.

| Arm | Child run | Candidate |
|---|---|---|
| A-wall | `20261004-151132-024-cli-vulkan-b11408-ctx262144-866c3a91043c` | MTP ON, dense indexer omission=0 |
| B-wall | `20261004-153138-606-cli-vulkan-b11408-ctx262144-64edda7945a2` | MTP ON, dense indexer omission=1 |

Both use b11408, embedded source commit `e2deea70a`, Clang 20.1.8, Vulkan0
Radeon(TM) 8060S Graphics, manual UMA label 96GB. The checkout recorded by both
runs is clean `8d76b349ecc881b8abc3ff96fe10ce9d28ff94ef`; later documentation
commits do not require rebuilding this executable.

- CLI SHA256: `406e37421b1efdfad2a6fdc50356f30404bef59bb57b6e3158d5d793db306741`.
- Runtime artifact digest: `04eb0847d003a55f562c59fd33fca8c298c20d072023c592f8241ffc8c59cdb6`.
- Main model: Unsloth PLE16 UD-IQ3_XXS; draft: Q8_0 MTP, same paths/size/mtime in both runs.
- Input: `nlp-survey-ch3-d31-b1.txt`, 1,261,235 bytes, SHA256
  `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.
- Context262144, prompt255181, generated512, f16, b2048/ub1024, t4/tb4,
  ngl999/CpuMoe0, FAauto, fit/reasoningoff, prompt cache RAM0/checkpoints0t.
- DraftMax2/Pmin0, temperature0.2/top-p0.8/seed1234/ignore-eos.
- MoE legacy1, GET_ROWS128x4=0, QSA union1; diagnostics wall in both.
  All other experimental controls are cleared by the plan.

The two EffectiveCondition objects are identical after removing only
`LLAMA_MTP_SKIP_DENSE_INDEXER`. Model hashes were not collected, so model
identity here is path/size/mtime evidence rather than content-hash verification.
The generic result ModelFileType=Q8_0/ModelFileSizeGiB=3.84 describes the last
loaded draft; it does not replace the main ModelIdentity PLE16 record.

## Measured performance

| Metric | A-wall | B-wall | B change |
|---|---:|---:|---:|
| PP tok/s | 229.91 | 230.21 | +0.13% |
| Prompt evaluation seconds | 1109.90455 | 1108.48611 | -1.41844 |
| TG tok/s | 14.76 | 19.95 | +35.16% |
| Generation evaluation seconds | 34.61605 | 25.60850 | -9.00755 (-26.02%) |
| Prompt + generation seconds | 1144.52061 | 1134.09461 | -10.42600 (-0.91%) |
| Draft accepted/generated | 293/436 | 293/436 | identical |
| Draft acceptance | 67.202% | 67.202% | identical |

This is one wall-instrumented run per arm. It establishes removal of the
intended work and a large TG improvement in this pair, not a repeated normal
performance result. Prompt time dominates the full request; TG +35.16% is not
a +35.16% reduction of end-to-end latency. PP is effectively unchanged and
MTP PP overhead remains a separate investigation.

The preserved earlier 256k MTP OFF reference is TG19.69/PP268.37. B-wall is now
near that TG throughput, but this upload contains no matched OFF control.
Do not infer that MTP ON now beats OFF consistently or in total latency.
The candidate comparison is MTP ON A versus MTP ON B throughout.

## Output and real speculative paths

Generated response bytes are exactly identical A/B: 2,538 UTF-8 bytes,
SHA256 `70584ef998b9bbaf454e52f5d41dae21ade4e9ed4d53d406a742b52011ffd90a`.
Extract the body after the CLI prompt-preview `... (truncated)\r\n` delimiter
and before the timing footer; full stdout files differ in speed reports.
The prompt preview cuts a UTF-8 character in both files, so full-file strict
UTF-8 decoding fails; the generated body itself decodes correctly and matches.
This is a display-preview boundary, not generated-output corruption.
Generated token count is 512 in both; output ends at the imposed budget.
Saved token-ID/logit traces were not collected in these CLI runs; numeric
A/B equivalence is covered by the preceding native gate, not this byte check.

The ordered `accept_carry` histories match on all 218 generation rounds:

| Accepted in a round | A count | B count |
|---|---:|---:|
| 0: rejected | 48 | 48 |
| 1: partial acceptance | 47 | 47 |
| 2: full acceptance | 123 | 123 |

The sum is 293 accepted drafts, with 436 generated drafts. Both have 436
generation draft_decode calls and 218 catchup_decode/draft/accept_carry calls.
The improvement is not explained by different acceptance or fewer rounds.
No nonzero rc or incomplete end event occurs in either parsed report.

## Work removal and residual target cost

Generation memory groups below are CPU scope times; layout/pool_state and
seq_rm_indexer are distinct scopes. Do not add parent seq_rm, draft_decode or
catchup_decode time again on top of their children.

| Generation scope | A calls / seconds | B calls / seconds |
|---|---:|---:|
| draft layout | 654 / 9.767278 | 0 / 0 |
| draft pool_state | 654 / 0.017306 | 0 / 0 |
| draft seq_rm_indexer | 436 / 0.094139 | 0 / 0 |
| target layout | 218 / 5.027922 | 218 / 5.499980 |
| target pool_state | 218 / 0.008283 | 218 / 0.008474 |
| target seq_rm_indexer | 218 / 0.028312 | 218 / 0.028615 |

B has zero draft layout/pool_state/seq_rm_indexer events across *all* phases,
including prompt and unknown. A has 907/905/562 such events overall.
Generation A draft layout has 435 full/stale rebuilds and 111,114,370 copied
cells; B has no draft layout. Target counters are identical A/B:
217 full/stale rebuilds, 55,429,810 copied cells and 69,287,183 scan steps.
Target time is about 0.472 s higher in B despite identical work counters;
one run per arm does not establish a target regression.

Prompt A has 250 draft layout calls / 1.240349 s and 250 draft pool_state
calls / 0.014606 s; B has zero. Target prompt layout remains 250 calls in each
arm, 1.312196/1.314714 s. Removing prompt bookkeeping of this scale is
consistent with a tiny PP change; it does not resolve the overall MTP PP cost.

Startup evidence confirms requested0/eligible1/omitted0/reason disabled in A
and requested1/eligible1/omitted1/reason dense_single_block in B, at layer48,
ratio0. Both retain target attention KV6144MiB and indexer KV1536MiB, and draft
attention KV512MiB. Only A logs the draft indexer KV128MiB allocation.
This is an allocation-log difference, not a measured 128MiB process-memory
drop. The printed common memory breakdown describes the target context.

Measured generation saving 9.00755 s is close to the removed 9.767278 s
draft layout cost, with other scopes changing too. These CPU interval
measurements support dense-draft indexer maintenance as a major cause of the
long-context TG slowdown. They are not GPU kernel timings or an exact
prediction for normal ABBA. B still spends 5.499980 s (~21.48% of its reported
generation time) in target layout, making target suffix/no-op maintenance the
next bounded TG source investigation after normal validation.

## Diagnostic accounting

| Report | A-wall | B-wall |
|---|---:|---:|
| Parsed end events | 19,861 | 17,487 |
| Unmatched phase events | 1,026 | 896 |
| Covered server generation seconds | 34.501018 | 25.502965 |
| Approximate uncovered generation seconds | 0.115032 | 0.105535 |
| Generation coverage | 99.67% | 99.59% |

Both Status=Complete, Issues=[], PhaseAlignmentWarning=null.
Unmatched records are outside matched phase scopes, not failed operations:
A has target memory503/draft memory508/unknown Vulkan15; B has target
memory503/draft memory378/unknown Vulkan15. Keep them explicit rather than
inventing a prompt/generation assignment. Inclusive groups are nested;
coverage is the interval union of server generation scopes.

## Next measurement

Gate A native correctness and Gate B allocation/short CLI gates already passed.
Gate C now confirms intended work removal and matched real output/acceptance.
Run only the existing normal 256k ABBA next:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-abba.psd1 -PlanOnly
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-mtp-dense-indexer-abba.psd1 -StopOnError
```

Exactly A1,B1,B2,A2, all MTP ON; A omission0, B omission1,
LLAMA_MTP_DIAG=off. Same verified executable/DLL digest and 256k workload.
Review both repetitions per arm, mean TG and generation seconds, PP and full
prompt+generation time, output/acceptance and absence of diagnostic events.
The wall matrix took 39.832 minutes; four normal runs are roughly an 80-minute
planning estimate, not a measured duration.

No code/config change or rebuild accompanies this recording. Preserve the
existing manifest. Do not switch the source default ON or expand into a full
matrix before normal review. If the normal gain is useful and consistent,
prepare focused 128k confirmation and then separate target-layout work,
MTP PP diagnosis and ROCm PP scaling according to the roadmap.
COMMON-005 decode remains deferred.

Related:
[implementation and gates](R4-COMMON002-DENSE-INDEXER-IMPLEMENTATION-2026-10-04.md),
[short validation](R4-COMMON002-DENSE-INDEXER-SHORT-VALIDATION-2026-10-04.md),
[earlier wall baseline](R4-COMMON002-WALL-DIAGNOSTICS-2026-10-04.md),
[roadmap](ROADMAP.md).
