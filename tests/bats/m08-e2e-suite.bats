#!/usr/bin/env bats
# M08 代表4シナリオの E2E スイートの検査（unit）。Docker を使わず、シナリオ表、実測値の抽出、実行ループ、レポートをスタブで確かめる。
# 旧の tests/m08-e2e-suite.sh の unit の検査名を、そのまま @test の名前にした。
# 入口は tests/m08-e2e-suite.sh（unit は tests/lib/run-bats.sh を呼ぶ）。
# 検査の本体（unit_*）は、旧の入口と同じ関数を使う。入口の関数は M08_LIB_ONLY=1 で読み込む。

# shellcheck disable=SC2034,SC2329 # この検査は入口（tests/m08-e2e-suite.sh）を . で読み込んで使う。M08_LIB_ONLY、M08_LIB_ROOT、RESULTS、smoke_started は入口が読み、関数は入口の run_suite などから呼ばれる。shellcheck は別ファイルを追えないため、この2件を外す。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  WORK=$TMP
  SELF=$ROOT/tests/m08-e2e-suite.sh
  # 入口の関数だけを読む。M08_LIB_ONLY=1 のときは本体（main）を走らせない。
  M08_LIB_ONLY=1
  M08_LIB_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$SELF"
  unset M08_LIB_ONLY M08_LIB_ROOT
  # 入口は set -eu で読み込まれる。bats の変数を守るため、-u を戻す。
  set +u
  # 入口の main と同じく、シナリオ表の関数を読み込む。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/scenario-lib.sh"
}

teardown() {
  common_teardown_tmp
}

# smoke の信号の検査は、入口（tests/m08-e2e-suite.sh smoke）が取った親のロックの下でだけ動かす。
# 直接起動（bats を単独で実行）では、ロックを取らずに skip する。ロックを取ると、TERM で止まったときに
# teardown が動かず、ロックが残るため。
smoke_require_lock() {
  if [ "${SWSC_LOCK_HELD:-0}" != 1 ]; then
    skip '入口 tests/m08-e2e-suite.sh smoke から実行する（ロックは入口が取る）'
  fi
}

# ---- 検査の本体（旧の unit_* 関数。判定は関数の終了コード） ----

# ---- unit: 引数と既定の順 ----

unit_arg_codes() {
  _d="$WORK/args"
  make_shim "$_d"
  rc_is 2 env PATH="$_d/shim:$PATH" sh "$SELF" bogus || return 1
  rc_is 2 env PATH="$_d/shim:$PATH" sh "$SELF" unit normal || return 1
  rc_is 2 env PATH="$_d/shim:$PATH" sh "$SELF" smoke no-such || return 1
  rc_is 2 env PATH="$_d/shim:$PATH" sh "$SELF" smoke slow-100 || return 1
  # 引数の誤りは起動より前に止まる。
  [ ! -e "$_d/calls" ]
}

unit_no_docker() {
  # 入れ子の unit 実行では、この検査を飛ばして再帰を防ぐ（M08_NESTED）。
  if [ -n "${M08_NESTED:-}" ]; then
    return 0
  fi
  _d="$WORK/nocompose"
  make_shim "$_d"
  _rc=0
  env PATH="$_d/shim:$PATH" M08_NESTED=1 sh "$SELF" unit >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] && [ ! -e "$_d/calls" ]
}

unit_default_order() {
  [ "$E2E_ORDER" = "normal error-500-then-200 ratelimit-429 slow-5000" ]
}

# ---- unit: シナリオ表 ----

unit_scenario_table() {
  [ "$(scenario_path normal)" = /api/users/123 ] || return 1
  [ "$(scenario_path error-500-then-200)" = /api/error-500-then-200 ] || return 1
  [ "$(scenario_path ratelimit-429)" = /api/ratelimit ] || return 1
  [ "$(scenario_path slow-5000)" = /api/slow-5000 ] || return 1
  [ "$(scenario_expect normal)" = 'status=200 result=success attempts=1 retries=0 wiremock=1 rc=0' ] || return 1
  [ "$(scenario_expect error-500-then-200)" = 'status=200 result=success attempts=2 retries=1 wiremock=2 rc=0' ] || return 1
  [ "$(scenario_expect ratelimit-429)" = 'status=429 result=retries_exhausted attempts=4 retries=3 wiremock=4 rc=0' ] || return 1
  [ "$(scenario_expect slow-5000)" = 'status=- result=timeout attempts=1 retries=0 wiremock=1 rc=28' ] || return 1
  [ -z "$(scenario_env normal)" ] || return 1
  [ "$(scenario_env slow-5000)" = RESPONSE_TIMEOUT_SECONDS=1 ] || return 1
  rc_is 2 scenario_expect slow-100
}

