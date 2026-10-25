# COMMON-004版とr4のVulkan 64k profile比較

調査日: 2026-10-03。対象は固定r4 upstream `bed0a856606ee4a24a164066f73d2379447033f5`。

## 結論

同じOriginalモデル・入力・計測設定でも、r4のGPU演算時間はPPで8.01%、
steady TGで4.04%増加した。PPの最大の増加項目はMoE matmulであり、FAではない。
TGではGET_ROWSとQSA選択処理の構成差が主要な調査対象になった。
通常実行の速度低下と整合する方向だが、各1回の同期profiler測定であり、
通常TGの5〜8%差を完全に説明したものではない。

次は128k profile追加や旧cache全体の再移植より、MoEタイル選択の単独A/Bと
TG GET_ROWSのtensor別計測を優先する。VULKAN-002はその後の長文PP最適化候補として維持。

## 比較条件とCOMMON-004の適用確認

| 項目 | COMMON-004版 | r4 clean |
|---|---|---|
| ZIP | `20261003-115720-684-cli-vulkan-b11260-ctx65536-6d20112c7b54.zip` | `20261003-113858-285-cli-vulkan-b11372-ctx65536-f5498bca2f96.zip` |
| BuildKey | Common004Vulkan | R4Vulkan |
| 実バイナリversion | b11260 / 31886a2c2 | b11372 / 94b877457 |
| 終了 | OK / 0 | OK / 0 |
| 入力 / 生成tokens | 61,789 / 128 | 61,789 / 128 |
| logger有効時 PP tok/s | 239.10 | 235.90 |
| logger有効時 TG tok/s | 6.22 | 7.68 |

conditionsのModelIdentity、InputIdentity、Environmentは一致。
EffectiveConditionもExecutable以外は一致する。Original UD-IQ3_XXS、UMA 96GB、
ctx65536、f16 KV、batch2048 / ubatch1024、threads4、MTP OFF、FA auto。
入力SHA-256は `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`。
モデルは同一path・size・mtimeで、モデル本体のSHA-256は未取得。

COMMON-004版のmanifestは `Source.Dirty=true`、変更ファイルは
`src/llama-memory-hybrid-idx.cpp`、同 `.h`、`src/models/qwen4exp.cpp`。
実行ログにも `pooled indexer key cache, 12 layers x 16386 rows ... 96.01 MiB` がある。
versionのcommitはdirty buildの親であり、COMMON-004未適用とは判断しない。
wrapper側GitIdentityと実行バイナリのidentityも区別する。

両ログの190 timingブロックを同じ方法で解析し、各演算の合計とTotal timeの整合を確認。
warmup2ブロックを除外。PPは61ブロック（1024×60+349）、TGは127ブロック中の
初回を除く126ブロック。初回decodeは旧67.263 ms、r4 42.591 msでsteady値に混ぜない。

## PP: 増加18.690秒のうちMoEの純増は16.634秒

下表はPP全体のGPU演算時間合計。秒、増減はr4−COMMON-004版。

| 演算 | COMMON-004版 | r4 | 増減 |
|---|---:|---:|---:|
| MoE matmul | 47.051 | 63.685 | +16.634 |
| FLASH_ATTN_EXT | 107.674 | 108.408 | +0.735 |
| その他matmul | 36.641 | 37.461 | +0.819 |
| その他全体 | 41.837 | 42.339 | +0.502 |
| 合計 | 233.203 | 251.893 | +18.690 |

MoEは35.4%増。特にbatch1024のIQ2_Sは33.594→43.764秒、
IQ4_NLは12.078→18.116秒。同じshape・呼び出し回数の演算が遅くなっている。
一方、旧TOPK_QSAは6.753秒、r4 TOP_Kは1.268秒と選択処理側の削減もあるため、
MoEの増加割合をそのまま最終PPの改善予測にしない。

### 最優先の原因候補: upstreamのMoEタイル選択変更

ローカル履歴で `31886a2c2..bed0a8566` を確認すると、
`94a0ae3e7298127b74d5b31370e83a1b4f143070`
（`vulkan: MOE aware mat_mul_id tile selection (#29182)`）が入っている。
`ggml_vk_mul_mat_id_q_f16()` 内のtile/alignment選択に渡すNが、
旧 `nei1`（token数）から `ceil(nei0*nei1/n_as)`（expertあたり平均行数）に変わった。

