# b12651 系 Vulkan モデルロードの基準計測（作業4-2、2026-11-26）

[作業4-1の既存ログ・ソース解析](B12651-MODEL-LOAD-INVESTIGATION-20261126.md)を受け、既存 Stage 2 バイナリで、バッファ報告から Context 生成開始までを比較した。

## 実行条件と事前確認

- EVO-X2 専用 clone の計測ツールは `f500e9b070f3e6065dde50309def74d83cf9ddd4`、作業3-5統合版。GitHub main の基準 `3bc6d1faa76c0cd0adfbbf0dbbac60f59c686885` と標準25パスが一致する。実機の作業ツリーでは 作業4-1 のレビュー版 Markdown 1件が未追跡で、計測の `GitDirty=True` はそのファイルに由来する。 [統合記録](BENCHMARK-INTEGRATION.md)
- `build-s2v/bin/Release/llama-bench.exe`、b12676、実行ソース `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`。既存マニフェスト `evox2-build.json` は Verified。開始前に EXE の SHA-256 `576cda5ac89f2eb0b534b25ff37da78dfdc14c28e7b7d1ab5bb56f9ed7cdc8d2` を照合した。
- Radeon 8060S Vulkan0、UMA 96 GiB、P-MODE Performance、Qwen3.8 IQ3 PLE16 の既存 GGUF（81,961,816,672 bytes）。PP8192 と TG256 を各1回、depth 0、warmup ON、threads 4、batch 2048、ubatch 1024、GPU layers 999、CPU MoE 0、f16 KV、FA ON、MTP OFF。作業3-4と同じ Matrix plan から Round 1 の C を選択。通常監視2秒、ADLX 2,000 ms、詳細 RAM 250 ms、Perf Logger／RGP／実験フラグは同 plan の解除指定。 [作業3-4の条件](BENCHMARK-MATRIX-ROUNDS-B12651.md#実機条件)
- ローカル plan は実機の `C:\llama-build\automation\benchmark-configs\qwen38-b12651-monitor-overhead-34.local.psd1`。`PlanOnly` で1セルを確認してから、ThinkPad から `-MaxRuns 1 -StopOnError` で起動した。作業3-4の復旧コントローラーに確認項目と1セルの選択を加えた実行記録用コピーは実機 `C:\llama-build\_logs\codex\r42-model-load-20261126\run-one.ps1`。標準計測・ビルドツールを編集していない。
- Task Manager と競合プロセスは起動前に該当なし。System／Application の Event Log Readers アクセスと該当0件の区別を確認。OS 最終起動は Kernel-General 12 の `2026-11-26 00:21:08.500 JST`。前回は異常終了、高速スタートアップ無効。正常シャットダウン時刻・方式・停止期間は欠損。前後の安全判定に物理 RAM、コミット、WDDM アダプター Dedicated、P-MODE、イベント cursor、子・監視プロセスの終了を使用した。

## 結果と停止判断

**1件目でモデルデータ投入中の遅延が再現した。** 容量報告から Context 生成開始報告まで104.515秒。同じ250 ms監視の正常対照 R34R3C-M001 より59.019秒長かった。PP/TG は629.270／29.555 tok/sで、復旧後の作業3-4と同水準。遅延とリソースの時系列を同時に取得でき、同じ条件を反復しても ReadFile と転送待ちの内訳を直接測れないため、上限3件のうち1件で終了した。

| 項目 | 記録 |
| --- | --- |
| run | `R42-20261126T111727-01-M001`、PID 16432、OS プロセス開始 11:20:37.474 JST、終了 11:23:04.885 JST |
| OS 稼働時間 | 計測前 39,565.609秒（10.990時間）。作業3-4の復旧後と同じ OS 起動期間で、起動からの経過は約9時間長い |
| 成否 | SSH 終了0、Matrix OK、子終了0、PP/TG のネイティブ2行と Matrix を照合、残留 PID なし |
| 前→後の安全観測（GiB） | 空き RAM 25.220→25.324、コミット9.790→9.582（上限127.647）、WDDM アダプター Dedicated 0.482→0.482 |
| 回復 | RAM・GPU とも WithinTolerance。ADLX VRAM は493→最大80,993→493 MB。P-MODE は開始・終了とも Performance |
| 重大イベント | System cursor 69627→69627、Application 43716→43718。追加2件は Security-SPP の情報（16394、16384）。重大イベント0件 |
| ログのルート | `C:\llama-build\_logs\codex` |
| 子 | `20261126-112025-280-bench-vulkan-b12676-ctx8192-02dabb1c78a3` |
| Matrix | `matrix\20261126-111942-484-b12651-monitor-overhead` |
| 前後ゲート | `r42-model-load-20261126\R42-20261126T111727-01.result.json` と同名の `.log` |

## 作業3-4との比較

フェーズの起点は OS プロセス開始。容量は最後の `model buffer size` 行。各マーカーは stderr のラッパー受信時刻。Matrix の `ContextMarkerFromLaunchSeconds=110.718` は起動要求 tick からの値。ネイティブ load は1行目で、モデル計時起点から初回 eval 同期までを含む。PP/TG は stdout ネイティブ行の `samples_ns` に基づく。 [作業4-1の比較とタイマー定義](B12651-MODEL-LOAD-INVESTIGATION-20261126.md#5-タイマーとサンプルの対応)

| run | 開始→容量 s | 容量→Context s | 開始→Context s | Context→warmup s | native load s | プロセス s | PP／TG tok/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| M001・1A | 6.220 | 167.499 | 173.720 | 2.096 | 188.118 | 210.999 | 630.051／30.038 |
| M004・1D | 6.158 | 44.466 | 50.624 | 2.107 | 63.328 | 85.972 | 627.100／30.019 |
| R34R2D-M001 | 6.206 | 44.976 | 51.182 | 2.094 | 65.516 | 88.272 | 629.142／29.587 |
| R34R3D-M001 | 6.195 | 59.663 | 65.858 | 2.099 | 78.859 | 101.643 | 628.230／29.666 |
| R34R3C-M001 | 6.193 | 45.496 | 51.688 | 2.096 | 64.480 | 87.239 | 628.279／29.574 |
| R42・1C | 6.196 | **104.515** | **110.711** | 2.118 | **124.616** | **147.411** | 629.270／29.555 |

新規 run は、GGUF メタデータ受信0.590秒（stderr 7行）、容量6.196秒（2865–2866行）、Context 110.711秒（2870行）、warmup 112.829秒（4753行）。ラッパー全体165.001秒。PP／TG 実測は13.018／8.662秒、最初の `total − load` は13.021秒。最初の `reserve took` は809.27 ms（R34R3C との比較では容量から Context までの約59秒が主差）。実効 `load_mode=none`。stderr は以前と同じく Vulkan0 async upload と Vulkan_Host の別経路を示す（2867–2869行）。

### RAM・I/O・GPU の時系列

詳細 RAM は610行、欠損0、実測平均255.5 ms・最大294.3 ms。通常監視は57行、平均2.585秒・最大6.170秒。ADLX は78行。通常監視は Partial（背景 CPU 等の取得制限あり）、ADLX と詳細 RAM は Complete。子の PID と開始 UTC を `result.json`、`ram-events.jsonl`、`ram-detail.csv`、`resources.csv` で照合。メモリの時刻は詳細 CSV の UTC。I/O は PerfMon の通常監視行時刻、ADLX は記録された JST を UTC に換算した。各取得時刻やレート集計窓には差がある。

| 起動から s | 空き RAM GiB | Commit GiB | System Cache GiB | WS GiB | Private GiB | 観測 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| −1.020 | 25.088 | 9.933 | 12.819 | — | — | 起動前。Cache は R34R3C の約24.9 GiBより小さい |
| 5.849 | 24.268 | 85.676 | 12.818 | 0.135 | 74.953 | モデルバッファ報告直前 |
| 14.943 | 23.872 | 88.073 | 23.981 | 0.629 | 77.456 | GPU バッファへの投入中に Cache が増加 |
| 48.051 | 23.722 | 87.940 | 24.095 | 0.641 | 77.468 | 正常 run と同水準の読取帯域が終わる時期 |
| 54.996 | 23.661 | 87.942 | 24.094 | 0.641 | 77.469 | 読取帯域・GPU 稼働率が低下した区間 |
| 75.051 | 23.474 | 87.935 | 24.096 | 0.641 | 77.469 | 同区間で Commit／WS／Private は横ばい |
| 94.965 | 23.277 | 87.930 | 24.102 | 0.642 | 77.469 | 低活動が続く |
| 102.153 | **22.993** | 88.392 | 23.638 | 0.626 | 77.454 | RAM 最大8.655 GiB。R34R3D の57.303秒の変化と同じ方向 |
| 109.081 | 23.401 | 87.978 | 24.046 | 0.622 | 77.448 | Context 直前に空きが回復 |
| 111.659 | 23.900 | 90.542 | 24.019 | 0.667 | 80.023 | Context 生成報告後。KV・計算バッファ確保と整合 |
| 151.496 | 25.286 | 9.652 | 24.023 | — | — | 終了後の監視 |

コミット最大90.597 GiB、Private 最大80.058 GiB、WS 最大0.677 GiB。前後の OS 背景負荷や常駐量の差は残る。R34R2D／M004／R34R3C の最低空きは23.140／22.942／23.672 GiB。R34R3D は23.373 GiB。今回も追加遅延の間に物理 RAM 逼迫は観測されなかった。

| PerfMon または ADLX の区間 | R42 | R34R3C（通常） | R34R3D（異常） |
| --- | ---: | ---: | ---: |
| 7～45秒の Disk Read 中央値 MiB/s | 1,774 | 1,764 | 1,816 |
| Context 受信直前14秒の Disk Read 中央値 MiB/s | 60 | 1,651 | 58 |
| 同、Pages Input 中央値 pages/s | 15,384 | 423,386 | 14,757 |
| 同、ADLX GPU 稼働率中央値 | 1% | 11% | 1% |
| 通常帯域時の PID Dedicated／Shared GiB | 76.892／0.491 | 76.892／0.491 | 76.892／0.491 |
| Context 受信直前14秒の Dedicated／Shared 中央値 GiB | 76.890／0.487 | 76.892／0.491 | 76.891／0.489 |

- R42 の `DiskRead_MiBps` は47.767秒で1,658、49.788秒で796、51.815秒で58。51.815～96.039秒の各通常行は54.83～59.25 MiB/s、Pages Input は約14,000～15,000 pages/s。ADLX は49.189秒で11%、51.183秒で3%、53.194～103.179秒の観測は1%。この間の VRAM は約79,231 MBで安定していた。通常監視には最大6秒超のサンプル間隔がある。
- 102秒台に WS と Private が少し下がり、GPU の Dedicated／Shared が76.890／0.487 GiB、ADLX VRAM が79,228 MBへ変化。104.073秒と106.986秒では依然約60 MiB/sの読み取りがあり、ADLX の105.195～109.179秒は0%。110.711秒の Context 報告まで続いたこの末尾と、R34R3D の同様の末尾を、既存ログだけで個別のテンソル・バッファ群・イベントに割り当てることはできない。
- 51.815～106.986秒の測定行で、ディスク書き込みは最大0.45 MiB/s、CPU は2.1～10.6%。`% Disk Time` は末尾で9,407.6／26,741.2も記録しており、単純な SSD 稼働率として採用できない。ページ入力はシステム集約。モデルファイル、キャッシュ、ページファイルを区別するためのファイル別記録はない。
- 正常対照と同程度の読み取り帯域が起動後約48秒まで続いた点、その後に GPU 使用率・読み取りが低い区間が延びた点、Context 前のメモリの段差は R34R3D との共通点。低帯域は読み取りの停滞でも、イベント待ちによる次の読み込み開始の遅れでも生じ得る。両方を同じ優先度で調べる。M001 は当時のリソース記録がなく、この時系列が共通だったかは不明。ROCm の RAM 逼迫、IQ2_S run-02 の初回 eval 遅延、M005 のフリーズへの因果関係は確認していない。

### PP/TG 中のクロック

作業3-5と同じ集計方法で、各 PP/TG 開始報告の受信時刻からネイティブ実測秒数ぶんの窓を取り、ADLX 稼働率90%以上のサンプルの平均を示す。内部の処理境界とは時間差がある。

| run | PP 件数 | PP GPU／VRAM MHz | TG 件数 | TG GPU／VRAM MHz |
| --- | ---: | ---: | ---: | ---: |
| M001・1A | — | — | — | — |
| M004・1D | 6 | 2883.0／969.7 | 4 | 2889.8／999.3 |
| R34R2D-M001 | 6 | 2883.7／966.0 | 3 | 2897.3／999.7 |
| R34R3D-M001 | 7 | 2877.0／967.1 | 4 | 2877.8／998.0 |
| R34R3C-M001 | 7 | 2874.4／968.3 | 3 | 2893.0／999.7 |
| R42・1C | 7 | 2885.3／966.1 | 4 | 2890.0／999.3 |

R42 の PP/TG 中に顕著なクロック低下は観測されなかった。単一 run であり、OS 稼働時間や起動前のファイルキャッシュが遅延を変えるか、発生率がどの程度かは判断できない。

実機の製品 HEAD は `f500e9b`、追跡比較は0／0。作業4-1のレビュー用コピーの SHA-256 は維持した。生ログとコントローラー結果は実機の上記パスに保存した。変更は今回の計測用・出力用ログに限り、製品ソース、計測・ビルドツール、ドライバ、ROCm、UMA、OS 設定は維持した。

## 作業4-3の設計案

### 変更候補と計測境界

入口は `llama_model_base::load_tensors`、主な計測点は `llama_model_loader::load_all_data`。既存の読み込み順、バッファの再利用、GPU コマンドの発行順を保ったまま、呼び出し側の単調時計で経過時間を採る。`LLAMA_MODEL_LOAD_DIAG=1` を候補名とし、未指定と `0` は OFF。フラグの評価はモデルを開くときに1回とし、ON 時だけ集計を更新する。既存の `load time`、stdout JSON、動作条件は保持する。 [バッファ群の呼び出し順](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model.cpp#L2229-L2256) · [非同期アップロードの実装](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model-loader.cpp#L1680-L1958)

| 変更候補 | 診断点・計測境界 | 観測値 |
| --- | --- | --- |
| `src/llama-model.cpp` の `llama_model_base::load_tensors` | バッファ確保完了、群ごとの `load_all_data` 呼び出し前後、最後の群から復帰後に走るスケール取得・Hadamard 等の後処理 | 群の区間全体、群番号、デバイス／バッファ型、順序、テンソル数、論理バイト数 |
| `src/llama-model-loader.cpp` の `llama_model_loader::load_all_data` | upload 利用可否と初期化。host staging の確保、event 作成、upload backend 初期化。選択に失敗した場合の分岐 | 経路、失敗の分類、件数、確保バイト数、累積・最大 µs |
| 同、GPU 向けチャンクループ | seek、ファイル読み取り、staging 再使用前の `ggml_backend_event_synchronize`、`ggml_backend_tensor_set_async`、`ggml_backend_event_record` の前後を個別に測る | 件数、累積・最大 µs、読んだ物理要求バイト、実際の重みコピーに渡した論理バイト。未使用 slot への初回 wait は再使用待ちと別に数える |
| 同、ホスト・同期・マッピング分岐 | Host 宛ての seek と直接読み、同期転送 fallback の staging／set、mmap／lazy が選択された際のマッピング経路 | 経路、件数、バイト数、累積・最大 µs。mapped copy を通常の ReadFile の集計に加えない |
| 同、ループ後 | 最終 drain の各イベント待ち、イベント・host staging・backend の解放、検証を個別に測る | 件数、累積・最大 µs、load_all_data 群内の区間位置 |
| 必要時の `src/llama-mmap.cpp` の Windows `llama_file::impl::read_raw_unsafe` | 第1案は呼び出し側で read API の壁時計を取得。内部の部分読みや direct I/O fallback の切り分けが必要な場合だけ、OS の `ReadFile` 呼び出し単位を追加する | 読み取りの要求・返却バイトと回数、内部の最長待ち。file seek や upstream の集計との二重計上に注意 |

最初の反復で分かるのは CPU スレッドが各呼び出しから戻るまでの壁時計、またはそこで待った時間。`tensor_set_async`／`event_record` の CPU 時間は GPU 転送の実行時間とは別。`event_synchronize` の待ち時間には、キューの先行仕事とドライバ待ちも含み得る。GPU の非同期転送は次の read と重なる。群全体の wall time に GPU 実行時間や待ちの推定量を足さない。同期型 fallback も API の壁時計として記録する。GPU 側の実時間が必要になった時点で、別レビューの上で限定トレースを検討する。

### 出力と負荷

- 主出力は stderr に固定 prefix `llama_load_diag` と schema version を付けた1行 JSON。群の開始と終了、最終サマリを出す。各操作は `calls`、`bytes_requested`、取得可能な場合の `bytes_returned`、`sum_us`、`max_us`。群ごとの wall time、モデル開始からの monotonic offset、経路、終了状態を記録する。stdout の bench JSON は既存形式を使う。
- 進捗の候補は約5秒間隔の1行。長い待ちは暫定100 ms超を候補として群ごとに件数を持ち、詳細は最長の少数件に制限する。詳細にはテンソルの通番、チャンク offset／長さ、slot、操作、開始相対時刻、経過時間を保存する。待ちの直前に各チャンクをログ出力せず、待ちから戻った後に記録する。復帰しない待ちは最後の進捗・群イベントまでしか分からない。
- ON 時は固定長の集計領域と最長数件の領域を確保し、ホットループで文字列整形・メモリ割当・ディスク flush を行わない。各操作前後の時計読み取り自体は負荷になる。OFF で時計、積算、追加ログに入らない分岐を検証する。異常待ちの内訳を判断する際は、群の全体時間との整合と、ReadFile とイベント待ちの増分を別々に確認する。

### Vulkan／ROCm で共有できる範囲

CPU 側の read・event・upload・drain と host 宛て読み込みは汎用ローダーで共有できる。Vulkan の timeline semaphore と HIP のイベント／ストリーム待ちの内訳は各バックエンド固有。ログの経路名、バッファ型、成功・fallback で比較する。ROCm は CPU 側 PLE 重みの割合が異なるため、全 run の単純な速度比較は避け、群内で処理バイト数に対応づける。最初の実機対象は Vulkan。ROCm の追加計測は別レビューとする。 [Vulkan イベント待ち](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L17499-L17511) · [ROCm 非同期転送](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L3195)

### 検証とリスク

1. 実装レビュー後、CPU だけで検証できる集計器に既知の回数、0 バイト、異なる長さ、途中失敗、閾値超の操作を渡す。OFF の出力不変、JSON の読み取り、途中終了時の部分集計と終了状態、カウンターのオーバーフロー余裕を確認する。GPU の一括演算テストは使用しない。
2. ビルドの承認後、同じバイナリで OFF／ON を同一 OS 期間に交互に走らせる。初期は各3件を目安とし、1件ごとに安全ゲートを通す。EXE、モデル、監視、計測条件を固定し、容量→Context、native load、PP/TG、ログ量を比較する。差が正常 run のばらつきと区別できない場合は負荷の上限を断定せず、さらに軽い群単位のモードも検討する。
3. 異常を捕捉した場合は、正常例と同じ群・経路・バイト量で比較する。累積値で間欠的な遅れ、最大値と長時間記録で単発の停滞を区別する。ReadFile 側が増えた場合はファイル I/O の帰属を、event wait 側が増えた場合は転送キュー側を次の候補にする。両方が増えた場合は、低頻度進捗の時系列が示す先後を確認する。

主なリスクは、計時が I/O と転送の重なりを変えること、ログがローダーや通常監視に負荷を加えること、診断ビルドを既存 b12676 と直接比較する際にコード差が混入すること。今回の範囲は設計案まで。実装、ビルド、診断 run、ROCm run は別レビューで扱う。
