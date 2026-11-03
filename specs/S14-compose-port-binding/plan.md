# S14実装計画

## 1. 技術方針

S14は、開発用`docker-compose.yml`のホスト公開をループバックに限定し、Squidに送信元ACLを足す。
`spec.md`と`clarify.md`の決定（Q-001からQ-008）をそのまま実装の前提にする。

| 方針 | 内容 |
| --- | --- |
| 公開範囲 | squidとwiremockの`ports`を`127.0.0.1:3128:3128`と`127.0.0.1:8080:8080`に固定する。環境変数と`::1`は使わない |
| 送信元制御 | `squid.conf`に`acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`を足し、`http_access allow api_domains`を`http_access allow local_src api_domains`へ置き換える |
| 変更しないもの | Test Client、`whitelist.txt`、`acl all src all`、`cache deny all`、`cache_peer`の各行、サービス名、ネットワーク名、マウント |
| 検査の入口 | `tests/s14-compose-port-binding.sh`を新設する。`static`、`live`の2モードで、引数なしは両方を実行する |
| 実行時依存 | 追加しない。POSIX sh、`curl`、`python3`（M03の検査が既に使用）、`docker-compose`だけを使う |
| 文書 | 新規`docs/ポート公開範囲.md`に接続先、採用しなかった案、症状と対処、M10への引き継ぎを書く |

検証は、Dockerのデーモンを使わない層とComposeを起動する層に分ける。M06、M07の`unit`、`smoke`と同じ考え方である。

| 層 | モード | 対象 | デーモン |
| --- | --- | --- | --- |
| 静的 | `static` | `docker-compose config`の出力、`squid.conf`と文書の記述 | 不要 |
| 実機 | `live` | `docker-compose ps`、非ループバックへの接続、送信元ACLの許可と拒否 | 必要 |

本番のスクリプトや設定に、テスト専用の分岐や環境変数は入れない。範囲外の送信元を作る検査は、
検査内で作る一時ファイルとComposeの上書き指定で行う。

`spec.md`には、`clarify.md`の決定（Q-001からQ-008の解消）が反映済みである。
本planの記述は`spec.md`と`clarify.md`の両方と一致させる。

## 2. 変更ファイル

| パス | 種別 | 変更内容 |
| --- | --- | --- |
| `docker-compose.yml` | 変更 | squidの`ports`を`"127.0.0.1:3128:3128"`、wiremockの`ports`を`"127.0.0.1:8080:8080"`にする |
| `squid-config/squid.conf` | 変更 | `acl local_src`を1行足し、`http_access allow api_domains`を`http_access allow local_src api_domains`へ置き換える。意図のコメントを足す |
| `tests/s14-compose-port-binding.sh` | 新規 | 公開範囲と送信元ACLの検査入口（4.3） |
| `scripts/quality-gate.sh` | 変更 | Compose関連の`for test in ...`の一覧の末尾に`tests/s14-compose-port-binding.sh`を足す（4.4） |
| `docs/ポート公開範囲.md` | 新規 | 接続先、許可ネットワークを採用しない理由、代替手段、症状と対処、M10への引き継ぎ（4.5） |
| `README.md` | 変更 | System Componentsの2か所を`127.0.0.1`へ直し、`docs/ポート公開範囲.md`へのリンクを足す（4.6） |
| `docs/シナリオ隔離.md` | 変更 | 固定公開の記述に、公開先が`127.0.0.1`であることを足す（4.6） |
| `specs/S14-compose-port-binding/live-check.md` | 新規 | 8章の実機確認の記録（単位U1） |
| `specs/S14-compose-port-binding/contract-impact.md` | 新規 | M01からM04の契約への影響の記録（5章、FR-009） |
| `specs/S14-compose-port-binding/security-review.md` | 新規 | セキュリティレビューの結果（4.7、FR-012） |
| `specs/S14-compose-port-binding/plan.md` | 新規 | 本書 |

変更しないファイルは次のとおり。

| パス | 理由 |
| --- | --- |
| `tests/m02-routing-smoke.sh` | FR-013。M02の検査は変えず、スタックを起動して個別に実行する |
| `tests/m03`から`m07`の各検査、`scripts/scenario-lib.sh` | 既定値が`127.0.0.1`であり、影響しない見込み（5章で確かめる） |
| `squid-config/whitelist.txt` | NFR-003 |
| `Dockerfile.test-client`、`test-client/` | NFR-001 |
| `docs/requirements.md`、`README.md`のECSモデルの`localhost`記述 | ECSのlocalhost共有を説明する記述であり、Q-007で変更しないと決めた |
| `README.md`の`docs/troubleshooting.md`への参照 | M10の範囲。S14では作らず、引き継ぎとして記録する |

## 3. 検証境界

### 3.1 静的検査（`static`）

Dockerのデーモンを使わない。`docker-compose config`はデーモンに接続せずに設定を展開する。
展開できない環境では、理由を出力して失敗とする（静的検査は必須のため、スキップしない）。

