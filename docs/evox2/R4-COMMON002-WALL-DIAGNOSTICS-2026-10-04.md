# r4 COMMON-002: long-context wall diagnostics and report recovery

Recorded: 2026-10-04 JST. Archive:
`20261004-115840-898-qwen38-r4-mtp-diagnostics.zip`.
Runtime is b11401/a1b343c69, Clang 20.1.8, Vulkan, UMA label 96GB.
Scripts are from ef0ecf7; the upstream pin remains bed0a856606ee4a24a164066f73d2379447033f5.
All three runs use the same Verified runtime artifact digest recorded in the
[short validation](R4-COMMON002-SHORT-VALIDATION-2026-10-04.md).

## Completion and the reported error

All three inference processes exited 0 and generated 512 tokens. The final
256k OFF run was marked DIAGNOSTIC_INCOMPLETE only after inference, by the
diagnostic parser. Its stderr, completion summary, performance results,
resources and paired diagnostic records are available. This is a report
classification bug, not a Vulkan crash or an interrupted model run.

Two startup records are the complete causal chain:

| Event | Identity | Observed return |
|---|---|---|
| seq_rm | memory-34788152-6 | seq=0, pos_first=1, pos_last=-1, rc=-1, complete=0 |
| seq_rm_recurrent | memory-34788156-7 | child of the above, rc=-1, complete=0 |

Immediately afterwards stderr prints
`the context does not support partial sequence removal` from common_context_can_seq_rm.
Pinned `common/common.cpp` clears memory, evaluates two test tokens, and tries
llama_memory_seq_rm(mem, 0, 1, -1). A false return sets the normal capability
result to COMMON_CONTEXT_SEQ_RM_TYPE_FULL, clears/synchronizes the temporary
state, and returns. The recurrent memory implementation intentionally refuses
unsupported partial removal. With MTP's bounded rollback enabled, the helper
can return COMMON_CONTEXT_SEQ_RM_TYPE_RS before this probe, explaining why the
same refusal is absent from the ON runs.

The original diagnostic helper sets complete=0 on nonzero operation status.
The parser wrongly treated every such record as a globally incomplete run,
including this recognized negative capability test. It now recognizes only an
immediately logged, pre-request probe with the exact root/child relationship,
operation shape, return statuses, paired records, thread and interval nesting.
The refusal remains in Events with its original rc/complete and an
ExpectedRefusal annotation; top-level ExpectedRefusals and group counts expose
it explicitly. No general suppression of unknown-phase failures is introduced.
Other refusals, post-request failures, exceptions, malformed records and missing
begin/end records continue to fail completeness.

## Observed results (wall diagnostics enabled)

| Context | MTP | Prompt tokens | PP tok/s | TG tok/s | TG seconds | Acceptance |
|---|---|---|---|---|---|---|
| 128k | ON | 126,253 | 269.61 | 22.78 | 22.43084 | 292 / 436 = 66.972% |
| 256k | ON | 255,181 | 229.80 | 14.70 | 34.75906 | 293 / 436 = 67.202% |
| 256k | OFF | 255,181 | 268.37 | 19.69 | 25.94587 | — |

All produce 512 tokens. ON uses DraftMax=2/p-min=0 with 218 draft rounds in
both contexts. These are single diagnostic samples, not an unprofiled ABBA
comparison. Diagnostic OFF still means MTP OFF with LLAMA_MTP_DIAG=wall;
it is not the normal performance baseline.

After re-parsing the same raw logs with the fixed parser:

| Run | Events | Report | Recognized startup refusal probes | Unmatched phase events | Approximate uncovered TG |
|---|---|---|---|---|---|
| 128k ON | 16,487 | Complete | 0 | 522 | 84.294 ms |
| 256k ON | 19,861 | Complete | 0 | 1,026 | 117.362 ms |
| 256k OFF | 13,734 | Complete | 1 (two records) | 533 | 321.955 ms |

No phase-unmatched event falls inside the generation interval of any run.
Completeness recovery preserves every measured performance field; no model
execution or inference rerun is required.

## Measured CPU layout bottleneck

