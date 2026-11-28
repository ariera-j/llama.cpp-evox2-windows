# B12651 — 高速化候補の独立調査・統合レビュー（2026-11-27）

状態: **暫定候補一覧 / 未実装・未実機検証**。Neon Medium（簡易・詳細）、Neon High（詳細）の独立調査を ChatGPT で比較し、主要な製品ソースおよび upstream PR 本文を照合した記録。Sonnet 5.5 Medium の中断・再開後の最終レポートも 2026-11-28 にレビュー・追記済み（第8節）。エージェントの評価・利用枠については [別記録](AI-AGENT-EVALUATION-20261127.md) を参照。

## 1. 調査の固定条件

- 製品: `codex/vulkan-manifest-cpu-variants-20261124` / [a650d641ee99198543697e1e3913c593059721f7](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/a650d641ee99198543697e1e3913c593059721f7)（upstream b12651 / f5e6915c28f10330885fcb9243a93ae98d3115ab）。
- 文書正本: main / [2a65d8629a62927d0f20e00893a2d988c2159698](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/2a65d8629a62927d0f20e00893a2d988c2159698/docs/evox2)。main の推論コードは現行製品ではない。CURRENT-REFRESH.json の旧 r6 情報に注意。
- EVO-X2 / Radeon 8060S gfx1151 / RDNA3.5 WMMA Wave32 / Windows / TheRock 10.0.0 / Adrenalin 26.11.2 / UMA 96 GiB。詳細は [環境](automation/EVOX2-ENVIRONMENT.md)。
- 主力 Qwen3.8 Flash Next 旧 UD-IQ3_XXS PLE16、今後 ROCmFP4 FAST PLE16 HIP 対応。Gemma 4 31B Q4_0 QAT も重要。F16 K/V、batch 2048、ubatch 1024、MTP OFF を基準とし、64K/128K/256K の PP/TG を優先する。
- 現行統合済み: COMMON-001、COMMON-003A/VULKAN-001A/B、ROCM-002（幅160 IQ4_NL GET_ROWS、host 配置制限）。過去の COMMON-005、VULKAN-002、MTP-DENSE、QSA-NOOP、Stage-B 等は未移植。詳細は [D0-5](B12651-D0-5-HIP-IQ4NL-GETROWS-INTEGRATION-20261127.md)、[PATCHES](PATCHES.md)、[前日 upstream 調査](UPSTREAM-OPTIMIZATION-REVIEW-2026-11-26.md)。
- High が報告した外部参照: upstream master 15fcfc7357f8de73671d39e7d8c594e1beb3052d、Strata v0.2.22 c234774038d1c9249cb33637d27b895d47b39786（いずれも2026-11-27の調査報告値）。他 fork の全差分は未照合。

## 2. 実測と仮説を分ける

| データ | 64K | 128K | 256K | 注記 |
|---|---:|---:|---:|---|
| b12651 clean ROCm Original PP/TG | 412.09 / 22.48 | 304.71 / 18.00 | 200.19 / 12.75 | 旧 joined PLE、条件差あり |
| b12696 ROCm PLE16 D0-4B PP/TG | 64K比の基準 | 303.23 / 17.54 | 199.25 / 12.62 | 128K/256K は最終 host 配置制限追加前、各1回 |
| b12651 clean Vulkan Original PP/TG | 373.52 / 26.47 | 288.85 / 24.29 | 242.25 / 20.60 | 別バックエンド・モデル配置 |
| r6 ROCm 診断 FA 時間 | 44.351 s (28.72%) | 189.788 s (45.00%) | 未測定 | GPUイベント区間の集計、ホスト待ち等を含み得る |
| r6 ROCm 診断 MoE 時間 | 46.807 s | 97.605 s | 未測定 | 同上 |

