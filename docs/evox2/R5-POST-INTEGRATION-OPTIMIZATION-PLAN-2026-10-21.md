# Evo-X2：統合版完成後の高速化候補・最終優先順位

> **2026-10-29 post-integration re-prioritization (supersedes the 2026-10-21 provisional ranking for the next task):** [New r6 S9 full speed inventory, raw run evidence and ROCm 64/128/256k comparison](R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md). The user selects **ROCm HIP long-context PP **and** TG** as the next investigation priority. Integrated ROCm IQ3 PLE16/MTP-ON (DENSE+NOOP ON) was 371.43/28.63 at 64k, 282.24/22.64 at 128k, 184.79/15.04 at 256k (PP/TG tok/s); compared with r6 clean *Original/MTP-OFF*, PP is about 7–8% lower even while TG is higher. Do **not** conflate model layout and MTP differences, or treat context scaling as an integration bug without matched controls. First preserve same-build same-model MTP OFF/ON controls, then use selected RGP/HIP/host profiling to locate the actual long-context QSA/FA/GDN/Draft/memory bottleneck; **COMMON-005 HIP compact gathered K/V is a candidate, not yet a proven fix**. Vulkan CONCAT/FA, s1/Strata, and corpus/MoE visualization stay in the backlog. No new patch, source repin, default all-ON preset, or unsafe broad ROCm FA test is approved by this research priority update.


更新日：2026-10-21 JST  
対象：Windows 11 / GMKtec Evo-X2 / Ryzen AI Max+ 395・gfx1151 / UMA 96GB / llama.cpp / Qwen3.8-Flash-Next / UD-IQ3_XXS・ROCmFPx / f16 KV / 長文PP・TG / dense Draft MTP。

本書は、s1・Strata調査、外部情報の追加調査、添付のDeepSeekレビューを統合した判断文書である。レビューの追加情報を一次資料・PR差分・r5とupstreamの実装で再確認し、妥当な指摘を採用した。旧2文書の候補優先順位は本書に置き換える。過去の実測記録やr5の統合計画自体は変更しない。

**推奨順は、統合版の固定 → 設定・実dispatchの監査とMMVQ幅の確認 → CONCAT → upstream収録分を除いたFA改善 → 残るkernel／host処理の選別。** halo-boxとtethertoの分解済み移植記録を主要な参照先に追加する。Gufo Windows版、pwilkin、s1、Strataは、それぞれ得意な部分の比較対象として残す。

今回行ったのは資料・ソースの調査。新しいWindowsビルド、Evo-X2での性能測定、実装の採用判定は行っていない。以下の「最終順位」は調査時点の着手順であり、未完成の統合版の速度を予測した順位ではない。

## 2026-10-25 最新予定（下記10/24予定より優先）

- **完了：** 直接ID検索（旧V1）128k/192k、CR-128K、MH-128Kの試験。MHは Qwen3.8 **4モデル×2seed×A/B=16run**（IQ3 45/48、FP4 48/48、IQ4 48/48、Huihui 46/48）。生成器・独立oracle・採点器・詳細結果は[専用実験リポジトリ](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval/EXPERIMENTS-2026-10-25.md)へ保存。Gemma 4の長文PPは今回の研究本筋とは切り離す。
- **直近：** 本書の研究候補への着手ではなく、[r5統合版作成](R5-INTEGRATION-PLAN-2026-10-21.md)を優先。完成後は旧b11592と凍結MH入力で最小限の品質・性能回帰チェックを行う。詳細は[10/25引き継ぎ](R5-MODEL-QUALITY-AND-POST-INTEGRATION-HANDOFF-2026-10-25.md)。
- **統合後：** 必要なら複数成立経路からの選択を要求するMH-Hardを別版として設計。Gemma 4は統合版で16k/32kと選択した長文を再測定し、必要に応じてFlash Attention kernel経路を調べてから高速化ターゲット採否・優先度を決める。QSA mask/selected IDs、入力別MoE Expert routing、選択したROCm RGPも継続候補とする。
- いずれも**統合版作成のブロッカーにはしない**。下の技術最適化順位・ガード・既存測定provenanceをこの品質結果だけで書き換えない。

## 2026-10-24 作業順変更（下記10/21時点のキューに優先）

- **完了:** ROCm runtime整合、同一seedの出力再現性、Windowsイベント確認、モデル速度比較、5モデル×5プロンプトの要約出力比較。要約55runとバックエンド比較は[実験専用リポジトリ](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/summary-prompt-variation)に記録。
- **次:** [V1検索・照合ベンチマーク](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/search-retrieval)を128k、5モデル、設問順序の対照条件で実施。全モデルが満点に近く差が見えない場合に256kを検討する。
- **その直後:** 最新upstreamでr5統合候補を作成。統合手順・検証基準は[R5-INTEGRATION-PLAN-2026-10-21.md](R5-INTEGRATION-PLAN-2026-10-21.md)を維持する。下記の可視化・新規調査が統合作業を待たせない。
- **統合版が動作・回帰検証を通過してから:** llama-bench入力種類差による**QSAのmask/選択ID**の可視化、対象を絞った**ROCm RGP**の続き、および**MoE Expertの選択・ルーティング頻度／分布**の入力依存性を併せて調べる。最後の項目は最近紹介された記事をきっかけとする**新しい研究候補**で、計測方法・入力・統計量は未確定。既存の入力7種類の比較や同一入力での反復を活用しつつ、QSA選択とExpert選択を混同しない。
- 本書の下記候補順位は**統合完了後の最適化仮説の優先順位**であって、V1・統合版作成より先にmask/RGP実測を完了する指示ではない。統合後の実測を使って新規高速化への着手順を再判断する。

## 0. 直近のROCm確認タスク順 — 2026-10-21追記（当時の計画・上記で置換）

高速化候補へ戻る前に、ROCm側の provenance / correctness / model差を次の順で処理する。

1. **ROCm build/runtime provenance確認** — 完了。[記録](R5-ROCM-RUNTIME-PROVENANCE-ABBA-2026-10-21.md)。b11521はTheRock/ROCm SDK 10.0.0 buildだが、旧runtimeはBLAS境界で`ROCm\\7.2` install rootと混在していた。64k same-binary ABBAではwarm後の速度差は実質なし。
2. **ROCm出力再現性調査** — 次に実施。最近の同条件runではVulkanは複数回一致する一方、ROCmはtemp=0/fixed seedでも時々出力が変わる。runtime ABBAでもpure-TheRock B1/B2が一致しなかったため、runtime統一とは別のcorrectness課題として扱う。
3. **ROCmFP4モデル vs Unslothモデルを同一llama.cpp binaryで速度比較** — 出力再現性の切り分け後。同じunified TheRock 10.0 runtimeを使う。
4. **入力種類比較の続き** — QSA mask可視化を先に完了し、その後selectedなROCm RGPへ進む。
5. **needle test v1** — Qwen3.8 ROCmFP4とGemma 4に適用する。

