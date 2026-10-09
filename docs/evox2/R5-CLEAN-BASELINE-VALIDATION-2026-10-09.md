# r5 clean upstream Windows validation (2026-10-09)

## Status and scope

**Accepted as a single-run clean baseline, not a controlled r4-versus-r5 source-only A/B.**
The user reports both fresh Vulkan/ROCm builds and relevant backend tests passed on Evo-X2; the supplied benchmark archives independently establish two successful 64k allocation/short-prompt runs and six successful real-document runs (64k, 128k, 256k per backend). All eight child runs are OK / exit 0 with verified runtime artifacts and no recorded run exceptions. Backend test details/counts were not included with these two measurement archives, so the backend test gate is marked **passed (user report)**, not independently audited.

Source:
- Target branch: `r5/upstream-refresh-20261009`
- Pinned upstream inference base: `de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b`
- Actual benchmark checkout/build manifest HEAD: `6763689b2c33af6132589f01c46a78ac397baf95` (clean; tooling/build-wrapper commit atop pinned upstream)
- Engine: llama.cpp 0.6.0-dev, **b11517**, embedded `6763689b2`
- GPU: Radeon 8060S / Ryzen AI Max+ 395, manual UMA allocation 96 GB
- Vulkan: LLVM/Clang 20.1.8, Vulkan SDK 1.4.357.0
- ROCm: Clang 23.0.0, Windows ROCm/TheRock build toolchain; the child environment records `HIP_PATH=C:\Program Files\AMD\ROCm\7.2\` (do not infer a different installed ROCm runtime version from older guide text)
- AMD display driver: **32.0.31041.1004**, dated 2026-08-17 (as captured in Windows system identity)
- Executable SHA-256, Vulkan: `065ff1d1ee837ba429b2ffbe21174a78cc84b2bfbdc9e654e16620d7db0bb9de`
- Executable SHA-256, ROCm: `96d481a187f208baf15727152203bb33b00618c687b05fa1587673cdc959e9dd`
- Runtime digests: Vulkan `56992bf1223248495568b59aa35e3cdde40f749b96a64180d59ddaf4367435db`; ROCm `580bc9def81e6f3b3709846d43bde74896cf8b47e9a2dfea7a668cae9601e402`.

## OS change immediately before r5 baseline

The user updated Evo-X2 with Windows Update **after r4 measurements and before r5 branch creation/build/measurement**. PowerShell registry and Get-HotFix output supplied on 2026-10-09:

| Field | Observed value |
|---|---|
| Windows | Windows 11 Pro, **26H2** |
| CurrentBuild | **26300** |
| UBR | **9550** (effective OS build **26300.9550**) |
| BuildLabEx | `26100.1.amd64fre.ge_release.240331-1435` (build-lab string; not the current build number) |
| Update | KB5121794 — installed 2026-10-08 |
| Update | KB5124010 — installed 2026-09-29 |
| Update | KB5124009 — installed 2026-09-29 |
| Update | KB5126052 — installed 2026-09-09 |
| Update | KB5054156 — installed 2026-05-11 |

The archive system identity independently reports Windows 11 Pro / `10.0.26300`; it does not record UBR/hotfix details, which come from the subsequent user-provided PowerShell output.

**Critical comparison limit:** historical r4 clean runs occurred before this Windows upgrade. r4→r5 differences cannot yet be attributed exclusively to llama.cpp changes; OS/kernel/WDDM/runtime/environment changes remain plausible confounders. Re-run the preserved r4 clean binaries on this same 26H2 machine for a better-controlled comparison.

## Input and fixed inference conditions

- `tools/evox2/benchmark/configs/qwen38-clean.psd1`; `llama-cli`, original **Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS** split-GGUF **first shard** (original joined-PLE tensor layout; *not* the split PLE16 converted model), MTP OFF, `--spec-type none`.
- K/V cache f16/f16; `-b 2048 -ub 1024 -t 4 -tb 4 -ngl 999 -ncmoe 0 -fa auto -fit off --cache-ram 0 --ctx-checkpoints 0t --reasoning off --jinja --single-turn -n 1024 --temp 0.2 --top-p 0.8`; generation stops at EOS where applicable.
- Prompt/input files and SHA-256: 64k `nlp-survey-ch3-d7-b1.txt` / `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; 128k `nlp-survey-ch3-d15-b1.txt` / `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`; 256k `nlp-survey-ch3-d31-b1.txt` / `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.
- Requested context 65,536 / 131,072 / 262,144; actual prompt 61,789 / 126,253 / 255,181 tokens. Inputs and prompt lengths agree with historical r4 logs. Input SHA-256s verified in archives. Full model-file hash **not supplied**.
- Shared settings for Vulkan and ROCm, with separate actual executables and detected backends. Experimental r4 patch environment controls cleared.

## Real-document baseline (2026-10-09, one run per cell)

| Backend | Context | Prompt tokens | Generated tokens | PP tok/s | TG tok/s | PP s | Generation s | Child run s | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Vulkan | 64k | 61,789 | 609 | **269.24** | **25.31** | 229.494 | 24.020 | 301.179 | OK |
| ROCm | 64k | 61,789 | 586 | **390.73** | **21.18** | 158.139 | 27.621 | 226.553 | OK |
| Vulkan | 128k | 126,253 | 639 | **179.51** | **23.67** | 703.308 | 26.954 | 775.786 | OK |
| ROCm | 128k | 126,253 | 616 | **292.69** | **17.13** | 431.350 | 35.904 | 509.756 | OK |
| Vulkan | 256k | 255,181 | 470 | **135.41** | **20.02** | 1884.448 | 23.424 | 1955.848 | OK |
| ROCm | 256k | 255,181 | 612 | **193.64** | **12.37** | 1317.797 | 49.396 | 1413.115 | OK |

`Child run s` includes load/setup and is not identical to `PP s + Generation s`. EOS-driven generated-token counts differ between individual runs and backends; TG percentages are descriptive, not tightly controlled same-token A/B.

### Historical r4 clean comparison (different OS session; descriptive only)

| Backend | Context | r4 clean PP | r5 clean PP | PP change | r4 clean TG | r5 clean TG | TG change |
|---|---:|---:|---:|---:|---:|---:|---:|
| Vulkan | 64k | 248.38 | 269.24 | +8.40% | 24.61 | 25.31 | +2.84% |
| ROCm | 64k | 369.72 | 390.73 | +5.68% | 20.98 | 21.18 | +0.95% |
| Vulkan | 128k | 168.09 | 179.51 | +6.79% | 22.81 | 23.67 | +3.77% |
| ROCm | 128k | 275.00 | 292.69 | +6.43% | 17.13 | 17.13 | 0.00% |
| Vulkan | 256k | 126.76 | 135.41 | +6.82% | 19.26 | 20.02 | +3.95% |
| ROCm | 256k | 185.95 | 193.64 | +4.14% | 12.23 | 12.37 | +1.14% |

r4 clean is original joined-PLE MTP OFF, b11372/embedded `94b877457`, same long-document inputs and basic CLI settings, as documented in [BASELINE.md](BASELINE.md). Different generations (EOS), binary/build, OS and date prevent strict isolated attribution.

### Later r4 optimized reference (not a matched baseline)

- Vulkan r4 legacy MoE tile + QSA union **OFF**: original 64k ABBA mean PP **269.08**, TG **24.72**; PLE16 128k PP **178.97**, 256k PP **132.96** with legacy MoE fixed. r5 clean PP (269.24 / 179.51 / 135.41) is close, but **does not establish that upstream reverted or matched legacy tile selection**. Inspect source before deciding.
- Vulkan r4 legacy MoE + grouped QSA union **ON**: original 64k ABBA PP **337.45**, TG **24.82**; PLE16 128k PP **295.68**, 256k PP **266.75**. Strong candidate for a **separate measured** VULKAN-002 port; different model layout on long inputs, build and OS mean these numbers are not a same-binary causal r5 A/B.
- ROCm r4 post-COMMON-001 original 64k PP **370.32** / TG **21.17**; r5 390.73 / 21.18. ROCm r5 256k/64k PP ratio is **49.56%**; prior clean r4 ratio was **50.29%**, so long-context scaling still warrants investigation.
- r4 MTP candidates/combined TG optimizations are **not** present in r5 clean and must not be interpreted as current r5 results.

## Allocation, process logging, resource observations

Two standalone allocation/short-prompt gates (original model, 64k context) also passed: Vulkan b11517 OK/exit0 (18 prompt tokens, 2 generated), ROCm b11517 OK/exit0 (18 prompt tokens, 2 generated). These were recorded at 12:15 and 12:16 JST ahead of the long-input runs, and are **smoke checks, not PP/TG throughput baselines**.

| Context | Backend | Peak sampled system commit, GiB | Minimum sampled free RAM, GiB | Peak process GPU shared, GiB |
|---|---|---:|---:|---:|
| 64k | Vulkan | 90.919 | 0.055 | 0.695 |
| 64k | ROCm | 90.357 | 0.070 | 0.775 |
| 128k | Vulkan | 93.589 | 0.023 | 0.853 |
| 128k | ROCm | 92.830 | 0.044 | 0.932 |
| 256k | Vulkan | 98.766 | 0.004 | 1.167 |
| 256k | ROCm | 97.927 | 0.002 | 1.247 |

Very low free RAM occurs at some sampled points, notably model initialization / early work. For the 128k and 256k runs, the earlier inspection of central (non-startup/non-shutdown) resource samples found substantially more headroom and no sustained median disk throughput. These **system-wide** counters do not by themselves prove OOM or sustained paging in the inference process. All long-input runs reached exit0. No fatal engine-stderr error was found; incidental wrapper warnings about API/CORS, cache-idle-slots and reasoning preservation are not fatal. Natural Japanese text was produced, but correctness/coverage has not been scored.

## Raw record identity (not committed)

- `20261009-121742-712-qwen38-clean.zip`: two 64k input runs, 2/2 OK; standalone preceding allocation runs also included.
- `20261009-123632-588-qwen38-clean.zip`: four 128k/256k input runs, 4/4 OK.
- All six inputs use the same backend-specific executable/runtime SHA identities above and share git HEAD `6763689b2c33af6132589f01c46a78ac397baf95`; real-input resource monitoring enabled.
- Original ZIP files, private local paths/model blobs and process resource CSVs remain local; this document preserves summary metrics and identities only.

## Next: historical r4 clean binaries on the same Windows 26H2 installation

The user preserved these **r4 clean** build directories (directory label `b11352`, but verify **actual** executable version; the 2026-10-03 archived executable was b11372):

```text
C:\llama-build\llama.cpp-evox2-windows-r4\build-vulkan-b11352\bin\Release
C:\llama-build\llama.cpp-evox2-windows-r4\build-rocm-b11352\bin\Release
```

Use the **r5 matrix runner and r5 clean plan settings** with only the BuildKeys changed. Keep `CleanVulkan`/`CleanROCm` pointed at r5; register separate `R4CleanVulkan`/`R4CleanROCm` entries in ignored `tools/evox2/benchmark/configs/local.psd1`. Save an untracked, disposable plan under the ignored `evox2-logs` directory by replacing `Name` and `BuildKeys` in a copy of `qwen38-clean.psd1`, then run `-PlanOnly` and `-OnlyCase 64k` before expanding to 128k/256k. Compare input SHA, CLI arguments, runtime SHA and b11372 version; **do not rebuild** historical binaries. If a DLL mismatch breaks them, stop and document the issue rather than silently substituting a different binary. This same-OS replay reduces OS-update confounding but does not control for all driver, cache and run-order differences. A repeated/interleaved 64k A/B helps if the remaining gaps are small.

See [R5-REFRESH-2026-10-09.md](R5-REFRESH-2026-10-09.md) for current acceptance and [R4-CHECKPOINT-2026-10-09.md](R4-CHECKPOINT-2026-10-09.md) for historical patch gating.
