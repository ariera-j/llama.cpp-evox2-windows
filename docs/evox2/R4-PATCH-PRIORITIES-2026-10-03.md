# r4: 256kまでの結果による再移植判定と暫定優先順位

調査日: 2026-10-03 JST。11:22 JSTに256k clean baselineが両backendで完了。
以下のprofile・通常ABBA比較を最新判断とし、256k・128k時点の分析も保持する。
対象は固定upstream `bed0a856606ee4a24a164066f73d2379447033f5`。
初期baseline/profile時の `git diff <base> -- src ggml common` は空だった。
後続MoE A/Bは診断変更を加えた `c81b8bf78` を対象とし、区別して記録する。
以後のupstream master全般についての判定ではない。
後続作業として[MoEタイル選択の診断スイッチと比較plan](R4-MOE-TILE-AB-2026-10-03.md)
を実装済み。Windows profile A/BでlegacyのMoE時間が25.22%短縮し、
両モードのMUL_MAT_IDテスト939/939成功を確認。通常ABBAも完了し、PP平均が
248.475→268.985 tok/s（+8.25%）、prompt evalが18.959秒短縮した。
TG平均は25.195→24.565（-2.50%）だが、生成128tokens・各2回・本文も異なるため
安定した退行か変動かは未確定。この条件のPP原因切り分けは完了し、旧方式の明示選択を維持。
次はTG GET_ROWSのtensor別診断を行い、修正が大きければVULKAN-002へ進む。

## 14:02 JST: ユーザー指定による順序更新

GET_ROWSをtensor別に分ける診断コード・64k単発planを作成。
[手順](R4-GET-ROWS-PROFILE-2026-10-03.md)に従い、MoE旧方式固定で導入前ログを取得する。
**次の移植はCOMMON-001を先行**し、Original/PLE16を同じr4条件で比較できるようにする。
これはOriginalの安定性不足ではなく、r3/r4の比較条件を揃えるためのユーザーの選択。
両backendのload・64k動作を確認後、TGの小さい修正とVULKAN-002/COMMON-005の順序を判断。
以下の以前の「COMMON-001は条件付き」「VULKAN-002優先」は、この指定で更新する。

## 64k Vulkan profile取得後の更新

最新の同一バイナリA/Bでは、MoEタイルが32×32から64×64へ切り替わり、
MoE 63.933→47.807秒、PP GPU全体253.097→230.763秒。FAとsteady TGはほぼ不変。
PPの主要因としてタイル選択変更を強く支持し、後続normal ABBAでも通常PP改善を
確認済み（[結果詳細](R4-MOE-TILE-AB-2026-10-03.md)）。
以下のCOMMON-004との比較は、この診断A/B以前の調査記録。

[R4-VULKAN-PROFILE-64K-2026-10-03.md](R4-VULKAN-PROFILE-64K-2026-10-03.md)に集計を記録。
PPのFAはGPU演算時間の43.0%。今回の1024/349-query PPはupstream sparse FA分岐の対象外。
TGでは小さいpool normとpool領域TOP_Kが観測され、差分cache更新の裏付けが得られた。
COMMON-004版＋Originalの比較profileも取得済み。
[比較結果](R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md)ではr4のGPU演算時間が
PPで+8.01%、TGで+4.04%。PPはMoEが47.051→63.685秒と増え、FAはほぼ同程度。
次はupstream `94a0ae3e7` のMoEタイル選択変更だけを切り分けるA/Bを最優先とする。
TGはGET_ROWS＋QSA融合/TOP_Kの小計が+1.022 ms/token。tensor名・shape別計測で
pool gatherと選択/mask構築を分ける。通常TGの5〜8%差を完全に説明したとはしない。
128k profile追加やCOMMON-004全体の再移植より、この2点の診断を先行し、
logger無効で改善を確認してからVULKAN-002 / COMMON-005へ進む。

## 256k結果による更新

256kは両backendでStatus OK / ExitCode 0、実入力255,181 tokens。
Vulkanは555 tokens生成・34分49秒、ROCmは448 tokens生成・24分12秒。
同一backendのバイナリhashは64k/128kと一致し、Original・MTP OFF等の設定も継続。
元ログ: `20261003-102327-930-qwen38-r4-clean.zip`。

