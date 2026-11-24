# b12651 初期 PP/TG 32k 試験計測（2026-11-24）

Vulkan、ROCm の順に各1回、Windows PowerShell 5.1 の `Measure-LlamaCli.ps1` で実行した。計測時の作業ブランチは `integration/upstream-b12651-20261124`、HEAD は `1ada4beae1db6bfa8e2f4679dbb6e3c8e78ce1f8`。既存バイナリのハッシュを Verified マニフェストと照合し、両方の DryRun と監視ツールの起動前確認が通った。モデル・入力は既存の Git 管理外 `local.codex.psd1` を使用した。

| バックエンド | 実行ファイル（clone 相対） | ビルド・ソースコミット | 実行ファイル SHA-256 |
|---|---|---|---|
| Vulkan0 | `build-b12651-vk/bin/Release/llama-cli.exe` | b12660・`feccc7e539a435b0bcd128f223d40291e9e7121c` | `2e7f5135ded3917d20a1d9183c9ef04b74beea9fcdfad16ee7e7d845b3590abe` |
| ROCm0 | `build-b12651-r/bin/Release/llama-cli.exe` | b12662・`7a06ee2a38f4213c28533176f9d6ba896a670440` | `b1fa09954e77510aa0db1d2bab35faf70f1e4662dd9f631f185a5a7b42029e6a` |

## 入力とコマンド

- モデルは `Models.UnslothOriginal` の Unsloth Qwen3.8 Flash Next 旧 UD-IQ3_XXS。元の3シャードは `Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf` から `00003-of-00003.gguf`（10,946,624 / 49,567,921,344 / 32,382,955,968 bytes）。各シャードの SHA-256 は未計算。
- 入力は `Inputs.'32k'` の `nlp-survey-ch3-d3-b1.txt`（145,547 bytes）。指定ディレクトリにあり、SHA-256 は `1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601`。過去の日本語論文入力と一致。
- 過去の Qwen 計測の 29,557 トークンに生成上限 256 を加えると 29,813。過去の32k計測にも合わせて context 32768 を採用し、今回も両方の実入力が 29,557 とログで確認できた。

実際にラッパーが生成したCLI呼び出しを変数で表記する。バッチ用スレッドも実ログで4。EOSは有効、MTP・Fit・reasoning・RAMプロンプトキャッシュ・コンテキストチェックポイントは無効。

```powershell
$cfg = Import-PowerShellDataFile .\tools\evox2\benchmark\configs\local.codex.psd1
$model = $cfg.Models.UnslothOriginal.Path
$paper = $cfg.Inputs['32k']
$opts = @('-m', $model, '-c', '32768', '-ngl', '999', '-ncmoe', '0',
    '-t', '4', '-b', '2048', '-ub', '1024', '-fa', 'auto', '-lv', '4',
    '-ctk', 'f16', '-ctv', 'f16', '-fit', 'off', '--cache-ram', '0',
    '--temp', '0', '--top-p', '0.8', '--reasoning', 'off', '--jinja',
    '--single-turn', '--spec-type', 'none', '-n', '256', '-f', $paper,
    '--seed', '1234', '--ctx-checkpoints', '0', '--no-display-prompt')
& .\build-b12651-vk\bin\Release\llama-cli.exe @opts
& .\build-b12651-r\bin\Release\llama-cli.exe @opts
```

## 試験結果

