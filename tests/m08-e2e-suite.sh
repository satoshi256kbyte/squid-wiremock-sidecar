#!/bin/sh
# M08 代表4シナリオの E2E スイートの検査入口。
# unit は Docker を使わず、シナリオ表、実測値の抽出、実行ループ、レポートをスタブで確かめる。
# smoke は unit に続けて新基盤（taskdef）で実通信する（T806 以降で実装する）。
set -eu

# 管理APIは常にループバックの WireMock だけを指す。Why: 環境変数で他者の WireMock へ reset を
# 送らないため。WIREMOCK_URL を受け付けるのは 127.0.0.1 の宛先だけにする。
case "${WIREMOCK_URL:-http://127.0.0.1:8080}" in
  http://127.0.0.1:*) WIREMOCK_URL=${WIREMOCK_URL:-http://127.0.0.1:8080} ;;
  *)
    printf 'FAIL: WIREMOCK_URL は http://127.0.0.1:<ポート> のみ指定できる\n' >&2
    exit 2
    ;;
esac
export WIREMOCK_URL
# Why: 管理APIへの要求が外部のプロキシを経由すると、パス情報が外へ出て疎通も失敗するため。
no_proxy=127.0.0.1,localhost
NO_PROXY=$no_proxy
export no_proxy NO_PROXY

# 読み込み（M08_LIB_ONLY=1、M08_LIB_ROOT）のときだけ、呼び出し側が渡したルートを使う。
# Why: 読み込み時の $0 は相対パスのままで、main が cd した後に評価するとずれるため。
# 値を厳密に 1 と比べるのは、環境変数の残りで検査を黙ってスキップさせないため。
if [ "${M08_LIB_ONLY:-}" = 1 ] && [ -n "${M08_LIB_ROOT:-}" ]; then
  ROOT=$M08_LIB_ROOT
else
  ROOT=$(cd "$(dirname "$0")/.." && pwd)
fi
SELF="$ROOT/tests/m08-e2e-suite.sh"
# 新基盤の共通部品（名前の定数、Client 実行、起動、停止）。Why: 実通信は swsc_client_once_env と swsc_start_main を通すため。
# shellcheck disable=SC2034 # 直後で読み込む scripts/e2e-lib.sh と scripts/e2e-runner.sh が SWSC_ROOT を参照する
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

# 既定の実行順。slow-5000 を最後に置くのは、遅れた記録を次のシナリオのリセット確認に混ぜないため。
E2E_ORDER="normal error-500-then-200 ratelimit-429 slow-5000"

failures=0
total=0

# 検査の本体を1つ走らせ、失敗したら記録する。関数の成否を終了コードで受ける。
check() { # 検査名 関数
  _name=$1
  shift
  total=$((total + 1))
  if ! "$@"; then
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$_name" >&2
  fi
}

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

unit_main() {
  check "引数: 不正なモード、unit への名前、未定義、対象外は終了コード2" unit_arg_codes
  check "既定の順は normal、error-500-then-200、ratelimit-429、slow-5000" unit_default_order
  check "Docker を呼ばない（docker を PATH の先頭に置く）" unit_no_docker
  check "m08_scenario_expectations: シナリオ表（パス、期待値、上書き設定）" unit_scenario_table
  check "429の4と3が retry-lib の既定値と整合" unit_retry_defaults
  check "実測値の抽出（4種と、読めない項目は -）" unit_parse_client
  check "固有の検査（正しい例は通り、崩した例は落ちる）" unit_extra_checks
  check "受信回数が - のシナリオは wiremock_count を呼ばない" unit_dash_not_called
  check "run_client が TEST_API_PATH と上書き設定を渡す" unit_run_client_args
  check "run_suite: 全件 PASS で終了コード0、経過時間の行" unit_suite_all_pass
  check "run_suite: 順序を逆にしても各シナリオの結果が同じ" unit_suite_order
  check "run_suite: 不一致で続行し、終了コード1" unit_suite_continue
  check "run_suite: リセット確認の失敗で停止（残りは NOT_RUN）" unit_suite_reset_stop
  check "レポート: 全件 PASS の要約行" unit_report_pass
  check "レポート: FAIL と NOT_RUN の件数と未実行の行" unit_report_mixed
  check "レポート: ファイルを作らない" unit_report_no_files
  check "失敗出力: 再現コマンドと診断ログ、認証情報の形がない" unit_fail_detail
  check "m08_term_cleanup: 後始末の reset は実行中だけ送り、未実行なら skipped を出す（TERM の実機は smoke の signal-case）" unit_cleanup_reset
  check "文書: docs/E2Eテスト.md があり、README から参照され、4シナリオ名と禁止の形を含まない" unit_doc

  if [ "$failures" -ne 0 ]; then
    printf 'M08 unit: %s of %s checks failed\n' "$failures" "$total" >&2
    exit 1
  fi
  printf 'M08 e2e suite unit passed (%s checks)\n' "$total"
}

