# B12651 D0-4C — IQ4_NL GET_ROWSの既存モデル回帰確認

2026-11-27 JST。AのGemma 4 32kは1回実行し、機能・終了監査とも合格。BのUnslothOriginal 4kはAの終了後にモデルと容量を照合し、ロード時の物理メモリ逼迫が懸念されるため開始前に見送った。Bの新ビルドでの動作と実際のバッファ配置は未確認。

## 基準と実行条件

| 項目 | 照合結果 |
| --- | --- |
| 製品基準 | `9ae819d5be4fe9861d2aa8547983aed801c437ac` |
| 文書・標準ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216`。実験ブランチの標準Matrix、Measure、モジュールと一致 |
| 実行時の実験HEAD | `experiment/hip-iq4nl-ple160` の `a4e7adabef20f24bb4ae85abb982180ea3b48704`。GitHub、実機worktree、追跡先が一致し、作業ツリーはクリーン |
| 修正版 | b12696 Release、ビルド元 `044be892e12bffdfd06cfb698bf55e54582ae63a`、CLI SHA-256 `98da309636095a3be2d28b26fb19194968607b54b9cc042565875774a9dda6bf` |
| 実行環境 | Windows 11、ROCm0 Radeon 8060S／gfx1151、UMA 96 GiB、Adrenalin 26.11.2（32.0.32029.2010）、TheRock 10.0.0、P-MODE Performance |
| 来歴 | `BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。HIP DLL SHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c`、マニフェスト SHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f` |

AはAdrenalin更新後の計測5のGemma 4 31B IT QAT Q4_0。単一GGUF `gemma-4-31B_q4_0-it.gguf`、17,650,999,456 byte、mtime `2026-07-14T13:14:45.1108976Z`。入力 `nlp-survey-ch3-d3-b1.txt` は145,547 byte、SHA-256 `1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601`。Measureの `Arguments`、モデルと入力の識別情報は計測5と一致。CLIは `w54` の修正前ビルド（ソース `20f48bfe162d8d886b9f5fea7ad6d7df91eb3266`）から `w55` の修正版に置き換えた。 [Adrenalin更新後の計測5](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/ADRENALIN-UPDATE-COMPARISON-20261126.md) · [Gemmaの入力と既存条件](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/UPSTREAM-B12651-PP-TG-20261124.md)

Context 32,768、GPU layers 999、CPU MoE 0、threads 4、batch 2048、ubatch 1024、K/V f16、FA auto、MTP/Fit/reasoning OFF、temperature 0、top-p 0.8、seed 1234、生成上限256、ログレベル4。warmupとJinjaを使用し、prompt cache 0。ResourceMonitor 2秒、ADLX 2000 ms、RAM詳細250 ms、詳細回復許容差128 MiB。PlanOnlyで `D04C-Gemma-M001` だけを確認し、次のMatrix呼び出しを1回実行した。

```powershell
Set-Location 'C:\llama-build\automation\w55'
$plan = 'C:\llama-build\_logs\codex\d0-4c-audit-20261127\CLI.psd1'
$config = 'C:\llama-build\_logs\codex\d0-4a-audit-20261127\cli-local.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -LocalConfig $config -OnlyJob cell-5 -MaxRuns 1 -RunIdPrefix D04C-Gemma -StopOnError
```

## A — Gemma 4 31B IT QAT Q4_0

| 項目 | 計測5 | D0-4C |
| --- | ---: | ---: |
| 入力／生成トークン | 29,379／256 | 29,379／256 |
| PP tok/s／時間 | 186.48／157.547秒 | 188.79／155.614秒 |
| TG tok/s／時間 | 9.01／28.297秒 | 9.02／28.269秒 |
| CLIプロセス時間 | 190.489秒 | 194.813秒 |
| テンソルロード開始 → context構築開始 | 3.141秒 | 9.364秒 |
| GPU層 | 61/61 | 61/61 |
| 独立CPU／CPU_Mappedモデル | 行なし | 行なし |
| ROCm0／ROCm_Hostモデル | 16,818.28／1,102.50 MiB | 16,818.28／1,102.50 MiB |
| ROCm0 KV／compute | 4,160.00／404.05 MiB | 4,160.00／404.05 MiB |
| ROCm_Host compute | 152.05 MiB | 152.05 MiB |
| 実行中の物理空き最小／commit最大 | 23.879／31.233 GiB | 24.095／31.432 GiB |
| ADLX VRAM最大（生ログのMB） | 22,182 | 22,187 |

