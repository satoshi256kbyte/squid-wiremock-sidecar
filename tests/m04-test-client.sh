#!/bin/sh
set -eu

wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
tmp_dir=$(mktemp -d)
cleanup() {
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  rm -f "$tmp_dir"/*
  rmdir "$tmp_dir"
}
trap cleanup EXIT

docker-compose down --remove-orphans >/dev/null 2>&1 || true
docker-compose up -d squid wiremock
attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

proxy_url="http://127.0.0.1:3128"
attempt=0
until proxy_body=$(curl --noproxy '' --proxy "$proxy_url" --silent --show-error \
  'http://api.example.com/api/users/123'); do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done
printf '%s' "$proxy_body" | grep -Fq '"id": 123'

output=$(docker-compose run --rm --no-deps --build test-client)
printf '%s\n' "$output"
printf '%s' "$output" | grep -q '^CLIENT_STATUS=200$'
printf '%s' "$output" | grep -q '^CLIENT_BODY='
printf '%s' "$output" | grep -Fq '"id": 123'
printf '%s' "$output" | grep -Fq '"name": "John"'

requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$requests" | grep -q '/api/users/123'

error_output=$(docker-compose run --rm --no-deps --build \
  -e TEST_API_PATH=/api/error-500 test-client)
printf '%s' "$error_output" | grep -q '^CLIENT_STATUS=500$'
printf '%s' "$error_output" | grep -Fq 'Internal Server Error'

set +e
docker-compose run --rm --no-deps --build \
  -e HTTP_PROXY=http://127.0.0.1:1 -e HTTPS_PROXY= -e NO_PROXY= test-client \
  >"$tmp_dir/transport-output" 2>"$tmp_dir/transport-error"
transport_rc=$?
set -e
[ "$transport_rc" -ne 0 ]
grep -q '^CLIENT_ERROR=curl_exit_' "$tmp_dir/transport-error"

set +e
docker-compose run --rm --no-deps \
  -e HTTP_PROXY= -e HTTPS_PROXY= -e NO_PROXY= test-client \
  >"$tmp_dir/no-proxy-output" 2>"$tmp_dir/no-proxy-error"
no_proxy_rc=$?
set -e
[ "$no_proxy_rc" -eq 78 ]
grep -q 'CLIENT_ERROR=proxy_not_configured' "$tmp_dir/no-proxy-error"

if grep -Eiq 'wiremock|:8080' test-client/entrypoint.sh; then
  printf '%s\n' 'Test ClientにWireMock直接接続の指定がある' >&2
  exit 1
fi

printf '%s\n' 'M04 Test Client transport smoke test passed'
