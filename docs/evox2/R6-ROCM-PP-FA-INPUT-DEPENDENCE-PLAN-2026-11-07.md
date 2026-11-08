# r6 ROCm/HIP 64k PP入力依存性 — Vulkan比較からの引継ぎ計画（2026-11-07）

**STATUS（元計画時点）: 調査計画・ソースレビューのみ。以降に実測が完了したため、2026-11-08追記を参照。**

> **2026-11-08 追記：HIP FAの同一KV/Layer GPU時間比較が完了（16k/32k/48k、Layer19/23）。** 本文の「未実行」「Gate案」「Next action」は当初の2026-11-07時点の履歴。確定した値・制約・次の小規模KV_max診断については末尾「2026-11-08 実測結果」を優先して参照。

## 研究上の問い

同じQwen3.8 Flash Next Unsloth IQ3_XXS PLE16モデルで、なぜVulkanのPPはコードが文学より約8%速い一方、r6 ROCmでは約1.5%しか差がなく、むしろ文学が少し速いのか？ 最優先は**同じ入力・Kv位置におけるHIP Flash AttentionのGPU時間、mask処理経路、他の重いカーネル**を調べること。

Vulkanで既に分かったこと（[実験総括](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/runs/2026-11-07-vulkan-pp-input-dependence-consolidated-ja.md)）：
- KV49152 / N1024 / Qcur-19、全mask 16×64タイル：コードMIXED12,200/ALL_ZERO92 = 有効12,292、文学MIXED31,638/ALL_ZERO2 = 有効31,640、**2.574倍**。
- 対応するF16セルとIndexerのscore/top-kから元のmaskを再構成し**114,688要素PASS**。同じ64 Queryにおける直近約8k Key選択はコード93.933%・文学54.578%。
- Vulkan RGPの同一KV・layer19、shader `flash_attn_f32_f16_aligned_cm1` ではFA MAIN **44.830msコード、133.210ms文学**（文学2.971倍）。Qcur-23 MAINも65.195msコード、149.954ms文学（2.30倍）。
- Wavefront occupancyはMAIN中の比較的低く一定な帯が両コーパスで観察される。タイルスキップだけの因果分離やPP全体に対する寄与率は未測定。

## 現行HIPコードの事前確認（調査ブランチ）

- `ggml/src/ggml-cuda/fattn.cu`：HIPではCUDA用sparse index compaction関数が `GGML_ABORT`、`ggml_cuda_flash_attn_ext_mma_f16_shall_use_sparse` が**false**。したがってCUDA-only compact sparse MMAは使用しない。
- `ggml/src/ggml-cuda/fattn-common.cuh`：別の**mask末尾スキャン** `flash_attn_mask_to_KV_max<ncols1>` は条件 `!use_sparse && mask && K%stride==0 && (Q>=1024 || multiple sequences)` で有効。これはVulkanの**内部ALL_NEG_INF 16×64タイルを個別skip**する方式とは違う。よって「HIPはmaskを全く使わない」も誤り。
- `src/models/qwen4exp.cpp`：`QWEN4EXP_QSA_GATHER` は独立した選択K/V gather方式。最初の測定は明示的に**OFF**。COMMON-005などのON/OFF比較と混ぜない。
- **既存r5 HIP RGP** [R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md](R5-ROCM-HIP-FA-SOURCE-TRACE-2026-10-11.md)：過去の1組ではテンプレート `flash_attn_ext_f16<256,256,16,4,false,false,false>` のFA MAINが文学104.911ms、コード111.198ms（コード約+6%）、直前の `flash_attn_mask_to_KV_max<16>` が文学46.914us/コード68.492us。**正確なKV/layer位置もwarmup/timed区間も一致検証されておらず、現在のr6の比較値ではない。**
- **既存r6 ROCm TG RGP** [R6-COMMON005-RGP-2026-11-02.md](R6-COMMON005-RGP-2026-11-02.md)：128k**単一トークン生成**では `flash_attn_tile<256,256,1,4,false>` 約1.49ms、`k_get_rows_float` 約0.405msを観測。これは今回の**1024-Query PP**とカーネル・問題設定が違うので、直接数値比較はしない。

