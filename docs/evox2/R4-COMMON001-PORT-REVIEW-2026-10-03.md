# COMMON-001: r4移植可否の確認

確認日: 2026-10-03 JST。実装前のソースレビュー。

状態: **実装可能 / Ready**。この文書を実装前の固定判断として扱う。

- 移植元: r3 `902e9f4a762cc0fe89d613868c35e4861610081e`。
- 移植先レビュー時点: r4 `b9dce8192fa28887e7bcd17a8fd49576ad1710d4`。
- 固定upstream: `bed0a856606ee4a24a164066f73d2379447033f5`。
- r4にはMoE旧タイル選択とGET_ROWS診断を含む。COMMON-001は未実装。
- pre-port基準はOriginal 64k / Vulkan / MoE legacy=1で取得済み。COMMON-001はモデルlayoutを揃えた比較のため次に実装する。

## 結論

**無修正の移植は不可。ただし、r3の基本方式を維持した小規模な適応移植が可能と判断する。**
split PLE16対応はupstreamで代替されていない。新しいkernelやCOMMON-004の移植は不要。
変更先は原則として旧パッチと同じ4ファイルで足りる見込み。
Windowsビルド・実モデル検証前なので、動作保証や速度改善の確定ではない。

旧commitには当時のPATCHESとmodel READMEの変更も含まれるため、commit全体の
cherry-pickより、現在のソースへコード差分だけを移す。

## 適用チェック

旧commitから次の4ファイルだけを抽出し、作業ツリーを変更せず確認した。

| ファイル | 通常の `git apply --check` | 別indexでの `git apply --cached --3way` |
|---|---|---|
| `src/llama-arch.h` | 適用可 | 適用可 |
| `src/llama-arch.cpp` | 適用可 | 適用可 |
| `src/models/models.h` | 文脈不一致 | 自動マージ可 |
| `src/models/qwen4exp.cpp` | 文脈不一致 | 競合 |

3-wayの終了コードは1。これはコード差分のマージ確認であり、コンパイル試験ではない。

## そのまま使える設計

- `LLM_TENSOR_PLE_NGRAM_EMBD` と `ple_ngram_embd.%d` の登録。
- qwen4expモデルの `std::vector<ggml_tensor *> ple_ngram_embd`。
- joinedがある実ファイルでは既存のjoined経路を選択。
- splitではmetadataのhead数だけ全tensorを要求し、各headの行数・形状を検査。
  対象モデルは16 headsだが、実装は16を固定値にしない。
- joinedのindexはtoken-majorかつglobal offset付き、splitはhead-majorかつhead-local。
- splitではhead別のGET_ROWS結果をdim 0でhead順に結合し、
  `[head_dim * n_heads, n_tokens]` に揃える。

joinedの並びはtokenごとにhead 0, 1, …となる。
splitの各gatherは `[head_dim, n_tokens]` で、dim 0への結合が同じtoken内のhead順を再現する。
hash計算、EOS処理、KV履歴の取得は現行upstreamの実装を使う。

## 必要な調整

### 1. 現行PLE入力クラスへの接続

現行r4では入力クラスが `llm_graph_input_qwen4exp_ple` となり、保持する参照は
`const llama_model_qwen4exp &` ではなく `const llama_model & model` になっている。
旧コードの `pmodel.ple_ngram_embd` と `hp` をそのまま挿入しない。

`set_input()` 内で必要な場合にのみ
`static_cast<const llama_model_qwen4exp &>(model)` で型付き参照を取得し、
`ple_ngram_embd.empty()` によってjoined/splitのindex layoutを分岐する。
`can_reuse()` が更新するKV contextとtoken数判定は維持する。

### 2. Originalのlazy load/prefetchを保持

joinedは現行の `TENSOR_READ_LAZY`、global index、`model.can_prefetch` による
`llama_prefetch_rows()` を維持する。
splitはr3と同じ通常ロード（flags=0）とし、headごとの配置を維持する。
splitのlocal indexをjoined tensor用prefetchへ渡さない。

現行 `llama-model.cpp` は非nullのjoined lazy tensorだけを `can_prefetch` に登録するので、
split時にjoinedがnullなら現状の集合判定でもprefetchは呼ばれない。
ただし移植時はjoined経路に限定する条件を明示する。
splitへのlazy/prefetch追加は別の挙動変更になるため、この移植には含めない。

