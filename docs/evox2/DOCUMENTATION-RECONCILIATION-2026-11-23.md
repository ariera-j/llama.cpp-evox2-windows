# Evo-X2 文書統合・現行ステータス（2026-11-23 JST）

> **対象:** この公開リポジトリの `main` にある研究・ビルド・自動化の文書。**本書はドキュメントの整理であり、新しい推論ソースのビルド、計測、最適化の採用を証明するものではない。**実験時点の測定値、モデル、build/commit、バックエンド、フラグの区別は各原報告が正本。本書の「現在」は2026-11-23時点で、実機で本日進行中の作業についてはユーザー報告を含む。

## 1. どこを最新の入口として読むか

| 文書 | 役割と読み方 |
| --- | --- |
| [本書](DOCUMENTATION-RECONCILIATION-2026-11-23.md) | 2026-11-23の作業状態、旧予定からの移行、ブランチ差分の扱い |
| [README](README.md) / [ROADMAP](ROADMAP.md) | 研究資料への入口・時系列。古い「現行」「次」「未実施」はその記載日時の状態 |
| [PATCHES](PATCHES.md) | **採用ソース／実験ソース／既定フラグを分離**したパッチ記録。過去の未実装・未検証行は当時の状態 |
| [PERFORMANCE-RESEARCH-LOG](PERFORMANCE-RESEARCH-LOG.md) | 計測・RGP等の時系列研究記録。旧スナップショットは消さない |
| [INTEGRATED-RELEASES](INTEGRATED-RELEASES.md) | 公開タグ・配布物・実測バイナリの別々の来歴 |
| [Codex RUNBOOK](automation/RUNBOOK.md) | Codex専用clone、Vulkan/ROCmビルド経路の安全な実行手順 |
| [2026-11-18 外部調査・優先度更新](R6-NEXT-PRIORITIES-EXTERNAL-REFRESH-2026-11-08.md) | 11/08原計画に対する11/18追補。11/23の更新については本書を優先 |

**根本ルール:** 「文書がmainに存在する」≠「当該実験のソースがmainへ統合された」≠「現在のバイナリで検証済み」。公開tag `evox2-integrated-2026-10-29`、測定用のb11908、後続のr6/main、upstream v1.0.0、Strataのエンジンは同一とみなさない。

## 2. 2026-11-23 現行の作業・実験状態

| 項目 | 2026-11-23の判定 | 補足・次の扱い |
| --- | --- | --- |
| r6 初回統合チェックポイント | **限定検証・公開済み** | 2026-10-29タグはソースチェックポイント、配布ZIPは**Vulkan b11908のみ**。公開物のビルド時ソースと後続mainを混同しない。S8/S9の適用範囲に限定 |
| COMMON-005 / QSA compact gather | **ROCm MTP-OFF 限定ゲート完了、opt-in/default OFF** | 64k/128k/256k速度・RGP・128k検索品質18runを実施。MTP-ON、Vulkan active path、完全数値一致の一般保証は未了。[詳細](R6-COMMON005-MH128K-QUALITY-PLAN-2026-11-03.md) |
| 実入力 `llama-bench` r6移植 | **完了** | r5 TOOL-001由来。11/03等の「次の実装」は過去の予定 |
| PP入力依存性（FA/QSA Mask/Indexer/MoE/RGP） | **11/08までの主調査は完了** | コード・文学等の差、RGP/Indexer位置合わせ、ROCm MoEの条件付き一致を確認。実験の局所相関を因果・全体PP性能へ拡張しない。[設計・履歴](R6-PP-INPUT-FA-MASK-MOE-QUANT-PROFILING-DESIGN-2026-11-04.md) |
| 日本語論文要約とMH-Hard品質比較 | **実施済み** | 旧IQ3・IQ4・新IQ3・旧IQ1・ROCmFP4等を評価。MH-Hardは独立データseed、逆順、複数反復を利用。**旧IQ3を継続、新IQ3の常用採用は見送り、IQ4への常用変更も見送り**。各条件の数値は実験用privateリポジトリを正本とする |
| IQ3/IQ4のROCm PP逆転 | **原因を絞る実験・RGP観察まで実施** | UBatch512/1024、MMQ/FA dispatch位置・回数の差を確認したが、単一の因果原因に確定しない。[64k MMQ調査](R6-ROCM-PP64K-IQ3-IQ4-MMQ-CLI-TRACE-2026-11-10.md) |
| Strata試用（v0.2.13 / engine 0.1.59） | **実機動作・速度・品質比較済み** | 旧IQ3 3-shard、UMA64GBで64k/128k/256k等と日本語要約・MH-Hardを試した。llama.cpp r6/上流と条件差を明記して比較。**Strataの高速化をこのforkへ移植した、という意味ではない**。後続のv0.2.14/0.2.15は11/18時点で外部調査、同条件の実機再計測は別課題 |
| Gemma 4 Vulkan/ROCm PP・TG/RGP調査 | **11/21に調査を整理して一区切り** | FAやGPU側の挙動を追ったが、速度差の単一原因は未確定。#31323/#32415の移植実験worktreeやGlobal FA診断worktreeは**11/22に通常利用・無人Codex/RGP基準から退役**。GPU timeoutの発生と原因・移植実装の欠陥疑惑を混同しない。[PP/RGP](V1-GEMMA4-PP-RGP-20261121.md)、[FA移植](V1-GEMMA4-VULKAN-FA31323-PORT-2026-11-21.md)、[Global FA](V1-GEMMA4-GLOBALFA-RGP-GATE-20261121.md) |
| Codex→EVO-X2接続とビルド自動化 | **環境構築・Vulkan/ROCm preflight確認済み、モデル推論は進行中** | 本日までの接続・権限・既存ラッパーのビルド確認は[RUNBOOK](automation/RUNBOOK.md)を参照。**新Codexビルドラッパーは両backend preflight成功**。そのラッパーによるconfigure・実ビルド、Ple16/ROCmFP4の推論完了を未確認のままPASSと書かない |
| モデル・入力配置の整理 | **後続作業** | 長期の高速化主対象は**IQ3 PLE16版とROCmFP4版**（元の旧IQ3 3-shardはStrata/比較用）。共有入力ファイルは別フォルダへ手動移動・ACL設定した後に `local.codex.psd1` に登録する予定で、現時点で変更済みとは扱わない |
| 次の最適化テーマ | **着手前** | Codex推論テスト→本書の文書統合→ブランチ整理後、Strata / strix.cpp / rdna-boosts / upstreamの実装差を監査し、1候補ずつ別ブランチでopt-in・同一条件A/B・正答確認。**一括移植やmainでの直接高速化はしない** |
| 独立の未完了テーマ | **保留／必要時再開** | QSA UNIONとVRAM clockの相関の追加反復、数値的Draft K/V parity、長期サーバー安定性、Vision品質、未測定モデル/条件、新Strata版、ROCmFPxの未検証経路等。旧「未実施」と同じ課題かどうかを条件ごとに確認 |

