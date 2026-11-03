#!/bin/sh
# M07 の検査入口。
# unit は scripts/scenario-lib.sh の関数とマッピングの構成を、Docker を使わずに確かめる。
# smoke は unit に続けて、WireMock を Compose で起動し、リセットと確認を実機で確かめる（T706）。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELF="$ROOT/tests/m07-scenario-isolation.sh"
MODE=${1:-smoke}

case "$MODE" in
  unit | smoke) ;;
  *)
    printf 'usage: sh tests/m07-scenario-isolation.sh [unit|smoke]\n' >&2
    exit 2
    ;;
esac

cd "$ROOT"
# 読み込みに副作用はない。関数を試験ごとに呼ぶために、ここで読み込む。
. "$ROOT/scripts/scenario-lib.sh"

failures=0
total=0
# 一時ファイルは unit でも smoke でも使う。Compose は起動しないので、削除だけを trap で行う。
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

record_fail() { # 検査名
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# 終了コードだけを比べる。標準出力と標準エラーは捨てる。
expect_rc() { # 検査名 期待終了コード コマンド...
  _name=$1
  _want=$2
  shift 2
  total=$((total + 1))
  _rc=0
  "$@" >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -ne "$_want" ]; then
    record_fail "$_name (期待 rc=$_want 実際 rc=$_rc)"
  fi
}

# 標準出力と終了コードを比べる。
expect_out() { # 検査名 期待出力 コマンド...
  _name=$1
  _want=$2
  shift 2
  total=$((total + 1))
  _rc=0
  _got=$("$@" 2>/dev/null) || _rc=$?
  if [ "$_rc" -ne 0 ] || [ "$_got" != "$_want" ]; then
    record_fail "$_name (期待 出力=[$_want] 実際 rc=$_rc 出力=[$_got])"
  fi
}

# 終了コードと標準エラーの一部を比べる。標準エラーに期待の文字列が無ければ失敗する。
expect_err() { # 検査名 期待終了コード 含む文字列 コマンド...
  _name=$1
  _want=$2
  _needle=$3
  shift 3
  total=$((total + 1))
  _rc=0
  _err=$("$@" 2>&1 >/dev/null) || _rc=$?
  _matched=no
  case "$_err" in
    *"$_needle"*) _matched=yes ;;
  esac
  if [ "$_rc" -ne "$_want" ] || [ "$_matched" = no ]; then
    record_fail "$_name (期待 rc=$_want 標準エラーに[$_needle] 実際 rc=$_rc 標準エラー=[$_err])"
  fi
}

# 検査の本体を1つ走らせ、失敗したら記録する。関数の成否を終了コードで受ける。
check() { # 検査名 コマンド...
  _name=$1
  shift
  total=$((total + 1))
  if ! "$@"; then
    record_fail "$_name"
  fi
}

# 一時ディレクトリにスタブを1件置く。内容は1行のJSONとして書く。
put_stub() { # ディレクトリ ファイル名 JSON本文
  mkdir -p "$1"
  printf '%s\n' "$3" >"$1/$2"
}

# 状態を持つ2件（Started から Succeeded、続けて Succeeded）の正しいグループを置く。
# 静的検査が正しい構成を通すことを、拒否する検査の対照として確かめる。
G_START='"name":"g","scenarioName":"g","requiredScenarioState":"Started","newScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":500}'
G_DONE='"name":"g","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":200}'

make_valid_group() { # ディレクトリ
  put_stub "$1" start.json "{$G_START}"
  put_stub "$1" done.json "{$G_DONE}"
}

# 静的検査が1件の不正で拒否することを確かめる。検査名と、置くスタブの組を受け取る。
expect_static_reject() { # 検査名 ディレクトリ
  total=$((total + 1))
  if scenario_check_static "$2" >/dev/null 2>&1; then
    record_fail "$1（不正な構成が通った）"
  fi
}

