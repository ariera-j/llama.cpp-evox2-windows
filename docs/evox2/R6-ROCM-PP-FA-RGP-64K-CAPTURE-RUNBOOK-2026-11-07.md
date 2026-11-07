# ROCm/HIP 64k PP Flash Attention RGP — 実入力計測Runbook（2026-11-07）

**作成済み、未実行。コード変更・ビルド・GPU計測はしていない。** 前回Vulkanの同条件調査の次段。最初はROCmコード1回だけでHIP RGP kernelを確認し、文学はその後にする。

- Plan: [qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107.psd1](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107.psd1)
- RDP values: [qwen38-r6-rocm-pp-fa-rgp-64k-rdp-settings-20261107.json](../../tools/evox2/benchmark/configs/qwen38-r6-rocm-pp-fa-rgp-64k-rdp-settings-20261107.json)
- Background: [r6 ROCm PP investigation plan](R6-ROCM-PP-FA-INPUT-DEPENDENCE-PLAN-2026-11-07.md), [Vulkan final report](https://github.com/ariera-j/evox2-llm-experiments/blob/main/benchmarks/pp-input-dependence-64k-20261104/runs/2026-11-07-vulkan-pp-input-dependence-consolidated-ja.md)

## 重要：ユーザーが持っている3系統のROCmビルド

| Build | 確認済み/推定系統 | 実入力 `llama-bench -f` | 初回RGPでの扱い |
|---|---|---|---|
| `CombinedROCm` | r6統合 b11908 | **非対応**（そのcommitのソースを確認） | 保存、初回使用しない |
| `R6RocmCommon005` | COMMON-005追加 b12013 | **非対応**（移植前のソースを確認） | 保存、初回使用しない |
| **`R6RocmRealPromptRgp`**（新しいlocalビルドキー） | **実入力 `llama-bench` b12038 / `d321e7ff3`**、2026-11-03のROCm実機smokeで確認済み | **対応済み** | **使用する** |

この3つは別の比較軸。COMMON-005は `QWEN4EXP_QSA_GATHER=1` として動作する可能性があるが、最初は**すべてGather OFF**で固定し、Vulkanとの**入力条件**比較を優先する。b12038はb12133 Vulkanと厳密に同じsource commitではないため、差をすべてbackend効果と断定しない。後で厳密なsource-paired比較が必要になった場合にだけ、同じ調査sourceのROCm buildを別ディレクトリに用意する。

**古い2本は実入力対応前のため、旧 `llama-bench.exe` に `-f` を渡してはいけない。** 代わりに `llama-cli` を使う場合は、元コード6MBや文学全文をそのまま`-f`で与えると、Vulkan benchの先頭61,777 tokenスライスとは一致しない。CLI自体のBOS/プロンプト構成に過去12 token程度の差もあった。raw長文をctx65,536へ暗黙切り詰めする方法は本比較に使わず、別途トークンprefix fixtureと入力token列の検証を設計する。

## Gate0: 使うバイナリと実入力ファイルの確認

PowerShellで既存r6本体（調査ドキュメントを更新するworktreeと実測バイナリの場所は異なってよい）を使用：

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6'

$binDir = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-bench-real-r6\bin\Release'
$exe = Join-Path $binDir 'llama-bench.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    throw "実入力対応 b12038 が見つかりません: $exe"
}
& $exe --version
$helpText = (& $exe --help 2>&1 | Out-String)
if ($helpText -notmatch '\-\-prompt-file' -or $helpText -notmatch '\-\-prompt-slice') {
    throw 'この llama-bench.exe は実入力未対応です。ここで停止し、別ビルドかビルドし直しを検討します。'
}
Get-FileHash $exe -Algorithm SHA256

$code = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\qsa-code-test\llamacpp-inference-code.txt'
$lit  = 'C:\Users\ai\Desktop\qwen38-flash-next-evo-x2\test_input\qsa-test\wagahaiwa_nekodearu_utf8.txt'
$expectedCode = '249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345'
$expectedLit  = '8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143'
foreach ($item in @(@($code,$expectedCode),@($lit,$expectedLit))) {
    if (-not (Test-Path -LiteralPath $item[0])) { throw "Input missing: $($item[0])" }
    $hash = (Get-FileHash -LiteralPath $item[0] -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $item[1]) { throw "Input SHA mismatch: $($item[0]) $hash" }
}
"Binary input capability and original input hashes PASS"
```

もしb12038が残っていなければ、そのまま旧binへ置き換えず、既存の`feature/r6-llama-bench-real-prompt-20261103`等から別名のROCm実入力対応バイナリを作るか相談する。ビルドは今回のプラン作成では実行していない。

### `local.psd1`（Git管理外）の新規BuildKey

`tools/evox2/benchmark/configs/local.psd1`内の**既存 `Builds = @{ ... }`** に、この1項目だけを追記する（重複する `Builds` 全体を作り直さない）。

```powershell
R6RocmRealPromptRgp = @{
    BinDir          = 'C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-bench-real-r6\bin\Release'
    ExpectedBackend = 'ROCm'
}
```

**BuildKeyは同じでも実行時のバイナリSHAを毎回記録する。** 旧`CombinedROCm`、`R6RocmCommon005`のaliasは変更しない。ライブラリ探索順で別の `ggml-hip.dll` をロードしていないかstderrと実行ログから確認する。

## Gate1: PlanOnly → 1024 smoke（必要時） → コード64k実行

既にb12038で実入力の小さいsmokeを完了しているため、同じバイナリSHA・runtimeであれば今回のsmokeは任意。新しいバイナリの場合はsmokeを先に実施。

```powershell
$plan = '.\tools\evox2\benchmark\configs\qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107.psd1'
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 -Plan $plan -PlanOnly

