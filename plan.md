# Plan: ECS サイドカープロキシ E2E テスト基盤

**Status**: Design Phase  
**Date**: 2026-11-01

## 1. Clarifications

### 1.1 HTTPS サポート

**決定**: 初期実装では HTTP のみ。HTTPS は将来の拡張タスク。  
**理由**: Squid の SSL Bump 設定は MITM 証明書生成が必要で複雑化。
HTTP での動作確認後に段階的に拡張。

### 1.2 Squid キャッシュ戦略

**決定**: キャッシュを有効化（テスト再現性のため cache_dir は tmpfs）。  
**理由**: 本番 ECS でもプロキシキャッシュが稼働するため、再現性維持。
テスト環境での容量制限（1GB）と明示的なキャッシュクリア。

### 1.3 WireMock スタブ形式

**決定**: JSON 形式統一（WireMock 標準）。  
**理由**: YAML より JSON が REST API 互換性に優れる。
GitHub Actions での動的マッピング追加が容易。

### 1.4 Test Client リトライ設定

**決定**: クライアント側で実装（環境変数で設定）。  
**理由**: テストケースごとに異なるリトライ戦略を検証する必要があるため、
設定を外部化してコード化。

### 1.5 CI での Container Registry

**決定**: Docker Hub public イメージのみ使用（squid、wiremock/wiremock）。  
**理由**: GitHub Actions 内で ECR ログイン不要、セキュリティリスク最小化。
Test Client のビルドイメージのみ Dockerfile で管理。

## 2. Technical Architecture

### 2.1 ディレクトリ構成

```text
squid-wiremock-sidecar/
├── docker-compose.yml
├── .dockerignore
├── Dockerfile.test-client
│
├── squid-config/
│   ├── squid.conf          # Squid ルーティング・キャッシュ設定
│   └── whitelist.txt       # 対象ドメイン ACL リスト
│
├── wiremock-scenarios/
│   ├── __files/            # Mock response body
│   │   ├── success.json
│   │   ├── error-500.json
│   │   └── error-503.json
│   └── mappings/           # WireMock 定義ファイル（JSON）
│       ├── normal-case.json
│       ├── error-500-case.json
│       └── delay-case.json
│
├── test-client/
│   ├── package.json        # Node.js クライアント
│   └── client.js
│
├── tests/
│   ├── e2e.test.js         # E2E テストスイート
│   └── fixtures/           # テストデータ・シナリオ定義
│
├── docs/
│   ├── requirements.md
│   ├── setup-guide.md      # ローカル・CI セットアップ
│   └── troubleshooting.md
│
├── .github/workflows/
│   └── e2e-test.yml        # CI 実行定義
│
└── README.md
```

### 2.2 Service Dependencies & Port Mapping

| Service | Port | Image | Environment |
|---------|------|-------|-------------|
| test-client | - | Dockerfile | `HTTP_PROXY=http://squid:3128` |
| squid | 3128 | squid:latest | - |
| wiremock | 8080 | wiremock/wiremock | - |

### 2.3 Network

- **Driver**: bridge（デフォルト）
- **Isolation**: コンテナ同士は service name 解決で通信（127.0.0.1 不要）
- **External Access**: ローカル開発時は localhost:3128（squid）, localhost:8080（wiremock）

### 2.4 Squid Configuration Strategy

```conf
# squid.conf の主要部分

# Cache 設定
cache_dir ufs /var/spool/squid 1000 16 256  # 1GB, tmpfs 環境
cache_mem 256 MB

# Peer（WireMock） 登録
cache_peer wiremock parent 8080 0 no-query

# ACL 定義（対象ドメイン）
acl api_example dstdomain api.example.com
acl api_staging dstdomain api-staging.example.com

# ルーティングルール
http_access allow api_example
cache_peer_access wiremock allow api_example
cache_peer_access wiremock deny all

# ログ出力
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
```

### 2.5 WireMock Mapping Template

```json
{
  "request": {
    "method": "GET",
    "urlPath": "/api/users/123"
  },
  "response": {
    "status": 200,
    "body": "{\"id\": 123, \"name\": \"John\"}",
    "headers": {
      "Content-Type": "application/json"
    }
  }
}
```

