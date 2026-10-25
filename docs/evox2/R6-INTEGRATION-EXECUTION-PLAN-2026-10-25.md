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
