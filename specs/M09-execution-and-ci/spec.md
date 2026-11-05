# M09 ローカル実行とGitHub Actions CIの統合の仕様

## 1. 目的

ローカルとGitHub Actionsで、起動、検証、ログ保存、確実な後処理までを同じ契約で実行できるようにする。
実行基盤は、ECSタスク定義から起動する方式に一本化する。docker-composeは廃止する方向とし、併用や切り戻しの経路は残さない。
既存検査（M02〜M08、S14）の移行と`docker-compose.yml`の削除は別Issueに分ける（Q-912、利用者承認済み）。
移行が終わるまで`docker-compose.yml`が残るのは暫定であり、新基盤の逃げ道ではない（FR-920）。

要件の出典はIssue #9と、利用者が確定した方針（1.1）とする。Issue #9の本文は`gh issue view 9`で取得して確認済みである。
Issue本文には、入口の具体名、CIのトリガーの範囲、ログの保存期間、時間の数値が書かれていない。
これらは`clarify.md`で決定し、本spec.mdに反映した（8章）。
Issue本文は実行基盤にComposeを前提としている。本spec.mdは利用者の決定でこれを置き換えるため、Issueの文言との差分を8章のQ-912で扱う。
Issueの更新と別Issueの起票は、利用者に依頼する。

### 1.1 確定した方針（利用者決定）

| 番号 | 方針 |
| --- | --- |
| 1 | docker-composeは廃止する。ローカルとCIの実行基盤は、ECSタスク定義から起動する方式に一本化し、逃げ道を残さない |
| 2 | タスク定義は静的なテンプレートをリポジトリに置く（ClientとSquidの2コンテナ、awsvpc）。CIのビルドでイメージURIと切り替え値を埋めて完成版を生成する（amazon-ecs-render-task-definitionと同じ考え方） |
| 3 | 完成したタスク定義を、MiniStackに登録してAWS APIの契約を検証し、同じJSONをpauseコンテナ方式で起動して通信を検証する |
| 4 | Squidの上流は、Squidコンテナの環境変数（例 `SQUID_UPSTREAM=mock\|direct`）で起動時に設定を選ぶ。mockはWireMockへcache_peer転送、directは直接接続。本番はdirectとし、本番でmockになっていないことを検査する仕組みを要件に入れる。タスク定義を2種類持つ案は採らない |
| 5 | WireMockは別タスク（独立コンテナ）とする。SquidからWireMockへの宛先は環境変数で渡す。ECSでの名前解決（Service Connect等）はM09の範囲外とする |
| 6 | MiniStackへの接続は、公式の方法どおりダミー認証情報（`AWS_ACCESS_KEY_ID=test`等）と`--endpoint-url`を使う。CIはワークフローの`env`に書き、Secretsは使わない。ローカルは利用者が自分のターミナルで環境変数を設定する。既定の認証情報や実AWSは使わない。リポジトリ内に独自の`.aws/config`プロファイルは作らない |
| 7 | 既存検査（M02〜M08、S14）の移行と`docker-compose.yml`の削除は別Issueに分ける（Q-912でA案を利用者が承認、2026-11-04）。M09は基盤、タスク定義テンプレート、MiniStack契約検証、新しい疎通検証、CIまでとする |

### 1.2 実機検証で確認済みの事実（2026-11-04）

| 確認項目 | 結果 |
| --- | --- |
| MiniStackのイメージ（`ministackorg/ministack`） | 起動し、`127.0.0.1:4566`で待ち受ける |
| タスク定義の登録とrun-task | Dockerソケット（`/var/run/docker.sock`）を渡すと、登録とrun-taskに応答し、実コンテナ（`ministack-ecs-<id>-<name>`）を起動する |
| MiniStackのECSのネットワーク | 各コンテナを`net=bridge`で個別に置き、awsvpcのlocalhost共有を再現しない。ソース`ministack/services/ecs.py`の`_start_task_worker`も、MiniStack自身のネットワークへ各コンテナを個別に参加させるだけで、名前空間の共有処理はない。clientから`127.0.0.1:18080`はConnection refused |
| pauseコンテナ方式 | pause（`alpine:3.20`の`sleep`）を起動し、sidecarとclientを`docker run --network container:<pause>`で参加させると、clientから`127.0.0.1:18080`に到達する（pong、rc=0）。sidecarを再起動しても共有は保たれた。対照の別bridgeではConnection refused |
| Colima | MiniStackにソケットを渡す場合は、ホスト側のソケットパスではなく、VM内の`/var/run/docker.sock`を指定する必要がある（M09ではソケットを渡さないため使わない。Q-914） |

このため、タスク内コンテナ間のlocalhost共有は、MiniStackのrun-taskでは得られず、pauseコンテナ方式で再現する。
MiniStackは、タスク定義の登録とAPI契約の検証に使う。
ソケットを渡さないMiniStackは、`ministackorg/ministack:1.5.37`で、起動、ECS APIの応答、登録、describeの項目ごとの一致を確認した（G2、`gate-results.md`）。
describeの完全出力とMiniStackのログの識別情報は、CIの初回で再確認する。

