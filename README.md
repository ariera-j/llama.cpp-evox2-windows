# llama.cpp Evo-X2 Windows fork

**Language / 言語:** 日本語（このページ） · **[English README](README.en.md)**

**Windows 11 / GMKtec NucBox EVO-X2 / AMD Radeon 8060S (gfx1151) 向けのローカルLLM推論・高速化研究用forkです。**  
[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)をベースに、Qwen3.8-Flash-NextのPLE16、Vulkan/ROCm、長コンテキスト推論、MTP（speculative decoding）を検証しています。

> **2026-10-29 r6統合チェックポイント（b11908ベース）**：S8・S9の限定した検証範囲をWindows実機で完走。**汎用の安定版・全環境への性能保証ではありません。** 速度最適化5フラグはソース既定ですべてOFF。Vulkanルーターモードは後追いの3モデル／35応答テストで限定PASS、数値的Draft K/V一致は未検証です。

**English:** Research-focused downstream llama.cpp fork for Radeon 8060S (gfx1151) on Windows 11. Covers Qwen3.8-Flash-Next PLE16, long-context Vulkan/ROCm and MTP optimizations. Results are hardware- and configuration-specific; this is **not** an official upstream build. [Read the full English version](README.en.md).

[Upstream README](README.upstream.md) · [ビルド方法](tools/evox2/build/README.md) · [速度計測全文](docs/evox2/R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md) · [パッチ一覧](docs/evox2/PATCHES.md) · [統合版記録](docs/evox2/INTEGRATED-RELEASES.md)

## Vulkan版ビルド済みバイナリ（実験用Pre-release）

**[GitHub Release: Evo-X2 r6 b11908 Vulkan Experimental Preview](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/tag/evox2-integrated-2026-10-29)**

- **[Windows Vulkan ZIP（約34.1 MiB）](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/download/evox2-integrated-2026-10-29/llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip)** · [ZIPのSHA256ファイル](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/download/evox2-integrated-2026-10-29/llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip.sha256)
- 対象：**Windows x64 / Vulkan**。実機検証環境はWindows 11、GMKtec NucBox EVO-X2、AMD Radeon 8060S（gfx1151）。**ROCm/HIP版は含みません**。
- 同梱：`llama-cli.exe`、`llama-server.exe`、`llama-bench.exe`、`llama-tokenize.exe`、Vulkan/CPUバックエンドのDLL、ライセンス通知とハッシュ一覧。**GGUFモデル・MTP Draftモデルは含みません**。
- バイナリは実測済み**b11908**（ビルド時のソースコミット`b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`）。公開タグ`evox2-integrated-2026-10-29`は文書を含む**ソースチェックポイント**で、バイナリのビルド時コミットとは別です。

ダウンロード後は新しいフォルダへ展開し、**既存のllama.cppのEXE/DLLと混在させないでください**。PowerShellで同じフォルダにZIPを保存した場合の確認例：

```powershell
$zip = '.\llama.cpp-evox2-b11908-win-vulkan-preview-v2.zip'
$expected = '8e68dd4de9f5eccdf454ba33705a9da18ad252fecb4ed55144915c24d56775b6'
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'ZIP SHA256 mismatch' }

Expand-Archive -LiteralPath $zip -DestinationPath '.\evox2-vulkan-preview'
Set-Location '.\evox2-vulkan-preview\llama.cpp-evox2-b11908-win-vulkan-preview-v2'
.\llama-cli.exe --version
.\llama-cli.exe --list-devices
.\llama-server.exe --version
```

