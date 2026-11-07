# S26 フェーズ3 検証結果

フェーズ3（M06〜M08の移行。T2614〜T2618）の結果を記録する。
実装はサブエージェント（Claude Haiku 5.5）、実機の検証、修正、品質ゲートはメインエージェントが行った。
実行環境はLinux aarch64のEC2（2026-11-07）である。AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 変更範囲

| ファイル | 変更 |
| --- | --- |
| `tests/m06-client-resilience.sh` | smokeを新基盤へ移行する。Clientは`swsc_client_once_env`で実行し、受信数は`swsc_wiremock_count_path`で数える。`docker stop`、`restart`、`kill`は再現しない |
| `tests/m07-scenario-isolation.sh` | reset、状態遷移、2周の再現、INT/TERM、cleanup、`swsc.managed=true`の残存確認を新基盤へ移行する |
| `tests/m08-e2e-suite.sh` | 4シナリオ、信号、後始末を新基盤へ移行する。起動失敗の検査を、出力先に他人のファイルがある起動へ置き換える |
| `scripts/e2e-lib.sh` | `swsc_test_ci_scenarios`を追加する。シナリオ名を検査してからロックを取り、M08のsmoke経路で選んだシナリオだけを実行する |
| `scripts/e2e.sh` | `test:ci [シナリオ名...]`を受け付ける。名前が無いときは従来の`swsc_test_ci_main`を使う |
| `tests/m09-execution-and-ci.sh` | `test:ci`の不明なシナリオ名が、ロックと起動の前に終了コード2になるunitを追加する |

`scripts/scenario-lib.sh`は変更していない。`wiremock_verify_reset`の`/squid-internal-`除外（Issue #23）は、そのまま使う。

## 2. 実装中に直した点

| 問題 | 原因 | 対応 |
| --- | --- | --- |
| M06とM07のsmokeが`swsc_lock_enter: command not found`で止まる | 共通部品（`scripts/e2e-lib.sh`、`scripts/e2e-runner.sh`）を読み込んでいなかった。unitはdockerを呼ばないため、気付かなかった | M08と同じく、スクリプトの先頭で読み込む |
| M08の信号ケース（INT、TERM）で、後始末のresetが行われない | 新基盤は、WireMockをSquidより先に起動する。親は管理APIの応答で準備完了と判定し、`swsc_start_main`の途中で信号を送る。そのとき`smoke_started`がまだ0だった | 移行前と同じく、ポートの空きを確かめた直後に`smoke_started=1`を立てる |
| M08の起動失敗の検査が、上の対応の後に落ちる | 起動はWireMockを作る前に止まる。後始末は「実行中でない」としてresetを送らない | 期待値を`cleanup: reset skipped (not running)`にする。resetを送らないことは維持する |
| `test:ci`の名前指定で、親だけがINT/TERMを受けるとロックが残る（`evidence-code-review`のMUST） | `swsc_test_ci_scenarios`がtrapを持たず、子を前景で動かしていた。shは前景の子が終わるまでtrapを処理しない | 子をバックグラウンドで起動して`wait`する。信号を受けたら子へTERMを送り、子の後始末を待ってからロックを解放する。unit 2件を追加し、実機で親だけにTERMを送って終了コード143、ロックと資源の残り0件を確かめた |
| 名前付きのunitケースが2件無い | `m08_scenario_expectations`、`m08_term_cleanup`の名前が付いていなかった | 既存の検査（シナリオ表、後始末のreset）へ名前を付ける。TERMの実機の確認はsmokeの信号ケースで行う |

## 3. 実行結果

| 層 | 内容 | 結果 |
| --- | --- | --- |
| 構文 | `sh -n`（変更した全ファイル） | 通過 |
| Compose呼び出し | `grep -n 'docker-compose\|docker compose'`（M06〜M08、`scripts/e2e.sh`、`scripts/scenario-lib.sh`） | 0件 |
| unit | M06、M07、M08、M09 | 133件、44件、19件、218件。全て通過 |
| smoke | M06 | 通過（21秒） |
| smoke | M07 | 60件通過（147秒） |
| smoke | M08（1回目） | 30件通過（66秒） |
| smoke | M08（2回目） | 30件通過（68秒） |
| test:ci | `sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000` | 4件PASS（26秒、シナリオ部分10秒） |
| 品質ゲート | `sh scripts/quality-gate.sh` | 失敗（433秒）。`docker-compose config --quiet`だけが失敗した |
| 後始末 | `swsc.managed=true`のコンテナ、ロック | 0件、残っていない |

品質ゲートの中では、M03〜M08のsmoke、M09のunitとsmokeが全て通過した。
失敗は、この環境に`docker-compose`が無いことによる。この項目はT2621で削除する。成功とは断定しない。

### M08のシナリオの秒数（2回分）

| シナリオ | 1回目（周1、周2） | 2回目（周1、周2） | 期待 |
| --- | --- | --- | --- |
| normal | 1、0 | 0、0 | status=200、試行1 |
| error-500-then-200 | 1、1 | 1、2 | status=200、試行2 |
| ratelimit-429 | 7、6 | 6、6 | status=429、試行4 |
| slow-5000 | 1、1 | 1、2 | timeout、終了コード28 |

### M08の信号ケース（2回分）

| 回 | 信号 | 準備まで | 信号から終了まで | 終了コード |
| --- | --- | --- | --- | --- |
| 1 | INT | 6秒 | 2秒 | 130 |
| 1 | TERM | 6秒 | 2秒 | 143 |
| 2 | INT | 6秒 | 2秒 | 130 |
| 2 | TERM | 6秒 | 2秒 | 143 |

両方の回で、後始末のreset、一時ディレクトリの空、管理対象の残存0件を確かめた。
以前に1回だけ失敗したTERMケース（Issue #21）は、この2回では再発していない。

## 4. 次フェーズへ渡す事項

| 事項 | 内容 |
| --- | --- |
| 品質ゲートのCompose項目 | `scripts/quality-gate.sh`の`docker-compose config`と`docker-compose ps`をT2621で削除する |
| 品質ゲートのM02 | 「稼働中のスタックが必要」の除外を、T2621で外す |
| CIのM08 | `test:ci`の4シナリオをT2622でCIへ載せる。実行は`sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000` |
| 品質ゲートの所要時間 | 433秒。M07（約150秒）とM08（約70秒）が増えた。CIのtimeoutの見直し（T2626）の材料にする |
| 未実行の層 | contract（フェーズ4のCI） |

## 5. コミット前の必須レビュー（2026-11-07）

スキルごとに独立したサブエージェント（Claude Sonnet 5.5、effort medium）で、直列に実行した。

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | MUST 1件（`test:ci`の名前指定で、親だけがINT/TERMを受けるとロックが残る） | 対応した（2章）。再レビューで解消を確認し、新しい指摘はなかった |
| `security-review`（対応後の差分） | Critical・High・Mediumなし。Low 1件 | 対応しない。`SWSC_LOCK_HELD=1`を環境に設定したまま並行して起動すると、ロックを取らずに進む。既存の`test:ci`の規約で、今回の差分が作ったものではない |

確認していない範囲は、`&`の直後から子のPIDを記録するまでの、命令数個分の時間窓に届いた信号である。
この窓で信号が届くと子が孤児になりうるが、再現性は極めて低く、ブロッカーにしない。
