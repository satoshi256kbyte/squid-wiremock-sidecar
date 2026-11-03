# M07 リセット実験の記録

T701（plan.md 3章）の結果。WireMock 3.13.1 の `POST /__admin/reset` が何を戻すかを実機で確かめた。

## 1. 環境

| 項目 | 値 |
|------|-----|
| WireMock | `wiremock/wiremock:3.13.1`（`docker-compose.yml` の `wiremock` サービス） |
| Compose | `docker-compose` 5.6.1。プロジェクト名は `-p m07-reset-exp` |
| Docker 実行基盤 | Colima。`DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock` |
| Docker 設定 | セッション用の空の `config.json`（認証情報は読んでいない） |
| 開始前の確認 | ポート3128と8080にリスナーなし。本リポジトリ由来のコンテナは起動していなかった |
| 管理APIの宛先 | `127.0.0.1:8080`。Compose の既定公開は `0.0.0.0:8080`（ps の表示どおり。変更していない） |
| 実施日 | 2026-11-03 |

## 2. 実験に使ったファイル

実験は使い捨てコピーで行い、リポジトリのファイルは書き換えていない。コピーは実験後に削除した。

| コピー側のパス | 内容 |
|----------------|------|
| `docker-compose.yml` | リポジトリから複製。変更なし |
| `squid-config/` | リポジトリから複製。変更なし |
| `wiremock-scenarios/mappings/normal-case.json` | `"name": "normal"` を追加 |
| `wiremock-scenarios/mappings/error-429-case.json` | `"name": "ratelimit-429"` を追加 |
| `wiremock-scenarios/mappings/delay-100ms-case.json` | `"name": "slow-100"` を追加 |
| `wiremock-scenarios/mappings/delay-5000ms-case.json` | `"name": "slow-5000"` を追加 |
| `wiremock-scenarios/mappings/error-500-then-200-1.json` | 新規。plan.md 4.2 の1つ目（`Started` から `Succeeded`、500） |
| `wiremock-scenarios/mappings/error-500-then-200-2.json` | 新規。plan.md 4.2 の2つ目（`Succeeded` のまま200） |
| `wiremock-scenarios/mappings/zz-tmp.json` | Q-704 用の一時ファイル。`name` は `zz-tmp`、パスは `/api/zz-tmp` |

`error-500-case.json` と `error-503-case.json` は、複製のまま `name` を付けていない。

## 3. 観測

| 順 | 操作 | 観測結果 |
|----|------|----------|
| 1 | `GET /__admin/mappings`、`GET /__admin/scenarios` | マッピング8件（`mappings/*.json` のファイル数と一致）。`name` を持つのは6件。`error-500-case` と `error-503-case` は `name` キーがない。シナリオ `error-500-then-200` の状態は `Started` |
| 2 | `GET /api/error-500-then-200` を2回 | 1回目は500、2回目は200。状態は `Succeeded` に遷移 |
| 3 | `POST /__admin/reset` | HTTP 200。応答本文は空 |
| 4 | リセット直後に `GET /__admin/mappings`、`/__admin/requests`、`/__admin/scenarios` | マッピング8件（ファイル数と一致）。ジャーナル0件。シナリオ状態は `Started` |
| 5 | リセット後の `GET /api/error-500-then-200` | 500（初回と同じ） |
| 6 | 管理APIで `POST /__admin/mappings`（`/api/admin-added`、応答201）を追加し、リセット | 追加前は件数9、`/api/admin-added` は201。リセット後は件数8、同パスは404。管理APIで足したマッピングも消えた |
| 7 | `GET /__admin/requests` の応答形 | `meta`、`requestJournalDisabled`、`requests` の3キー。件数は `meta.total`、一覧は `requests` |

観測6の後にリクエストジャーナルが1件だったのは、リセット後に私が送った404の呼び出しが記録されたため。
リセット直後に呼び出しを挟まず読んだ観測4と、Q-704のリセット直後の読み取りでは0件だった。

## 4. 値

plan.md 3.3 の値は次のとおり。