`--list-devices`に`Vulkan0`が表示されることを確認してください。AMD Vulkan対応ドライバと必要なWindows/VC++ランタイムが必要です。**組み込みWebUIはビルド時に`LLAMA_BUILD_UI=OFF`で無効**ですが、CLIとAPIサーバーは同梱されています。VulkanのルーターモードとOpen WebUIからの3モデル切り替えは[35応答の限定テスト](docs/evox2/R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md)でPASSしています。ただし画像処理の正確性と長期安定性は未検証です。ROCmのルーターモードも[3モデル・16応答の限定テスト](docs/evox2/R6-S9-GATE5-ROCM-ROUTER-RESULTS-2026-10-29.md)でPASSしています（Web検索時の1件のコンテキスト超過は別）。ROCmバイナリは公開ZIPに含みません。全5高速化フラグは**ソース既定でOFF**です。使用するモデル・backendごとの[フラグ検証範囲](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md)と[Releaseの制限事項](https://github.com/ariera-j/llama.cpp-evox2-windows/releases/tag/evox2-integrated-2026-10-29)を確認してください。

## このforkの主な追加点

| 機能 | 内容・適用範囲 |
| --- | --- |
| PLE16 / GGUF | Unsloth Qwen3.8-Flash-Nextの分割PLE16への互換対応（COMMON-001）。[変換・検証](tools/evox2/model/README.md) |
| ROCmFP4 / Vulkan | Agention ROCmFP4 FAST PLE16の形式とVulkan GPU演算への対応。**ROCm HIPでのFP4 GPU kernel対応ではありません** |
| Vulkan QSA-union | f16 KVでの長文PP改善。`GGML_VK_QSA_UNION=1`、対象時に`GGML_VK_QSA_UNION_MIN_KV=32768` |
| MTP DENSE / NOOP | 対象Qwen4Exp経路のDraft indexer省略とTarget invalidation抑止。Vulkan・ROCmで検証済み条件に限りopt-in |
| Stage-B / flatten | Draft KV-only prefill / `mtp_eh_proj`最適化。数値的Draft K/V一致は**DEFER**、研究用途のopt-inのみ |
| 計測・運用ツール | Vulkan/ROCm個別ビルド、TheRock依存管理、ADLX/P-MODE計測、SHA付きbenchmark plan。[Vulkanビルド前検証](tools/evox2/build/README.md)と[Windowsバックグラウンド負荷の記録](tools/evox2/benchmark/BACKGROUND-ACTIVITY-MONITORING.md)を追加（Windows上の動作再確認は未実施） |

適用条件は[フラグ別の判定表](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md)を参照してください。全モデル・全バックエンドに自動的に有効な機能という意味ではありません。

## 速度計測例：Qwen3.8-Flash-Next

PP=prompt processing、TG=token generation。単位はいずれも**tokens/s**です。

| Backend | 実入力 | r6 upstream PP / TG | r6統合版 PP / TG |
| --- | ---: | ---: | ---: |
| Vulkan | 64k | 339.72 / 25.42 | **358.29 / 33.90** |
| Vulkan | 128k | 268.60 / 23.54 | **322.98 / 30.49** |
| Vulkan | 256k | 228.89 / 20.30 | **301.30 / 25.08** |
| ROCm | 64k | 405.24 / 21.86 | **371.43 / 28.63** |
| ROCm | 128k | 303.66 / 17.50 | **282.24 / 22.64** |
| ROCm | 256k | 200.59 / 12.55 | **184.79 / 15.04** |

**比較条件・注意：** NucBox EVO-X2 / Radeon 8060S / Windows 11 / UMA 96 GiB / Performance P-MODE、f16 KV、全層GPU配置、実文書入力64k=**61,789**、128k=**126,253**、256k=**255,181**トークン。r6 upstreamはb11875（upstream b11870と推論ソース同一）、**IQ3 Original joined-PLE・MTP OFF**。統合版はb11908（実測ソースSHA `b82243bf0d1d6cd995bec2952e03c9fb61a5ff1f`）、**IQ3 split PLE16・MTP ON**。統合版Vulkanは**5フラグONの実験構成**、ROCmは**DENSE+NOOPの2フラグON**。モデルレイアウトもMTPも異なる**運用構成比較**であり、**同一条件のパッチ単独改善率ではありません**。256kは代表的な単発値です。

同一バイナリ内のON/OFF実測、追加21run、全5フラグONのROCm短期安定性確認、アーカイブSHAは[詳細記録](docs/evox2/R6-S9-GAPFILL-AND-ROCM-LONG-CONTEXT-PRIORITY-2026-10-29.md)を参照。次の高速化優先課題は**ROCmの128k～256kでのPPとTG**です。

## 動作確認したモデルと範囲

| モデル | 対象backend・確認内容 |
| --- | --- |
| Unsloth Qwen3.8 UD-IQ3_XXS Original / PLE16 | Vulkan・ROCm CLI、MTP OFF/ON、64/128/256k実入力。Vulkan MTP ONの通常`llama-server`短文・多段対話・64kを別途確認 |
| Agention ROCmFP4 FAST PLE16 | **Vulkan**で4k/16kおよび64/128k実文書とMTPの限定検証 |
| Unsloth / huihui UD-IQ4_XS PLE16 | **Vulkan**で4k/16k起動、64k・選択的128k、MH-128Kの限定的検索回帰 |
| Gemma4 31B QAT Q4_0 / 26B A4B QAT | **Vulkan**で4k/16kと実32k文書。旧b10919バイナリをフォールバックとして保全 |

GGUF・MTP Draftモデルは付属しません。詳細は[S9 Qwen/Gemma検証](docs/evox2/R6-S9-FINAL-MODELS-RUNBOOK-2026-10-28.md)・[Gemma4の限定判定](docs/evox2/R6-S9-GEMMA4-G9-4-RESULTS-2026-10-29.md)を参照してください。

## ビルド・使い方

本forkの独自コードは、上記の**検証済みVulkan実験用バイナリ**を利用するか、**このリポジトリからソースビルド**して使えます。ROCm版など公開ZIPにない構成はソースビルドしてください。upstream公式インストーラー・公式バイナリには本fork独自のパッチは含まれません。

- [Windows Vulkan](docs/evox2/BUILD-VULKAN-WINDOWS.md) / [Windows ROCm](docs/evox2/BUILD-ROCM-WINDOWS.md) ビルド手順
- [Evo-X2 PowerShellビルド・計測ツール](tools/evox2/build/README.md)、[ベンチマークplan一覧](tools/evox2/benchmark/configs/)
- [PLE16モデル変換](tools/evox2/model/README.md)、[実運用フラグの判定](docs/evox2/R6-S8-SUPPORTED-FLAG-PROFILES-2026-10-28.md)

速度フラグは**バックエンドごとにプロセス単位で明示**し、`setx`による常時設定は避けてください。以下は研究用の全5フラグONではなく、実測に基づく**保守的なopt-in候補**の例です。

**Vulkan IQ3 PLE16 / f16 KV / 対象MTPパス:**

```powershell
$env:GGML_VK_QSA_UNION = '1'
$env:GGML_VK_QSA_UNION_MIN_KV = '32768'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
```

**ROCm IQ3 PLE16 / MTP ON（CLI確認済み・server未確認）:**

```powershell
$env:GGML_VK_QSA_UNION = '0'
$env:LLAMA_MTP_SKIP_DENSE_INDEXER = '1'
$env:LLAMA_QSA_SKIP_NOOP_INVALIDATION = '1'
$env:LLAMA_MTP_DRAFT_PREFILL_KV_CROP = '0'
$env:LLAMA_MTP_EH_PROJ_FLATTEN = '0'
```

起動引数・GGUF/Draftの指定例は[G8-6 llama-server手順](docs/evox2/R6-S8-GATE6-RUNTIME-USABILITY-RUNBOOK-2026-10-28.md)を参照。**ソースの既定値は5スイッチ全OFF**です。

## 未検証事項・注意点

- Vulkan `llama-server`の**router mode + Open WebUI**はGemma4 31B／26B／Qwen3.8 IQ3 PLE16を切り替えて**35/35応答が完了、限定PASS**。[G9-5実測記録](docs/evox2/R6-S9-GATE5-ROUTER-OPENWEBUI-RESULTS-2026-10-29.md)。**組み込みWebUIはビルド時OFF、Qwen画像時の位置警告24件と長期メモリ解放は未検証**。
- ROCmの**MTP ON `llama-server`**は未確認。ROCm CLI MTP ONおよびサーバーMTP OFFはそれぞれ確認済み。
- Stage-B/flattenの数値的Draft K/V一致、汎用の全5フラグON既定プロファイルは**未承認**。
- ROCmでは同一seedでも出力に揺らぎがある。Gemma4のVision・長文回答完結性・64k以上は本checkpointの承認範囲外。
- Windows/gfx1151で問題のあった広範囲の`FLASH_ATTN_EXT` backendテストは実行しない。
- このforkの速度結果を、別のハードウェア、量子化、入力文書へそのまま一般化しない。

## Upstream・ライセンス

このリポジトリは[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)の**非公式fork**です。[元のREADME](README.upstream.md)は同じルートに保存しており、最新の一般向けllama.cpp説明はupstreamを参照してください。独自パッチの検証結果はupstream公式の保証ではありません。[MIT License](LICENSE)。モデルの使用・配布は各提供元の条件を確認してください。
