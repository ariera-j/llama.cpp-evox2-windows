# b12651 D0-2B — ROCm IQ4_NL GET_ROWS の限定検証結果

**総合判定は合格未成立。** 承認されたGPU数値比較5件は各1回 `OK`、集計は `5/5 tests passed`、ROCm0は `OK`。PowerShellの監督処理で null に対するメソッド呼び出し例外が発生し、子EXEの終了コードと正確な実行時間を記録できなかった。監督側の終了コードは1。テスト回数は1回。数値比較結果と監査ログを保全した。

## 来歴と開始条件

| 項目 | 結果 |
| --- | --- |
| 実施日時 | 2026-11-26 23:49 JST。子の開始記録は23:49:50.7920427 JST |
| 文書と共通ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216` |
| ブランチと開始時HEAD | `experiment/hip-iq4nl-ple160`、`264c513eb2c7daee8a90fef468dfbbca99d43069`。GitHub・追跡先と一致、`w55` はクリーン |
| ビルド元 | `044be892e12bffdfd06cfb698bf55e54582ae63a`、b12696、`BuildIdentity=Verified`。以降の差分はD0-2Aの記録のみ |
| テストEXE | `C:\llama-build\automation\w55\build-rm\bin\Release\test-backend-ops.exe`、2,490,368 byte、SHA-256 `24ef370e740df616c2e64dd7114811a037e7089a9a7dd34f7dc9299b0762a5ac` |
| マニフェスト | SHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`、`RuntimeDependenciesV1` は `Verified` |
| HIPバックエンド | `ggml-hip.dll` のSHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c`。生成物・同梱DLL 8本・gfx1151データツリーをマニフェストと照合 |
| ホスト | Windows 11 26300.10075、Adrenalin 26.11.2（32.0.32029.2010）、TheRock 10.0.0、UMA 96 GiB、PowerShell 5.1.26100.10068 |
| 選択デバイス | 起動前のCLI列挙は `ROCm0: AMD Radeon(TM) 8060S Graphics`。テストstderrで Device 0、gfx1151、Wave Size 32、およびロードされたHIP DLLの実パスを確認 |

バックエンド探索パスとGPU可視性の上書きなし。競合プロセス・Task Manager・対象テストプロセスの不在を確認した。開始時の物理空きは26.690 GiBで16 GiBの閾値を通過し、P-MODEは新規測定でPerformance。両イベントチャネルを読めることと、差分クエリの該当0件を識別できることを確認して起動した。 [D0-2Aの手順](B12651-D0-2A-HIP-IQ4NL-GETROWS-20261126.md)

## 実際の起動

PowerShellの `Start-Process` から以下のパスと単一引数文字列を渡し、標準出力と標準エラーを別ファイルにリダイレクトした。ログディレクトリは下記の生ログ保全先。テストのPIDは16152、照合用開始時刻は `2026-11-26T14:49:50.7920427Z`。

```powershell
$exe = 'C:\llama-build\automation\w55\build-rm\bin\Release\test-backend-ops.exe'
$nativeArgs = 'test -b ROCm0 -j 1 -o GET_ROWS -p "^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$"'
$proc = Start-Process -FilePath $exe -ArgumentList $nativeArgs -WorkingDirectory (Split-Path -Parent $exe) -RedirectStandardOutput (Join-Path $log 'stdout.log') -RedirectStandardError (Join-Path $log 'stderr.log') -PassThru
```

| IQ4_NL GET_ROWS | 個別結果 |
| --- | --- |
| 幅32、padded=0 | OK、1件 |
| 幅160、padded=0 | OK、1件 |
| 幅160、padded=1 | OK、1件 |
| 幅256、padded=0 | OK、1件 |
| 幅288、padded=0 | OK、1件 |

ANSI装飾を除いて全ケース行を照合した。対象外、非対応、ケースのスキップ、重複、欠落は0件。CPUデバイス名の後の `Skipping` は独立テスト対象からの除外表示。CPU参照比較を行う既存ハーネスの結果は全件OKで、NaN、Inf、数値比較エラー、GPUエラーはログに出なかった。個別のNMSE実測値は出力されなかった。 [テスト設計と既存比較条件](B12651-D0-1-HIP-IQ4NL-GETROWS-20261126.md)

監督には60秒の上限を設定した。タイムアウトによる強制停止は発生しなかった。最後のstdout更新は23:49:51.0917913 JST（記録された開始の0.300秒後）。23:49:57.9615854 JSTの終了後確認で対象は不在で、開始から約7.17秒後までに消失を確認した。stdout更新時刻と不在確認時刻はプロセスの正確な終了時刻として扱わない。監督処理の例外で `status.json` の `ExitCode`、`ElapsedSeconds`、`ExitUtc` は欠損。最後の成功表示をOS終了コード0の代用にしない。

## 監視・回復・イベント

| 読み取り | 開始前 | 初回監視サンプル | 終了後 |
| --- | ---: | ---: | ---: |
| 物理空き（GiB） | 26.690 | 26.663 | 26.721 |
| commit（GiB） | 8.311 | 8.324 | 8.252 |
| commit limit（GiB） | 127.647 | 127.647 | 127.647 |
| WDDM Dedicated / Shared（GiB） | 0.459 / 0.072 | 0.459 / 0.072 | 0.459 / 0.072 |
| GPU Engine利用率の合計、有効件数 | 0%、269件 | 0%、269件 | 0%、269件 |
| P-MODE | Performance（23:49:47新規取得） | — | Performance（23:49:54新規取得） |

監視セッションの初回採取では、子のWorking Set 44.973 MiB、Private Bytes 27.781 MiBを記録した。WDDMの初回採取は23:49:52以降で、最後のstdout更新後だった。子のGPU演算区間と重なるGPU利用率のサンプルは確認できず、0%を負荷中の利用率として解釈しない。終了後の物理空きは16 GiB以上で、commitは開始時より約0.059 GiB減、Dedicatedの増分は0。回復閾値を満たした。

Kernel-General 12のOS起動時刻 `2026-11-26T11:45:51.500Z` とRecordID 69721は前後一致。Systemは69911→69911、Applicationは44068→44068で、差分監査は両チャネルとも成功、新規イベントは0件。監督側の即時確認は `MonitorEnded=false` を記録した。23:50:29 JSTの個別確認では、監視PID 2952、テストPID 16152、関連プロセスすべてが不在だった。

生ログは `C:\llama-build\_logs\codex\d0-2b-fc3c52d1ea2e4459aa1dfea56fc7b606` に保持。 `stdout.log`、`stderr.log`、`provenance.json`、`child.json`、`status.json`、`before.json`、`during.jsonl`、`after.json`、`event-delta.json`、`residual-check.json` と監督コードの控え `supervisor-source.txt` を保全した。

## 結論と未検証範囲

固定した5件でCPU参照との比較はOK。終了処理の記録不備によりD0-2Bの合格条件は成立しなかった。GPU演算区間の利用率、長時間負荷時の回復、実モデルのPLE配置、RAM・転送量への効果、4スレッドworkgroupの性能、既知の別演算障害は未検証。再試行、ソース修正、再ビルド、モデルロード・推論、性能計測は実施していない。
