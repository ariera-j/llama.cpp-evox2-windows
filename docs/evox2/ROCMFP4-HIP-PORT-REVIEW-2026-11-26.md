# EVO-X2 ROCmFP4 FAST PLE16 の HIP 移植調査（2026-11-26）

> **2026-11-27 引き継ぎ。** D0（ROCM-002）はhost配置制限を含め製品採用済み。次のROCmFP4 FAST HIP対応は、統合後製品SHA `a650d641ee99198543697e1e3913c593059721f7` を基準にHIP-1から進める。下記の調査SHA・候補表は2026-11-26時点の記録。 [D0採用と検証範囲](B12651-D0-5-HIP-IQ4NL-GETROWS-INTEGRATION-20261127.md)


## 段階3 — 対象、ソース、移植元

2026-11-26 22:11 JST の各 HEAD を固定した。基準は製品 `9ae819d5be4fe9861d2aa8547983aed801c437ac`、upstream b12651。b12696 実ビルド元 `20f48bfe162d8d886b9f5fea7ad6d7df91eb3266` と製品の `src`、`ggml`、`common`、`include`、ルート CMake は一致。COMMON-001、COMMON-003A、VULKAN-001A/B を現行の比較基準とする。再開時は表の固定 SHA と製品 SHA を取得し、`git show SHA:<path>` で型、CPU decoder、HIP decoder、dispatch、配置の順に照合する。 [全体調査](UPSTREAM-OPTIMIZATION-REVIEW-2026-11-26.md) · [Stage 1](B12651-STAGE1-COMMON001-20261124.md) · [Stage 2](B12651-STAGE2-ROCMFP4-VULKAN-20261124.md)

