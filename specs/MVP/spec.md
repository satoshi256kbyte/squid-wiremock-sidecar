# MVP の仕様（スリム版）

元の要件は [docs/要件定義.md](../../docs/要件定義.md)。この仕様は、それを満たしているかを実機で確かめた記録である。
構成と設計判断は [ARCHITECTURE.md](../../ARCHITECTURE.md)、テストの方式は [docs/テスト方式.md](../../docs/テスト方式.md) を参照。
Spec は、この1ファイルだけにする。分割しない。

## 目的

ECS のサイドカー構成（Client、Squid、WireMock）をローカルと CI で再現し、
HTTP クライアントのリトライとタイムアウトを、実通信の E2E で確かめる。
ローカルと CI は、AWS と同じ完成版のタスク定義を、ECS のエミュレータ（fakecloud）で `run-task` して動かす。
そのタスク定義が、そのまま AWS（Fargate）にデプロイされることも保証する。

## 範囲

対象は、`register-task-definition` と `run-task` でタスクとして起動する形に限る。
`create-service` などサービスとしての起動、ローリングデプロイ、Auto Scaling、ロードバランサーは対象外とする。
AWS 上でタスクが止まらないこと（Squid が `essential`）も、検証の対象外とする。手動で止める。

## 範囲外

単体テスト、スクリプトの中身を読む検査、MiniStack の contract、品質ゲートのスクリプト、
仕様と計画を何本にも分ける運用。テストは E2E だけにする。ビジネスロジックのテストは、必要になったときに足す。
CDK のコードに対する jest のテストも入れない。代わりに `check-cdk` で `cdk synth` の出力を検査する。

## 要件と受け入れ条件

確認は 2026-11-12。ローカルは Docker（Colima）で行った。CI（GitHub Actions）では PR #44 と #46 で通った。
AWS での確認は、「AWS での確認」に書く。

| ID | 要件 | 受け入れ条件（確認方法） | 結果 |
| --- | --- | --- | --- |
| R1 | ECS サイドカー構成を再現する | タスク定義が `awsvpc` で `client` と `squid` の2コンテナを持ち、fakecloud の `run-task` で起動する（`npm run test:ci`） | 満たす |
| R2 | 許可ドメインだけを Mock へ転送する | 許可ドメインは 200 で受信数 1、許可外は 403 で受信数 0（`npm run test:ci` の検査 1、2） | 満たす |
| R3 | 閉域は、プロキシの許可リストで担保する | 許可外のドメインは、プロキシ経由で 403 になり、Mock に届かない（検査 2）。プロキシを使わない直接接続の遮断は保証しない | 満たす（範囲を限定） |
| R4 | 異常系を再現する | 500 の後の 200、429 の再試行の使い切り、5秒遅延のタイムアウトが期待値どおりになる（4シナリオの `test:ci`） | 満たす |
| R5 | 振る舞いを JSON で定義する | `wiremock-scenarios/mappings/` の JSON を読み取り専用でマウントして応答する | 満たす |
| R6 | コマンド一つで構築から破棄まで行う | `npm run test:ci` が起動、検査、収集、停止を続けて行い、コンテナ、ネットワーク、レジストリ用のタグが残らない | 満たす |
| R7 | 構成をコードで管理する | `ecs/task-definition.template.json` と Squid の設定が、リポジトリのファイルである | 満たす |
| R8 | Docker Compose を使わない | Compose のファイルと呼び出しが無い | 満たす |
| R9 | ローカルと CI は、完成版のタスク定義を fakecloud に登録して `run-task` で実行する | 実行されるコンテナが、完成版の `client` と `squid` である。`docker-args` と pause を使わない | 満たす（Squid 再起動後の確認の追加 Client だけは ECS を通らない） |
| R10 | AWS 用との差は、環境変数の値とイメージの参照だけにする | `render` の出力の差が、イメージ、`HTTP_PROXY`、`HTTPS_PROXY`、`TEST_API_BASE_URL`、`SQUID_UPSTREAM`、`SQUID_MOCK_*` に限られる | 満たす |
| R11 | 既存の検査を、新しい方式で通す | `test:ci` の 3 項目と 4 シナリオが PASS する | 満たす |
| R12 | 公開先を `127.0.0.1` に限る | WireMock、fakecloud、レジストリが `127.0.0.1` だけに公開され、Squid はホストへ公開されない | 満たす |
| R13 | 後始末で、作ったものを残さない | `stop` の後に、`swsc-` のコンテナ、タスクのコンテナとネットワーク、レジストリ用のタグが残らない | 満たす |
| R14 | AWS のタスク定義は、雛形から CDK が作る | CDK のコードに、コンテナ名、環境変数（イメージ以外）、ヘルスチェック、依存関係を書かない | 満たす |
| R15 | AWS 用のスタックは、WireMock なしの `direct` に固定する | `mock` を指定できない。`SQUID_MOCK_*` が出力に含まれない。宛先は `https://` だけ | 満たす |
| R16 | 一本化していることを機械で確かめる | `cdk synth` の出力と `render` の本番用の出力が、イメージ、ログ、ロール以外で一致する（`check-cdk`） | 満たす |
| R17 | CI は AWS に接続しない | ワークフローに認証情報と Secrets を足さない。`cdk synth` と `check-cdk` だけを行う | 満たす |

