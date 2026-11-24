$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='C:\llama-build\automation\llama.cpp-evox2-windows'
$out='C:\llama-build\automation\iq2s-matvec-20261125'
$log='C:\llama-build\_logs\codex\iq2s-matvec-20261125-a38ba149'
if(Test-Path $log){throw 'Validation log already exists'}
New-Item -ItemType Directory -Path $log | Out-Null
$originalPath=$env:PATH
foreach($variant in 'Base','A1','A2','A1A2'){
 $build=if($variant -eq 'Base'){'build-s2v'}else{'build-i2mv'}
 $bin="$root\$build\bin\Release"
 $manifest=Get-Content "$bin\evox2-build.json" -Raw | ConvertFrom-Json
 $commit=if($variant -eq 'Base'){'eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1'}else{'a38ba149d11d6a7067e6c323523f95c7889b167b'}
 if($manifest.BuildIdentity.Status -ne 'Verified' -or $manifest.Source.Commit -ne $commit){throw "Unexpected build identity: $variant"}
 foreach($name in 'llama-bench.exe','ggml-vulkan.dll'){
  $actual=(Get-FileHash -Algorithm SHA256 "$bin\$name").Hash
  if($actual -ne ($manifest.Artifacts | Where-Object Name -eq $name).Sha256){throw "Hash mismatch: $build $name"}
 }
 $env:PATH="$bin;$originalPath"
 $env:GGML_VK_IQ2_S_MATVEC_A1=$null
 $env:GGML_VK_IQ2_S_MATVEC_A2=$null
 if($variant -in 'A1','A1A2'){$env:GGML_VK_IQ2_S_MATVEC_A1='1'}
 if($variant -in 'A2','A1A2'){$env:GGML_VK_IQ2_S_MATVEC_A2='1'}
 $env:GGML_VK_PIPELINE_STATS='iq2_s_f32'
 $p=Start-Process -FilePath "$out\validate-iq2-s.exe" -WorkingDirectory $bin -ArgumentList ('"'+$bin+'\ggml-vulkan.dll"') -Wait -PassThru -RedirectStandardOutput "$log\validate-$variant.csv" -RedirectStandardError "$log\validate-$variant.stderr.txt"
 "$variant exit=$($p.ExitCode)"
 Get-Content "$log\validate-$variant.csv"
 if($p.ExitCode -ne 0){
  Get-Content "$log\validate-$variant.stderr.txt" -Tail 25
  throw 'IQ2_S numerical validation failed'
 }
}
'PASS' | Set-Content -Encoding ASCII "$log\validation-complete.txt"