PP +1.24%、TG +0.11%。5%を超える速度低下は観測されなかった。正規化stdoutの差はビルドバナー1行で、日本語の応答本文は一致した。応答は評価表現辞書、文書分類、評価文、要素組の各課題を要約した。ロード区間は6.224秒長かった。ファイルキャッシュやOSの稼働状態は揃えておらず、ロード差の再現性と原因は未確認。

| 終了監査 | D0-4C |
| --- | --- |
| CLI／Measure／Matrix／SSH | ネイティブ終了0、Measure OK、Matrix 1/1 OK・Complete、SSH 0 |
| 開始／終了の物理空きRAM | 26.463 → 26.440 GiB |
| 開始／終了のcommit | 8.176 → 8.256 GiB（+0.080 GiB、上限127.647 GiB） |
| WDDM Dedicated／Shared | 0.461／0.072 GiBで前後同値 |
| RAM／GPU詳細の初回回復 | `WithinTolerance`／`WithinTolerance`、RAM空き差 −14.68 MiB |
| P-MODE／OS起動 | Performanceのまま。起動時刻 `2026-11-26T11:45:51.5000000Z` で一致 |
| イベント／残留 | System 69919 → 69919、Application 44188 → 44188。差分0件、CLI・監視・Matrixの既知PIDとADLX名の残留なし |

RAM詳細802件とADLXは `Complete`。通常監視79件ではネイティブRAM、対象プロセス、システムPerfMonが全件 `Complete`。PID別GPUは63件 `Complete`、16件 `Partial`。背景CPUサンプルにも制約があり、通常監視の総合は `Partial`。欠損は実測ゼロに置き換えていない。

## B — UnslothOriginal 4kの開始判断

元の4k実行記録から joined PLE の先頭シャードを特定。実機の3ファイルのサイズは10,946,624／49,567,921,344／32,382,955,968 byteで、先頭のmtimeも保存記録と一致した。計画条件はD0-3の `-AllocationOnly`、Context 4,096、`Reply with the word OK.`、生成上限32、同じ監視・推論オプションで、モデルだけを `UnslothOriginal` に変更。 [D0-3の短文条件](B12651-D0-3-HIP-IQ4NL-GETROWS-20261127.md)

