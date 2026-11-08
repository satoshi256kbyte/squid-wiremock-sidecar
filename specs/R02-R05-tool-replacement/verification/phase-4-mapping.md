# フェーズ4 R04（bats-core）の対応表（作成中）

## 1. 旧の記録（T-R0272、作業中）

### 1.1 s14-taskdef-contract.sh

- 引数: `unit` のみ。`sh tests/s14-taskdef-contract.sh unit` の終了コードは 0。
- 検査名と判定（旧の出力）:
  - `s14_acl_lines`: 固定の ACL 行と許可・拒否の行が規定どおり
  - `s14_derived_config_parse`: 派生設定の指令が既知の指令だけで、不正な値を拒否する
  - `s14_mapping_readonly`: WireMock のシナリオが読み取り専用で渡される
  - `s14_squid_not_published`: Squid の 3128 がホストへ公開されない
  - `s14_allowlist_fixed`: 許可ドメインが api.example.com と api-staging.example.com の2件だけ
- 件数: 5（`^ok:` の行は 5 件、末尾は `s14 taskdef contract: 5 件中 5 件通過`）。
- 実行時間: 未計測（T-R0272 の後半）。

### 1.2 m02-routing-smoke.sh、m04-test-client.sh、m05-proxy-integration.sh

- `check` 関数、`expect` 関数、`unit` のモードを持たない。
- Docker を使う直列の smoke スクリプトである（`plan.md` 10.1節の前提と合わない）。
- 旧の「unit の出力の単位」は存在しない。`@test` の区切りは、旧の実行の出力（`ok`、`FAIL`、段階の見出し）から決める必要がある。
- そのため、旧の判定の記録には、Docker の実行が要る（メインが実行する）。実行できない間は「未確認」と書く。

## 2. 未決（利用者の判断が要るもの）

- m02、m04、m05 の旧の判定を、Docker で取るかどうか（取る場合はメインが直列で実行し、結果を保存する）。
- 上の結果を見てから、`@test` の区切りの単位を決める。

## 3. 旧の Docker の判定（T-R0272 の一部）

メインが、Docker の旧のスクリプトを 1 本ずつ直列に実行した。
実行の後に、残った swsc- のコンテナは 0 だった。

| スクリプト | 終了コード | 実行時間 | 結果 |
| --- | --- | --- | --- |
| `tests/m02-routing-smoke.sh` | 0 | 13 秒 | 「M02 Squid routing smoke test passed」 |
| `tests/m04-test-client.sh` | 0 | 12 秒 | 「M04 Test Client transport smoke test passed」（再試行の 4 回を含む） |
| `tests/m05-proxy-integration.sh` | 0 | 13 秒 | 「M05 closed network integration smoke test passed」 |

注意:

- `m05` の 1 回目は、固定ポートのロック（`/tmp/swsc-e2e-ports.lock`）が既にあり、終了コード 1 で止まった。
  ロックの持ち主（PID 1656126）は実行中ではなく、直後にロックは消えていた。
  別の実行が取っていたものが、終わったと考えられる。ロックを手で消してはいない。
  2 回目の実行で通った。
- 検査の 1 件ずつの名前と判定は、まだ記録していない（`@test` の区切りを決めるための作業が残っている）。

## 4. 旧の検査の一覧（1 件ずつの判定）

3 本とも、名前を持つ検査ではなく、順番に実行される手順である。手順 1 つを、1 つの判定として扱う。
名前は、手順の内容から付けた仮の名前である。旧には名前が無いので、移行のときに 1 つに決める。

### 4.1 m02-routing-smoke.sh（5 件）

| 番号 | 手順 | 判定（失敗の条件） |
| --- | --- | --- |
| 1 | WireMock に `/m02-routing` の mapping を登録する | `curl` が失敗する |
| 2 | Client で proxy 経由に `/m02-routing` を取る | 出力に `CLIENT_STATUS=200` と `CLIENT_BODY=m02-routing-ok` が無い |
| 3 | WireMock の受信に `m02-routing` が現れる | 受信の応答に `m02-routing` が無い |
| 4 | Squid の access log に `m02-routing` の行がある | `swsc_squid_log_check` が失敗する |
| 5 | allowlist 外（example.com）を Client で送る | 出力に `CLIENT_STATUS=403` が無い |

### 4.2 m04-test-client.sh（5 件）

