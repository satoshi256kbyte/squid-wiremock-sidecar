# S14実装タスク

## 1. 進め方

`plan.md` 7章の11実装単位（U1からU11）を、T1401からT1411に対応させる。
タスクの並びは、実機確認、変更、検査、文書、M02 smoke、品質ゲート登録、最終確認の順にする。
そのため、`plan.md`の単位番号の順（U2、U3、U4、U5、U6、U7、U8、U9、U10、U11）とは並びが一部異なる。
各タスクは、対応する検査が通ってから次へ進む。検査は、先に失敗するケースを確かめてから実装する。

タスクと`plan.md` 7章の単位の対応は次のとおり。

| タスク | 単位 | 内容 |
| --- | --- | --- |
| T1401 | U1 | 実機確認の先行（ゲート） |
| T1402 | U3 | Squidの送信元ACL |
| T1403 | U2 | Composeのポート変更 |
| T1404 | U4 | 検査入口の`static`モード |
| T1405 | U5 | 検査入口の`live`モード |
| T1406 | U7 | `docs/ポート公開範囲.md`の新規作成 |
| T1407 | U8 | `README.md`と`docs/シナリオ隔離.md`の更新 |
| T1408 | U9 | M02 smokeの個別実行と契約影響の記録 |
| T1409 | U10 | セキュリティレビュー |
| T1410 | U6 | 品質ゲートへの登録 |
| T1411 | U11 | 最終確認 |

### 1.1 実機確認のゲート

T1401は最初に行うゲート付きタスクである。結果が出るまで、結果に依存するタスクへ着手しない。
結果は`specs/S14-compose-port-binding/live-check.md`だけに記録する。
このファイルが、実機で得た結果の唯一の記録である。PR本文、コミットログ、ほかのspec文書には、実機の値を写さない。

| 確認項目（`plan.md` 8章） | 内容 | 依存するタスク | 失敗した場合 |
| --- | --- | --- | --- |
| Q-002の利用者確認 | 許可ネットワークを採用しない決定は、利用者が承認済み（2026-11-03、R-11） | T1402以降のすべて | 「採用する」に変わったら、作業を止めて`plan.md`の見直しを報告する |
| 8.1 Test Client経由の許可 | 送信元ACLを通った許可ドメインの要求が成功する | T1402 | `acl local_src`の範囲を見直す。T1402の前に止めて報告する |
| 8.2 Linux CIの送信元 | ループバック経由の送信元がACLの範囲に入る | T1405の完了判断 | Linux環境がなければ「未確認」と記録し、M09への引き継ぎにする。R-02を残リスクにする |
| 8.3 `squid -k parse`の終了コード | WARNINGだけの場合の終了コードと、未定義のディレクティブの終了コード | T1405 | 終了コードと文字列の両方で判定する（実測では、未定義のディレクティブは終了コード1で文字列なし） |
| 8.4 `docker-compose config --format json` | `target`、`published`、`host_ip`のキーが得られる | T1404 | 使えない場合は、`plan.md`の4.3を直してから進める |
| 8.5 一時ディレクトリのマウント | リポジトリ直下の写しがsquidコンテナから見える | T1405 | 見えない場合は、`docker-compose cp`で設定を入れる方式に直す |

Dockerが使えない環境では、その項目を「未確認」と記録して止め、利用者に報告する。
8.2だけは、「未確認」でも他のタスクを止めない（`plan.md` 8.2）。

### 1.2 並列実行の可否と、タスクが所有するファイル

各ファイルは、表に挙げたタスクだけが編集する。ほかのタスクは読むだけにする。

| ファイル | 編集するタスク |
| --- | --- |
| `specs/S14-compose-port-binding/live-check.md` | T1401のみ（唯一の実機結果の記録） |
| `squid-config/squid.conf` | T1402のみ |
| `docker-compose.yml` | T1403のみ |
| `tests/s14-compose-port-binding.sh` | T1404、T1405、T1407（文書の検査を足す） |
| `docs/ポート公開範囲.md` | T1406のみ |
| `README.md`、`docs/シナリオ隔離.md` | T1407のみ |
| `specs/S14-compose-port-binding/contract-impact.md` | T1408のみ |
| `specs/S14-compose-port-binding/security-review.md` | T1409のみ |
| `scripts/quality-gate.sh` | T1410のみ |

並列にできるのはT1402とT1403だけである。編集するファイルが異なり、どちらもDockerを起動せず、
どちらもT1401の完了後に着手できる。

それ以外は並列に実行しない。理由は次のとおり。

- T1404、T1405、T1407は同じ検査ファイルを編集する
- T1401、T1405、T1408、T1410、T1411は、Composeのポート3128と8080を使う
- 実通信を伴う検査どうしは、ポートを取り合うため、1つずつ順に実行する