### 2.6 E2E テストシナリオ

| シナリオ | HTTP Status | Delay | リトライ検証 | テストコード |
|----------|-------------|-------|-----------|-----------|
| Normal Success | 200 | 0ms | 成功 | tests/e2e.test.js: test_normal_case |
| 500 Error with Retry | 500 | 0ms | リトライ 3 回後成功 | tests/e2e.test.js: test_error_500_retry |
| Timeout Handling | 200 | 5000ms | タイムアウト判定 → fallback | tests/e2e.test.js: test_timeout_fallback |
| Rate Limit (429) | 429 | 0ms | バックオフリトライ | tests/e2e.test.js: test_rate_limit_backoff |

## 3. Implementation Strategy

### Phase 1: Foundation (docker-compose + Squid)

1. docker-compose.yml: 3 service 基本構造
2. Squid Dockerfile + squid.conf（基本ルーティング）
3. Test Client: curl ベースの簡易実装（node.js 不要）
4. 疎通確認: `curl -x http://localhost:3128 http://api.example.com`

### Phase 2: WireMock Integration

1. wiremock-scenarios/mappings/ へ JSON スタブ定義
2. docker-compose.yml で volumes マウント
3. WireMock 管理 API（POST /__admin/mappings）テスト
4. `curl -x http://localhost:3128 http://api.example.com/api/users` → 200 OK

### Phase 3: Test Suite & Scenarios

1. tests/e2e.test.js 実装（複数シナリオ）
2. test-client/client.js: リトライロジック実装
3. fixtures/ で異なる WireMock mapping セット管理
4. pnpm test で全シナリオ実行

### Phase 4: CI Integration & Docs

1. .github/workflows/e2e-test.yml: GitHub Actions 定義
2. docs/setup-guide.md: ローカル・CI セットアップ
3. README.md: 使用方法・トラブルシューティング
4. smoke test: pr-branch で docker-compose up/down 検証

## 4. Verification Boundaries

- **ユニットテスト**: 各コンポーネント（Squid 設定、WireMock mapping）の独立検証
- **インテグレーションテスト**: docker-compose での 3 service 疎通
- **E2E テスト**: 実際のリトライ・フェイルオーバー挙動の検証

## 5. Key Risks & Mitigations

| リスク | 影響 | 対策 |
|--------|------|------|
| Squid ルーティング未設定でインターネットへ出てしまう | テスト不正確 | cache_peer_access で明示的ルーティング、logs 確認 |
| WireMock の mappings 読み込み失敗 | Mock Server 起動失敗 | volumes マウント確認、docker logs |
| Docker Bridge ネットワークで service name 解決失敗 | コンテナ間通信不可 | docker network inspect、DNS テスト |
| CI での container イメージ pull timeout | ビルド失敗 | プライベートレジストリ不使用、retries 設定 |

## 6. Success Metrics

- [ ] ローカル docker-compose up で全 3 service 起動・リヘルスチェック成功
- [ ] Test Client → Squid → WireMock の通信フロー確認（tcpdump or squid logs）
- [ ] E2E テストスイート全通過（4 シナリオ × 正常系・異常系）
- [ ] GitHub Actions での CI 実行成功（< 3 分）
- [ ] docs/setup-guide.md でローカル・CI セットアップ完結

## 7. Timeline

| Phase | Week | Deliverables |
|-------|------|--------------|
| 1 | W1 | docker-compose.yml、Squid 基本設定 |
| 2 | W2 | WireMock mappings、疎通確認 |
| 3 | W3 | E2E テストスイート、Test Client リトライロジック |
| 4 | W4 | CI 統合、ドキュメント完成、smoke test |

## 8. Out of Scope

- HTTPS/SSL Bump 対応（Phase 2 以降）
- Squid ユーザー認証・キャッシュ詳細チューニング
- WireMock の advanced features（Scenarios、State）
- ECS Fargate への実際のデプロイ（本番移行時）
