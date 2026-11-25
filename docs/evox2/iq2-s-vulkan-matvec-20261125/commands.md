# 実行条件・ログ

EVO-X2 の作業 clone は `C:\llama-build\automation\llama.cpp-evox2-windows`。SSH は `ssh -F /dev/null -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=yes`。

## ビルド

```powershell
$clang = 'C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\Llvm\x64\bin'
& .\tools\evox2\automation\Invoke-CodexBuild.ps1 -Backend Vulkan -BuildDir build-i2mv `
  -VulkanLlvmBin $clang -ExpectedVulkanClangVersion 22.1.3 -CpuAllVariants OFF -Offline
```

- Base は既存の `build-s2v\bin\Release`。実験版は `build-i2mv\bin\Release`。数値比較前に `llama-bench.exe` と `ggml-vulkan.dll` の SHA-256 をマニフェストと照合した。
- SDK による静的比較は [spirv.ps1](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/spirv.ps1)。元 GLSL と実験 GLSL をそれぞれ生成条件相当で glslc `-O` コンパイルし、SPIRV-Tools で定数を固定した。 `spirv-val` は16構成すべて通過。CSV の静的命令数は ID, NUM_COLS, NUM_ROWS, workgroup の指定を固定して求めた。
- 数値比較は [コンパイルコマンド](logs/validator-compile-command.txt) と [実行手順](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/validate.ps1)。ベンチマークとは別のプロセスで `GGML_VK_PIPELINE_STATS=iq2_s_f32` を使った。特定の2演算だけを呼び出す独立プログラムで、`test-backend-ops.exe`、自動スイープ、`-RunBackendTest` は使用していない。

## ベンチマーク

[bench.ps1](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/bench.ps1) を PowerShell 5.1 で実行。モデルは専用 clone のローカル設定 `Models.UnslothPle16.Path`。ファイル容量 81,961,816,672 bytes を照合した。各実装の切り替えはプロセス環境変数の有無で決まる。設定値は `1`、無効化時は削除。

| 構成 | 使用バイナリ | GGML_VK_IQ2_S_MATVEC_A1 | GGML_VK_IQ2_S_MATVEC_A2 |
|---|---|---|---|
| Base | build-s2v | 削除 | 削除 |
| A1 | build-i2mv | 1 | 削除 |
| A2 | build-i2mv | 削除 | 1 |
| A1+A2 | build-i2mv | 1 | 1 |

Logger OFF では `GGML_VK_PERF_LOGGER*` を削除。Concurrent Logger では `GGML_VK_PERF_LOGGER=1`、`GGML_VK_PERF_LOGGER_CONCURRENT=1`、`GGML_VK_PERF_LOGGER_FREQUENCY=1000000`。TG256 の実行順は Base/A1/A1+A2/A2、A1/A2/Base/A1+A2、A2/A1+A2/A1/Base。各ラウンドに Base を入れ、実行位置を変えた。Concurrent の順は Base/A2/A1/A1+A2。

```powershell
& $exe -m $model -p 0 -n $tokens -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 `
  -ngl 999 -ncmoe 0 -dev Vulkan0 -ctk f16 -ctv f16 -fa on --offline -v -o json
```

run ごとに実行引数、環境変数、P-MODE の前後、stdout、stderr 抜粋を [logs](logs) に収録した。完全な stderr、生の Vulkan プロパティ、数値検証結果を以下に保存。GPU ログの [SHA-256](raw-log-sha256.csv) も照合できる。

- 計測と数値検証 `C:\llama-build\_logs\codex\iq2s-matvec-20261125-a38ba149`
- ビルド `C:\llama-build\_logs\codex\build-Vulkan-Build-fd3f03de17e84084bbc3f54db0f42ab4.*`
- 数値比較ツールと SPIR-V `C:\llama-build\automation\iq2s-matvec-20261125`
