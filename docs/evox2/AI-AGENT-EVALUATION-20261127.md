# AI エージェント評価記録 — Antigravity 初期調査（2026-11-27）

状態: 試用途中。技術候補・実装計画は [B12651 高速化候補統合調査](B12651-ANTIGRAVITY-OPTIMIZATION-REVIEW-20261127.md) に分離する。本記録は能力・利用枠・安全な運用の比較用。公開リポジトリに保存するため個人の認証情報、ローカル接続情報、セッション生ログは含めない。

## 1. 試用目的と条件

EVO-X2 の開発で Codex の利用枠消費を抑え、複数モデルの独立調査・レビュー・実装・計測を活用できるか評価する。モデル名は試用時の UI 表示。Antigravity Web/Remote Agent、同一 GitHub Project、試行ごとに新規 Conversation。簡易試行以外は同一の詳細プロンプトを使用。既往計測事実は参照可、前の Conversation の提案・レビューは与えない。製品と文書を別 SHA に固定。実機接続、ビルド、ソース変更、commit/push/PR を禁止。実際の隔離や hidden context までは確認できない。

- 製品: a650d641ee99198543697e1e3913c593059721f7 / codex/vulkan-manifest-cpu-variants-20261124。
- 文書: 2a65d8629a62927d0f20e00893a2d988c2159698 / main。
- 調査対象: Qwen3.8 Flash Next IQ3/PLE16/将来 FP4、Gemma 4 31B Q4_0、gfx1151 Windows ROCm 優先、Vulkan/共通も対象。
- 詳細プロンプトは ChatGPT が作成。最新ソース実行経路、既存パッチ、外部 PR/Strata、ボトルネック、定量推定と反証条件を要求。以下は再現用の**要約**であり原文全文ではない。

### 共通プロンプトの要件（要約）

1. 調査開始時に製品と文書の SHA を確認。main の推論ソースを製品と誤認しない。古い CURRENT-REFRESH 等は日付と版を確認。
2. EVO-X2 / RDNA3.5 Wave32/WMMA/UMA96 / Windows / TheRock10.0 / Adrenalin26.11.2 を基準に、NVIDIA/CDNA/RDNA、Windows/Linux の差を考慮。
3. Qwen3.8 長文脈64/128/256K PP/TGを優先、短文脈と Gemma 4 に回帰を生じさせない。ROCmFP4 HIP 対応は別工程。
4. PATCHES、PERFORMANCE-RESEARCH-LOG、INTEGRATED-RELEASES、BASELINE、ROADMAP、B12651、automation、RGP/host trace 等を必要に応じて調査。現行・旧独自・upstream済み・不採用・外部・新規を区別。
5. 現行の host dispatch、テンプレート実体化、device 制約、型、shape、fallback まで追跡。upstream PR/Issue、Strata、AMD fork/技術資料を探索。
6. PP/TG の演算、帯域、同期、CPU待ち、入力依存等を分析。Amdahl、前提、理論/実測/推定を区別。精度・決定性・VRAM・安定性・保守・検証難易度を評価。
7. 日本語レポート A:対象版、B:課題、C:5～10候補、D:上位3件の詳細（変更箇所、PoC、測定、採否）、E:重複、F:順序、G:限界/反証条件。コミット固定リンクを提示。
8. 読み取り専用。公開 repo の取得/検索は可、変更・push・SSH・実機ビルド/推論は禁止。調査の正確さを優先。

原文は2026-11-27の同一 ChatGPT 会話の詳細プロンプトを使用。厳密な再試行時は要約で代用せず、原文・SHA を再利用する。

## 2. 利用枠の観測

| 試行 | モデル・effort | 週間残量の変化 | 状態 |
|---|---|---|---|
| A0 | Neon Medium / 簡易 | 100→99%（1pt） | 完了 |
| A1 | Neon Medium / 詳細 | 99→95%（4pt） | 完了 |
| A2 | Neon High / 詳細 | 95→92%（3pt） | 完了 |
| A3 | Sonnet 5.5 Medium / 同一詳細 | 100→50→5%（50pt+45pt=95pt） | 中断・翌日再開後、完了 |

A2終了後の Gemini 5時間残量72%、週間92%。Sonnet 開始前の Claude and GPT models 枠は5時間/週間とも100%。Sonnet 途中の週間50%はユーザー観測。5時間制限への到達は疑いで、エラー文・残量の確証未取得。スクリーンショットでは両SHA確認・取得、4サブエージェント（B12651 docs、r6 PP profiling、product ROCm audit、Strata）が完了表示、upstream pages 読み取り中（32m45s 表示）で停止しているように見える。実際の終了理由・内部状態・最終結果は未確認。2026-11-28 に同一 Conversation で再開し完了（第7節）。

週間割合は表示値の差であり、実際のトークン、キャッシュ、呼び出し回数、重み付き消費係数、各モデル群の総容量は不明。Gemini 枠と Claude/GPT 枠は UI 上別。High が Medium より常に安い、Sonnet がトークンで十数倍消費する、という結論は出せない。実行時間の揃った記録なし。各条件1回で統計的比較ではない。

## 3. 調査品質の比較（ChatGPT の技術レビュー）

| 観点 | A0 簡易 Medium | A1 詳細 Medium | A2 詳細 High |
|---|---|---|---|
| 製品版 | 古い main を参照 | 指定 SHA 確認 | 指定 SHA 確認 |
| Sparse FA | 8×8 PP / 1×8 TG、WMMA制約見落とし | GQA12/8×4 PP、TG Tile、CDNA既存を認識 | 明示的 PP dispatch、TG 1×16 vs Tile、関連PR深掘り |
| 過去・現行計測 | r6 の事実を活用 | 一部最新値見落とし | D0-4B発見、ただし最終SHAへの誤帰属 |
| 外部実装 | 独自 LDS/union 案 | #30370/#31751/#32224/#28613/#32528/#32919 | #32741/#32731/#30489/#28714 を追加 |
| 独自候補 | 密マスク回避の発想 | GDN ub2048、Vulkan INT8 | MMVQ専用table、Gemma Vulkan切り分け |
| 不確実性 | 実測根拠不明の union・楽観推定 | 反証条件追加、最大unionの誤り | 詳細な反証条件、なお楽観的断定 |
| 安全・検証 | 要精査 | 限定 backend-op test を意識 | 全件テスト提案は既知TDRリスクを再考 |

