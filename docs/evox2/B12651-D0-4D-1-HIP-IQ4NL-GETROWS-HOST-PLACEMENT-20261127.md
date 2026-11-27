# B12651 D0-4D-1 — 非256整列IQ4_NL GET_ROWSのホスト配置制限

2026-11-27 JST。非256整列IQ4_NL GET_ROWSで、CUDA系のホストバッファを重みの格納先とする場合だけ対応判定を拒否した。Originalの従来のCPU配置と、split PLE16のROCm0配置を両立させるための変更。今回はソースとテストの静的確認までを実施した。

- 実験ブランチ `experiment/hip-iq4nl-ple160` の開始HEADは `a1dbfde12003424261380723e185a6e4265e265f`。GitHub、実機 `C:\llama-build\automation\w55`、追跡先に一致。
- 製品基準 `9ae819d5be4fe9861d2aa8547983aed801c437ac`、現行バイナリのビルド元 `044be892e12bffdfd06cfb698bf55e54582ae63a`、文書・共通ツール main `891e2605fbc0798228ffad2a69dd618f6cdab216`。
- 修正ソースとテストの固定コミットは `86e343cd4bfa0110f49e430d59081725af976e01`。 [ソース差分](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/86e343cd4bfa0110f49e430d59081725af976e01)

## 配置回帰が成立する経路

1. `src/llama-arch.cpp` でjoinedの `LLM_TENSOR_PER_LAYER_TOKEN_EMBD` はINPUT、splitの `LLM_TENSOR_PLE_NGRAM_EMBD` はREPEATING。いずれも重みの用途は `GET_ROWS`。 `src/models/qwen4exp.cpp` はjoinedでは1つの幅160の重みを、splitではheadごとの幅160の重みを参照する。
2. INPUTの候補は `src/llama-model.cpp` の `make_cpu_buft_list` に由来し、既存のROCm0/CPU構成ではROCm_Hostが通常CPUより先に来る。GPU offload対象のREPEATINGにはROCm0のデバイスバッファが先行する。
3. `select_weight_buft` は最初に通過した候補を採用する。 `weight_buft_supported` はI32行インデックス512本の代表GET_ROWSを構築し、重みに候補のサイズ0バッファを一時設定して `supports_op` を呼ぶ。サイズ0はバッファ型を保持するメタデータで、バックエンド固有の割当コールバックを呼ばない。
4. D0は幅160を許可したため、同じ幅のjoinedでもROCm_Host候補が判定を通過できた。D0-4CのOriginal実測ではCPUモデル27,465.95 MiBの行が消え、ROCm_Hostが497.31 → 27,963.27 MiB、ROCm0が50,191.17 MiBのまま。仮想メモリ不足イベントとROCmエラーが発生した。配置変化は上記経路と整合する。ページ固定から異常終了に至った直接の因果関係は未確定。 [D0-1の設計](B12651-D0-1-HIP-IQ4NL-GETROWS-20261126.md) · [Original失敗記録](B12651-D0-4C-ORIGINAL-HIP-IQ4NL-GETROWS-20261127.md)

## 候補の比較と変更範囲

| 候補 | 評価 |
| --- | --- |
| **共有 `supports_op` で非256整列IQ4_NLのホストバッファを拒否** | 採用。ローダーとスケジューラで同じ判定を使い、デバイスバッファでの新経路を維持できる。既存の `ggml_backend_buft_is_cuda_host` を使用する。 |
| HIP限定のホスト拒否 | Windows ROCmで必要な効果は得られる。共有の候補選択でCUDA系ホストバッファの扱いがビルド別になる。 |
| joined PLE固有のloader例外 | モデルへの影響を最も限定できる。loader側にモデル識別とバックエンド固有ポリシーが必要で、同じ代表GET_ROWSを使う他モデルのホスト配置問題には届かない。 |

`ggml/src/ggml-cuda/ggml-cuda.cu` の `GGML_OP_GET_ROWS` 内の `GGML_TYPE_IQ4_NL` 分岐だけが製品差分。重みがviewであれば、schedulerと同じく `view_src` の格納バッファを参照する。非256整列かつ格納バッファがCUDA系ホストならfalse。バッファ未設定ではD0の形状・型判定を返し、既知の格納先が付いた時点でホストの制約を適用する。256整列では前記条件に入らず、旧経路の判定と32スレッドのdispatchが残る。幅32、160、288では未割当とデバイスバッファの従来判定を維持し、ホストでは拒否する。padded viewでもbaseのバッファ型を認識する。

CUDA、HIP、同じ `ggml-cuda/*.cu` をコンパイルするMUSAに共通。影響範囲はモデル名を問わず、非256整列IQ4_NL GET_ROWSの当該ホストバッファ。CPUメモリ一般を拒否する条件ではない。他量子化型、CPUとVulkanの実装、loader・モデル定義、GET_ROWSカーネルに直接変更はない。CUDAとMUSAのビルド・実機は未検証。

### schedulerの確認

