# ROCmFP4 FAST PLE16 HIP 段階検証計画

ソース・文書 SHA と対象 tensor は [HIP-1設計書](B12651-ROCMFP4-HIP1-DESIGN-20261128.md) に従う。ここに記す全実行は将来の個別作業。既存 b12709 回帰結果を再利用する。

## 順序と通過条件

1. 製品 a650d641ee99198543697e1e3913c593059721f7 の専用worktreeで、型番号/size/offset、decoder、convert戻り値、実行と許可条件、同期・融合、許可外の経路を相互レビューする。HIP-2と3は独立にレビュー可。型登録だけでは通過しない。
2. 別承認後に標準worktreeラッパーで完全SHA指定、offline preflight、標準ビルド。manifest、実ソース、ROCm DLL、rocBLAS/Tensile gfx1151、CLI版・デバイス・ドライバーを照合する。ビルド異常や来歴不一致で停止。
3. CPU単独で下表のfixture、参照row、F16丸め、ID順・拒否ケースを確定する。全scale 256値×全codeを列挙し、無効scaleのdecoder値とGGUF validatorの受理を別々に記録。
4. 個別承認後、専用の限定数値ハーネスで下表の正例9ケースを各1回。ケースIDを完全一致で指定し、1プロセス1ケース・1 worker・ROCm0限定。各回60秒上限。dry enumerationで件数・op・shapeが一致するまでGPUを起動しない。ケース欠落/skip/余分なop/予期せぬCPU dispatchで停止。test-backend-ops.exe の自動実行、-RunBackendTestは禁止。ドライバー更新を障害解消の根拠にしない。
5. HIP-2と3の数値通過後、既存headerで事前予算を作成。承認済み配置確認で16 headの名前、型、ne/nb、実格納buft・device、HCと48 expertの配置、ロードピークを保存。容量・配置を証明できなければスモークに進まない。
6. 個別承認の短文脈（例4k、MTP off）で固定入力・seed、同一サンプリングと生成長、停止理由、出力妥当性を確認。BLASとgroupingのtrace、異常値、意図しない転送を検査。正しさ優先経路に速度目標は課さない。
7. HIP-4 は少token MMVQ、次にPP MMQ、最後に各ID経路を独立に有効化。同じfixture・参照とBLAS経路で比較。小型でもtraceが別経路なら未検証。配置予算で6が不可能なら6を保留し、7の小型検証→予算再評価→6に戻る。
8. HIP-5 で短文脈通過後、32k→64k→128k→256k。段階ごとに前回実測と次のKV/compute増分、pool・host/WDDM両方の余裕を提示し、承認1件につき1条件。必要余裕を説明できない条件は保留。

## 小型fixture

|ID|1回の限定演算|検査点|
|---|---|---|
|1|FAST→F32、幅32×複数行|先頭から qs[j]=((15-j)<<4) OR j、全nibble、各行scale 00/01/07/08/38/7e/7f/80/ff。0x38の倍率は0.5。|
|2|同じpacked内容→F16、幅160、5 blocks、行末17 byte padding|低位/高位、最後のblock、paddingの毒値を出力しない。|
|3|FP3 GET_ROWS、幅32、4行|8 code 0..7 をLSB-firstに詰めた 88 c6 fa（hex）を4組。前半と後半に異なるscale。index [3,0,3]。|
|4|FP3 GET_ROWS、幅160、3行、stride 73|異なるblock/row値、offset付きview、index [0,2,2]。15→16、byte跨ぎ、最終byteを検査。|
|5|FAST MUL_MAT、K32/M3/N1|one-hot入力、符号とゼロ、正確な位置。|
|6|FAST MUL_MAT、K160/M5/N7|非256尾部、行間17 byte padding、正負交互と相殺。NC許可の前提。|
|7|FAST MUL_MAT_ID、K32/M3/E4/T1/S2|ID [3,1]、空expert、各expertに別の既知値。|
|8|同ID、K160/M5/E4/T3/S2、B=2|tokenごとに [2,0],[0,2],[2,2]、expert 1/3 は未使用。逆scatterと重複slotの出力。|
|9|同ID、K640/M7/E3/T5/S2、B=1|入力行broadcast、非均等group、末尾expert/最終token、padding付きexpert stride。|