## 2. 対象範囲

- ローカルの入口: start、test、logs、stop、clean、test:ci（3章、4章、Q-901）と補助操作collect、check-production、contract
- タスク定義の静的テンプレート（ClientとSquidの2コンテナ、awsvpc）と、完成版の生成（FR-902、FR-903）
- MiniStackへの登録とAPI契約の検証（FR-904、FR-905、`contract`）
- pauseコンテナ方式による起動と通信の検証（FR-906、FR-907、Q-913、Q-918）
- Squidの上流切り替え（`SQUID_UPSTREAM`）と、本番でmockになっていないことの検査（FR-908、FR-909、Q-916、Q-917）
- 別タスクのWireMockと、宛先の環境変数による受け渡し（FR-910、Q-915）
- GitHub Actionsのworkflow: PRとpushのトリガー、ジョブ、ステップ、権限（Q-902、Q-908）
- 成功・失敗にかかわらないcleanup（ローカルとCIの両方）
- ログの収集と、失敗時のActionsアーティファクトとしての保存（Q-903、Q-904、Q-905）
- CIの実行時間の目標とタイムアウト（Q-906）
- docker-composeに依存する既存検査（M02〜M08、S14）の移行は別Issueとし、M09では計画の記録に留める（Q-912）
- `README.md`の実行手順の更新と、検証手順の文書化（Q-910）
- Spec Kit成果物と検証手順のリポジトリへの保存（`specs/M09-execution-and-ci/`）

## 3. 機能要件