### 3. metadata-only / virtual model構築を壊さない

旧パッチの「joinedの `get_weight()` がnullならsplitを必須にする」だけでは不十分。
現行loaderには `files.empty()` のvirtual/metadata-only経路があり、実ファイルもweights mapもない場合は
指定shapeからtensorを合成する。このとき `get_weight()` はnullでもjoined tensorを作る必要がある。

そのためloader分岐は次の順にする。

1. `ml.files.empty()` なら既存のjoined合成経路を維持する。
2. 実GGUFでjoined weightが存在すれば、既存joined lazy pathを維持する。
3. 実GGUFでjoinedが欠落するときだけsplit layoutとして扱い、全head tensorを必須にする。

壊れた実GGUFをmetadata合成fallbackで隠さない。
`no_alloc` は実ファイルのmemory-fitでも使われるため、これだけでvirtual経路と判定しない。

### 4. r4のQSA・MTP・診断変更を保持

r4ではQSA/k-poolとMTPのloader/graphがr3当時から更新されている。
これらが旧パッチの文脈と異なるが、split PLE方式を根本変更する理由ではない。
旧ファイル全体の置換は避け、PLE箇所だけ変更する。初期実機検証は従来どおりMTP off。

既存の `ple_embedding_rows` 診断名はjoinedに残し、splitの各GET_ROWSにもhead別の名前を付ける。
QSA側のGET_ROWS名、incremental pool cache、MoE選択スイッチは維持する。

### 5. head番号を配置用layer番号として使う前提

r3はsplit tensorを `LLM_TENSOR_LAYER_REPEATING` に登録し、head番号を `tn.bid` に渡す。
現行の `llama_model_base::create_tensor()` もlayer配置表を `tn.bid` で参照する。
対象の16 heads / 48 trunk layersでは範囲内で、全層offload条件の移植を妨げない。

一般化する場合は `ple_n_heads <= n_layer_all` の前提を検査する必要がある。
部分offload・複数GPUでは先頭側layerの配置に従うため、今回の全層offload検証と同一とは扱わない。

## 実装境界

今回のCOMMON-001で変更するのは次の4ファイルに限定する。

```text
src/llama-arch.h
src/llama-arch.cpp
src/models/models.h
src/models/qwen4exp.cpp
```

実装内容は次の範囲に留める。

1. split PLE tensor ID/name/infoを登録する。
2. qwen4exp modelにsplit head tensor vectorを追加する。
3. loaderでvirtual / joined / splitを明示的に分岐する。
4. split時だけhead-local indexを作る。
5. graphでhead別GET_ROWSを行い、head順にconcatしてjoinedと同じ最終shapeへ戻す。
6. joinedのlazy load/prefetch、QSA、MTP、MoE、既存診断は変更しない。

このcommitではCOMMON-004/005、VULKAN-002、split側lazy load、MTP-QSAを同時に持ち込まない。

## 実装後の検証順序

1. ソース差分を確認し、変更が上記4ファイルのPLE箇所に限定されていることを確認。
2. 可能なら小さいsynthetic入力でjoined/splitのgather結果一致を確認。
   複数tokens、headごとに異なるvocab/offset、行数paddingを含める。
   欠落head・不足行数・metadata-onlyの分岐も確認する。
3. Vulkan/ROCmでOriginalとPLE16のAllocationOnly、短い推論を確認。
   ログでjoinedのlazy/prefetchとsplitのtensor配置を確認する。
4. 同一ビルド・同一入力・MTP offでOriginal/PLE16の64k比較。
   VulkanはMoE legacy=1に固定し、通常計測では両profilerを無効化する。
   Original導入前後も比較し、layout差と移植による退行を区別する。
5. 64kが正常なら128k/256kへ進む。r3での成功をr4の検証済み扱いにはしない。

PLE16化で今回のcached pool gather 1.662 ms/tokenが消えるわけではない。
COMMON-001は比較するモデルlayoutを揃える互換性作業として先行し、
TGの残存コストはその後に評価する。

## 実装開始条件

このレビュー時点で、r4 HEAD、upstream pin、pre-port GET_ROWS基準、移植対象4ファイル、
virtual/joined/splitの分岐条件が確定したため、COMMON-001の適応移植を開始してよい。
