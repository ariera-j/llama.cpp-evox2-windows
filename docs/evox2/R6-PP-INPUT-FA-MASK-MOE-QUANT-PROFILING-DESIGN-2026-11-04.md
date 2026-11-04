# r6 PP入力依存・FA／QSA mask／MoE／量子化×UBatch GPUプロファイリング：概要設計（2026-11-04）

> **Status: DESIGN ONLY / DEFER — 実装・ビルド・RGP採取・追加計測は未着手。**
> **PP調査・QSA UNIONとVRAMクロックの独立検証・Strata試用の着手順は未決定**。本書は着手時の見取り図であり、未完了作業の優先順位変更、r6の最適化フラグ変更、公開バイナリ更新を指示しない。

## 1. 調査の狙い／出発点

**中心課題：** どの入力文書で、どの処理（FA、mask、MoE、量子化GEMMなど）が、どのKV深さ・物理UBatch・バックエンドで時間を使い、PP全体の差を生むのかを、同一位置のGPUイベントと計測値で説明する。

**元の3テーマ（今回も主軸）：**
1. **ROCm / HIP FA:** 入力別PP差が旧Vulkanより小さく見えた理由。旧RGPでROM/HIP FAの特殊化は見つけたが、**同一レイヤー・KV長・マイクロバッチ・warmup／本計測を揃えていない**ため、厳密なGPU時間比較が未完。
2. **Vulkan / QSA mask可視化:** 旧r5で16×64タイルの ALL_NEG_INF／ALL_ZERO／Mixed の**数**は取得済み。次は実際の**位置・連結／偏り・query行ごとの形**を可視化して、非スキップタイル数2.58倍と同一FA本体時間4.1倍の残差を説明したい。
3. **MoE Expert選択:** 文書ジャンルによるExpert ID分布、物理UBatch内での**distinct expert数**、各Expertに割り当てられたtoken数、実際のMoE GPU時間が入力差に寄与するか。HF記事を仮説の手掛かりとして使う。

**追加の第4テーマ（2026-11-03～04実測から）：** 元Unsloth IQ3_XXS Ple16とIQ4_XS Ple16の**量子化テンソル構成／GEMM・MMQ・MMVQ・dequant・MoE MUL_MAT_ID dispatch**と、UBatch512／1024に対する応答がVulkanとROCmで異なる理由。量子化を変えるとrouterの選択も変化し得るため、**演算カーネルの違いとroutingの違いを切り分ける**。

### 先行資料と未解明点

