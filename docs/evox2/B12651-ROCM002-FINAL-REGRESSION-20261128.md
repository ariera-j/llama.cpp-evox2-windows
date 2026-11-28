# B12651 ROCM-002（D0-5）製品統合後の残存回帰検証（2026-11-28）

> 将来の GitHub 保存先: `docs/evox2/B12651-ROCM002-FINAL-REGRESSION-20261128.md`

## 1. 目的と結論

host 配置制限を含む ROCM-002 最終版（D0-5 製品統合版）の検証済みバイナリ `b12709` を用い、未実施であった Qwen3.8 旧 IQ3 PLE16 の長コンテキスト（64k / 128k / 256k、各 1 run）および Gemma 4 31B Q4_0 QAT（32k、1 run）の回帰検証を実施した。

**結論: 全 4 run 合格。**
- すべての run で `Status=OK`、`ExitCode=0`、全層 GPU offload（IQ3 PLE16: `49/49`、Gemma 4: `61/61`）、独立した CPU モデルバッファ行なし、`truncated = 0` を確認した。
- 比較基準（64k: D0-4D-5 `b12709`、128k/256k: D0-4B `b12696`、Gemma 4 32k: D0-4C `b12696`）に対して、**5% を超える PP/TG 速度低下は観測されなかった**（PP 差 `−1.32% ~ +0.11%`、TG 差 `−0.71% ~ +0.11%`）。
- バッファ容量・配置は 4 run とも過去基準と完全に一致し、実行中の空き物理 RAM 1 GiB 未満は全 run で 0 サンプル、終了後の資源回復・イベント監査・P-MODE 維持を通過した。

---

## 2. 来歴・バイナリ照合・実機環境

| 項目 | 実測・照合結果 |
|---|---|
| **GitHub `main`（ローカル参照）** | `d4d129db28449acc375e67155640fb2426db1ce7` |
| **製品ブランチ / SHA** | `codex/vulkan-manifest-cpu-variants-20261124` / `a650d641ee99198543697e1e3913c593059721f7`（クリーン） |
| **実験 worktree (`w55`)** | `experiment/hip-iq4nl-ple160` / `fe961fa0685e141b9967b31271aef7ab4afb99b4`（クリーン） |
| **検証済みバイナリ** | `C:\llama-build\automation\w55\build-rh\bin\Release\llama-cli.exe` (`b12709`, ビルド元 `e199e5f4319731071199d84f4f2e571fcaa7d413`, `Clang 23.0.0`) |
| **EXE / DLL / マニフェスト SHA-256** | `llama-cli.exe`: `538a12f93ed12ab2a639640d87aeb78582acca4d9d9c086fe5d6f9220f7c01de`<br>`test-backend-ops.exe`（※未実行）: `993c6f4b16c52d82d246f48c4e67eb5c751d703379ccdd39c8f34cc512e003f3`<br>`ggml-hip.dll`: `2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f`<br>`evox2-build.json`: `8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116` |
| **マニフェスト状態** | `SchemaVersion=1`, `BuildIdentity.Status=Verified`, `RuntimeArtifactStatus=Verified` |
| **実機・OS・ドライバー** | NucBox EVO-X2 / Windows 11 / `ROCm0: AMD Radeon(TM) 8060S Graphics` (`gfx1151`, UMA `96 GiB`, P-MODE `Performance`)<br>AMD Software `26.11.2`（表示ドライバー `32.0.32029.2010`）、TheRock `10.0.0` |
| **OS 最終起動 (`Kernel-General/12`)** | `2026-11-28T02:39:39.5000000Z`（全 4 run を同一 OS 起動期間内で実施） |
| **標準計測ツール blob** | `Invoke-BenchmarkMatrix.ps1` (`186c6136762939fe76dc72503d7c50e9f962f46e`), `Measure-LlamaCli.ps1` (`20c6809e04cc98f54c77bcdc9020a49203227269`), `Evox2.Benchmark.psm1` (`b4b31bd6395e726dbbd46dcc7c0ee4ba75d93420`), `Evox2.Common.psm1` (`205a80ec715e82cc357245c9fa162cd1a63e6f05`) |