| 対象 | 件数の場所 | 一覧の場所 | 名前の場所 | 状態の場所 |
|------|-----------|-----------|-----------|-----------|
| マッピング | `meta.total` | `mappings[]` | 各要素の `name`（トップレベル）。`name` のないスタブではキーが存在しない | 対象外 |
| シナリオ | 応答に件数フィールドがない。`scenarios[]` の長さを使う | `scenarios[]` | 各要素の `name` | 各要素の `state` と `possibleStates` |
| リクエストジャーナル | `meta.total` | `requests[]` | 対象外 | 対象外 |

補足は次のとおり。

- マッピングの要素には `request.urlPath`、`scenarioName`、`requiredScenarioState`、`newScenarioState` も含まれる。
- ジャーナルの応答には `requestJournalDisabled` キーもある。
- `name` は `GET /__admin/mappings` の応答にそのまま載る。トップレベルの `name` は M03 の検査とWireMockの読み込みに影響しなかった。

Q-704（ファイル追加の反映）の結果は次のとおり。

| 手順 | 結果 |
|------|------|
| `mappings/` に `zz-tmp.json` を置いた直後（リセット前）に `GET /__admin/mappings` | 件数8。`/api/zz-tmp` はなし |
| リセット前の `GET /api/zz-tmp` | 404 |
| `POST /__admin/reset` の後に `GET /__admin/mappings` | 件数9。`/api/zz-tmp` あり |
| リセット後の `GET /api/zz-tmp` | 200 |

結論として、ファイルを追加した後は `POST /__admin/reset` で反映される。コンテナの再起動は要らない。

## 5. 分岐の決定

plan.md 3.2 の判定は「3つとも戻る」である。

| 確認項目 | 結果 |
|----------|------|
| ファイル由来のマッピングは戻ったか | 戻った（件数8。管理APIで追加した1件は消えた） |
| ジャーナルは空になったか | 空になった（0件） |
| シナリオ状態は戻ったか | 戻った（`Succeeded` から `Started`） |

この結果により、5.2の主経路（`POST /__admin/reset` の1回）を採用する。
3.2 の代替経路（`POST /__admin/mappings/reset`、`DELETE /__admin/requests`、`POST /__admin/scenarios/reset`）は
試していない。主経路で戻ったため、必要がなかった。
コンテナの再起動は使っていない。

## 6. 後続への影響

| 対象 | 影響 |
|------|------|
| T706 `wiremock_reset` | `POST /__admin/reset` の1回だけを呼ぶ。個別エンドポイントは追加しない |
| T706 `wiremock_verify_reset` | `meta.total` がマッピングのファイル数（`.gitkeep` を除く）と一致すること、`requests` の `meta.total` が0であること、`scenarios[].state` がすべて `Started` であることを確認する |
| T706 確認の順序 | 確認はリセット直後に読む。管理APIの読み取りはジャーナルに載らなかった |
| T709 追加手順 | 新しいマッピングは `wiremock-scenarios/mappings/` に置き、`POST /__admin/reset` で反映させる |
| T709 名前の確認 | 管理APIの応答に `name` が載るため、`smoke` で名前と `request.urlPath` の一致を確かめられる |
| 公開設定 | Compose が 8080 と 3128 を `0.0.0.0` で公開している。本実験では変更していない（plan.md 8章の既存リスク） |

## 7. ゲート判定

| 条件 | 判定 | 根拠 |
|------|------|------|
| 通過の条件1: 3.4の全節があり、3.1の観測1から7が揃っている | 満たす | 1章から6章が3.4の節に対応する。観測1から7を3章に記録した |
| 通過の条件2: 3.3の値（件数、状態、ジャーナルのフィールド名、`name` の有無、Q-704）が揃っている | 満たす | 4章に、件数、一覧、名前、状態、ジャーナルの各フィールド名とQ-704の結果を記録した |
| 通過の条件3: 3.2の分岐が確定している | 満たす | 5章で主経路の採用を決定した |
| 通過しない条件 | 該当なし | 「代替でも戻らない」には当たらない。観測の欠落もない |

ゲートは通過と判定する。T706、T707、T708、T709、T711、T712 と T710 の着手条件を満たす。
