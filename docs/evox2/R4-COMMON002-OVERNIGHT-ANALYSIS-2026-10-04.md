# r4 COMMON-002: overnight results and long-context MTP investigation

Recorded: 2026-10-04 JST. Measurement/source review; no performance patch is
implemented by this document. Prioritize MTP decode regression, then MTP prompt
overhead, then ROCm long-context prompt scaling, as requested by the user.

## Outcome and scope

All **28/28 runs passed**, exit 0, 512 generated tokens each. The batch ran from
01:40:32 to 06:32:04 JST (291.536 minutes). Both backends complete dense-sidecar
MTP through 256k after the input guard fix. This establishes runtime coverage,
not exhaustive output/logit/rollback equivalence.

MTP improves TG at 64k, loses its advantage around 128k, and is slower at 256k.
Acceptance remains about 67% on Vulkan at both 128k and 256k; its decline cannot
explain the sharp 256k regression by itself. ROCm likewise has a 256k TG loss.

Current logs support a growing per-round cost. Source inspection identifies:
dense draft attention plus draft catch-up re-evaluation; CPU pool-layout rebuilds
after sequence edits; unnecessary indexer bookkeeping for this dense MTP sidecar;
and different main-model verification dispatches. Their individual wall-time
shares are not yet measured. Do not call the residual time "main model time."

## Reproducibility

Archive supplied:
`20261004-023243-703-cli-vulkan-b11390-ctx262144-56080c886037.zip`.

Matrix:
`20261004-014032-340-qwen38-r4-mtp-overnight`,
`qwen38-r4-mtp-overnight.psd1`, OFF/ON/ON/OFF within each backend/context.
Two samples per condition; tables below use arithmetic means. Rounded log
throughputs are averaged, while time comparisons use the measured durations.
Prompt + generation excludes model loading and process startup.

All conditions use the same main PLE16 file identity and matching input hash at
each context. Actual input lengths: 32k=29557, 64k=61789, 128k=126253,
256k=255181. f16 caches, batch=2048, ubatch=1024, threads/tb=4, GPU layers=999,
CPU MoE=0, FA=auto, fit=off, temperature=0.2, top-p=0.8, seed=1234,
ignore-eos, reasoning=off, prompt cache=0, checkpoints=0t. MTP uses the same
Q8_0 sidecar, DraftMax=2, p-min=0.

| Identity | Vulkan | ROCm |
|---|---|---|
| Build manifest source | `e8f3be2e9ff9e3b7b3fbfe2aaa08cf4158f55bf7` | `b1623c961d35988342094d08e02815aeadf0913a` |
| Embedded version label | b11390 / `5814fbe99` | b11380 / `a60a57879` |
| Compiler | Clang 20.1.8 | Clang 23.0.0 |
| Executable SHA-256 | `00af95d17e7a340db7b901d9d7f65c7da97db75c523de92abeda20216b60a474` | `7d8bd068c9556b216216bb13ea6a8d9d079b38cee79d716363b250f866f89f7c` |
| Legacy MoE / GET_ROWS 128x4 / union | 1 / 0 / 1 | unset / unset / unset |

Working trees report clean `b1623c9`. That commit only added documentation and
the matrix; runtime source matches the dense-MTP fix. Incremental-build version
labels are stale, so identify builds using manifest source and artifact hashes.
The executable is a small launcher; do not equate its hash with all backend DLLs.
Known profiler/experiment overrides were cleared; normal timings are unprofiled.

No assert, NaN, Vulkan error, or checkpoint replay was reported. Four Vulkan
MTP runs (128k/256k) emit a compute-buffer-size expectation warning during
context destruction, after successful output and timing. Preserve it as a
nonfatal allocator-accounting observation; no causal timing link is established.

Within each Vulkan OFF or ON pair the generated output bytes match; ROCm
repetitions differ despite the fixed seed. Generated excerpts remain readable
Japanese. OFF versus ON outputs are not identical. Do not treat these
temperature-0.2 performance runs as an exact-output correctness test.

## Performance

