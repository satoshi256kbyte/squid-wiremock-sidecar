# M06実装タスク

## 1. 進め方

`plan.md` 8章の12実装単位を、T601からT612に1対1で対応させる。品質ゲート実行をT613として追加する。
各タスクは、対応する検査が通ってから次へ進む。検査は先に失敗するケースを書いてから実装する。

タスクと実装単位の対応は次のとおり。

| タスク | plan.md 8章の単位 |
| --- | --- |
| T601 | 1 検査入口の骨格 |
| T602 | 2 対象判定と待機計算 |
| T603 | 3 Retry-After解析 |
| T604 | 4 設定の既定値と検証 |
| T605 | 5 entrypointの前処理 |
| T606 | 6 リトライループ |
| T607 | 7 タイムアウト |
| T608 | 8 診断ログと出力契約 |
| T609 | 9 Dockerfile |
| T610 | 10 M04スモークの調整 |
| T611 | 11 M06スモーク |
| T612 | 12 最終確認 |
| T613 | 品質ゲート（追加） |

### 並列実行の可否

`tests/m06-client-resilience.sh`は T601 から T608、T611 のすべてが編集する。
`test-client/retry-lib.sh`は T602 から T604 が、`test-client/entrypoint.sh`は T605 から T608 が編集する。
同一ファイルを編集するため、T601 から T608 と T611 は並列に実行しない。依存順に1つずつ進める。

並列にできるのは T609 と T610 だけである。編集するファイルが互いに異なり、どちらも T608 の完了後に着手できる。
ただし T611 は両方の完了を待つ。

## 2. タスク

### T601: 検査入口の骨格

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-605 |
| 触るファイル | `tests/m06-client-resilience.sh`（新規） |
| 依存 | なし |
| 並列 | 不可（以降の全タスクが同じ検査ファイルを編集する） |
| 検査 | `docker-compose`をPATHから外して`sh tests/m06-client-resilience.sh unit`を実行し、Composeを呼ばずに終了する |

- `unit`と`smoke`の引数でモードを切り替える。引数なしは`smoke`と同じ
- `unit`では`docker`、`docker-compose`を呼ばず、Composeの`trap`も登録しない
- 一時ファイルは`mktemp -d`配下に置き、`trap`で削除する
- 失敗時は落ちた検査名を標準エラーに出し、非ゼロで終了する
- 最初は失敗するケースから作る

### T602: 対象判定と待機計算

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-601、FR-602、FR-604、FR-610 |
| 触るファイル | `test-client/retry-lib.sh`（新規）、`tests/m06-client-resilience.sh` |
| 依存 | T601 |
| 並列 | 不可（検査ファイルを共有。T603、T604と`retry-lib.sh`も共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`の対象判定、5xx待機、429待機のケースが通る |

- `is_retryable_status`、`backoff_wait_5xx`、`resolve_429_wait`を実装する
- 対象判定は200、301、404、501、502、504が対象外、500、503、429が対象
- 5xx待機はbase=1でn=1,2,3が1,2,4、上限での打ち切り、base=0、n=1が上限に等しい場合を検査する
- 429待機は上限ちょうど、上限+1（切り詰めフラグ1）、0秒、値なしで既定待機、既定待機が上限超過を検査する
- 読み込み時に副作用を持たせない。POSIX shのみを使う

### T603: Retry-After解析

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-603 |
| 触るファイル | `test-client/retry-lib.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T602 |
| 並列 | 不可（`retry-lib.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`の`parse_retry_after`のケースが通る |

- `parse_retry_after`を`awk`で実装する（busyboxで動く機能のみ）
- 有効値は0、5、上限ちょうど、999999（6桁の最大）、大文字小文字違いのヘッダー名、CR付き、同名複数は最後の値
- 不在扱い（終了コード1）は空、負数、小数、HTTP日付、数字以外を含む値、ヘッダーなし
- 7桁以上は上限超過として`1000000`を出力して0を返す。`0000005`は5、`0000000`は0、20桁の数字列は1000000とする

