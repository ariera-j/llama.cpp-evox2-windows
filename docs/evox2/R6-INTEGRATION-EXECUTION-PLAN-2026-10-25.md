# r6 b11870 統合実行計画：パッチ順序・計測ゲート固定版

- **決定日:** 2026-10-25 JST
- **対象ブランチ:** `r6/upstream-refresh-20261025`
- **固定upstream:** `ggml-org/llama.cpp` b11870 / `74bca3950054eed1795f525cb9cf06bfe796492d`
- **初期状態:** b11870 の推論ソース無変更。r5から `tools/evox2/`、`docs/evox2/`、`.gitignore` のみ移管。r6の初回コミット完了。Vulkan/ROCmクリーンビルド・推論検証は未実施。
- **既存の根拠:** [r5パッチ管理表](PATCHES.md)、[r5統合計画](R5-INTEGRATION-PLAN-2026-10-21.md)、[ROCmFPx Vulkan検証](R5-ROCMFPX-VULKAN-PORT-PLAN-2026-10-20.md)、[Stage-B/flatten複合ソース検証](R5-NOOP-ROCMFPX-STAGEB-FLATTEN-INTEGRATION-CHECK-2026-10-21.md)。
- **この文書の位置付け:** r6の初回統合に限り、実行順序、採否、モデル割当、性能計測の回数・タイミングは本書を優先。r5の既存文書・実測値は履歴と移植の根拠として保持する。

## 1. 固定する方針

1. **まず再現可能な初回統合を完成させる。** この作業中にs1、Strata、Halogen、project-maya等の新規高速化は加えない。上流の新しいタグへの乗換えもしない（再現可能な重大不具合を除く）。
2. **移植対象を最初に凍結する。** 下表にないパッチ・診断用C++・計測仮説を途中で足さない。各移植前にb11870上での既存実装と重複を短時間確認し、不要なら「upstreamで充足」とする。
3. **ソースは意味単位で移植。** r5実験ブランチから `ggml-vulkan.cpp` 等を丸ごと置き換えない。新しいQwen4Expのmask/top-k/入力契約とVulkan shader ABIを優先。
4. **正確性→実行経路→速度の順。** 新型式対応と互換性修正を速度パッチとして評価しない。速度差は同一バイナリ・同一入力・opt-in ON/OFFのABBAを優先する。
5. **性能ベンチ中はPerformance P-MODE固定、ADLX/P-MODE/ビルド・モデル・入力の証跡を保存。** 64k・128kは入力トークン数も固定。ROCmはTheRock 10.0統一のDLL/データツリーとロード元を記録。
6. **失敗時は原因を一段だけ切り分けて、採用/保留/除外を記録する。** 当日の勢いで新しい探索項目を増やさず、想定外の事象だけ本書の判断ログを更新する。

## 2. 候補一覧と採用順（この順序を変更しない）

| 優先 / ID | 対象 | b11870での判定・実装方針 | 次段階に進む条件 |
| --- | --- | --- | --- |
| **S0 / BASE** | 素のb11870、ビルド/計測基盤 | VulkanとROCmを独立クリーンビルド。変更のない推論ソースを保存 | version/device、実モデル短文、計測証跡が正常 |
| **S1 / COMMON-001** | オリジナル結合PLEとsplit PLE16ローダ | upstream未実装なら必須移植。**この段階だけIQ3オリジナルとPLE16変換版の両方を計測** | 原版/変換版のロード、同条件出力、32/64k動作 |
| **条件付き / COMMON-005** | ROCm/HIP gathered K/V compact QSA | r3で256k MTP OFFのTG改善実績あり。b11870 HIPでは未充足。**S1後のROCm PLE16 128k実測で必要性を判断する**。旧patchの機械移植はしない | 実行条件を揃えてr5より大幅な長文TG低下が再現した場合のみ追加の移植判断。その他はS8後まで保留 |
| **S2 / COMMON-003A** | ROCmFPx GGML型・GGUFローダ・CPUフォールバック | ROCmFP4モデル利用の前提。不要になった上流部分は除外 | 型/量子化の単体・ロード確認。未対応GPU型をCPUに黙って逃がさない |
| **S2 / VULKAN-001A** | ROCmFPx Vulkan正確性 | 対応する演算・shader・pipelineを意味単位で移植 | 対象型の数値テスト、4k実モデル・GPU配置 |
| **S2 / VULKAN-001B** | 整数dot MMVQ/MMQ・MUL_MAT_ID | `-1` expert indexと`block_a_to_shmem`変更に追従 | 5形式×幅1,3–8×通常/強制MMVQの**140/140**（想定）と64k実モデル |
| **S3 / MTP-COMPAT** | Agention旧`output_hc_*`、ratio-zero unused k-pool guard | まずb11870ネイティブMTPを試す。不足分だけ最小移植。旧COMMON-002全体は戻さない | IQ3および利用可能なROCmFP4 target+Draft短文、全GPU配置、acceptance>0、DraftMax=7幅8 |
| **S4 / VULKAN-002** | grouped-union QSA prefill（f16 KV） | upstream同等機能を先に監査。必要ならopt-inで移植、#30965変更後のmask/selection契約に合わせる | `qsa-union active`を実確認、短文fallback、64/128kの同一バイナリA/B |
| **S5 / MTP-DENSE-001** | ratio-zero Draft indexerを省略 | 独立ON/OFF。MTP互換性と状態検査を通してからTG評価 | 64/128k MTP ON のA/B、状態/acceptance整合 |
| **S5 / MTP-NOOP-001** | Target側のQSA no-op invalidation抑止 | DENSEから独立に無効化可能。native policy/state/rollbackを先に確認 | 64/128kの増分A/B、ROCmFP4+QSA+DENSE+NOOP短文複合smoke |
| **S6 / MTP Stage-B** | Draft KV-only zero-output prefill、Draft FA省略 | 独立opt-in。短文C/A/BのC（OFF）とA（Stage-B ON/flatten OFF）を評価 | 活性グラフのK/V書込みとFA省略、64/128kのPP/TG、rollback正常 |
| **S6 / `mtp_eh_proj` flatten** | Stage-B prefill内の投影flatten | Stage-Bとは独立に無効化可。短文B（Stage-B+flatten）を加え、C/A/B比較 | 短文/rollback、64/128k ABBAで小幅PP差を再確認 |
| **S7 / COMBINED** | 上記で採用したものだけ | flagを個別に切れる状態で統合。有効化設定を別途明記 | 32/64→128→必要な256k、MTP OFF/ON、各backend・モデルで検証 |
| **S8 / FINAL MODELS** | IQ4、huihui、Gemma4 | **完成後にまとめて実測**。b10919のGemma4運用版は維持 | 各モデルのロード/品質/PP/TGを別判定。安定後にリリース化 |

