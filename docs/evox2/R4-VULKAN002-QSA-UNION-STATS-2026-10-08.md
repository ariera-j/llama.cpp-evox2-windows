> [!IMPORTANT]
> **Historical r4 diagnostic implementation — archived copy brought into r5 on 2026-10-10.** The implementation and verification narrative below applies to r4/b11433. Its "not ported to r5" statements are now historical.
>
> Original source: `investigation/vulkan-qsa-union-stats-20261008` at `979ef17eeff14440a58c866a966b355a1b63b17e`. For the active r5 implementation see [r5 union stats port/validation](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md). For contemporary distributions see [64k](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md) and [128k](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md).
>
> The original r4 environment flags for MoE tile and GET_ROWS are experiment conditions, **not** recommended r5 defaults. STATS ON PP is diagnostic only.

# VULKAN-002: QSA grouped-union 診断機能（試験実装）

更新日: 2026-10-09

## 位置づけ・状態

- ブランチ: `investigation/vulkan-qsa-union-stats-20261008`
- 起点: `investigation/llama-bench-real-prompt-20261007`（`e3466e8fa769928140f81c93c84889860732ff82`）
- 実文書入力オプション `-f`, `--prompt-slice`, `-c` は汎用計測機能として維持する。
- union統計はVULKAN-002の**診断用付属機能**。本線r4やr5には**未移植**。
- **Evo-X2 / Vulkan b11433で実測済み**（2026-10-09）。64k・256kの実文書/random双方で診断CSVを回収し、`dropped_groups=0`を確認。QSA OFF 64kの対照測定も取得済み。ただし通常性能への影響・他環境での動作・本線r4への移植は未確認。

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

## Evo-X2での動作確認手順

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

## 実機測定と現時点の確認状況（2026-10-09）

詳しい測定条件、数値、入力SHA、各ZIP名、QSA OFFで生じた速度順位逆転とその留保は [llama-bench実文書入力モード／b11433追加検証](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md#b11433-追加検証-vulkan-002-union-診断と-64k-qsa-off2026-10-09) に記録する。

| QSA UNION | Stats | Context | 実文書 | Random | 記録漏れ |
| --- | --- | --- | --- | --- | --- |
| ON | ON | 64k | 実行成功、CSV取得 | 実行成功、CSV取得 | 0 / 0 |
| ON | ON | 256k | 実行成功、CSV取得 | 実行成功、CSV取得 | 0 / 0 |
| OFF | OFF | 64k | 初回1回＋再測定2回成功 | 初回1回＋再測定2回成功 | 統計対象外 |

64k QSA ON の実文書は timed repetitions=2、randomは1で、**どちらもwarmupあり**。256k QSA ON は両方 `NoWarmup=true`、repetitions=1。16k binごとに出力されたCSVから、group数を重みとしたunique/padded平均と `sum(unique)/sum(selected)` を算出できることを確認した。

256k QSA ONでは、randomのunique union平均は実文書比約**+66.85%**で、入力内容によるunion効率の差が大きい。これは長文PP差の有力な説明だが、PP低下の寄与率まで確定するものではない。

64k QSA OFFではrandom PPが実文書PPより速い結果が**再現した**。初回は実文書→random（NoWarmup、各1回）で **268.81 vs 305.59 tok/s**（random +13.68%）。追加測定は順序を**random→実文書**と逆転し、warmupあり・各2回で **実文書269.119772 vs random306.514502 tok/s**（random +13.90%）。追加測定の2サンプルは実文書269.087/269.153、random306.680/306.349 tok/s。共通環境: `GGML_VK_QSA_UNION=0`、`GGML_VK_MOE_LEGACY_TILE_SELECTION=1`、`GGML_VK_GET_ROWS_128X4=0`。両runの終了ステータスOK。

追加測定のZIP: `20261009-020541-191-bench-vulkan-b11433-ctx65536-68a3c2ffc33e.zip`（real/random収録）。詳細とrun ID、実文書入力SHAは [実文書bench検証メモ](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md) に追記した。

**測定順序やwarmupだけでは逆転を説明しにくい**ことは確認できた一方、grouped-union OFFでは通常のFA経路が選ばれるため、速度逆転の内部要因は未特定である。

### MoE tile単独A/Bとの関連

10/07の64k実文書 `243.34 tok/s` はQSAとMoE legacy等の環境変数を**すべて未設定**で取得された。Vulkan実装では `GGML_VK_QSA_UNION`、`GGML_VK_GET_ROWS_128X4` は未設定でも明示的な`0`でもOFFなので、今回のQSA OFF実文書 `268.81 / 269.12 tok/s` との差で**実効設定が異なるのは `GGML_VK_MOE_LEGACY_TILE_SELECTION`**。

独立した [10/03のMoE tile A/B](R4-MOE-TILE-AB-2026-10-03.md) は、b11376で同一実行ファイル・Originalモデルのcli ABBAにより upstream 248.475 → legacy 268.985 tok/s（**+8.25%**）を確認。GPU profileでもMoE演算合計は63.933→47.807秒（**-25.22%**）で、FAはほぼ同じ。別調査のbench参考比較 243.34→268.81（**+10.47%**）と同方向・近い大きさだが、**そのbench同士でもbuildとwarmupが異なり、10/03のCLI ABBAとはモデル形式・ツールも異なる**。この+10.47%自体を厳密なMoE単独効果とみなしてはいけない。

### 本流移植前に残る確認

- 診断OFFで追加処理がなく、r4の通常PP/TGに性能退行がないかを比較する。
- 64k QSA OFFの順序反転再測定は完了。残るのはFA経路・MoEなど**逆転の機構**の切り分けであり、本流移植の必須条件とはしない。
- 将来必要なら、複数文書ジャンル・レイヤー別・適用経路別の診断範囲を拡張する。

## 今後の扱い

- 診断機能の実動作を確認できたら、**実文書入力機能（汎用）**と**VULKAN-002統計機能（専用）**を別単位でr4へ取り込む。
- r5のupstream refresh後も、統計機能はVULKAN-002本体の変更と一緒に移植する。
- レイヤー別統計、分布ヒストグラム、QSA fallback件数の全量計測は追加要件として保留。

---

## r5移植後の追記（2026-10-10）

- 2026-10-09に**r5版統計機能の選択的移植**を完了。b11535 / Vulkanで実測し、診断CSV作成と `dropped_groups=0` を確認している。[移植と検証](R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md)。元のr4ブランチをそのままマージしたものではない。
- r5では同じ実文書の比較軸を拡充。通常PP（STATS OFF）は [64k/128k Vulkan OFF/ON](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md)、unionの内部統計（STATS ON）は [64k 7種類](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md)、[128k 3種類](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md) に記録。
- r4の主要観測（64k/256kの実文書とランダムのunionサイズの差、64k QSA OFFの速度順位逆転）は当時の測定値として上に保存した。r5でも入力依存性が見られ、[ROCm対照](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md)ではROCm側のばらつきがかなり小さいことを確認した。**r4とr5の数値の直接同一条件比較ではない。**
- 今後の診断は `investigation/r5-vulkan-off-fa-dispatch-20261010` に分離しており、FA分岐のCPU側統計を収集する設計。現行r5安定ブランチには含まない。[診断設計資料](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-vulkan-off-fa-dispatch-20261010/docs/evox2/R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md)。
