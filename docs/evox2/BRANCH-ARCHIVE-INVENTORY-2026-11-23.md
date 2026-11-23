# 2026-11-23 GitHubブランチ棚卸しとアーカイブ候補（実行前計画）

> **2026-11-23 JST の静的棚卸し。** 対象は `ariera-j/llama.cpp-evox2-windows` / `main`。GitHub上の全53ブランチを列挙し、各ブランチとmainの`compare_commits`（ahead/behind、変更ファイル）、公開リポジトリ内の統合・実験記録を参照した。**この文書作成時点ではタグ作成・ブランチ削除・リネーム・ソースmerge・force pushを一切実施していない。** 分類は次回作業前に再確認すること。


## 2026-11-24追補：手動側worktreeの実測一覧（ユーザー提供、取得日時未記録）

**重要：下の一覧は手動操作ユーザーが実行した `git worktree list --porcelain` と `git remote -v` の出力を保存したもの。** Codexユーザーから旧cloneの`.git`を直接読み取れたことを意味しない。実行日時、`git status`、各branchの未pushコミット、`git branch -vv`、Codex専用cloneのworktreeは未確認。EVO-X2のACLと所有者は変更しない。

### Git共通ディレクトリ系統A（r2/r5/r6）

確認起点：`C:\llama-build\llama.cpp-evox2-windows-r6`。remote `origin=https://github.com/ariera-j/llama.cpp-evox2-windows.git`、`upstream=https://github.com/ggml-org/llama.cpp.git`（fetch/push各設定）。

| worktree | HEAD | branch/状態 | 判断 |
|---|---|---|---|
| `C:\llama-build\llama.cpp-evox2-windows-r2` | `23c316fb5af67da74e614af4a7453fba9ae46189` | `r2/legacy` | 別系統。保持・bundle再現ゲート前はremote削除禁止 |
| `C:\llama-build\llama.cpp-evox2-windows-r5` | `25004972199c68a0678c2341c155dc84a98e5da8` | `r5/upstream-refresh-20261009` | 保持 |
| `C:\llama-build\llama.cpp-evox2-windows-r6` | `8054fc278f0f00dce7876c78693f5d42e387ddfb` | `main` | 保持。リモートmainに追随済みとは未確認 |
| `C:\llama-build\llama.cpp-evox2-windows-r6-webui` | `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f` | detached HEAD | 既存検証済みr6 source。branchでないが参照元commitを保持 |

### Git共通ディレクトリ系統B（v1.0.0研究）

確認起点：`C:\llama-build\llama.cpp-evox2-v1-strata-pp`。remote `origin=https://github.com/ariera-j/llama.cpp-evox2-windows.git`（fetch/push各設定）。Aとは異なるworktree集合。

| worktree | HEAD | branch/状態 | 判断 |
|---|---|---|---|
| `C:\llama-build\llama.cpp-evox2-v1-strata-pp` | `76be555297bd3883c574bb4c918adef5229ad75c` | `investigation/v1-strata-dense-gemm-20261115` | 保持 |
| `C:\llama-build\llama.cpp-evox2-v1-gemma4` | `352b620aab388002ffe9b991986dcf980f3de5ca` | `investigation/gemma4-31b-v1-rocm-20261116` | **従来のarchive候補から要確認へ移す。現役worktree** |
| `C:\llama-build\llama.cpp-evox2-v1-pp-rgp` | `010d0d3b1d9e4c78379b278a2aa95d6e3456acef` | `investigation/gemma4-v1-pp-rgp-20261121` | **従来のarchive候補から要確認へ移す。現役worktree** |

### 削除ゲートと扱い

- **いま観測されたworktreeは合計7個、2つの独立したworktree集合**。この記録だけでは別にあるCodex専用cloneの状態や、他の独立したcloneの不存在は証明できない。
- 現在checkout中のbranchは、remoteを削除してもローカルworktree/branchが消えるわけではない。ただし追跡先が消えて混乱しやすくなるので**現役worktreeのremote branchは保持**。
- 旧cloneの`.git`をCodexから読むためにACL/所有権を緩めない。Codexには**この一覧を既知の保護ブランチとして使わせる**。必要な追加確認は所有ユーザーが読み取り専用で行う。
- 追加の最小確認（各集合の管理起点で実行）：`git -C <repo> branch -vv` と、各worktreeに対する `git -C <path> status --porcelain=v1 -b`、さらに `git ls-remote --heads origin`。必要に応じてローカルbranchとremoteのcommit比較を行う。`worktree list`だけでは未commit/未pushは分からない。
- `r6-webui` はdetachedのため削除対象branchではないが、`b82243bf...` のcommit参照は保持。既存ソースcheckpointはタグに紐づけて追跡可能にする。
- **修正後の暫定分類は 保持7 / 要確認13 / archive候補33（計53）**。以下の元の日付付き方針を読み替える。元の候補を機械実行せず、manifestを再生成・レビューする。

