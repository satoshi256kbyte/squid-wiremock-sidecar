# M09 clarify

## 前提

spec.mdの新方針（1.1）と実機検証の事実（1.2）を入力に、リポジトリの読み取りで確認できた事実と、
実機でしか確認できない事項を分けて扱う。
行番号は、ブランチ`feature/m09-execution-and-ci`の時点のものである。
Dockerは起動していない。静的な読み取りだけで確認した。
旧clarify.mdはdocker-compose前提だったため、全面的に書き直した。

| 区分 | 内容 |
| --- | --- |
| 確認済み | `docker-compose.yml`のClientは`HTTP_PROXY`を`http://squid:3128`、`NO_PROXY`を`localhost,127.0.0.1,squid,wiremock`にする（7〜9行）。localhost共有の新基盤では宛先が`127.0.0.1:3128`に変わる |
| 確認済み | ClientはComposeでは`depends_on`で`squid`と`wiremock`のhealthyを待つ（11〜16行）。1回のリクエストで`exit 0`するため常駐せず、ヘルスチェック`kill -0 1`（18〜23行）は意味を持たない |
| 確認済み | Squidのイメージは`ubuntu/squid:latest`（26行）。設定は`squid.conf`と`whitelist.txt`を読み取り専用でマウントする（29〜30行）。`/var/log/squid`と`/var/spool/squid`は`tmpfs`（32〜34行） |
| 確認済み | WireMockは`wiremock/wiremock:3.13.1`（45行）。ホストへは`127.0.0.1:8080`だけ公開し（47行）、`wiremock-scenarios`をマウントする |
| 確認済み | `squid.conf`の10行目は`cache_peer wiremock parent 8080 0 no-query`で、宛先のホスト名とポートが固定値。13行目の`never_direct allow api_domains`が直接接続を禁じる。環境変数の置換機構はSquidに無い |
| 確認済み | `squid.conf`の8行目`acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`が送信元を制限する。15行目の`http_access allow local_src api_domains`と16行目の`http_access deny all`の2行だけがhttp_accessである |
| 確認済み | `tests/s14-compose-port-binding.sh`は`squid-config/squid.conf`の行を`grep -Fx`で固定検査する（429〜444行）。このためM09で`squid.conf`を直接書き換えると、既存の検査が壊れる |
| 確認済み | `squid.conf`の23〜24行で、アクセスログとキャッシュログはファイル（`/var/log/squid/access.log`、`cache.log`）に出る。標準出力には出ない |
| 確認済み | 許可ドメインは`whitelist.txt`の`api.example.com`と`api-staging.example.com`の2つ。ダミーのドメインで、本番のドメインではない |
| 確認済み | `Dockerfile.test-client`は`alpine:3.20`に`curl`を入れたイメージ。`test-client/entrypoint.sh`は`HTTP_PROXY`未設定なら終了コード78で止まる |
| 確認済み | `scripts/scenario-lib.sh`の`WIREMOCK_URL`の既定は`http://127.0.0.1:8080`（200行、214行）。WireMockをホストの8080へ公開すれば、リセット関数はそのまま使える |
| 確認済み | `docker-compose`の呼び出し数は、`tests/m02`が1、`m03`が3、`m04`が7、`m05`が8、`m06`が13、`m07`が13、`m08`が20、`s14`が20、`scripts/quality-gate.sh`が5。M02〜M08とS14とゲートの全てがComposeに依存する |
| 確認済み | `scripts/quality-gate.sh`の74行の検査リストに`tests/m09-*.sh`は無い。68行の条件に`.github/`、`package.json`、`scripts/e2e.sh`は含まれない。`.github/workflows/`は存在しない |
| 確認済み | `package.json`のscriptsは`lint:md`だけ。`engines`は`node >=22`、ロックファイルは`package-lock.json`（npm）。実行時の依存は無い |
| 確認済み | `docs/requirements.md`は17行と33行で「ECSのタスク定義のサイドカーパターンと、awsvpcによるlocalhost共有」を目的に置く。新方針（タスク定義の一本化）はこの要件と整合する |
| 実機確認が要る | 本clarifyのうち、挙動に依存する決定（Squidのエントリポイント、DNS、MiniStackの登録内容、Linuxでの動作）。「plan以降の実機確認」に一覧する |

## 決定の一覧

| ID | 決定 | 利用者確認 |
| --- | --- | --- |
| Q-901 | 維持。起動の中身は論点を整理してplanへ渡す | 不要 |
| Q-902 | 維持。理由の記述だけ改める | 不要 |
| Q-903 | 新基盤の入口で、停止の前にコンテナログとSquidの`access.log`を収集する。M08のsmokeには足さない | 不要（通知のみ） |
| Q-904 | 維持。収集とアップロードの順序を補う | 不要 |
| Q-905 | 推奨案を採る。MiniStackの出力はアカウントIDとARNを含めない形で保存する | 不要 |
| Q-906 | 維持。testステップのタイムアウトだけ5分から10分に改める | 不要 |
| Q-907 | 推奨案を変更。新規に導入するイメージは固定し、Squidの基底だけ`latest`のまま記録する | 不要 |
| Q-908 | 維持。ランナーの根拠を改める | 不要 |
| Q-909 | 推奨案を採る。検査項目を補う | 不要 |
| Q-910 | 維持。READMEの旧Compose手順は移行完了まで残す | 不要 |
| Q-911 | 維持 | 不要 |
| Q-912 | 推奨案を採る。M09は基盤、テンプレート、MiniStack契約、新しい疎通検証、CIまで。既存検査の移行は別Issueに分ける | 承認済み（A案、2026-11-04） |
| Q-913 | 推奨案を採る。扱う項目と、扱わない項目の挙動を確定する | 不要 |
| Q-914 | 推奨案を採る。Dockerソケットは渡さない。run-taskは使わない | 不要（通知のみ） |
| Q-915 | 推奨案を採る。固定名のネットワークとコンテナ名で、環境変数にコンテナ名を渡す | 不要 |
| Q-916 | 推奨案を採る。生成時の拒否に加え、任意のタスク定義ファイルを検査する操作を足す | 不要 |
| Q-917 | 推奨案を変更。設定は既存の`squid.conf`を単一の情報源にし、起動時に派生させる | 不要 |
| Q-918 | 推奨案を採る。Clientは起動時には作らず、test実行ごとに1回だけ起動する | 不要 |

