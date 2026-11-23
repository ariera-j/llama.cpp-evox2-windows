# Evo-X2 / Windows Vulkan: r1 基準版

2026-09-16の実機計測で使用した推論ソースを保存する基準版です。初期登録では新しい推論最適化を追加していません。

元forkのコミットは `5e085d123eead2e89b5c19f824fccb05727da6a2`。[r1パッチ](backport-r1/qwen38-upstream-r1.patch)を適用済みです。13件のupstream PRから必要部分を取り込んでおり、upstream全体の最新版への更新ではありません。[manifest](backport-r1/manifest.json)と[採用範囲](backport-r1/UPSTREAM-AUDIT-ja.md)を参照してください。

## 確認済みの条件

| 項目 | 条件 |
|---|---|
| PC / GPU | Evo-X2 128GB / Radeon 8060S |
| OS / ドライバー | Windows 11 Pro 25H2 / AMD 26.8.1 (LLPC) |
| BIOSのGPUメモリ割当 | 96GB |
| コンパイラー / SDK | LLVM 20.1.8 / Vulkan SDK 1.4.357.0 |
| コンテキスト / 実入力 | 65,536 / 61,789 tokens |
| K/V / batch / ubatch | f16 / 2,048 / 1,024 |
| MTP / 同時会話数 | OFF / 1 |

Unsloth UD-IQ3_XXSはPLE16変換後、AgentionはROCmFP4-FAST-v2-ple16を使用しました。両モデルとも上記条件で正常終了しています。変換前Unslothは96GB設定でWindowsごと停止した履歴があり、その条件の再試験を前提にしません。

代表的な通常計測です。profiler付きの回は含めません。入力内容、生成長、実行時の状態によって変動します。

| 96GB、LLVM、MTP OFF | PP (tok/s) | TG (tok/s) |
|---|---:|---:|
| 元fork + Unsloth PLE16、2回 | 220.24 / 221.42 | 22.90 / 23.07 |
| r1 + Unsloth PLE16、直後の2回 | 228.68 / 227.97 | 23.52 / 23.59 |
| r1 + Agention、2回 | 230.72 / 230.83 | 23.74 / 23.76 |
| r1 + Unsloth PLE16、後刻の再計測 | 232.44 | 23.70 |

`GGML_VK_FUSE_UNARY_MUL=1` は近接したOFF計測とほぼ同程度で、採用する根拠は得られていません。基準計測では未設定にします。このページはr1の記録です。QSA unionと128kの結果は[r2のページ](r2/README-ja.md)を参照してください。256k、MTP ON、MSVCとLLVMの最終比較は未完了です。

## LLVM 20.1.8でビルド

Git、Visual StudioのC++ Build ToolsとWindows SDK、CMake、Ninja、LLVM 20.1.8、Vulkan SDK、7-Zipを使います。

初期登録後に通常のcloneを行う場合:

```powershell
git clone https://github.com/ariera-j/llama.cpp-evox2-windows.git C:\llama-build\llama.cpp-evox2-windows
```

初期登録スクリプトがこのフォルダーを作成済みならcloneは不要です。「x64 Native Tools Command Prompt for VS」を開き、次を **cmd.exe** で実行します。インストール先は実際の場所に合わせてください。環境変数の変更はこのウィンドウ内だけです。

```cmd
set "PATH=C:\LLVM\20.1.8\bin;C:\Program Files\7-Zip;%PATH%"
set "VULKAN_SDK=C:\VulkanSDK\1.4.357.0"
clang --version
where clang
where cmake
where ninja
where 7z
cd /d C:\llama-build\llama.cpp-evox2-windows
cmake -S . -B build-llvm20 -G "Ninja Multi-Config" ^
  -DCMAKE_TOOLCHAIN_FILE=cmake/x64-windows-llvm.cmake ^
  -DGGML_VULKAN=ON ^
  -DGGML_NATIVE=OFF ^
  -DGGML_BACKEND_DL=ON ^
  -DGGML_CPU_ALL_VARIANTS=ON ^
  -DGGML_OPENMP=ON ^
  -DGGML_OPENMP_FETCH=ON ^
  -DLLAMA_BUILD_BORINGSSL=ON ^
  -DLLAMA_BUILD_EXAMPLES=OFF ^
  -DLLAMA_BUILD_TESTS=OFF ^
  -DLLAMA_BUILD_TOOLS=ON ^
  -DLLAMA_BUILD_SERVER=ON ^
  -DGGML_RPC=ON
```

configure成功後:

```cmd
cmake --build build-llvm20 --config Release --parallel 4 --target llama-server llama-cli llama-bench
build-llvm20\bin\Release\llama-cli.exe --version
build-llvm20\bin\Release\llama-cli.exe --list-devices
```

