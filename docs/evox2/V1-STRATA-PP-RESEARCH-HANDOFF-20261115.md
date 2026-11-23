# Strata PP research: upstream v1.0.0 base and EVO-X2 r6 tooling handoff (2026-11-15)

> **2026-11-23状況追補:** 本書は11/15に準備した**setup専用ブランチの引き継ぎ手順**であり、このsetupブランチ自体がupstream v1.0.0実装へ変わったわけではない。ユーザーは別途upstream v1.0.0 / r6 / Strata v0.2.13の実機比較を実施済み。これをもってここに書かれた将来の全移植候補が実装・検証されたとは扱わない。現在はCodex接続の推論ゲート／ドキュメント・ブランチ整理を優先。[現行ステータス](DOCUMENTATION-RECONCILIATION-2026-11-23.md)。

**Status: PREPARATION BRANCH ONLY - the inference source in `setup/strata-pp-v1-docs-tools-20261115` is NOT upstream v1.0.0. Do not use this setup branch as a v1.0.0 benchmark base.**

## Goal and exact provenance

- Final **research branch** to create in this repository: `investigation/strata-pp-v1.0.0-20261115`.
- Source **must be** upstream [llama.cpp v1.0.0](https://github.com/ggml-org/llama.cpp/releases/tag/v1.0.0), commit `b1b770d90d94cad9e9ea5b993bdbc383a522fb28`, Git tree `03d5ee6748f415d4069dc570764c24ff3576a0f1`; this is identical to the previously benchmarked clean ROCm **build 12359**.
- **Only** copy the **complete directory trees** `docs/evox2/` and `tools/evox2/` from `r6/combined-20261028`, at remote source commit `e9deff8ebcd87d6685a73f0cb7adbb9a16462d67`. This setup branch already holds exact original r6 tree snapshots `c80daf7f73f3b504aba9af2d56d6a336da361c59` and `675d499af5609edd5abde8270ab516a454e2efaf`, respectively, **plus this new handoff document**. Do not port `ggml/`, `src/`, `common/`, other inference modifications, build outputs, the PLE16 model loader or r6's COMMON-005 as part of initial creation.
- Hardware/experiment: EVO-X2 Windows HIP RDNA3.5 gfx1151, **UMA 64 GiB**, original 3-shard Unsloth Qwen3.8 Flash Next IQ3_XXS GGUF, native KV initially f16, no PLE16 conversion required. After later changing UMA to **96 GiB** and needing Ple16-converted models, evaluate/port **COMMON-001 PLE16 separately**, with loader/quality validation.
- Strata source audit and ablations live in [external experiment repository](https://github.com/ariera-j/evox2-llm-experiments/blob/main/engines/strata/STRATA_V0213_VS_LLAMA_R6_PP_SOURCE_COMPARISON_20261115.md). Initial proposed kernel work: MoE gate/up+GLU/Down fused route, shape-specific GEMM/hipBLASLt and QSA WMMA candidates - one gated feature per test. Never treat former r6 docs as automatically applicable to newer upstream source.

## Why this is a separate setup branch

GitHub reports `ariera-j/llama.cpp-evox2-windows` as **not a network fork**. The GitHub connector cannot create a branch from the upstream v1.0.0 commit because that commit object does not yet exist in this independent repository (Git API returns HTTP 422). GitHub's create-tree API also cannot use the upstream tree SHA. Reconstructing upstream v1.0.0 by copy/pasting its large diff from the older r6 source would not preserve the required upstream commit ancestry and risks introducing source differences.

**Do not falsely rename `r6/upstream-refresh-20261025` as v1.0.0.** The setup branch was made from `r6/upstream-refresh-20261025` solely to stage full r6 tool/doc directory trees for an exact `git restore` on top of actual upstream v1.0.0.

## Finalization: execute on EVO-X2 (fresh working directory strongly preferred)

PowerShell, with Git installed and the user's normal GitHub push credentials. Choose a new folder to avoid touching the running r6 tree:

```powershell
$ErrorActionPreference = 'Stop'
$repo = 'C:\llama-build\llama.cpp-evox2-v1-strata-pp'
git clone https://github.com/ariera-j/llama.cpp-evox2-windows.git $repo
if ($LASTEXITCODE -ne 0) { throw 'Clone failed' }
Set-Location $repo

$prep = 'setup/strata-pp-v1-docs-tools-20261115'
$target = 'investigation/strata-pp-v1.0.0-20261115'
$upstreamCommit = 'b1b770d90d94cad9e9ea5b993bdbc383a522fb28'

git fetch origin "refs/heads/${prep}:refs/remotes/origin/${prep}"
if ($LASTEXITCODE -ne 0) { throw 'Setup branch fetch failed' }
git fetch --no-tags https://github.com/ggml-org/llama.cpp.git refs/tags/v1.0.0
if ($LASTEXITCODE -ne 0) { throw 'Upstream fetch failed' }

$resolved = (git rev-parse 'FETCH_HEAD^{commit}').Trim()
if ($resolved -ne $upstreamCommit) { throw "Wrong upstream commit: $resolved" }
if (-not [string]::IsNullOrWhiteSpace((git status --porcelain))) { throw 'Unclean working tree' }
git show-ref --verify --quiet "refs/heads/$target"
if ($LASTEXITCODE -eq 0) { throw "Local branch already exists: $target" }

git switch -c $target $upstreamCommit
if ($LASTEXITCODE -ne 0) { throw 'Cannot switch to upstream commit' }
git restore --source="refs/remotes/origin/$prep" --staged --worktree -- docs/evox2 tools/evox2
if ($LASTEXITCODE -ne 0) { throw 'Docs/tools restore failed' }

$changed = @(git diff --cached --name-only)
if ($changed.Count -eq 0) { throw 'Nothing staged' }
$bad = @($changed | Where-Object { $_ -notmatch '^(docs|tools)/evox2/' })
if ($bad.Count -gt 0) { throw "Unexpected staged source changes: $($bad -join ', ')" }
git status --short
git log -1 --format='%H %s'
git diff --cached --stat

# The user reviews the staged files and supplies their own commit message:
git commit
if ($LASTEXITCODE -ne 0) { throw 'Commit failed' }
git push -u origin $target
if ($LASTEXITCODE -ne 0) { throw 'Push failed' }
```

The user's upstream `AGENTS.md` prohibits AI-authored commit messages for upstream submissions, so the script uses interactive `git commit` rather than writing a message automatically. This is a separate research fork branch, not an upstream PR.

**Final verification:** the final branch's first-parent base must be upstream `b1b770d90...`, and `git diff --name-status b1b770d90...HEAD` should list only `docs/evox2/` and `tools/evox2/`. `git diff b1b770d90 HEAD -- ggml src common` must be empty. The final branch must be distinctly named; setup branch remains only to preserve the staged directory snapshots.

## Testing plan after finalization

1. ROCm build with original 3-shard IQ3; capture `llama-cli --version` and model-file hashes; run 64K frozen code and a 128K smoke with baseline settings from the 2026-11-14 clean v1 experiment. Check tool-script compatibility; these were carried unchanged from r6 and are **not yet validated** on v1.
2. Record clean-v1 64K PP/TG/quality baseline and a working-memory/ADLX trace at UMA64. Compare only against clean v1 numbers first; r6+COMMON-005 is a *separate reference*, not part of this branch.
3. Source audit and one-feature-at-a-time MoE/GEMM/QSA experiment flags; smoke, real 64/128K, correctness and MH-Hard when applicable.
4. Future UMA96 milestone: re-evaluate COMMON-001 split-PLE16 loader and other required r6 patches separately, never silently incorporate them at branch creation.
