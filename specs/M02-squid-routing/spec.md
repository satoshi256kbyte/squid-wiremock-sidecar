# M02 Squidサイドカー閉域ルーティングの仕様

## 1. 目的

SquidをTest Clientのフォワードプロキシとして動かし、許可したAPIドメインだけを
WireMockへ転送する。許可対象外の通信はSquidで拒否し、
外部ネットワークへ直接到達させない。

## 2. 対象範囲

- SquidのDocker設定拡張
- WireMockへの`cache_peer`設定
- APIドメインのallowlist
- `http_access`、`cache_peer_access`、`never_direct`
- テスト時の一時キャッシュとログ
- HTTPによる閉域ルーティング検証

## 3. 機能要件

| ID | 要件 |
|----|------|
| FR-201 | `api.example.com`をWireMockへ転送する |
| FR-202 | allowlistを外部ファイルで管理する |
| FR-203 | 許可対象外のドメインをSquidで拒否する |
| FR-204 | 許可対象ドメインで直接接続を行わない |
| FR-205 | Squidの転送結果をアクセスログで確認できる |
| FR-206 | WireMockが転送されたリクエストを受信できる |
| FR-207 | 検証用キャッシュとログをコンテナ停止時に残さない |

## 4. 非機能要件

| ID | 要件 |
|----|------|
| NFR-201 | ルーティング対象を設定ファイルの変更で追加できる |
| NFR-202 | HTTPだけを対象とし、HTTPSのSSL Bumpを導入しない |
| NFR-203 | Squidプロセスをroot権限で実行する変更を行わない |
| NFR-204 | M01の3サービス構成とポート契約を壊さない |

## 5. 完了条件

- [ ] SquidがWireMockをparent peerとして認識する
- [ ] allowlist対象のHTTPリクエストがWireMockへ到達する
- [ ] allowlist外のリクエストが成功しない
- [ ] Squidのアクセスログで転送を確認できる
- [ ] WireMock側で受信結果を確認できる
- [ ] キャッシュとログが一時領域に保存される
- [ ] M02固有のSpec Kit成果物と検証スクリプトがある
