# Antigravity CLI: ThinkPad / EVO-X2 導入・運用記録 (2026-11-28)

## 適用範囲と確認状態

Antigravity CLI 1.5.18、Ubuntu 26.04.1 LTS、kernel 7.0.0-44-generic。今回の実機での記録であり、新版の CLI / Ubuntu でも同じ設定名・挙動であることは保証しない。標準計測・SSH 安全規則は [AGENT-RULES.md](AGENT-RULES.md)、[RUNBOOK.md](RUNBOOK.md)、[BENCHMARK-RULES.md](BENCHMARK-RULES.md)、[KNOWN-ISSUES.md](KNOWN-ISSUES.md) を正本とする。本書はそれらを緩和しない。

- ThinkPad の Codex 用 agent と Antigravity 用 antigravity は別々の非管理者ユーザー。OpenCode 用 opencode の Ubuntu アカウントとクライアントからの SSH 設定のみ準備済み、本体の導入は保留。
- クライアント→ThinkPad と ThinkPad→EVO-X2 は別の鍵。各エージェント専用鍵を使用し、EVO-X2 の既存一般ユーザー evox2-runner と ACL、計測ツール、製品 clone を共用。エージェントは同時稼働させない。
- GitHub main は文書・共通ツールの正本。ThinkPad の Antigravity 用参照 clone は公開リポジトリのみ。GitHub 書き込みは EVO-X2 の既存認証経由、文書専用 worktree で確認済み。非公開リポジトリの認証情報は ThinkPad の Antigravity に与えない。
- 本書に実機の非公開接続先、公開鍵の実値、認証情報、会話 UUID、セッション生ログは掲載しない。

## 1. インストールと認証

公式配布先として導入時に参照した URL: https://antigravity.google/cli/install.sh 。新規導入時は公式サイト・現行の手順を再確認し、ダウンロードしたスクリプトを検査してから専用一般ユーザーで実行する。例（導入時の案。現在の配布物を検証したものではない）:

```bash
curl --proto '=https' --tlsv1.2 -fSL https://antigravity.google/cli/install.sh -o install.sh
# 内容、取得元、公開されていれば署名・ハッシュを確認後
bash install.sh
agy --version
```

今回確認したユーザー側のバイナリは ~/.local/bin/agy (ELF x86-64)、運用時のバイナリは /opt/antigravity-cli/agy。後者は管理者所有とし、非管理者がバイナリや親ディレクトリを置換できないようにする。ユーザーが書き込める領域の実行物を管理者が昇格実行するのではなく、配布物の由来・内容を確認したものだけを管理者が配置する。更新は同じ確認を繰り返す。今回の正確な配置時コマンドと公開署名の有無は本記録では未確認。

OAuth 認証後に invalid settings: artifactReviewPolicy: unrecognized value "request-review" が発生。artifactReviewPolicy を asks-for-review に修正（または不正項目を削除して既定値を確認）する。toolPermission と artifactReviewPolicy は別項目である。設定ファイルは ~/.gemini/antigravity-cli/settings.json。編集前バックアップと python3 -m json.tool での構文確認を行う。OAuth トークンを表示・転送・コミットしない。

## 2. AppArmor と Terminal Sandbox

実機の初期状態:

- kernel.apparmor_restrict_unprivileged_userns = 1
- kernel.unprivileged_userns_clone = 1
- user.max_user_namespaces = 28497
- unshare --user --map-root-user true は uid_map の許可エラー。
- cli.log に Terminal sandbox unavailable: AppArmor restricts unprivileged user namespaces が出力された。

グローバルな userns 制限は解除せず、管理者所有の運用用 agy のみに userns を許す AppArmor プロファイル agy-evox2 を使用した。実測されたラベルは agy-evox2 (unconfined)。これは agy を AppArmor の厳密なファイルアクセス制御で閉じ込めるものではなく、CLI の Terminal Sandbox とは別の仕組みである。

再構築時は現機のプロファイル定義と公式 AppArmor 仕様を確認すること。本記録では実際のプロファイルファイル名・全文は回収していない。以下は構成の例であり、現機の完全な設定の復元ではない。

```text
abi <abi/4.0>,
include <tunables/global>
profile agy-evox2 /opt/antigravity-cli/agy flags=(unconfined) {
    userns,
}
```

管理者が配置先・所有者・モードを確認し、対象プロファイルを apparmor_parser -r でロードする。実際に使用する ABI・構文はインストール済み AppArmor で検証する。グローバル sysctl は変更しない。別エージェントへ例外を無条件に拡大しない。実行権限を必要なユーザーに限定する構成も検討可能だが、今回の実行ファイルの厳密なモードは未採取。

専用アカウントの ~/.bashrc に起動用 alias を置いた:

```bash
alias agy='/opt/antigravity-cli/agy --sandbox'
```

