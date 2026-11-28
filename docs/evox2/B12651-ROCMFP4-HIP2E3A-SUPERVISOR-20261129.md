# ROCmFP4 FAST PLE16 直列監督ツール開発・レビュー記録（HIP-2E-3A、2026-11-29）

- **担当**：Gemini 4 Hydrogen (Medium)（実装・修正）、ChatGPT（独立レビュー：GO）
- **保存先（固定実験版）**：[tools/evox2/experiments/hip2e3/run_hip2e_suite.py](../../tools/evox2/experiments/hip2e3/run_hip2e_suite.py)

> [!IMPORTANT]
> 本スクリプトは HIP-2E 実験（ビルド元 SHA `5cc54b8c04f5ec812d5b8a35f452eb8679de948e` / `main` `57d60df3c2507c1a96c6370a8fba8736ceb906b4`・固定 13 ケース）専用の実験用監督ツールであり、**まだ汎用製品ツールではありません**。

## 1. 固定成果物と SHA-256

| ファイル | SHA-256 | 備考 |
|---|---|---|
| `run_hip2e_suite.py` | `fd5921966e32dbc43cdb701bc367c2b79a0880475ef48d5c811eb630297f2104` | 固定版（変更禁止） |
| `test_run_hip2e_suite.py` | `f4a683d2961250e27d23757bf64eebb4728e7a058f48563035a436d293fbda9e` | mock テスト 10 グループ |

既存単発用 `review/hip2d/run_hip2d_case.py`（SHA-256 `50d8d8f6c3200767e6ff2319dc317f956b76863be9906f32d3060ff1bd6c42c4`）は無変更で保全した。

## 2. 安全設計とレビュー反映内容

1. **ThinkPad 側からの 1 ケース・1 独立 SSH 直列起動**：Windows 側ループを禁止し、1 ケースずつ `System.Diagnostics.Process` で起動。stdin 経由 1 行 base64 bootstrapper によりコマンドライン長制限と `[Console]::In.ReadToEnd()` ハングを回避。
2. **Pre-Audit と固定 hash 照合**：`w62` の `Head`, `RemoteMain`, `RemoteBranch`, `Clean=true`, `6` バイナリ + `System32\libomp140.x86_64.dll` SHA-256、`PMode=Performance`、空きメモリ >= 16 GiB、WDDM カウンタ正常性、13 件 CPU 参照 SHA-256 を起動前に検証。
3. **ケース間監査・異常時即時停止**：60 秒超過（`TimedOut` および `ElapsedSeconds >= 60.0`）または監視ループ例外発生時に即座に子プロセスを `Kill()` し終了確認。終了後のイベントログ逆行/新規重大エラー、物理空き < 16 GiB、Commit/Dedicated +4 GiB 超増加、残留プロセスを拒否し後続ケースを実行しない。
4. **原ログ厳密照合（CRLF 保持）**：`collect_logs()` にて `.stdout.log` / `.stderr.log` を `read_bytes().decode("utf-8")` で厳密比較し、不正 UTF-8 バイト列を拒否。

## 3. 検証状況（実機確認済みと未確認の区別）

- **ローカル・静的検証**：`py_compile` PASS、mock テスト **10/10 PASS**（`0.137s`）、EVO-X2 上 PowerShell 5.1 `Parser::ParseInput` 構文エラー `0` 件（`PARSE_CASE_ERRORS=0`）、実機 `--pre-audit-only` PASS（`preaudit-20261129-v2`）。
- **実機で確認済み**：
  - pre-audit
  - 単一ケースの数値検証と 4 ログ回収（HIP-2E-3B-0）
  - 複数ケースの直列実行（HIP-2E-3B）
  - 異常検出と後続ケース停止（HIP-2E-3B：`S-HC-PIN` 異常で停止し `S-ID-PIN` を `NOT RUN` 保全）
- **実機未確認**：
  - 全 13 件成功時の 52 ログ一括回収
  - timeout 等の異常系（mock テストのみで確認）
