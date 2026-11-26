# b12651 Benchmark Matrix 移植・互換性確認（作業 3-1）

> 本文は当時の検証記録。標準運用は [計測ルール](BENCHMARK-RULES.md) と [作業3-5の統合記録](BENCHMARK-INTEGRATION.md) を参照。


対象は `codex/vulkan-manifest-cpu-variants-20261124` の開始時 HEAD `fdd965967eda4da3c90847c348750694a120561f`。移植元は GitHub `main` の `14bfbe376b8cb6c3b21d4ebbe80aacf005973ded`。実装は専用ブランチ `codex/benchmark-matrix-b12651-20261125` のコミット `0baa3725671a0f3cb9756579d2e78af6e64ee624` に置く。計測時は [BENCHMARK-RULES.md](BENCHMARK-RULES.md) を参照する。実行コードは専用ブランチでレビューする。 [移植元 Matrix](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/14bfbe376b8cb6c3b21d4ebbe80aacf005973ded/tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1) · [実装コミット](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/0baa3725671a0f3cb9756579d2e78af6e64ee624)

## 移植範囲と依存関係

| 追加ファイル | 内容 |
|---|---|
| `tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1` | SchemaVersion 1 の plan、Job → Case → Build → Model → Variant 順の展開、絞り込み、MaxRuns、クールダウン、監視のオーバーライド、StopOnError、子出力の集計を移植。 |
| `tools/evox2/benchmark/configs/local.b12651.example.psd1` | 公開用 LocalConfig。パスは置き換え用の例。 |
| `tools/evox2/benchmark/configs/qwen38-b12651-comparison.example.psd1` | COMMON-001 同士の Vulkan／ROCm 比較、Stage 2 Vulkan の 2 モデル比較、実入力を使う CLI を定義。 |
| `tools/evox2/benchmark/configs/qwen38-b12651-vulkan-abba.example.psd1` | 同一 Stage 2 Vulkan バイナリに対する明示順 A1 → B1 → B2 → A2 の環境変数 A/B。 |

Runner は現行の `Evox2.Benchmark.psm1` と `lib/Evox2.Common.psm1` を読み込み、現行の `Measure-LlamaBench.ps1` / `Measure-LlamaCli.ps1` を呼ぶ。前者のモジュールと Measure 2 ファイルの移植元との差分は BOM のみ。共通モジュールには BOM に加え、現行ブランチの P-MODE 用 COM 呼び出しと取得結果の鮮度検証がある。必要な export と Measure の引数は現行版に揃っているため、これらの既存ファイルと `Monitor-LlamaProcess.ps1` は現行版を保持した。製品ソースに差分はない。

Matrix 本体と設定例は UTF-8 BOM 付き。CLI の表示で PowerShell 自動変数 `$input` と衝突していた変数を改名した。bench の `InputKey` は CLI と同様に LocalConfig で照合する。環境変数の適用と子呼び出しを同じ `try/finally` の範囲に置いた。CSV は最初の行のプロパティで列を決めるため、bench 行にも CLI 専用の識別・根拠列を空欄で持たせる。これにより bench から始まる混在 plan でも CLI の DenseIndexer／QSA 証跡列が落ちない。既存の列名、SchemaVersion、ファイル名、子ラッパーの出力形式を使用する。

## 設定と PlanOnly

1. `local.b12651.example.psd1` を Git 管理外へコピーし、`LogRoot`、`Builds.<Key>.BinDir` / `ExpectedBackend`、`Models.<Key>.Path` / `Alias`、`Inputs.<Key>` を実機に合わせる。入力キーはファイルパス文字列。BuildKeys / ModelKeys と整合させる。
2. 実機の専用 LocalConfig と、ADLX パスを明示する実機用 plan 2 件は専用 worktree の外に置いた。名前は `local.b12651-matrix.psd1`、`qwen38-b12651-comparison.local.psd1`、`qwen38-b12651-vulkan-abba.local.psd1`。別環境で ADLX が既定パスにない場合も、各ツールの既存引数 `AdlxMonitorExe` をローカル plan の BenchParameters / CliParameters に設定できる。
3. 実行前に `-PlanOnly` で件数と順序を確認する。PlanOnly は plan とキー・引数名を検証して展開を表示し、計測用ログや実行プロセスを作らない。実機パスの存在と実行ファイルの対応フラグは別途確認する。実計測を承認された際は、UMA 容量、P-MODE、競合プロセス、開始時メモリ、監視サンプルを確認する。

