# Spec: ECS サイドカープロキシ E2E テスト基盤

**Status**: Specification Phase  
**Owner**: satoshi  
**Date**: 2026-11-01

## 1. What

ECS のサイドカー（Squid プロキシ）構成をローカル環境・CI 環境で完全にエミュレートし、
外部 API のエラー応答やネットワーク遅延を含む E2E テストを実施できるサンドボックス環境を構築。

Test Client（メインアプリ）→ Squid Proxy（localhost:3128）→ WireMock（Mock Server）
の 3 層構成を Docker Compose で一括管理。

## 2. Why

- HTTP クライアントのリトライ・フェイルオーバー制御を検証するには、
  相手先からの 503 エラーやタイムアウトを確実に発生させる必要がある
- 本番 ECS では awsvpc ネットワークモード下でタスク内コンテナが localhost を共有するため、
  同じモデルをローカルでエミュレートして再現性を確保する
- 外部 API に依存せず、完全にネットワークが閉じた環境での テスト実行が必須

## 3. Success Criteria

- [ ] docker-compose up で 3 コンポーネント（Client、Proxy、Mock Server）が同時起動
- [ ] Test Client が `HTTP_PROXY=http://localhost:3128` 経由で Mock Server と通信
- [ ] WireMock で HTTP 500、503、429 を返却できる
- [ ] WireMock で response delay（100ms～5s）を設定できる
- [ ] Squid ルーティングで特定ドメイン（例: api.example.com）の通信が Mock Server に転送される
- [ ] ローカル環境（Colima）と CI（GitHub Actions）の両環境で動作確認可能
- [ ] 再現可能なテストシナリオが最低 3 パターン（正常系 1 件、エラー系 2 件）実装可能
- [ ] 環境破棄（docker-compose down）後にポート競合・ストレージリーク が残らない

## 4. Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                 Docker Network (bridge)                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐      ┌──────────────┐                   │
│  │ Test Client  │ ---→ │ Squid Proxy  │                   │
│  │ (localhost)  │      │ (:3128)      │                   │
│  └──────────────┘      └──────────────┘                   │
│                               │                            │
│                               │ (Cache-peer)              │
│                               ▼                            │
│                        ┌──────────────┐                   │
│                        │  WireMock    │                   │
│                        │  (:8080)     │                   │
│                        └──────────────┘                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 5. Design Decisions

### 5.1 Network Mode

- **Docker Compose**: service ごとにネットワーク内の独立コンテナとして稼働
  - localhost 通信はコンテナ内に閉じているため、
    環境変数で明示的にプロキシアドレスを指定（`http://squid:3128`）
  - ECS awsvpc モードと異なり、サービス名解決で通信

### 5.2 Squid 設定

- **cache_peer**: Mock Server（wiremock:8080）をピアとして登録
- **acl**: 特定ドメイン（api.example.com 等）のリクエストのみ対象化
- **http_access**: 対象 ACL に合致したリクエストを cache_peer へ転送
- **ssl_bump**: HTTPS 対応時のプロキシ処理（初期は HTTP のみ）

### 5.3 WireMock Mappings

- JSON 形式で request/response を定義（__files/ で管理）
- 管理 API（POST /__admin/mappings）で動的追加・削除可能
- Status Code、Body、Delay、Headers が設定可能

### 5.4 Test Client

- Node.js or Python ベースの簡易クライアント
- HTTP_PROXY 環境変数でプロキシを指定
- curl / axios / requests 等で HTTP リクエストを送信

## 6. Implementation Phases

### Phase 1: Foundation

- docker-compose.yml の基本構造（3 サービス）定義
- Squid コンテナのビルド（Dockerfile）
- WireMock の既存イメージ利用

### Phase 2: Routing & Proxy Config

- squid.conf の cache_peer/acl ルール実装
- Test Client から Squid 経由でのリクエストフロー検証

### Phase 3: Mock Scenarios

- WireMock mappings（正常系・エラー系・遅延系）定義
- E2E テストスイート実装

### Phase 4: Integration & Polish

- ローカル環境（Colima）での動作確認
- CI 環境での実行（GitHub Actions）
- セットアップ・トラブルシューティングガイド作成

## 7. Dependencies & Constraints

| 項目 | 内容 |
|------|------|
| Docker | 20.10+ （Compose v2）|
| Squid | OSS squid:latest または alpine ベースイメージ |
| WireMock | oficialimage wiremock/wiremock:latest |
| Test Client | curl / Node.js / Python 環境 |
| ネットワーク | Docker Bridge ネットワーク、外部通信なし |

## 8. Open Questions

- [ ] HTTPS トラフィックにも対応するか？（初期は HTTP のみ）
- [ ] Squid のキャッシュを有効化するか、それとも全リクエスト透過か？
- [ ] WireMock のスタブ定義を YAML か JSON か統一するか？
- [ ] Test Client のリトライ・タイムアウト設定をどこで管理するか？
- [ ] CI 環境での実行時の container registry（ECR or public）をどうするか？

## 9. Acceptance Criteria

- [x] 要件定義書（requirements.md）作成
- [ ] spec.md の clarify フェーズで未決事項を解消
- [ ] plan.md で技術方針・実装方針を確定
- [ ] tasks.md で実装タスク 10～15 件に分解
- [ ] ローカル環境での docker-compose up/down で E2E テスト実行可能
- [ ] CI に統合された状態での smoke テスト成功
