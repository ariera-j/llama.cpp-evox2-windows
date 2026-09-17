#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BinaryDirectory,
    [ValidateSet('Quick', 'Full')][string]$Suite = 'Quick',
    [string]$LogDirectory = (Join-Path (Get-Location).Path 'evox2-r2-tests')
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) { $PSNativeCommandUseErrorActionPreference = $false }
$TestExe = (Resolve-Path -LiteralPath (Join-Path $BinaryDirectory 'test-backend-ops.exe')).Path
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$Filter = if ($Suite -eq 'Quick') { 'kv=1024,.*qsa_top_k=17,' } else { 'qsa_top_k=[1-9]' }
$ExpectedTests = if ($Suite -eq 'Quick') { 23 } else { 31 }
$Names = @('GGML_VK_QSA_UNION', 'GGML_VK_QSA_UNION_MIN_KV', 'GGML_VK_QSA_UNION_STATS',
    'GGML_VK_QSA_GATHER_GROUPS', 'GGML_VK_PERF_LOGGER')
$Saved = @{}
foreach ($Name in $Names) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process') }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
try {
    [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION_MIN_KV', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION_STATS', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GGML_VK_QSA_GATHER_GROUPS', $null, 'Process')
    [Environment]::SetEnvironmentVariable('GGML_VK_PERF_LOGGER', $null, 'Process')
    foreach ($Mode in @('0', '1')) {
        [Environment]::SetEnvironmentVariable('GGML_VK_QSA_UNION', $Mode, 'Process')
        $Log = Join-Path $LogDirectory "$Stamp-$Suite-union-$Mode.log"
        Push-Location (Split-Path -Parent $TestExe)
        try {
            $ErrorActionPreference = 'Continue'
            & $TestExe test -b Vulkan0 -o FLASH_ATTN_EXT -p $Filter 2>&1 | Tee-Object -FilePath $Log
            $Code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = 'Stop'
            Pop-Location
        }
        if ($Code -ne 0) { throw "Backend tests failed with union=$Mode (exit $Code). Send $Log before running the model." }
        $Text = Get-Content -LiteralPath $Log -Raw
        if ($Text -notmatch 'Vulkan0' -or $Text -notmatch 'FLASH_ATTN_EXT') { throw "No Vulkan Attention tests were found in $Log" }
        if ($Text -notmatch "(?m)^\s*$ExpectedTests/$ExpectedTests tests passed\s*$") {
            throw "Expected $ExpectedTests passing cases. Tests may have been skipped; send $Log before benchmarking."
        }
        if ($Mode -eq '1' -and $Text -notmatch 'qsa-union active[^\r\n]*\bmin_kv=1\b') {
            throw "The new path did not run with min_kv=1. Send $Log before benchmarking."
        }
    }
} finally {
    foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name], 'Process') }
}
Write-Host "OFF and ON checks passed. Logs: $LogDirectory"
