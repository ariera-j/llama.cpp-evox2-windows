# Gate MOE-TOPK-2 — 16k / 32k MoE Expert routing re-sample (2026-11-07)

**実機検証PASS（2026-11-07）：4run追加を正常終了。詳細は本書末尾の結果参照。** 前回の [MOE-TOPK-1](R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md) はb12156実機でsmoke + 64k code/literatureが全PASSした。今回は**既存の同一ビルド/入力/Modelを維持し、新しいUBatch位置だけ**を変更する。ソース変更・再ビルド・RGP取得不要。

## 目的と最小マトリクス

現在の観察点はUBatch47（0始まり48番目、N1024, KV49152）。そこから時間軸を広げ、選択分布の変化が一時的かを検証する。

| 0-based UBatch index | N1024の処理終了に対応するKV長 | コード | 文学 | 備考 |
|---:|---:|---|---|---|
| 15 | **16384 (16k)** | 新規 | 新規 | 前半 |
| 31 | **32768 (32k)** | 新規 | 新規 | 中盤 |
| 47 | **49152 (48k)** | **既存データを再利用** | **既存データを再利用** | 後半 |

対象layerはそれぞれ**19/23**、総12の局所選択分布テーブル（3位置×2入力×2layer）。追加するのは**4つの独立した64k PP実行**のみ（1回のrunで1 UBatchしか採らない現行callback仕様）。3つの位置はいずれも計算上のKV末端と対応するが、診断のUBatchカウント自身は直接KV状態を読んでいるわけではなく、ベンチ設定から対応づける。

### 変更しない条件

- b12156 `b82a76ca663b0b81e231211e6882ebac1b193dab`, `R6RocmMoeTopk`, Unsloth Ple16 IQ3_XXS, ROCm gfx1151 Radeon8060S, TheRock10.0.0
- `PromptTokens=61777`, `Context=65536`, `UBatch=1024`, `Batch=2048`, head of exactly the same files, NoWarmup=true, Repetitions1, K/V f16, GPU999, CpuMoe0, MTP OFF, Gather OFF, P-MODE Performance
- `GGML_EVOX2_MOE_TOPK_TRACE=1`, `GGML_EVOX2_MOE_TOPK_LAYERS=19,23`, `GGML_EVOX2_MOE_TOPK_RAW=1`; only `GGML_EVOX2_MOE_TOPK_UBATCH` is 15 or 31
- Original code input SHA256 `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`, literature SHA256 `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`

**計測制限：`cb_eval`はGPU同期待ち・graph分割を追加するため、`llama-bench`結果のtok/sや秒数を通常速度/入力差評価に使わない。RGP同時取得はしない。**

## 新しい計測プラン

[config](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-moe-topk-multi-ubatch-20261107.psd1)

- job `rocm-moe-topk-code-samples`: `moe-topk-code-u15`, `moe-topk-code-u31`
- job `rocm-moe-topk-literature-samples`: `moe-topk-literature-u15`, `moe-topk-literature-u31`
- **指定したvariantだけを実行**するか、Plan指定のみで4runを順次実行可能。先日3run一括が正常終了したので、今回も一括でも技術的に問題ない。ただし異常があればその時点で停止すること。

## 実行手順 (PowerShell)

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git status --short
git pull --ff-only

$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-moe-topk-multi-ubatch-20261107.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# UBatch 15 のコード・文学を先に対にする
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-code-u15 -StopOnError
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-literature-u15 -StopOnError

# UBatch 31 のコード・文学
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-code-u31 -StopOnError
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant moe-topk-literature-u31 -StopOnError
```

**PlanOnlyで4 variantを確認し、過去のsmokeやUBatch47を実行しないこと。** 既存 `local.psd1` のBuild key `R6RocmMoeTopk` は変更不要。プランを一括実行しても既存のトークン・モデル一致に問題はないが、結果のrun-directoryと入力・UBatchの関連をZIPの`conditions.json`から必ず照合する。

## 合格条件と比較内容

それぞれのrunで：
1. `Status=OK / ExitCode=0`、同じb12156 / input SHA / P-MODE Performance維持
2. 各runで**該当UBatchの2つのhistogram**（layer19と23）、かつRAWがONなら**1024×2トークン行**を取得
3. 各histは`tokens=1024`, `k=10`, `experts=512`, `assignments=10240`, `bad_ids=0`、各tokenに異なる10 Expert ID、histとRAW再計算の完全一致
4. b12156の同一条件でu15/u31/u47を比較する。**Layer 19のu47はJ32 tiles 566/566、Layer 23のu47は589(code)/568(lit)でコードが+21(+3.7%)**という既存結果を保持。

主要分析：
- `active`、Expert頻度のトップ10集中率、Shannon実効Expert数 `2^H`、最大選択数
- `active_tiles32 = Σ_e ceil(m_e/32)` を入力別、Layer別、KV位置別に整理。**同じlayerでも符号が変化するか？**
- RAW IDを使い、隣接トークン間Expert集合の重なり（10のうちの一致個数）、Top-k順位ごとのExpert分布
- 質量分布の `Σ min(count_code,count_lit)` と半L1距離。別文章の同一token位置の一致率は意味的に解釈しない
- 入力差が小さい位置/大きい位置を抽出し、今後MMQタイミングとの位置合わせ候補を決める

比較方法（各UBatchの2つの `stderr.log` をペアにして実行）：

```powershell
.\tools\evox2\benchmark\Compare-MoeTopkTrace.ps1 `
    -CodeStderr 'C:\PATH\CODE-U15\stderr.log' `
    -LiteratureStderr 'C:\PATH\LITERATURE-U15\stderr.log' `
    -OutCsv '.\moe-topk-u15-expert-counts.csv'
```

