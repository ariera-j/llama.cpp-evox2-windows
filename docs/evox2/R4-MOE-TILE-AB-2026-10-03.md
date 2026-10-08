# r4 Vulkan MoEタイル選択の診断A/B

目的: upstream `94a0ae3e7` のタイル/alignment選択変更が64k PP退行に寄与するかを、
同じr4バイナリで切り分ける。恒久最適化やr3全体の再現ではない。
根拠は [COMMON-004比較](R4-COMMON004-VULKAN-COMPARISON-64K-2026-10-03.md)。

## 切り替え仕様

| 環境変数 | 未設定 / `0` | `1` |
|---|---|---|
| `GGML_VK_MOE_LEGACY_TILE_SELECTION` | 現行: expertあたり平均行数で選択 | 旧: 総token数で選択 |
| `GGML_VK_MOE_TILE_LOG` | pipeline詳細ログOFF | 最初の64種類までcontextごとに記録 |

文字列 `1` だけがON。それ以外はOFF。device初期化時に読み込むため、モード変更時は
新しいプロセスで起動する。matrix runnerは各runを別プロセスで実行する。
起動ログに `MoE tile selection = upstream-per-expert` または `legacy-token-count` が出る。
詳細ログにはtype、m/k、tokens、selected/total experts、tile_n、aligned、mmq、
pipeline名、wg_denomsを記録する。wg_denomsはdispatchの分割単位。

変更対象は `ggml_vk_mul_mat_id_q_f16()` のtile選択とそれに伴うalignment選択だけ。
旧モードは `nei1`、現行モードは `ceil(nei0*nei1/n_as)` を両方の判定に使う。
実dispatch件数、expert routing、QSA、FA、MoE matvec/decodeの分岐は変更しない。
既定動作はupstreamと同じ。ROCmには影響しない。
詳細ログOFFでは文字列作成やsetへの追加を行わない。

## 1. 別ディレクトリへビルド

既存のclean baselineバイナリを残す。

```powershell
cd C:\llama-build\llama.cpp-evox2-windows-r4
.\tools\evox2\build\Build-Vulkan.ps1 `
    -BuildDir build-vulkan-r4-moe-tile `
    -LlvmBin 'C:\Program Files\LLVM\bin' `
    -Parallel 4
```

`tools/evox2/benchmark/configs/local.psd1` の既存 `Builds` 内に追加する。
他のbuild/model/input登録はそのまま使う。`local.example.psd1` にも同じ登録例がある。

```powershell
R4MoeTileVulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r4\build-vulkan-r4-moe-tile\bin\Release'
    ExpectedBackend = 'Vulkan'
}
```

## 2. 対象演算の正しさを両モードで確認

既存test-backend-opsのMUL_MAT_IDケースを使う。これは今回のモデルの全shape・
expert routingを網羅するものではないが、変更した経路の基本動作を確認できる。
失敗時は計測を進めず、ログを確認する。

```powershell
$bin = Join-Path $PWD 'build-vulkan-r4-moe-tile\bin\Release'
$testRoot = Join-Path $PWD 'evox2-logs\moe-tile-tests'
New-Item -ItemType Directory -Force $testRoot | Out-Null
$testStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$names = @('GGML_VK_MOE_LEGACY_TILE_SELECTION', 'GGML_VK_MOE_TILE_LOG',
           'GGML_VK_PERF_LOGGER', 'GGML_VK_PERF_LOGGER_CONCURRENT',
           'GGML_VK_PERF_LOGGER_FREQUENCY')
$saved = @{}
foreach ($name in $names) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($mode in @('0', '1')) {
        $env:GGML_VK_MOE_LEGACY_TILE_SELECTION = $mode
        & "$bin\test-backend-ops.exe" test -b Vulkan0 -o MUL_MAT_ID 2>&1 |
            Tee-Object -FilePath (Join-Path $testRoot "$testStamp-mode-$mode.log")
        if ($LASTEXITCODE -ne 0) { throw "MUL_MAT_ID test failed: mode=$mode, exit=$LASTEXITCODE" }
    }
}
finally {
    foreach ($name in $names) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
    }
}
```

## 3. 最初はprofile 2回だけ実行

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r4-moe-tile-64k.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob profile -PlanOnly
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob profile
```

