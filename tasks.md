# Tasks: ECS サイドカープロキシ E2E テスト基盤

このファイルの16項目は、Issue内で実施する実装サブタスクのチェックリストである。
Spec Kitの実行単位は1 Issueとし、Issue一覧、優先度、順番は
[docs/roadmap.md](./docs/roadmap.md)を正とする。

実装タスク一覧（4 Phase × 3～4 task/Phase）

## Phase 1: Foundation

### T1-1: docker-compose.yml の基本構造実装

**Description**: 3 service（test-client、squid、wiremock）の定義とネットワーク設定

**Acceptance Criteria**:

- [ ] service 定義: image/ports/environment/volumes
- [ ] network driver: bridge 指定
- [ ] health check: 各 service の起動確認
- [ ] docker-compose up で 3 service 同時起動・実行確認

**Effort**: 1h  
**Assignee**: satoshi

---

### T1-2: Squid Dockerfile + squid.conf 実装

**Description**: Squid コンテナの作成、基本ルーティング設定（cache_peer、ACL）

**Acceptance Criteria**:

- [ ] Dockerfile: squid:latest ベース、squid.conf をコピー
- [ ] squid.conf: cache_dir、cache_peer wiremock:8080、acl api_example
- [ ] http_access ルール: allow api_example
- [ ] logs（access.log、cache.log）を stdout へ出力
- [ ] docker-compose で squid build + run 確認

**Effort**: 1.5h  
**Assignee**: satoshi

---

### T1-3: Test Client の簡易実装（curl ベース）

**Description**: HTTP クライアントの最小実装、HTTP_PROXY 環境変数経由でリクエスト送信

**Acceptance Criteria**:

- [ ] Shell script または Node.js スクリプト
- [ ] `HTTP_PROXY=http://squid:3128` 環境変数を読み込み
- [ ] `curl -x $HTTP_PROXY http://api.example.com/api/users` でリクエスト送信
- [ ] レスポンス（status code、body）を出力
- [ ] docker-compose exec test-client で疎通確認

**Effort**: 0.5h  
**Assignee**: satoshi

---

### T1-4: ローカル疎通確認（Colima 環境）

**Description**: docker-compose up → 3 service 起動 → curl 疎通テスト

**Acceptance Criteria**:

- [ ] docker-compose up -d で 3 service 起動
- [ ] docker ps で squid、wiremock、test-client がスタート状態
- [ ] docker-compose logs squid/wiremock で エラーなし
- [ ] docker-compose down で 完全停止（orphans なし）

**Effort**: 0.5h  
**Assignee**: satoshi

---

## Phase 2: WireMock Integration

### T2-1: WireMock mappings JSON ファイル作成（正常系）

**Description**: wiremock-scenarios/mappings/ に HTTP 200 OK の mapping 定義

**Acceptance Criteria**:

- [ ] mappings/normal-case.json: GET /api/users/123 → 200 + {"id":123,"name":"John"}
- [ ] __files/success.json: レスポンス body テンプレート
- [ ] WireMock ログで mapping 読み込み確認
- [ ] `curl -x http://localhost:3128 http://api.example.com/api/users/123` → 200

**Effort**: 0.5h  
**Assignee**: satoshi

---

### T2-2: WireMock mappings JSON ファイル作成（エラー系・遅延系）

**Description**: HTTP 500、503、429、及び delay 設定の mapping

**Acceptance Criteria**:

- [ ] mappings/error-500-case.json: GET /api/fail → 500 + {"error":"Internal Server Error"}
- [ ] mappings/error-503-case.json: GET /api/unavailable → 503 + {"error":"Service Unavailable"}
- [ ] mappings/error-429-case.json: GET /api/ratelimit → 429 + Retry-After header
- [ ] mappings/delay-case.json: GET /api/slow → delay 5000ms + 200 response
- [ ] curl でリクエスト → 各々のステータス・delay 確認

**Effort**: 1h  
**Assignee**: satoshi

---

### T2-3: Squid ルーティング設定の確定テスト

**Description**: Squid logs から cache_peer へのルーティングフロー確認

**Acceptance Criteria**:

- [ ] `curl -x http://localhost:3128 http://api.example.com/api/users` → squid access.log に記録
- [ ] access.log に "TCP_TUNNEL_PARENT_HIT" または peer 関連のログ出現
- [ ] WireMock logs に incoming request 記録
- [ ] docker-compose logs squid | grep -i "wiremock\|peer" で確認

**Effort**: 0.5h  
**Assignee**: satoshi

---

### T2-4: docker-compose.yml に volumes 統合（mappings マウント）

**Description**: WireMock mappings・__files を volume として mount

**Acceptance Criteria**:

- [ ] wiremock service: volumes: - ./wiremock-scenarios:/home/wiremock
- [ ] WireMock start log に "Loaded mappings from ..." 出現
- [ ] mapping 追加後 docker-compose restart wiremock で新規定義反映
- [ ] 既存データ（curl 疎通）は影響なし

**Effort**: 0.25h  
**Assignee**: satoshi

---

## Phase 3: Test Suite & Scenarios

### T3-1: Test Client リトライロジック実装

