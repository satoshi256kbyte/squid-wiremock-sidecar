# E2Eテスト

M08 の E2E スイートの実行方法、4シナリオの期待値、失敗時の見方を説明する。
検査の入口は `tests/m08-e2e-suite.sh`（`unit` と `smoke`）。
名前からパスを引く処理、リセットと確認は `scripts/scenario-lib.sh` にある。
シナリオの隔離、リセット、追加の手順は [シナリオの隔離と追加](シナリオ隔離.md) を参照。

## 実行方法

```sh
sh tests/m08-e2e-suite.sh
sh tests/m08-e2e-suite.sh unit
sh tests/m08-e2e-suite.sh smoke error-500-then-200
```

モードは `unit` と `smoke` の2つで、引数なしは `smoke` になる。

| モード | 内容 | Docker |
| --- | --- | --- |
| `unit` | シナリオ表、実測値の抽出、実行ループ、レポート、後始末をスタブで検査する | 使わない |
| `smoke` | `unit` の後に Compose を起動し、4シナリオを実通信で実行する | Compose を使う |

`smoke` の後にシナリオ名を並べると、その名前のシナリオだけを1周実行する。
名前は既定の順と違う順で指定してよい。実行は常に直列である。
`unit` はシナリオ名を受け付けない。

Colima を使う環境では、`smoke` の前に `colima status` で起動を確かめ、Docker のソケットを指定する。
Compose は `docker compose` ではなく `docker-compose` を使う。

### 終了コード

| 終了コード | 意味 |
| --- | --- |
| 0 | 全件合格 |
| 1 | 一つでも失敗した。アサーションの失敗と、リセット確認の失敗による未実行を含む |
| 2 | 引数の誤り。不正なモード、未定義または対象外のシナリオ名、`unit` へのシナリオ名の指定 |
| 130、143 | `smoke` の実行中に `INT` または `TERM` を受けた。後始末の後に終了する |

## 4シナリオの期待値

| シナリオ | パス | 上書きする設定 | status | result | attempts | retries | wiremock | rc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `normal` | `/api/users/123` | なし | 200 | success | 1 | 0 | 1 | 0 |
| `error-500-then-200` | `/api/error-500-then-200` | なし | 200 | success | 2 | 1 | 2 | 0 |
| `ratelimit-429` | `/api/ratelimit` | なし | 429 | retries_exhausted | 4 | 3 | 4 | 0 |
| `slow-5000` | `/api/slow-5000` | `RESPONSE_TIMEOUT_SECONDS=1` | -（出力なし） | timeout | 1 | 0 | 1 | 28 |

各列の読み方は次のとおり。

- status は標準出力の `CLIENT_STATUS` の値である。`slow-5000` は応答を受けないため `-` になる。
- attempts は総試行、retries はリトライ回数である。retries は attempts から 1 を引いた値に等しい。
  診断ログの `retry` 行の数とも突き合わせる。
- wiremock は、WireMock のジャーナルに残ったそのパスへの受信回数である。
- rc はクライアントの終了コードである。`ratelimit-429` は再試行を使い切っても終了コード 0 になる。
- 既定の設定値は M06 の 4 章に従う。上書きするのは上の表の列だけである。
- `slow-5000` の受信回数は 1 である。クライアントが 1 秒で切断しても、WireMock は要求を受信した時点で記録する。
  Q-810 の実機確認（[q810-experiment.md](../specs/M08-e2e-suite/q810-experiment.md)）で、
  記録は応答完了を待たず即時に残ることを確かめた。遅れた記録は見られなかった。

## レポートの見方

レポートは標準出力に出る。ファイルには保存しない（保存は M09 の対象）。

```text
scenario | expected | actual | result
normal | status=200 result=success attempts=1 retries=0 wiremock=1 rc=0 | status=200 result=success attempts=1 retries=0 wiremock=1 rc=0 | PASS
error-500-then-200 | ... | ... | PASS
ratelimit-429 | ... | ... | PASS
slow-5000 | ... | ... | PASS
summary: PASS passed=4 failed=0 not_run=0 failed_scenarios=- elapsed=20s
```

1シナリオにつき1行で、シナリオ名、期待値、実測値、合否を並べる。
期待値と実測値は同じ項目名で並ぶため、行を見比べるだけで差がわかる。

最後の行（`summary:`）は全体の合否を示す。項目は次のとおり。

