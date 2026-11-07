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