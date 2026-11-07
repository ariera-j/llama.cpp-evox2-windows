# Gate MOE-TOPK-1 — ROCm 64k MoE Expert選択分布 (2026-11-07)

**状態：コード・計測プラン・集計スクリプトを実装。実機ビルドと実行は未検証。**

対象ブランチ：investigation/r6-rocm-moe-topk-diag-20261107。既存HIP FA診断から分岐し、llama-bench.cppのみを変更。GPUカーネルやllama-cli/serverは変更していない。

## 既存HIP RGPからの確定事項

同じb12038 Dispatch range 181200/count512のコード/文学RGPには、Event 85 topk_moe_cuda → 87 mm_ids_helper<10> → 89 quantize_mmq_q8 → 91 mul_mat_q (IQ2_S)、同様に93→95→97、101→103→105 (IQ4_NL)が現れる。別グループも459→461→463→465等を反復。これにより表示された重いMMQのMoE経路を確認。helper<10>は10 Expert/Tokenを意味する。

## 取得内容とコスト

環境変数 GGML_EVOX2_MOE_TOPK_TRACE=1 のときだけ、既存llama_context_params.cb_evalを利用して名前 ffn_moe_topk-<layer> の selected_experts tensorを観察する。UBatch47・Layer19/23を初期対象に設定。

ggml_argsort_top_kは [k,n_tokens] の非連続VIEWなので、その親の連続 [n_experts,n_tokens] argsort配列を一度GPU→CPU転送し、各tokenで先頭k選択IDを取り出す。必要に応じて正しい2D strideによるフォールバックを使う。

stderr.logに evox2_moe_topk_hist_v1（expert別選択数、active expert数、J32処理タイルproxy Σceil(count_e/32)、不正ID数等）と、RAW=1時は evox2_moe_topk_ids_v1（token別10 Expert ID）を出す。原則1回の64k計測でLayer19/23の2件だけ取得する。

**重要：既存eval callbackはggml-backend.cpp内でグラフを分割しGPU同期を追加する。診断ONのPP時間・RGP GPU時間は元のベンチマークと比較禁止。RGPを同時取得しない。** 診断OFF時はこのcallback自体を接続しない。

UBatch47は0始まりの48番目。n_prompt61777、n_batch2048、n_ubatch1024、NoWarmup/1runで前回のFA host trace 565..576 (KV49152) と対応する条件。一般の実行についてKV49152をコールバックから直接計測しているわけではない。

## Windowsでのビルド

ソースルート C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag で次を実行する。git status --short で未追跡ファイルを削除しないこと。

    git fetch origin
    git switch -c investigation/r6-rocm-moe-topk-diag-20261107 --track origin/investigation/r6-rocm-moe-topk-diag-20261107
    & C:\TheRock\build\.venv\Scripts\Activate.ps1
    .\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-moe-topk-r6 -Parallel 4 -AmdGpuTarget gfx1151
    .\build-rocm-moe-topk-r6\bin\Release\llama-bench.exe --version