| 番号 | 手順 | 判定（失敗の条件） |
| --- | --- | --- |
| 1 | 200 の経路（`/api/users/123`）を取る | `CLIENT_STATUS=200`、`CLIENT_BODY=`、`"id": 123`、`"name": "John"` が無い。WireMock の受信に `/api/users/123` が無い |
| 2 | 500 の経路（`/api/error-500`）を取る | `CLIENT_STATUS=500` と `Internal Server Error` が無い |
| 3 | 転送失敗（proxy を 127.0.0.1:1 にする） | 終了コードが 0。`CLIENT_ERROR=curl_exit_` が無い |
| 4 | proxy 未設定 | 終了コードが 78 でない。`CLIENT_ERROR=proxy_not_configured` が無い |
| 5 | `test-client/entrypoint.sh` に WireMock への直接接続の指定が無い | `wiremock` または `:8080` の一致がある（失敗） |

### 4.3 m05-proxy-integration.sh（6 件）

| 番号 | 手順 | 判定（失敗の条件） |
| --- | --- | --- |
| 1 | 許可した経路（`api.example.com/api/users/123`）を Client で取る | `CLIENT_STATUS=200` と `"id": 123` が無い |
| 2 | WireMock の受信に `/api/users/123` が現れる | 受信の応答に `/api/users/123` が無い |
| 3 | Squid の access log に `api.example.com/api/users/123` と `TCP_MISS/200` がある | `swsc_squid_log_check` が失敗する |
| 4 | WireMock の受信を空にし、allowlist 外（example.com）を送る | 出力に `CLIENT_STATUS=403` が無い |
| 5 | allowlist 外の要求が WireMock に届かない | `swsc_wiremock_total`（/api/ の件数）が 0 でない |
| 6 | Squid の access log に `example.com` と `TCP_DENIED` がある | `swsc_squid_log_check` が失敗する |

### 4.4 件数（仮）

- m02: 5 件（`@test` の候補 5 件）
- m04: 5 件（`@test` の候補 5 件。手順 1 は中で 2 段の確認を持つ）
- m05: 6 件（`@test` の候補 6 件）

これらは旧の出力の単位（手順）に合わせた仮の件数である。移行のときに、`@test` の区切りとして確定する。

## 5. 旧の検査名と新の `@test` 名の対応表（T-R0287）

`bats --count` と `grep -c '^@test'` は、すべてのファイルで一致した。

| 旧のファイルと行 | 旧の名前（または手順） | 新のファイルと `@test` 名 | 判定の一致 |
| --- | --- | --- | --- |
| `tests/s14-taskdef-contract.sh`（`check` 5 件） | `s14_acl_lines` など 5 件 | `tests/bats/s14-taskdef-contract.bats`、同名の 5 件 | 名前は完全に一致（diff なし） |
| `tests/m02-routing-smoke.sh` 手順 1 | mapping の登録（名前なし） | `m02 smoke: WireMock に /m02-routing の mapping を登録する` | 手順の内容が一致 |
| `tests/m02-routing-smoke.sh` 手順 2〜5 | 200、受信、Squid の log、403（名前なし） | `m02 smoke:` の 4 件（`phase-4-results.md` 8 章） | 手順の内容が一致 |
| `tests/m03-wiremock-scenarios.sh` の `validate_json`、`validate_mapping` の unit（T-R0256） | `unit_validate_*`（5 件） | `tests/bats/m03-wiremock-scenarios.bats`、同名の 5 件 | 名前が一致。判定は section 3 の旧の記録と一致 |
| `tests/m03-wiremock-scenarios.sh` の smoke | 手順（名前なし） | `m03 smoke:` の 11 件 | 手順の内容が一致 |
| `tests/m04-test-client.sh` 手順 1〜5 | 200、500、転送失敗、proxy 未設定、入口の確認（名前なし） | `tests/bats/m04-test-client.bats` の `m04 smoke:` 5 件 | 手順の内容が一致 |
| `tests/m05-proxy-integration.sh` 手順 1〜6 | 許可の 200、受信、log（TCP_MISS）、403、受信 0、log（TCP_DENIED）（名前なし） | `tests/bats/m05-proxy-integration.bats` の `m05 smoke:` 6 件 | 手順の内容が一致 |
| `tests/m07`、`tests/m08` の unit（T-R0258 など） | 既存の検査名 | 本作業では移行していない（T-R0295〜T-R0309 で移す） | 対象外 |

注意:

- 旧の m02、m03 の smoke、m04、m05 の手順には名前が無かった。新しい名前は、手順の内容から付けた。
  名前が変わった分は、この表で対応を示す。
- 件数の一致: s14 は 5、m02 は 5、m04 は 5、m05 は 6、m03 は 17（unit 6、smoke 11）。
- 壊した入力で、旧と新が同じ検査で落ちることは、T-R0288 で確かめる。
