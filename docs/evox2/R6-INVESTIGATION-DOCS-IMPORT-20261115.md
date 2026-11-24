# Historical r6 investigation documents imported to v1.0.0 research branch (2026-11-15)

> 2026-11-24: 以下のリンク・ファイル名は main の現行名に更新した。元ブランチでのファイル名は [DOCUMENT-NAMING.md](DOCUMENT-NAMING.md) の旧名欄を参照。

**Documentation only.** The source of this branch's inference code remains clean upstream v1.0.0 `b1b770d90d94cad9e9ea5b993bdbc383a522fb28`. These files describe experiments on separate r6 investigation/test branches, with different executables and patch sets. Their commands and recorded run results **must not** be treated as validated for the v1.0.0 branch.

## Import scope and provenance

- 39 **new** Markdown files below `docs/evox2/` from eleven r6-related feature, research and investigation branches, compared with the existing v1 research branch.
- Two **new** Markdown usage notes below `tools/evox2/benchmark/`: `BACKGROUND-ACTIVITY-MONITORING.md`, `LLAMA-BENCH-B11908-ARGUMENT-COMPATIBILITY.md`.
- All imported file **blobs are identical to GitHub source branch objects** (copy by Git blob SHA, no rewriting of the historical contents). Paths and original filenames retained.
- Existing documents `PATCHES.md`, `ROADMAP.md`, `PERFORMANCE-RESEARCH-LOG.md`, etc. are intentionally **not overwritten** by conflicting branch versions. No new experimental source files, tools/scripts, model files or compiled artifacts are included.
- Fork-specific `README.en.md` was intentionally excluded: it describes the downstream project rather than r6 experiment results, and copying it onto the clean upstream base could misrepresent current capabilities.

## Files by topic

### COMMON-005 and llama-bench
- [`R6-COMMON005-IMPLEMENTATION-2026-11-02.md`](R6-COMMON005-IMPLEMENTATION-2026-11-02.md)
- [`R6-COMMON005-MH128K-QUALITY-PLAN-2026-11-03.md`](R6-COMMON005-MH128K-QUALITY-PLAN-2026-11-03.md)
- [`R6-COMMON005-RGP-2026-11-02.md`](R6-COMMON005-RGP-2026-11-02.md)
- [`R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md`](R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md)
- [`R6-LLAMA-BENCH-REAL-INPUT-CROSSCHECK-AND-ROCM-PLAN-2026-11-03.md`](R6-LLAMA-BENCH-REAL-INPUT-CROSSCHECK-AND-ROCM-PLAN-2026-11-03.md)
- [`R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md`](R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md)
- [`R6-LLAMA-BENCH-REAL-PROMPT-GATE4PLUS-RESULTS-2026-11-03.md`](R6-LLAMA-BENCH-REAL-PROMPT-GATE4PLUS-RESULTS-2026-11-03.md)
- [`R6-LLAMA-BENCH-REAL-PROMPT-PORT-PLAN-2026-11-03.md`](R6-LLAMA-BENCH-REAL-PROMPT-PORT-PLAN-2026-11-03.md)
- [`R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md`](R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md)
- [`R6-ROCM-256K-MTP-OFF-ON-COMMON005-2026-10-30.md`](R6-ROCM-256K-MTP-OFF-ON-COMMON005-2026-10-30.md)

### Vulkan QSA mask and RGP
- [`R6-PP-FA-MASK-COLUMN-STRIPE-ANALYSIS-2026-11-06.md`](R6-PP-FA-MASK-COLUMN-STRIPE-ANALYSIS-2026-11-06.md)
- [`R6-PP-FA-MASK-MIXED-RAW-CROP-2026-11-06.md`](R6-PP-FA-MASK-MIXED-RAW-CROP-2026-11-06.md)
- [`R6-PP-FA-MASK-TILE-GATE2-64K-RUNBOOK-2026-11-06.md`](R6-PP-FA-MASK-TILE-GATE2-64K-RUNBOOK-2026-11-06.md)
- [`R6-PP-FA-MASK-TILE-GATE2-IMPLEMENTATION-2026-11-06.md`](R6-PP-FA-MASK-TILE-GATE2-IMPLEMENTATION-2026-11-06.md)
- [`R6-PP-INPUT-FA-MASK-MOE-QUANT-PROFILING-DESIGN-2026-11-04.md`](R6-PP-INPUT-FA-MASK-MOE-QUANT-PROFILING-DESIGN-2026-11-04.md)
- [`R6-PP-RGP-GATE1-4K-CAPTURE-RUNBOOK-2026-11-06.md`](R6-PP-RGP-GATE1-4K-CAPTURE-RUNBOOK-2026-11-06.md)
- [`R6-PP-RGP-MASK-EXPERIMENT-PLAN-2026-11-05.md`](R6-PP-RGP-MASK-EXPERIMENT-PLAN-2026-11-05.md)
- [`R6-PP-RGP-MASK-GATE1-IMPLEMENTATION-2026-11-05.md`](R6-PP-RGP-MASK-GATE1-IMPLEMENTATION-2026-11-05.md)
- [`R6-PP-RGP-MASK-RUNBOOK-DRAFT-2026-11-05.md`](R6-PP-RGP-MASK-RUNBOOK-DRAFT-2026-11-05.md)
- [`R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md`](R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md)
- [`R6-QSA-INDEXER-SCORE-TOPK-DIAGNOSTIC-DESIGN-2026-11-06.md`](R6-QSA-INDEXER-SCORE-TOPK-DIAGNOSTIC-DESIGN-2026-11-06.md)
- [`R6-QSA-INDEXER-SCORE-TOPK-RUNBOOK-2026-11-06.md`](R6-QSA-INDEXER-SCORE-TOPK-RUNBOOK-2026-11-06.md)

