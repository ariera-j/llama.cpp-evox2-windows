# HIP-2E-4B　scheduler 検証ハーネスと派生監督ツール

**READY FOR REVIEW**。基準 5cc54b8c04f5ec812d5b8a35f452eb8679de948e から実機の C:\llama-build\automation\w64 に codex/b12651-rocmfp4-hip2e4-20261129 を作成。製品 a650d641ee99198543697e1e3913c593059721f7、HIP-2D a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959、旧実験と main d0bf0911c135594e19038488613f9211a1dd5a3e は保全した。

## 実装

tools/evox2/hip2a の cases.inc、fixtures.py、harness.cpp を変更。直接10件のケース行・export・数値検査を継承した。S-HC-CPU と新 HC の activation、ID ケースの ID は、alloc_graph で自然割当と書換えを検査し、コピー先を poison する。主演算の eval callback の ask 段階で型・全 ne/nb・生データを確認する。ID は元 view から独立した device tensor に入り、2,048 byte 間隔の3行、最後の2 slot までの4,104 byte を比較する。active ID と −99 は HIP 初期化前に検査する。元親の6,144 byte と両 guard は計算後に検査する。split_copy は activation の論理的置換を示し、id_copy は ID の置換を示す。物理 DMA 回数は測定しない。

配置負例では pinned dst・x を用意し、元 op の HIP/CPU supports_buft・supports_op を採取してから割当を行う。実 backend 名と全カウンタを出力し、期待値を検査して compute 手前で解放・return する。出力ポインタは null、長さ0。専用 PASS 行だけを使用する。数値ケースの FAST stage と host ID 分岐の span/pitch は0、コピー先は observed_span/pitch で報告する。

## 監督・固定情報

main の run_hip2e_suite.py（fd5921966e32dbc43cdb701bc367c2b79a0880475ef48d5c811eb630297f2104）と mock（f4a683d2961250e27d23757bf64eebb4728e7a058f48563035a436d293fbda9e）から tools/evox2/experiments/hip2e4 に派生。14件の順序、数値13件の参照、負例の専用 PASS、経路項目の完全一致、hip2e4- 接頭辞を適用。保存先は --output-dir 配下の新接頭辞の summary とログディレクトリ。全件成功時は4ファイル×14件。SSH、監査、異常停止、原ログの照合は旧実装を継承した。

後続ビルドの測定後、controller で使う派生監督ツールの PINNED に source_commit、binary_dir（実 BuildDir の bin/Release）、manifest_sha256、hip_dll_sha256、ggml_dll_sha256、base_dll_sha256、cpu_dll_sha256、cli_sha256 を固定する。build 対象を固定した後に監督側で pin を保存することで自己参照 SHA を避ける。実ビルドの worktree が異なる場合は worktree も照合・更新する。既存 libomp hash・main pin も監査時に一致が必要。未固定の間は run_suite が SSH の前に拒否する。

## 検証

正規化 catalog SHA-256 は 5d5a2e08ae7eed50a6d6cb52013a4ce0e92c6c51cfa94088690039cb990258a6（CASE 行を LF で連結、終端 LF なし）。controller で dry enumerate 14件、CPU 個別参照13件、旧11件の geometry・fixture・参照・許容値・SGEMM 数の個別一致、新2件の旧数値 fixture との一致を確認。Python の py_compile と offline mock を実施した。mock の全件成功・56ログ回収は実機での実行結果とは区別する。以下は CPU 参照値であり、配置負例には参照値を付与しない。

- PASS 1 reference SHA256 d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a
- PASS 1-NC reference SHA256 d29a1e441ed6e8730a2bfeff0d79bdd63b3d438b1ec43a07b794fc4c4baae70a
- PASS 2 reference SHA256 637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f
- PASS 2-C reference SHA256 637b914bafc3774a6aa5d5c01b5b0d33c1ac7f796b021d9f66d88ad8be0e509f
- PASS 5 reference SHA256 0978449fc6f46e694dcffa7841034c6a4d85da13766c20b55e37446f32597cbd
- PASS 6 reference SHA256 f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1
- PASS 7 reference SHA256 d3ab1c4678f9604738fc286adbe9ee181a9e0bd56f6a55e4fa8616f28d933c1e
- PASS 8 reference SHA256 3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb
- PASS 9 reference SHA256 9203115b655f0305deaad40823cf2920d8e33e3c2d6ef9ad9d45001ff9146414
- PASS 9-Z reference SHA256 738c079dff6c9b77a0891ac42db1cabcab933a672b14aed8ecfcf94c0e77bb40
- PASS S-HC-CPU reference SHA256 f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1
- PASS S-HC-PIN-COPY reference SHA256 f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1
- PASS S-ID-PIN-COPY reference SHA256 3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb

ビルド、DLL ロード、GPU・モデル実行は今回の対象外。C++ コンパイルと実機での新規3ケースの実測は、独立レビューと後続承認を待つ。旧 summary の 11 PASS / 1 FAIL / 1 NOT RUN は更新していない。
