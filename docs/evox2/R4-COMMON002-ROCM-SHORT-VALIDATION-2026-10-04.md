# r4 COMMON-002: ROCm native, allocation and short CLI validation

The ROCm native gates and allocation/short gate pass. Both native suites are
Complete with SourceChecks/PolicyTest/ModelTest Passed and Verified build
identity; all three allocation and five short CLI runs are OK with exit0.
Candidate A/B output and aggregate acceptance match, and short wall histories
match. Proceed to the prepared three-run ROCm256k normal plan using the same
verified binaries. Keep the short B-normal PP outlier explicit; this gate
establishes behavior and work removal, not a ROCm throughput gain.

## Archive, runtime and native gates

Archive: `20261004-233327-868-qwen38-r4-qsa-noop-rocm-check.zip`.
Dense-indexer native suite runs23:08:14.608–23:11:26.785 JST; target no-op
suite23:15:47.118–23:22:37.895 JST on2026-10-04. All four native processes
exit0. BuildIdentity=Verified; policy and completed-model PASS markers exist.

- Dense suite: all36 comparisons with matched execution partition have
  nmse0/max_abs0. Eight separately labeled diagnostic-only partition-tail
  comparisons are nonzero (different execution partitions) and are not the
  pass/fail numeric gate. Do not claim all44 comparisons are exact or change
  the gate threshold to accommodate those informational rows.
- Target no-op suite: all524 logits/hidden comparisons have nmse0/max_abs0.
  The native memory records show67 suppressed no-op invalidations and33
  pending-stale preservations. Numeric, pool-boundary, rollback, state,
  unsupported/fallback and refusal-continuation checks pass.

Native model executable artifact-set digests:

| Suite | Runtime digest |
| --- | --- |
| Dense-indexer model | `d5f32e3b082e6194cc6fe389a590fc0b161fb1defd4bd99c366d965ba88f7b2c` |
| Target no-op model | `10991f61018e2d8b294ae1693cbd7233168cf7e1260e728fe07d005735123e8d` |

All eight CLI runs use ROCm b11420 /embedded commit `131288531`, Clang23.0.0,
Radeon8060S /96GB UMA, BuildIdentity and RuntimeArtifactStatus Verified:

- CLI runtime digest: `aba45b977bb8bc68bc702142d7ad5db923af002705361f295c8f1ddb1a7b472f`
- CLI SHA-256: `93a1f5fdcf7f9b7cfb2a4a32bf58b1d6591587ec0cbab6ac1f17689b5ca80145`

Main is the81,961,816,672-byte PLE16 UD-IQ3_XXS GGUF and draft is the
4,137,429,120-byte Q8_0 MTP GGUF. Recorded paths/lengths/mtimes match across
arms; model hashes remain unset. Main identity comes from conditions/load
records, not the summary's last Q8_0 metadata belonging to the draft.

CLI requested/actual context32768, f16, b2048/ub1024, t4/tb4, ngl999,
CPU MoE0, FA auto, fit/reasoning OFF, cache RAM0, checkpoints0t, temp0/top-p0.8,
seed1234 and ignore EOS. All MTP ON arms have DraftMax2/PMin0 and dense
omission1. Five short runs additionally use top-k1 and the same811-byte input,
SHA-256 `88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`.
No Vulkan tuning variables remain in the recorded CLI environment.

Every CLI target decision is Verified: target1/eligible1/pool4/stream1/seq_max1,
with requested0/1 respected. Draft target0/eligible0/enabled0 remains unchanged.
MTP ON draft omission is Verified at layer48/ratio0/omitted1; OFF has the
expected MtpDisabled draft status and independent Verified target enablement.

## Allocation and short results

Allocation runs start23:24:23,23:29:53 and23:30:43 JST. Each has18 prompt tokens
and32 generated tokens. All three response bodies match (148 bytes; SHA-256
`51e29c58ea6f5a538cca6a67ffcfffbb17d6193a152c3741952accfcbea0aca7`).
The MTP A/B acceptance is16/29 in both.

| Allocation arm | Target switch | PP tok/s | TG tok/s | Status |
| --- | ---: | ---: | ---: | --- |
| MTP OFF | 1 | 36.84 | 26.31 | OK |
| MTP A | 0 | 26.88 | 28.79 | OK |
| MTP B | 1 | 28.65 | 27.59 | OK |

