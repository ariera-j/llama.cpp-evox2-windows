# r6 QSA Indexer score/top-k diagnostic design (2026-11-06)

**状態: 実装を調査ブランチに追加済み。ソースコードレビューとPythonテストfixtureを追加。Windowsビルド・GPU smoke・64k計測は未実施。** 実装先は調査ブランチ `investigation/r6-pp-fa-mask-rgp-20261105` またはその子ブランチ。production `main` は変更しない。

## 目的と既存実測

| corpus | KV列 | F16で確認した選択パターン (Query48640–48703) |
|---|---|---|
| コード | 28 | Key1816–1819: 55/64 Query、単一4-Key group |
| コード | 41 | Key2624–2627: 46/64 Query、単一group。46 QueryはすべてKV28も選択 |
| コード | 93 | 30/64 Query、9種類の4-Key group |
| コード | 470 | 29/64 Query、9種類の4-Key group |
| 文学 | 470 | Key30084–30087: 13/64 Query |
| 文学 | 472 | Key30244–30247: 22/64 Query（Query48666–48678の13連続を含む） |
| 文学 | 93 | 4/64 Queryが対象列を選択 |

問い: 単一groupの反復選択は常に高スコア・高順位なのか、それともtop-k境界付近の繰り返し選択か。複数group選択の領域では、スコアの高いpoolが近接しているか。これは **Indexerのスコアと実際のtop-k選択の調査**であり、最終Attention重みは測れない。

基準条件: EVO-X2 AMD Radeon 8060S、Vulkan、Unsloth IQ3_XXS PLE16、Performance P-MODE/UMA96GB、context65536、prompt head61777、batch2048/UBatch1024、F16 KV、no warmup、MTP OFF、QSA UNION OFF、gather OFF。対象 `Qcur-19` / layer il19 / KV49152 / N1024。Query global48640..48703は local512..575（UBatch開始48128）。実行時に `il`, tensor名, KV, Query global position をすべて照合し、形状だけの一致では採取しない。

## 現行ソースでのデータ流れ

- `src/models/qwen4exp.cpp::build_qsa_sel` で `ggml_lightning_indexer(q,pooled,weights,pool_mask)` -> **F32 score [n_pool,n_tokens]**、cb名 `indexer_score-<il>`。重みは `1/sqrt(idx_dim)`、headごとのrectified scoreを加算。これはAttention softmax scoreではない。
- `ggml_top_k(score,n_top_pool)` -> **I32 pool index [n_top_pool,n_tokens]**、cb名 `indexer_top_k-<il>`。**返却順は順位順ではない**。 `n_top_pool=min(n_pool,indexer_top_k/kpool)`。model GGUFの `indexer_top_k`, `dsv4_compress_ratios` を記録。
- `src/llama-memory-hybrid-idx.cpp::set_input_kpool`: host入力 `pool_idxs` はI32 `[kpool,n_pool]`、各要素は **KV cache cell番号**またはsentinel `n_kv` であり、必ずしも文書の絶対トークン位置ではない。sequence順の cell -> 論理Key位置を同一UBatchから別途保存。 `pool_mask` により不可視候補は `-inf`。top-k後にmember kpool個を展開し、未完成tail(`kpool-1`以下)を追加。**tailとpadding候補を通常のtop-k poolと混同しない**。
- `llama_context::graph_get_cb()` は名前を `%s-%d` 形式に設定。Vulkan backendに `GGML_OP_LIGHTNING_INDEXER` と `GGML_OP_TOP_K` の別dispatchが存在する。

## 推奨: 全pool × 64 QueryだけをそのままGPUから保存

**64 Query × n_poolのF32 scores + 64 Query × n_top_poolのI32 top-k + host pool->Key位置マップ**を、ちょうど1 layer、1 KV時点だけ保存する。これなら全Queryを比較しつつ、候補プールの再スコア計算や新shaderが不要で、選ばれなかった候補も含め正確な順位区間をCPU側で計算可能。

参考寸法: kpool=4、49152入力token、完成pool12288、実装のpad `max(64,PAD(n_pool_real+1,64))` により `n_pool=12352` が予想される。このとき64 Queryのscoreは **3,162,112 bytes（約3.02 MiB）**。全1024 Queryでは約50.6 MiBとなるため禁止。実際のGGUFからkpoolとn_top_poolを取得し、この見積は必ず実機メタデータで照合する。

### 取得箇所の候補

