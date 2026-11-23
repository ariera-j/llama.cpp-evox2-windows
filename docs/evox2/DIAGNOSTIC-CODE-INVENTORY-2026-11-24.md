# EVO-X2 診断コード保全目録

[ブランチ棚卸し台帳](BRANCH-ARCHIVE-INVENTORY-2026-11-23.md) の「保全確認待ち」から、診断実装の参照元5件を固定した。各 SHA は確認時点の GitHub ブランチ先端。実装と設定名は、そのコミットのソースで照合した。5件のブランチはいずれも GitHub に残っている。[削除済み33件の保存先](BRANCH-ARCHIVE-TAGS-MANIFEST-2026-11-23.json) は別途マニフェストに記録している。

| 診断項目 | 元ブランチと固定 SHA | 実装の所在と設定 |
|---|---|---|
| llama-bench の実入力 PP | `feature/r6-llama-bench-real-prompt-20261103` / `6a092fd2e60789d6ff7001cbe8e342fccff323ac` | [llama-bench.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/6a092fd2e60789d6ff7001cbe8e342fccff323ac/tools/llama-bench/llama-bench.cpp#L468)。UTF-8 テキストを PP に使う `-f/--prompt-file` と、トークンの取り出し方を指定する `--prompt-slice head-tail\|head`。 |
| r6 Vulkan FA の RGP マーカーとマスク取得 | `investigation/r6-pp-fa-mask-rgp-20261105` / `5288bf9541e56f60943b66177f671564b466cd39` | [設定とマスク取得](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5288bf9541e56f60943b66177f671564b466cd39/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L18)、[FA の dispatch ラッパー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/5288bf9541e56f60943b66177f671564b466cd39/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L8909)。`GGML_VK_FA_RGP_MARKERS` と `VK_EXT_debug_utils` による `EVOX2_FA_` ラベル。マスク取得は `GGML_VK_FA_MASK_DIAG` と `_KV`、`_QUERY`、`_FILE`、`_RAW` の各設定。 |
| r6 ROCm FA ホストトレースと GPU アンカー | `investigation/r6-rocm-rgp-moe-anchor-20261107` / `c1ebedabedbc5893eeb0c71241debd38f3d16904` | [fattn.cu のホストトレース](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/c1ebedabedbc5893eeb0c71241debd38f3d16904/ggml/src/ggml-cuda/fattn.cu#L773) は `GGML_HIP_FA_TRACE`、`GGML_HIP_FA_TRACE_KV`、`GGML_HIP_FA_TRACE_LAYER`。 [GPU アンカー](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/c1ebedabedbc5893eeb0c71241debd38f3d16904/ggml/src/ggml-cuda/fattn.cu#L858) は `GGML_HIP_RGP_ANCHOR` と `GGML_HIP_RGP_ANCHOR_KV` で制御し、`evox2_hip_anchor_fa_layer19` と `evox2_hip_anchor_fa_layer23` を使う。 |
| r6 ROCm FA 帯別調査と IQ3/IQ4 MMQ トレース | `investigation/r6-rocm-pp64k-iq3-iq4-mmq-trace-20261110` / `7a293e320890383d7d16903aa89fbd47bcae8904` | [evox2-hip-fa-survey.cuh](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/7a293e320890383d7d16903aa89fbd47bcae8904/ggml/src/ggml-cuda/evox2-hip-fa-survey.cuh#L41) と [fattn.cu の組み込み箇所](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/7a293e320890383d7d16903aa89fbd47bcae8904/ggml/src/ggml-cuda/fattn.cu#L17)。`GGML_HIP_RGP_FA_SURVEY`、`_FINE_BAND`、`_FINE_LAYER`。 [mmq.cu](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/7a293e320890383d7d16903aa89fbd47bcae8904/ggml/src/ggml-cuda/mmq.cu#L185) の `GGML_HIP_MMQ_TRACE`、`_LAYER`、`_N`。 |
| r5 Vulkan FA の移植元 | `investigation/r5-vulkan-off-fa-dispatch-20261010` / `65ed1285c3d6429b4d63c75fba7a87d7f627ac50` | [ggml-vulkan.cpp](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/65ed1285c3d6429b4d63c75fba7a87d7f627ac50/ggml/src/ggml-vulkan/ggml-vulkan.cpp#L8569) の `EVOX2_FA_` ラベルと `GGML_VK_FA_RGP_MARKERS`。r6 へ抽出したマーカーとマスク診断の由来を調べる起点。移植を検討する際は機能ごとの差分を確認する。 |

関連記録は [実入力 Gate 1](R6-LLAMA-BENCH-REAL-PROMPT-GATE1-IMPLEMENTATION-2026-11-03.md)、[Vulkan RGP/Mask の移植調査](R6-PP-RGP-MASK-SOURCE-INVENTORY-2026-11-05.md)、[ROCm FA 調査と移植記録](R6-HIP-FA-RGP-SURVEY-PORTING-2026-11-11.md) を参照。

## ソースの読み出し

コミットを取得済みの clone では、`git show <固定SHA>:<ファイルパス>` で実装を読める。例えば `git show 6a092fd2e60789d6ff7001cbe8e342fccff323ac:tools/llama-bench/llama-bench.cpp` で実入力の実装を確認できる。作業ブランチとして復元する場合は、専用 clone で `git branch <新しいブランチ名> <固定SHA>` を使う。

照合時の `main` は `423f70d3039a626afc77d8ac9976badab3a71ab8`。表に挙げた診断設定と実入力オプションは、対応する `main` のソースに見つからなかった。今回はソースの静的確認を行った。
