# b12651 Matrix のラウンド比較と監視の統合検証（作業 3-4）

実装は `codex/benchmark-matrix-b12651-20261125` の [544718493](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/5447184939aa1e60dbb9228c1c512ecf78c3d761)。基準は `94c1413dfca7452e9d00a2fc54d57f8aea7e8660`。製品ソースと既存ビルドはそのまま使用した。計測規則と来歴は [BENCHMARK-RULES.md](BENCHMARK-RULES.md)、[Matrix 移植](BENCHMARK-MATRIX-B12651.md)、[通常監視](BENCHMARK-MONITORING-B12651.md)、[RAM 詳細監視](BENCHMARK-RAM-DETAIL-B12651.md) に記録している。

## ラウンド設定

比較する Job に任意の `Comparison` を指定する。下記の識別子は Matrix のメタデータで、環境変数や実行引数を増やさない。設定なしの Job では従来の展開順を使う。通常の `Repetitions` は子 bench 内の反復、`Comparison.Runs` は各構成で別プロセスを起動する回数。

```powershell
Comparison = @{
    Group = 'monitoring'
    Base = 'A'
    References = @('B','C')
    Runs = 3
    Order = 'Explicit'
    Rounds = @(
        @{ Order = @('A','B','C','D') },
        @{ Order = @('D','C','B','A') },
        @{ Order = @('B','D','A','C') }
    )
}
```

- `ABAB` は 2 構成で各ラウンド A→B。 `ABBA` はラウンドごとに A→B、B→A を交互に使う。 `Rotate` は先頭をラウンドごとに繰り上げる。 `Explicit` は各ラウンドに全構成の順序を指定する。
- 単一ビルドの構成識別子は Variant 名。複数ビルドの Job は `BuildKey/Variant`。比較は Job／Case／ModelKey ごとに行い、`Group` は出力上で追える表示名。設定に `References` を追加すると Base 以外との同一ラウンド比較も得られる。
- 意図的に繰り返すのは展開済みの構成。元の plan で有効条件が重複している場合は従来どおり拒否する。 `PlanOnly` は予定順、ラウンド、構成、元のラウンド内位置を表示する。フィルターで基準が除かれても残った計測値は保存し、該当比較は欠損扱いとなる。 `MaxRuns` は展開後、`StopOnError` と `CooldownSeconds` は実行時に適用する。
- `matrix-comparison-rounds.csv` はラウンドと参照構成別の値・差・監視品質・時刻を、`matrix-comparison-summary.csv` は構成別の有効・失敗・欠損数、平均・中央値・最小・最大を保存する。ベンチの PP／TG と複合 PG は別指標。各比較はモデル、入力識別、Context、実トークン数、depth、ベンチ区間と反復サンプルが同じ行を使用する。P-MODE 変化、失敗、欠損、異なる生成長の結果を補完しない。予定順と実行順は既存の plan／run 出力にも追加する。
- ロード付近のマーカーの受信時間、ネイティブの `load time` が出た場合の報告値、対象プロセスの OS 経過時間、ラッパー経過時間を別列に記録する。PP/TG は子ラッパーの元データ。マーカーの受信に含まれるポーリング・出力バッファの遅延を区間の実行時間と混同しない。

## 実機条件

- Windows PowerShell 5.1、EVO-X2 の `evox2-runner` SSH。ネイティブ API が搭載 RAM 128 GiB、Radeon 8060S のドライバー登録値が Dedicated 96 GiB、Windows 可視は約 31.65 GiB。Vulkan の 114,507 MiB はデバイスの報告値で UMA 予約量とは別。P-MODE は既存の読み取り手段で Performance を確認した。
- Vulkan Stage 2 `build-s2v`、b12676、`eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`。bench の SHA-256 `576cda5ac89f2eb0b534b25ff37da78dfdc14c28e7b7d1ab5bb56f9ed7cdc8d2` はマニフェストと一致。Vulkan0 を明示した。モデルは IQ3 PLE16、81,961,816,672 bytes。
- PP8192 と TG256、depth 0、各子プロセス内 1 repetition、warmup ON、threads 4、batch 2048、ubatch 1024、GPU layers 999、CPU MoE 0、KV f16、FA ON、MTP OFF。各構成で `--progress --verbose` とフェーズ行の受信記録を同じ条件で使った。Perf Logger・RGP は OFF、実験フラグは解除した。A は ResourceMonitor、ADLX、RAM 詳細の周期監視を無効とし、ビルド検証・P-MODE・共通のログ受信を維持した。
- B は通常監視と ADLX、C は B＋250 ms、D は B＋100 ms。共通の周期設定は通常 2 秒、ADLX 2,000 ms、バックグラウンド 15 秒。詳細は前 3 秒、後 5 秒、ピーク増加閾値 64 MiB、回復許容差 128 MiB。
- 予定は A→B→C→D、D→C→B→A、B→D→A→C の 3 ラウンド。順序効果の完全均衡は意図していない。実機用 plan には検証済みの ADLX パスを指定し、実機固有の LocalConfig と共に Git 管理外に保持した。公開の [計測 plan](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5447184939aa1e60dbb9228c1c512ecf78c3d761/tools/evox2/benchmark/configs/qwen38-b12651-monitor-overhead.example.psd1) を参照する。
- 本番 plan の各 run の前後に RAM、コミット、アダプター専用メモリ、競合・残留プロセスを確認する。P-MODE は起動前と子ラッパー内で照合する。5 秒のクールダウンを使い、回復判定の僅かな超過と、次の実行を見送るためのバッチ安全止めは別の閾値で扱う。設定したコマンドと gate の結果は実機の生ログに保存する。

