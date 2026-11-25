# IQ2_S Vulkan MatVec 最適化実験（EVO-X2）

[llama.cpp PR #30904](https://github.com/ggml-org/llama.cpp/pull/30904) の `c1d245bc3d1c416f74f1e108b0f60fa2a699dbf1` を参考にした IQ2_S 向けの独自実装。対象は IQ3 PLE16 の routed expert Gate/Up。Baseline は前回の調査と同じ製品コードで、作業基準は `f4f1aa3e85124fed75a891ec63a1504536049eff`。実験ソースは `a38ba149d11d6a7067e6c323523f95c7889b167b`。

**A2 は Gate/Up の並行計測区間を 1.89% 短縮した。** A1 単独は区間が 0.01% 短縮、併用版は 1.89% 短縮。A2 と併用版で、対象 ID パイプラインの VGPR は 82 から 73 へ減った。区間は各構成1回の診断値。

Logger OFF の TG256 中央値は Base 29.970 tok/s、A1 29.975、A2 30.078、併用版 30.081。A2 と併用版は中央値で +0.36% と +0.37% だったが、3ラウンドのうち1ラウンドは両方とも Base を下回った。Base 自身も 29.220〜29.991 tok/s の幅があり、この run 数では実効 TG の改善は確定できない。A1 の初回 22.017 tok/s は集計に含め、計測境界を下記で再確認した。全16 run が終了コード0、開始・終了とも P-MODE Performance。

## 採否と今後の候補（2026-11-25）

- **PR #30904 は直接移植を見送る。** 常用2モデルに IQ3_XXS テンソルは0件。 [移植前調査](../pr30904-preport-20261125/README.md)
- **A1 は採用見送り。** 単独での高速化を確認できなかった。対象の1列パイプラインで VGPR は82のまま、Gate/Up の並行計測区間の差は −0.01%、TG256 中央値の差は +0.02%。
- **A2 は採用保留。** Gate/Up の並行計測区間は約1.89%短縮し、VGPR は82から73に減少した。TG256 中央値は約0.36%上がったが、同ラウンドの Base を下回った回もあり、実効 TG 改善は確定できない。将来 TPB や NUM_ROWS などを変更した際に VGPR 削減が有効になる可能性があるため、実験ソースを保存する。 [実験コミット](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/a38ba149d11d6a7067e6c323523f95c7889b167b)
- **A1+A2 に明確な追加効果はない。** Gate/Up の区間、VGPR、TG256 中央値はいずれも A2 単独とほぼ同じだった。
- **TPB=8 は未実施の独立候補。** 本実験は TPB=16、NUM_ROWS=4 を固定した。TPB の変更効果と A2 との組み合わせは未評価。

## 対象経路と実装

| 項目 | 実機とソースの確認結果 |
|---|---|
| IQ3 PLE16 | 47層の Gate/Up が IQ2_S。残る1層の Gate/Up は IQ3_S。入力側は K=2560、出力側は M=640 |
| TG の MUL_MAT_ID | `mul_mat_vec_id_iq2_s_f32`、NUM_COLS=1、NUM_ROWS=4、workgroup `64×1×1`、subgroup 64。512 expert 中10スロットを dispatch。Perf Logger の `n=10` はこのスロット数 |
| 通常の MUL_MAT | `mul_mat_vec_iq2_s_f32_f32` / `mul_mat_vec_iq2_s_f16_f32`。NUM_COLS はベクトル列数。両経路で同一 GLSL を使い、ID 版を `MUL_MAT_ID=1` で生成する |
| TPB とロード | TPB=16、各 lane が同じスケールの16ウェイトを持つ。格子インデックスと符号は既存の packed16 ロードを使用 |

- **Base** は前回の既存バイナリ `build-s2v`（b12676、`eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1`）。作業基準までの差分は Stage 2 文書とビルドラッパー関係のみ。
- **A1** は符号付き格子を列ループの前で復元する。入力ロード、入れ子の FMA 順、各8要素和にスケールを適用する順は Base と同じ。
- **A2** は同一 lane の2つの8要素格子を局所 FMA で加算する。半バイトのスケールは両方で同一であり、最後に1回だけ `fma(db, accum, temp)` を行う。局所値は出力行と量子化ブロックごとに初期化する。多列でのレジスタ使用量を抑えるため、A2 は NUM_COLS≤6 で有効化する。
- **A1+A2** は上記両方を有効化する。実験バイナリ `build-i2mv` の IQ2_S パイプライン特殊化定数で選択し、実装ごとに別プロセスで起動した。

製品コードの差分は IQ2_S のシェーダーと、その通常・ID 登録の2ファイル。workgroup、NUM_ROWS、TPB、他の量子化形式は比較条件として固定した。 [実験ソース](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/a38ba149d11d6a7067e6c323523f95c7889b167b) · [前回のモデル構成](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4fb3a4dbf40f69f268cb057530e05afd90af410d/docs/evox2/pr30904-preport-20261125/README.md)

## 数値検証

4構成で各6ケース、計 **24/24 PASS**。専用プログラムで Vulkan0 の GGML グラフを実行し、CPU の IQ2_S デクオンタイズと倍精度ドット積から求めた参照値と照合した。入力は固定シードで生成した有効な IQ2_S ブロックと F32 ベクトル。K=2560、通常 MatVec のトークン数1・3・8、ID の512 expert/10スロット、M=640・643、共有・スロット別入力、1・3トークン、一部および1トークン全体の ID=-1 をカバーした。スキップした出力は厳密にゼロを要求した。

| 構成 | ケース | 最大絶対誤差 | 最大相対 L2 |
|---|---:|---:|---:|
| Base | 6/6 | 1.70e-6 | 7.77e-8 |
| A1 | 6/6 | 1.70e-6 | 7.77e-8 |
| A2 | 6/6 | 1.79e-6 | 7.49e-8 |
| A1+A2 | 6/6 | 1.79e-6 | 7.49e-8 |

通常の F16 入力版の登録は確認した。数値実行には F32 入力を使った。A1 の誤差集計は Base と全ケースで一致した。受入条件は各点 `|Δ| <= 2e-5 + 1e-5 × |ref|`、相対 L2 ≤ `3e-6`。既存の自動テスト制限に従い、限定の独立比較を実施した。 [専用数値比較のソース](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/validate-iq2-s.cpp) · [全ケース CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/validation.csv) · [運用ルール](../automation/AGENT-RULES.md)

## ベンチマーク

Radeon 8060S、UMA96GB、P-MODE Performance、Vulkan0、IQ3 PLE16、49/49層を GPU offload、CPU MoE 0、F16 KV、FA ON、MTP OFF。threads 4、batch 2048、ubatch 1024。Logger OFF では `pp0/tg256` を1回ずつ、3ラウンドに分けて各構成3回。Concurrent Logger では、構成ごとに `pp0/tg32` を別プロセスで1回。いずれも depth 0、warmup OFF。 [再現と生ログの所在](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/commands.md) · [run 別 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/runs.csv)

| 構成 | Logger OFF TG256（3回、tok/s） | 中央値 | Base 比 | Gate/Up 区間 µs/token | 区間の Base 比 |
|---|---:|---:|---:|---:|---:|
| Base | 29.220 / 29.970 / 29.991 | 29.970 | +0.00% | 5049.81 | +0.00% |
| A1 | 22.017 / 29.975 / 29.985 | 29.975 | +0.02% | 5049.12 | -0.01% |
| A2 | 29.106 / 30.098 / 30.078 | 30.078 | +0.36% | 4954.41 | -1.89% |
| A1+A2 | 29.146 / 30.081 / 30.095 | 30.081 | +0.37% | 4954.12 | -1.89% |

Gate/Up の列は Concurrent Logger の別計測。負の区間差は計測区間の短縮を表す。TG256 は全区間のスループット。ラウンド内の Base 比と各 run の時刻は CSV に収録した。 [集計 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/summary.csv)

### 同じラウンドの Base に対する TG256 速度差

各セルは Logger OFF の tok/s から計算した `100 × (構成 / 同ラウンドの Base − 1)`。run-02 を含む。 [集計 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/summary.csv)

| 構成 | ラウンド1 | ラウンド2 | ラウンド3 |
|---|---:|---:|---:|
| Base | +0.000% | +0.000% | +0.000% |
| A1 | -24.649% | +0.020% | -0.020% |
| A2 | -0.387% | +0.428% | +0.288% |
| A1+A2 | -0.251% | +0.370% | +0.346% |

### GPU 区間と TG wall time

Concurrent Logger の対象は、同じ `MUL_MAT_ID_VEC iq2_s m=640 n=10 k=2560 n_expert=512` が2回並ぶグループ。1区間に Gate と Up の2ノードが入る。今回の定義では1,504区間/32トークン（47区間/トークン）、対象ノード3,008件。区間は GPU timestamp の差で、重なり得る仕事を含む。Gate と Up への個別配分や重複時間の逆算はしていない。Logger OFF の TG wall time は llama-bench の `samples_ns`、プロセス時間はモデルロードや初期化を含む別の値。 [対象グループの CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/gate-up.csv) · [実行ログ](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/logs)

## 低速2件の生ログ再解析

比較した6件の stderr は保存時の SHA-256 と一致した。出典は実機の `C:\llama-build\_logs\codex\iq2s-matvec-20261125-a38ba149` にある各 run の `.stderr.log`、`.stdout.json`、`.result.json`。stderr の `load time` と `total time` を秒に換算し、`samples_ns[0]` と `processSeconds` を別に示す。 [ログの所在](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/commands.md) · [stderr のハッシュ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/raw-log-sha256.csv)

| run | 構成 | プロセス全体 (s) | load time (s) | total time (s) | total − load (s) | TG256 計測 (s) |
|---|---|---:|---:|---:|---:|---:|
| run-02 | A1 | 63.60625 | 53.41183 | 61.92056 | 8.50873 | 11.627241 |
| run-05 | A1 | 59.53724 | 50.02125 | 58.49237 | 8.47112 | 8.540327 |
| run-11 | A1 | 59.46878 | 50.07547 | 58.54840 | 8.47293 | 8.537569 |
| run-03 | A1+A2 | 59.57710 | 50.22635 | 58.67021 | 8.44386 | 8.783293 |
| run-08 | A1+A2 | 154.16271 | 143.97960 | 152.42555 | 8.44595 | 8.510482 |
| run-10 | A1+A2 | 60.59433 | 50.57426 | 59.01717 | 8.44291 | 8.506438 |


### タイマーの境界

- PowerShell の `processSeconds` は起動直前から `Start-Process -Wait` の復帰直後まで。ロードと初期化、TG、終了処理を含む。 [実験時の起動スクリプト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/4829d29150fad1bd117b4be9aa23a311f80bc2e0/docs/evox2/iq2-s-vulkan-matvec-20261125/bench.ps1#L39)
- stderr の `load time` はモデルロードに由来する `t_start_us` を起点とする。`llama_context::synchronize()` はバックエンドを同期した後、最初の eval の完了時に `t_load_us = ggml_time_us() - t_start_us` へ更新する。 `total time` は同じ起点から、TG 結果出力後の `llama_perf_context_print()` まで。したがって `total time − load time` は最初の eval 完了から統計出力までの残余時間で、純粋なロード時間や定常 TG を直接測った値ではない。 [モデルロードの起点](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/src/llama.cpp#L337) · [同期時の更新](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/src/llama-context.cpp#L949) · [統計出力](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/src/llama-context.cpp#L5093)
- stdout の `samples_ns[0]` は `llama-bench` の TG タイマー。モデルロードとコンテキスト生成は開始前にあり、今回の `--no-warmup`、pp=0、depth=0 では初回 decode とその同期が TG256 に入る。 `samples_ns[0]` と stderr の残余時間は起点・終点が異なるため、その差を初回 eval の厳密な所要時間として扱わない。 [ウォームアップ分岐](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/tools/llama-bench/llama-bench.cpp#L2434) · [TG ループ](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/tools/llama-bench/llama-bench.cpp#L2201) · [計測範囲](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/a38ba149d11d6a7067e6c323523f95c7889b167b/tools/llama-bench/llama-bench.cpp#L2503)

### 観測と推定

- **run-02（A1 初回）**。TG256 は11.627秒で、再現2件の8.540秒・8.538秒より約3.09秒長かった。一方、`total − load` の8.509秒は再現2件の8.471秒・8.473秒と近い。初回 eval 完了までに相当する TG 冒頭付近の遅延が、ウォームアップなしの TG 計測に約3秒入った可能性が高い。各トークンの時刻は記録されておらず、遅延箇所や原因は特定できない。この記録に継続的な TG 性能低下を示す証拠はない。
- **run-08（併用版2回目）**。プロセスは154.163秒、`load time` は143.980秒。併用版3回目の run-10 よりそれぞれ93.568秒、93.405秒長い。TG256 は8.510秒で run-10 の8.506秒と同程度だった。約94秒の追加遅延の大部分は TG タイマー開始前に発生したと考えられる。 `load time` は初回 eval までを含むため、ファイル読込だけに遅延を帰属できない。

両現象で遅延が現れた計測区間は異なる。共通の原因があるかは不明。

### 引き継ぎ

運用者の報告では、過去の手動計測でもモデルロード付近の異常低速が複数回あり、今回の TG256 の12 run 中は実機操作をしていない。運用者はモデルロード時の一時的な RAM 使用量の増加を観測し、異常低速との関連を疑っている。今回の記録にリソースログはなく、直接の原因は特定できない。計測環境の改善後に、原因調査を別タスクとして実施する。

## SPIR-V とドライバーの比較

Radeon 8060S のパイプライン統計で、対象 ID は Base/A1 の VGPR 82 から A2/併用版の 73 へ変化。SGPR は全構成 106、scratch は 0。NUM_COLS=1 では列間の重複が生じないため、A1 で削減できる符号復元は少ない。オフラインの特殊化 SPIR-V でも、対象 ID の FNegate は全構成 80、FMA は Base/A1 が90、A2/併用版が85。通常の3列では A1 により FNegate が240から80、8列では640から80へ減った。通常の3列・8列で観測されたドライバーの VGPR は構成間で同じだった。これらは命令数と資源使用量の観測値で、GPU ISA の命令列一致までは確認していない。 [SPIR-V CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/spirv.csv) · [ドライバー統計 CSV](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/driver-pipelines.csv)

## ビルドと再現

実験版は Codex Vulkan ラッパーで Release ビルド。Clang 22.1.3、Vulkan SDK 1.4.357.0、LLVM OpenMP 22.1.8、`-CpuAllVariants OFF -Offline`。ビルド所要時間 147.12 秒。BuildIdentity は Base と実験版ともに Verified。Base の保存済みマニフェストには旧 `CpuAllVariants` 表示の既知差分があり、実際の CMake キャッシュは OFF。実験版のマニフェストはキャッシュと同じ OFF。 [Base マニフェスト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/logs/build-s2v-manifest.json) · [実験版マニフェスト](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/logs/build-i2mv-manifest.json) · [ビルドログ末尾](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/becad6b05ce5f7c602facd3bb5ed586a4b4f38b4/docs/evox2/iq2-s-vulkan-matvec-20261125/logs/build-tail.txt)
