$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Set-ExecutionPolicy -Scope Process RemoteSigned -Force
$root='C:\llama-build\automation\llama.cpp-evox2-windows'
$log='C:\llama-build\_logs\codex\iq2s-matvec-20261125-a38ba149'
Set-Location $root
if((Get-Content "$log\validation-complete.txt" -Raw).Trim() -ne 'PASS'){throw 'IQ2_S validation gate'}
$cfg=Import-PowerShellDataFile 'tools\evox2\benchmark\configs\local.codex.psd1'
$model=Get-Item -LiteralPath $cfg.Models.UnslothPle16.Path
if($model.Length -ne 81961816672){throw 'Unexpected model size'}
Import-Module .\tools\evox2\lib\Evox2.Common.psm1 -Force
$vulkan= & 'C:\Windows\System32\vulkaninfo.exe'
$vulkan | Set-Content -Encoding UTF8 "$log\vulkaninfo.txt"
if(($vulkan -join ' ') -notmatch '103079215104' -or ($vulkan -join ' ') -notmatch '8060S'){throw 'Unexpected Vulkan device or UMA size'}
foreach($b in 'build-s2v','build-i2mv'){Copy-Item "$b\bin\Release\evox2-build.json" "$log\$b-manifest.json"}
function Get-PerformanceMode {
 $probe=Get-Evox2PModeMetadata
 if(-not $probe.ProbeSucceeded){$probe=Get-Evox2PModeMetadata}
 return $probe
}
function Measure-Variant($variant,$mode,$round,$sequence) {
 $build=if($variant -eq 'Base'){'build-s2v'}else{'build-i2mv'}
 $exe="$root\$build\bin\Release\llama-bench.exe"
 $stem="$log\run-$('{0:D2}' -f $sequence)-$variant-$mode"
 if((Test-Path "$stem.command.json") -or (Get-Process 'llama-bench','llama-cli','llama-server' -ErrorAction SilentlyContinue)){throw 'Run exists or conflicting process'}
 $names='GGML_VK_IQ2_S_MATVEC_A1','GGML_VK_IQ2_S_MATVEC_A2','GGML_VK_PERF_LOGGER','GGML_VK_PERF_LOGGER_CONCURRENT','GGML_VK_PERF_LOGGER_FREQUENCY'
 foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
 if($variant -in 'A1','A1A2'){$env:GGML_VK_IQ2_S_MATVEC_A1='1'}
 if($variant -in 'A2','A1A2'){$env:GGML_VK_IQ2_S_MATVEC_A2='1'}
 $tokens=if($mode -eq 'concurrent'){
  $env:GGML_VK_PERF_LOGGER='1'
  $env:GGML_VK_PERF_LOGGER_CONCURRENT='1'
  $env:GGML_VK_PERF_LOGGER_FREQUENCY='1000000'
  '32'
 } else {'256'}
 $argv=@('-m',('"'+$model.FullName+'"'),'-p','0','-n',$tokens,'-d','0','-r','1','--no-warmup','-b','2048','-ub','1024','-t','4','-ngl','999','-ncmoe','0','-dev','Vulkan0','-ctk','f16','-ctv','f16','-fa','on','--offline','-v','-o','json')
 $pMode=Get-PerformanceMode
 if($pMode.Mode -ne 'Performance'){throw "P-MODE before $sequence is $($pMode.Mode)"}
 $start=Get-Date
 $envFields=@{}
 foreach($name in $names){$envFields[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
 @{variant=$variant;mode=$mode;round=$round;sequence=$sequence;exe=$exe;args=$argv;environment=$envFields;pmodeBefore=$pMode;started=$start.ToString('o')} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 "$stem.command.json"
 "Run $sequence $variant $mode $($start.ToString('o'))"
 $p=Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory (Split-Path $exe) -RedirectStandardOutput "$stem.stdout.json" -RedirectStandardError "$stem.stderr.log" -PassThru -Wait
 $end=Get-Date
 if ($p.ExitCode -ne 0 -or (Select-String -Path "$stem.stderr.log" -Pattern 'VK_ERROR_DEVICE_LOST|VK_ERROR_OUT_OF_DEVICE_MEMORY|device lost|out of memory' -Quiet)) {
  @{exitCode=$p.ExitCode;ended=$end.ToString('o')} | ConvertTo-Json | Set-Content -Encoding UTF8 "$stem.result.json"
  throw "Benchmark failed: $stem"
 }
 $after=Get-PerformanceMode
 @{exitCode=$p.ExitCode;processSeconds=($end-$start).TotalSeconds;ended=$end.ToString('o');pmodeAfter=$after} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 "$stem.result.json"
 if($after.Mode -ne 'Performance'){throw "P-MODE after $sequence is $($after.Mode)"}
 if(-not (Select-String -Path "$stem.stderr.log" -Pattern 'offloaded 49/49 layers' -Quiet)){throw 'Full offload not confirmed'}
 if($mode -eq 'concurrent' -and -not (Select-String -Path "$stem.stderr.log" -Pattern '^Vulkan Timings:' -Quiet)){throw 'Missing logger timings'}
 $result=@(Get-Content "$stem.stdout.json" -Raw | ConvertFrom-Json)
 if($result.Count -ne 1 -or $result[0].n_gen -ne [int]$tokens -or $result[0].n_prompt -ne 0){throw 'Unexpected benchmark output'}
 "Run $sequence $variant $mode exit=0, $($result[0].avg_ts) tok/s"
}
$order=@('Base','A1','A1A2','A2','A1','A2','Base','A1A2','A2','A1A2','A1','Base')
for($i=0;$i -lt $order.Count;$i++){Measure-Variant $order[$i] 'off' ([int][Math]::Floor($i / 4)+1) ($i+1)}
$order=@('Base','A2','A1','A1A2')
for($i=0;$i -lt $order.Count;$i++){Measure-Variant $order[$i] 'concurrent' 0 ($i+13)}
