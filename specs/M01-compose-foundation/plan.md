# M01 Compose実行基盤の実装計画

## 1. 実装方針

Composeの責務をサービスの起動契約に限定する。
Test Clientは常駐プレースホルダー、Squidは後続設定を受け入れる最小設定、
WireMockは標準イメージと空のマッピング領域を使用する。

## 2. ファイル構成

| パス | 役割 |
|------|------|
| `docker-compose.yml` | 3サービス、ネットワーク、ポート、healthcheck、依存関係 |
| `Dockerfile.test-client` | Test Clientの最小常駐イメージ |
| `test-client/entrypoint.sh` | コンテナを常駐させるエントリーポイント |
| `squid-config/squid.conf` | M02で拡張するSquidの最小設定 |
| `wiremock-scenarios/mappings/.gitkeep` | WireMockマッピング領域のプレースホルダー |
| `wiremock-scenarios/__files/.gitkeep` | WireMock本文ファイル領域のプレースホルダー |
| `.dockerignore` | Test Clientのビルドコンテキスト除外 |

## 3. Compose契約

- `test-client`は`HTTP_PROXY=http://squid:3128`を持つ
- `test-client`は`TEST_API_BASE_URL=http://api.example.com`を持つ
- `squid`はホストの3128番ポートへ公開する
- `wiremock`はホストの8080番ポートへ公開する
- 3サービスは`sidecar`という論理ネットワークへ接続する
- Test ClientはSquidとWireMockがhealthyになった後に起動する
- healthcheckはPID 1の生存確認とする

## 4. 検証境界

### 構文検証

`docker-compose config`でComposeファイルを解釈できることを確認する。

### 起動検証

Colimaが稼働している場合はColimaのDockerソケットを指定し、
空のセッション用Docker設定を使って3サービスを起動する。
全サービスがhealthyになった後、状態を取得する。

### 終了検証

`docker-compose down --remove-orphans`を実行し、M01のComposeプロジェクトに
残存コンテナがないことを確認する。

## 5. 対象外

- Squidの外部ドメインACLとcache_peer転送
- WireMockのHTTPマッピング
- Test ClientのHTTPリクエストとリトライ
- E2Eテストスイート
- GitHub Actions
