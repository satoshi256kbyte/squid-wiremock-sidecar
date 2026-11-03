# S14 契約影響の記録（T1408）

## 概要

S14 の変更が M01 から M07 の契約に与える影響を記録する。
変更は次の2点である。

- Compose のホスト公開を、ループバックだけに限定した。サービス名、ネットワーク名、マウント、コンテナ内のポートは変えていない
- Squid に送信元 ACL（`local_src`）を1つ足し、`http_access allow api_domains` を
  `http_access allow local_src api_domains` に変えた。`cache deny all` の行は以前に承認済みで、今回の変更ではない

## 影響の有無

| 契約 | 影響 | 根拠 |
| --- | --- | --- |
| M01 公開ポート（3128、8080） | 有 | ポート番号は不変。公開先が全インターフェースからループバックに狭まった。`sh tests/s14-compose-port-binding.sh static` が終了コード 0。`live` は3回連続で成功（毎回 12 PASS、終了コード 0） |
| M01 README 上の接続先 | 有 | 接続先の表記を `localhost` からループバックの数値表記に変えた。`README.md` の差分で確認できる |
| M02 ルーティング | 有 | 宛先と転送は不変。`http_access` に送信元の条件が増えた。新しいスタックで `sh tests/m02-routing-smoke.sh` を個別に実行し、終了コード 0、M02 Squid routing smoke test passed を確認した |
| M03 WireMock シナリオ | 無 | `tests/m03-wiremock-scenarios.sh` は編集していない。管理 API の既定の接続先はループバックで、`live` の順3で管理 API が 200 を返した |
| M04 Test Client 契約 | 無 | `test-client/` と `Dockerfile.test-client` は編集していない。Test Client 経由の許可ドメインは `live` の順7で成功した |
| M05 閉域統合 | 無 | `tests/m05-proxy-integration.sh` は編集していない。`WIREMOCK_URL` と `PROXY_URL` の既定値はループバックである |
| M06 リトライ | 無 | `tests/m06-client-resilience.sh` は編集していない。既定値はループバックである |
| M07 シナリオ隔離 | 無 | `tests/m07-scenario-isolation.sh` と `scripts/scenario-lib.sh` は編集していない。既定値はループバックである |

## 既定値の確認

`grep -nE "WIREMOCK_URL|PROXY_URL" tests/*.sh scripts/scenario-lib.sh` で、M02 から M07 の検査と
`scripts/scenario-lib.sh` の既定値がすべてループバックであることを確認した。
`git status --short` で、`tests/` の既存ファイルに差分がないことも確認した（`tests/` の変更は新規の
`tests/s14-compose-port-binding.sh` だけ）。

## 変更していない契約とその理由

| 契約 | 理由 |
| --- | --- |
| サービス名、ネットワーク名 | Test Client がサービス名で Squid に接続する契約（M04）を保つため |
| マウント | WireMock のマッピングと Squid の設定の供給経路（M03）を保つため |
| コンテナ内のポート | ネットワーク内の通信（M04、M05）を変えないため。変えたのはホスト側の公開先だけである |
| Test Client | 送信元 ACL の範囲内に収まるため、変更の必要がなかった |
| M03 から M07 の検査スクリプト | 既定の接続先がもともとループバックで、公開先の変更後も動くため |

## 未確認の事項

Linux の CI で、ループバック経由の接続の送信元アドレスが ACL の範囲に入るかは確認していない（R-02）。
この作業では Linux のホストまたは CI ランナーを用意できず、macOS（Colima）でだけ確かめた。
M09 で CI を導入する際に、Linux の送信元アドレスがアクセスログで ACL の範囲に入ることを確認する必要がある。