## 2026-11-23 追加の保全条件（削除作業より優先）

> **重要：当初の「41件をアーカイブ候補」は保全調査の途中段階の分類だったため修正。** 実装調査で、`main` にない診断専用コードを実験ブランチ上に確認した。さらにr2はr1からの別ベース系譜であり、Codex専用アカウントから旧Windows cloneの`.git`/worktreeを検査できない可能性がある。**この追加条件を解消する前に、元ブランチのリモート削除を実行しない。** 本書はタグ作成もまだ行っていない計画文書。

### 確認できたmain未統合の実装

| 目的 | 保全すべき原実装の参照 |
|---|---|
| 実文書で`llama-bench` PP測定 | `feature/r6-llama-bench-real-prompt-20261103`: `tools/llama-bench/llama-bench.cpp` に `-f/--prompt-file`、`--prompt-slice` と読み込み処理。mainの同ファイルには未実装。ソース履歴は[Gate1実装記録](R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md)参照。 |
| Vulkan RGP/Mask | `investigation/r6-pp-fa-mask-rgp-20261105`: `ggml/src/ggml-vulkan/ggml-vulkan.cpp` の `GGML_VK_FA_RGP_MARKERS`、`ggml_vk_fa_rgp_dispatch`、`EVOX2_FA_`。mainの同ファイルにこれらはなし。[ソース移植調査](R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md)参照。 |
| ROCm FA/MoE RGP | `investigation/r6-rocm-rgp-moe-anchor-20261107` の `ggml/src/ggml-cuda/fattn.cu` にhost trace `GGML_HIP_FA_TRACE` と `evox2_hip_anchor_fa_layer19/23`。mainにはこれらはなし。 |
| ROCm帯別 survey とIQ3/IQ4 MMQ | `investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110` に `ggml/src/ggml-cuda/evox2-hip-fa-survey.cuh`（mainでは不存在）。[RGP survey/移植記録](R6-HIP-FA-RGP-SURVEY-PORTING-2026-11-11.md)。 |
| Vulkan元ドナー | `investigation/r5-vulkan-off-fa-dispatch-20261010` はr6へのmarkers/Mask抽出の元。別変更まで混ぜた全ファイル移植はせず、次回も機能別の差分で読む。 |

**これら5診断ブランチは「保全確認待ち」に変更する。** 将来タグで保全し、各コードの所在・flag/対象ファイル・元SHAと復元コマンドをmanifestに固定し、GitHub上でtagからコードが読めることまで検証すれば、ブランチ名の維持自体は必須ではない。ただしリンク修正と旧cloneの参照状況を未確認の間は削除保留。

### r2は別系統として二重保全

[mainに集約したr1由来のmanifest](backport-r1/manifest.json)は、元のベースを `https://github.com/LaurentZuijdwijk/llama.cpp`、ベースコミットを `5e085d123eead2e89b5c19f824fccb05727da6a2` と記録。`r2/legacy` の[r2 README](../../README.md)（r2ブランチを選択して閲覧）はr1 `ee245db63d4bd08f590aa5a4d756c5913e56ffdd` から発展したQSA union版として説明している。

- r2は単なる古いmainのコピーではない。GitHub比較でもmainとの差分はdiverged（2026-11-23時点 ahead=107、behind=1348）。
- **r2/legacyは直ちに削除しない。** 先端SHA、Gitの祖先chain、base/upstreamのSHA、サブモジュール/LFS依存を記録し、tagを作成して読み出しを検証する。
- さらに、現在の公開リポジトリを**専用のmirror clone**にすべてのrefs・tagをfetchし、`git bundle create ... --all`で独立したbundleを作成、`git bundle verify`、別cloneでの復元・`git cat-file -t <r2-head/base-commit>`を検証する。bundleは外部HDD等に保管。Git LFS実体・submodule先・release assets・RGP生ログはGit bundleに自動収録されないため、使用有無を別途確認。
- リモートのr2ブランチ参照を除去するかは、**tagと独立bundleの検証後に改めて判断**。元ベースGitHubリポジトリが消えても、参照するコミットの実体が保存されていることを保証する。

