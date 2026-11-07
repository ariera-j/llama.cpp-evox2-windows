# Gate MOE-TOPK-2 — 16k / 32k MoE Expert routing re-sample (2026-11-07)

**計画作成済み、実行前。** 前回の [MOE-TOPK-1](R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md) はb12156実機でsmoke + 64k code/literatureが全PASSした。今回は**既存の同一ビルド/入力/Modelを維持し、新しいUBatch位置だけ**を変更する。ソース変更・再ビルド・RGP取得不要。

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