# 名前の解決: 5名の宛先が M07 の表と一致する
unit_name_resolution() {
  expect_out "名前: normal の宛先" "/api/users/123" scenario_path normal
  expect_out "名前: error-500-then-200 の宛先" "/api/error-500-then-200" scenario_path error-500-then-200
  expect_out "名前: ratelimit-429 の宛先" "/api/ratelimit" scenario_path ratelimit-429
  expect_out "名前: slow-100 の宛先" "/api/slow-100" scenario_path slow-100
  expect_out "名前: slow-5000 の宛先" "/api/slow-5000" scenario_path slow-5000
  # 一覧は name を持つスタブだけを返す。name を持たない 500 と 503 が混ざれば、ここで落ちる
  expect_out "名前の一覧は5件だけ" "$(printf '%s\n' error-500-then-200 normal ratelimit-429 slow-100 slow-5000)" scenario_names
}

# 未定義と形式違反は、既定の宛先へ逃げずに終了コード2で止まる
unit_name_undefined() {
  expect_err "未定義の名前は終了コード2と一覧" 2 "unknown scenario: no-such" scenario_path no-such
  expect_err "未定義の名前の標準エラーに定義済みの一覧" 2 "normal" scenario_path no-such
  expect_rc "大文字は未定義扱い" 2 scenario_path Normal
  expect_rc "空文字は未定義扱い" 2 scenario_path ""
  expect_rc "アンダースコアは未定義扱い" 2 scenario_path a_b
  expect_rc "先頭ハイフンは未定義扱い" 2 scenario_path -x
  expect_rc "空白を含む名前は未定義扱い" 2 scenario_path "x y"
  # 制御文字は標準エラーへ出す前に取り除く。取り除かれていなければ、期待の文字列が一致しない
  _esc=$(printf '\033')
  expect_err "制御文字を含む名前は取り除いて表示" 2 "unknown scenario: normal" scenario_path "nor${_esc}mal"
}

# 同じ名前で宛先が異なるスタブは、既定へ逃げず終了コード1で失敗する
unit_name_conflict() {
  _dir="$tmp_root/conflict"
  put_stub "$_dir" d1.json '{"name":"dup","request":{"method":"GET","urlPath":"/d1"},"response":{"status":200}}'
  put_stub "$_dir" d2.json '{"name":"dup","request":{"method":"GET","urlPath":"/d2"},"response":{"status":200}}'
  expect_rc "同名で宛先が異なれば終了コード1" 1 scenario_path dup "$_dir"
  expect_rc "同名で宛先が異なれば静的検査も拒否" 1 scenario_check_static "$_dir"
}

