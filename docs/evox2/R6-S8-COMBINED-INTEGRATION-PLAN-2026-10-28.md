# r6 S8 combined integration: fixed decisions and execution plan - 2026-10-28

## Purpose, source baseline and scope

This is the **next-stage plan**, not a claim that S8 has been built or tested. The original [r6 execution plan](R6-INTEGRATION-EXECUTION-PLAN-2026-10-25.md) remains authoritative for the pinned upstream and S0-S9 sequencing. S7-B evidence is closed in the [flatten record](R6-MTP-EH-PROJ-FLATTEN-IMPLEMENTATION-2026-10-27.md#s7-b-windows-vulkan-measured-closure---2026-10-28-jst).

- **Pinned upstream:** b11870 / `74bca3950054eed1795f525cb9cf06bfe796492d`. Do not refresh upstream during S8 except to resolve an independently reproduced blocking defect and with a separate decision.
- **Source starting point:** GitHub branch `r6/mtp-eh-proj-flatten-20261027`, implementation commit `3e377c23827945a7f71bfc741bd03d1c97e7fe89` plus its S7-B evidence-only documentation commit `606227d3dc17481783207ca6dcd276be95dfc160`. Its source tree is **cumulative**: S1-S7-B are already present. **Do not cherry-pick or re-implement the same patches.**
- **S8 preparation (2026-10-28):** The requested `r6/combined-20261028` **local worktree branch** was created from that S7-B source tree, and the five `.psd1` files below were added. **No S8 source optimization, new Windows build, measurement, commit or remote branch publication has occurred in this preparation step.** Recheck the GitHub parent SHA before eventual publication; local and GitHub history may have different commit IDs even if their source trees match.
- **S8 deliverable:** one reproducible, build-identified Vulkan candidate plus a separately build-identified ROCm candidate, validated feature flags/presets, and PASS/DEFER decisions by model/backend. S9 (IQ4/huihui/Gemma4 and distribution) remains a separate gate.

## 1. Decision inventory from S0-S7

| Stage / patch | Evidence so far | S8 classification and residual risk |
| --- | --- | --- |
| **S0 upstream b11870** | Clean Vulkan/ROCm 4k and 64/128/256k baseline PASS | Fixed reference; do not claim cross-build A/B causality |
| **S1 COMMON-001 PLE16** | IQ3 original/split bridge and 128k Vulkan/ROCm PASS | **Required compatibility**, keep source; no speed flag |
| **S2 COMMON-003A + VULKAN-001A/B** | ROCmFPx Vulkan numeric **150/150 PASS**, real FP4 4/16/64/128k and 49/49 GPU layers | **Required for FP4 on Vulkan**; not an assertion of HIP FP4 kernel availability |
| **S3 MTP-COMPAT** | Legacy Agention HC and ratio-zero MTP Draft loads, DraftMax=2/7 paths passed | **Required for current selected sidecars**; preserve fail-closed cases |
| **S4 VULKAN-002 union** | IQ3 PP **+5.69% (64k), +22.03% (128k)**; FP4 PP **+6.12% / +22.07%**. MTP-OFF isolated same-binary tests, no material TG loss | **High-priority Vulkan candidate**, f16 KV only, independent default-OFF switch; confirm MTP-ON interaction in S8 |
| **S5 MTP-DENSE-001** | IQ3 Vulkan TG **+6.99/+16.32% (64/128k)**, FP4 Vulkan 64k **+7.51%**, IQ3 ROCm observed **+9.55/+12.11%**; state/rollback PASS | **Vulkan/ROCm candidate**, default OFF, ROCm temp0/output-acceptance variability limits exact speed attribution |
| **S6 MTP-NOOP-001** | IQ3 Vulkan TG **+3.00/+6.18%**, FP4 Vulkan 64k **+3.01%**, IQ3 ROCm observed **+2.80/+3.00%**; native state comparisons **524/524 exact** | **Vulkan/ROCm candidate**, default OFF, require regression tests after S8 build |
| **S7-A Stage-B** | IQ3 Vulkan PP/TG **+4.65/+1.97% (64k)** and **+6.87/+2.94% (128k)**; FP4 Vulkan 64k **+4.74/+1.78%**. Output/Draft acceptance identical | **Vulkan candidate**, default OFF. ROCm S7 execution and independent Draft K/V parity not established |
| **S7-B `mtp_eh_proj` flatten** | b11906; Vulkan 4k C/A/B 6/6 PASS, native S5/S6 PASS, **16/16** long-context runs. IQ3 PP **+1.58% (64k, 8run)** / **+1.31% (128k, 4run)**; FP4 PP **+2.02% (64k, 4run)**. Output/acceptance parity throughout | **Conditional Vulkan candidate**, default OFF. Intermittent ~0.9s TG slow runs in first IQ3/FP4 B1; follow-up B2 and IQ3 repeat did not reproduce. Must not conceal this risk in S8 |

**Neither additive speed estimates nor an all-on verdict follow from this table.** S4's isolated MTP-OFF results and S5/S6's older union-OFF results have different effective configurations. S7-A/B tested union+DENSE+NOOP already ON, but not the entire all-OFF versus all-ON stack in a single S8 binary.

**Do not add to S8:** COMMON-004/006 or MOE patches already provided upstream; COMMON-005 ROCm gathered QSA unless its separate trigger is met; r2 MTP-QSA, gather-stride, Stage-A, VULKAN-GR-001, ROCmFPx HIP kernels, q8_0 union, Strata/s1/Halogen/Gufo, deterministic ROCm top-k, mask/Expert/RGP research and diagnostic instrumentation. Keep these in post-integration research notes.

## 2. Feature-switch contract: independent, fail closed

| Feature | Environment key | OFF | Candidate ON / effective path | Backend limitation |
| --- | --- | --- | --- | --- |
| S4 QSA union | `GGML_VK_QSA_UNION` | Unset or `0` | `1`; f16 KV prefill, `GGML_VK_QSA_UNION_MIN_KV=32768`, actual `qsa-union active` evidence required | **Vulkan only**, MTP-OFF and MTP-ON must both be checked |
| S5 DENSE | `LLAMA_MTP_SKIP_DENSE_INDEXER` | Unset or `0` | `1`, only eligible ratio-zero Draft indexer omitted | Vulkan / ROCm Qwen4Exp MTP |
| S6 NOOP | `LLAMA_QSA_SKIP_NOOP_INVALIDATION` | Unset or `0` | `1`, only eligible Target no-op invalidation suppressed | Vulkan / ROCm Qwen4Exp Target |
| S7-A Stage-B | `LLAMA_MTP_DRAFT_PREFILL_KV_CROP` | Unset or `0` | `1`, eligible zero-output Draft KV-only prefill | **Vulkan validated**; ROCm requires its own gate |
| S7-B flatten | `LLAMA_MTP_EH_PROJ_FLATTEN` | Unset or `0` | `1`, only when Stage-B graph is eligible **and** Stage-B flag is ON | **Vulkan validated for tested paths**; no standalone effect without Stage-B |

1. Source defaults **all OFF**. Merely merging source must not change the user's existing command-line behavior or silently enable unsupported model/backend paths.
2. An optional **Qwen3.8 Vulkan MTP performance profile** may set all five flags to `1` and union `MIN_KV=32768` **only after** the S8 combined gates. Record the profile with the exact model/quant/KV type, not as a global process setting affecting Gemma4 or other models.
3. A **ROCm IQ3 profile** may start with S5+DENSE and S6+NOOP only. Do not assume Vulkan union applies to HIP; keep Stage-B/flatten disabled on ROCm pending targeted parity and speed checks.
4. S7-B OFF must preserve S7-A ON behavior; switching S7-A OFF must make S7-B inert. Test that relationship with the same final executable.
5. Keep trace flags (`GGML_VK_QSA_UNION_STATS`, `LLAMA_MTP_DIAG`, `LLAMA_QSA_NOOP_TRACE`, graph/RGP trace) OFF for speed measurements. No broad `FLASH_ATTN_EXT` backend tests on Windows gfx1151.

## 3. S8 execution gates: stop on failure, no new optimization

| Gate | Order and scope | Required evidence / stop rule |
| --- | --- | --- |
| **G8-0 Branch and source freeze** | Create new S8 branch from current **S7-B GitHub HEAD**, not r5 or stale local branch. Audit `git diff`, ancestry and all five flags; create separate `CombinedVulkan` / `CombinedROCm` build keys | Exact source SHA, clean worktree/BuildIdentity, no duplicate cherry-picks or unrelated edits. Keep b11903 and b11906 binaries intact |
| **G8-1 Independent builds and native tests** | New Vulkan and ROCm release build directories; add `llama-tokenize` target to **both** (`-ExtraTargets`). Vulkan targeted FP4 MUL_MAT/MUL_MAT_ID widths/negative-expert tests; S5 MTP policy+model state; S6 NOOP policy+model state; tokenizer short English/Japanese sample | S2 numerical gate **150/150**, S5/S6 native state/rollback PASS (NOOP 524/524 or documented equivalent), CLI version/device and GPU/DLL identity. ROCm build/runtime **TheRock 10.0** provenance. `Build-ROCm.ps1 -RunBackendTest` prohibited |
| **G8-2 Short functional matrix** | Same new binary: IQ3 Vulkan and FP4 Vulkan MTP OFF baseline, MTP ON all flags OFF, Stage-B only, Stage-B+flatten, and all-on union/DENSE/NOOP. Test 4k/16k and brief DraftMax=7. IQ3 ROCm MTP OFF and MTP ON DENSE+NOOP first | Main+Draft fully GPU offloaded, positive MTP acceptance, output coherent. Verify flags by actual active-path/eligible markers; Vulkan output/hash parity when expected. For FP4, no silent CPU fallback. Fail/abort/rollback anomaly stops the affected backend path |
| **G8-3 Same-binary real-input speed** | IQ3 Vulkan **64k ABBA** all-speed-flags OFF versus candidate all-on, then **128k ABBA**; FP4 Vulkan **64k ABBA**, then **128k A/B** for missing combined evidence. IQ3 ROCm **64k then 128k** compare DENSE/NOOP OFF versus ON, with S7-A/B OFF unless separately qualified. Keep input/model/KV/FA/DraftMax=2 fixed | PP, TG, **total time**, output SHA, accepted/generated, actual tokens, P-MODE/ADLX, build and model/input SHA. Strictly same executable and model for each A/B; do **not** multiply/add S4-S7 gains. Inconsistent P-MODE, CPU fallback, crashes or bad text stop the affected sequence |
| **G8-4 S7 interaction and numerical parity** | On Vulkan, targeted C (Stage-B OFF), A (Stage-B ON/flatten OFF), B (both ON) under final all-other-flags-on profile. When feasible, compare Draft K/V content and rollback state after zero-output prefill OFF versus ON, not only legacy S5/S6 tests | If state/KV differs beyond validated numerical tolerance or resume behavior diverges, do not promote S7-A/B as a production preset. If no dedicated parity evidence is obtained, **document uncertainty and keep default OFF**. On ROCm, run this gate independently before any S7 enablement there |
| **G8-5 Selective stability** | Once 64/128k and correctness gates pass, **one representative IQ3 Vulkan 256k MTP ON/all-on** run; use a known previously stable input and cap GPU/UMA risk. One further run only for a clear failure classification, not optimization hunting | Complete without hang/reset/OOM; stable P-MODE, VRAM clock, output coherence and accepted/generated. Avoid bulk 256k repetition or stress on ROCm unless explicitly needed |
| **G8-6 Runtime usability and decision freeze** | Check `llama-server` Qwen3.8 (Jinja and short multi-turn) plus one representative real document. Confirm normal MTP-OFF path, separate frontend/backend binaries and `llama-tokenize` outputs. Create a small supported flag-profile document | Record PASS/DEFER/DISABLE per flag/backend; retain old working binaries and rollback procedure. Only then designate an S8 candidate for S9 final-model testing |

### Fixed minimal real-input matrix

| Priority | Backend/model | ctx | MTP | Flags compared | Repetitions |
| --- | --- | ---: | --- | --- | --- |
| P0 | Vulkan IQ3 PLE16 | 32k smoke then 64k and 128k | OFF and ON | All-speed-flags OFF vs all-on **within the same binary** | 64/128k ABBA for MTP ON; MTP OFF representative |
| P0 | Vulkan FP4 FAST PLE16 | 32k smoke then 64k and 128k | ON | C/A/B 4k; all-off/all-on and S7-B isolated if needed | 64k ABBA; 128k A/B, escalate only on disagreement |
| P1 | ROCm IQ3 PLE16 | 4k then 64k and 128k | OFF and ON | DENSE/NOOP OFF vs ON; S7-A/B stay OFF initially | Same-binary 64/128k A/B; repeat only on inconclusive evidence |
| P1 | Vulkan IQ3 PLE16 | 256k | ON | A single all-on stability case after 128k PASS | **1 run**, not a throughput optimization search |
| P2 | Vulkan IQ3/FP4 and ROCm IQ3 | 4k/short | ON | DraftMax=7 and rollback/multi-turn, MTP OFF fallback | Functional only, before promoting presets |

Inputs at 64k/128k remain the existing **61,789/126,253-token** fixtures; context size is not a substitute for actual prompt tokens. Hold `-ngl 999`, `-b 2048`, `-ub 1024`, `-t 4`, `-tb 4`, flash-attn auto, f16 K/V, temperature 0, fixed seed, no graph trace, identical Draft model and `n-predict=512`. Use the matrix runner's `-PlanOnly` and resource/P-MODE monitoring. Do not compare a b11903 Stage-B executable directly against b11906 flatten for isolated speed claims.

## 4. Acceptance, bounded follow-up and defaults

- **Correctness always gates speed.** S2 backend numerical tests, native state/rollback, complete GPU placement and coherent output are required. Vulkan exact output/acceptance matching is desirable and observed in S7; any mismatch requires a specific explanation before production use. ROCm's known `temp=0` output nondeterminism means the same byte-hash criterion cannot be imposed blindly there.
- **Performance:** preserve both PP and TG and minimize **PP+TG total time** for each intended workload. Pre-existing S4/S5/S6/S7 standalone gains are motivation, not additive forecasts. If all-on is slower than all-off or TG degradation of approximately 3% or more **repeats under comparable conditions**, perform **at most one** bounded confirmatory ABBA; then disable the offending optional patch and record it. Start ablation with flatten, then Stage-B, rather than reversing every patch indiscriminately.
- **Flatten specific:** expected small PP gain ~1-2% but rare ~0.9s TG outliers on 64k. For low gains, require consistent direction across paired runs and no repeatable output/TG regression. Keep default OFF even if an opt-in performance preset is allowed.
- **Backend boundaries:** Vulkan FP4 evidence must not be reported as FP4 GPU HIP kernel support. ROCm Stage-B/flatten remains **DEFER** until tested on ROCm. Build/runtime 10.0 mismatch or low-VRAM-clock state invalidates a performance run; use prior [P-MODE recovery evidence](R5-ADLX-PMODE-VALIDATION-2026-10-15.md), and do not repeatedly stress a suspected low-power state.
- **Time/complexity budget:** no new s1/Strata/Mask/Expert/RGP exploration until S9; one follow-up sequence per uncertain gate, with a clear PASS/DEFER/DISABLE checkpoint. Never run the unsafe broad `FLASH_ATTN_EXT` suite.
- **Rollback:** retain b11903 Stage-B, b11906 flatten, earlier r6 S4/S5/S6, S0 clean binaries and b10919 Gemma4, with version/hash in the final manifest. Turning all five opt-in flags OFF is a quick functional isolation path; it does not remove required S1-S3 loader compatibility patches.

## 5. S8 output and S9 handoff

S8 completion requires:

1. `R6-S8-COMBINED-RESULTS` with source/binary/DLL hashes, actual local flags, numerical/native/smoke/long outputs, accepted/generated ratios, clock/P-MODE evidence, archived raw ZIP SHA256 and explicit limitations.
2. Per-backend and per-model **flag-decision table**: `PASS opt-in`, `DEFER`, `DISABLE`, or `upstream-covered`. Source present != feature ON != measured performance PASS.
3. Reproducible Vulkan and ROCm build procedures including `llama-cli`, `llama-server`, `llama-bench`, `llama-tokenize`; associated manifest and basic tokenize sanity checks.
4. A short example **performance preset** with all explicit flags, and a stock/default-OFF command. Do not silently change global environment variables or overwrite the existing user's binaries.
5. Hand off to the existing **S9 final models**: Unsloth IQ4 and huihui IQ4XS 4/16k, selected 64/128k and known text/search cases; Gemma4 31B/26B separately against operational b10919; vision/`mmproj` and server checks where applicable. Keep this outside S8's source patch acceptance.

## 6. Prepared matrix plan files and Windows execution order (2026-10-28)

All five plans use the existing `Invoke-BenchmarkMatrix.ps1` schema without changing the runner. `CombinedVulkan` and `CombinedROCm` are new build keys, so **do not alias them to S7-B binaries**. Add the entries to ignored `tools/evox2/benchmark/configs/local.psd1` only after both fresh Windows builds exist:

```powershell
# Add these entries inside Builds (keep the previous b11903/b11906 mappings).
CombinedVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-combined\bin\Release'
    ExpectedBackend = 'Vulkan'
}
CombinedROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-r6-combined\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

Existing `Models.UnslothPle16`, `Models.UnslothMtp`, `Models.AgentionRocmFp4FastPle16`, `Models.AgentionRocmFp4FastMtp`, and `Inputs.'64k'/'128k'/'256k'` must resolve to the same known GGUF shards and input files as the S7 comparisons. The 4k/16k smoke uses `mtp-short.txt` (163 tokens): **16k names the context allocation, not a 16k-token prompt**. Keep `-PlanOnly` and `-OnlyJob` / `-OnlyCase` to avoid unintentionally launching every matrix row.

Before building, check PowerShell data-file parsing on the Windows host (this Linux preparation environment does not have `pwsh`):

```powershell
Get-ChildItem .\tools\evox2\benchmark\configs\qwen38-r6-s8-*.psd1 | ForEach-Object {
    $parsed = Import-PowerShellDataFile -LiteralPath $_.FullName
    '{0}: schema={1}, jobs={2}' -f $_.Name, $parsed.SchemaVersion, @($parsed.Jobs).Count
}
```

| Plan file | Gate / intended sequence | Scope and default stop |
| --- | --- | --- |
| [`qwen38-r6-s8-smoke.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-smoke.psd1) | G8-2 | IQ3/FP4 Vulkan 4k/16k MTP-OFF, MTP-ON all-OFF, C Stage-B-OFF, D Stage-B-ON, E flatten-ON; separately, 32k real input A/B with 256 generated tokens; IQ3 ROCm 4k MTP-OFF/ON with DENSE+NOOP; short DraftMax=7 job. **Run 4k first**, then 16k/32k/DraftMax=7 only after checking the first gate. |
| [`qwen38-r6-s8-vulkan-abba.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-vulkan-abba.psd1) | G8-3 | Same-binary IQ3 Vulkan 64k ABBA -> 128k ABBA; FP4 Vulkan 64k ABBA -> 128k A/B. A = all five opt-in flags OFF, B = all ON with `GGML_VK_QSA_UNION_MIN_KV=32768`. |
| [`qwen38-r6-s8-rocm-abba.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-rocm-abba.psd1) | G8-3 | IQ3 ROCm 64k ABBA -> 128k ABBA, DENSE+NOOP only. Stage-B/flatten and Vulkan union remain OFF for both arms. |
| [`qwen38-r6-s8-gate4-stageb-flatten.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-gate4-stageb-flatten.psd1) | G8-4 | Vulkan IQ3/FP4 4k C/A/B/D (D tests flatten inertness with Stage-B OFF), then IQ3/FP4 real 64k C/A/B. All other speed flags stay ON. Follow the [Gate 4 runbook](R6-S8-GATE4-STAGEB-FLATTEN-RUNBOOK-2026-10-28.md). **Output-level comparison only; b11908 has no Draft K/V snapshot instrumentation, so numerical state parity remains DEFER.** |
| [`qwen38-r6-s8-rocm-stageb-smoke.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-rocm-stageb-smoke.psd1) | Optional G8-4 | Only after ROCm baseline/native/smoke gates: IQ3 4k C/A/B for Stage-B and flatten, DENSE+NOOP fixed ON. This is **not** a direct K/V parity test; no ROCm S7 promotion from smoke alone. |
| [`qwen38-r6-s8-vulkan-256k.psd1`](../../tools/evox2/benchmark/configs/qwen38-r6-s8-vulkan-256k.psd1) | Optional G8-5 | A single IQ3 256k Vulkan all-ON stability run. **Run only after the prior 64/128k gates pass**; no automated 256k loop. |

