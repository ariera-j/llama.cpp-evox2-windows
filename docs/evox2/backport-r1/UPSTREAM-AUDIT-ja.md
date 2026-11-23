# upstream差分調査と採用範囲

調査日: 2026-09-15 UTC。再現性のため、以下のコミットで範囲を固定しました。

| 対象 | コミット |
|---|---|
| ユーザーの計測ログにある専用fork | `5e085d123eead2e89b5c19f824fccb05727da6a2` |
| upstreamのb10641相当 | `539f24529bdf99e0baefd54fefff1660034bfe7b` |
| 専用forkとupstreamの共通祖先 | `0190529ec450659b541ff608449401e68c27d098` |
| 調査時のupstream最新ソース | `d1d3c3396aa13a5f239109a822666c4870490ad5` |

[対象fork](https://github.com/LaurentZuijdwijk/llama.cpp/tree/5e085d123eead2e89b5c19f824fccb05727da6a2)、[upstreamの調査終点](https://github.com/ggml-org/llama.cpp/commit/d1d3c3396aa13a5f239109a822666c4870490ad5)。

調査時点のnightlyリリースAPIの先頭はb10985、ソース終点はb10987相当でした。「最新版」は動くため、本パッチは上記ソースまでを調査対象としています。b10641タグは取得できず、b10642の親と後続ビルドとのコミット数から相当コミットを特定しています。

## どちらを土台にするか

専用forkのb10809は、upstream b10706相当の共通祖先に独自の103コミットを加えた番号です。upstreamのb10809と同じ内容ではありません。b10641以降の65コミットは共通祖先までに含まれています。今回の調査範囲は合計346コミット、そのうち共通祖先以降が281コミットです。

| 方法 | 今回の実際の確認 | 判断 |
|---|---|---|
| 動いているforkへ関連更新を選択適用 | 今回は10ファイル、258行追加・124行削除のパッチに限定 | 現時点の計測用にはこれが容易 |
| forkへupstream全体を統合 | 3-way mergeで12ファイルが競合 | 解決・広範囲の再検証が必要 |
| 最新upstreamへ独自変更を全て移植 | 同じ内容を3-way mergeすると、逆方向でも同じ12ファイルが競合 | 土台を逆にするだけでは競合は減らない |

独自差分は共通祖先から116ファイル、14,273行追加・225行削除でした。ドキュメントや補助スクリプトも含む数値ですが、ROCmFPxの型・量子化・Vulkan実装、PLE16、QSAキャッシュ、MTPが複数箇所にまたがっています。

競合ファイル: `conversion/base.py`、`convert_hf_to_gguf.py`、`ggml/src/ggml-vulkan/ggml-vulkan.cpp`、`ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp`、`src/CMakeLists.txt`、`src/llama-kv-cache.cpp`、`src/llama-memory-hybrid-idx.cpp`、`src/llama-memory-hybrid-idx.h`、`src/models/dflash.cpp`、`src/models/qwen4exp.cpp`、`tests/test-backend-ops.cpp`、`tools/ui/CMakeLists.txt`。

これはmerge-treeによる競合調査であり、最新版全体の統合を完成させたという意味ではありません。競合表示のないファイルにも、独自量子化形式とupstreamのシェーダー構造変更を組み合わせる際の意味的な調整が残り得ます。

長期保守でupstreamの新機能を継続して使うなら、最新upstreamを土台に独自機能を小さなパッチ群へ整理する価値はあります。ただし、今回のEvo-X2で早く比較計測する目的では、選択適用の方が作業と不確実性を抑えられます。

## 今回取り込んだ更新

13件のPRに由来する変更です。一部採用・調整があるため、13コミットをそのままcherry-pickしたものではありません。完全SHAと採用範囲はmanifest.jsonにあります。

| upstream PR | 取り込み内容 | 対象への関係 |
|---|---|---|
| [#28422](https://github.com/ggml-org/llama.cpp/pull/28422) | MoEの融合処理で外部入力の寿命を延ばす | PPで入力・出力のメモリー重複により融合が解除される問題を軽減 |
| [#28023](https://github.com/ggml-org/llama.cpp/pull/28023) | QSA indexerのヘッド別スコアをスライス加算 | 転置・連続化コピーと行方向集計を減らす |
| [#28896](https://github.com/ggml-org/llama.cpp/pull/28896) | HC/PLEでRMSNormと乗算を隣接させる | 既存のVulkan融合を利用可能にする。forkのMTP層にも同じ形状を適用し、ロード用フラグを保持 |
| [#28330](https://github.com/ggml-org/llama.cpp/pull/28330) | 未使用indexer Vキャッシュを確保しない | 長いコンテキストでメモリーを節約。forkのpooled-key cacheを保持 |
| [#27941](https://github.com/ggml-org/llama.cpp/pull/27941)の一部 | indexerの生KキャッシュにRoPEをかけない設定 | #28330適用先の関連設定。seq_cp、ブロック位置管理など同PRの残りは含まない |
| [#28190](https://github.com/ggml-org/llama.cpp/pull/28190) | 単一ストリームでFAの量子化KV復元経路を選ぶ条件を修正 | 同時会話数1、q8_0 KVで関係する候補 |
| [#28457](https://github.com/ggml-org/llama.cpp/pull/28457) | 小さいMの行列積、split-K、1行出力時の入力交換 | 小さな行列積の無駄を減らす候補。元PRの別GPUの倍率をEvo-X2には当てはめない |
| [#28387](https://github.com/ggml-org/llama.cpp/pull/28387) | 入力数の上限だけによるグラフ分割を除去 | 大きな計算グラフやCPU/GPU境界で余分な分割を減らす候補 |
| [#28618](https://github.com/ggml-org/llama.cpp/pull/28618) | GPUがidleかつhost-coherentな小さな転送をCPUコピー | UMA上で同期のオーバーヘッドを減らす候補。128KiB以下などの条件付き |
| [#28253](https://github.com/ggml-org/llama.cpp/pull/28253)のVulkan部分 | GET_ROWSの量子化型に応じたoffset処理 | PLEなどの量子化テンソル・viewに関係する正しさの修正。既存テストの拡張も採用 |
| [#28705](https://github.com/ggml-org/llama.cpp/pull/28705) | argsortの範囲外読み込みと共有メモリー競合を修正 | 選択処理の正しさ。以前のWindows停止原因と特定したものではない |
| [#28592](https://github.com/ggml-org/llama.cpp/pull/28592) | FILLを2次元workgroupに分ける | 大きなテンソルでデバイスのdispatch上限を超える問題への対応 |
| [#28068](https://github.com/ggml-org/llama.cpp/pull/28068)のQwen4exp部分 | GDNのL2正規化を正しいepsilonの式へ修正 | 性能ではなく計算の正しさ。出力の完全一致を目標とする変更ではない |

#28422はforkに存在しない追加fusion状態を持ち込まずに適応しました。#28457のタイル選択はforkの既存構造に合わせています。#28896はtrunk_flagsとMTPのflagsを維持しています。ROCmFPx固有のエンコーダー、型番号、シェーダー定義は変更していません。

## 既に入っていたもの・今回は保留したもの

| 更新 | 判断 |
|---|---|
| [#27812](https://github.com/ggml-org/llama.cpp/pull/27812)、[#27880](https://github.com/ggml-org/llama.cpp/pull/27880)、[#27301](https://github.com/ggml-org/llama.cpp/pull/27301)、[#27925](https://github.com/ggml-org/llama.cpp/pull/27925)など | 共通祖先に含まれる。再適用不要 |
| [#27449](https://github.com/ggml-org/llama.cpp/pull/27449) IQ3_Sのバッチmatvec修正 | パッチの逆適用チェックが成功し、同等変更が既に存在すると確認 |
| [#28032](https://github.com/ggml-org/llama.cpp/pull/28032) QSA融合付きradix TOP_K | forkには別のlarge-k radix実装があるが、upstreamの融合版と同一ではない。両実装の置換とGPUでの比較を必要とするため今回は保留 |
| [#28105](https://github.com/ggml-org/llama.cpp/pull/28105) sparse Flash Attention | 有望。ただしKV上限のヒントAPI・グラフ側設定などの依存対応が必要。単にVulkan部分を足してもこのforkでは有効にならないため今回のr1には含めない |
| [#27909](https://github.com/ggml-org/llama.cpp/pull/27909) Strix Haloのbatched matvec調整 | 関連候補。実機の整数dot経路の確認とMTPを含む比較対象として保留 |
| [#28024](https://github.com/ggml-org/llama.cpp/pull/28024)、[#27220](https://github.com/ggml-org/llama.cpp/pull/27220)の追加融合 | 今回は既存のRMSNorm+MUL融合を使うモデル側変更に絞った。追加シェーダーと状態管理の拡張は保留 |
| [#25773](https://github.com/ggml-org/llama.cpp/pull/25773) VulkanのA型specialization constants化 | 広い構造変更。fork固有のROCmFPxプリプロセッサー定義と併せて再設計・検証が必要 |
| [#28123](https://github.com/ggml-org/llama.cpp/pull/28123) recurrent rollback | fork独自MTPの状態管理との組合せを実機で検証する必要があるため今回は変更しない |
| [#27483](https://github.com/ggml-org/llama.cpp/pull/27483)、[#28326](https://github.com/ggml-org/llama.cpp/pull/28326)などのロード時メモリー対策 | joined PLEの巨大テーブルを自動でGPUへ置ける変更とは別。今回の96GB対策はPLE16変換と未使用Vキャッシュ削除を優先 |
| [#27466](https://github.com/ggml-org/llama.cpp/pull/27466)、[#28552](https://github.com/ggml-org/llama.cpp/pull/28552) | ROCm/HIP側のPP改善候補。Vulkan用パッチの対象外 |
| [#28476](https://github.com/ggml-org/llama.cpp/pull/28476) IQ量子化MoE改善 | SYCL用。Unslothというモデル名が共通でもVulkanへそのまま適用する対象ではない |

## 以前のPP差をどこまで説明できるか

b10641以降の更新が効いたという仮説は妥当です。ただし、b10641以降でもforkの共通祖先に既に入った修正は、両者の差の説明には使えません。また、ROCm側の改善とVulkan側の改善は分けて評価する必要があります。

ユーザーのupstream b10919の計測時点には、今回の候補のうちMoE融合・QSA集計・量子化KV経路などは含まれています。一方、9月14日の#28896や9月15日の#28105はb10919より後なので、以前の計測差の原因にはなりません。

このr1は複数更新をまとめた比較用です。改善が見えた場合に個々の寄与率を知るには、同じ条件で更新群を分けた計測が必要です。現段階で何%速くなるか、Halogenにどこまで近づくかは判断できません。