## 3. ブランチ文書の差分解消の基準

2026-11-23時点で公開リポジトリの **48ブランチ（mainを含む）** を対象に、`docs/evox2`、`tools/evox2` 配下のテキスト文書とREADMEの同一パス・Git blob SHAを比較した。先行の[51ファイルのmain取り込み](BRANCH-DOCS-IMPORT-2026-11-23.md)は、**mainになかった文書をコピーしたのみ**で、旧版と最新版の同名ファイルは統合していなかった。

1. **後日追記で、mainにまだない正確な新事実:** 実験日と発生条件を保持して元の文書へ取り込む。例：11/22のGemma4 worktree運用判断、11/23のCodexラッパー検証、11/07のMoE/RGP補足。
2. **mainの後続版が追加検証・結論を含む旧スナップショット:** 古い「未実施」「次に行う」へ**上書きしない**。同一ファイルの過去版は元ブランチに残し、現行の読者へは本書と各文書先頭の新しい日付付き追補を示す。
3. **同じ実験計画の改稿:** 過去の条件・判断根拠が別の原報告に保存されているものは、その原報告への参照で集約する。計画が一時期未着手だった事実と、現在完了した事実は両立する。
4. **ソース／ツール／現場設定:** 文書以外は今回変更しない。例えば研究ブランチの `tools/evox2/benchmark/configs/*rdp-settings*.json` は測定設定資産であり、ドキュメント統合を口実にmainの実行条件へコピーしない。
5. **作業ブランチ:** この段階では削除・rebase・force-pushしない。ブランチ本体の整理は推論テストと文書整理の後に別途判断する。

### 代表的な重複の扱い

| 重複・差分グループ | 結果 |
| --- | --- |
| r2/r3/r4の `BASELINE`・`BENCHMARKING`・`ROADMAP`・`PATCHES` | **履歴**。r3の基準計測は独立した[R3-BASELINE](R3-BASELINE.md)にも残る。最新r6の文書へ古い状態を戻さない |
| r5のMTP DENSE/NOOP/Stage-B/flatten、ROCmFPx、QSA関連の実験枝 | 後続の検証がmainの個別日付付き報告とパッチ台帳に存在するものはその結果を正本とする。旧「source-only」「Windows未実施」判定は実装直後の記録 |
| `PERFORMANCE-RESEARCH-LOG` と `PATCHES` の旧枝 | mainの時系列追補版を優先し、旧枝固有の有効な測定補足だけ日付付きで足す |
| r6初期 `R6-INTEGRATION-EXECUTION-PLAN` とS8/S9 runbook | 計画立案時点と実測閉鎖時点を区別。[実測統合結果](R6-S8-COMBINED-RESULTS-2026-10-28.md)が優先 |
| Gemma4 RGP/FA三文書 | **11/22の枝ローカル追記をmainの同名文書へ統合済み**。性能値は維持し、安全性・運用の判断を別節として付記 |
| Codex `automation/RUNBOOK.md` | **11/23の専用ラッパー実装／preflight結果をmainへ統合済み**。モデル推論・新ラッパー実ビルドは別ゲート |

## 4. 本書作成時の保留と検証の境界

- この文書照合は**GitHub上のテキストとshaの比較**であり、EVO-X2ローカルディスク・非公開実験リポジトリの生ログ全件を再集計したものではない。外部実測の正答数や速度値を新たに捏造しない。
- 研究用ブランチの**コードや実験スクリプトはmainへマージしていない**。したがって各文書の実装状態はそのブランチ、commit、binaryと結び付く。
- 2026-11-23以降、Codexによる推論、入力データ移動、次の高速化実装が進んだ場合は、本書の日付を当時のスナップショットとして残し、後日の更新日付き節を最上部に追加する。


## 5. 旧r1 provenanceの追加入庫（2026-11-23）

- `r2/legacy` にのみ存在した [`backport-r1/manifest.json`](backport-r1/manifest.json) を、元のJSONを変更せずmainへ取り込んだ。2026-09-15のr1 upstream適用元・13件のPR・パッチSHA256を記録した**歴史的な来歴データ**であり、現在の実行設定や最新パッチ一覧ではない。
- mainにない `tools/evox2/benchmark/configs/*rdp-settings*.json` はRGP計測条件に関係する**実行設定**なので、この文書限定の統合では変更しない。元の研究ブランチに残し、別途設定資産の整理時に扱う。