| Backend | Context | PP OFF → ON (tok/s) | TG OFF → ON (tok/s) | TG change | ON acceptance | PP+TG OFF → ON (s) | Total change |
|---|---|---:|---:|---:|---:|---:|---:|
| Vulkan | 64k | 334.68 → 310.19 | 25.75 → 29.84 | 15.9% | 72.8% | 204.47 → 216.33 | 5.8% |
| Vulkan | 128k | 294.27 → 266.09 | 23.27 → 23.02 | -1.1% | 67.0% | 451.01 → 496.69 | 10.1% |
| Vulkan | 256k | 265.02 → 228.08 | 19.76 → 15.25 | -22.8% | 67.2% | 988.73 → 1152.38 | 16.6% |
| ROCm | 32k | 440.19 → 412.09 | 23.99 → 31.29 | 30.4% | 71.6% | 88.45 → 88.07 | -0.4% |
| ROCm | 64k | 370.13 → 347.41 | 21.12 → 25.48 | 20.6% | 70.1% | 191.13 → 197.91 | 3.5% |
| ROCm | 128k | 277.57 → 260.15 | 16.88 → 17.73 | 5.1% | 69.6% | 485.15 → 514.14 | 6.0% |
| ROCm | 256k | 185.72 → 173.81 | 12.41 → 10.96 | -11.7% | 65.6% | 1415.21 → 1514.80 | 7.0% |

At 512 generated tokens, every 64k+ case has worse total prompt+generation time
with MTP. ROCm 32k's mean total reduction is only 0.4%, within the observed
run-to-run variation; it is not an established end-to-end gain. Do not promote
MTP globally based only on short-context TG.

Vulkan 256k TG repeats are OFF 19.80/19.72 and ON 15.20/15.29 tok/s; the
regression is much larger than the observed pair variation. At Vulkan 128k,
OFF 23.27/23.27 and ON 23.00/23.03 are effectively near parity with a small loss.

## First investigation: why long-context MTP slows decode

### Measured drafting time is only part of the overhead

The existing `dur(b,g,a)` line measures begin, draft, and accept hooks.
`common_speculative_process()` has no corresponding timer. Its MTP
implementation performs a separate draft decode after the target batch, so the
reported `g` time excludes this catch-up, target verification, sequence/cache
management, and other host/sampling work. GPU submission/synchronization
boundaries also prevent treating these wall timers as pure kernel time.

| Backend | Context | Draft calls | ON generation (s) | Draft hook g (s) | Remaining generation (s) | Draft g/call (ms) |
|---|---|---:|---:|---:|---:|---:|
| Vulkan | 64k | 208.0 | 17.127 | 2.477 | 14.650 | 11.91 |
| Vulkan | 128k | 218.0 | 22.203 | 3.543 | 18.660 | 16.25 |
| Vulkan | 256k | 218.0 | 33.518 | 7.388 | 26.130 | 33.89 |
| ROCm | 32k | 210.5 | 16.345 | 3.116 | 13.229 | 14.80 |
| ROCm | 64k | 213.0 | 20.054 | 3.607 | 16.446 | 16.94 |
| ROCm | 128k | 213.5 | 28.832 | 4.905 | 23.927 | 22.97 |
| ROCm | 256k | 221.0 | 46.639 | 8.947 | 37.692 | 40.48 |

For Vulkan 128k → 256k:

- Both ON runs make 218 draft calls, with nearly unchanged acceptance (66.97%
  → 67.20%) and mean accepted length (2.34).
- Draft hook time rises 3.543 → 7.388 s, about +3.845 s.
- Remaining generation rises 18.660 → 26.130 s, about +7.470 s.
- Total generation rises 22.203 → 33.518 s. About one third of that increase
  lies in the measured draft hook and two thirds outside it.

At 256k the ON residual alone (~26.13 s) is already comparable with all OFF
generation (~25.86 s), before adding ~7.39 s of drafting. Improving acceptance
alone is unlikely to remove all of this overhead.

### A. Dense draft attention and verification catch-up

