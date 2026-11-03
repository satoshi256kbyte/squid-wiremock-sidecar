#!/bin/sh
set -eu

wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
proxy_url="${PROXY_URL:-http://127.0.0.1:3128}"
tmp_dir=$(mktemp -d)

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    docker-compose logs --no-color squid wiremock >&2 || true
    docker-compose exec -T squid sh -c 'cat /var/log/squid/access.log' >&2 || true
  fi
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  rm -f "$tmp_dir"/*
  rmdir "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

docker-compose down --remove-orphans >/dev/null 2>&1 || true
docker-compose up -d --build squid wiremock

attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

attempt=0
until proxy_body=$(curl --noproxy '' --proxy "$proxy_url" --silent --show-error \
  'http://api.example.com/api/users/123'); do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done
printf '%s' "$proxy_body" | grep -Fq '"id": 123'

client_output=$(docker-compose run --rm --no-deps --build test-client)
printf '%s\n' "$client_output"
printf '%s' "$client_output" | grep -q '^CLIENT_STATUS=200$'
printf '%s' "$client_output" | grep -Fq '"id": 123'

wiremock_requests=$(curl --fail --silent --show-error "$wiremock_url/__admin/requests")
printf '%s' "$wiremock_requests" | grep -q '/api/users/123'

squid_log=$(docker-compose exec -T squid sh -c 'cat /var/log/squid/access.log')
printf '%s' "$squid_log" | grep -q 'api.example.com/api/users/123'
printf '%s' "$squid_log" | grep -q 'TCP_MISS/200'

if curl --fail --silent --show-error --noproxy '' \
  --max-time 5 --proxy "$proxy_url" 'http://example.com/' >/dev/null 2>&1; then
  printf '%s\n' 'allowlist外の通信が成功した' >&2
  exit 1
fi

squid_log=$(docker-compose exec -T squid sh -c 'cat /var/log/squid/access.log')
printf '%s' "$squid_log" | grep -q 'example.com'
printf '%s' "$squid_log" | grep -q 'TCP_DENIED'

printf '%s\n' 'M05 closed network integration smoke test passed'
