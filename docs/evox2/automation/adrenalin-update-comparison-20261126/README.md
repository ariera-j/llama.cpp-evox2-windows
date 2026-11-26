# 更新後の再実行と再集計

実機に保全した `adrenalin-pre-20261126` の実プランと LocalConfig を使う。公開例を使う場合は ADLX 実行ファイルと LocalConfig のプレースホルダーを保全済みの値で置き換える。標準ツールは GitHub main の `07c33cf4b7e69057f45b9903f762b28ec221d588` に固定する。

- 計測1は `diagnostic.example.psd1` を `-OnlyRound 1 -OnlyVariant C` で選択する。実モデルを起動する検査はこのセルより後に行う。
- 計測2～6は `cli.example.psd1` を `-OnlyJob cell-2` から `-OnlyJob cell-6` まで1件ずつ選択する。
- 各セルに `-LocalConfig`、`-MaxRuns 1 -StopOnError` を付けて `-PlanOnly` で展開を確認する。実行はセルごとに SSH 接続を分ける。固有の `-RunIdPrefix` を付ける。前後の判定と中止条件は [無人計測の手順](../RUNBOOK.md#無人計測の-run-単位の停止手順) に従う。
- モデルハッシュの全ファイル読み出しは自然な初回ロードに影響し得るため、識別に必要なパス・サイズ・更新時刻の照合を先に行い、全モデルハッシュは推論終了後に採取する。

実引数は [引数一覧](arguments.json) を参照する。モデルと入力はファイル名で表示した。

## 集計

- Measure の `conditions.json` を引数・入出力識別・実行前依存照合の正本とする。Measure の `result.json`、bench のネイティブ JSON、Matrix の `matrix-result.json` から実トークン数と PP／TG を取る。リソースの集計対象は有効なサンプルとし、欠損欄は空欄で保存する。
- CLI の時間境界は過去記録に合わせ、プロセスの実終了時刻（欠損時は Measure の完了時刻）から TG と PP の報告時間を引く。該当 UTC 時間帯に入った ADLX 行の中央値を取る。Gemma の PP コア／VRAM は各区間の先頭・末尾各1/3の中央値も確認する。bench は `ram-events.jsonl` の PP/TG 実行開始の受信マーカー、2件目の Context 報告、実プロセス終了時刻を使う。
- RAM 使用・空き・コミットは `RamDetail.RunningMetrics` から採る。WDDM GPU は PID 別、ADLX VRAM はアダプター全体の値。UMA の RAM と GPU メモリは重複し得る。
- ロード診断は stderr の `llama_load_diag ` プレフィックスを除き、JSON schema、終了レコードと群別 `wall_us` を確認する。通常ログのネイティブ load とマーカー受信間隔は個別に比較する。
- 計測6の低メモリ観測は、`ram-detail.csv` の有効な連続サンプルを時刻順に並べ、空き1 GiB未満の区間ごとに先頭・末尾の時刻差を取る。単独サンプルや時間境界の通過時刻は欠損扱いとする。PP 区間と終了後を別に確認する。

## 過去の参照記録

- 計測1は [作業4-4の正常時診断](../B12651-MODEL-LOAD-DIAG-RESULTS-20261126.md)。
- 計測2と6は [Stage 1 UMA96GB](../../B12651-STAGE1-COMMON001-20261124.md)。計測6の短時間の RAM 逼迫については [作業4-1](../B12651-MODEL-LOAD-INVESTIGATION-20261126.md) も参照する。
- 計測3は [Stage 2 Vulkan FAST 64k](../../B12651-STAGE2-ROCMFP4-VULKAN-20261124.md)。
- 計測4・5は [b12651 Gemma 4 32k](../UPSTREAM-B12651-PP-TG-20261124.md)。対象 run ごとの識別情報は [参照 run CSV](reference-identity.csv) を参照する。

## 更新後データ

[更新後比較 CSV](post-update-comparison.csv) の変化率は（更新後－更新前）／更新前×100。未実行セルの更新後の値は空欄。ページングは通常監視 CSV の `PerfMonSystemStatus=Complete` 行の最大値。 [ロード診断 CSV](load-diag-comparison.csv) は前後の stderr の `group_end` にある `operations` を、群と操作名で結合した。積算値と最大値の単位は µs。終了後の RAM 判定は算出し直さず Measure の `RamDetail.SystemRecovery` を使用した。
