# Current refresh baseline and historical validation record

## r5 clean baseline (2026-10-09)

Source identity is in [CURRENT-REFRESH.json](CURRENT-REFRESH.json). r5 is pinned at `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b` and carries documentation/tooling from r4 `bddf73442c24545879c9acadc078ba5b2c3cb7d8`. The inference/build source matches upstream; Windows builds, backend/model gates and 64k/128k/256k measurements are pending.

Use [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md), the current build guides and `tools/evox2/benchmark/configs/qwen38-clean.psd1`. Start with Original joined-PLE layout, MTP OFF and f16 KV. Historical r4 results below are preserved as comparison evidence and are not r5 measurements.

Before the first build, check the complete bootstrap diff and an empty source diff against the pinned upstream. Record the actual later HEAD and binary identity in manifests, not just directory labels.

## Preserved r4 clean baseline

Snapshot: 2026-10-03. Windows builds and original-model 64k/128k/256k real-input runs completed on both backends. The clean baseline is preserved below; subsequent COMMON-001 validation is recorded separately in the post-baseline section.

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
metadata housekeeping was committed separately. At the clean-baseline checkpoint,
the following import carried only Evo-X2 documentation and build/benchmark
infrastructure. COMMON-001/004/005, r2 grouped-union, and MTP-QSA were not
ported into the r4 inference source at that point.

Before building the clean baseline, confirm the working tree is clean and this
source-only diff is empty:

```powershell
git status --short
git diff --exit-code bed0a856606ee4a24a164066f73d2379447033f5 -- src ggml common
```

Record the actual r4 HEAD and executable identity in the build/run manifests;
the pinned upstream SHA and the later tooling commit are different identities.

## Validation gates

These gates describe the **pure refreshed-upstream baseline before COMMON-001**.

| Gate | Vulkan | ROCm |
|---|---|---|
| Fresh build (`build-*-b11352`) | passed | passed |
| `llama-cli --version` / `--list-devices` | passed, b11372 / 94b877457 | passed, b11372 / 94b877457 |
| Relevant backend tests | manual OK (user report) | auto 3985/3986, manual 3986/3986; cause unresolved |
| Original GGUF / AllocationOnly, 64k | OK | OK |
| PLE16-converted model load | failed: joined tensor absent | failed: joined tensor absent |
| Real-input 64k | OK, exit 0 | OK, exit 0 |
| Real-input 128k | OK, exit 0 | OK, exit 0 |
| Real-input 256k | OK, exit 0 | OK, exit 0 |

The attached manifests and AllocationOnly console log establish the Windows
build/load results above. Details are in
[R4-BUILD-LOAD-VALIDATION-2026-10-03.md](R4-BUILD-LOAD-VALIDATION-2026-10-03.md).
Use [BUILD-VULKAN-WINDOWS.md](BUILD-VULKAN-WINDOWS.md) and
[BUILD-ROCM-WINDOWS.md](BUILD-ROCM-WINDOWS.md), then proceed through the gates in order.

## Model and measurement plan

Use the original Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS model with MTP off.
`UnslothOriginal` points to the existing `00001-of-00003.gguf` shard. The
original joined PLE tensor layout does not require physically joining GGUF
shards. The PLE16-converted file does not load on the pinned pure upstream
without COMMON-001.

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

## Clean performance through 256k

Each row is one run, MTP off, original joined-PLE Unsloth UD-IQ3_XXS,
manual UMA 96 GB, with the plan settings above. Both binaries report
b11372 / `94b877457`; subsequent tooling changes do not change the inference source.
All six runs returned status OK and exit code 0. Log paths point to r4.

| Backend | Context | Prompt tokens | Generated tokens | PP tok/s | TG tok/s | Run seconds |
|---|---:|---:|---:|---:|---:|---:|
| Vulkan | 64k | 61,789 | 593 | 248.38 | 24.61 | 318.034 |
| ROCm | 64k | 61,789 | 578 | 369.72 | 20.98 | 234.448 |
| Vulkan | 128k | 126,253 | 463 | 168.09 | 22.81 | 816.551 |
| ROCm | 128k | 126,253 | 533 | 275.00 | 17.13 | 533.015 |
| Vulkan | 256k | 255,181 | 555 | 126.76 | 19.26 | 2089.375 |
| ROCm | 256k | 255,181 | 448 | 185.95 | 12.23 | 1451.543 |

Source archives (user-supplied; not committed):

- `20261003-093152-929-qwen38-r4-clean.zip`
- `20261003-094849-992-qwen38-r4-clean.zip`
- `20261003-102327-930-qwen38-r4-clean.zip`

128k prompt-evaluation times are 751.087 s (Vulkan) and 459.098 s (ROCm);
generation-evaluation times are 20.257 s and 31.062 s. Peak sampled system
commit is 94.443 GiB and 93.430 GiB respectively; these are system totals,
not per-process resident memory. No error/warning lines were found in the
128k engine stderr logs. Successful exit is not a semantic-quality validation.