# 429 の総試行とリトライは固定値で書いてある。retry-lib の既定値と突き合わせ、既定が変わったら気づかせる。
unit_retry_defaults() {
  _d=$(unset RETRY_MAX_ATTEMPTS_429; . "$ROOT/test-client/retry-lib.sh"; apply_config_defaults; printf '%s' "$RETRY_MAX_ATTEMPTS_429") || return 1
  [ "$_d" = 3 ] || return 1
  [ "$(scenario_expect ratelimit-429)" = "status=429 result=retries_exhausted attempts=$((_d + 1)) retries=$_d wiremock=$((_d + 1)) rc=0" ]
}

# ---- unit: 実測値の抽出 ----

unit_parse_client() {
  _d="$WORK/parse"
  write_canned "$_d"
  : >"$_d/empty.out"
  : >"$_d/empty.err"
  [ "$(parse_client "$_d/normal.out" "$_d/normal.err" 0 1)" = "$(scenario_expect normal)" ] || return 1
  [ "$(parse_client "$_d/error-500-then-200.out" "$_d/error-500-then-200.err" 0 2)" = "$(scenario_expect error-500-then-200)" ] || return 1
  [ "$(parse_client "$_d/ratelimit-429.out" "$_d/ratelimit-429.err" 0 4)" = "$(scenario_expect ratelimit-429)" ] || return 1
  [ "$(parse_client "$_d/slow-5000.out" "$_d/slow-5000.err" 28 1)" = "$(scenario_expect slow-5000)" ] || return 1
  # 読めない項目は - になり、期待値と一致しない。
  [ "$(parse_client "$_d/empty.out" "$_d/empty.err" 0 1)" = 'status=- result=- attempts=- retries=0 wiremock=1 rc=0' ] || return 1
  # 受信回数が - のときは、そのまま - を出す。
  [ "$(parse_client "$_d/normal.out" "$_d/normal.err" 0 -)" = 'status=200 result=success attempts=1 retries=0 wiremock=- rc=0' ]
}

# ---- unit: シナリオ固有の検査 ----

unit_extra_checks() {
  _d="$WORK/extra"
  write_canned "$_d"
  for _n in normal error-500-then-200 ratelimit-429 slow-5000; do
    extra_checks "$_n" "$_d/$_n.out" "$_d/$_n.err" 2>/dev/null || return 1
  done
  # 崩した例は落ちる。待機、上限、標準出力、retry 行の数をそれぞれ崩す。
  sed 's/wait=1$/wait=2/' "$_d/error-500-then-200.err" >"$_d/bad500.err"
  ! extra_checks error-500-then-200 "$_d/error-500-then-200.out" "$_d/bad500.err" 2>/dev/null || return 1
  sed 's/capped=0/capped=1/' "$_d/ratelimit-429.err" >"$_d/bad429.err"
  ! extra_checks ratelimit-429 "$_d/ratelimit-429.out" "$_d/bad429.err" 2>/dev/null || return 1
  sed 's/retry_after=2 wait=2/retry_after=2 wait=1/' "$_d/ratelimit-429.err" >"$_d/badwait.err"
  ! extra_checks ratelimit-429 "$_d/ratelimit-429.out" "$_d/badwait.err" 2>/dev/null || return 1
  grep -v 'retry=2/3' "$_d/ratelimit-429.err" >"$_d/bad429n.err"
  ! extra_checks ratelimit-429 "$_d/ratelimit-429.out" "$_d/bad429n.err" 2>/dev/null || return 1
  printf 'CLIENT_STATUS=200\n' >"$_d/badslow.out"
  ! extra_checks slow-5000 "$_d/badslow.out" "$_d/slow-5000.err" 2>/dev/null
}

