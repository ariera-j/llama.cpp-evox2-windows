# r5 MTP-NOOP-001: isolated target QSA no-op invalidation port plan — 2026-10-12

**Status (2026-10-12): source candidate and test harness implemented on this branch; Windows Vulkan/ROCm build, native correctness, and ABBA throughput gates are NOT YET RUN.** See [implementation handoff](R5-MTP-NOOP-IMPLEMENTATION-2026-10-12.md). The original planning criteria below remain the acceptance gates; none is implicitly waived. Keep `r5/upstream-refresh-20261009` untouched. Never silently refresh the pinned upstream or combine another optimization.

## 1. Source and branch identity

| Item | Exact reference / disposition |
| --- | --- |
| Repository | `ariera-j/llama.cpp-evox2-windows` |
| Proven DENSE-only parent | `investigation/r5-mtp-dense-indexer-20261011` @ `0dc8672d8b9b8c81e167bc566a9d80aadfb90307` |
| New isolated branch | `investigation/r5-mtp-noop-20261012`, created **directly from** `0dc8672d` |
| Stable branch (do not alter) | `r5/upstream-refresh-20261009` @ `7fefdf6149287f6adfc85efd85133c0f51fbba04` at review time |
| Divergence base | `4cc8050c929f47abf642d7bb1c413b4b18f1dd56` |
| Stable-only commits | `48d570cc571303b691962aa3bfd731c4fe7b2aac`, `7fefdf6149287f6adfc85efd85133c0f51fbba04` |
| Stable-only files | **Only** `docs/evox2/PERFORMANCE-RESEARCH-LOG.md` (+115 / -0); no code/tests/scripts. Do **not** merge stable for this task |
| r4 source reference | `r4/upstream-refresh-20261002` @ `bddf73442c24545879c9acadc078ba5b2c3cb7d8` |
| r5 experiment code base | b11566; DENSE-001 validated Vulkan/ROCm at 64k, 128k, 256k; see `R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md` |
| Current upstream inspection | `ggml-org/llama.cpp` master @ `f2cc7282ce0042641df55e0e563b75e824e2b647` on 2026-10-12: its `src/llama-memory-hybrid-idx.cpp/.h` files were text-identical to this r5 parent and **did not** include NOOP-001 |

**Branch rule:** all future implementation and investigation changes belong on the new investigation branch only. Preserve both the original DENSE experiment and r5 stable, including their benchmarks/build identities. Do not cherry-pick the newer stable-only documentation merely as part of this feature port; refer to it by link if needed.

## 2. Why NOOP-001 still applies

Pinned r5 and inspected upstream still implement `llama_memory_hybrid_idx::seq_rm` as: recurrent removal first (abort on refusal); if an indexer exists, compute stale position, call `mem_idx->seq_rm`, **always** `mem_idx_stale_set(seq_id, stale)`; then remove from attention and return its result. A full-accept MTP target trim may not delete any indexer cells, yet the next target QSA layout call rebuilds because of this new stale marker. The optimization is to avoid **only that unnecessary new invalidation** when a verified single-target no-op has not changed membership.

The r4 opt-in proof used `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` with `LLAMA_MTP_SKIP_DENSE_INDEXER=1` fixed. r4 Vulkan 256k same-binary normal ABBA: TG **20.205 -> 22.830 tok/s (+12.99%)**, identical response and 293/436 aggregate acceptance; wall evidence showed 123 true no-op suppressions, 95 real-removal stale marks retained, full rebuilds 217 -> 95, target CPU layout 5.529702 -> 2.436146 s. These are **r4-specific**, not an r5 speed prediction. r4 ROCm 256k A/B output and acceptance differed, so long-context isolated attribution was **not** established.

DENSE-001 and NOOP-001 are separate mechanisms. DENSE drops the unused **ratio-zero MTP draft** indexer allocation, leaving recurrent/attention state intact. NOOP suppresses unnecessary stale bookkeeping on the **DEFAULT target** indexer while preserving the target indexer itself. The experiment fixes DENSE=ON and MTP=ON; NOOP is the only A/B variable.

The 2026-10-12 source audit found no upstream replacement for NOOP-001. Do not backport r4's entire hybrid-indexer file: r5 has newer k-pool, copy/keep/restore behavior.

## 3. r4 → r5 source delta and port strategy

