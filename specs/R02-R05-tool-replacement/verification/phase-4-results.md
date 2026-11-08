# フェーズ4 R04（bats-core）の結果記録

## 1. bats の実測（T-R0273、U12〜U15）

実測の環境: Amazon Linux 2023（aarch64）、bash 5.2.15、`/bin/sh` は bash へのリンク。
bats は `mise.toml` の 1.14.0 を使った。shellcheck は 0.11.0 を使った。
probe の材料は、`$KIROCREW_SCRATCH` の一時ディレクトリに作り、実測の後に削除した。

### 1.1 U12: `.bats` を shellcheck の対象に含めるか

- `shellcheck -s bats` は使えない。0.11.0 の方言は `sh`、`bash`、`dash`、`ksh`、`busybox` だけである。
- `shellcheck -s bash` で `.bats` を検査できた。`@test "..." { ... }` の構文は、構文エラーにならずに読まれた。
- 結論: `.bats` は `-s bash` で検査する。`.bats` は shellcheck の対象に含める（T-R0275 で別の呼び出しにする）。

### 1.2 U13: `--filter-tags` と `test_tags`

- `# bats test_tags=unit` の行は、直後の `@test` に効いた。
- `bats --count` は 3 を返した（probe の 3 件）。
- `bats --filter-tags unit`: 2 件（`ok` 1、`not ok` 1。not ok は意図的な失敗）。
- `bats --filter-tags smoke`: 1 件。
- `bats --filter-tags '!unit'`: 1 件。
- 結論: 絞り込みは使える。モードごとの件数を、タグで数えられる。

### 1.3 U14: `sh` の入口から bats を呼ぶときの bash

- Linux（bash 5.2）では、`sh` の入口から bats が動く（probe で確かめた）。
- macOS の bash 3.2 での動作は、この環境では確かめられない。利用者の端末で行う（T-R0293）。未確認。

### 1.4 U15: `BATS_TEST_TMPDIR`、`setup_file`、`teardown_file`、信号

- 通常の実行: `setup_file`、`setup`、テスト、`teardown_file` の順に動く。
  `BATS_TEST_TMPDIR` は、テストの後に残らなかった。`BATS_RUN_TMPDIR` は、実行の後に残らなかった。
- TERM（`kill -TERM`、長い `sleep` の途中）を bats に送ったとき:
  - `setup_file` は動いた。`teardown_file` は動かなかった。
  - bats は終了コード 143 で終わった。
  - bats の一時ディレクトリは残らなかった。
  - テストが起動した子の `sleep` は残った（孤児になった）。probe で止めた。
- 結論: `teardown_file` を信号の後始末に使えない。後始末は、起動する sh の入口の trap で行う。
  子のプロセスを止める処理も、その trap に入れる。`run-bats.sh`（T-R0276）の設計に反映する。

## 2. 反映先

- `plan.md` 13章の U12〜U15 の状態を、この結果に合わせて直す（T-R0273）。
- 次の作業（T-R0274 の赤いテスト、T-R0276 の `run-bats.sh`）は、この結果を前提にする。

## 3. 赤い静的検査（T-R0274）

`tests/m09-execution-and-ci.sh` に、次の4つの検査を追加した。基盤（`tests/bats/`、`tests/lib/run-bats.sh`）がまだ無いため、4つとも失敗する（赤）。

| 検査 | 緑になる条件 |
| --- | --- |
| `t_bats_helpers_define_fakes_once` | `make_base_bin`、`make_fake`、`make_shims`、`no_calls` の定義が `tests/bats/helpers/fakes.bash` の1か所だけ |
| `t_run_bats_entry_keeps_interface` | `tests/lib/run-bats.sh` が、引数なしと不正なモードで終了コード 2 |
| `t_gate_checks_bats_first` | 品質ゲートに `if ! resolve_tool bats 's/^Bats //p' --version; then` があり、yq の照合より前にある |
| `t_gate_triggers_cover_bats_paths` | 品質ゲートに `tests/bats/helpers/` と `tests/lib/run-bats.sh` があり、M02〜M09 それぞれの `tests/bats/<名前>.bats` がある |

