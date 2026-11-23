# 2026-11-08: r6後続タスク再順位付けとupstream/fork/他エンジン更新、IQ1・新IQ3／Strata着手準備

> **2026-11-23追補:** [文書集約・現行ステータス](DOCUMENTATION-RECONCILIATION-2026-11-23.md)を優先。11/18時点の主題①だったGemma4 PP/TG/RGP調査は11/21に一区切り。11/22に疑わしいFA移植／Global FAの診断worktreeを通常・無人運用対象から除外した（原因の確証はない）。11/23にCodex→EVO-X2の接続設定・テストが完了した。**広域の外部情報を収集・差分監査してから、ベースupstreamと最初の高速化候補を決める**。旧IQ3原GGUFではなく、IQ3 PLE16とROCmFP4を高速化の主モデルとする。


## 2026-11-23追補：外部動向の広域再調査（upstream・fork・Strata・エンジン・モデル）

> **情報収集のスナップショット：2026-11-23 JST。** この節は11/18追補と11/08原記録より新しい。CodexとEVO-X2の接続設定およびビルド・推論の接続テストは**完了**。次の段階は新たな高速化実装の着手候補を選ぶことだが、**この調査時点ではベースupstreamコミットも移植項目も未決定**。確認した公開情報と、外部作者の性能主張・未確認の仮説を区別する。今回の追記ではモデルダウンロード・実機計測・高速化コード実装はしていない。
>
> **履歴上の注意：** 11/18の「Gemma 4原因調査を先に進める」「Codex接続はこれから」、11/08の「IQ1/MH-HardやStrataは未着手」は**各日付時点の予定**。現在のタスク状態には適用しない。11/21までにGemma 4 PP/TG/RGP調査はいったん整理し、11/23にCodex接続テスト完了。現行の文書・ブランチ管理の基準は [2026-11-23文書集約](DOCUMENTATION-RECONCILIATION-2026-11-23.md) を参照。

### A. llama.cpp upstream：更新スナップショットと移植前のリスク