既存構成では、OriginalのROCm_Host候補を拒否すると通常CPU候補がCPUの `GET_ROWS` 対応判定を通る。splitのROCm0候補は通過する。実行時の `ggml_backend_sched_backend_id_from_cur` は `WEIGHTS` を優先し、格納型と演算の両方をサポートするバックエンドを選ぶ。通常CPUバッファはROCm0の `supports_buft` の対象外であり、CPUのjoined重みでCPUノードが選ばれる。GPUへ引き上げる任意のoffload判定はGET_ROWSのバッチサイズ0と既定閾値32でfalse。後続の展開は割当済みCPUノードを上書きせず、優先順位を引き上げる分岐は互換バッファ型を要する。標準配置ではjoinedテーブル全体のGPUコピーを新たに要求する経路は見当たらない。後続GPU演算へのgather出力のコピーは既存経路の範囲。任意の配置overrideやoffload閾値変更を含む構成と、実際の割当・転送量は未確認。 [scheduler](https://github.com/ariera-j/llama.cpp-evox2-windows/blob/86e343cd4bfa0110f49e430d59081725af976e01/ggml/src/ggml-backend.cpp#L1315)

## テスト追加と静的確認

`tests/test-backend-ops.cpp` に `support -p` 用の6ケースを追加した。既存の小型IQ4_NL GET_ROWSのshapeを再利用し、メタデータ専用contextで重みのバッファ型をサイズ0のダミーで指定する。paddedケースはviewのbaseに指定する。各ケースは `supports_op` の結果を期待値と比較し、不一致ならバックエンドおよび終了コードを失敗にする。既存のsupport表示プローブとD0-1の数値ケース5件を保持した。対応判定のprobeはテンソルデータを確保せず、グラフ演算も行わない。テストEXEのデバイス列挙と選択バックエンドの初期化は既存機能として残る。

| 実行バックエンド | 幅 | バッファ | レイアウト | 期待表示 |
| --- | ---: | --- | --- | --- |
| ROCm0 | 160 | デバイス | 連続 | SUPPORTED |
| ROCm0 | 160 | ホスト | 連続 | NOT SUPPORTED |
| ROCm0 | 160 | ホスト | padded view | NOT SUPPORTED |
| ROCm0 | 256 | デバイス | 連続 | SUPPORTED |
| ROCm0 | 256 | ホスト | 連続 | SUPPORTED |
| CPU | 160 | CPU | 連続 | SUPPORTED |

以下は別承認で作成した新ビルドに対する将来の実行案。 `$testExe` は来歴を照合した新ビルドのEXEとする。

```powershell
& $testExe support -b ROCm0 -o GET_ROWS -p '^type=iq4_nl,d0_4d_width=(160,buffer=(device,padded=0|host,padded=[01])|256,buffer=(device|host),padded=0)$'
& $testExe support -b CPU -o GET_ROWS -p '^type=iq4_nl,d0_4d_width=160,buffer=cpu,padded=0$'
& $testExe test -b ROCm0 -j 1 -o GET_ROWS -p '^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$'
```

supportはROCm0で5行、CPUで1行。表の期待表示と1行ずつ照合し、対象バックエンドOK・終了0・欠落や重複なしを要求する。数値テストはD0-2Bと同じROCm0の5件で、各OKと5/5を要求する。 `-b` の完全一致と `-p` のアンカーを確認し、旧数値・新supportの登録は別モード。数値テストのGET_ROWS指定は `run_fa_vec_slice` を対象外にする。静的なラベル抽出と幅・バッファ条件の照合で5＋1件、既存数値5件を確認した。 `git diff --check` は通過。 [既存のD0-2B再検証](B12651-D0-2B-RETEST-HIP-IQ4NL-GETROWS-20261127.md)

## 実機の読み取り専用事後監査

2026-11-27 10:20:11 JST。空きRAM **27.353 GiB**、現在commit **8.116 GiB**／上限 **127.647 GiB**。OS起動以降のcommit高水位 **127.613 GiB** は前回終了後から同値で、失敗時の履歴。WDDM Dedicated／Sharedは **0.461／0.035 GiB**、GPU Engine利用率カウンター合計0%。P-MODEはPerformance、OS起動時刻は前回と同じ `2026-11-26T11:45:51.5000000Z`。前回のCLI・監視・MatrixのPIDおよびADLX名の残留なし。

前回最終カーソル以降、System 69921 → 69924（3件）、Application 44227 → 44242（15件）。すべて情報レベルで、追加のGPU、メモリ枯渇、異常終了の重大イベントは観測しなかった。前回のGPU詳細回復 `Unobserved` の判定は維持した。生ログは `C:\llama-build\_logs\codex\d0-4d-1-audit-20261127` の `snapshot.json` と `event-delta.json`。失敗時の生ログは `20261127-093643-307-cli-rocm-b12696-ctx4096-b82ed489f63c`。

修正後のビルド、GPU初期化、backend-op数値検証、モデルロード・推論は未実施。OriginalのCPU配置復帰、実モデル上のsplit PLE16配置維持、メモリ回復は次の個別承認で確認する。製品採用は保留のまま。
