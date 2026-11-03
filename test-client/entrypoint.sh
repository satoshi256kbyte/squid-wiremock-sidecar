#!/bin/sh
set -eu

proxy_url="${HTTP_PROXY:-}"
if [ -z "$proxy_url" ]; then
  printf '%s\n' 'CLIENT_ERROR=proxy_not_configured' >&2
  exit 78
fi

api_base_url="${TEST_API_BASE_URL:-http://api.example.com}"
api_path="${TEST_API_PATH:-/api/users/123}"
api_url="${api_base_url%/}/${api_path#/}"
tmp_dir=$(mktemp -d)
trap 'rm -f "$tmp_dir/body"; rmdir "$tmp_dir"' EXIT

set +e
status=$(curl --noproxy '' --proxy "$proxy_url" --silent --show-error \
  --output "$tmp_dir/body" --write-out '%{http_code}' "$api_url")
curl_rc=$?
set -e

if [ "$curl_rc" -ne 0 ]; then
  printf 'CLIENT_ERROR=curl_exit_%s\n' "$curl_rc" >&2
  exit "$curl_rc"
fi

body=$(tr '\n' ' ' < "$tmp_dir/body")
printf 'CLIENT_STATUS=%s\n' "$status"
printf 'CLIENT_BODY=%s\n' "$body"
