# M06実装計画

## 1. 実装方針

M06はTest Clientの`test-client/entrypoint.sh`にリトライ、バックオフ、タイムアウトを追加する。
判定と計算は副作用のない関数として`test-client/retry-lib.sh`に分け、`entrypoint.sh`が読み込んで使う。
ループ、curl呼び出し、`sleep`、出力はすべて`entrypoint.sh`が担当する。

検証は実通信を使う層と使わない層に分ける。M06の中心である境界値と出力契約は、Dockerもネットワークも使わずに確認する。

| 層 | 対象 | 実通信 |
| --- | --- | --- |
| 単体検査 | `retry-lib.sh`の関数をホストの`sh`で直接呼ぶ | なし |
| entrypoint検査 | スタブ`curl`と`sleep`をPATH先頭に置いて`entrypoint.sh`を実行する | なし |
| Composeスモーク | M04の既存検査とM06の追加検査 | あり（Squid経由でWireMock） |

本番スクリプトにテスト専用の環境変数や分岐は入れない。スタブはPATHの差し替えだけで実現する。
スクリプトはM04と同じPOSIX shで書き、配列、`[[ ]]`、`local`、プロセス置換は使わない。

## 2. 変更ファイル

| パス | 変更内容 |
| --- | --- |
| `test-client/retry-lib.sh` | 新規。POSIX shの関数のみ。読み込み時に副作用を持たない |
| `test-client/entrypoint.sh` | 設定検証、リトライループ、curlオプション、診断ログを追加する |
| `Dockerfile.test-client` | `retry-lib.sh`のCOPYを追加する |
| `tests/m06-client-resilience.sh` | 新規。M06の検査入口。引数なしは`smoke`と同じ全検査、`unit`はCompose不要 |
| `tests/m04-test-client.sh` | `/api/error-500`の`docker-compose run`に`-e RETRY_BACKOFF_BASE_SECONDS=0`を1行足す |
| `specs/M06-client-resilience/` | M06のSpec Kit成果物 |

`docker-compose.yml`、Squid、WireMockの設定は変更しない（NFR-603）。

## 3. 技術方針

### 3.1 retry-lib.shの責務

すべての関数は引数と標準入力だけを入力とし、結果を標準出力か終了コードで返す。
ファイル、ネットワーク、`sleep`、`exit`には触れない。呼び出し側が`set -eu`でも動くよう、未定義変数を参照しない。

| 関数 | 入力 | 出力と終了コード |
| --- | --- | --- |
| `is_retryable_status` | HTTPステータス | 500と503は`5xx`、429は`429`を標準出力に出して0。それ以外は何も出さず1 |
| `backoff_wait_5xx` | リトライ番号n、base、上限 | `min(base * 2^(n-1), 上限)`の秒数を出力 |
| `parse_retry_after` | 標準入力にレスポンスヘッダー全文 | 有効な秒数を出力して0。無効または不在は何も出さず1 |
| `resolve_429_wait` | `parse_retry_after`の結果（空可）、既定待機、上限 | `<待機秒> <切り詰めフラグ0/1>`を出力 |
| `apply_config_defaults` | なし（環境変数） | 空または未設定の設定変数に既定値を入れる。先頭の0を除去して正規化する |
| `validate_config` | なし（環境変数） | 不正な最初の変数名を出力して1。すべて正常なら何も出さず0 |

#### 待機時間の計算

`backoff_wait_5xx`は`base`から始めて`n-1`回2倍にする。各回で上限を超えたら上限に置き換えて打ち切る。
上限は6桁以内なので、64bit整数のオーバーフローは起きない。`2^(n-1)`を直接計算しない理由はここにある。

`resolve_429_wait`は次の順で決める。

1. `Retry-After`の値が空なら、既定待機を使い、切り詰めフラグは0
2. 値が上限を超えていれば、上限を使い、切り詰めフラグは1
3. それ以外は値をそのまま使い、切り詰めフラグは0

429の既定待機にも上限を適用する（FR-604）。指数的には増やさない。

#### Retry-Afterの解析