結果: `sh tests/m09-execution-and-ci.sh unit` は 239 件中 235 件通過。失敗は上の4件だけ。
追加した行の shellcheck（`-S style`）は 0 件。

注意: `t_gate_checks_bats_first` は、ゲートの行の形を固定している。T-R0275 で書くときは、この1行と同じ文字列にする。

## 4. 入口と品質ゲート（T-R0275、T-R0276）

### 4.1 `tests/lib/run-bats.sh`（T-R0276）

- 引数: `<tests/bats/名前.bats> [unit|smoke|contract]`。引数が 0 個か 3 個以上、モードが不正、ファイルが無い、のどれでも終了コード 2。
- `resolve_tool bats 's/^Bats //p' --version` で固定版を照合する。3つの環境変数は関数の中にある。
- 背景で bats を起動して待つ。TERM と INT は bats に送ってから、143 と 130 で止まる。
- 結果の確認: 引数の 6 通り（引数なし、不正なファイル、不正なモード、unit、smoke、モードなし）の終了コードは、期待どおり。
  失敗する `.bats` を渡すと終了コード 1 を返した。
- shellcheck（`-S style`）は 0 件。

### 4.2 品質ゲート（T-R0275）

- `bats` の照合を、yq より前に置いた（`t_gate_checks_bats_first`）。
- `.bats` を `shellcheck -s bash` で検査する（U12）。`.bats` は、まだ 0 件のため、この時点では実行されない。
- M02〜M08 の入口は、対応する `tests/bats/<名前>.bats` の変更でも走る。`tests/bats/helpers/` と `tests/lib/run-bats.sh` の変更では、全件を走らせる。
- M09 の実行条件に、`tests/bats/m09-execution-and-ci.bats`、`tests/bats/helpers/`、`tests/lib/run-bats.sh` を足した。

### 4.3 検査の結果

`sh tests/m09-execution-and-ci.sh unit` は 239 件中 238 件通過。
残りの失敗は `t_bats_helpers_define_fakes_once` のみ。`tests/bats/helpers/fakes.bash` は T-R0278 で作る。

## 5. 共通部品（T-R0277、T-R0278）

### 5.1 `tests/bats/helpers/fakes.bash`（T-R0278）

- `make_base_bin`、`make_fake`、`make_shims`、`no_calls` の4つを、`tests/m09-execution-and-ci.sh` から移した。本文は変えていない。
- `tests/m09-execution-and-ci.sh` は、この関数を `. "$ROOT/tests/bats/helpers/fakes.bash"` で読む（定義は持たない）。
- 呼び出し側は、先に `TMP`（作業場所）を設定する。
- 検査 `t_bats_helpers_define_fakes_once` は緑になった。

### 5.2 `tests/bats/helpers/common.bash`（T-R0277）

- `common_require_foreground`: 旧の m09 の冒頭の SIGINT の検査を移した。SIGINT が無視されていれば失敗する。
  注意: 旧は終了コード 2 で止まっていた。bats の `setup_file` の失敗は、終了コード 1 になる。文言は同じ。
- `common_setup_tmp`: `TMP` を `BATS_TEST_TMPDIR` にする。bats が検査の後に消すため、`setup` で作って `teardown` で消す形にはしなかった（U15）。
- `common_teardown_tmp`: 追加の後始末は持たない。信号の後始末は `run-bats.sh` の trap が行う（U15）。

### 5.3 品質ゲート

- `.bats` と `.bash` を `shellcheck -s bash` で検査する（`tests/bats/helpers/` の2つは、この検査の対象）。

### 5.4 結果

- `sh tests/m09-execution-and-ci.sh unit`: 239 件中 239 件通過。
- `bash -n` と shellcheck（`-S style`）は、helpers の2つと m09 と gate で 0 件。