UBatch31も同様に実行。48k既存データ（2026-11-07 `de511770...`のcombined ZIP）は再計測しない。新runを終了後にZIPを共有してもらえば、3地点の比較テーブルとグラフ／原因候補の順位を更新できる。

## 制約

J32の`Σceil`はMoE MMQの**有効列タイル代理指標**で、GPUイベントを直接計時したデータではない。古いb12038 RGP Event91等のKV/layerが未対応であるため、J32差があってもGPU時間・PP全体に因果帰属しない。今回の目的は**Expert選択分布の位置変化を確認すること**まで。

## 2026-11-07 17:13 JST — Gate MOE-TOPK-2 completed (4 runs PASS)

**The combined 4run ZIP has been fully parsed; all four 64k runs PASS.** The first variant started 16:58:44 JST, and the last finished 17:13:49 JST, with non-overlapping serial execution. Same b12156/`b82a76ca6` binary SHA256 `68f7f8adc2bb8688b12525620c474e57ffbaea17c72bef215237a64d4ce63ebd`; `R6RocmMoeTopk`; exact original input SHA verified per run. P-MODE Performance preserved, GPU gfx1151 ROCm, Gather/MTP OFF; `Status=OK ExitCode=0` in each, `PossibleNoise=false`, no crash/reset indications.

- ZIP `20261107-171020-102-bench-rocm-b12156-ctx65536-ddcd7a30de72.zip`, **SHA256 `26cbcf3001e6ff8cbf4e0c4447ca38212e11c3224c61e7474b92a624d630af07`**, 422,808 bytes, 52 ZIP entries including four individual run folders.
- Code UBatch15 `20261107-165843-305-bench-rocm-b12156-ctx65536-075ad2221445`; code UBatch31 `20261107-170240-150-bench-rocm-b12156-ctx65536-c8364dc86642`.
- Literature UBatch15 `20261107-170630-225-bench-rocm-b12156-ctx65536-a7c1265ac3a8`; literature UBatch31 `20261107-171020-102-bench-rocm-b12156-ctx65536-ddcd7a30de72`.
- Each stderr contains two `evox2_moe_topk_hist_v1` rows (layer19/23) and **2048 raw `evox2_moe_topk_ids_v1` rows** (1024 per layer). All eight new histogram arrays were independently reconstructed from every token's top10 Expert IDs, all IDs unique and in [0,511], no missing tokens, bad_ids0. All eight `Σceil(m_e/32)` counts agree.

### J32 tile comparison, 16k/32k plus existing 48k

| KV / UBatch (0-based) | Layer | Code | Literature | Code−Literature |
|---|---:|---:|---:|---:|
| 16384 /15 | 19 | 560 | 565 | −5 |
| 32768 /31 | 19 | 592 | 549 | **+43** |
| 49152 /47 (from previous Gate) | 19 | 566 | 566 | 0 |
| 16384 /15 | 23 | 556 | 572 | **−16** |
| 32768 /31 | 23 | 572 | 573 | −1 |
| 49152 /47 (from previous Gate) | 23 | 589 | 568 | **+21** |

At Layer19 code active Expert counts for 16k/32k/48k = 351/392/348 vs literature341/321/357; at Layer23 code345/380/394 vs literature339/352/348. The sign of J32 tile difference varies with KV and layer; **expert selection distribution is input/position dependent, not invariably code-heavy**.

**Adjacent token sets share (out of 10) at Layer23:** code 2.541,2.243,2.695 vs literature4.949,4.472,4.254 (KV16k/32k/48k). At Layer19: code2.762,3.057,4.467 vs literature4.740,4.768,4.302. Literature reuses Expert identity between adjacent tokens more than code in five of six comparisons, but Layer19 at48k reverses; this is a document-specific spatial observation, not a universal literature-vs-code claim.

Top10 Expert share code/lit: Layer19 16k26.71/37.11%, 32k23.73/36.55%, 48k38.34/31.82%; Layer23 16k31.93/39.69%, 32k23.87/37.59%, 48k23.78/29.72%. Intra-document histogram *mass* reuse u15→u31: literature70–71%, code47–55%, again not tokenwise exact agreement.

**Gate verdict:** MOE-TOPK-2 PASS with 12 source-validated spatial snapshots (8 new + 4 prior). No need to repeat 4run. **Speed from callback-on runs is not comparable** because this adds GPU sync/graph splits. This evidence doesn't assign HIP RGP Event91/465 to the same layer/KV or prove that the extra tiles cause a particular GPU-time/PP delay.

[Full comparison report and 12-row CSV](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/runs/2026-11-07-rocm-moe-expert-topk-multi-ubatch-16k32k48k.md).
