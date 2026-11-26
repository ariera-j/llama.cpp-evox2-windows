# EVO-X2 標準ビルドツール統合（作業5-1〜5-2、2026-11-26）

GitHub の `main` を標準ビルドツールの正本とする。現行製品ブランチ `codex/vulkan-manifest-cpu-variants-20261124` は同じ標準ファイルを使う。実機の構成と起動手順は [RUNBOOK](RUNBOOK.md) と [ビルド README](../../../tools/evox2/build/README.md) を参照する。

作業5-4では B・A・D の改善版を短い登録 worktree から両バックエンドで実ビルドし、GitHub main の標準ビルド・計測ツールに採用した。以下は作業5-2時点の記録。現行の操作と検証範囲は [作業5-4の実ビルド検証](BUILD-VALIDATION-20261126.md) を参照する。

## 採用元と差分

開始時の GitHub main は `2bce03311306c3d0367349e85db4420455ab283a`、現行製品と実機専用 clone は `f500e9b070f3e6065dde50309def74d83cf9ddd4`。製品上の専用作業ブランチ `codex/build-integration-20261126` でツール差分を検証した。両 Release の実ビルド元と製品側ツールコミットは `170552d0a2a7bc481bb7f5b4828ebae7d7bb3306`。main のツールコミットは `ea8b6a6ac6b472fefa427c8ff3ade59a515b3934`。文書は後続の文書専用コミットに収録。

| パス（`tools/evox2/` 配下） | 採用元と変更 |
| --- | --- |
| `automation/Invoke-CodexBuild.ps1` | 製品側。Clang の明示指定、CPU variant、Offline、固定パス・ツール検査、configure 後の実キャッシュ検査、来歴とスモークの照合を取り込んだ。 |
| `build/Build-Vulkan.ps1` | 製品側。実 CMake Cache の CPU variant をマニフェストに記録し、明示設定との不一致、欠損、不正値、重複を拒否する。変更元は `f4f1aa3e8`。 |
| `build/Build-ROCm.ps1`、`build/Evox2.Build.psm1` | 製品側。main との差は UTF-8 BOM。TheRock ランタイムの検証とマニフェスト schema 1 を共有する。 |
| `build/Evox2.DependencyCache.psm1` | 製品側の公式依存準備 `4311e2a2a`、入力監査 `35818246a`、固定 ROCmFPx CMake blob の許可を採用。旧 main の入力は開始 SHA に照合して既存キャッシュのみを使い、BoringSSL の origin／固定 SHA と OpenMP の必要ファイルを検証する。 |
| `build/Test-Evox2DependencyInputs.ps1`、`build/Test-Evox2VulkanCpuAllVariants.ps1` | 製品側の既存テストを取り込んだ。 |
| `build/README.md`、`lib/Evox2.Common.psm1` | 開始時に両枝で同じ blob。README に標準ツールと依存の適用範囲を追記。共通モジュールは作業3-5の版を使用した。 |

旧 main の依存構成は BoringSSL `0.20261020.0`／`d3bf4795ad5b79d646cddf2fec687da5b9b502db`、Vulkan OpenMP `20.1.8`。b12651 系は BoringSSL `0.20261105.0`／`3dc4b63808921e914a3fb1fa61869abc3938781b`、Vulkan OpenMP `22.1.8`。通常／ConfigureOnly の不足分取得はレビュー済み b12651 系の公式依存だけ。PreflightOnly と Offline は既存キャッシュを使う。両内側ラッパーの既存引数、既定値、位置順、BuildOnly、ManifestOnly、ExtraCMakeArgs、ExtraTargets、直接実行時の依存キャッシュ処理と SDK／コンパイラ検証を保持した。製品ソースの比較は各枝の開始 SHA を基準に行い、ビルド・運用文書の指定パスのみを統合した。

## 非推論検証

