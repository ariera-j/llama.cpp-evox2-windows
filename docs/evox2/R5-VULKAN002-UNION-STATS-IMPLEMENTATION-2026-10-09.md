# r5 VULKAN-002 optional union statistics — selective source port / Windows handoff

Recorded: 2026-10-09. Branch: `r5/upstream-refresh-20261009`.

**Source implemented, Windows build/runtime validation PENDING.** The **pre-stats b11530 matrix completed (12/12 OK)**: [r5 validation](R5-VULKAN002-VALIDATION-2026-10-09.md). Preserve that tested binary and its logs; compile diagnostics in a **different build directory**. Phase B correctness 18/18 OFF+ON passed, and Phase B 64k PLE16 A/B PP 269.44→338.71 tok/s (+25.71%) is recorded at [r5 Phase B](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md). That earlier run is the preserved STATS=0 baseline.

## Port details

- Source donor: `investigation/vulkan-qsa-union-stats-20261008` at `979ef17eeff14440a58c866a966b355a1b63b17e`. Extract **only** native commits `0f855134246e22cb63c41ec6a58e6c2423bd19dc`, `53ba50a8de25df0bfc0df455c30f2090a99986d6` and wrapper `1f04f9b679a60640279e5e3af833569dca1e6f0d`; the original investigation branch includes other r4 changes and must not be merged wholesale.
- r5 source port: [`37ba95673a061c1b4c0991e8eeea5eb003bbe898`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/37ba95673a061c1b4c0991e8eeea5eb003bbe898). Exactly three modified files: `ggml/src/ggml-vulkan/ggml-vulkan.cpp`, `ggml/src/ggml-vulkan/ggml-vulkan-types.h`, `tools/evox2/benchmark/Measure-LlamaBench.ps1`. Native functionality and wrapper port hunks matched the r5 source contexts; top-of-file includes were adapted to r5 (which no longer has `ggml-mtp-diag.h`). No shader, attention arithmetic, union activation threshold, model, or `llama-bench.cpp` changes.
- `GGML_VK_QSA_UNION_STATS=1` is required; its default is OFF. Requires `GGML_VK_QSA_UNION=1` to encounter relevant kernels. `GGML_VK_QSA_UNION_STATS_KV_BIN` defaults 16384 (power-of-two, supported 1024..262144). `GGML_VK_QSA_UNION_STATS_FILE` selects output location; default filename `qsa-union-stats.csv`. The bench wrapper automatically places it in each run directory if unset and restores the inherited environment.
- Each group already computes four 32-bit counters in `qsa_union.comp`: padded KV count, true unique count, candidate selected slots and n_kv. STATS=1 alone copies 16 bytes/group GPU→GPU into a bounded 65536-record device buffer; sync waits before a single CPU readback and KV-bin CSV aggregation. `dropped_groups` explicitly exposes overflow. STATS=0 avoids buffer allocation, copies, CSV and additional diagnostics barriers/readback.
- CSV columns: `sync,kv_bin_start,kv_bin_end,groups,unique_mean,unique_min,unique_max,padded_mean,padded_min,padded_max,selected_mean,unique_over_selected,padded_over_selected,dropped_groups`.
- Important: `selected_mean` includes invalid slots, so `unique_over_selected` is not a strict duplicate ratio; `padded_mean` approximates the KV length actually processed by FA. CSV may include warmup, and each row is one KV bin **per backend sync**, not one complete run. Aggregate using `groups` as weights. **Do not use STATS=1 throughput as an ordinary speed result**.

## Windows build — only after old matrix completes or in a separate independent checkout

Use a **new** build directory, preserving `build-vulkan-qsa-union\bin\Release` (b11530).

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r5
git pull --ff-only

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-qsa-stats `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4

& '.\build-vulkan-qsa-stats\bin\Release\llama-cli.exe' --version
& '.\build-vulkan-qsa-stats\bin\Release\llama-bench.exe' --help
```

In ignored `tools/evox2/benchmark/configs/local.psd1` add `Builds.R5QsaStatsVulkan` with `BinDir='C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-qsa-stats\bin\Release'` and `ExpectedBackend='Vulkan'`. Do **not** repoint the existing `R5QsaUnionVulkan` key/binary, especially while the previous matrix is running.