起動時にバージョンと Sandbox Mode ON を確認。alias は強制的なセキュリティ境界ではない。

初期の trustedWorkspaces 登録だけでは workspace が ro bind mount になり、touch に失敗。以下の対象限定許可を追加して rw 化した。

```json
{
  "enableTerminalSandbox": true,
  "trustedWorkspaces": ["/home/antigravity/workspaces/evox2-controller"],
  "permissions": {
    "allow": ["write_file(/home/antigravity/workspaces/evox2-controller)"]
  }
}
```

既存 settings.json の必要な項目を保持して統合すること。これは指定 workspace の編集許可も与える。CLI の保存設定は既定値と異なるものだけ残る場合があり、キーの未記載は /config で実効値を確認する。

実機確認: PID/net namespace がホストと異なる、workspace の findmnt が ro→rw、workspace 内 touch 成功、指定した workspace 外のパスへの touch 失敗、CLI 認証領域が mask/ro。外側の touch は No such file or directory で失敗したため、全ホストパスや全ネットワークの隔離を証明したものではない。

## 3. SSH と参照用 clone

既存の ThinkPad sshd の公開鍵認証を維持（PermitRootLogin no、PasswordAuthentication no、KbdInteractiveAuthentication no を実効設定で確認）。AllowUsers に専用ユーザーを追加する。既存管理者セッションを維持したまま sshd -t、sshd -T、systemctl reload ssh.service、新規接続検証を行う。一般ユーザーに sudo 等を付与しない。各アカウントの ~/.ssh は 0700、authorized_keys は 0600、秘密鍵は元の接続元から移さない。

ThinkPad の Antigravity 専用ユーザーで ssh-keygen -t ed25519 を使い、パスフレーズ付き専用鍵 ~/.ssh/id_ed25519_evox2 を作成。EVO-X2 の既存一般ユーザーの authorized_keys に公開鍵のみ追加（既存鍵を残し、ACLを変えない、UTF-8 BOMなし）。known_hosts は別経路で検証済みのホスト鍵を用いる。既存の SSH 接続先や ACL を拡大する必要はない。

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_evox2
ssh -F /dev/null -o BatchMode=yes -o ControlMaster=no -o ControlPath=none \
  -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o ForwardAgent=no \
  -i ~/.ssh/id_ed25519_evox2 evox2-runner@<verified-host> whoami
```

上の <verified-host> は置換用。ホスト鍵の不一致や認証失敗時は停止。無人計測の keepalive 等は RUNBOOK に従う。Post-quantum key exchange 警告は今回出たが接続は成功。警告を消すために SSH 安全設定を緩和しない。

ワークスペースを用意し、公開 main の参照用 clone を作成:

```bash
mkdir -p ~/workspaces/evox2-controller
cd ~/workspaces/evox2-controller
git clone --depth 1 --single-branch --branch main --filter=blob:none --sparse \
  https://github.com/ariera-j/llama.cpp-evox2-windows.git rules-main
