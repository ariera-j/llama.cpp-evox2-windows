# AMD Adrenalin 更新前後の比較（2026-11-26）

## 更新前の固定条件

GitHub main は `07c33cf4b7e69057f45b9903f762b28ec221d588`。実機専用 clone は `codex/vulkan-manifest-cpu-variants-20261124` の `9ae819d5be4fe9861d2aa8547983aed801c437ac` で、追跡先と一致し、作業ツリーはクリーン。使用した標準 Measure／Matrix は作業5-4の統合版。

| 対象 | 実機値 | 同じ情報の取得方法 |
| --- | --- | --- |
| AMD Adrenalin | 運用記録 26.8.1。ディスプレイドライバー `32.0.31041.1004`、リリース文字列 `26.10.41.01-260811a-203304C-AMD-Software-Adrenalin-Edition` | `Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\Video\*\0000` の Radeon 8060S エントリ。DriverVersion、ReleaseVersion、DriverDate |
| Vulkan | SDK 1.4.357.0、System32 Loader 1.4.357.0、ICD `amdvlk64.dll` 9.2.10.395、ICD API 1.4.349 | SDK パス、System32 の `vulkan-1.dll` の FileVersion、同 GPU エントリの VulkanDriverName が指す JSON の ICD と、参照 DLL の FileVersion |
| ROCm | TheRock SDK 10.0.0、同梱 `amdhip64_7.dll` 10.0.3581.0、`hipblas.dll` 3.6.0.0、`libhipblaslt.dll` 1.4.1.0 | w54 ROCm マニフェストと同梱バイナリの VersionInfo.FileVersion |
| Windows・BIOS | Windows 26300.10075、EVO-X2 1.12（BIOSReleaseDate `12/09/2025`） | Windows NT CurrentVersion の CurrentBuild／UBR、HARDWARE DESCRIPTION System BIOS の BIOSVersion／BIOSReleaseDate |
| UMA・OS 起動 | UMA 96 GiB、Windows 可視 31.647 GiB、起動 2026-11-26 00:21:08.500 JST | Radeon エントリの HardwareInformation.qwMemorySize、GetPerformanceInfo、Kernel-General/12 StartTime。稼働時間は GetTickCount64 |

実機は Performance、Task Manager は起動前に不在を確認。通常監視2秒、ADLX 2,000 ms、RAM 詳細250 ms。開始／終了ゲートは物理空き16 GiB、基準からのコミット増分・WDDM Dedicated 増分各4 GiB。詳細回復の許容差は128 MiB。ファイルキャッシュの強制解放、再起動、アイドル時間の調整は実施していない。

## ビルドと実行条件

| セル | バックエンド | ビルドとソース | モデル／入力 |
| --- | --- | --- | --- |
| 1 | Vulkan | b12690、`d32cdfaf1c86739b6479260e6324d1394081cf50` | IQ3 PLE16、合成 PP8192/TG256 |
| 2 | Vulkan | b12696、`20f48bfe162d8d886b9f5fea7ad6d7df91eb3266` | IQ3 PLE16、128k 日本語論文 |
| 3 | Vulkan | 同上 | ROCmFP4 FAST v2 PLE16、64k 日本語論文 |
| 4 | Vulkan | 同上 | Gemma 4 31B IT QAT Q4_0、32k 日本語論文 |
| 5 | ROCm | 同上 | 同じ Gemma 4 モデルと入力 |
| 6 | ROCm | 同上 | IQ3 PLE16、64k 日本語論文 |

計測1は作業4-4の ON プランから C の第1ラウンドを選択。depth 0、repetition 1、warmup ON、threads 4、batch 2048、ubatch 1024、GPU layers 999、CPU MoE 0、K/V f16、FA ON、MTP OFF。Matrix 内で診断フラグを適用して復元。計測2～6の CLI 引数は下記の設定例と、各参照 run の条件ログに対応する。Context は順に 131072、65536、32768、32768、65536。共通で生成上限256、batch 2048、ubatch 1024、threads 4、GPU layers 999、CPU MoE 0、K/V f16、FA auto、Fit/MTP/reasoning OFF、温度0、top-p 0.8、seed 1234。Gemma 参照 run は UMA64 GiB 相当の Windows 可視 RAM 約63.65 GiB。今回の前後チェックは実機の UMA96 GiB 下で実施する。

