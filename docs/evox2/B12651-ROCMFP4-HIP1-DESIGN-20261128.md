# ROCmFP4 FAST PLE16 Windows HIP 移植設計

文書基準 [105e03dc](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/105e03dc78de7994ce71e3263349111db5bb65db/docs/evox2)、ソース基準 [a650d641](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/a650d641ee99198543697e1e3913c593059721f7)。以下の製品パスは全てこのソース基準。b12709 の実ビルド元は e199e5f4319731071199d84f4f2e571fcaa7d413。ROCM-002 最終4 runを比較基準として保持する。

## モデルと初期対応範囲

[ヘッダー全件 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/105e03dc78de7994ce71e3263349111db5bb65db/docs/evox2/pr30904-preport-20261125/tensors.csv) の FAST 行で確認。GGUF v3、qwen4exp、1,239 tensors。general.file_type=103 はファイル分類、下表の ID は tensor codec。既存共通型・CPU codec・Vulkan 実装は再利用する。新設 HIP 経路は次の3群に限定。

|重み|型・shape (K先頭)|用途と必要な経路|段階と配置|
|---|---|---|---|
|output_hc_down / up.weight|101、10240×320 / 320×10240|出力 HC 投影、MUL_MAT|2、device BLAS|
|blk.0〜47.ffn_down_exps.weight|101、640×2560×512|選択 expert の down 投影、MUL_MAT_ID|2、device、expert 単位|
|ple_ngram_embd.0〜15.weight|104、160×20000003〜20000171（各行数は CSV）|ngram index による GET_ROWS|3、16個すべて device|

以上で101全50件、104全16件を説明できる。対象グラフに FAST lookup、FP3 matmul を追加する根拠はない。ほかの既存型は既存 dispatch に従う。FP6/8、Q2、量子化KV、MTP、ROCMI4 は対象外。予期せぬホスト配置をモデル成功に数えない。

旧製品 9ae819d5be4fe9861d2aa8547983aed801c437ac は製品基準の祖先。ggml/src/common/include 対象の比較で共有 HIP の dequantize.cuh、getrows.cu、ggml-cuda.cu の3ファイル（+58/-19）のみ。D0 が IQ4_NL 非256幅と host制限を追加。GitHub compare は文書mainと製品を diverged、merge base 74bca3950054eed1795f525cb9cf06bfe796492d と報告。製品ブランチ HEAD と製品基準は同一。グラフ根拠は src/models/qwen4exp.cpp の hc_head_down/up（190, 588）、build_moe_ffn（1241）、split PLE の ggml_get_rows（1444）。

## データ契約と出典

製品 ggml/include/ggml.h と ggml/src/ggml.c の type traits を維持。ggml/rocmfp4/rocmfp4.h と ggml/rocmfpx/rocmfpx.h の byte 配列構造体を HIP TU に限定して include。host と device 両方で sizeof/alignof と offsetof(e) を静的検査（FAST 17/1/16、FP3 14/1/12）。大きい型へのポインタキャストで未整列アクセスしない。32要素単位。両型とも製品 row decoder が使う倍率は byte b、E=b>>3、m=b&7 に対し、b>126 は0、E=0 は m/1024、それ以外は (8+m)×2^(E−11)。通常の unsigned FP8 変換や追加の1/2倍率は使わない。無効scaleを持つモデルの受理可否は既存validatorに従う。

- FAST は j=0..15 について qs[j] の下位4bitを出力j、上位4bitをj+16に展開。符号bit 3、絶対値 [0,1,2,3,4,6,8,10] に倍率を乗算。両ゼロコードは整数0。dual-scale type 100、MXFP4、NVFP4、ROCMI4との型別名は禁止。
- FP3 は4組の24bit little-endian streamから (word >> (3×(j%8))) & 7。符号bit 2、絶対値 [0,1,2,4]、scaleは e[j/16]。幅160で5 blocks、70 byte。末尾から scale や次の行へ読み越さない。CPU正本は rocmfp4_dequantize_row_q4_0_fast と rocmfpx_dequantize_row_fp3。Vulkan の dequant_rocmfp4_fast.comp と dequant_rocmfpx_fp3.comp も同じ nibble/bit位置に書く。F32積は有限の小整数×2の冪で正確。F16は最後に最近接偶数丸め。

