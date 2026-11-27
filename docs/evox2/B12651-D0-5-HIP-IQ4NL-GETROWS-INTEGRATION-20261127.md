# B12651 D0-5 IQ4_NL GET_ROWSの製品統合（ROCM-002）

2026-11-27 JST。host配置制限を含むD0最終修正版を運用者承認に基づき製品採用した。製品ブランチは既存の統合記録、GitHub、実機の登録worktreeで照合した。 [標準ビルドツール統合](automation/BUILD-INTEGRATION.md)

## 製品とコミット

| 項目 | 固定値 |
| --- | --- |
| 製品ブランチ | `codex/vulkan-manifest-cpu-variants-20261124`、実機の専用clone `C:\llama-build\automation\llama.cpp-evox2-windows` |
| 製品起点 | `9ae819d5be4fe9861d2aa8547983aed801c437ac`、upstream b12651ベース |
| 統合後製品SHA | `a650d641ee99198543697e1e3913c593059721f7` |
| 実験最終HEAD | `experiment/hip-iq4nl-ple160` の `fe961fa0685e141b9967b31271aef7ab4afb99b4` |
| 文書・共通ツールの従来基準 | main `891e2605fbc0798228ffad2a69dd618f6cdab216` |

| 順序 | 実験コミット | 製品コミット | 内容 |
| --- | --- | --- | --- |
| 1 | `b035acb957b10147d156c06365b2074338462303` | `aa8bf2d09df4da9d76325b3ce961232197fc8491` | IQ4_NLの32要素ブロック単位のGET_ROWS |
| 2 | `f97071be5b919c24b22f2d75846f72258ddd55d4` | `0e4c4639a521b0b019439c2f38ac6a5d137142ae` | 数値・境界・strideのテスト |
| 3 | `86e343cd4bfa0110f49e430d59081725af976e01` | `a650d641ee99198543697e1e3913c593059721f7` | host配置制限と対応判定テスト |

3件を順に `cherry-pick -x` で取り込んだ。製品起点との差分は `ggml/src/ggml-cuda/dequantize.cuh`、`getrows.cu`、`ggml-cuda.cu`、`tests/test-backend-ops.cpp` の4ファイル。 `git diff --check` は通過。製品と検証済みビルド元および実験最終HEADの間では、`docs/**` と実験専用 `tools/evox2/experiments/iq4nl-getrows/**` を除く全パスで差分なし。 `src`、`common`、`include`、ルートCMake、指定外の `ggml` とC++テストを含めて照合した。 [製品SHA](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/a650d641ee99198543697e1e3913c593059721f7) · [実験の固定ツリー](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/fe961fa0685e141b9967b31271aef7ab4afb99b4)

## 実装とhost配置制限

256要素に整列した行は既存の専用経路を維持する。非256整列のIQ4_NLは32要素ブロックのdecoderとstrideを使う経路を選ぶ。幅160では5ブロックを読み出す。対応判定はI32 index、連続F32出力、バッチ・stride・アライメントなど、実装の前提を確認する。 [D0-1設計](B12651-D0-1-HIP-IQ4NL-GETROWS-20261126.md)

最初のD0では対応条件が広がり、Originalのjoined PLEの候補 `ROCm_Host` が受理された。D0-4CではCPUモデルバッファ行が消え、ROCm_Hostは27,963.27 MiBに増加し、ロード中に仮想メモリ枯渇とROCmエラーが生じた。最終版は非256整列のIQ4_NL GET_ROWSで、格納先がCUDA系のhostバッファなら拒否する。viewでは格納元のバッファ型で判定する。これによりOriginalの通常CPU候補とsplit PLE16のROCm0 device候補がともに利用できる。ページ固定と異常終了の直接の因果関係は未確定。 [Original失敗記録](B12651-D0-4C-ORIGINAL-HIP-IQ4NL-GETROWS-20261127.md) · [host配置制限の設計](B12651-D0-4D-1-HIP-IQ4NL-GETROWS-HOST-PLACEMENT-20261127.md)

## 検証範囲と結果

