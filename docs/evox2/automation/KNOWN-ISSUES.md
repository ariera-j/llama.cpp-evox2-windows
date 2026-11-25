# 既知のビルド・実行時の問題

| 症状 | 運用上の扱い |
|---|---|
| ROCm の `FLASH_ATTN_EXT` スイープ | 2026-10-22、DKQ=64 と logit-softcap のケースが HIP の trap 経路に達し、launch failure、画面と RDP の応答停止、Windows `LiveKernelEvent 141` が観測された。trap と watchdog の因果関係は未確定。両バックエンドとも `test-backend-ops.exe` は自動実行せず、`-RunBackendTest` は使わない。 |
| Vulkan の長コンテキストで device lost | 2026-11-03 の 128k IQ4 ベンチマークで `VK_ERROR_DEVICE_LOST` と Windows `LiveKernelEvent 141` を確認。障害箇所の GPU カーネルは未確定。自動再試行や Windows TDR 設定の変更は行わず、実行条件とログを保存して停止する。 |
| Web UI の取得・検証失敗 | build 12037 で `b12037` のチェックサム取得が HTTP エラーになり、`latest` 展開後も必須の JS/CSS/workbox パターンが揃わず `llama-ui-assets` が失敗した。`LLAMA_BUILD_UI=OFF` と `LLAMA_USE_PREBUILT_UI=OFF` の両方を configure に指定する。失敗残骸の退避が承認されている場合は、当該ビルド内の `tools\ui\dist` と `.ui-stamp` だけを確認し、同じビルド内の一意な場所へ移す。 |
| CMake/Clang の警告 | Vulkan の `ccache not found`、Windows の pthread 探索失敗に続く `Found Threads: TRUE`、Clang の signed/unsigned 比較や `httplib.h` の言語拡張警告は成功ビルドでも観測された。ログに残し、終了コードと生成物で判定する。新規の警告、compiler error、ツールの版違いは個別に確認し、フラグや SDK を勝手に変えない。 |
| VS18 / MSVC 14.51 と TheRock | 過去に HIP の `<cmath>` オーバーロード衝突が発生した。この運用では VS2022 / MSVC 14.44 を使用する。 |

詳細は [ROCm の障害記録と警告](../BUILD-ROCM-WINDOWS.md)、[Vulkan device-lost 記録](../R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md)、[Gemma 4 Global FA の研究記録](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/V1-GEMMA4-GLOBALFA-RGP-GATE-20261121.md) を参照する。研究記録の計測手順を自動スモークには組み込まない。

## 2026-11-23 物理メモリ取得のみの修正と推論再検証

