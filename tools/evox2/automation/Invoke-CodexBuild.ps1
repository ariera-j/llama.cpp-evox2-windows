#requires -Version 5.1
[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Mandatory)][ValidateSet('Vulkan', 'ROCm')][string]$Backend,
    [Parameter(Mandatory)][ValidatePattern('\Abuild-[A-Za-z0-9][A-Za-z0-9_-]*\z')][string]$BuildDir,
    [Parameter(ParameterSetName = 'Preflight')][switch]$PreflightOnly,
    [Parameter(ParameterSetName = 'Configure')][switch]$ConfigureOnly,
    [ValidateNotNullOrEmpty()][string]$VulkanLlvmBin,
    [ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')][string]$ExpectedVulkanClangVersion,
    [ValidateSet('ON', 'OFF')][string]$CpuAllVariants = 'ON',
    [switch]$Offline,
    [switch]$Worktree,
    [ValidatePattern('\A[0-9a-f]{40}\z')][string]$SourceCommit
)

$ErrorActionPreference = 'Stop'
if ($Backend -ne 'Vulkan' -and $PSBoundParameters.ContainsKey('CpuAllVariants')) { throw '-CpuAllVariants requires -Backend Vulkan.' }
if ([bool]$VulkanLlvmBin -ne [bool]$ExpectedVulkanClangVersion) {
    throw 'Specify both -VulkanLlvmBin and -ExpectedVulkanClangVersion.'
}
if ($Backend -ne 'Vulkan' -and $VulkanLlvmBin) { throw 'Vulkan Clang options require -Backend Vulkan.' }
if ($VulkanLlvmBin) {
    if (![IO.Path]::IsPathRooted($VulkanLlvmBin)) { throw 'Specify an absolute Vulkan LLVM path.' }
    $VulkanLlvmBin = (Resolve-Path -LiteralPath $VulkanLlvmBin).ProviderPath
} else {
    $VulkanLlvmBin = 'C:\Program Files\LLVM\bin'
    $ExpectedVulkanClangVersion = '20.1.8'
}
$ProgressPreference = 'SilentlyContinue'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$mode = $PSCmdlet.ParameterSetName
Import-Module (Join-Path $PSScriptRoot 'Evox2.BuildLocation.psm1')
Assert-Evox2RegularPath 'C:\llama-build\_logs\codex'

$logRoot = 'C:\llama-build\_logs\codex'
$stem = Join-Path $logRoot ("build-$Backend-$mode-" + [guid]::NewGuid().ToString('N'))
$result = [ordered]@{
    Command = @($PSCommandPath, '-Backend', $Backend, '-BuildDir', $BuildDir)
    Stdout = "$stem.stdout.log"
    Stderr = "$stem.stderr.log"
    ExitCode = 1
    ElapsedSeconds = $null
}
if ($Backend -eq 'Vulkan') { $result.Command += @('-VulkanLlvmBin', $VulkanLlvmBin, '-ExpectedVulkanClangVersion', $ExpectedVulkanClangVersion, '-CpuAllVariants', $CpuAllVariants) }
if ($mode -ne 'Build') { $result.Command += "-$($mode)Only" }
if ($Offline) { $result.Command += '-Offline' }
if ($Worktree) { $result.Command += @('-Worktree', '-SourceCommit', $SourceCommit) }
if (!(Test-Path -LiteralPath $logRoot -PathType Container)) { throw "Missing log directory: $logRoot" }

# Run the phases in one child PowerShell with separate native output streams.
Import-Module (Join-Path $PSScriptRoot 'Evox2.BuildState.psm1')
$workerPath = Join-Path $PSScriptRoot 'Invoke-CodexBuildWorker.ps1'
$quoted = @($workerPath, $repo, $Backend, $BuildDir, $mode, $VulkanLlvmBin, $ExpectedVulkanClangVersion,
    $CpuAllVariants, $Offline.IsPresent.ToString(), $Worktree.IsPresent.ToString(), [string]$SourceCommit, $stem) |
    ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
$payload = 'try { & ' + ($quoted -join ' ') + '; exit 0 } catch { [Console]::Error.WriteLine($_.ToString()); exit 1 }'
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
$conditions = [ordered]@{
    Backend = $Backend; Repository = $repo; BuildDirectory = Join-Path $repo $BuildDir
    Mode = $mode; Offline = $Offline.IsPresent; Worktree = $Worktree.IsPresent; RequestedSourceCommit = $SourceCommit
    CpuAllVariants = $CpuAllVariants; VulkanClangVersion = $ExpectedVulkanClangVersion
}
$options = @{
    Program = "$PSHOME\powershell.exe"
    Arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'RemoteSigned', '-EncodedCommand', $encoded)
    Stem = $stem; Result = $result; Conditions = $conditions
}
try {
    Invoke-Evox2TrackedBuildProcess @options
    if ($result.ExitCode -ne 0) { throw "Codex build failed. See $($result.Stderr) and $($result.Stdout)" }
} finally {
    Write-Host "Result: $stem.result.json"
    Write-Host "State: $stem.state.json"
}
