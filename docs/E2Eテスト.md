# E2Eテスト

4つの代表シナリオの実行方法、期待値、失敗時の見方を説明する。
実行は `scripts/e2e-scenarios.sh`。名前からパスを引く処理と、リセットと確認は `scripts/scenario-lib.sh` にある。
シナリオの隔離、リセット、追加の手順は [シナリオの隔離と追加](シナリオ隔離.md) を参照。

## 実行方法

```sh
sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000   # 4シナリオ（CI と同じ）
sh scripts/e2e.sh test:ci error-500-then-200                                    # 1シナリオだけ
```

WireMock、pause、Squid を起動し、シナリオを実通信で直列に実行して、最後に止める（Docker を使う）。
名前は既定の順と違う順で指定してよい。実行は常に直列である。

### 終了コード

| 終了コード | 意味 |
| --- | --- |
| 0 | 全件合格 |
| 1 | 一つでも失敗した。リセット確認の失敗による未実行を含む |
| 2 | 引数の誤り。未定義または対象外のシナリオ名 |
| 130、143 | 実行中に `INT` または `TERM` を受けた。後始末の後に終了する |

## 4シナリオの期待値

| シナリオ | パス | 上書きする設定 | status | result | attempts | retries | wiremock | rc |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `normal` | `/api/users/123` | なし | 200 | success | 1 | 0 | 1 | 0 |
| `error-500-then-200` | `/api/error-500-then-200` | なし | 200 | success | 2 | 1 | 2 | 0 |
| `ratelimit-429` | `/api/ratelimit` | なし | 429 | retries_exhausted | 4 | 3 | 4 | 0 |
| `slow-5000` | `/api/slow-5000` | `RESPONSE_TIMEOUT_SECONDS=1` | -（出力なし） | timeout | 1 | 0 | 1 | 28 |

- status は標準出力の `CLIENT_STATUS` の値である。`slow-5000` は応答を受けないため `-` になる。
- attempts は総試行、retries はリトライ回数である。retries は attempts から 1 を引いた値に等しい。
- wiremock は、WireMock のジャーナルに残ったそのパスへの受信回数である。
- rc はクライアントの終了コードである。`ratelimit-429` は再試行を使い切っても終了コード 0 になる。

## レポートの見方

レポートは標準出力に出る。1シナリオにつき1行で、シナリオ名、期待値、実測値、合否を並べる。

```text
scenario | expected | actual | result
normal | status=200 result=success attempts=1 retries=0 wiremock=1 rc=0 | status=200 ... | PASS
summary: PASS passed=4 failed=0 not_run=0 failed_scenarios=- elapsed=10s
```

最後の行（`summary:`）は全体の合否、合格と失敗と未実行の件数、失敗したシナリオ名、秒数を示す。

## 失敗時の見方

シナリオが失敗すると、標準エラーに `scenario:`（名前）、`path:`、`overrides:`、`expected:`、`actual:`、
`rerun:`（そのシナリオだけを再実行するコマンド）、`diag:`（クライアントの診断ログ）が出る。
診断ログには認証情報を含めない。

リセット確認が外れた場合は、`FAIL: リセットを確認できないため <名前> を実行しない` と出る。
その後のシナリオは `NOT_RUN` になる。最初に見るべきはリセットの結果である。

## 並列実行の禁止

1台の WireMock に対して、シナリオを並列に実行しない。
リセットと受信回数は同じジャーナルを共有するため、並列にすると互いの結果が混ざる。
固定ポート 8080 と 3128 は、入口のロックで排他する。別のスタックが同じポートを使っているときは実行しない。
