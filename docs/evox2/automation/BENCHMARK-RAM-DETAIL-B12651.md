# b12651 モデルロード時の RAM 詳細監視（作業 3-3）

> 本文は当時の検証記録。標準運用は [計測ルール](BENCHMARK-RULES.md) と [作業3-5の統合記録](BENCHMARK-INTEGRATION.md) を参照。


Matrix 専用ブランチの実装 [c5966f009](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/c5966f0097d28e294c1715d06244c908e7cb5f31) を対象とする。作業開始時の HEAD は `603094a70a1fe731c8cf2d80ed3c0fe62b75af8d`。通常監視の来歴は [作業 3-2](BENCHMARK-MONITORING-B12651.md)、Matrix の起動・設定は [作業 3-1](BENCHMARK-MATRIX-B12651.md) に記録している。

## 起動と終了

`-RamDetail` の指定で Measure 系は詳細監視プロセスを起動し、ネイティブ RAM の最初の有効行が書き込まれたことを確認する。設定した起動前観測窓を置いて対象を起動し、PID と OS の開始時刻を監視側へ渡す。監視側は両方を照合して PID の再利用を避ける。PID 引き渡しまでの区間もシステムの時系列は続く。接続できない場合は PID 情報を欠損とし、ランチャーが終了を確認するまで post 区間と判定しない。

対象終了後は指定した観測窓だけシステムを測る。起動例外時は停止を通知し、親が失われた場合は監視が自ら終了する。準備・全体の監視・終了待ちにはそれぞれ上限があり、応答がなければ起動した監視子だけを終了する。詳細監視の失敗・タイムアウトは品質に記録する。通常の実行は既存の成否判定に従うので、診断解析では `RamDetail.Status` も確認する。

通常 2 秒の PerfMon 監視、ADLX、RAM 詳細監視は別プロセス。詳細サンプラーは `GetPerformanceInfo()` と PID のプロセスメモリ API だけを利用する。CSV は開いたままバッファへ書き、準備完了時と約 1 秒ごとにフラッシュする。ADLX を併用すると既存 ADLX ロガーの終了基準を RAM 監視子の PID に設定し、対象プロセスの前後も GPU 全体を観測できる。ADLX の準備を待ってから各 RAM サンプルを採る処理はない。通常監視と ADLX の既定間隔は従来どおり。

## オプションと出力

| Measure の引数 | 値 |
|---|---|
| `-RamDetail` | 指定時のみ有効。 |
| `-RamDetailIntervalMs` | 実装上の初期値 250 ms、範囲 100～1,000 ms。採用間隔は実モデル統合評価後に判断する。 |
| `-RamDetailPreSeconds` / `-RamDetailPostSeconds` | 既定 3 秒 / 5 秒。各 0～120 秒。 |
| `-RamDetailReadyTimeoutSeconds` / `-RamDetailTimeoutSeconds` | 既定 10 秒 / 3,600 秒。後者は監視子の寿命上限。 |
| `-RamDetailPeakThresholdMiB` / `-RamDetailRecoveryToleranceMiB` | 基準からの増加閾値は既定 64 MiB、解放評価の許容差は既定 128 MiB。 |

Matrix の `Defaults.BenchParameters`、`Defaults.CliParameters` または Job／Case／Variant の `Parameters` に同名で設定できる。詳細監視を有効にしたときだけ設定を条件 ID に含める。次は既存 plan のパラメータ例で、実行前に `-PlanOnly` で展開を確認する。

```powershell
BenchParameters = @{
    ResourceMonitor = $true
    RamDetail = $true
    RamDetailIntervalMs = 250
    RamDetailPreSeconds = 3
    RamDetailPostSeconds = 5
    RamDetailPeakThresholdMiB = 64
    ExtraArgs = @('--progress')
}
```

