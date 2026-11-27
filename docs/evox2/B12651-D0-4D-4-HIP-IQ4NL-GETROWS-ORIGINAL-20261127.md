# B12651 D0-4D-4 host配置制限修正版のOriginal回帰検証

2026-11-27 JST。**合格。** UMA 96 GiBで承認されたOriginal 4k短文推論を1回行い、joined PLEのCPU配置復帰をローダーのログと実モデルバッファで確認した。モデルロード・context生成・固定入力への応答が成功し、CLI終了コード0、Measureは `OK`。ロード中に一時的な物理RAM逼迫を観測した。commit枯渇イベント、ROCmエラー、資源回復の異常はなかった。

## 来歴と実行条件

- 実行時の `experiment/hip-iq4nl-ple160` は `f85ae71046253b7e2b16170b90e1550f6cd8166e`。GitHub、登録worktree `C:\llama-build\automation\w55`、追跡先が一致。作業ツリーはクリーン。文書と共通ツールは固定main `891e2605fbc0798228ffad2a69dd618f6cdab216`。
- `build-rh\bin\Release\llama-cli.exe`、b12709／`e199e5f43`。ビルド元 `e199e5f4319731071199d84f4f2e571fcaa7d413`、修正ソース `86e343cd4bfa0110f49e430d59081725af976e01`。CLI SHA-256 `538a12f93ed12ab2a639640d87aeb78582acca4d9d9c086fe5d6f9220f7c01de`。 `BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。HIP DLLは `2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f`、マニフェストは `8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116` と照合。 [build-rhの来歴](B12651-D0-4D-2A-HIP-IQ4NL-GETROWS-20261127.md)
- Radeon 8060S／gfx1151、ROCm0、Windows 11、UMA 96 GiB、Adrenalin 26.11.2、TheRock 10.0.0、P-MODE Performance。関連環境の上書きなし。
- `UnslothOriginal` は旧IQ3 UD-IQ3_XXSのjoined PLE。サイズ10,946,624／49,567,921,344／32,382,955,968 byteの3シャードと各更新UTCを前回の予算記録に照合。
- D0-4C Originalの保存済みplanの設定を再利用し、単一条件を標準 `Measure-LlamaCli.ps1` で実行した。DryRunと実際の `conditions.json` でCLIのパス以外のコマンド、モデル識別、通常・詳細監視設定が前回と一致。通常監視2秒、ADLX 2,000 ms、RAM詳細250 ms、詳細回復許容差128 MiB。追加の現場監視は標準ログを読み、停止時に対象PID・開始時刻・実行パスを照合する方式。 [前回Originalの条件・失敗記録](B12651-D0-4C-ORIGINAL-HIP-IQ4NL-GETROWS-20261127.md)

```text
C:\llama-build\automation\w55\build-rh\bin\Release\llama-cli.exe -m C:\llama\models\unsloth_Qwen3.8-Flash-Next-GGUF\UD-IQ3_XXS\UD-IQ3_XXS\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf -c 4096 -ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa auto -lv 5 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0.2 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none -n 32 -p "Reply with the word OK." --device ROCm0 --threads-batch 4
```

## モデル配置と短文応答

`stderr.log` 2862行の `done_getting_tensors` は、`per_layer_token_embd.weight`（IQ4_NL）に対する優先候補 `ROCm_Host` の拒否と、`CPU` の選択を記録した。2865–2868行に49/49層のGPU offloadと3種類の実モデルバッファを確認した。前回はROCm_Hostに移っていたjoined PLE相当の容量がCPUに戻った。

| モデルバッファ（MiB） | 従来4k UMA64 | 従来64k UMA96 | D0-4C失敗 4k UMA96 | 今回 4k UMA96 |
| --- | ---: | ---: | ---: | ---: |
| CPU | 27,465.95 | 27,465.95 | 行なし | **27,465.95** |
| ROCm0 | 50,191.17 | 50,191.17 | 50,191.17 | **50,191.17** |
| ROCm_Host | 497.31 | 497.31 | 27,963.27 | **497.31** |
| GPU offload | 49/49 | 49/49 | 49/49（ロード中） | 49/49 |

今回のROCm0 KVは96＋24 MiB、recurrent stateは112.57 MiB。computeはROCm0 413.52 MiB、ROCm_Host 52.31 MiB。 `OK` と応答し、18入力／2生成トークンを処理した。PP 31.60／TG 25.85 tok/sは参考値。CLIは12:40:15.831 → 12:41:18.600 JSTの62.769秒。Measureの所要時間は81.104秒。 [従来計測の条件](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/B12651-STAGE1-COMMON001-20261124.md)

## ロードとメモリ時系列

CLI内時刻でtensorロード開始は0.432秒、CPU選択は0.930秒、割当後のバッファ報告は2.095秒、context構築開始は58.739秒、warmup開始は59.181秒。tensorロードからcontext構築まで58.307秒。詳細監視のマーカー受信間隔は58.211秒。割当後のバッファ報告では、直前の割当の安全性を保証できない。

以下は `ram-detail.csv` の有効サンプルの時刻をOS上のCLI開始で相対化した値。

| CLI開始から | 観測 |
| --- | --- |
| 35.411秒 | 今回の実行中commit最大89.642 GiB、上限127.647 GiB |
| 45.671～52.540秒 | 空き1 GiB未満を20サンプル、6区間で観測 |
| 49.768秒 | 最小物理空き **3.691 MiB** |
| 52.793秒 | 空きが1 GiB以上へ戻った最初の観測。以降、実行中に1 GiB未満の観測なし |
| context構築開始のマーカー以降 | 最小空き5.568 GiB、commit最大87.520 GiB、空き1 GiB未満0件 |

各区間は連続する閾値未満サンプルの最初と最後で定義する。区間開始～終了秒と件数は45.671～45.938（2）、46.697～47.201（3）、48.227～50.773（11）、51.278（1）、51.782～52.034（2）、52.540（1）。最長観測幅は **2.546秒**。観測の間の状態は未計測。RAM詳細全体は278サンプル、ネイティブ欠損0、実測平均254.938 ms。

| 指標 | 今回の観測値 |
| --- | --- |
| Working Set／Private／Virtual最大 | 24.582／77.819／337.578 GiB |
| System Cache最大 | 26.160 GiB |
| WDDM Dedicated／Shared最大 | アダプター50.493／0.593 GiB、対象PID 50.032／0.558 GiB |
| ADLX VRAM最大 | 51,705（`gpu_vram_mb` のログ単位）、36サンプル、終了0 |
| Pages Input／Page Reads／Page Faults最大 | 898,226.1／2,220.4／1,358,967.6 件/秒 |
| ディスク読取／書込最大 | 3,479.35／481.61 MiB/s |

ページングとディスクI/Oはシステムカウンターであり、読み込み元・ページファイルへの帰属は未確認。UMAの内部バッファ、WDDM、ADLX、物理RAMには重複する計数がある。

## 過去との比較

| Originalの参照run | 結果 | 物理空き最小 | 空き1 GiB未満 | 観測されたcommit最大 |
| --- | --- | ---: | --- | ---: |
| b12671 4k、UMA64 | 応答 `OK`、終了0 | 25.915 GiB | 通常監視で0件 | 92.094 GiB |
| b12671 64k、UMA96 | 日本語要約、終了0 | 0.492 GiB | ロード中2件 | 90.928 GiB |
| b12696 D0-4C 4k、UMA96 | ROCm異常終了、context未到達 | 0.621 MiB | 39件、最長9.726秒 | 85.566 GiB（250 msサンプル） |
| b12709 D0-4D-4 4k、UMA96 | 応答 `OK`、終了0 | 3.691 MiB | 20件、最長2.546秒 | 89.642 GiB（250 ms設定） |

b12696失敗時は瞬時サンプル間でOS起動以降のcommit高水位が127.613 GiBへ上昇し、資源枯渇イベントも発生した。今回その高水位は前後同値で、今回の観測最大とは別の指標。b12671の4kと64kは通常監視の値で、UMA・context・計測頻度の差があるため参考比較。今回、短時間の極端な物理RAM低下は残ったが、context生成前に逼迫を脱し、前回の異常終了は再発しなかった。 [従来4k・64k](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/B12651-STAGE1-COMMON001-20261124.md) · [D0-4C失敗時](B12651-D0-4C-ORIGINAL-HIP-IQ4NL-GETROWS-20261127.md)

## 安全監査

| 項目 | 開始 → 終了または結果 |
| --- | --- |
| 物理空きRAM | 27.080 → 28.038 GiB。開始は直近の約27 GiB水準、前後とも既存の16 GiBゲート以上 |
| 現在commit | 8.273 → 8.250 GiB、増分 −0.024 GiB。上限127.647 GiB |
| WDDM Dedicated／Shared | 前後とも0.461／0.035 GiB。Dedicated増分0 |
| 詳細RAM／GPU回復 | 両方 `WithinTolerance`。RAM使用量とcommitは開始基準より減少。ADLX VRAMは開始／最終とも472（ログ単位）、事後有効3サンプル |
| P-MODE／OS | 前後ともPerformance。起動時刻 `2026-11-26T11:45:51.5000000Z` で一致 |
| イベント | D0-4D-3終了以降の開始前監査、および今回の差分監査はいずれもSystem 69929 → 69929、Application 44252 → 44252。新規イベント0件 |
| 実行中監視と残留 | CLIの識別を確認して監視し、停止シグナルなしで終了。CLI、通常・詳細RAM監視、監督、実行中監視の確認PIDおよびADLX等のプロセス名に残留なし |

通常監視25サンプルのRAM・対象プロセス・システムPerfMon・PID GPUは全件 `Complete`。補助のバックグラウンドCPU比較にアクセス拒否があり、通常監視の総合表示は `Partial`。詳細RAMとADLXは `Complete`。再試行は0回。

## D0採用判断とログ

**host配置制限を含むD0修正版を採用候補とする。** D0-4D-2Bの対応判定6件・数値比較5件、D0-4D-3のPLE16配置維持、今回のOriginal CPU配置復帰を確認した。UMA 96 GiBでのOriginal実ロードには従来同様の一時的な物理RAM逼迫が残る。修正版での長文性能、他設定の配置、NVIDIA実機は未検証。製品統合は別承認。 [対応判定と数値テスト](B12651-D0-4D-2B-HIP-IQ4NL-GETROWS-20261127.md) · [PLE16実モデル](B12651-D0-4D-3-HIP-IQ4NL-GETROWS-20261127.md)

生ログは実機 `C:\llama-build\_logs\codex` の `20261127-124003-562-cli-rocm-b12709-ctx4096-92d9a2c6c232`。コマンドは `conditions.json`、実行結果は `result.json`、配置根拠は `stderr.log`、時系列は `ram-detail.csv`、`ram-events.jsonl`、`resources.csv`、`gpu-metrics.csv`。DryRun、開始・終了ゲート、イベント差分、実行中監視と残留確認は `d0-4d-4-original-audit-20261127`。旧runは同じログルートの `20261124-165852-574-cli-rocm-b12671-ctx4096-a54242f85d44`、`20261124-201244-632-cli-rocm-b12671-ctx65536-88eafc6178e1`、`20261127-093643-307-cli-rocm-b12696-ctx4096-b82ed489f63c`。