- 製品基準 SHA（`a650d641...`）と `b12709` の実ビルド元 SHA（`e199e5f43...`）は D0-5 記録どおり別個のものとして区別した。
- `llama-cli.exe --list-devices` で報告される `110456 MiB` はランタイム報告値であり、UMA の実際の割当可能容量（`96 GiB`）およびホスト側物理 RAM 容量（OS 可視 `31.647 GiB`）とは区別して扱った。

---

## 3. 実行条件・モデル・入力・コマンド

D0-4A / D0-4B / D0-4C / D0-4D-5 と同一の Plan（`d0-4a-audit-20261127\CLI.psd1`, `d0-4b-audit-20261127\CLI.psd1`）および新規 LocalConfig（`C:\llama-build\_logs\codex\rocm002-final-regression-20261128\cli-local.psd1`）を使用し、`-PlanOnly` および `-DryRun` で実効引数の一致を確認したうえで 1 run ずつ順次実行した。

- **共通推論設定**: `-ngl 999 -ncmoe 0 -t 4 -b 2048 -ub 1024 -fa auto -lv 4 -ctk f16 -ctv f16 -fit off --cache-ram 0 --temp 0 --top-p 0.8 --reasoning off --jinja --single-turn --spec-type none -n 256 --seed 1234 --ctx-checkpoints 0 --no-display-prompt`（warmup ON、MTP OFF、評価対象外の高速化フラグ OFF）
- **共通監視設定**: 通常リソース監視 2 秒、ADLX `2,000 ms`（`C:\llama-build\adlx-gpu-monitor\build\bin\evox2-adlx-gpu-monitor.exe`）、RAM 詳細監視 `250 ms`（前 3 秒 / 後 5 秒、ピーク閾値 `64 MiB`、回復許容 `128 MiB`）、フェーズマーカー有効。

| Run | モデル | 入力ファイル（SHA-256） | Context |
|---|---|---|---|
| **Run 1 (64k)** | `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf` (`81,961,816,672 B`) | `nlp-survey-ch3-d7-b1.txt` (`2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`) | `65,536` |
| **Run 2 (128k)** | 同上 | `nlp-survey-ch3-d15-b1.txt` (`182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`) | `131,072` |
| **Run 3 (256k)** | 同上 | `nlp-survey-ch3-d31-b1.txt` (`63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788`) | `262,144` |
| **Run 4 (Gemma 4)** | `gemma-4-31B_q4_0-it.gguf` (`17,650,999,456 B`) | `nlp-survey-ch3-d3-b1.txt` (`1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601`) | `32,768` |

---

## 4. 性能比較（PP / TG・所要時間・基準差）

| 指標 | Run 1: IQ3 64k | Run 2: IQ3 128k | Run 3: IQ3 256k | Run 4: Gemma 4 32k |
|---|---:|---:|---:|---:|
| **Status / ExitCode** | `OK` / `0` | `OK` / `0` | `OK` / `0` | `OK` / `0` |
| **入力 / 生成トークン** | `61,789` / `256` | `126,253` / `256` | `255,181` / `256` | `29,379` / `256` |
| **PP 速度 (tok/s)** | **408.18** | **302.65** | **199.03** | **186.30** |
| **比較基準 PP (tok/s)** | 407.72 (`D0-4D-5`) | 303.23 (`D0-4B`) | 199.25 (`D0-4B`) | 188.79 (`D0-4C`) |
| **PP 基準比** | **+0.11%** | **−0.19%** | **−0.11%** | **−1.32%** |
| **TG 速度 (tok/s)** | **21.76** | **17.45** | **12.53** | **9.03** |
| **比較基準 TG (tok/s)** | 21.75 (`D0-4D-5`) | 17.54 (`D0-4B`) | 12.62 (`D0-4B`) | 9.02 (`D0-4C`) |
| **TG 基準比** | **+0.05%** | **−0.51%** | **−0.71%** | **+0.11%** |
| **PP / TG 時間 (秒)** | `151.376` / `11.721` | `417.152` / `14.614` | `1,282.146` / `20.359` | `157.695` / `28.240` |
| **ロード開始→Context 構築 (秒)** | `45.652` | `43.849` | `44.162` | `8.869` |
| **ラッパー全体所要 (秒)** | `229.071` | `495.077` | `1,367.078` | `215.093` |