注：ROCmFP4は**モデルの量子化形式**。既存のisolated移植で実証済みなのは主に**Vulkan実行対応**であり、HIP/ROCm backendのROCmFPx GPU kernel移植はS2の範囲外。ROCm backendの性能計測は原則IQ3 PLE16で行い、ROCmFP4をROCm backendで走らせることは別途対応確認できた場合だけ追加する。

### 今回は移植しない

| 区分 | 対象 | 取扱い |
| --- | --- | --- |
| **b11870で充足確認** | COMMON-004（persistent pooled-K）、COMMON-006（block-top-k）、VULKAN-MOE-001 | **移植検討対象外**。Qwen4Expの新しいpool管理・mask契約を維持する |
| upstream差分の確認だけ | HIP/CUDA FA同期 #30103、MTP checkpoint/hidden restore #30141、その他Qwen4Exp変更 | 既に充足のものは移植しない。実不具合があった場合のみ再判定 |
| **改善効果なし・代替あり** | VULKAN-GR-001、r2 MTP-QSA、r2 gather-stride、Target rewarmup #30511、Stage-A単独 | **移植検討対象外**。Stage-AはStage-Bに置換 |
| 診断専用・常時不採用 | RGP/dispatchトレース、Draft KV強制checkpoint、argsort TOPK決定化 | 本番/速度測定ソースには混ぜない |
| **初回統合対象外** | q8_0 KV union、ROCmFPx HIP専用kernel、ROCM-001、ROCM-PP-001、s1/Strata/Halogen/Gufo/project-maya/CONCAT/Expert分布/MASK可視化/RGP深掘り | 完成後の研究キュー。統合の停止理由にしない |
| **条件付き保留** | COMMON-005 ROCm long-context compact QSA | 上記S1後の実測判定を満たす場合だけ独立検討。トリガーなしなら今回移植しない |

## 3. モデルと計測タイミングを固定

### 対象モデル

| モデル | S0 | S1（PLE16前後） | S2以降の各パッチ | S7完成候補 | S8最終 |
| --- | --- | --- | --- | --- | --- |
| **IQ3オリジナル（結合PLE）** | **主要baseline**、Vulkan/ROCm | **変換版との比較のみ** | 原則測らない | 必要な回帰smokeだけ | 常時計測対象外 |
| **IQ3 PLE16変換版** | split未対応ならロード可否のみ | **主要baselineに移行**、Vulkan/ROCm | **最優先：該当backendで64k、性能patchは128kも** | 32/64/128k、選択的256k | 回帰比較の基準 |
| **Agention ROCmFP4-FAST PLE16** | 未対応ならロード可否のみ | 未対応なら速度測定しない | **S2対応後に追加**。Vulkanを主対象。初回64/128k、その後は主要速度patchの64kと段階的128k | 32/64/128k（Vulkan）、必要時256k | 品質と速度を最終記録 |
| **Unsloth IQ4 / huihui IQ4XS PLE16** | なし | なし | なし | なし | 4/16k起動、代表64/128k、固定入力で品質・PP/TG |
| **Gemma4 31B/26B** | **原則なし**。必要な場合のみ短文ロードsmoke | なし | なし | なし | b10919既存版を残して別々にロード・文章・長文・PP/TG |

S0でGemma4の長文速度を取らない。b11870で起動互換性が疑わしい変更が見つかった場合や、S8で不具合が出て原因がupstreamかr6移植か分からない場合に限り、**未改変b11870を使った短い切り分け測定**を追加する。

### 段階別の計測ゲート

