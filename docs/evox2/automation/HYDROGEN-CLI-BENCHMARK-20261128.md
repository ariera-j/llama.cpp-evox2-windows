# EVO-X2 Vulkan CLI ベンチマーク記録（2026-11-28、H4・H5）

> 将来の GitHub 保存先: `docs/evox2/automation/HYDROGEN-CLI-BENCHMARK-20261128.md`

## 1. 計測目的・実行体制・実行日

- **実行日**: 2026-11-28（JST）
- **実行エージェント / モデル**: Antigravity（Gemini 4 Hydrogen (Medium)）
- **目的**:
  - **H4**: EVO-X2 上の標準計測ツール（`Invoke-BenchmarkMatrix.ps1`）を用いた Vulkan 短文 CLI スモーク 1 run の再現性および前後安全監査手順の確認。
  - **H5**: 同一ビルド・モデル・監視構成のもとでの 32k 日本語論文入力（`nlp-survey-ch3-d3-b1.txt`）による標準 CLI 計測 1 run の実施、および H5 で観測されたモデルロード〜Context 初期化報告の遅延現象のログ調査。
- **事前経緯**: H4 の開始前に VMware Ubuntu 上の OpenCode と EVO-X2 の `llama-server` による接続試験が実施され、その後、運用者が EVO-X2 を 1 回正常再起動した状態で H4・H5 を連続実施した。

---

## 2. 実機環境・ソース・計測ツール来歴

| 項目 | 値・来歴 |
|---|---|
| **実機** | NucBox EVO-X2（Windows 11、Radeon 8060S Graphics、`Vulkan0`、UMA 96 GiB、P-MODE `Performance`） |
| **OS 起動期間** | 最終起動 `2026-11-28T02:39:39.5000000Z`（`11:39:39.500 JST`、`Kernel-General/12.StartTime`）。直前の正常シャットダウンは `2026-11-28T02:39:36.7797317Z`（再起動、OS 停止 `2.72 s`、`BootAfterUnexpectedShutdown = false`、`FastStartupEnabled = false`）。**H4（稼働 `916.5 s`）と H5（稼働 `1,811.64 s`）は同一 OS 起動期間で実行。** |
| **文書リポジトリ（正本）** | `main` / `ede665688a5b0d49891a2461564ebc07f588f2ae` |
| **実機製品ソース** | ブランチ `codex/vulkan-manifest-cpu-variants-20261124` / HEAD `a650d641ee99198543697e1e3913c593059721f7`（クリーン） |
| **ビルド元ソース** | `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`（`codex/b12651-rocmfp4-20261124`, `b12676`） |
| **標準計測ツール来歴** | 統合コミット `4c03d3e4fee3e411449f649dc02b40e34aa31552`（2026-11-26 10:01:11 +0900）。`Invoke-BenchmarkMatrix.ps1` blob `186c6136762939fe76dc72503d7c50e9f962f46e`、`Measure-LlamaCli.ps1` blob `20c6809e04cc98f54c77bcdc9020a49203227269`（`main` と一致）。 |

---

## 3. EXE・モデル・入力の識別情報

| 対象 | パス（実機） | 識別情報 / SHA-256 |
|---|---|---|
| **EXE (`VulkanStage2`)** | `C:\llama-build\automation\llama.cpp-evox2-windows\build-s2v\bin\Release\llama-cli.exe` | `b12676` (`eea8dcefc`, `Clang 22.1.3`), SHA-256: `406F91AC5D09E83BA7C54D4BABF0043E3879DFED84EF8EDD82256921C8B829F8`<br>マニフェスト `evox2-build.json`: `SchemaVersion=1`, `BuildIdentity.Status=Verified`, `RuntimeArtifactStatus=Verified` |
| **モデル (`UnslothPle16`)** | `C:\llama\models\unsloth_Qwen3.8-Flash-Next-GGUF\UD-IQ3_XXS\UD-IQ3_XXS\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf` | `qwen4exp`, `IQ3_XXS - 3.0625 bpw`, `81,961,816,672 bytes`（`76.32 GiB`）<br>※巨大 GGUF のため実行時ハッシュは未計算（`-HashModel` 未指定） |
| **H4 入力（短文）** | `C:\evox2-llm-experiments\benchmarks\gemma4-31b-pp-tg-20261115\inputs\short-ja-writing-v1.txt` | `927 bytes`, SHA-256: `AD29FE3EC728057CE0736594ED79886ED278CB0B0F6ED35E9EACA26CB27B0BB6` |
| **H5 入力（32k 論文）** | `C:\llama\inputs\qwen38\nlp-survey-paper-japanese\long-input-abstract-out\data\nlp-survey-ch3-d3-b1.txt` | SHA-256: `1709EBFD6F2E005D94AF03FE7029E8D4D87F66BA1A22A226D9F63DA6A003B601`（既知記録値と一致） |
| **ADLX 監視ツール** | `C:\llama-build\adlx-gpu-monitor\build\bin\evox2-adlx-gpu-monitor.exe` | 存在確認・終了コード `0` |

