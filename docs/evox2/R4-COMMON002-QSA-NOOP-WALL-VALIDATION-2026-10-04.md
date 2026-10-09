# r4 COMMON-002: target QSA no-op 256k wall validation

Gate C passes: both runs are OK with verified startup/runtime evidence,
identical response bodies and identical ordered acceptance/position history.
B suppresses 123 unchanged-membership invalidations while preserving all 95
real-removal stale marks. Target generation full rebuilds fall 217 -> 95,
and target layout CPU time falls 5.529702 -> 2.436146 seconds.
Proceed to diagnostic-OFF normal ABBA using the same verified binaries.
Source default remains OFF; this wall pair does not establish repeatable
normal throughput or fresh-prompt MTP superiority over OFF.

## Submitted runs and conditions

Archive: `20261004-195334-038-qwen38-r4-qsa-noop-wall.zip`.
Matrix `20261004-195334-038-qwen38-r4-qsa-noop-wall` runs
19:53:34.175–20:34:19.933 JST on 2026-10-04 (40.763 minutes).
Complete=true, two planned/finished/OK runs, zero NonOK, not stopped early.
Both children exit 0 without a run exception; diagnostics are Complete with
no Issues or ExpectedRefusals.

| Arm | Child run | Target switch | Draft omission | PP tok/s | TG tok/s | Accepted/drafted |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| A-wall | `20261004-195336-034-cli-vulkan-b11416-ctx262144-ef59ec47c047` | 0 | 1 | 230.12 | 19.96 | 293/436 |
| B-wall | `20261004-201440-175-cli-vulkan-b11416-ctx262144-582e9d7320a8` | 1 | 1 | 229.92 | 22.71 | 293/436 |

Both use Vulkan b11416 / embedded commit `5df0bdbaf`, Clang 20.1.8,
Radeon 8060S and 96 GB UMA. BuildIdentity and RuntimeArtifactStatus are
Verified, matching the earlier allocation/short gate:

- Runtime artifact digest: `a90aedcdccacaada6b6a3105d7da3573c2b26797d128a6acfecd1430d5d358e6`
- CLI SHA-256: `5b6b39f51395b707a3b2c9eddb50eedb05e625fb1cdc7c10e82727c095c53ef3`

Main: `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`, 81,961,816,672 bytes.
Draft: `mtp-Qwen3.8-Flash-Next-Q8_0.gguf`, 4,137,429,120 bytes. Recorded
paths/lengths/mtimes match across arms and the short gate. Model hashes are
unset; the main-model identity comes from conditions/load records, rather
than the summary's last Q8_0 metadata belonging to the draft.

