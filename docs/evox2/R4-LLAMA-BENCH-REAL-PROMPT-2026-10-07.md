> [!IMPORTANT]
> **Historical r4 investigation — archived copy brought into r5 on 2026-10-10.** This document preserves the r4 implementation and measured results as recorded at the time. Statements below such as "not yet ported to r5" describe the historical status, **not** the current r5 branch.
>
> Original source: `investigation/vulkan-qsa-union-stats-20261008` at `979ef17eeff14440a58c866a966b355a1b63b17e`. This later branch includes the original real-prompt work from `investigation/llama-bench-real-prompt-20261007` at `e3466e8fa769928140f81c93c84889860732ff82`, plus the b11433 QSA diagnostic and OFF control appendices.
>
> r5 status: real-prompt llama-bench was selectively ported, Windows smoke-tested and used in the 64k/128k Vulkan and ROCm studies. See [r5 real-prompt port](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md), [r5 Vulkan corpus A/B](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md), and [r5 ROCm/Vulkan comparison](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md). Do not copy the old r4 test-specific MoE/GET_ROWS tuning settings to current r5 as though they were still the baseline.

# llama-bench 実文書入力モード

日付: 2026-10-07

## 目的

この変更は、llama-cli と llama-bench の prompt processing (PP) 差を調べるために、llama-bench の PP 入力を従来のランダム token ID から任意の実文書へ差し替えられるようにするものです。

通常の llama-bench は変更しません。入力ファイルを指定しなければ、従来どおりランダム token ID で測定します。

## 追加オプション

- `-f, --prompt-file <filename>`
  - UTF-8 テキストファイルを読み込み、使用モデルの vocabulary で tokenize して PP 入力に使用します。
- `--prompt-slice <head-tail|head>`
  - `-p` で指定した token 数をファイル全体からどう取り出すかを選びます。
  - デフォルトは `head-tail` です。
- `-c, --ctx-size <n>`
  - context size を明示します。
  - `0` または未指定では、従来の llama-bench と同じく各 test の `n_prompt + n_gen + n_depth` から決めます。

## prompt-file の動作

`--prompt-file` を使った場合:

- `-p N` なら、tokenize 後のファイルからちょうど `N` token を使用します。
- `-p 61789,126253,255181` のように複数指定した場合、同じソース文書から各長さを独立に作ります。
- `-p` を省略した場合は、tokenize 後のファイル全文を PP test に使用します。
- 指定した `-p` がファイルの token 数より大きい場合、反復や padding はせずエラー終了します。
- tokenize と slice 作成は計測区間の外で行います。
- warmup と全 timed repetition で同じ token 列を再利用します。
- `-d/--n-depth` の事前充填は従来どおり random token のままです。
- llama-bench が logical prompt batch ごとの末尾で output/logits を要求する既存動作は変更していません。

### head-tail

要求 token 数を `N` とすると、

- 先頭から `ceil(N / 2)`
- 末尾から `floor(N / 2)`

を取り出し、そのまま連結します。間に separator token は追加しません。

例: `N = 61789`

- 先頭 30,895 token
- 末尾 30,894 token

この方式は、長文の中央を削りつつ、冒頭指示と末尾の質問・要約依頼などを残したい場合に向いています。

`--prompt-slice head` は従来案どおり先頭 `N` token だけを使用します。

## 重要な注意

このモードはファイルを **raw text として** tokenize します。llama-cli/server の Jinja chat template は適用しません。

そのため、CLIログに出る prompt token 数と、同じファイルをraw tokenizeした token 数は一致しない場合があります。たとえばCLIの 61,789 token をそのまま `-p 61789` として再現したい場合は、raw tokenize後にも61,789 token以上ある、より長いソース文書を指定してください。短い場合は自動反復せずエラーになります。

したがって、最初の用途は「random token と自然言語 token の分布差が QSA grouped-union などへ影響するか」を切り分けることです。CLI の完全な request path と同一になったことを意味しません。

