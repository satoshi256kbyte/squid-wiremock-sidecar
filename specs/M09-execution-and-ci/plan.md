# M09実装計画

## 1. 実装方針

M09は、ローカルとGitHub Actionsの実行基盤を、docker-composeからECSタスク定義方式へ一本化する。
タスク定義の静的テンプレートから完成版を生成し、同じ生成手順と入力で作った同一バイト列のJSONを2か所に使う。
1か所目はMiniStackへの登録とdescribeによる契約検証（`contract`操作）、2か所目はpauseコンテナ方式の起動（`start`操作）である。
入口は`package.json`の6つのscriptsと、実体の`scripts/e2e.sh`の1本にそろえる。補助操作は`collect`、`check-production`、`contract`の3つである。

既存の検査（M02〜M08、S14）と`docker-compose.yml`は変更しない。移行と削除は別Issueとする（FR-920、Q-912のA案）。
新基盤はdocker-composeを呼ばず、切り戻しの処理も持たない。
`squid-config/squid.conf`は単一の情報源とし、新基盤のSquidイメージが起動時に派生させる。

実装の順序は次の方針に従う。

- 結果で設計が変わる実機確認を「前提ゲート」として、実装単位の最初（U1）に置く
- Dockerを使わない部分（生成、変換、比較、派生、入口の判断）を先に作り、`unit`で固定する
- Dockerを使う部分は、ゲートの結果を反映してから作り、`smoke`で確かめる
- 本番のスクリプトにテスト専用の分岐は入れない。失敗の注入は、偽の`docker`と`aws`を`PATH`の先頭に置くか、
  子プロセスとして本物の入口を起動して行う（M08の方式）

検査の入口は`tests/m09-execution-and-ci.sh`とし、`unit`、`smoke`、`contract`の3モードを持つ（FR-922）。
引数なしは`smoke`、不正な引数は終了コード2とする。

2種類の制約が、検査を3層に分ける理由である。

- エージェントのシェルは、AWS認証情報の環境変数を設定できない（安全ポリシー。回避しない。NFR-902）
- pause方式の通信検証はDockerだけで動き、AWS CLIを要するのはMiniStackの契約検証だけである

| 層 | 要るもの | エージェント | CI | 利用者の端末 | 品質ゲート |
| --- | --- | --- | --- | --- | --- |
| `unit` | なし（偽の`docker`と`aws`） | 実行する | 実行する | 実行する | 登録する |
| `smoke` | Docker。AWS CLIと認証情報は不要 | 実行する | 実行する | 実行する | 登録する |
| `contract` | Dockerとダミー認証情報 | 実行しない（未検証と報告） | 実行する | 実行する | 登録しない |

## 2. 変更ファイル

### 2.1 新規

| パス | 責務 |
| --- | --- |
| `ecs/task-definition.template.json` | タスク定義の静的テンプレート（3.1）。ClientとSquidの2コンテナ、awsvpc |
| `ecs/squid/Dockerfile` | `ubuntu/squid`を基底にしたSquidのイメージ（3.4） |
| `ecs/squid/derive-config.sh` | `squid.conf`から、`SQUID_UPSTREAM`に応じた設定を派生させる。Dockerなしで検査できるよう分離する |
| `ecs/squid/entrypoint.sh` | 値の検査、派生、`squid -k parse`、上流のログ出力、元のエントリポイントへの引き渡し |
| `scripts/e2e.sh` | 入口。操作の振り分け、引数の検査、終了コード、`trap`（3.8）。操作は`start`、`test`、`logs`、`stop`、`clean`、`test:ci`、`collect`、`check-production`、`contract` |
| `scripts/e2e-lib.sh` | 共通の関数。名前と版の定数、前提検査（smoke層とcontract層。3.8）、`aws`と`docker`の薄い包み、待機、後始末、収集（3.7、6章）、完成版の生成関数`swsc_render` |
| `scripts/e2e-runner.sh` | pauseコンテナ方式の起動とClientの実行（3.3）。MiniStackは扱わない |
| `scripts/e2e-contract.sh` | `contract`操作の本体。MiniStackの起動、登録、describe、比較、削除（3.5）。MiniStackの起動の担当はここだけ |
| `scripts/e2e-taskdef.py` | 完成版の生成、本番向けの検査、契約の比較、`docker run`の引数への変換（3.2、3.6）。標準ライブラリだけ |
| `tests/m09-execution-and-ci.sh` | 検査入口。`unit`、`smoke`、`contract`（5章） |
| `.github/workflows/e2e-test.yml` | CIのworkflow（3.9） |
| `docs/ローカル実行とCI.md` | 検証手順の文書（9章） |
| `specs/M09-execution-and-ci/gate-results.md` | 前提ゲートの記録（4章、U1） |
| `specs/M09-execution-and-ci/contract-results.md` | 利用者の端末での`contract`の実行結果の記録（5.4、T925）。識別情報を含めない |
| `specs/M09-execution-and-ci/tasks.md`、`analyze.md` | 後続のSpec Kit成果物 |

### 2.2 変更（最小限）

| パス | 変更内容 |
| --- | --- |
| `package.json` | scriptsに`start`、`test`、`logs`、`stop`、`clean`、`test:ci`の6つを足す。`lint:md`は変えない |
| `.gitignore` | `.e2e/`と`e2e-logs/`を足す |
| `README.md` | 実行手順を新基盤の記述に更新する。旧Compose手順は残し「移行完了後に削除」と明記する（9章） |
| `scripts/quality-gate.sh` | M09の`unit`と`smoke`を足す。`contract`は足さない（5.3）。既存の行は変えない |
| `AGENTS.md` | 変更範囲別の品質ゲート表に、新基盤の行を足す。表の末尾の「Ministackを追加した場合は表へ追加する」に従う |
| `specs/M09-execution-and-ci/spec.md` | ゲートの結果で食い違いが出た箇所だけ直す（12章） |

### 2.3 変更しない

| パス | 理由 |
| --- | --- |
| `docker-compose.yml` | FR-920。別Issueで削除する |
| `tests/m02`から`m08`、`tests/s14-compose-port-binding.sh` | FR-920、NFR-903。別Issueで移行する |
| `squid-config/squid.conf`、`squid-config/whitelist.txt` | S14が行を固定で検査する。派生元として読むだけにする |
| `wiremock-scenarios/`、`test-client/`、`Dockerfile.test-client` | NFR-903。イメージは既存のDockerfileからそのままビルドする |
| `scripts/scenario-lib.sh` | 読み込んで再利用するだけにする（`wiremock_reset`、`wiremock_verify_reset`） |
| `.dockerignore`、`docs/requirements.md`、`docs/roadmap.md`、ルートの`plan.md` | 範囲外 |

実装の最後に`git diff --name-only origin/main...HEAD`を取り、2.1と2.2の一覧に収まることを確かめる（U13）。

## 3. 構成要素の設計

### 3.1 タスク定義テンプレート

`ecs/task-definition.template.json`は、AWS CLIの`--cli-input-json`にそのまま渡せるキーだけで書く。
コメント用のキーは持てない。説明は`docs/ローカル実行とCI.md`に書く。

```json
{
  "family": "swsc-e2e",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [
    {
      "name": "client",
      "image": "{{CLIENT_IMAGE}}",
      "essential": false,
      "environment": [
        { "name": "HTTP_PROXY", "value": "http://127.0.0.1:3128" },
        { "name": "HTTPS_PROXY", "value": "http://127.0.0.1:3128" },
        { "name": "NO_PROXY", "value": "localhost,127.0.0.1" },
        { "name": "TEST_API_BASE_URL", "value": "http://api.example.com" }
      ],
      "dependsOn": [{ "containerName": "squid", "condition": "HEALTHY" }]
    },
    {
      "name": "squid",
      "image": "{{SQUID_IMAGE}}",
      "essential": true,
      "portMappings": [{ "containerPort": 3128, "protocol": "tcp" }],
      "environment": [{ "name": "SQUID_UPSTREAM", "value": "{{SQUID_UPSTREAM}}" }],
      "healthCheck": {
        "command": ["CMD-SHELL", "kill -0 1"],
        "interval": 5, "timeout": 3, "retries": 5, "startPeriod": 10
      }
    }
  ]
}
```

決めたことは次のとおり。

| 項目 | 決定 | 根拠 |
| --- | --- | --- |
| WireMockの宛先 | テンプレートに書かない。完成版の生成が`local`プロファイルのときだけ、Squidの環境変数`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`を足す | テンプレートに`mock`の既定値とWireMockの宛先が無いことを、静的に検査できる（FR-909の層1） |
| `cpu`と`memory` | Fargateの有効な組み合わせ（0.5 vCPU、1 GB）を固定値で書く。G2でMiniStackが受理するか確かめる | FR-902。値はコンテナの動作に影響しない |
| ロール | `taskRoleArn`と`executionRoleArn`を書かない | アカウントIDを含むARNをリポジトリに置かない |
| Clientの`healthCheck` | 書かない | 1回で終了する（Q-918） |
| Squidの`healthCheck` | 旧基盤と同じ`kill -0 1`から始める。「待受の確認」は`start`の最後の待機（3.8）で別に行う | `pid_filename none`のため`squid -k check`が使えない。G5で代替の有無を確かめる |
| Clientの`dependsOn` | SquidのHEALTHY | ECSの標準的な表現。`test`がClientを起動する前に、Squidが稼働中であることを確かめる |
| プレースホルダー | `{{NAME}}`の形。名前は`CLIENT_IMAGE`、`SQUID_IMAGE`、`SQUID_UPSTREAM`の3つ | 生成側が許可リストで管理する |

### 3.2 完成版の生成（`scripts/e2e-taskdef.py render`）

実装手段はG4で確定する。既定は`python3`の標準ライブラリだけとする。理由は次のとおり。

- 既存の検査（M03、S14）が`python3`に依存している
- 生成だけでなく、契約の比較（3.5）と`docker run`の引数への変換（3.3）が、JSONの構造を読む必要がある
- POSIX shだけでは、JSONの構造を安全に読めない。値の文字種を許可リストで絞れば置換だけは書けるが、比較と変換が残る

呼び出しの形は次のとおり。

```sh
python3 -B scripts/e2e-taskdef.py render \
  --template ecs/task-definition.template.json --out .e2e/taskdef.json \
  --client-image swsc-client:e2e --squid-image swsc-squid:e2e \
  --profile local --upstream mock --mock-host swsc-wiremock --mock-port 8080
```

| 検査 | 失敗時 |
| --- | --- |
| 値の文字種。イメージは`[A-Za-z0-9._/:@-]`、ホストは英数字と`.`と`-`、ポートは数字だけ、`--upstream`は英数字と`-`と`_`だけ（長さ1〜32） | 名前を示して終了コード1。値は出さない。`mock`と`direct`の判定は、`local`プロファイルではSquid側が行う（FR-908。`smoke`が不正な値での起動失敗を確かめる） |
| 置換後に`{{`が残る。テンプレートに未知のプレースホルダーがある | 残った名前を示して終了コード1（FR-903） |
| 完成版に許可リスト外のキーがある（トップレベル、コンテナ）。`volumes`、`mountPoints`、`secrets`、`logConfiguration`、`taskRoleArn`など | キーの名前を名指しして終了コード1（Q-913、fail closed） |
| `dependsOn`の条件が`START`と`HEALTHY`以外、`healthCheck`の形式が`CMD-SHELL`以外 | 名指しして終了コード1（pause方式で再現できない） |
| `--profile production`で、`--upstream`が`direct`以外、または`--mock-host`、`--mock-port`が指定されている | 終了コード1（FR-909の層2） |
| 出力が`check-production`（3.6）の検査を通らない（productionのとき） | 終了コード1 |