### 1.3 検査の順序についての補足

`plan.md` 7章では、U4（`static`）がU7、U8（文書）より前に並ぶ。
`static`は文書の記述も確かめるため、T1404の時点では文書の検査を入れない。
文書の検査は、文書が揃うT1407で足し、`static`を再実行して通す。

`static`の誤検出と検出漏れの確認（`plan.md` 6章R-06）は、リポジトリの外の`mktemp -d`配下に
必要なファイルの写しを作り、写しの側で検査を実行して行う。本番のファイルと検査スクリプトに、
テスト専用の分岐は入れない。

### 1.4 一時ファイルの後始末の規則

範囲外の送信元を作る検査（`plan.md` 4.3の手順aからe）は、Squidの設定の写し（以下、deny用の写し）を作る。
deny用の写しは、次の規則で扱う。T1401（8.5の確認）とT1405で、同じ規則を守る。

1. 写しを作る場所は、リポジトリ直下の使い捨てディレクトリ`.s14-deny.<PID>`だけにする。
   `<PID>`は検査を実行するシェルのプロセスIDで、名前の形式は固定する。
   リポジトリ直下に置く理由は、VM型ランタイムでホストの一時ディレクトリがマウントされない場合があるためである（R-05）。
   8.5の結果が「見えない」でない限り、ほかの場所には作らない
2. 写しは、必要な場合にだけ作る。必要な場合とは、8.5の確認と、`live`の順9である。
   ほかのタスクでは作らない
3. 検査スクリプトは、`cleanup`関数で、自分が作った`.s14-deny.<PID>`だけを`rm -rf`する。
   `trap cleanup EXIT`に加え、`trap 'exit 130' INT`と`trap 'exit 143' TERM`を置き、シグナルで`exit`して
   `EXIT`の`trap`を必ず通す。`.s14-deny.*`のような広い名前のパターンで、他のディレクトリを消さない。
   変数は作成後にだけ設定し、空でないことを確かめてから消す
4. `.gitignore`は変更しない。`plan.md`の変更ファイル一覧に`.gitignore`がないためである。
   後始末は`trap`だけに頼り、`.gitignore`への追加は採らない（Why not: 無視すると消し残しが見えなくなる）
5. 写しは、`git add`、`git add -A`、`git add .`の対象にしない。ステージングは、この工程では一切行わない
6. 写しは、実行が終わったら必ず消えている状態にする。正常終了、失敗終了、中断（`INT`、`TERM`）のどれでも消える。
   観測では、`TERM`による終了で`EXIT`の`trap`を、macOSの`sh`とbashは実行したが、`dash`は実行しなかった。
   そのため、中断の確認は、スクリプトが使う`sh`で行う（T1405）
7. 各タスクの終了時と、T1411で、消し残しがないことを次の2つで確かめる。
   `git status --short | grep -F '.s14-deny.'`が何も出力しない（`grep`の終了コードが1）ことと、
   `ls -d .s14-deny.* 2>/dev/null`が空であること。未追跡のディレクトリは`?? .s14-deny.<PID>/`と表示され、
   行頭が`.s14-deny.`ではないため、行頭が一致する書き方は使わない。
   残っていたら、中身を確認してから`rm -rf`で消し、残った原因を直す。
   `SIGKILL`で止めた場合は捕捉できないため、この規則で手動で回収する
8. 写しの中身は、`squid.conf`の写しと上書き用のComposeファイルだけにする。識別情報を書かない

## 2. タスク一覧

