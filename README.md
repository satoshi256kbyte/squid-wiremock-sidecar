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

- ✅ ECS サイドカー構成の完全再現（Docker Compose）
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

# 2. Docker Compose で環境構築（実装後）
docker-compose up -d

# 3. E2E テスト実行（M09 実装後に提供予定）
pnpm test

# 4. 環境破棄
docker-compose down
```

## System Components

### Test Client

- HTTP クライアント（リトライロジック付き）
- HTTP_PROXY 環境変数経由でプロキシを指定
- テスト用シナリオ実行

### Squid Proxy

- フォワードプロキシ
- localhost:3128 でリッスン
- cache_peer で特定ドメインの通信を WireMock へ転送

### WireMock Mock Server

- REST API mock server（localhost:8080）
- JSON で request/response をコード化
- HTTP status、delay、headers をカスタマイズ可能

## Testing Scenarios

| Scenario | Status Code | Delay | Retry | Purpose |
|----------|------------|-------|-------|---------|
| Normal Success | 200 | 0ms | N/A | 正常系検証 |
| Error 500 with Retry | 500→200 | 0ms | ✓ 3 times | リトライロジック検証 |
| Timeout Handling | 200 | 5000ms | ✓ timeout | タイムアウト処理検証 |
| Rate Limit Backoff | 429 | 0ms | ✓ backoff | 速度制限対応検証 |

シナリオの名前による選択、リセット、追加手順、並列実行の禁止は [シナリオの隔離と追加](docs/シナリオ隔離.md) を参照。

## Directory Structure

```text
.
├── README.md
├── spec.md                    # 仕様書
├── plan.md                    # 技術設計
├── tasks.md                   # 実装タスク
├── analyze.md                 # 整合性検査
├── docker-compose.yml         # (実装後)
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

- Docker & Docker Compose (v2.0+)
- Node.js 18+ （テスト実行時）
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

以下の pnpm 入口は M09 実装後に提供予定であり、現時点では利用できません。

```bash
# ローカルテスト（Colima 環境）
export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock
pnpm start           # docker-compose up -d
pnpm test            # E2E テスト実行
pnpm logs            # ログ確認
pnpm stop            # docker-compose down
pnpm clean           # リソース完全削除
```

## CI/CD Integration

M09 実装後は、GitHub Actions workflow（`.github/workflows/e2e-test.yml`）により、
PR/push 時に自動的に E2E テストを実行する予定です。

実行時間の目標: < 3 分

## Troubleshooting

よくある問題と対策は [docs/troubleshooting.md](./docs/troubleshooting.md) を参照（実装後）。

## License

MIT

## Contact

Developed by <satoshi.kaneyasu@serverworks.co.jp>