## 論点と決定

### Q-901 ローカルの入口の形と名前

| 項目 | 内容 |
| --- | --- |
| 選択肢A | `package.json`のscriptsを契約とし、実体を`scripts/e2e.sh <操作>`の1本に置く |
| 選択肢B | 操作ごとに別のシェルスクリプトを置く |
| 決定 | 選択肢A（旧clarifyの決定を維持）。scriptsは`start`、`test`、`logs`、`stop`、`clean`、`test:ci`の6つ |
| 新方針との整合 | 矛盾しない。入口がComposeに触れない点だけを加える。操作の意味は変わる（下の表） |

旧clarifyでは`test`がM08のsmokeを呼ぶ自己完結の操作だった。新方針では、`test`は起動済みの環境に対する検証になる。

| 操作 | 旧clarify | 新方針 |
| --- | --- | --- |
| start | Composeで`squid`と`wiremock`を起動 | 完成版の生成、MiniStackへの登録、契約検証、WireMockとpauseとSquidの起動、ヘルス待機 |
| test | M08のsmokeを呼ぶ。`start`中は失敗 | 起動済みの環境に対し、Clientを1回ずつ起動して疎通を検証する。`start`が前提 |
| test:ci | 前提検査、test、収集、stop | 前提検査、start、test、収集、stop。testが失敗しても収集とstopを行い、終了コードはtestの結果を保つ |

起動の中身は、planで次の論点を決める。

| 論点 | 整理 | 推奨 |
| --- | --- | --- |
| 実行の識別 | stopとcleanが対象を特定する手段が要る | 固定のコンテナ名の接頭辞`swsc-`と、ラベル`swsc.managed=true`を全てに付ける。他のDockerリソースは消さない（FR-911） |
| 起動済みのstart | NFR-908の冪等性 | 既存の`swsc-`を一度停止して作り直す。「起動済みなら何もしない」は、完成版の内容が古いまま残るため採らない |
| 順序 | 依存関係の表現 | ネットワーク作成、MiniStack、WireMock、pause、Squid（ヘルス待機）。Clientはtestで起動する |
| 待機 | 起動待ちの方法 | `docker inspect`の`State.Health.Status`を1秒間隔で読む。上限は120秒 |
| 完成版の置き場所 | 生成物のディレクトリ | `.e2e/`（`.gitignore`に追加し、cleanで削除）。コミットしない（FR-903） |
| ポート公開 | NFR-907 | Squidのポートは公開しない。WireMockの管理APIの`127.0.0.1:8080`と、MiniStackの`127.0.0.1:4566`だけ公開する（Q-915） |
| 中断 | `INT`と`TERM`の扱い | M07、M08と同じ`trap`で`stop`を呼び、元の終了コード（130、143）を保つ |
| AWS CLIの環境 | FR-905 | ダミー認証情報が未設定なら止まる。`start`は`--endpoint-url`を毎回明示する |

影響するFR/NFR: FR-901、FR-905、FR-911、FR-912、NFR-908。

### Q-902 CIのトリガーの範囲

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。`pull_request`（全ブランチ向け）と`push`（`main`のみ）。パスの絞り込みなし。ファイルは`.github/workflows/e2e-test.yml` |
| 新方針との整合 | 矛盾しない。トリガーはComposeに依存しない |
| 理由 | 絞ると、`package.json`、`.github/`、`scripts/`、タスク定義のテンプレートの変更でE2Eが走らず、必須チェックが未実行のまま残る |

`concurrency`は、グループを`${{ github.workflow }}-${{ github.ref }}`とし、PRのときだけ`cancel-in-progress: true`にする。
`main`へのpushは取り消さない。マージ後の結果が残らなくなるため。

並列実行の注意は変わらない。1台のWireMockを共有する検査を並列に走らせない（M07のFR-712）。
新基盤は固定名と固定ポートを使うため、同一ホストでの並列実行はできない。文書に残す。

### Q-903 ログの収集方法

| 項目 | 内容 |
| --- | --- |
| 選択肢A | 入口の`collect`操作が、停止の前に`docker logs`と`docker exec`で収集する |
| 選択肢B | Squidのログを標準出力へ切り替える |
| 決定 | 選択肢A |
| 理由 | 新基盤は起動と停止を自前で持つため、停止の前に収集する順序を入口に固定できる。Squidの`access.log`はファイルに出る設定で（`squid.conf`の23行）、M05が同じ`access.log`を読む。ログ出力を標準出力へ変えると、既存検査の契約が変わる |

M08のsmokeにログ収集を足す必要は無い（論点cの結論）。理由は次のとおり。

- 旧clarifyで収集をM08に足す案が出たのは、M08のsmokeが自分で`down`まで行い、呼び出し側が停止の前に収集できなかったため。
- 新基盤のCIはM08のsmokeを呼ばない。収集は新基盤の入口が持つ。
- M08の自前の起動は、既存の検査（旧基盤）の中で閉じる。M09は触らない。

収集の細則は次のとおり。