# 静的検査: 実マッピングは通り、6検査と名前の形式の違反はそれぞれ拒否される
unit_static_check() {
  check "静的検査: 実マッピングが通る" scenario_check_static wiremock-scenarios/mappings

  _good="$tmp_root/good"
  make_valid_group "$_good"
  check "静的検査: 正しい状態グループが通る" scenario_check_static "$_good"
  expect_out "正しい状態グループの宛先" "/g" scenario_path g "$_good"

  # 状態の網羅: Started が無い、または2件ある
  _none="$tmp_root/no-started"
  put_stub "$_none" done.json "{$G_DONE}"
  expect_static_reject "状態の網羅: Started が0件" "$_none"

  _two="$tmp_root/two-started"
  make_valid_group "$_two"
  put_stub "$_two" start2.json "{$G_START}"
  expect_static_reject "状態の網羅: Started が2件" "$_two"

  # 遷移の到達性: newScenarioState が、どの requiredScenarioState にも現れない
  _unreach="$tmp_root/unreachable"
  put_stub "$_unreach" start.json '{"name":"g","scenarioName":"g","requiredScenarioState":"Started","newScenarioState":"Nowhere","request":{"method":"GET","urlPath":"/g"},"response":{"status":500}}'
  put_stub "$_unreach" done.json "{$G_DONE}"
  expect_static_reject "遷移の到達性: 遷移先が存在しない" "$_unreach"

  # 宛先の一致: 同じグループで urlPath が違う
  _dest="$tmp_root/dest-mismatch"
  put_stub "$_dest" start.json "{$G_START}"
  put_stub "$_dest" done.json '{"name":"g","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/other"},"response":{"status":200}}'
  expect_static_reject "宛先の一致: グループ内で urlPath が違う" "$_dest"

  # 名前の一致: 同じグループで name が違う
  _name=$tmp_root/name-mismatch
  put_stub "$_name" start.json "{$G_START}"
  put_stub "$_name" done.json '{"name":"h","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":200}}'
  expect_static_reject "名前の一致: グループ内で name が違う" "$_name"

  # 部分指定: requiredScenarioState があるのに scenarioName が無い
  _partial="$tmp_root/partial"
  put_stub "$_partial" p.json '{"name":"p","requiredScenarioState":"Started","request":{"method":"GET","urlPath":"/p"},"response":{"status":200}}'
  expect_static_reject "部分指定: scenarioName が無い状態スタブ" "$_partial"

  # パスの重複: グループの外で同じ method と urlPath を持つ2件
  _dup="$tmp_root/path-dup"
  put_stub "$_dup" p1.json '{"name":"p1","request":{"method":"GET","urlPath":"/dup"},"response":{"status":200}}'
  put_stub "$_dup" p2.json '{"name":"p2","request":{"method":"GET","urlPath":"/dup"},"response":{"status":200}}'
  expect_static_reject "パスの重複: グループの外で重複" "$_dup"

  # 名前の形式: 大文字を含む name
  _format="$tmp_root/name-format"
  put_stub "$_format" f.json '{"name":"Bad_Name","request":{"method":"GET","urlPath":"/f"},"response":{"status":200}}'
  expect_static_reject "名前の形式: 大文字とアンダースコア" "$_format"
}

# 状態遷移の2ファイルが plan 4.2 のとおりに書かれている
unit_state_machine_files() {
  _m=wiremock-scenarios/mappings
  if [ ! -f "$_m/error-500-then-200-1.json" ] || [ ! -f "$_m/error-500-then-200-2.json" ]; then
    record_fail "状態遷移の2ファイルが存在する"
    return 0
  fi
  total=$((total + 1))
  if ! python3 - "$_m/error-500-then-200-1.json" "$_m/error-500-then-200-2.json" <<'PY'
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


first = load(sys.argv[1])
second = load(sys.argv[2])

for stub in (first, second):
    if stub.get("name") != "error-500-then-200" or stub.get("scenarioName") != "error-500-then-200":
        raise SystemExit("name or scenarioName")
    if stub["request"].get("method") != "GET" or stub["request"].get("urlPath") != "/api/error-500-then-200":
        raise SystemExit("request")

if first.get("requiredScenarioState") != "Started" or first.get("newScenarioState") != "Succeeded":
    raise SystemExit("first state")
if first["response"].get("status") != 500 or first["response"].get("bodyFileName") != "error-500.json":
    raise SystemExit("first response")

if second.get("requiredScenarioState") != "Succeeded" or "newScenarioState" in second:
    raise SystemExit("second state")
if second["response"].get("status") != 200 or second["response"].get("bodyFileName") != "success.json":
    raise SystemExit("second response")

for stub in (first, second):
    if stub["response"].get("headers", {}).get("Content-Type") != "application/json":
        raise SystemExit("content type")
PY
  then
    record_fail "状態遷移の2ファイルが plan 4.2 どおり"
  fi
}