# ---- 実装: 引数 ----

usage() { # 理由
  printf 'M08: %s\nusage: sh tests/m08-e2e-suite.sh [unit|smoke] [シナリオ名...]\n' "$1" >&2
  exit 2
}

# E2E 対象の名前だけを通す。未定義は定義済みの一覧を、対象外は対象4名を出す。
validate_name() { # 名前
  case " $E2E_ORDER " in
    *" $1 "*) return 0 ;;
  esac
  if printf '%s\n' "$(scenario_names)" | grep -Fxq "$1"; then
    printf 'シナリオ %s は代表4シナリオに含まれない。対象は %s\n' "$1" "$E2E_ORDER" >&2
  else
    printf '未定義のシナリオ: %s\n定義済み: %s\n' "$1" "$(scenario_names | tr '\n' ' ')" >&2
  fi
  return 1
}

# ---- 実装: シナリオ表 ----

# 期待値の文字列。項目の順は実測値と揃えてあり、文字列の一致で合否を決める。
# 429 の 4 と 3 は固定値で書く。retry-lib の既定値との突き合わせは unit で行う（Q-811）。
scenario_expect() { # 名前
  case "$1" in
    normal) printf '%s\n' 'status=200 result=success attempts=1 retries=0 wiremock=1 rc=0' ;;
    error-500-then-200) printf '%s\n' 'status=200 result=success attempts=2 retries=1 wiremock=2 rc=0' ;;
    ratelimit-429) printf '%s\n' 'status=429 result=retries_exhausted attempts=4 retries=3 wiremock=4 rc=0' ;;
    slow-5000) printf '%s\n' 'status=- result=timeout attempts=1 retries=0 wiremock=1 rc=28' ;;
    *) return 2 ;;
  esac
}

# 上書きする設定。無い名前は空を出す。RESPONSE_TIMEOUT_SECONDS は M06 で実機確認済みの値。
scenario_env() { # 名前
  case "$1" in
    slow-5000) printf '%s\n' 'RESPONSE_TIMEOUT_SECONDS=1' ;;
    normal | error-500-then-200 | ratelimit-429) printf '\n' ;;
    *) return 2 ;;
  esac
}

# 期待値の文字列から1項目の値を取り出す。
expect_field() { # 項目名 期待値の文字列
  for _tok in $2; do
    case "$_tok" in
      "$1"=*)
        printf '%s' "${_tok#*=}"
        return 0
        ;;
    esac
  done
  return 1
}

# ---- 実装: 実測値 ----

# 標準出力の CLIENT_STATUS を読む。タイムアウトなど出力が無いときは -。
client_status() { # 標準出力
  _v=$(sed -n 's/^CLIENT_STATUS=\([0-9][0-9]*\)$/\1/p' "$1" | sed -n '1p')
  printf '%s' "${_v:--}"
}

# 診断ログの最終結果と総試行。タイムアウトの行も同じ形なので、同じ読み方で足りる。
client_result() { # 標準エラー
  _v=$(sed -n 's/^CLIENT_DIAG result=\([a-z_]*\) attempts=.*/\1/p' "$1" | sed -n '1p')
  printf '%s' "${_v:--}"
}

client_attempts() { # 標準エラー
  _v=$(sed -n 's/^CLIENT_DIAG result=[a-z_]* attempts=\([0-9][0-9]*\).*/\1/p' "$1" | sed -n '1p')
  printf '%s' "${_v:--}"
}

