# Qwen3.8-Flash-Next / Evo-X2 高速化候補調査 — 2026-10-03

## 調査範囲と比較基準

2026-10-03 JST に一次資料（各プロジェクトのREADME、リリース、PR本文・差分・コメント）を確認。
比較対象は `r4/upstream-refresh-20261002` の `ab3b4daf51c4615a96efa5c52117533c52dcc490`、
推論ソースの固定upstreamは `bed0a856606ee4a24a164066f73d2379447033f5`。
GitHub上のPATCHES.md/ROADMAP.mdも取得し、ローカル資料と照合する。

これは候補抽出のメモ。新しいPATCH IDの付与や採用決定ではない。
記載の性能値は、特記がなければ各開発者の報告であり、Evo-X2で今回再測定した値ではない。
別モデル・OS・量子化・入力・MTP条件の改善率を現在の64k結果に乗算しない。

現在の実測条件は Original UD-IQ3_XXS、Windows、UMA 96GB、MTP OFF、
batch 2048 / ubatch 1024、f16 KV、temperature 0.2。
64kではVulkan 248.38/24.61、ROCm 369.72/20.98 tok/s（PP/TG）。
追記: 128k/256kも完了。全結果はBASELINE.md、既存パッチを優先する最新判断は
[R4-PATCH-PRIORITIES-2026-10-03.md](R4-PATCH-PRIORITIES-2026-10-03.md)を参照。
以下の新規候補より先にVulkanのr3比PP/TG低下を診断する。

## エンジンの最新状況

| 対象 | 確認した版 | Evo-X2 / Windowsでの位置づけ |
|---|---|---|
| Halogen | README/CHANGELOG 0.16.1。公開repo HEAD `6ff580c0f37513da2c4aae984ba89291efe08af6`、2026-10-02 16:04 UTC | gfx1151専用だがnative Linux + amdgpu/KFD前提。WSL2は明示的に非対応。公開物は配布・運用資料とバイナリ中心 |
| Strata | v0.1.37、2026-10-02 19:51 UTC = 10/03 04:51 JST | v0.1.34以降Windows HIP配布あり。ただしv0.1.37の対応アーキテクチャ一覧にgfx1151なし。setupも統合GPUを非対応と扱う |
| Unsloth mix | 最新release APIは b11160-mix-a6922cc、2026-09-25 00:10 UTC | 今回のr4より古いupstreamを基礎に独自PRを合成。丸ごとの置換より、残る差分の選別が適切 |
| flashrt | READMEの状態日付2026-10-01、v0.1.0以降の研究実装 | Qwen3.8-Flash-Next専用の参考実装。Linux / CUDA / RTX 5080とGSQ-RCO Q2_0が主検証条件。HIP版として使えるものではない |

Halogenは0.14.1でrouted-expert prefillカーネルを変更、0.15.2/0.15.3もPP、
0.16.1はdecodeを改善と記載。ただしREADMEの主要PP表は0.14.1、
32k MTPの表は0.14.0の測定であり、0.16.1の新しい実測値として扱わない。
参考値は131,072-token PP 1,517 tok/s、32k MTP TG 46.0 tok/s。
同一モデルファイル・同一条件のr4比較ではない。

HalogenのGGUF直接読み込みは以前より拡大しているが、
現在使うIQ3_XXSは確認した対応形式一覧に明記されていない。
「今のUnslothファイルをそのまま使える」とはまだ判断できない。
ネイティブLinuxで将来比較する場合も、モデル形式の確認が先。

Strata v0.1.36のPP +16〜22%等はRTX 5070/Q2_0の結果で、新カーネルはNVIDIA専用。
v0.1.37のWindows WDDM予算対策はRX 6800での改善報告。
gfx1151やUMA 96GBへそのまま外挿しない。
flashrtのexpert cache/CPU併用はVRAM不足のdGPUで有効な設計であり、
現在のほぼ全GPU配置のEvo-X2では優先度が下がる。

Sources:
- https://github.com/peonist-ai/halogen-flash-server
- https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md
- https://github.com/Niko1221/Strata/releases/tag/v0.1.37
- https://github.com/Niko1221/Strata/releases/tag/v0.1.36
- https://github.com/Niko1221/Strata/blob/v0.1.37/docs/AMD_HIP.md
- https://github.com/unslothai/llama.cpp/releases/tag/b11160-mix-a6922cc
- https://github.com/BFinn/flashrt

## 独立した新規候補