`parse_retry_after`はヘッダー全文を`awk`で読む。busyboxの`awk`でも動く機能だけを使う。

- 行末のCRを除去する
- ヘッダー名を小文字化して`retry-after`と比較する（大文字小文字を区別しない）
- 値の前後の空白を除去する
- 同名が複数あれば最後の値を採用する
- 採用した値が`^[0-9]+$`なら、先頭の0を除去する。除去後が7桁以上なら`1000000`を出力して0を返す
- 6桁以内なら除去後の値を出力して0を返す。桁数の比較だけで判定し、算術に渡さない
- 空、負数、小数、HTTP日付、数字以外を含む値、ヘッダーなしは不在と同じ扱いにして終了コード1を返す

7桁以上は秒数形式に一致するため、不在扱いにせず上限超過として扱う（`spec.md` FR-603、`analyze` A-01）。
`resolve_429_wait`は`1000000`が上限を超えるので切り詰めフラグ1を返す。

#### 設定値の規則

`apply_config_defaults`と`validate_config`は、spec.md 4章の表の順（下記の検査順）で7変数を扱う。

| 規則 | 実装 |
| --- | --- |
| 空文字は未設定と同じ | `${VAR:-}`が空なら既定値を代入する |
| 形式 | `case`で空と非数字を含む値を拒否し、`${#value}`が6を超える値を拒否する |
| 下限 | `CONNECT_TIMEOUT_SECONDS`と`RESPONSE_TIMEOUT_SECONDS`は0を拒否する |
| 先頭0 | `007`のような値は、`$(( ))`で8進数と誤解釈されないよう、検証後に`sed`で先頭の0を除去する |
| タイムアウト整合 | 接続タイムアウトが全体タイムアウトより大きくても拒否しない |

### 3.2 entrypoint.shの処理順

`entrypoint.sh`は次の順に動く。順序はFR-607のプロキシ優先規則に従う。

1. `HTTP_PROXY`が空なら、`CLIENT_ERROR=proxy_not_configured`を標準エラーに出して78で終了する（M04と同じ）
2. `retry-lib.sh`を`. "$(dirname "$0")/retry-lib.sh"`で読み込む
3. `apply_config_defaults`を呼ぶ
4. `validate_config`を呼ぶ。不正なら`CLIENT_ERROR=invalid_config`と`CLIENT_DIAG invalid_config name=<変数名>`を標準エラーに出して78で終了する。値は出さない
5. 一時ディレクトリを作り、`trap`で後始末を登録する
6. リトライループに入る（最初の通信はここ）

1から4までは通信しない。両方が不正な場合は手順1で止まるため、`proxy_not_configured`が優先される。

#### 設定検査の順序

`validate_config`は次の順に検査し、最初の不正変数名だけを報告する。

| 順 | 変数 |
| --- | --- |
| 1 | `RETRY_MAX_ATTEMPTS_5XX` |
| 2 | `RETRY_BACKOFF_BASE_SECONDS` |
| 3 | `RETRY_MAX_ATTEMPTS_429` |
| 4 | `RETRY_429_DEFAULT_WAIT_SECONDS` |
| 5 | `RETRY_MAX_WAIT_SECONDS` |
| 6 | `CONNECT_TIMEOUT_SECONDS` |
| 7 | `RESPONSE_TIMEOUT_SECONDS` |

### 3.3 リトライループ

ループは2つのカウンター`retries_5xx`と`retries_429`を独立に持つ。総試行回数は`attempt`で数える。

1. `attempt`を1増やし、curlを1回実行する（3.4）
2. curl終了コードが28なら、`CLIENT_ERROR=timeout`を標準エラーへ出し、最終結果`timeout`を記録して28で終了する。標準出力は空
3. curl終了コードが0以外なら、M04どおり`CLIENT_ERROR=curl_exit_<rc>`を出して`rc`で終了する。リトライしない
4. `is_retryable_status`が1を返したら、最終結果`success`を記録してループを抜ける（2xxと、301、404などの対象外）
5. 対象で、該当カウンターが上限に達していたら、最終結果`retries_exhausted`を記録してループを抜ける
6. 該当カウンターを1増やし、待機時間を計算する（5xxは`backoff_wait_5xx`、429は`parse_retry_after`と`resolve_429_wait`）
7. 診断ログを出し、`sleep "$wait"`を呼んで、手順1へ戻る