# 受信回数が - のシナリオは wiremock_count を呼ばず、- のまま PASS になる。
unit_dash_not_called() {
  _d="$WORK/dash"
  mkdir -p "$_d"
  # shellcheck disable=SC2030 # RESULTS の変更は、この部分シェル（サブシェル）の中だけで使う隔離が意図。親の RESULTS は変えない
  ( RESULTS="$_d/results"
    scenario_expect() { printf '%s\n' 'status=200 result=success attempts=1 retries=0 wiremock=- rc=0'; }
    run_client() { canned_out normal >"$3/out"; canned_err normal >"$3/err"; return 0; }
    wiremock_count() { printf x >>"$_d/wm-called"; printf 0; }
    run_one normal ) >"$_d/out" 2>"$_d/err" || true
  [ ! -e "$_d/wm-called" ] || return 1
  grep -Fq 'normal|PASS|' "$_d/results"
}

# run_client は、パスを TEST_API_PATH で渡し、上書き設定を -e で渡す。
unit_run_client_args() {
  _d="$WORK/rc-args"
  mkdir -p "$_d/shim" "$_d/out" "$_d/run"
  # Why: swsc_client_once は起動情報のファイル（イメージ名より後ろの引数）を読むため、同じ名前で作る。
  printf 'swsc-client:e2e\n' >"$_d/run/swsc-client-$$.args"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s"\nexit 28\n' "$_d/args" >"$_d/shim/docker"
  chmod +x "$_d/shim/docker"
  _rc=0
  # shellcheck disable=SC2030 # PATH の変更は、この部分シェル（サブシェル）の中だけで使う隔離が意図。親の PATH は変えない
  ( PATH="$_d/shim:$PATH"; SWSC_E2E_DIR="$_d" run_client /api/slow-5000 RESPONSE_TIMEOUT_SECONDS=1 "$_d/out" ) || _rc=$?
  [ "$_rc" -eq 28 ] || return 1
  grep -Fxq 'TEST_API_PATH=/api/slow-5000' "$_d/args" || return 1
  grep -Fxq 'RESPONSE_TIMEOUT_SECONDS=1' "$_d/args" || return 1
  grep -Fxq 'TEST_API_BASE_URL=http://api.example.com' "$_d/args" || return 1
  grep -Fxq 'swsc-client:e2e' "$_d/args"
}

# ---- unit: 実行ループ ----

unit_suite_all_pass() {
  _d="$WORK/all-pass"
  mkdir -p "$_d"
  _rc=0
  ( suite_sandbox "$_d"; run_suite ) >"$_d/report" 2>"$_d/err" || _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  [ "$(grep -c '|PASS|' "$_d/results")" -eq 4 ] || return 1
  grep -Fq 'scenario normal elapsed=' "$_d/err" || return 1
  tail -n 1 "$_d/report" | grep -Fq 'summary: PASS passed=4 failed=0 not_run=0 failed_scenarios=- elapsed='
}

unit_suite_order() {
  _d="$WORK/order"
  mkdir -p "$_d/a" "$_d/b"
  ( suite_sandbox "$_d/a"; run_suite ) >"$_d/a/report" 2>"$_d/a/err" || true
  ( suite_sandbox "$_d/b"; run_suite slow-5000 ratelimit-429 error-500-then-200 normal ) >"$_d/b/report" 2>"$_d/b/err" || true
  [ "$(sort "$_d/a/results")" = "$(sort "$_d/b/results")" ] || return 1
  [ "$(grep -c '|PASS|' "$_d/b/results")" -eq 4 ]
}

# 3番目だけ不一致にしても、4番目まで実行され、終了コードは1になる。
unit_suite_continue() {
  _d="$WORK/continue"
  mkdir -p "$_d"
  _rc=0
  ( suite_sandbox "$_d"
    wiremock_count() { # パス
      case "$1" in
        /api/ratelimit) printf 5 ;;
        *) canned_wm "$(name_of_path "$1")" ;;
      esac
    }
    run_suite ) >"$_d/report" 2>"$_d/err" || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  grep -Fq 'ratelimit-429|FAIL|' "$_d/results" || return 1
  grep -Fxq '/api/slow-5000' "$_d/calls" || return 1
  grep -Fq 'slow-5000|PASS|' "$_d/results"
}

