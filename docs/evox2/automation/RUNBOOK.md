# Vulkan / ROCm 自動ビルド運用

運用範囲は [エージェントルール](AGENT-RULES.md)、ツールの固定値は [EVO-X2 環境](EVOX2-ENVIRONMENT.md) を参照する。ラッパーの構文、キャッシュ形式、マニフェストの正本は [ビルドラッパー README](../../../tools/evox2/build/README.md) と各ビルドガイド ([Vulkan](../BUILD-VULKAN-WINDOWS.md)、[ROCm](../BUILD-ROCM-WINDOWS.md))。

このランブックと標準ビルドツールの正本は GitHub の `main`。b12651 のコマンドは現行製品ブランチなど、レビュー済みの b12651 系ソースを選んだ専用 clone で実行する。実行前に製品ソースの SHA とラッパーの引数を照合する。 [標準ツールの採用元と実ビルド検証](BUILD-INTEGRATION.md)

性能計測は main の標準ツールを使用する。単独の条件は Measure、複数条件は Matrix で `-PlanOnly` の展開を先に確認する。通常は監視2秒＋ADLX 2,000 ms、詳細診断は250 msから始める。設定の意味と採用条件は [BENCHMARK-RULES.md](BENCHMARK-RULES.md) を参照する。

## 実行順序

1. Git のブランチ、HEAD、作業ツリーを記録する。承認済みのビルド先を明示し、Vulkan と ROCm で分ける。成功済みの出力を保持する場合は新しい専用ディレクトリを使う。VS2022 x64 とバックエンドの SDK を同一 PowerShell 5.1 プロセスに準備する。
2. 対象ソースの要求版を確認し、Codex 専用キャッシュ `C:\llama-build\automation\_deps` を検証する。レビュー済み b12651 の Codex ラッパーは、通常ビルドと ConfigureOnly で公式 BoringSSL / LLVM OpenMP の不足分を取得できる。BoringSSL はタグ・HEAD・固定 SHA・取得元・作業ツリーを照合し、OpenMP は配布ファイルとライセンスの upstream SHA-256、および展開済みの必要ファイルを検証する。一時領域で準備して検証後に公開し、同じ依存に対する並行取得はロックで直列化する。破損キャッシュ、取得失敗、未レビューの upstream 入力は configure 前に停止する。
3. 既存の `Build-Vulkan.ps1` または `Build-ROCm.ps1` に専用 `-BuildDir`、`-DependencyCacheRoot`、`-Parallel 4` を渡す。Vulkan は確認済みの `-CMakeExe`、`-VulkanSdk`、`-LlvmBin` を指定する。ROCm は TheRock を有効化済みの環境で `-ExpectedRocmSdkVersion '10.0.0'` と `-AmdGpuTarget gfx1151` を指定する。
4. `-ConfigureOnly` と `-ExtraCMakeArgs @('-DLLAMA_BUILD_UI=OFF', '-DLLAMA_USE_PREBUILT_UI=OFF')` で再現する。終了コード `0` とキャッシュ上の UI 両フラグ `OFF`、選択されたコンパイラ、SDK、依存の出所を確認する。ROCm の場合は `GGML_HIP=ON` と `AMDGPU_TARGETS=gfx1151` も確認する。
5. 同じ PowerShell とビルド先で `-BuildOnly` を実行する。このモードは既存 CMake キャッシュを使ってメタデータを更新し、configure と生成を再実行する。更新後も UI が `OFF` で、UI 取得処理がログに現れていないことを確認する。
6. `bin\Release\llama-cli.exe --version` と `--list-devices` がともに `0` で終了し、期待するバックエンドで Radeon 8060S が出ることを確認する。`bin\Release\evox2-build.json` の `BuildIdentity.Status=Verified`、ソースと実行ファイルのコミット、実際の CMake・コンパイラ・SDK、スモーク結果を確認する。ROCm の場合は TheRock コピー元と DLL の SHA-256、rocBLAS/hipBLASLt データツリーのダイジェスト、および `gfx1151` データを確認する。

