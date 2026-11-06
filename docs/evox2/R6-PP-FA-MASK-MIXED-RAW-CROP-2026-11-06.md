# r6 Vulkan FA mask: inspect individual F16 values inside MIXED tiles

Status: committed C++ diagnostic + Python renderer + 64k plan + static tests. Windows build, native F16 readback and actual GPU contents remain UNTESTED.

## Why this is necessary

The previous 2-bit mask tile report retains only ALL_NEG_INF (1), ALL_ZERO (2), or MIXED (0). It cannot show how many of the Br16 × Bc64 (1024) individual positions in a MIXED tile are masked. MIXED means neither all-negative-infinity nor all-zero; it is NOT the fraction of attended tokens.

The upper-right triangle in the 64×768 tile map is causally forced: with KV49152 and N1024, exactly 480 tiles are fully in the Query's future and must be ALL_NEG_INF for both corpora. All 480 were verified on the saved literature/code binaries.

The selected high-contrast region is query tile rows 32..35 and key tile columns 718..721, which covers Query token positions 48640..48703 and Key positions 45952..46207 (0-based, end inclusive). The old packed map contains 15 MIXED + 1 ALL_NEG_INF in code versus 7 MIXED + 9 ALL_NEG_INF in literature.

## GPU diagnostic design

Existing GGML_VK_FA_MASK_DIAG=1 must still be set; additional GGML_VK_FA_MASK_DIAG_RAW=1 opts in to the original F16 mask readback. GGML_VK_FA_MASK_DIAG_RAW_Q_TILE=32 and GGML_VK_FA_MASK_DIAG_RAW_K_TILE=718 specify the crop. Four-by-four full tiles are copied to a separate bounded 32 KiB GPU buffer using the source mask tensor's row stride. No full 64k×1024 readback, no new shader, no changes to attention results, no forced host GPU wait in the mask-opt hot path; the CPU reads only after the existing backend synchronization. Run-time shape/stride/window bounds are checked and invalid requests are rejected.

Outputs, using a fresh GGML_VK_FA_MASK_DIAG_FILE prefix, include the existing 2-bit .bin and .json plus new -raw.bin and -raw.json. Files are never silently overwritten. Raw F16 snapshots use IEEE754 float16 little-endian values. Because diagnostic GPU copies are added, PP tok/s from these runs is NOT a clean performance result.

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
