# ROCmFP4 FAST PLE16 Windows HIP 実装案（HIP-2B、2026-11-28）

**READY FOR REVIEW**。判定対象は未コミットのソース、fixture、限定ハーネス。実機のPython参照10件が通過した。Windowsコンパイル、HIP数値、実モデル配置、性能および製品採用は後続ゲート。

## 基準と実機の状態

|項目|確認値|
|---|---|
|リポジトリ|ariera-j/llama.cpp-evox2-windows、実機 C:/llama-build/automation/llama.cpp-evox2-windows|
|製品・実験HEAD|a650d641ee99198543697e1e3913c593059721f7。製品 codex/vulkan-manifest-cpu-variants-20261124 の追跡先も同一。upstream b12651|
|文書|GitHub main と fetch 後の origin/main は 244ec7a97d5206e897786481b4b34cedf3173521。旧追跡値 105e03dc78de7994ce71e3263349111db5bb65db。固定treeの必須13文書、製品のAGENTS.mdとcode-reviewを参照|
|実験|開始時は製品branchでclean。ローカル・GitHubで同名branchが存在しないことを確認し、製品から codex/b12651-rocmfp4-hip2-20261128 を作成。追跡先なし、作業後は下表の未ステージ差分|
|回帰比較|ROCM-002 b12709、実ビルド元 e199e5f4319731071199d84f4f2e571fcaa7d413。既存の旧IQ3 64/128/256k・Gemma 32kの4 runは過去の比較基準|
|ツール|今回の実機照合はGit 2.55.0.windows.5、CPU参照は既設 C:/Python314/python.exe 3.14.9。製品tree上の Invoke-CodexBuild.ps1 の最終変更 04ac2e4b7973140cb912c12c18a8654c68411786、Build-ROCm.ps1 は eb45c5c04129f4f5fe520b677eaf231c8a59c006。今回使用した数値fixtureは実験差分|

運用文書6パスを比較した結果、EVOX2-ENVIRONMENT.md（+9）とKNOWN-ISSUES.md（+35）が同期候補。専用cloneの外、C:/llama-build/automation/hip2a-JdozU6sm-operations.patch に保存し、git apply --check を確認した。適用は文書専用レビュー・承認待ち。ソースにmainをmergeしていない。

## 変更ファイルと理由

|ファイル|追加行|関数・目的|
|---|---:|---|
|ggml/src/ggml-cuda/common.cuh|7|ggml_hip_rocmfp4_fast_device。登録と実行で同じgfx1151・単一device条件を使う|
|ggml/src/ggml-cuda/dequantize.cuh|24|dequantize_rocmfp4_fast と rocmfp4_fast_value。製品の17 byte ABIを静的assert、byte読取り、符号付きゼロ|
|ggml/src/ggml-cuda/convert.cu|28|ggml_get_to_fp32_cuda / fp16_cuda および両NC版で既存テンプレートを実体化|
|ggml/src/ggml-cuda/ggml-cuda.cu|273（削除2）|rocmfp4_fast_span/storage/supported、通常・ID dispatch、needs_sync、融合除外、テスト構成のみSGEMMカウンタ|
|ggml/src/ggml-hip/CMakeLists.txt|5|Windows限定の明示指定 GGML_HIP_ROCMFP4_TEST でテスト用entryとカウンタをHIP DLLに組み込む。非公開converterを実際のDLL内で呼ぶため|
|tools/evox2/hip2a/cases.inc|11|ケースID・演算・shape・strideの共通表|
|tools/evox2/hip2a/fixtures.py|276|GPU非依存の列挙・生成・CPU照合と、別承認用の単一ケースdriver|
|tools/evox2/hip2a/harness.cpp|232|限定converter、実backendの支持照会、graph実行とSGEMM回数の検査|
|本報告書|202|手順、静的根拠、結果と停止条件|

実装・検証用8ファイルは +856/−2。既存追跡5件は +337/−2、検証用新規3件は +519。未追跡の報告書と検証用ファイルは通常の git diff --stat に現れない。

