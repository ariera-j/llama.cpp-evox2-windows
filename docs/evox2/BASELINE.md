# Baseline index / バージョン別の基準計測

このページはバージョン横断の入口。過去の測定結果を現在のビルドの検証結果として扱わないこと。

| 対象 | 記録 |
|---|---|
| r3 | [R3-BASELINE.md](R3-BASELINE.md) |
| r4 / r5 | [R4-R5-BASELINE.md](R4-R5-BASELINE.md)（旧 BASELINE.md の計測履歴） |
| r5 clean | [R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md) |
| r6 clean | [R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md) |
| v1.0.0 / Strata 調査 | [V1-STRATA-PP-RESEARCH-HANDOFF-20261115.md](V1-STRATA-PP-RESEARCH-HANDOFF-20261115.md) |
| Codex / 次期 upstream | [モデル互換性・監視ゲート・移植方針 (2026-11-23)](automation/MODEL-BASELINE-AND-UPSTREAM-PORTING-20261123.md) |
| b12651 初期ビルド | [Vulkan／ROCm ベースライン](automation/UPSTREAM-B12651-20261124.md) |
| b12651 PP/TG | [32k 試験](automation/UPSTREAM-B12651-32K-PP-TG-TRIAL-20261124.md) · [本計測](automation/UPSTREAM-B12651-PP-TG-20261124.md) |
| b12651 Stage 1 / 2 | [COMMON-001](B12651-STAGE1-COMMON001-20261124.md) · [ROCmFP4 FAST PLE16 の Vulkan 検証](B12651-STAGE2-ROCMFP4-VULKAN-20261124.md) |
| PR #30904 移植前調査 | [IQ3_XXS の経路・テンソル調査](pr30904-preport-20261125/README.md) |
| IQ2_S Vulkan MatVec | [A1/A2 実験結果](iq2-s-vulkan-matvec-20261125/README.md) |
| b12651 系モデルロード | [既存ログ・ソース解析（作業4-1）](automation/B12651-MODEL-LOAD-INVESTIGATION-20261126.md) · [基準計測・診断設計案（作業4-2）](automation/B12651-MODEL-LOAD-BASELINE-20261126.md) · [診断実装・ビルド検証（作業4-3）](automation/B12651-MODEL-LOAD-DIAG-20261126.md) · [実モデルの診断計測（作業4-4）](automation/B12651-MODEL-LOAD-DIAG-RESULTS-20261126.md) |

共通の計測方法は [BENCHMARKING.md](BENCHMARKING.md)、文書命名規則は [DOCUMENT-NAMING.md](DOCUMENT-NAMING.md)。新しい基準計測の結果は実際に使用したソースバージョン（または upstream build 番号）を先頭につけた独立した文書として記録する。
