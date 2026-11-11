# R04 段階4（m09）の旧の検査の記録（T-R0316）

作業日: 2026-11-09。対象: `tests/m09-execution-and-ci.sh`（旧の入口、4250行、関数 339 個）。

## 1. 旧の入口の既定と実行結果

- 引数なしの既定は `smoke`（`MODE=${1:-smoke}`、7行目）。`plan.md` 10.1節の既定の欄を確定した。
- 実行結果は次のとおり。

| モード | 終了コード | 所要時間 | 実行時の件数 | 結果 |
| --- | --- | --- | --- | --- |
| `unit` | 0 | 44秒 | 239件（`ok` の行も239件） | `unit: 239 件中 239 件通過` |
| `smoke` | 0 | 119秒 | 11件 | `smoke: 11 件中 11 件通過` |
| `contract` | 未実行 | — | 未確定（静的な項目数は6件） | 利用者の端末と CI だけで実行する（`AGENTS.md` の規則）。ゲートには登録しない |

- smoke の後、`swsc-` 接頭辞のコンテナは残っていない。

## 2. U17（件数のずれ）の扱い

| 数え方 | 値 | 判断 |
| --- | --- | --- |
| 入口のファイルの行数 | 4250 | 件数ではない |
| 仮の数字 227（静的） | — | 今回の数え方では再現できなかった。確定しない |
| 仮の数字 234（`clarify.md`） | — | 出所を確定できなかった。確定しない |
| `unit` の実行時の件数 | 239 | 実測で確定 |
| `smoke` の実行時の件数 | 11 | 実測で確定。静的な `smoke_item` の行数も11件 |
| `contract` の件数 | 未確定 | 利用者の端末とCIで実測する。静的な `contract_item` の行数は6件 |

- U17 は、`unit` と `smoke` が確定した時点で一部解消する。234 と 227 の出所は未解決のまま残す。
- 静的な行数と実行時の件数が違うのは、`smoke_item` と `contract_item` の包みの行から、項目が複数回呼ばれるためである（`plan.md` 6.3節）。

## 3. 信号の検査の一覧（`grep -nE 'kill -(INT|TERM)|signal\.SIG|SIGINT'`、19行）

| 行 | 種類 |
| --- | --- |
| 22、23、27、29 | 冒頭の SIGINT 無視の検査（前面で起動したかの確認） |
| 156 | `kill -TERM "$PPID_PARENT"` |
| 705、706 | 偽の aws の `kill -INT "$PPID"`、`kill -TERM "$PPID"` |
| 1766 | `lib_call` 経由の偽の関数の中の `kill`（`sig-sent` の判定） |
| 1794、1806、1850 | `lib_call` 経由の `kill -INT $$`、`kill -TERM $$` |
| 2131、2136、2137 | Python の `signal`（`SIG_DFL` へ戻す） |
| 3831、3882、3895、3908、3958 | `lib_call` 経由の `kill`（smoke とは別の段の検査） |

## 4. 関数の群（接頭辞ごとの分割表、T-R0317、T-R0318〜T-R0321の入力）

| 群 | 接頭辞 | 関数数 | 移す先の段 |
| --- | --- | --- | --- |
| 群1（静的） | `t_wf_` 19、`t_gate_` 16、`t_mise_` 1、`t_gitleaks_` 4、`t_json_` 1、`t_bats_` 1、`t_run_bats_` 1 | 43 | T-R0318 |
| 群2（文書とCI） | `t_ci_` 1、`t_doc_` 14 | 15 | T-R0319 |
| 群3（unit の実行系、信号を除く） | `t_entry_` 17、`t_test_` 16、`t_runner_` 10、`t_derive_` 10、`t_docker_` 8、`t_collect_` 8、`t_start_` 7、`t_managed_` 6、`t_swsc_` 4、`t_render_` 9、`t_compare_` 9、`t_clean_` 4、`t_wiremock_` 3、`t_template_` 3、`t_production_` 3、`t_fr9*` 3、`t_entrypoint_` 3、`t_client_` 3、`t_squid_` 2、`t_stop_` 2、`t_prepare_` 2、`t_check_` 5、`swsc_stop` 10、`swsc_collect` 6、残りの接頭辞のない関数 | 残り（個別の数は T-R0320 で数える） | T-R0320 |
| 群4（smoke と contract） | `t_smoke_` 2、`t_contract_` 25 | 27 | T-R0321 |
| 信号の検査 | 3章の19行に対応する関数 | 別表 | T-R0322 |

