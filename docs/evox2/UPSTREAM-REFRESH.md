# Repeatable upstream refresh

Use Git's existing worktree and path-restore operations. A merge or a broad cherry-pick of the previous optimization branch is unnecessary. A custom branch-creation script is also unnecessary.

## What is carried forward

| Path | Treatment |
|---|---|
| `docs/evox2/` | Import the previous checkpoint; retain dated results as historical evidence. |
| `tools/evox2/` | Import build/measurement utilities and historical plans; use the generic clean plan for the new baseline. |
| `README.md` | Maintain the downstream overview and current-document links. |
| `.gitignore` | Keep the new upstream version; append the two Evo-X2 local-data entries. |
| `.github/workflows/` | Keep new upstream workflow content, with `.disabled` appended to active YAML filenames. |
| Upstream source, CMake and other docs/tools | Use the new upstream versions. Re-evaluate inference patches separately. |
| Upstream `AGENTS.md` and related instruction files | Retain them and read their actual scope; the 2026-10-09 version excludes downstream/fork work. |

The imported test fixtures and dated experiment plans do not make their corresponding native patches available. Do not run a historical patched-source plan against a clean refresh and count it as validation.

## Branch and import commands

Run in a preserved local checkout whose `origin` is this downstream repository. Change only the three inputs for the next cycle. Use a new, nonexistent worktree directory and branch name.

```powershell
$RefreshSourceBranch = 'r4/upstream-refresh-20261002'
$RefreshTargetBranch = 'r5/upstream-refresh-20261009'
$RefreshWorktree = 'C:\llama-build\llama.cpp-evox2-windows-r5'

git fetch origin $RefreshSourceBranch
if ($LASTEXITCODE -ne 0) { throw 'Source fetch failed.' }
$RefreshSourceSha = (git rev-parse FETCH_HEAD).Trim()

git fetch https://github.com/ggml-org/llama.cpp.git master
if ($LASTEXITCODE -ne 0) { throw 'Upstream fetch failed.' }
$RefreshUpstreamSha = (git rev-parse FETCH_HEAD).Trim()

git worktree add -b $RefreshTargetBranch $RefreshWorktree $RefreshUpstreamSha
if ($LASTEXITCODE -ne 0) { throw 'Worktree creation failed.' }

git -C $RefreshWorktree restore --source $RefreshSourceSha --staged --worktree -- docs/evox2 tools/evox2
if ($LASTEXITCODE -ne 0) { throw 'Documentation/tool import failed.' }
```

The two resolved SHAs are the record of what was actually selected. If working against a previously reviewed snapshot, fetch that exact SHA in place of `master`; do not assume it remains the latest upstream.

## Small housekeeping step

In the new worktree, keep the new upstream ignore file and append the following block if absent:

```text
# Evo-X2 local benchmark data and machine-local configuration
/evox2-logs/
/tools/evox2/benchmark/configs/local.psd1
```

Continue the existing downstream CI policy by renaming each tracked active workflow YAML to `<name>.disabled`. Preserve its contents rather than restoring the previous branch's entire `.github` tree.

```powershell
Get-ChildItem (Join-Path $RefreshWorktree '.github\workflows') -File |
    Where-Object { $_.Extension -in @('.yml', '.yaml') } |
    ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination ($_.FullName + '.disabled') }
```

Update `docs/evox2/CURRENT-REFRESH.json` with the new branch, selected upstream SHA and tooling-source SHA. Add a dated handoff with pending validation gates. Update the current status at the top of README, ROADMAP, BASELINE and PATCHES; leave dated historical results intact.

Keep `qwen38-clean.psd1`, `local.clean.example.psd1` and the explicit `build-*-clean` directories independent of the r-number. This avoids renaming the build scripts or changing historical plans each cycle.

## Verify, commit and publish

Stage only the carried paths and housekeeping. Confirm that the complete path list contains no unplanned changes; the source-only diff must be empty.

```powershell
git -C $RefreshWorktree add -- docs/evox2 tools/evox2 README.md .gitignore .github/workflows
git -C $RefreshWorktree diff --cached --check
git -C $RefreshWorktree diff --cached --name-status $RefreshUpstreamSha
git -C $RefreshWorktree diff --cached --exit-code $RefreshUpstreamSha -- src ggml common include cmake CMakeLists.txt tools/llama-bench tests
```

Check each native exit code before committing. Then commit the reviewed bootstrap and push only the new branch:

```powershell
git -C $RefreshWorktree commit -m "docs: bootstrap clean upstream refresh"
git -C $RefreshWorktree push -u origin $RefreshTargetBranch
```

A normal Git push also uploads the upstream history needed by this independent repository. GitHub's branch API alone cannot upload missing Git objects. Do not force-push or move the previous comparison branch.

## Local machine configuration

`local.psd1`, model files, input documents, logs and compiled binaries are not carried by Git. Copy the ignored config privately or start from `local.clean.example.psd1`, then correct binary paths and `LogRoot`. Reuse the external dependency cache while using fresh build directories.

Use the current build guides and generic clean plan. Build/version/device/backend and Original-model allocation/short gates precede long-context measurement.
