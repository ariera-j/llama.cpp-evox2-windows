# EVO-X2 計測ツールの統合（作業3-5）

GitHub の `main` を標準計測ツールの正本とする。現行製品ブランチ `codex/vulkan-manifest-cpu-variants-20261124` の標準計測ファイルは同じ内容を使用する。運用手順は [計測ルール](BENCHMARK-RULES.md)、[RUNBOOK](RUNBOOK.md)、[ツール README](../../../tools/evox2/README.md) を参照する。

## 採用元と差分

統合開始時は main `76417e3725ba13b2866b1140c634a8e13f71952d`、製品作業ブランチ `f50db0b63c58eb1263b5a46eb569368da2c4f657`、Matrix 専用 `6c09299f680de008524da420a340c162e948fae3`。Matrix の分岐点 `fdd965967eda4da3c90847c348750694a120561f` から計測差分を抽出し、main と製品ブランチ両方の実ファイルと照合した。

| パス（`tools/evox2` 配下） | 採用元と解消方法 |
|---|---|
| `benchmark/Measure-LlamaBench.ps1`、`Measure-LlamaCli.ps1`、`Evox2.Benchmark.psm1`、`Monitor-LlamaProcess.ps1` | Matrix 専用。既存引数、ログ列、バックエンド・バイナリ識別、実入力・合成入力、MTP 診断出力を保持し、詳細監視、部分取得、OS 起動情報を取り込んだ。 |
| `benchmark/Invoke-BenchmarkMatrix.ps1`、`Evox2.MatrixComparison.psm1` | Matrix 専用。従来の設定形式、旧 plan の展開順、絞り込み、環境変数の復元に、ラウンド指定、独立反復、欠損ありの対応比較とロールアップを加えた。 |
| `benchmark/Evox2.Memory.psm1`、`Evox2.OsStartup.psm1`、`Evox2.RamDetail.psm1`、`Monitor-Evox2RamDetail.ps1` | Matrix 専用。起動前・終了後の採取、PID と開始時刻の照合、後片付け、データの品質、フェーズ受信、メモリ回復判定。 |
| `benchmark/configs/local.b12651.example.psd1`、`qwen38-b12651-comparison.example.psd1`、`qwen38-b12651-monitor-overhead.example.psd1`、`qwen38-b12651-vulkan-abba.example.psd1` | Matrix 専用の公開例。オーバーヘッド比較例に通常設定と詳細監視設定の説明を加えた。 |
| `benchmark/tests/Test-BackgroundActivityClassification.ps1`、`Test-MatrixComparison.ps1`、`Test-MonitoringQuality.ps1`、`Test-MonitoringQualityMatrix.ps1`、`Test-OsStartup.ps1`、`Test-RamDetailLifecycle.ps1`、`Test-RamDetailNonInference.ps1`、`Test-ResourceMonitorCadence.ps1` | Matrix 専用。通常監視、旧 CSV 互換、ADLX、障害時の継続と停止、RAM タイムライン、Matrix の成功・失敗と欠損を扱う。 |
| `lib/Evox2.Common.psm1`、`pmode/tests/Test-Evox2PModeMetadata.ps1` | 現行製品側の COM 呼び出し、直近の更新と捕捉時刻、昇格結果・Method ID・応答値の整合確認を採用。主な機能差は P-MODE のみで、ビルド関数は同じ。 |
| `adlx-gpu-monitor/Run-AdlxGpuMonitor.ps1` | 両枝で UTF-8 BOM とローカル変数名を揃えた。既存の実行引数と既定値を保持。ADLX C++、実行ファイル、ビルド手順は既存のものを使用する。 |

Matrix 専用の実装履歴は保持し、ブランチ全体の merge は行っていない。main 固有の r4～r6 設定例と MTP/QSA 診断工具・旧文書を保持した。製品側と main の製品ソース、ビルドラッパー、P-MODE 管理者向けインストール／読取りスクリプトの差分は各枝に保持する。ADLX のビルドスクリプトには既存の BOM 差が残る。ビルド統合候補は `Invoke-CodexBuild.ps1`、`Build-Vulkan.ps1`、`Build-ROCm.ps1`、`Evox2.Build.psm1`、`Evox2.DependencyCache.psm1`、依存入力と CPU variant のテスト。別作業で採用範囲を決める。

## 検証と実機固有設定

- Windows PowerShell 5.1.26100.10068 の隔離 worktree で両枝を検証した。25対象ファイルの構文・UTF-8 BOM・予約変数への代入・設定読み込み、モジュール参照、既存引数の型・既定値・位置順、`git diff --check` を確認した。Measure と Matrix の新規引数は既存引数の後ろに追加して位置引数を維持した。
- 旧ローカル plan、4構成×3ラウンド、明示順と対象の絞り込み、ABAB／ABBA／Rotate、MaxRuns、無効な Base、同一ラウンドの欠損・失敗、CLI／bench 混在、StopOnError、クールダウンの上書きと環境復元を確認した。main 固有の旧 r4 CLI／bench 比較も12件展開した。
- 両 Measure は既存 EXE とローカル設定で `DryRun` を通した。模擬ラッパーで旧 CSV・追加列・JSON の読み取りと集計、実測0・欠損・部分取得、通常監視の復帰と終了競合を確認した。
- 詳細100 ms と通常監視＋詳細250 ms の短い非推論試験は両方で終了し、ネイティブ欠損0、残留 PID なし。一部の任意プロセス情報は SSH でアクセス拒否となった。既存 ADLX 1.5 は非推論で Radeon 8060S を列挙し有効3サンプル。P-MODE は COM の模擬鮮度・拒否・不正応答と実機 Performance、OS 起動情報と System／Application の読取り・該当0件を確認した。
- 実モデルの統合検証は作業3-4を参照する。今回は EXE のメタデータ取得までで、モデルロードや性能の再計測は行っていない。別のバイナリ、ドライバ、ワークロードでの監視・安全条件は各実験で確認する。

既存の実機 `benchmark-configs` は読み取り専用で使用し、公開例にはプレースホルダーを使う。作業3-4の生ログ、障害ログ、保全コピーはそのまま保持する。実機では ADLX ヘルパーがリポジトリ外にあるため、必要ならローカル plan または Measure の `-AdlxMonitorExe` で既存実行ファイルを明示する。

新しい実験ブランチは検証済み製品ベースから作り、計測ツールを更新するときは main の採用コミットと変更パスを固定する。該当ファイルの差分を確認して取り込み、独自変更があればファイル単位で統合する。ツールだけをコミットし、`PlanOnly`／`DryRun` と関連テストを通す。過去の plan・製品パッチは各実験ブランチに保持する。

作業4へは M001、Round 3 D、ROCm CLI の RAM 逼迫、IQ2_S A1/A2 のロード／初回 eval 遅延を引き継ぐ。バイナリ・run ID・計測境界・ログ参照は作業3-4の追加集計に記載。 [追加集計と引き継ぎ](BENCHMARK-MATRIX-ROUNDS-B12651.md#作業3-5で照合した追加集計)