## 支持判定と実行

|項目|受理条件と拒否境界|
|---|---|
|デバイスと重み|Windows HIP、列挙1 device、ROCm0、正確な gfx1151。対象はtype 101。実割当時はrootとviewの整合、同一deviceの通常buft、rootの先頭から実buffer終端まで、view起点と最終byteを検証。ROCm_Host、CPU、他device、splitを拒否|
|予約照会|未割当shapeと、正しいbuftの0 byte dummyを許容。実行時は実data・実bufferが必須。FAST重みのcompute buffer viewは拒否。通常device重みの17 byte単位の非ゼロoffset viewは受理|
|通常|重み [K,M]、入力 [K,N]、出力 [M,N]。正の寸法、Kは32の倍数、nb0=17。行strideは17の倍数でpayload以上。M=1の不要なrow paddingは拒否|
|ID|重み [K,M,E,1]、入力 [K,B,T,1]、I32 ID [S,T,1,1]、出力 [M,S,T,1]、S%B=0。expert strideは17の倍数で最終行末端以上。IDのslotは4 bytes、token pitchは4の倍数かつ4S以上|
|activation・dst|F32。singleton軸を含むstrideをpacked値に限定。実入力は範囲検証済みのdeviceまたはhost、実出力は通常deviceまたはiGPUのROCm_Hostを受理。schedulerの実グラフ、hostからのstagingと配置は後続で観測する|
|上限|各軸を正のint32内とし、K×M、U=T×S、U×K、U×M、leading dimensionを制限。ID gather/scatterのgrid.x×256はuint32内。spanは各stride×歩数を加算前に検査。rootとbufferの残長は減算して比較|
|精度|src1精度指定はUNDEFINEDのみ。accはUNDEFINED/F32。明示compute環境設定はauto/f32/fp32（大文字小文字を無視）のみ。BF16 converter、汎用CPY、量子化dotの追加なし|

対象モデルの通常重みは output_hc_down.weight / output_hc_up.weight（10240×320、320×10240）。ID重みは blk.0〜47.ffn_down_exps.weight（640×2560×512）。判定は演算・型・メタデータに基づく。実行時にtensor名を照合する実装ではない。

### 独立レビューへの対応

- **High 1**。外側の型・shape確認とchecked spanから、IDのコピー長は (T−1)×nb[1]+4S。ggml_nbytes(ids) がこの値を返すことを製品実装と照合した。親領域内かつ実buffer内を確認後、device IDはD2H後に同期し、host IDはstream同期後に同じspanをホスト上でコピーし、token/slot strideで走査する。支持照会はID値を読まない。
- **High 2**。通常は ggml_cuda_mul_mat の先頭から ggml_cuda_mul_mat_cublas_impl<GGML_TYPE_F32> を直接呼ぶ。FWHT、compute paddingによる汎用BLAS早期return、MMVF/MMVQ/MMQ/MMFより前で確定。F32 traitsの連続/NC変換に続き、2D条件で cublasSgemm に到達する。
- **High 3**。IDは同じ外側predicateで全expertの実spanを確認後、少token・few-rowを含む高速分岐を飛ばす。D2H/H2Dの同期とneeds_sync=trueがgraph capture除外に対応。非空expertのdataは元viewの実data+i×nb[2]、shape [K,M,1,1]。sorted入出力は現在位置と実poolのactual_sizeで残長を確認し、同じF32 BLAS実装を直接呼ぶ。そこでは明示tensor引数のdata/shape/strideを使い、内部dstのsrcや仮のbufferから実アドレスを復元しない。逆scatterは元のtoken/slot順。
- groupingは重複slotを保持し、空expertを飛ばす。製品の公開MUL_MAT_ID契約で -1 はslot無効を表すため、FASTでは未使用のsorted出力1行をゼロにし、該当slotの逆indexをその行に向ける。fixture生成時に -1 と有効範囲以外のactive IDを拒否する。余白は演算対象外。
- **Medium 1**。FP3 GET_ROWSの重複書込みはHIP-3に引き継ぐ。ケース3/4と幅288の拒否確認、初版幅32/160の方針を維持する。
- **Medium 2**。下位nibbleはj、上位はj+16。有限scaleはCPU式のまま、127〜255はscaleを0とし、code 8は+0、9〜15はscale=0なら−0。F16は最終変換1回。decoderの入力バイト検査とGGUF validatorの受理条件は別。一般GEMMは後述の絶対誤差で評価する。

