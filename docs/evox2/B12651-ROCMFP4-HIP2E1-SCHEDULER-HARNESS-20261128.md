# HIP-2E-1 ROCmFP4 FAST scheduler 限定数値検証ハーネス

**READY FOR REVIEW（実装・静的検証）**。scheduler 3件の CPU 参照を確認した。Windows でのコンパイル、DLL ロード、scheduler 実配置、転送、SGEMM、GPU 数値は HIP-2E-2 の検証対象である。

## 基準と保全

GitHub origin の main は `57d60df3c2507c1a96c6370a8fba8736ceb906b4`、製品は `a650d641ee99198543697e1e3913c593059721f7`、HIP-2 実験ブランチは `a8b8a6ffd4e74f50de9d9d9a1704c47f38c3f959`。実機の追跡 ref は3件とも一致。専用 clone の HEAD は実験版で作業ツリーは clean。登録 worktree と関連プロセスを確認し、競合する実行は見つからなかった。実験版から `codex/b12651-rocmfp4-hip2e-20261128` を `C:\llama-build\automation\w61` に作成した。変更は未コミット。

固定 main の AGENT-RULES、RUNBOOK、環境・既知問題、HIP-2A/B/C/D と検証計画を参照した。BENCHMARK-RULES の正本パスは `docs/evox2/automation/BENCHMARK-RULES.md`。w60 は同じ実験 SHA の detached worktree。既存テスト DLL の SHA-256 は `CD7D6B380ED7C7B7FA487792FE97A316999C4ED72066E8FB72038783475A3911`。

## 配置と数値の契約

表の値は実行時に要求する値。全件で重みを通常 ROCm0 の WEIGHTS buffer に置き、主演算を1件だけ構築する。演算 backend の期待値は ROCm0。

| ケース | 演算、fixture | activation の元配置 → 主演算の入力 | dst | ID | scheduler の入力転送 | FAST の activation H2D / dst D2H | SGEMM |
|---|---|---|---|---|---:|---|---:|
| S-HC-CPU | MUL_MAT、6 | CPU → ROCm0 | ROCm0 | なし | 1 | 0 / 0 | 1 |
| S-HC-PIN | MUL_MAT、6 | ROCm_Host → 同じ tensor | ROCm_Host | なし | 0 | 1 / 1 | 1 |
| S-ID-PIN | MUL_MAT_ID、8 | ROCm0 → 同じ tensor | ROCm0 | ROCm_Host の親と view | 0 | 0 / 0 | 2 |

軸順は ggml の ne[0..3]、stride は byte 単位。FAST の nb[0] は32要素ブロックのサイズ。

| ケース | tensor | shape | stride | 補足 |
|---|---|---|---|---|
| S-HC 両件 | FAST W | (160,5,1,1) | (17,102,510,510) | root 544 B、view offset 17 B、各行1ブロック padding |
| S-HC 両件 | F32 X | (160,7,1,1) | (4,640,4480,4480) | 4480 B |
| S-HC 両件 | F32 dst | (5,7,1,1) | (4,20,140,140) | 35出力 |
| S-ID-PIN | FAST W | (160,5,4,1) | (17,85,425,1700) | root 1717 B、view offset 0 |
| S-ID-PIN | F32 X | (160,2,3,1) | (4,640,1280,3840) | 3840 B |
| S-ID-PIN | I32 親 / view | (512,3,1,1) / (2,3,1,1) | ともに (4,2048,6144,6144) | 親 6144 B、view offset 0、span 4104 B |
| S-ID-PIN | F32 dst | (5,2,3,1) | (4,20,40,120) | 30出力 |

## scheduler と FAST の観測箇所

