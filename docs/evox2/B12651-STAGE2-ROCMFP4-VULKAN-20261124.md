# b12651 Stage 2 — ROCmFP4 FAST PLE16 / Vulkan

- 基準は Stage 1 完了済み `codex/b12651-common001-20261124` の `ff907a1e41b6f27890fc6de0dbaa2cb106d811f3`。
- 作業ブランチは `codex/b12651-rocmfp4-20261124`。実装・ビルド元は `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`。
- 過去の移植元は r6 S2 `70545f99826cc1f9d6a0690cd44684124914f2e8`。r5 COMMON-003A `85ab8d79`、VULKAN-001A `202f4988`、VULKAN-001B `8205db29`、数値ケース `fe36a4d3` を照合した。

## 実装と GGUF 互換性

| 対応 | 主な変更 |
|---|---|
| COMMON-003A | `ggml/rocmfp4/`、`ggml/rocmfpx/` のコーデック、`ggml/include/ggml.h`・`ggml/src/ggml.c` のブロック定義と型特性、CPU参照演算、量子化・行検証、`include/llama.h` とモデルローダーの ftype |
| VULKAN-001A | `ggml/src/ggml-vulkan/` の型別デコード、GET_ROWS、コピー・SET_ROWS、MUL_MAT / MUL_MAT_ID の Vulkan 登録とシェーダー生成 |
| VULKAN-001B | ROCmFP4・FAST の q8_1 MMQ、ROCmFP4・FAST・ROCmFPx FP8 の q8_1 MMVQ。b12651 の MMVQ 登録テーブルに統合。範囲外 K タイルへのガードを保持 |
| 数値ケースとビルド | `tests/test-backend-ops.cpp` の小規模ケース、`ggml/src/CMakeLists.txt` のコーデック4ファイル追加、Codex 依存監査に当該 CMake ファイルの確認済み blob `cfdb9a0ac0fe698592cf448657fc81bf7d247cdc` のみ追加 |

GGUF の tensor ID は ROCmFP4=100、FAST=101、FP6=102、FP8=103、FP3=104、Q2=107。既存の b12651 の F8_E4M3=43 を維持し、型 ID の衝突はなかった。Q2 の対応は共通・CPU 側まで。FP3・FP6 の matvec は浮動小数点経路を使う。既存 dispatch の方針を維持し、MMVQ 強制は数値ゲートのみで使用した。HIP の専用カーネル、MTP、QSA union の変更は含まない。

ローカル設定の `AgentionRocmFp4FastPle16` は `C:/llama/models/agentionai/Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf`（93,484,237,760 bytes、更新日時 `2026-09-05T22:21:30.8906089Z`）。読み取り専用のヘッダー調査で GGUF v3、`general.architecture=qwen4exp`、`general.file_type=103`、1,239 tensors を確認した。type ID 101 は50 tensors。type ID 104 は `ple_ngram_embd.0.weight` から `15.weight` までの16 tensorsで、幅160、各 head の行数は metadata と一致した。type ID と general.file_type は別の列挙値。

## Release ビルド

Codex ラッパーで `build-s2v`（Vulkan Release、b12676）を作成した。154.21秒、終了0、Clang 22.1.3、OpenMP 22.1.8、Vulkan SDK 1.4.357.0、`-Offline`。Windows PowerShell 5.1 構文・UTF-8 BOM、依存監査の既存回帰テストが通過。CMake キャッシュで `GGML_CPU_ALL_VARIANTS:BOOL=OFF`、Ninja に Sapphire Rapids ターゲットがないことを確認した。既知のマニフェスト表示は `BackendSettings.CpuAllVariants=true`。Source はクリーン、`BuildIdentity.Status=Verified`、`--version` と `--list-devices` は終了0、`Vulkan0` は AMD Radeon 8060S。

| ファイル | SHA-256 |
|---|---|
| `llama-cli.exe` | `406f91ac5d09e83ba7c54d4babf0043e3879dfed84ef8edd82256921c8b829f8` |
| `llama.dll` | `514f5598c8250055350f01e4056e610a8ce02d46afa5cc839572b8e2dd2c9c67` |
| `ggml-base.dll` | `5a92f52e37ed0270e981853091a6ed5a1cac3a942a305cabfc6f19743a71e42b` |
| `ggml-vulkan.dll` | `891196297b5d3f7eda62f34dd84e36016bcac8943006bfe93740401dd0a6dea5` |
| `test-backend-ops.exe` | `4662efd5034b09004d80e9e2cc282d947dbd1d4f36576fb7146ae23cbc1eaf01` |

ビルドログは `build-Vulkan-Build-fd3dd792084f4492a5025d4e265a4be5`。以下のログもすべて EVO-X2 の `C:/llama-build/_logs/codex` 配下。

## 限定数値ゲート

r6 の5形式に絞ったテストを、b12651 のパラメータ名に合わせて実施した。Vulkan0、1ワーカー、明示した演算名とパラメータでフィルターし、CPU参照と比較した。行列演算は `m=64,k=256`、幅1・3〜8。ROCmFP4とFASTには行列 dispatch 用の幅32、MUL_MAT_ID には4 experts と skipped expert のケースを含む。GET_ROWS は対象モデルと同じ FP3・幅160、5行中3行の小規模ケース。Radeon 8060S のドライバーは `int dot: 1` と KHR cooperative matrix を報告した。実行件数と終了コードを照合した。