R16 の確認では、`check-cdk` が次の9通りの改ざんをすべて検出した。`mock` への変更、WireMock の変数の追加、`http://` への変更、
環境変数の追加、ヘルスチェックの変更、CPU の変更、不明なキーの追加、依存関係の削除、コンテナの追加。

## 決定

### 閉域と HTTPS

- 閉域（R3）は、Squid の許可リスト（`squid-config/whitelist.txt`）で担保する。
- 直接接続の遮断は保証しない。以前の方式（pause の名前空間）では、Client が `HTTP_PROXY` を使わずに外部へ直接接続すると
  通ることを実測した。fakecloud の方式では再測定していない。目的はリトライとタイムアウトの検証で、直接接続の遮断ではない。
- ローカルと CI は HTTP で WireMock を使い、AWS の E2E は HTTPS で `httpbin.org` を叩く。
  Squid は HTTPS を `CONNECT` で中継するだけで、復号しない。`render` の `--api-base-url` が叩く先を決め、
  本番では `https://` だけを受け付ける。叩く先のドメインは、許可リスト（`whitelist.txt`）に入れる。

### ローカルと CI の実行方式

- エミュレータは fakecloud 0.51.0 を使う。MiniStack 1.5.37 は使わない（理由は ARCHITECTURE.md の「ECS エミュレータの選定」）。
- Client を1回実行するごとに、タスクを1つ起動する。Squid は毎回起動し直す。
  Squid 再起動後の確認（検査 3）だけは、同じタスクのネットワークで Client を追加で実行する。
- 同じタスクのコンテナは `127.0.0.1` を共有しない。ローカルと CI の Client のプロキシは、Squid の別名 `swsc-squid:3128` にする。
- ECS の呼び出しは curl で行い、AWS CLI と認証情報は使わない。
- fakecloud に Docker のソケットを渡す。ホストの Docker を操作できるため、`127.0.0.1` だけに公開する。
  CI は使い捨てのランナーで動かす。fakecloud のライセンスは AGPL-3.0 で、社内のローカル開発と CI での利用を想定する。
- ローカルにしか無いイメージは、fakecloud が pull を拒否する（`TaskFailedToStart`）。ビルドしたイメージを、
  `127.0.0.1:15000` のレジストリ（`registry:2.8.3`）に置き、その参照をタスク定義に書く。
- WireMock は、タスクのコンテナではなく、`127.0.0.1:8080` に公開するコンテナのまま使う。タスクごとに、そのタスクの
  ネットワークへ接続する。Squid は起動時に WireMock の名前を引くため、Squid の起動前に接続する。
- Squid のヘルスチェックは、3128 の待ち受けを確かめる（`bash` の `/dev/tcp`）。以前の `kill -0 1` は、
  待ち受けの開始を示さず、Client が先に動くことがあったため。AWS 用の完成版も同じ定義を使う。
- タスク定義に `portMappings` を書かない。fakecloud は、書かれたポートをホストの全インターフェースへ公開するため（R12）。
  `awsvpc` では、同じタスクのコンテナ間の通信に `portMappings` は要らない。

### AWS（CDK）

- タスク定義の元は `ecs/task-definition.template.json` の1つにする。ローカルと CI は `render`、AWS は CDK が、同じ雛形から作る。
- 雛形のキーは ECS の API の JSON と同じ camelCase で、CDK の L1（`CfnTaskDefinition`）の props も camelCase のため、
  キーの変換は要らない。`cdk/lib/taskdef.ts` が、雛形を読み、許可したキーだけを通し、イメージ、`SQUID_UPSTREAM`（`direct` 固定）、
  `TEST_API_BASE_URL`、ログ、実行ロール、`runtimePlatform` を置き換える。
- 検査は `check-cdk` が行う。`cdk synth` の出力の `AWS::ECS::TaskDefinition` を camelCase に直し、イメージ、ログ、ロールの項目を除き、
  `render` の本番用の出力と比べる。`check-production` と同じ条件も確かめる。