## 6. s14 の移行（T-R0279）

- `tests/bats/s14-taskdef-contract.bats` を新規に作った。旧の5件の関数の本文は変えていない。
  各 `@test` の名前は、旧の検査名と同じである。`# bats test_tags=unit` を付けた。
- `bats --count` は 5。名前は旧の5件と一致する。
- 旧の「検査が docker を呼んだ」の確認は、独立の `@test` にすると件数が 6 になる。そのため、各 `@test` の最後で呼ぶ形にした。
- `tests/s14-taskdef-contract.sh` は、引数の検査（`unit` 以外は終了コード 2）と、`tests/lib/run-bats.sh` の呼び出しだけになった。
- 結果:
  - `sh tests/s14-taskdef-contract.sh unit` は終了コード 0。5件すべて `ok`。
  - 不正な引数（`bogus`、引数なし）は終了コード 2。
  - 出力の形式が変わった（旧は `s14 taskdef contract: 5 件中 5 件通過`、新は bats の `ok` の行）。終了コードは旧と同じ。
  - `sh tests/m09-execution-and-ci.sh unit`: 239 件中 239 件通過。
- 確認: 関数が `return 1` で返すと、その `@test` は `not ok` になり、終了コード 1 になる。
- shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。

## 7. m03 の移行（T-R0280）

- `tests/bats/m03-wiremock-scenarios.bats` を新規に作った（17 件）。
  - unit（`test_tags=unit`、6 件）: T-R0256 の 5 件（旧の名前のまま）と、空ファイルと `{} {}` の 1 件（T-R0256 の後の修正で足した）。
  - smoke（`test_tags=smoke`、11 件）: 旧の smoke の手順を 1 件ずつの `@test` にした。
    mapping の JSON と項目、静的検査、壊れた JSON、欠けた項目、経路の登録、200、500、503、429 と Retry-After、0.08 秒以上、4.5 秒以上。
- 旧の smoke は手順の名前を持たなかった。`@test` の名前は手順の内容から付けた（仮の名前）。
- `tests/m03-wiremock-scenarios.sh` は入口になった。
  - unit は `run-bats.sh` を呼ぶ（終了コード 0。6 件すべて `ok`）。
  - smoke は、ロック、WireMock の起動、停止、失敗時の収集を行い、その間に `run-bats.sh` で smoke の 11 件を走らせる。
    bats は背景で起動し、TERM と INT は bats に伝えてから、入口の後始末へ進む。
  - 引数が不正なら終了コード 2。省略時は smoke。
- 確認:
  - `sh tests/m03-wiremock-scenarios.sh smoke` は終了コード 0。11 件すべて `ok`。20 秒。
    終了後、`swsc-` のコンテナとロックは残らなかった。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit` は 239 件中 239 件通過。
- 注意: 旧の m03 は、起動の後に検査を直接行っていた。新しい入口は、bats の終了コードを受けて停止する。
  終了コードは、旧と同じく、失敗のとき非 0 になる。出力の形式は変わった（bats の `ok` の行）。

## 8. m02 の移行（T-R0281）

- `tests/bats/m02-routing-smoke.bats` を新規に作った（5 件、`test_tags=smoke`）。手順の番号は `phase-4-mapping.md` の 4.1 節と同じ。
  1. WireMock に mapping を登録する
  2. proxy 経由で 200 と本文 `m02-routing-ok` を得る
  3. WireMock の受信に `m02-routing` が現れる
  4. Squid の access log に `m02-routing` の行がある
  5. allowlist 外（example.com）は 403 で拒否される
- 手順は順番に実行される（後の検査は前の手順の結果を使う）。`@test` は、ファイルの順番どおりに走る。
- 注意（修正の記録）: 最初の実行では、手順 2 以降が「起動情報が無い」で失敗した。
  Client の呼び出しに `bats` のプロセスの PID を渡していたため。起動は入口の PID で登録されている。
  入口が `SWSC_RUN_ID=$$` を export し、`.bats` はその値を使うように直した。
  同じ仕組みは m04、m05 にも要る（次の段階で同じ方法を使う）。
- `tests/m02-routing-smoke.sh` は入口になった。ロック、起動、停止、失敗時の収集は入口が行い、検査は `run-bats.sh` で走らせる。
- 確認:
  - `sh tests/m02-routing-smoke.sh` は終了コード 0。5 件すべて `ok`。13 秒。残ったコンテナ、ロックは無い。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit` の結果は次の行のとおり。
  - `sh tests/m09-execution-and-ci.sh unit`: 239 件中 239 件通過。

