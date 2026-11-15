# R6 S8 G8-6 runtime usability / decision freeze runbook - 2026-10-28

## Status, scope and order

**Status: EXECUTED / G8-6 RUNTIME PASS (2026-10-28 JST).** The commands below are retained for reproducibility; the measured closure is appended at the end. G8-5 [Vulkan IQ3 256k selective stability](R6-S8-GATE5-SELECTIVE-STABILITY-RUNBOOK-2026-10-28.md#windows-measured-result-and-g8-5-closure---2026-10-28-jst) passed 1/1 on the fixed b11908 executable. **Do not repeat 256k for G8-6.** This gate checked practical `llama-server` behavior, independent executable/backend identity and tokenizer parity and froze the narrow S8 flag decision. No new optimization or source rebuild was performed.

Run on **Windows Evo-X2 / 96GB UMA**, PowerShell, branch `r6/combined-20261028`, from `C:\llama-build\llama.cpp-evox2-windows-r6`. Run **one server at a time**; no other inference/benchmark process. Keep P-MODE **Performance**, watch ADLX/VRAM/free RAM and Defender scan activity. No background daemon, WAN listener, UI tool execution, unfiltered ROCm backend tests, or global flag changes. The b11908 binaries remain the measured subject even if documentation commits have advanced Git HEAD.

| Order | Gate case | Backend / model | Context | MTP / performance switches | Requests |
| --- | --- | --- | ---: | --- | --- |
| 0 | Build+tokenizer preflight | **separate** `CombinedVulkan` and `CombinedROCm` / Unsloth IQ3 PLE16 | vocab-only | No inference | version, manifest, hashes, devices, EN/JA token IDs |
| 1 | `vk-stock` | Vulkan / Unsloth IQ3 PLE16 | 4096 | **MTP OFF, five switches OFF** | one Jinja chat; `/health` |
| 2 | `vk-mtp` | Vulkan / Unsloth IQ3 PLE16 + Unsloth MTP Draft | 65536 | **MTP ON DraftMax=2, all five ON** | two-turn Jinja chat, then **one** existing real 64k document |
| 3 | `rocm-stock` | ROCm / Unsloth IQ3 PLE16 | 4096 | **MTP OFF, S4/S5/S6/S7 OFF** | one short Jinja chat; `/health` |
| 4 | Decision freeze | Evidence only | — | No further runs | PASS/DEFER/DISABLE, rollback, S9 handoff |

The single 64k case is the *existing* `Inputs.'64k'` fixture, **61,789 input tokens** and file SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`. This is a **usability** check, not ABBA speed evidence. G8-3's 64/128k real-input benchmark and G8-4's 14/14 output checks remain the speed/continuation evidence. G8-4 cannot establish numerical Draft K/V equality: **S7-A Stage-B and S7-B flatten remain DEFER for a generally supported preset, even if this API smoke passes**.

## 0. Windows preflight: exact build and tokenizer

First, keep any existing local edits; do not reset or overwrite working binaries. `local.psd1` is ignored and holds machine-local paths. When the tree is clean, a fast-forward docs update is allowed; a new docs commit is **not** a reason to rebuild b11908.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
git status --short --branch
if (@(git status --porcelain).Count -ne 0) { throw 'Worktree dirty; inspect, do not reset.' }
git pull --ff-only origin r6/combined-20261028
if ($LASTEXITCODE -ne 0) { throw 'Pull failed; inspect before proceeding.' }

$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$vkBin   = [string]$local.Builds.CombinedVulkan.BinDir
$rocmBin = [string]$local.Builds.CombinedROCm.BinDir
$main    = [string]$local.Models.UnslothPle16.Path
$draft   = [string]$local.Models.UnslothMtp.Path
$real64  = [string]$local.Inputs.'64k'
if ($vkBin -eq $rocmBin) { throw 'Vulkan and ROCm must have separate bin directories.' }
foreach ($p in @($main, $draft, $real64)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing model/input: $p" }
}
if ((Get-FileHash -LiteralPath $real64 -Algorithm SHA256).Hash.ToLowerInvariant() -ne `
    '2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751') {
    throw '64k input mismatch: stop and resolve the existing real fixture.'
}