## HIPのRGP位置合わせの制約

- AMDの公式説明では **RGP User Debug MarkersはOpenCL/HIPに非対応**： https://gpuopen.com/manuals/rgp_manual/user_debug_markers/ 。Vulkanの `EVOX2_FA_MAIN KV=49152 q=Qcur-19` のようなRGPユーザーラベルをHIPへコピーする案は採用しない。
- Windows版RDP/RGPはHIP Kernel dispatchとWavefrontの計測をサポート： https://gpuopen.com/rgp/ 。初期RGPではカーネル名・dispatch grid・実行順、前後イベントから対象候補を絞る。
- RDPの**Dispatch start index**はVulkanとHIPで一致しない。Vulkanで使った181200をHIPに使い回さない。計測中にtimeoutが発生するならscopeを縮める。
- カーネル名 `flash_attn_ext_f16...` や形状が一致するだけでは、対象が**KV49152/Qcur-19**と実証できない。厳密な時刻対応が取れなければ、結論は「同一モデル・類似カーネルの参考比較」に留め、必要に応じて別Gateでdefault-OFFのHIP launch診断（対象KV/layerをホストログに出す等）を設計。RGPでroctxマーカーが表示されるとの前提は置かない。
- HIPではVulkanのMASK_OPTと同名の時間区間はない。比較は `flash_attn_mask_to_KV_max`（末尾scan）、HIP MAIN、Vulkan MASK_OPT / MAINという**処理機能別**で行い、単純に同名stageとは扱わない。

## Gate案

### Gate0 — ソース・既存計測監査（今回）

HIPのsparse disabled、suffix scan enabled condition、r5 HIP RGP、r6 TG RGPとVulkanの確定結果を整理。**完了**。コード修正・ビルドなし。

### Gate1 — 同条件64k ROCm実入力計測の再現確認（実機）

- 既存の検証済みROCm `llama-bench` バイナリ（例 r6 b12038）を候補に、ビルドcommit/独立したHIP runtime DLL/model SHAと`R6Rocm...BuildKey`を記録。b12133 Vulkanとの**source revision mismatch**は明示。より厳密に同一source commitを揃えるには調査ブランチを別ROCm build folderへビルドし直す（このGate後に判断）。
- 条件固定：`PromptTokens61777`, `Context65536`, `Batch2048`, `UBatch1024`, `GenerationTokens0`, `Depth0`, `Repetitions1`, `NoWarmup=true`, `KvType=f16`, `Threads4`, 全GPU offload、`QWEN4EXP_QSA_GATHER=0`、MTP OFF、P-MODE Performance、UMA96GB。同じ**コード/文学原本SHA**を使用。
- 初回はコード・文学両方を自動連続実行せず、**コード1回のみ**でROCm kernel event一覧の妥当性を検証。RDPのProfile targetは**HIPで実際に計算するllama-bench.exe**。Vulkan marker/FA-mask/Indexer readback/dispatch loggingはOFF。
- 必要に応じて1回だけ文学を追加。RGP ONのPP tok/sは通常速度比較に使用しない。

### Gate2 — ROCm HIP RGP dispatchの同定

- 既存RDPのWindows HIP対応を使い、まず小さい**Dispatch range**をcalibrate。全GPU Graphの長いtraceやGPU memory pressureを避ける。最初からVulkan`start181200`を流用しない。
- `flash_attn_ext_f16<...>`, `flash_attn_mask_to_KV_max<...>`, `flash_attn_tile<...>`, Indexer/top-k、GDN/MatMulを探し、各カーネルのテンプレート引数、dispatch grid、duration, registered VGPR/LDS, occupancy, barrier, queue idleを記録。
- **KV/layer位置が確定していなければ、Vulkanの44.830/133.210msとは厳密比較しない**。まず可視のGPU kernel実行時間と他workの割合を把握する。

### Gate3 — 必要時のみ位置合わせ用の最小HIP診断