今後のWindows ROCm buildは`Build-ROCm.ps1`の`TheRockUnified` policyを使い、既定ではROCm SDK 10.0.0を要求する。2026-10-21以前のROCm測定値は、実ロードDLL provenanceが別途確認されていない限り、mixed-runtimeの可能性を注記する。

## 1. 固定する前提と、今回変えない基準

- まず[r5最新統合計画][r5-plan]を完了する。PLE16、ROCmFPx、VULKAN-002、MTP-DENSE/NOOP、Stage-B、eh_proj flattenは既存候補で、新規高速化として再登録しない。
- 最初の対照は、現在のモデル・入力・f16 KV・dense Draft・full GPU offloadを維持する。量子化変更、入力削減、sparse Draftは別研究にする。
- 研究の目的は、Windows/Evo-X2上の仕組みを理解して再現できる改善を積み上げること。[既存方針][r5-policy]に従い、実用サーバーのcacheを有効化した速度とcold PPの研究を混ぜない。
- 統合時は選定したupstream SHA、統合後SHA、binary、モデルhash、driver、toolchain、実ロードDLLを一つの実験manifestに記録する。過去資料のSHAを消して一つに書き換える意味ではない。
- 成績はPP tok/s・TG tok/sに加え、同じ入力のPP秒、固定出力token数のTG秒、必要に応じTTFTで比較する。診断を有効にしたrunの時間は通常runと分ける。

## 2. 最終的な着手順

工数は実装範囲の目安。「小」は設定確認や局所差分、「中」は複数kernel／graphの適応、「大」はbackend・状態管理の再設計。ビルド待ちや128K/256K計測時間は含めない。全項目を順番に実施する計画ではなく、適用条件を満たさない候補は飛ばす。

| 順位 | 作業と候補 | 進める条件 | 工数 | Evo-X2で減らせる秒数 |
|---|---|---|---|---|
| 0 | 統合版を完成・固定 | 既存のQwen/Gemma・MTP・backend検証を通す | 既存計画 | 新規改善の比較基準 |
| 1 | 実行条件・build/runtime監査、MMVQのN=1〜8確認 | 実際のtensor型・kernel・環境変数を取得 | 小 | 未算定。誤設定・dispatchの問題がなければ0 |
| 2 | Vulkan transposed CONCAT：#30591を第一比較対象 | 新baseに未収録で、実CONCAT時間が残る | 小 | 未算定。対象CONCAT時間が削減の上限 |
| 3 | Vulkan FAの残差分：P-fragment配置、multi-row、V転置 | #27703等の既存分を除き、該当FAが律速 | 中 | 未算定。FA短縮からcopy/scratch増分を引く |
| 4 | 残るGPU処理を選ぶ：小融合、IQ3_XXS、HIP FA/GDN | 下記4章の候補ごとに実時間とguardを確認 | 小〜中 | 各対象opの総時間から見積もる |
| 5 | 残るhost／状態処理：同期、copy/rollback、state view、graph cache | NOOP等の統合後も待ち・再構築・コピーが残る | 小〜大 | 非重複の待ち時間・コピー時間が上限 |
| 6 | 小weight読込：Gufo型別vector load、条件付きbf16 twin | 対象dtype・値・shapeが合い、読込費用が残る | 小〜中 | 未算定。小projectionの合計時間を使う |
| 7 | Draft shortlist、用途限定prompt lookup | Draft LM headが重い／コード編集等に一致区間が多い | 中 | Draft削減とacceptance・verify増減の差で決まる |
| 8 | QSAの中期研究：union閾値、indexed attention、selector | 既存の選択ID・maskを保って総時間を改善できる | 中〜大 | score→TOP_K→index/mask→attention全体で評価 |

**順位を上げる条件：** HIP長文でFAが大半を占めるならHIP FA／selected-ID研究を4・8から前へ出す。MTPのGPU空き時間が大きければ5を前へ出す。MMVQの崖が実機で出れば1の直後にdispatch修正を行う。こうした判断は統合版の測定に基づき、外部の最大改善率では決めない。

秒数は現段階では埋めない。候補対象の実時間をt、同じ条件で測ったkernel速度比をr、新たなcopy・同期費用をcとすれば、概算は「t × (1 − 1/r) − c」。並列実行が重なる区間ではkernel時間の単純合算を使わず、wall timeで確認する。例として対象処理が10秒、2倍速、追加費用1秒なら削減は4秒であり、PP全体が2倍になるわけではない。

## 3. 最初に確認する監査項目

### 3.1 設定・ビルド監査を採用。ただし無差別な再スイープはしない

| 確認項目 | 今回確認できたこと | 統合版で残る確認 |
|---|---|---|
| upstream／統合SHA | r5 pin、当日のwatch SHA、調査snapshotは別の役割 | 選定upstreamと完成版SHAをmanifestに固定 |
| ROCm build/runtime | 現ソースには旧GGML_HIP_ROCWMMA_FATTNのoption・実装が見当たらない | CMakeCache、未使用option警告、実ロードHIP/BLAS DLL、実FA kernel |
| Vulkan MMVQ | DISABLE/FORCEは環境変数の値でなく存在を判定 | 両変数の残留を消し、対象型とN=1〜8のdispatchを記録 |
| PLE prefetch | joined lazy PLEとsplit PLE16で経路が違う | Original/split、host/device配置、page fault・I/Oが残るか |
| 電力・driver | ADLX/P-MODE計測基盤は既存 | Performance状態、clock/温度、RDP等の条件、driver/DLL同一性 |
| batch／ubatch | ub1024と2048でGDN等のdispatchが変わる | 必要なshapeだけ比較。全設定の総当たりはしない |
| UMA／HAGS／KV dtype／cache | 現在の基準はUMA96GB・f16 KV・cold条件 | 不具合・メモリ不足・別用途の理由が生じた場合に別実験 |

レビューの「設定だけで−41%〜+50%が動く」を現在の期待値にはしない。旧kernel、別モデル、別OS、build変更が混在している。build-time optionを変えるなら別binaryであり、「全て同一binaryのON/OFF」という手順にはできない。

### 3.2 MMVQ：kernel最適化の前に、使うべきshapeを確認

