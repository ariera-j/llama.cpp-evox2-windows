# r6 b11870 clean upstream Windows baseline — 2026-10-25

**判定：S0 PASS / Vulkan・ROCm各4k smoke＋64k/128k/256k実文書、8runすべてOK。** S1 COMMON-001移植前の不変baseline。各長文depth/backendは1runのみで、反復ABBAによる有意差判定ではない。

## 1. ソース・計測の同一性

- リポジトリ：ariera-j/llama.cpp-evox2-windows、r6/upstream-refresh-20261025
- upstream固定元：ggml-org/llama.cpp **b11870**、SHA **74bca3950054eed1795f525cb9cf06bfe796492d**。
- 実行バイナリ：**b11875 / 280a639f3538c9da10c189154fbc26db86925372**。upstreamからの5コミットはdocs/tools/.gitignoreのみで、推論ソースsrc・ggml・common・include・tools/llama-benchの変更なし。Vulkan/ROCmのbuild identity Verified、ビルド時git clean。
- GPU：Evo-X2 / Ryzen AI Max+ 395 / Radeon 8060S、UMA label 96GB、Windows。
- ROCm：TheRock SDK 10.0.0、AMD Clang 23、gfx1151。ROCm HIP/BLAS DLL8件とアーキテクチャデータ2系統のソース/配置先SHA一致、危険な広範囲FLASH_ATTN_EXTテストは未実施。
- モデル：Unsloth Qwen3.8-Flash-Next UD-IQ3_XXS **Original joined PLE**（3 shardの先頭GGUF）、**PLE16 split変換前**。モデル全shard SHAは取得していない。
- 計測：llama-cli、MTP OFF、KV f16、-ngl 999、-ncmoe 0、-b 2048、-ub 1024、-t 4 / -tb 4、FA auto、ctx-checkpoints 0t、fit off、cache-ram 0、generation cap 1024、temp 0.2、top-p 0.8、reasoning off。出力はEOSで早期終了する場合がある。
- 入力はr5 cleanと**本文SHA-256完全一致**。64k（61,789 tokens）2c06456c13b9b2b60292742bbff116d234805bfe88ce5765a83721c3ce2d4751、128k（126,253 tokens）182d14a0ca0a8da3659da6bfc2203a68efd96bbb52a26a4bc41dcd24b10da466、256k（255,181 tokens）63a5c074c457c8de8016ca8498cf38c432b47b8fb8782f7c35a4d37006cc8788。

### 元ログ

- 4k smoke（Vulkan・ROCm両方）：20261025-144917-967-cli-rocm-b11875-ctx4096-10886c26e1af.zip
- 64k/128k 4run：20261025-145716-376-qwen38-clean.zip
- 256k 2run：20261025-153747-046-qwen38-clean.zip

これらのZIP本体はユーザーの計測アーカイブに保持し、Gitには実測サマリーのみ記録する。

## 2. r6 S0 全6長文run（IQ3 Original / MTP OFF）

| Backend | Context | Prompt tokens | Generated | PP tok/s | TG tok/s | Wall秒 | ADLX高負荷W | 結果 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Vulkan | 64k | 61,789 | 564 | **339.72** | **25.42** | 254.8 | 118.67 | OK |
| ROCm | 64k | 61,789 | 605 | **405.24** | **21.86** | 226.4 | 120.27 | OK |
| Vulkan | 128k | 126,253 | 627 | **268.60** | **23.54** | 546.4 | 118.47 | OK |
| ROCm | 128k | 126,253 | 517 | **303.66** | **17.50** | 492.4 | 119.59 | OK |
| Vulkan | 256k | 255,181 | 435 | **228.89** | **20.30** | 1,190.4 | 119.24 | OK |
| ROCm | 256k | 255,181 | 487 | **200.59** | **12.55** | 1,356.4 | 118.59 | OK |

すべてExitCode 0 / Runtime Verified、P-MODE開始・終了ともPerformanceで変更なし、ADLXログ取得成功、電力分類Performance-like、P-MODE警告ゼロ。4k smokeも両backendで49/49 layers GPU offload、期待出力OK、ADLX取得成功。高負荷サンプルは短文では足りず電力によるP-MODE判定は未評価（WMIはPerformance）で問題なし。

## 3. r5 clean b11517 → r6 clean b11875 比較