# リトライの行の数。0件でも grep の終了コードで止まらないよう || true で受ける。
client_retries() { # 標準エラー
  _v=$(grep -c '^CLIENT_DIAG retry attempt=' "$1" || true)
  printf '%s' "${_v:-0}"
}

# 実測値を期待値と同じ項目名の文字列にする。読めない項目は -。
parse_client() { # 標準出力 標準エラー 終了コード 受信回数
  printf 'status=%s result=%s attempts=%s retries=%s wiremock=%s rc=%s\n' \
    "$(client_status "$1")" "$(client_result "$2")" "$(client_attempts "$2")" \
    "$(client_retries "$2")" "$4" "$3"
}

# 検査が外れたら理由を標準エラーへ出して 1 を返す。
extra_expect() { # 検査の名前 コマンド...
  _what=$1
  shift
  if "$@" >/dev/null 2>&1; then
    return 0
  fi
  printf 'extra check: %s\n' "$_what" >&2
  return 1
}

# シナリオ固有の検査（plan 3.5）。文字列の比較では見られない、リトライの経過を確かめる。
extra_checks() { # 名前 標準出力 標準エラー
  _attempts=$(client_attempts "$3")
  _retries=$(client_retries "$3")
  # Why: 失敗の注入で、retry 行が抜けたり余分に出たりする経路を拾うため。
  if [ "$_attempts" = - ] || [ "$_retries" -ne $((_attempts - 1)) ]; then
    printf 'extra check: retry 行の数が総試行−1に一致しない（試行 %s、retry行 %s）\n' "$_attempts" "$_retries" >&2
    return 1
  fi
  case "$1" in
    error-500-then-200)
      extra_expect '500 の再試行行（retry=1/3 wait=1）' \
        grep -Fq 'CLIENT_DIAG retry attempt=1 status=500 class=5xx retry=1/3 wait=1' "$3" || return 1
      ;;
    ratelimit-429)
      extra_expect '429 の retry 行が3本' \
        test "$(grep -c '^CLIENT_DIAG retry .*class=429 ' "$3" || true)" -eq 3 || return 1
      extra_expect '429 の待機が Retry-After: 2 に従う（wait=2 capped=0）' \
        test "$(grep -c '^CLIENT_DIAG retry .*class=429 .*retry_after=2 wait=2 capped=0$' "$3" || true)" -eq 3 || return 1
      ;;
    slow-5000)
      extra_expect 'タイムアウトの標準出力が空' test ! -s "$2" || return 1
      extra_expect 'CLIENT_ERROR=timeout の行' grep -Fqx 'CLIENT_ERROR=timeout' "$3" || return 1
      ;;
  esac
  return 0
}

# ---- 実装: 外へ触る3点 ----

# 1シナリオ分のクライアントを実行する。出力は出力先の out と err に分けて残す。
# Why: 上書きの設定は -e で明示したものだけを渡す。ホストの環境変数は届かないため。
# Why: 新基盤の共通入口を使う。Squid の 3128 はホストへ公開しないので、要求は Client から送る。
run_client() { # パス 上書き設定（空可） 出力先
  _rc=0
  if [ -n "$2" ]; then
    swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$SWSC_M08_CLIENT_URL" "$3/out" "$3/err" \
      "TEST_API_PATH=$1" "$2" || _rc=$?
  else
    swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$SWSC_M08_CLIENT_URL" "$3/out" "$3/err" \
      "TEST_API_PATH=$1" || _rc=$?
  fi
  return "$_rc"
}