製品CPU codecの型定義と数値仕様から実装した。外部donorのソース・ヘッダー・データ表は転記していない。製品の ciru-ai / charlie12345 の帰属および既存LICENSEを維持した。

## 限定ケースとCPU参照結果

直接backendでの候補は**10件**。原計画のHIP-2の7 IDに、converter登録2種と全slot無効の9-Zを加えた。各行の主対象演算は1件。MMグラフは重みview 1件、IDグラフは重み・ID view各1件も含み、native側でノード数と実体を照合する。

|ID|主対象・shape|期待SGEMM数|検査点|
|---|---|---:|---|
|1|連続 F32、K32×256行|0|全256 scale×16 code、両nibble、8192出力|
|1-NC|NC F32、K32×256行|0|各行17 byte padding、1とbitwise一致|
|2|NC F16、K160×256行|0|5 blocks、行間17 byte、全scale/code、40960出力、RNE|
|2-C|連続 F16、K160×256行|0|2とbitwise一致|
|5|MUL_MAT K32/M3/N1|1|one-hot。CPU結果は −0.5、−0.28125、0 の3要素|
|6|MUL_MAT K160/M5/N7|1|非ゼロ起点、行間17 byte、相殺、NC変換、35出力|
|7|MUL_MAT_ID K32/M3/E4/T1/S2/B1|2|ID [3,1]、空expert、少token、6出力|
|8|同 K160/M5/E4/T3/S2/B2|2|親pitch 512 I32、span 4104 bytes、余白 −99、[2,0],[0,2],[2,2]、30出力|
|9|同 K640/M7/E3/T5/S2/B1|3|重み起点34 bytes、行stride357、expert stride2550、末尾expert、broadcast、−1 slot、70出力|
|9-Z|9と同じK640/M7/E3/T5/S2/B1・stride・offset|0|全10 active IDが−1、全70出力を+0のbit列で検査|

converter4件は全て入力前後のguard、packing順、出力前後32 bytesを検査する設計。NCのstrideは17 byte block単位。既存kernelの i00>=ne00 分岐が末尾を保護する。直接converterは製品CPU rowの各出力bitとも比較する。標準Pythonの参照はF32をlittle-endian binary32、F16をbinary16 RNEでpackする。FASTの有限値はbinary32で厳密に表せる。

実機で fixtures.py enumerate と reference をPython隔離モードで実行し、ともに終了0。referenceは製品CPUソースの有限scale表とcodebookから4096組を照合した。独立の整数単位で生成した期待bit列、符号付きゼロ、および全IDケースの直接参照とgrouping後のscatterが一致。ID spanの境界は正例1・負例10が通過。C/C++の製品CPU関数および実supports_opの呼出しは未実行。

|CPU参照|SHA-256（出力bit列。GEMMはFP64参照）|
|---|---|
|1 / 1-NC|d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a|
|2 / 2-C|637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f|
|5|0978449fc6f46e694dcffa7841034c6a4d85da13766c20b55e37446f32597cbd|
|6|f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1|
|7|d3ab1c4678f9604738fc286adbe9ee181a9e0bd56f6a55e4fa8616f28d933c1e|
|8|3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb|
|9|9203115b655f0305deaad40823cf2920d8e33e3c2d6ef9ad9d45001ff9146414|
|9-Z|738c079dff6c9b77a0891ac42db1cabcab933a672b14aed8ecfcf94c0e77bb40|

