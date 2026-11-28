# HIP-2C-1 初回 Preflight 停止と HIP-2C-1A 依存関係監査例外（2026-11-28）

## 1. HIP-2C-1 初回 Preflight 失敗記録

- 対象 worktree：`C:\llama-build\automation\w57`（clean、detached HEAD `cab3886c3e76c6cb0716be62a60bfe752d9c0b7c`）
- 実行コマンド：`Invoke-CodexBuild.ps1 -Backend ROCm -Worktree -SourceCommit cab3886c3e76c6cb0716be62a60bfe752d9c0b7c -BuildDir build-h2t -PreflightOnly -Offline`
- 実行 ID：`build-ROCm-Preflight-b2374726fce641959d88303c85e2325f`
- 終了コード：`1`（Outcome: `Failed`）
- 所要時間：`3.9976513` 秒
- 停止フェーズ：`VerifyDependencies`
- 停止理由：
  ```text
  Dependency inputs differ from reviewed baseline f5e6915c28f10330885fcb9243a93ae98d3115ab. Review these files before building:
  ggml/src/ggml-hip/CMakeLists.txt: CMake configuration can change dependency acquisition
  ```
- ログ保存先（EVO-X2）：`C:\llama-build\_logs\codex\build-ROCm-Preflight-b2374726fce641959d88303c85e2325f.{stdout.log,stderr.log,result.json,state.json,worker.json}`
- 運用判断：Preflight 失敗のため Configure 以降（HIP-2C-2〜4）は実行せず停止した。`w57` は clean のまま保全した。

## 2. HIP-2C-1A 監査済み例外の仕様とレビュー

HIP-2A/2B で追加された `ggml/src/ggml-hip/CMakeLists.txt` の差分は、Windows 限定のテストハーネス組み込み用 5 行のみであり、外部依存関係の取得・取得元・バージョンに変更がないことを独立レビューで確認した。

- 対象ファイル：`tools/evox2/build/Evox2.DependencyCache.psm1`、`tools/evox2/build/Test-Evox2DependencyInputs.ps1`
- 監査基準 SHA（固定値）：`f5e6915c28f10330885fcb9243a93ae98d3115ab`
- 許可パス：`ggml/src/ggml-hip/CMakeLists.txt`
- 許可 Git blob hash：`b683a1d32fd8cf8e3bf15a788b16b1f2c083bd76`（基準 blob `35a898e230914a97f43d92ce114ca06ae8057aa1`）
- 適用条件：
  1. `$AuditedCommit` が固定監査基準 SHA `f5e6915c28f10330885fcb9243a93ae98d3115ab` と厳密一致すること（`Assert-Evox2DependencyInputs` は 2 引数固定）。
  2. 対象パスが `ggml/src/ggml-hip/CMakeLists.txt` と完全一致すること。
  3. 実ファイルが存在し、`git hash-object` が `b683a1d32fd8cf8e3bf15a788b16b1f2c083bd76` と完全一致すること。
  4. `tracked` 差分のみを除外し、`untracked`・`ignored`・その他 CMake / package / submodule 変更はすべて従来どおり拒否すること。

## 3. テスト条件と結果

- テスト前提条件：ローカルオブジェクトストアに `f5e6915c28f10330885fcb9243a93ae98d3115ab` および `f19d5c75f68ae25bbd5a95b223e67d816c97e2fc` が存在すること（外部ダウンロードなし、一時リポジトリの `.git/objects/info/alternates` と `sparse-checkout` を使用し終了後削除）。
- 実行環境：EVO-X2 Windows PowerShell 5.1（隔離 worktree `C:\llama-build\automation\w58`）
- 検証項目（すべて PASS、終了コード `0`）：
  - 従来の全テスト
  - 固定監査基準 SHA に対する本番 2 引数呼び出しでの正確な HIP-2 blob 許可
  - 他の未レビュー CMake 変更共存時の拒否
  - 別の監査基準 SHA での例外非適用（拒否）
  - 1 行追加・変更時の拒否
  - 正確な blob が未追跡状態（固定監査基準 SHA 指定時を含む）での拒否
  - ファイル削除時の拒否
  - 一時リポジトリの残留なし確認、UTF-8 BOM (`EF BB BF`)、`git diff --check` 終了コード `0`

## 4. 保存コミット

- レビュー済みパッチ SHA-256（最終修正前、`Evox2.DependencyCache.psm1` は同一）：`75a89217508d0c80795a18b111287ec27d5ee88eb2d8c7d450fc0ea022048ff1`
- `main` 共通ツール修正コミット：`fe5dc0832ec6d7bc0d20d3537eef00fcb3b67693`
- `codex/b12651-rocmfp4-hip2-20261128` 反映コミット：`56e4f6dc7f332eb275de9d27bd3c12a7ed0c320d`（新たな HIP-2C ビルド元）
- 両ブランチで修正後 blob 一致を確認：
  - `tools/evox2/build/Evox2.DependencyCache.psm1`: `402f65a42c4b8402248d2f393b5d7f2d1917394f`
  - `tools/evox2/build/Test-Evox2DependencyInputs.ps1`: `39e2d6d905b630374b57fdbedc680d98af7a10bd`
