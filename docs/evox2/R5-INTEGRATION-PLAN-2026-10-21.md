# Evo-X2 r5 latest-upstream integration plan — 2026-10-21

## Status and objective

This is the **current authoritative plan for the next integrated candidate**. It supersedes dated "NEXT" instructions in older research reports for integration ordering, while preserving those reports as evidence.

The goal is not to merge investigation branches wholesale. The goal is to start from one deliberately selected current upstream commit and **semantically reapply only the still-needed, validated local functionality**, with measurement provenance kept intact.

No final latest-upstream integrated candidate, release tag or replacement binary exists yet.

> **Post-integration optimization research is tracked separately.** The 2026-10-21 point-in-time priority snapshot is [R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md). It does **not** change the candidate-construction order in this document. Use it only after the integrated candidate is frozen and re-check upstream PR/fork state at the actual start of the next optimization session.

### Point-in-time upstream watch

At the 2026-10-21 review checkpoint, upstream `ggml-org/llama.cpp` master is:

```text
493253fe5a5af7e800b3c92a2452b5684a99e961
```

which is 270 commits ahead of the pinned r5 upstream:

```text
de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b
```

This is **not yet the selected integration SHA**. Re-read upstream at the start of the integration session, review relevant Qwen4Exp/MTP/Vulkan/HIP changes, and freeze one immutable SHA before modifying source.

## Evidence added on 2026-10-20/21

### ROCmFP4 / ROCmFPx isolated port

The Windows/Vulkan isolated port validation is complete. Canonical records now preserved on r5:

- [COMMON-003A core implementation](R5-COMMON003A-ROCMFPX-CORE-IMPLEMENTATION-2026-10-20.md)
- [ROCmFPx port plan and final validation record](R5-ROCMFPX-VULKAN-PORT-PLAN-2026-10-20.md)
- [VULKAN-001A correctness implementation](R5-VULKAN001A-ROCMFPX-CORRECTNESS-IMPLEMENTATION-2026-10-20.md)
- [VULKAN-001B integer-dot implementation](R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-21.md)

Validated scope includes:

- historical ROCmFPx GGML type/core support and CPU fallback;
- Vulkan ROCmFP4/ROCmFPx correctness paths;
- q8_1 integer-dot MMVQ/MMQ and MUL_MAT_ID;
- focused widths 1,3,4,5,6,7,8: **140/140 backend tests PASS** under normal and forced-MMVQ dispatch;
- target-only real model through 32k/64k/128k/256k;
- existing Agention old `output_hc_*` MTP sidecar compatibility;
- ratio-zero dense-MTP k-pool compatibility;
- real MTP 32k/64k and DraftMax=7 verification-width-8 gate.

This establishes **port feasibility and correctness on the pinned r5 lineage**, not an automatic claim that the same source text applies cleanly to the future upstream SHA.

### DENSE / NOOP / VULKAN-002 + ROCmFPx combined rehearsal

[NOOP + ROCmFPx integration rehearsal](R5-NOOP-ROCMFPX-INTEGRATION-CHECK-2026-10-21.md) passed.

The pinned-r5 combined runtime proved coexistence of:

- VULKAN-002 grouped-union;
- MTP-DENSE;
- MTP-NOOP;
- ROCmFP4/ROCmFPx core + Vulkan paths;
- old-layout Agention ROCmFP4 MTP sidecar.

The integrated backend test remained **140/140 PASS**. Native NOOP policy/model-state/rollback gates passed. A short all-on real-model run entered the grouped-union prefill path, then correctly fell back for single-query decode; target and draft remained fully GPU-offloaded and MTP acceptance was nonzero/coherent.

Important lesson: the isolated ROCmFPx branch did **not** contain VULKAN-002. Whole-file copying from that branch would remove existing grouped-union/selected-row source. Use **semantic/hunk-level porting**, not final-file replacement.

### Stage-B + eh_proj flatten interaction rehearsal

[Stage-B + flatten source integration rehearsal](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md) also passed at source level.

Production additions are limited to:

```text
src/llama-graph.cpp
src/models/models.h
src/models/qwen4exp.cpp
```

and can coexist structurally with the already-passing VULKAN-002 + DENSE + NOOP + ROCmFPx line.

The complete all-feature combination has **not** yet been natively built/run together. Treat this as source-level feasibility, not final runtime acceptance.