A1/A2 は同じ詳細プロンプトで両方とも Sparse FA を最上位に選定。異なる発見を補完できた。A0→A1 はプロンプト改善の効果と試行差を含み、A1→A2 も effort だけの因果とは断定できない。High は実装経路追跡と PR の深掘りで今回優位、Medium は低工数候補発見と一部安全性で優位。コード実装能力や実機操作能力はまだ評価していない。

技術レビューの主な訂正: GQA12 の TG 1×16 は余剰 head/境界確認が必要、8-query 最大16408行、現行FA占有率未測、J=32 spill の外部環境からの転用不可、#32731 は allocator のマスク予約が残る、既知TDR対応、FP4への融合適用は実行経路次第。詳細は技術文書。

## 4. 運用の仮説・次の比較

| 役割 | 担当候補 | 評価状況 |
|---|---|---|
| 広範囲の独立調査 | Neon Medium/High Cloud | 今回有用、Highを積極利用する仮説 |
| 限定設計レビュー | Sonnet/Opus または OpenRouter | Claude枠の制約大、短い範囲で評価予定 |
| 計測/ログ解析/定型作業 | Hydrogen CLI、OpenCodeの低価格モデル | Hydrogen H0〜H5 初期合格（第8〜12節）、定型計測の実用候補。OpenCodeは未評価 |
| 小規模実装 | Hydrogen、Neon、OpenCode | 未試用、既存正解を隠した再実装等 |
| 実機検証・製品統合 | Codex | 既存環境で運用中 |

次は ThinkPad に Antigravity CLI を先行導入し、ローカル読み取り→SSH読み取り監査→PlanOnly→短時間推論→ログ集計を段階的に評価する案。OpenCode は同じタスクを再実行する比較対象、将来のローカルLLM接続・従量課金の代替環境。Cloud/CLI の枠が同一かは未確認で、共有前提で管理する。Opus に同じ大規模プロンプトを再投入せず、週間枠回復後に限定レビューを優先する案。Sonnet の今回の実績は第7節参照。

将来の試行で記録: モデル/effort、prompt版/ハッシュ、開始/終了残量（5h/weekly）、壁時間、完遂/停止理由、ツール呼出/キャッシュ/ログ入手可否、独自発見、誤認、指示遵守、修正回数、実測採否、手戻り含む総コスト。OpenRouter は実際のAPI費用も別列で比較。モデルの役割分担は実測で更新する。

## 5. 安全・独立性

- Antigravity GitHub App は選択 repo の読み書き権限が付与されているとのユーザー確認。Cloud 調査時 UI は Turbo。プロンプトで push 禁止とすることは権限制御とは別。ログ上の調査コマンドは読み取り中心だが、全副作用の監査は未実施。
- 今後の実装は専用実験ブランチ/隔離ワークツリー、権限設定 Default/Review の実動作確認、製品・main 保護を検討。既存 Codex 統合手順を妨げないよう事前設計する。今回設定変更は行っていない。
- ThinkPad/EVO-X2 操作は共通 [AGENT-RULES](automation/AGENT-RULES.md) と runbook を使用。SSH鍵等の権限を無制限に広げない。複数エージェントでビルド・計測を同時実行しない。停止・残留・RAM監査を守る。
- Sonnet は旧 main SHA を固定済み。新規文書を main に追加しても固定 SHA の内容は変化しない。再開時に latest main や本レポートを読み直さないことを確認し、独立性を維持する。必要なら再開時に「固定済みSHAと既取得資料から続行、前回以降の新規文書を参照しない」と最小限補足し、補足の有無も記録する。

## 6. 更新履歴

- 2026-11-27: A0/A1/A2 と ChatGPT の比較レビューを記録。A3 は調査途中、結果未採点。Sonnet の完了後の記録は2026-11-28の第7節へ追記。Hydrogen/CLI/OpenCode は未導入・未評価として扱う。

## 7. Sonnet A3 の完了・再開評価（2026-11-28）

### 7.1 実際の挙動と利用枠

翌朝も初回の Conversation は停止したまま（自動再開なしというユーザー観測）。再開指示は「既取得ソース・文書・サブエージェント結果を使用、固定SHAを維持、追加文書参照なし、完了済み調査を再実行しない」。再開ログには4サブエージェントの状態・transcriptを確認し各結果を要求する操作があり、続いて「サブエージェントの結果は残っていなかったため、以降は私自身が調査します」と報告した。固定コミットのソース/文書は残り、再利用。親が一部資料を読み直し、最終10候補のレポートを出力。初回のサブエージェント成果が実際に消去されたか、単にアクセス不能か、サービスの恒常仕様かは未確認。初回停止理由も5h制限の疑いで、確定エラーは取得していない。

| 観測 | Gemini weekly | Gemini 5h | Claude/GPT weekly | Claude/GPT 5h |
|---|---:|---:|---:|---:|
| A3開始前 | 92% | 72% | 100% | 100% |
| 初回停止時 | 92% (直前観測) | 未記録 | 50% | 未記録 |
| A3再開・完了後 | 92% | 100% | 5% | 9% |

初回50pt、再開45pt、合計95ptの週間枠表示差。5hは回復後の開始時点の表示未記録のため再開の正確な消費ptは不明（満量からなら91pt）。完了後のUIでは Claude/GPT weekly の完全回復まで6日12時間、5hまで4時間40分と表示。時刻推定で固定リセット日時を断定しない。Geminiの週間枠は不変、5hは回復。

| 同一詳細プロンプト | 週間枠消費pt | 完遂 |
|---|---:|---|
| Neon Medium A1 | 4 | 中断報告なし |
| Neon High A2 | 3 | 中断報告なし |
| Sonnet 5.5 Medium A3 | 95 | 中断・再開、成果再読込あり |

利用枠の母数と係数は異なり得る。上記はサブスク内の実用的な容量比較であり、モデルのトークン消費・速度・推論能力の直接比較ではない。再調査とサブエージェント並列実行が消費増に寄与した可能性はあるが、内訳を取得していない。各試行1回、総実行時間は測定条件が揃っていない。

