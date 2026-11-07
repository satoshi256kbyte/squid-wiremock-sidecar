#!/bin/sh
# M03 WireMock シナリオの検査。新基盤で WireMock を起動し、mapping の静的検査、
# 管理APIの応答、本文、ステータス、遅延を確かめる。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する（出力先の既定値）
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/scenario-lib.sh"
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

attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

validate_json() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    json.load(stream)
PY
}

validate_mapping() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    mapping = json.load(stream)

request = mapping.get("request", {})
response = mapping.get("response", {})
required_request = {"method", "urlPath"}
missing_request = required_request - request.keys()
if missing_request or "status" not in response:
    missing = sorted(missing_request | ({"response.status"} if "status" not in response else set()))
    raise SystemExit("missing mapping fields: " + ", ".join(missing))
PY
}

for file in wiremock-scenarios/mappings/*.json wiremock-scenarios/__files/*.json; do
  validate_json "$file"
done

for file in wiremock-scenarios/mappings/*.json; do
  validate_mapping "$file"
done

# Why: 既存の scenario-lib の静的検査（状態グループと宛先）を、項目の検査に加えて使う。既存の検査は残す。
scenario_check_static wiremock-scenarios/mappings

printf '%s' '{' > "$tmp_dir/invalid.json"
if validate_json "$tmp_dir/invalid.json" >/dev/null 2>&1; then
  printf '%s\n' 'invalid JSON was accepted' >&2
  exit 1
fi
printf '%s' '{"request": {}}' > "$tmp_dir/incomplete-mapping.json"
if validate_mapping "$tmp_dir/incomplete-mapping.json" >/dev/null 2>&1; then
  printf '%s\n' 'incomplete mapping was accepted' >&2
  exit 1
fi

mappings=$(curl --fail --silent --show-error "$wiremock_url/__admin/mappings")
for path in '/api/users/123' '/api/error-500' '/api/error-503' '/api/ratelimit' '/api/slow-100' '/api/slow-5000'; do
  printf '%s' "$mappings" | grep -q "$path"
done

check_body() {
  path="$1"
  expected_status="$2"
  expected_text="$3"
  body_file="$tmp_dir/body"
  headers_file="$tmp_dir/headers"
  status=$(curl --silent --show-error -D "$headers_file" -o "$body_file" \
    -w '%{http_code}' "$wiremock_url$path")
  [ "$status" = "$expected_status" ]
  grep -Eiq '^Content-Type:[[:space:]]*application/json' "$headers_file"
  grep -Fq "$expected_text" "$body_file"
}

check_body '/api/users/123' 200 '"id": 123'
check_body '/api/error-500' 500 'Internal Server Error'
check_body '/api/error-503' 503 'Service Unavailable'
check_body '/api/ratelimit' 429 'Rate Limited'
grep -Eiq '^Retry-After:[[:space:]]*2' "$tmp_dir/headers"

check_delay() {
  path="$1"
  minimum_seconds="$2"
  body_text="$3"
  headers_file="$tmp_dir/delay-headers"
  body_file="$tmp_dir/delay-body"
  elapsed=$(curl --fail --silent --show-error -D "$headers_file" -o "$body_file" \
    -w '%{time_total}' "$wiremock_url$path")
  awk -v elapsed="$elapsed" -v minimum="$minimum_seconds" \
    'BEGIN { exit !(elapsed >= minimum) }'
  grep -Eiq '^Content-Type:[[:space:]]*application/json' "$headers_file"
  grep -Fq "$body_text" "$body_file"
}

check_delay '/api/slow-100' 0.08 'slow-response'
check_delay '/api/slow-5000' 4.5 'slow-response'

printf '%s\n' 'M03 WireMock scenarios smoke test passed'
