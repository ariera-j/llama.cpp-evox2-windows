# ROCm/HIP `mul_mat_q` コード/文学入力差 — ソース監査（2026-11-07）

**ステータス：ソース調査のみ完了。実行バイナリの変更・ビルド・RGP再取得はしていない。**

調査対象は **実際にRGPを取得したb12038/d321e7ff38052be311fde9392598fe02c7548956**。以下の `mmq.cu` / `mmq.cuh` / `ggml-cuda.cu` は後のb12148 HIP-FA診断ブランチでも**blob SHAが一致**し、当時の実装を正確に代表する。

- [b12038/mmq.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/ggml/src/ggml-cuda/mmq.cu)
- [b12038/mmq.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/ggml/src/ggml-cuda/mmq.cuh)
- [b12038/mmid.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/ggml/src/ggml-cuda/mmid.cu)
- [b12038/mmq-config-rdna4.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/ggml/src/ggml-cuda/mmq-config-rdna4.cuh)
- [b12038/ggml-cuda.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/ggml/src/ggml-cuda/ggml-cuda.cu)
- [b12038/llama-graph.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/src/llama-graph.cpp)
- [b12038/models/qwen4exp.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d321e7ff38052be311fde9392598fe02c7548956/src/models/qwen4exp.cpp)
- [実測24イベントをEvent IDで対応づけたCSV](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/data/rocm-hip-rgp-same-index-expensive-events-paired-20261107.csv)

## 1. 正確なカーネル実体とテンプレート引数

RGPの`mul_mat_q<(ggml_type)20, 32, false, (ggml_prec)30>` および `mul_mat_q<(ggml_type)22, 32, false, (ggml_prec)30>` は:

| テンプレート値 | 解釈（`ggml/include/ggml.h`） |
|---|---|
| `ggml_type=20` | `GGML_TYPE_IQ4_NL`、**weight**形式 |
| `ggml_type=22` | `GGML_TYPE_IQ2_S`、**weight**形式 |
| `J=32` | 32個の右辺列／出力token slotをひとつのGPU tileとして処理する選択 |
| `fallback=false` | MMQの分割端処理のspecializationを用いない |
| `ggml_prec=30` | `GGML_PREC_Q8`。右辺F32活性値はQ8_1等に量子化して計算に使用 |

これは **GGUFモデル全体がIQ4_NL/IQ2_Sである**という意味ではなく、今回表示された個別GPU weight kernelの形式。MMQの`ggml_cuda_mul_mat_q_switch_type`は型別に`mul_mat_q_case<type,GGML_PREC_Q8>`を選択する。

RDNA4 `mmq-config-rdna4.cuh` の `IQ2_S` / `IQ4_NL`・`J=32`・`fallback=false` 構成は**128threads, I=64, stream_k=false**で、実際のRGP名称と一致。したがって観測された主カーネルでは、Stream-Kによる特殊な分割が主な差であるという説明は優先しない。

## 2. 同じGPUカーネルに至る2つの経路

`ggml-cuda.cu`:
```text
GGML_OP_MUL_MAT
  -> ggml_cuda_mul_mat
  -> ggml_cuda_should_use_mmq(...)
  -> ggml_cuda_mul_mat_q(ctx, src0, src1, /*ids=*/nullptr, dst)
      [一般的な密行列演算]

GGML_OP_MUL_MAT_ID
  -> ggml_cuda_mul_mat_id
  -> ggml_cuda_should_use_mmq(... n_experts=ne02)
  -> ggml_cuda_mul_mat_q(ctx, src0, src1, ids, dst)
      [Expert選択付きMoE演算]
```

両方とも`mmq.cu`から同一の`mul_mat_q<type,J,fallback,prec>` GPUカーネルを起動し得る。**RGPのGPUカーネル名だけでは、どちらのGGML op、どのweight名、layer番号か断定できない。**

