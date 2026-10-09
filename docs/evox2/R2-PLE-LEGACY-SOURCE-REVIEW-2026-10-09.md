# r2 legacy PLE code review — deferred, watch the source fork (2026-10-09)

## Decision / when to reopen

**NO ADDITIONAL r2 PLE PORT PLANNED.** This is a **source-only investigation**, not a new optimization and not a performance validation on r5. Keep the current r5 minimal COMMON-001 split-PLE support and prioritize its Windows Vulkan/ROCm correctness/performance gate, then **branch housekeeping**, then **VULKAN-002**. Do not routinely repeat this r2 source review.

Reopen **only if [LaurentZuijdwijk/llama.cpp](https://github.com/LaurentZuijdwijk/llama.cpp) changes in a PLE-related way** (new relevant commits, a relevant release, or new demonstrated performance/Windows support) **or the user's requirements change** (e.g. a low-VRAM out-of-core PLE experiment). Before reopening, compare the **new fork revision** against the pinned donor revision and against current r5/upstream; identify a concrete, reproducible gap. A generic llama.cpp upstream update alone is not a mandate to re-port this legacy code. No recurring monitoring/notification task is being created by this note.

## Inspected revisions and code

| Reference | Identity | Scope |
|---|---|---|
| Legacy r2 in this repository | `main` at inspection, `23c316fb5af67da74e614af4a7453fba9ae46189` | Historical r2 tree; `main` is scheduled to be reorganized separately, so **use the SHA or future r2 branch**, not a permanent `main` link, for reproducibility |
| Original specialized fork donor | [LaurentZuijdwijk/llama.cpp at `5e085d123eead2e89b5c19f824fccb05727da6a2`](https://github.com/LaurentZuijdwijk/llama.cpp/tree/5e085d123eead2e89b5c19f824fccb05727da6a2) | r1/r2 source fork baseline; the reviewed PLE disk code is present at this revision |
| Earliest split PLE reference | [`bf9e0a2ace3b86f77950e5516f351110baa37f5d`](https://github.com/LaurentZuijdwijk/llama.cpp/commit/bf9e0a2ace3b86f77950e5516f351110baa37f5d) | Split the n-gram table into head tensors |
| Current r5 implementation | [r5 COMMON-001 implementation](R5-COMMON001-IMPLEMENTATION-2026-10-09.md) | Four-file compatibility delta against pinned r5 clean; GPU runtime gate **not yet verified** at this review |

Source files: legacy [qwen4exp.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/23c316fb5af67da74e614af4a7453fba9ae46189/src/models/qwen4exp.cpp), [llama-ple-disk.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/23c316fb5af67da74e614af4a7453fba9ae46189/src/llama-ple-disk.cpp), [llama-ple-disk.h](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/23c316fb5af67da74e614af4a7453fba9ae46189/src/llama-ple-disk.h), [GGUF converter](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/23c316fb5af67da74e614af4a7453fba9ae46189/gguf-py/gguf/scripts/gguf_split_ple_heads.py), r2 [README](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/23c316fb5af67da74e614af4a7453fba9ae46189/docs/evox2/r2/README-ja.md).

## Per-feature inspection

| Legacy source feature | Implementation/meaning | r5 decision |
|---|---|---|
| Lossless joined-to-16-head GGUF conversion | `gguf_split_ple_heads.py` copies per-head quantized row ranges **without dequantizing/requantizing**. Bypasses the single large joined Vulkan buffer placement limit. Also implements reverse join. | Already represented by the user's existing PLE16 model and r5 COMMON-001 compatibility code. **Do not add a conversion or reformat step.** |
| Split-head GGUF tensor support | Legacy `ple_ngram_embd.N.weight` with one GET_ROWS/head and concatenation. | **Implemented in r5 COMMON-001**. No second legacy port. Confirm Vulkan/ROCm load and placements before marking validated. |
| Per-head index extraction in r2 | r2 computes a token-major index array, then slices head-specific strided indices with `ggml_view_2d` + `ggml_cont` + reshape. | r4/r5 builds **head-major local indices** for split mode and uses a contiguous `ggml_view_1d`. Fewer graph steps by inspection; **not benchmarked as a measured speedup**. No reason to restore the r2 approach. |
| `--ngram-on-disk` out-of-core joined table | Leaves the large joined n-gram weight on disk instead of mapping/loading it; gathers only required rows into host float data for each ubatch. | **Do not port.** Original r2/source-fork code explicitly throws `llama_ple_disk: not supported on Windows` on construction (also aborts from Windows gather); implementation is POSIX `pread`/`O_DIRECT`-dependent. A real Windows port would be new I/O work, not a small cherry-pick. |
| PLE-only I/O thread pool and raw-row cache | Sort/deduplicate requested IDs, optional direct-mapped cache of rows (default 256 MiB), parallel reads (default 64 I/O threads), dequantization, logged cache hit/read stats; lives inside `llama_ple_disk`. | **Deferred** together with out-of-core mode; the cache cannot simply accelerate resident split PLE GPU GET_ROWS. Potential value is memory reduction / out-of-core behavior, not demonstrated Evo-X2 PP/TG gain. |
| `--model-ple` separate GGUF sidecar | Points to an independent **joined-layout** PLE GGUF, for swapping PLE table source/precision without rewriting the main model; implies disk-backed PLE reading. | **Deferred**; Linux/POSIX disk path in donor, not split-PLE16 sidecar support and not the current Windows workload. Reconsider only for a specific low-memory or PLE-precision experiment. |
| `PLE_DEBUG_DUMP` diagnostic | Env-controlled host-side token/history dump from r2 `qwen4exp.cpp`. | Debug only, not an optimization. No r5 port while current hash/KV behavior is correct. |

### Important distinctions

1. PLE16's practical benefit on 96 GB UMA was **model loadability and a different weight placement**, not a proven standalone PP/TG speedup. In r4 post-COMMON-001 64k matched-model pairs: Vulkan Original **267.51**, PLE16 **268.79** PP tok/s; ROCm Original **370.32**, PLE16 **370.37**. Vulkan in the r4 comparison was also using a separate MoE selector change, so do not attribute a baseline-to-ported increase to PLE16.
2. The r4 [VULKAN-002 results](R4-VULKAN002-VALIDATION-2026-10-04.md) demonstrate **QSA grouped-union is not PLE16-specific**: Original 64k PP 269.08→337.45; PLE16 64k PP 268.42→335.38 (same conditions per model). The long-context 128k/256k ABBA was on PLE16 only, hence r5 should align that model after COMMON-001 passes.
3. The legacy specialized fork contains **no additional PLE16-exclusive GPU kernel/PP acceleration that this inspection justifies porting**. The potentially useful uncovered features are distinct *out-of-core* and *sidecar* experiments, not a dependency of VULKAN-002.
4. Do not infer that the fork's disk path works on Windows from the existence of CLI flags; Windows support is explicitly absent in the inspected implementation. No Windows timing or memory-savings measurement for this code is claimed.

## Future review gate (only if source fork changes materially)

- Compare current LaurentZuijdwijk fork commit/release to donor SHA `5e085d123eead2e89b5c19f824fccb05727da6a2`; inspect changes in `src/models/qwen4exp.cpp`, `src/llama-ple-disk.*`, GGUF conversion scripts, any relevant PLE GPU kernels or new Windows-specific implementation.
- Compare against the **then-current r5/upstream** features: per-head weights, loading, lazy paging/prefetch, sidecar, OS support and hardware limits.
- Request/measure a specific effect (peak committed/dedicated GPU memory, disk reads, PP/TG for 64k→256k, output agreement) on Evo-X2 before considering a port.
- Keep the **VULKAN-002** port/ABBA independent; do not mix any future fork-derived PLE optimization into that measurement.

## Immediate execution order (agreed 2026-10-09)

1. **Finish r5 COMMON-001** Windows Vulkan/ROCm build + Original/PLE16 allocation, short-run and 64k validation. Source change `b45025848b97fc8fd3efa7333305567bc897f61f`; acceptance results not yet supplied.
2. **Reorganize branches after COMMON-001 validation**, separately and with stable historical SHA references: preserve current r2 `main` under a clear r2 legacy branch, expose frozen r4 as new `main`, retain existing r4 and active r5 branch. Review link/default-branch impact and avoid losing r2 references. **Not performed by this memo.**
3. **Investigate/port VULKAN-002** and compare matched PLE16 QSA union OFF/ON at 64k/128k/256k with unchanged clean/reference binaries.
4. Further r2/fork PLE research: **not scheduled**. Wait for a relevant source-fork change or a new explicit user need.

This document is a decision record; it makes no changes to inference, build or benchmark tooling.
