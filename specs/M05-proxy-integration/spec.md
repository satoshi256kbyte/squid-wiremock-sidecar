# M05 閉域通信統合検証の仕様

## 1. 目的

Test Client、Squid、WireMockの3サービスを起動し、Test Clientの通信がSquidを経由して
WireMockへ到達する統合経路を自動検証する。
許可対象外の外部通信も成功しないことを確認する。

## 2. 対象範囲

- 3サービスのCompose起動とreadiness待機
- Test ClientからSquidを経由したM03正常系への通信
- Squid access logとWireMock受信履歴の相関確認
- allowlist外ドメインの遮断
- 失敗時のSquid、WireMock、Compose状態の診断出力
- 実行後のコンテナとネットワークのcleanup

## 3. 機能要件

| ID | 要件 |
| --- | --- |
| FR-501 | 3サービスを統合テストから起動できる |
| FR-502 | Test ClientからSquid経由でWireMock正常系へ到達できる |
| FR-503 | Test Client出力とWireMock受信履歴を相関できる |
| FR-504 | Squid access logに対象リクエストが記録される |
| FR-505 | allowlist外ドメインへの通信が成功しない |
| FR-506 | 統合テスト失敗時にSquidとWireMockのログを出力する |
| FR-507 | 統合テスト終了時にコンテナとネットワークを回収する |

## 4. 非機能要件

| ID | 要件 |
| --- | --- |
| NFR-501 | 既存のM01〜M04のCompose、Squid、WireMock、Test Client契約を変更しない |
| NFR-502 | M06のリトライ、バックオフ、タイムアウトを実装しない |
| NFR-503 | 外部APIへ実通信せず、allowlist外の失敗を確認する |
| NFR-504 | ローカルとCIで同じテスト入口を使用できる |

## 5. 完了条件

- [ ] 3サービスを起動して統合テストを自動実行できる
- [ ] Test ClientからのリクエストがSquidを経由したことを検証できる
- [ ] WireMockが期待したリクエストを受信したことを検証できる
- [ ] 外部ネットワークへ到達していないことを検証できる
- [ ] 失敗時にSquidとWireMockのログを診断情報として取得できる
- [ ] M05のSpec Kit成果物と検証手順が保存されている
