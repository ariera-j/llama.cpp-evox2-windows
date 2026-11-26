# b12651 系 モデルロード診断の実装とビルド検証（作業4-3、2026-11-26）

作業4-2で、通常対照と同程度の読み取り帯域が起動後約48秒まで続いた後、約55～60 MiB/sと低いGPU稼働率の区間が延びる現象を捕捉した。R34R3D と R42 の RAM 使用ピークから Context 開始報告までは8.555秒と8.558秒。サンプル間隔と受信遅延を含むため、近さは同じ処理段階を探す手掛かりとして扱う。R42 は OS 稼働約11時間で、一連の計測の初回に発生した。ReadFile と転送・イベント待ちを同じ優先度で調べる。 [既存調査（作業4-1）](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/b72c415c7a62e804b2cc80a478ed8a8531a7c566/docs/evox2/automation/B12651-MODEL-LOAD-INVESTIGATION-20261126.md) · [基準計測（作業4-2）](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/c45e17a0da9a5f4cda0268c9ec0a0452c5caef35/docs/evox2/automation/B12651-MODEL-LOAD-BASELINE-20261126.md)

## 基準と変更範囲

- GitHub main の開始時点は `c45e17a0da9a5f4cda0268c9ec0a0452c5caef35`。現行製品ブランチ `codex/vulkan-manifest-cpu-variants-20261124` の `f500e9b070f3e6065dde50309def74d83cf9ddd4` から `codex/model-load-diag-20261126` を作成した。旧 Stage 2 b12676 の `eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1` との差分は文書、運用・計測ツール、Vulkan マニフェストの CPU variant 表示・検証。`src`、`ggml`、`common`、`include`、CMake 設定に差分なし。
- 実装コミット `d32cdfaf1c86739b6479260e6324d1394081cf50`。新規 `src/llama-model-load-diag.h`、`tests/test-model-load-diag.cpp` と、`src/llama-model.cpp`、`src/llama-model-loader.cpp`、`src/llama-model-loader.h` の計5ファイル。バックエンド・計測・ビルドツールに変更なし。 [実装差分](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/d32cdfaf1c86739b6479260e6324d1394081cf50)
- EVO-X2 専用 clone は現行製品ブランチを維持した。レビュー用 Markdown は元のパスに保全した。実装の実機確認は新規 worktree `C:\llama-build\automation\w43diag` で実施。

## 診断の動作

