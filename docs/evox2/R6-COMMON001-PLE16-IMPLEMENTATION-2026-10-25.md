# r6 S1 COMMON-001 — split PLE16ローダ移植（2026-10-25）

- **基準:** b11870 `74bca3950054eed1795f525cb9cf06bfe796492d`（r6 clean表示b11875）
- **元ブランチ:** `r6/upstream-refresh-20261025` / `9b5ff9a5`
- **実装ブランチ:** `r6/common001-ple16-20261025`
- **コードコミット:** `259a0b95a653f303a207f2919901560e6c0b3408`
- **実装元:** r5 COMMON-001 `b45025848b97fc8fd3efa7333305567bc897f61f`
- **状態:** ソース移植・GitHub差分検証済み。**Windowsビルド、起動・速度・品質は未検証。**

## 移植内容

| ファイル | 内容 |
| --- | --- |
| `src/llama-arch.h` | `LLM_TENSOR_PLE_NGRAM_EMBD` 型 |
| `src/llama-arch.cpp` | `ple_ngram_embd.%d.weight` 名前とGET_ROWS用tensor情報 |
| `src/models/models.h` | Qwen4Expのsplit head tensor配列 |
| `src/models/qwen4exp.cpp` | モデルロード、head-major local index、headごとのGET_ROWS・結合 |

**Originalの結合PLE `per_layer_token_embd.weight` とメタデータのみモデルのlazy pathは維持**。結合tensorが存在しない場合だけsplit PLE head tensorを必須として各行数を検証する。Vulkan/ROCm専用kernelやshader、QSA、MTPには触れない。

ソース差分は上記4 C++ファイルのみ（+63/-14）。r5の実装コミットとGitHub API上の追加・削除行が**完全一致**。r6本流のS0 baselineソース・ビルドは未変更。互換性patchであり高速化patchではない。

## ユーザー側の手順 — 別ビルドディレクトリ使用

```powershell
Set-Location C:\llama-build\llama.cpp-evox2-windows-r6
git fetch origin
git switch -c r6/common001-ple16-20261025 --track origin/r6/common001-ple16-20261025
git status

.\tools\evox2\build\Build-Vulkan.ps1 -BuildDir .\build-vulkan-r6-common001 -Parallel 4
.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-r6-common001 -ExpectedRocmSdkVersion 10.0.0 -AmdGpuTarget gfx1151 -Parallel 4
```

- S0の `build-vulkan-r6-clean` と `build-rocm-r6-clean` は保存。Vulkan SDK / LLVM / ROCm SDKはS0の環境・指定を使う。
- ROCmの `-RunBackendTest` は**実行しない**（Windows/gfx1151 FLASH_ATTN_EXT網羅テストのwatchdogリスク）。
- ビルドmanifest・version/device、backend、TheRock 10.0 DLLロード元を確認する。

次にローカル専用の `tools/evox2/benchmark/configs/local.psd1`（Git管理外）に追記する。

```powershell
# Builds の項目（実際のr6パスを指定）
S1Vulkan = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-vulkan-r6-common001\bin\Release'
    ExpectedBackend = 'Vulkan'
}
S1ROCm = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-r6-common001\bin\Release'
    ExpectedBackend = 'ROCm'
}
# Models の項目：PLE16変換版の実ファイルパスを指定
UnslothPle16 = @{
    Path = 'C:\path\to\Unsloth-IQ3-ple16.gguf'
    Alias = 'unsloth-iq3-ple16'
}
```

**上記は各 `Builds`/`Models` hashtableの中に追加する断片**。既存 `UnslothOriginal`、`Inputs.64k/128k` はS0と共通。例示のモデルパスは実パスに置換。

## G1ゲート：4k → 64k → 128k

1. 両backend×Original/split PLE16の**4k短文4条件**。各32 token推論まで行い、tensorロード、出力、全49層のGPU配置と重大なCPU fallbackを確認。
2. 両backendで**64k Original対split各1run、計4run**。同一S1バイナリ・同一入力・MTP OFF・f16 KVで比較（出力/PP/TG）。
3. 64k通過後、**128k splitだけ両backend各1run、計2run**。ROCmのTGは後続COMMON-005の条件判断に保存。
4. S1では256kを再実行せず、IQ4/huihui/Gemma4/ROCmFP4は後続stageに残す。

専用マトリクス：`tools/evox2/benchmark/configs/qwen38-r6-common001.psd1`

```powershell
$bench = '.\tools\evox2\benchmark'
$local = "$bench\configs\local.psd1"
$plan  = "$bench\configs\qwen38-r6-common001.psd1"

# 4k smoke（AllocationOnlyは固定32tokenの短文推論も行う）
foreach ($backend in @('S1Vulkan','S1ROCm')) {
    foreach ($model in @('UnslothOriginal','UnslothPle16')) {
        & "$bench\Measure-LlamaCli.ps1" -LocalConfig $local -BuildKey $backend -ModelKey $model -AllocationOnly -Context 4096
    }
}

# 64k ×4run（PlanOnly確認後に実行）
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 64k

# 128k split ×2run（64k PASS後）
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k -OnlyJob common001-split-64k-128k -PlanOnly
& "$bench\Invoke-BenchmarkMatrix.ps1" -Plan $plan -LocalConfig $local -OnlyCase 128k -OnlyJob common001-split-64k-128k
```

## 判定記録

| Gate | Vulkan | ROCm |
| --- | --- | --- |
| ビルド/manifest | 未実施 | 未実施 |
| 4k Original | 未実施 | 未実施 |
| 4k split PLE16 | 未実施 | 未実施 |
| 64k Original vs split | 未実施 | 未実施 |
| 128k split | 未実施 | 未実施 |

P-MODE Performance、ADLX、モデル/input SHA、build manifest、推論backendを記録する。ロード失敗・出力崩壊・CPU fallback等なら後続ゲートへ進まず、このブランチで原因を限定する。
