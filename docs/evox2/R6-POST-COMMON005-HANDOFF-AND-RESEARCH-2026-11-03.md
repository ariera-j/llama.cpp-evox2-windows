# r6 COMMON-005完了後：未完了タスク／最新動向／ROCmFPx HIP移植の引き継ぎ（2026-11-03）

> **状態：調査・作業整理のみ。新しい推論ソース変更、Windowsビルド、実機計測、上流へのrebase、release変更は行っていない。**
> ここは2026-11-03 JSTに確認できたGitHub公開資料および当リポジトリの既存実測記録のスナップショットである。最新開発版や外部開発者の測定値を、EVO-X2のr6実測と混同しない。今後の作業順はユーザー指定の**調査後 → r5実入力 `llama-bench` のr6移植**を第一とする。

## 0. 確定したチェックポイントと今後の取り扱い

- r6統合済みソースは `main`。公開タグ／Vulkan preview ZIPは `evox2-integrated-2026-10-29`／b11908に固定したまま。後のmainドキュメントコミットはビルド済みバイナリとは同一視しない。
- COMMON-005 `QWEN4EXP_QSA_GATHER=1` は**明示的opt-in、ソースのデフォルトOFF**。ROCm TheRock 10.0、Qwen3.8 Flash Next IQ3 PLE16、MTP OFFの64k/128k/256k同一ビルドABBAではTG **+12.66%/+28.88%/+56.02%**、PPはほぼ不変。128k RGPでは選択後Attentionの対象kernelが約1490.8 → 40.7 µs。GPU全体のwall改善と単一kernel短縮を混同しない。
- 検索品質：128k・2モデル（元Unsloth IQ3と元IQ4）・2データseed・質問順A/B・Gather OFF/ONの**16run＋IQ4-B 2run追加＝18run**。全108回答インスタンス（12本問題 × 各フラグ9run）のstrict正解は**OFF 106/108、ON 106/108**。IQ4のseed20261026/B/ONで一度起きたQ08 `near_link_decoy` は直後の同条件ペア再試行では再現しなかった。**限定条件の品質スクリーニング合格**であり数値/logit完全一致の証明ではない。A/Bは同じ設問の並べ替えで独立サンプルではない。
- **COMMON-005の当初予定した開発・速度・RGP・128k検索品質ゲートは完了**。追加ABBAやRGPをこの作業の終了条件に追加しない。MTP ON、Vulkan active-path、256kの本格回答品質、ROCm数値非決定性、CPU-bound/GPU-idle現象は独立保留。
- 実測と条件は [COMMON-005実装報告](R6-COMMON005-IMPLEMENTATION-2026-11-02.md)、[RGP](R6-COMMON005-RGP-2026-11-02.md)、[18run品質ゲート](R6-COMMON005-MH128K-QUALITY-PLAN-2026-11-03.md) を参照。

## 1. 未完了の主作業 — 今回整理した暫定優先度