| 対象 | 確認内容 |
| --- | --- |
| `docker-compose config`の出力 | squidの3128番とwiremockの8080番の両方に`host_ip: 127.0.0.1`が付いている。ほかのサービスに`ports`がない |
| 同上 | サービス名（3件）、ネットワーク名`sidecar`、コンテナ内ポート、`:ro`のマウント、Test Clientの環境変数4件が変わっていない（NFR-001、NFR-002） |
| `squid.conf` | `acl local_src`の行が規定の4範囲と一致する。`http_access allow local_src api_domains`が1行ある。送信元を見ない`http_access allow api_domains`が残っていない。`http_access deny all`、`cache deny all`、`cache_peer`の各行が残っている |
| `whitelist.txt` | 許可ドメインが`api.example.com`と`api-staging.example.com`の2件のままである（NFR-003） |
| 文書 | `docs/ポート公開範囲.md`に必須の節がある。READMEのSystem Componentsに`127.0.0.1:3128`、`127.0.0.1:8080`、文書へのリンクがある |
| 識別情報 | 変更対象のファイルに、12桁の数字列の連続、`arn:aws`、認証情報らしい文字列がない（NFR-006） |

### 3.2 実機検査（`live`）

自らComposeを起動し、`trap`で`docker-compose down --remove-orphans`する。M03、M05と同じ方式である。

| 順 | 確認内容 | 失敗の扱い |
| --- | --- | --- |
| 1 | `up -d --build`の後、`/__admin/mappings`が200になり、Squidが応答するまで待つ（4.3の待機） | 失敗 |
| 2 | `docker-compose ps`の公開ポート表示が`127.0.0.1:3128->3128/tcp`と`127.0.0.1:8080->8080/tcp`で、`0.0.0.0`と`::`を含まない | 失敗 |
| 3 | `127.0.0.1:8080`の`/__admin/mappings`がHTTP 200を返す | 失敗 |
| 4 | ホストの非ループバックIPv4アドレスを取得する | 取得不可はスキップ（理由を出力） |
| 5 | 取得したアドレスの3128番と8080番への接続が失敗する。3が成功した後にだけ判定する | 接続成功は失敗 |
| 6 | ホストの`127.0.0.1:3128`経由の許可ドメインの要求が成功し、許可外ドメインの要求がHTTP 403で拒否される | 失敗 |
| 7 | 許可ドメインの要求がTest Client経由で成功する（FR-006） | 失敗 |
| 8 | 現行の設定は`squid -k parse`が終了コード0で、出力にERRORとFATALがない。未定義のディレクティブを足した写しは終了コードが非0になる。WARNINGは失敗にしない | 失敗 |
| 9 | 送信元ACLを範囲外へ差し替えたSquidが、許可ドメインの要求をHTTP 403で拒否する | 失敗 |

順の番号は4.3の`live`の実装と同じである。5章、6章、tasks.mdの参照も、この番号を使う。

### 3.3 M02 smoke

`tests/m02-routing-smoke.sh`は稼働中のスタックを前提とし、品質ゲートから実行されない。
S14では、スタックを起動した状態で個別に実行し、成功を確認する（FR-007）。
手順は`AGENTS.md`の方針どおり、`docker-compose up -d --build`、起動待ち、smoke、`docker-compose down`の順とする。
`tests/m02-routing-smoke.sh`には待機の処理がないため、smokeの前に、`curl --fail --silent --max-time 2`で
`/__admin/mappings`が200になるまで最大30回、1秒間隔で待つ（M02は変更しない）。
`s14`の`live`とは別に実行し、同時には動かさない（ポート3128と8080を取り合うため）。

### 3.4 品質ゲート

コミット前に`scripts/quality-gate.sh`をすべて成功させる（FR-013）。

| 確認 | 内容 |
| --- | --- |
| シェル構文 | `tests/s14-compose-port-binding.sh`が`sh -n`の対象に自動で入る |
| Markdown | `npm run lint:md`が、新規と変更の文書で成功する（NFR-008） |
| Compose | `docker-compose config --quiet`が成功する |
| スモーク | 一覧にs14が入り、m03からm07とあわせて成功する。実行後にコンテナが残らない |

## 4. 各変更の設計

### 4.1 ポート公開（`docker-compose.yml`）

squidとwiremockの`ports`の1行を、ホストIP付きの文字列に置き換える。ほかの行には触れない。

```text
squid:    - "3128:3128"  ->  - "127.0.0.1:3128:3128"
wiremock: - "8080:8080"  ->  - "127.0.0.1:8080:8080"
```

IPv6の`::1`は公開しない。ホストIPを環境変数にしない（Q-001）。
`test-client`には`ports`がなく、`HTTP_PROXY`は`http://squid:3128`のままで、Composeネットワーク内で完結する。

### 4.2 Squidの送信元ACL（`squid.conf`）

`acl api_domains`の宣言の直後に、次の1行を足す。

```text
acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
```

`http_access allow api_domains`は`http_access allow local_src api_domains`に置き換える。
`http_access deny all`が後ろにあるため、範囲外の送信元は許可行に一致せず、`deny all`で拒否される。

コメントには、Why notを書く。

