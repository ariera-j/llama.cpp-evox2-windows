# Research branch document import — 2026-11-23

> **2026-11-23 追補（このページは当初インポートの履歴）:** その後の同名ファイルの差分精査・新しい実験状態の読み替えは[DOCUMENTATION-RECONCILIATION-2026-11-23.md](DOCUMENTATION-RECONCILIATION-2026-11-23.md)に記録。11/22 Gemma4の安全判断3件、11/23 Codex RUNBOOKの追記はmainへ統合済み。README/ROADMAP/PATCHES等の最新ステータスを更新し、過去のr2〜r6差分は元ブランチの時点付き記録として保存する。下記「未統合」一覧は**初回インポート時点**のものであり、11/23の最終判断ではない。

This inventory records a **documents-only** import into `main` from the research branches listed below. Original source code, build scripts, and previously existing documentation remain unchanged.

## Imported files

- 51 files new to main (.md / .txt), preserved with original blob hashes
- Scope: docs/evox2 and Markdown/TXT files in tools/evox2
- Root README.md and AGENTS.md are unchanged
- Existing research docs with divergent branch edits were **not** overwritten; do not treat them as synchronized until content review.

### Source mapping
- `docs/evox2/GEMMA4-GLOBALFA-RGP-GATE-20261121.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/GEMMA4-V1-PP-RGP-20261121.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/GEMMA4-V1-VULKAN-FA31323-PORT-2026-11-21.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/GEMMA4-V1-VULKAN-TG-RGP-2026-11-16.md` — `investigation/gemma4-31b-v1-rocm-20261116`
- `docs/evox2/OPTIMIZATION-SUMMARY-ja.md` — `r2/legacy`
- `docs/evox2/R5-VULKAN001B-ROCMFPX-INTEGER-DOT-IMPLEMENTATION-2026-10-20.md` — `investigation/r5-rocmfpx-vulkan-20261020`
- `docs/evox2/R6-HIP-FA-RGP-SURVEY-PORTING-2026-11-11.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-INVESTIGATION-DOCS-IMPORT-20261115.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-LLAMA-BENCH-REAL-INPUT-CROSSCHECK-AND-ROCM-PLAN-2026-11-03.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-LLAMA-BENCH-REAL-PROMPT-GATE4PLUS-RESULTS-2026-11-03.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-LLAMA-BENCH-REAL-PROMPT-PORT-PLAN-2026-11-03.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-FA-MASK-COLUMN-STRIPE-ANALYSIS-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-FA-MASK-MIXED-RAW-CROP-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-FA-MASK-TILE-GATE2-64K-RUNBOOK-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-FA-MASK-TILE-GATE2-IMPLEMENTATION-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-FA-RGP-64K-PAIRED-CAPTURE-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-INPUT-FA-MASK-MOE-QUANT-PROFILING-DESIGN-2026-11-04.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-RGP-GATE1-4K-CAPTURE-RUNBOOK-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-RGP-MASK-EXPERIMENT-PLAN-2026-11-05.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-RGP-MASK-GATE1-IMPLEMENTATION-2026-11-05.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-RGP-MASK-RUNBOOK-DRAFT-2026-11-05.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-QSA-INDEXER-SCORE-TOPK-DIAGNOSTIC-DESIGN-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-QSA-INDEXER-SCORE-TOPK-RUNBOOK-2026-11-06.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-FA-KVMAX-DIAG-2026-11-08.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-MOE-EXPERT-ROUTING-RGP-SUMMARY-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-MOE-TOPK-MULTI-UBATCH-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-PP-FA-HOST-TRACE-GATE-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/R6-ROCM-PP64K-IQ3-IQ4-MMQ-CLI-TRACE-2026-11-10.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/README-ja.md` — `r2/legacy`
- `docs/evox2/ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/ROCM-PP-PROFILE-128K-2026-11-15.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/ROCM-PP-PROFILE-64K-2026-11-15.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/V1-STRATA-DENSE-GEMM-DISPATCH-RUNBOOK-20261115.md` — `investigation/v1-strata-dense-gemm-20261115`
- `docs/evox2/V1-STRATA-MOE-IQ2S-FUSION-POC-20261115.md` — `investigation/v1-strata-moe-fusion-20261115`
- `docs/evox2/V1-STRATA-MOE-PHASE0-RUNBOOK-20261115.md` — `investigation/v1-strata-moe-fusion-20261115`
- `docs/evox2/V1-STRATA-PP-RESEARCH-HANDOFF-20261115.md` — `investigation/gemma4-fa31323-globalfa-rgp-20261121`
- `docs/evox2/V1-STRATA-Q6K-DENSE-BLAS-MMQ-EXPERIMENT-20261115.md` — `investigation/v1-strata-dense-gemm-20261115`
- `docs/evox2/V1-STRATA-VS-LLAMA-DENSE-GEMM-SOURCE-COMPARISON-20261115.md` — `investigation/v1-strata-dense-gemm-20261115`
- `docs/evox2/backport-r1/UPSTREAM-AUDIT-ja.md` — `r2/legacy`
- `docs/evox2/backport-r1/verification.txt` — `r2/legacy`
- `docs/evox2/r2/README-ja.md` — `r2/legacy`
- `docs/evox2/r2/verification.txt` — `r2/legacy`
- `tools/evox2/experiments/qsa/README.md` — `r3/upstream-first`

## Existing paths with divergent branch versions

Main content is retained because branch changes may be earlier snapshots or different experiment states. Reconcile semantically, keeping dated history and avoiding stale status regressions.
- `README.md`
- `docs/evox2/BASELINE.md`
- `docs/evox2/BENCHMARKING.md`
- `docs/evox2/BUILD-ROCM-WINDOWS.md`
- `docs/evox2/BUILD-VULKAN-WINDOWS.md`
- `docs/evox2/INTEGRATED-RELEASES.md`
- `docs/evox2/PATCHES.md`
- `docs/evox2/PERFORMANCE-RESEARCH-LOG.md`
- `docs/evox2/R5-COMMON001-IMPLEMENTATION-2026-10-09.md`
- `docs/evox2/R5-REFRESH-2026-10-09.md`
- `docs/evox2/R6-INTEGRATED-PUBLIC-CHECKPOINT-2026-10-29.md`
- `docs/evox2/R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md`
- `docs/evox2/R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md`
- `docs/evox2/R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md`
- `docs/evox2/README.md`
- `docs/evox2/ROADMAP.md`
- `tools/evox2/README.md`
- `tools/evox2/build/README.md`
- `tools/evox2/model/README.md`

## Notes

- The import uses Git blob identities from existing branches and does not alter experimental source trees.
- New operating procedures should be authored under `docs/evox2/automation/` after checking the imported history.
- Git clients on EVO-X2 must fetch the updated `main` explicitly; the existing Codex smoke-test branch does not automatically follow it.


## 2026-11-23 後続の補足

初回の51件(.md/.txt)に加え、`r2/legacy` にのみ存在する `docs/evox2/backport-r1/manifest.json` を歴史的な来歴資料としてmainに取り込んだ。同名文書の差分精査後の結果・古い「未実施」の読み替えは [DOCUMENTATION-RECONCILIATION-2026-11-23.md](DOCUMENTATION-RECONCILIATION-2026-11-23.md) を参照。