---

## 4. 計測コマンド・サンプラー・実効設定

### H4（Matrix 経由: `Invoke-BenchmarkMatrix.ps1`）

```powershell
& 'C:\llama-build\automation\llama.cpp-evox2-windows\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1' `
  -Plan 'C:\llama-build\_logs\codex\r34-recovery-20261126\monitor-smokes.local.psd1' `
  -LocalConfig 'C:\llama-build\automation\benchmark-configs\local.b12651-matrix.psd1' `
  -OnlyJob 'vulkan-iq3-cli' `
  -RunIdPrefix 'H4-smoke-20261128' `
  -MaxRuns 1 `
  -StopOnError
```

- **生成された実 CLI コマンド**:
  `llama-cli.exe -m <UnslothPle16> -c 2048 -ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa on -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0.2 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none -n 32 -f <short-ja-writing-v1.txt> --device Vulkan0 -tb 4`

### H5（単一条件ラッパー: `Measure-LlamaCli.ps1`）

```powershell
& .\tools\evox2\benchmark\Measure-LlamaCli.ps1 `
  -LocalConfig 'C:\llama-build\automation\benchmark-configs\local.b12651-matrix.psd1' `
  -BuildKey 'VulkanStage2' `
  -ModelKey 'UnslothPle16' `
  -InputFile 'C:\llama\inputs\qwen38\nlp-survey-paper-japanese\long-input-abstract-out\data\nlp-survey-ch3-d3-b1.txt' `
  -Context 32768 -GenerationTokens 256 -Threads 4 -Batch 2048 -UBatch 1024 `
  -GpuLayers 999 -CpuMoe 0 -KvType 'f16' -FlashAttn 'auto' `
  -Temperature 0 -TopP 0.8 -UmaLabel 'UMA96GB' `
  -ResourceMonitor -ResourceIntervalSeconds 2 `
  -AdlxIntervalMs 2000 -AdlxMonitorExe 'C:\llama-build\adlx-gpu-monitor\build\bin\evox2-adlx-gpu-monitor.exe' `
  -RamDetail -RamDetailIntervalMs 250 -CapturePhaseMarkers `
  -ExtraArgs @('--device', 'Vulkan0', '-tb', '4', '--seed', '1234', '--ctx-checkpoints', '0', '--no-display-prompt')
