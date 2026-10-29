#requires -Version 5.1
<#
.SYNOPSIS
  Safely remove only the eight redundant r6 intermediate remote branch refs.
.DESCRIPTION
  Dry-run by default. Compares each remote tip to a frozen SHA and proves that
  the tip is an ancestor of origin/r6/combined-20261028 before deletion.
  Uses a per-ref force-with-lease to reject concurrent changes. Does NOT
  remove local branches, worktrees, tags, r5 research refs, upstream controls,
  the combined candidate, README, or the GitHub default branch.
  Review branch-based GitHub documentation links before -Execute.
.EXAMPLE
  .\tools\evox2\git\Invoke-R6StageBranchCleanup.ps1
.EXAMPLE
  .\tools\evox2\git\Invoke-R6StageBranchCleanup.ps1 -Execute
#>
[CmdletBinding()]
param(
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (& git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$repo)) {
    throw 'Must run inside the llama.cpp-evox2-windows Git repository.'
}

$remoteUrl = [string](& git remote get-url origin)
if ($LASTEXITCODE -ne 0 -or
    $remoteUrl -notmatch '(?i)github\.com[:/]ariera-j/llama\.cpp-evox2-windows(?:\.git)?/?$') {
    throw "Unexpected origin: $remoteUrl"
}

# The only remote refs this script may remove. Frozen at 2026-10-29 JST.
$stageBranches = [ordered]@{
    'r6/common001-ple16-20261025'       = '39920946753e14b0e9bc43eba00e186441370ba3'
    'r6/rocmfpx-vulkan-20261025'        = '739af71c117f463236bf33d1624a9438f945ccf2'
    'r6/mtp-compat-20261025'            = 'db27fcbaefa35e411bc9979f9fe0f6bdbae9bcab'
    'r6/vulkan-qsa-union-20261025'      = '96b49ec8e3f92def0c68377191f326d25323b7c1'
    'r6/mtp-dense-20261026'             = '8665c0c3b5ce26e7346818826de24677c77ba570'
    'r6/mtp-noop-20261026'              = '02e44a240a975bbb3de689425ebf3185edded057'
    'r6/mtp-stageb-20261027'            = '48fe00a0036867d94b2ae0721413a603100484d4'
    'r6/mtp-eh-proj-flatten-20261027'   = '606227d3dc17481783207ca6dcd276be95dfc160'
}

Write-Host "Repository: $repo"
Write-Host "Mode: $(if ($Execute) { 'EXECUTE remote deletion' } else { 'DRY RUN only' })"
Write-Host "Protected refs: main, r5/upstream-refresh-20261009, r6/upstream-refresh-20261025, r6/combined-20261028"

& git fetch --no-tags origin
if ($LASTEXITCODE -ne 0) { throw 'git fetch failed; no deletion attempted.' }

$combined = [string](& git rev-parse 'refs/remotes/origin/r6/combined-20261028')
if ($LASTEXITCODE -ne 0 -or $combined -notmatch '^[0-9a-f]{40}$') {
    throw 'Cannot resolve origin/r6/combined-20261028.'
}
Write-Host "Combined tip: $combined"

$worktrees = @(& git worktree list --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not check local worktrees.' }
$checkedOut = @($worktrees | Where-Object { $_ -match '^branch refs/heads/' })

$toDelete = @()
foreach ($entry in $stageBranches.GetEnumerator()) {
    $branch = [string]$entry.Key
    $expected = [string]$entry.Value
    $ref = "refs/heads/$branch"

    $remoteLine = @(& git ls-remote --heads origin $ref)
    if ($LASTEXITCODE -ne 0) { throw "ls-remote failed for $branch" }
    if ($remoteLine.Count -eq 0) {
        Write-Host "[ALREADY ABSENT] $branch"
        continue
    }
    if ($remoteLine.Count -ne 1) {
        throw "Unexpected remote ref count for $branch"
    }
    $matched = [regex]::Match([string]$remoteLine[0], '^([0-9a-fA-F]{40})\s+refs/heads/')
    if (-not $matched.Success) {
        throw "Unexpected remote ref response for $branch"
    }

    $actual = $matched.Groups[1].Value.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "REMOTE MOVED: $branch expected=$expected actual=$actual. No deletion; re-audit."
    }
    if ($checkedOut -contains "branch $ref") {
        throw "BRANCH IN WORKTREE: $branch. Preserve local worktree; no deletion."
    }

    & git merge-base --is-ancestor $expected $combined
    if ($LASTEXITCODE -ne 0) {
        throw "NOT AN ANCESTOR of combined: $branch ($expected). No deletion."
    }

    Write-Host "[VERIFIED MERGED] $branch $expected"
    $toDelete += [pscustomobject]@{ Branch = $branch; Ref = $ref; Sha = $expected }
}

if (-not $Execute) {
    Write-Host "Dry run complete; $($toDelete.Count) removable remote refs verified."
    Write-Host 'No remote refs changed. Review historical GitHub branch URLs before -Execute.'
    return
}

foreach ($item in $toDelete) {
    # An exact SHA lease protects against deleting any branch someone updated
    # between the fetch/check and the push.
    $lease = "--force-with-lease=$($item.Ref):$($item.Sha)"
    $deleteSpec = ":$($item.Ref)"
    & git push $lease origin $deleteSpec
    if ($LASTEXITCODE -ne 0) {
        throw "Deletion rejected for $($item.Branch). STOP; inspect remote and do not force."
    }
    Write-Host "[REMOTE REF DELETED] $($item.Branch)"
}

Write-Host "Finished: $($toDelete.Count) remote r6 intermediate refs deleted. Local refs/worktrees and all other branches untouched."
Write-Host 'Run git fetch origin; review git branch -r. Do not prune local worktrees automatically.'