Matrix runs23:33:28.074–23:41:10.052 JST (7.7 minutes), Complete=true,
five planned/finished/OK, zero NonOK, not stopped early. Each has163 prompt
tokens and128 generated tokens; allocated32k is not a32k input benchmark.

| Short arm | Target switch | Diagnostics | PP tok/s | TG tok/s | Accepted/drafted |
| --- | ---: | --- | ---: | ---: | ---: |
| control-mtp-off | 1 | off | 230.09 | 26.41 | — |
| A-normal | 0 | off | 182.67 | 32.37 | 68/118 |
| B-normal | 1 | off | 48.16 | 33.63 | 68/118 |
| A-wall | 0 | wall | 184.92 | 32.85 | 68/118 |
| B-wall | 1 | wall | 173.07 | 30.92 | 68/118 |

All four MTP ON bodies match (685 bytes; SHA-256
`9af8bac14893768f940030b0bfae90f36b43d97d361e49404be530376d61aec5`),
also matching the earlier Vulkan short MTP ON body. The OFF body differs
(661 bytes; SHA-256
`87c557760fc786b5dcdecb24255b71e1dd8ee025d97ad2e4d23d9aa6b38d0749`).
Cross-backend aggregate acceptance differs from Vulkan; within ROCm it is
68/118=57.627% in all four candidate arms.

## Short wall work and timing caveats

Both wall sidecars are Complete with no Issues/ExpectedRefusals. Each has13
events with unknown phase attribution; they remain excluded from generation.
All59 ordered `(accepted,drafted,pos_first)` trim records match: accepted0=14,
accepted1=22, accepted2=23; drafted2 per round. Compact JSON history SHA-256
`afdf7e70532e1fc8eb6705176db8051f651a24eb9216c9ed35e0f9dd50ad3fda`.

| Target generation metric | A-wall | B-wall |
| --- | ---: | ---: |
| seq_rm / layout / target_trim calls | 59 / 59 / 59 | 59 / 59 / 59 |
| noop_observed / noop_suppressed | 23 / 0 | 23 / 23 |
| stale_marked / pending_stale_preserved | 59 / 0 | 36 / 0 |
| full_rebuilds / stale_rebuilds | 58 / 58 | 36 / 36 |
| copied_cells / appended_cells | 13459 / 3 | 8625 / 69 |
| scan_steps | 16804 | 10853 |
| layout CPU elapsed, microseconds | 1744 | 1345 |
| pool_state logical_new / padded_new | 42 / 59 | 42 / 59 |

All36 actual membership decreases retain stale marks; all23 B suppressions
have equal membership and unchanged stale state before/after. Final accepted2
trim at pos_first290 has no following decode, explaining22 fewer rebuilds for
23 suppressions. Pending preservation is covered by native tests. Draft seq_rm
is118 calls in both and no draft layout/pool-state group exists. Layout scopes
have no nested children; do not sum nested group times or call this GPU time.

The layout saving is only399 microseconds. Normal TG rises32.37->33.63 while
wall TG falls32.85->30.92; neither single short pair establishes speedup.
B-normal PP is an explicit outlier:3.384780s versus0.892300s for A-normal and
0.881450/0.941810s for A/B wall. It is retained, not discarded or averaged
into a claimed candidate slowdown. Disk/page-input activity occurs during
late loading and around prompt processing in its resource samples, but those
system-wide counters do not establish a per-process cause. Logs contain no
fatal CLI error. Track PP in256k; investigate if the anomaly recurs.

Whole-process OFF durations327.942s for allocation and205.949s for short
include large startup/loading costs; reported evaluation totals are only
1.666810/5.517160s. Do not attribute startup savings relative to MTP ON to
the target candidate or substitute these durations for PP/TG timings.

## Next measurement

Native and short correctness/work gates support proceeding without a rebuild:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-rocm-256k.psd1
```

Run only OFF/A-normal/B-normal at256k now. Review runtime/setting identity,
output/acceptance, PP (including recurrence of the short outlier), TG and total
evaluation. Long ROCm performance remains pending. Then proceed to the staged
CLI/bench comparison before choosing a new optimization. Defaults stay OFF.
This validation update changes documents only; keep the current ROCm and
Vulkan binaries. See [ROCm/bench procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).
