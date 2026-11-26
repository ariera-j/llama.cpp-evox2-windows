# EVO-X2 標準ビルドツールの追加改善（作業5-3、2026-11-26）

現行製品 `7be783173567a87d9318808ee5d7643e89704e68` を基準に、`codex/build-improvements-20261126` を `C:\llama-build\automation\w53` で検証した。開始時の GitHub main は `b51f94d1df72c36aea7b7491e6a5cada8845561a`。参照した両 Release の実ビルド元は `170552d0a2a7bc481bb7f5b4828ebae7d7bb3306`。作業5-3の成果はこの専用枝へ保存する。標準化の反映は作業5-4の Release 検証後に判断する。 [作業5-2の統合・実ビルド記録](BUILD-INTEGRATION.md)

| 改善 | コミット | 対象 |
| --- | --- | --- |
| B | `9712dc7bc2fedcb466e37ee1e389f493231b9cc4` | `Evox2.RuntimeDependencies.psm1`、`Evox2.Common.psm1`、`Evox2.Build.psm1`、`Measure-LlamaBench.ps1`、ランタイムテスト |
| A | `5dc52c74c186d2c173eb333a8a050334b4f7eaba` | `Invoke-CodexBuild.ps1`、`Evox2.BuildLocation.psm1`、worktree テスト |
| D | `11d5c7b751f55a19c409b04d1060429d1640b6ac` | 外側ラッパーとワーカー、`Evox2.BuildState.psm1`、状態テスト |
| B の入口確認 | `078d0548aab3a3c2853b5233f82aab2d3b912508` | 拡張結果の停止条件、ワーカーからの最終照合、Measure／Matrix の互換性テスト |

## B. ランタイムの検証

schema 1 の `Artifacts`、`Runtime`、`BuildIdentity` を保持し、Release の `RuntimeDependencies` version 1 を追加した。既存 VS の `dumpbin /DEPENDENTS` で CLI、bench、server と Release 直下の DLL を読み取り、同梱 import の推移閉包を EXE ごとに記録する。作業5-2の結果では CLI／server の実装 DLL、bench の実装 DLL、`mtmd.dll`、`libomp.dll` の依存に加えて、PE import では現れない RPC プラグインを確認した。CPU・GPU の動的バックエンドは実 CMake Cache と `ggml_backend_load_all_from_path` の探索を根拠に扱う。

- `Files` には全同梱 DLL と対象 EXE のハッシュ、ファイル種別、同梱／外部 import を記録する。製品と同梱 SDK／コンパイラランタイムを別種別にする。
- `Executables.Required` は対象 EXE の推移依存と `ConfigurationRequired` の閉包。構成に有効な単一 CPU・GPU バックエンドと同梱ランタイムを必須とする。CPU 全バリアント構成では、列挙した候補のうち少なくとも1個を要求する。RPC などの任意プラグインは欠損を許し、存在する場合は自身のハッシュと同梱 import を検証する。
- TheRock の DLL とデータツリーは従来の `Runtime` と照合する。データツリーは相対名、長さ、各ファイルの SHA-256 から digest を再計算する。reparse point とディレクトリ外参照を拒否する。
- `External` は PE の import 名と、取得可能な System directory 上の候補パス、ファイル版、SHA-256 を記録する。ROCm の `libomp140.x86_64.dll`、Vulkan の `vulkan-1.dll`、VC ランタイムや API set 等を含む。外部ファイルの差は同梱検証の停止条件に含めない。実ロード元、遅延解決や任意の動的プラグインの全列挙は未確認。
- 旧マニフェストは `Scope=LegacyArtifacts` で既存検査を使う。拡張付きは `Scope=RuntimeDependenciesV1`。欠損・重複・不正な拡張は停止させる。Measure の CLI／bench は EXE メタデータ取得より先に検査し、bench では `--help` の前にも適用される。Matrix の実行は同じ Measure の経路を使う。
- `ManifestOnly` の拡張は `Provenance=Observed`、検証結果は `Unverified`。来歴を照合できた当該呼び出しの実ビルドは `BuildCompleted` を記録する。今回の作業5-2成果物の PE 読み取りはメモリ内の観測で、既存マニフェストに書き込んでいない。

## A. 承認済み worktree の使い方

従来の専用 clone の呼び出しを保持した。新経路では対象 worktree 内にあるラッパーを使い、レビュー済みの完全 SHA を `-Worktree -SourceCommit <SHA>` で明示する。worktree は `C:\llama-build\automation` 直下の `w` と2〜4桁の数字。GitHub の枝名は独立して選ぶ。

実体パスと祖先・Git 管理領域・キャッシュの reparse point、Git 登録、専用 clone と共通の Git dir、固定 GitHub remote、完全 SHA、clean、出力名と既存出力との衝突を確認する。Windows の ACL は有効アクセスで読み、出力先の親とログ領域への既存権限を検査する。固定の専用依存キャッシュと既存の依存入力監査を使用する。開始・終了の SHA と clean 状態、外側／内側スクリプトのハッシュを保存する。