Confirmed sidecar metadata has MTP layer 48 compression ratio zero.
`graph_mtp` therefore takes ordinary dense attention, reading its own full
attention KV history. The main model's QSA does not make this draft sparse.

For this non-shared-cache model, `process()` pairs every target token with the
previous target hidden state and calls `llama_process(ctx_dft, ...)`.
It runs after prompt batches and verification batches. The server explicitly
notes that drafts are currently re-evaluated for simplicity. Thus speculative
tokens cost both draft generation and later catch-up work. As KV grows, both
dense draft attention paths become more expensive.

This source mechanism is confirmed; its exact GPU-time contribution needs
phase-aware profiling. It does not by itself account for every extra second.

### B. CPU pool-layout rebuild after sequence removal

The server trims target sequence state after verification and removes speculative
draft state before verification. `llama_memory_hybrid_idx::seq_rm()` marks the
indexer layout stale. `kpool_layout_update()` then rebuilds its CPU cell vector
and pool list whenever stale, even for a suffix edit:
`sq.cells.assign(sp.begin(), sp.end())`, clear pools, restart scan at zero.

This creates a full-history CPU pass where ordinary append can extend only the
tail. The next `kpool_build_state()` carefully limits **GPU re-pooling** to
affected pools, so this is NOT evidence that all cached pooled keys are
recomputed on the GPU. Measure CPU layout reconstruction independently.

The same issue can occur in the draft memory wrapper. The dense MTP graph no
longer registers unused QSA inputs, but `llama-model.cpp` still creates an
indexer cache/filter for the MTP block based on global indexer metadata.
`kpool_track()` checks the presence of that cache and global kpool, not whether
the active MTP layer uses QSA. Its context still applies indexer slots/layout
updates although the dense attention graph does not consume them.

Concrete low-scope candidate: retain the hybrid-indexer wrapper required by
`graph_mtp`, but leave its indexer cache absent when **all active MTP layers**
have ratio zero. The constructor already supports a null indexer filter.
Test positive-ratio MTP and main-model behavior separately before accepting a
change. A broader suffix-only layout update is a second candidate; it must
handle partial pools, position/order grouping, shared cells and rollback exactly.

### C. Main verification changes the Vulkan dispatch

`ggml_vk_flash_attn()` tries grouped union before ordinary sparse attention.
The union guard accepts query counts **2 through 4096**, not only large prompt
batches. DraftMax=2 normally verifies up to three tokens together, so main
verification can take union while ordinary one-token decode cannot.

The existing one-time "union active" message is emitted during prefill and does
not prove which verification dispatch ran. Add a phase/query-count counter.
Then compare small-query union against the existing fallback while preserving
large-batch PP union. Globally disabling union would also change PP and is a
poor first isolation experiment. Correctness tests must cover differing
per-query selections, causal masks, tails and rollback.

This candidate is Vulkan-specific. ROCm's 256k loss shows that union cannot be
the sole explanation across both backends.

### Memory and replay checks

Both contexts report the expected target bounded recurrent rollback with two
snapshots. No checkpoint restore/replay message appears in these logs.
That weakens checkpoint replay as the main explanation, but is not a proof
against every state-management cost.

Vulkan 256k ON reaches ~93.36 GiB process GPU Dedicated and ~2.52 GiB Shared.
During steady TG, the sampled disk reads and page input are zero, with roughly
23 GiB CPU-side free RAM. There is no observed disk-paging explanation for the
Vulkan TG regression. These WDDM/UMA counters are not a direct physical memory
partition and should not be summed into an allocation-failure claim.

ROCm steady TG has small system-wide disk/page activity (~0.4–1.5 MiB/s mean
reads in the 256k runs). This cannot establish per-process residency or exclude
all memory effects, but it does not explain the clean, repeatable scaling by
itself. Startup/teardown samples can show much larger paging and low free RAM;
do not use whole-run extrema as steady-decode evidence. Phase windows here are
approximately aligned using stderr timing and two-second resource samples.

## Second investigation: MTP prompt overhead