| オペレータ | 通常 | MMVQ強制 | ログ（通常 / 強制） |
|---|---:|---:|---|
| MUL_MAT | 37/37 | 37/37 | `b12651-s2-test-mul_mat-normal-20261124-203723-650` / `b12651-s2-test-mul_mat-forced-20261124-203823-962` |
| MUL_MAT_ID | 42/42 | 42/42 | `b12651-s2-test-mul_mat_id-normal-20261124-203820-403` / `b12651-s2-test-mul_mat_id-forced-20261124-203825-519` |
| GET_ROWS | 1/1 | — | `b12651-s2-test-get_rows-normal-20261124-203826-504` |

合計159/159 PASS。強制指定は当該 PowerShell プロセスの `GGML_VK_FORCE_MMVQ=1` のみ。シェーダー選択はソース条件と数値ケースで確認し、個別の GPU パイプライン・トレースは収録していない。広範囲の sweep と FLASH_ATTN_EXT は実行していない。

## 実モデルと回帰確認

UMA96GB（AMDドライバー報告値 103,079,215,104 bytes）。4k・16k は `Reply with the word OK.` を使い、16 head のロードと `Q4_0_ROCMFP4_FAST`、応答 `OK` を実ログで確認。初回4kはロード後半に約60 MiB/sで進行し、監視込み469.49秒。16kの実行は95.59秒。短文は18 promptトークンと2生成トークンのため、PP/TG はモデル動作の参考値。

64k は Stage 1 と同じ日本語論文入力 `nlp-survey-ch3-d7-b1.txt`、SHA-256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`。Batch 2048、UBatch 1024、Threads 4、KV f16、FA auto、GPU layers 999、CPU MoE 0、Fit/MTP/reasoning OFF、temp 0、top_p 0.8、seed 1234、生成上限256。通常 dispatch、ResourceMonitor、ADLX GPU 0。

| モデル / Context | PP / TG (tok/s) | GPU Dedicated / Shared ピーク (GiB) | 空きRAM最小 / コミット最大 (GiB) | ADLX VRAM最大 (MiB) / 温度最大 (°C) | ADLX / リソース件数 | Run ID |
|---|---:|---:|---:|---:|---:|---|
| FAST 4k | 16.85 / 5.27 | 89.096 / 0.529 | 22.377 / 100.560 | 91644 / 38 | 232 / 184 | `20261124-203950-905-cli-vulkan-b12676-ctx4096-17838cbd82c0` |
| FAST 16k | 73.84 / 24.78 | 89.101 / 0.491 | 23.064 / 100.448 | 91645 / 36 | 45 / 36 | `20261124-204940-355-cli-vulkan-b12676-ctx16384-4d0986355651` |
| FAST 64k | 385.76 / 26.13 | 91.101 / 0.561 | 23.410 / 102.683 | 93693 / 83 | 126 / 101 | `20261124-205352-955-cli-vulkan-b12676-ctx65536-f492410e32a2` |
| IQ3 PLE16 64k | 382.77 / 26.63 | 79.478 / 0.561 | 23.455 / 91.029 | 81791 / 83 | 122 / 96 | `20261124-205957-539-cli-vulkan-b12676-ctx65536-08bc99312b31` |

4回とも終了0、49/49層を Vulkan0 に配置、RuntimeArtifact Verified、ADLX終了0、CLI / Windows イベントでGPUエラー・リセットなし。64k の2回とも61,789 promptトークンを処理し、256トークンの日本語要約を生成した。Stage 1 の条件ログと比較し、IQ3 モデルのパス・サイズ・更新日時、両64k入力の SHA-256 とモデルパス以外の引数が一致した。

- FAST の Vulkan0 モデルバッファは全runで88,645.69 MiB。IQ3 は77,657.05 MiB。両方の `Vulkan_Host` は497.31 MiBで、CPU の独立したモデルバッファは報告されなかった。FAST 64k 終了直前の CLI デバイス内訳は GPU self 91,124 MiB、free 16,951 MiB。プロセスの Shared ピークは0.561 GiB。
- 64k の PP 区間推定値を比較した。FAST / IQ3 の ADLX コア中央値は2,769 / 2,791 MHz、VRAMクロックは両方1,000 MHz、GPU電力は120 / 119 W。高負荷分類はいずれも Performance-like。PP の Pages Input/sec 中央値は8.9 / 24.9、95パーセンタイルは59.2 / 70.1。全区間のピーク433,347.4 / 417,395.4はモデル読み込みを含む。システムコミット上限は127.647 GiB。持続的なメモリ圧迫や大きな共有GPUメモリ増加は観測されなかった。
- 全runの開始時は P-MODE Performance。FAST 3回は終了時の委任タスクの状態ファイル待ちが5秒でタイムアウトし、ログ上は Unknown。各run終了後の読み取りでは Performance を確認した。IQ3 は終了時も Performance。短文の ADLX 高負荷分類にはサンプル数が不足した。

## 判定と範囲

**Stage 2 の Vulkan 互換性ゲートと IQ3 PLE16 64k の回帰確認は PASS。** IQ3 の Stage 1 UMA96GB 中央値（384.10 / 26.57 tok/s、3回）と比べ、Stage 2 は PP −0.35%、TG +0.23%。FAST 64k は同じ Stage 2 バイナリの IQ3 64k に対して PP +0.78%、TG −1.88%。量子化形式が異なるモデルの各1回の参考比較で、互換性移植単独の高速化効果は評価していない。

残る観察事項は FAST の初回ロード時間と終了時の P-MODE 取得タイムアウト。64kより長い FAST の GPU メモリ余裕、HIP での ROCmFPx 対応、MTP は今回の検証範囲外。Stage 1 のソース参照、`build-c1v`、`build-c1r` と既存ログは保持し、両CLIのハッシュを再照合した。