GPU判定候補はF32/F16 decoderのbitwise一致、one-hotの厳密一致。一般GEMMはdecoded重みとF32入力からFP64直接内積を取り、各要素で有限かつ絶対誤差が A=2Ku/(1−Ku)×Sabs+1e−7 以下。u=2^-24、Sabs=Σ|w×x|。相対誤差と条件数は診断に限る。HIP変換ヘッダーでは cublasSetMathMode は成功を返すマクロになっており、API名だけでは内部積精度を確定できない。使用DLL・rocBLAS設定と内部精度の根拠を確認し、実行前に合否条件を固定する。

## メモリ予算

U=T×S。単一streamでgrouping中に同時生存するdevice要求量は、非空expertの変換4KM、sorted入力4KU、sorted出力4MU、双方向index 8U bytes。−1用のゼロ行は確保済みsorted出力に収める。実モデルのexpert変換は1個6.25 MiB、HCは各12.5 MiB。全512個に相当する3200 MiBの変換は行わない。

hostの主な要求量はID原本 (T−1)×nb[1]+4S、連結indexの予約8U、逆index 4U、expert counts 4E bytes。vector管理と容量余裕、runtimeの転送stagingは別。例としてケース9は変換17920、sorted 25880、device index 80、host主領域204 bytes。これらはBLAS・poolを除く論理値。

HIP 7以降の該当構成で既定workspaceは生成された各device/streamのBLAS handleあたり32 MiB。legacy poolは既存大きめブロックの再利用または要求の約1.05倍を256 byte単位へ丸めて確保する。VMM poolはアドレス空間を予約し、実マップをgranularity単位で拡張する。変換のスコープ終了後もpool予約・高水位が残る。実stream/handle数、pool実装と保持量、model/KV/compute、staging、ドライバーの追加領域は実測項目。UMA 96 GiBの容量判断は物理空き、commit/limit、WDDM budget・dedicated/shared、pagingの同時刻系列を必要とする。

## 静的自己レビューと引き継ぎ

- 既存型のIDコピーは従来と同じD2Hとstream同期。製品CPU/Vulkan、一般CPY・BF16登録、loader候補順、汎用supports_buft、ROCM-002のIQ4_NL GET_ROWSとhost制限の差分は空。Windows HIPの既存型が通るgroupingは従来の分岐を保つ。CUDA/MUSA等のコンパイル回帰は未測定。
- 既存BLASの連続/NC分岐、F32 SGEMM条件、IDの同期箇所、graph capture判定、融合選択、内部sliceのdata参照を固定SHAから追跡。git diff --checkは終了0。native負例はK31/159、stride、root・末尾expert範囲、I64 ID、F16 dst、精度、compute view、CPU/ROCm_Host dummy等を実predicateに照会する設計。別deviceとsplitは単一通常buftのidentity条件を静的に確認した。
- 次は差分レビュー、commitとpushの個別承認。ビルド承認後に固定した完全SHA、cleanな専用worktree、短い未使用build先、offline preflight、既存のTheRock 10.0.0 / gfx1151 / VS2022 x64を使う。CLI・manifest・DLL・rocBLAS/Tensileデータとソースを照合する。ハーネスを含む構成は GGML_HIP_ROCMFP4_TEST=ON とDLLのhashを明記し、標準構成と区別する。
- Hydrogen Mediumの数値検証はビルド後に別承認。dry enumerationでID・op・shape・件数を照合し、1プロセス1ケース、直列1 worker、ROCm0のみ、外部監督60秒上限。driverは明示DLLと完全一致IDを要求し、DLL内でopと全shapeも照合する。行列ケースは指定backendで1 graphを直接実行し、F32 SGEMM回数まで検査する。CPU fallback、skip、余分な主演算、非有限、bit/guard/閾値不一致、ビルド・DLL来歴不一致で停止する。
- 開始前のP-MODE、OS起動時刻、イベントカーソル、PID、物理空き16 GiB以上、commit/WDDM余裕を記録。各回のstdout/stderr、開始・終了・PID、資源と回復を記録し、終了後の物理空き16 GiB、commitとDedicatedの各4 GiB以内の回復、残留なしを確認。timeout、SSH切断、GPU/WHEA等の新規重大イベント、監査不能、回復不良なら後続を送らずログを保全する。
- 残存リスクはWindowsでのコンパイル・export・DLLロード、実機での符号付きゼロとF16変換、BLAS内部精度、実router viewと最適化後graph、実配置と資源高水位。限定数値の通過後もFP3・実モデル・性能・ROCM-002回帰はそれぞれの段階で検証する。

