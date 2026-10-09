# r4 COMMON-002: CLI versus llama-bench at64k/256k

## Collection and decision

The requested comparison is collected at both context depths. All11 uploaded
runs are OK/exit0: three MTP OFF CLI controls and eight bench invocations,
with20 timed bench repetitions (PP2 and TG3 per backend/depth). Four matrices
are Complete, with no early stop or NonOK result. Reuse the already verified
ROCm256k MTP OFF control from the preceding three-run matrix; it is not a new
run in this archive.

The broad backend ordering agrees between CLI and bench: ROCm PP leads at64k,
Vulkan PP leads at256k, and Vulkan TG leads at both depths. TG differences
between tools stay within2.40%. ROCm PP also agrees closely between tools.
Vulkan256k PP is the distinct discrepancy:268.10 CLI versus216.09 bench
(bench−19.40%). This establishes a workload/tool-dependent gap, not its cause.

ROCm PP falls by about half from64k to256k in both MTP OFF CLI and bench.
That observation reproduces outside speculative generation and the CLI
application path; it cannot be explained solely by MTP PP overhead. It does
not by itself distinguish attention/cache scaling, MoE routing, placement or
other backend costs. Only64k and256k were collected here;128k crossover remains
historical evidence, not a fresh measurement in this comparison.

The comparison is complete as a data-collection step. Choose the next source
investigation separately; no runtime implementation or automatic extra matrix
is introduced. ROCm MTP long A/B response/acceptance divergence remains open:
MTP OFF bench does not validate speculative output equivalence.

## Combined results

All rates below are tok/s. Bench values are arithmetic means of per-repetition
throughput, not token count divided by the mean time. Percentage is
100×(bench/CLI−1). CLI controls are single runs, not repeated means.

| Depth | Backend | CLI PP | Bench PP | PP difference | CLI TG | Bench TG | TG difference |
|---|---|---:|---:|---:|---:|---:|---:|
| 64k | Vulkan | 337.45 | 322.19 | −4.52% | 25.55 | 25.71 | +0.63% |
| 64k | ROCm | 370.22 | 366.88 | −0.90% | 21.12 | 20.90 | −1.06% |
| 256k | Vulkan | 268.10 | 216.09 | −19.40% | 19.57 | 19.94 | +1.87% |
| 256k | ROCm | 185.76* | 185.78 | +0.01% | 12.39* | 12.09 | −2.39% |

*ROCm256k CLI reuses `20261005-000814-637-cli-rocm-b11420-ctx262144-8ee365c11666`
from [the preceding collection](R4-COMMON002-ROCM-256K-VALIDATION-2026-10-05.md).
The binary/runtime, model/input and CLI arguments/environment agree with the
prepared comparison plan. It was collected at00:08 rather than with the later
CLI controls; do not imply simultaneous or paired-repeat collection.

| Backend | CLI PP64k→256k | Bench PP64k→256k | CLI TG64k→256k | Bench TG64k→256k |
|---|---:|---:|---:|---:|
| Vulkan | −20.55% | −32.93% | −23.41% | −22.46% |
| ROCm | −49.82% | −49.36% | −41.34% | −42.13% |

## Bench repetitions and dispersion

Mean±SD is throughput sample standard deviation across2 or3 timed repetitions,
not a confidence interval or between-process reproducibility estimate. Samples
below preserve native rounded `samples_ts`; mean/SD retain the full-precision
calculation from `samples_ns`. Warmup and depth-prefill/state-restore time are
excluded from these rates.

| Depth | Backend | Test | Mean±SD tok/s | Individual tok/s | SD/mean |
|---|---|---|---:|---|---:|
| 64k | Vulkan | PP | 322.191±1.262 | 321.298 / 323.083 | 0.392% |
| 64k | ROCm | PP | 366.885±3.659 | 364.297 / 369.472 | 0.997% |
| 64k | Vulkan | TG | 25.711±0.107 | 25.5866 / 25.7696 / 25.7757 | 0.418% |
| 64k | ROCm | TG | 20.896±0.101 | 20.8284 / 21.0122 / 20.8463 | 0.485% |
| 256k | Vulkan | PP | 216.090±3.139 | 218.310 / 213.870 | 1.453% |
| 256k | ROCm | PP | 185.784±0.251 | 185.607 / 185.962 | 0.135% |
| 256k | Vulkan | TG | 19.935±0.045 | 19.9860 / 19.9031 / 19.9160 | 0.224% |
| 256k | ROCm | TG | 12.093±0.051 | 12.0392 / 12.1011 / 12.1397 | 0.419% |

