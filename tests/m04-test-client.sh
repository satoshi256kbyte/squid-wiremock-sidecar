#!/bin/sh
# M04 Test Client の検査。新基盤の共通 Client 実行（swsc_client_once_env）で、
# 標準出力、診断出力、200、500、転送失敗、proxy 未設定の終了コードを確かめる。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する（出力先の既定値）
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"
cd "$ROOT"

wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
api_base_url="http://api.example.com"

# Why: 固定ポートのロックは入口と同じ規約で1回だけ取る。取れなければ、他の実行の swsc- に触れずに止まる。
swsc_lock_enter || exit 1
# Why: 一時ディレクトリはロックの後に作る。ロックが取れずに止まったとき、残さないため。
tmp_dir=$(mktemp -d) || { swsc_lock_leave; exit 1; }
cleanup() {
  rc=$?
  # Why: 失敗時だけ収集する。成功時は環境を残さず、終了コードは本体の結果のまま返す。
  if [ "$rc" -ne 0 ]; then swsc_collect || true; fi
  swsc_stop || true
  # Why: 一時ディレクトリの削除に失敗しても、ロックの解放まで進める。
  rm -f "$tmp_dir"/* || true
  rmdir "$tmp_dir" || true
  swsc_lock_leave || { [ "$rc" -ne 0 ] || rc=1; }
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Client を1回実行する。標準出力と標準エラーは別のファイルへ保存する。終了コードは Client のものを返す。
# Why: 環境変数は引数として渡し、シェルの文字列へ連結しない（swsc_client_once_env の作法）。
client_run() { # 標準出力の保存先 標準エラーの保存先 [NAME=VALUE...]
  _out=$1
  _err=$2
  shift 2
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$api_base_url" "$_out" "$_err" "$@"
}

swsc_start_main

attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

# Why: Squid の起動と 3128 の待ち受けは swsc_start_main（runner）が pause の中で確かめる。
# ホストからの proxy 確認は行わない（新基盤の Squid はホストへ公開しない）。

client_run "$tmp_dir/output" "$tmp_dir/error"
cat "$tmp_dir/error" >&2
output=$(cat "$tmp_dir/output")
printf '%s\n' "$output"
printf '%s' "$output" | grep -q '^CLIENT_STATUS=200$'
printf '%s' "$output" | grep -q '^CLIENT_BODY='
printf '%s' "$output" | grep -Fq '"id": 123'
printf '%s' "$output" | grep -Fq '"name": "John"'

requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$requests" | grep -q '/api/users/123'

client_run "$tmp_dir/error-output" "$tmp_dir/error-error" \
  RETRY_BACKOFF_BASE_SECONDS=0 TEST_API_PATH=/api/error-500
cat "$tmp_dir/error-error" >&2
error_output=$(cat "$tmp_dir/error-output")
printf '%s' "$error_output" | grep -q '^CLIENT_STATUS=500$'
printf '%s' "$error_output" | grep -Fq 'Internal Server Error'

set +e
client_run "$tmp_dir/transport-output" "$tmp_dir/transport-error" \
  HTTP_PROXY=http://127.0.0.1:1 HTTPS_PROXY= NO_PROXY=
transport_rc=$?
set -e
[ "$transport_rc" -ne 0 ]
grep -q '^CLIENT_ERROR=curl_exit_' "$tmp_dir/transport-error"

set +e
client_run "$tmp_dir/no-proxy-output" "$tmp_dir/no-proxy-error" \
  HTTP_PROXY= HTTPS_PROXY= NO_PROXY=
no_proxy_rc=$?
set -e
[ "$no_proxy_rc" -eq 78 ]
grep -q 'CLIENT_ERROR=proxy_not_configured' "$tmp_dir/no-proxy-error"

if grep -Eiq 'wiremock|:8080' test-client/entrypoint.sh; then
  printf '%s\n' 'Test ClientにWireMock直接接続の指定がある' >&2
  exit 1
fi

printf '%s\n' 'M04 Test Client transport smoke test passed'
