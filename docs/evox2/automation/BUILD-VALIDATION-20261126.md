# EVO-X2 改善版ビルドツールの実ビルド検証（作業5-4、2026-11-26）

B・A・D の改善版を短い登録 worktree から Vulkan、ROCm の順に各1回ビルドした。使用したソースとツールは `20f48bfe162d8d886b9f5fea7ad6d7df91eb3266`。作業開始時の GitHub main は `b51f94d1df72c36aea7b7491e6a5cada8845561a`、現行製品は `7be783173567a87d9318808ee5d7643e89704e68`。検証済み標準ビルド・計測ツールの正本は GitHub main。 [作業5-3の設計と非推論検証](BUILD-IMPROVEMENTS-20261126.md)

## 実行条件と事前検査

固定 clone を一時的に採用 SHA に置いて両 preflight を行い、元の現行製品ブランチへ戻した。新規 `C:\llama-build\automation\w54` を同じ SHA の detached worktree として登録した。既存 `w53` の改善ブランチは開始時の HEAD を維持。両作業先の Git common directory は専用 clone の `.git`。外側ラッパーで登録、remote、完全 SHA、clean、親ディレクトリ・Git・専用依存キャッシュの reparse point と有効アクセス、出力名との衝突を検査した。

| 作業先 | Vulkan preflight | ROCm preflight | ソース／出力の絶対パス長 |
| --- | --- | --- | --- |
| 固定 clone | 0／2.848秒 | 0／3.008秒 | 49／58文字 |
| `w54` | 0／3.519秒 | 0／3.687秒 | 29／38文字 |

すべて `-Offline -PreflightOnly`。事前検査は出力を作成せず、専用キャッシュのパス・サイズ・更新時刻の観測値と保全対象マニフェスト5件のハッシュは前後で一致した。

## Release と非推論スモーク

両方とも VS2022 x64、MSVC 14.44 系、CMake 3.31.6-msvc6、Ninja 1.12.1 Multi-Config、Release、並列4、Offline。BoringSSL は `0.20261105.0`／`3dc4b63808921e914a3fb1fa61869abc3938781b`。UI と prebuilt UI を OFF、FetchContent は完全切断。作業5-2の同一バックエンドの実 CMake Cache と設定を照合した。外側ラッパーは内部で `ConfigureOnly`、実キャッシュ検証、`BuildOnly`、メタデータ再生成と CLI スモークを実行した。下表は外側の一括所要時間。

| 項目 | Vulkan | ROCm |
| --- | --- | --- |
| 出力 | `w54\build-vk\bin\Release` | `w54\build-rm\bin\Release` |
| configure／build 終了 | 0／0、148.962秒 | 0／0、441.376秒 |
| コンパイラと SDK | Clang 22.1.3、Vulkan SDK 1.4.357.0、OpenMP 22.1.8、CPU 全バリアント OFF | AMD Clang 23.0.0git、TheRock 10.0.0、`gfx1151` |
| CLI `--version`／`--list-devices` | 0／0、b12696、`Vulkan0` Radeon 8060S | 0／0、b12696、`ROCm0` Radeon 8060S |
| BuildIdentity／埋め込み | Verified／`20f48bfe1` | Verified／`20f48bfe1` |
| CLI SHA-256 | `e17f37d2cd6163f63fc68db683c7f68e11b3b09af9706f352dfdbb6419e9f3d3` | `ac1703d17e1be08ff8d3f7ce643a720f89fa40b108da663dc5922362a285752f` |
| マニフェスト SHA-256 | `ca47435a3507d39f5095724a2e38b0f962e36a1ce97c5547ef1a971ffdd515c4` | `dd08ffa6b9518ed2a7e8a4027fb0bcf5375a5fc9bf85ac6399d8adfd11d0bb43` |

作業5-3で特定した CMake の Git index 警告は 両バックエンドで確認した。Git が解決する index は実在し、明示再生成後の埋め込み SHA と BuildIdentity は両方で一致した。ROCm は作業5-2と同じ `AMDGPU_TARGETS` 非推奨通知と `CMAKE_HIP_COMPILER` 未使用警告が出た。実キャッシュと実コンパイルコマンドの `--offload-arch=gfx1151` を照合した。

