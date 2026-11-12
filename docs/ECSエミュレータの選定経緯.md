# ECS エミュレータの選定経緯

ローカルと CI で、AWS と同じ完成版のタスク定義を `run-task` で動かすために、ECS のエミュレータを比べた。
結論は fakecloud である。この文書は、比べた候補、確かめたこと、選んだ理由、残る差を記録する。

確認は 2026-11-12 に、ローカルの Docker（Colima）で行った。

## 求めた条件

| 条件 | 理由 |
| --- | --- |
| 完成版のタスク定義を、ECS の API（`register-task-definition`、`run-task`）で実行できる | AWS と同じ定義で検証するため |
| コンテナを実際に起動する | Client と Squid の実通信で、リトライとタイムアウトを確かめるため |
| `dependsOn: HEALTHY` と `healthCheck` が効く | Client は Squid が待ち受けてから起動する必要があるため |
| 同じタスクのコンテナが `127.0.0.1` を共有する | AWS の `awsvpc` と同じく、`HTTP_PROXY=127.0.0.1:3128` で届くため |
| 無料で、アカウントやトークンが要らない | CI で使うため |

4 つ目の条件は、どの候補も満たさなかった。そのため、Client のプロキシを Squid の別名にして補った（後述）。

## 候補

| 候補 | ライセンス | ECS | 試したか |
| --- | --- | --- | --- |
| MiniStack 1.5.37 | MIT | コンテナを実行する | 試した |
| AWS Emulator（`aws/aws-emulator`） | CC0 | API はあるが、コンテナの実行は確認できなかった | 試していない（ソースと文書を読んだ） |
| fakecloud 0.51.0 | AGPL-3.0 | コンテナを実行する | 試した |
| Floci | MIT | コンテナを実行するとされる | 試していない |
| LocalStack | 独自 | 有料 | 対象外 |
| moto、kumo | Apache-2.0、MIT | モックが中心とされる | 試していない |