# Optional if the verified b12038 is not demonstrably the same executable:
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant rocm-code-smoke-1024 -StopOnError

# RDPを設定してから、まずコード入力だけ。
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant rocm-code-64k -StopOnError
```

`-PlanOnly`で3バリアント（smoke、code64k、literature64k）が**別々のrun**として表示されることを確認。入力、model、BuildKey、UBatch、Gather OFFを確認する。コード64kのNativeRowCount1, ExitCode0, `PromptTokens=61777`、実入力ファイルSHA、ROCmバックエンドがロードされたことを検証。

## Gate2: Radeon Developer Panel / GPU Profiler でHIP FAを検出

GUI設定（初回は**探索キャプチャ**、KV/layer一致を前提としない）:

| RDP設定 | 初回 |
|---|---|
| Auto connect | Any application |
| API | **HIP**（Vulkanではない） |
| Target | ROCmの `llama-bench.exe` |
| Capture mode | Dispatch |
| Auto capture | **None / manual capture** |
| Dispatch count | **512** |
| SQTT buffer size | High |
| Instruction tracing / counters / shader instrumentation | すべてOFF |
| Hotkey | RDPで表示中の設定。初回手動ならUIのCaptureボタンでもよい |
| 出力 | 新規別名`.rgp`; 元のVulkan・r5 HIP profileを上書きしない |

CPU開始時刻だけでなく、**モデル読み込みが完了してPP実行が進行中**のタイミングにCaptureする。512 dispatchでどのKV/layerが写るかは保証されない。最初の一回ではカーネル名を確認することが主目的。

RGPで検索するカーネル候補:
- **`flash_attn_ext_f16<...>`**（r5 64k PPで見えたHIP MMA FA MAIN、b12038で同じとは限らない）
- **`flash_attn_mask_to_KV_max<...>`**（suffix mask scan）
- `flash_attn_tile<...>` （r6 128k 1-token TGで見た別方式。64k PPでは別のFAテンプレートが選ばれ得る）
- `lightning_indexer`、`top_k_mask_kernel`、`k_get_rows_float`、MoE matmul / GDN

実測記録：Profile file名+SHA、`RDP capture mode/count/start/time`、実行bin SHA、カーネル文字列/shape、GPU Duration(us)、grid、occupancy、VGPR/LDS/SGPR、対象のFAとscanの対応、GPU idle/queue状態。**HIP RGPはVulkanの`EVOX2_FA_`ユーザーマーカーに対応しない**ため、RGP名だけでKV49152やlayer19と断定しない。

位置合わせは **Gate2.5**：RDPのHIP固有dispatch indexと実行ログから推定し、精度を検証してから同一KV/layerとして比較。Vulkanの `start=181200` をHIPにコピーしない。確認不能なら、Gate3でdefault-OFFのhost診断（KV/layerとdispatchを記録）を実装するか判断する。

## Gate3: Literature capture (after code HIP capture validated)

```powershell
.\tools\evox2\benchmark\Invoke-BenchmarkMatrix.ps1 `
    -Plan $plan -OnlyVariant rocm-literature-64k -StopOnError
```

Code/Literatureが**同一HIPカーネル・KV・layerで確認された場合のみ**Vulkan Qcur-19 MAINコード44.830ms、文学133.210msと厳密に比較。HIPでscan maskが存在したらスキャンとMAINを区別する。旧b11908/b12013でのGather ON/OFF差は別の追試とし、初回のコーパス比較には混ぜない。

## Stop / safety

- Win11 gfx1151 ROCmでは過去にwatchdog/VIDEO_ENGINE_TIMEOUT_DETECTED(141)・HIP backend wide FA testで障害履歴がある。**`Build-ROCm.ps1 -RunBackendTest` や broad FA test suiteは禁止**。
- モデルをVulkanと並列ロードしない。RDP/Vulkan profileを同時に使わない。イベントの取得に失敗したら長大な繰り返し計測に進まず、UIやHIP kernel detectionを確認する。
- OOM、TDR、GPU reset、HIP trap、P-MODE変更、著しいクロックドロップや持続pagingが見えたら停止。
- profiler中のPP tok/sは診断用の参考のみ。過去のUnprofiled PPスループットと直接速度差として比較しない。
- 生RGPはGit外保管。GitHubへは設定・キャプチャ要約・SHA・計測表のみcommit。

## 現状と依頼する最初の結果

- **今回の成果：計測Plan + RDP値 + Runbook作成のみ。** 新GPU計測なし。古い2バイナリは保全。
- 最初は `--help` 実入力確認・バイナリSHAと `-PlanOnly` を実施し、成功すればコード1回のROCm HIP RGP（`.rgp`またはイベント一覧スクショ）＋実行ZIPを提出。
- ビルドキーやb12038バイナリが見つからない場合、旧バイナリへの単純差し替えはせず、その情報で計測対象を再決定する。