対象 `Qwen3.8-Flash-Next-ROCmFP4-FAST-v2-ple16.gguf` の既存ヘッダー調査は GGUF v3、`qwen4exp`、`general.file_type=103`、1,239 tensors。tensor ID 101 は50件、104 は幅160の16個の PLE head。tensor ID と file_type は別々の列挙値。現行型は 100=FP4、101=FAST、102=FP6、103=FP8、104=FP3、107=Q2。初期対象は 101 と104、およびモデルに必要な既存型の回帰。FP6/8、Q2、量子化 KV、MTP の全面対応は後続候補。 [製品型定義](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/include/ggml.h#L265-L273)

| 移植元 | 固定 SHA、根拠、判断 |
| --- | --- |
| [ROCmFPX/ROCmFPX](https://github.com/ROCmFPX/ROCmFPX/tree/120141f1f9da0a82bb109135c82cd173107fac25) | **主候補**。`120141f1f9da0a82bb109135c82cd173107fac25`（10/17、RDNA4 MMQ fallback #58）。FAST/FP3 の dequant、GET_ROWS 実装、変換、MMQ/MMVQ と RDNA3.5 の tile 設定を確認。FAST GET_ROWS 実装はあるが、同じ版の `supports_op` GET_ROWS 許可リストに FAST がない。製品の tensor 用途に沿ってサポートと実装を合わせる。MIT、NOTICE と THIRD_PARTY_NOTICES あり。 |
| [ArtomYuan/strix.cpp](https://github.com/ArtomYuan/strix.cpp/tree/aa1fa7ad0350b9bedc0c39d1cc0aec0288f72034) | **第二候補**。`aa1fa7ad0350b9bedc0c39d1cc0aec0288f72034`（10/26）。FAST/FP3 の GET_ROWS は許可リストと実装の両方にあり、FAST MMQ、RDNA3.5 MMVQ と ID 向け調整もある。幅160 IQ4_NL は依然拒否。公開 gfx1151 資料は参考。ルート Apache-2.0 と継承された ggml の権利表示をファイル単位で確認してから再利用。 |
| [HarshaVardhan3002/ROCmFPX](https://github.com/HarshaVardhan3002/ROCmFPX/tree/bc1e8cabeab4b34387a155565cab5710742ff1de) | `bc1e8cabeab4b34387a155565cab5710742ff1de`（11/23）。FAST/FP3 の GET_ROWS、変換、vecdot/MMVQ の関連箇所あり。FAST の専用 MMQ は確認した現行 MMQ ファイルに同じ型分岐が見当たらず、主候補にしない。ROCMI4 は別の型・コードブック。MIT。 |
| [walcz-de/llama.cpp-ROCmFP4](https://github.com/walcz-de/llama.cpp-ROCmFP4/tree/e5b4bc020c3f790c77db369588a06525ab8d76bf) | `e5b4bc020c3f790c77db369588a06525ab8d76bf`（9/02）。FAST/FPx 系の行検証、GPU コード、RDNA3.5 の切り分け用。Artom と同一の CPU codec blobs を確認。幅160 IQ4_NL は依然拒否。MIT。 |
| [flyingcrab-design/llama.cpp](https://github.com/flyingcrab-design/llama.cpp/tree/751e8b3b04ea2fc841f1ceccd536acebb0be6cb0) | `751e8b3b04ea2fc841f1ceccd536acebb0be6cb0`（6/14）。100/101 の FAST dequant/GET_ROWS/MMQ や MTP の歴史参照。確認した `ggml.h` は対象 FP3 type 104 を持たず、PLE 対応一式の移植元には不足。MIT。 |
| [agentionai/llama.cpp](https://github.com/agentionai/llama.cpp/tree/dc255f2a4b6e4211b555b0c05260b2523281f314) | `dc255f2a4b6e4211b555b0c05260b2523281f314`（10/07）。製品と 4 個の CPU codec C/header blob が一致。型と CPU 数値の正本照合に適する。確認した `ggml/src/ggml-cuda` に FAST/FP3 の専用 dispatch は見当たらず、同名 HIP ヘルパーだけで対応済みとは判断しない。MIT。 |

r2／r5／r6 では旧枝の CPU 参照、Vulkan の数値ゲートと HIP 移植上の差分が残っている。旧 MMQ の `block_a_to` 周辺の契約変更、テンプレートと tile 選択を現行に合わせる。既存の下流 Vulkan と共通型を最初から置き換える必要はない。 [既存パッチ](PATCHES.md) · [以前の調査履歴](PERFORMANCE-RESEARCH-LOG.md)

### ABI と演算別の確認

| 確認点 | 分かったことと残る作業 |
| --- | --- |
| FAST type 101 | 32要素、16 byte の packed nibble 後に UE4M3 1 byte、17 byte/block。low nibble は先頭16、high は後半。符号付き整数コードブックに half-scale を掛ける。100 は scale が2個あり18 byte/block。MXFP4/NVFP4、ROCMI4 と ABI を共有しない。 |
| FP3 type 104 | 32要素、12 byte の 3-bit ストリーム（8要素を3 byteずつ、4組）と UE4M3 2 byte、14 byte/block。16要素ごとに scale を選ぶ。幅160は5 blocks、量子化 payload 70 byte/row。 |
| CPU 参照の比較 | 主候補・Artom・Harsha の CPU FAST decode、codebook、scale table と、FP3 unpack8、code decode、scale table、row decode の該当関数／配列を空白・コメント除外で現行製品と照合し一致。GPU の `dequantize_rocmfp4_fast` と `dequantize_rocmfpx_fp3` も packing と scale の選択を静的に追った。数値一致は後続テストのゲート。 [FAST/FP3 GPU decoder](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/ggml/src/ggml-cuda/dequantize.cuh#L86-L174) |
| GET_ROWS と配置 | FP3 の generic `get_rows_cuda_q<QK_ROCMFP3,QR_ROCMFP3,...>` と対応判定を組にする。製品では `src/models/qwen4exp.cpp` の split tensor と `src/llama-model-loader.cpp` の代表 op による配置を再利用し、`supports_op` の型・dst・stride、`supports_buft` の device/path 条件、実際の16 head 配置を照合する。FAST がモデル上で GET_ROWS を必要とするかも tensor 用途ごとに確定する。 [主候補の GET_ROWS](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/ggml/src/ggml-cuda/getrows.cu#L473-L493) |
| MUL_MAT／MUL_MAT_ID | 最初は FAST→FP16/F32 変換と既存 BLAS／ID fallback の到達を確認する。dequant と BLAS があるだけでは ID grouping、forward dispatcher、expert offset、strided 行、無選択 expert、非倍数 tail は保証されない。主候補の `convert.cu` と `ggml_cuda_mul_mat_id`、型登録を読み、GPU 実行を確認できるまで広告する形状を狭くする。 |
| MMQ／MMVQ | 主候補は `mmq.cu:443` などの dispatch、`mmq-config-rdna3-5.cuh:305` の FAST tile、`mmvq.cu` の FAST/FP3 と `vecdotq.cuh` の積和を持つ。PP の行列型と TG の少 token 型を分けて移植。gfx1151 の wave32、tile/warp、LDS、Q8_1 の scaling と tail、MUL_MAT_ID の small batch を確認。ROCMI4 W4A4 は別 ABI と別実験。 [MMQ tile](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/ggml/src/ggml-cuda/mmq-config-rdna3-5.cuh#L298-L318) · [MMVQ](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/ggml/src/ggml-cuda/mmvq.cu) |
| Windows ビルド | 現行 TheRock 10.0.0、AMD Clang 23.0.0git、gfx1151 固定。共有 CUDA/HIP ソースの `GGML_USE_HIP`、`GGML_CUDA_CC_IS_RDNA3_5`、コンパイル時 `__gfx1151__`、既存テンプレート収集と `ggml/src/ggml-hip/CMakeLists.txt` を確認。初期は既存 wrapper と runtime DLL 来歴を維持し、専用 fast-path の生成物が必要になった場合だけ CMake を別差分でレビューする。fork の SDK・チューニング値は移植の前提にしない。 |

### 幅160の IQ4_NL とメモリ予算

IQ3 PLE16 の IQ4_NL では、現製品の `supports_op` が `ne[0] % QK_K == 0` を要求し、既存 `get_rows_cuda_kq` も 256 要素単位で反復する。160 は IQ4_NL の32要素ブロック5個からなる正当な行。条件だけ変えるとカーネルの assert または読み出し欠落が残る。整列行の高速経路を維持しながら、非整列行の32要素単位の IQ4_NL 読み出しを別経路にする。FP3 の generic kernel は別の codec と契約なので、FP3 を追加しても IQ4_NL には効かない。最新 upstream と主候補・Artom・Harsha も IQ4_NL のこの条件を維持。 [製品 GET_ROWS](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/src/ggml-cuda/getrows.cu#L194-L219) · [backend の対応判定](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/9ae819d5be4fe9861d2aa8547983aed801c437ac/ggml/src/ggml-cuda/ggml-cuda.cu#L6474-L6510)

既存 ROCm IQ3 PLE16 は約27,466 MiB の CPU モデルバッファを記録。新ドライバーでも 64k のロード最小空き14.117 MiB、1 GiB未満3.303秒、PP中最小3.287 GiBで終了後は回復した。Vulkan FAST のモデルバッファは88,645.69 MiB、独立した CPU モデルバッファなし。96 GiB=98,304 MiB からモデルバッファだけ引くと約9,658 MiBだが、これは HIP の割当可能容量ではない。KV・計算・staging、ドライバー/WDDM、連続性・アロケータの一時ピーク、CPU 物理空きとコミットを別々に記録する。全重みの常駐 F16 展開を前提にせず、fallback の一時変換範囲でもピークを判定する。既存の Vulkan 64k 成功は HIP 64k の収容保証にならない。 [ドライバー比較と低メモリ区間](automation/ADRENALIN-UPDATE-COMPARISON-20261126.md)

## 段階4 — 実装候補と承認後の検証

**最初は D、独立した IQ4_NL GET_ROWS／幅160 の GPU 配置。次に B相当の ROCmFP4 HIP 対応を段階化し、その後に PP/TG 高速化を選ぶ。** IQ4_NL の改修は現在の常用モデルの観測済みの問題を対象にした小規模候補。FP3 を使う FAST の技術的な必須前提ではない。FAST は移植元があるため現実的だが、native MMQ/MMVQ まで含めると中〜大規模。工数は変更面と検証の相対評価で、期間や改善率の見積もりは未確定。

| 段階・相対工数 | 変更候補と再利用 | 将来の確認・停止条件 |
| --- | --- | --- |
| **D0 小** IQ4_NL | 製品 SHA 固定の独立 worktree、例 `experiment/hip-iq4nl-ple160`。主に `ggml-cuda/getrows.cu` と `ggml-cuda.cu` の IQ4_NL 条件のみ。既存 IQ4_NL decoder と 256 整列専用経路を利用し、非整列幅向けカーネルの5 blocks と stride を扱う。 | 32/160/256/非連続 row、重複・先頭・末尾行、dst 型、CPU 比較、許可判定と実行一致。ソースレビュー後に限定数値ゲートと別承認の短い実モデル。16 head 配置、GPU/CPU バッファ、空きRAMを確認。誤差、範囲外、配置未達、割当超過で停止。 |
| **HIP-1 小** 移植範囲 | donor の必要ファイル、FP4/FP3 CPU参照、GGUF型番号、演算別 tensor 用途、対応 predicate、通知・ライセンスを固定する。既存共通/Vulkan ファイルを極力維持。 | ABI・出典不明、競合型、現行ビルドルールに収まらない依存があれば実装に進まない。 |
| **HIP-2 中** 正しさ優先 | `dequantize.cuh`、`convert.cu`、`ggml-cuda.cu` の FAST→F16/F32 と MUL_MAT／MUL_MAT_ID dispatch。既存 BLAS とバッチ化された expert fallback を使い、未対応は従来通り拒否。 | scale境界、奇数側 nibble、K tail、stride、ID並べ替え、空 expert、複数 token を CPU/Vulkan参照で確認。まず小型 tensor のみ。CPU fallback で実モデルへ進めない。 |
| **HIP-3 小〜中** FP3／配置 | 2 と並行開発できる。 `getrows.cu`、`dequantize.cuh`、`supports_op` をセットで扱う。16 head の loader 配置が外れた場合に限り `llama-model-loader.cpp` を見直す。 | FP3 幅160、16要素境界、byte 跨ぎ、stride、batches の比較。配置検証、承認済みの低 context スモーク。予期せぬ CPU 配置や物理 RAM 低下時は長文に進まない。 |
| **HIP-4 中〜大** MMVQ と MMQ | `mmvq.cu`／`vecdotq.cuh` の少 token ルート、次に `mmq.cu/.cuh`／`mmq-config-rdna3-5.cuh` と型の template instances。独立トグルか dispatch trace で一つずつ検証。 | TG と PP の選択ルート、RDNA3.5 wave32、tail、各 expert ID、fallback、非 HIP の既存ソース互換性。許容誤差超過、ドライバーコンパイル問題、GPU 異常時に停止。 |
| **HIP-5 中** 実モデル・回帰 | 対象 FAST と既存 IQ3、Vulkan FAST、Gemma 4 の比較。固定バイナリ来歴、同じ入力／条件／ドライバー、D0 や最適化を混在させない。 | 承認済み短条件→実行後回復・イベント確認→別承認の長文。PP/TG、出力品質、WDDM・RAM・コミット、KV／計算バッファ、MTP OFF を確認。MTP は別レビュー。 |

検証の実行は運用者レビュー後。数値ゲートは CPU 参照と比較し、実機での自動 smoke は CLI 版・デバイス列挙・マニフェスト照合まで。実機 `test-backend-ops.exe` の自動実行に依存せず、限定 GPU 数値検証の方法を別途承認する。WHEA/GPU/資源枯渇、SSH 切断、回復不良、異常終了で停止し、ログを保全する。 [運用ルール](automation/AGENT-RULES.md) · [計測ルール](automation/BENCHMARK-RULES.md)

### ライセンスと未確認事項

主候補の [LICENSE](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/LICENSE) は ggml と ROCmFPX の MIT 表示を含み、[NOTICE](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/NOTICE) に ROCmFPX 由来と Carlo Pasquale / Charlie12345 の帰属、[上流クレジット](https://github.com/ROCmFPX/ROCmFPX/blob/120141f1f9da0a82bb109135c82cd173107fac25/docs/ROCmFPX-UPSTREAM-CREDITS.md) に実装別出典がある。採用するファイルごとに履歴と copyright/permission を残し、再利用範囲を明記する。Artom 由来の追加コードは Apache-2.0 の該当表示と必要な NOTICE を個別に扱う。外部コードやモデルは今回のコミットに含めていない。

未確認は Windows/TheRock 上でのビルド可否、gfx1151 の実選択、GPU 数値とモデル出力の一致、FAST の一時メモリと最大 context、IQ4_NL 配置変更での実 RAM／転送差。調査の再開点は D0 の現行 call graph と小規模ケース表、および HIP-1 の donor の型別照合。上の固定 SHA を再取得してから別実験ブランチでレビューする。