| ID | 要件 |
| --- | --- |
| FR-901 | ローカルで、start（完成版の生成、イメージのビルド、WireMock、pause、Squidの起動、起動待機）、test、logs、stop、clean、test:ciの操作を、リポジトリルートの一つの入口から実行できる。入口は`package.json`のscripts（`start`、`test`、`logs`、`stop`、`clean`、`test:ci`の6つ）を契約とし、実体を`scripts/e2e.sh <操作>`に置く。補助操作として`collect`（ログ収集）、`check-production <ファイル>`（本番向けの検査）、`contract`（MiniStackへの登録と契約検証。FR-904）を持つ。`start`、`test`、`test:ci`は、AWS CLIとAWS認証情報を要求も参照もしない。 |
| FR-902 | タスク定義の静的テンプレートをリポジトリに置く。コンテナはClientとSquidの2つ、ネットワークモードはawsvpcとする。イメージURIと切り替え値はプレースホルダーとし、実値を直接書かない。Clientの`HTTP_PROXY`と`HTTPS_PROXY`は`http://127.0.0.1:3128`、`NO_PROXY`は`localhost,127.0.0.1`とし、Clientに`healthCheck`は置かない。タスクレベルの項目（`family`、`networkMode`、`requiresCompatibilities`、`cpu`、`memory`）は固定値で書き、`taskRoleArn`と`executionRoleArn`は書かない。 |
| FR-903 | 完成版のタスク定義は、CIのビルド（ローカルでは`start`と`contract`）でテンプレートから生成する。生成は単一の関数に集め、同じ入力から同じバイト列を作る。埋める値は、各コンテナのイメージURIと切り替え値（`SQUID_UPSTREAM`、WireMockの宛先）とする。置換されずに残ったプレースホルダーがあれば、生成を失敗させる。完成版はコミットせず、生成物のディレクトリ`.e2e/`に置く。 |
| FR-904 | `contract`操作が、完成したタスク定義を、MiniStackにAWS CLIの`register-task-definition`で登録する。MiniStackは`contract`が起動し、終了時に削除する。登録後に`describe-task-definition`で、ネットワークモード（awsvpc）、コンテナ名、コンテナ数、イメージURI、環境変数、`essential`、ポート、`dependsOn`、`healthCheck`が、生成した完成版と一致することを検証する。比較は、順序差と空の既定項目（`mountPoints`、`volumesFrom`など）を無視して行う。MiniStackのイメージは、タグ`1.5.37`に固定する（NFR-909）。登録に失敗した場合は、原因を示して非ゼロで終了する。 |
| FR-905 | MiniStackへの接続は、ダミー認証情報（`AWS_ACCESS_KEY_ID=test`、`AWS_SECRET_ACCESS_KEY=test`、`AWS_DEFAULT_REGION=ap-northeast-1`）と`--endpoint-url http://127.0.0.1:4566`だけで行う。環境変数が未設定の場合、または認証情報が`test`以外の値の場合は、`aws`を呼び出す前に、既定の認証情報（`~/.aws`、既定プロファイル）へ切り替えず、原因を示して非ゼロで終了する。実AWSへの接続を試みない。MiniStackへ接続できない場合も、原因を示して非ゼロで終了する。この規則は、MiniStackを使う`contract`にだけ適用する。`contract`は、この検査を、MiniStackの起動より前に行う。 |
| FR-906 | `contract`が登録する完成版と同じ生成手順、同じ入力で作ったJSON（バイト列が一致する。FR-903）を、pauseコンテナ方式で起動する。pause（`alpine:3.20`の`sleep`）を起動し、タスク定義の各コンテナを`docker run --network container:<pause>`で参加させ、タスク内のlocalhost共有を再現する。登録用と起動用で、別のテンプレートや別の生成手順を用意しない。扱う項目は`name`、`image`、`environment`、`essential`、`portMappings`、`dependsOn`、`healthCheck`、`command`、`entryPoint`に限り、それ以外の項目（`volumes`、`mountPoints`、`secrets`、`logConfiguration`など）が完成版にあれば、名指しして失敗させる（Q-913）。Clientはstartでは起動せず、testの検証ごとに1回だけ起動し、環境変数の上書きを受け、終了コードを検証結果に使う（Q-918）。起動順は、WireMockの管理APIの応答を待ってから、pause、Squidの順に固定する（Squidを先に起動すると、WireMockの名前を引けず、後からWireMockを起動しても復帰しない。G1）。 |
| FR-907 | pause方式での起動後、ClientからSquidへlocalhost経由で到達し、`SQUID_UPSTREAM=mock`の構成で、次の3項目を検証する。1) 許可ドメインへのリクエストがWireMockの応答として返る（`CLIENT_STATUS=200`、終了コード0、`/api/`で始まる受信数が1）。2) 許可外ドメイン（`whitelist.txt`に無いダミーのドメイン）がSquidに拒否される（`CLIENT_STATUS=403`、WireMockの受信数は0のまま。受信数はWireMockの管理APIで取得し、URLが`/api/`で始まるリクエストだけを数える。Squid自身が送る`/squid-internal-periodic/store_digest`は数えない）。3) Squidだけを再起動した後も、1)と同じリクエストが成功する。 |
| FR-908 | Squidコンテナは、環境変数`SQUID_UPSTREAM`の値で起動時に設定を選ぶ。`mock`はWireMockへの`cache_peer`転送（閉域）、`direct`は直接接続とする。未設定または`mock`と`direct`以外の値では、起動に失敗する。上流の切り替えのために、タスク定義を2種類持たない。mockの宛先は環境変数`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`で渡す。`SQUID_MOCK_HOST`は英数字、`.`、`-`だけ、`SQUID_MOCK_PORT`は数字だけを許し、外れたら起動に失敗する。設定は既存の`squid-config/squid.conf`を単一の情報源とし、起動時に派生させる。派生した設定は`squid -k parse`で検査し、失敗したら非ゼロで終了する。 |
| FR-909 | 本番でSquidの上流がmockになっていないことを検査する仕組みを持つ。次の4層で検査する。1) テンプレートに`mock`が既定値として書かれていないこと（静的）。2) 完成版の生成に本番向けの指定（`--profile production`）を設け、本番向けでは`SQUID_UPSTREAM=direct`以外の値、およびWireMockの宛先（`SQUID_MOCK_HOST`、`SQUID_MOCK_PORT`）の設定が残っていれば、生成を失敗させる。3) `scripts/e2e.sh check-production <ファイル>`が、任意のタスク定義JSONに同じ検査を行う。4) Squidの起動ログに有効な上流を出し、`smoke`で確認する。層1〜3はCIの`unit`で実行する。`mock`の既定値、大文字小文字の違い、前後の空白、環境変数の欠落の入力で拒否することも固定する。 |
| FR-910 | WireMockは、タスク定義のClientとSquidとは別の独立コンテナ（別タスク）として起動する。固定名のDockerネットワーク`swsc-net`にWireMock（コンテナ名`swsc-wiremock`）とpauseを置き、WireMockの管理API用に`127.0.0.1:8080`だけをホストへ公開する。SquidからWireMockへの宛先は、Squidコンテナの環境変数（FR-908）にWireMockのコンテナ名とポートを指定して渡す。起動順は、WireMockの管理APIの応答を待ってから、pause、Squidとする（FR-906）。ECSでの名前解決（Service Connect等）は扱わない。 |
| FR-911 | stopは、このリポジトリが起動したコンテナ（pause、Client、Squid、WireMock、MiniStack）とネットワーク`swsc-net`を削除する。対象は接頭辞`swsc-`とラベル`swsc.managed=true`で特定する。削除は`docker rm -f`で行う（元のエントリポイントはSIGTERMをSquidへ転送しないため、`docker stop`に頼らない。G5）。cleanは、stopに加え、ビルドしたイメージ、生成した完成版（`.e2e/`）、収集済みのログ（`e2e-logs/`）など、このリポジトリが作った一時物を削除する。いずれも、このリポジトリ以外のDockerリソースを消さない。 |
| FR-912 | 入口は、実行する操作に必要な前提だけを検査し、満たさなければ原因を示して終了コード非ゼロで止まる。`start`、`test`、`test:ci`（smoke層）は、Dockerの有無、`python3`の有無、`curl`の有無（WireMockの待機に使う）、ポート8080の空きを検査し、AWS CLIとダミー認証情報は検査しない。`contract`は、Dockerの有無、AWS CLIの有無、`python3`の有無、ダミー認証情報の環境変数、ポート4566の空きを検査する。ポートの空きは、`start`と`contract`が自分の`swsc-`のコンテナを停止した後に確認する。`swsc-`以外のコンテナまたはプロセスがポートを使用中の場合（旧基盤のdocker-composeを含む）は、使用中として検出して止め、同時には動かさない。旧基盤は名前で検出しない。docker-composeの有無は検査せず、呼び出さない。 |
| FR-913 | GitHub Actionsのworkflowを`.github/workflows/e2e-test.yml`に置く。トリガーは`pull_request`（全ブランチ向け）と`push`（`main`のみ）とし、パスの絞り込みはしない。`concurrency`のグループは、PRのときは`ワークフロー名とref`（新しい実行が古い実行を取り消す）、`main`のpushのときはコミットごとの別グループ（互いに取り消さない）とする。ワークフローの`env`にダミー認証情報を書き、Secretsは使わない。 |
| FR-914 | CIのジョブは、チェックアウト、`unit`（`sh tests/m09-execution-and-ci.sh unit`）、`npm run test:ci`、`smoke`（`sh tests/m09-execution-and-ci.sh smoke`）、`contract`（`sh tests/m09-execution-and-ci.sh contract`）、収集（`if: always()`）、アップロード（`if: failure()`）、後処理（`if: always()`、`npm run stop`）の順で実行する。手順は入口の呼び出しと検査入口の呼び出しだけで構成し、workflowに重複して書かない。 |
| FR-915 | 検証が失敗しても、収集、アップロード、後処理のステップは実行される（ジョブがキャンセルされた場合のアップロードは除く）。検証の結果（成功または失敗）は、ジョブの結果に保たれる。収集は、コンテナの削除より前に行う。`start`が途中で失敗した場合も、`test:ci`では収集を`stop`より先に行う。実行ステップがタイムアウトで強制終了された場合も、workflow側の収集と後処理が走る。 |
| FR-916 | 失敗時に、各コンテナのログ、Squidのアクセスログとキャッシュログ、完成版のタスク定義、MiniStackの検証結果（取り出した項目だけ）、検査の標準出力・標準エラー、環境の情報（Dockerの版、イメージのダイジェスト）を、Actionsのアーティファクトとして保存する。名前は`e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}`、保存期間は`retention-days: 7`とする。環境変数の全体は保存しない。 |
| FR-917 | workflowに、ジョブ全体（`timeout-minutes: 15`）と、`test:ci`のステップ（`timeout-minutes: 10`）、`smoke`と`contract`のステップのタイムアウトを明示する（`smoke`と`contract`の値はplanで仮置きし、初回の実測で見直す）。起動待機の上限は、待機ごとに120秒とする。初回の実測が設定値の1/2を超えたら、値と根拠を文書に残す。 |
| FR-918 | 収集したログ、完成版のタスク定義、アーティファクトに、認証情報、AWSアカウントID、未マスクのARNを含めない。MiniStackの出力は`--query`で必要な項目だけを取り出し、`taskDefinitionArn`など、ARNとアカウントIDを含む項目は取らない。MiniStackの出力とログにはダミーの12桁を含むARNが出るため、`contract`の出力とログは、識別情報の検査の前にマスクしてから保存する（保存しない選択もできる）。収集の最後に、`arn:aws`と、前後が英数字と`-`でない12桁の数字を含む行がないことを検査する（UUIDの一部が偶然12桁の数字になっても、ログを削除しないため）。該当行は、収集物のコピーの上でマスクして再検査し、マスクしても残ったファイルだけを削除して、ファイル名を`scrub.txt`に記録する。`scrub.txt`は`collect`の実行ごとに作り直し、その回の削除または記録があるときだけ、`collect`を非ゼロで終了させる（`test:ci`の内側の`collect`は、終了コードを捨てる）。CIのワークフローは、`permissions: contents: read`だけで動かし、ランナーは`ubuntu-24.04`を明示する。 |
| FR-919 | 検証手順（ローカルの実行方法、環境変数の設定、CIの見方、失敗時のアーティファクトの取得方法、所要時間の目安、移行完了までのCIの検証範囲）を、`docs/ローカル実行とCI.md`に残し、`README.md`の実行手順を実装後の記述に更新し、`AGENTS.md`の変更範囲別の品質ゲート表に新基盤の行を足す。READMEの旧Compose手順は移行完了まで残し、「移行完了後に削除」と明記して区別する。ルートの`plan.md`は変更しない。 |
| FR-920 | 新しい実行基盤は、docker-composeを呼び出さない。呼び出しの検査は、`docker-compose`と`docker compose`（空白区切り）の両方を、コマンドとして呼ぶ形（行頭、または`;`、`&&`、`\|`、`$(`の直後）で探す。検査の対象は、`scripts/e2e*.sh`、`ecs/`、`.github/workflows/e2e-test.yml`、`package.json`とし、コメントとメッセージで旧基盤に触れるときは「旧基盤」と書く。`tests/`は対象外とする（偽の置き場を持つため）。ECSタスク定義の方式が失敗した場合に、docker-composeへ切り替える処理も持たない。移行が終わるまで`docker-compose.yml`と旧基盤の検査（M02〜M08、S14）がリポジトリに残るのは暫定であり、新基盤の逃げ道ではない。旧基盤の削除（`docker-compose.yml`とComposeを呼ぶ処理）は、別Issueの完了条件とする。 |
| FR-921 | `scripts/e2e.sh collect`は、停止の前に、`swsc-squid`、`swsc-wiremock`、`swsc-ministack`のログ（`docker logs`）と、`swsc-squid`の`/var/log/squid/access.log`および`cache.log`（`docker exec`）を`e2e-logs/`へ収集する。対象のコンテナがない場合は、その旨を記録して続け、収集の失敗でtestの終了コードを変えない。何度実行しても同じ構造になる。 |
| FR-922 | 検査は、`tests/m09-execution-and-ci.sh`の3層に分ける。`unit`はDockerとAWSを使わない。`smoke`はDockerを使い、AWS CLIとAWS認証情報を使わない（pause方式の通信検証）。`contract`はDockerとダミー認証情報を使う（MiniStackの登録とdescribeによる契約検証）。エージェントとCIは`unit`と`smoke`を実行できる。`contract`は、利用者の端末とCIで実行し、エージェントは実行しない（エージェントのシェルは認証情報の環境変数を設定できないため。NFR-902）。エージェントは`contract`を未検証と報告する。品質ゲート（`scripts/quality-gate.sh`）には`unit`と`smoke`を登録し、`contract`は登録しない。 |