1. `ggml-vulkan.cpp::ggml_vk_lightning_indexer` の **score出力直後**と `ggml_vk_topk` の **I32 index出力直後**。両テンソルの名前・実際のstride・dtype・device、対象UBatch/KV/layerを検査。対象64 Query連続行だけdevice-to-device copyで上書きされない専用バッファに保存し、既存のbackend同期後にCPU読み出し。barrierとソース寿命を厳密に確認。既存FA mask snapshot方式を参考にする。
2. Graph/UBatch側から `KV, N, layer, global Query position, sequence id` を明示的に渡す契約を定義する。Vulkan backendの `n_pool` や名前だけでKVを推定しない。score/topk/pool_idxsは同じUBatch実行でなければ拒否。
3. `pool_idxs` はhost側で保持される入力。hostのpool layout（sequence ID、logical Key positions、KV cell IDs、real/padded/sentinel）を同時採取する。単一sequenceでpool index = key/4になっても、その式を前提としない。
4. 全データが揃ったら **一回だけ**prefix付きファイルへ出力。以前のmask binary /F16 cropは絶対上書きしない。Vulkan以外、形状不一致、dtype不一致、対象なし、既存ファイルがある場合は明示的にrejected。
5. 万一 backend dispatch-hook が安全に組めなければ、diagnostic専用graphの `view/cont` でscore一部を保持する代替設計を別Gateで評価する。汎用 `ggml_backend_sched_set_eval_callback` は `ggml-backend.cpp` の実装でsplit毎のGPU同期を生み、計測中のGPU実行を大きく変えるため第一候補にしない。

### 環境変数案（**まだ存在しない**）

```powershell
GGML_VK_INDEXER_DIAG=1
GGML_VK_INDEXER_DIAG_KV=49152
GGML_VK_INDEXER_DIAG_LAYER=19
GGML_VK_INDEXER_DIAG_Q_START=512
GGML_VK_INDEXER_DIAG_Q_COUNT=64
GGML_VK_INDEXER_DIAG_FILE=C:\llama-build\evox2-ppdiag-indexer\idx-code-kv49152-il19
```

デフォルトは完全OFF。対象を採取した時だけ少量のsnapshot bufferを確保し、複数候補が一致する場合も最初の1回だけ保存。ファイル名にはcorpus/build/target/試行IDを含め、既存を拒否。

## 診断ファイル v1

- `<prefix>-meta.json`: format version、実行設定、source SHA、model/build SHA、layer/Q位置/KV、n_tokens、kpool、budget、n_pool_real/padded、n_top_pool、Tensor type/stride、source/capture status、pool可視性、buffer寸法。
- `<prefix>-score.f32`: Query 64行 × pool n_pool列、little-endian F32。見えないpoolの `-inf` を含む。
- `<prefix>-topk.i32`: Query 64行 × n_top_pool列、little-endian I32 **unordered pool index**。
- `<prefix>-pool-map.csv`（または小さなbinary+json）: pool id、kpool各memberのKV cell、元の絶対Key token位置、sequence ID、real/pad/sentinel。
- offline `per-query.csv`, `per-group.csv`、score/cutoff図。raw/binary/ZIPは実験リポジトリにcommitせず、集計だけ記録する。

## CPU側分析: score / rank / cutoff

各Query qで:
1. `score[q,p]` が有限の可視poolのみ候補にする。 `-inf` padded/invisibleは選択候補から除外する。
2. 実`topk[q]`で選ばれたpoolを確定。異常index、重複、不可視poolを検査。 `-inf` のpaddingがtopkの空き枠を埋めた場合にはlive選択扱いしない。
3. 有効候補数 `n_valid >= n_top_pool` なら `cutoff = min(score[q,p] for actual selected visible p)`。topk配列末尾はcutoffではない。不足している場合 `cutoff=NA (underfilled)`。
4. 候補poolの順位区間を `rank_best = 1 + count(visible score > score[p])`、`rank_worst = count(visible score >= score[p])` として計算。ゼロに丸められたscore等で同点があると順位は一意ではない。`selected`は実topk indexが唯一の根拠。`margin = score[p]-cutoff`はcutoffが定義できる時だけ算出。
5. score→topk→pool-map→Key位置を使い、元のF16 mask（0/-inf）と**要素単位で照合**。Tailと不可視paddingを区別し、コードKV28/41/93/470、文学KV28/93/470/472の既存4x4 raw cropを比較する。2-bit CLASSのみの照合では不足。

