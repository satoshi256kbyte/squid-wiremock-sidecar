#!/bin/sh
set -eu

wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
proxy_url="${PROXY_URL:-http://127.0.0.1:3128}"

mapping='{"request":{"method":"GET","urlPath":"/m02-routing"},"response":{"status":200,"body":"m02-routing-ok","headers":{"Content-Type":"text/plain"}}}'

curl --fail --silent --show-error \
  -X POST "$wiremock_url/__admin/mappings" \
  -H 'Content-Type: application/json' \
  --data "$mapping" >/dev/null

body=$(curl --fail --silent --show-error --noproxy '' \
  --proxy "$proxy_url" \
  'http://api.example.com/m02-routing')

if [ "$body" != 'm02-routing-ok' ]; then
  printf 'unexpected response body: %s\n' "$body" >&2
  exit 1
fi

requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$requests" | grep -q 'm02-routing'

docker-compose exec -T squid sh -c 'cat /var/log/squid/access.log' | grep -q 'm02-routing'

if curl --fail --silent --show-error --noproxy '' \
  --max-time 5 --proxy "$proxy_url" 'http://example.com/' >/dev/null 2>&1; then
  printf '%s\n' 'allowlist外の通信が成功した' >&2
  exit 1
fi

printf '%s\n' 'M02 Squid routing smoke test passed'
