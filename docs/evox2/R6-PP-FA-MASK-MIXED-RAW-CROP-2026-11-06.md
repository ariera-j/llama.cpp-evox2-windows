# r6 Vulkan FA mask: inspect individual F16 values inside MIXED tiles

Status: committed C++ diagnostic + Python renderer + 64k plan + static tests. Windows build, native F16 readback and actual GPU contents remain UNTESTED.

## Why this is necessary

The previous 2-bit mask tile report retains only ALL_NEG_INF (1), ALL_ZERO (2), or MIXED (0). It cannot show how many of the Br16 × Bc64 (1024) individual positions in a MIXED tile are masked. MIXED means neither all-negative-infinity nor all-zero; it is NOT the fraction of attended tokens.

The upper-right triangle in the 64×768 tile map is causally forced: with KV49152 and N1024, exactly 480 tiles are fully in the Query's future and must be ALL_NEG_INF for both corpora. All 480 were verified on the saved literature/code binaries.

The selected high-contrast region is query tile rows 32..35 and key tile columns 718..721, which covers Query token positions 48640..48703 and Key positions 45952..46207 (0-based, end inclusive). The old packed map contains 15 MIXED + 1 ALL_NEG_INF in code versus 7 MIXED + 9 ALL_NEG_INF in literature.

## GPU diagnostic design

Existing GGML_VK_FA_MASK_DIAG=1 must still be set; additional GGML_VK_FA_MASK_DIAG_RAW=1 opts in to the original F16 mask readback. GGML_VK_FA_MASK_DIAG_RAW_Q_TILE=32 and GGML_VK_FA_MASK_DIAG_RAW_K_TILE=718 specify the crop. Four-by-four full tiles are copied to a separate bounded 32 KiB GPU buffer using the source mask tensor's row stride. No full 64k×1024 readback, no new shader, no changes to attention results, no forced host GPU wait in the mask-opt hot path; the CPU reads only after the existing backend synchronization. Run-time shape/stride/window bounds are checked and invalid requests are rejected.

Outputs, using a fresh GGML_VK_FA_MASK_DIAG_FILE prefix, include the existing 2-bit .bin and .json plus new -raw.bin and -raw.json. Files are never silently overwritten. Raw F16 snapshots use IEEE754 float16 little-endian values. Because diagnostic GPU copies are added, PP tok/s from these runs is NOT a clean performance result.

## Mandatory short F16 smoke before any 64k run

After updating and rebuilding the diagnostic Vulkan binary, run a separate 1024-token raw crop first. The plan targets q tile32 and k tile8 at KV1024, which includes a causal boundary. This guards against an expensive repeated 64k benchmark when the GPU readback or F16 decoding is incorrect.

~~~powershell
$smoke = '.\tools\evox2\benchmark\configs\qwen38-r6-fa-mask-raw-1024-smoke-20261106.psd1'
$dir = 'C:\llama-build\evox2-ppdiag-mask'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($suffix in @('.bin','.json','-raw.bin','-raw.json')) {
    $p = Join-Path $dir ('raw-smoke-1024-q32-k8' + $suffix)
    if (Test-Path -LiteralPath $p) { throw "Existing snapshot: $p. Select a new unique prefix." }
}
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $smoke -OnlyVariant raw-mask-smoke-1024 -StopOnError
python .\tools\evox2\benchmark\visualize_fa_mask_raw.py --prefix "$dir\raw-smoke-1024-q32-k8" --out "$dir\raw-smoke-1024-zoom.svg"
~~~

Require exit0, a 32768-byte raw binary, raw status=wrote in stderr, and a 16-tile crosscheck PASS from Python. Then proceed to the subsequent existing 64k code and literature instructions. Preserve all failed/previous evidence and use a new prefix for retries.

## Windows commands (investigation branch only)

~~~powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git pull --ff-only
python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_mask_raw.py' -v
.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-ppdiag-rgp -VulkanSdk 'C:\VulkanSDK\1.4.357.0' -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4 -BuildOnly
~~~

Use the same pinned CMake executable and expected version as the earlier successful build, if applicable. Confirm that R6PpFaRgpVulkan in the local config selects this newly built diagnostic Vulkan binary, not the production r6 one.

~~~powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-fa-mask-raw-4x4-64k-20261106.psd1'
$dir = 'C:\llama-build\evox2-ppdiag-mask'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($stem in @('raw-code-49152-q32-k718','raw-literature-49152-q32-k718')) {
  foreach ($suffix in @('.bin','.json','-raw.bin','-raw.json')) {
    $p = Join-Path $dir ($stem + $suffix)
    if (Test-Path -LiteralPath $p) { throw "Output already exists: $p. Set a new prefix in the plan." }
  }
}
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant raw-mask-code -StopOnError
~~~