- [v1.0.0](https://github.com/ggml-org/llama.cpp/releases/tag/v1.0.0) は11/13公開。公開APIのversioning・整理を含むため、r6旧コードの移植では単なるkernelのcherry-pickだけで済まない場合がある。
- **11/23に確認したnightlyは [b12651 / f5e6915](https://github.com/ggml-org/llama.cpp/releases/tag/b12651)**（GitHubの公開時刻11/23 08:52 UTC、JST 17:52）。b12650からの直接のrelease差分は **WebGPU ROLL対応 (#31887)**。これだけを根拠にVulkan/ROCmの性能が上がったとは言えない。
- r6統合元 b11870、最近検証した b12363～b12370、11/18確認 b12490のすべてより進んだ版。**nightly番号を新ベースの採用理由にはしない**。v1.0.0以降のAPI、PLE16・QSA/Indexer・GDN・KV・MTP・MoE・Vulkan FA・ROCm経路の実差分を監査する。
- 追跡すべき技術領域：GDN/chunked prefill/state、Flash Attention（KV取得法、KV量子化、BF16、Sparse経路）、MoE fused GEMMとexpert cache、Speculative/MTPのdraft用KV、HIP scheduler/workspace、Vulkan cooperative matrix、WebGPU・マルチモーダル・サーバー/API機能。
- **既知の回帰報告は採用前ゲート**：[Windows AMD Vulkan FAのdriverクラッシュ #32353](https://github.com/ggml-org/llama.cpp/issues/32353)（b12398～b12421周辺のFA/flip-direct経路）、[HIPでMTP有効時にPPが低下する報告 #31495](https://github.com/ggml-org/llama.cpp/issues/31495)、[Windows Strix Haloのidle時VRAM退避・TTFT問題 #32124](https://github.com/ggml-org/llama.cpp/issues/32124)。issue報告は環境限定であり、EVO-X2での再現は未確認。
- b12651を採用すると決めたわけではない。新ベースは**ソース監査→Windows VulkanとROCmのsmoke→固定条件PP/TG→品質→回帰チェック**で選ぶ。非破壊・別worktree/branchで行う。

### B. Strata：実測した0.2.13/Engine 0.1.59から0.2.20/Engine 0.1.66へ

公式：[Strata releases](https://github.com/Niko1221/Strata/releases)、[v0.2.20](https://github.com/Niko1221/Strata/releases/tag/v0.2.20)、[Strix Halo解説](https://github.com/Niko1221/Strata/blob/main/docs/STRIX_HALO.md)。

- 0.2.14（11/15）：AMD/NVIDIA prefillのStrata独自kernel化が大きな変更点。0.2.16前後：エンジン構成・ディレクトリ整理。0.2.18：Hy4 Flash専用family。0.2.19：Inkling 2 Mini専用family。0.2.20（11/22公開）：3エンジンfamilyの0.1.66と、共通MoE planner・カーネル改良。
- **AMD HIP Wave32 WMMA prefill、fused dequant-to-LDS、LUT16/ v_perm_b32 / DP4A decode** を確認。作者が公表する70.7 TFLOPS、28.5～36.7 TFLOPS、451～583 GB/sは**カーネルレベルの値**であり、EVO-X2のQwen3.8 Flash Next全体PP/TGの実測値ではない。
- **GPU VRAM + RAM/CPU SIMD + SSD**を横断する4-tier MoE/expert配置、hot/cold expert、量子化KV・host offload、SSD Engram/expert streaming等が拡充。gfx1151はUMAなのでPCIe dGPUの階層モデルをそのまま移植しない。まずrouting、expert頻度推定、cacheとCPU/GPUの負担配分を読む。
- **Windows向け0.1.66 hip-rdna3バイナリ**がreleaseに含まれる。Inkling/Hy4用には別engine familyとWindows/HIPバイナリも存在。公開パッケージがあることと、所有するGGUF・Windows構成での動作成功は別。
- 数値・品質・起動の不具合修正も多い。0.2.20についても [issue一覧](https://github.com/Niko1221/Strata/issues) にMTP verifyやGGUFロード・Inklingの不安定報告があり、修正済みと断定せず検証時のログとengine buildを残す。
- 過去の比較（Strata 0.2.13／旧IQ3原GGUF／UMA64GB／MTP・DFlash2 OFF）を基準として残す。0.2.20再計測は**後日の独立課題**。同じGGUF revision、KV型、context、batch/ubatch、draft設定、起動方法でPP/TGと日本語要約/MH-Hardを対比する。
- 以前の11/18記録どおり、**DeepSeek V4.1-Flashは0.2.13とそれ以降のサポート状態が異なる**。0.2.20の同梱リストに旧DeepSeek 0.1.59 packageへの参照があっても、最新通常経路での実行サポートとは扱わない。

### C. 優先してコード差分を調べたいfork

| 対象・公式参照 | 最近の特徴・研究対象 | 監査時の注意 |
|---|---|---|
| [stew675/llama-cpp-rdna-boosts](https://github.com/stew675/llama-cpp-rdna-boosts/blob/main/README.md) | 11/20 upstream 919794500にrebase、**公式17ブロック + 暫定0300 = デフォルト18パッチ**、任意0100/0101。GDN、FA/KV、WMMA/MMQ、MoE融合/cache、MTPなど。 | **直列パッチで前ブロックに依存**する。独立機能の単純cherry-pickとは限らない。暫定0300とoptionalは区別し、対象shapeとnumericsを監査。 |
| [Strix-Halo/strix-llama.cpp](https://github.com/Strix-Halo/strix-llama.cpp) | adaptive speculation、Vulkan mat-vecのbatch3～8におけるregister spill、ROCmFPx、tiled concat-transpose、mul_mat_id、LDS stride padding。 | **LDS stride padは公式説明でRADV専用のdriver gate**。Windows AMD proprietary driverでは同じ改善が有効にならない。作者報告のpp +7.3%やkernel 10～20%をEVO-X2/Windows予測値にしない。 |
| [ArtomYuan/strix.cpp](https://github.com/ArtomYuan/strix.cpp) | 前回からの継続最重要調査対象：gfx1151向けHIP、shape別attention、ROCmFP4 K-tile、SSM convolution等。 | Linux向け実測や異なるQwen3.8-27BとFlash Nextを混同しない。 |
| [Nathanw1014/strix-halo-llamacpp](https://github.com/Nathanw1014/strix-halo-llamacpp) | Vulkan FA / MoE prefillやtiled concat-transposeの先行実装。 | 他forkへ再利用された変更を重複して数えない。 |
| [SelfRef/llama.cpp-rdna](https://github.com/SelfRef/llama.cpp-rdna) | RDNA Vulkan、ROCmFPx、量子化・FA。 | 実装経路・型・OS・upstreamへの取り込み状況を比較。 |
| [vahpetr/llama.cpp-s1-fork](https://github.com/vahpetr/llama.cpp-s1-fork) | Qwen3.8 Flash Nextの1M context、Sparse Attention/Indexer、prompt cache、MTP。 | 主な測定はLinux RADV、128GB UMA、特殊条件。数字はWindowsへ外挿しない。 |
| [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) | 独自量子化、Sparse FA/QSA、MoE expert cache、CPU/部分offload、新モデル。 | モデル形式とkernelを切り分けて移植可能性を判断。 |
| [justinappler/llama.cpp-strix-halo](https://github.com/justinappler/llama.cpp-strix-halo)、[halo-box/strix-llama.cpp](https://github.com/halo-box/strix-llama.cpp) | gfx1151向け歴史資料、検証・ビルド方法。 | justinappler版はretire済みの履歴があり、新規パッチの採用候補と区別。 |

**調査管理方法：** fork単位で「速い/遅い」ではなく、(1) source commit・初出作者、(2) upstream取り込み済みか、(3) 変更kernel/ggml graph/dispatch、(4) dtype/量子化・M/N/K/ubatch、(5) Windows proprietary Vulkan/HIPかLinux RADVか、(6) 定量結果の測定条件、(7) 数値/KLD/MH-Hard、(8) rollbackの容易さを1件1行で管理する。

### D. 他の推論エンジン・運用関連（高速化に直結しない情報も含む）

- [ExLlamaV3](https://github.com/turboderp-org/exllamav3) と [exllamav3-rdna](https://github.com/SelfRef/exllamav3-rdna)：EXL3/低ビット量子化、WMMAとdecode融合の参考。ただしgfx1100の測定が多く、gfx1151/Windowsでの動作・速度は未検証。
- [vLLM](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/index.html)：ROCm対応に**Ryzen AI MAX / gfx1151（ROCm 7.0.2以上）**が明記。Ubuntu側でモデルとAPIを試す有力候補。単発CLIのPP/TGと複数同時リクエストのserving throughputを別軸にする。
- [SGLang](https://github.com/sgl-project/sglang)：batch scheduler、attention、MoEの比較対象。gfx1151は有効kernel/設定が限定される場合がある。
- [Lemonade](https://github.com/lemonade-sdk/lemonade)、[Ollama](https://github.com/ollama/ollama)、[LM Studio](https://lmstudio.ai/)：モデル管理、OpenAI互換API、NPU/GPU/CPUの使い分け、エージェント連携の運用比較。Lemonadeは統合フロントであり、内側のbackendごとに性能を評価する。
- [DeepInfer](https://github.com/deepseek-ai/DeepInfer)、DeepSeek/Engram/DSpark/DFlash2等の技術は、EVO-X2への直接導入よりも設計・メモリ管理の調査対象。
- Codex/OpenCode利用では、TG token/sだけでなく**最初の応答までの時間、ツール呼び出し成功率、長文作業履歴、サーバー常駐中のidleメモリ挙動、処理タスク完了時間**も将来の評価指標にする。

### E. オープンウェイトモデル（性能と動作互換を分けて扱う）

| モデル・公開情報 | 注目点 | 記録上の扱い |
|---|---|---|
| [Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini)（11/20公開） | 公式model cardは**総26.4B、active 5.4B**、looped MoE、画像/テキスト。 | **先行の会話でactive約3.4Bと表記した値は訂正し5.4Bを採用**。Strata専用engineあり。GGUF/llama.cpp対応の実動作は別確認。 |
| [Hy4 flash](https://huggingface.co/tencent/Hy4-flash) | **総220B（Engram 64B含む）、active 12B、最大1M context、DFly2 drafter**。 | Strata専用engineあり。SSD容量、expert/Engram stream、長文KV、Windows UMAを検討してから取得。 |
| [Nemotron 3.5 Bolt 74B-A9B 24GB GGUF](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF) | 小さい圧縮量子化モデル・MoE pruningの参考。 | 速度比較だけでなく品質と推論時メモリを含める。 |
| Qwen3.8 Flash Next（既存旧IQ3 PLE16/ROCmFP4） | QSA、GDN、MoE、MTP、長文PP/TGと既存RGP実績が最大。 | **高速化検証の主対照モデルとして維持**。 |
| [AMD Quark Qwen3.6-35B-A3B INT4 GGUF](https://huggingface.co/amd/Qwen3.6-35B-A3B-Quark-INT4-G32-GGUF) | AMD側の量子化/変換経路とINT4 GGUFを調べられる。 | IQ3/IQ4単純比較とは別の量子化パイプライン検証。 |
| [DeepSeek V4.1 Flash](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017) | 大規模MoE、圧縮/sparse attention、Indexer、メモリ階層。 | 専用SSD/RAM要件の見積もりが先。単体EVO-X2での実用性能を期待しない。 |
| Gemma 4 31B / 26B A4B、Qwen3.8-27B dense、軽量MoE | GEMM、FA、MoEの比較対照。 | 11/21までのGemma 4計測資料と整合させ、必要時だけ再測定。 |

新モデルの高性能ベンチマーク結果はモデル提供側・各エンジンの条件付き主張。**EVO-X2上で走ること、品質が十分なこと、速いことは独立したゲート**。モデル作者の公開値と本リポジトリの実測を同じ欄に混ぜない。

### F. 候補技術一覧：ここでは順位・採否を決めない

| 技術系統 | ソース調査項目 | 既存データの利用先 |
|---|---|---|
| Dense / MoE GEMM | Wave32 WMMA、LDS bank conflict、fused dequant、Gate/Up/Down融合、mul_mat_id | IQ3/IQ4のubatch逆転、Gemma4 Vulkan/ROCm、RGP MMQ |
| Flash Attention | KV直接参照、quantized/BF16 KV、flip/coopmat、Sparse FA | 文学/コード64k～256k、RGP FA位置合わせ |
| QSA / Indexer | mask/top-k/pool、sparse tile、scoreとKey対応 | 既存Mask SVGとIndexer解析 |
| GDN / state | chunked prefill、SSM state、WMMA、graph reuse | Qwen3.8 Flash Next |
| MTP / Speculative | adaptive draft、DFlash2、DSpark、KV共有、batch3～8 register spill | MH-Hard品質、TG、MTP有無のPP回帰 |
| Quantization | ROCmFPx、LUT/DP4A、Quark INT4、CPU codecs | 既存IQ3/4/FP4の品質/速度 |
| Expert/UMA | expert cache、hot/cold tier、CPU SIMD、RAM/SSD paging | UMA 32/64/96GB、ページング・TG |
| Runtime / Serving | host-submit待ち、dispatch、graph構築、KV scheduling、MTP idle、API | ADLX、RGP、llama-cli/bench、Codex連携 |

### G. ベースupstreamと最初の高速化実装を選ぶ前の判定条件

1. **新規・改良・既にupstream入り・旧版のみ・Windows不可・未確認**をまず分類する。特にStrata/rdna-boosts/strix-llama.cpp/ArtomYuan間の同一実装を二重計上しない。
2. 候補の関係する**具体的なcommit / PR / ファイル / kernelと量子化dtype、M/N/K、ubatch**を特定し、r6から新upstreamへの既存COMMON-001/005・QSA・MTP等の影響を見積もる。
3. Windows 11 gfx1151（AMD proprietary Vulkan、HIP/ROCm）での**active path**を確かめる。Linux RADV固有最適化はまずコード調査までとし、改善幅を直接流用しない。
4. ベース候補は独立worktree/branchでbuild・load・短文smoke・64k/128k PP/TG・数値再現性・MH-Hardの限定品質チェックを行う。driver、モデルGGUF、KV dtype、MTP、batch/ubatch、UMA値を記録。
5. 個別最適化は**1機能1branch、default OFF/opt-in、A/B同条件、rollback可能**。性能差が誤差程度なら深追いを限定し、ボトルネック変化がRGP/計数値で説明できるか重視。
6. Codexからのビルド、実機ベンチマーク、品質試験、結果ドキュメントの保存はGitHub上で追跡できるようにする。**この節は調査だけで、実装順・ベースコミット・最適化採用を決めていない**。

### H. 一次資料・調査リンク一覧（スナップショット）

- upstream: [b12651](https://github.com/ggml-org/llama.cpp/releases/tag/b12651)、[v1.0.0](https://github.com/ggml-org/llama.cpp/releases/tag/v1.0.0)、[Windows Vulkan FA #32353](https://github.com/ggml-org/llama.cpp/issues/32353)、[MTP PP #31495](https://github.com/ggml-org/llama.cpp/issues/31495)、[WDDM memory #32124](https://github.com/ggml-org/llama.cpp/issues/32124)。
- Strata: [v0.2.14](https://github.com/Niko1221/Strata/releases/tag/v0.2.14)、[v0.2.18](https://github.com/Niko1221/Strata/releases/tag/v0.2.18)、[v0.2.19](https://github.com/Niko1221/Strata/releases/tag/v0.2.19)、[v0.2.20](https://github.com/Niko1221/Strata/releases/tag/v0.2.20)、[STRIX_HALO.md](https://github.com/Niko1221/Strata/blob/main/docs/STRIX_HALO.md)。
- fork: [stew675 README](https://github.com/stew675/llama-cpp-rdna-boosts/blob/main/README.md)、[Strix-Halo/strix-llama.cpp README](https://github.com/Strix-Halo/strix-llama.cpp)、[ArtomYuan/strix.cpp](https://github.com/ArtomYuan/strix.cpp)、[ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp)、[s1-fork](https://github.com/vahpetr/llama.cpp-s1-fork)。
- モデル: [Inkling 2 Mini model card](https://huggingface.co/thinkingmachines/Inkling-2-Mini)、[Hy4 flash model card](https://huggingface.co/tencent/Hy4-flash)、[Nemotron 3.5 Bolt GGUF](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-24GB-GGUF)、[AMD Quark GGUF](https://huggingface.co/amd/Qwen3.6-35B-A3B-Quark-INT4-G32-GGUF)。
- 他エンジン: [vLLM ROCm GPU requirements](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/index.html)、[SGLang](https://github.com/sgl-project/sglang)、[ExLlamaV3](https://github.com/turboderp-org/exllamav3)、[Lemonade](https://github.com/lemonade-sdk/lemonade)。

**次の作業は、ベースupstreamと候補を選ぶ前の具体的な差分・重複監査。** この11/23記録はあくまで広域の情報収集であり、正式な実装計画・実験結果・採用決定ではない。

---

## 2026-11-18追補：llama.cpp / fork / 他エンジン / オープンウエイトモデル最新動向と優先順位

> **最新判断（2026-11-18 JST、公開ソース調査）。** ここから次の区切り線までが11/18追補。以降の11/08原記録は当時の判断として維持し、過去の「次にやる」指示は現状の予定として読み替えない。今回の更新ではEVO-X2実機ビルド・速度計測・ソース移植を行っていない。外部作者の性能値は作者報告であり、r6実測とは区別する。

### A. 11/08以降の実験進捗と今回の方針

- 11/08の優先度1だったIQ1・更新IQ3とMH-Hard品質比較、優先度2だったStrata試用は既に進行・評価済み。旧IQ3を常用継続、新IQ3の採用を見送り、Strataとr6・upstreamのPP/TGを比較した。これらを再び「未着手」と記載しない。
- 現在の主テーマは **(1) Gemma 4のPP速度がVulkanとROCmで異なる理由の調査**（高速化より内部挙動の理解が目的）、**(2) CodexからEVO-X2へ接続できる環境の確立後、Strataの最適化を個別にllama.cppへ移植** の2件。
- **判断：この2本柱は維持。** ただし移植前に、最新upstream・strix.cpp・rdna-boosts・Strataの重複実装／kernel経路を監査する工程を追加する。DeepSeek、vLLM等は別トラックで、メイン開発を遮らない範囲に限定する。

### B. upstream llama.cpp（11/18時点）

- [2026-11-18公開nightly b12490](https://github.com/ggml-org/llama.cpp/releases/tag/b12490) を確認。r6統合ベースb11870、11/08確認b12202より進んでいる。ビルド番号の進行はr6上の性能改善を保証しない。
- [v1.0.0（11/13公開）](https://github.com/ggml-org/llama.cpp/releases/tag/v1.0.0) はb12359相当（commit b1b770d）。公開API整理だけでなく、**外部PLE/engramシャード読み込み（#31185）**、**CPU共有可能なMoE expert cache（#30966等）**、**FP8 KV cache**、GDNの経路整理、Vulkan prefill FA、scheduler/graph再利用等を含む。
- r6の **COMMON-001 PLE16、COMMON-005 Gather、QSA Mask・KV処理、MTP、MoE/cache、Vulkan PP** と重複・干渉する可能性がある。外部PLEの実装が入ったからといってr6の既存PLE16と機能同等とは断定しない。コード経路、量子化型、head split、モデル読み込み条件を照合する。
- [AMDのggml-hrx RFC](https://github.com/ggml-org/llama.cpp/discussions/27219) はAMD専用backendの将来候補。Windows gfx1151での優位は未確立のため、現時点は追跡のみ。

### C. 優先度が上がったfork

| 対象 | 確認点 | EVO-X2での扱い |
|---|---|---|
| [ArtomYuan/strix.cpp](https://github.com/ArtomYuan/strix.cpp) | gfx1151特化のLinux ROCm 10.x / HIP fork。Attention shape別kernel、ROCmFP4 GEMMのK-tiling、SSM convolutionのコピー削減。作者報告でQwen3.8-27B / Q4_0_ROCMFP4_FASTのPPを約44～73%改善した比較あり（条件により別幅の報告もある）。 | **ソース差分・RGP計測手法の優先監査対象**。Qwen3.8 Flash Next、Windows ROCm、r6で同じ改善が出るとは仮定しない。 |
| [stew675/llama-cpp-rdna-boosts](https://github.com/stew675/llama-cpp-rdna-boosts) | RDNA/HIP向け複数パッチブロックと再現性重視の計測記録。v17系列が公開。 | r6に未導入で、対象shape/active pathが一致するパッチのみ検討。一括適用しない。 |
| [justinappler/llama.cpp-strix-halo](https://github.com/justinappler/llama.cpp-strix-halo) | 2026-10-19にforkをretireし、主要最適化はupstreamに反映された旨を記録。 | 重複実装を避けるための履歴資料として利用。 |

上記の速度値は作者の環境・量子化・モデル・バッチ条件に依存。**kernel単体の改善率とPP全体の改善率、同一forkの旧版対新版とfork対upstreamを混同しない**。

### D. Strata 0.2.14 / 0.2.15の更新と移植対象

- [Strata v0.2.14（11/15）](https://github.com/Niko1221/Strata/releases/tag/v0.2.14) はNVIDIA/AMDのprompt処理を独自kernel中心へ変更し、engine 0.1.60になった。[v0.2.15（11/16）](https://github.com/Niko1221/Strata/releases/tag/v0.2.15) は主にapp/terminal修正で、通常engineは同じ0.1.60。以前実測したv0.2.13 / engine 0.1.59との差分を読む際はバイナリを混ぜない。
- [Strix Halo公式説明](https://github.com/Niko1221/Strata/blob/main/docs/STRIX_HALO.md) にある STRATA_PF_GEMM、STRATA_PF_FUSED、STRATA_HIP_WMMA、STRATA_HC_UPMIX、GDN、hipBLASLt tuning、expert-cacheの選択・RAM budget等を、既存r6/upstream/strix.cppの**コードと同一shapeでのdispatch経路**に対応づける。
- 移植順は「実装対応表を作る → 依存最小の候補を一つ選ぶ → opt-in / default OFFで独立branch → 同一モデル・GGUF版・KV dtype・UBatch・MTP設定でA/B → 数値とMH-Hard品質 → 採否」のゲート方式とする。新たな最適化が既にupstreamにある場合は、先にupstream経路での再現性を確認する。

### E. DeepSeek V4.1-Flash：技術的興味は高いが本体計画と分離

- **重要：現行Strataの通常経路ではDeepSeekは起動不可。** [Strataのretired.py](https://github.com/Niko1221/Strata/blob/main/strata_control/retired.py) には、**0.2.13まで動作、以降はDeepSeek設定/モデルを実行前に明示的に拒否**する実装がある。一方[v0.2.15のrelease note](https://github.com/Niko1221/Strata/releases/tag/v0.2.15) にはDeepSeek用**過去版engine 0.1.59の配布ファイルが0.2.13から供給される**と記載がある。**配布継続と実行サポート継続を混同しない**。最新Strataで動くという前提にしない。
- 大きなモデル本体に加えて、別のEngram/n-gramテーブル（公式案内では約111 GB）等の容量・SSD帯域が必要。[Strataのモデル説明](https://github.com/Niko1221/Strata/blob/main/docs/AI_REFERENCE.md)にある2bpw前後でモデル本体が数百GB規模。UMA 64/96 GB全載せを前提にしない。
- 試す場合は **(a) llama.cppの対応GGUFと動作ビルド確認、(b) Strata v0.2.13を別環境に固定する歴史再現、(c) SSD空き容量、mmap/キャッシュ、expert配置、OSメモリ不足時の挙動の事前見積もり** を最初のゲートとする。ダウンロード・起動はゲート通過後に判断。初期目的は実用速度より巨大MoEの実行経路・キャッシュ挙動の理解。

### F. 他エンジンとモデルの候補

| 項目 | 11/18時点の公開情報 | 判断 |
|---|---|---|
| [vLLM](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/) | ROCmの対応GPUにgfx1151/Ryzen AI MAXが明示。Linux中心で検証。 | 他エンジンを1つ試すなら第一候補。サービング重視の構造のため、単発GGUF長文PPにそのまま優位とは推定しない。 |
| [SGLang gfx1151](https://github.com/sgl-project/sglang/blob/main/docs/docs/hardware-platforms/amd_gpu.mdx) | Strix Halo向けDocker経路。AITERを無効化する構成が示される。 | vLLMの後。wave32 kernelの数値正確性にも注意。 |
| [Lemonade](https://github.com/lemonade-sdk/lemonade/releases) / [Halogen](https://github.com/peonist-ai/halogen-flash-server) | Strix Halo向けの複数container backend（Halogen、Gufo、ROCmFPX等）が拡充。 | Lemonade自身を1エンジンとして比べず、backend単位で評価。 |
| [Qwen3.8-27B](https://github.com/QwenLM/Qwen3.8) | dense GEMMの性能検証に利用可能。strix.cppの測定モデルに近い。 | 常用Flash Nextとは別の**高速化検証用dense対照モデル**として検討。 |
| [Qwen4](https://www.alibabacloud.com/en/press-room/alibaba-unveils-qwen4-max) | 11/16にQwen4-Max発表。小型オープンウエイト版は今後公開予定。 | ウエイト公開とllama.cppサポートを監視。今すぐ置き換え不要。 |
| Kimi K3.1 Pro | 2.8T総パラメータ/約104B activeの大型MoE。v1.0.0でアーキテクチャ対応が追加。 | 単体EVO-X2での優先試用対象にはしない。 |

### G. 2026-11-18の実行優先順位（11/08の順位を更新）

| 順位 | 作業 | 完了条件・扱い |
|---:|---|---|
| **1** | **Gemma 4のVulkan/ROCm PP差をRGPで整理** | 既存profileからGEMM形状・kernel時間・dispatch/待機時間を突き合わせ、主要因を分類。高速化実装は必須としない。 |
| **2（並行・基盤整備）** | **CodexからEVO-X2へ安全に接続** | 非管理者SSH、指定commitのbuild、同条件benchmark、品質確認、差分記録、rollback、GitHubへの結果保存を自動化。既存サービスへの影響は避ける。 |
| **3** | **4者の差分監査**（upstream / Strata / strix.cpp / rdna-boosts） | 対応表にshape・dtype・kernel・driver/ROCm前提・r6 active path・upstream取り込み済みか否かを整理。 |
| **4** | **個別最適化の移植・採否判定** | 1機能1branch、default OFF、性能と数値/品質を必ずA/B。 |
| **5（独立の短い事前調査）** | **DeepSeek V4.1-Flash可動性確認** | 対応版・巨大モデル容量・SSD/UMA/キャッシュ計画を確認。モデル取得前に実施可否を判断。 |
| **6** | **他エンジン試用** | Linux上でvLLM → 必要に応じHalogen/Gufo/SGLang。比較対象は同一モデルまたは比較可能なモデルで限定。 |
| **7（継続監視）** | **新モデル・HRX・新upstream機能** | Qwen4小型ウエイト、Vulkan/ROCm新kernel等の公開時に順位を再判定。 |

**総合判断：** Gemma 4原因調査は研究目的に沿って続行し、早めに観測事実と未解明点を整理して区切る。Codex/EVO-X2の反復ビルド・計測基盤が整った後の主開発はStrataの最適化を個別に比較・移植すること。ただし**実装の前にupstream/strix.cpp/rdna-boostsとの差分監査**を挟む。DeepSeek試用や新エンジン探索は補助テーマにして、主計画を中断しない。

**変更・検証の境界：** この追補は情報収集と優先順位記録のみ。計測値、最適化の採用、上流統合、GitHubソース変更、Windowsサービス・UMA設定変更を伴わない。後続の実機ログ・条件・成果物は実験リポジトリへ記録し、採用したコードのみ本リポジトリへ反映する。

---


> **現在の基準文書（2026-11-08 JST）。** 本記録は公開GitHubリリース・PR・各公式ドキュメントの静的調査と既存EVO-X2実測の整理。**ローカルビルド・モデル動作確認・変換・外部エンジン起動・速度計測は未実施。** 以前の2026-11-03引き継ぎや2026-11-07「PP調査中」計画より新しい優先順位をこちらに記録し、古い日付付き測定値・意思決定は履歴として残す。古い実測を後から改変しない。

## 1. 現状と完了済みの調査

- 実験基盤：r6 `main` / Qwen3.8 Flash Next / Unsloth IQ3_XXS PLE16 / EVO-X2 Radeon 8060S gfx1151 / Windows 11、Vulkan・ROCm。r6統合元b11870、2026-10-29公開Vulkan preview b11908およびtagは保存する。
- **r5 TOOL-001の実入力`llama-bench`のr6移植と実入力64k計測は完了**。古い「次に移植」記述は既に終了した履歴。11月4–8日の[実験記録](https://github.com/ariera-j/evox2-llm-experiments/tree/main/benchmarks/pp-input-dependence-64k-20261104)と[PP総括](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/runs/2026-11-08-pp-input-dependence-overall-summary-ja.md)参照。
- **QSA 2-bit/F16 Mask・Indexer score/top-k・コード/文学の縦線・MoE Expert routing・Vulkan/ROCm FA RGP厳密位置合わせ・ROCmのGPU KV_max・局所RGP時間収支は一段落**。Vulkan通常64k PPはコード159.923秒／文学173.168秒、ROCmは153.690秒／151.427秒。局所差を全PP原因別秒数と混同しない。
- **COMMON-005（ROCm Gather）初期検証は完了**。128k限定品質スクリーニングをPASS、source opt-in/default OFF。長期運用、MTP ON、Vulkan active path、ROCm数値再現性、TG時GPU idleなどは独立保留。

## 2. 外部調査（2026-11-08に確認できたスナップショット）

### 2.1 upstream llama.cpp

- [公開release b12202](https://github.com/ggml-org/llama.cpp/releases/tag/b12202)（2026-11-08 17:11 JST公開）。r6統合ベースb11870、前回11/03スナップショットb12061を上回る。**新しいreleaseの数字やPRの存在はEVO-X2性能向上の実測ではない**。
- QSA/KV構造：[#31243](https://github.com/ggml-org/llama.cpp/pull/31243)（10/27 merged、k-poolをkq_mask形状から独立化）および[#29510](https://github.com/ggml-org/llama.cpp/pull/29510)（11/02 merged、unified KV/multi-seq/flash_attn_ext_rows）。次のupstream refreshではCOMMON-001 PLE16・COMMON-005 Gather・QSA Mask生成・single/multi-seq、rollbackと相互作用を先に監査。いきなりmainにmergeしない。
- HIP MoE：[#31188](https://github.com/ggml-org/llama.cpp/pull/31188) gate/up+GLU fusion（10/28 merged）。[Unsloth mix #264](https://github.com/unslothai/llama.cpp/pull/264)のprompt MMQと重複・相補を区別。
- Vulkan：[#30146](https://github.com/ggml-org/llama.cpp/pull/30146) small-N split-K（11/02 merged）、[#31266](https://github.com/ggml-org/llama.cpp/pull/31266) skipped-row scan削減（11/02 merged）。[#31587](https://github.com/ggml-org/llama.cpp/pull/31587) AMD proprietary driver向けlarge coopmat再有効化（11/05 merged）：ドライバ依存を考慮。
- MTP：[#31497](https://github.com/ggml-org/llama.cpp/pull/31497) DraftへのMoE cache不適用（11/08 merged）。
- **監視中・未merge**（11/08時点）：[#31196](https://github.com/ggml-org/llama.cpp/pull/31196) Vulkan MMVQ 9–16列、[#31197](https://github.com/ggml-org/llama.cpp/pull/31197) CM1 FA、[#31185](https://github.com/ggml-org/llama.cpp/pull/31185) external PLE loader。候補patch化する前にmerge状況・現行r6 active kernelを再確認。

### 2.2 llama.cpp派生fork

- [Unsloth mix b12189-mix-725acdc](https://github.com/unslothai/llama.cpp/releases/tag/b12189-mix-725acdc)（2026-11-08公開）：Qwen4Exp shared-weight MTP #240、ROCm iGPU修正 #158、HIP/CUDA MoE prompt #264、Vulkan large-head FA #270、Vulkan top_k align #328等を含む。**一括mergeではなく個別差分ドナー**。
- [s1-fork v75](https://github.com/vahpetr/llama.cpp-s1-fork/blob/main/docs/s1/RELEASE-NOTES.md)（11/05）：直近のv74/v75は主にUI/運用側、v73のエンジン・数値と共通。Linux RADV・別モデル・別量子化の数字をWindows Vulkanの見込み速度として使わない。
- [SelfRef llama.cpp-rdna](https://github.com/SelfRef/llama.cpp-rdna)：11/03の直近docs更新、Vulkan・ROCmFPxの差分監査ドナー。紹介される[exllamav3-rdna](https://github.com/SelfRef/exllamav3-rdna)は主にRX7900XTX/Qwen3.8-27B/EXL3での実測であり、現在のFlash Next用Windowsへの直接移行先ではない。
- [ROCmFPX](https://github.com/charlie12345/ROCmFPX)：確認できたmainの最新ソース更新は09/23。HIP型101/104限定移植構想は保留、現行r6へのcherry-pick前提にしない。

### 2.3 他エンジン

| エンジン | 11/08時点公開版・重要点 | EVO-X2優先度・注意 |
|---|---|---|
| [Strata 0.2.12](https://github.com/Niko1221/Strata/releases/tag/v0.2.12)（11/07公開） | Windows gfx1151 HIP package `strata-engine-0.1.58-windows-x86_64-hip-rdna3.tar.gz`、hipBLASLt tuning同梱。作者比較でStrix Halo UD-IQ4_XS-v31 4k PP **690→1220**、32k **1107→1377** tok/s（**0.2.11→0.2.12**）。text categoryによってTG悪化もあり。 | **実機比較1位**。公開値はStrata同士の別GGUF同士の比較でr6との比較値ではない。 |
| [Strata 0.2.11](https://github.com/Niko1221/Strata/releases/tag/v0.2.11)（11/05公開） | Unsloth 11/04再アップロード「Dynamic v3.1」revision `d9620119`のUD-IQ3_XXS（83.6GB、4 shard）とUD-IQ4_XS-v31（93.7GB、4 shard）などを新たにサポート。従来UD-IQ4_XSとは別物。 | 旧/新IQ3比較で**revision差・tensor差・GGUF分割形式**を記録。 |
| [Gufo 0.31.0](https://github.com/gufo-org/gufo/releases/tag/v0.31.0)（11/05公開） | 0.29.0でIQ3_XXS/IQ1_S等のGGML block形式認識・dequant、Qwen3.8 ngram等を追加、0.30.0でprefill/checkpoint改良。 | **比較2位**。型認識だけでは自分のGGUF/PLE16のGPU実行保証なし。公式はLinux本番中心・Windowsは開発ビルド対象。[gufo-win](https://github.com/jaacMusic/gufo-win)別プロジェクトも監視。 |
| [Project Maya 1.1.56](https://github.com/mw00/project-maya/releases/tag/v1.1.56)（11/06公開） | 1.1.54でQwen3.8 Unsloth UD-IQ2_XS GGUF採用、1.1.55 Codex CLI対応、1.1.56ファイル添付。 | 比較3位。直近の大きなPP向上報告は主にDeepSeekなど別モデル。 |
| [Halogen](https://github.com/peonist-ai/halogen-flash-server) | AMDの主な実装・運用説明はLinux系。 | Linux実験環境導入後に再検討。 |

**比較の統制：** GPUが同じでも、GGUF revision・量子化、PLE16、KV dtype（Strata既定int8 vs r6 F16）、DFlash2/MTP（Strata AutoがDFlash2を選ぶ）、cache、batch/UBatch、prefill範囲、driver/ROCm、samplerが違えば直接の性能比や品質差ではない。外部作者の速度数値は自分の実機結果として転載しない。

## 3. 2026-11-08現在の優先順位（実装着手前の暫定）

| 順位 | 項目 | 現在の判断／完了条件 |
|---:|---|---|
| **1** | **旧IQ1_S・更新IQ3の可動確認→PLE16変換→品質比較** | 小さいsmoke・元GGUF／変換GGUFの整合を先行。旧IQ3・旧IQ4・更新IQ3を主比較したMH-Hard、旧IQ1は参考。既存MH-128Kは改変しない。 |
| **2（並行準備）** | **Strata公式Windows v0.2.12試用** | 初回は公式prebuilt。別データディレクトリ/ポート、既存llamaサービスを止めるかリソース分離、4k/32k smoke→比較可能なモデルだけ64k。 |
| **3（読解のみ並行可）** | upstream b12202統合影響監査 | COMMON-001/005/QSA/KV/rollback、MoE、MTP、driver pathの重複チェック。アップストリーム統合自体は別判断。 |
| **4** | Gufo 0.31.0短いロード/動作確認 | Strata結果後に、モデル型/Windows build条件の同等性をゲート。 |
| **5** | IQ3/IQ4×UBatch/量子化別PP/TG | 旧実測の交差（ROCm UBatch512/1024）と量子化品質を踏まえて小規模ABBA。 |
| **6** | s1/Unsloth/SelfRefの最適化候補選定 | 現行r6では未導入かつ実際に動くGPU kernel/shapeだけ、PR状態更新後に選別。 |
| **7** | ROCmFPx HIP（型101/104）最小移植 | 独立branch、ロード→GET_ROWS→MUL_MAT/MUL_MAT_ID→数値→4k→64kの限定Gate。Vulkan実装からHIP速度を推定しない。 |
| **8/条件付** | Gemma4 31B PP/FA、Nanbeige4.3、MTP KV数値parity、ROCm非決定性、ROCm TGホスト投入待ち | 使用頻度・新しい障害・次の計測目的に従い独立taskとして着手。自動化専用PC／SSHは並行準備してよいが品質比較の依存にはしない。 |

**今回の選択：** まず第1位を着手し、第2位のStrataセットアップを並行。コードの新最適化・upstream一括mergeより先にユーザー使用上の品質と他エンジンを比較する。

## 4. 旧IQ1_S・更新IQ3の最初のゲート（手順案。まだ実行していない）

### G0 元GGUFの在庫・識別

1. 旧IQ1_S、更新IQ3_XXS、旧IQ3_XXS、旧IQ4_XSの**実ファイルパス／全shard数／各サイズ／リビジョンとSHA-256**を記録。更新IQ3の提供revisionが11/04 `d9620119`と同一か検証（ダウンロード済みというだけで一致とは断定しない）。
2. `gguf` architecture、PLE head offsets/vocab sizes、`per_layer_token_embd.weight`（joined）か`ple_ngram_embd.N.weight`（split）か、量子化tensorタイプを記録。IQ1の`IQ1_S`対応・テンソル型・実際のrequired memoryは初回smokeで確定する。単純に旧IQ3のサイズ/レイアウトを当てはめない。
3. 旧版GGUFを残し、旧版と更新版を別ModelKeyで管理する。型の差、revision差、PLE配置差は別軸。

### G1 元GGUFの非破壊smoke（各モデル先行）

- **既存の検証済みr6 VulkanかROCmビルド**で、最初はctx4096・短い日本語入力・生成32token程度。実際のモデルパスとbinary SHAを記録。速さの比較はまだしない。
- 終了0、loaderにunsupported typeなし、49/49など想定のGPU offload/CPU fallback、応答が崩れないこと、P-MODE・メモリ／ページングを確認。モデルの新しい量子化形式がr6でunsupportedなら**変換で直るとは限らず、GGUF/モデル実装互換の課題として止める**。
- 両モデルの元GGUFがロードできた後に、片方ずつPLE変換へ進む。

### G2 PLE16 preflight / 必要なら変換

既存ツール：[Convert-Unsloth-Ple16.ps1](../../tools/evox2/model/Convert-Unsloth-Ple16.ps1) / [説明](../../tools/evox2/model/README.md)。PowerShellから**モデルの先頭shard**を指定。例（パスは仮、実機で置換）：

```powershell
$repo = 'C:\llama-build\llama.cpp-evox2-windows-r6'
$converter = Join-Path $repo 'tools\evox2\model\Convert-Unsloth-Ple16.ps1'
$inputModel = 'D:\models\new-IQ3\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00004.gguf'
$outputModel = 'D:\models\converted\new-IQ3-ple16.gguf'
& $converter -InputFile $inputModel -OutputFile $outputModel -DryRun
& $converter -InputFile $inputModel -OutputFile $outputModel -PreflightOnly
# Preflight OK後だけ実行：
# & $converter -InputFile $inputModel -OutputFile $outputModel -VerifyBytes
```

- ツールは`00001-of-NNNNN`から**3/4 shardを固定せず**入力群を認識するが、元GGUF側に**joined PLEと正しい16-head metadata**を要求する。**更新版が既にsplit PLEなら、無理に再変換しない**（`--expect-operation split`に失敗する）。型・メタデータ不一致の際は原本を変更せず診断する。
- 全入力shardとほぼ同量の**追加空きディスク**が必要。出力は`.partial.gguf`経由、原本は上書きしない。`-VerifyBytes`は大容量ストリーム検証で負荷大、余裕のあるタイミングで実施。
- 変換完了後は**別ModelKey**でr6 Vulkan/ROCm ctx4096のロード・32 token生成、必要なら32k→128k品質タスクへ拡張。変換済みと未変換で性能やエラーを同一母集団と混同しない。

### G3 品質比較

- [r6出力品質追加計画](R6-OUTPUT-QUALITY-EXTENSION-PLAN-2026-11-07.md)に従う。日本語論文要約は軽い確認。
- 高難度検索`MH-Hard`は既存MH-128Kに手を加えず独立seedで新規作成。旧IQ3／旧IQ4／更新IQ3の主比較、IQ1は選択的参考。ROCm同条件再試行、MTP・Gather OFF/ONを固定、sampler/data seedを区別。
- 初期smokeを品質合格とは扱わない。すべてのモデル・seedの巨大matrixを初日から走らせずpilot gateで停止条件を決める。

## 5. Strata公式バイナリ試用の準備（並行トラック）

**推奨：** 初回は[公式v0.2.12 release](https://github.com/Niko1221/Strata/releases/tag/v0.2.12)のWindows Terminal / App。エンジンは`windows-x86_64-hip-rdna3`、gfx1151 GPUコード・ROCm runtime DLL・hipBLASLtチューニングテーブルが同梱。[Windows Strix Haloガイド](https://github.com/Niko1221/Strata/blob/main/docs/STRIX_HALO_WINDOWS.md) / [インストールガイド](https://github.com/Niko1221/Strata/blob/main/docs/INSTALL.md)。

- 初回はソースビルド**不要**。自前で`tools\hip\build_windows.bat`を実行する道は存在するが、Visual Studio 2022 C++／TheRock wheels約10GB／hipBLASLt tuning適用／環境差検証の手間が増え、目的が性能比較なら基準を汚しやすい。**profilingやソース変更を行う段階で、自前ビルドを別インストール／別バイナリとして検討する**。[SOURCE_INSTALL](https://github.com/Niko1221/Strata/blob/main/docs/SOURCE_INSTALL.md) / [AMD HIP](https://github.com/Niko1221/Strata/blob/main/docs/AMD_HIP.md)。
- 公式HIPパッケージはROCm runtimeを同梱。既存llama.cpp ROCm10.0用PATHと混ぜず、Strata管理のlibrary searchを使う。共有GPUドライバは当面Adrenalin26.8.1で試し、必要な場合だけ**別ゲートで**driver26.10.1以降との互換検証。Windows/driver/BIOS/ROCmを同時に更新しない。
- ポート衝突回避：現行llama-serverが8080の場合、Strataは**8081等の別ポート**、localhost限定。**異なるポートでも2つの大きなモデルを同時GPUロードしない**。既存Windowsサービス設定を書き換えず、stop/startを記録。
- 計測向けにはTerminalで`strata launch --model-path <local-gguf-folder> --context 32k --kv fp16 --drafting off --parallel 1 --port 8081 --access local --plan`（`--plan`は事前確認）。実際の起動は`--plan`を外す。必要なら`--family qwen --model iq3_s`で**既知対応モデル**を先に用いる。**PLE16への直接対応は未確認**であり、初回にr6変換済みGGUFが読めると断定しない。通常プロファイル`--kv int8`・Draft Auto/DFlash2は別枠で記録。
- 初回はデバイス検出・モデルのロード・4kの短文・TG32 tokensで1 run、次に同一条件の32kで代表文書、最後に64kと既存MHの代表問題（品質）。writerモデルやPrompt token数の差に注意。無理な長文・128kを最初に走らせない。
- Strataの2026-11-07公開改善（4k690→1220、32k1107→1377 tok/s）は**Strata v0.2.11対v0.2.12／UD-IQ4_XS-v31**の作者報告で、r6/PLE16と直接比較できる数字ではない。DFlash2 defaultやgfx1151 PP fast kernelsは挙動/精度差を生むことがあるので品質ゲートをセットにする。

## 6. 独立して残す課題／変更管理

- ROCm TGにおけるGPU idle 15%台の局所RGPは、64k PP入力差とは別課題。CPU host submit・GPU queue対応が必要になった時に再開。
- MTP Draft K/V数値parity、ROCm temperature0でのrun差、StrataのDFlash2とr6 MTPの速度・品質比較、ROCmFPx HIP移植、Gemma4長文PP、Nanbeige、日本語記事化、専用自動化PC/SSHは別トラック。**既存の完了済みMask/MoE/FA調査を「未着手」に戻さない**。
- 実機作業ログ・成果物は実験リポジトリへ。現行`main` sourceの最適化flag default、配布済みZIP/tag、nssm本番サービス設定はこの調査では変更しない。