| Backend | PP tok/s | TG tok/s | 128k→256k TG変化 |
|---|---:|---:|---:|
| Vulkan | 126.76 | 19.26 | -15.6% |
| ROCm | 185.95 | 12.23 | -28.6% |

r3との256k比較:

- COMMON-001+004 ON直後: Vulkan PP 98.63 / TG 21.03、ROCm PP 166.18 / TG 11.60。
  r4 Vulkan TGは-8.4%。64k/128kで約-5%だった差は256kでも解消しない。
- 後日のCOMMON-005 OFF: Vulkan PP 98.065 / TG 21.135、ROCm PP 167.58 / TG 11.68。
  r4 PPはそれぞれ+29.3% / +11.0%。Vulkanは64k PP低下と長文PP改善が共存する。
- COMMON-005 ON: Vulkan TG 21.69、ROCm TG 17.37。
  r4 ROCm TGはONより29.6%低く、OFFより4.7%高い。未代替のcompact K/Vの調査を支持する。
- r2 Vulkan union PP 177.01に対してr4は-28.4%。VULKAN-002も引き続き候補。

モデル配置、実装、生成長、反復数が異なり、上記の差は単独パッチの効果ではない。

判断:

1. VulkanのPP/TG低下の再現確認・profileを最優先とする方針を維持。
   TGの差は256kでも残り、単なる固定時間差という仮説だけに絞らない。
2. VULKAN-002とCOMMON-005はどちらも残す。長文待ち時間なら前者、
   ROCm decodeなら後者。まず診断し、実証された小さい修正を先行できるようにする。
3. COMMON-001はOriginalの256k完走により緊急の安定性対策としては先行不要。
   PLE16互換性、またはTGのモデル配置差を切り分けるためなら先行可能。
4. COMMON-004は機能代替済み・性能検証未完了のまま。旧実装の単純な再導入はしない。

メモリと出力の観察は [BASELINE.md](BASELINE.md) に追記。
起動時に空きRAMが一時的に小さくなるが、測定中盤の空きRAM中央値は約18 GiB。
継続的なメモリ枯渇によるTG低下と断定する証拠はない。
両出力は読みやすい日本語要約で、明らかな生成崩壊は見られないが、内容の正確さは未採点。

## 結論

| 項目 | upstreamで不要になったか | 暫定方針 |
|---|---|---|
| COMMON-001 | PLE16互換機能は未代替。ただし元モデル運用での必要性は低下 | 条件付き。256k完走済み。PLE16利用または配置差の診断が必要なら先行 |
| COMMON-004 | 主要目的はupstreamが実装済み | 旧実装の再移植は見送り。新しいcacheの動作・残存コストを検証 |
| COMMON-005 | ROCmのcompact K/V decodeは未代替 | 実装候補2位。ROCm decode profile後、新しい選択処理に合わせ最小差分で適応 |
| VULKAN-002 | sparse FAは一部重複するがgrouped-union PPは未代替 | 実装候補1位。Vulkan PP profile後、grouped-unionの不足分を移植 |

長文入力の待ち時間を短くする目的からVULKAN-002を先に置く。
ROCmの生成速度を優先する場合や、Vulkan側の移植調査が大きくなる場合は
COMMON-005を先にする。旧パッチ番号の順にすべて再導入する計画ではない。
新規候補・MTPより先に、この4項目の採否と必要な差分を確定する。

## 追加の最優先診断: Vulkanのr3比低下

128kまでの比較で、VULKAN-002の移植より前に確認する診断項目を追加する。
COMMON-004の機能代替は確認できるが、性能同等性は未確認である。

| 比較 | r3 tok/s | r4 tok/s | 変化 |
|---|---:|---:|---:|
| Vulkan 64k PP: pure baseline同士 | 265.10 | 248.38 | -6.3% |
| ROCm 64k PP: pure baseline同士 | 359.84 | 369.72 | +2.7% |
| Vulkan 64k TG: COMMON-001+004 ON対clean | 25.95 | 24.61 | -5.2% |
| Vulkan 128k TG: COMMON-001+004 ON対clean | 24.00 | 22.81 | -5.0% |
| Vulkan 64k PP: COMMON-001+004 ON対clean | 262.89 | 248.38 | -5.5% |
| Vulkan 128k PP: COMMON-001+004 ON対clean | 156.47 | 168.09 | +7.4% |