# 3番目のリセット確認が失敗したら、3番目は FAIL（未実行）、残りは NOT_RUN で、クライアントを呼ばない。
unit_suite_reset_stop() {
  _d="$WORK/reset-stop"
  mkdir -p "$_d"
  _rc=0
  ( suite_sandbox "$_d"
    suite_reset() { # 3回目だけ失敗させる
      _c=$(cat "$_d/n" 2>/dev/null || printf 0)
      _c=$((_c + 1))
      printf '%s' "$_c" >"$_d/n"
      [ "$_c" -ne 3 ]
    }
    run_suite ) >"$_d/report" 2>"$_d/err" || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  [ "$(wc -l <"$_d/calls" | tr -d ' ')" -eq 2 ] || return 1
  grep -Fq 'ratelimit-429|FAIL|' "$_d/results" || return 1
  grep -Fq 'slow-5000|NOT_RUN|' "$_d/results"
}

# ---- unit: レポートと失敗出力 ----

unit_report_pass() {
  _d="$WORK/report-pass"
  mkdir -p "$_d"
  printf '%s\n' 'normal|PASS|e1|a1' 'error-500-then-200|PASS|e2|a2' 'ratelimit-429|PASS|e3|a3' 'slow-5000|PASS|e4|a4' >"$_d/r"
  report_all "$_d/r" 3 >"$_d/out" 2>/dev/null || return 1
  tail -n 1 "$_d/out" | grep -Fxq 'summary: PASS passed=4 failed=0 not_run=0 failed_scenarios=- elapsed=3s'
}

# 合格、失敗、未実行の件数と、合計が実行対象の数に等しいこと。
unit_report_mixed() {
  _d="$WORK/report-mixed"
  mkdir -p "$_d"
  printf '%s\n' 'normal|PASS|e1|a1' 'error-500-then-200|FAIL|e2|not_run' 'ratelimit-429|NOT_RUN|e3|not_run' 'slow-5000|NOT_RUN|e4|not_run' >"$_d/r"
  report_all "$_d/r" 5 >"$_d/out" 2>/dev/null && return 1
  tail -n 1 "$_d/out" | grep -Fxq 'summary: FAIL passed=1 failed=1 not_run=2 failed_scenarios=error-500-then-200 elapsed=5s' || return 1
  grep -Fq 'ratelimit-429 | e3 | not_run | NOT_RUN' "$_d/out"
}

unit_report_no_files() {
  _d="$WORK/report-files"
  mkdir -p "$_d/empty"
  printf '%s\n' 'normal|PASS|e1|a1' >"$_d/r"
  ( cd "$_d/empty" && report_all "$_d/r" 1 ) >/dev/null 2>&1 || true
  [ -z "$(ls -A "$_d/empty")" ]
}

# 失敗出力: 再現コマンドと診断ログがあり、認証情報の形がない。上書きがなければ none と出す。
unit_fail_detail() {
  _d="$WORK/fail-detail"
  mkdir -p "$_d"
  canned_err slow-5000 >"$_d/err"
  fail_detail slow-5000 /api/slow-5000 RESPONSE_TIMEOUT_SECONDS=1 "$(scenario_expect slow-5000)" \
    'status=- result=timeout attempts=2 retries=0 wiremock=1 rc=28' "$_d/err" 2>"$_d/fd" || return 1
  grep -Fq 'scenario: slow-5000' "$_d/fd" || return 1
  grep -Fq 'sh tests/m08-e2e-suite.sh smoke slow-5000' "$_d/fd" || return 1
  grep -Fq 'RESPONSE_TIMEOUT_SECONDS=1' "$_d/fd" || return 1
  grep -Fq 'CLIENT_DIAG result=timeout' "$_d/fd" || return 1
  ! grep -Eq 'Authorization|Bearer|[0-9]{12}|arn:aws' "$_d/fd" || return 1
  fail_detail normal /api/users/123 '' "$(scenario_expect normal)" 'status=429 result=success attempts=1 retries=0 wiremock=1 rc=0' "$_d/err" 2>"$_d/fd2" || return 1
  grep -Fq 'overrides: none' "$_d/fd2"
}