今回の調査では、まず以下を固定します。

1. llama-bench の batch 構築方法は変更しない。
2. batch ごとの logits/output 動作も変更しない。
3. random token を実文書 token にだけ差し替える。
4. 必要になった場合に限り、Jinja 適用や final-only logits を別の実験として扱う。

## llama-bench.exe の例

64k 相当、PP のみ:

```powershell
& .\llama-bench.exe `
  -m C:\models\Qwen3.8-Flash-Next.gguf `
  -f C:\data\long-source.txt `
  --prompt-slice head-tail `
  -c 65536 `
  -p 61789 `
  -n 0 `
  -d 0 `
  -r 2 `
  -b 2048 `
  -ub 1024 `
  -ctk f16 `
  -ctv f16 `
  -t 4 `
  -ngl 999 `
  -ncmoe 0 `
  -fa auto `
  -o json
```

十分長い1つの文書から複数の PP 長を測る例:

```powershell
& .\llama-bench.exe `
  -m C:\models\Qwen3.8-Flash-Next.gguf `
  -f C:\data\long-source.txt `
  --prompt-slice head-tail `
  -c 262144 `
  -p 61789,126253,255181 `
  -n 0 `
  -d 0 `
  -r 2 `
  -b 2048 `
  -ub 1024 `
  -ctk f16 `
  -ctv f16 `
  -t 4 `
  -ngl 999 `
  -ncmoe 0 `
  -fa auto `
  -o json
```

この例では `-c 262144` を固定しているため、3つの PP test が同じ context allocation を使用します。

従来の llama-bench と同じ自動 context sizing に戻す場合は `-c` を省略するか `-c 0` を指定します。

## Evo-X2 計測ラッパー

`tools/evox2/benchmark/Measure-LlamaBench.ps1` に以下を追加しています。

- `-InputKey <key>`
  - `configs/local.psd1` の既存 `Inputs` セクションから入力ファイルを解決します。
- `-InputFile <path>`
  - 任意の入力ファイルを直接指定します。
- `-PromptSlice head-tail|head`
  - デフォルト `head-tail`。
- `-Context <n>`
  - native llama-bench の `-c` へ渡します。
  - デフォルト `0` は自動 sizing です。

`-InputKey` と `-InputFile` のどちらも指定しない場合、従来の random-token benchmark のままです。

例:

```powershell
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 `
  -BuildKey R4QsaUnionVulkan `
  -ModelKey Qwen38UnslothPle16 `
  -InputFile C:\data\long-source.txt `
  -PromptSlice head-tail `
  -Context 65536 `
  -PromptTokens 61789 `
  -GenerationTokens 0 `
  -Depths 0 `
  -Repetitions 2 `
  -KvType f16 `
  -Batch 2048 `
  -UBatch 1024 `
  -Threads 4 `
  -GpuLayers 999 `
  -CpuMoe 0 `
  -FlashAttn auto
```

ラッパーは条件・結果メタデータに以下を保存します。

- 入力ファイル path
- byte size
- SHA-256
- prompt slice
- requested context

同名ファイルの内容を差し替えた場合でも、SHA-256 により実験条件を区別できます。

## 最初の推奨比較

| Backend | 入力 | 目的 |
| --- | --- | --- |
| Vulkan | random | 既存 baseline |
| Vulkan | 実文書 | QSA grouped-union の入力依存性を見る |
| ROCm | random | 対照 |
| ROCm | 実文書 | Vulkan 固有かを見る対照 |

まず64kで確認し、Vulkan の実文書 PP が CLI 側へ近づき、ROCm がほぼ変わらない傾向が出た場合に、256k Vulkan の実文書測定へ進むのが効率的です。


## 64k 測定結果（2026-10-07）

実装後、Vulkan b11427 で 64k 相当の PP を測定した。

主比較では以下を固定した。

