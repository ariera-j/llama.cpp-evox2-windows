# b12651 通常リソース監視の部分取得と品質記録（作業 3-2）

> 本文は当時の検証記録。標準運用は [計測ルール](BENCHMARK-RULES.md) と [作業3-5の統合記録](BENCHMARK-INTEGRATION.md) を参照。


実装とテストは Matrix 専用ブランチ `codex/benchmark-matrix-b12651-20261125` の [実装コミット](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/78e50b838cd885c32cfb34da817f80c8e6c75df2) に置く。作業開始時の専用ブランチは `6afa0c1a0a82b7aa5e38dd2f3cff9ef2fd65dd22`、`main` は `605d2f7e9d5b64acde4ef040167d76aaa2b97a3e`。運用条件は [BENCHMARK-RULES.md](BENCHMARK-RULES.md) に従う。

## 変更前と変更後

旧モニターは `GetPerformanceInfo()` の失敗で監視を停止した。PID つきの `Get-Counter` とシステム用フォールバックの両方に失敗すると行全体をスキップした。有効なカウンターがない場合の 0 と実測の 0 が同じ列に出る経路があった。旧 `GpuProcessCountersAvailable` は PID を含む問い合わせが例外なく返ったことを示し、各項目の有効性は表さなかった。Measure 系は CSV の行数を数え、Matrix はその件数を引き継いだ。

| 取得元 | 保存する項目と失敗時の扱い |
|---|---|
| `GetPerformanceInfo()` | 物理総容量、利用可能 RAM、使用量（総容量から利用可能 RAM を引いた値）、コミット量・上限・割合、System Cache、起動後のコミットピーク。同じ構造体のページ数に PageSize を掛け、GiB は 2³⁰ バイトで換算。割合は同一スナップショットの上限が正のときに計算。API が失敗した場合はこの取得元の列を空欄にする。 |
| `Get-Process` | Working Set、Private Memory、Virtual Memory を対象 PID から通常サンプルごとに読み取る。読めた項目を個別に保存する。PID がカウンター取得中に終了した場合はその採集中の行を捨てて終了し、以前に保存した行を保持する。 |
| `Get-Counter` | システム CPU、ディスク使用率・読み書き、ページング、比較用のコミット値、GPU アダプター・対象 PID の各メモリ、PID の GPU Engine。Windows が有効とした数値を使う。非終端エラーと一緒に返った有効値を残し、システムの有効値がなくエラーが出た場合には、PID が生きている間にシステム専用問い合わせを最大 1 回試す。次のサンプルで取得が回復すれば通常どおり保存する。 |
| バックグラウンド | 対象プロセス一覧と読める CPU 時間は `Get-Process`、不足時にだけ PerfProc CIM を試す。拒否されてもプロセス一覧と既知の CPU 値を保存する。最初のスナップショットでは CPU 差分は未観測。比較に使える値がないときは CPU 統計・負荷判定を欠損とする。 |
| ADLX | 既存実行ファイルの CSV と対応可否・API 戻り値を使う。未対応または取得に失敗した getter の空欄と、API が返した 0 を保持する。固定値・全件 0 は項目名を記録し、アイドル時の値や SSH の実測精度はこの情報だけで判定しない。 |

`CommitPeakSinceBoot_GiB` はシステム全体で再起動後に観測されたコミットピーク。通常 run 中に観測した物理 RAM のピークは `UsedRAM_GiB` の時系列で評価する。Windows API の `SystemCache` は standby list と system working set の合計。特定のモデルや GGUF ファイルによるキャッシュ量はこの値から特定できない。PerfMon との比較には取得時刻と定義による差を許容する。 [Microsoft PERFORMANCE_INFORMATION](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-performance_information)

