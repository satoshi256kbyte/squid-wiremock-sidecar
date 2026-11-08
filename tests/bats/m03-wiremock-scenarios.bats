#!/usr/bin/env bats
# M03 WireMock シナリオの検査。
#   unit（Docker を使わない）: validate_json と validate_mapping の判定（旧の判定を固定する）。
#   smoke（WireMock が起動している前提）: mapping の静的検査、管理APIの応答、本文、ステータス、遅延。
# 入口は tests/m03-wiremock-scenarios.sh。smoke の起動と停止は、その入口が行う。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  # jq の実体は、固定版の照合で得る（unit の判定と、smoke の mapping の判定に使う）。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/resolve-tool.sh"
  resolve_tool jq 's/^jq-//p' --version || return 1
  jq_bin=$RESOLVED_PATH
  wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"
}

# JSON の値が1つだけ入っているかを見る（空ファイルと、JSON が2つ連続した入力は失敗）。
validate_json() {
  "$jq_bin" -e -s 'length == 1' "$1" >/dev/null
}

# 必須の項目（request.method、request.urlPath、response.status）を確かめる。失敗時は欠けた項目を標準エラーに出す。
validate_mapping() {
  if "$jq_bin" -e '
    (.request | type == "object" and has("method") and has("urlPath")) and
    (.response | type == "object" and has("status"))
  ' "$1" >/dev/null 2>&1; then
    return 0
  fi
  _missing=$("$jq_bin" -r '
    [
      (if (.request | type) == "object" and (.request | has("method")) then empty else "request.method" end),
      (if (.request | type) == "object" and (.request | has("urlPath")) then empty else "request.urlPath" end),
      (if (.response | type) == "object" and (.response | has("status")) then empty else "response.status" end)
    ] | join(", ")
  ' "$1" 2>/dev/null || true)
  printf '%s\n' "missing mapping fields: ${_missing:-(not an object)}" >&2
  return 1
}

# 応答の本文と、ヘッダの Content-Type を確かめる。
check_body() { # 経路 期待のステータス 期待の本文
  _status=$(curl --silent --show-error -D "$TMP/headers" -o "$TMP/body" -w '%{http_code}' "$wiremock_url$1")
  [ "$_status" = "$2" ] || return 1
  grep -Eiq '^Content-Type:[[:space:]]*application/json' "$TMP/headers" || return 1
  grep -Fq "$3" "$TMP/body"
}

# 遅延の下限を確かめる。
check_delay() { # 経路 下限の秒 期待の本文
  _elapsed=$(curl --fail --silent --show-error -D "$TMP/delay-headers" -o "$TMP/delay-body" -w '%{time_total}' "$wiremock_url$1")
  awk -v elapsed="$_elapsed" -v minimum="$2" 'BEGIN { exit !(elapsed >= minimum) }' || return 1
  grep -Eiq '^Content-Type:[[:space:]]*application/json' "$TMP/delay-headers" || return 1
  grep -Fq "$3" "$TMP/delay-body"
}

# ---- unit: Docker を使わない判定（旧の unit_* の検査名を保つ） ----

# bats test_tags=unit
@test "unit_validate_json_rejects_broken_json" {
  printf '%s' '{' > "$TMP/broken.json"
  if validate_json "$TMP/broken.json" >/dev/null 2>&1; then
    return 1
  fi
}

# bats test_tags=unit
@test "unit_validate_json_keeps_empty_array_and_null" {
  printf '%s\n' '[]' > "$TMP/empty.json"
  printf '%s\n' 'null' > "$TMP/null.json"
  validate_json "$TMP/empty.json" >/dev/null 2>&1 || return 1
  validate_json "$TMP/null.json" >/dev/null 2>&1
}

# bats test_tags=unit
@test "unit_validate_json_rejects_empty_and_multiple_values" {
  : > "$TMP/empty-file.json"
  printf '%s\n' '{} {}' > "$TMP/two-values.json"
  if validate_json "$TMP/empty-file.json" >/dev/null 2>&1; then
    return 1
  fi
  if validate_json "$TMP/two-values.json" >/dev/null 2>&1; then
    return 1
  fi
}

# bats test_tags=unit
@test "unit_validate_mapping_accepts_complete_mapping" {
  printf '%s\n' '{"request":{"method":"GET","urlPath":"/a"},"response":{"status":200}}' > "$TMP/ok.json"
  validate_mapping "$TMP/ok.json" >/dev/null 2>&1
}

# bats test_tags=unit
@test "unit_validate_mapping_rejects_missing_key" {
  printf '%s\n' '{"request":{"method":"GET"},"response":{"status":200}}' > "$TMP/missing.json"
  if validate_mapping "$TMP/missing.json" >/dev/null 2>"$TMP/missing.err"; then
    return 1
  fi
  grep -Fq 'request.urlPath' "$TMP/missing.err"
}

# bats test_tags=unit
@test "unit_validate_mapping_rejects_empty_array_and_null" {
  printf '%s\n' '[]' > "$TMP/empty.json"
  printf '%s\n' 'null' > "$TMP/null.json"
  if validate_mapping "$TMP/empty.json" >/dev/null 2>&1; then
    return 1
  fi
  if validate_mapping "$TMP/null.json" >/dev/null 2>&1; then
    return 1
  fi
}

# ---- smoke: WireMock が起動している前提（入口が起動と停止を行う） ----

# bats test_tags=smoke
@test "m03 smoke: mapping と __files の JSON が1つの値で、mapping の項目が揃う" {
  for file in wiremock-scenarios/mappings/*.json wiremock-scenarios/__files/*.json; do
    validate_json "$file" || return 1
  done
  for file in wiremock-scenarios/mappings/*.json; do
    validate_mapping "$file" || return 1
  done
}

# bats test_tags=smoke
@test "m03 smoke: scenario の静的検査（状態グループと宛先）が通る" {
  # shellcheck disable=SC2034 # 読み込む scripts/scenario-lib.sh が SWSC_ROOT を参照する。
  SWSC_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$ROOT/scripts/scenario-lib.sh"
  scenario_check_static wiremock-scenarios/mappings
}

# bats test_tags=smoke
@test "m03 smoke: 壊れた JSON は拒否される" {
  printf '%s' '{' > "$TMP/invalid.json"
  if validate_json "$TMP/invalid.json" >/dev/null 2>&1; then
    return 1
  fi
}

# bats test_tags=smoke
@test "m03 smoke: 項目の欠けた mapping は拒否される" {
  printf '%s' '{"request": {}}' > "$TMP/incomplete-mapping.json"
  if validate_mapping "$TMP/incomplete-mapping.json" >/dev/null 2>&1; then
    return 1
  fi
}

# bats test_tags=smoke
@test "m03 smoke: WireMock に /api の経路が登録されている" {
  _mappings=$(curl --fail --silent --show-error "$wiremock_url/__admin/mappings")
  for path in '/api/users/123' '/api/error-500' '/api/error-503' '/api/ratelimit' '/api/slow-100' '/api/slow-5000'; do
    printf '%s' "$_mappings" | grep -q "$path" || return 1
  done
}

# bats test_tags=smoke
@test "m03 smoke: /api/users/123 は 200 と JSON の本文を返す" {
  check_body /api/users/123 200 '"id": 123'
}

# bats test_tags=smoke
@test "m03 smoke: /api/error-500 は 500 を返す" {
  check_body /api/error-500 500 'Internal Server Error'
}

# bats test_tags=smoke
@test "m03 smoke: /api/error-503 は 503 を返す" {
  check_body /api/error-503 503 'Service Unavailable'
}

# bats test_tags=smoke
@test "m03 smoke: /api/ratelimit は 429 と Retry-After: 2 を返す" {
  check_body /api/ratelimit 429 'Rate Limited' || return 1
  grep -Eiq '^Retry-After:[[:space:]]*2' "$TMP/headers"
}

# bats test_tags=smoke
@test "m03 smoke: /api/slow-100 は 0.08 秒以上で応答する" {
  check_delay /api/slow-100 0.08 'slow-response'
}

# bats test_tags=smoke
@test "m03 smoke: /api/slow-5000 は 4.5 秒以上で応答する" {
  check_delay /api/slow-5000 4.5 'slow-response'
}