| コメントの内容 | 理由 |
| --- | --- |
| `sidecar`のサブネットを固定せずRFC1918の3範囲で受ける | Dockerがサブネットを動的に割り当てる。`ipam`での固定はNFR-002に反する |
| `acl all src all`を消さない | 組み込みの`all`と重複するWARNINGが出るが、動作に影響しない。目的外の変更になる（Q-008） |

`acl all src all`の行、`cache_peer`の各行、`never_direct`、`cache`系の行は変えない。

### 4.3 検査入口（`tests/s14-compose-port-binding.sh`）

POSIX shで書く。`#!/bin/sh`と`set -eu`で始め、配列、`[[ ]]`、`local`、プロセス置換は使わない。
引数は`static`、`live`、なし（両方）の3通りで、それ以外は使い方を出力して終了コード2で終わる。

#### 構成

| 部分 | 内容 |
| --- | --- |
| 変数 | `wiremock_url`は`${WIREMOCK_URL:-http://127.0.0.1:8080}`、`proxy_url`は`${PROXY_URL:-http://127.0.0.1:3128}`。M03、M05と同じ名前にそろえる |
| 後始末 | `cleanup`関数を作り、`trap cleanup EXIT`、`trap 'exit 130' INT`、`trap 'exit 143' TERM`を置く。`cleanup`は`docker-compose down --remove-orphans`と一時ファイルの削除を行う。開始時にも`down`し、前回の残りを消す（NFR-007） |
| 失敗の記録 | 失敗した検査の名前を標準エラーへ出力し、最後に終了コード1で終わる。最初の失敗で止めない箇所は設けない |
| 出力 | 識別情報を出さない。非ループバックのアドレスは出力せず、「取得した」「取得できない」だけを書く（NFR-006） |

#### `static`の実装

`docker-compose config --format json`の出力を`python3`で読む。M03の検査と同じく、標準入力の`<<'PY'`で書く。
`--format json`が使えない場合の代替は、8.4で確かめる。

| 検査 | 方法 |
| --- | --- |
| 公開範囲 | `services.squid.ports`に`target`が3128、`host_ip`が`127.0.0.1`、`published`が`3128`の要素が1件だけある。wiremockも8080で同様。その他のサービスの`ports`は空である |
| 契約の不変 | サービス名の集合が3件、ネットワークが`sidecar`だけ、volumesの`read_only`が`true`、Test Clientの環境変数4件が既存の値と一致する |
| Squid設定 | `grep -Fx`で完全一致の行を確かめる。`acl local_src`の行、`http_access allow local_src api_domains`、`http_access deny all`、`cache deny all`。`grep -Fxq 'http_access allow api_domains'`が見つからないこと |
| 許可ドメイン | `whitelist.txt`の有効な行が規定の2件であること |
| 文書 | `grep -q`で必須の節の見出しとREADMEの記述を確かめる。`docs/シナリオ隔離.md`は、`ポートとコンテナ`を含む行に`127.0.0.1`があることを`grep -F`で確かめる（FR-010） |
| 識別情報 | `grep -E`で12桁の数字列、`arn:aws`、`AKIA`、`aws_secret`を探し、あれば失敗。対象は下記の固定一覧で、存在しないファイルは読み飛ばす |

識別情報の検査の対象は、`docker-compose.yml`、`squid-config/squid.conf`、`scripts/quality-gate.sh`、`README.md`、
`docs/ポート公開範囲.md`、`docs/シナリオ隔離.md`、`live-check.md`、`contract-impact.md`、`security-review.md`である。
`tests/s14-compose-port-binding.sh`自身は、検査のパターンの文字列を含むため対象に入れない。
検査の方法は`tests/m07-scenario-isolation.sh`と同じ`grep -E '[0-9]{12}|arn:aws'`に、`AKIA`と`aws_secret`を足したものである。
検査出力は一時ファイルに保存し、同じパターンで探して、現れないことも確かめる。

記録文書の中身は、次の規則で`grep`により確かめる（T1408、T1409の検査）。目視だけにしない。

| 文書 | 規則 |
| --- | --- |
| `live-check.md` | 環境、手順、観測、結論の4節の見出しがある。8.1、8.3、8.4、8.5が記録されている |
| `contract-impact.md` | M01、M02、M03、M04、M05からM07の5行が、影響の有無の列つきで存在する（`grep -c`で5） |
| `security-review.md` | 4つの確認項目の見出しがある。重大な指摘は、ない場合に「なし」と明記する |
| `docs/ポート公開範囲.md` | 4.5の7つの節の見出しがある。`#`見出しが1つだけである |

静的検査は、確認用の入力を別に作らず、現物を読むだけにする。パスは、スクリプトの位置から決める`ROOT`
（`$(cd "$(dirname "$0")/.." && pwd)`）からの相対だけを使い、リポジトリ固定の絶対パスや、テスト専用の分岐を持たない。
検査自体の正しさ（誤検出しないこと）は、U4で、わざと壊した写しに対して失敗することを確かめる（6章R-06）。
写しは、リポジトリの外の`mktemp -d`配下に作り、`docker-compose config`が読むファイル（Compose、
`squid-config/`、`Dockerfile`類、`test-client/`）と検査スクリプトを`tests/`ごと写す。
写しの側の`ROOT`で検査を実行し、写しの削除は、その確認を行う補助シェルの`trap`
（`EXIT`、`INT`、`TERM`）で行う。