# WireMock の管理APIで、パス一致の呼び出し件数だけを読む。M06 と M07 の定義を複製する。
# Why: 共通化すると scenario-lib.sh の変更が要るため、M08 の検査入口に置く（NFR-802）。
wiremock_count() { # URLパス
  _base=${WIREMOCK_URL:-http://127.0.0.1:8080}
  _body=$(printf '{"method":"GET","url":"%s"}' "$1")
  _res=$(curl --fail --silent --show-error --connect-timeout 2 --max-time 10 -H 'Content-Type: application/json' \
    -d "$_body" "$_base/__admin/requests/count") || return 1
  _n=$(printf '%s' "$_res" | sed -n 's/.*"count" *: *\([0-9][0-9]*\).*/\1/p')
  [ -n "$_n" ] || return 1
  printf '%s' "$_n"
}

# 各シナリオの前に、リセットして確認する。どちらかが外れたら 1 を返す。
suite_reset() {
  wiremock_reset && wiremock_verify_reset wiremock-scenarios/mappings
}

# ---- 実装: 実行ループ ----

# 結果を1行で残す。区切りは | で、値には | を含まない。
record_result() { # 名前 結果 期待値 実測値
# shellcheck disable=SC2031 # RESULTS は呼び出し元が設定する。部分シェルで隔離した値へ追記する使い方が意図
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$RESULTS"
}

# 1シナリオを実行し、実測値を期待値と比べる。内部の失敗は呼び出し側が FAIL にする。
run_one() { # 名前
  _nm=$1
  _want=$(scenario_expect "$_nm") || return 1
  _env=$(scenario_env "$_nm") || return 1
  _path=$(scenario_path "$_nm") || return 1
  _od=$(mktemp -d "$WORK/run.XXXXXX") || return 1
  _t0=$(date +%s)
  _rc=0
  run_client "$_path" "$_env" "$_od" || _rc=$?
  _t1=$(date +%s)

  _wm_want=$(expect_field wiremock "$_want") || return 1
  if [ "$_wm_want" = - ]; then
    _wm=-
  else
    _wm=$(wiremock_count "$_path") || _wm=-
  fi

  _got=$(parse_client "$_od/out" "$_od/err" "$_rc" "$_wm")
  _ok=PASS
  if [ "$_got" != "$_want" ] || ! extra_checks "$_nm" "$_od/out" "$_od/err"; then
    _ok=FAIL
  fi
  printf 'scenario %s elapsed=%s\n' "$_nm" "$((_t1 - _t0))" >&2
  record_result "$_nm" "$_ok" "$_want" "$_got"
  if [ "$_ok" = FAIL ]; then
    fail_detail "$_nm" "$_path" "$_env" "$_want" "$_got" "$_od/err"
  fi
  return 0
}

# 指定された名前（省略時は既定の順）を直列に実行する。リセット確認が外れたら残りを実行しない。
# Why: 続行と停止を分けるのは、リセットが外れると後続の結果が前の混入を受けるため（FR-807、FR-811）。
run_suite() { # シナリオ名...
  if [ "$#" -eq 0 ]; then
    # shellcheck disable=SC2086 # E2E_ORDER は行 39 の固定の文字列（空白区切りの4シナリオ名）で、語ごとに分ける意図
    set -- $E2E_ORDER
  fi
  # shellcheck disable=SC2031 # RESULTS は呼び出し元が設定する値で、この関数では空に作り直す意図
  : >"$RESULTS"
  _stop=0
  _start=$(date +%s)
  for _nm in "$@"; do
    _want=$(scenario_expect "$_nm") || _want=-
    if [ "$_stop" -eq 1 ]; then
      record_result "$_nm" NOT_RUN "$_want" not_run
    elif suite_reset; then
      run_one "$_nm" || record_result "$_nm" FAIL "$_want" not_run
    else
      record_result "$_nm" FAIL "$_want" not_run
      printf 'FAIL: リセットを確認できないため %s を実行しない\n' "$_nm" >&2
      _stop=1
    fi
  done
  _elapsed=$(( $(date +%s) - _start ))
# shellcheck disable=SC2031 # 上の : >"$RESULTS" で作り直した同じ値を読むのが意図（部分シェルの値ではない）
  report_all "$RESULTS" "$_elapsed"
}

# ---- 実装: レポート ----

report_row() { # 名前 期待値 実測値 結果
  printf '%s | %s | %s | %s\n' "$1" "$2" "$3" "$4"
}

# 要約行は、全体の合否、合格数、失敗数、未実行数、失敗名の一覧、秒数を含む。
report_summary() { # 結果ファイル 秒数
  _pass=$(grep -c '|PASS|' "$1" || true)
  _fail=$(grep -c '|FAIL|' "$1" || true)
  _nr=$(grep -c '|NOT_RUN|' "$1" || true)
  _names=$(sed -n 's/^\([^|]*\)|FAIL|.*/\1/p' "$1" | paste -sd, -)
  [ -n "$_names" ] || _names=-
  if [ "$_fail" -eq 0 ] && [ "$_nr" -eq 0 ]; then
    _status=PASS
  else
    _status=FAIL
  fi
  printf 'summary: %s passed=%s failed=%s not_run=%s failed_scenarios=%s elapsed=%ss\n' \
    "$_status" "$_pass" "$_fail" "$_nr" "$_names" "$2"
  [ "$_status" = PASS ]
}

report_all() { # 結果ファイル 秒数
  printf 'scenario | expected | actual | result\n'
  while IFS='|' read -r _n _r _e _a; do
    report_row "$_n" "$_e" "$_a" "$_r"
  done <"$1"
  report_summary "$1" "$2"
}

# 失敗したシナリオの再現情報と診断ログを標準エラーへ出す。値に認証情報は含まれない。
fail_detail() { # 名前 パス 上書き設定 期待値 実測値 診断ログ
  printf 'scenario: %s\n' "$1" >&2
  printf '  path: %s\n' "$2" >&2
  printf '  overrides: %s\n' "${3:-none}" >&2
  printf '  expected: %s\n  actual: %s\n' "$4" "$5" >&2
  printf '  rerun: sh tests/m08-e2e-suite.sh smoke %s\n' "$1" >&2
  printf '  diag:\n' >&2
  sed 's/^/    /' "$6" >&2 || true
}

# ---- 実装: smoke（新基盤の実通信、T806からT808） ----

# 起動、ポートの空き確認、停止は新基盤の入口（swsc_start_main、swsc_stop）に任せる。
# Why: ポートの空き確認を個別に持つと、新基盤の入口と判定が食い違うため。
# smoke_started は、起動が成功した後に立てる。失敗した起動の後に reset を送らないため。
smoke_started=0
# 起動の後、Client が送る先（Squid の 3128 を通る要求の宛先）。
SWSC_M08_CLIENT_URL=http://api.example.com

# 起動し、WireMock の管理APIが応答するまで待つ。Squid の待ち受けは swsc_start_main が確かめる。
# Why: ホストから 3128 へ要求を送らない。Squid 経由の準備の確認は、最初の Client の実行で見える。
smoke_up() {
  smoke_started=0
  if ! swsc_stop; then
    printf 'FAIL: 既存の swsc- の停止に失敗した\n' >&2
    return 1
  fi
  if ! swsc_check_ports_free "$SWSC_MOCK_PORT" "$SWSC_SQUID_PORT"; then
    printf 'FAIL: ポート 3128 か 8080 が使用中のため起動しない\n' >&2
    return 1
  fi
  # Why: 空きを確かめた直後に立てる（移行前と同じ）。swsc_start_main は WireMock を Squid より先に起動するため、
  # 途中で信号を受けても、後始末の reset を送れるようにする。空いていないポートへは reset を送らない。
  smoke_started=1
  if ! swsc_start_main; then
    printf 'FAIL: 新基盤の起動に失敗した\n' >&2
    return 1
  fi
  smoke_started=1
  _i=0
  until curl --fail --silent --show-error --max-time 5 "$WIREMOCK_URL/__admin/mappings" >/dev/null 2>&1; do
    _i=$((_i + 1))
    if [ "$_i" -ge 60 ]; then
      printf 'FAIL: WireMock の管理APIが準備できない\n' >&2
      return 1
    fi
    sleep 1
  done
}

# 後始末の reset。Why: 起動を始めていなければ、確かめた宛先は他人のものかもしれず、
# 実行中でなければ reset を送っても効果がなく、ログを誤解させるため、送らず理由だけ出す。
cleanup_reset() {
  if [ "${smoke_started:-0}" -ne 1 ]; then
    printf 'cleanup: reset skipped (not started)\n' >&2
    return 0
  fi
  if [ "$(docker inspect --format '{{.State.Running}}' "${SWSC_PREFIX}wiremock" 2>/dev/null || true)" != true ]; then
    printf 'cleanup: reset skipped (not running)\n' >&2
    return 0
  fi
  printf 'cleanup: reset attempted\n' >&2
  if wiremock_reset 2>/dev/null; then
    printf 'cleanup: reset ok\n' >&2
  else
    printf 'cleanup: reset failed (ignored)\n' >&2
  fi
}

# 終了時の後始末。順序は plan 6.1 のとおり。各処理の失敗は次へ進む（|| true）。
# Why: 失敗時だけ収集する（test:ci の collect と同じ方針）。収集の失敗で終了コードを変えない。
# Why: 元の終了コードを保つのは、失敗経路の検査（終了コード1、130、143）が後始末の後の値で判定するため。
# ロックは自分が取ったときだけ解放する。子（SWSC_LOCK_HELD=1）では何もしない。
smoke_cleanup() {
  _rc=$?
  if [ "$_rc" -ne 0 ]; then swsc_collect || true; fi
  cleanup_reset
  swsc_stop || true
  rm -rf "$WORK" || true
  swsc_lock_leave || { [ "$_rc" -ne 0 ] || _rc=1; }
  exit "$_rc"
}

# ---- 実装: 周回の検査（4.2 の順2から4） ----

# 1周分を実行し、4行すべてが PASS で、要約が全体 PASS であることを確かめる。報告は $WORK/round<N>.txt に残す。
smoke_round_pass() { # 周回の番号
  _f="$WORK/round$1.txt"
  run_suite >"$_f" || return 1
  [ "$(grep -c ' | PASS$' "$_f" || true)" -eq 4 ] || return 1
  tail -n 1 "$_f" | grep -Eq '^summary: PASS passed=4 failed=0 not_run=0 failed_scenarios=- elapsed=[0-9]+s$'
}

# 周2の行が周1と同じであることを確かめる。要約の行は所要時間が毎回違うため外して比べる。
smoke_rows_same() {
  grep -v '^summary:' "$WORK/round1.txt" >"$WORK/round1.rows" || return 1
  grep -v '^summary:' "$WORK/round2.txt" >"$WORK/round2.rows" || return 1
  cmp -s "$WORK/round1.rows" "$WORK/round2.rows"
}

# 名前指定で1シナリオだけ実行し、レポートが見出し、1行、要約の3行になることを確かめる。
smoke_named() {
  run_suite error-500-then-200 >"$WORK/named.txt" || return 1
  [ "$(wc -l <"$WORK/named.txt" | tr -d ' ')" -eq 3 ] || return 1
  grep -Eq '^error-500-then-200 \| .* \| PASS$' "$WORK/named.txt" || return 1
  tail -n 1 "$WORK/named.txt" | grep -Eq '^summary: PASS passed=1 failed=0 not_run=0 failed_scenarios=- elapsed='
}

# ---- 実装: 失敗の注入（6.3、同じ起動の中で行う） ----

# アサーション失敗は続行する。normal の期待値だけを総試行2に差し替え、残りは本物の期待値のまま実行する。
# Why: 実通信の結果が期待値と違うとき、残りのシナリオが実行され、失敗の詳細が出ることを確かめるため。
smoke_inject_assert() {
  _f="$WORK/inject-assert"
  mkdir -p "$_f"
  _rc=0
  (
    scenario_expect() {
      case "$1" in
        normal) printf '%s\n' 'status=200 result=success attempts=2 retries=1 wiremock=2 rc=0' ;;
        error-500-then-200) printf '%s\n' 'status=200 result=success attempts=2 retries=1 wiremock=2 rc=0' ;;
        ratelimit-429) printf '%s\n' 'status=429 result=retries_exhausted attempts=4 retries=3 wiremock=4 rc=0' ;;
        slow-5000) printf '%s\n' 'status=- result=timeout attempts=1 retries=0 wiremock=1 rc=28' ;;
        *) return 2 ;;
      esac
    }
    run_suite
  ) >"$_f/report" 2>"$_f/err" || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  grep -Eq '^normal \| .* \| FAIL$' "$_f/report" || return 1
  grep -Eq '^error-500-then-200 \| .* \| PASS$' "$_f/report" || return 1
  grep -Eq '^ratelimit-429 \| .* \| PASS$' "$_f/report" || return 1
  grep -Eq '^slow-5000 \| .* \| PASS$' "$_f/report" || return 1
  grep -Fq 'scenario: normal' "$_f/err" || return 1
  grep -Fq 'rerun: sh tests/m08-e2e-suite.sh smoke normal' "$_f/err" || return 1
  grep -Fq 'CLIENT_DIAG result=success attempts=1' "$_f/err"
}

