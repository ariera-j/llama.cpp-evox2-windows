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
- この環境にはVulkan開発ツール・GPU実行環境がないため、backend全体のコンパイル、
  Windows実行、GPU上の正しさ・性能は未検証。上記ビルド・テスト・計測で確認する。