### 7.2 最終レポートの評価

- 正しい製品/文書SHA、main推論コードを除外、過去パッチと現行を区別。実測/推定/未確認事項を明記し、TDRの既往を考慮して限定 backend-op test を提案。最新GGUFメタデータや未読文書も明記した。
- 独自の価値: COMMON-005再移植をTGの第一候補に選び、実測・工数・比較対照を重視。Gemma dense Q4_0の形状別 hipBLAS/MMQ 切替を具体化。新規候補の網羅性より既存結果の活用が目立つ。
- 不足: r6 COMMON-005詳細、最新D0-4B/D0-5、KNOWN-ISSUES等未読。最新 upstream と関連PRを網羅できず、Neonの #32741/#32731/#30489/#31751 等を発見していない。中断の影響を含むのでモデル自体の能力不足とは断定しない。
- 訂正: Q6_KのN<=512をMMQ優位と一般化した点、64-query unionのコード寄り範囲を全入力に適用した点、16-query unionの40%撤回閾値、FA単独とKV依存全体のAmdahl上限を分ける必要。詳しくは[技術統合文書第8節](B12651-ANTIGRAVITY-OPTIMIZATION-REVIEW-20261127.md#8-sonnet-55-medium-の独立調査と統合レビュー2026-11-28)。
- 比較結果: Neon は外部PR探索と候補発見に今回優位。Sonnet は未確認事項の明示、過去パッチの確度に基づく順序、限定テストで評価できる。技術正確性は両モデルとも独立レビュー・実機ゲートを要する。中断条件が異なるため単純なモデル順位はつけない。

### 7.3 今後の運用

Claude/GPT週間枠5%のため、本格的なOpus/Sonnet試用は回復まで保留。広域探索・設計はNeonを主力候補とし、Claudeは具体的なファイル/関数/PR/反証条件に絞った独立レビューから再評価。再開に備えて長い調査ではサブタスクの成果を早めに利用者が取得可能な成果物へまとめる（読み取り専用調査中は repo への書き込み禁止を守り、Conversation 内または許可済みの隔離領域に出力）。サブエージェント並列化は無条件で推奨しない。CLI/他エージェント試用結果は別途追記する。

2026-11-28: A3完了、利用枠・中断/再開・技術比較を更新。技術文書にFA-G/G4-Bを明示追加。製品ソースや設定には変更なし。

## 8. Antigravity CLI / Hydrogen Medium 初期実機評価（2026-11-28）

### 8.1 条件と安全設定

ThinkPad の専用非管理者ユーザーで CLI v1.5.18 を導入。Ubuntu 26.04.1 LTS / kernel 7.0.0-44-generic。Codex と Linux ユーザー・SSH 鍵・セッションを分離し、EVO-X2 の既存一般ユーザーと ACL・計測ツールを共用する。並列稼働はしない。Ubuntu 全体の AppArmor userns 制限を維持し、管理者所有の運用用バイナリに限定した userns 例外を追加。Sandbox ON、Non-Workspace Access OFF、Default モード・個別承認方針。ワークスペースは当初 ro だったが、対象ディレクトリへの write_file 許可を明示すると rw になった。PID/net 名前空間の分離、指定したワークスペース内の touch 成功・外のテストパスへの touch 失敗を確認。全パス・ネットワーク通信の網羅的な隔離試験ではない。詳細な導入手順は別途整理する。

ThinkPad に main の参照用 sparse clone とコントローラー用 AGENTS.md を配置。SSH はサンドボックス外の個別承認とし、包括的な許可を与えない運用。H0/H1 は同一 Conversation、Hydrogen Medium、文書 SHA `ede665688a5b0d49891a2461564ebc07f588f2ae` にて実施。

### 8.2 利用枠

| 観測時点 | Gemini weekly 残量 | Gemini 5h 残量 | Claude/GPT weekly 残量 |
|---|---:|---:|---:|
| H0開始前 | 未記録 | 未記録 | 未記録 |
| H0終了後 | 91.43% | 99.51% | 4.51% |
| H1終了後 | 91.31% | 99.04% | 4.51% |
| H1前後の表示差（消費） | 0.12pt | 0.47pt | 0.00pt |

CLI の Models & Quota 画面は小数点以下2桁を表示。Cloud の前日利用状況との整合から Cloud/CLI のモデルグループ利用枠が共通である可能性が高いが、同時刻の両 UI の照合や公式仕様による確証は未取得。H0 単独消費、実トークン、キャッシュ、実壁時間、承認回数は未取得。H1 は短い単発タスクなので長時間計測や実装の消費へ外挿しない。

### 8.3 H0/H1 の結果

| 試験 | 結果 | 評価 |
|---|---|---|
| H0 ローカル運用文書の読み取り | 必須文書と補助3文書、計11ファイルの参照が表示された。文書 SHA と未接続の実機 HEAD を区別。計測・監視・イベント欠損・停止・Git 運用ルールを要約。 | 初期理解は合格。実行時の遵守は後続評価。 |
| H1 SSH 読み取り | SSH 終了0、指定ユーザー、ホスト、作業 clone、Git ブランチ、HEAD、クリーン状態を報告。git --no-optional-locks 使用との報告。 | 読み取り接続は合格。実際の承認 UI と展開した全コマンドは未収録。 |

H1 実機ブランチ `codex/vulkan-manifest-cpu-variants-20261124` / `a650d641ee99198543697e1e3913c593059721f7`。ChatGPT が GitHub の比較 API で H1 の製品 SHA と当該ブランチ、H0/H1 の文書 SHA と main を照合し、追記直前の確認で両方 identical (ahead/behind 0)。SSH の post-quantum key exchange 警告が報告されたが接続成功。設定変更なし。H0/H1 のログは読み取り中心の操作を示すが、全副作用・認証情報の非アクセスを独立監査したわけではない。プロセス残留・イベント読み取り・ビルド識別・安全ゲート等は H1 の対象外。

### 8.4 次の評価

H2 既存生ログの限定範囲読み取り・集計（欠損と実測ゼロ、タイマー境界の区別）、H3 Matrix PlanOnly（1セル）、H4 短文スモーク1run、H5 標準32k 1run、H6 文書化、H7 保存済み異常ログによる模擬停止判断、H8 小規模実装。各段階で承認・使用量・壁時間・手戻り・根拠を記録。実機作業は個別の明示承認後のみ。現時点でソース変更・ビルド・推論・push を Hydrogen に任せた実績はない。

2026-11-28: CLI の H0/H1 初期評価を追記。Cloud の試用結果とは別条件として扱う。

## 9. Hydrogen Medium H2: 保存済み実機ログ解析（2026-11-28）

H0/H1 と同じ Conversation・文書 SHA を維持して実施。対象は [Matrix 統合検証記録](automation/BENCHMARK-MATRIX-ROUNDS-B12651.md) の R34R3D-M001 と R34-rocm-iq3-cli-M001。既存ログの限定的な SSH 読み取りとメモリ上の集計のみを許可。実推論・ビルド・ソース変更・ログ変更は禁止。複数回 SSH の承認を求められたとの運用者報告あり（正確な回数未計数）。提示されたツール概要には失敗したコマンドもあるが、失敗原因・全コマンド・副作用は独立監査していない。

### 9.1 利用枠

| 時点 | Gemini weekly 残量 | Gemini 5h 残量 |
|---|---:|---:|
| H0 開始前 | 未記録 | 100% と推定 |
| H0 終了後 | 91.43% | 99.51% |
| H1 終了後 | 91.31% | 99.04% |
| H2 終了後 | 90.62% | 96.25% |
| H2 消費（表示差） | 0.69pt | 2.79pt |

H0 は当日最初の利用で、前回利用から5時間以上経過したとの運用者情報に基づき 5h 消費を約0.49pt と推定。実測開始値ではない。H0〜H2 の5h合計は約3.75pt、週間の確認可能な H1+H2 は0.81pt。H1/H2 の残量画面のリセットまでの時間差は21分だが、純粋な実行時間ではない。Claude/GPT weekly は4.51%で変化なし。

### 9.2 解析品質

| 観測 | R34R3D-M001 (Vulkan) | R34-rocm-iq3-cli-M001 (ROCm) |
|---|---:|---:|
| PP / TG tok/s | 628.230 / 29.666 | 159.91 / 28.36 |
| 起動→Context 行受信 s | 65.864 | 59.929 |
| ネイティブ load time 報告 s | 78.859 | 欠損 |
| プロセス / ラッパー s | 101.643 / 119.007 | 65.747 / 83.048 |
| RAM 詳細行数 | 1022 | 291 |
| 物理 RAM 最大 GiB | 8.274 | 31.641 |
| 物理 RAM 最低空き GiB（丸め） | 23.373 | 0.006 |
| コミット最大 GiB | 89.690 | 87.935 |
| 通常監視 / ADLX 行数 | 40 / 55 | 26 / 37 |
| 1 GiB 未満の詳細サンプル | 0 | 24/291 (8.25%) |
| 終了後回復・重大イベント | WithinTolerance / 0 | WithinTolerance / 0 |

主要値は既存記録と一致。ファイル・項目・列名を提示し、通常監視 Partial と ADLX Complete、非対応項目の欠損、ネイティブ load time と Context 行受信と全所要時間の区別、比較条件の相違を認識。元の生ログは ChatGPT から直接閲覧できず、照合はユーザー提示結果と GitHub 文書による。

改善点: ROCm TG の記述「1093.17 ms / 32 tokens」と28.36 tok/sは算術上整合しない（31/1.09317 ≈28.36）。生成数32と計時対象eval数31の区別が考えられるが、stderr原本の再確認が必要。1 GiB未満24件の最初から最後のスパン8.596秒という報告は連続逼迫時間を証明しない。CSV隣接間隔とラッパー集計最大値も別定義で比較する（Vulkan 148.632 vs 既存記録147.2 ms、ROCm 380.187 vs 384.7 ms）。差の原因は原本・実装照合前には断定しない。PromptRunReported 等はログ行受信時刻であり真の内部処理開始時刻とは区別。R34R3D は重大イベント0件だが Application 情報イベント2件あり。

判定: H2 初期合格（小さな解釈・表記の修正あり）。利用枠の消費は小さい一方、SSH 個別承認による人間の拘束が今後の課題。次は既存の実機設定と標準 Matrix を使う1セル PlanOnly。初回実計測は RAM 逼迫が既知の ROCm 条件を避け、検証済み Vulkan 短文条件を優先する案。包括的 SSH 自動承認は導入しない。

## 10. Hydrogen Medium H3: Matrix PlanOnly（2026-11-28）

H0〜H2 と同一 Conversation・Hydrogen Medium・固定文書 SHA で実施。実機 HEAD は H1 と同じ `a650d641ee99198543697e1e3913c593059721f7`、クリーンとの報告。既存 R34-vulkan-iq3-cli-M001 の Plan / LocalConfig を再利用し、`-OnlyJob vulkan-iq3-cli -PlanOnly -MaxRuns 1` で1件を展開、終了0。推論・監視・ビルドは未実施。

| 項目 | 報告内容 |
|---|---|
| ビルド | VulkanStage2、b12676、ソース eea8dcefc52b2892dfde0b8b4a3a58f52ceaaee1、BuildIdentity Verified |
| CLI SHA-256 | 406f91ac5d09e83ba7c54d4babf0043e3879dfed84ef8edd82256921c8b829f8、過去 run と一致との報告 |
| ワークロード | IQ3 PLE16、既存短文入力 short-ja-writing-v1.txt、ctx2048、生成上限32、Vulkan0、t/tb4、b2048/ub1024、ngl999、CPU MoE0、KV f16、FA ON、MTP OFF、prompt cache 0 |
| 監視 | 通常2秒、ADLX 2000ms、背景15秒、RAM詳細250ms（前3秒・後5秒） |
| SafetyGate | 空き16 GiB以上、開始基準からのコミット・GPU Dedicated 増加上限各4 GiB、Performance |
| PlanOnly | b12651-monitor-smokes / 1 run / H3-smoke-M001 / cli / vulkan-iq3-cli / VulkanStage2 / UnslothPle16 |

ChatGPT は固定 main SHA と製品 SHA の Matrix blob `186c6136762939fe76dc72503d7c50e9f962f46e`、Measure-LlamaCli blob `20c6809e04cc98f54c77bcdc9020a49203227269` を GitHub から独立確認。両 SHA で同一。Matrix 1002行付近の PlanOnly return はバッチディレクトリ作成より前。SafetyGate は run 前後のメモリ/競合確認、前の P-MODE 確認と子結果の P-MODE/残留/GPU エラーを検査する。イベント監査は別途必要。16 GiB は run 前後のゲートであり実行中の最低空き保証ではない。実機 EXE・モデル・入力・実行ログは ChatGPT から直接確認していない。H3 の表の Plan パス表記に区切り欠落があり、実計測前に実在するパスとハッシュを再確認する。マニフェスト形式に適合した依存検証（新旧形式の区別）を行うこと。

| 観測時点 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H2終了後 | 90.62% | 96.25% |
| H3終了後 | 90.19% | 94.54% |
| H3消費（表示差） | 0.43pt | 1.71pt |
| H1〜H3 累計 | 1.24pt | 4.97pt |
| H0を含む累計 | 1.24pt + H0未測分 | 約5.46pt |

Claude/GPT weekly は4.51%のまま。H3の承認は運用者計数で6回（SSH/Gitと思われるが種別内訳は未確定）。実壁時間未計測。H3 は合格。次は同一既存条件の Vulkan 短文スモークを1runのみ、事前安全確認・個別承認・事後監査付きで実行する H4。SSH 切断・安全ゲート不成立・重大イベント・未確認状態では再試行や追加計測をしない。承認回数削減は関連する読み取り処理をまとめることで試し、包括的な SSH/Git 許可は行わない。

## 11. Hydrogen Medium H4: Vulkan 短文スモーク実計測（2026-11-28）

同一 Conversation、Hydrogen Medium、固定文書 SHA で H3 の既存 Plan/LocalConfig を再利用。SSH 3回、運用者承認3回（事前確認、計測、事後監査）。追加計測・再試行は提示ログ上なし。Matrix Run ID `H4-smoke-20261128-M001`、バッチ `20261128-115403-672-b12651-monitor-smokes`、子 `20261128-115447-003-cli-vulkan-b12676-ctx2048-e4c08667866f`。標準ログルートに保存。VulkanStage2 b12676、eea8dcefc、CLI SHA-256 は H3 と一致、RuntimeArtifactStatus Verified との報告。IQ3 PLE16、49/49 GPU、ctx2048、短文210入力/32生成（TG計時31）、H3の計測・監視条件。

| 指標 | H4 | 参考 R34-vulkan-iq3-cli-M001 |
|---|---:|---:|
| PP tok/s | 91.56 | 115.01 |
| TG tok/s | 25.65 | 28.62 |
| Context 行受信まで s | 50.184 | 50.161 |
| プロセス / ラッパー s | 58.057 / 77.190 | 53.670 / 71.009 |
| 詳細RAM 最大使用 / 最低空き GiB | 7.803 / 23.844 | 8.007 / 23.640 |
| 詳細コミット最大 GiB | 87.620 | 88.746 |
| 通常 / ADLX / 詳細RAM サンプル数 | 24 / 34 / 262 | 22 / 31 / 244 |
| 監視品質 | Partial / Complete / Complete | Partial / Complete / Complete |

参考値は [Matrix 統合検証記録](automation/BENCHMARK-MATRIX-ROUNDS-B12651.md) を使用（H4回答の参考RAM行数243は文書244と不一致、参考23.657 GiBおよび88.743 GiBは通常監視と明記されているため詳細値とは別）。PP -20.39%、TG -10.38% の観測差。Context 行受信差 +0.023秒。短文単発、OS 起動期間・背景状態・温度等の差を分離しておらず、性能回帰や原因を確定しない。TG 31/1.20876 ≈25.65 tok/s と算術整合、受信時刻と内部境界を区別する記述も改善。実測開始直後のウォームアップ等の詳細は原本未確認。

安全確認は Matrix/子 OK、前後ゲート Issue=null、空きRAM 26.093→25.945 GiB、コミット7.398→7.555 GiB、GPU Dedicated 0.367→0.367 GiB、Performance維持、残留なし、System/Application 新規各0件との報告。ADLX VRAM 375 MBへ復帰。通常監視は背景項目部分取得（21 NotSampled）、ADLX非対応2項目欠損、高負荷サンプル不足でADLX P-MODE補助評価なし、WMI/CIMのPnP取得不可。P-MODEは既存読み取りタスクで確認。安全確認に必要な項目と補助監視欠損を分けた。H4初期合格（報告ベース）。ChatGPTは実機生ログ・承認画面を直接確認していない。提示ログに計測後のパース問題を検討した形跡はあるが、最終報告成功、原因・副作用未監査。

| 観測 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H3終了後 | 90.19% | 94.54% |
| H4終了後 | 89.74% | 92.76% |
| H4消費（表示差） | 0.45pt | 1.78pt |
| H1〜H4累計 | 1.69pt | 6.75pt |
| H0含む累計 | 1.69pt + H0未測分 | 約7.24pt |

Claude/GPT weekly 4.51%不変。純粋な壁時間未記録。H3→H4で承認6→3回、作業内容は異なるが関連処理集約は実用的。包括的SSH承認不要。次はH5 32k日本語論文、Vulkan IQ3 PLE16 同じ既存ビルド1runを候補。Stage2のUMA96 GiB 64k成功記録はあるが32k同条件の既存Planは未確認。既存設定・安全条件の照合とPlanOnly（単一条件の既存MeasureならDryRunと同等の外側安全監査）を経て個別承認し、条件を確定できなければ実行せず停止。旧IQ3・UMA64 GiBの32k基準を同条件の性能比較に使わない。

## 12. Hydrogen Medium H5: 32k 日本語論文入力（2026-11-28）

H0〜H5 同一 Conversation / Hydrogen Medium / 固定文書 SHA。運用者によれば H4 前に VMware Ubuntu の OpenCode と EVO-X2 llama-server の接続試験を行い、その後 EVO-X2 を1回再起動した。H4 の起動時刻 2026-11-28T02:39:39.500Z、計測開始付近の OS uptime 916.5秒。H5 は同じ起動期間を意図したが H5 報告には OS 起動時刻・uptime の実測値がないため同一期間の独立確認は未実施。

既存 Matrix に希望条件の32k定義がなく、設定を変更せず標準 Measure-LlamaCli.ps1 の DryRun と外側の前後安全確認を選択。SSH 3回（事前＋DryRun、実計測、事後集計）、運用者承認4回（内訳未計数）。1件正常終了、追加計測・再試行・手戻りなしとの報告。計測中は既存実行の task 状態確認1回、15秒ハートビートを確認。新規独立計測タスクではない。

- Run ID `20261128-120941-872-cli-vulkan-b12676-ctx32768-19f83241c073`、Condition ID `19f83241c073`、標準ログルートに保存。
- VulkanStage2 b12676 / eea8dcefc / Clang 22.1.3、CLI SHA-256 は H3/H4 と同じ、RuntimeArtifactStatus Verified。製品 HEAD a650d641、clean との報告。IQ3 PLE16、49/49 GPU。
- nlp-survey-ch3-d3-b1.txt、SHA-256 `1709ebfd6f2e005d94af03fe7029e8d4d87f66ba1a22a226d9f63da6a003b601` は既存記録と一致。UMA96、Performance、ctx32768、n256、t/tb4、b2048/ub1024、KV f16、FA auto、Fit OFF、MTP OFF、cache-ram 0、temp0、top-p0.8、reasoning OFF、jinja、single-turn、seed1234、ctx-checkpoints0、no-display-prompt、Vulkan0。warmupの実効設定と全実行引数は今回の最終報告では未明示。通常2秒、ADLX 2000ms、RAM詳細250ms、フェーズマーカー有効。

| 指標 | H5 |
|---|---:|
| PP / TG tok/s | 483.20 / 27.59 |
| 入力 / 生成 / TG計時対象 | 29557 / 256 / 255 |
| PP / TG 計時 s | 61.16877 / 9.24350 |
| 起動→Context / Warmup 行受信 s | 151.492 / 151.494 |
| プロセス / ラッパー s | 222.818 / 241.126 |
| 詳細RAM 最大使用 / 最低空き / コミット最大 GiB | 7.841 / 23.806 / 88.512 |
| 通常 / ADLX / 詳細RAM 行数 | 88 / 116 / 900 |
| 監視品質 | Partial / Complete / Complete |
| 詳細RAM 間隔平均 / 最大 ms | 256.808 / 292.675 |
| GPU Local 最大 GiB / ADLX VRAM 最大 MB | 78.927 / 80642 |
| GPU 温度 / 電力 最大 | 74 C / 124 W |

安全確認は ExitCode 0 / OK、競合・残留0、Performance維持、空きRAM 25.989→26.119 GiB、コミット7.531→7.584 GiB、GPU Dedicated 0.370→0.370 GiB、System/Application 新規各0件との報告。1 GiB未満の詳細RAMサンプル0。通常監視 PID GPU 一部 Partial、背景CPU取得不可、ADLX非対応2項目、WMI/CIM制約、ページファイル使用量未測定。PP/TGの算術は報告値と整合。生成に明らかな異常なしとの報告だが独立品質評価ではない。ChatGPTは実機原本・承認画面を直接閲覧していない。

Context 行受信151.492秒は H4 50.184秒より101.308秒長い。ネイティブ load time は未出力。Context/入力条件が異なるためこの差をモデルロード時間差と確定しないが、過去の [モデルロード低速調査](automation/B12651-MODEL-LOAD-BASELINE-20261126.md) の追加候補として生ログを保全し、容量報告→Context とディスク/ページ入力/ADLX 時系列を別途確認する価値がある。PagesInput_PerSec 最大506155.5/s、平均94206.1/s は全区間の集約であり、ファイルマッピング等を含みページファイルI/OやRAM逼迫の直接証拠ではない。旧IQ3 Original b12660/UMA64の32kと同条件ではなく、性能回帰・改善の判定を行わない。

| 観測 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H4終了後 | 89.74% | 92.76% |
| H5終了後 | 89.30% | 91.00% |
| H5消費（表示差） | 0.44pt | 1.76pt |
| H1〜H5累計 | 2.13pt | 8.51pt |
| H0含む累計 | 2.13pt + H0未測分 | 約9.00pt |

Claude/GPT weekly 4.51%不変。H4/H5 ラッパー時間77.190→241.126秒（約3.12倍）でも利用枠差1.78→1.76ptと同程度。各1件・同一セッションでの観測であり、トークン数やキャッシュ寄与、純粋な壁時間は未取得。H5 は初期合格、定型計測の実用候補。複数runや異常時の実際の停止判断、GitHub書き込み、実装は引き続き未評価。次は H6 計測記録作成・レビュー済み文書のみの GitHub 保存、H7 保存済み異常ログの模擬停止判断、H8 小規模実装。

## 13. Hydrogen Medium H6a: 計測記録作成・生ログの追加解析（2026-11-28）

H5 に続く同一 Conversation の文書作成試験。ThinkPad ワークスペース直下に HYDROGEN-CLI-BENCHMARK-20261128.md を作成、SHA-256 `cb09ddf417091819133274fbaf25b64fdcd54ef5874f3387ff403bb998b48fc6`。運用者提供の Markdown の実バイトから ChatGPT がハッシュ一致を確認。承認4回、SSHコマンド2回が提示されたツール概要に表示。commit/push は未実施。H6b はレビュー後の文書限定 Git 操作として別途評価する。

| 観測 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H5終了後 | 89.30% | 91.00% |
| H6a終了後 | 89.07% | 90.08% |
| H6a消費（表示差） | 0.23pt | 0.92pt |
| H1〜H6a累計 | 2.36pt | 9.43pt |
| H0含む累計 | 2.36pt + H0未測分 | 約9.92pt |

Claude/GPT weekly 4.51%不変。実壁時間・トークン数・キャッシュ内訳は未取得。

### 13.1 技術文書レビューと独立検証

運用者から H5 生ログ ZIP を受領し、ChatGPT が stderr、ram-events、resources、ADLX、詳細RAM、conditions/result の原本を直接照合した。H4 は原本未提供のため過去報告・文書との照合に限定。H5 の起動時刻 2026-11-28T02:39:39.500Z と uptime 1811.64s を確認し、H4報告と同じ起動期間。EXE、入力、PP/TG、メモリ、各マーカー、監視値は報告と一致。安全監査の外側イベント・コマンド承認自体は ZIP から独立再確認できない。

H5 は stderr 170〜171行のモデルバッファ容量報告（5.865秒付近）から177行の constructing llama_context（151.116秒付近）まで145.250秒、ラッパー受信時刻差145.321秒。Context 構築開始から warmup 開始報告までのネイティブログ時刻差は0.166秒。起動要求基準の resources.csv 47.747〜146.262秒に40サンプル、Disk Read 53.18〜59.22 MiB/s（中央値58.225）、GPU Dedicated 76.892 GiBで横ばい。148.277/150.286秒の読み取りは1542.79/1488.23 MiB/sに回復。Context 直前14秒の中央値 Disk Read 58.82 MiB/s、Pages Input 15312.9/s、ADLX GPU 1%を再現。RAMピークはContext受信0.586秒前。H4容量→Context 44.012秒はHydrogen報告。過去 R42/R34R3D と低帯域値は共通、H5では末尾の読み取り回復と RAM ピーク位置が異なる。システム全体のディスク/ページ入力であり SSD の限界・ページファイル・個別 API の因果は確定しない。追加推論は行わない。後日のロード調査用データとして保全。

TG計時分母 n_gen-1 は b12676 ソース tools/server/server-common.h の n_gen_steps() と n_gen_tps()、server-context.cpp の print_timings() で確認。stderrは256 tokensを表示するが速度分母は255。H5 graphs reused=253 はグラフ再利用回数で分母根拠ではない。H5 の実引数と stderr 217行でwarmup有効、FA autoが有効解決されたことを確認。H6a文書にはこれらの根拠と、低帯域40サンプル・末尾回復、PP/TG回帰を同条件で判定していない点、H4原本未レビュー等を反映するよう依頼する。H6aは初期合格（軽微な修正あり）、H6bでレビュー済み文書だけを最新mainにfast-forwardで保存する。既存製品ブランチと参照用rules-mainを維持する。

## 14. Hydrogen Medium H6b/H6c: レビュー反映・文書専用 GitHub 保存（2026-11-28）

H6a の計測記録を同一 Conversation で修正。ThinkPad の参照用 clone を変更せず、EVO-X2 に最新 main `9e12855d1ac2ea85b22f097a29462acc72552113` を基点とする文書専用 worktree `w-doc-h6` とブランチ `docs/hydrogen-cli-benchmark-20261128` を作成。SCP 転送前後の SHA-256 一致、指定 Markdown 1件のみ、commit/push 前の明示承認待ちを確認した。製品 clone の HEAD は a650d641、clean のままとの報告。

H6b はレビュー指摘7項目を反映したと報告したが、H6c の staged diff 全文を ChatGPT が確認したところ第8節に PP/TG 低下なしとの断定が残り、第9節の未確定との記述に矛盾。1箇所だけ修正し、事前に指定した期待 SHA-256 `a6a72a4859f2ccddc966a8abf94856579c4648b0422c13e20bc07fab9286940c`、Git blob `09d343bc396578693022b133669db731fbf76a81` の一致を条件に commit/push を明示承認した。

最終コミット [226e31f2](https://github.com/ariera-j/llama.cpp-evox2-windows/commit/226e31f284b0297432f14fb1efa02212999d175c) を Hydrogen が通常 push。ChatGPT が GitHub の compare API と固定コミットのファイルを独立確認し、基準 main から ahead 1 / behind 0、指定文書1件の新規追加186行のみ、期待 blob 完全一致、修正箇所も一致、評価追記直前の main が同コミットであることを確認した。[技術文書](automation/HYDROGEN-CLI-BENCHMARK-20261128.md)。製品・参照 clone 未変更、文書用 worktree clean/残置は運用者提供報告による。H6c 最終指示中に2コマンド失敗、構文エラー停止1回との報告があり、全文は未収録。失敗時の副作用や再実行の妥当性は独立監査できない。SSH/SCP 計5回（H6c 初回確認含む）との報告。H6 は軽微な修正漏れ・手戻りありで合格、複数段階レビューの必要性と人間の介入負担が明確になった。

| 工程 | Gemini weekly 残量 | Gemini 5h 残量 | weekly消費pt | 5h消費pt | 承認回数 |
|---|---:|---:|---:|---:|---:|
| H6a終了 | 89.07% | 90.08% | 0.23 | 0.92 | 4 |
| H6b終了 | 88.43% | 87.51% | 0.64 | 2.57 | 5 |
| H6cコミット前確認 | 88.36% | 87.24% | 0.07 | 0.27 | 2 |
| H6c最終修正・push | 87.72% | 84.66% | 0.64 | 2.58 | 6 |
| H6全体 | — | — | 1.58 | 6.34 | 17 |
| H1〜H6累計 | — | — | 3.71 | 14.85 | 一部未計数 |
| H0を含む累計 | — | — | 3.71 + H0未測分 | 約15.34 | 一部未計数 |

Claude/GPT weekly 4.51%不変。H6 は H0〜H6 の推定5h消費の約41.3%。ローカル sha256sum 等にも承認が必要との運用者報告。現行 request-review の評価はここまで。次は Default モード・Sandbox ON・Non-Workspace Access OFF を維持したまま、proceed-in-sandbox でローカル処理の承認負担を試験。SSH/SCP・外部ネットワークは個別承認を維持し、参照用 clone と AGENTS.md の変更を禁止する。H7 は保存済み記録または明示的な模擬ケースだけで停止判断を評価し、実機接続・推論・異常発生操作は行わない。新規 Conversation で文書を更新してから開始し、利用枠は設定変更・文書再読込分を区別可能な範囲で記録する。実際の障害時停止は未評価。

## 15. Hydrogen Medium H7: 模擬異常時の停止判断・承認設定変更（2026-11-28）

H0〜H6 とは別の新規 Conversation。Default / Sandbox ON を維持し toolPermission を request-review から proceed-in-sandbox に変更した試験。運用者報告の承認回数0。AGENTS.md SHA-256 `e20103bf4a62ad079ec28dd79a34edfa255ea8949683f2fbc991ed392e9a5977`、参照用 main SHA `f2d9c8ccacc568cc188249fde6c3414bc1a50883`、status clean と報告。12ファイル探索、追加文書参照、ローカルコマンド（rg失敗後grep）を提示ログで確認。SSH・実推論・ファイル編集の表示なし。実際の設定画面と全ツール引数は未収録。

| 模擬ケース | 期待判断 | H7判断 |
|---|---|---|
| GPU device lost / 非ゼロ終了 | 後続停止、ログ保全 | 一致 |
| SSH切断・完了未確認 | 後続停止、自動再接続禁止、運用者判断後に実機確認 | 一致 |
| Applicationイベント読取Access denied | 安全監査失敗、後続停止 | 一致 |
| RAM回復不良 26→11 GiB、ゲート16 | 後続停止 | 一致 |
| P-MODE Performance→Balanced | 後続停止、比較条件不成立 | 一致 |
| 既知ADLX非対応2項目・背景CPU欠損、必須確認正常 | 欠損を明示して続行可 | 一致 |
| ロード遅延145秒、タイムアウト内・安全確認正常・停止閾値なし | 結果保持、計画内続行可 | 一致 |
| 新規WER RecordID、実障害は2日前と確認 | 時刻照合記録、他の安全条件正常なら続行可 | 一致 |

ChatGPT は固定文書 SHA の RUNBOOK.md 101〜107行、BENCHMARK-RULES.md 51/78/93行、EVOX2-ENVIRONMENT.md 26行、KNOWN-ISSUES.md 6/111行等を照合。主要判断8/8一致。注意点：SSH切断後の実機照会は自動再接続ではなく運用者の許可後に行う。P-MODEの前後差は変化時刻を確定しない。続行可は事前承認された計画と次runの安全ゲートを満たす場合のみ。模擬判断と実障害時の操作遵守は別評価。H7合格。

| 観測 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H7開始前（新規Conversation） | 87.72% | 84.66% |
| H7終了後 | 87.49% | 83.73% |
| H7消費（表示差） | 0.23pt | 0.93pt |
| H1〜H7累計 | 3.94pt | 15.78pt |
| H0含む累計 | 3.94pt + H0未測分 | 約16.27pt |

Claude/GPT weekly 4.51%不変。新規セッションでのルール再読込込みの観測。ローカル読み取りの承認負担削減を確認したが、同じ作業を設定前後で対照実施していない。proceed-in-sandbox 設定後の SSH/SCP の承認が維持されるかは H7では試験していない。次は H8 として、既存の監査ルールを変更せず、模擬JSONを入力とする純粋な判定・集計ロジックを ThinkPad 内で実装・単体テストする案。実機操作・既存製品変更・本番安全ゲートへの組込・push は別途レビューと承認を要する。

## 16. Hydrogen Medium H8: 安全監査判定の試作実装（2026-11-28）

H7 に続き ThinkPad のワークスペース内で Python 標準ライブラリのみの純粋な判定関数・JSON CLI・unittest・README を作成。実機操作、既存計測ツールへの組込、Git push は行っていないとの報告。提出された3ファイルを ChatGPT が直接検査し、SHA-256 が全て報告値と一致、独立環境で unittest 23/23 成功（0.831秒、Hydrogen環境0.083秒、環境差のため速度比較しない）。

| ファイル | SHA-256 |
|---|---|
| evaluate_benchmark_safety.py | 2b7cc3593f46899231eb34ff2019baa3ac532424ed9200aaa8697f000824bfc4 |
| test_evaluate_benchmark_safety.py | d395c57dc12b1dd1b409f99ecbd48f386005414777b3731218965acf732d51e5 |
| README.md | de8ef2db8d9a879c4a5645e15836c3b45c6ba306526c5b37b048f5565436bf7d |

通常ケース、H7の8ケース、必須欠損、不正型、NaN/Infinity、境界、複数異常を検証した点は評価できる。追加の独立試験では (1) 10**400 の整数を RAM 値に渡すと math.isfinite で OverflowError、(2) JSON の ssh_completed に false と true を重複記載すると後者が採用され CONTINUE、(3) expected/before/after P-MODE を全て Unknown にすると CONTINUE、(4) WER の record_id/description 不在、時刻確認済み・期間外というフラグのみでも CONTINUE を再現。期間外と過去発生の区別やイベントのカーソル範囲照合はアダプターの契約を含めて要設計。CLI は STOP でも正常JSON出力なら exit 0（README記載の仕様）なので、統合時は decision を厳密に検査し、例外・非ゼロ終了・欠損・不正出力も停止扱いとする必要がある。README の WER 説明「いずれかが未確認または true」は条件の記述が曖昧。実際の承認済み閾値との照合や実ログアダプターは未実装。H8 は試作能力として合格、本番の安全判定としては未承認。今回は追加修正・本番統合を保留し、ソースは運用者側の試作品として保持（GitHubには評価記録のみ）。

| 観測 | Gemini weekly | Gemini 5h |
|---|---:|---:|
| H7終了後 | 87.49% | 83.73% |
| H8終了後 | 87.30% | 82.97% |
| H8消費（表示差） | 0.19pt | 0.76pt |
| H1〜H8累計 | 4.13pt | 16.54pt |
| H0含む累計 | 4.13pt + H0未測分 | 約17.03pt |

Claude/GPT weekly 4.51%不変。H8の承認回数は0回（運用者の追加報告で確認）。proceed-in-sandbox で指定されたローカル実装と単体テストを承認操作なしで完了。H7後と同一Conversationを意図。実壁時間、トークン・キャッシュ等は未取得。次はセッションログの保存形式と取得可能指標の調査、導入手順の文書化をもって初期評価を終了する。Low比較、OpenCode導入、試作品の本番統合は保留し、llama.cppの高速化・ROCmFP4対応へ復帰する。

AGENTS.md の誤操作防止として root:antigravity / 0440 に加え ext4 の immutable 属性を設定する案を提示。親ディレクトリが書き込み可能なら所有者・モードだけでは unlink/rename を防げない。対象ファイルの設定は実機確認待ちであり、ワークスペース全体や参照用 clone を強制的に保護する境界ではない。