- Gate2でKV/layerを確定できない場合だけ、既存の推論アルゴリズムを変えない opt-in のホスト/dispatch logの追加方式を具体化。HIP RGPにVulkan user markersが見えるとは仮定せず、出力ログの時刻・dispatch順などの対応精度を検証。
- 必要なら限定した対象KernelにHIP event timerを入れる対照を検討。ただし同期・capture overheadがGPU時間を変える可能性を別途評価。精度が確立するまでは「推定位置」扱い。
- 取得できたら**同一KV49152 / layer19 / N1024** のコード対文学（可能なら layer23も）の時間比を出す。末尾mask scanとMAINの時間を分ける。
- Vulkanの1-FA差と全PP速度差の定量寄与率を主張するには、PP全体の対応カーネルを十分サンプリング/積算する別実験が必要。

## 安全・再現性

- Windows gfx1151で過去にHIP watchdog/TDRがあったため、**広範囲の`FLASH_ATTN_EXT` backend suiteや`Build-ROCm.ps1 -RunBackendTest`を実行しない**。
- RGP/SQTTはメモリを使用する。元の診断用RGPの保存先に上書きしない。TDR、Kernel-Power、DeviceLost、OOM、P-MODE変化や異常クロック、GPU resetを見たら停止してログだけ収集。
- 未加工`.rgp`ファイルや大きいZIPはGit外に保管し、実験結果の集計/SHA/正確な設定値だけを`evox2-llm-experiments`へ記録。
- 先にVulkan側から差が得られたので、ROCmにscore/top-k/F16同一量のinstrumentationを移植するのは**初期Gateで不要**。Vulkanが抽出したマスクは「モデルgraphのmask選択先」という既知の入力依存性を示すが、ROCm FA timingにどの程度寄与するかは実測が必要。

## Next action

**64k ROCm 実入力RGPプランとRDP HIP設定を作成済み（未実行）。** [Runbook](R6-ROCM-PP-FA-RGP-64K-CAPTURE-RUNBOOK-2026-11-07.md) と [計測プラン](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107.psd1) を参照。旧r6 b11908/COMMON-005 b12013の`llama-bench`は実入力未対応。既にsmokeを完走したb12038実入力対応ROCmを最初の比較に使用し、同一source比較が必要なら別Buildを検討。作業worktreeは`r6-ppdiag`、実行binは`r6/build-rocm-bench-real-r6`と分離。まずビルド確認、PlanOnly、コード64k HIP RGP。HIPカーネル取得を確認後に文学へ。

この計画はVulkanの完了結果を前提としており、無断でHIP source変更や長時間計測を始めるものではない。


---

## 2026-11-08 実測結果：ROCm HIP FAの入力依存性（16k / 32k / 48k）

**Status:** b12164 HIP RGPで、KV=16384 / 32768 / 49152、それぞれ Qcur Layer19 / Layer23 の `flash_attn_ext_f16<256,256,16,4,false,false,false>` をコードと文学で位置合わせして取得済み。**FAのRGP比較は一区切り。実際にscanが返した `KV_max` 値は未測定で、次の限定診断候補。**

### 計測系とサンプルの同一性

- Repo/branch: `investigation/r6-rocm-rgp-moe-layer-tags-20261107`、ROCm `llama-bench` b12164（実行ソース表示 `72434d94b`、実機報告済みSHA256 `6684cc090588ea8b1afd46be770462a250da1db1b1cdf31b0eb807ce4568ef39`）。
- GPU: Radeon 8060S (gfx1151) / Windows / TheRock ROCm、P-MODE Performance / UMA 96 GB。モデル: Qwen3.8 Flash Next, Unsloth PLE16 IQ3_XXS。
- 64kベンチの同一入力head61777 tokens、ctx65536、UBatch1024、Batch2048、KV f16、generation0、no-warmup、1 repetition、4 threads、full GPU offload、CPU MoE0。QSA Gather/MTPパッチOFF。
- 入力ファイルSHA256: コード `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`、文学 `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`。
- `GGML_HIP_RGP_ANCHOR=1` と `GGML_HIP_RGP_ANCHOR_KV=<対象KV>`、`GGML_HIP_FA_TRACE_KV=<対象KV>` を揃え、HIP Dispatch range 512 / SQTT HighのRGPで `evox2_hip_anchor_fa_layer19/23` の直後の **mask scan kernel** と **FA MAIN kernel** を計測した。MoE tagged markersも使用。GPU kernel eventの継続時間のみで、後続の `CmdBarrier` 約3〜10msやホストFA trace `host_us` は加算しない。
- プロファイルON時のPP tok/sは通常PP性能として扱わない。Vulkanとのソース時点やbackendの違いも存在する。

