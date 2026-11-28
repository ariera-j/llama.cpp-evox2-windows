# ROCmFP4 FAST PLE16 scheduler 検証ハーネス実装記録（HIP-2E-1、2026-11-29）

- **担当**：Codex Astra Medium（実装）、ChatGPT（独立レビュー：GO）、Codex Astra Low（commit・push）
- **判定**：**GO**（実験ブランチへ固定済み）

## 1. 基準 SHA と変更範囲

| 項目 | SHA / 値 |
|---|---|
| `main`（文書正本） | `57d60df3c2507c1a96c6370a8fba8736ceb906b4` |
| 製品基準 SHA（変更禁止） | `a650d641ee99198543697e1e3913c593059721f7` |
| HIP-2D 検証済み SHA（変更禁止） | `a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`（`codex/b12651-rocmfp4-hip2-20261128`） |
| HIP-2E 実験ブランチ | `codex/b12651-rocmfp4-hip2e-20261128` |
| HIP-2E 実装・ビルド元 SHA | `5cc54b8c04f5ec812d5b8a35f452eb8679de948e` |
| 差分規模 | 5 ファイル、+295 / -11 行 |

## 2. 実装概要

HIP-2D の直接 backend 検証（10 件）に加え、`ggml_backend_sched` 経由で ROCmFP4 FAST 経路および host staging / split copy / 非連続 ID pitch を検証するため、以下の 3 ケースを `tools/evox2/hip2a/` ハーネスへ追加した。

| Case ID | 目的 | 期待される経路診断指標 |
|---|---|---|
| `S-HC-CPU` | CPU activation からの split copy 経路 | `split_copy=1, stage_h2d=0, stage_d2h=0, host_reads=0, span=0, pitch=0, ops=1, sgemms=1` |
| `S-HC-PIN` | pinned 出力を含む host staging 経路 | `split_copy=0, stage_h2d=1, stage_d2h=1, host_reads=0, span=0, pitch=0, ops=1, sgemms=1` |
| `S-ID-PIN` | pinned 非連続 ID 入力経路 | `split_copy=0, stage_h2d=0, stage_d2h=0, host_reads=1, span=4104, pitch=2048, ops=1, sgemms=2` |

- `harness.cpp` にて scheduler 経路診断行および数値誤差診断（`max_relative_error`, `max_condition`）を stderr へ出力し、さらに `ggml_backend_sched_get_tensor_backend(sched, dst) == hip` 等の事前 assert 検査を組み込んだ。
- 既存の製品コード・HIP-2D 検証済みブランチ（`a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`）への変更は行われていない。
