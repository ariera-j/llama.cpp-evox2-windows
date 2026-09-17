# Evo-X2 Windows: r2 QSA union

r2は、r1 `ee245db63d4bd08f590aa5a4d756c5913e56ffdd` にVulkan用のQSA grouped-union prefillを追加した版です。QSAを使うQwen3.8-Flash-Nextの長文PPを主な対象としています。新経路は初期値OFFで、未対応の形状は従来経路へ戻ります。

公開対象は実機で確認したr2本体です。後続のgather-stride実験は、既存r2を超える再現可能な改善が確認できなかったため含めていません。

## 確認状況

| 項目 | 状態 |
|---|---|
| Windows LLVM 20.1.8 / Vulkan SDK 1.4.357.0 | ビルド成功 |
| `Test-Qsa-Union.ps1 -Suite Full` | OFF / ONとも成功 |
| Unsloth PLE16、64k、MTP OFF | 確認済み |
| Agention ROCmFP4-FAST-v2-ple16、64k、MTP OFF | 確認済み |
| Unsloth PLE16、128k、MTP OFF | 確認済み |
| 256k | 未確認 |
| MTP ON | 未確認 |
| MSVCとLLVMの比較 | 未確認 |

96GB GPU割り当て、f16 K/V、ubatch 1024、同時会話1で測定しました。入力、生成長、Windowsの状態により速度は変動します。

| モデル / 条件 | QSA union OFF | QSA union ON | 備考 |
|---|---:|---:|---|
| Unsloth PLE16、64k | PP平均227.26 | PP平均274.67 | ONが約20.9%高速 |
| Agention、64k | PP平均227.12 | PP平均273.22 | ONが約20.3%高速 |
| Unsloth PLE16、128k | PP 147.17 | PP 222.38 / 223.16 | OFFは1回、ONは2回 |

TGは各比較でほぼ同等でした。128kのON平均は222.77 token/sです。

## 1. Windowsでビルド

ソースは短いパスへ配置してください。Windows Explorerで長いパスを持つZIPを展開すると、一部ファイルだけ欠けた状態になることがあります。Git cloneを推奨します。

「x64 Native Tools Command Prompt for VS」を開き、`powershell -NoProfile`を実行します。リポジトリのルートへ移動して次を実行します。

```powershell
.\tools\evox2\Build-Qsa-Union.ps1 `
  -LlvmBin 'C:\LLVM\20.1.8\bin' `
  -VulkanSdk 'C:\VulkanSDK\1.4.357.0'
```

既定の出力先は`build-llvm20-r2\bin\Release`です。依存物は`C:\llama-build\evox2-deps`へ保存し、次回以降のconfigureで再利用します。別の場所を使う場合は`-DependencyCacheDirectory`を指定します。

スクリプトは次も確認します。

- Visual StudioリンカーとWindows SDKの環境
- LLVM、Vulkan SDK、CMake、Ninja、7-Zip
- 長すぎるビルドパス
- ZIP展開失敗で欠けやすいソースファイル
- 異なるソースツリーのCMakeCache再利用

`llama-cli.exe`、`llama-server.exe`、`llama-bench.exe`、`test-backend-ops.exe`と、同じディレクトリに生成されたDLLを一緒に使います。

## 2. モデルを使わない演算確認

```powershell
.\tools\evox2\Test-Qsa-Union.ps1 `
  -BinaryDirectory '.\build-llvm20-r2\bin\Release' `
  -Suite Full
```

既存の`test-backend-ops`を使い、31種類のQSAケースをOFFとONでCPU参照と比較します。最後に次が表示された場合だけモデル計測へ進みます。

```text
OFF and ON checks passed.
```

起動直後にCPUバックエンドのテスト候補に関するメッセージが出る場合があります。最終的なVulkanテスト数、終了コード、新経路の利用確認をスクリプトが判定します。

## 3. 64k / 128kの比較

```powershell
.\tools\evox2\Measure-Qsa-Union.ps1 `
  -LlamaCli '.\build-llvm20-r2\bin\Release\llama-cli.exe' `
  -ModelKind Unsloth `
  -ModelFile 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' `
  -InputFile 'D:\bench\prompt.txt' `
  -Context 131072 `
  -Sequence ABBA