| File/interface | r4 implementation | r5 parent | Planned delta |
| --- | --- | --- | --- |
| `src/llama-qsa-noop-policy.h` | Independent pure fail-closed policy | Missing | Add a narrowly reviewed policy helper; keep default OFF |
| `src/llama-memory-hybrid-idx.h` | Includes policy; final `target_context = false` ctor arg; private policy decision | No NOOP state / arg | Add explicit target role and private decision only |
| `src/llama-memory-hybrid-idx.cpp` ctor | Reads env once; checks actual stream count after cache allocation; emits decision only when switch set | No NOOP evaluation | Adapt only policy initialization and startup evidence |
| `src/llama-memory-hybrid-idx.cpp::seq_rm` | Records membership before/after; skips fresh stale only on actual safe no-op | Always marks stale | Retain r5 recurrent/indexer/attention order and return behavior; conditionally skip only the new stale mark |
| `src/llama-model.cpp::create_memory` | Passes real `params.ctx_type == LLAMA_CONTEXT_TYPE_DEFAULT` to hybrid-indexer ctor | DENSE-001 already controls MTP draft filter; no target flag | Pass the **actual** context role; preserve the existing DENSE block verbatim |
| `src/llama-memory-hybrid-idx.cpp` k-pool/seq_cp/seq_keep/state | r4 implementation with `kpool_layout_shared()`, `cache_safe` and different shared-cell handling | Updated r5 semantics; no `kpool_layout_shared()` | **Do not port r4 layout, sharing, seq_cp, seq_keep or state implementation**; require a safe r5-specific fallback |
| `src/llama-mtp-diag.h` | r4 detailed wall/sync event scopes | Not present on r5 parent | **Do not wholesale backport**; use narrowly scoped, opt-in mechanism proof if necessary |
| `tests/test-qsa-noop-policy.cpp` | Policy/real cell metadata tests | Missing | Port/adapt, register with CTest |
| `tests/test-qsa-noop-invalidation.cpp` | Model correctness/state/output tests; expects r4 `mtp_diag` events | Missing | Adapt to r5 API and proof mechanism; build explicitly, not auto-run by CTest because model required |
| `tests/CMakeLists.txt` | Registers policy and model executables | DENSE-001 registered; NOOP not | Add NOOP targets without replacing DENSE tests |
| `tools/evox2/tests/Test-QsaNoopInvalidation.ps1` | r4-oriented runner | Already exists but r4-specific | Adapt to r5 build keys/expected evidence; preserve artifact/exit checks |
| Benchmark modules and manifest | r4 NOOP log parser/runtime gating | r5 already contains NOOP evidence parser in `Evox2.Benchmark.psm1`, extraction/status gate in `Measure-LlamaCli.ps1`, and NOOP executable names in `Evox2.Build.psm1` | Reuse; modify only where tests reveal concrete incompatibility |
| `tools/evox2/benchmark/configs/` | r4 check/wall/ABBA matrices exist | r5 configs exist; r4 ones still present | New r5-scoped matrices; do not overwrite r4 plans |

## 4. Opt-in policy and safety invariants

**Independent switch:** `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` enables; unset, `0`, or anything other than exact `1` means OFF. Read once at the creation of each eligible hybrid-indexer memory, **not per token**. The separate `LLAMA_MTP_SKIP_DENSE_INDEXER=1` is held constant in comparative MTP tests and is not implicitly toggled by NOOP.

Allocation-time eligibility (fail closed):
1. Actual model architecture `LLM_ARCH_QWEN4EXP`.
2. Actual `params.ctx_type == LLAMA_CONTEXT_TYPE_DEFAULT` (target), **never** MTP draft. Do not infer target from model filename or presence of a draft.
3. A real indexer cache exists.
4. By-order k-pool layout with pool size exactly 4.
5. Configured `n_seq_max == 1` and actual indexer `get_n_stream() == 1`.
6. No SWA.
7. At removal, explicit, valid `seq_id == 0`, and single-target/unshared membership can be guaranteed under r5 semantics. **Inspect r5 sharing model carefully**: r4's `kpool_layout_shared()` is absent, so do not copy a call to it or invent a substitute asserting the same property. If one-sequence/stream constraints are insufficient for a particular state, refuse optimization and use original stale path.