## 4. 入口と終了コードの契約

入口は、`package.json`のscriptsに`start`、`test`、`logs`、`stop`、`clean`、`test:ci`を置き、実体を`scripts/e2e.sh`に委ねる（Q-901、Q-911）。
文書は`npm run <操作>`の形に統一する。補助操作は`scripts/e2e.sh collect`、`scripts/e2e.sh check-production <ファイル>`、`scripts/e2e.sh contract`で呼ぶ。

| 操作 | 内容 | 終了コード |
| --- | --- | --- |
| start | 完成版を生成し、イメージをビルドして、WireMock、pause、Squidを起動し、ヘルス待ちまで行う。AWS CLIとMiniStackは使わない。起動済みの場合は、既存の`swsc-`を停止して作り直す | 0は成功、非ゼロは前提、生成、ポート、起動、待機の超過のいずれかの失敗 |
| test | startの済んだ環境に対し、Clientを検証ごとに1回起動して、通信検証（FR-907）を実行する。startが前提 | 検査の結果を保つ（0は全件合格、1は失敗、2は引数の誤り） |
| logs | 各コンテナのログを表示する。コンテナ名の指定と追従の有無を選べる | 0は成功、非ゼロは対象なしなど |
| stop | コンテナとネットワークを削除する | 0は成功（既に停止していても0） |
| clean | stopに加え、一時物を削除する | 0は成功（対象がなくても0） |
| test:ci | 前提検査、start、test、収集、stopを順に実行する。startが失敗しても、収集の後にstopを実行する。workflowはこれを呼ぶ | testの結果を保つ（startが失敗したときは、startの終了コード） |
| collect | stopの前にログを`e2e-logs/`へ収集する（FR-921） | 0は成功。対象なしでも0。識別情報の削除または記録があれば1 |
| check-production | 指定したタスク定義JSONが本番向けの条件（FR-909）を満たすか検査する | 0は合格、1は不合格、2は引数の誤り |
| contract | ダミー認証情報を検査し、MiniStackを起動して完成版を登録し、describeで契約を検証し、MiniStackを削除する（FR-904、FR-905） | 0は一致、1は前提、登録、不一致の失敗 |