### Codexの旧clone/worktree不可視性

- `C:\llama-build\llama.cpp-evox2-windows-r6` 等の旧cloneは別Windowsユーザー所有、`.git`とACLが異なり、Codex専用ユーザーから`git status` / `git worktree list`に失敗し得る。**アクセス拒否＝clean / 未使用 / worktreeなし、ではない。**
- Codex専用のアクセス可能なcloneから確認できる`git worktree list`は、そのcloneと同一common .gitに属するworktreeだけで、**独立した旧cloneのworktreeは網羅できない**。GitHub APIからはリモートbranchとcommitは監査できるが、旧EVO-X2ローカルcloneの作業状態は判定できない。
- 所有ユーザーによる**読み取り専用確認**（`git -C '<path>' status --porcelain=v1 -b`、`git -C '<path>' branch --show-current`、`git -C '<path>' worktree list --porcelain`、`git -C '<path>' remote -v`、必要なら未push確認）の結果をmanifestに追加する。複数cloneでは各cloneごとに行う。できなければ **REMOTE BRANCH DELETE は保留**、タグ作成・保存のみを先行する。
- `safe.directory '*'`、ACL変更、takeown、所有者変更、`.git`直接編集、旧cloneへの強制fetch/prune、ローカルworktree自動削除は行わない。Codexで操作するのは専用cloneとGitHubの明示allowlistだけ。

## 1. 方針

- GitHubには「ブランチをアーカイブ済みにする」専用操作はない。**元ブランチの先端コミットを `archive/2026-11-23/<original-branch>` というGitタグで保存し、リモートタグの先端SHAが一致したことを検証した後、必要な保全確認がすべて終わったブランチに限り元のリモートブランチを削除**することでブランチ一覧を縮小する。
- タグは可能ならannotated tagにし、元ブランチ名・先端のcommit SHA・保存日・計測/運用上の注意をメッセージに記録する。既存タグ `evox2-integrated-2026-10-29` や他の歴史的tagを変更しない。
- **mainへの文書集約≠コードのマージ。** 歴史的実験ブランチのunique commitsはアーカイブタグで保存する。archive済みコードを安全な実装と誤認しない。
- ブランチベースの `/blob/<branch>/` / `/tree/<branch>/` GitHubリンクは削除で切れることがある。参照頻度の高いリンクはタグURLかcommit permalinkへ変更する。
- main・運用上の基準ブランチ・作業中のCodexブランチを削除しない。リモートとローカルのworktreeは別物。稼働中のEVO-X2やCodexのローカルworktreeは一括削除しない。
- 2026-11-23調査時点で**オープンPRは0件**。実行前にPR、branch protection、remoteの新しいcommit、実機worktreeを再確認する。

## 2. 判定結果：53ブランチ → 保持7 / 要確認13 / アーカイブ候補33

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

### B. 先にmainとの差分解消・保全が必要（13件）

| ブランチ | 保留の理由 |
|---|---|
| `codex/build-wrapper-20261123` | ビルドラッパーとRUNBOOKの分岐変更。mainとコードを照合 |
| `codex/main-monitor-check-20261123` | KNOWN-ISSUESの追記がmainにあるか確認 |
| `codex/model-baseline-plan-20261123` | 新規モデルベースライン文書がmainに取り込まれたか確認 |
| `codex/monitor-physical-memory-20261123` | Monitor-LlamaProcess.ps1変更と最終接続テストを照合 |
| `codex/resource-monitor-20261123` | Measure-LlamaCli / Monitor-LlamaProcessの変更を照合 |

**以下のCodex用5件は**mainに対する比較で**ahead=1～2**の変更を含む。mainの類似文書やスクリプトへコピー済みでも、そのbranchに固有のコードが残っている可能性がある。内容を照合してから、必要なものだけmainへ取り込む（実行条件が変わる変更は明示的にレビュー）。その後タグへ移し、アーカイブ候補に変更する。

