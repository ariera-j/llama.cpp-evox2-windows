# b12651 系 モデルロード時の異常低速化の調査（作業4-1、2026-11-26）

## 結論

- Vulkan **M001** と **R34R3D-M001** の追加時間は、モデルバッファ容量の報告から最初の Context 生成開始報告までに集中した。この受信間隔は **167.499秒／59.663秒**。正常対照は約44.5～45.5秒。両異常 run とも本計測の PP/TG は各ラウンドの通常範囲だった。
- **R34R3D-M001** の追加区間では、読み取り帯域と GPU 稼働率が低下したまま Context 生成への移行が遅れた。最低空き物理 RAM は **23.373 GiB**。遅延した区間にはバッファへの読み込み・コピー・転送待ち・後処理が含まれる。ReadFile と転送・イベント待ちを同じ優先度で調べる。
- **ROCm CLI** はロード後半に CPU 側 Working Set が増え、空き RAM が **6.563 MiB** まで低下した。既存の CPU 側 PLE16 配置と整合し、終了処理で回復した。分割 head の GPU 配置を ROCm で可能にできれば、CPU 側の常駐量を抑え、RAM 逼迫の軽減にも寄与する可能性がある。これは Vulkan のロード遅延とは別課題。
- **IQ2_S 実験**の run-02 は最初の eval 付近、run-08 は TG タイマー開始前の遅延が有力。M005 はロード後の PP warmup 開始付近のハードフリーズとして扱う。

## 1. 開始時の環境と Git

専用 clone の `AGENTS.md` と `AGENT-RULES.md` を先に読み、GitHub 上の各参照と運用文書を確認した。SSH は `-F /dev/null -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=yes`。

| 参照 | GitHub | EVO-X2 専用 clone | 追跡先／ahead・behind |
| --- | --- | --- | --- |
| main | `3bc6d1faa76c0cd0adfbbf0dbbac60f59c686885` | 同じ | `origin/main`、0／0 |
| `codex/vulkan-manifest-cpu-variants-20261124` | `f500e9b070f3e6065dde50309def74d83cf9ddd4` | 同じ。チェックアウト中の HEAD | 同名の `origin/…`、0／0 |

専用 clone と既存の Matrix worktree は開始時クリーン。GitHub 側の2参照は ThinkPad の一時 clone でも照合した。作業3-5の main 側取り込み差分 `76417e3..6b01ac2` から特定した標準計測25パスは、基準の2コミット間で差分なし。製品ビルドと過去の計測ラッパーの来歴は別途確認した。 [作業3-5の統合記録](BENCHMARK-INTEGRATION.md)

対象 run の記録上の環境は Windows、Radeon 8060S、UMA 96 GiB、Windows 可視 RAM 31.647 GiB、P-MODE Performance。Adrenalin 26.8.1、ROCm は TheRock 10.0.0。復旧後の OS 起動時刻は 2026-11-26 00:21:08.500 JST。始動前取得の OS 稼働時間は R34R2D が1.835時間、R34R3D が2.113時間、Vulkan／ROCm CLI が2.287／2.334時間。旧 M001 の OS 稼働時間は `result.json` にない。障害記録の起動時刻から OS プロセス開始まで約3時間14分26秒。 [実機環境](EVOX2-ENVIRONMENT.md) · [障害記録](INCIDENT-20261126-M005.md)

## 2. 参照した資料と生ログ