startとtestは、`INT`と`TERM`を受けたときに`trap`でstopを呼び、元の終了コード（130、143）を保つ。
`start`は、単独で呼ばれて失敗した場合に限り、入口のラッパーがstopする。`test:ci`の中では、`start`の本体にtrapを持たせず、
失敗後に収集してからstopする。

## 5. 非機能要件、検証方法

### 5.1 非機能要件

| ID | 要件 |
| --- | --- |
| NFR-901 | 実AWSや外部APIへ接続しない。AWS APIの呼び出しはMiniStack（`127.0.0.1:4566`）に限る。CIが外部へ出る通信は、チェックアウト、アクションの取得、イメージの取得に限る。AWSアカウントやECRを使うデプロイは扱わない（Issue #9の対象外）。 |
| NFR-902 | 認証情報はダミー値だけを使い、既定の認証情報と実AWSを使わない。ダミー値はリポジトリの文書とworkflowの`env`にだけ書く。Secretsに登録しない。リポジトリ内に独自の`.aws/config`は置かない。ローカルの環境変数は利用者が自分のターミナルで設定し、エージェントのシェルでは設定しない。このため、エージェントが実行する検査（`unit`、`smoke`）はAWS CLIと認証情報を使わず、認証情報を要する`contract`は利用者の端末とCIで実行する（FR-922）。 |
| NFR-903 | 検証の中身（許可ドメインの扱い、WireMockのシナリオ、Clientの出力、M08の4シナリオの期待値）は変えない。変わるのは実行基盤（Composeからタスク定義）であり、移行の対象外の契約が変わる場合は、未確認事項に戻して扱う。Clientの出力の契約（`CLIENT_STATUS`、`CLIENT_BODY`、`CLIENT_DIAG`、終了コード0、28、78）は変わらない。 |
| NFR-904 | CIの実行時間の目標を、ジョブ全体で10分以内の目安とし、`timeout-minutes`の上限は、ジョブ15分、`test:ci`のステップ10分とする（FR-917）。CIは`unit`、`test:ci`、`smoke`、`contract`を順に実行するため、合計が目安を超えうる。初回の実測で見直す。MiniStackのイメージ取得の時間次第でも目安は外れうる。ルートの`plan.md`の「3分未満」は目安とし、超えても失敗にしない。 |
| NFR-905 | 同じコミットに対し、ローカルとCIで同じ完成版のタスク定義の生成手順と同じ検証（`unit`、`smoke`、`contract`の3層）が実行される。CIは3層をすべて実行する。結果が変わる要因（イメージのタグ、`latest`の使用、ポートの空き）を、文書に残す（Q-907）。固定名とポートを使うため、同一ホストでの並列実行はできないことも文書に残す。 |
| NFR-906 | MiniStackには、Dockerソケットを渡さない。渡すと、ホストのDockerを操作できる権限になる。run-taskは使わない（Q-914）。 |
| NFR-907 | ポートの公開は、ループバック（`127.0.0.1`）に限る。公開するのはMiniStackの`127.0.0.1:4566`とWireMockの`127.0.0.1:8080`だけで、Squidとpauseのポートは公開しない。 |
| NFR-908 | 入口の各操作は、複数回実行しても結果が同じになる（既に起動済みのstart、既に停止済みのstopなど）。 |
| NFR-909 | 新規に導入するイメージは固定する。`ministackorg/ministack`はタグ`1.5.37`で固定し、イメージのダイジェストを`env.txt`に残す（G2。公開から1日未満の版のため、問題が出たら`1.5.36`へ戻す）。pause（`alpine:3.20`）と`wiremock/wiremock:3.13.1`も固定する。`ubuntu/squid`は旧基盤の既存検査と同じ挙動を保つため`latest`のまま据え置き、イメージのダイジェストを`env.txt`に残す。AWS CLIはランナー標準のバージョンを使う。`collect`はAWS CLIを呼ばないため、AWS CLIの版は`env.txt`に残さない（FR-905。版は`contract`の実行結果で確認する）。固定しないものは再現性のリスクとして文書に残す（Q-907）。 |
| NFR-910 | 同一PRのCIの並列実行は、新しい実行が古い実行を取り消す（PRのときの`concurrency`のグループは`${{ github.workflow }}-${{ github.ref }}`）。`main`へのpushは、コミットごとに別のグループ（`github.sha`）にして、互いに取り消さない。`cancel-in-progress: false`でも、同じグループでは待機中の古い実行が取り消されるため（GitHubの仕様）、グループを分けて実現する。ランナーは実行ごとに別のVMで、ポートは衝突しない。1台のWireMockへの並列実行はしない（M07のFR-712）。 |
| NFR-911 | 検査は、POSIX shと、AWS CLIと、GitHub Actionsの標準アクション（`actions/checkout`と`actions/upload-artifact`）だけで書く。サードパーティのアクションは使わない。完成版の生成と契約検証の比較には、`python3`（標準ライブラリだけ）に依存する。`jq`は使わない。依存はランナーの標準イメージに含まれるものに限り、前提検査（FR-912）で確認する。 |

