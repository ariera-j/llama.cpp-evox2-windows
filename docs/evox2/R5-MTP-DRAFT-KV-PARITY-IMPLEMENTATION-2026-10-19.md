# MTP Draft KV numerical parity gate — 2026-10-19

> **2026-10-19 build correction:** Earlier version referenced nonexistent `common_batch::token::is_prompt` and failed compiling `common/speculative.cpp:1659`. Fixed in commits `e161d313` (server prompt-phase propagation) and `3c437e6e` (Draft hook). Pull latest branch commit before retrying. No native compile success is asserted yet.

**Status: diagnostic source, C/A/B benchmark plan, Python numerical comparator and synthetic regression tests COMMITTED. Windows Vulkan native compilation and model execution NOT YET PERFORMED; no correctness verdict and no speed claim.**

## Scope / baseline safety

Branch: `investigation/r5-mtp-draft-kv-parity-20261019`; branched from **completed and retained** `investigation/r5-mtp-eh-proj-flatten-20261016` after same-binary A/B RGP closure. The previous b11659 binary (SHA256 `317d76e3d915c766397c076375438602a2c238d60ccefbd0da079e63a28c5009`) must remain **untouched**. No inference math, graph builder, Vulkan kernels, ROCm source or stable r5 source was modified. This branch merely adds a diagnostic C++ hook, private header, testing plan and parser.

The required comparison is:
- **C**: `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=0`, flatten=0 (baseline full Draft graph);
- **A**: Stage-B `LLAMA_MTP_DRAFT_PREFILL_KV_CROP=1`, flatten=0;
- **B**: Stage-B=1, `LLAMA_MTP_EH_PROJ_FLATTEN=1`.

All arms use **exactly the same newly compiled binary**, original PLE16 Target and self-contained Unsloth MTP Q8_0 sidecar, f16 K/V, QSA union ON/minKV32768, same seed/temperature, prompt data and P-MODE. Diagnostics should be the only runtime change between the previous normal ABBA and the new experimental binary.

## Implementation

- `common/mtp-kv-snapshot.h`: opt-in `mtp_kv_snapshot::recorder`, no-op unless all of `LLAMA_MTP_KV_SNAPSHOT_DIR`, `_TAG`, `_POSITIONS` are set. `_TAG` must be an ASCII-safe label; `_POSITIONS` are comma-separated **1-based token-count thresholds**. On the first completed prompt Draft catch-up whose `end_pos + 1 >= threshold`, synchronously stream Draft sequence-0 state with existing `llama_state_seq_save_file(ctx_dft,..., seq_id=0, tokens=nullptr, n_tokens=0)`. The state file has the normal llama seq-state header and serializes **KV cell metadata, actual K/V values, recurrent state and possibly the indexer suffix**; this is not a new raw format. The helper logs `mtp_kv_snapshot_v1 OK tag=... threshold=... pos=... bytes=... path=...` to stderr; failure returns false, breaking the diagnostic rather than silently producing an apparently complete run. Existing files are never silently overwritten.
- `common/speculative.cpp`: include helper; hook **immediately after successful Draft catch-up `llama_process(ctx_dft)`**, before the Target hidden-state copy for later verification. **`common_batch::token` has no `is_prompt` field**: the hook instead checks `mtp_pp_process_phase == 1` and sequence ID. `tools/server/server-context.cpp` explicitly derives and passes that phase from its source `batch.tokens[i].is_prompt` whenever either CPU phase trace or `LLAMA_MTP_KV_SNAPSHOT_DIR` is set. Do not capture generation/mixed batches. This was corrected after a native Windows compile error on 2026-10-19.
- `tools/evox2/benchmark/configs/qwen38-r5-mtp-draft-kv-parity.psd1`: `kv-short` (threshold 1), `kv-64k` (1024,32768,61789), `kv-128k` (32768,65536,126253). Each job has C/A/B arms and its own snapshot directory. Existing resource-monitoring and authoritative P-MODE capture remain on.
- `tools/evox2/benchmark/analyze_mtp_kv_parity.py`: memory-maps two **zero-token llama seq-state files** and parses only the FIRST **attention K/V** section; validates common header, layer count, type, logical cell positions and seq-ID ownership, then numerically compares **all active positions and every element** of each K and V layer, independent of physical slot order. Handles native f16/f32 row-major K/V and transposed V. The later recurrent and indexer states are **not compared by this utility**.
- `tools/evox2/tests/test_mtp_kv_parity.py`: artificial state fixtures for physical-slot permutation, f16 numerical mismatch, transposed V, optional 12-byte per-cell extension and seq/position mismatch. This test does not substitute for native runs.