# unit は Docker と Compose を呼ばず、Compose の trap も登録しない。
# 偽の docker と docker-compose を PATH の先頭に置き、呼ばれたら記録する。
# 入れ子の unit 実行では、この検査を飛ばして再帰を防ぐ（M07_NESTED）。
unit_no_compose() {
  if [ -n "${M07_NESTED:-}" ]; then
    return 0
  fi
  _shim="$tmp_root/shim"
  _calls="$tmp_root/calls"
  mkdir -p "$_shim"
  for _cmd in docker docker-compose; do
    printf '#!/bin/sh\necho %s >>"%s"\nexit 99\n' "$_cmd" "$_calls" >"$_shim/$_cmd"
    chmod +x "$_shim/$_cmd"
  done
  total=$((total + 1))
  _rc=0
  M07_NESTED=1 PATH="$_shim:$PATH" sh "$SELF" unit >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    # 変数の直後に全角の括弧が続くと、UTF-8 のロケールでは変数名の一部と解釈され set -u で止まる。
    # そのため変数は波括弧で囲む。
    record_fail "unit が Docker なしで成功する（rc=${_rc}）"
  fi
  if [ -e "$_calls" ]; then
    record_fail "unit が docker か docker-compose を呼んだ"
  fi
}

# 文書の追加手順: 文書の JSON 例を一時ディレクトリへ置き、解決と静的検査が通ることを確かめる。
unit_doc_add_procedure() {
  _tmp_dir="$tmp_root/doc-add"
  mkdir -p "$_tmp_dir/mappings"
  cp wiremock-scenarios/mappings/*.json "$_tmp_dir/mappings/"
  python3 - "docs/シナリオ隔離.md" "$_tmp_dir/mappings/example-added.json" <<'PY' || return 1
import re
import sys

doc, out = sys.argv[1], sys.argv[2]
text = open(doc, encoding="utf-8").read()
# 文書の最初の json のコードブロックを、追加する例として取り出す。
match = re.search(r"```json\n(.*?)\n```", text, re.S)
if match is None:
    sys.exit(1)
open(out, "w", encoding="utf-8").write(match.group(1) + "\n")
PY
  [ "$(scenario_path example-added "$_tmp_dir/mappings")" = "/api/example-added" ] || return 1
  scenario_check_static "$_tmp_dir/mappings" || return 1
  rm -rf "$_tmp_dir"
}

# 文書の内容: 並列禁止の節と4項目の語があり、識別情報のパターンがない。README から実在する文書へ辿れる。
unit_doc_content() {
  _doc="docs/シナリオ隔離.md"
  grep -Fq '## 並列実行をしない理由' "$_doc" || return 1
  for _word in 'シナリオ状態' 'リクエストジャーナル' 'リセット操作' 'ポートとコンテナ'; do
    grep -Fq "$_word" "$_doc" || return 1
  done
  if grep -E '[0-9]{12}|arn:aws' "$_doc" >/dev/null; then
    return 1
  fi
  grep -Fq '(docs/シナリオ隔離.md)' README.md && [ -f "$_doc" ]
}

unit_main() {
  check "文書の追加手順（JSON例が解決と静的検査を通る）" unit_doc_add_procedure
  check "文書の内容（並列禁止の節、識別情報の不在、README のリンク）" unit_doc_content
  unit_name_resolution
  unit_name_undefined
  unit_name_conflict
  unit_static_check
  check "状態遷移の2ファイル" unit_state_machine_files
  check "Compose を呼ばない" unit_no_compose

  if [ "$failures" -ne 0 ]; then
    printf 'M07 unit: %s of %s checks failed\n' "$failures" "$total" >&2
    exit 1
  fi
  printf 'M07 scenario isolation unit passed (%s checks)\n' "$total"
}

unit_main

smoke_wiremock_url=${WIREMOCK_URL:-http://127.0.0.1:8080}

# WireMock と Squid を Compose で起動し、リセット、対照実験、通し実行を行う（T707、plan.md 6.2）。
# 起動と後始末は M06 の run_smoke と同じ方式。後始末の trap は元の終了コードを保つ。
smoke_wiremock_url=${WIREMOCK_URL:-http://127.0.0.1:8080}
smoke_proxy_url=${PROXY_URL:-http://127.0.0.1:3128}
export WIREMOCK_URL="$smoke_wiremock_url"

smoke_dir="$tmp_root/smoke"
mkdir -p "$smoke_dir"

# test-client を1回だけ実行する。標準出力と標準エラーは別々に残し、終了コードは client_rc へ入れる。
smoke_client() { # docker-compose run に渡す -e 指定
  client_rc=0
  docker-compose run --rm --no-deps "$@" test-client \
    >"$smoke_dir/out" 2>"$smoke_dir/err" || client_rc=$?
}

# WireMock の管理APIで、パス一致の呼び出し件数だけを読む。ジャーナルのリセットはしない。
wiremock_count() { # URLパス
  _body=$(printf '{"method":"GET","url":"%s"}' "$1")
  _res=$(curl --fail --silent --show-error --connect-timeout 2 --max-time 10 -H 'Content-Type: application/json' \
    -d "$_body" "$smoke_wiremock_url/__admin/requests/count") || return 1
  _n=$(printf '%s' "$_res" | sed -n 's/.*"count" *: *\([0-9][0-9]*\).*/\1/p')
  [ -n "$_n" ] || return 1
  printf '%s' "$_n"
}