`PreflightOnly` のログにはソースと出力ルートの絶対パスと文字数が出る。作業5-2の成功時の Vulkan 出力ルートを超える worktree パスは注意を出し、出力ルート自体が Windows の従来の MAX_PATH に達する場合は停止する。CMake、Ninja、MSVC の生成パスはさらに深いため、短いルートでも成功保証にはしない。作業5-4は `w54` と `build-vk`／`build-rm` を使う。 [過去のパス長エラー](KNOWN-ISSUES.md#b12651-vulkan-で確認したビルド上の制約)

## D. 状態と復旧時の読み取り

既存の `.stdout.log`、`.stderr.log`、`.result.json` を同じ一意 stem で維持し、`.state.json`、`.worker.json`、実行中は `.progress.jsonl` を追加した。レコードは EVO-X2 の `C:\llama-build\_logs\codex` が正本。5秒間隔のサンプルとフェーズの切り替わりを記録する。状態 JSON は同一ディレクトリの一時ファイルから置換する。Ninja の CR／LF に対応し、直近32 KiB から進捗とファイル名を抽出する。プロセス記録は PID と UTC 開始時刻、親 PID、CPU 時間・Working Set を含む。コンパイラのコマンドは実行名、ソース／ターゲット名、許可した最適化・アーキテクチャ引数の抜粋。コマンド全文や環境変数は記録しない。

再確認は `Evox2.BuildState.psm1` の `Read-Evox2BuildState -Stem <絶対パス>` を使う。完了結果が読めるときは `Succeeded`／`Failed`、PID と開始時刻が一致するワーカーを観測できるときは `Running`、それ以外は `Unconfirmed`。過去サンプルと同一と確認できた残留プロセスは `LiveProcesses`。処理は既存のフォアグラウンド呼び出しと同じ。中断後は実機ログと残留を照合してから運用者が判断する。

## 非推論テスト

| 対象 | 結果 |
| --- | --- |
| 共通 | Windows PowerShell 5.1.26100.10068。変更した PowerShell 13ファイルの構文・BOM・予約変数、モジュール import、既存位置引数の定義、`git diff --check` 通過。 |
| B | 正常新旧、必須の欠損とハッシュ不一致、任意欠損、構成にないバックエンド、EXE ごとの依存、不正パスと重複・欠損拡張、外部のハッシュ差を確認。作業5-2の PE と TheRock DLL／データツリーを読み取り専用で照合。CPU variant 既存テストのマニフェスト6件・拒否7件を通過。 |
| Measure／Matrix | 模擬 EXE の CLI／bench で新旧 `DryRun`、両形式で `PlanOnly` が通過。不正な新形式の bench が `--help` 以前に停止。既存の Matrix・監視・OS 起動・RAM ライフサイクル用テストに加え、合成 `combined250` と cadence を確認。Matrix の品質テストは隔離先に新しい共通依存モジュールをコピーするよう更新した。 |
| A | 登録済み、明示未承認、別 repo、automation 外、トラバーサル、領域外 junction、SHA 不一致、dirty、出力名不正と既存出力を検証。依存入力テストと空キャッシュ Offline 拒否が通過。固定 clone と `w53` の両バックエンドで実 `PreflightOnly -Offline` が終了0。 |
| D | 模擬プロセスの終了0／7、stdout／stderr、単一行、CR 上書き、複数サンプル、子終了、開始時刻の不一致、結果・状態欠損時の復旧判定が通過。実 preflight でも状態・結果と開始／終了 SHA を照合した。 |

成果物の照合に使用した作業5-2の PE import CSV、全 EXE／DLL ハッシュ、実 CMake Cache とログは原位置に保持。今回の補助ログは `C:\llama-build\_logs\codex\w53-20261126`。実 preflight の state stem は固定 clone が Vulkan `53f2f29039f2454fb1b0269ca0b62b1b`、ROCm `1f199856c768448e99bdaae970b59315`、`w53` が Vulkan `627f9781d4314de188a7f5fb3d923be5`、ROCm `5e074d5130f74f91bb7fd5730b4205dc`。worktree のソース／出力は29／38文字。入口確認後の Vulkan 再確認は `c9804e892176492b8b45b18e16773b26`。検査範囲のキャッシュ情報、出力不在、Git clean を前後で照合した。ADLX ビルドスクリプトの枝差は先頭3バイトの UTF-8 BOM のみ。改善枝には既に BOM 付きの製品版がある。

## 作業5-4の実ビルド案

1. 採用候補の完全 SHA をレビューして固定する。固定 clone では従来経路の両 `PreflightOnly -Offline` を行い、専用 clone を現行製品へ戻す。
2. 同じ SHA を `C:\llama-build\automation\w54` に登録する。 `-Worktree -SourceCommit <固定 SHA> -Offline` で各 preflight を確認し、`build-vk` で Vulkan Release、終了確認後に `build-rm` で ROCm Release を各1回行う。Vulkan は VS2022 x64、Clang 22.1.3、Vulkan SDK 1.4.357.0、OpenMP 22.1.8、CPU 全バリアント OFF。ROCm は TheRock 10.0.0、AMD Clang、`gfx1151`。各出力で CMake Cache、状態・進捗、イベントと残留、CLI のバージョンとデバイス列挙、BuildIdentity、埋め込み SHA、新しい依存マニフェストを検証する。
3. 新旧マニフェストを Measure の非推論経路で照合し、採用 SHA と対象パスだけを main と現行製品に取り込む。成果物の来歴、実ビルド結果とログ参照を記録する。

worktree では CMake の Git index 警告が出る場合がある。明示的な再生成と埋め込み SHA、`BuildIdentity=Verified` で確認する。CMake 本体の変更と SDK の複数版対応は保留。将来の TheRock 対応ではバージョン別ルート、コンパイラと DLL の混在防止、ランタイムの隔離を設計する。実ロード元の追跡、本番コンパイル中の進捗と DLL 収集、改善版 Release の結果は5-4の確認対象。モデルロード、推論、性能計測、演算テスト、実 SSH 切断・OS 異常終了試験は対象外。