起動時刻と System／Application のイベントカーソルを前後で照合し、両バックエンドとも同一 Windows 起動期間、重大イベント0件、残留プロセス0件。System／Application の RecordID は全区間 69638／43811。空き RAM／コミット（GiB）は Vulkan 25.314→25.136／9.754→9.902、ROCm 25.276→25.182／9.794→9.891。両方の終了後に各成果物を確認した。

## 実マニフェスト・計測互換性

両 `evox2-build.json` は schema 1、`RuntimeDependencies.Version=1`、`Provenance=BuildCompleted`。CLI／bench／server の検証は `Verified / RuntimeDependenciesV1`。PE を再読し、保存済み import、推移依存、実 CMake 設定と照合した。CLI は `llama-cli-impl.dll → llama-server-impl.dll → mtmd.dll`、bench は `llama-bench-impl.dll` が必須。動的 CPU／GPU バックエンドは構成上必須、`ggml-rpc.dll` は任意で存在時は厳格照合。Vulkan の `libomp.dll` は同梱必須。ROCm では TheRock DLL 8本と両 `gfx1151` データツリーの従来検証を維持し、保存 digest と実ファイルを再照合した。PE インベントリは Vulkan 15件、ROCm 22件。 [EXE、DLL、マニフェストの SHA-256](build-validation-20261126/artifact-sha256.csv)

`External` は PE import と System directory 上の候補、取得できたファイル版・ハッシュを記録する。Vulkan の `vulkan-1.dll`（ファイル版 `1.4.357.0`）と ROCm の `libomp140.x86_64.dll`（同 `20140926`）はどちらも System32 の環境側候補。実プロセスの DLL ロード元は未確認。外部の候補変化は同梱ファイルのハッシュ不一致と区別する。

作業5-2両版、`build-s2v`、`build-c1r`、`w43diag\build-ld` の CLI／bench は `Verified / LegacyArtifacts`。新両版と診断 b12690 で CLI／bench の `DryRun`、同じ3構成の6セルの Matrix `PlanOnly` を確認した。依存入力・CPU variant・ランタイム・worktree・状態記録・計測の回帰テスト8件が終了0。隔離 fixture で不正な新形式が `--help` を含む起動前に停止することを再確認した。実行プランには検証用のテキストファイルを指定し、モデルロードは行っていない。

| 検証時間の観測（秒） | Vulkan | ROCm |
| --- | ---: | ---: |
| 依存ハッシュ CLI／bench／server | 0.209／0.107／0.139 | 0.601／0.468／0.465 |
| rocBLAS／hipBLASLt digest 再計算 | — | 0.114／0.072 |
| 実 Measure DryRun CLI／bench 全体 | 40.94／40.66 | 41.00／41.01 |

ハッシュ行は `Test-Evox2RuntimeArtifacts` の1回の実測。ROCm の依存ハッシュ行は両データツリーを含む。データツリー行は個別の再計算。DryRun 全体は CLI メタデータと実機情報の取得を含む。診断版の DryRun は 40.53／40.57秒。Matrix の呼び出し経路を確認すると、各 Measure に依存検証が1回あり、Matrix 側に同じ依存検証の追加呼び出しはない。Measure 内では EXE の識別用 SHA-256 も取得する。検証時間は測定対象のモデルロード・PP/TG と区別する。 [全測定値](build-validation-20261126/verification-timing.csv)

## 状態・進捗とログ

`Read-Evox2BuildState` は両方 `Succeeded`。同一実行 ID で stdout／stderr、result、state、worker、progress を照合した。開始・終了、親・ワーカー・子 PID と開始時刻、Ninja 進捗、コンパイラの許可された抜粋、CPU 時間・Working Set を確認した。ROCm のサンプル内のコンパイラ最大 Working Set は334.43 MiB、同一プロセスの累積 CPU 時間の最大観測は43.81秒。短いフェーズは5秒サンプルに現れない場合があり、worker の最新フェーズと stdout の ConfigureOnly／実キャッシュ検査／BuildOnly／スモークの記録を組み合わせて確認した。6種類のログに認証情報の既知の形式が現れないことを検査した。

