# ROCmFP4 FAST HIP-2B 独立再レビューと HIP-2C 引き継ぎ

2026-11-28、運用者から ChatGPT 独立再レビューの **GO** が通知された。対象は `changes-hip2b-final.patch`（SHA-256 `63d333acb41963ac6d073e3d9c5ccf300160b4862bcb4d41d8aa895af08f8fee`、9ファイル、+1058/−2）。ChatGPT 側で Python fixture の10件を再照合し、全参照 SHA-256 が報告書と一致した。実機の9ファイルとレビュー版の Git blob、stage 後の内容、差分の空白検査を確認して固定した。[実装・CPU参照・静的検証報告](B12651-ROCMFP4-HIP2A-IMPLEMENTATION-20261128.md)

| 用途 | 完全 SHA |
|---|---|
| 製品基準 | `a650d641ee99198543697e1e3913c593059721f7` |
| HIP-1文書・今回の運用文書同期元 main | `244ec7a97d5206e897786481b4b34cedf3173521` |
| 実装コミット | `f19d5c75f68ae25bbd5a95b223e67d816c97e2fc` |
| 実験ブランチ `codex/b12651-rocmfp4-hip2-20261128` の文書同期後 HEAD・HIP-2C ビルド元 | `cab3886c3e76c6cb0716be62a60bfe752d9c0b7c` |

同期は EVOX2-ENVIRONMENT.md と KNOWN-ISSUES.md のみ。Windows コンパイル、GPU 数値、scheduler の実配置、実モデルは未検証。製品採用の判定は保留。

## レビューで確認した範囲

- High 1 は重みの同一device制限を維持し、scheduler が入力をコピーする場合と iGPU で ROCm_Host を保持する場合を扱う。必要な activation は H2D staging、host ID は同期後に stride と span を保って読み、pinned dst は D2H で返す。FAST の通常・ID 両演算を graph capture から除外した。
- Medium 1 はケース6の K160・NC padding を維持した。非ゼロ積の相殺で厳密なゼロ5個、非ゼロかつ絶対値 1e-6 以下5個、一般の正負値を含む。Medium 2 はケース9の skip slot と 9-Z の全出力を +0 のビット列で照合する。Medium 3 は geometry、サイズ、active ID と期待 SGEMM 数の検査を native entry の実行前に移した。

| 後続検証 | ケース | 要求する演算・件数 |
|---|---|---|
| 直接backend・実装済み | 1、1-NC、2、2-C | converter 各1件、SGEMM 各0回 |
| 同上 | 5、6 | MUL_MAT 各1件、SGEMM 各1回 |
| 同上 | 7、8、9、9-Z | MUL_MAT_ID 各1件、SGEMM は順に2、2、3、0回 |
| scheduler・未実装 | S-HC-CPU | 通常CPU入力の split copy、MUL_MAT 1件、SGEMM 1回 |
| scheduler・未実装 | S-HC-PIN | pinned 入出力で FAST 内 H2D/D2H、MUL_MAT 1件、SGEMM 1回 |
| scheduler・未実装 | S-ID-PIN | pitched host ID view を保持、MUL_MAT_ID 1件、SGEMM 2回 |

直接backend 10件と scheduler 3件の結果を別に記録する。GPU数値はビルド後の別承認で1プロセス1ケース、1 worker、ROCm0、各60秒上限。割当・コピー・演算件数・SGEMM数の不一致、fallback、skip、timeoutで停止する。scheduler 3件の実装・検証完了まで実モデルを実行しない。

## Hydrogen Medium 向けビルド案（個別承認待ち）

短い登録済み clean worktree で完全 SHA と GitHub の実験ブランチを照合し、各版に未使用の build 先を確保する。以下はその worktree のルートから実行する案。通常版は標準外側ラッパーの既定値、テスト版は内側へ限定 BOOL を渡す。共通ツールの変更はない。

```powershell
$sha = 'cab3886c3e76c6cb0716be62a60bfe752d9c0b7c'
$outer = '.\tools\evox2\automation\Invoke-CodexBuild.ps1'
& $outer -Backend ROCm -Worktree -SourceCommit $sha -BuildDir build-h2n -PreflightOnly -Offline
& $outer -Backend ROCm -Worktree -SourceCommit $sha -BuildDir build-h2t -PreflightOnly -Offline
# 通常版（ビルド承認後）
& $outer -Backend ROCm -Worktree -SourceCommit $sha -BuildDir build-h2n -Offline
```

