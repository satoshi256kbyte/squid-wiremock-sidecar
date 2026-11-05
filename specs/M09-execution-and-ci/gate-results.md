# M09 前提ゲートの結果

## 判定表

| ゲート | 対応タスク | 確認項目 | 結果 | 分岐（plan 4.3） | 日時 |
| --- | --- | --- | --- | --- | --- |
| G4 完成版の生成の実装手段 | T901 | 6 | 判定済み（通過） | python3の標準ライブラリで全項目が書ける | 2026-11-04 |
| G5 Squidのエントリポイント | T902 | 7 | 判定済み（通過） | 元のエントリポイントに引き渡せる（squidは`exec`されない） | 2026-11-04 |
| G1 コンテナ名の解決 | T903 | 9 | 判定済み（通過） | 解決できる。起動順はWireMock、pause、Squidに固定する | 2026-11-04 |
| G3 pause方式と送信元ACL（Colima） | T904 | 2、3 | 判定済み（通過。CIは未確認） | すべて期待どおり | 2026-11-04 |
| G2 ソケットなしのMiniStack | T905 | 4、5 | 判定済み（通過。観測4は既存証跡による。CIの初回で再確認） | 全項目が一致。タグを固定する | 2026-11-04 |

## G4 完成版の生成の実装手段

### G4 環境

- 日時: 2026-11-04
- Docker runtime: 使わない
- `python3`: 3.14.6（macOS、arm64）。ランナー（ubuntu-24.04）の版はT924で確認する
- `jq`: 1.7.1（`/usr/bin/jq`）。実装では使わない判断のため、有無の記録のみ

### G4 手順

- 実験スクリプトを`$KIROCREW_SCRATCH/g4`に置き、`python3 -B`で実行した（リポジトリには置かない）
- 比較した方式は二つ。テンプレートの`{{...}}`を文字列置換する方式と、パース後の文字列値だけを置換して
  再シリアライズする方式
- 値の例は `a/b:c@d\e"f` と改行を含む文字列

### G4 観測

| 観測 | 結果 |
| --- | --- |
| 1 特殊文字 | 文字列置換のみの方式は`Invalid \escape`でJSONが壊れた。パース後に値を置換する方式は、値が再パースで一致した |
| 2 未置換と許可外キー | 未置換の`{{UNKNOWN_ONE}}`を検出できた。許可リスト外の`volumes`と`logConfiguration`を名指しできた。値の欠落（`SQUID_IMAGE`）は例外で検出できた |
| 3 同じバイト列 | 同じ入力を2回描画し、バイト列が一致した（446バイト） |
| 4 比較 | 環境変数の順序差と、AWSが足す空の`mountPoints`、`volumesFrom`を無視して一致と判定できた。値の変更は不一致になった |
| 5 版と有無 | `python3` 3.14.6、`jq` 1.7.1あり。ランナーの版は未確認（T924） |

### G4 分岐の決定

- 結果の行: 「`python3`の標準ライブラリで全項目が書ける」
- 決定: 採用する。生成、比較、`docker run`への変換は`python3`の標準ライブラリで実装する。`jq`は使わない
- 注意: 置換は文字列全体ではなく、パース後の文字列値に対して行う（文字列置換のままではJSONが壊れる）
- 前提検査（T907）は`python3`と`curl`を見る。POSIX shだけの実装は選ばない

### G4 後続への影響

- T908（テンプレートと生成）: 置換はパース後の値に対して行い、出力は固定形式（インデント2、入力のキー順、末尾改行）にする
- T907: 前提検査で`python3`を必須とし、`jq`は検査しない
- `spec.md`の変更: 無し

## G5 Squidのエントリポイント

### G5 環境

- 日時: 2026-11-04
- Docker runtime: Colima（`DOCKER_HOST`をColimaのソケットに設定）。Docker Server 29.5.2、Ubuntu 24.04.4、aarch64
- `DOCKER_CONFIG`: `~/.docker/config.json`の読み取りが`Operation not permitted`になったため、
  `$KIROCREW_SCRATCH/docker-config`に空の`{}`を置いて指定した。内容は読んでいない
- イメージ: `ubuntu/squid:latest`
  - イメージID: `sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029`
  - RepoDigest: `ubuntu/squid@sha256:6a097f68bae708cedbabd6188d68c7e2e7a38cedd05a176e1cc0ba29e3bbe029`
  - サイズ: 69158201バイト。Squidの版は6.13
