#!/usr/bin/env bats
# M05 閉域ネットワークの統合検査（smoke）。新基盤の pause 共有 namespace で Squid と Client を動かし、
# 許可要求の200、WireMock の受信、許可外の403、Squid の TCP_MISS と TCP_DENIED を確かめる。
# 起動と停止は入口（tests/m05-proxy-integration.sh）が行う。検査は順番に実行される（前の手順の結果を使う）。

load 'helpers/common'

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

# bats test_tags=smoke
@test "m05 smoke: 許可した経路（api.example.com/api/users/123）は 200 と JSON の本文を返す" {
  # Why: Squid はホストへ公開しない。proxy 経由の要求は、同じ namespace で動く Client から送る。
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$SWSC_RUN_ID" 'http://api.example.com' \
    "$TMP/client-output" "$TMP/client-error"
  _output=$(cat "$TMP/client-output")
  printf '%s' "$_output" | grep -q '^CLIENT_STATUS=200$' || return 1
  printf '%s' "$_output" | grep -Fq '"id": 123'
}

# bats test_tags=smoke
@test "m05 smoke: WireMock の受信に /api/users/123 が現れる" {
  _requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
  printf '%s' "$_requests" | grep -q '/api/users/123'
}

# bats test_tags=smoke
@test "m05 smoke: Squid の access log に api.example.com/api/users/123 と TCP_MISS/200 がある" {
  swsc_squid_log_check 'api.example.com/api/users/123' 'TCP_MISS/200'
}

# bats test_tags=smoke
@test "m05 smoke: allowlist 外（example.com）は 403 で拒否される" {
  # Why: 受信記録を先に空にし、許可外の要求だけを数える。経路は /api/ 配下にする（swsc_wiremock_total の数え方に合わせる）。
  swsc_wiremock_reset || return 1
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$SWSC_RUN_ID" 'http://example.com' \
    "$TMP/blocked-out" "$TMP/blocked-err" TEST_API_PATH=/api/users/123
  grep -q '^CLIENT_STATUS=403$' "$TMP/blocked-out"
}

# bats test_tags=smoke
@test "m05 smoke: allowlist 外の要求は WireMock に届かない（/api/ の受信数が 0）" {
  _blocked_count=$(swsc_wiremock_total) || return 1
  [ "$_blocked_count" = 0 ]
}

# bats test_tags=smoke
@test "m05 smoke: Squid の access log に example.com と TCP_DENIED がある" {
  swsc_squid_log_check 'example.com' 'TCP_DENIED'
}
