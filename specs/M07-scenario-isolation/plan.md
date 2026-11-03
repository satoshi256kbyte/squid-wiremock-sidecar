# M07実装計画

## 1. 実装方針

M07は、WireMockのシナリオを名前で選ぶ仕組みと、テスト間で状態が漏れない隔離手順を足す。
Test Client、Squid、`docker-compose.yml`は変更しない（NFR-702）。
シナリオはすべて`wiremock-scenarios/mappings/`に静的に置き、各スタブのトップレベル`name`で名前を付ける。
名前から宛先パスを引く処理と、リセットとその確認は、POSIX shの共有ヘルパーにまとめる。

検証は、Dockerを使わない層とComposeを使う層に分ける。M06と同じ`unit`と`smoke`の2モードで、既定は`smoke`とする。

| 層 | 対象 | Compose |
| --- | --- | --- |
| `unit` | 名前の解決、静的検査、追加手順の検査 | 使わない |
| `smoke` | `unit`に続けて、リセットと確認、対照実験、通し実行、失敗経路の回収 | 使う |

本番のスクリプトにテスト専用の環境変数や分岐は入れない。失敗の注入は検査内のサブシェルで行う。

## 2. 変更ファイル

| パス | 変更内容 |
| --- | --- |
| `wiremock-scenarios/mappings/normal-case.json` | トップレベルに`"name": "normal"`を1行足す |
| `wiremock-scenarios/mappings/error-429-case.json` | `"name": "ratelimit-429"`を足す |
| `wiremock-scenarios/mappings/delay-100ms-case.json` | `"name": "slow-100"`を足す |
| `wiremock-scenarios/mappings/delay-5000ms-case.json` | `"name": "slow-5000"`を足す |
| `wiremock-scenarios/mappings/error-500-then-200-1.json` | 新規。初回の500（4.2） |
| `wiremock-scenarios/mappings/error-500-then-200-2.json` | 新規。2回目以降の200（4.2） |
| `scripts/scenario-lib.sh` | 新規。名前の解決、リセット、リセット後の確認の関数（5章） |
| `tests/m07-scenario-isolation.sh` | 新規。M07の検査入口（7章） |
| `docs/シナリオ隔離.md` | 新規。一覧、追加手順、隔離の手順、並列禁止の理由、後始末 |
| `README.md` | 「Testing Scenarios」に`docs/シナリオ隔離.md`への参照を1行足す |
| `scripts/quality-gate.sh` | 74行目の検査リストに`tests/m07-scenario-isolation.sh`を足す（7.3） |
| `specs/M07-scenario-isolation/` | M07のSpec Kit成果物 |
| `specs/M07-scenario-isolation/reset-experiment.md` | 新規。リセット実験の記録（3章） |

`__files/`は既存の`error-500.json`と`success.json`を再利用し、新しい本文は足さない。
`error-500-case.json`と`error-503-case.json`には`name`を付けない。

## 3. 最初に行う実機実験（リセットの意味の確認）

`POST /__admin/reset`が何を戻すかは、リポジトリの読み取りでは確定できない（Q-703）。
この結果で、リセット手順、確認手順、`docs/シナリオ隔離.md`の記述が決まる。
そのため、実装単位の最初（8章の単位1）に置き、結果が出るまで5章以降の設計を確定しない。
実験は手動で一度だけ行い、smokeには入れない。$KIROCREW_SCRATCH配下の使い捨てコピーで行い、リポジトリは書き換えない。
結果はreset-experiment.mdに記録して仕様と一緒にコミットする（analyze A-01、A-02）。

### 3.1 実験の手順

使い捨てコピーに docker-compose.yml、squid-config/、wiremock-scenarios/ を複製し、コピー側のmappings/に
4.2の2ファイルと、既存4ファイルへのname追加を入れる。内容は4章と同一にする。
プロジェクト名を明示（docker-compose -p m07-reset-exp）してup -d squid wiremockを行い、127.0.0.1:8080の管理APIを呼ぶ。
開始前にポート3128と8080が空であることを確かめる。手順1で件数がコピーのファイル数と一致しなければ、止めて報告する。

