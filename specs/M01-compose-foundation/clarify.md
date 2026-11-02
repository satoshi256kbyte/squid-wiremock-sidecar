# M01 clarify記録

## 実施内容

M01の仕様、既存の全体Spec、全体Plan、ロードマップ、Issue #1を照合した。
M01で実装する起動契約と、後続Issueへ持ち越す機能境界を確定した。

## 確定事項

| 論点 | 決定 | 理由 |
|------|------|------|
| Composeコマンド | `docker-compose`を使用 | リポジトリのDocker運用ルールに従うため |
| Clientの実装 | 常駐する最小Alpineコンテナ | M01ではHTTP処理を実装しないため |
| Squidイメージ | `ubuntu/squid:latest` | ARM64のColimaでも検証しやすい計画上の標準イメージのため |
| WireMockイメージ | `wiremock/wiremock:3.13.1` | WireMockの動作を後続Issueで固定しやすくするため |
| healthcheck | 全サービスのPID 1生存確認 | HTTP経路の検証はM05で実施し、M01の責務を起動契約に限定するため |
| Squidの通信許可 | M01では閉じる | M02でACLとcache_peerを設計し、直接通信を許可する暫定設定を残さないため |
| WireMockの定義 | 空のマッピングディレクトリをマウント | M03でシナリオを追加できる構成を先に固定するため |
| 起動依存関係 | ClientがSquidとWireMockのhealthyを待つ | 後続の統合テストで起動競合を避けるため |

## 未決事項の扱い

HTTPS、Squidの詳細キャッシュ、WireMockのシナリオ状態、リトライポリシー、CI実行は
M01の対象外として、各後続IssueのSpec Kitで確定する。

## 出力契約

M01の実装は、Compose構文検証とコンテナ起動・停止を確認できる状態を出力する。
HTTPリクエストがWireMockへ到達することはM01の完了条件に含めない。
