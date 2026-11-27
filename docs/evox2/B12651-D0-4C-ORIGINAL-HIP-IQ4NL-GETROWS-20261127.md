# B12651 D0-4C追加検証 — ROCm UnslothOriginal 4k

**不合格。** 2026-11-27 JSTに個別承認された1回で、joined PLE相当のモデル容量がCPUからROCm_Hostへ移った。モデルロード中にROCmエラーとWindowsの仮想メモリ不足を観測し、context生成・短文応答に到達しなかった。現パッチの製品採用は見送る。前回の見送り記録は保存した。 [D0-4Cの開始判断](B12651-D0-4C-HIP-IQ4NL-GETROWS-20261127.md)

## 基準、モデル、実行条件

- 実行時branchは `experiment/hip-iq4nl-ple160`、HEADは `b74586a8d08b0e57774a140ad312d9c73ab803d6`。GitHub、実機worktree `C:\llama-build\automation\w55`、追跡先が一致し、実行前はクリーン。固定main `891e2605fbc0798228ffad2a69dd618f6cdab216` と標準Matrix・Measureの内容を照合した。
- b12696 Release、ビルド元 `044be892e12bffdfd06cfb698bf55e54582ae63a`、CLI SHA-256 `98da309636095a3be2d28b26fb19194968607b54b9cc042565875774a9dda6bf`、HIP DLL SHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c`、マニフェスト SHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`。`BuildIdentity=Verified`、`RuntimeDependenciesV1=Verified`。
- Windows 11、ROCm0 Radeon 8060S／gfx1151、UMA 96 GiB、Adrenalin 26.11.2（32.0.32029.2010）、TheRock 10.0.0、Performance。
- `UnslothOriginal` は旧IQ3 UD-IQ3_XXS joined PLE。先頭は `Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf`。3シャードのサイズ10,946,624／49,567,921,344／32,382,955,968 byteと各mtimeをD0-4Cの予算記録と照合した。
- Context 4,096、`AllocationOnly`、固定入力 `Reply with the word OK.`、生成上限32、GPU layers 999、CPU MoE 0、threads／threads-batch 4、batch 2048、ubatch 1024、K/V f16、FA auto、MTP/Fit/reasoning OFF、温度0.2、top-p 0.8、warmup有効、ログレベル5。DryRunと実行時 `conditions.json` の引数はモデルパスを除きD0-3と一致。通常監視2秒、ADLX 2000 ms、RAM詳細250 ms、詳細回復許容差128 MiB。 [D0-3の短文条件](B12651-D0-3-HIP-IQ4NL-GETROWS-20261127.md)

PlanOnlyで `D04C-Original-M001` だけを確認した。実行前の空きRAM 26.459 GiB、commit 8.224／127.647 GiB、WDDM Dedicated／Shared 0.461／0.072 GiB、GPU Engineカウンター合計0%。競合プロセスなし。過去のOriginal 4k実測に26.822 GiBを追加する比較でcommit 118.916 GiB、WDDM Dedicated 76.873 GiBと試算した。計数元は独立に比較した。この試算は短時間の割当ピークを保証できず、実測では後述のOS高水位が試算を超えた。想定される一時的な物理RAM逼迫を承認範囲に含め、既存の開始ゲートで起動した。

```powershell
Set-Location 'C:\llama-build\automation\w55'
$log = 'C:\llama-build\_logs\codex\d0-4c-original-audit-20261127'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan "$log\CLI.psd1" -LocalConfig "$log\local.psd1" -OnlyJob original -MaxRuns 1 -RunIdPrefix D04C-Original -StopOnError
```

## joined PLEの配置と停止位置

| モデルバッファ | 従来Original 4k | 修正版Original 4k |
| --- | ---: | ---: |
| CPU | 27,465.95 MiB | ログ行なし |
| CPU_Mapped | ログ行なし | ログ行なし |
| ROCm0 | 50,191.17 MiB | 50,191.17 MiB |
| ROCm_Host | 497.31 MiB | **27,963.27 MiB** |
| GPU層の報告 | 49/49 | 49/49 |

従来stderr 2859行は `per_layer_token_embd.weight`（IQ4_NL）を `ROCm_Host` からCPUへフォールバックしたと明記。修正版の250行には当該テンソルの作成行があり、同じ拒否理由のログ行はなかった。修正版2865–2866行でROCm_Hostが27,465.96 MiB増え、従来のCPUモデル容量と丸め内で一致した。joined PLEがホストバッファに載ったことを示す集計上の根拠で、個別テンソルの実buffer名やgatherの実行先は確認できなかった。