# 対象のパスへ直接 HTTP ステータスを読む。Squid は使わない。
smoke_status() { # URLパス
  curl --connect-timeout 2 --max-time 10 --silent --output /dev/null --write-out '%{http_code}' "$smoke_wiremock_url$1" || true
}

# Squid 経由で api.example.com のパスへ要求し、HTTP ステータスを読む。
smoke_via_proxy() { # URLパス
  curl --noproxy '' --proxy "$smoke_proxy_url" --connect-timeout 2 --max-time 15 --silent --output /dev/null \
    --write-out '%{http_code}' "http://api.example.com$1" || true
}

smoke_reset_verify() {
  wiremock_reset && wiremock_verify_reset wiremock-scenarios/mappings
}

# 管理APIの name と request.urlPath が、scenario_path の結果と一致する（plan 6.2 の検査2）。
smoke_names_match() {
  curl --fail --silent --show-error --connect-timeout 2 --max-time 10 "$smoke_wiremock_url/__admin/mappings" \
    >"$smoke_dir/mappings.json" || return 1
  for _n in $(scenario_names); do
    _want=$(scenario_path "$_n") || return 1
    _got=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next((m["request"]["urlPath"] for m in d["mappings"] if m.get("name")==sys.argv[2]), ""))' \
      "$smoke_dir/mappings.json" "$_n") || return 1
    [ "$_got" = "$_want" ] || return 1
  done
}

# 対照実験（検査3）。リセットなしで2回目は200、リセットを挟むと500に戻る。
smoke_control() {
  wiremock_reset || return 1
  _c1=$(smoke_status /api/error-500-then-200)
  _c2=$(smoke_status /api/error-500-then-200)
  wiremock_reset || return 1
  _c3=$(smoke_status /api/error-500-then-200)
  [ "$_c1" = 500 ] && [ "$_c2" = 200 ] && [ "$_c3" = 500 ]
}

# Test Client の通し実行（検査4、5）。リセットを挟んでから実行し、500 のあと 200 で総試行2回。
smoke_recovered_run() {
  wiremock_reset || return 1
  smoke_client -e TEST_API_PATH=/api/error-500-then-200
  [ "$client_rc" -eq 0 ] \
    && grep -qx 'CLIENT_STATUS=200' "$smoke_dir/out" \
    && grep -Fq 'CLIENT_DIAG result=success attempts=2 status=200' "$smoke_dir/err"
}

# 4シナリオの応答と、Squid 経由の到達（検査6）。
smoke_scenarios() {
  [ "$(smoke_via_proxy /api/users/123)" = 200 ] \
    && [ "$(smoke_via_proxy /api/ratelimit)" = 429 ] \
    && [ "$(smoke_via_proxy /api/slow-100)" = 200 ] \
    && [ "$(smoke_via_proxy /api/slow-5000)" = 200 ]
}