# リセット確認の失敗で停止する。1回目の確認は成功、2回目は失敗に差し替える。
# Why: 2回目以降のシナリオは、前の結果が混ざった状態で走らせないため、クライアントを呼ばない。
smoke_inject_reset() {
  _f="$WORK/inject-reset"
  mkdir -p "$_f"
  _cf="$_f/verify-count"
  _rc=0
  (
    wiremock_verify_reset() {
      _c=$(cat "$_cf" 2>/dev/null || printf 0)
      _c=$((_c + 1))
      printf '%s' "$_c" >"$_cf"
      [ "$_c" -eq 1 ]
    }
    run_suite
  ) >"$_f/report" 2>"$_f/err" || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  grep -Eq '^normal \| .* \| PASS$' "$_f/report" || return 1
  grep -Eq '^error-500-then-200 \| .* \| not_run \| FAIL$' "$_f/report" || return 1
  grep -Eq '^ratelimit-429 \| .* \| not_run \| NOT_RUN$' "$_f/report" || return 1
  grep -Eq '^slow-5000 \| .* \| not_run \| NOT_RUN$' "$_f/report" || return 1
  grep -Fq 'summary: FAIL passed=1 failed=1 not_run=2 failed_scenarios=error-500-then-200 elapsed=' "$_f/report" || return 1
  # 2回目以降は呼ばれていない。2回目の reset の後にジャーナルは空なので、件数が0のままなら呼ばれていない。
  [ "$(wiremock_count /api/error-500-then-200)" -eq 0 ] || return 1
  [ "$(wiremock_count /api/ratelimit)" -eq 0 ] || return 1
  [ "$(wiremock_count /api/slow-5000)" -eq 0 ] || return 1
  grep -Fq 'リセットを確認できないため error-500-then-200 を実行しない' "$_f/err"
}

