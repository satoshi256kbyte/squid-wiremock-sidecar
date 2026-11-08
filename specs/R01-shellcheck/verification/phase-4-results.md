# R01 フェーズ4 検証結果

フェーズ4（品質ゲートの置き換えとCI。T-R0131〜T-R0141、T-R0153、T-R0154）の結果を記録する。
実装は実装サブエージェント（Claude Haiku 5.5）が4回の依頼（D1: テストを赤にする、D2: ゲートとワークフロー、D3: レビュー指摘の修正、D4: セキュリティ指摘の修正）で行った。差分の確認、検証、レビューの取りまとめはメインエージェントが行った。
実行環境はLinux aarch64の2コアのEC2（2026-11-08）である。AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 変更の範囲

| ファイル | 内容 |
| --- | --- |
| `scripts/quality-gate.sh` | `sh -n`のループを`shellcheck_gate`に置き換えた。`mise current`、`mise which`、版の比較、`git ls-files -z -co --exclude-standard '*.sh'`の一時ファイル、`xargs -0 ... --`、`trap`（EXIT、INT、TERM） |
| `.github/workflows/e2e-test.yml` | `jdx/mise-action`（コミットSHA `b44d12e7d0d8ee7461bb893e1b1993500433185b`、v5.2.7）を`unit`の前に追加。`shellcheck` step（`timeout-minutes: 3`） |
| `tests/m09-execution-and-ci.sh` | 新しい検査2件（`t_gate_runs_shellcheck_with_pinned_options`、`t_shellcheck_config_and_mise_toml_are_restricted`）。壊れる4件の期待を更新。PATH 保護の`t2602_guard_bin`（前回の修正） |

## 2. 検査の結果

| 検査 | 結果 |
| --- | --- |
| `sh tests/m09-execution-and-ci.sh unit` | 225件中225件通過（終了コード0） |
| `shellcheck -s sh -S style`（`quality-gate.sh`、`m09`） | 0件 |
| `sh -n`（`quality-gate.sh`、`m09`） | 通過 |
| YAML（`e2e-test.yml`） | 読める。job名は`e2e` |
| `sh scripts/quality-gate.sh` | `quality-gate: passed`（527秒）。M02〜M05 smoke、M06〜M08 unit と smoke、S14 unit、M09 unit 223件、M09 smoke 11件、lint:md 0件、`git diff --check` 通過 |

品質ゲートの時間は、フェーズ3の約450秒から約527秒になった。増えたのは、`shellcheck`の追加と、ゲートの前後の検査の量が変わったためである。

## 3. 失敗の確認（T-R0154、T-R0134）

| 確認 | 方法 | 結果 |
| --- | --- | --- |
| 構文エラー以外の指摘（SC2086） | 一時ファイルに未クォートの変数を書き、`git add -N` で対象に入れてゲートを実行 | 終了コード1。`SC2086` が表示された |
| 構文エラー（SC1073） | 閉じていない`if`の一時ファイルで、同様に実行 | 終了コード1。`SC1073` と `FAILED: xargs -0 ...` が表示された |
| mise が無い | `shellcheck_gate`の関数だけを取り出し、PATH に mise を含めずに実行 | 終了コード1。`FAILED: miseが未導入。miseを導入し、mise install --lockedを実行する` |
| shellcheck が無い | 空のmiseデータディレクトリを指定して実行 | 終了コード1。`FAILED: shellcheckが未導入。mise install --lockedを実行する` |
| 版が違う | 未確認。版を変えた`mise.toml`を作る方法が、リポジトリの`mise.toml`を書き換えることになるため、この確認では行わなかった | 残り（利用者の端末での確認とあわせる） |

一時ファイル（`scripts/r01-tmp-style.sh`、`scripts/r01-tmp-syntax.sh`）は、`git reset`と絶対パスでの削除で消した。ゲートの途中で残った`.e2e/`も消した。

## 4. 必須レビュー（T-R0136）

| レビュー | 重大な指摘（Critical、High、Medium） | 指摘 | 対応 |
| --- | ---: | --- | --- |
| `evidence-code-review`（1回目） | 0 | SHOULD 2件、NITS 1件 | 直した（未追跡の`.sh`を検査対象にする、m09 検査の強化、名前の更新） |
| `security-review`（1回目） | 0 | Low 2件、要確認 1件、NITS 3件 | Low 2件を直した（`--`の追加、INT と TERM の trap）。要確認は下の5章。NITS は既知の安全側の失敗のため直さない |

Low の修正は、もう一度のレビューを要しない（再実行は、Critical、High、Medium のとき）。

## 5. 残りの確認

| 項目 | 状態 |
| --- | --- |
| `mise-action` の`install_args`（T-R0153） | 確認済み。`src/install-args.ts`で、`--locked`は既に付いていない場合だけ足す。`--locked shellcheck`の書き方で重複は起きない |
| `mise-action` の`sha256`（security-review の要確認） | 確認済み。`src/index.ts`で、取得した mise 本体の SHA256 が一致しないと止まる（fail-closed）。CI は x64 の`ubuntu-24.04`で動くため、linux-x64 の値で合う |
| macOS と Linux の端末での確認（T-R0138） | 未実施。利用者の端末で行う。未実施のまま完了としない |
| 任意の`aws-well-architected-review-lite`（T-R0137） | 利用者の判断が必要。CI 定義を変えたため、実行するかを決める |
| PR と初回 CI（T-R0141） | 未実施。利用者の端末で、feature ブランチを push し、PR を作る |
| コミット4（T-R0140） | 未実施。利用者の指示を待つ |

## 6. 既知の限界

| 項目 | 内容 |
| --- | --- |
| `mise which` が失敗したときの CI の表示 | `xargs`の空の引数で止まり、導入手順つきの`FAILED:`は出ない（ゲートにはある）。失敗はする（安全側） |
| 削除済みの追跡ファイル | `git ls-files -co`は、作業ツリーから消えた追跡ファイルも一覧に出す。shellcheck が「ファイルがない」で止まる（安全側） |
| `mise.toml`の評価順 | mise-action は、`m09`の検査（`unit`）より前に`mise.toml`を評価する。PR が`[env]`や`[tasks]`を足すと、制限より前に評価される。plan 5.4 節の既知の限界 |
| `docs/ローカル実行とCI.md` | 失敗メッセージから参照しているが、このドキュメントはフェーズ5で作る |
