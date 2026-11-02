# M01 Compose実行基盤の仕様

## 1. 目的

Docker ComposeでTest Client、Squid、WireMockを同時に起動し、後続Issueが利用する
サービス名、ネットワーク、ポート、環境変数、ヘルスチェックの契約を固定する。

## 2. 対象範囲

- `test-client`、`squid`、`wiremock`の3サービス
- bridgeネットワーク
- サービス間の名前解決
- 後続Issueが利用するポートと環境変数
- 各サービスのプロセス生存確認
- `depends_on`による起動順序
- `docker-compose down --remove-orphans`による終了契約

## 3. 機能要件

| ID | 要件 |
|----|------|
| FR-001 | 3サービスを一つのComposeプロジェクトとして定義する |
| FR-002 | 3サービスを同一のbridgeネットワークへ接続する |
| FR-003 | Squidを3128番ポート、WireMockを8080番ポートで公開する |
| FR-004 | Test ClientからSquidへ接続するHTTP_PROXY契約を定義する |
| FR-005 | 全サービスにhealthcheckを定義する |
| FR-006 | Test ClientがSquidとWireMockのhealthy後に起動する |
| FR-007 | Compose設定を構文検証できる状態にする |
| FR-008 | Compose停止時に孤児コンテナを残さない手順を定義する |

## 4. 非機能要件

| ID | 要件 |
|----|------|
| NFR-001 | M02以降で設定を差し替えられる最小構成にする |
| NFR-002 | Colima利用時に既存のDocker設定や認証情報を変更しない |
| NFR-003 | 既存のユーザー変更を上書きしない |
| NFR-004 | 設定とSpec Kit成果物をGitでレビュー可能にする |

## 5. clarifyで確定した事項

詳細は`clarify.md`に記録する。

- Docker Composeのコマンド表記は、この環境のルールに従い`docker-compose`を使用する
- ローカルの公開ポートはSquidが3128、WireMockが8080とする
- Dockerネットワーク名はComposeのプロジェクトスコープに任せ、論理名は`sidecar`とする
- M01のhealthcheckはプロセス生存確認に限定し、HTTP経路の確認はM05で実施する
- SquidのACL、cache_peer、WireMockマッピング、リトライ処理はM01の対象外とする
- Test Clientは後続実装の土台となる最小の常駐コンテナとする
- イメージは既存計画に合わせ、Squidは`ubuntu/squid:latest`、WireMockは
  `wiremock/wiremock:3.13.1`を使用する

## 6. 完了条件

- [ ] M01のSpec Kit成果物が作成されている
- [ ] `docker-compose.yml`が3サービスとbridgeネットワークを定義している
- [ ] 全サービスにhealthcheckがある
- [ ] Compose設定の構文検証が成功する
- [ ] 起動、状態確認、停止の検証手順がある
- [ ] M02以降の対象外が明確である
