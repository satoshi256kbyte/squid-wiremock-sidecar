# S26 フェーズ5 検証結果

フェーズ5（Composeの削除と一回限りのgrep。T2630〜T2637）の結果を記録する。
作業と検証はメインエージェントが行った。実行環境はLinux aarch64のEC2（2026-11-07）である。
AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 前提の確認

| 前提 | 状態 |
| --- | --- |
| フェーズ1〜4の検証記録 | `phase-1-results.md`〜`phase-4-results.md`に保存済み |
| 品質ゲート | フェーズ4の最後とT2626の後に通過（448秒、453秒） |
| CI | PR #29の`f8e6582`で成功。PRの状態は`CLEAN` |
| contract | CIで6件通過 |
| CIの実測値の反映 | T2626で`docs/ローカル実行とCI.md`へ反映済み |
| 現行文書 | フェーズ4で新基盤へ更新済み |

## 2. 削除と更新（T2630）

| ファイル | 変更 |
| --- | --- |
| `docker-compose.yml` | 削除 |
| `tests/s14-compose-port-binding.sh` | 削除。S14の契約は`tests/s14-taskdef-contract.sh`へ移行済みで、品質ゲートからも外してある |
| `README.md` | 旧Compose手順と、その注記を削除 |
| `docs/ローカル実行とCI.md` | 「旧基盤との関係」を、削除済みの記述へ直す |
| `tests/m09-execution-and-ci.sh` | READMEの検査を「旧手順が残る」から「旧手順と`docker-compose.yml`が無い」へ直す |

`Dockerfile.test-client`は新基盤のClientのビルドに使うため残した。
リポジトリ直下の`analyze.md`、`plan.md`、`spec.md`、`tasks.md`はM01の記録であり、履歴として書き換えていない。
`specs/`配下の過去のSpec Kit成果物も同様である。

## 3. 一回限りのgrep（T2631）

`plan.md`8章のコマンドで1回だけ実行した。結果は`compose-grep.txt`に保存した。

| 項目 | 内容 |
| --- | --- |
| 対象 | `scripts`、`tests`、`ecs`、`.github`、`docs`、`README.md`、`AGENTS.md`、`package.json`（`specs/`は除外） |
| `git grep`の終了コード | 0（一致あり） |
| 一致した行 | 11行。全て`tests/m09-execution-and-ci.sh` |
| 除外 | コメント行、および`tests/m09-execution-and-ci.sh`（FR-920の検出パターンと、偽の`docker-compose`をPATHに置く検査。呼び出しではない） |
| 呼び出しとしての一致 | 0件 |

## 4. 削除後の検査（T2632）

| 層 | 内容 | 結果 |
| --- | --- | --- |
| 構文 | `sh -n`（`scripts/`、`tests/`、`test-client/`の全shファイル） | 通過 |
| unit | M09、S14契約 | 223件、4件。全て通過 |
| Markdown検査 | `npm run -s lint:md` | 指摘0件 |
| 差分 | `git diff --check`、`git diff --cached --check` | 通過 |
| 作業ツリー | `git status --short` | 想定した削除2件、変更3件、追加1件（`compose-grep.txt`）だけ |

品質ゲート全体は、必須レビューの修正の後に1回だけ実行する（T2635）。

## 5. 必須レビュー（T2633、T2634）

スキルごとに独立したサブエージェント（Claude Sonnet 5.5、effort medium）で、直列に実行した。

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Critical・High・Mediumなし。BETTER 1件、NITS 1件 | 対応した。`docs/roadmap.md`のPhase 1の完了条件に、当時はComposeで確かめ、S26で削除したと書き足す。実態と合わなくなったM09の検査の関数名と表示名を直す |
| `security-review`（1回目） | Critical・High・Mediumなし。旧S14の項目のうち、引き継がれていないものがLow 5件 | 下の表のとおり対応した。レビューアがスキル本文の末尾（埋め込みの基準）を読まなかったため、正式な結果とせず、対応後に再実行する |

旧S14の項目のLow 5件の対応:

| 指摘 | 対応 |
| --- | --- |
| 1 WireMock 8080の実際の公開先（`docker inspect`の`HostIp`）を見る検査がない | 対応しない。後継は、ランナーの`-p 127.0.0.1:8080:8080`が1件だけであることを静的に確かめる。旧S14のlive検査も品質ゲートでは動かない手動の検査だった。静的な検査にとどまることを、ここに記録する |
| 2 許可ドメインを固定する検査がない | 対応した。`s14_allowlist_fixed`を追加し、有効な行が`api.example.com`と`api-staging.example.com`の2件だけであることを確かめる |
| 3 ランナーの静的検査が`-P`を拾わない | 対応した。`s14_squid_not_published`の禁止パターンに`-P`と`--publish-all`を加える |
| 4 範囲外の送信元が拒否されることの動作検査がない | 対応しない。`http_access`の行が2行だけで、固定の行と完全一致することを静的に確かめており、この種の回帰の大半を抑える。動作検査は費用に見合わない |
| 5 識別情報の検査範囲が狭くなった | 対応した。M09の`t_doc_has_no_identity_values`の対象に、`docs/ポート公開範囲.md`、`squid-config/`の2ファイル、`ecs/`の4ファイルを加える |

