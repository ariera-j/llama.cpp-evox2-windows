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

## Vulkan

`C:\VulkanSDK\1.4.357.0` と `C:\Program Files\LLVM\bin` をラッパーへ明示する。後者の `clang.exe` と `clang++.exe` はともに `20.1.8`。詳細は [Windows Vulkan ビルドガイド](../BUILD-VULKAN-WINDOWS.md)。

## ROCm

同じ PowerShell で `C:\TheRock\build\.venv\Scripts\Activate.ps1` を実行する。`rocm-sdk version` は `10.0.0`、`rocm-sdk path --root` は `C:\TheRock\build\.venv\Lib\site-packages\_rocm_sdk_devel`。C/C++ と HIP に使う AMD Clang はルートの `lib\llvm\bin` にあり、実測バナーは `23.0.0git`、ターゲットは `gfx1151`。

仮想環境の有効化後も `PATH` と `HIP_PATH`、`HIP_PATH_72` に ROCm 7.2 が残る場合がある。プロセス内で 7.2 への参照を除去し、`HIP_PATH` と `ROCM_PATH` を TheRock ルートに合わせる。ユーザー・システム環境変数は変更しない。ラッパーは SDK の DLL と rocBLAS/hipBLASLt のデータを実行ファイルの隣に配置して照合する。詳細は [Windows ROCm ビルドガイド](../BUILD-ROCM-WINDOWS.md)。