出力は、キーの順序を固定し、末尾に改行を付け、同じ入力で同じバイト列になるようにする（NFR-905）。
生成は`e2e-lib.sh`の`swsc_render`の1か所に集め、`start`と`contract`の両方が同じ関数を同じ入力で呼ぶ。
`.e2e/taskdef.json`は、MiniStackへの登録と`docker run`の変換の両方が読む完成版である。
`contract`は`start`を前提にせず、自分で`swsc_render`を呼んで同じバイト列を作る（`unit`で、呼び出しが`swsc_render`だけであること、
別の生成経路が無いことを`grep`で確かめる）。

### 3.3 pauseコンテナ方式のランナー（`scripts/e2e-runner.sh`）

名前、ラベル、起動順は次のとおり。ラベルは全てに`swsc.managed=true`と`swsc.role=<役割>`を付ける。

| 順 | 対象 | コンテナ名 | ネットワーク | ホストへの公開 |
| --- | --- | --- | --- | --- |
| 1 | ネットワーク | `swsc-net` | bridge | なし |
| 2 | WireMock | `swsc-wiremock` | `swsc-net` | `127.0.0.1:8080`だけ。`wiremock-scenarios`を読み取り専用でマウント |
| 3 | pause | `swsc-pause`（`alpine:3.20`、`sleep infinity`） | `swsc-net` | なし |
| 4 | Squid | `swsc-squid` | `container:swsc-pause` | なし |
| 5 | Client（testごと） | `swsc-client-<PID>` | `container:swsc-pause` | なし |

MiniStack（`swsc-ministack`、既定のbridge、`127.0.0.1:4566`だけ、ソケットは渡さない）は、`contract`操作だけが起動する（3.5）。
`start`は起動しない。

完成版から`docker run`への変換は、`e2e-taskdef.py docker-args`が行う。
出力は、コンテナごとに`.e2e/run/<name>.args`（1行1引数）と`.e2e/run/<name>.env`（`--env-file`用）である。
シェルは`.args`を1行ずつ読み、位置引数に積んで`docker run`へ渡す。値に改行が含まれる場合は、変換の段階で失敗させる。

| ECSの項目 | docker runへの対応 |
| --- | --- |
| `name`、`image` | `--name swsc-<name>`、イメージ |
| `environment` | `--env-file`。値は引数に出さない（プロセス一覧に出さないため） |
| `essential` | trueのSquidが終了したら、`start`と`test`を失敗させる。falseのClientは`test`が1回だけ起動する |
| `portMappings` | 公開には使わない。同じ`containerPort`を2つのコンテナが使う場合は失敗させる |
| `dependsOn` | 起動順に変換する。`HEALTHY`は`docker inspect`の`State.Health.Status`を読んで待つ |
| `healthCheck` | `--health-cmd`、`--health-interval`、`--health-timeout`、`--health-retries`、`--health-start-period` |
| `command`、`entryPoint` | 引数と`--entrypoint` |

Clientは`docker run --rm`で起動し、検証ごとの環境変数の上書きは`-e`で足す。
終了コードと標準出力・標準エラーを、そのまま検証の入力に使う（Q-918）。

起動順は、WireMockの起動、WireMockの管理APIの応答の待機、pause、Squidの順に固定する（G1）。
Squidを先に起動すると、起動時にWireMockの名前を引けず（`DNS lookup for 'wiremock' failed`）、
WireMockを後から起動しても復帰せず、要求が502になる。このため、WireMockの待機より前にpauseとSquidを作る経路を作らない。
`unit`は、偽の`docker`と`curl`の呼び出し記録で、この順序を固定する。
WireMockの待機は、ホストの`curl`で`http://127.0.0.1:8080/__admin/mappings`が200になるまでとする。
Squidの待機は、ヘルスが`healthy`になった後に、pauseの名前空間に参加した使い捨てコンテナで
`nc -z 127.0.0.1 3128`が成功するまでとする。どちらも上限は120秒である（FR-917）。

### 3.4 Squidのイメージとエントリポイント（`ecs/squid/`）

イメージは`ubuntu/squid:latest`を基底にする（NFR-909、Q-907）。ボリュームのマウントに頼らない。
ビルドの文脈は、`start`が`.e2e/context/squid/`に作る。`squid-config/squid.conf`、`squid-config/whitelist.txt`、
`ecs/squid/`の3ファイルをコピーしたものである。リポジトリ全体を文脈にしない（`node_modules`を送らないため）。
コピーが`squid.conf`と同一であることは、`unit`で`cmp`により確かめる。

```text
FROM ubuntu/squid:latest
COPY squid.conf /etc/squid/squid.conf.src
COPY whitelist.txt /etc/squid/whitelist.txt
COPY derive-config.sh /usr/local/bin/swsc-derive-config.sh
COPY entrypoint.sh /usr/local/bin/swsc-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/swsc-entrypoint.sh"]
```

`entrypoint.sh`は次の順に動く。どれかが失敗したら、非ゼロで終了する（FR-908）。

1. `derive-config.sh /etc/squid/squid.conf.src /etc/squid/squid.conf`を実行する
2. `squid -k parse -f /etc/squid/squid.conf`で派生した設定を検査する
3. 標準出力に`swsc-squid: upstream=<mock|direct>`を1行出す（FR-909の層4）
4. 元のエントリポイントへ`exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC`で引き渡す（G5。引数はイメージの`Cmd`と同じ）

元のエントリポイントは起動時に`squid -Nz`を実行し、`squid`を`exec`せず子として動かす。
このため、派生した設定は、引き渡しより前に`/etc/squid/squid.conf`へ書く（派生、`parse`、引き渡しの順）。
`docker stop`のSIGTERMは`squid`へ届かない可能性があるため、停止は`docker rm -f`で行う（6.2）。
SIGTERMの非転送は`smoke`の対象外とする。tmpfsは要らない（G5の観測3）。

`derive-config.sh`の規則は次のとおり。行の比較は、正規表現でなく完全一致（`awk`の`$0 == 文字列`）で行う。

| 入力 | 動作 |
| --- | --- |
| `SQUID_UPSTREAM`が未設定、または`mock`と`direct`以外（大文字、前後の空白を含む） | 何も出力せず終了コード1 |
| `mock` | `SQUID_MOCK_HOST`は英数字、`.`、`-`だけ、`SQUID_MOCK_PORT`は数字だけ（1から65535）。外れたら終了コード1。`cache_peer wiremock parent 8080 0 no-query`の1行を`cache_peer <HOST> parent <PORT> 0 no-query name=wiremock`へ置換する |
| `direct` | `cache_peer`、`cache_peer_access`の3行と`never_direct`の1行を除き、`always_direct allow api_domains`を同じ位置に足す。`SQUID_MOCK_*`は無視する |
| 元の行が1行ずつ存在しない | 欠けた行を示して終了コード1（派生元の書式変更を検知する） |

`name=wiremock`を付けるのは、`cache_peer_access wiremock ...`の2行を書き換えずに済ませるためである。
この書式をSquidが受け付けることは、G5で確かめる。

### 3.5 MiniStackの契約検証（`contract`操作、`scripts/e2e-contract.sh`）

`contract`は、`scripts/e2e.sh contract`で呼ぶ補助操作である。MiniStackの起動、登録、describe、比較、削除を、この操作だけが担当する。
`start`、`test`、`test:ci`はMiniStackもAWS CLIも使わない。

AWS CLIの呼び出しは、`e2e-lib.sh`の包み`swsc_aws`1か所に集める。`swsc_aws`の呼び出し元は`e2e-contract.sh`だけである。
包みは、次を必ず行う。

- `--endpoint-url http://127.0.0.1:4566`と`--region ap-northeast-1`を毎回明示する
- `AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`が未設定、または`test`以外なら、呼び出さずに終了コード1（FR-905）。
  既定の認証情報にはフォールバックしない
- その1回の呼び出しに限り、`AWS_CONFIG_FILE=/dev/null`、`AWS_SHARED_CREDENTIALS_FILE=/dev/null`、
  `AWS_EC2_METADATA_DISABLED=true`を与え、`AWS_PROFILE`を外す。`~/.aws`と既定プロファイルを読ませない

`contract`は、MiniStackを起動する前に、同じ認証情報の検査（contract層の前提検査。3.8）を行う。
認証情報が不正なときは、コンテナを作らず、`aws`も呼ばずに終了コード1で止まる。

`unit`は、`scripts/e2e*.sh`でAWS CLI（`aws`コマンド）を直接呼ぶ箇所が包みの1か所だけであることを`grep`で確かめる。
また、`start`、`test`、`test:ci`が、偽の`aws`を呼ばず、認証情報が無くても動くことを確かめる。

手順は次のとおり。失敗したら、原因の段階名を示して終了コード1とする（FR-904）。
どの終了経路でも、`EXIT`の`trap`で`swsc-ministack`を削除する（他のコンテナには触らない）。

| 順 | 処理 |
| --- | --- |
| 1 | contract層の前提検査（Docker、AWS CLI、`python3`、ダミー認証情報）。既存の`swsc-ministack`を削除し、その後にポート4566を確認する（`swsc-`以外が使用中なら止まる） |
| 2 | `swsc_render`で`.e2e/taskdef.json`を作る（`start`と同じ関数、同じ入力） |
| 3 | `docker run -d --name swsc-ministack -p 127.0.0.1:4566:4566`と、`ministackorg/ministack:1.5.37`（G2で固定したタグ）。ソケットのマウントなし |
| 4 | `swsc_aws ecs list-task-definitions`が応答するまで待つ（上限120秒）。応答の確認先は`list-task-definitions`（G2で空の一覧を返した） |
| 5 | `register-task-definition --cli-input-json file://.e2e/taskdef.json`。出力は`--query taskDefinition.revision`だけ取り、ARNを取らない |
| 6 | `describe-task-definition`の出力を`--query`で必要な項目だけに絞り、`.e2e/ministack-describe.json`に残す。項目は`networkMode`、コンテナの`name`、`image`、`essential`、`environment`、`portMappings`、`dependsOn`、`healthCheck` |
| 7 | `e2e-taskdef.py compare .e2e/taskdef.json .e2e/ministack-describe.json`が、項目ごとに一致を確かめる。結果を`.e2e/ministack-contract.json`に残す。あわせて、`docker inspect --format`で`swsc-ministack`の`Mounts`と公開ポートだけを`.e2e/ministack-inspect.json`に残す |
| 8 | 失敗した場合は、削除の前に`collect`を呼び、`swsc-ministack`のログを`e2e-logs/`へ残す。その後、`swsc-ministack`を削除する |

比較は、完成版とdescribeの出力を、順序差（環境変数、コンテナ）と空の既定項目（`mountPoints`、`volumesFrom`など）を無視して行う。
G2で、describeは入力と項目ごとに一致した（`gate-results.md`）。入力に無い項目（`squid`の`dependsOn`など）はnullで返るため、
完成版側が無い項目は、null、空の配列、空のオブジェクトを同じとみなす。
完成版の側に無い項目がdescribe側にあっても、取り出す項目の外なら比較しない。
G2で見つかっていない変形が出た場合の扱いは4.3の表に従う。

MiniStackのイメージは`ministackorg/ministack:1.5.37`に固定する（NFR-909）。公開から1日未満の版のため、
問題が出た場合は`1.5.36`へ戻す。ダイジェストはG2で貼り付けられた値を`gate-results.md`に記録し、`env.txt`にも残す。
その値がindexかイメージIDかは未確認のため、`tag@sha256`の参照形式にするかは、T911で`docker image inspect`により確かめてから決める。

`contract`が保存する出力とログは、識別情報の検査（FR-918）の前にマスクする。MiniStackの出力にはARNとダミーの12桁が含まれるため、
`--query`で除外できない場合（ログ、`docker inspect`の出力）は、3.7のマスクを通してから`.e2e/`と`e2e-logs/`へ置く。

