# M03実装計画

## 1. 実装方針

WireMock標準の静的マッピングを`wiremock-scenarios/`へ追加する。
マッピングはリクエスト条件と応答メタデータを持ち、本文は`__files/`から読み込む。

## 2. 変更ファイル

| パス | 変更内容 |
| --- | --- |
| `wiremock-scenarios/mappings/` | 正常、500、503、429、100ms、5000msのマッピング |
| `wiremock-scenarios/__files/` | 各シナリオのJSONレスポンス本文 |
| `tests/m03-wiremock-scenarios.sh` | 自動ロード、応答契約、遅延、JSON検証の確認 |
| `docker-compose.yml` | M01のWireMockマウント契約を維持して確認する |

## 3. 検証方針

1. 全JSONを`python3`で構文検証する
2. マッピングに`request.method`、`request.urlPath`、`response.status`があることを検証する
3. Composeを起動し、WireMockのマッピング一覧に6シナリオがロードされたことを確認する
4. 各パスへリクエストし、ステータス、本文、ヘッダーを確認する
5. 100msと5000msの応答時間が下限を満たすことを確認する
6. Composeを停止し、孤児コンテナを残さない

## 4. 設計上の制約

- M01のサービス名、ポート、ネットワーク、healthcheckを変更しない
- M03では管理APIへマッピングを登録しない
- M02未マージのため、M03の検証はWireMockへ直接アクセスする
- シナリオ追加はJSONファイルの追加だけで完結させる
