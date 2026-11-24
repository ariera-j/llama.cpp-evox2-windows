# 文書の命名規則・旧名対応表

2026-11-24 / main の docs/evox2 を対象とする。

## 命名規則

- 特定のソース世代に依存する実装・検証・計測・調査・計画は `R2-`、`R3-`、`R4-`、`R5-`、`R6-`、`V1-` のように、実際のベースを先頭に置く。V1 はこの時期の upstream v1.0.0 ベースを指す。複数世代の比較は `R4-R5-` 等で明示する。今後の新しい upstream ベースでは曖昧な V1 を流用せず、固定 build 番号や対応する世代名を使う。
- 新規の時点付き文書は `R6-<SUBJECT>-<YYYY-MM-DD>.md` の形式を基本とする。既存の日付表記と既に世代先頭のファイル名は不要な変更を避けるため維持する。
- README、PATCHES、ROADMAP、PERFORMANCE-RESEARCH-LOG、BUILD-*-WINDOWS、BENCHMARKING、INTEGRATION-POLICY、INTEGRATED-RELEASES、UPSTREAM-REFRESH、運用・障害・ブランチ保全の横断記録は汎用名のままとする。CURRENT-REFRESH.json は設定・来歴データであり改名しない。BASELINE.md は世代別計測への索引とする。
- 既に世代別サブディレクトリに入っている `r2/` と `backport-r1/` の来歴・検証資料はディレクトリ名で区別できるため変更しない。automation/ の複数世代にまたがる運用・移植計画も維持する。

## 旧名と現行名（13件）

| 変更前（旧ブランチ・変更前 main） | 現行 main | 内容 |
|---|---|---|
| `BASELINE.md` | [R4-R5-BASELINE.md](R4-R5-BASELINE.md) | r4/r5 基準計測履歴 |
| `COMMON005-ROCM-VALIDATION-2026-10-02.md` | [R3-COMMON005-ROCM-VALIDATION-2026-10-02.md](R3-COMMON005-ROCM-VALIDATION-2026-10-02.md) | r3 ROCm 検証 |
| `COMMON005-VALIDATION-2026-10-02.md` | [R3-COMMON005-VALIDATION-2026-10-02.md](R3-COMMON005-VALIDATION-2026-10-02.md) | r3 Vulkan/ROCm 検証 |
| `ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md` | [R3-ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md](R3-ROCM-QSA-PROFILING-SOURCE-TRACE-2026-10-01.md) | r3 QSA 調査 |
| `PERFORMANCE-CANDIDATES-2026-10-03.md` | [R4-PERFORMANCE-CANDIDATES-2026-10-03.md](R4-PERFORMANCE-CANDIDATES-2026-10-03.md) | r4 基準の候補調査 |
| `OPTIMIZATION-SUMMARY-ja.md` | [R2-OPTIMIZATION-SUMMARY-ja.md](R2-OPTIMIZATION-SUMMARY-ja.md) | r2 時点の高速化まとめ |
| `GEMMA4-GLOBALFA-RGP-GATE-20261121.md` | [V1-GEMMA4-GLOBALFA-RGP-GATE-20261121.md](V1-GEMMA4-GLOBALFA-RGP-GATE-20261121.md) | v1.0.0 派生の Global FA 診断 |
| `GEMMA4-V1-PP-RGP-20261121.md` | [V1-GEMMA4-PP-RGP-20261121.md](V1-GEMMA4-PP-RGP-20261121.md) | v1.0.0 PP/RGP 比較 |
| `GEMMA4-V1-VULKAN-FA31323-PORT-2026-11-21.md` | [V1-GEMMA4-VULKAN-FA31323-PORT-2026-11-21.md](V1-GEMMA4-VULKAN-FA31323-PORT-2026-11-21.md) | v1.0.0 Vulkan 移植 |
| `GEMMA4-V1-VULKAN-TG-RGP-2026-11-16.md` | [V1-GEMMA4-VULKAN-TG-RGP-2026-11-16.md](V1-GEMMA4-VULKAN-TG-RGP-2026-11-16.md) | v1.0.0 TG/RGP 診断 |
| `ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md` | [R6-ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md](R6-ROCM-PP-GPU-TIMING-EXPERIMENT-2026-11-15.md) | r6 PP 診断 |
| `ROCM-PP-PROFILE-128K-2026-11-15.md` | [R6-ROCM-PP-PROFILE-128K-2026-11-15.md](R6-ROCM-PP-PROFILE-128K-2026-11-15.md) | r6 128k PP 計測 |
| `ROCM-PP-PROFILE-64K-2026-11-15.md` | [R6-ROCM-PP-PROFILE-64K-2026-11-15.md](R6-ROCM-PP-PROFILE-64K-2026-11-15.md) | r6 64k PP 計測 |

旧 BASELINE.md の詳細本文は R4-R5-BASELINE.md へ移動し、BASELINE.md 自体は新しい横断索引に置き換えた。その他の旧名は main の現行ファイルとして残さない。

## 過去ブランチとの照合

2026-11-24 の命名整理は main のみに適用する。開発・診断用ブランチやアーカイブタグを一律に書き換えない。旧名とソースの対応を記録しているブランチ台帳、固定 SHA の参照、インポート時点のファイル一覧は当時の情報として保持する。アーカイブタグの一覧は [BRANCH-ARCHIVE-TAGS-MANIFEST-2026-11-23.json](BRANCH-ARCHIVE-TAGS-MANIFEST-2026-11-23.json)。

旧ブランチに存在する文書を探すときは上表で旧名・現行名を正規化してから比較する。例（Git CLI、旧ブランチ名は存在するものに変更可）:

```powershell
git diff --no-index <旧ファイルのローカルコピー> <現行ファイルのローカルコピー>
# 個別ファイルを比較（blob 同士を指定）
git diff 'r5/upstream-refresh-20261009:docs/evox2/BASELINE.md' 'main:docs/evox2/R4-R5-BASELINE.md'
# 改名前 main の内容を確認
git show 'cb614f15cf4f1ddcccf7d717350b3f41de0d74f1:docs/evox2/BASELINE.md'
```

命名整理は過去実験の計測値、採否、実装状態の変更ではない。文書中の現行名への参照修正と、履歴の参照先を区別する。