256k completed with the same binary hashes and inference settings as 64k/128k.
The matrix completed 2/2 runs in 59.256 minutes. Vulkan prompt evaluation took
2013.150 s and generation 28.767 s; ROCm took 1372.284 s and 36.545 s.
Both engine stderr logs contain no error/warning matches. The generated answers
are readable Japanese summaries; factual coverage has not been scored.

256k resource observations (Vulkan / ROCm):

- Peak sampled system commit: 100.184 / 99.053 GiB (78.5% / 77.6%).
- Peak process GPU shared memory: 1.272 / 1.355 GiB.
- KV buffers: 6144 + 1536 MiB on each backend.
- GPU compute buffers: 3162.15 / 2977.18 MiB; host compute: 802.12 MiB each.
- Free RAM briefly reaches 0.041 / 0.064 GiB during the first 60 seconds, which
  include model loading and early prefill. Large page-in/disk-read peaks occur
  in that interval. Page-ins include file-backed reads, not just pagefile I/O.
- Excluding the first and last 60 seconds, median free RAM is 18.457 / 17.978 GiB,
  with median disk reads and page-ins zero. Some read bursts remain; system-wide
  counters alone do not identify their process or file. The data do not establish
  sustained RAM exhaustion as the cause of the TG gap.
- Graph reuse counts: 550 / 443 for 555 / 448 generated tokens.

Original-model completion through 256k removed an immediate load/stability reason
to port COMMON-001 for this workload; PLE16 compatibility and matched-layout
performance comparisons remained separate reasons to evaluate it.

## Post-baseline COMMON-001 validation

COMMON-001 was subsequently adapted to r4 and committed as:

```text
a60a57879a9ffb4d51acd45d4de7e80d721548f9
qwen4exp: restore split PLE n-gram tensor support
```

The port restores the split PLE16 layout while preserving the joined Original
path. Vulkan and ROCm both pass AllocationOnly/short inference with PLE16, and
PLE16 real-input validation now completes through 256k on both backends.

64k matched post-port comparison:

| Backend | Model | PP tok/s | TG tok/s |
|---|---|---:|---:|
| Vulkan | Original joined | 267.51 | 24.53 |
| Vulkan | PLE16 | 268.79 | 25.46 |
| ROCm | Original joined | 370.32 | 21.17 |
| ROCm | PLE16 | 370.37 | 21.16 |

Long-context PLE16 validation:

| Backend | Context | PP tok/s | TG tok/s | Result |
|---|---:|---:|---:|---|
| Vulkan | 128k | 178.99 | 23.24 | OK |
| ROCm | 128k | 279.80 | 17.13 | OK |
| Vulkan | 256k | 132.99 | 19.56 | OK |
| ROCm | 256k | 185.90 | 12.41 | OK |

The Vulkan COMMON-001 measurements use
`GGML_VK_MOE_LEGACY_TILE_SELECTION=1` to match the pre-port diagnostic reference,
whereas the pure clean baseline above used the upstream-default MoE policy.
Therefore the Vulkan clean-to-COMMON-001 PP gain is not attributed to the PLE16
port. At 64k, the +8.2% clean-to-PLE16 PP difference closely matches the earlier
same-binary MoE legacy A/B gain (+8.25%), while the post-port Original/PLE16 PP
difference is only about +0.5%.

ROCm is effectively performance-neutral between the clean Original baseline and
the COMMON-001 PLE16 runs across 64k/128k/256k. COMMON-001 is therefore treated
as a compatibility/layout patch, not a throughput optimization.

Detailed validation, r3/r2 comparisons, and next-step interpretation are in
[R4-COMMON001-VALIDATION-2026-10-03.md](R4-COMMON001-VALIDATION-2026-10-03.md).
The exact matrix plans are:

```text
tools/evox2/benchmark/configs/qwen38-r4-common001-64k.psd1
tools/evox2/benchmark/configs/qwen38-r4-common001-longctx.psd1
```

The provisional patch decisions and revision gates are in
[R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md).

## Historical comparison records

- [R3-BASELINE.md](R3-BASELINE.md): unchanged original r3 clean b11247 record.
- r3 COMMON-004/005 checkpoint: `0a93fcbb8e5bcf51b331275c4f4b142d822168d6`.
- [COMMON005-VALIDATION-2026-10-02.md](COMMON005-VALIDATION-2026-10-02.md): final r3 comparison.
- [COMMON005-ROCM-VALIDATION-2026-10-02.md](COMMON005-ROCM-VALIDATION-2026-10-02.md): detailed ROCm validation.

No r3 throughput value is an r4 measurement. The original clean r4 baseline and
r3 checkpoint used different PLE layouts; the subsequent COMMON-001 validation
now supplies the matched r4 Original/PLE16 comparison needed to separate layout
compatibility from the larger performance topics.

The refresh acceptance checkpoint additionally requires the comparisons and
COMMON-001/004/005/006 decisions listed in [ROADMAP.md](ROADMAP.md).