- `ram-detail.csv` に Run ID、UTC、ホストの単調増加 tick、間隔、段階、取得状態とエラー、PID 識別情報、メモリのバイト値を保存する。項目は総 RAM・使用 RAM・利用可能 RAM、コミット量・上限・率、System Cache、起動後のコミットピーク、Working Set・Private・Virtual。PID が存在しない前後の列は空欄で状態は `NotApplicable`。
- `ram-monitor.json` は監視側の起動・準備・PID 接続・終了時刻、取得失敗件数、停止理由を記録する。`ram-events.jsonl` はランチャー側の UTC、単調増加 tick、起動要求・PID 取得・対象終了観測、ログ行を読んだ時刻を記録する。OS の実プロセス開始・終了時刻を取得できた場合は別に記録する。通常監視の行時刻と RAM・プロセスメモリ取得時の UTC／tick、ADLX のローカル時刻を Windows のタイムゾーンで UTC に換算した値を対応付ける。夏時間切替で一意に換算できない ADLX 行は解放集計から除く。
- `result.json` に `RamDetail` を追加する。取得状態、指標ごとの有効数と欠損数、間隔、基準とピーク、終了後の状態、ログ参照を含む。子の `summary.csv` と Matrix の run／結果には詳細監視状態、RAM 増加量、システム解放判定だけを追加する。 `resources.csv`、`gpu-metrics.csv`、元の stdout・stderr と既存列は維持する。通常 CSV 末尾にネイティブ RAM・プロセスメモリ取得時の UTC と tick を追加した。

## ピークと解放の定義

基準は起動要求前の最後の有効なシステム RAM サンプル。CPU 側のピーク・最低利用可能 RAM・最大コミット・System Cache と、PID 接続後の最大 Working Set 等を別に集計する。閾値は基準使用量に設定 MiB を加えた値。連続して閾値以上を観測した隣接サンプルの間隔だけを合計し、その最長の連続観測区間も出す。欠損や設定間隔の 2 倍を超えた箇所で連続区間を切る。1 サンプルだけのピークに正確な継続時間を割り当てることはできない。

解放は対象終了後の最後の有効サンプルと基準を比較する。システム RAM とコミットがともに基準＋許容差以下なら `WithinTolerance`、超過を観測した場合は `AboveTolerance`、比較に必要な値がない場合は `Unobserved` とする。GPU も ADLX が報告した VRAM を独立して比較し、同じ数値の許容差を ADLX の MB 単位で適用する。ファイルキャッシュや他プロセスの活動があるため、この判定は特定プロセスのメモリ解放の証明ではない。UMA の CPU 側と GPU 側の数値は単純合算しない。

## 処理段階のマーカー

Stage 2 の既存 Vulkan CLI stderr と対応ソースを読み、次の報告行を対象とした。元ファイルには書き込まず、サイドカーには行番号とマーカー種別を記録する。

| 段階 | 参照した報告行 |
|---|---|
| バックエンド・モデル読み込み | `load_backend:`、`llama_prepare_model_devices: using device`、`llama_model_loader: loaded meta data`、`load_tensors: loading model tensors` とオフロード・モデルバッファ報告。 |
| コンテキスト・メモリ・グラフ | `llama_context: constructing`、KV／計算バッファ容量、`sched_reserve:` 等の予約報告。 |
| Warmup・初回 eval | CLI の warmup 通知、bench の `--progress` による warmup prompt／generation 通知。最初の eval の実時刻と完了はこれらから確定できない。 |
| PP・TG | CLI の `prompt eval time`／`eval time` は終了時等の集計報告。bench の `--progress` では prompt／generation run の通知も取得候補となる。 |

ログ受信時刻はラッパーがリダイレクト済み行を読んだ時刻。バッファリング、stdout/stderr の非同期性、ポーリング、最終ドレインの上限がある。改行で完結した行が対象。別ストリームの受信順を内部実行順とは扱わない。設定・ログレベルによって出ないマーカーは `Unobserved`。内部区間の正確な開始・終了時刻は推定で埋めない。 [b12651 bench の warmup と PP/TG](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp) · [b12651 llama-context.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp)

## EVO-X2 SSH での非推論検証

Windows PowerShell 5.1、UTF-8 BOM、既存の通常監視・旧 CSV、および Measure の引数と Matrix への集計を確認した。模擬テストでは、ネイティブ取得失敗からの復帰、準備のタイムアウト、監視期限、対象起動失敗、PID 再利用防止、親終了と監視子の停止を確認した。非推論子の段階マーカーは、既知の待ち時間と出力順で受信順・時刻を検証した。