## HIP-2B 独立レビューの追跡結果

開始前に2Aのレビュー入力 changes-final.patch（SHA-256 383e2def77f5b0c6de5c52f17b6d29301912051970e258928b806c2705ebf698、+846/−0）と実機9 blobを照合した。

### High 1　予約、割当、実行

|段階|製品基準での根拠と2Bでの扱い|
|---|---|
|HC 2 tensor|src/models/qwen4exp.cpp:587 の最終build_hc_mixは結合重み引数がnull。371以降でRMSNorm・乗算・reshapeしたxnをdownに渡し、scale・SiLU後のloをupに渡す。各build_lora_mmの基底が通常MUL_MAT。graph構築時の型・shapeだけではこれらの生成ノードの最終buftは決まらない|
|48層のexpert down|qwen4exp.cpp:319,1241の各層down_expsはbuild_moe_ffnへ渡る。src/llama-graph.cpp:2440付近の通常routerはargsort top-k view、2666付近でFFN中間activationとIDをbuild_lora_mm_idに渡す。cache slot置換なしの1890付近の経路で元IDを保持。random routing・cache・precision policy等の異なる設定は個別照合が必要|
|loaderと予約|loaderの0 byte weight dummyでの代表op照会の後、ggml_backend_sched_reserve/ reserve_sizeもsplit_graphを呼ぶ。ggml-backend.cpp:1315–1415では既存dst/view、次いでWEIGHTSのbuftを使ってbackendを探し、入力置換前のopでsupports_opを呼ぶ。2Aはここで実CPU/pinned入力を拒否し得た|
|割当|1465–1497のbuffer_supportedはrootの実buft、未割当なら割当予定backendのbuftを見る。1630–1745のpass 3は支持可否と対応入力数、pass 4はview親を考慮する。weightがdeviceでも最終割当の保証にはならない|
|split|1791–1828のコピー条件はbackendが異なり、かつ入力buftが非対応の場合。ggml_dup_tensor_layoutは全nbを保持する。通常CPUからの置換先はdevice。iGPUのsupports_buftはROCm_Hostを支持するため、その入力を残せる。pinned確保失敗時にはCPU buftに戻る場合もある|
|実行|2Bではx/IDのhost格納を照会時と実行時に同じspan条件で許す。重みのdevice限定は維持。host F32 activationのみ必要長をH2D、pinned dstならdevice一時出力からD2H。実device bufferを持つ一時記述子にshape/strideを保存し、view起点を転送先の先頭に設定。同一streamを同期してから解放する。host IDは同期後、元view先頭から正確なspanをmemcpyし、既存stride付きgroupingへ渡す|
|captureと容量|FAST通常・IDをcaptureから除外し、host stagingの動的確保・同期をcaptureしない。stagingを要する場合の追加device要求は入力ggml_nbytes(x)と出力ggml_nbytes(dst)の該当分。ID用の追加deviceコピーは不要。通常deviceだけの経路は従来のF32呼出しを使う|

汎用scheduler、汎用supports_buft、ROCM-002は製品基準どおり。実モデルのreserve/allocで選ばれるbackend、最適化後のIDレイアウト、pinned割当成功・失敗、stream順序とピークは未測定。既存の直接ハーネスはこの割当を試験しない。

**scheduler専用の後続提案（基本10件の外、3件）**。各1プロセスでROCm0とCPUをschedulerに登録し、device重みを固定。reserveと実allocのnode backend、親/viewのbuft、置換前後のdata/nb、SGEMM回数、CPU参照と一致する出力を記録する。主対象ノードは各1件、合計MUL_MAT 2件・MUL_MAT_ID 1件。viewと転送は個別に数える。

