# 作業4-1のオフライン再集計

Python 3.10 以降と標準ライブラリで、保存済みログから [モデルロード調査報告書](../B12651-MODEL-LOAD-INVESTIGATION-20261126.md) の集計に使った値を再出力する。入力は読み取り専用で、実行結果は標準出力にプレーンテキストで出る。出力には生の stderr の抜粋やタイムスタンプが含まれる。

## 入力の配置

任意の作業ディレクトリを用意し、以下の相対配置で入力を置く。生ログの原本は EVO-X2 の `C:\llama-build\_logs\codex` にある。コピー時はファイル名、ディレクトリ名、バイト列を保つ。

- `logs/<子ログディレクトリ>/` に、報告書の「3. run、バイナリ、識別情報」の表にある11件を置く。スクリプトは `logs/` 直下の `20*` を名前順に run ラベルへ割り当てるため、同じパターンの別 run は混ぜない。11件すべてに `result.json`、`ram-events.jsonl`、`stderr.log` が必要。
- M004、R34R2D-M001、R34R3D-M001、R34R3C-M001、R34R3B-M001、Vulkan CLI、ROCm CLI の7件に `resources.csv` と `gpu-metrics.csv` を置く。元の run で `ram-detail.csv` が取得されていれば併せて置く。ADLX ログのローカル時刻は元の計測と同じ JST（UTC+09:00）として扱う。
- `logs/iq2s-matvec-20261125-a38ba149/` に、`run-{02,05,11}-A1-off` と `run-{03,08,10}-A1A2-off` の各 `.stderr.log` と `.command.json` を置く。`extra.py` は `logs/iq*/*.stderr.log` を検索するため、照合結果が6件出ることを確認する。
- `manifests/build-c1r/bin/Release/evox2-build.json` と `manifests/build-s2v/bin/Release/evox2-build.json` に、実機の専用 clone 内の同名ビルドの `bin/Release/evox2-build.json` をコピーする。`manifests/` にはこの2件の JSON を置く。
- `repo/docs/evox2/iq2-s-vulkan-matvec-20261125/` に、調査の基準コミット `3bc6d1faa76c0cd0adfbbf0dbbac60f59c686885` の [実験資料](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/3bc6d1faa76c0cd0adfbbf0dbbac60f59c686885/docs/evox2/iq2-s-vulkan-matvec-20261125) から `raw-log-sha256.csv` と `logs/build-i2mv-manifest.json` を置く。

## 実行と照合

入力を配置した作業ディレクトリをカレントディレクトリにして実行する。下の `/path/to/llama.cpp-evox2-windows` は再集計資料を取得したローカルリポジトリの場所に置き換える。

```sh
scripts=/path/to/llama.cpp-evox2-windows/docs/evox2/automation/b12651-model-load-analysis-20261126
python3 -B "$scripts/analyze.py" > phases.txt
python3 -B "$scripts/resources.py" > resources.txt
python3 -B "$scripts/extra.py" > cross-checks.txt
```

| 出力 | 報告書と照合できる内容 |
| --- | --- |
| `phases.txt` | §5–6 のフェーズ受信境界。OS プロセス開始からの秒数と stderr 行番号（`秒@行番号`）、対象 run のタイマー値を出力する。 |
| `resources.txt` | §7–8 の RAM・通常監視・ADLX の時系列、メモリの極値、空き RAM が 1／0.5／0.125 GiB を下回った観測区間。 |
| `cross-checks.txt` | §3・§7–9 の補助照合。ロード中盤と Context 直前の通常監視集計、RAM 回復情報、マニフェストのソース・EXE ハッシュ、IQ2_S 6件の stderr の SHA-256・バイト数の一致と起動前時刻を出力する。 |

出力は報告書の表を組み立てるための確認値。Windows イベント調査、M005 の障害記録、ソース解析、原因仮説は報告書を参照する。