## 検証と結果

### 確認できた run と接続中断

Windows PowerShell 5.1.26100.10068 で変更 8 ファイルの構文・UTF-8 BOM を確認した。既存の背景分類、通常監視の部分取得・旧 CSV、RAM 詳細監視の障害・後片付け、Measure と Matrix の模擬集計を再実行した。ABAB／ABBA／3 構成の繰り上げ、明示順の重複拒否、失敗・欠損 Base、実生成長の違い、MaxRuns=11 に対する 12 件の拒否を確認した。旧 plan は 6 件を従来順に展開した。実 plan は指定の 12 件を PlanOnly で確認した。

バッチ `20261125-234629-575-b12651-monitor-overhead` の Round 1 は全 4 件が Matrix で OK。M001～M003 は取得済みの Matrix 結果、M004 の速度は取得済みの子 `result.json` のネイティブ行。M004 の run 状態と時刻は取得済みの Matrix run CSV と照合済み。

| Run | Round | 構成 | PP8192 tok/s | TG256 tok/s | 起動→Context 行 s | プロセス s | ラッパー記録 s |
|---|---:|---|---:|---:|---:|---:|---:|
| M001 | 1 | A | 630.051 | 30.038 | 173.732 | 210.999 | 216.538 |
| M002 | 1 | B | 628.671 | 30.017 | 52.246 | 88.167 | 94.170 |
| M003 | 1 | C | 627.702 | 30.020 | 51.269 | 86.716 | 101.739 |
| M004 | 1 | D | 627.100 | 30.019 | 50.627 | 85.972 | 99.744 |
| M005 | 2 | D | — | — | — | — | — |

Round 2 の M005 は Matrix の開始表示まで確認した。日本時間 2026-11-26 00:07 頃の状態確認から SSH が `No route to host` を返し、コントローラーの隣接ホスト解決も失敗した。M005 の成否、M006～M012 の実行有無、バッチの最終集計・安全チェック、切断後のプロセス残留は確認できていない。切断だけから GPU 障害・実機の停止・計測の終了は判定できない。追加 run と後続スモークは起動していない。

### Round 1 の対応比較

| 同一ラウンドの比 | ΔPP % | ΔTG % |
|---|---:|---:|
| B／A | -0.219 | -0.070 |
| C／B | -0.154 | +0.011 |
| D／B | -0.250 | +0.007 |
| D／C | -0.096 | -0.004 |

構成ごとに 1 run の観測であり、通常の変動幅や 3 ラウンド中央値、監視負荷の確定値は得られていない。C／D のラッパー時間には起動前・終了後の採取が含まれる。PP/TG に対する監視の影響はこの差だけで判定しない。通常計測は既存の運用どおりリソース 2 秒と ADLX 2,000 ms を揃え、詳細診断の初回候補は作業 3-3 に基づく 250 ms。0.3～1% の比較では同一の監視条件とラウンド設計を使い、十分な反復と変動の確認が必要。

### 取得できた監視品質と引き継ぎ

- B/C/D の通常監視は Partial、ADLX は Complete。取得済みの D では RAM、PID メモリ、システム PerfMon 各 34/34。PID GPU の使用率と local memory は有効 34/34、PID GPU の全項目取得は 26/34。背景 CPU は取得不可の期間があり、通常監視の最大間隔は 6.154 秒。
- D の ADLX は 47 行。GPU 利用率 0～100%、電力 8～123 W、VRAM は 403～80,904 MB と変動し、終了後の有効 2 行で 403 MB。PID local 最大 79.145 GiB、アダプター dedicated 最大 79.008 GiB、Vulkan モデルバッファ報告約 77,657 MiB と桁が一致する。計数範囲・時刻・単位は同一とは限らないので値の一致を要求しない。クロック・温度の行も保存した。
- C/D は RAM 詳細監視 Complete とシステム・ADLX の回復 WithinTolerance。起動前基準比ピーク増加は C 2,321.152 MiB、D 1,965.750 MiB。D は 835 行、通常とは独立して平均 112.883 ms、最大 149.957 ms、ネイティブ欠損 0。D の子 JSON で起動、GGUF 情報、テンソル配置、Context、KV／計算バッファ、Graph reserve、warmup、bench の PP／TG progress の受信を確認した。実際の内部境界は未観測。
- M001 のネイティブ `load time` 報告 188.118 秒、B/C/D の同報告 63.328～65.388 秒。M001 の PP/TG はネイティブ計測で約 13.002／8.522 秒であり、長い差は少なくとも Context 報告以前から観測できる。A は周期監視を無効にした条件のため、M001 のロード中 RAM、コミット、GPU 等は未取得。起動から終端までをそのままロード時間として扱わない。M001 の記録保持と M005 の最終状態確認を引き継ぐ。原因調査や再実行は行っていない。
- 生ログの保管先は `C:\llama-build\_logs\codex\matrix\20261125-234629-575-b12651-monitor-overhead` と親ログ `matrix-34-overhead-588fa9.log`。Round 1 の最後の子ログに残留 PID なし。SSH 回復後は新しい計測の前に元バッチ・子ログと残留プロセスを照合し、既存の停止条件に従う。
