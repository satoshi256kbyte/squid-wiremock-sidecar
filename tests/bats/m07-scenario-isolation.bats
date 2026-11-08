#!/usr/bin/env bats
# M07 シナリオの隔離の検査（unit）。Docker を使わず、scripts/scenario-lib.sh の関数と、マッピングの構成を確かめる。
# 旧の tests/m07-scenario-isolation.sh の unit の検査名を、そのまま @test の名前にした。
# 入口は tests/m07-scenario-isolation.sh（unit は tests/lib/run-bats.sh を呼ぶ）。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  tmp_root=$TMP
  SELF=$ROOT/tests/m07-scenario-isolation.sh
  # 固定版の jq を照合して得る（マッピングの判定に使う）。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/resolve-tool.sh"
  resolve_tool jq 's/^jq-//p' --version || return 1
  jq_bin=$RESOLVED_PATH
  # shellcheck source=/dev/null
  . "$ROOT/scripts/scenario-lib.sh"
}

# ---- 検査の補助（旧の expect_* と同じ判定。失敗は return 1 で返す） ----

# 終了コードだけを比べる。
expect_rc() { # 検査名 期待終了コード コマンド...
  _name=$1
  _want=$2
  shift 2
  _rc=0
  "$@" >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -ne "$_want" ]; then
    printf 'FAIL: %s (期待 rc=%s 実際 rc=%s)\n' "$_name" "$_want" "$_rc" >&2
    return 1
  fi
}

# 標準出力と終了コードを比べる。
expect_out() { # 検査名 期待出力 コマンド...
  _name=$1
  _want=$2
  shift 2
  _rc=0
  _got=$("$@" 2>/dev/null) || _rc=$?
  if [ "$_rc" -ne 0 ] || [ "$_got" != "$_want" ]; then
    printf 'FAIL: %s (期待 出力=[%s] 実際 rc=%s 出力=[%s])\n' "$_name" "$_want" "$_rc" "$_got" >&2
    return 1
  fi
}

# 終了コードと標準エラーの一部を比べる。
expect_err() { # 検査名 期待終了コード 含む文字列 コマンド...
  _name=$1
  _want=$2
  _needle=$3
  shift 3
  _rc=0
  _err=$("$@" 2>&1 >/dev/null) || _rc=$?
  _matched=no
  case "$_err" in
    *"$_needle"*) _matched=yes ;;
  esac
  if [ "$_rc" -ne "$_want" ] || [ "$_matched" = no ]; then
    printf 'FAIL: %s (期待 rc=%s 標準エラーに[%s] 実際 rc=%s 標準エラー=[%s])\n' "$_name" "$_want" "$_needle" "$_rc" "$_err" >&2
    return 1
  fi
}

# 静的検査が1件の不正で拒否することを確かめる。
expect_static_reject() { # 検査名 ディレクトリ
  if scenario_check_static "$2" >/dev/null 2>&1; then
    printf 'FAIL: %s（不正な構成が通った）\n' "$1" >&2
    return 1
  fi
}

# 一時ディレクトリにスタブを1件置く。内容は1行のJSONとして書く。
put_stub() { # ディレクトリ ファイル名 JSON本文
  mkdir -p "$1"
  printf '%s\n' "$3" >"$1/$2"
}

G_START='"name":"g","scenarioName":"g","requiredScenarioState":"Started","newScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":500}'
G_DONE='"name":"g","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":200}'

make_valid_group() { # ディレクトリ
  put_stub "$1" start.json "{$G_START}"
  put_stub "$1" done.json "{$G_DONE}"
}

