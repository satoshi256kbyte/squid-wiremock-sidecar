#!/usr/bin/env bats
# M02 Squid 経路の検査（smoke）。新基盤（ECSタスク定義方式、pause 共有 namespace）の上で、
# proxy 経由の要求、WireMock の登録、Squid の access log、allowlist 外の拒否を確かめる。
# 起動と停止は入口（tests/m02-routing-smoke.sh）が行う。検査は順番に実行される（前の検査の結果を使う）。

load 'helpers/common'

# WireMock に登録する mapping。Client が /m02-routing を取ると、この本文が返る。
mapping='{"request":{"method":"GET","urlPath":"/m02-routing"},"response":{"status":200,"body":"m02-routing-ok","headers":{"Content-Type":"text/plain"}}}'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
  # 新基盤の共通部品（Client の実行、Squid の log の検査）を読む。読み込みに副作用はない。
  # shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する。
  SWSC_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$ROOT/scripts/e2e-lib.sh"
  # shellcheck source=/dev/null
  . "$ROOT/scripts/e2e-runner.sh"
}

# bats test_tags=smoke
@test "m02 smoke: WireMock に /m02-routing の mapping を登録する" {
  curl --fail --silent --show-error \
    -X POST "$wiremock_url/__admin/mappings" \
    -H 'Content-Type: application/json' \
    --data "$mapping" >/dev/null
}

# bats test_tags=smoke
@test "m02 smoke: proxy 経由の要求は 200 と本文 m02-routing-ok を返す" {
  # Why: 新基盤の Squid はホストへ公開しない（3128 は pause の namespace の中だけ）。
  # proxy 経由の要求は、同じ namespace で動く Client から送る。
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$SWSC_RUN_ID" 'http://api.example.com' \
    "$TMP/out" "$TMP/err" TEST_API_PATH=/m02-routing
  grep -q '^CLIENT_STATUS=200$' "$TMP/out" || return 1
  grep -q '^CLIENT_BODY=m02-routing-ok *$' "$TMP/out"
}

# bats test_tags=smoke
@test "m02 smoke: WireMock の受信に m02-routing が現れる" {
  _requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
  printf '%s' "$_requests" | grep -q 'm02-routing'
}

# bats test_tags=smoke
@test "m02 smoke: Squid の access log に m02-routing の行がある" {
  swsc_squid_log_check 'm02-routing'
}

# bats test_tags=smoke
@test "m02 smoke: allowlist 外（example.com）は 403 で拒否される" {
  # Why: allowlist 外の要求も Client から送る。Squid が 403 で拒否すれば、通信は成功していない。
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$SWSC_RUN_ID" 'http://example.com' \
    "$TMP/blocked-out" "$TMP/blocked-err" TEST_API_PATH=/
  grep -q '^CLIENT_STATUS=403$' "$TMP/blocked-out"
}