| 順 | 操作 | 観測 |
| --- | --- | --- |
| 1 | `GET /__admin/mappings`と`GET /__admin/scenarios`の応答を保存する | `name`が含まれるか。件数と状態のフィールド名（`meta.total`、`scenarios[].state`など） |
| 2 | `GET /api/error-500-then-200`を2回呼ぶ | 500、200の順。シナリオ状態が`Succeeded` |
| 3 | `POST /__admin/reset`を呼ぶ | 応答のステータス |
| 4 | `GET /__admin/mappings`、`/__admin/requests`、`/__admin/scenarios`を読む | 件数がファイル数と一致するか。ジャーナルが0か。状態がすべて`Started`か |
| 5 | `GET /api/error-500-then-200`を呼ぶ | 500に戻っているか |
| 6 | `POST /__admin/mappings`で、ファイルに無いマッピングを足してから手順3と4を行う | 管理APIで足したものが消えるか |
| 7 | `GET /__admin/requests`の応答の形を保存する | 件数のフィールド名 |

### 3.2 結果による分岐

| 結果 | 決まること |
| --- | --- |
| 3つとも戻る | 5.2の主経路（`POST /__admin/reset`の1回）を採用する |
| マッピングが戻らない | 5.2の代替経路にマッピングの再読み込みを足す |
| ジャーナルが空にならない | 代替経路にジャーナル削除を足す |
| シナリオ状態が戻らない | 代替経路にシナリオ状態のリセットを足す |
| 代替でも戻らない | コンテナ再起動は自分では採らず、ユーザーに確認する（clarify決定） |

代替経路の候補は、3.13.1の管理APIで次の3つである。名前と挙動は実機で確かめてから採用する。

| 目的 | 候補 |
| --- | --- |
| マッピングを初期状態へ | `POST /__admin/mappings/reset` |
| ジャーナルを消す | `DELETE /__admin/requests` |
| シナリオ状態を戻す | `POST /__admin/scenarios/reset` |

どの分岐でもコンテナ再起動は使わない。再起動が要る結果になった場合は、そこで作業を止めて報告する。

### 3.3 同じ実験で取る値

| 値 | 使い道 |
| --- | --- |
| `GET /__admin/mappings`の件数フィールド名と`name`の有無 | FR-709のパース方法、`smoke`の整合検査 |
| `GET /__admin/scenarios`の状態フィールド名 | FR-709のパース方法 |
| `GET /__admin/requests`の件数フィールド名 | FR-709のパース方法 |
| ファイル追加後に、リセットで反映されるか（Q-704） | `docs/シナリオ隔離.md`の追加手順 |

ファイル追加の確認では、コピー側にzz-tmp.jsonを足して確かめ、コピーごと破棄する。
リポジトリのgit status --shortが実験の前後で変わらないことを確かめる。name追加後のM03検査はT702で行う。

### 3.4 結果の記録

結果はspecs/M07-scenario-isolation/reset-experiment.mdに日本語で記録する。節は環境、実験に使ったファイル、観測、値、
分岐の決定、後続への影響とする。5.2のフィールド名と呼び出し列は、このファイルの値で固定する。
planには観測値を書かない。分岐が主経路のみでない場合に限り、5.2の代替経路の1行を直す。

## 4. シナリオの構成

### 4.1 名前とパス

名前の形式は`^[a-z0-9][a-z0-9-]*$`とする。対応は次のとおり（FR-701から705）。

| 名前 | パス | ファイル |
| --- | --- | --- |
| `normal` | `/api/users/123` | `normal-case.json`（`name`追加） |
| `error-500-then-200` | `/api/error-500-then-200` | `error-500-then-200-1.json`、`-2.json`（新規） |
| `ratelimit-429` | `/api/ratelimit` | `error-429-case.json`（`name`追加） |
| `slow-100` | `/api/slow-100` | `delay-100ms-case.json`（`name`追加） |
| `slow-5000` | `/api/slow-5000` | `delay-5000ms-case.json`（`name`追加） |

### 4.2 状態遷移のマッピング（2ファイル）

どちらもトップレベルの`name`は`error-500-then-200`とする。`scenarioName`も同じ値にする。

| ファイル | `requiredScenarioState` | `newScenarioState` | 応答 |
| --- | --- | --- | --- |
| `error-500-then-200-1.json` | `Started` | `Succeeded` | 500、`error-500.json`、`Content-Type: application/json` |
| `error-500-then-200-2.json` | `Succeeded` | なし | 200、`success.json`、`Content-Type: application/json` |

2ファイルとも、`request.method`は`GET`、`request.urlPath`は`/api/error-500-then-200`とする。
M03の検査が見る`request.method`、`request.urlPath`、`response.status`を満たすため、M03の検査は変えない。
2回目以降は`Succeeded`のまま200を返し続ける。

