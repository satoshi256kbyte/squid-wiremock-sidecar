# M02 Squidサイドカー閉域ルーティングの実装計画

## 1. 実装方針

M01の最小Squid設定を、allowlistとWireMock parent peerを使う閉域設定へ拡張する。
設定ファイルの変更だけで対象ドメインを追加できるようにする。

## 2. 変更ファイル

| パス | 変更内容 |
|------|----------|
| `squid-config/squid.conf` | ACL、cache_peer、転送制御、tmpfsログ出力を追加 |
| `squid-config/whitelist.txt` | 許可対象ドメインを定義 |
| `docker-compose.yml` | allowlistのmountとSquidのtmpfsを追加 |
| `tests/m02-routing-smoke.sh` | WireMock一時mappingとproxy経路を検証 |

## 3. Squid設定

- `api_domains` ACLは`whitelist.txt`を読む
- `wiremock`をparent peerとして登録する
- `cache_peer_access`でallowlist対象だけをpeerへ渡す
- `never_direct`でallowlist対象の直接接続を禁止する
- `http_access`でallowlist対象以外を拒否する
- access logとcache logは`/var/log/squid`へ書く
- cache directoryとログディレクトリはComposeのtmpfsにする

## 4. 検証手順

1. Composeを起動する
2. WireMock管理APIへ一時mappingを登録する
3. Squidの3128番ポートへ`api.example.com`宛てにHTTPリクエストを送る
4. レスポンス本文とWireMockの受信履歴を確認する
5. Squidのアクセスログに対象リクエストがあることを確認する
6. allowlist外のドメインが拒否されることを確認する
7. Composeを`down --remove-orphans`で停止する

## 5. 対象外

- HTTPSのCONNECTとSSL Bump
- WireMockのGit管理mapping
- Test Clientコンテナからの実リクエスト
- リトライやタイムアウト