# 後始末の reset は、WireMock が実行中のときだけ送る。実行中でなければ送らず、理由を残す。
# Why: smoke 本体が先に down するため、後始末の reset は停止後に呼ばれ、必ず失敗して ignored と出ていた。
unit_cleanup_reset() {
  _d="$WORK/cleanup-reset"
  mkdir -p "$_d/shim"
# shellcheck disable=SC2016 # 単一引用符の中の $FAKE_RUNNING は、偽の docker（子の sh）が展開する
  printf '#!/bin/sh\nif [ "$FAKE_RUNNING" = 1 ]; then echo true; else echo false; fi\nexit 0\n' >"$_d/shim/docker"
  chmod +x "$_d/shim/docker"

# shellcheck disable=SC1090,SC2031 # $SELF を M08_LIB_ONLY=1 で関数だけ読む（自己参照のため解析しない）。PATH の変更は unit_run_client_args のサブシェルで隔離済みで、ここは親の PATH を読む
  ( M08_LIB_ONLY=1 M08_LIB_ROOT="$ROOT" . "$SELF"
    smoke_started=1
    wiremock_reset() { printf x >>"$_d/reset-running"; }
    PATH="$_d/shim:$PATH" FAKE_RUNNING=1 cleanup_reset ) 2>"$_d/err-running" || return 1
  grep -Fxq 'cleanup: reset attempted' "$_d/err-running" || return 1
  grep -Fxq 'cleanup: reset ok' "$_d/err-running" || return 1
  [ -e "$_d/reset-running" ] || return 1

# shellcheck disable=SC1090,SC2031 # $SELF を M08_LIB_ONLY=1 で関数だけ読む（自己参照のため解析しない）。PATH の変更は unit_run_client_args のサブシェルで隔離済みで、ここは親の PATH を読む
  ( M08_LIB_ONLY=1 M08_LIB_ROOT="$ROOT" . "$SELF"
    smoke_started=1
    wiremock_reset() { printf x >>"$_d/reset-stopped"; }
    PATH="$_d/shim:$PATH" FAKE_RUNNING=0 cleanup_reset ) 2>"$_d/err-stopped" || return 1
  grep -Fxq 'cleanup: reset skipped (not running)' "$_d/err-stopped" || return 1
  grep -Fq 'cleanup: reset attempted' "$_d/err-stopped" && return 1
  [ ! -e "$_d/reset-stopped" ] || return 1

# shellcheck disable=SC1090,SC2031 # $SELF を M08_LIB_ONLY=1 で関数だけ読む（自己参照のため解析しない）。PATH の変更は unit_run_client_args のサブシェルで隔離済みで、ここは親の PATH を読む
  ( M08_LIB_ONLY=1 M08_LIB_ROOT="$ROOT" . "$SELF"
    smoke_started=0
    wiremock_reset() { printf x >>"$_d/reset-unstarted"; }
    PATH="$_d/shim:$PATH" FAKE_RUNNING=1 cleanup_reset ) 2>"$_d/err-unstarted" || return 1
  grep -Fxq 'cleanup: reset skipped (not started)' "$_d/err-unstarted" || return 1
  [ ! -e "$_d/reset-unstarted" ]
}

# 文書の検査。文書があり、README から参照され、4シナリオの名前が書かれていること。
# 識別情報の検査（12桁の数字、arn:aws）は、gitleaks の規則（品質ゲート）へ移した。このunitは確かめない。
unit_doc() {
  _doc="$ROOT/docs/E2Eテスト.md"
  [ -f "$_doc" ] || return 1
  grep -Fq '(docs/E2Eテスト.md)' "$ROOT/README.md" || return 1
  for _n in normal error-500-then-200 ratelimit-429 slow-5000; do
    grep -Fq "$_n" "$_doc" || return 1
  done
}

# 件数の取り出し: 空、null、文字列、負の数は失敗し、0 と正の整数は通る（T-R0260）。
unit_count_extraction_rejects_empty_and_null() {
  wiremock_count_value "" >/dev/null 2>&1 && return 1
  wiremock_count_value '{"count":null}' >/dev/null 2>&1 && return 1
  wiremock_count_value '{"count":"3"}' >/dev/null 2>&1 && return 1
  wiremock_count_value '{"count":-1}' >/dev/null 2>&1 && return 1
  [ "$(wiremock_count_value '{"count": 3}')" = 3 ] || return 1
  [ "$(wiremock_count_value '{"count":0}')" = 0 ]
}