- build: b11427
- context: `65536`
- prompt tokens: `61789`
- generation tokens: `0`
- depth: `0`
- repetitions: `2`
- KV: f16
- batch / ubatch: `2048 / 1024`
- threads: `4`
- GPU layers: `999`
- CPU MoE: `0`
- Flash Attention: `auto`
- `GGML_VK_MOE_LEGACY_TILE_SELECTION=1`
- `GGML_VK_QSA_UNION=1`
- `GGML_VK_GET_ROWS_128X4=0`

実文書側は 256k 用の長文入力から `head-tail` で 61,789 token を取り出した。random 側は `-InputFile` を指定せず、従来の llama-bench random token path を使用した。

### 結果

| 条件 | PP [tok/s] | timed samples [tok/s] | 実文書比 |
| --- | ---: | --- | ---: |
| 実文書 / QSA UNION ON | **337.68** | 337.646 / 337.709 | baseline |
| random token / QSA UNION ON | **316.10** | 315.704 / 316.503 | **-6.39%** |
| 実文書 / Vulkan tuning 環境変数なし | 243.34 | 243.381 / 243.307 | -27.94% |

対応する計測成果物:

- 実文書 / tuning vars なし: `20261007-144021-997-bench-vulkan-b11427-ctx65536-bf0df9f30928.zip`
- 実文書 / QSA UNION ON: `20261007-150636-426-bench-vulkan-b11427-ctx65536-50463dfce096.zip`
- random / QSA UNION ON: `20261007-153025-382-bench-vulkan-b11427-ctx65536-835d1d6f93a4.zip`

最初の実文書 run では Vulkan tuning 用の3環境変数を設定していなかった。この run は参考値として残すが、ON設定との比較で**実効動作が変化するのはQSA UNIONとMoE legacy tile選択の2つ**である（GET_ROWSは未設定も明示的な`0`もOFF）。したがって243.34 → 337.68 tok/s の差を QSA UNION 単独の効果とは扱わない。

### 過去の CLI / llama-bench との対応

過去の64k比較では、

| 経路 | 入力 | PP [tok/s] |
| --- | --- | ---: |
| llama-cli | 実文書 | 337.45 |
| llama-bench | random token | 322.19 |

だった。

今回、同じ b11427・同じ `c=65536`・同じ Vulkan tuning 条件で実文書と random を直接比較すると、

- 実文書: **337.68 tok/s**
- random: **316.10 tok/s**

となった。

今回の実文書 llama-bench は過去の実文書 llama-cli 337.45 tok/s と **+0.07%** の差に収まった。一方、同一build・同一contextで random token にすると実文書比 **-6.39%** となった。

したがって64kでは、以前観測した llama-cli と llama-bench の PP 差について、少なくとも主要因の1つが **llama-bench の random token 入力**であることが強く支持される。

過去の random benchmark 322.19 tok/s と今回の316.10 tok/sは完全同条件ではない。過去 run は llama-bench の自動 context sizing を使用し、今回は CLI 条件に合わせて `65536` を明示しているため、この差は今回の入力内容比較には使用しない。

### 現時点の QSA grouped-union 仮説

有力な説明は、random token と自然言語文書で QSA が選ぶ K/V 位置の分布が異なることである。

現在の grouped-union は64 queryごとに selected ID をunionして重複を除去し、その compact K/V を gather して Flash Attention に渡す。このため自然言語では64-query group内の selected ID overlap が大きく、random token では overlap が小さい場合、

1. random token の unique selected ID 数が増える
2. gather対象の K/V が増える
3. compact後の Flash Attention の実効KV長も増える
4. PPが低下する

という挙動が説明できる。

ただし、今回直接測定したのは PP 差までであり、union後の unique selected ID 数や overlap 率そのものは未計測である。したがって、**「random token で Vulkan QSA ON の PP が低下する」ことは確認済みだが、その内部原因が selected-ID overlap であることはまだ仮説**として扱う。

## 256k 測定結果（2026-10-07）

