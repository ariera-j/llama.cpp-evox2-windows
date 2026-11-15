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

## Gate 4 Fast + Core 実機結果 — 2026-11-03

**結果：Fast 5/5 PASS、Core 自動判定 8/9 PASS、手動ログ照合ではCore 9/9が期待どおり動作（合計14/14）。** Gate 4 Extended 2ケース・golden token ID比較・fit正常系は未実施。

入力ZIP：`evox2-bench-gate4-20261103-113622.zip`（Fast）および`evox2-bench-gate4-20261103-113643.zip`（Core）。いずれも同一`llama-bench.exe` SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`、モデル`Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf`、既存実入力`nlp-survey-ch3-d7-b1.txt` SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`。短文テスト用ファイル`full-utf8.txt`は1356 bytes / SHA256 `dc9db5d3f3099cf2af8be914edd8c2794ffb2322eb0144e428a5fc183cf7a1b4`（ZIP内バイト列を独立検証）。PowerShell 5.1.26100.9818、scriptはP-MODE/ADLX状態を採取せず。生ZIPはrepoにcommitしない。

### Fast — 5件全PASS

| Case | 内容 / 実行結果 |
| --- | --- |
| F01 | 未知の`--prompt-slice` → ExitCode=1、invalid parameter、PASS |
| F02 | `-c`負値 → ExitCode=1、invalid parameter、PASS |
| F03 | 存在しない`-f`ファイル → ExitCode=1、failed to open prompt file、PASS |
| F04 | 空の`-f`ファイル → ExitCode=1、prompt file is empty、PASS |
| F05 | `-f`かつ`-p`省略、`-fitc 512` → ExitCode=1、fit/full-file拒否、PASS |

F05診断文字列は`--fit-target with --prompt-file and no -p ...`となるが、実際のケースは`-fitc 512`のみ。実装上`do_fit`がfit-targetまたはfit-ctxのどちらでも成立するため、**拒否は想定どおり、メッセージはやや不正確**。後続の表示改善候補（この検証ではコード変更なし）。

### Core — 自動8/9、ログ再照合で9/9正常

| Case | 実行結果 | 判定 |
| --- | --- | --- |
| C01 | source token 1に対して`-p 256` → ExitCode=1、token不足診断 | PASS |
| C02 | 実入力256 tokensに対して`-c 128` → ExitCode=1、context不足診断 | PASS |
| C03 | `-p`省略で短いUTF8全文 → ExitCode=0、JSON 1行、`n_prompt=360`、samples 1、進捗には`360 available/using 360 (head)` | **native PASS / 検証script FALSE** |
| C04 | `-p 257 --prompt-slice head` → ExitCode=0、JSON 1行、samples 1 | PASS |
| C05 | `-p 257 --prompt-slice head-tail` → ExitCode=0、JSON 1行、samples 1 | PASS |
| C06 | 複数`-p 255 -p 256` → ExitCode=0、JSON 2行、各samples 1 | PASS |
| C07 | `-p 257 -r 2`、warmupあり → ExitCode=0、JSON 1行、samples 2、進捗でwarmup/1of2/2of2を確認 | PASS |
| C08 | `-pg 32,4` → ExitCode=0、`n_prompt=32`、`n_gen=4`、samples 1 | PASS |
| C09 | `-f`なしrandom `-p 257` → ExitCode=0、`n_prompt=257`、samples 1 | PASS |

**C03の自動判定FAILの原因：PowerShellの`stderr.log`改行処理。** `gate4-summary.csv`には`progressMatch=False`として記録された。しかし生`stderr.log`（UTF-16 LE）では、長いWindows入力パスを含む進捗表示が改行され、`360 availabl`と次行の`e tokens, using 360 (head)`に分断されていた。JSONでは実際の`n_prompt=360`・ExitCode=0・`samples_ns=[1010828300]`を確認。これは本体ではなく**スモーク検証器の長いログ行への非対応による誤検知**。再実行は不要。今後スクリプトでは折り返しを考慮するか短いログパスを利用する。

C03を除く陽性8ケースも、出力JSONの`build_commit=c4ddd239b`・`build_number=12032`・expected `n_prompt/n_gen`・samples件数を独立確認。F01/F02のusage標準出力はJSONではないが、エラーケースのため正常。C07にはベース引数`-r 1`に加えて`-r 2`を後置しており、native実際のサンプル数は2（最後の指定が有効）。`--progress`と実サンプルからwarmupありで動作したことを確認できるが、token IDsの同一性はまだ証明できていない。