最大リトライ回数0は、手順5が初回で成立するので1回だけ試行して終わる（FR-611）。
`sleep`は待機が0でも呼ぶ。これでスタブの`sleep`記録が待機列と一対一に対応し、検査が単純になる。

ループを抜けた後は、最後のレスポンスの`CLIENT_STATUS`と`CLIENT_BODY`を出力して終了コード0で終わる。
HTTP 404のような対象外ステータスも、最終結果は`success`とする。FR-609の3値に収めるための決定で、
`success`は「通信が完了し、これ以上の再試行が不要」を意味する。

### 3.4 curlオプション

M04のオプションに、タイムアウトとヘッダー出力を足す。

| オプション | 値 | 目的 |
| --- | --- | --- |
| `--noproxy ''` | M04のまま | 環境変数の`NO_PROXY`を無視してプロキシを強制する |
| `--proxy` | `$HTTP_PROXY` | M04のまま |
| `--silent --show-error` | M04のまま | 進捗を消し、エラーは標準エラーへ出す |
| `--connect-timeout` | `$CONNECT_TIMEOUT_SECONDS` | 接続タイムアウト（FR-605） |
| `--max-time` | `$RESPONSE_TIMEOUT_SECONDS` | 1試行あたりの全体タイムアウト（FR-605） |
| `--dump-header` | 試行ごとの一時ファイル | `Retry-After`の取得 |
| `--output` | 試行ごとの一時ファイル | 本文の取得 |
| `--write-out '%{http_code}'` | M04のまま | ステータスの取得 |

接続先はプロキシなので、`--connect-timeout`はクライアントからSquidへの接続に効く。
`--max-time`は1試行の全体に効き、リトライ間の`sleep`は含まない。総所要時間の上限は試行回数、待機、タイムアウトの合計になる。

ヘッダーと本文のファイルは試行ごとに上書きする。`Retry-After`は直前の試行のヘッダーだけを見る。

### 3.5 出力契約

| 出力先 | 内容 |
| --- | --- |
| 標準出力 | 成功終了時だけ`CLIENT_STATUS=<code>`と`CLIENT_BODY=<body>`の2行。診断ログは混ぜない（NFR-604） |
| 標準エラー | `CLIENT_ERROR=<識別子>`と`CLIENT_DIAG ...`の診断ログ |
| 終了コード | 0（HTTP応答を得た場合）、28（タイムアウト）、`rc`（その他のcurl失敗）、78（プロキシ未設定と設定不備） |

診断ログは1行1事象のキー=値形式とする。値に空白を含めない。

| 事象 | 形式の例 |
| --- | --- |
| 5xxのリトライ | `CLIENT_DIAG retry attempt=1 status=503 class=5xx retry=1/3 wait=1` |
| 429で`Retry-After`あり | `CLIENT_DIAG retry attempt=2 status=429 class=429 retry=1/3 retry_after=120 wait=30 capped=1` |
| 429で`Retry-After`なし | `CLIENT_DIAG retry attempt=2 status=429 class=429 retry=1/3 retry_after=none wait=2 capped=0` |
| 最終結果（成功） | `CLIENT_DIAG result=success attempts=1 status=200` |
| 最終結果（上限到達） | `CLIENT_DIAG result=retries_exhausted attempts=4 status=500` |
| タイムアウト | `CLIENT_DIAG result=timeout attempts=1 curl_exit=28` |
| curl失敗 | `CLIENT_DIAG curl_failed attempts=1 curl_exit=7`（`result=`は出さない） |

`result=`の値は`success`、`retries_exhausted`、`timeout`の3種に固定する（FR-609）。
curl失敗は3値に含まれないため、`result=`を持たない行で出し、終了コードで識別する。
診断ログには、設定値、URL、本文、`Retry-After`以外のヘッダーを出さない。