[再実行・再集計手順](adrenalin-update-comparison-20261126/README.md) · [参照 run とモデル・入力識別](adrenalin-update-comparison-20261126/reference-identity.csv) · [EXE／DLL／マニフェスト SHA-256](adrenalin-update-comparison-20261126/build-artifacts.csv)

GGUF 全体の SHA-256 は推論終了後に取得した。参照 run の条件ログは全体 SHA-256 欠損のため、事前照合はモデルのパス・サイズ・更新時刻と入力ハッシュを使用した。 [今回のモデル SHA-256](adrenalin-update-comparison-20261126/model-sha256.csv)

起動前の標準照合は、計測1が `Verified / LegacyArtifacts`、b12696 が `Verified / RuntimeDependenciesV1`。表の b12696 全ファイル台帳は作業5-4の記録を収録し、実行対象の EXE とマニフェストの SHA-256 および標準ツールによる実行時依存を今回照合した。

依存 digest は診断版 `dbbedde569242e142fe04f8f6de443920cd86abbb2306e43dfc841ef995473d3`、b12696 Vulkan `5d031913881904468962e0cbd5dc0c9f0002ec363aa71d23ad79961cb05a24dc`、b12696 ROCm `0abc8d39f245e19d3e516d8a4dd297654d226aad1408549f56ead49b975170a5`。全6件で使用した ADLX モニター EXE の SHA-256 は `8c5da580c05d8f7c2477865a48aa1b2cd24cbabd926dc599a6f6a1580dbcc487`。

## 更新前の結果

計測は 6 件。各条件1回。更新後との差は同じセルで比較する。

| セル | 条件 | 入力 / 生成 tok | PP / TG tok/s | RAM 最大 / 空き最小 / コミット最大 GiB | PID GPU Dedicated GiB / ADLX VRAM MB | 最高温度 °C | Context 受信まで s | プロセス s | 結果 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | Vulkan b12690 IQ3 診断 | 8192 / 256 | 629.22 / 29.55 | 8.477 / 23.171 / 90.687 | 78.614 / 80994 | 69 | 51.683 | 87.521 | OK / 0 |
| 2 | Vulkan b12696 IQ3 128k | 126253 / 256 | 299.12 / 23.06 | 8.382 / 23.266 / 94.231 | 81.764 / 84220 | 87 | 50.665 | 488.553 | OK / 0 |
| 3 | Vulkan b12696 FP4 FAST 64k | 61789 / 256 | 389.38 / 26.08 | 8.652 / 22.995 / 103.493 | 91.101 / 93781 | 82 | 53.737 | 224.960 | OK / 0 |
| 4 | Vulkan b12696 Gemma 32k | 29379 / 256 | 64.44 / 8.88 | 8.613 / 23.035 / 33.707 | 21.801 / 22817 | 87 | 11.221 | 498.204 | OK / 0 |
| 5 | ROCm b12696 Gemma 32k | 29379 / 256 | 186.87 / 9.02 | 8.188 / 23.459 / 33.073 | 21.206 / 22208 | 82 | 4.130 | 190.276 | OK / 0 |
| 6 | ROCm b12696 IQ3 64k | 61789 / 256 | 407.87 / 22.26 | 31.647 / 0.000240 / 90.950 | 51.969 / 53709 | 84 | 63.727 | 229.363 | OK / 0 |

GPU 監視の PP／TG 中央値。通常監視の Partial は主に PID GPU の部分取得とバックグラウンド CPU 読み取り制約による。ADLX のホットスポットとボード全体電力は未対応。計測3は ADLX のサポートメタデータが欠損して Partial。主な GPU 指標は117サンプルすべて有効で、モニター終了コードは0。サンプルの欠損は補完していない。

| セル | GPU 使用率 % | GPU MHz | VRAM MHz | GPU 温度 °C | GPU 電力 W | 通常 / ADLX / RAM 詳細件数 | 監視品質 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 100 / 97 | 2884 / 2898 | 968 / 1000 | 65 / 52 | 121 / 80 | 35 / 48 / 377 | Partial / Complete / Complete |
| 2 | 100 / 94 | 2836 / 2886 | 1000 / 999 | 78 / 65 | 119 / 78 | 194 / 249 / 1955 | Partial / Complete / Complete |
| 3 | 100 / 96 | 2777 / 2887 | 1000 / 1000 | 78 / 64 | 120 / 79 | 89 / 117 / 922 | Partial / Partial / Complete |
| 4 | 100 / 99 | 2864 / 2900 | 1000 / 1000 | 73 / 70 | 119 / 98 | 199 / 254 / 1979 | Partial / Complete / Complete |
| 5 | 100 / 97 | 2819 / 2899 | 683 / 1000 | 73 / 61 | 104 / 82 | 76 / 100 / 782 | Partial / Complete / Complete |
| 6 | 100 / 95 | 2880 / 2893 | 981 / 1000 | 79 / 68 | 120 / 109 | 92 / 119 / 936 | Partial / Complete / Complete |

