# R6: KV49152 / Qcur-19 FA 2-bit mask column-stripe analysis (2026-11-06)

**Status:** completed offline analysis of already captured 64×768 packed 2-bit FA mask maps. No new 64k GPU execution or changes to Vulkan runtime. Both input masks have identical query `Qcur-19 (view) (permuted)`, KV49152, N1024, Br16, Bc64, 64 Query-tile rows × 768 Key-tile columns, one slice. The analysis decodes every 2-bit code directly and independently checks counts. Codebook: 0=MIXED, 1=ALL_NEG_INF, 2=ALL_ZERO, 3=INVALID (none).

**Provenance:** user's `literature-49152.zip` including both code/literature binary masks and metadata; code `code-49152.bin` SHA256 `71a23eede6dbb382e8c520ea27b2caae28a6122460b0d5bef6e9eb554ea463dc`, literature `literature-49152.bin` SHA256 `bfaefa1a07ed611f1b2fe680f2b02d4d04c7c967bcabaab593ebe4795f1e6142`. Identical hashes were recovered from the later 64k F16 raw-crop capture ZIPs, thus the global masks analyzed here match those independently validated runs.

## Overall and regional distributions

| Quantity | Code | Literature |
|---|---:|---:|
| MIXED /49152 | 12200 (24.82%) | 31638 (64.37%) |
| ALL_NEG_INF /49152 | 36860 (75.00%) | 17512 (35.63%) |
| ALL_ZERO /49152 | 92 (0.19%) | 2 (0.004%) |
| MIXED rate for Key tokens 0..40959 (640 KV columns) | 13.4326% | 61.8237% |
| MIXED rate for Key tokens 40960..48127 (112 KV columns) | 86.8164% | 80.5386% |
| Zero-MIXED columns in first 640 | **205** | **0** |
| 64-of-64-MIXED columns in first 640 | **4** (0,16,28,41) | **21** |
| Coefficient of variation (SD/mean) of mixed Query-row counts per first-640 KV column | **1.531** | **0.389** |
| Interior KV columns with local prominence >=40 extra MIXED Query rows versus 8-neighbor median | **11** | **0** |

Here `local prominence` = MIXED row count in column c minus the median of counts in columns c-4..c-1 and c+1..c+4, 64 query rows each; for the >=40 count only columns 4..635 are included to avoid truncated neighborhoods. These threshold-defined findings provide a quantitative definition of the narrow vertical stripes observed in code. Note that literature has 21 fully-MIXED columns too, but often their neighbors are also highly MIXED; isolated contrast is less pronounced.

## Candidate strongly isolated KV columns

| KV tile column | Key token positions (0-based inclusive) | Code MIXED /64 Q tile rows | Literature MIXED /64 | Code local neighbor median /64 | Code longest consecutive MIXED run |
|---|---|---:|---:|---:|---:|
| 28 | 1792..1855 | 64 | 26 | 6 | 64 |
| 41 | 2624..2687 | 64 | 38 | 11 | 64 |
| 93 | 5952..6015 | 60 | 17 | 14 | 37 |
| 470 | 30080..30143 | 59 | 51 | 5.5 | 31 |
| 160 | 10240..10303 | 53 | 64 | 8 | 16 |
| 16 | 1024..1087 | 64 | 24 | 31.5 | 64 |

Example: for code column28, neighboring columns27 and29 have only 18 and 4 mixed Query rows, respectively, whereas c28 has all64. Code c41 has 64/64 versus neighbors16 and13. Thus these are true persistent spatial stripes, not only SVG color artifacts. But a column being MIXED for all Query tiles does **not** prove the exact same Key tokens are unmasked by every Query (tile-classification is much coarser).

## Abrupt code regime change at 41k

| Key 1024-token interval | Code MIXED | Literature MIXED |
|---|---:|---:|
| 39936..40959 | 0.5% | 81.3% |
| 40960..41983 | 36.8% | 60.9% |
| 41984..43007 | 80.7% | 74.3% |
| 43008..44031 | 97.9% | 83.9% |
| 46080..47103 | 99.8% | 82.5% |

For code, **54 of its 58 all-64-row MIXED columns occur after 40960**, whereas 205 zero-MIXED columns occur before 40960. The corresponding literature mask is more uniformly distributed across the entire KV extent. Previous source token-piece inspection located the switch from `src/llama-arch.h` to `src/llama-batch.cpp` around 42k, but the mask change begins before the file boundary; causation by source boundaries is unproven.

## Meaning and limitations

- Both maps describe the same 1024-token Query window: global Query token48128..49151; each of the 64 Query tile rows represents 16 consecutive Query tokens. A persistent vertical stripe is **a specific 64-token Key region classified as MIXED across many different Query tile rows**, meaning at least one unmasked or nonzero value prevents an ALL_NEG_INF/ALL_ZERO classification per tile. It does not establish per-token selection, exact Key identity, or semantic importance.
- Earlier separate raw F16 inspection at far-later Key tokens45952..46207 found 15/16 code tiles MIXED but only **6.05%** of individual entries unmasked, versus 5/16 literature tiles MIXED and **3.42%** unmasked. These numbers cannot be extrapolated to early isolated columns c28 or c41.
- A common future-masked causal triangle forces 480 all-negative-infinity tiles at the upper right for both corpora. The early stripes occur far to the left and are not causally required by the Query-vs-Key position ordering.
- Most-likely follow-up target: capture original F16 mask at `GGML_VK_FA_MASK_DIAG_RAW_Q_TILE=32`, `GGML_VK_FA_MASK_DIAG_RAW_K_TILE=28` (4x4 tile crop), code first; this samples the persistent early KV stripe and adjacent low-MIXED columns with 64×256 F16 values. A full 64k rerun is required to obtain that new raw crop. Separately, use the exact model tokenizer to relate Key positions1792..1855 to source-document text; the 2-bit masks alone cannot do this.
- Do **not** infer model attention weights or clean PP speedup from these tile-classification rates. Separate instrumentation-OFF bench and RGP timings are necessary for performance attribution.

## Reproducible offline artifacts

CSV, PNG, JSON and Python analysis script were packaged in the conversation attachment `fa-mask-column-analysis-20261106.zip`; its `fa-mask-input-49152.zip` contains the original four `.bin/.json` inputs. CSV files: `kv_column_64token_detail.csv`, `kv_1024token_bins.csv`, `query_row_16token_detail.csv`, `code_isolated_stripe_candidates.csv`; plots compare 1024-token regions and per-64-token columns, and show independent code/literature 64×640 binary heatmaps. Requires numpy+matplotlib. The experiment branch has no binary data committed.