- 合計の関数数は339個。群の数の合計と一致するかは、T-R0317 で数え直して確かめる。

## 5. 自己参照の検査（`plan.md` 11.4節）

`tests/m09-execution-and-ci.sh` の本文を、`grep` や `sed` で読む検査の箇所は次のとおり。

| 行 | 読む対象 | 扱い |
| --- | --- | --- |
| 2007 | 自分の `smoke_item` の並び（`grep -E '^  smoke_item [0-9]+ '`） | 薄い入口に移すと0件になる。読む先を `.bats` へ変える（T-R0349） |
| 2013 | 自分の `contract_item` の並び | 同上 |
| 2019〜2021 | 自分の `unit` の呼び出し位置 | 同上 |
| 3131 | 自分の `json.load(` の数 | 同上 |

- 他の箇所は、ワークフロー、`AGENTS.md`、ゲートの本文を読む。自分の本文は読まない。

## 6. 次の段階への引き継ぎ（完了の記録）

- 群1（43件）、群2（15件）、信号以外（123件と48件）、信号（10件と契約の INT 1件）を、すべて bats へ移した（§7〜§9）。
- 信号の検査は、本体を字句のまま移し、呼び出しだけを `@test` にした（T-R0322）。
- `contract` の件数は、利用者の端末かCIで確定させる。確定までは「未確認」と書く。

## 7. 群1の移行の結果（T-R0318）

- 群1（静的な検査、43件）を `tests/bats/m09-execution-and-ci.bats` へ移した。`@test` の名前は旧の `check` の名前と同じで、順序も同じ。
- 件数: `grep -c '^@test'` は 43。`sh tests/lib/run-bats.sh tests/bats/m09-execution-and-ci.bats unit` は 43 件すべて通過。
- 入口 `tests/m09-execution-and-ci.sh unit` の件数は、旧と同じ 239 件（入口の残り 196 件と、bats の 43 件）。終了コードは 0。
- 入口の変更（最小限）:
  - 群1の関数と `check` の行を外した。`must`、`rc_is`、`gate_has` など、群1と他の群が共有する補助は入口に残した。
  - `M09_LIB_ONLY=1` と `M09_LIB_ROOT` で読み込んだとき、SIGINT の確認と検査の実行を飛ばす。bats の setup が入口を読むため。
  - `run_unit` の最後で、bats の群1を `run-bats.sh` で走らせ、件数を `total` に足す。
- 逸脱: 群1の検査は、入口の `check` の仕組み（サブシェルと作業場所の掃除）ではなく、bats の隔離で実行する。判定は、検査の関数の終了コードで同じく決まる。
- 検証: shellcheck（`-s sh -S style` と `-s bash -S style`）は 0 件。品質ゲートは通過（unit 239 件、smoke 11 件）。
- 残り: 群2（文書とCI、15件）、群3（unit の実行系、信号を除く）、群4（smoke と contract）、信号の検査（T-R0322）は未着手。

## 8. 群2の移行の結果（T-R0319）

- 群2（文書と CI の検査、15件: `t_ci_` 1件、`t_doc_` 14件）を `tests/bats/m09-execution-and-ci.bats` へ移した。`@test` の名前と順序は旧の `check` と同じ。
- 件数: `grep -c '^@test'` は 58（群1の 43 と群2の 15）。
  `sh tests/lib/run-bats.sh tests/bats/m09-execution-and-ci.bats unit` は 58 件すべて通過。
- 入口 `tests/m09-execution-and-ci.sh unit` の件数は 239 件（入口の残り 181 件と、bats の 58 件）。終了コードは 0。
- 群2の本体の中に、入口のファイル名を読む検査（`t_doc_` の1件）がある。
  入口のファイルは残るため、読む先は変わらない。
- 群2の関数が使う `check` と `wf_yq_bin` は、入口を読み込んで使う（群1と同じ方法）。
- 残り: 群3（unit の実行系、信号を除く）、群4（smoke と contract）、信号の検査（T-R0322）。