64kで入力依存性が確認できたため、256kでも同じA/Bを行った。

固定条件:

- build: b11427
- context: `262144`
- prompt tokens: `255181`
- generation tokens: `0`
- depth: `0`
- repetitions: `2`
- KV: f16
- batch / ubatch: `2048 / 1024`
- threads: `4`
- GPU layers: `999`
- CPU MoE: `0`
- Flash Attention: `auto`
- `GGML_VK_MOE_LEGACY_TILE_SELECTION=1`
- `GGML_VK_QSA_UNION=1`
- `GGML_VK_GET_ROWS_128X4=0`

実文書側は長文入力を `head-tail` で255,181 tokenに切り出した。random側は `-InputFile` を指定せず、従来の llama-bench random token pathを使用した。

### 結果

| 条件 | PP [tok/s] | timed samples [tok/s] | 実文書比 |
| --- | ---: | --- | ---: |
| 実文書 / QSA UNION ON | **270.42** | 270.422 / 270.413 | baseline |
| random token / QSA UNION ON | **213.42** | 215.955 / 210.895 | **-21.08%** |

対応する計測成果物:

- 実文書 / QSA UNION ON: `20261007-181635-742-bench-vulkan-b11427-ctx262144-f9d241c696c0.zip`
- random / QSA UNION ON: `20261007-200749-569-bench-vulkan-b11427-ctx262144-5856b6e8f49f.zip`

両runとも stderr で `qsa-union active (r4)` を確認した。

### 過去のCLI / llama-benchとの対応

過去の256k比較:

| 経路 | 入力 | PP [tok/s] |
| --- | --- | ---: |
| llama-cli | 実文書 | 268.10 |
| llama-bench | random token | 216.09 |

今回の同一build・同一context比較:

| 経路 | 入力 | PP [tok/s] |
| --- | --- | ---: |
| llama-bench b11427 | 実文書 | **270.42** |
| llama-bench b11427 | random token | **213.42** |

実文書 llama-bench は過去の実文書 llama-cli に対して **+0.86%**、random llama-bench は過去の random llama-bench に対して **-1.23%** であり、両系統とも過去測定とほぼ同じ性能帯を再現した。

## 64k / 256k のまとめ

| 経路 / 入力 | 64k PP [tok/s] | 256k PP [tok/s] | 64k→256k |
| --- | ---: | ---: | ---: |
| 過去 llama-cli / 実文書 | 337.45 | 268.10 | **-20.55%** |
| 今回 llama-bench / 実文書 | **337.68** | **270.42** | **-19.92%** |
| 今回 llama-bench / random | 316.10 | 213.42 | **-32.48%** |
| 過去 llama-bench / random | 322.19 | 216.09 | **-32.93%** |

同一build・同一contextでの random penalty は、

- 64k: **-6.39%**
- 256k: **-21.08%**

まで拡大した。

実文書に差し替えた llama-bench は、絶対PPだけでなく64k→256kのスケーリングも llama-cli とほぼ一致した。一方、random tokenでは以前と同様に長コンテキストで大きく性能が低下した。

この結果から、以前観測した「llama-benchだけ256k PPが大きく低下する」現象については、llama-benchの実行経路そのものよりも、**標準のrandom-token workloadがVulkan QSA grouped-unionに不利であることが主要因**と判断できる。

### QSA grouped-union内部機構について

現在の実装では、64-query groupごとにQSAのselected IDをunionして重複を除去し、compact K/VをgatherしてFlash Attentionへ渡す。

今回確認できたのは以下までである。

- random token入力では、実文書入力よりPPが低下する。
- その差は64kの約6%から256kの約21%へ拡大する。
- 実文書 llama-bench は llama-cli の性能と長文スケーリングをほぼ再現する。

一方、**random tokenでselected-ID overlapが低下し、union後のunique KV数が増えているかどうかはまだ直接測定していない**。