[upstream #25666][pr25666]はgfx1151/RADVの35B-A3B、Q6_K＋Q4_K、MTP最大draft2で、TG 75.2→84.9 tok/sとacceptance上昇を報告する。小さいNにも既存の型・K別選択を適用する提案であり、全てのMMVQを無効にするpatchではない。

[upstream #29679][pr29679]はRX 7900 XTX・Windows 11・26.8.1で、4-row workgroupがN=5〜7で遅くなる例。**これはgfx1151実測ではない。** PR自身がdriverとGPU差を切り分けておらず、MUL_MAT_IDも未測定と明記する。レビューの「gfx1151で逆向きの証拠が2件」は「gfx1151/RADVの1件＋Windows/RDNA3 dGPUの1件」に修正する。

推奨する確認順：

1. 常用モデル内の対象tensorのdtype、dense／routed、M/K/N、実kernelを取得する。
2. 対象型・shapeの演算をN=1〜8で測り、特に5/6/7の崖を確認する。短いllama-benchは補助で、MTPと同じ経路の証明にはしない。
3. 既定dispatchとMMVQ無効の診断比較を行う。全体無効はDraftや他の演算にも作用するため、結果だけで原因を1箇所に帰さない。
4. 崖や不利な選択がある場合だけdispatchを局所修正。ない場合にs1 #0236のweight展開再利用を検討する。

**重要な手順訂正：GGML_VK_DISABLE_MMVQ=0でも無効化される。** 対照は変数を削除した状態。PowerShellでは、対照側でRemove-Item Env:GGML_VK_DISABLE_MMVQ、無効側で値1を設定する。GGML_VK_FORCE_MMVQも対照から除き、各条件を新しいprocessで開始する。

DraftMax 2/4/7の最大verify幅は通常3/5/8。これだけでN=6/7のkernelを必ず検査したことにはならない。op試験の幅を補い、実runでは実際のverify幅分布を記録する。

s1 #0236はQ4_0/Q5_0/Q8_0/Q4_K等の通常MUL_MATが中心で、IQ3_XXS・ROCmFPx・routed経路全体の改善ではない。したがって**却下ではなくdispatch監査後へ延期**する。[実装][s1-mmvq]

### 3.3 旧rocWMMA情報は、現行設定の推奨に使わない

[#24562][pr24562]はclosed・未merge。コメントでは保守者が旧WMMA FA kernelとbuild引数の廃止を説明している。今回のr5・upstream snapshotでも、旧GGML_HIP_ROCWMMA_FATTNを有効にする定義は確認できない。

従って「#24562がmergeされてgfx1151を除外済み」「ONならOFFにするだけで現環境が大幅改善」は採用しない。古いCMakeCacheに文字列が残っていても使用されるとは限らない。必要なのは**現在のbinaryがどのFA kernelを呼ぶかと、どのDLLをロードするか**の監査である。古いbinaryを比較する場合だけ、その版のoptionとして別に扱う。

### 3.4 PLE prefetch：ログがないことを障害と判定しない

[#29599][pr29599]のrow prefetchは既存機能。r5のllama-mmap.cppにはWindows PrefetchVirtualMemory実装がある。joined PLEはTENSOR_READ_LAZYで作られ、lazy対象ならcan_prefetchへ登録される。[r5 loader/graph][r5-qwen]

一方、COMMON-001のsplit PLE16はheadごとの通常tensorを作り、graph側もsplit時はjoined PLEのprefetchを呼ばない。**split PLE16・GPU常駐でenabling prefetchログがないのは、実装上想定される。** Originalのlazy/host経路と同じ条件だと思って二重のprefetchを追加しない。

監査するのはモデルlayout、各PLE tensorの配置、実I/O、page fault、待ち時間。外部のpp512 177→383 tok/sはjoined/lazy等の条件付き報告であり、現在のPLE16への改善予測ではない。

## 4. 採用候補の技術別判断

### 4.1 CONCAT：小さな実装候補の第一位を維持

[upstream #30591][pr30591]を第一比較対象とし、[s1 #0036][s1-vk]および[tetherto #393][qvac393]の移植版を比較する。tiled transposeでstate＋転置入力の結合を速くする。主にPPで、現在のQwen4Exp graphに対象shapeがある。

Radeon 8060Sはgfx1151で、ハードの適合性は高い。未確定なのはPR表のOS/driver、量子化、ubatch、baseとの差である。作者のFlash-Next IQ4_XS・ub2048では403.9→552.1 tok/s、tethertoのEVO-X2/RADV表では432→484。後者もVulkanの値であり、ROCmの+12%ではない。

この数字からWindowsの期待値を「0〜30%」とは置かない。まず対象op時間を測る。週末baseにmergeされるかは未定なので、統合時に確認する。旧#30149はclosed・未mergeで、#30591を追う。HIPのtransposed CONCATは別の[#28303][pr28303]として残す。

CONCATそのものを消すs1 #0228／[halo #161][halo161]は次段階。halo側にはgraph寿命・余分なconsumer・rollbackを含むテストがあり、s1独自のKEEP_ALIVE導入より先に比較したい。tethertoではtranspose改善後の増分が483→491 tok/sと小さい例があるので、**残るcopy時間が小さければ保留**する。単一の外部値だけで永久却下はしない。

### 4.2 Vulkan FA：halo-boxを昇格。ただし収録済み部分を引く

[halo #159][halo159]と[tetherto #396][qvac396]を主要資料に追加する。後者はEVO-X2/RADVで移植を分解しており、Flash-Nextのpp2048 at d32768が316.8→380.2 tok/sという報告がある。ただしd32768はub512・r1であり、cold 32K全体の処理速度ではない。

取り扱いは次のように分ける。

| 部品 | 判断 |
|---|---|
| strided f16 KVを連続scratchへcopy | [upstream #27703][pr27703]で収録済み。新規移植に数えず、統合版で実際に選ばれるか確認 |
| P-fragment loadのhoist、Psh配置 | 残差分の候補。現在のcm1 shaderとの差を抽出 |
| multi-row coopmat1、V転置scratch | 新規候補。Windowsのdriver/coopmat条件、scratch容量、maskを検証 |
| wave32 pin | donorのhead-size条件付き。hs256のFlash-Nextへ一律適用しない |
| NaN-safe／selected-key対応 | dense FA移植とは依存が違うため別に確認 |

upstream snapshotの#27703相当分岐はAMD・非RDNA4、query数256以上、strided F16/BF16 KV、dense cache layout、非coopmat2等が条件。Windowsを一律に除外していない。既に入った機能を「未導入の大きな穴」として重複実装しない。[実装][up-vk]

halo #159のFlash-Next REAP-320では0/8K/16Kの改善はnoise内とも記載される。tethertoはselected-key attentionを含まない別構成で、V転置/multi-rowをsparse gatherと併用しない。従って、**dense/通常FAの改善がVULKAN-002 unionにもそのまま乗るとは扱わない**。copy込みの総FA時間と、union ON/OFFの経路を分ける。

### 4.3 小融合とIQ3_XXS

| 候補 | 再利用の仕方 | 判断 |
|---|---|---|
| s1 #0227 SCALE+SiLU／ADD列+SCALE | shaderとdispatchを部分移植 | 残る演算列だけ。現upstreamのHC融合と重複する部分は省く |
| s1 #0061 ADD→SOFTPLUS→MUL | GDN gate融合 | 既存UNARY_MULからの増分を測る |
| halo #161 short-row normと融合 | 小headのnorm配置・fusion | dtype・reduction順を検証。CONCAT消去と独立に評価 |
| upstream #30904 IQ3_XXS matvec | 1 shaderの局所差分 | 実際に該当shaderへ入るtensorがある場合に優先 |

小融合の価値はdispatch数と実時間で判断する。「Windowsは常にRADVよりdispatch overheadが大きい」とは断定しない。s1の主な実装は[multi_add][s1-multiadd]、[scale_silu][s1-scale]、[add_softplus_mul][s1-gdn-pre]。

[#30904][pr30904]はpacked load・符号処理のhoist・局所累積。Windows/RX 9070 XTのdenseモデルで該当kernel時間約23〜24%減の報告があるが、Flash-NextのIQ3_XXSがどの経路にいるかが先。dense／routedを数えるだけでなく、実shaderと呼出時間を確認する。routed全体の効果も、routed中心なら効果ゼロという断定もまだしない。

累積順が変わるためbit-identicalを前提にしない。短いgreedy一致やPPLだけで長文MTPを合格にしない。ROCmFPxはこのshader最適化とは別に扱う。

s1 #0019のHC内CONT除去も局所候補として残すが、upstreamの融合経路では対象が減る。残るCONTの実時間がある場合だけ進める。#0205/#0230/#0238のoccupancy・dispatch・spec traceは、既存の診断で足りない観測を補う部品として扱う。[s1 backend][s1-vk]

### 4.4 HIP：halo-boxを主な比較先に加え、pwilkinを残す

[halo-box][halo-pinned]にはGDN prefill、decode周辺の融合、同一activationを読むmatvecのgroup化、MoE reduction、RDNA3.5 FAがある。ggml構造に近いため、独立engineであるStrataより先に差分を比較する価値がある。

ただし「完成度が高いのでpwilkinから全面的に乗り換える」とはしない。

- halo READMEはHIPの非同期実行で正しさの問題があり、CIではHIP_LAUNCH_BLOCKING=1を使うと明記する。現在のWindowsで同じ問題が起きるとは未確認だが、fork全体の無条件採用はできない。
- [halo #172][halo172]の大きな速度表は、別モデル・Q8_0・Linux・一部custom PM4 runtimeで、baselineと同一sessionでもない。PR自身もclosed・未merge。必要な変更が現在のmasterにあるかは個別sourceで確認する。
- [issue #198][halo198]はGDN/MMB等のVGPR spillでCI品質チェックが失敗する報告。ただし実dispatchと性能悪化は未確認で、spillだけを理由にkernelを却下しない。

GDNについては、[pwilkin 964c6f2][pw-gdn]のDPP集約・入力共有・multi-column構成と、haloの現在のkernelを比較する。前者はS_v128/H48/1seq/16〜32768token等の条件付き。現upstreamのHIP MMA GDNは2,048token以上のguardを持つため、**ub1024でAR経路に残るなら検討余地がある**。実kernelを必ず確認する。[upstream GDN][up-gdn-mma]

「stateをregisterに置く」だけを新規差分とみなさない。現upstream ARもtoken loopの外でstateをloadする。比較点は集約方式、load共有、中間書込、fusionの増分。decode fusionとprefill kernelを一つの改善率にまとめない。

HIPでFAが支配的なら、GDNよりRDNA3.5 FAを先に評価する。Q8 KV専用経路は現在のf16 KV基準に含めない。Strataは[GEMMのshape/版別tuning][strata-gemm]、[GDN中間書込削減][strata-prefill-kernels]、[selected-ID attention][strata-attn]の設計資料として残す。

### 4.5 GLU融合：#29948と#30489の対象を混同しない

[#29948][pr29948]はgate/up matmul＋GLUを融合するが、現差分はNVIDIAのMMA layoutに限定され、dense FFNが対象。一方[#30489][pr30489]はGLUをdown projection用Q8_1量子化へ融合し、gate/upの型が違う場合やrouted MoEも扱う。

両者は同じFFN内でそのまま重ならない。議論後に#30489がreopenされたのは補完的な適用範囲があるため。**AMDで#29948を上流の本命として優先する、というレビュー判断は採用しない。** #30489をStrata QFUSEと比較するHIP系候補として維持し、HIPのbuild・guard・実効果を確認する。

また「VulkanにはQ8_1 activation経路がない」は誤りで、r5にもVulkanの量子化activation経路がある。ただし、この2つのPRのコードはCUDA/HIP backend向けで、Vulkanへ自動適用されるわけではない。

### 4.6 Gufo Windows、同期・rollback・state view

[Gufo Windows版][gufo-win]はWindows 11・gfx1151・TheRockを明記し、[executor][gufo-win-executor]と[kernel][gufo-win-kernels]を確認済み。小copyをcompute kernelへ移すこと、採用長別rollback graph、scratch保持、submit/waitの整理を参考にする。

NOOP後にも必要なrollbackやcopyが残る場合に部分移植する。完了flagによる待ち方はcoherent allocation、device fence、timeout、error処理が必要で、単に同期を削除しない。pollがAPUのCPU/GPU電力配分に与える影響も測る。公開の全switch ON/OFF差を個別効果として加算しない。

[#30196][pr30196]は現在open・draft=false。出力の同期と並べ替えを一度行い、verify loopがviewを再利用する。**Draftだから降格という理由は撤回**し、重複同期が実際に残る場合の条件付き候補に置く。現在の作者速度表はNemotron＋DFlashの1モデル構成で、Evo-X2 MTPの速度根拠ではない。

[#30139][pr30139]とhalo #187のstate in-placeはidentity gatherをviewにする候補。NOOP/Stage-B/rollbackを含む統合baselineから、独立差分として試す。旧state読込と新state書込の順序、graph reuse、buffer再確保、restoreを重点確認する。Vulkanの結果は混在し、haloの新baseでも速度差がほぼnoise内の例がある。

s1の[graph/allocation cache][s1-context]と[backend側管理][s1-backend]は、graph構築・再割当の残存時間が大きい場合に進める。単純なprevious-graph再利用ではなく、複数graphの寿命・世代管理を含む設計として扱う。sampling候補窓も同様に、CPU時間の計測なしで「誤差程度」「大きく効く」のどちらにも決めない。

[s1 #0059/#0078][s1-sampling]の候補窓とGufo Windowsのfast samplingは、top_k先頭などsampler条件が合う場合の別候補。penalty・grammar・同点logit・NaN・候補順・乱数消費を保つ必要があり、GPU上の候補だけをhostへ戻せば常に同値とは扱わない。

### 4.7 小weightの読込：値を変えない案を先に

[Gufo #681][gufo681]はF16/BF16小projectionのscalar loadをvector化する。型・値・FMA順序を維持する設計で、Kやalignment、幅1〜8等のguardがある。kernel単体の改善はあるが、serve全体は小さくnoise内の比較もある。実dtypeで高速分岐が発火するかを調べる材料にする。

[halo #187][halo187]のbf16 twinは、全F32 weightを無条件に丸める案ではない。差分では**各F32値の下位16bitがゼロでBF16へ正確に表現できるtensorだけ**複製し、host bufferは避け、prefillには元のF32を残す。decodeでの読込量を減らす候補として採用する。ただし追加メモリ、backendの演算経路、実logitsを確認する。

これは[halo #190][halo190ref]のBF16→F16変換とは別。後者は小さい値のsubnormal丸めを許す説明があり、同じ「losslessなtwin」として混ぜない。一般的なnorm/routerの低精度化は別の品質研究にする。

### 4.8 Draft shortlistとprompt lookup

[#30380][pr30380]の動的shortlist、Gufoのrequest別shortlist、Windows forkの短縮headを参考にする。Target full headを維持し、Draft側の行列計算を減らす点に価値がある。dense Draftのattention設定を変える必要はない。

レビューが追加した[rdna-boosts issue #190][rdna190]は、**98,304が語彙数、promptは約24K、ctxは131,072**。測定は別flagのVulkan payloadで、投稿自身がspecとspeclessのgreedy不一致を留保し、[後続コメント][rdna190comment]でも投稿者が事前確認不足を認めている。従って+7.5%を検証済みの「98K長文での#30380の効果」として採用せず、順位を上げる根拠にしない。

候補自体は維持する。最初は日本語・コード・EOGとfallback、Draft計算量、acceptanceを測る。sampled decodingでは実際のproposal分布に整合するaccept/reject・残差処理が必要で、「Targetが検証するから同じ分布」とは断定しない。

prompt lookupはコード編集・引用・反復などで有用な別候補。Gufoの反復文での大きなTGを一般文章へ外挿しない。greedy、sampled、同seed再現性、target分布の維持は別の検証項目にする。

s1 #0056〜/#0190のadaptive draft長は低優先を維持する。s1側でもthroughput policyに利益なし・既定OFFとされており、先に固定長2/4/7の費用とacceptanceを測る。shortlistによる1回当たり計算量の削減とは別に評価する。

## 5. QSAと長文研究の整理

### 5.1 union閾値の限定的な比較は採用

r5のgrouped-unionは環境変数で有効にした場合、min_kv既定32768。閾値は変更可能だが、group sizeはVK_QSA_GROUP=64のcompile-time定数。query数2〜4096など他のguardもある。[r5 Vulkan実装][r5-vk]

従って採用するのは**既存の閾値だけを必要な範囲で比較する案**。16K付近で有利かは実測し、N=1 decodeには閾値を下げても入らないことを区別する。通常FAへfallbackすることと、モデルのQSA選択規則を無視することも同義ではない。

レビューの「閾値とgroup sizeの2変数を既存flagで振れる」は修正する。また既存CSVは元の閾値・groupで観測した集計であり、未観測の浅いKVや別groupのunion集合を正確には復元できない。必要なら対象範囲の統計・selected IDsを追加採取する。CSVから全て事前予測できるとはしない。

### 5.2 selected-ID attentionはCOMMON-005に紐づける

参考はs1、[Strata QSA][strata-select]、Gufo、[CIRU][ciru]、[pwilkinの実験][pw-journey]、[Volta fork][volta]。新規番号を乱立させず、既存COMMON-005のdecode移植とmulti-query PP拡張を分ける。

比較順は、同じscore・selected IDs・causal maskを確保 → 通常FAとindexed/gather attentionを比較 → selector/TOP_K自体を改善。indexer、選択、mask/index生成、gather、attentionを含めた総時間で判定する。dense attentionからQSAへ変えることを「全く同じ演算の高速化」とは呼ばない。

s1の中期候補は、#0130〜/#0237のmask metadata・device mirror、#0235/#0240/#0241のscore融合・f16 mirror、#0153/#0243のradix TOP_K・一時配列削減に分けて残す。[実装][s1-vk] f16 mirrorを使う計算は数値差の検証を伴う。maskの意味、KVの更新・巻戻し、cache無効化を共通の比較対象にする。

API上では、r5もs1もFLASH_ATTN_EXTのsrc[5]に選択情報を渡すが、shape・mask省略条件・解釈が同じではない。同じ入力番号というだけでは互換ではなく、metadata契約から適応が必要。StrataもHD256/GQA12・独自page/poolや加算精度に依存し、独自INT8 KVはggmlのq8_0 KVと同一ではない。[Strata attention][strata-attn]

[#30370][pr30370]のHIP sparse FAは現差分がGCN限定で、gfx1151では有効にならない。compactionやテストは使えるが、guardを外すだけでRDNA対応にはならない。CIRUの独自IU4・sparse Draft・runtime込みの大きなTG値も、そのまま移植効果にはしない。

### 5.3 正しさの確認と性能改善を分離

haloの解放KVセル初期化、NaN-safe処理、Vulkan radix TOP_Kのslot決定性は確認対象にする。ただし、それだけで過去のROCm出力変動の原因を未初期化KVと断定しない。Vulkan専用修正をROCmの根拠にもしない。

実際に影響する条件が見つかれば、最小の修正を性能patchと分け、同じ入力のstate・選択ID・logitsで確認する。決定性の改善を速度向上と同じ指標にしない。

## 6. 参考情報と、参照先の使い分け

| 情報源 | 主に使う内容 | 扱い |
|---|---|---|
| s1-fork | 小Vulkan fusion、MMVQ再利用、mask metadata、graph cache、indexed attention | 関数・shaderを部分再利用。Linux/RADV guardと既存upstream差を確認 |
| halo-box/strix-llama.cpp | ggmlに近いVulkan/HIP最適化、幅別dispatch、FA、GDN、twin | 主要donorへ昇格。ただし全fork採用・全HIP経路の正しさ承認ではない |
| tetherto/qvac-fabric-llm.cpp | #393/#396の部品別移植、EVO-X2測定、失敗条件 | 分解と検証方法の主要資料。古いbaseのupstream catch-upを新規改善から除く |
| pwilkin | DPP/GDN、TOP_K、HIP runtime、QSAの負例 | haloと併読。旧baseの大きな改善率を現在に流用しない |
| Gufo本体／pixmaate Windows版 | 小projection、shortlist、prompt lookup、Windows copy/rollback/wait | 独立engineから部分移植。両repoは別revisionとして扱う |
| Strata | GEMM tunerとfallback、GDN出力削減、QFUSE、CPU/GPU電力、Windowsメモリ | 大きな設計の参考。presetやexpert cacheを丸ごと持ち込まない |
| [Nathan][nathan]／gaetan系 | Vulkan wave32・tile・帯域制約 | halo等との共通patchを二重計上しない |
| CIRU／Volta fork | QSA選択・cache・長文index・境界条件 | 中期研究。独自量子化・sparse Draft・CUDA依存を分ける |
| [AMD GEMM解説][amd-gemm] | gfx1151のWMMA、LDS、VGPR、prefetch | 教材はFP16累積。現在のFP32累積の数値条件へ適応する |
| [AITER][aiter] | norm/quant/activation融合、GEMM/attention | gfx1151はExperimental。CDNA用kernelと区別し、Windows導入は別検証 |
| [FlashInfer][flashinfer] | selected block ID、page table、causal情報のinterface | metadata設計の参考。NVIDIA kernelの直接移植ではない |
| [Windows gfx1151 GEMM資料][win-gemm] | shape別測定、clock、fresh process、BLAS選択 | 別アプリの測定。全shapeでhipBLASLtが速いとはしない |
| [hipEngine][hipengine] | HIP kernel、CPU reference、strict比較 | Flash-Next公開運用範囲は32K。AGPL系のためコード再利用条件はMITと異なる |
| [hipfire][hipfire] | dispatch、kernel生成、XDNA2分担 | 独自runtime/format。native Windowsはbest-effort、NPUはLinux側 |
| [GateSight][gatesight]／[DMS][dms] | gateを使うKV削減、学習したeviction | 近似・別checkpointの研究。GateSightのコードは今回取得できていない |

Strataの形状別hipBLASLt tableは、architecture・ライブラリ版・shape・workspaceの検査とfallbackが前提。実モデルがquantized MMQへ行くならLt tableは直接の対策にならない。[tuning実装][strata-tuning]

Strataのshared expert別stream実行は、routed expertとの間にGPUの空き時間がある場合の中期候補。APUの帯域競合とgraph capture・event順序を検証する。verifyのPLE投影をまとめる発想も参考になるが、r5には既にn_tokens幅のprojectionがあるため、単なるbatch化を新規改善として数えない。[verify実装][strata-verify]

メモリ面は、Windows gfx1151でexpert arenaのGPU登録を避ける条件、OS commitと物理RAM、bufferの貸借・寿命を参照する。Strataの--no-prefill-borrowは独自expert cacheの設定であり、llama.cppのfull offloadに同名の対策を設ける理由にはならない。[platform設定][strata-arch]

[Strata #2711][strata2711]のCPU worker数と電力配分は既存-t/-tb/pollの実験へ取り込む。ただしVERIFY_PROFILEは現コードで融合・別stream条件にも影響するので、純粋なsleep効果とは断定しない。既に-t4/-tb4の構成に、15→6 workerの外部改善率を適用しない。

## 7. 却下・保留・別研究に回すもの

「却下」は今回の統合版後の同条件高速化として採用しない意味。永久に研究価値がないという意味ではない。

| 対象 | 判断 | 理由／再開条件 |
|---|---|---|
| #24562による旧rocWMMA OFF実験を現行の最優先にする | 却下 | PR未merge、旧optionは現sourceにない。actual DLL/kernel監査へ置換 |
| #30196をDraftだから降格 | 理由を却下 | APIはdraft=false。host待ちが残るかで優先度を決める |
| #29948をAMD向け本命として#30489より優先 | 却下 | 現実装はNVIDIA限定、対象FFNも異なる |
| +7.5%@98KをDraft shortlist昇格の根拠にする | 却下 | 語彙数の誤読、別実装・品質留保・投稿者の事後釈明 |
| 週末baseに#30591が入らないと決め打ち | 却下 | 現在openでも未来のmerge状態は未定 |
| s1 #0236を直ちに移植 | 保留 | MMVQの型・幅・dispatch監査後に判断 |
| s1 #0228／halo direct conv | 保留 | CONCAT改善後も中間copyが有意なら再開 |
| s1 adaptive draft長 | 低優先 | 作者のthroughput policyも利益なし・OFF。固定長の費用とacceptanceが先 |
| Vulkan chunked GDN一式 | 低優先 | halo #128ではop改善に対しe2e +0.2〜0.7%。FP16入力化も含む |
| s1 #0233 HC大tile | 却下 | gfx1151で作者側も悪化・OFF |
| s1 MoE #0231/#0232、HC #0234をWindowsへそのまま適用 | 却下 | AMD proprietary driver除外とdtype限定がある。型別tile研究は残す |
| s1旧FA tile/GQA設定、Linux madvise/GTT設定 | 直接移植を却下 | 現upstream・Windows・unionの条件が違う |
| s1 sparse MTP／Strata窓／CIRU sparse Draft preset | 別研究 | dense Draftの状態を維持する最適化ではない |
| --spec-prefillでprompt token自体を省略 | 別研究・低優先 | 入力を変える近似。原文全文を扱う長文評価と同じ条件にならない |
| BF16→F16の丸め、一般的な低精度weight化、q8 KV | 別研究 | 値やKV精度が変わる。exactなbf16 twinと分離 |
| prompt cache／cache-reuse | 実運用の別課題 | 再prefill削減は有用だがcold PP比較を置き換えない |
| UMA・HAGS・driver・batch・KVを一括で再スイープ | 保留 | 条件を増やし過ぎる。異常の根拠がある項目だけ独立に測る |
| PM4 runtime、NPU、GateSight/DMS | 長期研究 | runtime移植、OS、学習／近似の範囲が大きい |
| expert pruning、SSD streaming、expert二重cache | 現目的では低優先 | 現在の96GB/full offloadに必要か未確認 |
| [ik_llama.cpp][ik]全体移植、[Halogen][halogen]のkernel流用 | 優先しない | 前者は主にCPU/CUDA、後者はengine binary配布。参考・比較用途は残る |
| 外部%の合算、推定秒数の捏造 | 却下 | base・入力・OS・量子化・重複変更が異なる |

## 8. DeepSeekレビューをどう反映したか

| レビューの論点 | 最終判断 |
|---|---|
| 設定・build監査をコード変更より前へ | 採用。静的確認済み事項と実機の確認事項を分けた |
| MMVQのN=5〜7とdispatchを先に確認 | 採用。s1 #0236をその結果待ちへ移動 |
| halo-boxを主要donorへ昇格 | 採用。tethertoの分解表も追加。ただしHIP非同期問題等を併記 |
| 秒数と工数で判断 | 採用。現時点の秒数は未算定とし、対象時間からの算出方法を追加 |
| CONCATを最優先の小patchにする | 採用。監査後の第1候補を維持 |
| FA at depthを追加 | 採用。ただし#27703の収録済み機能を差し引く |
| #30196がDraft | 不採用。現在のAPI結果と不一致 |
| #24562でupstreamが対処済み、flagをOFFへ | 不採用。closed未merge、現sourceでは旧option廃止 |
| #30380にgfx1151・98Kで+7.5%の証拠 | 数値根拠として不採用。元issueまで遡り解釈を修正 |
| #29948をAMD側の本命にする | 不採用。NVIDIA限定guardと適用範囲の違いを確認 |
| PLE prefetchログの確認 | 条件付き採用。split PLE16ではログ不在が正常な経路 |
| bf16 twinの追加 | 採用。全値のexact判定とfallbackを条件にする |
| union閾値／group sizeのスイープ | 閾値のみ条件付き採用。groupは固定、既存集計からの完全予測は不可 |
| cacheで再prefillを減らす | 実運用の別評価として採用。既存のcold研究を優先 |
| KV初期化等を過去の出力変動の原因とみなす | 原因断定は不採用。該当条件の診断候補として残す |

## 9. 候補を採用するための最小限の検証

全てを256Kまで測り直すのではなく、変更の失敗条件を狙う。短い対象opで適用・正しさ・効果を確認し、現在の代表64K条件でrequest全体を確認する。128K/256Kは長文効果・境界・メモリリスクが残る候補へ拡張する。

| 変更 | 重点確認 |
|---|---|
| CONCAT・copy | dtype/stride、端数tile、短いtail、同じ値が同じ位置へ届くこと |
| 小fusion・IQ3累積・GDN | 演算誤差、logits、実dispatch、compiler差、MTP acceptance |
| MMVQ dispatch | 実モデルの型・M/K、N=1〜8、dense/routed、数値とacceptance |
| FA／QSA | copyを含む時間、scratch容量、mask/selected IDs、tail、GQA12、unionとの分岐 |
| state view／graph cache／rollback | reject後の再開、reset/restore、buffer再確保、別consumer、Target/Draft切替 |
| 小weight／twin | exact値判定、型別fallback、追加メモリ、選択されたGPU演算 |
| shortlist／lookup | 日本語・コード・EOG、proposal分布、greedyとsampling、fallback |
| thread/poll／wait flag | 出力同一性、CPU/GPU電力、GPU空き時間、持続的なwall time |

profileには対象opの総PP時間・ms/token・呼出回数を残す。Vulkan perf logger等は同期を増やすため、profileと性能測定を分ける。実測の変動幅内なら無理に採用せず、保留または取り下げを記録する。

統合版ではGemma4 31B/26Bの回帰も確認する。ただしFlash-Next専用guardの小実験ごとに全モデルを反復する必要はなく、共有backend変更と最終組合せの検証に割り当てる。

## 10. 調査時点の版・状態

| 対象 | 確認した値／状態 |
|---|---|
| r5 docs/source | a791848251cf6d7cce7a30e4724174322fed6929 |
| r5の従来upstream pin | de7fa0a3c6a2e1b4cd9f22eb8d6bf5b12dbdb63b |
| r5計画内の当日watch | 493253fe5a5af7e800b3c92a2452b5684a99e961。統合base選定ではない |
| 前2調査の比較用upstream snapshot | 8baabd53b77d1c48c6ef8d3b620436292f3f6231。統合base選定ではない |
| 新統合版のupstream／完成SHA | 未選定／未作成。本書では決めない |
| s1-public | 6228a635f11489ca8824ea8f16861e343989b43e |
| Strata main | 9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4 |
| halo-box master | da731374077f2ad9bdffd4848f782b5694b9bb68 |
| Gufo main | 0e4f987b8145bc37fca25b601881abd369982c36 |
| pixmaate Gufo Windows | 2eb0778ac15d9e1c18c5b2f9e5dbbecc19e20ec2 |
| #30591 | open、head 52e41a44519ec15ae197c65244bba8260af35978 |
| #29679 | open、head 5a6c26f4eb6c3e9faae52712b9b70425afc38ddb |
| #25666 | open、head e0649d3e02c0a2540a4a1d2b80f308083779e273 |
| #30196 | open・draft=false、head 77c1d264bf76a7e6130002c23d6caa3e1faece52 |
| #29948 | open、head 6e34e56db9384dfd9f247bd6af5bf5c04bf93f7e |
| #30489 | open・draft=false、head 784fd01678cb91227c8de2fa1566308e7e3e2244 |
| #30139 | open・draft=false、head ae2cae7228b902fb504a8cd9b4ee2e1cbbdfd4ae |
| #30380 | open・draft=false、head da03be64749b994d6dc2aeedff0a3b3da9f2b6fe |
| #30904 | open・draft=false、head ea67f25df05cd790a86c3f57a4f843321decb432 |
| #24562／#30149／#28427 | closed・未merge。現行候補と取り違えない |
| #27703／#29599／#28501／#29353 | 収録済み機能として扱い、選定baseで再確認 |
| tetherto #393／#396 | 同forkでmerged。ggml-org upstreamでのmergeとは別 |
| halo #159／#161／#128 | 同forkでmerged |
| halo #172 | closed・未merge。現在masterの個別実装と区別 |

## 参照先

入力資料：s1-strata-optimization-review-2026-10-21.md、evox2-broad-optimization-research-2026-10-21.md、deepseek-response 2026-10-21.md。前2文書の静的確認を引き継ぎ、今回追加された順位変更の根拠は一次資料と現sourceで再確認した。以下は本文から辿れる一次資料へのリンク。

[r5-plan]: https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a791848251cf6d7cce7a30e4724174322fed6929/docs/evox2/R5-INTEGRATION-PLAN-2026-10-21.md
[r5-policy]: https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a791848251cf6d7cce7a30e4724174322fed6929/docs/evox2/INTEGRATION-POLICY.md
[pr25666]: https://github.com/ggml-org/llama.cpp/pull/25666
[pr29679]: https://github.com/ggml-org/llama.cpp/pull/29679
[s1-mmvq]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-vulkan/vulkan-shaders/mul_mat_vecq.comp
[pr24562]: https://github.com/ggml-org/llama.cpp/pull/24562
[pr29599]: https://github.com/ggml-org/llama.cpp/pull/29599
[r5-qwen]: https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a791848251cf6d7cce7a30e4724174322fed6929/src/models/qwen4exp.cpp
[pr30591]: https://github.com/ggml-org/llama.cpp/pull/30591
[s1-vk]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-vulkan/ggml-vulkan.cpp
[qvac393]: https://github.com/tetherto/qvac-fabric-llm.cpp/pull/393
[pr28303]: https://github.com/ggml-org/llama.cpp/pull/28303
[halo161]: https://github.com/halo-box/strix-llama.cpp/pull/161
[halo159]: https://github.com/halo-box/strix-llama.cpp/pull/159
[qvac396]: https://github.com/tetherto/qvac-fabric-llm.cpp/pull/396
[pr27703]: https://github.com/ggml-org/llama.cpp/pull/27703
[up-vk]: https://github.com/ggml-org/llama.cpp/blob/8baabd53b77d1c48c6ef8d3b620436292f3f6231/ggml/src/ggml-vulkan/ggml-vulkan.cpp
[s1-multiadd]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-vulkan/vulkan-shaders/multi_add.comp
[s1-scale]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-vulkan/vulkan-shaders/scale_silu.comp
[s1-gdn-pre]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-vulkan/vulkan-shaders/add_softplus_mul.comp
[pr30904]: https://github.com/ggml-org/llama.cpp/pull/30904
[halo-pinned]: https://github.com/halo-box/strix-llama.cpp/tree/da731374077f2ad9bdffd4848f782b5694b9bb68
[halo172]: https://github.com/halo-box/strix-llama.cpp/pull/172
[halo198]: https://github.com/halo-box/strix-llama.cpp/issues/198
[pw-gdn]: https://github.com/pwilkin/llama.cpp/commit/964c6f2f0b66008243883298f3f535bc99f5998c
[up-gdn-mma]: https://github.com/ggml-org/llama.cpp/blob/8baabd53b77d1c48c6ef8d3b620436292f3f6231/ggml/src/ggml-cuda/gated-delta-net-mma.cu
[strata-gemm]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/prefill/gemm.cu
[strata-prefill-kernels]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/prefill/kernels.cu
[strata-attn]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/kernels/cuda/qsa_prompt_attn.cu
[pr29948]: https://github.com/ggml-org/llama.cpp/pull/29948
[pr30489]: https://github.com/ggml-org/llama.cpp/pull/30489
[gufo-win]: https://github.com/pixmaate/gufo/blob/2eb0778ac15d9e1c18c5b2f9e5dbbecc19e20ec2/docs/WINDOWS.md
[gufo-win-executor]: https://github.com/pixmaate/gufo/blob/2eb0778ac15d9e1c18c5b2f9e5dbbecc19e20ec2/src/models/qwen38_flash_next/kernels/rocm/executor.cpp
[gufo-win-kernels]: https://github.com/pixmaate/gufo/blob/2eb0778ac15d9e1c18c5b2f9e5dbbecc19e20ec2/src/models/qwen38_flash_next/kernels/rocm/kernels.hip.cpp
[pr30196]: https://github.com/ggml-org/llama.cpp/pull/30196
[pr30139]: https://github.com/ggml-org/llama.cpp/pull/30139
[s1-context]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/src/llama-context.cpp
[s1-backend]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/ggml/src/ggml-backend.cpp
[gufo681]: https://github.com/gufo-org/gufo/pull/681
[halo187]: https://github.com/halo-box/strix-llama.cpp/pull/187
[halo190ref]: https://github.com/halo-box/strix-llama.cpp/pull/190
[pr30380]: https://github.com/ggml-org/llama.cpp/pull/30380
[rdna190]: https://github.com/stew675/llama-cpp-rdna-boosts/issues/190
[rdna190comment]: https://github.com/stew675/llama-cpp-rdna-boosts/issues/190#issuecomment-6288175263
[r5-vk]: https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a791848251cf6d7cce7a30e4724174322fed6929/ggml/src/ggml-vulkan/ggml-vulkan.cpp
[strata-select]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/kernels/cuda/qsa_select.cu
[ciru]: https://github.com/ciru-ai/Qwen3.8-Flash-CIRU-STRIX-IU4
[pw-journey]: https://pwilkin.github.io/strix-halo/journey.html
[volta]: https://github.com/jackjusko/jusko-llama-volta-qwen3flash
[pr30370]: https://github.com/ggml-org/llama.cpp/pull/30370
[amd-gemm]: https://rocm.blogs.amd.com/software-tools-optimization/rdna-fp16-gemm/README.html
[aiter]: https://github.com/ROCm/aiter
[flashinfer]: https://docs.flashinfer.ai/generated/flashinfer.msa_ops.msa_sparse_attention.html
[win-gemm]: https://github.com/kroqueta-s/gfx1151-gemm
[hipengine]: https://github.com/shisa-ai/hipEngine
[hipfire]: https://github.com/warpfront/hipfire
[gatesight]: https://arxiv.org/html/2610.14754v1
[dms]: https://arxiv.org/abs/2506.05345
[strata-tuning]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/prefill/hipblaslt_tuning.hpp
[strata2711]: https://github.com/Niko1221/Strata/issues/2711
[ik]: https://github.com/ikawrakow/ik_llama.cpp
[halogen]: https://github.com/peonist-ai/halogen-flash-server
[s1-sampling]: https://github.com/vahpetr/llama.cpp-s1-fork/blob/6228a635f11489ca8824ea8f16861e343989b43e/common/sampling.cpp
[nathan]: https://github.com/Nathanw1014/strix-halo-llamacpp
[strata-verify]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/core/verify.cpp
[strata-arch]: https://github.com/Niko1221/Strata/blob/9de04cd44e927a9a3df6bbc0e94fc1be8b844ba4/src/core/arch_defaults.cpp