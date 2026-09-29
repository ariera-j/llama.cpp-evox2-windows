# Evo-X2 build wrappers

These wrappers turn the documented Windows build procedures into repeatable
commands and write a machine-readable build manifest next to the executables.

Generated manifest:

```text
<build>\bin\Release\evox2-build.json
```

The benchmark tools already look for this exact path. Once the manifest is
present, subsequent `conditions.json` files include it automatically.

## Safety model

The wrappers do not delete build directories.

There is no automatic `cmake --fresh`, `Remove-Item`, or source-tree cleanup.

Use an explicit `-BuildDir` when creating a new experimental build.

## Backfill the current b11247 builds without rebuilding

This is the recommended Phase 5 validation.

Vulkan:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-b11247 `
  -ManifestOnly
```

ROCm:

```powershell
.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-b11247 `
  -ManifestOnly
```

`-ManifestOnly` does not configure, compile, or replace runtime DLLs. It inspects
the existing binaries, hashes build artifacts, records Git/toolchain information,
and runs the normal `--version` / `--list-devices` smoke checks.

For ROCm, if the TheRock venv is active, the wrapper also resolves the ROCm
SDK paths. If it is not active, manifest-only mode still works against an
already self-contained binary directory.

## New Vulkan build

Open the same x64 Visual Studio Native Tools shell used by the documented
manual procedure.

Example:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r3 `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin C:\LLVM\20.1.8\bin `
  -Parallel 4
```

The wrapper uses the repository's:

```text
cmake\x64-windows-llvm.cmake
```

and preserves the existing Vulkan build options from the r3 documentation.

## New ROCm build

Open the VS2022 x64 Native Tools environment and activate the TheRock venv.

Example:

```powershell
.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-r3 `
  -Parallel 4 `
  -RunBackendTest
```

The wrapper resolves:

```text
rocm-sdk path --root
rocm-sdk path --bin
rocm-sdk path --cmake
```

and keeps the tested `gfx1151` target by default.

The HIP backend is built before the user-facing tools, matching the documented
bring-up procedure.

The wrapper also copies:

```text
amdhip64_7.dll
rocm_kpack.dll
amd_comgr.dll
```

beside the executables unless `-SkipRuntimeDllCopy` is specified.

## Manifest content

The manifest records:

- Git commit, branch, dirty state, and dirty fingerprint
- backend and configuration
- build and binary directories
- exact CMake argument list
- target list and parallelism
- CMake / Ninja / Clang / MSVC identities
- Vulkan SDK or ROCm SDK paths
- GPU target for ROCm
- executable/build-artifact SHA-256 values
- `llama-cli --version`
- `llama-cli --list-devices`
- optional ROCm backend-test result
- copied ROCm runtime DLL identities

The manifest records what the wrapper observed. It is not a claim that every
toolchain combination is supported.
