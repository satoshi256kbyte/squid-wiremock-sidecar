#!/bin/sh
# M02 Squid 経路の検査。新基盤（ECSタスク定義方式、pause 共有 namespace）で起動し、
# proxy 経由の要求、WireMock の登録、Squid の access log、allowlist 外の拒否を確かめる。
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

swsc_start_main

mapping='{"request":{"method":"GET","urlPath":"/m02-routing"},"response":{"status":200,"body":"m02-routing-ok","headers":{"Content-Type":"text/plain"}}}'

curl --fail --silent --show-error \
  -X POST "$wiremock_url/__admin/mappings" \
  -H 'Content-Type: application/json' \
  --data "$mapping" >/dev/null

# Why: 新基盤の Squid はホストへ公開しない（3128 は pause の namespace の中だけ）。
# proxy 経由の要求は、同じ namespace で動く Client から送る。
swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" 'http://api.example.com' \
  "$tmp_dir/out" "$tmp_dir/err" TEST_API_PATH=/m02-routing
if ! grep -q '^CLIENT_STATUS=200$' "$tmp_dir/out" || ! grep -q '^CLIENT_BODY=m02-routing-ok *$' "$tmp_dir/out"; then
  printf 'unexpected response body: %s\n' "$(sed -n 's/^CLIENT_BODY=//p' "$tmp_dir/out")" >&2
  exit 1
fi

requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$requests" | grep -q 'm02-routing'

swsc_squid_log_check 'm02-routing'

# Why: allowlist 外の要求も Client から送る。Squid が 403 で拒否すれば、通信は成功していない。
swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" 'http://example.com' \
  "$tmp_dir/blocked-out" "$tmp_dir/blocked-err" TEST_API_PATH=/
if ! grep -q '^CLIENT_STATUS=403$' "$tmp_dir/blocked-out"; then
  printf '%s\n' 'allowlist外の通信が成功した' >&2
  exit 1
fi

printf '%s\n' 'M02 Squid routing smoke test passed'