リモートで標準出力と標準エラーを別々の一意名で `C:\llama-build\_logs\codex` に記録し、configure、ビルド、各スモークの終了コードと所要時間を残す。SSH が切れたら、再実行の前にプロセスとログを確認する。非ゼロ終了、SDK/キャッシュ不一致、UI 取得、期待デバイスの欠落、マニフェスト不一致があれば停止し、失敗箇所とログを報告する。失敗したビルドディレクトリは保存する。詳細は [既知の問題](KNOWN-ISSUES.md)。

## P-MODE の取得

対応する作業ブランチの計測ラッパーでは、直接WMIの読み取りに失敗した場合、計測ラッパーはTask Scheduler COMで既存の `\Evox2\PModeProbe` を引数なしで起動する。 `ai` のInteractiveログオンが必要で、結果ファイルの新規更新を検証する。保護先、管理者による更新・SHA-256確認、通常ユーザーでの検証コマンド、障害時の切り分けは [P-MODE 読み取り運用](PMODE-PROBE.md) を参照する。

## b12037 の確認記録（2026-11-23）

旧 b12037 の手順では共有キャッシュを読み取り専用で検証し、不足分を専用キャッシュにコピーした。追加取得は明示承認を要し、キャッシュが不足すると configure 前に停止した。ROCm の成功時は `-DFETCHCONTENT_FULLY_DISCONNECTED=ON` も指定した。

確認ソースは `9de09c6106daf13f26134a4a453a200c73c45bbb`、CLI は `0.7.0-dev` の build `12037`。BoringSSL `0.20261020.0` を両方で再利用し、Vulkan では LLVM OpenMP `20.1.8` も再利用した。

| バックエンド | 結果 |
|---|---|
| Vulkan | `build-vulkan-codex`。UI 両設定を OFF にして configure と build が成功し、`Vulkan0` に Radeon 8060S を確認。BuildIdentity は Verified。 |
| ROCm | `build-rocm-codex`。TheRock 10.0.0 / `gfx1151` で configure と build が成功し、`ROCm0` に Radeon 8060S を確認。TheRock DLL 8 本と両ランタイムデータツリーのハッシュが一致。BuildIdentity は Verified。 |

文書取り込み後の `bf3026f32915a88a96f9131636820dbcd45aaeed` からの再ビルド、モデル推論、バックエンド演算テスト、ベンチマークは **未検証**。このスモークはビルドの来歴とデバイス列挙を確認する。

## b12651 の再現コマンド

Windows PowerShell 5.1 で `C:\llama-build\automation\llama.cpp-evox2-windows` のルートから実行する。clone のパスは変更しない。以下は未使用の短いビルド先を指定する例。既存の出力や失敗時のログは保存する。

```powershell
$wrapper = '.\tools\evox2\automation\Invoke-CodexBuild.ps1'
$clang = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\Llvm\x64\bin'

& $wrapper -Backend Vulkan -BuildDir build-vk2 -VulkanLlvmBin $clang `
    -ExpectedVulkanClangVersion 22.1.3 -CpuAllVariants OFF -PreflightOnly
& $wrapper -Backend ROCm -BuildDir build-r2 -PreflightOnly

& $wrapper -Backend Vulkan -BuildDir build-vk2 -VulkanLlvmBin $clang `
    -ExpectedVulkanClangVersion 22.1.3 -CpuAllVariants OFF
& $wrapper -Backend ROCm -BuildDir build-r2
```

`-BuildDir` は clone 直下の未使用の `build-*` 名を指定する。configure と build にはクリーンな作業ツリーが必要。SSH セッションで必要な場合は PowerShell 起動時に `-ExecutionPolicy RemoteSigned` を指定する。