| 項目 | 決定 |
| --- | --- |
| 操作名 | `scripts/e2e.sh collect`。`test:ci`の中で停止の前に呼ぶ。単体でも呼べる |
| 対象 | `swsc-squid`、`swsc-wiremock`、`swsc-ministack`のログ（`docker logs`）。`swsc-squid`の`/var/log/squid/access.log`と`cache.log`（`docker exec cat`） |
| 対象の欠如 | コンテナが無い、または既に消えている場合は、その旨を記録して続ける。収集の失敗でtestの終了コードを変えない |
| 出力先 | `e2e-logs/`（`.gitignore`に追加。cleanが削除する） |
| 冪等 | 何度呼んでも上書きで同じ構造になる |

影響するFR/NFR: FR-911、FR-915、FR-916。

### Q-904 アーティファクトの名前、保存期間、保存条件

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。失敗時のみ保存し、名前は`e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}`、`retention-days: 7` |
| 新方針との整合 | 矛盾しない。ただしタイムアウトで`test:ci`が強制終了された場合に、入口の内部の収集とstopが走らない穴がある |

穴を塞ぐため、workflowの順序を次のとおり確定する（FR-914、FR-915に反映）。

| 順 | ステップ | 条件 | 内容 |
| --- | --- | --- | --- |
| 1 | チェックアウト | 常に | `actions/checkout` |
| 2 | 実行 | 常に | `npm run test:ci`（`timeout-minutes: 10`） |
| 3 | 収集 | `if: always()` | `scripts/e2e.sh collect`。コンテナが残っていなければ何もしない |
| 4 | アップロード | `if: failure()` | `actions/upload-artifact`。`if-no-files-found: warn`、`retention-days: 7` |
| 5 | 後処理 | `if: always()` | `npm run stop`。冪等 |

ジョブがキャンセルされた場合は保存しない（`failure()`は`cancelled()`を含まない）。ここは変えない。

### Q-905 アーティファクトに含める内容

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。以下の内容を保存し、環境変数の全体は保存しない |
| 追加の決定 | MiniStackの出力は、`aws ... --query`で必要な項目だけを取り出して保存する。ARNとアカウントIDを含む項目（`taskDefinitionArn`など）は取らない |

| ファイル | 内容 |
| --- | --- |
| `e2e-logs/containers/<名前>.log` | 各コンテナの`docker logs` |
| `e2e-logs/squid/access.log`、`cache.log` | Squidのログ |
| `e2e-logs/taskdef.json` | 完成版のタスク定義（ダミー値だけ。FR-918） |
| `e2e-logs/ministack-contract.json` | `describe-task-definition`の取り出し結果（名前、ネットワークモード、コンテナ、環境変数、`essential`） |
| `e2e-logs/test.out`、`test.err` | `test`の標準出力と標準エラー |
| `e2e-logs/env.txt` | Dockerのバージョン、使ったイメージのダイジェスト。環境変数は含めない。AWS CLIのバージョンは書かない（`collect`はAWS CLIを呼ばないため。FR-905） |

MiniStackの既定のアカウントIDは、ダミー値でも12桁の数字の形を持つ可能性がある。
FR-918は「AWSアカウントID」と書くため、形が同じものは含めない方針とする。
収集の最後に、`[0-9]{12}`と`arn:aws`を含む行が無いことを検査し、あれば該当ファイルを削除して失敗を記録する（`unit`で固定）。

影響するFR/NFR: FR-916、FR-918。

### Q-906 時間の目標とタイムアウト

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。ジョブ全体は`timeout-minutes: 15`。起動待機の上限は120秒。「3分未満」は目安で、失敗条件にしない |
| 変更 | testステップの`timeout-minutes`を5から10に改める |
| 理由 | 旧clarifyの5分は、M08のsmoke単体の想定だった。新方針ではこのステップ（`test:ci`）がイメージの取得とSquidのビルド、MiniStackの起動まで含む。実測前なので、仮の値を広めに置く |

見直しの条件は変えない。初回の実測が設定値の1/2を超えたら、値と根拠を文書に残す。
NFR-904の「ジョブ全体で10分以内の目安」は、MiniStackのイメージの取得時間次第で外れる。実測で判断する（実機確認の表）。

影響するFR/NFR: FR-917、NFR-904。

### Q-907 イメージのバージョンの固定

| 項目 | 内容 |
| --- | --- |
| 選択肢A | 固定しない。リスクとして文書に残す（spec.mdの推奨案） |
| 選択肢B | 新たに導入するものだけ固定し、既存の`latest`は据え置いて記録する |
| 決定 | 選択肢B（推奨案から変更） |
| 理由 | MiniStackとpauseは新方針で初めて導入するため、固定しても既存の契約を変えない。固定しないと、MiniStackの更新でCIが突然落ちる。一方`ubuntu/squid:latest`は、旧基盤の既存検査と同じ挙動を保つため据え置く |

| イメージ・ツール | 方針 |
| --- | --- |
| `ministackorg/ministack` | タグを固定する。具体的なタグはplanで、実機検証に使った版（spec.mdの1.2）に合わせる |
| `alpine`（pause） | `alpine:3.20`を維持する（Clientと同じ） |
| `wiremock/wiremock` | `3.13.1`（既存の固定） |
| `ubuntu/squid` | `latest`のまま。新しいSquidのイメージは、この基底を`FROM`に使う。ダイジェストを`env.txt`に残す |
| AWS CLI | ランナー標準のバージョンを使う。`env.txt`にはバージョンを残さない（`collect`はAWS CLIを呼ばないため。版は`contract`の実行結果で確認する） |

影響するFR/NFR: NFR-905、NFR-909。

