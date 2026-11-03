#!/bin/sh
# M06 の検査入口。unit は retry-lib.sh の関数を直接呼ぶだけで、Compose も Docker も使わない。
# smoke は unit に続けて、squid、WireMock、test-client を実際に起動して通しで確かめる。
# 外部の API には出ない。通信はすべて Compose の閉じたネットワーク内で行う。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/test-client/retry-lib.sh"
MODE=${1:-smoke}

failures=0
total=0

# 期待する標準出力と終了コードを比べる。失敗した検査名は標準エラーへ出す。
expect() { # 検査名 期待出力 期待終了コード コマンド [引数...]
  _name=$1
  _want_out=$2
  _want_rc=$3
  shift 3
  total=$((total + 1))
  _got_out=$("$@" 2>/dev/null) && _got_rc=0 || _got_rc=$?
  if [ "$_got_out" = "$_want_out" ] && [ "$_got_rc" -eq "$_want_rc" ]; then
    return 0
  fi
  failures=$((failures + 1))
  printf 'FAIL: %s (期待 出力=[%s] rc=%s / 実際 出力=[%s] rc=%s)\n' \
    "$_name" "$_want_out" "$_want_rc" "$_got_out" "$_got_rc" >&2
}

unit_retryable_status() {
  expect "5xx: 500は対象" 5xx 0 is_retryable_status 500
  expect "5xx: 503は対象" 5xx 0 is_retryable_status 503
  expect "429: 429は対象" 429 0 is_retryable_status 429
  expect "対象外: 200" "" 1 is_retryable_status 200
  expect "対象外: 301" "" 1 is_retryable_status 301
  expect "対象外: 404" "" 1 is_retryable_status 404
  expect "対象外: 501" "" 1 is_retryable_status 501
  expect "対象外: 502" "" 1 is_retryable_status 502
  expect "対象外: 504" "" 1 is_retryable_status 504
}

unit_backoff_5xx() {
  expect "backoff: n=1 base=1 上限30は1" 1 0 backoff_wait_5xx 1 1 30
  expect "backoff: n=2 base=1 上限30は2" 2 0 backoff_wait_5xx 2 1 30
  expect "backoff: n=3 base=1 上限30は4" 4 0 backoff_wait_5xx 3 1 30
  expect "backoff: n=3 base=1 上限3で打ち切り" 3 0 backoff_wait_5xx 3 1 3
  expect "backoff: base=0は常に0" 0 0 backoff_wait_5xx 1 0 30
  expect "backoff: base=0のn=3も0" 0 0 backoff_wait_5xx 3 0 30
  expect "backoff: n=1で基準が上限ちょうど" 30 0 backoff_wait_5xx 1 30 30
  expect "backoff: 大きなnでも上限で止まる" 30 0 backoff_wait_5xx 40 1 30
}

unit_wait_429() {
  expect "429待機: Retry-After上限ちょうど" "30 0" 0 resolve_429_wait 30 2 30
  expect "429待機: Retry-After上限+1で切り詰め" "30 1" 0 resolve_429_wait 31 2 30
  expect "429待機: Retry-After 0秒" "0 0" 0 resolve_429_wait 0 2 30
  expect "429待機: 値なしは既定待機" "2 0" 0 resolve_429_wait "" 2 30
  expect "429待機: 既定待機が上限超過は上限へ切り詰め" "30 1" 0 resolve_429_wait "" 40 30
}

# 生のヘッダー文字列を parse_retry_after へ渡す。\r\n は printf %b で実際の CR と LF にする。
ra_headers() {
  printf '%b' "$1" | parse_retry_after
}