### 5.2 検証方法

検査の入口は、`tests/m09-execution-and-ci.sh`に`unit`、`smoke`、`contract`の3モードを持つ形とし、M08と同じく既定を`smoke`、不正な引数を終了コード2とする（FR-922）。
`scripts/quality-gate.sh`には`unit`と`smoke`を登録し、`contract`は登録しない（Q-909）。

| モード | 実行主体 | 内容 |
| --- | --- | --- |
| `unit` | エージェント、CI | Dockerと実AWSを使わない。`docker`と`aws`は偽物を`PATH`の先頭に置く。完成版の生成（プレースホルダーの置換、未置換の検出、本番向けの拒否）、`SQUID_UPSTREAM`の値の検査、`check-production`、入口の前提検査（操作ごとに必要なものだけ）と終了コードの保持、`start`と`test`と`test:ci`がawsを呼ばないこと、stopの冪等性、cleanupの順序、`test:ci`での収集と停止の呼び出し順、収集後のアカウントIDとARNの混入検査、Squid設定の派生元の行が1行ずつ存在することを、スタブで確かめる。workflowのYAMLの構文と、必須項目（トリガー、`env`のダミー値、`timeout-minutes`、`if: always()`相当、アーティファクト、`concurrency`）の存在を静的に確かめる。 |
| `smoke` | エージェント、CI | `unit`に続けて、pause方式での起動と通信検証（FR-907の3項目）を実機で行う。AWS CLIとダミー認証情報は使わない。加えて、不正な`SQUID_UPSTREAM`（未設定、`mock`と`direct`以外）でSquidが非ゼロで終了すること、起動ログに有効な上流が出ること、directの設定を`squid -k parse`が受理すること（外部通信は行わない）、startの二重実行とstopの二重実行の冪等性、`swsc-`以外のコンテナが8080を使用中のときの停止を確かめる。失敗の注入でも、cleanupとログ収集が行われ、終了コードが保たれることを確かめる。 |
| `contract` | 利用者の端末、CI | `unit`に続けて、ダミー認証情報の検査（未設定と`test`以外の値で、`aws`を呼ぶ前に失敗すること）、MiniStackの登録とdescribeによる契約検証（FR-904）、MiniStackにDockerソケットを渡していないこと、終了後に`swsc-`が残らないことを実機で確かめる。エージェントは実行せず、未検証として報告する。 |

