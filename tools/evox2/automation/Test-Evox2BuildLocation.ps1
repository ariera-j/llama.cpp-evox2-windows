#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$env:GIT_OPTIONAL_LOCKS = '0'
Import-Module (Join-Path $PSScriptRoot 'Evox2.BuildLocation.psm1')
$automation = 'C:\llama-build\automation'
$clone = Join-Path $automation 'llama.cpp-evox2-windows'
$fixture, $separate, $junction = 'w531', 'w532', 'w533' | ForEach-Object { Join-Path $automation $_ }
foreach ($path in $fixture, $separate, $junction) {
    if (Test-Path -LiteralPath $path) { throw "Choose unused worktree test destinations: $path" }
}

function Assert-Rejected([string]$Message, [scriptblock]$Action) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Message) { throw }
        return
    }
    throw "Expected rejection matching $Message"
}

$head = & git.exe -C $clone rev-parse HEAD
if ($LASTEXITCODE) { throw 'Cannot identify dedicated clone.' }
$default = Resolve-Evox2BuildLocation -Repository $clone -BuildName build-t53 -Preflight -Offline
if ($default.LinkedWorktree -or $default.SourceCommit -ne $head) { throw 'Wrong default clone.' }

$createdFixture = $false
$createdSeparate = $false
$createdJunction = $false
try {
    & git.exe -C $clone worktree add --quiet --detach $fixture $head
    if ($LASTEXITCODE) { throw 'Unable to create detached fixture.' }
    $createdFixture = $true
    $options = @{ Repository = $fixture; BuildName = 'build-t53'; Worktree = $true; SourceCommit = $head; Preflight = $true; Offline = $true }
    $location = Resolve-Evox2BuildLocation @options
    if (!$location.LinkedWorktree -or !$location.Clean -or $location.SourcePathLength -ne $fixture.Length -or
        $location.BuildPathLength -ne (Join-Path $fixture 'build-t53').Length -or (Test-Path -LiteralPath $location.Destination)) {
        throw 'Approved preflight unexpectedly changed or misidentified the fixture.'
    }
    Assert-Rejected 'explicitly approve' { Resolve-Evox2BuildLocation -Repository $fixture -BuildName build-t53 -Preflight }
    $bad = $options.Clone()
    $bad.Remove('SourceCommit')
    Assert-Rejected 'full approved SHA' { Resolve-Evox2BuildLocation @bad }
    $bad = $options.Clone()
    $bad.SourceCommit = '0' * 40
    Assert-Rejected 'differs from the approved SHA' { Resolve-Evox2BuildLocation @bad }
    Assert-Rejected 'directly under' {
        Resolve-Evox2BuildLocation -Repository 'C:\llama-build\_logs\codex\w531' -BuildName build-t53 -Worktree -SourceCommit $head
    }
    Assert-Rejected 'dot segments' {
        Resolve-Evox2BuildLocation -Repository "$automation\w532\..\w531" -BuildName build-t53 -Worktree -SourceCommit $head
    }
    $bad = $options.Clone()
    $bad.BuildName = '..\build-t53'
    Assert-Rejected 'Invalid build directory name' { Resolve-Evox2BuildLocation @bad }
    $dirty = Join-Path $fixture 'evox2-worktree-test.txt'
    [IO.File]::WriteAllText($dirty, 'temporary worktree fixture')
    try { Assert-Rejected 'not clean' { Resolve-Evox2BuildLocation @options } }
    finally { [IO.File]::Delete($dirty) }
    $null = [IO.Directory]::CreateDirectory($location.Destination)
    try { Assert-Rejected 'already exists' { Resolve-Evox2BuildLocation @options } }
    finally { [IO.Directory]::Delete($location.Destination) }

    & git.exe init --quiet $separate
    if ($LASTEXITCODE) { throw 'Unable to create separate repository fixture.' }
    $createdSeparate = $true
    $bad = $options.Clone()
    $bad.Repository = $separate
    Assert-Rejected 'path type|Git common directory' { Resolve-Evox2BuildLocation @bad }

    $null = New-Item -ItemType Junction -Path $junction -Target 'C:\llama-build\_logs\codex'
    $createdJunction = $true
    $bad.Repository = $junction
    Assert-Rejected 'reparse point' { Resolve-Evox2BuildLocation @bad }
    $stillClean = Get-Evox2BuildCheckout $fixture
    if (!$stillClean.Clean -or $stillClean.SourceCommit -ne $head) { throw 'Fixture changed.' }
} finally {
    if ($createdJunction) { [IO.Directory]::Delete($junction) }
    if ($createdSeparate) { Remove-Item -LiteralPath $separate -Recurse -Force }
    if ($createdFixture) {
        & git.exe -C $clone worktree remove $fixture
        if ($LASTEXITCODE) { throw 'Fixture cleanup failed.' }
    }
}
'Build location tests passed.'
