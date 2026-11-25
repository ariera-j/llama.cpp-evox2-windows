# PR #30904 移植前調査（2026-11-25 JST）

**IQ3 PLE16 と ROCmFP4 FAST PLE16 の両方で、IQ3_XXS（GGML tensor type ID 18）は 0 テンソルでした。** Vulkan TG32 の通常 MatVec と MatVec ID でも、対象型の記録は各 0 件です。この2モデルと計測条件では PR の対象カーネルが実行されず、対象カーネルの高速化率は評価できません。

## 比較対象とビルド

| 対象 | 識別情報 |
|---|---|
| Baseline ソース | `codex/vulkan-manifest-cpu-variants-20261124` の `f4f1aa3e85124fed75a891ec63a1504536049eff`。b12651 系に COMMON-001、ROCmFPx Vulkan 対応、ビルドマニフェスト修正を含む |
| 実行した既存バイナリ | `build-s2v/bin/Release/llama-bench.exe`、b12676、実装コミット `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`。このコミットから Baseline HEAD までの差分は Stage 2 記録とビルドラッパー関連の3ファイルで、製品コードの差分は 0 |
| 対象 PR | `c1d245bc3d1c416f74f1e108b0f60fa2a699dbf1`（2026-11-12 UTC 修正版）。親は `f5027fb21307eb264aed483242603d68c87b0fe3`。親から対象コミットまでの差分を照合 |
| 実機 | Radeon 8060S / AMD proprietary Vulkan `26.8.1 (LLPC)`。Vulkan の DEVICE_LOCAL ヒープ `103079215104` bytes（96 GiB）を当日確認 |