※各 1 run の比較であるため、微小な速度差の原因をパッチや環境差に断定しない。

---

## 5. バッファ配置・メモリ・GPU・I/O・出力確認

### 5.1 内部バッファ配置（`stderr.log`）

| バッファ (MiB) | Run 1: IQ3 64k | Run 2: IQ3 128k | Run 3: IQ3 256k | Run 4: Gemma 4 32k |
|---|---:|---:|---:|---:|
| **GPU offload 層** | `49 / 49` | `49 / 49` | `49 / 49` | `61 / 61` |
| **独立 CPU / CPU_Mapped モデル** | 行なし | 行なし | 行なし | 行なし |
| **`ROCm0` モデル** | `77,657.12` | `77,657.12` | `77,657.12` | `16,818.28` |
| **`ROCm_Host` モデル** | `497.31` | `497.31` | `497.31` | `1,102.50` |
| **`ROCm0` KV 合計** | `1,920.00` (`1,536 + 384`) | `3,840.00` (`3,072 + 768`) | `7,680.00` (`6,144 + 1,536`) | `4,160.00` (`2,560 + 1,600`) |
| **`ROCm0` recurrent state (RS)** | `112.57` | `112.57` | `112.57` | — |
| **`ROCm0` / `ROCm_Host` compute** | `453.62` / `73.19` | `660.41` / `106.13` | `1,127.41` / `172.01` | `404.05` / `152.05` |

全 4 run で対応する過去基準（D0-4D-5 / D0-4B / D0-4C）と 0.01 MiB 単位まで完全に一致した。

### 5.2 メモリ・WDDM・ADLX・I/O・GPU 指標

| 指標 | Run 1: IQ3 64k | Run 2: IQ3 128k | Run 3: IQ3 256k | Run 4: Gemma 4 32k |
|---|---:|---:|---:|---:|
| **実行中 最小空き RAM (GiB)** | `24.104` | `23.872` | `24.012` | `23.731` |
| **ロード / PP / TG 最小空き RAM (GiB)** | `24.104` / `24.487` / `24.491` | `23.872` / `24.421` / `24.423` | `24.012` / `24.291` / `24.291` | `23.731` / `24.166` / `24.196` |
| **空き 1 GiB 未満サンプル数** | `0` | `0` | `0` | `0` |
| **コミットピーク / 上限 (GiB)** | `88.975` / `127.647` | `91.146` / `127.647` | `95.483` / `127.647` | `30.980` / `127.647` |
| **WDDM アダプター Dedicated / Shared ピーク (GiB)** | `79.244` / `0.707` | `81.325` / `0.739` | `85.540` / `0.804` | `21.596` / `1.367` |
| **WDDM 対象 PID Dedicated ピーク (GiB)** | `78.854` | `80.935` | `85.150` | `21.206` |
| **ADLX VRAM ピーク (`gpu_vram_mb`)** | `81,145` | `83,277` | `87,593` | `22,113` |
| **Pages Input / Page Reads / Page Faults ピーク (/s)** | `566,016.5` / `1,997.4` / `716,421.7` | `585,047.2` / `2,083.7` / `739,728.7` | `594,155.6` / `2,213.1` / `764,994.5` | `576,135.4` / `2,105.7` / `747,215.3` |
| **ディスク読取 / 書込ピーク (MiB/s)** | `2,210.94` / `15.85` | `2,285.34` / `3.31` | `2,319.86` / `2.16` | `2,250.53` / `0.60` |
| **ADLX PP 中央値（クロック MHz / 温度 °C / 電力 W）** | `2,883.0` / `74.0` / `120.0` | `2,884.0` / `81.0` / `120.0` | `2,889.0` / `83.0` / `119.0` | `2,818.0` / `77.5` / `105.0` |
| **ADLX TG 中央値（クロック MHz / 温度 °C / 電力 W）** | `1,967.0` / `46.0` / `50.0` | `2,884.0` / `71.0` / `95.0` | `2,891.0` / `73.0` / `99.5` | `2,898.5` / `63.5` / `83.0` |

### 5.3 128k・256k 開始前容量判定と実測

