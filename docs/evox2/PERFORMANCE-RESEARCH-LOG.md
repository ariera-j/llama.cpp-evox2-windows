# Performance Research Log

This file is a dated intake log for performance-related research around the Evo-X2 / Windows `llama.cpp` work.

It is intentionally separate from `ROADMAP.md` and the implementation/measurement documents.

- Record newly found upstream changes, external engines, toolchain releases, and optimization ideas here first.
- Treat entries as research notes, not implementation decisions.
- Promote items into `ROADMAP.md`, `PERFORMANCE-CANDIDATES-*.md`, or a dedicated implementation document only after the priority and applicability are reviewed.
- Keep source links and the observed date because upstream status can change quickly.

---

## 2026-10-07

### Context at time of research

- Active branch: `r4/upstream-refresh-20261002`
- r4 pinned upstream: `bed0a856606ee4a24a164066f73d2379447033f5`
- Main target: GMKtec Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S (`gfx1151`)
- Main workload: Qwen3.8-Flash-Next on Windows, Vulkan and ROCm
- Current Windows ROCm baseline: ROCm 10.0.0 / TheRock, LLVM/Clang 23
- Current GPU driver baseline: Adrenalin 26.8.1
- No upstream repin or implementation change is implied by this log.

### High-level conclusion

The latest upstream has become materially more interesting for a clean A/B than it was at the start of r4, mainly because upstream reverted the Vulkan MoE tile-selection change that independently looked problematic on Evo-X2.

At the same time, the current r4 pin should remain fixed until the ongoing MTP correctness/equivalence work is settled. A latest-upstream comparison should be done as a separate clean baseline rather than by replacing the r4 source in place.

Current provisional priority impact:

1. Keep COMMON-002 MTP correctness/equivalence and PP attribution as the immediate work.
2. Raise a clean latest-upstream A/B in priority.
3. Keep ROCm long-context PP scaling as an active investigation if the latest-upstream A/B does not change it.
4. Promote Strata from "later external engine" to an independent Windows/gfx1151 smoke-test candidate.
5. Add ROCm 10.1.0 as an independent toolchain A/B candidate, but do not replace the current ROCm 10.0 baseline in the middle of r4.
6. Keep COMMON-005 residual ROCm decode work and broader VULKAN-002 work deferred until the current PP/MTP/upstream questions are clearer.

---

## llama.cpp upstream

### Snapshot

Observed on 2026-10-07:

- Master observed at `b9acf138a1e28ce1fc23b5a4fc4b12444b50f7ea`
  - commit message: `feat: add GLM5Next MTP, optimize (#29928)`
- Latest release observed: `b11472`
- The observed master was about 104 commits ahead of the r4 pinned upstream.
- This count is only a point-in-time reference and should be rechecked before any actual repin.

Sources:

- https://github.com/ggml-org/llama.cpp
- https://github.com/ggml-org/llama.cpp/releases/tag/b11472

### #29936 - Vulkan MoE tile-selection revert

Status: **merged**

Relevance: **High**

Upstream reverted PR #29182's `mul_mat_id` tile-selection behavior.

The problematic behavior selected the tile using rows-per-expert (`n_per_expert`) rather than the total row count. Upstream reports regressions from that change, including AMD/Strix Halo observations, and restored the previous behavior.

This is especially relevant because r4 independently isolated the same area while investigating MoE PP behavior and added legacy tile-selection diagnostics/selection.

Implication:

- This strongly supports the local r4 diagnosis.
- A current upstream baseline may now behave closer to the r4 legacy-tile candidate without carrying that local workaround.
- This is the strongest reason found today to raise latest-upstream A/B priority.
- Do not remove the r4 diagnostic path yet; use it as a comparison point.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29936

### #29825 - Qwen4Exp indexer score memory reduction

Status: **merged**

Relevance: **Medium-High for long-context memory; Low-Medium for raw speed**

This PR was still open around the r4 pin and is now merged.

The implementation scores one indexer head at a time and uses in-place ReLU, reducing compute-buffer memory while preserving the same top-k result.

Reported examples in the PR include approximately:

- 128k / ub2048: 3.0 GiB -> 1.5 GiB
- 128k / ub4096: 6.1 GiB -> 3.0 GiB
- 256k / ub4096: 11.7 GiB -> 5.6 GiB

Implication:

- Useful for 256k memory margin and stability.
- Not currently treated as a direct PP/TG optimization.
- Another reason that a clean current-upstream long-context baseline is worthwhile.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29825

### #30049 - Vulkan AMD iGPU slow checkpoint-read fix

Status: **merged**

Relevance: **High for checkpoint/prompt-cache paths; Low for the current benchmark configuration**

The change specifically addresses slow reads from AMD UMA host-visible memory and includes Strix Halo / Radeon 8060S measurements.

The new path avoids the slow direct read and uses a device-to-host copy path.

Implication:

- Potentially important for real TTFT, checkpoint restore, and prompt-cache workflows.
- Current benchmark runs commonly use `--ctx-checkpoints 0t`, so it is unlikely to explain the current PP measurements.
- Keep as an upstream benefit to verify later when checkpoint/prompt-cache behavior is tested.

Source:

- https://github.com/ggml-org/llama.cpp/pull/30049

### #29639 - Vulkan sparse flash attention for quantized K/V

Status: **merged**

Relevance: **Medium as a future q8_0/q4 K/V candidate**

Adds sparse flash attention support for quantized K/V in the QSA path instead of falling back to context-wide dense attention.

Reported q8_0 K/V decode gains on RDNA3/RDNA4 vary by context length, with a particularly interesting result around 64k.

Implication:

- The current main benchmark configuration uses f16 K/V, so this does not directly change the present baseline.
- It makes the existing roadmap item for a q8_0 K/V operational A/B more attractive.
- Test only after the current f16 baseline and MTP behavior are stable.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29639

### Other merged changes noted

#### #29988 - Vulkan flash-attention shared-memory bounds fix

Relevance: Low for current Evo-X2 performance work.

Mostly a correctness/stability fix; the reported failure context is more NVIDIA-oriented.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29988

#### #29934 - RDNA4 mat_vec tuning

Relevance: Low-Medium.

Interesting as a tuning reference, but the Evo-X2 is RDNA 3.5 / gfx1151, not RDNA4.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29934

#### #29797 - greedy selection for temp=0 eligible sampler chains

Relevance: Low-Medium.

Can improve decode overhead for temp=0 workloads. The normal long-context runs here often use nonzero temperature, so it is not a primary optimization target.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29797

---

## Open upstream candidates

### #28303 - HIP tiled F32 concat fast path for RDNA 3.5

Status: **open at time of research**

Relevance: **High enough to retain for ROCm PP investigation**

The PR adds a shared-memory tiled transpose fast path for an F32 concat pattern on RDNA 3.5.

The PR reports Windows 11 / Ryzen AI Max+ 395 / Radeon 8060S / ROCm results with PP improvements in roughly the 5-10% range for a Qwen3.6-35B-A3B workload, with TG essentially unchanged.

Implication:

- Hardware match is unusually good.
- Do not assume Qwen3.8-Flash-Next hits the same shape.
- If the current ROCm 64k -> 256k PP slope remains after a clean latest-upstream A/B, this is a strong isolated candidate to profile/test.

Source:

- https://github.com/ggml-org/llama.cpp/pull/28303

### #29353 - CUDA/HIP chunked GDN kernel

Status: **open at time of research**

Relevance: **High for ROCm PP investigation**

The PR reports a Qwen3.8-27B PP gain on Strix Halo of about 6-7% at pp2048/pp4096 in the provided test.

Implication:

- Directly interesting because of both the model family and Strix Halo target.
- It is not merged, so simply repinning to current upstream is unlikely to capture this gain.
- If ROCm long-context PP remains weak after an upstream refresh test, isolate this candidate rather than immediately starting a broad source rewrite.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29353

### #29187 - fuse GDN alpha/beta projections

Status: **open at time of research**

Relevance: Medium.

Conceptually relevant to GDN overhead, but current evidence is more CUDA-focused than HIP/gfx1151-focused.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29187

### #25666 - disable MMVQ for speculative-decode steps on AMD Vulkan