Removal invariants:
- Invoke recurrent `seq_rm` first; if it refuses, return `false` with no indexer/attention mutation.
- Only on an eligible, requested, safe call, take `mem_idx->get_cells(seq_id).seq_pos_get(seq_id).size()` before and after the **unchanged** indexer removal.
- Membership must not change; counts can be accepted as evidence of an unchanged set **only because the operation is a removal** within an isolated single sequence. Explicitly review this assumption against r5's `other`/sharing, stream and ownership paths; otherwise fail closed.
- If counts match in a safe call, suppress the **new** stale mark. Never clear or overwrite a previously pending `mem_idx_stale[seq_id]`.
- If a real suffix was removed, counts increased unexpectedly, the call is invalid/all-sequence/shared/unsupported, or the decision is OFF, keep r5's original invalidation behavior.
- Keep attention `seq_rm` and its return value exactly as before. Do not change state serialization, GPU pooled-key invalidation, kernels, QSA prefill union, MTP draft internals, or layout-rebuild algorithm.

**Startup evidence** for explicitly set switch, target and draft as applicable:
```text
QSA no-op invalidation: requested=1 eligible=1 enabled=1 target=1 kpool=4 streams=1 seq_max=1 reason=target_single_sequence
```
When candidate is OFF but eligible, expect `requested=0 eligible=1 enabled=0 target=1 ... reason=disabled`. The draft should be `target=0 eligible=0 enabled=0` (or, with DENSE indexer omitted, indexer-absent evidence consistent with policy ordering). Select target=1 evidence only; missing, duplicate, malformed or mismatched target evidence is a **failed candidate gate**. MTP OFF may still have an eligible target; don't mistake that for draft/NOOP evidence.

**Behavioral proof** must also show an actual skipped no-op and an actual preserved real-removal stale mark; startup eligibility alone is not enough. Plan a small opt-in, off-by-default mechanism trace or equivalent native-test inspection if the r4 wall diagnostics cannot be used. This diagnostic may collect count/stale snapshots only in a dedicated proof run; normal ABBA diagnostics must be OFF. Avoid introducing a broad logging framework or changing benchmark timing scopes just to port this optimization.

## 5. Implementation boundaries and commit plan (after approval)

1. Reconfirm the new branch head and keep base SHA `0dc8672d` recorded. Confirm no unexpected source changes before patching.
2. Add policy header and lightweight native policy test; ensure exact-switch and all ineligibility cases pass.
3. Add target-context plumbing and construction-time policy/evidence without disturbing existing `LLAMA_MTP_SKIP_DENSE_INDEXER` decision or the null-indexer hybrid behavior.
4. Implement the minimal `seq_rm` conditional and any narrow r5-specific safety guard. Do not copy r4 `kpool_layout_update`, `kpool_layout_shared`, `seq_cp`, `seq_keep`, state code, or r4 diagnostics wholesale.
5. Adapt model/state test and a narrowly isolated suppression proof, register test targets, update only r5-scoped scripts/configs. Keep tests non-destructive and build outputs separate from proven DENSE-only binaries.
6. Review diff carefully: NOOP OFF must exactly preserve the prior control flow and output behavior (except explicitly requested startup evidence). No r5 stable change, unrelated format/ROCm/HIP/Vulkan kernel change, upstream refresh, or combined release decision.
7. Write implementation/validation observations to a separate dated report and record precise source SHA + compiler/backend/runtime/model/input identities for reproducibility. Implementation is **not** started by this planning commit.

## 6. Vulkan-first verification gates

**A — source/policy and build**: Compile/rerun DENSE native policy tests; run new NOOP policy tests including `null/0/1/true/01`, target vs MTP, architecture, missing indexer, pool mode/size, n_seq_max/streams/SWA, valid seq0, invalid/all-sequence and shared/unsafe fallbacks; confirm OFF default. Reconfigure/build into **new separate** r5 Vulkan build directory. Verify build manifest, executable/DLL digests and version rather than trusting prior binaries. Do not accept `BuildOnly` if it did not actually rebuild changed targets.

**B — native target correctness**: Using the same PLE16 main model as r5 DENSE and two separately initialized target contexts (NOOP=0/1), compare finite logits and NextN hidden vectors with matched batch splits; require NMSE <= 1e-5 and no missing outputs. Exercise kpool boundaries, accepted=0/1/2 rollback, a true no-op, real trim, pending stale + no-op, full and PARTIAL_ONLY state save/load, malformed restore + defensive clear, repeated no-op, empty/offset/gapped/drop/reuse, and multi-sequence or shared-prefix **ineligible** fallback. Preserve the recurrent refusal gate with `n_rs_seq=0`. Adapt the r4 test's reliance on `mtp_diag` rather than silently dropping its suppression proof.

