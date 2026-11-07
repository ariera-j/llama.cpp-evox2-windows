# r6 ROCm/HIP 64k PP入力依存性 — Vulkan比較からの引継ぎ計画（2026-11-07）

**STATUS: 調査計画・ソースレビューのみ。新たな計測プランの実行、ROCmビルド、GPUキャプチャ、HIPのソース変更は未実施。**

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