# ---- 実装: 失敗経路の子（6.3、子は M08_NESTED=1 で動く） ----

smoke_clean_after() { # 子の一時ディレクトリ
  [ -z "$(ls -A "$1")" ] && swsc_check_managed_empty
}

# 起動の失敗。出力先に swsc が作っていない中身を置き、swsc_start_main を準備の前に止める。
# Why: 親のロックの下で子を動かすため SWSC_LOCK_HELD=1 を渡す。子の起動失敗は親のスタックに触れない。
smoke_case_start_fail() {
  _t=$(mktemp -d "$WORK/child.XXXXXX") || return 1
  _occ=$(mktemp -d "$WORK/occupied.XXXXXX") || return 1
  : >"$_occ/foreign.txt" || return 1
  _rc=0
  env M08_NESTED=1 M08_TMP_ROOT="$_t" SWSC_LOCK_HELD=1 SWSC_E2E_DIR="$_occ" \
    sh "$SELF" smoke >/dev/null 2>"$WORK/child-start.err" || _rc=$?
  rm -rf "$_occ" || true
  # Why: 起動は WireMock を作る前に止まる。後始末は、WireMock が動いていないことを見て reset を送らない。
  [ "$_rc" -eq 1 ] \
    && grep -Fq 'FAIL: 新基盤の起動に失敗した' "$WORK/child-start.err" \
    && grep -Fq 'cleanup: reset skipped (not running)' "$WORK/child-start.err" \
    && ! grep -Fq 'cleanup: reset attempted' "$WORK/child-start.err" \
    && smoke_clean_after "$_t"
}

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