小規模な非推論子プロセスが 32 MiB を確保し、各ページに書き込み、保持後に解放した。短パルスは各構成 6 回、実測約 133～148 ms。長パルスは 1 回、約 2.61 秒。事前の静止区間に対し対象 Working Set が 16 MiB 以上増えたサンプルを、実行ホストの単調増加 tick でパルス保持区間に照合した。通常監視の行時刻は PerfMon 後なので、通常監視と併用の捕捉結果は新しく追加したメモリ取得時 tick を使って再確認した。

| 構成 | 短パルス | 長パルス | サンプル数・欠損 | 平均／最大間隔 |
|---|---:|---:|---|---|
| 監視なし | 観測なし | 観測なし | 監視子なし | — |
| 通常 2 秒のみ | 0/6 | 0/1 | 10 行 | 2.441／6.120 秒 |
| 詳細 250 ms のみ | 4/6 | 1/1 | 124 行、ネイティブ欠損 0 | 259.2／294.4 ms |
| 詳細 100 ms のみ | 6/6 | 1/1 | 282 行、ネイティブ欠損 0 | 113.9／146.7 ms |
| 通常 2 秒＋詳細 250 ms | 通常 0/6、詳細 5/6 | 通常 0/1、詳細 1/1 | 通常 10 行、詳細 124 行、詳細のネイティブ欠損 0 | 通常 2.445／6.128 秒、詳細 258.9／295.2 ms |

| 構成・監視子 | CPU 時間 | ピーク Working Set | Windows プロセス I/O 読み／書き |
|---|---:|---:|---:|
| 通常 2 秒のみ | 891 ms | 104.93 MiB | 2,138,977／11,621 bytes |
| 詳細 250 ms のみ | 1,031 ms | 115.08 MiB | 502,622／42,122 bytes |
| 詳細 100 ms のみ | 1,719 ms | 111.21 MiB | 503,038／89,693 bytes |
| 併用時の通常監視子 | 766 ms | 104.93 MiB | 2,138,851／11,666 bytes |
| 併用時の詳細 250 ms 監視子 | 1,109 ms | 115.10 MiB | 502,622／42,319 bytes |

CPU 時間と I/O は各子の開始時処理を含む。Windows のプロセス I/O カウンターは実ディスクの転送量と同じとは限らない。通常監視にバックグラウンド取得由来の約 6 秒の行間隔があった併用試験でも、詳細監視の最大は約 295 ms だった。短パルス捕捉の一回の比較であり、通常 2 秒の長パルス 0/1 も対象の発生位置と行間隔に依存する。

別の ADLX＋250 ms の試験は、基準・実行中・終了後に ADLX の VRAM 403 MB を取得し、終了後は有効 3 件だった。固定値の物理的妥当性はこの静止系の検証から判断できない。詳細監視のシステム解放判定は各試験で `WithinTolerance`（試験用 64 MiB）。すべての対象・監視子の残留は 0。実機原本は Codex ログ領域の `ram-detail-33-study-697be3` と取得時 tick による再確認 `ram-detail-33-normal-ticks-7ae34e`。

詳細 100 ms は今回の短パルスをすべて捕捉した一方、250 ms より監視子の CPU 時間は約 1.7 倍、書き込み量は約 2.1 倍だった。初回の実モデル診断には 250 ms を候補とし、約 150 ms 以下の変化を重点的に追う試験では 100 ms との比較に理由がある。捕捉率や負荷を個々の実モデルに外挿しない。

### 作業 3-4 への引き継ぎ

実モデルの PP/TG に対する監視負荷、モデル別の段階マーカー網羅性、GPU 負荷時の収集・解放判定は未検証。250 ms を最初の実モデル試験の候補とし、短時間ピークを追う必要がある場合には 100 ms と監視なし条件も比較する。RAM の急変とロード遅延の原因関係は今回の対象外。自動交互実行、ラウンド別集計、main への実装統合は別作業。
