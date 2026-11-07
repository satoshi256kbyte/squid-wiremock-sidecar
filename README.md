# Squid WireMock Sidecar E2E Test Framework

ECS のサイドカー（Squid プロキシ）構成をローカル環境・CI 環境で完全にエミュレートし、
外部 API のエラー応答やネットワーク遅延を含む E2E テストを実施するサンドボックス環境。

## Overview

**3 層構成:**

```text
Test Client → Squid Proxy (localhost:3128) → WireMock (Mock Server)
```

本番 ECS では awsvpc ネットワークモード下でタスク内コンテナが localhost を共有するため、
同じモデルをローカルでエミュレートして、HTTP クライアントのリトライ・フェイルオーバー制御を検証します。

## Key Features

- ✅ ECS サイドカー構成の完全再現（ECS タスク定義と、同じ namespace を共有するコンテナ）
- ✅ 閉域ルーティング（Squid cache_peer 経由）
- ✅ 異常系シミュレーション（HTTP 500/503/429、response delay）
- ✅ 振る舞いのコード化（JSON mapping）
- ✅ ローカル環境・CI 環境での完結実行

## Project Status

**Phase**: Planning & Specification ✅  
**Implementation**: Ready to start

詳細な実装計画は以下のドキュメントをご覧ください：

- [requirements.md](./docs/requirements.md) - 要件定義書
- [spec.md](./spec.md) - 仕様書（success criteria）
- [plan.md](./plan.md) - 技術設計・実装方針
- [roadmap.md](./docs/roadmap.md) - Issue単位の完成ロードマップ（11 Issue）
- [tasks.md](./tasks.md) - Issue内で使う実装サブタスク一覧
- [analyze.md](./analyze.md) - 全体設計の整合性検査

## Quick Start

```bash
# 1. リポジトリを clone
git clone https://github.com/yourusername/squid-wiremock-sidecar.git
cd squid-wiremock-sidecar

# 2. 環境構築と E2E テスト実行（npm run。手順は docs/ローカル実行とCI.md）
npm run start

# 3. E2E テスト実行
npm run test

# 4. 環境破棄
npm run stop
```

## System Components

### Test Client

- HTTP クライアント（リトライロジック付き）
- HTTP_PROXY 環境変数経由でプロキシを指定
- テスト用シナリオ実行

### Squid Proxy

- フォワードプロキシ
- pause コンテナと共有する namespace の中で 127.0.0.1:3128 をリッスン（ホストへは公開しない）
- cache_peer で特定ドメインの通信を WireMock へ転送

### WireMock Mock Server

- REST API mock server（127.0.0.1:8080）
- JSON で request/response をコード化
- HTTP status、delay、headers をカスタマイズ可能

ホストからの公開範囲と、別マシンから使う場合の手段は [ポート公開範囲](docs/ポート公開範囲.md) を参照。

## Testing Scenarios

| Scenario | Status Code | Delay | Retry | Purpose |
|----------|------------|-------|-------|---------|
| Normal Success | 200 | 0ms | N/A | 正常系検証 |
| Error 500 with Retry | 500→200 | 0ms | ✓ 3 times | リトライロジック検証 |
| Timeout Handling | 200 | 5000ms | ✓ timeout | タイムアウト処理検証 |
| Rate Limit Backoff | 429 | 0ms | ✓ backoff | 速度制限対応検証 |

シナリオの名前による選択、リセット、追加手順、並列実行の禁止は [シナリオの隔離と追加](docs/シナリオ隔離.md) を参照。

E2E スイートの実行方法、4シナリオの期待値、失敗時の見方は [E2Eテスト](docs/E2Eテスト.md) を参照。

## Directory Structure

```text
.
├── README.md
├── spec.md                    # 仕様書
├── plan.md                    # 技術設計
├── tasks.md                   # 実装タスク
├── analyze.md                 # 整合性検査
├── ecs/                       # ECS タスク定義のテンプレートと Squid 設定
├── scripts/                   # npm run の入口（e2e.sh）と品質ゲート
├── .gitignore
│
├── docs/
│   ├── requirements.md        # 要件定義書
│   ├── roadmap.md             # Issue単位の完成ロードマップ
│   ├── setup-guide.md         # セットアップ手順 (実装後)
│   └── troubleshooting.md     # トラブルシューティング (実装後)
│
├── squid-config/              # (実装後)
│   ├── squid.conf
│   └── whitelist.txt
│
├── wiremock-scenarios/        # (実装後)
│   ├── __files/
│   │   ├── success.json
│   │   └── error-*.json
│   └── mappings/
│       ├── normal-case.json
│       ├── error-500-case.json
│       └── delay-case.json
│
├── test-client/               # (実装後)
│   ├── package.json
│   └── client.js
│
├── tests/                     # (実装後)
│   ├── e2e.test.js
│   └── fixtures/
│
└── .github/workflows/         # (実装後)
    └── e2e-test.yml
```

## Prerequisites

- Docker（`docker run` で直接起動する。Compose は使わない）
- Node.js 22+（`npm run` の入口と Markdown 検査）
- curl（動作確認時）

## Implementation Roadmap

実装は、1Issueを1回のSpec Kit実行単位として、優先度と依存関係の順に進めます。

| Phase | Issue | 完了条件 |
|-------|-------|----------|
| Phase 1: 閉域通信の基盤 | M01〜M05 | Client → Squid → WireMockを検証できる |
| Phase 2: 耐障害性とE2E | M06〜M08 | 4つの代表シナリオが通る |
| Phase 3: CI、文書、受入 | M09〜M11 | ローカルとCIの受入条件を満たす |

順番、優先度、各IssueのAcceptance Criteriaは
[docs/roadmap.md](./docs/roadmap.md)を参照。

## Development Workflow

現在の入口は、次の「新基盤の実行（npm run）」です。

### 新基盤の実行（npm run）

ローカルの実行手順、検査の層、CI の見方は [ローカル実行とCI](docs/ローカル実行とCI.md) を参照する。

```bash
npm run start      # WireMock、pause、Squid を起動する
npm run test       # Client を実行して検査する
npm run logs       # コンテナのログを表示する
npm run stop       # 起動したコンテナとネットワークを削除する
npm run clean      # stop に加えて生成物と収集ログを削除する
npm run test:ci    # start、test、collect、stop を続けて実行する
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000  # M08 の4シナリオ（CI と同じ）
```

固定ポート（8080、3128、4566）は、入口のロックで1つの実行だけに限る（既定は `/tmp/swsc-e2e-ports.lock`）。
並列に実行しない。ロックの扱いは [ローカル実行とCI](docs/ローカル実行とCI.md) を参照する。

## CI/CD Integration

GitHub Actions workflow（`.github/workflows/e2e-test.yml`）により、
PR/push 時に自動的に E2E テストを実行する。実行の順序と見方は
[ローカル実行とCI](docs/ローカル実行とCI.md) を参照する。

実行時間の目標: < 3 分（CI の初回実行で実測し、文書に反映する）

## Troubleshooting

よくある問題と対策は [docs/troubleshooting.md](./docs/troubleshooting.md) を参照（実装後）。

## License

MIT

## Contact

Developed by <satoshi.kaneyasu@serverworks.co.jp>