| 観測 | Vulkan | ROCm |
| --- | --- | --- |
| progress 行数／平均間隔／サイズ | 29件／5.10秒／39,100 B | 86件／5.10秒／178,101 B |
| 最終 Ninja スナップショット | 842/843 `test-backend-ops.exe` | 479/479 `test-backend-ops.exe` |
| コンパイラ抜粋を含むプロセス観測 | 17件 | 521件 |

ROCm の Ninja 番号は HIP ターゲットの163件とツール側の479件で別の系列。警告出力が32 KiBの読み取り窓を埋める区間では状態 JSON が前の進捗を保持した。17:53:04 JST の一例は状態33/479、同時刻の stdout 最終進捗56/479。詳細確認は stdout を併用する。

ROCm の実行途中に状態ファイルを読み、`Running / Build` と生存 PID を確認した。経過86.8秒時は9/163で、`clang++ -O3 --offload-arch=gfx1151` のコンパイルを記録した。結果ファイルと各ログは実機に保持している。試験のための SSH 切断や OS 異常終了は行っていない。

ログは `C:\llama-build\_logs\codex`。次の stem に `.stdout.log`、`.stderr.log`、`.result.json` が付く。通常実行には state、worker、progress も付く。補助の前後状態・新旧互換性・再集計ログは `w54-20261126` に保全した。

| 経路 | Vulkan | ROCm |
| --- | --- | --- |
| 固定 clone preflight | `build-Vulkan-Preflight-21e745baa9714bdd855db2c1a14d8e7b` | `build-ROCm-Preflight-f83aa1d5ec874f2a87bbed07de7fcd2b` |
| worktree preflight | `build-Vulkan-Preflight-b5b44a0503e54deb8616400a56dd8641` | `build-ROCm-Preflight-1aa2fd410aa44cda8bb22f7d6881b14a` |
| Release | `build-Vulkan-Build-b092ffc6622e4b69be9e03a8fb8cd4d7` | `build-ROCm-Build-97590367f8304c768fac5a7de1a88ffe` |

## 再現と運用

承認済みの完全 SHA と短い未使用の名前を選ぶ。以下は今回の条件。成果物を保全するため、再実行では新しい登録 worktree と未使用の出力を使う。

```powershell
$sha = '20f48bfe162d8d886b9f5fea7ad6d7df91eb3266'
$clang = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\Llvm\x64\bin'
$wrapper = '.\tools\evox2\automation\Invoke-CodexBuild.ps1'
$v = @{ Backend = 'Vulkan'; BuildDir = 'build-vk'; Worktree = $true; SourceCommit = $sha
        Offline = $true; VulkanLlvmBin = $clang; ExpectedVulkanClangVersion = '22.1.3'; CpuAllVariants = 'OFF' }
$r = @{ Backend = 'ROCm'; BuildDir = 'build-rm'; Worktree = $true; SourceCommit = $sha; Offline = $true }
& $wrapper @v -PreflightOnly
& $wrapper @r -PreflightOnly
& $wrapper @v
# Verify host and Vulkan artifacts before the separate ROCm invocation.
& $wrapper @r
```

[Verify-W54Build.ps1](build-validation-20261126/Verify-W54Build.ps1) は実ビルドの生成物と記録を読み、PE・ハッシュ・設定・進捗を照合する。[Verify-W54Measure.ps1](build-validation-20261126/Verify-W54Measure.ps1) は旧・新の依存検証と非推論 DryRun／PlanOnly を再現する。実機の保存先を再利用するときは既存ログを上書きしない出力先を指定する。

採用時は main と現行製品に指定パスだけを反映し、標準ビルド・計測ツールと新依存モジュールの blob 一致を確認した。ツールコミットは main `18927c95997d4d8463dc37b6a8bb5b22465d6cd9`、現行製品 `04ac2e4b7973140cb912c12c18a8654c68411786`。ADLX ビルドスクリプトは先頭3バイトの BOM 差だけを揃えた。 main の旧依存構成は両バックエンドのキャッシュ検証が通過した。実験ブランチは採用元の SHA とパスを照合して取り込む。将来の ROCm 複数版対応と、DLL 実ロード元の継続観測は保留。 [RUNBOOK](RUNBOOK.md)
