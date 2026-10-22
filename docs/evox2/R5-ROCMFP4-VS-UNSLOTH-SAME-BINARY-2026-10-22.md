# ROCmFP4 FAST vs Unsloth IQ3 — same-binary Vulkan comparison (2026-10-22)

## Scope and sources

GMKtec Evo-X2, Windows/Vulkan, identical Stage-5 llama.cpp binary `b11561`, MTP OFF, normal dispatch. Targets are Agention ROCmFP4-FAST v2 PLE16 and Unsloth UD-IQ3_XXS PLE16. Input is the same ANLP ch3 corpus across sizes (not three independent domains). Temperatures 0, reasoning off, generation cap 512, f16 KV, -ngl 999 -ncmoe 0, -t/-tb 4, -b 2048, -ub 1024, --fa auto, P-MODE Performance and ADLX logging. Every context has ABBA four independent process runs (two per model).

Raw submitted archives:
- `20261022-130606-837-qwen38-stage5-rocmfp4-vs-unsloth-32k-abba.zip`
- `20261022-131344-441-cli-vulkan-b11561-ctx32768-183523a398ca.zip` (32k detailed logs)
- `20261022-133121-908-qwen38-stage5-rocmfp4-vs-unsloth-64k128k-abba.zip` (matrix plus detailed logs)

Measured with `tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1`, one build `R5RocmFpxStage5Vulkan`; models `AgentionRocmFp4FastPle16` and `UnslothPle16`. Per-run uniqueness provided through `EVOX2_ABBA_RUN` (no inference behavior change).

## ABBA PP and TG measurements

Values are tok/s, listed in chronological order. Averages are arithmetic means of two runs per model.

| Context | Prompt tokens | ROCmFP4 PP (runs) | Unsloth PP (runs) | ROCmFP4 PP avg | Unsloth PP avg | ROCmFP4 PP advantage | ROCmFP4 TG avg | Unsloth TG avg |
|---|---:|---|---|---:|---:|---:|---:|---:|
| 32k | 29,557 | 424.13 / 421.52 | 407.57 / 409.25 | 422.83 | 408.41 | +3.53% | 27.24 | 27.28 |
| 64k | 61,789 | 277.51 / 277.48 | 272.57 / 272.00 | 277.50 | 272.29 | +1.91% | 26.12 | 26.27 |
| 128k | 126,253 | 180.83 / 180.66 | 178.61 / 178.50 | 180.75 | 178.56 | +1.23% | 23.90 | 23.97 |

TG is effectively tied, with Unsloth slightly ahead (<1%). The PP advantage of ROCmFP4 shrinks as context grows. The difference may reflect changing attention-versus-weight-compute fractions, but this benchmark does **not** establish the cause. Each model's repeated PP readings are very close. The 32k and long-context runs consistently finished with exit 0; P-MODE remained Performance throughout and ADLX was recorded. 128k power consistency classification was Ambiguous for both models, **not** evidence of P-MODE switching.

32k GPU Vulkan model buffers were approximately ROCmFP4 88,645.69 MiB vs Unsloth 77,657.05 MiB, with 49/49 target layers offloaded in both cases. These buffer numbers are not total process memory.

## Output sanity and reproducibility

No obvious mojibake, uncontrolled repetition or incoherent Japanese observed in sampled generated answers. At 32k both copies for each model generated identical text at temperature 0. Unsloth stopped naturally at 479 generated tokens; ROCmFP4 reached the 512-token cap. At 64k both reached 512. At 128k Unsloth stopped at 481, ROCmFP4 at 512. A length cap is not itself an output-degeneration error.

Qualitative observation over related ANLP inputs: ROCmFP4 tended to mention individual authors/studies and details, while Unsloth tended to summarize methods into higher-level categories and limitations. This is **exploratory, not a verified quantization-specific quality trait**: inputs are all excerpts of the same source, and autoregressive divergences from small logit shifts can produce different levels of detail. A separate cross-domain, multi-prompt evaluation is needed to test that hypothesis; no winner in accuracy is inferred.

## Historical comparison boundary

Older Qiita write-up: https://qiita.com/ariera/items/d4026ad03775ebb1daa5

The older comparison differed substantially in binary/fork and upstream baseline, OS, Unsloth pre-PLE16 state, sampling/output settings, run count and measurement conditions. Its broad direction (ROCmFP4 PP lead / nearly tied TG) is useful qualitatively, **but its percent gaps must not be used as a controlled longitudinal speed improvement metric**. The present study isolates target GGUFs on one executable but does not equate their quantization accuracy.

## Follow-up: optimized r5 integration binary, MTP ON

