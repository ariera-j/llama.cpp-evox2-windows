# b12651 D0-2C — 限定検証の監督処理

D0-2Bの初回記録は総合合格未成立のまま保持した。D0-2Cでは実験専用の監督処理を修正し、Windows PowerShell 5.1上でCPUダミー5件を検証した。製品ソース、C++テスト、共通ツール、ビルド成果物に変更はない。 [D0-2Bの初回記録](B12651-D0-2B-HIP-IQ4NL-GETROWS-20261126.md)

## 例外の調査

運用文書は main `891e2605fbc0798228ffad2a69dd618f6cdab216`、調査開始時の実験ブランチは `e03063d3e2dfa93e0329544a89c3eff55a194401`、ビルド元は `044be892e12bffdfd06cfb698bf55e54582ae63a`。初回の `supervisor-source.txt`（SHA-256 `68584dab567bc78c6a7528b8c8c536d6bac4cba444a6238383737627cf69ec59`）、`status.json`、`child.json`、両出力ログ、`during.jsonl`、`residual-check.json`、監督の終了記録を読んだ。生ログのパスは初回記録に記載した。

- 200行目は出力リダイレクト付き `Start-Process -PassThru`。主監督は同一の `$proc` を使い続け、202行目の開始時刻取得と207行目までの `child.json` 作成を完了した。主監督の `$proc` を監視ジョブが更新する経路はない。ジョブの `$p` は別セッションで取得する観測用オブジェクト。
- 214行目は `$proc.HasExited`。215行目で `$proc.ExitCode` が `$null` となり、216行目の **`$proc.ExitTime.ToUniversalTime()`** で `$null` に対するメソッド呼び出しが発生したと記録とコードから特定した。終了捕捉区間に到達した根拠は `child.json`、欠損した終了フィールド、例外文字列。初回のcatchは `$_.ToString()` のみを保存したため、初回ログ自体には例外の行番号とスタックがない。発生箇所は下記の同型再現でも照合した。
- 実機 PowerShell 5.1.26100.10068 で、リダイレクト付き `Start-Process -PassThru` により `cmd.exe /d /c exit 7` を起動し、元と同じ開始時刻、`HasExited`、`WaitForExit`、終了情報の順序を再現した。ハンドルを保持しない試行では `HasExited=True` でも通常のプロパティ参照が `ExitCode=null`、`ExitTime=null` を返し、`ToUniversalTime()` は `InvokeMethodOnNull` となった。リフレクションで `.NET Process.get_ExitCode()` の内部例外を確認すると、`InvalidOperationException`（「プロセスはこのオブジェクトによって開始されていないため、要求された情報を決定できません」）だった。同じ起動で待機前に `$proc.Handle` を開いて保持した試行はコード7と終了時刻を返した。したがって、確認できた欠損の条件は終了情報を読めるハンドルを保持していないこと。短時間終了はこの経路を再現した条件であり、短時間であることだけで失敗するという結論にはしていない。
- 初回の終了情報は監視ジョブ停止前から欠損している。ジョブの残留を示した即時フラグと、直後のPID照合で残留がないことは初回どおり。stdoutの最終更新と後続の不在観測は実行時間の参考範囲に限られる。保存ログからOS終了コードと正確な終了時刻は復元できない。5件のOK表示は数値結果として扱う。

## 修正

実験スクリプトは `tools/evox2/experiments/iq4nl-getrows`。PowerShell 5.1とUTF-8 BOMを使用する。

| ファイル | 役割 |
| --- | --- |
| `D0GetRows.Supervisor.psm1` | `ProcessStartInfo` と `Process.Start` でネイティブの子を起動し、生成ハンドルを持つ同一の `Process` を終了捕捉まで保持。stdout/stderrを別々に非同期で保存し、待機前から監視側で読めるようにする。 |
| `Invoke-D0GetRows.ps1` | 固定成果物・実機の開始条件、別セッション監視、回復・イベント監査、5件の出力と合格条件を検査する実験専用の入口。 |
| `Test-D0GetRowsSupervisor.ps1` | CPUだけの固定ダミー5件で、監督の起動・待機・終了、両ログ、停止と残留を検証する。 |

