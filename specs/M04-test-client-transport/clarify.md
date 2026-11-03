# M04 clarify

## 確定事項

| 論点 | 決定 |
| --- | --- |
| クライアント実装 | Alpine上のPOSIX shellとcurlを使用する |
| プロキシ指定 | `HTTP_PROXY`を必須とし、curlの`--proxy`へ明示的に渡す |
| API入力 | 既存の`TEST_API_BASE_URL`に`TEST_API_PATH`を連結する |
| 既定パス | `/api/users/123`を使用する |
| 成功出力 | `CLIENT_STATUS`と改行を除去した`CLIENT_BODY`を標準出力へ出す |
| 失敗出力 | `CLIENT_ERROR`を標準エラーへ出し、非ゼロ終了する |
| プロキシ未設定 | 終了コード78で停止し、curlを実行しない |
| HTTPエラー | HTTP通信が成立した場合はステータスと本文を出力し、リトライしない |
| 直接接続 | WireMockのホスト名やポートはクライアントスクリプトに書かない |

## 対象外

- HTTP 500、503、429へのリトライとバックオフ
- タイムアウトポリシー
- Test ClientのNode.js化
- HTTPSの証明書検証変更
- M05の統合経路全体の受入検証