MoEグラフの存在は明示的：
- `models/qwen4exp.cpp` の各block `build_layer_ffn` は `build_moe_ffn` を呼び、Routed Expertのgate/up/down tensorを使用。Shared Expertがある場合は`build_ffn`の通常`MUL_MAT`も別に実行。
- `llama-graph.cpp` はMoE確率→`ggml_argsort_top_k`で選択した`selected_experts`を`build_lora_mm_id`へ渡す。gate/upが融合した `gate_up_exps` tensorの場合は1 `MUL_MAT_ID`にまとめることもあるため、**3カーネル=gate/up/downと断定しない**。

## 3. MoEなら入力依存の実処理量が変わるソース上の機構

`mmq.cu:ggml_cuda_mul_mat_q`:
1. `ids != nullptr`（MoE）の場合に`ggml_cuda_launch_mm_ids_helper`を実行し、`ids_src1`, `ids_dst`, `expert_bounds`をGPUで構成する。
2. `mmid.cu:mm_ids_helper`がselected-expert IDsをトークン別に走査、Expertごとにコンパクト化し`expert_bounds[e]` / `expert_bounds[e+1]`を設定する。
3. `mmq.cuh:mul_mat_q`はExpert `e`について `col_diff = expert_bounds[e+1] - expert_bounds[e]` を読み、`jt*J >= col_diff`ならそのタイルを早期終了。

```cpp
if (ids_dst) {
    col_low  = expert_bounds[zt];
    col_high = expert_bounds[zt + 1];
    col_diff = col_high - col_low;
    if (jt*J >= col_diff) {
        return;
    }
}
```

この設定の`J=32`から、Expertごとのtoken assignment数を`m_e`とすると、理論上の*処理が必要な列タイル数*は概ね `Σ_e ceil(m_e/32)`。総assignment数 `Σm_e = n_tokens × n_expert_used` が固定でも、分布の偏り・未使用Expert・余剰列・重みアクセス先は文書で変わり得る。GPU並列実行・wave scheduling・cache/重みの局所性も実行時間へ影響し得る。

**上記はデータに依存し得る機構の実在を示すが、今回のコード入力で本当に`Σceil(m_e/32)`が大きいかは未計測。** `ids==nullptr`（通常の密MUL_MAT）の場合はこのExpert別early-return分岐を使用しないため、同じ行列形状なら演算タイル構造自体は通常固定。測定差の原因はGPUクロック・cache・メモリ配置・同期/スケジューリング・測定誤差などの候補になる。

## 4. RGPの規則的な5組×3 kernel

同じHIP RDP `Dispatch range start=181200/count512`をコード/文学で取得し、24件の高価なEventのうち`mul_mat_q`15件をEvent IDで対応付けた。

**タイミング順**に見ると、2本のIQ2_S + 1本のIQ4_NLという3件組が5回出現する：

| 順番 | 対応Event ID (IQ2_S, IQ2_S, IQ4_NL) | コード計 ms | 文学計 ms | コード−文学 ms |
|---|---|---:|---:|---:|
| 1 | 91 / 97 / 105 | **16.394** | 14.668 | +1.726 |
| 2 | 245 / 251 / 259 | **16.188** | 15.501 | +0.687 |
| 3 | 465 / 471 / 479 | **15.906** | 15.039 | +0.867 |
| 4 | 619 / 625 / 633 | **16.266** | 15.767 | +0.500 |
| 5 | 773 / 779 / 787 | 11.595 | **12.060** | **−0.465** |
| **合計** | **15件** | **76.349** | **73.035** | **+3.315** |