exeと同じディレクトリのDLLも必要です。MSVCで比較するときは別のビルドディレクトリを使い、SDKと機能設定を合わせます。コミット番号はこのリポジトリのものを自動表示させます。以前のパッチ配布版の表示を強制する指定は入れていません。

## UnslothのPLE16変換

既存の `gguf_split_ple_heads.py` を呼び、量子化済みデータを再量子化せず、結合されたPLEテーブルを16テンソルへ分けます。出力用に元モデルもう1個分の空き容量が必要です。

リポジトリのルートでPowerShellを開きます。

```powershell
py -3 -m venv tools\evox2\.venv
.\tools\evox2\.venv\Scripts\python.exe -m pip install .\gguf-py
.\tools\evox2\Convert-Unsloth-Ple16.ps1 `
  -InputModel 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-00001-of-00003.gguf' `
  -OutputModel 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' `
  -VerifyBytes
```

パスは実際の場所に置き換えます。元の全シャードを同じディレクトリに置き、最初のシャードを指定してください。元ファイルと既存の出力は上書きしません。検証後に `.partial.gguf` から最終名に変更します。`-VerifyBytes` は型・形状・メタデータに加え、使用する全重みのバイト列をSHA-256で照合するため追加の読み込み時間がかかります。

既に変換・動作確認済みのモデルはそのまま使えます。Agentionの既存PLE16版はこの変換の対象ではありません。

## 比較計測

公開用スクリプトでは個人用パスを既定値から外しました。CLI、モデル、入力を明示します。起動引数・ログ解析は従来のスクリプトを引き継いでいます。

```powershell
Remove-Item Env:GGML_VK_FUSE_UNARY_MUL -ErrorAction SilentlyContinue
Remove-Item Env:GGML_VK_PERF_LOGGER -ErrorAction SilentlyContinue
Remove-Item Env:GGML_VK_PERF_LOGGER_FREQUENCY -ErrorAction SilentlyContinue
.\tools\evox2\Measure-Qwen38-Ple16.ps1 `
  -LlamaCli 'C:\llama-build\llama.cpp-evox2-windows\build-llvm20\bin\Release\llama-cli.exe' `
  -ModelKind Unsloth `
  -ModelFile 'D:\models\Qwen3.8-Flash-Next-UD-IQ3_XXS-ple16.gguf' `
  -InputFile 'D:\bench\prompt.txt' `
  -Context 65536 -KvType f16 -UBatch 1024 -UmaVramLabel 96GB
```

`-DryRun` でファイルの存在と起動引数だけを確認できます。`-InputFile` の代わりに `-AllocationOnly` を指定すると短い入力の読み込み確認になります。これは長文PPの計測ではありません。Agentionでは `-ModelKind Agention` と対応する `-ModelFile` を指定します。既存のr1実行ファイルも指定でき、GitHubへの登録のために再ビルドする必要はありません。

出力先は実行したディレクトリの `evox2-logs` で、Gitの対象から除外しています。MTPは既定でOFF。GPUメモリ割当のラベルは手動指定で、BIOS設定を変更・検出するものではありません。

自動管理ページファイルでモデル読み込み中にコミット上限へ近づいた記録があるため、長コンテキストの試験前にコミット余裕を確認します。ページファイル設定はメモリ確保の余裕を作るための別の設定であり、速度改善そのものではありません。

## r2と出典

profilerでは純粋なPP区間のGPU時間の約42.7%を `FLASH_ATTN_EXT` が占め、後半の区間では約56.6%でした。QSA top-k単体は約0.44%。この内訳はprofiler付き測定であり、通常のPP/TG速度とは区別します。

[grouped-union sparse prefillの外部PR](https://github.com/Nathanw1014/llama.cpp/pull/11)を参考にしたQSA unionをr2として追加しました。クエリーごとのmaskを保ち、端数ubatch、GQA、数値の正しさ、Windowsドライバーの共有メモリ32KiB制約を確認しています。実装範囲とWindows結果は[r2のページ](r2/README-ja.md)に分離しています。Linuxで報告された倍率をWindowsの予測値にはしていません。

- [元fork](https://github.com/LaurentZuijdwijk/llama.cpp)、[upstream](https://github.com/ggml-org/llama.cpp)
- [採用PRのSHA・範囲](backport-r1/manifest.json)、[選定理由](backport-r1/UPSTREAM-AUDIT-ja.md)
- [r1配布時点の検証記録](backport-r1/verification.txt)。当時の記録であり、その後のWindows計測はこのページを参照してください。
- [元のWindowsビルド記事](https://qiita.com/ariera/items/d4026ad03775ebb1daa5)、[従来の計測記事](https://qiita.com/ariera/items/d4f123d9f47c0f120a1d)

元の著作権・MITライセンスを維持します。モデルの利用・再配布条件は各配布元のライセンスを確認してください。