# ---- 検査（旧の unit_main の並びと同じ。名前は旧の check の名前） ----

# bats test_tags=unit
@test "引数: 不正なモード、unit への名前、未定義、対象外は終了コード2" {
  unit_arg_codes
}

# bats test_tags=unit
@test "m08_count_extraction: 空、null、文字列、負の数は失敗し、0と正の整数は通る" {
  unit_count_extraction_rejects_empty_and_null
}

# bats test_tags=unit
@test "既定の順は normal、error-500-then-200、ratelimit-429、slow-5000" {
  unit_default_order
}

# bats test_tags=unit
@test "Docker を呼ばない（docker を PATH の先頭に置く）" {
  unit_no_docker
}

# bats test_tags=unit
@test "m08_scenario_expectations: シナリオ表（パス、期待値、上書き設定）" {
  unit_scenario_table
}

# bats test_tags=unit
@test "429の4と3が retry-lib の既定値と整合" {
  unit_retry_defaults
}

# bats test_tags=unit
@test "実測値の抽出（4種と、読めない項目は -）" {
  unit_parse_client
}

# bats test_tags=unit
@test "固有の検査（正しい例は通り、崩した例は落ちる）" {
  unit_extra_checks
}

# bats test_tags=unit
@test "受信回数が - のシナリオは wiremock_count を呼ばない" {
  unit_dash_not_called
}

# bats test_tags=unit
@test "run_client が TEST_API_PATH と上書き設定を渡す" {
  unit_run_client_args
}

# bats test_tags=unit
@test "run_suite: 全件 PASS で終了コード0、経過時間の行" {
  unit_suite_all_pass
}

# bats test_tags=unit
@test "run_suite: 順序を逆にしても各シナリオの結果が同じ" {
  unit_suite_order
}

# bats test_tags=unit
@test "run_suite: 不一致で続行し、終了コード1" {
  unit_suite_continue
}

# bats test_tags=unit
@test "run_suite: リセット確認の失敗で停止（残りは NOT_RUN）" {
  unit_suite_reset_stop
}

# bats test_tags=unit
@test "レポート: 全件 PASS の要約行" {
  unit_report_pass
}

# bats test_tags=unit
@test "レポート: FAIL と NOT_RUN の件数と未実行の行" {
  unit_report_mixed
}

# bats test_tags=unit
@test "レポート: ファイルを作らない" {
  unit_report_no_files
}

# bats test_tags=unit
@test "失敗出力: 再現コマンドと診断ログ、認証情報の形がない" {
  unit_fail_detail
}

# bats test_tags=unit
@test "m08_term_cleanup: 後始末の reset は実行中だけ送り、未実行なら skipped を出す（TERM の実機は smoke の signal-case）" {
  unit_cleanup_reset
}

# bats test_tags=unit
@test "文書: docs/E2Eテスト.md があり、README から参照され、4シナリオ名と禁止の形を含まない" {
  unit_doc
}

# ---- smoke: 信号の検査の本体（旧の入口の関数を字句のまま移す。T-R0308） ----

# 子を起動し、管理APIが応答してから信号を送り、終了コードを標準出力へ出す。
# Why: sh は前景のコマンドが終わるまでトラップを処理しないため、待機は短い sleep のポーリングにする。
# 子の信号の既定の動作を preexec_fn で戻す。バックグラウンドのシェルは INT を無視するため。
smoke_child_signal() { # 信号名 子の一時ディレクトリ
  python3 - "$SELF" "$1" "$WIREMOCK_URL" "$2" "$WORK/child-$1.err" <<'PY'
import http.client
import os
import signal
import subprocess
import sys
import time
import urllib.request

self_path, sig_name, admin, tmp_parent, err_path = sys.argv[1:6]
sig = {"INT": signal.SIGINT, "TERM": signal.SIGTERM}[sig_name]
# Why: 親が持つロックを子が取り直さないよう、SWSC_LOCK_HELD=1 を渡す（test:ci と同じ規約）。
env = dict(os.environ, M08_NESTED="1", SWSC_LOCK_HELD="1", M08_TMP_ROOT=tmp_parent)


def restore_default_signals():
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, signal.SIG_DFL)