# ---- 実装: 検査の並び ----

# 周1と周2は同じ起動の中で行う。名前指定は1シナリオのレポートを確かめる。
smoke_checks() {
  check "開始前のリセットと確認" smoke_reset_verify
  check "[周1] 既定の順で4シナリオが PASS、終了コード0" smoke_round_pass 1
  check "[周2] 既定の順で4シナリオが PASS、終了コード0" smoke_round_pass 2
  check "[周2] 各行が周1と同じ（所要時間の行を除く）" smoke_rows_same
  check "名前指定 error-500-then-200 が1行のレポート" smoke_named
  check "アサーション失敗: 続行し、終了コード1、詳細を出す" smoke_inject_assert
  check "リセット確認の失敗: 停止し、2回目以降を呼ばない" smoke_inject_reset
}

smoke_reset_verify() {
  wiremock_reset && wiremock_verify_reset wiremock-scenarios/mappings
}

# 失敗経路。親のスタックを畳んでから行う（M07 と同じ）。子の中では行わない（再帰を防ぐ）。
smoke_failure_path() {
  check "起動失敗: 終了コード1、リセットは試みず、残存と一時ディレクトリがない" smoke_case_start_fail
  check "INT: 終了コード130、リセットを試み、残存と一時ディレクトリがない" smoke_case_signal INT 130
  check "TERM: 終了コード143、リセットを試み、残存と一時ディレクトリがない" smoke_case_signal TERM 143
}

