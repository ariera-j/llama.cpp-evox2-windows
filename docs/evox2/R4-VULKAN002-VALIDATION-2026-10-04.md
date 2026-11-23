# r4 VULKAN-002 measurement validation

Recorded: 2026-10-04 JST. Measurements: 2026-10-03 JST.
Branch: `r4/upstream-refresh-20261002`.
Implementation: `5814fbe99e9249e8ac2c4c2e9b977c05735b0912` (b11390, Clang 20.1.8).
Pinned upstream remains `bed0a856606ee4a24a164066f73d2379447033f5`.

## Decision

The Evo-X2 Windows build, targeted GPU correctness gate, 64k profile and normal
ABBA through 256k pass. Promote VULKAN-002 from pending experiment to validated
opt-in for this tested device/model/workload. Keep the code default OFF; changing
the default and broader model/device validation are separate decisions.

Vulkan grouped-union materially improves PP while keeping decode TG effectively
unchanged. At 128k/256k it now exceeds the recorded COMMON-001 ROCm PP. Prioritize
Vulkan and ordinary upstream MTP compatibility (COMMON-002); defer the ROCm-focused
COMMON-005 port. Retain ROCm as a comparison/alternative backend.

## Supplied evidence

- `20261003-202659-940-qwen38-r4-qsa-union.zip`: Windows correctness OFF/ON and
  64k Original profile pair.
- `20261003-204202-568-qwen38-r4-qsa-union.zip`: 64k Original and PLE16 normal ABBA.
- `20261003-212720-693-qwen38-r4-qsa-union.zip`: PLE16 128k and 256k normal ABBA.
- `20261003-164324-643-qwen38-r4-common001-longctx.zip`: earlier COMMON-001
  Vulkan/ROCm long-context reference, source `a60a57879...` (b11380).

No raw user logs are committed to the repository. This report records their
identities, results, comparison limits and resulting priorities.

## Build and correctness

The build manifest identifies a clean source at `5814fbe99...`. The Vulkan0
device is AMD Radeon 8060S on the Evo-X2, Windows, UMA label 96GB. The dedicated
`Test-QsaUnion.ps1` gate reports 18/18 passed in both OFF and ON, exit code 0,
no unsupported/skipped cases; ON has activation and fallback evidence.
The cases include high cell ids through 262143, partial groups, shuffled/duplicate
and invalid ids, query-specific additive masks, and unsupported-input fallback.
This confirms the supplied targeted dense-reference tests, not universal
model quality or all device/descriptor-limit and all-masked edge cases.

Test executable SHA256:
`dface0a88f1d2a02e7dfdd69aea622ed8302adbdad4d05e3b51e0d6557ad2232`.
All profile/normal CLI runs share executable SHA256:
`b35dfe13df8d74224dbe6bde5577f78ec50cf5fa03c6f8019b5cddcf5a05fb05`.

## Fixed normal conditions

Same binary and input per comparison, f16 K/V, batch 2048, ubatch 1024, threads
4, GPU layers 999, CPU MoE 0, FA auto, MTP OFF, cache-ram 0, ctx-checkpoints 0t,
seed 1234, temperature 0.2, top-p 0.8, ignore-eos, fixed 512 generated tokens,
resource monitor enabled, profiler OFF. Each model/context uses OFF/ON/ON/OFF
(ABBA), two observations per mode. All 16 normal runs report OK/exit 0.

- `GGML_VK_MOE_LEGACY_TILE_SELECTION=1` in every Vulkan run, including the earlier
  COMMON-001 Vulkan reference. This is legacy-token-count tile selection.
- `GGML_VK_GET_ROWS_128X4=0` throughout.
- `GGML_VK_QSA_UNION=0/1` is the OFF/ON change; minimum KV remains 32768.
- COMMON-001 split-PLE support is present in both backends; MoE tile and union
  switches are Vulkan-specific. ROCm does not consume the new FA selected-id hint.

Actual prompt sizes are 61789 / 126253 / 255181 tokens for 64k / 128k / 256k.
Input SHA256s, unchanged against the earlier reference:

| Input | SHA256 |
|---|---|
| 64k | `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751` |
| 128k | `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466` |
| 256k | `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788` |

## Logger-OFF normal results

Arithmetic means of the two logged tok/s values per mode. TG includes the
existing timing convention; these are whole-generation wall timings, not
profiler GPU sums.

| Model | Context | PP OFF | PP ON | PP gain | TG OFF | TG ON |
|---|---|---:|---:|---:|---:|---:|
| Original | 64k | 269.08 | 337.45 | 25.41% | 24.72 | 24.82 |
| PLE16 | 64k | 268.42 | 335.38 | 24.95% | 25.30 | 25.40 |
| PLE16 | 128k | 178.97 | 295.68 | 65.21% | 23.22 | 23.28 |
| PLE16 | 256k | 132.96 | 266.75 | 100.62% | 19.58 | 19.59 |

The 128k ON repeats are 295.67/295.69 tok/s; 256k ON repeats are
266.65/266.85. OFF also repeats closely. Mean PP time at 128k is 705455.395 ->
426990.990 ms (about 11m45s -> 7m07s); at 256k, 1919252.255 -> 956628.085 ms
(about 31m59s -> 15m57s). This is consistent with an attention-cost reduction
that matters more at long context. Union does not accelerate Q=1 decode.

ON CLI logs show the intended CM1 path (`path=1`), Br=16, Bc=64, f32 accumulation,
group=64 and min_kv=32768. The first eligible full-ubatch log shows 16 groups,
capacity=32768 and scratch=73400576 bytes. This bounded first-activation log is
not a peak scratch/memory measurement for later, larger KV lengths.

### PLE16 TG observation at 64k

PLE16 mean TG exceeds Original by 2.37% with union OFF and 2.32% with ON.
Original's four values range 24.43-25.00 tok/s; PLE16's range is 25.09-25.51.
Within each union setting, the generated stdout body matches across models and
repetitions after removing the timing line. The observation supports a small
PLE16 TG advantage in this batch, but Original was measured as a block before
PLE16. Model-order/time effects remain; reverse/interleave model order before
attributing a definitive layout speedup. PP is slightly slower on PLE16 here.
Do not conflate this model comparison with union's PP gain.

## Earlier COMMON-001 ROCm comparison

Same PLE16 file identity, input SHA256/prompt tokens, context, KV type, ubatch,
threads and MTP OFF. ROCm is one earlier run/context at b11380; union ON is two
runs/context at b11390. No matched new ROCm ABBA was performed.

| Context | Earlier ROCm PP | Vulkan union ON PP | Observed PP advantage |
|---|---:|---:|---:|
| 128k | 279.80 | 295.68 | +5.68% |
| 256k | 185.90 | 266.75 | +43.49% |

Earlier ROCm TG is 17.13/12.41 tok/s versus Vulkan ON 23.275/19.590.
Treat that TG comparison as descriptive: ROCm requested up to 1024 tokens and
stopped at EOS (610/532), while this ABBA uses fixed 512 tokens and seed 1234.
The PP comparison uses identical full prompt workloads, but remains cross-build
and cross-session evidence. The same-binary Vulkan OFF/ON is the causal union
comparison and is the stronger acceptance evidence.

## 64k profile gate

Original, 61789 prompt tokens, 128 generated tokens, profiler ON, same binary
and conditions except union. Two warmup blocks are excluded; all 61 PP blocks
are retained. Decode has 127 blocks; exclude its initial block for 126 steady
blocks. Existing FA operator timings include union/gather/synchronization.

| Metric | OFF | ON | Change |
|---|---:|---:|---:|
| PP wall throughput | 256.33 tok/s | 319.69 tok/s | +24.72% |
| Sum of GPU PP operator times | 231.370140 s | 184.324460 s | -20.33% |
| Sum of GPU PP FA times | 108.925958 s | 60.832516 s | -44.15% |
| Steady decode GPU total | 40.664906 ms/token | 40.509144 ms/token | -0.38% |
| Steady decode FA | 1.332667 ms/token | 1.333357 ms/token | effectively neutral |

