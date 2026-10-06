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
