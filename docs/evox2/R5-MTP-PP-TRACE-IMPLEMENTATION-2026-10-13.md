# r5 MTP PP phase tracing — implementation and Windows validation gate (2026-10-13)

**State: implementation only, Windows Vulkan/ROCm build and real model execution NOT YET VERIFIED.** Source branch: [`investigation/r5-mtp-pp-trace-20261013`](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/investigation/r5-mtp-pp-trace-20261013) branched from **exact compatibility-only `f8d24494fcacee01f8c9858595c3e778a1698d11`**. No DENSE-001, NOOP-001 or r2 MTP-QSA implementation was ported. Pinned stable r5 continues to hold the [approved research plan](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/r5/upstream-refresh-20261009/docs/evox2/R5-MTP-PP-INVESTIGATION-PLAN-2026-10-13.md).

## Scope of this diagnostic implementation

- `common/mtp-pp-trace.h`: **disabled unless `LLAMA_MTP_PP_TRACE=bins|1|detail`**; `bins` retains five KV-depth interval counters for prompt/generation/mixed phases and logs them when the recorder is destroyed. `detail` also keeps one per-ubatch row in memory and flushes it at orderly teardown. No extra GPU sync, source patch or sampling/attention policy change.
- `tools/server/server-context.cpp::decode`: use the server's **actual `is_prompt` bit** to classify each batch, including final short prompt ubatches. Measure **target submit/yield wall**, nested existing explicit target synchronization wall, the speculative process wrapper, and their enclosing total. The server's `metrics_post_decode` runs between target/spec scopes, and reported server prompt wall can exclude MTP work after the final prompt timestamp. **Do not add child durations to parents.**
- `common/speculative.cpp::common_speculative_impl_draft_mtp::process`: instrument the non-shared draft's full catch-up wall, **synchronizing target hidden getter** `llama_get_embeddings_nextn`, shifted-token/hidden batch construction, `llama_process(ctx_dft)` call(s), and verified hidden-row lookup/copy. Each event has explicit phase (forwarded in `common_speculative_process(..., trace_phase)`), processed token count and final logical token position. Other speculative implementations retain their default behavior.
- **Important backend caveat:** `llama_process(ctx_dft)` CPU wall may reflect asynchronous GPU submission, and hidden getter wall can include earlier queued target GPU work; these fields are **not actual per-kernel completion time**. `verify_copy_us` includes `_ith` getters (and possible synchronization), vector resizing and `memcpy`, not only memory bandwidth.
- `tools/evox2/benchmark/summarize_mtp_pp_trace.py`: parses native stderr into `mtp-pp-bins.csv`, `mtp-pp-rows.csv` (detail), and `mtp-pp-summary.json`. It verifies bin/detail counts and timing sums; missing/aborted records fail instead of becoming misleading zeros. CSV is **one inference process per analysis**.
- `tools/evox2/benchmark/configs/qwen38-r5-mtp-pp-trace-64k.psd1`: separate **short** OFF/ON diagnostic smoke and **64k** OFF/ON real-input collection, temperature 0/seed1234, 512 output, b2048/ub1024, f16 target/draft K/V, Vulkan union explicitly ON threshold32768. Output is **diagnostic timing, not performance ABBA**. Inherited `LLAMA_MTP_DIAG`, DENSE/NOOP, other QSA-prototype and Vulkan profiler switches explicitly cleared.
- This instrumentation **does not yet identify exact FA shader/kernel dispatch**. For draft dense-FA versus fallback, first use backend's selected operation/graph logging or a separate profiler trace. `GGML_VK_QSA_UNION=1` + “qsa-union active” proves neither draft FA nor draft sparse selection. Do not label a long `draft_us` window “FA GPU time”.

## Source / diagnostics compatibility warning

The r4 source instrumentation `ggml/src/ggml-mtp-diag.h` was **not** in compatibility-only r5; `LLAMA_MTP_DIAG=wall` alone will not produce its old JSON/CSV. This branch contains a new, narrower `LLAMA_MTP_PP_TRACE` diagnostic. Use the new plan; do not re-run `qwen38-r4-mtp-diagnostics.psd1` as if it were an r5 plan.

The original r5 b11560 MTP OFF/ON 64k/128k ABBA is already validated and should remain the **unprofiled speed control**: Vulkan 64k 361.520→333.995, 128k 335.455→303.965 PP tok/s; ROCm 64k 392.295→365.390, 128k 294.710→274.465. Rebuilds of this branch acquire a **new** executable/runtime SHA even with tracing OFF; do not label them b11560.