参照: [D0-4B](B12651-D0-4B-HIP-IQ4NL-GETROWS-20261127.md)、[D0-5](B12651-D0-5-HIP-IQ4NL-GETROWS-INTEGRATION-20261127.md)、[clean baseline](automation/UPSTREAM-B12651-PP-TG-20261124.md)、[r6 64K](R6-ROCM-PP-PROFILE-64K-2026-11-15.md)、[r6 128K](R6-ROCM-PP-PROFILE-128K-2026-11-15.md)。

D0-4B の PP は64K比74.19%/48.75%。256K 内部でも前半340.96→後半142.41 tok/s。クロック・温度が安定し Pages Input 中央値0でも、瞬間ページング、WDDM、待機等を完全には排除できない。密 FA の超線形増加は強い仮説だが、現行製品の演算別比率を測定するまでは r6 の45%を現行の事実としない。

Gemma 4 のドライバ更新比較では Vulkan 32K PP 64.44→99.96、ROCm 186.87→186.48 tok/s。過去の ub512 170.11 tok/s や UMA64 の ROCm 224.06 は条件差あり。原因を ubatch や UMA 単独に帰属しない。[ドライバ比較](automation/ADRENALIN-UPDATE-COMPARISON-20261126.md)。

## 3. 候補台帳（採用ではなく検証候補）

M=詳細 Neon Medium、H=Neon High、M0=簡易 Medium。PR は調査時点の未マージ候補。着手直前に HEAD、依存 PR、差分、マージ状況を再確認する。各パッチは独立した ON/OFF または別ビルドで検証する。