- [Qiita 番外編5「入力文書と読み込み速度の関係（検証編）」](https://qiita.com/ariera/items/40c915c47009ec0a7e16)（2026-10-19）。旧r5 Vulkan b11535～b11571／ROCm b11543 の実験。Vulkan QSA UNION **OFF**、IQ3、64k、UBatch1024で、コード vs 日本語文学の全PP中のFA GPU時間 69.565 vs 102.460秒。RGPの同一FAノード KV=49152、N=1024、Qcur-19、Br/Bc=16/64でFA本体がコード約75.8～76.0ms、文学約311.0～314.1ms（約4.1倍）。mask分類49152タイル中スキップ可能 ALL_NEG_INF はコード36881（75.03%）／文学17538（35.68%）、非スキップは12271／31614（比約2.58倍）。元のRGP・mask診断は **investigation/r5-vulkan-off-fa-dispatch-20261010** にあり、r6 current sourceへ既に移植済みと仮定しない。
- 同記事の旧ROCm HIP RGPは \`flash_attn_ext_f16<256,256,16,4,false,false,false>\`（文学104.911ms／コード111.198ms）と \`flash_attn_mask_to_KV_max<16>\` を確認したが**取得したGPUイベントの位置・層・KV・warmup識別が未確定**。この2値をVulkanのKV49152 Qcur-19と同条件の直接比較に使わない。CUDA由来のcompact sparse gatherがHIPで無効だった調査結果と、HIPが末尾KV範囲を短縮できる可能性も、現行r6の実dispatchで再確認する。
- [r5 ROCm/Vulkan corpus PP](R5-ROCM-VULKAN-CORPUS-PP-64K-128K-2026-10-10.md)：旧r5、IQ3、UB1024でROCm入力差は64k約5.5%、128k約4.1%（旧入力群の max/min−1）、一方VulkanはQSA OFF/ONや入力で大きな差。**旧r5条件の観察であり、現行r6/量子化横断の結論ではない**。
- [Hugging Face「Sort your prompts」](https://huggingface.co/blog/badaoui/sort-your-prompts)（2026-10-19）：**複数リクエストのdecodeバッチ**をドメイン順に並べ、batch内のdistinct expertを減らす手法。対象はQwen3-30B-A3B等＋vLLMの専用実装であり、**単一長文のprefillやQwen3.8-Flash-Nextでの性能改善率を直接外挿しない**。本調査では「Expert分布・distinct集合・カーネル時間をセットで測る」という観点のみ移す。
- [r6 実入力bench／128k比較と生ログ集約](R6-LLAMA-BENCH-REAL-INPUT-CROSSCHECK-AND-ROCM-PLAN-2026-11-03.md)、[r6 COMMON-005以降の調査バックログ](R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md)、[r5 MTP/RGPのdispatch位置合わせ例](R5-MTP-PP-KV-CROP-STAGE1-IMPLEMENTATION-2026-10-14.md)。旧r5のソース／診断とr6 b12032/12038の実測は**異なるビルド**であり数値を無条件に接続しない。

### 直近の確定PPデータから導く問い

ROCm b12038・MH-A raw111137 tokens・Gather OFF・warmup ON、Vulkan b12032・同MH-A・QSA UNION ON・warmup OFF、各条件1run：

| backend / 量子化 | UBatch512 PP tok/s | UBatch1024 PP tok/s | 512→1024 |
|---|---:|---:|---:|
| ROCm IQ3 | 285.350 | 319.117 | **+11.83%** |
| ROCm IQ4 | 312.486 | 310.343 | **−0.69%** |
| Vulkan IQ3 | 257.919 | 278.523 | **+7.99%** |
| Vulkan IQ4 | 260.986 | 284.386 | **+8.97%** |

Vulkan QSA OFF/UB512ではIQ3 248.367・IQ4 249.836 tok/s。ROCm b12038では、ANLP raw111137/UB512のIQ4優位 +9.18%、native random126253/UB512 +8.50%、MH +9.51%なのに対し、UB1024ではMH −2.75%、native random126253 −1.68%、ANLP126253 −2.76%、code126253 −2.65%（符号はIQ4対IQ3）。**モデル差の順位逆転は入力ジャンル単独よりUBatchとの交互作用が有力**だが、入力内容、length、物理UBatch、backend、MTP/QSA、clock が交絡する箇所があり因果帰属は未実施。入力ジャンルによる絶対PP差も別に解析する。

## 2. 統一した座標と分析成果物

**最重要原則：『同じ秒数』ではなく『同じ仕事』を比較する。**

- 取得イベントのjoin keyを \`session_id, backend, binary_sha, model_sha_or_verified_identity, input_token_hash, qsa_mode, ubatch, phase(warmup/measured), sample_ordinal, token_begin/end, n_tokens, KV_start/end, layer_index, op_role, kernel_signature, dispatch_shape, RGP_capture_id\` とする。最低限、**レイヤー／KV位置／対象Qブロック／実際のカーネル／warmupか否か**が確定しなければ「厳密な同一ノード比較」とは書かない。
- tokenizerとllama-benchの**raw prompt file、BOSの扱い、head slicing、実token数、できればtoken ID列のSHA**を固定。以前CLIとbenchのraw vs Jinja入力でtoken数が異なる例があるため、混ぜない。同一モデルなら語彙が共通でもIQ3/IQ4のtoken ID列一致は照合する。native randomは実行内で疑似乱数生成されるため、**jobを跨いだbit-identical入力とみなさない**。厳密なrandom比較が必要なら固定token ID列の再生／ダンプ方式を別途実現した後に使う。
- CPU trace（実際に処理中のubatch/層/KVとkernel role）↔ RGPのdispatch を照合する。Vulkan既存 \`EVOX2_FA_MAIN\`／\`EVOX2_FA_MASK_OPT\` ラベル等はr5診断ブランチを**読んでから**最小限移植を検討。HIPはVulkanと同じdebug-label機構を想定せず、**marker／HIP profiler dispatch correlationの実現性を先に確認**。位置が確定しない場合は探索的captureとして分離して保存。
- **全PPスループット（通常ビルド・診断OFF）／個別GPU kernel時間（RGP）／全GPU演算の合計（perf logger）／CPU submit/idle／診断によるCPU-GPU同期の追加時間**を別指標として記録。キュー重なりやhost idleがあればkernel時間の単純和をwall時間とはしない。
- マイクロバッチの位置を合わせた**同一KV深度の2入力**をまず比較し、その後UBatchを変える場合は\`ubatch_index\`ではなく\`absolute_token_position\`／\`n_tokens\`で比較する。QSA UNIONのON/OFFを変更するなら**別の実験因子**にする。

## 3. 4系統で共有する採取設計

| 系統 | 共通の測定アンカー／ログ | 解析する値 | 単独では言えないこと |
|---|---|---|---|
| A. ROCm FA位置合わせ | HIP FA、KV末尾cutoff処理、RGP kernel名・格子・層・N・KV・対象phase | 同一anchorでの FA 本体ms、cutoff処理µs、cutoff後の実KV範囲、VGPR/LDS/occupancy/wave、必要ならメモリ帯域 | kernel名だけ合致しても同じGPU位置とは限らない |
| B. Vulkan mask形状 | 同じanchorの2-bitタイル分類と必要ならqueryを絞ったraw mask/selected IDs、FA本体RGP | 16×64タイル**行×列ヒートマップ**、ALL_NEG_INF/ALL_ZERO/Mixed、連続スキップ長、行/列分布、境界/局在、非スキップタイル vs GPU時間 | skipタイル総数だけでFA時間を完全に説明できない |
| C. MoE Expert routing | 同じモデル層・ubatch・token位置のrouter選択ID／選択重み／MUL_MAT_ID GPU event | layer毎のdistinct expert数、Expertごとのtoken割当・分布（entropy/Gini等）、連続ubatch間の重なり、実処理byte・MoE GPU時間 | **token毎のtop-k固定値**と、ubatchで実際に触る**unique expert数**は別物。選択Expert数の違いだけで因果は言えない |
| D. 量子化GEMM／UBatch | IQ3/元IQ4のmodel tensor type内訳＋FA/MoE以外のMUL_MAT系kernel、dispatch・shape | backend別 MMQ/MMVQ/quant GEMM/dequant・MUL_MAT_ID、tensor type、M/N/K、実dispatch kernel、GPU ms、VGPR/LDS/waves/occupancy、メモリ帯域／実トラフィック | 量子化でrouting自体が変わる可能性があるためカーネル差とExpert差を分離要 |

**Mask可視化の最小成果物:** 指定レイヤーの例えば **KV=49152, N=1024, Br16/Bc64** なら **64行×768列の2-bit分類マップ（49152タイル）**。日本語文学とC/C++を同じ軸範囲・同じ色分類で並べ、行/列のskip率と連続領域、選択割合/位置のヒストグラムを添える。Mixed内部はタイル分類だけから復元できないため、必要なら**限定したquery行**だけ元mask／selected positionをサンプルして重ねる。全GPU maskの常時ダンプは避ける。

**MoEの特記事項:** HF記事の実験は複数decode要求の同時バッチを並べ替えてExpert重量の読み直しを減らすもの。ここでは**単一長文のprefillを勝手に並べ替えない**（文脈・Attention・正答が変わるため）。router選択IDとExpertごとのtoken数を実際の物理UBatchで数え、モデルのmetadataからexpert総数とper-token top-kを明記する。IQ3/4のExpert ID差も記録する。必要なら将来、選択IDを固定した限定診断replayを別実験として考えるが、最初から実装しない。

## 4. 段階的な実施案：フル4因子直積を最初から回さない

### Gate 0：証拠整理・計測器の実現性確認（GPU長時間計測なし）

- r5 articleで使った調査ブランチのFA labels／mask分類・readbackと、r6 b12032/12038への最小移植差分をソースで調査。既存r6の診断スイッチ、RGP capture手段、VulkanとHIPでのdispatch correlation可否を調べる。
- 固定モデル・入力・コード／文学・SHA・PP length・UBatch・backend EXE SHA・configと、**FA→mask→MoE→GEMMの計測フィールド対応表**を先に作る。新しい診断は実験ブランチ＆明示的opt-inのみ、非診断時にhot pathや数値結果を変えないこと。RGPのSQTT切り詰めやdriver timeoutがない小規模captureから開始。
- 完了条件：各backendで**どの方法でレイヤー/KV/phaseを特定できるか**、足りない診断実装とコスト、停止条件が文書化される。

### Gate 1：64kの入力差を再現し、共通の基準点を固定

- **第一群：IQ3 ×「吾輩は猫である」／llama.cpp C/C++コード × Vulkan／ROCm × UBatch1024**（最低4条件）。MTP OFF、f16 KV、Batch2048、FA auto、-ngl999/-ncmoe0、Performance、RDP/物理表示状態を固定。Vulkan **QSA UNION OFF** を旧記事への橋渡し基準、ROCmはGather OFF。これらは**異なるattention経路**なので、「同一アルゴリズムのbackend差」とは称さない。
- 新規r6実入力benchで使える**共通長を実際のtokenizeで確かめる**。例えば **61440 tokens（1024×60で末尾端数なし）／ctx65536**を検討（最終長は実測・source availability確認後に固定）。旧r5記事の61789 tokensやr6別入力の61777 tokensと**同じ実験だと称しない**。KV49152のアンカーを含む長さを維持する。旧資料に近づけたい場合は別途、同じ入力を検証した上で61789を使う。
- UBatch512は、**まず同じIQ3×2入力を追加**して「入力差×UBatch」を検討し、必要性が確認できたら第2群へ拡張。randomはnative RNGの同一入力問題を解決した場合に追加。32k/48kはFA path/skip条件が変わるため主比較の代用にしない。
- 取得は通常PP・ADLX/Windows resourceを主体。重要な小さい差のみ交互順ABBA/複数runで再確認。4条件では因子の独立効果をまだ結論しない。

### Gate 2：旧記事の未完テーマを優先して精密化

- **FA/ROCm:** Gate1で差がある入力ペアについて、元記事の基準 **KV=49152/N=1024/同じ層（VulkanのQcur-19相当）** を探し、Vulkan/ROCm各々で一致したkernelと属性を最低2captureずつ。**同一backend内**の文学vsコード時間比→その後backend横断の差を比べる。ROCm HIP RGPでanchorが取得できなければ観測範囲を明記し、代替のdispatch correlationを設計してから先へ進む。
- **Vulkan mask:** 旧r5のタイル分類dumpをr6診断環境で再現するか、r5の証拠を完全に同定できるならその素材を再利用。mask heatmapを層/KV/Q位置一致で描く。行・列・局所連続性と「skipタイル比2.58 vs FA時間比4.1」の残差の関係を議論するが、形状だけで因果確定とはしない。
- **MoE:** 同じGate2の層とPP位置でrouter IDヒストグラム／distinct Expert／workloadを取り、FA+MoE GPU時間・入力差を分解する。旧記事のVulkan 64k全体ではコードのMUL_MAT_ID関連GPU時間が文学より**約4.45秒長かった**ため、FAと逆方向の寄与にも注目する。まずIQ3のみで可否を判断し、不要な全層巨大readbackはしない。
- 診断・readbackは必ず**別run**。時間比較には診断をONにしたrunのtok/sを採用しない。RGPを大量に同時併用しない。

### Gate 3：量子化 × UBatchを選択的に重ねる

- Gate1/2で比較可能な代表入力と位置を固定し、**同じbackendにおけるIQ3/元IQ4 × UBatch512/1024**のRGP・routing・GEMM dispatchを比較する。最初は64k・1つの代表入力だけを増やし、必要ならコード／文学の対比を追加する。
- 特に ROcm のIQ3 UB1024改善、IQ4ほぼ横ばいと、Vulkanでは両者が改善した事象を説明できる**quantized matmul/MMQ vs MMVQ/dequant/MoE FFN**のkernel選択・入力幅・tensor type・occupancy・weight bytesの違いを検証。各backendのカーネルは異なり、Vulkan QSA UNION ONとROCm Gather OFFの数字をそのまま「GEMM差」と解釈しない。
- 旧／今回のMH-128K 111137 PPデータは**現象の参照**として再利用し、現象が64kで再現しなければ「128k特有」の条件があり得ると扱う。**IQ4 Vulkan 128k/UB1024/UNION ONはADLX GPUメモリ97002MiBで完走したが、別ANLP128kではDeviceLostがある**ので、新たな長文RGP captureをデフォルトにしない。64kでもIQ4重みだけで負荷が高いため、必ず監視して個別可否判断。
- IQ3/4でrouter IDが変わる場合、「同じinputの異quantでは同じexpert計算をする」とは仮定せず、routing差の定量と同一shapeの対応kernelを別々に整理する。

### Gate 4：PP差の説明・反例・終了判定

- 同一入力のPP総時間差を **FA(QSA mask含む)／MoE／非MoE量子化MM(GEMM)／その他GPU(GDN等)／GPU idle・CPU submit・sync** のスコープで説明する表と、KV帯別（例 0–16k, 16–32k, 32–48k, 48–61k）の変化を作成。GPU kernelの合算は重複やsyncのため単純wallに一致しない可能性を明記する。
- 入力の主効果、UBatchの主効果、量子化の主効果、backendの違い、および**入力×UBatch／量子化×UBatch／backend×量子化×UBatch**の交互作用を、**実際にセルが揃った範囲だけ**で計算する。4因子を総当たりしたと装わず、空欄セル・1run・再現性不足を表示する。
- 期待成果物：①照合可能なevent/dispatch索引 ②同位置FA ROCm/Vulkan表 ③maskヒートマップとrow/column分布 ④Expert routing／distinct数／GPU時間表 ⑤quantized GEMM kernel表 ⑥PP時間の寄与・残差と未解明点。**数値・可視化・相関・因果仮説を別欄**に分ける。
- 停止条件：位置合わせが不能／RGP切り詰め／異常な大規模GPUメモリ確保／DeviceLost・ドライバーリセット／実験機再起動／モデル・入力の同一性未確認。該当時は結果を保存し、対象範囲を縮小して再設計する。無理に全因子の表を埋めない。

## 5. 計測・実装の安全設計／非目標

- 原則は **existing b12032 Vulkan、b12038 ROCmの元Unsloth IQ3/IQ4、既存実入力、96GB UMA設定、P-MODE Performance、MTP OFF、-ncmoe0、-ctk/ctv f16、原版リポジトリ／診断ブランチ別**。開始時にビルド・GGUF・入力 SHAとdriverを固定。QSA UNION、COMMON-005 Gather、warmupはbackendごと明記し、時間比較時の設定差を隠さない。
- **性能用run**は診断OFF・ADLX等最小限の監視。**GPU動作説明用run**は小範囲RGP／イベント相関。**mask/routerのreadback**はさらに別の診断run（低頻度・対象層限定）として、観測で性能とrouter分布が変わらないかを確認。GPU memoryの余裕はADLX数値から絶対的に推定しない。
- QSA UNION ONで観測されたVRAMクロック800MHz前後の低下は**別課題として[ROADMAP](ROADMAP.md)にDEFER済み**。本研究ではVRAM/コアクロック・電力・温度の共変量を記録するが、**クロック低下のドライバー/BIOS原因研究そのものはここへ合流しない**。ON/OFFでGPUクロックpolicyが変わるならカーネル時間比較の交絡要因として注記する。
- **非目標:** 現段階でのPP高速化パッチ実装、QSAカーネル改変、Expert sorting導入、モデル品質評価のやり直し、各量子の全コンテキスト巨大フルマトリクス、Strata実機試用、VRAMクロック独立ABBA、ROCmFPx HIP対応、upstream rebase。
- **着手順未決定:** PP本調査、QSA UNION↔VRAM clockの独立64k検証、Strata試用のどれを先に実施するかは情報収集後に改めて選ぶ。本書のGate番号は**PP調査に着手した場合の内部順序**であり、プロジェクト横断の優先順位ではない。

## 6. 将来着手時の最初の成果物（今は作らない）

1. **source/instrumentation compatibility memo**：r5診断ブランチとの機能差とr6 source適用可否、Vulkan／HIP RGPイベント位置合わせ方法。
2. **frozen minimal corpus manifest**：日本語文学・C/C++コードの文字列SHA、raw/token ID hash、head sliceと同一n_prompt、tensor/model identity、warmup／QSA／UB等。
3. **64k 2-input 2-backend IQ3 reference runbook**：4runから開始、最初の同一KV=49152 RGP probeは位置が合うまでデータの確定比較に使わない。
4. **mask/export and MoE routing schema**：読み出し対象の層／KV／ubatch／event key／timestamp／RGPリンク、データ量上限と診断なし対照。
5. **report layout**：未計測・未位置合わせ・非同一token・cross-buildのセルを明示した4軸比較表と寄与分析。

**作成日時:** 2026-11-04 JST。**判定:** OVERVIEW PREPARED、NOT STARTED。