### 3.6 本番向けの検査（`check-production`）

`scripts/e2e.sh check-production <ファイル>`は、`e2e-taskdef.py check-production`を呼ぶ。
任意のタスク定義JSONに対して、次を全て満たすときだけ終了コード0とする。

| 条件 | 備考 |
| --- | --- |
| いずれかのコンテナに、環境変数`SQUID_UPSTREAM`がある | 欠落は不合格 |
| `SQUID_UPSTREAM`の値が、全ての出現で、完全一致の`direct`である | `mock`、`Mock`、`MOCK`、前後に空白のある`direct`、空は不合格 |
| どのコンテナにも、環境変数`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`が無い | 残っていれば不合格 |

不合格の出力には、環境変数の名前とコンテナの名前だけを書く。値は書かない。
JSONとして読めない、またはファイルが無い場合は終了コード2とする。
層1（テンプレートの静的検査）は、`unit`がテンプレートを読み、`mock`の文字列と`SQUID_MOCK_`の文字列が無いことを確かめる。

### 3.7 ログの収集（`collect`）

`scripts/e2e.sh collect`は、`e2e-logs/`へ次を集める（FR-921、Q-905）。

| 出力先 | 内容 |
| --- | --- |
| `containers/<名前>.log` | `swsc-squid`、`swsc-wiremock`、`swsc-ministack`の`docker logs` |
| `squid/access.log`、`squid/cache.log` | `docker exec swsc-squid cat /var/log/squid/...` |
| `taskdef.json` | `.e2e/taskdef.json`のコピー |
| `ministack-contract.json` | `.e2e/ministack-contract.json`のコピー |
| `test.out`、`test.err` | `test`が残した標準出力と標準エラー |
| `env.txt` | Dockerのバージョン、使ったイメージのダイジェスト。環境変数は書かない。AWS CLIのバージョンは書かない（`collect`はAWS CLIを呼ばないため） |

規則は次のとおり。

- 冪等にする。元が存在しないときは、既存の収集物を消さず、`missing.txt`に追記する。
  `test:ci`の内側で収集した後に、workflowが同じ収集を再実行しても、ログが空にならない
- 収集の失敗でtestの終了コードを変えない（`test:ci`の内側では収集の終了コードを捨てる）
- 最後に、識別情報の検査を行う（FR-918）。検査の正規表現は、`arn:aws`と、前後が英数字と`-`でない12桁の数字である。
  WireMockのログにあるUUIDの末尾12桁が、数字だけになる偶然の一致を拾わないための前置きである（R-07）
- 一致した行は、コピーの上でマスクしてから、残りがないことを再検査する。残ったファイルは削除し、
  `scrub.txt`にファイル名だけを記録する
- `scrub.txt`は、`collect`の実行の先頭で作り直す。その回の削除または記録があるときだけ、単独の`collect`は終了コード1にする。
  `test:ci`の内側の`collect`で削除が起きても、workflowの2回目の`collect`は、`scrub.txt`を作り直して同じ検査をやり直し、
  その回にマスクで除けないファイルが無ければ終了コード0を返す
- マスクを挟むのは、MiniStackのログがダミーのアカウントIDとARNを常に出す場合に、毎回ファイルが全削除されるのを防ぐためである。
  G2の判断として、マスクの処理を入れる（MiniStackの出力にはARNとダミーの12桁が含まれる。
  ただし、describeの完全出力とログでの確認は未了のため、CIの初回で実際に出るかを再確認し、出ない場合に限ってマスクを外す）

### 3.8 入口、終了コード、`test:ci`

`package.json`のscriptsは、`"start": "sh scripts/e2e.sh start"`の形で6つとも委譲する。
`logs`は追加の引数を受ける（`npm run logs -- squid -f`）。コンテナ名は`squid`、`wiremock`、`ministack`、`pause`のどれかに限る。

| 操作 | 内容 |
| --- | --- |
| `start` | smoke層の前提検査、既存の`swsc-`の停止、ポートの空き確認、イメージのビルド、`swsc-net`、完成版の生成（`swsc_render`）、WireMock、WireMockの管理APIの応答の待機、pause、Squid、待受の確認。MiniStackとAWS CLIは使わない |
| `test` | `start`済みの環境に対し、FR-907の3項目を実行する。Squidが稼働していなければ、Clientを起動せず失敗する |
| `logs` | `docker logs`を表示する |
| `stop` | 6章の規則で削除する。冪等 |
| `clean` | `stop`に加え、ビルドしたイメージ、`.e2e/`、`e2e-logs/`を削除する |
| `test:ci` | smoke層の前提検査、`start_main`、`test`、`collect`、`stop` |
| `contract` | 3.5。contract層の前提検査、`swsc_render`、MiniStackの起動、登録、describe、比較、削除 |
| `collect`、`check-production` | 3.7、3.6 |

#### 前提検査（操作ごと）

前提検査は`e2e-lib.sh`にあり、操作が必要とするものだけを検査する（FR-912）。ポートの空きは前提検査に含めず、
`start_main`と`contract`が自分の`swsc-`の停止を済ませた後に確認する。

| 検査 | smoke層（`start`、`test`、`test:ci`） | contract層（`contract`） |
| --- | --- | --- |
| `docker`、`python3` | 検査する | 検査する |
| `curl` | 検査する（WireMockの待機） | 検査しない |
| `aws` | 検査しない | 検査する |
| ダミー認証情報（未設定、`test`以外） | 検査しない | 検査する（`aws`と`docker run`の前） |
| ポート | 8080（`start_main`の停止の後） | 4566（`contract`の停止の後） |

ポートの使用中は、`python3`の`socket`で`127.0.0.1`への接続を試みて判定する（`swsc-`の停止の後に応答があれば使用中）。
応答したものは、`swsc-`以外のコンテナまたはプロセスである。旧基盤（docker-compose）の可能性をメッセージに書く。
旧基盤は名前で検出しない（プロジェクト名が任意のため）。

終了コードは、4章のspec.mdの表に従う。`start`の本体は`start_main`関数とし、`trap`を持たせない。
入口（`scripts/e2e.sh`）の`start`操作だけが、`start_main`の失敗時に`stop`するラッパーである。
`test:ci`は`start_main`を直接呼び、`set -e`の下でも`collect`に届くよう、`|| rc=$?`の形で受ける。

```sh
# test:ci 本体（set -e の下で動く形。trap の EXIT は collect と stop の最終防衛のみ）
rc=0
start_main || rc=$?
if [ "$rc" -eq 0 ]; then
  test_run || rc=$?
fi
collect || true
stop || true
exit "$rc"
```

`start`操作のラッパーは、次の形にする。

```sh
rc=0
start_main || rc=$?
if [ "$rc" -ne 0 ]; then stop || true; fi
exit "$rc"
```

`test`の3項目は次のとおり。各項目の前に`wiremock_reset`と`wiremock_verify_reset`を行う。
WireMockの受信数は、`e2e-lib.sh`の関数`swsc_wiremock_total`が、`curl`で`http://127.0.0.1:8080/__admin/requests`を取得し、
`python3`で`requests[].request.url`が`/api/`で始まるものだけを数えて返す（`meta.total`は使わない）。
Squidが起動後に送る`/squid-internal-periodic/store_digest`が混入し、許可ドメインの要求の件数が1件ずれるためである（G1、G3）。
`wiremock_count`はM06とM07に別々にあり、`scripts/scenario-lib.sh`に無いため、再利用しない。
許可外ドメインは`blocked.example.net`（`whitelist.txt`に無い）とする。

| 項目 | 要求 | 期待値 |
| --- | --- | --- |
| 1 許可ドメイン | 既定の`TEST_API_BASE_URL`（`http://api.example.com`）、パスは既存のシナリオの正常系（`/api/users/123`） | `CLIENT_STATUS=200`、終了コード0、`swsc_wiremock_total`（`/api/`で始まるURLだけ）が1 |
| 2 許可外ドメイン | `TEST_API_BASE_URL=http://blocked.example.net`（Clientへの`-e`の上書き）、パスは項目1と同じ | `CLIENT_STATUS=403`、`swsc_wiremock_total`が0のまま |
| 3 Squid再起動後 | `docker restart swsc-squid`とヘルス待機の後、項目1と同じ要求 | 項目1と同じ |

結果は、1項目1行の`PASS`または`FAIL`で標準出力へ出し、同じ内容を`e2e-logs/test.out`へ残す。
終了コードを保つため、出力は一度ファイルへ書き、終了コードを取ってから表示する（パイプにしない）。

`trap`は、6章の表に従う。`start`操作（ラッパー）が失敗した場合と、`INT`、`TERM`を受けた場合は、`stop`を呼ぶ。
`start_main`は`trap`を持たず、`test:ci`の中では、失敗後に`collect`、`stop`の順で呼ぶ（FR-915）。
`start`が成功したときは、環境を残す。

### 3.9 CIワークフロー

```yaml
name: e2e-test
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
env:
  AWS_ACCESS_KEY_ID: test
  AWS_SECRET_ACCESS_KEY: test
  AWS_DEFAULT_REGION: ap-northeast-1
jobs:
  e2e:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<メジャー版>
        with:
          persist-credentials: false
      - name: unit
        run: sh tests/m09-execution-and-ci.sh unit
        timeout-minutes: 3
      - name: test-ci
        run: npm run test:ci
        timeout-minutes: 10
      - name: smoke
        run: sh tests/m09-execution-and-ci.sh smoke
        timeout-minutes: 8
      - name: contract
        run: sh tests/m09-execution-and-ci.sh contract
        timeout-minutes: 5
      - name: collect
        if: always()
        run: sh scripts/e2e.sh collect
      - uses: actions/upload-artifact@<メジャー版>
        if: failure()
        with:
          name: e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}
          path: e2e-logs/
          retention-days: 7
          if-no-files-found: warn
      - name: stop
        if: always()
        run: npm run stop
```

| 判断 | 内容 |
| --- | --- |
| `unit`のステップ | FR-909が「層1〜3はCIの`unit`で実行する」と書くため、`test:ci`の前に足す。FR-914の手順の一覧にも同じステップを書いてある（12章の3） |
| `smoke`と`contract`の位置 | CIでは`unit`、`test:ci`、`smoke`、`contract`の順に実行する（FR-914）。`smoke`の追加項目（不正な`SQUID_UPSTREAM`、`direct`の`squid -k parse`、冪等性、`INT`と`TERM`、ポート衝突）と、`ubuntu/squid:latest`の更新の検知が、CIでも走る（R-04）。`smoke`はAWS CLIを使わない。`contract`はworkflowの`env`のダミー認証情報を使う。`smoke`と`contract`のステップのタイムアウト（8分、5分）は仮値で、T924の実測で見直す。合計がジョブの15分を超えそうな場合は、値の見直しを利用者に確認する（R-16） |
| `smoke`が`e2e-logs/`を消さない | `smoke`は、全項目が成功したときだけ、自分が作った`e2e-logs/`を消す。失敗時は残し、後続の`collect`とアップロードに使う |
| アクションの版 | `actions/checkout`と`actions/upload-artifact`は、公式リポジトリで現行のメジャー版のコミットSHAを確認し、SHAで固定する（末尾のコメントに版を書く）。タグは付け替えられるため、タグでは固定しない（security-reviewのLow対応。13章のR-10は解消済み）。`unit`が40桁のSHAであることを検査する |
| 入力値 | `run:`に`${{ }}`を展開しない。値は全て`env`かスクリプトの中にある（`unit`で検査する） |
| `collect`の再実行 | `test:ci`の内側でも収集するが、タイムアウトで強制終了された場合に備え、workflowでも実行する。3.7の冪等性が前提 |
| 取り消し | GitHubの公式文書（Control the concurrency of workflows and jobs）によれば、同じグループでは、`cancel-in-progress: false`でも、待機中の古い実行が新しい実行に置き換わる（`queue: single`が既定）。このため`main`のpushは、グループにコミットのSHAを含めて、コミットごとに別グループにする。PRのときだけ、ref単位のグループで`cancel-in-progress: true`にする。ランナーは実行ごとに別のVMで、ポートは衝突しない（NFR-910） |

