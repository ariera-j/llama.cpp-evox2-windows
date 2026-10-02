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

Relative `-BuildDir` values are resolved from the repository root, not from the
process working directory inherited from Visual Studio or another launcher.

## Historical r3 manifest backfill (run from the preserved r3 checkout)

These examples concern the old b11247 binaries, not the new r4 build.
The first r4 build must use a fresh build directory; `-ManifestOnly` cannot build it.

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

The default directories are `build-vulkan-r4` and `build-rocm-r4`. Runtime and
performance validation on the pinned r4 upstream is pending.

## New Vulkan build

Open the same x64 Visual Studio Native Tools shell used by the documented
manual procedure.

Example:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r4 `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

The wrapper validates that `clang.exe` and `clang++.exe` exist in an explicitly
supplied `-LlvmBin`. This prevents a bad LLVM path from silently falling through
to another Clang installation already on `PATH`.

`GGML_OPENMP_FETCH=ON` requires 7-Zip during configure. The wrapper first checks
`PATH`, then the standard `C:\Program Files\7-Zip` and
`C:\Program Files (x86)\7-Zip` locations. Use `-SevenZipBin` only when 7-Zip is
installed elsewhere.

The wrapper uses the repository's:

```text
cmake\x64-windows-llvm.cmake
```

and preserves the existing Vulkan build options carried forward from the validated r3 documentation.

## New ROCm build

Open the VS2022 x64 Native Tools environment and activate the TheRock venv.

The validated Evo-X2 setup uses MSVC 14.44 from VS2022 Build Tools. During
bring-up, MSVC 14.51 caused HIP compilation conflicts in `<cmath>`, so confirm
`$env:VCToolsInstallDir` and `where.exe cl` if the host toolchain changes.

Example:

```powershell
.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-r4 `
  -Parallel 4 `
  -RunBackendTest
```

The wrapper records the SDK version with:

```text
rocm-sdk version
```

and resolves:

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
- Vulkan SDK / 7-Zip path or ROCm SDK paths
- GPU target for ROCm
- executable/build-artifact SHA-256 values
- `llama-cli --version`
- `llama-cli --list-devices`
- optional ROCm backend-test result
- copied ROCm runtime DLL identities

The manifest records what the wrapper observed. It is not a claim that every
toolchain combination is supported.

## Shared dependency cache

The build wrappers can reuse a dependency cache outside the repository so that
fresh build directories do not repeatedly download the same dependencies.

Cache-root resolution order:

1. explicit `-DependencyCacheRoot`
2. `EVOX2_DEPS_ROOT`
3. an existing `evox2-deps` directory beside the repository directory

For the standard Evo-X2 layout:

```text
C:\llama-build\
  llama.cpp-evox2-windows-r4\
  evox2-deps\
```

the wrappers automatically discover:

```text
C:\llama-build\evox2-deps
```

The current cache layout is:

```text
evox2-deps\
  fetchcontent\
    boringssl-src\
    boringssl-<version>-src\
  openmp\
    llvm-openmp-<version>-x64\
```

The legacy unversioned `fetchcontent\boringssl-src` directory is accepted only
when Git confirms that it is a clean checkout of the BoringSSL version requested
by the current llama.cpp source. New cache captures use a versioned source
directory.

Only the BoringSSL **source tree** is shared. `boringssl-build` is deliberately
not reused across build directories because Vulkan and ROCm may use different
compiler toolchains and build settings.

For Vulkan, the wrapper seeds the build-local `_deps\llvm-openmp-...` directory
from the shared OpenMP cache before CMake configure. For both Vulkan and ROCm,
the wrapper passes a validated BoringSSL source through
`FETCHCONTENT_SOURCE_DIR_BORINGSSL`.

On a cache miss, CMake uses its normal network fetch. After a successful
configure, the wrapper copies the newly fetched dependency into the shared
cache so that later fresh build directories can reuse it.

To use a different cache explicitly:

```powershell
-DependencyCacheRoot D:\llama-deps
```

To disable automatic cache use for one invocation, explicitly pass an empty
value:

```powershell
-DependencyCacheRoot ''
```

A build manifest records the cache root, expected dependency versions, reused
sources, OpenMP seeding, and any dependency captured after configure.