### 4.3 検討して採らなかった方式

| 方式 | 採らない理由 |
| --- | --- |
| 選択時に管理APIでマッピングを投入する | 失敗時に中途半端なマッピングが残る。リセットの確認も複雑になる |
| 選択時にファイルを差し替える | `:ro`の変更かホスト側の書き換えが要る（Q-702、Q-704） |
| `mappings`配列の1ファイル形式 | M03の検査が拒否する。件数の数え方も変わる |

## 5. 共有ヘルパー`scripts/scenario-lib.sh`

### 5.1 配置と形式

置き場所は`scripts/scenario-lib.sh`とする。理由は次のとおり。

| 観点 | 判断 |
| --- | --- |
| 利用側 | M08のE2Eが再利用する。`tests/`は検査入口、`scripts/`は共有部品という既存の分け方に合う |
| ゲート | `scripts/quality-gate.sh`の50行目は`scripts/*.sh`も構文検査の対象にする。追加の登録は要らない |
| 実行権限 | `source`されるだけなので実行権限は不要。`tests/m06`が`retry-lib.sh`を読む形と同じ |

POSIX shで書き、配列、`[[ ]]`、`local`、プロセス置換は使わない。読み込み時に副作用を持たない。
JSON解析はM03と同じホストの`python3`を使い、`jq`などの新しい依存は足さない（NFR-704）。
`python3`へは値をコマンドライン引数で渡し、シェル展開で組み立てたコードに埋め込まない。

### 5.2 関数

| 関数 | 入力 | 出力と終了コード |
| --- | --- | --- |
| `scenario_path` | 名前、マッピングのディレクトリ（省略時は`wiremock-scenarios/mappings`） | 一致する`name`のスタブの`request.urlPath`を出力して0 |
| `scenario_names` | マッピングのディレクトリ | 定義済みの名前を昇順で1行ずつ出力 |
| `scenario_check_static` | マッピングのディレクトリ | 名前の形式、パス重複、状態グループの静的検査。不正なら理由を標準エラーへ出して1 |
| `wiremock_reset` | なし（`WIREMOCK_URL`） | リセットの呼び出し列を実行。失敗したら1 |
| `wiremock_verify_reset` | マッピングのディレクトリ | 3項目の確認。不一致なら項目名と期待値と実測値を標準エラーへ出して1 |

`scenario_path`の規則は次のとおり（FR-701）。

- 名前が`^[a-z0-9][a-z0-9-]*$`に合わなければ、未定義と同じ扱いにする
- 未定義なら`unknown scenario: <名前>`と`scenario_names`の一覧を標準エラーへ出して、終了コード2を返す
- 同じ名前のスタブが異なる`method`または`urlPath`を持つなら、終了コード1で失敗する
- 既定シナリオへフォールバックしない
- 標準エラーに出す名前はそのまま出さず、制御文字を除いてから出す

`wiremock_reset`の主経路は`POST /__admin/reset`の1回とする。3章の実験で戻らない項目が出たら、
その項目に対応する個別エンドポイントを同じ関数の中で続けて呼ぶ。コンテナの再起動は含めない。

`wiremock_verify_reset`は次の3項目を、管理APIの応答から読む（FR-709）。
フィールド名は`reset-experiment.md`の値で固定する。

| 項目 | 期待 |
| --- | --- |
| マッピング件数 | `mappings/*.json`のファイル数（`.gitkeep`を除く）と一致 |
| ジャーナル件数 | 0 |
| シナリオ状態 | すべて`Started` |

読み取れない、または不一致なら、関数は非ゼロで返す。呼び出し側は`set -e`で止め、続行しない。

### 5.3 テストごとの使い方

各テストは、開始前に`wiremock_reset`と`wiremock_verify_reset`を呼び、終了時の`trap`でもう一度呼ぶ（FR-707、FR-708）。
失敗経路では、後始末の中のリセットが失敗しても、Composeの回収を妨げない。
後始末のリセットの前後に、標準エラーへ`cleanup: reset attempted`と結果を1行出す（FR-708の観測用）。

## 6. 検証境界と後始末

### 6.1 `unit`

Dockerとネットワークを使わない。`docker-compose`をPATHから外した環境でも通ることを前提にする。