今回の10 selected experts / 512 expertsでは、1024-token時は1024→20、
349-token時は349→7になる。後者は `aligned` 判定の `N > 8` も満たさなくなる。
実際に端数349-tokenのIQ2_Sは409.493→684.604 ms、
IQ4_NLは130.312→263.782 msと増えており、この変更は有力な切り分け対象。
ただしログに選択pipeline/tile名はなく、このcommitが原因と確定したわけではない。

診断ではr4上でこの選択変更だけを旧方式へ戻す比較版を用い、同じOriginal 64kで
MoE演算時間とlogger無効時PPを確認する。先にVULKAN-002等を混ぜない。
広いモデル/GPUに対してupstream変更が誤りだとは判断せず、gfx1151と今回のshapeの
結果に基づいて恒久的な選択条件を検討する。

FAは両版でほぼ同程度（+0.68%）なので、今回の64k PP退行の主因候補とは分ける。
FAがr4 PPの43%を占め、今回のquery数ではbackend sparse分岐に入らないという
前回の観察は維持される。VULKAN-002の長文最適化価値は引き続きある。

## TG: GET_ROWSだけでなく融合・選択処理を合わせて比較

単位はsteady平均ms/token。

| 演算 | COMMON-004版 | r4 | 増減 |
|---|---:|---:|---:|
| GET_ROWS全体 | 0.743 | 2.483 | +1.739 |
| TOPK_QSA融合 | 1.001 | 0 | -1.001 |
| TOP_K | 0 | 0.283 | +0.283 |
| 上記3項目小計 | 1.744 | 2.766 | +1.022 |
| その他matmul | 20.972 | 20.981 | +0.009 |
| MoE matmul | 8.962 | 8.825 | -0.136 |
| FLASH_ATTN_EXT | 1.291 | 1.336 | +0.045 |
| 全演算合計 | 39.022 | 40.597 | +1.575 |

小計の増加は全体差の約65%。ただしGET_ROWSにはQSA以外も含むため、これは
「QSA単体の厳密な総時間」ではなく、融合の境界を考慮した比較用の括りである。
GET_ROWSの回数は88→124/token。旧TOPK_QSA融合12回が消え、
r4のpool-domain TOP_Kが12回出ている。

r4では `kpool_access::gather_pooled()` がGET_ROWSを発行し、
`build_qsa_sel()` に選択poolのindex取得とtop_score取得のGET_ROWSもある。
旧融合はexpanded score/maskからtoken-domain top-kを作るgraph patternを要求し、
新しいpool-domain graphにはそのまま適用できない。
したがって、旧融合や旧cache全体の単純復活より、新graphのgather/selection/maskの
残存コストをtensor名・shape別に特定する。

loggerのGET_ROWSラベルにはtensor名もshapeもない。+1.739 msをすべてpool cacheの
gatherだと断定したり、回数差36だけから各演算の時間を割り当てたりはしない。
差分pool normが小さいことは前回確認済みで、全pool再計算に戻った証拠もない。

## profiler wall timeとの関係と次の順序

PP wall timeは旧258.422秒→r4 261.934秒、TG wall timeは20.419秒→16.528秒。
TGのwall timeはGPU演算合計と逆向きであり、同期・CPU側graph処理・logging等を
含むprofile時のtok/sを通常性能の指標として使えない。
GPU合計との差を単一のCPU原因に割り当てることも避ける。
decode入力token列の同一性は確認していないため、TGは同一prompt・生成数の比較。

1. PP: 上記MoEタイル選択だけを切り替える診断A/B。選択pipelineも記録する。
2. TG: GET_ROWSにtensor名・shapeを記録する診断を行い、pool gatherと選択/maskを分離。
3. 改善候補をlogger無効の同条件64kで確認してから128k/256kへ広げる。
4. 退行の切り分け後にVULKAN-002、ROCm COMMON-005を進める。
   COMMON-001は今回のOriginal同士の比較には不要。

本更新はログ集計・ローカル履歴照合・文書更新のみ。推論コードの変更や
上記診断A/Bの実行はまだ行っていない。