モデルバッファ行は、確保後のバッファオブジェクトの実名とサイズを出す。続く2867行では、**別の1.00 MiB**のページ固定確保が `unspecified launch failure` で失敗した。直後に `hipGetDevice(&current_device)` でも同じエラーが出て停止。標準のホスト割当関数は固定確保に失敗するとCPUバッファへフォールバックするが、この1 MiBのCPUバッファが処理で利用された証跡はない。モデル本体に対するHIP成功コードはログに出ない。ROCm_Hostの実バッファ報告と実装はモデル割当時のページ固定確保成功を支持する。全ページの常駐時間、後続エラーの根因、ページ固定との因果関係は未確認。 [バッファログの実装](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/044be892e12bffdfd06cfb698bf55e54582ae63a/src/llama-model.cpp#L2217) · [ホスト割当とフォールバック](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/044be892e12bffdfd06cfb698bf55e54582ae63a/ggml/src/ggml-cuda/ggml-cuda.cu#L1772)

`load_mode=none`。モデルロード開始はCLI相対0.439秒、バッファ報告は9.946秒、ROCmエラーは10.004秒。stdoutは `Loading model...` までで、モデルロード完了、context生成、グラフ実行、応答は確認できなかった。CLIは09:36:55.582 → 09:37:11.585 JST、16.003秒で異常終了。ネイティブ終了コード **3221226505（`0xC0000409`）** は `GetExitCodeProcess` から取得した。

## リソースと監査

| 実測 | 修正版Original 4k |
| --- | --- |
| 最小物理空き | **0.621 MiB**（CLI起動後8.438秒） |
| 空き1 GiB未満 | 39サンプル、1区間、CLI起動後6.134–15.860秒。最長観測幅 **9.726秒** |
| RAM詳細の瞬時commit最大／limit | 85.566／127.647 GiB |
| OS起動以降のcommit高水位 | 101.819 → **127.613 GiB**。実行中の11.005–11.256秒の間に更新を観測 |
| WDDMアダプターDedicated／Sharedピーク | 49.802／15.756 GiB |
| WDDM対象PID Dedicated／Sharedピーク | 49.340／15.744 GiB |
| ADLX VRAMピーク（生ログのMB） | 50,997 |
| Pages Input／Page Reads／Page Faults各ピーク（件/秒） | 5,812.6／1,075.4／1,749,365.7 |
| ディスク読取／書込ピーク | 22.33／253.29 MiB/s |

commit高水位は上限から約35.5 MiBの水準。250 msごとの瞬時値は同じピークを捕捉していない。Systemで09:37:06.713のApplication Popup **26**（仮想メモリ不足）と09:37:07.746のResource-Exhaustion-Detector **2004**を確認。2004は最大消費プロセスとして対象の `llama-cli.exe`（PID 17232）を報告した。派生CSVは `ram-detail.csv` のRAM・commitのbyte列を保持し、各時刻から `TargetLifecycle.StartedUtc` を引いた。物理空きの区間は有効サンプルの最初と最後で比較した。ディスクI/Oとページングはシステム値で、特定ファイルや転送量への帰属は未確認。 [RAMとcommitの派生時系列](d0-4c-original-20261127/ram-timeline.csv)

従来4kの通常監視の初回行は使用7.863＋空き55.784 GiBで、可視RAM約63.647 GiB。今回の31.647 GiBと異なり、計測間隔やサンプラーにも差がある。従来4kは配置の比較に用い、最小空きの差をD0の効果として扱わない。 [Stage 1の既存結果](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/891e2605fbc0798228ffad2a69dd618f6cdab216/docs/evox2/B12651-STAGE1-COMMON001-20261124.md)

| 終了監査 | 結果 |
| --- | --- |
| Measure／Matrix | `FAILED`／0 OK・1 NonOK、`Complete=False`、`StoppedEarly=True` |
| 終了前後の接続・監査 | SSH終了0は外部監査を回収できたことを示す。ネイティブCLIは異常終了 |
| 物理空き／commit増分／WDDM Dedicated増分 | 27.716 GiB／−0.071 GiB／0 GiB |
| RAM初回詳細回復 | `WithinTolerance`、終了後の最終空き27.788 GiB。context生成後の回復は未観測 |
| GPU初回詳細回復 | **`Unobserved`**。OS終了時刻より後のADLX 2行は472 MBだが、標準の終了検出境界09:37:15.495 JSTより前で、有効な事後サンプル数は0。128 MiB判定は未成立 |
| P-MODEとOS起動 | 前後Performance。OS起動時刻 `2026-11-26T11:45:51.5000000Z` で一致 |
| Windowsイベント | System 69919 → 69921、メモリ枯渇関連2件。Application 44227 → 44227、0件 |
| 残留 | CLI、通常監視、RAM詳細監視、MatrixのPIDおよびADLX名に残留なし |

RAM詳細92サンプル、ネイティブ欠損0。通常監視7サンプル、ADLX 12サンプル。数値上の終了時RAM・commit・Dedicatedは回復した。異常終了、メモリ枯渇イベント、GPU詳細回復の未成立により総合不合格。

## 採用判断と保全先

D0-2BのGPU数値5/5、IQ3 PLE16の4k～256kとGemma 4の合格は有効。今回、joined PLEのホストへの配置変化とロード失敗を実機で確認したため、**現行D0差分の製品採用は見送る**。別途承認を受ける場合は、joined PLEの従来のCPU配置を維持できる変更範囲をレビューし、split PLE16のGPU配置とjoinedの正常ロードを併せて検証する。NVIDIA CUDA実機、個別headの実buffer名、転送量、新カーネル単体性能も未検証のまま。承認された1回で停止した。

生ログは `C:\llama-build\_logs\codex` 配下。

- 今回のMeasure `20261127-093643-307-cli-rocm-b12696-ctx4096-b82ed489f63c`。stdout／stderr、条件・結果JSON、RAM詳細、通常監視、ADLX。
- Matrix `matrix\20261127-093600-337-d0-4c-original-smoke`。実行計画、開始ゲート、失敗結果。
- 監査 `d0-4c-original-audit-20261127`。Plan、LocalConfig、DryRun、前後資源、イベント差分、残留照合、予算と来歴。
- 従来Original 4k `20261124-165852-574-cli-rocm-b12671-ctx4096-a54242f85d44`。
