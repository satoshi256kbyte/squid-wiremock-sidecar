#!/bin/sh
# M05 閉域ネットワークの統合検査。新基盤の pause 共有 namespace で Squid と Client を動かし、
# 許可要求の200、WireMock の受信、許可外の403、Squid の TCP_DENIED を確かめる。
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
  # Why: 失敗時だけ収集する（Squid と WireMock のログを含む）。成功時は環境を残さず、終了コードは本体の結果のまま返す。
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

attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

# Why: Squid の起動と 3128 の待ち受けは swsc_start_main（runner）が pause の中で確かめる。
# ホストからの proxy 確認は行わない（新基盤の Squid はホストへ公開しない）。

# Client を1回実行する。標準出力と標準エラーは別のファイルへ保存し、終了コードは Client のものを返す。
client_out="$tmp_dir/client-output"
client_err="$tmp_dir/client-error"
swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" 'http://api.example.com' "$client_out" "$client_err"
cat "$client_err" >&2
client_output=$(cat "$client_out")
printf '%s\n' "$client_output"
printf '%s' "$client_output" | grep -q '^CLIENT_STATUS=200$'
printf '%s' "$client_output" | grep -Fq '"id": 123'

wiremock_requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$wiremock_requests" | grep -q '/api/users/123'

swsc_squid_log_check 'api.example.com/api/users/123' 'TCP_MISS/200'

# Why: allowlist 外の要求は Client から送る。受信記録を先に空にし、許可外の要求だけを数える。
# 経路は /api/ 配下にする。swsc_wiremock_total が /api/ で始まる要求だけを数えるため。
swsc_wiremock_reset || exit 1
swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" 'http://example.com' \
  "$tmp_dir/blocked-out" "$tmp_dir/blocked-err" TEST_API_PATH=/api/users/123
if ! grep -q '^CLIENT_STATUS=403$' "$tmp_dir/blocked-out"; then
  printf '%s\n' 'allowlist外の通信が成功した' >&2
  exit 1
fi

# Why: 許可外の要求は WireMock に届かないことを、受信記録の件数で確かめる（期待値の追加。既存の検査は変えない）。
blocked_count=$(swsc_wiremock_total) || exit 1
if [ "$blocked_count" != 0 ]; then
  printf 'allowlist外の要求が WireMock に届いた（受信数=%s）\n' "$blocked_count" >&2
  exit 1
fi

swsc_squid_log_check 'example.com' 'TCP_DENIED'

printf '%s\n' 'M05 closed network integration smoke test passed'