| 暫定順 | トピック | 状態・作業内容 | 依存／注意 |
| --- | --- | --- | --- |
| **次に着手** | **r5 TOOL-001 実入力 `llama-bench` をr6/mainへ移植** | r5で実装・Windowsスモーク合格、**r6へ未移植**。native `-f/--prompt-file`、`--prompt-slice head-tail|head`、`-c/--ctx-size`、PowerShellの`-InputKey/-InputFile/-PromptSlice/-Context`とrun provenanceを揃える | 新ブランチ、現行r6 APIへ適応。native `llama-bench` に `-f/-c` がない従来b11908の前提を保持 |
| **続いて** | **量子化別PP/TG再比較（r6）** | Vulkanで**IQ3_XXS、元IQ4_XS、Huihui IQ4_XS、Agention ROCmFP4 FAST v2**を同一ビルド/入力/サンプラ/MTP OFFで比較。ROCmはまずIQ3と元IQ4 | 先にTOOL-001を移植すると実文書／ランダム統制が容易。通常の量子化差と高速化フラグ差は別実験 |
| 後続 | QSA実マスク／selected-ID位置可視化 | r5では64k・128kのunion統計まで実施。文章（日本語技術・文学・コード）／ランダムで**実際にどのKV位置が選ばれるか**を観察 | 統計CSVのユニーク数と実マスク画像は異なる。診断同期のため速度結果と分離 |
| 後続 | MoE Expert選択の入力依存性 | 上記と同じ入力ジャンル・トークン範囲でExpert ID・頻度・分布／偏りを比較 | モデル層、MTP OFF/ON、実験条件を固定して観察。単なる選択の違いを速度改善とは扱わない |
| 後続 | 他推論エンジンの**実機比較** | 調査は本書で更新。Windows gfx1151でStrataを第一候補、Gufoを第二候補とし、モデル互換・必要RAM・PP/TG・品質を調べる | 外部エンジンのbenchmark数値はr6との直接比較不可。正式導入やソース移植は未決 |
| 後続 | 次の最適化テーマ決定 | 実際のr6 bottleneckに基づきMMVQのN幅、Vulkan CONCAT、FA、HIP FA/GDN、host sync、MoE dispatchなどを再順位付け | 旧2026-10-21順位は調査スナップショット。COMMON-005の長文TG改善を反映して再選定 |
| **独立候補** | ROCmFPxの**ROCm/HIPバックエンド対応** | 共通型とVulkanは既存。HIP専用演算は未移植。下記§4で実装難易度・ドナーを分離調査済み | 着手はTOOL-001と量子化比較後に再判断。必要なら独立ブランチと限定テスト |
| 条件付き | 次回upstream refresh | b12061/#29510等を別ブランチで比較 | COMMON-005のQSA/KV前提が変わる可能性。現行タグとb12013検証済みバイナリは固定 |

### 量子化比較が新たに重要になった理由

- **旧Vulkan b11592、MH-128K（2seed×A/B＝各モデル4run）：** IQ3 PP平均 **182.93**、元IQ4 **184.22**、Huihui **184.93**、Agention ROCmFP4 FAST v2 **185.26** tok/s。最速と最遅の差は約1.3%。ここでの「ROCmFP4」は**量子化形式名**で、**バックエンドは4モデルすべてVulkan**。
- **r6 ROCm b12013、MH-128K Gather OFF：** IQ3 PP平均 **286.04**、元IQ4 **313.94** tok/s（IQ4 **約+9.8%**）。Gather ONのTGはIQ3/元IQ4でそれぞれ約+25%/+23%（同2seed、品質試験付随速度）。
- **未解明：** Vulkanでは小さいIQ4のPP優位がROCmで約10%に広がる理由。テンソル構成差（IQ3に`q6_K`と`iq2_s`、IQ4に`q8_0`と`iq3_s`が多い）、HIPのMMQ/逆量子化・dispatch、VRAM clockなどが候補。カーネル別profileなしで因果関係を断言しない。Vulkan b11592とROCm b12013は世代も異なる。
- r6比較では①モデル別base計測、②該当モデルに適用可能な最適化flag別差分、③必要ならRGP、の順に切る。全モデルに同一フラグが有効だと仮定しない。

## 2. 本筋とは別に残す確認事項

