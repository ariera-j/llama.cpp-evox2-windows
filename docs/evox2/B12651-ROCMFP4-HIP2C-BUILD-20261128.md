# ROCmFP4 FAST PLE16 Windows HIP テスト版ビルド記録（HIP-2C、2026-11-28）

**PASS**。テスト版ビルド（`GGML_HIP_ROCMFP4_TEST:BOOL=ON`）および成果物・DLL・Runtime・標準 CLI smoke 検査を通過した。通常版のビルド、GPU 数値ハーネス、実モデル推論は本工程の対象外。

## 1. 基準 SHA とビルド環境

| 項目 | 確定値 |
|---|---|
| `main`（本記録保存前） | `63d1322b8e58ad0baf11094087ced068e2677101` |
| 製品基準（変更禁止） | `a650d641ee99198543697e1e3913c593059721f7` |
| 実験ブランチ | `codex/b12651-rocmfp4-hip2-20261128` |
| 最終ビルド元 SHA | `a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959` |
| 最終 worktree / BuildDir | `C:\llama-build\automation\w60` / `C:\llama-build\automation\w60\build-h2t` |
| ツールチェーン | VS2022 `17.0` (x64/x64)、MSVC `14.44.35229.0`、CMake `3.31.6-msvc6`、Ninja `1.12.1`、TheRock `10.0.0` (`gfx1151`)、AMD Clang `23.0.0git` |
| 依存キャッシュ（Offline） | `C:\llama-build\automation\_deps`（BoringSSL `0.20261105.0` / `3dc4b63808921e914a3fb1fa61869abc3938781b`） |

## 2. 経過：初回 Preflight 停止・監査例外・識別子修正

1. **HIP-2C-1 初回 Preflight 停止（`w57` / `cab3886c3e76c6cb0716be62a60bfe752d9c0b7c`）**：
   - `VerifyDependencies` にて `ggml/src/ggml-hip/CMakeLists.txt` の基準コミット `f5e6915c28f10330885fcb9243a93ae98d3115ab` に対する差分が検出され停止（実行 ID `build-ROCm-Preflight-b2374726fce641959d88303c85e2325f`、終了コード `1`、所要 `3.998` 秒）。
   - HIP-2C-1A で `tools/evox2/build/Evox2.DependencyCache.psm1` と `Test-Evox2DependencyInputs.ps1` に固定監査基準 SHA・厳密 blob `b683a1d32fd8cf8e3bf15a788b16b1f2c083bd76`・`tracked` 差分限定の例外を追加し、`main` (`fe5dc0832ec6d7bc0d20d3537eef00fcb3b67693`) および実験ブランチ (`56e4f6dc7f332eb275de9d27bd3c12a7ed0c320d`) へ反映した。[HIP-2C-1 / HIP-2C-1A 記録](B12651-ROCMFP4-HIP2C1-PREFLIGHT-AUDIT-20261128.md)
2. **初回コンパイル失敗（`w59` / `56e4f6dc7f332eb275de9d27bd3c12a7ed0c320d` / `build-h2t2`）**：
   - Preflight（`build-ROCm-Preflight-c62e46b80eca487f87be706995c60ea5`、4.231 秒）と Configure（`hip2c-configure-f879931d8a6141458beff36d0c5d931b`、10.198 秒）を通過後、BuildOnly（`hip2c-build-1a49d21fc7b74ba296261ea93500a3cb`、PID `14948`、Exit `1`、24.251 秒）で `convert.cu` のコンパイルに失敗。
   - 原因：`ggml/include/ggml.h:266` の正式名 `GGML_TYPE_Q4_0_ROCMFP4_FAST` ではなく未宣言識別子 `GGML_TYPE_ROCMFP4_FAST` を使用していた（`dequantize.cuh:7:15`, `convert.cu:558,627,693,754`）。
   - `w59` および `build-h2t2` は失敗時の記録として保全し、`build-h2t`（`Test-Path` 失敗時の初期フォルダ）も残置した。
3. **HIP-2C-3A 識別子置換**：
   - 4 ファイル計 21 箇所（`dequantize.cuh` 1、`convert.cu` 4、`ggml-cuda.cu` 14、`harness.cpp` 2）を `GGML_TYPE_Q4_0_ROCMFP4_FAST` へ置換し、逆置換一致・`git diff --check` 成功を確認後、`a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`（`fix(hip): use canonical ROCmFP4 FAST type identifier`）として commit・push した。

