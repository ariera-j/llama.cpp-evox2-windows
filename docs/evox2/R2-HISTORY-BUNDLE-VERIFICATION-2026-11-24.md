# r2 履歴の独立バックアップ検証

2026-11-24 JST に、[棚卸し台帳](BRANCH-ARCHIVE-INVENTORY-2026-11-23.md) の r2 保全計画に沿って GitHub から新規に `git clone --mirror` を実行し、その mirror で `git bundle create <bundle> --all` を実行した。取得時点の `main` は `083480e0ba951acfa38bb11b6f5b7f19c1ddf592`。

| 項目 | 結果 |
|---|---|
| ファイル名 | `llama.cpp-evox2-windows-all.bundle` |
| 容量 | 421,183,190 バイト |
| SHA-256 | `70482e121f237ace538f9e28ce53266866e1461fd707a23bde2f7bafdc414bfd` |
| 検証時刻 | `2026-11-23T16:02:07.4780297Z` |
| `git bundle verify` | 成功。完全な履歴を持つ bundle と判定 |
| 独立復元 | 成功。mirror と復元先の全 66 refs が一致（ブランチ 21、タグ 45） |
| アーカイブタグ | 33/33 件のタグオブジェクト SHA と参照先コミット SHA が [凍結マニフェスト](BRANCH-ARCHIVE-TAGS-MANIFEST-2026-11-23.json) と一致 |
| `r2/legacy` の先端 | `23c316fb5af67da74e614af4a7453fba9ae46189` と一致 |
| r1 | `ee245db63d4bd08f590aa5a4d756c5913e56ffdd` がコミットとして存在 |
| 元ベース | `5e085d123eead2e89b5c19f824fccb05727da6a2` がコミットとして存在 |

bundle、mirror、検証記録は EVO-X2 の Codex 専用領域に保管した。復元テスト用ディレクトリは削除済み。外付け HDD は専用アカウントから利用できなかったため、外部媒体への保管には手動コピーが必要。コピー後は上記 SHA-256 と照合できる。

保全範囲は GitHub の mirror が取得した refs とその到達履歴。r2 の先端ツリーで submodule の gitlink と Git LFS の属性設定はともに 0 件だった。この確認は r2 の先端ツリーに限る。Git LFS の外部実体、リリース添付ファイル、実験ログ、旧 clone にしか存在しない参照は bundle の保全範囲外。