## 9. m04 の移行（T-R0282）

- `tests/bats/m04-test-client.bats` を新規に作った（5 件、`test_tags=smoke`）。手順の番号は `phase-4-mapping.md` の 4.2 節と同じ。
  1. 200 の経路で、出力と WireMock の受信を確かめる
  2. 500 の経路で、500 と Internal Server Error を確かめる
  3. 転送失敗で、終了コードが 0 でなく、`CLIENT_ERROR=curl_exit_` を出す
  4. proxy 未設定で、終了コード 78 と `proxy_not_configured` を出す
  5. `test-client/entrypoint.sh` に WireMock への直接接続の指定が無い
- 失敗の終了コードは `run` で受けた（`$status`）。
- 入口は `tests/m04-test-client.sh`。起動、WireMock の待ち、停止を行い、`SWSC_RUN_ID=$$` を渡す（m02 と同じ修正を最初から入れた）。
- 確認:
  - `sh tests/m04-test-client.sh` は終了コード 0。5 件すべて `ok`。13 秒。コンテナ、ロックは残らず。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit` は 239 件中 239 件通過。

## 10. m05 の移行（T-R0283）

- `tests/bats/m05-proxy-integration.bats` を新規に作った（6 件、`test_tags=smoke`）。手順の番号は `phase-4-mapping.md` の 4.3 節と同じ。
  1. 許可した経路（api.example.com/api/users/123）が 200 と JSON を返す
  2. WireMock の受信に /api/users/123 が現れる
  3. Squid の log に api.example.com/api/users/123 と TCP_MISS/200 がある
  4. WireMock の受信を空にし、allowlist 外（example.com）が 403 になる
  5. allowlist 外の要求は WireMock に届かない（/api/ の受信数が 0）
  6. Squid の log に example.com と TCP_DENIED がある
- 手順は順番に実行される（4 で受信を空にし、5 でその後の件数を数える）。
- 入口は `tests/m05-proxy-integration.sh`。起動、WireMock の待ち、停止を行い、`SWSC_RUN_ID=$$` を渡す。
- 確認:
  - `sh tests/m05-proxy-integration.sh` は終了コード 0。6 件すべて `ok`。14 秒。コンテナ、ロックは残らず。
  - shellcheck（入口は `-S style`、`.bats` は `-s bash`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit` は 239 件中 239 件通過。

### 10.1 phase 4 の残り

- T-R0284 から T-R0287: AGENTS.md、docs、README、対応表（phase-4-mapping.md の対応表）。
- T-R0288: 壊した入力で旧と新が同じ検査で落ちることの確認。
- T-R0289: Docker の smoke（m02〜m05）の実行時間の記録（m02 13 秒、m04 13 秒、m05 14 秒、m03 20 秒は本作業で計測済み）。
- T-R0290、T-R0291、T-R0292: レビュー、品質ゲート、コミット。
- T-R0293: 利用者の macOS（bash 3.2）での確認。未実施。

## 11. 壊した入力の確認（T-R0288）