| ID | タイトル | 単位 | 要件 | 依存 | 並列 | 検査コマンド |
| --- | --- | --- | --- | --- | --- | --- |
| T1401 | 実機確認の先行（ゲート） | U1 | FR-005、FR-006、FR-008 | なし | 不可 | `git diff --stat`が空で、`git status --short -uall`の前後の差が`live-check.md`の追加だけである。`live-check.md`に8.1、8.3、8.4、8.5が記録されている |
| T1402 | Squidの送信元ACL | U3 | FR-005、NFR-003 | T1401 | T1403と並列可 | `grep -Fx 'http_access allow local_src api_domains' squid-config/squid.conf` |
| T1403 | Composeのポート変更 | U2 | FR-001、FR-002、FR-003、NFR-002 | T1401 | T1402と並列可 | `docker-compose config --quiet`と`docker-compose config`の`host_ip`が2件 |
| T1404 | 検査入口の`static`モード | U4 | FR-003、FR-005、FR-008、NFR-001、NFR-002、NFR-003、NFR-005、NFR-006 | T1402、T1403 | 不可 | `sh tests/s14-compose-port-binding.sh static` |
| T1405 | 検査入口の`live`モード | U5 | FR-003、FR-005、FR-006、FR-008、NFR-005、NFR-006、NFR-007 | T1404 | 不可 | `sh tests/s14-compose-port-binding.sh live` |
| T1406 | `docs/ポート公開範囲.md`の新規作成 | U7 | FR-004、FR-010、FR-011、NFR-006、NFR-008 | T1405 | 不可 | `npm run lint:md` |
| T1407 | `README.md`と`docs/シナリオ隔離.md`の更新 | U8 | FR-010、NFR-008 | T1406 | 不可 | `sh tests/s14-compose-port-binding.sh static`と`npm run lint:md` |
| T1408 | M02 smokeの個別実行と契約影響の記録 | U9 | FR-007、FR-009、NFR-001 | T1407 | 不可 | `sh tests/m02-routing-smoke.sh`（スタック起動後） |
| T1409 | セキュリティレビュー | U10 | FR-012、NFR-004、NFR-006 | T1408 | 不可 | 4つの確認項目に結果がある。`npm run lint:md` |
| T1410 | 品質ゲートへの登録 | U6 | FR-013 | T1409 | 不可 | `grep -n 's14-compose-port-binding' scripts/quality-gate.sh` |
| T1411 | 最終確認 | U11 | FR-007、FR-013、NFR-007、NFR-008、全体 | T1410 | 不可 | `sh scripts/quality-gate.sh`が成功。`git diff --stat`が計画の範囲内 |

## 3. タスク

### T1401: 実機確認の先行（ゲート）

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-005、FR-006、FR-008（`plan.md` 7章U1） |
| 触るファイル | `specs/S14-compose-port-binding/live-check.md`（新規）。リポジトリのほかのファイルは書き換えない。例外は8.5の`.s14-deny.<PID>`だけで、終了時に消す |
| 依存 | なし |
| 並列 | 不可（Composeのポートを使う。以降の全タスクのゲート） |
| 検査 | 1.1の表の結果が、8.1、8.3、8.4、8.5と、可能なら8.2について記録されている。`git diff --stat`が空で、`git status --short -uall`の前後の差が`live-check.md`の追加だけである（`-uall`は未追跡ディレクトリの中のファイルも1行ずつ出す） |

- Q-002は利用者承認済み（採用しない）であることを、作業の最初に確かめる
- 実験の前に、`git diff --stat`と`git status --short -uall`の出力を保存する
- 8.1、8.3、8.4、8.5の手順3は、リポジトリの外の`$KIROCREW_SCRATCH`配下の使い捨てコピーで行う。コピーにT1402とT1403相当の変更を入れる
- 隔離条件: 開始前に`docker-compose ps -a -q`が空で、ポート3128と8080が空いていることを確かめる。使用中なら止めて報告する
- 隔離条件: `docker-compose -p`でプロジェクト名を明示し、終了時に同じ名前で`down --remove-orphans`する
- 隔離条件: 最初に、コピーの`/__admin/mappings`の件数と`squid.conf`の中身がコンテナから見えることを確かめる。見えなければコピーを`$HOME`配下へ移す
- 8.1: 許可ドメインのマッピングを投入し、Test Client経由の要求が200になること、アクセスログの判定が`TCP_MISS`であることを確かめる
- 8.1: 許可外ドメインが拒否されることを確かめる。アドレスの値は記録せず、範囲に入ったかだけを書く
- 8.3: 現行と変更後の設定で、`squid -k parse`の終了コードと出力を記録する。未定義のディレクティブを足した写しの終了コードと出力も記録する（ERRORとFATALの文字列が出ない場合も、そのまま記録する）
- 8.4: `docker-compose config --format json`で、`target`、`published`、`host_ip`が得られるかを確かめる
- 8.5の手順1と2: 使い捨てコピーではなく、実際のリポジトリ直下で行う（T1405が使う場所のマウントを確かめるため）。1.4の規則に従い、`.s14-deny.<PID>`に置いた写しがsquidコンテナから見えるかを確かめる
- 8.5の手順3: 同じ確認を`mktemp -d`配下でも行い、見えるかどうかを将来の利用者向けの注意として残す
- 8.2: Linux環境があれば行う。なければ「未確認」と記録し、M09への引き継ぎとR-02の残リスクを書く
- `live-check.md`は、環境、手順、観測、結論の順に書く。識別情報（アドレス、ホスト名）は書かない
- 終了時に`docker-compose down --remove-orphans`で回収し、使い捨てコピーと`.s14-deny.<PID>`を消す
- 終了後、保存した出力と比べる。`git diff --stat`が空で、`git status --short -uall`の差が`live-check.md`の追加だけであること。
  1.4の規則7の2つの確認も行う