```powershell
$configDirectory = 'C:\path\to\private-benchmark-configs'
$matrix = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
$config = Join-Path $configDirectory 'local.b12651-matrix.psd1'
$comparison = Join-Path $configDirectory 'qwen38-b12651-comparison.local.psd1'
$abba = Join-Path $configDirectory 'qwen38-b12651-vulkan-abba.local.psd1'

& $matrix -LocalConfig $config -Plan $comparison -Tool bench `
    -OnlyJob bench-backends-iq3 -OnlyCase tg32 -OnlyBuild RocmCommon001 `
    -OnlyVariant default -MaxRuns 1 -ResourceMonitor -StopOnError -PlanOnly
& $matrix -LocalConfig $config -Plan $comparison -MaxRuns 6 -PlanOnly
& $matrix -LocalConfig $config -Plan $abba -MaxRuns 4 -PlanOnly
```

表の 3 ビルドでは、実機に存在する CLI・bench の SHA-256 を各マニフェストの記録と照合した。2 モデルの GGUF と既存の `nlp-survey-ch3-d7-b1.txt` も実在を確認した。UMA96GB は plan の条件ラベル。

| BuildKey | 既存ビルド | マニフェストの製品ソース |
|---|---|---|
| VulkanStage2 | `build-s2v`・b12676 Vulkan | `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1` |
| VulkanCommon001 | `build-c1v`・b12671 Vulkan | `35818246a27521327e627e8f323e5f3a6386f8f9` |
| RocmCommon001 | `build-c1r`・b12671 ROCm | `35818246a27521327e627e8f323e5f3a6386f8f9` |

r6 の既存設定はデータとして読み取った。過去の baseline は実入力 CLI と合成入力 bench を分け、全層 GPU、CPU MoE 0、F16 KV、threads 4、batch 2048、ubatch 1024、リソース監視を指定していた。r6 の性能比較には 64k／128k の MTP ON など対象実装固有の条件もあった。今回の設定例は MTP OFF。Stage 2 の `llama-bench --help` では `-c` を確認でき、実入力用の `-f` と `--prompt-slice` は出なかったため、例では実入力を CLI に割り当てた。

ABBA 例では A で `GGML_VK_DISABLE_GRAPH_OPTIMIZE` を解除し、B で `1` を設定する。対象のフラグは変数の有無を参照するため、A を `0` で表さない。`EVOX2_ABBA_RUN` は繰り返しを区別する run 識別子で、同一有効条件の重複検出を維持する。順序は Variants の配列で明示する。自動での交互化とラウンド別集計は今後の候補。

## 非推論の確認結果

| 確認 | 結果 |
|---|---|
| 実機 PowerShell `5.1.26100.10068` | Matrix、現行ラッパー・依存モジュールと設定の構文、UTF-8 BOM、モジュール export、データファイルの読み込みを確認。 |
| PlanOnly | 現行 LocalConfig の単一条件 1 件、比較 6 件、ABBA 4 件。2 ビルド × 2 モデル × 2 Variant のテスト plan は 8 件、OnlyVariant で 4 件。MaxRuns=3 で 4 件の plan を拒否し、bench の未登録 InputKey も拒否。実機専用 plan と r6 の既存 Vulkan ABBA 64k サブセットも読み込み、順序を確認。 |
| 実バイナリを使うラッパー DryRun | 比較 plan 相当の bench 4 件と CLI 2 件で、実行ファイルの識別・デバイス列挙、モデルと入力の解決、コマンドプレビューを確認。モデルはロードしていない。 |
| テスト用の子ラッパー | 現行ラッパーのパラメータ宣言を使い、A1/B1/B2/A2 の実行順、ResourceMonitor の ON/OFF、環境変数の設定・解除・復元、子例外時の StopOnError と復元を確認。 |
| 集計互換性 | テストデータで `matrix-plan.json`、`matrix-runs.csv`、`matrix-results.csv`、`matrix-result.json` を読み戻した。混在 6 run で bench 値と CLI 値・根拠列、失敗シナリオで 1 件での途中停止を確認。失敗判定には `matrix-result.json` の `StoppedEarly`・各 run の状態も参照する。 |

実機ログは Codex ログ領域の `matrix-b12651-31-verification-9d63c1` と `matrix-b12651-31-fixtures-9d63c1`。前者の transcript に実バイナリのプレビュー、後者にテスト用出力を保存した。一部のプレビュー取得時は専用 worktree のコミット前で、出力に GitDirty が立つ。使用したバイナリとファイル内容はコミット前後で同じ。既定の ADLX パスは専用 worktree に存在せず、実機用 plan を別に作成して既存 ADLX のパスと PlanOnly を確認した。実機の LocalConfig、ローカル plan、試験用データは Git 管理外。

実運用での未検証項目は、Matrix から実 Measure を起動した場合のモデルロード、PP/TG・GPU オフロード・実効 UMA／P-MODE、通常の子出力、PerfMon・ADLX のサンプル、クールダウン後のメモリ解放と実際の速度差。監視修正や高頻度 RAM 監視、自動交互実行、ラウンド別集計は別作業とする。