| 項目 | 意味 |
| --- | --- |
| `PASS` または `FAIL` | 全体の合否。失敗か未実行が一つでもあると `FAIL` |
| `passed`、`failed`、`not_run` | 合格、失敗、未実行の件数 |
| `failed_scenarios` | 失敗したシナリオ名のカンマ区切り。無ければ `-` |
| `elapsed` | 実行の秒数。起動とビルドは含まない |

## 失敗時の見方

シナリオが失敗すると、標準エラーに次の内容が出る。

```text
scenario: slow-5000
  path: /api/slow-5000
  overrides: RESPONSE_TIMEOUT_SECONDS=1
  expected: status=- result=timeout attempts=1 retries=0 wiremock=1 rc=28
  actual: status=- result=timeout attempts=2 retries=0 wiremock=1 rc=28
  rerun: sh tests/m08-e2e-suite.sh smoke slow-5000
  diag:
    CLIENT_ERROR=timeout
    CLIENT_DIAG result=timeout attempts=1 curl_exit=28
```

| 出力 | 意味 |
| --- | --- |
| `scenario:` | 失敗したシナリオ名 |
| `path:` | クライアントに渡したパス |
| `overrides:` | 上書きした環境変数。無ければ `none` |
| `expected:`、`actual:` | 期待値と実測値 |
| `rerun:` | そのシナリオだけを再実行するコマンド |
| `diag:` | クライアントの診断ログ（標準エラー）をそのまま出したもの |

診断ログには認証情報を含めない。

リセット確認が外れた場合は、`FAIL: リセットを確認できないため <名前> を実行しない` と出る。
このとき、その後のシナリオは `NOT_RUN` になり、クライアントを呼ばない。
最初に見るべきはリセットの結果である。

`smoke` が0以外で終わると、`squid` と `wiremock` のログの末尾100行を標準エラーに出す。

後始末の行は次の意味である。

| 行 | 意味 |
| --- | --- |
| `cleanup: reset attempted` | 起動中の WireMock へ、リセットを送った |
| `cleanup: reset ok` | リセットが成功した |
| `cleanup: reset failed (ignored)` | リセットが失敗した。後始末は続き、終了コードは変わらない |
| `cleanup: reset skipped (not running)` | WireMock が起動していないため、リセットを送らなかった |
| `cleanup: reset skipped (not started)` | 起動を始めていないため、ポートに触れずに終わった |

終了時は、Compose のコンテナを止めて削除し、一時ディレクトリも消す。
終了コードは、後始末の前の値を保つ。

## 所要時間の目安

NFR-803 の目標は、起動とビルドを除いて 60 秒以内である。
超えても失敗にはならない。所要時間は、レポートの最後の行の `elapsed` に出る。

| 区分 | 実測の目安 | 内訳 |
| --- | --- | --- |
| `unit` | 約 11 秒 | Docker を使わない |
| `smoke` の実行（起動とビルドを除く） | 約 20 秒 | 待機が中心。500 の後の成功で 1 秒、タイムアウトで 1 秒、429 で 6 秒 |
| 起動とビルドを含む全体 | 約 100 秒 | イメージの有無で変わる |

## 既存文書との違い

ルートの `plan.md` の 2.6 と、`README.md` の「Testing Scenarios」の表は、現在の実装と記載が違う（Q-815）。
M08 では直さず、この節で違いを説明する。

| 項目 | 記載 | M08 の実装 |
| --- | --- | --- |
| 500 の後の成功 | `plan.md` 2.6 はリトライ 3 回後成功 | 再試行は 1 回で成功する（`error-500-then-200`） |
| 表の「✓ 3 times」 | 最大再試行の設定値 | E2E の実測値とは別の値 |
| タイムアウト | `plan.md` 2.6 は fallback への移行 | 結果 `timeout` を判定する。fallback の動作は検査しない |
| テストコード | `plan.md` 2.6 は `tests/e2e.test.js` | `tests/m08-e2e-suite.sh` |

直す判断は、M11（最終受入検証）か別の Issue で行う。

## 並列実行の禁止

1台の WireMock に対して、シナリオを並列に実行しない（NFR-806、M07 の FR-712）。
リセットと受信回数は同じジャーナルを共有するため、並列にすると互いの結果が混ざる。
1回のスイートの中でも、シナリオは直列に実行する。

`smoke` は、Compose のプロジェクト名 `m08-e2e` と、ポート 3128 と 8080 を使う。
どちらかのポートが使用中なら、起動せずに終了コード 1 で止まる。
別のスタックが同じポートを使っているときは、`smoke` を実行しない。