- `python3`: 3.14.6（検査には使わない。ゲート用の書き換えは`awk`と`tar`で行った）

### G5 手順

1. `docker pull ubuntu/squid:latest`（取得済みで最新）
2. `docker image inspect`で`Config`を読む（`User`、`Entrypoint`、`Cmd`、`Env`、`Volumes`）
3. `docker run --rm --entrypoint cat`で、イメージ内の`/usr/local/bin/entrypoint.sh`を読む（起動はしない）
4. 使い捨てのコンテナ（`--rm`、名前`swsc-gate-g5-*`、ラベル`swsc.managed=true`）で、マウントもtmpfsも無しに
   `/var/log/squid`と`/var/spool/squid`への書き込みを確かめた
5. `squid.conf`の写しを`awk`で2種類作った。`mock`は`cache_peer`行を
   `cache_peer swsc-gate-wiremock parent 8080 0 no-query name=wiremock`へ置換した。`direct`は
   `cache_peer`、`cache_peer_access`の3行と`never_direct`を除き、`always_direct allow api_domains`を足した。
   写しは`$KIROCREW_SCRATCH/g5`に置き、リポジトリには置かなかった
6. 写しを`tar`で標準入力からコンテナへ渡し、`squid -k parse -f /etc/squid/squid.conf`を実行した。
   マウントは使わなかった

### G5 観測

| 観測 | 結果 |
| --- | --- |
| 1 イメージの設定 | `Entrypoint`は`["entrypoint.sh"]`、`Cmd`は`["-f","/etc/squid/squid.conf","-NYC"]`、`User`は未設定（root）。`ExposedPorts`は3128/tcp。`Volumes`に`/var/log/squid`と`/var/spool/squid`が宣言されている |
| 2 元のエントリポイント | `/usr/local/bin/entrypoint.sh`は、snakeoil証明書の再作成、`tail -F`で4つのログをstdoutへ流す、`squid -Nz`でキャッシュディレクトリを作る、`/usr/sbin/squid "$@"`を実行する。設定ファイルは上書きせず、環境変数に依存しない。`squid`は`exec`されず子として動く |
| 3 書き込み | マウントもtmpfsも無しで、`/var/log/squid`と`/var/spool/squid`は`proxy`所有で書き込めた。`/etc/squid`はrootが所有する |
| 4 `parse`（mock） | `cache_peer swsc-gate-wiremock parent 8080 0 no-query name=wiremock`と`cache_peer_access`、`never_direct`を含む設定が、`squid -k parse`を通った（終了コード0）。`name=wiremock`は受理された |
| 5 `parse`（direct） | `always_direct allow api_domains`を含む設定が`squid -k parse`を通った（終了コード0）。`'::/0'`の警告が出たが、既存の`acl all src all`由来で終了コードには影響しない |

### G5 分岐の決定

- 結果の行: 「元のエントリポイントに`exec`で引き渡せる」
- 決定: 引き渡しを採用する。`plan.md` 3.4の手順4は`exec /usr/local/bin/entrypoint.sh "$@"`とし、
  引数は`-f /etc/squid/squid.conf -NYC`（イメージの`Cmd`と同じ）とする
- 注意: 元のエントリポイントは`squid`を`exec`しないため、`docker stop`のSIGTERMが`squid`へ届かない可能性がある。
  停止は`docker rm -f`（SIGKILL）で行う（plan 6.2と整合）
- 注意: 元のエントリポイントは起動時に`squid -Nz`を実行するため、派生した設定は、引き渡しより前に
  `/etc/squid/squid.conf`へ書いておく（派生、`parse`、引き渡しの順）
- `parse`はtmpfsなしで通る。起動前の`squid -k parse`による検査を残す
- `name=wiremock`は受理されるため、`cache_peer_access`の2行は書き換えない
- `pid_filename none`のため`squid -k check`は使えない（plan 3.1の`kill -0 1`の理由と一致）

### G5 後続への影響

- T910（Squidのイメージ）: `entrypoint.sh`は、派生、`squid -k parse -f /etc/squid/squid.conf`、`upstream=<mock|direct>`の出力、
  `exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC`の順にする。`derive-config.sh`の規則は変えない
- T910: 派生元の行の存在検査は、`cache_peer wiremock parent 8080 0 no-query`、`cache_peer_access wiremock allow api_domains`、
  `cache_peer_access wiremock deny all`、`never_direct allow api_domains`の4行を対象にする
