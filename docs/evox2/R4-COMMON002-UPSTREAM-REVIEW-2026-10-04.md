# r4 COMMON-002: pinned-upstream MTP review

Recorded: 2026-10-04 JST. Status: source review complete; first allocation smoke
failed after loading. Dense-MTP pool-input fix implemented; Windows rebuild and
repeat smoke are pending. Generation, rollback and performance remain unvalidated.

## Decision

COMMON-002 is the next practical gate after VULKAN-002. Defer COMMON-005's
ROCm-focused decode work. Start with the existing Unsloth Q8_0 MTP sidecar and
the measured Vulkan binary, without porting historical MTP compatibility code.
The pinned upstream already supplies a native Qwen4Exp MTP implementation.

Review base: `ggml-org/llama.cpp` at
`bed0a856606ee4a24a164066f73d2379447033f5`, not moving master.
Downstream source reviewed: `5814fbe99e9249e8ac2c4c2e9b977c05735b0912`.
Neither upstream pin nor runtime defaults change in this review.

## Upstream inclusion and downstream differences

[PR #29761, Qwen4Exp: add MTP](https://github.com/ggml-org/llama.cpp/pull/29761)
merged on 2026-10-01 at `c061df19838ff60970faf54fd7e414953590125d`.
The GitHub compare of that merge to the r4 pin reports `ahead`, 40 commits,
with the merge itself as merge base. Therefore the pinned r4 base includes it.

Blob identities match the pin for the speculative driver, converter, CLI
arguments, model loader/context/memory factory, hybrid/indexer/recurrent memory,
and server verification implementation. At the reviewed `5814fbe99...`, the
Qwen4Exp MTP graph constructor and convolution-history function also match
byte-for-byte despite other downstream
changes in that file. The architecture's rollback-support function is unchanged.
COMMON-001 adds split-PLE loading; VULKAN-002 changes the shared QSA attention
helper to expose selected cell ids. Both main and MTP graphs call that helper,
so the union interaction still needs runtime validation with MTP enabled.

## What the pinned source already implements

| Area | Source finding | Consequence for COMMON-002 |
|---|---|---|
| Conversion | `Qwen4ExpModel.supports_mtp_export = True`; maps MTP modules, concatenates embedding/hidden projections into `nextn.eh_proj`, splits indexer Q/K, emits MTP compression ratio; MTP-only export omits PLE metadata | Native export exists; an older existing GGUF still needs its own compatibility gate |
| Sidecar loading | Detects MTP-only files by absent layer-0 HC attention norm; trunk tensors become optional, MTP tensors are loaded when `load_mtp` is true | A sidecar need not contain the entire trunk; it must contain token embeddings and the required MTP block, plus LM head or tied-output fallback |
| HC norm shapes | HC norms and NextN hidden/head norms allow equal-element-count reshape into `[n_embd, hc]` | Flat HC norm storage is explicitly accommodated; this is not a general tensor-name/shape adapter |
| Hidden state | Main graph exports the HC-wide residual before the final mixer; the MTP graph consumes it with the token embedding and returns the next HC-wide residual | Driver checks equal target/draft `n_embd_out`; current target reports 2560 x 4 = 10240, not just 2560 |
| MTP graph | Requires one NextN block and token input; executes HC mixing, attention, MoE and the NextN HC head | One trained block can be reused autoregressively for multiple draft tokens; `DraftMax=2` does not require two trained blocks |
| Memory | MTP context filters attention/indexer to NextN layers and recurrent layers to none; target retains trunk attention/indexer/recurrent state | Qwen4Exp draft has its own KV/indexer state; it does not take the driver's shared-memory shortcut |
| Prompt catch-up | Non-shared driver pairs each token with the preceding target HC state and decodes the draft for each processed target batch | MTP adds prompt processing and hidden-state transfer work; PP/total latency must be measured separately from TG |
| Acceptance carry | Driver stores verified target hidden rows and selects the accepted boundary row for the next draft | Accepted/rejected boundaries require runtime testing, not just successful allocation |
| Recurrent rollback | Qwen4Exp is listed as supporting bounded rollback; target snapshot count is draft maximum; hybrid/indexer removal first checks recurrent removal and invalidates stale pools | Source support exists to avoid whole-state checkpoint replay within the configured window; check actual logs and state behavior |

### MTP already includes upstream QSA

The upstream MTP graph builds a hybrid/indexer input and calls the same
`build_layer_attn` as the trunk. That helper selects QSA when the indexer pool
exists and that layer's compression ratio is positive. Conversion explicitly
assigns the compression ratio to the MTP block. This is QSA attention, not a
linear/recurrent MTP layer; with missing/zero ratio or no pool it takes the
dense attention fallback.

Thus ordinary upstream MTP can already run QSA without the historical downstream
MTP-QSA prototype. Check the existing sidecar's metadata/indexer tensors before
claiming it actually activates. Reassess any old prototype against this source;
do not treat adding draft QSA from scratch as the next task.

The downstream union switch may cover eligible multi-query MTP catch-up and
target verification through the shared helper. Single-query draft steps still
use the existing one-query path. These are source-path expectations, not measured
MTP speedups. Current union GPU/model acceptance was MTP OFF.

### Rollback and remaining overhead

`common_params_speculative::need_n_rs_seq()` requests `draft.n_max` snapshots
for `draft-mtp`. Qwen4Exp keeps convolution histories for these slots; recurrent
memory also allocates PLE history with the same snapshot count. Increasing draft
maximum increases target recurrent snapshot storage/work, not just draft tokens.
The empty recurrent component in the draft can move its position back without
replaying recurrent state.

The CLI starts the local server implementation. Its verifier uses checkpoint
restore/replay when partial removal is unsupported or rollback exceeds the
available window. Within the normal configured window the source provides the
bounded removal path. This does not prove that the actual model/backend executes
it correctly or that replay never occurs. The server still re-evaluates draft
catch-up after target batches; avoiding whole-target replay does not eliminate
all speculative overhead.

For this target, one 1024-token HC-wide F32 hidden batch alone is
`1024 * 10240 * 4 = 41943040` bytes (40 MiB). This is one buffer's size, not a
peak-memory estimate. Include hidden-state extraction/copying in PP overhead
assessment even on UMA.

## Existing sidecar: runtime questions still open

No MTP-enabled r4 logs or sidecar GGUF header were supplied in the union results.
The subsequent allocation smoke and header inspection are recorded below.
The main GGUF reports 48 trunk blocks and `n_embd_out=10240`; the sidecar's
metadata/tensors must be checked independently. Verify architecture, total
block count and NextN count/index, HC width, required projection/norm/attention/
MoE/head tensors and matching vocabulary/token mapping. A positive MTP compression
ratio with indexer tensors enables QSA; ratio zero must retain dense attention.
Missing or incompatible metadata is a reason to
identify a minimal compatibility delta, not to restore all old patches.

Do not change GGUF data or reconvert the model before the initial load attempt.
Record the sidecar identity and loader error verbatim if it fails.

## Next Windows gates

Use `R4QsaUnionVulkan`, `UnslothPle16` and `UnslothMtp` from the existing local
configuration. The measured executable is b11390, source `5814fbe99...`, CLI
SHA256 `b35dfe13df8d74224dbe6bde5577f78ec50cf5fa03c6f8019b5cddcf5a05fb05`.
The original review commits needed no rebuild. The dense-MTP input fix below
changes runtime code and requires a rebuild before repeating gate 1.
Keep f16 K/V, ubatch 1024, batch
2048, threads/batch threads 4, ngl 999, CPU MoE 0, FA auto and fit off.

Keep legacy MoE tile selection=1, GET_ROWS 128x4=0 and union=1 fixed; profiler
OFF. Clear inherited experimental graph/cache/sparse-disable overrides as in
the existing union measurement plan. The 32k input normally stays below union's
32768-KV threshold; do not lower the threshold to force activation.

| Gate | Workload | Required evidence before proceeding |
|---|---|---|
| 1. Load/allocation smoke | 32k allocated context, short built-in prompt, MTP ON, DraftMax=2, p-min=0 | Main and Q8_0 sidecar identities, target/draft contexts, NextN=1 and matching HC width, GPU backend, no missing tensor/assert/NaN/abort; exit 0 and generation completes |
| 2. Short correctness/rollback | Existing 32k input, fixed 128 tokens, greedy MTP OFF/ON, same seed; targeted trace only if needed | Drafted/accepted counts, actual MTP activation, rejected/partially accepted drafts, expected target snapshot count, no checkpoint replay/state error within the configured window; compare output and investigate mismatches |
| 3. First performance gate | 64k PLE16, fixed 512 tokens, original temp 0.2/top-p 0.8/seed 1234, ignore-eos, profiler OFF; MTP OFF/ON/ON/OFF | PP, TG, acceptance, total prompt+generation time and peak memory; evaluate overall benefit instead of TG alone |
| 4. Long-context value | 128k then 256k, same fixed conditions | Run only after gates 1-3; measure extra draft prefill/KV/hidden transfer and memory cost, stop on failure or overall latency regression |

`Measure-LlamaCli.ps1 -AllocationOnly` is a short-prompt **32-token generation
smoke test**, not a pure no-decode allocator. Existing wrapper switches are
`-Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0`; they pass explicit
`-md`, `--spec-type draft-mtp`, draft GPU layers and f16 draft cache types.

From the repository root in a dedicated measurement PowerShell session, after
clearing inherited overrides:

```powershell
$env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
$env:GGML_VK_GET_ROWS_128X4 = '0'
$env:GGML_VK_QSA_UNION = '1'
Remove-Item Env:GGML_VK_PERF_LOGGER -ErrorAction SilentlyContinue

$mtpCommon = @{
    BuildKey = 'R4QsaUnionVulkan'; ModelKey = 'UnslothPle16'
    Context = 32768; KvType = 'f16'; UBatch = 1024; Batch = 2048
    Threads = 4; GpuLayers = 999; CpuMoe = 0; FlashAttn = 'auto'
    Fit = 'off'; Temperature = 0; PromptCacheMiB = 0
    ResourceMonitor = $true
    ExtraArgs = @('-tb', '4', '--ctx-checkpoints', '0t', '--seed', '1234', '--ignore-eos')
}
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @mtpCommon `
    -AllocationOnly -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
```

Stop and review this first archive. After it passes, use the same session/options
for the short baseline and MTP pair:

```powershell
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @mtpCommon `
    -InputKey '32k' -GenerationTokens 128
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 @mtpCommon `
    -InputKey '32k' -GenerationTokens 128 `
    -Mtp -DraftModelKey UnslothMtp -DraftMax 2 -DraftPMin 0
```

Draft acceptance is workload dependent; no acceptance percentage or throughput
gain is required from an unrelated upstream device/model benchmark. Tune draft
maximum/p-min only after compatibility and a fixed baseline are established.
The upstream `test-recurrent-state-rollback` target also exists for an additional
state/logit check if the smoke/trace reveals ambiguity; its model/backend pass
is not asserted here. The initial source review changed no runtime code or
measurement scripts; the subsequent scoped runtime fix is recorded below.

## Allocation failure and dense-MTP input fix

Supplied run: `20261004-003447-112-cli-vulkan-b11390-ctx32768-50108d5463b6`,
2026-10-04 00:34:47-00:35:29 JST. Allocation short prompt, MTP ON, DraftMax=2,
p-min=0, greedy, f16 main/draft caches, union=1, legacy MoE=1, GET_ROWS 128x4=0.
Same b11390 executable/source/hash as the union baseline. Status FAILED,
exit 3221226505 (`0xC0000409`), no prompt/generation or acceptance result.

Loading succeeds for the main PLE16 model and the 4137429120-byte Q8_0 sidecar
(34 tensors). Sidecar metadata reports 49 total blocks, NextN=1, HC count=4,
embedding width=2560, output hidden width=10240, matching the target. Draft
context reserves attention KV 64 MiB and indexer KV 16 MiB; target requests two
recurrent rollback snapshots. The driver registers `draft-mtp`, then initialization
aborts at `ggml-backend.cpp:345: GGML_ASSERT(buffer)` before serving the prompt.
No missing-tensor, allocation-failed or Vulkan error is logged.

The user's read-only GGUF inspection confirms compression ratios
`[0,0,0,4]` repeated 12 times, followed by `0`: MTP block 48 has ratio zero.
Consequently this existing sidecar requests **dense MTP attention**. Upstream's
new converter can export QSA MTP, but that does not establish QSA activation in
this older file. Do not change its metadata to force QSA during compatibility work.

The MTP graph previously created k-pool inputs whenever an indexer cache and a
positive model-wide pool size existed. The trunk's ratios provide that pool size
even when the MTP block's ratio is zero. `build_layer_attn` then takes the dense
path and leaves pool index/update inputs unreferenced. Registered
`llm_graph_input_kpool::set_input` still writes them; its first index setter calls
`ggml_backend_buffer_is_host` on the unallocated index tensor, which reaches the
reported buffer assertion. The log has no backtrace; this source-path diagnosis
and confirmed metadata must be validated by the repeat Windows smoke.

The minimal COMMON-002 delta adds the current MTP layer's positive compression
ratio to the pool-input creation guard in `graph_mtp`. Ratio zero registers no
k-pool input setter and keeps dense attention. Positive-ratio MTP retains the
native QSA path and the existing cache alignment assertion. Main graph pool
creation, selector/union thresholds, tensor loading, recurrent snapshots and
GGUF data are unchanged. Existing draft indexer memory remains allocated; removing
that unused memory is outside this fix.

Validation here: reviewed the ratio-zero and positive-ratio source paths; verified
the main graph constructor is unchanged and the shared attention predicate agrees
with the new MTP guard; `git diff --check` passes. This environment cannot run
the Windows/Vulkan model build or repeat GPU smoke. No pass or speedup is claimed.

Rebuild the existing measured build directory, preserving its CMake options and
refreshing the manifest, then repeat the same allocation command above:

```powershell
git pull --ff-only
& .\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-r4-qsa-union -BuildOnly
```

Check the new executable commit/build manifest before the run. Keep the same
environment and draft settings; no diagnostic optimizer/sampling disable switch
is needed for this repair. Review the repeated allocation archive before gate 2.

## Pinned source references

- [Qwen4Exp tensors, main/MTP graphs, QSA and convolution snapshots](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/src/models/qwen4exp.cpp)
- [Qwen4Exp conversion](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/conversion/qwen4exp.py)
- [MTP driver and draft context initialization](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/common/speculative.cpp)
- [Snapshot count request](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/common/common.h)
- [Common model/context parameter mapping and sequence-removal detection](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/common/common.cpp)
- [Architecture rollback capability](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/src/llama-arch.cpp)
- [Qwen4Exp draft/trunk memory filtering](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/src/llama-model.cpp)
- [Hybrid/indexer removal and stale-pool tracking](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/src/llama-memory-hybrid-idx.cpp)
- [Recurrent snapshot storage and bounded removal](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/src/llama-memory-recurrent.cpp)
- [Verification, replay fallback and catch-up](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/tools/server/server-context.cpp)
- [Upstream recurrent rollback test](https://github.com/ggml-org/llama.cpp/blob/bed0a856606ee4a24a164066f73d2379447033f5/tests/test-recurrent-state-rollback.cpp)

Baseline evidence: [R4-VULKAN002-VALIDATION-2026-10-04.md](R4-VULKAN002-VALIDATION-2026-10-04.md).
