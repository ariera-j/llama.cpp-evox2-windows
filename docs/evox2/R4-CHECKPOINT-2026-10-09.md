# r4 checkpoint and r5 validation plan (2026-10-09)

This checkpoint records the confirmed r4 state and the decision to resume work
by validating a new r5 upstream refresh. It does not report completed r5 builds
or measurements.

## Source identity

| Item | Reference |
|---|---|
| Current r4 branch | `r4/upstream-refresh-20261002` |
| r4 HEAD before this documentation checkpoint | `2360a7b9825fe102d80d325753437785b9780cd6` |
| Pinned r4 upstream base | `bed0a856606ee4a24a164066f73d2379447033f5` |
| Frozen r3 comparison checkpoint | `r3/upstream-first`, `0a93fcbb8e5bcf51b331275c4f4b142d822168d6` |
| Planned r5 branch name | `r5/upstream-refresh-20261009` (candidate; not created by this checkpoint) |
| r5 upstream base | To be checked and pinned when the new branch is created |

Keep r4 and the investigation branches below available for comparison. This is
a documentation checkpoint, not a release acceptance or a new freeze tag.
Use each dated validation report for the exact source, build and runtime identity
of its measurements.

## Implemented in r4

| Item | Implementation / control | Confirmed scope |
|---|---|---|
| Vulkan MoE legacy tile selection | `c81b8bf78f47dcaefd47a2f49f72ec4035e1d874`; `GGML_VK_MOE_LEGACY_TILE_SELECTION=1` | Opt-in diagnostic/performance path; default OFF. Original-model 64k PP profile and normal ABBA completed. |
| COMMON-001 split PLE16 support | `a60a57879a9ffb4d51acd45d4de7e80d721548f9` | Joined Original and split PLE16 compatibility; Vulkan/ROCm validation through 256k. |
| VULKAN-002 QSA grouped-union | `5814fbe99e9249e8ac2c4c2e9b977c05735b0912`; `GGML_VK_QSA_UNION=1` | Default OFF. GPU OFF/ON tests and PLE16 PP/TG A/B through 256k completed; measured PP benefit with TG effectively unchanged. |
| Dense MTP sidecar pool-input guard | `e8f3be2e9ff9e3b7b3fbfe2aaa08cf4158f55bf7` | Minimal compatibility correction: skip unused pool inputs for the ratio-zero dense MTP block. |
| TG candidate 1: omit unused dense-draft indexer | `3cab9d07a78426cf4058d86be94272ccf094a014`; `LLAMA_MTP_SKIP_DENSE_INDEXER=1` | Default OFF. Native/state/rollback and real CLI gates completed; Vulkan 256k normal ABBA validates the gain. |
| TG candidate 2: skip target no-op QSA invalidation | `8f42138625294ace3be2c5839c572dd90473bd18`; `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1` | Default OFF. Native/state/rollback and real CLI gates completed; Vulkan 256k normal ABBA validates the additional gain with candidate 1 enabled. |

Evidence:
[MoE tile A/B](R4-MOE-TILE-AB-2026-10-03.md),
[COMMON-001](R4-COMMON001-VALIDATION-2026-10-03.md),
[VULKAN-002](R4-VULKAN002-VALIDATION-2026-10-04.md),
[dense-indexer ABBA](R4-COMMON002-DENSE-INDEXER-ABBA-VALIDATION-2026-10-04.md),
[no-op invalidation ABBA](R4-COMMON002-QSA-NOOP-ABBA-VALIDATION-2026-10-04.md).

### COMMON-002 / MTP interpretation

The historical r2/r3 COMMON-002 compatibility patch was **not ported wholesale**.
r4 uses upstream-native MTP, but the existing dense Unsloth sidecar required the
small pool-input guard above. Therefore “COMMON-002 unported” does not mean that
MTP runs on completely unmodified upstream code. The guard, diagnostics and the
two opt-in TG candidates are tracked under the COMMON-002 work.

Vulkan 256k normal ABBA TG improved from 15.220 to 20.185 tok/s (+32.62%) with
dense-indexer omission, then from 20.205 to 22.830 tok/s (+12.99%) with no-op
invalidation added. Each comparison preserved response/acceptance in its own
A/B setting; these are separate experiments, not a single cumulative A/B.
Neither change resolves MTP PP overhead.