1. Windows の DL 構成では Python が指定テスト DLL と同じディレクトリの ggml.dll を開き、公開関数 ggml_backend_load に ggml-cpu.dll の絶対パスを渡す。この loader は score があれば適合性を確認し、初期化後に API version を照合する。専用 export は受領した registry の device 数と CPU 種別を照合し、ggml_backend_dev_init を使う。HIP モジュールから registry DLL や CPU モジュールへの新規リンクは不要。既存 DLL の PE export 表をファイルとして照合した。
2. ggml_backend_sched_new の backend 順は ROCm0、CPU。parallel と op_offload は false。set_tensor_backend は使用しない。CPU 入力と ID のケースでは dst が未割当で、scheduler は重みの配置・演算対応から backend を選べる。pinned 出力のケースでは dst の buffer をハーネスが事前確保し、scheduler がその配置で実行できる最優先 backend を選ぶ。pinned dst を自動選択したという主張はしない。通常 CPU への pinned 確保フォールバックは buffer 型照合で拒否する。
3. alloc_graph 後に dst の backend、全主入力の置換、buffer 型、重みと ID の親・データアドレスを検査する。CPU 入力には INPUT フラグを付ける。split 入力の即時 copy に先立って置換先を 0xff で埋め、scheduler の eval callback で主ノード投入直前に4480 Bすべてを元 fixture と照合する。pinned ケースは元 tensor・buffer の保持も検査する。copy slot 数を返す get_n_copies は使用しない。
4. テスト限定の thread_local カウンタを FAST 内の activation H2D と dst D2H の成功直後に置く。ID 経路では stream 同期後の host memcpy で読取回数・span・pitch を記録する。ID の転送対象 span には行間 padding を含む。expert の選択に使える値は各行の先頭2個だけで、token 順に (2,0), (0,2), (2,2)。残りは -99 とし、active ID として参照すれば Release でも失敗する。内部の index upload や検査用読戻しを activation/dst staging の回数には含めない。
5. 主ノード、view 以外の演算を拒否し、callback 完了1件、自然割当 ROCm0、既存の FAST F32 SGEMM カウンタを GGML_ASSERT で照合する。出力の初期値は NaN。重み root・activation・ID 親の全内容と、ハーネスが確保した各 buffer の前後 guard を再確認する。CPU fallback、非有限出力、経路・件数・guard の不一致は失敗となる。

## CPU 検証

controller と実機の Python で dry enumeration、従来10件の CPU 参照、新規3件の個別 CPU 参照が成功。codec 4096組、ID span 正例1件・負例10件を通過した。dense は FP64 直接内積を独立した行デコード・有理数和で照合。ID は slot ごとの直接内積と expert 別グループ化・逆 scatter の全出力が一致した。GPU 出力の判定は有限な F32 の各要素で |v-ref| ≤ 2Ku/(1-Ku)·Sabs + 1e-7、u=2^-24。

| 対象 | SHA-256 |
|---|---|
| 旧10件の正規化 catalog | `0f5c1cf6b166d57f6c8ed16bc85c3ef6d8a88f10837c09d55655dfd577c6feea` |
| 新13件の正規化 catalog | `5afb7000d94c9bcadba08336d2f4ba3c018a32d36dda53dd8595e7d8cf4b0136` |
| S-HC-CPU FP64参照 | `f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1` |
| S-HC-PIN FP64参照 | `f4077833acd24673fb09faba35108abd645aea44cada551ce354484abc18e8c1` |
| S-ID-PIN FP64参照 | `3a2a7133f050237f341b99e09a71fc42011d60c7d9baacdac9a325c759a86ecb` |

正規化は CASE 行を元の順序で LF 連結し末尾 LF を含めない。行単位、fixture の全要素（入力・参照・許容誤差を含む）、各参照 hash を基準と個別照合し、旧10件はすべて一致した。レビュー用 cpu-reference.txt に個別値を収録。旧 export の名前・引数は維持し、新規3件には CPU registry を受け取る専用 export を設けた。GPU は明示 case ID と DLL を必須とし、case 無指定の reference 対象は旧10件。

## 差分・通常ビルドへの影響

実装4ファイル。ggml/src/ggml-cuda/ggml-cuda.cu +18/-0、tools/evox2/hip2a/cases.inc +3/-0、fixtures.py +39/-5、harness.cpp +174/-6。実装計 +234/-11。全差分には本報告書1件を追加した。汎用 scheduler と依存監査設定の差分は空。ggml-hip/CMakeLists.txt の blob は `b683a1d32fd8cf8e3bf15a788b16b1f2c083bd76`。追加の C++ 計測は GGML_HIP_ROCMFP4_TEST の条件内に収まり、harness は既存の Windows テスト専用 target_sources でのみコンパイルされる。

## HIP-2E-2 案と未検証事項

独立レビュー・別承認後の固定 SHA に対し、w60 と異なる未使用先で offline preflight、Windows Release テスト版ビルド、依存・manifest・PE export・DLL hash を確認する。DL 構成、実機の pinned 確保、実コピー、host 同期読取、staging、GPU 数値はこの段階で初めて確認できる。実行例は `fixtures.py gpu --case S-HC-CPU --dll <新テストDLLの絶対パス>`。S-HC-PIN、S-ID-PIN もそれぞれ別プロセス、直列1 worker、ROCm0、各60秒上限で実行する。各ケースの経路ログ、CPU 参照判定、終了コード、終了後プロセス・資源・イベントを保存し、不一致または timeout で停止する。