## 4. 前提ゲートと実機確認

clarifyの「plan以降の実機確認」は、表に数えると19行ある（依頼文の18項目より1つ多い）。
19行すべてを、次のとおり分類する。

### 4.1 19項目の分類

| 番号 | 事項（clarifyの表の順） | 分類 | 確認の場所 |
| --- | --- | --- | --- |
| 1 | Colimaでの通し動作 | 実装中に確認 | U8の後、U13 |
| 2 | Linux（GitHub Actions）でのpause方式 | 前提ゲート（Colimaで先行）、CI初回で再確認 | G3、U14 |
| 3 | Squidの送信元ACL（S14のlocal_src） | 前提ゲート（Colimaで先行）、CI初回で再確認 | G3、U14 |
| 4 | MiniStackの登録（ソケットなし） | 前提ゲート | G2 |
| 5 | MiniStackのdescribeの忠実度 | 前提ゲート | G2 |
| 6 | 完成版の生成のシェル実装 | 前提ゲート | G4 |
| 7 | Squidのエントリポイント | 前提ゲート | G5 |
| 8 | `mock`と`direct`の動作確認 | 実装中に確認 | U5、U9 |
| 9 | WireMockのコンテナ名の解決 | 前提ゲート | G1 |
| 10 | ヘルスチェックの変換 | 実装中に確認 | U7 |
| 11 | Squid再起動後の疎通 | 実装中に確認 | U9 |
| 12 | Clientの`HTTP_PROXY`の変更 | 実装中に確認 | U7、U9 |
| 13 | 冪等性、中断 | 実装中に確認 | U8、U9 |
| 14 | 旧基盤との排他 | 実装中に確認 | U9 |
| 15 | アカウントIDの混入検査 | 実装中に確認（G2の観測を入力にする） | U8 |
| 16 | ランナーの前提 | CI初回で確認 | U14 |
| 17 | 初回のCI時間 | CI初回で確認 | U14 |
| 18 | 失敗注入とアーティファクト | CI初回で確認 | U14 |
| 19 | 取り消しの動作 | CI初回で確認 | U14 |

件数は、前提ゲート7（4、5、6、7、9と、2と3）、実装中8（1、8、10から15）、CI初回4（16から19）である。
2と3は、Colimaで先に確かめ、CIの初回でも再確認する。

依頼文の4つの前提ゲートは、次の対応である。

| 依頼文 | ゲート |
| --- | --- |
| a) `--network container:<pause>`のSquidがWireMockを名前で引けるか | G1 |
| b) ソケットなしのMiniStackでregisterとdescribeが動くか | G2 |
| c) Linuxでpause方式とSquidの送信元ACLが動くか | G3 |
| d) 完成版の生成をシェルでどう実装するか | G4 |

G5（Squidのエントリポイント）を足す。結果でDockerfileと派生の方法が変わるためである。

### 4.2 ゲートの進め方

ゲートの実験は、実装単位U1で、使い捨てのコンテナを使って行う。結果は`specs/M09-execution-and-ci/gate-results.md`に、
環境、手順、観測、分岐の決定、後続への影響の節で残す。plan.mdの作成時点では、実験を行わない。

| 規則 | 内容 |
| --- | --- |
| 名前とラベル | コンテナは`swsc-gate-`の接頭辞と`swsc.managed=true`を付ける。`stop`で回収できる |
| 作業場所 | マウントが要る実験は、リポジトリ直下の`.e2e/gate/`で行う。`mktemp -d`はColimaでマウントできない（S14の8.5） |
| ポート | 実験の前に8080と4566が空いていることを確かめる。使用中なら止めて報告する（M08、S14のポート衝突の教訓） |
| Docker環境 | Colimaを使う場合だけ`DOCKER_HOST`を設定する。Dockerの設定ファイルは読まない |
| ダミー認証情報 | G2は`aws`を呼ぶ。NFR-902により、利用者が自分のターミナルで環境変数を設定した状態で実行する。設定されていなければ、未検証として報告する |
| 順序 | G4（Dockerなし）、G5、G1、G3、G2。G1とG3はG5のイメージを使う。G2は独立 |
| 実行主体 | G4、G5、G1、G3はエージェントが実行できる（AWS CLIを使わない）。G2は`aws`を呼ぶため、利用者の端末で実行する |
| 仕上げ | 実験の後に`stop`相当で回収し、`docker ps -a --filter label=swsc.managed=true`が空であることを記録する |

### 4.3 ゲートの内容と分岐

#### G1 コンテナ名の解決（確認項目9）

`swsc-pause`に参加したSquidが、`swsc-net`の名前解決で`swsc-wiremock`を引けるかを確かめる。

| 観測 | 内容 |
| --- | --- |
| 1 | Squidの`cache.log`に、ピアの解決の失敗が出ないこと |
| 2 | ClientからSquid経由で`http://api.example.com`を要求し、WireMockの応答が返ること |
| 3 | WireMockをSquidより後に起動した場合に、ピアが復帰するか（起動順の制約の有無） |
| 4 | ColimaとLinux（CI）の両方で同じ結果か |

| 結果 | 決定 |
| --- | --- |
| 解決できる | コンテナ名を`SQUID_MOCK_HOST`に渡す（FR-910どおり）。起動順は、WireMockの管理APIの応答を待ってから、pause、Squidとする（G1で、Squid先行は502で復帰しないと確認済み） |
| 解決できない | `docker inspect`で`swsc-net`上のWireMockのIPアドレスを読み、`SQUID_MOCK_HOST`に渡す。文字種の規則（英数字、`.`、`-`）はIPアドレスを通す。FR-910とQ-915の「コンテナ名を指定する」を、spec.mdで「名前またはIPアドレス」に直す |
| 解決できるが、起動順が逆だと復帰しない | 起動順を固定する規則（WireMock、pause、Squid）を維持し、文書に残す。`start`の待機でこの順序を保証する |
| ColimaとLinuxで結果が異なる | 両方で通る方式（IPアドレス）に統一する。差の原因は`gate-results.md`に残す |

#### G2 ソケットなしのMiniStack（確認項目4、5）

固定する候補のタグを、ソケットを渡さずに起動し、登録とdescribeを確かめる。

候補のタグは、次の規則で選ぶ。`latest`と、日付だけのタグは候補にしない。

- MiniStackの公式のリリースの一覧で、最新の安定版を確認する
- そのタグがイメージレジストリに存在することを、`docker manifest inspect`などの読み取りで確かめる
- 選んだタグと確認の根拠（リリースの日付、確認したコマンド）を、`gate-results.md`のG2の節に書く

G2は`aws`を呼ぶため、利用者の端末で実行する（T905）。エージェントは、候補のタグの選定と手順の提示までを行い、
利用者の貼り付けを受けたT906を別の実行として開始する。

| 観測 | 内容 |
| --- | --- |
| 1 | ソケットなしで起動し、`list-task-definitions`が応答する。待機に使う応答の確認先 |
| 2 | `register-task-definition`が3.1の完成版を受理する。`cpu`、`memory`、`requiresCompatibilities`の受理 |
| 3 | `describe-task-definition`の項目ごとの忠実度。`healthCheck`、`dependsOn`、`portMappings`、`essential`、`environment`、`networkMode` |
| 4 | 出力とコンテナのログに、12桁の数字とARNが現れるか。`--query`で除外できるか |
| 5 | イメージの取得時間と大きさ（CIの時間の見積もり） |
| 6 | 動作したタグ。dateでなく、固定できるタグを選ぶ |

| 結果 | 決定 |
| --- | --- |
| 登録とdescribeが応答し、全項目が一致して返る | 採用する。タグを固定する（NFR-909） |
| 応答するが、一部の項目が欠落または変形して返る | 比較に正規化の規則を足す。返らない項目は、describeとの比較をやめ、完成版を直接検査する対象として`docs`に列挙する。`networkMode`、`name`、`image`、`environment`のいずれかが返らない場合は、次の行へ進む |
| ソケットなしでは起動しない、またはECS APIが応答しない | MiniStackの公式の設定で回避できるかを調べる。回避できなければ、ここで止めて利用者に判断を求める。選択肢は(A)AWS CLIのクライアント側検証だけにしてFR-904を緩める、(B)読み取り専用でもソケットを渡す（NFR-906を緩める。推奨しない）、(C)別のエミュレータ。計画は自動では選ばない |
| `cpu`、`memory`、`requiresCompatibilities`を拒否する | Fargateの有効な組み合わせに直す。それでも拒否するなら、テンプレートから外し、FR-902を直す |
| 出力またはログにダミーのアカウントIDとARNが出る | 出力は`--query`で除外する。ログは3.7のマスクを入れる |

#### G3 Linuxでのpause方式と送信元ACL（確認項目2、3）

LinuxのVMであるColimaで先に確かめ、CIの初回（U14）でGitHub Actionsのランナーを確かめる。

| 観測 | 内容 |
| --- | --- |
| 1 | `sleep infinity`のpauseに、Squid（`mock`）とClientが参加し、許可ドメインが200で返る |
| 2 | Squidの`access.log`で、Clientの送信元が`127.0.0.1`であり、`local_src`で許可される |
| 3 | 許可外ドメインが403（`TCP_DENIED`）になり、WireMockの受信が0のまま |
| 4 | Squidだけを再起動した後も、1が成功する |
| 5 | `sleep infinity`がalpine:3.20のbusyboxで動く。動かなければ`tail -f /dev/null` |

| 結果 | 決定 |
| --- | --- |
| すべて期待どおり | 採用する |
| 許可ドメインが403になる（`local_src`に一致しない） | `squid.conf`は変更しない（S14の検査が固定している）。`access.log`の送信元アドレスを調べ、`derive-config.sh`で`local_src`の範囲に足す案をspec.mdの変更として利用者に確認する |
| Colimaで通り、CIで失敗する | 失敗時のアーティファクトで原因を特定する（ネットワークの名前空間、ユーザー空間のプロキシ、DNS）。ランナー側の差であれば、ランナーの処理で吸収する |
| `sleep infinity`が動かない | `tail -f /dev/null`にする |

CIでの確認は、ゲート用の一時ブランチやworkflowを作らず、本番のworkflowの初回実行（U14、T924）で行う。
一時ブランチのpushは、このspecの作業中の禁止事項（commit、push、PR作成）に反するためである。
G1またはG3の分岐がCIで覆った場合は、`gate-results.md`、U5、U7（`derive-config.sh`とランナー）へ戻って直し、
`unit`と`smoke`を再実行する手戻りになる（R-03）。

#### G4 完成版の生成の実装（確認項目6）

`python3`と`jq`を、同じ検査の一覧で比べる。

| 観測 | 内容 |
| --- | --- |
| 1 | 値に`/`、`:`、`@`、`\`、`"`、改行を含む場合に、JSONが壊れないか |
| 2 | 未置換のプレースホルダーを検出できるか。許可リスト外のキーを名指しできるか |
| 3 | キーの順序が固定され、同じ入力で同じバイト列になるか |
| 4 | describeとの比較（環境変数の順序、既定値の無視）を実装できるか |
| 5 | macOSの`python3`とランナーの`python3`のバージョン。`jq`の有無（macOSの標準にはない） |

