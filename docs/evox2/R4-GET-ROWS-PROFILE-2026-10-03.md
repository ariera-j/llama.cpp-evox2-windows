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
他planでの解除も確認。Windowsでの全体ビルド・実GPU profileは未実施。
