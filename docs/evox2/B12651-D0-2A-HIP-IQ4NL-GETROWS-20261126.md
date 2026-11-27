# b12651 D0-2A — ROCm Release と限定数値検証の準備

## ビルドの来歴

| 項目 | 値 |
| --- | --- |
| 文書・標準ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216` |
| 製品基準 | `9ae819d5be4fe9861d2aa8547983aed801c437ac` |
| 実験ブランチ / ビルド元 | `experiment/hip-iq4nl-ple160` / `044be892e12bffdfd06cfb698bf55e54582ae63a` |
| 実機 / 出力 | `C:\llama-build\automation\w55` / `w55\build-rm\bin\Release` |

ビルド前の登録 worktree はクリーンで、HEAD、追跡先、GitHub の実験ブランチはいずれも対象 SHA と一致した。使用した `tools/evox2/{automation,build,lib}` と RAM・GPU 監視モジュールの blob は固定 main と一致した。使用したオプションは `-Backend ROCm -BuildDir build-rm -Worktree -SourceCommit 044be892e12bffdfd06cfb698bf55e54582ae63a -Offline`。最初の `-PreflightOnly` は終了0、4.247秒で、出力ディレクトリは作成されなかった。通常モードは同じ引数から `-PreflightOnly` を外して1回実行した。 [標準の登録 worktree 手順](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/BUILD-VALIDATION-20261126.md)

| 照合項目 | 結果 |
| --- | --- |
| ROCm Release | 終了0、`Succeeded`、ラッパー全体442.564秒。Ninja Multi-Config、Release、並列4 |
| ビルド番号 / 来歴 | `1.0.0-dev b12696`、埋め込み `044be892e`、`BuildIdentity=Verified`。ビルド番号は旧標準と同じため、SHAで区別する |
| 実 CMake 設定 | `GGML_HIP=ON`、`AMDGPU_TARGETS=gfx1151`、Ninja の `--offload-arch=gfx1151`、`GGML_BACKEND_DL=ON`、`LLAMA_BUILD_TESTS=ON`、UIとprebuilt UIはOFF、FetchContentは完全切断 |
| コンパイラ・ツール | TheRock 10.0.0、AMD Clang 23.0.0git（LLVM `8f497e0992fb7513f7f78a6f6b6f1056c375e961`）、VS2022 x64 MSVC 14.44.35207、CMake 3.31.6-msvc6、Ninja 1.12.1 |
| `test-backend-ops.exe` | 2,490,368 byte、SHA-256 `24ef370e740df616c2e64dd7114811a037e7089a9a7dd34f7dc9299b0762a5ac`。マニフェストの `Artifacts` と一致 |
| `llama-cli.exe` | SHA-256 `98da309636095a3be2d28b26fb19194968607b54b9cc042565875774a9dda6bf`。`--version` と `--list-devices` は終了0 |
| `evox2-build.json` | SHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`。`RuntimeDependenciesV1` の CLI 照合は `Verified` |
| デバイス | `ROCm0: AMD Radeon(TM) 8060S Graphics`。gfx1151 は実機の既知構成、CMake/Ninja、両データツリーの対象で照合。補足 CLI 列挙も終了0で機種は一致したが、CLI の出力にアーキテクチャ文字列はなく、この補足チェックでの文字列照合は未成立 |

外側ラッパーは `ConfigureOnly`、実キャッシュ検査、`BuildOnly`、CLIスモークとマニフェスト検証を完了した。最終マニフェストの `Configure.Executed=False` は `BuildOnly` の記録で、先行した `ConfigureOnly` は stdout、実キャッシュ、ラッパーの終了結果で確認した。

TheRock の `C:\TheRock\build\.venv\Lib\site-packages\_rocm_sdk_devel\bin` から、`amdhip64_7.dll`、`rocm_kpack.dll`、`amd_comgr.dll`、`hipblas.dll`、`rocblas.dll`、`rocsolver.dll`、`libhipblaslt.dll`、`origami.dll` を配置し、8本のコピー元・先とマニフェストの SHA-256 を照合した。rocBLAS（150ファイル、`3a6de928ed5ec7c2c7eac5cd98d1fa5e872c20643a81488bdfc755f9a94e11b3`）と hipBLASLt（100ファイル、`0a9dd8a70063551cbc7e358599165fd8c007af8e458e4554ea858ae8ff5a759d`）のデータツリー digest と `library\gfx1151` を確認した。

コンパイルエラーは0件。既知の CMake Git index、`AMDGPU_TARGETS` 非推奨、`CMAKE_HIP_COMPILER` 未使用等の警告があった。標準 `w54` ROCm ログと比較し、差として抽出された `-Wignored-attributes` 1件は、同じ `GGML_BACKEND_DL_IMPL` の警告（`ggml-cuda.cu:7119` から `7142` へ行番号移動）と確認した。新規警告は確認されなかった。Ninja は最終479/479でテストEXEをリンクした。状態には86サンプル、コンパイラ観測514件があり、個別観測の最大CPU時間43.77秒、Working Set 266.79 MiB。