After fresh builds, source SHA / build manifest / P-MODE and native regressions pass, run from the repository root (PowerShell):

```powershell
$bench = '.\tools\evox2\benchmark'
$smoke = "$bench\configs\qwen38-r6-s8-smoke.psd1"
$vulkan = "$bench\configs\qwen38-r6-s8-vulkan-abba.psd1"
$rocm = "$bench\configs\qwen38-r6-s8-rocm-abba.psd1"

& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $smoke -OnlyJob s8-iq3-vulkan-smoke -OnlyCase 4k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $smoke -OnlyJob s8-iq3-vulkan-smoke -OnlyCase 4k -StopOnError
# Check output, full GPU offload and Draft acceptance before the next job.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $smoke -OnlyJob s8-fp4-vulkan-smoke -OnlyCase 4k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $smoke -OnlyJob s8-fp4-vulkan-smoke -OnlyCase 4k -StopOnError

# Only after smoke and native gates; each long workload is selected explicitly.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $vulkan -OnlyJob s8-iq3-vulkan-abba -OnlyCase 64k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $vulkan -OnlyJob s8-iq3-vulkan-abba -OnlyCase 64k -StopOnError
# Check 64k output, per-run TG and P-MODE before selecting 128k.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $vulkan -OnlyJob s8-iq3-vulkan-abba -OnlyCase 128k -PlanOnly

# ROCm is a separate build and run sequence. Do not enable S7 here yet.
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $smoke -OnlyJob s8-iq3-rocm-smoke -OnlyCase 4k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $rocm -OnlyJob s8-iq3-rocm-abba -OnlyCase 64k -PlanOnly
```

Execute the remaining 16k, 32k real input, FP4 64/128k, ROCm 64/128k, short DraftMax=7 and optional G8-4/G8-5 **one gated job at a time**, only after reading the preceding results. The plans stop on any child error but do **not** automatically verify active QSA/Stage-B paths or independently prove Draft K/V parity. Inspect those in logs; if the evidence is missing, record DEFER rather than a PASS.

**Next action:** build fresh `CombinedVulkan` and `CombinedROCm` binaries with `llama-tokenize` included, run the G8-1 native tests, populate the ignored local build keys, then execute the first `-PlanOnly`/4k smoke. No S8 runtime result is claimed yet.