#### `live`の実装

| 順 | 処理 |
| --- | --- |
| 1 | `docker-compose down --remove-orphans`の後、`docker-compose up -d --build`。`curl --fail --silent --max-time 2`で`/__admin/mappings`が200になるまで最大30回、1秒間隔で待つ（M05、M06と同じ）。続けて、Squidがプロキシとして応答する（HTTPステータスが`000`ではない）まで、同じ回数と間隔で待つ |
| 2 | `docker-compose ps`の出力から公開ポート表示を読み、期待する2件があることと、`0.0.0.0`と`::`がないことを確かめる |
| 3 | `curl`で`127.0.0.1:8080`の`/__admin/mappings`が200であることを確かめる（以降の拒否の判定の前提） |
| 4 | 非ループバックIPv4アドレスを取得する（下記）。取得できなければ「スキップ」を出力して6へ進む |
| 5 | 取得したアドレスの3128番と8080番へ、`--connect-timeout 3`で接続する。接続できたら失敗。拒否とタイムアウトは成功とみなす |
| 6 | WireMockへ許可ドメイン用のマッピングを投入し、`curl --proxy`で許可ドメインを要求して200と本文を確かめる。続けて許可外ドメインがHTTP 403で拒否されることを確かめる（M02と同じ流れ） |
| 7 | `docker-compose run --rm --no-deps test-client`で、one-shotのTest Clientから`squid:3128`経由で許可ドメインが200になることを確かめる。Test Clientは要求を1回送ると終了するため、`exec`は使わない（FR-006） |
| 8 | 現行の設定で`docker-compose exec -T squid squid -k parse`を実行し、終了コードが0で出力にERRORとFATALがないことを確かめる。続けて、未定義のディレクティブを足した写しで同じコマンドを実行し、終了コードが非0であることを確かめる。未定義のディレクティブは終了コード1になり、ERRORとFATALの文字列を出さないため、文字列だけでは見逃す。どちらかを満たさなければ失敗にする |
| 9 | 範囲外の送信元の検査（下記） |

非ループバックIPv4アドレスの取得は、次の順で試し、最初に得られたものを使う。どれも得られなければスキップする。

| 順 | 方法 |
| --- | --- |
| 1 | `ipconfig getifaddr`（macOS）で`en0`と`en1`を順に試す |
| 2 | `hostname -I`（Linux）の最初の要素のうち、`127.`で始まらず、`:`を含まないもの |

取得に使うコマンドが無い場合は、そのコマンドをスキップして次へ進む。出力にアドレスを書かない。

範囲外の送信元の検査は、送信元ACLを範囲外へ差し替えて、拒否されることを確かめる。

| 手順 | 内容 |
| --- | --- |
| a | リポジトリ直下の使い捨てディレクトリ（`.s14-deny.<PID>`）に、`squid.conf`の写しを作る。`acl local_src`の行だけを、文書用の範囲`192.0.2.0/24`（RFC 5737）に`sed`で置き換える。リポジトリの`squid.conf`は書き換えない |
| b | 同じディレクトリに、`squid`の`volumes`だけを上書きするComposeファイルを作る。写しを`/etc/squid/squid.conf:ro`にマウントする |
| c | `docker-compose -f docker-compose.yml -f <上書きファイル> up -d --force-recreate squid`でsquidだけを作り直す。作り直しの後、手順1と同じ待機（Squidの応答が`000`ではなくなるまで最大30回、1秒間隔）を入れてから判定する。ヘルスチェックの`start_period`は10秒で、待たないと403の判定が不安定になる |
| d | 許可ドメインの要求がHTTP 403になること、アクセスログに`TCP_DENIED`が出ることを確かめる |
| e | `trap`で、作り直したスタックを`down`し、使い捨てディレクトリを削除する |

`INT`と`TERM`で`exit`するのは、`EXIT`の`trap`をシェルによらず必ず通すためである。
分析で`TERM`による終了を試したところ、`EXIT`の`trap`は、macOSの`sh`とbashでは実行され、`dash`では実行されなかった。
そのためT1405の中断の確認は、スクリプトが使う`sh`で行う。`SIGKILL`は捕捉できないため、
その場合は手動で回収する（`tasks.md` 1.4の規則7）。

使い捨てディレクトリをリポジトリ直下に置くのは、ColimaなどのVM型ランタイムで、ホストの一時ディレクトリ
（macOSの`/var/folders`配下）がVMにマウントされない場合があるためである。マウントされるかは8.5で確かめる。
8.5の手順3で、`mktemp -d`のディレクトリはColimaでマウントできなかった。この結果は、リポジトリ直下に置く本節の設計が正しいことを裏づける。
そのため、範囲外の検査（deny用の写し）に`mktemp`の場所は使わない。
`.s14-deny.*`は、検査が終了時に必ず消す。消し残しを避けるため、`trap`で`rm -rf`するのは
この名前で自分が作ったディレクトリだけにする。変数は作成後にだけ設定し、空でないことを確かめてから消す。