The Stage-B/flatten replay also exposed a practical porting hazard: Qwen4Exp target and MTP builders contain similar `inp_pos / inp_out_ids` text. Anchor the output-id crop specifically inside `graph_mtp::graph_mtp()`; do not use a global first textual match.

## Measurement and provenance tooling — preserve as first-class integration assets

The current r5 branch already contains the validated measurement infrastructure. Do **not** overwrite it with older investigation-branch copies.

Carry forward or run externally against the new candidate as appropriate:

```text
tools/evox2/adlx-gpu-monitor/
tools/evox2/pmode/
tools/evox2/lib/Evox2.Common.psm1
tools/evox2/benchmark/Evox2.Benchmark.psm1
tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1
tools/evox2/benchmark/Measure-LlamaCli.ps1
tools/evox2/benchmark/Measure-LlamaBench.ps1
tools/evox2/benchmark/Monitor-LlamaProcess.ps1
tools/evox2/build/
```

Also preserve the real-prompt llama-bench support and the relevant opt-in analyzers/plans indexed by [R5-RESEARCH-ASSET-INVENTORY-2026-10-20.md](R5-RESEARCH-ASSET-INVENTORY-2026-10-20.md).

[ADLX/P-MODE validation](R5-ADLX-PMODE-VALIDATION-2026-10-15.md) established:

- automatic ADLX logging for llama-cli and llama-bench;
- `gpu-metrics.csv` and monitor status per run;
- authoritative P-MODE start/finish capture;
- Performance/Balanced/Quiet materially change PP;
- 2s ADLX sampling showed no material 64k PP overhead in the validation ABBA;
- ADLX power classification is a secondary consistency warning, never a replacement for the authoritative P-MODE read.

### Mandatory performance-run provenance

For any integration performance claim, record at minimum:

- candidate source SHA and executable SHA;
- backend runtime DLL manifest/digest;
- model + draft + input fingerprints;
- Windows/driver/toolchain identity;
- authoritative P-MODE start and finish; require Performance for normal comparisons;
- whether P-MODE changed during the run;
- ADLX start/exit/sample count;
- high-load GPU clock/power/temperature and consistency classification where enough samples exist;
- GPU dedicated/shared/committed memory and system committed memory;
- effective inference flags, especially QSA union, DENSE, NOOP, Stage-B, flatten, MMVQ and KV dtype.

A telemetry probe failure remains fail-open for execution but makes the run unsuitable for a strong performance attribution unless the missing condition is independently established.

## Candidate construction order

### 0. Freeze and baseline the selected upstream

1. Re-check current upstream at integration-session start.
2. Review Qwen4Exp/MTP, speculative decoding, k-pool, Vulkan, HIP, GGML type and loader changes since the r5 pin.
3. Freeze one exact upstream SHA.
4. Build **untouched upstream** Vulkan and ROCm references before local inference-source changes.
5. Use the stable r5 measurement harness externally if needed so the untouched-upstream source remains a genuine baseline.
6. Record the actual compile-time HIP/ROCm toolchain and runtime-loaded HIP/ROCm DLL paths/versions; resolve the previously suspected build-version/runtime-version mismatch instead of inferring it from labels.

### 1. Loader/model prerequisites

Port only if still missing upstream:

1. **COMMON-001** split PLE16 support.
2. **COMMON-003 / ROCmFPx core** required by the selected Agention ROCmFP4-FAST GGUF.

Run loader/type tests and short target-only smoke before backend optimizations.

### 2. ROCmFPx Vulkan support

If the intended Agention model is used on Vulkan and upstream still lacks the required paths, semantically port:

1. VULKAN-001A correctness paths;
2. VULKAN-001B integer-dot MMVQ/MMQ/MUL_MAT_ID.

Mandatory gate:

- focused five-format MUL_MAT + MUL_MAT_ID widths 1,3-8;
- normal + `GGML_VK_FORCE_MMVQ=1`;
- expected **140/140** pass before model-level acceptance.

Do not copy `ggml-vulkan.cpp` wholesale from the isolated ROCmFPx branch because that would discard unrelated newer-upstream/VULKAN-002 logic.

### 3. MTP compatibility before MTP speed patches

Test the target + matching Draft on native selected upstream first.

If still required, port only the minimal compatibility gaps:

- old `output_hc_*` final-mixer fallback for the current Agention MTP sidecar;
- ratio-zero dense-MTP unused k-pool input guard.

Verify short load/generation, full GPU placement, nonzero acceptance and DraftMax=7 wide-verify behavior before optimization claims.