Use separate matched plans on `build-vulkan-r5-noop-rocmfpx` (`R5NoopRocmFpxVulkan` local key): 32k ABBA gate, then 64k+128k continuous ABBA. Each target uses its own matching MTP sidecar (Agention ROCmFP4 or Unsloth Q8_0), DraftMax=2, DraftPMin=0.0, identical normal Vulkan/QSA union/DENSE/NOOP settings. This next experiment measures **model+draft system throughput and acceptance**, not a target-only quantization effect. Review matched draft compatibility and memory allocation at 32k before committing to longer workloads. P-MODE/ADLX and output checks remain mandatory.

## Follow-up: 128k optimized-r5 MTP ON ABBA in recovered high-speed regime (2026-10-22 23:53 to 2026-10-23 00:26 JST)

Source: user-supplied `20261022-235301-027-qwen38-r5-noop-rocmfpx-mtp-64k128k-abba.zip`. Four completed `-OnlyCase 128k` runs from `qwen38-r5-noop-rocmfpx-mtp-64k128k-abba.psd1`, same `b11588 / 1c3167fb6` binary, 126,253 prompt tokens and 512 generated, `-c 131072`, Kv f16, QSA union/DENSE/NOOP, two-token MTP. This follows a period of variable VRAM clocks and unexpected system hangs; see [EVOX2-UNEXPECTED-WINDOWS-RESTART-INCIDENT-LOG.md](EVOX2-UNEXPECTED-WINDOWS-RESTART-INCIDENT-LOG.md).

| Order | Target + matching draft | PP tok/s | TG tok/s | MTP draft acceptance | Approx. prefill high-load VRAM mean MHz | GPU core mean MHz | GPU power mean W | GPU temp mean °C |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 / `128k-05` | ROCmFP4 | **300.98** | **29.62** | 66.972% | 918.5 | 2844.8 | 111.7 | 76.2 |
| 2 / `128k-06` | Unsloth | 298.32 | 28.40 | 67.667% | 906.5 | 2857.2 | 111.6 | 78.4 |
| 3 / `128k-07` | Unsloth | 297.27 | 28.39 | 67.667% | 902.5 | 2857.8 | 111.3 | 78.8 |
| 4 / `128k-08` | ROCmFP4 | **293.51** | **29.44** | 66.972% | 905.0 | 2842.9 | 111.1 | 78.5 |

Each run exited 0 and logged P-MODE Performance at start and finish with zero warnings; matched runs have internally identical output fingerprint per target, consistent model and executable hashes. High-utilization PP ADLX means use gpu_usage >=95%, excluding load/TG via result duration: first ROCmFP4 run n=202 samples, last n=207; thus approximate phase boundaries, not exact kernel profiling.

- ROCmFP4 PP **first vs fourth 300.98→293.51 (-2.48%)**, GPU VRAM clock **918.5→905.0 MHz**; core nearly unchanged, mean GPU temperature **76.2→78.5°C**, GPU power **111.7→111.1W**. Clock by prefill thirds first **935.4→910.9→909.4 MHz**, fourth **913.9→904.9→896.0 MHz**. This supports a *correlation* with VRAM clock drift, not an established causal or thermal-protection mechanism.
- Unsloth PP 298.32→297.27 (-0.35%), VRAM clock 906.5→902.5 MHz. In this run order, ROCmFP4 is more affected by sequence/time variation.
- ABBA mean **ROCmFP4 PP 297.245 / TG 29.53**, **Unsloth PP 297.795 / TG 28.395**: ROCmFP4 PP **-0.18%** (effectively tied), TG **+4.00%**. This is the *model+matching MTP draft* comparison, not isolated target quantization.
- Earlier post-reboot low-clock 128k 4run ABBA (same day) gave ROCmFP4 PP ~276.78, Unsloth ~276.52; this recovered-regime run improved PP by **~7.4% / ~7.7%**, respectively. Cross-session speed differences must not be interpreted as code changes.
- **32k MTP OFF outstanding in high-speed state.** The prior optimized-r5 MTP OFF 32k ABBA (`20261022-201146-028-qwen38-r5-noop-rocmfpx-nomtp-32k-abba.zip`) was measured in the earlier low-VRAM-clock regime: ROCmFP4 mean PP **406.88**, TG **26.95**; Unsloth PP **390.81**, TG **27.05**. Do not combine that OFF dataset with recovered high-clock MTP ON results for a controlled MTP-on/off comparison. Re-run existing `tools/evox2/benchmark/configs/qwen38-r5-noop-rocmfpx-nomtp-32k-abba.psd1` in the now-stable high-clock state; preserve P-MODE, ADLX and headless/display metadata.

## Follow-up: high-speed 32k MTP OFF ABBA control (2026-10-23 00:32–00:42 JST)

