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

## Vulkan IQ3 PLE16 の PP warmup 付近のハードフリーズ（2026-11-26）

作業3-4の M005（Stage 2 b12676、UMA 96 GiB、PP8192／TG256）で、通常監視と RAM 詳細監視が PP warmup 開始報告の直後に途切れ、結果 JSON は空だった。RDP、ping、SSH、物理ディスプレイと USB キーボードの反応が失われ、強制終了後の起動で復旧した。フリーズ直前の観測範囲で RAM、コミット、GPU メモリに顕著な異常はなく、直接原因は未特定。AMD External Events Client Module の停止との因果関係は未確認。

無人再開には新規重大イベントの確認経路が必要。復旧後の SSH ユーザーでは System チャネルがアクセス拒否だったため、残りの計測は開始前に停止した。M001 のロード遅延は独立した作業4の資料として保持する。 [障害記録](INCIDENT-20261126-M005.md)

2026-11-26、運用者による Event Log Readers の追加後、新規 SSH で System／Application の読み取りを再確認した。障害前の測定と復旧後の測定は別ラウンドとして保持する。 [SSH のイベントログ読み取り](EVOX2-ENVIRONMENT.md#ssh-のイベントログ読み取り)


## 作業4で参照する独立した観測

再起動前後の TG 速度差、M001 と Round 3 D のロード遅延、ROCm 短時間の物理 RAM 逼迫は調査候補として保持する。M005 のハードフリーズと AMD External Events の停止との因果関係は未確認。 [run ID・計測条件・ログ](BENCHMARK-MATRIX-ROUNDS-B12651.md#ram-詳細監視と作業4への引き継ぎ)

## 登録 worktree の CMake Git index 警告

Windows の `.git` ファイルがドライブ付き絶対パスを指す場合、CMake がこれを相対パスと解釈し `Git index not found in git repository.` を出す場合がある。`git rev-parse --path-format=absolute --git-path index` で Git が解決した実体を確認する。明示 configure と `BuildOnly` の再生成、CLI の埋め込み SHA、`BuildIdentity=Verified` を照合する。短い worktree と出力名を使い、Windows の長いパス設定は変更しない。 [w54 の両バックエンド検証](BUILD-VALIDATION-20261126.md)

## 2026-11-26 Adrenalin 更新後の backend-op 数値テストの扱い（ソース再確認）

Adrenalin 26.8.1 から 26.11.2（表示ドライバー 32.0.32029.2010）へ更新。TheRock 10.0.0、Vulkan SDK/Loader 1.4.357.0、UMA 96 GiB は維持した。更新前後の6条件の推論比較は完了し、更新後の計測中に GPU リセットは観測されなかった。ただし backend-op の全条件テストや過去の障害条件の再実行はしていない。推論の正常終了は backend-op の安全性や障害解消の証拠ではない。[更新前後の比較](ADRENALIN-UPDATE-COMPARISON-20261126.md)

### 既知の FLASH_ATTN_EXT 障害と現行コード

2026-10-22 の ROCm の障害では DKQ=64、logit-softcap 有効のケースが上位の対応判定を通過し、GPU カーネルの NO_DEVICE_CODE / trap に到達した。HIP launch failure、LiveKernelEvent 141（WATCHDOG-20261022-0244.dmp）、画面・RDP の応答停止が観測された。trap と watchdog の直接の因果関係はダンプ解析で確定していない。[当時の記録](../BUILD-ROCM-WINDOWS.md#backend-tests)

現行製品 SHA `9ae819d5be4fe9861d2aa8547983aed801c437ac`（upstream b12651 ベース、b12696 のビルド元と推論ソース一致）を静的に再確認した。

- [fattn-mma-f16.cuh L1977-L1981](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/src/ggml-cuda/fattn-mma-f16.cuh#L1977-L1981)：MMA F16 カーネルは `use_logit_softcap && !(DKQ == 128 || DKQ == 256 || DKQ == 512)` の場合に NO_DEVICE_CODE を実行して return する。
- [fattn.cu L672-L683](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/src/ggml-cuda/fattn.cu#L672-L683)：softcap に関する head size の拒否判定は `mask && mask->ne[2] != 1` の内側にある。
- [fattn.cu L762-L766](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/src/ggml-cuda/fattn.cu#L762-L766)：AMD WMMA の MMA F16 選択は GQA、head size、実効 batch 等に依存する。softcap と DKQ の組み合わせをここで独立に拒否していない。

このため、対応判定と実カーネルの契約の不一致が残る可能性がある。旧障害ケースが現行ビルドで実際に同じ dispatch に到達するかは未実行・未確認。ドライバー更新によって launch failure 後のエラー処理、GPU リセットからの復旧、画面/RDP/OS の応答性が改善する可能性はあるが、明示的な trap 経路そのものをドライバー更新で修正したとは判断できない。障害の再現性と復旧性はいずれも未確認。

### 今後の運用（自動実行禁止は維持）

| テスト範囲 | 扱い |
|---|---|
| 全演算の一括実行、広範囲 sweep | 禁止を維持 |
| FLASH_ATTN_EXT 全条件、既知の危険ケース | 実行しない。必要な修正と別途レビューを先行 |
| ビルド直後の自動 backend-op テスト、`-RunBackendTest` | 禁止を維持 |
| 実装対象の演算・型・形状を明示した限定数値テスト | ソース・dispatch・フィルターの実効範囲をレビューし、運用者の個別承認後にのみ実行を検討 |

限定テストは過去に Vulkan ROCmFPx で r6 150/150、b12651 159/159 の PASS 実績がある。ただし HIP または新ドライバー下の安全性を示すものではない。[r6 S2](../R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md)・[b12651 Stage 2](../B12651-STAGE2-ROCMFP4-VULKAN-20261124.md)

次の D0（ROCm IQ4_NL GET_ROWS 幅160対応）ではソース実装とケース表を先にレビューし、D0-2 の限定 GPU 数値検証を別途承認する。小規模な GET_ROWS のみを対象とし、対象外ケースが実行されないフィルター、期待件数、CPU 参照比較、タイムアウト、プロセス・RAM/コミット/GPU 回復、イベント監査を事前に確認する。既存の安全閾値を変更せず、異常終了、SSH 切断、GPU エラー、重大イベント、資源回復不良では後続テストを停止してログを保全する。自動再試行、TDR 設定変更は行わない。今回の記録は将来の個別承認の代わりではない。[D0 の実装計画](../ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md)・[AGENT-RULES](AGENT-RULES.md)

FA の対応判定と dispatch の整合性修正は、Gemma 4 HIP FA の候補 #32901 / #33045 と併せて将来の独立調査候補とする。これらの PR が旧障害を修正するとは未確認。D0 に混在させない。今回は文書と静的ソースの確認のみで、実機の backend-op テスト、ビルド、推論、ソースや運用ルールの変更は行っていない。