- 正本の GitHub main `3bc6d1f`。リポジトリの `AGENTS.md`、[エージェントルール](AGENT-RULES.md)、[環境](EVOX2-ENVIRONMENT.md)、[ランブック](RUNBOOK.md)、[計測ルール](BENCHMARK-RULES.md)、[既知の問題](KNOWN-ISSUES.md)、[統合](BENCHMARK-INTEGRATION.md)、[Matrix](BENCHMARK-MATRIX-B12651.md)、[通常監視](BENCHMARK-MONITORING-B12651.md)、[RAM 詳細](BENCHMARK-RAM-DETAIL-B12651.md)、[ラウンド比較・追加集計・引き継ぎ](BENCHMARK-MATRIX-ROUNDS-B12651.md#作業3-5で照合した追加集計)、[M005](INCIDENT-20261126-M005.md)。
- [COMMON-001 と UMA 64／96 GiB の配置比較](../B12651-STAGE1-COMMON001-20261124.md)、[Stage 2](../B12651-STAGE2-ROCMFP4-VULKAN-20261124.md)、[過去の異常再起動・VRAM クロック記録](../EVOX2-UNEXPECTED-WINDOWS-RESTART-INCIDENT-LOG.md)。
- IQ2_S 実験の [既存再解析](../iq2-s-vulkan-matvec-20261125/README.md#低速2件の生ログ再解析)、[条件とコマンド](../iq2-s-vulkan-matvec-20261125/commands.md)、[ログのハッシュ](../iq2-s-vulkan-matvec-20261125/raw-log-sha256.csv)、`runs.csv`、`summary.csv`、保存マニフェストと6件の生ログ。 [起動スクリプト固定版](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/bench.ps1#L23-L62)
- 実機の `C:\llama-build\_logs\codex`。元バッチ `matrix\20261125-234629-575-b12651-monitor-overhead` の `matrix-runs.csv`、`matrix-result.json` と関連ファイル。復旧後の `r34-recovery-20261126` の `recovery-run-map.csv`、`combined-summary.csv`、`combined-rounds.csv`、各結果と終了時イベント監査。下表の子ログから `result.json`、`conditions.json`、`summary.csv`、`stderr.log`、bench の `llama-bench.json` または CLI の stdout、取得済みの `ram-events.jsonl`、`ram-detail.csv`、`ram-monitor.json`、`resources.csv`、`gpu-metrics.csv` を参照した。
- 元 M005 は子 `20261126-000203-446-bench-vulkan-b12676-ctx8192-b4c155bdcc62` の stderr・RAM CSV・イベント行と `llama-bench.json` のサイズを確認した。既存の保全先は `incident-M005-preserved-20261126-014720-524`。Windows の System、Application、TerminalServices-LocalSessionManager/Operational も対象の日時・イベント種別に絞って照会した。

## 3. run、バイナリ、識別情報

| 実行物（各ビルドの `bin\Release`） | ビルド・固定ソース SHA | EXE SHA-256 |
| --- | --- | --- |
| `build-s2v\…\llama-bench.exe` | b12676、`eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1` | `576cda5ac89f2eb0b534b25ff37da78dfdc14c28e7b7d1ab5bb56f9ed7cdc8d2` |
| `build-s2v\…\llama-cli.exe` | b12676、同じ SHA | `406f91ac5d09e83ba7c54d4babf0043e3879dfed84ef8edd82256921c8b829f8` |
| `build-c1r\…\llama-cli.exe` | b12671、`35818246a27521327e627e8f323e5f3a6386f8f9` | `d03759b7b1a364d8d1b6f46419711f7a90d1a8b58d149092945198dcad5ddf58` |
| `build-i2mv\…\llama-bench.exe` | b12679、`a38ba149d11d6a7067e6c323523f95c7889b167b` | `42e44e07faafb25becd3c0cdbdc0dbdcf3af4befe49ab77c8daf21a8190dc574` |

`build-s2v`／`build-c1r` の既存 `evox2-build.json` は `BuildIdentity=Verified`。EXE の保存ハッシュと埋め込みコミットは子 `result.json` と一致。両 CLI は `RuntimeArtifactStatus=Verified`。IQ2_S は実験時に保存した Verified マニフェスト、`command.json` の EXE、stdout の build 12679／`a38ba149d` が対応する。比較6件の生 stderr は保存済みハッシュとバイト数に全件一致した。今回 EXE・モデル本体の再ハッシュはしていない。 [IQ2_S 実験マニフェスト](../iq2-s-vulkan-matvec-20261125/logs/build-i2mv-manifest.json)

Vulkan Matrix は Qwen3.8 IQ3 PLE16（GGUF 実ファイル 81,961,816,672 bytes）、Vulkan0、PP8192 と TG256 を各1回、depth 0、warmup ON、threads 4、batch 2048、ubatch 1024、GPU layers 999、CPU MoE 0、KV f16、FA ON、MTP OFF。A は周期監視なし、B は通常／ADLX、C は B＋RAM 250 ms、D は B＋RAM 100 ms。CLI 2件は同じモデル、Context 2048、warmup ON、同じ短文入力（SHA-256 `ad29fe3ec728057ce0736594ed79886ed278cb0b0f6ed35e9eaca26cb27b0bb6`）、実 PP210／TG32、通常／ADLX／RAM 250 ms。CLI は Vulkan0／ROCm0、各 `-fit off` と MTP OFF。IQ2_S の6件は Vulkan0、同じ IQ3 PLE16、TG256、pp=0、depth=0、warmup OFF、Logger OFF。 [Matrix の条件](BENCHMARK-MATRIX-ROUNDS-B12651.md#実機条件) · [IQ2_S 実験の条件](../iq2-s-vulkan-matvec-20261125/commands.md)

時刻は子プロセス OS 開始時刻（UTC）。JST は +09:00。ディレクトリ名の JST 時刻と OS 開始時刻にはラッパー準備分の差がある。

| run | 子ログディレクトリ（生ログのルート直下） | PID | OS 開始 UTC |
| --- | --- | ---: | --- |
| M001・1A | `20261125-234712-543-bench-vulkan-b12676-ctx8192-6f86f40011cb` | 11288 | 11/25 14:47:18.074 |
| M002・1B | `20261125-235223-620-bench-vulkan-b12676-ctx8192-6f86f40011cb` | 6856 | 11/25 14:52:29.089 |
| M003・1C | `20261125-235532-805-bench-vulkan-b12676-ctx8192-02dabb1c78a3` | 2876 | 11/25 14:55:41.714 |
| M004・1D | `20261125-235849-088-bench-vulkan-b12676-ctx8192-b4c155bdcc62` | 3440 | 11/25 14:58:58.118 |
| R34R2D-M001 | `20261126-021104-218-bench-vulkan-b12676-ctx8192-b4c155bdcc62` | 16236 | 11/25 17:11:16.503 |
| R34R3B-M001 | `20261126-022429-677-bench-vulkan-b12676-ctx8192-6f86f40011cb` | 6396 | 11/25 17:24:38.479 |
| R34R3D-M001 | `20261126-022746-202-bench-vulkan-b12676-ctx8192-b4c155bdcc62` | 9232 | 11/25 17:27:58.421 |
| R34R3A-M001 | `20261126-023125-949-bench-vulkan-b12676-ctx8192-6f86f40011cb` | 15632 | 11/25 17:31:34.771 |
| R34R3C-M001 | `20261126-023441-478-bench-vulkan-b12676-ctx8192-02dabb1c78a3` | 13136 | 11/25 17:34:53.682 |
| R34-vulkan-iq3-cli-M001 | `20261126-023811-817-cli-vulkan-b12676-ctx2048-e4c08667866f` | 12084 | 11/25 17:38:24.025 |
| R34-rocm-iq3-cli-M001 | `20261126-024103-292-cli-rocm-b12671-ctx2048-f9704be4729c` | 15440 | 11/25 17:41:15.520 |

IQ2_S の生ログは `iq2s-matvec-20261125-a38ba149` の `run-{02,05,11}-A1-off.*` と `run-{03,08,10}-A1A2-off.*`。この実験の保存形式では PID、OS プロセス開始 UTC、行別の受信時刻は欠損。`command.json` の JST 起動前時刻と `result.json` の終了時刻は照合した。

## 4. 実行時ソース上の処理フロー

| 段階 | 実装と観測境界 |
| --- | --- |
| 1. 起動、DLL、バックエンド | bench の `main` は `ggml_backend_load_all()`、`llama_backend_init()`。CLI では `common_init()`、引数解析でバックエンド登録、`llama_backend_init()`、内蔵 server の `load_model`。bench 初回 stderr のデバイス行はこの一部を示す。 [Vulkan bench](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp#L2274-L2293) · [ROCm CLI](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/tools/cli/cli.cpp#L37-L50) · [引数解析](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/common/arg.cpp#L230) · [server から common 初期化](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/tools/server/server-context.cpp#L1326) |
| 2. GGUF メタデータ | `llama_model_load` が `llama_model_loader` を生成し、ファイルから GGUF メタデータとテンソル記述を読む。モデルオブジェクト生成、デバイス準備の後でモデルタイマーが始まり、hparams・vocab とテンソルのロードに進む。 [Vulkan llama.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama.cpp#L315-L372) · [GGUF ローダー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model-loader.cpp#L575-L596) |
| 3. ファイルと mmap | `AUTO` でデバイスが mmap 非対応なら `use_mmap=false`。Vulkan 統合 GPU と ROCm iGPU の capability が該当し、対象 stderr は全件実効 `load_mode = none`。`direct-io` は別モード。今回の通常重みはキャッシュ可能な Windows `ReadFile` 経路。mmap を使用する条件では `init_mappings` から `CreateFileMappingA`、`MapViewOfFile`、条件付き prefetch。`lazy.has(cur)` は別のマッピング条件だが、PLE16 の16分割 head は lazy フラグなし。 [モード解決](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model.cpp#L1727-L1767) · [Vulkan capability](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L16712-L16726) · [ROCm capability](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L6305-L6316) · [ReadFile](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-mmap.cpp#L213-L236) · [マッピング](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-mmap.cpp#L822-L859) |
| 4. テンソル配置と確保 | `llama_model_base::load_tensors` で arch tensors とバッファ型を選び、`init_mappings`、バックエンドバッファ確保に続く。`model buffer size` はウェイトバッファ確保後の報告で、データ投入前。PLE16 はファイルに格納された head-local テンソルを個別に作成し、推論グラフで `GET_ROWS` と `CONCAT`。joined→split の変換は既存 GGUF 作成時。 [ロード順序](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model.cpp#L2093-L2241) · [PLE16 作成](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/models/qwen4exp.cpp#L198-L240) · [PLE16 グラフ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/models/qwen4exp.cpp#L1421-L1449) |
| 5. データ投入と同期 | mmap 無効時は非ホストのバッファ群を先に処理。`load_all_data` はホストなら `seek`／`read_raw` で宛先に直接読み、非ホストの対応デバイスなら4本の staging（通常 I/O は各1 MiB）、イベント待ち、チャンク読み込み、非同期 `ggml_backend_tensor_set_async`、終端のイベント待ち・解放を行う。条件不成立時は CPU 一時バッファと同期転送の経路もある。`load_tensors` 復帰前に付帯情報の処理もあり、現行ログでは内部境界は得られない。 [Vulkan ローダー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model-loader.cpp#L1664-L1958) · [ROCm ローダー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/src/llama-model-loader.cpp#L1834-L1941) |
| 6. Context、KV、Graph reserve | `llama_init_from_model` から `llama_context` 構築。Context 行はコンストラクタ冒頭。モデルのタイマー起点を引き継ぎ、メモリと backend scheduler を準備して `sched_reserve` を実行する。`reserve took` は reserve 内部の計時。 [Context 初期化](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp#L163-L183) · [確保と予約](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp#L600-L620) · [sched_reserve](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp#L782-L946) |
| 7–8. Warmup と最初の eval | bench は PP8192 の全 prompt warmup、TG サブテストでは1トークン warmup。`test_prompt` は複数バッチの decode と同期、`test_gen` は各トークンで同期。`synchronize()` は scheduler 同期後、キュー済みトークンがある最初の eval で `t_load_us` を更新する。CLI は `common_init_result` のモデル／Context 生成後、`common_init_from_params` で小さな空 run（BOS/EOS 等）と同期を行う。 [bench warmup](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp#L2434-L2462) · [decode と同期](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp#L2171-L2225) · [ネイティブタイマー更新](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp#L949-L980) · [ROCm CLI warmup](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/common/common.cpp#L1512-L1554) |
| 9–10. PP/TG と解放 | bench は条件が同じモデルを再利用し、PP Context 8192 を解放して TG Context 256 を新規作成。各 `samples_ns` は実測ループの壁時計。出力・perf print 後に Context／threadpool、最後にモデルを解放する。CLI は server slot の実入力・生成のタイマーを出力し、server 終了時に Context 等を解放する。 [モデル再利用](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp#L2367-L2381) · [bench タイマーと解放](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/tools/llama-bench/llama-bench.cpp#L2503-L2553) · [ROCm CLI slot タイマー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/tools/server/server-context.cpp#L735-L795) |

Vulkan の stderr 2867～2869 は Vulkan0 の非同期 upload の選択、続いて Vulkan_Host が既定デバイス型と異なること、進捗の終端を記録する。非同期経路は Vulkan のコピー処理へ入り、staging の再使用では timeline semaphore の待機経路がある。デバイスバッファは Vulkan メモリタイプの選択を通る。WDDM の個別の residency や待機長はこのログにない。 [Vulkan バッファ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/ggml/src/ggml-vulkan/ggml-vulkan-buffers.cpp#L220) · [Vulkan upload](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L14553-L14607) · [イベント待ち](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L17499-L17511)

ROCm の HIP バックエンドは CUDA 互換 API 名の実装を持つ。通常デバイス確保は `hipMalloc`、ホスト型の pinned 確保は `hipHostMalloc`（失敗時 CPU バッファへフォールバック）。非同期経路は `hipMemcpyAsync` とイベント、同期テンソル設定は `hipMemcpyAsync` の後にストリーム待ち。CLI のログレベルでは使用した upload 分岐の Debug 行がなく、個別の pinned 確保成否は欠損。CPU モデルバッファは `read_raw(cur->data)` で埋める経路があり、約26.8 GiB の CPU バッファを pinned staging 量として解釈する根拠はない。 [HIP マクロ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/vendors/hip.h#L79-L99) · [デバイス確保](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L200-L226) · [ホスト確保](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L1771-L1801) · [同期転送](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L1079-L1085) · [非同期転送](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L3195)

## 5. タイマーとサンプルの対応

Round 1 の子 `summary.csv` の計測ツール側 Git SHA は `5447184939aa1e60dbb9228c1c512ecf78c3d761`。復旧後は `ba3341cebe37adedc1724a145aa9dea5e87b6a32`。両方とも記録上クリーン。以下は復旧後の固定参照を主に示す。 [Round 1 のマーカー記録実装](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5447184939aa1e60dbb9228c1c512ecf78c3d761/tools/evox2/benchmark/Evox2.RamDetail.psm1#L121-L174)

| 値 | 計測境界 |
| --- | --- |
| `ProcessSeconds` | 子 OS `StartTime`→`ExitTime`。ラッパーの `StartedAt` や `DurationSeconds` は計測準備・監視停止等を含む別区間。 [Measure-LlamaBench](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Measure-LlamaBench.ps1#L891-L906) · [Measure-LlamaCli](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Measure-LlamaCli.ps1#L962-L977) |
| Context／warmup 受信、Matrix | ファイルにリダイレクトされた改行完結行を、概ね500 ms ごとのループで読む。大量ログの追尾では1ポーリング1チャンクの上限がある。Matrix は起動要求 tick→最初の該当マーカー tick。下表は比較用に子の OS 開始 UTC を起点とする。stdout と stderr は独立して到着し、同時に受信したログは内部処理の同時発生を意味しない。 [Measure の追尾](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Measure-LlamaBench.ps1#L775-L782) · [マーカー抽出](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Evox2.RamDetail.psm1#L121-L174) · [Matrix 算出](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1#L444-L480) |
| ネイティブ `load time` | `llama_model_load` 内のモデルタイマー開始から、最初に eval を計上する backend 同期完了まで。従ってファイル I/O のほかに割り当て・Context 構築・warmup または初回 decode を含み得る。PP と TG の Context はモデルと同じ起点を継承し、TG 側の2行目の `load time` には先行 PP も入る。Matrix の `ModelLoadReportedSeconds` は最初の行を採用。 |
| ネイティブ `total time`、差分 | 同じモデル起点→`llama_perf_context_print`。`total − load` は上記の最初の同期→統計作成の残余。stdout 出力の処理などを含み得る。 [Vulkan 出力](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-context.cpp#L5093-L5105) · [IQ2_S 実行版の更新と出力](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/src/llama-context.cpp#L949-L980) |
| `samples_ns` | Context、warmup、depth の準備を終えてから対象ループの同期完了まで。IQ2_S は warmup OFF・pp=0・depth=0 なので TG に初回 decode と同期が入る。IQ2_S の `processSeconds` は `Get-Date`（command JSON 保存前）→`Start-Process -Wait` 復帰後で、OS のプロセス時刻との差があり得る。 [固定 bench](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/tools/llama-bench/llama-bench.cpp#L2434-L2534) · [実験起動スクリプト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/bench.ps1#L39-L52) |
| CLI 内部時刻 | stderr の相対時刻は common logger の時刻基準。行どうしの差に使用。slot の `total time` は PP と TG の和。CLI 2件の Matrix ネイティブ `load time` 欄は欠損。 [CLI ロガー初期化](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/common/common.cpp#L406-L414) |

RunId、イベントの PID／開始時刻、子 `result.json` の OS 時刻を照合した。詳細と通常監視の PID を持つ行も同じ組に一致した。詳細の tick 周波数は10 MHz。UTC と tick の相対差を PID 観測点で比較すると対象詳細ログで最大約7.4 ms。詳細 CSV の `ElapsedMs` は監視開始基準なので、プロセス開始基準への変換に使っていない。通常監視の RAM と Working Set は専用 UTC／tick 列を使用し、CPU・ディスク・ページングと WDDM は PerfMon 収集後の行時刻で表示する。PerfMon は区間レートであり、小数3桁の時刻はサンプルの識別用。ADLX は JST の `timestamp_local` を UTC に換算した。 [RAM 詳細の採取](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Monitor-Evox2RamDetail.ps1#L91-L130) · [通常監視の取得順](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Monitor-LlamaProcess.ps1#L164-L193)

RAM 使用は `PhysicalTotal − PhysicalAvailable`。Available は standby／free／zero の合計、System Cache は standby と system working set の合計で、両者に standby の重複がある。Commit と Private はコミット／私有割当の指標、Working Set は常駐ページ。GPU の WDDM Dedicated／Shared／Local と ADLX のアダプター VRAM は取得元・対象が異なる。メモリ値は GiB、ADLX は元の MB 表記、I/O は MiB/s。UMA の CPU・GPU 値を足し合わせず、欠損は空欄のまま扱った。 [Windows API の定義](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-performance_information) · [計測ツールの換算](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Evox2.Memory.psm1#L25-L45) · [PerfMon の出力元](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Monitor-LlamaProcess.ps1#L265-L299)
## 6. Vulkan Matrix のフェーズ比較

起点は OS プロセス開始。容量・Context・warmup は同じ stderr の受信時刻。表の初回 native は PP Context の `load time`。PP/TG は `samples_ns[0]` の実測秒数。

| run | 容量報告まで s | 容量報告→Context s | Context まで s | Context→PP warmup 報告 s | warmup 報告→PP 実測報告 s | 初回 native s | PP／TG 実測 s | プロセス／ラッパー s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| M001・1A | 6.220 | **167.499** | **173.720** | 2.096 | 12.680 | 188.118 | 13.002／8.522 | 210.999／216.538 |
| M002・1B | 6.722 | 45.522 | 52.244 | 2.115 | 11.669 | 65.388 | 13.031／8.528 | 88.167／94.170 |
| M003・1C | 6.187 | 45.077 | 51.264 | 2.096 | 11.190 | 64.085 | 13.051／8.528 | 86.716／101.739 |
| M004・1D | 6.158 | 44.466 | 50.624 | 2.107 | 11.157 | 63.328 | 13.063／8.528 | 85.972／99.744 |
| R34R2D-M001 | 6.206 | 44.976 | 51.182 | 2.094 | 12.680 | 65.516 | 13.021／8.652 | 88.272／107.105 |
| R34R3B-M001 | 6.218 | 45.496 | 51.713 | 2.119 | 11.167 | 64.644 | 13.036／8.660 | 87.427／96.653 |
| R34R3D-M001 | 6.195 | **59.663** | **65.858** | 2.099 | 11.165 | 78.859 | 13.040／8.629 | 101.643／119.007 |
| R34R3A-M001 | 6.160 | 44.974 | 51.134 | 2.585 | 11.168 | 64.295 | 13.053／8.659 | 87.076／95.670 |
| R34R3C-M001 | 6.193 | 45.496 | 51.688 | 2.096 | 11.154 | 64.480 | 13.039／8.656 | 87.239／105.018 |

- **M001**。GGUF 報告は開始後0.575秒（stderr 7行）、テンソルロード開始報告0.580秒（181行）。モデルバッファ報告（2865–2866行）から Context（2870行）まで167.499秒。M004 比でこの区間だけが123.033秒長い。起動要求を起点とする Matrix 値は173.732秒。PP の `total − load` は13.007秒、TG の実測は8.522秒。PP 630.051／TG 30.038 tok/s。stdout、stderr、Matrix、結果 JSON は正常終了と整合。周期監視がすべて OFF なので、当時の RAM／GPU／I/O の値は欠損。初回バックグラウンド観測では Defender や Indexer の名前はあるが、CPU 取得はアクセス拒否で帰属できない。
- **R34R3D-M001**。容量報告から Context は R34R2D より14.687秒、M004 より15.197秒長い。Matrix の Context は65.864秒。最初の Context 受信から warmup 受信まで2.099秒で、同条件の2対照と近い。内部 `reserve took` は332.15 ms（R34R2D 235.09 ms、M004 225.42 ms）で、秒単位の追加時間を説明しない。最初の native load 差は対 R34R2D で13.343秒。受信マーカーと native の起点・warmup 境界が異なる。PP 628.230／TG 29.666 tok/s は Round 3 の通常範囲。
- 両 run とも stderr 上、バッファ容量報告と Context の間に upload 選択、進捗とホストバッファ側への移行がある。進捗のドットは同一行にまとまり、それらの時刻は採取していない。遅延をロード段階内に絞れるが、GPU バッファのデータ投入、ホストへのコピー、イベント待ちのどこかは分解できない。

## 7. R34R3D-M001 の時系列

100 ms 設定、1022行、ネイティブ欠損0、実測平均107.4 ms、最大147.2 ms。通常監視40行（平均2.453秒、最大7.314秒）、ADLX 55行（平均2.000秒）。通常監視のシステム指標は40行で取得。PID GPU は6行で一部カウンター欠損。バックグラウンド CPU は取得できず、ホットスポット温度・ボード電力も欠損。R34R2D と M004 を主対照とし、再起動の影響を抑えた対照として直前・直後の Round 3 B/A/C を併用した。

| OS 開始後 | 空き RAM | Commit | System Cache | WS | Private | 観測された状態 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 起動前中央値 | 25.688 | 8.837 | 24.879 | — | — | R34R2D の起動前 Cache は9.281、M004 は23.885 GiB |
| 5.990 s | 24.873 | 86.579 | 24.878 | 0.135 | 76.959 | バッファ容量報告直前。WDDM と ADLX も急増 |
| 20.037 s | 24.431 | 87.005 | 24.796 | 0.630 | 77.458 | 通常読み取り帯域。R34R2D はこの時点までに Cache が24.521 GiBに達した |
| 47.961 s | 24.166 | 87.075 | 24.750 | 0.640 | 77.468 | R34R2D／R34R3C も同等の WS、Private、GPU 配置 |
| 51.987 s | 23.679 | 87.076 | 24.733 | 0.641 | 77.469 | 正常の D 対照が Context に進む時期でもロード中 |
| 55.046 s | 23.692 | 87.078 | 24.732 | 0.641 | 77.469 | 読み取り・GPU 稼働率は低下。コミットと WS に大きな変化なし |
| 57.303 s | **23.373** | 87.551 | 24.264 | 0.627 | 77.454 | RAM 使用ピーク8.274 GiB、17:28:55.724 UTC |
| 64.032 s | 23.769 | 87.147 | 24.663 | 0.623 | 77.448 | 空き RAM は緩やかに回復。GPU バッファは維持 |
| 66.016 s | 24.361 | 89.644 | 24.700 | 0.667 | 80.019 | 初回 Context 受信直後。KV・計算バッファ等に整合する Commit／Private 増加 |
| 75.213 s | 24.347 | **89.690** | 24.690 | 0.676 | 80.063 | コミットピーク。PP warmup 中の受信窓 |
| 106.008 s | 25.685 | 8.840 | 24.716 | — | — | 終了後。RAM・GPU とも WithinTolerance |

表の値は GiB。R34R2D／M004 の最小空き RAM は23.140／22.942 GiB、コミット最大89.787／89.351 GiB。R34R3C の最小空きは23.672 GiB。異常 run が対照よりメモリを消費し続ける形は見られない。R34R3D の57.080→57.303秒で空き23.753→23.373 GiB、WS 0.641→0.627 GiB。時刻付けされたテンソル名がなく、この小さな変化をロード内部の特定処理に帰属できない。

| 比較区間（通常監視の行時刻） | R34R3D | R34R2D | M004 | R34R3B／R34R3C |
| --- | ---: | ---: | ---: | ---: |
| 起動後7～45秒、Disk Read 中央値 MiB/s | 1,816 | 1,794 | 1,817 | 1,793／1,764 |
| Context 受信直前14秒、Disk Read 中央値 MiB/s | **58** | 1,789 | 1,642 | 1,678／1,651 |
| 同、Pages Input 中央値 pages/s | **14,757** | 457,988 | 420,679 | 430,562／423,386 |
| 同、CPU 中央値 % | 3.75 | 5.0 | 5.7 | 5.2／7.9 |
| 同、Disk Write 中央値 MiB/s | 0.02 | 0.10 | 0.04 | 0.02／0.03 |

- 7～49秒台まで読み取りとページ入力は高い。行時刻51.780秒では465.22 MiB/sと118,969 pages/s、53.785／55.780／63.094／65.094秒では54.83～61.03 MiB/sと13,909～15,672 pages/s。55.780～63.094秒の通常監視は欠測区間が長く、その間の連続性は不明。ディスク書き込みは4観測で0.01～0.04 MiB/s。
- モデルデータ投入の大半で WDDM PID Dedicated／Shared は76.892／0.491 GiB、ADLX は79,272 MB。53～65秒は ADLX が79,270～79,272 MBを保ち、GPU 稼働率3%から0%へ低下。63／65秒付近も WDDM Dedicated 76.890 GiB、Shared 0.487 GiB。Context 時期には論理使用量が増え、warmup で GPU 稼働が戻る。CPU、GPU とも遅延窓で高負荷が持続した形はない。個別キューや residency の待ちは総量では検出できない。
- `PhysicalDisk(_Total)\% Disk Time` は読み取り約60 MiB/sの行で32,333.9／44,578.0も記録した。同指標は他の run にも極端値があるため、100%を上限にした稼働率や SSD 飽和の根拠として使わない。I/O の取得元はシステム集約。非同期 upload のループでは前回のイベント完了を待ってから次のチャンクを ReadFile で読む。転送・イベント待ちが伸びる場合も、次の読み込みが遅れて単位時間あたりの読み取り量は低下し得る。既存ログでは帯域低下が原因か結果かを区別できない。 [非同期 upload の処理順](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1/src/llama-model-loader.cpp#L1878-L1914)
- 起動前の System Cache は、R34R2D より R34R3D の方が大きかった。同じ OS 起動期間の R34R3C も R34R3D と似た Cache で通常時間。Cache 総量だけでは GGUF の温冷を判断できない。 [通常監視カウンター定義](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/ba3341cebe37adedc1724a145aa9dea5e87b6a32/tools/evox2/benchmark/Monitor-LlamaProcess.ps1#L110-L137)

## 8. ROCm CLI の RAM 逼迫

RAM 詳細291行、ネイティブ欠損0、平均254.1 ms、最大384.7 ms。通常監視26行、平均2.494秒、最大6.134秒、ADLX 37行。起点は 17:41:15.5195646 UTC（02:41:15.5195646 JST）。

| OS 開始後 | 空き RAM | Commit | System Cache | WS | Private | フェーズ |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 起動前中央値 | 25.710 | 8.839 | 24.627 | — | — | Windows 可視31.647 GiB |
| 2.040 s | 24.657 | 86.151 | 25.008 | 0.710 | 76.712 | バッファ容量報告後。GPU データ投入側と整合 |
| 29.907 s | 24.309 | 86.146 | 25.018 | 0.710 | 76.712 | GPU 稼働率約10～11%、ADLX 51,058 MB、まだ WS は横ばい |
| 31.422 s | 23.227 | 86.049 | 24.005 | 1.763 | 76.649 | 31.169秒までは WS 0.710 GiB。ここから WS の段階的増加を観測 |
| 34.994 s | 18.942 | 86.375 | 19.724 | 5.677 | 76.649 | GPU 稼働率は低下。CPU 宛先の読み込みと整合 |
| 40.106 s | 11.026 | 87.576 | 11.808 | 12.380 | 76.647 | WS 増加。空きと Cache が減少 |
| 48.005 s | 4.276 | 86.056 | 4.953 | 20.762 | 76.647 | 逼迫直前 |
| 49.805 s | **0.0064** | 87.060 | 0.699 | 24.115 | 76.647 | 最小6.563 MiB、使用最大31.641 GiB、17:42:05.3247316 UTC |
| 51.069 s | 0.409 | 86.051 | 1.040 | **24.186** | 76.647 | WS 最大。Context より前 |
| 55.875 s | 1.237 | 86.369 | 1.089 | 20.516 | 76.647 | WS が下がり空きが一時回復。58秒台に再度低下 |
| 59.921 s | 2.937 | 87.712 | 1.926 | 22.050 | 77.648 | Context／reserve／warmup 各行を同じ追尾回で受信 |
| 62.702 s | 2.700 | **87.935** | 1.704 | 22.150 | 77.854 | 短文 PP/TG 終盤 |
| 63.964 s | 14.447 | 87.001 | 1.704 | 11.166 | 76.942 | 結果報告後の解放。WS と使用 RAM が急減 |
| 65.981 s | 27.461 | 8.892 | 1.739 | — | — | OS 終了65.747秒の後。ADLX は67.191秒で534 MB |

GiB。内部ログの `constructing llama_context` 59.598秒、`reserve took` 59.708秒、warmup 59.709秒、slot の統計と解放開始62.763～62.768秒は logger 相対時刻。外部受信では Context が OS 起点から59.921秒、起動要求起点で59.929秒。容量報告→Context は ROCm の内部時刻で58.022秒、Vulkan CLI は43.923秒。OS 時刻位置の誤差を避けるため、差は同じ logger 内で計算した。

### しきい値を下回った観測区間

下表は連続する有効サンプルの最初と最後（OS 開始から秒）。点は単独サンプル。例えば <1 GiB の51.069～55.607秒の前後に、基準以上の50.816秒と55.875秒の行がある。閾値を通過した厳密時刻や単独点の継続時間は推定しない。

| 空き RAM | 行数 | 観測点・区間 s | 単調増加 tick での最長観測幅 |
| --- | ---: | --- | ---: |
| <1 GiB | 24 | 49.805–50.057、50.562、51.069–55.607、58.149–58.401 | 4.537 s |
| <512 MiB | 13 | 49.805、51.069–52.079、52.835–53.087、53.589、54.093、54.596、55.607、58.149 | 1.010 s |
| <128 MiB | 4 | 49.805、51.572–51.827、53.589 | 0.254 s |

通常監視の最小は0.084 GiB（約86 MiB）。該当行の時刻53.793秒に対して RAM 採取自体は52.772秒。100／250 ms の極小値と通常行の極小値は同時刻で比較しない。

### 処理と配置の対応

- 31秒台から WS が23 GiB以上増える間、Private は約76.65 GiB、コミットは概ね86～88 GiBですでに確保済み。Cache は25 GiBから1 GiB前後まで低下。CPU 側の重みページへの書き込み・常駐化と standby の消費に整合する。WS が後半で24.186→20.5 GiB付近へ下がり、Private が横ばいの所見は常駐量の変化を示す。トリミング・圧縮・スワップの区別に必要なデータはない。
- メモリ逼迫中に WDDM PID Dedicated／Shared は約49.321／0.494 GiB、ADLX は51,039 MB付近で横ばい。GPU 使用率は37～59秒台の ADLX で0%。Vulkan CLI ではモデル投入中に Dedicated／Shared が76.892／0.491 GiB、ADLX 約79,272 MB、Working Set は約0.63 GiBで推移。Vulkan CLI の最低空き23.640 GiB、最大コミット88.746 GiB、Context 受信50.161秒、プロセス53.670秒。ROCm の対応値は6.563 MiB、87.935 GiB、59.929秒、65.747秒。両件とも監視上は終了後 RAM・GPU が WithinTolerance。
- ROCm のモデルバッファは CPU 27,465.94 MiB＋ROCm0 50,191.17 MiB＋ROCm_Host 497.31 MiB。Vulkan は Vulkan0 77,657.05 MiB＋Vulkan_Host 497.31 MiB。両件とも `offloaded 49/49 layers` だが、モデル全体のテンソル配置はバッファ行を見て判断する。COMMON-001 の IQ4_NL 分割 head は幅160。ROCm の `GET_ROWS` は IQ4_NL に256の倍数を要求し、配置時の演算可否確認で CPU 側に置かれる。CPU 宛て `ReadFile` がこの領域を埋める順序と時系列が合う。現行ログにテンソル別の時刻はない。 [配置時の演算可否確認](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/src/llama-model-loader.cpp#L1148-L1158) · [ROCm の幅制約](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/35818246a27521327e627e8f323e5f3a6386f8f9/ggml/src/ggml-cuda/ggml-cuda.cu#L6473-L6508)
- 通常監視の行時刻33.652秒は読み取り1,709 MiB/s、Pages Input 約438千/s。その後も読み取り高値が間欠的に続いた。49.777秒の Page Faults は約879千/s、53.793秒は Disk Read 1,712 MiB/s、Pages Input 約421千/s、Disk Write 97.92 MiB/s（局所ピーク）。これらはシステム値。`Pages Input/sec` と `Page Faults/sec` だけではページファイルを識別できない。対象の主経路は `load_mode=none` の cached ReadFile。Windows のファイルキャッシュ関連のページ入力を含み得る。Page Output、Page Writes、Paging File 使用量、ファイル別 I/O はこの run の監視にない。
- 既存 UMA 64→96 GiB 検証では、Vulkan PLE16 64k の PP 中 PID Dedicated／Shared 中央値が62.773／17.134→79.445／0.561 GiBへ変わった。Original は両 UMA で52.479／0.570 GiB、CPU モデルバッファ約26.8 GiBを維持し、UMA 96 GiB で最低空き約14 MiB。ROCm PLE16 は同じモデルバッファ配置のまま、UMA 96 GiBの64kで最低0.168 GiB、Original 64kも0.492 GiB。今回の短入力でも CPU 配置によるロード時の圧力が観測されており、コンテキストの長さだけで説明できない。 [Stage 1 の配置・比較](../B12651-STAGE1-COMMON001-20261124.md#uma96gb-再計測2026-11-24-jst)

## 9. IQ2_S MatVec 実験の2件

時間は秒。`processSeconds` は実験ラッパー、native 2列は stderr、TG256 は stdout の `samples_ns[0]`。

| run／条件 | JST 起動前 | プロセス | native load | native total | total − load | TG256 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| run-02／A1 | 11/25 00:49:14.164 | 63.606 | 53.412 | 61.921 | 8.509 | **11.627** |
| run-05／A1 | 11/25 00:52:21.549 | 59.537 | 50.021 | 58.492 | 8.471 | 8.540 |
| run-11／A1 | 11/25 01:00:04.726 | 59.469 | 50.075 | 58.548 | 8.473 | 8.538 |
| run-03／A1+A2 | 11/25 00:50:18.988 | 59.577 | 50.226 | 58.670 | 8.444 | 8.783 |
| run-08／A1+A2 | 11/25 00:55:26.266 | **154.163** | **143.980** | 152.426 | 8.446 | 8.510 |
| run-10／A1+A2 | 11/25 00:59:03.020 | 60.594 | 50.574 | 59.017 | 8.443 | 8.506 |

- **run-02**。他の A1 2件より TG256 は約3.09秒長い。`total − load` の差は約0.04秒。最初の eval 完了までの TG 冒頭に追加時間が入ったと推定する。1トークンごとの時刻がなく、パイプライン生成、初回 dispatch、同期などの寄与は分離できない。
- **run-08**。run-10 よりプロセス +93.568秒、native load +93.405秒、TG256 +0.004秒。追加時間の大部分は TG タイマー前にあると推定する。受信時刻付きの容量・Context 境界がなく、M001／R34R3D と同じ細区間に帰属させることはできない。
- 実行版 `a38ba149d` と b12676 の関連コードを比較すると、`src` と `tools/llama-bench` の差分は空。Vulkan 差分は IQ2_S shader とパイプライン登録の2ファイル。A1/A2 は IQ2_S の MatVec 特殊化を切り替え、モデル全体の量子化は IQ3 PLE16。各構成に正常例があり、定常 TG の変化が2種の遅延を一律に説明する証拠はない。実験中の運用者操作は報告なし。手動時の一時的 RAM 上昇は運用者の観測で、実験 run と対応する時系列は欠損。 [特殊化の選択](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L3328-L3340) · [既存実験記録](../iq2-s-vulkan-matvec-20261125/README.md#低速2件の生ログ再解析)

## 10. 関連の障害、OS 稼働時間、TG 差

- **M005**。旧 Round 2 D。PID 14780、00:02:12.444 JST 起動。Context 00:03:03.673、PP warmup 00:03:05.771 JST を受信。原本の stderr は `reserve took 230.45 ms` と PP warmup、`set_n_threads` まで。RAM 詳細の最終行は00:03:06.455 JST。最大使用8.862 GiB、最小空き22.785 GiB、最大コミット89.334 GiB。ネイティブ結果 `llama-bench.json` は0バイト。原本の結果から速度は集計せず、正常対照に代替の R34R2D-M001 を使用した。SSH・RDP・ping・画面・USB キーボードの無応答と強制終了後の復旧は既存障害記録による。 [M005 障害記録](INCIDENT-20261126-M005.md)
- **イベントの再確認**。11/25 23:45～11/26 02:44 JST を対象に、System の警告以上と選択した起動・GPU・枯渇 ID、Application の警告以上と WER 1001 を検索。System の該当15件は復旧時刻帯（00:21～00:23 JST）。当該ロード窓に検索範囲で新規 GPU リセット・枯渇記録は見つからなかった。Application の該当119件は WER 1001。再処理済み報告の扱いは既存記録に従い、WER の記録時刻だけで新規発生と判断しない。Kernel-General 12（RecordId 69404）の StartTime と Kernel-Power 41（69439）を再確認。6008 の23:53:03は後続正常 run と矛盾するため、フリーズ時刻には採用しない。復旧後 run のゲートも重大イベント0件だった。
- **AMD External Events Client Module**。Application Error 1000 と RDP LocalSessionManager の再接続（25）を再照合した。既存障害記録の3件は同じ `atieclxx.exe`、`32.0.31041.1004`、`0xc0000005`、`0x28870`。11/23 11:53:16.935（記録42216、起動25分19秒後、RDP 再接続約9.54秒後）、11/24 19:15:40.249（42819、起動1分31秒後、約25.29秒後）、11/25 21:50:04.270（43283、起動1時間17分12秒後、約57分4秒後）。近接した日もあるが、11/25は約57分離れている。その停止の後に M001～M004 は完走している。M005 やロード遅延への直接の関連は未確認。 [AMD 停止・RDP の運用記録](INCIDENT-20261126-M005.md#amd-external-events-client-module)
- **OS 稼働時間**。旧 M005 の最終 RAM 行は OS 起動約3時間30分14秒後。運用者の所見に対して稼働時間別の run 数・観察時間がなく、発生率は出せない。高速スタートアップは既存確認と復旧後結果で無効。強制終了の前に対応する正常シャットダウンがなく、停止期間は欠損。OS 停止時間から物理電源 OFF 時間は決まらない。
- **TG とクロック**。既存の全構成平均 TG は30.024→29.594→29.592 tok/s（復旧後約1.44%低下）。監視なし A も同方向。同一ラウンド内の監視条件差は PP 最大0.25%、TG 最大0.35%。PP の VRAM 平均は968.8／965.8／967.4 MHz、TG は999.3／999.6／999.1 MHz。過去の PP 中約884 MHz の低下は短い PP8192 では見られず、長い Context では未確認。復旧後のタスクマネージャと管理者 PowerShell の影響は未検証。ロード異常が PP/TG の定常差を説明する観測は得られていない。 [作業3-5の再集計](BENCHMARK-MATRIX-ROUNDS-B12651.md#gpu-クロックと再起動前後の速度) · [過去のクロック記録](../EVOX2-UNEXPECTED-WINDOWS-RESTART-INCIDENT-LOG.md)

## 11. 原因仮説の優先順位

Vulkan のロード遅延で最も情報量が大きい R34R3D を基準に並べた。ROCm の RAM 逼迫と IQ2_S run-02 の優先度は別記する。

| 順位・仮説とフェーズ | 支持するログとソース | 説明しにくい観測・残る疑問 | 確からしさと次に識別する値 |
| --- | --- | --- | --- |
| 1（同順位）. A ロード終盤の ReadFile、SSD／ファイルキャッシュ | R34R3D の読み取り・ページ入力が通常ロード終盤の水準から低下。`load_all_data` の ReadFile と整合 | 前半の帯域は対照と類似。総 Cache が同等の R34R3C は通常。総 I/O 低下は別の待ちの結果でも起きる。実効 mmap は無効 | E と同じ優先度。I/O 自体が原因かは未確定。データ量と ReadFile 累積／最大待ちを計測し、必要時に対象ファイル別 I/O |
| 1（同順位）. E 転送、ホスト staging、イベント待ち（Vulkan／HIP） | Vulkan ログが async upload を選択。ReadFile と staging 再利用待ちは交互に起き得る。R34R3D 後半の GPU 使用率も低下 | バッファ容量報告までは対照と同等。GPU 総量の変化は小さい。HIP 逼迫は pinned 確保の有無だけでは説明できない | A と同じ優先度。`ReadFile`／イベント再使用待ち／最終 drain を別集計し、ホストバッファ群と GPU 群の開始・終了を計時 |
| 3. G 実行順、温冷キャッシュ、OS／バックグラウンド | M001 は Round 1 先頭。M001 の事前スナップショットに Defender／Indexer | R34R3D は Round 3 の2件目で前後は通常。Cache 総量では GGUF のキャッシュを識別できず、背景 CPU は欠損 | 低～中。OS 起動期間と GUI を固定し、順序と開始前の状態を記録。必要時に対象プロセス別 I/O |
| 4. C WDDM／UMA residency | 既存 UMA 64→96 比較で Dedicated／Shared の配分が変化。大容量バッファと Vulkan 転送は関係し得る | R34R3D の遅延窓に Dedicated／Shared／ADLX VRAM の大きな段差なし。WDDM の集約値は eviction や再常駐を直接示さない | 低。転送待ちが増えた場合に絞り、GPU メモリ管理の既存ログまたは短い DxgKrnl のトレース |
| 5. D PLE16 のテンソル配置と副次バッファ | CPU／GPU の PLE 配置差はソース、マニフェスト対応 stderr、過去の比較で一致。ROCm の WS 増加に強く整合 | Vulkan 異常／正常とも同じ PLE16 と配置。対象 GGUF は事前変換済み。共通の実行時 split 変換で15／123秒を説明する証拠なし | ROCm 逼迫の説明として高、Vulkan のばらつきとして低。群別ごとの処理時刻・バイト数で確認 |
| 6. B 物理 RAM 逼迫、圧縮、トリミング、ページファイル | ROCm の空き6.563 MiB、Cache と WS の反対方向の変化、書き込みの局所ピーク。M001 と IQ2_S は採取なし | R34R3D の空きは全観測で23 GiB超。ROCm は完走し Context へ進んだ。空き低下の開始は CPU バッファ投入と整合し、遅延の原因・増幅かは分からない | ROCm 逼迫は確定。Vulkan R34R3D の説明として低。必要時にページ出力、ページファイル I/O と hard-fault 対象を照合 |
| 7. F DLL、パイプライン生成、初回 eval | run-02 の追加時間は初回 eval 付近。Vulkan ソースに起動時の準備と on-demand pipeline 作成の双方がある | M001／R34R3D は GGUF と容量報告までは通常で、遅延が Context より前。Context→warmup は通常。run-08 の TG 自体は通常 | run-02 の区間推定は強いが機序は低。再発時に first decode 前後と pipeline 作成／最初の同期の時間を取得。 [Vulkan pipeline 作成](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L760-L855) |
| 8. H ドライバ／GPU の一過性状態 | M005 と atieclxx.exe 停止の履歴。WDDM／Vulkan 側の待ちを観測した可能性は残る | 両 Vulkan 遅延 run は完走し TG は通常。選択したイベントと終了監査にロード時の重大異常なし。M005 は PP warmup 開始付近 | 低・因果未確認。既存イベント監査を維持し、GPU 同期待ちを計測して必要時に関連トレース |

## 12. 確定・推定・不明

- **確定**。Vulkan 2件は容量報告→Context の受信間隔が長い。R34R3D ではこの区間が延びた間も空きが23 GiB超。ROCm のロード後半には複数の有効行で逼迫し、終了後 RAM／GPU は回復。実効ロードモード、モデル配置、native とラッパー等の計時境界は固定ソースとログから確認した。
- **推定**。R34R3D の通常帯域区間は対照に近く、終盤に読み取りまたは転送・同期待ちを含む低活動の区間が追加された。ROCm の逼迫は CPU 側の PLE 重み常駐化が主因と考えられる。IQ2_S の run-02 は初回 eval 付近、run-08 は TG 計測前。
- **不明**。M001 と run-08 の I/O・RAM・GPU 状態、各 Vulkan 遅延の共通原因、R34R3D で末尾を延ばした具体的な待ち、ROCm のページアウト／圧縮／トリミングと処理時間への寄与、M005・AMD 停止・TG 差との因果。物理 RAM 逼迫は R34R3D の発生に必要だったとはいえず、ROCm の逼迫だけで完走可否は決まらない。

## 13. レビュー後の最小追加調査案

| 優先 | 条件と必要反復数 | 判別する仮説と取得値 | リスクと判断点 |
| --- | --- | --- | --- |
| 1 | 既存 b12676／IQ3 PLE16／PP8192＋TG256／warmup ON を固定。通常2秒、ADLX 2000 ms、RAM 詳細250 ms。初期は独立した最大3件、1件ずつ | A/E/G/B。容量→Context を主指標とし、末尾の Read MiB/s、Pages Input、WS、Private、Dedicated／Shared と ADLX を同時に取得。実行順を記録。短い変動の取りこぼしが判別を左右する場合のみ100 msを検討 | 実行負荷と既往のフリーズ。各 run 後の回復・イベント監査で停止可。初期3件で再現しなくても問題の解消とは判断しない。反復数の上積みはレビュー |
| 2 | 基準3件の再現有無にかかわらず診断機能の設計・実装を候補に残す。実装・ビルドと診断 run は後続レビュー。同一 OS 期間で診断 OFF/ON を照合 | 容量報告後、非ホスト／ホストの各 `load_all_data` の出入口で `ReadFile`、upload、再使用イベント待ち、最後の drain の回数・バイト数・累積／最大待ちを分ける。最初の Context と first decode を区間確認用に少数記録 | ソース変更・ビルド検証が別途必要。チャンクごとの出力は I/O と時間を乱すため、群ごとの集約を想定。異常を捕捉した時点で追加反復の要否を再評価 |
| 3 | 優先2で OS 側の待ちが残った場合だけ短いトレースを1件。対照が必要なら同条件1件 | ReadFile が主ならファイル別 Read／hard fault、必要時にページファイル。GPU 待ちが主なら DxgKrnl の割当・eviction・スケジュールを対象。A/B/C/E/H の帰属 | トレースの負荷、出力サイズ、権限、記録内容を事前確認。採取区間をロード終盤に絞る |
| 保留 | ROCm、Original／PLE16、warmup ON/OFF、起動直後と後続、その他の変更 | 既存データで ROCm の配置差を確認済み。Vulkan で初回 eval の遅延だけが再発した場合には、短い条件で warmup ON/OFF 各3件を候補にする。温冷は自然な実行順で先に評価 | ROCm は既存 run で6.6 MiBまで低下しており、再観測の安全条件を先にレビュー。Original や OS 再起動・キャッシュ操作を一括で組み込む必要はない |

Adrenalin 26.8.1、ROCm 10.0.0、UMA 設定および Performance を維持。次回はタスクマネージャを閉じ、OS 起動期間、稼働時間、起動方式、GUI／RDP、背景条件を記録する。承認済みモデルと Context に限定し、UMA 96 GiB の Original IQ3 256k は両バックエンドで対象外。SSH の Event Log Readers 経路を維持し、SSH 切断、GPU 異常、重大イベント、回復・確認の失敗時は後続を開始しない。 [計測規則](BENCHMARK-RULES.md) · [復旧ゲート](INCIDENT-20261126-M005.md#復旧確認再開条件)

## 14. 制約と欠損

通常監視は区間最長で6～7秒空く。Detailed RAM は CPU 側のサンプルで、GPU residency と I/O を同じ周期では測っていない。Disk Time の極端値、ADLX の未対応値、PID GPU の部分取得、背景 CPU の権限制約がある。Page Output／Page Writes、pagefile と GGUF のファイル別 I/O、圧縮量、WDDM eviction、チャンク単位の read／copy／wait、Vulkan bench の内部ログ時刻は欠損。保存データから判断し、欠損値の補完や再計測は行っていない。詳細監視の回復は選択指標が許容範囲に戻ったことを意味する。ROCm の終了後 Cache は開始前の約25 GiBから約1.75 GiBになっており、同じキャッシュ内容への回復は確認できない。

### 再集計用の成果物

[オフライン再集計手順とスクリプト](b12651-model-load-analysis-20261126/README.md)で、フェーズ受信境界、RAM・通常監視・ADLX の時刻対応、しきい値区間、実行物の識別情報と低速6件のログ照合を再現できる。派生表はスクリプトの標準出力と本書の表に残した。過去のまとめ用 CSV は既存の実機索引にある。

## 15. 終了時の状態

GitHub の2参照と専用 clone の HEAD・追跡参照を終了時に再照合した。開始時と同じ `3bc6d1f`／`f500e9b`、専用 clone はクリーン、ahead／behind は双方0／0。Matrix worktree は `d8dd87128d726e45612f18480dd24b07f243f143` のままクリーン（追跡先と0／0）。参照・ログ取得用の ThinkPad 一時 clone は main 基準の detached HEAD でクリーン。

EVO-X2 は SSH で既存 Git、ログ、マニフェスト、イベントを読み取った。製品・計測・ビルドソース、設定、モデル、既存ログ、M005 原本と保全コピーに対する変更はない。追加モデルロード、推論、ベンチマーク、ビルド、GPU テスト、コミット、push は実施していない。解析時の成果物は ThinkPad の Markdown ドラフト。レビュー用に同じ内容のコピーを EVO-X2 専用 clone の `docs/evox2/automation/B12651-MODEL-LOAD-INVESTIGATION-20261126.md` に置き、SHA-256 `178198bc0909a5ceb473985c9d001e1c359fdaad4295729c8d99929c1ef4fdaa` を照合済み。調査時、このレビュー版は専用 clone の未追跡ファイルとして保存した。確定版は GitHub main の本書に記録した。