**Opt-in side effects:** sequence-state serialization forces Draft GPU synchronization and writes potentially hundreds of MiB per checkpoint to local disk. It can increase total RAM/disk pressure and has no diagnostic timing value. Do not mix with RGP. The snapshot dirs are **not** part of the benchmark ZIP and must be retained separately; only the small comparator JSON and relevant stderr/result ZIP normally need uploading.

**Boundaries:** this first validation path supports **one non-mixed prompt sequence, stream 1, GGML f16/f32 K/V**. If underlying native seq-state serialization changes, the parser must fail closed instead of reporting matching arbitrary bytes. Metadata can include an optional 12-byte KV cell extension (x,y,tok); parser auto-detects 0/12 only if unambiguous. If snapshots fail to appear, do NOT call the run a PASS. Numeric parity for K/V cache alone does **not** establish the correctness of recurrent state, indexer cache, post-prompt rollback or speculative reject/replay.

## Windows commands — native build gate (do not reuse b11659)

Use your existing r5 worktree. Move aside existing results before a rerun (the saver refuses to overwrite old files).

```powershell
git fetch origin
git switch investigation/r5-mtp-draft-kv-parity-20261019
# If the branch is not local yet:
# git switch --track origin/investigation/r5-mtp-draft-kv-parity-20261019

python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_kv_parity.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-r5-mtp-kv-parity `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

Add this BuildKey to ignored `tools/evox2/benchmark/configs/local.psd1` alongside the original model/input keys, pointing to the new build's **bin/Release**:

```powershell
R5MtpKvParityVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r5\build-vulkan-r5-mtp-kv-parity\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

Use the **actual** checkout/build directory, not the illustrative path if different. Confirm the executable hash changes from b11659; `R5MtpEhProjFlattenVulkan` must retain its original mapping.

## Smoke and numerical comparator

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-draft-kv-parity.psd1 `
  -PlanOnly

.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-draft-kv-parity.psd1 `
  -OnlyJob kv-short
```

Confirm **all three** arms exit0, each emits `mtp_kv_snapshot_v1 OK ... threshold=1`, has saved one file and has matched prompt length and same compiled executable. **Important: `Measure-LlamaCli.ps1` starts llama-cli with `-WorkingDirectory` set to its executable directory** (`<new-build>/bin/Release`), so `kv-parity-output/short` is created **under that bin/Release directory**, not under the repository root or the ZIP/logs directory. Use the **absolute `path=` in stderr** as the source of truth. The commands below define `$kvDir` for the illustrative default build; adjust it to the actual path. Then run the parser locally (NumPy required):

```powershell
$kvDir = '.\build-vulkan-r5-mtp-kv-parity\bin\Release\kv-parity-output\short'
python .\tools\evox2\benchmark\analyze_mtp_kv_parity.py `
  --directory $kvDir --left C --right A --threshold 1 `
  --report (Join-Path $kvDir 'C-vs-A.json')

python .\tools\evox2\benchmark\analyze_mtp_kv_parity.py `
  --directory $kvDir --left A --right B --threshold 1 `
  --report (Join-Path $kvDir 'A-vs-B.json')
```

The comparator emits compact JSON with logical token count/position bounds, per-layer K/V checked element count, **bitwise difference count**, numerical tolerance-failure count, non-finite count, max absolute/relative error and **PASS/FAIL**. Defaults: `atol=0.001, rtol=0.001`, fail for missing positions, seq ownership changes, NaN/Inf or any element outside tolerance. Check the strict difference counts even when within the default tolerance; do not quietly widen tolerances to force success. Record both `C vs A` (Stage B effect) and `A vs B` (flatten effect). Optionally add `C vs B` as a cross-check.

`mtp-short.txt` contains only a small prompt, so short demonstrates loading/snapshot/parser wiring, not 1024-token geometry. **If short fails, stop before 64k.**

## Next, 64k then 128k gates

After the short C/A/B parity and acceptance sanity pass:

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
  -Plan .\tools\evox2\benchmark\configs\qwen38-r5-mtp-draft-kv-parity.psd1 `
  -OnlyJob kv-64k
```

Analyze thresholds **1024, 32768, 61789** for C→A and A→B using the same parser, setting `--directory (Join-Path (Split-Path $kvDir -Parent) '64k')` and `--threshold` for each (or using the saved `path=` directory in stderr). Compare actual logged end positions, total active K/V cell count, seq ownership, relative/absolute tolerances and post-prefill 512-token generation text + acceptance. At most one binary snapshot per threshold per arm is expected.

Then run `-OnlyJob kv-128k` at thresholds **32768,65536,126253** only if 64k passes. For a bounded first 128k test, `-OnlyVariant A-stageb-on-flat-off,B-stageb-on-flat-on` omits C until the A/B gate passes. Full C/A/B is needed before claiming Stage-B parity through 128k.