次に内部原因まで確認する場合は、QSA union shaderが生成しているgroupごとのunique countを診断用に読み出し、実文書とrandomで比較する。


---

## b11433 追加検証: VULKAN-002 union 診断と 64k QSA OFF（2026-10-09）

この節は b11427 の実文書対応 llama-bench 検証（上記）に続く、b11433 の **union統計を直接取得した診断実験**を記録する。実行場所は Evo-X2 / Vulkan。実装・仕様は [R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md](R4-VULKAN002-QSA-UNION-STATS-2026-10-08.md) を参照。

### 共通条件と実験の違い

- build: **b11433**（診断機能を含む、実行ファイルメタデータのcommit表記は `b1623a7aa`）
- モデル: Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS、PLE16変換モデル
- context / prompt: **64k = 65,536 / 61,789 tokens**、**256k = 262,144 / 255,181 tokens**
- `-n 0 -d 0 -b 2048 -ub 1024 -ctk f16 -ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto`
- 実文書は `head-tail` 入力。ソース入力SHA-256: `d08f051c05a72d73b959301269daa2d75682a9438773d48614c3655325add990`（`nlp-survey-ch3-d32-b1.txt`）
- random は入力ファイルを指定しない標準 `llama-bench` の token ID 生成
- Vulkan共通: `GGML_VK_MOE_LEGACY_TILE_SELECTION=1`、`GGML_VK_GET_ROWS_128X4=0`
- QSA ON 診断: `GGML_VK_QSA_UNION=1`、`GGML_VK_QSA_UNION_STATS=1`、`GGML_VK_QSA_UNION_STATS_KV_BIN=16384`
- QSA OFF: `GGML_VK_QSA_UNION=0`。STATSも無効。QSA OFF は QSAモデル全体を無効にする指定ではなく、**grouped-unionの専用経路を使用しない**という意味。

**重要:** 診断 ON のPP値はGPU統計コピー・同期・CSV処理の影響を受け得る。QSA ON診断とQSA OFF通常経路のPP値は、**厳密なON/OFF速度向上率の算定に用いない**。入力差の傾向と内部統計を見る実験である。実文書/ランダムの診断も測定回数・warmup条件を下記のとおり区別する。

### 64k / 256k: 実文書とrandomの直接比較（QSA ON / STATS ON）

| Context | 入力 | Timed repetitions | Warmup | PP [tok/s] | Unique union平均 | Padded union平均 | Unique / selected | 有効group合計 | Dropped |
| --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 64k | 実文書 | 2 | あり | **336.58** | 17,512.02 | 17,638.17 | 13.36% | 16,920 | 0 |
| 64k | Random | 1 | あり | **315.62** | 24,859.00 | 24,984.69 | 18.96% | 11,280 | 0 |
| 256k | 実文書 | 1 | なし | **269.57** | 19,703.62 | 19,829.13 | 15.01% | 41,904 | 0 |
| 256k | Random | 1 | なし | **215.46** | 32,875.50 | 33,001.68 | 25.05% | 41,904 | 0 |

- 64k: randomは実文書に対してPP **-6.23%**。unique union平均は **約41.95%増**、padded union平均は **約41.65%増**。
- 256k: randomは実文書に対してPP **-20.07%**。unique union平均は **約66.85%増**、padded union平均は **約66.43%増**。
- 64kは**実文書のrepetitions=2、random=1（どちらもwarmupあり）**。統計にはwarmupとtimedの両方が含まれるため、group数も異なる。比較には各測定内の `groups` で重み付けした平均を使用している。
- 256kは両方 `repetitions=1`・`NoWarmup=true`。64k・256kとも `dropped_groups=0`、ステータスOK / exit code 0。
- ON実行のstderrには、初期KV長でのfallbackと、その後の `qsa-union active (r4)` を確認した。
- `selected` は `n_batch*n_top` の**候補slot総数**（無効indexも含む）。したがって `unique/selected` は便利な効率指標だが、**重複率だけを厳密に分離した値ではない**。