標準ラッパーのログは `C:\llama-build\_logs\codex` に保存した。各実行の `.stdout.log`、`.stderr.log`、`.result.json`、`.state.json`、`.worker.json`、`.progress.jsonl` は同じ stem で照合する。

| 用途 | 参照 |
| --- | --- |
| Preflight | `build-ROCm-Preflight-3d1966e4840144fb86e411123b11a5d4` |
| Release | `build-ROCm-Build-43b0c6b6382e4800a7ab88de7c372d07` |
| 前後の状態・追加照合 | `d0-2a-289c343e02ff47579d0e8b453107e5dd` |

## 実機と監視経路の確認

Windows 11 26300.10075、Radeon 8060S、UMA 96 GiB、Adrenalin 26.11.2（32.0.32029.2010）、PowerShell 5.1.26100.10068。承認済みの `Get-Evox2PModeMetadata`（ScheduledTask、Method ID 2）で 23:28:14 と 23:36:01 JST の新規サンプルがともに Performance。前後の競合・残留プロセスは0件だった。

| 読み取り | ビルド前 → ビルド後 |
| --- | --- |
| 物理空き / commit / commit limit | 27.000 → 26.819 GiB / 8.029 → 8.162 GiB / 127.647 → 127.647 GiB |
| WDDM Dedicated / Shared | 0.461 → 0.461 GiB / 0.067 → 0.067 GiB。有効サンプル各3件 |
| GPU Engine 利用率 | 有効サンプル各269件。全エンジンの測定値の合計は0.0104% → 0% |
| OS起動 / System | Kernel-General 12 の起動時刻は `2026-11-26T11:45:51.500Z` で一致。RecordID 69911 → 69911、新規0件 |
| Application | 44066 → 44068。新規2件は Security-SPP の情報レベル（16394、16384）、重大イベント0件 |

両イベントチャネルで通常の最新レコード読み取りと、XPath の該当0件が `NoMatchingEventsFound` になることを確認した。実測のイベント差分も読み取れた。開始・終了の資源条件は既存閾値内。観測値は `before.json`、`after.json`、`event-delta.json`、バイナリ照合は `artifacts.json` に保全した。D0-2Bの開始前に同じ項目を再取得する。

## D0-2B 実行手順（個別承認後）

D0-1のケース、CPU参照比較、計画を維持する。以下の対象コマンドは D0-2A では未実行。運用者が単一の実行を監督する手順を、Markdown に記録した。 [D0-1のレビュー資料](B12651-D0-1-HIP-IQ4NL-GETROWS-20261126.md)

```powershell
& 'C:\llama-build\automation\w55\build-rm\bin\Release\test-backend-ops.exe' test -b ROCm0 -j 1 -o GET_ROWS -p '^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$'
```

### 開始条件とログ

1. Windows PowerShell 5.1 の承認済みプロセス設定を使う。作業ツリーがクリーンで、ビルド元 SHA からの後続差分がこの実行記録に限られることを確認する。EXE のサイズと SHA-256、`evox2-build.json` の SHA-256・`Source.Commit`・`BuildIdentity.Status`・`Artifacts`、検証済みデバイスと同梱ランタイムを照合する。実行は承認済みの絶対パスと引数を1回だけ使用する。`GGML_BACKEND_PATH` と GPU デバイス可視性の環境変数は承認済みビルド時の列挙条件と照合する。設定変更で差異を解消せず、差異があれば保留する。
2. `C:\llama-build\_logs\codex` に GUID 付き実行ディレクトリを1個作り、ビルドSHA、ハッシュ、固定引数、前後・実行中の時刻、PIDと開始時刻、終了コード、stdout/stderr、イベントを保存する。起動直前に再計測し、競合するビルド・推論・バックエンドテスト・GPU監視プロセスと Task Manager の不在、Performance、物理空き16 GiB以上、GPU状態と EventRecordID の取得を確認する。取得エラーがあれば開始しない。
3. RAM・commit・commit limit は固定 main の `tools/evox2/benchmark/Evox2.Memory.psm1` の `Get-Evox2SystemMemory` で記録する。P-MODE は `tools/evox2/lib/Evox2.Common.psm1` の `Get-Evox2PModeMetadata` の新規結果を使う。GPU は `Get-Counter` で `\GPU Adapter Memory(*)\Dedicated Usage`、`\GPU Adapter Memory(*)\Shared Usage`、`\GPU Engine(*)\Utilization Percentage` を取得し、インスタンス・時刻・有効サンプルを保全する。以下の前後監査で使う System／Application の最新 EventRecordID と Kernel-General 12 の `StartTime` を控える。

### 起動、60秒の上限、プロセス監視

監督付き起動では、上記コマンドと同じ引数を、次の単一文字列として `Start-Process -ArgumentList` に渡す。起動は同じ PowerShell セッションから `-PassThru -WorkingDirectory (Split-Path -Parent $exe) -RedirectStandardOutput <一意のstdout> -RedirectStandardError <一意のstderr>` を付けて1回だけ行う。