### Q-908 workflowの権限とアクションの固定

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。`permissions: contents: read`のみ。公式アクションをメジャーバージョンで指定。ランナーは`ubuntu-24.04`を明示 |
| 変更 | ランナー固定の根拠を改める。旧clarifyは「PythonとDocker Composeのバージョンが一覧で確認できるため」だった。新方針ではComposeを使わない |
| 新しい根拠 | Docker、AWS CLI v2、`python3`がランナーのイメージに入っていることを前提にするため、イメージの世代を固定する |

使うアクションは`actions/checkout`と`actions/upload-artifact`の2つだけで、サードパーティは使わない（NFR-911）。
ダミー認証情報（`AWS_ACCESS_KEY_ID=test`など）はworkflowの`env`に書く（FR-913）。Secretsは使わない。
`pull_request`はフォークからでも同じ権限で動くが、書き込み権限が無く、Secretsも使わないため問題ない。

AWS CLI v2とPython 3のバージョンは、ランナーのイメージ一覧で確認する。実機確認の表に残す。

影響するFR/NFR: FR-913、NFR-902、NFR-911。

### Q-909 検査の入口と通信検証の項目

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。`tests/m09-execution-and-ci.sh`に`unit`と`smoke`を置き、品質ゲートに登録する |
| 新方針との整合 | 矛盾しない。M08と同じ形（既定は`smoke`、不正な引数は終了コード2）にそろえる |

| モード | 内容 |
| --- | --- |
| `unit` | Dockerと実AWSを使わない。完成版の生成（置換、未置換の検出、本番向けの拒否）、`SQUID_UPSTREAM`の値の検査、入口の前提検査と終了コードの保持、stopの冪等性、cleanupの順序、アカウントIDの混入検査、workflowの静的検査。`docker`と`aws`は偽物を`PATH`の先頭に置く |
| `smoke` | `unit`に続けて、MiniStackの登録と契約検証、疎通検証、不正な`SQUID_UPSTREAM`の起動失敗、冪等性を実機で行う |

通信検証（`test`）の項目を次のとおり確定する。

| 番号 | 項目 | 期待値 |
| --- | --- | --- |
| 1 | mockでの許可ドメイン | Clientが`http://api.example.com`へ要求し、WireMockの応答が返る（`CLIENT_STATUS=200`、終了コード0） |
| 2 | 許可外ドメイン | Clientが許可外のドメインへ要求し、Squidが拒否する（`CLIENT_STATUS=403`）。WireMockの受信数は0のまま |
| 3 | sidecarの再起動後 | Squidだけを再起動した後も、1と同じ要求が成功する。pauseのlocalhost共有が保たれている |

追加の`smoke`の確認は次のとおり。

| 項目 | 期待値 |
| --- | --- |
| 不正な`SQUID_UPSTREAM` | 未設定、`mock`と`direct`以外の値で、Squidのコンテナが非ゼロで終了する（FR-908） |
| 上流の確認 | 起動ログに有効な上流（`mock`または`direct`）が出る（Q-916） |
| directの構文 | `squid -k parse`が設定を受理する。実際の外部通信は行わない |

WireMockのシナリオの切り替えは、`scripts/scenario-lib.sh`のリセット関数を使う。
失敗注入によるアーティファクトの確認は、本番のworkflowに分岐を持ち込まず、一時ブランチで一度だけ行う。

影響するFR/NFR: FR-907、FR-908、FR-909、FR-915、5.2。

### Q-910 文書の置き場所とREADMEの更新

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。`docs/ローカル実行とCI.md`を新設し、`README.md`の実行手順を更新する。ルートの`plan.md`は変更しない |
| 変更 | READMEの旧Compose手順は、Q-912の決定により、移行が終わるまで残す。旧手順は「移行完了後に削除」と明記して区別する |

`docs/ローカル実行とCI.md`に書く内容は次のとおり。

- 各操作の目的と終了コード
- ダミー認証情報の設定手順（利用者が自分のターミナルで設定する。エージェントのシェルでは設定しない）
- `start`と`test`の関係と、旧基盤の検査（Compose）との排他（同じポート8080を使う）
- CIの見方、失敗時のアーティファクトの取得方法
- 所要時間の目安（実測後）
- 再現性の要因（Q-907、ポートの空き）
- Q-909の失敗注入の結果

影響するFR/NFR: FR-919、7章の完了条件。

### Q-911 package.jsonの位置づけ

| 項目 | 内容 |
| --- | --- |
| 決定 | 旧clarifyの決定を維持。npmを正とし、`npm run <操作>`を契約とする |
| 新方針との整合 | 矛盾しない |

`npm start`と`npm test`は`run`なしでも動く。`start`と`test`の2つはこの略記でも呼べるため、文書は`npm run`の形に統一する。
CIは`actions/setup-node`と`npm ci`を使わず、ランナー標準のnpmで`npm run test:ci`を実行する（実行時の依存が無いため）。
`pnpm`は検証対象にしない。

### Q-912 既存検査（M01〜M08）の移行の範囲

| 項目 | 内容 |
| --- | --- |
| 選択肢A | M09は基盤、テンプレート、MiniStack契約、新しい疎通検証、CIまで。M02〜M08とS14の移行は別Issueに分ける |
| 選択肢B | Aに加え、M08の4シナリオ（正常、500後に成功、429、タイムアウト）を新基盤へ移す |
| 選択肢C | M02〜M08とS14の全てをM09で移し、Composeを同時に削除する |
| 決定 | 選択肢A（推奨案どおり）。利用者がA案を承認した（2026-11-04） |

事実関係は次のとおり。