#### KV長別の差（各16k区間、unique unionのgroup加重平均）

| KV bin開始 | 64k 実文書 | 64k Random | 256k 実文書 | 256k Random |
| ---: | ---: | ---: | ---: | ---: |
| 32,768 | 16,863 | 23,257 | 16,908 | 23,033 |
| 49,152 | 18,289 | 26,776 | 18,090 | 26,618 |
| 65,536 | — | — | 19,162 | 29,866 |
| 81,920 | — | — | 19,409 | 31,387 |
| 98,304 | — | — | 19,731 | 33,384 |
| 114,688 | — | — | 19,982 | 34,306 |
| 131,072 | — | — | 19,752 | 34,490 |
| 147,456 | — | — | 19,894 | 33,952 |
| 163,840 | — | — | 20,231 | 34,834 |
| 180,224 | — | — | 20,388 | 35,345 |
| 196,608 | — | — | 20,234 | 35,456 |
| 212,992 | — | — | 20,328 | 35,948 |
| 229,376 | — | — | 20,808 | 36,591 |
| 245,760 | — | — | 21,624 | 36,266 |

**読み取り:** 256kの実文書では長文域でunique unionが概ね2万前後に留まるのに対し、randomでは3.5万～3.7万近くまで増加した。randomで selected ID集合の共有が少なくなるという従来の仮説を支持する。union後にFAが処理するpadded KV長も同時に増加している。

ただし、この統計だけで **PP速度差の100%をunion経路の違いによるものと確定することはできない**。QSA OFFでは別のFA経路を選択し得るほか、MoE等も入力依存である。

### 64k: QSA UNION OFF の暫定対照測定（2026-10-09、各1回）

QSA ON診断のあと、**grouped-unionのみOFF**とし、64kの実文書・randomを各1回測定した。ON測定と同じb11433・入力ファイルSHA・context・prompt数・KV型・batch等を使用した。Vulkan環境変数は `GGML_VK_QSA_UNION=0`、`GGML_VK_MOE_LEGACY_TILE_SELECTION=1`、`GGML_VK_GET_ROWS_128X4=0`。STATSは設定されていない。

| 条件 | 実文書PP [tok/s] | Random PP [tok/s] | Randomの実文書比 |
| --- | ---: | ---: | ---: |
| QSA ON、STATS ON（参考・測定回数とwarmup条件が異なる） | 336.58 | 315.62 | -6.23% |
| **QSA OFF、STATS OFF（NoWarmup・各1回）** | **268.81** | **305.59** | **+13.68%** |

QSA OFFでは **randomの方が速い**という、ON時と逆の順位が出た。条件のメタデータ上、明らかな設定間違いは見当たらず、両測定ともステータスOK / exit code 0。診断OFFなのでunion統計CSVはない。

ただし、実文書→randomの順で、warmupなし・各1回の測定であるため、GPUクロック・初回状態・測定順序などの影響が残る。**逆転の原因は未確定で、現時点では暫定結果**として扱う。過去の64k `243.34 tok/s` の環境変数を一括設定し忘れた測定はMoE tile等も異なるので、この純粋なQSA OFF対照とは分けて扱う。

#### 関連する元データ（ZIPにreal/randomの両方を収録）

- **64k QSA ON/STATS ON**: `20261009-003514-594-bench-vulkan-b11433-ctx65536-90a7d414f967.zip`
  - 実文書 run: `20261009-002507-004-bench-vulkan-b11433-ctx65536-838d3f383d73`
  - Random run: `20261009-003514-594-bench-vulkan-b11433-ctx65536-90a7d414f967`
- **256k QSA ON/STATS ON**: `20261009-010950-147-bench-vulkan-b11433-ctx262144-26785f0f75a6.zip`
  - 実文書 run: `20261009-005225-937-bench-vulkan-b11433-ctx262144-1262e2597b8c`
  - Random run: `20261009-010950-147-bench-vulkan-b11433-ctx262144-26785f0f75a6`
