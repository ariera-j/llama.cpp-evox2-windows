# ROCmFP4 FAST PLE16 限定 GPU 数値検証記録（HIP-2D、2026-11-28）

**PASS（10/10）**。テスト版 `ggml-hip.dll`（`a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`）を用いた直接 backend 限定 GPU 数値検証 10 件は全件通過した。scheduler 経由の検証（HIP-2E）および実モデル推論は未実施。

## 1. 事前監査（HIP-2D-0）と環境分離

- **対象ビルド**：`C:\llama-build\automation\w60\build-h2t\bin\Release`（`ggml-hip.dll` SHA-256 `CD7D6B380ED7C7B7FA487792FE97A316999C4ED72066E8FB72038783475A3911`、manifest `05CDF29DF6DEF0C40C3BDEA8CAE2DD736DDDCEDED1BB804022A8BBC7D4000C6C`）
- **Python / ハーネス来歴**：`C:\Python314\python.exe` (`3.14.9`)、`cases.inc` (`e21a8eee5d5560a4498af9ad2eb455166e06eaf5`)、`fixtures.py` (`f2fef43d1e9049f01e98b1c0dcdb661433f14875`)、`harness.cpp` (`149f1a850cb7f53cb625c6c515220c271dc7aed1`)
- **dry enumeration / CPU 参照**：`fixtures.py enumerate` / `reference` ともに終了コード `0`。catalog の正規化レコード SHA-256 は `0f5c1cf6b166d57f6c8ed16bc85c3ef6d8a88f10837c09d55655dfd577c6feea`、CPU codec 4096 組、ID span 正例 1 / 負例 10、全 10 件の参照 SHA-256 がレビュー済み値と一致。
- **ROCm 7.2 混入防止措置**：SSH 親環境に `HIP_PATH`・`HIP_PATH_72`・`PATH` への `ROCm\7.2` 参照が残存していたため、各ケース実行プロセスの環境変数から `ROCm\7.2` を除去した上で、`fixtures.py` の `os.add_dll_directory` によりテスト版 `Release` ディレクトリを優先検索させた。
- **開始前状態**：P-MODE `Performance`（`ScheduledTask`, RawValue `1`）、OS 起動 `2026-11-28T02:39:40.0575102Z`、物理空き `25.592 GiB` / `31.647 GiB`、Commit `8.288/127.647 GiB`、WDDM Dedicated `0.420 GiB` / Shared `0.065 GiB`、イベントカーソル `System=70257`, `Application=44878`。

## 2. BLAS 内部精度の根拠

- `ggml/src/ggml-cuda/vendors/hip.h`：L22 `#define CUBLAS_TF32_TENSOR_OP_MATH 0`、L42 `#define cublasSetMathMode(handle, mode) CUBLAS_STATUS_SUCCESS`（実質 no-op）、L47 `#define cublasSgemm hipblasSgemm`。
- 同梱 TheRock 10.0.0 `hipblas.dll`（3.6.0.0）経由で `rocblas.dll` を使用し、`ROCBLAS_*` / `HIPBLAS_*` による低精度指定は未設定。
- **未確認事項**：`cublasSetMathMode` が実質 no-op であり、`hipblasSgemm` / `rocblas` バイナリ内部の具体的な F32 積和実装（FMA 順序や分割等）は未確認。

## 3. 監督スクリプト（`run_hip2d_case.py`）の仕様と安全停止条件

- **用途・保存先**：未レビューの検証補助スクリプトとしてコントローラー側（`review/hip2d/run_hip2d_case.py`、SHA-256 `50d8d8f6c3200767e6ff2319dc317f956b76863be9906f32d3060ff1bd6c42c4`）に保存。**共通製品ツールとしては未採用**。
- **監督方法**：1 ケースにつき 1 回 `powershell.exe -EncodedCommand` を生成し、実機上で `System.Diagnostics.Process` により `C:\Python314\python.exe -I -B tools/evox2/hip2a/fixtures.py gpu --case <ID> --dll <ggml-hip.dll>` を直列 1 worker で起動。`WaitForExit(2000)` ループで 2 秒周期サンプリングを行い、60 秒超過時は対象 PID のみ `Stop-Process -Force` で停止する。stdout / stderr / `report.json` を `C:\llama-build\_logs\codex\hip2d-<case>-<guid>.*` に保存。
- **安全停止条件**：タイムアウト、非ゼロ終了、終了後物理空き 16 GiB 未満、Commit または WDDM Dedicated の開始比 +4 GiB 超増加、残留プロセス、P-MODE 変化、`System`/`Application` の新規重大イベント（WHEA/Display/BugCheck/DxgKrnl/Application Error 等）のいずれかで停止。

