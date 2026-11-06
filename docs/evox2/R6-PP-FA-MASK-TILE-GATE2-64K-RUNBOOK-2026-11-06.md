# Gate 2: 64k literature/code mask snapshot runbook (2026-11-06)

**Plan prepared; long 64k GPU runs not executed yet.** This follows a passed 1024-token Vulkan mask snapshot on b12108. Separate benchmark jobs and variants ensure only one source is run at a time and that output prefixes do not collide.

## Fixed conditions

- r6 investigation branch, Vulkan diagnostic BuildKey R6PpFaRgpVulkan (reuse verified b12108 or a subsequently validated binary), Unsloth IQ3_XXS PLE16, UMA96GB, Performance P-MODE.
- Two text sources, each using its own **head 61,777 tokens**: wagahaiwa_nekodearu_utf8.txt and llamacpp-inference-code.txt.
- Context65536, physical UBatch1024, batch2048, threads4, f16 KV, no generation, no warmup, QSA UNION OFF, MTP OFF, and no RGP/host trace.
- FA mask metadata one-shot target **KV49152, query Qcur-19, N1024**. The expected 64-by-768 tile grid is conditional on actually selected Br16/Bc64 and slice count.
- Source SHA256 of the literature text: 8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143.
- Source SHA256 of llama.cpp code text: 249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345.

## Fetch, test, preflight (no GPU execution)

~~~powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git pull --ff-only
python -m unittest discover -s .\tools\evox2\tests -p 'test_r6_fa_mask_64k_plan.py' -v
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-fa-mask-tile-gate2-64k-20261106.psd1'
$maskDir = 'C:\llama-build\evox2-ppdiag-mask'
New-Item -ItemType Directory -Force -Path $maskDir | Out-Null
foreach ($stem in @('literature-49152', 'code-49152')) {
    foreach ($ext in @('.bin', '.json')) {
        $dest = Join-Path $maskDir ($stem + $ext)
        if (Test-Path -LiteralPath $dest) {
            throw "Existing output: $dest. Change this source's output prefix in the local plan before rerunning."
        }
    }
}
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
~~~

PlanOnly must list exactly two selected cases: literature with variant mask-literature-64k and code with variant mask-code-64k, with separate output prefixes. The output folder may be reused from the successful 1024 smoke; do not delete previous evidence.

## Run 1: literature only

~~~powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant mask-literature-64k -StopOnError
~~~

**Stop and inspect before Run 2.** The native benchmark must be Status OK / exit 0 and a metadata snapshot must appear in stderr as status=queued followed by status=wrote with KV49152. The files literature-49152.bin and literature-49152.json must both exist. Review GPU/Windows RAM/ADLX/P-MODE; fail immediately on OOM, TDR 0x141, lost device, heavy sustained paging or mismatched tensor metadata. A transient separate backend context may emit status=not_captured; check the successful wrote event and files, not only the first status line.

## Run 2: code only

~~~powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant mask-code-64k -StopOnError
~~~

Check the corresponding code-49152.bin and code-49152.json, same target query, KV, N, Br/Bc, rows, cols and slices as literature. Do not attempt to overwrite any capture; if rerunning, edit GGML_VK_FA_MASK_DIAG_FILE for that variant to a new unique prefix.

## SVG render and exact difference

~~~powershell
$vis = '.\tools\evox2\benchmark\visualize_fa_mask_tiles.py'
python $vis render --prefix "$maskDir\literature-49152" --out "$maskDir\literature-49152.svg"
python $vis render --prefix "$maskDir\code-49152" --out "$maskDir\code-49152.svg"
python $vis compare --a "$maskDir\literature-49152" --b "$maskDir\code-49152" --out "$maskDir\literature-vs-code-49152.svg"
Get-ChildItem "$maskDir\*49152*" | Select-Object Name,Length
Get-FileHash "$maskDir\literature-49152.bin" -Algorithm SHA256
Get-FileHash "$maskDir\code-49152.bin" -Algorithm SHA256
~~~

The standard-library decoder generates two individual SVGs, an exact-coordinate difference SVG, row/column skip histograms (CSV), count/geometry summary JSON, and a comparison JSON. It rejects incompatible geometry and invalid/reserved code 3. This is mask-tile classification data, **not raw attention masks or the measured proportion of FA GPU runtime saved**. No direct PP performance claim from these diagnostic runs.

## Evidence for investigation

Upload the two benchmark run ZIPs plus both pairs of .bin/.json outputs. Mask snapshots live outside the benchmark ZIP. The difference SVG and comparison JSON are useful optional additions. Save hashes and keep the unchanged clean-performance baseline separate from snapshot-on GPU measurements.