追加した検査が回帰を検出することを確かめた。許可ドメインに1行足すと`s14_allowlist_fixed`が、ランナーに`-P`を足すと`s14_squid_not_published`が失敗した。確認の後、ファイルは元に戻した。
S14の契約検査は5件、M09のunitは223件、全て通過した。

`security-review`の再実行（スキル本文を最後まで読んだことを確認）は、Critical・High・Mediumなしだった。
受容した2件（指摘1と4）の理由は、妥当と判断された。Low 1件は対応した。

| 指摘 | 対応 |
| --- | --- |
| ランナーの`-p`の検査が、空白なしの`-p8080:8080`を数えない | 対応した。正規表現を`' -p ?[0-9]'`へ広げ、行の数（`grep -c`）ではなく一致の数を数える。行の数では、同じ行の2つ目の`-p`を見落とすことも分かった |

ランナーに`-p8080:8080`、`-p 0.0.0.0:8081:8081`、`-P`をそれぞれ足すと、`s14_squid_not_published`が失敗することを確かめた。確認の後、ファイルは元に戻した。
`security-review`の対応で、`evidence-code-review`が見た範囲（`tests/s14-taskdef-contract.sh`、`tests/m09-execution-and-ci.sh`）が変わったため、`evidence-code-review`を変更箇所に絞って再実行する（AGENTS.mdの「レビューの進め方」の手順7）。

`evidence-code-review`の再実行は、Critical・High・Mediumなしだった。SHOULD 1件は対応せず、限界として記録する。

| 指摘 | 判断 |
| --- | --- |
| ランナーの`-p`の検査は、数字で始まらない公開指定（`-p "$VAR"`、`-p [::]:8081:8081`、タブの後の`-p`）を数えない | 対応しない。`0.0.0.0:`、`3128:`、`--publish`、`-P`の個別の検査が補う。この検査は2回直しており、同じ箇所の局所修正を続けない。ランナーの`-p`を変数で組み立てる形へ変える場合は、この検査も見直す |

## 6. 任意レビュー（T2636）

利用者の判断で、`aws-well-architected-review-lite`をPR #29全体へ実行した（Claude Sonnet 5.5、effort medium。スキル本文を最後まで読んだことを確認）。
High Riskはなかった。Medium Risk 3件は、どれも本番のECSへ持っていくときの差で、このPRで変更していないファイル（`ecs/task-definition.template.json`、`scripts/e2e-taskdef.py`の`check-production`。M09で導入）に関する指摘である。
S26の範囲（既存のE2E検査の移行とComposeの削除）の外であり、任意レビューの結果はコミットのブロッカーにしないため、別のIssueで扱う。

| 柱 | 指摘（Medium Risk） | 扱い |
| --- | --- | --- |
| 運用上の優秀性 | 本番向けのタスク定義に`logConfiguration`がなく、`check-production`も検査しない | 別Issue |
| セキュリティ | `check-production`が、実行ロールとタスクロール、`privileged`、`user`、`readonlyRootFilesystem`を検査しない。Squidのegressをセキュリティグループで許可リスト宛てに限る設計が、タスク定義の外に無い | 別Issue |
| 信頼性 | Squidのヘルスチェックが`kill -0 1`で、3128の待ち受けを確かめない | 別Issue |

Best Practiceとして挙がった項目（CIの失敗時の収集と後処理、CIの権限と秘密、ポート公開の最小化、固定ポートの排他、CIの実行時間）は、変更不要とされた。
本番移行時の検討事項として、負荷の測定、タグ、ARM64（Graviton）が挙がった。

実AWSの検証は、このPRでは行わない。本番移行のIssueで、次の順に行う計画とする。

1. 検証用のアカウントで、本番プロファイルのタスク定義を登録し、`compare`でdescribeと照合する。
2. `check-production`を通したタスク定義で、Fargateのタスクを1回起動する。許可リストの内と外への要求で、許可と拒否を確かめる。
3. CloudWatch Logsへの出力と、セキュリティグループのegressの制限を確かめる。
4. 終了後に、タスク、ロググループ、ロールを削除する。

## 7. 最終の品質ゲート（T2635）

必須レビューと任意レビューの対応の後、`sh scripts/quality-gate.sh`を1回だけ実行し、通過した（449秒）。
Composeの無い状態で、M02〜M08のsmoke、S14の契約検査（5件）、M09のunit（223件）とsmoke（11件）を含む。
後始末の後、`swsc.managed=true`のコンテナ、ロック、`.e2e/`、`e2e-logs/`は残っていない。
CIの結果は、push後にPR #29で確かめる。