| Backend | Context | OFF prompt (s) | ON prompt (s) | Added prompt time (s) |
|---|---|---:|---:|---:|
| Vulkan | 64k | 184.620 | 199.201 | 14.580 |
| Vulkan | 128k | 429.048 | 474.489 | 45.442 |
| Vulkan | 256k | 962.867 | 1118.859 | 155.992 |
| ROCm | 32k | 67.147 | 71.726 | 4.579 |
| ROCm | 64k | 166.938 | 177.856 | 10.918 |
| ROCm | 128k | 454.870 | 485.305 | 30.435 |
| ROCm | 256k | 1374.021 | 1468.161 | 94.140 |

Vulkan's added PP time grows ~14.6 → 45.4 → 156.0 s from 64k to 256k.
ROCm grows ~10.9 → 30.4 → 94.1 s over those contexts. This is compatible with
the extra dense draft attention's superlinear prefill work, plus hidden-state
transfer and bookkeeping. The totals alone cannot assign all of the increase
to attention.

Source also copies target HC hidden states out to a host buffer and supplies
them back as draft inputs. Width is 10240 f32 values per token (~40 KiB).
At 255181 prompt tokens this is ~9.73 GiB for one traversal of the hidden
rows, before the return upload and CPU copies. This is data volume, not a
measured bandwidth bottleneck; on UMA, transfers still have copy/sync costs.

Investigate in this order:

1. Measure target PP, draft catch-up PP, hidden-state synchronization/copy, and
   indexer-layout work separately.
2. Remove unused dense-draft indexer bookkeeping if the measurements and
   compatibility checks support it.
3. Consider device-side hidden-state handoff or fewer host copies, preserving
   the token/previous-hidden pairing and batch boundaries.
4. Optimize dense draft prefill kernels/batching only after locating their cost.

Do not simply skip draft prefill or treat its KV as shared with the main model:
the sidecar has different attention projections and needs its own cache.
Deferring draft prefill moves latency and does not automatically reduce
end-to-end work.

Earlier r2 MTP-QSA work is a prior negative result, not a new proposed shortcut:
the recorded history reports lower attention time offset by indexer/top-k/
gather/CONT costs, no net PP improvement at 64k, and worse decode. The
`test/mtp-qsa-prototype` prefill-only/49152-threshold experiment remained
unmerged. Revisit only if phase measurements show a newly removed cost or a
different longer-context crossover; do not alter GGUF ratios to force QSA.

## Third investigation: ROCm long-context PP scaling

MTP-OFF PP is 370.13 vs 334.68 tok/s at 64k (ROCm ahead), 277.57 vs 294.27
at 128k, and 185.72 vs 265.02 at 256k (Vulkan ahead). A within-run comparison
also shows the crossover, so this is not just timing drift between context runs.

Local PP rates derived from adjacent progress records, using intervals wholly
inside each prefix band in the two **256k MTP-OFF** runs:

| Prefix band | Vulkan A1 / A2 (tok/s) | ROCm A1 / A2 (tok/s) |
|---|---:|---:|
| 32k–64k | 288.65 / 288.58 | 315.78 / 315.96 |
| 112k–144k | 255.36 / 254.85 | 184.32 / 184.56 |
| 216k–approximately 249k | 229.18 / 229.36 | 118.19 / 118.27 |

The model graph hands full K/V plus a sparse selection mask to attention.
Vulkan's enabled union compacts the selected rows for prompt groups.
In the pinned CUDA/HIP source, mask-to-sparse-indices and the MMA sparse
dispatch are excluded under `GGML_USE_HIP`; HIP falls back to
`use_sparse_kernel=false`. Causal upper-bound trimming can still exist;
this is specifically a missing selected-row compaction path, not a claim
that absolutely every future masked cell is always evaluated.

A full-KV-span kernel path explains why ROCm's initially fast PP can lose its
advantage as context grows. This is a strong source-backed hypothesis, not a
GPU profile of the present 28 runs. The QSA indexer itself also grows with
context on both backends; profile its cost along with FA and MoE matmuls.

