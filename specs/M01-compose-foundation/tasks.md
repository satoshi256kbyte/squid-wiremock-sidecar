# M01 Compose実行基盤のタスク

## T01: Composeサービス契約

- `docker-compose.yml`に3サービスを定義する
- bridgeネットワーク、ポート、環境変数、volumeを定義する
- Test Clientの起動依存関係を定義する

## T02: 最小コンテナ構成

- Test ClientのDockerfileとエントリーポイントを作成する
- Squidの設定ファイルをマウント可能にする
- WireMockのmappingsと`__files`領域をマウントする

## T03: ヘルスチェック

- 全サービスにPID 1のhealthcheckを定義する
- healthcheckの間隔、タイムアウト、再試行回数を明示する
- M05でHTTP経路検証へ拡張する境界を文書化する

## T04: 構文・起動・停止検証

- `docker-compose config`を実行する
- Colima条件付きの起動手順を検証する
- 3サービスのhealthy状態を確認する
- `docker-compose down --remove-orphans`で終了する

## T05: 差分レビューとコミット

- Issue #1のAcceptance Criteriaと差分を照合する
- M02以降の実装が混入していないことを確認する
- 必須ゲート通過後に日本語コミットを作成する

## 完了条件

- [ ] T01からT05を完了している
- [ ] `spec.md`、`clarify.md`、`plan.md`、`tasks.md`、`analyze.md`が揃っている
- [ ] Compose構文検証が成功している
- [ ] 起動・停止検証の結果が記録されている
- [ ] Issue #1のAcceptance Criteriaが満たされている