## 4. 検証境界

### 4.1 単体検査

ホストの`sh`で`retry-lib.sh`を読み込み、関数を直接呼ぶ。Docker、curl、ネットワーク、`sleep`を使わない。

| 対象 | ケース |
| --- | --- |
| `is_retryable_status` | 200、301、404、501、502、504は対象外。500、503、429は対象 |
| `backoff_wait_5xx` | base=1でn=1,2,3が1,2,4。上限で打ち切り。base=0は常に0。n=1が上限に等しい |
| `parse_retry_after` | 0、5、上限ちょうど、大文字小文字違いのヘッダー名、CR付き、同名複数は最後 |
| `parse_retry_after`（不在扱い） | 空、負数、小数、HTTP日付、数字以外を含む値、ヘッダーなし |
| `parse_retry_after`（飽和） | 999999は999999、1000000と20桁の数字列は1000000、`0000005`は5、`0000000`は0 |
| `resolve_429_wait` | 上限ちょうど、上限+1（切り詰めフラグ1）、0秒、値なしで既定待機、既定待機が上限超過 |
| `validate_config` | 負数、非数値、小数、7桁以上、タイムアウト0で不正。空文字は既定値。先頭0（`007`）の正規化 |
| 検査順 | 2変数が不正なとき、表の順で先の変数名だけを報告する |

### 4.2 entrypoint検査

テスト用の一時ディレクトリに、スタブ`curl`と`sleep`を作り、PATHの先頭に置く。

| スタブ | 動作 |
| --- | --- |
| `curl` | 引数を記録する。`--output`と`--dump-header`のパスを引数から取り出して書き込み、`--write-out`の位置にステータスを出力する。試行ごとのステータス、ヘッダー、終了コードは、テストが用意する台本ファイルから1行ずつ読む |
| `sleep` | 引数をログに追記して即座に戻る |

検査項目は次のとおり。

| 項目 | 期待 |
| --- | --- |
| 200の1回成功 | `sleep`が0回。標準出力が2行のみ。最終結果`success` |
| 500が続く（回数3、base=1） | 待機列が1,2,4。4試行。`CLIENT_STATUS=500`。終了コード0。最終結果`retries_exhausted` |
| 500の後に200 | 途中で止まる。最終ステータスは200 |
| 503、500の混在 | 5xxカウンターが共有で数えられる |
| 429で`Retry-After`あり、上限超過 | 待機が上限へ切り詰められ、`capped=1`が出る |
| 429で`Retry-After`なし | 既定待機を使い、増加しない |
| 429と500の混在 | カウンターが独立で、各上限で止まる |
| 回数0 | 対象ステータスでも1回で終了。終了コード0 |
| タイムアウト（curl終了コード28） | `CLIENT_ERROR=timeout`、標準出力は空、終了コード28、`sleep`が0回 |
| 接続拒否（curl終了コード7） | `CLIENT_ERROR=curl_exit_7`、終了コード7 |
| curlオプション | 記録した引数に`--connect-timeout`、`--max-time`が設定値で入り、`--noproxy ''`と`--proxy`が維持されている |
| 設定不備 | 通信前に終了コード78。`curl`スタブが呼ばれない。`name=`が出る。値が出ない |
| プロキシ優先 | `HTTP_PROXY`が空かつ設定不備のとき、`proxy_not_configured`だけが出る |
| 標準出力の純度 | すべてのケースで、標準出力に`CLIENT_DIAG`が混ざらない |

### 4.3 Composeスモーク

Composeを使う検査は2か所に分かれる。