後日のCOMMON-005 OFFの128k ABBA平均24.61 tok/sに対してはTG -7.3%。
COMMON-004導入直後の24.00と後日の24.61を同一測定として混ぜない。
前者を用いたTGの遅延増加は64k +2.10 ms/token、128k +2.17 ms/token。
固定的な追加コストも調査する理由になるが、各1回・出力長の違いがあり原因の証明ではない。

r3にもgrouped-unionはなく、64k pure baseline同士はOriginalを使うため、
このPP低下をVULKAN-002未移植やPLE16の有無では説明できない。
記録上、Vulkan compilerは両方Clang 20.1.8、主要batch/KV/input条件と
CPU/GPU/host model buffer量は一致する。ただしr3 baseline資料だけでは全CLI、
環境変数、温度・クロック、ビルド条件が完全一致するとまでは確認できない。
TG比較にはPLE配置の違いも残る。r4のgraph再利用は64kで588回、128kで460回と
記録されており、毎token graphを再構築しているという説明は支持されない。

ソースから得た未確定の調査候補:

- r3 COMMON-004は専用pool bufferをviewで参照するが、r4はraw keyと同じstorageの
  pooled slotから `gather_pooled` / `ggml_get_rows` で取り出す。cache機能があっても
  データ移動・kernel数・layoutは同じではない。
- r3のincremental経路は既定で32 token以下。r4はprefillでも新しいk-pool処理を使う。
  PPの短い側で追加処理が目立ち、長い側で別の削減効果が勝つ可能性を検証する。
- 新QSA selection/mask構築のkernel・CPU準備コスト、FA dispatchを比較する。
- upstream差分にはVulkan MoE tile選択（94a0ae3e7 / #29182）、GDN調整
  （5c200e0c8 / #29476）もある。Vulkanだけ遅いことはVulkan backendだけが原因という
  証拠ではないが、これらもprofileで対象演算が重ければ確認する。

実施順序:

1. 256k cleanは完了。全6条件のbaselineを維持する。
2. 保存済みr3バイナリが利用できれば、64kで主要条件を合わせた通常計測を交互に行い、
   約5〜6%の差が再現するか確認する。PPはOriginal同士が比較しやすい。
3. 再現する差をVulkan PP/TG profileで分解する。QSA pool/selection/mask、FA、
   GDN/MoE、CPU側の待ち時間を区別する。旧profileとは同じprofiler条件で比較する。
4. 修正可能なr4側の追加コストがあれば先に対処。その後VULKAN-002、COMMON-005へ進む。
   COMMON-004は「再移植保留・性能検証未完了」とし、無条件に完了扱いしない。
5. TGのPLE差が切り分けを妨げる場合は、COMMON-001を比較条件統一のため先行する。
   同じr4バイナリでOriginal/PLE16を比較し、QSA変更と分けて評価する。

新upstreamにはモデルの正しさに関する変更もある。速度のために旧selection/hashへ
丸ごと戻す判断はせず、現在の意味を保った最小修正を検討する。

## 実測根拠

今回の条件・元ログ名・生成token数は [BASELINE.md](BASELINE.md) に記録。

| Backend | 指標 | r4 clean 64k | r4 clean 128k | 比較用の旧128k |
|---|---|---:|---:|---:|
| Vulkan | PP tok/s | 248.38 | 168.09 | r2 union: 222.77 |
| Vulkan | TG tok/s | 24.61 | 22.81 | r3 COMMON-004 ON / COMMON-005 OFF: 24.61 |
| ROCm | PP tok/s | 369.72 | 275.00 | r3 COMMON-005 ON: 262.50 |
| ROCm | TG tok/s | 20.98 | 17.13 | r3 COMMON-005 OFF: 16.425 / ON: 20.41 |

Vulkan PPはr2の参考値より24.5%低い。r2の速度まで回復すると仮定した
計算上は、今回の126,253-token入力が約751秒から約567秒になる
（約184秒短縮）。これは優先順位のための換算であり、実装効果の予測ではない。
ROCm TGが旧20.41まで回復すると仮定すると、今回の533生成tokenの時間差は
約5秒。長文入力が主体の今回の測定では、PPの改善が全体時間に効きやすい。
継続チャット・長い回答・キャッシュ済み入力ではTGの価値が上がる。