## 3. 最終ビルド結果（`w60` / `a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`）

| 段階 | 判定 | 所要時間 | PID / 終了コード | ログ保存先（EVO-X2） |
|---|---|---:|---|---|
| HIP-2C-1：Preflight | **PASS** | 3.670 秒 | Exit `0` | `C:\llama-build\_logs\codex\build-ROCm-Preflight-a38438f2198e4ea8a4909c7fb6d5cf73.*` |
| HIP-2C-2：Configure | **PASS** | 9.164 秒 | PID `14404` / Exit `0` | `C:\llama-build\_logs\codex\hip2c-configure-45e5eabd29b8407f9637d0fcf6d8275f.{stdout,stderr}.log` |
| HIP-2C-3：Build | **PASS** | 435.545 秒 | PID `11224` / Exit `0` | `C:\llama-build\_logs\codex\hip2c-build-688e32a35a0743e2b7c9016045a5940f.{stdout,stderr}.log` |
| HIP-2C-4：成果物検査 | **PASS** | — | Exit `0` | `C:\llama-build\_logs\codex\hip2c-ggml-hip-exports.txt` |

- **Configure 引数**：`-DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DGGML_HIP_ROCMFP4_TEST:BOOL=ON`（`AMDGPU_TARGETS=gfx1151`、`GGML_HIP=ON`、`impl-Release.ninja` に `tools/evox2/hip2a/harness.cpp` と `-DGGML_HIP_ROCMFP4_TEST`、legacy ROCm 7.2 排除）。
- **成果物・Hash**：
  - `llama-cli.exe`：`C:\llama-build\automation\w60\build-h2t\bin\Release\llama-cli.exe`（SHA-256 `D11D5C7C493F958DECFEF81C994D3C274D147538F935CC565864491BC4F90352`）
  - `evox2-build.json`：`C:\llama-build\automation\w60\build-h2t\bin\Release\evox2-build.json`（SHA-256 `05CDF29DF6DEF0C40C3BDEA8CAE2DD736DDDCEDED1BB804022A8BBC7D4000C6C`）
  - `ggml-hip.dll`：`C:\llama-build\automation\w60\build-h2t\bin\Release\ggml-hip.dll`（SHA-256 `CD7D6B380ED7C7B7FA487792FE97A316999C4ED72066E8FB72038783475A3911`）
  - `ggml-base.dll`：`C:\llama-build\automation\w60\build-h2t\bin\Release\ggml-base.dll`（SHA-256 `C51541D434A66D9CB5E36626CA63EEDA968EC12F992127B885074D9D746000A8`）
- **Manifest / Smoke / Runtime / Export**：
  - `BuildIdentity.Status = Verified`、`Source.Commit = a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`、`Backend = ROCm`、`SmokeSkipped = false`
  - `llama-cli --version`（Exit `0`, `version: 1.0.0-dev (build 12700, commit a8b8a6ffd)`）および `--list-devices`（Exit `0`, `ROCm0: AMD Radeon(TM) 8060S Graphics (110456 MiB, 110301 MiB free)`）
  - `RuntimePolicy.Verification = DllAndRuntimeDataHashesVerified`（ROCm DLL 8 本、`rocblas` 150 ファイル・Digest `3a6de928ed5ec7c2c7eac5cd98d1fa5e872c20643a81488bdfc755f9a94e11b3`、`hipblaslt` 100 ファイル・Digest `0a9dd8a70063551cbc7e358599165fd8c007af8e4554ea858ae8ff5a759d`）
  - `Test-Evox2RuntimeArtifacts`（`llama-cli.exe`, `llama-bench.exe`, `llama-server.exe`）：すべて `Verified / RuntimeDependenciesV1 / BuildCompleted`（PE インベントリ 22 ファイル）
  - `dumpbin.exe /nologo /exports`：`evox2_hip2a_case` export が正確に **1 件**（`1 0 00CE4AB0 evox2_hip2a_case`）
- **テスト版と通常版の区別**：本ビルドは `GGML_HIP_ROCMFP4_TEST:BOOL=ON` により `evox2_hip2a_case` を export する検証専用ビルドであり、通常版ビルド（同 export 0 件の確認を含む）は未実施。
