# EVO-X2 のビルド環境

2026-11-23 に Windows 11 上で Vulkan と ROCm の構成を確認した。ビルド共通設定の正本は [ビルドラッパー README](../../../tools/evox2/build/README.md)。

## VS2022 x64 と SSH

VS2022 Build Tools のルートは `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`。その配下の `Common7\Tools\VsDevCmd.bat` を `-arch=x64 -host_arch=x64 -no_logo` で実行する。SSH で PowerShell を親にする場合は、同じ子 `cmd.exe` で初期化に続けて `set` を実行し、出力の環境変数を親 PowerShell のプロセススコープに取り込む。初期化、SDK 選択、configure、ビルド、スモークは同じ PowerShell 5.1 プロセスで行う。

VS `17.0`、`VSCMD_ARG_HOST_ARCH=x64`、`VSCMD_ARG_TGT_ARCH=x64` を確認する。確認済みのホストツールセットは MSVC `14.44.35207`。VS18 / VS2026 は選択しない。PowerShell には `$ProgressPreference = 'SilentlyContinue'` を設定し、必要な場合は実行ポリシーを当該プロセスの `RemoteSigned` にする。

| ツール | VS2022 ルートからの相対パス | バージョン |
|---|---|---|
| CMake | `Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe` | `3.31.6-msvc6` |
| Ninja | `Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe` | `1.12.1` |

`Get-Command` と `--version` で実体を確認する。Vulkan は `-CMakeExe` に上記の絶対パスを指定する。ROCm は `PATH` 上の先頭が上記 CMake と Ninja になるよう確認する。バージョン検証は有効のまま使用する。

## 標準計測ツール

GitHub main と現行製品作業ブランチは作業3-5で同じ標準計測コードを使用する。実機設定は引き続き Git 管理外の `C:\llama-build\automation\benchmark-configs`。ADLX ヘルパーの既存配置がツールの自動検出範囲外の場合は、実機設定から実行ファイルを明示する。 [作業3-5の統合記録](BENCHMARK-INTEGRATION.md)

## SSH のイベントログ読み取り

2026-11-26、運用者が管理者権限で `evox2-runner` を Windows の組み込み **Event Log Readers**（SID `S-1-5-32-573`）へ追加した。新規 SSH 接続の `whoami /groups` で有効を確認した。Windows PowerShell 5.1 の `Get-WinEvent` で System／Application の各最新1件を取得できた。両チャネルで意図的に該当0件の検索を行い、`NoMatchingEventsFound` を確認した。アクセス拒否や読み取りエラーがあれば、0件と扱わず無人計測を停止する。

計測の前後は両チャネルの EventRecordID を使い、新規の GPU、WHEA、BugCheck、リソース枯渇などのイベントを確認する。過去の WER 再処理を発生時刻の裏付けなしに新規障害へ分類しない。OS 最終起動は CIM が取得制約のため、Kernel-General 12 の `StartTime` から 2026-11-26 00:21:08.500 JST と取得した。Kernel-Power 41 により異常終了後の起動と判定したため、直前の正常シャットダウン時刻、方式、OS 停止時間は欠損。稼働時間はネイティブ API で取得し、高速スタートアップ設定は無効を確認した。 [M005 と復旧手順](INCIDENT-20261126-M005.md)

## Vulkan

2026-11-24 の b12651 Stage 1/2（Vulkan Release）では、Vulkan SDK `C:\VulkanSDK\1.4.357.0` と **Visual Studio 2026 Build Tools 付属の LLVM/Clang 22.1.3** を使用した。`clang.exe` と `clang++.exe` のディレクトリは `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\Llvm\x64\bin`。Codex ビルドラッパーには `-VulkanLlvmBin` でこのディレクトリを渡し、`-ExpectedVulkanClangVersion 22.1.3` を指定する。LLVM OpenMP は `22.1.8` を使用した。

MSVC・CMake・Ninja の開発環境は引き続き上記 VS2022 x64 を使用し、VS2026 の開発環境（`VsDevCmd.bat`）へは切り替えない。旧 `C:\Program Files\LLVM\bin` の Clang 20.1.8 は過去のビルド構成であり、b12651 Stage 1/2 の再現には使用しない。詳細は [Windows Vulkan ビルドガイド](../BUILD-VULKAN-WINDOWS.md)。

## ROCm

同じ PowerShell で `C:\TheRock\build\.venv\Scripts\Activate.ps1` を実行する。`rocm-sdk version` は `10.0.0`、`rocm-sdk path --root` は `C:\TheRock\build\.venv\Lib\site-packages\_rocm_sdk_devel`。C/C++ と HIP に使う AMD Clang はルートの `lib\llvm\bin` にあり、実測バナーは `23.0.0git`、ターゲットは `gfx1151`。

仮想環境の有効化後も `PATH` と `HIP_PATH`、`HIP_PATH_72` に ROCm 7.2 が残る場合がある。プロセス内で 7.2 への参照を除去し、`HIP_PATH` と `ROCM_PATH` を TheRock ルートに合わせる。ユーザー・システム環境変数は変更しない。ラッパーは SDK の DLL と rocBLAS/hipBLASLt のデータを実行ファイルの隣に配置して照合する。詳細は [Windows ROCm ビルドガイド](../BUILD-ROCM-WINDOWS.md)。

## AMD ドライバーとランタイムの履歴

| 確認時点 | AMD Software | ディスプレイドライバー | Vulkan ICD DLL 版／API | System32 Vulkan Loader |
| --- | --- | --- | --- | --- |
| 2026-11-26 更新前 | 26.8.1 | 32.0.31041.1004 | 9.2.10.395／1.4.349 | 1.4.357.0 |
| 2026-11-26 更新後 | 26.11.2 | 32.0.32029.2010 | 9.2.10.416／1.4.359 | 1.4.357.0 |

製品版は AMD Software のアンインストール レジストリ、ディスプレイ版と ICD JSON は Radeon 8060S の `Control\Video` レジストリから取得した。ICD DLL と Loader はファイル版を使用した。更新後も Vulkan SDK 1.4.357.0、TheRock 10.0.0、BIOS EVO-X2 1.12、Windows 26300.10075、UMA 96 GiB を確認した。標準ビルドに同梱された `amdhip64_7.dll` は10.0.3581.0、`hipblas.dll` は3.6.0.0、`libhipblaslt.dll` は1.4.1.0で、同梱ファイルとランタイムデータツリーの検証に成功した。 [更新比較と停止記録](ADRENALIN-UPDATE-COMPARISON-20261126.md#更新後adrenalin-26112)