ROCmの128k TGは旧COMMON-005 OFFに近く、ONより16.1%低い。
64k→128kのTG低下はVulkanが7.3%、ROCmが18.4%。
この傾向はCOMMON-005の再検証を支持するが、原因の確定にはprofileが必要。

比較上の制約:

- r4はOriginalのjoined PLE、旧最適化結果はPLE16。upstreamのモデル実装も変更されている。
- r4は各条件1回。r3 COMMON-005の128k/256kはABBA平均。生成長も異なる。
- r3のpure upstream baselineは64kのみ。旧256kはCOMMON-001導入後の結果。
- 旧結果との差を、ひとつの未移植パッチの効果と断定しない。
- 正常終了は出力品質や全server条件の正しさを保証しない。

## COMMON-001: PLE16機能は依然として未対応

確認箇所:

- `src/models/qwen4exp.cpp::load_tensors`: joinedの
  `per_layer_token_embd.weight` を `TENSOR_READ_LAZY` で要求。
  headごとのvocab範囲とパディングを確認するが、split tensorへのfallbackはない。
- `llm_graph_input_qwen4exp_ple::set_input`: joined tensor向けのindexを作り、
  条件に合えば `llama_prefetch_rows` を呼ぶ。
- `build_inp_ple`: `model.per_layer_tok_embd` に対する単一の `ggml_get_rows`。
- r3実装commit: `902e9f4a762cc0fe89d613868c35e4861610081e`。

したがって、今回PLE16がjoined tensor欠落でload失敗したことはソースと一致する。
upstreamのlazy load/prefetchはsplit PLE16対応そのものではない。
ただしOriginalが64k/128kを完走したため、現時点でQSA高速化の前提にはしない。
旧64kではPLE16の速度差は小さく、長文での配置・安定性の意義が主だった。

移植する場合はtensor名、検出、head-local indexと結合に絞り、r4の新しい
hash・履歴・load処理を維持する。旧qwen4expファイル全体で置き換えない。
OriginalとPLE16の両方をloadし、同じr4バイナリで比較してからモデルを切り替える。
256kで問題が出ても、まずログから原因を切り分ける。失敗だけでPLEを原因にしない。

## COMMON-004: 中心機能はupstreamにある

確認箇所:

- `qwen4exp.cpp::build_qsa_sel`: raw keyとpersistent pooled slotを使う。
  `new_pool_idxs` の分だけmean、norm、RoPEを計算し、`scatter_pooled` で保存。
  `gather_pooled(pool_cells)` で既存結果を再利用する。
- `llama-memory-hybrid-idx.cpp::kpool_layout_update`: appendを継続し、
  sequence編集ではlayoutを再構成。共有cellがある場合はcache-safeを無効にする。
- 同ファイルの新規pool追跡: 編集位置以後と今回触れたpoolをmarkする。
  `n_new_g` をubatch由来の上限にpadし、graph形状を安定させる。
- cache-safeでないケースは全pool再計算へfallbackする。

これは単にk-poolという名称があるだけでなく、旧COMMON-004の主要目的である
「過去の全poolに対するnorm/RoPE再計算をdecodeごとに繰り返さない」構造である。
今回の単一sequence・MTP OFFでは、このcacheを使える構造になっている。
ただしcache-safe/n_newの実行時値は未記録。後続64k GPU profileでは差分更新を支持する小さいnorm形状を確認したが、性能同等性は未達（冒頭の比較を参照）。

全poolのgatherやscore計算は今も残る。残存するO(n_pool)処理を見つけても、
直ちにcache全体が未実装とは判断しない。旧COMMON-004の二重導入は避ける。
旧 `LLAMA_QSA_NO_POOLED_CACHE` はr4 cacheのA/Bスイッチではない。

## COMMON-005: ROCmの不足分が残る

確認箇所:

- `qwen4exp.cpp::build_attn_qsa`: 全K/Vを `mctx_cur->get_k/get_v` で取得し、
  選択maskと `n_sel` hintを `build_attn_mha` に渡す。モデル側K/V gatherはない。