**Description**: HTTP 500/503 時の自動リトライ（exponential backoff）

**Acceptance Criteria**:

- [ ] test-client/client.js: retry 関数（最大 3 回、初回 1s、次回 2s、3 回目 4s）
- [ ] HTTP 500/503 → リトライ、その他エラー → 即失敗
- [ ] success 時は immediate return
- [ ] 環境変数 MAX_RETRIES で retry 回数制御可能
- [ ] テスト実行時ログで "Retry attempt N/M" 出現

**Effort**: 1h  
**Assignee**: satoshi

---

### T3-2: E2E テストスイート実装（4 シナリオ）

**Description**: Jest/Mocha を使用した E2E テストケース定義

**Acceptance Criteria**:

- [ ] tests/e2e.test.js 実装
- [ ] test_normal_case: GET /api/users/123 → 200 OK
- [ ] test_error_500_retry: GET /api/fail → 500 → リトライ → 200 OK
- [ ] test_timeout_handling: GET /api/slow → 5s delay → timeout 検出
- [ ] test_rate_limit_backoff: GET /api/ratelimit → 429 → backoff → 成功
- [ ] pnpm test で全 4 case 通過

**Effort**: 1.5h  
**Assignee**: satoshi

---

### T3-3: テストフィクスチャ・シナリオ定義

**Description**: テストシナリオごとの WireMock mapping セット管理

**Acceptance Criteria**:

- [ ] tests/fixtures/ に scenario-normal.json、scenario-errors.json など配置
- [ ] setup hook: docker-compose down → up、fixtures copy
- [ ] teardown hook: docker-compose down、cleanup
- [ ] テスト実行時にシナリオ自動切り替え

**Effort**: 0.5h  
**Assignee**: satoshi

---

### T3-4: package.json セットアップ（scripts）

**Description**: pnpm 実行スクリプトの整備

**Acceptance Criteria**:

- [ ] pnpm start: docker-compose up -d
- [ ] pnpm stop: docker-compose down
- [ ] pnpm test: jest/mocha で E2E テスト実行
- [ ] pnpm logs: docker-compose logs tail
- [ ] pnpm clean: 全リソース削除（volumes 含む）

**Effort**: 0.25h  
**Assignee**: satoshi

---

## Phase 4: CI Integration & Docs

### T4-1: GitHub Actions ワークフロー実装（CI 統行）

**Description**: PR/push 時の E2E テスト自動実行

**Acceptance Criteria**:

- [ ] .github/workflows/e2e-test.yml: ubuntu-latest 上での実行
- [ ] docker-compose up -d → pnpm test → docker-compose down
- [ ] 実行時間: < 3 分
- [ ] failure on test failure、success on all pass
- [ ] logs artifact 保存（troubleshooting 用）

**Effort**: 0.75h  
**Assignee**: satoshi

---

### T4-2: docs/setup-guide.md 作成

**Description**: ローカル・CI セットアップ手順ドキュメント

**Acceptance Criteria**:

- [ ] Prerequisites: Docker/Docker Compose、Node.js、curl
- [ ] ローカル: colima status → export DOCKER_HOST → docker-compose up
- [ ] CI: GitHub Actions runner（ubuntu-latest）での実行手順
- [ ] トラブルシューティング: よくあるエラーと対策
- [ ] リンク切れなし、markdownlint 0 件

**Effort**: 0.75h  
**Assignee**: satoshi

---

### T4-3: README.md 作成

**Description**: プロジェクト全体の使用方法・概要

**Acceptance Criteria**:

- [ ] Project Overview（背景・目的）
- [ ] Quick Start: pnpm start → pnpm test
- [ ] Architecture Diagram（テキスト形式）
- [ ] Directory Structure
- [ ] Testing Scenarios（4 case の説明）
- [ ] Troubleshooting リンク
- [ ] License

**Effort**: 0.5h  
**Assignee**: satoshi

---

### T4-4: Smoke Test & Integration Check

**Description**: ローカル + CI 環境での最終動作確認

**Acceptance Criteria**:

- [ ] ローカル（Colima）: pnpm test 全通過
- [ ] CI PR: .github/workflows/e2e-test.yml 成功
- [ ] docker-compose logs で エラーなし（warnings は許容）
- [ ] cleanup 完全（orphan volumes、port binding 残存なし）
- [ ] 本番 ECS デプロイ前のチェックリスト作成

**Effort**: 0.5h  
**Assignee**: satoshi

---

## Summary

- **Total Tasks**: 16
- **Total Effort**: 約 10～12 工時
- **Critical Path**: T1-1 → T1-2 → T2-1 → T3-1 → T3-2 → T4-1
- **Parallelizable**: T1-3 & T2-1、T2-2 & T3-1、T4-2 & T4-3

## Dependencies

```text
T1-1 ──→ T1-2 ──→ T1-3 ──→ T1-4
              ↓
         T2-1, T2-2
              ↓
         T2-3, T2-4
              ↓
         T3-1, T3-2, T3-3
              ↓
         T3-4
              ↓
         T4-1, T4-2, T4-3
              ↓
         T4-4
```