## 9. 信号以外と信号の検査の移行の結果（T-R0320〜T-R0322）

- 入口の unit の検査 239 件は、すべて `tests/bats/m09-execution-and-ci.bats` の `@test` に移した（239 件、すべて通過）。
- 入口 `tests/m09-execution-and-ci.sh unit` は、bats を1回呼ぶだけになった。件数は bats の 239 件。終了コードは 0。
- 信号の検査（10件）は、本体を字句のまま移した。この移行には、2つの変更を伴う:
  - `tests/lib/run-bats.sh` は、bats を前面で動かす。背景で動かすと、子が SIGINT を無視して始まり、INT の検査（子が 130 で止まること）が通らなかった。
  - 利用者が受け入れた既知のリスク: 入口だけに TERM が届くと、bats は孤児として残る。
- 逸脱（記録）: smoke の実装（11項目）と contract の実装は、入口に残した。m06、m07、m08 と同じ扱い。薄い入口（T-R0323）からの逸脱として、ここで記録する。
- 検証: 品質ゲートは通過（unit 239 件、smoke 11 件）。shellcheck（入口と bats、`run-bats.sh`）は通過。
- 残り: 文書（T-R0324）、対応表（T-R0325）、実行時間の記録（T-R0326）、レビュー（T-R0327）、品質ゲートの最終実行（T-R0328）、commit（T-R0329）。
- 補足（evidence-code-review の指摘）: bats 内の順序は、群2の15件が先頭側に移ったため、旧と完全には同じでない。残りの181件は相対順序が同じ。件数と名前は旧と一致する。

## 10. 対応表と実行時間の最終記録（T-R0325、T-R0326）

### 10.1 モード別の件数と時間

| モード | 旧（段階4の開始時） | 移行後 | 実行時間 | 備考 |
| --- | --- | --- | --- | --- |
| `unit` | 入口の `check` 239 件（旧の時間は44秒、§1） | bats の `@test` 239 件。入口は bats を1回呼ぶ | 約95秒（移行後の実測。入口も bats も同じ値） | 入口の件数と bats の件数は一致する。時間は旧の約2倍（§10.3） |
| `smoke` | 11 件（入口） | 11 件（入口に残す） | 約119秒（1回目）、約168秒（2回目。2回の差の原因は未確認） | `swsc-` の残存はない |
| `contract` | 件数は未確定（静的な項目数は6件） | 入口に残す | 未実行 | 利用者の端末と CI だけで実行する |

### 10.2 件数の対応

- 旧の `check` の名前と、bats の `@test` の名前は、1対1で一致する（群1、群2、信号以外、信号、契約の INT 1件）。
- 順序は、群2の15件が先頭側に移ったため、旧と完全には同じでない。件数と名前は一致する（§8 の補足）。
- 入口に残る件数は 0（unit）。smoke の 11 項目は入口に残る。

### 10.3 残り

- contract の実行（利用者の端末と CI で確かめ、件数と時間を記録する）。
- 薄い入口（T-R0323）は、smoke と contract の実装を入口に残すため、逸脱として記録する（§9）。
- `unit` の時間は、旧の約44秒から約95秒に増えた。原因は未確認（bats の起動と検査ごとの隔離のコストと推定するが、計測していない）。
  `docs/ローカル実行とCI.md` の基準（上限の半分の90秒）を超えるため、次の CI の実測で確かめ、必要なら原因を調べる。
- 品質ゲートは、この記録の時点（commit `61fa050`）で通過している。

## 11. 利用者の端末での確認（macOS、bash 3.2）の手順

この手順は、CI（Linux）では確認できない項目を、利用者の端末で確かめるための記録である。結果は、この表の「結果」の列に書き込む。