| b12709の確認 | 結果 |
| --- | --- |
| 対応判定6件 | ROCm0の幅160 device・256 device・256 hostは対応。幅160 hostは連続・paddedとも非対応。CPUの幅160は対応。全6件が期待どおり |
| ROCm0数値比較5件 | 幅32、160連続、160 padded、256、288をCPU参照と比較し全件OK |
| PLE16 4k・64k | 49/49層offload。独立CPUモデルバッファ行なし、ROCm0 77,657.12 MiB、ROCm_Host 497.31 MiB。16 headのROCm0配置を支持する合計値で、個別headの実バッファ名は未確認 |
| Original 4k | `per_layer_token_embd.weight` のROCm_Host候補拒否とCPU選択をログで確認。CPU 27,465.95 MiB、ROCm0 50,191.17 MiB、ROCm_Host 497.31 MiB。応答 `OK`、終了0、回復ゲート通過 |

OriginalではUMA 96 GiBでの一時的な物理RAM逼迫が残る。今回の最小空きは3.691 MiB、1 GiB未満20サンプル、最長観測区間2.546秒。context構築前に1 GiB以上に回復し、資源枯渇イベントやROCmエラーは観測しなかった。 [対応判定と数値](B12651-D0-4D-2B-HIP-IQ4NL-GETROWS-20261127.md) · [PLE16 4k](B12651-D0-4D-3-HIP-IQ4NL-GETROWS-20261127.md) · [Original 4k](B12651-D0-4D-4-HIP-IQ4NL-GETROWS-ORIGINAL-20261127.md)

| PLE16 64k | D0適用前 | D0-4A（host制限前） | D0-4D-5（最終版） |
| --- | ---: | ---: | ---: |
| PP（tok/s） | 408.28 | 408.72 | 407.72 |
| TG（tok/s） | 22.13 | 21.81 | 21.75 |
| ロード中の最小空きRAM | 14.117 MiB | 24.531 GiB | 25.211 GiB |

すべて61,789入力／256生成トークンで応答本文が一致した。最終版はD0-4A比でPP −0.24%、TG −0.28%。どちらの基準からも5%超の低下を観測しなかった。PLE16の128k・256kおよびGemma 4の回帰確認は**host配置制限を追加する前**のb12696で実施した。最終版のCUDA・MUSAのビルドと実機、128k・256kおよびGemma 4は未検証。 [64k最終比較](B12651-D0-4D-5-HIP-IQ4NL-GETROWS-20261127.md) · [128k・256k](B12651-D0-4B-HIP-IQ4NL-GETROWS-20261127.md) · [Gemma 4](B12651-D0-4C-HIP-IQ4NL-GETROWS-20261127.md)

## 検証済みバイナリと記録

既存 b12709 は実機 `w55\build-rh\bin\Release` にあり、実ビルド元は `e199e5f4319731071199d84f4f2e571fcaa7d413`。マニフェストの `BuildIdentity=Verified` と次のSHA-256を読み取り照合した。今回の製品SHAはソース照合の基準で、バイナリのビルド元SHAは従来のまま。D0-5ではビルド、推論、GPUテスト、追加計測を実施していない。

| 成果物 | SHA-256 |
| --- | --- |
| `llama-cli.exe` | `538a12f93ed12ab2a639640d87aeb78582acca4d9d9c086fe5d6f9220f7c01de` |
| `test-backend-ops.exe` | `993c6f4b16c52d82d246f48c4e67eb5c751d703379ccdd39c8f34cc512e003f3` |
| `ggml-hip.dll` | `2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f` |
| `evox2-build.json` | `8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116` |

生ログのルートは実機 `C:\llama-build\_logs\codex`。各ビルド・対応判定・推論・失敗のログ名と監査先は個別記録に記載した。mainには16件の検証文書と公開用の結果CSV3件を集約。初回数値検証の総合合格未成立記録とOriginalの失敗記録を保持した。実験専用の監督スクリプト、解析コード、planは固定ツリーを参照する。 [初回監督記録](B12651-D0-2B-HIP-IQ4NL-GETROWS-20261126.md) · [限定再検証](B12651-D0-2B-RETEST-HIP-IQ4NL-GETROWS-20261127.md) · [実験専用ツール](https://github.com/ariera-j/llama.cpp-evox2-windows/tree/fe961fa0685e141b9967b31271aef7ab4afb99b4/tools/evox2/experiments/iq4nl-getrows) · [D0-4A CSV](d0-4a-20261127/ram-timeline.csv) · [D0-4B CSV](d0-4b-20261127/summary.csv) · [Original失敗時CSV](d0-4c-original-20261127/ram-timeline.csv)

次工程のROCmFP4 FAST HIP対応は製品SHA `a650d641ee99198543697e1e3913c593059721f7` を出発点とし、別承認で開始する。 [HIP移植レビュー](ROCMFP4-HIP-PORT-REVIEW-2026-11-26.md)