- Windows PowerShell 5.1.26100.10068 で対象8ファイルの構文、UTF-8 BOM、予約変数 `$input` 代入、モジュール import、既存引数の属性・型・既定値・順序、対象パスの `git diff --check` を確認。CPU variant テストはマニフェスト6件と拒否7件。依存入力テストは変更、追加、削除、ignored module、npm・submodule を検出。
- 隔離した空キャッシュは Offline で拒否し、キャッシュを作らなかった。隔離した破損ライセンスは SHA-256 不一致で停止。main 用 worktree で旧構成の既存キャッシュは Vulkan／ROCm とも通過し、取得を有効にする引数を渡した空キャッシュでも停止した。
- 製品専用 clone の両 `PreflightOnly -Offline` が終了0。出力ディレクトリは作られず、Git 作業ツリーもクリーン。依存キャッシュのディレクトリ一覧・サイズ・更新時刻の観測範囲に変化なし。BoringSSL のタグ、HEAD、origin と OpenMP 4ファイルの SHA-256 を各 preflight の検証に使用した。
- 既存 `build-s2v`／`build-c1r` の schema 1 マニフェストは読み取り専用で使用。標準計測側の `Read-Evox2BuildManifest` と `Test-Evox2RuntimeArtifacts` が CLI／bench 4件を識別し、標準対象のハッシュ検証はすべて Verified。旧 Vulkan の CPU variant 表示は当時のマニフェストを保持した。
- 新しい両 CLI は標準計測側の `Get-Evox2LlamaIdentity` で隣接マニフェスト、埋め込みコミット、実行ファイル／DLL とデバイスを照合した。両 bench も標準のアーティファクト照合が Verified。検証時の処理は CLI の非推論メタデータ取得とファイルハッシュ。

## Release 実ビルド

専用 clone で `PreflightOnly -Offline` の後、各バックエンドを通常モードで1件ずつ実行した。外側ラッパーの内部ログに `ConfigureOnly`、実キャッシュ検査、`BuildOnly`、ビルドメタデータ再生成、CLI スモークの来歴を保存した。各 CMake 呼び出しは非ゼロ終了を停止条件とし、両バックエンドで外側ラッパーの終了コードは0。下表の所要時間は通常ラッパー全体の実測値。フェーズ単独の時間は収集対象外。

| 実測項目 | Vulkan | ROCm |
| --- | --- | --- |
| 出力 | `build-w5v/bin/Release` | `build-w5r/bin/Release` |
| PreflightOnly／ConfigureOnly／BuildOnly | 0／0／0 | 0／0／0 |
| preflight／通常ラッパー | 2.458秒／151.283秒 | 3.053秒／442.043秒 |
| コンパイラ・SDK | Clang 22.1.3、Vulkan SDK 1.4.357.0、OpenMP 22.1.8 | AMD Clang 23.0.0git、TheRock 10.0.0、`gfx1151` |
| CLI `--version`／`--list-devices` | 0／0、b12690、`Vulkan0` Radeon 8060S | 0／0、b12690、`ROCm0` Radeon 8060S |
| BuildIdentity／埋め込み | Verified／`170552d0a` | Verified／`170552d0a` |
| CLI SHA-256 | `e01b0dbc0b48a420d3944d9abd3ca82d244d78ecc0793cdfe5700460208db56a` | `0a37dae2baef47a74817fdb12755354317a109452eb40dae1e258f48e0890dcf` |
| `evox2-build.json` SHA-256 | `bdeef91d663e854e11efdff2a209ddc5dd7a66c7f5f61dfdd154042e6005a4b7` | `c77210e008e4a0e52ddc3ce2829047a7ce459d87d3d311a2c6597a4399afe4e5` |