重点Key group（開始token位置）:
- コード: 1816、2624、5964、5968、5980、5984、6004、30084、30088、30092、30096、30104
- 文学: 5960、30084、30244（ほかKV93/472で検出したgroup）
- 全Query48640..48703について選択率、score分布、中央値rank interval、cutoff margin、selected/unselected/tiesの特徴を出す。同じ絶対位置でも文学とコードでは内容が違うため「同じKeyを参照した」と解釈しない。

## Gateと停止条件

- **Gate0（現在）** ソース/モデルメタデータ/対象layer/UBatch位置合わせ、readback設計レビュー。**本ファイルのみ**。実装・native計測なし。
- **Gate1** 調査ブランチでopt-in実装、padding/ties/sentinel/stride/buffer size/再書込拒否/UBatch誤一致の単体テスト、Build。
- **Gate2** 1024 token smoke（target KVを1024に変更）、raw F32/I32/metadata/pool map整合、pool->mask再構成を確認。pool予算未充足ならcutoff NA許容。
- **Gate3** code 64k 1回、対象Qcur19/KV49152一致と既存mask F16に一致することを確認。TDR/OOM/DeviceLostがあれば停止。
- **Gate4** literature 64k 1回、同条件。順位・score・cutoffとの比較を `evox2-llm-experiments` に記録。

診断ONのPP tok/sを通常性能データとして使用しない。0x141 TDR、OOM、過大バッファ、score/topk/pool-map不一致、F16再構成不一致、保存先既存があれば停止。

## 次段で分かること / 分からないこと

- c28/c41がほぼ全Queryで上位ランクに入る→広く高く評価されるIndexer表現の可能性。
- cutoff付近で同点が多い→topk budgetやtieによって繰り返し選択が起きる可能性。
- c93/c470の近接groupが同時に高得点→領域全体が関連poolとして評価される可能性。
- **どの結果でもAttention sink・最終Attention重み・性能差の因果性は証明できない**。必要なら後で別の測定設計を行う。


## 2026-11-06 実装追記 (Gate1 source prepared, native test pending)

- **Source:** `src/models/qwen4exp.cpp` tags QSA score/topk tensors with precise layer/KV/Q-first/N; `ggml/src/ggml-vulkan/ggml-vulkan.cpp` saves an original 64-Query F32 score slice and unordered I32 top-k slice after each corresponding kernel with bounded device copies, releasing only after regular fence; `ggml/src/ggml-vulkan/ggml-vulkan-types.h` holds snapshot ownership; `src/llama-memory-hybrid-idx.cpp` emits exact same UBatch's pool->KV cell->logical Key map, rejecting existing output files. Defaults OFF.
- **Decoder:** `tools/evox2/benchmark/analyze_indexer_diag.py` computes rank intervals, cutoff and selected pool sets, optionally element-wise checks previous raw F16 crops.
- **Plans:** `qwen38-r6-indexer-score-1024-smoke-20261106.psd1` and `qwen38-r6-indexer-score-64k-20261106.psd1` (use separately for code and literature).
- **Unit fixtures:** `tools/evox2/tests/test_r6_indexer_diag.py`: score/topk unordered, ties, missing visible candidates, bad IDs, F16 correspondence, static opt-in bounds.
- **Runbook:** [R6-QSA-INDEXER-SCORE-TOPK-RUNBOOK-2026-11-06.md](R6-QSA-INDEXER-SCORE-TOPK-RUNBOOK-2026-11-06.md).
- **Important:** Native Windows compilation and a real Vulkan graph's tensor strides, event barriers, and pool-map alignment remain UNVERIFIED. Execute and inspect Gate1 unittest/build + Gate2 smoke before any 64k work; do not infer PASS from source inspection. No clean tok/s should be taken from this instrumentation.

## Source references

- [QSA score, top-k, mask expansion](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/src/models/qwen4exp.cpp#L845-L1031)
- [Pool layout and per-Query visibility](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/src/llama-memory-hybrid-idx.cpp#L762-L1007)
- [Vulkan lightning indexer dispatch](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L11069-L11138)
- [Vulkan top-k dispatch](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L12225-L12322)
- [Vulkan original F16 mask capture precedent](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/docs/evox2/R6-PP-FA-MASK-MIXED-RAW-CROP-2026-11-06.md)
- [Generic callback GPU sync tradeoff](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r6-pp-fa-mask-rgp-20261105/ggml/src/ggml-backend.cpp#L1899-L1930)
- [Experiment summaries](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/RESULTS.md)
