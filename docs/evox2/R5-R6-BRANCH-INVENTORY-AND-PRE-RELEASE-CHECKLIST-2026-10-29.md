# r5/r6 branch inventory and pre-release consolidation plan — 2026-10-29

> **Status:** inventory verified against the GitHub branches API; **33 remote branches**. This is **non-destructive cleanup stage 1**: branch roles, SHA and retirement criteria have been frozen in docs; **no branch delete, rename, new tag, default-branch switch or README rewrite has occurred**. Subsequent tag/main/README work is explicitly reserved for a later request. Remote tips are dated observations and may advance as plans are committed.

## 1. Canonical references and preservation policy

- **Current downstream integration/publication candidate:** `r6/combined-20261028`; at inventory time `d6c4a580d40f1bbafac86974ed1cf0329a9d5595` (docs HEAD). Actual **measured b11908 Vulkan/ROCm executable source:** `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`; a docs commit is **not** a newly measured executable.
- **Pinned upstream control:** `r6/upstream-refresh-20261025` (S0 built b11875, upstream source b11870); preserve. **r5 pinned control:** `r5/upstream-refresh-20261009`; preserve for benchmark comparability.
- **Current GitHub default branch:** `main` at `bddf73442c24545879c9acadc078ba5b2c3cb7d8`, identical in SHA to `r4/upstream-refresh-20261002`. **Do not move `main` until the agreed later step.**
- All eight r6 intermediate branches are documented *historical stage checkpoints*. Their source/commit and test evidence is valuable to rollback and patch attribution. Do not presume they are ancestors of the combined candidate without a `git merge-base` check.
- The 14 r5 isolated investigation/integration-check branches are not presumed merged into combined; preserve until their unique commits, branch-anchored documentation links, and retained binaries/measurements have been reviewed. **Branch renaming or deleting can break GitHub /blob/<branch>/ URLs**.
- No destructive cleanup before the release tag, and no forced branch updates. A later deletion requires: immutable archival ref/tag if necessary; ancestry/unique-commit assessment; backlink audit; local `git worktree list`; and explicit selected branch names. Avoid blanket `git push --prune`.

## 2. Exact remote-branch inventory

### Current publication path / keep (2)

| Branch | Remote tip SHA (2026-10-29) |
| --- | --- |
| `main` | `bddf73442c24545879c9acadc078ba5b2c3cb7d8` |
| `r6/combined-20261028` | `d6c4a580d40f1bbafac86974ed1cf0329a9d5595` |

### Reproducible baselines / keep (2)

| Branch | Remote tip SHA (2026-10-29) |
| --- | --- |
| `r5/upstream-refresh-20261009` | `25004972199c68a0678c2341c155dc84a98e5da8` |
| `r6/upstream-refresh-20261025` | `9b5ff9a5aef57ae0c36d0d2cf1d89747911ae7c3` |

### R6 intermediate stage checkpoints / keep until immutable release tag + ancestry/link audit (8)

| Branch | Remote tip SHA (2026-10-29) |
| --- | --- |
| `r6/common001-ple16-20261025` | `39920946753e14b0e9bc43eba00e186441370ba3` |
| `r6/mtp-compat-20261025` | `db27fcbaefa35e411bc9979f9fe0f6bdbae9bcab` |
| `r6/mtp-dense-20261026` | `8665c0c3b5ce26e7346818826de24677c77ba570` |
| `r6/mtp-eh-proj-flatten-20261027` | `606227d3dc17481783207ca6dcd276be95dfc160` |
| `r6/mtp-noop-20261026` | `02e44a240a975bbb3de689425ebf3185edded057` |
| `r6/mtp-stageb-20261027` | `48fe00a0036867d94b2ae0721413a603100484d4` |
| `r6/rocmfpx-vulkan-20261025` | `739af71c117f463236bf33d1624a9438f945ccf2` |
| `r6/vulkan-qsa-union-20261025` | `96b49ec8e3f92def0c68377191f326d25323b7c1` |

### R5 isolated implementation and integration-check branches / historical review before deletion (14)