| 順序 | 実行するコマンド（リポジトリのルートで） | 期待する結果 | 結果 |
| --- | --- | --- | --- |
| 1 | `/bin/bash --version` | GNU bash 3.2 系が出る | 通過（GNU bash 3.2.57、arm64） |
| 2 | `mise install --locked` | 6つのツール（shellcheck、actionlint、gitleaks、bats、jq、yq）が入り、エラーが出ない | 通過（6 ツールのみ指定。警告のみ: global の `~/.tool-versions` の3件と、actionlint の非推奨） |
| 3 | `sh tests/s14-taskdef-contract.sh unit` | 終了コード 0 | 通過（5/5） |
| 4 | `sh tests/m03-wiremock-scenarios.sh unit` | 終了コード 0 | 通過（6/6） |
| 5 | `sh tests/m06-client-resilience.sh unit` | 終了コード 0（133 件） | 通過（133/133） |
| 6 | `sh tests/m07-scenario-isolation.sh unit` | 終了コード 0（42 件） | 通過（42/42） |
| 7 | `sh tests/m08-e2e-suite.sh unit` | 終了コード 0（20 件） | 通過（20/20） |
| 8 | `sh tests/m09-execution-and-ci.sh unit` | 終了コード 0（239 件） | 通過（239/239） |
| 9 | `env AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test sh tests/m09-execution-and-ci.sh contract`（先に `unset AWS_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN`。実際の認証情報の混在を避けるため） | 終了コード 0。ダミー値の認証情報が前提（実際の認証情報は使わない）。Docker と MiniStack を使うため、Docker が動いていることも前提 | 通過（6/6）。最初は認証情報の前提で止まった。ダミー値（AWS_ACCESS_KEY_ID=test、AWS_SECRET_ACCESS_KEY=test）と unset AWS_PROFILE で再実行 |

- 手順 2 で `mise` が導入されていない場合は、`docs/ローカル実行とCI.md` の導入手順に従う。
- 手順 9 は、利用者の端末だけで行う（品質ゲートには登録しない）。結果を、この表に書き込む。
- 手順 1 から 8 で失敗した項目は、失敗したコマンドと出力の末尾を、この表の下に貼り付ける。
- 確認は済み（手順1〜9、すべて通過。手順9は、ダミー値で再実行した）。
- 作業記録の commit は、レビューの後に行う。

## 12. 移行の検査（T-R0345〜T-R0349）の結果

| タスク | 内容 | 結果 |
| --- | --- | --- |
| T-R0345 | m08 の移行の検査 `t_bats_stage3_m08_is_migrated` | 追加した。実際のファイルで通過。偽の用意（`make_fake`）の定義を足した写しで落ちることを確かめた（赤の確認）。入口には、smoke が使う `check` が残るため、検査は `check` を禁じない（段階3で承認した逸脱） |
| T-R0346 | m09 の移行の検査 `t_bats_stage4_m09_is_migrated` | 未完了。入口には、bats の補助として使う `check`、`must`、`rc_is` の定義が残っている。これを外すのは、T-R0323 の設計の作業である。検査を先に足すと赤のまま残るため、今は追加しない |
| T-R0347 | gitleaks の規則の検査 `t_gitleaks_rules_detect_runtime_built_values` | 既にある（群1の移行で bats に入った） |
| T-R0348 | actionlint の式の誤りの検査 `t_actionlint_rejects_expression_error` | 既にある（bats に入っている） |
| T-R0349 | 自己参照の検査の書き換え | 不要。読む先の入口には、smoke と contract の項目（`smoke_item`、`contract_item`）が残るため、検査はそのまま通る |

## 13. T-R0346 の前提（入口の補助関数の移動）の計画

### 13.1 現状（`tests/m09-execution-and-ci.sh`、1399行）

| 補助 | 入口での定義 | 入口での使用 | bats での使用 | 扱い |
| --- | --- | --- | --- | --- |
| `must` | あり | 3 | 482 | 移す |
| `rc_is` | あり | 1 | 12 | 移す |
| `check` | あり | 5 | 14 | 移す（smoke と contract の入口が使う） |
| `lib_call` | あり | 2 | 49 | 移す |
| `run_e2e` | あり | 1 | 7 | 移す |
| `gate_has`、`gate_sources`、`gate_m09_block` | あり | 1 | 4 〜 12 | 移す |
| `wf_yq_bin`、`wf_broken_case` | あり | 1 | 10 〜 19 | 移す |
| `make_base_bin`、`make_fake`、`make_shims`、`no_calls` | なし（`tests/bats/helpers/fakes.bash` にある） | 6 | 4 〜 15 | 変更なし |

- 入口に残る smoke と contract の関数は 17 個ある。これらは移さない（段階4で承認した逸脱）。

### 13.2 方針

