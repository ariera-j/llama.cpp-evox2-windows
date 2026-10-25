# r4 Vulkan 64k profiling — 2026-10-03

## 対象と集計方法

- 入力ZIP: `20261003-113858-285-cli-vulkan-b11372-ctx65536-f5498bca2f96.zip`
- バイナリ: b11372 / `94b877457`。clean baselineとSHA-256一致。
- Original UD-IQ3_XXS、UMA 96GB、f16 KV、batch 2048 / ubatch 1024、threads 4。
- MTP OFF、生成上限128、`GGML_VK_PERF_LOGGER=1`、frequency=1、concurrent未設定。
- Status OK / exit 0。入力61,789 tokens、生成128 tokens、graph reuse 127。
- 所要328.019秒。profiler有効時PP 235.90 / TG 7.68 tok/s。
  通常baselineのPP/TGと直接比較しない。

`stderr.log`から190個の完結したVulkan Timingsブロックを集計。
指数表記（例 `2.06788e+06`）を含む数値を解析し、各ブロックの演算時間合計と
Total timeの一致を表示丸めの範囲で確認した。

- warmup: 2ブロック、除外。
- PP: 61ブロック = 1024 tokens × 60 + 349 tokens。合計61,789 tokensと一致。
- decode: 127ブロック。最初の1ブロックを移行時として除外し、残る126をsteady集計。
  最初の出力tokenは最後のprefillのlogitsから得るため、128生成に対して127 decodeは整合する。

以下の時間はprofilerが出すGPU演算時間の合計。実行を同期させるloggerの測定であり、
通常実行のframe時間・CPU時間・実ユーザー待ち時間の内訳とは同一ではない。

## PP: Attentionが43%、末尾のフルubatchでは63%

| 演算分類 | PP全体の合計秒 | GPU演算時間に占める割合 |
|---|---:|---:|
| FLASH_ATTN_EXT | 108.408 | 43.04% |
| MoE matmul（MUL_MAT_ID系） | 63.685 | 25.28% |
| その他matmul | 37.461 | 14.87% |
| CONCAT | 10.255 | 4.07% |
| その他 | 32.084 | 12.74% |
| 合計 | 251.893 | 100% |

PP wall timeは261.934秒。GPU演算合計との差を、そのままCPUボトルネック時間としない。

| KV深さ | 今回のquery数 | GPU演算合計ms | FA合計ms |
|---:|---:|---:|---:|
| 1,024 | 1,024 | 2,067.88 | 17.768 |
| 16,384 | 1,024 | 2,891.96 | 558.659 |
| 32,768 | 1,024 | 4,285.98 | 1,848.23 |
| 49,152 | 1,024 | 5,863.19 | 3,358.51 |
| 61,440 | 1,024 | 6,760.22 | 4,227.33 |
| 61,952 | 349（端数） | 2,560.46 | 1,142.63 |

最後のフルubatchでFAは62.5%。端数349-tokenの行は1024-token行と直接速度比較しない。

### sparse FA分岐についての追加確認

`ggml/src/ggml-vulkan/ggml-vulkan.cpp::ggml_vk_flash_attn`では、
`gqa_ratio`は初期値1で、query数 `N <= 8` の場合にGQA最適化条件を判定する。
`sparse`の条件は `gqa_ratio > 1` またはscalarかつ `N == 1` を要求する。

今回のPPはN=1024または349なので、このsparse compact経路には入らない。
全KV形状の通常FAを使う構造であり、maskによるtile skip等の最適化は別途あり得る。
ログにfull-K/V shapeがあるだけでdenseと判断したのではなく、ソースのdispatch条件を
今回のquery数に適用した結論である。

以前の「upstreamにはper-row sparse FAがある」という記述は機能の存在を述べたもの。
今回のPPでそれが使われているという意味ではない。r2 grouped-unionを再評価する
根拠は強まるが、このprofile単独ではr3→r4の64k PP低下の原因は確定しない。

## TG: 差分pool更新を支持、ただしr3との性能差は未解決

steady 126ブロックのGPU演算時間合計:

- 平均40.597 ms/token、中央値40.492、最小40.273、最大41.114。
- 初回decodeは42.591 msで、steady集計から除外。

