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