両方とも VS2022 x64、MSVC 14.44.35207、CMake 3.31.6-msvc6、Ninja 1.12.1、Ninja Multi-Config、Release、並列4。BoringSSL は専用キャッシュの `0.20261105.0`。UI と prebuilt UI は OFF、FetchContent は完全切断。実 CMake Cache の主要設定を Vulkan は `build-s2v`、ROCm は `build-c1r` と比較した。Vulkan は CPU 全バリアント OFF、Sapphire Rapids ターゲットなし、`GGML_NATIVE=OFF`、`GGML_BACKEND_DL=ON`。成果物の libomp.dll は既存キャッシュの SHA-256 と一致。ROCm は `GGML_HIP=ON` と `AMDGPU_TARGETS=gfx1151` を確認し、TheRock DLL 8本の SHA-256、rocBLAS と hipBLASLt のデータツリーのコピー元・先の digest、および両方の `gfx1151` ディレクトリを照合した。ROCm configure では SDK の `AMDGPU_TARGETS` 非推奨通知と `CMAKE_HIP_COMPILER` 未使用の警告が出た。実 Ninja グラフの `--offload-arch=gfx1151`、ビルド時の AMD Clang とデバイス結果で構成を確認した。

ROCm データツリーの digest をファイル一覧・サイズ・各 SHA-256 から再計算し、マニフェストと照合した。rocBLAS は150ファイル、`3a6de928ed5ec7c2c7eac5cd98d1fa5e872c20643a81488bdfc755f9a94e11b3`。hipBLASLt は100ファイル、`0a9dd8a70063551cbc7e358599165fd8c007af8e458e4554ea858ae8ff5a759d`。

各ビルドの前後で Windows 起動イベント、物理 RAM・コミット、System／Application のイベントカーソル、ビルド・llama プロセスを確認した。両方で同じ起動期間、残留なし、対象の重大イベント0件。System／Application は全区間で RecordID 69637／43771。空き物理 RAM は Vulkan 25.477→24.296 GiB、ROCm 22.650→25.355 GiB。コミットは Vulkan 9.591→10.681 GiB、ROCm 12.470→9.746 GiB。Vulkan 起動前の補助ディスク確認では SSH 上の `Get-PSDrive` から空き容量が得られず、ラッパー起動前に停止した。空きは `DriveInfo.AvailableFreeSpace` で確認してから、同じ設定で初回のラッパー呼び出しを行った。確認データを生ログに保存した。

成果物は `C:\llama-build\automation\llama.cpp-evox2-windows` の下にある。ログの正本は `C:\llama-build\_logs\codex`。次の stem に `.stdout.log`、`.stderr.log`、`.result.json` が付く。

| バックエンド | PreflightOnly | 通常ビルド |
| --- | --- | --- |
| Vulkan | `build-Vulkan-Preflight-8771b214a76e4e289b277b86c1114a8a` | `build-Vulkan-Build-7acaa90adaf9400fbc713e2574d71bb0` |
| ROCm | `build-ROCm-Preflight-d53737720bd34f35a4c388343534f097` | `build-ROCm-Build-00f0c74a9f2e47239957a8cbd951bf70` |

