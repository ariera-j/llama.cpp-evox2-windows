# B12651 ROCmFP4 FAST PLE16 HIP-1 独立レビュー・HIP-2引き継ぎ（2026-11-28）

状態: **CONDITIONAL GO**。Astra Medium による別セッションの静的レビュー報告（運用者提供 Markdown）を ChatGPT が整理した記録。原設計と検証計画は当時の状態を保持する。本書の追加条件を HIP-2/3 の実装依頼に反映する。実装・ビルド・GPU実行・性能計測は未実施。

- 製品基準: [a650d641](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/a650d641ee99198543697e1e3913c593059721f7)
- 原設計・検証計画: [24cb096d](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/24cb096dfe5a39dd7d1f14d3bb659c9ee28fbff1) の [設計書](B12651-ROCMFP4-HIP1-DESIGN-20261128.md)・[検証計画](B12651-ROCMFP4-HIP-VALIDATION-PLAN-20261128.md)。
- 下記ソース行番号は製品基準SHA。レビューはローカル固定資料を再利用し、ネットワーク・SSH・製品変更なしとの報告。ChatGPTは argsort top-k、MUL_MAT の早期分岐、GET_ROWS ループ、既存 ID grouping/BLAS の関連部分を固定SHAで静的に照合。全経路・donor・実行結果を独立に検証したわけではない。

## 1. High: 非連続 top-k ID view

`src/models/qwen4exp.cpp:1241` → `src/llama-graph.cpp:2440–2445,2666,2677–2679`、`ggml/src/ggml.c:5442–5455` の argsort top-k は親の nb[1] を保持した view。slot置換なしの `build_lora_mm_id`（llama-graph.cpp:1890–1903）ではそのまま渡される。E=512、S<E、T>1 なら token stride=2048 bytes、密な I32 [S,T] の 4S bytes と異なる。loader の代表演算（src/llama-model-loader.cpp:1070–1077,1168–1173）は密なIDのため通過し得る。元の9ケースに合格しても実PPで拒否される可能性。

**HIP-2開始前必須:** I32 slot stride=4、token stride が4の倍数かつ4S以上、最終要素までの割当範囲を検証して受けるか、明示的連続化と配置・容量を設計する。既存 grouping（ggml/src/ggml-cuda/ggml-cuda.cu:2720–2739）は ggml_nbytes(ids) を D2H し stride で読む。コピー span=(T−1)×nb[1]+4S（T>0）。ケース8を実ルータ相当の top-k view とし、余白に無効ID、重複slot・後続token・逆scatterを検証。

## 2. High: FAST F32固定の迂回

`ggml-cuda.cu:2535–2555` は量子化vector/tile選択前に FWHT の判定と compute buffer view の padding 等による汎用BLAS早期returnを持つ。後者は F16/BF16 自動選択（2125–2133,2151–2164）に達し得る。F16なら設計外の精度、未登録BF16ならassert（1953–1966）の可能性。単なるrow padding fixtureではこの buffer usage を再現できない。

**HIP-2開始前必須:** FASTの有効な条件では早期汎用BLASを迂回するF32経路を明示する。FWHT、融合、少token経路も含め全先行分岐との整合を確認し、既存精度・配置制限を維持。compute view を許すなら条件を再現して SGEMM 到達を確認、対象外なら支持判定で拒否。将来HIP-4の比較時に通常・ID双方からF32を選択できること。

## 3. High: expert内部一時tensorのメタデータと実アドレス

`ggml-cuda.cu:2755–2799` の grouping は重み data を expert offset だけ進めるが対応する view_offs を設定しない。dst_slice の src は空、sorted入出力の data は pool を指す一方で buffer は元tensorを参照する。SGEMM は明示引数のdataを使う（1939–1958,1975–1977,2046–2052）。graph tensor の root+view_offs、dst->src、元buffer容量による検証をそのまま内部呼出しに適用すると誤拒否・別expert参照等のリスク。

**HIP-2開始前必須:** 外側の MUL_MAT_ID で root、view起点、全expert spanをchecked算術で検証し、内部では検証済みポインタ・明示shape/stride・実pool割当長を使うか、一時記述子の整合を確立する。ケース9に非ゼロ親view起点、末尾expert、expert間paddingを加え、expertごとに異なる期待値を検査。内部呼出しからF32に確実に到達し、graph capture除外と既存D2H/H2D同期の条件を揃える（2693–2695,2720–2722,2741–2744,3325–3334）。

## 4. Medium: FP3 GET_ROWS 重複書込み

`ggml/src/ggml-cuda/getrows.cuh:3` と `getrows.cu:15–38,160–168` の generic kernel は256 threads、grid.y=ceil(K/512)（上限あり）、開始列は2倍だが反復増分は grid.y×256。K=288 では thread 128の初回とthread 0の次回が列256/257に書く。値が同じでも書込み競合。元設計の32整列のみのpredicateでは拒否されず、幅32/160のケースでは再現しない。

HIP-3初版は幅32/160に限定する方針を推奨。幅288の拒否も検証する。より広い対応は一意な書き手の証明と既存型の回帰を伴う独立変更とする。ROCM-002 IQ4_NLは別テンプレート（399–406）を維持。

## 5. Medium: 誤差判定と符号付きゼロ

一般 F32 GEMM は有限性と全要素の絶対誤差 |GPU−ref| ≤ A（A=2Ku/(1−Ku)×Sabs+1e−7、u=2^-24、Sabs=Σ|w×x|）を暫定合否条件とし、実BLAS math modeを確認後、実行前に固定。相対誤差と条件数は診断値（対応する相対上限はA/|ref|、条件数の二重乗算をしない）。one-hotの厳密一致、decoder/gather のbitwise比較は独立。scale=0・無効scaleと負の非ゼロcodeの積でCPUが負のゼロを生成し得る（rocmfp4.c:119–120,579–589、rocmfpx.c:145–146,1053–1073）。符号ビットもfixtureに含め、安易な+0早期returnを避ける。HIP-4の量子化dotには別基準。

## 6. 実装・検証への追加条件

- High 1–3 をHIP-2の実装開始条件とする。連続ケースから開始しても、実ルータ相当のID strideと内部expert sliceのケースを通すまで実モデルを許可しない。支持判定、実device、grouping、F32 converter/SGEMMへの到達を照合。少token・融合・captureも確認。
- ケース8/9を上記に従って改訂。compute viewの許否、FP3幅288負例、符号付きゼロと全scale/codeのGPU側検査範囲も確定。限定テスト前にケースID・件数・許可対象を再レビューする。旧9件を無条件に実行しない。
- IDコピーspanおよびHIP 7以降の該当条件でhandleごとの既定32 MiB workspace（ggml-cuda.cu:1924–1925,1944–1958、common.cuh:1450–1466）を容量見積りに追加。実pool高水位は未確認。
- ROCM-002の回帰基準は維持。Windowsコンパイル、実SGEMM内部精度、最適化後graph、配置、実機数値・資源・回帰は今後の個別承認ゲート。共有コード変更・広範GPUテスト・自動再試行は禁止条件に従う。
- 本書は設計変更候補の記録であり実装採用・テスト承認ではない。運用者が次回HIP-2実装範囲を承認する。

エージェント実績は [AI-AGENT-EVALUATION-20261127.md](AI-AGENT-EVALUATION-20261127.md) の追記参照。