The layout scopes contain the CPU sequence-cell/pool-list update, not GPU
kernel time. Their generation intervals do not overlap each other, so this
table sums those scopes without adding their enclosing parents:

| Generation layout work | 128k ON | 256k ON | 256k OFF |
|---|---|---|---|
| Target layout CPU time | 2.142854 s | 5.113921 s | 0.004377 s |
| Draft layout CPU time | 3.064064 s | 9.901350 s | — |
| Combined layout CPU time | 5.206918 s | 15.015271 s | 0.004377 s |
| Target full/stale rebuilds | 218 / 218 | 217 / 217 | 0 / 0 |
| Draft full/stale rebuilds | 436 / 436 | 435 / 435 | — |
| Target copied cells | 27,580,169 | 55,429,810 | 0 |
| Draft copied cells | 55,159,396 | 111,114,370 | — |

128k -> 256k ON increases TG by 12.328220 s and measured layout time by
9.808353 s (79.6% of that increase in these wall samples). This directly
identifies a material long-history CPU cost, rather than inferring cost from
cell counts alone. Nearly unchanged acceptance and equal draft-round count
exclude an increased number of speculative rounds as the main explanation.

Draft CPU layout is distributed across two distinct server operations:

| Enclosing operation | 128k draft layout | 256k draft layout |
|---|---|---|
| draft_round | 0.942960 s | 4.541205 s |
| catchup | 2.121104 s | 5.360145 s |

Thus the existing draft-hook timer alone misses catch-up layout work. In 256k,
the catch-up wrapper takes 5.710287 s, containing 5.360145 s of draft layout
time. Do not add either wrapper to its children when reporting total TG.

Target verification selects union with three queries in both ON runs: 2,616
FA dispatches each. The initial 128k generation one-query evaluation selects
sparse. The 256k OFF control selects sparse with one query throughout its 511
generation evaluations (6,132 FA dispatches). Dense draft attention remains
dense. Dispatch timing is CPU command construction; it does not establish the
GPU duration of union versus sparse or eliminate that later question.

The next bounded candidate is eliminating unused dense-draft indexer/layout
bookkeeping, with correct memory-wrapper/ratio handling and rollback validation.
The measured 256k draft layout is the largest targeted CPU component. Main-model
suffix/no-op layout maintenance is a separate candidate afterward. Do not
subtract 15 s from TG and promise the resulting throughput: GPU overlap,
allocation/memory pressure and changed execution dependencies require normal
OFF-diagnostics confirmation after a correctness gate.

CPU layout attribution is already decisive enough to select a candidate without
the optional sync pair. GPU verification attribution remains conditional rather
than a reason to repeat the full diagnostic matrix now. MTP PP and ROCm PP remain
the subsequent priorities from ROADMAP.

## Script-only recovery and validation

The fix changes Python/PowerShell tools and documentation only; keep the existing
b11401/a1b343c69 binary and its manifest. No rebuild or repeat of the 46-minute
matrix is needed. Fourteen tests passed locally, including exact startup-probe
classification, rejection of unrecognized/late/missing-pair failures, diagnostic
status recovery with preserved timings, runtime-error protection and refusing
to mark a partially collected matrix complete. Windows still skips the three
g++ helper tests if g++ is unavailable; PowerShell execution remains a user gate.

The full uploaded archive was tested in an isolated scratch copy. Recovery
produced all three Complete reports, all three child statuses OK, and a complete
3/3 OK matrix with its CSV statuses updated. The uploaded archive was not altered.

From the repository root:

```powershell
git pull --ff-only
& .\tools\evox2\tests\Test-MtpDiagnostics.ps1
& .\tools\evox2\benchmark\Repair-MtpDiagnostics.ps1 `
    -MatrixDirectory .\evox2-logs\matrix\20261004-115840-898-qwen38-r4-mtp-diagnostics
```

Repair uses the child directories already recorded in matrix-result.json.
It regenerates diagnostic sidecars, restores only diagnostic-only failures with
exit 0/no runtime exception, updates result/summary/matrix status, and records
DiagnosticRecovery history. Raw logs and measured metrics are retained. A
runtime failure, still-incomplete report, child identity mismatch or missing
matrix run prevents successful matrix recovery.