グループ変更後、当時の main `633c874874dd8dc6af603b9e36ac8c5ff236b0f3` で WMI の Win32_OperatingSystem は 0x80041003 で失敗した。ADLX VRAM と PerfMon は個別取得できた。この版の再試験は WMI エラーのため開始前に中止した。対象スクリプトの blob と SHA-256 は [再確認の記録](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/729ec6256ac6ecec5a219ee19876c2f787e1fcb7/docs/evox2/automation/KNOWN-ISSUES.md#2026-11-23-グループ変更後の-main-版モニター再確認)。

その後、Monitor-LlamaProcess.ps1 の物理 RAM 取得だけを GetPerformanceInfo に変更し、総ページ数と空きページ数をページサイズでバイトに換算して既存の GiB 列に出力する。API 失敗時は Win32 エラー番号を表示する。PerfMon、CSV 53 列、Measure-LlamaCli.ps1、ADLX は従来のまま。

PowerShell 5.1 の構文検証と UTF-8 BOM を確認した。10秒の PowerShell プロセスを監視した結果は終了コード 0、53 列・10 サンプル。最初の行で物理使用 8.009 GiB、空き 55.639 GiB、コミット 10.286 GiB、ページング3項目、GPU アダプターの Dedicated / Shared を取得した。

既存 b12037（9de09c610）、UMA 64 GB、Context 4096、全層 GPU、CPU MoE 0、batch 2048、ubatch 1024、threads 4、KV f16、Flash Attention auto、MTP OFF。AllocationOnly の固定短文を各1回、表の順で実行した。生成数は実測で、上限は32トークン。

| バックエンド | モデルキー | 終了コード | GPU 層 | 生成 | リソース / PID 別 GPU メモリ取得 | ADLX VRAM 取得 | ADLX VRAM 最大 (MiB) |
|---|---|---:|---:|---:|---:|---:|---:|
| Vulkan | UnslothOriginal | 0 | 49/49 | 2 | 22 / 22 | 27/27 | 52066 |
| ROCm | UnslothOriginal | 0 | 49/49 | 2 | 20 / 20 | 24/24 | 51682 |
| Vulkan | UnslothPle16 | 0 | 49/49 | 2 | 22 / 22 | 27/27 | 65336 |
| ROCm | UnslothPle16 | 0 | 49/49 | 2 | 15 / 15 | 18/18 | 51684 |
| Vulkan | AgentionRocmFp4FastPle16 | 0 | 49/49 | 2 | 34 / 34 | 44/44 | 64811 |

以下はサンプルごとの最大値。ページ入力やフォールトにはモデル読込中のファイルマッピング由来の値が含まれ得る。

| バックエンド / モデルキー | RAM 使用 / コミット (GiB) | Pages Input / Page Reads / Page Faults (毎秒) | Adapter Dedicated / Shared (GiB) | PID Dedicated / Shared (GiB) |
|---|---:|---:|---:|---:|
| Vulkan / UnslothOriginal | 35.88 / 89.50 | 642989.3 / 1566.0 / 889386.4 | 50.84 / 0.60 | 50.37 / 0.54 |
| ROCm / UnslothOriginal | 36.35 / 89.37 | 702246.7 / 2446.2 / 876214.2 | 50.49 / 0.68 | 50.02 / 0.61 |
| Vulkan / UnslothPle16 | 24.13 / 88.62 | 549872.2 / 1646.4 / 1312542.2 | 63.81 / 14.12 | 63.33 / 14.05 |
| ROCm / UnslothPle16 | 36.19 / 88.45 | 480096.1 / 1811.5 / 2181268.2 | 50.47 / 0.63 | 50.00 / 0.56 |
| Vulkan / AgentionRocmFp4FastPle16 | 35.90 / 101.40 | 713087.2 / 1593.1 / 1514349.2 | 63.29 / 26.54 | 62.82 / 26.47 |

生ログは EVO-X2 の `C:\llama-build\_logs\codex` 以下。各推論ディレクトリに stdout、stderr、resources.csv、gpu-metrics.csv、result.json がある。

- 単体監視 `monitor-physical-smoke-b050f480c0ca40ef975b881eec02c8d9`
- 集計 `physical-memory-inference-43a177847881419eabb149c0b6c2e9d9.jsonl`
- Vulkan / UnslothOriginal `20261123-184107-672-cli-vulkan-b12037-ctx4096-c1033772a5a6`
- ROCm / UnslothOriginal `20261123-184356-581-cli-rocm-b12037-ctx4096-0e6201be05e2`
- Vulkan / UnslothPle16 `20261123-184639-993-cli-vulkan-b12037-ctx4096-311ea7675402`
- ROCm / UnslothPle16 `20261123-184929-142-cli-rocm-b12037-ctx4096-0af5622c8dad`
- Vulkan / AgentionRocmFp4FastPle16 `20261123-185200-026-cli-vulkan-b12037-ctx4096-5fb75dac2f5b`

## b12651 Vulkan で確認したビルド上の制約

| 症状 | 対応 |
|---|---|
| OpenMP 22.1.8 と Clang 20.1.8 の組み合わせを configure が拒否 | VS2022 x64 Native Tools は維持し、Vulkan のコンパイラに VS2026 付属 Clang 22.1.3 を明示する。 |
| CPU 全バリアント ON で Sapphire Rapids の AMX `mmq.cpp` が約7時間32分継続 | 当該ジョブは停止済み。初期ベースラインは `-CpuAllVariants OFF` とし、Ninja に Sapphire Rapids がないことを確認した。長時間化を検出したら実行中のコマンド、Ninja 進捗、PID、CPU 時間、メモリ、ログを保存して原因を調べる。 |
| 長いディレクトリ名で Vulkan シェーダー生成ツールの入れ子の MSVC テストがパス長制限を超過 | clone のパスを維持し、短い未使用のビルド名を選ぶ。`build-b12651-vk` への短縮で解消した。 |

詳細な失敗と成功の記録は [b12651 ベースライン](UPSTREAM-B12651-20261124.md) にある。

## Vulkan IQ3 PLE16 の初回 eval・モデルロード付近の遅延（2026-11-25）

IQ2_S MatVec 実験の Logger OFF TG256 で、A1 初回の run-02 は TG 計測が11.627秒に延びた。最初の eval 完了後に相当する `total − load` は8.509秒で、他の A1 run と近い。併用版 run-08 はプロセス154.163秒、`load time` 143.980秒、TG 計測8.510秒で、追加遅延の大部分は TG 開始前とみられる。両現象の共通原因は不明。

運用者による過去の手動計測でもモデルロード付近の異常低速が複数回あり、一時的な RAM 使用量増加が観測されている。今回の12 run 中に運用者の実機操作はなかった。リソースログがなく RAM 使用量と遅延の関係は未確認。環境改善後に別タスクで原因を調べる。 [生ログ再解析とタイマーの境界](../iq2-s-vulkan-matvec-20261125/README.md#低速2件の生ログ再解析)
