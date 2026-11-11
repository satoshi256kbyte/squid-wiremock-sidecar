# Squid WireMock Sidecar E2E Test Framework

ECS のサイドカー（Squid プロキシ）構成をローカルと CI でエミュレートし、
外部 API のエラー応答や遅延を含む E2E テストを実施する検証用の環境。

```text
Test Client → Squid Proxy (127.0.0.1:3128) → WireMock (127.0.0.1:8080)
```

本番 ECS では awsvpc ネットワークモードでタスク内のコンテナが localhost を共有する。
同じ構成を、pause コンテナと共有する namespace で再現し、クライアントのリトライやタイムアウトを確かめる。

## 使い方

```bash
npm run start      # WireMock、pause、Squid を起動する
npm run test       # Client を実行して検査する
npm run logs       # コンテナのログを表示する
npm run stop       # 起動したコンテナとネットワークを削除する
npm run clean      # stop に加えて生成物と収集ログを削除する
npm run test:ci    # start、test、collect、stop を続けて実行する
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000  # 4シナリオ（CI と同じ）
```

固定ポート（8080、3128）は入口のロックで1つの実行だけに限る。並列に実行しない。

## 構成

| 場所 | 役割 |
| --- | --- |
| `squid-config/` | Squid の設定と許可ドメイン |
| `wiremock-scenarios/` | WireMock の応答定義（JSON） |
| `test-client/` | リトライ付きの HTTP クライアント |
| `ecs/` | ECS タスク定義のテンプレートと Squid のイメージ |
| `scripts/` | 入口（`e2e.sh`）、起動と停止、4シナリオの実行（`e2e-scenarios.sh`） |
| `.github/workflows/e2e-test.yml` | CI（shellcheck、actionlint、gitleaks、test:ci） |

## シナリオ

| シナリオ | 結果 | 目的 |
| --- | --- | --- |
| `normal` | 200 | 正常系 |
| `error-500-then-200` | 500 の後に 200 | 再試行して成功する |
| `ratelimit-429` | 429 が続く | 再試行を使い切る |
| `slow-5000` | 5 秒の遅延 | タイムアウトの処理 |

詳しくは [E2Eテスト](docs/E2Eテスト.md)、[シナリオの隔離と追加](docs/シナリオ隔離.md)、
[ポート公開範囲](docs/ポート公開範囲.md)、[ローカル実行とCI](docs/ローカル実行とCI.md) を参照。

## 前提

- Docker（`docker run` で直接起動する。Compose は使わない）
- Node.js 22+（`npm run` の入口として使う）
- curl
- mise 2026.11.3 以上。`mise install --locked` で shellcheck、actionlint、gitleaks、jq を固定版で導入する

## License

MIT

## Contact

Developed by <satoshi.kaneyasu@serverworks.co.jp>
