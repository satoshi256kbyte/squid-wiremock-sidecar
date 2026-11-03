# M05 clarify

## 確定事項

| 論点 | 決定 |
| --- | --- |
| 起動単位 | M05専用スクリプトがComposeを起動し、終了時に停止する |
| readiness | WireMock管理APIとSquid経由の正常系リクエストを待機条件にする |
| 経路確認 | Test Clientの出力、Squid access log、WireMock受信履歴を同一パスで照合する |
| 外部通信 | allowlist外の`example.com`が成功しないこととSquid拒否ログを確認する |
| 診断出力 | 失敗時にComposeログとSquid access logを標準エラーへ出す |
| cleanup | EXIT trapで`docker-compose down --remove-orphans`を必ず実行する |
| シナリオ | M03正常系`/api/users/123`だけを使用する |

## 対象外

- HTTPエラーのリトライ、バックオフ、タイムアウト
- WireMockシナリオの切り替え
- AWS ECSへのデプロイ
- M01/M02の既存公開ポート設計の変更
