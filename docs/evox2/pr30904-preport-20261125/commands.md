# 再現条件とログ

## Baseline の確認

EVO-X2 の専用 clone `C:\llama-build\automation\llama.cpp-evox2-windows` で読み取りを実施。SSH は `-F /dev/null -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o StrictHostKeyChecking=yes`。

```powershell
git --no-optional-locks status --porcelain=v1 --branch
git rev-parse HEAD
git diff --name-only eea8dcefc HEAD
Get-FileHash -Algorithm SHA256 -LiteralPath @(
    'build-s2v\bin\Release\llama-bench.exe',
    'build-s2v\bin\Release\ggml-vulkan.dll'
)
Select-String -LiteralPath 'build-s2v\CMakeCache.txt' -Pattern '^GGML_CPU_ALL_VARIANTS:'
& 'C:\Windows\System32\vulkaninfo.exe'
```

PR は GitHub のコミット API で完全 SHA、親、変更ファイルを確認。GitHub の Baseline blob 3ファイルを一時ディレクトリに配置し、そこから以下を実行した。

```text
git apply --check --verbose ../pr.patch
```

`pr.patch` は `https://github.com/ggml-org/llama.cpp/commit/c1d245bc3d1c416f74f1e108b0f60fa2a699dbf1.patch`。適用チェックのログは [patch-check.txt](logs/patch-check.txt)。

## GGUF

専用 clone の Git 管理外設定 `tools/evox2/benchmark/configs/local.codex.psd1` を `Import-PowerShellDataFile` で読み、`Models.UnslothPle16.Path` と `Models.AgentionRocmFp4FastPle16.Path` を取得した。Windows の Python 3.14 標準ライブラリで `Path.open('rb')` し、little-endian の GGUF v3 magic、テンソル数・メタデータ数、メタデータ、テンソルディレクトリを読んだ。配列メタデータは不要な値をスキップし、テンソル payload の領域へは読み進めていない。テンソルごとに `name, dimensions[ne0...], ggml_type, relative_offset` を記録した。総 payload は量子化ブロック単位で計算し、アラインメントと `llama-bench` のサイズで照合した。 [標準型のブロック定義](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/gguf-py/gguf/constants.py#L7571) · [ROCmFP4](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/rocmfp4/rocmfp4.h) · [ROCmFPx](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/rocmfpx/rocmfpx.h)

## ベンチマーク

各モードは別の `llama-bench.exe` プロセスで順次実行した。P-MODE は `Get-Evox2PModeMetadata` で開始・終了時に読む。モデルの実パス、正確な引数、開始時刻は各 `*.command.json` に保存した。プロセス環境を初期化し、logger の無効化には変数の削除を用いる。コードは環境変数の存在を検査する。

```powershell
# Windows PowerShell 5.1、専用 clone のルート
$exe = (Resolve-Path 'build-s2v\bin\Release\llama-bench.exe').Path
$cfg = Import-PowerShellDataFile 'tools\evox2\benchmark\configs\local.codex.psd1'
$model = $cfg.Models.UnslothPle16.Path
# FAST は $cfg.Models.AgentionRocmFp4FastPle16.Path
$env:GGML_VK_PERF_LOGGER = $null
$env:GGML_VK_PERF_LOGGER_CONCURRENT = $null
$env:GGML_VK_PERF_LOGGER_FREQUENCY = $null

# 個別モードの場合
$env:GGML_VK_PERF_LOGGER = '1'
$env:GGML_VK_PERF_LOGGER_FREQUENCY = '1000000'
# 並行モードの場合は、さらに $env:GGML_VK_PERF_LOGGER_CONCURRENT = '1'
# OFF の場合は3変数の削除だけで実行

& $exe -m $model -p 0 -n 32 -d 0 -r 1 --no-warmup -b 2048 -ub 1024 -t 4 `
    -ngl 999 -ncmoe 0 -dev Vulkan0 -ctk f16 -ctv f16 -fa on --offline -v -o json
```

実行時は `Start-Process -Wait` で stdout / stderr を別ファイルに保存した。ドラフトモデルや speculative decoding の設定を持たない `llama-bench` の TG ループで MTP OFF。 `--no-warmup` と `-d 0` により別の warmup／depth グラフを除外し、大きい logger frequency と teardown の `print_timings(true)` で各計測を1ブロックにまとめた。 [TG ループ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/tools/llama-bench/llama-bench.cpp#L2201) · [logger の集計](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/f4f1aa3e85124fed75a891ec63a1504536049eff/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L17894)

## ログの保存先と集計

- 実機の生ログ：`C:\llama-build\_logs\codex\pr30904-20261125-000430-b6f68c44`（個別、OFF）。並行：`C:\llama-build\_logs\codex\pr30904-concurrent-20261125-000830-2bc8611f`。GPU プロパティの全量も同ディレクトリの `vulkaninfo.txt` に保存。
- 公開記録の [logs](logs) は bench stdout JSON、コマンド、終了コードと P-MODE、stderr のデバイス／設定抜粋と完全な `Vulkan Timings` ブロック、ビルド証跡を含む。完全な stderr の SHA-256 は [raw-log-sha256.csv](raw-log-sha256.csv)。
- [vk-timings.csv](vk-timings.csv) の `interval_count` と `sum_us` は logger の `count x mean = sum` の値。`sum_us_per_token` は32で割った値。`percent_of_logger_total` は logger の `Total time` に対する比率。出力は有効桁で丸められる。並行モードの行はグループ単位で、個々の演算型や shape に配賦する列は空欄。 [runs.csv](runs.csv) の `bench_tg_wall_s` は stdout JSON の `samples_ns[0] / 1e9`。
