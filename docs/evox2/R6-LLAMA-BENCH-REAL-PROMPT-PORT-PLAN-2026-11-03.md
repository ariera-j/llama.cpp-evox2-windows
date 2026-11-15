# r6 TOOL-001 — llama-bench 実入力対応：r5との差分監査と移植計画

日付: 2026-11-03 (JST)  
状態: **静的調査・移植計画のみ。C++/PowerShellコード変更なし、ビルド・実機測定未実施。**  
作業ブランチ: `feature/r6-llama-bench-real-prompt-20261103`（mainから分岐）。  
起点main: `7e2150bb99164bea87ee119c50bdbbbd9444561b`。公開b11908 preview tag・既存COMMON-005 b12013実測バイナリは変更しない。

## 1. 参照・移植元

- [2026-11-03引き継ぎ](R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md) §5：TOOL-001が次作業、ツール範囲に限定、Vulkan first。
- [r5実入力移植・Windows smoke](R5-LLAMA-BENCH-REAL-PROMPT-PORT-2026-10-09.md)：r5 `r5/upstream-refresh-20261009`、元実装commit `4bf9af6fefa98622a65bd8d4c04ba73a02e27422`、b11526/256-token random・head-tail・head smoke PASS。
- [r4原設計と入力依存性](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md)：raw tokenize、-p指定厳守、QSA入力依存の背景。
- 本監査の読み取り対象はGitHub上の**現main/r6 combined/r5**の実ファイル。main headが更新された場合は作業開始前にHEADと差分を再確認。

## 2. 2026-11-03 静的差分監査（ファイル別SHA）

| ファイル | main | r6/combined-20261028 | r5/upstream-refresh-20261009 | 判定 |
| --- | --- | --- | --- | --- |
| `tools/llama-bench/llama-bench.cpp` | `96ae4870ff3c7b7ac4b78a0efb75ca43d3807612` | 同左 | `5f7edd28beee964439615420ca0f943a274a02ba` | native実入力**未移植** |
| `tools/evox2/benchmark/Measure-LlamaBench.ps1` | `e6777e864ee362e4232422d171c84939af316042` | `ca6b662ea1f44397fd1a22a5df235e4f8f3da678` | `ca6b662ea1f44397fd1a22a5df235e4f8f3da678` | wrapper実入力部分**移植済み**。mainに追加保護あり |

**重要:** r5の`Measure-LlamaBench.ps1`をmainに上書きしない。main固有の`--help` probe（概ね247–267行）は、-cと-f/--prompt-sliceを知らない旧benchを明示的に拒否し、-fitcと-cの誤用を防ぐ。移植後のhelp表示が既存正規表現に合うことを検査する。通常random modeはhelp probeを強制しない。

main wrapperには既に`-InputKey/-InputFile/-PromptSlice/-Context`、ファイルパス・byte数・SHA-256・context modeのcondition fingerprint、`conditions.json`、`summary.csv`、`result.json`、ADLX/P-MODEなどのrun provenanceが存在する。既存コードの再移植不要。必要な変更は検証で実際の不整合が出たときに限定する。

## 3. native側：具体的移植ポイント

対象は主に`tools/llama-bench/llama-bench.cpp`一ファイル。r5全ファイル・全commitの機械的置換/mergeは不可。