| 項目 | Vulkan | ROCm |
|---|---:|---:|
| 終了コード / ラッパー判定 | 0 / OK | 0 / OK |
| Prompt / 生成トークン | 29,557 / 256 | 29,557 / 256 |
| PP tok/s / 秒 | 461.65 / 64.024 | 502.35 / 58.837 |
| TG tok/s / 秒 | 26.92 / 9.472 | 25.42 / 10.033 |
| GPU オフロード層 | 49/49 | 49/49 |
| CLI の GPU モデルバッファ (MiB) | 50,191.11 | 50,191.17 |
| ADLX サンプル / VRAM 有効値 / 終了コード | 64 / 64 / 0 | 61 / 61 / 0 |
| ADLX VRAM 最大（CSV の MB 列） | 53,158 | 52,778 |
| リソースモニターのサンプル | 51 | 48 |
| PID別 GPU Dedicated / Shared 最大 (GiB) | 51.384 / 0.554 | 51.012 / 0.636 |
| アダプター Dedicated / Shared 最大 (GiB) | 51.913 / 0.619 | 51.541 / 0.700 |
| 物理 RAM 使用最大 / 空き最低 (GiB) | 40.048 / 23.600 | 38.400 / 25.247 |
| システムコミット最大 (GiB) | 92.716 | 92.050 |
| Pages Input / Page Reads / Page Faults 最大 (毎秒、各列の最大) | 846,509.5 / 2,094.3 / 1,653,575.6 | 944,298.7 / 2,210.5 / 1,715,334.4 |

ページ入力の主要ピークはモデルロード中。プリフィル中の確認サンプルでページ入力は Vulkan 4.9/s、ROCm 16.8/s まで低下し、両回の回復確認では入力・読み出しとも0。これらのカウンターはファイルマッピング由来の読み込みを含み、ページファイル使用量は未測定。

Vulkan終了後、llamaプロセスが消失し、空きGPUメモリ108,610 MiB、物理空き54.509 GiB、コミット10.951 GiBに回復してからROCmを実行した。ROCm終了後もプロセスが消失し、空きGPUメモリ101,974 MiB、物理空き55.506 GiB、コミット10.996 GiB。両回終了後のアダプター Dedicated / Shared は 0.529 / 0.064 GiB。

いずれも判読可能な日本語を生成し、256トークンで終了した。CLIログに device lost、GPU割り当て失敗、メモリ枯渇は見当たらず、照会した Windows イベントにも表示リセット・異常再起動・LiveKernelEvent はなかった。両CLIはAPIキー/CORSの起動警告、無効キャッシュに伴う idle-slot cache の無効化、テンプレートの reasoning-preserve 既定値を報告した。P-MODE は WMI/CIM の権限不足で開始・終了とも Unknown、バックグラウンドCPUも取得不可。ADLX の高負荷電力は 117.0 / 117.548 W だったが、P-MODE の確定には用いない。

## 比較範囲とログ

同じ入力と主要設定のため過去の値と参考比較は可能。[r4 32kペア](../R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md#post-fix-windows-smoke-and-32k-pair) は128生成・ignore-eosと下流最適化を使用し、[r5の32k ABBA](../R5-QWEN38-TWO-BINARY-MODEL-COMPARISON-2026-10-23.md) は Unsloth PLE16、UMA 96 GB、生成上限512。今回は旧3シャード、単発・固定順で、P-MODE、バックグラウンド負荷、OSファイルキャッシュの同等性が確認できていない。速度差の原因や性能順位の確定には使わない。

生ログは `C:\llama-build\_logs\codex` に保存した。各ディレクトリの `conditions.json` に実コマンド、`result.json` と `summary.csv` に結果、`resources.csv` と `gpu-metrics.csv` に時系列がある。

- Vulkan `20261124-103542-349-cli-vulkan-b12660-ctx32768-e779519bb301`
- ROCm `20261124-103958-159-cli-rocm-b12662-ctx32768-d0d0d1d0542d`
- 起動前モニター `b12651-32k-precheck-d453d80f75bc40b280b7cc6ef7ee1d3e.csv`
- 回復確認 `b12651-32k-recovery-5488cad3cf0d4525af93f48277c9a877` と `b12651-32k-rocm-recovery-0be71d023d2f4834b63d3515a305c6e5`

再ビルド、追加試行、Gemma 4、64k以上の入力、backend演算テストは実施していない。