Snapshot files grow with context; verify disk headroom (potentially several GiB across the three arms) and avoid uploading raw state binaries unless diagnosis requires them. When reporting results, send **small JSON comparator reports**, benchmark ZIPs and any `mtp_kv_snapshot_v1 ERROR` lines, not full binary snapshots.

## Subsequent correctness gates, not implemented by snapshot comparison

1. Compare post-prompt **generated text, Draft acceptance and normal speculative decode** for C/A/B under fixed seed/temp. Use `stdout`, `stderr`, and benchmark results.
2. **Accept/reject/rollback**: design a separate deterministic continuation/rollback stress test that actually exercises rejection and state restoration; current basic CLI smoke only checks ordinary decode and whichever rejections naturally occur, not all rollback cases.
3. Assess recurrent state and QSA indexer state where applicable, especially if the candidate is widened beyond the self-contained ratio-zero Draft. Current Python reader reads attention K/V only.
4. If these gates pass, record **correctness scope**, numerical tolerances, backend/model/context, build SHA and raw evidence before proposing Stage B / flatten integration into a **new-upstream candidate branch**. ROCm remains a separate native correctness/performance gate.

**Do not merge this experimental diagnostic into the stable inference runtime.** Keep the b11659 ABBA/RGP cohort reproducible.

## 2026-10-19 short native validation — PASS (C/A and A/B)

The user reports that the corrected dedicated branch **compiled successfully on Windows** and the `kv-short` C/A/B matrix produced three `threshold=1` snapshots at **actual prompt end pos=162 (163 tokens)**. The two numerical comparisons were executed with default `atol=rtol=0.001` and report:

| Pair | Logical positions | K elements | V elements | Bitwise differences | Outside tolerance | Max abs/relative | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| C (Stage-B OFF) → A (Stage-B ON, flatten OFF) | 163, range 0..162 | 83,456 | 83,456 | **0 K / 0 V** | 0 | 0 / 0 | **PASS** |
| A (flatten OFF) → B (flatten ON) | 163, range 0..162 | 83,456 | 83,456 | **0 K / 0 V** | 0 | 0 / 0 | **PASS** |

All compared attention storage is **f16**, **1 attention layer**, **512 elements per token for each K and V**, nontransposed V, and single-sequence state. The raw C/A/B snapshot binary files are retained locally by the user; comparison JSON was pasted in chat. This short prompt does **not** exercise the 1024-token flattened GEMM from RGP or long-cache behavior, so the correctness claim is **short-context/short-prompt only**.

The attached **B-arm** native ZIP `20261019-211544-319-cli-vulkan-b11682-ctx32768-cce740a55b8d.zip` was inspected:
- Vulkan, **b11682 / reported executable commit `b617984d8`**, compiler Clang 20.1.8, exe SHA256 **`737324a93095a61c31fdbdd155058e6ebdf2eb7b997b67ac877f39a5ff420a38`**, runtime artifact digest **`c44f279afb663e89dc8ea6595abef87f7e35914303ca735a9036acaccfa5e23e`**;
- normal exit0, 163-token prompt, 32 generated, **Draft 17/27 accepted**, P-MODE **Performance at start and finish**; ADLX high-load classifier `InsufficientSamples` for short job (not an error);
- `mtp_kv_snapshot_v1 OK tag=B threshold=1 pos=162 seq=0 bytes=423264` with absolute path to `build-vulkan-r5-mtp-kv-parity/bin/Release/kv-parity-output/short`;
- the manifest marks **`Source.Dirty=true`** (dirty fingerprint `13afa3188e82c7377ad0ebbfc9fd763b6df3b7a910ec24fb6370f91618bb3568`) at native build. **Before using this build as an integration correctness baseline, verify/reconcile local `git status --short` and that C/A/B runs really share the same executable SHA.** We do not infer an actual uncommitted code change from the dirty flag without inspecting the local diff.
- Only **B run ZIP** accompanied the user message, not the C/A child ZIPs or matrix result metadata. The C/A comparison reports necessarily demonstrate both raw A/C states existed and parsed, but model/executable identity of those arms has not independently been inspected yet. Request their result metadata/ZIP if mismatches arise or before final integration attestation.

**Next:** run 64k plan, preferably **A/B variants first** to exercise the flattened 1024-token Draft matmul, then C for full Stage-B proof. Thresholds `1024,32768,61789` are first crossed at ubatch boundaries, so compare **actual `pos=` and position maps**, not just filenames. Both pairs must independently pass at each depth, and generated text/acceptance and condition identity must be checked; otherwise halt before 128k. This measurement deliberately forces GPU synchronization and dumps potentially hundreds of MiB of Draft state: **do not interpret PP/TG as a speed result**. Numeric attention KV equality still does not establish recurrent/indexer state parity or forced rejection/rollback.

