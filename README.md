# Squid WireMock Sidecar E2E Test Framework

ECS のサイドカー（Squid プロキシ）構成を、ローカルと CI で ECS のエミュレータ（fakecloud）に載せ、
外部 API のエラー応答や遅延を含む E2E テストを実施する検証用の環境。
同じタスク定義を、CDK で AWS（Fargate）にもデプロイできる。

```text
Client → Squid (:3128) → WireMock (:8080)      ローカル、CI
Client → Squid (:3128) → 外部 API（HTTPS）       AWS（WireMock なし）
```

構成、技術スタック、環境ごとの違いは [アーキテクチャ](ARCHITECTURE.md) を参照。

## 検証の範囲

ローカルと CI は、AWS と同じ完成版のタスク定義を fakecloud に登録し、`run-task` でタスクとして起動する。

| 項目 | 範囲 |
| --- | --- |
| 対象 | `register-task-definition` と `run-task`（タスクとしての起動） |
| 対象外 | `create-service` などサービスとしての起動、ローリングデプロイ、Auto Scaling、ロードバランサー |
| 対象外 | タスクが止まらないこと（Squid が `essential` のため。検証後は手動で止める） |
| 差 | fakecloud は同じタスクのコンテナで `127.0.0.1` を共有しない。ローカルと CI では Squid の別名で届く |

## ローカルでの実行

前提は [アーキテクチャ](ARCHITECTURE.md) の「実行環境の前提」を参照。初回だけ、検査ツールを固定版で入れる。

```bash
mise install --locked
```

E2E（Docker を使う。CI と同じ内容）:

```bash
npm run test:ci                                                              # 起動、検査、収集、停止を続けて実行する
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000  # 4シナリオ
sh scripts/e2e.sh test:ci error-500-then-200                                 # 1シナリオだけ
```

操作の一覧、固定ポート、CI の内容は [テスト方式](docs/テスト方式.md) を参照。

## シナリオ

| シナリオ | 結果 | 目的 |
| --- | --- | --- |
| `normal` | 200 | 正常系 |
| `error-500-then-200` | 500 の後に 200 | 再試行して成功する |
| `ratelimit-429` | 429 が続く | 再試行を使い切る |
| `slow-5000` | 5 秒の遅延 | タイムアウトの処理 |

期待値、見方、追加の手順は [テスト方式](docs/テスト方式.md) を参照。

## AWS へのデプロイ

CDK でデプロイするか、`render` で作ったタスク定義を手動で登録する。実行は利用者が行い、CI は AWS に接続しない。

```bash
npm ci --prefix cdk
npm run synth --prefix cdk       # CloudFormation を出す
sh scripts/e2e.sh check-cdk      # タスク定義が、ローカルと CI の元と一致するか
cd cdk && npx cdk deploy         # 利用者の AWS 環境で行う
```

手順と注意は [AWS へのデプロイ](docs/AWSへのデプロイ.md) を参照。

## ドキュメント

| 文書 | 内容 |
| --- | --- |
| [アーキテクチャ](ARCHITECTURE.md) | ディレクトリ構成、技術スタック、環境ごとの構成、公開範囲、設計判断（エミュレータの選定）、既知の差 |
| [要件定義](docs/要件定義.md) | 元の要件 |
| [仕様](specs/MVP/spec.md) | 要件の受け入れ条件と、確認結果の記録 |
| [テスト方式](docs/テスト方式.md) | 実行方法、検査の内容、シナリオの追加、AWS での確認（httpbin.org）、CI、後始末 |
| [AWS へのデプロイ](docs/AWSへのデプロイ.md) | CDK と手動の手順 |
| [AGENTS.md](AGENTS.md) | 開発のルール（コミット前の確認など） |

## License

MIT

## Contact

Developed by <satoshi.kaneyasu@serverworks.co.jp>
