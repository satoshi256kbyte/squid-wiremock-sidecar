# M02 clarify記録

## 実施内容

M02のIssue、M01のCompose契約、全体Planを照合し、Squidのルーティング方式と
検証方法を確定した。

## 確定事項

| 論点 | 決定 | 理由 |
|------|------|------|
| 対象プロトコル | HTTPのみ | HTTPS SSL Bumpは初期スコープ外のため |
| 対象ドメイン | `api.example.com`と`api-staging.example.com` | 全体Planのallowlist方針に合わせるため |
| allowlist管理 | `squid-config/whitelist.txt` | 設定と対象ドメインを分離し、追加を容易にするため |
| WireMock転送 | `cache_peer wiremock parent 8080 0 no-query` | Composeサービス名で閉域接続するため |
| 直接接続防止 | `never_direct allow`と`http_access deny all` | WireMock以外への経路を許可しないため |
| キャッシュ | `/var/spool/squid`のtmpfs | テスト間の永続化とストレージリークを防ぐため |
| ログ | `/var/log/squid`のtmpfs | proxyユーザーで書き込み可能にし、停止時に破棄するため |
| 統合検証 | WireMock管理APIで一時mappingを登録し、host curlで検証 | M03のシナリオ定義と責務を分離するため |

## 対象外

WireMockの永続mapping、Test Clientの実装、リトライ、E2Eテストスイート、CI、HTTPSは
後続Issueで扱う。
