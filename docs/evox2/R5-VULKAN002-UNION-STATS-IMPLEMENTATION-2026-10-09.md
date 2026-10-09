# r5 VULKAN-002 optional union statistics — selective source port / Windows handoff

Recorded: 2026-10-09. Branch: `r5/upstream-refresh-20261009`.

**Source ported; Windows Vulkan build b11535, STATS=0 CLI and STATS=1 CSV smoke PASSED (2026-10-09).** A repeat of the native 18/18 OFF/ON test on the statistics binary was not included in this evidence. The **pre-stats b11530 matrix completed (12/12 OK)**: [r5 validation](R5-VULKAN002-VALIDATION-2026-10-09.md). Preserve that tested binary and its logs; compile diagnostics in a **different build directory**. Phase B correctness 18/18 OFF+ON passed, and Phase B 64k PLE16 A/B PP 269.44→338.71 tok/s (+25.71%) is recorded at [r5 Phase B](R5-VULKAN002-IMPLEMENTATION-2026-10-09.md). That earlier run is the preserved STATS=0 baseline.

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

As of 2026-10-09, r5 STATS OFF/ON 64k smoke data are now available and passed. A post-stats native reference test rerun, and fuller matched A/B performance repetition, are not yet evidenced. The completed pre-stats b11530 12-run matrix remains authoritative for normal VULKAN-002 64k/128k/256k throughput; see [accepted results](R5-VULKAN002-VALIDATION-2026-10-09.md).

## r5 Windows b11535 64k runtime verification (2026-10-09)

Source user ZIP (raw artifacts held outside Git): `20261009-220633-703-bench-vulkan-b11535-ctx65536-ea3fb4e261b7.zip` includes **one** STATS=0 `llama-cli` 64k full-model run plus **one** STATS=1 `llama-bench` 64k real-prompt run and the actual `qsa-union-stats.csv`. Both results report `Status=OK`, ExitCode=0, Vulkan0/AMD Radeon 8060S, clean source build SHA `fbb6e15bdfe85737683c56c74ab7fae13d520f17` (b11535, Clang 20.1.8). Both logged `qsa-union active (r5)` and fallback where expected. This accepts the *observed statistics data path*, not untested GPU platforms or full model output parity.

### ② STATS=0 ordinary CLI no-regression smoke

- Run ID: `20261009-215859-763-cli-vulkan-b11535-ctx65536-038a925d976b`.
- Binary `llama-cli.exe` SHA256 `214a6e3c4175e5db838a8824651d01e3cab0ee4caa6a8fc44791f2192d0df78b`; runtime artifact digest `43ecfa03065bc879bab5e3ce861970d8273976bdbe0f10b5878ee629dd4c67ec`, runtime verified.
- `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_STATS=0`; PLE16, original **64k** input `nlp-survey-ch3-d7-b1.txt`, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; 61,789 tokens, ctx=65,536. Same measured parameters as the pre-stats PLE16 ABBA: MTP off, f16 KV, batch/ubatch 2048/1024, threads 4, GPU layers 999, CPU MoE 0, FA auto, 512 fixed generated tokens, seed 1234, ignore-EOS, temperature 0.2, top-p 0.8, `--ctx-checkpoints 0t`, cache-ram 0, `-tb 4`.
- **PP=337.84 tok/s (182,894.46 ms)**, **TG=25.35 tok/s (20,155.34 ms)**; compare pre-stats b11530 PLE16 64k **ABBA ON mean PP=339.48, TG=25.80**, giving **PP −0.48%, TG −1.74%**. A single new run versus prior two-run mean does *not* demonstrate a meaningful regression or establish statistical equivalence. There were no detected errors and no stats CSV in this CLI run. STATS-off baseline smoke **PASS**.

### ③ STATS=1 llama-bench union CSV verification

- Run ID `20261009-220633-703-bench-vulkan-b11535-ctx65536-ea3fb4e261b7`. Binary `llama-bench.exe` SHA256 `9d32422898d4c8038acc3da9c8e3045841726d8cf1df6cea2e68241e4c707159`.
- `GGML_VK_QSA_UNION=1`, `GGML_VK_QSA_UNION_STATS=1`, bin size 16384, PLE16, `-c 65536 -p 61789 -n 0 -d 0 -r 1 -b 2048 -ub 1024 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 --no-warmup`.
- The actual **bench** source is `nlp-survey-ch3-d31-b1.txt` (**256k source file**, 1,261,235 bytes, SHA256 `63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`), extracted with `--prompt-slice head-tail` to 61,789 tokens. It is **not the same exact 64k text file as CLI**; do not infer head-to-head PP differences. `llama-bench` recorded 335.508686 tok/s under statistics instrumentation, **not** used as the normal PP baseline.
- Valid run-local `qsa-union-stats.csv` contains **30 rows, 5,640 sampled groups, dropped_groups=0 in every row**. All rows have groups>0; integer-padded min/max multiples of 256; 0 < unique_min <= unique_mean <= unique_max; 0 < padded_min <= padded_mean <= padded_max; unique_mean <= padded_mean; selected_mean >= unique_mean; KV bins valid and sync 0..29 sequential. `qsa-union active (r5)` and fallback logged in stderr. **STATS=1 CSV collection/format gate PASS.**

Rows are **per-sync/per-16k-KV-bin aggregate**, not per-token or per-run; the table below uses group-weighted averages:

| KV-bin start | CSV rows | Sum groups | Unique mean | Padded mean | Selected mean | Unique / selected |
|---:|---:|---:|---:|---:|---:|---:|
| 32768 | 16 | 3072 | **16815.04** | 16943.08 | 131264.00 | 12.810% |
| 49152 | 14 | 2568 | **18293.45** | 18415.75 | 130928.56 | 13.972% |
| **Combined** | **30** | **5640** | **17488.18** | **17613.62** | **131111.27** | **13.338%** |

Historical r4 stats investigation reported approx **16863** at bin 32768, **18289** at bin 49152 and **17512** global unique mean for a 64k real-document run. r5 b11535 values are close (−0.28%, +0.02%, and approx −0.14%) but **the 64k real-text input and test runs are not proven identical**; r4 report recorded a different source/input SHA. Similarity strongly supports correct instrumentation, not same-input deterministic equivalence. `selected` counts invalid candidate slots, so `unique/selected` is not a pure duplicate rate.

### Post-verification status / recommended next steps

- **Passed:** Windows build, 64k STATS=0 normal CLI smoke (no evident PP regression), 64k STATS=1 actual Vulkan CSV with no dropped groups, r4-like bins/union values. The new source commit contains no non-opt-in shader changes.
- **Not evidenced in the supplied ZIP:** a repeat of the **18/18 OFF and 18/18 ON** targeted `Test-QsaUnion.ps1` on b11535; the prior **pre-stats** b11530 correctness suite passed both modes. No extra performance sampling on b11535 was performed. Keep this distinction explicit.
- Begin genre-specific 64k diagnosis with the same 61,789 raw token target where possible, record source commit/transformer, SHA256 of actual input and the model's tokenizer count, and use a common `PromptSlice` choice (prefer `head` for sequential literary texts). Compare unique/padded/selected counts from STATS=1, and PP independently with STATS=0. The literary full-file counts reported by the user are Japanese `吾輩は猫である` 251,252 and English `The Count of Monte Cristo` 668,434; both cover 64k/128k targets, only English covers previous exact 255,181-token 256k target.
