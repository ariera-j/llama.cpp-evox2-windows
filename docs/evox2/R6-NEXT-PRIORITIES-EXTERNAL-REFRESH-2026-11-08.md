# 2026-11-08: r6後続タスク再順位付けとupstream/fork/他エンジン更新、IQ1・新IQ3／Strata着手準備

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