補助ログ `w5-build-integration-170552d` に、前後の状態、イベント差分、Ninja 進捗・PID・CPU 時間・Working Set、マニフェスト検証、全 EXE・DLL ハッシュ、PE import を保存した。 [全 EXE・DLL とマニフェストの SHA-256](build-integration-20261126/artifact-sha256.csv) · [検証コマンド](#再現手順)

### 再現手順

`170552d0a2a7bc481bb7f5b4828ebae7d7bb3306` のツールと製品ソースを固定 clone で選ぶ。 [RUNBOOK の b12651 手順](RUNBOOK.md#b12651-の再現コマンド) に従い、新しい短い名前を選んで各呼び出しに `-Offline` を渡す。同一バックエンドで preflight と通常呼び出しを行い、通常呼び出しの終了後に結果 JSON、実 CMake Cache、機器状態を照合してから次へ進む。当時の成果物を再確認する場合は [Verify-Build.ps1](build-integration-20261126/Verify-Build.ps1) で既存の結果 JSON と出力を読み取れる。検証スクリプトには `-Backend`、`-RepoRoot`、`-BuildDir`、比較元の `-ReferenceDir`、実ビルド元の `-BuildCommit`、通常呼び出しの `.result.json` を `-WrapperResult` で渡す。評価範囲は構成、ビルド、CLI 識別・デバイス列挙、マニフェスト。旧 main ソースからの Release 再ビルド、依存のネットワーク取得、モデルロード・推論・性能計測・演算テストは未実施。

実験ブランチへの取り込みは main のツールコミットを固定して、上表のパスと当該ブランチの差分を確認する。ツールのファイルだけを取り込み、タグ・既存成果物と独自パッチを維持する。ソース SHA とツールの採用 SHA の両方を記録する。 [計測ツールの従来手順](BENCHMARK-INTEGRATION.md)

## 作業5-3の設計候補

1. **B. ランタイム DLL の照合。** PE の import を読み取り、`llama-bench.exe → llama-bench-impl.dll`、`llama-cli.exe → llama-cli-impl.dll → llama-server-impl.dll → mtmd.dll`、`llama-server.exe → llama-server-impl.dll` を確認した。Vulkan の `ggml-base.dll` と `ggml-cpu.dll` は `libomp.dll` を import する。これらの DLL と構成依存の `ggml-rpc.dll` は現行 schema 1 の共通 Artifacts 対象外。EXE ごとの推移 import と有効構成の動的バックエンドをビルド時に解決して、必須ファイルと任意プラグインを明示した追加項目で記録する。計測側は EXE 起動前に必須欠損と記録済みハッシュの不一致を止め、追加項目がない旧マニフェストは従来の検査を使用する。ROCm の既存 Runtime 記録とデータツリー digest も接続する。ROCm は ggml-base／ggml-cpu が libomp140.x86_64.dll、Vulkan は ggml-vulkan が vulkan-1.dll を外部から import する。実機の System32 に両ファイルが存在する。MSVC 再頒布 DLL とあわせて、外部ランタイムの識別情報を同梱 DLL の判定と区別して記録する案を検討する。実プロセスのロード元パスの確認は未実施。 PE import からは動的ロードを完全には列挙できないため、CMake 設定とバックエンドローダーを照合する。
2. **A. Codex ラッパーの worktree 対応。** 既定の専用 clone を維持する。登録済みで承認された automation 配下の worktree だけを候補にし、正規化した実体パス、祖先・出力・キャッシュの reparse point と ACL、`git worktree list`、共通 Git ディレクトリ、remote、固定ソース SHA、clean と依存監査を照合する。出力は検証済みの worktree 内の短い未使用先とし、既存キャッシュの保護と開始・終了時の Git 来歴検証を共有する。
3. **D. 中断時の記録。** 現行ラッパーの stdout／stderr と終了 JSON に加えて、親と子の PID、開始時刻、Ninja ターゲット進捗、コンパイラのコマンド、CPU 時間・メモリ、段階別の状態を、SSH が切れても実機に残る方法で記録する。接続復旧時は PID と開始時刻、ログ、出力を照合してから再開可否を判断する。Ninja の版のような単一行は配列化してから先頭要素を選び、進捗の CR 書き換えと改行の両方を扱う。ADLX ビルドスクリプトの両枝差は先頭 BOM。次の独立レビューで揃える候補。手順の版は README から現行 RUNBOOK へ誘導し、過去の構成は固定記録を参照する。
4. **C. CMake の Git index 警告。** 診断 worktree の `.git` は `gitdir: C:/…/.git/worktrees/w43diag`。Git の `rev-parse --git-path index` が返す実体は存在する。CMake は最初のスラッシュが位置0のときだけ絶対パスと扱い、Windows のドライブ付き絶対パスへソースパスを付加するため、index を構成再生成の依存に登録できなかった。一方、`cmake/build-info.cmake` は Git コマンドで短縮 SHA とコミット数を取得し、明示 configure と BuildOnly 時の再生成で埋め込める。現行の明示再生成と BuildIdentity 検査を継続し、将来 CMake を修正する場合は Git が解決した index パスを使い、通常 clone・worktree・サブモジュール、Windows と他 OS でメタデータ更新を確認する。