優先度は「現在のWindows/Originalモデルに対して、効果と適用条件を切り分けやすい順」。
以下のPRは調査時点では未merge。

### A1. ROCm: transposeを伴うF32 CONCATの専用コピー

Source: [upstream #28303](https://github.com/ggml-org/llama.cpp/pull/28303)
head: `e478c7ef9f81307f20d22a90256a802986f8bed6`

- 狙い: PP。GDNの畳み込み入力を作る際の転置コピーを、32×33のshared-memory tileで連続アクセス化。
- 報告: Windows 11 / Ryzen AI Max+ 395 / Radeon 8060S / ROCm 7.1。
  Qwen3.6-35B-A3BでPP +5.54〜9.92%、TGほぼ不変。
  ubatch 1024の中央値では+7.79%。5回のABBA、各版10サンプル。
- r4照合: `ggml/src/ggml-cuda/concat.cu` にこのRDNA3.5専用分岐はない。
  `src/models/qwen4exp.cpp::build_conv_state_at` は
  `concat(state, transpose(x), 0)` を使い、対象に近い演算が実在する。
- 適用条件: F32、dim=0、転置側の幅512/1024/2048、channel/stride等の条件。
  現在のubatch 1024と整合するが、実際のtensor型・strideでfast pathに入るかは未測定。
- 既存計画との差: PLE、QSA、matvecではなくGDN前段のメモリコピー。PATCHES/ROADMAPに独立項目なし。
- 次の確認: real-input PP profileでCONCATの比率とshapeを記録。
  対象なら小さい単独パッチとしてbackend CONCATテストと同条件A/B。
- 注意: 報告はQwen3.6。Flash-Nextで+5〜10%と予告する根拠にはしない。

### A2. ROCm: Gated DeltaNetのchunked matrix-coreカーネル

Source: [upstream #29353](https://github.com/ggml-org/llama.cpp/pull/29353)
head: `377e111e8ce466652b9c4a6ef5e62521d588bf91`

- 狙い: PP。GDNの複数token処理をmatrix core向けにまとめる。
- 報告: Strix Halo / Qwen3.8-27B UD-Q8_K_LでPP +6.75〜6.98%。
  Flash-NextやWindowsで同じ効果が確認された報告ではない。
- r4照合: 新しい `gated-delta-net-mma.cu` とdispatchは未収録。
  Flash-Nextも共通GDN実装を使う。
- 重要な条件: PRのHIP dispatchはRDNA3.5かつ `n_tokens >= 2048`。
  現在の `-ub 1024` では選択されない。
  K head数16、V head数16/32/48/64、head dimension128等の制限もある。
  手元ログのFlash-Nextはgroup_count16、time_step_rank48、state_size128で、
  head形状は候補に合う。実際のdispatch確認は必要。
- MTPとの関係: PRコメントではrecurrent snapshotを使うspeculation時のprefillは現状対象外。
  まずMTP OFFで評価する。
- 既存計画との差: QSA以外のlinear-attention層を高速化する新しい軸。
- 次の確認: clean r4をubatch 1024/2048で比較した後、
  clean 2048対patched 2048を比較。ubatch変更とカーネル効果を混ぜない。
  長文でcompute buffer増加、PP、出力品質を確認する。

### B1. GDN alpha/beta生成の融合

Source: [upstream #29187](https://github.com/ggml-org/llama.cpp/pull/29187)
head: `3d3d1592fc916eac51fb49118ed424f5995acdb7`

- 狙い: 主に少token処理/MTP verify。projection、bias、softplus/sigmoid、scaleをまとめ、
  小さいkernelを繰り返し起動するコストを減らす。
- 公開性能値はNVIDIA上の別モデル。gfx1151の利益は未確認。
- r4のqwen4expにはalpha/betaの演算列が残っているが、betaを先に構築する。
  PRのfusion matcherはalpha側から始まる列を前提としており、
  このモデルで自動的にfusionされるとは限らない。
- 次の確認: GDN gate生成のGPU時間と起動回数を測定し、fusion成立条件を照合。
  適用する場合はHIPビルド・数値比較に加え、qwen4exp用のpattern調整要否を確認。
- 判定: A1/A2より後。既存COMMON-002の「MTPを読み込めるようにする」作業とは別のkernel課題。

### B2. MTP + prompt lookupの併用評価

Source:
- [Halogen CHANGELOG 0.6.0](https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md)
- r4 `common/speculative.cpp`

- 狙い: 原文の引用・コード編集など、入力中の語句を再利用する生成のTG。
- HalogenはMTPに加えて入力中の一致列をdraftとして使い、coding-agent条件で
  49.1→56.3 tok/sを報告。一般文章では差が小さく、公開実装説明はgreedy専用。
- r4には既にngram系speculatorとMTPを複数指定する基盤がある。
  従って最初は新規パッチではなく運用A/B候補。
  その優先順位方式はHalogenのchain構成と同一とは限らない。
- 新規性: ROADMAPに普通のMTP評価はあるが、入力再利用draftとの組み合わせは未記載。
- 次の確認: MTP単独が正常動作した後、引用多めの日本語要約・コード編集・自由生成を分け、
  MTP単独とngram併用でacceptanceとwall timeを比較。
  最初はtemp=0、その後普段のtemp=0.2で検証。Halogenの+15%をそのまま予測しない。
- ngram単独、MTP単独、併用の3条件を分け、候補が使われた回数も記録する。

### C1. Draft側だけの語彙・LM head縮小

Source:
- [flashrt README](https://github.com/BFinn/flashrt)
- [Strata v0.1.36](https://github.com/Niko1221/Strata/releases/tag/v0.1.36)

- 狙い: MTP draftのLM head計算量・メモリ量を減らす。
- flashrtは頻出tokenでdraft vocabularyを絞る。Strataもdraft-vocabと小さい言語別候補を扱う。
- r4の普通のMTP互換性確認とは別の最適化。利用中のUnsloth draftへそのまま適用できる機能は未確認。
- 日本語中心の運用では英語向けの語彙削減を流用しない。draft acceptanceが落ちれば逆効果。
- target側の語彙・重みは保持し、token ID対応と検証・棄却処理を維持する設計が必要。
- 判定: MTP profileでLM headが支配的だった場合の長期候補。現時点でモデル変換は行わない。

### C2. Unslothのpenalty sampler最適化

Source: [Unsloth #95](https://github.com/unslothai/llama.cpp/pull/95)
head: `3db8cb5b2e9bf291057b9f19960e8601a162da81`

- 狙い: TGのCPU側負荷。全語彙に対するhash lookupを避ける。
- r4 `src/llama-sampler.cpp` には全候補を走査する旧ループが残る。
- ただし今回のログはrepeat_penalty=1、frequency/presence=0。
  無効時は早期returnするので、現在のbaselineの高速化にはならない。
- 新規候補としては記録するが、penaltyを使う運用を評価する時まで保留。
  他モデルの+11%という報告を今回のTGに適用しない。

## 既存項目を具体化する情報（新規件数には数えない）

| 情報 | 既存の受け皿 | 今回追加すると有用な具体的確認 |
|---|---|---|
| Vulkan #25666 / #29679 の小batch MMVQ policy | Strix Halo/RDNA matvec tuning、COMMON-002 | MTP verifyのn=2〜8を個別に測定。Windowsで5〜7 token時に急落しないか、acceptanceも確認 |
| PLE direct read #29030 | PLE residency/mmap experiments | r4のprefetchに加えdirect readがなお有効か。cold/warm別・実入力で比較 |
| Halogen 0.12.0のparallel block select / key reuse | COMMON-006、indexer-pipeline | block-domain化の有無だけでなく、selection kernel占有率・読出し帯域を測る |
| StrataのHIP matrix-core QSA prefill | VULKAN-002関連QSA/FA研究 | 公開WMMA pathはgfx12用。gfx1151へ直接移植可能とはしない。ROCm向け再設計の資料 |
| Halogen/flashrtのrouted-expert PP kernel | MMID row-list prepass / MoE prefill | token groupingとquant/dequantの再利用をprofile。NVIDIA int8 kernelや別量子化の値は外挿しない |
| Halogenのtrunk展開を保持するopt-in | メモリ配置の派生実験 | PPが量子化展開律速なら検討。常駐メモリ増とTG bandwidth悪化を別々に測る |

#29679はWindows/7900 XTX/Adrenalin 26.8.1の報告で、
同PRコメントにはRADV/Navi31でも似た急落が報告されている。
「Windows固有と確定した不具合」とは扱わない。
#25666はgfx1151/RADV/35B-A3BでMTP TG +12.9%の報告。
ともに今のMTP OFF、IQ3_XXS全体の改善率を示すものではない。

#29030の前身#28136はclosed/unmerged、#29030が後継。
「古いclosed PRをそのまま採用」としない。
#29825はopenのままで、すでにROADMAPにあるため新規候補ではない。

Sources:
- https://github.com/ggml-org/llama.cpp/pull/25666
- https://github.com/ggml-org/llama.cpp/pull/29679
- https://github.com/ggml-org/llama.cpp/pull/29030
- https://github.com/Niko1221/Strata/issues/432
- https://github.com/Niko1221/Strata/blob/v0.1.37/docs/AMD_HIP.md

## 検討したが独立候補から外したもの

- **MTPのon-device checkpoint #28118**:
  初期報告は大きいが、コメントではnative recurrent rollbackでcheckpoint自体を避ける方が良いと整理。
  r4の `llm_arch_supports_rs_rollback` にQWEN4EXPがある。
  既存COMMON-002のrollback検証へ含める。host checkpointが実際に残る場合のみ再検討。
  PRコメントにはrestore失敗の報告もあり、8行を無条件に移植する候補ではない。
- **Unsloth #158 / host-buffer対策**:
  r4のCUDA/HIP共通初期化では `integrated=false`。
  問題となったhost入力直接実行経路をそのまま使う状態ではなく、
  このPRの速度効果も未測定。新しい高速化候補に数えない。
- **Unsloth #149 / #157**:
  managed allocation変数の解釈とcopy方向の正確性対策。
  r4にはpresence判定とDeviceToDevice指定が残るが、現在の計測でその設定を使って高速化する根拠はない。
  BIOSのUMA 96GB設定と `GGML_CUDA_ENABLE_UNIFIED_MEMORY` は別の設定。
- **Unsloth #152 / contiguous mapping**:
  主にMetalの実メモリ常駐問題。Windows Vulkan/ROCmでPP/TGが改善する根拠が弱い。
- **Strata packed-byte最適化**:
  r4のHIP側は既に `__vsub4` / `__vcmpne4` をpacked処理し、
  IQ4 table lookupに `__builtin_amdgcn_perm` を使う。
  現行IQ3_XXS dotにもこれらのpacked処理が入るため、
  Strataの改善報告を未導入機能として数えない。
- **Strata MoE router高速化**:
  r4にもtopk-MoE fusionがある。Strata内部の遅い旧routerとの差をそのまま移植効果にしない。
- **#29796 output getterの同期削減**:
  現PRはHIP/MUSAを明示的にopt-in対象外としている。即時ROCm候補から外す。
- **#29720 RMS norm**:
  主な利益はCDNA、RDNAは概ね中立という報告。今回は優先度を上げない。
- **#28702 MMQ gate/up+GLU**:
  現段階ではdense FFN向け、MoE `mul_mat_id` は対象外。Flash-Nextの主なexpert PP対策にはならない。
- **NPU併用**:
  Halogen 0.16.0のNPU機能は小型embedding/reranker等向け。
  Flash本体のPP/TG高速化ではなく、同時稼働でFlashは遅くなると明記。
- **IOMMU設定**:
  Halogenのnative Linux機での電力・クロック条件の報告。
  Windowsの現行baselineへ直接持ち込むkernel候補ではない。

Sources:
- https://github.com/ggml-org/llama.cpp/pull/28118
- https://github.com/unslothai/llama.cpp/pull/158
- https://github.com/unslothai/llama.cpp/pull/149
- https://github.com/unslothai/llama.cpp/pull/157
- https://github.com/unslothai/llama.cpp/pull/152
- https://github.com/Niko1221/Strata/pull/262
- https://github.com/ggml-org/llama.cpp/pull/29796
- https://github.com/ggml-org/llama.cpp/pull/29720
- https://github.com/ggml-org/llama.cpp/pull/28702

## 次の作業順案

1. 実行中の64k/128k/256k baselineを完了し、既存COMMON-005等の要否を決める。
2. PP profileにCONCATとGDNを加える。優先パッチ候補はA1。
3. A2を調べるなら、先にclean ubatch 2048の速度・メモリを測り、同じ2048でPRを比較。
4. 普通のMTPが成立したら、小batch Vulkan MMVQとprompt lookup併用を追加評価。
5. GDN alpha/beta融合とdraft vocabularyは、その部分が律速だと分かった場合に進む。

ロードマップに追加するなら、独立した項目は
「ROCm GDN/CONCAT prefill」「GDN producer fusion」
「MTP + prompt lookup」「draft head計算量削減」「penalty有効時のsampler」の5系統。
既存QSA/PLE/matvecの項目は、上記のPR・適用条件で具体化する。