# ratelimit-429 の待機2秒と呼び出し回数（検査7）。呼び出し回数は診断の試行回数と一致する。
smoke_ratelimit() {
  _before=$(wiremock_count /api/ratelimit) || return 1
  smoke_client -e TEST_API_PATH=/api/ratelimit
  _after=$(wiremock_count /api/ratelimit) || return 1
  _attempts=$(sed -n 's/.*result=retries_exhausted attempts=\([0-9][0-9]*\) status=429.*/\1/p' "$smoke_dir/err")
  [ -n "$_attempts" ] \
    && grep -qx 'CLIENT_STATUS=429' "$smoke_dir/out" \
    && grep -Fq 'retry_after=2 wait=2 capped=0' "$smoke_dir/err" \
    && [ "$((_after - _before))" -eq "$_attempts" ]
}

# 手順3から7を1周する（検査9）。同じ起動の中で、リセットと再実行の結果が毎周同じになることを見る。
smoke_round() { # 周回の番号
  check "[周$1] 対照実験: リセットなしの2回目は200、リセット後は500" smoke_control
  check "[周$1] Test Client: 500 のあと 200 で総試行2回" smoke_recovered_run
  check "[周$1] リセットを挟んでも同じ結果（FR-706）" smoke_recovered_run
  check "[周$1] 4シナリオの応答と Squid 経由の到達" smoke_scenarios
  check "[周$1] ratelimit-429: 待機2秒と呼び出し回数" smoke_ratelimit
}

smoke_checks() {
  check "開始前のリセットと確認" smoke_reset_verify
  check "管理APIの name と urlPath が scenario_path と一致" smoke_names_match
  smoke_round 1
  smoke_round 2
}

# 起動、準備完了の待機、後始末。M06 の run_smoke と同じ方式。
smoke_run() {
  cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
      docker-compose logs --no-color squid wiremock >&2 || true
    fi
    # 後始末でもリセットを試みる（FR-708）。失敗しても Compose の回収は続ける。
    printf 'cleanup: reset attempted\n' >&2
    if wiremock_reset; then
      printf 'cleanup: reset ok\n' >&2
    else
      printf 'cleanup: reset failed (ignored)\n' >&2
    fi
    docker-compose down --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$tmp_root"
    exit "$rc"
  }
  trap cleanup EXIT
  # 中断でも EXIT の後始末を通す。終了コードは cleanup が保つ。
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # 前回の残りが別の結果を混ぜないように、開始前にも落としておく。
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  docker-compose up -d --build squid wiremock >/dev/null
  docker-compose build test-client >/dev/null

  _i=0
  until curl --fail --silent --show-error --max-time 5 "$smoke_wiremock_url/__admin/mappings" >/dev/null 2>&1; do
    _i=$((_i + 1))
    [ "$_i" -lt 60 ] || { printf 'FAIL: WireMock の管理APIが準備できない\n' >&2; exit 1; }
    sleep 1
  done
  # Squid 経由で WireMock に届くまで待つ。502 を成功扱いにしないため --fail を付け、本文も見る。
  _i=0
  until _body=$(curl --fail --noproxy '' --proxy "$smoke_proxy_url" --silent --show-error --max-time 5 \
    'http://api.example.com/api/users/123') && printf '%s' "$_body" | grep -Fq '"id": 123'; do
    _i=$((_i + 1))
    [ "$_i" -lt 60 ] || { printf 'FAIL: Squid 経由の疎通が準備できない\n' >&2; exit 1; }
    sleep 1
  done

  smoke_checks

  # 後始末の確認: Compose の残存がないこと。
  docker-compose down --remove-orphans >/dev/null 2>&1 || true
  check "終了後に Compose の残存がない" sh -c '[ -z "$(docker-compose ps -a -q)" ]'
  # 失敗経路は子の検査入口を起動するため、親のスタックを畳んでから行う。
  # 子の中では行わない（子が自分の失敗経路をさらに起動する再帰を防ぐ）。
  if [ -z "${M07_NESTED:-}" ]; then
    smoke_failure_path
  fi
}