Input `nlp-survey-ch3-d31-b1.txt`: 1,261,235 bytes, SHA-256
`63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.
Both process 255181 prompt tokens and generate 512 tokens. Requested/actual
context=262144, f16, batch2048/ubatch1024, t4/tb4, ngl999, CPU MoE0, FA auto,
fit/reasoning OFF, cache RAM0, checkpoints0t, temp0.2/top-p0.8, seed1234,
ignore EOS, DraftMax2 and DraftPMin0. The command arguments are identical.
Environment differs only in `LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1`;
diagnostics=wall, draft omission=1, legacy MoE tile=1, get-rows-128x4=0 and
QSA union=1 are fixed.

Target QSA startup evidence is Verified in both: eligible target=1,
pool4/stream1/seq_max1, enabled0 for A and enabled1 for B. The draft remains
target0/eligible0/enabled0 with reason not_target. Dense-indexer omission is
Verified at draft layer48/ratio0/omitted1 in both.

## Output and acceptance

Response bodies are byte-identical: 2538 bytes, SHA-256
`70584ef998b9bbaf454e52f5d41dae21ade4e9ed4d53d406a742b52011ffd90a`.
The comparison excludes the echoed/truncated input and performance/exit footer.
Aggregate acceptance is 293/436 = 67.202% in both arms.

All 218 ordered `(accepted, drafted, pos_first)` target-trim records match.
Distribution: accepted0=48, accepted1=47, accepted2=123; drafted=2 each time.
Compact JSON history SHA-256:
`9148895e912d295548e71909c40d1dcb11a21389f137218244ba26a8d67603d2`.
The final trim is accepted2/drafted2 at pos_first255692.

## Target generation work and attribution

Totals below include only resolved target/generation groups. Each sidecar has
896 unmatched-phase events, with the same domain/event/role distribution.
These remain explicitly unknown; do not relabel setup/prefill maintenance
as generation or add it into the following totals. Complete diagnostic scopes
and unmatched phase attribution are separate checks.

| Target generation metric | A-wall | B-wall |
| --- | ---: | ---: |
| seq_rm calls / target_trim calls | 218 / 218 | 218 / 218 |
| noop_observed | 123 | 123 |
| noop_suppressed | 0 | 123 |
| stale_marked | 218 | 95 |
| pending_stale_preserved | 0 | 0 |
| layout calls | 218 | 218 |
| full_rebuilds / stale_rebuilds | 217 / 217 | 95 / 95 |
| copied_cells | 55429810 | 24265693 |
| appended_cells | 3 | 369 |
| scan_steps | 69287183 | 30332541 |
| layout CPU elapsed, seconds | 5.529702 | 2.436146 |
| pool_state calls | 218 | 218 |
| pool_state logical_new / padded_new | 163 / 218 | 163 / 218 |

Every one of the 95 actual membership decreases still marks stale in both
arms. All 123 suppressed B removals have equal membership before/after,
unchanged stale state and stale_marked=0. No pending stale case occurs in this
CLI sequence; the native gate separately validated that preservation path.
The final full-accept trim has no subsequent decode, so 123 suppressions
remove 122 rebuilds. The planned conditional 217 -> 95 mechanism check is met.

The layout scope reduction is 3.093556 seconds (-55.94%). The reported
generation evaluation reduction is 3.108240 seconds; their close agreement
supports attribution to removed layout work. Layout InclusiveUs=ExclusiveUs
here; do not sum nested diagnostic groups or call this GPU kernel time.
Draft seq_rm remains 436 calls and no draft layout/pool-state groups exist
in either arm. Pooled logical/padded new counts are unchanged.

Resource monitoring records 620/583 samples. Peak target working set is
3.307 GiB in both, private commitment 98.146/98.145 GiB, GPU local95.764 GiB
and shared2.524 GiB in both; peak committed percentage85.2/85.1. These sampled
counters do not prove absence of every transient pressure event, but show
no material A/B peak allocation difference.

## Timing interpretation

| Reported evaluation time | A-wall, seconds | B-wall, seconds | B minus A |
| --- | ---: | ---: | ---: |
| Prompt | 1108.918650 | 1109.848310 | +0.929660 |
| Generation | 25.606340 | 22.498100 | -3.108240 |
| Total evaluation | 1134.524990 | 1132.346420 | -2.178570 |
| Whole child process | 1246.262 | 1173.364 | -72.898 |

TG improves 19.96 -> 22.71 (+13.78%); PP changes 230.12 -> 229.92 (-0.09%).
The wall pair confirms intended work removal and a promising timing signal.
Normal ABBA must establish performance without diagnostic overhead/order bias.
Fresh-prompt evaluation improves only about 0.19% in this pair because PP
dominates the 512-token workload. Whole-process duration includes loading and
startup; the 72.898-second process difference is not the candidate's measured
TG saving. No same-session MTP OFF arm exists, so this is not an OFF comparison.

B retains 95 real suffix rebuilds costing 2.436146 seconds. That residual
supports keeping separate suffix-layout reuse next in the TG investigation
after normal ABBA review. It does not authorize merging CPU layout dirtiness
with pooled GPU-key invalidation. MTP PP and ROCm long-context PP remain later
priorities, with COMMON-005 deferred.

## Next gate

Run the four diagnostic-OFF A1/B1/B2/A2 arms from the same verified binary:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-abba.psd1
```

Both draft omission=1 and target A0/B1 pairing are fixed by the plan. Review
all four statuses, executable/runtime/startup identity, generated tokens,
output and acceptance, then normal PP/TG and total evaluation time. No rebuild
is needed for this documentation update. Default remains OFF; focused128k
and ROCm coverage are still expansion gates.

See [implementation](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md) and
[allocation/short gate](R4-COMMON002-QSA-NOOP-SHORT-VALIDATION-2026-10-04.md).