All eight `avg_ts` and `stddev_ts` values were independently reproduced from
the integer nanosecond samples. The Vulkan256k PP samples are both below CLI
268.10; the gap is larger than within-process dispersion in this sample, but
there is only one CLI process and one bench process per test. No claim of
cross-process statistical significance or steady-state causality follows.

### Native time-standard-deviation overflow

Vulkan256k PP native `stddev_ns=4208875769` is inconsistent with its two
`samples_ns=[1168894605800,1193160458200]`. Their correct sample SD is
17158548783.31186 ns (17.158549 s), not4.208876 s. Mean time is
1181.027532 s and the individual times are1168.8946058/1193.1604582 s.

Pinned `tools/llama-bench/llama-bench.cpp` implements `stdev<uint64_t>` with
integer squared sums/mean products. Emulating its unsigned64-bit arithmetic
reproduces4208875769 exactly; overflow explains this native field. For this
dataset, the other native time SDs agree closely with stable sample
calculations, but the integer formula remains unsafe in general.
The throughput SD uses doubles and is independently verified at3.139458 tok/s.
Mean time and mean throughput also agree with the samples. Preserve the raw
JSON and annotate/recompute time SD; do not discard the speed measurements or
silently replace the native field. A stable-statistics fix is a separate small
measurement-tool task, not an inference optimization.

## Conditions and actual allocations

Common: Evo-X2/8060S, UMA96GB, PLE16 UD-IQ3_XXS model, f16 K/V,
batch2048/ubatch1024, t4, ngl999/ncmoe0, FAauto, resource monitoring,
dense-omission1/target-no-op1 and diagnosticsOFF. No draft is loaded; CLI
records MtpDisabled. Vulkan controls remain moe legacy tile1, QSA union1 and
get-rows128x4=0; ROCm has those Vulkan controls cleared.

CLI: real Japanese input, tb4, seed1234, temperature0.2/topP0.8,
reasoningOFF, Jinja/single-turn, ignoreEOS, fitOFF, cacheRAM0, checkpoints0t.
Actual prompt61789/255181 and generated512 match the prepared plan. Bench
uses random token IDs with no sampler or speculative execution. PP is
p=P/n0/d0, repetitions2 with full-prompt warmup. TG is p0/n512/d=P,
repetitions3; depth initialization and attempted state reuse precede its timer.

| Depth | CLI actual ctx | Bench PP actual ctx | Bench TG actual ctx | PP/TG prefix tokens |
|---|---:|---:|---:|---:|
| 64k | 65536 | 61952 | 62464 | 61789 |
| 256k | 262144 | 255232 | 255744 | 255181 |

Bench requests p+n+d and runtime pads the allocation; wrapper directory
ContextHint excludes n and is not the actual context. Prefix depth matches,
allocation does not. The difference is logged rather than hidden by adding
dummy PP depth.

| Depth | Backend | CLI GPU compute MiB | Bench PP GPU compute MiB | Bench TG GPU compute MiB |
|---|---|---:|---:|---:|
| 64k | Vulkan | 899.65 | 1021.25 | 1021.25 |
| 64k | ROCm | 821.59 | 980.00 | 980.00 |
| 256k | Vulkan | 3165.95 | 3091.16 | 3096.70 |
| 256k | ROCm | 2977.18* | 2901.54 | 2907.15 |

*ROCm256k CLI buffer comes from the reused OFF control. Different reservations
and allocation size do not establish the source of the PP gap. Random/real
token IDs affect MoE routing; cache/warmup history, application graph setup
and synchronization/timer boundaries also differ. TG agreement does not make
PP an identical workload. These benches cannot attribute MTP PP overhead.

## Build/runtime identity

| Backend | Build | Embedded source | Compiler | Bench executable SHA256 |
|---|---|---|---|---|
| Vulkan | b11416 | `5df0bdbaf` | Clang20.1.8 | `5eba05dcae614ddca7b84a0f3173db2cb7a5db6f6aad1d0716cab38944df435b` |
| ROCm | b11420 | `131288531` | Clang23.0.0 | `443540d14d3a1f7a77eabd7e1e9af890e398226a39b2469c3d927f89a825b52e` |

