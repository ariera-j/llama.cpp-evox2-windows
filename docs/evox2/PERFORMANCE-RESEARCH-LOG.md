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


---

## 2026-10-09

### Scope, snapshots, and restart decision

Observed on 2026-10-09 JST, around 10:01-10:07. This entry supplements the
2026-10-07 research rather than replacing its historical observations.

- Document branch before this update: `r4/upstream-refresh-20261002`,
  `13245a485d0e154d82afe0126b4350ecd651e27c`.
- r4 pinned upstream remains `bed0a856606ee4a24a164066f73d2379447033f5`.
- Upstream master observed at `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`,
  committed 2026-10-08 19:56 UTC; latest build release **b11514**, published
  20:14 UTC (2026-10-09 05:14 JST), targets the same SHA.
- GitHub compare reports **144 commits ahead** of the r4 upstream pin.
  This is a snapshot, not a decision to adopt all 144 changes.
- GitHub's `releases/latest` endpoint returns the stable **v0.6.0** release.
  The newer b11514 build is marked prerelease; use the release collection and
  exact SHA when identifying the current development baseline.
- Main target remains Windows / Evo-X2 / gfx1151 / Qwen3.8-Flash-Next,
  primarily real-document 128k/256k, f16 K/V, single sequence.

**Restart conclusion:** preserve r4 and its measurement branches; establish a
separate clean current-upstream comparison, then audit the necessary downstream
deltas. Follow the existing [ROADMAP restart policy](ROADMAP.md#planned-restart-sequence-after-the-qwen35-long-context-study):
COMMON-001 if still needed, then COMMON-003/VULKAN-001 and a matched
AgentionAI/Unsloth comparison. The 10/07 entry's provisional MTP-first ordering
must not be read as a requirement to solve all MTP overhead before that baseline.
MTP correctness remains a gate for adopting MTP changes, not a blocker to an
independent MTP-OFF baseline.

This update is research only: no upstream repin, implementation, branch merge,
toolchain change, or new Windows benchmark was performed.

Snapshot sources:

- https://github.com/ggml-org/llama.cpp/commit/de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b
- https://github.com/ggml-org/llama.cpp/releases/tag/b11514
- https://github.com/ggml-org/llama.cpp/compare/bed0a856606ee4a24a164066f73d2379447033f5...de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b

### Carry forward the completed CLI/bench investigation

The newer measurements are on
`investigation/vulkan-qsa-union-stats-20261008`, observed at
`979ef17eeff14440a58c866a966b355a1b63b17e`; they are not part of the document
branch's implementation. Preserve that distinction when choosing a new base.

| Measurement path, grouped-union ON | 64k PP, tok/s | 256k PP, tok/s |
|---|---:|---:|
| Earlier real-document llama-cli | 337.45 | 268.10 |
| b11427 real-document llama-bench | 337.68 | 270.42 |
| b11427 random-token llama-bench | 316.10 | 213.42 |

The historical 256k tool gap is now substantially explained by **input workload
dependence**, with real-document bench reproducing CLI's performance band.
This is not a token-for-token equivalence claim: bench uses raw tokenization and
head-tail slicing, without CLI's chat template.

The b11433 diagnostics directly support the union-size explanation: at 256k,
group-weighted unique union size was 19,703.62 for real text and 32,875.50 for
random tokens (**+66.85%**), with no dropped groups. The diagnostic run includes
extra copies/readback and must not be used to calculate a normal ON/OFF speedup.
It does not assign all PP differences to union work.

The 64k grouped-union-OFF comparison also reproduced the opposite input ranking:
real 269.119772 versus random 306.514502 tok/s (**random +13.90%**), after
reversing run order and using warmup plus two samples per input.
`GGML_VK_MOE_LEGACY_TILE_SELECTION=1` was fixed. The mechanism behind this
OFF-path ranking remains open; it is not evidence that random input is always
a pessimistic benchmark.

The independent 10/03 MoE tile CLI ABBA measured 248.475 -> 268.985 tok/s
(**+8.25%**). The separate bench figures 243.34 -> 268.81 are consistent in
direction, but differ in build/warmup and must not be presented as a controlled
MoE-only speedup.

**Priority consequence:** do not reopen the old CLI/bench gap as unexplained
tool overhead. Retain real-input bench as an optional comparison aid; keep
llama-cli as the primary first-pass speed/output check. Further document-genre,
non-repeated-text, layer-level, and union-OFF mechanism studies are optional
investigations, not prerequisites for resuming r4. Real-input bench support and
union diagnostics remain separate potential ports; diagnostics-OFF performance
still needs its own confirmation before promotion.

Pinned local evidence:

- [Real-input bench and 10/09 results](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/979ef17eeff14440a58c866a966b355a1b63b17e/docs/evox2/R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md)
- [Union diagnostic status](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/979ef17eeff14440a58c866a966b355a1b63b17e/docs/evox2/R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md)
- [MoE tile ABBA](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/979ef17eeff14440a58c866a966b355a1b63b17e/docs/evox2/R4-MOE-TILE-AB-2026-10-03.md)

### Merged upstream changes to account for in a clean baseline

All states below were checked against the PR API. Reported gains belong to the
PR authors' hardware and workloads; none is an Evo-X2 Windows result from this
research.

| Item | Status / date (UTC) | Relevance and next action |
|---|---|---|
| [#30087: recurrent GDN kernel](https://github.com/ggml-org/llama.cpp/pull/30087) | Merged 10/08 | New baseline candidate. Final patch assigns four state columns per warp and adjusts launch occupancy. It changes shared CUDA/HIP source without a CUDA-only guard around the new mapping. qwen4exp calls the recurrent attention builder, so relevance is supported by source; gfx1151 performance and numerical behavior still require validation. |
| [#28713: TOP_K dispatch](https://github.com/ggml-org/llama.cpp/pull/28713) | Merged 10/08 | QSA/indexer relevance, but the large published gains are NVIDIA results. HIP deliberately keeps the 1024-column bitonic threshold and disables the new CUDA-only few-row shortcut. The radix path gains bounded temporary-buffer chunking. Do not forecast the CUDA speedups for ROCm. |
| [#30097: shared NextN tensor flags](https://github.com/ggml-org/llama.cpp/pull/30097) | Merged 10/07 | qwen4exp and other models accept trunk-only files through common detection. Loading compatibility improvement; it does not by itself establish compatibility with every published Unsloth shared or dense MTP sidecar. |
| [#30107: Vulkan TOP_K edge cases](https://github.com/ggml-org/llama.cpp/pull/30107) | Merged 10/08 | Correctness fix for non-finite input and negative-value k=1 selection. Includes Radeon 8060S/RADV tests. Useful refresh coverage, but not a demonstrated fix for the local ROCm MTP A/B divergence. |
| [#30003: sparse FA on coopmat2](https://github.com/ggml-org/llama.cpp/pull/30003) | Merged 10/08 | Extension of #29639 for NV cooperative-matrix-2. Low direct relevance to the current AMD path; not equivalent to downstream grouped-union. |
| [#29887: GPU cache for host MoE experts](https://github.com/ggml-org/llama.cpp/pull/29887), [#30112: multiple GPUs](https://github.com/ggml-org/llama.cpp/pull/30112) | Merged 10/07 and 10/08 | Optional host-offload feature. #29887 caches experts for batches up to 32 tokens; large batches keep regular offload. With the current full-offload / `-ncmoe 0` setup, do not expect the published offload gains. More relevant to a later constrained-memory study. |
| [#29958: k-pool graph shape stability](https://github.com/ggml-org/llama.cpp/pull/29958) | Merged 10/05; supplemental finding | Omitted from the previous intake. Makes qwen4exp pooled-key scatter/gather graph construction stable across cache-sharing states. Relevant when reviewing COMMON-004 and MTP/cache changes; graph re-reservation and CPU layout invalidation are different costs. It does not prove that the local dense-indexer omission or no-op invalidation fixes are obsolete. |

For #30087, the opening description retains a two-column explanation and early
RTX 4090 numbers, while the final patch and subsequent discussion use four
columns. Use the merged code as the implementation reference. The author reports
roughly 8% Qwen3.8-27B PP gains for the four-column experiment on RTX 4090, not
on Strix Halo; FP32 reduction order changes. #29353's chunked GDN proposal remains
a separate, unmerged kernel and its gains must not be added to #30087's figures.

Previously recorded changes were rechecked and remain merged:
[#29936](https://github.com/ggml-org/llama.cpp/pull/29936) MoE tile revert,
[#29825](https://github.com/ggml-org/llama.cpp/pull/29825) indexer memory reduction,
and [#29639](https://github.com/ggml-org/llama.cpp/pull/29639) quantized-K/V sparse
Vulkan FA. The tile revert remains a strong reason to compare clean upstream
before carrying the local legacy-selection workaround forward.

[#27962](https://github.com/ggml-org/llama.cpp/pull/27962), HIP IQ2/IQ3 SWAR
optimization, appeared in the recently updated search results but was merged
on **2026-09-22**. It is not a newly landed October optimization.

### New open candidates: scope before speedup

These are **WATCH-UPSTREAM / applicability investigations**, not approved ports.

| Candidate | Observed status | Evidence and applicability to this project |
|---|---|---|
| [#30149: tiled Vulkan transposed CONCAT](https://github.com/ggml-org/llama.cpp/pull/30149) | Open, Draft | Adds a tiled path for eligible dim-0, non-quantized 4-byte transposed input. W7800/RADV results show increasing PP benefit with larger ubatches; Qwen3.8-27B pp2048/ub2048 is about +3.2%. qwen4exp's `build_conv_state_at` explicitly constructs `concat(state, transpose(x), 0)`, so this is a concrete profiling lead, not just a model-family guess. Check actual tensor strides/widths and Windows 8060S timing first. |
| [#30139: recurrent state views](https://github.com/ggml-org/llama.cpp/pull/30139) | Open | Avoids identity GET_ROWS copies of recurrent state, with graph-reuse and read/write ordering safeguards. qwen4exp uses `build_rs`, making it a plausible TG candidate on both backends. Published single-sequence gains are generally small and CUDA-based. This is recurrent-state copying, not the QSA pooled-key gather already investigated locally. |
| [#30191: query-row slicing at deep KV](https://github.com/ggml-org/llama.cpp/pull/30191) | Open, Draft; created 10/08 | Serializes large FA dispatches into 512-query slices; W7800/RADV Qwen3.8-27B pp2048 at depth 16k reports about +10% at ub1024 and +27% at ub2048. Gate excludes sparse FA, GQA rewriting, and split-K. Therefore it is **not a direct grouped-union optimization** for Flash-Next. Retain for eligible dense/fallback paths or dense-model comparisons only. |
| [#30190: fold verify tokens with GQA heads](https://github.com/ggml-org/llama.cpp/pull/30190) | Open, Draft / RFC; created 10/08 | Opt-in coopmat1 path for GQA-6, 2-8 tokens, masked dense FA and split-K. Reports +14.6% MTP TG for Qwen3.8-27B on W7800/RADV. Its narrow shape gate is not established for the actual Flash-Next target/draft, and the PR retains unresolved deep-KV NMSE observations and no token-exact equivalence claim. Watch; do not port based on its headline gain. |
| [#30146: small-N split-K heuristic](https://github.com/ggml-org/llama.cpp/pull/30146) | Open, Draft | RDNA3/4 regular MUL_MAT tuning; tests are gfx1100/RADV. Routed MUL_MAT_ID is unaffected, and large-ubatch/TG controls are flat. Conditional small-batch/MTP lead, not evidence of a gain for the current ub1024 long prefill. |
| [#30141: MTP hidden-state save/restore](https://github.com/ggml-org/llama.cpp/pull/30141) | Open | Checkpoint restoration currently leaves speculative hidden state stale; proposal restores pending and verification hidden rows. Direct correctness watch for checkpoint workflows. Current checkpoint-disabled fresh-prompt runs do not establish this as their failure cause. |
| [#30103: CUDA/HIP FA race fix](https://github.com/ggml-org/llama.cpp/pull/30103) | Open | Addresses a tile-processing race for a particular `nbatch_combine` / head-dimension relation, linked to a gfx1201 backend-test failure. Inspect the actual ROCm FA specialization if reopening numerical divergence; no reproduction on this Evo-X2 has been established. |
| [#27218: native HRX backend](https://github.com/ggml-org/llama.cpp/pull/27218) | Open, Draft; updated 10/08 | Larger AMD/ROCm backend proposal. Keep on a long-term watch list; this intake does not establish Windows/gfx1151/Flash-Next coverage or a ready replacement for the working HIP backend. |

The 10/07 open list was also rechecked:

- [#28303](https://github.com/ggml-org/llama.cpp/pull/28303), HIP tiled F32
  CONCAT, remains open. Its Windows 8060S hardware match remains stronger than
  #30149's, but its width/stride gate must still match the model.
- [#29353](https://github.com/ggml-org/llama.cpp/pull/29353), chunked CUDA/HIP GDN,
  remains open. Retain the reported 8060S Qwen3.8-27B pp2048/4096 gains of
  6.75%/6.98% as external evidence, not as a Flash-Next 128k/256k prediction.
- [#29187](https://github.com/ggml-org/llama.cpp/pull/29187), GDN projection
  fusion, remains open and is Draft; no reason to promote it ahead of measured
  bottlenecks.
- [#25666](https://github.com/ggml-org/llama.cpp/pull/25666) and
  [#29679](https://github.com/ggml-org/llama.cpp/pull/29679), Vulkan small-batch
  MMVQ changes, remain open. Reproduce the relevant verify shape before porting.
  The latter's Windows-driver match remains useful, but its tests are on a
  7900 XTX and do not measure routed MUL_MAT_ID.

### Source audit: downstream work that is still distinct

This is a targeted audit at the observed upstream SHA, not a full port review.

| Existing item | Finding | Provisional classification |
|---|---|---|
| COMMON-001, split PLE16 | `qwen4exp.cpp` still loads a joined `per_layer_token_embd.weight` with lazy-read flags; the inspected loader has no split-head fallback. Lazy row prefetch is not split-PLE16 support. | Still-needed compatibility candidate; use Original for a genuinely clean baseline, then validate a minimal PLE16 port. |
| COMMON-003 / VULKAN-001, ROCmFPx | Current upstream `ggml.h` has MXFP4/NVFP4 but lacks the fork's `GGML_TYPE_Q4_0_ROCMFP4` and `GGML_TYPE_Q4_0_ROCMFP4_FAST` entries (100/101 in the inspected fork). Generic FP4 support does not establish AgentionAI ROCmFP4-FAST compatibility. | Retain the planned format/core audit and backend work after the baseline; not already upstreamed. |
| COMMON-004 | Pooled-key reuse is already upstream, with #29958 further stabilizing graph construction. | Do not restore the old full patch; examine only a demonstrated residual cost. |
| COMMON-005 / ROCm long-context PP | `ggml_cuda_flash_attn_ext_mma_f16_shall_use_sparse` still returns false under `GGML_USE_HIP`; mask compaction rejects HIP too. CUDA sparse support is not a HIP solution. | Recheck ROCm PP depth scaling on the new baseline, then profile FA versus GDN/CONCAT/TOP_K. Keep historical single-token compaction distinct from a PP design. |
| VULKAN-002, grouped-union | Current Vulkan source has sparse FA but no downstream `GGML_VK_QSA_UNION` path. #30003 does not add that path. | Retain as a separately measured port candidate; input dependence is now evidenced. |
| COMMON-002, MTP | #30097 helps tensor detection, while the inspected MTP graph still uses its own model embedding and constructs k-pool input from general indexer conditions. Sidecar loading, dense-draft indexer omission, and target no-op invalidation require separate review. | Do not retire the validated local work or claim universal sidecar compatibility from the new loader helper. |

The preserved r4 record still has an unresolved ROCm 256k MTP A/B output and
acceptance difference, plus MTP PP overhead. Today's public PRs are leads, not
proof of their cause or resolution.

Pinned source references:

- [qwen4exp model and graph](https://github.com/ggml-org/llama.cpp/blob/de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b/src/models/qwen4exp.cpp)
- [CUDA/HIP FA selection](https://github.com/ggml-org/llama.cpp/blob/de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b/ggml/src/ggml-cuda/fattn.cu)
- [Current ggml types](https://github.com/ggml-org/llama.cpp/blob/de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b/ggml/include/ggml.h)
- [Current Vulkan backend](https://github.com/ggml-org/llama.cpp/blob/de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b/ggml/src/ggml-vulkan/ggml-vulkan.cpp)
- [Fork ROCmFP4 types](https://github.com/LaurentZuijdwijk/llama.cpp/blob/11bfe8a633fa02bac251db6cf21bd5ddab282a64/ggml/include/ggml.h)

### Related engines and toolchain updates

**Unsloth mix:** latest observed
[b11505-mix-5209c9f](https://github.com/unslothai/llama.cpp/releases/tag/b11505-mix-5209c9f),
published 2026-10-08 23:42 UTC / 10/09 08:42 JST.
Its release manifest still includes
[#240](https://github.com/unslothai/llama.cpp/pull/240) for shared/self-contained
Qwen MTP heads. That PR remains open: inclusion in a mix build and merge into
mainline are different facts. The newer manifest also lists
[#253](https://github.com/unslothai/llama.cpp/pull/253), removing a CUDA graph-cache
count cap that caused tensor-split regressions. The reported issue does not
affect single-GPU or layer-split runs, so it is not evidence of a large gain on
this Evo-X2. #241 remains open, but use the actual release manifest rather than
assuming the 10/07 pin set is unchanged. Retain mix as a compatibility/performance
reference, not a clean upstream baseline.

**Strata:** latest observed
[v0.1.41](https://github.com/Niko1221/Strata/releases/tag/v0.1.41),
published 2026-10-08 12:14 UTC. The more immediately relevant Windows AMD changes
were in [v0.1.40.3](https://github.com/Niko1221/Strata/releases/tag/v0.1.40.3):
bundled HIP dependencies are placed beside the executable and runtime selection
is logged; automatic expert-cache sizing on 16-GB-or-larger AMD cards retains
more free VRAM. These respond to RX 7800 XT/7900 XT reports, not verified
Evo-X2 results. v0.1.41's large speed claims mostly concern multi-GPU,
NVIDIA short prompts, or memory-constrained streaming. Keep a separate current
Windows HIP smoke test as an external reference; no new evidence here justifies
replacing the llama.cpp plan or predicting its long-context throughput.

**Halogen:** current README/changelog is at **0.17.3**, beyond the 10/07 note's
0.17.0 era. 0.17.2 reports faster new-text long prompts and decode, and adaptive
per-conversation MTP depth by default; 0.17.3 reports faster sampled decode.
Greedy output identity is the project's claim; sampled seeded text can change
between releases. It remains a native-Linux reference for the normal Windows
workflow. Adaptive draft depth is worth tracking as a later design idea, after
local MTP correctness and actual net latency are understood.

- https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md
- https://github.com/peonist-ai/halogen-flash-server/blob/main/README.md

**LaurentZuijdwijk fork:** default-branch tip remains
`11bfe8a633fa02bac251db6cf21bd5ddab282a64` from 2026-09-07.
No new default-branch refresh was found. Keep its specialized format/kernels
as reference for COMMON-003/VULKAN-001.

**ROCm / TheRock:** AMD's official current documentation remains **10.1.0**,
released 2026-10-05. The matrix still lists Radeon 8060S/gfx1151, Windows 11
25H2 and Adrenalin 26.10.41.05. Preserve the accepted 10.0/26.8.1 baseline.

A refinement to the earlier memory note matters: the 10.1 release notes say
Windows host registration now defaults to fine-grained, uncached memory, and
coarse-grained behavior requires the explicit
`hipExtHostRegisterCoarseGrained` flag. This is a semantics/correctness change,
not an automatic speedup. Inspect the actual allocation/registration path before
a separate toolchain A/B; do not combine that experiment with a source repin.

- https://rocm.docs.amd.com/en/latest/about/release-notes.html
- https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html

### Provisional next sequence

1. Preserve r4, the investigation branches, runtime hashes, and existing results.
   At the actual start of build work, recheck the upstream SHA and pin the
   separate clean comparison explicitly.
2. Run minimum load/short-output gates and matched real-document measurements,
   primarily 128k, with 64k support and 256k for depth scaling. Keep MTP OFF,
   f16 KV, driver/toolchain, sampling, and input identity fixed for the first
   comparison. Use the joined Original model until a minimal PLE16 port is
   separately validated.
3. Reclassify the existing deltas against the new base: MoE legacy selection is
   an upstream-retirement candidate; COMMON-004 is already substantially
   upstream; COMMON-001, ROCmFPx, and grouped-union remain distinct.
4. Follow the ROADMAP's specialized-format sequence: minimal COMMON-001 if
   needed, then COMMON-003/VULKAN-001, then matched AgentionAI versus Unsloth
   speed and long-context quality checks. This research does not reorder those
   tasks around every newly posted general optimization.
5. For any remaining ROCm PP slope, measure the dominant operators before
   choosing an experiment. #30087 is already in the clean baseline; #28303 and
   #29353 are isolated watch/test candidates, while sparse FA still lacks the
   inspected HIP path. GDN/CONCAT gains alone would not prove the context-depth
   problem solved.
6. Watch #30149/#30139 and the narrower #30190/#30191/#30146 rather than
   duplicating their active upstream work. Escalate correctness issues using
   the ROADMAP exception only if their triggering conditions are reproduced.
7. Keep Strata, ROCm 10.1, quantized KV, and broader MTP tuning as independent
   experiments. Promote findings into ROADMAP or implementation plans only
   after applicability and priority review.

Validation for this entry: GitHub PR states/releases, targeted source reads,
and existing repository measurement documents were checked. No newly reported
third-party speedup has been validated on the user's Windows hardware.


---

## 2026-10-11 — r5 post-FA investigation priority refresh

**Research intake date:** 2026-10-11 JST. **Target:** GMKtec Evo-X2 / Radeon 8060S (gfx1151), Windows 11, Qwen3.8-Flash-Next UD-IQ3_XXS PLE16 GGUF, 96GB UMA, r5 pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`. All external statuses and third-party performance reports below are an **upstream watch snapshot**, not results measured on this Evo-X2 or a proposal to rebase r5 now. Prior 2026-10-09 plans were made before the full 64k/128k corpus study and the 2026-10-11 Vulkan GPU mask investigation.

### Newly completed local evidence changes the question

- **Experimental tooling:** a selective r5 port added real-text `llama-bench -f/--prompt-file` with `--prompt-slice head/head-tail` and explicit `-c`. Its short Windows smoke and use in 64k/128k studies passed. This resolves the previous major random-token bench versus real-input `llama-cli` workload mismatch as the explanation for much of the apparent tool gap; do not resume that comparison as a generic unresolved performance defect.
- **Vulkan union speed, not just statistics:** same-build 64k seven-corpus QSA union OFF/ON A/B completed 14/14; repeat 64k ABBA on Japanese ANLP, source code and native random reproduced ON gains **+25.812% / +14.736% / +4.899%**, respectively. 128k six-corpus OFF/ON A/B completed: **+46.784% to +74.945%** across corpus types. ON-path union unique/padded work differs substantially by input. Source: [r5 corpus speed A/B](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md), [seven-input union histogram](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md), [128k union statistics](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md).
- **ROCm was the contrasting backend:** on 64k real/random inputs, ROCm throughput ranged **394.030–415.821 tok/s** (5.5% max/min spread), against Vulkan union OFF 20.9% spread and ON 17.2%. At 128k ROCm ranged **296.075–308.215 tok/s** (4.1%) versus Vulkan OFF 40.5% and ON 32.5%; notably **Vulkan union ON beat ROCm on four of six** matched 128k inputs, so ROCm cannot be described as universally faster. Absolute backend measurements were from different sessions/binaries/ambient conditions; no cross-backend per-kernel speed claim follows. Source: [r5 64k/128k backend comparison](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md).
- **Vulkan OFF input dependence attributed to Flash Attention:** same-shape host FA dispatch census for 64k Japanese literature and llama.cpp C/C++ was identical (**732 calls**, regular FA-coopmat1, `mask_opt=1`, `sparse=0`, `Br/Bc=16/64`, `split_k=1`). GPU op logger totals showed `FLASH_ATTN_EXT` **102.460 s** literature vs **69.565 s** code; this **32.895 s** difference exceeds the overall GPU op-time difference (**29.537 s**) because other operations partly offset it. At matched `Qcur-19 KV=49152 N=1024`, two repeated RGP captures showed main FA **314.071/310.968 ms** literature against **75.840/75.990 ms** code (~4.14×/4.09×), with nearly equal mask-prepass durations. One-shot mask snapshot classified `ALL_NEG_INF` **17,538/49,152 = 35.68%** literature against **36,881/49,152 = 75.03%** code; the code is more skip-eligible in **all 64 query-tile rows**. This strongly supports mask-tile elimination as a contributor, without claiming that count ratio (~2.58× non-skippable) mathematically explains the ~4.1× single-kernel time ratio. Source: [archived r5 FA diagnosis](R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md).
- The full Vulkan RGP/mask instrumentation remains in `investigation/r5-vulkan-off-fa-dispatch-20261010`; **stable r5 has the report only**, not those debug source changes. The previously completed r4 real-prompt and QSA-union-statistics investigations were selectively ported to r5 and historical documents archived; donor branches can be retired after preserving refs.

### Fresh upstream checks (GitHub status as observed 2026-10-11)

| Source | Observed update/status | Project interpretation / next gate |
| --- | --- | --- |
| [llama.cpp #30103](https://github.com/ggml-org/llama.cpp/pull/30103), CUDA/HIP Flash Attention tile race fix | **Merged 2026-10-10**, correcting `flash_attn_ext_f16_process_tile` when `nbatch_combine != DKQ/2`. | Later than the frozen r5 upstream pin; check applicability to the *selected HIP FA specialization* at the next refresh. Do not claim it changes the measured r5 performance or that Evo-X2 reproduced the race. |
| [llama.cpp #30280](https://github.com/ggml-org/llama.cpp/pull/30280), RDNA3/4 Vulkan large-tile Split-K | **Open**, created 2026-10-10. Reports end-to-end PP gains on W7800-family/discrete AMD GPUs for eligible large-tile **matrix multiplication**. | **Not Flash Attention Split-K**; relevance to gfx1151 + Qwen3.8-Flash-Next needs eligible `MUL_MAT` shape/device-path proof. Watch upstream; no immediate FA port. |
| [llama.cpp #29353](https://github.com/ggml-org/llama.cpp/pull/29353), CUDA/HIP chunked GDN | **Open**, recently updated. Reports **+6.75/+6.98%** on Radeon 8060S for **Qwen3.8-27B**, PP2048/4096, `ubatch=2048`. | Plausible HIP PP improvement, **not yet measured for Flash-Next with ubatch 1024** or for deep 64–256k. Consider only after a ROCm operator-time attribution and shape/ubatch check. |
| [llama.cpp #28303](https://github.com/ggml-org/llama.cpp/pull/28303), tiled F32 transposed CONCAT on RDNA3.5 | **Open**; Windows Radeon 8060S results report **+5.54–9.92% PP** for eligible Qwen3.6-35B-A3B. | Hardware match is strong, but model/CONCAT shape and actual ROCm hotspot must be verified; WATCH-UPSTREAM before porting. |
| [llama.cpp #30191](https://github.com/ggml-org/llama.cpp/pull/30191), Vulkan deep-KV FA query-row slicing | **Draft, open**; dense FA with specific row/KV constraints and RDNA3 device gating. | Do not assume applicability to gfx1151 or to Flash-Next QSA union, sparse paths or the diagnosed Vulkan OFF kernel without confirming guard conditions. |
| [llama.cpp #30149](https://github.com/ggml-org/llama.cpp/pull/30149), Vulkan tiled transposed CONCAT | **Draft, open**; W7800 performance results for recurrent-state tensor shapes. | WATCH-UPSTREAM; run applicable `CONCAT` profiling/shape gate first. |
| [llama.cpp #30139](https://github.com/ggml-org/llama.cpp/pull/30139), recurrent-state view in place | **Open**, targets redundant recurrent state GET_ROWS/copies. | Possible TG relevance; upstream-led and non-identical to old QSA pool gather. Verify graph semantics after upstream merge. |
| [llama.cpp #30190](https://github.com/ggml-org/llama.cpp/pull/30190), folded MTP verify tokens + GQA | **Draft/RFC, open**; opt-in, limited GQA/token/FA conditions. | External +14.6% MTP TG reported for *Qwen3.8-27B* on W7800, not yet transferable to Flash-Next. Correctness and exact gate first. |
| [llama.cpp #30141](https://github.com/ggml-org/llama.cpp/pull/30141), MTP hidden-state checkpoint save/restore | **Open**, correctness-oriented. | Watch and revalidate when using checkpoints; does not by itself explain current fresh-prompt MTP PP overhead. |
| [Unsloth llama.cpp `b11541-mix-2500203`](https://github.com/unslothai/llama.cpp/releases/tag/b11541-mix-2500203) | Published 2026-10-11 UTC, based on upstream b11541 plus mix patches. | Keep as alternate compatibility/throughput reference; not clean upstream, and no demonstrated need to switch currently validated r5 baseline. |
| [Strata v0.1.42](https://github.com/Niko1221/Strata/releases/tag/v0.1.42) | Published 2026-10-10; Windows AMD HIP guards include avoiding overly large auto prefill chunks / host commit exhaustion. Large headline TG improvements are chiefly NVIDIA or multi-GPU. | External-engine watch; no proven single gfx1151/96GB UMA/Flash-Next gain. Do not mix engine replacement into llama.cpp diagnosis. |
| [Halogen CHANGELOG 0.17.5](https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md) | Public changelog currently lists 0.17.5 (prompt-read and drafted-decoding improvements, cache/stream observability, stall fixes). | Linux-specific reference, not drop-in Windows backend; watch conceptual ideas rather than attempt a direct port. |

The pinned Windows r5 source remains unmodified by this research. Some newly merged upstream changes (especially #30103) are **not** automatically present in the pinned r5 binary. External percentages are not forecasts of an Evo-X2 / Flash-Next speedup, and 'Open'/'Draft' statuses must be rechecked when acting on them.

### Priority recommendation from current evidence

This dated intake supports, but does not replace, the active [ROADMAP priority checkpoint](ROADMAP.md):

1. **First: bounded ROCm HIP Flash Attention execution-path diagnosis** (**INVESTIGATE**, short gate). Determine the *actual* selected HIP FA specialization on gfx1151 for the matched 64k Japanese literature and C/C++, whether `scan_mask`/trailing-KV scan and Stream-K are active, and how much of the corpus-dependent PP and absolute ROCm/Vulkan gap is FA versus MoE/GDN/CONCAT. Start with source call-chain + available Windows HIP profiler/logging capability; instrument or rebuild only after confirming a clear observability gap. Reassess after a two-corpus matched-KV/result sample instead of indefinitely chasing profiler minutiae.
2. **Next: r5 upstream-native MTP status and end-to-end value** (**INVESTIGATE**, high practical impact). The r4 dense-draft indexer omission and target no-op work yielded TG benefits, but MTP PP overhead, fresh-prompt total latency and ROCm 256k output/acceptance equivalence were unresolved. Do **not** assume r4 candidate deltas are ported to r5, and do not port both before native r5 allocation, short, rollback and matched A/B checks.
3. **Then: ROCm 128k/256k PP scaling and dominant-operator profile** (**INVESTIGATE**). ROCm 64k→128k PP fell ~25% across all six inputs and prior 64k→256k results were near half-speed. Its small content-dependent spread does not imply cheap FA or prove a sole attention bottleneck. Reuse HIP FA observations and separate depth/graph/recurrent/MoE costs before choosing a local optimization.
4. **Separate feature gate: COMMON-003 / VULKAN-001 AgentionAI ROCmFP4-FAST support** (**LOCAL-CANDIDATE**, applicability dependent). Needed to compare the alternative format/model; audit pinned/current upstream type/loader/kernels first. Treat as a compatibility deliverable, not a claim of higher PP.
5. **Hold: deeper Vulkan OFF FA mask count/time discrepancy or applying ROCm-style suffix cutoffs / FA Split-K** (**DEFER/INVESTIGATE on new evidence**). The measured FA-tile phenomenon has a credible mechanism. Do not spend another long dive on the 2.58× tile-count versus 4.1× kernel-time ratio without an actionable improvement; avoid duplicative scans.
6. **WATCH-UPSTREAM** for GDN/CONCAT/large-tile matmul/MTP/recurrent-state candidates; reprioritize only when actual runtime bottleneck, applicability and a same-build A/B gate are established.

**Bounded ROCm next-chat handoff:** stay on validated stable `r5/upstream-refresh-20261009`; do not mix Vulkan investigation source or re-pin upstream. First trace `ggml-hip` → `ggml-cuda/fattn.cu`/FA specialization for the actual qwen4exp model shapes; distinguish `flash_attn_mask_to_KV_max` suffix scans, HIP-disabled CUDA sparse gather, and FA/matmul Stream-K. Second inventory Windows HIP profiling options and select the least invasive logging/timing method. Third, *only if feasible*, collect Japanese literature and code under identical ROCm binary, model, prompt SHA, KV depth and batch parameters. Record call/kernel identity and measured time separately from overall PP. Stop and re-rank if instrumentation is disproportionate to expected optimization benefit. **No source or benchmark changes are authorized by this intake alone.**

---

## 2026-10-12 — upstream, mix, Strix Halo engines, and Qwen3.8-Flash-Next research refresh

**Observed:** 2026-10-12 JST. **Research only; no source patch, rebase, test run, release tag, or ROADMAP priority decision.** Existing dated entries remain historically valid as snapshots at their stated times. Sources below are GitHub releases, PR descriptions/statuses, project changelogs, and the repository's own measurements. External speed/quality percentages are developer reports **not reproduced on this Windows Evo-X2**.

**Target/policy:** Windows 11 / GMKtec Evo-X2 / Ryzen AI Max+ 395 (gfx1151) / configured 96GB UMA; main workload Qwen3.8-Flash-Next GGUF, long 64k–256k context, Vulkan and ROCm/HIP. Stable r5 research branch is `r5/upstream-refresh-20261009`, pinned upstream `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b` (`docs/evox2/CURRENT-REFRESH.json`). The more recent isolated MTP investigation branch must not be confused with a repinned or integrated r5. Per `ROADMAP.md` / `INTEGRATION-POLICY.md`, continue bounded experiments on pinned sources; an integrated snapshot will be prepared at a natural research boundary, with planned ROCmFP4 compatibility validation in its first acceptance scope; Strata smoke comes after a validated integrated snapshot.

### 1. Change summary and immediate applicability

| Project | Current snapshot (verified on 2026-10-12) | What changed since the 2026-10-11 log | Evo-X2 / action |
| --- | --- | --- | --- |
| `ggml-org/llama.cpp` | master/automated build **b11559**, SHA `f2cc7282ce0042641df55e0e563b75e824e2b647`; released 2026-10-11 19:14 UTC (10/12 04:14 JST). **Stable** GitHub release `v0.6.0` is a separate release channel. | Merged Vulkan MoE #29998; HIP FA #30103 and MTP/graph correctness fixes in recent commits. b11559's own release-head change is an **OpenCL/Gemma-4** change, not a measured Strix Halo improvement. | **WATCH / next integration A/B**; no source repin now. |
| `unslothai/llama.cpp` | **b11541-mix-2500203**, 2026-10-11 01:24 UTC; composition starts from upstream b11541, not b11559. | Updated mix carrying Qwen shared/self-contained MTP compatibility #240, residual patches #241, MoE auto cache sizing #251. | **Compatibility reference**, not clean upstream. Native Windows `gfx1151` ROCm + Windows Vulkan archives supplied. |
| `Niko1221/Strata` | **v0.1.43**, 2026-10-11 14:40 UTC, Windows HIP release ZIP present. | gfx12/R9700 and discrete-GPU optimizations, Windows disk-streaming fix, reproducible `BENCH.bat` suite. | **CURRENTLY UNSUPPORTED on integrated Radeon GPUs per official INSTALL guide**; revisit a Windows HIP smoke only if gfx1151 support is added. |
| `peonist-ai/halogen-flash-server` | Public changelog / image **0.18.1**; main commit `a83cfbf4dee782a07ec8d3800496415b622f95d6`, 2026-10-11 23:12 UTC (10/12 JST). | 0.18.0 sessions/NPU features; 0.18.1 request/cache/scheduling/API features, with unchanged Flash checkpoints. | **Linux-only reference**, not direct Windows/WSL port or evidence of new engine PP/TG boost. |
| `vahpetr/llama.cpp-s1-fork` | Public branch `s1-public`, SHA `6fd3d69374cffe39c6572c0fe51a6f494f37e9b0`; published Oct 2026; docs report image v59. | A substantial **gfx1151-specific Vulkan + QSA + sparse-MTP + graph/cache** research fork with 1M-context measurements. | **HIGH-INTEREST source/idea audit**; different Linux/128GB/memory/weights, not directly deployable to 96GB Windows. |
| `SelfRef/llama.cpp-rdna` | Public `rdna` branch; based on LaurentZuijdwijk plus upstream refresh through Oct 7 per its README. | ROCmFPx GGUF types 100–107 plus selectively carried Vulkan RDNA3/3.5 Flash Attention and recurrent/CONCAT ideas. | **FP4 format + Vulkan comparison reference**, not a verified Windows build nor a ready-made integrated source. |

References: [llama.cpp b11559](https://github.com/ggml-org/llama.cpp/releases/tag/b11559), [Unsloth mix b11541](https://github.com/unslothai/llama.cpp/releases/tag/b11541-mix-2500203), [Strata v0.1.43](https://github.com/Niko1221/Strata/releases/tag/v0.1.43), [Halogen changelog](https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md), [s1 fork README](https://github.com/vahpetr/llama.cpp-s1-fork/blob/s1-public/README.md), [SelfRef RDNA fork](https://github.com/SelfRef/llama.cpp-rdna/blob/rdna/README.md).

### 2. Upstream source changes with a concrete test gate

**Merged (as of this research):**

- [#29998 Vulkan MUL_MAT_ID duplicate prepass](https://github.com/ggml-org/llama.cpp/pull/29998), merged Oct 11: hoists duplicate routed-MoE rows to a compact tile-description prepass rather than executing repeated row loops; author suggests only about **1%** on their system. The model has many experts, so this is relevant, but not a reason to assume a major gain on Windows AMD or that it replaces all r5 grouped-union / legacy MoE work. At integration: diff against local Vulkan MoE selection, verify eligible shapes, compare matched 64k and 128k real prompts.
- [#30103 HIP/CUDA FA race](https://github.com/ggml-org/llama.cpp/pull/30103), merged Oct 10: fixes `flash_attn_ext_f16_process_tile` when `nbatch_combine != DKQ/2`. **Correctness fix**, not established performance change or a reproduced Evo-X2 race. Check selected HIP FA specialization and geometry first, then accept at a new baseline.
- [#30160 embedding GET_ROWS graph order](https://github.com/ggml-org/llama.cpp/pull/30160), merged Oct 9: puts GET_ROWS before graph split-interleaved PAD/MUL/SCALE for mixed/token/raw embeddings, avoiding unwanted scheduling/CPU splits. This is not a split-PLE16 GGUF loader, and does not retire COMMON-001. May change PP profiles/scheduling in an integrated version.
- [#30257 mtmd input for MTP](https://github.com/ggml-org/llama.cpp/pull/30257), merged Oct 10: image/multimodal draft input no longer becomes zeros; published acceptance check uses Qwen3.5-4B image inputs. **Not** proof of text-only Qwen3.8-Flash-Next acceptance or Windows vision compatibility.
- [#30223 static backend sampling graph](https://github.com/ggml-org/llama.cpp/pull/30223), merged Oct 9: fixes inconsistent sampling graph topology/reallocation across draft ubatches; ordinary no-draft graph unaffected. Observe if experimenting with `--backend-sampling`; not a direct explanation for current default MTP TG or PP.
- [#30145 Vulkan RMS_NORM workgroup overflow](https://github.com/ggml-org/llama.cpp/pull/30145), merged Oct 9: bounds dispatch via looping; carry as correctness hygiene when relevant rather than claim unconditional PP speedup.
- [#29887 MoE host-expert GPU LRU cache](https://github.com/ggml-org/llama.cpp/pull/29887), merged Oct 7, and [#30112 multi-GPU extension](https://github.com/ggml-org/llama.cpp/pull/30112), merged Oct 8: `--moe-cache-mib N` brings selected CPU-resident experts to GPU for small batches (at most 32 tokens). Huge third-party gains are from **PCIe discrete-GPU systems with experts deliberately offloaded to host**: for Qwen3.8-Flash-Next Q4_0, 4090 25.0→39.4 t/s and 5090 30.8→54.5 t/s in #29887's examples. **Low direct benefit** in current `-ngl 999 -ncmoe 0` 96GB UMA resident-expert setup. Do not translate these percentages to Evo-X2; useful only if a new format/size causes host spill or experiments explicitly change MoE placement.

**Open upstream watch, with guards rather than speculative gains:**

| PR | Status/reported external result | Exact candidate gate |
| --- | --- | --- |
| [#29353 chunked GDN CUDA/HIP](https://github.com/ggml-org/llama.cpp/pull/29353) | Open; Radeon 8060S **Qwen3.8-27B** PP2048/4096 +6.75/+6.98%, on `-ub 2048` | Real Flash-Next operation + shape time, `-ub 1024`, long-context scaling. No 177B forecast. |
| [#28303 tiled F32 transposed CONCAT HIP](https://github.com/ggml-org/llama.cpp/pull/28303) | Open; Radeon 8060S Qwen3.6-35B-A3B +5.54–9.92% PP on selected shapes | Confirm the exact transposed concat tensors in this model and meaningful time before port. |
| [#30149 Vulkan transposed CONCAT](https://github.com/ggml-org/llama.cpp/pull/30149) | Open/draft; W7800 results | Check Vulkan recurrent/CONCAT path and isolate from QSA union/mask. |
| [#30139 recurrent-state view in place](https://github.com/ggml-org/llama.cpp/pull/30139) | Open; removes redundant GET_ROWS/copies in recurrent-state read | Potential TG not necessarily equivalent to r3 COMMON-004 pooled-key path; correctness/restore first. |
| [#30190 Vulkan MTP verify token/GQA fold](https://github.com/ggml-org/llama.cpp/pull/30190) | Open WIP; W7800/Qwen3.8-27B MTP decode +14.57% author report | Applies to narrow GQA/token/masked-dense FA geometry, **not** guaranteed for Flash-Next target/draft or grouped-union sparse paths. |
| [#30191 deep-KV Vulkan FA query slicing](https://github.com/ggml-org/llama.cpp/pull/30191) | Open/draft; W7800 at KV16384, deep prefill; dense-only selected paths | gfx1151 driver gate, `Q>512`, `KV>=12288`, ordinary dense path; no assumption for QSA sparse/union. |
| [#30146 small-N Vulkan split-K](https://github.com/ggml-org/llama.cpp/pull/30146), [#30280 large-tile split-K](https://github.com/ggml-org/llama.cpp/pull/30280) | Open; RDNA3/4 hardware/shape-specific | **Matrix multiplication split-K, not Flash Attention split-K**. #30146 is regular MUL_MAT, not routed MUL_MAT_ID; #30280 has large tile and N/K limits. |
| [#30141 MTP hidden-state checkpoint save/restore](https://github.com/ggml-org/llama.cpp/pull/30141) | Open; speculative hidden-state correctness | Track for snapshot/restore/rollback semantics; not a demonstrated cure for fresh-prompt MTP PP overhead. |

**Judgment:** #29998 is the newest MoE match; #30103 the concrete HIP correctness delta. Most larger claimed prefill gains are different model, batch, device, or tensor shape. Do not displace the bounded r5 MTP work with a collection of cherry-picks.

### 3. Unsloth mix: version and material residual differences

Official [b11541-mix-2500203 release manifest](https://github.com/unslothai/llama.cpp/releases/tag/b11541-mix-2500203) lists a **Windows gfx1151 ROCm** package named `app-b11541-mix-2500203-windows-x64-rocm-gfx1151.zip` and a **Windows Vulkan** package named `app-b11541-mix-2500203-windows-x64-vulkan.zip`. The upstream base is b11541, so the mix binary is not “newer than upstream b11559” just because it has mix-only patches.

- [Unsloth #240](https://github.com/unslothai/llama.cpp/pull/240), open and included: Qwen `qwen4exp` MTP models sharing the target's token embedding/output; self-contained ratio-zero dense head's k-pool/indexer allocation guard. The known upstream errors described by the PR include missing `token_embd.weight` in shared heads and `GGML_ASSERT(buffer)` on first decode of a self-contained dense head. **This is directly related to the user's independently validated r5 dense-head compatibility branch**, not an instruction to blindly duplicate all of #240.
- [Unsloth #241](https://github.com/unslothai/llama.cpp/pull/241), open/included: shape-aware CUDA graph caching and a number of residual features from upstream-superseded pins. Differentiate these from wholesale Unsloth MTP support already upstream and from current Windows Vulkan/HIP observations.
- [Unsloth #251](https://github.com/unslothai/llama.cpp/pull/251), open/included: `--moe-cache-mib auto` sizes upstream's GPU expert cache from `--fit`, only for single GPU / no explicit `-ngl`, `-ts`, `-ot`; recommends load mode `none` for fast host-to-GPU misses. **Does not activate in the user's explicit `-ngl 999` setup**; not a next-step win for UMA resident experts.
- Existing mix-only HIP iGPU memory behavior and sampling changes should remain isolated reference topics. Do not use generic “newer mix faster” claims in place of matched real-input, fixed binary A/B; match actual source pin, model, driver, quant, prompt, KV, and draft settings.

### 4. Strata v0.1.43: practical readiness vs marketing headline

Sources [v0.1.42](https://github.com/Niko1221/Strata/releases/tag/v0.1.42), [v0.1.43](https://github.com/Niko1221/Strata/releases/tag/v0.1.43), [official installation compatibility matrix](https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md#amd-cards).

- **Important blocker found in official documentation:** the AMD install guide explicitly states **“Integrated Radeon GPUs are listed as not supported”**; the listed architectures are discrete gfx1100/gfx1101/gfx1200/gfx1201/gfx1030, not gfx1151. A Windows HIP archive **existing** does **not** establish that this Strix Halo iGPU is runnable. The previously planned external-engine smoke is now **conditional on a future gfx1151 enablement or an explicitly supported developer workaround**, not merely a timing experiment.

- Windows `strata-windows-x64-hip.zip` remains available. v0.1.42 limits Windows AMD **automatic** prefill chunks to 6,144 (RX7900 XTX high Windows commit/reservation crash at 8,192; developer notes a trade-off in prompt speed) and adds commit/free-memory warnings. Unified-memory APU setups now use conservative explicit cache values; authors do **not** claim tested Strix Halo Windows hardware.
- v0.1.43 reports AMD Radeon AI PRO R9700 (gfx1200/gfx1201 RDNA4) IQ3_XXS improvements up to +38% TG in constrained cache configurations, and other 64k PP gains on R9700. Its notes expressly retain older RDNA3/gfx11 behavior rather than supplying an equivalent gfx1151 A/B. The headlines **must not be relabeled as Evo-X2 gains**.
- A Windows GGUF in-place expert streaming fix removes serialized NTFS unbuffered shard reads; measured on RTX5070 with experts needing file/RAM tiers: 1.35–1.85x developer-reported decode improvement. For models resident in Windows Evo-X2's UMA this is largely a different bottleneck.
- New `BENCH.bat` / `tools/strata_bench.py` (4k/16k prompts, short chat, five-turn agent, optional long/client count) enables later reproducible cross-engine assessment. User's long 64/128/256k corpus suite still needs a separate engine-neutral timed setup.
- **Do not install or benchmark now as a dependency for MTP-NOOP**. If a future release explicitly enables integrated gfx1151, first verify device detection and AMD/HIP runtime, ROCm/HIP DLL source, model load, requested context, PLE and MTP, GPU versus CPU routing, and text correctness **before** interpreting timings.

### 5. Halogen 0.18.1: software/service changes, not a portable engine patch

Sources [CHANGELOG 0.18.1](https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md), [README](https://github.com/peonist-ai/halogen-flash-server/blob/main/README.md).

- **0.17.5** reported faster prompt reading and drafted decode, prompt/cache metrics and stream stall fixes; keep its performance claims distinct from subsequent changes.
- **0.18.0** added opt-in fork/join sessions, NPU Qwen3-ASR transcription, larger Flux images, and prompt-cache rewrite fix for agent clients.
- **0.18.1** adds JSON/schema constrained sampling above temperature 0, cache-avoiding `prompt_cache_policy: "no_store"`, retry-resume after disconnect, opt-in Claude Code sessions, and shorter-request scheduling during long prefills. **Flash checkpoints unchanged**, and README says greedy output preserved. Treat mainly as serving/observability design ideas, not a newly demonstrated intrinsic Qwen PP/TG step-change.
- Native Linux amdGPU/KFD context; Windows 11 / WSL2 not a supported drop-in execution target. Quantization, memory budget, context/caching and hardware can differ substantially from local r5, so raw Halogen leaderboard numbers cannot be used as a fair r5 A/B.

### 6. New Strix Halo-specific fork: high-value research, but not a like-for-like benchmark

Primary sources: [s1 README](https://github.com/vahpetr/llama.cpp-s1-fork/blob/s1-public/README.md), [measured suite](https://github.com/vahpetr/llama.cpp-s1-fork/blob/s1-public/docs/s1/BENCHMARKS.md), [numbered 226 patches](https://github.com/vahpetr/llama.cpp-s1-fork/blob/s1-public/docs/s1/PATCHES.md), [weights/memory](https://github.com/vahpetr/llama.cpp-s1-fork/blob/s1-public/docs/s1/WEIGHTS.md).

- Machine is **Ryzen AI Max+ 395 with 128GB physical memory, Linux Ubuntu/RADV Vulkan, 110GiB GTT**, host kernel/`amd_iommu` tuned. Weights are **Qwen3.8-Flash-Next-Uncensored i1-Q4_K_M** with n-gram PLE in CPU memory and a **privately vocabulary-pruned MTP draft head**, KV q8_0, YaRN ×4. **Not** the user's Windows 96GB UMA, Unsloth UD-IQ3_XXS PLE16, unpruned Q8 draft, f16 KV.
- Developers report current implementation **61 tok/s cold TG**, **45 tok/s TG at 524k**, **35.5 tok/s TG near 1M**; **524k fill ~25.6 min**, **1M fill ~1.09h**, steady **102.7GiB GTT at 1M**, 8k PP ~550 tok/s. Reports include single-run experiments and some paired per-lever gates; “stock” column uses other quants/older dates, so it is **not an equal-model/equal-platform before/after**. 1M accuracy is not fully validated; 1M exceeds 262k native context through extension.
- Main engineering ideas: indexer-driven sparse QSA ~2,051 selected cells/query, efficient incremental QSA census, indexed prefill and compact KQ mask, sparse MTP draft, faster QSA top-k selection, cache-optimized graph/allocation plans and recurrent checkpoints/disk prompt caching. Their per-lever gates report **MTP 23.4 vs 35.1 ms/token at 81k**, QSA-specific improvements at deep context and **graph+plan cache −5.8% ms/token**; these are on **their own Linux build**.
- **Memory mismatch matters:** 102.7 GiB of GPU memory already exceeds the user's manually configured **96GB UMA allocation**. Not a drop-in 1M solution; Windows driver/WDDM/GTT semantics also differ. No HIP path for fork's new kernels.
- Suggested later **read-only narrow code audit**: (1) sparse draft + no-op/catch-up semantics compared with r5 MTP-DENSE/NOOP, (2) QSA top-k/census/pooled-key copy elimination, (3) GPU FA/MoE transposed kernels and model/shape gates, (4) graph/plan cache and recurrent checkpoint correctness. Compare with existing upstream and r5 patches before borrowing ideas; isolate each and measure on the **same Windows r5 build/model**. Do not attempt to import 226 patches or copy benchmark headline.

### 7. FP4 / ROCmFPx specialization reference

[SelfRef/llama.cpp-rdna](https://github.com/SelfRef/llama.cpp-rdna/blob/rdna/README.md) explicitly targets **gfx1100/gfx1101/gfx1151** and assembles LaurentZuijdwijk's ROCmFPx type IDs **100–107** (`Q4_0_ROCMFP4*` and `Q2/Q3/Q6/Q8_0_ROCMFPX`) with upstream refreshed to 2026-10-07 and several measured Vulkan coopmat1 FA/CONCAT and recurrent patches. This is useful for the first-integration **COMMON-003 / VULKAN-001 ROCmFP4-FAST loading/kernels audit**, because upstream generic NVFP4/MXFP4 support must not be mistaken for matching proprietary fork GGUF type IDs and data layouts.

The README's +33–38% TG comparison involves **RX7900XTX, Qwen3.8-27B, ROCmFP4-FAST vs Q4_K_M**, not Flash-Next on Windows gfx1151; its “matched output” caveats are model/quant specific. It also documents rejecting a checkpoint patch after a measured −23%/−24% decode regression and different greedy output. Important lesson for r5: **benchmark/rollback correctness beats patch count**. No ROCmFP4 or RDNA fork kernels have been incorporated or validated here.

### 8. Update to active experiment priority and acceptance gates

**2026-10-12 local experiment checkpoint (new since the preceding log):** [r5 MTP-DENSE-001 report on the isolated branch](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-mtp-dense-indexer-20261011/docs/evox2/R5-MTP-DENSE-INDEXER-PORT-2026-10-11.md) closes Windows ABBA validation: 3 context lengths × 2 backends × 4 OFF→ON→ON→OFF = **24/24 OK**. Dense-indexer omission enabled **only for eligible ratio-zero MTP indexer**. Relative *MTP ON TG* improvements:

| Context | Vulkan: DENSE OFF → ON TG (tok/s) | Delta | ROCm: DENSE OFF → ON TG (tok/s) | Delta |
| --- | --- | --- | --- | --- |
| 64k | 29.275 → 31.270 | **+6.81%** | 25.840 → 27.835 | **+7.72%** |
| 128k | 23.420 → 27.055 | **+15.52%** | 18.050 → 21.195 | **+17.42%** |
| 256k | 15.490 → 21.100 | **+36.22%** | 11.160 → 13.780 | **+23.48%** |

Vulkan ABBA response text/acceptance were identical; **ROCm temp0 generated text and acceptance varied even between same-arm controls**, so distinct output remains its own determinism investigation. DENSE-001 has minimal impact on PP: it does **not** remove the baseline MTP ON prefill overhead (~7–9% PP rate loss in earlier r5 native ON/OFF 64k/128k tests), nor prove fresh-prompt 512-token end-to-end latency is improved. The user intentionally did not run a new 256k MTP-OFF baseline. The MTP investigation binaries embed a distinct local `b11566` build label, **not an upstream/master rebase of stable r5**. Retain native and source provenance by branch; no invented cross-version ratios.

**Recommended order, consistent with the user-selected work and ROADMAP rather than an imposed deadline:**

1. **MTP-NOOP-001 next (isolated branch)**. Source-review r4 target-context QSA no-op invalidation first; fix DENSE-001 ON as control, NOOP default OFF/fail-closed; run native rollback/acceptance, text correctness and Vulkan ABBA before drawing HIP speed conclusions. Preserve ROCm's existing nondeterminism as independent evidence.
2. **Then MTP ON PP and ROCm deep-context path attribution**. Distinguish draft prefill cost, target QSA, HIP Flash Attention selected kernel/race applicability, GDN/CONCAT/MoE and 64k→128k→256k depth behavior. Use actual operator timing and 2–3 representative text corpora, not all branches of speculative upstream.
3. **Prepare first integrated snapshot at a natural stopping point**: recheck then-current upstream pin (today's b11559 is **observation, not a selected future pin**); port mandatory PLE16; assess demonstrated local beneficial patches and ROCmFP4-FAST support (common format/core, Windows HIP kernels, optional Vulkan); validate model load, short inference, rollback and 64k/128k/256k f16-KV baselines before tagging. Avoid mixing toolchain/driver upgrades.
4. **After integrated acceptance, check Strata's future gfx1151 compatibility first**. Current official docs exclude integrated Radeon GPUs, so no Windows Evo-X2 smoke is actionable at v0.1.43; run one only if support changes. Separately explore s1 fork / RDNA fork **source ideas**, not broad replacements. Defer quantization/accuracy study to its already planned separate lane.

**Explicit non-claims:** No third-party reported speedup in this entry was benchmarked on the user's Evo-X2 today; no upgrade is proven to fix ROCm temp0 nondeterminism; no 1M context at 96GB Windows or Strata gfx1151 Windows throughput is established; no new integrated release, tag or source merge has been performed by this documentation update.


---

## 2026-10-15 — Vulkan Stage-B source attribution and latest upstream / Unsloth mix

**Research status: read-only repository/GitHub review.** No upstream import, build, merge, or runtime/RGP capture was performed. Detailed source trace, compiled-commit provenance, GPU profiling decision and exact 64k/128k P-MODE-verified ABBA are documented separately in [R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md). This section is the canonical external-change **intake / candidate / priority** record, **not** a claim that any new patch has been tested locally.

### Observation time, head SHAs and reproducibility

- **Observation:** 2026-10-15 around 22:50 JST. External references are point-in-time and may move; use full SHAs and tagged releases for eventual reproducibility.
- **llama.cpp upstream:** latest published [b11658](https://github.com/ggml-org/llama.cpp/releases/tag/b11658) (published 2026-10-15 22:11 JST, tagged commit `3e4dfa8f39f904e681737d9f512a6e6338d848aa`); `master` **`620d2225cc436ab0b001e3200e590e3b286ef9ab`** (2026-10-15 22:48 JST, upstream version bump **0.7.0** after that release). GitHub reports master **155 commits ahead / 0 behind** relative to stable r5's pinned upstream **`de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`**. This GitHub comparison is not a test of branch merge cleanliness or binary compatibility.
- **Unsloth mix prebuilt:** latest published **[b11541-mix-2500203](https://github.com/unslothai/llama.cpp/releases/tag/b11541-mix-2500203)** (2026-10-11 10:24 JST), including **Windows x64 Vulkan and ROCm gfx1151** binaries. **Unsloth development master** independently advanced to **`b0e5f06af6359f053105eac9f11037faf03f0792`** (2026-10-15 21:07 JST); its later pinned PRs and packaging fixes are **not** a newly released Windows mix binary.
- **Local reference:** Windows Vulkan **b11618**, exact source **`5ea504315450aeb3ef9e0160bfeea2c0da965960`**, fixed `llama-cli.exe` SHA256 **`7f0edf27aa9505702aeb4c5092ebe588883e76ba7c979e1fba2cf73643c01ba2`**. 128k 126,253-token prompt, Performance-mode controlled: MTP OFF PP **330.90 tok/s / 381.544s**; MTP ON Stage-B OFF **300.93 / 419.545s**; MTP ON Stage-B ON **321.13 / 393.152s**. Stage-B removes **26.393s (69.45%)** of the **38.001s** MTP-induced PP-time overhead; **11.608s** remains by comparison to the *single-run* MTP-OFF control. **No numerical GPU-kernel attribution yet.**

### External candidates ranked for the *present* Evo-X2 / Qwen3.8-Flash-Next question

| Candidate | Upstream/mix status at observation | Evidence, applicability and limitation | Action |
| --- | --- | --- | --- |
| [ggml-org #27703: Vulkan AMD f16 KV scratch/read layout](https://github.com/ggml-org/llama.cpp/pull/27703) | **Merged 2026-10-15**, b11647 onward | **High future priority.** Copy strided f16 KV once into scratch so FA reads spread across AMD memory channels. Author tested Radeon 8060S **RADV/Linux**, including Qwen3.8-27B Q8_0 **pp512 @ 65,536 KV 64.18→172.65 tok/s** under that particular local benchmark. The PR's Vulkan changes target **regular `ggml_vk_flash_attn`**, not proven to accelerate the **Target QSA-union** path; current Stage-B Draft catch-up explicitly removes its own FA. Windows AMD proprietary driver and the user's Qwen4Exp 128k workload are **not tested** by those numbers. | **Inspect later in separate upstream-refresh A/B**, after profiling the existing b11618 residual PP. Isolate AMD driver, QSA-vs-regular FA and extra scratch-memory impact. |
| [ggml-org #30215: Vulkan CM2 L2 workgroup remap](https://github.com/ggml-org/llama.cpp/pull/30215) | Merged 2026-10-15 | Reports significant DGX Spark/GB10 `mul_mm_cm2` gains (Qwen3.8-27B Q6_K pp2048 +21.3%). **CM2-only** optimization: current Evo-X2 shader dispatch family must be established before hypothesizing gain; not a confirmed gfx1151 uplift. | Watch; check RGP shader identity, no immediate port. |
| [ggml-org #30459: `--spec-draft-n-ubatch`](https://github.com/ggml-org/llama.cpp/pull/30459) | Merged 2026-10-14 | Independent Draft physical ubatch size, intended primarily to save VRAM. Changing `-ub` would alter the fixed b11618 64/128k experiment conditions, not a source-verified PP fix. | Follow up as a separate VRAM/perf parameter study. |
| [ggml-org #30480: k-pool selection mask layout](https://github.com/ggml-org/llama.cpp/pull/30480) | Merged 2026-10-14 | Drops redundant reshape views for QSA-related k-pool selection; no claimed numerical difference. Current Qwen4Exp Target already builds its selection in causal-mask layout. | Carry into later refresh; low direct priority for remaining Stage-B Draft cost. |
| [ggml-org #29766: Vulkan concurrent first-init stability](https://github.com/ggml-org/llama.cpp/pull/29766) | Merged 2026-10-15 | Repairs first-device initialization race, not steady-state 128k PP. | Include with future upstream refresh/stability testing. |
| [ggml-org #30574: draft slot state save/restore](https://github.com/ggml-org/llama.cpp/pull/30574) | Merged 2026-10-15 | Restores speculative Draft memory after saved slot reload to recover acceptance, relevant to persistent server sessions but not uncheckpointed CLI prefill. | Track for user-facing server reliability. |
| [Unsloth #270: 32KiB Vulkan CM1 FA at head-size 512/576](https://github.com/unslothai/llama.cpp/pull/270) | **Open**, development-mix pin added 2026-10-13; absent from October 11 prebuilt | Particularly important **for Gemma 4 on Windows Radeon 8060S** where AMD proprietary Vulkan reports 32KiB shared memory: author's 16k Gemma4 test pp4096 **196→788 tok/s**. It addresses an HSK512/576 scalar fallback, **not** verified as an improvement to current Qwen4Exp Stage-B. | High-priority **separate Gemma 4 test** later; not a reason to replace b11618 for Qwen Stage-B RGP. |
| [Unsloth #264: CUDA/HIP-source MoE prompt optimization](https://github.com/unslothai/llama.cpp/pull/264) / [pin-set #273](https://github.com/unslothai/llama.cpp/pull/273) | #264 open; integrated in **development** mix pin set via #273, merged 2026-10-15 | Qwen3.8-Flash-Next pp2048 **+22.2%** on NVIDIA CUDA; implementation is `ggml-cuda`, **not Vulkan**. Cannot assume the same effect on Windows gfx1151 ROCm/HIP. | ROCm-only experimental candidate with a new clean validation gate; no direct Vulkan import. |
| [Unsloth #240: shared Qwen4Exp MTP weights and ratio-zero guard](https://github.com/unslothai/llama.cpp/pull/240) | Open, in development pin set | Relevant to shared-weight MTP sidecars and target tensor ownership; local current b11618 uses the known-good **self-contained** Unsloth Q8_0 Draft, with ratio-zero guard already present. Changing the Draft file changes the correctness/performance baseline. | Separate loading/NextN/acceptance test after completing current Stage-B work. |
| [Unsloth #251: auto MoE cache budget](https://github.com/unslothai/llama.cpp/pull/251) | Open, development pin set | Helpful when expert weights **spill out of GPU memory** with the fitter; not directly relevant to the current fixed 96GB UMA, `-ncmoe 0`, full GPU-layer test with manually controlled settings. | Conditional future fit/VRAM study, not an RGP prerequisite. |

### Newly strengthened Stage-B source attribution (b11618)

From [the exact compiled Qwen4Exp source](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5ea504315450aeb3ef9e0160bfeea2c0da965960/src/models/qwen4exp.cpp#L550-L669), zero-output Stage-B removes the Draft Q/FA/downstream HC+FFN/logits but **retains Draft `mtp_eh_proj`, HC mix and wk/wv/K-norm/RoPE/KV-cache writes**. The [Target NextN mode](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5ea504315450aeb3ef9e0160bfeea2c0da965960/common/speculative.cpp#L1482-L1483) uses **unmasked all-token hidden rows**, which [disables Target early final-layer output-row crop](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5ea504315450aeb3ef9e0160bfeea2c0da965960/src/llama-graph.h#L1060-L1068) and requires CPU-accessible NextN extraction. The Target final-layer HC/FFN, Draft remaining projections, ~4.82GiB **logical** F32 hidden rows over 126,253 tokens, and scheduler/copies/synchronization are all plausible residual contributors. **None is yet shown to account individually for the observed 11.608s.** The 4.82GiB number is *logical payload*, not proven PCIe/device-host traffic on Strix Halo UMA. Historical b11587 RGP confirms the *old* Draft FA and `mtp_eh_proj` kernels, not Stage-B post-crop timing.

### Priority and stop gates before new RGP

1. **Continue b11618-only Stage-B RGP diagnosis, not upstream refresh yet.** Confirm b11618 SHA, use a **dedicated diagnostic cohort** with `GGML_VK_MTP_PP_RGP_MARKERS=1` and `GGML_VK_MTP_PP_RGP_DISPATCH_TRACE=1`, both opt-in; check short and 64k `role=draft` log ranges before RDP **Auto capture → Dispatch range**. Do **not** reuse old b11587 dispatch indexes and do not treat diagnostic PP as ABBA measurements.
2. Capture **Draft Stage-B-only `mtp_eh_proj` / HC mix / K/V write** at ~50k KV to verify Draft `FLASH_ATTN_EXT` has disappeared, then capture/compare **Target final-layer HC/FFN** around the same depth in MTP-ON vs MTP-OFF (possibly needs separate instrumented controls). Do not assume the latter is inside the same brief dispatch slice.
3. Where needed, perform a **separate CPU phase trace** for Target sync, NextN getter, Draft preparation and decode submission; CPU wall encloses asynchronous GPU execution. Validate numerical **Draft K/V parity**, not merely identical output tokens, before any merge.
4. **Only after this attribution** consider a separately sourced clean baseline or isolated backport of upstream #27703 to test plain f16 FA vs Target QSA-union on Windows proprietary Vulkan. Keep power mode, RDP state, model/input GGUFs and binaries fixed within each A/B, with ADLX/P-MODE evidence. Preserve all 64k/128k prior ZIPs without rewriting them.

**No claim:** upstream #27703's large Radeon/RADV f16 KV gains, Unsloth's Gemma4 gains or CUDA MoE gains have **not** been observed in the user's Vulkan Qwen3.8-Flash-Next b11618 Stage-B experiment.


---

## 2026-10-16 — Stage-B GPU RGP closure: Draft retained matmul and Target layer-47 NextN cost

**Source of truth:** [R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md), section "2026-10-16 consolidated Vulkan RGP evidence". All timings in this section refer to **b11618** (`5ea504315`) on the same 61,789-token / ctx65536 / 1,024-token ubatch with QSA union ON/minKV32768, and P-MODE direct read **Performance**. GPU event times were obtained with Radeon Developer Panel's *targeted, opt-in RGP*, not from ordinary ABBA benchmark runs. ZIP and RGP checksums, capture ordinals and source references are in the linked implementation document.

**Established GPU behavior:**
- **Stage-B Draft zero-output prefill:** the clean 128-dispatch RGP (two consecutive Draft graph units; no SQTT truncation warning) verifies **no Draft `FLASH_ATTN_EXT`**, retaining HC mix and K/V writes. `mtp_eh_proj` Q8_0 dominant GPU matmul costs **56.510 / 58.643 ms**, accounting for **91.65 / 91.85%** of the respective Draft graph envelopes **61.662 / 63.846 ms**. The historical broad capture had a truncated SQTT warning and is only a preliminary cross-check.
- **Target final layer 47, MTP ON:** one corresponding unit exposes `ffn_moe_gate-47` **4.595 ms**, `ffn_moe_up-47` **4.722 ms**, and `ffn_moe_down-47` **3.942 ms** (**13.259 ms subtotal**), plus additional HC/FFN work. Unmasked NextN requires all input token rows.
- **Target final layer 47, MTP OFF:** a separately ordinal-calibrated narrow RGP captures `Qcur_full-47`, Target QSA union/gather/FA and `attn_output-47`; it does **not** show FFN-47 in the fully inspected no-output microbatch. The next visible `EVOX2_MTP_GRAPH role=target` begins with GET_ROWS and **layer-0** work: do **not** mislabel its GET_ROWS as a measured layer-47 crop. Source `crop_before_nextn()` and `crop_after_nextn()` explain why ON can need full final-layer FFN while OFF can drop unneeded rows. Absence is demonstrated **only for the sampled no-output graph**, not universally.
- **Graph structure:** around 51–53k depth, OFF Target **4345 dispatch / 6971 nodes** versus ON **4562 dispatch / 7265 nodes** per 1024-token unit (**+217 dispatch/+294 nodes**). Not all extras can be assigned to final-layer FFN without finer tracing.
- **Non-profiled 128k reference:** same-binary, authoritative Performance-mode MTP OFF PP **381.544s** (one run), MTP ON Stage-B OFF **419.545s** (ABBA A mean), Stage-B ON **393.152s** (ABBA B mean). Stage-B saves **26.393s**, ~**69.45%** of the **38.001s** prompt-time cost. **11.608s** remains vs single-run MTP OFF. The 64k local GPU kernel times are **not** a valid 128k aggregate or an additive decomposition, given depth variation and asynchronous backend scheduling.

**Decision:** The **qualitative RGP coverage is sufficient to stop repeating the same Draft/Target screenshots**. The next optimization study should separately quantify (A) Draft `mtp_eh_proj` Q8_0 matmul/shader performance (observed Pipeline state VGPR256, occupancy3/16 is hypothesis-only), (B) Target all-row NextN HC/FFN workload, and (C) host/device NextN handoff and sync. Gate any mathematical shortcut on *numerical K/V cache parity*, not just identical 512-token output. Preserve the validated b11618 baseline; inspect newer upstream/Unsloth in a **separate branch and separately powered A/B**, not inside the original Stage-B cohort. No C++ optimization/backport has been carried out by these records.

---

## 2026-10-25 — Unsloth mix, Strata, Halogen, Project Maya and RDNA-fork research refresh

**Scope / status:** Public repository and release-note review only (2026-10-25 JST); no new Evo-X2 benchmark, Windows build, branch change, performance patch or GGUF compatibility test. The current r5 source remains frozen for baseline/quality comparison. Complete the ongoing 128k V1 quality study, then produce and validate the latest-upstream **integrated candidate** before investigating new optimizations. The integration patch/gate order in [R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md) and the post-integration optimization priority in [R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md) are **not changed** by this intake.

### Summary / changed decisions

| Project / observed revision | What changed since the earlier October review | Applicability and disposition |
| --- | --- | --- |
| [Strata](https://github.com/Niko1221/Strata/releases) **v0.2.3.1** (2026-10-23; Windows HIP engine v0.1.48) | **Windows HIP package now includes gfx1151** using TheRock ROCm 10.2; Strix Halo hyper-connection handling, prefill chunks and tuning improved. Developer reports roughly 6–19% decode improvement on Windows gfx1151 + IQ3_S vs Strata 0.2.2 (workload dependent). | **Promote from “Windows gfx1151 support pending” to a realistic independent-engine comparison after integration.** These are Strata-vs-Strata figures, not an r5 speedup. Separate latency and output-quality comparisons are required. |
| [Unsloth llama.cpp mix](https://github.com/unslothai/llama.cpp/releases) **b11798-mix-f8a7950** (2026-10-21) | Newer upstream b11798 + retained MTP, ROCm/iGPU, Vulkan FA and CUDA/HIP MoE patches. | Keep as a **post-integration prebuilt comparator and source reference**, not the clean upstream base. b11798 predates the b11870 candidate inspected for integration. |
| [Halogen Flash Server](https://github.com/peonist-ai/halogen-flash-server) container **0.18.14** | Supports user-supplied compatible llama.cpp GGUFs via lossless layout repacking; e.g. Unsloth UD-IQ4_XS. | A separate Linux ROCm engine/design reference. **No native Windows adoption** or portable llama.cpp source patch established. |
| [Project Maya](https://github.com/mw00/project-maya/releases) **v1.1.27** (2026-10-24) | Windows HIP/Strix Halo work, AMD long-context bug fix, RAM-resident CPU-lane expert optimization and Windows vision freeze fix. | Valuable for UMA/CPU-GPU expert-placement design, **but focuses on GLM-5.3-Flash and DeepSeek-V4.1-Flash**, not Qwen3.8-Flash-Next. |
| [s1-fork](https://github.com/vahpetr/llama.cpp-s1-fork) **v64** (2026-10-21) | gfx1151 Qwen3.8-Flash-Next-specific Vulkan/RADV work: shared-memory FA layouts, MoE \`mul_mat_id\` tiles, GDN/CONCAT and QSA/MTP paths. | **High-priority source audit after integration**; published RADV/Linux values are not Windows proprietary-Vulkan evidence. |
| [SelfRef llama.cpp-rdna](https://github.com/SelfRef/llama.cpp-rdna) (October 2026 updates) | Maintains upstream-facing ROCmFPx/Vulkan implementation; documents an MMQ shader interface break after upstream #29533. | **Concrete integration compatibility gate for ROCmFPx** (below). |
| [stew675 RDNA boosts](https://github.com/stew675/llama-cpp-rdna-boosts) (V2.1, **14 patch blocks**) | HIP/RDNA package now covers adaptive MTP, GDN prefill, FA/KV variants, MoE/quantized kernels, purity gates and opt-in draft vocabulary subset. | Source/validation-method reference only; do not wholesale import HIP patches or infer Windows gfx1151 gains. |
| [pwilkin/strix-halo](https://github.com/pwilkin/strix-halo) / [Strix-Halo/strix-llama.cpp](https://github.com/Strix-Halo/strix-llama.cpp) | TOP_K/UMA scheduling, adaptive MTP/DFlash2 and memory-placement ideas. | Mainly different model/configuration cohorts (including Qwen3.8-27B dense); keep as lower-priority targeted references. |

### Specific upstream/mix source candidates to remember

- [Unsloth mix b11798 release](https://github.com/unslothai/llama.cpp/releases/tag/b11798-mix-f8a7950) includes [#270](https://github.com/unslothai/llama.cpp/pull/270), a two-subgroup Vulkan coopmat1 FA tile for **head size 512/576 within 32 KiB shared memory**. The likely direct target is large-head FA (not proven to fix Qwen3.8-Flash-Next's QSA path). It may also matter for **Gemma 4**, which will be considered separately after the integrated baseline.
- [Unsloth #264](https://github.com/unslothai/llama.cpp/pull/264) improves **CUDA/HIP-source** MoE prefill with compact MMQ tiling/device expert sorting/GET_ROWS; [#287](https://github.com/unslothai/llama.cpp/pull/287) sets a compiled-architecture-specific MMVQ batch cap. The first is **not a Vulkan optimization**; applicability to the user's TheRock 10.0 Windows HIP build remains unmeasured.
- [Unsloth #158](https://github.com/unslothai/llama.cpp/pull/158) avoids direct ROCm_Host compute on HIP iGPUs; [#240](https://github.com/unslothai/llama.cpp/pull/240) and [#241](https://github.com/unslothai/llama.cpp/pull/241) preserve MTP/share-weight and other downstream behavior. Do not change the known-good Q8_0 MTP head within an established performance or quality cohort.
- **ROCmFPx integration hazard:** [SelfRef's recorded upstream migration](https://github.com/SelfRef/llama.cpp-rdna) notes that [upstream #29533](https://github.com/ggml-org/llama.cpp/pull/29533) changed \`block_a_to_shmem\` in MMQ shaders to take an **in-bounds flag**. Its ROCmFP4/FAST Vulkan MMQ shaders stopped compiling until updated to pass the flag and zero-fill blocks beyond \`end_k\`. **When porting r5 VULKAN-001A/B ROCmFPx to the new upstream, check this API and compile the affected quantized MMQ shader families**. This is a compatibility check within existing integration scope, not a new optimization patch.
- **s1-fork v64:** Developer's same-machine Linux RADV v63→v64 A/B showed approximately **+7.1% PP at 32k and +8.2% at 72k**; the v64 change set also includes FA LDS layout and MoE 8-warp tile experiments. The generic [CONCAT + SSM_CONV fusion](https://github.com/vahpetr/llama.cpp-s1-fork) remains a post-integration candidate, but only if the updated baseline still spends meaningful time on that op. Different GGUF, RADV driver, 1M context settings and custom MTP head mean figures must **not** be compared numerically to the r5 Windows PP/TG runs.

### Independent-engine notes and correctness caveats

- **Strata:** [releases](https://github.com/Niko1221/Strata/releases) and [AMD HIP support documentation](https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md) now establish a plausible Windows gfx1151 path. The v0.2.3 family also has optional DFlash2. Strata's hyper-connection Q8 path can change near-tie logits/selected tokens; developers document toggles \`STRATA_HC_Q8=0\` and \`STRATA_GFX1151_CHUNK=0\` for older-result comparisons. For later benchmarking, record its specific engine version, gfx1151 backend, power mode, input, quantization, MTP setting and **output differences**, not PP/TG alone.
- **Halogen:** [Bring your own GGUF](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/gguf.md) documents lossless repacking of supported IQ4_NL/IQ4_XS/IQ3_S/Q4_0/Q8_0/K-quant families, including Unsloth UD-IQ4_XS, and a **separate \`.hgn\` draft head**. The user's UD-IQ3_XXS is **not explicitly documented as compatible**. The current setup is Linux Podman with \`/dev/kfd\`/\`/dev/dri\`; official speed figures use another Linux/custom checkpoint setup, not r5. The engine's non-standard license/distribution model also prevents treating it as a straightforward llama.cpp code donor.
- **Project Maya:** [v1.1.27 notes](https://github.com/mw00/project-maya/releases/tag/v1.1.27) describe \`--mmap-experts auto\` RAM staging of experts when the available RAM permits (large gains measured on other GPU systems), and a Windows first-image freeze fix. [v1.1.23](https://github.com/mw00/project-maya/releases/tag/v1.1.23) fixed DeepSeek after 32,768 tokens on AMD; v1.1.18–v1.1.20 describe Windows UMA dedicated/shared-memory and pagefile accounting fixes. **None of these measurements demonstrates a Qwen3.8-Flash-Next r5 gain**.

### Sequencing / handoff

1. Finish and document the already-running Qwen3.8 quality comparison/V1 tests. Keep the known-good r5 baseline and its untracked local test settings intact.
2. Freeze r5 and create the separate latest-upstream integration branch; carry the existing r5 patch plan, including ROCmFPx, MTP DENSE/NOOP, Stage-B and correctness gates. **Add the SelfRef-identified MMQ signature/ROCmFP4 shader build check.**
3. After the integrated candidate's Windows Vulkan + ROCm runtime, model-load, 32k/64k/128k quality and performance gates pass, compare **Unsloth mix** and **Strata Windows gfx1151** as separate engines/builds with identical model/input/clock conditions when possible. Strata's changes make it a realistic comparison candidate but **do not make it part of the integrated llama.cpp source**.
4. For *new* optimization research after integration, retain the accepted sequence: **settings/dispatch and MMVQ-width audit → CONCAT → unmerged FA work → remaining GPU/kernel and host operations**. Re-evaluate s1/SelfRef/stew675 source patches against the **new** baseline before any implementation. Halogen and Maya remain later cross-engine/model-design references.
5. Defer QSA mask/selected-ID visualization, selective ROCm RGP and MoE expert-routing input-dependence work until after the integrated candidate. Avoid full \`FLASH_ATTN_EXT\` backend stress tests on the user's Windows machine given the earlier restart/watchdog incident.

**Evidence boundary:** Version numbers, feature lists and stated speedups above come from respective maintainers' public notes/source, not local Evo-X2 measurements. No source changes, new benchmarks, portability conclusions or performance/quality acceptance decisions were made by this 2026-10-25 research intake.
