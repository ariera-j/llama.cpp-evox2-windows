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

最初の実文書 run では Vulkan tuning 用の3環境変数を設定していなかった。この run は参考値として残すが、`GGML_VK_QSA_UNION` だけでなく MoE legacy tile と GET_ROWS 設定も同時に異なるため、243.34 → 337.68 tok/s の差を QSA UNION 単独の効果とは扱わない。

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
