# Windows Vulkan build

## Scope

This procedure builds the clean r4 Vulkan baseline on the Evo-X2.

Baseline source:

```text
pinned upstream: bed0a856606ee4a24a164066f73d2379447033f5
branch: r4/upstream-refresh-20261002
```

The procedure is carried forward from the validated r3 toolchain. The r4 build
and runtime checks have not yet been executed on the Evo-X2.

## Previously tested toolchain (r3)

```text
Windows 11
Visual Studio Build Tools environment / Windows SDK
LLVM/Clang 20.1.8
Vulkan SDK 1.4.357.0
CMake 4.3.1
Ninja 1.13.2
7-Zip (required by `GGML_OPENMP_FETCH=ON`)
```

The build uses the repository's Windows LLVM toolchain file.

## Environment

Open an x64 Visual Studio Native Tools shell and then PowerShell.

Example:

```powershell
$env:VULKAN_SDK = 'C:\VulkanSDK\1.4.357.0'
$LlvmBin = 'C:\Program Files\LLVM\bin'
$SevenZipBin = 'C:\Program Files\7-Zip'

$env:PATH = "$LlvmBin;$SevenZipBin;$env:VULKAN_SDK\Bin;$env:PATH"

where.exe clang
where.exe cmake
where.exe ninja
where.exe 7z
clang --version
```

The exact installation paths can differ.

An explicitly selected LLVM directory should contain both `clang.exe` and
`clang++.exe`. Verify the path rather than allowing another Clang installation
already on `PATH` to be selected accidentally.

`GGML_OPENMP_FETCH=ON` uses 7-Zip while fetching/configuring OpenMP. If 7-Zip is
not already on `PATH`, add its installation directory before running CMake.

## Build wrapper (recommended)

From the r4 repository root in the prepared Native Tools PowerShell shell:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

The default build directory is `build-vulkan-r4`. Use a new directory for the
first r4 build. The wrapper records build provenance and runs identity/device
smoke checks; it does not run model-load or backend-ops validation.

## Configure (manual alternative)

From the repository root:

```powershell
cmake -S . -B .\build-vulkan-r4 -G "Ninja Multi-Config" `
  "-DCMAKE_TOOLCHAIN_FILE=$PWD\cmake\x64-windows-llvm.cmake" `
  -DGGML_VULKAN=ON `
  -DGGML_NATIVE=OFF `
  -DGGML_BACKEND_DL=ON `
  -DGGML_CPU_ALL_VARIANTS=ON `
  -DGGML_OPENMP=ON `
  -DGGML_OPENMP_FETCH=ON `
  -DLLAMA_BUILD_BORINGSSL=ON `
  -DLLAMA_BUILD_EXAMPLES=OFF `
  -DLLAMA_BUILD_TESTS=ON `
  -DLLAMA_BUILD_TOOLS=ON `
  -DLLAMA_BUILD_SERVER=ON `
  -DLLAMA_BUILD_UI=OFF `
  -DGGML_RPC=ON
```

If dependency caches are used, keep them outside the source tree or in explicitly ignored build/cache directories.

## Build

```powershell
cmake --build .\build-vulkan-r4 `
  --config Release `
  --parallel 4 `
  --target llama-cli llama-server llama-bench test-backend-ops
```

Expected binary directory:

```text
build-vulkan-r4\bin\Release
```

## Smoke checks

```powershell
$Bin = Join-Path $PWD 'build-vulkan-r4\bin\Release'

& "$Bin\llama-cli.exe" --version
& "$Bin\llama-cli.exe" --list-devices
```

Confirm that the Radeon 8060S appears as the Vulkan device and that the build identity matches the intended source.

## Backend and model-load checks

```powershell
& "$Bin\test-backend-ops.exe" test -b Vulkan0 -o FLASH_ATTN_EXT

.\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -BuildKey R4Vulkan -ModelKey UnslothOriginal `
  -Context 65536 -FlashAttn auto -AllocationOnly -ResourceMonitor
```

Use the actual Vulkan device name from `--list-devices` if it differs. Configure
`local.psd1` first. AllocationOnly uses a short prompt and 32 generated tokens;
it verifies allocation and real execution rather than long-context throughput.

## Baseline measurement

Use the workload defined in [BENCHMARKING.md](BENCHMARKING.md) and compare against [BASELINE.md](BASELINE.md).

The r4 results are pending. The historical clean r3 b11247 Vulkan baseline is:

```text
PP: 265.10 tok/s
TG: 16.75 tok/s
```

## Notes

- Use a separate build directory for ROCm.
- Do not mix r2 QSA build flags or source changes into this baseline.
- Keep runtime DLLs beside the generated executables when required by the build.
- Treat any compiler, SDK, driver, or source revision change as a new measurement condition.