**追加の保全確認待ち（6件：元の41件から一時除外）**

| ブランチ | なぜ今は削除候補にしないか |
|---|---|
| `feature/r6-llama-bench-real-prompt-20261103` | 実入力native -f/--prompt-slice。mainのtools/llama-bench/llama-bench.cppにはない。 |
| `investigation/r6-pp-fa-mask-rgp-20261105` | Vulkan GGML_VK_FA_RGP_MARKERS/FA labels、mask snapshot。main ggml-vulkan.cppにはない。 |
| `investigation/r6-rocm-rgp-moe-anchor-20261107` | ROCmのFA host traceとGPU可視マーカー、MoE位置合わせの原型。 |
| `investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110` | ROCm survey header evox2-hip-fa-survey.cuh とMMQ調査。mainには専用ヘッダーなし。 |
| `investigation/r5-vulkan-off-fa-dispatch-20261010` | Vulkan markerのr5由来ソースと実験記録。後続r6への移植依存を保全。 |
| `r2/legacy` | r1/r2はLaurentZuijdwijk/llama.cppをベースとする別系統の歴史。Gitタグに加えて独立bundleで全到達履歴を確保。 |

**追加：現在checkout中のGemma 4ブランチ2件も要確認へ移動**

| ブランチ | worktree / 実行時HEAD |
|---|---|
| `investigation/gemma4-31b-v1-rocm-20261116` | `C:\llama-build\llama.cpp-evox2-v1-gemma4` / `352b620aab388002ffe9b991986dcf980f3de5ca` |
| `investigation/gemma4-v1-pp-rgp-20261121` | `C:\llama-build\llama.cpp-evox2-v1-pp-rgp` / `010d0d3b1d9e4c78379b278a2aa95d6e3456acef` |

**保全確認まで削除禁止。** タグ保存後でも、診断コードの所在目録・r2独立bundle・旧clone worktree確認を完了してから再分類する。

### C. アーカイブ候補（33件：元41件から8件を一時除外）

次の名前を**明示allowlist**として扱う。外部refをパターン（`investigation/*`、`r5/*`、`codex/*`）で無差別に削除してはならない。

```text
codex/automation-docs-20261123
codex/main-handoff-20261123
integration-check/r5-noop-rocmfpx-20261021
integration-check/r5-noop-rocmfpx-stageb-flatten-20261021
investigation/gemma4-fa31323-globalfa-rgp-20261121
investigation/gemma4-fa31323-pp-rgp-20261121
investigation/gemma4-v1-fa31323-20261121
investigation/gemma4-v1-globalfa-rgp-20261121
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
investigation/r6-rocm-fa-kvmax-diag-20261108
investigation/r6-rocm-moe-topk-diag-20261107
investigation/r6-rocm-pp-fa-trace-20261107
investigation/r6-rocm-rgp-anchor-visibility-20261107
investigation/r6-rocm-rgp-moe-layer-tags-20261107
r3/upstream-first
r4/upstream-refresh-20261002
r6/rocm-pp-timing-20261115
research/rocm-qsa-gather-20261030
setup/strata-pp-v1-docs-tools-20261115
test/mtp-qsa-prototype
test/qwen35-vulkan-2gib-guard
```

- 33件中**4件はmainの祖先（ahead=0）**：`codex/automation-docs-20261123`、`codex/main-handoff-20261123`、`r4/upstream-refresh-20261002`、`research/rocm-qsa-gather-20261030`。再現用tagを作った後なら本体のrefを削除できる見込み。
- 残り**29件はmainからdivergeして独自コミットを持つ**。**タグ保存前に絶対に消さない**（歴史的実装・診断shader、ツール・設定等はmain未統合の可能性）。ahead数が多いbranchではupstreamからの大きなimportが混在するので、ahead数をすべて独自高速化コミットと解釈しない。
- Gemma 4のFA #31323 / Global FA関連の6本は**危険が未解明の実験状態としてread-only archive**。GPU timeoutの原因を断定しないが、Codexの通常無人ビルド・ベンチマーク用baseに選ばない。
- r5 MTP / r6 RGP / QSA / ROCmFPx / 旧r2・r3・r4、r6診断、旧テストbranchは研究結果として保存。下流の正本は [PATCHES](PATCHES.md)、[PERFORMANCE-RESEARCH-LOG](PERFORMANCE-RESEARCH-LOG.md)、[文書集約](DOCUMENTATION-RECONCILIATION-2026-11-23.md)、[r5/r6旧ブランチ監査](R5-R6-BRANCH-INVENTORY-AND-PRE-RELEASE-CHECKLIST-2026-10-29.md) を参照。