消し残しの判定は、`git status --short | grep -F '.s14-deny.'`が何も出力しないこと（`grep`の終了コードが1）とし、
`ls -d .s14-deny.* 2>/dev/null`が空であることも併せて確かめる。未追跡のディレクトリは
`?? .s14-deny.<PID>/`と表示され、行頭が`.s14-deny.`ではないため、「行頭が一致する」書き方は使わない。

### 4.4 品質ゲートへの登録（`scripts/quality-gate.sh`）

`for test in ...`の一覧の末尾に`tests/s14-compose-port-binding.sh`を足す。ほかの行は変えない。
実行条件は既存の`has_match`をそのまま使う。各検査は、自身のパスか、`docker-compose.yml`、`Dockerfile`、
`squid-config/`、`wiremock-scenarios/`、`test-client/`、`scripts/scenario-lib.sh`の変更で動く。
`scripts/*.sh`の構文検査と`docker-compose config --quiet`は、既存の仕組みが新しい検査も対象にする。

ゲートは、s14の`live`を含めて実行する。s14は自らスタックを起動するため、m03からm07と同じく直列で動く。
並列実行はしない（ポートを取り合う）。

### 4.5 新規文書（`docs/ポート公開範囲.md`）

節の構成は次のとおり。`#`見出しは1つだけにする。

| 節 | 内容 |
| --- | --- |
| 概要 | 公開先が`127.0.0.1`であること。他のホストや別マシンのコンテナからは接続できないこと |
| 接続先 | Squidは`127.0.0.1:3128`、WireMockは`127.0.0.1:8080`。管理APIも同じ公開範囲 |
| Squidの送信元制御 | 許可する4範囲と、`sidecar`のサブネットを固定しない理由 |
| 許可ネットワークを採用しない理由 | clarifyのQ-002（利用者承認済み、2026-11-03）。採用すると誤設定で`0.0.0.0`相当に戻せる。利用の実態がない。変更する条件（LAN上の別端末やリモートのCIから使う運用が出た場合） |
| 別マシンや別コンテナから使う場合 | 利用者側の手段としてSSHポートフォワードを案内する。例にはダミー値（`<REMOTE_HOST>`）を使う |
| 症状と対処 | 下の表。M10が統合する対象 |
| M10への引き継ぎ | 「症状と対処」を`docs/troubleshooting.md`へ統合する項目として記録する |

「症状と対処」は、症状と対処のペアが並ぶため表にする。

| 症状 | 原因 | 対処 |
| --- | --- | --- |
| 別マシンや別コンテナから接続が拒否される | 公開先が`127.0.0.1`のため | SSHポートフォワードなど利用者側の手段を使う |
| `localhost`への接続が失敗する | `localhost`が`::1`へ解決され、`::1`は公開していない（curl以外の挙動は未確認） | 接続先を`127.0.0.1`にする |
| 許可ドメインの要求がHTTP 403になる | Dockerが`default-address-pools`でRFC1918外のサブネットを割り当て、送信元ACLの範囲外になった | `acl local_src`にそのサブネットを足す |
| ポート3128、8080が使用中で起動に失敗する | 他のプロセスが同じポートを使っている | 既存のプロセスを止める。ホストIPを変える設定は提供しない |

### 4.6 README.mdと`docs/シナリオ隔離.md`

README.mdは、System Componentsの2か所（Squidの`localhost:3128`、WireMockの`localhost:8080`）だけを
`127.0.0.1:3128`、`127.0.0.1:8080`へ直す。同じ節に、`docs/ポート公開範囲.md`へのリンクを1行足す。
冒頭の構成図、ECSモデルを説明する記述、`docs/troubleshooting.md`への参照は変えない。

`docs/シナリオ隔離.md`は、ポート3128と8080を固定で公開する記述に、公開先が`127.0.0.1`であることを一言足す。
行番号は変わりうるため、実装時に`grep`で該当箇所を探す。
足した後の表の行は「Compose はポート 3128 と 8080 を 127.0.0.1 だけに固定で公開する。」の形とし、
`ポートとコンテナ`を含む行に`127.0.0.1`があることを`static`で確かめる。

文書の書式は、`markdown.md`のルール（見出し前後の空行、表の前後の空行、120文字以内、
箇条書きでの強調とコロンの併用の禁止）に従う（NFR-008）。

### 4.7 契約影響の記録とセキュリティレビュー

契約影響の記録は`specs/S14-compose-port-binding/contract-impact.md`に、5章の表を実機の結果で確定して書く。
セキュリティレビューは`specs/S14-compose-port-binding/security-review.md`に書く。確認項目は次の4つである（FR-012）。

| 確認項目 | 確認方法 |
| --- | --- |
| 公開範囲 | `docker-compose config`と`docker-compose ps`の出力、非ループバックへの接続拒否 |
| 管理APIの到達性 | 管理APIが`127.0.0.1`以外から到達できないこと。認証がないため、到達性の制限だけが防御であることを明記する |
| Squidの送信元制御 | 範囲外の拒否（`live`の順9）、許可範囲の根拠、限界（`default-address-pools`） |
| 識別情報の混入 | 変更ファイルと検査出力を、`static`の識別情報検査と目視で確認する |