```

- **生成された実 CLI コマンド**:
  `llama-cli.exe -m <UnslothPle16> -c 32768 -ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa auto -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none -n 256 -f <nlp-survey-ch3-d3-b1.txt> --device Vulkan0 -tb 4 --seed 1234 --ctx-checkpoints 0 --no-display-prompt`
- **実効 Flash Attention / Warmup（`stderr.log` 原本確認）**:
  - **H4**: `flash_attn = enabled`、warmup 有効（`warming up the model with an empty run`）、`sched_reserve: reserve took 62.88 ms`。
  - **H5**: `FA auto` から `flash_attn = enabled` へ解決、warmup 有効、`sched_reserve: reserve took 76.48 ms`。
- **共通監視設定**: 通常監視 2 秒、ADLX 2,000 ms、RAM 詳細監視 250 ms（前 3 s / 後 5 s、ピーク閾値 64 MiB、回復許容 128 MiB）、フェーズマーカー有効、MTP 無効。

---

## 5. PP/TG・トークン数・所要時間

| 指標 | H4 (`ctx2048`) | H5 (`ctx32768`) |
|---|---:|---:|
| **Status / ExitCode** | `OK` / `0` | `OK` / `0` |
| **GPU オフロード層** | `49 / 49` | `49 / 49` |
| **要求 / 実効 Context** | `2,048` / `2,048` | `32,768` / `32,768` |
| **入力トークン数 (`PromptTokens`)** | `210` | `29,557` |
| **生成トークン数 (`GeneratedTokens`)** | `32` | `256` |
| **TG 計時対象トークン数** ※1 | `31` | `255` |
| **graphs reused**（参考・別指標） | `31` | `253` |
| **PP 速度 / 時間** | `91.56 tok/s` / `2,293.61 ms` | `483.20 tok/s` / `61,168.77 ms` |
| **TG 速度 / 時間** | `25.65 tok/s` / `1,208.76 ms` | `27.59 tok/s` / `9,243.50 ms` |
| **Context 初期化マーカー受信** ※2 | `50.184 s` (`50,184.019 ms`) | `151.492 s` (`151,492.453 ms`) |
| **Warmup マーカー受信** ※2 | `50.690 s` (`50,689.692 ms`) | `151.494 s` (`151,494.164 ms`) |
| **Context 構築開始→Warmup 開始報告（ネイティブログ差）** | — | 約 `0.166 s`（`sched_reserve`: `76.48 ms`） |
| **対象プロセス経過 (`ProcessSeconds`)** | `58.057 s` | `222.818 s` |
| **ラッパー全体所要 (`DurationSeconds`)** | `77.190 s` | `241.126 s` (`4.019 min`) |

- ※1: ビルド元 `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1` の `tools/server/server-common.h` にある `n_gen_steps()` と `n_gen_tps()`、および `tools/server/server-context.cpp` の `print_timings()` により、TG 計時対象ステップ数は生成トークン数から初回分を除いた `31`（H4）・`255`（H5）となる。`graphs reused`（`31` / `253`）はこれとは別の指標として扱う。
- ※2: `ram-events.jsonl` における `ContextInitialization` / `WarmupReported` の初回ログ行受信時刻から `TargetLaunchRequested` を差し引いた値であり、内部処理の厳密な境界ではない。両 run とも `stderr.log` にネイティブ `load time` 行は出力されていない。

---

## 6. メモリ・GPU・ページング・監視品質

| 区分 | H4 (`ctx2048`) | H5 (`ctx32768`) |
|---|---|---|
| **RAM 詳細 (`ram-detail.csv`)** | `262 件` (平均 `253.618 ms`, 最大 `284.778 ms`, 欠損 `0`), `Complete` | `900 件` (間隔統計 `ValidCount=899`, 平均 `256.808 ms`, 最大 `292.675 ms`, 欠損 `0`), `Complete` |
| **物理 RAM 最大使用 / 最低空き** | `7.803 GiB` (`PeakUsedMiB=7990.652 MiB`) / `23.844 GiB` | `7.841 GiB` (`PeakUsedMiB=8029.285 MiB`) / `23.806 GiB` |
| **コミット最大 (`ram-detail.csv`)** | `87.620 GiB` | `88.512 GiB` |
| **通常監視 (`resources.csv`)** | `24 件` (平均 `2.361 s`, 最大 `6.177 s`), `Partial`<br>使用最大 `7.650 GiB`, 空き最小 `23.997 GiB`, コミット最大 `87.499 GiB` | `88 件` (平均 `2.474 s`, 最大 `6.169 s`), `Partial`<br>使用最大 `7.491 GiB`, 空き最小 `24.157 GiB`, コミット最大 `88.504 GiB` |
| **ADLX (`gpu-metrics.csv`)** | `34 件` (平均 `2.000 s`), `Complete` ※3<br>VRAM `375 ~ 79,650 MB`, GPU 使用率 `0 ~ 58%`, 温度 `22 ~ 50 ℃`, 電力 `6 ~ 62 W` | `116 件` (平均 `2.000 s`), `Complete` ※3<br>VRAM `379 ~ 80,642 MB`, GPU 使用率 `0 ~ 100%`, 温度 `22 ~ 74 ℃`, 電力 `7 ~ 124 W` (`HighLoadPowerW=118.188 W`) |
| **GPU クロック (ADLX)** | コア `600 ~ 2,802 MHz` / VRAM `531 ~ 1,000 MHz` | コア `600 ~ 2,898 MHz` / VRAM `570 ~ 1,000 MHz` |
| **WDDM PID GPU Local / Dedicated 最大** | `78.056 GiB` / `77.417 GiB` | `78.927 GiB` / `78.382 GiB` |
| **ページング (`resources.csv`)** | `PagesInput`: `1.0 ~ 542,290.9 /s` (平均 `332,070.1 /s`)<br>`PageReads`: `1.0 ~ 1,500.7 /s` (平均 `791.0 /s`)<br>`PageFaults`: `11,726.4 ~ 704,816.8 /s` (平均 `440,818.6 /s`) | `PagesInput`: `0 ~ 506,155.5 /s` (平均 `94,206.1 /s`)<br>`PageReads`: `0 ~ 2,675.9 /s` (平均 `327.1 /s`)<br>`PageFaults`: `31.1 ~ 636,532.3 /s` (平均 `125,251.4 /s`) |

- ※3: `gpu_hotspot_c` と `total_board_power_w` はハードウェア/ドライバー非対応（`Supported=false`）のため全行欠損。その他 6 項目は欠損 0。

---

## 7. 安全確認・イベント監査

| 項目 | H4 前→後 | H5 前→後 |
|---|---|---|
| **競合 / 残留プロセス** | `0` → `0` (`ResidualPids=[]`) | `0` → `0` (`ResidualPids=[]`) |
| **P-MODE** | `Performance` → `Performance` (`PModeChanged=False`) | `Performance` → `Performance` (`PModeChanged=False`) |
| **RAM 空き (GiB)** | `26.093` → `25.945` (`WithinTolerance`) | `25.989` → `26.119` (`WithinTolerance`) |
| **コミット (GiB)** | `7.398` → `7.555` | `7.531` → `7.584` |
| **GPU Dedicated (GiB)** | `0.367` → `0.367` (ADLX `375 MB` 復帰) | `0.370` → `0.370` (ADLX `379 MB` 復帰) |
| **System / Application 新規イベント** | `70253` / `44715` 以降: 各 `0 件` (`OK`) | `70254` / `44715` 以降: 各 `0 件` (`OK`) |

---

## 8. H5 のモデルロード〜Context 報告遅延に関するログ確認

H5 では `ContextInitialization` マーカー受信まで `151.492 s` を要し、H4 の `50.184 s` より約 `101.3 s` 長かった。保存済みログから以下を確認した。

1. **最後の `model buffer size` 報告から `ContextInitialization` 報告までの時間**:
   - **H5**: `ram-events.jsonl` の `TensorLoadOrPlacement` 最終受信（`9,580.339 ms`）から `ContextInitialization` 初回受信（`154,900.976 ms`）まで **`145.321 s`**（`stderr.log` 内時刻でも `0.05.865.149` → `2.31.115.584` で約 `145.250 s`）。
   - **H4**: 同区間は **`44.012 s`**（`9,661.092 ms` → `53,673.435 ms`）。
2. **H5 のディスク読み取り速度・ページ入力の時間変化（`resources.csv`）**:
   - `0–60 s`（24 サンプル）: `DiskRead_MiBps` 平均 **`1,086.06 MiB/s`**、`PagesInput_PerSec` 平均 **`278,139.6 /s`**
   - `60–120 s`（24 サンプル）: `DiskRead_MiBps` 平均 **`58.35 MiB/s`**、`PagesInput_PerSec` 平均 **`14,999.1 /s`**
   - `120 s–Context`（13 サンプル）: `DiskRead_MiBps` 平均 **`281.92 MiB/s`**、`PagesInput_PerSec` 平均 **`72,281.4 /s`**
   - **低帯域区間の詳細（起動要求基準 `47.747～146.262 s`、40 サンプル）**: `DiskRead_MiBps` は `53.18～59.22 MiB/s`（中央値 **`58.225 MiB/s`**）、`TargetGPUDedicated_GiB` は **`76.892 GiB`** で一定、`TargetPrivate_GiB` は **`77.479～77.480 GiB`** で推移。その直後の `148.277 s`・`150.286 s` では `DiskRead_MiBps` がそれぞれ **`1,542.79 MiB/s`**・**`1,488.23 MiB/s`** に回復している。
   - ※ディスク・ページ入力指標はシステム全体の値であり、個別ファイル I/O やページファイル I/O の直接計測ではない。
3. **H5 の `ContextInitialization` 報告直前 14 秒間の中央値**（`03:12:11.932Z ~ 03:12:25.932Z`）:
   - `DiskRead_MiBps`: **`58.82 MiB/s`**（`resources.csv` 5 サンプル）
   - `PagesInput_PerSec`: **`15,312.9 /s`**（`resources.csv` 5 サンプル）
   - `ADLX gpu_usage_pct`: **`1 %`**（`gpu-metrics.csv` 7 サンプル: `1, 1, 1, 1, 1, 10, 10`）
4. **RAM ピークと Context 報告の時刻関係**:
   - **H5**: `RamDetail.PeakUtc`（`03:12:25.3457517Z`）は `ContextInitialization` 受信（`03:12:25.9319934Z`）の **`0.586 s` 前**。
   - **H4**: `RamDetail.PeakUtc`（`02:55:48.6943306Z`）は `ContextInitialization` 受信（`02:55:49.5655460Z`）の **`0.871 s` 前**。
5. **2026-11-26 既存モデルロード調査との比較（観測事実と推定の区別）**:
   - **共通点（観測事実）**: `B12651-MODEL-LOAD-BASELINE-20261126.md` の遅延例（R42・R34R3D）と同様に、序盤の高帯域読取後に `~58–60 MiB/s`・`~15,000 pages/s`・ADLX GPU `1%` の低帯域区間が現れ、物理 RAM 逼迫（空き `23.8 GiB` 以上）は観測されず、容量→Context 時間が延長した。H5 の PP/TG 性能低下の有無は同一条件の正常対照がないため未確定。
   - **相違点（観測事実）**: H5 は `llama-cli.exe`（`Context=32768`, `fa=auto`）であり 2026-11-26 の `llama-bench.exe`（`Context=8192`, `fa=on`）と条件が異なる。また H5 は RAM ピークが Context 報告の `0.586 s` 前（2026-11-26 正常対照 R44 の `0.316–1.291 s` 前に近い）であり、R42/R34R3D の約 `8.56 s` 前とは異なる。120 秒以降に読取平均が再上昇している点も異なる。
   - **限界（断定不可）**: 本ビルド（b12676）には `LLAMA_MODEL_LOAD_DIAG` の内部計時がないため、低帯域区間が OS/ストレージ側の読取停滞によるものか、GPU 転送イベント待ちによる次の読取開始遅延によるものかは断定できない。

---

## 9. 生ログの所在・再解析方法・過去の比較との違い

- **生ログ保管先（EVO-X2 `C:\llama-build\_logs\codex` 配下）**:
  - H4 Matrix: `matrix\20261128-115403-672-b12651-monitor-smokes`
  - H4 子 run: `20261128-115447-003-cli-vulkan-b12676-ctx2048-e4c08667866f`
  - H5 子 run: `20261128-120941-872-cli-vulkan-b12676-ctx32768-19f83241c073`
  - 再解析時は各ディレクトリの `conditions.json`, `result.json`, `summary.csv`, `resources.csv`, `gpu-metrics.csv`, `ram-detail.csv`, `ram-events.jsonl`, `stderr.log` を参照する。
- **過去計測との比較条件の違い**:
  - H4 vs `R34-vulkan-iq3-cli-M001`: 同一 EXE・モデル・入力・監視だが、OS 起動期間および直前の負荷履歴が異なる（H4 は再起動後、単発）。
  - H5 vs `UPSTREAM-B12651-32K-PP-TG-TRIAL-20261124.md`（Vulkan `PP 461.65 / TG 26.92 tok/s`）: 過去記録は **旧 IQ3 Original 3 シャード・b12660・RAM 詳細監視なし・P-MODE Unknown** であり、今回の **IQ3 PLE16・b12676・RAM 詳細監視 250ms あり・P-MODE Performance** とは条件が異なる。同一条件の正常対照がないため、H5 の PP/TG 性能低下の有無は確定できない。
- **独立レビュー確認**:
  - H5 の添付生ログについて ChatGPT による独立集計を実施し、主要数値およびレビュー前文書（SHA-256: `cb09ddf417091819133274fbaf25b64fdcd54ef5874f3387ff403bb998b48fc6`）との整合が一致した。なお、H4 の生ログは ChatGPT には未提供。

---

## 10. 欠損・制約・未確認事項

- ADLX の `gpu_hotspot_c`、`total_board_power_w` は非対応（全行欠損）。
- SSH セッション制約により、`BackgroundProbeStatus` の背景プロセス CPU 負荷および `DisplayEnvironmentAtFinish`（WMI/CIM）は取得不能。
- H4 の `InputAtLeast80Percent = false` は短文スモーク入力のため想定内。
- 両 run とも `stderr.log` にネイティブ `load time` 行の出力なし。
- ページファイル使用量、および H5 ロード低帯域区間の内部 API 別内訳（`ReadFile` vs `event_synchronize`）は未確認。
