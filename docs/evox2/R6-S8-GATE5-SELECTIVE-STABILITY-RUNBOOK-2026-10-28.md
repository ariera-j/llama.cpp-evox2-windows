# R6 S8 G8-5 selective 256k stability runbook - 2026-10-28

## Scope and status

**Status: EXECUTED; G8-5 selective stability PASS (1/1).** The instructions below are retained for reproducibility; do not schedule a routine repeat. The run is one representative Qwen3.8 IQ3 PLE16 **Vulkan 256k**, MTP ON, all five S8 performance switches ON. This is a **stability** gate, not a 256k throughput comparison or a repeated stress test. The existing [S8 256k plan](../../tools/evox2/benchmark/configs/qwen38-r6-s8-vulkan-256k.psd1) defines one job and one variant; no new source code, build, or benchmark plan was needed.

Prerequisites:

1. G8-3 Vulkan IQ3 64k/128k correctness and P-MODE/ADLX gates have passed. The [G8-4 result](R6-S8-GATE4-STAGEB-FLATTEN-RUNBOOK-2026-10-28.md#g8-4-windows-measured-closure---2026-10-28-jst) adds 14/14 output/continuation PASS on the final combined Vulkan b11908. **Numerical Draft K/V parity remains DEFER**; do not reinterpret a successful 256k run as numerical parity proof.
2. Use the **fixed** Clang 20.1.8 Vulkan b11908 binary from `build-vulkan-r6-combined-fixed\bin\Release`. It must have the same `llama-cli.exe` SHA256 as G8-4: `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`. Runtime digest was `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3`. Git HEAD may advance for docs; do not rebuild or substitute a different executable.
3. Windows GMKtec Evo-X2, UMA label `96GB`, P-MODE **Performance**, no other GPU inference jobs, no known in-progress Defender/system scan or heavy disk activity. Do **not** disable security software; wait until incidental activity finishes. Keep the old verified binaries for rollback.
4. The ignored `tools/evox2/benchmark/configs/local.psd1` must map `Builds.CombinedVulkan`, `Models.UnslothPle16`, `Models.UnslothMtp`, and `Inputs.'256k'` to the known local assets. The original S0 256k reference input was **255,181 actual tokens**, file SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`. This G8-5 plan intentionally reuses the `256k` input key. Do not silently replace it with a synthetic/repeated prompt.

### Exact fixed configuration

| Item | Required |
| --- | --- |
| Job / case / variant | `s8-iq3-vulkan-256k` / `256k` / `all-on-stability` |
| Backend / model | Vulkan / Unsloth UD-IQ3_XXS PLE16, Unsloth Q8_0 MTP Draft |
| Context / input / output | `262144` / known real 256k fixture / `-n 512` |
| Main/Draft KV | f16 / f16; GPU layers 999, CPU MoE 0, `-fit off` |
| MTP | ON, `--spec-draft-n-max 2`, `--spec-draft-p-min 0` |
| PP configuration | FA auto, `-b 2048`, `-ub 1024`, `-t 4`, `-tb 4` |
| Sampler | `--temp 0`, `--top-p 0.8`, `--seed 1234`, `--ignore-eos` |
| Other | no prompt cache, context checkpoints `0t`, resource monitor plus ADLX/P-MODE |
| All-ON profile | `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_MIN_KV=32768`, `LLAMA_MTP_SKIP_DENSE_INDEXER=1`, `LLAMA_QSA_SKIP_NOOP_INVALIDATION=1`, `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`, `LLAMA_MTP_EH_PROJ_FLATTEN=1` |
| Off for measurement | QSA/NOOP/MTP graph diagnostics, RGP trace, experimental Vulkan overrides |

All flags are **explicitly opt-in for this job**. Their source defaults remain OFF, and this document does not authorize enabling them globally or on ROCm/Gemma4.

## Windows PowerShell execution - one gated job

Use Windows PowerShell in `C:\llama-build\llama.cpp-evox2-windows-r6`. Run the preflight first; stop if any check fails. The local config is ignored by Git and must not be committed.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'

# Update docs/plan only if the worktree is clean and the pull can fast-forward.
git status --short --branch
$pending = @(git status --porcelain)
if ($LASTEXITCODE -ne 0 -or $pending.Count -ne 0) {
    throw 'Worktree is not clean: inspect local changes before updating.'
}
git pull --ff-only origin r6/combined-20261028
if ($LASTEXITCODE -ne 0) { throw 'Git pull failed: inspect the worktree; do not reset it automatically.' }

$localPath = '.\tools\evox2\benchmark\configs\local.psd1'
$local = Import-PowerShellDataFile $localPath
$binDir = [string]$local.Builds.CombinedVulkan.BinDir
$cli = Join-Path $binDir 'llama-cli.exe'
$expectedExe = 'bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a'
if (-not (Test-Path -LiteralPath $cli)) { throw 'CombinedVulkan llama-cli.exe is missing.' }
if ((Get-FileHash -LiteralPath $cli -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedExe) {
    throw 'CombinedVulkan executable SHA mismatch: do not substitute a different build.'
}

$input256 = [string]$local.Inputs.'256k'
$expectedInput = '63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788'
if (-not (Test-Path -LiteralPath $input256)) { throw '256k input fixture is missing.' }
if ((Get-FileHash -LiteralPath $input256 -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedInput) {
    throw '256k input SHA mismatch: resolve the intended input before running.'
}

$os = Get-CimInstance Win32_OperatingSystem
$freeGiB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
Write-Host "Free physical RAM before run: $freeGiB GiB"
if ($freeGiB -lt 12) { throw 'Less than 12 GiB physical RAM free; defer the 256k run.' }

& $cli --version
if ($LASTEXITCODE -ne 0) { throw 'CombinedVulkan executable version check failed.' }

$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-s8-vulkan-256k.psd1'
$runner = '.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1'
& $runner -Plan $plan -OnlyJob s8-iq3-vulkan-256k -OnlyCase 256k -OnlyVariant all-on-stability -MaxRuns 1 -PlanOnly
```

**Stop after PlanOnly.** It must expand to **exactly 1** CLI/Vulkan/UnslothPle16 row, context 256k, `all-on-stability`, `CombinedVulkan`, MTP ON. Check the environment summary and `local.psd1` mappings. Do not launch if it selects a different build, model, Draft, input, or more than one run. Confirm P-MODE=Performance and that no scanning/inference background workload is active.

Only then execute the one run:

```powershell
& $runner -Plan $plan -OnlyJob s8-iq3-vulkan-256k -OnlyCase 256k -OnlyVariant all-on-stability -MaxRuns 1 -StopOnError
```

Do **not** add `-NoResourceMonitor`, run a matrix without the filters, launch an automatic retry loop, run ROCm/FP4 256k, or change flags during this gate. The prior S0 256k input took about 18.6 minutes of prompt evaluation at 228.89 tok/s (different model layout and MTP OFF), so allow a long monitored session; this is only a rough planning reference, **not** a G8-5 speed target or a timeout.

### Resource and safety watch

- Observe system free RAM, GPU dedicated/shared commit, GPU temperature, core/VRAM clock, power and disk paging while the run proceeds. The resource/ADLX CSVs provide approximately 2-second samples. Do not run unattended just to obtain a speed number.
- The **12 GiB free-RAM preflight** is a conservative operational guard, not a correctness threshold. During execution, if free RAM approaches 8 GiB and continues falling with sustained paging, GPU memory spills heavily, a driver reset occurs, the process hangs, or the system becomes unstable, stop the affected run safely and classify it as incomplete/DEFER pending resource triage. Do not automatically start it again.
- The S0 256k Vulkan reference had a high-load VRAM clock near **995 MHz**, power around **119 W** and hot GPU temperatures. Compare trends, not a single sample; sustained collapse in clock/power or authoritative P-MODE disagreement makes performance uninterpretable. A brief warm-up or load spike is not itself a failure.
- Do not disable Defender or change Windows security settings to improve a benchmark. If a scan notification appears, record its approximate wall-clock time for correlation and separate functional PASS from precise throughput attribution.

## Post-run review and evidence to send

Collect the single matrix batch's `matrix-plan.json`, `matrix-runs.csv`, `matrix-results.csv`, `matrix-result.json`, and the child run's `conditions.json`, `result.json`, `summary.csv`, `stderr.log`, `stdout.normalized.log`, `resources.csv` and `gpu-metrics.csv`. Preserve raw ZIPs outside Git; do not commit model paths, local config, large logs or system-private data. Send the one-result ZIP for review before G8-6.

| Check | PASS evidence | DEFER / stop reason |
| --- | --- | --- |
| Provenance | Same b11908 fixed Vulkan executable SHA and verified runtime artifacts; expected model/Draft/input keys; no source change | Wrong executable/input, dirty unexplained source, missing artifact identity |
| Long context | Actual context `262144`, input SHA above, actual prompt approximately **255,181 tokens**, `InputAtLeast80Percent=true` | Less than 80% filled, unexpected input tokens or truncation; label as allocation-only rather than full G8-5 |
| Completion | `Status=OK`, `ExitCode=0`, no exception, requested 512 generated, captured output fingerprint and coherent normalized text | Hang, crash, OOM, bad output, zero/partial generation or unclassified termination |
| GPU execution | Main 49/49 and Draft 50/50 GPU layers, Vulkan backend, no unexpected CPU model fallback; `qsa-union active` at long context; DENSE/NOOP evidence Verified | Missing GPU placement/active-path evidence, unintended fallback or relevant runtime error |
| MTP | MTP ON, positive accepted/generated with sensible acceptance and no rollback/continuation anomaly | Zero/invalid drafts, broken continuation or recurrent errors; 64k acceptance counts are **not** a fixed 256k target |
| Power/memory | Performance -> Performance P-MODE, ADLX power consistency, no prolonged VRAM-clock collapse, stable RAM/VRAM and no sustained paging/driver reset | Missing telemetry, scan/system interference, sustained memory pressure, GPU reset or thermal/power anomaly |

**G8-5 verdict:** PASS only on complete stable execution with adequate provenance and telemetry; DEFER for missing evidence/environmental/resource interference; FAIL for a verified functional defect. With only one run, do not claim 256k speedup, statistical stability, numerical Draft K/V equality, deterministic output parity, or production-wide default-ON approval.

If a clear, reproducible failure category must be distinguished from transient environment interference, **at most one targeted follow-up run** is permitted after reviewing the first ZIP and restoring safe conditions. No bulk 256k repetition or opportunistic tuning. After a PASS, proceed to **G8-6 runtime/server usability**, then **S9 final-model validation**, keeping ROCm Stage-B/flatten and numerical K/V parity as separate DEFER items.

## Windows measured result and G8-5 closure - 2026-10-28 JST

**Verdict: PASS (1/1), no repeat required.** This is a successful single all-ON 256k stability run, not a same-binary speedup claim, a statistical repeatability result, or a numerical Draft K/V parity gate.

### Input, build and condition identity

- User-supplied raw ZIP: `20261028-201824-559-cli-vulkan-b11908-ctx262144-3eaea070692e.zip`, SHA256 `0ae127d6c600056c13b42d0fea746205648bf3a83f83e96e70651338ad626831`. Raw results remain outside Git.
- The clean source-worktree identity was `r6/combined-20261028` at the previous documentation commit `9cfe8868bd864b2adee6224b0f3026bdcd45d801`; this is not the executable source commit. Actual binary remains **Vulkan b11908 / `b82243bf0` / Clang 20.1.8**, using `build-vulkan-r6-combined-fixed`, `llama-cli.exe` SHA256 `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a` and verified runtime digest `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3` (same as G8-4).
- Vulkan IQ3 PLE16 main / Unsloth Q8_0 MTP Draft, 96GB UMA, f16 main/Draft KV, FA auto, DraftMax=2, all five speed switches ON and union min-KV=32768. `ContextRequested=ContextActual=262144` and input file SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`, **255,181 actual prompt tokens**, `InputAtLeast80Percent=true`.

### Results

| Check | Measurement / evidence |
| --- | --- |
| Process | `Status=OK`, `ExitCode=0`, `RunException=null`; **512 generated tokens**, `truncated=0` and complete captured output fingerprint |
| Timings | PP **301.30 tok/s** over **846.946 s**, TG **25.08 tok/s** over **20.377 s**; PP+TG **867.322 s**, wall duration **920.423 s** |
| MTP | **298 accepted / 425 drafted (70.118%)**, coherent Japanese summary output, no observed continuation abort |
| Output SHA256 | `37e41758e0930461f9cfb2176a945176a0f98bbc7c81640b5fbdfd528ceda807` (single run; no same-input output-pair parity claim) |
| GPU paths | Vulkan main **49/49**, Draft **50/50** layers on GPU; `qsa-union active` at long context; DENSE indexer omission and target NOOP decision both `Verified`; no unexpected CPU-model execution evidence |
| P-MODE | WMI start/finish **Performance -> Performance**, no warning. ADLX **422** high-load samples, mean **110.29 W**, `Performance-like`, `Consistent=true` |
| GPU telemetry | High-load mean usage **98.79%**, mean core **2856.7 MHz**, mean VRAM clock **931.4 MHz**, mean temperature **76.6 C**, maximum temperature **85 C**. VRAM clock stayed around **924-928 MHz** in 3-15 min segments, with no sustained collapse |
| Host/GPU memory | Minimum free physical RAM **22.643 GiB**; maximum process GPU Dedicated **91.582 GiB**, Shared **1.919 GiB**. No observed OOM, GPU reset or sustained disk-paging stall |

The generated Japanese text reads as a coherent technical summary, although it ends at the configured 512-token cap and is not a separate semantic-accuracy assessment. The log reports `graph reallocs = 0 / 0` and `truncated=0`. During the monitored post-start interval, disk reads were low on average; a single short spike does not establish sustained paging. The observed VRAM clock is below the older S0 reference but steady after initial warm-up; P-MODE and ADLX power are consistent, so there is no evidence of a sustained low-power transition.

**Decision:** G8-5 selective 256k Vulkan stability PASS. Do not run a second 256k sample merely to improve a throughput number. Do not compare its PP/TG causally with the earlier S0 original-layout, MTP-OFF build, and do not upgrade G8-4 numerical Draft K/V parity from DEFER. All five switches remain independent/default OFF in source, with the all-ON configuration an explicitly scoped Vulkan Qwen3.8 opt-in candidate. **Next: prepare G8-6 runtime/server usability and per-backend flag-decision freeze, then S9 final models.**