- `ggml/src/ggml-cuda/fattn.cu::ggml_cuda_flash_attn_ext_mma_f16_shall_use_sparse`:
  `GGML_USE_HIP` の場合は `false` を返す。
- r3実装commit: `d03c91b6342b099457de3508c5d67533a9a5f0ee`。

よって、CUDA向けsparse FAの追加をROCmのCOMMON-005代替とみなすことはできない。
これはソース上のfull-K/V入力の確認であり、現在のGPU時間の占有率は未測定。
maskを持つdense経路内のskipまで存在しないと断言するものではない。
まずROCmの128k/256k decodeでFAのshape、kernel、時間、深さによる変化を確認する。

旧実装をそのままcherry-pickできない理由:

- 旧経路はcell top-kを渡していたが、新 `build_qsa_sel` はpool top-kとtailから
  full-context maskを作って返す。選択indexを別途保持・受け渡しする必要がある。
- 新経路にはpadding用 `n_kv` sentinelとdead slot用dump行がある。
  それらをK/Vの実indexとしてgatherしてはいけない。
- invisible pool、未完成tail、重複、causal/sequence maskの扱いを保つ。
  特に無効slotを安全なindexへ写す場合もmaskで確実に無効化する。
- 最初は単一token・単一sequence・MTP OFFに限定し、fallbackとA/Bを維持する。

pool-domain top-kは維持する。COMMON-004もCOMMON-001もこの移植の必須依存ではない。
Vulkanは現行sparse FAを既定に保ち、ROCmの効果を確認してから別途A/Bする。

## VULKAN-002: sparse FAとgrouped-unionを区別する

確認箇所:

- `ggml/src/ggml-vulkan/ggml-vulkan.cpp::ggml_vk_flash_attn`:
  sparse hint、f16 K/V、KV深さ、GQA等の条件に応じてsparse経路を選ぶ。
- `vulkan-shaders/flash_attn_sparse_compact.comp`: maskの各行につき1 workgroup。
  全KVをscanし、その行のfinite位置を昇順のindex listへcompactする。
- FA shaderはそのindex listを用いる。複数queryの選択集合をunionして再利用する
  r2のgrouped-union経路とは異なる。

したがって「upstreamにsparse FAがあるからVULKAN-002全体が不要」は成立しない。
一方、既存sparse FA、top-k、subgroup処理と重複する部分を再実装する必要もない。
r2の参照値は [ROADMAP.md](ROADMAP.md) の保存済み記録による。
この調査ではr2全ソースとの差分を確定しておらず、移植量や改善率は未確定。

次の作業は長文prefill profileで、mask構築、compact scan、FA、indexerの時間を分けること。
既存sparse経路が実際に使われているかも確認する。grouped-unionが対象のコストに
効くと確認できたら、r2ソースを改めて比較し、新selection・tail/causal条件を保って
不足分だけ適応する。queryごとのmaskを失う単純なunion化は避ける。
OriginalモデルのままA/Bできる形とし、PLE16導入と効果を混ぜない。

## 256k計測前に設定した順位変更条件と検証（判断経緯）

1. Originalが正常完走: COMMON-001は互換性枠に据え置き。
2. joined-layout由来の再現する問題: COMMON-001を先行して同条件で比較。
3. Vulkan PPが旧256k union 177.01 tok/sから大きく離れる:
   VULKAN-002優先を維持。ただし差をそのままunion効果としない。
4. ROCm TGの低下が大きく、profileでfull-K/V FAが主要因:
   COMMON-005を先行してよい。旧256k OFF 11.68 / ON 17.37は参考値。
5. upstream cacheが想定外に全poolを再計算:
   COMMON-004として原因調査を先行し、現行実装への修正量を判断する。

最初のclean測定は各backend/context 1回でよい。採用判断に使うパッチのA/Bは
128kを主な比較点にし、256kで長文効果・安定性を確認する。
GPU profile中の絶対PP/TGを通常測定と混ぜない。
実装時は変更したbackend演算とmodel pathに合うテスト、load、短い実入力の確認を
先に通し、出力異常や短context退行も確認する。推論コードは本調査では未変更。
