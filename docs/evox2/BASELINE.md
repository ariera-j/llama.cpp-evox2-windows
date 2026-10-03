# r4 clean baseline and validation record

Snapshot: 2026-10-03. Windows builds and original-model 64k allocation checks completed; PP/TG pending.

## Source identity

```text
upstream: ggml-org/llama.cpp
branch: r4/upstream-refresh-20261002
upstream base: bed0a856606ee4a24a164066f73d2379447033f5
upstream title: CUDA: fuse shared experts into MMVQ (#29184)
fork housekeeping: 39f35efdfa135b36d0181a393178cc53719e5363
r3 frozen checkpoint: 0a93fcbb8e5bcf51b331275c4f4b142d822168d6
```

The pure-upstream branch was created at the pinned base, then README/repository
metadata housekeeping was committed separately. The following import carries
only Evo-X2 documentation and build/benchmark infrastructure. COMMON-001/004/005,
r2 grouped-union, and MTP-QSA are not ported into the r4 inference source.

Before building, confirm the working tree is clean and this source-only diff is empty:

```powershell
git status --short
git diff --exit-code bed0a856606ee4a24a164066f73d2379447033f5 -- src ggml common
```

Record the actual r4 HEAD and executable identity in the build/run manifests;
the pinned upstream SHA and the later tooling commit are different identities.

## Validation gates

| Gate | Vulkan | ROCm |
|---|---|---|
| Fresh build (`build-*-b11352`) | passed | passed |
| `llama-cli --version` / `--list-devices` | passed, b11372 / 94b877457 | passed, b11372 / 94b877457 |
| Relevant backend tests | manual OK (user report) | auto 3985/3986, manual 3986/3986; cause unresolved |
| Original GGUF / AllocationOnly, 64k | OK | OK |
| PLE16-converted model load | failed: joined tensor absent | failed: joined tensor absent |
| Real-input 64k | pending | pending |
| Real-input 128k | pending | pending |
| Real-input 256k | pending | pending |

The attached manifests and AllocationOnly console log establish the Windows
build/load results above. Details are in
[R4-BUILD-LOAD-VALIDATION-2026-10-03.md](R4-BUILD-LOAD-VALIDATION-2026-10-03.md).
Use [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md) and
[BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md), then proceed through the gates in order.

## Model and measurement plan

Use the original Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS model with MTP off.
`UnslothOriginal` points to the existing `00001-of-00003.gguf` shard. The
original joined PLE tensor layout does not require physically joining GGUF
shards. The PLE16-converted file does not load on this pinned upstream.

The measured executable identifies itself as b11372 / `94b877457`, while the
existing build directories retain `b11352` in their names. Keep the actual
paths from `local.psd1`; directory labels are not executable identities.

The new `qwen38-r4-clean.psd1` plan uses `R4Vulkan` / `R4ROCm`, f16 K/V,
2048 batch, 1024 ubatch, four threads, FA auto, 1024 generated-token limit,
fit off, reasoning off, and zero prompt-cache RAM. It retains the r3 COMMON-005
CLI settings (`-tb 4`, `--ctx-checkpoints 0t`) but clears the old patch controls.
Actual prompt and generated-token counts must be recorded for comparisons.

AllocationOnly has passed on both backends. Before the initial performance run,
correct `local.psd1` RepoRoot/LogRoot to r4 and inspect the matrix:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r4-clean.psd1 `
  -PlanOnly
```

For the first real-input gate, use the same command with `-OnlyCase 64k` in place
of `-PlanOnly`. After both backends pass, select `-OnlyCase 128k` and then
`-OnlyCase 256k`. `-OnlyBuild R4Vulkan` or `R4ROCm` selects one backend.
The full plan contains six runs and stops on an error. It does not run automatically.

## Historical comparison records

- [R3-BASELINE.md](R3-BASELINE.md): unchanged original r3 clean b11247 record.
- r3 COMMON-004/005 checkpoint: `0a93fcbb8e5bcf51b331275c4f4b142d822168d6`.
- [COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md): final r3 comparison.
- [COMMON005-ROCM-VALIDATION-2026-10-02.md](COMMON005-ROCM-VALIDATION-2026-10-02.md): detailed ROCm validation.

No r3 throughput value is an r4 measurement. Model PLE layout differs between the
primary joined r4 baseline and the converted r3 checkpoint; record this condition
when interpreting PP/TG and memory behavior. If a matched-layout comparison is
needed later, define it as a separate experiment.

The refresh acceptance checkpoint additionally requires the comparisons and
COMMON-001/004/005/006 decisions listed in [ROADMAP.md](ROADMAP.md).