## 5. M01からM04の契約への影響

FR-009の記録の見込みである。実機の結果で確定し、`contract-impact.md`に書く。

| 契約 | 内容 | 変更の有無 | 根拠と確認方法 |
| --- | --- | --- | --- |
| M01 公開ポート | 公開ポートは3128と8080 | 番号は変わらない。公開先が全インターフェースからループバックへ狭まる | `docker-compose config`の`published`と`target`が不変であることを`static`で確認 |
| M01 README上の接続先 | 接続先の表記が`localhost` | 表記が`127.0.0.1`に変わる | READMEの差分で確認 |
| M02 ルーティング | 許可ドメインはWireMockへ転送し、許可外は拒否 | 宛先と転送は変わらない。`http_access`に送信元の条件が増える | M02のsmokeを個別に実行して成功を確認（3.3）。`cache_peer`の行が不変であることを`static`で確認 |
| M03 マッピング | 管理APIでマッピングを確認する | 変更なし | `127.0.0.1:8080`の`/__admin/mappings`が200（`live`の順3）。M03の検査をゲートで実行 |
| M04 Test Client | `squid:3128`へネットワーク内で接続する | 変更なし | `test-client/`、`Dockerfile.test-client`、環境変数4件の差分がないこと。Test Client経由の許可ドメインが成功（`live`の順7） |
| M05からM07（参考） | 検査の既定値が`127.0.0.1` | 変更なし | `tests/*.sh`と`scripts/scenario-lib.sh`で`WIREMOCK_URL`、`PROXY_URL`の既定値を確認。ゲートでm05からm07が成功 |

## 6. リスクと確認方法

| ID | リスク | 影響 | 確認方法 |
| --- | --- | --- | --- |
| R-01 | Test Client経由の要求が、送信元ACLの追加後に拒否される | FR-006、M04の契約が壊れる | `live`の順7と、8.1の実機確認 |
| R-02 | Linuxのホスト（CI）で、ループバック経由の接続の送信元がACLの範囲外になる | CIで`live`が失敗する。M09に波及する | 8.2の手順で、アクセスログの送信元アドレスを確かめる |
| R-03 | `default-address-pools`でRFC1918外のサブネットを使う環境で、要求が拒否される | 利用者の環境で403になる | 文書の「症状と対処」に書く。検査では再現しない（環境依存）。限界として`security-review.md`に記録 |
| R-04 | `squid -k parse`の終了コードが想定と違い、判定を誤る | 検査が通らない、または見逃す | 8.3で終了コードを実測する。終了コードと出力の`ERROR`、`FATAL`の文字列の両方で判定する。8.3の実測で、未定義のディレクティブは終了コード1で文字列を出さなかった |
| R-05 | 範囲外の送信元の検査で、一時ディレクトリがVMにマウントされない | 順9が失敗する | 8.5でマウントを確かめる。リポジトリ直下に置く設計で回避する |
| R-06 | `static`が誤検出または検出漏れをする | 退行を見逃す | わざと壊した一時コピー（`0.0.0.0`公開、ACL行の欠落）に対して失敗することをU4で確かめる |
| R-07 | 非ループバックの接続拒否の判定が、スタック停止による失敗を拒否と取り違える | 公開範囲の誤判定 | 順3で`127.0.0.1`の成功を先に確かめ、成功した後にだけ判定する |
| R-08 | `ubuntu/squid:latest`が移動するタグで、バージョンが変わるとparseの出力が変わる | 検査が将来不安定になる | 特定のバージョン文字列に依存しない。WARNINGは失敗にしない（Q-008） |
| R-09 | 検査の連続実行で状態が残る | NFR-007に反する | 開始時と終了時に`down`する。連続2回の実行を最終確認でやる（U11） |
| R-10 | 検査出力や文書に、ホストのアドレスなどの識別情報が入る | NFR-006に反する | アドレスを出力しない設計。`static`の識別情報検査と、目視確認 |
| R-11 | Q-002の利用者確認の結果が「採用する」に変わる | FR-004と検査の範囲が変わる | 利用者が「採用しない」を承認済み（2026-11-03）。採用に変わった場合は、実装前にplanを見直す |
| R-12 | 範囲外の検査でsquidを作り直す際に、元の設定のスタックと混ざる | 後続の検査に影響する | 範囲外の検査を`live`の最後に置き、終了時に`down`する。`trap`で必ず後始末する |

## 7. 実装単位

各単位は小さく保ち、単位ごとに検証してから次へ進む。順序は依存に従う。

