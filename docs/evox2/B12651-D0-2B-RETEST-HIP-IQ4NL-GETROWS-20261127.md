# b12651 D0-2B 再検証 — ROCm IQ4_NL GET_ROWS

**合格。** 2026-11-27 00:13 JST、レビュー済み監督スクリプトで1回実行した。CPU参照との比較は全5ケースが個別に1回ずつOK。子プロセスは終了コード0で終了し、`audit.json` は `Passed=true`、`NumericalCases=true` だった。

## 開始条件と来歴

| 項目 | 確認結果 |
| --- | --- |
| 文書・共通ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216` |
| 実行前HEAD | 実験ブランチ `experiment/hip-iq4nl-ple160` の `1146a8f8d7db1e17b285f6343476d7c4cbb9ce20`。GitHub、実機 `w55`、追跡先が一致、作業ツリーはクリーン |
| ビルド元 | `044be892e12bffdfd06cfb698bf55e54582ae63a`、b12696、`BuildIdentity=Verified` |
| テストEXE | `C:\llama-build\automation\w55\build-rm\bin\Release\test-backend-ops.exe`、2,490,368 byte、SHA-256 `24ef370e740df616c2e64dd7114811a037e7089a9a7dd34f7dc9299b0762a5ac` |
| ランタイム | `RuntimeDependenciesV1` の検証結果は `Verified`。マニフェストSHA-256 `28ec1ff4ee9ced5469a86c6970738eed59acd4647cb1575e4bac2a3894cdbd7f`、HIPバックエンドSHA-256 `21779032dc5401e1735b1ac07da19628d736fda0327b79447e9194d78ef9780c` |
| 実機 | Windows 11 26300.10075、Adrenalin 26.11.2、TheRock 10.0.0、UMA 96 GiB。GPU可視性・バックエンド探索パスの上書きなし |
| デバイス | 起動前のCLI列挙で `ROCm0: AMD Radeon(TM) 8060S Graphics`。テストstderrで同デバイスの `gfx1151`、Wave Size 32、固定ビルド配下の `ggml-hip.dll` のロードを確認 |

レビュー済みスクリプトの開始条件を通過し、次のコマンドを1回実行した。子の引数は `test -b ROCm0 -j 1 -o GET_ROWS -p "^type=iq4_nl,d0_1_width=(32,padded=0|160,padded=[01]|256,padded=0|288,padded=0)$"`。1ワーカー、監督の上限は60秒。 [D0-2Cの監督処理](B12651-D0-2C-HIP-IQ4NL-GETROWS-20261127.md)

```powershell
Set-Location 'C:\llama-build\automation\w55'
& '.\tools\evox2\experiments\iq4nl-getrows\Invoke-D0GetRows.ps1' -ExpectedHead '1146a8f8d7db1e17b285f6343476d7c4cbb9ce20' -RunApproved
```

## 数値結果と初回との比較

| IQ4_NL GET_ROWS | 初回 | 再検証 |
| --- | --- | --- |
| 幅32、padded=0 | OK | OK |
| 幅160、padded=0 | OK | OK |
| 幅160、padded=1 | OK | OK |
| 幅256、padded=0 | OK | OK |
| 幅288、padded=0 | OK | OK |
| 集計・バックエンド | `5/5 tests passed`、`Backend ROCm0: OK` | 同左 |
| ネイティブ終了コード | 欠損 | 0 |
| 子の開始 → 終了（JST） | 23:49:50.7920427 → 欠損 | 00:13:42.6939578 → 00:13:42.9708257 |
| 子の実行時間 / Stopwatchによる監督時間 | 欠損 / 欠損 | 276.8679 ms / 287.2105 ms |
| 総合判定 | 合格未成立 | 合格 |

対象外ケース、非対応、ケースのスキップ、重複、欠落は0件。CPUデバイス列挙後の `Skipping` は独立テスト対象からの除外表示。NaN、Inf、数値比較エラー、GPUエラーはログになく、NMSEの実測値は出力されなかった。 [初回の結果](B12651-D0-2B-HIP-IQ4NL-GETROWS-20261126.md)

`status.json` で連続した子の開始・終了と終了コード0、`ChildEnded=true`、`MonitorEnded=true`、`StdoutSaved=true`、`StderrSaved=true` を確認した。監督側の終了コードも0。監督・停止・監視エラー、メタデータ取得エラー、cleanupエラーは0件で、停止理由はなし。子のPID 16972、監視のPID 12688は別途確認でも残留なし。

## 資源回復とイベント監査

| 観測値 | 起動前 | 終了後 |
| --- | ---: | ---: |
| 物理空きRAM（GiB） | 26.639431 | 26.657661 |
| commit（GiB） | 8.338749 | 8.318333 |
| commit limit（GiB） | 127.647282 | 127.647282 |
| WDDM Dedicated / Shared（GiB） | 0.460197 / 0.071655 | 0.460197 / 0.071655 |
| GPU Engineの利用率合計（有効件数） | 0%（269） | 0%（269） |
| P-MODE | Performance | Performance |

終了後の物理空きは16 GiB以上で、開始時比のcommitは約0.020416 GiB減、Dedicatedは増分0。開始・終了の回復条件を通過した。Kernel-General 12のOS起動時刻 `2026-11-26T11:45:51.500Z` とRecordID 69721は前後一致。Systemのカーソルは69911、Applicationは44068で前後一致し、新規イベント・重大イベント候補は0件。両チャネルの差分監査は成功した。

`sample-001.json` の採取は00:13:42.7621936 JSTに開始したが、WDDMカウンターの観測は子の終了後で、サンプル全体は00:13:46.0527781 JSTに完了した。`SamplesWhileChildAlive=0`。子が約277 msで終了したため、演算中に完結したGPUサンプルはなく、その区間の利用率は未観測。前後の0%を演算中の利用率として扱わない。

生ログは `C:\llama-build\_logs\codex\d0-2c-getrows-f908064f5323454fab817c8f3ee8e393` に保存した。主な記録は `status.json`、`audit.json`、`stdout.log`、`stderr.log`、`provenance.json`、`devices.json`、`child.json`、`monitor-ready.json`、`before.json`、`sample-001.json`、`after.json`、`event-delta.json`。

## 未検証事項

合格範囲は固定ROCmビルドのIQ4_NL GET_ROWS 5ケース。実モデルのPLE配置、RAM・転送量への効果、新経路の性能、長時間GPU負荷や別演算の挙動は未検証。追加テスト、再ビルド、ソースや監督スクリプトの変更、D0-3への移行は実施していない。