比較元は [r5 clean baseline](R5-CLEAN-BASELINE-VALIDATION-2026-10-09.md)。r5/r6ともUnsloth IQ3 Original joined PLE、MTP OFF、実入力SHAが一致する。主要CLI設定も一致し、同様のEvo-X2環境。**各1run**かつ出力token数が違うため、特にTGの小差は参考値とする。

| Backend | Context | r5 PP | r6 PP | PP増減 | r5 TG | r6 TG | TG増減 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Vulkan | 64k | 269.24 | 339.72 | **+26.2%** | 25.31 | 25.42 | +0.4% |
| ROCm | 64k | 390.73 | 405.24 | **+3.7%** | 21.18 | 21.86 | +3.2% |
| Vulkan | 128k | 179.51 | 268.60 | **+49.6%** | 23.67 | 23.54 | −0.5% |
| ROCm | 128k | 292.69 | 303.66 | **+3.7%** | 17.13 | 17.50 | +2.2% |
| Vulkan | 256k | 135.41 | 228.89 | **+69.0%** | 20.02 | 20.30 | +1.4% |
| ROCm | 256k | 193.64 | 200.59 | **+3.6%** | 12.37 | 12.55 | +1.5% |

**主な所見**
1. Vulkan PP改善は長文ほど大きい（64k +26%、128k +50%、256k +69%）。原因となる個別upstream commit/kernelは未特定。TGは同程度。
2. ROCm PPは全depthで約+3.6〜3.7%、TGもわずかに上がり、悪化の実測はなし。ただし256k TG 12.55 tok/sと長文低下が大きく、64k 21.86→128k 17.50→256k 12.55となる。
3. 256kではVulkan PP 228.89 > ROCm 200.59（Vulkan +14.1%）、TG 20.30 > ROCm 12.55（+61.8%）。r5 cleanの256k PP順位はROCm優位だったので順位が逆転した。
4. 過去のCOMMON-005はROCm 256k MTP OFFで改善実績を持つが、**r6採否ルールをこの1runで変更しない**。S1のPLE16 128kで既存r5条件と突き合わせ、条件付き判定枠として保持。
5. r5後半のMTP ON＋QSA union＋DENSE/NOOP最適化との絶対値比較は**別モデルlayout・MTP有無・出力条件**が異なる参考比較に過ぎない。移植効果は各ステージの同一バイナリABBAで再評価する。

## 4. 実装・環境上の観察

- 両backendとも **49/49 GPU offload**。モデルバッファ約50,191MiB GPU＋約27,466MiB CPUが報告されるが、CPUモデルバッファの存在だけで計算のCPU fallbackとは断定しない。
- Vulkanは全depthで「fused top-k mask not supported, set to disabled」（layer3 Vulkan / fused CPU割当）の警告。ROCmでは「fused top-k mask enabled」。これらは経路差の観察であり、今回のVulkan PP改善やROCm TG差の直接原因を立証するものではない。
- 256k ADLX高負荷平均：Vulkan GPU使用99.3%、core 2,836MHz、VRAM 996MHz、GPU温度86.6℃（最高95℃）、電力119.2W。ROCm GPU使用99.9%、core 2,882MHz、VRAM 994MHz、温度87.6℃（最高94℃）、電力118.6W。明確なP-MODE低速状態はない。温度と速度の因果は未検証。
- ROCm子プロセスの環境には歴史的HIP_PATH（ROCm7.2）が見えるが、**ビルドmanifestはTheRock10.0のDLL8件＋データを自己完結stage・SHA一致検証済み**。環境変数だけでDLL混在とは判定しない。今後の厳密なruntime追跡時にロード元を再確認する。
- Windows/gfx1151で問題になった広範囲FLASH_ATTN_EXT backendテストは禁止を維持。

## 5. 判定と次の手順

**S0 PASS。** 初期予定の64k/128kに加え、ユーザー合意による例外として256kを各backend1run追加し、移植前の純粋な長文baselineを保存した。

**次はS1 COMMON-001 split PLE16対応。** b11870ベースに最小パッチを移植し、まずOriginal GGUFロードが変わらないことを確認。S1の**同一バイナリ**でIQ3 OriginalとPLE16変換版をVulkan/ROCmの64kで比較し、PLE16版128k代表runを実施。S1では256kを繰り返さない。S0との差をCOMMON-001固有の改善率と即断せず、同一S1バイナリの原版/変換版を優先する。