1. 補助関数と、それが使う変数（`total`、`failures`、`TMP`、`WF`、`SMOKE_ID_RE` など）を、`tests/bats/helpers/m09-lib.bash` へ移す。定義は字句のまま移す。
2. 入口は、この補助ファイルを `.` で読み込む（`fakes.bash` と同じ作り）。入口の定義は残らない。
3. bats は、補助ファイルを `load` で読む。入口を読み込む必要は、補助の関数については無くなる。
4. 入口に残るのは、smoke と contract の関数、モードの分岐、`run-bats.sh` の呼び出し。
5. T-R0346 の検査（`t_bats_stage4_m09_is_migrated`）を、移動の後に足す。入口に `check`、`must`、`rc_is`、`expect`、`make_fake` の定義が無いことを確かめる。

### 13.3 手順と確認

| 順序 | 作業 | 確認 |
| --- | --- | --- |
| 1 | 補助と変数の一覧を作る（定義の行範囲と、使う変数） | 一覧の件数が 13.1 と合う |
| 2 | 補助ファイルを作り、定義を字句のまま移す。入口は読み込みに置き換える | `sh -n` と shellcheck が通る |
| 3 | bats の setup から、入口の読み込みを補助ファイルの読み込みに変える。残る入口の変数は、移した後に確かめる | bats の 240 件が通る |
| 4 | 入口の unit を実行する | 件数が 240、終了コードが 0 |
| 5 | T-R0346 の検査を足す。赤の確認は、入口に `must` の定義を足した写しで行う | 実際のファイルで通り、写しで落ちる |
| 6 | 記録の件数を更新する。unit は 239 件（T-R0316 の記録）から 240 件（m08 の検査を足した後）になった理由を書く | 記録と実測が一致する |

### 13.4 注意

- 入口の `set -eu` と、読み込み時の副作用（`TMP=`、`total=0`）は、補助ファイルへ移すと挙動が変わる。読み込みの順序を、bats の setup と入口で揃える。
- `check` は、入口に残る smoke と contract が使うため、入口からも読み込む。同じ定義を2か所に持たない。
- 変更は大きい（補助の定義の移動と、読み込みの変更）。段階ごとに commit し、各段階で品質ゲートを通す。
- レビューは、移動の commit ごとに evidence と security を行う。

### 13.5 段階1の結果（補助と変数の一覧）

入口 `tests/m09-execution-and-ci.sh`（1399行）の、補助関数の定義の行範囲。

| 補助 | 行 | 補助 | 行 |
| --- | --- | --- | --- |
| `must` | 51〜56 | `contract_go` | 258〜262 |
| `rc_is` | 59〜65 | `contract_item` | 564〜566 |
| `check` | 68〜84 | `contract_setup` | 239〜243 |
| `run_e2e` | 91〜95 | `contract_run` | 247〜255 |
| `render_local` | 115〜120 | `entry_fakes` | 419〜479 |
| `mutate` | 123〜130 | `entry_run` | 488〜493 |
| `render_production` | 136〜140 | `entry_sandbox` | 159〜171 |
| `check_production` | 142〜144 | `entry_setup` | 482〜485 |
| `derive` | 151〜155 | `runner_docker_args` | 405〜408 |
| `contract_fakes` | 180〜215 | `runner_mutate` | 398〜403 |
| `contract_base` | 219〜236 | `runner_run` | 384〜390 |
| `desc_mutate` | 282〜290 | `runner_setup` | 372〜380 |
| `compare_cli` | 292〜294 | `seq_before` | 270〜274 |
| `compare_mismatch` | 298〜307 | `seq_last_is` | 277〜279 |
| `has_text` | 265〜267 | `seq_line` | 393〜395 |
| `fr920_hits` | 106〜108 | `smoke_item` | 560〜562 |
| `lib_call` | 496〜502 | `managed_setup` | 1306〜1324 |
| `swsc_collect` | 509 | `managed_run` | 1327〜1331 |
| `swsc_stop` | 510〜515 | `lock_case_dir` | 1233〜1239 |
| `swsc_test_run` | 508 | `lock_case_clear` | 1242〜1245 |
| `wf_yq_bin` | 1113〜1117 | `lock_busy_setup` | 1336〜1339 |
| `wf_broken_case` | 1125〜1135 | `t2602_fake_docker` | 1265〜1287 |
| `gate_has` | 1152〜1154 | `t2602_fake_curl` | 1289〜1301 |
| `gate_m09_block` | 1157〜1162 | `contract_c4` | 1055〜1075 |
| `gate_sources` | 1165 | `contract_c6` | 1085〜1101 |

