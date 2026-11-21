#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,
    [ValidateRange(1, 1800)]
    [int]$WaitSeconds = 600
)

$ErrorActionPreference = 'Stop'

# The PP diagnostic writes a .ready marker and waits for .go.
# Run this helper in a SECOND PowerShell session while llama-cli is running.
$readyFile = "$Prefix.ready"
$goFile = "$Prefix.go"

Write-Host "Waiting for PP graph pause: $readyFile" -ForegroundColor Cyan
$watch = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath $readyFile -PathType Leaf)) {
    if ($watch.Elapsed.TotalSeconds -ge $WaitSeconds) {
        throw "Timed out waiting for ready file: $readyFile"
    }
    Start-Sleep -Milliseconds 250
}

Write-Host ""
Write-Host (Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8)
Write-Host 'The target Vulkan PP graph is paused. In Radeon Developer Panel:' -ForegroundColor Yellow
Write-Host '  1. Select this llama-cli application as the profiling capture target.'
Write-Host '  2. Choose manual Dispatch capture, Render op count 16 (small initial trace).'
Write-Host '     Disable Collect counters / instruction tracing; disable client timeout in RDP.'
Write-Host '  3. Click Capture profile to arm capture at the next dispatch.'
Write-Host '  4. Return here and press ENTER to allow the graph to execute.'
Write-Host ''
$null = Read-Host 'Press ENTER after arming RDP dispatch capture'

# Only write this after the user explicitly confirms capture is armed.
[IO.File]::WriteAllText($goFile, "go`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Resumed: $goFile" -ForegroundColor Green