| 結果 | 決定 |
| --- | --- |
| `python3`の標準ライブラリで全項目が書ける | 採用する。`jq`は使わない。前提検査は`python3`と`curl`を見る |
| `python3`が古く、使う構文が動かない | 構文を古い版に合わせる。標準ライブラリ以外には依存しない |
| 利用者の環境に`python3`が無い | 前提検査で止める（FR-912）。`jq`への切り替えは、`jq`が両方の環境にあるときだけ検討する |
| `jq`だけで書ける | 比較と変換の保守性を見て決める。両方の実装は持たない |

POSIX shだけの実装は選ばない。値の文字種を絞れば置換は書けるが、比較と`docker run`への変換が、JSONの構造を読む必要があるため。

#### G5 Squidのエントリポイント（確認項目7）

`ubuntu/squid:latest`の中身を、読み取り専用の確認で調べる。

| 観測 | 内容 |
| --- | --- |
| 1 | `docker image inspect`の`Config.Entrypoint`、`Config.Cmd`、`Config.User` |
| 2 | 元のエントリポイントが何をするか（キャッシュのディレクトリ作成、権限、`squid`の起動の引数） |
| 3 | tmpfsなしで、`/var/log/squid`と`/var/spool/squid`が書き込み可能か |
| 4 | `squid -k parse -f <path>`が起動前に動くか。`cache_peer ... name=wiremock`を受け付けるか |
| 5 | `always_direct allow api_domains`を含む`direct`の設定が`parse`を通るか |

| 結果 | 決定 |
| --- | --- |
| 元のエントリポイントに`exec`で引き渡せる | 3.4の手順4に、そのパスと引数を書く |
| 元のエントリポイントが`/etc/squid/squid.conf`を上書きする、または環境に依存する | 引き渡さず、イメージの`Cmd`と同じ引数で`squid`を直接`exec`する |
| tmpfsなしでは書き込めない | エントリポイントに、ディレクトリの作成と所有者の設定を足す（`derive-config.sh`には足さない） |
| `parse`が起動前に使えない | 検査を`squid -k parse`でなく、起動後の`cache.log`の確認に変える。`smoke`の「directの構文」は、使い捨てコンテナで行う |
| `name=wiremock`を受け付けない | `cache_peer_access`の2行も、ホスト名に合わせて置換する。派生元の行の存在検査に2行を足す |

## 5. 検査の層

### 5.1 `unit`（Dockerと実AWSを使わない）

偽の`docker`と`aws`を`PATH`の先頭に置く。偽は引数を記録し、成功と失敗を切り替えられる。
一時ディレクトリは`mktemp -d`で作り、`trap`で消す。マウントしないので、Colimaの制約に当たらない。
リポジトリのファイルは書き換えない。

| 検査 | 内容 |
| --- | --- |
| 引数 | 不正なモード、`unit`に余計な引数、未知の操作が終了コード2。`package.json`の6つのscriptsが`scripts/e2e.sh`へ委譲する |
| 前提検査 | smoke層（`start`、`test`、`test:ci`）は`docker`、`python3`、`curl`の欠落だけを検査し、`aws`の欠落と認証情報の有無を問わない（`aws`が`PATH`に無く、認証情報が無くても、前提検査が通る）。contract層（`contract`）は`docker`、`aws`、`python3`の欠落、ダミー認証情報の未設定と`test`以外の値（`AWS_PROFILE`の設定を含む）を検査し、`aws`と`docker run`を呼ぶ前に終了コード1にする。`docker-compose`が`PATH`にあっても呼ばれない（呼ばれたら失敗する偽を置く） |
| ポートの確認 | ポートの空き確認が前提検査に含まれず、`start_main`と`contract`の`swsc-`の停止の後にあること（偽の`docker`の呼び出し順で固定）。停止の後に8080か4566が応答する場合に、`swsc-`以外が使用中として止まる。自分の`swsc-wiremock`が残った状態の`start`は、停止の後なので止まらない |
| `aws`を呼ばない経路 | `start`、`test`、`test:ci`、`stop`、`clean`、`collect`が、偽の`aws`（呼ばれたら失敗し、呼び出しを記録する）を呼ばない。認証情報の環境変数が無い状態でも成功する |
| 完成版の生成 | 正常、未置換、未知のプレースホルダー、値の文字種違反、許可リスト外のキー（`volumes`など）の名指し、固定値の項目、Clientの`HTTP_PROXY`と`NO_PROXY`、Clientに`healthCheck`が無いこと、同じ入力で同じバイト列 |
| 本番向け | `--profile production`での拒否。`check-production`の表（`mock`、`Mock`、`MOCK`、前後の空白、欠落、`SQUID_MOCK_*`の残存、合格）。テンプレートに`mock`と`SQUID_MOCK_`が無い |
| 契約の比較 | 一致、項目ごとに1つだけ違う入力（`image`、環境変数の値、`essential`、ポート、`dependsOn`、`healthCheck`、コンテナ数、`networkMode`）で不一致、環境変数の順序差と既定値の追加は一致 |
| Squidの派生 | 6章の規則の全て。派生元の行が1行ずつ存在する。注入になる値（空白、`;`、改行、`$(`）の拒否。`mock`と`direct`の出力。コピーが`squid.conf`と`cmp`で同一 |
| 変換 | `.args`と`.env`の内容。値が引数に出ない。`HEALTHY`の待機。未対応の条件（`COMPLETE`）と`CMD`形式の名指し。ポートの重複 |
| 起動順と受信数 | 偽の`docker`と`curl`の呼び出し記録で、WireMockの起動、管理APIの待機、pause、Squidの順になること（Squidがpauseより後、WireMockの待機より後）。`swsc_wiremock_total`が、`/api/`で始まるURLだけを数え、`/squid-internal-periodic/store_digest`を数えないこと（偽の`curl`が返すJSONで固定） |
| 引数の安全 | 記録した`docker`の引数に、`docker.sock`、`--privileged`、Squidとpauseの`-p`が無い。MiniStackの`-p`が`127.0.0.1:4566:4566`だけ。全ての作成に`swsc-`とラベルが付く |
| stopとclean | ラベルと接頭辞の両方が一致するものだけを削除する。接頭辞だけ、ラベルだけ、他のプロジェクトのものを触らない。削除の順序。二重実行で終了コード0。`clean`の追加の対象 |
| `test:ci`の順序 | 偽で`start_main`失敗、`test`失敗、`collect`失敗を起こし、いずれも`collect`が`stop`より前に呼ばれ、`start_main`失敗でも`collect`に届くこと（`set -e`の下で、`\|\| rc=$?`で受ける形）、終了コードが失敗の元の値を保つこと。`start`操作（単独）は失敗時に`stop`を呼び、`collect`は呼ばない。`INT`が130、`TERM`が143。呼び出し順は、偽の`docker`と入口の関数の呼び出し記録で比べる |
| 収集 | 対象なしで終了コード0。既存の収集物を壊さない。UUIDを拾わない。12桁の数字とARNを、マスクと削除で除く。単独の`collect`が終了コード1を返す。続けて2回実行した`collect`の2回目は、その回に削除対象が無ければ終了コード0を返し、`scrub.txt`を作り直す |
| workflow | 3.9の項目を`grep`で検査する。トリガー、`permissions`、`runs-on`、`timeout-minutes`、ダミーの`env`、`concurrency`のグループ（`pull_request`はref、それ以外はSHA）と`cancel-in-progress`、`if: always()`と`if: failure()`、アーティファクトの名前と保存期間、`secrets.`が無い、`run:`に`${{`が無い、`uses:`が2つの公式アクションだけ、ステップの順序（`unit`、`test-ci`、`smoke`、`contract`、`collect`、アップロード、`stop`）、`docker-compose`が無い。PyYAMLがあるときだけ構文を読む。無いときは`SKIP`と表示し、成功として数えない |
| FR-920 | コマンドとして呼ぶ形（行頭、または`;`、`&&`、`\|`、`$(`の直後）の`docker-compose`と`docker compose`が無い。対象は`scripts/e2e*.sh`、`ecs/`、`.github/workflows/e2e-test.yml`、`package.json`。コメントとメッセージは、旧基盤と書く。`tests/`は対象外（偽の置き場）。`docker compose`（空白）の入力で検査が失敗するケースを固定する |
| 文書 | 必須の節、READMEの記述、識別情報（12桁の数字と`arn:aws`）が無い |

### 5.2 `smoke`（Dockerが必要。AWS CLIと認証情報は不要）

`unit`が落ちたら、Dockerを起動しない。最初に、`swsc-`の残りを`stop`で消す。
`smoke`は`aws`を呼ばず、ダミー認証情報の環境変数を要求しない。エージェントとCIが実行する。
ポート8080が`swsc-`の停止の後も空いていなければ、止めて報告する。M03からM08、S14の検査と同時には動かさない（8080を取り合う）。

| 順 | 検査 |
| --- | --- |
| 1 | `start`が成功する。起動順がWireMock、pause、Squidで、Squidのログに`upstream=mock`が出る |
| 2 | `test`の3項目が通る。受信数は`/api/`で始まるURLだけを数える（`store_digest`を数えない）。Clientの終了コードと出力の契約（`CLIENT_STATUS`、終了コード）がM04からM06と同じである |
| 3 | `SQUID_UPSTREAM`が未設定、`mock`と`direct`以外の使い捨てのSquidが、非ゼロで終了する |
| 4 | `direct`の使い捨てのSquidで、ログに`upstream=direct`が出て、`squid -k parse`が通る。外部通信はしない |
| 5 | `start`の二重実行で成功し、`swsc-`のコンテナが重複しない。`stop`の二重実行で終了コード0。2回目の`start`は、1回目の`swsc-wiremock`が8080を持つ状態でも、停止の後にポートを確認するため止まらない |
| 6 | 8080を、`swsc-`の接頭辞を付けない別のコンテナ（項目7と同じ）が使う状態で、`start`と`test:ci`が非ゼロで終わり、`swsc-`が残らず、`e2e-logs/`が作られる |
| 7 | `swsc-`以外が8080を使用中の状態を、偽ではなく、`swsc-`の接頭辞を付けない名前（例 `m09-smoke-port-holder`）の使い捨てコンテナ（`docker run -p 127.0.0.1:8080:80`）で作り、`start`が「`swsc-`以外が使用中」として止まる。メッセージに旧基盤の可能性が書かれている |
| 8 | 子として本物の入口を起動し、`INT`で130、`TERM`で143になり、`swsc-`と`.e2e/`の一時物が残らない。`INT`の送信はM07の`smoke_child_signal`と同じ方式を再利用する |
| 9 | `stop`の後に`docker ps -a --filter label=swsc.managed=true`と`docker network ls`の`swsc-net`が空である |
| 10 | 収集した`e2e-logs/`に、12桁の数字とARNが無い |
| 11 | 起動の途中で失敗させた`test:ci`（`SQUID_UPSTREAM`に不正な値を渡し、Squidが非ゼロで終了する。本番のスクリプトに分岐を持ち込まない）が非ゼロで終わり、`e2e-logs/containers/swsc-squid.log`が作られ、空でない。`collect`が`stop`より先に走ったことの確認である |

7の使い捨てコンテナは、`swsc-`の接頭辞とラベルを付けない。このため`stop`では回収されない。
検査の`trap`が、コンテナ名を指定して必ず回収する（`docker rm -f m09-smoke-port-holder`）。
回収の対象は、検査が名前を指定して作ったこのコンテナだけで、他のプロジェクトのコンテナには触らない。

`smoke`は、全項目が成功したときだけ、自分が作った`e2e-logs/`を消す。失敗時は残して、後続の`collect`とアップロードに使う。

### 5.3 品質ゲートへの登録

