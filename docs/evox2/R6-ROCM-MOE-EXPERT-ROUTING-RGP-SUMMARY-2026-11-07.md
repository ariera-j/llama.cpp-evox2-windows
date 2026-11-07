# r6 ROCm 64k PP: MoE Expert選択分布とRGP MMQ実行時間 — 調査まとめ（2026-11-07）

**結論：MoE調査はこの時点で一区切り（局所検証PASS）。** 入力文章とUBatch位置でExpert選択分布は変わり、Layer23 / KV49152ではJ32有効列タイル数proxyがコード入力で+3.70%、RGP MMQ GPU時間がコード入力で+3.24%（逆順2ペア平均）と同方向。Layer19 / KV49152はproxy同値でMMQ時間差が1%未満。**因果関係の確定やPP全体の説明ではない。**

この報告は、既存のMoE Top-k解析（b12156）、HIP/RGPアンカー実装（b12161→b12162→b12164）、2026-11-07夜のユーザー提供RGP Event Timingスクリーンショット・ZIPの結果を整理する。新しいRGPや未提出の測定データを仮定していない。MMQ秒数はスクリーンショット読み取り値。

## 1. 背景・目的

当初の課題は、ROCm版のPrompt Processing (PP)で実入力コード・文学の差がVulkanより小さく見える理由を調べること。既存のb12038 RGPでは`topk_moe_cuda`→`mm_ids_helper<10>`→`quantize_mmq_q8_1`→`mul_mat_q`の繰り返しが見えていたが、個々のイベントを**特定Layer・KV・MoE Gate/Up/Down**へ帰属できなかった。

検証対象：GMKtec EVO-X2 / Radeon 8060S (gfx1151) / Windows / TheRock ROCm10.0.0、Qwen3.8 Flash NextのUnsloth Ple16 IQ3_XXS、論文ではなく **llama.cppコード** と **『吾輩は猫である』文学**のhead61777 tokens。共通条件：context65536、batch2048、ubatch1024、f16 KV、Threads4、GPU layers999、CPU MoE0、no-warmup、1 repetition、generation0、Gather/MTP速度パッチOFF、P-MODE Performance。2入力ファイルのSHA256は元のExpert診断と新RGP側で照合した。

- Code input SHA256: `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`
- Literature input SHA256: `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`

## 2. 二つの独立した計測ゲート

**A. Expert選択のデータ（b12156 / `investigation/r6-rocm-moe-topk-diag-20261107`）**
`llama-bench`のeval callbackで`ffn_moe_topk`から実際のExpert IDsを取得。対象はLayer19/23、0-based UBatch15/31/47（KV=16384/32768/49152）。1024 tokens × 上位10 Expert / Layer、512候補Expert、raw IDs・ヒストグラム照合は12サンプルでPASS。CallbackがGPU同期・グラフ分割を加えるため、**この実行のPP速度・GPU時間を性能比較に使用しない。**

**B. GPU実行時間のデータ（b12164 / `investigation/r6-rocm-rgp-moe-layer-tags-20261107`）**
同Streamへdefault-OFFの識別HIPカーネルを投入。Layer19/23のFA専用アンカーは`GGML_HIP_RGP_ANCHOR_KV=49152`で絞り、各MoE Gateには`evox2_hip_anchor_moe_tagged<N>`（N=0..63）を投入、各MoE Gate/Up/DownにはLayer19/23の専用アンカーを配置。RGPではGPU上のアンカー→ids helper→quantize→MMQを可視化。CPUのMMQホスト診断はweight名まで記録（Layer19/23のGate/Up=IQ2_S、Down=IQ4_NL、MMQ J32）。

- b12161の1-threadアンカーでは、少なくとも試した512-dispatch窓内で表示されなかった。これだけでは未実行とは証明できない。
- b12162で128 blocks ×64 threadsの汎用全Layer GateアンカーはRGPに表示され、実GPU eventで`topk_moe_cuda → anchor → mm_ids_helper`を確認。
- b12164でLayerタグ特殊化・FA KV専用アンカーを使用。Layer19/23とKV49152を同じ局所RGP窓で確認。
- いくつかの長いキャプチャはLayer23 Down MMQの途中で終わり、見かけ上1.9〜3.47msという過小時間が出た。RGPファイルが約275MB前後で揃うことは**SQTTバッファ制約の疑い**と整合するが、実際のoverflowは未証明。後続の`CmdBarrier`と`moe_weighted_reduction_f32`まで入った別窓のみ採用。

Bでも識別カーネル・RGPトレースによる負荷があるため、**RGP有効のPP tok/sを通常PP性能比較に用いない。** AとBは選択分布とGPU時間の**別run・別build**であり、同時測定ではない。