CPU側のみの負例はK=31/159、weight.nb0不一致、FAST row strideが17の倍数でない、転置、F16 dstのGET_ROWS、I64 ID、異device/split/ROCm_Host/通常CPUとhostを親に持つview、gridまたはint積超過。支持判定false、kernel起動0を要求。範囲外index/IDはfixture事前検証で拒否。未確保の代表opと候補dummyで配置可能性を別途評価する。

F32 decode/GET_ROWSはCPU rowの全要素とbitwise比較、F16はCPU F32から一回だけround-to-nearest-evenした16bit列と一致。各blockの入力・周辺guard・行順を確認。GEMMは同一decoded重みとF32 activationのFP64直接内積を参照、IDはtoken/slotごとに指定expertを直接引く。小整数one-hotは完全一致。一般のF32累積は各出力で Sabs=Σ|w×x|、u=2^-24、暫定絶対上限 2Ku/(1−Ku)×Sabs+1e−7。相対誤差は |ref|>1e−6 の値で記録し、条件数 Sabs/|ref| を乗じた同じ上限を相対化する。near-zeroは絶対誤差で評価。乗算・加算の丸め回数からの保守値であり、内部積精度とBLAS math modeを確認して実行前に固定する。NaN/Inf・参照の並べ違いは即停止。F16積和やQ8_1直接dotには同じ閾値を流用せず、丸めた入力・activation量子化を含む独立参照を先に用意する。

## 実機監督・回帰

[固定運用文書](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/105e03dc78de7994ce71e3263349111db5bb65db/docs/evox2/automation) とD0-2Cに準拠。事前にPerformance、対象PIDなし、物理空き16 GiB以上、commit余裕とWDDM budget、OS起動時刻・イベントカーソル・実行物hashを記録。開始/終了UTC、PIDと開始時刻、argv、case別数値と経路、stdout/stderr、exit code、2秒周期のRAM/commit/WDDM、プロセス、System/ApplicationとWHEA・Displayを保存。正常終了0、全件各1回、同一OS、残留なし、物理空き16 GiB以上、commit/WDDM Dedicatedの開始比各4 GiB以内の回復を要求。異常終了・timeout・WHEA・GPUエラー・SSH切断・資源枯渇・回復不良では次のケースを送らない。健全なOSで同じ開始時刻の対象子だけ停止。自動再試行、再接続、TDR変更なし。

実モデルは標準計測ルールで監視。ロード前後250ms RAM詳細、通常2秒監視、ピークと低空き継続時間、paging、commit/limit、WDDM dedicated/shared、model/KV/compute/staging別MiB、終了後回復を個別判定する。前段の最大実測に次段増分と未計測余裕を加え、物理空き、commit、WDDMのどれかが運用下限を満たせない場合は停止。短文脈の成功から長文脈の容量を外挿して合格にしない。

|比較|合格の判断|
|---|---|
|FAST HIP と FAST Vulkan|同じモデルhash・入力・context・batch/ubatch・生成条件でPP/TGを別計測。品質は固定入力の出力、反復・破損、可能なら初手logitsと差異発生位置を評価。backend横断の速度比目標は未設定。|
|HIP-4 とHIP-2/3|数値と配置通過を前提に、同一条件で対象フェーズの速度差が反復ばらつきを越えること。他フェーズの低下・ピーク増は別記して採否レビュー。|
|旧IQ3 PLE16 64/128/256k、Gemma Q4_0 QAT 32k|b12709のPP/TG基準は順に408.18/21.76、302.65/17.45、199.03/12.53、186.30/9.03 tok/s。各々5%超低下で停止。応答、全層配置、個別buffer容量、資源回復・終了監査も別に合格が必要。共通コードに影響した場合は既存Vulkanも比較。|

[元の4 runと全バッファ表](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/105e03dc78de7994ce71e3263349111db5bb65db/docs/evox2/B12651-ROCM002-FINAL-REGRESSION-20261128.md)。対応完了後に batch=2048固定でubatch=1024/2048、常用llama-server、必要時エージェント設定を比較。COMMON-005再移植、Sparse FAは独立実験。Hydrogenの4 run最終評価追記は後続の文書管理作業。
