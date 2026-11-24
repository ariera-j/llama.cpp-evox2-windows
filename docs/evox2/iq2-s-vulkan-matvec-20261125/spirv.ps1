$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='C:\llama-build\automation\llama.cpp-evox2-windows'
$out='C:\llama-build\automation\iq2s-matvec-20261125'
$shader="$root\ggml\src\ggml-vulkan\vulkan-shaders"
$bin='C:\VulkanSDK\1.4.357.0\Bin'
Set-Location $out
function Confirm-Exit { if($LASTEXITCODE -ne 0){throw "SDK tool failed: $LASTEXITCODE"} }
& "$bin\glslc.exe" --version | Set-Content -Encoding UTF8 glslc-version.txt
$common=@('-c','-fshader-stage=compute','--target-env=vulkan1.2','-O',"-I$shader",'-DDATA_A_IQ2_S=1','-DFLOAT_TYPE=float','-DFLOAT_TYPEV2=vec2','-DB_TYPE=float','-DB_TYPEV2=vec2','-DB_TYPEV4=vec4','-DD_TYPE=float','-DUSE_SUBGROUP_ADD_NO_SHMEM=1')
$rows=foreach($route in 'indexed','ordinary'){
 $defs=@()
 if($route -eq 'indexed'){$defs+= '-DMUL_MAT_ID=1'}
 & "$bin\glslc.exe" @common @defs base-iq2-s.comp -o "$route-base.spv"
 Confirm-Exit
 & "$bin\glslc.exe" @common @defs "$shader\mul_mat_vec_iq2_s.comp" -o "$route-experiment.spv"
 Confirm-Exit
 foreach($columns in $(if($route -eq 'indexed'){1}else{1,3,8})){
  foreach($variant in 'Base','A1','A2','A1A2'){
   $mode=@{Base=0;A1=1;A2=2;A1A2=3}[$variant]
   $source=if($variant -eq 'Base'){"$route-base.spv"}else{"$route-experiment.spv"}
   $spec="0:64 1:4 2:$columns"
   if($variant -ne 'Base'){$spec+=" 3:$mode"}
   $name="$route-n$columns-$variant"
   & "$bin\spirv-opt.exe" --set-spec-const-default-value $spec --freeze-spec-const --fold-spec-const-op-composite -O --compact-ids $source -o "$name.spv"
   Confirm-Exit
   & "$bin\spirv-val.exe" --target-env vulkan1.2 "$name.spv"
   Confirm-Exit
   & "$bin\spirv-dis.exe" "$name.spv" -o "$name.spvasm"
   Confirm-Exit
   $asm=Get-Content "$name.spvasm"
   [pscustomobject]@{Route=$route;NumCols=$columns;Variant=$variant;Bytes=(Get-Item "$name.spv").Length;Sha256=(Get-FileHash "$name.spv").Hash;Fma=@($asm -match ' Fma ').Count;FNegate=@($asm -match ' OpFNegate ').Count;Select=@($asm -match ' OpSelect ').Count;Instructions=@($asm -match '^\s*(?:%\S+\s*=\s*)?Op\w+').Count}
  }
 }
}
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 spirv.csv
$rows | Format-Table Route,NumCols,Variant,Bytes,Fma,FNegate,Select,Instructions
