# B12651 D0-4D-2A — host配置制限修正版のROCm Releaseビルド

**ビルドと限定検証の実行準備は完了。** 2026-11-27 JST。標準のCLIバージョン・デバイス列挙・マニフェスト照合を実施した。

## 来歴と成果物

- ビルド時の `experiment/hip-iq4nl-ple160` は `e199e5f4319731071199d84f4f2e571fcaa7d413`。GitHub、登録worktree `C:\llama-build\automation\w55`、追跡先が一致し、開始時の作業ツリーはクリーン。修正・テストの固定コミット `86e343cd4bfa0110f49e430d59081725af976e01` からの差分はD0-4D-1文書のみ。
- 標準の `tools/evox2/{automation,build,lib}` は固定main `891e2605fbc0798228ffad2a69dd618f6cdab216` と照合。旧 `build-rm` のCLI／test EXE／HIP DLL／マニフェストのSHA-256は前後で一致。新規出力は `w55\build-rh\bin\Release`。
- 完全SHAを指定し、`PreflightOnly` は4.182秒・終了0で出力先未作成を確認。通常モードは同じ引数で `-PreflightOnly` を外して1回実行。ラッパー全体は **443.702秒**、終了0・`Succeeded`。Ninja最終479/479でテストEXEをリンクした。

```powershell
Set-Location 'C:\llama-build\automation\w55'
$cfg = @{ Backend='ROCm'; BuildDir='build-rh'; Worktree=$true; SourceCommit='e199e5f4319731071199d84f4f2e571fcaa7d413'; Offline=$true }
.\tools\evox2\automation\Invoke-CodexBuild.ps1 @cfg -PreflightOnly
.\tools\evox2\automation\Invoke-CodexBuild.ps1 @cfg
```

| 成果物 | SHA-256 |
| --- | --- |
| `llama-cli.exe` | `538a12f93ed12ab2a639640d87aeb78582acca4d9d9c086fe5d6f9220f7c01de` |
| `test-backend-ops.exe`（2,500,096 byte） | `993c6f4b16c52d82d246f48c4e67eb5c751d703379ccdd39c8f34cc512e003f3` |
| `ggml-hip.dll` | `2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f` |
| `evox2-build.json` | `8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116` |