| 検査 | 内容 |
| --- | --- |
| 名前の解決 | 5名の宛先、未定義の名前の終了コード2と一覧、形式違反、大文字、空文字 |
| 重複 | 同名で異なるパスの拒否、全スタブの`method`と`urlPath`の組がグループ外で重複しない |
| 状態グループ | spec.md 5.3の6検査。不正な一時ファイルを足して、それぞれ拒否されることも確かめる |
| 既存マッピング | 4ファイルの`name`と、2ファイルの構成が4章のとおり |
| 追加手順 | `mktemp -d`へ`wiremock-scenarios/`をコピーし、文書の手順どおりに1ファイルを足して解決と静的検査が通る |
| 文書の内容 | `docs/シナリオ隔離.md`に並列禁止の節と4項目の語があり、識別情報のパターン（12桁の数字、`arn:aws`）がない |

リポジトリのファイルは書き換えない。一時ディレクトリは`trap`で削除する。

### 6.2 `smoke`

`unit`が落ちたらComposeを起動しない。ライフサイクルはM06の`run_smoke`と同じ方式にする。

| 項目 | 方式 |
| --- | --- |
| 開始前 | `docker-compose down --remove-orphans`、`up -d --build squid wiremock`、readiness待機 |
| 後始末 | `EXIT`の`trap`で、失敗時のログ出力、リセットの試行、`down --remove-orphans`、一時ディレクトリの削除。終了コードを保つ |
| 中断 | `INT`は`exit 130`、`TERM`は`exit 143`で`EXIT`の後始末へ入る。値は実機で観測して確定する |
| 回収の確認 | 最後に`docker-compose ps -a -q`が空であることを確かめる |

`smoke`の検査は次の順に行う。

1. 開始前のリセットと確認（`wiremock_reset`、`wiremock_verify_reset`）
2. 管理APIの`name`と`request.urlPath`が、`scenario_path`の結果と一致する
3. 対照実験。リセットなしで`error-500-then-200`を2回続けて呼ぶと、2回目が初回から200になる。リセットを挟むと500に戻る
4. M06のTest Clientを`TEST_API_PATH=/api/error-500-then-200`で実行し、`CLIENT_STATUS=200`、最終結果`success`、総試行2回
5. 続けてもう一度、リセットを挟んで実行し、同じ結果になる（FR-706）
6. 4シナリオ（`normal`、`ratelimit-429`、`slow-100`、`slow-5000`）の応答と、Squid経由の到達
7. `ratelimit-429`で、診断ログの待機2秒と`wiremock_count`による呼び出し回数
8. 失敗経路（6.3）
9. 手順3から7を同じ起動のまま2周し、結果が同じであることを確かめる。スクリプトは再起動しない

### 6.3 失敗経路の検査

失敗の注入は、検査内のサブシェルで本物の検査入口を子として起動して行う。本番のスクリプトに注入用の分岐は入れない。

| 経路 | 方法 | 確認 |
| --- | --- | --- |
| アサーション失敗 | 子のシェルに、必ず落ちるアサーションを渡す | 終了コードが元の非ゼロを保つ。子の標準エラーにリセット試行の記録がある |
| `INT` | 子の起動後に`kill -INT`を送る | 終了コードが130。回収済み |
| `TERM` | 同様に`kill -TERM`を送る | 終了コードが143。回収済み |

どの経路でも、`docker-compose ps -a -q`が空であること、一時ディレクトリが残らないことを確かめる。
子の一時ディレクトリは、`mktemp -d`で親が名前を知れる場所に作らせ、後から存在を調べる。
`INT`と`TERM`は`sh`が待機中のコマンド終了後にトラップを処理するため、子は`sleep`を前景で待たずに
短い間隔のポーリングにして、シグナルに速く反応させる。

## 7. 既存検査との関係

### 7.1 M03とM06

`name`の追加と新しいスタブの追加の後で、`tests/m03-wiremock-scenarios.sh`と`tests/m06-client-resilience.sh`を実行する。
M03はマッピング数を数えないため、スタブの追加で落ちない。`/api/error-500`は常に500を返し、M06の呼び出し回数検査を保つ。

### 7.2 並列実行

M07の検査は、1台のWireMockに対して並列実行しない。docker-composeのポート3128と8080は固定で公開されるため、
並列に走らせると後始末の`down`が互いのコンテナを落とす。`docs/シナリオ隔離.md`に理由を表で書く（FR-712）。

### 7.3 品質ゲート

`scripts/quality-gate.sh`の74行目は、検査を明示的に列挙している。`tests/*.sh`の構文検査は自動で拾われるが、
実行は列挙に足さない限りされない。M07の検査を足す必要がある。足す位置はM06の後ろとする。

