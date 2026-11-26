# B12651 D0-4A — ROCm IQ3 PLE16 64kの初回同条件比較

2026-11-27 JST。Adrenalin更新後の計測6と、IQ4_NL GET_ROWSを修正したビルドでの1回を比較した。D0-3では独立CPUモデルバッファの消失とROCm0バッファの増加を集計で確認済み。 [D0-3の配置記録](B12651-D0-3-HIP-IQ4NL-GETROWS-20261127.md) · [修正前の計測6](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/ADRENALIN-UPDATE-COMPARISON-20261126.md#更新後)

## 来歴と実行条件

| 項目 | 照合結果 |
| --- | --- |
| 文書・使用した標準ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216`。Matrix、Measure、使用するモジュールを実験ブランチと照合 |
| 製品基準／修正版のビルド元 | `9ae819d5be4fe9861d2aa8547983aed801c437ac`／`044be892e12bffdfd06cfb698bf55e54582ae63a` |
| 実験ブランチと実行時HEAD | `experiment/hip-iq4nl-ple160`、`8f5793ba7bd440884ddc25808bb970b374dba15f`。GitHub、worktree、追跡先が一致。ビルド以降の差分は記録と実験固有のPowerShell監督ツール |
| 修正版CLI | b12696、Clang 23.0.0、`w55\build-rm\bin\Release\llama-cli.exe`、SHA-256 `98da309636095a3be2d28b26fb19194968607b54b9cc042565875774a9dda6bf` |
| HIPとruntime | `BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。HIP DLL SHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c`、マニフェスト SHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`。TheRock 10.0.0、Release、gfx1151 |
| 実機 | Windows 11、ROCm0 Radeon 8060S、UMA 96 GiB、Adrenalin 26.11.2（32.0.32029.2010）、Performance。デバイスを単独列挙し、CMakeのgfx1151ターゲットとD0-2B/D0-3の実機記録を照合。GPU可視性やバックエンドの環境上書きなし |
| モデル | `UnslothPle16`、`Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf` 単一ファイル。81,961,816,672 byte、mtime `2026-09-16T00:32:20.7663142Z`。既存SHA-256 `ef7d1a61dcf531e62b4bc2b570d4ea58847d7c5594aa138ae2c501f68f0cbc7b`。今回の照合はパス・サイズ・mtimeで行った |
| 入力 | `nlp-survey-ch3-d7-b1.txt`、304,931 byte、SHA-256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`。計測6と一致 |
| 監視 | ResourceMonitor 2秒、ADLX 2000 ms、RAM詳細 250 ms。RAM／GPU回復許容差128 MiB、RAM詳細前3秒・後5秒、Matrix cooldown 5秒 |

計測6が参照した設定ディレクトリ `adrenalin-pre-20261126` の `CLI.psd1` と `cli-local.psd1` を実験の監査ディレクトリに複製した。変更はplan名と `Rocm54` キーが解決するビンディレクトリ（`w54` → `w55`）。実行IDを `D04A-M001` とした。PlanOnlyで以下の1件だけが展開され、DryRunでCLIパス以外のコマンドの一致を確認した。スレッドバッチ4は両ビルド共通の既定動作。warmup有効、`load_mode = none`、GPU診断・Perf Logger・RGPなし。

```powershell
Set-Location 'C:\llama-build\automation\w55'
$log = 'C:\llama-build\_logs\codex\d0-4a-audit-20261127'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan "$log\CLI.psd1" -LocalConfig "$log\cli-local.psd1" -OnlyJob cell-6 -MaxRuns 1 -RunIdPrefix D04A -StopOnError
```

展開されたCLIコマンド。

```powershell
C:\llama-build\automation\w55\build-rm\bin\Release\llama-cli.exe -m C:\llama\models\unsloth_Qwen3.8-Flash-Next-GGUF\UD-IQ3_XXS\UD-IQ3_XXS\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf -c 65536 -ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa auto -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none -n 256 -f C:\llama\inputs\qwen38\nlp-survey-paper-japanese\long-input-abstract-out\data\nlp-survey-ch3-d7-b1.txt --seed 1234 --ctx-checkpoints 0 --no-display-prompt
```

開始前の容量見積もりはD0-3のROCm0モデル77,657.12 MiBと計測6のGPU KV、recurrent state、computeを足した80,135.50 MiB（78.26 GiB）。UMA 96 GiBで既知の内部割当を収容でき、約17.74 GiBの差に一時割当などが入る。実測された修正版の対応値は80,143.31 MiB。これらはライブラリ内訳の見積もりで、WDDM値やWindows可視物理RAMと重複する。開始ゲートでは空き26.74 GiB、commit 8.12／127.65 GiB、WDDM Dedicated 0.461 GiB、Shared 0.072 GiB、GPU Engineカウンター合計0%を確認した。

## モデル配置とメモリ

| CLIログの内訳 | 計測6 | D0-4A |
| --- | ---: | ---: |
| GPU層 | 49/49 | 49/49 |
| 独立CPUモデル | 27,465.94 MiB | 行なし |
| CPU_Mappedモデル | 行なし | 行なし |
| ROCm0モデル | 50,191.17 MiB | 77,657.12 MiB |
| ROCm_Hostモデル | 497.31 MiB | 497.31 MiB |
| ROCm0 KV（2バッファ、K/V f16） | 1,536.00 + 384.00 MiB | 1,536.00 + 384.00 MiB |
| ROCm0 recurrent state | 112.57 MiB | 112.57 MiB |
| ROCm0 compute | 445.81 MiB | 453.62 MiB |
| ROCm_Host compute | 91.94 MiB | 73.19 MiB |
| ROCm_Host output | 0.95 MiB | 0.95 MiB |

モデルのパス、サイズ、mtime、GPU layers 999、CPU MoE 0、`load_tensors: ... model buffer size` の定義は両runで一致。計測6のstderr 167–169行の3バッファに対し、修正版の167–168行では独立CPUの行が消え、ROCm0が27,465.95 MiB増えた。D0-3で確定した16個のIQ4_NL headの容量27,465.94 MiBと表示丸め内で一致。ROCm_Hostは同値だった。全16 headのROCm0配置を支持する集計上の根拠で、個々の実バッファ名は未確認。

| 物理メモリ・I/O観測値 | 計測6 | D0-4A |
| --- | ---: | ---: |
| Windows可視物理RAM | 31.647 GiB | 31.647 GiB |
| テンソルロード中の最小空きRAM | **14.117 MiB** | **25,119.270 MiB（24.5305 GiB）** |
| 実行中の空き1 GiB未満 | 29サンプル、5区間 | 0サンプル、観測区間なし |
| 最長観測区間 | 3.303208秒、14サンプル | 観測なし |
| PP中の最小空きRAM | 3.287 GiB | 25.129 GiB |
| TG中の最小空きRAM | 4.110 GiB | 25.142 GiB |
| 物理使用RAM最大 | 31.633 GiB | 7.117 GiB |
| commit最大／limit | 89.100231／127.647282 GiB | 89.495743／127.647282 GiB |
| Working Set最大 | 24.905 GiB | 0.958 GiB |
| Private Memory最大 | 77.796 GiB | 77.779 GiB |
| Virtual Memory最大 | 337.518 GiB | 337.517 GiB |
| System Cache最大 | 24.930 GiB | 25.747 GiB |
| WDDMアダプターDedicated／Sharedの各ピーク | 52.425／0.732 GiB | 79.315／0.714 GiB |
| WDDM対象PID Dedicated／Sharedの各ピーク | 51.969／0.661 GiB | 78.854／0.642 GiB |
| ADLX VRAMピーク（生ログの `gpu_vram_mb`） | 53,683 MB | 81,218 MB |
| Pages Input／Page Reads／Page Faultsの各ピーク（件/秒） | 539,834.5／3,279.2／836,168.4 | 566,551.0／2,053.6／678,754.1 |
| ディスク読取り／書込みの各ピーク | 2,108.79／1,344.21 MiB/s | 2,210.61／3.45 MiB/s |

250 msのRAM詳細の有効サンプルから求めた。修正前の5区間はCLI起動基準で47.337–47.842、48.348–48.852、49.862（単独）、52.138–55.441、57.475–59.272秒で、すべてテンソルロード中。区間長は最初と最後のサンプルの差。未観測の時間は含めない。修正版ではPP中も含め、全実行中に空き1 GiB未満を観測しなかった。物理RAMの逼迫はこのrunで大幅に軽減した一方、commitピークは0.396 GiB増えた。ページングやディスクI/Oはシステムカウンターで、CPU/GPU間の転送量は今回未計測。内部バッファ、WDDM、ADLX、物理RAMはUMA上で重複し、ピーク時刻も異なる。

## 時系列と性能

| CLI起動を起点とした境界 | 計測6（秒） | D0-4A（秒） |
| --- | ---: | ---: |
| テンソルロード開始 | 0.413 | 0.419 |
| コンテキスト構築開始（ロード完了の目安） | 60.081 | 44.291 |
| テンソルロード開始からコンテキストまで | **59.668** | **43.872** |
| warmup開始 | 60.254 | 44.420 |
| warmup後の `new prompt` 報告 | 61.009 | 45.086 |
| PP開始の推定境界 | 63.867 | 45.548 |
| TG開始の推定境界 | 215.205 | 196.726 |
| ネイティブPP/TGタイミング報告 | 223.869 | 207.956 |
| CLI実終了 | 226.727 | 208.418 |

ロード、context、warmup、最初のpromptはstderrの相対時刻。CSVのPP/TG区間は既存の計測6と同じく、OSが記録したCLI終了時刻から報告TG時間とPP時間を逆算した近似境界。終了処理やログ時計とのずれを含むため、PP/TGの開始時刻そのものは確定していない。RAM詳細CSVは両runをCLI起動からの経過秒に正規化し、運用ツールの元のphaseと解析用phase、有効性、元のbyte数を保持した。RAM詳細は927／855サンプル、ネイティブ欠損は0／0、実測平均間隔は253.42／253.36 ms。 [派生CSV](d0-4a-20261127/ram-timeline.csv) · [解析コード](d0-4a-20261127/compare_measure.py)

| 項目 | 計測6 | D0-4A | 差 |
| --- | ---: | ---: | ---: |
| 入力／生成トークン | 61,789／256 | 61,789／256 | 一致 |
| PP | 408.28 tok/s | 408.72 tok/s | +0.44（+0.11%） |
| TG | 22.13 tok/s | 21.81 tok/s | −0.32（−1.45%） |
| PP時間 | 151.338310秒 | 151.177900秒 | −0.160410秒 |
| TG時間 | 11.521480秒 | 11.691790秒 | +0.170310秒 |
| CLIプロセス時間 | 226.726806秒 | 208.418042秒 | −18.308764秒 |
| Measure時間 | 244.929秒 | 227.085秒 | −17.844秒 |

| ADLX区間中央値（計測6 → D0-4A） | PP | TG |
| --- | ---: | ---: |
| 有効サンプル数 | 76 → 75 | 5 → 6 |
| GPU利用率 | 100 → 100% | 94 → 93.5% |
| GPUクロック | 2,881 → 2,883 MHz | 2,890 → 2,897.5 MHz |
| VRAMクロック | 980 → 980 MHz | 1,000 → 993 MHz |
| GPU電力 | 120 → 119 W | 108 → 87 W |
| GPU温度 | 78 → 70 °C | 67 → 61 °C |

出力は評価表現辞書と文書分類を含む、入力に沿った日本語の要約。両runとも256生成トークンで上限に達した。正規化stdoutの差はビルドバナー1行だけで、応答本文は一致した。本文のUTF-8 SHA-256は両runで `af77a85a5f18c7cefa487ee9ca4e05d08e369e23263eb33b2dac6745b5d7cbe6`。CLI stderrにNaN/Inf、GPUエラー、異常終了の報告はなかった。

## 終了監査

| 確認項目 | D0-4A |
| --- | --- |
| ネイティブCLI | JST 00:44:47.996 → 00:48:16.414、終了コード0（`System.Diagnostics.Process.ExitCode`） |
| 標準ツール／SSH | Measure `OK`、Matrix `Complete=True`、1/1 OK、`StoppedEarly=False`、SSH 0 |
| 詳細回復の初回判定 | RAM／GPUとも `WithinTolerance`。RAMの基準から最終サンプルまでの空き差 −13.84 MiB、ADLX 472 → 472 MB、許容差128 MiB |
| 終了ゲート | 空き26.605 GiB、commit増加 +0.151 GiB、WDDM Dedicated増加0 GiB。標準Matrixゲートも前後 `Issue=null` |
| P-MODEとOS | 前後ともPerformance。起動時刻は `2026-11-26T11:45:51.5000000Z` で一致 |
| イベント | System 69911 → 69911、Application 44072 → 44072。読取り経路確認済み、差分0件、重大イベントなし |
| 残留 | CLI、通常・RAM詳細監視、Matrixの既知PIDは消滅。ADLXも終了0で名前照合に残留なし |
| 監視品質 | RAM詳細・ADLXは `Complete`。通常監視83サンプルはネイティブRAM、プロセスメモリ、システムPerfMon全件 `Complete`。総合 `Partial` はPID GPUカウンター27件が `Partial`（56件 `Complete`）、バックグラウンドCPU比較も初回以降9件で `None`。欠損を0として集計していない |

**D0-4A合格。** 64k推論の正常動作と終了監査を確認した。ロード区間は15.796秒短かった。PP/TGの速度差、ロード時間、I/Oは各1回の観測であり、温度、OS稼働時間、ファイルキャッシュと同時I/Oの状態は制御していない。同条件反復でPP/TGとロード区間を分けて確認する余地がある。128k以上、他モデル・バックエンド、個別headの実バッファ名、転送量は未検証。今回の実行はこの1回で終了した。

## 生ログと再集計

すべて `C:\llama-build\_logs\codex` 配下。

- 計測6 Measure `20261126-214709-314-cli-rocm-b12696-ctx65536-308cf3ff8e36`、Matrix `matrix\20261126-214626-238-adrenalin-pre-cli-20261126`。修正前CLI b12696のビルド元は `20f48bfe162d8d886b9f5fea7ad6d7df91eb3266`、バイナリSHA-256は `ac1703d17e1be08ff8d3f7ce643a720f89fa40b108da663dc5922362a285752f`。
- D0-4A Measure `20261127-004435-749-cli-rocm-b12696-ctx65536-a32734523471`、Matrix `matrix\20261127-004352-653-d0-4a-iq3-ple16-64k`。
- 設定と開始／終了監査 `d0-4a-audit-20261127`。実行時に保存された新旧Matrix planはrun ID以外の展開条件、選択、RunnerSettingsが一致した。ADLXモニターSHA-256は両runで `8c5da580c05d8f7c2477865a48aa1b2cd24cbabd926dc599a6f6a1580dbcc487`。

```text
python d0-4a-20261127/compare_measure.py <計測6 Measureログ先> <D0-4A Measureログ先> ram-timeline.csv
```
