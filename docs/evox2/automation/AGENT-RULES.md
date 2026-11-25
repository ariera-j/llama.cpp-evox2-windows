# EVO-X2 エージェント運用ルール

Codex、OpenCode などが ThinkPad から EVO-X2 の専用 clone を操作するときに適用する。作業前にリポジトリの [AGENTS.md](../../../AGENTS.md) と今回の依頼範囲を確認する。

## SSH と Windows ACL

- 接続先は `evox2-runner@192.168.240.38`。SSH オプションは `-F /dev/null -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=yes`。ホスト鍵や認証の検証に失敗したら停止して報告する。認証情報は文書やログに記録しない。
- 作業 clone は `C:\llama-build\automation\llama.cpp-evox2-windows`。作業出力は `C:\llama-build\automation` 配下、ログは `C:\llama-build\_logs\codex`。2026-11-23 の ACL 確認では両領域への書き込みに成功し、`C:\llama-build\_archive` と `C:\llama\models` の直下ではディレクトリ作成が拒否された。
- 既存の r6/v1 worktree、共有依存キャッシュ `C:\llama-build\evox2-deps`、モデル、アーカイブ、SDK は保護対象。必要な読み取りや SDK の実行だけを行う。テスト用の一時ファイルには一意名を使い、その実行が作成したものだけを片付ける。

## Git と作業範囲

- `git status --porcelain` を確認し、更新やブランチ切替は作業ツリーがクリーンな場合に進める。指定された基準コミットを確認し、専用の作業ブランチを使う。main の更新は fast-forward のみ。競合、想定外の変更、ブランチ名の衝突があれば停止する。
- 既存のブランチを保持する。`git reset --hard`、`git clean`、force push は使用しない。commit と push は明示的に依頼された範囲でのみ行う。レビュー前は diff と status を提示する。
- ソースやビルドスクリプトの変更、configure・ビルド、依存の取得、ベンチマーク、モデル推論は、それぞれ依頼で認められた範囲で行う。モデル推論の際はバックエンド、モデル、入力、実行規模を個別に確認する。
- 両バックエンドとも自動検証は CLI のバージョン、デバイス列挙、マニフェスト照合まで。`test-backend-ops.exe` はビルド対象に含められる。自動実行と `-RunBackendTest` は禁止する。GPU 異常時の扱いは [既知の問題](KNOWN-ISSUES.md) を参照する。
- Codex 専用ラッパーの通常ビルドと configure-only は、レビュー済み b12651 の公式 BoringSSL / LLVM OpenMP が専用キャッシュにない場合に限り自動取得できる。preflight は検査のみで、`-Offline` は依存取得を禁止する。破損、取得元・ハッシュ・SHA 不一致、取得不能、未レビューの upstream 入力は configure 前に停止する。SDK や開発ツールの自動導入・更新は行わない。
- Codex 専用 clone のパスを維持し、ビルド先には短い未使用のディレクトリ名を選ぶ。長時間コンパイル時は Ninja の進捗、コンパイラのコマンドと PID、CPU 時間、メモリ、ログを保存する。変更を判断する前に同じ条件での再実行を避ける。

## 文書の正本と同期

- GitHub の `main` を共通ドキュメントと確定済み調査記録の正本とする。作業前に GitHub の `main` の SHA を確認し、[運用ルール](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/automation/AGENT-RULES.md)、[実機環境](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/automation/EVOX2-ENVIRONMENT.md)、[ランブック](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/automation/RUNBOOK.md)、[既知の問題](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/automation/KNOWN-ISSUES.md) と対象の検証記録を読む。必要な運用文書を確認できなければ停止して報告する。
- 性能計測の計画・実行前に GitHub の `main` にある [BENCHMARK-RULES.md](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/automation/BENCHMARK-RULES.md) を必ず確認する。
- 実験ソース、計測・検証スクリプト、未採用パッチは作業ブランチに置く。確定した Markdown、結果 CSV、マニフェスト、実行ログの必要な部分を文書専用コミットで `main` に反映する。実験で使用したブランチ、ソース SHA、ビルド識別情報、実行条件、生ログの所在を記録し、実装やスクリプトの参照は実行時のコミットに固定する。
- 同期前に、GitHub の `main`、作業ブランチ、実機 clone の HEAD・作業ツリー・追跡先と ahead/behind を確認する。既存の未コミット変更は退避して内容を照合し、取り込み済みと確認できた差分は同期後の blob で検証する。競合や採否を判断できない差分は保持し、対象パスと理由を報告する。
- 共通の運用文書は `main` の該当ファイルを現行作業ブランチに文書専用コミットとして反映する。同期前後で文書以外の差分が空であることと、実機の HEAD が対象の追跡先と一致することを確認する。過去の実験ブランチと固定 SHA の記録は当時の状態を保持する。世代別の調査記録は [EVO-X2 文書索引](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/main/docs/evox2/README.md) を参照する。

## P-MODE 管理者タスク

- 計測側はMethod ID 2の読み取りだけを行い、直接取得に失敗したら既存の `\Evox2\PModeProbe` をCOMで引数なしで起動する。
- 管理者タスクは `C:\Program Files\Evox2\PModeProbe` の保護済みコピーを実行する。Codexはこの配置のファイル、タスク定義、DACL、ユーザー権限を変更しない。GitHub上の変更を反映する場合は、管理者が差分・SHA-256・ACLを確認する。[P-MODE 読み取り運用](PMODE-PROBE.md)