### T604: 設定の既定値と検証

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-607 |
| 触るファイル | `test-client/retry-lib.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T603 |
| 並列 | 不可（`retry-lib.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`の設定検証のケースが通る |

- `apply_config_defaults`は空または未設定の変数に既定値を入れ、先頭の0を除去して正規化する
- `validate_config`は不正な最初の変数名だけを出力して1を返す
- 不正値は負数、非数値、小数、7桁以上、`CONNECT_TIMEOUT_SECONDS`と`RESPONSE_TIMEOUT_SECONDS`の0
- 空文字は既定値、`007`と`08`は8進数と誤解釈されず正規化される
- 2変数が不正なとき、`plan.md` 3.2の検査順で先の変数名だけを報告する
- 接続タイムアウトが全体タイムアウトより大きい場合は不正にしない

### T605: entrypointの前処理

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-607、NFR-601、NFR-602 |
| 触るファイル | `test-client/entrypoint.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T604 |
| 並列 | 不可（`entrypoint.sh`と検査ファイルを共有。T606からT608も`entrypoint.sh`を共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`のentrypoint検査のうち、設定不備とプロキシ優先のケースが通る |

- スタブ`curl`と`sleep`を一時ディレクトリに作り、PATHの先頭に置く検査基盤をこのタスクで用意する
- 処理順は`HTTP_PROXY`検査、`retry-lib.sh`読み込み、`apply_config_defaults`、`validate_config`とする
- 設定不備は`CLIENT_ERROR=invalid_config`と`CLIENT_DIAG invalid_config name=<変数名>`を標準エラーに出し、78で終了する
- 設定不備のとき`curl`スタブが呼ばれず、値が出力に含まれないことを確認する
- `HTTP_PROXY`が空かつ設定不備のときは`proxy_not_configured`だけが出る

### T606: リトライループ

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-601、FR-602、FR-603、FR-604、FR-610、FR-611 |
| 触るファイル | `test-client/entrypoint.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T605 |
| 並列 | 不可（`entrypoint.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`のentrypoint検査のうち、リトライ系のケースが通る |

- 5xxと429のカウンターを独立に持ち、`attempt`で総試行回数を数える
- 対象外ステータスは1回で返し、`sleep`を呼ばない
- 上限到達時は最後の`CLIENT_STATUS`と`CLIENT_BODY`を出力し、終了コード0で終わる
- 最大リトライ回数0は1回だけ試行して終了コード0とする
- `sleep`は待機が0でも呼ぶ
- 検査は200の1回成功、500が続く（回数3、base=1で待機列1,2,4）、500の後に200、503と500の混在を含む
- 429は`Retry-After`あり上限超過（切り詰め）、`Retry-After`が7桁以上で待機が上限に切り詰められ`capped=1`、`Retry-After`なし（既定待機で増加しない）、429と500の混在を含む
- 対象ステータスでも回数0なら1回で終了することを検査する

