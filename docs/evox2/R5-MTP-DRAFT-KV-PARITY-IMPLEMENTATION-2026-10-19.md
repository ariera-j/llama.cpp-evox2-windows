# MTP Draft KV numerical parity gate — 2026-10-19

> **Historical 2026-10-19 build correction (now resolved):** Earlier version referenced nonexistent `common_batch::token::is_prompt` and failed compiling `common/speculative.cpp:1659`. Fixed in commits `e161d313` (server prompt-phase propagation) and `3c437e6e` (Draft hook). Windows b11682 has since built and completed short/64k/128k native runs. This historical note is not a current blocker.

**Status (updated 2026-10-19 ~22:08 JST): native Windows Vulkan b11682 built successfully; short, 64k, and 128k C/A/B Draft attention K/V equality gates all PASSED bitwise at every compared position, and ordinary 512-token generation text/acceptance match at 64k/128k. NOT YET validated: serialized recurrent/indexer state equivalence, forced speculative accept/reject/rollback, other backends or quantizations. Diagnostic PP/TG are not performance measurements.**

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

### 2026-10-19 local Source.Dirty explanation from user

User ran `git status --short` on the Windows checkout after the successful b11682 short test. The only listed changes are benchmarking and monitoring tools copied from a separate branch:

```text
 M tools/evox2/benchmark/Evox2.Benchmark.psm1
 M tools/evox2/benchmark/Invoke-BenchmarkMatrix.ps1
 M tools/evox2/benchmark/Measure-LlamaBench.ps1
 M tools/evox2/benchmark/Measure-LlamaCli.ps1
 M tools/evox2/benchmark/Monitor-LlamaProcess.ps1
 M tools/evox2/lib/Evox2.Common.psm1
?? tools/evox2/adlx-gpu-monitor/
?? tools/evox2/pmode/
```

**No modified inference, Draft, ggml, backend, or model source appears in this status.** This plausibly explains the `Source.Dirty=true` manifest observation. No build rerun or git clean/reset is needed for the immediate **C/A/B correctness comparison** if all arms use the same b11682 executable digest and the same local test harness. Preserve the local P-MODE/ADLX instrumentation until the tests finish. The exact diff/hashes of these uncommitted tooling files have **not** been archived in GitHub by this note; `git status` documents paths but not their content. Before a new-upstream integration or externally reproducible performance baseline, commit or otherwise capture the harness diff and include its provenance. Do not silently transplant those tooling changes into the r5 stable inference tree.

The wording “the build was dirty only because of tools” is a **worktree-status-supported explanation**, not a line-by-line diff audit or a cryptographic proof of the historical build tree. The user-reported status contains no inference-source changes and thus does not undermine the bit-exact short Draft K/V result.

## 2026-10-19 64k native validation — six numerical comparisons PASS, full input and generation

**Status: 64k Draft attention KV correctness gate PASSED for the tested b11682/Vulkan/Unsloth PLE16 + Q8_0 Draft configuration.** User pasted all six JSON comparison results for the 3 C/A/B snapshots and supplied an archive containing **all three native child runs**. This is not yet a 128k gate, nor a recurrent state / rollback correctness pass.

Native archive: `20261019-212754-335-cli-vulkan-b11682-ctx65536-4393dc97f141.zip`; **SHA256 `29fec25172c2c306c9cd45ac3e4ec81bbfcd242c4fab58e091b63570b96346a3`**. Child runs C=`20261019-212318-012-cli-vulkan-b11682-ctx65536-4e548d200013`, A=`20261019-212754-335-cli-vulkan-b11682-ctx65536-4393dc97f141`, B=`20261019-213226-676-cli-vulkan-b11682-ctx65536-92eb18ac8d8b`. All three are status OK / exit0; b11682, Clang20.1.8, exactly same executable SHA256 `737324a93095a61c31fdbdd155058e6ebdf2eb7b997b67ac877f39a5ff420a38` and runtime artifact digest `c44f279afb663e89dc8ea6595abef87f7e35914303ca735a9036acaccfa5e23e`. The source-dirty fingerprint is likewise unchanged between these runs; previously identified non-inference P-MODE/ADLX harness modifications were left in the local worktree.

