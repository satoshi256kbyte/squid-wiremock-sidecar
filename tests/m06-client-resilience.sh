#!/bin/sh
# M06 の検査入口。
# unit の検査は tests/bats/m06-client-resilience.bats にある（Docker を使わない）。
# smoke は unit（bats）に続けて、新基盤（taskdef）で squid、WireMock、Client を起動して通しで確かめる。
# 外部の API には出ない。通信は新基盤の閉じたネットワーク内で行う。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-smoke}
BATS_FILE=$ROOT/tests/bats/m06-client-resilience.bats

case "$MODE" in
  unit | smoke) ;;
  *)
    printf 'usage: sh tests/m06-client-resilience.sh [unit|smoke]\n' >&2
    exit 2
    ;;
esac

if [ "$MODE" = unit ]; then
  exec sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" unit
fi

# smoke: unit が落ちたら起動しない。どの層が壊れたかを分けるため。
sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" unit || exit 1

# 新基盤の共通部品（ロック、起動、Client 実行、停止）。読み込みに副作用はない。
# Why: smoke が swsc_lock_enter、swsc_start_main などを使うため。
# shellcheck disable=SC2034 # 直後で読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

# ---- smoke（新基盤で通しに確かめる。T611） ----
# 起動、収集、停止は共通の入口（swsc_start_main、swsc_collect、swsc_stop）に任せる。
# WireMock の件数は前後の差で見る。swsc_wiremock_count_path で完全一致の経路だけを数えるため。
# Why not docker stop、restart、kill: M06 の実装は Client 実行、ログ収集、停止だけに当たる（plan.md 3.2）。
wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
api_base_url="http://api.example.com"
smoke_dir=
client_rc=0

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

# WireMock の受信数を、経路の完全一致で数える。取得に失敗したら非ゼロで返し、set -e で止める。
wiremock_count() { # 経路
  swsc_wiremock_count_path "$1"
}

# Client を1回だけ実行する。標準出力と標準エラーは別々に残し、終了コードは client_rc へ入れる。
# 環境変数は NAME=VALUE の引数で渡す。Why: 値をシェルの文字列へ連結しないため。
smoke_client() { # NAME=VALUE...
  client_rc=0
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$api_base_url" \
    "$smoke_dir/out" "$smoke_dir/err" "$@" || client_rc=$?
}

