# フェーズ5 R04 段階2（m06、m07）の旧の記録（T-R0294）

利用者の端末で、macOS の確認（T-R0293）が済んだ後に、旧の unit を実行して記録した。
実行の環境は、この作業の Linux の環境（bash 5.2）である。

## 1. 旧のスクリプトの形

| 項目 | m06-client-resilience.sh | m07-scenario-isolation.sh |
| --- | --- | --- |
| 行数 | 595 | 699 |
| 既定のモード | `smoke`（`MODE=${1:-smoke}`） | `smoke`（`MODE=${1:-smoke}`） |
| 検査の書き方 | `expect`（検査名、期待出力、期待終了コード、コマンド） | `check`（20 件）と `expect_rc`、`expect_out`、`expect_err`（26 件） |
| 信号の検査 | なし | 4 行（`signal.SIG*` を使う Python の検査） |
| 他のテストの本文を読む検査 | 未確認（T-R0317 で確認する） | 未確認 |

## 2. unit の旧の判定（実行結果）

| スクリプト | 終了コード | 件数 | 出力（旧） | 実行時間 |
| --- | --- | --- | --- | --- |
| `sh tests/m06-client-resilience.sh unit` | 0 | 133 | `M06 unit: 133件すべて通過` | 2 秒 |
| `sh tests/m07-scenario-isolation.sh unit` | 0 | 45 | `M07 scenario isolation unit passed (45 checks)` | 4 秒 |

注意: 旧の unit は、検査の 1 件ずつの結果を出さない。件数と、全体の判定だけを出す。
新しい `.bats` では、件数が一致することと、検査名が旧と一致することを確かめる。

## 3. smoke の旧の件数（作業中の記録）

- m07 の smoke: 61 件（本作業の品質ゲートの実行で `M07 scenario isolation smoke passed (61 checks)`）。
- m06 の smoke: 件数は未記録。`M06 smoke: 新基盤の通し検査すべて通過` と出る。件数は、T-R0295 で数える。

## 4. 未決（次の作業で確かめる）

- m06 の `expect` の 133 件の名前の一覧（T-R0295 で、1 件ずつ `@test` にする前に一覧にする）。
- m07 の信号の検査 4 行（`unit_signal_exit_codes` の `kill`、Python の `signal`）の移し方（T-R0297）。
- 他のテストの本文を読む検査（plan 11.4 節）の一覧。

## 5. m07 の移行（T-R0296〜T-R0298、unit の部分）

- `tests/bats/m07-scenario-isolation.bats` を新規に作った（42 件）。
  旧の unit の検査名（`expect_*` と `check` のラベル）を、そのまま `@test` の名前にした。
  検査の補助（`expect_rc`、`expect_out`、`expect_err`、`expect_static_reject`、`verify_with`）は、`.bats` の中に移し、
  失敗は `return 1` で返す（旧の `record_fail` と同じ文言を標準エラーに出す）。
- 件数の対応（旧の 45 と新の 42 の差は 3 件）:
  - 旧の `unit_verify_reset_journal` を包む `check`（`m07_reset_excludes_internal`）は、中の 9 件と重複するため、移していない（−1）。
  - 旧の `unit_error_500_then_200_definitions_match` と `unit_no_docker` は、関数の中で `total` を余分に数えていた（−2）。
  - 検査の内容は、旧の `expect` と `check` の全件を移している。
- 信号の検査（`unit_signal_exit_codes`）は、`.bats` の中で、旧の入口のファイルの中身を `grep` で確かめる形で移した（字句のまま）。
- 「Docker を呼ばない」（`unit_no_docker`）は、偽の docker を PATH の先頭に置き、この `.bats` を入れ子の bats で走らせて確かめる。入れ子の実行では、この検査を飛ばす（`M07_NESTED`）。
- `tests/m07-scenario-isolation.sh` は、unit を `tests/lib/run-bats.sh` へ渡す入口になった。
  smoke は、まず bats の unit（42 件）を走らせ、続けて従来の smoke（16 件）を実行する。
- 結果:
  - `bats --count`: 42。`sh tests/m07-scenario-isolation.sh unit`: 42 件すべて `ok`、終了コード 0（15 秒）。
  - `sh tests/m07-scenario-isolation.sh`（Docker の smoke）: 終了コード 0。smoke の 16 件すべて通過。155 秒。コンテナ、ロックは残らず。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit`: 239 件中 239 件通過。

### 5.1 計画からの違い

- 計画（T-R0298）は、入口を薄くすると書いている。しかし、smoke の検査（16 件）は、起動と停止の仕組み（`check` と `total` を使う）を持つ。
  そのため、smoke は入口の `sh` に残した。smoke の bats への移行は、別の段階で行う（今回の作業には含めない）。
  この判断は、利用者の確認を受けていない。

## 6. m06 の移行（T-R0295、unit の部分）

- `tests/bats/m06-client-resilience.bats` を新規に作った（133 件）。
  旧の `expect` の 133 件を、1 件ずつ `@test` にした。名前は旧の `expect` の名前と同じ（重複は無い）。
- 移し方: 旧の `expect` の文（継続行と、改行を含む二重引用符を含む）を、スクリプトで機械的に取り出した。
  検査の補助（`expect`、`ra_headers`、`cfg_run`、`ep_obs`、`ep_text_check`）も、旧の本文をそのまま使った（`expect` だけは、失敗を `return 1` で返す形に直した）。
  取り出しに使ったスクリプトは作業の後に削除した。
- 偽の curl と sleep（`ep_obs`）は、旧の本文のままである。一時ディレクトリは、旧と同じく `KIROCREW_SCRATCH` か `TMPDIR` の下に作る。
- `tests/m06-client-resilience.sh` は、unit を `tests/lib/run-bats.sh` へ渡す入口になった。
  smoke は、bats の unit（133 件）を先に走らせ、続けて従来の smoke（`run_smoke`）を実行する。
  smoke の検査は、起動と停止の仕組み（`smoke_must` と、ロックと trap）に依存するため、
  入口の `sh` に残した（m07 と同じ判断）。
- 結果:
  - `bats --count`: 133（旧の unit の件数と一致）。
    `sh tests/lib/run-bats.sh tests/bats/m06-client-resilience.bats unit`: 133 件すべて `ok`、14 秒。
  - `sh tests/m06-client-resilience.sh unit`: 終了コード 0、133 件すべて `ok`。
  - `sh tests/m06-client-resilience.sh smoke`（Docker）: 終了コード 0。`M06 smoke: 新基盤の通し検査すべて通過`。33 秒。コンテナ、ロックは残らず。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit`: 239 件中 239 件通過。
- 注意: `bash -n` は `.bats` の `@test` 構文を解釈できないため、検査には使えない。`.bats` の構文の確認は `bats --count` で行う。

### 6.1 計画からの違い（m07 と同じ）

- smoke の検査は、入口の `sh` に残した。計画の「入口を薄くする」とは、smoke の部分で異なる。移すかどうかは、利用者の確認を受けていない。