Status: **open at time of research**

Relevance: **Medium-High for MTP small-batch verification**

The PR reports a notable Strix Halo MTP TG improvement in the tested configuration and also reports higher acceptance behavior.

Caveats:

- The evidence is narrowly hardware/configuration specific.
- The vendor-selection semantics are debated in the PR.
- It should not be ported blindly.

Implication:

- If MTP small-batch verify remains suspicious after correctness is established, reproduce the relevant batch/shape behavior first.
- This is more targeted than a general Vulkan PP optimization.

Source:

- https://github.com/ggml-org/llama.cpp/pull/25666

### #29679 - RDNA3 AMD proprietary-driver MMVQ small-batch tuning

Status: **open at time of research**

Relevance: **Medium-High for Windows Vulkan MTP**

The PR reports severe small-batch cliffs for certain column counts on AMD's Windows proprietary driver and large gains from changing 4-row MMVQ selection behavior.

The published test GPU is not gfx1151, but the driver family overlaps the current Windows setup more closely than Linux Mesa-only investigations.

Implication:

- Worth a microbenchmark/reproduction check if MTP verification remains a bottleneck.
- Do not port without reproducing the relevant shape on Radeon 8060S.

Source:

- https://github.com/ggml-org/llama.cpp/pull/29679

---

## Unsloth llama.cpp mix

### Latest observed release

Observed release:

- `b11443-mix-d65395f`
- Published 2026-10-06

This is materially newer than the previously tracked b11160-era mix.

Source:

- https://github.com/unslothai/llama.cpp/releases

### #240 - Qwen MTP heads sharing target token_embd/output

Status: **open at time of research**

Relevance: **High to COMMON-002 correctness/compatibility**

The PR explains that newer upstream MTP support does not by itself make all currently published Unsloth Qwen MTP sidecars work.

It describes two important compatibility cases:

- a shared MTP head that omits its own `token_embd` / output tensors;
- a self-contained head whose dense MTP block can conflict with QSA k-pool assumptions.

The patch borrows the target embeddings/output for the shared-head form and avoids constructing an incompatible QSA k-pool input for the dense MTP block.

Implication:

- This independently supports keeping COMMON-002's real-sidecar loading/correctness/equivalence gate.
- Do not treat "upstream has MTP support" as sufficient evidence that the actual Unsloth sidecar is correct.
- The current local MTP compatibility work remains justified even if r4 later moves to a newer upstream.

Source:

- https://github.com/unslothai/llama.cpp/pull/240

### #241 - remaining mix-only changes

Status: **open at time of research**

Relevance: Medium.

Carries additional mix-side behavior that has not necessarily landed upstream, including graph/readahead/NextN-related changes.

Implication:

- Keep Unsloth mix as a comparison/reference source rather than assuming latest upstream fully supersedes it.

Source:

- https://github.com/unslothai/llama.cpp/pull/241

---

## Strata

### v0.1.40 / v0.1.40.2

Status: **released**

Relevance: **Raised from "later exploration" to "independent smoke-test candidate"**

The major change is experimental Strix Halo / `gfx1151` support.

The project documentation now states that:

- Radeon 8060S / 8050S are recognized;
- HIP includes `gfx1151` code;
- a Windows HIP package exists;
- Windows Strix Halo is not yet maintainer-tested;
- the gfx1151 path includes hardware-specific prompt attention, block scorer, GEMM/prompt-expert work, hipBLASLt tuning, and related defaults.

The published Strix Halo numbers are not directly comparable with the current llama.cpp measurements because model quantization, KV format, speculative settings, and benchmark method differ.

Implication:

- It is now worth doing a **separate** Windows HIP smoke test when the Evo-X2 is free.
- Treat Strata as a performance/reference engine, not as a replacement for the llama.cpp optimization project.
- A short 64k/128k test can answer whether the Windows package runs correctly and establish an external performance reference with little source-change risk.

Sources:

- https://github.com/Niko1221/Strata/releases/tag/v0.1.40
- https://github.com/Niko1221/Strata/releases/tag/v0.1.40.2
- https://github.com/Niko1221/Strata/blob/main/docs/STRIX_HALO.md