### HIP FA and MMQ
- [`R6-HIP-FA-RGP-SURVEY-PORTING-2026-11-11.md`](R6-HIP-FA-RGP-SURVEY-PORTING-2026-11-11.md)
- [`R6-ROCM-FA-KVMAX-DIAG-2026-11-08.md`](R6-ROCM-FA-KVMAX-DIAG-2026-11-08.md)
- [`R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md`](R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md)
- [`R6-ROCM-PP-FA-HOST-TRACE-GATE-2026-11-07.md`](R6-ROCM-PP-FA-HOST-TRACE-GATE-2026-11-07.md)
- [`R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md`](R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md)
- [`R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md`](R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md)
- [`R6-ROCM-PP64K-IQ3-IQ4-MMQ-CLI-TRACE-2026-11-10.md`](R6-ROCM-PP64K-IQ3-IQ4-MMQ-CLI-TRACE-2026-11-10.md)

### MoE expert routing / RGP
- [`R6-ROCM-MOE-EXPERT-ROUTING-RGP-SUMMARY-2026-11-07.md`](R6-ROCM-MOE-EXPERT-ROUTING-RGP-SUMMARY-2026-11-07.md)
- [`R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md`](R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md)
- [`R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md`](R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md)
- [`R6-ROCM-MOE-TOPK-MULTI-UBATCH-2026-11-07.md`](R6-ROCM-MOE-TOPK-MULTI-UBATCH-2026-11-07.md)

### PP GPU timing
- [`R6-ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md`](R6-ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md)
- [`R6-ROCM-PP-PROFILE-128K-2026-11-15.md`](R6-ROCM-PP-PROFILE-128K-2026-11-15.md)
- [`R6-ROCM-PP-PROFILE-64K-2026-11-15.md`](R6-ROCM-PP-PROFILE-64K-2026-11-15.md)

### Other
- [`R6-S9-GATE5-ROCM-ROUTER-RESULTS-2026-10-29.md`](R6-S9-GATE5-ROCM-ROUTER-RESULTS-2026-10-29.md)
- [`R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md`](R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md)

### Further r6 research docs
- [`R6-PP-FA-RGP-64K-PAIRED-CAPTURE-2026-11-07.md`](R6-PP-FA-RGP-64K-PAIRED-CAPTURE-2026-11-07.md)

### Tool documentation

- [`BACKGROUND-ACTIVITY-MONITORING.md`](../../tools/evox2/benchmark/BACKGROUND-ACTIVITY-MONITORING.md)
- [`LLAMA-BENCH-B11908-ARGUMENT-COMPATIBILITY.md`](../../tools/evox2/benchmark/LLAMA-BENCH-B11908-ARGUMENT-COMPATIBILITY.md)

## Selected versions when a filename differed across branches

- `R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md`: preserve the later, more complete document from `investigation/r6-rocm-fa-kvmax-diag-20261108`; other research branches may contain shorter historical variants.
- `R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md`: preserve the later, more complete document from `investigation/r6-rocm-fa-kvmax-diag-20261108`; other research branches may contain shorter historical variants.
- `R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md`: preserve the later, more complete document from `investigation/r6-rocm-fa-kvmax-diag-20261108`; other research branches may contain shorter historical variants.
- `R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md`: preserve the later, more complete document from `investigation/r6-rocm-fa-kvmax-diag-20261108`; other research branches may contain shorter historical variants.

**Important:** Original documents may link to r6-only test scripts, `.psd1` plans, RGP captures and other data **not included** in this documentation-only import. They remain historical pointers; check that any referenced tool is actually present before trying to run a command.

## Local setup and later steps

At UMA 64 GiB, test the **Original 3-shard IQ3** on the clean v1.0.0 code; do not import PLE16/COMMON-001 or COMMON-005 yet. The user intends to copy only their ignored `local.psd1` configuration and the local `evox2-adlx-gpu-monitor.exe` binary from their r6 working environment. Neither file belongs in Git. After moving to UMA 96 GiB, review the PLE16 loader port as a separate change.

Original project source references: r6 combined `r6/combined-20261028`; follow-up `feature/r6-llama-bench-real-prompt-20261103`; `investigation/r6-pp-fa-mask-rgp-20261105`; `investigation/r6-rocm-fa-kvmax-diag-20261108`; `investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110`; and `r6/rocm-pp-timing-20261115`.