ROCm native and short gates passed, but the 256k A/B responses and acceptance
differed. The ROCm long-context equivalence gate and an isolated no-op speedup
claim remain open. See
[ROCm short validation](R4-COMMON002-ROCM-SHORT-VALIDATION-2026-10-04.md) and
[ROCm 256k validation](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md).
Focused 128k confirmation also remains coverage to complete for the no-op
candidate; the Vulkan 256k result does not close every validation gate.

## Unresolved and deferred work

- **MTP fresh-prompt PP overhead / total latency:** still unresolved. TG recovery
  alone does not make fresh-prompt MTP faster overall.
- **ROCm long-context PP scaling:** PP declines from 64k toward 256k even with
  MTP OFF; this remains separate from MTP overhead.
- **MTP correctness/coverage:** preserve the ROCm long-context and focused
  confirmation limits above before broader enablement.
- **COMMON-003 / VULKAN-001 ROCmFPx:** not implemented in r4.
- **COMMON-004 / COMMON-005:** historical implementations are not automatically
  carried into r4. Upstream already supplies the major pooled-key reuse path;
  the old ROCm selected-KV decode port remains deferred.
- **COMMON-006:** an upstream-validation gate.
- **GET_ROWS 128x4:** the r4 experiment found no useful gain and remains default
  OFF; no further expansion is currently prioritized.

## Implemented on separate investigation branches

These source changes are **not integrated into the main r4 branch**.

| Branch | Preserved HEAD | Scope / remaining gate |
|---|---|---|
| `investigation/llama-bench-real-prompt-20261007` | `e3466e8fa769928140f81c93c84889860732ff82` | Real-document input, prompt slicing and explicit context-size support for llama-bench. |
| `investigation/vulkan-qsa-union-stats-20261008` | `979ef17eeff14440a58c866a966b355a1b63b17e` | Based on the real-prompt branch; includes that feature and opt-in union statistics. Stats-OFF performance regression validation remains pending. |

Pinned reports:
[real-prompt investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/e3466e8fa769928140f81c93c84889860732ff82/docs/evox2/R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md),
[union-statistics investigation](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/979ef17eeff14440a58c866a966b355a1b63b17e/docs/evox2/R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md).

The earlier Vulkan 256k llama-cli / random-token llama-bench PP gap is now
substantially explained by input-dependent QSA union behavior. Real-document
llama-bench input closely matches CLI throughput. The remaining union-OFF
real/random mechanism question is a lower-priority investigation, not a blocker
for starting r5. Details are recorded in the
[2026-10-09 research update](PERFORMANCE-RESEARCH-LOG.md).

## Decision: validate r5 from a fresh upstream base

1. Re-check latest upstream and create a separate r5 branch from an exact pinned
   upstream SHA. Preserve r4; do not replace its base or merge its full inference
   patch stack into the new baseline.
2. Carry only the minimum documentation/build/measurement tooling needed to
   identify and test the baseline. Review the two investigation branches
   separately before selectively integrating their tools; do not treat them as
   already integrated.
3. Establish joined Original-model, MTP-OFF, f16-KV Vulkan/ROCm build, load,
   short-inference and matched 64k/128k PP/TG baselines. Extend to 256k for
   long-context decisions and repeat material differences.
4. Reclassify every r4 delta against that pinned upstream: still needed,
   WATCH-UPSTREAM, or UPSTREAMED / RETIRE. Re-test MoE tile selection and MTP
   compatibility/candidates rather than automatically carrying them forward.
5. Restore the minimum COMMON-001 split PLE16 path if still required, then
   re-evaluate and port VULKAN-002 only where current upstream still benefits.
6. Add missing COMMON-003 / VULKAN-001 ROCmFPx support, then compare AgentionAI
   and Unsloth with matched speed and long-context quality conditions, MTP OFF
   first.
7. Choose subsequent optimizations from the remaining measured bottlenecks,
   including MTP PP overhead and ROCm PP scaling, under the upstream-watch policy.

The current execution order is in [ROADMAP.md](ROADMAP.md). Upstream/model/engine
research and the reasons for this order are in
[PERFORMANCE-RESEARCH-LOG.md](PERFORMANCE-RESEARCH-LOG.md). r5 validation is the
next work phase; no r5 performance or correctness result is asserted here.