- S-HC-CPU はケース6の通常CPU入力からdevice入力へのsplitコピー、SGEMM 1回。
- S-HC-PIN は同shapeのROCm_Host入力・事前確保pinned出力で入力のコピー省略とFAST内のH2D/D2H、SGEMM 1回。
- S-ID-PIN はケース8のROCm_Host親（512 I32 pitch）を持つtop-k ID view、device activation、2 expertのSGEMM。IDがdeviceへ置換される場合はコピー省略側の証明にならない。要求したbuft、ノード割当、件数が食い違えば停止する。

### Medium 1　ケース6の相殺

Nの先頭2列だけ入力を変更した。出力行0の重みの列1と9は +0.25、−0.25。入力組 (1,1) で厳密な相殺、(1+2^-23,1) で2^-25の残差が生じる。その他5列は従来の一般入力。以下はCPUの全35出力で、NとMは0起点。Aは一般GEMMの従来式、κ=Sabs/|ref| は診断値。

|N|M|FP64 ref|Sabs|A|κ|
|---:|---:|---:|---:|---:|---:|
|0|0|0|0.5|9.636834114400048e-06|inf|
|0|1|0|1.125|2.155787675740011e-05|inf|
|0|2|0|1.875|3.586312792900018e-05|inf|
|0|3|0|2.75|5.255258762920026e-05|inf|
|0|4|0|4.5|8.593150702960044e-05|inf|
|1|0|2.980232238769531e-08|0.5000000298023224|9.636834682839658e-06|16777217|
|1|1|6.705522537231445e-08|1.125000067055225|2.155787803638923e-05|16777217|
|1|2|1.117587089538574e-07|1.875000111758709|3.586313006064872e-05|16777217|
|1|3|1.639127731323242e-07|2.750000163912773|5.255259075561812e-05|16777217|
|1|4|2.682209014892578e-07|4.500000268220901|8.593151214555692e-05|16777217|
|2|0|12.53125050268136|253.1706751605961|0.004828993463274533|20.20314533704551|
|2|1|11.23557671159506|268.9230788489804|0.0051294495850329|23.93495997152092|
|2|2|-6.766827510436997|305.1033680846449|0.005819540418335992|45.08809595250663|
|2|3|-4.298077166080475|319.5432712938637|0.006094962341404617|74.34563386056264|
|2|4|10.81249958858825|344.6778870800044|0.006574371663967828|31.87772487351445|
|3|0|5.629807824734598|248.0336551093496|0.004731011647132363|44.05721524269659|
|3|1|6.49519242788665|257.2980783425737|0.004907718182214066|39.6136190265715|
|3|2|-3.490384834818542|293.1250017704442|0.005591069033335894|83.98071148096859|
|3|3|-7.365384900709614|299.2644248732831|0.005708170352715674|40.63119971428114|
|3|4|2.447115092072636|358.2740410654806|0.006833700194274477|146.4066983306587|
|4|0|-6.91826917976141|243.2451941072941|0.004639678130652607|35.1598337368658|
|4|1|10.05048117227852|279.622598648537|0.00533352867589712|27.8218120959023|
|4|2|8.221153922844678|296.4134634048678|0.005653792059534027|36.05497065092086|
|4|3|-4.576922874199226|322.7644252825994|0.006156401563899639|70.51996158861863|
|4|4|-6.75480797374621|336.4567327159457|0.006417564093170019|49.80996262568025|
|5|0|-9.846154184779152|235.5288473654073|0.004492499092959476|23.92089773787045|
|5|1|-0.4759616022929549|269.4615399288014|0.005139720013023527|566.1413412986778|
|5|2|2.574519136687741|275.3725975386333|0.005252465564754785|106.9607887603101|
|5|3|-7.156250193482265|330.0216366222594|0.006294823205258599|46.11655932919099|
|5|4|-10.17067345860414|333.5312522810418|0.006361764449944816|32.79342844292012|
|6|0|-9.149038715288043|255.0000021993183|0.004863885440293091|27.87178086515398|
|6|1|-7.725961493328214|272.6153862960637|0.005199875432277294|35.28562581259068|
|6|2|3.899038394447416|299.2259635981172|0.005707436755113503|76.74352835925959|
|6|3|5.740384996403009|314.2740403437056|0.005994458778440377|54.74790289164112|
|6|4|-5.151441496098414|340.9927905185614|0.00650408335476377|66.19366458433463|