| ID | 候補・対象 | 出所 | 暫定扱い |
|---|---|---|---|
| FA-P | HIP WMMA sparse FA / QSA PP | M0/M/H | 最優先実装候補 |
| FA-T | HIP sparse tile FA [#30370](https://github.com/ggml-org/llama.cpp/pull/30370) / TG・小バッチ | M/H | 最優先、PPとは分離 |
| FA-R | RDNA tile 対応・圧縮改善 [#32741](https://github.com/ggml-org/llama.cpp/pull/32741) | H | FA-T の後続、依存あり |
| FA-F | TOP_K_MASK→FA 融合 [#32731](https://github.com/ggml-org/llama.cpp/pull/32731) | M0の発想/HのPR | sparse 基盤後に検証 |
| MMQ-S | J=32 のアンロール抑制 [#31751](https://github.com/ggml-org/llama.cpp/pull/31751) | M/H | 低工数、まず現行バイナリ調査 |
| GDN-U | ub2048 の GDN slice64 WMMA 経路 | M | 低工数、コード変更前に確認 |
| GLU-Q | GLU→Q8_1 量子化融合 [#30489](https://github.com/ggml-org/llama.cpp/pull/30489) | H | 高 |
| MMQ-P | RDNA3.5 MMQ パイプライン [#28714](https://github.com/ggml-org/llama.cpp/pull/28714) | H | 高、特に Q4_0 |
| MMVQ-T | RDNA3.5 専用 nwarps/rows_per_block 調整 | H | 高、通常 TG |
| MOE-F | IQ2_S Gate+Up+SwiGLU 融合 | M/H | FP4移行後の残余に応じて |
| GEMM | prefer_f32_output / hipBLASLt / PF_PAD 等 | M/H | 既往候補、残余計測後 |
| FEW | Few-row WMMA MMQ [#32224](https://github.com/ggml-org/llama.cpp/pull/32224) | M/H | MTP・小バッチ検証時 |
| MMVQ-B | MMVQ バッチ閾値 [#28613](https://github.com/ggml-org/llama.cpp/pull/28613) | M | MTP・並列時 |
| VK-M | Vulkan CM1 INT8 MMQ [#32528](https://github.com/ggml-org/llama.cpp/pull/32528) / [#32919](https://github.com/ggml-org/llama.cpp/pull/32919) | M | Vulkan 別トラック、後者は前者依存 |
| VK-U | VULKAN-002 grouped-union 再評価 | H | 現行 mask_opt との差分評価 |
| G4-H | Gemma 4 Global FA DKQ512 WMMA | M/H | 別トラック、制約多い |
| G4-V | Gemma 4 Vulkan ub512/1024 切り分け | H | 先に同一条件 A/B |
| MTP | 過去 MTP-DENSE/QSA-NOOP/Stage-B 等 | H | MTP ON ベースライン後 |
| KV-Q | KV 量子化 | M/H | 非等価、品質優先のため保留 |
| FA-G | COMMON-005 compact-KV gather TG 再移植 | S（Sonnet） | 既存候補の独立項目化・比較対照/フォールバック、低工数なら先行 PoC |
| G4-B | Gemma 4 dense Q4_0 の形状別 hipBLAS/MMQ 切替 | S | 新規の具体的 PoC、別トラック |

## 4. Sparse FA の詳細とレビュー

現行ソース: [fattn.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/fattn.cu#L130-L298)、[fattn-mma-f16.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/fattn-mma-f16.cuh#L1931-L2010)、[qwen4exp.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/src/models/qwen4exp.cpp)、[fattn-common.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/fattn-common.cuh)。

- M0 は NVIDIA sparse FA の HIP 移植と、Top-K pool ID から LDS bitset/union を生成する方式を提案。初回は古い main ソースに基づき、8×8 PP / 1×8 TG の形状や HIP 既存経路を誤認した。詳細 M/H は現行 SHA を正しく使用し CDNA/MFMA の既存疎経路を認識。
- QSA は DKQ/DV=256/256、GQA=12、n_kv_max=2051（モデル条件は実機ログでも再確認）。WMMA の sparse 選択は現行の shall_use_sparse で除外される。may_use_sparse の既存 256/256 は 1×8、8×8。AMD WMMA デバイス側は ncols1*ncols2>=16、ncols2!=1、DKQ<=256 が必要。
- PP: RDNA の GQA 選択は ncols2=4、標準大バッチで ncols1=16。M/H の 8×4 は最小 WMMA 制約に適合する候補だが、may/shall の変更だけでは選択されない。H が指摘した switch_ncols1 の明示的な 8×4 選択が必要。4×4 / 16×4 も比較候補。テンプレート実体化、全レジスタ/LDS 使用量、境界、spill、stream-K、split/fixup、マスク・有限値扱いを検証する。
- TG: 現行の MMA 選択は Q*GQA>16 を要求するため単一 token/GQA12 は Tile へ。M0 の 1×8 は WMMA 不成立。H の 1×16 は最小幅を満たすだけで、GQA12 の余剰4ヘッドへの load/store ガード、ncols2 選択、出力境界、実体化を別途確認する必要がある。Tile #30370→#32741 を優先比較する価値が高い。PP と TG の採否を独立させる。
- #30370 の GCN 実測例（256/256、GQA12、F16、KV65536、n_kv_max2048）: nq1 505.6→180.4 µs、nq64 11594.3→1527.6 µs。#32741 は RDNA2/3/4 対応と16Bロード/LDS staging、#30370 に依存。gfx1151/Windows の実測ではない。
- #32731 は single-consumer TOP_K_MASK→[RESHAPE→]FA を融合し、sorted index と query mask を直接生成。RTX4090 サブグラフで decode64K 1.43–1.56倍、128K 1.92–2.24倍、prefill128K nb512 1.35倍。密マスクの読み書きを省くが **allocator の領域予約は残る**。最終 HIP 検証は PR 本文上未完了。M0 の独自 LDS 方式より upstream 追従性が良い可能性があるが、同一方式ではない。
- 256K/ub1024 の密 F16 mask は論理サイズ512 MiB/層。これを転送量または常時実占有量の実測と混同しない。8-query union の最大は8×2051=16408行。M0 の実測を称した union サイズ、H の2500–5000行は現行 gfx1151 では未計測。M の20000行の反証閾値は最大値を超える。Br=2/4/8/16、実プロンプトの平均・p95・最大・KV bin、重複率、padding を測定する。過去 [r5 64-query union 統計](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md) はグループ幅が異なるので直接転用不可。
- sparse FA 本体が短縮されても、密マスク走査・Indexer が残れば PP 全体が O(N) になるわけではない。密マスクのない経路でも Indexer のスケーリングを別測定する。
- 数学的等価、許容誤差内一致、bitwise 一致、生成出力一致を区別。選択 index、tail、causal/sequence mask、物理 KV 行対応、tie、空集合、部分タイルをテストする。Gemma 4 は sparse 選択対象外でも回帰確認は必要。
- 比較対照: 現行 dense、r6 [COMMON-005](R6-COMMON005-IMPLEMENTATION-2026-11-02.md) 相当 compact-KV gather（TG）、VULKAN-002（PP）。新方式が旧方式の上位互換とは未確認。mask scan を含む全時間で比較する。

### 期待値の扱い

Amdahl: 全体倍率=1/(1-f+f/s)。r6 128K FA 比率 f=0.45 と仮定すると FA 部分 2/3/5/8倍で全体 +29.0/+42.9/+56.3/+65.0%、理論上限 +81.8%。H の256K PP +119% は f=0.62、s=8 の仮定で成立するが現行版の比率・倍率は未実測。別途圧縮コスト等が加わる。目標値と採用閾値を分離し、例えば+30%でも再現性・品質・安定性が良ければ価値がある。短文脈無退行、Gemma 無退行も実測で判定。

## 5. MMQ / TG / その他の候補の詳細

### MMQ-S: J=32 spill
[#31751](https://github.com/ggml-org/llama.cpp/pull/31751) は Q8_0 layout の AMD WMMA 内側 K loop を `#pragma unroll 1` で抑制。W7800 gfx1100 / ROCm10.1 / Q8_0 の 28列 MUL_MAT 時間−41.01%、PP32 +36.08%、256→104 VGPR、108→0 B scratch/lane、26→0 VGPR spills。IQ4_NL/Q4_0 等でも spill 解消報告があるが速度実測は Q8_0 のみ。現行 gfx1151/TheRock10.0 の spill を断定しない。[mmq-vec-dot.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/mmq-vec-dot.cuh#L145-L210) と実バイナリの metadata/ISA を照合し、使用中の J=32/type/shape を確認。scratch=0 でも VGPR/occupancy 改善はあり得る。r6 の [MMQ audit](R6-ROCM-MMQ-SOURCE-AUDIT-2026-11-07.md) は旧 RDNA4 設定の RGP であり、現在の RDNA3.5 設定と区別する。小規模 PoC は Hydrogen の実装能力評価にも使える。

### GDN-U: ubatch
[gated-delta-net-mma.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/gated-delta-net-mma.cu#L430-L455) の RDNA3.5 は n_tokens>=2048 等の条件で slice64 を選ぶ。ub1024→2048 で経路が変わり得る。実際の GDN shape・初期化成功とメモリ余裕を確認し、32K/64Kから試す。ub変更は他演算も変えるため GDN単体計測が必要。

### GLU-Q / MMQ-P / MOE-F
- #30489: GLU の F32 中間を書かず Down 用 Q8_1 量子化内で SWIGLU/GEGLU 等を計算。Dense/非broadcast routed MoE 対応、consumer・alias・入力依存条件あり。RTX4090 でモデル PP +1.0～1.8%、IQ2_S gate/up + IQ4_NL down の52,428,800 floats で差分0の報告。gfx1151や将来 FP4 の活性量子化経路での適用は未確認。
- #28714: MMA を分割し load/prefetch/LDS store をパイプライン化。Q4_0/Q8_0/Q4_K/Q5_K が対象、外部 pp4096 モデル +1.96～3.96%。Q4_0 の一部形状で約12%改善。Q6_K 等は対象外、Q8_0 は prefetch 単独で大幅退行する形状あり。組合せを確認。
- IQ2_S Gate+Up 融合は過去未ビルド PoC [V1](V1-STRATA-MOE-IQ2S-FUSION-POC-20261115.md) と Strata を参考に再評価。AMD WMMA、型対応、VGPR、中間バッファ、GLU-Q との重複を検証。FP4 移行後に IQ2_S がどれだけ残るかで優先度を決める。
- Dense GEMM は [Strata比較](V1-STRATA-VS-LLAMA-DENSE-GEMM-SOURCE-COMPARISON-20261115.md) を起点に実際の GEMM 型・形状・実行経路を再測定。外部の int8 KV 等による差を混同しない。

### MMVQ-T / FEW / MMVQ-B
[mmvq.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/mmvq.cu#L469-L555) の RDNA3.5 は RDNA2 table に割り当てられ、基本単一列設定 nwarps=1, rows_per_block=1。RDNA3.0 では Q4_0/IQ4_NL=8, Q6_K=2。RDNA3.5 専用 table を実測に基づき検討。nwarps 1/2/4/8、rows 1/2 を量子化型・行列形状別に、正当な組合せのみ sweep。host/device table 一致、reduction/境界、spill、数値誤差、実効帯域を確認。Gemma TG が100% MMVQ という意味ではない。

#32224 の 8060S / ROCm7.2.4 / Qwen3.8-27B Q4_K_M では ub8 PP 70.2→92.7 tok/s、ub16 +4%程度。Q4_K/Q5_K/Q6_K/IQ4_NL の型別小列範囲、IQ2_S/Q4_0 非対応。Expert 個々の少数 token が実際に few-row dispatch を通るかは要調査。#28613 の gfx1151 バッチ TG は npl4/6/8 で +6.4/+10.2/+20.5%、npl1 −0.8%（対照）。通常単一 token TG へ効果を転用しない。MTP 受理率・verify latency・総 TG を別測定。

### Vulkan / Gemma / KV / MTP
- #32528 の accumulate folding、#32919 の load-only prefetch は RDNA3/4 dGPU の外部実測。後者は前者に依存。Windows proprietary driver、RDNA3.5、実際の CM1 INT8 経路、FP 丸めの変化を検証。
- VULKAN-002 は現行 PP mask_opt と比較。過去版の改善率を新 baseline に流用しない。Gemma Vulkan は同一ドライバ/UMA/モデル/入力/ビルドで ub512/1024 ABBA、クロック/電力/RGP と Global/SWA を分離。
- Gemma Global FA DKQ512 の WMMA 解放は host 選択・device 制約の双方に変更が必要。Q_in_reg=false の設定が存在しても LDS/レジスタ/テンプレート/出力の適合は未確認。過去の TDR を考慮し、小規模限定テストから始める。
- KV量子化は非等価。Qwen QSA と Gemma の品質、変換コスト、実際の sparse 対応を独立検証する場合のみ候補化。
- MTP は過去の受理履歴差分等を踏まえて再評価。MTP OFF に効果なし。現行の baseline を先に取得。

## 6. 暫定ロードマップと採否ゲート

0. 既定計画 ROCmFP4 FAST HIP 対応を維持。IQ3/FP4/Gemma の測定対象を明確化。現行最終製品で64/128/256Kの PP/TG 基準と演算別 GPU 時間（FA、mask、Indexer、MoE、Dense、MMVQ、GDN）、HIP Graph 実行状態を確認。診断 ON/OFF の速度を混ぜない。
1. 低工数の MMQ-S metadata/ISA 調査、GDN-U ub2048 経路確認、必要なら MMVQ-T の小規模 sweep。実装着手順と期待効果順を区別する。
2. FA-P / FA-T / FA-R の独立 PoC。FA-G (COMMON-005) の現行適合性・再移植工数を事前調査し、低工数なら TG の先行対照を作る。PP の 8×4 選択と TG の Tile 対応を分離。TG MMA 1×16 は境界検証できた場合のみ比較。既存 COMMON-005 を対照に残す。
3. FA-F（mask+圧縮の占有率とメモリ量に応じて）を独立検証。
4. GLU-Q、MMQ-P、MMVQ-T、MMQ-S の実測有望なものを一つずつ検証。MoE-F/GEMM は FP4 後の残余比率で再順位付け。
5. Vulkan/Gemma 別トラック（G4-B の限定 dense Q4_0 BLAS/MMQ A/B を含む）、MTP ON 再評価時に FEW/MMVQ-B/過去 MTP パッチ。KV-Q は必要性が出てから。

共通ゲート: [AGENT-RULES](automation/AGENT-RULES.md) と標準計測 runbook を遵守。既知の test-backend-ops TDR リスクがあるため全件一括ではなく対応済み・小規模な限定ケースから、停止監査を挟む。変更前後のビルド identity、入力/model hash、環境、実行経路を記録。A/B または ABBA、短文脈 smoke→32/64K→128/256K、メモリ容量判定、GPU エラー/残留プロセスなし。F16 KV・同一量子化・MTP OFF の等価比較を基本とし、出力/数値比較、必要に応じて日本語要約・MH-Hard、Gemma 回帰を行う。速度差はばらつきと手戻りも含めて判断する。予測値を機械的な合格基準にしない。

## 7. 未確定事項と次回更新

- Medium/High とも同じモデル系列の独立セッションであり、同じ結論は実機での独立証明ではない。
- H は最新 D0-4B 数値を拾ったが最終 SHA に帰属した点を訂正。M は最新長文脈値を一部見落とした。M の Gemma TG Amdahl 上限は MMVQ 以外だけを高速化する場合に限定される。
- H の推定改善率、Windows 動作可能、Gemma 副作用ゼロ、J=32 spill 断定は未確認。外部 PR 本文と主要ソースは照合したが全差分/コメント/実機を網羅した検証ではない。
- Sonnet の結果は第8節へ追記済み。今後も新規独立調査中は本統合文書を参照させない。製品ソースや既存ロードマップは本記録では変更しない。

## 8. Sonnet 5.5 Medium の独立調査と統合レビュー（2026-11-28）

### 8.1 調査範囲と制約

Neon A1/A2 と同一詳細プロンプトで開始。初回停止後、同じ Conversation に固定 SHA と完了済み成果を再利用する再開指示を送った。報告上、4サブエージェントの成果は取得できず、メインが固定ソース/文書を読み直した。最新 main の統合文書は参照させていない（ログに再取得や当文書参照は見当たらず、固定 SHA 使用を本人が報告。内部状態の完全監査は未実施）。最終レポートは10候補。実機計測なし。

参照: 製品 a650d641 / 文書 2a65d862、Strata c234774038d1、upstream discussion #26377、issue #21284、PR #28195。最新 upstream HEADとの差分の網羅、外部forkの実ソース、D0-4B/D0-5、r6 COMMON-005 詳細、KNOWN-ISSUES、ROCmFP4 HIP review 等は未確認または未読。GGUF メタデータ未取得。Sonnet 自身が限界を明記。最新 PR の探索が不十分で、Neon が発見した #30370/#32741/#32731/#31751/#30489/#28714/#32224 等を否定する材料ではない。

### 8.2 10候補と既存台帳との対応

| Sonnet 候補 | 統合台帳 | 扱い |
|---|---|---|
| 1: COMMON-005 gather TG | FA-G | 明示的な比較対照/条件付き先行 PoC に昇格 |
| 2: WMMA sparse-index FA | FA-P/FA-T | 重複、詳細は Neon 案を優先し union 実測を追加 |
| 3: Gemma Q4_0 BLAS/MMQ | G4-B | 新規の具体的な低工数検証 |
| 4: fresh RGP/MMQ/非FA | ロードマップ0 | 共通の前提計測 |
| 5: indexer/mask/get_rows | FA-F/残余調査 | 重複、現行内訳測定後 |
| 6: D256 Tile/MMA tuning | FA-P/FA-T | 未具体化、実測後 |
| 7: MTP stack | MTP | 重複 |
| 8: Vulkan union | VK-U | 重複 |
| 9: Gemma Vulkan PP | G4-V | 重複 |
| 10: Strata PF_PAD/GEMM/MoE/HC Q8 | GEMM/MOE-F | 既往、HC Q8は非等価として別扱い |

Sonnet は新規高速化として FA-G を最優先、G4-B を2位、FA-Pを3位とした（着手前に fresh RGP）。これは過去の実測と実装工数を重視した順序。Neon のカーネル内 sparse FA と対立するというより比較対照の重要性を強める提案。全体ロードマップは ROCmFP4 FAST HIP の既定計画、現行プロファイル、独立PoCを維持する。

### 8.3 FA-G: COMMON-005 の再評価

- Sonnet の +10/+24.3/+48.7% (64/128/256K TG) は旧 r3 の [PATCHES](PATCHES.md#L736-L873) に基づく。r6 詳細を未読だったため、より新しい [r6 b12013 / f29592d6a の ABBA](R6-COMMON005-IMPLEMENTATION-2026-11-02.md) を優先参照する。
- r6 PLE16 / F16 KV / MTP OFF / ub1024 の同一ビルドABBA: 64K 21.80→24.56 (+12.66%)、128K 17.625→22.715 (+28.88%)、256K 12.665→19.760 (+56.02%) tok/s。異なる版へ保証される値ではない。4K fallback と32K smoke、長文脈安定性ゲートを通過したが、既知の非決定性のため品質完全等価や default ON は未承認。
- r6 は single-token/single-sequence、opt-in QWEN4EXP_QSA_GATHER=1、選択 pool の全メンバー＋tail から n_sel=2051 を構成し、F16 KV を gather→F32→F16 経路で compact 化、n_kv_max=0 で通常FA。旧 r3 固定幅2048と区別。MTP ON と量子化 KV は未検証。Sonnet の old get_rows 時間は旧診断区間であり現行の残余コストとは限らない。
- b12651 で既存グラフ/API/型/stride/sequence/物理セル対応を照合し、独立 opt-in PoC。現行の密FA、FA-G、#30370→#32741 の Tile sparse を同じ model/seed/input/KV/ubatch/build identity で比較。128/256Kに進む前に4/32/64Kゲートと出力/数値/メモリ確認。gather の効果は PP へ流用しない。
- 旧 top_k 非決定性や argsort+cont コストを b12651 へ無条件で転用しない。現行 top_k で選択集合と tie、出力の再現性を測定。既存パッチの品質評価は smoke レベルである。

### 8.4 G4-B: Gemma dense Q4_0 hipBLAS/MMQ

固定製品の [mmq.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/ggml/src/ggml-cuda/mmq.cu#L395-L528) を再確認。通常の MMQ 対応型/48KiB shared-memory/コンパイル条件等を満たす RDNA3.5 WMMA の Q4_0 は switch default true で、大バッチの BLAS crossover は未設定。全演算が MMQ になるという意味ではない。

過去の [Q6_K 強制ルート実験](V1-STRATA-Q6K-DENSE-BLAS-MMQ-EXPERIMENT-20261115.md) の実測（別モデル/型）:

| shape | N | BLAS us | MMQ us |
|---|---:|---:|---:|
| Attn Q K2560/M12288 | 512 | 1501.72 | 2220.61 |
| 同上 | 1024 | 2581.34 | 4122.41 |
| Attn Output K6144/M2560 | 512 | 1832.11 | 1100.88 |
| 同上 | 1024 | 2405.51 | 2709.23 |

Sonnet の「N<=512はMMQ有利」は過度な一般化。Attn Qでは512でもBLAS優位。旧実験は実モデル PP 改善未実証で停止。Q4_0の予測+10–20%や1.3–1.5倍は根拠の弱い仮説で採用基準にしない。Gemma の実際の dense projection/FFN shape と N の分布を確認し、gfx1151・HIP・Q4_0・dense・実測形状限定の default OFF ルート指定で dequant+BLAS と MMQ を比較。全 backend の FORCE_CUBLAS は使用しない。既存の選択条件、非連続/バッチ/alias、MoE/MUL_MAT_ID、Qwen、FP4、TGを巻き込まないよう host dispatch を追跡する。単なる1行変更で安全に限定できるとは未確認。F16 dequant+GEMM と量子化 MMQ は近似数値一致を確認する必要があり、bitwise等価ではない。追加バッファ、実帯域、WDDM、32K PP/TG、品質と出力を確認。

### 8.5 ソース/推定の追加レビュー

- Sonnet は QSA sparse MMA の WMMA最小幅、ncols2=4、CDNA/NVIDIA限定を認識し、広範 backend-op テストでの TDR 既往を考慮した限定テストを提案した点が良い。ただし GQA12 は未確定と報告しており、Neonの 8×4 明示 dispatch や TG Tile の関連PR調査ほど具体化されていない。実測モデルメタデータを確認する。
- QSA top_k=2048 はセル予算、kpool=4 の場合の pool 選択は最大512、tail込み n_sel=2051。[qwen4exp.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a650d641ee99198543697e1e3913c593059721f7/src/models/qwen4exp.cpp#L897-L923) で n_top_pool=min(n_pool,indexer_top_k/kpool) を確認。pool indexとセル indexを区別する。
- 16-query union の理論最大は16×2051=32816行。128Ki KV の約25.04%、256Ki KVの約12.52%。Sonnet の40%超という撤回条件はこれらの深さで成立しない（より短いKVでは成立し得る）。128Kの20%閾値だけで採否を決めず、実分布、圧縮・padding・occupancy・総FA時間で判断する。
- Sonnet が r5 64-query union を11k–17kと要約したのはコード入力の一部KV binに偏った値。[3 corpus統計](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md) では文学/randomはさらに大きい。コードの値を全入力へ一般化しない。
- PP/TG latency の定数＋KV依存項の近似は有用な仮説。ただし総スループットから FA と Indexer を分離できない。Sonnet の256K FA占有率50%・3/5倍FA改善なら全体は1.50/1.67倍、FAだけの理論上限は2倍。3.1倍はKV依存項68%全体を除去した別の仮想上限で、Sparse FA単独には使えない。r6プロファイル及び現行実測で再推定する。
- Sonnet は clean b12651 基準を使用し、D0-4B 長文脈 PLE16 を未確認。Highの最終SHA誤帰属を繰り返してはいないが、現行 PLE16 の基準として十分ではない。
- 追加調査で新たに採用確定したパッチなし。ChatGPTは mmq.cu、qwen4exp.cpp、r3/r6 gather 文書、Q6_K BLAS/MMQ 実験、union 統計を再確認した。Sonnetの全ソース主張や外部資料の全件再照合、実機計測は未実施。

### 8.6 更新後の方針

既定の FP4 HIP 対応を優先し、その後に現行 profile。TG の COMMON-005再移植工数を調べ、低工数なら opt-in 比較対照を作成する。新しい Tile sparse FA と比較して維持/置換/撤回を決める。PP WMMA sparseは独立で進める。Gemma Q4_0 BLAS/MMQ は小規模な別トラックとして、#28714等のMMQ改善とは個別に比較。その他のNeon候補は維持する。