## 8. リスク

| リスク | 対策 |
| --- | --- |
| `POST /__admin/reset`が一部しか戻さない | 3章で最初に確かめる。毎回`wiremock_verify_reset`で確認し、不一致なら止める |
| リセットが管理APIで足したマッピングも消す | 意図した挙動。ファイル由来だけが残ることを3章の手順6で確かめる |
| 前のテストのシナリオ状態が次へ漏れる | 開始前と終了後のリセット。対照実験で漏れの再現と解消を示す |
| 異常終了でリセットが走らず、状態が残る | 次のテストの開始前リセットが拾う。後始末で`down`するのでコンテナごと消える |
| `name`追加がM03の検査やWireMockに影響する | 3章で`name`の返却とM03の検査を実機で確認する |
| 管理APIの応答のフィールド名の思い込み | 3章の実機の応答でパース方法を固定してから書く |
| 状態グループの片方だけを編集して遷移が壊れる | `unit`の静的検査（状態の網羅、遷移の到達性、宛先の一致） |
| 3128と8080がホストの全インターフェースで公開される | Issue 14で追跡済み。M07では変更せず、`docker-compose.yml`に触れない |
| `INT`と`TERM`で子がすぐ終わらず検査が固まる | 子はポーリング待機にし、検査全体に上限時間を設ける |
| 失敗経路の検査が残骸を残す | 親の`trap`でも子のコンテナと一時ディレクトリを回収する |
| 公開物にアカウントIDや認証情報が混ざる | 文書と出力は`api.example.com`などのダミー値だけにする（NFR-706） |

## 9. 実装単位

依存順に並べる。各単位は、対応する検査が通ってから次へ進む。
単位1の結果が出るまで、単位3以降の細部（5章の関数、パース方法、`wiremock_reset`の呼び出し列）を確定しない。

| 順 | 単位 | 内容 | 要件 | 検査 |
| --- | --- | --- | --- | --- |
| 1 | リセット実験 | 使い捨てコピーで3章の実験を行い、reset-experiment.mdに記録して設計を確定する | FR-707、FR-709 | reset-experiment.mdに全節があり、3.1の観測が揃い、分岐が決まる。リポジトリのgit statusが変わらない |
| 2 | マッピング | 4章の`name`追加と2ファイルの新規作成 | FR-701から705、NFR-701 | M03の検査が通る。`name`の値と2ファイルの本文が`reset-experiment.md`の記録と一致する |
| 3 | 検査入口の骨格 | `tests/m07-scenario-isolation.sh`の`unit`と`smoke`の枠、後始末の規則 | FR-710 | `unit`がComposeを呼ばずに動く |
| 4 | 名前の解決 | `scenario_path`、`scenario_names`と`unit`の検査 | FR-701、FR-702、FR-705 | `unit`の名前の解決と重複 |
| 5 | 静的検査 | `scenario_check_static`と不正ファイルの拒否 | FR-703 | `unit`の状態グループ |
| 6 | リセットと確認 | `wiremock_reset`、`wiremock_verify_reset`（単位1の結果に従う） | FR-707、FR-708、FR-709 | `smoke`のリセットと確認 |
| 7 | 通し実行と対照実験 | 「500の後に200」、4シナリオ、連続実行、Squid経由 | FR-702から706、NFR-705 | `smoke`の3から7 |
| 8 | 失敗経路 | アサーション失敗、`INT`、`TERM`の回収と終了コード | FR-710 | `smoke`の失敗経路 |
| 9 | 文書 | `docs/シナリオ隔離.md`と`README.md`の参照。追加手順の`unit`検査 | FR-711、FR-712 | `unit`の追加手順 |
| 10 | 品質ゲート | `scripts/quality-gate.sh`に検査を登録 | NFR-702 | ゲートが通る |
| 11 | 最終確認 | M07の`unit`と`smoke`、M03とM06の既存検査を順に実行 | 7章の完了条件すべて | すべて通る |

## 10. 制約

- `docker-compose.yml`、Squid、Test Clientのコードを変更しない
- 初期化は管理APIだけで行い、コンテナ再起動とファイル置換は使わない
- 本番のスクリプトにテスト専用の分岐を入れない
- 検査はリポジトリのファイルを書き換えない
- 外部ネットワークへ出ない。通信は閉じたネットワークと`127.0.0.1`だけ
- 1台のWireMockに対して並列に実行しない
