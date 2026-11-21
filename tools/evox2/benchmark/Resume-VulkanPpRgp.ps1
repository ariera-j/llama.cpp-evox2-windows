#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Prefix,
    [ValidateRange(1, 1800)]
    [int]$WaitSeconds = 600,

    # Reject old .ready files from previous profiling sessions.
    [ValidateRange(15, 3600)]
    [int]$MaxReadyAgeSeconds = 300
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

# Guard against the common mistake of using the previous test's Prefix.
# If another, newer .ready exists in the same folder, fail closed.
function Assert-Evox2ReadyTarget {
    param([string]$Stage)

    $selected = Get-Item -LiteralPath $readyFile -ErrorAction Stop
    $age = ([DateTime]::UtcNow - $selected.LastWriteTimeUtc).TotalSeconds
    if ($age -gt $MaxReadyAgeSeconds) {
        throw (("$Stage : stale ready file (age {0:N0}s): {1}. " +
            "Use the -Prefix shown in the CURRENT llama-cli pause log. " +
            "The desired file must be <prefix>.ready, not a prior test's marker.") -f $age, $readyFile)
    }

    $readyDir = Split-Path -Parent $readyFile
    $newer = @(Get-ChildItem -LiteralPath $readyDir -Filter '*.ready' -File |
        Where-Object {
            $_.FullName -ne $selected.FullName -and
            $_.LastWriteTimeUtc -gt $selected.LastWriteTimeUtc.AddSeconds(2)
        } | Sort-Object LastWriteTimeUtc -Descending)
    if ($newer.Count -gt 0) {
        $newerPrefix = $newer[0].FullName.Substring(0, $newer[0].FullName.Length - '.ready'.Length)
        throw "$Stage : another NEWER ready file exists: $($newer[0].FullName). Check the current pause log and rerun with -Prefix '$newerPrefix'. No .go file was written."
    }
}

Assert-Evox2ReadyTarget -Stage 'Before arming'
Write-Host ""
Write-Host "Selected READY file: $readyFile" -ForegroundColor Green
Write-Host ("READY modified at: {0}" -f (Get-Item -LiteralPath $readyFile).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
Write-Host "Corresponding GO file (must match): $goFile" -ForegroundColor Yellow
Write-Host (Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8)
Write-Host 'The target Vulkan PP graph is paused. In Radeon Developer Panel:' -ForegroundColor Yellow
Write-Host '  1. Select this llama-cli application as the profiling capture target.'
Write-Host '  2. Choose manual Dispatch capture, Render op count 16 (small initial trace).'
Write-Host '     Disable Collect counters / instruction tracing; disable client timeout in RDP.'
Write-Host '  3. Click Capture profile in RDP to ARM the next dispatch capture.'
Write-Host '  4. IMMEDIATELY return to this window and press ENTER to release the PP graph.'
Write-Host '  5. Do NOT wait for the RGP trace to finish BEFORE releasing the graph.'
Write-Host '     Without further dispatches, a pending capture can remain waiting until gate TIMEOUT.'
Write-Host ''
$null = Read-Host 'Press ENTER now, after clicking Capture profile (do not wait for .rgp)'

# Recheck after user confirmation: wrong/stale prefix must NEVER write .go.
Assert-Evox2ReadyTarget -Stage 'Before release'
[IO.File]::WriteAllText($goFile, "go`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Go-file written: $goFile" -ForegroundColor Green
Write-Host 'Check llama-cli stderr for RESUMED (not TIMEOUT) and confirm the .rgp file is created.'