Check status OK, exit 0, normal ADLX/Windows memory/P-MODE, and a raw status=queued and status=wrote in stderr (the existing packed 2-bit status=wrote is separate). Confirm code raw binary length 32768 bytes and raw JSON KV49152, q_tile_start32, k_tile_start718, rows64, columns256.

~~~powershell
$vis = '.\tools\evox2\benchmark\visualize_fa_mask_raw.py'
python $vis --prefix "$dir\raw-code-49152-q32-k718" --out "$dir\raw-code-zoom.svg"
~~~

The stdlib-only Python renderer classifies every F16 element as -infinity, zero, or other; for each of 16 tiles it computes the masked/unmasked element counts and derives its original 2-bit code. It refuses success if any tile does not match the saved 2-bit bitmap. It generates zoom SVG and per-tile JSON.

Only if the code capture and 16-tile crosscheck PASS, optionally repeat for literature:

~~~powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant raw-mask-literature -StopOnError
python $vis --prefix "$dir\raw-literature-49152-q32-k718" --out "$dir\raw-literature-zoom.svg"
~~~

Upload run ZIPs and four files per captured corpus plus zoom SVG/JSON. The raw files are outside benchmark ZIPs. STOP on any TDR, DeviceLost, OOM, memory pressure, wrong mask identity, code-vs-packed mismatch, or P-MODE drift.

## 2026-11-06 b12117 raw-smoke PASS — native Windows evidence

Both GPU readbacks succeeded: 2-bit mask classification and original F16 mask crop. Native Vulkan b12117 (commit 7bb6e926f), Unsloth IQ3_XXS PLE16, literature SHA256 8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143, prompt1024, context2048, UBatch1024, no warmup, QSA UNION OFF. Query Qcur-19, KV1024, Br16/Bc64. Cropped F16 query tiles32..35 and key tiles8..11; 64x256 elements.

- User benchmark ZIP: 20261106-194323-694-bench-vulkan-b12117-ctx2048-a069bebf170f.zip, SHA256 487e091407d013c79ae0f9e6ee7b5f63922920cae1242458babb1eef3c798fb8.
- User snapshot ZIP: raw-smoke-1024-zoom.zip, SHA256 80a1b462e4a9e59c74a2b032d203596a0219f7b314ecaec92b2d8f4e172260c6.
- F16 raw bin: 32768 bytes, SHA256 4df00ba6eadc52585f1423d3badd90b04b44488c20c8c34116623a570d2794d9. Original 2-bit bin: 256 bytes, SHA256 1ce6be7bb824511ae407f581cc73662682c69d50fad47200232399e1e2ef3a62.
- Status OK / ExitCode0; stderr raw status=queued then status=wrote plus packed status=queued then status=wrote, both for KV1024, Qcur-19. An earlier not_captured message was from another context, not an error in the successful target context. Rendered zoom JSON packed_2bit_crosscheck=PASS.
- Independent F16 scan: exactly 14,304 -infinity, 2,080 zero, 0 other/NaN in all 16,384 sampled positions. Allowed fraction 12.6953125%. Exactly 4 MIXED and 12 ALL_NEG_INF 16x64 tiles. Four MIXED tiles (key tile8) have 136, 392, 648, 904 allowed elements respectively. Every one of the 16 tile codes matched packed 2-bit data.
- Strongest check: every one of 16,384 raw elements matches causal mask value 0 iff global key index <= query index; otherwise -infinity. Independent F16 vs causal calculation produced ZERO cell mismatches.
- Performance P-MODE remained constant, ADLX exit0 with 24 samples, resource monitor 24 samples, min available Windows RAM 22.748 GiB, peak ADLX VRAM 80,934 MiB, no recorded OOM/TDR. PageInputs/sec elevated during mapped-model-loading span; high counters do not alone demonstrate pagefile pressure. Single-run 527.171 tok/s is DIAGNOSTIC ONLY and must not be compared with clean PP.

Gate: F16 RAW 1024 SMOKE PASS. Proceed to separate 64k code-only capture (query tiles32..35 / key tiles718..721 / KV49152), verify metadata and 16-code F16 crosscheck, then run literature. 64k long-context contents remain unverified.

## 2026-11-06 64k code raw mask PASS — exact mixed-tile occupancy