### FA MAIN：Layer/KV位置を一致させた比較

単位ms（小数第3位表示）。コード側差 = (コード − 文学) / 文学 ×100%。正はコードの方が遅い。

| KV / UBatch(0-based) | Layer | コードMAIN ms | 文学MAIN ms | コード側差 | 反復 |
|---|---:|---:|---:|---:|---|
| 16384 / u15 | 19 | 38.429691 | 38.022206 | **+1.072%** | 各1回 |
| 16384 / u15 | 23 | 37.301801 | 38.613050 | **−3.396%** | 各1回 |
| 32768 / u31 | 19 | 79.546987 | 79.734893 | **−0.236%** | 各1回 |
| 32768 / u31 | 23 | 78.599406 | 78.795051 | **−0.248%** | 各1回 |
| 49152 / u47 | 19 | 116.998671 | 117.921638 | **−0.783%** | 各1回 |
| 49152 / u47 | 23 | 117.724093 | 114.936902 | **+2.425%** | **順序反転の2組平均** |

KV49152のLayer23の内訳：1組目 code116.469703ms / literature115.087484ms、2組目 literature114.786320ms / code118.978482ms。同一方向だが差の大きさは変動する。上記以外は1回比較で、数%の差を確定した入力効果とは呼ばない。

**結果:** 今回の6比較点ではFA MAINの差が絶対値で最大3.40%。16k/32k/48kに伴うFA実行時間の伸びは概ねKV長に比例し、Vulkan QSAのKV49152一致サンプル（Layer19 文学133.210ms vs コード44.830ms、Layer23 文学149.954ms vs コード65.195ms）のような2〜3倍の文章差はHIPでは観察されない。ただし両backendでソースのrevや計算経路が違うため「厳密な同一コードA/B」とはしない。

### HIP `flash_attn_mask_to_KV_max<16>` GPU時間

単位µs。カーネル単体でありFA MAINとは別に記録。

| KV | Layer | コード scan µs | 文学 scan µs |
|---|---:|---:|---:|
| 16384 | 19 | 61.629 | 62.774 |
| 16384 | 23 | 59.997 | 64.468 |
| 32768 | 19 | 87.358 | 81.959 |
| 32768 | 23 | 83.690 | 81.077 |
| 49152 | 19 | 94.928 | 91.868 |
| 49152 | 23 | 94.130 | 89.604 |

KV49152 L23 scanは2組平均（code93.362 /94.898、lit87.788/91.420 µs）。絶対時間は約0.06〜0.095msであり、数十〜百msのFA MAINよりずっと短い。

### ソース上のskip条件（b12164）

1. HIPではCUDA専用の `use_sparse` index compactionを使用しない：`ggml/src/ggml-cuda/fattn.cu` `ggml_cuda_flash_attn_ext_mma_f16_shall_use_sparse` はHIPでfalse。したがって今回のmainは末尾走査方式。
2. `ggml/src/ggml-cuda/fattn-common.cuh`：`FATTN_KQ_STRIDE=256`。`scan_mask = !use_sparse && mask && K->ne[1] % 256 == 0 && (Q->ne[1] >= 1024 || Q->ne[3]>1)`。Query tile (`ncols1=16`) ごとに末尾から256-Key区間を調べ、全16 Queryの全要素が無限大（実際は −inf）なら連続して遡る。最初の有効要素のある256区間の末端を `KV_max` として返す。*途中*の無効区間は対象外。
3. `ggml/src/ggml-cuda/fattn-mma-f16.cuh`：FA MAINは `kb0_stop = min(kb0_stop, KV_max[sequence*iter_j+jt] / nbatch_fa)` を使用。RDNAのこの `<256,256,16,4>` 構成では `nbatch_fa=64`、256 Key単位の末尾判定が4個の内部KV処理単位に対応する。スキャンによる実際の `KV_max` 値は今回読んでいない。
4. 対比：Vulkan QSAの独立したALL_NEG_INFタイルskipはmask*内部*にも作用する。Vulkanのmaskタイル数差を、そのままROCmでskipされた仕事量へ換算してはいけない。過去Indexer調査のKV49152 L19では最近8192 Key選択率 code93.933% / lit54.578%だが、最後の256 KeyにQuery tile内で選択があったか、実 `KV_max` がいくつかはこの率から断定できない。
5. `GGML_HIP_FA_TRACE` の `kv_max_hint=2051` はQSA sparse選択予算のヒントであり、GPUのsuffix scan結果 `KV_max` ではない。