**C — Vulkan allocation/short real CLI**: MTP ON and DENSE=1 always for target A/B; NOOP=0/1. Confirm explicit target=1 decision, DENSE omitted=1 at draft layer48/ratio0, no target-indexer omission, exit0, verified runtime identity, equal output/acceptance/rollback and actual avoided no-op invalidations without hiding real removals. Optionally one MTP-OFF target sanity arm tests independence; do not count it in MTP ON A/B.

**D — Vulkan long normal ABBA (one variable)**: First 128k (126,253 input tokens), then 64k (61,789), then 256k (255,181), provided prior gates pass. Four conditions A1/B1/B2/A2, same exact new Vulkan binary and runtime, identical input/model/config/output count; NOOP=0/1/1/0, **MTP ON and DENSE=1 for all four**. Fixed defaults aligned to the r5 DENSE experiment: Unsloth PLE16 main + Unsloth Q8_0 MTP draft, `-n 512 --temp 0 --seed 1234 --ignore-eos`, DraftMax2/PMin0, target and draft f16 KV, `-b 2048 -ub 1024 -t 4 -tb 4 -ngl 999 -ncmoe 0`, `--ctx-checkpoints 0t`, no prompt cache, Vulkan union explicitly ON with min KV32768; diagnostics OFF and inherited experimental variables cleared. Validate each run's conditions/evidence, exit status, runtime digest, text hash, acceptance, TG and PP. This is a **same-binary NOOP comparison**, not a comparison against old DENSE-only or r4 binaries.

Existing DENSE-only ON TGs are **reference numbers, not NOOP controls from the new binary**: Vulkan 64k 31.270 / 128k 27.055 / 256k 21.100 tok/s. The paired A arms from the new NOOP build are the actual controls. No automatic target percentage is assumed from r4.

**Go/no-go:** No long timing claim before native/state proof and short real output gate. If ON changes output or acceptance on Vulkan, stop long measurements and debug correctness. If evidence is ineligible/missing, do not label the run a passed feature comparison. If 128k improvement is absent, inspect actual suppressions and confounding before committing to 256k runtime.

## 7. ROCm follow-up: separate nondeterminism from patch behavior

After Vulkan correctness and performance gates, build **separately** for r5 Windows ROCm and run equivalent policy/model/state and short CLI checks, then same-binary ABBA 128k → 64k/256k only when justified. Do not simultaneously run Vulkan and ROCm long GPU inference.

In the completed DENSE-only ROCm experiment, temp0 generated output/acceptance **differed even between identical-setting repeats**. Therefore use OFF/OFF and ON/ON repeat variability, numerical/state tests and mechanism counters to distinguish intrinsic nondeterminism from a feature regression. Do not present ROCm A/B text equality as established, do not ascribe any output mismatch specifically to NOOP without controls, and do not infer strict isolated throughput causality if sequence length, acceptance or GPU state materially differs. Record unresolved equivalence explicitly and defer ROCm promotion if needed.

Existing DENSE-only ON TG references: ROCm 64k 27.835 / 128k 21.195 / 256k 13.780 tok/s. New paired ROCm A runs remain the comparison controls.

## 8. Reporting and stopping rules

- Separate **policy correctness**, **state/rollback numerical equivalence**, **mechanism activation/suppression**, **output and acceptance**, **same-binary TG speed**, **PP/fresh-prompt total latency**, and **release integration**. Passing one does not prove the rest.
- Archive all ABBA `conditions.json`, `result.json`, stdout/stderr, resources, versions, executable/runtime digests, input hashes and full result tables. Verify that *only* the NOOP switch changes between A/B.
- Document whether successful removal suppression eliminates target layout rebuilds under r5, including at least one real suffix removal left intact. Do not conflate stale-layout CPU saving with GPU pooled-key cache behavior.
- Keep NOOP default OFF until at least the specified tests complete. No patch integration or stable merge is authorized by this plan.
- After the NOOP-specific experiment reaches a stopping point, consider MTP ON PP/fresh-prompt overhead and ROCm determinism as **separate** workstreams per `ROADMAP.md`.

## Source links

- [r5 ROADMAP](ROADMAP.md)
- [r5 DENSE-001 verification](R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md)
- [r4 NOOP implementation plan](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-PLAN-2026-10-04.md)
- [r4 NOOP implementation](R4-COMMON002-QSA-NOOP-IMPLEMENTATION-2026-10-04.md)
- [r4 Vulkan NOOP ABBA result](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md)
- [r4 ROCm 256k caveats](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md)
- [r5 patch inventory](PATCHES.md)
