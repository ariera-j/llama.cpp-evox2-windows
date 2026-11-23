# 2026-11-23 GitHubブランチ棚卸しとアーカイブ候補（実行前計画）

> **2026-11-23 JST の静的棚卸し。** 対象は `ariera-j/llama.cpp-evox2-windows` / `main`。GitHub上の全53ブランチを列挙し、各ブランチとmainの`compare_commits`（ahead/behind、変更ファイル）、公開リポジトリ内の統合・実験記録を参照した。**この文書作成時点ではタグ作成・ブランチ削除・リネーム・ソースmerge・force pushを一切実施していない。** 分類は次回作業前に再確認すること。

## 1. 方針

- GitHubには「ブランチをアーカイブ済みにする」専用操作はない。**元ブランチの先端コミットを `archive/2026-11-23/<original-branch>` というGitタグで保存し、リモートタグの先端SHAが一致したことを検証した後、元のリモートブランチを削除**することでブランチ一覧を縮小する。
- タグは可能ならannotated tagにし、元ブランチ名・先端のcommit SHA・保存日・計測/運用上の注意をメッセージに記録する。既存タグ `evox2-integrated-2026-10-29` や他の歴史的tagを変更しない。
- **mainへの文書集約≠コードのマージ。** 歴史的実験ブランチのunique commitsはアーカイブタグで保存する。archive済みコードを安全な実装と誤認しない。
- ブランチベースの `/blob/<branch>/` / `/tree/<branch>/` GitHubリンクは削除で切れることがある。参照頻度の高いリンクはタグURLかcommit permalinkへ変更する。
- main・運用上の基準ブランチ・作業中のCodexブランチを削除しない。リモートとローカルのworktreeは別物。稼働中のEVO-X2やCodexのローカルworktreeは一括削除しない。
- 2026-11-23調査時点で**オープンPRは0件**。実行前にPR、branch protection、remoteの新しいcommit、実機worktreeを再確認する。

## 2. 判定結果：53ブランチ → 保持7 / 内容確認5 / アーカイブ候補41

### A. 現時点で保持（7件）

| ブランチ | 保持理由 |
|---|---|
| `main` | 唯一の現行デフォルト。常に除外 |
| `baseline/v1.0.0-docs-tools-only-20261115` | 次のupstream選定で比較基準として使用する可能性 |
| `investigation/v1-strata-dense-gemm-20261115` | v1.0.0でのStrata/GEMM検証ソース。次の移植候補の差分確認まで保持 |
| `investigation/v1-strata-moe-fusion-20261115` | IQ2_S Gate/Up/SwiGLU融合PoC。再利用可否を確認するまで保持 |
| `r5/upstream-refresh-20261009` | r5性能・patch帰属の凍結基準 |
| `r6/combined-20261028` | r6統合・公開時点の再現基準。既存公開タグと先端は同一とは限らない |
| `r6/upstream-refresh-20261025` | r6の清浄upstream対照。mainの祖先だが現時点では基準として保持 |

※保持は永久保証ではない。新しいupstreamベースが安定し、基準をタグと計測マニフェストで再現できる状態になれば一部を再分類してよい。

### B. 先にmainとの差分解消が必要（5件）

| ブランチ | 保留の理由 |
|---|---|
| `codex/build-wrapper-20261123` | ビルドラッパーとRUNBOOKの分岐変更。mainとコードを照合 |
| `codex/main-monitor-check-20261123` | KNOWN-ISSUESの追記がmainにあるか確認 |
| `codex/model-baseline-plan-20261123` | 新規モデルベースライン文書がmainに取り込まれたか確認 |
| `codex/monitor-physical-memory-20261123` | Monitor-LlamaProcess.ps1変更と最終接続テストを照合 |
| `codex/resource-monitor-20261123` | Measure-LlamaCli / Monitor-LlamaProcessの変更を照合 |

これらはmainに対する比較で**ahead=1～2**の変更を含む。mainの類似文書やスクリプトへコピー済みでも、そのbranchに固有のコードが残っている可能性がある。内容を照合してから、必要なものだけmainへ取り込む（実行条件が変わる変更は明示的にレビュー）。その後タグへ移し、アーカイブ候補に変更する。

### C. アーカイブ候補（41件）

次の名前を**明示allowlist**として扱う。外部refをパターン（`investigation/*`、`r5/*`、`codex/*`）で無差別に削除してはならない。

```text
codex/automation-docs-20261123
codex/main-handoff-20261123
feature/r6-llama-bench-real-prompt-20261103
integration-check/r5-noop-rocmfpx-20261021
integration-check/r5-noop-rocmfpx-stageb-flatten-20261021
investigation/gemma4-31b-v1-rocm-20261116
investigation/gemma4-fa31323-globalfa-rgp-20261121
investigation/gemma4-fa31323-pp-rgp-20261121
investigation/gemma4-v1-fa31323-20261121
investigation/gemma4-v1-globalfa-rgp-20261121
investigation/gemma4-v1-pp-rgp-20261121
investigation/r5-adlx-gpu-monitor-20261015
investigation/r5-mtp-dense-compat-20261011
investigation/r5-mtp-dense-indexer-20261011
investigation/r5-mtp-draft-kv-parity-20261019
investigation/r5-mtp-eh-proj-flatten-20261016
investigation/r5-mtp-noop-20261012
investigation/r5-mtp-pp-kv-crop-stage1-20261014
investigation/r5-mtp-pp-target-rewarmup-30511-20261016
investigation/r5-mtp-pp-trace-20261013
investigation/r5-mtp-rollback-diagnostic-20261019
investigation/r5-rocm-qsa-argsort-topk-20261022
investigation/r5-rocm-qsa-topk-baseline-20261022
investigation/r5-rocmfpx-vulkan-20261020
investigation/r5-vulkan-off-fa-dispatch-20261010
investigation/r6-pp-fa-mask-rgp-20261105
investigation/r6-rocm-fa-kvmax-diag-20261108
investigation/r6-rocm-moe-topk-diag-20261107
investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110
investigation/r6-rocm-pp-fa-trace-20261107
investigation/r6-rocm-rgp-anchor-visibility-20261107
investigation/r6-rocm-rgp-moe-anchor-20261107
investigation/r6-rocm-rgp-moe-layer-tags-20261107
r2/legacy
r3/upstream-first
r4/upstream-refresh-20261002
r6/rocm-pp-timing-20261115
research/rocm-qsa-gather-20261030
setup/strata-pp-v1-docs-tools-20261115
test/mtp-qsa-prototype
test/qwen35-vulkan-2gib-guard
```

