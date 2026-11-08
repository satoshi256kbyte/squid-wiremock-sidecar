#!/usr/bin/env bats
# M06 Test Client の再試行と耐性の検査（unit）。Docker を使わず、retry-lib.sh の関数と、entrypoint.sh の振る舞いを確かめる。
# 旧の tests/m06-client-resilience.sh の unit の検査（expect）を、1件ずつ @test にした。検査名は旧と同じ。
# 入口は tests/m06-client-resilience.sh（unit は tests/lib/run-bats.sh を呼ぶ）。
# entrypoint の検査（ep_obs）は、偽の curl と sleep を一時ディレクトリに置き、実通信と実待機をしない。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  LIB="$ROOT/test-client/retry-lib.sh"
  # 関数を読む。旧の run_unit と同じ読み込み。
  # shellcheck source=../../test-client/retry-lib.sh
  . "$LIB"
}

# 期待する標準出力と終了コードを比べる。失敗は return 1 で返し、検査名を標準エラーへ出す。
expect() { # 検査名 期待出力 期待終了コード コマンド [引数...]
  _name=$1
  _want_out=$2
  _want_rc=$3
  shift 3
  _got_out=$("$@" 2>/dev/null) && _got_rc=0 || _got_rc=$?
  if [ "$_got_out" = "$_want_out" ] && [ "$_got_rc" -eq "$_want_rc" ]; then
    return 0
  fi
  printf 'FAIL: %s (期待 出力=[%s] rc=%s / 実際 出力=[%s] rc=%s)\n' \
    "$_name" "$_want_out" "$_want_rc" "$_got_out" "$_got_rc" >&2
  return 1
}

# 生のヘッダー文字列を parse_retry_after へ渡す。\r\n は printf %b で実際の CR と LF にする。
ra_headers() {
  printf '%b' "$1" | parse_retry_after
}

cfg_run() {
  _fn=$1
  _show=$2
  shift 2
# shellcheck disable=SC2016 # 単一引用符の中の $1、$2 は子の sh が展開する（引数の受け渡し）
  env -i PATH="$PATH" "$@" sh -c '
    . "$1" || exit 99
    "$2"
    _rc=$?
    if [ "$3" != "-" ]; then
      eval "printf %s \"\$$3\""
    fi
    exit "$_rc"
  ' sh "$LIB" "$_fn" "$_show"
}

ep_obs() {
  _what=$1
  _tape=$2
  shift 2
  _work=$(mktemp -d "${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}/m06-ep.XXXXXX")
  trap 'rm -f "$_work"/* ; rmdir "$_work"' EXIT

  # 台本は空白区切りの1語ずつを1行にする。語の中に glob 文字は含まれない。
# shellcheck disable=SC2086 # 台本は検査が渡す固定の文字列（呼び出し元の ep_obs の引数）で、空白で区切った語を1行ずつにする意図
  printf '%s\n' $_tape > "$_work/tape"

  cat > "$_work/curl" <<'STUB_CURL'
#!/bin/sh
# スタブ curl。呼び出しの引数を記録し、台本の n 試行目の応答を返す。
# --output と --dump-header の値は試行ごとに名前が変わるため、記録では <file> に置き換える。
d=$(dirname "$0")
n=0
if [ -f "$d/count" ]; then n=$(cat "$d/count"); fi
n=$((n + 1))
printf '%s\n' "$n" > "$d/count"
prev=
{
  for a in "$@"; do
    case $prev in
      --output|--dump-header) printf '[<file>]' ;;
      *) printf '[%s]' "$a" ;;
    esac
    prev=$a
  done
  printf '\n'
} >> "$d/calls"
out=
hdr=
wo=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) out=$2; shift 2 ;;
    --dump-header) hdr=$2; shift 2 ;;
    --write-out) wo=$2; shift 2 ;;
    --noproxy|--proxy|--connect-timeout|--max-time) shift 2 ;;
    *) shift ;;
  esac
done
line=$(sed -n "${n}p" "$d/tape")
if [ -z "$line" ]; then line=$(tail -n 1 "$d/tape"); fi
st=${line%%/*}
rest=${line#*/}
rc=${rest%%/*}
ra=${rest#*/}
if [ -n "$hdr" ]; then
  {
    printf 'HTTP/1.1 %s\r\n' "$st"
    if [ "$ra" != "-" ]; then printf 'Retry-After: %s\r\n' "$ra"; fi
    printf 'X-Secret: s3cr3t\r\n'
    printf '\r\n'
  } > "$hdr"