def note(message):
    # 診断は標準エラーへ出す。標準出力は呼び出し側が終了コードとして読むため、混ぜない。
    sys.stderr.write(f"signal-case {sig_name}: {message}\n")


def stop_child(proc):
    # 準備できなかった子も、信号で止めて後始末を走らせる。
    # Why not proc.kill(): SIGKILL は子のトラップを走らせず、管理対象の資源が残るため。
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


started = time.time()
with open(err_path, "w") as err:
    proc = subprocess.Popen(["sh", self_path, "smoke"], env=env,
                            stdout=subprocess.DEVNULL, stderr=err,
                            preexec_fn=restore_default_signals)
    ready = False
    last_error = "なし"
    deadline = started + 180
    while time.time() < deadline and proc.poll() is None:
        try:
            with urllib.request.urlopen(admin + "/__admin/mappings", timeout=2) as resp:
                if resp.status == 200:
                    ready = True
                    break
        # HTTPException は OSError ではない。ここで落とすと、待機の上限を待たずに原因不明で終わる。
        except (OSError, http.client.HTTPException) as exc:
            last_error = type(exc).__name__
            time.sleep(1)
    ready_after = time.time() - started
    if not ready:
        note(f"管理APIが準備できない（待機 {ready_after:.0f} 秒、子の終了コード={proc.poll()}、最後の例外={last_error}）")
        if proc.poll() is None:
            stop_child(proc)
        print("not-ready")
        sys.exit(0)
    proc.send_signal(sig)
    try:
        rc = proc.wait(timeout=120)
        note(f"準備まで {ready_after:.0f} 秒、信号から終了まで {time.time() - started - ready_after:.0f} 秒、終了コード={rc}")
        print(rc)
    except subprocess.TimeoutExpired:
        note(f"信号から120秒たっても終了しない（準備まで {ready_after:.0f} 秒）")
        proc.kill()
        proc.wait()
        print("timeout")
PY
}

# 信号の検査が外れたとき、原因を特定できるように、子の標準エラーの末尾と残存を出す。
# Why: 子の標準エラーと一時ディレクトリは、検査の後始末で消える。外れた時点で残さないと、事後に確かめられない。
smoke_signal_diag() { # 信号名 子の終了コード 期待する終了コード 子の一時ディレクトリ
  printf 'DIAG: %s: 子の終了コード=%s 期待=%s\n' "$1" "$2" "$3" >&2
# shellcheck disable=SC2012 # 引数の $4 は検査が mktemp -d で作った子の一時ディレクトリ。名前は診断表示にだけ使う
  printf 'DIAG: %s: 一時ディレクトリの残り=[%s] 管理対象の残存=%s件\n' "$1" \
    "$(ls -A "$4" 2>/dev/null | tr '\n' ' ')" "$(docker ps -a -q --filter "label=$SWSC_LABEL" 2>/dev/null | wc -l | tr -d ' ')" >&2
  printf 'DIAG: %s: 子の標準エラーの末尾 20 行\n' "$1" >&2
  grep -v 'Making directories' "$WORK/child-$1.err" 2>/dev/null | tail -n 20 | sed 's/^/  | /' >&2 || true
}

smoke_case_signal() { # 信号名 期待する終了コード
  _t=$(mktemp -d "$WORK/child.XXXXXX") || return 1
  _rc=$(smoke_child_signal "$1" "$_t") || return 1
  if [ "$_rc" = "$2" ] \
    && grep -Fq 'cleanup: reset attempted' "$WORK/child-$1.err" \
    && smoke_clean_after "$_t"; then
    return 0
  fi
  smoke_signal_diag "$1" "$_rc" "$2" "$_t"
  return 1
}


# ---- smoke: 信号の検査（旧の check の名前と同じ。子の smoke を起動して信号を送る） ----

# bats test_tags=smoke
@test "INT: 終了コード130、リセットを試み、残存と一時ディレクトリがない" {
  smoke_require_lock || return 1
  smoke_case_signal INT 130
}

# bats test_tags=smoke
@test "TERM: 終了コード143、リセットを試み、残存と一時ディレクトリがない" {
  smoke_require_lock || return 1
  smoke_case_signal TERM 143
}

# ---- 検査の補助（旧の入口の unit 専用の関数。smoke では使わないため、ここへ移す） ----

