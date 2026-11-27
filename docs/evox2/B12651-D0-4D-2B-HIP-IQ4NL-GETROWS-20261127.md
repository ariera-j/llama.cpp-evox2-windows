# B12651 D0-4D-2B IQ4_NL GET_ROWS host配置制限の限定検証

2026-11-27 JST。**合格。** 対応判定6件が期待値と一致し、ROCm0のCPU参照との数値比較5件がすべて合格した。承認された3プロセスはそれぞれ1回起動し、ネイティブ終了コード0と監査合格を確認した順に次へ進んだ。

## 実行基準

| 項目 | 値 |
| --- | --- |
| 実験ブランチ | `experiment/hip-iq4nl-ple160` |
| 実行時のGitHub・worktree・追跡先HEAD | `17c8f61d20f1ab02f53e094a0732a7c9812134a6` |
| ビルド元 | `e199e5f4319731071199d84f4f2e571fcaa7d413` |
| ホスト配置制限のソース・C++テスト | `86e343cd4bfa0110f49e430d59081725af976e01` |
| 文書・共通ツール | main `891e2605fbc0798228ffad2a69dd618f6cdab216` |
| ビルド | `build-rh`、b12709、`BuildIdentity=Verified` |
| EXE | `C:\llama-build\automation\w55\build-rh\bin\Release\test-backend-ops.exe`、2,500,096 byte |
| EXE SHA-256 | `993c6f4b16c52d82d246f48c4e67eb5c751d703379ccdd39c8f34cc512e003f3` |
| HIP DLL SHA-256 | `2fa77001a526fff6bf907577b39cec29122d4bc35dbbc957d3b47b0f34d5089f` |
| マニフェスト SHA-256 | `8739b90b5833c5da38bcde6e2d4c466a986d7acc6200a4f03f7f41f5fcfc7116` |
| 環境 | EVO-X2、ROCm0 Radeon 8060S (gfx1151)、UMA 96 GiB、Adrenalin 26.11.2、TheRock 10.0.0 |

実行前の作業ツリーはクリーンで、3件の完了までHEADを固定した。各実行の `provenance.json` でビルド元、成果物のハッシュ、runtimeの `Verified`、環境上書きの不在を確認した。[D0-4D-2A ビルドと実行計画](B12651-D0-4D-2A-HIP-IQ4NL-GETROWS-20261127.md)

## 実行順序と終了情報

各行の値を `-Case` に指定し、作業ディレクトリ `C:\llama-build\automation\w55` から独立したSSH呼び出しで実行した。

```powershell
& '.\tools\evox2\experiments\iq4nl-getrows\Invoke-D0GetRows.ps1' -ExpectedHead '17c8f61d20f1ab02f53e094a0732a7c9812134a6' -Case <表の値> -RunApproved
```

子の時刻は2026-11-27 JST。子の経過時間はネイティブプロセスの開始・終了時刻の差、監督時間はStopwatch値。

| 順序・Case | 子開始 → 終了 JST | 子 ms | 監督 ms | ネイティブ終了コード | ExpectedOutput / Passed |
| --- | --- | ---: | ---: | ---: | --- |
| 1 `RocmSupport` | 11:11:29.3180176 → 11:11:29.5605651 | 242.5475 | 267.9590 | 0 | True / True |
| 2 `CpuSupport` | 11:12:33.6378407 → 11:12:33.7846801 | 146.8394 | 155.6835 | 0 | True / True |
| 3 `RocmNumerical` | 11:13:03.5101029 → 11:13:03.7832849 | 273.1820 | 283.7841 | 0 | True / True |

全件が60秒上限内に終了し、stdout/stderrを保存した。監督・監視・停止・メタデータ取得・後処理のエラーはなかった。

## 対応判定と数値比較