unit_parse_retry_after() {
  expect "Retry-After: 0は0" 0 0 ra_headers 'HTTP/1.1 429\r\nRetry-After: 0\r\n\r\n'
  expect "Retry-After: 5は5" 5 0 ra_headers 'Retry-After: 5\r\n'
  expect "Retry-After: 999999は999999" 999999 0 ra_headers 'Retry-After: 999999\r\n'
  expect "Retry-After: 上限ちょうど1000000は1000000" 1000000 0 ra_headers 'Retry-After: 1000000\r\n'
  expect "大文字ヘッダー名RETRY-AFTERを認識" 7 0 ra_headers 'RETRY-AFTER: 7\r\n'
  expect "混在大小文字retry-AfterとCR付き" 8 0 ra_headers 'retry-After: 8\r\n'
  expect "同名が複数あれば最後の値" 9 0 ra_headers 'Retry-After: 3\r\nRetry-After: 9\r\n'
  expect "値の前後の空白は除く" 4 0 ra_headers 'Retry-After:   4  \r\n'
  expect "7桁は上限超過として1000000" 1000000 0 ra_headers 'Retry-After: 1234567\r\n'
  expect "20桁の数字列は1000000" 1000000 0 ra_headers 'Retry-After: 12345678901234567890\r\n'
  expect "先頭0の0000005は5" 5 0 ra_headers 'Retry-After: 0000005\r\n'
  expect "全部0の0000000は0" 0 0 ra_headers 'Retry-After: 0000000\r\n'
  expect "ヘッダーなしは不在" "" 1 ra_headers 'HTTP/1.1 429\r\nContent-Type: text/plain\r\n\r\n'
  expect "空入力は不在" "" 1 ra_headers ''
  expect "負数は不在" "" 1 ra_headers 'Retry-After: -1\r\n'
  expect "小数は不在" "" 1 ra_headers 'Retry-After: 1.5\r\n'
  expect "HTTP日付は不在" "" 1 ra_headers 'Retry-After: Wed, 21 Oct 2015 07:28:00 GMT\r\n'
  expect "数字以外を含む値は不在" "" 1 ra_headers 'Retry-After: 5 seconds\r\n'
  expect "値が空は不在" "" 1 ra_headers 'Retry-After:\r\n'
}