### 4. VULKAN-002 grouped-union

Source-audit latest upstream first. If no equivalent path exists, port the grouped-union functionality semantically and retain it opt-in.

Gate:

- f16 K/V;
- short forced-eligibility smoke proving `qsa-union active`;
- normal threshold 64k control;
- then bounded 64k/128k performance before deciding whether 256k is necessary.

Do not infer q8_0 K/V acceleration from the f16 union path.

### 5. MTP-DENSE, then MTP-NOOP

Port independently and preserve independent switches:

1. MTP-DENSE ratio-zero indexer omission;
2. MTP-NOOP target no-change invalidation suppression.

Run native policy/state/rollback gates and one all-on short smoke combining:

- ROCmFPx target + Draft;
- VULKAN-002;
- DENSE;
- NOOP.

The pinned-r5 rehearsal already proves this combination is feasible; the new-upstream run is a regression/port gate, not first-principles research.

### 6. Stage-B, then eh_proj flatten

Port Stage-B KV-only Draft prefill behind its own opt-in control. Port flatten second, also independently disableable and scoped to Stage-B prefill.

Required sequence:

```text
C = Stage-B OFF
A = Stage-B ON, flatten OFF
B = Stage-B ON, flatten ON
```

On the new upstream candidate:

- short native C/A/B first;
- inspect graph roots / absence of Draft FA only when Stage-B applies;
- verify target/draft output and acceptance;
- bounded continuation/rollback state gate;
- 64k then 128k uninstrumented correctness/performance if short passes.

The pinned-r5 parity/rollback diagnostics are evidence, not production C++ to merge. Do not carry synthetic forced-checkpoint diagnostics into the final inference source.

### 7. Final combined Qwen3.8 regression

Only after all selected features pass individually:

- normal integrated settings at 32k/64k first;
- 128k;
- 256k once on the final candidate if memory/stability is clean;
- MTP OFF and ON representative checks;
- DraftMax=2 normal use and a bounded DraftMax=7 correctness gate;
- Vulkan and ROCm treated as separate backends with separate claims.

Do not add the independently measured percentage wins together. The combined source requires its own baseline.

### 8. Gemma 4 replacement gate

Before replacing the existing known-working b10919 Vulkan installation, test separately:

- Gemma 4 31B IT QAT q4_0;
- Gemma 4 26B A4B IT QAT UD-Q4_K_XL.

Use the existing b10919 setup as rollback-safe baseline. Validate load/template, short text, representative longer context, stability/memory and matched PP/TG. Replace per model only when acceptable; a Qwen3.8 pass does not certify Gemma 4.

## Deferred / non-blocking investigations

Do not block the first integrated candidate on:

- telemetry-controlled 256k Stage-3 versus AgentionAI-fork rerun;
- 256k RGP investigation of the large Stage-3/Agention PP + memory-layout difference;
- COMMON-005 deep-context selected-K/V rework;
- new s1-derived CONCAT/MoE experiments;
- Strata comparison;
- additional arbitrary MTP PP diagnostics already superseded by Stage-B/flatten evidence.

These may resume after the integrated candidate is frozen.

## Stop criteria

Stop feature promotion and isolate the failing layer if any of the following occurs:

- build or shader generation failure;
- unsupported ROCmFPx type/pipeline;
- CPU fallback where full GPU placement is expected;
- backend numerical failure;
- output corruption or repeatable degeneration;
- MTP acceptance/state/rollback inconsistency;
- grouped-union / Stage-B path does not actually activate when its gate requires it;
- P-MODE changes or strong ADLX/P-MODE inconsistency during a performance run;
- unexpected ROCm compile/runtime library mismatch;
- a claimed speed patch loses its effect under clean same-binary measurements.

A failed feature can be deferred without invalidating the entire integration candidate if the resulting scope is explicitly documented.

## Release rule

Do not call the candidate integrated/stable merely because it builds.

Only update [INTEGRATED-RELEASES.md](INTEGRATED-RELEASES.md) and create a read-only release tag after documenting:

- selected upstream SHA;
- final downstream commit;
- included/upstream-covered/deferred/excluded patch matrix;
- exact tool/driver/runtime identities;
- Qwen3.8 validated models/backends/contexts;
- MTP compatibility and selected optimization flags;
- Gemma 4 results or explicit per-model fallback decision;
- known untested combinations.

Until then, retain `r5/upstream-refresh-20261009` as the pinned research/control lineage and keep the integration candidate clearly marked incomplete.