| 項目 | 状態・再開条件 |
| --- | --- |
| ROCm RGP CPU-bound／GPU idle | Gather OFF以前とON後の両captureに一時的なidleがある。host submit・driver queue・同期を別プロジェクトとして観察。**COMMON-005の不具合だと断定しない** |
| ROCm出力再現性 | temperature=0・固定seedでもrun差あり。既存の[再現性調査](R5-ROCM-QSA-REPEATABILITY-2026-10-22.md)を基点に、必要時に候補kernel/精度を切り分け |
| MTP Stage-B／flatten Draft K/V数値同等性 | 関連フラグはopt-in lab限定。出力ハッシュ合致だけでは内部KV一致を示せない |
| ROCm MTP-ON server | r6でCLI／routerの限定確認はあるが、最新flagプロフィールの一般支持範囲と区別。必要時にserverの長期運用・memory returnを再評価 |
| 256k・MTP-ON・VulkanでのCOMMON-005品質 | 今回の128k ROCm MTP-OFF合格からは外挿しない。常用ケースが生じたときのみ別ゲート |
| Gemma 4 31B／26B | r6で回帰・機能確認は実施。31Bの長文PPの遅さとFA/kernel選択の原因は未解明。常用性が上がったら独立profile |
| MH-Hard | 既存の凍結MH-128Kを変更せず、複数成立経路を区別する新しい高難度データセットとして設計する案 |
| Nanbeige4.3-33B | Gemma4の日本語要約・文書生成の置換候補として保留。品質、速度、量子化／モデル対応は未実機評価 |
| Qiita記事 | P-MODE、Qwen3.5長文、MTP、5モデル要約、MH検索等の別々の記事構成・投稿準備。技術評価と投稿進捗は別管理 |
| 公開Vulkan ZIP／Windows環境 | 公開b11908 previewのDLL依存・展開後実行可否に関する旧調査と、最新mainソースを混同しない。再配布を企画するとき再検証 |

## 3. 2026-11-03 upstream／他エンジン調査スナップショット

### 3.1 ggml-org/llama.cpp