| 検査 | 場所 | 内容 |
| --- | --- | --- |
| M04の既存検査 | `tests/m04-test-client.sh` | `/api/error-500`の実行に`-e RETRY_BACKOFF_BASE_SECONDS=0`を足す。検査行は変えない |
| `retry-lib.sh`の存在確認 | `tests/m06-client-resilience.sh`のスモークモード | `docker-compose run --rm --no-deps --entrypoint test test-client -f /usr/local/bin/retry-lib.sh`が成功する |
| リトライ経路の実通信 | 同上 | `/api/error-500`に`RETRY_MAX_ATTEMPTS_5XX=1`、`RETRY_BACKOFF_BASE_SECONDS=0`を指定し、`CLIENT_STATUS=500`と、WireMockの当該URLの呼び出し数が前後で2増えることを確認する |
| タイムアウトの実通信 | `tests/m06-client-resilience.sh`のスモークモード | `RESPONSE_TIMEOUT_SECONDS=1`で`/api/slow-5000`を呼び、`CLIENT_ERROR=timeout`、標準出力が空、終了コード28を確認する |
| busybox上の解析 | 同上 | コンテナ内で`retry-lib.sh`を読み込み、CR付きの`Retry-After`と7桁以上の値を`parse_retry_after`に渡して期待値を確認する |

WireMockの呼び出し数は`POST /__admin/requests/count`で前後の差を取る。ジャーナルのリセットはしない。M03のマッピングも変更しない。

## 5. Composeとコンテナの変更

| 対象 | 変更 |
| --- | --- |
| `docker-compose.yml` | 変更なし。既定値は`retry-lib.sh`が持つため、`environment`に追加しない。上書きは`docker-compose run -e`で行う |
| `Dockerfile.test-client` | 変更あり。`COPY test-client/retry-lib.sh /usr/local/bin/retry-lib.sh`と`chmod 0644`を追加する |
| ベースイメージとパッケージ | 変更なし。`awk`、`sed`、`sleep`、`tr`はalpine 3.20のbusyboxに含まれる |

`retry-lib.sh`は読み込まれるだけなので実行権限は不要。`entrypoint.sh`と同じディレクトリに置き、`dirname "$0"`で見つける。
COPY漏れは実行時に`entrypoint.sh`が起動直後に止まる形で現れるため、スモークの存在確認で検出する。

## 6. 検査スクリプトの構成とライフサイクル

`tests/m06-client-resilience.sh`はM06の検査入口とし、引数でモードを切り替える。

| 引数 | 内容 | Compose |
| --- | --- | --- |
| `unit` | 単体検査（4.1）とentrypoint検査（4.2） | 起動しない。`docker`、`docker-compose`を呼ばない |
| なし、または`smoke` | `unit`に加えて4.3のM06分を実行する | 起動する |

品質ゲートは引数なしで実行するため、`smoke`が実行される。

ライフサイクルの規則は次のとおり。

- `unit`では、`docker-compose`の`down`、`up`、`run`のいずれも呼ばない。`trap`でのComposeの後始末も登録しない
- `smoke`のときだけ、M05と同じく開始前に`down --remove-orphans`、`up -d squid wiremock`、readiness待機を行い、終了時の`trap`で`down`する
- `unit`のモードで`docker-compose`をPATHから外した環境でも通ることを、検査自体の前提にする
- 一時ファイルは`mktemp -d`配下に置き、`trap`で削除する。リポジトリ内に生成物を残さない
- 失敗時は、どの検査が落ちたかを標準エラーに出して非ゼロで終了する

NFR-605の検査ファイルは、analyzeの決定により`tests/m06-client-resilience.sh`の1つに統一した。
spec.mdのNFR-605も同じ記述に直した。

## 7. リスクと対策