- **64k QSA OFF/STATS OFF**: `20261009-013908-588-bench-vulkan-b11433-ctx65536-3b709d9654b4.zip`
  - 実文書 run: `20261009-013438-820-bench-vulkan-b11433-ctx65536-d170bc3a04e8`
  - Random run: `20261009-013908-588-bench-vulkan-b11433-ctx65536-3b709d9654b4`

### 64k: QSA UNION OFF 追加測定（Random先→実文書後、各2回）

入力ZIP: `20261009-020541-191-bench-vulkan-b11433-ctx65536-68a3c2ffc33e.zip`。前回とは逆に **Random→実文書** の順で、それぞれ **warmupあり・timed repetitions=2** として再測定した。

- random run: `20261009-015501-179-bench-vulkan-b11433-ctx65536-e41d256ce0b4`
- 実文書 run: `20261009-020541-191-bench-vulkan-b11433-ctx65536-68a3c2ffc33e`
- 共通: b11433 / `b1623a7aa`、Vulkan、モデルはUnsloth PLE16、ctx=65536、prompt=61789、`-n 0 -d 0 -b 2048 -ub 1024 -ctk f16 -ctv f16 -t 4 -ngl 999 -ncmoe 0 -fa auto`
- Vulkan環境: `GGML_VK_QSA_UNION=0`、`GGML_VK_MOE_LEGACY_TILE_SELECTION=1`、`GGML_VK_GET_ROWS_128X4=0`。QSA診断STATSは未設定。
- 実文書入力SHA256 `d08f051c05a72d73b959301269daa2d75682a9438773d48614c3655325add990`。両run Status OK / exit code 0。

| 条件 | 順番 | Warmup | Timed rep数 | 実文書PP [tok/s] | Random PP [tok/s] | Randomの実文書比 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 初回（64k OFF） | 実文書→Random | なし | 1ずつ | 268.81 | 305.59 | +13.68% |
| **再測定（64k OFF）** | **Random→実文書** | **あり** | **2ずつ** | **269.119772** | **306.514502** | **+13.90%** |

再測定のtimed samples: random **306.680 / 306.349**、実文書 **269.087 / 269.153 tok/s**。先行runに対するPP変化はrandom約+0.30%、実文書約+0.12%で、各2回のばらつきも小さい。**QSA UNION OFFでrandomが速い現象は、順序を逆転しても再現**した。したがって測定順序・warmupのみを原因とする説明は支持しにくくなったが、OFF時のFA実行経路と入力依存性の内訳は未確定のまま。

### 10/03のMoE tile単独A/Bとの比較（環境変数設定忘れの整理）

一次資料: [R4-MOE-TILE-AB-2026-10-03.md](R4-MOE-TILE-AB-2026-10-03.md)。

Vulkanソース上、`GGML_VK_QSA_UNION`、`GGML_VK_MOE_LEGACY_TILE_SELECTION`、`GGML_VK_GET_ROWS_128X4` は**いずれも文字列 `1` の場合だけON**である。よって「3変数とも未設定」と「QSA UNION=0 / GET_ROWS=0 / MoE legacy=1」の間で、**実効動作の差はMoE legacy tile選択だけ**。10/07の243.34 tok/sは、QSA OFFだけでなくMoE legacyもOFFだったため、QSA ONとの直接比較に使えない。

10/03には、同じr4バイナリ b11376 / `c81b8bf78` で `GGML_VK_MOE_LEGACY_TILE_SELECTION=0/1` だけを切り替えた **llama-cli ABBA測定（Originalモデル、生成128）**が完了している。