1. **CLI引数・初期値・help:** `cmd_params`に`prompt_file`、`prompt_slice`、`n_ctx`。初期値は空、`head-tail`、0。`-f/--prompt-file`、`--prompt-slice head-tail|head`、`-c/--ctx-size`。負のcontext、無効slice、欠落引数を拒否。現在の`-fitc/--fit-ctx`とは別物。
2. **-p省略時の全文:** ファイル指定なしは既存`-p` default=512のまま。ファイル指定かつ`-p`なしは、r5同様に内部sentinel（`-1`）を使い、モデルロード・tokenize後に実数へ確定する。整数検証と出力件数・context生成の順序に注意。wrapperは現状`-p`を常に指定するため、**全文モードはnative直接呼び出しで検証**。
3. **context形成:** `cmd_params_instance`へ`n_ctx`を追加し、PP/TG/PGの全instanceで引き回す。`to_llama_cparams()`は`n_ctx > 0 ? n_ctx : n_prompt + n_gen + n_depth`。必要トークン総数より`-c`が小さければ失敗、パディング・自動拡張はしない。`--fit-target/-fitc`既存分岐では `max(workload, requested_context, fit_min_ctx)` の要件を整理し、`-f`＋`-p`省略＋fitの未解決組合せはr5と同様、明示的に拒否してよい（黙って誤計測しない）。
4. **raw入力準備:** ファイルをbinaryで読み込み（空・読込失敗拒否）、各モデルのvocabで`common_tokenize(vocab, raw_text, true, false)`（BOS/Jinjaとの差に注意）。サイズ上限・0 token・指定`-p`がraw token数を超える場合を明示的に拒否し、繰返し・paddingしない。ファイルのtoken列は計測区間外で準備、timed repetition中にtokenizeしない。
5. **slice:** `head`なら先頭N、`head-tail`なら先頭`ceil(N/2)`＋末尾`floor(N/2)`、separatorなし。奇数N、全文N、複数`-p`で同一ファイルからそれぞれ独立に切り出すこと。
6. **PP経路:** `test_prompt_tokens()`を追加し、`common_batch_get_one`＋`llama_process(... LLAMA_PROCESS_TYPE_DECODE ...)`の既存実行方法を踏襲。warmup・timed repetition双方に同一tokensを渡す。random用`test_prompt()`、depthのrandom prefill、generation、出力/logits batch動作、試行回数、JSON schemaは変更しない。

**API/回帰上の注意:** mainの`cmd_params_instance::to_llama_cparams()`は単純にworkload合計を使用する。r5は`n_ctx`で置換する設計。mainのmodel reuse、`common_fit_params`、`ctx_state`、`-pg`のループ構成を保って必要箇所だけ差し込む。sourceの行数や文脈はr5とずれている。r5は`<fstream>`追加があるためincludeも確認。

## 4. スコープと非目標

**変更予定**: 原則 `tools/llama-bench/llama-bench.cpp` と本計画／検証記録。`Measure-LlamaBench.ps1`はmainを維持し、明確に再現する不具合がある場合のみ最小修正。`tools/evox2/benchmark/configs/local.psd1`はignore対象であり**コミットしない**。

**変更禁止／別タスク:** ggml、Vulkan/ROCm shader、COMMON-005 (`QWEN4EXP_QSA_GATHER`)、QSA unionのstats追加、MTP、model loading本体、router、b11908 preview ZIP、upstream refresh。raw tokenize入力はllama-cli/serverのchat templateと同一ではない。実測PPの一致もリクエスト経路・logit完全一致を保証しない。

## 5. 段階的実装・受入ゲート

