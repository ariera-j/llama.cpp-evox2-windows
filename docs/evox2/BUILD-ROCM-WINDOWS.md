# Windows ROCm 10.0 build

## Scope

This procedure builds the clean r4 ROCm baseline on the Evo-X2 using the ROCm 10.0 / TheRock Python distribution.

Baseline source:

```text
pinned upstream: bed0a856606ee4a24a164066f73d2379447033f5
branch: r4/upstream-refresh-20261002
```

GPU target:

```text
gfx1151
```

The procedure is carried forward from the validated r3 toolchain. The r4 build
and runtime checks have not yet been executed on the Evo-X2.

## Previously tested toolchain (r3)

```text
Windows 11
Visual Studio 2022 Build Tools
MSVC 14.44.35207
ROCm 10.0.0 / TheRock
ROCm LLVM/Clang 23.0.0
CMake 4.3.1
Ninja 1.13.2
```

### Why VS2022 is used

A ROCm 10.0 build attempted with the newer VS18 / MSVC 14.51 host headers failed during HIP compilation with `<cmath>` overload conflicts involving functions such as:

```text
isgreater
isgreaterequal
isless
islessequal
islessgreater
isunordered
```

Using the VS2022 / MSVC 14.44 host environment allowed the same ROCm 10.0 source to build successfully.

This is recorded as an observed compatibility result for this machine and toolchain, not as a general claim about every Clang/MSVC combination.

## Build wrapper (recommended for the existing environment)

Open the VS2022 x64 Native Tools PowerShell shell and activate the existing
TheRock environment. Do not recreate a working venv just for r4.

```powershell
& C:\TheRock\build\.venv\Scripts\Activate.ps1
.\tools\evox2\build\Build-ROCm.ps1 -Parallel 4 -RunBackendTest
```

The default directory is `build-rocm-r4`. Use a fresh directory for the first
r4 build. The wrapper configures and builds HIP/tools, copies runtime DLLs,
runs identity/device smoke checks and the requested FLASH_ATTN_EXT test, and
writes `evox2-build.json`. Model loading is a separate check.

## Create the ROCm environment (only if not already installed)

Open **x64 Native Tools Command Prompt for VS 2022**, then start PowerShell.

Create the venv:

```powershell
New-Item -Path 'C:\TheRock\build' -ItemType Directory -Force | Out-Null

python -m venv C:\TheRock\build\.venv
& C:\TheRock\build\.venv\Scripts\Activate.ps1

python -m pip install --upgrade pip
```

Install ROCm 10.0 including the device package for `gfx1151`:

```powershell
python -m pip install `
  --index-url https://stable.repo.amd.com/rocm/whl-next/ `
  "rocm[libraries,devel,device-gfx1151]==10.0.0"
```

Initialize and validate the SDK prefix:

```powershell
rocm-sdk init
rocm-sdk test
```

## Configure the shell

```powershell
$RocmPath  = (rocm-sdk path --root).Trim()
$CmakePath = (rocm-sdk path --cmake).Trim()
$BinPath   = (rocm-sdk path --bin).Trim()
$RocmLlvmBin = "$RocmPath\lib\llvm\bin"

$env:HIP_PATH            = $RocmPath
$env:ROCM_PATH           = $RocmPath
$env:CMAKE_PREFIX_PATH   = $CmakePath
$env:HIP_DEVICE_LIB_PATH = "$RocmPath\lib\llvm\amdgcn\bitcode"
$env:HIP_PLATFORM        = 'amd'
$env:LLVM_PATH           = "$RocmPath\lib\llvm"

$env:PATH = "$RocmLlvmBin;$BinPath;C:\TheRock\build\.venv\Scripts;$env:PATH"
```

Verify the important pieces:

```powershell
$env:VCToolsInstallDir
where.exe cl
where.exe clang
rocm-sdk version
clang --version
where.exe rocm-sdk
Test-Path $env:HIP_DEVICE_LIB_PATH
```

Expected host toolchain for the tested baseline:

```text
MSVC 14.44.x
```

Expected ROCm compiler:

```text
Clang 23.0.0
```

## Configure llama.cpp

From the repository root:

```powershell
cmake -S . -B .\build-rocm-r4 -G "Ninja Multi-Config" `
  "-DCMAKE_PREFIX_PATH=$RocmPath" `
  -DGGML_BACKEND_DL=ON `
  -DGGML_NATIVE=OFF `
  -DGGML_HIP=ON `
  "-DCMAKE_C_COMPILER=$RocmPath\lib\llvm\bin\clang.exe" `
  "-DCMAKE_CXX_COMPILER=$RocmPath\lib\llvm\bin\clang++.exe" `
  "-DCMAKE_C_FLAGS=-Wno-error=incompatible-pointer-types" `
  "-DCMAKE_HIP_COMPILER=$RocmPath\lib\llvm\bin\clang.exe" `
  "-DHIP_PATH=$RocmPath" `
  -DAMDGPU_TARGETS=gfx1151 `
  -DLLAMA_BUILD_BORINGSSL=ON `
  -DLLAMA_BUILD_EXAMPLES=OFF `
  -DLLAMA_BUILD_TESTS=ON `
  -DLLAMA_BUILD_TOOLS=ON `
  -DLLAMA_BUILD_SERVER=ON `
  -DLLAMA_BUILD_UI=OFF `
  -DGGML_RPC=ON
```