Native 64k single run on Vulkan b12117 (commit 7bb6e926f), IQ3_XXS PLE16, head of source code `llamacpp-inference-code.txt` SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`; `-p61777 -c65536 -ub1024 -b2048 -n0 -d0 -r1`, no warmup, f16 KV, QSA UNION OFF. Existing raw-F16 target `Qcur-19` KV49152, Q tiles32..35, K tiles718..721, global Q48640..48703, global K45952..46207, Br16×Bc64, 16 raw tiles = 64×256 individual F16 values.

Uploaded evidence:
- Native run ZIP `20261106-195305-451-bench-vulkan-b12117-ctx65536-eab0e8da254f.zip` SHA256 `8153b158a0a5af2c58a5663a9c166fd59502c1d5dddfc66228638d03f294f6a0`.
- Raw and rendered ZIP `raw-code-zoom.zip` SHA256 `9b7ca815bd809ee6aec60572b97fa549264b65b870484585810a03ac6bbeaff5`.
- Packed 2-bit binary 12288 bytes, SHA256 `71a23eede6dbb382e8c520ea27b2caae28a6122460b0d5bef6e9eb554ea463dc`; original F16 32768 bytes, SHA256 `6d12872293810e50040a1ae52e67b661410f4a6eea3dec6b5748e68085a31922`.

Status `OK`, `ExitCode=0`; diagnostics `evox2_vk_fa_mask_diag_v1 status=queued/wrote` and `evox2_vk_fa_mask_raw_v1 status=queued/wrote` both present in stderr at KV49152. Earlier `not_captured` from transient other backend context does not override successful target write. Native PP 383.459 tok/s (161.105s, **diagnostic-only**, do not compare against stock). ADLX 173 samples, resource monitor 171, P-MODE Performance start/finish unchanged; high-GPU-power classifier consistent (mean high-load 119.1W), minimum free Windows RAM 22.75GiB, maximum GPU committed 81.13GiB, ADLX VRAM max 83,168MiB. No OOM/driver-reset indication in the provided run logs. RDP-Tcp session. Background-process sampling PartialCoverage; does not certify no interference.

### Independently decoded F16 and packed two-bit tile occupancy

- All 16,384 F16 mask values are either exact `-inf` (15,392 = **93.9453125%**) or `0` (992 = **6.0546875%**), with no NaN or other values. The *four-by-four tile region* contains **15 MIXED + 1 ALL_NEG_INF**, matching **all 16 original packed codes** exactly (`packed_2bit_crosscheck=PASS`).
- Code tile distribution is therefore **93.75% tiles marked MIXED but only 6.05% individual entries unmasked**. Mixed tile classification is a uniformity test; it does not imply high density of unmasked entries.

| Query tile | K718 allowed /1024 | K719 allowed /1024 | K720 allowed /1024 | K721 allowed /1024 | Q tile total allowed /4096 |
|---|---:|---:|---:|---:|---:|
| Q32 | 128 | 116 | 36 | 64 | 344 |
| Q33 | 12 | 40 | 20 | **0 (ALL_NEG_INF)** | 72 |
| Q34 | 40 | 68 | 60 | 176 | 344 |
| Q35 | 48 | 16 | 40 | 128 | 232 |
| Total | 228 | 240 | 156 | 368 | **992** |

- Additional precise observation: for each of 64 Query rows, the binary mask is **uniform in every consecutive group of four KV positions** within the 256-column crop; there are exactly 248 unmasked four-token groups out of 4,096 such groups. Query rows themselves are not constant in groups of 2/4/8, and some individual Query rows have zero unmasked keys in this crop.
- This region lies entirely in the past of the sampled Query positions (`K ≤ 46207`, `Q ≥ 48640`), so causal future-masking cannot account for these `-inf` values. Their structured sparsity must be explained by a separate mask-selection mechanism; exact creating code and its semantic interpretation have NOT yet been verified.
- These are **mask allowed positions**, NOT actual post-softmax attention weights or the number of GPU FLOPs the shader saved. In the current mask-opt scheme, only the one fully-negative-infinity tile in this crop is trivially skippable as an entire tile, even though 93.95% of F16 elements are individually masked. This offers a testable explanation for why many MIXED tiles can still imply GPU work.

### Next step

64k **code** raw F16 gate PASS. Run `raw-mask-literature` with the identical Q32..35 K718..721 geometry and `KV49152` target, then validate its 16 packed labels, F16 values and P-MODE/memory. Compare *element-level allowed fraction*, not only mixed tile count (literature has 7 MIXED and 9 ALL_NEG_INF at the same coordinates in prior 2-bit capture). Broader relevance to end-to-end PP awaits multi-window and separate RGP timing comparisons.