`LLAMA_MODEL_LOAD_DIAG=1` で有効。未指定、空文字、`0`、その他の値は OFF。`llama_model_base::load_tensors` の入口で一度判定し、no-alloc の予備計算では無効。同じ `ggml_time_us` のモデル基準時計を使い、ネイティブタイマーを上書きしない。元の呼び出しの引数、順序、バッファ数、イベントと転送方式を保持した。 [フラグ処理](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d32cdfaf1c86739b6479260e6324d1394081cf50/src/llama-model.cpp#L1729-L1735)

| 範囲 | 計測点 |
| --- | --- |
| モデルとバッファ群 | load_tensors 開始、mmap 初期化前後、モデルバッファ報告後、各 load_all_data 開始／終了、後処理開始／終了 |
| upload 準備 | 群開始～async_ready／async_unavailable。staging 確保、イベント作成、upload backend 初期化を計数・計時 |
| 非同期ループ | seek、再使用前 event wait、ファイル読み取り、tensor_set_async、event_record。イベント未使用の最初の待ちを first_wait に分離 |
| 他経路 | host 宛て読み込み、同期 fallback の staging と tensor set、mmap／lazy の bind・lock・set。CPU 側の呼び出し単位 |
| 群末尾 | 最終 drain、イベント・staging・backend の解放、検証結果待ち、unmap、進捗コールバック。既存の例外・キャンセル時には群の部分集計を出力 |

[モデル境界](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d32cdfaf1c86739b6479260e6324d1394081cf50/src/llama-model.cpp#L2240-L2292) · [load_all_data](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d32cdfaf1c86739b6479260e6324d1394081cf50/src/llama-model-loader.cpp#L1667)

### 出力仕様

- stderr に `llama_load_diag ` と1行 JSON（`schema: 1`）。`group_begin`、`group_phase`、`progress`、`group_end` を群番号とバッファ型で照合する。通常の進捗ドットと混ざらないよう、診断行の前に改行を入れる。stdout の既存 JSON とラッパーのファイル形式は維持した。
- `load_elapsed_us` はモデルのネイティブ計時起点からの単調時間。進捗は操作の完了時に確認し、群の前回の進捗から約5秒以上経過した場合に1行出す。長い単一呼び出し中の heartbeat はない。`wall_us`、`classified_us`（重複しない計時の和）、`unclassified_us`、`completed_tensors`、`read_requested_bytes`、`transfer_logical_bytes` を記録する。差分で区間の発行量と待ちの累積を求められる。
- 操作ごとに `calls`、`bytes`、`sum_us`、`max_us`、`interval_max_us` を出力する。進捗出力後は区間最大のみリセット。カウンターは64 bit飽和加算。読み取りバイトは既存ラッパーに渡した**要求**量で、SSD の実バイト数や OS の返却量ではない。転送論理バイトは tensor set API に渡した量。例外で戻った呼び出しも試行として数える。
- 群終了時の計時ヒストグラムの境界（µs）は100、1,000、5,000、10,000、20,000、50,000、100,000、500,000、1,000,000。境界値は上の bin。100 ms以上を対象に、固定領域へ最長8件を保持する。操作、モデル起点の開始時刻、所要時間、群内のテンソル通番、0始まりの shard、テンソル開始と操作のファイルオフセット、テンソル内チャンク位置、要求バイト、staging slot を記録する。再使用待ちと最終 drain の詳細は、待たれた前回の upload の位置に対応する。
- CPU 側 API の壁時計を測る。GPU 実時間と重ねて加算しない。`unclassified_us` にはテンソル走査、フレームワーク、診断自体の処理、分類していない後片付け等が含まれる。OFF では診断グループを構築せず、各計時ラッパーは直接元の操作を呼ぶ。ON でも通常のチャンク処理は固定領域で加算し、整形・出力は境界と間引いた進捗に限定した。
- リソース CSV との照合では、既存フェーズログの容量報告受信 UTC を近傍の `buffers_ready` へ対応させ、モデル単調時間を相対配置する。`load_tensors_end` と Context 報告の先後も確認する。絶対 UTC の診断アンカーは追加しておらず、差には stderr の遅延と通常監視のサンプル幅が残る。 [集計と出力](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d32cdfaf1c86739b6479260e6324d1394081cf50/src/llama-model-load-diag.h#L133-L281)

## CPU 検証と静的確認

ThinkPad 上で C++17 の単体テストを `-Wall -Wextra -Werror -pedantic -O2` でコンパイルした。カウント、バイト、累積時間・最大、全ヒストグラム境界、64 bit 飽和、最長8件、5秒進捗と区間最大のリセット、例外時の部分集計、キャンセルを検証した。ON の stderr は Python 標準 JSON で解析し、schema、エスケープ、数値、位置と順序を確認した。未指定と `0` は stdout／stderr が空で、null-group 呼び出しに時計取得がないことをテストした。UBSan で同テストを通過し、両変更翻訳単位の C++ 構文検査と `git diff --check` を通過した。 [CPU テスト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/d32cdfaf1c86739b6479260e6324d1394081cf50/tests/test-model-load-diag.cpp)

再実行はリポジトリルートから `c++ -std=c++17 -Wall -Wextra -Werror -pedantic -O2 tests/test-model-load-diag.cpp -o /tmp/test-model-load-diag`。テストをフラグ未指定、`0`、`1` の各プロセスで実行する。本番ロード経路の診断 OFF／ON の性能と実データログは、次のレビュー済み計測で確認する。

## Vulkan Release ビルド結果

EVO-X2 の新規 worktree の `build-ld` で検証した。外側の `Invoke-CodexBuild.ps1` は専用 clone 固定のため、ランブックに記載の現行製品版 `Build-Vulkan.ps1` の `PreflightOnly`、`ConfigureOnly`、`BuildOnly` を使用した。隔離 worktree のパスから同一 PowerShell 5.1 内で VS2022 x64 を初期化し、製品版 `Initialize-Evox2CodexDependencies` で依存入力・既存キャッシュを取得なしで照合した。既存 `build-s2v` は比較用の読み取りのみ。 [ビルドの運用](RUNBOOK.md)

| 項目 | 結果 |
| --- | --- |
| 構成 | Ninja Multi-Config、Release、並列4。VS2022 x64、MSVC 14.44.35207、VS2026 Build Tools 配下の LLVM Clang 22.1.3 |
| ツール | CMake 3.31.6-msvc6、Ninja 1.12.1、Vulkan SDK 1.4.357.0 |
| 依存 | BoringSSL 0.20261105.0、`3dc4b63808921e914a3fb1fa61869abc3938781b`。LLVM OpenMP 22.1.8。共有依存の既存検証済みキャッシュを再利用 |
| CMake キャッシュ | Vulkan／Backend DL／OpenMP／OpenMP fetch／RPC／BoringSSL ON。Native／CPU 全バリアント／UI／prebuilt UI OFF。FetchContent 完全切断 ON。Sapphire Rapids ターゲットなし |
| 所要時間 | configure 7.028秒。Release build＋CLI スモーク 141.566秒。SSH 終了コード0 |
| BuildIdentity | **Verified**。ソースはクリーンな `d32cdfaf1c86739b6479260e6324d1394081cf50`、CLI は b12690（埋め込み `d32cdfaf1`） |
| スモーク | `llama-cli.exe --version`、`--list-devices` がともに終了0。`Vulkan0: AMD Radeon(TM) 8060S Graphics` を確認 |
| 成果物 | `C:\llama-build\automation\w43diag\build-ld\bin\Release` |
| ログ | `C:\llama-build\_logs\codex\w43diag-d32cdfaf` の `build-release.ps1`、`verified-preflight.*.log`、`release.*.log`、`build-monitor.txt` |

マニフェストは成果物ディレクトリの `evox2-build.json`。SHA-256 は `7fcdef68ba725596a088b1f92811da9414a958b08b67349626c3d82e67ccf14c`。以下のバイナリをマニフェストと照合した。

| 成果物 | SHA-256 |
| --- | --- |
| `llama-cli.exe` | `ebb8cc5eee5d6d64d7fe8adbf9037593333de48881b96c747a5a237004273192` |
| `llama-bench.exe` | `aad7b53f5e67fb83e493611bae9818096efa8b3159748a9ef7c482aa78e1187d` |
| `llama.dll` | `edef9e61b0e86553b6847c614b4f7170f3877ebd57709fe29b2a734b24591f67` |
| `ggml-vulkan.dll` | `48d80b947129a29c3e5d3438dde2e81dea2e0cb7c90b89f09bd709189523c12e` |

### b12676 Stage 2 との差

CMake キャッシュで上記の主要フラグを照合した。Stage 2 の古いマニフェストの CPU 全バリアント表示は True だが、実キャッシュは OFF。今回のマニフェストは False で、実キャッシュと一致。コンパイラ・SDK・依存版と Release ターゲットは同じ。ソースの診断差分、埋め込みコミット・ビルド番号、worktree／出力パス、生成バイナリのハッシュは異なる。Vulkan バックエンドにはソース差分がないが DLL のハッシュも異なる。再現ビルドでのバイト一致や性能同等性は未検証。

worktree の `.git` 参照形式により CMake は `Git index not found in git repository.` と警告した。明示した configure と BuildOnly のメタデータ更新後に CLI の埋め込み SHA を照合して Verified を確認した。初回 preflight 用スクリプトの Ninja 一行出力を文字列一文字として扱う問題は configure 前に検出し、ログを保全して修正した。正しい版で Ninja 1.12.1 と各固定値を照合してから一度だけ configure／build した。

`test-backend-ops.exe` は既定ターゲットとしてビルドした。実機で実行した製品 EXE の検証は CLI のバージョンとデバイス列挙まで。モデルロード、推論、性能計測、演算テストは行っていない。診断 OFF のロード時オーバーヘッド、ON の実リソース時系列、ROCm の実ビルドは未確認。

## 次回の診断計測候補

1. 最初のモデルロードを診断 **ON** にする。前回の終了時刻・確認元、同一モデルの最終ロード、直前のモデルとバックエンド、実行順、アイドル期間、System Cache、Windows 起動・稼働時間を分かる範囲で事前記録する。時間差が推定できない場合は欠損とする。Task Manager は閉じ、キャッシュの強制クリア、再起動、サービス変更は予定に含めない。
2. 作業4-2と同じ Vulkan0、IQ3 PLE16、PP8192／TG256、warmup ON、UMA 96 GiB、Performance、通常2秒、ADLX 2,000 ms、詳細 RAM 250 ms。Perf Logger、RGP と実験フラグは解除。ThinkPad 側から1件ずつ起動し、既存の終了・回復・イベントゲートを通す。異常捕捉時は継続の要否を再評価する。
3. ON の異常 run では、約48秒以降、RAM ピーク近傍、Context 前の末尾を `buffers_ready`、進捗差分、`drain`、ホスト群、後処理の境界と照合する。ReadFile の要求バイト／経過時間と、再使用待ちの回数・累積・最大、最終 drain、短い待ちの分布を対照と比較する。stderr マーカーには受信幅を残し、帯域低下だけで SSD 側の原因と判断しない。
4. 同じ診断バイナリで正常な ON／OFF の対照を後続で取得する。最初の ON 以降は順序を考慮して交互の比較を候補とし、異常 run は診断負荷の比較から外して時系列解析に用いる。初回 ON が正常でも設計の価値や異常の消失は判断できない。反復の上限は実行前にレビューする。

ON の計時が読み込み・転送の重なりを変える可能性がある。待ちが復帰しない場合は最後の進捗・群境界までが残る。GPU 側の実行時間、ファイル別の実 I/O、待ちが継続した箇所の完全な帰属は未確認。今回は実ビルドと非推論検証で終了した。