| 事実 | 根拠 |
| --- | --- |
| M02〜M08、S14、品質ゲートの全てが`docker-compose`を呼ぶ | 前提の表。合計で90回前後の呼び出し |
| S14は`squid.conf`の行を固定で検査する | `tests/s14-compose-port-binding.sh`の429〜444行 |
| M08だけで1076行あり、起動と停止と残存確認が`docker-compose`に結びつく | `tests/m08-e2e-suite.sh`の749行、813行、905行、1024行 |
| 新基盤のtestはClientを`docker run --network container:<pause>`で起動する。`docker-compose run`の呼び出しは置き換える必要がある | `m08`の586行、589行 |

選択肢Aを採る理由は次のとおり。

- Issue #9の主題は、入口とCIの統合である。既存検査の全面移行を含めると、範囲が数倍になる。
- 新基盤の疎通検証（Q-909の3項目）と、M08の4シナリオは、別の契約として分けられる。
- 旧基盤の検査は、移行が終わるまで品質ゲートで動かし続けられる。

選択肢Aの注意点は次のとおり。

| 注意点 | 対処 |
| --- | --- |
| CIで検証するのはQ-909の3項目と契約検証だけになり、M08の4シナリオ（リトライ、バックオフ、タイムアウト）はCIに載らない | 別Issueの優先度を、M09の直後に置く。移行完了までのCIの検証範囲を、`docs/ローカル実行とCI.md`に明記する |
| 移行までの間、`docker-compose.yml`がリポジトリに残る。方針1（併用や切り戻しの経路を残さない）と一時的に食い違う | FR-920の対象を「新基盤」に限る。新基盤はComposeを呼ばず、切り戻しの処理も持たない。旧基盤の削除は別Issueで完了条件にする |
| 旧基盤と新基盤がホストの8080を共有する | `start`が8080の使用中を検出して止まる（FR-912）。同時に動かさない |
| 旧基盤の`squid.conf`と新基盤の設定が二重管理になる | Q-917のとおり、`squid.conf`を単一の情報源にする |

Issue #9の本文の「Compose起動待機とテスト実行」は、新方針で置き換わる。Issueの更新は利用者に依頼する（エージェントは編集しない）。
別Issueの起票も利用者に依頼する。起票の下書きは、後続の工程で用意できる。

影響するFR/NFR: FR-920、NFR-903、7章。

### Q-913 pause方式で扱うタスク定義の項目

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。扱う項目を限り、それ以外は完成版に含まれていれば失敗させる（fail closed） |

扱う項目と、dockerコマンドへの対応は次のとおり。

| 項目 | 対応 |
| --- | --- |
| `name`、`image` | コンテナ名（`swsc-`+`name`）とイメージ |
| `environment` | `--env`。値は引数ではなく`--env-file`に書き出し、プロセス一覧に出さない |
| `essential` | falseのClientは、testでの1回起動とする。trueのSquidは、終了したらstartを失敗させる |
| `portMappings` | 公開には使わない。awsvpcの`containerPort`だけを、重複の検査に使う（同じポートを2つのコンテナが待ち受けない） |
| `dependsOn` | 起動の順序に変換する。条件`START`と`HEALTHY`を扱う |
| `healthCheck` | `--health-cmd`、`--health-interval`、`--health-timeout`、`--health-retries`、`--health-start-period`に変換する |
| `command`、`entryPoint` | `docker run`の引数と`--entrypoint`に変換する |

扱わない項目（`volumes`、`mountPoints`、`secrets`、`logConfiguration`、`linuxParameters`、`user`、`readonlyRootFilesystem`など）は、
完成版に含まれていれば「未対応の項目」と名指しして失敗させる。
Squidの設定はイメージに含める（Q-917）。tmpfsの代わりにコンテナの書き込み層を使う。

タスクレベルの項目（`family`、`networkMode`、`requiresCompatibilities`、`cpu`、`memory`）はテンプレートに固定値で書く。
`taskRoleArn`と`executionRoleArn`は書かない。アカウントIDを含むARNをリポジトリに置かないため。
`requiresCompatibilities`、`cpu`、`memory`をMiniStackが受け付けるかは、実機確認の表に残す。

影響するFR/NFR: FR-902、FR-904、FR-906、FR-918。

### Q-914 MiniStackの使い方の範囲

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。MiniStackにはタスク定義の登録と`describe`による契約検証だけを使う。run-taskは使わない。Dockerソケットは渡さない |
| 理由 | 通信の検証はpause方式で行う（1.2）。このため、MiniStackにDockerを操作させる理由が無くなった。ソケットを渡すと、MiniStackがホストのDockerを操作できる権限を持つ（NFR-906）。不要な権限は渡さない |

利用者は以前、ソケットの受け渡しを了承していた。不要になったため、渡さない方針に改める。利用者確認は不要で、通知のみとする。

細則は次のとおり。

| 項目 | 決定 |
| --- | --- |
| 起動 | `docker run -d --name swsc-ministack -p 127.0.0.1:4566:4566`と、ラベル。ソケットのマウントなし |
| タグ | 固定する（Q-907） |
| ColimaのDockerソケットのパス | 不要になったため、文書から外す |
| 契約検証の範囲 | ネットワークモード、コンテナ名と数、イメージ、環境変数、`essential`、ポート、`dependsOn`、`healthCheck`が一致すること（FR-904） |
| 登録の失敗 | 原因を示して非ゼロで終了する。登録できないタスク定義でpause方式の起動に進まない |

ソケットなしでMiniStackが登録と`describe`に応答するかは、1.2で確認していない（1.2はソケットを渡した状態の結果）。実機確認の表に残す。
応答しない場合は、方針を変えず、ソケットなしで動くMiniStackの設定を調べる。ソケットの受け渡しに戻すかどうかは、利用者に確認する。