# 終了コードだけを比べる。標準出力と標準エラーは捨てる。
rc_is() { # 期待終了コード コマンド...
  _want=$1
  shift
  _rc=0
  "$@" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq "$_want" ]
}

# docker の代わりに置く偽物。呼ばれたら記録し、失敗させる。
# Why: unit で Docker を呼ばないことを、呼び出しの記録で確かめるため。
make_shim() { # 作業ディレクトリ
  mkdir -p "$1/shim"
  printf '#!/bin/sh\necho %s >>"%s"\nexit 99\n' docker "$1/calls" >"$1/shim/docker"
  chmod +x "$1/shim/docker"
}

# 4シナリオの標準出力の例。実機の entrypoint.sh が出す形と同じにする。
canned_out() { # 名前
  case "$1" in
    normal) printf 'CLIENT_STATUS=200\nCLIENT_BODY={"id":"123"}\n' ;;
    error-500-then-200) printf 'CLIENT_STATUS=200\nCLIENT_BODY={}\n' ;;
    ratelimit-429) printf 'CLIENT_STATUS=429\nCLIENT_BODY={}\n' ;;
    slow-5000) : ;;
  esac
}

# 4シナリオの標準エラー（診断ログ）の例。
canned_err() { # 名前
  case "$1" in
    normal)
      printf 'CLIENT_DIAG result=success attempts=1 status=200\n'
      ;;
    error-500-then-200)
      printf 'CLIENT_DIAG retry attempt=1 status=500 class=5xx retry=1/3 wait=1\n'
      printf 'CLIENT_DIAG result=success attempts=2 status=200\n'
      ;;
    ratelimit-429)
      printf 'CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/3 retry_after=2 wait=2 capped=0\n'
      printf 'CLIENT_DIAG retry attempt=2 status=429 class=429 retry=2/3 retry_after=2 wait=2 capped=0\n'
      printf 'CLIENT_DIAG retry attempt=3 status=429 class=429 retry=3/3 retry_after=2 wait=2 capped=0\n'
      printf 'CLIENT_DIAG result=retries_exhausted attempts=4 status=429\n'
      ;;
    slow-5000)
      printf 'CLIENT_ERROR=timeout\n'
      printf 'CLIENT_DIAG result=timeout attempts=1 curl_exit=28\n'
      ;;
  esac
}

canned_rc() { # 名前
  case "$1" in
    slow-5000) printf '28' ;;
    *) printf '0' ;;
  esac
}

# WireMock の受信回数の例。期待値の attempts と一致させる。
canned_wm() { # 名前
  case "$1" in
    normal) printf '1' ;;
    error-500-then-200) printf '2' ;;
    ratelimit-429) printf '4' ;;
    slow-5000) printf '1' ;;
  esac
}

# URLパスから名前へ戻す。スタブの中でだけ使う。
name_of_path() { # URLパス
  case "$1" in
    /api/users/123) printf 'normal' ;;
    /api/error-500-then-200) printf 'error-500-then-200' ;;
    /api/ratelimit) printf 'ratelimit-429' ;;
    /api/slow-5000) printf 'slow-5000' ;;
    *) return 1 ;;
  esac
}

# 4シナリオの例を一つのディレクトリに置く（<名前>.out と <名前>.err）。
write_canned() { # ディレクトリ
  mkdir -p "$1"
  for _n in normal error-500-then-200 ratelimit-429 slow-5000; do
    canned_out "$_n" >"$1/$_n.out"
    canned_err "$_n" >"$1/$_n.err"
  done
}

# 外へ触る3点（リセット確認、クライアント実行、受信回数）をスタブにする。
# サブシェルの中で呼ぶ。本番の関数に差し替え用の分岐は入れない。
suite_sandbox() { # 作業ディレクトリ
  CALLS="$1/calls"
  RESULTS="$1/results"
  : >"$CALLS"
  suite_reset() { return 0; }
  run_client() { # パス 上書き設定 出力先
    _n=$(name_of_path "$1") || return 1
    printf '%s\n' "$1" >>"$CALLS"
    canned_out "$_n" >"$3/out"
    canned_err "$_n" >"$3/err"
    return "$(canned_rc "$_n")"
  }
  wiremock_count() { # パス
    _n=$(name_of_path "$1") || return 1
    canned_wm "$_n"
  }
}
