# r6 Vulkan QSA Indexer score/top-k — Windows runbook (2026-11-06)

**Status: source committed; native build, smoke and 64k GPU captures are NOT YET VERIFIED.** Do not proceed to 64k until all smoke checks pass. Must use the updated diagnostic Vulkan executable, not b12117 production or an old cached binary.

## Change inventory

- `src/models/qwen4exp.cpp`: opt-in explicit tensor names for score/topk at actual QSA layer/KV/first Query/physical N, without changing tensor values or top-k operator.
- `src/llama-memory-hybrid-idx.cpp`: host pool map `-pool-map.csv` and metadata `-pool-map.json`, with sequence-ordered **logical positions** and actual KV cache cell IDs.
- `ggml/src/ggml-vulkan/ggml-vulkan.cpp`, `ggml-vulkan-types.h`: bounded existing-output GPU copies of F32 Lightning Indexer score and unordered I32 TOP_K, 64 Query rows only, after kernel; write after the backend's ordinary synchronization.
- `tools/evox2/benchmark/analyze_indexer_diag.py`: validate exact shapes, pool->logical Key map, ranks/ties/cutoff and optional F16 raw mask crosschecks.
- `tools/evox2/tests/test_r6_indexer_diag.py`: synthetic score/tie/padding/crosscheck/overwrite tests and static source contracts.
- `tools/evox2/benchmark/configs/qwen38-r6-indexer-score-1024-smoke-20261106.psd1`, `qwen38-r6-indexer-score-64k-20261106.psd1`: isolated benchmark plans.

All diagnostic flags are default-OFF. Never benchmark timing with this capture ON.

## Gate 1: local tests, compile and executable identity (no 64k yet)

PowerShell on EVO-X2:

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git status --short
git pull --ff-only

python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_indexer_diag.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-ppdiag-rgp `
    -VulkanSdk 'C:\VulkanSDK\1.4.357.0' `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4 -BuildOnly
```

Use the previously successful pinned CMake executable/flags if the local build requires them; the invocation above follows the earlier diagnostic build convention. Check that `R6PpFaRgpVulkan` in local benchmark config points to the **newly rebuilt** binary and that `llama-bench.exe --version` identifies the updated local commit. Stop on compiler/test errors; report the first failure and do not start any 64k job.

## Gate 2: one 1024-token smoke

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-indexer-score-1024-smoke-20261106.psd1'
$dir = 'C:\llama-build\evox2-ppdiag-indexer'
$prefix = "$dir\idx-smoke-1024-il19"

New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($suffix in @('-pool-map.csv','-pool-map.json','-score.f32','-topk.i32','-meta.json')) {
    if (Test-Path -LiteralPath "$prefix$suffix") {
        throw "Prior capture exists; choose a unique prefix in the plan: $prefix$suffix"
    }
}
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant idx-smoke-1024 -StopOnError
python .\tools\evox2\benchmark\analyze_indexer_diag.py `
    --prefix $prefix `
    --out "$dir\analysis-smoke-1024"
```

**Require all** before continuing:
- process `Status=OK`, `ExitCode=0`; no new GPU TDR/0x141, reset, OOM, sustained paging;
- host stderr `evox2_indexer_pool_map_v1 status=wrote`;
- GPU stderr `evox2_indexer_diag_v1 status=queued kind=score`, `... kind=topk`, **and `status=wrote`**; reject `not_captured`, `rejected`, `exists`;
- `-pool-map.json`, `-pool-map.csv`, `-score.f32`, `-topk.i32`, `-meta.json` exist and decoder exits successfully;
- `kv=1024`, `layer=19`, `q_global_first=0`, `q_local_start=512`, `q_count=64`, `n_tokens=1024`; actual `n_pool/n_top_pool/kpool` from output JSON, not hardcoded;
- `-score.f32` length exactly `64*n_pool*4` bytes, `-topk.i32` exactly `64*n_top_pool*4`. Underfilled early KV score sets have `cutoff = null` legitimately.

