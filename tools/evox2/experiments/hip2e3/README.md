# HIP-2E-3 実験用直列監督ツール（固定 SHA 専用）

> [!WARNING]
> 本ディレクトリに収録されている `run_hip2e_suite.py` は **HIP-2E 実験（`main` `57d60df3c2507c1a96c6370a8fba8736ceb906b4` / ビルド元 SHA `5cc54b8c04f5ec812d5b8a35f452eb8679de948e` / 固定 13 ケース）専用の実験用ツール** であり、**まだ汎用製品ツールではありません**。ツール本体の無断変更は禁止します。

## 収録ファイル

| ファイル | SHA-256 | 説明 |
|---|---|---|
| `run_hip2e_suite.py` | `fd5921966e32dbc43cdb701bc367c2b79a0880475ef48d5c811eb630297f2104` | 直列監督スクリプト固定版 |
| `test_run_hip2e_suite.py` | `f4a683d2961250e27d23757bf64eebb4728e7a058f48563035a436d293fbda9e` | 対応 mock テスト（10 グループ） |
| `results/hip2e3b0-case1-20261129-summary.json` | — | HIP-2E-3B-0 単一ケース smoke 結果 |
| `results/hip2e3b-full-20261129-summary.json` | — | HIP-2E-3B 初回直列検証結果（11 PASS / 1 FAIL / 1 NOT RUN） |

## 検証済み範囲と未確認範囲

- **実機で確認済み**：
  - pre-audit（固定 SHA・6 バイナリ + `System32\libomp140.x86_64.dll`・P-MODE・資源・CPU 参照 13 件）
  - 単一ケースの数値検証と 4 ログ回収（`hip2e3b0-case1-20261129`）
  - 複数ケースの直列実行（`hip2e3b-full-20261129`、1〜11 件目連続 PASS）
  - 異常検出と後続ケース停止（12 件目 `S-HC-PIN` FAIL で安全停止し、`S-ID-PIN` を `NOT RUN` 保全）
- **実機未確認**：
  - 全 13 件成功時の 52 ログ一括回収
  - timeout 等の異常系（mock テストのみで確認）