fi
if [ -n "$out" ]; then printf 'BODYTEXT' > "$out"; fi
if [ -n "$wo" ]; then printf '%s' "$st"; fi
exit "$rc"
STUB_CURL

  cat > "$_work/sleep" <<'STUB_SLEEP'
#!/bin/sh
# スタブ sleep。待機秒数を記録するだけで、実際には待たない。
d=$(dirname "$0")
printf '%s\n' "$1" >> "$d/sleeps"
STUB_SLEEP
  chmod 0755 "$_work/curl" "$_work/sleep"

  _rc=0
  env -i PATH="$_work:$PATH" HTTP_PROXY=http://proxy.test:3128 "$@" \
    sh "$ROOT/test-client/entrypoint.sh" >"$_work/out" 2>"$_work/err" || _rc=$?

  case $_what in
    stdout) cat "$_work/out" ;;
    stderr) cat "$_work/err" ;;
    rc) printf '%s' "$_rc" ;;
    curl_calls)
      if [ -f "$_work/calls" ]; then wc -l < "$_work/calls" | tr -d ' '; else printf '0'; fi
      ;;
    curl_args)
      if [ -f "$_work/calls" ]; then cat "$_work/calls"; fi
      ;;
    sleeps)
      _n=0
      _list=
      if [ -f "$_work/sleeps" ]; then
        _n=$(wc -l < "$_work/sleeps" | tr -d ' ')
        _list=$(paste -sd, "$_work/sleeps")
      fi
      printf 'count=%s waits=%s' "$_n" "$_list"
      ;;
    leak)
      # 診断は標準エラーに出る。URL、本文、Retry-After以外のヘッダー、設定値の混入を見る。
      _hit=
      for _p in BODYTEXT s3cr3t api.example.com secretpath http:// X-Secret; do
        if grep -q -F -e "$_p" "$_work/err"; then _hit="$_hit $_p"; fi
      done
      if [ -z "$_hit" ]; then printf 'clean'; else printf 'leak:%s' "$_hit"; fi
      ;;
  esac
  return 0
}

ep_text_check() { # 語 ファイル...
  _pat=$1
  shift
  for _f in "$@"; do
    if grep -q -F -e "$_pat" "$ROOT/$_f"; then
      printf 'present'
      return 0
    fi
  done
  printf 'absent'
}

# bats test_tags=unit
@test "5xx: 500は対象" {
  expect "5xx: 500は対象" 5xx 0 is_retryable_status 500
}

# bats test_tags=unit
@test "5xx: 503は対象" {
  expect "5xx: 503は対象" 5xx 0 is_retryable_status 503
}

# bats test_tags=unit
@test "429: 429は対象" {
  expect "429: 429は対象" 429 0 is_retryable_status 429
}

# bats test_tags=unit
@test "対象外: 200" {
  expect "対象外: 200" "" 1 is_retryable_status 200
}

# bats test_tags=unit
@test "対象外: 301" {
  expect "対象外: 301" "" 1 is_retryable_status 301
}

# bats test_tags=unit
@test "対象外: 404" {
  expect "対象外: 404" "" 1 is_retryable_status 404
}

# bats test_tags=unit
@test "対象外: 501" {
  expect "対象外: 501" "" 1 is_retryable_status 501
}

# bats test_tags=unit
@test "対象外: 502" {
  expect "対象外: 502" "" 1 is_retryable_status 502
}

# bats test_tags=unit
@test "対象外: 504" {
  expect "対象外: 504" "" 1 is_retryable_status 504
}

# bats test_tags=unit
@test "backoff: n=1 base=1 上限30は1" {
  expect "backoff: n=1 base=1 上限30は1" 1 0 backoff_wait_5xx 1 1 30
}

# bats test_tags=unit
@test "backoff: n=2 base=1 上限30は2" {
  expect "backoff: n=2 base=1 上限30は2" 2 0 backoff_wait_5xx 2 1 30
}

# bats test_tags=unit
@test "backoff: n=3 base=1 上限30は4" {
  expect "backoff: n=3 base=1 上限30は4" 4 0 backoff_wait_5xx 3 1 30
}

# bats test_tags=unit
@test "backoff: n=3 base=1 上限3で打ち切り" {
  expect "backoff: n=3 base=1 上限3で打ち切り" 3 0 backoff_wait_5xx 3 1 3
}

# bats test_tags=unit
@test "backoff: base=0は常に0" {
  expect "backoff: base=0は常に0" 0 0 backoff_wait_5xx 1 0 30
}