- **128k 開始前容量判定（Run 1 実測基準）**: Run 1（64k）の内部バッファ実測（`ROCm0` モデル `77,657.12 MiB`、KV `1,920.00 MiB`、RS `112.57 MiB`、compute `453.62 MiB`）に対し、128k では KV が `3,840.00 MiB`（`+1,920.00 MiB = +1.875 GiB`）、compute が最大でも 2 倍（`907.24 MiB`, `+0.443 GiB`）と見積もり、既知 GPU バッファ合計を **`80.583 GiB`**（UMA `96 GiB` に対して十分余裕あり）と判定して Run 2 を開始した。実測の 128k compute は `660.41 MiB`、WDDM Dedicated ピーク `81.325 GiB`、コミットピーク `91.146 GiB`（上限 `127.647 GiB`）、最小空き RAM `23.872 GiB` であった。
- **256k 開始前容量判定（Run 2 実測基準、`budget-256k.json`）**: Run 2（128k）の実測値（KV `3,840 MiB`、`ROCm0` compute `660.41 MiB`、WDDM アダプター Dedicated ピーク `81.325 GiB`、コミットピーク `91.146 GiB`、最小空き RAM `23.872 GiB`）を基準に、256k 増分（KV `+3,840 MiB`、compute 上限見積 `+660.41 MiB`、計 `+4.395 GiB`）を加算して事前判定を実施し、`PASS` を確認後に Run 3 を実行した。
  - 既知 GPU バッファ見積: `84.737 GiB`（UMA `96 GiB` 以下）
  - WDDM Dedicated ピーク見積: `85.720 GiB` → 実測 **`85.540 GiB`**
  - コミットピーク見積: `95.541 GiB`（上限 `127.647 GiB`）→ 実測 **`95.483 GiB`**
  - 最小空き RAM 参考見積: `19.477 GiB` → 実測 **`24.012 GiB`**

### 5.4 出力内容の比較

- **64k**: `OutputFingerprintSha256`（`1b228eee49b9e007e7bdedf72df6e7f42caf59b46f97a1ce9954742db2a22fee`）が D0-4D-5 と **完全一致**。
- **128k / 256k / Gemma 4 32k**: 基準（`b12696`）とは `OutputFingerprintSha256` が異なったが、いずれも同一日本語論文の内容（評価表現辞書の構築手法 3 分類・PMI・文脈一貫性ブートストラップ・文書分類等）を日本語で要約しており、ROCm 環境で既知の出力非決定性の範囲内であることを確認した。

---

## 6. 終了後の安全監査・監視データの信頼性

| 監査項目 | Run 1 (64k) | Run 2 (128k) | Run 3 (256k) | Run 4 (Gemma 4 32k) |
|---|---|---|---|---|
| **RAM 空き 前→後 (GiB)** | `25.963` → `25.952` | `25.953` → `25.948` | `25.953` → `25.965` | `25.939` → `25.909` |
| **コミット 前→後 (GiB)** | `7.868` → `7.799` | `7.811` → `7.802` | `7.803` → `7.790` | `7.827` → `7.845` |
| **RAM 詳細回復 / サンプル / 欠損** | `WithinTolerance` / `864` / `0` | `WithinTolerance` / `1,919` / `0` | `WithinTolerance` / `5,363` / `0` | `WithinTolerance` / `807` / `0` |
| **ADLX VRAM 回復 (MB) / 状態** | `399` → `399` / `Complete` | `399` → `399` / `Complete` | `399` → `399` / `Complete` | `399` → `399` / `Complete` |
| **P-MODE 前→後** | `Performance` → `Performance` | `Performance` → `Performance` | `Performance` → `Performance` | `Performance` → `Performance` |
| **残留プロセス** | なし | なし | なし | なし |
| **System / App 新規イベント** | `0` / `39`（詳細は下記） | `0` / `1`（詳細は下記） | `0` / `0` | `0` / `0` |