### 生データの所在・再現性

- **KV16384の4run ZIP（2026-11-08）:** `20261108-144205-199-bench-rocm-b12164-ctx65536-96a5a526e617.zip`、SHA256 `ae3a857ef658023c79b7c31d91c7621a7ddcfa625a6979ef8ddca9cbed688f82`。4 run IDs：文学 L19 `20261108-142358-510-...`、コード L19 `20261108-142933-819-...`、文学 L23 `20261108-143523-309-...`、コード L23 `20261108-144205-199-...`。4/4 status OK、exit0、実行バイナリSHA/入力原本パス/対象KVをZIP内部 `result.json` と `conditions.json` で再検証。対応RGPは `llama-bench-20261108-142535789.rgp`、`...-143106926.rgp`、`...-143828596.rgp`、`...-144432133.rgp`。
- **KV32768コード:** ZIP `20261108-012504-523-bench-rocm-b12164-ctx65536-c62ace99a505.zip`（L19）と `20261108-074917-523-bench-rocm-b12164-ctx65536-c62ace99a505.zip`（L23）。**KV32768文学:** combined `20261108-082448-296-bench-rocm-b12164-ctx65536-961a06c34519.zip`（2run）。いずれもZIP内status OK/exit0/対象KVを確認した。
- **KV49152:** b12164の2026-11-07夜RGP（Layer19およびLayer23、後者2組順序反転）。2組目ZIP `20261107-224217-882-bench-rocm-b12164-ctx65536-cab91edc1b65.zip`。元のRGP/ZIPはユーザーの実機・チャット資料、Gitへは含めない。RGP時間はユーザー提供Event Timingスクリーンショットから転記。
- RDP開始位置（実験時の例で、将来の別buildに転用不可）：KV16384 L19≈63800/L23≈64200、KV32768 L19=130550/L23=130900、KV49152 L19=197240/L23=197540。512-dispatch rangeでFA直後のMAINを確認。
- **MoE調査とは独立:** b12156のExpert histogramはGPU同期callbackによる別run。b12164のLayer23/KV49152 MoE MMQ差（code+3.24%）と本FA差（code+2.43%）を、未検証のPP全体寄与として単純に足さない：[MoE最終報告](R6-ROCM-MOE-EXPERT-ROUTING-RGP-SUMMARY-2026-11-07.md)。

### 次のGate：実 `KV_max` の小規模確認（未着手）

*目的:* 末尾256-Key単位のskipが実際に何回起きたかを測る。性能改善コードではなく、**診断専用・default OFF・通常ベンチとは別run**。まずKV49152か32768の**Layer19の単一FA op**（コード／文学）を対象とし、Query tile64組中の実 `KV_max` のmin/median/max、フルKVと同値の割合、平均skip256タイル数、非ゼロskip件数を取得する。実際の対象opは `N1024/ncols1=64` グループ、各groupの要素数は1 int。
*安全:* HIP Graph capture中での同期読戻しは不可/実行グラフが変わるため、計測以外の独立した実験としてCUDA/HIP graph disabled経路または後段の安全な診断ポイントで少量readback。同期・copyがあるrunのFA timing / PP tok/sは測らない。開始前にGraph制御と所有するストリーム・`KV_max` buffer lifetimeをソースで確認し、先にsmoke。巨大なmaskやKV全体は読まない。
