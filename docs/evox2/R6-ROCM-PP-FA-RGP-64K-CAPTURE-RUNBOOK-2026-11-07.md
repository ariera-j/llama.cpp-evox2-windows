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

**計測スクリプトはGitHub調査ブランチを持つ `r6-ppdiag` worktreeから実行し、実行バイナリだけ別のr6本体ビルドディレクトリを指定する。** 以下はそれを分離した手順：

```powershell
Set-Location 'C:\llama-build\llama.cpp-evox2-windows-r6-ppdiag'
git branch --show-current
git pull --ff-only

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

## 2026-11-07 13:10 — HIP code capture PASS (unmatched KV/layer, exploratory)

**First ROCm code RGP successfully captured** without replacing existing frozen r6/COMMON-005 binary. User intentionally tried the **Vulkan RDP Dispatch range start=181200/count=512** in **API=HIP**; this happened to catch an FA kernel on HIP. This does **not** prove the same Vulkan dispatch ordinal, KV=49152 or Qcur-19. Initial calibration step from the Runbook is now fulfilled for the existence of HIP FA kernels, *not* for position matching.

### Original evidence and source identity

- Native ZIP `20261107-130748-235-bench-rocm-b12038-ctx65536-d5705f57f05b.zip` SHA256 **`5c5e10b70faadc5e677abe5a273326aff5c72b8ade71de92bfa1d3ee738aa1af`**.
- HIP RGP `llama-bench-20261107-131042215.rgp` SHA256 **`bdd4f8282dbf06fc7f6377157db1a0524d4407d043ca1f63977515c96067a997`**; original binary retained off Git.
- Actual program `C:\llama-build\llama.cpp-evox2-windows-r6\build-rocm-bench-real-r6\bin\Release\llama-bench.exe`, embedded **b12038/d321e7ff3**, exact executable SHA256 **`a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a`**; verified source commit **`d321e7ff38052be311fde9392598fe02c7548956`**. Log collection Git branch/head is separate: `investigation/r6-pp-fa-mask-rgp-20261105` / `557044b2...`.
- Inputs: `llamacpp-inference-code.txt`, SHA256 **`249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`**, `--prompt-slice head`, 61,777 tokens. Model `UnslothPle16` IQ3_XXS, ROCm Radeon8060S gfx1151 Wave32, ctx65536, batch2048, ubatch1024, f16 K/V, no generation, repetitions1, **no warmup**, Gather `QWEN4EXP_QSA_GATHER=0`. No Vulkan-only markers.
- Native result **OK / ExitCode=0**, PP **368.838634 tok/s** for one RGP-on run, wall 225.619s, GPU/ADLX high-load average **119.805 W**, authoritative P-MODE **Performance→Performance** with no warning and no GPU reset reported. PP figure is not a clean baseline.
- RGP Event timing screenshot, filter `fla`: event **421** `flash_attn_mask_to_KV_max<16>` **55.474 µs**; event **423** `flash_attn_ext_f16<256,256,16,4,false,false,false>` **98,000.337 µs = 98.000337 ms**. Both appear in one 512-dispatch window.
- Wavefront occupancy screenshot has a relatively steady low-to-moderate wave band through the long FA dispatch and no obvious large zero-occupancy gap in that interval; no numerical average occupancy or memory bottleneck proven. Other kernels and phases exist in the sampled range. This specialization mirrors earlier r5 PP HIP traces (previous ~105ms literature and ~111ms code at unknown KV).
- **The missing live progress is expected**: `Measure-LlamaBench.ps1` sends stderr into `stderr.log`, stdout to `llama-bench.json`; the native binary in these settings emits backend startup messages but **no per-UBatch/PP token-progress lines**. `Get-Content -Tail 20 -Wait` cannot show KV progress when the application doesn't log it. `--progress`, even if passed, only reports test/prompt start and not each 1,024-token update.

### Next smallest evidence-producing action

1. Keep **the same b12038 binary**/source model/context/UBatch/F16/Gather OFF, process and RDP **HIP / Auto Dispatch range / start=181200 / count=512 / SQTT High** for **one literature 64k run**, no code edits or warmup changes. The same HIP index across corpora is an **initial approximate GPU program-location comparison only**, NOT validated KV/layer matching. RDP must be set for the executable actually used, not Vulkan.
2. Execute `Invoke-BenchmarkMatrix.ps1 -Plan .\tools\evox2\benchmark\configs\qwen38-r6-rocm-pp-fa-rgp-64k-realprompt-20261107.psd1 -OnlyVariant rocm-literature-64k -StopOnError`. Save RGP and run ZIP. Compare event 421/423 kernel specialization and time with literature kernel in its own trace, but **do not call the pair KV49152/Qcur-19** without external proof. If same HIP start index fails to cover the same GPU-graph region due to content-dependent differences, record capture mismatch explicitly.
3. If the HIP code/literature FA time ratio is already close to unity, we have a strong *exploratory* indication corroborating earlier r5, but next decide whether strict per-layer position calibration warrants source change. For strong cross-backend claims require the latter. Only then consider default-OFF host-side per-UBatch/layer dispatch tracer, without assuming HIP supports Vulkan user debug markers. **Do not enable broad HIP FA backend tests**.
4. To see at least the **beginning** of prompt testing in future, a proposed `--progress` flag requires checking wrapper support/behavior; it does not solve KV pinpointing and need not be added for this exploratory pair.

### Interpretational cautions

- HIP `flash_attn_mask_to_KV_max<16>` detects suffix and is not identical to Vulkan `EVOX2_FA_MASK_OPT` tile-classification stage; do not compare 55µs vs Vulkan 4ms as same operation.
- HIP code FA MAIN98.0ms and Vulkan code FA MAIN44.83ms cannot be interpreted as direct speed ratio: the HIP event has **unknown KV/layer** and is a separate source revision. Need comparable totals, not a single chosen dispatch, to explain whole-run ROCm/Vulkan PP.

## 2026-11-07 13:26 — HIP literature capture PASS; same-index code/literature FA are almost identical

**Gate2 exploratory HIP paired observation completed**, no code edits. Both captures are the same **ROCm b12038/d321e7ff3** `llama-bench` binary, same UnslothPle16 IQ3 model, 61777 tokens/head, ctx65536, UBatch1024, Batch2048, no-warmup, no generation, QWEN4EXP_QSA_GATHER=0, P-MODE Performance. The different inputs are validated against the earlier SHA256 manifests.

| RGP field | Code (13:10) | Literature (13:26) |
|---|---:|---:|
| API | HIP | HIP |
| Auto capture | Dispatch range | Dispatch range |
| RDP start / count | **181200 / 512** | **181200 / 512** |
| Event 421 `flash_attn_mask_to_KV_max<16>` | **55.474 µs** | **47.822 µs** |
| Event 423 `flash_attn_ext_f16<256,256,16,4,false,false,false>` | **98,000.337 µs** | **98,447.049 µs** |
| MAIN ms | **98.000337** | **98.447049** |
| Native PP tok/s, profiled | 368.838634 | 375.711898 |
| Native result / P-MODE | OK / 0 / Performance | OK / 0 / Performance |

- **Literature/Code HIP FA MAIN ratio = 1.004558× (+0.4558% or +0.446712 ms literature)**. Suffix scan difference is only **−7.652 µs literature**. Thus the observed HIP FA input dependency at the sampled dispatch is tiny, unlike prior **strictly matched Vulkan KV49152 Qcur-19** literature/code MAIN ratio **133.210264/44.829555=2.971×**. **Caveat: the HIP pair lacks independently confirmed KV49152/layer19** and is built at an earlier source revision than Vulkan b12133.
- Both HIP RGP event numbers **421 (suffix scan) / 423 (FA main)** and **same kernel template** match between inputs; using the same *HIP* Dispatch range is a useful **same-relative-program-location** control. It is stronger than comparing arbitrary RGP snapshots, but **RDP same index and event id alone do not prove same KV/layer**.
- Literature native ZIP: `20261107-132316-840-bench-rocm-b12038-ctx65536-e38bc6abba27.zip` SHA256 `0e9e66782ba150b086b3f1f4d3d677556fa44268b565b40f21f5a182c9b89aed`, bytes 30575; input `wagahaiwa_nekodearu_utf8.txt`, SHA `8db20100f2244509b2ef13104691bb91650e98476bd5609f19e15ae91e79d143`, result `OK/ExitCode0`; PP `375.711898` tok/s, full-run wall `223.096s`, P-MODE unchanged, high-load ADLX power `119.21W`, no warnings.
- Literature HIP RGP: `llama-bench-20261107-132609191.rgp`, SHA256 `79744ed4b8f1928382acfb14d0f7ffdcc1af2bc1a8b44e0f91c8a8d51a4d0e41`, bytes `288054835` (original large RDF binary kept off Git). Source of 47.822/98447.049 µs timings: user-supplied RGP Event timing screenshot `image(20261107-043134).png`, SHA256 `a399bc90b1e341a87cae681b2fdad23e1cac34719a8ef9accaa51f1cfec79118`. Wavefront screenshot `image(20261107-043140).png`, SHA256 `ce299a4ccc68a424ad2a56680dc581cb3f4466a0fd11cf35bc75365aa64f936e`.
- Previously verified code: `20261107-130748-235-bench-rocm-b12038-ctx65536-d5705f57f05b.zip`, SHA256 `5c5e10b70faadc5e677abe5a273326aff5c72b8ade71de92bfa1d3ee738aa1af`; RGP `llama-bench-20261107-131042215.rgp` SHA256 `bdd4f8282dbf06fc7f6377157db1a0524d4407d043ca1f63977515c96067a997`. Code input SHA `249511db693de1092696fa46a6b8d3369c8f5d1a167ec854c4a4ace95717b345`.
- Both native `llama-bench.exe` SHA `a46e512cdc78ab2475b52d5d1d694ec968edade16c9229f95ced3380d559298a` (source `d321e7ff38052be311fde9392598fe02c7548956`). HIP `ggml-hip.dll` loaded in both; no Vulkan backend. Run contexts match and files are verified; native progress remains unavailable in stderr by design.
- ADLX sampling near RGP filename times: code **13:10:41.541** GPU `2884MHz, 800MHz VRAM, 100%, 120W`; literature **13:26:08.722** GPU `2884MHz, 800MHz VRAM, 100%, 120W`. This is **sampling near profile file timestamps**, not necessarily synchronized to the captured GPU event; it rules out obvious gross mode mismatch but not per-kernel clock variation.
- Literature Wavefront occupancy includes a long comparatively low nearly flat wave band through MAIN, resembling code. The **RGP profile is a bounded window**, not a full-PP GPU-time decomposition. No precise occupancy percent or per-tile cost inferred.

### Interpretation and next decision gate

**What is supported:** at the same HIP capture index, both corpora execute nearly-identical duration of the same HIP FA template even though the model/inputs' QSA mask distributions were previously found to differ markedly in Vulkan. Existing HIP code disables the NVIDIA CUDA sparse KV-index gather path; HIP uses a suffix mask scan, not Vulkan's per-interior-tile skip. This matches the hypothesis of weak ROCm input dependency. It is **not proof** that HIP ignores the mask entirely or that the two captures are at exactly the same KV49152/Qcur-19. The profiled PP ratio literature/code **1.0186×** also remains a diagnostic not a clean-speed benchmark.

**No immediate 64k repeat needed.** Decide with the user whether this exploratory r6 HIP evidence suffices for a high-confidence *qualitative* conclusion or to proceed with a **minimal HIP host-side KV/layer and dispatch ordinal trace** (default-OFF; no GPU kernel modifications; validate host↔RGP correlation), then reacquire one correctly annotated code/literature pair. Do not blindly use Vulkan RDP markers on HIP, infer KV from event index, or start a broad ROCm 4x2xN matrix. Avoid unsafe Windows gfx1151 HIP broad backend test suite and forced GPU synchronization.

The main ongoing technical outcome is a plausible source-backed explanation for the **Vulkan PP content sensitivity vs weak ROCm sensitivity**; strict equal-KV/source causal quantification is explicitly still open.