## Windows Evo-X2 gate A: source tests, then separate Vulkan build

From a **new checkout/worktree** of this experiment branch (avoid overwriting old measured b11560, DENSE or NOOP binaries):

```powershell
git fetch origin
git switch --track origin/investigation/r5-mtp-pp-trace-20261013

python -m unittest discover -s .\tools\evox2\tests -p 'test_mtp_pp_trace.py' -v

.\tools\evox2\build\Build-Vulkan.ps1 `
  -BuildDir .\build-vulkan-mtp-pp-trace `
  -VulkanSdk C:\VulkanSDK\1.4.357.0 `
  -LlvmBin 'C:\Program Files\LLVM\bin' `
  -Parallel 4
```

**The sample uses ```powershell** and then replace placeholder ` with real PowerShell backticks (line continuation); full ready-to-paste single-line build command is shown below:

```powershell
.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-mtp-pp-trace -VulkanSdk C:\VulkanSDK\1.4.357.0 -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4
```

The current branch has no Windows build validation yet. Check compiler errors before attempting any long run. After a successful build check `llama-cli.exe --version` and `evox2-build.json`, source commit and executable/DLL digest (do not assume the build wrapper's default path matches the new build).

## Windows gate B: short OFF/ON and 64k OFF/ON

In ignored `tools/evox2/benchmark/local.psd1`, point **`R5Common001Vulkan`** at the newly compiled `build-vulkan-mtp-pp-trace\bin\Release\llama-cli.exe`, **not** at the b11560 or any prior r5 binary. Verify the target `UnslothPle16` and `UnslothMtp` path keys, input-key `64k` and resource logging. The checked-in PSD1's build key is a local-config lookup key, **not** a built-in guarantee that this new binary was chosen. The runner must report a verified runtime artifact and the expected new executable commit.

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r5-mtp-pp-trace-64k.psd1'

# Verify job/variants/paths, without running the model.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# Fast smoke: OFF/ON with new trace, shorter output.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob vulkan-short -StopOnError

# ONLY after smoke and trace sidecar parsing pass: real 61,789-token input.
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyJob vulkan-64k -StopOnError
```

Example of parsing one successful **MTP ON detail** run (replace with the actual native stderr path shown by the runner):

```powershell
python .\tools\evox2\benchmark\summarize_mtp_pp_trace.py `
  --log 'C:\path\to\on-detail\stderr.log' `
  --outdir 'C:\path\to\on-detail\mtp-pp-analysis' `
  --require-prompt-draft --require-detail
```

For an exact copy-paste one-line version:

```powershell
python .\tools\evox2\benchmark\summarize_mtp_pp_trace.py --log 'C:\path\to\on-detail\stderr.log' --outdir 'C:\path\to\on-detail\mtp-pp-analysis' --require-prompt-draft --require-detail
```

For the OFF run omit `--require-prompt-draft`. Confirm: (1) summary records from **both** server target and non-shared draft on ON; (2) the prompt-binned token totals agree between target and draft for 64k; (3) CSV detail rows plotted with `end_pos` on X, `draft_us_per_token` on Y; (4) late prompt batch/first generation classification is sensible; (5) normal output/acceptance and error status remain credible. Detail timings are biased by timer and buffering overhead. **Do not report speed gains/losses from these diagnostic runs.**

## Initial evaluation and stop gates

1. Establish prompt/generation tagging and the **wall-accounting boundary**. Example: server `spec_us` encloses draft `total_us` (plus queue work); server `target_sync_us` is a subset of `target_us`. `hidden_get_us` may cover outstanding target work, so the components cannot simply be summed into a putative GPU time.
2. Plot per-ubatch `draft_us_per_token` vs KV end position and compare with `hidden_get_us / n_tokens`. If the draft portion grows strongly with KV, **independently** check actual f16 FA shader dispatch and GPU operator time before attributing growth to dense attention. If hidden getter dominates, investigate synchronization and device/host handoff instead.
3. Existing ResourceMonitor GPU Local/Dedicated/Shared + system committed checks for UMA budget pressure. Do not infer GTT paging solely from those counters.
4. If a 64k test fails correctness or trace completeness, **stop and fix the diagnostic** before 128k; do not attempt KV-only query pruning, inferred-ratio QSA, or DENSE/NOOP ports. If it passes, extend the same instrumentation/config to **128k and ROCm** in a later measured milestone; 256k remains optional.

All diagnostic source files and scripts are **experiment-branch only**. Sync this finalized report and measured evidence to canonical r5 docs **after** actual Windows validation; do not merge the experimental source into stable r5 merely to record it.