| 項目 | 判断 |
| --- | --- |
| `unit` | 登録する。Dockerを使わず、数秒の見込み。M09の対象ファイル（`scripts/e2e`、`ecs/`、`tests/m09`、workflow、`docs/ローカル実行とCI.md`）の変更時に実行する |
| `smoke` | 登録する。AWS CLIと認証情報を使わないため、エージェントのシェルでもゲートを通せる。M03からM07、S14の所要時間の合計を基準値とし、M09の`smoke`が基準値の半分以下で、ゲート全体が登録前の1.5倍以内であることを実測で確かめる。超える場合は、実測値を示して利用者に確認する（登録を自動では外さない） |
| `contract` | 登録しない。ダミー認証情報の環境変数が要り、エージェントのシェルでは設定できないため（NFR-902）。利用者の端末とCIで実行する（5.4） |
| 実行条件 | `docker-compose`を使う既存のブロックの後ろに、独立したブロックで置く。8080を取り合うため、既存のComposeの検査が終わって回収された後に実行する |
| 残存の検査 | ブロックの最後に、`docker ps -aq --filter label=swsc.managed=true`が空であることを確かめる |
| `squid-config/`、`test-client/`、`wiremock-scenarios/`の変更 | M09の検査も実行する（新基盤が同じファイルを読むため） |
| `sh -n` | 既存の共通ゲートが`tests/*.sh`と`scripts/*.sh`を検査する。`ecs/squid/*.sh`は、M09の`unit`が`sh -n`を検査する。`.py`は`python3 -B -m py_compile`を`unit`で検査する |

`docker-compose`のブロックの`has_match`の条件は変えない。既存の行を書き換えず、新しいブロックを足すだけにする。

### 5.4 `contract`（DockerとダミーAWS認証情報が必要。利用者の端末とCIで実行）

`contract`は、MiniStackの登録とdescribeによる契約検証（FR-904）と、認証情報の規則（FR-905）を実機で確かめる。
`unit`に続けて実行する。エージェントは実行しない。結果は、利用者が自分の端末で実行して貼り付け、
`specs/M09-execution-and-ci/contract-results.md`に記録する（貼り付けに12桁の数字、ARN、認証情報を含めない）。
貼り付けが得られない場合は、エージェントは`contract`を未検証と報告する（成功と断定しない）。
CIでは、ダミー認証情報をworkflowの`env`から受けて実行する。

| 順 | 検査 |
| --- | --- |
| C1 | 認証情報の環境変数が未設定のとき、`contract`が非ゼロで終わり、`swsc-ministack`が作られず、`aws`が呼ばれていない（偽ではなく、実機の`contract`を、環境変数を外した子シェルで起動し、`docker ps -a`で確かめる）。既定の認証情報にフォールバックしていない |
| C2 | 認証情報が`test`以外の値（例 `AWS_ACCESS_KEY_ID=other`）のとき、C1と同じく止まる |
| C3 | ダミー認証情報で`contract`が成功し、登録とdescribeの比較が一致する。終了コード0 |
| C4 | `contract`が成功時に残す`.e2e/ministack-inspect.json`（`docker inspect --format`で取り出した`Mounts`と公開ポートだけ）に、`docker.sock`が無く、公開ポートが`127.0.0.1:4566`だけである |
| C5 | `contract`の終了後、`swsc-`のコンテナが残っていない（`docker ps -aq --filter label=swsc.managed=true`が空） |
| C6 | `.e2e/ministack-describe.json`（`--query`で取り出した項目だけ）に対し、完成版の`image`を1か所変えた写しで`compare`を呼ぶと、不一致で非ゼロになる（実機のdescribeの返り値で、比較が働くことの確認） |

C1とC2は、認証情報の規則を`contract`に残す（FR-905）。この規則は`unit`でも偽の`aws`で固定する（5.1）。

## 6. 後始末と排他

### 6.1 命名と対象の特定

| 対象 | 名前 | ラベル |
| --- | --- | --- |
| コンテナ | `swsc-ministack`、`swsc-wiremock`、`swsc-pause`、`swsc-squid`、`swsc-client-<PID>`、ゲート用の`swsc-gate-*` | `swsc.managed=true`、`swsc.role=<役割>` |
| ネットワーク | `swsc-net` | `swsc.managed=true` |
| イメージ | `swsc-client:e2e`、`swsc-squid:e2e` | ビルド時に`--label swsc.managed=true` |

`stop`と`clean`は、接頭辞`swsc-`とラベル`swsc.managed=true`の両方が一致するものだけを削除する。
`docker rm -f`の対象は、`docker ps -aq --filter label=swsc.managed=true`の結果を、さらに名前の接頭辞で絞ったものである。
他のプロジェクト（`m05`、`pr99-review`、Composeのプロジェクト）のコンテナは、名前もラベルも一致せず、触らない。

`clean`が消すイメージは、`swsc-client:e2e`と`swsc-squid:e2e`だけである。
`alpine:3.20`、`wiremock/wiremock`、`ministackorg/ministack`、`ubuntu/squid`は、他のプロジェクトも使いうるので消さない。

### 6.2 `stop`の順序

| 順 | 処理 |
| --- | --- |
| 1 | Client（`swsc-client-*`）を削除する |
| 2 | Squidを削除する（pauseの名前空間に参加しているため、pauseより先） |
| 3 | pause、WireMock、MiniStackを削除する |
| 4 | ネットワーク`swsc-net`を削除する（ラベルが一致するときだけ） |

それぞれ、存在しなくても失敗にしない。`docker rm -f`は`SIGKILL`で止めるため、pauseの`sleep`が`SIGTERM`を無視しても待たない。
Squidも同じ理由で`docker rm -f`で止める。G5で、元のエントリポイントが`squid`を`exec`せず子として動かすため、
`docker stop`のSIGTERMが`squid`へ転送されないことが分かった。

### 6.3 `trap`

| 場面 | 動作 |
| --- | --- |
| `start`操作が単独で非ゼロで終わる | 入口のラッパーが`stop`を呼ぶ。元の終了コードを保つ。`start_main`自体は`trap`を持たない（`test:ci`の中で、`collect`より先に`stop`が走るのを防ぐ） |
| `start`が成功する | 環境を残す。`trap`を解除する |
| `test` | `INT`と`TERM`のときだけ`stop`を呼ぶ。通常の失敗では環境を残し、調査できるようにする |
| `test:ci` | 通常の失敗は、本体の`start_main \|\| rc=$?`の形で受け、`collect`（失敗を無視）、`stop`の順に呼ぶ。`EXIT`の`trap`は、`INT`と`TERM`で本体に届かなかった場合の最終防衛で、`collect`、`stop`の順に呼ぶ。`INT`は`exit 130`、`TERM`は`exit 143`にし、`EXIT`の`trap`を通す |
| `contract` | `EXIT`で、失敗時は`collect`を呼んでから`swsc-ministack`だけを削除する（他のコンテナには触らない）。`INT`は130、`TERM`は143 |
| 強制終了（`SIGKILL`、workflowのタイムアウト） | 捕捉できない。workflowの`collect`と`stop`のステップで回収する。ローカルでは`npm run stop` |

終了コードの保持は、M07とM08の`cleanup`と同じく、先頭で`rc=$?`を取り、最後に`exit "$rc"`で返す。

### 6.4 S14、M08の教訓の反映

| 教訓 | 反映 |
| --- | --- |
| リポジトリ直下の写し（S14の`.s14-deny.<PID>`）。Colimaでは`mktemp -d`のディレクトリをマウントできない | マウントするものは、リポジトリ直下の`.e2e/`に置く（WireMockのシナリオはリポジトリのパスを直接マウントする）。`mktemp -d`は、マウントしない偽のコマンドの置き場だけに使う。`.e2e/`の中を消すときは、自分が作った名前で、変数が空でないことを確かめてから消す |
| 検査の中断で残骸が残る | 子として本物の入口を起動して`INT`と`TERM`を確かめ、親の`trap`でも`swsc-`を回収する |
| smokeのポート衝突（M08、S14） | `start`は、自分の`swsc-`を停止した後に、8080を確かめ、`swsc-`以外が使用中なら止める（前提検査にはポートを含めない）。`contract`は同様に4566を確かめる。旧基盤の検出は、名前でなく、「`swsc-`以外が使用中」とする（プロジェクト名が任意のため）。他の検査と同時に動かさない。`smoke`の項目7は、`swsc-`の接頭辞を付けない名前のコンテナで塞ぎ、検査の`trap`が名前を指定して回収する |
| 写しの残り | `.e2e/`は`.gitignore`に入れ、`clean`が消す。`unit`は`.e2e/`に書かない |

排他の仕組み（ロックファイル）は持たない。固定名と固定ポートを使うため、同一ホストでの並列実行はできないことを文書に残す（NFR-905）。

## 7. セキュリティ

| 観点 | 対応 |
| --- | --- |
| 認証情報 | ダミー値（`test`）だけを使う。未設定と`test`以外は、呼び出す前に止める。既定の認証情報、`~/.aws`、実AWSには切り替えない。`AWS_PROFILE`を外し、設定ファイルを`/dev/null`にして1回の呼び出しに限定する |
| 認証情報の置き場 | CIはworkflowの`env`に書く。Secretsを使わない。ローカルは利用者が自分のターミナルで設定する。リポジトリに`.aws/config`を作らない。エージェントのシェルでは設定しない |
| CIの権限 | `permissions: contents: read`だけ。`persist-credentials: false`。ランナーは`ubuntu-24.04`。サードパーティのアクションを使わない |
| 入力値 | `run:`に`${{ }}`を展開しない。`unit`で検査する。`github.run_id`と`run_attempt`は、アーティファクトの名前だけに使う |
| ホストの権限 | MiniStackにDockerソケットを渡さない。`--privileged`を使わない。ポートは`127.0.0.1`だけに公開し、Squidとpauseは公開しない |
| 設定の注入 | `SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`の文字種を、Squidの設定へ書く前に検査する。行の置換は完全一致で行う |
| 引数と環境変数 | 環境変数の値は`--env-file`に書き、引数に出さない。ファイルは作成時にパーミッション0600にする |
| ログとアーティファクト | AWS CLIの出力は`--query`で必要な項目だけを取る。ARNを返す項目は取らない。収集の最後に、12桁の数字（英数字と`-`で囲まれないもの）と`arn:aws`を検査する。`env.txt`に環境変数を書かない |
| 公開物 | 文書、workflow、PR本文にアカウントIDとARNを書かない。`<ACCOUNT_ID>`のような記号に置き換える。`unit`と、既存のS14の識別情報の検査（`README.md`と`scripts/quality-gate.sh`が対象）が通ることを確かめる |
| 対象の保護 | `stop`と`clean`は、接頭辞とラベルの両方が一致するものだけを消す（6.1） |

## 8. 実装単位

依存順に並べる。各単位は、対応する検査が通ってから次へ進む。
U1のゲートの結果が出るまで、U3以降の設計の細部（生成の実装手段、WireMockの宛先、MiniStackの比較の規則、エントリポイントの引き渡し）を確定しない。

