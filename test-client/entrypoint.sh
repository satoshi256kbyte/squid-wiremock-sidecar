#!/bin/sh
set -eu

# プロキシ未設定を最初に検査する。設定不備と同時に起きても proxy_not_configured を
# 優先させたいため、設定値の検査より前に置く（FR-607）。
proxy_url="${HTTP_PROXY:-}"
if [ -z "$proxy_url" ]; then
  printf '%s\n' 'CLIENT_ERROR=proxy_not_configured' >&2
  exit 78
fi

# 読み込み先は entrypoint.sh と同じディレクトリに限る。/usr/local/bin の外から
# 別の retry-lib.sh を拾うと、検査した版と実行する版が食い違うため。
. "$(dirname "$0")/retry-lib.sh"

apply_config_defaults
# 値は診断ログに出さない。どの変数が不正かだけを残す（FR-607）。
if ! invalid_name=$(validate_config); then
  printf '%s\n' 'CLIENT_ERROR=invalid_config' >&2
  printf 'CLIENT_DIAG invalid_config name=%s\n' "$invalid_name" >&2
  exit 78
fi

api_base_url="${TEST_API_BASE_URL:-http://api.example.com}"
api_path="${TEST_API_PATH:-/api/users/123}"
api_url="${api_base_url%/}/${api_path#/}"
tmp_dir=$(mktemp -d)
trap 'rm -f "$tmp_dir/body" "$tmp_dir/headers"; rmdir "$tmp_dir"' EXIT

# 最後に受け取った応答を出して終了コード0で終わる。
# 上限到達の応答も HTTP 応答なので 0 にする。呼び出し側は診断ログの result で判別する。
finish() { # 最終結果（success、retries_exhausted のいずれか）
  body=$(tr '\n' ' ' < "$tmp_dir/body")
  printf 'CLIENT_STATUS=%s\n' "$status"
  printf 'CLIENT_BODY=%s\n' "$body"
  printf 'CLIENT_DIAG result=%s attempts=%s status=%s\n' "$1" "$attempt" "$status" >&2
  exit 0
}

attempt=0
retries_5xx=0
retries_429=0
while :; do
  attempt=$((attempt + 1))
  # --dump-header は試行ごとに上書きする。前の試行の Retry-After を次の待機に使わないため。
  set +e
  status=$(curl --noproxy '' --proxy "$proxy_url" --silent --show-error \
    --connect-timeout "$CONNECT_TIMEOUT_SECONDS" --max-time "$RESPONSE_TIMEOUT_SECONDS" \
    --dump-header "$tmp_dir/headers" --output "$tmp_dir/body" --write-out '%{http_code}' \
    --url "$api_url")
  curl_rc=$?
  set -e

  # タイムアウトは再試行しない。接続先が遅いのか応答が遅いのかは区別しない（FR-606）。
  if [ "$curl_rc" -eq 28 ]; then
    printf '%s\n' 'CLIENT_ERROR=timeout' >&2
    printf 'CLIENT_DIAG result=timeout attempts=%s curl_exit=28\n' "$attempt" >&2
    exit 28
  fi
  if [ "$curl_rc" -ne 0 ]; then
    printf 'CLIENT_ERROR=curl_exit_%s\n' "$curl_rc" >&2
    printf 'CLIENT_DIAG curl_failed attempts=%s curl_exit=%s\n' "$attempt" "$curl_rc" >&2
    exit "$curl_rc"
  fi

  # 対象外のステータス（2xx、301、404 など）は、これ以上の再試行が要らない結果として返す。
  if ! class=$(is_retryable_status "$status"); then
    finish success
  fi

  # 5xx と 429 は独立したカウンターで数える。片方の失敗回数がもう片方の上限を使い切らないため。
  if [ "$class" = 5xx ]; then
    if [ "$retries_5xx" -ge "$RETRY_MAX_ATTEMPTS_5XX" ]; then
      finish retries_exhausted
    fi
    retries_5xx=$((retries_5xx + 1))
    delay=$(backoff_wait_5xx "$retries_5xx" "$RETRY_BACKOFF_BASE_SECONDS" "$RETRY_MAX_WAIT_SECONDS")
    printf 'CLIENT_DIAG retry attempt=%s status=%s class=5xx retry=%s/%s wait=%s\n' \
      "$attempt" "$status" "$retries_5xx" "$RETRY_MAX_ATTEMPTS_5XX" "$delay" >&2
    sleep "$delay"
    continue
  fi

  if [ "$retries_429" -ge "$RETRY_MAX_ATTEMPTS_429" ]; then
    finish retries_exhausted
  fi
  retries_429=$((retries_429 + 1))
  # Retry-After がない、または解析できない場合は空になり、既定待機を使う。
  retry_after=$(parse_retry_after < "$tmp_dir/headers") || retry_after=
  pair=$(resolve_429_wait "$retry_after" "$RETRY_429_DEFAULT_WAIT_SECONDS" "$RETRY_MAX_WAIT_SECONDS")
  delay=${pair%% *}
  capped=${pair##* }
  ra_label=none
  if [ -n "$retry_after" ]; then ra_label=$retry_after; fi
  printf 'CLIENT_DIAG retry attempt=%s status=%s class=429 retry=%s/%s retry_after=%s wait=%s capped=%s\n' \
    "$attempt" "$status" "$retries_429" "$RETRY_MAX_ATTEMPTS_429" "$ra_label" "$delay" "$capped" >&2
  sleep "$delay"
done