| Gate | 作業 | 合格条件 |
| --- | --- | --- |
| **0 — 静的監査（本書）** | r5 donor、main/native、main wrapper、引き継ぎを照合 | 移植範囲確定、main既存保護を維持。本ゲートはGitHubファイル確認済み。ビルドは未実施 |
| **1 — 最小実装/レビュー** | nativeにCLI、tokenize、slice、context、PP入力切替を移植。1 commitに分離 | mainからの差分はツール/ドキュメントのみ。`git diff --check`、random既存経路に変更なし、型/overflow/context条件の確認 |
| **2 — Windows Vulkan build** | **新しい専用build directory** でClang/Vulkanをビルド | `llama-bench.exe --help`に`-f`,`--prompt-slice`,`-c`。`--version`が対応ならbuild identity確認。既存release/buildを上書きしない |
| **3 — 256-token smoke** | 同一バイナリ・同一モデル、`-p 256 -n 0 -d 0 -r 1 -c 1024 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -ctk f16 -ctv f16 -fa auto --no-warmup`。wrapperで①random（Inputなし）②`-InputKey 64k -PromptSlice head-tail`③`-InputKey 64k -PromptSlice head` | 3ケースがExit 0、native JSON/summary/conditions/resultが有効、n_prompt=256、realは同一ファイルSHAとslice・c=1024、randomは実入力引数なし |
| **4 — negative/regression** | 空/短すぎる/存在しないファイル、無効slice、`-c < needed`、`-p`省略全文、複数`-p`、奇数N、warmupあり/なし、randomをテスト | 適切な非0 exit、silent paddingなし。全文Nの実token数・contextが一致。旧random結果とJSON schemaが破綻しない |
| **5 — 実験への橋渡し** | 64k実文書/randomの限定対照→必要なら128k/256k、Vulkan first | 本番入力のSHA、actual n_prompt、model/build、P-MODE/ADLX、KV、flagsを保存。時間・メモリ・出力回帰確認後にROCm build/比較を決定 |

Windows build参考：`tools/evox2/build/Build-Vulkan.ps1 -BuildDir .\build-vulkan-bench-real-r6 -VulkanSdk C:\VulkanSDK\1.4.357.0 -LlvmBin 'C:\Program Files\LLVM\bin' -Parallel 4`。パスはユーザー環境に合わせる。wrapperは`BuildKey`にこの新しいバイナリを指定する（`local.psd1`のみ）。

smoke用PowerShell例（既存キー名はローカル設定に合わせる）：

```powershell
$common = @{
    BuildKey = 'R6BenchRealVulkan'; ModelKey = 'UnslothPle16'
    Context = 1024; PromptTokens = @(256); GenerationTokens = @(0)
    Depths = @(0); Repetitions = 1; Batch = 256; UBatch = 256
    Threads = 4; KvType = 'f16'; GpuLayers = 999; CpuMoe = 0
    FlashAttn = 'auto'; NoWarmup = $true
}
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head-tail
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head
```

数値の大小を256-token/1回のsmokeから最適化効果と解釈しない。r5の256-token smoke（random 86.034、real head-tail 383.022、head 390.620 tok/s）は**旧環境の機能確認**でありr6の性能目標値ではない。64k以上の速度比較は条件を揃え繰返し測定する。

## 6. 調査から判明した注意点と決めること

- **wrapperはr5と同一ではない**: main側に旧native未対応時のhelp guardが追加されている。旧r6 combined/r5 wrapperへ戻さない。
- **nativeはr6 combinedとmainでblob SHAが同一**: 新機能はない。`-fitc`は`-c`の代替にならない。
- **実token数**: wrapperの`PromptTokens`は**要求値**、nativeが出す`n_prompt`は実行件数。raw source token数/選択token配列のSHAまで記録する機能はr5の必須実装ではない。必要なら別診断拡張として検討。smokeではstderrに出るavailable/usingを確認する。
- **全文モード**: wrapperは既存API上必ず`-p`を出す。native全文テストは直接実行で確認し、ラッパーに新しいスイッチを追加するのは別判断。
- **fitとの組合せ**: 明示context/実入力の動作とfitを混同せず、未対応組合せは拒否。通常benchの既存fit経路は非回帰確認。
- **出力同等性**: 実入力はraw textでchat templateなし。`-d` prefillやgenは従来randomのまま。`-pg`の実文書PPは限定テストしてから利用する。
- **未実施**: ローカルworktreeとの差分確認、Windowsコンパイル/スモーク/性能、機能移植のcommit。次はGate 1。

## 7. 実装時のcommit分割

1. C++ native TOOL-001最小移植（機能・既存random non-regression）。
2. build/smoke/negative結果の検証記録（必要な場合のみwrapperの局所修正を別commit）。
3. 合格後mainへの反映／公開手順は別途判断。性能研究・ROCm・mask/Expert解析は後続タスク。