影響するFR/NFR: FR-904、FR-905、NFR-906。

### Q-915 WireMockの宛先の受け渡しと到達方法

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。固定名のDockerネットワーク`swsc-net`にWireMockとpauseを置き、Squidへ渡す環境変数にWireMockのコンテナ名とポートを指定する |
| 変更点 | 推奨案の「実行ごとのネットワーク」は採らない。固定名にして、stopとcleanが冪等に消せるようにする |

| 項目 | 決定 |
| --- | --- |
| ネットワーク | `swsc-net`（bridge） |
| WireMock | コンテナ名`swsc-wiremock`、`swsc-net`に参加。ホストへ`127.0.0.1:8080`を公開（管理APIの呼び出し用） |
| pause | コンテナ名`swsc-pause`、`swsc-net`に参加。pauseにはポートを公開しない |
| 環境変数 | Squidのコンテナに`SQUID_MOCK_HOST=swsc-wiremock`と`SQUID_MOCK_PORT=8080`を渡す |
| ホスト名の検査 | Squidのエントリポイントが、`SQUID_MOCK_HOST`を英数字、`.`、`-`だけ、`SQUID_MOCK_PORT`を数字だけに限り、外れたら起動を失敗させる（設定への注入を防ぐ） |
| ECSの名前解決 | 対象外（Service Connect等） |

WireMockのコンテナ名の解決は、ユーザー定義のネットワークの組み込みDNSに依存する。
`--network container:swsc-pause`で参加するSquidが、同じDNSで名前を引けるかは実機確認の表に残す。

影響するFR/NFR: FR-910、NFR-907。

### Q-916 本番でmockになっていないことの検査方式

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。完成版の生成に`--profile production`を設け、本番向けでは`SQUID_UPSTREAM`が`direct`以外、またはWireMockの宛先があれば失敗させる |
| 追加の決定 | 任意のタスク定義ファイルを検査する操作`scripts/e2e.sh check-production <ファイル>`を足す。将来のデプロイ工程が、登録直前のJSONに対して呼べる |
| 理由 | 生成時の検査は、M09が生成した完成版にしか効かない。本番へ渡る直前のJSONを検査できる入口があれば、生成を経ない経路にも防御を掛けられる |

検査の層は次のとおり。

| 層 | 検査 | 実行場所 |
| --- | --- | --- |
| 1 | テンプレートに`mock`が既定値として書かれていない（静的） | `unit`、CI |
| 2 | 本番向けの生成で`SQUID_UPSTREAM`が`direct`以外なら失敗。WireMockの宛先（`SQUID_MOCK_HOST`、`SQUID_MOCK_PORT`）が残っていれば失敗 | `unit`、CI |
| 3 | `check-production`が任意のJSONに同じ検査を行う | `unit`。将来のデプロイ工程 |
| 4 | Squidの起動ログに有効な上流を出す | `smoke` |

層1〜3の検査は、`mock`の既定値、大文字小文字の違い、前後の空白、環境変数の欠落の入力で拒否することを`unit`で固定する。

本番にはWireMockの宛先を書かないため、directのSquidが誤ってWireMockへ接続することはない。
ただしSquid自身が環境変数だけを信頼する点は残る。本番の実環境でmockになっていないかの確認は、デプロイ工程の責任とし、M09の対象外とする。

影響するFR/NFR: FR-908、FR-909。

### Q-917 Squidのイメージの作り方

| 項目 | 内容 |
| --- | --- |
| 選択肢A | 推奨案どおり、`mock`用と`direct`用の設定ファイルを別々にイメージに含める |
| 選択肢B | 既存の`squid-config/squid.conf`を単一の情報源とし、エントリポイントが起動時に派生させる |
| 決定 | 選択肢B（推奨案から変更） |
| 理由 | `tests/s14-compose-port-binding.sh`が`squid.conf`の行を固定で検査する（429〜444行）。設定を2ファイルに分けると、旧基盤の検査と新基盤の設定が二重管理になり、ACLの変更が片方にだけ入る恐れがある。移行完了までは、`squid.conf`を直接書き換えない |

派生の方針は次のとおり。詳細はplanで決める。

| 項目 | 方針 |
| --- | --- |
| イメージ | `ubuntu/squid`を`FROM`に、`squid.conf`、`whitelist.txt`、エントリポイントを含める。ボリュームのマウントに頼らない |
| mock | `squid.conf`の`cache_peer wiremock parent 8080 0 no-query`と、`cache_peer_access wiremock`の行のホスト名とポートを置換する。置換の対象は固定の行に限る |
| direct | `cache_peer`、`cache_peer_access`、`never_direct`の行を除き、許可ドメインへ`always_direct allow api_domains`を足す |
| 検査 | 起動前に`squid -k parse`で、派生した設定を検査する。失敗したら非ゼロで終了する |
| 未設定、不正値 | `SQUID_UPSTREAM`が`mock`と`direct`以外なら、非ゼロで終了する（FR-908） |
| 元のエントリポイント | `ubuntu/squid`が持つ起動処理に引き渡す。内容はplanで実機確認する |

派生の元の行の書式が変わると、置換が空振りする。`unit`で「置換の対象の行が1行ずつ存在する」ことを固定する。
許可ドメインの一覧（`whitelist.txt`）は、現在ダミーのドメインである。本番のドメインへの差し替えはM09の対象外とする。

影響するFR/NFR: FR-908、FR-909、NFR-903。

### Q-918 Clientの実行形態