```powershell
$meta = Get-Content "$prefix-meta.json" -Raw | ConvertFrom-Json
$hostMap = Get-Content "$prefix-pool-map.json" -Raw | ConvertFrom-Json
if ($meta.kv -ne 1024 -or $meta.layer -ne 19 -or
    $meta.q_global_first -ne 0 -or $meta.q_local_start -ne 512 -or
    $meta.q_count -ne 64 -or $meta.n_pool -ne $hostMap.n_pool) {
    throw 'Unexpected smoke snapshot identity'
}
$sizeScore = (Get-Item "$prefix-score.f32").Length
$sizeTop = (Get-Item "$prefix-topk.i32").Length
if ($sizeScore -ne 64*$meta.n_pool*4 -or
    $sizeTop -ne 64*$meta.n_top_pool*4) {
    throw 'Unexpected smoke snapshot size'
}
"Smoke metadata and lengths PASS"
```

Do not delete failed files; for a retry change `GGML_VK_INDEXER_DIAG_FILE` to a new prefix in a copied plan. Keep all earlier mask and F16 snapshots intact.

## Gate 3: 64k code only, after Gate 2 PASS

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-indexer-score-64k-20261106.psd1'
$prefix = "$dir\idx-code-kv49152-il19"

foreach ($suffix in @('-pool-map.csv','-pool-map.json','-score.f32','-topk.i32','-meta.json')) {
    if (Test-Path -LiteralPath "$prefix$suffix") { throw "Existing capture: $prefix$suffix" }
}
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant idx-code -StopOnError

$maskDir = 'C:\llama-build\evox2-ppdiag-mask'
python .\tools\evox2\benchmark\analyze_indexer_diag.py `
    --prefix $prefix `
    --out "$dir\analysis-code-kv49152" `
    --raw-prefix "$maskDir\raw-code-49152-q32-k27" `
    --raw-prefix "$maskDir\raw-code-49152-q32-k40" `
    --raw-prefix "$maskDir\raw-code-49152-q32-k92" `
    --raw-prefix "$maskDir\raw-code-49152-q32-k469"
```

All four previous F16 raw-window files and their metadata must be present for this 4-way crosscheck. If one is missing, omit **that specific** `--raw-prefix`; still run the remaining matches, or stop to retrieve earlier evidence. Never silently report all 4 as PASS when they are absent.

**64k expected identity:** KV49152, layer19, UBatch start48128, n_tokens1024, q local512–575 / global48640–48703, kpool metadata-derived (F16 shows 4-Key groups), n_pool runtime-derived. For kpool4 expect n_pool12352 and score size `3162112` bytes only as a *sanity estimate*, not an assertion.

**Per-Key F16 comparison gate:** reconstructed 0/-inf original masks must match for all existing windows (16,384 values each). If mismatch, investigate pool layout/visibility/tail/Query alignment before ranking conclusions.

## Gate 4: 64k literature, ONLY after Gate 3 PASS

```powershell
$prefix = "$dir\idx-literature-kv49152-il19"
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant idx-literature -StopOnError

$maskDir = 'C:\llama-build\evox2-ppdiag-mask'
python .\tools\evox2\benchmark\analyze_indexer_diag.py `
    --prefix $prefix `
    --out "$dir\analysis-literature-kv49152" `
    --raw-prefix "$maskDir\raw-literature-49152-q32-k27" `
    --raw-prefix "$maskDir\raw-literature-49152-q32-k92" `
    --raw-prefix "$maskDir\raw-literature-49152-q32-k469"
```

Use a fresh unique prefix; the same no-overwrite check applies to literature. If the old F16 filenames differ, consult their raw `-raw.json` files first. Repeat full key/pool/rank/selection and F16 checks. Full raw ZIPs stay outside Git; only compact aggregates/plots and SHA-256 should be committed to `evox2-llm-experiments`.

## Interpretation and stop conditions

- Unordered `topk.i32` is **not** a rank list; rank and cutoff are computed from original F32 scores. Underfilled top-k may contain invisible padding; such entries are not valid selected Keys.
- Pool indices are cache layout IDs, not absolute Key positions; use `pool-map.csv` to get position. Incomplete tail members are **not** top-k pools.
- A selected pool's score/rank is **not** a final Attention weight, and score capture does not prove causal PP optimization opportunities.
- Abort and preserve evidence on any compile failure, failed unit test, missing status, inconsistent output shape, bad pool map, F16 reconstruction error, TDR/DeviceLost/0x141, OOM, or wrong build. Do not run code+literature back-to-back before each gate passes.
