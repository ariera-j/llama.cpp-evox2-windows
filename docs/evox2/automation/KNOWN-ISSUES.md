# 既知のビルド・実行時の問題

| 症状 | 運用上の扱い |
|---|---|
| ROCm の `FLASH_ATTN_EXT` スイープ | 2026-10-22、DKQ=64 と logit-softcap のケースが HIP の trap 経路に達し、launch failure、画面と RDP の応答停止、Windows `LiveKernelEvent 141` が観測された。trap と watchdog の因果関係は未確定。両バックエンドとも `test-backend-ops.exe` は自動実行せず、`-RunBackendTest` は使わない。 |
| Vulkan の長コンテキストで device lost | 2026-11-03 の 128k IQ4 ベンチマークで `VK_ERROR_DEVICE_LOST` と Windows `LiveKernelEvent 141` を確認。障害箇所の GPU カーネルは未確定。自動再試行や Windows TDR 設定の変更は行わず、実行条件とログを保存して停止する。 |
| Web UI の取得・検証失敗 | build 12037 で `b12037` のチェックサム取得が HTTP エラーになり、`latest` 展開後も必須の JS/CSS/workbox パターンが揃わず `llama-ui-assets` が失敗した。`LLAMA_BUILD_UI=OFF` と `LLAMA_USE_PREBUILT_UI=OFF` の両方を configure に指定する。失敗残骸の退避が承認されている場合は、当該ビルド内の `tools\ui\dist` と `.ui-stamp` だけを確認し、同じビルド内の一意な場所へ移す。 |
| CMake/Clang の警告 | Vulkan の `ccache not found`、Windows の pthread 探索失敗に続く `Found Threads: TRUE`、Clang の signed/unsigned 比較や `httplib.h` の言語拡張警告は成功ビルドでも観測された。ログに残し、終了コードと生成物で判定する。新規の警告、compiler error、ツールの版違いは個別に確認し、フラグや SDK を勝手に変えない。 |
| VS18 / MSVC 14.51 と TheRock | 過去に HIP の `<cmath>` オーバーロード衝突が発生した。この運用では VS2022 / MSVC 14.44 を使用する。 |

詳細は [ROCm の障害記録と警告](../BUILD-ROCM-WINDOWS.md)、[Vulkan device-lost 記録](../R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md)、[Gemma 4 Global FA の研究記録](../GEMMA4-GLOBALFA-RGP-GATE-20261121.md) を参照する。研究記録の計測手順を自動スモークには組み込まない。

## 2026-11-23 リソース監視の権限と代替経路

EVO-X2 の SSH セッションで `evox2-runner` として確認した。`Get-CimInstance Win32_OperatingSystem` は `0x80041003 (Access Denied)` だった。旧 IQ3 の推論は正常終了したが、従来の ResourceMonitor はこの例外で停止し、両方とも0サンプルだった。

従来の英語パス20件を `Get-Counter` で個別に確認した。内訳は CPU 1、ディスク 3、コミット 3、ページング 3、GPU アダプター 4、PID 別 GPU メモリ・エンジン 6。すべて `CounterApiError`（指定オブジェクトが見つからない）を返し、カウンターセット一覧も `NoCounterSetsOnComputer`（`c0000bc8`）だった。WMI のアクセス拒否とは別のエラーであり、PerfMon が取得できない原因を権限だけに限定できない。

`Monitor-LlamaProcess.ps1` は物理メモリとシステム全体のコミットを Windows の `GetPerformanceInfo` で取得する。カウンター一括照会に失敗したときは個別に取得を試み、取得できた値は残す。`resources.csv` の53列と単位を維持し、取得不能な数値は空欄にする。PID 別 GPU サンプルの有無は `GpuProcessCountersAvailable` で確認する。ページングは3項目ともこの環境では未取得。GPU の利用率などは既存の ADLX ログも参照できるが、ADLX に VRAM 使用量がない場合、PerfMon のメモリ欄を埋めるデータとしては使えない。

`Measure-LlamaCli.ps1` は監視が有効で0サンプルの場合、推論の `Status` と独立に `ResourceMonitorStatus=Failed` と警告を出す。サンプルを記録した場合は `Collected` とし、個々のカウンターの取得可否は CSV と監視ログで確認する。

10秒間の PowerShell プロセスを1秒間隔で監視し、10サンプル、既存と同じ53列、監視終了コード0を確認した。最初の値は物理使用7.854 GiB、空き55.793 GiB、コミット10.038 / 159.647 GiB。ページングと GPU の未取得欄は空欄、PID 別 GPU フラグは `False`。存在しない PID のテストでは0サンプルで監視が終了コード1になり、CLI 側の判定も推論 `OK` と監視 `Failed` を両立することをコード単体で確認した。権限設定は変更せず、モデルを使った再試験は実施していない。

生ログは EVO-X2 の `C:\llama-build\_logs\codex` 以下。

- `resource-counter-probe-656e3a8313e94721b5999c258a03646b.csv`
- `resource-monitor-smoke-b4499f91d80e40b7834c29325450b526`