# 引数があれば、そのシナリオだけを1周実行して終了する（名前指定の再実行）。
# 引数がなければ、4.2 の順に検査する。
smoke_main() { # 名前...
  # Why: ロックはトップレベルで1回だけ取る。取れなければ、他の実行の swsc- に触れずに止まる。
  swsc_lock_enter || exit 1
  trap smoke_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # 既定の宛先を明示する。set -u のもとで、後始末と準備完了の待機が未定義の変数を読まないため。
  WIREMOCK_URL=${WIREMOCK_URL:-http://127.0.0.1:8080}
  export WIREMOCK_URL

  smoke_up || exit 1

  if [ "$#" -gt 0 ]; then
    run_suite "$@"
    exit $?
  fi

  smoke_checks

  # 終了後の残存確認。失敗経路の子が親のスタックを使う前に、畳んでおく。
  swsc_stop || exit 1
  check "終了後に管理対象の残存がない" swsc_check_managed_empty
  if [ -z "${M08_NESTED:-}" ]; then
    smoke_failure_path
  fi

  if [ "$failures" -ne 0 ]; then
    printf 'M08 smoke: %s of %s checks failed\n' "$failures" "$total" >&2
    exit 1
  fi
  printf 'M08 e2e suite smoke passed (%s checks)\n' "$total"
}

main() {
  _mode=smoke
  case "${1:-}" in
    '') ;;
    unit | smoke)
      _mode=$1
      shift
      ;;
    *) usage "不正なモード: $1" ;;
  esac
  if [ "$_mode" = unit ] && [ "$#" -gt 0 ]; then
    usage 'unit はシナリオ名を受け付けない'
  fi

  cd "$ROOT"
  # 読み込みに副作用はない。関数を使うためにここで読み込む。
  . "$ROOT/scripts/scenario-lib.sh"
  for _n in "$@"; do
    validate_name "$_n" || exit 2
  done

  # 一時ファイルは KIROCREW_SCRATCH の下に作る。/tmp は使わない。
  # M08_TMP_ROOT は失敗経路の子が一時ディレクトリを親と分けるための上書き（M07 の TMPDIR に相当）。
  WORK=$(mktemp -d "${M08_TMP_ROOT:-${KIROCREW_SCRATCH:-${TMPDIR:-$HOME}}}/m08.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT
  RESULTS="$WORK/results"

  unit_main
  if [ "$_mode" = unit ]; then
    exit 0
  fi
  smoke_main "$@"
}

# 検査から関数だけを読み込むときは本体を走らせない。ガードがないと、読み込みの
# たびに unit が再帰的に走り、プロセスが増え続けて止まらない。
if [ "${M08_LIB_ONLY:-}" = 1 ]; then
  printf 'M08 e2e suite: M08_LIB_ONLY=1 のため関数だけを読み込み、検査は実行しない\n' >&2
else
  main "$@"
fi