### Medium 2・3　全skipとnative事前検査

9の混在IDでは無効slotの7要素、9-Zでは全70要素に+0のbitwise判定を適用する。出力tensorを0xa5で初期化し、書き忘れを検出する。全skipでは先頭未使用行zero_row=0、全expert count=0、逆indexは全て0。期待SGEMM数は0。catalogの正規化レコードSHA-256は 0f5c1cf6b166d57f6c8ed16bc85c3ef6d8a88f10837c09d55655dfd577c6feea。

native entryはGPU情報取得より前に完全一致ID、op、geometry、入力・出力byte数、必須ポインタを確認する。IDはpitchでactive slotだけを読み、範囲・slot順の期待値・異なる非負expert数とcatalog回数を照合する。計数器の初期値も確認し、実行後は観測SGEMM数を照合する。DLLロード自体は将来の実行工程に含む。

### テスト用ビルドの指定と識別（後続承認用）

製品の外側Invoke-CodexBuild.ps1は追加CMake引数を公開せず、Worker:152–154がUI無効・offlineの3項目を固定する。内側Build-ROCm.ps1:32,246は文字列配列ExtraCMakeArgsをconfigureに渡せる。運用で外側ラッパーを必須にする場合の提案は、限定switchで下記のBOOL指定だけをworkerへ転送し、Cacheの値を照合すること。共通ツール差分は今回のパッチに含めていない。

内側を使う場合のコマンド案は、利用許可を受け、固定SHA、未使用build先、外側offline preflight、同じVS2022 x64/TheRock環境と依存キャッシュを確認した後のもの。$params はWorkerと同じ BuildDir、DependencyCacheRoot、Parallel=4、RocmPath/RocmBin/RocmCmakePath、ExpectedRocmSdkVersion=10.0.0、AmdGpuTarget=gfx1151 を指す。

```powershell
$options = @('-DLLAMA_BUILD_UI=OFF','-DLLAMA_USE_PREBUILT_UI=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON','-DGGML_HIP_ROCMFP4_TEST:BOOL=ON')
& .\tools\evox2\build\Build-ROCm.ps1 @params -ConfigureOnly -ExtraCMakeArgs $options
# Verify the cache and provenance before the separately approved build step.
& .\tools\evox2\build\Build-ROCm.ps1 @params -BuildOnly
```

通常版とテスト版は別の未使用build先を指定する。通常版はtest指定なしまたはOFF。テスト版はCacheのBOOL=ON、ggml-hip targetのdefineとharness.cppのコンパイル、Release DLLのPE export evox2_hip2a_case、SHA-256を確認する。通常版は同exportが存在しないことを確認する。両版のソースSHAが同じでもDLLの識別にSHA単独のソース表記は使えない。

Build-ROCm.ps1の同梱対象は amdhip64_7.dll、rocm_kpack.dll、amd_comgr.dll、hipblas.dll、rocblas.dll、rocsolver.dll、libhipblaslt.dll、origami.dll と rocblas/hipblaslt のデータツリー。ggml-hip.dll、ggml-base.dll、推移依存および実際にロードするDLLは各ビルドのPE・manifest・hashで照合する。テスト版Releaseディレクトリを明示し、Python driverがそのディレクトリをDLL検索に加える。限定実行例は下記の1ケースのみ。60秒上限と回復監査は外部監督が担う。

```powershell
C:\Python314\python.exe -I -B tools/evox2/hip2a/fixtures.py enumerate --case 9-Z
C:\Python314\python.exe -I -B tools/evox2/hip2a/fixtures.py gpu --case 9-Z --dll C:\path\to\build-test\bin\Release\ggml-hip.dll
```