### T607: タイムアウト

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-605、FR-606 |
| 触るファイル | `test-client/entrypoint.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T606 |
| 並列 | 不可（`entrypoint.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`のentrypoint検査のうち、タイムアウトとcurlオプションのケースが通る |

- curlに`--connect-timeout "$CONNECT_TIMEOUT_SECONDS"`と`--max-time "$RESPONSE_TIMEOUT_SECONDS"`を渡す
- curl終了コード28で`CLIENT_ERROR=timeout`を標準エラーに出し、標準出力を空にして28で終了する。`sleep`は0回
- 接続拒否（curl終了コード7）は`CLIENT_ERROR=curl_exit_7`、終了コード7になる
- スタブが記録した引数に、2つのタイムアウトオプションが設定値で入り、`--noproxy ''`と`--proxy`が維持されていることを確認する

### T608: 診断ログと出力契約

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-608、FR-609、NFR-604 |
| 触るファイル | `test-client/entrypoint.sh`、`tests/m06-client-resilience.sh` |
| 依存 | T607 |
| 並列 | 不可（`entrypoint.sh`と検査ファイルを共有） |
| 検査 | `sh tests/m06-client-resilience.sh unit`の診断ログと標準出力の純度のケースが通る |

- `plan.md` 3.5の形式で`CLIENT_DIAG`を出す（5xxのリトライ、429の`Retry-After`あり／なし、最終結果、タイムアウト、curl失敗）
- `result=success`の行（`CLIENT_DIAG result=success attempts=1 status=200`）を出す
- 最終結果`result=`は`success`、`retries_exhausted`、`timeout`の3値に固定する
- curl失敗の行は`result=`を持たない
- 診断ログに設定値、URL、本文、`Retry-After`以外のヘッダーを出さない
- `retry-lib.sh`と`entrypoint.sh`に`wiremock`と`:8080`の文字列がないことを確認する
- すべてのケースで標準出力が`CLIENT_STATUS`と`CLIENT_BODY`の2行のみで、`CLIENT_DIAG`が混ざらない

### T609: Dockerfile

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-603、NFR-605 |
| 触るファイル | `Dockerfile.test-client` |
| 依存 | T608 |
| 並列 | T610と並列可（編集ファイルが異なる）。T611は本タスクの完了を待つ |
| 検査 | `grep -n 'retry-lib.sh' Dockerfile.test-client`で`COPY`と`chmod 0644`の行が見える。実体の確認はT611 |

- `COPY test-client/retry-lib.sh /usr/local/bin/retry-lib.sh`を追加する
- `chmod 0644`を追加する。`retry-lib.sh`は読み込まれるだけなので実行権限は付けない
- ベースイメージとパッケージは変更しない
- `docker-compose.yml`、Squid、WireMockの設定は変更しない

### T610: M04スモークの調整

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-601 |
| 触るファイル | `tests/m04-test-client.sh` |
| 依存 | T608 |
| 並列 | T609と並列可（編集ファイルが異なる）。T611は本タスクの完了を待つ |
| 検査 | `sh tests/m04-test-client.sh`が通る。`git diff`で変更が`/api/error-500`の`docker-compose run`への1行追加だけである |

- `error_output=$(docker-compose run ...)`の`/api/error-500`実行に`-e RETRY_BACKOFF_BASE_SECONDS=0`を足す
- 検査行（`CLIENT_STATUS=500`と`Internal Server Error`）とM04の他の検査は変えない
- 実通信を伴うため、T609の反映後のイメージで実行する。必要なら先にイメージを再ビルドする

### T611: M06スモーク

| 項目 | 内容 |
| --- | --- |
| 要件 | NFR-605 |
| 触るファイル | `tests/m06-client-resilience.sh` |
| 依存 | T609、T610 |
| 並列 | 不可（検査ファイルを共有。T609とT610の完了後に単独で実施） |
| 検査 | `sh tests/m06-client-resilience.sh smoke`が通る。引数なしの`sh tests/m06-client-resilience.sh`も通る |

- `smoke`のときだけ、開始前に`down --remove-orphans`、`up -d squid wiremock`、readiness待機を行い、終了時の`trap`で`down`する
- `docker-compose run --rm --no-deps --entrypoint test test-client -f /usr/local/bin/retry-lib.sh`が成功することを確認する
- `/api/error-500`に`RETRY_MAX_ATTEMPTS_5XX=1`と`RETRY_BACKOFF_BASE_SECONDS=0`を指定し、`CLIENT_STATUS=500`を確認する
- WireMockの`POST /__admin/requests/count`で、当該URLの呼び出し数が前後で2増えることを確認する
- ジャーナルのリセットとM03マッピングの変更はしない
- `/api/slow-5000`に`RESPONSE_TIMEOUT_SECONDS=1`を指定し、`CLIENT_ERROR=timeout`、標準出力が空、終了コード28を確認する
- コンテナ内で`retry-lib.sh`を読み込み、CR付きと7桁以上の`Retry-After`を`parse_retry_after`に渡して期待値を確認する
- `smoke`は`unit`を含めて実行する
- 引数なしの`sh tests/m06-client-resilience.sh`も通る

### T612: 最終確認

| 項目 | 内容 |
| --- | --- |
| 要件 | `spec.md` 7章の完了条件すべて |
| 触るファイル | なし（確認のみ。失敗があれば原因のタスクへ戻って直す） |
| 依存 | T611 |
| 並列 | 不可（Composeのポートとコンテナ名を共有するため、検査を順に実行する） |
| 検査 | 下記の4コマンドが順にすべて成功する |

- `sh tests/m06-client-resilience.sh unit`（Composeなし）
- `sh tests/m06-client-resilience.sh`（引数なし）
- `sh tests/m04-test-client.sh`
- `sh tests/m05-proxy-integration.sh`
- `spec.md` 7章の各項目に対応する検査があることを突き合わせる

### T613: 品質ゲート

| 項目 | 内容 |
| --- | --- |
| 要件 | M06全体（コミット前の最終ゲート） |
| 触るファイル | なし（確認のみ） |
| 依存 | T612 |
| 並列 | 不可（全タスクの完了後に単独で実施） |
| 検査 | `sh scripts/quality-gate.sh`が成功する |

- コミットの前に実行する。失敗した場合は原因のタスクへ戻って直し、再度実行する
- 実行結果を記録する
- Squid、WireMock、Composeの設定に差分がないこと（NFR-603）を`git diff --stat`で確認する

## 3. analyze で確定する論点

analyzeで次の2点を確定した。

| 論点 | 決定 |
| --- | --- |
| 1. NFR-605の検査ファイル構成 | `tests/m06-client-resilience.sh`の1ファイルに統一。`spec.md`のNFR-605を直す |
| 2. 7桁以上の`Retry-After` | 上限超過として`RETRY_MAX_WAIT_SECONDS`へ切り詰める。`spec.md`のFR-603に明記する |

## 4. 完了条件

- [ ] T601からT613を完了している
- [ ] `retry-lib.sh`の関数を実通信なしで検査できる
- [ ] スタブ`curl`と`sleep`でentrypointの待機列、終了コード、出力契約を検査できる
- [ ] `Dockerfile.test-client`が`retry-lib.sh`をCOPYし、スモークで存在を確認できる
- [ ] `tests/m04-test-client.sh`が`RETRY_BACKOFF_BASE_SECONDS=0`で通る
- [ ] `sh scripts/quality-gate.sh`が成功している
- [ ] `spec.md`、`plan.md`、`clarify.md`が`analyze.md`の修正どおりに直されている