Source ZIP: `20261023-003215-173-qwen38-r5-noop-rocmfpx-nomtp-32k-abba.zip`. This is the **previously missing MTP OFF control in the recovered high-PP state** on `b11588 / 1c3167fb6`, executable SHA-256 `a816c4e8bf68e923d662f2e470f06b892bd9d8c6c2b0305cc2d26ad597f0c1d5`, with the same 29,557-token 32k input, 512 generated tokens, temperature=0, no draft, QSA union/DENSE/NOOP environment retained (DENSE inert because MTP OFF). No physical display connected, RDP monitoring, P-MODE Performance at start/end of each run, exit 0. Output fingerprints matched *within each target model* across repeats, and each model's fingerprint matched its previous 2026-10-22 MTP OFF series.

| Sequence | Target | PP tok/s | TG tok/s | Prefill VRAM MHz (mean) | Prefill GPU power W | Prefill GPU core MHz | Prefill GPU temperature °C |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | ROCmFP4 | **421.81** | 27.18 | 932.6 | 113.4 | 2875.9 | 71.2 |
| 2 | Unsloth | **407.53** | 27.31 | 923.3 | 112.3 | 2881.8 | 73.6 |
| 3 | Unsloth | **408.49** | 27.25 | 927.8 | 112.7 | 2881.1 | 74.3 |
| 4 | ROCmFP4 | **422.34** | 27.18 | 939.7 | 115.3 | 2869.9 | 75.7 |
| **Mean** | **ROCmFP4** | **422.075** | **27.18** | **936.2** | **114.3** | — | — |
| **Mean** | **Unsloth** | **408.01** | **27.28** | **925.5** | **112.5** | — | — |

Prefill GPU averages above were extracted from ADLX 2-second samples within each `prompt eval` interval reconstructed from the llama.cpp stderr timing line and `PromptEvalMilliseconds`/`GenerationEvalMilliseconds`, with GPU usage >=95% (33/35/35/34 samples). Approximate boundary precision ~2s, suitable for comparisons, not exact per-kernel telemetry. Low-clock values from an earlier time window use the same extraction approach.

- **Repeatability:** ROCmFP4 repeated PP difference **0.53 tok/s (0.13%)**; Unsloth **0.96 tok/s (0.24%)**. TG was stable too. The fourth run was *slightly faster* than the first; unlike the 128k MTP ON series, no progressive PP collapse occurred over the four runs despite GPU temperature increasing.
- **Target comparison with MTP OFF:** ROCmFP4 PP **+3.45%** vs Unsloth; TG **-0.37%**, effectively tied. The larger ROCmFP4 PP lead at 32k is consistent with the Stage5 MTP OFF 32k matched-binary results but the builds differ and must not be numerically conflated.
- **Old low-clock 32k OFF control** (2026-10-22 ~20:11): ROCmFP4 PP **406.88**, Unsloth **390.81**; new **422.08**/**408.01** represent **+3.74%**/**+4.40%** PP recovery, with ADLX prefill VRAM clocks also higher. No binary change or improvement is implied.
- **Compare with earlier *high-performance-state* MTP ON 32k ABBA** (2026-10-22 16:50, `20261022-165037-175-qwen38-r5-noop-rocmfpx-mtp-32k-abba.zip`): ROCmFP4 PP **398.76**, TG **36.59**; Unsloth PP **387.99**, TG **33.40**. Relative to current MTP OFF, MTP ON is **-5.52% PP / +34.62% TG** for ROCmFP4 and **-4.91% PP / +22.43% TG** for Unsloth. This supports a *material MTP-prefill overhead despite TG benefit* under the current r5 integration, **BUT** the ABBA sets are separated by more than seven hours and intervening OS/power/display events. The MTP ON runs had higher PP VRAM clocks (roughly 965–969 MHz) than the new OFF controls (roughly 923–940 MHz), so these percentages are *cross-session indicative*, **not a controlled MTP ON/OFF causal estimate**. For precise overhead, interleave same-target ON/OFF runs in one session with clock logging.
- Late-evening single ROCmFP4 MTP ON at ~23:45 after headless boot had PP **394.96**, TG **36.66**, PP VRAM ~944 MHz. Against current OFF 422.08, the indicative MTP PP difference is **-6.43%**, though measured in different runs and sessions.
- **Stability conclusion:** 32k MTP OFF ABBA is an acceptable stable high-state baseline for comparing ROCmFP4 and Unsloth target quantization, but it does not prove the system stays stable for sustained 128k tests or during display/power-state transitions. Record physical display/remote session, P-MODE, GPU VRAM clocks in future benchmark metadata.