| 項目 | 内容 |
| --- | --- |
| 決定 | 推奨案を採る。タスク定義では`essential`をfalseとする。`start`では起動せず、`test`が1回の検証ごとに起動して、終了コードを検証結果に使う |
| 理由 | ClientはM04のとおり1回の要求で終了する。M06〜M08では、検証ごとに環境変数（`TEST_API_PATH`、`RESPONSE_TIMEOUT_SECONDS`など）を上書きして起動する。常駐させる設計は、実態に合わない |

Clientの扱いは次のとおり。

| 項目 | 決定 |
| --- | --- |
| 起動 | `docker run --rm --network container:swsc-pause`。イメージと環境変数は完成版のClientの定義から読む。検証ごとの上書きを加える |
| `HTTP_PROXY`、`HTTPS_PROXY` | `http://127.0.0.1:3128`。`squid`というホスト名は使わない（awsvpcではlocalhost共有のため） |
| `NO_PROXY` | `localhost,127.0.0.1`だけにする。`squid`と`wiremock`は消す |
| `healthCheck` | Clientには置かない。1回で終わるため、意味が無い |
| 終了コード | Clientの終了コードと標準出力・標準エラーを、検証の入力に使う |

Clientの出力の契約（`CLIENT_STATUS`、`CLIENT_BODY`、`CLIENT_DIAG`、終了コード0と28と78）は変わらない（NFR-903）。

影響するFR/NFR: FR-902、FR-906、FR-907。

## 利用者確認

利用者の判断が必要だった1件は、承認済みである。

| 番号 | 判断 | 選択肢と影響 | 結果 |
| --- | --- | --- | --- |
| 1 | 既存検査（M02〜M08、S14）の移行をM09に含めるか分けるか（Q-912） | A: 分ける。M09は基盤と新しい疎通検証まで。CIにはM08の4シナリオが載らず、`docker-compose.yml`が一時的に残る。B: Aに加え、M08の4シナリオを新基盤へ移す。CIがリトライ、バックオフ、タイムアウトまで検証するが、M08の1076行の改修が加わる。C: 全部をM09で移し、Composeも削除する。方針1を満たすが、範囲が数倍になる | A案を承認（2026-11-04）。別Issueの優先度をM09の直後に置く |

通知のみで、確認を求めない変更点は次のとおり。

| 件 | 内容 |
| --- | --- |
| Q-914 | MiniStackにDockerソケットを渡さない。以前の了承は不要になったため使わない |
| Q-903 | M08のsmokeにログ収集を足さない。収集は新基盤の入口が持つ |
| Q-906 | testステップのタイムアウトを5分から10分にする（`test:ci`が起動まで含むため） |
| Q-917 | Squidの設定は`squid.conf`を単一の情報源とし、起動時に派生させる |

## plan以降の実機確認

Dockerが必要な項目は、clarifyでは実行しない。

| 事項 | 確認の手順 | 結果の反映先 |
| --- | --- | --- |
| ColimaでのCI相当の通し動作 | `test:ci`の全工程（生成、登録、起動、疎通、収集、停止）をColimaで実行する | plan、`docs/ローカル実行とCI.md` |
| Linux（GitHub Actions）でのpause方式 | PR上のworkflowで、pauseにSquidとClientを参加させ、疎通が成功することを確かめる | plan、FR-906 |
| Squidの送信元ACL（S14のlocal_src） | Linuxで、Clientからの要求が`access.log`に`127.0.0.1`として記録され、`local_src`で許可されることを確かめる。許可外ドメインは403になる | Q-909、plan |
| MiniStackの登録（ソケットなし） | ソケットを渡さずに起動し、`register-task-definition`と`describe-task-definition`が応答することを確かめる | Q-914、plan |
| MiniStackの`describe`の忠実度 | `healthCheck`、`dependsOn`、`portMappings`、`essential`、`environment`が登録した内容と一致して返るか。`requiresCompatibilities`、`cpu`、`memory`の受理。`taskDefinitionArn`の形（アカウントIDの有無） | FR-904、Q-905、Q-913 |
| 完成版の生成のシェル実装 | amazon-ecs-render-task-definition相当の置換を、POSIX shとpython3（またはjq）でどう実装するか。置換値のJSONエスケープ、未置換の検出、生成の失敗時の挙動 | plan、NFR-911 |
| Squidのエントリポイント | `ubuntu/squid`の元のエントリポイントとの連携。環境変数による設定の派生、`squid -k parse`、不正値での非ゼロ終了、tmpfsなしでのログと`spool`の書き込み権限 | Q-917、plan |
| `mock`と`direct`の動作確認 | directは外部へ出ないため、設定の構文検査とログの確認に限る。directの実通信を検証する別の手段が要るか | Q-916、plan |
| WireMockのコンテナ名の解決 | `--network container:swsc-pause`で参加するSquidが、`swsc-net`の組み込みDNSで`swsc-wiremock`を引けるか。ColimaとLinuxの両方。Squidの`cache_peer`が起動時に名前を解決するため、WireMockの起動順 | Q-915、plan |
| ヘルスチェックの変換 | `healthCheck`から`--health-*`への変換。`startPeriod`の扱い。`docker inspect`で待機する秒数 | Q-913、Q-906 |
| Squid再起動後の疎通 | Squidだけを再起動して、pauseのlocalhost共有が保たれ、疎通が戻ること（1.2はsidecarの再起動で確認済み。M09の構成で再確認する） | Q-909、FR-907 |
| Clientの`HTTP_PROXY`の変更 | `127.0.0.1:3128`で、Clientの出力と終了コードの契約（M04〜M06）が変わらないこと | Q-918、NFR-903 |
| 冪等性、中断 | `start`の二重実行、`stop`と`clean`の二重実行、`INT`と`TERM`での後始末、ラベルによる他リソースの保護 | NFR-908、FR-911 |
| 旧基盤との排他 | 旧基盤が稼働中に`start`が、ポート8080の使用中を検出して止まること | FR-912、Q-912 |
| アカウントIDの混入検査 | MiniStackの出力に12桁の数字とARNが現れるか。収集後の検査が検出して削除すること | Q-905、FR-918 |
| ランナーの前提 | `ubuntu-24.04`のイメージに、Docker、AWS CLI v2、`python3`が入っているバージョン | Q-908、plan |
| 初回のCI時間 | MiniStackのイメージ取得、Squidのビルド、`test:ci`全体の時間。10分のステップと15分のジョブに収まるか | Q-906、NFR-904 |
| 失敗注入とアーティファクト | 一時ブランチで失敗を注入し、アーティファクトの取得と中身を確認する。タイムアウト時に収集のステップが走ること | Q-904、Q-909 |
| 取り消しの動作 | 同じPRに2回pushして、1回目が取り消されること。`main`のpushが取り消されないこと | Q-902 |