# wiremock_verify_reset を、偽の管理API応答で実行する。curl を関数で差し替え、-o の出力先へ決め打ちのJSONを書く。
# Why: 実機の WireMock では、Squid の内部要求が混ざる偶然を作れず、偽陽性を再現できないため。
verify_with() { # リクエスト応答のJSON シナリオ応答のJSON マッピング応答のmeta.total
  (
    FAKE_REQ=$1
    FAKE_SCN=$2
    FAKE_MAP=$3
    # shellcheck disable=SC2329 # wiremock_verify_reset が curl を呼ぶときに、この関数が差し替えとして使われる。
    curl() {
      _o=
      _u=
      while [ $# -gt 0 ]; do
        case $1 in
          -o) _o=$2; shift 2 ;;
          -*) shift ;;
          *) _u=$1; shift ;;
        esac
      done
      case $_u in
        */__admin/mappings) printf '{"meta":{"total":%s}}' "$FAKE_MAP" >"$_o" ;;
        */__admin/requests) printf '%s' "$FAKE_REQ" >"$_o" ;;
        */__admin/scenarios) printf '%s' "$FAKE_SCN" >"$_o" ;;
        *) return 22 ;;
      esac
    }
    _md=$(mktemp -d "$tmp_root/verify-map.XXXXXX")
    printf '{}\n' >"$_md/a.json"
    wiremock_verify_reset "$_md"
  )
}

# ---- リセットの確認（Issue #23: Squid の内部要求は数えず、テストの通信と想定外の要求は数える） ----

# bats test_tags=unit
@test "ジャーナル: 空なら通る" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _empty='{"meta":{"total":0},"requests":[]}'
  expect_rc "ジャーナル: 空なら通る" 0 verify_with "$_empty" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: Squid の内部要求だけなら通る（偽陽性にならない）" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _internal='{"meta":{"total":1},"requests":[{"request":{"url":"/squid-internal-periodic/store_digest"}}]}'
  expect_rc "ジャーナル: Squid の内部要求だけなら通る（偽陽性にならない）" 0 verify_with "$_internal" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: テストの通信が1件残れば実測1で失敗する" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _api='{"meta":{"total":1},"requests":[{"request":{"url":"/api/users/123"}}]}'
  expect_err "ジャーナル: テストの通信が1件残れば実測1で失敗する" 1 "リクエストジャーナル件数: 期待 0 実測 1" \
    verify_with "$_api" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: 内部要求とテストの通信が混ざれば、テストの通信だけを数える" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _mixed='{"meta":{"total":2},"requests":[{"request":{"url":"/squid-internal-periodic/store_digest"}},{"request":{"url":"/api/users/123"}}]}'
  expect_err "ジャーナル: 内部要求とテストの通信が混ざれば、テストの通信だけを数える" 1 "リクエストジャーナル件数: 期待 0 実測 1" \
    verify_with "$_mixed" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: 接頭辞でなく部分一致の URL は内部要求として除外しない" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _lookalike='{"meta":{"total":1},"requests":[{"request":{"url":"/api/squid-internal-x"}}]}'
  expect_err "ジャーナル: 接頭辞でなく部分一致の URL は内部要求として除外しない" 1 "リクエストジャーナル件数: 期待 0 実測 1" \
    verify_with "$_lookalike" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: meta.total と requests[] の件数が食い違えば数えずに失敗する" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _mismatch='{"meta":{"total":2},"requests":[{"request":{"url":"/squid-internal-periodic/store_digest"}}]}'
  expect_err "ジャーナル: meta.total と requests[] の件数が食い違えば数えずに失敗する" 1 "meta.total と一致しない" \
    verify_with "$_mismatch" "$_scn_ok" 1
}

# bats test_tags=unit
@test "ジャーナル: URL が読めなければ失敗する" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _nourl='{"meta":{"total":1},"requests":[{"request":{}}]}'
  expect_err "ジャーナル: URL が読めなければ失敗する" 1 "request.url が読めない" verify_with "$_nourl" "$_scn_ok" 1
}

# bats test_tags=unit
@test "確認の3項目: マッピング件数の不一致は引き続き失敗する" {
  _scn_ok='{"scenarios":[{"name":"g","state":"Started"}]}'
  _empty='{"meta":{"total":0},"requests":[]}'
  expect_err "確認の3項目: マッピング件数の不一致は引き続き失敗する" 1 "マッピング件数: 期待 1 実測 2" \
    verify_with "$_empty" "$_scn_ok" 2
}

# bats test_tags=unit
@test "確認の3項目: シナリオ状態が Started でなければ引き続き失敗する" {
  _internal='{"meta":{"total":1},"requests":[{"request":{"url":"/squid-internal-periodic/store_digest"}}]}'
  _bad_scn='{"scenarios":[{"name":"g","state":"Succeeded"}]}'
  expect_err "確認の3項目: シナリオ状態が Started でなければ引き続き失敗する" 1 "シナリオ状態: g 期待 Started 実測 Succeeded" \
    verify_with "$_internal" "$_bad_scn" 1
}