- A1: current upstream（明示的に `0`）、B1: legacy（`1`）。
- 同一build、UnslothOriginal、64k入力、ctx65536、生成128、MTP OFF。
- batch2048 / ubatch1024、threads4、f16 KV、FA auto、既存sampler設定を継続。
- GPU logger ON、frequency1、concurrent OFF、pipeline詳細ログON。
- 2つの環境変数は既存の `GGML_` 自動収集によりconditions.jsonにも残る。
- matrixごとのログ一式はlocal.psd1のLogRoot（空ならr4配下evox2-logs）へ出る。

まず両runの起動モード、同一実行バイナリ、tile_n/pipelineの差を確認する。
今回のMoE shapeでは1024-token時に20対1024、349-token時に7対349が想定される。
IQ2_S/IQ4_NLのPP演算合計とPP全体を比較し、FA等の差も観察する。
タイミングラベルの形式は変えていないため、前回と同じ集計方法を使用できる。

## 4. profile確認後、通常計測ABBA

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyJob normal
```

順番はA1→B1→B2→A2。GPU loggerとpipeline詳細ログは両方OFF。
`EVOX2_ABBA_RUN` は同条件runの重複排除を避けるための識別タグ。
環境変数は各子プロセスの前に設定され、終了後は呼び出し元の状態に戻される。
`-OnlyJob` を省略するとprofile2回＋normal4回の計6回になる。

生成128はPP診断用に前回profileと揃えたもの。通常baselineの生成1024設定と区別し、
このABBA内で比較する。主判定は通常PP、GPU内訳は原因の説明に使う。
生成token列やMoE routingの同一性は保証しない。TGの改善は今回の目的・約束に含めない。
profileでMoEが短縮し通常PPも改善すれば、gfx1151向け選択条件の検討へ進む。
改善しなければこの診断結果を残して候補を見直し、広範なrevertを行わない。

## 実施した検証と残る確認

- C++の変更部分を抽出した比較ハーネスで、1800条件について現行モードは固定upstream、
  legacyモードは変更前ソースとselector/alignment判定が一致。環境変数の`0`/`1`/未設定等も確認。
- PowerShellでplanを読み込み、実runnerのPlanOnlyで2回/4回の順序を確認。
  profile/normalの環境分離とconditions用環境変数収集も確認。
- 開発環境ではbackend全体のコンパイル・GPU実行はできない。
  後続のユーザー提供Windowsログで、下記の対象演算テストとprofile成功を確認した。

## 2026-10-03 13:17 JST: Windows profile A/B結果

入力ZIP: `20261003-125719-840-qwen38-r4-moe-tile-64k.zip`。
このZIPはprofile jobの2回のみ。後続normal ABBAの結果は末尾に追記。

- 両方ともb11376 / `c81b8bf78`、manifest Source.Dirty=false、Status OK / exit0。
- 実行ファイルSHA-256は両方とも
  `956622760b322694145104102d7a318ba9eb49ca5ef1e5a791548d2efbee5205`。
- ModelIdentity / InputIdentity / ExecutableIdentityは一致。
  EffectiveConditionの差は `GGML_VK_MOE_LEGACY_TILE_SELECTION=0/1` のみ。
- 同じOriginal・61,789 prompt tokens・128 generated tokens。
  profilerとtile logは両方ON、frequency1、concurrent未設定。
- 添付MUL_MAT_IDテストログはmode0/mode1ともVulkan0で **939/939 passed**。
  全backend演算やモデルの全shapeを網羅した結果ではない。

### 実際に選ばれたpipeline

| PP query数 | A: upstream tile_n | B: legacy tile_n | Aのwg_denoms | Bのwg_denoms |
|---|---:|---:|---|---|
| 1024 | 20 | 1024 | 32,32,1 | 64,64,1 |
| 349 | 7 | 349 | 32,32,1 | 64,64,1 |

IQ2_S/IQ3_Sの1024-queryではalignedのままpipeline末尾が`_0`→`_1`。
349-queryではunaligned `_0`→aligned `_1`へ変わった。
IQ4_NLは両方mmq=1・aligned=0で、`matmul_id_subgroup_iq4_nl_q8_1_0`→`_1`。
つまりalignmentだけの差ではなく、主力演算で実際のタイル選択が変わっている。

### 時間比較

両方190 timing blocksを解析し、各blockの演算合計とTotal timeの一致を丸め範囲で確認。
warmup2を除外、PP61（1024×60+349）、TG127の最初の1つを除く126をsteady集計。
GPU演算時間とwall timeを区別する。変化はB/A−1。

| 指標 | A: upstream | B: legacy | 変化 |
|---|---:|---:|---:|
| PP GPU演算合計 | 253.097秒 | 230.763秒 | -8.82% |
| PP MoE演算合計 | 63.933秒 | 47.807秒 | -25.22% |
| PP Flash Attention | 108.658秒 | 108.654秒 | ほぼ同じ |
| PP その他matmul | 38.103秒 | 36.155秒 | -5.11% |
| PP wall time（profiler ON） | 264.307秒 | 240.609秒 | -8.97% |
| PP tok/s（profiler ON） | 233.78 | 256.80 | +9.85% |
| steady TG GPU平均 | 40.648 ms/token | 40.582 ms/token | -0.16% |

MoEの短縮は16.127秒で、PP GPU全体の短縮22.334秒の約72%。
batch1024のIQ2_Sは43.735→34.234秒、IQ4_NLは18.328→12.074秒。
端数349-queryではIQ2_Sが706.597→406.968 ms、IQ4_NLが260.494→132.217 ms。
旧COMMON-004版のMoE合計47.051秒に近い水準へ戻った。

最初のPP blockはA 3458.11 / B 2735.42 msと前回profileより大きい。
このblockを両方から除いてもMoEは62.667→46.305秒、PP GPU全体は
249.639→228.027秒であり、結論は初回blockの差だけには依存しない。
初回decodeもA 532.707 / B 42.399 msと差があるため、従来どおりsteady集計から除外。
この初回差の原因はログだけでは特定しない。

TG GET_ROWSはA 2.48248 / B 2.48236 ms/tokenでほぼ不変。
TGの退行は今回のPP修正と別に残っている。表示上のTG 7.34→7.50 tok/sも
profilerを含むため、通常TGの改善を示す値とは扱わない。

### 判断と次の計測

同一バイナリの切り替えだけでpipeline変更とMoE短縮を観測し、タイル選択変更が
今回のgfx1151・モデル・PP shapeで退行を起こす主要因という強い証拠が得られた。
ただし各1回のprofileであり、PP全体の差をすべてMoEに割り当てない。
通常速度への効果や他モデル/GPUへの一般化はまだ未確認。

次は上記手順4の `-OnlyJob normal` を実行する。再ビルド・plan変更は不要。
通常PPで改善が再現したら、診断スイッチを比較手段として保持しつつ、適用する
GPU・型・shapeの範囲を検討する。現時点でlegacyを全GPUの既定値にはしない。
TGの追加診断とVULKAN-002/COMMON-005の順序は、この通常計測後に判断する。

## 2026-10-03 13:56 JST: 通常計測ABBA結果

入力ZIP: `20261003-132757-224-qwen38-r4-moe-tile-64k.zip`。
13:27:57〜13:48:17 JST、normal jobの4回が完了、全run Status OK / exit0。
前節の「次はnormal ABBA」は完了し、以下を最新判断とする。

### 条件確認

- 全runはb11376 / `c81b8bf78`、同一実行ファイルSHA-256、manifestはclean。
- ModelIdentity、InputIdentity、ExecutableIdentityは4回で一致。
  EffectiveConditionの差はlegacy selector環境変数の0/1のみ。
- 入力61,789 tokens、生成128 tokens、MTP OFF、graph reuse127が4回で一致。
- `GGML_VK_PERF_LOGGER` と `GGML_VK_MOE_TILE_LOG` は未設定。
  stderrにVulkan Timingsはなく、起動時の選択モードとtile log offを確認。
- A1/A2、B1/B2はそれぞれ同一ConditionId。生成本文はrunごとに異なる。

### 結果

PP/TGは通常実行のtok/s。PP時間はロード時間を含まないprompt eval時間。

| 実行順 | 方式 | PP tok/s | TG tok/s | PP秒 | generation eval秒 |
|---|---|---:|---:|---:|---:|
| A1 | 現行 | 248.89 | 25.25 | 248.259 | 5.030 |
| B1 | 旧 | 268.99 | 24.13 | 229.710 | 5.264 |
| B2 | 旧 | 268.98 | 25.00 | 229.716 | 5.080 |
| A2 | 現行 | 248.06 | 25.14 | 249.085 | 5.052 |
| A平均 | 現行 | 248.475 | 25.195 | 248.672 | 5.041 |
| B平均 | 旧 | 268.985 | 24.565 | 229.713 | 5.172 |

平均は各方式2回の算術平均。PPは **+8.25%**、prompt eval時間は
**18.959秒短縮（-7.62%）**。A1→B1で+8.08%、A2→B2で+8.43%と同方向。
B2の後でA2が248.06へ戻っており、単純な後半runの高速化だけでは説明しにくい。
旧方式の2回は268.99/268.98で揃い、profileに続いて通常PPでも改善を確認できた。

r4 cleanの64k PP 248.38に対してA平均248.475はほぼ同水準。
r3 Original baseline 265.10もB平均268.985は数値上上回ったが、これは別時点・
別バイナリの参考比較。同一バイナリABBA内の+8.25%を主な改善量とする。

### TGの扱い

TG平均は25.195→24.565 tok/sで **-2.50%**。
generation eval時間の平均差は+0.132秒（約5秒の区間に対して+2.61%）。
B1 24.13に対してB2 25.00で、B内のばらつきが目立つ。
各方式2回・生成128tokens・生成本文も異なるため、安定したTG退行かrun変動かは
このABBAだけでは区別できない。B1を根拠なく除外したり「TG影響なし」としない。
今回の変更はMoE matvecの選択を直接変更せず、前回profileのsteady TGも
40.648→40.582 ms/tokenとほぼ同じだったが、これは通常TGの同等性の証明ではない。

### 現時点の判断・次の優先順位

1. このモデル・gfx1151・batch2048/ubatch1024・64kに限り、MoEタイル選択変更が
   PP退行の主要因という診断を完了する。profileと通常ABBAの両方で改善が再現した。
2. 旧方式はこの条件で有効なPP対策として扱い、環境変数による明示的な選択を維持。
   全GPU/モデル/shapeへの既定化や128k/256kへの効果の外挿はまだ行わない。
3. 次は予定どおりTG GET_ROWSのtensor名・shape別診断を一度行い、
   pool gatherとQSA選択/maskのどこを直すべきか判断する。
   A/BではMoEモードを固定し、PP修正とTG変更の効果を混ぜない。
4. TG修正が大きければ現状を比較基準として残し、VULKAN-002へ進む。
   長文検証やTG反復計測は、次の変更の評価とまとめて行う。

追加の64k PP ABBAや全GPU向けrevertは現時点では不要。
このABBA結果の分析ではソース/planを変更していない。

 
## 2026-10-09: llama-bench QSA OFF計測との参考比較

10/07～09の別調査で、`llama-bench`の実文書64k PPに以下の参考値が得られた。
詳細: [llama-bench実文書入力・QSA union検証](R4-LLAMA-BENCH-REAL-PROMPT-2026-10-07.md)。

| 実文書64k PP | MoE upstream相当 | MoE legacy | 改善幅 |
| --- | ---: | ---: | ---: |
| **このドキュメントの10/03同一build CLI ABBA** (b11376/Original) | **248.475** | **268.985** | **+8.25%** |
| 10/07～09の別build bench参考値 (b11427→b11433/PLE16) | 243.34 | 268.81 | +10.47% |
| 上記bench legacy再測定（Random先、実文書後、warmupあり、2rep） | 243.34 | 269.119772 | +10.59% |

参考値の「upstream相当」243.34 tok/sはVulkan環境変数を3つ設定し忘れた測定。ソースでは `GGML_VK_QSA_UNION` と `GGML_VK_GET_ROWS_128X4` は未設定/`0`でどちらもOFFであり、今回legacy側で変えた**実効設定はMoE tileのみ**という解釈と整合する。

ただし、**243.34→268.81のbench 2測定でもbuild・warmup条件が異なり**、加えて10/03のCLI ABBAと比べると**実行ツール・Original対PLE16というモデル形式も異なる**ため、+10.47%は厳密なMoE tile A/Bではない。本資料で確認済みのMoE tile単独の改善率は、あくまで**10/03の同一build ABBA +8.25%**である。別調査の参考値が近いことは傍証に留める。