Effective run conditions checked via all three `conditions.json`: **61,789 prompt tokens, 512 output**, context65536, Vulkan, f16 Target/Draft KV, ubatch1024, batch2048, PLE16 Target with MTP-Q8_0 sidecar, QSA union ON/minKV32768, MTP enabled, temperature0/seed1234, same input SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`, P-MODE Performance at start/end in all arms. Only Stage-B / flatten settings (and snapshot tag) differ: **C=0/0, A=1/0, B=1/1**.

| requested threshold | actual cell positions | KV element count **per K or V per pair** | C→A | A→B |
| ---: | ---: | ---: | --- | --- |
| 1,024 | 0–2,047 (2,048 positions), filename pos2047 | **1,048,576** | **PASS, 0 bit differences** | **PASS, 0 bit differences** |
| 32,768 | 0–32,767 (32,768 positions), pos32767 | **16,777,216** | **PASS, 0 bit differences** | **PASS, 0 bit differences** |
| 61,789 | 0–61,788 (61,789 positions), pos61788 | **31,635,968** | **PASS, 0 bit differences** | **PASS, 0 bit differences** |

Every comparison on **one f16 attention layer with 512 floats per token for each K and V**, native row-major V, single sequence. All six pairs report `outside_tolerance=0`, `nonfinite=0`, `max_abs=0.0`, `max_relative=0.0`, matching logical position sets and metadata. Total **98,923,520 K+V values per C/A or A/B pair summed across three cumulative snapshots**; note that these are cumulative, not independent tokens. The first threshold is crossed only at the end of a **2048-token batch**, as indicated by file name `pos-2047`; this is expected and must be labeled as the actual sampled boundary.

Snapshots at each arm/threshold were observed in `stderr.log` (`mtp_kv_snapshot_v1 OK`), and state file sizes were identical across arms at each checkpoint: **5,316,724 bytes, 85,065,844 bytes, 160,404,360 bytes**. Raw `.bin` state snapshots are held locally and **not** part of the uploaded ZIP; all six comparator JSON results were pasted in chat.

Generated text was verified byte-identical across all three child `stdout.log` files **after excluding the printed per-run PP/TG speed banner**; normalized region SHA256 `5013d9308389667530dc78b8008ea27f1ed2d5038d827428dc6bf3ea5e39d5e2`. Draft acceptance in all arms **295/430 (68.605%)**.

| arm | diagnostic PP tok/s | diagnostic TG tok/s | PromptEval ms | Performance P-MODE |
| --- | ---: | ---: | ---: | --- |
| C Stage-B OFF / flatten OFF | 313.10 | 28.19 | 197,348.58 | start=end |
| A Stage-B ON / flatten OFF | 323.85 | 28.91 | 190,797.14 | start=end |
| B Stage-B ON / flatten ON | 327.80 | 28.87 | 188,496.82 | start=end |

**Do not interpret these numbers as performance evidence:** the capture hook synchronizes and serializes Draft state to disk three times, strongly perturbing execution. Use previous independent uninstrumented ABBA and focused RGP for source performance evidence.

**Implication:** both Stage-B and flatten produced **exactly unchanged Draft attention KV contents over every active position at all sampled depths up to 61,789 prompt tokens**, while ordinary completion text and acceptance matched. This is a robust numerical gate for the tested f16 path, including long-context 1024-token Draft operations. It does **not** compare the recurrent-state buffer, QSA indexer suffix, or controlled accept/reject/rollback behavior.

**Next P0: run the existing `kv-128k` job** using the same b11682 executable, thresholds **32768, 65536, 126253**, C/A/B full matrix. Compare each threshold's actual saved `pos` and both C→A and A→B JSONs; verify generated text/acceptance, hashes and Performance mode. **No code changes or rebuild are needed before 128k.** Expect around 1.5–2 GiB cumulative files depending on recurrent state. Stop if any mismatch. After 128k passes, design/execute a separate recurrent-state and rollback/reject stress test before proposing inclusion in the new-upstream integration candidate.

## 2026-10-19 128k native validation — all six C/A/B attention K/V comparisons PASS

**Completed:** user ran `kv-128k` on the same native b11682 Vulkan binary and pasted all six `analyze_mtp_kv_parity.py` JSON reports. Both C→A (Stage-B OFF→ON) and A→B (flatten OFF→ON) yielded **zero bitwise differences, zero values outside tolerance, zero nonfinite values and zero max abs/relative error** across all active K and V elements at the three prompt positions.

| Threshold tokens | Actual saved position range | K elements per pair | V elements per pair | C→A | A→B |
| ---: | ---: | ---: | ---: | --- | --- |
| 32,768 | 0–32,767, file `pos-32767` | 16,777,216 | 16,777,216 | **PASS, bitwise 0** | **PASS, bitwise 0** |
| 65,536 | 0–65,535, file `pos-65535` | 33,554,432 | 33,554,432 | **PASS, bitwise 0** | **PASS, bitwise 0** |
| 126,253 | 0–126,252, file `pos-126252` | 64,641,536 | 64,641,536 | **PASS, bitwise 0** | **PASS, bitwise 0** |

Each snapshot contains one **f16** Draft attention layer, K width512 and V width512, V nontransposed, seq0, consistent logical cell sets. The numeric comparator uses `atol=rtol=0.001`, but every value was **bit identical**, not merely within tolerance. Counts are cumulative per snapshot; do not count them as independent tokens. Across all three 128k checkpoints, each C/A or A/B pair compares 114,973,184 K floats and 114,973,184 V floats (repeated older positions intentionally included).

**Native archive:** `20261019-215953-397-cli-vulkan-b11682-ctx131072-ea94f4719823.zip`, SHA256 **`681b024dd215047a86725a8797eae3eb0f66f0e865288d4439f3f66b36efa660`**. It contains all three C/A/B child run directories:

- C: `20261019-214211-882-cli-vulkan-b11682-ctx131072-c5c1f6b2188c`;
- A: `20261019-215114-656-cli-vulkan-b11682-ctx131072-d4b744d7a87d`;
- B: `20261019-215953-397-cli-vulkan-b11682-ctx131072-ea94f4719823`.

**Independently checked from all three `conditions.json` and `result.json`:** `Status=OK`, exit0, same executable SHA256 **`737324a93095a61c31fdbdd155058e6ebdf2eb7b997b67ac877f39a5ff420a38`**; same runtime artifact digest **`c44f279afb663e89dc8ea6595abef87f7e35914303ca735a9036acaccfa5e23e`**; b11682 Clang20.1.8; 126,253 prompt / 512 generated tokens; 131072 context, f16 KV, batch2048/ubatch1024, Vulkan, 96GB UMA, same PLE16 model/Draft/input identity (input SHA256 begins `182d14a0ca0a8da365`), seed1234/temp0; QSA union ON/minKV32768; P-MODE **Performance both at start and end** in every arm and ADLX Performance-like. Environment differs in intended `LLAMA_MTP_DRAFT_PREFILL_KV_CROP / LLAMA_MTP_EH_PROJ_FLATTEN / LLAMA_MTP_KV_SNAPSHOT_TAG`: **C=0/0/C, A=1/0/A, B=1/1/B**. All runs report **Draft accepted/generated 295/429**, or 68.765% (note denominator **429** for 128k, versus **430** in earlier 64k results). After removing the printed speed banner, all three `stdout.log` contents were identical, SHA256 **`4a05d0d5e5bc7417e0c48837322ef65ad3db2f3fde711c23bb99ef4ade38052b`**.

| Arm | Diagnostic PP tok/s | Prompt time s | Diagnostic TG tok/s | ADLX high-load W |
| --- | ---: | ---: | ---: | ---: |
| C (Stage-B OFF, flatten OFF) | 274.78 | 459.472 | 23.48 | 107.363 |
| A (Stage-B ON, flatten OFF) | 292.85 | 431.122 | 23.73 | 107.067 |
| B (Stage-B ON, flatten ON) | 295.47 | 427.289 | 23.86 | 106.732 |

**These timings are diagnostic-only and must not replace uninstrumented ABBA**: the program serializes Draft state synchronously to host/disk at each checkpoint. All 9 expected `mtp_kv_snapshot_v1 OK` messages appear with matching actual positions; every arm's files are identical in size at each threshold: **85,065,844**, **170,131,572**, **327,752,904** bytes. Aggregate binary snapshot size across C/A/B is **1,748,850,960 bytes (~1.63 GiB)**. Raw `.bin` dumps remain local and were not provided in the ZIP; the six comparator JSON outputs were pasted by the user.

**Scope and remaining gates:** the tested Stage-B and flatten optimizations preserve **the Draft attention K/V values at every active position through 126,253 tokens**, not just a statistical sample of K/V rows. This is a strong isolated correctness finding. The Python comparator intentionally **does not read the trailing recurrent state or QSA indexer state** inside the serialized Draft sequence state; it does not prove those buffers equal. Ordinary generated text / acceptance matches; it does not systematically force rejection, replay or rollback. Neither the current branch's diagnostic source nor the optimized Stage-B/flatten implementation is yet incorporated into a validated new-upstream integrated release.

**Next recommended P0:** before investing in another long benchmark, compare **the entire serialized state** (recurrent/indexer sections included) at corresponding C/A/B checkpoints by streaming hashes; if the complete files are byte-identical this provides additional strong evidence beyond K/V. If hashes differ, **do not automatically conclude a model-state failure**: physical slot ordering, nonsemantic metadata or serialization differences may cause binary divergence, so add a structured trailing-state parser or an instrumented state digest for logical-state comparison. Independently test **forced accept/reject/rollback and post-catch-up continuation**, with a deterministic fixed-seed scenario, before final integration acceptance. If broader new-upstream integration is scheduled first, carry Stage-B/flatten as **experimental candidates with these explicit correctness limitations**.


### Next local no-rebuild follow-up: full serialized Draft state SHA256

This **compares entire serialized seq-state files**, not just the parsed attention KV. In addition to attention K/V, the public state serializer includes the Draft recurrent state and (when present) indexer state. Identical hashes give strong bitwise equality of the whole serialized byte stream at that checkpoint, including its metadata. Different hashes are **inconclusive** until mapped to logical recurrent/indexer values, since cache-slot order and other serialization metadata can differ without changing model semantics. This is a low-cost triage, **not a substitute** for forced rejection / rollback.

From repository root on Windows, without rerunning inference:

```powershell
$kvDir = '.\build-vulkan-r5-mtp-kv-parity\bin\Release\kv-parity-output\128k'
$checks = foreach ($threshold in @(32768, 65536, 126253)) {
    $hashes = @{}
    foreach ($arm in @('C', 'A', 'B')) {
        $files = @(Get-ChildItem -LiteralPath $kvDir -File `
            -Filter "draft-kv-$arm-threshold-$threshold-pos-*.bin")
        if ($files.Count -ne 1) {
            throw "Expected 1 snapshot for $arm at $threshold; got $($files.Count)"
        }
        $hashes[$arm] = (Get-FileHash -LiteralPath $files[0].FullName -Algorithm SHA256).Hash
    }
    [pscustomobject]@{
        Threshold = $threshold
        C_vs_A = ($hashes['C'] -eq $hashes['A'])
        A_vs_B = ($hashes['A'] -eq $hashes['B'])
        C_SHA256 = $hashes['C']
        A_SHA256 = $hashes['A']
        B_SHA256 = $hashes['B']
    }
}
$checks | Format-Table Threshold, C_vs_A, A_vs_B -AutoSize
```

Keep the printed checks and SHA256 values. If all rows are `True`, the entire serialized attention/recurrent/(optional indexer) state is bitwise equal in this serialization. If any are `False`, proceed to structured state comparison **before** interpreting the divergence. Post-prefill replay and forced rollback remain open even if every full state hash matches.