---

## Halogen

### 0.17.0-era update

Status: active upstream; still Linux-native

Relevance: **Reference only for the normal Windows setup**

Recent changes include faster decode on new text through n-gram lookup-table row readahead, plus other speculative/NPU work.

The project still requires native Linux with the amdgpu/KFD stack for its main engine and does not become a direct Windows execution option for the current setup.

Implication:

- Keep as a design/profiling reference.
- The n-gram row-readahead idea remains conceptually interesting for future PLE/lazy-table/residency work.
- No reason found today to divert the current Windows llama.cpp work into a Halogen port.

Source:

- https://github.com/peonist-ai/halogen-flash-server

---

## LaurentZuijdwijk llama.cpp fork

Status: no meaningful new movement found since the previously reviewed early-September work.

Relevance: Low for immediate refresh.

Implication:

- No new reason found today to refresh r4 from this fork.
- Retain earlier ROCmFPx and Strix Halo work as reference material.

Source:

- https://github.com/LaurentZuijdwijk/llama.cpp

---

## ROCm 10.1.0 / TheRock

Status: **released 2026-10-05**

Relevance: **Medium-High as an independent toolchain A/B**

The current accepted r4 Windows ROCm baseline is ROCm 10.0.0 / TheRock with LLVM/Clang 23.

ROCm 10.1.0 is directly relevant to the Evo-X2:

- AMD's compatibility matrix includes Ryzen AI Max+ 395 / Radeon 8060S / `gfx1151`.
- The listed supported Windows configuration is Windows 11 25H2.
- The listed supported Adrenalin version for that matrix is 26.10.41.05.
- The current Evo-X2 baseline driver is 26.8.1, so a fully supported 10.1 configuration would also change the driver.
- HIP moves to 10.1.0.
- LLVM is 24.0.0.
- rocBLAS moves from 5.6.0 to 5.7.0.
- Windows APU handling gains explicit `hipExtHostRegisterCoarseGrained` support for host-pinned unified memory.

The coarse-grained host-memory change is especially interesting on a unified-memory APU, but it should not be assumed to improve llama.cpp automatically without checking whether the relevant allocation path uses it.

Implication:

- Do **not** replace the r4 ROCm 10.0 environment in place while MTP and upstream comparisons are still active.
- Preserve ROCm 10.0 as the reproducible baseline.
- Add a separate `ROCm 10.0 vs 10.1` A/B after the current work reaches a clean checkpoint.
- Because the supported matrix also changes the GPU driver, distinguish:
  - toolchain-only experiments, if technically runnable;
  - the fully supported 10.1 stack with the matching newer driver.
- Recheck release notes, Windows compatibility, and driver known issues immediately before doing the actual update.
- The existing ROCm long-context PP slope is a good workload for the A/B, but there is currently no evidence that 10.1 alone fixes it.

Sources:

- https://rocm.docs.amd.com/en/latest/about/release-notes.html
- https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html

---

## Suggested next sequence when llama.cpp work resumes

This is a provisional ordering from today's research, not a ROADMAP change.

1. Finish/settle the current COMMON-002 MTP correctness/equivalence question.
2. Preserve the current r4 pin and measurements.
3. Build a separate clean latest-upstream candidate and compare primarily at 128k, with 64k support and 256k if needed.
4. Confirm whether the upstream #29936 revert removes the need for the local legacy MoE tile-selection behavior.
5. Recheck the ROCm long-context PP slope on the clean latest-upstream candidate.
6. If the ROCm PP slope remains:
   - inspect/test #28303 first where its concat shape applies;
   - inspect/test #29353 as a Qwen3.8/Strix-Halo-relevant GDN candidate.
7. Run an independent Strata Windows HIP smoke test at a convenient point; do not mix it into r4 source changes.
8. Treat ROCm 10.1.0 as a separate toolchain experiment after the current r4/upstream comparison is reproducible.
9. Revisit #25666 / #29679 only if MTP small-batch Vulkan verification remains a demonstrated bottleneck.
10. Promote only confirmed items from this research log into ROADMAP/performance-candidate documents.