| Branch | Remote tip SHA (2026-10-29) |
| --- | --- |
| `integration-check/r5-noop-rocmfpx-20261021` | `9d4721fb8e2d3bbaeb863370ae79e01621f7351c` |
| `integration-check/r5-noop-rocmfpx-stageb-flatten-20261021` | `c9d81a311277fed13800b5f3f5c4ea0f499d1e95` |
| `investigation/r5-adlx-gpu-monitor-20261015` | `1b94f19fd331a2b5885d00313d27558fdf63deef` |
| `investigation/r5-mtp-dense-compat-20261011` | `5492421d898ceb8a86d7594e26f5086d0371dd2d` |
| `investigation/r5-mtp-dense-indexer-20261011` | `0dc8672d8b9b8c81e167bc566a9d80aadfb90307` |
| `investigation/r5-mtp-draft-kv-parity-20261019` | `9040443ce8e41a094ab84811105c59789d425938` |
| `investigation/r5-mtp-eh-proj-flatten-20261016` | `22e4b1f09ce35509ad2d1da0d613546676e69435` |
| `investigation/r5-mtp-noop-20261012` | `80dd44ed90e8e199786c8c436bbb9a084bde4aa5` |
| `investigation/r5-mtp-pp-kv-crop-stage1-20261014` | `df74d2f221d651ce3916973819f92d37fff94ab3` |
| `investigation/r5-mtp-pp-target-rewarmup-30511-20261016` | `8a7f56c96630939f6ec01942182134f7b27684e7` |
| `investigation/r5-mtp-pp-trace-20261013` | `61c9c5ee8db1aa4f0609458234d9bddaa0151239` |
| `investigation/r5-mtp-rollback-diagnostic-20261019` | `33175c2bdfafc82a7ce91d2a68f982ab8bd33353` |
| `investigation/r5-rocmfpx-vulkan-20261020` | `ceb558b2acb0be388863f6d8c4c15e92193f5c0c` |
| `investigation/r5-vulkan-off-fa-dispatch-20261010` | `65ed1285c3d6429b4d63c75fba7a87d7f627ac50` |

### Older research/misc / out of this cleanup scope (7)

| Branch | Remote tip SHA (2026-10-29) |
| --- | --- |
| `investigation/rocm-qsa-argsort-topk-20261022` | `16c983edaf5d53666a8a3680df198fb5f920e0c6` |
| `investigation/rocm-qsa-topk-baseline-20261022` | `264b839235837cac296c8ce0a8ea14cc62d566f8` |
| `r2/legacy` | `23c316fb5af67da74e614af4a7453fba9ae46189` |
| `r3/upstream-first` | `0a93fcbb8e5bcf51b331275c4f4b142d822168d6` |
| `r4/upstream-refresh-20261002` | `bddf73442c24545879c9acadc078ba5b2c3cb7d8` |
| `test/mtp-qsa-prototype` | `dbf1ec0f869f271e86d770aa24f0a5c992e38e47` |
| `test/qwen35-vulkan-2gib-guard` | `b686a49c3c77f2d061cdfc729ba9d94092fea3df` |


## 3. Safe order: now vs next session

**Now (stage 1, docs-first):** (1) keep current b11908 source and rollback binaries frozen; (2) record the measured 21-run gap fill + ROCm all-five CLI-only smoke and source-vs-docs HEAD distinction; (3) synchronize release/index/ROADMAP/PATCHES current-state pointers; (4) inventory and classify branches; (5) collect untracked local R6 S9 plan scripts in Git **without overwriting or reconstructing their private local contents**.

**After user-requested release preparation (stage 2):** (1) confirm the five local plans are committed/pushed and verify there are no raw private paths/data; (2) make explicit go/no-go for candidate release scope, including G9-5 router-mode **deferred by user**, numerical Draft K/V parity **DEFER**, no global all-ON, no general Gemma4 vision/long-answer quality assertion; (3) review/check in README for fork-vs-upstream attribution; (4) finalize release manifest and tag an exact docs+source commit after that content is complete; (5) **then** switch GitHub default branch from `main` to the validated integration lineage as requested; (6) archive/delete only specifically reviewed obsolete remote stage refs. If the user chooses to tag before README, record that changed order deliberately.

