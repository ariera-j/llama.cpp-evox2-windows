#requires -Version 5.1
Set-StrictMode -Version 3

function Get-D0GetRowsPlan {
    param([Parameter(Mandatory)][ValidateSet('RocmSupport','CpuSupport','RocmNumerical')][string]$Case)

    $backend = 'ROCm0'
    $summary = $null
    switch ($Case) {
        'RocmSupport' {
            $native = 'support -b ROCm0 -o GET_ROWS -p "^type=iq4_nl,d0_4d_width=(160,buffer=(device,padded=0|host,padded=[01])|256,buffer=(device|host),padded=0)$"'
            $expected = @(
                'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=device,padded=0): SUPPORTED'
                'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=host,padded=0): NOT SUPPORTED'
                'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=host,padded=1): NOT SUPPORTED'
                'GET_ROWS(type=iq4_nl,d0_4d_width=256,buffer=device,padded=0): SUPPORTED'
                'GET_ROWS(type=iq4_nl,d0_4d_width=256,buffer=host,padded=0): SUPPORTED'
            )
        }
        'CpuSupport' {
            $backend = 'CPU'
            $native = 'support -b CPU -o GET_ROWS -p "^type=iq4_nl,d0_4d_width=160,buffer=cpu,padded=0$"'
            $expected = @('GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=cpu,padded=0): SUPPORTED')
        }
        'RocmNumerical' {
            $native = 'test -b ROCm0 -j 1 -o GET_ROWS -p "^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$"'
            $expected = @(foreach ($shape in '32,0','160,0','160,1','256,0','288,0') {
                $width,$padded = $shape.Split(',')
                "GET_ROWS(type=iq4_nl,d0_1_width=$width,padded=$padded)`: OK"
            })
            $summary = '5/5 tests passed'
        }
    }
    [pscustomobject]@{
        Case=$Case; Backend=$backend; NativeArguments=$native; Expected=$expected; Summary=$summary
        ExpectedUnsupported=@($expected | Where-Object { $_ -clike '*: NOT SUPPORTED' })
    }
}

function ConvertTo-D0GetRowsLines {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        ($line -replace ([string][char]27 + '\[[0-9;]*m'), '').Trim()
    }
}

function Test-D0GetRowsFailureLog {
    param($Plan, [string[]]$Stdout, [string]$Stderr)
    $fail = '(?i)\b(?:HIP|ROCm|CUDA|GPU|device) (?:error|lost)|hipError\w+|launch (?:failure|failed)|\b(?:FAILED|FAIL|NaN|Inf)\b|not supported|skipping large tensors'
    $relevant = @(ConvertTo-D0GetRowsLines $Stdout | Where-Object { $Plan.ExpectedUnsupported -cnotcontains $_ })
    ($relevant -join "`n") -match $fail -or $Stderr -match $fail
}

function Test-D0GetRowsOutput {
    param($Plan, [string[]]$Stdout, [string]$Stderr, [string]$BuildBin)
    if (Test-D0GetRowsFailureLog $Plan $Stdout $Stderr) { return $false }
    $lines = @(ConvertTo-D0GetRowsLines $Stdout)
    $actual = @($lines | Where-Object { $_ -cmatch '^[A-Z][A-Z0-9_]*\(' })
    if ($actual.Count -ne $Plan.Expected.Count -or @(Compare-Object $Plan.Expected $actual -CaseSensitive).Count) { return $false }
    $backends = @($lines | Where-Object { $_ -cmatch '^Backend [^:]+: (?:OK|FAIL)$' })
    if ($backends.Count -ne 1 -or $backends[0] -cne "Backend $($Plan.Backend)`: OK") { return $false }
    $summaries = @($lines | Where-Object { $_ -cmatch '^\d+/\d+ tests passed$' })
    if ($Plan.Summary) {
        if ($summaries.Count -ne 1 -or $summaries[0] -cne $Plan.Summary) { return $false }
    } elseif ($summaries.Count) {
        return $false
    }
    if ($Plan.Backend -eq 'ROCm0') {
        $hipLoad = 'load_backend: loaded ROCm backend from ' + (Join-Path $BuildBin 'ggml-hip.dll')
        if (($Stderr -split '\r?\n') -inotcontains $hipLoad -or $Stderr -notmatch 'Device 0: AMD Radeon.*8060S.*gfx1151') { return $false }
    }
    return $true
}

Export-ModuleMember -Function Get-D0GetRowsPlan,Test-D0GetRowsFailureLog,Test-D0GetRowsOutput