各コマンドが終了コード 0 だったことを確認してから次へ進む。キャッシュ不足で preflight が停止し、公式依存の取得が許可されている場合は、通常ビルドまたは `-ConfigureOnly` がツールの確認後に依存を取得する。ネットワーク取得を禁止するときは通常ビルドにも `-Offline` を付ける。preflight は依存とビルド先を変更せず、検査ログだけを出力する。

外側ラッパーの通常呼び出しは、同じ Windows PowerShell 5.1 プロセス内で内側の `ConfigureOnly`、実キャッシュ検証、`BuildOnly` の順に実行する。外側の `ConfigureOnly` は実キャッシュ検証までで、通常呼び出しとは別の未使用ディレクトリを指定する。上の例に `-Offline` を付けて作業5-2の経路を再現できる。旧 main の依存構成は既存の検証済みキャッシュのみを再利用する。

| Release 構成 | 所要時間 | BuildIdentity | llama-cli.exe SHA-256 |
|---|---:|---|---|
| Vulkan・VS2022 x64、VS2026 Clang 22.1.3、Vulkan SDK 1.4.357.0、OpenMP 22.1.8、CPU全バリアントOFF | 140.34 秒 | Verified | `2e7f5135ded3917d20a1d9183c9ef04b74beea9fcdfad16ee7e7d845b3590abe` |
| ROCm・VS2022 x64、TheRock 10.0.0、AMD Clang 23.0.0git、gfx1151 | 440.44 秒 | Verified | `b1fa09954e77510aa0db1d2bab35faf70f1e4662dd9f631f185a5a7b42029e6a` |

両ビルドは Radeon 8060S のデバイス列挙と旧 IQ3 の短文生成を確認済み。全実行ファイルのハッシュ、条件、ログは [b12651 ベースライン記録](UPSTREAM-B12651-20261124.md) を参照する。

## b12037 用 Codex ラッパーの確認記録（2026-11-23）