# 失敗経路（検査8、plan.md 6.3）。本物の検査入口を子として起動し、後始末を確かめる。
# 本番のスクリプトに注入用の分岐は入れない。
smoke_clean_after() { # 子の一時ディレクトリ
  [ -z "$(ls -A "$1")" ] && [ -z "$(docker-compose ps -a -q)" ]
}

# アサーション失敗の代わりに、WireMock の管理APIに届かない宛先を渡す。
# 準備完了の待ちが時間切れで終わり、終了コード1で止まる。後始末のリセットは失敗する。
smoke_case_assert() {
  _t=$(mktemp -d "$tmp_root/child.XXXXXX") || return 1
  _rc=0
  env WIREMOCK_URL=http://127.0.0.1:9 M07_NESTED=1 TMPDIR="$_t" sh "$SELF" smoke \
    >/dev/null 2>"$smoke_dir/child-assert.err" || _rc=$?
  [ "$_rc" -eq 1 ] \
    && grep -Fq 'cleanup: reset attempted' "$smoke_dir/child-assert.err" \
    && smoke_clean_after "$_t"
}

# 子を起動し、管理APIが応答してから信号を送り、終了コードを標準出力へ出す。
# 子の信号の既定の動作を Python の preexec_fn で戻す。バックグラウンドのシェルは INT を無視するため。
smoke_child_signal() { # 信号名 子の一時ディレクトリ
  python3 - "$SELF" "$1" "$smoke_wiremock_url" "$2" "$smoke_dir/child-$1.err" <<'PY'
import os
import signal
import subprocess
import sys
import time
import urllib.request

self_path, sig_name, admin, tmp_parent, err_path = sys.argv[1:6]
sig = {"INT": signal.SIGINT, "TERM": signal.SIGTERM}[sig_name]
env = dict(os.environ, M07_NESTED="1", TMPDIR=tmp_parent)

def restore_default_signals():
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, signal.SIG_DFL)

with open(err_path, "w") as err:
    proc = subprocess.Popen(["sh", self_path, "smoke"], env=env,
                            stdout=subprocess.DEVNULL, stderr=err,
                            preexec_fn=restore_default_signals)
    ready = False
    deadline = time.time() + 180
    while time.time() < deadline and proc.poll() is None:
        try:
            with urllib.request.urlopen(admin + "/__admin/mappings", timeout=2) as resp:
                if resp.status == 200:
                    ready = True
                    break
        except OSError:
            time.sleep(1)
    if not ready:
        proc.kill()
        proc.wait()
        print("not-ready")
        sys.exit(0)
    proc.send_signal(sig)
    try:
        print(proc.wait(timeout=120))
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        print("timeout")
PY
}

smoke_case_signal() { # 信号名 期待する終了コード
  _t=$(mktemp -d "$tmp_root/child.XXXXXX") || return 1
  _rc=$(smoke_child_signal "$1" "$_t") || return 1
  [ "$_rc" = "$2" ] \
    && grep -Fq 'cleanup: reset attempted' "$smoke_dir/child-$1.err" \
    && smoke_clean_after "$_t"
}

smoke_failure_path() {
  check "アサーション失敗: 終了コード1を保ち、リセットを試み、残存と一時ファイルがない" smoke_case_assert
  check "INT: 終了コード130、リセットを試み、残存と一時ファイルがない" smoke_case_signal INT 130
  check "TERM: 終了コード143、リセットを試み、残存と一時ファイルがない" smoke_case_signal TERM 143
}

if [ "$MODE" = smoke ]; then
  smoke_run
  if [ "$failures" -ne 0 ]; then
    printf 'M07 smoke: %s of %s checks failed\n' "$failures" "$total" >&2
    exit 1
  fi
  printf 'M07 scenario isolation smoke passed (%s checks)\n' "$total"
fi