- s14 の関数の本文: 旧（commit `d1f1c98` の `tests/s14-taskdef-contract.sh`）と新（`tests/bats/s14-taskdef-contract.bats`）の5つの関数を、1つずつ比べた。5件とも本文が同じだった。
- 壊した入力（`squid-config/whitelist.txt` に `bad.example.com` を1行足した）:
  `sh tests/s14-taskdef-contract.sh unit` は終了コード 1。`s14_allowlist_fixed` が `not ok`。
  他の 4 件は通過した。ファイルは、コピーから戻した（`git status` で変更なしを確認）。
- m03 の判定は、unit の 6 件で、壊した JSON、空、複数の値、欠けた項目を入力にして確かめた（section 6、7）。
- m02、m04、m05 の壊した入力は、Docker が要るため、ここでは行わなかった。手順の内容は、旧の本文と同じ（4.1〜4.3 節）。

## 12. 品質ゲート（T-R0291）

- `sh scripts/quality-gate.sh` は `quality-gate: passed`（終了コード 0）。
- 1 回目は `npm run -s lint:md` で失敗した（`phase-4-mapping.md` の 2 か所で、リストの前に空行が無かった）。空行を足して、ゲートを最初から再実行した。
- ゲートの中身: git の差分検査、shellcheck（`-s sh`、`-s bash`）、actionlint、gitleaks（検出 0）、Markdown の lint、
  m02〜m08 の入口（smoke を含む）、S14 の unit、m09 の unit（239 件）と smoke（11 件）。
- 残った一時物: ゲートのログは削除した。`git status --short` に想定外の生成物は無い。

## 13. 残り（T-R0289〜T-R0293）

- T-R0289: m02〜m05 の Docker の smoke は、移行の後に 1 本ずつ直列で実行し、すべて通過（m02 13 秒、m04 13 秒、m05 14 秒）。残った `swsc-` のコンテナは無い。
- T-R0290: commit 4 の evidence-code-review と security-review。メモリが 4 GB 未満のため、まだ実施していない。
- T-R0292: commit 4 のコミット。レビューの後に行う。
- T-R0293: 利用者の macOS（bash 3.2、Colima）の確認。未実施。

## 14. commit 4 の evidence-code-review の指摘と修正（T-R0290）

- evidence-code-review（`claude-sonnet-5.5`、修正前のスナップショット）の指摘:
  - MUST（指摘 1）: 入口が `&` で起動した `run-bats.sh` は、非対話シェルの仕様で INT を無視して始まる。
    そのため、入口が送る `kill -INT` が bats に届かず、入口は bats を待たずに後始末を走らせていた。
  - SHOULD（指摘 2）: TERM でも、入口が子の終了を待たずに後始末へ進んでいた。
  - SHOULD（指摘 3）: `t_run_bats_entry_keeps_interface` の不正なモードの検査が、モードの分岐を通していなかった。
    第2引数に `bogus-mode` を渡すと、それがファイルとして扱われ、「ファイルが無い」の分岐で止まっていた。
- 修正:
  - 4 つの入口（m02、m03、m04、m05）: INT と TERM をどちらも子の bats に TERM として送り、子の終了を待ってから後始末へ進む。
    背景の子は INT を無視して始まるため、INT を TERM に読み替えた。
  - `tests/lib/run-bats.sh`: INT を受けたら TERM を bats に送り、終了を待つ。
  - `t_run_bats_entry_keeps_interface`: 実在する `.bats` を第1引数に渡し、不正なモードを第2引数に渡す検査を足した。
- 確認:
  - 4 つの入口と `run-bats.sh` の `sh -n`、shellcheck（`-S style`）は 0 件。
  - `sh tests/m09-execution-and-ci.sh unit` は 239 件中 239 件通過。
  - 実際の信号を送る確認（m02、Docker あり）。Python の `subprocess` で入口を起動し、7 秒後に信号を送った（背景の `&` の子ではない）。
    - SIGINT: 入口の終了コード 130。コンテナ 0、ロック無し、残ったプロセス無し。
    - SIGTERM: 入口の終了コード 143。コンテナ 0、ロック無し、残ったプロセス無し。