- 41件中**4件はmainの祖先（ahead=0）**：`codex/automation-docs-20261123`、`codex/main-handoff-20261123`、`r4/upstream-refresh-20261002`、`research/rocm-qsa-gather-20261030`。再現用tagを作った後なら本体のrefを削除できる見込み。
- 残り**37件はmainからdivergeして独自コミットを持つ**。**タグ保存前に絶対に消さない**（歴史的実装・診断shader、ツール・設定等はmain未統合の可能性）。ahead数が多いbranchではupstreamからの大きなimportが混在するので、ahead数をすべて独自高速化コミットと解釈しない。
- Gemma 4のFA #31323 / Global FA関連の6本は**危険が未解明の実験状態としてread-only archive**。GPU timeoutの原因を断定しないが、Codexの通常無人ビルド・ベンチマーク用baseに選ばない。
- r5 MTP / r6 RGP / QSA / ROCmFPx / 旧r2・r3・r4、r6診断、旧テストbranchは研究結果として保存。下流の正本は [PATCHES](PATCHES.md)、[PERFORMANCE-RESEARCH-LOG](PERFORMANCE-RESEARCH-LOG.md)、[文書集約](DOCUMENTATION-RECONCILIATION-2026-11-23.md)、[r5/r6旧ブランチ監査](R5-R6-BRANCH-INVENTORY-AND-PRE-RELEASE-CHECKLIST-2026-10-29.md) を参照。

## 3. Codexから安全に実行するときの手順（まだ未実施）

1. **別の管理用clone/worktreeで実行**。EVO-X2で推論中のworktreeやCodexの起動中プロセスを変更しない。作業ツリーclean、`git remote -v`、`git status`、`git worktree list --porcelain`、`git ls-remote --heads origin`を保存する。remoteが本リポジトリのoriginであることを検証する。
2. 各allowlist branchのremote先端 **SHA40を取得してmanifest（branch/SHA/date/status）に固定**。照合後にbranchが進んだ場合は停止して再監査する。`main`と保持・保留リストに一致するbranchが紛れたら停止する。open PRやbranch protectionにも注意。
3. 最初の実行は**dry-runだけ**。タグ名`refs/tags/archive/2026-11-23/<branch>`がGit refとして妥当で、既存tagと衝突せず、取得対象commitがローカルに存在するか確認する。
4. 次の段階で**tag作成とpushだけを実行**。成功後、`git ls-remote --tags origin`でタグが存在し、**annotated tagはpeeled commit SHA**が元branchのSHAと一致することを確認。タグが既存で異なるコミットを指すなら上書きせず停止。
5. **削除は別段階・明示承認後**。タグを全件検証し、GitHubのbranch-basedリンクとworktree使用状況を確認してから、対象41件のうち個別に選択したrefだけ`git push --force-with-lease=refs/heads/<branch>:<expected_sha> origin :refs/heads/<branch>`で削除。エラー時は全処理を停止。広域`--prune`、`--mirror`、force pushは避ける。
6. 削除後は`git ls-remote --heads origin`で対象branchが消えたこと、対応する`refs/tags/archive/2026-11-23/...`が全件残ることを確認。manifestに実行commit、タグSHA、実行日時、成功/失敗、戻し方を記録してGitHubへpushする。
7. 戻す場合は、保存したタグが指すcommitから新しいbranchを作成できる。削除した元branch名で再作成する場合はCodexで使用中のworktreeとリンクに注意する。

旧来の安全な削除手順は [Invoke-R6StageBranchCleanup.ps1](../../tools/evox2/git/Invoke-R6StageBranchCleanup.ps1) を参照。ただし**このスクリプトは旧r6中間8枝限定であり、今回の41件に使えるものではない**。新しい安全なarchiveツールを作るなら、dry-run / tag phase / delete phaseの分離、SHA lease、branch明示allowlist、UTF-8 BOMのPowerShell 5.1互換性、log保存を必須にする。

## 4. 計画と実施を混同しないための状態

- **済み：** 53件のbranch inventory、mainとの比較、保持・保留・archive候補の暫定分類、open PR有無確認、過去のbranch運用文書の参照。
- **未実施：** GitHub tag作成、remote branch削除、EVO-X2ローカルworktree/未push変更の確認、branch URL完全監査、branch archiveスクリプト作成・実行、各branch先端SHAの固定manifest作成。
- **目的：** 最初は41候補を対象とし、削除承認・実行後は53→12ブランチまで縮小可能（作業中に新しいbranchが増えていない前提）。さらに保留5件や旧baselineも後日整理できる。

新upstream b12651等を取り込むCodex作業は、**このアーカイブ作業をソースmergeやモデル実験と混同せず**、新しい`codex/`または`integration/`専用branchで開始する。

