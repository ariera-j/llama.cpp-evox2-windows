# B12651 D0-4B — ROCm IQ3 PLE16の128k／256k比較

2026-11-27 JST。同じ修正版ビルドの64k実測を基準に、入力長を変えたときのPP/TG、モデルロードとメモリ使用量を比較した。 [D0-4A 64k](B12651-D0-4A-HIP-IQ4NL-GETROWS-20261127.md)

## 条件と来歴

- 実行時の実験ブランチ `experiment/hip-iq4nl-ple160` は `f37218ffd9c25f6f4b29b9dce54a2c4a45be3b1c`。GitHubと実機worktree、追跡先を照合。固定main `891e2605fbc0798228ffad2a69dd618f6cdab216` の標準Matrix・Measureと関連モジュールを使用。
- 修正版 b12696、ビルド元 `044be892e12bffdfd06cfb698bf55e54582ae63a`。CLI SHA-256 `98da309636095a3be2d28b26fb19194968607b54b9cc042565875774a9dda6bf`、HIP DLL SHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c`、マニフェストSHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`。`BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。
- Windows 11、ROCm0 Radeon 8060S／gfx1151、UMA 96 GiB、Adrenalin 26.11.2、TheRock 10.0.0。常用 `UnslothPle16` 単一GGUF（81,961,816,672 byte、mtime `2026-09-16T00:32:20.7663142Z`）をD0-4Aとパス・サイズ・mtimeで照合。ファイル全体のハッシュはD0-4Aの既存記録を参照。
- 引数はD0-4Aの `-c` と `-f` の値を変更。GPU layers 999、CPU MoE 0、threads 4、batch 2048、ubatch 1024、K/V f16、FA auto、MTP/Fit/reasoning OFF、temperature 0、top-p 0.8、seed 1234、生成上限256。warmupとJinjaは有効、prompt cache 0、verbosity 4。Perf Logger、RGP、追加の高速化フラグなし。
- ResourceMonitor 2秒、ADLX 2000 ms、RAM詳細250 ms、詳細回復許容差128 MiB、Matrix cooldown 5秒。D0-4Aのplanから設定と既定値を継承し、対象ジョブを2件に絞った。PlanOnlyで展開した後、runごとに `-OnlyJob`、`-MaxRuns 1 -StopOnError` で独立して呼び出す構成とした。

| Context | 同定した入力 | SHA-256 | 期待prompt |
| --- | --- | --- | ---: |
| 65,536 | `nlp-survey-ch3-d7-b1.txt` | `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` | 61,789 |
| 131,072 | `nlp-survey-ch3-d15-b1.txt` | `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` | 126,253 |
| 262,144 | `nlp-survey-ch3-d31-b1.txt` | `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` | 255,181 |

256kは既存r6のCLI実測に対応するファイルに限定し、1,261,235 byteとSHA-256を実機で照合。期待入力と生成上限の合計255,437はContext以下。 [r6 256k入力と計測条件](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/R6-ROCM-256K-MTP-OFF-ON-COMMON005-2026-10-30.md)

## 実測比較

**両run合格。** 128kと256kとも期待トークン数を処理し、生成256トークンで既定の上限に達した。両runは本文が扱う評価表現辞書と文書分類を日本語で要約した。128kは類義・反義関係とPMI、256kはそれらに加え文脈一貫性を用いる辞書拡張にも言及した。応答本文は生ログに保存。256kのネイティブログは `truncated = 0`。GPUエラーや異常終了は両runで観測されなかった。

| 性能 | 64k（D0-4A） | 128k | 256k |
| --- | ---: | ---: | ---: |
| 入力／生成トークン | 61,789／256 | 126,253／256 | 255,181／256 |
| PP tok/s（64k比） | 408.72（100.00%） | 303.23（74.19%） | 199.25（48.75%） |
| TG tok/s（64k比） | 21.81（100.00%） | 17.54（80.42%） | 12.62（57.86%） |
| PP／TG時間（秒） | 151.178／11.692 | 416.362／14.537 | 1,280.717／20.199 |
| 64k比 入力トークン増加率／PP時間増加率 | +0.00%／+0.00% | +104.33%／+175.41% | +312.99%／+747.16% |
| CLI時間（秒） | 208.418 | 476.545 | 1,348.202 |
| テンソルロード開始 → context構築（秒） | 43.872 | 43.820 | 45.129 |

| 内部バッファ（MiB） | 64k（D0-4A） | 128k | 256k |
| --- | ---: | ---: | ---: |
| 独立CPU／CPU_Mappedモデル | 行なし | 行なし | 行なし |
| ROCm0／ROCm_Hostモデル | 77,657.12／497.31 | 77,657.12／497.31 | 77,657.12／497.31 |
| ROCm0 KV合計 | 1,920.00 | 3,840.00 | 7,680.00 |
| ROCm0 recurrent state | 112.57 | 112.57 | 112.57 |
| ROCm0／ROCm_Host compute | 453.62／73.19 | 660.41／106.13 | 1,127.41／172.01 |

| メモリ・I/O | 64k（D0-4A） | 128k | 256k |
| --- | ---: | ---: | ---: |
| ロード中最小空きRAM（GiB） | 24.531 | 24.739 | 24.526 |
| PP／TG中最小空きRAM（GiB） | 25.129／25.142 | 25.058／25.066 | 24.933／24.916 |
| 空き1 GiB未満のサンプル数／観測区間数 | 0／0 | 0／0 | 0／0 |
| 最長観測区間（秒） | 観測なし | 観測なし | 観測なし |
| commit最大／limit（GiB） | 89.496／127.647 | 91.645／127.647 | 95.973／127.647 |
| Working Set／Private Memory最大（GiB） | 0.958／77.779 | 1.014／77.836 | 1.133／83.970 |
| Virtual Memory／System Cache最大（GiB） | 337.517／25.747 | 337.539／25.652 | 343.590／25.568 |
| WDDMアダプターDedicated／Sharedピーク（GiB） | 79.315／0.714 | 81.397／0.746 | 85.611／0.810 |
| WDDM対象PID Dedicated／Sharedピーク（GiB） | 78.854／0.642 | 80.935／0.674 | 85.150／0.739 |
| ADLX VRAMピーク（生ログのMB） | 81,218 | 83,350 | 87,666 |
| Pages Input／Page Reads／Page Faults各ピーク（件/秒） | 566,551.0／2,053.6／678,754.1 | 609,855.3／2,466.3／726,220.6 | 612,766.9／2,142.5／712,918.3 |
| ディスク読取／書込ピーク（MiB/s） | 2,210.61／3.45 | 2,382.75／6.64 | 2,393.62／1.00 |
| RAM詳細／通常監視サンプル数 | 855／83 | 1,915／191 | 5,364／536 |

| GPU指標（PP／TG区間中央値） | 64k（D0-4A） | 128k | 256k |
| --- | ---: | ---: | ---: |
| ADLX有効サンプル数 | 75／6 | 208／7 | 640／10 |
| GPU利用率（%） | 100.0／93.5 | 100.0／94.0 | 100.0／95.5 |
| GPUクロック（MHz） | 2,883.0／2,897.5 | 2,886.0／2,893.0 | 2,889.0／2,894.5 |
| VRAMクロック（MHz） | 980.0／993.0 | 986.0／993.0 | 991.0／986.5 |
| GPU温度（°C） | 70.0／61.0 | 77.0／67.0 | 79.0／69.0 |
| GPU電力（W） | 119.0／87.0 | 119.0／93.0 | 119.0／100.0 |

| PP内部の観測 | 64k（D0-4A） | 128k | 256k |
| --- | ---: | ---: | ---: |
| 前半／後半の区間PP（tok/s） | 528.04／343.89 | 445.52／234.96 | 340.96／142.41 |
| 前半／後半のコアクロック中央値（MHz） | 2,880.0／2,885.0 | 2,884.0／2,888.0 | 2,887.0／2,891.0 |
| 前半／後半のVRAMクロック中央値（MHz） | 976.0／982.0 | 982.0／988.0 | 988.0／993.0 |
| 前半／後半の温度中央値（°C） | 66.0／74.0 | 74.0／79.0 | 79.0／79.0 |
| 前半／後半のPages Input中央値（件/秒） | 0.0／0.0 | 0.0／0.0 | 0.0／0.0 |
| 前半／後半のPages Inputピーク（件/秒） | 4,651.9／1,399.5 | 5,790.4／34.9 | 3,190.6／1,369.3 |

**D0適用後もPP低下傾向が残った。** 128kは64k比74.19%（−25.81%）、256kは48.75%（−51.25%）。PP中の区間速度は長い入力ほど後半に落ち、256kでは約10–30%区間の340.96 tok/sから約70–90%区間の142.41 tok/sへ低下した。ADLXのPP前後半でGPU／VRAMクロック中央値は低下せず、256kの温度中央値は79 °Cで同値。前後半のPages Input中央値は各条件とも0だった。瞬間的なページ入力は観測されており、観測した指標だけでは低下の要因を特定できない。

3条件とも49/49層GPU、独立CPUモデルのログ行は消失したままで、ROCm0モデル77,657.12 MiBとROCm_Hostモデル497.31 MiBは同値。256kではKV 7,680 MiB、ROCm0 compute 1,127.41 MiBに増えた。ロード中の最低空きは全条件24.5 GiB以上で、1 GiB未満の観測は0件だった。256kのcommit・WDDM Dedicatedピークは開始前の試算内。PP/TGとロードの再現性、個々のheadの実バッファ名、CPU/GPU間転送量、他モデル・他バックエンドの動作は今回未確認。

集計はD0-4Aと同じ基準。RAMは有効な250 ms詳細サンプルを使用し、1 GiB未満の連続観測区間の長さを先頭・末尾サンプルの差とした。バッファとロード境界はstderrの相対時刻。PP/TG区間のRAMとADLXはネイティブ終了時刻から報告されたTG、PP時間を引いた近似区間で集計した。PP内部の区間速度は別に、stderrにある累積トークン数の約10→30%と約70→90%に最も近い進捗行の差分から算出した。クロック、温度、電力、ページングの前後半はPP推定区間を時間で二等分した。これらはGPUの個々の演算時間を表さない。

内部バッファ、WDDM、ADLX、物理RAM、commitは計数範囲が重なる。ピークは値ごとに取得し、加算していない。ディスクI/Oとページングはシステム値。Pages Inputにはマッピングされたファイルの読込みが含まれる。 [集計CSV](d0-4b-20261127/summary.csv) · [再集計コード](d0-4b-20261127/summarize.py)

## 256k開始前の容量判定

128kの開始前は64kの実測を起点に、追加KV 1,920 MiBで既知のGPUバッファを80.14 GiBと見積もった。実測の128k KVは3,840 MiB、GPU computeは660.41 MiB。物理空きは全実行中に1 GiBを下回らず、終了監査と既存の5秒クールダウンを通過した。

256kではKVを7,680 MiB、GPU computeを128k実測の2倍の1,320.82 MiBまで見込んだ。128kに対する増分は4.395 GiB。以下の見積もりは計数元ごとに独立して比較した。

| 256k開始判断 | 見積もり |
| --- | ---: |
| 既知の内部GPUバッファ | 84.737 GiB |
| WDDM Dedicatedピーク（128k実測81.397 GiB + 増分） | 85.792 GiB |
| commitピーク（128k実測91.645 GiB + 増分） | 96.040 GiB |
| 空き物理RAM（128k実測24.739 GiBから全増分を引いた参考値） | 20.344 GiB |

UMA 96 GiBとcommit limit 127.647 GiBに対して余裕を確認し、直前の開始ゲートも再取得した。一時割当の正確なピークを示すものではない。

## 開始・終了監査

| 指標 | 128k | 256k |
| --- | --- | --- |
| CLI時刻（JST） | 01:02:49.164 → 01:10:45.709 | 01:13:43.723 → 01:36:11.925 |
| CLIネイティブ終了コード | 0 | 0 |
| Measure／Matrix／SSH | OK／1/1 OK／0 | OK／1/1 OK／0 |
| 空きRAM 前 → 後（GiB） | 26.645 → 26.588 | 26.632 → 26.579 |
| commit 前 → 後、増分（GiB） | 8.205 → 8.267（+0.062） | 8.203 → 8.273（+0.070） |
| WDDM Dedicated／Shared 前 → 後（GiB） | 0.461 → 0.461／0.072 → 0.072 | 0.461 → 0.461／0.072 → 0.072 |
| 詳細RAM 初回回復 | `WithinTolerance`（空き差-17.23 MiB） | `WithinTolerance`（空き差-4.94 MiB） |
| 詳細GPU 初回回復 | `WithinTolerance`（ADLX 472 → 472 MB） | `WithinTolerance`（ADLX 472 → 472 MB） |
| P-MODE／OS起動 | Performance → Performance／一致 | Performance → Performance／一致 |
| System／Applicationイベントカーソル | 69911 → 69911／44072 → 44074 | 69911 → 69911／44074 → 44074 |
| 通常監視／PID GPU Complete・Partial | `Partial`／142・49 | `Partial`／443・93 |
| RAM詳細／ADLX | `Complete`／`Complete` | `Complete`／`Complete` |

開始時に両runとも空き16 GiB以上、競合プロセス・Task Managerの不在とイベントログ読み出しを確認。終了時は両runとも空き16 GiB以上、commit増分4 GiB以内、WDDM Dedicated増分0 GiB。OS起動時刻は両runの前後で `2026-11-26T11:45:51.5000000Z`。128kのApplication差分2件はSecurity-SPPの情報イベント16394・16384。128kのSystemと256kの両チャネルの差分は0件。重大イベントはなく、CLI・通常監視・RAM詳細監視・MatrixのPIDとADLX名に残留なし。

通常監視はPID別GPUカウンターの一部と背景CPU差分の取得に制約があり、総合判定は `Partial`。ネイティブRAM、プロセスメモリ、システムPerfMonは128kの191件と256kの536件で全件 `Complete`。RAM詳細のネイティブ欠損は0件。欠損値を実測0に置き換えていない。128k、256kの各1回で計測を終了した。

## 過去の計測との比較

以下はすべて参考比較。PP／TG（tok/s）を掲載し、同一入力SHAが確認できる日本語論文CLIを優先した。D0-4A～D0-4Bの比較は同一ビルド・モデル・推論設定で、Contextと入力長が一緒に変わる。

| 過去条件 | 64k PP／TG | 128k PP／TG | 256k PP／TG | 主な条件差 |
| --- | ---: | ---: | ---: | --- |
| b12651 clean ROCm Original b12662 | 412.09／22.48 | 304.71／18.00 | 200.19／12.75 | 同じ入力SHA、生成256、KV f16、batch 2048／ubatch 1024、MTP OFF。旧IQ3のjoined PLE、P-MODE記録Unknown。64k・128kは中央値、256kは単発 |
| b12651 Stage 1 ROCm Original b12671 | 411.85／22.10 | 304.62／17.97 | 記録なし | 64kはUMA96 GiB、128kは別セッションのUMA64 GiB。上記CLI基本条件と同じ |
| b12651 Stage 1 ROCm PLE16 b12671 | 411.93／22.18 | 記録なし | 記録なし | UMA96 GiB。GPUモデル50,191.17 MiB、独立CPUモデル27,465.94 MiB |
| b12651 ROCm PLE16 b12696、Adrenalin更新後 | 408.28／22.13 | 記録なし | 記録なし | 計測6。D0-4Aと引数・モデル・入力が一致し、CPU配置は修正前 |
| r6 ROCm PLE16 b12013、COMMON-005 OFF | 403.66／21.80 | 298.87／17.625 | 198.425／12.665 | 同じ日本語論文、MTP OFF、f16、2048／1024。各2回平均、生成512、通常ResourceMonitor OFF、旧ビルド |
| r5 ROCm Original clean b11517 | 390.73／21.18 | 292.69／17.13 | 193.64／12.37 | 同じ入力SHA、生成上限1024、temp 0.2、EOS終了、joined PLE、旧環境 |
| b12651 Stage 1 Vulkan PLE16 b12671 | 384.10／26.57 | 299.22／24.72 | 記録なし | UMA96 GiB、同じ入力SHA・モデル・CLI基本条件、バックエンドとビルドが異なる |
| b12651 clean Vulkan Original b12660 | 373.52／26.47 | 288.85／24.29 | 242.25／20.60 | 同じ入力SHA、生成256、モデルはjoined PLE、バックエンドとビルドが異なる |

r5のPLE16 ROCm benchによる繰り返し日本語論文は394.030 → 296.274 tok/s（−24.81%）。チャットテンプレート付きのCLIと異なるhead sliceで、速度低下の方向だけを参照した。r6のGather OFFは128kで64kの74.04%、256kで49.16%。b12651 clean ROCm Originalは73.94%／48.58%。 [b12651 clean](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/UPSTREAM-B12651-PP-TG-20261124.md) · [Stage 1](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/B12651-STAGE1-COMMON001-20261124.md) · [Adrenalin更新後の計測6](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/ADRENALIN-UPDATE-COMPARISON-20261126.md) · [r6 PLE16 Gather ABBA](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/R6-COMMON005-IMPLEMENTATION-2026-11-02.md) · [r5 clean](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md) · [r5 コーパス別PP](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md)

## 生ログと再集計

実機の `C:\llama-build\_logs\codex` 配下。条件、ネイティブstdout／stderr、RAM詳細、通常監視、ADLX、Measureの結果JSONを各runディレクトリに保存した。

| 条件 | Measureディレクトリ | Matrixディレクトリ（`matrix\` 配下） |
| --- | --- | --- |
| D0-4A 64k | `20261127-004435-749-cli-rocm-b12696-ctx65536-a32734523471` | `20261127-004352-653-d0-4a-iq3-ple16-64k` |
| 128k | `20261127-010236-805-cli-rocm-b12696-ctx131072-c15148be5d26` | `20261127-010153-802-d0-4b-iq3-ple16-longctx` |
| 256k | `20261127-011331-456-cli-rocm-b12696-ctx262144-ea50cce75a9b` | `20261127-011248-468-d0-4b-iq3-ple16-longctx` |

`d0-4b-audit-20261127` に使用planとLocalConfigを保存。各条件のサブディレクトリに `identity.json`、`before.json`、`after.json`、`gate.json`、`event-delta.json`、`residual-check.json` を置き、256kには容量判定の `budget.json` を追加した。

[実行plan](d0-4b-20261127/CLI.psd1) は `d0-4a-audit-20261127\CLI.psd1` のSettingsとDefaultsを保持。LocalConfigはD0-4Aのコピーに、128kと同じディレクトリの `nlp-survey-ch3-d31-b1.txt` を `Inputs.'256k'` として追加した。作業ディレクトリは `C:\llama-build\automation\w55`。以下が使用したMatrix呼び出し。実runは別々のSSH呼び出しで、間に終了監査と容量の再判定を挟んだ。

```powershell
$cfg = 'C:\llama-build\_logs\codex\d0-4b-audit-20261127'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan "$cfg\CLI.psd1" -LocalConfig "$cfg\cli-local.psd1" -MaxRuns 2 -RunIdPrefix D04B -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan "$cfg\CLI.psd1" -LocalConfig "$cfg\cli-local.psd1" -OnlyJob paper-128k -MaxRuns 1 -RunIdPrefix D04B-128k -StopOnError
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan "$cfg\CLI.psd1" -LocalConfig "$cfg\cli-local.psd1" -OnlyJob paper-256k -MaxRuns 1 -RunIdPrefix D04B-256k -StopOnError
```

```text
python d0-4b-20261127/summarize.py summary.csv --run 64k <64kのMeasureログ先> --run 128k <128kのMeasureログ先> --run 256k <256kのMeasureログ先>
```