CLIは `1.0.0-dev b12709`、埋め込み `e199e5f43`。 `BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。標準の `--version` と `--list-devices` は終了0、ROCm0はAMD Radeon 8060S。Ninjaの `--offload-arch=gfx1151`、CMakeターゲット、両ランタイムデータツリーでgfx1151を確認した。 `BackendTestRequested=False`。

D0-2Aと同じTheRock 10.0.0、AMD Clang 23.0.0git（LLVM `8f497e0992fb7513f7f78a6f6b6f1056c375e961`）、VS2022 MSVC 14.44.35207、CMake 3.31.6-msvc6、Ninja 1.12.1。Ninja Multi-Config Release・並列4。対象キャッシュ項目はD0-2Aと差分なし。HIP、HIP graphs、HIP no VMM、バックエンド動的ロード、C++テストと完全切断FetchContentはON、UIとprebuilt UIはOFF。TheRockの8 DLLのコピー元・先のSHA-256、rocBLAS（150ファイル）とhipBLASLt（100ファイル）のデータツリーdigestを照合し、旧D0-2Aと同じ配布元・データを確認。

ログ上にCMake Git index、AMDGPU_TARGETS、コンパイラの既知警告があった。D0-2Aのログに対して出力先と行番号を正規化した比較で新規警告は抽出されず、コンパイルエラーも抽出されなかった。 [D0-2Aのビルド条件](B12651-D0-2A-HIP-IQ4NL-GETROWS-20261126.md)

## 開始・終了監査

| 指標 | ビルド前 → 後 |
| --- | --- |
| 空き物理RAM | 27.424 → 27.083 GiB |
| 現在commit／limit | 8.047 → 8.365 GiB（上限127.647 GiB） |
| WDDM Dedicated／Shared | 0.461／0.035 → 0.461／0.035 GiB |
| P-MODE | Performance → Performance |
| OS起動 | `2026-11-26T11:45:51.5000000Z`で一致 |
| System／Application | 69925 → 69925／44246 → 44246。ビルド中の差分0件 |
| 残留 | ビルド・推論・監視の残留なし |

前回Original終了後から今回開始までの追加重大イベントは観測しなかった。OS起動以降のcommit高水位127.613 GiBは前回の失敗履歴で、現在commitとは別。OriginalのGPU詳細回復 `Unobserved` は維持した。

生ログは `C:\llama-build\_logs\codex` 配下。

- Preflight stem `build-ROCm-Preflight-e4a5f7bfdd3647f38553813a10879cb3`。
- Build stem `build-ROCm-Build-314c3d42084e47bd8a0c022426d9664a`。stdout、stderr、result、state、worker、progressを保存。
- `d0-4d-2a-audit-20261127` に前後資源、イベント差分、旧成果物照合、`artifacts.json`、ダミー引数の記録。

## 限定検証の実行準備

既存の `D0GetRows.Supervisor.psm1` をそのまま使用し、実験専用 `Invoke-D0GetRows.ps1` を新ビルドと3つの固定 `-Case` に対応させた。ケース計画とstdout/stderrの判定は `D0GetRows.Cases.psm1`。選択肢に任意の実行ファイル、演算、フィルター、引数を追加できるパラメーターは設けていない。ランチャーは修正版ビルドのテストEXEの絶対パス・長さ・SHA-256、CLI・HIP DLL・マニフェストのSHA-256と依存を照合する。既定の起動前確認は `-RunApproved` を付けずに行える。

次工程の個別承認後、承認された1ケースずつ `-ExpectedHead <レビュー済みHEADの完全SHA> -Case <ケース> -RunApproved` で起動する。1回の呼び出しで実行するテストは1プロセス。 `$testExe` が表す固定EXEは `C:\llama-build\automation\w55\build-rh\bin\Release\test-backend-ops.exe`。以下はランチャー内部で選ばれるコマンドに対応する。

```powershell
& $testExe support -b ROCm0 -o GET_ROWS -p '^type=iq4_nl,d0_4d_width=(160,buffer=(device,padded=0|host,padded=[01])|256,buffer=(device|host),padded=0)$'
& $testExe support -b CPU -o GET_ROWS -p '^type=iq4_nl,d0_4d_width=160,buffer=cpu,padded=0$'
& $testExe test -b ROCm0 -j 1 -o GET_ROWS -p '^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$'
```

| ケース | 必須結果 |
| --- | --- |
| `RocmSupport` | 5行。160 device、256 device、256 hostの3件が `SUPPORTED`。160 hostの連続・paddedの2件が `NOT SUPPORTED`。 `Backend ROCm0: OK` |
| `CpuSupport` | 1行。160 CPUが `SUPPORTED`。 `Backend CPU: OK` |
| `RocmNumerical` | 5行。32、160連続、160 padded、256、288が各 `OK`。 `5/5 tests passed`、 `Backend ROCm0: OK` |

行数と内容を照合し、重複・欠落・予定外の演算行・バックエンド結果を失敗扱いにする。監視中に許容する `NOT SUPPORTED` はROCm0 supportの期待2行だけ。CPU supportも既存テストEXEのデバイス列挙経路は通る。supportケースはサイズ0のダミーバッファで判定し、グラフを実行しない。CPUのみというフィルターはGPU初期化を完全に抑止する保証にはならない。 [期待値とテスト実装](B12651-D0-4D-1-HIP-IQ4NL-GETROWS-HOST-PLACEMENT-20261127.md)

D0-2Cと同じ60秒上限、PID・開始時刻・パスによる監督、ネイティブ終了コードと開始・終了時刻の保存、監視中止と残留確認を維持した。起動前後のPerformance、RAM 16 GiB以上、終了時commitとDedicatedの増分各4 GiB以内、OS起動時刻、イベント差分を監査する。実行中の閾値もD0-2Cと同一。短時間で完全な実行中サンプルが取れない場合は理由を記録する。GPUエラー、異常イベント、欠損、タイムアウト時は保存済みログを保持して停止する。自動再試行はしない。 [D0-2C監督処理](B12651-D0-2C-HIP-IQ4NL-GETROWS-20261127.md) · [D0-2B再検証](B12651-D0-2B-RETEST-HIP-IQ4NL-GETROWS-20261127.md)

### CPUダミー確認

- 出力判定14件合格。3種類の正常例と、想定外の肯定・否定、重複、欠落、対象外演算、誤バックエンド、誤集計、誤ランタイム、ROCmエラー、監視中の期待否定と想定外否定を確認した。出力は合成データ。
- 既存D0-2CのCPUダミー5件が合格。即時終了0／7、遅延終了0、2秒のTimeout、意図的なMonitorErrorで終了コード・時刻・stdout/stderrを回収した。Timeout時の監督経過は約2.046秒。対象と監視の残留なし。ダミー記録は `d0-2c-dummy-3125e51afc364048bcd3c5750104c57e`。
- 同じ `Start-Process` の経路で、PowerShellのダミー子に固定引数を渡した。引数数はROCm0 support／CPU support／ROCm0 numericalの順で7／7／9。各正規表現は末尾の単一引数として原文と一致した。記録は監査ディレクトリの `dummy-tools\argv-results.json`。

テストEXEのhelp・support・test、モデルロード、推論、GPU数値検証は未実施。修正版でのOriginal・PLE16の実際の配置と挙動は次の個別承認で確認する。今回はビルドと実行準備で停止した。