[比較用 CSV](adrenalin-update-comparison-20261126/pre-update.csv) に PP 区間の先頭・末尾各1/3 のクロック中央値も収録。RAM と GPU メモリは合算しない。

### 計測1のロード診断

診断 JSON は schema 1 の24レコード。両群が `ok` で終了し `load_tensors_end` が出力された。容量報告→Context 受信は45.500秒（作業4-4の正常 ON 43.954～43.965秒）、GPU 群 wall は45.190秒（43.590～43.936秒）、ホスト群は0.322秒（0.315～0.318秒）、native load は64.766秒（63.182～67.049秒）。過去の大幅なロード遅延は今回観測されなかった。

### 計測6の RAM 詳細

ロード中の最小空きは 0.246 MiB（2026-11-26T11:03:07.3428101Z）。空き1 GiB未満の連続有効行は次の5区間（UTC）。 2026-11-26T11:03:00.7749440Z ～ 2026-11-26T11:03:02.0526209Z、6行、1.277676秒。2026-11-26T11:03:02.5559766Z ～ 2026-11-26T11:03:03.0593759Z、3行、0.503399秒。2026-11-26T11:03:03.5649101Z ～ 2026-11-26T11:03:04.3232779Z、4行、0.758367秒。2026-11-26T11:03:05.0813499Z ～ 2026-11-26T11:03:12.1488910Z、29行、7.067542秒。2026-11-26T11:03:13.9107064Z ～ 2026-11-26T11:03:14.6657543Z、4行、0.755048秒。PP 区間の最小空きは 4.594 GiB。終了後ゲートは 26.327 GiB、詳細監視の終了後最終行は 26.376 GiB。System Cache は 23.666 から 0.708 GiB に縮小した。参照 run の最小空きは0.168 GiB、最大コミットは89.398 GiB。 [低メモリ区間 CSV](adrenalin-update-comparison-20261126/rocm-iq3-low-memory.csv)

## 生ログと終了確認

生ログは実機の `C:\llama-build\_logs\codex`。下記 Measure と `matrix\<Batch ID>` に stdout／stderr、監視、Measure／Matrix JSON、条件、展開済み plan を保全した。`adrenalin-pre-20261126` には実機用プランと前後ゲートの記録がある。確認を通過した行は SSH／Measure の終了コード0、Matrix OK、RAM／GPU WithinTolerance、前後 Performance、Task Manager・残留プロセスなし、起動時刻不変、新規重大イベントなし。

| セル | Matrix Run ID | Measure 開始 JST | Measure ログディレクトリ | Matrix Batch ID | 空き RAM 前→後 GiB | コミット前→後 GiB | GPU Dedicated 前→後 GiB | System / Application |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| 1 | `ADRPRE-01-ON-M001` | 2026-11-26 19:26:36 | `20261126-192635-816-bench-vulkan-b12690-ctx8192-bd810f7bbb71` | `20261126-192553-266-b12651-monitor-overhead` | 25.366 → 25.334 | 9.876 → 9.742 | 0.482 → 0.482 | 69638 / 43815 |
| 2 | `ADRPRE-02-M001` | 2026-11-26 19:30:13 | `20261126-193013-111-cli-vulkan-b12696-ctx131072-e67552e50cff` | `20261126-192930-462-adrenalin-pre-cli-20261126` | 25.335 → 25.375 | 9.736 → 9.700 | 0.482 → 0.482 | 69638 / 43815 |
| 3 | `ADRPRE-03-M001` | 2026-11-26 19:40:27 | `20261126-194026-739-cli-vulkan-b12696-ctx65536-95d269031f3b` | `20261126-193944-102-adrenalin-pre-cli-20261126` | 25.342 → 25.382 | 9.735 → 9.732 | 0.482 → 0.482 | 69638 / 43817 |
| 4 | `ADRPRE-04-M001` | 2026-11-26 19:46:18 | `20261126-194617-675-cli-vulkan-b12696-ctx32768-23a227086e44` | `20261126-194535-065-adrenalin-pre-cli-20261126` | 25.347 → 25.337 | 9.772 → 9.778 | 0.482 → 0.482 | 69638 / 43819 |
| 5 | `ADRPRE-05-M001` | 2026-11-26 19:56:44 | `20261126-195644-161-cli-rocm-b12696-ctx32768-b1fdf75723fd` | `20261126-195600-894-adrenalin-pre-cli-20261126` | 25.314 → 25.338 | 9.810 → 9.818 | 0.482 → 0.482 | 69638 / 43819 |
| 6 | `ADRPRE-06-M001` | 2026-11-26 20:02:00 | `20261126-200200-309-cli-rocm-b12696-ctx65536-308cf3ff8e36` | `20261126-200117-225-adrenalin-pre-cli-20261126` | 25.296 → 26.327 | 9.861 → 9.711 | 0.482 → 0.482 | 69638 / 43819 |