| 順 | 単位 | 内容 | 要件 | 検査 |
| --- | --- | --- | --- | --- |
| U1 | 前提ゲート | 4章のG4、G5、G1、G3（Colima）、G2を実施し、`gate-results.md`に記録して分岐を決める。必要ならspec.mdを直す（12章） | FR-902、FR-904、FR-906、FR-910、NFR-909、NFR-911 | 記録に全節が揃う。分岐が一つに決まる。作業開始前の`git status --short`との差が、`specs/M09-execution-and-ci/`の文書だけである。`.e2e/`ごと削除されている。ゲート用のコンテナが回収されている |
| U2 | 入口の骨格と前提検査 | `package.json`の6つ、`scripts/e2e.sh`の振り分け、`e2e-lib.sh`の定数と、操作ごとの前提検査（smoke層とcontract層。3.8）と`swsc_aws`、`.gitignore`。`tests/m09`の`unit`の枠 | FR-901、FR-905、FR-912、FR-920、NFR-902、NFR-909 | `unit`の引数、前提検査（操作ごとに必要なものだけ）、FR-920 |
| U3 | テンプレートと生成 | `ecs/task-definition.template.json`、`e2e-taskdef.py render`、許可リスト | FR-902、FR-903、NFR-905、NFR-909、NFR-911 | `unit`の完成版の生成 |
| U4 | 本番向けの検査 | `--profile production`、`check-production`、層1から3 | FR-909 | `unit`の本番向け |
| U5 | Squidのイメージ | `ecs/squid/`の3ファイル、`derive-config.sh`の規則、`unit`の派生の検査 | FR-908、FR-909 | `unit`のSquidの派生。`smoke`の3と4はU9で行う |
| U6 | MiniStackの契約検証 | `e2e-contract.sh`（`contract`操作）、`compare`、登録とdescribe、`--query`、MiniStackの起動と削除 | FR-904、FR-905、FR-918、NFR-901、NFR-902、NFR-906 | `unit`の契約の比較と偽の`aws`の呼び出し。実機の確認はU9の`contract`モード |
| U7 | pause方式のランナー | `docker-args`、`e2e-runner.sh`、起動順、待機、Clientの実行 | FR-902、FR-906、FR-910、FR-911、NFR-903、NFR-906、NFR-907 | `unit`の変換と引数の安全 |
| U8 | 入口の完成 | `start`（`start_main`とラッパー）、`test`、`logs`、`stop`、`clean`、`test:ci`、`collect`、`trap`、識別情報の検査 | FR-901、FR-903、FR-911、FR-912、FR-915、FR-916、FR-918、FR-920、FR-921、NFR-905、NFR-908 | `unit`のstopとclean、`test:ci`の順序（`start_main`失敗時の`collect`と`stop`の呼び出し順）、収集（2回続けた`collect`を含む） |
| U9 | 実通信の検査 | `smoke`の1から11と、`contract`のC1からC6（`tests/m09`のモード）。Colimaでの通し動作。`smoke`はエージェントとCIが、`contract`は利用者の端末とCIが実行する | FR-904、FR-906、FR-907、FR-908、FR-909、FR-910、FR-911、FR-912、FR-922、NFR-902、NFR-903、NFR-906、NFR-907、NFR-908 | `smoke`が通り、`swsc-`が残らない。`contract`は利用者の貼り付けで確認する（エージェントは未検証と報告） |
| U10 | CIワークフロー | `.github/workflows/e2e-test.yml`（`unit`、`test:ci`、`smoke`、`contract`の順。`concurrency`のグループ）と、`unit`のworkflowの静的検査 | FR-913、FR-914、FR-915、FR-916、FR-917、FR-918、NFR-901、NFR-902、NFR-904、NFR-905、NFR-910、NFR-911 | `unit`のworkflow |
| U11 | 文書 | `docs/ローカル実行とCI.md`、`README.md`、`AGENTS.md`の行。`unit`の文書の検査 | FR-919、NFR-905 | `unit`の文書。M07、M08、S14の文書の検査が通る |
| U12 | 品質ゲート | 5.3の実測と判断。`scripts/quality-gate.sh`に`unit`と`smoke`のブロックを足す（`contract`は足さない） | FR-922、NFR-904 | ゲートが通り、残存が無い。実測値を記録する |
| U13 | 最終確認とレビュー | `unit`と`smoke`、既存の検査、`lint:md`、変更ファイルの範囲、10章のレビュー。`contract`の結果の確認（利用者の貼り付け、または未検証の報告） | 7章の完了条件、FR-922 | `unit`と`smoke`がすべて通る。`contract`は記録または未検証の明記がある |
| U14 | CI初回の確認 | PRを作ってworkflowを実行する。確認項目2、3、16から19。所要時間を文書に反映する | FR-917、FR-919、NFR-904 | 4.1のCI初回の項目が記録される |

U14は、PRを作成した後の作業である。PRの作成と、Issueの編集と起票は、利用者の指示を待つ。

### 8.1 要件の対応

FR-901からFR-922とNFR-901からNFR-911の全てを、少なくとも1つの単位に対応させる。

| 要件 | 単位 |
| --- | --- |
| FR-901 | U2、U8 |
| FR-902 | U1、U3、U7 |
| FR-903 | U3、U8 |
| FR-904 | U1、U6、U9 |
| FR-905 | U2、U6 |
| FR-906 | U1、U7、U9 |
| FR-907 | U9 |
| FR-908 | U5、U9 |
| FR-909 | U4、U5、U9 |
| FR-910 | U1、U7、U9 |
| FR-911 | U7、U8、U9 |
| FR-912 | U2、U8、U9 |
| FR-913 | U10 |
| FR-914 | U10 |
| FR-915 | U8、U10 |
| FR-916 | U8、U10 |
| FR-917 | U10、U14 |
| FR-918 | U6、U8、U10 |
| FR-919 | U11、U14 |
| FR-920 | U2、U8、U13 |
| FR-921 | U8 |
| FR-922 | U9、U12、U13 |
| NFR-901 | U6、U10、U13 |
| NFR-902 | U2、U6、U9、U10 |
| NFR-903 | U7、U9、U13 |
| NFR-904 | U10、U12、U14 |
| NFR-905 | U3、U8、U10、U11 |
| NFR-906 | U6、U7、U9 |
| NFR-907 | U7、U9 |
| NFR-908 | U8、U9 |
| NFR-909 | U1、U2、U3 |
| NFR-910 | U10 |
| NFR-911 | U1、U3、U10、U13 |

## 9. 文書

`docs/ローカル実行とCI.md`は、M08の`docs/E2Eテスト.md`と同じ体裁にする（FR-919、Q-910）。

| 節 | 内容 |
| --- | --- |
| 実行方法 | 6つの操作、補助操作、終了コード。Colimaの`DOCKER_HOST` |
| ダミー認証情報の設定 | 利用者が自分のターミナルで設定する手順（`contract`だけが要る）。リポジトリに設定を置かないこと。`start`、`test`、`smoke`は認証情報を要らないこと |
| 検査の層と実行主体 | `unit`、`smoke`、`contract`の違い。エージェントとCIと利用者の端末のどれが実行するか。品質ゲートに登録するのは`unit`と`smoke`であること |
| 構成 | テンプレート、完成版、MiniStack、pause方式、WireMockが別タスクであること |
| 旧基盤との関係 | 8080の排他。移行完了までのCIの検証範囲（M08の4シナリオが載らないこと） |
| CIの見方 | トリガー、ステップ、失敗時のアーティファクトの取得方法 |
| 所要時間の目安 | U14の実測値。`timeout-minutes`の根拠 |
| 再現性 | イメージの固定と`latest`、ポートの空き、並列実行の禁止 |
| 本番向けの検査 | `--profile production`と`check-production`の使い方。デプロイ工程の責任 |
| ゲートの結果 | G1からG5の決定の要約 |

`README.md`は、Quick Startと実行手順の記述を新基盤の`npm run <操作>`に更新する。
旧Compose手順は消さず、「移行完了後に削除」と明記して区別する。
S14の検査は`README.md`のSystem Componentsの行とリンクを、M07とM08の検査は文書へのリンクを`grep`で確かめる。
このため、既存の行は書き換えず、足す変更を中心にし、U11でM07、M08、S14の`unit`と`static`を再実行する。
文書にアカウントIDと認証情報を書かない。MiniStackのダミーのアカウントIDも書かない。

## 10. 検証とレビュー計画

実AWSでの検証は行わない（NFR-901）。AWS APIはMiniStackだけに向ける。

| 段階 | 内容 |
| --- | --- |
| 実装中 | 各単位の検査を通す。`sh -n`と、`python3 -B -m py_compile`を通す |
| 品質ゲート前 | `npm run lint:md`、`git diff --check`、`sh tests/m09-execution-and-ci.sh unit`、`smoke`（`contract`は利用者の端末。下の「未検証の扱い」） |
| 既存検査の確認 | M03からM08、S14の検査入口を個別に実行し、結果が変わらないこと。M02は稼働中のスタックが要るため、ゲートからは実行しない |
| 不変の確認 | `git diff --name-only origin/main...HEAD`が2章の一覧に収まる。2.3のファイルに差分が無い |
| 必須スキルレビュー | コミット前に、`evidence-code-review`と`security-review`を実行する。`sh scripts/review-snapshot.sh m09`でスナップショットを作り、レビュー対象マニフェストをサブエージェントへの依頼文に含める。サブエージェントには、スキルの`SKILL.md`を`read`で読ませる。AGENTS.mdの「サブエージェントの実行条件」に従い、1スキルにつき1サブエージェント、`include_memory=false`、`include_lessons=false`、`include_project=true`、effort `medium`、ファイル変更禁止、Git操作禁止とする。モデルはAGENTS.mdの推奨に従い、利用可能な一覧から解決する。実質的な修正で変更範囲が広がった場合は、2つのレビューをスナップショットから再実行する |
| 任意スキルレビュー | CI/CDとネットワークを変更するため、`aws-well-architected-review-lite`も実行する。tasksのT926に置く。見送る場合は、理由を報告に書く（失敗や未実行を成功とは書かない） |
| 重い検査 | 品質ゲートと`smoke`は、メインエージェントが実行する。サブエージェントに実行させない |
| 品質ゲート | `sh scripts/quality-gate.sh`を、すべての修正後に一度だけ最終実行する。`unit`と`smoke`が登録されており、ダミー認証情報は不要である。Colimaを使う場合だけ`DOCKER_HOST`を設定する |
| 未検証の扱い | `contract`はエージェントが実行しない。利用者の端末での実行結果の貼り付け（`contract-results.md`）が無い間は、`contract`を未検証として報告し、成功と断定しない。CIの初回（U14）で実行結果を確認する |

CIの初回実行で確認する項目は、次のとおりである（U14）。ローカルでは検証できない。

| 項目 | 確認する内容 |
| --- | --- |
| 確認項目2、3 | Linuxのランナーでpause方式と`local_src`が動く。G1またはG3の分岐が覆った場合は、4.3のG3の手戻りの手順に従う |
| 確認項目16 | `ubuntu-24.04`のDocker、AWS CLI v2、`python3`、`curl`、Nodeのバージョン |
| 確認項目17 | `unit`、`test:ci`、`smoke`、`contract`の各ステップの時間と合計。`test:ci`の10分、`smoke`の8分、`contract`の5分のステップと、15分のジョブに収まる。設定値の1/2を超えたら、値と根拠を文書に残す。ジョブの上限を超える場合は、見直しを利用者に確認する |
| 確認項目18 | 一時ブランチで失敗を注入し、アーティファクトが取得でき、中身に識別情報が無い。タイムアウトで強制終了されたときに、workflowの`collect`と`stop`が走る |
| 確認項目19 | 同じPRに2回pushして、1回目が取り消される。`main`へのpushは、短時間に複数回pushしても、互いに取り消されない（グループがコミットごとに別であること） |

失敗注入は、本番のworkflowに分岐を持ち込まず、一時ブランチで一度だけ行う。

## 11. 別Issueの起票内容（案）

起票はしない。利用者に依頼する。優先度はM09の直後とする。

### 11.1 既存検査の新基盤への移行

| 項目 | 内容 |
| --- | --- |
| タイトル案 | 既存のE2E検査（M02〜M08、S14）をECSタスク定義方式へ移行する |
| 背景 | M09で新基盤（タスク定義、MiniStack契約、pause方式、CI）を導入した。既存の検査はdocker-composeに依存し、M08の4シナリオはCIに載らない |
| 依存 | M09 |
| 対象外 | `docker-compose.yml`の削除（11.2） |

