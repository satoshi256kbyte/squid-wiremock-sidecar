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
