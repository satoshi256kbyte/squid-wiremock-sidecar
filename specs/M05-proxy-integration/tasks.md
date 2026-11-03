# M05実装タスク

## T01: 統合テストのライフサイクル

- Composeを起動する
- WireMockとSquidのreadinessを待機する
- EXIT trapでcleanupする

## T02: ClientからWireMockへの経路検証

- Test ClientをComposeネットワーク内で実行する
- `CLIENT_STATUS`と`CLIENT_BODY`を確認する
- WireMock受信履歴で対象パスを確認する

## T03: Squidログ相関

- Squid access logから対象パスを確認する
- WireMock受信履歴と同じパスで照合する

## T04: 外部通信遮断

- allowlist外ドメインへのproxy通信が成功しないことを確認する
- Squidの拒否ログを確認する

## T05: 失敗時診断

- SquidとWireMockのComposeログを標準エラーへ出力する
- Squid access logを診断情報へ含める
- 元の終了コードを維持する

## T06: Spec Kit整合性とレビュー

- `spec.md`、`clarify.md`、`plan.md`、`tasks.md`、`analyze.md`を確認する
- M06以降のリトライ、切り替え、タイムアウトを混入させない
- 品質ゲート実行結果を記録する

## 完了条件

- [ ] T01からT06を完了している
- [ ] 3層通信経路を自動検証できる
- [ ] 外部通信遮断を検証できる
- [ ] 失敗時診断とcleanupを確認できる
