# Gate 2: Vulkan 2-bit FA mask tile snapshot and SVG visualization (2026-11-06)

**Status:** source + Python visualization + synthetic static tests + 1024 smoke plan committed; **Windows build, on-device snapshot, and sample image not tested yet**. Do not treat this as Gate 2 GPU PASS until a real short capture is decoded and verified.

## What this records

This selectively ports r5's GPU->GPU one-shot copy into r6 and **preserves each packed 2-bit tile code** instead of discarding spatial coordinates after row-count aggregation. The underlying existing `fa_mask_opt` shader and the normal `flash_attn_cm1` computation are unchanged. Captures occur only when all match: `GGML_VK_FA_MASK_DIAG=1`, literal integer KV, case-sensitive query prefix, actual `N=1024`, mask-opt path enabled, no earlier capture by that context. Uses at most **1MiB** independent GPU snapshot buffer. No new FA shader, dispatch or forced CPU-side synchronization in the hot path. GPU copy is scheduled after the existing mask-opt dispatch, and host readback is deferred to the **existing backend synchronize** after its fence completes.

Two outputs, one-shot, with an explicit **no-overwrite guard**:
- `<prefix>.bin`: raw packed little-endian uint32, 16 successive 2-bit codes per word, row-major per slice, padding to `words_per_row`. Codes: **0 MIXED**, **1 ALL_NEG_INF**, **2 ALL_ZERO**, **3 INVALID/reserved**.
- `<prefix>.json`: `schema_version=1`, `source`, `word_encoding`, `query`, KV, N, Br/Bc, `n_kv_max`, mask ne0, row stride, logical tiles per row, row count, slice count, binary payload byte count, and codebook.

Logs: `evox2_vk_fa_mask_diag_v1 status=queued/wrote/not_captured/rejected`; not_captured happens when target match never occurs (e.g., wrong KV/query/FA path). Missing parent output directories or preexisting files cause explicit failure rather than silently choosing another location.

**Caveat:** it captures **mask tile classification metadata**, not the raw attention mask and not proof that FA actually avoided every marked tile; some mixed tiles may also be skipped by a separate shader check. Snapshot ON timings cannot be compared with clean PP or RGP durations.

## Native Windows preparation

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_mask_tiles.py' -v
python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_mask_gate2_source.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-ppdiag-rgp `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4 -BuildOnly
```

Reuse the already validated explicit CMake path/options where applicable. This is a NEW diagnostic build identity, not b12100; verify `llama-bench --version`, hash EXE and `ggml-vulkan.dll`. Never overwrite production Vulkan builds.

## Smoke 1024: one-shot Qcur-19 KV1024, no RDP

```powershell
New-Item -ItemType Directory -Force 'C:\llama-build\evox2-ppdiag-mask' | Out-Null

$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-fa-mask-tile-gate2-smoke-20261106.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant mask-snapshot-on -StopOnError
```

If the output prefix already exists from an earlier attempt, **do not delete it**. Instead change `GGML_VK_FA_MASK_DIAG_FILE` in your local copy of the plan to a unique path (e.g. add `-run2`). Do not use RDP during a mask snapshot. Expect 1024 PP status OK and one `status=queued`, one `status=wrote` in `stderr.log`. Check both binary/JSON exist and inspect metadata (expect KV=1024, Qcur-19, N=1024, Br=16, Bc=64, typically 64×16 tiles for a single slice; check actual shape rather than assume).

## Render a heatmap and validate source categories

```powershell
python .\tools\evox2\benchmark\visualize_fa_mask_tiles.py render `
    --prefix 'C:\llama-build\evox2-ppdiag-mask\smoke-1024-qcur19' `
    --out    'C:\llama-build\evox2-ppdiag-mask\smoke-1024-qcur19.svg'
```

The renderer uses **Python standard library only**, checks expected binary byte length, row stride, KV/Bc, slices, code3=INVALID, exports SVG plus `-row-summary.csv`, `-column-summary.csv`, and `-summary.json`. The SVG is a **static image**. To inspect it, open the SVG in Chrome/Edge. For an exact full tile-map image compare, supply the same slice number in both captures.

## After smoke PASS: literature and code 64k

Do **not** start 64k in the first Gate 2 run. Later, after confirming the 1024 diagnostic, adapt the plan to `-c65536 -p61777` and `GGML_VK_FA_MASK_DIAG_KV=49152`, `QUERY=Qcur-19`, distinct unique output prefixes `literature-49152` and `code-49152`. Keep source/model/UBatch/Br/Bc exactly identical. The expected 64×768 tile grid (16×64 tile size) is **conditional on runtime geometry**.

```powershell
python .\tools\evox2\benchmark\visualize_fa_mask_tiles.py compare `
    --a 'C:\llama-build\evox2-ppdiag-mask\literature-49152' `
    --b 'C:\llama-build\evox2-ppdiag-mask\code-49152' `
    --out 'C:\llama-build\evox2-ppdiag-mask\literature-vs-code-49152.svg'
```

The comparison validates all shape fields **and query identity** before creating a difference plot. It produces three matched-axis SVG maps (`-A.svg`, `-B.svg`, difference), row/column summary CSVs, and `-comparison.json` with changed tile counts and skips lost/gained A→B. Neither CSV nor SVG replaces the original packed binary/metadata.

## Evidence to upload

The benchmark result ZIP (stderr+conditions+ADLX+monitor), captured `.bin` and `.json` from the distinct output prefix, plus optionally the rendered `.svg` and `-summary.json`. The generated binary is intentionally outside the benchmark ZIP; **include it separately** so the 2-bit image can be independently decoded.

Stop on Vulkan DeviceLost/TDR 0x141/OOM, missing/invalid target capture, differing shape, any invalid 2-bit code, or sustained Windows memory pressure. The implementation remains on the investigation branch until the GPU gates pass.