```powershell
$exe = 'C:\llama-build\automation\w55\build-rm\bin\Release\test-backend-ops.exe'
$nativeArgs = 'test -b ROCm0 -j 1 -o GET_ROWS -p "^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$"'
```

PowerShell 側の単一引用符で `$` やパイプをそのまま保持し、内部の二重引用符は Windows の引数境界として残る。正規表現全体が `-p` の直後の1引数になり、EXE のパーサーに引用符自体は渡らない。PowerShell 5.1 のパーサーと、C++ の引数・ケース名・出力形式を静的に確認した。起動に `cmd.exe` や `Invoke-Expression` は介在しない。C++ 側は `test`、`-b ROCm0`、`-j 1`、`-o GET_ROWS`、`-p <式>` を順に消費する。

- 起動時の Stopwatch と、返された `Process.Id`／`Process.StartTime.ToUniversalTime()` をログに記録する。主監督の待機は `WaitForExit` の有限時間版を使い、1回の待機は `min(2000 ms, 残り時間)` とする。RAM・commit・WDDM の取得は別の監視セッションで行い、カウンター読み取りの遅延を終了の待機と分離する。実行中は2秒間隔を目安に、RAM・commit・GPU、取得できる対象PIDの Working Set・Private Bytes、ログ進捗を保存する。テストが最初の採取前に終了した場合は短時間終了として記録し、前後の両観測を要求する。
- 60秒到達、応答停止、GPUエラー、新規重大イベントなどの異常を検知したら、健全なOS上で PID・開始時刻・実行ファイルを照合した当該子だけを停止する。終了後の同名残留を確認する。他のPIDは操作しない。SSH切断やOS応答停止では以降の起動を保留し、運用者が保存済みログと実機状態を照合する。ホスト自体が応答しない場合、プロセス停止の成否は未確認とする。
- 終了後に物理空き16 GiB以上、開始比で commit と WDDM Dedicated の増分がそれぞれ4 GiB以内、P-MODE Performance、対象および監視プロセスの終了を確認する。基準は開始時の値を使う。欠損を0として扱わない。閾値逸脱・状態不明・回復不良では実行ログとサンプルを保全し、運用者へ報告する。再試行は運用者の判断を待つ。 [既存の停止・回復基準](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/RUNBOOK.md#無人計測の-run-単位の停止手順)

### イベント監査と合否

両チャネルで `Get-WinEvent -LogName <channel> -MaxEvents 1` を前後に実行する。起動時刻とカーソルの連続性を確認し、`-FilterXPath '*[System[EventRecordID > <before-id> and EventRecordID <= <after-id>]]'` で新規イベントを抽出する。Windows PowerShell 5.1 では `NoMatchingEventsFound` のみをゼロ件として扱い、アクセス拒否、巻き戻り、読み取りエラーは監査失敗とする。Display/GPU、WHEA、BugCheck、Kernel-Power、リソース枯渇、Application Error/Hang、WER を照合し、過去のWERは実際の障害発生時刻を確認する。新規重大イベント、SSH切断、タイムアウト時は採取済みの証拠を保全する。

既定の console 出力から ANSI SGR を除いて、次の識別子について各行がちょうど1回 `GET_ROWS(<識別子>): OK` と出力されることを照合する。CPU参照は既存の backend-op 比較、既定の NMSE `1e-7` と NaN/Inf 検査を使用する。

| 幅・配置 | 期待する識別子 |
| --- | --- |
| 32・連続 | `type=iq4_nl,d0_1_width=32,padded=0` |
| 160・連続 | `type=iq4_nl,d0_1_width=160,padded=0` |
| 160・padded/batched | `type=iq4_nl,d0_1_width=160,padded=1` |
| 256・連続 | `type=iq4_nl,d0_1_width=256,padded=0` |
| 288・連続 | `type=iq4_nl,d0_1_width=288,padded=0` |

終了0・上の個別OK全5件・`5/5 tests passed`・ROCm0の成功・監視と監査の通過をすべて要求する。対象外演算・ケース、非対応、ケースのスキップ、重複、欠落、GPUエラーの出力があれば失敗。別デバイスの列挙時の `Skipping` は `-b ROCm0` の分岐で、ケースのスキップとログ上で区別する。ハーネスは部分的な非対応を件数から除外するため、終了0単独では合格にしない。正規表現と演算フィルターは D0-1 の静的確認どおりで、`run_fa_vec_slice` は `-o GET_ROWS` で早期復帰する。

## 未確認事項

D0-2A の確認範囲は、ビルド、CLIのバージョン・デバイス列挙、ファイルとマニフェストの照合、監視経路の読み取り。GPU 数値、GPU 高負荷時の回復、実モデル配置と新経路の4スレッド workgroup の性能は D0-2A の結果から判断できない。実行時の読み取り、タイムアウトと停止、5件の合否判定は D0-2B で個別に承認する。Adrenalin 26.11.2 更新後も既知の backend-op 障害の解消は未確認。 [既知の問題の2026-11-26追記](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/KNOWN-ISSUES.md#2026-11-26-adrenalin-更新後の-backend-op-数値テストの扱いソース再確認)
