#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$tools = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$module = Import-Module (Join-Path $tools 'lib\Evox2.Common.psm1') -Force -PassThru
$temp = Join-Path ([IO.Path]::GetTempPath()) ('evox2-pmode-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    & $module {
        param($temp)
        function Assert-Test($passed, $label) {
            if (!$passed) { throw "Failed: $label" }
            Write-Host "PASS $label"
        }
        $script:probeTestPath = Join-Path $temp 'state.json'
        $script:probeTestMode = 'Direct'
        $script:probeTestRuns = 0
        function script:Get-Evox2PModeDirectMetadata {
            [pscustomobject]@{ ProbeSucceeded = $script:probeTestMode -eq 'Direct'; Transport = 'Direct'; Error = 'direct access denied'; OpenResult = 5; ExecuteResult = $null; CloseResult = $null; OutputSize = $null; Elevated = $false }
        }
        function script:New-Evox2PModeTaskService {
            $service = [pscustomobject]@{}
            $service | Add-Member ScriptMethod Connect {}
            $service | Add-Member ScriptMethod GetFolder {
                param($name)
                if ($name -ne '\Evox2') { throw 'Unexpected folder' }
                $folder = [pscustomobject]@{}
                $folder | Add-Member ScriptMethod GetTask {
                    param($name)
                    if ($name -ne 'PModeProbe') { throw 'Unexpected task' }
                    $task = [pscustomobject]@{}
                    $task | Add-Member ScriptMethod Run {
                        param($argument)
                        if ($null -ne $argument) { throw 'Unexpected run arguments' }
                        $script:probeTestRuns++
                        if ($script:probeTestMode -eq 'Denied') { throw 'Task execution access denied' }
                        if ($script:probeTestMode -eq 'NoWrite') { return }
                        $capture = [DateTimeOffset]::UtcNow
                        if ($script:probeTestMode -eq 'Stale') { $capture = $capture.AddDays(-1) }
                        $state = [ordered]@{
                            ProbeSucceeded = $script:probeTestMode -ne 'ProbeFailure'
                            Mode = 'Performance'; RawValue = 1; MethodId = 2; Elevated = $true
                            CapturedAt = $capture.ToString('o'); Error = 'fixture probe failure'; Source = 'IP3-WMI-method2'
                            InstanceName = 'fixture'; OpenResult = 0; ExecuteResult = 0; CloseResult = 0; OutputSize = 4
                        }
                        if ($script:probeTestMode -eq 'WrongMethod') { $state.MethodId = 1 }
                        if ($script:probeTestMode -eq 'WrongMode') { $state.Mode = 'Quiet' }
                        $state | ConvertTo-Json | Set-Content -LiteralPath $script:probeTestPath -Encoding UTF8
                    }
                    $task
                }
                $folder
            }
            $service
        }
        $p = $script:probeTestPath
        $result = Get-Evox2PModeMetadata -StatePath $p
        Assert-Test ($result.Transport -eq 'Direct' -and $script:probeTestRuns -eq 0) 'direct success bypasses COM'
        $script:probeTestMode = 'Fresh'
        $result = Get-Evox2PModeMetadata -DirectOnly -StatePath $p
        Assert-Test (!$result.ProbeSucceeded -and $script:probeTestRuns -eq 0) 'direct-only failure bypasses COM'
        $result = Get-Evox2PModeMetadata -StatePath $p
        Assert-Test ($result.ProbeSucceeded -and $result.Transport -eq 'ScheduledTask' -and
            $result.MethodId -eq 2 -and $result.Elevated -and $result.Mode -eq 'Performance' -and
            $result.RawValue -eq 1 -and $script:probeTestRuns -eq 1) 'fresh COM result with no run arguments'
        $conditions = Join-Path $temp 'conditions.json'
        $results = Join-Path $temp 'result.json'
        Write-Evox2Json -InputObject @{PModeAtStart=$result} -Path $conditions -Depth 24
        Write-Evox2Json -InputObject @{PModeAtStart=$result;PModeAtFinish=$result} -Path $results -Depth 32
        $c = Get-Content -LiteralPath $conditions -Raw | ConvertFrom-Json
        $r = Get-Content -LiteralPath $results -Raw | ConvertFrom-Json
        Assert-Test ($c.PModeAtStart.Transport -eq 'ScheduledTask' -and
            $r.PModeAtFinish.CapturedAt -eq $result.CapturedAt -and $r.PModeAtStart.RawValue -eq 1) 'benchmark JSON schema round trip'

        foreach ($case in @{
            NoWrite = 'Timed out'; Stale = 'capture timestamp'; WrongMethod = 'Method ID 2'
            WrongMode = 'invalid mode'; ProbeFailure = 'fixture probe failure'; Denied = 'access denied'
        }.GetEnumerator()) {
            $script:probeTestMode = $case.Key
            if ($case.Key -in 'Stale','WrongMethod','WrongMode','ProbeFailure') {
                Remove-Item -LiteralPath $p -ErrorAction SilentlyContinue
            }
            $result = Get-Evox2PModeMetadata -StatePath $p -TaskTimeoutMs 500
            Assert-Test (!$result.ProbeSucceeded -and $result.Mode -eq 'Unknown' -and
                $result.Transport -eq 'ScheduledTaskFallbackFailed' -and $result.Error -match $case.Value) $case.Key
        }
    } $temp

    foreach ($name in 'Measure-LlamaCli.ps1', 'Measure-LlamaBench.ps1') {
        $path = Join-Path $tools "benchmark\$name"
        $tokens = $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $calls = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-Evox2PModeMetadata'
        }, $true))
        $jsonWriters = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Evox2Json'
        }, $true))
        if ($errors.Count -or $calls.Count -ne 2 -or
            !($jsonWriters.Extent.Text -match '\$ConditionsPath') -or !($jsonWriters.Extent.Text -match '\$ResultPath') -or
            $ast.Extent.Text -notmatch 'PModeAtStart\s*=\s*\$PModeAtStart' -or
            $ast.Extent.Text -notmatch 'PModeAtFinish\s*=\s*\$PModeAtFinish') {
            throw "P-MODE integration check failed: $name"
        }
        Write-Host "PASS $name module calls and JSON fields"
    }
} finally {
    Remove-Module $module -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