# bats test_tags=unit
@test "backoff: base=0のn=3も0" {
  expect "backoff: base=0のn=3も0" 0 0 backoff_wait_5xx 3 0 30
}

# bats test_tags=unit
@test "backoff: n=1で基準が上限ちょうど" {
  expect "backoff: n=1で基準が上限ちょうど" 30 0 backoff_wait_5xx 1 30 30
}

# bats test_tags=unit
@test "backoff: 大きなnでも上限で止まる" {
  expect "backoff: 大きなnでも上限で止まる" 30 0 backoff_wait_5xx 40 1 30
}

# bats test_tags=unit
@test "429待機: Retry-After上限ちょうど" {
  expect "429待機: Retry-After上限ちょうど" "30 0" 0 resolve_429_wait 30 2 30
}

# bats test_tags=unit
@test "429待機: Retry-After上限+1で切り詰め" {
  expect "429待機: Retry-After上限+1で切り詰め" "30 1" 0 resolve_429_wait 31 2 30
}

# bats test_tags=unit
@test "429待機: Retry-After 0秒" {
  expect "429待機: Retry-After 0秒" "0 0" 0 resolve_429_wait 0 2 30
}

# bats test_tags=unit
@test "429待機: 値なしは既定待機" {
  expect "429待機: 値なしは既定待機" "2 0" 0 resolve_429_wait "" 2 30
}

# bats test_tags=unit
@test "429待機: 既定待機が上限超過は上限へ切り詰め" {
  expect "429待機: 既定待機が上限超過は上限へ切り詰め" "30 1" 0 resolve_429_wait "" 40 30
}

# bats test_tags=unit
@test "Retry-After: 0は0" {
  expect "Retry-After: 0は0" 0 0 ra_headers 'HTTP/1.1 429\r\nRetry-After: 0\r\n\r\n'
}

# bats test_tags=unit
@test "Retry-After: 5は5" {
  expect "Retry-After: 5は5" 5 0 ra_headers 'Retry-After: 5\r\n'
}

# bats test_tags=unit
@test "Retry-After: 999999は999999" {
  expect "Retry-After: 999999は999999" 999999 0 ra_headers 'Retry-After: 999999\r\n'
}

# bats test_tags=unit
@test "Retry-After: 上限ちょうど1000000は1000000" {
  expect "Retry-After: 上限ちょうど1000000は1000000" 1000000 0 ra_headers 'Retry-After: 1000000\r\n'
}

# bats test_tags=unit
@test "大文字ヘッダー名RETRY-AFTERを認識" {
  expect "大文字ヘッダー名RETRY-AFTERを認識" 7 0 ra_headers 'RETRY-AFTER: 7\r\n'
}

# bats test_tags=unit
@test "混在大小文字retry-AfterとCR付き" {
  expect "混在大小文字retry-AfterとCR付き" 8 0 ra_headers 'retry-After: 8\r\n'
}

# bats test_tags=unit
@test "同名が複数あれば最後の値" {
  expect "同名が複数あれば最後の値" 9 0 ra_headers 'Retry-After: 3\r\nRetry-After: 9\r\n'
}

# bats test_tags=unit
@test "値の前後の空白は除く" {
  expect "値の前後の空白は除く" 4 0 ra_headers 'Retry-After:   4  \r\n'
}

# bats test_tags=unit
@test "7桁は上限超過として1000000" {
  expect "7桁は上限超過として1000000" 1000000 0 ra_headers 'Retry-After: 1234567\r\n'
}

# bats test_tags=unit
@test "20桁の数字列は1000000" {
  expect "20桁の数字列は1000000" 1000000 0 ra_headers 'Retry-After: 12345678901234567890\r\n'
}

# bats test_tags=unit
@test "先頭0の0000005は5" {
  expect "先頭0の0000005は5" 5 0 ra_headers 'Retry-After: 0000005\r\n'
}

# bats test_tags=unit
@test "全部0の0000000は0" {
  expect "全部0の0000000は0" 0 0 ra_headers 'Retry-After: 0000000\r\n'
}

# bats test_tags=unit
@test "ヘッダーなしは不在" {
  expect "ヘッダーなしは不在" "" 1 ra_headers 'HTTP/1.1 429\r\nContent-Type: text/plain\r\n\r\n'
}

# bats test_tags=unit
@test "空入力は不在" {
  expect "空入力は不在" "" 1 ra_headers ''
}

# bats test_tags=unit
@test "負数は不在" {
  expect "負数は不在" "" 1 ra_headers 'Retry-After: -1\r\n'
}