| 単位 | 内容 | 対応する要件 | 完了の確認 |
| --- | --- | --- | --- |
| U1 | 実機確認の先行（8章の8.1、8.3、8.4、8.5）。結果を`live-check.md`に記録する。リポジトリのファイルは変えない。8.5の一部を除き、`$KIROCREW_SCRATCH`配下の使い捨てコピーで行う（8章） | FR-006、FR-005、FR-008 | 8章の各項目の結果が記録され、`git diff --stat`が空で、`git status --short -uall`の差が`live-check.md`の追加だけである |
| U2 | `docker-compose.yml`の`ports`変更（4.1） | FR-001、FR-002、FR-003、NFR-002 | `docker-compose config`で`host_ip`が2件。`docker-compose config --quiet`が成功 |
| U3 | `squid.conf`の送信元ACL（4.2） | FR-005、NFR-003 | 必須の行が完全一致で存在し、`allow api_domains`の旧行が無い |
| U4 | `tests/s14-compose-port-binding.sh`の`static`モード（4.3）。壊した一時コピーで失敗することも確かめる | FR-003、FR-005、FR-008、NFR-001、NFR-002、NFR-003、NFR-005、NFR-006 | `sh tests/s14-compose-port-binding.sh static`が成功。壊した入力で失敗 |
| U5 | 同`live`モード（4.3）。公開表示、非ループバック、許可と拒否、`squid -k parse`、範囲外の送信元 | FR-003、FR-005、FR-006、FR-008、NFR-005、NFR-006、NFR-007 | `sh tests/s14-compose-port-binding.sh live`が成功。実行後にコンテナが残らない |
| U6 | `scripts/quality-gate.sh`への登録（4.4） | FR-013 | 一覧の末尾にs14が入り、ゲートが検査を実行する |
| U7 | `docs/ポート公開範囲.md`の新規作成（4.5） | FR-004、FR-010、FR-011 | 必須の節がある。`npm run lint:md`が成功。M10への引き継ぎが書かれている |
| U8 | `README.md`と`docs/シナリオ隔離.md`の更新（4.6） | FR-010、NFR-008 | 該当箇所の差分が4.6の範囲だけ。ECSモデルの`localhost`が残っている |
| U9 | `contract-impact.md`の作成（5章）。M02 smokeを個別に実行する（3.3） | FR-007、FR-009、NFR-001 | 契約ごとの表が埋まっている。M02 smokeが成功。`test-client/`の差分がない |
| U10 | `security-review.md`の作成（4.7） | FR-012、NFR-004、NFR-006 | 4つの確認項目に結果がある。重大な指摘が残っていない |
| U11 | 最終確認。`s14`の連続2回実行、`npm run lint:md`、`scripts/quality-gate.sh`、M02 smokeの再実行 | FR-007、FR-013、NFR-007、NFR-008 | ゲートが`quality-gate: passed`。連続2回の結果が同じ。コンテナが残らない |

### 7.1 要件の網羅表

| 要件 | 対応する単位 |
| --- | --- |
| FR-001 | U2 |
| FR-002 | U2 |
| FR-003 | U2、U4、U5 |
| FR-004 | U7 |
| FR-005 | U1、U3、U4、U5 |
| FR-006 | U1、U5 |
| FR-007 | U9、U11 |
| FR-008 | U1、U4、U5 |
| FR-009 | U9 |
| FR-010 | U7、U8 |
| FR-011 | U7 |
| FR-012 | U10 |
| FR-013 | U6、U11 |
| NFR-001 | U4、U9 |
| NFR-002 | U2、U4 |
| NFR-003 | U3、U4 |
| NFR-004 | U10 |
| NFR-005 | U4、U5 |
| NFR-006 | U4、U5、U10 |
| NFR-007 | U5、U11 |
| NFR-008 | U8、U11 |

FR-001からFR-013、NFR-001からNFR-008のすべてが、1つ以上の単位に対応している。

## 8. 実機で確かめる項目

clarifyから引き継いだ項目を、実装の前（U1）に確かめる。結果は`live-check.md`に、環境、手順、観測、結論の順で書く。
8.1から8.4と8.5の手順3は、リポジトリの外の`$KIROCREW_SCRATCH`配下の使い捨てコピーで行う。
8.5の手順1と2だけは、マウントの可否が場所に依存するため、実際のリポジトリ直下に`.s14-deny.<PID>`を作って行う。
これは「リポジトリのファイルを書き換えない」の唯一の例外で、終了時に必ず消す（4.3、`tasks.md` 1.4）。

使い捨てコピーでの実験には、次の隔離条件を課す。

| リスク | 条件 |
| --- | --- |
| コピーの場所がColimaのマウント対象外で、ファイルが見えない | 最初に`/__admin/mappings`の件数と`squid.conf`の中身を確かめる。見えなければコピーを`$HOME`配下へ移す |
| ポート3128、8080が使用中 | 開始前に`docker-compose ps -a -q`が空で、両ポートが空いていることを確かめる。使用中なら止めて報告する |
| プロジェクト名の取り違え | `docker-compose -p`で名前を明示し、終了時に同じ名前で`down --remove-orphans`する |

Dockerが使えない環境では、その項目を「未確認」と記録して止め、ユーザーに報告する。

### 8.1 Test Clientから送信元ACLを通った許可ドメインの要求

clarifyでは、Test Clientの要求を拒否側にした設定でしか確かめていない。許可側での成功を確かめる。