run_smoke() {
  # Why: ロックは取ってから一時ディレクトリを作る。取れずに止まったとき、残さないため。
  swsc_lock_enter || exit 1
  smoke_dir=$(mktemp -d) || { swsc_lock_leave; exit 1; }
  cleanup() {
    rc=$?
    # Why: 失敗時だけ収集する。成功時は環境を残さず、終了コードは本体の結果のまま返す。
    if [ "$rc" -ne 0 ]; then swsc_collect || true; fi
    swsc_stop || true
    # Why: 一時ディレクトリの削除に失敗しても、ロックの解放まで進める。
    rm -f "$smoke_dir"/* || true
    rmdir "$smoke_dir" || true
    swsc_lock_leave || { [ "$rc" -ne 0 ] || rc=1; }
    exit "$rc"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  swsc_start_main

  attempt=0
  until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 30 ] || exit 1
    sleep 1
  done

  # Why: Squid の待ち受けは swsc_start_main（runner）が確かめる。ホストからの proxy 確認は行わない。
  # retry-lib.sh が Client のイメージに入っていることを確かめる。COPY 漏れはここで見つかる。
  docker run --rm --entrypoint test "$SWSC_LOCAL_CLIENT_IMAGE" -f /usr/local/bin/retry-lib.sh
  printf '%s\n' 'retry-lib.sh: イメージ内に存在'

  # 成功応答では再試行も待機もしない。WireMock の件数が1増えるだけであることを見る。
  before=$(wiremock_count /api/users/123)
  smoke_client TEST_API_PATH=/api/users/123
  after=$(wiremock_count /api/users/123)
  smoke_must "200: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "200: CLIENT_STATUS=200" grep -qx 'CLIENT_STATUS=200' "$smoke_dir/out"
  smoke_must "200: 1回で成功（result=success attempts=1）" \
    grep -Fq 'CLIENT_DIAG result=success attempts=1 status=200' "$smoke_dir/err"
  smoke_must "200: WireMockの件数は1増える" [ $((after - before)) -eq 1 ]

  # 500 は設定回数（1回）だけ再試行し、上限で最後のステータスを返す。終了コードは0のまま。
  # 基準秒0にして待機を省く。待機の計算そのものは unit で検査済み。
  before=$(wiremock_count /api/error-500)
  smoke_client RETRY_MAX_ATTEMPTS_5XX=1 RETRY_BACKOFF_BASE_SECONDS=0 TEST_API_PATH=/api/error-500
  after=$(wiremock_count /api/error-500)
  smoke_must "500: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "500: CLIENT_STATUS=500" grep -qx 'CLIENT_STATUS=500' "$smoke_dir/out"
  smoke_must "500: retries_exhausted で2試行" \
    grep -Fq 'CLIENT_DIAG result=retries_exhausted attempts=2 status=500' "$smoke_dir/err"
  smoke_must "500: WireMockの件数は2増える（初回+再試行1回）" [ $((after - before)) -eq 2 ]

  # 503 も 500 と同じ扱い。5xx のカウンターを使うので、回数の数え方も同じになる。
  before=$(wiremock_count /api/error-503)
  smoke_client RETRY_MAX_ATTEMPTS_5XX=1 RETRY_BACKOFF_BASE_SECONDS=0 TEST_API_PATH=/api/error-503
  after=$(wiremock_count /api/error-503)
  smoke_must "503: 終了コードは0" [ "$client_rc" -eq 0 ]
  smoke_must "503: CLIENT_STATUS=503" grep -qx 'CLIENT_STATUS=503' "$smoke_dir/out"
  smoke_must "503: retries_exhausted で2試行" \
    grep -Fq 'CLIENT_DIAG result=retries_exhausted attempts=2 status=503' "$smoke_dir/err"
  smoke_must "503: WireMockの件数は2増える" [ $((after - before)) -eq 2 ]

  # 429 は Retry-After: 2 を返すマッピングを使う。待機は2秒で、診断ログの wait に出る。
  # 429 専用の回数 1 なので、初回と再試行の2試行になる。
  before=$(wiremock_count /api/ratelimit)
  smoke_client RETRY_MAX_ATTEMPTS_429=1 TEST_API_PATH=/api/ratelimit
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
  smoke_client RESPONSE_TIMEOUT_SECONDS=1 TEST_API_PATH=/api/slow-5000
  smoke_must "timeout: 終了コードは28" [ "$client_rc" -eq 28 ]
  smoke_must "timeout: 標準出力は空" [ ! -s "$smoke_dir/out" ]
  smoke_must "timeout: CLIENT_ERROR=timeout" grep -qx 'CLIENT_ERROR=timeout' "$smoke_dir/err"

  # 実際の CR 付きヘッダーと7桁の値を、コンテナ内の busybox awk で解析する。
  # 解析結果は標準出力に出るので、期待値と完全一致で比べる。
  ra_script='. /usr/local/bin/retry-lib.sh
printf "Retry-After: 7\r\n" | parse_retry_after
printf "Retry-After: 1234567\r\n" | parse_retry_after'
  ra_out=$(docker run --rm --entrypoint sh "$SWSC_LOCAL_CLIENT_IMAGE" -c "$ra_script")
  smoke_must "Retry-After: CR付き7と7桁の上限飽和がコンテナ内で一致" \
    [ "$ra_out" = "$(printf '7\n1000000')" ]

  # 停止のあと、管理対象（接頭辞とラベルの両方に一致）が1つも残らないことを確かめる。
  swsc_stop || exit 1
  swsc_check_managed_empty || exit 1

  printf '%s\n' 'M06 smoke: 新基盤の通し検査すべて通過'
}

run_smoke
