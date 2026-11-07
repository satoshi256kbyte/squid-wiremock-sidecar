# S26 フェーズ2 検証結果

フェーズ2（M02〜M05の移行。T2607〜T2612）の結果を記録する。
実装はサブエージェント（Claude Haiku 5.5）、実機の検証と品質ゲートはメインエージェントが行った。
実行環境はLinux aarch64のEC2（2026-11-07）である。AWSアカウント識別子、ARN、認証情報は記録しない。

## 1. 変更範囲

| ファイル | 変更 |
| --- | --- |
| `tests/m02-routing-smoke.sh` | 新基盤で起動する。proxy要求と許可外要求をClientから送る。access logは`swsc_squid_log_check`で検査する |
| `tests/m03-wiremock-scenarios.sh` | 新基盤で起動する。既存のmapping、本文、遅延の検査の後に`scenario_check_static`を追加する |
| `tests/m04-test-client.sh` | Client実行を`swsc_client_once_env`へ置き換える。環境変数の上書きは引数で渡す |
| `tests/m05-proxy-integration.sh` | Clientと`swsc_squid_log_check`へ置き換える。許可外要求の受信数0を追加する |

4本とも、固定ポートのロック（`swsc_lock_enter`、`swsc_lock_leave`）、`swsc_start_main`による起動、
trapでの後始末（失敗時だけ`swsc_collect`、常に`swsc_stop`）を使う。`scripts/e2e-lib.sh`は変更していない。

## 2. 実装中に直した点

新基盤のSquidは、ホストへポートを公開しない（3128はpauseのnamespaceの中だけ）。
サブエージェントの初版は、ホストから`127.0.0.1:3128`へproxy要求を送る形を残していた。
M02の実機smokeが終了コード7（接続できない）で失敗し、原因を特定した。

| 検査 | 直した内容 |
| --- | --- |
| M02 | 許可要求と許可外要求を、`swsc_client_once_env`でClientから送る。`TEST_API_PATH`で経路を指定する |
| M04 | ホストからのproxy待ちを削除する。Squidの待ち受けは`swsc_start_main`（runner）がpauseの中で確かめる |
| M05 | M04と同じ待ちの削除に加え、許可外要求をClientから送る。送る前に受信記録を空にし、許可外の受信数を`swsc_wiremock_total`で数える。経路は`/api/users/123`にする（`swsc_wiremock_total`が`/api/`配下だけを数えるため） |
| M02〜M05 | 一時ディレクトリをロックの後に作る。cleanupの削除失敗でロック解放が止まらないよう、`rm`と`rmdir`の失敗を無視する |

M05の経路と一時ディレクトリの扱いは、`evidence-code-review`のLow指摘（3件）への対応である。
対応後に、M02〜M05のsmokeを再実行し、全て終了コード0だった（13秒、17秒、13秒、12秒）。

## 3. 期待値の比較

移行前（Compose）の実行は、この環境に`docker-compose`が無いため行っていない。
比較は、移行前のスクリプト（`origin/main`）の判定と、移行後の判定の対応で行った。

| 検査 | 移行前の判定 | 移行後の判定 | 差 |
| --- | --- | --- | --- |
| M02 | 本文`m02-routing-ok`、受信記録、access log、許可外の失敗 | 同じ。許可外は`CLIENT_STATUS=403`で判定する | 許可外の判定が「失敗」から「403」へ具体化 |
| M03 | mapping、本文、ステータス、遅延 | 同じ。`scenario_check_static`を追加 | 検査の追加のみ |
| M04 | 200、500、転送失敗（非0）、proxy未設定（78）、WireMock直接接続の禁止 | 同じ | なし |
| M05 | 200、受信記録、`TCP_MISS/200`、許可外の失敗、`TCP_DENIED` | 同じ。許可外の受信数0を追加 | 検査の追加と、403での具体化 |

## 4. 実行結果

| 層 | 内容 | 結果 |
| --- | --- | --- |
| 構文 | `sh -n`（変更した4ファイル） | 通過 |
| Compose呼び出し | `grep -n 'docker-compose\|docker compose'`（変更した4ファイル） | 0件 |
| smoke（実Docker） | M02、M03、M04、M05を直列実行 | 全て終了コード0（12秒、17秒、13秒、12秒） |
| unit | `sh tests/m09-execution-and-ci.sh unit` | 215件中215件通過 |
| smoke（M09） | `sh tests/m09-execution-and-ci.sh smoke` | 11件中11件通過（114秒） |
| Markdown検査 | `npm run -s lint:md` | 指摘0件 |
| 品質ゲート | `sh scripts/quality-gate.sh` | 失敗（198秒）。`docker-compose config --quiet`だけが失敗した |
| 後始末 | `swsc.managed=true`のコンテナ、ロック | 0件、残っていない |

品質ゲートの失敗は、この環境に`docker-compose`が無いことによる。この項目はT2621で削除する。成功とは断定しない。
品質ゲートは、M02を「稼働中のスタックが必要」として実行しない。M02は移行後に自分で起動するため、
T2621でゲートの対象へ加える。

## 5. 次フェーズへ渡す事項

| 事項 | 内容 |
| --- | --- |
| 起動時の`curl: (56)` | 起動の待ちの間に、接続リセットのメッセージが標準エラーに出る。判定には影響しない。M09 smokeでも同じ |
| 品質ゲートのM02 | 「稼働中のスタックが必要」の除外を、T2621で外す |
| M06の移行 | M04と同じく、ホストからのproxy要求を使わない形にする |
| 未実行の層 | contract（フェーズ4のCI）、M06〜M08の実機smoke（フェーズ3） |

## 6. コミット前の必須レビュー（2026-11-07）

スキルごとに独立したサブエージェント（Claude Sonnet 5.5、effort medium）で、直列に実行した。

| レビュー | 結果 | 対応 |
| --- | --- | --- |
| `evidence-code-review` | Critical・High・Mediumなし。Low 3件 | 全て対応した（2章）。対応後にM02〜M05のsmokeを再実行し、全て通過 |
| `security-review`（対応後の差分） | Critical・High・Mediumなし。Low 1件 | 対応しない。M02の許可外検査は403だけを見る。M05が`TCP_DENIED`と受信数0を確かめており、移行前より弱まっていない |

確認していない範囲は、`swsc_lock_acquire`のPID再利用への耐性と、収集物のマスク規則の網羅性である。