| Case | 幅 | バッファ | padded | 期待値 | 実測 |
| --- | ---: | --- | ---: | --- | --- |
| RocmSupport | 160 | ROCm0 device | 0 | SUPPORTED | SUPPORTED |
| RocmSupport | 160 | ROCm_Host | 0 | NOT SUPPORTED | NOT SUPPORTED |
| RocmSupport | 160 | ROCm_Host | 1 | NOT SUPPORTED | NOT SUPPORTED |
| RocmSupport | 256 | ROCm0 device | 0 | SUPPORTED | SUPPORTED |
| RocmSupport | 256 | ROCm_Host | 0 | SUPPORTED | SUPPORTED |
| CpuSupport | 160 | CPU | 0 | SUPPORTED | SUPPORTED |

| 数値比較（ROCm0、1ワーカー） | padded | CPU参照との比較 |
| --- | ---: | --- |
| 幅32 | 0 | OK |
| 幅160 | 0 | OK |
| 幅160 | 1 | OK |
| 幅256 | 0 | OK |
| 幅288 | 0 | OK |

`RocmNumerical` は `5/5 tests passed`。各呼び出しの対象バックエンドは `OK`。期待ケースは個別に各1件で、追加ケース、欠落、重複、対象ケースのスキップはなかった。列挙上の `Skipping` は対象外バックエンドに対応する。

## 開始・終了監査

容量はGiB。各欄は開始前 → 終了後。

| Case | 物理空きRAM | 現在commit | WDDM Dedicated | WDDM Shared | 子PID / 監視PID |
| --- | --- | --- | --- | --- | --- |
| RocmSupport | 27.133804 → 27.165859 | 8.315166 → 8.268108 | 0.461063 → 0.461063 | 0.035149 → 0.035149 | 15704 / 2436 |
| CpuSupport | 27.222324 → 27.192085 | 8.230259 → 8.258648 | 0.461063 → 0.461063 | 0.035149 → 0.035149 | 17640 / 2228 |
| RocmNumerical | 27.132809 → 27.130768 | 8.321442 → 8.323696 | 0.461063 → 0.461063 | 0.035149 → 0.035149 | 14228 / 11504 |

- 全件で前後の物理空きRAMは16 GiB以上、commitとWDDM Dedicatedの終了時増分は各4 GiB以内。commit limitは前後とも127.647282 GiB。OS起動以降のcommit高水位127.612583 GiBは先行のOriginal失敗時の履歴として保持されている。
- 各件の前後ともP-MODEはPerformance、OS起動時刻は `2026-11-26T11:45:51.5000000Z`。Systemのイベントカーソルは全件 `69927 → 69927`、Applicationは `44248 → 44248`。差分監査に成功し、新規イベントと重大イベント候補は0件。各件の残留確認で子・監視プロセスともに0件。
- 各子は0.28秒未満で終了し、存命中に完了した監視サンプルは0件。前後スナップショットは取得済み。実行中のGPU利用率と瞬間最大メモリは未観測。

## 配置への含意と未検証事項

- Originalのjoined PLEに関して、幅160のROCm_Host候補が拒否され、CPU backendが同幅を受理することを確認した。従来のCPU配置に戻るという見立てを支持する。実モデルの配置先、ページ固定とメモリ逼迫、ロード・推論・回復の挙動は未検証。
- PLE16に関して、幅160のROCm0 device候補が受理され、連続とpaddedの両layoutでCPU参照との数値比較が通った。GPU配置を維持できるという見立てを支持する。修正版での実モデル配置、推論結果、性能、CUDA実機での動作は未検証。

## 生ログ

保存先は実機の `C:\llama-build\_logs\codex`。各ディレクトリに `provenance.json`、`status.json`、`audit.json`、`before.json`、`after.json`、`event-delta.json`、`residual-check.json`、`stdout.log`、`stderr.log` を保持した。

| Case | ディレクトリ |
| --- | --- |
| RocmSupport | `d0-4d-getrows-2a6c32deef394ecd99df02ca02d2b58f` |
| CpuSupport | `d0-4d-getrows-ba1bd06b45ee4250805db0e3ad8ca668` |
| RocmNumerical | `d0-4d-getrows-dcba6cf9c6b94b50a5e5ae790065014d` |