LocalStack は、2026 年 3 月にコミュニティ版をやめ、アカウントとトークンが必要になったとされる。
無料で使う条件に合わないため、対象外にした。出典は
[比較記事](https://codenote.net/en/posts/localstack-archived-oss-alternatives-comparison/) と
[fakecloud の README](https://github.com/faiscadev/fakecloud) である。

## 確かめたこと

### MiniStack

| 確認事項 | 結果 |
| --- | --- |
| 登録と `run-task`、コンテナの起動 | できた |
| 同じタスクのコンテナの `127.0.0.1` | 共有しない。コンテナごとに別の `bridge` で起動した |
| `healthCheck` | 反映されない（コンテナのヘルス状態が空） |
| `dependsOn: HEALTHY` | 効かない。Client が Squid の起動を待たずに動いた |
| `portMappings` | `awsvpc` では、ホストへ公開されない |
| コンテナ名 | `ministack-ecs-<タスクIDの先頭8文字>-<名前>`。毎回変わり、別名の指定もない |

Squid に別名を付けて Client を向ける案も試した。専用ネットワークに MiniStack と WireMock を置き、
`run-task` の直後に別名を付けた。3 回とも Client が失敗した。名前を解決できないか、Squid が起動前で
接続できなかった。Client には接続の再試行がなく、`dependsOn: HEALTHY` も効かないため、競合を避けられなかった。

MiniStack は、ECS のコンテナを MiniStack 自身が参加するネットワークに置く。
そのため、MiniStack を自作のネットワークで起動すれば、同じネットワークの WireMock を名前で引ける
（ソースを読んだ内容で、実行では確かめていない）。

### AWS Emulator

[`aws/aws-emulator`](https://github.com/aws/aws-emulator) は AWS 公式の API エミュレータである。ECS の API のクレートはある。
ただし、README と `RunTask` のソースの冒頭は、タスクを `PENDING` で記録し、`RUNNING` への移行を
「時計で決まる」と書いている。コンテナを起動する記述は見つからなかった。
同じリポジトリの Issue には、EMR Serverless のジョブが「記録されるが実行されない」という報告もある。
README は、本番のワークロードやセキュリティの検証には使わないとも書いている。

このリポジトリは、Client と Squid の実通信を確かめるため、コンテナを実行しないエミュレータは使えない。
動かしての確認はしていない。ECS の API の応答だけを確かめる用途なら、候補になりうる。

### fakecloud

| 確認事項 | 結果 |
| --- | --- |
| 登録と `run-task`、コンテナの起動 | できた。Docker のソケットを渡して動かす |
| `healthCheck` | 反映された |
| `dependsOn: HEALTHY` | 守られた。Client は Squid が healthy になってから起動した |
| 同じタスクのコンテナの `127.0.0.1` | 共有しない。タスクごとに専用の Docker ネットワークを作り、コンテナごとに別の名前空間になる |
| `taskRoleArn` を付けたとき | コンテナごとに holder ができ、やはり共有しない |
| `run-task` の `overrides`（環境変数） | 効く |
| ローカルにしか無いイメージ | pull が拒否され `TaskFailedToStart` になる。ローカルのレジストリが要る |
| `portMappings` | 書いたポートをホストの全インターフェース（`0.0.0.0`）へ公開する |
| コンテナ名 | `<タスクID>-<名前>`。毎回変わる。ラベルは `fakecloud-ecs-task`、`fakecloud-ecs-container` |
| 終わったコンテナ | エミュレータが後から消す |

Squid に別名を付ける案は、fakecloud では成立した。`dependsOn: HEALTHY` が効くため、Client は Squid の
準備ができてから起動する。専用ネットワークに別名を付けた状態で、`run-task` を繰り返しても失敗しなかった。

## 選んだ理由

| 理由 | 内容 |
| --- | --- |
| 必須の条件を満たした | コンテナを実行し、`healthCheck` と `dependsOn: HEALTHY` が効く。MiniStack は後者が効かず、競合を避けられなかった |
| 外側の処理が小さい | 別名を付ける処理と、WireMock のネットワーク接続だけで済む |
| 無料 | アカウントとトークンが要らない |
| AWS Emulator は用途に合わない | コンテナを実行する記述が見つからず、実通信の検証に使えない見込みだった |

条件の「127.0.0.1 の共有」は、どの候補でも満たせない。選んだ理由は、その不足を最も小さい補い方で
済ませられたことである。

## 残る差とリスク

| 項目 | 内容 |
| --- | --- |
| AWS との差 | ローカルと CI の Client のプロキシは `swsc-squid:3128`。AWS 用は `127.0.0.1:3128`。差は環境変数の値だけにしている |
| 検査 3 | Squid 再起動後の確認は、同じタスクのネットワークで Client を追加で実行する。ECS を通らない |
| Docker のソケット | fakecloud はホストの Docker を操作できる。公開先を `127.0.0.1` に限り、CI は使い捨てのランナーで動かす |
| ライセンス | fakecloud は AGPL-3.0。社内のローカル開発と CI での利用を想定している。製品へ同梱するなら見直す |
| 成熟度 | fakecloud は 2026 年に出た新しいプロジェクトで、版を固定している（0.51.0）。上げるときは、全検査をやり直す |
| 未確認 | CI（GitHub Actions）での実行。AWS 本物での `run-task`。HTTPS（`httpbin.org`）の実通信 |

## 見直しの条件

次のどれかが起きたら、候補を見直す。

- MiniStack が `healthCheck` と `dependsOn: HEALTHY` を反映し、コンテナの別名を指定できるようになった。
- fakecloud が、同じタスクのコンテナで `127.0.0.1` を共有できるようになった。
  Kubernetes のバックエンド（`FAKECLOUD_CONTAINER_BACKEND=k8s`）は Pod を使うため共有する見込みだが、試していない。
- AWS Emulator が、ECS のタスクをコンテナで実行するようになった。
- fakecloud のライセンスや保守の状況が、利用の条件に合わなくなった。

## 関連

- [テスト用 API の httpbin.org](テスト用APIのhttpbin.md)
- [ポート公開範囲](ポート公開範囲.md)
- [MVP の仕様](../specs/MVP/spec.md)
