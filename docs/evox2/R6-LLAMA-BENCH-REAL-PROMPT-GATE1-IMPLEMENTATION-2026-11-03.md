# r6 TOOL-001 Gate 1 — 実入力 llama-bench native移植結果

日付: 2026-11-03 (JST)  
状態: **Gate 1 ソース移植・静的レビュー完了。Windows build・実行検証は未実施。**  
作業ブランチ: `feature/r6-llama-bench-real-prompt-20261103`、分岐元main `7e2150bb99164bea87ee119c50bdbbbd9444561b`。  
詳細手順: [事前調査・移植計画](R6-LLAMA-BENCH-REAL-PROMPT-PORT-PLAN-2026-11-03.md)。  
引き継ぎ: [COMMON-005後](R6-POST-COMMON005-HANDOFF-AND-RESEARCH-2026-11-03.md) §5。

## 実装コミット

- `85dcddf75c86c4b8e55431258f86a72d92266180`: `feat(evox2): port r5 real-prompt llama-bench native mode to r6`
- `3f14e5c5c8f23c9d50048df9907851d58bbfa985`: `fix(evox2): preserve r6 fit-min-context sizing in real-prompt bench`

C++変更対象: **`tools/llama-bench/llama-bench.cpp` のみ**。r5の元commitは `4bf9af6fefa98622a65bd8d4c04ba73a02e27422`、実装済みドナー `r5/upstream-refresh-20261009`。Gate 1完成ソースのGitHub blob SHAは `cd551f9a67a0975423da022342cb694bd772f02f`。mainと比較したnative差分は**188行追加・8行削除**（GitHub compare、コード変更のみ）。GGML・QSA・Vulkan・HIP・MTP・COMMON-005は変更していない。

## 実装内容

- `-f/--prompt-file`、`--prompt-slice head-tail|head`、`-c/--ctx-size`をnative help/parse/defaultへ追加。`-fitc/--fit-ctx`は別フラグとして残す。
- `-f`指定時のUTF-8ファイル読込とモデルのvocabでの`common_tokenize(vocab, prompt_file_text, true, false)`。`-p`省略時のみファイル全文のtoken数を採用。`-p N`では選択後が正確にN token。
- `head-tail`: head `ceil(N/2)`+tail `floor(N/2)`、`head`: 先頭N、separator/padding/繰返しなし。tokenizeとslice構築は測定開始前。各timed repetitionとwarmupに同一配列を渡す。
- `cmd_params_instance::n_ctx`をPP、TG、PG各testに伝播し、明示context不足をエラーにする。`-c 0`または省略で既存の自動context sizing。`-f`で`-p`省略と`--fit-target`組合せはr5同様に明示的に拒否する。
- 既存random `test_prompt()`、generation `test_gen()`、depthのrandom prefill、JSON出力列、warmup/repetitionループ、モデル再利用処理は維持。
- **r6固有の非回帰配慮**: r5側の`-fitc`helpには「default: 4096」というmainと異なる文字列があったが、mainの`default: 0`を保持。fit実行時のcontextは`max(workload, explicit -c, inst.fit_min_ctx)`とし、r6の`--fit-ctx`最小値を落とさない。

## PowerShellラッパー

main `tools/evox2/benchmark/Measure-LlamaBench.ps1` のblob SHA `e6777e864ee362e4232422d171c84939af316042`を**変更なし**。元r5 wrapperとは別で、現mainには既に以下がある。

- `-InputKey/-InputFile/-PromptSlice/-Context`、実入力パス/byte数/SHA256、context modeの条件記録、ADLX/P-MODE・build Git identityの記録。
- `-c`と`-f/--prompt-slice`の旧バイナリ対応可否を`--help`から検査。今回追加したhelp書式は既存の正規表現に整合する。
- wrapperは常に`-p`を送るため、**native全文入力モードは直接CLIで確認**する。

`configs/local.psd1`はユーザー固有情報としてcommitしない。

## 静的レビュー（GitHub sourceに対する15検査、全PASS）

1. nativeの3種の追加オプションがparseに存在
2. native help表記がmain wrapper検知条件に合致
3. random初期値と`test_prompt()`の元ロジック保持
4. `-f`で`-p`なしの内部full-file sentinel解決
5. `common_tokenize`はchat templateを使わないraw入力
6. source token不足とcontext不足のエラーパスが存在
7. `head-tail`の奇数token分配が正しい
8. warmupとtimed双方でreal-token経路選択
9. depthのrandom prefill保持
10. r6 `fit_min_ctx`の保持
11. `--fit-target`と全文入力未解決の組合せを明示的に拒否
12. mainのwrapper blob SHAが不変
13. mainの`-fitc default: 0`help保持
14. mainとの差分にGPU/backend系ファイルが含まれない
15. C++ソースの行末余白なし