| 受け入れ条件 | 内容 |
| --- | --- |
| 1 | M02からM08とS14の各検査が、docker-composeを呼ばずに、`scripts/e2e.sh`とpause方式で動く |
| 2 | 検査の期待値（M08の4シナリオの値を含む）が、移行の前後で変わらない（Clientの出力の契約を含む） |
| 3 | S14の`squid.conf`の固定行の検査が、派生元の`squid-config/squid.conf`に対して維持される。派生後の設定の検査が加わる |
| 4 | M08の4シナリオ（正常、500後に成功、429、タイムアウト）がCIで実行される |
| 5 | 品質ゲートがdocker-composeに依存しない。残存の検査が、ラベル`swsc.managed=true`で行われる |
| 6 | 検査が同じポート（8080、4566）の取り合いを起こさない。検査の入口ごとの排他の方法が文書に残る |
| 7 | CIの実行時間とタイムアウトが見直され、根拠が文書に残る |
| 8 | `README.md`と`docs/`が、移行後の実行手順と一致する。「移行完了後に削除」と明記した旧手順の削除対象が確定する |
| 9 | 識別情報（アカウントID、ARN）が、ログ、アーティファクト、文書に無い |

### 11.2 docker-compose.ymlの削除

| 項目 | 内容 |
| --- | --- |
| タイトル案 | docker-composeの基盤を削除する |
| 背景 | 方針で、docker-composeは廃止し、併用や切り戻しの経路を残さないと決めた。移行が終わるまでの暫定として残している |
| 依存 | 11.1の完了 |

| 受け入れ条件 | 内容 |
| --- | --- |
| 1 | `docker-compose.yml`が削除されている |
| 2 | リポジトリ内の`docker-compose`の呼び出しが0件である（`grep`で確認し、結果を記録する） |
| 3 | `scripts/quality-gate.sh`から、Composeに関する項目（`docker-compose config`、Composeプロジェクトの残存検査）が消えている |
| 4 | `README.md`の旧Compose手順と「移行完了後に削除」の注記が削除されている。`AGENTS.md`の品質ゲート表のCompose行が更新されている |
| 5 | `docs/`と`specs/`の現行の記述のうち、Composeを前提にするものが更新されている（過去のSpec Kit成果物は、履歴として書き換えない） |
| 6 | 新基盤の旧基盤検出（8080の使用中の判定）の要否が判断され、不要なら削除されている |
| 7 | CIが成功し、`main`のブランチ保護の必須チェックの名前が変わらない |

## 12. spec.mdへ戻す事項

ゲートの結果と、plan作成中に見つけた食い違いのうち、spec.mdの文言を揃える必要があるものを挙げる。
番号3から7は、spec.mdとplan.mdに反映済みである。番号1と2は、U1のゲートの結果を受けて、T906で判定した（反映済み）。
実装の前に`analyze`で確かめる。

implementの途中でspec.mdを直した場合（T906の分岐、利用者の判断による緩和など）は、直した箇所の範囲で、
analyzeの確認（FR/NFR/タスクの番号、値、モード名の突き合わせ）をやり直し、`gate-results.md`に記録する。
NFR-906の緩和のように、安全側の要件を緩める場合は、実装に進む前に利用者の明示的な承認を記録する。
承認が無い緩和を基準に、必須レビュー（T919、T920）を行わない。

| 番号 | 箇所 | 内容 | 状態 |
| --- | --- | --- | --- |
| 1 | FR-910、Q-915 | G1の結果が「解決できない」場合、「コンテナ名」を「名前またはIPアドレス」に直す | 対応不要（G1は「解決できる」。コンテナ名のまま）。起動順はFR-906、FR-910に反映済み |
| 2 | FR-904、FR-902、NFR-906 | G2の結果で、緩和または項目の変更が必要になった場合に直す（利用者の判断が要る分岐を含む） | 緩和は不要（G2は全項目が一致）。FR-904、FR-918、NFR-909、1.2に、比較方式、マスク、タグ固定を反映済み |
| 3 | FR-914 | 手順の一覧に、`test:ci`の前の`unit`のステップを足した（3.9）。FR-909の「CIの`unit`」と整合 | 反映済み |
| 4 | FR-912、NFR-911 | 前提検査の一覧に`curl`を足した（WireMockの待機に使う）。`python3`の記述は、G4の既定（標準ライブラリだけ、`jq`は使わない）に一つに決めた。G4で覆る場合だけ、U1の後に直す | 反映済み |
| 5 | FR-918、3.7 | 12桁の数字の検査を、前後が英数字と`-`でないものに限った。UUIDの偶然の一致で、ログが削除されるのを防ぐ。マスクの有無はG2の結果で決める | 反映済み |
| 6 | FR-905 | 認証情報が`test`以外の値のときも、`aws`を呼び出す前に止めるよう、未設定のときの記述に並べた（3.5と同じ規則） | 反映済み |
| 7 | 2章、FR-919 | 変更ファイルに`AGENTS.md`の品質ゲート表の行を足した（2.2と同じ） | 反映済み |
| 8 | 依頼文との差 | 実機確認の項目は19件である。spec.mdとclarifyに、件数の記述は無い | 対応不要 |
| 9 | FR-901、FR-904、FR-905、FR-912、FR-922（新設） | 検査を`unit`、`smoke`、`contract`の3層に分け、MiniStackとAWS CLIを`contract`操作に限った。前提検査は操作ごとに必要なものだけにした（analyzeのA-01、A-02） | 反映済み |
| 10 | FR-913、NFR-910、FR-914、FR-917、FR-918、FR-920 | `main`のpushのグループをコミットごとにした。CIの手順に`smoke`と`contract`を足した。`scrub.txt`の回ごとの作り直し、コマンドとして呼ぶ形の`docker compose`の検査を書いた（A-03、A-06からA-09） | 反映済み |
| 11 | FR-906、FR-907、FR-910、FR-911、FR-904、FR-918、NFR-909、1.2 | T906で、G1の起動順、G3とG1の受信数（`/api/`で始まるURLだけ）、G5の停止（`docker rm -f`）、G2の比較方式、マスク、MiniStackのタグ固定を反映した。FR/NFRの件数は変えていない | 反映済み |

## 13. リスク

| 番号 | リスク | 対策 |
| --- | --- | --- |
| R-01 | ソケットなしのMiniStackが登録とdescribeに応答しない | G2で最初に確かめる。応答しない場合は、計画では選ばず、利用者に判断を求める（4.3） |
| R-02 | pause方式のSquidがWireMockの名前を引けない | G1で確かめる。引けなければIPアドレスで渡す |
| R-03 | ColimaとGitHub ActionsのLinuxで、`local_src`や名前空間の挙動が違う | G3でColimaを先行し、U14のCI初回で再確認する。失敗時のアーティファクトで原因を特定する。CIで分岐が覆った場合は、`gate-results.md`、U5、U7へ戻って直し、`unit`と`smoke`を再実行する手戻りになる |
| R-04 | `ubuntu/squid:latest`の更新で、元のエントリポイントや`squid.conf`の書式が変わる | 派生元の行の存在検査（`unit`）と、起動ログの`upstream=`（`smoke`）で検知する。CIも`smoke`を実行するため、`latest`の更新はCIで検知できる。ダイジェストを`env.txt`に残す |
| R-05 | MiniStackのタグの更新、削除、挙動の変更。固定した`1.5.37`は公開から1日未満の版である | タグを`1.5.37`に固定する。ダイジェストを`env.txt`に残す。問題が出たら`1.5.36`へ戻す。失敗時は固定のタグを見直す |
| R-06 | 新基盤と旧基盤が8080を取り合う | `start`の停止の後のポート確認で、`swsc-`以外の使用を検出して止める。並列実行を禁止する旨を文書に残す |
| R-07 | 識別情報の検査が、UUIDなどを誤って拾い、ログが全削除される | 前後が英数字と`-`でない12桁に限る。UUIDの例を`unit`で固定する |
| R-08 | 識別情報の検査が、MiniStackのログを毎回削除し、調査に使えない | G2の判断として、マスクしてから再検査する（出力にARNとダミーの12桁が含まれる）。ログでの実際の出力はCIの初回で再確認する |
| R-09 | `kill -0 1`のヘルスチェックは、Squidが待ち受ける前に`healthy`になる | `start`の最後に`nc -z 127.0.0.1 3128`で待受を確認する。G5で代替のヘルスチェックを探す |
| R-10 | 公式アクションのメジャー版のタグは可変である。Q-908はメジャー版の指定を決めている | 権限を`contents: read`に絞り、Secretsを使わない。コミットのSHAに固定する案は、利用者の判断として残す |
| R-11 | 検査が`python3`の版の違い（macOSとランナー）で動かない | 標準ライブラリだけを使い、古い版でも動く構文にする。G4で版を確かめる |
| R-12 | `swsc-`の回収が、他のプロジェクトのコンテナを巻き込む | ラベルと接頭辞の両方が一致するものだけを対象にする。`unit`で、片方だけ一致するものを触らないことを固定する |
| R-13 | タイムアウトの強制終了で、`test:ci`の内側の収集と停止が走らない | workflowの`collect`と`stop`のステップで回収する。3.7の冪等性で、二重の収集に耐える |
| R-14 | `contract`がダミー認証情報を要し、エージェントのシェルでは設定できないため、エージェントが実行できない | 検査を3層に分け、`unit`と`smoke`はAWS CLIと認証情報なしで動かす（5章）。`contract`は利用者の端末とCIで実行し、エージェントは未検証と報告する（5.4、T925）。品質ゲートには登録しない |
| R-15 | M08の4シナリオがCIに載らない期間の、リトライとタイムアウトの退行 | 別Issue（11.1）で追跡する。文書にCIの検証範囲を明記する |
| R-16 | 新基盤のイメージのビルドと取得に加え、CIが`test:ci`、`smoke`、`contract`の3つを順に実行するため、時間がジョブの15分を超える | U14で各ステップを実測し、超えたら値と根拠を文書に残す。ジョブの上限を超える場合は、見直しを利用者に確認する。ビルドの文脈を小さくしている（3.4）。Docker Hubのレート制限による取得の失敗も、初回の実測で確認する |
| R-17 | READMEの更新で、S14、M07、M08の文書の検査が壊れる | 既存の行を書き換えず足す。U11で3つの検査を再実行する |

## 14. 制約

- `docker-compose.yml`、`tests/m02`から`m08`、`tests/s14-compose-port-binding.sh`、`squid-config/`、
  `wiremock-scenarios/`、`test-client/`、`Dockerfile.test-client`、`scripts/scenario-lib.sh`を変更しない
- 新基盤の全てのファイルで、docker-composeを呼ばない。切り戻しの処理を持たない
- 本番のスクリプトにテスト専用の分岐を入れない。偽は`PATH`の先頭に置くか、子プロセスとして本物を起動する
- 実AWSと外部APIへ接続しない。AWS APIはMiniStack（`127.0.0.1:4566`）だけに向ける
- MiniStackにDockerソケットを渡さない。run-taskを使わない
- ダミー認証情報（`test`）だけを使い、Secretsを使わない。エージェントのシェルで環境変数を設定しない。エージェントは`contract`を実行せず、未検証と報告する
- マウントするものは、リポジトリ直下の`.e2e/`に置く。`mktemp -d`をマウントしない
- 1台のWireMockとポート8080、4566に対して、並列に実行しない
- 文書、workflow、PR本文に、AWSアカウントID、ARN、認証情報を書かない
- 計画の段階では、Dockerを起動せず、`git commit`、push、PR作成、Issueの編集と起票をしない