## specへの反映事項

spec.mdは、この工程では変更しない。後続の工程で次を反映する。

| 番号 | 更新箇所 | 変更 | 出典 |
| --- | --- | --- | --- |
| 1 | 2章の2項目目 | 「Clientとの2コンテナ」を「ClientとSquidの2コンテナ」に直す | 誤記 |
| 2 | 3章 FR-901 | 入口を`scripts/e2e.sh`と`package.json`の6つのscriptsに確定する。`collect`と`check-production`の補助操作を足す | Q-901、Q-903、Q-916 |
| 3 | 3章 FR-902 | Clientの`HTTP_PROXY`と`HTTPS_PROXY`を`http://127.0.0.1:3128`、`NO_PROXY`を`localhost,127.0.0.1`にすると書く。Clientの`healthCheck`は置かない | Q-918 |
| 4 | 3章 FR-902、FR-904 | タスクレベルの項目（`family`、`requiresCompatibilities`、`cpu`、`memory`）は固定値。ロールのARNは書かない | Q-913 |
| 5 | 3章 FR-906 | Clientはstartで起動せず、testの検証ごとに1回起動して、環境変数の上書きを受けると書く | Q-918 |
| 6 | 3章 FR-907 | 通信検証を3項目に確定する（mockの許可ドメイン、許可外の403、Squid再起動後） | Q-909 |
| 7 | 3章 FR-908 | `SQUID_MOCK_HOST`と`SQUID_MOCK_PORT`を足す。設定は`squid.conf`から派生させる。値の文字種を検査する | Q-915、Q-917 |
| 8 | 3章 FR-909 | `check-production <ファイル>`による任意のJSONの検査を足す。検査の4層を書く | Q-916 |
| 9 | 3章 FR-910 | ネットワーク`swsc-net`、コンテナ名`swsc-wiremock`、ホスト公開`127.0.0.1:8080`を書く | Q-915 |
| 10 | 3章 FR-911 | 対象にMiniStack、ネットワーク`swsc-net`、ラベル`swsc.managed=true`を明記する。`.e2e/`と`e2e-logs/`をcleanの対象にする | Q-901、Q-903 |
| 11 | 3章 FR-912 | 前提検査に`python3`（またはjq）、ポート8080と4566の空きを足す。旧基盤との排他を書く | Q-912、実機確認 |
| 12 | 3章 FR-914、FR-915 | workflowの手順を、実行（`test:ci`）、収集（`always`）、アップロード（`failure`）、後処理（`always`）の順に改める | Q-904 |
| 13 | 3章 FR-916、FR-918 | 保存内容の一覧を確定する。MiniStackの出力はARNとアカウントIDを含まない項目だけを取る。収集後に`[0-9]{12}`と`arn:aws`を検査する | Q-905 |
| 14 | 3章 FR-917、5.1 NFR-904 | testステップの`timeout-minutes`を10、ジョブを15、起動待機を120秒にする | Q-906 |
| 15 | 3章 FR-920 | 対象を「新基盤」と明記する。`docker-compose.yml`の削除は別Issueの完了条件とする | Q-912 |
| 16 | 4章の表 | startとtestの内容を改める。`collect`、`check-production`を足す。`test:ci`の順序（前提検査、start、test、収集、stop）を書く | Q-901 |
| 17 | 5.1 NFR-906 | 「run-taskを使う場合に限り渡す」の文を削る。Dockerソケットは渡さない | Q-914 |
| 18 | 5.1 NFR-907 | Squidのポートを公開しないと書く。公開は`127.0.0.1:8080`（WireMock）と`127.0.0.1:4566`（MiniStack）に限る | Q-915 |
| 19 | 5.1 NFR-909 | 固定するもの（MiniStack、`alpine:3.20`）と、固定しないもの（`ubuntu/squid:latest`）を分ける。ダイジェストを残す | Q-907 |
| 20 | 5.1 NFR-911 | `python3`（またはjq）の依存を注記する。完成版の生成と契約検証の比較に使う | Q-913、実機確認 |
| 21 | 5.2 | `unit`と`smoke`の内容を確定する。上流の確認と、アカウントIDの混入検査を足す | Q-909 |
| 22 | 6章（対象外） | 次を足す。既存検査（M02〜M08、S14）の移行と`docker-compose.yml`の削除（別Issue）、`whitelist.txt`の本番ドメイン、本番の実環境でmockでないことの確認 | Q-912、Q-916、Q-917 |
| 23 | 7章 | 完了条件に「M08の4シナリオはCIに載らない。別Issueで追跡する」を足す（A案の承認により確定） | Q-912 |
| 24 | 8章 | Q-901〜918をすべて解消済みにする。Q-912は利用者がA案を承認した（2026-11-04）ため「解消（利用者承認: A案）」にする | 全般 |