git -C rules-main sparse-checkout set docs/evox2 tools/evox2
```

rules-main は文書・ツール参照専用。製品 source tree ではない。更新は操作者が行い、git status --porcelain が空であることを確認して git pull --ff-only。失敗したら強制リセットしない。セッション中は文書 SHA を固定し、製品 SHA、ビルド元 SHA、ツール SHA を区別する。

## 4. コントローラー AGENTS.md

ローカル workspace 直下に作成。実機の接続先等はローカルで設定し、GitHub に書かない。最低限含める事項:

- Remote user/host/repository、参照用 rules-main と main の指定。
- 作業前に rules-main/AGENTS.md、docs/evox2/automation/AGENT-RULES.md、EVOX2-ENVIRONMENT.md、RUNBOOK.md、KNOWN-ISSUES.md を読む。計測前には BENCHMARK-RULES.md と tools/evox2/README.md、関連する実験記録も参照する。
- 上記の SSH オプションと運用者提供 SSH agent、秘密鍵・トークンを読み出さないこと、失敗時に停止すること。
- ローカルは Sandbox 内、SSH/SCP は具体的コマンドの都度承認。包括的許可、セキュリティ設定変更、並列実機操作を禁止。
- 実機の作業範囲、安全監査、停止条件、Git 管理は共通ルールに従う。明示承認外の変更・計測・build・commit・push を行わない。日本語で根拠・不明点を報告。

誤操作防止の推奨（Codex 側にも同じ方針、実機適用の確認は未報告）: コントローラー用 AGENTS.md のみ root:専用ユーザーグループ、0440、ext4 の immutable 属性を付ける。所有者・モードだけでは書き込み可能な親ディレクトリからの unlink/rename を防げない。

```bash
# CLIを終了し、管理者が対象の正規ファイルであることを確認して実施
p=/home/antigravity/workspaces/evox2-controller/AGENTS.md
sudo sha256sum "$p"
sudo chown root:antigravity "$p"
sudo chmod 440 "$p"
sudo chattr +i "$p"
sudo lsattr "$p"
sudo sha256sum "$p"
```

一般ユーザーの test -r / test ! -w と SHA の不変を確認する。Codex は実際の起動ディレクトリを確認し root:agent とする。更新時のみ管理者が属性を解除して検証済み文書に更新し、属性と所有者・モードを復元する。Git 管理下の AGENTS.md には適用しない。親 workspace の移動や別 workspace での起動、参照 clone の変更を禁止する強制境界ではない。

## 5. 運用設定と開始・終了

| 項目 | 採用方針 |
|---|---|
| Agent Mode | Default |
| Model | Hydrogen Medium |
| Terminal Sandbox | ON |
| Tool Permission | proceed-in-sandbox（H7/H8でローカル承認0回） |
| Non-Workspace Access | OFF |
| Artifact Review | asks-for-review |
| SSH/SCP/外部操作 | 個別承認、包括的許可なし |
| 参照用 clone | 操作者が更新、エージェントは変更禁止 |
| 並列実機作業 | 禁止 |

H0〜H6 は request-review で実施。変更後の SSH/SCP 個別承認は H7/H8 では未試験なので、次回実機作業の最初に実際の承認表示を確認する。意図しない外部実行が自動承認されたら中止して request-review に戻す。初期の実機 SSH/計測/文書 push は成功済み。Sandbox 内の読み書きができる範囲は引き続き注意する。

通常起動: クライアントから専用アカウントへ SSH、rules-main の clean/fast-forward 更新と SHA 記録、ssh-agent と専用鍵の準備、workspace で agy。終了時は対象推論・ビルド・監視の状態とログ・Git 状態を共通ルールで確認し、CLI 終了後にそのセッションで起動した ssh-agent を終了する。作業途中の切断を正常終了とみなさない。

## 6. セッションログと利用枠

保存先 ~/.gemini/antigravity-cli/。conversations/*.db はセッション別 SQLite、brain/<UUID>/ は関連する出力等、log/cli-*.log は CLI ログ、conversation_summaries.db は要約・全文検索インデックス、history.jsonl 等も存在。認証ファイル antigravity-oauth-token、設定、会話本文、brain 内の実機出力を一括回収・公開しない。

集計用 Python 標準ライブラリスクリプト: [inspect_antigravity_logs.py](../../../tools/evox2/automation/inspect_antigravity_logs.py)。実ファイルの選択は操作者が行う。CLI と関連書き込みプロセスを終了させ、更新されない整合した DB を対象にする。WAL/SHM/journal がある場合は読み取りを拒否する（削除してはいけない）。例:

```bash
cd ~/workspaces/evox2-controller
python3 rules-main/tools/evox2/automation/inspect_antigravity_logs.py \
  --db "$HOME/.gemini/antigravity-cli/conversations/<session-id>.db" \
  --log "$HOME/.gemini/antigravity-cli/log/<cli-log>.log"
```

プレースホルダを実ファイル名に置換。複数の --db / --log を指定可能。出力は JSON の件数・BLOB形式候補・ログのキーワードとソース別件数で、会話・BLOB本文やログ本文は出力しない。共有前に集計結果も確認する。終了コード 1 は一部または全部の集計失敗。バージョン違い・未知スキーマには対応を保証しない。模擬データで件数、ソース別集計、秘匿文字列非出力、DBハッシュ不変、sidecar拒否、magic分類を独立確認済み。実機 DB に対する統合版の実行は未確認（個別集計スクリプトは実機実行済み）。

利用枠は /usage のタスク前後（週・5h、リセット時刻）を記録し、承認回数も別記する。gen_metadata などの BLOB は今回未解読。ログの token/cache/permission/error/duration 行数は実トークン・承認・失敗数・時間の合計ではない。詳細解析は必要になった時に再検討する。

## 7. 初期評価完了と今後

[評価記録](../AI-AGENT-EVALUATION-20261127.md)、[実機計測記録](HYDROGEN-CLI-BENCHMARK-20261128.md) を参照。H0〜H8 は初期評価として完了。定型計測・解析・文書作成を Hydrogen Medium の主用途とする。実際の障害時停止、本格的な複数run自動化、新規権限設定後の外部操作承認は未検証。H8 試作は非公開実験リポジトリに原版とレビューを保存済み、本番安全ゲートへの組込みは未承認。

OpenCode 本体導入、Hydrogen Low 比較、BLOB の内部解析、共通コントローラーの本番実装は保留。次は Neon / Sonnet の調査記録と現行ソースを照合し、ROCmFP4 FAST PLE16 の HIP 対応または PP/TG 高速化へ戻る。難しいGPU実装は Codex、定型計測・ログ集計は Hydrogen、技術調査は Neon を基本案とする。