- T910と文書: 停止時のSIGTERM非転送は`smoke`の対象外とし、停止は`rm -f`で行う旨を書く
- `spec.md`の変更: 無し

## G1 コンテナ名の解決

### G1 環境

- 日時: 2026-11-04
- Docker runtime: Colima（G5と同じ）。`swsc-net`（bridge、ラベル付き）
- イメージ: `alpine:3.20`（`alpine@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc`）、
  `wiremock/wiremock:3.13.1`（`wiremock/wiremock@sha256:d61e7720f89483fdef5366843b58d1dfd06bcce5828179c9f2f54de5c28354b0`）、
  `ubuntu/squid:latest`（G5と同じ）
- クライアント: `Dockerfile.test-client`を`swsc-gate-client`としてビルドした（リポジトリ直下の文脈。マウントなし）
- 事前に、ポート8080と4566が空いていることを`lsof`で確かめた

### G1 手順

- コンテナはすべて`swsc-gate-*`の名前とラベル`swsc.managed=true`を付けた
- `swsc-gate-pause`（`alpine:3.20`、`sleep infinity`）と`swsc-gate-wiremock`（ポート`127.0.0.1:8080`だけ公開、
  `wiremock-scenarios`を読み取り専用で`/home/wiremock`へ）を`swsc-net`に置いた
- `swsc-gate-squid`は`--network container:swsc-gate-pause`で作り、G5の`mock`の写しを`docker cp`で入れて起動した
  （マウントは使わなかった）
- 順序A（WireMockを先に起動）: WireMockの管理APIの応答を待ってから、Squid、Clientの順に起動した
- 順序B（Squidを先に起動し、WireMockは後から起動）: Squidを起動し、4秒後にWireMockを起動して、要求を1回送った
- Clientは`swsc-gate-client`を`--network container:swsc-gate-pause`で実行し、
  `HTTP_PROXY=http://127.0.0.1:3128`、`TEST_API_BASE_URL=http://api.example.com`を与えた

### G1 観測

| 観測 | 結果 |
| --- | --- |
| 1 解決の失敗が出ないか | 順序Aで、Squidの`cache.log`に`Configuring Parent wiremock`が出て、名前解決の失敗は0件だった。要求の後も0件だった |
| 2 Squid経由の応答 | 順序Aで、Clientは`CLIENT_STATUS=200`を受けた（終了コード0）。`access.log`は`TCP_MISS/200`、`FIRSTUP_PARENT/172.31.0.3`。Squidは名前をIPアドレスに解決して接続した |
| 3 起動順の影響 | 順序Bでは、Squidの起動時にWireMockの名前が引けず、`WARNING: DNS lookup for 'wiremock' failed!`が出た。WireMockを後から起動した後の要求は`502`（`ERR_READ_ERROR`）になり、復帰しなかった。Squidはピアの解決を起動時に行い、後から再解決しないと判断した |
| 4 ColimaとLinuxの差 | Linux（GitHub Actions）の結果は未確認（T924で確認する） |

観測2の補足: WireMockの受信数は、要求1回につき`/api/users/123`以外に、Squidが起動後に送る
`/squid-internal-periodic/store_digest`を1件数えた。このため、受信総数（`meta.total`）をそのまま比較すると、
許可ドメインの要求の件数が1件ずれる（G3で確認）。

### G1 分岐の決定

- 結果の行: 「解決できる」。ただし、順序Bの結果から、起動順は固定する
- 決定: コンテナ名を`SQUID_MOCK_HOST`に渡す（FR-910どおり）。起動順は、WireMockの管理APIの応答を待ってから、
  pause、Squidの順にする
- 注意: 順序Bの結果から、WireMockがSquidより後に起動する経路は作らない（`start`の待機で保証する）。
  順序を守れない場合は、IPアドレス方式（`docker inspect`）へ切り替える判断をT906で行う

### G1 後続への影響

- T912（ランナー）: WireMockの待機、pause、Squidの順に起動する。Squidの作成の前に、WireMockの管理APIの応答を確かめる
- T912と`unit`: 起動順を、偽の`docker`の呼び出し記録で固定する
- T914（`smoke`）: WireMockの受信数は、URLで絞って数える（`/api/`で始まるものだけ）。`store_digest`を数えない
- `spec.md`: 変更無し（FR-910とQ-915の「コンテナ名」は、この決定どおり）

## G3 pause方式と送信元ACL（Colima）

### G3 環境