git-ignored tools/evox2/benchmark/configs/local.psd1 の既存Buildsキーに次を追加：

    R6RocmMoeTopk = @{ BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-moe-topk-r6\bin\Release'; ExpectedBackend = 'ROCm' }

## Smoke → 64k コード → 64k 文学

プラン: tools/evox2/benchmark/configs/qwen38-r6-rocm-moe-topk-64k-20261107.psd1

    $plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-moe-topk-64k-20261107.psd1'
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-smoke-code -StopOnError
    # SmokeがPASSした場合だけ、以下を別々に実行
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-code-64k -StopOnError
    .\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-literature-64k -StopOnError

Smokeは1024tokens/UBatch0/Layer19/RAW OFF。期待：Status OK、evox2_moe_topk_hist_v1が1件、k=10、tokens=1024、assignments=10240、bad_ids=0。64kではUBatch47とLayer19/23の各2件、RAW ONなら1024 token/Layerの選択ID行を保存。

## 照合コマンド

    .\tools\evox2\benchmark\Compare-MoeTopkTrace.ps1 -CodeStderr 'C:\PATH\CODE\stderr.log' -LiteratureStderr 'C:\PATH\LITERATURE\stderr.log' -OutCsv '.\moe-topk-expert-counts.csv'

CSVにはUBatch、Layer、Expert IDごとのコード/文学の選択数と差を記録。J32 active tile数が大きく違うなら実処理量の仮説を支持。差がほぼなければ、Expertアクセスの局所性・並び順・キャッシュ・クロック等をさらに検証する。いずれも単一UBatchの観察でありPP全体の数秒差を直接説明したことにはならない。

### 注意

- この診断はMoE top-kであり、Vulkanで解析したQSA Lightning Indexer top-kとは別のもの。
- 入力が違うため、同じtoken位置のExpert IDが違うことだけでは意味的な比較にならない。頻度、非空数、偏り、近傍連続性を比較する。
- b12038のRGP Event IDと新診断のLayer19/23は直接対応づけていない。トレースファイルをそのように命名しない。
- 出力のPP速度は有効なベンチマークではない。コードと文学のモデル・入力SHA256等はベンチZIPで検証する。

**このGateで終了後、ソース変更と計測の安全性を評価し、必要があればGPU内ヒストグラム版を別Gateで検討する。**

## 2026-11-07 16:10 JST — MOE-TOPK-1 first real device run PASS (3 sequential)

**Validated with user-supplied build manifest and combined ZIP.** The accidental use of the whole plan caused **three sequential, NON-OVERLAPPING runs**: 16:01:54–16:02:58 smoke; 16:03:20–16:06:51 code64k; 16:07:12–16:10:42 literature64k (JST). All `Status=OK / ExitCode=0 / NativeRowCount=1`, P-MODE Performance→Performance, `BackgroundActivitySummary.PossibleNoise=false`, no reported TDR/OOM. **No rerun required for routing data.**

- Build `(rocm-moe)evox2-build.json` sha256 `90753bb782f7b100b1088f662c5e0d70e08c502b7beee05a91bbedfed2b03fc5`; build number **12156**, branch `investigation/r6-rocm-moe-topk-diag-20261107`, source **`b82a76ca663b0b81e231211e6882ebac1b193dab`**; `BuildIdentity.Status=Verified`; ROCm10.0.0 (TheRock), gfx1151, Clang23. `Dirty=true` due exclusively to **four unrelated untracked legacy Vulkan mask plan PSD1**, no tracked-source edit. Same `llama-bench.exe` sha256 `68f7f8adc2bb8688b12525620c474e57ffbaea17c72bef215237a64d4ce63ebd` in all three runs.
- Combined ZIP `20261107-160711-663-bench-rocm-b12156-ctx65536-23f1e78b3ed8.zip` sha256 `de511770b92a48ab9788310f01fa272e26e55654abb6634044393f88a5203b56`, bytes 240308. It actually contains **3 independent run folders** (1 smoke, 2 full); do not treat name of outer ZIP as a single case. Exact per-run IDs:
  - Smoke code `20261107-160153-538-bench-rocm-b12156-ctx2048-c4189f4be6f9`; input SHA `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`; UBatch0, Layer19 only, `RAW=0`. **One** `evox2_moe_topk_hist_v1` record, 1024tokens, 512 experts, k10, 10240 assignments, 416 active experts, max count591, J32 effective tiles614, bad_ids0. Correct histogram checksums.
  - Code64k `20261107-160320-015-bench-rocm-b12156-ctx65536-923a3d6c27cd`; input SHA same original code; head61777, ctx65536, UBatch1024, no warmup, MTP/gather OFF. UBatch47 Layers19/23 with **two histograms and 2048 selected-token rows**.
  - Literature64k `20261107-160711-663-bench-rocm-b12156-ctx65536-23f1e78b3ed8`; input SHA `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`; identical configurations and selected UBatch/layers, **two histograms and 2048 selected-token rows**.
- All four 64k layer histogram sums and tile counts were **independently recomputed from the raw IDs** (1024 distinct 10-ID values per layer, all IDs in [0,511]) and match the log exactly. All four `bad_ids=0`. No duplicate raw-token IDs within a given top-k list and no skipped token indexes.

### Actual selection frequency data at UBatch47 (maps to the prior KV49152 schedule)

| Metric | Code layer19 | Literature layer19 | Code layer23 | Literature layer23 |
|---|---:|---:|---:|---:|
| `tokens × k` assignments | 10,240 | 10,240 | 10,240 | 10,240 |
| Distinct selected Experts (512 possible) | **348** | **357** | **394** | **348** |
| Max assignments to single Expert | **735** | **671** | **460** | **582** |
| `Σ_e ceil(m_e/32)` J32 effective tile proxy | **566** | **566** | **589** | **568** |
| Top-10 most used Experts: assignments/share | 3926 / 38.34% | 3258 / 31.82% | 2435 / 23.78% | 3043 / 29.72% |
| Average shared Expert IDs between **adjacent** tokens (two unordered size-10 sets) | 4.467 | 4.302 | **2.695** | **4.254** |
| Shannon effective selected Expert count `2^H` | 94.79 | 120.66 | 170.97 | 117.02 |

- Layer19: histogram **strongly differs** (frequency overlap sum(min counts)/10240 = **12.87%**, normalized histogram L1/2 = **87.13%**), yet the J32 active-tile count is **exactly identical: 566 vs566**. More concentrated code frequency (top10 38.34%) does not imply fewer actual J32 tiles. Expert-ID frequency differences alone do not explain a putative layer19 MMQ-time gap.
- Layer23: code chooses **46 more distinct Experts**, and **21 additional J32 live tiles** (+3.70%) than literature. It also has markedly lower adjacent-token shared selection (**2.70 vs4.25 / 10**), suggesting less local semantic/routing continuity in this UBatch; memory locality implications remain speculative since HIP MMQ uses Expert grouping. Histogram overlap **23.37%**, total variation 76.63%.
- The two inputs show almost entirely different top selected Expert IDs, but **same token index represents different text**; per-position identity matches are not an interpretable quality metric. No logits or loss data gathered.
- The **RGP b12038** 512-dispatch expensive-event rows are **not** verified to be the same layer/KV as this isolated **b12156** topk data. The `Σceil` proxy is neither GPU kernel time nor an exact executed-wave count; **do not claim the 21 tiles caused the historical 3.315ms local RGP gap or whole PP 2.259s difference**.
- Diagnostic-ON `avg_ts` code **393.957** vs literature **389.242** tok/s reverses historical no-callback PP direction. This comparison is **INVALID** because `cb_eval` synchronizes GPU and restructures graph execution, raw IDs are also written to stderr, and a new build is used. Do NOT use this result to refute the historical normal-PP tendency.

### Gate verdict and next research

**MOE-TOPK-1 PASS as a correct, bounded, host-observed GPU top-k readback.** Dataset contains exact selected Expert IDs, per-Expert counts, and tile-work proxies. Runtime overhead/instrumentation neutrality **not** validated and is deliberately excluded from claims.

Next decision: for studying *Expert selection* as an independent research topic, analyze 512-Expert frequency/adjacent-token continuity (and eventually several UBatch positions). For testing *the MMQ slowdown mechanism*, collect a bounded set of matched **kernel→layer/KV** GPU times on the same source revision, or first extend top-k capture to other layers and ubatch positions while retaining source SHA and masks. Do not write a GPU timing explanation solely from this one UBatch.

## Gate MOE-TOPK-2 — additional UBatch15/31 prepared (2026-11-07)

Following MOE-TOPK-1 PASS, [matched 16k/32k follow-up plan](R6-ROCM-MOE-TOPK-MULTI-UBATCH-2026-11-07.md) and [four-variant PSD1](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-moe-topk-multi-ubatch-20261107.psd1) were added on the *same branch*.

- Reuse **exactly b12156** / `R6RocmMoeTopk`; **no rebuild or additional smoke**.
- Add zero-based UBatch **15 (KV16384)** and **31 (KV32768)**, code and literature each, layers19/23, 4 independent runs. The already-complete UBatch47 (KV49152) pair is reused, not rerun.
- Same original head61777 token inputs, ctx65536/UBatch1024/B2048, noWarmup, F16 KV, QSA Gather/MTP OFF, P-MODE Performance.
- Compare using the existing `Compare-MoeTopkTrace.ps1`, then analyze Expert frequency concentration, entropy, adjacent-token overlap and `Σceil(m_e/32)` by KV and layer. **Do not use callback PP time for performance**, and do not infer RGP event-to-layer identity without a separate alignment Gate.
- User can run one `-OnlyVariant` at a time in pairs or all 4 sequentially. `-PlanOnly` before execution verifies the intended 4 cases.