- 入口の先頭の変数: `MODE`（7行）、`TMP`（46行）、`total`（47行）、`failures`（48行）、`CONTRACT_FREE`（311行）、`COLLECT_DEF`（314行）、`CI_FAKES`（507行）、`SMOKE_HOLDER`（556行）、`SMOKE_ID_RE`（558行）、`WF`（1109行）。
- 補助の定義は、入口の先頭から末尾まで散らばっている（51〜1399行）。smoke と contract の関数（17個）と並んでいるため、一括の移動は、補助の定義の行範囲を一つずつ切り出す必要がある。
- 段階2（移動）は、補助ごとに、移動と読み込みの確認を繰り返す。1回の commit に収めない。

### 13.6 段階2の第1区切り（完了）

- 移したもの: `TMP`、`total`、`failures`、`must`、`rc_is`、`check`（入口の44〜84行目）。字句のまま、`tests/bats/helpers/m09-lib.bash` へ移した。
- 入口は、この補助ファイルを `. "$ROOT/tests/bats/helpers/m09-lib.bash"` で読み込む（`fakes.bash` と同じ作り）。
- 確認: 入口の unit は 240 件すべて通過（bats の 240 件を含む）。shellcheck（`sh` と `bash` の方言）は通過。
- 残り: `lib_call`、`run_e2e`、`gate_has` などの補助。`check` を含めた残りの補助は、次の区切りで移す。T-R0346 の検査は、移動が終わってから足す。

### 13.7 段階2の第2区切り（完了）

