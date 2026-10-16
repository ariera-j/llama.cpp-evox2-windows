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

## 2026-10-16 — MTP Draft `mtp_eh_proj` flatten prototype prepared

Created `investigation/r5-mtp-eh-proj-flatten-20261016` from the retained
Stage-B investigation branch. The prototype is opt-in with
`LLAMA_MTP_EH_PROJ_FLATTEN=1` and is additionally gated by the existing
Stage-B zero-output Draft catch-up condition, so ordinary speculative-generation
graphs remain unchanged.

The graph-only change reshapes the contiguous `eh_proj` input from
`[2*n_embd,hc,T]` to `[2*n_embd,hc*T]` before `build_lora_mm`, then
reshapes the output back to `[n_embd,hc,T]`. For the measured Qwen3.8
T=1024 catch-up this changes Vulkan matmul geometry from
**M=2560,N=4,K=5120,batch=1024** to **M=2560,N=4096,K=5120,batch=1** without
changing the intended linear operation.

Prepared same-binary plans:

- `qwen38-r5-mtp-eh-proj-flatten.psd1`: short A/B, 64k ABBA, conditional
  128k ABBA, optional 128k MTP-OFF residual control.
- `qwen38-r5-mtp-eh-proj-flatten-rgp-64k.psd1`: profiling-only OFF/ON
  variants with role markers / dispatch trace.
- Full procedure:
  `R5-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-16.md`.

No native Windows build or timing has been run yet. Keep this investigation
separate from the #30511 Target re-warmup branch and from the retained b11618
historical binary. First gate is short functionality, then 64k ABBA. Run 128k
only if the 64k effect clearly exceeds run-to-run drift.