- 11月3日JST時点で確認した公開release：**[b12061](https://github.com/ggml-org/llama.cpp/releases/tag/b12061)**（2026-11-02 23:17 UTC公開）。r6統合ベースはb11870、既存COMMON-005実測バイナリはb12013／独自source commit `f29592d6a`。build番号だけでは性能を比較できない。
- **[PR #29510 / commit `1b6935b22`](https://github.com/ggml-org/llama.cpp/pull/29510)**（2026-11-02）：unified KV/multi-sequence用`flash_attn_ext_rows`、QSA関連graphとKV row layoutを広範囲に変更。前段の**[PR #31243 / `27b7a8a`](https://github.com/ggml-org/llama.cpp/commit/27b7a8a009de2f5f75d8111b6171381c920df764)**と併せ、次のrefresh時にCOMMON-005の`k-pool/selected-ID/kv-mask`、single-seq eligibility、full-KV fallback、MTP rollbackとの互換性を先に検査する。**今のmainに即mergeしない**。
- **[PR #31188](https://github.com/ggml-org/llama.cpp/pull/31188)**：CUDA/HIP MoE `MUL_MAT_ID` gate/up＋GLU融合。量子化別PPやMoE dispatchと関連し得るが、gfx1151での有効パス・性能は未計測。
- **[PR #30146](https://github.com/ggml-org/llama.cpp/pull/30146)**：Vulkan RDNA3/RDNA4 small-N split-K選択。MTP MMVQ width実測との関連候補。**[PR #31266](https://github.com/ggml-org/llama.cpp/pull/31266)**：Vulkan skipped row zeroingの不要scan削減。S5/S6・Expert ID経路との適用重複を確認してから評価。
- 既存watch：Vulkan MMVQ 9–16列 [#31196](https://github.com/ggml-org/llama.cpp/pull/31196)、FA CM1 [#31197](https://github.com/ggml-org/llama.cpp/pull/31197)、PLE外部GGUF [#31185](https://github.com/ggml-org/llama.cpp/pull/31185)、Qwen MTP系。**PRのstatus・base包含は次の実装直前に再確認**。

### 3.2 他エンジン（作者公開資料の比較、EVO-X2ユーザー実測ではない）

| ソース | 11月3日確認状況 | 関連性／制約 |
| --- | --- | --- |
| **[Strata](https://github.com/Niko1221/Strata)** | **[v0.2.10](https://github.com/Niko1221/Strata/releases/tag/v0.2.10)**（11/03 JST公開）。前版**[0.2.9](https://github.com/Niko1221/Strata/releases/tag/v0.2.9)**でWindows Strix Halo：Qwen3.8 IQ3_S 8k PP **791→1424**、32k **778→1460** tok/s、Unsloth UD-IQ4_XS 8k **794→1243**（**0.2.8比**、作者交互計測）。v0.2.10はQwen3.8の通常単発リクエストで**DFlash2を既定ドラフター**に変更。作者のWindows gfx1151比較ではDFlash2対MTPでIQ3_Sの短/長TG **+8.4%/+4.0%**。 | **実機比較の第1候補**。同一GGUF使用可否、F16 vs int8 KV、MTP/DFlash2/OFF、prefix-cacheの扱い、試験入力の種類を一致させる。v0.2.9の`STRATA_PF_F16`や`STRATA_SELECT_WMMA`はselectedセル境界の数値差があり得るので、MH品質も比較する。 |
| **[Gufo](https://github.com/gufo-org/gufo)** | **[v0.28.1](https://github.com/gufo-org/gufo/releases/tag/v0.28.1)**。Qwen3.8のprefill row経路修正とMTP draft chain停止処理を含む。公式Flash-Next構成はUnsloth **UD-Q4_K_XL**（4 shard）、追加Q8 MTPなど。 | **実機比較第2候補**。現在のUnsloth IQ3_XXS／IQ4_XSをそのまま使えるとは未確認。主な公開速度は別モデル・ツールチェーン／Linux／128GB条件もあるため直接比較不可。 |
| **[Project Maya](https://github.com/mw00/project-maya)** | **[v1.1.50](https://github.com/mw00/project-maya/releases/tag/v1.1.50)**（v1.1.49より新しい）。モデル管理API／Turbo／thinking budget／DeepSeek長文改善など。 | Qwen3.8 CYBER-FROST等の独自構成。r6と量子化・実験条件を揃えるコストを考えると優先度は中。Turboは品質条件が変わる可能性。 |
| **[Halogen](https://github.com/peonist-ai/halogen-flash-server)** | Qwen Flash-Next/GGUFサポート資料。Linux（Podmanなど）でのAMD GPU利用を中心に調査済み。 | Linux環境を導入後に実機候補。Windowsで同じGGUF・同条件を使えることは確認していない。ライセンス／再利用条件は個別確認 |
| **[s1-fork](https://github.com/vahpetr/llama.cpp-s1-fork)、[SelfRef](https://github.com/SelfRef/llama.cpp-rdna)、[Unsloth](https://github.com/unslothai/llama.cpp)** | QSA/FA/MMVQ/MoEの差分ドナーとして継続観察 | 全forkを無条件にmergeしない。現r6で使うkernel/shapeと重複する部分を引いて評価 |

**比較設計の注意：** 同じGPUでもモデルweight、独自モデルpack、QSA selected-IDs近似、KV dtype、speculative draft、context、cache（cold PPと再利用PP）、OS/driver/ROCm、出力品質が異なる場合、公開PP/TG比率をそのまま移植効果やエンジン優劣とは言えない。長文111k/128kでのr6との公平比較は未実施。

## 4. ROCmFPxをROCm/HIPバックエンドへ移植する難易度調査

### 4.1 r6現状（2026-11-03ソース静的確認）

- **対応済み：** `GGML_TYPE_Q4_0_ROCMFP4`(100)、`Q4_0_ROCMFP4_FAST`(101)、`Q6_0_ROCMFPX`(102)、`Q8_0_ROCMFPX`(103)、`Q3_0_ROCMFPX`(104)、`Q2_0_ROCMFPX`(107)の共通型／FTYPE／CPU fallback。Vulkanは5形式のdequant/GET_ROWS/`MUL_MAT`/`MUL_MAT_ID`、ROCmFP4/FASTなどの整数dotまで移植・検証済み（[r6 S2](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md)）。
- **未対応：** r6 `ggml/src/ggml-cuda/{convert.cu,dequantize.cuh,vecdotq.cuh,mmvq.cu,mmq.cu,getrows.cu,ggml-cuda.cu}`にはROCmFPx専用分岐が**見当たらない**。r6 HIPは`ggml/src/ggml-hip/CMakeLists.txt`からggml-cudaの実装群を共用する構成だが、Vulkan shaderは使わない。**GGUFを認識できるだけでHIPで全重みをGPU offloadできるとは限らない**。
- 実際のAgention **ROCmFP4 FAST v2 PLE16**の先行モデルログは`q4_0_rocmfp4_fast` 50テンソルと`q3_0_rocmfpx` 16テンソルを報告。まず**型101/104**を最小対象とし、GGUFとMTP sidecarの全tensor typeは改めてinventoryする。型100/102/103/107と量子化KV cache対応を初回必須範囲に広げない。
- **未検証：** b12013 ROCmでのROCmFP4モデル実行。Vulkanの4k/16k/64k/128k成功をROCmに外挿しない。過去のsourceレビューだけではWindows HIPのビルド／性能は不明。

### 4.2 移植ドナーと技術範囲

**一次ドナー：** [charlie12345/ROCmFPX](https://github.com/charlie12345/ROCmFPX)（2026-11-03に公開mainを確認、先頭コミット`fb08d7cdb67082ddda15a25e64dc7ec413afc41c`、2026-09-23）。古いupstream基盤を含む独立forkで、**新r6への単純cherry-pickやそのままWindowsビルド可能という意味ではない**。共通GGUF形式とHIPカーネルを選別して移植する。

関連箇所：

- `ggml/rocmfp4/rocmfp4_hip.cu` とコードブック／スケール用`*.cuh`：HIPデバイス実装・速度処理。
- `ggml/src/ggml-cuda/convert.cu`、`dequantize.cuh`、`getrows.cu`：quant重みのdequant/GET_ROWSを接続。
- `ggml/src/ggml-cuda/vecdotq.cuh`、`mmvq.cu`、`mmq.cu`：single-token TGとbatch PP、量子化行列dotの本体。
- `ggml/src/ggml-cuda/ggml-cuda.cu`：GPU対応判定、F16活性化条件、分岐、`MUL_MAT_ID`などのdispatch。
- `ggml/src/ggml-hip/CMakeLists.txt`：追加HIPファイルのコンパイル対象・Windows build依存。

ドナーにはFP4/FASTだけでなくROCmI4、量子化KV FlashAttention、特殊FA/GET_ROWS、各種高速化が混在する。最初から丸ごと移植しない。現行r6の`F16 KV`通常経路ではドナーの**量子化KV専用FAは初回移植に不要**。共通型／CPU／Vulkanコードを二重に追加しない。

### 4.3 難易度と分割ゲート（**工数の確定見積ではない**）

| 段階 | 内容・合格条件 | 見立て |
| --- | --- | --- |
| 0：静的差分監査 | 型101/104の実テンソルとshape、r6のHIP/CUDA API差、Windows gfx1151コンパイル可否、既存の量子化type traits、ドナーライセンス・build flags | **小〜中** |
| 1：最小HIP機能移植 | dequant/GET_ROWS/`MUL_MAT`/`MUL_MAT_ID`を型101/104に限定。現行r6で**clean Windows HIP build**、4k model load、49/49 GPU offload、CPUに巨大なquant重みが残らないこと | **中**（現行r6とドナーのAPI差次第） |
| 2：数値correctness | focused `test-backend-ops`、幅1/3/4/5/6/7/8、MoE skipped expert IDs `-1`、CPU refとの許容誤差、FAST scale／partial tiles／F16 activationなど | **中〜高** |
| 3：実入力安定性 | 4k/16k → 64k → 128k、GGUF同一性、Windows TheRock 10.0実ロードDLL、UMA使用、OOM・GPU-reset・format/OOM fallback確認、MTP OFF／f16 KV | **中** |
| 4：性能／拡張 | 同じr6で元IQ3/元IQ4/ROCmFP4 FAST比較、HIP MMVQ/MMQの実dispatch、必要に応じてMTP sidecar・他形式・KV quantと最適化 | **高**（モデル互換を超える調整） |

**総合判断：** *まず対象モデルをROCmで動かす*のは**中程度（移植可能性は高いが未ビルド）**、既存ROCm運用並みに安定させ高速化するのは**中〜高／高**。新たな量子化形式設計を要する話ではないが、複数カーネルとWindows HIPバイナリの数値検証は必要。モデルのロードだけではPASSとしない。

- 実装する場合は`main`から**別research branch**、既存b11908/b12013をcontrol、4k smokeまでは小さく分けてcommit／measure。
- **Windows gfx1151で既往の危険な全`FLASH_ATTN_EXT` backend suiteや`Build-ROCm.ps1 -RunBackendTest`一括実行は避ける**。演算名・型・shapeを限定する。初期のF16 KVターゲットではquantized FAをテストしない。
- **移植着手は今ではなくTOOL-001後に再判断**。ドナーは開発状況・source APIを再確認してから採用。性能改善幅は未推定。

## 5. 次の新チャット：r5 `llama-bench` 実入力対応をr6へ移植

**最初のタスクはこの項目。** 今回の調査だけではbenchソースを編集していない。r5の実装／Windows Vulkan smokeは [R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md) 参照。元ドナーcommit [`4bf9af6f`](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/4bf9af6fefa98622a65bd8d4c04ba73a02e27422)。

引き継ぎ手順：

1. **現mainの`tools/llama-bench/llama-bench.cpp`と`tools/evox2/benchmark/Measure-LlamaBench.ps1`をr5ドナーと比較**。現r6で引数/クラス構造が変わっている可能性があるので、コミットの機械的適用前に設計差を確認する。
2. native `-f/--prompt-file`でモデル毎に**実テキストを計測時間外でtokenize**、`--prompt-slice head-tail|head`、`-c/--ctx-size`。指定した`-p N`に実token数が足りない場合は拒否／水増ししない。ファイル指定なしの従来ランダム`llama-bench`動作を維持。
3. wrapper `-InputKey/-InputFile/-PromptSlice/-Context`と`conditions.json`内のmode、input SHA256、token数、context、sliceを一致させる。ユーザー固有の`local.psd1`はpushしない。通常の`llama-cli`入力（テンプレート展開済）とは別の**raw tokenize**入力であることを明記。
4. **独立ブランチ／新build directory**でVulkan first、`llama-bench --help`とrandom／real head-tail／real headの各256-token smoke、short/empty inputの失敗、実トークン数、PP差とメモリ監視を検証。ROCm build/同入力比較はVulkan gate後に判断。先に長文全matrixを走らせない。
5. 変更対象は**計測ツールに限定**。COMMON-005フラグ/挙動、GGML kernel、既存公開b11908 ZIP/tagを変えない。Windows検証ログを確認してからmainへの統合可否を決める。

このドキュメントは次のチャットの**実行入口**であり、実装完了報告ではない。

## 6. 参照記録

- [r6後半のROCm長コンテキスト／保留タスク](R6-ROCM-256K-MTP-OFF-ON-COMMON005-2026-10-30.md)
- [元の統合後最適化候補](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md)
- [r5 QSA 128k入力別統計](R5-QSA-UNION-128K-THREE-CORPUS-STATS-2026-10-10.md)
- [r5実入力bench移植元](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md)
- [r6 ROCmFPx Vulkan採用範囲](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md)
- [2026-10-28までの外部調査ログ](PERFORMANCE-RESEARCH-LOG.md)
- [COMMON-005限定品質検証](R6-COMMON005-MH128K-QUALITY-PLAN-2026-11-03.md)
