# r4 COMMON-002: Vulkan diagnostic short gate

Recorded: 2026-10-04 JST. Source/binary:
`a1b343c695007de094db1ab2d5cdf464ad9f4440`, b11401, Clang 20.1.8,
Vulkan Radeon 8060S, UMA label 96GB. User archive:
`20261004-114405-456-qwen38-r4-mtp-check.zip`.

## Gate result

Both AllocationOnly runs and all three short matrix runs completed with status
OK and exit 0. All five report runtime artifacts Verified with the same digest
`ff2349ba445954a3e6a94ac4fc164fb18a183643702bd0392514b2cfc020b940`.
Their embedded commit matches a1b343c69; the manifest shows cache-preserving
BuildOnly metadata refresh, stable build source and BuildIdentity Verified.
This establishes the rebuilt Vulkan build and target-model smoke/short gate.
It does not establish ROCm, sync-mode or exhaustive logit/state equivalence.

| Run | MTP | Diagnostics | Prompt / output tokens | PP tok/s | TG tok/s | Draft acceptance |
|---|---|---|---|---|---|---|
| AllocationOnly | OFF | OFF | 18 / 32 | 50.25 | 28.88 | — |
| AllocationOnly | ON | OFF | 18 / 32 | 47.59 | 27.64 | 13 / 34 = 38.235% |
| Short input | OFF | OFF | 163 / 128 | 328.96 | 28.61 | — |
| Short input | ON | OFF | 163 / 128 | 299.83 | 34.92 | 69 / 116 = 59.483% |
| Short input | ON | wall | 163 / 128 | 296.41 | 35.34 | 69 / 116 = 59.483% |

The generated text portion of stdout is identical between ON normal and ON wall
in this archive. Both have 58 draft rounds and 69 accepted draft tokens. OFF text differs
from ON, but is readable; this is not by itself evidence of a new diagnostic
or rollback defect. No diagnostic records appear in the four disabled runs.
Single short runs cannot quantify throughput effects or statistical significance.

## Diagnostic coverage and observations

The wall report is Complete with no issues, 3,546 complete events and 7,092 raw
begin/end records. Every event reports rc=0. All 58 generation target evaluations
have three tokens. The accepted draft count at target trim is:

| Accepted from DraftMax=2 | Rounds |
|---|---|
| 0 | 14 |
| 1 | 19 |
| 2 | 25 |

This exercises natural rejection, partial acceptance and full acceptance. It
supports proceeding to attribution, while retaining the broader correctness
limits above.

All 34 phase-unmatched events lie outside the measured generation interval;
they are early memory/backend setup operations, not missing TG attribution.
The report's covered server generation is 3.584200 s, against reported TG
3.593220 s; the approximate residual is 9.020 ms. This is interval-union
coverage, not a sum of inclusive groups.

Generation memory layout observations:

| Memory role | Layout calls | Full / stale rebuilds | Copied cells | Layout CPU time |
|---|---|---|---|---|
| Target | 58 | 57 / 57 | 13,256 | 0.967 ms |
| Draft | 174 | 115 / 115 | 26,564 | 1.800 ms |

Frequent rebuilds are observable even in a short sequence. Their cost is small
here; the long-context change in both time and cell/scan counts is needed before
choosing a performance candidate. Counts can include empty sequence bookkeeping
and must not be interpreted as full-history copies without copied-cell counters.

The main target's generation FA records all show dense, query count 3 (696
calls); draft FA is dense for one-query drafting and three-query catch-up.
This validates branch/role/query recording at short history. It does not imply
the same branch is used at 128k/256k, where sparse/union eligibility differs.
Wall-mode sample/target-wait timings can consume GPU work submitted earlier.
Do not label them pure CPU sampling or GPU kernel duration.

## Matrix result-stream bug and fix

The individual wall result, ordinary summary CSV, text output and diagnostic
sidecars are valid. The Python summarizer's progress string was accidentally
returned on the PowerShell success stream before the structured measurement
summary. Invoke-BenchmarkMatrix treated it as another result object, producing
an extra empty M003 row and leaving the run-record child identifiers null; the
valid wall row is also present in matrix-results.csv/matrix-result.json.

`Summarize-MtpDiagnostics.ps1` now routes the progress message through Out-Host,
leaving its success stream empty. The wrapper retains nonzero exit handling.
`Test-MtpDiagnostics.ps1` adds a native-parser fixture checking zero success-stream
objects and complete JSON/CSV sidecars. No C++ or inference behavior changes.

Re-parsing the uploaded real wall log with the current Python parser confirms
Complete/no issues. Windows PowerShell execution of the new wrapper regression
test is pending in the user's environment. The archived GPU measurements remain
usable: no rebuild or repeat of the short model runs is required for this fix.

## Next collection

After pulling the script fix and running Test-MtpDiagnostics.ps1, proceed with
`qwen38-r4-mtp-diagnostics.psd1`: Vulkan 128k ON wall, 256k ON wall, 256k OFF wall.
Keep the b11401/a1b343c69 binary/artifact set. The later script-only commit differs
from the executable commit intentionally; each is recorded in conditions.
Only take sync runs if this wall collection leaves attribution unresolved.

User also prepared `C:\llama-b11160-mix-a6922cc-windows-x64-vulkan`:
PLE16 loading errors, original model generation succeeds with MTP OFF and ON.
These are reported smoke results, not uploaded benchmark numbers. Prebuilt
Vulkan is sufficient for a normal reference comparison. Use original GGUF with
the same draft/input/options and obtain r4 original controls when comparing
fork performance; do not attribute r4 PLE16 versus mix original differences
solely to the runtime fork. Source-build diagnostics remain a conditional step.