# bats test_tags=unit
@test "小数は不在" {
  expect "小数は不在" "" 1 ra_headers 'Retry-After: 1.5\r\n'
}

# bats test_tags=unit
@test "HTTP日付は不在" {
  expect "HTTP日付は不在" "" 1 ra_headers 'Retry-After: Wed, 21 Oct 2015 07:28:00 GMT\r\n'
}

# bats test_tags=unit
@test "数字以外を含む値は不在" {
  expect "数字以外を含む値は不在" "" 1 ra_headers 'Retry-After: 5 seconds\r\n'
}

# bats test_tags=unit
@test "値が空は不在" {
  expect "値が空は不在" "" 1 ra_headers 'Retry-After:\r\n'
}

# bats test_tags=unit
@test "既定値: 未設定の5xx回数は3" {
  expect "既定値: 未設定の5xx回数は3" 3 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_5XX
}

# bats test_tags=unit
@test "既定値: 未設定の基準秒は1" {
  expect "既定値: 未設定の基準秒は1" 1 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS
}

# bats test_tags=unit
@test "既定値: 未設定の429回数は3" {
  expect "既定値: 未設定の429回数は3" 3 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_429
}

# bats test_tags=unit
@test "既定値: 未設定の429既定待機は2" {
  expect "既定値: 未設定の429既定待機は2" 2 0 cfg_run apply_config_defaults RETRY_429_DEFAULT_WAIT_SECONDS
}

# bats test_tags=unit
@test "既定値: 未設定の上限待機は30" {
  expect "既定値: 未設定の上限待機は30" 30 0 cfg_run apply_config_defaults RETRY_MAX_WAIT_SECONDS
}

# bats test_tags=unit
@test "既定値: 未設定の接続タイムアウトは5" {
  expect "既定値: 未設定の接続タイムアウトは5" 5 0 cfg_run apply_config_defaults CONNECT_TIMEOUT_SECONDS
}

# bats test_tags=unit
@test "既定値: 未設定の応答タイムアウトは10" {
  expect "既定値: 未設定の応答タイムアウトは10" 10 0 cfg_run apply_config_defaults RESPONSE_TIMEOUT_SECONDS
}

# bats test_tags=unit
@test "既定値: 空文字は既定値" {
  expect "既定値: 空文字は既定値" 1 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS RETRY_BACKOFF_BASE_SECONDS=
}

# bats test_tags=unit
@test "正規化: 007は7（8進数と誤解しない）" {
  expect "正規化: 007は7（8進数と誤解しない）" 7 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS RETRY_BACKOFF_BASE_SECONDS=007
}

# bats test_tags=unit
@test "正規化: 08は8（8進数エラーにしない）" {
  expect "正規化: 08は8（8進数エラーにしない）" 8 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_5XX RETRY_MAX_ATTEMPTS_5XX=08
}

# bats test_tags=unit
@test "正規化: 000は0" {
  expect "正規化: 000は0" 0 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_429 RETRY_MAX_ATTEMPTS_429=000
}

# bats test_tags=unit
@test "検証: 全部未設定は通る" {
  expect "検証: 全部未設定は通る" "" 0 cfg_run validate_config -
}