各段階で終了状態とログを確認し、失敗時は停止する。外側は任意 CMake 引数を公開していない。テスト版の内側呼び出しは次工程の明示承認と、下記の worker 同等の検査が前提。外側の preflight 子プロセスで準備した環境は親シェルに残らない。同じ VS2022 x64 Native Tools と TheRock venv をテスト版のプロセスにも設定する。

```powershell
$sdk = 'C:\TheRock\build\.venv\Scripts\rocm-sdk.exe'
$params = @{
    BuildDir = (Join-Path (Get-Location) 'build-h2t')
    DependencyCacheRoot = 'C:\llama-build\automation\_deps'
    Configuration = 'Release'
    Parallel = 4
    ExpectedRocmSdkVersion = '10.0.0'
    AmdGpuTarget = 'gfx1151'
    RocmPath = (& $sdk path --root).Trim()
    RocmBin = (& $sdk path --bin).Trim()
    RocmCmakePath = (& $sdk path --cmake).Trim()
}
$options = @('-DLLAMA_BUILD_UI=OFF','-DLLAMA_USE_PREBUILT_UI=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON','-DGGML_HIP_ROCMFP4_TEST:BOOL=ON')
& .\tools\evox2\build\Build-ROCm.ps1 @params -ConfigureOnly -ExtraCMakeArgs $options
# cache・生成ターゲットと来歴を照合した後のみ
& .\tools\evox2\build\Build-ROCm.ps1 @params -BuildOnly
```

1. 固定SHAの Invoke-CodexBuild.ps1、Invoke-CodexBuildWorker.ps1、Build-ROCm.ps1 の hash と起動引数・ログを保存する。開始・終了時の clean と SHA、worktree、ACL、絶対パス長、依存キャッシュの BoringSSL / LLVM OpenMP の採用元・hash を標準ラッパーと同条件で検証する。ダウンロードは禁止。
2. VS 17.0、host/target x64、MSVC 14.44、VS 配下の CMake 3.31.6-msvc6 と Ninja 1.12.1、TheRock rocm-sdk 10.0.0 とその root 配下の AMD clang/clang++ 23.0.0（git suffix 可）を絶対パスと版で照合する。Worker と同じ legacy ROCm 7.2 排除、HIP_PATH/ROCM_PATH、bin/cmake の root 配下検査を行う。
3. 両 cache で UI の2項目 OFF、disconnected ON、GGML_HIP ON、AMDGPU_TARGETS=gfx1151 を確認する。テスト版のみ GGML_HIP_ROCMFP4_TEST:BOOL=ON、define と harness.cpp が ggml-hip target に入ること、通常版は未指定または OFF を照合する。
4. 各 bin/Release/evox2-build.json で BuildIdentity.Status=Verified、Source.Commit がビルド元と一致、Backend=ROCm、llama-cli.exe の SHA-256 が ExecutableIdentity.Sha256 と一致すること。標準 BuildOnly は CLI smoke を含むため、その承認範囲も先に確認する。SmokeSkipped=false、--version と --list-devices の終了0、ROCm0 Radeon 8060S を照合する。
5. amdhip64_7.dll、rocm_kpack.dll、amd_comgr.dll、hipblas.dll、rocblas.dll、rocsolver.dll、libhipblaslt.dll、origami.dll と rocblas/hipblaslt データツリーを照合する。RuntimePolicy.Verification=DllAndRuntimeDataHashesVerified、Test-Evox2RuntimeArtifacts が Verified / RuntimeDependenciesV1 を要求する。ggml-hip.dll と ggml-base.dll の PE 推移依存・解決先も版ごとに確認する。
6. 各 DLL の export 表を取得し、evox2_hip2a_case は通常版0件、テスト版1件と照合する。版別 cache、export 表、DLL の絶対パス・SHA-256、manifest を保存する。検査不足・不一致で停止する。

```powershell
foreach ($dir in 'build-h2n','build-h2t') {
    $dll = (Resolve-Path "$dir\bin\Release\ggml-hip.dll").Path
    $exports = & dumpbin.exe /nologo /exports $dll
    if ($LASTEXITCODE -ne 0) { throw "dumpbin failed: $dll" }
    $count = @($exports | Select-String '\bevox2_hip2a_case\b').Count
    if ($count -ne [int]($dir -eq 'build-h2t')) { throw "unexpected export count: $dll" }
    Get-FileHash -Algorithm SHA256 -LiteralPath $dll
}
```