## 更新後（Adrenalin 26.11.2）

計測1は Measure 終了0・Matrix OK。終了後 RAM の詳細回復判定が `AboveTolerance` だったため、更新前と同じ停止手順で計測2～6を中止した。更新前のプランと LocalConfig をそのまま参照し、全6セルを個別に `PlanOnly -MaxRuns 1 -StopOnError` で確認した。推論は計測1の1回。

### 環境差分

| 項目 | 更新前 | 更新後 |
| --- | --- | --- |
| Adrenalin | 26.8.1 | 26.11.2（AMD Software のアンインストール レジストリ DisplayVersion） |
| Radeon 8060S ディスプレイドライバー | 32.0.31041.1004 | 32.0.32029.2010（リリース文字列 `26.20.29.02-261116a-206168C-AMD-Software-Adrenalin-Edition`） |
| Vulkan ICD DLL／API | `amdvlk64.dll` 9.2.10.395／1.4.349 | `amdvlk64.dll` 9.2.10.416／1.4.359 |
| Vulkan SDK／System32 Loader | 1.4.357.0／1.4.357.0 | 1.4.357.0／1.4.357.0 |
| TheRock と同梱 HIP／BLAS | 10.0.0、HIP 10.0.3581.0、hipBLAS 3.6.0.0、hipBLASLt 1.4.1.0 | 同左。ランタイムファイルとデータツリーの照合に成功 |
| Windows／BIOS／UMA／P-MODE | 26300.10075／EVO-X2 1.12／96 GiB／Performance | 同左 |
| OS 起動時刻 | 11/26 00:21:08.500 JST | 11/26 20:45:51.500 JST。計測1の Measure 環境取得時の稼働時間577.781秒 |
| 計測1の詳細監視開始前 System Cache | 22.21 GiB | 3.56 GiB |

取得元は上記「更新前の固定条件」と同じ。計測前に3ビルドの EXE、同梱 DLL、マニフェストをハッシュ台帳と照合し、実行依存の3種の digest も更新前と一致した。ROCm のデータツリーは標準検証で照合した。モデルはパス・名前・サイズ・更新日時を確認し、入力3種は SHA-256 一致。自然な初回ロードを保持するためモデル全体の再ハッシュは行っていない。計測1の引数配列、モデルパス、ADLX EXE ハッシュも更新前と一致。

### 実測と比較

| セル | 条件 | PP 更新前 → 更新後 tok/s | TG 更新前 → 更新後 tok/s | 結果 |
| --- | --- | ---: | ---: | --- |
| 1 | Vulkan b12690 診断 | 629.219 → 636.351（+1.13%） | 29.552 → 29.606（+0.18%） | 推論完了。回復判定により後続停止 |
| 2 | Vulkan IQ3 128k | 299.12 → — | 23.06 → — | 未実行 |
| 3 | Vulkan FP4 FAST 64k | 389.38 → — | 26.08 → — | 未実行 |
| 4 | Vulkan Gemma 32k | 64.44 → — | 8.88 → — | 未実行 |
| 5 | ROCm Gemma 32k | 186.87 → — | 9.02 → — | 未実行 |
| 6 | ROCm IQ3 64k | 407.87 → — | 22.26 → — | 未実行 |