主監督の有限時間 `WaitForExit` と Stopwatch は別セッションの監視周期から独立させた。停止時の再検索はPID・開始時刻・実行パス照合にだけ使い、終了コードと終了時刻は起動に使ったオブジェクトから取得する。終了情報と両ログの保存結果を監視ジョブの終了待ちより先に記録し、個々の取得失敗はnullとエラー情報として残す。子のOS開始／終了時刻からの時間と、生成要求から監督が終了を観測するまでのStopwatch経過を区別する。モニターは停止信号を受け、待機後に元の監視PIDが消失したか照合する。

## GPUを使用しない検証

実機の `C:\llama-build\_logs\codex\d0-2c-dummy-451564a1dda84a5f9fcccccb3c3fb5b4` に `dummy-summary.json`、ケースごとの `status.json` とstdout/stderrを保存した。早期2件は `cmd.exe` の組み込み処理、他3件はPowerShellのスリープのみ。強制停止対象はこの実行が起動したダミーのみ。

| ケース | 期待値 | 終了コード | 子実行時間 / 監督時間（ms） | 結果 |
| --- | --- | ---: | ---: | --- |
| 即時正常 | 0、自然終了 | 0 | 19.714 / 29.076 | OK |
| 即時非ゼロ | 7、自然終了 | 7 | 21.725 / 23.076 | OK |
| 約3秒で正常 | 0、3秒以上 | 0 | 3175.930 / 3183.423 | OK |
| 2秒テスト用上限 | Timeout、停止後の非ゼロコード | −1 | 2029.222 / 2036.792 | OK |
| 監視で意図的例外 | MonitorError、停止、例外と両ログを保持 | −1 | 215.596 / 221.888 | OK |

すべてで開始・終了時刻、終了コード、両ストリームのマーカーを取得した。即時終了ケースは監視サンプルを持たなくても正常に完了または非ゼロ終了と分類できた。監視例外は子が動作中にstderrを読み取ってから発生させた。全ケースで子と監視の残留なし。強制停止のコード −1 は今回のWindowsの観測値で、将来の固定仕様とは扱わない。

## 次の限定GPU検証（個別承認後）

`w55` のレビュー済み完全SHAとGitHub・追跡先を照合し、Windows PowerShell 5.1で以下を運用者が1回だけ実行する。実行前の照合だけを行う場合は `-RunApproved` を付けない。こちらは成果物・監視経路を確認し、テストEXEやCLIを起動しない。

```powershell
Set-Location 'C:\llama-build\automation\w55'
& '.\tools\evox2\experiments\iq4nl-getrows\Invoke-D0GetRows.ps1' -ExpectedHead '<レビュー済みコミットの完全SHA>' -RunApproved
```

子は既存EXE（SHA-256 `24ef370e740df616c2e64dd7114811a037e7089a9a7dd34f7dc9299b0762a5ac`）で、実引数は `test -b ROCm0 -j 1 -o GET_ROWS -p "^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$"`。60秒上限、個別5件のOK、`5/5`、ROCm0成功、ネイティブ終了0、資源回復とイベント監査の全条件を保持する。他のケースやデバイスは対象外。前後のPerformance、16 GiB以上の物理空き、開始比のコミットとWDDM Dedicated各4 GiB以内、同一OS起動、System／Application監査と残留なしを要求する。 [D0-2A監督手順](B12651-D0-2A-HIP-IQ4NL-GETROWS-20261126.md)

実時間に重なる監視サンプルは `audit.json` の `SamplesWhileChildAlive` に記録する。0件なら前後と採取時刻を根拠に、演算中のGPU使用率は未観測と報告する。GPU負荷下のモニター、実機ドライバー障害時の停止、OS無応答時の回復は今回のCPUダミーから確定できない。重大イベント候補は実行ログに保全し、WER再処理等は人が発生時刻を照合する。SSH切断やOS無応答では状態を推測せず、再起動や再試行は行わない。

D0-2Cでは `test-backend-ops.exe` の起動、GPU数値テスト、再ビルド、モデルロード・推論・性能計測を実施していない。