| ゲート | 実施する計測 | 実施しないこと |
| --- | --- | --- |
| **G0 / S0 clean** | Vulkan・ROCm IQ3原版：4k smoke、固定64k/128k PP/TG各1run。**2026-10-25合意の例外として256k各1runも実施済み**。ビルド/入力SHA・P-MODE/ADLXを記録 | PLE16の無理な比較、IQ4/huihui/Gemma4長文、256kの反復探索 |
| **G1 / S1 PLE16** | IQ3原版 vs splitを**同一S1バイナリで64k**（Vulkan/ROCm）、変換版128k代表。S0の原版との橋渡しを記録 | S1以降の原版の反復計測 |
| **G2 / S2 ROCmFPx** | まず型・shader backend数値テスト、4k/16kロード、完全GPU配置。ROCmFP4 Vulkan 64/128k代表値 | correctness未達での長文性能主張、HIP向けの新kernel開発 |
| **G3 / S3 MTP互換性** | IQ3 split・ROCmFP4の4k短文target+Draft、32/64k MTP ON、DraftMax=7短距離検証 | 互換性修正自体の高速化率の主張 |
| **G4 / S4 union** | Vulkan IQ3 splitの64/128k MTP OFFでunion OFF/ON。ROCmFP4 Vulkanは64kと128k代表。強制経路が実際に有効か確認 | 全corpus/全KV型/全backend探索 |
| **G5 / S5 DENSE/NOOP** | IQ3 splitのVulkan+ROCm各64/128k MTP ONを個別switchでA/B。ROCmFP4 Vulkanは64k、複合smokeは必須 | DENSEとNOOPを同時導入して差を混同すること |
| **G6 / S6 Stage-B/flatten** | IQ3 split Vulkan 64k→128kで**C/A/B**。ROCmは64kで状態と方向確認、ROCmFP4 Vulkanは64k、128kはS7でまとめて確認 | RGP深掘りを合格条件にすること、合成診断パッチの常時有効化 |
| **G7 / S7 統合** | IQ3 split + ROCmFP4 Vulkanの32/64/128k実入力、MTP OFF/ON、DraftMax=2と短い7、1回の選択的256k安定性確認、MH-128K固定入力の正解基準 | 速度上昇率を各パッチの改善率の足し算で算出 |
| **G8 / S8 完成後** | IQ4/huihui/Gemma4の別建て品質・速度とb10919フォールバック判定 | これらを前段パッチの毎回のベンチ対象に増やすこと |

性能計測の固定入力は、過去の64k（約61,789 tokens）・128k（約126,253 tokens）の既存実文書系を優先し、**入力本文ハッシュ、実token数、n-predict、sampler、KV dtype、FA、MTP Draft/flagsを必ず併記**する。既存 `tools/evox2/benchmark` の計測ログ形式を使い、具体的なPSD1は各ゲート開始前にそのゲート用として固定する。256kは原則として最終候補の安定性ゲート。ただしS0未改変upstreamの基準点を残すためにユーザー合意で一度だけ前倒し計測し、完了した。**S1〜S6では再測しない。**

## 4. 速度採否のルール

- **互換性パッチ（S1–S3）:** 出力正常・モデル/quantのロードとGPU配置・数値正確性を採否基準にする。速度向上の証明を要求しない。明確な速度低下があれば原因メモのみ付け、次の速度patchに混ぜない。
- **速度パッチ（S4–S6）:** まず短文の活性化・安全性テスト。その後**同一バイナリのOFF/ONでABBA（原則A1/B1/B2/A2）**。PPとTGを両方記録する。片方を改善し片方を落とすときは絶対速度だけで採否を決めず、64/128kの用途（PP重視/TG重視）と実行時間で判定。
- **差が概ね3%未満、またはABBA内で方向が揺れる場合:** 暫定判定として追加のABBAを**最大1セット**だけ実施。再現できない場合は「効果未確定・既定OFF」で保留し、無制限に条件を探さない。
- **flattenの事前例外:** r5で観測したPP差は約1.4%なので、3%未満でも連続した2セットのABBAで方向一致、同一設定でTG/品質の悪化がない場合に限り候補として残せる。最終デフォルトONの採否は統合状態S7で確定。
- **Stage-Bの事前注意:** r5では64k改善と128k悪化の実測がある。64kだけの改善を理由に128kで既定ONにしない。128kで再現性のある悪化なら、128k既定OFFまたはパッチ保留とし、新しいPP原因調査をその場で開始しない。
- **ROCmの出力再現性:** 通常 `ggml_top_k` の非決定性を既知条件として扱う。temp=0でも全runのbyte一致は要求しない。正解/破綻/acceptance/状態を比較する。argsort決定化は初回統合に加えない。
- **比較不能run:** P-MODE変更、電源/クロック異常、ROCm DLL不整合、強いGPU idle stall、異なるモデル/入力、明らかなcold-cache大差は性能採否に使わない。原ログは保持して理由を記録する。
- **強制停止:** ビルド/数値失敗、CPU fallback、出力崩壊、MTP状態・rollback不整合、必須経路が実行されない場合、そのパッチの次段階へ進まない。必要なら除外して、独立した他のパッチへ進む。
- **安全:** Windows/gfx1151の広範囲 `FLASH_ATTN_EXT` backendテスト、および `Build-ROCm.ps1 -RunBackendTest` は実行しない。必要な演算/形状に絞ったbackendテストを使う。

## 5. 実行管理：予定外の変更を抑える

各Sの完了時、以下の短い1行を本書末尾の記録表に追記する（ログは別ファイルでも可）。

`Stage | commit/binary | model/backend | test & performance evidence | PASS/DEFER/UPSTREAM/FAIL | next stage`

予定を変更できるのは次の4条件に限る。

1. **事前ゲートの失敗:** 安全性・正確性・GPU配置が成立しない。
2. **upstreamと実際の重複:** パッチの意味が既に充足され、適用不要になった。
3. **モデル/backend固有の技術的制約:** 例：ROCmFP4モデルのHIP非対応、b11870でのDraft互換性問題。IQ3の独立系列は継続可能。
4. **実測に基づく採否変更:** 同じ条件の繰返しで速度効果が出ない／悪化する。不要patchを残さない。

その他の面白そうな変更・別forkの高速化・mask/Expert可視化・RGP詳細追跡は、[統合版完成後の研究計画](R5-POST-INTEGRATION-OPTIMIZATION-PLAN-2026-10-21.md)にメモだけ残し、S8完了まで実装しない。

### Stage実績（初期状態）