After the MTP investigations, profile ROCm PP at early and late prefixes.
If FA dominates the growth, evaluate a **grouped selected-K/V union path for
PP** on HIP (gather plus a suitable existing FA kernel, with exact per-query
masks). Reassess CUDA sparse portability instead of deleting HIP guards:
warp, tile and backend requirements need implementation and correctness work.
This is related to COMMON-005's compact-attention goal, but the frozen r3
decode-oriented design is not automatically a complete PP solution.

## Next focused measurement and decision gates

First add opt-in diagnostic counters, leaving normal inference unchanged:

- Per context and phase: target decode/verify wall time, draft `process()`
  time, draft `draft()` time, hidden-state extraction/synchronization, and
  sequence removal/layout-update time.
- Count layout full rebuilds, cells traversed, newly GPU-pooled blocks, and
  whether the cache is safe; distinguish main from draft.
- Record actual query count and attention dispatch for target verification;
  identify the MTP block separately in GPU profiles.
- Place synchronization deliberately at diagnostic boundaries and label its
  overhead. Never compare profiled throughput directly with this normal baseline.

Start with MTP ON at 128k and 256k, DraftMax=2, otherwise the measured settings.
A focused 256k OFF control can then separate ordinary target decode. No need
to repeat all 28 conditions to locate the first cost.

Use those timings to select one change at a time: unused dense-draft indexer,
suffix layout maintenance, small-query verification dispatch, or dense draft
attention/catch-up. DraftMax=1 is a later policy comparison, not a guaranteed
speed fix: it reduces draft work but also amortizes fewer accepted tokens.

After a candidate passes short deterministic/rollback checks, measure 256k
OFF/ON ABBA without diagnostic timers, then the affected 64k/128k cases.
Only then proceed to the PP investigations. All kernel attribution and
performance improvements beyond the measurements above remain unverified.

## Source anchors

Source is pinned to runtime-equivalent r4 commit
`b1623c961d35988342094d08e02815aeadf0913a`, upstream
`bed0a856606ee4a24a164066f73d2379447033f5`.

- [MTP graph and dense/QSA selection](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/src/models/qwen4exp.cpp): `graph_mtp`, `build_layer_attn`.
- [MTP hooks and existing timer scope](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/common/speculative.cpp): `common_speculative_impl_draft_mtp::process/draft`, `common_speculative_process/draft`.
- [Verification, re-evaluation and sequence trimming](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/tools/server/server-context.cpp): `TAG_SPEC_AVOID_DRAFT_REEVAL`, `post_decode`.
- [Indexer allocation filters](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/src/llama-model.cpp): Qwen4Exp MTP `filter_idx`.
- [CPU layout rebuild and bounded GPU re-pooling](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/src/llama-memory-hybrid-idx.cpp): `seq_rm`, `kpool_layout_update`, `kpool_track`, `kpool_build_state`.
- [Hidden-state extraction](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/src/llama-context.cpp) and [draft input upload](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/src/llama-graph.cpp).
- [Vulkan union query-count guard](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/ggml/src/ggml-vulkan/ggml-vulkan.cpp): `ggml_vk_qsa_union`, `ggml_vk_flash_attn`.
- [CUDA/HIP dispatch](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/ggml/src/ggml-cuda/fattn.cu) and [HIP sparse exclusion](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b1623c961d35988342094d08e02815aeadf0913a/ggml/src/ggml-cuda/fattn-mma-f16.cuh).
- Historical [ROCm decode trace](ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md) is r3 evidence; do not substitute it for current r4 PP profiling.

## Individual runs