### 残件 / 今後の方針

1. Gate 4 Extended：`-c 0` 自動context、実入力＋random depthなどの補足2ケースを実行し確認。
2. 未検証の`--fit-target/-fitc`正常系、明示`-c`と組合せたfit minimumの挙動、head/head-tailのgolden token ID同等性は別の小テストとして扱う。単なる出力行一致ではsliceの正当性を完全には示せない。
3. 実入力ベンチの長文（64k→必要時128k/256k）とrandom比較は、機能検証が完了してから計測条件・再現性を揃えて進める。
4. 識別可能な改善候補：`F05`のエラーメッセージ文言修正、Gate 4 scriptの折り返しログ対応。**実装の修正が必須な障害は今回観測していない。**


## Gate 4 Extended 実機結果 — 2026-11-03

**Extended: 2/2 PASS。Gate 4 Fast + Core + Extended 全16ケースでnativeの期待動作を確認（Core C03は検証スクリプトの誤判定、nativeはPASS）。**

ユーザー提供ZIP `evox2-bench-gate4-20261103-114952.zip`の`gate4-summary.csv`, `metadata.json`, 各`arguments.json`/`stdout.json`/`stderr.log`を照合。生ZIPはGitHubに保存しない。実機binary SHA256 `9ad4fa1220fb9241dfa6d5a3c752c55eb4087d1fd74e9999d3e33ef8ba72e69f`、build b12032 `c4ddd239b`、Vulkan0 AMD Radeon 8060S、Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16、実入力`nlp-survey-ch3-d7-b1.txt`（304931 bytes, SHA256 `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`）。

| Case | CLI要点 | ExitCode / JSON rows / samples | avg_ns | tok/s | 判定 |
| --- | --- | --- | ---: | ---: | --- |
| E01-auto-context | `-f ... -p 257 -c 0 --prompt-slice head --no-warmup` | `0 / 1 / 1` | 688977200 | 373.016698 | PASS |
| E02-depth | `-f ... -p 32 -d 16 -c 1024 --prompt-slice head --no-warmup` | `0 / 1 / 1` | 265939000 | 120.328346 | PASS |

共通: `-n 0 -r 1 -b 256 -ub 256 -t 4 -ngl 999 -ncmoe 0 -fa auto -ctk f16 -ctv f16 -o json --progress`。出力はモデル/バイナリ/b12032整合、`n_prompt`・`n_depth`期待値と一致、`progressMatch=True`。

- E01: native進捗に`61777 available tokens, using 257 (head)`、`prompt run 1/1`を確認。`-c 0`の自動context指定でも正常終了。**実際に確保されたn_ctxはJSON出力されないため値そのものの検証ではない**。
- E02: 進捗に`61777 available tokens, using 32 (head)`、`depth run 1/1`と`prompt run 1/1`を確認。depthのrandom prefill + 実入力PPが同じnativeテストで完走した。時間計測はdepthを含む複合条件のため、通常のPP単独速度と単純比較しない。
- stderr.logにはPowerShell 5.1側の`NativeCommandError`ラッパー（backendロードのstderr出力に由来）が記録されているが、処理自体はExitCode 0で正常完走、JSONを取得できている。実行失敗を示すものではない。
- テストスクリプトはP-MODE/ADLX監視なし、token ID列のgolden比較なし。`-fit-target/-fitc`の正常系は未実施。

### Gate 4 総括

- **16/16 native期待動作を確認**：Fast 5/5、Core 9/9（うちC03のscript判定は偽陰性）、Extended 2/2。
- 機能確認の残件は主に (1) 短いgolden token列でhead/head-tailの位置と内容を独立検証する、(2) `-fitc`と`-c`のfit正常系を検証する、(3) Gate4 PowerShell検証器の長行折り返し正規化とF05の診断文言を改善するか判断。
- データ依存PP速度の定量評価は、次段の64k実文書vs random同条件複数runで行う。Gate 3の256-token約5.3倍は予備的観測にとどめる。
- **この段階でnative C++の機能上の不具合は検出されていない。** 新ソースコミット・再ビルドは不要。
