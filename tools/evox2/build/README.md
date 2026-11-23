# Evo-X2 build wrappers

## 2026-10-29: confirmed r6 Vulkan toolchain pin (corrected after Windows preflight)

**The measured b11908 Vulkan and ROCm builds both used VS2022 Build Tools CMake `3.31.6-msvc6`, *not* `4.3.1`.** The original `4.3.1` description came from the earlier **r3** Windows build guide. This was confirmed by inspecting the previously uploaded **G8-6 verification archive** (Vulkan and ROCm `evox2-build.json` manifests, both with verified build identities) plus the independent Vulkan manifest from 2026-10-28. The CMake executable path in all three manifests was:

`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`

The wrapper's **default `-ExpectedCMakeVersion` is therefore `3.31.6-msvc6`**. This is a reproducibility guard for the tested r6 toolchain, **not** a claim that other CMake versions cannot compile llama.cpp. The checked-in source tag and prebuilt Vulkan release ZIP are unchanged.

Resolution rules in `Build-Vulkan.ps1`:

1. CMake: explicit `-CMakeExe` (full path) if supplied, otherwise first `cmake` on `PATH` (VS Native Tools normally resolves to the verified executable above). Check the full version including any suffix against `3.31.6-msvc6` before configure/build; fail with executable path on mismatch. `-ManifestOnly` is exempt. The build manifest now records the selected CMake executable even if `-CMakeExe` overrides `PATH`.
2. Vulkan SDK: explicit `-VulkanSdk` > existing `VULKAN_SDK` environment > if present, `C:\VulkanSDK\1.4.357.0`.
3. LLVM: explicit `-LlvmBin` > if available, `C:\Program Files\LLVM\bin` > else `clang.exe` on `PATH`. Explicit directories are validated.

**No-build preflight** (repo root in x64 VS2022 Native Tools PowerShell):

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 -PreflightOnly
```

Expected:

```text
CMake version verified: 3.31.6-msvc6 (C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\...\cmake.exe)
Auto-selected Vulkan SDK: C:\VulkanSDK\1.4.357.0
Auto-selected LLVM: C:\Program Files\LLVM\bin
PRE-FLIGHT PASS: ...
```

If a different CMake appears after updates or in another shell, inspect `Get-Command cmake.exe -All | Select-Object -ExpandProperty Source` and use `-CMakeExe` to choose an installed matching binary. `-ExpectedCMakeVersion` can be explicitly overridden for a deliberately tested future version, or set to `''` to disable this single guard in an investigation; neither option proves a new build equivalent to the frozen b11908 baseline.

For provenance inspection on Windows:

```powershell
$manifest = Get-Content '.\build-vulkan-r6-combined-fixed\bin\Release\evox2-build.json' -Raw |
    ConvertFrom-Json
$manifest.Toolchain.CMake | Format-List Name,Path,ExitCode,Text
```

The older paragraphs below preserve historical r4/r5 examples and are not instructions to replace the verified r6 CMake. The build still needs Ninja, the VS x64 compiler environment, 7-Zip and the dependency cache; this toolchain check does not compile anything.

## Current refresh

Use new build directories in the new worktree and pass `-BuildDir .\build-vulkan-clean` / `.\build-rocm-clean` explicitly. Defaults in the carried scripts remain `build-vulkan-r4` / `build-rocm-r4`. The shared dependency cache can remain outside the worktree.

Follow the [current Vulkan guide](../../../docs/evox2/BUILD-VULKAN-WINDOWS.md), [current ROCm guide](../../../docs/evox2/BUILD-ROCM-WINDOWS.md) and [handoff](../../../docs/evox2/R5-REFRESH-2026-10-09.md). The carried wrappers are not proof of a successful build on the new upstream.

### Clean-upstream build targets (2026-10-09)

Both wrappers build `llama-cli`, `llama-server`, `llama-bench` and `test-backend-ops` by default. ROCm still builds `ggml-hip` first.

The imported r4 wrappers also requested four downstream MTP/QSA test targets. Their native implementation/CMake definitions are absent from clean r5, so the first Vulkan invocation configured successfully but Ninja stopped with `unknown target 'test-mtp-indexer-policy'`. The same target list was present in the ROCm wrapper; ROCm had not yet been tried on the machine.

Downstream tests are now explicit additions through `-ExtraTargets`, for example `-ExtraTargets @('test-mtp-indexer-policy', 'test-mtp-dense-indexer')` after the corresponding native patch is ported. Missing explicitly requested targets still fail; no test failure is converted to a pass. The build manifest records the complete requested target list.

The completed configure/cache can be reused after pulling the fix:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-clean `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4 -BuildOnly
```

`-BuildOnly` checks the existing cache and refreshes CMake metadata before building. This repair does not establish a completed Windows build or inference validation; those gates remain pending.

## Imported r4 reference

The detailed wrapper reference below preserves historical examples and results. The current guides select the new build directories.

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

The default directories are `build-vulkan-r4` and `build-rocm-r4`. The initial
r4 builds used explicit `build-vulkan-b11352` / `build-rocm-b11352` directories.
Build and original-model allocation results are recorded; performance is pending.

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

## Full ROCm backend-test diagnostics

`-RunBackendTest` still returns an error when the native test exits nonzero.
It now saves all captured output to a timestamped
`evox2-backend-test-rocm-*.log` beside the executables, records its path as
`Validation.BackendTestLogPath`, and prints failure/summary lines on failure.
The compact manifest tail is retained. Logs from earlier invocations are not
overwritten by a later successful retry.

The initial r4 run had one real failed test (3985/3986), followed by a manual
3986/3986 pass. No test threshold, native exit code, or inference source is
changed to hide that failure.