- 日時: 2026-11-04
- Docker runtime: Colima。G1と同じ構成（`swsc-net`、`swsc-gate-pause`、`swsc-gate-wiremock`、`swsc-gate-squid`）
- 起動順は G1の決定どおり、WireMock、pause、Squidとした
- 実験の本体は`$KIROCREW_SCRATCH/g1/g3.sh`（リポジトリ外）

### G3 手順と観測

| 観測 | 結果 |
| --- | --- |
| 1 許可ドメインが200 | `api.example.com`への要求が`CLIENT_STATUS=200`（終了コード0）。WireMockの本文を受けた |
| 2 送信元と`local_src` | `access.log`の送信元は`127.0.0.1`。`http_access allow local_src api_domains`で許可された（`TCP_MISS/200`） |
| 3 許可外ドメインの拒否 | `blocked.example.net`への要求は`CLIENT_STATUS=403`。`access.log`は`TCP_DENIED/403`。要求の前後でWireMockの受信数は変わらなかった（2のまま） |
| 4 Squidだけの再起動 | `docker restart swsc-gate-squid`の後も、pauseは`Up`のままで、`api.example.com`への要求が`CLIENT_STATUS=200`になった |
| 5 `sleep infinity` | `alpine:3.20`（busybox）で、`sleep infinity`がPID 1として動いた |

### G3 分岐の決定

- 結果の行: 「すべて期待どおり」
- 決定: 採用する。`squid.conf`は変更しない（S14の検査が固定している）。`derive-config.sh`で`local_src`を変える必要は無い
- CIでの確認（GitHub Actionsのランナー）は、この時点では行わない。T924で、本番のworkflowの初回実行で確かめる

### G3 後続への影響

- T914（`smoke`）: 項目1と項目3の受信数の判定は、`/api/`で始まるURLだけを数える。
  `swsc_wiremock_total`（`plan.md` 5.2の項目2）の定義を、この規則に直す。`plan.md`の文言を変えるかは、T906で判断する
- T912: pause方式の`sleep infinity`はそのまま使う
- `spec.md`: 変更無し

## G2 ソケットなしのMiniStack

### G2 環境（準備時点）

- 日時: 2026-11-04
- Docker runtime: Colima。ポート4566は空いていることを確かめた
- ローカルに`ministackorg/ministack:latest`（ダイジェスト`sha256:71b13e2045075b4faef3a0457db5ee33dce446fa1230ec6b75192b9c364b0f33`、
  ラベルの版1.5.36）があるが、これは候補ではない（固定するタグを選ぶ）

### G2 候補のタグ

| 項目 | 内容 |
| --- | --- |
| 候補 | `ministackorg/ministack:1.5.37` |
| 根拠1 | Docker Hubのタグ一覧で、`1.5.37`が最も新しい版（`last_updated` 2026-11-04T10:26:04Z）。`latest`と同じ版を指す |
| 根拠2 | `docker manifest inspect ministackorg/ministack:1.5.37`が成功した。linux/amd64のダイジェストは`sha256:e53f273e5c2d03bb23089e6b2350607fe53184c86360c7f6b8613152bc1bcef7`、linux/arm64は`sha256:094a6d8556352f208f38e2a714cd231f6d18e2c9fa861a36d573154f498d0a6e`（`latest`のindexと一致） |
| 注意 | 公開から1日未満の版である。G2の結果が`smoke`で問題を起こすなら、前の版`1.5.36`（2026-11-02公開）へ戻す |
| 除外 | `latest`と、日付だけのタグは使わない（`1.5`のような浮動タグも使わない） |

### G2 完成版（テストの入力）

- `$KIROCREW_SCRATCH/g2/taskdef.json`を作成した（`jq`で読めることを確認。プロファイルは`mock`相当）
- 中身は`plan.md` 3.1のテンプレートの`{{...}}`を、`swsc-client:gate`、`swsc-squid:gate`、`mock`に置換したもの
- リポジトリ直下の`.e2e/gate/`には置かなかった（リポジトリ直下の一時物を残さないため。T906の前に作業を終える）

### G2 利用者の端末で実行する手順

前提: リポジトリのルートで実行する。`aws` CLIが必要。ダミー認証情報は、この手順の中だけで設定する。