**Future research branch:** start ROCm long-context PP/TG investigation on a *new isolated branch from frozen combined source*, leaving `r6/combined-20261028` and its measured binary untouched; see [measured priority](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md). Do not mix the next experimental kernel with the release snapshot.

## 4. Five untracked local S9 plans: source is on the Windows worktree, not on GitHub

User reported on `C:\llama-build\llama.cpp-evox2-windows-r6`, branch `r6/combined-20261028`, clean tracked files and precisely these **untracked** paths:

| Relative path | Evidence / purpose |
| --- | --- |
| `tools/evox2/benchmark/configs/qwen38-r6-s9-gapfill-overnight-20261029.psd1` | 21-run consecutive speed matrix |
| `tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-a-minimal.psd1` | S9 MH-128K A candidate |
| `tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-huihui-only.psd1` | S9 MH-128K B huihui |
| `tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-iq4-only.psd1` | S9 MH-128K B original IQ4 |
| `tools/evox2/benchmark/configs/qwen38-r6-s9-rocm-all5-on-manual-64k-20261029.psd1` | manual ROCm 64k/all-five flag compatibility smoke |

Their **actual local contents are not accessible through the GitHub API** because these are untracked Windows files; do not invent them or claim they have been committed. The three MH scripts were referenced by S9 runbook before being committed. Ensure no machine-specific secrets, private absolute paths or input text are embedded; prefer `local.psd1` keys and repo-relative references.

After fetching the docs commit and reviewing the actual PSD1 files locally, the Windows-side exact staging sequence is:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
git status --short --branch
git pull --ff-only origin r6/combined-20261028
$plans = @(
  'tools/evox2/benchmark/configs/qwen38-r6-s9-gapfill-overnight-20261029.psd1'
  'tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-a-minimal.psd1'
  'tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-huihui-only.psd1'
  'tools/evox2/benchmark/configs/qwen38-r6-s9-mh128k-seed20261026-b-iq4-only.psd1'
  'tools/evox2/benchmark/configs/qwen38-r6-s9-rocm-all5-on-manual-64k-20261029.psd1'
)
foreach ($p in $plans) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing plan: $p" } }
# Review the files for locally specific absolute paths, secrets and raw private input.
git add -- $plans
git diff --cached --check
git diff --cached --stat
git commit -m 'test(evox2): archive S9 gap-fill and MH-128K plans'
git push origin r6/combined-20261028
git status --short --branch
```

**Important:** the docs commit will advance the remote ref past the user's previously clean local checkout, so **pull --ff-only before committing**; these five untracked plan files are not touched by that fast-forward. Do **not** use `git clean -fd`, `git reset --hard`, `git add -A` or `git push --force` to tidy the tree.

## 5. Deferred release/operational gates

- G8-0–G8-6 / S9 Qwen original IQ4, huihui and Gemma4 text-only gates: complete within recorded bounded scopes.
- G9-5 actual `llama-server` **router-mode** / llama.cpp WebUI / Open WebUI model switching: **deferred at user request** to a later hands-on check. ROCm MTP-ON server is still separately unvalidated.
- Stage-B/flatten numerical Draft K/V parity **DEFER**; runtime all-five on ROCm 64k **CLI stability only**, never silently approve as production defaults.
- b10919 Gemma4 fallback binaries and original verified Vulkan/ROCm b11908 binary+DLL manifests: preserve. Do not tag a claimed universal stable server/vision package without additional bounded evidence. A *clearly scoped candidate/source checkpoint* can be tagged later with limitations prominently documented.

## Sources

- [Completed combined S8 integration](R6-S8-COMBINED-RESULTS-2026-10-28.md)
- [S9 model verification](R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md)
- [Gap-fill measured matrix and ROCm-next priority](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md)
- [Supported flag profiles](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md)
- [Original integration policy](INTEGRATION-POLICY.md)
