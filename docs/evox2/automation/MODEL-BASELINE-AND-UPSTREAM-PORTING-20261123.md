# Codex: モデル互換性・監視ゲート・次期 upstream ベース (2026-11-23)

> **2026-11-23確定済みの監視・モデル互換性スモークと、次期upstream移植方針。** 実績はb12037（r6系ソース）に限られ、新しいupstreamでのビルド・PLE16互換性・性能はまだ検証していない。

## 目的と現在地

- 公開リポジトリ `ariera-j/llama.cpp-evox2-windows` の **main は r6 系の下流改造コード**。クリーンな最新 upstream ではない。既存 b12037 の Codex 専用 Vulkan/ROCm ビルドとその BuildIdentity は、あくまでそのソースでの実績。
- Codex が管理する EVO-X2 専用 clone は `C:\llama-build\automation\llama.cpp-evox2-windows`。ログは `C:\llama-build\_logs\codex`。モデルと後日移設する入力データは書き換えない。Windows PowerShell は UTF-8 BOM 付き、予約変数 `$input` を使わない。
- 次の高速化研究で主に使うモデルは **Unsloth Qwen3.8 Flash Next IQ3 PLE16** と **ROCmFP4 FAST PLE16**。旧 IQ3 Original はクリーン upstream での起動や比較のための対照モデルであり、最終研究ターゲットではない。
- BIOS UMA は運用者確認で **64 GB**（2026-11-23）。旧 IQ3 Original（3シャード、合計76.33 GiB）は既存 b12037 にて Vulkan/ROCm とも `-ngl 999`、49/49 GPU 層の短文推論に成功している。これはメモリ使用の将来の保証ではない。

## バックエンド別モデル対応・計測ゲート

| モデル | r6 Vulkan (既存の対応経路) | r6 ROCm (既存の対応経路) | 新 upstream (移植前) |
|---|---|---|---|
| 旧 IQ3 Original / joined PLE | 短文実行済み | 短文実行済み | 対照モデルとして検証 |
| Unsloth IQ3 PLE16 / split PLE | **b12037短文PASS** | **b12037短文PASS** | **動作を仮定しない。COMMON-001を最初に移植** |
| ROCmFP4 FAST PLE16 | **b12037短文PASS** | **テスト対象外。HIP/ROCm専用実装は未完了** | 初期移植対象外。Vulkan互換性も別途検証 |

- 「ROCmFP4」というモデル名と、ROCm/HIPでのFP4カーネル対応は別の概念。Vulkanでのロード成功をROCm対応の根拠にしない。
- 原則 `Context=4096`、`GpuLayers=999`、`CpuMoe=0`、`Batch=2048`、`UBatch=1024`、`Threads=4`、`KV=f16`、`FlashAttn=auto`、`MTP=OFF`、`AllocationOnly`（固定短文、最大32トークン）、Vulkan/ROCm逐次実行。
- PLE16変換モデルはロードできるだけでなく、**全層GPU割当、GPUエラーなし、応答と終了コード0**まで確認する。モデルシャード、ビルドSHA、backend、量子化を各結果に記録する。

## ResourceMonitor 修復・実機推論の確定結果 (2026-11-23)

- `evox2-runner` は **Medium Integrity** の非管理者のまま。運用者が `Performance Monitor Users` と `Performance Log Users` を追加した結果、ADLX VRAMとPerfMonのページング・GPUメモリ照会は復旧。WMI `Win32_OperatingSystem` は引き続きアクセス拒否。
- `Monitor-LlamaProcess.ps1` の**物理メモリ取得のみ**を `GetPerformanceInfo` に変更した。PerfMon経路、53列、`Measure-LlamaCli.ps1`、ADLXは従来のまま。以前の広範な変更 `codex/resource-monitor-20261123` は参考として保持するが採用しない。
- 10秒単体監視は53列・10サンプルでPASS。既存b12037（`9de09c610`）、UMA64 GB、Context4096、全層GPU、CPU MoE 0、batch2048、ubatch1024、threads4、KV f16、FA auto、MTP OFF、AllocationOnlyの短文を計5回実施し、**全件で終了0、GPU 49/49層、生成2トークン、ページング・GPU Adapter/PID Dedicated/Shared、ADLX VRAM**を確認した。