**重要:** これはsource上の静的確認であり、コンパイル成功やWindows実機の動作/性能を示すものではない。`git diff --check`、実機ソースcheckout状況、help実出力はGate 2で確認。

## 次：Gate 2 Windows Vulkan build、Gate 3 smoke

既存r6統合バイナリと公開b11908 previewを上書きせず、新build directoryに作る。作業ディレクトリには本ブランチをfetch/checkoutし、dirty treeやmainとの差を事前確認する。

```powershell
git fetch origin
git switch feature/r6-llama-bench-real-prompt-20261103
git pull --ff-only
git status --short
git diff --check main...HEAD

.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir .\build-vulkan-bench-real-r6 `
    -VulkanSdk C:\VulkanSDK\1.4.357.0 `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4

$bin = '.\build-vulkan-bench-real-r6\bin\Release'
& "$bin\llama-bench.exe" --help
& "$bin\llama-bench.exe" --version
```

`--help`で`-f/--prompt-file`・`--prompt-slice`・`-c/--ctx-size`を確認。`--version`の非対応のみでbuild失敗とは判定しない。model/bench path・compiler・commit・hashを記録。

その後のスモークは[計画書 §5](R6-LLAMA-BENCH-REAL-PROMPT-PORT-PLAN-2026-11-03.md)の3ケース：256-token random / real head-tail / real head。条件：`Context=1024, PromptTokens=256, GenerationTokens=0, Depths=0, Repetitions=1, Batch=256, UBatch=256, Threads=4, KvType=f16, ngl=999, ncmoe=0, fa=auto, NoWarmup`、同一バイナリ・同一モデル。旧r5の256-token速度を比較目標にしない。

Gate 4ではnegative、全文省略`-p`、複数`-p`、`-pg`、fit/minctx、randomのnon-regression、可能なら短い既知token配列のhead/head-tail同等性を検証する。**合格判定はWindowsログ確認後**。その後に64k以上のrandom/real PP比較とROCm判断へ進む。

## Gate 2 実機ビルド結果 — 2026-11-03

**判定：Vulkan Windows build / CLI help / version — PASS。Gate 3実入力スモークは未実施。**

ユーザーから提供された`(vulkan-bench)evox2-build.json`（生成時刻 2026-11-03 10:45:39 JST）、および`llama-bench.exe --help`/`--version`の実行出力を確認した。ファイル自体はGitHubへ追加しない（個別環境パス等を含む）。

| 項目 | 実機結果 |
| --- | --- |
| Build | b12032 / commit `c4ddd239ba01ee3e7f18986e98b10bd089553aae` |
| Branch / dirty | `feature/r6-llama-bench-real-prompt-20261103` / `false` |
| BuildIdentity | `Verified` — source stable / embedded commit一致 |
| Configuration | `Release`, `Vulkan`, `Ninja Multi-Config` |
| Compiler | Clang 20.1.8, Windows x86_64 |
| BuildDir | `C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-bench-real-r6` |
| Target | `llama-cli`, `llama-server`, `llama-bench`, `test-backend-ops` |
| GPU | AMD Radeon 8060S / Vulkan0, device-list exit 0 |
| Native help | `-f/--prompt-file`, `--prompt-slice`, `-c/--ctx-size`を表示 |
| Native version | `0.7.0-dev (build 12032, commit c4ddd239b)`, Clang 20.1.8 |
| `llama-bench.exe` SHA256 | `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f` |

`--help`のロードログではRPC、Vulkan、CPU-zen4 backendを読み込んだ。Vulkan deviceは8060S 1台、`fp16:1`、`bf16:1`、`fp4:0`、`KHR_coopmat`を検出。

**注意:** ビルドスクリプトの`Validation.Version`と`ListDevices`は`llama-cli.exe`による自動チェック。これとは別にユーザーが実行した`llama-bench.exe --help`および`--version`を確認済み。モデルをロードしたPP実入力処理の成功はまだ未確認であり、Gate 3が次のゲート。

### Gate 3 実機256-token smoke（提案）

r6の既存`Measure-LlamaBench.ps1`を使用し、新しい実行ファイルを`-LlamaBench`で直接指定してもよい。ローカル`local.psd1`の`ModelKey`と`InputKey`の既存名を用いる（下記はr5からの既知例）。`-InputKey`を付けないrandom対照が必須。3条件の出力ログを同一build・同一modelで採取する。