- 既存のOriginal 4kではCPUモデル27,465.95 MiB（26.822 GiB）、ROCm0モデル50,191.17 MiB、ROCm_Hostモデル497.31 MiB。A終了後の再取得でWindows可視RAMは31.647 GiB、空きは26.544 GiB。CPUモデルの既知のサイズだけで空きを約0.279 GiB上回る。これはホスト割当の比較であり、GPUメモリとの合算ではない。全バイトの同時物理常駐を仮定しなくても、同じUMA 96 GiBの過去Originalではロード中に0.492 GiBまで低下し、同規模CPUバッファの旧PLE16短文でもcontext構築前に6.563 MiBまで低下した。Context 4kでKVを抑えてもロード対象のjoined重みは同じ。 [Stage 1の配置・実測](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/B12651-STAGE1-COMMON001-20261124.md) · [短文ロード時の観測](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/automation/B12651-MODEL-LOAD-INVESTIGATION-20261126.md)
- 旧4kのstderrは `per_layer_token_embd.weight` の型をIQ4_NL、PLE head幅を160と報告し、`ROCm_Host` が従来拒否されてCPUへ配置された記録がある。joinedは入力レイヤーで、ホストバッファが候補になる。今回の対応拡張でその候補が選ばれる可能性があり、ROCm_Hostの確保はページ固定を試み、失敗時はCPUにフォールバックする。CPU配置維持とROCm_Hostへの変更の双方で、現環境のロード時安全余裕を確認できなかった。Bのネイティブプロセスを起動せず、配置は実測していない。 [入力レイヤーとホストバッファの選択](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/044be892e12bffdfd06cfb698bf55e54582ae63a/src/llama-model.cpp#L1259) · [ホストバッファの確保](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/044be892e12bffdfd06cfb698bf55e54582ae63a/ggml/src/ggml-cuda/ggml-cuda.cu#L1770)

## 静的な回帰範囲とD0の確認結果

製品基準 `9ae819d5be4fe9861d2aa8547983aed801c437ac` から実行時HEAD `a4e7adabef20f24bb4ae85abb982180ea3b48704` までの製品コード差分は、CUDA/HIP共有の `ggml/src/ggml-cuda/{dequantize.cuh,getrows.cu,ggml-cuda.cu}`。C++テストの差分は `tests/test-backend-ops.cpp`。Vulkan、CPU、モデル定義、loaderへの直接変更はない。

- 幅が256の倍数なら従来の32スレッド／256要素経路。同じブロック内のscale、codebook、書き込み配置を維持し、D0-2Bの幅256回帰ケースはCPU参照と一致。IQ4_NLの支持判定には、整列幅も含めて型・stride・次元の安全条件を追加した。
- 非256整列の正当な幅は、4スレッドで32要素を処理する。幅160は5ブロック。IQ4_NL以外の型は従来の対応分岐を通り、共通カーネルのテンプレート既定値は `QK_K`（256）を保持する。
- ROCm0の限定テスト再検証は幅32、160連続、160 padded、256、288の全5件でCPU参照OK、5/5、終了コード0。NVIDIA CUDAでのビルド・実機実行は未検証。 [D0-1静的レビュー](B12651-D0-1-HIP-IQ4NL-GETROWS-20261126.md) · [D0-2B再検証](B12651-D0-2B-RETEST-HIP-IQ4NL-GETROWS-20261127.md)

IQ3 PLE16は4k、64k、128k、256kで正常応答し、独立CPUモデルバッファの行が消失。ROCm0バッファ増分27,465.95 MiBは16 head合計27,465.94 MiBと表示精度内で一致した。64k同条件ではロード中の最小空きRAMが14.117 MiBから約24.53 GiBへ改善し、1 GiB未満の観測は0件。応答本文は一致し、PPは+0.11%、TGは−1.45%だった。 [D0-3配置](B12651-D0-3-HIP-IQ4NL-GETROWS-20261127.md) · [D0-4A 64k比較](B12651-D0-4A-HIP-IQ4NL-GETROWS-20261127.md)

後続の高速化調査に引き継ぐ固定入力の基準値。

| IQ3 PLE16 | 入力／生成トークン | PP／TG（tok/s） | PPの64k比 |
| --- | ---: | ---: | ---: |
| 64k | 61,789／256 | 408.72／21.81 | 100% |
| 128k | 126,253／256 | 303.23／17.54 | 74.19% |
| 256k | 255,181／256 | 199.25／12.62 | 48.75% |

長コンテキストでの低下はD0適用後も観測された。原因、個別headの実バッファ名、CPU/GPU間の転送量、新規GET_ROWSカーネルの単体性能、反復時の性能再現性は未検証。 [D0-4B長文の結果](B12651-D0-4B-HIP-IQ4NL-GETROWS-20261127.md)

## 採用判定案とD0-5での扱い

**PLE16向けの採用候補として維持し、製品への採用確定は保留する。** D0の対象であるROCm PLE16の機能改善は確認した。joined PLEの回帰は今回未成立で、特に、同じ幅160のjoined tensorで拡張された対応判定がROCm_Hostを選び得る点を、統合前に判断する必要がある。既存の回復閾値を維持できる条件を運用者が別途承認したうえで、joinedの配置・ロード・短文応答を評価する。

D0-5で別途承認を受けた場合は、製品基準からの3つの共有バックエンドファイルとC++の限定回帰テストを、対象の製品ブランチに分けて適用する。実験コミット `044be892e12bffdfd06cfb698bf55e54582ae63a` にはレビュー文書もあるため、適用対象はパスで指定する。実験専用の監督モジュール、起動スクリプト、ダミーテスト、計測plan／派生データは実験ブランチに保持する。確定した採用記録を共有する場合は別の文書専用差分としてレビューする。D0-4Cで作業を停止した。

## 生ログ

実機の `C:\llama-build\_logs\codex` 配下に保全した。

- 計測5 Measure `20261126-214153-491-cli-rocm-b12696-ctx32768-b1fdf75723fd`、Matrix `matrix\20261126-214110-247-adrenalin-pre-cli-20261126`。
- D0-4C A Measure `20261127-091606-545-cli-rocm-b12696-ctx32768-e325560f7e8d`、Matrix `matrix\20261127-091522-643-d0-4c-regression`。条件、結果JSON、stdout／stderr、RAM詳細、通常監視、ADLXを保存。
- D0-4C監査 `d0-4c-audit-20261127`。Aの来歴、前後の資源・イベント差分、残留照合は `gemma`、Bのシャードと開始判断は `original-budget.json`。
- 参照Original 4k `20261124-165852-574-cli-rocm-b12671-ctx4096-a54242f85d44`。