PerfMon のステータスは PDH の有効データ・新規データを受理する。負値・非有限値と、個別 GPU エンジンで 100.5% を超える値を除き、複数エンジンの合計は 100% を超え得る。警告は取得元ごとに初回のみ出し、行にエラー情報と棄却件数を残す。ADLX の判定は SDK の成功コードとメトリクスごとの支持情報に基づく。 [Microsoft PDH ステータス](https://learn.microsoft.com/en-us/windows/win32/perfctrs/checking-pdh-interface-return-values) · [AMD ADLX 成功判定](https://gpuopen.com/manuals/adlx/adlx-sdk-references/adlx-types/adlxmacro/)

## 出力と互換性

- `resources.csv` は先頭 53 列の名称・順序・単位を維持し、17 列を追加した。追加列は `ResourceSchemaVersion=2`、UTC 時刻、物理総容量、System Cache、コミットピーク、PerfMon 比較値、取得元ごとの状態・エラー、PerfMon 棄却件数。既存 `Committed*` と `CommitLimit_GiB` は新版ではネイティブ値。 `GpuProcessCountersAvailable` は対象 PID の GPU 指標に有効値が一つ以上ある場合に True。
- 実測のゼロは数値 0、取得できない値は CSV の空欄と JSON の `null`。件数は 0 を表示できる。最初の `SampleIntervalSecondsActual` は空欄。 `CounterCollectionMilliseconds` は通常収集分、任意のバックグラウンド収集時間は `BackgroundCollectionMilliseconds` に記録する。旧 CSV は変更せず、旧ゼロを推測で欠損へ変えない。
- `Measure-LlamaBench.ps1` と `Measure-LlamaCli.ps1` は結果 JSON に `MonitoringQuality` を追加する。実行ユーザー・セッション、要求・起動・終了、ログとエラー、行数、取得元別の状態件数、主要指標ごとの有効・欠損件数と最小・最大・平均、間隔を記録する。統計は有効値だけを使う。バックグラウンドの開始・終了スナップショットと差分は既存の JSON に残る。
- `summary.csv`、`matrix-runs.csv`、`matrix-results.csv` に監視の状態を追加した。Matrix の run 側にも従来のサンプル件数を追加し、JSON にも同じ要約を出す。詳細は各子の `result.json` にある。計測ツールのファイル名と既存列を維持し、監視の状態だけで workload の成否を変更しない。
- `Complete` は対象の項目が取得できた状態で、ADLX では対応なしと確認された項目を除く。 `Partial` は有効値はあるが欠損・失敗等を含む状態。 `Unavailable` は起動失敗または有効データなし、`NotRequested` は監視要求なし、`LegacyUnqualified` は旧行の 0 に取得元の裏付けがない形式。ADLX の Complete は値の物理的妥当性を保証する判定ではない。

## 検証結果

PowerShell 5.1.26100.10068 で変更 9 ファイルの構文・UTF-8 BOM・予約変数、モジュール読み込み、既存 plan の 6 件の PlanOnly を確認した。旧 53 列の実機ログ 22 行を読み、新 70 列の先頭 53 列と一致することを確認した。

- `Test-MonitoringQuality.ps1` は全成功、PID だけの失敗、全 PerfMon 失敗、一部値と非終端エラー、正常な 0、無効値、一時失敗からの復帰、対象 PID 終了の競合、旧 CSV、ADLX の欠損と固定値を検証した。
- `Test-BackgroundActivityClassification.ps1` は既存の分類テストに CIM 拒否を追加し、他の経路で取得済みの一覧と実測 0 が保たれることを確認した。`Test-ResourceMonitorCadence.ps1` は今回の実機 CSV で合格した。
- `Test-MonitoringQualityMatrix.ps1` は実 Measure の集計・JSON・主要 CSV 列の式を合成ログに対して評価した。現行の引数宣言を使った子テストデータを Matrix に通し、監視が部分取得や取得不可でも workload の OK を維持し、CSV・JSON に品質を保存することを確認した。

### EVO-X2 SSH での非推論検証

`evox2-runner` の SSH セッション ID 0 で、約 23 秒の PowerShell 待機プロセスだけを対象に既存設定（通常 2 秒、ADLX 2,000 ms、詳細バックグラウンド 15 秒）で採取した。

| 項目 | 有効サンプル・結果 |
|---|---|
| ネイティブ物理 RAM、コミット、System Cache、プロセスメモリ | 各 9/9。ネイティブのコミット量は平均 8.653 GiB、上限 127.647 GiB、System Cache 平均 16.065 GiB。 |
| システム PerfMon | CPU、ディスク、ページング、アダプターメモリ、比較用コミット値は各 9/9。PerfMon のコミット量は平均 8.643 GiB、上限 127.647 GiB。CPU、ディスク、ページングで実測 0 も観測。 |
| PID GPU メモリと GPU Engine | 各 0/9。非 GPU プロセスの PID カウンター行がなく、空欄／null。GPU 利用時の SSH 可用性は未検証。 |
| バックグラウンド | 1 回、5,098.6 ms。一部 PerfProc CIM がアクセス拒否。観測されたプロセス名とエラーは保存。CPU 差分に必要な 2 回目の時点は対象の存続時間外。 |
| 通常監視間隔・収集時間 | 9 行、間隔 8 件で平均 2.498 秒、最小 1.794 秒、最大 6.117 秒。通常収集 1,013～1,255 ms、平均 1,046 ms。 |
| ADLX | 12 行、API 結果 0 が 12 件。GPU 使用率、クロック、VRAM クロック、温度、電力、VRAM が各 12/12。hotspot と total board power は API が非対応と報告し各 0/12。取得間隔平均 2.001 秒、範囲 1.995～2.015 秒。 |
| ADLX の固定値と終了状態 | 使用率 0%、VRAM 403 MB が全サンプルで固定。静止系の非推論検証なので GPU 負荷時や対話セッションとの違いは未判定。対象、通常監視、ADLX の残留 PID は 0。 |

実機原本は Codex ログ領域の `resource-32-live-3f11411ed4d94782b52b6790889a9d53`。全 Get-Counter 拒否時のネイティブ保存は模擬拒否で確認した。SSH での GPU 負荷、対話セッション、実モデルを使った Measure と Matrix、監視による性能影響は未検証。管理者権限・ACL・保護設定の変更は不要だった。

## 作業 3-3 への引き継ぎ

起動前・終了後のシステムメモリ監視、解放の判定、軽量な詳細 RAM 監視、モデルロードと初回 eval 等の時刻対応付けは次の作業で扱う。今回は PID の存続区間を対象にした。通常監視の取得元・欠損情報と UTC 列を後続の時系列に引き継ぎ、バックグラウンド CIM が間隔を延ばし得ることと UMA の計数重複を考慮する。
