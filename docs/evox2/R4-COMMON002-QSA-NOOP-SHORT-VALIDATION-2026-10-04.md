# r4 COMMON-002: target QSA no-op allocation and short CLI validation

Gate B passes: all three allocation smokes and five short CLI runs are OK,
with verified runtime/startup evidence. Candidate A/B response bodies and
acceptance match. The target switch suppresses only unchanged-membership
invalidations; all genuine suffix removals still mark the layout stale.
Proceed to the two-run 256k wall gate using the same binaries. Source default
remains OFF; normal ABBA follows only after reviewing that wall pair.

## Evidence and identity

Submitted archive: `20261004-192604-409-qwen38-r4-qsa-noop-check.zip`.
The allocation runs start at 19:23:44, 19:24:23 and 19:25:05 JST on
2026-10-04. Matrix `20261004-192604-409-qwen38-r4-qsa-noop-check` runs
19:26:04.550–19:30:25.950 JST: Complete, five planned/finished/OK runs,
zero NonOK, not stopped early. All eight processes exit 0 without a run exception.

All eight use Vulkan b11416, embedded commit `5df0bdbaf`, Clang 20.1.8,
Radeon 8060S / 96 GB UMA and the same Verified runtime artifact set:

- Runtime digest: `a90aedcdccacaada6b6a3105d7da3573c2b26797d128a6acfecd1430d5d358e6`
- CLI SHA-256: `5b6b39f51395b707a3b2c9eddb50eedb05e625fb1cdc7c10e82727c095c53ef3`

The recorded main model is `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`
(81,961,816,672 bytes; mtime 2026-09-16T00:32:20.766Z), paired with
`mtp-Qwen3.8-Flash-Next-Q8_0.gguf` (4,137,429,120 bytes;
mtime 2026-09-02T11:39:26.652Z). Recorded paths, lengths and timestamps
match across runs; model SHA-256 fields are unset. Main-model identity comes
from conditions and load records: the MTP ON summary's last Q8_0 metadata
belongs to the draft, not the main model.

Shared settings: requested/actual context 32768, f16, batch 2048, ubatch 1024,
t4/tb4, ngl999, CPU MoE 0, FA auto, fit/reasoning OFF, prompt RAM cache 0,
checkpoints 0t, temperature 0, top-p 0.8, seed 1234 and ignore EOS.
Vulkan legacy MoE tile=1, get-rows-128x4=0 and QSA union=1 are fixed.
All MTP ON arms use DraftMax=2, DraftPMin=0 and
`LLAMA_MTP_SKIP_DENSE_INDEXER=1`. A/B changes only
`LLAMA_QSA_SKIP_NOOP_INVALIDATION=0/1` within each matched diagnostic mode.
The five short runs additionally use top-k=1 and the same 811-byte input:
SHA-256 `88083a2910b0de75fdfc23d73a7e87ce3db0cf5110bb616ae102841be34368d5`.

New target startup evidence is Verified in all eight runs: target=1,
eligible=1, pool=4, streams=1, seq_max=1, with the requested setting observed.
The MTP draft reports target=0/eligible=0/enabled=0, reason=not_target.
Draft omission evidence is Verified for MTP ON (layer48, ratio0, omitted=1).
MTP OFF has the expected MtpDisabled draft-omission status while its target
switch is Verified and enabled. This confirms the independent target gate.

## Allocation smokes

Each is AllocationOnly with 18 prompt tokens and 32 generated tokens.
These are allocation/generation checks, not long-context throughput results.

| Arm | MTP | Target switch | PP tok/s | TG tok/s | Accepted/drafted | Status |
| --- | --- | --- | ---: | ---: | ---: | --- |
| OFF control | OFF | 1 | 47.10 | 29.06 | — | OK |
| A | ON | 0 | 41.96 | 27.88 | 13/34 | OK |
| B | ON | 1 | 44.92 | 27.90 | 13/34 | OK |

A/B response bodies are byte-identical (90 bytes; SHA-256
`e388e4b509163875789deb3b29d2c6f95f74f0bf67528113f1fc090dd950e67f`).
The OFF control generates different text. Forced generation with ignore EOS
can continue beyond OK; this does not indicate an A/B output regression.

## Five short CLI runs