- 実験と記録は、同じセッションで完了する

### T1402: Squidの送信元ACL

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-005、NFR-003 |
| 触るファイル | `squid-config/squid.conf` |
| 依存 | T1401（8.1が成功していること） |
| 並列 | T1403と並列可（編集ファイルが異なり、どちらもDockerを使わない） |
| 検査 | `grep -Fx 'acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16' squid-config/squid.conf`と`grep -Fx 'http_access allow local_src api_domains' squid-config/squid.conf`が1行ずつ一致する。`grep -Fx 'http_access allow api_domains' squid-config/squid.conf`が見つからない |

- `acl api_domains`の宣言の直後に、`acl local_src`の1行を足す
- `http_access allow api_domains`を`http_access allow local_src api_domains`へ置き換える
- `http_access deny all`、`cache deny all`、`acl all src all`、`cache_peer`、`never_direct`の各行は変えない
- コメントにはWhy notを書く。サブネットを固定しない理由（Dockerが動的に割り当てる。`ipam`での固定はNFR-002に反する）を書く
- コメントには、`acl all src all`を消さない理由（組み込みの`all`と重複するWARNINGは動作に影響せず、目的外の変更になる）も書く
- `git diff squid-config/squid.conf`で、ACLの1行、置き換えの1行、コメントだけが変わったことを確かめる
- `whitelist.txt`は変更しない（NFR-003）

### T1403: Composeのポート変更

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-001、FR-002、FR-003、NFR-002 |
| 触るファイル | `docker-compose.yml` |
| 依存 | T1401 |
| 並列 | T1402と並列可 |
| 検査 | `docker-compose config --quiet`が成功する。`docker-compose config`の出力で、squidの3128とwiremockの8080に`host_ip: 127.0.0.1`が付いている |

- squidの`ports`を`"127.0.0.1:3128:3128"`、wiremockの`ports`を`"127.0.0.1:8080:8080"`に置き換える
- ほかの行には触れない。サービス名、ネットワーク名`sidecar`、マウント（`:ro`を含む）、環境変数、コンテナ内のポートは不変にする
- `test-client`に`ports`を足さない
- ホストIPを環境変数にしない。`::1`を公開しない（Q-001）
- `git diff docker-compose.yml`で、変更が2行だけであることを確かめる

### T1404: 検査入口の`static`モード

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-003、FR-005、FR-008、NFR-001、NFR-002、NFR-003、NFR-005、NFR-006 |
| 触るファイル | `tests/s14-compose-port-binding.sh`（新規） |
| 依存 | T1402、T1403。8.4の結果（T1401） |
| 並列 | 不可（T1405とT1407が同じファイルを編集する） |
| 検査 | `sh tests/s14-compose-port-binding.sh static`が成功する。`sh -n tests/s14-compose-port-binding.sh`が成功する。壊した写しに対して失敗する |

- `#!/bin/sh`と`set -eu`で始める。配列、`[[ ]]`、`local`、プロセス置換は使わない
- 引数は`static`、`live`、なし（両方）の3通りにする。それ以外は使い方を出力して終了コード2で終わる
- `live`は、このタスクでは枠だけを置き、中身はT1405で足す
- `static`は、`docker-compose config --format json`の出力を、標準入力の`<<'PY'`で`python3`に読ませる（8.4の結果に従う）
- 公開範囲: squidの3128とwiremockの8080に、`host_ip`が`127.0.0.1`の要素が1件だけあり、ほかのサービスの`ports`が空である
- 契約の不変: サービス名3件、ネットワーク`sidecar`、`read_only`の`true`、Test Clientの環境変数4件を確かめる
- Squid設定: `grep -Fx`で、`acl local_src`の行、`http_access allow local_src api_domains`、`http_access deny all`、`cache deny all`を確かめる
- Squid設定: `grep -Fxq 'http_access allow api_domains'`が見つからないことを確かめる
- `whitelist.txt`の有効な行が、`api.example.com`と`api-staging.example.com`の2件であることを確かめる
- 識別情報: 変更対象のファイルに、12桁の数字列、`arn:aws`、`AKIA`、`aws_secret`がないことを`grep -E`で確かめる
- 失敗した検査の名前を標準エラーへ出し、最後に終了コード1で終わる
- 文書の検査はこのタスクでは入れない（1.3）
- 検査のパスは、スクリプトの位置から決める`ROOT`からの相対だけにする。絶対パスの固定と、テスト専用の分岐や環境変数は入れない
- 識別情報の検査の対象は、`plan.md` 4.3の固定一覧とする。存在しないファイルは読み飛ばし、`tests/s14-compose-port-binding.sh`自身は対象に入れない。
  方法は`tests/m07-scenario-isolation.sh`と同じ`grep -E '[0-9]{12}|arn:aws'`に`AKIA`と`aws_secret`を足したもので、検査出力も一時ファイルに保存して同じパターンで確かめる