- 移したもの: `run_e2e`、`lib_call`（それぞれの直前の説明コメントを含む）。`tests/bats/helpers/m09-lib.bash` へ字句のまま移した。
- 確認: 入口の unit は 240 件すべて通過。shellcheck（`sh` の方言）は通過。入口に残る定義は 0。
- 残り: `gate_has`、`gate_sources`、`gate_m09_block`、`wf_yq_bin`、`wf_broken_case`、`mutate`、`contract_*`、
  `entry_*`、`runner_*`、`managed_*`、`lock_*`、`t2602_*` などの補助と、変数
  （`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.8 段階2の第3区切り（完了）

- 移したもの: `wf_yq_bin`、`wf_broken_case`、`gate_has`、`gate_sources`、`gate_m09_block`
  （それぞれの説明コメントを含む）。`tests/bats/helpers/m09-lib.bash` へ字句のまま移した。
- 確認: 入口の unit は 240 件すべて通過。shellcheck（`sh` の方言）は通過。入口に残る定義は 0。
- 残り: `mutate`、`desc_mutate`、`derive`、`runner_*`、`entry_*`、`contract_*`、`managed_*`、`lock_*`、
  `t2602_*`、`render_*`、`check_production`、`compare_*`、`seq_*`、`has_text`、`fr920_hits`、`swsc_*`、
  `smoke_item`。変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.9 段階2の第4区切り（完了）

- 移したもの（14 個）:
  `fr920_hits`、`render_local`、`mutate`、`render_production`、
  `check_production`、`derive`、`has_text`、`seq_before`、
  `seq_last_is`、`seq_line`、`compare_cli`、`compare_mismatch`、
  `desc_mutate`、`runner_mutate`。
- 移し先は `tests/bats/helpers/m09-lib.bash`。定義は字句のまま。
- 確認: 入口の unit は 240 件すべて通過。shellcheck は通過。入口に残る定義は 0。
- 残り: `runner_*`（`runner_setup`、`runner_run`、`runner_docker_args`）、`entry_*`、`contract_*`、`managed_*`、`lock_*`、`t2602_*`、`swsc_*`、`smoke_item`。変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.10 段階2の第5区切り（完了）

- 移したもの（7 個）:
  `runner_setup`、`runner_run`、`runner_docker_args`、
  `entry_sandbox`、`entry_fakes`、`entry_setup`、`entry_run`。
- 移し先は `tests/bats/helpers/m09-lib.bash`。定義は字句のまま。
- 確認: 入口の unit は 240 件すべて通過。shellcheck は通過。入口に残る定義は 0。
- 残り: `contract_*`、`managed_*`、`lock_*`、`t2602_*`、`swsc_*`、`smoke_item`。変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.11 段階2の第6区切り（完了）

- 移したもの（13 個）:
  `contract_fakes`、`contract_base`、`contract_setup`、`contract_run`、
  `contract_go`、`contract_item`、`contract_no_ministack`、
  `contract_c1`、`contract_c2`、`contract_c3`、`contract_c4`、
  `contract_c5`、`contract_c6`。
- 移し先は `tests/bats/helpers/m09-lib.bash`。定義は字句のまま。
- 逸脱（記録）: `contract_c1` から `contract_c6` は、contract モードの検査の実装である。
  段階4で承認した「smoke と contract の実装は入口に残す」からは外れる。
  入口は、この補助ファイルを読んで contract モードを動かす。入口の unit は 240 件すべて通過。
- 残り: `managed_*`、`lock_*`、`t2602_*`、`swsc_*`、`smoke_item`。変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.12 段階2の第7区切り（完了）

- 移したもの（7 個）:
  `managed_setup`、`managed_run`、`lock_case_dir`、
  `lock_case_clear`、`lock_busy_setup`、
  `t2602_fake_docker`、`t2602_fake_curl`。
- 移し先は `tests/bats/helpers/m09-lib.bash`。定義は字句のまま。
- 確認: 入口の unit は 240 件すべて通過。shellcheck は通過。入口に残る定義は 0。
- 残り: `swsc_stop`、`swsc_collect`、`swsc_test_run`（入口の文字列の中の擬似の関数の可能性があるため、後で確かめる）、`smoke_item`。変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）。

### 13.13 段階2の第8区切り（swsc 系の確認と、変数の扱いの決定）

- 確かめた結果: `swsc_stop`、`swsc_collect`、`swsc_test_run` は関数ではない。
  入口の `CI_FAKES` という一重引用符の文字列の中に書かれた、偽の関数の定義である。
  実行時に子の sh で定義されるデータなので、関数として移さない。
- 変数（`MODE`、`CONTRACT_FREE`、`COLLECT_DEF`、`CI_FAKES`、`SMOKE_HOLDER`、`SMOKE_ID_RE`、`WF`）は、
  入口に残す。理由: 入口の関数が読む変数の位置を変えると、字句のまま移す方針を崩すため。
- 前回の試行（区切り 8）は、`CI_FAKES` の 4 行目の `swsc_collect` を外に出し、
  `CI_FAKES` を 3 行にした。この状態で unit は 240 件中 239 件に減った（`test:ci` の 4 件）。
  `CI_FAKES` を元の 4 行に戻して解消した。
- 確認: 入口の unit は 240 件すべて通過。`shellcheck -s sh -S style`（入口）と
  `-s bash -S style`（`m09-lib.bash`）は通過。`sh scripts/quality-gate.sh` は通過
  （unit 240、smoke 11）。
- 残り: 入口に残るのは、`smoke_item` と変数だけ。T-R0346（入口に補助の定義が残らない検査）は、
  変数と `smoke`、`contract` の実装を理由に、次の判断を人に求める。

### 13.14 レビュー後の修正（検査の効き方の修正）

- 発見: `tests/bats/m09-execution-and-ci.bats` の `setup` が `set +eu` で errexit を切っていた。
  その結果、`|| return 1` で失敗した検査が成功扱いになっていた（最小の再現で確認）。
  修正: `set +u` にして -e を残す。
- 同じ修正で表に出た失敗は2件。どちらも `コマンド; rc=$?` の形で、非 0 の終了で止まっていた。
  `|| rc=$?` の形に直した（gitleaks の印の検査、actionlint の式の検査）。
- `t_json_extraction_uses_jq` を、入口と補助（`m09-lib.bash`）の両方を読むように直した。
  補助へ禁止のパターンを一時的に足すと、検査が落ちることを確かめ、元に戻した。
- `m09-lib.bash` の先頭の説明コメントを、`TMP` と `total` と `failures` の説明に直した。
- 確認: bats の unit は 240 件中 240 件通過（2回連続）。