Each processes **163 prompt tokens** and generates 128 tokens. The allocated
context is 32k; this is not a 32k input benchmark.

| Arm | MTP | Target switch | Diagnostics | PP tok/s | TG tok/s | Accepted/drafted | Status |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| control-mtp-off | OFF | 1 | off | 334.18 | 28.55 | — | OK |
| A-normal | ON | 0 | off | 299.28 | 34.81 | 69/116 | OK |
| B-normal | ON | 1 | off | 294.21 | 34.86 | 69/116 | OK |
| A-wall | ON | 0 | wall | 303.92 | 35.39 | 69/116 | OK |
| B-wall | ON | 1 | wall | 302.75 | 35.53 | 69/116 | OK |

All four MTP ON response bodies match exactly (685 bytes; SHA-256
`9af8bac14893768f940030b0bfae90f36b43d97d361e49404be530376d61aec5`).
The comparison excludes the echoed input, performance footer and exit text.
Aggregate acceptance is 69/116 = 59.483% in all four. The OFF response differs
(652 bytes; SHA-256
`a9bb118f899631bee8a160e7936b15817bdae14bb48d6a09eba2f23a1d74dfdf`);
output equality is established between candidate A/B arms, not between MTP modes.

Wall A/B additionally have identical ordered 58-round
`(accepted, drafted, pos_first)` target-trim histories: accepted0=14,
accepted1=19, accepted2=25, with two drafted tokens per round. Compact JSON
history SHA-256:
`10258bb38b09d0c4a36fe512cbbeed52a9a48db043b812014a280b21fafd3c6f`.
Normal runs have aggregate acceptance evidence, not ordered diagnostic traces.

Normal TG changes 34.81 -> 34.86 (+0.14%); PP changes 299.28 -> 294.21
(-1.69%). One short pair does not establish a throughput gain or regression.
Wall timings are attribution evidence, not normal performance measurements.

## Target generation accounting

Both wall sidecars are Complete with no Issues or ExpectedRefusals.
Each has 28 events with unmatched phase attribution; they remain explicitly
unknown and are excluded from the target-generation totals below. This is
phase attribution uncertainty, not an incomplete diagnostic scope.

| Target generation metric | A-wall | B-wall |
| --- | ---: | ---: |
| seq_rm calls | 58 | 58 |
| noop_observed | 25 | 25 |
| noop_suppressed | 0 | 25 |
| stale_marked | 58 | 33 |
| pending_stale_preserved | 0 | 0 |
| layout calls | 58 | 58 |
| full_rebuilds / stale_rebuilds | 57 / 57 | 33 / 33 |
| copied_cells | 13256 | 7976 |
| appended_cells | 3 | 75 |
| scan_steps | 16550 | 10050 |
| layout CPU elapsed, microseconds | 995 | 721 |

All 33 actual membership decreases still mark stale in both arms. Every one
of the 25 suppressed B removals has equal membership before/after, unchanged
stale state and stale_marked=0. No pending-stale case occurs in this CLI
sequence; the earlier native gate separately validated 33 such preservations.

There are 24 fewer rebuilds despite 25 suppressions because the final
accepted2/2 trim at pos_first290 has no following decode. Counts therefore
agree with the event order. Draft seq_rm has 116 calls in both arms and no
draft layout/pool-state groups, consistent with the fixed draft omission.

The layout elapsed reduction is only 274 microseconds at this short input.
Work counts confirm the intended mechanism, but cannot predict long-context
TG. Layout group times here have no nested children; do not sum all inclusive
diagnostic groups or treat these CPU scopes as GPU kernel timings.

## Next gate

Run only the two 256k wall arms now, from the same verified binary:

```powershell
& .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-noop-wall.psd1
```

Review runtime/setting identity, output and acceptance history, preserved real
removals and pending stale state, reduced target scan/copy/rebuild work and
PP before authorizing diagnostic-off normal ABBA. Exact counts can differ
from earlier runs; the old 217 -> 95 rebuild projection is conditional on a
matching acceptance history. Source default stays OFF. This documentation
update requires no rebuild. Focused 128k and ROCm coverage remain later gates;
suffix reuse, MTP PP work, ROCm PP scaling and deferred COMMON-005 keep their
existing priority order.

See [implementation and native evidence](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md).