- 検出の確認: リポジトリの外の`mktemp -d`配下に写しを作る。写すものは、Compose、`squid-config/`、`Dockerfile`類、`test-client/`、`tests/s14-compose-port-binding.sh`である。
  `0.0.0.0`公開の写しと`acl local_src`の行を欠いた写しを作り、写しのディレクトリでスクリプトを実行して失敗することを確かめる
- 確認は補助シェルで行い、そのシェルの`trap 'rm -rf "$tmp"' EXIT INT TERM`で`mktemp -d`のディレクトリを消す。リポジトリ直下には作らない

### T1405: 検査入口の`live`モード

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-003、FR-005、FR-006、FR-008、NFR-005、NFR-006、NFR-007 |
| 触るファイル | `tests/s14-compose-port-binding.sh` |
| 依存 | T1404。8.3と8.5の結果（T1401） |
| 並列 | 不可（Composeのポートを使う） |
| 検査 | `sh tests/s14-compose-port-binding.sh live`が成功する。連続して2回実行しても結果が同じ。実行後に`docker-compose ps -a -q`が空で、1.4の規則7の2つの確認（`git status --short \| grep -F '.s14-deny.'`が空、`ls -d .s14-deny.*`が空）が通る。`TERM`を送る確認（下記）が通る |

- `cleanup`関数に、`docker-compose down --remove-orphans`と、自分が作った`.s14-deny.<PID>`の削除を入れる。
  `trap cleanup EXIT`、`trap 'exit 130' INT`、`trap 'exit 143' TERM`を置く（1.4の規則3）
- 開始時にも`docker-compose down --remove-orphans`を実行し、前回の残りを消す（NFR-007）
- 1: `up -d --build`の後、`curl --fail --silent --max-time 2`で`/__admin/mappings`が200になるまで最大30回、1秒間隔で待つ（M05、M06と同じ）。続けて、Squidの応答（HTTPステータスが`000`ではない）を同じ回数と間隔で待つ
- 2: `docker-compose ps`の公開ポート表示が、`127.0.0.1:3128->3128/tcp`と`127.0.0.1:8080->8080/tcp`で、`0.0.0.0`と`::`を含まないことを確かめる
- 3: `127.0.0.1:8080`の`/__admin/mappings`が200であることを確かめる。拒否の判定の前提にする（R-07）
- 4と5: 非ループバックIPv4アドレスを、`ipconfig getifaddr`、`hostname -I`の順で取得する。取得できなければ理由を出力してスキップし、失敗にしない
- 4と5: 取得できた場合は、3128番と8080番へ`--connect-timeout 3`で接続し、接続できたら失敗にする。アドレスは出力しない
- 6: 許可ドメイン用のマッピングを投入し、ホストの`127.0.0.1:3128`経由で200と本文を確かめる。許可外ドメインがHTTP 403で拒否されることも確かめる
- 7: `docker-compose run --rm --no-deps test-client`のone-shot実行で、`squid:3128`経由の許可ドメインが200になることを確かめる。
  Test Clientは要求を1回送ると終了するため、`exec`は使わない（FR-006）
- 8: 現行の設定で`docker-compose exec -T squid squid -k parse`を実行し、終了コードが0で、出力にERRORとFATALがないことを確かめる。
  続けて、未定義のディレクティブを足した写しで同じコマンドを実行し、終了コードが非0であることを確かめる。
  どちらかを満たさなければ失敗にする。WARNINGは失敗にしない。
  未定義のディレクティブは終了コード1で、ERRORとFATALの文字列を出さないため、文字列だけでは判定しない（8.3の結果）。
  壊した写しは`.s14-deny.<PID>`に置き、`mktemp`の場所は使わない
- 9（範囲外の送信元）: 1.4の規則に従う。`.s14-deny.<PID>`に、`acl local_src`を`192.0.2.0/24`へ差し替えた`squid.conf`の写しと、`volumes`だけを上書きするComposeファイルを置く
- 9: `docker-compose -f docker-compose.yml -f <上書きファイル> up -d --force-recreate squid`で作り直す。
  作り直しの後、Squidが応答する（ステータスが`000`ではない）まで最大30回、1秒間隔で待つ。
  その後、許可ドメインの要求がHTTP 403で、アクセスログに`TCP_DENIED`が出ることを確かめる
