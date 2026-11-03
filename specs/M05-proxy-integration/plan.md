# M05実装計画

## 1. 実装方針

`tests/m05-proxy-integration.sh`がComposeの起動、readiness確認、経路検証、
外部通信遮断確認、診断出力、cleanupを一つのライフサイクルとして管理する。

## 2. 変更ファイル

| パス | 変更内容 |
| --- | --- |
| `tests/m05-proxy-integration.sh` | 3サービス統合検証と失敗時ログ出力 |
| `specs/M05-proxy-integration/` | M05のSpec Kit成果物 |

既存のCompose、Squid、WireMock、Test Client実装は変更しない。

## 3. 検証手順

1. Composeを停止して前回の孤児を回収する
2. 3サービスを`up -d --build`で起動する
3. WireMock管理APIを待機する
4. Squid経由でM03正常系へアクセスできるまで待機する
5. Test ClientをComposeネットワーク内で実行する
6. Squid access logとWireMock受信履歴を同一パスで確認する
7. allowlist外ドメインが成功しないことと拒否ログを確認する
8. 失敗時にログを出力し、終了時にComposeを停止する

## 4. 制約

- Test ClientからWireMockへ直接接続しない
- 外部ネットワークへの成功リクエストを送らない
- `--max-time`は外部遮断確認の上限にだけ使用し、M06のタイムアウト契約にしない