## 3. Expert選択分布（b12156、3つのKV位置）

有効MMQタイルproxyは、Expert e の選択トークン数を `m_e`、MMQ列タイル幅をJ32として、`T32 = Σ_e ceil(m_e / 32)` と置いた値。実GPUの実行波数・時間をそのまま数えた値ではない。

| KV（0-based UBatch） | Layer | active Experts コード/文学 | T32 コード | T32 文学 | コード−文学 |
|---|---:|---:|---:|---:|---:|
| 16384 (u15) | 19 | 351 / 341 | 560 | 565 | −5 |
| 32768 (u31) | 19 | 392 / 321 | 592 | 549 | +43 |
| 49152 (u47) | 19 | 348 / 357 | 566 | 566 | **0** |
| 16384 (u15) | 23 | 345 / 339 | 556 | 572 | −16 |
| 32768 (u31) | 23 | 380 / 352 | 572 | 573 | −1 |
| 49152 (u47) | 23 | 394 / 348 | 589 | 568 | **+21 (+3.70%対文学)** |

全サンプルで、1024 tokens ×10 selected Experts=10,240 assignments、512 Experts、bad IDs=0。トークン内10ID重複なし、raw IDsからヒストグラムとT32を再構成して一致。

その他の観察：
- Layer19/u47は選択されたExpertの頻度分布が大きく異なるのにT32が同じ566。
- Layer23/u47はコードが46個多く異なるExpertを使用（394 vs348）、top10 Expertへの集中はコード23.78%・文学29.72%、隣接token間の共通Expert IDs（10個中）はコード2.695、文学4.254。
- タイル差の**符号はKV位置・Layerで変わる**。コードが常に重い、文学が常に局所性で優る、と一般化しない。Layer19/u47では隣接token共通Expert数はコード4.467、文学4.302と逆転。

詳細：[MOE-TOPK-1](R6-ROCM-MOE-TOPK-64K-GATE-2026-11-07.md) / [MOE-TOPK-2](R6-ROCM-MOE-TOPK-MULTI-UBATCH-2026-11-07.md)。

## 4. RGP Layer/KVとGate/Up/Downの対応

`GGML_HIP_RGP_ANCHOR=1`、`GGML_HIP_RGP_ANCHOR_KV=49152`、`GGML_HIP_RGP_ANCHOR_PROBE_ALL_MOE=1`で実行し、FAの`evox2_hip_anchor_fa_layer19/23`と、`evox2_hip_anchor_moe_tagged<19/23>`の両方を取得。MoEの3つの専用アンカーでGate→Up→Downのweight MMQを区別。

| 対象 | 完全に取得できたコードRDP開始値 | 文学RDP開始値 | 共通RDP設定 |
|---|---:|---:|---|
| KV49152, Layer19 | 197240 | 197240 | HIP Dispatch range、count512、SQTT High |
| KV49152, Layer23 | 197540 | 197540 | 同上 |

上記start値は**このb12164の実測例**であり、他のbuild/入力/Graph設定では再探索が必要。Layer19/23両方を同一512-dispatch窓へ詰め込もうとしてLayer23 Downが途中で切れたため、独立した窓に切り替えて完全なtraceを採用した。

## 5. 確定した局所GPU MMQ時間（KV49152）

単位ms。GPU event `mul_mat_q`自身の実行時間。Gate/UpはIQ2_S、DownはIQ4_NL。RGPのレイヤー/FAアンカーで位置合わせし、各Downの後にreductionが現れたトレースのみ採用。

### Layer19 — コード/文学 各1組

| MMQ | コード | 文学 |
|---|---:|---:|
| Gate | 3.967516 | 4.031498 |
| Up | 3.995632 | 4.052642 |
| Down | 7.231432 | 7.240887 |
| **合計** | **15.194580** | **15.325027** |

コードは約0.85%短い。T32 proxyは566対566で同値。頻度分布の違いだけで大きなMMQ差になるとは言えないことを示す**限定的な対照例**。反復数は少ない。

### Layer23 — 2組の再現性確認（順序反転）

| MMQ合計 | 1組目 コード→文学 | 2組目 文学→コード |
|---|---:|---:|
| コード | 15.931735 | 16.001167 |
| 文学 | 15.440545 | 15.489563 |
| コード側の遅さ | +3.181% | +3.303% |

MMQ内訳、単位ms：