- 9: 範囲外の検査は`live`の最後に置く（R-12）。リポジトリの`squid.conf`は書き換えない
- 識別情報を出力しない（NFR-006）
- 実行後に、1.4の規則7の2つの確認（`git status --short | grep -F '.s14-deny.'`が空、`ls -d .s14-deny.* 2>/dev/null`が空）を行う
- 規則7の確認自体の動作確認: わざと`.s14-deny.test`を作り、`grep -F`が検出することを確かめてから消す
- 中断の確認: `sh tests/s14-compose-port-binding.sh live &`で起動し、`$!`のプロセスへ`kill -TERM`を送る。
  確認は、スクリプトが使う`sh`で行う。`TERM`で`EXIT`の`trap`を実行するかはシェルで異なり、macOSの`sh`とbashは実行したが`dash`は実行しなかったためである
- 中断の確認: `TERM`は2つの時点で送る。Composeのコンテナが起動した後と、`.s14-deny.<PID>`が現れた後（0.2秒間隔で最大150回見る。現れなければコンテナ側だけを確かめ、その旨を記録する）
- 中断の確認: `wait`で終了を待ち、終了コードが143であること、`docker-compose ps -a -q`が空であること、`.s14-deny.*`の写しが残っていないこと（規則7の2つの確認）を確かめる

### T1406: `docs/ポート公開範囲.md`の新規作成

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-004、FR-010、FR-011、NFR-006、NFR-008 |
| 触るファイル | `docs/ポート公開範囲.md`（新規） |
| 依存 | T1405 |
| 並列 | 不可（READMEからのリンク先であり、T1407が内容を確かめる）。T1405への依存は順序のためで、`live`の結果は文書に使わない |
| 検査 | `npm run lint:md`が成功する。`plan.md` 4.5の7つの節の見出しが`grep -c`で7件ある。`#`見出しが1つだけである。`grep -E '[0-9]{12}\|arn:aws'`が何も出力しない |

- 節は、概要、接続先、Squidの送信元制御、許可ネットワークを採用しない理由、別マシンや別コンテナから使う場合、症状と対処、M10への引き継ぎの7つにする
- 接続先: Squidは`127.0.0.1:3128`、WireMockは`127.0.0.1:8080`。管理APIも同じ公開範囲だと書く
- Squidの送信元制御: 許可する4範囲と、`sidecar`のサブネットを固定しない理由を書く。`default-address-pools`の限界も書く
- 許可ネットワークを採用しない理由: `clarify.md`のQ-002の理由と、変更する条件（LAN上の別端末やリモートのCIから使う運用が出た場合）を書く
- 別マシンや別コンテナから使う場合: SSHポートフォワードを案内する。例には`<REMOTE_HOST>`を使う
- 症状と対処: `plan.md` 4.5の4行の表を書く（接続拒否、`localhost`が`::1`へ解決、HTTP 403、ポート使用中）
- M10への引き継ぎ: 「症状と対処」を`docs/troubleshooting.md`へ統合する項目として書く。`docs/troubleshooting.md`は作らない
- 見出しと表の前後に空行を置く。箇条書きで強調とコロンを併用しない。1行は120文字以内にする
- 実在のアドレス、ホスト名、アカウントIDを書かない。例にはダミー値を使う

### T1407: `README.md`と`docs/シナリオ隔離.md`の更新

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-010、NFR-008 |
| 触るファイル | `README.md`、`docs/シナリオ隔離.md`、`tests/s14-compose-port-binding.sh`（文書の検査を足す） |
| 依存 | T1406 |
| 並列 | 不可 |
| 検査 | `sh tests/s14-compose-port-binding.sh static`が文書の検査を含めて成功する。`npm run lint:md`が成功する |

- `README.md`のSystem Componentsの2か所を、`127.0.0.1:3128`と`127.0.0.1:8080`へ直す
- 同じ節に、`docs/ポート公開範囲.md`へのリンクを1行足す
- 冒頭の構成図、ECSモデルの`localhost`の記述、`docs/troubleshooting.md`への参照は変えない
- `docs/シナリオ隔離.md`は、`grep`で固定公開の記述を探し、公開先が`127.0.0.1`であることを一言足す。
  表の行は「Compose はポート 3128 と 8080 を 127.0.0.1 だけに固定で公開する。」の形にする
- `git diff README.md docs/シナリオ隔離.md`で、差分が上記の範囲だけであることを確かめる
- `static`に文書の検査を足す。`docs/ポート公開範囲.md`の必須の節の見出しと、READMEの`127.0.0.1:3128`、`127.0.0.1:8080`、リンクを`grep -q`で確かめる
- `static`に、`grep -F 'ポートとコンテナ' docs/シナリオ隔離.md | grep -Fq '127.0.0.1'`の検査を足す（FR-010）。
  `127.0.0.1`を除いた写しで失敗することも確かめる
