# EVO-X2 P-MODE 読み取り運用

## 取得経路

`tools/evox2/lib/Evox2.Common.psm1` の `Get-Evox2PModeMetadata` は、最初に ACPI-WMI の Method ID 2 で現在値を読み取る。直接取得が失敗すると、ローカル Task Scheduler COM の `Schedule.Service` で既存タスク `\Evox2\PModeProbe` を照会し、`Run($null)` で起動する。計測側の PowerShell は通常権限で動作する。

既定では最大5秒、新しく書き込まれた `C:\ProgramData\Evox2\PMode\state.json` を待つ。呼び出し前の更新日時より新しいこと、JSON の `CapturedAt` が起動要求以降であること、管理者で実行された Method ID 2 の有効な結果であることを確認する。直接取得成功時は `Direct`、タスク経由成功時は `ScheduledTask`。失敗時は `Unknown` とエラーの理由を返す。CLI・Bench の両ラッパーは開始と終了時に同じモジュールを呼び、`conditions.json` と `result.json` の既存フィールドに記録する。P-MODE 照会エラー時も計測は継続する。

## 実機の構成

2026-11-24 確認。実行ユーザーは `ai`、LogonType は `Interactive`、RunLevel は `Highest`。現在のActionは Windows PowerShell の絶対パスを使い、以下の保護先のスクリプトと `state.json` を固定引数で指定する。登録済みActionには呼び出し元からの引数置換がない。

```text
C:\Program Files\Evox2\PModeProbe\
  pmode\Read-Evox2PMode.ps1
  lib\Evox2.Common.psm1
```

GitHub上のソースは `tools/evox2/pmode/Read-Evox2PMode.ps1` と `tools/evox2/lib/Evox2.Common.psm1`。Reader は隣接する `lib` のモジュールを読み込み、`-DirectOnly` で Method ID 2 の結果を一時ファイルに書いて置き換える。Git管理のソース更新は実行用コピーへ自動反映しない。

タスク個別のDACLで `evox2-runner` に読み取り・実行のみ（実機のACEマスク `0x1200a9`）を付与する。タスク定義の書き込み、削除、DACL変更は許可しない。保護先と親ディレクトリは Administrators と SYSTEM が変更でき、Users は読み取り・実行のみ。状態ファイルには既存の Users の読み取り権限があり、`evox2-runner` の書き込み・削除は拒否されている。状態の置き換え後も同じアクセス条件が成立することを確認する。

## 管理者が実行用コピーを更新する手順

1. GitHub上の対象コミットを固定し、管理者が管理する作業領域に2ファイルを取得する。保護先への反映前に、現在の2ファイルとの差分、Reader の相対インポート、`-DirectOnly` と Method ID 2 のみの動作、UTF-8 BOM を確認する。
2. 管理者のWindows PowerShellで、既存のAction・DACL・ファイルACLを読み取る。タスクが停止中で、Actionが保護先の絶対パスと固定引数を参照し、ファイルと全親ディレクトリが一般ユーザーによる置き換えやリパースを許さないことを確認する。更新前の2ファイルと SHA-256 を管理者保護領域に保存する。
3. レビュー済みソース2ファイルの `Get-FileHash -Algorithm SHA256` を記録し、管理者が対応する保護先へコピーする。コピー後に双方の SHA-256 が一致することと、保護先の所有者・ACLが維持されていることを確認する。失敗時は使用を停止し、管理者が保護済みの控えから復元する。既存タスクの再登録は不要。
4. 通常ユーザーから下記コマンドを一度実行し、取得値と新しいタイムスタンプを確認する。GitHubのcloneやr5などの古いworktreeはActionから参照しない。

新規マシンでタスクが存在しない場合は、管理者が保護先と状態ディレクトリを準備・監査してから、レビュー済みの `tools/evox2/pmode/Install-Evox2PModeProbeTask.ps1` を、タスク実行者としてログオン中の管理者セッションで実行する。登録モードは `TASK_CREATE` で、既存タスクは上書きしない。スクリプトは保護先の絶対パスを参照し、登録後に自動起動やDACL変更は行わない。権限委任は別途承認してから当該タスクに限って実施する。今回の既存タスクにはインストーラーを使用しない。

## 通常ユーザーの確認と障害時の切り分け

Codex専用cloneのルートで、Windows PowerShell 5.1から実行する。

```powershell
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
Get-Evox2PModeMetadata | Format-List ProbeSucceeded, Transport, MethodId, Elevated, Mode, RawValue, CapturedAt, Error
```

- `WmiOpenBlock` の error 5 は通常ユーザーの直接照会で確認されている。COMの `GetFolder('\Evox2').GetTask('PModeProbe')` でも失敗する場合は、タスクの登録・パス・個別DACLを管理者が確認する。CIM名前空間への権限付与は不要。
- COM起動に成功しても、`ai` がログオフすると Interactive タスクは実行できない場合がある。対象ユーザーのログオン状態、タスクの `LastRunTime`・`LastTaskResult`、状態ファイルの最終更新時刻と `CapturedAt` を確認する。ファイルが新しくならない場合は古い結果を採用しない。
- 状態ファイルが更新されても、JSON解析、時刻、Method ID、実行権限、モードの照合で失敗した場合はエラーを確認する。管理者は実行用コピーのSHA-256と状態ファイルのACLを確認する。

2026-11-24 15:00:03 JST、`evox2-runner` の実機単発確認で `ProbeSucceeded=True`、`Transport=ScheduledTask`、`MethodId=2`、`Elevated=True`、`Mode=Performance`、`RawValue=1`、`CapturedAt=2026-11-24T15:00:03.3370543+09:00` を取得。タスク結果は0。単体テストと両計測スクリプトのJSON連携確認では推論を実行していない。