実機 HEAD の作業ツリーには前回の環境文書更新1件が未ステージで存在した。ソース比較は HEAD の Git blob を使用し、実行ファイルと SDK は既存のものを使用した。保存済みマニフェストは `BuildIdentity.Status=Verified`。同マニフェストの `CpuAllVariants=true` は旧記録の既知の誤表示で、`build-s2v/CMakeCache.txt` の値は `GGML_CPU_ALL_VARIANTS:BOOL=OFF`。ビルドの Clang は 22.1.3、Vulkan SDK は 1.4.357.0、LLVM OpenMP は 22.1.8。 [Baseline](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/f4f1aa3e85124fed75a891ec63a1504536049eff) · [PR の対象コミット](https://github.com/ggml-org/llama.cpp/pull/30904/commits/c1d245bc3d1c416f74f1e108b0f60fa2a699dbf1) · [保存済みマニフェスト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/logs/build-manifest.json) · [実測ハッシュ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/logs/artifact-hashes.json)

## 差分と競合

| ファイル | c1d245b の変更 | Baseline との関係 |
|---|---|---|
| `ggml-vulkan-types.h` | 通常 F32/F16 入力用 TPB=8 パイプライン配列2本、workgroup 区分別の閾値配列、`dmmv_tpb8_max_cols=1` | 既存 DMMV 配列と同じデバイス構造体に追加。Baseline に同等の IQ3_XXS TPB 選択はない |
| `ggml-vulkan.cpp` | 通常 IQ3_XXS の登録で TPB=16 を明示し、1列用 TPB=8 を登録。通常の selector に `k` 閾値を追加 | Baseline の同じ登録ブロックには ROCmFP4/FAST/FPx がある。IQ3_XXS 用パイプラインのみが変更対象。Q8_1 選択と ID 側の登録・selector は PR の変更範囲外 |
| `vulkan-shaders/mul_mat_vec_iq3_xxs.comp` | 特殊化定数 ID 3 に `TPB`（既定 16）を追加。2個の u8 格子インデックスを u16 でロードし、符号付き格子を列ループ外で求める。1〜6列は局所 FMA 蓄積へまとめ、7〜8列は逐次スケーリングを維持 | Baseline の同ファイルは PR 親とバイト一致。既存コードも scale/sign の読み込みには packed16 を使う。今回追加される packed16 は格子インデックス用 |

指定コミットの patch を Baseline の3ファイルを複製した一時ディレクトリで `git apply --check --verbose` にかけ、全ハンクが通過した。ヘッダーと C++ は周辺の実装差で行番号のずれがあった。実機への適用とビルドは実施していない。PR 本文の概要より修正版コミットの差分を優先した。 [PR 本文](https://github.com/ggml-org/llama.cpp/pull/30904) · [適用可否ログ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/logs/patch-check.txt)

## GGUF のテンソル構成

| モデル | GGUF ファイル bytes | テンソル数 | テンソル payload bytes | IQ3_XXS（ID 18） |
|---|---:|---:|---:|---:|
| IQ3 PLE16 | 81,961,816,672 | 1,239 | 81,950,791,260 | 0 |
| ROCmFP4 FAST PLE16 | 93,484,237,760 | 1,239 | 93,473,212,260 | 0 |

両方とも GGUF v3、`general.architecture=qwen4exp`。IQ3 PLE16 のファイル全体の `general.file_type` は 23 で、llama-bench はモデル種別を `IQ3_XXS` と表示する。個々のテンソル型はヘッダーの tensor descriptor に記録される。FAST の `general.file_type` は 103。

| 主なテンソル（層番号省略） | shape（GGML ne[0] から） | IQ3 PLE16 | FAST PLE16 |
|---|---|---|---|
| Attention `attn_q/k/v/output.weight` | Q `2560×12288`、K/V `2560×512`、Out `6144×2560` | 各 12 Q6_K | 各 12 Q6_K |
| Attention `attn_qkv/gate.weight` | QKV `2560×10240`、Gate `2560×6144` | 各 35 Q6_K + 1 Q8_0 | 各 36 Q6_K |
| 再帰 Attention 出力 `ssm_out.weight` | `6144×2560` | 36 Q6_K | 36 Q6_K |
| MoE `ffn_gate_exps.weight` / `ffn_up_exps.weight` | `2560×640×512` | 各 47 IQ2_S + 1 IQ3_S（層2） | 各 48 Q4_K |
| MoE `ffn_down_exps.weight` | `640×2560×512` | 48 IQ4_NL | 48 Q4_0_ROCMFP4_FAST |
| 共有 `ffn_gate_shexp.weight` / `ffn_up_shexp.weight` | `2560×640` | 各 47 Q6_K + 1 Q8_0 | 各 48 Q6_K |
| 共有 `ffn_down_shexp.weight` | `640×2560` | 48 Q8_0 | 48 Q8_0 |

テンソル全件の名前、型、shape、要素数、payload bytes、オフセットは CSV に収録した。容量は GGML のブロックサイズとブロック当たりのバイト数から計算し、各テンソル末尾と次のデータオフセットの差が GGUF アラインメント未満であること、および payload 総和と llama-bench の `model_size` が一致することを検証した。 [テンソル CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/tensors.csv) · [GGML 型 ID](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/include/ggml.h#L217)

## IQ3_XXS MatVec の実行経路

- **通常 MUL_MAT** は1列、またはデバイスの MatVec 列数制限内で追加のバッチ次元がない場合に MatVec を選ぶ。量子化の経路は `ggml_vk_mul_mat_vec_q_f16` → `ggml_vk_get_dequantize_mul_mat_vec`。IQ3_XXS は Q8_1 integer-dot の許可リストに含まれず、F32/F16 入力の dequant MatVec を使う。 [通常の分岐](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L8371)
- **MoE MUL_MAT_ID** は対象型で `ids->ne[1] <= 8` の場合に `ggml_vk_mul_mat_vec_id_q_f16` → `ggml_vk_get_dequantize_mul_mat_vec_id` へ進む。IQ3_XXS はここでも Q8_1 対象外で、ID 用の F32 入力パイプラインを使う。TG では `ids->ne[1]=1`。ログの ID 行にある `n=10` は出力のエキスパートスロット数で、PR の通常経路の `num_cols` とは意味が異なる。Perf Logger は ID の `_VEC` ラベルを `ids->ne[1]==1` で付与するため、複数トークンでこのラベルだけを実装の選択条件として使えない。 [ID の分岐](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L8969) · [名前付け](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L17949)
- 両者は同じ `mul_mat_vec_iq3_xxs.comp` から別の SPIR-V として生成される。ID は `MUL_MAT_ID=1`、追加の ID バインディング、固有 push constants とエキスパート別オフセットを使う。通常は F32/F16 の2種、ID は F32。c1d245b の共通シェーダー変更は ID の TPB=16 にも及ぶが、TPB=8 の登録と選択を追加するのは通常経路だけ。 [shader generator](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp#L805) · [offset と特殊化定数](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vec_base.glsl#L16)

## Radeon 8060S の workgroup と TPB 閾値

| 項目 | 確認値 |
|---|---|
| Subgroup | Vulkan の既定 64、デバイス対応範囲 32〜64。compute の算術 subgroup と subgroup-size control に対応 |
| IQ3_XXS の選択 workgroup | ソースとデバイス値から、通常・ID とも `DMMV_WG_SIZE_SUBGROUP` で `64×1×1`、subgroup 64、subgroup reduction、4出力行/workgroup（端数を除く）。AMD では大型 workgroup の選択条件に入らない |
| Baseline の TPB | 16 invocations / 256 要素ブロック。64-thread workgroup あたり4ブロックを並行処理 |
| c1d245b の通常経路 | 1列で `k >= 256 × 2 × (64/8) = 4096`（16ブロック/行）のとき TPB=8。64-thread workgroup あたり8ブロック。2列以上、閾値未満、ID は TPB=16 |
| 参考の大型 variant | `256×1×1`、subgroup 64。式上は64ブロック/行、`k >= 16384`。対象 AMD 経路では選択されない |

対象カーネルの実行は両モデルで 0 件のため、workgroup の選択と PR 後の閾値はホスト／シェーダーソースと実機 Vulkan プロパティの照合結果。 [パイプラインの特殊化](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L3325) · [デバイス情報の抜粋](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/logs/device.txt)

## TG32 と Perf Logger

各値は単発の診断値。モデルごと・logger モードごとに1回、`pp=0`、`tg=32`、`depth=0`、Vulkan0、49/49層 GPU、CPU MoE 0、F16 KV、FA ON、MTP OFF、warmup OFF で実行した。llama-bench の TG は1トークンずつ投入し、各 decode の GPU 完了を同期する。 `avg_ns` は TG 区間の wall time。プロセス経過時間にはモデルロードなども含まれる。 [コマンドとログ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/commands.md) · [llama-bench の TG ループ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/tools/llama-bench/llama-bench.cpp#L2201)

| モデル | Logger | TG wall s | tok/s | Logger 区間合計 s | 区間数 |
|---|---|---:|---:|---:|---:|
| IQ3 | OFF | 1.110148 | 28.825 | — | — |
| IQ3 | 個別 | 4.321207 | 7.405 | 2.250310 | 88009 |
| IQ3 | 並行グループ | 1.237860 | 25.851 | 1.041720 | 59456 |
| FAST | OFF | 1.124953 | 28.446 | — | — |
| FAST | 個別 | 2.444159 | 13.092 | 2.050440 | 88137 |
| FAST | 並行グループ | 1.242228 | 25.760 | 1.055740 | 59520 |

全6 run は終了コード 0 で、開始・終了とも P-MODE Performance を確認した。

通常・ID の **IQ3_XXS** は各モデルの個別計測でいずれも **0回、0 µs、0 µs/token、計測区間の合計に占める割合 0%**。実行がないため対応する `m,n,k` は空欄とした。両モデルの実際の MoE 処理は個別ログで観測できた。

| モデル | MatVec ID の重み型 | ログ上の `m,n,k` | 記録数 | 累積 ms | ms/token | 個別ログ計合計比 |
|---|---|---|---:|---:|---:|---:|
| IQ3 | IQ2_S | 640, 10, 2560 | 3,008 | 172.622 | 5.394 | 7.67% |
| IQ3 | IQ3_S | 640, 10, 2560 | 64 | 4.270 | 0.133 | 0.19% |
| IQ3 | IQ4_NL（MUL と融合） | 2560, 10, 640 | 1,536 | 98.983 | 3.093 | 4.40% |
| FAST | Q4_K | 640, 10, 2560 | 3,072 | 618.233 | 19.320 | 30.15% |
| FAST | Q4_0_ROCMFP4_FAST（MUL と融合） | 2560, 10, 640 | 1,536 | 106.429 | 3.326 | 5.19% |

個別 logger は enqueue 済み GGML ノード／融合単位で timestamp と同期を挿入する。CSV の件数はこの区間の記録数で、一つの区間に複数 dispatch や付随処理が含まれ得る。合計時間は logger の全記録区間の和で、各行のパーセントはこれを分母とした。並行 logger は同時進行し得るノードをグループ化し、一つの timestamp 区間として計る。グループ時間を構成カーネルへ配分できず、個別モードと並行モードの差には同期の有無や実行ごとの差も含まれる。差分から重複時間は算出していない。非計測 run の TG wall time が診断時より短いため、個別ログの累積時間を非計測 TG の時間内訳や短縮見込みに換算しない。 [logger 実装](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L15975) · [実測 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/runs.csv) · [全ラベル別集計](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/vk-timings.csv) · [IQ3_XXS 抽出結果](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/pr30904-preport-20261125/iq3-xxs.csv)

## 採否（2026-11-25）

常用の IQ3 PLE16 と ROCmFP4 FAST PLE16 は、IQ3_XXS テンソルと対象カーネルの呼び出しがともに0件だった。この用途での **PR #30904 の直接移植は見送る**。下記の移植時の注意点は、IQ3_XXS を実際に使用する構成を検討する際の記録として保持する。

手法を IQ2_S に展開した独立実験では、A1 単独は採用見送り、A2 は採用保留、併用版は A2 単独に対する明確な追加効果なし。TPB=8 は IQ2_S で未実施の独立候補として残す。 [IQ2_S の採否とラウンド別比較](../iq2-s-vulkan-matvec-20261125/README.md)

## 移植時の注意点

- IQ3_XXS を実際に含む GGUF をロード前にヘッダーで確認する。通常と routed expert の評価対象を分ける。今回の2モデルは既存経路の回帰比較に使える。
- 1列の `k=3840`／`4096` で境界選択、通常の F32/F16、7〜8列の蓄積切替、ID の既定 TPB=16、未選択 expert ID と端数出力行を数値確認の対象にする。FMA の加算順が変わるため、CPU 参照との比較で誤差を評価する。ID 用 TPB=8 は別の設計判断になる。
- packed16 の配列位置と sign/scale の抽出、ホスト側特殊化 ID 3、既存の ROCmFPx 登録・Q8_1 選択、ID のバインディングを照合する。実機比較は同一条件で計測し、logger OFF の TG 比較と区間プロファイルを併記する。ベンチマーク以外のバックエンド演算テストは専用運用ルールの承認範囲を確認する。 [エージェント運用ルール](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/docs/evox2/automation/AGENT-RULES.md)