| backend | model key | Resource/PID GPU samples | ADLX VRAM samples | ADLX VRAM max (MiB) |
|---|---|---:|---:|---:|
| Vulkan | UnslothOriginal | 22/22 | 27/27 | 52066 |
| ROCm | UnslothOriginal | 20/20 | 24/24 | 51682 |
| Vulkan | UnslothPle16 | 22/22 | 27/27 | 65336 |
| ROCm | UnslothPle16 | 15/15 | 18/18 | 51684 |
| Vulkan | AgentionRocmFp4FastPle16 | 34/34 | 44/44 | 64811 |

詳細な最大値・実行ID・ログパスは [KNOWN-ISSUES.md](KNOWN-ISSUES.md#2026-11-23-物理メモリ取得のみの修正と推論再検証)。生ログは `C:\llama-build\_logs\codex` 配下。これらはモデルロードと短文推論・監視のスモークであり、長文PP/TGや品質の比較結果ではない。

## 新 upstream 研究ベースの選定と導入順序

1. **候補SHA（2026-11-23確認時の ggml-org/llama.cpp master）**: `212c547fe908b288f6659d48741e6ffac1ff409c`。これは **提案・未検証** であり、ビルド済み/互換性確認済み/採用済みを意味しない。作業開始時にこのオブジェクトを取得してSHAを照合する。動くことを優先し、クリーンビルド/旧IQ3スモークに問題があれば、最近実機で使用した別のupstreamコミットを証拠付きで候補にする。無断で動くmasterへ更新しない。
2. 新しい専用研究ブランチ・worktree・未使用ビルド先を用いる。**main の r6 下流コードをそのまま上流ベースと呼んだり、既存のビルドや r6 worktree を上書きしない**。フォーク main に対して upstream master を安易に merge しない。
3. `docs/evox2`、`tools/evox2`、必要な実行用設定を **パス単位で** 取り込む。履歴・依存・upstreamとの衝突を確認し、文書/ツールの移植をネイティブ推論ソースの移植と明確に区別する。ローカル `local.codex.psd1`、モデル/生ログ/入力はGit管理外。Gitの作業ツリーがクリーンであることを確認する。
4. **最初に改造なしのupstreamをVulkan/ROCmでビルド・デバイス列挙・旧IQ3 Originalで短文推論。** 正確なSHA・BuildIdentity・ビルド環境・モデルとログを保存する。既存の `Invoke-CodexBuild.ps1` は `codex/build-wrapper-20261123` にあり、新しいupstreamでそのまま使えることは未検証。UI両フラグOFF、依存キャッシュの保護、危険な広範backendテストの自動実行禁止を守る。
5. **最初の互換性移植はCOMMON-001 (PLE16モデル読み込み/配置)**。必要箇所をr6のソースと対応させ、upstreamに既に同等実装が存在しないか調べ、最小差分で移植。対応はbackend別に検証し、IQ3 PLE16のVulkan/ROCm短文→必要に応じ64kで確認する。元モデルとはGGUFレイアウトが違うため、速度の因果比較で混同しない。
6. PLE16が通るまでQSA union・MTP DENSE/NOOP・Stage-B・flatten・ROCmFP4等を一括移植しない。次の最適化は独立した仮説・テストごとに選ぶ。ROCmFP4のHIP実装は別工程。
7. 実測の状況は `docs/evox2/automation/` と対応するパッチ履歴に **提案／実装／ビルド／推論／性能計測／採用** を分けて記録する。ブランチのコミット、実際のビルドバイナリSHA、モデル・入力・UMA・条件、代表値とログ場所を記録し、main統合はレビュー後のfast-forwardのみ。

## 参考文書

- `docs/evox2/INTEGRATION-POLICY.md`: 新 upstream の固定・COMMON-001優先・単独パッチ移植という基本方針
- `docs/evox2/PATCHES.md`: 旧パッチと前提条件の一覧
- `docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md`: r6時点のbackend別適用範囲（過去の限定判定）
- `docs/evox2/automation/{AGENT-RULES,EVOX2-ENVIRONMENT,KNOWN-ISSUES,RUNBOOK}.md`: Codex環境と安全運用
- `tools/evox2/benchmark/Measure-LlamaCli.ps1`, `tools/evox2/adlx-gpu-monitor/`: 実行・監視

**モデル推論テストは成功済み。次に入力ファイルを移管する。** `ai` が手動で安全な共有先にコピーしてSHA照合・ACL設定をした後に、Codexがその読み取り専用パスをGit管理外の `local.codex.psd1` に追加する。既存の `local.psd1` は変更しない。
