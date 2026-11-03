# M04実装計画

## 1. 実装方針

Test Clientのイメージへcurlを追加し、entrypointで環境変数を検証してから
`--proxy "$HTTP_PROXY"`でAPIへアクセスする。応答本文は一時ファイルへ保存し、
改行を除去して機械的に判定できる形式で出力する。

## 2. 変更ファイル

| パス | 変更内容 |
| --- | --- |
| `Dockerfile.test-client` | curlを追加し、非root実行契約を維持する |
| `test-client/entrypoint.sh` | プロキシ必須検証、curl実行、結果出力、終了コードを実装する |
| `tests/m04-test-client.sh` | Compose起動、Test Client実行、出力契約、直接接続防止を検証する |

## 3. 検証方針

1. SquidとWireMockをComposeで起動する
2. Test ClientをComposeネットワーク内で一度実行する
3. `CLIENT_STATUS=200`とM03正常系本文を確認する
4. WireMock受信履歴でリクエスト到達を確認する
5. `HTTP_PROXY`を空にした実行が終了コード78になることを確認する
6. Composeを停止し、孤児コンテナを残さない

## 4. 設計上の制約

- `docker-compose.yml`のM01〜M03契約は変更しない
- Test ClientからWireMockへ直接接続するURLを記載しない
- M06のリトライ、バックオフ、タイムアウトは実装しない
- テストは`docker-compose run --rm --no-deps test-client`で実行する
