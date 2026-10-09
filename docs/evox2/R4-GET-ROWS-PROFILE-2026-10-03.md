# r4 Vulkan GET_ROWSのtensor別診断

目的: 64k TGのGET_ROWS合計約2.48 ms/tokenを分解し、pool cache読出し、
QSA選択処理、その他のgatherを区別する。今回の変更は計測ラベルとtensor名だけで、
カーネル・fusion条件・graphの演算接続・計算値は変更しない。

## 診断スイッチ

`GGML_VK_PERF_GET_ROWS_DETAILS=1` を通常のVulkan perf loggerと併用する。
未設定・`0`・その他の値では従来のGET_ROWS合算ラベルを維持する。
perf loggerが無効なら詳細計測も動作しない。設定はbackend context初期化時に読み込む。

必要な設定:

```powershell
$env:GGML_VK_PERF_LOGGER = '1'
$env:GGML_VK_PERF_LOGGER_FREQUENCY = '1'
$env:GGML_VK_PERF_GET_ROWS_DETAILS = '1'
Remove-Item Env:GGML_VK_PERF_LOGGER_CONCURRENT -ErrorAction SilentlyContinue
```

concurrent loggerでは複数演算をまとめて計時するため、詳細スイッチを無効化して
警告を出す。concurrentは`0`でも「設定あり」扱いなので、必ず未設定にする。
用意したplanはこの設定・復元を自動で行うため、手動設定は不要。

GET_ROWS行は次の形式になる（以下は形式例で、実測値ではない）。

```text
GET_ROWS dst{name="indexer_pool_cached_rows-0" op=GET_ROWS type=f32 ne=(...) nb=(...) view_offs=0} src0{...} ids{...}: 1 x ... us = ... us
```

`dst`、`src0`、`ids`にtensor名・演算名・型・全4次元の形状とbyte stride・view offsetを
含める。GPUデータ自体やメモリアドレスは読み出さない。
元のGET_ROWS合算行へも重複加算する方式ではなく、同じtimestampを詳細キーで集計する。
各詳細行を足せばGET_ROWS全体を得られ、Total timeにも一度だけ加算される。
名前内の制御文字は`?`に置換し、引用符とbackslashはescapeして1行を維持する。

既存のfusionは維持し、融合演算がGET_ROWSから始まる場合は`TOPK_QSA`等のprefixを残す。
その行はfusion全体の時間であり、純粋なGET_ROWS時間とは区別して集計する。
今回のr4 pool-domain経路では旧TOPK_QSA融合は前回ログに出ていない。

## QSAの名前付け

reshape前の実GET_ROWS nodeに、callbackを追加せずmetadata名だけを付ける。

| dst名（末尾はlayer番号） | 用途 |
|---|---|
| `indexer_pool_raw_rows-N` | 更新対象poolのraw key読出し |
| `indexer_pool_cached_rows-N` | 保存済みpooled keyの読出し |
| `indexer_selected_pool_rows-N` | top-k poolからtoken index列を取得 |
| `indexer_selected_score_rows-N` | 選択poolのscoreを取得し可視性を判定 |
| `ple_embedding_rows` | OriginalのPLE embedding読出し |

これ以外のGET_ROWSも詳細化する。未命名nodeは既存graph構築時の`node_N`等と
入力tensor名・shapeで追跡する。CPUに配置された演算はVulkan loggerには出ない。
したがってPLEの行がないことだけで、その演算が存在しないとは判断しない。

## ビルドと64k計測

COMMON-001導入前の比較用として別build directoryを残す。

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r4
.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir build-vulkan-r4-getrows `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

`local.psd1` の `Builds` 内に追加する。登録例は`local.example.psd1`にもある。

```powershell
R4GetRowsVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r4\build-vulkan-r4-getrows\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