```powershell
$bin = '.\build-vulkan-bench-real-r6\bin\Release'
$common = @{
    LlamaBench = (Resolve-Path "$bin\llama-bench.exe").Path
    ModelKey = 'UnslothPle16'
    Context = 1024
    PromptTokens = @(256)
    GenerationTokens = @(0)
    Depths = @(0)
    Repetitions = 1
    Batch = 256
    UBatch = 256
    Threads = 4
    KvType = 'f16'
    GpuLayers = 999
    CpuMoe = 0
    FlashAttn = 'auto'
    NoWarmup = $true
}
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head-tail
.\tools\evox2\benchmark\Measure-LlamaBench.ps1 @common -InputKey '64k' -PromptSlice head
```

model/input keyが違う場合は、実機の`local.psd1`に登録済みのキーへ置き換える。絶対パスの`-ModelFile`/`-InputFile`を使ってもよい。受入条件は3 runともExitCode 0、native `n_prompt=256`、有効なJSON/CSV、real casesの入力SHA一致、randomが`InputIdentity=null`、slice/context metadataが期待値どおり、かつOOM/driver resetなし。256-tokenのtok/s値を性能改善指標にしない。

## Gate 3 実機smoke結果 — 2026-11-03

**判定：PASS（Random / real head-tail / real head 3ケース、すべてExitCode 0、各1有効行）。**

ユーザー提供の複数run ZIP `20261103-111602-549-bench-vulkan-b12032-ctx1024-c006631dc4fe.zip` 内の3ディレクトリを解析。`conditions.json`, `result.json`, `llama-bench.json`, `output.log`, `summary.csv`, `stderr.log`を照合。生ログZIPはこのリポジトリにcommitせず、各run ID/条件/値のみ記録する。

| 実行 (JST) | 種別 | ConditionId | PP tok/s | avg_ns | Status / ExitCode |
|---|---|---|---:|---:|---|
| 11:08 | Random | `2338e7f59fb4` | 73.208628 | 3496855600 | OK / 0 |
| 11:12 | real `head-tail` | `ca63c79231e2` | 386.068536 | 663094700 | OK / 0 |
| 11:16 | real `head` | `c006631dc4fe` | 385.298514 | 664419900 | OK / 0 |

実行条件：b12032 `c4ddd239b`（clean `feature/r6-llama-bench-real-prompt-20261103`）、`llama-bench.exe` SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`（3ケース一致）、Vulkan0 AMD Radeon 8060S、モデル `Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`、`-p 256 -n 0 -d 0 -r 1 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -c 1024 --no-warmup`。`ContextMode=ExplicitLegacyFlag`、native `n_prompt=256`、`n_gen=0`、`n_depth=0`、各run `NativeRowCount=1`、JSON parse exceptionなし。

実入力は同じ `nlp-survey-ch3-d7-b1.txt`（304931 bytes、SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`）で、`--prompt-slice`を`head-tail`/`head`と変更。`InputIdentity`/`InputSha256`と発行したnative `-f`/`--prompt-slice`引数が一致している。Randomではnative `-f`なし、`InputIdentity=null`、`PromptSlice=null`。

3ケースとも`PModeAtStart=Performance`、`PModeAtFinish=Performance`、`PModeChanged=false`。`ADLX`正常終了（samples 24/23/24）、background `PossibleNoise=false`、`ResourceSamples=0`（リソースモニタを使用せず）。stderrのbackend load以外にエラーなし。実入力とrandomの速度差は約5.27倍/5.26倍だが、**各1回の短いtoken列の結果であり、速度改善・再現性・実際のexpert活性分布は未検証**。後続のベンチ差・MoE入力依存性調査の動機として記録する。

### Gate 3で検証できた範囲 / 未検証

- 検証できた: 新機能付きnative EXEが実モデルのVulkan PPテストで正常終了、2種類の`--prompt-slice`オプションを受理、wrapperのinput source SHA・条件記録が一致、従来random経路も生きている。
- **未検証**: 選択後の実token IDs/切り出し位置のgolden比較、全文入力`-f`かつ`-p`省略、n_prompt奇数、明示context不足、short/empty/missing prompt file、fit-ctxとfit-target、`-pg`混合、warmupとtimedでの実token再利用、複数`-p`、64k以上の長文。
- 特に**native JSONには入力token ID列やslice方式列が出ない**。成功ログだけで正しいhead/tail内容を証明したとはみなさない。必要なら短いgolden textでtokenize結果を対照比較する。
- 次はGate 4の非正常系・回帰テスト。Windows環境ではモデルロードに時間がかかるので、CLI parser段階で止まるinvalid slice/空ファイル/存在しないファイルを先に実行し、重いモデルロードを伴うケースを段階的に試す。実装の修正がなければbuild再実施不要。