| Run ID | MTP | PP (tok/s) | TG (tok/s) | PP+TG (s) | Acceptance |
|---|---|---:|---:|---:|---:|
| `20261004-014034-592-cli-vulkan-b11390-ctx65536-2e29da11fb85` | OFF | 335.30 | 25.88 | 204.03 | — |
| `20261004-014445-031-cli-vulkan-b11390-ctx65536-fe2f47594186` | ON | 310.60 | 29.92 | 216.01 | 72.84% |
| `20261004-014909-464-cli-vulkan-b11390-ctx65536-fe2f47594186` | ON | 309.77 | 29.75 | 216.65 | 72.84% |
| `20261004-015334-907-cli-vulkan-b11390-ctx65536-2e29da11fb85` | OFF | 334.06 | 25.62 | 204.91 | — |
| `20261004-015746-167-cli-vulkan-b11390-ctx131072-cb9e6f56a32b` | OFF | 294.20 | 23.27 | 451.10 | — |
| `20261004-020603-879-cli-vulkan-b11390-ctx131072-3092afd382b6` | ON | 266.04 | 23.00 | 496.79 | 66.97% |
| `20261004-021514-864-cli-vulkan-b11390-ctx131072-3092afd382b6` | ON | 266.13 | 23.03 | 496.60 | 66.97% |
| `20261004-022425-862-cli-vulkan-b11390-ctx131072-cb9e6f56a32b` | OFF | 294.33 | 23.27 | 450.91 | — |
| `20261004-023243-703-cli-vulkan-b11390-ctx262144-56080c886037` | OFF | 265.16 | 19.80 | 988.17 | — |
| `20261004-025005-448-cli-vulkan-b11390-ctx262144-36b73ec4f8e1` | ON | 228.15 | 15.20 | 1152.11 | 67.20% |
| `20261004-031015-079-cli-vulkan-b11390-ctx262144-36b73ec4f8e1` | ON | 228.00 | 15.29 | 1152.65 | 67.20% |
| `20261004-033022-856-cli-vulkan-b11390-ctx262144-56080c886037` | OFF | 264.88 | 19.72 | 989.29 | — |
| `20261004-034745-016-cli-rocm-b11380-ctx32768-7d7024b1ef81` | OFF | 438.71 | 23.91 | 88.75 | — |
| `20261004-035006-179-cli-rocm-b11380-ctx32768-c9ad484baf99` | ON | 410.41 | 32.13 | 87.92 | 74.21% |
| `20261004-035231-385-cli-rocm-b11380-ctx32768-c9ad484baf99` | ON | 413.77 | 30.44 | 88.22 | 69.00% |
| `20261004-035455-645-cli-rocm-b11380-ctx32768-7d7024b1ef81` | OFF | 441.67 | 24.06 | 88.16 | — |
| `20261004-035713-710-cli-rocm-b11380-ctx65536-3ddec7bfb14c` | OFF | 370.04 | 21.09 | 191.21 | — |
| `20261004-040116-586-cli-rocm-b11380-ctx65536-cc456667844d` | ON | 347.30 | 25.67 | 197.82 | 71.84% |
| `20261004-040529-921-cli-rocm-b11380-ctx65536-cc456667844d` | ON | 347.52 | 25.29 | 198.00 | 68.29% |
| `20261004-040943-006-cli-rocm-b11380-ctx65536-3ddec7bfb14c` | OFF | 370.22 | 21.15 | 191.05 | — |
| `20261004-041345-818-cli-rocm-b11380-ctx131072-bd82cb13e106` | OFF | 275.76 | 16.65 | 488.52 | — |
| `20261004-042246-071-cli-rocm-b11380-ctx131072-ae4efe116570` | ON | 259.54 | 18.10 | 514.67 | 69.16% |
| `20261004-043217-859-cli-rocm-b11380-ctx131072-ae4efe116570` | ON | 260.76 | 17.36 | 513.61 | 70.12% |
| `20261004-044151-232-cli-rocm-b11380-ctx131072-bd82cb13e106` | OFF | 279.38 | 17.10 | 481.78 | — |
| `20261004-045047-408-cli-rocm-b11380-ctx262144-de50abb3b3d2` | OFF | 185.67 | 12.46 | 1415.41 | — |
| `20261004-051518-259-cli-rocm-b11380-ctx262144-6465efa5852c` | ON | 173.92 | 10.94 | 1513.90 | 65.39% |
| `20261004-054130-943-cli-rocm-b11380-ctx262144-6465efa5852c` | ON | 173.70 | 10.97 | 1515.70 | 65.76% |
| `20261004-060747-169-cli-rocm-b11380-ctx262144-de50abb3b3d2` | OFF | 185.77 | 12.35 | 1415.01 | — |