GitHub Actions上の実行は、PRを作ってワークフローが通ることで確かめる。
意図的な失敗の注入によるアーティファクトの取得確認は、本番のworkflowにテスト専用の分岐を持ち込まず、一時的なブランチで一度だけ行う。
WireMockのシナリオの切り替えには、`scripts/scenario-lib.sh`のリセット関数を使う。
`unit`、`smoke`、`contract`の詳細な内容は、planで確定する。

## 6. 対象外

- AWSアカウントやECRを使うデプロイ（Issue #9の対象外）
- 実AWS、外部APIへの接続
- ECSでのSquidからWireMockへの名前解決（Service Connect等）と、実ECS上の起動
- 複数タスクにまたがるタスク定義の管理（WireMockの別タスクの実ECS上の定義）
- MiniStackのrun-taskによる実コンテナの起動を、通信の検証に使うこと（localhostが共有されないため。Q-914）
- 既存検査（M02〜M08、S14）のpause方式への移行と、`docker-compose.yml`およびComposeを呼ぶ処理の削除（別Issue。Q-912）
- M08の4シナリオ（正常、500後に成功、429、タイムアウト）のCIへの搭載（上の移行と同じ別Issue）
- `whitelist.txt`の本番ドメインへの差し替え（現在はダミーのドメイン。Q-917）
- 本番の実環境でSquidの上流がmockになっていないことの確認（デプロイ工程の責任。Q-916）
- セットアップとトラブルシューティングの詳細文書（M10）
- ローカルとCIの最終受入検証（M11）
- 複数OS、複数アーキテクチャのマトリクス実行
- スケジュール実行、リリース、イメージの公開
- 実行結果のダッシュボード化、外部サービスへの通知

## 7. 完了条件

Issue #9の完了条件6項目を、次のとおり引き継ぐ。

- [ ] ローカルで一つの入口から起動、テスト、停止を実行できる
- [ ] GitHub Actionsのクリーン環境で同じ検証が通る
- [ ] テスト失敗時もcleanupが実行される
- [ ] 失敗時のログがActionsアーティファクトとして取得できる
- [ ] CIの実行時間とタイムアウトがワークフローに明示されている
- [ ] Spec Kit成果物と検証手順がリポジトリに残っている

本spec.mdは、上の項目に加えて、次を完了の確認に含める。

- [ ] 静的テンプレートから完成版が生成され、同じ生成手順と入力で作った同一バイト列のJSONが、MiniStackへの登録（`contract`）とpause方式の起動（`start`）の両方に使われる
- [ ] pause方式での通信検証（FR-907の3項目、`smoke`）が通る。MiniStackの契約検証（FR-904、`contract`）が、利用者の端末またはCIで通る
- [ ] `SQUID_UPSTREAM`が`mock`と`direct`で期待どおり切り替わり、不正な値で起動に失敗する
- [ ] 本番向けの完成版と`check-production`で、`direct`以外の指定が失敗になる
- [ ] AWS APIの呼び出しが、ダミー値と`--endpoint-url`だけで動き、既定の認証情報を参照しない。`start`、`test`、`test:ci`、`smoke`はAWS CLIを呼ばない
- [ ] MiniStackにDockerソケットを渡していない（NFR-906）
- [ ] 新しい実行基盤がdocker-composeを呼ばない（FR-920）
- [ ] 既存検査（M02〜M08、S14）の移行と`docker-compose.yml`の削除が、別Issueとして起票され、完了条件として追跡されている（Q-912）
- [ ] M08の4シナリオはCIに載らない。移行完了までのCIの検証範囲を文書に明記し、別Issueで追跡する
- [ ] 収集したログと完成版に、認証情報やAWSアカウントIDが含まれていない
- [ ] `README.md`の実行手順が、実装後の状態と一致している
- [ ] `unit`と`smoke`が品質ゲートに登録されている。`contract`はエージェントが実行せず、結果が利用者の貼り付けまたはCIで確認されている（FR-922）

