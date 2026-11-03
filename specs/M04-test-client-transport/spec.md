# M04 Test Client通信契約の仕様

## 1. 目的

Test Clientが外部APIの宛先へ直接接続せず、Compose内のSquidを明示的に経由して
WireMockへ到達する最小の通信契約を固定する。

## 2. 対象範囲

- `test-client/`の実行スクリプトとコンテナ依存
- `HTTP_PROXY`環境変数による明示的なプロキシ指定
- `TEST_API_BASE_URL`とAPIパスの入力
- HTTPステータス、レスポンス本文、通信失敗の出力
- Compose内Test ClientからSquid経由でWireMockへ到達する検証
- プロキシ未設定時の直接通信防止

## 3. 機能要件

| ID | 要件 |
| --- | --- |
| FR-401 | Test Clientが`HTTP_PROXY`を必須入力として読む |
| FR-402 | Test Clientが明示的にプロキシ経由でHTTPリクエストを送信する |
| FR-403 | APIのHTTPステータスを`CLIENT_STATUS`として出力する |
| FR-404 | APIのレスポンス本文を`CLIENT_BODY`として機械的に出力する |
| FR-405 | 通信失敗時に診断ログを標準エラーへ出力し、非ゼロ終了する |
| FR-406 | プロキシ未設定時に直接通信せず、固定の非ゼロ終了コードで停止する |
| FR-407 | Compose内Test ClientからSquid経由でM03正常系へ到達する |

## 4. 非機能要件

| ID | 要件 |
| --- | --- |
| NFR-401 | Test Clientは非rootユーザーで実行する |
| NFR-402 | プロキシURLとAPI URLを環境変数で差し替えられる |
| NFR-403 | WireMockのホスト名や8080番ポートをTest Clientへ直書きしない |
| NFR-404 | リトライ、バックオフ、タイムアウトポリシーを実装しない |
| NFR-405 | M01、M02、M03のCompose、Squid、WireMock契約を維持する |

## 5. 出力契約

| 出力 | 内容 |
| --- | --- |
| `CLIENT_STATUS=<status>` | 3桁のHTTPステータスコード |
| `CLIENT_BODY=<body>` | 改行を除去したレスポンス本文 |
| `CLIENT_ERROR=<code>` | 通信失敗または設定不備の識別子 |

プロキシ未設定時の終了コードは78とする。
HTTPエラーは通信成功としてステータスと本文を出力し、リトライは行わない。

## 6. 完了条件

- [ ] Compose内のTest ClientからSquid経由で正常系マッピングを取得できる
- [ ] ステータスコードとレスポンス本文を機械的に取得できる
- [ ] プロキシ設定を環境変数で差し替えられる
- [ ] WireMockへ直接接続する実装になっていない
- [ ] 通信失敗時の終了コードと診断ログが定義されている
- [ ] M04のSpec Kit成果物と検証手順が保存されている