| Corpus / round | Gate IQ2_S | Up IQ2_S | Down IQ4_NL | 合計 |
|---|---:|---:|---:|---:|
| code #1 | 4.146829 | 4.225044 | 7.559862 | 15.931735 |
| literature #1 | 4.023533 | 4.119903 | 7.297109 | 15.440545 |
| literature #2 | 4.049959 | 4.099297 | 7.340307 | 15.489563 |
| code #2 | 4.165431 | 4.219410 | 7.616326 | 16.001167 |
| **code平均** | — | — | — | **15.966451** |
| **literature平均** | — | — | — | **15.465054** |

2組の平均差=**0.501397ms、コードが文学より3.242%遅い**。どちらの順序でもGate・Up・Downの3箇所ともコードの方が長い。Layer23/u47のT32 proxyはコード589・文学568、**+21（+3.697%）**で同方向。

監視結果では再現確認ペアでGPU平均クロック約2878MHz、VRAM平均クロック約839MHz、P-MODE Performanceを維持したが、監視値はPP実行全体の統計で、瞬間的なGPUクロックやキャッシュ条件の一致を保証しない。

## 6. 機構の解釈と、証明していない事項

`mm_ids_helper`は選択Expertごとの`expert_bounds`を準備し、HIP `mul_mat_q`は`jt*J >= col_diff`を満たすタイルをskipする。このコード経路は入力のExpert分布によって実行される列タイル数が変化し得る。J32 proxyとLayer23 MMQ時間差の向き・大きさは整合し、Layer19はproxyが等しくMMQ時間差も小さい。

**今回確定したこと：**
1. Expert選択分布は入力・KV位置・Layerに依存する（実ID/ヒストグラムで検証）。
2. HIP RGPカーネルを実Layer、対象KV、Gate/Up/Downと対応付ける診断手法が実機で動作した。
3. 位置合わせ済みLayer23ではコードのT32 proxy +3.70%とGPU MMQ時間 +3.24%が2組で整合した。Layer19はproxy同値、MMQ差 <1%。

**今回確定していないこと：**
- T32 proxyの差**だけ**がGPU時間の差を引き起こすという因果関係。Expert重みアドレス・GPUキャッシュ・wave scheduling・温度/電力/瞬間クロック等の影響は排除できない。
- callback取得のExpert IDsとRGP取得時の選択IDがビット単位で同一だったこと（別ビルド・別run）。
- Layer23/u47の局所0.501ms差を、**64k全体のPP時間差**へ外挿できること。FA/CPU/他Layer/UBatchの寄与率を積算していない。
- SQTTバッファ overflowの確定。RGP末尾でMMQが切れた例は採用せず、局所Window変更で完全なtraceを取得。
- 入力ジャンル一般の傾向。今回のコードと文学はそれぞれ1文書の指定token位置。

## 7. 運用・成果物と保留事項

- b12156 Expert callback: `investigation/r6-rocm-moe-topk-diag-20261107`; 代表combined ZIP `20261107-160711-663-bench-rocm-b12156-ctx65536-23f1e78b3ed8.zip`（u47）と`20261107-171020-102-bench-rocm-b12156-ctx65536-ddcd7a30de72.zip`（u15/u31）。外部実験レポート：[12条件比較](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/runs/2026-11-07-rocm-moe-expert-topk-multi-ubatch-16k32k48k.md)。
- b12161 original anchor: `investigation/r6-rocm-rgp-moe-anchor-20261107`。
- b12162 visibility probe: `investigation/r6-rocm-rgp-anchor-visibility-20261107`。128×64のHIP汎用タグがRGPで初めて見えた。
- b12164 layer-tags: `investigation/r6-rocm-rgp-moe-layer-tags-20261107`。計測プラン：[64k HIP RGP](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-moe-rgp-anchor-20261107.psd1)。コード/文学同条件。実行順反転Layer23再検証のZIPは`20261107-224217-882-bench-rocm-b12164-ctx65536-cab91edc1b65.zip`（ユーザー提供）。原本RGP/ZIPは会話添付・実機ローカル資料であり、**この文書を作成するだけではリポジトリへ格納していない**。
- 診断カーネルは調査ブランチでdefault-OFFのまま。最適化・本番動作に有効化する意図はない。
- **本Gateの追加ROCm MoE計測は保留**。次にPP入力依存を調べる場合は、予定していたROCmのFA位置合わせ・VulkanのQSA mask解析の統合、さらに必要ならPP全体の寄与内訳を検討する。MoEタイル数の厳密な因果検証は別の独立Gateとして再開する場合だけ。

補足資料：[MMQ source audit](R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md)、[HIP RGP anchor runbook](R6-ROCM-MOE-RGP-ANCHOR-GATE-2026-11-07.md)。