| 手順 | 内容 |
| --- | --- |
| 1 | 使い捨てコピーに、U2とU3の変更を入れる |
| 2 | `docker-compose up -d --build`で起動し、WireMockへ許可ドメイン用のマッピングを投入する |
| 3 | `docker-compose run --rm --no-deps test-client`のone-shot実行で、`squid:3128`経由の許可ドメインの要求を行い、`CLIENT_STATUS=200`と終了コード0を確かめる |
| 4 | squidのアクセスログで、その要求の送信元アドレスが`sidecar`のサブネット内で、判定が`TCP_MISS`であることを確かめる |
| 5 | 許可外ドメインの要求が拒否されることを確かめる |

成功の条件は、手順3が200、手順4が許可、手順5が拒否である。失敗した場合は、`acl local_src`の範囲を見直し、
U3の前に止めて報告する。

### 8.2 Linux CIでのループバック経由の送信元アドレス

ホスト公開が`127.0.0.1`でも、Linuxではdocker-proxyやiptablesの経路により、Squidから見た送信元が
ブリッジのゲートウェイやループバックになる。どちらでも許可範囲に入ることを確かめる。

| 手順 | 内容 |
| --- | --- |
| 1 | Linuxのホスト（GitHub Actionsのhostedランナー、または手元のLinux）で、使い捨てコピーを起動する |
| 2 | `curl --proxy http://127.0.0.1:3128`で許可ドメインを要求する |
| 3 | `docker-compose exec -T squid cat /var/log/squid/access.log`で、送信元アドレスと判定を読む |
| 4 | 送信元が`127.0.0.0/8`またはRFC1918の3範囲に入り、判定が`TCP_MISS`であることを確かめる |
| 5 | 記録には、実際のアドレスを書かず、どの範囲に入ったかだけを書く |

Linuxの環境が用意できない場合は、「未確認」と記録し、M09のCI導入時の確認項目として引き継ぐ。
その場合でも、S14の`live`はmacOSのColimaで確かめた結果で完了条件を満たす。ただしR-02は残リスクとして
`security-review.md`に書く。

### 8.3 `squid -k parse`の終了コード

clarifyでは出力にERRORとFATALがないことだけを確かめ、終了コードは記録していない。

| 手順 | 内容 |
| --- | --- |
| 1 | 現行の設定と変更後の設定のそれぞれで、`docker-compose exec -T squid squid -k parse`を実行し、終了コードと出力を記録する |
| 2 | WARNINGだけの場合の終了コードが0であることを確かめる |
| 3 | 使い捨てコピーで、わざと未定義のディレクティブを足した設定を作り、ERRORを起こしたときの終了コードを記録する |
| 4 | 出力にERRORまたはFATALが出る形式を記録する |

判定は、終了コードと文字列の両方で行う。現行の設定が終了コード0で、出力にERRORとFATALがないことを確かめる。
加えて、未定義のディレクティブを足した写しが非0で終わることを確かめる。
実機では、WARNINGだけの設定は終了コード0で、未定義のディレクティブは終了コード1だった。
後者はERRORとFATALの文字列を出さないため、文字列だけの判定では見逃す。

### 8.4 `docker-compose config --format json`

`static`の実装に必要な形式を確かめる。

| 手順 | 内容 |
| --- | --- |
| 1 | デーモンを止めた状態か、デーモンへ接続しない設定で`docker-compose config --format json`を実行する |
| 2 | `services.squid.ports`の要素が`target`、`published`、`host_ip`のキーを持つことを確かめる |
| 3 | 使えない場合は、YAML出力を`python3`で整形せずに読む代替（`host_ip:`行の検査）を採用し、planの4.3を直す |

### 8.5 一時ディレクトリのマウント

範囲外の送信元の検査（4.3）の前提を確かめる。

| 手順 | 内容 |
| --- | --- |
| 1 | リポジトリ直下の使い捨てディレクトリに置いた設定ファイルを、上書き用のComposeファイルでマウントする |
| 2 | `docker-compose exec -T squid cat /etc/squid/squid.conf`で、写しの内容が見えることを確かめる |
| 3 | 同じ確認を、ホストの一時ディレクトリ（`mktemp -d`）に置いたファイルでも行い、見えるかどうかを記録する |

手順2が成功すれば、4.3の設計をそのまま使う。失敗した場合は、`docker-compose cp`で設定を入れる方式に直す。
手順3の結果は、将来の利用者向けの注意として`live-check.md`に残す。

### 8.6 M02 smokeの個別実行

U9とU11で、スタックを起動し、3.3の起動待ちを入れた状態で`tests/m02-routing-smoke.sh`を実行し、成功を確かめる。
S14の変更後に、許可ドメインがWireMockに届き、許可外ドメインが拒否されること（FR-007）を含む。
実行後は`docker-compose down`でスタックを止め、コンテナが残らないことを確かめる。

## 9. 制約

- 本書の作成は、`plan.md`のみを対象にする。`spec.md`、`clarify.md`、実装、`git add`、コミット、プッシュは行わない
- plan作成の工程では、Dockerを実行しない。8章の実機確認は、実装工程のU1で行う
- 文書、ログ、検査出力に、AWSアカウントID、ARN、認証情報、実在のホスト名やIPアドレスを含めない
- 例にはダミー値（`api.example.com`、`<REMOTE_HOST>`、文書用の`192.0.2.0/24`）を使う