|固定donor|ファイル・関数|判断・帰属|
|---|---|---|
|[ROCmFPX 120141f1f9da0a82bb109135c82cd173107fac25](https://github.com/ROCmFPX/ROCmFPX/tree/120141f1f9da0a82bb109135c82cd173107fac25)|ggml/src/ggml-cuda/dequantize.cuh の dequantize_rocmfp4_fast、dequantize_rocmfpx_fp3 と bounded bit reader、ggml/rocmfp4/rocmfp4_hip_scale.cuh の有限scale/code helper|必要部分のみ適応。FAST の非LUT分岐には上限検査がないため製品CPUの明示ガードを使用。|
|同上|convert.cu の dequantize_row_rocmfp4_fast_hip、getrows.cu の get_rows_cuda_q の型分岐、ggml-cuda.cu の許可表|登録位置のみ参考。256単位の専用変換を取り込まず、製品テンプレートを実体化。donorのFAST GET_ROWS caseに対し同じ版の GET_ROWS supports_op にFASTがない。両方とも対象外。|
|同上|mmvq.cu、mmq.cu、vecdotq.cuh、mmq-config-rdna3-5.cuh|HIP-4用参考のみ。|
|ArtomYuan/strix.cpp aa1fa7ad0350b9bedc0c39d1cc0aec0288f72034|ggml-cuda/getrows.cu、ggml-cuda.cu の実行・許可分岐|照合のみ。ルートApache-2.0、ggml継承表示あり。追加コピーは個別権利・NOTICE照合まで保留。|
|agentionai/llama.cpp dc255f2a4b6e4211b555b0c05260b2523281f314|rocmfp4.c/h、rocmfpx.c/h の row codec|11/26記録の4 blob一致、MIT。製品の既存コードを使用。|

実装時は donor の LICENSE の The ggml authors (2023–2026)、Carlo Pasquale (Charlie12345), ROCmFPX additions (2025–2026) と MIT permission 全文、NOTICE の creator/contributors 表示、関係する THIRD_PARTY_NOTICES.md、各ファイルの元の表示を配布物に保持。docs/ROCmFPX-UPSTREAM-CREDITS.md の DFlash、DSA、TurboQuant 等の機能を混入させない。製品側の ciru-ai/charlie12345 来歴も保持。新規直接コピーはHIP-1にはない。

## HIP-2 実装順序と拒否条件

1. ggml/src/ggml-cuda/dequantize.cuh に HIP 限定で byte decoder を追加。既存の ggml_cuda_ue4m3_to_fp32 はアーキテクチャ別の例外値処理が異なる。上の全バイト仕様で単体検査する。現行 HIP に 101 の matmul 登録はない。
2. 同ディレクトリの convert.cu で ggml_get_to_fp16_cuda / ggml_get_to_fp32_cuda に dequantize_block_cont_cuda<32,2,decoder>、対応する _nc_cuda に dequantize_block_cuda<32,2,decoder> を返す。NC の s01/s02/s03 は byte ではなく17 byte block単位。k%32==0 で末尾の余分なスレッドは既存 i00>=ne00 判定。最後の32要素だけでも成立させる。BF16変換、一般CPYの許可は追加しない。
3. ggml-cuda.cu の ggml_cuda_mul_mat に FAST 専用の BLAS 分岐を量子化 vector/tile 選択より前に置く。初版の演算は ggml_cuda_mul_mat_cublas_impl<F32> に固定する案を採用。既存 ggml_cuda_mul_mat_cublas は prefer_fp32_acc や環境変数から BF16 を選び、未登録変換に到達し得る。F16変換単体は検証し、F16 GEMM は精度指定・累積・一時出力を検証後に追加する。設定で明示的に別計算型を要求する場合は対応外。既存精度制限を取り除かない。
4. ggml_cuda_mul_mat_id の FAST は先頭の MMVQ、few-row MMQ、MMQ、MMF を全て飛ばして既存 grouping に入れる。ggml_cuda_mul_mat_id_needs_sync も FAST で true、graph capture 除外と一致させる。融合選択（ggml_cuda_should_fuse_mul_mat_vec_q 等）も FAST を対象外。ID転送・同期後、expert順で各token/slotを走査し、src行は token×ne11+slot%ne11。重複を保持し、空expertを飛ばす。重みの先頭は base+expert×nb[2]、ne[2]=1 の view、個別 ggml_cuda_mul_mat が上記BLASへ到達する。逆順表で元のtoken/slotへ戻す。範囲外IDは GPU 起動前にデータ作成側で拒否、実値は supports_op から参照しない。
5. 実行分岐と同一差分で ggml_backend_cuda_device_supports_op を追加。初版対象は HIP/gfx1151、単一device、非split、正の寸法、K%32==0、weight.nb0=17、activation/dst F32連続、K一致、通常は2D（上位軸1）。IDは [K,M,E,1]、入力 [K,B,T,1]、I32連続 [S,T,1,1]、S%B==0、出力 [M,S,T,1]。重みの行間paddingは17の倍数で payload 以上、expert stride は行領域以上かつ17の倍数、viewは正しいblock先頭と割当内。NCケースを通すまで連続だけを許可。T×S、行番号、grid、BLASのint次元・leading dimension、各積と最終offsetをchecked演算で上限判定。範囲外はfalse。root weight が既に割当済みなら同じdevice buftを必須とする。未割当の抽象グラフはshape評価を許し、実行時のdevice割当を確認する。loader dummy に実データや割当容量を要求しない。CPU側に再配置可能でも、実モデル試験は意図しないfallbackで停止。

## HIP-3 PLE配置

ggml_cuda_op_get_rows → get_rows_cuda → ggml_cuda_get_rows_switch_src0_type → get_rows_cuda_q<32,1,dequantize_rocmfpx_fp3> → k_get_rows。QR=1 は隣接2要素。ggml_backend_cuda_device_supports_op の FP3 分岐は I32 index、F32 dst、基本形 [K,R] と1次元index（上位軸1）、K>0かつ32整列、src.nb0=14、nb1>=14K/32。行アドレスは index×nb1 byte で計算するため行末 padding は14の倍数を要求しない。ビューは格納元とoffset、最終row末端の有効性を確認。転置・行内間引き・型の異なるdstは拒否。index/dstは各4 byte整列、連続、indexは [0,R)、grid.x×block.x<2^32 とint範囲を事前確認。多次元batchは別ゲート。

weight_buft_supported（src/llama-model-loader.cpp:1032）は候補の0 byte dummyを重みに付けて代表opを照会する。GET_ROWSならI32 512件。src/models/qwen4exp.cpp はsplit headごとにcreate_tensorを呼ぶ。既存順序で全16個のdevice候補を選ぶ設計。ggml_backend_cuda_device_supports_buft は UMA で ROCm_Host も許可する汎用関数であり変更しない。FP3重みは各約1.3 GiB。候補が既知なら view_src の実格納元をたどり、同一deviceの通常device buftだけ許可。ROCm_Host、通常CPU、別device、splitをGPU lookupの重みには許可しない。FASTにも同じdevice条件を課す理由は expert slice とBLASがdevice割当を前提とするため。入力IDや一時stagingまで一律にhost禁止とはしない。loader 変更は保留。各head名と実buftを記録し、集計だけでは判定しない。候補順または代表opの誤対応を特定した場合のみ再設計。IQ4_NL の256整列・非整列両分岐は維持。

## 容量とWindowsビルド

W=K×M、U=T×S、n=最大の選択expert token数。逐次同一streamでF32変換を使用すると1 expertの変換は4W=6.25 MiB（F16なら3.125 MiB）。全512 expert一括なら3200 MiBで設計外。HC重み1個はF32 12.5 MiB。ID grouping 中はdeviceで重み変換に加えて4U(K+M)+8U bytesのsorted入出力と両方向index、hostにID原本、逆順表、連結表、E個のcountが生存。F32入力・出力で既存BLASを直接使う。将来F16なら入力変換2Knと一時出力最大2Mn等を加算。スコープ終了はプールのOSへの返却を意味しない。複数stream、BLAS workspace、allocator予約/丸め・高水位を別計上し、同時実行数が不明なら1個分を全体上限にしない。現行512 MiB chunk分割は入力F16/BF16用でFASTには適用されない。

Vulkanの量子化モデル88,645.69 MiBを96 GiBから引いた9,658.31 MiBは参考差分。HIPでモデル・KV・compute・recurrent state・上記一時領域・upload staging/pinnedとpool予約の同時ピークを記録。WDDM dedicated/shared・budgetとhost物理空き・commit/limit・pagingを別系列で突合し、同じUMA割当を加算し直さない。短文脈でも余裕を示せない場合、モデル試験を保留し、小型で検証済みのHIP-4直接dotで変換・sortingピークが削減できると見積もった場合のみ先行する。モデルとKV自体が収まらない条件は直接dotでも進めない。

ggml/src/ggml-hip/CMakeLists.txt:60–86 は共有.cuを収集し GGML_USE_HIP を定義、mmq等は template-instances のglob。新規TU不要、既存HIP TUからテンプレート参照。TheRock 10.0.0 / gfx1151 / Wave32 / AMD Clang 23.0.0git / VS2022 MSVC 14.44。共通host側をHIP intrinsicに依存させない。RDNA3_5 判定は gfx1150 も含むため実行対象を厳密に識別、__gfx1151__ はdeviceコンパイル用でhost側のsupports判定に使わない。CUDA/MUSAにcaseを出さずCPU/Vulkan登録は既存のまま。専用SDK、donor CMake やコンパイルオプション追加は不要。

## 判定と引き継ぎ

**CONDITIONAL GO**。製品への採用判定は未実施。HIP-2実装を decoder → 変換 → 通常BLAS → 同期付きID → predicateの順に開始できる。自己レビューでBF16自動選択、ID少tokenの早期MMVQ、graph capture同期、NC strideの単位、host dummyの誤許可を設計に反映。Windowsコンパイル・精度・実配置・メモリ余裕は実測ゲート。HIP-2開始時に運用文書を実機cloneへ所定の方法で同期する。

HIP-4 は型ごとのMMVQ vecdotとQ8_1 の scale（入力側倍率・和補正を二重適用しない）→通常/ID少token → MMQ型dispatchとtemplate instanceの順。gfx1151のwave32、tileとLDS上限、edge K/M/N、expert offset、融合とgraph captureを個別検証。HIP-2のBLASを比較経路に残す。既存型のPP/TGに変更を混在させない。

### 同一GGUF内の既存型

CSVの残りはQ4_K 96、Q6_K 520、Q8_0 144、F32 388、BF16 24、F16 1。Q4_K routed expert 2560×640×512 は既存MUL_MAT_ID、shared expert のQ6_K 2560×640とQ8_0 640×2560は通常投影、attention projection のQ6_Kは層種別で幅が異なる。F32 router（2560×512）とベクトル、BF16/F16を含む残りの個々のruntime placementは未実測。全件の名前・shapeは上記CSVに固定し、実モデルで既存演算のdispatchも記録する。