- 文書の検査も、壊した写しで失敗することを、T1404と同じ方法で確かめる

### T1408: M02 smokeの個別実行と契約影響の記録

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-007、FR-009、NFR-001 |
| 触るファイル | `specs/S14-compose-port-binding/contract-impact.md`（新規）。`tests/m02-routing-smoke.sh`は変更しない |
| 依存 | T1407 |
| 並列 | 不可（Composeのポートを使う。`s14`の`live`と同時に動かさない） |
| 検査 | `docker-compose up -d --build`と起動待ちの後に`sh tests/m02-routing-smoke.sh`が成功し、`docker-compose down`の後に`docker-compose ps -a -q`が空である |

- 手順は、`docker-compose up -d --build`、起動待ち、`sh tests/m02-routing-smoke.sh`、`docker-compose down`の順にする
- 起動待ち: `tests/m02-routing-smoke.sh`には待機がないため、`curl --fail --silent --max-time 2`で`/__admin/mappings`が200になるまで最大30回、1秒間隔で待つ（M05、M06と同じ。M02は変更しない）
- 成功の条件に、許可ドメインの要求がWireMockに届くことと、許可外ドメインが拒否されることを含める
- M02 smokeは品質ゲートの対象外であるため、ここで個別に実行して結果を残す
- `contract-impact.md`に、M01（公開ポート、README上の接続先）、M02、M03、M04、M05からM07の影響の有無と根拠を表にする
- 根拠には、`static`の結果、`live`の順3と順7、M02 smokeの結果を使う
- `test-client/`、`Dockerfile.test-client`、`tests/m02-routing-smoke.sh`に差分がないことを`git diff --stat`で確かめる
- `tests/*.sh`と`scripts/scenario-lib.sh`で、`WIREMOCK_URL`と`PROXY_URL`の既定値が`127.0.0.1`であることを`grep`で確かめる
- `localhost`以外を指定する利用者がいないかを、リポジトリ内の記述で確かめる
- `contract-impact.md`の中身: M01、M02、M03、M04、M05からM07の5行が影響の有無の列つきで存在することを`grep -c`で確かめる
- 識別情報: `contract-impact.md`に`grep -E '[0-9]{12}|arn:aws'`が何も出力しないことを確かめる

### T1409: セキュリティレビュー

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-012、NFR-004、NFR-006 |
| 触るファイル | `specs/S14-compose-port-binding/security-review.md`（新規） |
| 依存 | T1408 |
| 並列 | 不可 |
| 検査 | 4つの確認項目（公開範囲、管理APIの到達性、Squidの送信元制御、識別情報の混入）の見出しが`grep`で4件ある。重大な指摘は「なし」と明記されているか、解消済みと書かれている。`grep -E '[0-9]{12}\|arn:aws'`が何も出力しない。`npm run lint:md`が成功する |

- 公開範囲: `docker-compose config`と`docker-compose ps`の結果、非ループバックへの接続拒否の結果（スキップした場合はその理由）を書く
- 管理APIの到達性: 認証がなく、到達性の制限だけが防御であることを明記する
- Squidの送信元制御: 範囲外の拒否（`live`の順9）、許可範囲の根拠、限界（`default-address-pools`、R-03）を書く
- 8.2が「未確認」の場合は、R-02を残リスクとして書き、M09への引き継ぎを書く
- 識別情報の混入: `static`の識別情報検査の結果と、変更ファイルの目視確認の結果を書く
- NFR-004: 本番ECSのSecurity GroupやIAM設計、HTTPSのSSL Bumpに変更がないことを書く
- レビュー記録にも、アドレス、ホスト名、アカウントIDを書かない
- 重大な指摘がない場合は、「重大な指摘: なし」と明記する

### T1410: 品質ゲートへの登録

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-013 |
| 触るファイル | `scripts/quality-gate.sh` |
| 依存 | T1409 |
| 並列 | 不可 |
| 検査 | `grep -n 's14-compose-port-binding' scripts/quality-gate.sh`で一覧の行が見える。`git diff scripts/quality-gate.sh`が1箇所の変更だけである |

- Compose関連の`for test in ...`の一覧の末尾に、`tests/s14-compose-port-binding.sh`を足す
- 行番号は着手時に現物で確認する。列挙の形式は既存の行に合わせる
- 実行条件の`has_match`、`scripts/*.sh`の構文検査、`docker-compose config --quiet`は、既存の仕組みをそのまま使う
- ゲートの実行そのものはT1411で行う

### T1411: 最終確認