2026-11-23 の実装確認では PowerShell 5.1 パーサーと UTF-8 BOM の確認が通過した。Vulkan preflight は終了コード `0`（1.88秒）、ROCm preflight は終了コード `0`（2.22秒）。両方ともビルド先を作成しなかった。この日のラッパー検証は preflight まで。当時の引数とキャッシュ運用は [b12037 用ラッパーの記録](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/0b4d4ab837b52b9fdef94aedc7543298e41cc107/docs/evox2/automation/RUNBOOK.md#codex-専用ラッパー) を参照する。

## 2026-11-23 旧 IQ3 推論スモーク（UMA 64 GB）

BIOS UMA 64 GB は実行前に運用者が確認した。`Measure-LlamaCli.ps1` と Git 管理外の設定を使い、既存の b12037（`9de09c610`）で Vulkan、ROCm をこの順に各1回実行した。両 CLI はマニフェストの BuildIdentity が Verified で、実行前の SHA-256 は保存済みの値と一致した。モデルは Qwen3.8-Flash-Next 旧 IQ3（3シャード）。Context 4096、GPU layers 999、CPU MoE 0、batch 2048、ubatch 1024、threads 4、KV f16、Flash Attention auto、MTP OFF。AllocationOnly の固定プロンプトに両方とも `OK` と応答し、最大32トークンの設定で実測は各2トークンだった。

| バックエンド | 終了コード | GPU 配置 | CLI 開始からモデル準備完了 | PP / TG (tok/s) | GPU 自プロセス使用 (MiB) | 物理空き最低 / コミット最大 (GiB) | ADLX |
|---|---:|---:|---:|---:|---:|---:|---|
| Vulkan0 | 0 | 49/49 層 | 48.60 秒 | 13.19 / 5.33 | 50,737 | 27.61 / 89.27 | 終了 0、27 サンプル |
| ROCm0 | 0 | 49/49 層 | 44.23 秒 | 38.04 / 26.68 | 50,837 | 29.81 / 88.05 | 終了 0、24 サンプル |

GPU メモリ値は CLI 終了時の内訳で、ピーク値は未計測。ADLX は利用率などを記録したが VRAM 欄は欠損。付属 ResourceMonitor は WMI アクセス拒否で0サンプルだったため、別の `resources.csv` に CLI 起動前から終了後まで物理メモリ、コミット、プロセスのメモリを保存した。ページングカウンターは取得できず、ページングの有無は未判定。Vulkan 終了後にプロセスが消え、物理空き 55.78 GiB、コミット 9.87 GiB、Vulkan の空き 108,610 MiB に戻ったことを確認してから ROCm を起動した。GPU エラーやメモリ枯渇による停止は無かった。PP/TG は18トークンの入力と2トークンの生成に限った値。

生ログの保存先は EVO-X2 の `C:\llama-build\_logs\codex`。

| バックエンド | CLI stdout・stderr・結果・ADLX | 起動前と補完リソース記録 |
|---|---|---|
| Vulkan | `20261123-164740-543-cli-vulkan-b12037-ctx4096-c1033772a5a6` | `iq3-Vulkan-baseline-20261123-164655-54f786b214794740a477a46bf128f16e` |
| ROCm | `20261123-165108-885-cli-rocm-b12037-ctx4096-0e6201be05e2` | `iq3-ROCm-baseline-20261123-165020-5813cdc0433d44cb822e2cca433ce6e7` |

### 無人計測の run 単位の停止手順

作業3-4では ThinkPad が実行順を保持し、各セルを一意の `-RunIdPrefix` と `-OnlyRound`／`-OnlyVariant`（別タスクは `-OnlyJob`）で絞り、`-PlanOnly -MaxRuns 1` を確認してから `-MaxRuns 1 -StopOnError` で起動した。SSH は既存の運用オプションに加えて keepalive を使う。後続セルの起動は ThinkPad 側で判断する。

1. 実行前に System／Application の最新 EventRecordID、起動時刻、P-MODE、空き RAM、コミット、WDDM GPU Dedicated、既存プロセスを記録する。各 run で対象ワークロードと機器を照合する。
2. 各 run の SSH 終了コード、`matrix-result.json` の `Complete` と1件の OK、子 `result.json`、bench のネイティブ PP/TG 行、残留プロセスを確認する。対象と全モニターが終了してから次へ進む。
3. 開始時の基準に対する終了後の RAM・コミット・GPU メモリ、P-MODE を確認する。詳細監視の 128 MiB 判定と、計測を続行できるかの安全条件は別に扱う。作業3-4の空き16 GiB・コミット増加4 GiB・GPU Dedicated 増加4 GiB は当時の開始／終了ゲート。実行中の全サンプルが閾値内であったことを示さない。
4. 前回の EventRecordID より新しいイベントを System／Application で確認する。Display/GPU ドライバ、WHEA、BugCheck、リソース枯渇などを対象にし、WER は実際の障害発生時刻を照合する。正常なチャネルでの `NoMatchingEventsFound` は0件。アクセス拒否、読取り失敗、カーソル巻き戻りは安全確認失敗として停止する。
5. SSH 切断、異常終了、新規重大イベント、持続的な回復不良、P-MODE の変化があれば後続セルを送らず、ログを保存して報告する。自動再試行・再接続・再起動を行わない。1接続で送るのは1セルなので切断時に実機側が次のセルを起動することはない。

標準 Matrix は実行順、絞り込み、結果・残留 PID 記録、`-StopOnError`、任意の `SafetyGate` による開始／終了の確認を提供する。SSH の監督、複数の単独呼び出しに共通の回復基準、イベントカーソルによる監査、後続セルの開始条件は作業3-4の ThinkPad 側の手順。標準 Matrix 単体で SSH 切断や Windows の重大イベントを監査する機能はない。 [作業3-4の実行記録](BENCHMARK-MATRIX-ROUNDS-B12651.md#event-log-readers-追加後の再開)
