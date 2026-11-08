# ROCm HIP Flash Attention 実 `KV_max` 限定診断（2026-11-08）

**STATUS: default-OFFの診断用ソースと32k Layer19専用2バリアントを準備。ROCm実機のコンパイル・実行は未検証。** 既存b12164実測値に対して性能結果を追加・置換するものではない。

- 前段の結果・ソース監査：[R6 ROCm PP FA input dependence（2026-11-08 results）](R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md)
- 実装箇所：`ggml/src/ggml-cuda/fattn-common.cuh`、`flash_attn_mask_to_KV_max<ncols1>` のGPU launch後、FA MAIN発行前。
- 計測プラン：[qwen38-r6-rocm-fa-kvmax-diag-20261108.psd1](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-fa-kvmax-diag-20261108.psd1)
- ブランチ：`investigation/r6-rocm-fa-kvmax-diag-20261108`。既存b12164実行物とMoE/FA RGPのベンチ用buildを変更しない。

## 目的と最小スコープ

b12164 HIP FAの16k/32k/48k Layer19/23 matched RGPでは、コードと文学のMAIN時間差は最大約3.4%で、Vulkan QSAのmask tile skipによる2〜3倍差とは対照的だった。HIPの `flash_attn_mask_to_KV_max<16>` が **実際に64 Query tileごとにどの上限を返したか** をまず1点だけ調べる。

初回は**KV32768 / Layer19 / N1024** に限定。head32768 tokensでu31を含める。前回のhead61777と同じ先頭トークン列・UBatch設定・Contextを使うが、**全runの長さを短くするのでタイミング比較は一切しない**。コードを1回成功させたら文学を1回。追加の16kや48k・他Layerは**この時点では走らせない**。

### 診断を有効にする環境変数

```text
GGML_CUDA_DISABLE_GRAPHS=1
GGML_HIP_KVMAX_DIAG=1
GGML_HIP_KVMAX_DIAG_KV=32768
GGML_HIP_KVMAX_DIAG_LAYER=19
```

1. HIP Graphを無効化する。対応する `ggml_cuda_graph::is_enabled()` は `GGML_CUDA_DISABLE_GRAPHS` の**存在**でfalseとなる（`common.cuh`）。
2. 対象はQ名 `Qcur-19`、KV32768、N1024、単一シーケンス、Query tile64組（16 Query×64）。
3. GPUが直前に算出した `KV_max[64]`（**256 bytes**）を**同じstreamに非同期コピー→1回同期**。同期を行うrunのPP速度・GPU FA時間は無効な性能指標。
4. stderrに `evox2_hip_kvmax_diag_v1 ... values=[...]` を1行だけ出す。 `min/median/max/full_count/truncated_count/invalid_count/skipped_tiles256_total` と64個の実値を保存。
5. `GGML_CUDA_DISABLE_GRAPHS` がない状態で対象に達した場合、診断は明示的に中止する。通常は `GGML_HIP_KVMAX_DIAG` が未設定なので同期・コピーは行わない。
6. HIP専用の診断機能。CUDA/Vulkanは変更しない。元のFA mask・K/V・計算経路には介入しない（ただし診断runは同期によりスケジューリングが変化する）。

## 実機手順（PowerShell）

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git fetch origin
git switch --track origin/investigation/r6-rocm-fa-kvmax-diag-20261108

# 既存のb12164 build directoryを再利用・上書きしない
.\tools\evox2\build\Build-ROCm.ps1 -BuildDir .\build-rocm-fa-kvmax-r6 -Parallel 4 -AmdGpuTarget gfx1151
.\build-rocm-fa-kvmax-r6\bin\Release\llama-bench.exe --version
```

ローカルignored `tools/evox2/benchmark/configs/local.psd1` の **既存Builds表に以下を追加**（既存キーを置換しない）。

```powershell
R6RocmFaKvmaxDiag = @{
    BinDir = 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag\build-rocm-fa-kvmax-r6\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-fa-kvmax-diag-20261108.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# Gate1: コードのみ。RGPは起動しない。
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant kvmax-code-32768-layer19 -StopOnError
```

`stderr.log` に正確に1つの `evox2_hip_kvmax_diag_v1` があり、`query_tiles=64`、`invalid_count=0`、`full_count + truncated_count=64`、`0 <= min <= median <= max <= 32768` を確認する。もし出ない・GPU同期/Graph/ExitCodeエラー・TDRなどが起きたら文学runに進まず停止し、ZIPとstderrを調査する。

コード成功後のみ、同じビルドと設定で以下を1回：

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -OnlyVariant kvmax-literature-32768-layer19 -StopOnError
```

**判定:** 64/64が32768なら、そのFA opにおける256-Key単位の末尾スキップはゼロ。文学側も同値なら「内部のsparse mask形状が違ってもHIPの末尾scanでは実効KV短縮を得られない」ことをこの局所sampleについて実証できる。一方で `KV_max < 32768` があればskipした256-Key区間の個数・分布を両入力で比べる。結果をほかのKV/Layerや全PPに無断で一般化しない。

### 注意事項

- **新しいROCm実行物は未ビルド・未GPU検証。** 今回のソース変更自体の安全性/ビルド結果は実機Gateで確認すること。
- 専用ブランチ・専用buildに分離しているため、前日のRGPキャプチャで使用したb12164・モニタリング環境は変更しない。
- 解析用ZIP・stderrのhashと要約値をGitへ記録し、生の大きいRGP/ZIPは追加しない。