## Minimum confidence gates before genre/long-context experiments

**Gate 1 — STATS OFF source regression.** New binary, matching original 64k PLE16 `llama-cli` workload and `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_STATS=0`. Compare PP to the stronger pre-stats b11530 **64k PLE16 ABBA ON mean 339.48 tok/s** (339.64/339.32; two runs; ordinary run-to-run variance), TG **25.80 tok/s**, actual active path, resulting text identity/status and binary hash. If materially different, repeat before attributing regression. For optional r5 native test repeat, run `Test-QsaUnion.ps1 -BinDir .\build-vulkan-qsa-stats\bin\Release -Backend Vulkan0`; expect 18/18 OFF and ON and r5 activation/fallback. No need to repeat all longctx yet.

**Gate 2 — STATS ON CSV correctness.** Use an existing 256k source file to supply **at least** 61,789 raw tokens at 64k context; the old 64k Jinja input file might tokenize to less than 61,789 raw tokens. The example below uses `InputKey '256k'` for this reason, but measures only 64k prompt:

```powershell
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_STATS = '1'
$env:GGML_VK_QSA_UNION_STATS_KV_BIN = '16384'
try {
    .\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
      -BuildKey R5QsaStatsVulkan -ModelKey UnslothPle16 `
      -InputKey '256k' -PromptSlice head-tail `
      -Context 65536 -PromptTokens 61789 -GenerationTokens 0 `
      -Depths 0 -Repetitions 1 -NoWarmup `
      -KvType f16 -Batch 2048 -UBatch 1024 `
      -Threads 4 -GpuLayers 999 -CpuMoe 0 -FlashAttn auto
} finally {
    Remove-Item Env:GGML_VK_QSA_UNION -ErrorAction SilentlyContinue
    Remove-Item Env:GGML_VK_QSA_UNION_STATS -ErrorAction SilentlyContinue
    Remove-Item Env:GGML_VK_QSA_UNION_STATS_KV_BIN -ErrorAction SilentlyContinue
}
```

Verify `Status=OK`/ExitCode=0, `qsa-union active (r5)`, nonempty run-local `qsa-union-stats.csv`, correct header, `groups>0`, `dropped_groups=0`, positive `unique_mean <= padded_mean`, and bounds relative to `selected_mean`. `STATS=1` is a diagnosis run and its PP is not compared to 339.48 CLI tok/s.

If the CSV is missing or dropped/nonphysical counts appear, attach `stderr.log`, `conditions.json`, `result.json` and `qsa-union-stats.csv` and investigate before running large diagnostic matrices.

**Gate 3 — STATS OFF impact:** compare old b11530 and new-binary STATS OFF same workload, with warmup/order conditions noted, and recheck that `GGML_VK_QSA_UNION_STATS=0` causes no diagnostic buffer copy/readback or CSV. The code is intended to do nothing for STATS OFF, but equality of performance is **not proven** by code inspection.

## Subsequent planned document comparisons

Begin with 64k, one stats-enabled run per input; avoid changing the tested model or backend. Compare the same number of raw tokens and `--prompt-slice` settings with input SHA256 records:

- Japanese repeated ANLP data (existing), Japanese non-repeating literary (`吾輩は猫である` after Shift_JIS→UTF-8), Japanese non-repeating technical source if found.
- English `The Count of Monte Cristo` novel, optional open-licensed English technical text.
- Code: files from the pinned upstream `llama.cpp` repository commit; store file manifest/paths/order and avoid vendored/third-party or generated sources.
- Random-token control.

Prefer weighted `unique_mean`, `padded_mean`, `unique_over_selected` (interpreted carefully) and KV-bin trend to unweighted averages. Use STATS OFF for speed separately. Extend to 128k/256k only if token count allows and earlier runs show meaningful differences.

## Status

As of this source commit, **only the r4 investigation branch has actual CSV evidence**. r5 CSV, compile, short smoke and non-regression checks require Evo-X2 runtime validation. The completed pre-stats b11530 12-run matrix remains authoritative for VULKAN-002 64k/128k/256k throughput; see [accepted results](R5-VULKAN002-VALIDATION-2026-10-09.md).