計測はOriginal・64k・生成128の **1回**。
MoEは旧方式 `GGML_VK_MOE_LEGACY_TILE_SELECTION=1` に固定し、tile詳細ログはOFF。
前回profileのB1-legacyを演算合計の参考にする。COMMON-001導入後もMoE条件を固定する。

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r4-getrows-64k.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan
```

開始時に`GET_ROWS tensor timing details = on`、MoEが`legacy-token-count`と記録される。
conditions.jsonにも詳細スイッチが残る。ログ一式はlocal.psd1のLogRootへ出る。
既存clean/MoE比較planには詳細フラグを消す設定を追加し、次の通常計測への持越しを防ぐ。

## 集計方針・次の実装

- warmup・PP・TGを分け、TGは初回decodeを除くsteady区間を前回と同じ方法で集計。
- まずGET_ROWS全体の時間/回数を確認し、上記4種類×layerとその他へ分類する。
  一部だけの合計を全GET_ROWSと誤認しない。
- 詳細出力でCPU側logging量が増えるので、表示TG tok/sは通常速度と比較しない。
  GPU時間も診断値として扱い、改善後の評価はlogger OFFで行う。
- **次の移植はCOMMON-001を先行する（2026-10-03のユーザー指定）。**
  r3/r4間でOriginal/PLE16の条件を揃えるため、現行loaderを保持してsplit-PLE16対応の
  不足分を移植し、両backendのloadと64k動作を確認する。
  本診断のbuild/logを導入前として残し、導入後は同じMoE条件で比較する。
- TGの修正やVULKAN-002/COMMON-005の移植は、その比較条件を揃えてから優先度を決める。
  今回はCOMMON-001自体のソース移植は行っていない。

## 検証状況

実ソースからlogger class・ラベル生成・print関数を抽出し、実ggml.hとともにC++で検証。
tensor別分離、既定ラベル維持、Total time維持、重複加算なし、fusion prefix、
名前escapeとnull metadataを確認した。GPU計算の検証ではない。
PowerShellの実runnerでPlanOnlyが1回に展開すること、環境設定・自動収集・
他planでの解除も確認。後続のWindowsビルド・実GPU profileは以下の提供ログで確認した。

## 2026-10-03 14:29 JST: 導入前64k診断結果

ZIP: `20261003-142128-968-qwen38-r4-getrows-64k.zip`。
子run: `20261003-142130-807-cli-vulkan-b11377-ctx65536-36b2b463f2e2`。

- b11377 / `acf7fea2b`、manifest Source.Dirty=false、Status OK / exit0。
- 実行ファイルSHA-256:
  `c7996060fbf5cab1c522644c313405307bab0c11a6c5005cecc4b278f59dc521`。
- Original・61,789 prompt tokens・128 generated tokens。
  前回MoE profileのB1-legacyとModelIdentity/InputIdentityが一致し、
  EffectiveConditionの差はExecutableと診断用Environmentのみ。
- MoE legacy=1、GET_ROWS details=1、perf logger=1/frequency1、concurrent未設定。
  起動ログでも詳細ON・legacy選択を確認。
- 190個のtiming blockを解析し、行合計とTotal timeの一致を丸め範囲で確認。
  warmup2、PP61（1024×60+349）、decode127。最初のdecodeを除く126をsteady集計。

### TG: cached pool gatherがGET_ROWSの約67%

単位はsteady平均ms/token。全GET_ROWS 124回/tokenを以下で網羅した。

| 分類 | 回数/token | ms/token | GET_ROWS内割合 |
|---|---:|---:|---:|
| `indexer_pool_cached_rows-*` | 12 | 1.66209 | 66.82% |
| recurrent state `cache_s_l*` | 36 | 0.59045 | 23.74% |
| recurrent state `cache_r_l*` | 36 | 0.10929 | 4.39% |
| `indexer_selected_score_rows-*` | 12 | 0.04216 | 1.69% |
| `indexer_selected_pool_rows-*` | 12 | 0.03608 | 1.45% |
| `indexer_pool_raw_rows-*` | 12 | 0.03014 | 1.21% |
| `cache_ple_r_l1` | 1 | 0.01171 | 0.47% |
| 出力選択（attn_output / l_last / hc_inject） | 3 | 0.00535 | 0.22% |
| 合計 | 124 | 2.48727 | 100% |

分類は行頭の実演算ラベルを使う。src0 metadataの`op=MUL_MAT`を検出して
GET_ROWSをmatmulへ誤分類しない。今回のGET_ROWS行にはfusion prefixはなかった。

全GPU演算のsteady平均は40.671 ms/token（中央値40.504、範囲40.187〜41.329）。
GET_ROWSは全体の約6.12%、cached pool gatherだけで約4.09%を占める。
前回legacy profileの40.582 ms/token、GET_ROWS 2.48236 ms/tokenと近い水準で、
詳細化後も集計値は概ね整合する。表示上のTGは3.90 tok/sだが、詳細ログの大量出力と
同期を含むprofileの値であり、通常推論の退行としては扱わない。

### キャッシュがないのではなく、読み出し・型変換が残る

全12 QSA layerでcached gatherの形状は次のとおり。

- src0: `cache_idx_k_lN (view)`、f16、`ne=(128,65536,1,1)`。
  byte stride `nb=(2,512,33554432,33554432)`、view offset256。
- ids: i32、`ne=(15488,1,1,1)`。
- dst: `indexer_pool_cached_rows-N`、f32、`ne=(128,15488,1,1)`。
  `nb=(4,512,7929856,7929856)`。

`kpool_access`のraw key | pooled key共有storageからpool_cellsでgatherし、
連続したf32のindexer入力へ展開する処理と一致する。dstの論理サイズは1 layerあたり
約7.56 MiB、12 layer合計90.75 MiB/token。これは出力tensorサイズの合計であり、
物理DRAM転送量やGPU帯域の実測ではない。

一方raw更新側はdst `ne=(128,4,1,1)` で12回合計0.03014 ms/token。
差分更新は小さく、全poolのnorm/RoPE再計算に戻っている証拠はない。
保存済みpoolの読出しが残存コストとして特定できた。
今後の修正候補はこのgatherを減らすcache配置/参照方法やカーネルであり、
COMMON-004全体の無条件再移植ではない。可変cell配置・sequenceの正しさを保つ必要がある。

1.662 msを全て除去できるとは限らず、r3とのTG差全体の原因や改善量が確定したわけではない。
旧r3のQSA融合/選択処理との構成差もあるため、単独差分のA/Bで評価する。

### PPと次の作業

PP GPU合計231.606秒、MoE47.483秒、FA109.068秒。
GET_ROWS全体は1.334秒（PP GPU全体の約0.58%）で、そのうち
selected scoreが1.049秒、cached pool gatherは0.061秒。
cached gatherは今回のTG側の候補であり、PPの主要ボトルネックとは分ける。

導入前の診断ゲートは完了。**次は指定どおりCOMMON-001を先行**し、
Original/PLE16を同じr4で比較できる状態を作る。追加のGET_ROWS計測や
gather最適化は先行させず、このbuild/logをCOMMON-001導入前の基準として保持する。
本更新は結果の分析とドキュメント更新のみ。