| リスク | 対策 |
| --- | --- |
| 先頭に0がある値（`08`）が`$(( ))`で8進エラーになる | `apply_config_defaults`で先頭の0を除去してから算術に使う。`007`と`08`を単体検査に入れる |
| `2^(n-1)`の計算が大きなnでオーバーフローする | 2倍するたびに上限で打ち切る。上限が6桁以内なので桁あふれしない |
| busyboxの`awk`と`sed`がホストのGNU版と挙動が違う | POSIXの機能だけを使う。entrypoint検査はホストで走るため、スモークでもalpine上で同じ解析が通ることを確認する |
| `Retry-After`の解析でCRが残り`^[0-9]+$`に一致しない | 解析の最初にCRを除去する。CR付きのケースを単体検査に入れる |
| スタブ`curl`の引数解析が実際のcurlとずれる | スタブは`--output`、`--dump-header`、`--write-out`だけを解釈する。本番の引数順を変えたときは検査が落ちるようにする |
| `Dockerfile.test-client`のCOPY漏れでコンテナだけが壊れる | スモークで`retry-lib.sh`の存在を確認する |
| 既定のリトライ有効化で、M04の`/api/error-500`が約7秒遅くなる | M04のテストに`RETRY_BACKOFF_BASE_SECONDS=0`を足す。M04の検査行は変えない |
| 呼び出し側が終了コード0だけを見て、リトライ上限到達の失敗を見逃す | 診断ログに`result=retries_exhausted`を残す。契約はclarifyで合意済みで、READMEや呼び出し側への周知は本計画の範囲外 |
| 診断ログに秘密情報が混ざる | URL、本文、ヘッダー全文、設定値を出さない。出すのは数値と固定の識別子のみ |
| `unit`モードで誤ってComposeを起動する | ライフサイクルの規則で分離し、`docker-compose`を使わない環境で実行して確認する |
| 7桁以上の`Retry-After`の扱いがspec.mdと食い違う | 上限超過として切り詰める方式に統一し、桁数の比較だけで判定する。単体検査とbusyboxの検査に入れる |

## 8. 実装単位

依存順に並べる。各単位は、対応する検査が通ってから次へ進む。

| 順 | 単位 | 内容 | 要件 | 検査 |
| --- | --- | --- | --- | --- |
| 1 | 検査入口の骨格 | `tests/m06-client-resilience.sh`の`unit`モードとライフサイクルの規則。最初は失敗するケースから作る | NFR-605 | `unit`がComposeを呼ばずに動く |
| 2 | 対象判定と待機計算 | `is_retryable_status`、`backoff_wait_5xx`、`resolve_429_wait` | FR-601、FR-602、FR-604、FR-610 | 4.1の該当ケース |
| 3 | Retry-After解析 | `parse_retry_after` | FR-603 | 4.1の該当ケース |
| 4 | 設定の既定値と検証 | `apply_config_defaults`、`validate_config` | FR-607 | 4.1の該当ケース |
| 5 | entrypointの前処理 | プロキシ検査、ライブラリ読み込み、設定検査、`invalid_config`出力 | FR-607、NFR-601、NFR-602 | 4.2の設定不備とプロキシ優先 |
| 6 | リトライループ | curl呼び出し、カウンター、`sleep`、上限到達時の出力と終了コード0 | FR-601、FR-602、FR-603、FR-604、FR-610、FR-611 | 4.2のリトライ系 |
| 7 | タイムアウト | `--connect-timeout`、`--max-time`、終了コード28の処理 | FR-605、FR-606 | 4.2のタイムアウトとオプション |
| 8 | 診断ログと出力契約 | `CLIENT_DIAG`の各行、最終結果の3値、標準出力の純度 | FR-608、FR-609、NFR-604 | 4.2の標準出力の純度 |
| 9 | Dockerfile | `retry-lib.sh`のCOPYを追加する | NFR-603、NFR-605 | 次の単位のスモーク |
| 10 | M04スモークの調整 | `/api/error-500`の実行に`-e RETRY_BACKOFF_BASE_SECONDS=0`を足す | NFR-601 | `tests/m04-test-client.sh`が通る |
| 11 | M06スモーク | `smoke`モードの存在確認とリトライ経路の実通信、タイムアウトの実通信、busybox上の解析 | NFR-605 | `m06-client-resilience.sh smoke`が通る |
| 12 | 最終確認 | `unit`と`smoke`、M04、M05の既存検査を順に実行する | 7章の完了条件すべて | 全検査が通る |

## 9. 制約

- 既存のSquid、WireMock、Composeの設定を変更しない
- Test ClientからWireMockへ直接接続しない
- 外部ネットワークへの成功リクエストを送らない
- 本番スクリプトにテスト専用の分岐を入れない
- ジッター、サーキットブレーカー、タイムアウトのリトライ、503の`Retry-After`は実装しない
