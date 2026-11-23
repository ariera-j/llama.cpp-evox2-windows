# Vulkan / ROCm 自動ビルド運用

運用範囲は [エージェントルール](AGENT-RULES.md)、ツールの固定値は [EVO-X2 環境](EVOX2-ENVIRONMENT.md) を参照する。ラッパーの構文、キャッシュ形式、マニフェストの正本は [ビルドラッパー README](../../../tools/evox2/build/README.md) と各ビルドガイド ([Vulkan](../BUILD-VULKAN-WINDOWS.md)、[ROCm](../BUILD-ROCM-WINDOWS.md))。

## 実行順序

1. Git のブランチ、HEAD、作業ツリーを記録する。承認済みのビルド先を明示し、Vulkan と ROCm で分ける。成功済みの出力を保持する場合は新しい専用ディレクトリを使う。VS2022 x64 とバックエンドの SDK を同一 PowerShell 5.1 プロセスに準備する。
2. ソースから BoringSSL と、Vulkan の場合は LLVM OpenMP の要求版を読む。共有キャッシュを読み取り専用で検証し、足りないものだけ `C:\llama-build\automation\_deps` にコピーする。BoringSSL は `.git` を含む独立した checkout とし、要求タグと HEAD の一致、クリーンな状態をコピー後にも確認する。OpenMP はヘッダー、インポートライブラリ、DLL、`LICENSE.TXT` を確認する。いずれかの必須キャッシュが不足したら configure の前に停止し、依存名と版を報告する。追加取得は明示承認後に専用領域で行う。ROCm の成功時は `-DFETCHCONTENT_FULLY_DISCONNECTED=ON` も指定した。
3. 既存の `Build-Vulkan.ps1` または `Build-ROCm.ps1` に専用 `-BuildDir`、`-DependencyCacheRoot`、`-Parallel 4` を渡す。Vulkan は確認済みの `-CMakeExe`、`-VulkanSdk`、`-LlvmBin` を指定する。ROCm は TheRock を有効化済みの環境で `-ExpectedRocmSdkVersion '10.0.0'` と `-AmdGpuTarget gfx1151` を指定する。
4. `-ConfigureOnly` と `-ExtraCMakeArgs @('-DLLAMA_BUILD_UI=OFF', '-DLLAMA_USE_PREBUILT_UI=OFF')` で再現する。終了コード `0` とキャッシュ上の UI 両フラグ `OFF`、選択されたコンパイラ、SDK、依存の出所を確認する。ROCm の場合は `GGML_HIP=ON` と `AMDGPU_TARGETS=gfx1151` も確認する。
5. 同じ PowerShell とビルド先で `-BuildOnly` を実行する。このモードは既存 CMake キャッシュを使ってメタデータを更新し、configure と生成を再実行する。更新後も UI が `OFF` で、UI 取得処理がログに現れていないことを確認する。
6. `bin\Release\llama-cli.exe --version` と `--list-devices` がともに `0` で終了し、期待するバックエンドで Radeon 8060S が出ることを確認する。`bin\Release\evox2-build.json` の `BuildIdentity.Status=Verified`、ソースと実行ファイルのコミット、実際の CMake・コンパイラ・SDK、スモーク結果を確認する。ROCm の場合は TheRock コピー元と DLL の SHA-256、rocBLAS/hipBLASLt データツリーのダイジェスト、および `gfx1151` データを確認する。

リモートで標準出力と標準エラーを別々の一意名で `C:\llama-build\_logs\codex` に記録し、configure、ビルド、各スモークの終了コードと所要時間を残す。SSH が切れたら、再実行の前にプロセスとログを確認する。非ゼロ終了、SDK/キャッシュ不一致、UI 取得、期待デバイスの欠落、マニフェスト不一致があれば停止し、失敗箇所とログを報告する。失敗したビルドディレクトリは保存する。詳細は [既知の問題](KNOWN-ISSUES.md)。

## 2026-11-23 に確認した範囲

確認ソースは `9de09c6106daf13f26134a4a453a200c73c45bbb`、CLI は `0.7.0-dev` の build `12037`。BoringSSL `0.20261020.0` を両方で再利用し、Vulkan では LLVM OpenMP `20.1.8` も再利用した。

| バックエンド | 結果 |
|---|---|
| Vulkan | `build-vulkan-codex`。UI 両設定を OFF にして configure と build が成功し、`Vulkan0` に Radeon 8060S を確認。BuildIdentity は Verified。 |
| ROCm | `build-rocm-codex`。TheRock 10.0.0 / `gfx1151` で configure と build が成功し、`ROCm0` に Radeon 8060S を確認。TheRock DLL 8 本と両ランタイムデータツリーのハッシュが一致。BuildIdentity は Verified。 |

文書取り込み後の `bf3026f32915a88a96f9131636820dbcd45aaeed` からの再ビルド、モデル推論、バックエンド演算テスト、ベンチマークは **未検証**。このスモークはビルドの来歴とデバイス列挙を確認する。

## Codex 専用ラッパー

Windows PowerShell 5.1 で Codex 専用 clone のルートから実行する。SSH セッションで必要な場合は、起動時に `-ExecutionPolicy RemoteSigned` を指定する。ラッパーは子 PowerShell 一つで VS2022 と SDK を初期化し、上記の既存ラッパーへ処理を委譲する。

```powershell
$wrapper = '.\tools\evox2\automation\Invoke-CodexBuild.ps1'
& $wrapper -Backend Vulkan -BuildDir build-codex-vulkan-001 -PreflightOnly
& $wrapper -Backend ROCm -BuildDir build-codex-rocm-001 -PreflightOnly
```

`-BuildDir` は clone 直下の未使用の `build-*` ディレクトリ名を指定する。`-PreflightOnly` はツールと専用キャッシュを検査し、ビルド先は作成しない。`-ConfigureOnly` は新規出力先で configure まで実行する。スイッチを省略すると、新規出力先で configure と Release ビルドを続けて実行する。configure 済みディレクトリの再利用はこのラッパーの対象外。configure と build にはクリーンな作業ツリーが必要。

依存は既に準備した `C:\llama-build\automation\_deps` を使う。キャッシュが不足していたら停止する。UI 関連の両フラグを `OFF` にし、FetchContent をオフラインに固定する。ビルド後は既存ラッパーの CLI スモーク結果とマニフェスト、実行ファイルの SHA-256、Radeon 8060S の列挙を照合する。`test-backend-ops.exe` は自動実行しない。コマンド、標準出力、標準エラー、終了コード、所要時間は `C:\llama-build\_logs\codex` に保存する。

2026-11-23 の実装確認では PowerShell 5.1 パーサーと UTF-8 BOM の確認が通過した。Vulkan preflight は終了コード `0`（1.88秒）、ROCm preflight は終了コード `0`（2.22秒）。両方ともビルド先を作成しなかった。この新ラッパーによる configure、ビルド、成果物検証は未実施。