| 演算分類 | 平均ms/token | 割合 |
|---|---:|---:|
| その他matmul | 20.981 | 51.68% |
| MoE matmul | 8.825 | 21.74% |
| GET_ROWS全体 | 2.483 | 6.12% |
| FLASH_ATTN_EXT | 1.336 | 3.29% |
| その他 | 6.972 | 17.17% |
| 合計 | 40.597 | 100% |

`GET_ROWS`は1 tokenあたり124演算がまとめられた値で、pool cache以外も含む。
2.483 ms全体をpool cacheのコストや、r3との差として扱ってはいけない。

pool差分更新に関する観察:

- pool-key normに対応する `RMS_NORM_MUL RMS_NORM(128,1,1,1)` は12回/token、
  合計約0.0397 ms/token。
- QSA query側は `(128,4,1,1)`。全15,488 poolをnormする形状は出ていない。
- CONT全体は約0.1885 ms/token、ROPEとROPE_VIEW_SET_ROWS合計は約0.1522 ms/token。
- TOP_Kは `K=512 (15488,1,1,1)`、12回/token、約0.2830 ms/token。
  block/pool領域で選択する新経路の実行も確認できる。

ソースのnew-pool更新・persistent slot再利用と合わせ、今回の単一sequence decodeで
旧来の全pool norm/RoPE再計算を繰り返す挙動は支持されない。
COMMON-004の機能代替には実行時の裏付けが加わった。ただしcache-safeフラグを
直接記録したわけではなく、r3 COMMON-004と同等速度だという証明でもない。

保存済み資料のVulkan profileはr2 union OFF 44.18 ms/token、
r3 COMMON-001のみ59.13 ms/tokenが主な比較値で、COMMON-004適用前である。
これを今回の約40.60 msと比較して、COMMON-004適用後のTG低下まで説明したとはしない。
通常実行のTGとprofiler GPU時間も混ぜない。

## 次の最小計測（取得済み）

以下のCOMMON-004版ログは取得済み。
[比較結果と更新した次の順序](R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md)を参照。
以下は実行条件の記録として残す。

128kを増やす前に、`Common004Vulkan` + `UnslothOriginal` + 64k + 生成128を
同じlogger条件で1回取得する。ユーザー提供local.psd1にこのbuild keyは登録済み。
これによりモデルlayoutを揃えたr3/r4の演算差を比較でき、PPとTGを1回で観察できる。
PLE16との差は、この比較で必要になった場合に別途調べる。

r3バイナリの実際のversion/manifestをログで確認する。ディレクトリ名だけで
COMMON-004適用状態を確定しない。旧ソースへの巻き戻し・再ビルドは不要。
通常速度の5〜6%差の再現性は、このprofileの差と分けて確認する。

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r4

$profileEnv = (Import-PowerShellDataFile `
    .\tools\evox2\benchmark\configs\qwen38-r4-clean.psd1
).Defaults.Environment
$profileEnv['GGML_VK_PERF_LOGGER'] = '1'
$profileEnv['GGML_VK_PERF_LOGGER_FREQUENCY'] = '1'
$profileEnv['GGML_VK_PERF_LOGGER_CONCURRENT'] = $null
$profileEnv['LLAMA_QSA_NO_POOLED_CACHE'] = $null
$profileEnv['LLAMA_QSA_POOLED_MAX_TOKENS'] = '32'

$savedEnv = @{}
foreach ($name in $profileEnv.Keys) {
    $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $profileEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $profileEnv[$name], 'Process')
    }
    .\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
        -BuildKey Common004Vulkan `
        -ModelKey UnslothOriginal `
        -InputKey 64k `
        -Context 65536 `
        -GenerationTokens 128 `
        -KvType f16 `
        -Batch 2048 `
        -UBatch 1024 `
        -Threads 4 `
        -FlashAttn auto `
        -ExpectedBackend Vulkan `
        -ResourceMonitor `
        -ExtraArgs @('-tb', '4', '--ctx-checkpoints', '0t')
}
finally {
    foreach ($name in $savedEnv.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process')
    }
}
```

ログはr4 wrapperのLogRootへ出る。r3バイナリ＋r4計測スクリプトという組合せは意図的。
condition/resultにバイナリの実identityが残り、推論ソースは変更しない。

## 状態

集計・ソース照合のみ。推論コードは未変更。
