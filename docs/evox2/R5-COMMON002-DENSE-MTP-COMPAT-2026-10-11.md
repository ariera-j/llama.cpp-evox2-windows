# r5 COMMON-002: ratio-zero Unsloth MTP input compatibility gate (2026-10-11)

**Status: source candidate committed; Windows build / MTP smoke NOT YET VERIFIED.** This is an isolated research branch; stable `r5/upstream-refresh-20261009` is unchanged. No speed or acceptance claim. Source change mirrors the validated r4 dense-MTP k-pool input guard and does **not** port the later r4 dense indexer omission, target no-op suppression or historical MTP-QSA prototype.

## Failure evidence (before patch)

User-supplied bundle: `20261011-144136-467-cli-rocm-b11543-ctx32768-ce00d7df7865.zip`.

| Run ID (2026-10-11 JST) | Result | Workload and identity |
| --- | --- | --- |
| `20261011-144046-836-cli-rocm-b11543-ctx32768-6a2ab11dd830` | **PASS**, exit 0; PP 39.33 tok/s, TG 25.89 tok/s, 18 prompt / 32 generated tokens | ROCm `llama-cli` b11543 / `28d0f32d0`, executable SHA256 `cd6aab3334dfdfefed0a9577cd4b8e3647271767e91e4d53a9a47118075d4e37`; MTP OFF |
| `20261011-144136-467-cli-rocm-b11543-ctx32768-ce00d7df7865` | **FAIL**, startup abort before prompt; `ggml/src/ggml-backend.cpp:345: GGML_ASSERT(buffer) failed` | Exactly the same `llama-cli` binary and main PLE16 GGUF; Unsloth `mtp-Qwen3.8-Flash-Next-Q8_0.gguf` (4,137,429,120 bytes, 34 tensors), `--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-p-min 0`, f16 K/V, ctx 32768, 96GB UMA label |

The failed log shows full target and draft tensor loading, draft context KV 64 MiB and **indexer KV 16 MiB**, successful scheduler reservation (127 then 133 nodes), followed by buffer assertion immediately after speculative driver initialization. There is no completed prompt, output-token rate, or draft acceptance on the failing run. `GGML_ASSERT(buffer)` is a symptom; a stack trace was **not** provided. Source review plus [r4 matching failure analysis](R4-COMMON002-UPSTREAM-REVIEW-2026-10-04.md#allocation-failure-and-dense-mtp-input-fix) strongly points to an unused registered k-pool input setter in a ratio-zero dense MTP graph.

The original GGUF was previously inspected in r4: 48 trunk layer compression ratios repeating `0,0,0,4` plus a **zero** ratio for its 49th (MTP) layer. The r5 log shows metadata array length 49 but truncates individual values, so the final ratio is supported by the **previous read-only r4 GGUF inspection of the same-size same-named draft**, not independently decoded from the latest log. Retest after the patch is the required causality gate; do not call this fix validated yet.

The desktop checkout at execution time was `investigation/r5-vulkan-off-fa-dispatch-20261010` / `0a2a7970c5`, but the **executed binary SHA and embedded commit** (shown above) are what identify the failing ROCm run; no source change in the old Vulkan investigation checkout can be inferred to have been compiled into the HIP executable. All model/load/buffer timings come from the zipped Windows logs.

## Source delta

File: `src/models/qwen4exp.cpp`, **MTP graph only** (not trunk). Add `hparams.dsv4_compress_ratios[il] > 0` to the existing `mctx_hyb->get_idx() && hparams.indexer_kpool > 0` condition before `build_inp_kpool`. The resulting MTP dense graph registers **no unused pool setters**; a positive-ratio MTP still executes the original QSA input construction and cache alignment assertion. Do **not** change original GGUF metadata, trunk QSA, PLE16, MTP drafting parameters or generic scheduler to work around the assertion.

This is strictly **compatibility**, not a TG/PP optimization. r4's separate `LLAMA_MTP_SKIP_DENSE_INDEXER` later removes unused indexer storage/update overhead and is **not included here**. Draft indexer KV allocation can still appear in log.

## Next Windows gate (after isolated build)

1. Check out `investigation/r5-mtp-dense-compat-20261011` from the r5 pinned base, preserving local unrelated work; confirm clean status.
2. Rebuild ROCm (prefer an explicitly **new** build directory if the currently validated b11543 binary should remain untouched), or carefully rebuild the already configured build dir and record source/binary identity. At minimum verify the new `llama-cli.exe` SHA differs from `cd6aab33...`.
3. Repeat **same 32k allocation short prompt**, same self-contained Q8_0 draft, `DraftMax=2`, `DraftPMin=0`, f16 K/V and diagnostic environment cleared, with `-NoThrowOnFailure`. Success requires exit 0, generated tokens and actual draft acceptance. An assertion at a new location or model incompatibility remains a failure, not a partial pass.
4. After success, run same-binary MTP OFF/ON 32k deterministic/rollback, then 64k paired real prompts (fixed token budget + seed) and 128k if clean, recording PP, TG, acceptance, total and executable SHA. **Do not merge candidate as validated until Windows gate passes**.