# 設定値の検査は親シェルの RETRY_* を持ち込まないよう env -i で子 sh を起動する。
# 第1引数は関数名、第2引数は結果を出す変数名（- なら出さない）、残りは NAME=VALUE。
cfg_run() {
  _fn=$1
  _show=$2
  shift 2
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

unit_config() {
  expect "既定値: 未設定の5xx回数は3" 3 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_5XX
  expect "既定値: 未設定の基準秒は1" 1 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS
  expect "既定値: 未設定の429回数は3" 3 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_429
  expect "既定値: 未設定の429既定待機は2" 2 0 cfg_run apply_config_defaults RETRY_429_DEFAULT_WAIT_SECONDS
  expect "既定値: 未設定の上限待機は30" 30 0 cfg_run apply_config_defaults RETRY_MAX_WAIT_SECONDS
  expect "既定値: 未設定の接続タイムアウトは5" 5 0 cfg_run apply_config_defaults CONNECT_TIMEOUT_SECONDS
  expect "既定値: 未設定の応答タイムアウトは10" 10 0 cfg_run apply_config_defaults RESPONSE_TIMEOUT_SECONDS
  expect "既定値: 空文字は既定値" 1 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS RETRY_BACKOFF_BASE_SECONDS=
  expect "正規化: 007は7（8進数と誤解しない）" 7 0 cfg_run apply_config_defaults RETRY_BACKOFF_BASE_SECONDS RETRY_BACKOFF_BASE_SECONDS=007
  expect "正規化: 08は8（8進数エラーにしない）" 8 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_5XX RETRY_MAX_ATTEMPTS_5XX=08
  expect "正規化: 000は0" 0 0 cfg_run apply_config_defaults RETRY_MAX_ATTEMPTS_429 RETRY_MAX_ATTEMPTS_429=000

  expect "検証: 全部未設定は通る" "" 0 cfg_run validate_config -
  expect "検証: 回数0は有効" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=0
  expect "検証: 空文字は既定値として通る" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=
  expect "検証: 負数は不正" RETRY_MAX_ATTEMPTS_5XX 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=-1
  expect "検証: 非数値は不正" RETRY_BACKOFF_BASE_SECONDS 1 cfg_run validate_config - RETRY_BACKOFF_BASE_SECONDS=abc
  expect "検証: 小数は不正" RETRY_MAX_ATTEMPTS_429 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_429=1.5
  expect "検証: 7桁は不正" RETRY_429_DEFAULT_WAIT_SECONDS 1 cfg_run validate_config - RETRY_429_DEFAULT_WAIT_SECONDS=1234567
  expect "検証: 上限待機の7桁は不正" RETRY_MAX_WAIT_SECONDS 1 cfg_run validate_config - RETRY_MAX_WAIT_SECONDS=1000000
  expect "検証: 上限待機の999999は有効" "" 0 cfg_run validate_config - RETRY_MAX_WAIT_SECONDS=999999
  expect "検証: 接続タイムアウト0は不正" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=0
  expect "検証: 接続タイムアウト00も0扱いで不正" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=00
  expect "検証: 応答タイムアウト0は不正" RESPONSE_TIMEOUT_SECONDS 1 cfg_run validate_config - RESPONSE_TIMEOUT_SECONDS=0
  expect "検証: 接続が応答より大きくても不正にしない" "" 0 cfg_run validate_config - CONNECT_TIMEOUT_SECONDS=20 RESPONSE_TIMEOUT_SECONDS=5
  expect "検証: 先頭0の007は有効" "" 0 cfg_run validate_config - RETRY_BACKOFF_BASE_SECONDS=007
  expect "検証: 先頭0の08は有効" "" 0 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=08
  expect "検証: 20桁の数字は不正" RETRY_429_DEFAULT_WAIT_SECONDS 1 cfg_run validate_config - RETRY_429_DEFAULT_WAIT_SECONDS=12345678901234567890

  expect "検査順: 5xx回数が上限待機より先" RETRY_MAX_ATTEMPTS_5XX 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_5XX=-1 RETRY_MAX_WAIT_SECONDS=x
  expect "検査順: 基準秒が429回数より先" RETRY_BACKOFF_BASE_SECONDS 1 cfg_run validate_config - RETRY_MAX_ATTEMPTS_429=bad RETRY_BACKOFF_BASE_SECONDS=bad
  expect "検査順: 接続が応答より先" CONNECT_TIMEOUT_SECONDS 1 cfg_run validate_config - RESPONSE_TIMEOUT_SECONDS=0 CONNECT_TIMEOUT_SECONDS=abc
}

# ---- entrypoint 検査（T605 から T608） ----
# entrypoint.sh が本物の curl と sleep を呼ぶと、実通信と実待機が起きて検査が遅くなり、
# 外部へ通信してしまう。そこで mktemp -d の一時ディレクトリに同名のスタブを置き、PATH の先頭に出す。
# 台本は試行ごとの「ステータス/curl終了コード/Retry-After」を1行ずつ並べたもので、
# スタブは呼び出しの順に1行ずつ返す。待機と呼び出しは記録だけして、実際には待たない。

# entrypoint を1回実行して、観測項目を標準出力へ出す。
# 第1引数は観測項目、第2引数は台本、残りは NAME=VALUE の上書き。後から書いた値が有効になる。
# 一時ディレクトリは KIROCREW_SCRATCH か TMPDIR の下に作り、EXIT で削除する。
ep_obs() {
  _what=$1
  _tape=$2
  shift 2
  _work=$(mktemp -d "${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}/m06-ep.XXXXXX")
  trap 'rm -f "$_work"/* ; rmdir "$_work"' EXIT

  # 台本は空白区切りの1語ずつを1行にする。語の中に glob 文字は含まれない。
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

# retry-lib.sh と entrypoint.sh の中に語があるかを見る。語があれば present、なければ absent。
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

# T605: 処理順は HTTP_PROXY 検査、設定検査の順。設定不備では curl を呼ばずに止まる。
unit_entrypoint_prep() {
  expect "T605 プロキシ未設定はproxy_not_configuredだけ" \
    "CLIENT_ERROR=proxy_not_configured" 0 ep_obs stderr "200/0/-" HTTP_PROXY=
  expect "T605 プロキシ未設定の終了コードは78" 78 0 ep_obs rc "200/0/-" HTTP_PROXY=
  expect "T605 プロキシ未設定で設定不備もあるならproxy優先" \
    "CLIENT_ERROR=proxy_not_configured" 0 ep_obs stderr "200/0/-" HTTP_PROXY= RETRY_MAX_ATTEMPTS_5XX=-1
  expect "T605 プロキシ未設定なら通信しない" 0 0 ep_obs curl_calls "200/0/-" HTTP_PROXY=

  expect "T605 設定不備の標準エラーは識別子と変数名のみ" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=RETRY_MAX_ATTEMPTS_5XX" 0 \
    ep_obs stderr "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
  expect "T605 設定不備の終了コードは78" 78 0 ep_obs rc "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
  expect "T605 設定不備では標準出力が空" "" 0 ep_obs stdout "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
  expect "T605 設定不備では curl を呼ばない" 0 0 ep_obs curl_calls "200/0/-" RETRY_MAX_ATTEMPTS_5XX=-1
  expect "T605 不正が2つなら表順で先の変数名だけ" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=RETRY_BACKOFF_BASE_SECONDS" 0 \
    ep_obs stderr "200/0/-" RETRY_MAX_ATTEMPTS_429=bad RETRY_BACKOFF_BASE_SECONDS=bad
  expect "T605 接続が応答より先に検査される" \
    "CLIENT_ERROR=invalid_config
CLIENT_DIAG invalid_config name=CONNECT_TIMEOUT_SECONDS" 0 \
    ep_obs stderr "200/0/-" RESPONSE_TIMEOUT_SECONDS=0 CONNECT_TIMEOUT_SECONDS=abc
  expect "T605 正常な設定では curl が1回呼ばれる" 1 0 ep_obs curl_calls "200/0/-" RETRY_MAX_ATTEMPTS_5XX=0
}

# T606: リトライループ。カウンターの独立、待機列、上限到達時の出力と終了コードを見る。
unit_entrypoint_retry() {
  expect "T606 200の1回成功は標準出力2行" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "200/0/-"
  expect "T606 200の1回成功はsleep0回" "count=0 waits=" 0 ep_obs sleeps "200/0/-"
  expect "T606 200の1回成功は終了コード0" 0 0 ep_obs rc "200/0/-"
  expect "T606 500が続く（回数3、base=1）は待機1,2,4" "count=3 waits=1,2,4" 0 \
    ep_obs sleeps "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T606 500が続く（回数3）は4試行" 4 0 ep_obs curl_calls "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T606 500が続く上限到達は最後のステータスを出す" \
    "CLIENT_STATUS=500
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T606 500が続く上限到達も終了コード0" 0 0 ep_obs rc "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T606 500の後の200で途中停止" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 200/0/-"
  expect "T606 500の後の200は待機1回" "count=1 waits=1" 0 ep_obs sleeps "500/0/- 200/0/-"
  expect "T606 503と500の混在は5xxカウンターを共有" "count=3 waits=1,2,4" 0 \
    ep_obs sleeps "503/0/- 500/0/- 503/0/- 500/0/-"
  expect "T606 429でRetry-After上限超過は上限30へ切り詰め" "count=1 waits=30" 0 \
    ep_obs sleeps "429/0/120 200/0/-"
  expect "T606 429で7桁のRetry-Afterは上限30へ切り詰め" "count=1 waits=30" 0 \
    ep_obs sleeps "429/0/1234567 200/0/-"
  expect "T606 429でRetry-Afterなしは既定2のまま増えない" "count=3 waits=2,2,2" 0 \
    ep_obs sleeps "429/0/- 429/0/- 429/0/- 429/0/-"
  expect "T606 429と500の混在は各カウンターが独立" "count=3 waits=2,1,2" 0 \
    ep_obs sleeps "429/0/- 500/0/- 429/0/- 429/0/-" RETRY_MAX_ATTEMPTS_5XX=1 RETRY_MAX_ATTEMPTS_429=2
  expect "T606 429と500の混在は429上限の4試行で止まる" 4 0 \
    ep_obs curl_calls "429/0/- 500/0/- 429/0/- 429/0/-" RETRY_MAX_ATTEMPTS_5XX=1 RETRY_MAX_ATTEMPTS_429=2
  expect "T606 5xx回数0の500は1回で終了" 1 0 ep_obs curl_calls "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
  expect "T606 5xx回数0の500は待機なし" "count=0 waits=" 0 ep_obs sleeps "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
  expect "T606 5xx回数0の500は終了コード0" 0 0 ep_obs rc "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
  expect "T606 429回数0の429は1回で終了" 1 0 ep_obs curl_calls "429/0/120" RETRY_MAX_ATTEMPTS_429=0
  expect "T606 対象外404は1回で返しsleepなし" "count=0 waits=" 0 ep_obs sleeps "404/0/-"
  expect "T606 対象外404は標準出力に404を出す" \
    "CLIENT_STATUS=404
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "404/0/-"
  expect "T606 待機0秒でもsleepを呼ぶ" "count=2 waits=0,0" 0 \
    ep_obs sleeps "500/0/- 500/0/- 200/0/-" RETRY_BACKOFF_BASE_SECONDS=0
}

# T607: タイムアウトと curl オプション。リトライしないこと、オプション値が設定値で入ることを見る。
unit_entrypoint_timeout() {
  expect "T607 既定のcurl引数は設定値付きでM04の順を保つ" \
    "[--noproxy][][--proxy][http://proxy.test:3128][--silent][--show-error][--connect-timeout][5][--max-time][10][--dump-header][<file>][--output][<file>][--write-out][%{http_code}][http://api.example.com/api/users/123]" 0 \
    ep_obs curl_args "200/0/-"
  expect "T607 タイムアウト設定の値が引数に入る" \
    "[--noproxy][][--proxy][http://proxy.test:3128][--silent][--show-error][--connect-timeout][3][--max-time][7][--dump-header][<file>][--output][<file>][--write-out][%{http_code}][http://api.example.com/api/users/123]" 0 \
    ep_obs curl_args "200/0/-" CONNECT_TIMEOUT_SECONDS=3 RESPONSE_TIMEOUT_SECONDS=7
  expect "T607 タイムアウトの標準エラーはtimeoutだけ" \
    "CLIENT_ERROR=timeout
CLIENT_DIAG result=timeout attempts=1 curl_exit=28" 0 ep_obs stderr "000/28/-"
  expect "T607 タイムアウトの標準出力は空" "" 0 ep_obs stdout "000/28/-"
  expect "T607 タイムアウトの終了コードは28" 28 0 ep_obs rc "000/28/-"
  expect "T607 タイムアウトはリトライしない（sleep0回）" "count=0 waits=" 0 \
    ep_obs sleeps "000/28/- 200/0/-"
  expect "T607 タイムアウトの試行は1回" 1 0 ep_obs curl_calls "000/28/- 200/0/-"
  expect "T607 接続拒否はcurl_exit_7" \
    "CLIENT_ERROR=curl_exit_7
CLIENT_DIAG curl_failed attempts=1 curl_exit=7" 0 ep_obs stderr "000/7/-"
  expect "T607 接続拒否の終了コードは7" 7 0 ep_obs rc "000/7/-"
  expect "T607 接続拒否はsleep0回" "count=0 waits=" 0 ep_obs sleeps "000/7/- 200/0/-"
}

# T608: 診断ログの形式、最終結果の3値、標準出力の純度、秘密情報の非混入を見る。
unit_entrypoint_diag() {
  expect "T608 200の成功行" "CLIENT_DIAG result=success attempts=1 status=200" 0 \
    ep_obs stderr "200/0/-"
  expect "T608 503から200の再試行行と成功行" \
    "CLIENT_DIAG retry attempt=1 status=503 class=5xx retry=1/3 wait=1
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "503/0/- 200/0/-"
  expect "T608 429でRetry-Afterありの切り詰め行" \
    "CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/3 retry_after=120 wait=30 capped=1
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "429/0/120 200/0/-"
  expect "T608 429でRetry-Afterなしの行" \
    "CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/3 retry_after=none wait=2 capped=0
CLIENT_DIAG result=success attempts=2 status=200" 0 ep_obs stderr "429/0/- 200/0/-"
  expect "T608 上限到達はretry行3つとretries_exhausted" \
    "CLIENT_DIAG retry attempt=1 status=500 class=5xx retry=1/3 wait=1
CLIENT_DIAG retry attempt=2 status=500 class=5xx retry=2/3 wait=2
CLIENT_DIAG retry attempt=3 status=500 class=5xx retry=3/3 wait=4
CLIENT_DIAG result=retries_exhausted attempts=4 status=500" 0 \
    ep_obs stderr "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T608 回数0の上限到達は最終行だけ" \
    "CLIENT_DIAG result=retries_exhausted attempts=1 status=500" 0 \
    ep_obs stderr "500/0/-" RETRY_MAX_ATTEMPTS_5XX=0
  expect "T608 対象外404はresult=success" "CLIENT_DIAG result=success attempts=1 status=404" 0 \
    ep_obs stderr "404/0/-"
  expect "T608 503の再試行でも標準出力は2行のみ" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "503/0/- 200/0/-"
  expect "T608 上限到達でも標準出力にCLIENT_DIAGを混ぜない" \
    "CLIENT_STATUS=500
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T608 429の再試行でも標準出力にCLIENT_DIAGを混ぜない" \
    "CLIENT_STATUS=200
CLIENT_BODY=BODYTEXT" 0 ep_obs stdout "429/0/120 200/0/-"
  expect "T608 タイムアウトの標準出力は空" "" 0 ep_obs stdout "000/28/-"
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（再試行あり）" "clean" 0 \
    ep_obs leak "429/0/120 200/0/-"
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（上限到達）" "clean" 0 \
    ep_obs leak "500/0/- 500/0/- 500/0/- 500/0/-"
  expect "T608 診断ログに本文・URL・非Retry-Afterヘッダーがない（タイムアウト）" "clean" 0 \
    ep_obs leak "000/28/-"
  expect "T608 retry-lib.shとentrypoint.shにwiremockがない" "absent" 0 \
    ep_text_check wiremock test-client/retry-lib.sh test-client/entrypoint.sh
  expect "T608 retry-lib.shとentrypoint.shに:8080がない" "absent" 0 \
    ep_text_check ':8080' test-client/retry-lib.sh test-client/entrypoint.sh
}

run_unit() {
  if [ -f "$LIB" ]; then
    . "$LIB"
  else
    printf 'FAIL: retry-lib.sh が見つからない (%s)\n' "$LIB" >&2
    failures=$((failures + 1))
  fi

  unit_retryable_status
  unit_backoff_5xx
  unit_wait_429
  unit_parse_retry_after
  unit_config
  unit_entrypoint_prep
  unit_entrypoint_retry
  unit_entrypoint_timeout
  unit_entrypoint_diag

  if [ "$failures" -ne 0 ]; then
    printf 'M06 unit: %s件失敗 / %s件中\n' "$failures" "$total" >&2
    return 1
  fi
  printf 'M06 unit: %s件すべて通過\n' "$total"
}

# ---- smoke（Compose を使う。T611） ----
# unit と違い、ここでは実際の squid、WireMock、test-client を起動する。
# WireMock の件数は前後の差で見る。readiness 確認の通信や他の検査の通信を数えないため。
wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
proxy_url="${PROXY_URL:-http://127.0.0.1:3128}"
smoke_dir=

# 判定が外れたら検査名を出して止める。どの検査が落ちたかを一目で分かるようにする。
smoke_must() { # 検査名 判定コマンド...
  _name=$1
  shift
  if "$@"; then
    return 0
  fi
  printf 'FAIL: %s\n' "$_name" >&2
  exit 1
}

# WireMock の管理 API で、パス一致の呼び出し件数だけを読む。ジャーナルのリセットはしない。
# 件数が取れなければ非ゼロで返し、呼び出し側の set -e で止める。
wiremock_count() { # URLパス
  _body=$(printf '{"method":"GET","url":"%s"}' "$1")
  _res=$(curl --fail --silent --show-error -H 'Content-Type: application/json' \
    -d "$_body" "$wiremock_url/__admin/requests/count")
  _n=$(printf '%s' "$_res" | sed -n 's/.*"count" *: *\([0-9][0-9]*\).*/\1/p')
  [ -n "$_n" ] || return 1
  printf '%s' "$_n"
}

# test-client を1回だけ実行する。標準出力と標準エラーは別々に残し、終了コードは client_rc へ入れる。
# docker-compose run の終了コードは test-client の終了コードを返すので、タイムアウトの 28 もそのまま取れる。
smoke_client() { # docker-compose run に渡す -e 指定
  client_rc=0
  docker-compose run --rm --no-deps "$@" test-client \
    >"$smoke_dir/out" 2>"$smoke_dir/err" || client_rc=$?
}

# test-client のイメージは起動の前に1回だけビルドし、各 run ではビルドしない。
# 毎回ビルドすると検査が遅くなり、ビルド結果の差で検査が揺れるのを避けるため。
run_smoke() {
  smoke_dir=$(mktemp -d)
  cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
      docker-compose logs --no-color squid wiremock >&2 || true
      docker-compose exec -T squid sh -c 'cat /var/log/squid/access.log' >&2 || true
    fi
    docker-compose down --remove-orphans >/dev/null 2>&1 || true
    rm -f "$smoke_dir"/*
    rmdir "$smoke_dir"
    exit "$rc"
  }
  trap cleanup EXIT

  # 前回の残りが別の結果を混ぜないように、開始前にも落としておく。
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  docker-compose up -d --build squid wiremock
  docker-compose build test-client

  attempt=0
  until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || exit 1
    sleep 1
  done

  # squid 経由で WireMock に届くまで待つ。M05 と同じ確認で、直接の疎通は見ない。
  # squid 経由で WireMock に届くまで待つ。502 を成功扱いにしないため --fail を付け、
  # 期待する本文が返るまで待つ。--fail がないと、WireMock 起動前の 502 で待ちが早く終わる。
  attempt=0
  until proxy_body=$(curl --fail --noproxy '' --proxy "$proxy_url" --silent --show-error \
    'http://api.example.com/api/users/123') && printf '%s' "$proxy_body" | grep -Fq '"id": 123'; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || exit 1
    sleep 1
  done

  # retry-lib.sh が test-client イメージに入っていることを確かめる。COPY 漏れはここで見つかる。
  docker-compose run --rm --no-deps --entrypoint test test-client -f /usr/local/bin/retry-lib.sh
  printf '%s\n' 'retry-lib.sh: イメージ内に存在'

  # 成功応答では再試行も待機もしない。WireMock の件数が1増えるだけであることを見る。
  before=$(wiremock_count /api/users/123)
  smoke_client -e TEST_API_PATH=/api/users/123
  after=$(wiremock_count /api/users/123)
  smoke_must "200: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "200: CLIENT_STATUS=200" grep -qx 'CLIENT_STATUS=200' "$smoke_dir/out"
  smoke_must "200: 1回で成功（result=success attempts=1）" \
    grep -Fq 'CLIENT_DIAG result=success attempts=1 status=200' "$smoke_dir/err"
  smoke_must "200: WireMockの件数は1増える" [ $((after - before)) -eq 1 ]

  # 500 は設定回数（1回）だけ再試行し、上限で最後のステータスを返す。終了コードは0のまま。
  # 基準秒0にして待機を省く。待機の計算そのものは unit で検査済み。
  before=$(wiremock_count /api/error-500)
  smoke_client -e RETRY_MAX_ATTEMPTS_5XX=1 -e RETRY_BACKOFF_BASE_SECONDS=0 \
    -e TEST_API_PATH=/api/error-500
  after=$(wiremock_count /api/error-500)
  smoke_must "500: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "500: CLIENT_STATUS=500" grep -qx 'CLIENT_STATUS=500' "$smoke_dir/out"
  smoke_must "500: retries_exhausted で2試行" \
    grep -Fq 'CLIENT_DIAG result=retries_exhausted attempts=2 status=500' "$smoke_dir/err"
  smoke_must "500: WireMockの件数は2増える（初回+再試行1回）" [ $((after - before)) -eq 2 ]

  # 503 も 500 と同じ扱い。5xx のカウンターを使うので、回数の数え方も同じになる。
  before=$(wiremock_count /api/error-503)
  smoke_client -e RETRY_MAX_ATTEMPTS_5XX=1 -e RETRY_BACKOFF_BASE_SECONDS=0 \
    -e TEST_API_PATH=/api/error-503
  after=$(wiremock_count /api/error-503)
  smoke_must "503: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "503: CLIENT_STATUS=503" grep -qx 'CLIENT_STATUS=503' "$smoke_dir/out"
  smoke_must "503: retries_exhausted で2試行" \
    grep -Fq 'CLIENT_DIAG result=retries_exhausted attempts=2 status=503' "$smoke_dir/err"
  smoke_must "503: WireMockの件数は2増える" [ $((after - before)) -eq 2 ]

  # 429 は Retry-After: 2 を返すマッピングを使う。待機は2秒で、診断ログの wait に出る。
  # 429 専用の回数 1 なので、初回と再試行の2試行になる。
  before=$(wiremock_count /api/ratelimit)
  smoke_client -e RETRY_MAX_ATTEMPTS_429=1 -e TEST_API_PATH=/api/ratelimit
  after=$(wiremock_count /api/ratelimit)
  smoke_must "429: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "429: CLIENT_STATUS=429" grep -qx 'CLIENT_STATUS=429' "$smoke_dir/out"
  smoke_must "429: Retry-After=2 が待機2秒に使われる" \
    grep -Fq 'CLIENT_DIAG retry attempt=1 status=429 class=429 retry=1/1 retry_after=2 wait=2 capped=0' "$smoke_dir/err"
  smoke_must "429: retries_exhausted で2試行" \
    grep -Fq 'CLIENT_DIAG result=retries_exhausted attempts=2 status=429' "$smoke_dir/err"
  smoke_must "429: WireMockの件数は2増える" [ $((after - before)) -eq 2 ]

  # 遅延5秒の応答に対して、応答タイムアウト1秒で打ち切る。
  # 標準出力は空、終了コードは28、標準エラーは timeout の識別子になる（FR-606）。
  smoke_client -e RESPONSE_TIMEOUT_SECONDS=1 -e TEST_API_PATH=/api/slow-5000
  smoke_must "timeout: 終了コードは28" [ "$client_rc" -eq 28 ]
  smoke_must "timeout: 標準出力は空" [ ! -s "$smoke_dir/out" ]
  smoke_must "timeout: CLIENT_ERROR=timeout" grep -qx 'CLIENT_ERROR=timeout' "$smoke_dir/err"

  # 実際の CR 付きヘッダーと7桁の値を、コンテナ内の busybox awk で解析する。
  # 解析結果は標準出力に出るので、期待値と完全一致で比べる。
  ra_script='. /usr/local/bin/retry-lib.sh
printf "Retry-After: 7\r\n" | parse_retry_after
printf "Retry-After: 1234567\r\n" | parse_retry_after'
  ra_out=$(docker-compose run --rm --no-deps --entrypoint sh test-client -c "$ra_script")
  smoke_must "Retry-After: CR付き7と7桁の上限飽和がコンテナ内で一致" \
    [ "$ra_out" = "$(printf '7\n1000000')" ]

  # 最後に止めて、このプロジェクトのコンテナが1つも残らないことを確かめる。
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  residue=$(docker-compose ps -a -q)
  if [ -n "$residue" ]; then
    printf 'FAIL: 終了後にコンテナが残っている\n%s\n' "$residue" >&2
    exit 1
  fi

  printf '%s\n' 'M06 smoke: Composeを使う通し検査すべて通過'
}

case "$MODE" in
  unit)
    run_unit
    ;;
  smoke)
    # unit が落ちたら Compose を起動しない。どの層が壊れたかを分けるため。
    run_unit
    run_smoke
    ;;
  *)
    printf 'usage: sh tests/m06-client-resilience.sh [unit|smoke]\n' >&2
    exit 2
    ;;
esac
