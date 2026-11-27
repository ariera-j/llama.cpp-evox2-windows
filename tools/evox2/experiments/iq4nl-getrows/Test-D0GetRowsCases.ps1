#requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'D0GetRows.Cases.psm1') -Force

$bin = 'C:\llama-build\automation\w55\build-rh\bin\Release'
$hip = "ggml_cuda_init: Device 0: AMD Radeon(TM) 8060S Graphics, gfx1151`r`n" +
    'load_backend: loaded ROCm backend from ' + (Join-Path $bin 'ggml-hip.dll')
$rocm = Get-D0GetRowsPlan RocmSupport
$cpu = Get-D0GetRowsPlan CpuSupport
$numeric = Get-D0GetRowsPlan RocmNumerical
$hostDenied = 'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=host,padded=0): NOT SUPPORTED'
$hostPaddedDenied = 'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=host,padded=1): NOT SUPPORTED'
$deviceAccepted = 'GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=device,padded=0): SUPPORTED'
$supportLines = @(
    $deviceAccepted
    $hostDenied
    $hostPaddedDenied
    'GET_ROWS(type=iq4_nl,d0_4d_width=256,buffer=device,padded=0): SUPPORTED'
    'GET_ROWS(type=iq4_nl,d0_4d_width=256,buffer=host,padded=0): SUPPORTED'
    'Backend ROCm0: OK'
)
$esc = [string][char]27
$supportLines[1] = '  ' + $hostDenied.Replace('NOT SUPPORTED', "${esc}[31mNOT SUPPORTED${esc}[0m")
$cpuLines = @('GET_ROWS(type=iq4_nl,d0_4d_width=160,buffer=cpu,padded=0): SUPPORTED','Backend CPU: OK')
$numericLines = @(
    'GET_ROWS(type=iq4_nl,d0_1_width=32,padded=0): OK'
    'GET_ROWS(type=iq4_nl,d0_1_width=160,padded=0): OK'
    'GET_ROWS(type=iq4_nl,d0_1_width=160,padded=1): OK'
    'GET_ROWS(type=iq4_nl,d0_1_width=256,padded=0): OK'
    'GET_ROWS(type=iq4_nl,d0_1_width=288,padded=0): OK'
    '5/5 tests passed'
    'Backend ROCm0: OK'
)
$fixtures = @(
    @{ Tag='rocm-support'; Plan=$rocm; Lines=$supportLines; Err=$hip; Expected=$true },
    @{ Tag='cpu-support'; Plan=$cpu; Lines=$cpuLines; Err=''; Expected=$true },
    @{ Tag='rocm-numerical'; Plan=$numeric; Lines=$numericLines; Err=$hip; Expected=$true },
    @{ Tag='unexpected-positive'; Plan=$rocm; Lines=@($supportLines[0],$hostDenied.Replace('NOT SUPPORTED','SUPPORTED')) + $supportLines[2..5]; Err=$hip; Expected=$false },
    @{ Tag='duplicate-case'; Plan=$rocm; Lines=@($supportLines[0],$supportLines[0]) + $supportLines[2..5]; Err=$hip; Expected=$false },
    @{ Tag='unexpected-case'; Plan=$rocm; Lines=$supportLines + @('FLASH_ATTN_EXT(unexpected): SUPPORTED'); Err=$hip; Expected=$false },
    @{ Tag='missing-case'; Plan=$rocm; Lines=$supportLines[1..5]; Err=$hip; Expected=$false },
    @{ Tag='unexpected-negative'; Plan=$rocm; Lines=@($deviceAccepted.Replace('SUPPORTED','NOT SUPPORTED')) + $supportLines[1..5]; Err=$hip; Expected=$false },
    @{ Tag='wrong-backend'; Plan=$cpu; Lines=@($cpuLines[0],'Backend ROCm0: OK'); Err=''; Expected=$false },
    @{ Tag='false-summary'; Plan=$numeric; Lines=$numericLines[0..4] + @('4/5 tests passed','Backend ROCm0: OK'); Err=$hip; Expected=$false },
    @{ Tag='unexpected-runtime'; Plan=$rocm; Lines=$supportLines; Err=$hip.Replace('gfx1151','gfx1150'); Expected=$false },
    @{ Tag='hip-error'; Plan=$rocm; Lines=$supportLines; Err=$hip + "`r`nROCm error: unspecified launch failure"; Expected=$false }
)
$results = @(
    foreach ($fixture in $fixtures) {
        $actual = Test-D0GetRowsOutput $fixture.Plan $fixture.Lines $fixture.Err $bin
        [pscustomobject]@{Case=$fixture.Tag; Expected=$fixture.Expected; Actual=$actual; Passed=($actual -eq $fixture.Expected)}
    }
    [pscustomobject]@{Case='live-allows-intended-negative'; Expected=$false; Actual=(Test-D0GetRowsFailureLog $rocm @($supportLines[1]) ''); Passed=!(Test-D0GetRowsFailureLog $rocm @($supportLines[1]) '')}
    [pscustomobject]@{Case='live-rejects-unknown-negative'; Expected=$true; Actual=(Test-D0GetRowsFailureLog $numeric @($hostDenied) ''); Passed=(Test-D0GetRowsFailureLog $numeric @($hostDenied) '')}
)
$results | Format-Table -AutoSize
if (@($results | Where-Object { !$_.Passed }).Count) { throw 'Dummy output checks failed.' }