- 未確認: m03、m04、m05 の信号の確認は、m02 と同じ仕組みだが、個別には実行していない。
- 上の「未確認」は、後から確認した。m03、m04、m05 も、Python の `subprocess` で起動し、8 秒後に SIGINT と SIGTERM を送った。
  6 回すべて、入口の終了コードは 130（INT）または 143（TERM）。コンテナ 0、ロック無し、残ったプロセス無し。
  - 注意: 残ったプロセスの確認に `pgrep -f` を使うと、確認のコマンド自身が一致する。`ps` の出力で確かめ直し、残りが無いことを確認した。
- 修正後の evidence-code-review（範囲を絞った再レビュー、`claude-sonnet-5.5`、修正後のスナップショット）: 指摘なし。
  4 つの入口の trap（TERM と INT の forward と wait）、`run-bats.sh` の INT と TERM の trap、
  `t_run_bats_entry_keeps_interface` の不正なモードの分岐、のすべてが修正どおりであることを確かめた。
  なお、Low の 1 件（m02 の trap の切り替えの前の数ミリ秒）は、実害が示せないため指摘にしない。
- 修正後の security-review: 実施中（`7d24c0cf6e2bbab6`）。結果を待ってから、commit 4 のコミットを判断する。
- 修正後の security-review（`7d24c0cf6e2bbab6`、`claude-sonnet-5.5`）: Critical、High、Medium は無し。Low 2 件、要確認 1 件。
  - Low 1（受け入れ）: `&` で起動した直後、子の PID を trap に渡す前の数ミリ秒に信号が届くと、子が残りうる。
    窓は数ミリ秒で、取りこぼしの問題にとどまる。信号を正確にその時点で送る経路は、利用者の操作では現実的でない。受け入れる。
  - Low 2（対応）: `run-bats.sh` の作業ディレクトリが、mise の設定の解決に影響しうる。`run-bats.sh` の冒頭で `cd "$ROOT"` を入れた。
  - 要確認（確認済み）: TERM で bats を止めたとき、`/tmp/bats-run-*` が残るか。
    13 章と前の確認（1.4 節）で、TERM の後に残りが無いことを確かめた。`BATS_TEST_TMPDIR` は bats が消す。
- `run-bats.sh` の `cd` の修正の後、shellcheck（0 件）と `sh tests/m09-execution-and-ci.sh unit`（239 件中 239 件通過）を確かめた。

## 15. macOS の確認（T-R0293）

利用者の端末（macOS、arm64、Homebrew の mise）で実施した。

- mise: 2026.11.4（`min_version` の 2026.11.3 以上を満たす）
- `mise install --locked shellcheck actionlint gitleaks bats jq yq`: 成功（bats@1.14.0、jq@1.8.2、yq@4.54.2、gitleaks@8.30.1、actionlint@1.7.12）
- `mise which jq` と `mise exec -- jq --version`: `jq-1.8.2`
- `sh` が使う bash: GNU bash 3.2.57（`/bin/bash --version`）
- `sh tests/s14-taskdef-contract.sh unit`: 5 件すべて `ok`、終了コード 0（bash 3.2）
- `sh tests/m03-wiremock-scenarios.sh unit`: 6 件すべて `ok`、終了コード 0（bats は mise の実体を使用）

注意:

- 最初の確認では、手元のブランチが `main` のままで、bats の入口と `.bats` が無かった。`feature/r02-r05-tool-replacement` に切り替えて確認した。
- `~/.tool-versions` の `awscli`、`node`、`python` は、リポジトリの lockfile に無い。これは利用者の全体設定で、リポジトリには影響しない。警告として扱う。
- mise が `actionlint` の非推奨を警告した（`jactionlint` への移行を勧める）。リポジトリの版（1.7.12）は現状のまま。移行の判断は別の作業として扱う。

結論: T-R0293 は完了。bash 3.2 での s14 と m03 の unit の動作を確かめた。T-R0294（段階2の前提）は満たされた。
