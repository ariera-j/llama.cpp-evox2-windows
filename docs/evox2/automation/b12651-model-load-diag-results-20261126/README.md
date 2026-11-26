# 作業4-4の再集計

[EVO-X2 計測結果](../B12651-MODEL-LOAD-DIAG-RESULTS-20261126.md) の派生データを再生成する。Python 3.9 以降の標準ライブラリを使用する。

## 入力と実行方法

生ログの保全先は EVO-X2 の `C:\llama-build\_logs\codex`。子 run と Matrix のディレクトリ名は報告書の索引を参照する。原本の相対配置を維持し、次のファイルを解析機へコピーする。

- `r44-model-load-20261126/R44-*.result.json`（実機前後チェックと子・Matrix の対応）
- `matrix/<バッチ>/matrix-result.json`
- 各子ディレクトリの `result.json`、`conditions.json`、`llama-bench.json`、`stderr.log`、`ram-events.jsonl`、`ram-detail.csv`、`ram-monitor.json`、`resources.csv`、`gpu-metrics.csv`

```sh
python3 analyze.py /path/to/copied-log-root /path/to/output
```

テンソル名はリポジトリ内の [PR #30904 調査時のテンソルメタデータ](../../pr30904-preport-20261125/tensors.csv) を参照する。単体で解析する場合は `--tensors path/to/tensors.csv` を追加する。

スクリプトが JSON、診断境界・カウンター、プロセス ID と開始時刻、CPU 計時の整合、実行バイナリと終了時の安全結果を検証する。実機の状態確認は元の実行時に行う。`runs.csv` の `stderr_sha256` で読み取った stderr 原本を照合できる。

## 出力

| ファイル | 内容 |
| --- | --- |
| `runs.csv` | 受信マーカー、診断量、メモリ、リソース集約、PP/TG。両モードを収録 |
| `boundaries.csv` | 診断マーカーの単調時刻と容量報告をアンカーにした推定プロセス時刻 |
| `groups.csv`、`operations.csv` | 群および処理別の確定回数、バイト数、CPU 側の積算・最大・平均時間、ヒストグラム |
| `progress.csv`、`progress.svg` | 実測間隔で差分を取り、読み込み、イベント待ち、テンソル設定 API、その他の CPU 側 wall time の割合を表示。群末の残区間も含む |
| `waits.csv` | 各群の100 ms以上の上位8件まで。処理単位の位置と時刻を収録 |
| `input_hashes.csv` | 入力ファイルの相対パス、サイズ、SHA-256 |
| `ram_selected.csv` | 各プロセス秒の最初の詳細RAM行と、ピーク／Context 報告の前後2秒の全行 |
| `resources.csv`、`adlx.csv` | 行時刻に基づくプロセス相対タイムライン。通常監視のネイティブ／プロセスメモリ取得時刻は別列 |

単位は列名に示す。ヒストグラムの `1000_4999` は 1,000 µs 以上5,000 µs未満。空欄は欠損・対象外。期間内のチャンクに読み込みがなかったときは差分が0になる。CPU 側の `upload` は API の呼び出し時間。読み込み要求バイトはストレージの実転送量と区別する。WDDM と ADLX の GPU メモリは別指標。

`active_tensor` はその群内のテンソル通番。進捗の位置にはテンソル先頭オフセットを掲載。個別の長時間待ちではチャンク位置を別途記録する。群中のヒストグラムは最終集計。`bulk` は起動後7～45秒、`late` は各 run の Context 報告前14秒の有効な通常監視点の中央値。PP/TG クロック平均は開始マーカーから `samples_ns` の実測時間までに含まれる GPU 稼働90%以上の ADLX 観測。初回ON、各 run の起動順、アンカーの不確実性は報告書に記載した。