# bats test_tags=unit
@test "検証: 回数0は有効" {
  expect "検証: 回数0は有効" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "検証: 空文字は既定値として通る" {
  expect "検証: 空文字は既定値として通る" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=
}

# bats test_tags=unit
@test "検証: 負数は不正" {
  expect "検証: 負数は不正" RETRY_MAX_ATTEMPTS_5XX 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "検証: 非数値は不正" {
  expect "検証: 非数値は不正" RETRY_BACKOFF_BASE_SECONDS 1 cfg_run validate_config - RETRY_BACKOFF_BASE_SECONDS=abc
}

# bats test_tags=unit
@test "検証: 小数は不正" {
  expect "検証: 小数は不正" RETRY_MAX_ATTEMPTS_429 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_429=1.5
}

# bats test_tags=unit
@test "検証: 7桁は不正" {
  expect "検証: 7桁は不正" RETRY_429_DEFAULT_WAIT_SECONDS 1 cfg_run validate_config - RETRY_429_DEFAULT_WAIT_SECONDS=1234567
}

# bats test_tags=unit
@test "検証: 上限待機の7桁は不正" {
  expect "検証: 上限待機の7桁は不正" RETRY_MAX_WAIT_SECONDS 1 cfg_run validate_config - RETRY_MAX_WAIT_SECONDS=1000000
}

# bats test_tags=unit
@test "検証: 上限待機の999999は有効" {
  expect "検証: 上限待機の999999は有効" "" 0 cfg_run validate_config - RETRY_MAX_WAIT_SECONDS=999999
}

# bats test_tags=unit
@test "検証: 接続タイムアウト0は不正" {
  expect "検証: 接続タイムアウト0は不正" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=0
}

# bats test_tags=unit
@test "検証: 接続タイムアウト00も0扱いで不正" {
  expect "検証: 接続タイムアウト00も0扱いで不正" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=00
}

# bats test_tags=unit
@test "検証: 応答タイムアウト0は不正" {
  expect "検証: 応答タイムアウト0は不正" RESPONSE_TIMEOUT_SECONDS 1 cfg_run validate_config - RESPONSE_TIMEOUT_SECONDS=0
}

# bats test_tags=unit
@test "検証: 接続が応答より大きくても不正にしない" {
  expect "検証: 接続が応答より大きくても不正にしない" "" 0 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=20 RESPONSE_TIMEOUT_SECONDS=5
}

# bats test_tags=unit
@test "検証: 先頭0の007は有効" {
  expect "検証: 先頭0の007は有効" "" 0 cfg_run validate_config - RETRY_BACKOFF_BASE_SECONDS=007
}

# bats test_tags=unit
@test "検証: 先頭0の08は有効" {
  expect "検証: 先頭0の08は有効" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=08
}

# bats test_tags=unit
@test "検証: 20桁の数字は不正" {
  expect "検証: 20桁の数字は不正" RETRY_429_DEFAULT_WAIT_SECONDS 1 cfg_run validate_config - RETRY_429_DEFAULT_WAIT_SECONDS=12345678901234567890
}

# bats test_tags=unit
@test "検査順: 5xx回数が上限待機より先" {
  expect "検査順: 5xx回数が上限待機より先" RETRY_MAX_ATTEMPTS_5XX 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=-1 RETRY_MAX_WAIT_SECONDS=x
}

# bats test_tags=unit
@test "検査順: 基準秒が429回数より先" {
  expect "検査順: 基準秒が429回数より先" RETRY_BACKOFF_BASE_SECONDS 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_429=bad RETRY_BACKOFF_BASE_SECONDS=bad
}

# bats test_tags=unit
@test "検査順: 接続が応答より先" {
  expect "検査順: 接続が応答より先" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - RESPONSE_TIMEOUT_SECONDS=0 CONNECT_TIMEOUT_SECONDS=abc
}

# bats test_tags=unit
@test "T605 プロキシ未設定はproxy_not_configuredだけ" {
  expect "T605 プロキシ未設定はproxy_not_configuredだけ" \
    "CLIENT_ERROR=proxy_not_configured" 0 ep_obs stderr "200/0/-" HTTP_PROXY=
}

# bats test_tags=unit
@test "T605 プロキシ未設定の終了コードは78" {
  expect "T605 プロキシ未設定の終了コードは78" 78 0 ep_obs rc "200/0/-" HTTP_PROXY=
}

# bats test_tags=unit
@test "T605 プロキシ未設定で設定不備もあるならproxy優先" {
  expect "T605 プロキシ未設定で設定不備もあるならproxy優先" \
    "CLIENT_ERROR=proxy_not_configured" 0 ep_obs stderr "200/0/-" HTTP_PROXY= RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "T605 プロキシ未設定なら通信しない" {
  expect "T605 プロキシ未設定なら通信しない" 0 0 ep_obs curl_calls "200/0/-" HTTP_PROXY=
}

# bats test_tags=unit
@test "T605 設定不備の標準エラーは識別子と変数名のみ" {
  expect "T605 設定不備の標準エラーは識別子と変数名のみ" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=RETRY_MAX_ATTEMPTS_5XX" 0 \
    ep_obs stderr "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "T605 設定不備の終了コードは78" {
  expect "T605 設定不備の終了コードは78" 78 0 ep_obs rc "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "T605 設定不備では標準出力が空" {
  expect "T605 設定不備では標準出力が空" "" 0 ep_obs stdout "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "T605 設定不備では curl を呼ばない" {
  expect "T605 設定不備では curl を呼ばない" 0 0 ep_obs curl_calls "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
}

# bats test_tags=unit
@test "T605 不正が2つなら表順で先の変数名だけ" {
  expect "T605 不正が2つなら表順で先の変数名だけ" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=RETRY_BACKOFF_BASE_SECONDS" 0 \
    ep_obs stderr "200/0/-" RETRY_MAX_ATTEMPTS_429=bad RETRY_BACKOFF_BASE_SECONDS=bad
}

# bats test_tags=unit
@test "T605 接続が応答より先に検査される" {
  expect "T605 接続が応答より先に検査される" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=CONNECT_TIMEOUT_SECONDS" 0 \
    ep_obs stderr "200/0/-" RESPONSE_TIMEOUT_SECONDS=0 CONNECT_TIMEOUT_SECONDS=abc
}

# bats test_tags=unit
@test "T605 正常な設定では curl が1回呼ばれる" {
  expect "T605 正常な設定では curl が1回呼ばれる" 1 0 ep_obs curl_calls "200/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "T606 200の1回成功は標準出力2行" {
  expect "T606 200の1回成功は標準出力2行" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "200/0/-"
}

# bats test_tags=unit
@test "T606 200の1回成功はsleep0回" {
  expect "T606 200の1回成功はsleep0回" "count=0 waits=" 0 ep_obs sleeps "200/0/-"
}

# bats test_tags=unit
@test "T606 200の1回成功は終了コード0" {
  expect "T606 200の1回成功は終了コード0" 0 0 ep_obs rc "200/0/-"
}

# bats test_tags=unit
@test "T606 500が続く（回数3、base=1）は待機1,2,4" {
  expect "T606 500が続く（回数3、base=1）は待機1,2,4" "count=3 waits=1,2,4" 0 \
    ep_obs sleeps "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T606 500が続く（回数3）は4試行" {
  expect "T606 500が続く（回数3）は4試行" 4 0 ep_obs curl_calls "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T606 500が続く上限到達は最後のステータスを出す" {
  expect "T606 500が続く上限到達は最後のステータスを出す" \
    "CLIENT_STATUS=500
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T606 500が続く上限到達も終了コード0" {
  expect "T606 500が続く上限到達も終了コード0" 0 0 ep_obs rc "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T606 500の後の200で途中停止" {
  expect "T606 500の後の200で途中停止" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 200/0/-"
}

# bats test_tags=unit
@test "T606 500の後の200は待機1回" {
  expect "T606 500の後の200は待機1回" "count=1 waits=1" 0 ep_obs sleeps "500/0/- 200/0/-"
}

# bats test_tags=unit
@test "T606 503と500の混在は5xxカウンターを共有" {
  expect "T606 503と500の混在は5xxカウンターを共有" "count=3 waits=1,2,4" 0 \
    ep_obs sleeps "503/0/- 500/0/- 503/0/- 500/0/-"
}

# bats test_tags=unit
@test "T606 429でRetry-After上限超過は上限30へ切り詰め" {
  expect "T606 429でRetry-After上限超過は上限30へ切り詰め" "count=1 waits=30" 0 \
    ep_obs sleeps "429/0/120 200/0/-"
}

# bats test_tags=unit
@test "T606 429で7桁のRetry-Afterは上限30へ切り詰め" {
  expect "T606 429で7桁のRetry-Afterは上限30へ切り詰め" "count=1 waits=30" 0 \
    ep_obs sleeps "429/0/1234567 200/0/-"
}

# bats test_tags=unit
@test "T606 429でRetry-Afterなしは既定2のまま増えない" {
  expect "T606 429でRetry-Afterなしは既定2のまま増えない" "count=3 waits=2,2,2" 0 \
    ep_obs sleeps "429/0/- 429/0/- 429/0/- 429/0/-"
}

# bats test_tags=unit
@test "T606 429と500の混在は各カウンターが独立" {
  expect "T606 429と500の混在は各カウンターが独立" "count=3 waits=2,1,2" 0 \
    ep_obs sleeps "429/0/- 500/0/- 429/0/- 429/0/-" RETRY_MAX_ATTEMPTS_5XX=1 RETRY_MAX_ATTEMPTS_429=2
}

# bats test_tags=unit
@test "T606 429と500の混在は429上限の4試行で止まる" {
  expect "T606 429と500の混在は429上限の4試行で止まる" 4 0 \
    ep_obs curl_calls "429/0/- 500/0/- 429/0/- 429/0/-" RETRY_MAX_ATTEMPTS_5XX=1 RETRY_MAX_ATTEMPTS_429=2
}

# bats test_tags=unit
@test "T606 5xx回数0の500は1回で終了" {
  expect "T606 5xx回数0の500は1回で終了" 1 0 ep_obs curl_calls "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "T606 5xx回数0の500は待機なし" {
  expect "T606 5xx回数0の500は待機なし" "count=0 waits=" 0 ep_obs sleeps "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "T606 5xx回数0の500は終了コード0" {
  expect "T606 5xx回数0の500は終了コード0" 0 0 ep_obs rc "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "T606 429回数0の429は1回で終了" {
  expect "T606 429回数0の429は1回で終了" 1 0 ep_obs curl_calls "429/0/120" RETRY_MAX_ATTEMPTS_429=0
}

# bats test_tags=unit
@test "T606 対象外404は1回で返しsleepなし" {
  expect "T606 対象外404は1回で返しsleepなし" "count=0 waits=" 0 ep_obs sleeps "404/0/-"
}

# bats test_tags=unit
@test "T606 対象外404は標準出力に404を出す" {
  expect "T606 対象外404は標準出力に404を出す" \
    "CLIENT_STATUS=404
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "404/0/-"
}

# bats test_tags=unit
@test "T606 待機0秒でもsleepを呼ぶ" {
  expect "T606 待機0秒でもsleepを呼ぶ" "count=2 waits=0,0" 0 \
    ep_obs sleeps "500/0/- 500/0/- 200/0/-" RETRY_BACKOFF_BASE_SECONDS=0
}

# bats test_tags=unit
@test "T607 既定のcurl引数は設定値付きでM04の順を保つ" {
  expect "T607 既定のcurl引数は設定値付きでM04の順を保つ" \
    "[--noproxy][][--proxy][http://proxy.test:3128][--silent][--show-error][--connect-timeout][5][--max-time][10][--dump-header][<file>][--output][<file>][--write-out][%{http_code}][--url][http://api.example.com/api/users/123]" 0 \
    ep_obs curl_args "200/0/-"
}

# bats test_tags=unit
@test "T607 タイムアウト設定の値が引数に入る" {
  expect "T607 タイムアウト設定の値が引数に入る" \
    "[--noproxy][][--proxy][http://proxy.test:3128][--silent][--show-error][--connect-timeout][3][--max-time][7][--dump-header][<file>][--output][<file>][--write-out][%{http_code}][--url][http://api.example.com/api/users/123]" 0 \
    ep_obs curl_args "200/0/-" CONNECT_TIMEOUT_SECONDS=3 RESPONSE_TIMEOUT_SECONDS=7
}

# bats test_tags=unit
@test "T607 タイムアウトの標準エラーはtimeoutだけ" {
  expect "T607 タイムアウトの標準エラーはtimeoutだけ" \
    "CLIENT_ERROR=timeout
CLIENT_DIAG result=timeout attempts=1 curl_exit=28" 0 ep_obs stderr "000/28/-"
}

# bats test_tags=unit
@test "T607 タイムアウトの標準出力は空" {
  expect "T607 タイムアウトの標準出力は空" "" 0 ep_obs stdout "000/28/-"
}

# bats test_tags=unit
@test "T607 タイムアウトの終了コードは28" {
  expect "T607 タイムアウトの終了コードは28" 28 0 ep_obs rc "000/28/-"
}

# bats test_tags=unit
@test "T607 タイムアウトはリトライしない（sleep0回）" {
  expect "T607 タイムアウトはリトライしない（sleep0回）" "count=0 waits=" 0 \
    ep_obs sleeps "000/28/- 200/0/-"
}

# bats test_tags=unit
@test "T607 タイムアウトの試行は1回" {
  expect "T607 タイムアウトの試行は1回" 1 0 ep_obs curl_calls "000/28/- 200/0/-"
}

# bats test_tags=unit
@test "T607 接続拒否はcurl_exit_7" {
  expect "T607 接続拒否はcurl_exit_7" \
    "CLIENT_ERROR=curl_exit_7
CLIENT_DIAG curl_failed attempts=1 curl_exit=7" 0 ep_obs stderr "000/7/-"
}

# bats test_tags=unit
@test "T607 接続拒否の終了コードは7" {
  expect "T607 接続拒否の終了コードは7" 7 0 ep_obs rc "000/7/-"
}

# bats test_tags=unit
@test "T607 接続拒否はsleep0回" {
  expect "T607 接続拒否はsleep0回" "count=0 waits=" 0 ep_obs sleeps "000/7/- 200/0/-"
}

# bats test_tags=unit
@test "T608 200の成功行" {
  expect "T608 200の成功行" "CLIENT_DIAG result=success attempts=1 status=200" 0 \
    ep_obs stderr "200/0/-"
}

# bats test_tags=unit
@test "T608 503から200の再試行行と成功行" {
  expect "T608 503から200の再試行行と成功行" \
    "CLIENT_DIAG retry attempt=1 status=503 class=5xx retry=1/3 wait=1
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "503/0/- 200/0/-"
}

# bats test_tags=unit
@test "T608 429でRetry-Afterありの切り詰め行" {
  expect "T608 429でRetry-Afterありの切り詰め行" \
    "CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/3 retry_after=120 wait=30 capped=1
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "429/0/120 200/0/-"
}

# bats test_tags=unit
@test "T608 429でRetry-Afterなしの行" {
  expect "T608 429でRetry-Afterなしの行" \
    "CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/3 retry_after=none wait=2 capped=0
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "429/0/- 200/0/-"
}

# bats test_tags=unit
@test "T608 上限到達はretry行3つとretries_exhausted" {
  expect "T608 上限到達はretry行3つとretries_exhausted" \
    "CLIENT_DIAG retry attempt=1 status=500 class=5xx retry=1/3 wait=1
CLIENT_DIAG retry attempt=2 status=500 class=5xx retry=2/3 wait=2
CLIENT_DIAG retry attempt=3 status=500 class=5xx retry=3/3 wait=4
CLIENT_DIAG result=retries_exhausted attempts=4 status=500" 0 \
    ep_obs stderr "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T608 回数0の上限到達は最終行だけ" {
  expect "T608 回数0の上限到達は最終行だけ" \
    "CLIENT_DIAG result=retries_exhausted attempts=1 status=500" 0 \
    ep_obs stderr "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# bats test_tags=unit
@test "T608 対象外404はresult=success" {
  expect "T608 対象外404はresult=success" "CLIENT_DIAG result=success attempts=1 status=404" 0 \
    ep_obs stderr "404/0/-"
}

# bats test_tags=unit
@test "T608 503の再試行でも標準出力は2行のみ" {
  expect "T608 503の再試行でも標準出力は2行のみ" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "503/0/- 200/0/-"
}

# bats test_tags=unit
@test "T608 上限到達でも標準出力にCLIENT_DIAGを混ぜない" {
  expect "T608 上限到達でも標準出力にCLIENT_DIAGを混ぜない" \
    "CLIENT_STATUS=500
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T608 429の再試行でも標準出力にCLIENT_DIAGを混ぜない" {
  expect "T608 429の再試行でも標準出力にCLIENT_DIAGを混ぜない" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "429/0/120 200/0/-"
}

# bats test_tags=unit
@test "T608 タイムアウトの標準出力は空" {
  expect "T608 タイムアウトの標準出力は空" "" 0 ep_obs stdout "000/28/-"
}

# bats test_tags=unit
@test "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（再試行あり）" {
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（再試行あり）" "clean" 0 \
    ep_obs leak "429/0/120 200/0/-"
}

# bats test_tags=unit
@test "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（上限到達）" {
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（上限到達）" "clean" 0 \
    ep_obs leak "500/0/- 500/0/- 500/0/- 500/0/-"
}

# bats test_tags=unit
@test "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（タイムアウト）" {
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（タイムアウト）" "clean" 0 \
    ep_obs leak "000/28/-"
}

# bats test_tags=unit
@test "T608 retry-lib.shとentrypoint.shにwiremockがない" {
  expect "T608 retry-lib.shとentrypoint.shにwiremockがない" "absent" 0 \
    ep_text_check wiremock test-client/retry-lib.sh test-client/entrypoint.sh
}

# bats test_tags=unit
@test "T608 retry-lib.shとentrypoint.shに:8080がない" {
  expect "T608 retry-lib.shとentrypoint.shに:8080がない" "absent" 0 \
    ep_text_check ':8080' test-client/retry-lib.sh test-client/entrypoint.sh
}

# bats test_tags=unit
@test "m06_retry_after: Retry-After 120 は 429 の待機を上限30へ切り詰める" {
  expect "m06_retry_after: Retry-After 120 は 429 の待機を上限30へ切り詰める" "30 1" 0 resolve_429_wait 120 2 30
}

# bats test_tags=unit
@test "m06_retry_after: CR付きRetry-After 5 を解析する" {
  expect "m06_retry_after: CR付きRetry-After 5 を解析する" 5 0 ra_headers 'Retry-After: 5\r\n'
}

# bats test_tags=unit
@test "m06_timeout_exit_28: タイムアウトの終了コードは28" {
  expect "m06_timeout_exit_28: タイムアウトの終了コードは28" 28 0 ep_obs rc "000/28/-"
}
