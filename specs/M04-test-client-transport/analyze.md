# M04 analyze結果

## 1. 要件カバレッジ

| 要件 | 設計 | タスク | 判定 |
| --- | --- | --- | --- |
| FR-401 HTTP_PROXY必須 | clarify、entrypoint検証 | T02、T03 | PASS |
| FR-402 明示的プロキシ送信 | curl `--proxy` | T02、T04 | PASS |
| FR-403 HTTPステータス出力 | `CLIENT_STATUS` | T02、T04 | PASS |
| FR-404 本文出力 | `CLIENT_BODY` | T02、T04 | PASS |
| FR-405 通信失敗契約 | `CLIENT_ERROR`と非ゼロ終了 | T03、T04 | PASS |
| FR-406 未設定時の直接通信防止 | 終了コード78でcurl未実行 | T03、T04 | PASS |
| FR-407 Squid経由の正常系 | Composeネットワーク実行 | T04 | PASS |
| NFR-401 非root | 既存Dockerfile契約維持 | T01、T05 | PASS |
| NFR-402 環境変数差し替え | URLとProxyを環境変数化 | T02、T04 | PASS |
| NFR-403 WireMock直書き禁止 | クライアントURLから除外 | T02、T05 | PASS |
| NFR-404 リトライ等対象外 | clarify、planで明示 | T05 | PASS |
| NFR-405 既存契約維持 | Compose変更なし | T04、T05 | PASS |

## 2. スコープ確認

M06のリトライ、バックオフ、タイムアウト、M05の全体受入検証は対象外である。
M01のCompose、M02のSquid、M03のWireMockマッピングを利用する。

## 3. 未決事項

CriticalまたはHighに相当する未決事項はない。
HTTPエラーの再試行はM06で扱うため、M04ではHTTPステータス取得を成功させる契約とする。

## 4. 判定

**PASS**。M04の実装へ進める。
