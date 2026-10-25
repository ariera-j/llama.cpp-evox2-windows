# r4 Windows build/load validation, 2026-10-03

## Source and executable identity

- Branch: `r4/upstream-refresh-20261002`.
- Pinned upstream: `bed0a856606ee4a24a164066f73d2379447033f5`.
- Built fork revision: `94b8774573901cd9b6986d3c43be0f74557e4863`, clean.
- Both executables report **b11372 / 94b877457**. The build directories are
  named `build-vulkan-b11352` and `build-rocm-b11352`; these labels do not
  override the detected build identity.
- Vulkan compiler: Clang 20.1.8. ROCm compiler: Clang 23.0.0, TheRock 10.0.0,
  VS2022 / MSVC 14.44, GPU target `gfx1151`.

Evidence: the two attached `evox2-build` manifests, the AllocationOnly console
transcript, the manual ROCm test transcript, and the user's Vulkan test report.
Raw machine-local configurations and logs are not committed to this repository.

## ROCm automatic backend test versus manual retest

The build finished and the executable/device smoke checks exited zero.
The wrapper then invoked:

```text
test-backend-ops.exe test -b ROCm0 -o FLASH_ATTN_EXT
```

The automatic test genuinely returned exit code 1:

```text
3985/3986 tests passed
Backend ROCm0: FAIL
```

The failing case was:

```text
FLASH_ATTN_EXT(hsk=128,hsv=128,nh=8,nr23=[4,1],kv=16384,nb=512,mask=1,sinks=0,max_bias=0.000000,logit_softcap=0.000000,prec=f32,type_K=f16,type_V=f16,permute=[0,1,2,3],kv_view=1,v_is_view_of_k=0,n_kv_max=0)
```

The manual transcript includes the same case marked OK, and ends with
`3986/3986 tests passed`, `Backend ROCm0: OK`, and `2/2 backends passed`.
This is a failed first execution followed by a passing retest, not a wrapper
misreading a successful test or a compilation failure.

The original manifest saved only the final 80 lines, so the first execution's
detailed error diagnostic is absent. It is not possible to distinguish an
error-threshold exceedance, NaN/sentinel problem, or backend comparison failure
from the retained summary alone.

Source inspection shows this Flash Attention test initializes Q/K/V with random
values and generates a random masked attention matrix on each execution.
Different runs therefore do not use identical inputs. An input-dependent
numerical issue is a candidate explanation, not an established cause. Runtime
environment differences also cannot be excluded from the supplied transcripts.

The tooling change preserves the native failure, saves complete timestamped
test logs beside the binaries, records `Validation.BackendTestLogPath`, and
prints failure/summary lines. It changes neither the test tolerance nor HIP or
model inference code. The actual cause remains unresolved until full failure
diagnostics are captured.

To rerun diagnostics without compiling or copying DLLs, use the updated wrapper
from the existing ROCm environment:

```powershell
.\tools\evox2\build\Build-ROCm.ps1 `
  -BuildDir .\build-rocm-b11352 `
  -ManifestOnly -RunBackendTest
```

This reruns the complete test and updates the build manifest. Preserve the old
manifest if it is needed as the initial failure record.

## Model-loading results at requested 64k context

| Backend | Original GGUF, first shard | PLE16-converted GGUF |
|---|---|---|
| Vulkan | OK, exit 0, actual context 65536 | failed, exit 1 |
| ROCm | OK, exit 0, actual context 65536 | failed, exit 1 |

Both PLE16 failures name the same required tensor:

```text
check_tensor_dims: tensor 'per_layer_token_embd.weight' not found
```

This identifies a model-loader/layout mismatch on the pinned r4 source, before
GPU inference. It supports leaving COMMON-001 out of the first clean baseline
while using the original model, but does not establish that COMMON-001 is no
longer needed for operational PLE16 support.

The successful model is `UnslothOriginal`, a multi-file GGUF loaded by passing
`00001-of-00003.gguf`. Its original PLE tensor has joined layout; the GGUF files
do not need to be merged into one physical file.

AllocationOnly used a short 18-token prompt and generated two tokens (`OK`).
Those PP/TG values are smoke-test measurements and are not long-context
performance baselines.

## Log destination and next measurement

The uploaded `local.psd1` still had r3 `RepoRoot` and `LogRoot` values. The
scripts detect the source root from their own location but honor an explicitly
configured `LogRoot`, so the r4 child runs correctly followed that stale
configuration into r3's `evox2-logs` directory.

The corrected local file changes those two settings to r4 and retains all
build/model/input entries. Existing logs remain where they were created.
The example configuration now leaves `LogRoot` empty so fresh copies default
to the scripts' own worktree. CLI/bench previews and matrix PlanOnly show the
effective log root before launching inference.

`qwen38-r4-clean.psd1` now uses `R4Vulkan` / `R4ROCm` with `UnslothOriginal`.
Inspect with `-PlanOnly`, then run `-OnlyCase 64k`. Proceed to 128k and 256k
after reviewing each earlier gate. The plan contains six CLI runs, MTP off,
and stops on error. Long-context PP/TG remains unmeasured.