- グループ先頭ID間隔は **+154, +220, +154, +154**。追加のFA MAIN `Event423` は2組目と3組目の間に挟まる。FFNの似た計算グラフが繰り返され、たまにQSA/full-attention用の演算が入るモデル構造と整合。
- Qwen4expは各layerにMoE FFNを持ち、`build_moe_ffn`のgate/up/downという3箇所のRouted weight計算があるので、**「5組は連続したMoE blockである」という仮説を強く優先**できる。ただしCPU/GPU演算のラベル対応がなく、3組の全てがRouted weightであること、FFNのどの枝か、絶対layer番号は**未証明**。Shared Expertの通常MMQ混入やgate/up融合の可能性も残る。
- 各イベントで `J=32,fallback=false,GGML_PREC_Q8` が一致。**15件中14件はコードが遅いが、最後の第5組は文学の方が遅い。** したがって、一定クロック比による全イベント一律の遅さだけでなく、layer/block単位の偏りも検討すべき。ただし1 RGPずつではrunノイズとの分離不可。
- この局所windowの`mul_mat_q` **+3.315ms（コード不利）**は、同windowの`flash_attn_ext_f16` **−0.447ms（コード有利）**を上回る。ただし **RGP Event423の厳密KV/layerは未照合**、この512-dispatch窓はPP全体ではなく、全promptでコード約2.259s遅い原因を定量的に説明できたわけではない。

## 5. 調査上の重要な区別

- **MoEのExpert top-k**（この調査の`ggml_argsort_top_k`）と、前段Vulkanで調査した**QSA Lightning Indexer top-k**は別の選択機構。QSAのscore/top-kサンプルをExpert選択の証拠として使わない。
- 今回の12件FAホスト診断 `GGML_HIP_FA_TRACE` の`fa_id`はMMQのGPU dispatch番号ではない。`fa_id=569` / `Qcur19`はGPUのMMQ Event105等のlayerを証明しない。
- ROCmの通常速度（以前、コードより文学約1.5%高速）はRGPを有効にしない全入力PP。RGPのGPU event durationはプロファイラー起動下の単一部分窓。これらを一対一対応させない。

## 6. 追加GPU計測なしで次に確かめられること

1. **既存RGPだけでできる確認（優先）**：コード/文学RGPの `Events → Event timing` からEvent **91(IQ2_S), 97(IQ2_S), 105(IQ4_NL)** と別組の **465/471/479** を開き、それぞれ可能な範囲で**HIP dispatch grid (x,y,z)**、workgroup size、kernel全名と直前の `mm_ids_helper` / quantize系イベントを確認する。MoEなら`launch_mul_mat_q`のgrid.zは`n_experts × n_samples`、通常行列ではそのテンソルのbatch/channel数に依存する。大きいgrid.zや直前のids helperはMoE経路を支持するが、絶対layerやExpert IDを単独では証明しない。
2. それでも確定しなければ、**次の独立Gateで** `GGML_HIP_MMQ_TRACE`（default-OFF）を`ggml_cuda_mul_mat_q`入口に追加。ログ項目：host MMQ call index, `ids != nullptr`, `src0->name`, `src0->type`, `dst->name`, graph op, `ne0..ne3`, `J_best`, `n_expert_used`、必要なら直前・直後の選択root tensor name。最初はHOSTメタデータのみ、GPU event copy/sync禁止。結果のCPU call順をRGP Event IDと同一視しない。
3. **Expert分布そのものを検証したい場合**には別途default-OFFの小さなHistogram診断が必要。`expert_bounds`はGPUメモリ上にあるため、HOSTログだけで各`m_e`は読めない。計算方式を変えない範囲で、安全な位置とデータ転送負荷を検討して実装する。理想はコード/文学の同一KV・layerにおける `Σceil(m_e/J)`、非空Expert数、最大`m_e`等を比較。
4. 全PPの数秒差を確定するには、局所512dispatchだけでなく複数KV位置での反復とGPU kernel family合計が必要。**まずはソース経路とExpert分布を確認**し、その結果で計測負担を判断。

## 7. 結論

**ソース上では、入力によって`mul_mat_q`の仕事量が変わり得る、具体的で検証可能な機構はMoEの`expert_bounds`とJ=32のタイル早期終了にある。** 15件のRGPは似た3件組を反復し、Qwen4expの各layerのMoE構造と整合するため、次の調査対象として優先する合理性がある。

一方、**各Eventが実際に`MUL_MAT_ID`なのか、どのweightとlayerなのか、および入力ごとのExpert分布が実際に異なるか**は未確認。ここを確認するまで「コードが遅いのはMoE Expert分布が原因」と断定しない。

**今回はソース調査・文書化のみ。新しいC++診断機能は未実装。**
