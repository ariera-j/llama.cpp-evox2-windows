# Evo-X2 integrated snapshots

> **Checkpoint intent updated 2026-10-19:** [User-selected candidate build and acceptance plan](R5-RESEARCH-AND-INTEGRATION-PLAN-2026-10-19.md): after the current flatten RGP and Draft correctness gate, create an **independent new-upstream integration candidate**, evaluate all beneficial patches by dependency and backend, and perform ROCm toolchain-vs-loaded-runtime version checks. Tentative prior target “10/18–19” is not an accepted release or a deadline; if targeting the next weekend it is Oct 24–25. **No branch, build, accepted release, or tag has been created by this update.**


**Status as of 2026-10-11 JST: PLANNED / NOT CREATED.**

No integrated release branch, validated all-patches snapshot, final binary, release tag or integrated benchmark has been produced under this policy yet. Do not infer a release from the existence of the r3/r4/r5 research branches. The first integration checkpoint is intended for a convenient upcoming research break; the approximate 4–6 week cadence is a guideline, not a booked date. **The first checkpoint is intended to include a separate ROCmFP4 compatibility port and correctness gate (COMMON-003) before the integrated release is accepted.** VULKAN-001 remains conditional on the target model/backend.

See [INTEGRATION-POLICY.md](INTEGRATION-POLICY.md) for selection, upstream pinning, execution gates and acceptance policy; see [PATCHES.md](PATCHES.md) for candidates and tested historical improvements.

## Release/attempt index

| Snapshot | State | Upstream SHA | Integration ref/tag | Notes |
| --- | --- | --- | --- | --- |
| First integrated checkpoint (date not decided) | **Planned; not started** | Not selected | None | Will re-evaluate verified beneficial patches; COMMON-001 mandatory for PLE16; **ROCmFP4 (COMMON-003) compatibility/correctness planned before acceptance**, VULKAN-001 conditional |

Only append an **accepted** row after passing the combined integration gate. If an attempt stalls, record it distinctly as `candidate / incomplete`; never label it the latest validated build.

## Follow-ups after the first accepted snapshot

After the integrated stack passes and is tagged, trial **Strata on Evo-X2** independently of the llama.cpp integration gate. This is planned, **not yet attempted**; record Strata version, operating system/backend and required model conversions if successful.

A separate later study will reuse the long-context test prompts originally generated for Qwen3.5, testing the **answer-key accuracy of different Qwen3.8-Flash-Next quantizations**, not automatically treating Qwen3.5 and Qwen3.8 as the same model. Hold prompt tokens, scoring rules, model revision and decoding settings constant; separate engine effects if Strata is included. Neither quantization accuracy nor Strata feasibility has been established.

## Template for an eventual checkpoint

- Date / name / state: `candidate`, `validated`, or `incomplete`
- Branch HEAD, immutable tag (if validated), chosen clean upstream SHA and included upstream commits/cherry-picks
- Machine, Windows build, driver, compiler/SDK/HIP runtime, actual compiled GPU target
- Model source, PLE layout, quantization, KV type, prompt hashes/context, runtime switches, MTP/cache conditions
- Clean upstream → COMMON-001 acceptance, tested binaries and their SHA256 hashes
- Per-candidate disposition: `included` / `covered by upstream` / `excluded` / `failed` / `deferred`, reason and source/test link
- Correctness: backend ops, short/long model runs, any output-equivalence or rollback checks
- Combined Vulkan/ROCm PP/TG (64k/128k/256k where feasible), repetition/ABBA scope, total time/memory and differences from clean control
- Limitations, untested combinations, raw archive identities, next research-only issues
- Explicit go/no-go for tagging and whether the last accepted integrated snapshot remains the recommended stable one

Historical r5 results (including Vulkan grouped-union measurements) remain **research-series** results until retested and admitted to an integrated checkpoint.