## 4. 全 10 ケース GPU 検証結果

SGEMM 期待回数は `harness.cpp` 内の `GGML_ASSERT` による実測カウンタ照合と `done == 1`・終了コード `0` により一致を確認（native 側は個別回数を標準出力に出力しない）。全 10 ケースで `DuringSamples` は空（0.267〜0.431 秒と 2 秒間隔未満で終了したため）であり、**実行中ピーク資源使用量は未測定**。

| Case | Op / Shape | 期待 SGEMM | PID | 所要(秒) | Exit | 誤差・一致確認 | 参照 SHA-256 | 終了後資源 (Phys / dCommit / dDed) | 原ログ stem (`C:\llama-build\_logs\codex\`) |
|---|---|---:|---:|---:|---:|---|---|---|---|
| `1` | `F32_C` 32,256 | 0 | 4836 | 0.314 | 0 | bitwise 一致 | `d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a` | 25.578 GiB / +0.026 / +0 | `hip2d-1-51bcb9cee32d4135976708bd7fa8bb00` |
| `1-NC` | `F32_NC` 32,256 | 0 | 8252 | 0.267 | 0 | bitwise 一致 | `d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a` | 25.580 GiB / +0.039 / +0 | `hip2d-1-NC-3edf75b499764b47aad548e3299ff138` |
| `2` | `F16_NC` 160,256 | 0 | 10080 | 0.288 | 0 | bitwise 一致 | `637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f` | 25.581 GiB / +0.034 / +0 | `hip2d-2-ed3a48bd1849433e8367486fb77f0c73` |
| `2-C` | `F16_C` 160,256 | 0 | 12444 | 0.302 | 0 | bitwise 一致 | `637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f` | 25.583 GiB / +0.032 / +0 | `hip2d-2-C-8f78489a0ba0429c93c5c3616ccd84e1` |
| `5` | `MM` 32,3 | 1 | 16064 | 0.416 | 0 | one-hot 厳密一致 | `0978449fc6f46e694dcffa7841034c6a4d85da13766c20b55e37446f32597cbd` | 25.575 GiB / +0.024 / +0 | `hip2d-5-2273419fefd446a58dce6e2c1bb9f230` |
| `6` | `MM` 160,5 | 1 | 5904 | 0.411 | 0 | `max rel err 2.1152120219556505e-06` (`cond 566.1413`) | `f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1` | 25.584 GiB / +0.027 / +0 | `hip2d-6-f039a16d370c4d1fbaba35d3ef98c37f` |
| `7` | `MM_ID` 32,3,E4,T1,S2 | 2 | 10040 | 0.417 | 0 | `max rel err 1.2382152407668576e-07` (`cond 45.3111`) | `d3ab1c4678f9604738fc286adbe9ee181a9e0bd56f6a55e4fa8616f28d933c1e` | 25.587 GiB / +0.023 / +0 | `hip2d-7-b415ef7cca6f4ea193de12f02495f50f` |
| `8` | `MM_ID` 160,5,E4,T3,S2 | 2 | 15908 | 0.417 | 0 | `max rel err 2.1152120219556505e-06` (`cond 566.1413`) | `3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb` | 25.581 GiB / +0.038 / +0 | `hip2d-8-a114b96e23b743a18d62654b37ff319c` |
| `9` | `MM_ID` 640,7,E3,T5,S2 | 3 | 14724 | 0.431 | 0 | `max rel err 1.5640720712051397e-06` (`cond 935.3666`) | `9203115b655f0305deaad40823cf2920d8e33e3c2d6ef9ad9d45001ff9146414` | 25.581 GiB / +0.035 / +0 | `hip2d-9-383ddd8e69874c37a586e4ee539e6352` |
| `9-Z` | `MM_ID` 640,7,E3,T5,S2 | 0 | 10464 | 0.290 | 0 | 全 70 要素 `+0` bitwise 一致 | `738c079dff6c9b77a0891ac42db1cabcab933a672b14aed8ecfcf94c0e77bb40` | 25.593 GiB / +0.031 / +0 | `hip2d-9-Z-7b4970610bdb44a19fba0104891c7aac` |

- **全区間監視**：イベントログ差分 0 件（`System=70257->70257`, `Application=44878->44878`）、残留プロセス 0 件、P-MODE `Performance` 維持。
- **未実施範囲**：scheduler 経由の検証 3 件（HIP-2E）、FP3 `GET_ROWS`、通常版ビルド、実モデルロード・推論・性能計測。