## 3. Codexから安全に実行するときの手順（まだ未実施）

> **追加ゲート：** 旧clone/worktreeの確認がアクセス権不足でできない場合はリモート削除を停止。安全な専用cloneからのGitHubリモート調査と、TAG ONLYは先行可能。r2は独立bundleで復元できるまで削除対象にしない。


1. **別の管理用clone/worktreeで実行**。EVO-X2で推論中のworktreeやCodexの起動中プロセスを変更しない。作業ツリーclean、`git remote -v`、`git status`、`git worktree list --porcelain`、`git ls-remote --heads origin`を保存する。remoteが本リポジトリのoriginであることを検証する。
2. 各allowlist branchのremote先端 **SHA40を取得してmanifest（branch/SHA/date/status）に固定**。照合後にbranchが進んだ場合は停止して再監査する。`main`と保持・保留リストに一致するbranchが紛れたら停止する。open PRやbranch protectionにも注意。
3. 最初の実行は**dry-runだけ**。タグ名`refs/tags/archive/2026-11-23/<branch>`がGit refとして妥当で、既存tagと衝突せず、取得対象commitがローカルに存在するか確認する。
4. 次の段階で**tag作成とpushだけを実行**。成功後、`git ls-remote --tags origin`でタグが存在し、**annotated tagはpeeled commit SHA**が元branchのSHAと一致することを確認。タグが既存で異なるコミットを指すなら上書きせず停止。
5. **削除は別段階・明示承認後**。タグを全件検証し、GitHubのbranch-basedリンクとworktree使用状況を確認してから、対象41件のうち個別に選択したrefだけ`git push --force-with-lease=refs/heads/<branch>:<expected_sha> origin :refs/heads/<branch>`で削除。エラー時は全処理を停止。広域`--prune`、`--mirror`、force pushは避ける。
6. 削除後は`git ls-remote --heads origin`で対象branchが消えたこと、対応する`refs/tags/archive/2026-11-23/...`が全件残ることを確認。manifestに実行commit、タグSHA、実行日時、成功/失敗、戻し方を記録してGitHubへpushする。
7. 戻す場合は、保存したタグが指すcommitから新しいbranchを作成できる。削除した元branch名で再作成する場合はCodexで使用中のworktreeとリンクに注意する。

旧来の安全な削除手順は [Invoke-R6StageBranchCleanup.ps1](../../tools/evox2/git/Invoke-R6StageBranchCleanup.ps1) を参照。ただし**このスクリプトは旧r6中間8枝限定であり、今回の41件に使えるものではない**。新しい安全なarchiveツールを作るなら、dry-run / tag phase / delete phaseの分離、SHA lease、branch明示allowlist、UTF-8 BOMのPowerShell 5.1互換性、log保存を必須にする。

## 4. 計画と実施を混同しないための状態

- **済み：** 53件のbranch inventory、mainとの比較、診断実装のmain未統合確認、r2の別系統由来確認、保持7／要確認13／アーカイブ候補33の暫定分類、open PR有無確認、過去のbranch運用文書の参照。
- **未実施：** 診断実装の完全なコード所在目録、r2独立Git bundle・復元確認、旧clone所有者によるworktree/未push状態の照合、GitHub tag作成、remote branch削除、EVO-X2ローカルworktree/未push変更の確認、branch URL完全監査、branch archiveスクリプト作成・実行、各branch先端SHAの固定manifest作成。
- **目的：** 保全確認を終えた33候補を対象とし、すべての安全ゲートを満たし削除承認・実行した後は53→20ブランチまで縮小可能（作業中に新しいbranchが増えていない前提）。さらに保留5件や旧baselineも後日整理できる。

新upstream b12651等を取り込むCodex作業は、**このアーカイブ作業をソースmergeやモデル実験と混同せず**、新しい`codex/`または`integration/`専用branchで開始する。