First decode GPU time is 537.037 -> 42.6165 ms. Do not interpret the profile
wall TG (7.33 -> 7.53 tok/s) as a steady decode gain. Logger-OFF normal ABBA,
not profile throughput, decides the performance result. The below-threshold
fallback during warmup/early prefill is expected; eligible later prefill activates.

## Individual normal observations

| Run ID | Model | Context | Union | PP tok/s | TG tok/s | Status |
|---|---|---|---|---:|---:|---|
| 20261003-204204-659-cli-vulkan-b11390-ctx65536-270c1f3be974 | Original | 64k | OFF | 269.39 | 24.43 | OK |
| 20261003-204712-412-cli-vulkan-b11390-ctx65536-86205a02bfe0 | Original | 64k | ON | 337.61 | 24.86 | OK |
| 20261003-205134-916-cli-vulkan-b11390-ctx65536-86205a02bfe0 | Original | 64k | ON | 337.29 | 24.78 | OK |
| 20261003-205555-644-cli-vulkan-b11390-ctx65536-270c1f3be974 | Original | 64k | OFF | 268.76 | 25.00 | OK |
| 20261003-210104-618-cli-vulkan-b11390-ctx65536-0a06b619c5b5 | PLE16 | 64k | OFF | 268.50 | 25.51 | OK |
| 20261003-210601-314-cli-vulkan-b11390-ctx65536-6a15ad2b0765 | PLE16 | 64k | ON | 335.26 | 25.51 | OK |
| 20261003-211011-706-cli-vulkan-b11390-ctx65536-6a15ad2b0765 | PLE16 | 64k | ON | 335.50 | 25.28 | OK |
| 20261003-211421-900-cli-vulkan-b11390-ctx65536-0a06b619c5b5 | PLE16 | 64k | OFF | 268.33 | 25.09 | OK |
| 20261003-212722-644-cli-vulkan-b11390-ctx131072-bc2947304e56 | PLE16 | 128k | OFF | 179.07 | 23.23 | OK |
| 20261003-214016-150-cli-vulkan-b11390-ctx131072-e751bb864b78 | PLE16 | 128k | ON | 295.67 | 23.29 | OK |
| 20261003-214831-686-cli-vulkan-b11390-ctx131072-e751bb864b78 | PLE16 | 128k | ON | 295.69 | 23.26 | OK |
| 20261003-215647-118-cli-vulkan-b11390-ctx131072-bc2947304e56 | PLE16 | 128k | OFF | 178.87 | 23.21 | OK |
| 20261003-220942-956-cli-vulkan-b11390-ctx262144-c77b8afa9501 | PLE16 | 256k | OFF | 132.98 | 19.53 | OK |
| 20261003-224255-462-cli-vulkan-b11390-ctx262144-3ee87ad25060 | PLE16 | 256k | ON | 266.65 | 19.54 | OK |
| 20261003-230005-539-cli-vulkan-b11390-ctx262144-3ee87ad25060 | PLE16 | 256k | ON | 266.85 | 19.64 | OK |
| 20261003-231717-750-cli-vulkan-b11390-ctx262144-c77b8afa9501 | PLE16 | 256k | OFF | 132.94 | 19.62 | OK |

## Next priority

1. COMMON-002: inspect the fixed r4 upstream MTP implementation, then test the
   existing Unsloth Q8_0 sidecar on the current Vulkan build without restoring
   old compatibility patches blindly. Separate allocation/loading, short-context
   generation/acceptance and long-context PP overhead gates.
2. Keep Vulkan's validated union baseline fixed for those comparisons; explicitly
   set the switch in child runs because the code default remains OFF.
3. COMMON-005: defer its ROCm selected-K/V decode port; retain the historical r3
   evidence and ROCm alternative build. Resume when an actual ROCm use case needs it.
4. MTP-QSA remains separate from ordinary MTP compatibility and measurement.

See [R4-VULKAN002-IMPLEMENTATION-2026-10-03.md](R4-VULKAN002-IMPLEMENTATION-2026-10-03.md)
and [ROADMAP.md](ROADMAP.md). No upstream SHA or runtime default changes here.
