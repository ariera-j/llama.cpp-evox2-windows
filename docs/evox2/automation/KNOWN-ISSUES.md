# 既知のビルド・実行時の問題

| 症状 | 運用上の扱い |
|---|---|
| ROCm の `FLASH_ATTN_EXT` スイープ | 2026-10-22、DKQ=64 と logit-softcap のケースが HIP の trap 経路に達し、launch failure、画面と RDP の応答停止、Windows `LiveKernelEvent 141` が観測された。trap と watchdog の因果関係は未確定。両バックエンドとも `test-backend-ops.exe` は自動実行せず、`-RunBackendTest` は使わない。 |
| Vulkan の長コンテキストで device lost | 2026-11-03 の 128k IQ4 ベンチマークで `VK_ERROR_DEVICE_LOST` と Windows `LiveKernelEvent 141` を確認。障害箇所の GPU カーネルは未確定。自動再試行や Windows TDR 設定の変更は行わず、実行条件とログを保存して停止する。 |
| Web UI の取得・検証失敗 | build 12037 で `b12037` のチェックサム取得が HTTP エラーになり、`latest` 展開後も必須の JS/CSS/workbox パターンが揃わず `llama-ui-assets` が失敗した。`LLAMA_BUILD_UI=OFF` と `LLAMA_USE_PREBUILT_UI=OFF` の両方を configure に指定する。失敗残骸の退避が承認されている場合は、当該ビルド内の `tools\ui\dist` と `.ui-stamp` だけを確認し、同じビルド内の一意な場所へ移す。 |
| CMake/Clang の警告 | Vulkan の `ccache not found`、Windows の pthread 探索失敗に続く `Found Threads: TRUE`、Clang の signed/unsigned 比較や `httplib.h` の言語拡張警告は成功ビルドでも観測された。ログに残し、終了コードと生成物で判定する。新規の警告、compiler error、ツールの版違いは個別に確認し、フラグや SDK を勝手に変えない。 |
| VS18 / MSVC 14.51 と TheRock | 過去に HIP の `<cmath>` オーバーロード衝突が発生した。この運用では VS2022 / MSVC 14.44 を使用する。 |

詳細は [ROCm の障害記録と警告](../BUILD-ROCM-WINDOWS.md)、[Vulkan device-lost 記録](../R6-LLAMA-BENCH-PP128K-VULKAN-DEVICE-LOST-2026-11-03.md)、[Gemma 4 Global FA の研究記録](../GEMMA4-GLOBALFA-RGP-GATE-20261121.md) を参照する。研究記録の計測手順を自動スモークには組み込まない。