| 計測1の項目 | 更新前 | 更新後 |
| --- | ---: | ---: |
| PP／TG GPU クロック中央値 MHz | 2884／2898 | 2881.5／2892.5 |
| PP／TG VRAM クロック中央値 MHz | 968／1000 | 938／1000 |
| PP／TG GPU 使用率中央値 % | 100／97 | 100／97 |
| PP／TG GPU 電力中央値 W | 121／80 | 119／80 |
| PP／TG GPU 温度中央値 °C | 65／52 | 66／52 |
| PID GPU Dedicated 最大 GiB／ADLX VRAM 最大 MB | 78.614／80994 | 78.618／80956 |
| RAM 使用最大／最小空き／コミット最大 GiB | 8.477／23.171／90.687 | 8.478／23.169／89.138 |
| Pages Input／Page Reads／Page Faults 最大（秒あたり） | 538865／1208／668731.4 | 541674.5／1652.4／709789.7 |
| 通常／ADLX／RAM 詳細サンプル数 | 35／48／377 | 36／49／387 |
| 通常／ADLX／RAM 詳細状態 | Partial／Complete／Complete | Partial／Complete／Complete |

[更新後の比較 CSV](adrenalin-update-comparison-20261126/post-update-comparison.csv) に差分と欠損セルを記録。ページング値は PerfMon の取得成功行の最大値で、ページファイル I/O の量は未確認。PP／TG の ADLX 区間は従来の受信マーカーに基づく。

### Vulkan ロード診断

診断 JSON は更新前24行、更新後23行。両方で schema 1 のロード終了と2群の `ok` を確認した。大幅なロード遅延は観測しなかった。

| 区間・操作 | 更新前 | 更新後 |
| --- | ---: | ---: |
| 容量報告 → Context 受信 s | 45.500 | 44.514 |
| native load 報告 s | 64.766 | 66.879 |
| Vulkan GPU 群 wall s | 45.190 | 43.998 |
| read 積算 s | 42.643 | 41.352 |
| reuse_wait 積算 ms | 309.133 | 283.612 |
| upload 積算 ms | 181.803 | 179.388 |
| event_record 積算 s | 1.995 | 2.123 |
| drain 積算 µs | 11 | 11 |

内部タイマーはローダーの CPU 側経過時間。容量報告から Context までの時間はラッパーのログ受信間隔。 [操作別 CSV](adrenalin-update-comparison-20261126/load-diag-comparison.csv)

### 停止判定と採用判断

RAM 詳細の終了後最終行は開始前より物理使用量が182.680 MiB、コミットが178.738 MiB増えた。物理使用量とコミットがともに128 MiB の許容差を超え、`AboveTolerance` になった。GPU の ADLX VRAM は408→451 MB で `WithinTolerance`。停止監査を実行した SSH の終了コードは1。読み取り専用の事後監査では Performance、空き RAM 25.571 GiB、コミット7.928 GiB、WDDM Dedicated 0.441 GiB、対象プロセスなしを確認した。診断は対象プロセスだけに設定され、新規 SSH のプロセス環境では未設定だった。

起動監査の Kernel-General/12（System 69721）は運用者による予定再起動。実行前カーソルは System 69907／Application 44009。停止時は69908／44012。追加記録は IsolatedUserMode と Security-SPP の情報イベントで、確認範囲に GPU リセット、WHEA、BugCheck、リソース枯渇、AMD External Events Client Module の異常終了はなかった。短時間の結果で長期安定性は判断できない。

今回のデータで確認できたのは Vulkan 診断ワークロードの完走と、回復判定による停止。再起動後の稼働時間やファイルキャッシュに差があり、単発の速度差からドライバー固有の効果は判断できない。採用判断には回復判定の扱いと、未実行の Vulkan 128k TG、両バックエンドの Gemma PP、ROCm IQ3 64k の RAM 逼迫、長時間の安定性の確認が残る。

生ログは `C:\llama-build\_logs\codex`。Measure は `20261126-205520-330-bench-vulkan-b12690-ctx8192-bd810f7bbb71`、Matrix は `matrix\20261126-205434-315-b12651-monitor-overhead`。実行 ID は `ADRPOST-01-ON-M001`。PlanOnly、コントローラーの transcript、停止根拠 JSON、事後監査結果は `adrenalin-post-20261126` に保全した。
