# r6 S1 COMMON-001 — split PLE16ローダ移植（2026-10-25）

- **基準:** b11870 `74bca3950054eed1795f525cb9cf06bfe796492d`（r6 clean表示b11875）
- **元ブランチ:** `r6/upstream-refresh-20261025` / `9b5ff9a5`
- **実装ブランチ:** `r6/common001-ple16-20261025`
- **コードコミット:** `259a0b95a653f303a207f2919901560e6c0b3408`
- **実装元:** r5 COMMON-001 `b45025848b97fc8fd3efa7333305567bc897f61f`
- **状態:** **S1 PASS（2026-10-25）**。Vulkan/ROCmビルド、4k 4run、64k 4run、128k split 2runを完走。後続S2へ進行可能。

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
| ビルド/manifest | **PASS**：b11879 / Clang 20.1.8 | **PASS**：b11879 / Clang 23.0.0 / TheRock 10.0 |
| 4k Original | **PASS**：49/49 GPU、出力OK | **PASS**：49/49 GPU、出力OK |
| 4k split PLE16 | **PASS**：49/49 GPU、出力OK | **PASS**：49/49 GPU、出力OK |
| 64k Original vs split | **PASS**：PP 339.77→344.51、TG 25.35→26.51 | **PASS**：PP 405.18→404.63、TG 21.55→21.78 |
| 128k split | **PASS**：PP 270.57、TG 24.35 | **PASS**：PP 301.43、TG 17.55 |

P-MODE Performance、ADLX、モデル/input SHA、build manifest、推論backendを記録する。ロード失敗・出力崩壊・CPU fallback等なら後続ゲートへ進まず、このブランチで原因を限定する。


## S1完了実測（2026-10-25追記）

**総合判定：COMMON-001 S1 PASS。** 4k 4run + 64k 4run + 128k split 2runの全10runが `Status=OK`、`ExitCode=0`、49/49層GPUオフロード、P-MODE開始/終了Performance、RuntimeArtifact Verified。長文runではADLX高負荷電力分類もPerformance-likeで一致。新しいPLE tensor名の認識、Original lazy pathの回帰防止、長文での出力正常性を確認した。

### 測定結果（単位 tok/s、MTP OFF、各条件1run）

| backend | 64k Original PP/TG | 64k PLE16 PP/TG | 128k PLE16 PP/TG | 128k S0 Original PP/TG |
| --- | ---: | ---: | ---: | ---: |
| Vulkan | 339.77 / 25.35 | **344.51 / 26.51** | **270.57 / 24.35** | 268.60 / 23.54 |
| ROCm | 405.18 / 21.55 | **404.63 / 21.78** | **301.43 / 17.55** | 303.66 / 17.50 |

- 64k: 61,789 prompt tokens、入力SHA `2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751`。同一S1バイナリでOriginalとPLE16を比較。VulkanのPLE16差分はPP +1.40%、TG +4.58%、ROCmはPP −0.14%、TG +1.07%。
- 128k: 126,253 prompt tokens、入力SHA `182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466`。PLE16対S0 OriginalはVulkan PP +0.73% / TG +3.44%、ROCm PP −0.73% / TG +0.29%。
- 64k・128kとも出力は評価表現辞書、語彙ネットワーク／共起／文脈、評価文書分類と限界を取り上げた自然な日本語要約。**出力崩壊なし**。temp 0.2、生成長が異なり、文面の完全一致は検証条件にしない。
- Vulkan PLE16ではOriginalのCPUモデルbuffer約27,466MiBがGPUモデルbufferに移動し約77,657MiB GPU配置。ROCmではPLE16もCPUモデルbuffer約27,466MiBとGPU約50,191MiBで、r5同様の傾向。49/49層GPUオフロードで完走したため、このbuffer差だけで計算のCPU fallbackとは判定しない。
- Vulkanのfused top-k mask disabled警告、ROCmでenabledはS0からの既知差。Vulkan PLE16の64k速度小幅改善は1runのため確定的効果と断定しない。

### 原ログ（ユーザーの計測アーカイブ）

- 4k 4run：`20261025-170750-890-cli-rocm-b11879-ctx4096-80bb4e0637f9.zip`
- 64k 4run：`20261025-173742-334-cli-rocm-b11879-ctx65536-9cba2c8e8700.zip`
- 128k 2run：`20261025-175836-436-cli-rocm-b11879-ctx131072-bcd32c1e52ff.zip`
- Vulkan/ROCmビルド：`(vulkan-common001)evox2-build.json`、`(rocm-common001)evox2-build.json`。双方BuildIdentity Verified、コミット `73324d6d`、clean、S0と同等のビルドオプション。

### COMMON-005判断

- r5 clean Originalの128k ROCm TG **17.13**、r6 S0 Original **17.50**、r6 S1 PLE16 **17.55 tok/s**。
- 計画で設定した「PLE16 128k ROCmでr5同条件より概ね10%以上のTG低下が再現」の条件に該当しない。**COMMON-005は初回r6統合では移植しない。S8後の条件付き研究項目として保留継続。**
- S1の同一バイナリ64k Original/PLE16比較で著しいPP/TG回帰なし。r6 S0のOriginal速度も維持。パッチ採用を確定し、**S2 COMMON-003A + VULKAN-001A/001B（ROCmFPx対応）**へ移る。

※測定は各条件1run。小幅なPP/TG差の統計的有意性や因果は検証していない。256kの追加反復は行わない。
