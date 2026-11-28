# ROCmFP4 FAST PLE16 単一スモークおよび初回直列 GPU 検証記録（HIP-2E-3B-0 / 3B、2026-11-29）

## 1. HIP-2E-3B-0：単一ケース実 GPU スモーク結果（PASS）

- **run_id**：`hip2e3b0-case1-20261129`
- **対象**：ケース `1`（`F32_C`）のみ
- **結果**：**PASS**（`ExitCode=0`, `ElapsedSeconds=0.313`, `Pid=10316`, `TimedOut=false`, `Unconfirmed=false`, `MonitorError=null`, 参照 SHA-256 `d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a` 一致）
- **未計測事項**：実行時間 `0.313` 秒（2 秒未満）のため `DuringSamples=0` であり、実行中ピーク使用量は未測定（`unmeasured (duration < 2s)`）。
- **回収ログ**：4 ファイル（`.stdout.log`, `.stderr.log`, `.report.json`, `.state.json`）+ `SHA256SUMS` 一致。レビュー用 ZIP `hip2e3b0-review.zip`（SHA-256 `e6883dbf9500603f576d68a9edb96c8296d4ab12a784a42bb5913bdc2deed7ed`）について ChatGPT 独立レビュー **GO**。

---

## 2. HIP-2E-3B：初回全 13 ケース直列 GPU 検証結果（途中安全停止）

- **run_id**：`hip2e3b-full-20261129`
- **監督スクリプト**：`run_hip2e_suite.py`（SHA-256 `fd5921966e32dbc43cdb701bc367c2b79a0880475ef48d5c811eb630297f2104`）
- **総合判定**：**`OVERALL=FAIL`**（**11 PASS / 1 FAIL / 1 NOT RUN**）
- **実績区別**：
  - **実行済み**：12 件（`1`〜`S-HC-CPU` の 11 件 PASS、`S-HC-PIN` 1 件 FAIL）
  - **実機原ログ**：48 ファイル（12 件 × 4 ファイル、`C:\llama-build\_logs\codex\hip2e3b-full-20261129-*`、ChatGPT にて全 48 ファイル独立確認済み。再実行による再取得は禁止）
  - **未実行**：1 件（`S-ID-PIN`：`NOT RUN`）
  - **summary JSON**：[tools/evox2/experiments/hip2e3/results/hip2e3b-full-20261129-summary.json](../../tools/evox2/experiments/hip2e3/results/hip2e3b-full-20261129-summary.json)（`overall_status=FAIL` のためコントローラー側への 52 ログ一括回収 `collected_logs` は `null`）

### ケース別実行結果

| # | Case ID | Status | PID | Elapsed (s) | Exit | 参照 SHA-256 | DuringSamples | 備考 |
|---|---|---|---:|---:|---:|---|---:|---|
| 1 | `1` | **PASS** | 8368 | 0.268 | 0 | `d29a1e44...baae70a` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 2 | `1-NC` | **PASS** | 4840 | 0.264 | 0 | `d29a1e44...baae70a` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 3 | `2` | **PASS** | 10340 | 0.284 | 0 | `637b914b...e0e509f` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 4 | `2-C` | **PASS** | 11080 | 0.285 | 0 | `637b914b...e0e509f` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 5 | `5` | **PASS** | 10124 | 0.398 | 0 | `0978449f...2597cbd` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 6 | `6` | **PASS** | 2880 | 0.395 | 0 | `f4077833...c18e8c1` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 7 | `7` | **PASS** | 16180 | 0.394 | 0 | `d3ab1c46...d933c1e` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 8 | `8` | **PASS** | 7580 | 0.401 | 0 | `3a2a7133...9a86ecb` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 9 | `9` | **PASS** | 13512 | 0.420 | 0 | `9203115b...9146414` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 10 | `9-Z` | **PASS** | 11592 | 0.272 | 0 | `738c079d...77bb40` | 0（未測定: <2s） | HIP-2D 同等合格 |
| 11 | `S-HC-CPU` | **PASS** | 12180 | 0.401 | 0 | `f4077833...c18e8c1` | 0（未測定: <2s） | 下記詳細参照 |
| 12 | `S-HC-PIN` | **FAIL** | 14364 | 3.851 | -1073740791 | `f4077833...c18e8c1` | 1（`2.01s` 時記録） | `harness.cpp:128` GGML_ASSERT 失敗 |
| 13 | `S-ID-PIN` | **NOT RUN** | — | — | — | — | — | `S-HC-PIN` 異常により安全停止 |

- **`S-HC-CPU` 経路・誤差診断（期待値一致）**：
  - `backend=ROCm0`, `weight=ROCm0`, `activation=CPU->ROCm0`, `dst=ROCm0`, `ids=-`
  - `split_copy=1, stage_h2d=0, stage_d2h=0, host_reads=0, span=0, pitch=0, ops=1, sgemms=1`
  - `max_relative_error=2.1152120219556505e-06`, `max_condition=566.1413412986778`
- **安全条件**：全 12 実行ケースで `ResidualCount=0`、`SysErrors=[]`、`AppErrors=[]`（`SysId=70260`, `AppId=44891` 維持）、`PMode=Performance` 維持。`S-HC-PIN` 異常検出と同時に安全停止し、後続の `S-ID-PIN` を起動しなかった。

---

## 3. `S-HC-PIN` 停止原因の記録

- **停止箇所**：`tools/evox2/hip2a/harness.cpp:128`
  ```cpp
  GGML_ASSERT(ggml_backend_sched_get_tensor_backend(sched, dst) == hip)
  ```
- **背景と推定原因**：
  - ChatGPT による固定 SHA（`5cc54b8c04f5ec812d5b8a35f452eb8679de948e`）ソース調査により、`ggml-cuda.cu:412` に `info.devices[id].integrated = false;` が設定されていることを確認（既存の出力破損対策として意図的に無効化されている設定）。
  - この設定が `ggml_backend_cuda_device_supports_buft` および `rocmfp4_fast_storage` の pinned 出力支持条件に影響し、`S-HC-PIN` の事前確保された pinned 出力が HIP 側に割り当てられなかったと推定される。
  - **未取得情報**：実際に選択された backend 名は今回未取得。
  - **重要事実**：FAST の数値演算や host staging が実行されて失敗したわけではなく、**演算前の scheduler 割当検査で停止**した。
  - **禁止事項**：`integrated=true` への変更、汎用 `supports_buft` の緩和、backend 強制割当は行わない。

---

## 4. 次工程の調査・修正方針（Codex Astra Medium への引き継ぎ）

次工程では Codex Astra Medium により以下を調査する予定（本記録時点では未着手）：

1. `integrated=false` の既存制約
2. `S-HC-PIN` と `S-ID-PIN` の実際の scheduler 配置・転送
3. pinned 入力から device 入力への split copy
4. 非連続 ID コピー時の pitch 保持
5. pinned 出力の支持判定負例
6. 実モデルの HC と expert down 演算への影響
7. FAST 内部 host staging を残す必要性
