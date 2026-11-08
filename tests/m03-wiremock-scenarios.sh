#!/bin/sh
# M03 WireMock シナリオの検査。
#   unit:  Docker を使わず、mapping と JSON の判定（validate_json、validate_mapping）だけを確かめる。
#   smoke: 新基盤で WireMock を起動し、mapping の静的検査、管理APIの応答、本文、ステータス、遅延を確かめる。
# 引数を省略すると smoke になる（品質ゲートの既存の呼び出しを変えないため）。
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

# jq の実体は、固定版を照合して得る。未導入や版違いは、ロックを取る前に導入手順つきで止まる。
# shellcheck source=/dev/null
. "$ROOT/scripts/lib/resolve-tool.sh"
resolve_tool jq 's/^jq-//p' --version || exit 1
jq_bin=$RESOLVED_PATH

# JSON の値が1つだけ入っているかを見る。-s で全体を1つの配列として読み、件数が1のときだけ成功する。
# Why: 空ファイルと、JSON が2つ連続した入力（{} {}）を失敗にするため（旧の json.load と同じ）。
# null と [] は値が1つなので成功する（plan 9.3 節の旧の判定を保つ）。
validate_json() {
  "$jq_bin" -e -s 'length == 1' "$1" >/dev/null
}

# 必須の項目（request.method、request.urlPath、response.status）を確かめる。
# -e を付けるため、欠落や null は失敗する。失敗時は欠けた項目名を旧と同じ形式で標準エラーに出す。
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

# ---------------------------------------------------------------------------
# unit: Docker を使わない判定の検査。validate_json と validate_mapping の旧の判定（plan 9.3 節）を固定する。
# Why: 旧の Python 実装と新しい jq 実装が、同じ入力で同じ判定になることを、Docker なしで確かめるため。
# ---------------------------------------------------------------------------

unit_validate_json_rejects_broken_json() {
  printf '%s' '{' > "$unit_dir/broken.json"
  ! validate_json "$unit_dir/broken.json" >/dev/null 2>&1
}

unit_validate_json_keeps_empty_array_and_null() {
  printf '%s\n' '[]' > "$unit_dir/empty.json"
  printf '%s\n' 'null' > "$unit_dir/null.json"
  validate_json "$unit_dir/empty.json" >/dev/null 2>&1 || return 1
  validate_json "$unit_dir/null.json" >/dev/null 2>&1
}

unit_validate_json_rejects_empty_and_multiple_values() {
  : > "$unit_dir/empty-file.json"
  printf '%s\n' '{} {}' > "$unit_dir/two-values.json"
  if validate_json "$unit_dir/empty-file.json" >/dev/null 2>&1; then
    return 1
  fi
  ! validate_json "$unit_dir/two-values.json" >/dev/null 2>&1
}

unit_validate_mapping_accepts_complete_mapping() {
  printf '%s\n' '{"request":{"method":"GET","urlPath":"/a"},"response":{"status":200}}' > "$unit_dir/ok.json"
  validate_mapping "$unit_dir/ok.json" >/dev/null 2>&1
}

unit_validate_mapping_rejects_missing_key() {
  printf '%s\n' '{"request":{"method":"GET"},"response":{"status":200}}' > "$unit_dir/missing.json"
  if validate_mapping "$unit_dir/missing.json" >/dev/null 2>"$unit_dir/missing.err"; then
    return 1
  fi
  grep -Fq 'request.urlPath' "$unit_dir/missing.err"
}

unit_validate_mapping_rejects_empty_array_and_null() {
  printf '%s\n' '[]' > "$unit_dir/empty.json"
  printf '%s\n' 'null' > "$unit_dir/null.json"
  if validate_mapping "$unit_dir/empty.json" >/dev/null 2>&1; then
    return 1
  fi
  ! validate_mapping "$unit_dir/null.json" >/dev/null 2>&1
}

run_unit() {
  unit_dir=$(mktemp -d) || return 1
  # Why: 一時ディレクトリは、この検査だけが作って消す（ロックも Docker も使わない）。
  trap 'rm -f "$unit_dir"/* || true; rmdir "$unit_dir" || true' EXIT
  _fail=0
  for _case in \
    unit_validate_json_rejects_broken_json \
    unit_validate_json_keeps_empty_array_and_null \
    unit_validate_json_rejects_empty_and_multiple_values \
    unit_validate_mapping_accepts_complete_mapping \
    unit_validate_mapping_rejects_missing_key \
    unit_validate_mapping_rejects_empty_array_and_null
  do
    if "$_case"; then
      printf 'ok: %s\n' "$_case"
    else
      printf 'FAIL: %s\n' "$_case"
      _fail=$((_fail + 1))
    fi
  done
  if [ "$_fail" -ne 0 ]; then
    printf 'unit: %s 件失敗\n' "$_fail"
    return 1
  fi
  printf '%s\n' 'M03 unit: 全件通過'
  return 0
}

mode=${1:-smoke}
case "$mode" in
  unit)
    run_unit
    exit $?
    ;;
  smoke) ;;
  *)
    printf '%s\n' '使い方: sh tests/m03-wiremock-scenarios.sh [unit|smoke]' >&2
    exit 2
    ;;
esac

# ---------------------------------------------------------------------------
# smoke: WireMock を起動して確かめる。
# ---------------------------------------------------------------------------

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