## 8. 未確認事項

すべて解消済みである。決定の詳細と根拠は`clarify.md`に記録する。
実機でしか確認できない事項は、`clarify.md`の「plan以降の実機確認」に一覧し、planで扱う。

| ID | 状態 | 決定の内容 |
| --- | --- | --- |
| Q-901 | 解消（clarify） | ローカルの入口の形と名前。`package.json`のscriptsに6つを置き、実体を`scripts/e2e.sh <操作>`に委ねる。npmを正とする（Q-911）。補助操作として`collect`、`check-production`、`contract`を持つ |
| Q-902 | 解消（clarify） | CIのトリガー。`pull_request`（全ブランチ向け）と`push`（`main`のみ）。パスの絞り込みなし。ファイル名は`.github/workflows/e2e-test.yml`。`concurrency`は、PRのときだけ古い実行を取り消す。`main`のpushはコミットごとの別グループで、互いに取り消さない |
| Q-903 | 解消（clarify） | ログの収集方法。新基盤の入口の`collect`が、停止の前に`docker logs`と`docker exec`で収集する。M08のsmokeには足さない |
| Q-904 | 解消（clarify） | アーティファクトの名前、保存期間、保存条件。失敗時のみ保存し、名前は`e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}`、`retention-days: 7` |
| Q-905 | 解消（clarify） | アーティファクトに含める内容。各コンテナのログ、Squidのログ、完成版のタスク定義、MiniStackの検証結果（ARNとアカウントIDを含まない項目だけ）、検査の出力、環境の情報。環境変数の全体は含めない |
| Q-906 | 解消（clarify） | 時間の目標とタイムアウト。ジョブ全体で`timeout-minutes: 15`、テストステップで10、起動待機の上限は120秒。「3分未満」は目安 |
| Q-907 | 解消（clarify） | 新規に導入するイメージ（MiniStack、pause、WireMock）は固定し、`ubuntu/squid:latest`は据え置いてダイジェストを記録する。AWS CLIはランナー標準 |
| Q-908 | 解消（clarify） | workflowの権限とアクションの固定。`permissions: contents: read`だけ。公式アクションをメジャーバージョンで指定。ランナーは`ubuntu-24.04`を明示 |
| Q-909 | 解消（clarify） | 検査の入口と通信検証の項目。`tests/m09-execution-and-ci.sh`に`unit`、`smoke`、`contract`を置き、`unit`と`smoke`を品質ゲートに登録する。通信検証は3項目（FR-907） |
| Q-910 | 解消（clarify） | 文書の置き場所。`docs/ローカル実行とCI.md`を新設し、`README.md`の実行手順を更新する。READMEの旧Compose手順は移行完了まで残す |
| Q-911 | 解消（clarify） | npmを正とし、`npm run <操作>`を契約とする。`pnpm`は検証対象にしない |
| Q-912 | 解消（利用者承認: A案） | 既存検査の移行の範囲。M09は基盤、タスク定義テンプレート、MiniStack契約検証、新しい疎通検証、CIまで。既存検査（M02〜M08、S14）の移行は別Issueに分ける。`docker-compose.yml`は別Issueで削除するまで一時的に残る。この残存は逃げ道ではなく移行中の暫定であり、新基盤はdocker-composeを呼ばない（FR-920）。利用者が2026-11-04に承認した |
| Q-913 | 解消（clarify） | pause方式で扱う項目は`name`、`image`、`environment`、`essential`、`portMappings`、`dependsOn`、`healthCheck`、`command`、`entryPoint`。それ以外が完成版にあれば失敗させる（fail closed） |
| Q-914 | 解消（clarify） | MiniStackは登録とdescribeによる契約検証だけに使う。run-taskは使わず、Dockerソケットは渡さない |
| Q-915 | 解消（clarify） | 固定名のネットワーク`swsc-net`にWireMockとpauseを置き、Squidへ`SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`でコンテナ名とポートを渡す |
| Q-916 | 解消（clarify） | 本番でmockでないことの検査。生成時の`--profile production`による拒否に加え、任意のJSONを検査する`check-production`を持つ。検査は4層（FR-909） |
| Q-917 | 解消（clarify） | Squidのイメージ。`ubuntu/squid`を元に、既存の`squid.conf`を単一の情報源として起動時に設定を派生させる。ボリュームに頼らない |
| Q-918 | 解消（clarify） | Clientは1回の要求で終了する。タスク定義上は`essential`をfalseとし、startでは起動せず、testの検証ごとに1回起動して終了コードを検証結果に使う |

### 利用者確認の記録

| 判断 | 結果 |
| --- | --- |
| 既存検査（M02〜M08、S14）の移行の範囲と段階（Q-912） | A案を利用者が承認した（2026-11-04）。M09は基盤、タスク定義テンプレート、MiniStack契約検証、新しい疎通検証、CIまで。移行は別Issueに分け、優先度はM09の直後に置く |

Issue #9の本文の「Compose起動待機とテスト実行」は、新方針で置き換わる。Issueの更新と別Issueの起票は、利用者に依頼する。
