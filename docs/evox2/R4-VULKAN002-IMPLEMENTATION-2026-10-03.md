# r4 VULKAN-002 implementation and validation

Date: 2026-10-03. Base: `78dac7895ac9f253169f5ac5c6c189ad0f46773d`.
Status: implemented, default OFF; Windows build and GPU acceptance pending.

## Implemented behavior

Enable only with `GGML_VK_QSA_UNION=1` in a fresh process. Unset/0 uses the
existing r4 FA dispatch. `GGML_VK_QSA_UNION_MIN_KV` defaults to 32768;
invalid values fall back to 32768. Keep the threshold fixed during initial A/B.
The historical r2 donor is pinned in
[R4-VULKAN002-PORT-REVIEW-2026-10-03.md](R4-VULKAN002-PORT-REVIEW-2026-10-03.md).

The qwen4exp graph passes final remapped KV-cell ids through a typed optional
`ggml_flash_attn_ext_set_selected_rows()` setter at src[5]. The original mask
continues to define visibility and additive bias. Hints must cover every finite
mask position in each query; supersets are safe. Pool ids must never be supplied
before pool-member expansion, tail concatenation and live/dump remapping.
The extra dependency preserves the ids until FA; src[4] sinks, precision and
op_params[4] sparse bound retain their current roles. Multi-stream model graphs
omit the flattened hint. The Vulkan debug clone copies the optional hint.

The backend processes groups of 64 queries with a 16 KiB bitmap reused across
131072-cell ranges. Duplicate ids are deduplicated; negative and out-of-range
ids are ignored, including dump sentinels. It gathers each KV head once and
copies each query's original mask. The device-local union count is rounded to
256 and consumed directly by FA, with no host readback or statistics loop.
Packed K/V head strides use allocated capacity; mask row strides use the actual
rounded count. Dynamic-count flag 32 is separate from existing sparse flag 16.
The alignment specialization requires every 256-rounded count to fit Bc.

Scratch uses prealloc_y with aligned descriptors and independent union/count
slots per group. Existing resize handling waits for prior work. Barriers order
union, gather, FA, and scratch reuse; cached prealloc_y tensor/pipeline ownership
is invalidated afterward. Capability, descriptor/range, dispatch, tensor shape,
type and stride guards decline unsupported inputs. Q=1, below-threshold KV,
missing hints, multi-stream, non-f16 K/V, sinks, ALiBi and softcap use existing FA.
Activation and fallback each log at most once per backend context. Device startup
logs the switch and threshold. Existing r4 scalar/CM1/CM2 and sparse decode remain
available. No general selector/cache rewrite or GET_ROWS promotion is included.

## Correctness tests

`test-backend-ops` has 18 fixtures selected by `-o FLASH_ATTN_EXT -p qsa_union=1`.
They compare the whole FA result with the dense CPU reference, tolerance NMSE
5e-4. Fixtures cover Q=2/63/64/65/349/1024, group tails, KV=32768/131073/262144,
KV-head/query-head broadcast, hsize 64/128/256, cache views/permuted strides,
shuffled duplicate ids, invalid/dump ids, tiny and >256 rounded unions, and
query-specific finite/-inf masks including additive bias. Eight other cases
exercise Q=1, KV=32767, absent hints, sinks, ALiBi, softcap, multi-stream and
f32 K/V. Empty/all-masked GPU behavior, forced descriptor/device-limit failures,
and graph reuse across real model runs remain explicit acceptance checks;
they are not claimed as executed by these fixtures.

`Test-QsaUnion.ps1` starts separate OFF/ON processes, clears inherited experiment
and profiler switches, restores the caller's environment, and records executable
SHA256, stdout/stderr and results.json. It requires 18/18 passed and startup
switch evidence; ON additionally requires both activation and fallback evidence.
All-fallback or skipped runs fail the gate. Default backend is Vulkan0.

## Validation performed here

- C11 syntax check of the changed real ggml.c with matching headers: passed.
- C++17 syntax check of test-backend-ops.cpp: passed.
- C++17 syntax checks of qwen4exp.cpp and llama-graph.cpp with matching r4 headers:
  passed, including the changed method declarations/calls.
- Built the real shader generator and generated its header: both new shader
  declarations are present. CMake discovers the new .comp files automatically.
- A linked host harness calls the setter from the compiled real ggml.c: attach
  and clear preserve sinks, precision, sparse bound and all other tensor fields.
- Whitespace/diff checks: passed.

This environment has no Vulkan SDK/glslc, GPU backend or PowerShell. Shader/SPIR-V
compilation, full Vulkan C++ compilation, PowerShell execution, the 18 GPU values
and model performance are pending. A successful syntax/host check is not GPU
acceptance, and no speedup is claimed.

## Windows execution order

From the r4 worktree root, build into a separate directory:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir build-vulkan-r4-qsa-union -Parallel 4 -ExtraCMakeArgs @('-DLLAMA_BUILD_TESTS=ON')
.\tools\evox2\benchmark\Test-QsaUnion.ps1 -BinDir .\build-vulkan-r4-qsa-union\bin\Release
```

Stop on build/test failures and provide the generated logs. If tests pass, add
`R4QsaUnionVulkan` to local.psd1 pointing at that bin directory (see local.example).
Use the existing Original/PLE16 model paths and 64k/128k/256k input files.

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-union.psd1 -OnlyJob profile -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan .\tools\evox2\benchmark\configs\qwen38-r4-qsa-union.psd1 -OnlyJob profile
```

The short profile gate is 64k Original OFF/ON (128 generated tokens); inspect
ON activation, errors/output, whole FLASH_ATTN_EXT and total GPU PP costs.
Do not compare union/gather alone. Separate warmup, PP and decode blocks, exclude
the initial decode block from steady TG, and retain all PP blocks under the same
methodology. Avoid interpreting logger-on wall throughput as the final gain.
After this review, run `-OnlyJob normal` for 64k Original and PLE16, then
`-OnlyJob longctx` for PLE16 128k and 256k. Each normal context/model uses
OFF/ON/ON/OFF (ABBA), fixed 512-token decode, seed 1234, ignore-eos and logger OFF.
All use one binary, f16 KV, ubatch 1024, batch 2048, MTP OFF, legacy MoE=1 and
GET_ROWS 128x4=0. Profile has 2 runs; normal and longctx have 8 runs each.

128k/256k PP is the primary value gate. Check TG stability, generated output,
resource-monitor memory and bounded scratch diagnostics. Existing sparse/decode
and graph reuse must remain correct; device/stride fallback must be visible
when exercising unsupported shapes. Stop on correctness failure or regression.
Keep default OFF until these results are reviewed; historical r2 numbers are
context, not a required reproduction target.
