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