| Stage | Source / build | Gate result | Decision | Next |
| --- | --- | --- | --- | --- |
| **S0完了** | b11870推論ソース未変更、b11875/280a639f3・Vulkan/ROCm clean build | 4k smoke各1run＋64/128/256k各backend1runの全8run PASS、P-MODE正常、[S0 baseline](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md) | **PASS**（256kを事前合意で追加） | **S1 COMMON-001 PLE16移植** |
| **S1コード移植** | [COMMON-001実装・計測手順](R6-COMMON001-PLE16-IMPLEMENTATION-2026-10-25.md)、`259a0b95`、独立 `r6/common001-ple16-20261025` | C++ 4ファイル、r5移植差分一致。Windowsのbuild・計測は未実施 | **実装済・実測待ち**（S1 PASS未判定） | Vulkan/ROCm別clean build → 4k×4条件 → 64k×4run → 128k split×2run |
| **S1完了** | b11879 / `73324d6d`、[S1最終結果](R6-COMMON001-PLE16-IMPLEMENTATION-2026-10-25.md#s1完了実測2026-10-25追記) | Vulkan/ROCm build、4k 4run、64k 4run、128k split 2run全PASS。128k ROCm TG 17.55、r6 S0 17.50、r5 clean 17.13 tok/s | **PASS**。COMMON-005追加条件なし、保留継続。256k追加なし | **S2 COMMON-003A → VULKAN-001A/001B ROCmFPx** |
| **S2コード移植** | `r6/rocmfpx-vulkan-20261025`、[S2実装・計測手順](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md) | r5の型/ローダ・Vulkan正確性・整数dot・140幅テストを移植。b11870のMMQ範囲チェック引数に対応し、追加の負expert IDテストを設置。ローカルC/C++構文チェックPASS、Windows build/実測未着手 | **実装済・実測待ち。S2 PASSとはしない** | Vulkan build → 数値テスト140+10件 → 4k/16k smoke → 64k IQ3/ROCmFP4 → 128k ROCmFP4。合格後のみS3へ進行 |
| **S2 Vulkanビルド確認** | b11882 / `70545f998`、`(vulkan-rocmfpx)evox2-build.json`（2026-10-25 18:55 JST） | `BuildIdentity=Verified`、source clean、Clang 20.1.8、Vulkan0 Radeon 8060S認識、`ggml-vulkan.dll`/`test-backend-ops.exe`生成、`llama-cli --version`/`--list-devices`成功 | **ビルドゲートPASS。数値/モデル推論は未判定** | 140+10数値テスト → 4k/16k ROCmFP4 smoke → 64/128k |
| **S2 数値テスト完了** | b11882 / `70545f998`、[結果と条件](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md#evo-x2-numerical-correctness-gate-pass-2026-10-25) | Vulkan0で5形式×幅1/3～8のMUL_MAT・MUL_MAT_ID、normal/強制MMVQ各75件を全実行。追加した`-1` expert ID 10件含め**150/150 PASS**、失敗なし | **数値正確性ゲートPASS。S2全体のPASSは実モデル確認後** | 計画どおりROCmFP4 FAST PLE16の4k/16k smoke → 64k IQ3/ROCmFP4 → 128k ROCmFP4 |
| **S2実モデル短文PASS** | b11882 / `70545f998`、[4k/16k smoke記録](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md#evo-x2-rocmfp4-fast-ple16-actual-model-smoke-pass-2026-10-25) | ROCmFP4 FAST PLE16両ctxで正常終了・`OK`生成、**49/49層Vulkanオフロード**、CPU model bufferなし、P-MODE Performance。各2生成tokenのため速度評価対象外 | **smoke PASS。S2全体は64/128k実測待ち** | 64k IQ3 PLE16 + ROCmFP4 FAST PLE16 → 結果確認 → 128k ROCmFP4 FAST PLE16。順序は固定 |
| **S2 64k実文書PASS** | b11882 / `70545f998`、[64k測定記録](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md#evo-x2-64k-real-document-measurement-pass-2026-10-25) | IQ3 PLE16 **343.56 PP/26.23 TG**、ROCmFP4 FAST PLE16 **351.27 PP/26.28 TG**。両run正常終了・49/49層GPU配置・P-MODE/ADLX整合PASS。IQ3のS1比PP **−0.28%** | **64k PASS。S2全体は128k実測待ち** | 計画固定のROCmFP4 FAST PLE16 Vulkan **128k 1run**。PASS後のみS3へ |
| **S2完了：ROCmFPx Vulkan** | b11882 / `70545f998`、[128k結果とS2総合判定](R6-ROCMFPX-S2-IMPLEMENTATION-2026-10-25.md#evo-x2-128k-rocmfp4-fast-ple16-real-document-gate-pass-2026-10-25) | ROCmFP4 FAST PLE16 128k、126,253入力token、**PP 275.28 / TG 24.19 tok/s**、577 token生成。`Status=OK`、49/49層Vulkan、CPU model bufferなし、P-MODE/ADLX整合。4k/16k/64kと数値150/150も全PASS | **S2総合PASS。新規patch・256k再測なし** | 合格S2ソースから**S3専用ブランチ**。まずnative MTPを確認し、必要な互換性patchだけ移植 |
| **S3 native MTPゲート準備** | `r6/mtp-compat-20261025`、[S3実装・検証手順](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md) | S2 b11882を変更せずに再利用。Unsloth IQ3+Q8_0 Draft、Agention ROCmFP4 FAST+同種Draftについて4k DraftMax 2→7を先に試験し、32/64kは固定matrixで計測。`ratio0 k-pool`／旧HC名はソース上の互換候補で、未確認のうちは移植しない | **S3未判定。まずnative実モデルログ待ち** | 4k×2 DraftMax2→結果確認→4k×2 DraftMax7→32k ON×2→64k ON×2。失敗時だけ最小互換性patchを検討 |
| **S3 native 4k FAIL → 互換性2点の実装** | `r6/mtp-compat-20261025`、[原因ログ・最小source差分](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md#native-4k-runtime-gate--failed-s3-compatibility-only-port-required)。失敗binaryはS2 Vulkan b11882 | Unsloth Q8_0 draftはGPU 50/50後 `GGML_ASSERT(buffer)`、Agention ROCmFP4 draftは `blk.48.nextn.hc_head_norm.weight not found`。r5と同じ2系列を別々に再現。`graph_mtp`比率0 guard＋旧`output_hc_*`3点再利用のみ `src/models/qwen4exp.cpp` に移植。S5高速化patchは未導入 | **互換性実装済・S3未判定（Windows再ビルド/実測待ち）** | S2バイナリを保護して新規`build-vulkan-r6-mtp-compat`、4k×2 DraftMax2再測→7短文→32k ON×2→64k ON×2。新原因がなければ順序変更なし |
| **S3 Vulkan b11889ビルド＋4k DraftMax2 PASS** | `befbc45388`、Windows Clang20.1.8、Vulkan b11889（SHA `42ebf2a69d3c7b22…`）、[ビルド・smoke証跡](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md#patched-s3-vulkan-build-and-4k-draftmax2--pass-2026-10-25-jst) | BuildIdentity Verified、source clean。IQ3＋Q8 draft、ROCmFP4＋FP4 draftの両方 `Status=OK`/exit0、32生成token、main 49/49 + draft 50/50層GPU。Draft accepted **12/36 (33.3%)**、**17/28 (60.7%)**、P-MODE Performance。`--ignore-eos`による継続出力は品質判定対象外 | **4k DraftMax2 PASS。S3全体は未判定** | **順序固定：4k×2 DraftMax7** → ログを確認して **32k ON×2** → **64k ON×2**。未検証patch・256kは追加しない |
| **S3 4k DraftMax7 PASS** | 同じS3 Vulkan b11889 / `befbc4538`、[DraftMax7実測](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md#patched-s3-vulkan-4k-draftmax7--pass-2026-10-25-jst) | Unsloth IQ3+Q8 MTP、Agention FP4+FP4 MTPが両方 `Status=OK`/exit0・32生成・main 49/49 + draft 50/50 GPU。`n_max=7`実行、受理は**15/95（15.79%）／20/71（28.17%）**、P-MODE Performance。短文は速度/品質差、bitwise rollback保証を主張しない | **S3 4k幅7 PASS。S3全体は未判定** | **32k MTP ON×2だけ**を `-OnlyCase 32k -OnlyVariant on` で計測、ログ確認後に64k ON×2。S4高速化patchは未導入 |
| **S3 32k MTP ON×2 PASS** | S3 Vulkan b11889 / `befbc4538`、[32k実文書ログ・判定](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md#patched-s3-vulkan-32k-real-document-mtp-on--pass-2026-10-25-jst) | 2/2完走、各29,557入力＋256生成token、GPU main 49/49 + draft 50/50。IQ3：**PP386.12/TG33.49、受理145/220=65.91%**。FP4：**PP396.92/TG38.05、受理149/212=70.28%**。両run P-MODE PerformanceとADLX高負荷電力約119.5/120.2W一致、正常な日本語要約。MTP OFF不在なので速度効果は未評価 | **32k互換性ゲートPASS。S3全体は64k・ROCm IQ3確認待ち** | **64k ON×2のみ** `-OnlyCase 64k -OnlyVariant on`（事前PlanOnly）、ログ確認で停止。OFF/ON比較・256k・S4早着手はしない |
| **S3 Vulkan 64k MTP ON×2 PASS** | b11889 / `befbc4538`、[64k実文書・比較と判定](R6-MTP-COMPAT-S3-IMPLEMENTATION-2026-10-25.md#patched-s3-vulkan-64k-real-document-mtp-on--pass-2026-10-25-jst) | 2/2完走、各61,789入力＋512生成token、GPU main 49/49 + draft 50/50。IQ3：**PP318.67/TG33.45、受理304/413=73.61%**。FP4：**PP323.37/TG33.29、受理294/433=67.90%**。P-MODE/ADLXは119.5/119.6Wで整合。GPU freeは**22,739/14,060MiB**。S2 OFFとの差はTG約+27%だがバイナリ違いの参考値、PP低下約7～8%、PP+TG合計で~10～11秒増の推算 | **Vulkan S3互換性ゲート完了。S3全体はROCm IQ3確認待ち** | S3ソースで新規ROCm build（-RunBackendTest禁止）→ IQ3+Unsloth MTP 4k DraftMax2 smoke → ログ確認。まだS4/256k/追加A/Bを開始しない |
| **S4 VULKAN-002 ソース準備** | `r6/vulkan-qsa-union-20261025`、S3 `db27fcba` 派生、[upstream監査・実装・計測計画](R6-QSA-UNION-S4-IMPLEMENTATION-2026-10-25.md) | **r6のQSA graphはr5と異なる。** fused `TOP_K_MASK` とVulkanで使われるunfused `CONT` maskの両方をGPU finite-mask compactに渡し、64-query bitmap union / f16 K/V gatherをopt-in実装。`GGML_VK_QSA_UNION`は既定OFF。r6 baselineが既に高速なため効果は仮定しない。 | **コード実装段階。Windows build・active path・A/B未確認でありPASSではない** | 新しいS4 Vulkan build → 4k fallback → 64k ON active+OFF smoke → IQ3 64/128k ABBA → FP4 64/128k A/B。S1–S6の256k禁止を維持 |
| **S4初回Windowsビルド修正** | S4 `ggml-vulkan.cpp` [ビルド不具合記録](R6-QSA-UNION-S4-IMPLEMENTATION-2026-10-25.md#first-windows-build-feedback-and-compile-fix-2026-10-25) | Clang 20.1.8の2件のC++エラーは同じ `const vk_pipeline sparse_compact` に起因。`ggml_pipeline_request_descriptor_sets` と `ggml_vk_dispatch_pipeline` が `vk_pipeline&` を要求するためローカル変数の `const` のみ除去。その他は未変更。 | **コンパイル修正済・再ビルド待ち。S4 PASSではない** | 同じS4 buildディレクトリで再ビルド → 4k fallback・64k活性化の順序を継続 |
| **S4 Vulkan build＋smoke PASS** | b11895 / `7748be523`、[S4ビルド・ゲート証跡](R6-QSA-UNION-S4-IMPLEMENTATION-2026-10-25.md#4-s4-windows-build-and-complete-measurement-results-2026-10-2526-jst) | BuildIdentity Verified／clean、Vulkan0 Radeon 8060S。IQ3 4kで閾値fallback、64k ONで`source=mask-compact`とgroup=64/capacity=32768の活性化、64k OFFで非活性化を確認。64k ON/OFF短文出力SHA一致、各49/49層GPU、P-MODE Performance。 | **ビルド・活性化ゲートPASS** | 64/128kの固定A/Bに進む。計測値は次行 |
| **S4完了：VULKAN-002** | 同じb11895 / `7748be523`、[12run全結果・採否](R6-QSA-UNION-S4-IMPLEMENTATION-2026-10-25.md#gate-4b-fixed-same-binary-64128k-ab-1212-pass) | **12/12 PASS**。IQ3 PLE16は64k PP **344.80→364.41 (+5.69%)**、128k **270.61→330.22 (+22.03%)**。ROCmFP4 FAST PLE16（Vulkan実行）は64k **351.86→373.40 (+6.12%)**、128k **275.22→335.97 (+22.07%)**。TG差は最大約0.3%。両128kではPP+TG計算で約**83–84秒短縮**。全run GPU49/49、P-MODE・ADLX正常、出力破綻なし。 | **S4 PASS、S7候補として保持。union既定OFF。S1–S6の256k禁止を維持** | **S5 MTP-DENSE-001**：r6 upstreamで既存のDraft indexer/ratio-zero条件を先に監査し、必要な差分だけ専用ブランチに移植。続いてMTP-NOOP-001 |
| **S5 MTP-DENSE-001 ソース準備** | `r6/mtp-dense-20261026`、[b11870監査・実装・Windowsゲート](R6-MTP-DENSE-S5-IMPLEMENTATION-2026-10-26.md)、[独立A/B計画](../../tools/evox2/benchmark/configs/qwen38-r6-s5-mtp-dense.psd1) | b11870のhybrid-indexer null安全性は既存だが、ratio0 NextNの自動省略は未実装。r5のfail-closed `LLAMA_MTP_SKIP_DENSE_INDEXER`のみ移植、state/rollbackテストを追加。ローカルLinuxでpolicy実行PASS・C++構文チェックPASS。**Windows build・GPU出力・速度は未計測** | **実装・ゲート準備済、S5採用は未判定**。S4 unionはOFF、NOOP未移植、256k計測なし | 新規S5 Vulkan build（追加test 2件）→ policy → Native model/state/rollback → IQ3/FP4 4k smoke → IQ3 Vulkan 64/128k ABBA → ROCm IQ3 64/128k → FP4 Vulkan 64k。各段階PASSで次へ |
| **S5 Vulkan b11898 PASS / nativeモデルテストABI修正** | b11898 / `45322c042`、[ビルド・ログと修正記録](R6-MTP-DENSE-S5-IMPLEMENTATION-2026-10-26.md#first-windows-feedback-build-pass-old-test-input-abi-stop-test-only-correction) | BuildIdentity Verified・clean、Vulkan0 Radeon8060S、2つのtest EXE生成。`test-mtp-indexer-policy.exe`はユーザー報告PASS。モデルテストのDENSE OFF/ON判定は正しく、`layer=48 ratio=0` の indexer omission をログで確認したが、旧r5テストがMTP hidden **10240次元**をr6のtoken embedding **2560次元**の入力APIに渡してabort。r6の実MTP decoderと同じ `set_embd_state` にテスト1行を修正し、ローカル構文PASS。 | **ビルド/単体policy PASS、Native state/rollbackテスト未完了。S5全体は未判定** | 同じbuildディレクトリで `test-mtp-dense-indexer` ターゲットのみ再ビルドしてstate/rollback再試験。PASS後に4k smoke、次に64k ABBA。 |
| **S5 MTP-DENSE-001 最終ゲートPASS（2026-10-26）** | `r6/mtp-dense-20261026`、[S5全結果と生ログSHA-256](R6-MTP-DENSE-S5-IMPLEMENTATION-2026-10-26.md#5-evo-x2-final-s5-results-and-closure-2026-10-26-jst)。Vulkan b11898、ROCm b11899 | native policy/state/rollback PASS、4k互換性PASS。長文は**18/18完走**：IQ3 Vulkan 64/128k TG **+6.99/+16.32%**、IQ3 ROCm **+9.55/+12.11%**（temp0出力は同一条件の反復でも変動）、FP4 FAST Vulkan 64k **+7.51%**（単一A/B、出力・受理率一致）。PPは全条件で±0.21%以内。各run P-MODE Performance、runtime identity・DENSE実行証跡 Verified | **S5 DENSE PASS、opt-in候補として保持、既定OFF**。ROCmの数値は同一バイナリ観測改善でbitwise同一出力ではない。FP4 2runの統計的限界を保持。256k追加なし | **次はMTP-NOOP-001を独立ゲートで実装**。既存の `S5 / MTP-NOOP-001` 枠を次の専用ブランチ「S6-NOOP」と呼んでも、固定patch順と次段のStage-B/flattenは変更しない。 |
| **S6-NOOP実装・ローカル検証（2026-10-26）** | `r6/mtp-noop-20261026`（S5ソース`7c819cffb`派生）、[実装とゲート手順](R6-MTP-NOOP-S6-IMPLEMENTATION-2026-10-26.md)、[4k smoke](../../tools/evox2/benchmark/configs/qwen38-r6-s6-mtp-noop-smoke.psd1)、[64/128k ABBA](../../tools/evox2/benchmark/configs/qwen38-r6-s6-mtp-noop.psd1) | 固定b11870の`seq_rm`は無操作でもTarget idx staleを付けるため、r5由来のfail-closedポリシーとTargetの実削除なし時だけのstale抑止を追加。DENSEとは独立opt-in、Stage-B/flatten未導入。ローカルpolicy実行PASSと関連3ソースのC++構文PASS | **実装のみ、Windows native/短文/長文未検証、S7採否保留**。S5の元結果は継承して記録、256k禁止を維持 | 新S6 Vulkan build→native state/rollback→4k IQ3/FP4→IQ3 Vulkan 64/128k ABBA→FP4 Vulkan 64k→ROCm 4k/64/128k。DENSE=1、union=0、NOOPだけOFF/ON。|
| **S6-NOOP Windows最終ゲートPASS（2026-10-26）** | `r6/mtp-noop-20261026`、Vulkan/ROCm **b11901**、`722a18926`、[18run全結果とraw archive SHA](R6-MTP-NOOP-S6-IMPLEMENTATION-2026-10-26.md#windows-final-gates-and-s6-noop-closure-2026-10-26-jst) | 両backendのpolicy・real-model state/rollback **524/524 NMSE=0**、4k IQ3/FP4/ROCm互換性PASS、長文**18/18完走**。DENSE=1、QSA union=0固定の独立NOOP A/B。TG: IQ3 Vulkan 64/128k **+3.00/+6.18%**、FP4 FAST Vulkan 64k **+3.01%**（単一pair）、IQ3 ROCm 64/128k **+2.80/+3.00%観測**。Vulkan各条件の出力SHA・受理数一致、ROCmは従来のtemp0非再現性＋受理率差を伴う。全run P-MODE Performance／ADLX正常、PPほぼ不変 | **S6-NOOP PASS、S7統合候補。既定OFF・独立flag保持**。ROCm速度の厳密な因果改善量とFP4の反復再現性は保留し、256k禁止を維持 | 次は元計画の**S6 Stage-B→`mtp_eh_proj` flatten**。両者をC（OFF）／A（Stage-Bのみ）／B（Stage-B＋flatten）で独立評価。機能と性能の採否を混同しない。 |

### 最終統合版のビルド対象（2026-10-25追加）

**S7で統合版候補を固め、S8の最終確認・配布用ビルドを行う際、`llama-tokenize.exe` をVulkan版・ROCm版ともに含める。** それ以前のS2〜S6の途中ビルドでは必須にしない。推論の高速化パッチ採否・計測順は変更しない。

- `tools/tokenize/CMakeLists.txt` に `llama-tokenize` ターゲットが既存。`LLAMA_BUILD_TOOLS=ON` の構成を継続する。
- `Build-Vulkan.ps1` と `Build-ROCm.ps1` は既に `-ExtraTargets` を受け付けるので、最終ビルド時に **`-ExtraTargets llama-tokenize`** を指定する。デフォルトターゲットを途中で変更する必要はない。
- 最終成果物チェックに `llama-tokenize.exe` の存在・ビルドJSON `Build.Targets` への記録・小さな日本語/英語入力のトークン化結果（`--ids` / `--show-count`）を追加する。
- 現行のS2 b11882ビルドには `llama-tokenize` が含まれていないが、S2の不備とはしない。


## 6. 過去パッチの移植漏れ監査（2026-10-25追記）

r1〜r5の採用・却下・実験記録とb11870実装を照合した一覧。**対象外の履歴は削除せずに残す**。本表は上のS0〜S8採否判断の補助であり、速度改善のない過去案を無条件に再試験する指示ではない。

| ID / 系列 | r6判定 | 根拠・条件 |
| --- | --- | --- |
| COMMON-001 | **S1：移植** | split PLE16ローダ。IQ3原版との橋渡しを同一バイナリで実施 |
| COMMON-002（旧一括MTP） | **S3：最小互換性のみ** | まずb11870標準MTPを試す。旧Agention output_hc_*、ratio-zero未使用pool guardで必要な部分のみ |
| COMMON-003A / VULKAN-001A / VULKAN-001B | **S2：移植** | ROCmFPx量子化型・ロード・Vulkan MMQ/MMVQ/MUL_MAT_ID。HIP専用kernelは含めない |
| COMMON-004 | **対象外：upstream実装済み** | qwen4exp.cppとllama-memory-hybrid-idxにpool K scatter/gather、new_pool_rep、dirty/stale状態管理あり |
| **COMMON-005** | **条件付き保留：有効実績あり** | r3では256k ROCm・MTP OFF TGが11.68→17.37 tok/s（約48.7%増）。b11870 HIP sparse FAには同等のcompact gathered K/V経路がない。旧71行patchはrow/selection/mask意味が変わったため直接再適用不可。**S1完了後、PLE16 IQ3のROCm 128k MTP OFFでP-MODE/入力/条件を揃えたr5との比較においてTGが概ね10%以上低下し、原因が再現する場合**だけ別ブランチで互換・数値正確性を調査する。それ以外はS8後まで保留。必要時の256kは代表1runだけ |
| COMMON-006 | **対象外：upstream実装済み** | b11870はblock-domainでggml_top_kし、pool IDとtailを選択。二重移植しない |
| VULKAN-002 | **S4：候補** | f16 QSA grouped-union、同等upstream機能の監査後にopt-in判定 |
| MTP-DENSE-001 / MTP-NOOP-001 | **S5：候補** | 各独立スイッチ・64/128k ABBAで効果確認 |
| Stage-B / mtp_eh_proj flatten | **S6：候補** | Stage-Bとflatten独立採否。微差flattenは初期既定OFF |
| VULKAN-MOE-001 | **対象外：upstream充足** | upstream #29936相当を確認 |
| VULKAN-GR-001（GET_ROWS 128×4） | **対象外：速度改善なし** | 既往A/Bで改善を確認できなかった |
| r2 MTP-QSA / gather-stride | **対象外：速度改善なし** | 既往実験のPP/速度に効果なし |
| Target rewarmup #30511 | **対象外：速度改善なし** | 64k ABBAでPP改善なし |
| Stage-A単独FA/FFN skip | **対象外：後継案に置換** | S6のStage-Bを評価 |
| r1 upstream backport 13件、FA同期 #30103、MTP hidden restore #30141 | **原則対象外：上流充足** | 実バグが出た場合だけ不足箇所を確認 |
| q8_0 KV union / ROCm QSA試作 / TOPK argsort決定化 | **初回対象外** | f16中心の本計画外、または速度/品質不確実 |
| **TOOL-001 native llama-bench 実文書入力対応** | **S0後の計測ツール候補** | r5のnative llama-bench.cppには -f / --prompt-file、--prompt-slice head|head-tail、-c / --ctx-size があるがb11870にはない。r6にコピーしたMeasure-LlamaBench.ps1はそれらを使うため、**移植・互換性確認まで実文書のllama-bench実行を禁止**。S0はllama-cli、標準ランダムllama-benchは可 |
| **DIAG-001 QSA union CSV統計** | **S4任意・速度測定OFF** | GGML_VK_QSA_UNION_STATS=1は診断時のみ。既存ログで経路活性化を確認できない場合だけ移植 |
| RGP/dispatch trace、KV強制checkpoint | **初回対象外：診断専用** | コードへの常駐を避け外部ログ・旧レポートのみ保持 |

参照資料：R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md、R5-VULKAN002-UNION-STATS-IMPLEMENTATION-2026-10-09.md。判定変更時は旧判定を消さず、理由と実測runを追記する。

## 7. S0クリーンビルドとbaseline実行の前提（2026-10-25追記）

- r6ディレクトリは C:\llama-build\llama.cpp-evox2-windows-r6。r5 worktreeは固定のまま変更しない。
- 最新ドキュメントをpullした後、upstreamの固定SHA 74bca3950054eed1795f525cb9cf06bfe796492d とr6 HEADとの差分を推論ソース（src,ggml,common,include,tools/llama-bench）で確認し、**推論ソース差分ゼロ**のままS0を始める。
- tools/evox2/build/Build-Vulkan.ps1 のBuildDirを build-vulkan-r6-clean、Build-ROCm.ps1を build-rocm-r6-clean に**明示指定**して、新規configure・Release build・manifest・version/devices smokeを実行する。共有依存cacheの再利用は可。
- ROCmはTheRock 10.0 SDK/実行時DLLを統一し、gfx1151、実際のMSVCバージョンをmanifestで検査。**-RunBackendTestは使わない**（WindowsでFLASH_ATTN_EXT網羅テストのwatchdogリスク）。
- **計測前の4k短文**はIQ3原版・MTP OFFで両backend確認。計測マトリックス tools/evox2/benchmark/configs/qwen38-clean.psd1 はMTP OFF、f16 KV、-b 2048、-ub 1024、-tb 4、n-predict 1024、temp 0.2、top-p 0.8、ctx-checkpoints 0t、P-MODE/ADLX収集向け。
- ローカル固有モデル/文書/binパスはGit管理外の tools/evox2/benchmark/configs/local.psd1 に記載。ひな形 local.clean.example.psd1 を参照。BuildKeysは CleanVulkan と CleanROCm、モデルキーは UnslothOriginal。
- **baseline順：** 64k Vulkan → 64k ROCm → 128k Vulkan → 128k ROCm、各代表1run。Invoke-BenchmarkMatrix.ps1 の -OnlyCase と -OnlyBuild でrunを1つずつ選択。先に -PlanOnly で展開を確認し、256kを初期baselineに混ぜない。
- P-MODE Performance、前後のGPU clock/温度、入力SHA/実token数、モデル版、build manifestを保存。異常時は次のlong-context runへ進む前に原因判断する。

## 8. S0完了時の実測ゲート記録（2026-10-25）

[S0 clean upstream検証・r5 clean比較の詳細](R6-CLEAN-BASELINE-VALIDATION-2026-10-25.md)を正本とする。Vulkan/ROCmともIQ3 Originalの4k smoke、64k/128k/256k計測が正常完走した。r6 b11875はb11870推論ソースから変更なし。

- Vulkan PP：64k **339.72**、128k **268.60**、256k **228.89 tok/s**。r5 clean比 **+26.2% / +49.6% / +69.0%**。
- ROCm PP：64k **405.24**、128k **303.66**、256k **200.59 tok/s**。r5 clean比 **+3.7% / +3.7% / +3.6%**。
- Vulkan TG：**25.42 / 23.54 / 20.30**、ROCm TG：**21.86 / 17.50 / 12.55 tok/s**（64/128/256k順）。
- **P-MODE Performance固定・ADLXの電力判定もPerformance-like**、警告なし。Vulkanはfused top-k mask無効警告、ROCmはfused有効。性能原因は未特定。
- 256kは計画変更の1回限りの例外。**今後はS1のPLE16 64k原版/変換版＋128k変換版に集中し、新しい256k反復は行わない。** COMMON-005はS1後の条件付き判断に据え置く。