```sh
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=ap-northeast-1
EP=http://127.0.0.1:4566
# Colimaを使う場合のみ
export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock

# 実AWSの認証情報が環境変数に無いことを確かめる（この出力が3であること）
env | grep -c '^AWS_'

# 1. ソケットを渡さずに起動する
time docker pull ministackorg/ministack:1.5.37
docker run -d --name swsc-gate-ministack --label swsc.managed=true \
  -p 127.0.0.1:4566:4566 ministackorg/ministack:1.5.37
docker image ls ministackorg/ministack --format '{{.Tag}} {{.Size}}'

# 2. 応答を待つ（応答しない場合は、その旨を貼り付ける）
aws --endpoint-url "$EP" ecs list-task-definitions

# 3. 登録する
aws --endpoint-url "$EP" ecs register-task-definition \
  --cli-input-json file:///Users/satoshi/.kiro/crew/scratch/runtime-df5dc60c/g2/taskdef.json \
  --query 'taskDefinition.revision'

# 4. 項目ごとに取り出す
aws --endpoint-url "$EP" ecs describe-task-definition --task-definition swsc-e2e \
  --query 'taskDefinition.{nm:networkMode,cpu:cpu,mem:memory,req:requiresCompatibilities,c:containerDefinitions[].{n:name,i:image,e:essential,env:environment,p:portMappings,d:dependsOn,h:healthCheck}}'

# 5. 出力とログに、12桁の数字とARNが出るか（数字は<ACCOUNT_ID>に置換して表示する）
aws --endpoint-url "$EP" ecs describe-task-definition --task-definition swsc-e2e \
  | grep -Eo 'arn:aws[^"]*|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)' | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'
docker logs swsc-gate-ministack 2>&1 \
  | grep -Eo 'arn:aws[^"]*|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)' | sed -E 's/[0-9]{12}/<ACCOUNT_ID>/g'

# 6. 回収する
docker rm -f swsc-gate-ministack
docker ps -aq --filter label=swsc.managed=true
```

利用者に貼り付けてほしい内容は、手順1の`docker image ls`の出力、手順2から5の出力、手順6の結果である。
アカウントIDの実値、ARN、認証情報、`~/.aws`の内容は貼らない。

### G2 実行結果（利用者の端末。貼り付けられた事実）

- 日時: 2026-11-04
- イメージ: `ministackorg/ministack:1.5.37`
  - ダイジェスト: `sha256:cdfa6ba04f4c7febd9e14a34a21e31b9f0fb5279ee6af545784c05219f5a59a4`
  - サイズ: 261MB
  - 上のダイジェストが、マルチアーキテクチャのindexか、イメージIDかは、貼り付けからは分からない（未確認）
- 取得時間は貼り付けに無い（未記録）
- 後始末は確認済み（`swsc-`ラベルのコンテナは0件）

### G2 観測

| 観測 | 結果 |
| --- | --- |
| 1 ソケットなしの起動と応答 | Dockerソケットを渡さず、`-p 127.0.0.1:4566:4566`で起動できた。ダミー認証情報（環境変数`test`）で`aws ecs list-task-definitions`が空の一覧を返した。待機の確認先は`list-task-definitions` |
| 2 登録 | 完成版（family `swsc-e2e`、awsvpc、FARGATE、cpu 512、memory 1024、`client`と`squid`の2コンテナ）を`register-task-definition`で受理した。リビジョンは1。`cpu`、`memory`、`requiresCompatibilities`は拒否されなかった |
| 3 describeの忠実度 | 入力と項目ごとに一致した。`networkMode`、`cpu`、`memory`、`requiresCompatibilities`、`client`の`essential`（false）、`environment`4件、`dependsOn`（`squid` HEALTHY）、`squid`の`essential`（true）、`portMappings`（3128、tcp）、`environment`、`healthCheck`（`CMD-SHELL kill -0 1`、interval 5、timeout 3、retries 5、startPeriod 10）。入力に無い項目（`squid`の`dependsOn`、`client`の`portMappings`と`healthCheck`）はnullだった。`hostPort`は足されなかった |
| 4 識別情報 | 終了後の再確認は、MiniStackが停止済みのため取れなかった。以前の検証（同系統のMiniStackイメージ）で、`register-task-definition`の出力に`arn:aws:ecs:<region>:<ダミーの12桁>:task-definition/<family>:<rev>`が出ることを確認している。MiniStackの出力には、ARNとダミーの12桁が含まれるとみなす。実アカウントIDではないが、FR-918の検査は拾う |
| 5 取得時間と大きさ | 大きさは261MB。取得時間は未記録 |
| 6 固定したタグ | `1.5.37` |

未確認の事項は次のとおり。