- スタックの範囲は、VPC、VPC Block Public Access の除外、セキュリティグループ、ECS クラスタ、ロググループ、実行ロール、
  タスク定義である。サービスは作らない（`run-task` は利用者が実行）。
- ネットワークは、プライベートサブネットと NAT Gateway 1つ。除外は `allow-egress`。セキュリティグループのアウトバウンドは 443 だけ。
- イメージは、CDK のアセットでビルドして ECR へ置く。`runtimePlatform` は ARM64 固定。
- `cdk/` に TypeScript で置き、依存は `cdk/package.json` に持つ。ルートの `package.json` は変えない。
- スタックに `env` を渡さない。渡すと、AZ の検索結果（`cdk.context.json`）や `cdk.out` にアカウント ID が残るため。
- CI は `npm ci --ignore-scripts`、`cdk synth`、`check-cdk` を足す。AWS には接続しない。デプロイは利用者が行う。

## 実測

| 項目 | 結果 |
| --- | --- |
| fakecloud 0.51.0（Docker）で `healthCheck` と `dependsOn: HEALTHY` | 効く |
| MiniStack 1.5.37 で同じ項目 | 効かない |
| 同じタスクのコンテナが `127.0.0.1` を共有するか | fakecloud も MiniStack も共有しない |
| `taskRoleArn` を付けたとき | コンテナごとに別の holder ができ、共有しない |
| Client の出力 | エミュレータは終わったコンテナを後から消す。コンテナができた時点で `docker logs -f` と `docker wait` を付けて取る |
| 実通信 | client → squid → WireMock で、`test:ci` の 3 項目と 4 シナリオが PASS |

## AWS での確認

2026-11-12、`ap-northeast-1` に専用のリソースを作って確認し、確認後にすべて削除した。次の3ケースを、2通りの構成で `run-task` した。

| ケース | 結果 |
| --- | --- |
| `https://httpbin.org/status/200` | `CLIENT_STATUS=200`。Squid のログに `CONNECT httpbin.org:443` が `TCP_TUNNEL/200` で残る |
| `https://httpbin.org/status/500` | 5xx を 3 回再試行し、`retries_exhausted`（試行 4、`CLIENT_STATUS=500`） |
| `https://example.org`（許可外） | Squid が `CONNECT` を拒否し、`curl: (56) CONNECT tunnel failed, response 403` |

| 構成 | 内容 |
| --- | --- |
| `render` の本番用の出力を手動で登録 | 専用の VPC、公開サブネット、公開 IP。VPC Block Public Access は、IGW 経由の双方向の通信になるため `allow-bidirectional` で除外し、インバウンドはセキュリティグループで閉じた |
| CDK（`cdk deploy` で約 3 分） | プライベートサブネットと NAT Gateway。`allow-egress` で除外。ARM64 の `awsvpc` |

削除後は、スタック、VPC、NAT Gateway、サブネット、ロググループが残らない。ECS クラスタは `INACTIVE` と表示される（削除済みの記録が
一定期間残る仕様）。CDK のアセットとして ECR に置いたイメージは、`cdk destroy` では消えないため、手動で削除した。

## 計画と作業

作業は完了している。

1. 要件定義の「閉域ルーティング」を、許可リストでの担保に合わせて書き直した。
2. ランナーを、pause と `docker run` から、fakecloud の `run-task` に置き換えた（R9〜R13）。
   `render` に `--proxy-url`、`--api-base-url`、`--cpu-architecture`、ログとロールの引数を足した。`docker-args` と `compare` は削除した。
3. `cdk/` に CDK のスタックを足し、`check-cdk` と CI の `cdk synth` を足した（R14〜R17）。
4. AWS で確認した。README、ARCHITECTURE.md、`docs/` を、新しい方式に合わせて整理した。

## Analyze

- R1〜R17 は、実機の確認結果と受け入れ条件が対応している。
- 未確認: fakecloud の方式での、プロキシを使わない直接接続の遮断。fakecloud の Kubernetes バックエンド
  （同じタスクのコンテナが `127.0.0.1` を共有する見込みだが、試していない）。
- 検査 3（Squid 再起動後）の Client は、ECS を通らない。タスクの Client は1回で終わるため。
- R7 の本番向けタスク定義の検査（`check-production`）は動くが、E2E に入れていない。MVP の範囲外とする。
- `npm audit` に、`aws-cdk-lib` に同梱の `minimatch` の moderate の通知（DoS）がある。ビルド時のみで、修正は破壊的な更新が要るため、
  そのままにした。
- fakecloud は Docker のソケットを持つ。セキュリティに関わる変更として、コミット前のレビューを受けた。
