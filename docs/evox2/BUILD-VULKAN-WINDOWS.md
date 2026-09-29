# Windows Vulkan build

## Scope

This procedure builds the clean r3 Vulkan baseline on the Evo-X2.

Baseline source:

```text
llama.cpp b11247
0bc845d356f437d5ce4fe975c36428f7522829cb
```

## Tested toolchain

```text
Windows 11
Visual Studio Build Tools environment / Windows SDK
LLVM/Clang 20.1.8
Vulkan SDK 1.4.357.0
CMake 4.3.1
Ninja 1.13.2
```

The build uses the repository's Windows LLVM toolchain file.

## Environment

Open an x64 Visual Studio Native Tools shell and then PowerShell.

Example:

```powershell
$env:VULKAN_SDK = 'C:\VulkanSDK\1.4.357.0'
$LlvmBin = 'C:\LLVM\20.1.8\bin'

$env:PATH = "$LlvmBin;$env:VULKAN_SDK\Bin;$env:PATH"

where.exe clang
where.exe cmake
where.exe ninja
clang --version
```

The exact installation paths can differ.

## Configure

From the repository root:

```powershell
cmake -S . -B .\build-vulkan-b11247 -G "Ninja Multi-Config" `
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
cmake --build .\build-vulkan-b11247 `
  --config Release `
  --parallel 4 `
  --target llama-cli llama-server llama-bench test-backend-ops
```

Expected binary directory:

```text
build-vulkan-b11247\bin\Release
```

## Smoke checks

```powershell
$Bin = Join-Path $PWD 'build-vulkan-b11247\bin\Release'

& "$Bin\llama-cli.exe" --version
& "$Bin\llama-cli.exe" --list-devices
```

Confirm that the Radeon 8060S appears as the Vulkan device and that the build identity matches the intended source.

## Baseline measurement

Use the workload defined in [BENCHMARKING.md](BENCHMARKING.md) and compare against [BASELINE.md](BASELINE.md).

The current accepted 64k self-built Vulkan baseline is:

```text
PP: 265.10 tok/s
TG: 16.75 tok/s
```

## Notes

- Use a separate build directory for ROCm.
- Do not mix r2 QSA build flags or source changes into this baseline.
- Keep runtime DLLs beside the generated executables when required by the build.
- Treat any compiler, SDK, driver, or source revision change as a new measurement condition.
