#!/bin/sh
# 代表4シナリオ（normal、error-500-then-200、ratelimit-429、slow-5000）を実通信で実行する。
# 使い方: sh scripts/e2e-scenarios.sh [シナリオ名...]。省略時は4つを既定の順に実行する。
# 起動、実行、収集、停止を持つ。scripts/e2e.sh の test:ci が、ロックを取ったうえでこのスクリプトを呼ぶ。
set -eu

# 管理APIは常にループバックの WireMock だけを指す。Why: 環境変数で他者の WireMock へ reset を
# 送らないため。WIREMOCK_URL を受け付けるのは 127.0.0.1 の宛先だけにする。
# Why: userinfo（http://127.0.0.1:80@other-host:8080 の形）で別の宛先に迂回されないよう、ポートが数字だけであることも確かめる。
_wm_url=${WIREMOCK_URL:-http://127.0.0.1:8080}
_wm_port=${_wm_url#http://127.0.0.1:}
case "$_wm_url" in
  http://127.0.0.1:*) ;;
  *) _wm_port= ;;
esac
case "$_wm_port" in
  '' | *[!0-9]*)
    printf 'FAIL: WIREMOCK_URL は http://127.0.0.1:<ポート> のみ指定できる\n' >&2
    exit 2
    ;;
esac
WIREMOCK_URL=$_wm_url
export WIREMOCK_URL
# Why: 管理APIへの要求が外部のプロキシを経由すると、パス情報が外へ出て疎通も失敗するため。
no_proxy=127.0.0.1,localhost
NO_PROXY=$no_proxy
export no_proxy NO_PROXY

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# 新基盤の共通部品（名前の定数、Client 実行、起動、停止）。Why: 実通信は swsc_client_once_env と swsc_start_main を通すため。
# shellcheck disable=SC2034 # 直後で読み込む scripts/e2e-lib.sh と scripts/e2e-runner.sh が SWSC_ROOT を参照する
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

# 既定の実行順。slow-5000 を最後に置くのは、遅れた記録を次のシナリオのリセット確認に混ぜないため。
E2E_ORDER="normal error-500-then-200 ratelimit-429 slow-5000"

usage() { # 理由
  printf 'e2e-scenarios: %s\nusage: sh scripts/e2e-scenarios.sh [シナリオ名...]\n' "$1" >&2
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
    swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$SWSC_SCENARIOS_CLIENT_URL" "$3/out" "$3/err" \
      "TEST_API_PATH=$1" "$2" || _rc=$?
  else
    swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$SWSC_SCENARIOS_CLIENT_URL" "$3/out" "$3/err" \
      "TEST_API_PATH=$1" || _rc=$?
  fi
  return "$_rc"
}

# WireMock の管理APIで、パス一致の呼び出し件数だけを読む。M06 と M07 の定義を複製する。
# Why: 共通化すると scenario-lib.sh の変更が要るため、このスクリプトに置く。
# jq の実体は、固定版を照合して得る（件数の取り出しに使う）。jq_bin が未設定なら、呼び出しごとに照合する（コマンド置換の中で設定しても親には残らない）。
scenarios_jq() {
  if [ -z "${jq_bin:-}" ]; then
    # shellcheck source=/dev/null
    . "$ROOT/scripts/lib/resolve-tool.sh"
    resolve_tool jq 's/^jq-//p' --version || return 1
    jq_bin=$RESOLVED_PATH
  fi
}

# 応答の本文から件数（"count"）を出す。件数は 0 以上の整数だけを受け付ける。
# Why: 旧の sed は数字の並びだけを拾い、文字列、負の数、空、null を失敗にしていた。同じ判定を jq で保つため。
wiremock_count_value() { # 応答の本文
  scenarios_jq || return 1
  printf '%s' "$1" | "$jq_bin" -e -r '
    if (.count | type) == "number" and .count >= 0 and .count == (.count | floor) then .count else empty end
  '
}

wiremock_count() { # URLパス
  _base=${WIREMOCK_URL:-http://127.0.0.1:8080}
  _body=$(printf '{"method":"GET","url":"%s"}' "$1")
  _res=$(curl --fail --silent --show-error --connect-timeout 2 --max-time 10 -H 'Content-Type: application/json' \
    -d "$_body" "$_base/__admin/requests/count") || return 1
  _n=$(wiremock_count_value "$_res") || return 1
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
    # shellcheck disable=SC2086 # E2E_ORDER は上の固定の文字列（空白区切りの4シナリオ名）で、語ごとに分ける意図
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
  printf '  rerun: sh scripts/e2e-scenarios.sh %s\n' "$1" >&2
  printf '  diag:\n' >&2
  sed 's/^/    /' "$6" >&2 || true
}


# ---- 実装: smoke（新基盤の実通信、T806からT808） ----

# 起動、ポートの空き確認、停止は新基盤の入口（swsc_start_main、swsc_stop）に任せる。
# Why: ポートの空き確認を個別に持つと、新基盤の入口と判定が食い違うため。
# smoke_started は、起動が成功した後に立てる。失敗した起動の後に reset を送らないため。
smoke_started=0
# 起動の後、Client が送る先（Squid の 3128 を通る要求の宛先）。
SWSC_SCENARIOS_CLIENT_URL=http://api.example.com

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

main() {
  cd "$ROOT"
  # shellcheck source=/dev/null
  . "$ROOT/scripts/scenario-lib.sh"
  for _n in "$@"; do
    validate_name "$_n" || exit 2
  done

  # 一時ファイルは KIROCREW_SCRATCH の下に作る。/tmp は使わない。
  WORK=$(mktemp -d "${KIROCREW_SCRATCH:-${TMPDIR:-$HOME}}/e2e-scenarios.XXXXXX")
  RESULTS="$WORK/results"

  # Why: ロックはトップレベルで1回だけ取る。取れなければ、他の実行の swsc- に触れずに止まる。
  swsc_lock_enter || exit 1
  trap smoke_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  WIREMOCK_URL=${WIREMOCK_URL:-http://127.0.0.1:8080}
  export WIREMOCK_URL

  smoke_up || exit 1
  run_suite "$@"
}

main "$@"