- **Run 1 (`44783..44821`, 39 件) の WER イベント根拠**: 39 件すべて `Windows Error Reporting`（ID `1001`、情報レベル、発生時刻 `17:33:32`〜`17:33:33`）。このうち **38 件**は添付ダンプ名に過去の日付（`ResourceTimeout-20260522-2218.dmp`、`WATCHDOG-20260720-1604.dmp`〜`WATCHDOG-20261121-2127.dmp`、`081526-15640-01.dmp`〜`112126-11312-01.dmp`）を含み、過去のダンプ再処理と確認できた。残り **1 件**（`RecordId 44784`、`AppTermFailureEvent`）は `P1` が空で添付ファイル名が `WER.*.tmpatk.kdmp`（日付を含まない一時名）のため、メッセージ単体では発生日時は未確認だが、同時間帯の `System` 新規イベントは `0` 件であり Run 1 自体は `ExitCode=0`・`Status=OK` で完了した。
- **Run 2 (`44822`, 1 件) の `RADAR_PRE_LEAK_64`**: `2026-11-28 17:39:58`（Run 2 実行中 `17:36:13〜17:45:08`）に `Windows Error Reporting`（ID `1001`、情報レベル）で `Event Name: RADAR_PRE_LEAK_64`, `P1: llama-cli.exe`（ダンプ添付なし）が記録された。Windows のメモリリーク予兆診断の情報イベントであり、Run 2 は `ExitCode=0`、`Status=OK` で完了し、終了監査で `RESIDUAL_PROCS=NONE`、`RamDetailSystemRecovery=WithinTolerance`（空き RAM `25.953 → 25.948 GiB`、コミット `7.811 → 7.802 GiB`、ADLX VRAM `399 → 399 MB`）と資源回復を確認した。
- **監視データの制約**: `ADLX` の `gpu_hotspot_c` と `total_board_power_w` はハードウェア/ドライバー非対応のため全行欠損。`resources.csv` はネイティブ RAM・プロセス・システム PerfMon 全件 `Complete` だが、PID GPU カウンターの一部と背景 CPU 比較（`CpuUnavailable`）に欠損があるため総合判定は `Partial`。欠損値は実測ゼロに置換していない。

---

## 7. ログ保全先・未解決事項・次工程への引き継ぎ

- **生ログ保全先（EVO-X2 `C:\llama-build\_logs\codex`）**:
  - 監査設定・256k 容量判定: `rocm002-final-regression-20261128`（`cli-local.psd1`, `budget-256k.json`）
  - Run 1 (64k): `20261128-172946-127-cli-rocm-b12709-ctx65536-5c176fdfd0a6`（Matrix: `matrix\20261128-172902-674-d0-4a-iq3-ple16-64k`）
  - Run 2 (128k): `20261128-173613-199-cli-rocm-b12709-ctx131072-119694e75e0a`（Matrix: `matrix\20261128-173529-553-d0-4b-iq3-ple16-longctx`）
  - Run 3 (256k): `20261128-174633-067-cli-rocm-b12709-ctx262144-7c2d4ef1849b`（Matrix: `matrix\20261128-174549-436-d0-4b-iq3-ple16-longctx`）
  - Run 4 (Gemma 4 32k): `20261128-181121-410-cli-rocm-b12709-ctx32768-a4724adaf638`（Matrix: `matrix\20261128-181037-772-d0-4a-iq3-ple16-64k`）
- **未解決事項**:
  - 長コンテキストでの PP 低下傾向（64k `408.18` → 128k `302.65` → 256k `199.03 tok/s`）は ROCM-002 最終版でも従来どおり観測されており、原因調査は別タスクとする。
  - CUDA / MUSA 環境でのビルド・実機確認、および `b12709` 以降の新規製品ビルドは本タスクの対象外。
- **次工程への引き継ぎ**:
  - ROCM-002（D0-5）製品統合後の残存回帰（IQ3 PLE16 64k / 128k / 256k、Gemma 4 31B Q4_0 QAT 32k）はすべて合格し、基準データが確定した。
  - 次工程は **ROCmFP4 FAST HIP-1** とし、製品ブランチ `codex/vulkan-manifest-cpu-variants-20261124` の SHA `a650d641ee99198543697e1e3913c593059721f7` を出発点として別承認で着手する。
  - HIP 対応完了時点で、`batch=2048` 固定・`ubatch 1024 / 2048` の比較と、常用 `llama-server` 設定の再評価を予定している。