```

`ABBA`はQSA unionのOFF、ON、ON、OFFです。gather方式の比較ではありません。単独計測では`-Sequence OFF`または`-Sequence ON`を指定します。

出力先の`evox2-r2-bench\日時`に、実行ログ、個別CSV、`comparison.csv`、`conditions.json`を保存します。ONではログ中の`min_kv`が要求値と一致しない場合に停止します。実験候補で使った`GGML_VK_QSA_GATHER_GROUPS`も計測中は解除し、終了後に元の値へ戻します。

## 4. 適用開始位置の比較

```powershell
.\tools\evox2\Measure-Qsa-Union.ps1 `
  -LlamaCli '.\build-llvm20-r2\bin\Release\llama-cli.exe' `
  -ModelKind Unsloth `
  -ModelFile 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' `
  -InputFile 'D:\bench\prompt.txt' `
  -Context 65536 `
  -Sequence ThresholdABBA `
  -MinKv 32768 `
  -CompareMinKv 26624
```

順序は32768、26624、26624、32768です。実機では26624のPP平均が275.30、32768が274.78 token/sで、約0.19%の差でした。同一条件の変動に対して小さいため、既定値は32768を維持します。16384は32768より約0.81%遅い結果でした。

## 5. 256kの最初の確認

256kでは最初からABBAを実行せず、リソース記録を開始してONを1回だけ測定します。

```powershell
.\tools\evox2\Measure-Qsa-Union.ps1 `
  -LlamaCli '.\build-llvm20-r2\bin\Release\llama-cli.exe' `
  -ModelKind Unsloth `
  -ModelFile 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' `
  -InputFile 'D:\bench\prompt-256k.txt' `
  -Context 262144 `
  -Sequence ON `
  -MinKv 32768
```

入力がコンテキストの80%未満の場合は警告を表示します。256kはコード上の境界テストを含みますが、Evo-X2での巨大モデル実行はまだ未確認です。

## 切り替えと適用条件

| 環境変数 | 動作 |
|---|---|
| `GGML_VK_QSA_UNION=1` | 新経路を有効にする。未設定または0ではOFF |
| `GGML_VK_QSA_UNION_STATS=1` | 新経路の利用回数やunionサイズを記録 |
| `GGML_VK_QSA_UNION_MIN_KV` | 適用開始KV行数。既定値32768 |

実モデルではQSAのPPバッチ32トークン以上にヒントを付けます。f16 K/V、1ストリーム、biasとsinksなしなどの条件を満たすと、64 queryずつ選択先の和集合を作り、K/Vをまとめてgatherします。queryごとのmaskとTop-Kは維持します。

TG、小さいMTP検証バッチ、q8_0 K/V、単一query、未対応形状では従来経路を使います。MTPの計算方法は変更していません。

`qsa-union active (r2)`が新経路を初めて利用した表示です。`path=0`はscalar、`path=1`はcooperative matrix 1、`path=2`はcooperative matrix 2です。

## 実装範囲

共有bitmapは4096 words、補助配列を含む宣言量は16,516 bytesで、実機の共有メモリ32 KiB上限内です。131,072位置ずつ範囲を分けるため、KV 262,144まで高い位置を保持できます。転送dispatchも複数次元へ分け、X方向65,535 groupの上限に依存しません。

K/Vとmaskの一時領域はgroup間で再利用し、unionリストと件数だけをgroup別に保持します。対応外の形状は従来経路へ戻ります。

## gather-stride実験を含めない理由

理論上の最大union行数まで起動する代わりに、少数のworkgroupがstride処理する候補を4096、8192、16384、32768 groupで比較しました。128kの最高値は32768の223.51 token/sでしたが、既存r2 ON平均222.77 token/sとの差は約0.33%でした。

追加反復では、PowerShellの単独指定を文字列配列として参照し、`32768`を`3`、`legacy`を`l`として渡す不具合が見つかりました。バックエンドは両方をlegacyへ戻したため、完走した7回はすべて同じlegacy経路でした。それでもPPは221.74から232.60 token/sまで約4.9%変動しました。この変動幅に対してstride候補の差は小さく、正式版から除外しています。

本リポジトリの安定版計測スクリプトにはgather指定を設けていないため、この先頭1文字問題はありません。

## 出典とライセンス

[Nathanw1014/llama.cpp PR #11](https://github.com/Nathanw1014/llama.cpp/pull/11)、head `1f4e25789d653cdef25e12b35099028c5a97553a`のgrouped-union方式を参考にしました。`qsa_union.comp`は同headの`flash_attn_union.comp`のbitmapとsubgroup prefix処理を適応しています。PRのMTP、Top-K radix、CUDA、DeepSeekの変更全体は取り込んでいません。

元の[MITライセンス](../../../LICENSE)を維持しています。AI支援をソース適応、スクリプト、ドキュメントに使用しました。実機でのビルドと測定はリポジトリ所有者が行いました。

ソフトウェア側の検証範囲は[verification.txt](verification.txt)、全体の経緯は[最適化まとめ](../OPTIMIZATION-SUMMARY-ja.md)を参照してください。