# ---- 文書 ----

# bats test_tags=unit
@test "文書の追加手順（JSON例が解決と静的検査を通る）" {
  _tmp_dir="$tmp_root/doc-add"
  mkdir -p "$_tmp_dir/mappings"
  cp wiremock-scenarios/mappings/*.json "$_tmp_dir/mappings/"
  python3 - "docs/シナリオ隔離.md" "$_tmp_dir/mappings/example-added.json" <<'PY'
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
}

# bats test_tags=unit
@test "文書の内容（並列禁止の節、識別情報の不在、README のリンク）" {
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

# ---- 名前の解決 ----

# bats test_tags=unit
@test "名前: normal の宛先" {
  expect_out "名前: normal の宛先" "/api/users/123" scenario_path normal
}

# bats test_tags=unit
@test "名前: error-500-then-200 の宛先" {
  expect_out "名前: error-500-then-200 の宛先" "/api/error-500-then-200" scenario_path error-500-then-200
}

# bats test_tags=unit
@test "名前: ratelimit-429 の宛先" {
  expect_out "名前: ratelimit-429 の宛先" "/api/ratelimit" scenario_path ratelimit-429
}

# bats test_tags=unit
@test "名前: slow-100 の宛先" {
  expect_out "名前: slow-100 の宛先" "/api/slow-100" scenario_path slow-100
}

# bats test_tags=unit
@test "名前: slow-5000 の宛先" {
  expect_out "名前: slow-5000 の宛先" "/api/slow-5000" scenario_path slow-5000
}

# bats test_tags=unit
@test "名前の一覧は5件だけ" {
  expect_out "名前の一覧は5件だけ" "$(printf '%s\n' error-500-then-200 normal ratelimit-429 slow-100 slow-5000)" scenario_names
}

# ---- 未定義と形式違反 ----

# bats test_tags=unit
@test "未定義の名前は終了コード2と一覧" {
  expect_err "未定義の名前は終了コード2と一覧" 2 "unknown scenario: no-such" scenario_path no-such
}

# bats test_tags=unit
@test "未定義の名前の標準エラーに定義済みの一覧" {
  expect_err "未定義の名前の標準エラーに定義済みの一覧" 2 "normal" scenario_path no-such
}

# bats test_tags=unit
@test "大文字は未定義扱い" {
  expect_rc "大文字は未定義扱い" 2 scenario_path Normal
}

# bats test_tags=unit
@test "空文字は未定義扱い" {
  expect_rc "空文字は未定義扱い" 2 scenario_path ""
}

# bats test_tags=unit
@test "アンダースコアは未定義扱い" {
  expect_rc "アンダースコアは未定義扱い" 2 scenario_path a_b
}

# bats test_tags=unit
@test "先頭ハイフンは未定義扱い" {
  expect_rc "先頭ハイフンは未定義扱い" 2 scenario_path -x
}

# bats test_tags=unit
@test "空白を含む名前は未定義扱い" {
  expect_rc "空白を含む名前は未定義扱い" 2 scenario_path "x y"
}

# bats test_tags=unit
@test "制御文字を含む名前は取り除いて表示" {
  # 制御文字は標準エラーへ出す前に取り除く。取り除かれていなければ、期待の文字列が一致しない。
  _esc=$(printf '\033')
  expect_err "制御文字を含む名前は取り除いて表示" 2 "unknown scenario: normal" scenario_path "nor${_esc}mal"
}

# ---- 同名の宛先の不一致 ----

# bats test_tags=unit
@test "同名で宛先が異なれば終了コード1" {
  _dir="$tmp_root/conflict"
  put_stub "$_dir" d1.json '{"name":"dup","request":{"method":"GET","urlPath":"/d1"},"response":{"status":200}}'
  put_stub "$_dir" d2.json '{"name":"dup","request":{"method":"GET","urlPath":"/d2"},"response":{"status":200}}'
  expect_rc "同名で宛先が異なれば終了コード1" 1 scenario_path dup "$_dir"
}

# bats test_tags=unit
@test "同名で宛先が異なれば静的検査も拒否" {
  _dir="$tmp_root/conflict"
  put_stub "$_dir" d1.json '{"name":"dup","request":{"method":"GET","urlPath":"/d1"},"response":{"status":200}}'
  put_stub "$_dir" d2.json '{"name":"dup","request":{"method":"GET","urlPath":"/d2"},"response":{"status":200}}'
  expect_rc "同名で宛先が異なれば静的検査も拒否" 1 scenario_check_static "$_dir"
}

# ---- 静的検査 ----

# bats test_tags=unit
@test "静的検査: 実マッピングが通る" {
  scenario_check_static wiremock-scenarios/mappings
}

# bats test_tags=unit
@test "静的検査: 正しい状態グループが通る" {
  _good="$tmp_root/good"
  make_valid_group "$_good"
  scenario_check_static "$_good"
}

# bats test_tags=unit
@test "正しい状態グループの宛先" {
  _good="$tmp_root/good"
  make_valid_group "$_good"
  expect_out "正しい状態グループの宛先" "/g" scenario_path g "$_good"
}

# bats test_tags=unit
@test "状態の網羅: Started が0件" {
  _none="$tmp_root/no-started"
  put_stub "$_none" done.json "{$G_DONE}"
  expect_static_reject "状態の網羅: Started が0件" "$_none"
}

# bats test_tags=unit
@test "状態の網羅: Started が2件" {
  _two="$tmp_root/two-started"
  make_valid_group "$_two"
  put_stub "$_two" start2.json "{$G_START}"
  expect_static_reject "状態の網羅: Started が2件" "$_two"
}

# bats test_tags=unit
@test "遷移の到達性: 遷移先が存在しない" {
  _unreach="$tmp_root/unreachable"
  put_stub "$_unreach" start.json '{"name":"g","scenarioName":"g","requiredScenarioState":"Started","newScenarioState":"Nowhere","request":{"method":"GET","urlPath":"/g"},"response":{"status":500}}'
  put_stub "$_unreach" done.json "{$G_DONE}"
  expect_static_reject "遷移の到達性: 遷移先が存在しない" "$_unreach"
}

# bats test_tags=unit
@test "宛先の一致: グループ内で urlPath が違う" {
  _dest="$tmp_root/dest-mismatch"
  put_stub "$_dest" start.json "{$G_START}"
  put_stub "$_dest" done.json '{"name":"g","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/other"},"response":{"status":200}}'
  expect_static_reject "宛先の一致: グループ内で urlPath が違う" "$_dest"
}

# bats test_tags=unit
@test "名前の一致: グループ内で name が違う" {
  _name="$tmp_root/name-mismatch"
  put_stub "$_name" start.json "{$G_START}"
  put_stub "$_name" done.json '{"name":"h","scenarioName":"g","requiredScenarioState":"Succeeded","request":{"method":"GET","urlPath":"/g"},"response":{"status":200}}'
  expect_static_reject "名前の一致: グループ内で name が違う" "$_name"
}

# bats test_tags=unit
@test "部分指定: scenarioName が無い状態スタブ" {
  _partial="$tmp_root/partial"
  put_stub "$_partial" p.json '{"name":"p","requiredScenarioState":"Started","request":{"method":"GET","urlPath":"/p"},"response":{"status":200}}'
  expect_static_reject "部分指定: scenarioName が無い状態スタブ" "$_partial"
}

# bats test_tags=unit
@test "パスの重複: グループの外で重複" {
  _dup="$tmp_root/path-dup"
  put_stub "$_dup" p1.json '{"name":"p1","request":{"method":"GET","urlPath":"/dup"},"response":{"status":200}}'
  put_stub "$_dup" p2.json '{"name":"p2","request":{"method":"GET","urlPath":"/dup"},"response":{"status":200}}'
  expect_static_reject "パスの重複: グループの外で重複" "$_dup"
}

# bats test_tags=unit
@test "名前の形式: 大文字とアンダースコア" {
  _format="$tmp_root/name-format"
  put_stub "$_format" f.json '{"name":"Bad_Name","request":{"method":"GET","urlPath":"/f"},"response":{"status":200}}'
  expect_static_reject "名前の形式: 大文字とアンダースコア" "$_format"
}

# ---- 状態遷移の2定義と urlPath の取り出し ----

# bats test_tags=unit
@test "error-500-then-200 の2定義が plan 4.2 どおりで一致する" {
  _m=wiremock-scenarios/mappings
  if [ ! -f "$_m/error-500-then-200-1.json" ] || [ ! -f "$_m/error-500-then-200-2.json" ]; then
    printf 'FAIL: 状態遷移の2ファイルが存在する\n' >&2
    return 1
  fi
  # shellcheck disable=SC2016 # 単一引用符の中の $a、$b は jq の変数であり、シェルで展開させない。
  if ! "$jq_bin" -e -s '
    def base(s): s.name == "error-500-then-200" and s.scenarioName == "error-500-then-200"
      and s.request.method == "GET" and s.request.urlPath == "/api/error-500-then-200"
      and s.response.headers["Content-Type"] == "application/json";
    .[0] as $a
    | .[1] as $b
    | base($a) and base($b)
      and $a.requiredScenarioState == "Started" and $a.newScenarioState == "Succeeded"
      and $a.response.status == 500 and $a.response.bodyFileName == "error-500.json"
      and $b.requiredScenarioState == "Succeeded" and ($b | has("newScenarioState") | not)
      and $b.response.status == 200 and $b.response.bodyFileName == "success.json"
  ' "$_m/error-500-then-200-1.json" "$_m/error-500-then-200-2.json" >/dev/null; then
    printf 'FAIL: 状態遷移の2ファイルが plan 4.2 どおり\n' >&2
    return 1
  fi
}

# 管理APIの mapping（JSON）から、name が一致する最初の mapping の urlPath を出す。
mapping_urlpath_by_name() { # JSON のファイル、name
  # shellcheck disable=SC2016 # 単一引用符の中の $m と $n は jq の変数であり、シェルで展開させない。
  "$jq_bin" -r --arg n "$2" '
    ([.mappings[] | select(.name == $n)] | first) as $m
    | if $m == null then "" else ($m.request.urlPath // error("urlPath が無い")) end
  ' "$1"
}

# bats test_tags=unit
@test "name から urlPath を引く: 無い name は空、urlPath の無い一致は失敗する" {
  _f="$tmp_root/lookup-mappings.json"
  printf '%s\n' '{"mappings":[{"name":"a","request":{"method":"GET","urlPath":"/a"}}]}' > "$_f"
  [ "$(mapping_urlpath_by_name "$_f" a)" = "/a" ] || return 1
  [ "$(mapping_urlpath_by_name "$_f" missing)" = "" ] || return 1
  printf '%s\n' '{"mappings":[{"name":"b","request":{}}]}' > "$_f.bad"
  if mapping_urlpath_by_name "$_f.bad" b >/dev/null 2>&1; then
    return 1
  fi
}

# ---- Docker を呼ばない、信号の宣言 ----

# bats test_tags=unit
@test "Docker を呼ばない" {
  # 入れ子の実行では、この検査を飛ばして再帰を防ぐ（M07_NESTED）。
  if [ -n "${M07_NESTED:-}" ]; then
    return 0
  fi
  _shim="$tmp_root/shim"
  _calls="$tmp_root/calls"
  mkdir -p "$_shim"
  printf '#!/bin/sh\necho %s >>"%s"\nexit 99\n' docker "$_calls" >"$_shim/docker"
  chmod +x "$_shim/docker"
  # 偽の docker を PATH の先頭に置いて、この検査の全件を入れ子で走らせる（unit は docker を呼ばないこと）。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/resolve-tool.sh"
  resolve_tool bats 's/^Bats //p' --version || return 1
  _rc=0
  M07_NESTED=1 PATH="$_shim:$PATH" "$RESOLVED_PATH" --filter-tags unit "$BATS_TEST_FILENAME" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  [ ! -e "$_calls" ]
}

# bats test_tags=unit
@test "m07_signal_exit_codes: INT は130、TERM は143" {
  # 信号の実機の検査は smoke にある。取り違えは unit でも気付けるように、宣言を見ておく。
  grep -Fq "trap 'exit 130' INT" "$SELF" && grep -Fq "trap 'exit 143' TERM" "$SELF" \
    && grep -Fq "smoke_case_signal INT 130" "$SELF" && grep -Fq "smoke_case_signal TERM 143" "$SELF"
}