Notes:

- `AMDGPU_TARGETS` produces a deprecation warning in this configuration, but it was kept for the b11247 baseline because it matches the b11247 Windows ROCm release workflow style used during bring-up.
- `CMAKE_HIP_COMPILER` may be reported as manually specified but unused. It is also retained in the baseline command for reproducibility.
- These warnings are not build failures.

## Build the HIP backend first

```powershell
cmake --build .\build-rocm-r4 `
  --config Release `
  --parallel 4 `
  --target ggml-hip
```

Historical r3 build output ended with (r4 step counts may differ):

```text
[155/155] Linking CXX shared module bin\Release\ggml-hip.dll
```

## Build the user-facing tools

```powershell
cmake --build .\build-rocm-r4 `
  --config Release `
  --parallel 4 `
  --target llama-cli llama-server llama-bench test-backend-ops
```

Expected binary directory:

```text
build-rocm-r4\bin\Release
```

## Copy the ROCm runtime DLLs beside the executables

This step is required for the tested Windows setup.

Without it, the GPU was detected but memory reporting was wrong:

```text
ROCm0: AMD Radeon(TM) 8060S Graphics (0 MiB, 0 MiB free)
```

Copy the ROCm 10.0 runtime DLLs:

```powershell
$Bin = Join-Path $PWD 'build-rocm-r4\bin\Release'
$RocmBin = (rocm-sdk path --bin).Trim()

@(
    'amdhip64_7.dll',
    'rocm_kpack.dll',
    'amd_comgr.dll'
) | ForEach-Object {
    Copy-Item (Join-Path $RocmBin $_) $Bin -Force
}
```

After the copy:

```powershell
& "$Bin\llama-cli.exe" --list-devices
```

Historical r3 result (verify again for r4):

```text
Available devices:
  ROCm0: AMD Radeon(TM) 8060S Graphics (110456 MiB, 110301 MiB free)
```

## rocBLAS/Tensile data for gfx1151

Installing only:

```text
rocm[libraries,devel]
```

was sufficient to compile, but not sufficient for real model inference on this GPU.

The first model run failed because rocBLAS could not find the Tensile data for `gfx1151`.

The working environment includes:

```text
device-gfx1151
```

After installation and `rocm-sdk init`, the rocBLAS data is placed under an architecture-specific directory such as:

```text
...\bin\rocblas\library\gfx1151\
```

A top-level `TensileLibrary.dat` is not required by the current per-architecture layout.

## Backend test

```powershell
& "$Bin\test-backend-ops.exe" test -b ROCm0 -o FLASH_ATTN_EXT
```

Historical r3 result (verify again for r4):

```text
3982/3982 tests passed
Backend ROCm0: OK
```

## Model smoke test

Example:

```powershell
$Model = 'C:\path\to\Qwen3.8-Flash-Next-UD-IQ3_XXS-joined.gguf'

& "$Bin\llama-cli.exe" `
  -m $Model `
  -p "日本語で短く自己紹介してください。" `
  -n 64 `
  -c 4096 `
  -ngl 999 `
  -t 4 `
  -b 2048 `
  -ub 1024 `
  --flash-attn auto
```

This checks real model loading and rocBLAS execution. It is not a performance benchmark.

After configuring `local.psd1`, also check the requested 64k allocation:

```powershell
.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R4ROCm -ModelKey UnslothOriginal `
  -Context 65536 -FlashAttn auto -AllocationOnly -ResourceMonitor
```

## Warning volume

Clang 23 emits many warnings in this Windows ROCm build. The high count is dominated by repeated template instantiations of a small set of warning classes, including:

```text
-Wignored-attributes
-Wnested-anon-types
-Wgnu-anonymous-struct
-Wsign-compare
-Wmissing-braces
-Wunused-parameter
-Wdeprecated-declarations
```

The clean r4 baseline does not modify source code merely to suppress these warnings.

## Historical r3 64k result

The r4 result is pending in [BASELINE.md](BASELINE.md). The following accepted
result belongs to [R3-BASELINE.md](R3-BASELINE.md).

Accepted self-built b11247 ROCm baseline:

```text
PP: 359.84 tok/s
TG: 14.50 tok/s
```
