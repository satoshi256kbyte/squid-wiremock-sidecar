# M02 Squidサイドカー閉域ルーティングのタスク

## T01: allowlistとSquid設定

- `squid-config/whitelist.txt`を作成する
- `cache_peer`と対象ドメインACLを追加する
- `http_access`、`cache_peer_access`、`never_direct`を設定する
- Squidのログとキャッシュをtmpfsへ出力する

## T02: Composeマウント

- allowlistをSquidコンテナへread-onlyでmountする
- `/var/log/squid`と`/var/spool/squid`をtmpfsにする
- M01のサービス名、ポート、healthcheckを維持する

## T03: 統合スモークテスト

- WireMock管理APIへ一時mappingを登録する
- host curlからSquid経由で対象ドメインへアクセスする
- 本文、WireMock受信履歴、Squidアクセスログを確認する
- allowlist外のリクエストが拒否されることを確認する
- 終了処理でコンテナとネットワークを回収する

## T04: レビューと品質ゲート

- `docker-compose config`を実行する
- M02のAcceptance Criteriaと差分を照合する
- HTTPS、リトライ、永続mappingが混入していないことを確認する
- 検証後に日本語コミットを作成する

## 完了条件

- [ ] T01からT04を完了している
- [ ] `spec.md`、`clarify.md`、`plan.md`、`tasks.md`、`analyze.md`が揃っている
- [ ] 対象ドメインがWireMockへ転送される
- [ ] 対象外ドメインが拒否される
- [ ] ログと受信履歴で経路を確認できる
