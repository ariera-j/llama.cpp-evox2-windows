#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsRoot = Split-Path -Parent $scriptDir
$commonModule = Join-Path $toolsRoot 'lib\Evox2.Common.psm1'

Import-Module $commonModule -Force

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Get-Evox2PModeStatePath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $OutputPath
if ($outputDir) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result = Get-Evox2PModeMetadata -DirectOnly

$tempPath = "$OutputPath.$PID.tmp"
Write-Evox2Json -InputObject $result -Path $tempPath -Depth 8
Move-Item -LiteralPath $tempPath -Destination $OutputPath -Force

if (-not $result.ProbeSucceeded) {
    Write-Error "P-MODE probe failed: $($result.Error)"
    exit 2
}

Write-Output ("P-MODE: {0} (raw={1})" -f $result.Mode, $result.RawValue)
exit 0
