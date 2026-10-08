# VULKAN-002: QSA grouped-union 診断機能（試験実装）

更新日: 2026-10-08

## 位置づけ・状態

- ブランチ: `investigation/vulkan-qsa-union-stats-20261008`
- 起点: `investigation/llama-bench-real-prompt-20261007`（`e3466e8fa769928140f81c93c84889860732ff82`）
- 実文書入力オプション `-f`, `--prompt-slice`, `-c` は汎用計測機能として維持する。
- union統計はVULKAN-002の**診断用付属機能**。本線r4やr5には**未移植**。
- **Windows / Evo-X2 での実ビルド・GPU実行は未検証**。マージ前に下記チェックが必要。

## 目的

- 64k/256kの「実文書 llama-bench は CLI と同程度、random-token llama-bench は低下」の内部要因を調べる。
- 繰り返しあり日本語文書、繰り返しなし日本語文書、本、英語文書、ソースコード、random tokenのQSA union効率を比較する。
- 長文コンテキストにおけるVULKAN-002の閾値・gather/FA最適化の判断材料を集める。

## 設定

```powershell
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_STATS = '1'
$env:GGML_VK_QSA_UNION_STATS_KV_BIN = '16384'
```

| 環境変数 | デフォルト | 用途 |
| --- | --- | --- |
| `GGML_VK_QSA_UNION` | 従来どおりOFF | VULKAN-002本体。有効化しないと統計対象なし |
| `GGML_VK_QSA_UNION_STATS` | OFF | **明示的に1の場合のみ**診断処理を追加 |
| `GGML_VK_QSA_UNION_STATS_KV_BIN` | `16384` | KV長を集計する区間幅。1024～262144の2の累乗のみ |
| `GGML_VK_QSA_UNION_STATS_FILE` | `qsa-union-stats.csv` | CSV出力先。通常はプロセスの作業ディレクトリ基準 |

`Measure-LlamaBench.ps1`を使い、STATS=1かつ`STATS_FILE`未指定の場合は、各runディレクトリに`qsa-union-stats.csv`を自動設定する。指定済みのパスは上書きしない。実験条件とresult.jsonにもCSVパスを残す。

### 出力CSV

列:

```text
sync,kv_bin_start,kv_bin_end,groups,unique_mean,unique_min,unique_max,padded_mean,padded_min,padded_max,selected_mean,unique_over_selected,padded_over_selected,dropped_groups
```

- `sync`: そのVulkan backend contextにおける統計flush番号（0始まり）。
- `kv_bin_start/end`: `n_kv`の半開区間 [start,end)。既定は16k幅。
- `groups`: 対象区間で計測した64-query groupの件数。末尾の短いgroupも含む。
- `unique_mean/min/max`: 重複除去後の**正確なunion count**（shaderの`data_count[1]`）。
- `padded_mean/min/max`: 256単位に丸めた**FAで使う長さ**（`data_count[0]`）。
- `selected_mean`: 入力の候補slot数（`data_count[2]=n_batch*n_top`）。無効indexもslot数には含む。
- `unique_over_selected`: `sum(unique)/sum(selected)`。小さいほどgroup間の候補重複が大きい可能性がある。
- `padded_over_selected`: `sum(padded)/sum(selected)`。paddedは最小256となる。
- `dropped_groups`: 同期区間で65536記録のbuffer上限を超え、記録されなかったgroup件数。この値が0でなければその区間は**不完全な測定**。

CSVの各行は**backend同期間の区間ごとの集約**であり、全runの1区間1行ではない。ランごとの代表値には各binの`groups`を重みとした加重平均を使うこと。warmupとtimed repetitionsの両方を含むため、**診断CSVからtimed-only PPを再現してはいけない**。本診断はレイヤー別の分解をまだ行わない。

### 収集方式と計測オーバーヘッド

1. 既存`qsa_union.comp`は変更しない。各groupのGPU上の4カウントを使用。
2. STATS=1の場合だけ、union shader完了後に16 byte/groupを専用のdevice bufferへGPU→GPUコピー。
3. Vulkan backend同期でGPU完了を待ってから、蓄積したデータを**一括readback**。
4. CPU側でKV区間ごとに集計し、CSVへappend。
5. STATS=0の場合、専用bufferの作成・転送・readback・CSV書き込みを行わない。

統計バッファはbackend contextごとに65536 group分（約1 MiB）を上限に固定する。同期ごとに読んで再利用する。buffer overflowは`dropped_groups`とstderrに記録する。

ただしSTATS=1のPP値は、GPUコピーや追加barrier、readback、CSV書き込みを含み、通常のPP性能の指標には使わない。**性能測定はSTATS=0、union効率の比較はSTATS=1**で分離する。

## Evo-X2での最初の動作確認

PowerShellから、次の3変数を同じターミナルで設定（既存のVulkan実測条件を維持）。

```powershell
$env:GGML_VK_MOE_LEGACY_TILE_SELECTION = '1'
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_GET_ROWS_128X4 = '0'
$env:GGML_VK_QSA_UNION_STATS = '1'
$env:GGML_VK_QSA_UNION_STATS_KV_BIN = '16384'
```

ビルド後、`configs/local.psd1`の`R4QsaUnionVulkan`が**このブランチの新build**を参照することを確認する。既存b11427では診断機能は使えない。

まず単回測定、warmupなしで64k realを試す:

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R4QsaUnionVulkan `
  -ModelKey UnslothPle16 `
  -InputFile "C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\long-input-abstract-out\nlp-survey-ch3-d31-b1.txt" `
  -PromptSlice head-tail `
  -Context 65536 `
  -PromptTokens 61789 `
  -GenerationTokens 0 `
  -Depths 0 `
  -Repetitions 1 `
  -NoWarmup `
  -KvType f16 `
  -Batch 2048 `
  -UBatch 1024 `
  -Threads 4 `
  -GpuLayers 999 `
  -CpuMoe 0 `
  -FlashAttn auto
```

random対照では`-InputFile`と`-PromptSlice`を削除し、他を同じにする。

### 検証チェック

- OFFでは既存b11427と同じ推論結果・性能帯を再現するか。
- ONで`qsa-union active (r4)`が出てCSVも生成されるか。
- `unique <= selected`、`unique <= padded <= capacity`、`groups > 0`、`dropped_groups = 0`か。
- `kv_bin_start`が`16384`の倍数になり、64k付近で対応するbinへ入るか。
- real/randomのunique・padded平均がどの程度違うか。ただし性能差のすべてをunion率だけに帰属しない。
- 64kで妥当性確認後、256kや文書ジャンル比較へ展開。

## 今後の扱い

- 診断機能の実動作を確認できたら、**実文書入力機能（汎用）**と**VULKAN-002統計機能（専用）**を別単位でr4へ取り込む。
- r5のupstream refresh後も、統計機能はVULKAN-002本体の変更と一緒に移植する。
- レイヤー別統計、分布ヒストグラム、QSA fallback件数の全量計測は追加要件として保留。