| 事項 | 扱い |
| --- | --- |
| 観測4の一部（describeの完全出力とMiniStackのログ） | 既存証跡による。CIの初回（T924）で再確認する |
| AWSの実サービスのように、空の`mountPoints`などが足される可能性 | `--query`で取り出した項目に含めていないため未確認。比較で空の既定項目を無視する規則で吸収する |
| 取得時間 | 未記録。T924の実測で補う |
| 貼り付けたダイジェストの種別 | 未確認。`tag@sha256`の参照形式にするかは、T911で`docker image inspect`により確かめてから決める |

### G2 分岐の決定

- 結果の行: 「登録とdescribeが応答し、全項目が一致して返る」
- 決定: 通過（観測4は既存証跡による。CIの初回で再確認）。採用する
- 決定: タグを`ministackorg/ministack:1.5.37`に固定し、貼り付けのダイジェストを記録する（NFR-909）
- 決定: 公開から1日未満の版である。問題が出た場合は`1.5.36`へ戻す
- 決定: 出力またはログにダミーのアカウントIDとARNが出る行にも当たる。出力は`--query`で除外し、
  contractの出力とログは、識別情報の検査の前にマスクしてから保存する（保存しない選択もできる）
- 決定: 利用者の判断を求める行（ソケットなしで起動しない場合）には当たらない

### G2 後続への影響

- T907: 定数にMiniStackのタグ`1.5.37`を置く
- T911: 比較は、完成版とdescribeの出力を、順序差と空の既定項目（`mountPoints`、`volumesFrom`など）を無視して行う。
  イメージは`1.5.37`のタグで固定し、`1.5.36`への切り戻しは、問題が出たときに限る
- T913: 収集のマスクの処理を入れる。contractの出力・ログは、識別情報の検査の前にマスクしてから保存する
- T924: 観測4と取得時間をCIの初回で確かめる
- `spec.md`: FR-904、FR-918、NFR-909、1.2を直した。`plan.md`: 3.5、3.7、5.4、12章、13章を直した

## T906 ゲートの判定と反映

### T906 判定の結果

| ゲート | 結果 | 分岐（plan 4.3） | 反映先 |
| --- | --- | --- | --- |
| G4 完成版の生成の実装手段 | 通過 | `python3`の標準ライブラリで全項目が書ける。前提検査は`python3`と`curl`。`jq`は使わない | 確認のみ。`spec.md` FR-912、NFR-911と`plan.md` 3.2、3.8、4.3は反映済み |
| G5 Squidのエントリポイント | 通過 | 元のエントリポイントに引き渡せる。停止は`docker rm -f` | `plan.md` 3.4の手順4、6.2。`spec.md` FR-911。`tasks.md` T910 |
| G1 コンテナ名の解決 | 通過（CIは未確認） | 解決できる。起動順はWireMockの待機、pause、Squidに固定する | `spec.md` FR-906、FR-910。`plan.md` 3.3、3.8、4.3、5.1。`tasks.md` T912 |
| G3 pause方式と送信元ACL | 通過（CIは未確認） | すべて期待どおり。受信数は`/api/`で始まるURLだけを数える | `spec.md` FR-907。`plan.md` 3.8、5.1、5.2。`tasks.md` T913、T914 |
| G2 ソケットなしのMiniStack | 通過（観測4は既存証跡による。CIの初回で再確認） | 全項目が一致。タグ`1.5.37`を固定する。ログの識別情報はマスクする | `spec.md` 1.2、FR-904、FR-918、NFR-909。`plan.md` 3.5、3.7、5.4、12章、13章。`tasks.md` T907、T911、T913 |

### T906 通過条件の確認

| 条件 | 結果 |
| --- | --- |
| 1 全節が揃い、観測に欠けが無い | G2の観測4（完全出力とログ）と取得時間を除き、揃っている。欠けは上の「未確認の事項」に明記した |
| 2 分岐が一つに決まっている | 決まっている |
| 3 G2が「利用者に判断を求める」行に当たっていない | 当たっていない |
| 4 ゲート用の資源が回収されている | 利用者の端末で`swsc-`ラベルのコンテナは0件。このタスクでDockerは起動していない。`git status --short`の差は`specs/M09-execution-and-ci/`だけ |

### T906 未了事項

- G1とG3のCIでの確認（T924）
- G2の観測4の再確認と取得時間の実測（T924）
- `tasks.md`の完了条件の「ゲートを通過」は、上の通過条件1の欠けを許容した判定である
