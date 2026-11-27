# EVO-X2 upstream・fork・推論エンジン調査（2026-11-26）

> **2026-11-27 引き継ぎ。** 優先項目D0を製品SHA `a650d641ee99198543697e1e3913c593059721f7` に採用済み。次工程はROCmFP4 FAST HIP対応。 [D0採用記録](B12651-D0-5-HIP-IQ4NL-GETROWS-INTEGRATION-20261127.md) · [HIP-1以降](ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md#段階4--実装候補と承認後の検証)


## 参照時点と再開方法

2026-11-26 22:10–22:22 JST に GitHub と実機の Git 参照を確認した。GitHub の文書正本は `f47e19a0203add434545a35adbd097215775d03e`、現行製品と専用 clone の HEAD は `9ae819d5be4fe9861d2aa8547983aed801c437ac`、標準ビルド b12696 のビルド元は `20f48bfe162d8d886b9f5fea7ad6d7df91eb3266`。実機のローカル main は `07c33cf4b7e69057f45b9903f762b28ec221d588`、追跡参照は `f47e19a`。製品の推論ソースを文書と標準ツールの正本の推論ソースから区別する。 [標準ビルド検証](automation/BUILD-VALIDATION-20261126.md)

前回の ThinkPad 上の調査用 bare Git と b12767 の調査結果を再利用した。22:22 JST に再照合した公式 master は `a866b4ade63921826c530307a368fbca3a334a0b`。初回照合時の `4ba835c637d863c00f54b59b8a0285d8d4db04cd` の次に UI 変更 #33082 が入った。番号付きの最新ビルドタグは `b12777`、`caea914e9d05153aa32b96a846dca543e7cb16be`。GitHub が Latest と表示する正式リリースは `v1.1.0`（注釈付きタグ `bdda03620c7355b4779afa8f78cb86129e9bf408`、指すコミット `171527522610996f5f0acf12334e185156ca8f44`、同じコミットの番号タグは `b12774`）。前回の b12767 は `a8ad690ca9239ea35db4de47e00cf632d01895fd`。再開時は公式 master と製品ブランチを読み取り用リポジトリへ取得し、`git merge-base`、`git log <base>..<head>`、`git show <PRのマージSHA> -- <path>` で追跡する。 [公式 master 固定版](https://github.com/ggml-org/llama.cpp/commit/a866b4ade63921826c530307a368fbca3a334a0b) · [正式リリース](https://github.com/ggml-org/llama.cpp/releases/tag/v1.1.0) · [番号付きビルド](https://github.com/ggml-org/llama.cpp/tree/b12777)

## 段階1 — upstream 差分

比較の出発点は upstream b12651 `f5e6915c28f10330885fcb9243a93ae98d3115ab`。現行製品と公式 master の共通祖先で、製品側42／upstream側138コミット。前回の b12767 まで116、そこから22件を追加確認。Qwen3.8 Flash Next のモデル実装は `src/models/qwen4exp.cpp`。QSA と GDN を持ち、製品ブランチは split PLE16 と ROCmFPx 量子化および Vulkan 経路を追加している。 [Stage 1](B12651-STAGE1-COMMON001-20261124.md) · [Stage 2](B12651-STAGE2-ROCMFP4-VULKAN-20261124.md)

| 変更 | 確認した適用範囲・採用判断 |
| --- | --- |
| Vulkan FA [#31323](https://github.com/ggml-org/llama.cpp/pull/31323) `d8f30a5b`、AMD Windows [#32415](https://github.com/ggml-org/llama.cpp/pull/32415) `8f647f1f` | 両方とも b12651 の祖先。前者は RDNA3/4 の協調行列による PP 改善、後者は AMD Windows の proprietary ICD で flip を選ばないガード。既存 Gemma 4 31B の Global FA 512／SWA 256 の計測結果を新規差分の改善と数えない。 [隔離移植の検証](V1-GEMMA4-VULKAN-FA31323-PORT-2026-11-21.md) |
| GDN replay [#31669](https://github.com/ggml-org/llama.cpp/pull/31669) `d35dc4d9`、Vulkan chunked replay [#32721](https://github.com/ggml-org/llama.cpp/pull/32721) `72cda4a2` | `src/llama-context.cpp` の `rs_replay` には `QWEN4EXP` が明示され、`n_rs_seq > 0` で有効。recurrent state のスナップショットを積む方式から入力の再生へ移行する。主に MTP／speculative verification の状態管理、メモリと TG に関係する。Vulkan の chunked shader は cooperative-matrix、形状と共有メモリの条件で選択。通常 PP の改善量や MTP OFF のロード改善は未確認。recurrent cache、graph、CPU、HIP、Vulkan を横断するため移植・検証は中〜大。 |
| ROCm 共有の Flash Attention [#32901](https://github.com/ggml-org/llama.cpp/pull/32901) `94a1e4b7` | `ggml/src/ggml-cuda/fattn{,-common,-tile,-mma-f16}.*` のロードと dispatch を変更し、512/512 も通る。Gemma Global 512／SWA 256、Qwen の既存 HIP FA の回帰確認候補。PR は HIP の品質修正を含む。Windows gfx1151・f16 KV の性能改善は未確認。Vulkan FA は別経路。 |
| [#30685](https://github.com/ggml-org/llama.cpp/pull/30685) `62d6c8cb` | バックエンドスケジューラの推論入力転送をまとめる。共有 CUDA/HIP device の `fast_async_host_input` は true、Vulkan は false。GGUF の読み込みやモデルアップロード用の修正として扱わない。 |
| [#30318](https://github.com/ggml-org/llama.cpp/pull/30318) `679d8677`、[#30997](https://github.com/ggml-org/llama.cpp/pull/30997)、[#28992](https://github.com/ggml-org/llama.cpp/pull/28992)、[#32828](https://github.com/ggml-org/llama.cpp/pull/32828) | GPU 上の sequence state 復元とサーバの prompt-cache 再利用を改善。両モデルのサーバ利用で候補。単発の bench PP/TG とは評価条件が異なる。 |
| [#32795](https://github.com/ggml-org/llama.cpp/pull/32795)、[#32740](https://github.com/ggml-org/llama.cpp/pull/32740)、[#32960](https://github.com/ggml-org/llama.cpp/pull/32960) | DeepSeek 4.1 の fused indexer K 読み出し、indexed bias 基盤、HY V4 Flash の DSA iSWA は QSA や Gemma の Global FA と隣接する実装。Qwen の pooled Top-K／選択マスク、Gemma の既存 Global FA を同じ fast path に置き換える差分は確認できない。 |
| [#32566](https://github.com/ggml-org/llama.cpp/pull/32566)、[#32965](https://github.com/ggml-org/llama.cpp/pull/32965)、[#32805](https://github.com/ggml-org/llama.cpp/pull/32805)、[#32837](https://github.com/ggml-org/llama.cpp/pull/32837) | few-row MMQ のゼロブロックと浮動小数点 MMV のオフセットは正しさの候補。後2件の MMQ 選択は Vega20／CDNA1 向け。gfx1151 の量子化 TG 高速化とみなさない。 |
| [#32080](https://github.com/ggml-org/llama.cpp/pull/32080)、[#33014](https://github.com/ggml-org/llama.cpp/pull/33014)、[#32225](https://github.com/ggml-org/llama.cpp/pull/32225) | Windows サーバの Ctrl-Break 終了、量子化ビルド時のマクロ衝突、UI のロード取消。運用上の候補で、既知の M005 ハードフリーズの修正を示すものではない。 |
| [#15550](https://github.com/ggml-org/llama.cpp/pull/15550)、[#32859](https://github.com/ggml-org/llama.cpp/pull/32859)、[#33038](https://github.com/ggml-org/llama.cpp/pull/33038) | 容量／bpw 指定の量子化探索、BPE tokenizer の高速化と Metaspace 修正。新規 GGUF 作成や入力処理に関係する。既存 GGUF の GPU カーネルによる PP/TG 改善とは区別する。 |

### b12767 からの22コミットと現行コード

| 変更 | 差分と扱い |
| --- | --- |
| [#33045](https://github.com/ggml-org/llama.cpp/pull/33045) `e38ea719bd29defbd8e5d11b5e1d799572cea45a` | #32901 後の ROCm CI 修正。`fattn.cu` で DKQ=576 かつ GQA 比が4の倍数でない場合、tile 経路を選ばない。512/256 の Gemma 固有高速化ではない。#32901 を個別評価する場合も後続修正までを一緒に読む。 |
| [#32533](https://github.com/ggml-org/llama.cpp/pull/32533) `09c1410642fa0395ca234571980093bc5c7f2ef5` | BF16 activation（src1）の MUL_MAT／MUL_MAT_ID。CPU と CUDA/HIP 共有の量子化・MMQ/MMV 経路に触れる。BF16 を実際に入力するグラフと対応形状に限定。既存 IQ／FAST の native 経路や PP の高速化を自動で提供するものではない。 |
| [#32943](https://github.com/ggml-org/llama.cpp/pull/32943) `51ab45e3c52304d7cc8e43e5a913baa8ccd7abcc` と [#33087](https://github.com/ggml-org/llama.cpp/pull/33087) `b671865c7bd44c8c2d4709b5f707bd55f7f612fd` | 前者は DeepSeek V4.1／Inkling 2 のような正規化の分母に加算バイアスを持つ top-k MoE pattern の融合。現行 Qwen4Exp の通常 softmax routing が新 pattern を使う証拠はない。後者は既存 fusion を `fusion.cu` へ動かす。HIP 移植時の比較位置に影響する。 |
| [#33006](https://github.com/ggml-org/llama.cpp/pull/33006)、[#33044](https://github.com/ggml-org/llama.cpp/pull/33044)、[#32365](https://github.com/ggml-org/llama.cpp/pull/32365) | 非連続 concat、MMF のオフセット幅、HIP CI の occupancy 検査。正しさや診断用の候補。CI は GCN/CDNA の解析を含むが gfx1151 の速度計測ではない。 |
| [#33073](https://github.com/ggml-org/llama.cpp/pull/33073) `55d482814bb3b985daa7bfa175c6d628fc27beac` | Inkling-2-Mini の DFlash2 対応。Qwen3.8 の Strata DFlash2 と同一の重み・モデル契約ではない。 |

固定版までで `qwen4exp.cpp` の直接差分は #31669、`gemma4.cpp`・`gemma4-assistant.cpp`・`llama-model-loader.cpp` と Vulkan FA シェーダーには直接差分を確認できなかった。最新の HIP device の GET_ROWS 判定は IQ4_NL の256要素条件を維持。公式 `ggml.h` に FAST/FP3 のカスタム型は見当たらない。型ID、PLE16 split、Vulkan dispatch は再ベース時も下流で検証が必要。 [上流比較](https://github.com/ggml-org/llama.cpp/compare/f5e6915c28f10330885fcb9243a93ae98d3115ab...a866b4ade63921826c530307a368fbca3a334a0b) · [最新 HIP GET_ROWS 判定](https://github.com/ggml-org/llama.cpp/blob/a866b4ade63921826c530307a368fbca3a334a0b/ggml/src/ggml-cuda/ggml-cuda.cu#L4212-L4216)

## 段階2 — 他 fork・エンジン

2026-11-26 22:11 JST の各 HEAD を固定した。量子化 ABI と HIP の移植元は [専用比較](ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md) に記録した。次回は固定 SHA を取得して下記のファイルの差分を追い、第三者ベンチマークは同一モデル・量子化・PP 長と既存 context 深さ・OS・SDK・draft 条件に分けて読む。

| 対象と固定 SHA | ソースで確認した候補 | EVO-X2 への適用判断 |
| --- | --- | --- |
| [Strata](https://github.com/Niko1221/Strata/tree/c234774038d1c9249cb33637d27b895d47b39786) `c234774038d1c9249cb33637d27b895d47b39786`、公開 [v0.2.22](https://github.com/Niko1221/Strata/releases/tag/v0.2.22) | `engine/src/prefill/gemm.cu` の `try_hipblaslt`、1312 付近の FP16 PF_GEMM、1492 付近の PF_PAD。 `prefill.cpp:1034` は K=6144 の対象投影、`wmma_gemm.cu:703` は gfx11 の FP16 WMMA。 `moe_fused_iq.cu` 等は expert 投影の別経路。 | Windows gfx1151 の公式資料に PP matrix-core 経路と専用 prompt buffer がある。現行 GGML では形状固有 WMMA と padding を個別に切り分けられる。IQ3 PLE16 は expert 型と形状が一致する場合に候補、FAST は専用 decoder/decoder→FP16 を要する。Gemma 4 31B は dense の形状を別途調べる必要があり、Qwen の MoE/HC 向け実績は移せない。MIT。 [gfx1151](https://github.com/Niko1221/Strata/blob/c234774038d1c9249cb33637d27b895d47b39786/docs/STRIX_HALO.md) |
| [Gufo](https://github.com/gufo-org/gufo/tree/233367ae3744a9d1dd5cf82ef761b3436dc243c6) `233367ae3744a9d1dd5cf82ef761b3436dc243c6`、公開 [v0.37.0](https://github.com/gufo-org/gufo/releases/tag/v0.37.0) | `src/models/qwen38_flash_next/kernels/rocm/mmq/moe_wave32.hip.cpp:228` の gate/up 向け wave32、`mmid.hip.cpp`、共有 Qwen attention/GEMM、continuation hooks。 | MIT、Linux／Windows を掲げる。gfx1151 特化の PP/TG と長文の設計参照。公開比較は UD-Q4_K_XL、128 GB、HTTP greedy、約 PP2048/TG128 と古い llama.cpp。MTP は shared Q8_0・adaptive。現行 IQ3 PLE16、FAST、生成 Gemma 4 31B の互換性および優位性は未確認。独自の実行グラフとキャッシュがあるため直接移植は中〜大。 [比較条件](https://github.com/gufo-org/gufo/blob/233367ae3744a9d1dd5cf82ef761b3436dc243c6/docs/internal/models/qwen3.8-flash-next/BENCHMARKS.md) |
| [Talus](https://github.com/nsbradley88/talus-public/tree/e5edb0e9eb2b505e3f936702706a344b6abb81b6) `e5edb0e9eb2b505e3f936702706a344b6abb81b6`、v0.1.9 | Strata／ggml 由来 HIP と Rust 実行系。長い prompt と cache を追う際の限定的な比較対象。 | MIT と第三者 ggml LICENSE。公開 128 GB の資料は参考。既存 PLE16/FAST/Gemma 31B の同条件実績と Windows/TheRock 互換は未確認。 |
| [agentionai の Vulkan 作業枝](https://github.com/agentionai/llama.cpp/tree/3c75be02f45081987e1b4baafd5aa4c5af245de9) `3c75be02f45081987e1b4baafd5aa4c5af245de9` | `perf/strix-vulkan` の `src/llama-context.h:388` は MTP／短 ubatch 用の graph slots を宣言。確認した default HEAD と当該枝の `src` および `ggml/src/ggml-vulkan` の内容は同一。Vulkan IQ2_S MatVec は、既存の検証記録にある各 shader の独立性と dispatch を優先して比較する。 | 短い verify 幅での graph 再利用は TG／起動オーバーヘッドの候補。保留中の scheduler buffer と既存 graph 再利用との競合を確認する。IQ2_S が実際に使われるテンソル、PP/TG 別の実行形状、FAST FP4 の型分岐は別確認。 [既存 IQ2_S 調査](iq2-s-vulkan-matvec-20261125/README.md) |

過去に追った [SelfRef/llama.cpp-rdna](https://github.com/SelfRef/llama.cpp-rdna/tree/b465928c0a561d4e492986cb6b1bd9c3a6f229b5) `b465928c0a561d4e492986cb6b1bd9c3a6f229b5`、[Project Maya](https://github.com/mw00/project-maya/tree/53885cef8faf0d3b3f7e28c0b1537a056c1f3ecf) `53885cef8faf0d3b3f7e28c0b1537a056c1f3ecf`、[Halogen](https://github.com/peonist-ai/halogen-flash-server/tree/6beb3da76e06713d0522221aa7f0b66e142cb20e) `6beb3da76e06713d0522221aa7f0b66e142cb20e` は公開 HEAD を再確認。今回は SelfRef を古い MMQ インターフェースとの比較用とし、Maya・Halogen は対象の PLE16、Windows gfx1151、同条件の根拠を確認した段階で再評価する。各 HEAD の内部差分は今回の深掘り対象から外した。 [前回の候補一覧](PERFORMANCE-RESEARCH-LOG.md)

### Strata v0.2.13 からの差と候補の独立性

- **PF_GEMM／PF_PAD／hipBLASLt。** 以前の K=6144 の padded stride は最新の公開ソースにもある。PF_PAD は PF_GEMM と対応形状に依存。FP16 PF_GEMM を先に試し、到達しない形状は hipBLASLt を含む既存 dispatch に進む。TheRock 10.0.0 へ package の solution ID をそのまま持ち込む根拠はない。FP16 化の一時容量と積算順序も評価対象。 [前回比較](V1-STRATA-VS-LLAMA-DENSE-GEMM-SOURCE-COMPARISON-20261115.md) · [現在の GEMM](https://github.com/Niko1221/Strata/blob/c234774038d1c9249cb33637d27b895d47b39786/engine/src/prefill/gemm.cu#L1295-L1332)
- **MoE fusion／iGPU PP。** Windows gfx1151 の公式文書は engine 0.1.52 以降に PF_GEMM・PF_FUSED・PA_FAST・HIP_WMMA・HC_UPMIX を自動選択し、expert-cache を prompt scratch に貸さないと説明する。短い断片の staged entry と長い prompt 用の経路は分けて評価する。Matrix8 の一括 toggle は過去の複数機能まとめの比較で、個々の gain を取り出せない。融合は既存 ggml の `MUL_MAT_ID`、ID 並べ替え、gate/up activation、accumulate の契約を調べてから。 [Windows の条件](https://github.com/Niko1221/Strata/blob/c234774038d1c9249cb33637d27b895d47b39786/docs/STRIX_HALO_WINDOWS.md)
- **gather／HC-08。** QSA gather、expert-ID gather、PLE の GET_ROWS は独立した演算。現行 b12651 の pooled Top-K と r6 の COMMON-005 は同じ前提にできない。HC の一致を調べる場合は公開文書の `STRATA_HCD_EXACT` と `STRATA_HC_Q8` を別に扱う。前者は特定の 320×10240・hipBLASLt solution の積算順、後者は HC 重みの表現に関わる。過去の HC-08 名称だけでは現行版の同一スイッチや同一速度を確認できない。 [Strata の実装条件](https://github.com/Niko1221/Strata/blob/c234774038d1c9249cb33637d27b895d47b39786/docs/STRIX_HALO.md) · [既存下流履歴](PATCHES.md)
- **suffix／MTP／DFlash2。** 公開 launcher では DFlash2 と MTP の同時ロードを避け、Strix Halo 用の draft window に別条件がある。suffix の提案や adaptive 戦略は TG 向けで、入力の反復性と受理率の影響が大きい。DFlash2 は適合する別の draft 重み、メモリ見積もり、品質確認が必要。既存 MTP OFF の PP/TG と混ぜない。公開 UI・launcher の実装と、各配布バイナリで選択された経路は区別する。 [draft 選択のコード](https://github.com/Niko1221/Strata/blob/c234774038d1c9249cb33637d27b895d47b39786/terminal/strata_control/drafting.py)

### モデル動向

[Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) は 26.4B の Apache 2.0 open-weight 視覚言語 MoE。中間層の反復、SWA と global attention の混在、GGUF 提供が技術上の見どころ。上流 [#32218](https://github.com/ggml-org/llama.cpp/pull/32218) の DSpark はこのモデル向け。[Raon-1-mini](https://huggingface.co/KRAFTON/Raon-1-mini) は hybrid/recurrent 系の比較対象で、上流 [#32176](https://github.com/ggml-org/llama.cpp/pull/32176) は preview 対応。いずれも EVO-X2 での量子化・長文・Windows 実行は未検証。

## 段階4 — 基準値、更新判断と優先順位

Windows 11、Radeon 8060S gfx1151/RDNA 3.5、UMA 96 GiB、Performance。基準は Adrenalin 26.11.2／表示 32.0.32029.2010／Vulkan ICD 9.2.10.416 API 1.4.359、SDK/Loader 1.4.357.0、Vulkan Clang 22.1.3、TheRock 10.0.0／AMD Clang 23.0.0git。既存 b12696 は標準ビルドの確認済み SHA に基づく。8k bench の行は報告書上の b12690 診断ビルドで、推論完了後に回復判定で後続を止めた回。再開した残り5件は b12696。 [ドライバー更新の原報告](automation/ADRENALIN-UPDATE-COMPARISON-20261126.md) · [診断計測](automation/B12651-MODEL-LOAD-DIAG-RESULTS-20261126.md)

| 更新後条件（各1回） | PP / TG tok/s |
| --- | ---: |
| Vulkan IQ3 PLE16 8k bench | 636.35 / 29.61 |
| Vulkan IQ3 PLE16 128k | 308.57 / 23.27 |
| Vulkan FAST PLE16 64k | 407.46 / 26.08 |
| Vulkan Gemma 4 31B QAT 32k | 99.96 / 9.00 |
| ROCm Gemma 4 31B QAT 32k | 186.48 / 9.01 |
| ROCm IQ3 PLE16 64k | 408.28 / 22.13 |

Vulkan の Qwen PP は観測値で約1～5%改善。Gemma Vulkan は PP 64.44→99.96（+55.12%）、PP 電力中央値 119→68 W、VRAM クロック中央値 1000→592 MHz。ROCm Gemma は PP 186.87→186.48（−0.21%）。各1回で稼働時間・温度・キャッシュ等を分離しておらず、ドライバー単独の効果や shader 選択の変化は特定できない。#31323/#32415 は旧ドライバー時点のコードにもある。#32901/#33045 は HIP 側の調査候補で、今回の Vulkan の差を説明する証拠はない。ロード診断で分けた ReadFile・upload・イベント待ちについても、#30685 の推論入力コピーから改善を推定しない。 [計測条件と解釈](automation/ADRENALIN-UPDATE-COMPARISON-20261126.md) · [既存 Global FA 調査](V1-GEMMA4-GLOBALFA-RGP-GATE-20261121.md)

| upstream 方針 | 適合性、工数、判断 |
| --- | --- |
| **b12651 を当面維持** | 同じバイナリ系統の観測と比較しやすい。IQ4_NL の変更と FAST HIP を隔離し、下流と Vulkan の既存結果を比較基準にできる。今回の推奨。 |
| **個別取り込み** | MTP やサーバ運用で再現する問題が生じたとき、#31669＋#32721 や状態復元を独立評価。#31669 は cache・GGML ABI・shader を横断し、#32901＋#33045 は HIP/CUDA FA と CMake が連動するため一行の修正として扱わない。 |
| **新 upstream へ再ベース** | 新モデル、正式 v1.1.0、gdn、BF16 と運用修正をまとめて評価できる。COMMON-001 の `qwen4exp` と loader、ROCmFPx 型特性、Vulkan pipeline/shader と scheduler の衝突、QSA・MTP の品質を再確認する必要があり、検証工数が最大。標準 wrapper の固定ハッシュ・依存監査も再レビュー。#32901 は `ggml_cuda_fattn_instances` へ集約し HIP/CUDA の対応する vec/tile/mma テンプレートの選び方を変える。確認した範囲の Windows SDK/ROCm 依存バージョン引上げは見当たらないが、TheRock 10.0.0 での再ビルド可否は未検証。 |

### 推奨順序と根拠

1. **D — ROCm IQ4_NL GET_ROWS の幅160対応。** 現用 Qwen IQ3 PLE16 の実測済み物理 RAM 逼迫を対象にでき、変更を2つの HIP 共有ソースに絞れる。GPU 配置・数値の確認を先に行う。FAST や Gemma の PP/TG へ直接の効果は見込まない。 [独立ブランチの検証計画](ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md#段階4--実装候補と承認後の検証)
2. **A — ROCmFP4 FAST HIP 対応を段階的に進める。** 主候補は ROCmFPX、補助は strix.cpp。FP3 PLE 配置と FAST 行列演算を小さく分け、まず両方で GPU 正しさとメモリ予算を確認。FAST の両バックエンド対応が成立すれば、量子化フォーマットとバックエンドの違いを分離しやすくなる。実行可能な最大 context と速度は未確認。
3. **B — 既存モデル高速化。** PP は HIP の形状別 PF_GEMM/PF_PAD を最初の独立候補とし、局所計測で寄与の確認された形状に限定。次に Qwen の MoE gate/up と ID ルート。長文 PP/TG は QSA の選択・gather を別テーマにし、top-k の同点順、tail、KV 形式、品質を検証する。Vulkan IQ2_S の A2 は区間が約1.89%短縮したが全体 TG の改善は未確定。#30904 は対象2モデルで IQ3_XXS tensor が0件で現時点の優先度は低い。Gemma は Global512 と SWA256 の既存 FA トレースを分けて扱う。 [IQ2_S 実測](iq2-s-vulkan-matvec-20261125/README.md) · [#30904 の対象型調査](pr30904-preport-20261125/README.md)
4. **C は保留。** 新 upstream への全面移行は、D/A の結果と Qwen MTP、Gemma HIP FA などの個別効果の根拠が揃った時点で比較。DFlash2／suffix／MTP は TG と品質の別評価で、現在の MTP OFF 条件を維持した評価には含めない。

候補間の順位は観測済みの RAM リスク、実装の独立性、GPU 対応モデル拡大、検証規模による。第三者の速度は同条件の代替にせず、改善率を予測していない。次回は [HIP 調査の D0／HIP-1](ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md#段階4--実装候補と承認後の検証) を運用者レビューにかける。未確認の gfx1151 dispatch、実メモリ、品質と数値等価性はそこで検証計画を承認する。今回の作業は調査と資料の記録まで。
