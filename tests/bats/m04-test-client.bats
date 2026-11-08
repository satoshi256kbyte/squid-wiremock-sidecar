#!/usr/bin/env bats
# M04 Test Client の検査（smoke）。新基盤の共通 Client 実行（swsc_client_once_env）で、
# 標準出力、診断出力、200、500、転送失敗、proxy 未設定の終了コードを確かめる。
# 起動と停止は入口（tests/m04-test-client.sh）が行う。実行の起点の PID は SWSC_RUN_ID で渡される。

load 'helpers/common'

api_base_url="http://api.example.com"

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
  # shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する。
  SWSC_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$ROOT/scripts/e2e-lib.sh"
  # shellcheck source=/dev/null
  . "$ROOT/scripts/e2e-runner.sh"
}

# Client を1回実行する。標準出力と標準エラーは別のファイルへ保存する。終了コードは Client のものを返す。
# Why: 環境変数は引数として渡し、シェルの文字列へ連結しない（swsc_client_once_env の作法）。
client_run() { # 標準出力の保存先 標準エラーの保存先 [NAME=VALUE...]
  _out=$1
  _err=$2
  shift 2
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$SWSC_RUN_ID" "$api_base_url" "$_out" "$_err" "$@"
}

# bats test_tags=smoke
@test "m04 smoke: 200 の経路（/api/users/123）は 200 と JSON の本文を返し、WireMock が受ける" {
  client_run "$TMP/output" "$TMP/error"
  _output=$(cat "$TMP/output")
  printf '%s' "$_output" | grep -q '^CLIENT_STATUS=200$' || return 1
  printf '%s' "$_output" | grep -q '^CLIENT_BODY=' || return 1
  printf '%s' "$_output" | grep -Fq '"id": 123' || return 1
  printf '%s' "$_output" | grep -Fq '"name": "John"' || return 1
  _requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
  printf '%s' "$_requests" | grep -q '/api/users/123'
}

# bats test_tags=smoke
@test "m04 smoke: 500 の経路（/api/error-500）は 500 と Internal Server Error を返す" {
  client_run "$TMP/error-output" "$TMP/error-error" RETRY_BACKOFF_BASE_SECONDS=0 TEST_API_PATH=/api/error-500
  _error_output=$(cat "$TMP/error-output")
  printf '%s' "$_error_output" | grep -q '^CLIENT_STATUS=500$' || return 1
  printf '%s' "$_error_output" | grep -Fq 'Internal Server Error'
}

# bats test_tags=smoke
@test "m04 smoke: 転送に失敗すると、終了コードは 0 でなく、curl_exit の診断を出す" {
  run client_run "$TMP/transport-output" "$TMP/transport-error" \
    HTTP_PROXY=http://127.0.0.1:1 HTTPS_PROXY= NO_PROXY=
  [ "$status" -ne 0 ] || return 1
  grep -q '^CLIENT_ERROR=curl_exit_' "$TMP/transport-error"
}

# bats test_tags=smoke
@test "m04 smoke: proxy が未設定なら、終了コード 78 と proxy_not_configured を返す" {
  run client_run "$TMP/no-proxy-output" "$TMP/no-proxy-error" \
    HTTP_PROXY= HTTPS_PROXY= NO_PROXY=
  [ "$status" -eq 78 ] || return 1
  grep -q 'CLIENT_ERROR=proxy_not_configured' "$TMP/no-proxy-error"
}

# bats test_tags=smoke
@test "m04 smoke: Test Client の入口に、WireMock への直接接続の指定が無い" {
  if grep -Eiq 'wiremock|:8080' test-client/entrypoint.sh; then
    return 1
  fi
}