| 64k実文書PP比較 | MoE upstream方式（legacy=0） | MoE legacy方式（legacy=1） | 改善率 | 比較の位置づけ |
| --- | ---: | ---: | ---: | --- |
| 10/03 llama-cli ABBA平均（b11376 / Original） | 248.475 | 268.985 | **+8.25%** | **同一buildの厳密なMoE単独A/B** |
| 10/07～09 llama-bench参考値（b11427→b11433 / PLE16） | 243.34 | 268.81 | **+10.47%** | **build、warmup等が異なるため交絡あり** |
| 同参考値の再測定版 | 243.34 | 269.119772 | +10.59% | b11433 / warmupありの参考値 |

10/03のGPU profileでは、MoE演算合計が **63.933→47.807秒（-25.22%）**、Flash Attentionが **108.658→108.654秒（ほぼ同じ）**、PPのGPU演算合計が **253.097→230.763秒（-8.82%）**。同一build・入力・条件でMoE切り替えに由来するPP改善を別途確認済みなので、今回の約10%の差も**MoE tile方式の寄与と整合**する。ただしOriginalとPLE16、llama-cliとllama-bench、build等の差があるため、**243.34→268.81の+10.47%すべてをMoEの因果効果と確定することはできない**。

記事では本筋（実文書 vs random / QSA union効率）から独立した「環境変数の設定忘れから過去のMoE tile検証につながった」補足として扱う。QSA UNION ON/STATS ON とOFF/STATS OFFのPP差を純粋なQSA改善率として使わない。

### ここまでの暫定結論とr4取り込み

1. `llama-bench` と `llama-cli` の以前のPP差は、実文書入力を使用するとほぼ消える（b11427の64k/256k比較）。実行経路の差だけでなく、**比較に使ったworkload差**が主要な交絡要因だった。
2. b11433の直接診断で、**randomでは実文書よりunique/padded unionが明確に大きい**ことを64k・256k双方で確認した。とくに256kの差が大きく、長文でrandom PPが大きく低下する事実と整合する。
3. QSA OFF 64kではrandomの方が速いという逆順位が、**順序反転・warmupあり・各2回の追加実測でも再現**。UNION OFFは別FA経路へ移るため、**原因の寄与割合や特定kernelの寄与は未確定**。
4. 通常のr4高速化を再開する際、**実文書入力は汎用llama-bench機能、union統計はVULKAN-002の診断付属機能**として、変更を分離して本流へ移植する。現時点では調査ブランチのみ。

---

## r5移植後の追記（2026-10-10）

この文書は **r4での一次調査・数値の履歴資料**として移植したものであり、上の本文中の実装状況や今後の予定は当時の記述を維持している。現行r5のソース・テスト手順を規定する文書ではない。

- **実文書モード：r5へ移植・確認済み。** `-f/--prompt-file`、`--prompt-slice`、`-c/--ctx-size` とEvo-X2計測ラッパーの入力ハッシュ記録は [r5移植・スモーク](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md) を参照。
- **union統計：r5へ移植・確認済み。** b11535でCSV生成を検証し、[7種類の64k統計](R5-QSA-UNION-SEVEN-CORPORA-64K-2026-10-10.md) と[128kの3種類統計](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md) に展開している。
- **PPの最新比較：** [Vulkan 64k/128k OFF/ON](R5-QSA-UNION-CORPUS-AB-64K-128K-2026-10-10.md)、[ROCm 64k/128kとの比較](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md)。r4のb11427/b11433測定とr5のb11535/b11543測定は別ビルドであり、入力のsource SHA・head/head-tail切り出し・warmup・MoE設定を揃えずに差を単一機能の効果として扱わない。
- **次の原因調査：** sparse FA切替で差がほぼ変わらなかったため、r5から切った `investigation/r5-vulkan-off-fa-dispatch-20261010` にFA分岐カウンタを実装。これはr5安定ブランチにはマージしていない。[調査ブランチの手順書](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/investigation/r5-vulkan-off-fa-dispatch-20261010/docs/evox2/R5-VULKAN-OFF-FA-DISPATCH-DIAGNOSTICS-2026-10-10.md) を参照。