User-reported bench runtime preflight digests:

- R4QsaUnionVulkan: `3f070684cc4f0510a6aad98f6c2e03f850773701d7e919a3176acb2270c93984`.
- R4ROCm: `3e3596280b88e6b134f13bea45fb51f8dda258c23010830c0c3edd7ec50ddfd8`.

Both digests were reconstructed from the uploaded manifest artifact identities
in their recorded Windows ordering, selecting the bench executable and bounded
ggml/llama runtime DLLs. All four runs per backend share executable/manifest
identities, and their recorded DLL hashes agree with the Verified actual CLI
runtime collection. CLI digests differ because they include llama-cli.exe
instead of llama-bench.exe; this is expected, not evidence of changed DLLs.

The bench wrapper records Verified BuildIdentity and actual executable SHA256,
but does not persist its per-run RuntimeArtifacts result/digest in conditions.
The supplied preflight plus manifest/CLI checks support the comparison; do
not invent per-run measured DLL hash evidence that is absent from bench logs.
No models/binaries were executed in this analysis environment.

Main model path/size/mtime are common (81961816672 bytes); full GGUF SHA256
was not collected. Input64k SHA256 is
`2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`;
input256k SHA256 is
`63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`.

## Provenance

Archive: `20261005-023613-767-qwen38-r4-cli-bench-comparison.zip`.
Collection is2026-10-05 01:40–05:34 JST (native test_time fields are UTC).

| Matrix ID prefix | Selection | Finished/planned/OK | Complete |
|---|---|---|---|
| 20261005-014048-955 | CLI64k, both backends | 2/2/2 | true |
| 20261005-014934-198 | Bench64k, PP/TG both backends | 4/4/4 | true |
| 20261005-021916-637 | CLI256k, Vulkan only | 1/1/1 | true |
| 20261005-023613-767 | Bench256k, PP/TG both backends | 4/4/4 | true |

Each matrix suffix is `qwen38-r4-cli-bench-comparison`.
All result exceptions are null; bench parse exceptions are null; eight native
rows parse successfully, one per invocation. No fatal stderr entries found.

| Run prefix | Tool/backend/depth/test | Process elapsed s |
|---|---|---:|
| 20261005-014051-167 | CLI Vulkan64k | 238.605 |
| 20261005-014501-777 | CLI ROCm64k | 231.545 |
| 20261005-014937-159 | Bench Vulkan64k PP | 613.719 |
| 20261005-020003-118 | Bench ROCm64k PP | 546.182 |
| 20261005-020921-434 | Bench Vulkan64k TG | 297.850 |
| 20261005-021431-383 | Bench ROCm64k TG | 284.906 |
| 20261005-021918-972 | CLI Vulkan256k | 1014.526 |
| 20261005-023615-972 | Bench Vulkan256k PP | 3571.580 |
| 20261005-033559-535 | Bench ROCm256k PP | 4187.545 |
| 20261005-044600-018 | Bench Vulkan256k TG | 1330.091 |
| 20261005-050822-113 | Bench ROCm256k TG | 1565.234 |

Process durations include loading/warmup/depth setup and differ from timed
test means. In particular, full-prompt warmup plus two PP repetitions explains
why each256k PP process takes about an hour; it is not a single timed prefill.

## Questions retained for the next decision

- MTP PP overhead remains a separate question: the latest ROCm combined ON
  adds94.176 s prompt time versus OFF at256k, with only5.859 s generation saved.
- ROCm long-prefix PP scaling now has matching OFF CLI and bench evidence;
  an early/late batch investigation can start from a workload without MTP.
- Vulkan256k PP has a tool/workload gap that should be distinguished from a
  general regression before comparing optimizations across CLI and bench.
- ROCm256k MTP A/B output/acceptance divergence still needs focused validation
  before broader candidate use; source defaults remain OFF.
- Native integer time SD overflow is identified and reproducible; preserve
  raw samples and treat a statistics fix separately from speed work.

No source change follows automatically from these observations. COMMON-005
remains deferred. See [current priorities](ROADMAP.md) and
[the measurement procedure](R4-COMMON002-ROCM-AND-BENCH-PLAN-2026-10-04.md).