$logDir = Join-Path (Get-Location) ('evox2-logs\g8-6-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
foreach ($entry in @(@{ Name='vulkan'; Bin=$vkBin }, @{ Name='rocm'; Bin=$rocmBin })) {
    $b = $entry.Bin
    foreach ($name in @('llama-cli.exe', 'llama-server.exe', 'llama-bench.exe', 'llama-tokenize.exe', 'evox2-build.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $b $name) -PathType Leaf)) {
            throw "$($entry.Name): missing $name; do not swap in another backend's executable."
        }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $b 'evox2-build.json') -Raw | ConvertFrom-Json
    if ($manifest.BuildIdentity.Status -ne 'Verified') { throw "$($entry.Name): BuildIdentity not Verified" }
    if ($entry.Name -eq 'vulkan' -and [string]$manifest.Backend -notmatch 'Vulkan') {
        throw 'CombinedVulkan manifest does not describe a Vulkan build.'
    }
    if ($entry.Name -eq 'rocm' -and [string]$manifest.Backend -notmatch 'ROCm') {
        throw 'CombinedROCm manifest does not describe a ROCm build.'
    }
    $cliSha = (Get-FileHash -LiteralPath (Join-Path $b 'llama-cli.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($entry.Name -eq 'vulkan' -and $cliSha -ne `
        'bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a') {
        throw 'Wrong CombinedVulkan build: expected fixed b11908/G8-5 CLI SHA256.'
    }
    Write-Host "$($entry.Name): manifest=$($manifest.Backend), source=$($manifest.ExecutableIdentity.Commit)"
    & (Join-Path $b 'llama-server.exe') --version
    if ($LASTEXITCODE -ne 0) { throw "$($entry.Name): server version failed" }
    & (Join-Path $b 'llama-cli.exe') --list-devices
    if ($LASTEXITCODE -ne 0) { throw "$($entry.Name): device enumeration failed" }
    Get-ChildItem -LiteralPath $b -File | Where-Object {
        $_.Extension -in @('.exe', '.dll') -or $_.Name -eq 'evox2-build.json'
    } | Get-FileHash -Algorithm SHA256 |
        Select-Object Path, Hash | Export-Csv -NoTypeInformation -Encoding UTF8 `
            (Join-Path $logDir ($entry.Name + '-file-hashes.csv'))
    Copy-Item -LiteralPath (Join-Path $b 'evox2-build.json') `
        -Destination (Join-Path $logDir ($entry.Name + '-evox2-build.json'))
}
```

Inspect both manifests: **Vulkan b11908 / Clang 20.1.8** and **ROCm b11908 / TheRock 10.0, correct `gfx1151` runtime DLL closure**. The Vulkan `llama-cli.exe` must retain the G8-5 SHA256 **`bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`**; its runtime digest was `ceb31061f39c4bc5dd1181c3f5eaa888623a5b0212f37b2e3d20d863e61e2bf3`. Check manifest `Artifacts` entries for the server/tokenizer (rebuilding just those from another source commit is not a valid substitute). Both binaries must report the expected backend devices. **Stop** if either identity/backend/runtime is ambiguous.

Tokenize the same *short* English and Japanese strings with both backends. `llama-tokenize` loads vocabulary only, so this does not launch a long context inference job. Compare the **IDs and counts**, ignoring backend initialization banners; do not compare raw stderr lines.

```powershell
$samples = @('The prior study differs from the present work.', '先行研究と本研究の関係を説明してください。')
foreach ($i in 0..($samples.Count - 1)) {
    $outputs = @()
    foreach ($entry in @(@{ Name='vulkan'; Bin=$vkBin }, @{ Name='rocm'; Bin=$rocmBin })) {
        $exe = Join-Path $entry.Bin 'llama-tokenize.exe'
        $raw = & $exe -m $main -p $samples[$i] --no-escape --ids --show-count 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Tokenizer failed: $($entry.Name) sample $i" }
        $tokenData = @($raw | ForEach-Object { "$_" } |
            Where-Object { $_ -match '^\[[0-9,\s]+\]$|^Total number of tokens:\s*\d+' })
        if ($tokenData.Count -ne 2) { throw "Missing tokenizer IDs/count: $($entry.Name) sample $i" }
        $tokenData | Set-Content -Encoding UTF8 (Join-Path $logDir "tokenize-$i-$($entry.Name).txt")
        $outputs += ,($tokenData -join "`n")
    }
    if ($outputs[0] -cne $outputs[1]) { throw "Vulkan/ROCm tokenizer disagreement: sample $i" }
}
Write-Host 'Vulkan/ROCm tokenizer IDs and counts: identical for EN/JA samples.'
```

The tokenizer samples are **not** a 64k chat-template token count. The full real-document request has Jinja/system/user framing, so compare actual server `usage.prompt_tokens` against the context and check for truncation.

## 1. Server terminal A: bounded Vulkan MTP-OFF (normal/stock path)

Use the *same* Vulkan build folder as G8-5. In this terminal, configure flags for **this process only**, clear inherited diagnostic/optimization overrides, then start the server. In a second PowerShell terminal run the client commands from §3. **Ctrl+C server A and wait until the process exits before starting the next case.**

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$vkBin = [string]$local.Builds.CombinedVulkan.BinDir
$main  = [string]$local.Models.UnslothPle16.Path

# Process-local explicit OFF. Do not set machine/user-level environment variables.
$env:GGML_VK_QSA_UNION = '0'
Remove-Item Env:GGML_VK_QSA_UNION_MIN_KV -ErrorAction SilentlyContinue
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '0'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
foreach ($n in @('GGML_VK_QSA_UNION_STATS','LLAMA_MTP_DIAG','LLAMA_QSA_NOOP_TRACE',
    'LLAMA_MTP_QSA_MIN_KV','LLAMA_QSA_NO_POOLED_CACHE','GGML_VK_FORCE_MMVQ',
    'GGML_VK_DISABLE_MMVQ','GGML_VK_FA_SPARSE_DISABLE','LLAMA_GRAPH_REUSE_DISABLE',
    'GGML_VK_GET_ROWS_128X4','QWEN4EXP_QSA_GATHER','GGML_VK_DISABLE_GRAPH_OPTIMIZE',
    'GGML_VK_FUSE_UNARY_MUL')) {
    Remove-Item "Env:$n" -ErrorAction SilentlyContinue
}

& (Join-Path $vkBin 'llama-server.exe') -m $main --alias g8-6 `
    --host 127.0.0.1 --port 18080 --parallel 1 `
    -c 4096 -ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 1024 `
    -fa auto -ctk f16 -ctv f16 -fit off --cache-ram 0 `
    --jinja --reasoning off --temp 0 --top-p 0.8 `
    --ctx-checkpoints 0t 2>&1 | Tee-Object '.\evox2-logs\g8-6-vk-stock-server.log'
```

**Expected:** successful load, Vulkan main **49/49 GPU layers**, local `/health` ready, Jinja response in Japanese/English, no Draft model initialization, no speculative statistics or S8 opt-in path. Source presence alone is not opt-in. This `vk-stock` case is a short functionality check, not a speed baseline or a promise of identical text hashes.

## 2. Server terminal A: Vulkan MTP-ON all-ON (opt-in reference)

After shutting down `vk-stock`, run the same short chat *and* one real 64k document on the verified Vulkan build. Keep the all-ON profile explicitly confined to this process; the supported-profile document treats S7-A/B as **experimental / parity-DEFER** pending a numerical state test.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$vkBin = [string]$local.Builds.CombinedVulkan.BinDir
$main  = [string]$local.Models.UnslothPle16.Path
$draft = [string]$local.Models.UnslothMtp.Path

$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_MIN_KV = '32768'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '1'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '1'
foreach ($n in @('GGML_VK_QSA_UNION_STATS','LLAMA_MTP_DIAG','LLAMA_QSA_NOOP_TRACE',
    'LLAMA_MTP_QSA_MIN_KV','LLAMA_QSA_NO_POOLED_CACHE','GGML_VK_FORCE_MMVQ',
    'GGML_VK_DISABLE_MMVQ','GGML_VK_FA_SPARSE_DISABLE','LLAMA_GRAPH_REUSE_DISABLE',
    'GGML_VK_GET_ROWS_128X4','QWEN4EXP_QSA_GATHER','GGML_VK_DISABLE_GRAPH_OPTIMIZE',
    'GGML_VK_FUSE_UNARY_MUL')) {
    Remove-Item "Env:$n" -ErrorAction SilentlyContinue
}

& (Join-Path $vkBin 'llama-server.exe') -m $main --alias g8-6 `
    --host 127.0.0.1 --port 18080 --parallel 1 `
    -c 65536 -ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 1024 `
    -fa auto -ctk f16 -ctv f16 -fit off --cache-ram 0 `
    --jinja --reasoning off --temp 0 --top-p 0.8 `
    --ctx-checkpoints 0t `
    -md $draft --spec-type draft-mtp --n-gpu-layers-draft 999 `
    --spec-draft-n-max 2 --spec-draft-p-min 0 `
    --cache-type-k-draft f16 --cache-type-v-draft f16 `
    2>&1 | Tee-Object '.\evox2-logs\g8-6-vk-mtp-server.log'
```

**Expected:** Vulkan main **49/49** and Draft **50/50** GPU placement, correct MTP Draft, no fallback or reset; Jinja works across two sequential API requests; after the real document, a `qsa-union active` line (if the enabled path is eligible) and meaningful MTP accepted/drafted statistics. Record if a diagnostic is absent instead of inventing evidence. With one slot and `-c 65536`, never launch concurrent requests or a 256k payload. If startup approaches unsafe RAM/VRAM pressure or the model/Draft backend is wrong, shut it down and classify DEFER.

## 3. Client terminal B: health, Jinja, multi-turn, one real input

Client requests go **only** to `127.0.0.1:18080`; the actual document body stays in memory and must **not** be written into the result ZIP. Set a unique `$logDir` in terminal B; use a **new log directory per session** or include the session label in the file names. Choose `$case = 'vk-stock'` for case 1 and `$case = 'vk-mtp'` for case 2. Wait for `/health` readiness manually; a failed request is a stop, not a signal to launch an automatic server-restart loop.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
$case = 'vk-stock'  # switch to 'vk-mtp' on the next server launch
$logDir = Join-Path (Get-Location) ('evox2-logs\g8-6-api-' + $case + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$uri = 'http://127.0.0.1:18080'
$health = Invoke-RestMethod -Uri "$uri/health" -Method Get
$health | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $logDir 'health.json')

function Invoke-G8Chat($Messages, [int]$MaxTokens) {
    $body = @{ model = 'g8-6'; messages = $Messages; temperature = 0.0
               top_p = 0.8; max_tokens = $MaxTokens; stream = $false } | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Uri "$uri/v1/chat/completions" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
}

$m1 = @(
    @{ role='system'; content='簡潔な日本語で答えてください。' },
    @{ role='user'; content='先行研究と本研究の違いを一文で説明してください。' }
)
$r1 = Invoke-G8Chat $m1 96
if (-not $r1.choices[0].message.content) { throw 'Empty Jinja chat response' }
$r1 | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $logDir 'turn1.json')

# Only on vk-mtp: a second API call contains the real prior assistant answer.
if ($case -eq 'vk-mtp') {
    $m2 = @($m1) + @(
        @{ role='assistant'; content=[string]$r1.choices[0].message.content },
        @{ role='user'; content='今の説明で、主語と目的語を取り違えない注意点を一文で述べてください。' }
    )
    $r2 = Invoke-G8Chat $m2 96
    if (-not $r2.choices[0].message.content) { throw 'Empty multi-turn response' }
    $r2 | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $logDir 'turn2.json')
}
```

For **`vk-mtp` only**, after confirming the short multi-turn completed, send the **one existing 64k real document**. Keep the request short around the full document (no extra document copies or long history); reserve `max_tokens=128`. Tokenization under Jinja adds framing overhead beyond 61,789 raw tokens. If actual `usage.prompt_tokens + usage.completion_tokens` reaches/exceeds 65536, or the server reports truncation/context shift, **do not call it a full-document PASS**.

```powershell
if ($case -ne 'vk-mtp') { throw 'Real 64k document is reserved for vk-mtp only.' }
$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$real64 = [string]$local.Inputs.'64k'
if ((Get-FileHash $real64 -Algorithm SHA256).Hash.ToLowerInvariant() -ne `
    '2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751') {
    throw 'Wrong 64k fixture.'
}
$document = Get-Content -LiteralPath $real64 -Raw -Encoding UTF8
$prompt = '次の全文資料に基づいて、先行研究と本研究の関係を3点で要約してください。資料外の情報を足さないでください。' + "`n`n" + $document
$docMessages = @(
    @{ role='system'; content='与えられた資料に限定し、主語・目的語を正確に区別してください。' },
    @{ role='user'; content=$prompt }
)
$docResponse = Invoke-G8Chat $docMessages 128
Remove-Variable document, prompt, docMessages -ErrorAction SilentlyContinue
if (-not $docResponse.choices[0].message.content) { throw 'Empty 64k response' }
$docResponse | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 (Join-Path $logDir 'real64-response.json')
$usage = $docResponse.usage
if ($null -eq $usage -or $null -eq $usage.prompt_tokens -or $null -eq $usage.completion_tokens) {
    throw 'Missing usage: preserve server logs, mark input-length verification DEFER.'
}
if (($usage.prompt_tokens + $usage.completion_tokens) -ge 65536) {
    throw 'Context boundary reached; do not claim untruncated full-document PASS.'
}
Write-Host "64k API: prompt=$($usage.prompt_tokens), completion=$($usage.completion_tokens)"
```

The server may report `truncated`/context-shift status in its logs/slot telemetry, depending on the endpoint. **Inspect the actual logs**; token arithmetic alone does not prove no internal trimming. The response is a *coherence/usefulness observation*, not a quantitative answer-accuracy score. Record prompt/evaluated counts, PP/TG/total where available, accepted/generated, GPU and power evidence without comparing numerically to CLI timing (Jinja and API framing are different).

## 4. ROCm MTP-OFF frontend/backend separation smoke

Shut down Vulkan server first. Use **only** the `CombinedROCm` executable + its **own** TheRock runtime DLL/data directory. Keep **all five flags OFF** and omit the Draft model. In ROCm's verified VS2022 / TheRock environment, run one 4k Jinja request (set `$case = 'rocm-stock'` in the client from §3, run only turn1). Do not enable ROCm Stage-B/flatten, Vulkan QSA union, or a broad `FLASH_ATTN_EXT` suite.

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'
$local = Import-PowerShellDataFile '.\tools\evox2\benchmark\configs\local.psd1'
$rocmBin = [string]$local.Builds.CombinedROCm.BinDir
$main = [string]$local.Models.UnslothPle16.Path

$env:GGML_VK_QSA_UNION = '0'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '0'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '0'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
Remove-Item Env:GGML_VK_QSA_UNION_MIN_KV -ErrorAction SilentlyContinue
foreach ($n in @('GGML_VK_QSA_UNION_STATS','LLAMA_MTP_DIAG','LLAMA_QSA_NOOP_TRACE',
    'LLAMA_MTP_QSA_MIN_KV','LLAMA_QSA_NO_POOLED_CACHE','GGML_VK_FORCE_MMVQ',
    'GGML_VK_DISABLE_MMVQ','GGML_VK_FA_SPARSE_DISABLE','LLAMA_GRAPH_REUSE_DISABLE',
    'GGML_VK_GET_ROWS_128X4','QWEN4EXP_QSA_GATHER','GGML_VK_DISABLE_GRAPH_OPTIMIZE',
    'GGML_VK_FUSE_UNARY_MUL')) {
    Remove-Item "Env:$n" -ErrorAction SilentlyContinue
}

& (Join-Path $rocmBin 'llama-server.exe') -m $main --alias g8-6 `
    --host 127.0.0.1 --port 18080 --parallel 1 `
    -c 4096 -ngl 999 -ncmoe 0 -t 4 -tb 4 -b 2048 -ub 1024 `
    -fa auto -ctk f16 -ctv f16 -fit off --cache-ram 0 `
    --jinja --reasoning off --temp 0 --top-p 0.8 `
    --ctx-checkpoints 0t 2>&1 | Tee-Object '.\evox2-logs\g8-6-rocm-stock-server.log'
```

Confirm HIP/ROCm backend (not Vulkan or CPU fallback), complete main GPU placement, correct staged runtime and no MTP initialization. A different response text from Vulkan is **not** automatically a regression; ROCm has known `temp=0` nondeterminism. If the ROCm server fails or cannot be validated, **DEFER ROCm server usability**, do not jeopardize the already measured Vulkan candidate.

## 5. Stop rules, evidence package and decision freeze

- **Immediate stop / relevant case DEFER:** wrong executable/build/runtime SHA, unexpected backend or CPU fallback, OOM/driver reset/hang, broken Jinja/template, empty/invalid API response, missing tokenizer parity, context truncation, untrustworthy P-MODE/ADLX or heavy concurrent scan. An unequivocal reproducible functional defect is **FAIL** for that affected profile. Do not loop/retry to manufacture a PASS.
- **Record:** per-case build manifest, EXE/DLL hashes, exact environment flag map and actual server arguments, `--version` and `--list-devices`, sample tokenizer IDs/counts, `/health`, turn1/turn2 JSON, real64 response JSON and usage, server stdout/stderr, GPU/ADLX/P-MODE trend, real fixture SHA and measured token counts. Preserve raw ZIP SHA256 after packing; keep actual real document, GGUFs, local paths/config and large binary artifacts **out of Git**.
- **PASS scope:** `vk-stock` short normal MTP-OFF path, `vk-mtp` Jinja multi-turn + full real64 document with no fallback/truncation, `rocm-stock` short backend-separated MTP-OFF path, and Vulkan/ROCm tokenizer exact parity. A server smoke does **not** prove Stage-B/flatten numerical Draft K/V parity or ROCm S7 speed.
- **Freeze:** update [supported flag profiles](R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md) with `PASS opt-in`, `DEFER`, `DISABLE` or `upstream-covered` by backend+model. Log G8-6 actual statuses in `R6-S8-COMBINED-RESULTS` (create only after reviewing the returned evidence) and link from `ROADMAP.md`/`PATCHES.md`. In particular, **do not** promote all-ON as a global default; any S7-A/B production-oriented preset remains DEFER without independent Draft K/V numerical parity.
- **Rollback:** stop the server, set all five flags to `0` (or unset), remove Draft args for the stock path, restart the **same verified** backend build; if still defective, use saved b11903 Stage-B, b11906 flatten, earlier S4/S5/S6, S0 upstream, or b10919 Gemma4 binaries **in their original folders**. Never overwrite them or silently rebase the source; retain manifest hashes. A rollback to flags OFF preserves required S1-S3 compatibility patches.

After closing all servers, pack the G8-6 evidence directories *only* (do not zip the entire source worktree or model folders). The examples above write under `evox2-logs`; adjust the folder selection if you chose a custom root:

```powershell
$entries = @(Get-ChildItem '.\evox2-logs' -Directory -Filter 'g8-6-*')
if ($entries.Count -eq 0) { throw 'No G8-6 evidence directories found.' }
$serverLogs = @('g8-6-vk-stock-server.log', 'g8-6-vk-mtp-server.log', 'g8-6-rocm-stock-server.log') |
    ForEach-Object { Join-Path (Get-Location) ('evox2-logs\' + $_) }
foreach ($p in $serverLogs) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing server log: $p" } }
$archive = Join-Path (Get-Location) ('evox2-logs\g8-6-review-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
$items = @($entries.FullName) + $serverLogs
Compress-Archive -LiteralPath $items -DestinationPath $archive
Get-FileHash -LiteralPath $archive -Algorithm SHA256
```

The archive includes all three `g8-6-*-server.log` files and the evidence folders; verify that the two tokenizer ID comparisons are present. **Before sharing, inspect for local private paths and sensitive text** and omit or redact sensitive source passages. Send the small ZIP for review. **Only after the evidence is reviewed and the decision table frozen should S8 be designated a candidate for S9** (Unsloth IQ4, huihui IQ4XS and separately Gemma4 against b10919).

## G8-6 Windows measured closure - 2026-10-28 JST

**Verdict: PASS for the bounded G8-6 runtime/usability scope, with explicit server/backend and S7 caveats. No repeat requested.** User-supplied archive `g8-6-review-20261028-210806.zip`, **SHA256 `6d143104949649cf89b3ffa6fa11b4a848eab61a0d2aaf9829871712b0395f38`**, contains 19 entries: two manifests, separate EXE/DLL SHA inventories, EN/JA tokenizer IDs/counts, API JSONs and all three server logs. The ZIP stays outside Git. Logs are Windows PowerShell `Tee-Object` UTF-16LE; decode before searching text. A startup `NativeCommandError` line is PowerShell's representation of native stderr; requests subsequently succeeded and the servers shut down normally.

### Provenance and tokenizer

- Both manifests `BuildIdentity.Status=Verified`, clean pinned source `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`, b11908. Vulkan: Clang 20.1.8, `build-vulkan-r6-combined-fixed`; `llama-cli.exe` SHA256 `bca8986ed712284d3305febed1fdb0f3e2b2b1a34f9c72f90ef4e74a6b5f9a4a`, `llama-server.exe` `89b575891366cd5d697686c84ef78ff09127088a6330d86b64da73f6b73d3615`, `ggml-vulkan.dll` `c5c00dab8ec29b2becccd33cccee64b3221ce243a7ff7909ce8d3f73e9078d54`.
- ROCm: TheRock SDK/runtime 10.0.0, AMD Clang 23.0.0, MSVC 14.44, `gfx1151`, `TheRockUnified`, `DllAndRuntimeDataHashesVerified`. `llama-cli.exe` SHA256 `1bbd4a5102b6181d8de92faf2d42e49f96ba2ad4b04b7c7f9e6aafc168d322b1`, `llama-server.exe` `9187ebec46825efc88a98644581ee6b856f30472b6a99671f95b237459ec9c82`, `ggml-hip.dll` `cb0c107b52d8a20a86a5b57b7db7b1cf64047be48302811cf593d3506e9a40ce`.
- `llama-tokenize.exe`: Vulkan SHA256 `a85e803bf30c1385ddb35ed24dda8f4a732608050c59c2cad24a2d876cc9cea8`; ROCm SHA256 `0333a9c90825729866241510b9a2970f6bdbe733331a83c63eeb0c6953c56581`. EN: **9/9 same token IDs**; JA: **9/9 same token IDs** (exact arrays retained in ZIP). This verifies tokenizer equivalence, not long-document semantic equivalence.

### Three server cases and one real document

| Case | API and server evidence | Verdict |
| --- | --- | --- |
| Vulkan MTP OFF `vk-stock` | `/health status=ok`; 37 prompt + 39 generated, `finish_reason=stop`, `truncated=0`; main model loaded with no Draft | **PASS** |
| Vulkan MTP ON `vk-mtp`, turn 1 | `/health status=ok`, Jinja response, 37+39 tokens, `truncated=0`; Draft **20 accepted / 38 drafted** | **PASS** |
| Vulkan MTP ON `vk-mtp`, turn 2 | Real assistant turn retained: prompt usage 109, completion 83, `cached_tokens=76`, `finish_reason=stop`, `truncated=0`; Draft **49/66** | **PASS** short multi-turn |
| Vulkan MTP ON real64 | Known `Inputs.'64k'` fixture SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`; Jinja prompt **61,842** + completion **128** = **61,970** total under `-c 65536`; `truncated=0`, `qsa-union active`; **76 accepted / 100 drafted** | **PASS long-input processing**, not quality/repeated speed |
| ROCm MTP OFF `rocm-stock` | `/health status=ok`; 37+39, `finish_reason=stop`, `truncated=0`; separate ROCm b11908 server initialized and exited normally | **PASS** |

For real64, server log reports **PP 358.29 tok/s** (172.601 s / 61,842), **TG 33.55 tok/s** (3.785 s / 128) and **total 176.387 s**. These are single API request timings, **not** comparable causal speedup to CLI G8-3/5. The response ended with `finish_reason=length` because of the intentionally fixed 128-token generation cap, **not context truncation**. It began a coherent document-grounded summary but said “6 items” despite the prompt's “3 points” request and did not finish its second item. Record as **semantic/format compliance DEFER to S9**, not a functional G8-6 failure. The Vulkan warning about unsupported *fused top-k mask* denotes a disabled fused optimization, not proof of full CPU-model fallback; server logs did not independently enumerate all 49/50 offloaded layers (CLI G8-5 placement evidence remains separate).

**Archive naming correction:** the API pair `g8-6-api-vk-stock-20261028-210740/health.json` and `turn1.json` is actually the **ROCm MTP-OFF** request, despite the inherited `vk-stock` directory name. The user explicitly confirmed this mapping. The earlier `g8-6-api-vk-stock-20261028-205841` pair is Vulkan MTP OFF.

**User's additional confirmations (2026-10-28 JST):** (1) the `21:07` result belongs to ROCm MTP OFF; (2) **P-MODE Performance throughout, no OOM, GPU reset or heavy Defender interference**; (3) all commands and five-flag settings were used **unchanged** from this runbook. ADLX/P-MODE per-sample CSVs and a separate server layer-offload summary were not in this 19-file ZIP, so do not claim independent telemetry averages or server 49/50 placement measurements. These bounded gaps do not require repeating the passed usability cases.

**Decision freeze:** Vulkan IQ3 PLE16 S4 union / S5 DENSE / S6 NOOP are **PASS opt-in** in their tested eligibility scope, with source defaults OFF. Vulkan S7-A Stage-B and S7-B flatten remain **DEFER for a supported preset** (lab all-ON functional PASS, numerical Draft K/V parity unproven). ROCm IQ3 DENSE/NOOP retain **PASS opt-in for the measured CLI MTP-ON scope**; ROCm MTP-OFF server PASS, but ROCm MTP-ON *server* stays DEFER. Vulkan FP4 server and S9 IQ4/huihui/Gemma4 model-specific support remain DEFER. Retain old known-good binaries. **S8 verified b11908 artifacts may advance to S9 final-model testing; no general release/default-ON decision follows.**
