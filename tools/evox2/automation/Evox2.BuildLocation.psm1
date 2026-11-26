#requires -Version 5.1
Set-StrictMode -Version Latest

function Assert-Evox2RegularPath {
    param([string]$Path, [switch]$File)
    $current = [IO.Path]::GetFullPath($Path)
    $leaf = $true
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            ($item.PSIsContainer -ne (!$leaf -or !$File))) {
            throw "Unexpected path type or reparse point: $current"
        }
        $leaf = $false
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Assert-Evox2DirectoryAccess {
    param([string]$Path, [uint32]$Access)
    if (!('Evox2DirectoryAccess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class Evox2DirectoryAccess
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(string path, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);
}
'@
    }
    # Open the existing directory itself. Windows evaluates effective ACL access without creating a probe file.
    $handle = [Evox2DirectoryAccess]::CreateFile($Path, $Access, 7, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
    try {
        if ($handle.IsInvalid) { throw "Required directory access denied: $Path (Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
    } finally { $handle.Dispose() }
}

function Read-Evox2LocationGit {
    param([string]$Repository, [string[]]$Arguments)
    $lines = @(& git.exe -C $Repository -c core.fsmonitor=false @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Git location check failed in $Repository" }
    $lines
}

function Get-Evox2BuildCheckout {
    param([string]$Repository)
    $head = Read-Evox2LocationGit $Repository @('rev-parse', 'HEAD')
    if ($head -notmatch '\A[0-9a-f]{40}\z') { throw 'Unexpected checkout SHA.' }
    $paths = @(Read-Evox2LocationGit $Repository @('status', '--porcelain', '--untracked-files=all'))
    [pscustomobject]@{ SourceCommit = $head; Clean = ($paths.Count -eq 0); ChangedPathCount = $paths.Count }
}

function Resolve-Evox2BuildLocation {
    [CmdletBinding()]
    param(
        [string]$Repository,
        [string]$BuildName,
        [switch]$Worktree,
        [string]$SourceCommit,
        [switch]$Preflight,
        [switch]$Offline
    )

    $automation = 'C:\llama-build\automation'
    $clone = Join-Path $automation 'llama.cpp-evox2-windows'
    $logs = 'C:\llama-build\_logs\codex'
    $cache = Join-Path $automation '_deps'
    $remote = 'git@github-evox2-windows:ariera-j/llama.cpp-evox2-windows.git'
    if ($BuildName -notmatch '\Abuild-[a-z0-9][a-z0-9_-]*\z') { throw 'Invalid build directory name.' }
    if ($Repository -match '(?:^|[\\/])\.\.?([\\/]|$)' -or $Repository -notmatch '\A[A-Za-z]:[\\/]') {
        throw 'The source directory must be an absolute path without dot segments.'
    }
    $repo = [IO.Path]::GetFullPath($Repository).TrimEnd('\')
    if ($Worktree) {
        if ($SourceCommit -notmatch '\A[0-9a-f]{40}\z') { throw '-Worktree requires -SourceCommit with the full approved SHA.' }
        if ((Split-Path -Parent $repo) -ine $automation -or (Split-Path -Leaf $repo) -notmatch '\Aw[0-9]{2,4}\z') {
            throw 'Use a short registered worktree directly under the automation directory (for example w54).'
        }
    } elseif ($repo -ine $clone -or $SourceCommit) {
        throw 'Use the EVO-X2 Codex clone, or explicitly approve this checkout with -Worktree and -SourceCommit.'
    }

    $override = @(Get-ChildItem Env: | Where-Object Name -match '^(GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|CONFIG|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\d+|CONFIG_VALUE_\d+)|GIT_NAMESPACE)$')
    if ($override.Count) { throw 'Git repository/configuration environment overrides are not supported.' }
    foreach ($path in $repo, $clone, (Join-Path $clone '.git'), $logs) { Assert-Evox2RegularPath $path }
    if ($Worktree) { Assert-Evox2RegularPath (Join-Path $repo '.git') -File }
    $common = [IO.Path]::GetFullPath((Read-Evox2LocationGit $repo @('rev-parse','--path-format=absolute','--git-common-dir')))
    if ($common -ine (Join-Path $clone '.git')) { throw 'Unexpected Git common directory.' }
    $gitDir = [IO.Path]::GetFullPath((Read-Evox2LocationGit $repo @('rev-parse','--absolute-git-dir')))
    Assert-Evox2RegularPath $gitDir
    if ($Worktree -and (Split-Path -Parent $gitDir) -ine (Join-Path $common 'worktrees')) { throw 'Unexpected Git worktree directory.' }
    $top = [IO.Path]::GetFullPath((Read-Evox2LocationGit $repo @('rev-parse','--show-toplevel')))
    if ($top -ine $repo -or (Read-Evox2LocationGit $repo @('config','--local','--get','remote.origin.url')) -cne $remote -or
        (Read-Evox2LocationGit $repo @('remote','get-url','origin')) -cne $remote) {
        throw 'Unexpected repository root or GitHub remote.'
    }
    if ($Worktree) {
        $registered = @(Read-Evox2LocationGit $clone @('worktree','list','--porcelain'))
        $registration = 'worktree ' + $repo.Replace('\','/')
        if ($registered -inotcontains $registration) { throw 'Worktree is not registered in the dedicated clone.' }
    }
    $checkout = Get-Evox2BuildCheckout $repo
    if ($Worktree -and $checkout.SourceCommit -ine $SourceCommit) { throw 'Worktree source SHA differs from the approved SHA.' }
    if (($Worktree -or !$Preflight) -and !$checkout.Clean) { throw 'Worktree is not clean.' }

    $destination = Join-Path $repo $BuildName
    # Directory enumeration also sees dangling links and detects collisions before any output is created.
    if (Get-ChildItem -LiteralPath $repo -Force -Filter $BuildName |
        Where-Object Name -ieq $BuildName | Select-Object -First 1) {
        throw "Build directory already exists: $destination"
    }
    foreach ($path in $cache, (Join-Path $cache 'fetchcontent'), (Join-Path $cache 'openmp')) {
        # Parent enumeration catches dangling reparse points as well as valid directories.
        $parent = Split-Path -Parent $path
        if ((Test-Path -LiteralPath $parent -PathType Container) -and
            (Get-ChildItem -LiteralPath $parent -Filter (Split-Path -Leaf $path) -Force |
                Where-Object Name -ieq (Split-Path -Leaf $path) | Select-Object -First 1)) {
            Assert-Evox2RegularPath $path
        }
    }
    if ($destination.Length -ge 260) { throw "The output path alone reaches the classic Windows MAX_PATH length: $destination" }
    Assert-Evox2DirectoryAccess $repo 4
    Assert-Evox2DirectoryAccess $logs 2
    if (!$Preflight -and !$Offline -and !(Test-Path -LiteralPath $cache -PathType Container)) {
        Assert-Evox2DirectoryAccess $automation 4
    }
    [pscustomobject]@{
        Repository = $repo; Destination = $destination; Cache = $cache; GitCommonDirectory = $common
        SourceCommit = $checkout.SourceCommit; Clean = $checkout.Clean; ChangedPathCount = $checkout.ChangedPathCount
        SourcePathLength = $repo.Length; BuildPathLength = $destination.Length; LinkedWorktree = $Worktree.IsPresent
    }
}

Export-ModuleMember -Function Assert-Evox2RegularPath, Get-Evox2BuildCheckout, Resolve-Evox2BuildLocation