| 項目 | 内容 |
| --- | --- |
| 要件 | FR-007、FR-013、NFR-007、NFR-008、全要件の最終突き合わせ |
| 触るファイル | なし（確認のみ。失敗があれば原因のタスクへ戻って直す） |
| 依存 | T1410 |
| 並列 | 不可（Composeのポートとコンテナ名を共有するため、検査を順に実行する） |
| 検査 | 下記のコマンドが順にすべて成功し、`git diff --stat`の変更が計画のファイルだけである |

実行する確認は次のとおり。

- `sh tests/s14-compose-port-binding.sh`を連続して2回実行し、結果が同じであること（NFR-007）
- `sh tests/m02-routing-smoke.sh`を、スタックを起動し、T1408と同じ起動待ちを入れた状態で再実行し、`docker-compose down`で止めること
- `npm run lint:md`
- `sh scripts/quality-gate.sh`が`quality-gate: passed`で終わること
- 実行後に`docker-compose ps -a -q`が空であること

変更範囲の確認は次のとおり。

- `git diff --stat`に現れるファイルは、`docker-compose.yml`、`squid-config/squid.conf`、`README.md`、
  `docs/シナリオ隔離.md`、`tests/s14-compose-port-binding.sh`、`scripts/quality-gate.sh`だけであること
- 新規ファイルは`git diff --stat`に出ないため、`git status --short`で確かめる。新規は`docs/ポート公開範囲.md`と
  `specs/S14-compose-port-binding/`配下の文書だけであること
- `test-client/`、`Dockerfile.test-client`、`wiremock-scenarios/`、`squid-config/whitelist.txt`、
  `tests/m02-routing-smoke.sh`、`.gitignore`に差分がないこと。`plan.md`がこれらの変更を挙げていないため、差分があれば原因を調べて戻す
- 消し残しがないこと。1.4の規則7の2つの確認（`git status --short | grep -F '.s14-deny.'`が空、`ls -d .s14-deny.* 2>/dev/null`が空）に従う
- 何もステージされていないこと（`git diff --cached --stat`が空）

記録と識別情報の確認は次のとおり。

- 実機の結果が、`specs/S14-compose-port-binding/live-check.md`だけに記録されていること
- `plan.md` 4.3の固定一覧のファイルと検査出力（一時ファイルに保存したもの）に、`grep -E '[0-9]{12}|arn:aws'`で識別情報のパターンが現れないこと
- `spec.md` 8章の完了条件の各項目に対応する成果物があること
- 失敗した場合は、原因のタスクへ戻って直し、T1411を最初からやり直す

## 4. 要件の網羅表

| 要件 | 対応するタスク |
| --- | --- |
| FR-001 | T1403 |
| FR-002 | T1403 |
| FR-003 | T1403、T1404、T1405 |
| FR-004 | T1406 |
| FR-005 | T1401、T1402、T1404、T1405 |
| FR-006 | T1401、T1405 |
| FR-007 | T1408、T1411 |
| FR-008 | T1401、T1404、T1405 |
| FR-009 | T1408 |
| FR-010 | T1406、T1407 |
| FR-011 | T1406 |
| FR-012 | T1409 |
| FR-013 | T1410、T1411 |
| NFR-001 | T1404、T1408 |
| NFR-002 | T1403、T1404 |
| NFR-003 | T1402、T1404 |
| NFR-004 | T1409、T1411 |
| NFR-005 | T1404、T1405 |
| NFR-006 | T1404、T1405、T1406、T1409、T1411 |
| NFR-007 | T1405、T1411 |
| NFR-008 | T1406、T1407、T1411 |

FR-001からFR-013、NFR-001からNFR-008のすべてが、1つ以上のタスクに対応している。網羅の抜けはない。
`plan.md`の網羅表（7.1）に対して、NFR-004にT1411（変更範囲の確認）、NFR-006にT1406とT1411、NFR-008にT1406を足した。

## 5. 完了条件

- [ ] T1401のゲート条件（1.1）を満たし、結果が`live-check.md`に記録されている
- [ ] T1402からT1411を完了している
- [ ] `sh tests/s14-compose-port-binding.sh`（`static`と`live`）が通り、連続2回の結果が同じである
- [ ] `sh tests/m02-routing-smoke.sh`が、スタックを起動した状態で成功している
- [ ] `scripts/quality-gate.sh`に`tests/s14-compose-port-binding.sh`が登録されている
- [ ] deny用の写し（`.s14-deny.`を含む名前）が残っていない。`git status --short | grep -F '.s14-deny.'`と`ls -d .s14-deny.*`がどちらも空である
- [ ] `git diff --stat`が、`plan.md`に挙げたファイルだけを示している
- [ ] `sh scripts/quality-gate.sh`が成功している
