# ROCm runtime provenance and 64k same-binary ABBA — 2026-10-21

## Scope

This note closes the first provenance question before further ROCm performance/correctness work:

1. what ROCm/HIP toolchain built the current r5 Windows ROCm binaries;
2. what runtime DLLs those binaries actually loaded before this investigation;
3. whether a fully TheRock/ROCm 10.0 runtime changes 64k Qwen3.8 PP/TG;
4. why the first run of each runtime arm was slower than the warmed runs.

The tested source/build is the pinned r5 line, build 11521 (embedded executable commit b45025848), using the existing Unsloth Qwen3.8 Flash Next PLE16 model, MTP OFF, f16 KV, 64k context, 61,789 prompt tokens and 512 generated tokens.

Raw matrix archive:

~~~text
20261021-221735-932-qwen38-r5-rocm-runtime-abba.zip
~~~

## Build-time provenance: TheRock / ROCm SDK 10.0.0

The build manifest and CMake cache agree that the binary was built against the TheRock Python SDK installation:

~~~text
C:\TheRock\build\.venv\Lib\site-packages\_rocm_sdk_devel
~~~

Important build-side observations:

- rocm-sdk version reports **10.0.0**.
- C, C++, HIP compiler, LLVM tools, HIP path and CMake prefix all resolve inside the TheRock SDK.
- the executable reports Clang 23.0.0.
- AMDGPU_TARGETS=gfx1151.
- the shell still contained older HIP SDK 7.2 paths, but Build-ROCm.ps1 explicitly overrode the configure/build toolchain with TheRock paths.

Therefore the current b11521 binary itself is a **TheRock / ROCm SDK 10.0.0 build**. The earlier hipcc text "HIP version: 7.15..." must not be interpreted as “built with ROCm 7.2”.

## Historical runtime provenance: mixed at the BLAS boundary

Process-module inspection of the existing build-rocm-common001\bin\Release runtime showed:

~~~text
TheRock-staged / build-local:
  amdhip64_7.dll
  amd_comgr.dll
  rocm_kpack.dll
  ggml-hip.dll and the other llama/ggml DLLs

loaded from C:\Program Files\AMD\ROCm\7.2\bin:
  hipblas.dll
  rocblas.dll
  hipblaslt.dll
~~~

The install-root distinction is the key evidence. Do not infer an exact internal component branch solely from the folder name: some DLL version resources under the ROCm\7.2 installation do not report a useful product version, and the amdhip64_7.dll filename suffix is not a ROCm major-version marker.

Operationally, however, the old runtime was unambiguously **mixed**:

- compile/toolchain + HIP core from TheRock 10.0;
- BLAS stack resolved through the HIP SDK 7.2 installation root because the build directory did not stage the BLAS closure.

This is a packaging/runtime-loader issue, not evidence that the source build itself used the wrong compiler SDK.

## TheRock BLAS dependency closure

Direct dependency inspection established the relevant TheRock runtime graph:

~~~text
ggml-hip.dll
├─ hipblas.dll
│  ├─ rocsolver.dll
│  │  ├─ rocblas.dll
│  │  └─ amdhip64_7.dll
│  └─ rocblas.dll
│     ├─ libhipblaslt.dll
│     └─ amdhip64_7.dll
└─ amdhip64_7.dll

libhipblaslt.dll
├─ amdhip64_7.dll
└─ origami.dll

origami.dll
└─ amdhip64_7.dll
~~~

TheRock DLL versions observed in this investigation include:

~~~text
amdhip64_7.dll   10.0.3581.0
hipblas.dll      3.6.0.0
rocblas.dll      5.6.0.0
libhipblaslt.dll 1.4.1.0
amd_comgr.dll    3.3.0.0
~~~

The unified TheRock staging set therefore includes:

~~~text
amdhip64_7.dll
amd_comgr.dll
rocm_kpack.dll
hipblas.dll
rocblas.dll
rocsolver.dll
libhipblaslt.dll
origami.dll
~~~

TheRock also requires architecture-specific runtime data trees, not only DLLs:

~~~text
rocblas\library\gfx1151\...
hipblaslt\library\gfx1151\...
~~~

The first DLL-only pure-TheRock test loaded the model and constructed the 64k context successfully, then failed when the first real rocBLAS work tried to find rocblas\library\TensileLibrary.dat.

After staging the TheRock rocblas and hipblaslt runtime-data trees as well, the 64k real workload completed normally.

The duplicate runtime files/trees under _rocm_sdk_devel and _rocm_sdk_libraries were checked. For the sampled/hashed DLLs, the duplicate copies were byte-identical. The build/runtime staging policy uses _rocm_sdk_devel\bin so build and runtime provenance have one source root.

## Same-binary A/B construction

The two runtime directories used the same llama.cpp executables and HIP backend DLL.

SHA256 equality was explicitly confirmed for:

~~~text
llama-cli.exe
llama-bench.exe
ggml-hip.dll
~~~

The A/B difference was therefore runtime packaging, not llama.cpp source or executable code.

Definitions:

~~~text
A = historical mixed runtime
    TheRock HIP core + BLAS resolved from C:\Program Files\AMD\ROCm\7.2\bin

B = unified TheRock runtime
    TheRock HIP core + TheRock BLAS closure + TheRock gfx1151 rocBLAS/hipBLASLt data
~~~

ABBA execution order:

~~~text
A1 -> B1 -> B2 -> A2
~~~

All four runs:

- completed with status OK;
- used P-MODE **Performance** from start to finish;
- reported no P-MODE changes or P-MODE warnings;
- used the same model/input/context and MTP OFF;
- processed 61,789 prompt tokens and generated 512 tokens.

## 64k result

| run | runtime | PP tok/s | TG tok/s | high-load power |
| --- | --- | ---: | ---: | ---: |
| A1 | mixed | 380.47 | 20.92 | 119.792 W |
| B1 | TheRock unified | 375.55 | 21.01 | 120.167 W |
| B2 | TheRock unified | 389.94 | 21.02 | 120.269 W |
| A2 | mixed | 389.21 | 21.18 | 119.897 W |

Reading only aggregate PP would make B1 look slower than A1/B2/A2. The prompt-progress, resource and ADLX traces show that this is not a sustained BLAS/runtime throughput difference.

### The difference is concentrated at the beginning of prompt processing

Time from prompt-processing start to 8,192 tokens:

| run | first 8k elapsed | approx. disk read during first 8k | first-8k GPU usage | first-8k GPU clock | first-8k GPU power |
| --- | ---: | ---: | ---: | ---: | ---: |
| A1 | 16.483 s | 765.8 MiB | 71.2% | 2222 MHz | 93.9 W |
| B1 | 19.635 s | 758.6 MiB | 56.7% | 1859 MHz | 94.0 W |
| B2 | 13.610 s | 156.9 MiB | 82.6% | 2431 MHz | 117.9 W |
| A2 | 13.550 s | 220.5 MiB | 90.8% | 2577 MHz | 125.0 W |

A1 was also the overall first run of the session: the task did not begin until about 83.5 s after process start, versus roughly 40–42 s for the later runs. This is another clear session-level cold-start effect and is separate from steady-state prompt throughput.

The exact source of every first-run read is not proven here. The observed pattern is consistent with one-time runtime/Tensile/page-cache/model-page warming. Treat this as a **cold/warm effect**, not as evidence that one runtime is intrinsically faster.

### After the first 8k, the runtime arms converge

Using the logged cumulative prompt times from 8,192 to 61,440 tokens:

~~~text
A1 mixed       377.99 tok/s
B1 TheRock     380.78 tok/s
B2 TheRock     380.91 tok/s
A2 mixed       379.91 tok/s
~~~

In the same region, ADLX averages are effectively the same:

~~~text
GPU usage : ~99.7-99.8 %
GPU clock : ~2.86-2.88 GHz
GPU power : ~119.4-119.6 W
~~~

The most appropriate warmed comparison in this matrix is therefore B2 vs A2:

~~~text
PP:
  B2 TheRock 389.94
  A2 mixed   389.21
  delta      +0.19 % for TheRock

TG:
  B2 TheRock 21.02
  A2 mixed   21.18
  delta      -0.76 % for TheRock
~~~

These differences are small enough to treat the two runtime layouts as **performance-equivalent for this 64k workload**. No evidence was found that keeping the mixed BLAS runtime provides a useful steady-state speed advantage.

## Measurement consequence

Future ROCm benchmark builds should use a unified TheRock 10.0 runtime.

The build script is being changed after this investigation so that a normal staged ROCm build includes:

- the complete TheRock DLL closure listed above;
- rocblas\library\<target>;
- hipblaslt\library\<target>;
- manifest provenance stating the unified-runtime policy.

Historical ROCm binaries built before this change must be treated as **potential mixed-runtime artifacts** unless their loaded module paths were explicitly captured. Do not retroactively relabel old benchmark archives as pure TheRock.

For runtime-comparison experiments, do not rely on the very first run of each newly staged runtime. Warm each runtime arm before attributing PP differences, or separately report cold-start behavior.

## Correctness observation discovered during the ABBA

Although the runtime-speed question is effectively closed, the four temp=0 / fixed-seed runs did **not** produce identical generated text.

This is not evidence that the runtime packaging caused the variation:

- A1 and A2 differ from each other;
- B1 and B2 differ from each other;
- therefore the output variation remains even inside the unified TheRock runtime arm.

The follow-up investigation is now complete; see [R5-ROCM-QSA-REPEATABILITY-2026-10-22.md](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md).

The same-parent / same-TheRock-10.0 64k control restored the missing attribution:

- normal Qwen4Exp `ggml_top_k`: **4 distinct outputs / 4**;
- `ggml_cont(ggml_argsort_top_k(...))`: **1 identical output / 4**;
- FA OFF still produced 4 distinct outputs / 4.

Therefore runtime packaging and Flash Attention alone are not sufficient explanations. QSA top-k selection is the strongest localized cause found for the observed ROCm greedy-output drift.

Current task order:

~~~text
1. ROCm build/runtime provenance and unified runtime      <- complete / this note
2. ROCm output repeatability / QSA top-k investigation    <- complete
3. lightweight Windows event checks                       <- backend-test hang + argsort-r3 stall
4. ROCmFP4 vs Unsloth, same llama.cpp binary
5. input-type investigation continuation: QSA mask visualization -> ROCm RGP
6. needle test v1: Qwen3.8 ROCmFP4 and Gemma 4
~~~

The normal fast top-k path remains the performance default. A future opt-in deterministic QSA selector is recorded in the repeatability report, with 64k-only ROCm coverage at this checkpoint.
